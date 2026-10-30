-- SmartHome OS installer: bundled-v14
-- Flat-root layout: lib_*, clients_*, apps_*, configs_*.
-- Upload this ONE file to Pastebin. All role files are included below.
-- Usage: inst server|io|monitor [--startup]
-- User apps: inst app NAME [--ref BRANCH_OR_COMMIT] (GitHub)
-- Alternatives: inst app NAME PASTE_ID   or   inst app NAME --file PATH
-- OS/client installation is offline. Apps are fetched only on request.
local sources = {
    ["lib_storage.lua"] = [=[-- Lua 5.1 / ComputerCraft 1.5. Only plain, serializable data belongs here.
local storage = {}

local function readTable(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local file = fs.open(path, "r")
    if not file then return nil end
    local contents = file.readAll()
    file.close()
    local ok, value = pcall(textutils.unserialize, contents)
    if ok and type(value) == "table" then return value end
end

function storage.load(path, validate)
    for _, candidate in ipairs({path, path .. ".tmp", path .. ".bak"}) do
        local value = readTable(candidate)
        if value and (not validate or validate(value)) then return value, candidate end
    end
end

function storage.save(path, value)
    local ok, err = pcall(function()
        local contents = textutils.serialize(value)
        -- fs.getDir was only added in CC 1.63; Tekkit Lite uses older CC.
        local dir = path:match("^(.*)/[^/]+$") or ""
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local file = assert(fs.open(path .. ".tmp", "w"), "Cannot write " .. path)
        file.write(contents)
        file.close()
        if fs.exists(path) then
            if readTable(path) then
                if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
                fs.move(path, path .. ".bak")
            else
                -- A corrupt primary must not replace a good backup.
                fs.delete(path)
            end
        end
        fs.move(path .. ".tmp", path)
    end)
    return ok, err
end

function storage.config(path, defaults)
    local value = storage.load(path)
    if value then
        for key, default in pairs(defaults) do
            if value[key] == nil then value[key] = default end
        end
        return value
    end
    for _, suffix in ipairs({"", ".tmp", ".bak"}) do
        assert(not fs.exists(path .. suffix), "Unreadable config: " .. path .. suffix)
    end
    local ok, err = storage.save(path, defaults)
    assert(ok, err)
    return defaults
end

return storage
]=],
    ["lib_network.lua"] = [=[-- All wire packets are serialized strings, including on old CC modems.
local Network = {}
local sides = {"top", "bottom", "left", "right", "front", "back"}
local protocol = "SmartHomeOS/1"

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= low and value <= high
end

function Network.new(config, isServer, logger)
    local log = logger or print
    assert(type(config.networkId) == "string" and #config.networkId > 0,
        "Set networkId in configs_network.txt")
    assert(integer(config.channel, 1, 65532), "Invalid network channel")
    assert(config.serverId == nil or integer(config.serverId, 0, 2147483647),
        "serverId must be a computer ID")
    local net = {id = os.getComputerID(), config = config, isServer = isServer}
    -- Destination IDs still disambiguate computers if reply channels collide.
    net.replyChannel = 1000 + (net.id % 40000)
    if net.replyChannel == config.channel then net.replyChannel = 41001 end
    net.listenChannel = isServer and config.channel or net.replyChannel

    function net.ensureModem()
        if net.modem then return true end
        for _, side in ipairs(sides) do
            if peripheral.getType(side) == "modem" then
                local modem = peripheral.wrap(side)
                -- isWireless is absent in some early versions; channels are required.
                if modem and modem.transmit and modem.open
                    and (not modem.isWireless or modem.isWireless()) then
                    local ok = pcall(modem.open, net.listenChannel)
                    if ok then
                        net.modem, net.side = modem, side
                        log("Wireless modem: " .. side .. ", channel " .. net.listenChannel)
                        return true
                    end
                end
            end
        end
        return false
    end

    function net.peripheralChanged(side)
        if side == net.side then net.modem, net.side = nil, nil end
        return net.ensureModem()
    end

    function net.send(channel, targetId, message)
        if not net.ensureModem() then return false end
        local packet = {}
        for key, value in pairs(message) do packet[key] = value end
        packet.protocol, packet.networkId = protocol, config.networkId
        packet.sender, packet.recipient = net.id, targetId
        local ok = pcall(net.modem.transmit, channel, net.listenChannel,
            textutils.serialize(packet))
        if not ok then net.modem, net.side = nil, nil end
        return ok
    end

    function net.toServer(message)
        return net.send(config.channel, config.serverId, message)
    end

    function net.toClient(client, message)
        return net.send(client.channel, client.computerId, message)
    end

    function net.receive(side, channel, replyChannel, raw)
        if side ~= net.side or channel ~= net.listenChannel then return nil end
        if not integer(replyChannel, 1, 65532) or type(raw) ~= "string"
            or #raw > 65536 then return nil end
        local ok, packet = pcall(textutils.unserialize, raw)
        if not ok or type(packet) ~= "table" or packet.protocol ~= protocol
            or packet.networkId ~= config.networkId
            or not integer(packet.sender, 0, 2147483647)
            or packet.sender == net.id or type(packet.type) ~= "string" then return nil end
        if packet.recipient ~= nil and packet.recipient ~= net.id then return nil end
        if not isServer then
            if packet.recipient ~= net.id or replyChannel ~= config.channel then return nil end
            if config.serverId and packet.sender ~= config.serverId then return nil end
        else
            local expected = 1000 + (packet.sender % 40000)
            if expected == config.channel then expected = 41001 end
            if replyChannel ~= expected then return nil end
        end
        return packet
    end

    return net
end

Network.sides = sides
Network.integer = integer
return Network
]=],
    ["lib_console.lua"] = [=[-- Local CC 1.5 terminal: log output above an independently edited bottom line.
-- No read(), term.redirect(), window API, or peripheral drawing is required.
local Console = {}
local codes = {enter = 28, numPadEnter = 156, backspace = 14, delete = 211,
    left = 203, right = 205, home = 199, ["end"] = 207, up = 200, down = 208}
for name, fallback in pairs(codes) do codes[name] = keys and keys[name] or fallback end

function Console.new(screen)
    local console = {lines = {}, history = {}, text = "", cursor = 0, offset = 0}
    local cache, previousWidth, previousHeight = {}, nil, nil
    local function clean(value)
        return tostring(value):gsub("\r", ""):gsub("\t", "    "):gsub("[%z\1-\8\11\12\14-\31\127]", " ")
    end
    function console.redraw(force)
        local width, height = screen.getSize()
        assert(width >= 3 and height >= 2, "Console needs at least 3x2 characters")
        if width ~= previousWidth or height ~= previousHeight then
            force, previousWidth, previousHeight = true, width, height
        end
        if screen.setCursorBlink then screen.setCursorBlink(false) end
        local setFG, setBG = screen.setTextColor or screen.setTextColour, screen.setBackgroundColor or screen.setBackgroundColour
        if setFG then setFG(1) end
        if setBG then setBG(32768) end
        local rows = {}
        for _, line in ipairs(console.lines) do
            if line == "" then rows[#rows + 1] = "" end
            for first = 1, #line, width do rows[#rows + 1] = line:sub(first, first + width - 1) end
        end
        local function paint(y, line)
            line = line:sub(1, width)
            line = line .. string.rep(" ", width - #line)
            if force or cache[y] ~= line then
                screen.setCursorPos(1, y); screen.write(line); cache[y] = line
            end
        end
        for y = 1, height - 1 do paint(y, rows[#rows - height + 1 + y] or "") end
        local available = width - 2
        if console.cursor < console.offset then console.offset = console.cursor end
        if console.cursor >= console.offset + available then console.offset = console.cursor - available + 1 end
        console.offset = math.max(0, math.min(console.offset, math.max(0, #console.text - available + 1)))
        paint(height, "> " .. console.text:sub(console.offset + 1, console.offset + available))
        screen.setCursorPos(3 + console.cursor - console.offset, height)
        if screen.setCursorBlink then screen.setCursorBlink(true) end
    end
    function console.log(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = clean(select(index, ...)) end
        for line in (table.concat(parts, " ") .. "\n"):gmatch("(.-)\n") do
            console.lines[#console.lines + 1] = line
        end
        while #console.lines > 200 do table.remove(console.lines, 1) end
        console.redraw()
    end
    function console.clear()
        console.lines, cache = {}, {}
        console.redraw(true)
    end
    local function changed()
        console.historyIndex, console.draft = nil, nil
    end
    function console.handle(event, value)
        if event == "char" or event == "paste" then
            if type(value) ~= "string" then return end
            value = clean(value):gsub("\n", " "):sub(1, math.max(0, 4096 - #console.text))
            console.text = console.text:sub(1, console.cursor) .. value .. console.text:sub(console.cursor + 1)
            console.cursor = console.cursor + #value
            changed()
        elseif event == "term_resize" then console.redraw(true); return
        elseif event == "key" then
            if value == codes.enter or value == codes.numPadEnter then
                local command = console.text
                if command:match("%S") and console.history[#console.history] ~= command then
                    console.history[#console.history + 1] = command
                    if #console.history > 50 then table.remove(console.history, 1) end
                end
                console.text, console.cursor, console.offset = "", 0, 0
                changed()
                console.log("> " .. command)
                return command
            elseif value == codes.left then console.cursor = math.max(0, console.cursor - 1)
            elseif value == codes.right then console.cursor = math.min(#console.text, console.cursor + 1)
            elseif value == codes.home then console.cursor = 0
            elseif value == codes["end"] then console.cursor = #console.text
            elseif value == codes.backspace then
                if console.cursor > 0 then
                    console.text = console.text:sub(1, console.cursor - 1) .. console.text:sub(console.cursor + 1)
                    console.cursor = console.cursor - 1; changed()
                end
            elseif value == codes.delete then
                console.text = console.text:sub(1, console.cursor) .. console.text:sub(console.cursor + 2)
                changed()
            elseif value == codes.up then
                if #console.history > 0 then
                    if not console.historyIndex then console.draft = console.text end
                    console.historyIndex = math.max(1, (console.historyIndex or (#console.history + 1)) - 1)
                    console.text = console.history[console.historyIndex]; console.cursor = #console.text
                end
            elseif value == codes.down then
                if console.historyIndex then
                    console.historyIndex = console.historyIndex + 1
                    if console.historyIndex > #console.history then console.text = console.draft or ""; changed()
                    else console.text = console.history[console.historyIndex] end
                    console.cursor = #console.text
                end
            else return end
        else return end
        console.redraw()
    end
    function console.finish()
        local width, height = screen.getSize()
        screen.setCursorPos(1, height); screen.write(string.rep(" ", width))
        screen.setCursorPos(1, height)
        if screen.setCursorBlink then screen.setCursorBlink(false) end
    end
    console.redraw(true)
    return console
end
return Console
]=],
    ["lib_gui.lua"] = [=[-- CC 1.5 colour surfaces. Uses write/setTextColor/setBackgroundColor, never blit.
local Gui = {}
local digits = "0123456789abcdef"
local names = {"White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray",
    "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
function Gui.colourName(colour)
    for index = 0, 15 do if colour == 2 ^ index then return names[index + 1] end end
    return "Unknown"
end
function Gui.contrast(colour)
    return (colour == 128 or colour == 1024 or colour == 2048 or colour == 4096
        or colour == 8192 or colour == 16384 or colour == 32768) and 1 or 32768
end
function Gui.hit(hit, x, y)
    return x >= hit.x1 and x <= hit.x2 and y >= (hit.y1 or hit.y) and y <= (hit.y2 or hit.y)
end
-- App widgets return text plus clipped colour rectangles, sharing geometry with hits.
function Gui.content(width, height)
    local ui = {lines = {styles = {}}, hits = {}}
    ui.lines.hits = ui.hits
    for y = 1, height do ui.lines[y] = string.rep(" ", width) end
    function ui.style(x, y, w, h, fg, bg)
        ui.lines.styles[#ui.lines.styles + 1] = {x = x, y = y, width = w, height = h, fg = fg, bg = bg}
    end
    function ui.text(y, text, centred)
        if y < 1 or y > height then return end
        text = tostring(text):sub(1, width)
        local left = centred and math.floor((width - #text) / 2) or 0
        ui.lines[y] = string.rep(" ", left) .. text .. string.rep(" ", width - left - #text)
    end
    function ui.heading(text, accent)
        ui.text(1, text)
        ui.style(1, 1, width, 1, Gui.contrast(accent or 128), accent or 128)
    end
    function ui.button(y, label, action, x1, x2, enabled, bg, fg, value)
        x1, x2 = x1 or 1, x2 or width
        label = label:sub(1, x2 - x1 + 1)
        local left = math.floor((x2 - x1 + 1 - #label) / 2)
        local text = string.rep(" ", left) .. label .. string.rep(" ", x2 - x1 + 1 - left - #label)
        ui.lines[y] = ui.lines[y]:sub(1, x1 - 1) .. text .. ui.lines[y]:sub(x2 + 1)
        bg = enabled == false and 256 or bg or 128
        ui.style(x1, y, x2 - x1 + 1, 1, enabled == false and 128 or fg or Gui.contrast(bg), bg)
        ui.hits[#ui.hits + 1] = {x1 = x1, x2 = x2, y = y, action = action, value = value, enabled = enabled}
    end
    return ui
end
function Gui.menu(width, height, title, items, page, back, accent)
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    local slots = #items <= height - 2 and height - 2 or height - 3
    local pages = math.max(1, math.ceil(#items / slots))
    page = math.max(1, math.min(page or 1, pages))
    ui.heading(title .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), accent)
    local gap = pages == 1 and height >= #items * 2 + 2 and 2 or 1
    local first = height >= #items * gap + 3 and pages == 1 and 3 or 2
    local inset = width >= 18 and math.max(2, math.floor((width - 32) / 2)) or 0
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then ui.button(first + (row - 1) * gap, item.label, item.action, 1 + inset, width - inset, item.enabled) end
    end
    if pages > 1 then
        local half = math.floor(width / 2)
        ui.button(height - 1, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 1, "Next >", "next", half + 1, width, page < pages)
    end
    ui.button(height, "Back", back)
    return ui.lines, ui.hits, page, pages
end
function Gui.palette(width, height, current, title)
    local ui = Gui.content(width, height)
    ui.heading(title or "UI colour", 128)
    local cellWidth, cellHeight = math.floor((width - 3) / 4), math.min(2, math.floor((height - 2) / 4))
    local short = {"White", "Orange", "Mag.", "Sky", "Yellow", "Lime", "Pink", "Gray", "L.gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
    for index = 0, 15 do
        local x, y = 1 + index % 4 * (cellWidth + 1), 2 + math.floor(index / 4) * cellHeight
        local colour = 2 ^ index
        ui.style(x, y, cellWidth, cellHeight, Gui.contrast(colour), colour)
        local label = colour == current and "*" or cellWidth >= 6 and short[index + 1] or ""
        local left = math.floor((cellWidth - #label) / 2)
        local row = ui.lines[y]
        ui.lines[y] = row:sub(1, x - 1) .. string.rep(" ", left) .. label
            .. string.rep(" ", cellWidth - left - #label) .. row:sub(x + cellWidth)
        ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + cellWidth - 1, y = y, y1 = y,
            y2 = y + cellHeight - 1, action = "colour", value = colour}
    end
    ui.button(height, "Back", "cancel")
    return ui.lines, ui.hits
end
function Gui.code(colour, fallback)
    for index = 0, 15 do if colour == 2 ^ index then return digits:sub(index + 1, index + 1) end end
    return fallback
end
function Gui.pack(row)
    local runs, x = {}, 1
    while x <= #row do
        local last = x
        while last < #row and last - x < 254 and row:sub(last + 1, last + 1) == row:sub(x, x) do last = last + 1 end
        runs[#runs + 1] = string.format("%02x", last - x + 1) .. row:sub(x, x)
        x = last + 1
    end
    return table.concat(runs)
end
function Gui.unpack(encoded, width)
    if type(encoded) ~= "string" or #encoded % 3 ~= 0 then return nil end
    local parts, length = {}, 0
    for x = 1, #encoded, 3 do
        local count, colour = tonumber(encoded:sub(x, x + 1), 16), encoded:sub(x + 2, x + 2)
        if not count or count < 1 or not colour:match("^[0-9a-f]$") then return nil end
        length = length + count
        if length > width then return nil end
        parts[#parts + 1] = string.rep(colour, count)
    end
    if length ~= width then return nil end
    return table.concat(parts)
end
function Gui.new(width, height, foreground, background)
    local surface = {lines = {}, foreground = {}, background = {}}
    for y = 1, height do
        surface.lines[y] = string.rep(" ", width)
        surface.foreground[y] = string.rep(Gui.code(foreground, "0"), width)
        surface.background[y] = string.rep(Gui.code(background, "f"), width)
    end
    local function replace(row, x, value) return row:sub(1, x - 1) .. value .. row:sub(x + #value) end
    function surface.style(x, y, w, h, fg, bg)
        local first, last = math.max(1, x), math.min(width, x + w - 1)
        if last < first then return end
        for row = math.max(1, y), math.min(height, y + h - 1) do
            local f, b = Gui.code(fg), Gui.code(bg)
            if f then surface.foreground[row] = replace(surface.foreground[row], first, string.rep(f, last - first + 1)) end
            if b then surface.background[row] = replace(surface.background[row], first, string.rep(b, last - first + 1)) end
        end
    end
    function surface.write(x, y, value, fg, bg, limit)
        if y < 1 or y > height then return end
        local text = tostring(value or ""):sub(1, limit or width)
        local first, last = math.max(1, x), math.min(width, x + #text - 1)
        if last < first then return end
        text = text:sub(first - x + 1, last - x + 1)
        surface.lines[y] = replace(surface.lines[y], first, text)
        surface.style(first, y, #text, 1, fg, bg)
    end
    function surface.fill(x, y, w, h, fg, bg)
        for row = math.max(1, y), math.min(height, y + h - 1) do surface.write(x, row, string.rep(" ", w), fg, bg) end
    end
    function surface.frame()
        local fg, bg = {}, {}
        for y = 1, height do fg[y], bg[y] = Gui.pack(surface.foreground[y]), Gui.pack(surface.background[y]) end
        return surface.lines, fg, bg
    end
    return surface
end
function Gui.drawRow(screen, y, text, fg, bg, colour, paint)
    local setFG, setBG = screen.setTextColor or screen.setTextColour, screen.setBackgroundColor or screen.setBackgroundColour
    paint = paint or {}
    local x = 1
    screen.setCursorPos(1, y)
    while x <= #text do
        local last, f, b = x, fg:sub(x, x), bg:sub(x, x)
        while last < #text and fg:sub(last + 1, last + 1) == f and bg:sub(last + 1, last + 1) == b do last = last + 1 end
        local foreground, background = 2 ^ tonumber(f, 16), 2 ^ tonumber(b, 16)
        if not colour then
            background = (b == "0" or b == "8") and 1 or 32768
            foreground = background == 1 and 32768 or 1
        end
        if setFG and paint.fg ~= foreground then setFG(foreground); paint.fg = foreground end
        if setBG and paint.bg ~= background then setBG(background); paint.bg = background end
        screen.write(text:sub(x, last))
        x = last + 1
    end
end
return Gui
]=],
    ["lib_settings.lua"] = [=[-- Built-in OS settings window. This is system UI, not an installed user app.
local Settings = {title = "OS settings", minWidth = 12, minHeight = 6, preferredWidth = 28, preferredHeight = 10}
local function build(width, height, api)
    local ui = api.ui.content(width, height)
    local settings = api.getOSSettings()
    ui.style(1, 1, width, height, 1, 32768)
    ui.heading("Appearance", 128)
    local items = {{label = "Background", action = "background", colour = settings.backgroundColour},
        {label = width >= 13 and "Window border" or "Borders", action = "windowBorder", colour = settings.windowBorderColour},
        {label = "Taskbar", action = "taskbar", colour = settings.taskbarColour}}
    for index, item in ipairs(items) do
        local label = width >= 24 and item.label .. ": " .. api.ui.colourName(item.colour) or item.label
        ui.button(3 + (index - 1) * (height >= 9 and 2 or 1), label, item.action, nil, nil, true, item.colour)
    end
    ui.text(height >= 9 and 9 or height, width >= 24 and "Applies to all monitors" or "All monitors", true)
    return ui.lines, ui.hits
end
function Settings.render(width, height, state, api)
    return (build(width, height, api))
end
function Settings.handleTouch(x, y, width, height, state, api, context)
    local _, hits = build(width, height, api)
    for _, hit in ipairs(hits) do
        if api.ui.hit(hit, x, y) then
            return api.pickColour(context.windowId, hit.action)
        end
    end
    return false
end
return Settings
]=],
    ["lib_io_picker.lua"] = [=[-- Reusable, server-rendered IO selector. No peripheral or network calls here.
local Picker = {}
local sideNames = {"top", "bottom", "left", "right", "front", "back"}
local colorNames = {"white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}

function Picker.new(key, direction, selected)
    local chosen = {}
    for k, v in pairs(selected or {}) do chosen[k] = v end
    return {key = key, direction = direction, stage = 1, page = 1, chosen = chosen}
end

local function choices(dialog, clients)
    local list = {}
    if dialog.stage == 1 then
        local found = false
        for _, client in ipairs(clients) do
            list[#list + 1] = {label = client.id .. (client.online and " +" or " -"), value = client.id}
            if client.id == dialog.chosen.clientId then found = true end
        end
        if dialog.chosen.clientId and not found then
            list[#list + 1] = {label = dialog.chosen.clientId .. " -", value = dialog.chosen.clientId}
        end
    elseif dialog.stage == 2 then
        local available
        for _, client in ipairs(clients) do
            if client.id == dialog.chosen.clientId then available = client.sides; break end
        end
        for _, side in ipairs(available or sideNames) do list[#list + 1] = {label = side, value = side} end
    elseif dialog.stage == 3 then
        list[1] = {label = "Digital", value = false}
        for i, name in ipairs(colorNames) do list[#list + 1] = {label = name, value = 2 ^ (i - 1), colour = 2 ^ (i - 1)} end
    end
    return list
end

local function colorName(value)
    if not value then return "Digital" end
    for i, name in ipairs(colorNames) do if value == 2 ^ (i - 1) then return name end end
    return "Invalid color"
end

function Picker.render(dialog, width, height, clients)
    local lines, hits = {styles = {}}, {}
    local half = math.floor(width / 2)
    local function text(row, value) lines[row] = tostring(value):sub(1, width) end
    local function button(row, x1, x2, label, action, value, enabled)
        local line = lines[row] or string.rep(" ", width)
        label = label:sub(1, x2 - x1 + 1)
        local padding = math.floor((x2 - x1 + 1 - #label) / 2)
        label = string.rep(" ", padding) .. label .. string.rep(" ", x2 - x1 + 1 - padding - #label)
        lines[row] = line:sub(1, x1 - 1) .. label .. line:sub(x2 + 1)
        hits[#hits + 1] = {y = row, x1 = x1, x2 = x2, action = action, value = value, enabled = enabled}
        lines.styles[#lines.styles + 1] = {x = x1, y = row, width = x2 - x1 + 1, height = 1,
            fg = enabled == false and 128 or action == "cancel" and 1 or 32768,
            bg = action == "cancel" and 16384 or action == "use" and 32 or action == "select" and (row % 2 == 0 and 1 or 256) or 256}
    end
    for row = 1, height do lines[row] = string.rep(" ", width) end
    if dialog.stage == 4 then
        text(1, "Use this " .. dialog.direction .. "?")
        text(2, dialog.chosen.clientId or "No IO client")
        text(3, "Side: " .. (dialog.chosen.side or "?"))
        text(4, colorName(dialog.chosen.color))
        if dialog.error then text(4, dialog.error) end
        button(height - 1, 1, width, "< Back", "back")
        button(height, 1, half, "Use", "use")
        button(height, half + 1, width, "Cancel", "cancel")
    else
        local titles = {"Select IO", "Select side", "Select wire"}
        local list = choices(dialog, clients)
        local slots = #list <= height - 2 and height - 2 or math.max(1, height - 3)
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        text(1, titles[dialog.stage] .. (pages > 1 and (" " .. dialog.page .. "/" .. pages) or ""))
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then
                button(row + 1, 1, width, (item.colour and "  " or "") .. item.label, "select", item.value)
                if item.colour then lines.styles[#lines.styles + 1] = {x = 1, y = row + 1, width = 2, height = 1, bg = item.colour} end
            end
        end
        if #list == 0 then text(2, "No IO clients") end
        if pages > 1 then
            button(height - 1, 1, half, "< Prev", "prev", nil, dialog.page > 1)
            button(height - 1, half + 1, width, "Next >", "next", pages, dialog.page < pages)
        end
        button(height, 1, half, "Back", "back")
        button(height, half + 1, width, "Cancel", "cancel")
    end
    dialog.hits = hits
    lines.styles[#lines.styles + 1] = {x = 1, y = 1, width = width, height = 1, fg = 1, bg = 2048}
    return lines
end

function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do
        if hit.y == y and x >= hit.x1 and x <= hit.x2 then
            if hit.enabled == false then return end
            dialog.error = nil
            if hit.action == "cancel" then return "cancel"
            elseif hit.action == "use" then return "selected", dialog.chosen
            elseif hit.action == "prev" then dialog.page = math.max(1, dialog.page - 1)
            elseif hit.action == "next" then dialog.page = math.min(hit.value, dialog.page + 1)
            elseif hit.action == "back" then
                if dialog.stage == 1 then return "cancel" end
                dialog.stage, dialog.page = dialog.stage - 1, 1
            elseif hit.action == "select" then
                if dialog.stage == 1 then dialog.chosen.clientId = hit.value
                elseif dialog.stage == 2 then dialog.chosen.side = hit.value
                else dialog.chosen.color = hit.value or nil end
                dialog.stage, dialog.page = dialog.stage + 1, 1
            end
            return
        end
    end
end

return Picker
]=],
    ["lib_desktop.lua"] = [=[-- Character-based desktop geometry and widgets. No peripheral calls here.
local Desktop = {}
local Gui = dofile("lib_gui.lua")
local function clamp(value, low, high) return math.max(low, math.min(value, high)) end

function Desktop.area(monitor)
    return {x = 1, y = 1, width = monitor.width, height = monitor.height - 1}
end

function Desktop.controls(win)
    local x = win.x + win.width - 9
    return {{x1 = x, x2 = x + 2, action = "minimize", label = " - "},
        {x1 = x + 3, x2 = x + 5, action = "layout", label = " + "},
        {x1 = x + 6, x2 = x + 8, action = "close", label = " X "}}
end

function Desktop.bounds(app, monitor)
    local area = Desktop.area(monitor)
    return math.max(10, (app.minWidth or 8) + 2), (app.minHeight or 2) + 2,
        math.min(area.width, app.maxWidth and app.maxWidth + 2 or area.width),
        math.min(area.height, app.maxHeight and app.maxHeight + 2 or area.height)
end

function Desktop.fits(rect, app, monitor)
    local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
    return rect and rect.width >= minW and rect.height >= minH and rect.width <= maxW
        and rect.height <= maxH and rect.x >= 1 and rect.y >= 1
        and rect.x + rect.width - 1 <= monitor.width
        and rect.y + rect.height - 1 < monitor.height
end

function Desktop.relative(rect, monitor)
    local area = Desktop.area(monitor)
    return {x = (rect.x - 1) / area.width, y = (rect.y - 1) / area.height,
        width = rect.width / area.width, height = rect.height / area.height}
end

function Desktop.free(rect, relative, app, monitor)
    local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
    if maxW < minW or maxH < minH then return nil end
    local area = Desktop.area(monitor)
    local width, height, x, y
    if relative then
        width, height = math.floor(relative.width * area.width + 0.5), math.floor(relative.height * area.height + 0.5)
        x, y = 1 + math.floor(relative.x * area.width + 0.5), 1 + math.floor(relative.y * area.height + 0.5)
    else
        width, height = tonumber(rect.width) or (app.preferredWidth or 30) + 2,
            tonumber(rect.height) or (app.preferredHeight or 10) + 2
        x, y = tonumber(rect.x) or 1, tonumber(rect.y) or 1
    end
    width, height = clamp(math.floor(width), minW, maxW), clamp(math.floor(height), minH, maxH)
    return {x = clamp(math.floor(x), 1, area.width - width + 1),
        y = clamp(math.floor(y), 1, area.height - height + 1), width = width, height = height}
end

local grids = {{1, 1}, {2, 1}, {1, 2}, {2, 2}, {3, 1}, {1, 3}, {3, 2}, {2, 3}, {3, 3}}
local legacyGrids = {maximize = {1, 1, 1, 1}, left = {2, 1, 1, 1}, right = {2, 1, 2, 1},
    top = {1, 2, 1, 1}, bottom = {1, 2, 1, 2}, top_left = {2, 2, 1, 1}, top_right = {2, 2, 2, 1},
    bottom_left = {2, 2, 1, 2}, bottom_right = {2, 2, 2, 2}}
function Desktop.gridMode(columns, rows, column, row)
    for mode, grid in pairs(legacyGrids) do
        if grid[1] == columns and grid[2] == rows and grid[3] == column and grid[4] == row then return mode end
    end
    return "grid_" .. columns .. "x" .. rows .. "_" .. column .. "_" .. row
end
function Desktop.gridForMode(mode)
    local grid = legacyGrids[mode]
    if grid then return grid[1] .. "x" .. grid[2] end
    if type(mode) == "string" then return mode:match("^grid_([1-3]x[1-3])_[1-3]_[1-3]$") end
end
local function gridSize(name)
    if type(name) ~= "string" then return end
    local columns, rows = name:match("^([1-3])x([1-3])$")
    return tonumber(columns), tonumber(rows)
end
function Desktop.zone(mode, monitor)
    local area = Desktop.area(monitor)
    local grid = legacyGrids[mode]
    local columns, rows, column, row
    if grid then columns, rows, column, row = unpack(grid)
    elseif type(mode) == "string" then
        columns, rows, column, row = mode:match("^grid_([1-3])x([1-3])_([1-3])_([1-3])$")
        columns, rows, column, row = tonumber(columns), tonumber(rows), tonumber(column), tonumber(row)
    end
    if not columns or column > columns or row > rows then return end
    local left, top = math.floor((column - 1) * area.width / columns), math.floor((row - 1) * area.height / rows)
    return {x = left + 1, y = top + 1, width = math.floor(column * area.width / columns) - left,
        height = math.floor(row * area.height / rows) - top}
end

function Desktop.layoutOptions(win, app, monitor, selectedGrid)
    local options = {}
    local columns, rows = gridSize(selectedGrid)
    if columns then
        for row = 1, rows do for column = 1, columns do
            local mode = Desktop.gridMode(columns, rows, column, row)
            options[#options + 1] = {label = "Position " .. ((row - 1) * columns + column), value = mode,
                enabled = Desktop.fits(Desktop.zone(mode, monitor), app, monitor)}
        end end
        options[#options + 1] = {label = "Back", value = "back", enabled = true}
    else
        for _, grid in ipairs(grids) do
            local enabled = false
            for row = 1, grid[2] do for column = 1, grid[1] do
                enabled = enabled or Desktop.fits(Desktop.zone(Desktop.gridMode(grid[1], grid[2], column, row), monitor), app, monitor)
            end end
            local name = grid[1] .. "x" .. grid[2]
            options[#options + 1] = {label = name, value = "choose_" .. name, enabled = enabled}
        end
        options[#options + 1] = {label = "Restore", value = "restore", enabled = win.layout ~= nil and win.layout ~= "normal"}
        options[#options + 1] = {label = "Resize", value = "custom", enabled = true}
        options[#options + 1] = {label = "Move", value = "move", enabled = true}
    end
    options[#options + 1] = {label = "Cancel", value = "cancel", enabled = true}
    return options
end

function Desktop.moveArrows(rect, monitor)
    local hits, area = {}, Desktop.area(monitor)
    local middleX, middleY = rect.x + math.floor((rect.width - 1) / 2), rect.y + math.floor(rect.height / 2)
    local function add(x, y, label, dx, dy)
        hits[#hits + 1] = {x1 = x, x2 = x + 2, y = y, label = label, dx = dx, dy = dy}
    end
    if rect.x > 1 then add(rect.x, middleY, " < ", -1, 0) end
    if rect.x + rect.width - 1 < area.width then add(rect.x + rect.width - 3, middleY, " > ", 1, 0) end
    if rect.y > 1 then add(middleX - 1, rect.y, " ^ ", 0, -1) end
    if rect.y + rect.height - 1 < area.height then add(middleX - 1, rect.y + rect.height - 1, " v ", 0, 1) end
    return hits
end

-- First choose a grid; only the second screen places the window in a pane.
function Desktop.layoutPicker(win, app, monitor, page, title, selectedGrid)
    local area, options = Desktop.area(monitor), Desktop.layoutOptions(win, app, monitor, selectedGrid)
    local gridColumns, gridRows = gridSize(selectedGrid)
    if (area.height < 10 and not gridColumns) or (gridColumns and area.height < gridRows * 2 + 3) then
        return Desktop.menu(monitor, title or (gridColumns and selectedGrid .. " position" or "Layout"), options, page,
            {x = win.x, y = win.y + 1})
    end
    local width = math.min(gridColumns and 35 or 43, area.width)
    local columns = width >= 40 and 3 or width >= 27 and 2 or 1
    local height = math.min(area.height, gridColumns and math.max(9, gridRows * 3 + 4) or 3 + math.ceil(#grids / columns) * 6)
    local rows = math.max(1, math.floor((height - 3) / 6))
    if rows * columns < #grids then rows = math.max(1, math.floor((height - 4) / 6)) end
    local perPage, pages = rows * columns, gridColumns and 1 or math.ceil(#grids / (rows * columns))
    page = clamp(page or 1, 1, pages)
    local rect = {x = clamp(win.x + win.width - width, 1, area.width - width + 1),
        y = clamp(win.y + 1, 1, area.height - height + 1), width = width, height = height}
    local ui, byMode = Gui.content(width, height), {}
    ui.style(1, 1, width, height, 1, 32768)
    for _, item in ipairs(options) do byMode[item.value] = item end
    ui.heading((title or (gridColumns and selectedGrid .. " - position" or "Layout"))
        .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), 128)
    local function hit(x, y, w, h, item)
        ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + w - 1, y = y, y1 = y, y2 = y + h - 1, action = "item", item = item}
    end
    local function pane(x, y, w, h, mode, label)
        local item = byMode[mode]
        local bg = item.enabled and (win.layout == mode and 2048 or 8) or 128
        ui.style(x, y, w, h, Gui.contrast(bg), bg)
        local textY = y + math.floor((h - 1) / 2)
        local textX = x + math.floor((w - #label) / 2)
        local line = ui.lines[textY]
        ui.lines[textY] = line:sub(1, textX - 1) .. label .. line:sub(textX + #label)
        hit(x, y, w, h, item)
    end
    if gridColumns then
        local diagramWidth, diagramHeight = width - 2, height - 4
        local usableWidth, usableHeight = diagramWidth - gridColumns + 1, diagramHeight - gridRows + 1
        for row = 1, gridRows do for column = 1, gridColumns do
            local x = 2 + math.floor((column - 1) * usableWidth / gridColumns) + column - 1
            local y = 3 + math.floor((row - 1) * usableHeight / gridRows) + row - 1
            local w = math.floor(column * usableWidth / gridColumns) - math.floor((column - 1) * usableWidth / gridColumns)
            local h = math.floor(row * usableHeight / gridRows) - math.floor((row - 1) * usableHeight / gridRows)
            pane(x, y, w, h, Desktop.gridMode(gridColumns, gridRows, column, row), tostring((row - 1) * gridColumns + column))
        end end
    else
        local cardWidth = math.floor((width - columns - 1) / columns)
        for slot = 1, perPage do
            local grid = grids[(page - 1) * perPage + slot]
            if grid then
                local x, y = 2 + (slot - 1) % columns * (cardWidth + 1), 2 + math.floor((slot - 1) / columns) * 6
                local name = grid[1] .. "x" .. grid[2]
                local item = byMode["choose_" .. name]
                local labelX = x + math.floor((cardWidth - #name) / 2)
                local line = ui.lines[y]
                ui.lines[y] = line:sub(1, labelX - 1) .. name .. line:sub(labelX + #name)
                local usableWidth, usableHeight = cardWidth - grid[1] + 1, 6 - grid[2]
                for row = 1, grid[2] do for column = 1, grid[1] do
                    local px = x + math.floor((column - 1) * usableWidth / grid[1]) + column - 1
                    local py = y + 1 + math.floor((row - 1) * usableHeight / grid[2]) + row - 1
                    local pw = math.floor(column * usableWidth / grid[1]) - math.floor((column - 1) * usableWidth / grid[1])
                    local ph = math.floor(row * usableHeight / grid[2]) - math.floor((row - 1) * usableHeight / grid[2])
                    ui.style(px, py, pw, ph, nil, item.enabled and 8 or 128)
                end end
                hit(x, y, cardWidth, 6, item)
            end
        end
    end
    local half = math.floor(width / 2)
    if pages > 1 then
        ui.button(height - 2, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 2, "Next >", "next", half + 1, width, page < pages)
    end
    local function action(y, x1, x2, mode, label)
        ui.button(y, label, "item", x1, x2, byMode[mode].enabled)
        ui.hits[#ui.hits].item = byMode[mode]
    end
    if gridColumns then
        action(height, 1, half, "back", "Back")
    else
        action(height - 1, 1, half, "restore", "Restore")
        action(height - 1, half + 1, width, "custom", "Resize")
        action(height, 1, half, "move", "Move")
    end
    action(height, half + 1, width, "cancel", "Cancel")
    for _, hit in ipairs(ui.hits) do
        hit.x1, hit.x2, hit.y = hit.x1 + rect.x - 1, hit.x2 + rect.x - 1, hit.y + rect.y - 1
        if hit.y1 then hit.y1, hit.y2 = hit.y1 + rect.y - 1, hit.y2 + rect.y - 1 end
    end
    return rect, ui.lines, ui.hits, page, pages
end

-- Returns a complete taskbar line and exact touch regions, with stable window order.
function Desktop.taskbar(windows, monitor, clock, saved, active)
    local width = monitor.width
    local line, hits = string.rep(" ", width), {}
    local function put(x, label, stop)
        label = label:sub(1, math.max(0, math.min(stop or width, width) - x + 1))
        line = line:sub(1, x - 1) .. label .. line:sub(x + #label)
    end
    local function hit(x1, x2, action, id) hits[#hits + 1] = {x1 = x1, x2 = x2, action = action, id = id} end
    put(1, "[+]"); hit(1, math.min(3, width), "launcher")
    local clockWidth = (width >= 22 or (#windows == 0 and width >= 10)) and 6 or 0
    if clockWidth > 0 then put(width - 4, clock) end
    local first, last = 5, width - clockWidth
    if last < first then return line, hits end
    local labels, needed = {}, 0
    for _, win in ipairs(windows) do
        local marker = win.minimized and "_" or win.id == active and "*" or ""
        local label = " " .. marker .. (win.title or win.appName) .. " "
        if #label > 14 then label = label:sub(1, 13) .. " " end
        labels[#labels + 1] = label
        needed = needed + #labels[#labels] + 1
    end
    local overflow = needed > last - first + 2
    local scroll = tonumber(saved.scroll) or 1
    if scroll ~= scroll then scroll = 1 end
    saved.scroll = clamp(math.floor(scroll), 1, math.max(1, #windows))
    if not overflow then saved.scroll = 1 end
    if overflow then
        if saved.scroll > 1 then put(first, "<"); hit(first, first, "previous") end
        first, last = first + 1, last - 1
    end
    local x, finalVisible = first, saved.scroll - 1
    for index = saved.scroll, #windows do
        local available = last - x + 1
        if available < 3 then break end
        local label = labels[index]
        local limit = math.min(14, available)
        if #label > limit then label = label:sub(1, limit - 1) .. " " end
        put(x, label, last); hit(x, x + #label - 1, "window", windows[index].id)
        x, finalVisible = x + #label + 1, index
    end
    if overflow and finalVisible < #windows then
        put(last + 1, ">"); hit(last + 1, last + 1, "next")
    end
    return line, hits
end

-- Shared paginated popup geometry for the launcher and window layout menus.
function Desktop.menu(monitor, title, items, page, anchor)
    local area = Desktop.area(monitor)
    local width = math.min(area.width, 26)
    local height = math.min(area.height, math.max(4, #items + 3))
    local slots = math.max(1, height - 3)
    local pages = math.max(1, math.ceil(#items / slots))
    page = clamp(page or 1, 1, pages)
    local rect = {x = clamp(anchor and anchor.x or 1, 1, area.width - width + 1),
        y = clamp(anchor and anchor.y or area.height - height + 1, 1, area.height - height + 1), width = width, height = height}
    local lines, hits = {}, {}
    for y = 1, height do lines[y] = string.rep(" ", width) end
    lines[1] = (" " .. title .. string.rep(" ", width)):sub(1, width)
    lines[height] = (" " .. page .. "/" .. pages .. string.rep(" ", width)):sub(1, width)
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then
            local label = (item.enabled == false and "-" or " ") .. item.label
            lines[row + 1] = " " .. label:sub(1, width - 2) .. string.rep(" ", math.max(0, width - 2 - #label)) .. " "
            hits[#hits + 1] = {x1 = rect.x + 1, x2 = rect.x + width - 2, y = rect.y + row,
                action = "item", item = item}
        end
    end
    if #items == 0 then lines[2] = (" No apps" .. string.rep(" ", width)):sub(1, width) end
    if pages > 1 then
        local half = math.floor((width - 2) / 2)
        lines[height - 1] = " " .. ("< Prev" .. string.rep(" ", width)):sub(1, half)
            .. ("Next >" .. string.rep(" ", width)):sub(1, width - 2 - half) .. " "
        hits[#hits + 1] = {x1 = rect.x + 1, x2 = rect.x + half, y = rect.y + height - 2, action = "previous"}
        hits[#hits + 1] = {x1 = rect.x + half + 1, x2 = rect.x + width - 2, y = rect.y + height - 2, action = "next"}
    end
    return rect, lines, hits, page, pages
end

return Desktop
]=],
    ["lib_server.lua"] = [=[-- Central state, app lifecycle, desktops and logical IO routing. No redstone here.
local Server = {}
local Picker = dofile("lib_io_picker.lua")
local Desktop = dofile("lib_desktop.lua")
local Gui = dofile("lib_gui.lua")
local Settings = dofile("lib_settings.lua")
local systemColours = {background = {field = "backgroundColour", title = "Background"},
    windowBorder = {field = "windowBorderColour", title = "Window border"}, taskbar = {field = "taskbarColour", title = "Taskbar"}}
local sideSet = {top = true, bottom = true, left = true, right = true, front = true, back = true}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function colour(value)
    if not integer(value, 1, 32768) then return false end
    while value > 1 do
        if value % 2 ~= 0 then return false end
        value = value / 2
    end
    return true
end
local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function wireGroup(groups, mapping)
    groups[mapping.clientId] = groups[mapping.clientId] or {}
    local sides = groups[mapping.clientId]
    sides[mapping.side] = sides[mapping.side] or {}
    local key = mapping.color or "digital"
    sides[mapping.side][key] = sides[mapping.side][key] or {}
    return sides[mapping.side][key]
end
local function currentWires(mappings, values)
    local groups = {}
    for name, mapping in pairs(mappings) do
        local group = wireGroup(groups, mapping)
        group.value = group.value == true or values[name] == true
    end
    return groups
end
local function sameSnapshot(a, b)
    for side, value in pairs(a) do
        if not b[side] or value.bundled ~= b[side].bundled or value.digital ~= b[side].digital then return false end
    end
    for side in pairs(b) do if not a[side] then return false end end
    return true
end

local function validState(value)
    for _, key in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if value[key] ~= nil and type(value[key]) ~= "table" then return false end
    end
    for name, mapping in pairs(value.outputMap or {}) do
        if type(name) ~= "string" or type(mapping) ~= "table" or type(mapping.clientId) ~= "string"
            or not sideSet[mapping.side] or (mapping.color ~= nil and not colour(mapping.color)) then return false end
    end
    for id, entries in pairs(value.managedSides or {}) do
        if type(id) ~= "string" or type(entries) ~= "table" then return false end
        for side, enabled in pairs(entries) do if not sideSet[side] or enabled ~= true then return false end end
    end
    return true
end

local function validApp(app)
    if type(app) ~= "table" then return false end
    if app.title ~= nil and (type(app.title) ~= "string" or #app.title < 1 or #app.title > 64) then return false end
    for _, key in ipairs({"minWidth", "maxWidth", "minHeight", "maxHeight", "preferredWidth", "preferredHeight"}) do
        if app[key] ~= nil and not integer(app[key], 1, 512) then return false end
    end
    if app.backgroundService ~= nil and type(app.backgroundService) ~= "boolean" then return false end
    for _, key in ipairs({"init", "shutdown", "background", "render", "handleTouch", "handleIOSelection"}) do
        if app[key] ~= nil and type(app[key]) ~= "function" then return false end
    end
    return (not app.maxWidth or app.maxWidth >= (app.minWidth or 8))
        and (not app.maxHeight or app.maxHeight >= (app.minHeight or 2))
end

function Server.new(net, storage, config, logger)
    local log = logger or print
    local loaded, source = storage.load(config.saveFile, validState)
    local state = loaded or {}
    for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if type(state[name]) ~= "table" then state[name] = {} end
    end
    -- Older/manual saves may contain aliases with separate values. Retain the
    -- previously powered mask, then keep every reference to each wire in sync.
    local restoredWires = currentWires(state.outputMap, state.outputs)
    for name, mapping in pairs(state.outputMap) do state.outputs[name] = wireGroup(restoredWires, mapping).value end
    state.appearance = type(state.appearance) == "table" and state.appearance or {}
    if not colour(state.appearance.backgroundColour) then state.appearance.backgroundColour = 2048 end
    if not colour(state.appearance.windowBorderColour) then state.appearance.windowBorderColour = 128 end
    if not colour(state.appearance.taskbarColour) then state.appearance.taskbarColour = 128 end
    if type(state.appearance.appColours) ~= "table" then state.appearance.appColours = {} end
    for name, value in pairs(state.appearance.appColours) do
        if type(name) ~= "string" or not colour(value) then state.appearance.appColours[name] = nil end
    end
    state.appStates["@settings"] = type(state.appStates["@settings"]) == "table" and state.appStates["@settings"] or {}
    local server = {state = state, monitors = {}, ioClients = {}, sensorClients = {}, apps = {},
        systemApps = {["@settings"] = Settings}, gameTime = "?:??", playerOnline = false,
        lastSave = 0, lastTick = os.clock(), views = {}, dialogs = {}, running = {}}
    local api, errors = {}, {}
    server.api = api
    api.ui, api.log, api.sharedOutputs = Gui, log, true
    local function definition(name) return server.systemApps[name] or server.apps[name] end
    local function invalidateInput(id)
        local monitor = server.monitors[id]
        if monitor then monitor.inputRevision = (monitor.inputRevision or 0) + 1 end
    end
    state.nextWindowId = 1
    local legacyDesktop = (tonumber(state.desktopVersion) or 1) < 2
    for id, win in pairs(state.windows) do
        if not integer(id, 1, 2147483646) or type(win) ~= "table"
            or type(win.appName) ~= "string" or type(win.monitorId) ~= "string" then
            state.windows[id] = nil
        else
            state.nextWindowId = math.max(state.nextWindowId, id + 1)
            win.id, win.order = id, tonumber(win.order) or id
            if not state.appStates[win.appName] and type(win.appState) == "table" then
                state.appStates[win.appName] = win.appState
            end
            win.appState = nil -- App state is shared with its background service.
            if legacyDesktop then win.y = math.max(1, (tonumber(win.y) or 3) - 2) end
        end
    end
    state.desktopVersion = 2
    state.bootCounter = (tonumber(state.bootCounter) or 0) + 1
    server.session = tostring(net.id) .. ":" .. state.bootCounter
    if source and source ~= config.saveFile then log("Recovered state from " .. source) end
    if not loaded and fs.exists(config.saveFile) then log("Unreadable OS state; starting with defaults") end

    function server.save()
        local saved = {}
        for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides",
            "nextWindowId", "bootCounter", "desktops", "desktopVersion", "appearance"}) do saved[name] = state[name] end
        local ok, err = storage.save(config.saveFile, saved)
        if not ok then log("State save failed: " .. tostring(err)) else server.lastSave = os.clock() end
        return ok, err
    end
    api.save = server.save

    function api.getOSSettings()
        return {backgroundMode = "solid", backgroundColour = state.appearance.backgroundColour,
            windowBorderColour = state.appearance.windowBorderColour, taskbarColour = state.appearance.taskbarColour}
    end
    function api.getAppColour(name) return state.appearance.appColours[name] or 2048 end
    local function saveAppearance(change)
        local previous = copy(state.appearance)
        change(state.appearance)
        local ok, err = server.save()
        if not ok then state.appearance = previous end
        return ok, err
    end
    function api.setBackgroundColour(value)
        if not colour(value) then return false, "Choose a CC colour" end
        return saveAppearance(function(appearance) appearance.backgroundColour = value end)
    end
    function api.setWindowBorderColour(value)
        if not colour(value) then return false, "Choose a CC colour" end
        return saveAppearance(function(appearance) appearance.windowBorderColour = value end)
    end
    function api.setTaskbarColour(value)
        if not colour(value) then return false, "Choose a CC colour" end
        return saveAppearance(function(appearance) appearance.taskbarColour = value end)
    end
    local systemColourSetters = {background = api.setBackgroundColour,
        windowBorder = api.setWindowBorderColour, taskbar = api.setTaskbarColour}
    function api.setAppColour(name, value)
        if not definition(name) or not colour(value) then return false, "Invalid app colour" end
        return saveAppearance(function(appearance) appearance.appColours[name] = value end)
    end

    local function appCall(name, hook, ...)
        local app = definition(name)
        if not app or not app[hook] then return true end
        local ok, a, b = pcall(app[hook], ...)
        if not ok then
            local key = name .. "." .. hook
            if errors[key] ~= a then log("App " .. key .. " failed: " .. tostring(a)); errors[key] = a end
        end
        return ok, a, b
    end

    local function isService(app) return app.backgroundService == true or app.render == nil end
    local function hasViews(name)
        for _, win in pairs(state.windows) do if win.appName == name then return true end end
        return false
    end
    local function startApp(name)
        if server.running[name] then return true end
        server.running[name] = true
        local ok, err = appCall(name, "init", state.appStates[name], api, {appName = name})
        if not ok then server.running[name] = nil; return false, err end
        return true
    end
    local function stopApp(name)
        if server.running[name] and not isService(definition(name)) and not hasViews(name) then
            appCall(name, "shutdown", state.appStates[name], api, {appName = name})
            server.running[name] = nil
            server.save()
        end
    end

    local function viewContext(win)
        server.views[win.id] = server.views[win.id] or {}
        return {windowId = win.id, monitorId = win.monitorId, appName = win.appName, view = server.views[win.id]}
    end

    local function updateClock()
        if type(os.time) == "function" then
            local ok, value = pcall(os.time)
            if ok and type(value) == "number" and value >= 0 and value < 24 then
                local minutes = math.floor(value * 60 + 0.000001)
                server.gameTime = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
                server.clockSource = "computer"
                return
            end
        end
        for _, id in ipairs(sortedKeys(server.sensorClients)) do
            local sensor = server.sensorClients[id]
            if sensor.online and type(sensor.values.gameTime) == "string" then
                server.gameTime, server.clockSource = sensor.values.gameTime:sub(1, 32), "sensor"
                return
            end
        end
        server.gameTime, server.clockSource = "?:??", "unavailable"
    end
    updateClock()

    local function outputSnapshot(clientId)
        local snapshot = {}
        for side in pairs(state.managedSides[clientId] or {}) do
            snapshot[side] = {bundled = 0, digital = false}
        end
        for name, mapping in pairs(state.outputMap) do
            if mapping.clientId == clientId and sideSet[mapping.side] then
                local values = snapshot[mapping.side] or {bundled = 0, digital = false}
                snapshot[mapping.side] = values
                if state.outputs[name] == true then
                    if mapping.color then values.bundled = colors.combine(values.bundled, mapping.color)
                    else values.digital = true end
                end
            end
        end
        return snapshot
    end

    function server.syncIO(clientId, changed)
        local client = server.ioClients[clientId]
        if not client then return end
        if changed then client.revision = client.revision + 1 end
        if not client.online then return end
        local snapshot = outputSnapshot(clientId)
        for side in pairs(snapshot) do
            if not client.capabilities[side] then
                log("IO " .. clientId .. ": mapped side " .. side .. " is unavailable")
                snapshot[side] = nil
            end
        end
        net.toClient(client, {type = "ioCommand", command = "syncOutputs", clientId = clientId,
            serverSession = server.session, revision = client.revision, outputs = snapshot})
        client.lastSent = os.clock()
    end

    function api.getOutput(name) return state.outputs[name] == true end
    -- One checkpoint for a whole panel, reroute, removal or group action. App
    -- state changed by the caller is included in that same durable checkpoint.
    function api.updateOutputs(changes)
        if type(changes) ~= "table" then return false, "Expected output changes" end
        local count = 0
        for index in pairs(changes) do
            if not integer(index, 1, #changes) then return false, "Expected a dense array of output changes" end
            count = count + 1
        end
        if count ~= #changes then return false, "Expected a dense array of output changes" end
        local mappings, values, managed = copy(state.outputMap), copy(state.outputs), copy(state.managedSides)
        local seen, affected = {}, {}
        local oldWires = currentWires(state.outputMap, state.outputs)
        local function remember(mapping)
            if not mapping then return end
            affected[mapping.clientId] = true
            managed[mapping.clientId] = managed[mapping.clientId] or {}
            managed[mapping.clientId][mapping.side] = true
        end
        for _, change in ipairs(changes) do
            if type(change) ~= "table" or type(change.name) ~= "string" or not change.name:match("^[%w_-]+$")
                or seen[change.name] then return false, "Invalid or repeated output name" end
            if change.remove ~= nil and type(change.remove) ~= "boolean"
                or change.clientId == nil and (change.side ~= nil or change.color ~= nil or change.initialValue ~= nil)
                or change.initialValue ~= nil and type(change.initialValue) ~= "boolean"
                or change.initialValue ~= nil and change.value ~= nil then return false, "Invalid output change" end
            seen[change.name] = change
            remember(mappings[change.name])
            if change.remove == true then
                mappings[change.name], values[change.name] = nil, nil
            else
                local mapping = mappings[change.name]
                if change.clientId ~= nil then
                    if type(change.clientId) ~= "string" or change.clientId == "" or not sideSet[change.side]
                        or (change.color ~= nil and not colour(change.color)) then return false, "Invalid output mapping" end
                    mapping = {clientId = change.clientId, side = change.side, color = change.color}
                    local client = server.ioClients[mapping.clientId]
                    if client and client.online and not client.capabilities[mapping.side] then
                        return false, "That side is unavailable (possibly occupied by the modem)"
                    end
                    mappings[change.name] = mapping
                end
                if not mapping then return false, "Unknown output: " .. change.name end
                if change.value ~= nil then
                    if type(change.value) ~= "boolean" then return false, "Output value must be boolean" end
                end
                remember(mapping)
            end
        end
        local wires, groups = {}, {}
        for _, name in ipairs(sortedKeys(mappings)) do
            local mapping = mappings[name]
            local group = wireGroup(wires, mapping)
            if not group.names then
                group.names, group.previous = {}, wireGroup(oldWires, mapping).value
                groups[#groups + 1] = group
            end
            group.names[#group.names + 1] = name
            local change = seen[name]
            if change and change.value ~= nil then
                if group.wanted ~= nil and group.wanted ~= change.value then return false, "Conflicting values for a shared wire" end
                group.wanted = change.value
            elseif change and change.initialValue ~= nil and group.previous == nil then
                if group.initial ~= nil and group.initial ~= change.initialValue then return false, "Conflicting initial values for a shared wire" end
                group.initial = change.initialValue
            end
            group.fallback = group.fallback == true or values[name] == true
        end
        for _, group in ipairs(groups) do
            local wanted = group.wanted
            if wanted == nil then wanted = group.previous end
            if wanted == nil then wanted = group.initial end
            if wanted == nil then wanted = group.fallback end
            for _, name in ipairs(group.names) do values[name] = wanted end
        end
        local before = {}
        for id in pairs(affected) do before[id] = outputSnapshot(id) end
        local previousMap, previousValues, previousManaged = state.outputMap, state.outputs, state.managedSides
        state.outputMap, state.outputs, state.managedSides = mappings, values, managed
        local ok, err = server.save()
        if not ok then
            state.outputMap, state.outputs, state.managedSides = previousMap, previousValues, previousManaged
            return false, err
        end
        for _, id in ipairs(sortedKeys(affected)) do server.syncIO(id, not sameSnapshot(before[id], outputSnapshot(id))) end
        return true
    end
    function api.mapOutput(name, clientId, side, color, initialValue)
        -- Binding another reference adopts an existing wire's state. An
        -- explicit rebind to the same address can still set its initial intent.
        if clientId == nil then return false, "Invalid output mapping" end
        local old = state.outputMap[name]
        local change = {name = name, clientId = clientId, side = side, color = color, initialValue = initialValue}
        if old and old.clientId == clientId and old.side == side and old.color == color then
            change.initialValue, change.value = nil, initialValue
        end
        return api.updateOutputs({change})
    end
    function api.setOutput(name, value)
        if type(value) ~= "boolean" then return false, "Output value must be boolean" end
        return api.updateOutputs({{name = name, value = value}})
    end
    function api.getOutputs()
        local result = {}
        for _, name in ipairs(sortedKeys(state.outputMap)) do
            local item = copy(state.outputMap[name])
            local client = server.ioClients[item.clientId]
            item.name, item.value, item.online = name, api.getOutput(name), client and client.online or false
            item.confirmed = item.online and client.capabilities[item.side]
                and client.ackedRevision == client.revision or false
            result[#result + 1] = item
        end
        return result
    end
    function api.getInput(clientId, side)
        local client = server.ioClients[clientId]
        if client and client.online then return copy(client.inputs[side]) end
    end
    function api.readInput(address)
        if type(address) ~= "table" or type(address.clientId) ~= "string" or not sideSet[address.side]
            or (address.color ~= nil and not colour(address.color)) then return nil, "Input not configured" end
        local reading = api.getInput(address.clientId, address.side)
        if not reading then return nil, "Input offline" end
        if address.color then return math.floor(reading.value / address.color) % 2 == 1 end
        return reading.digital
    end
    function api.getIOClients()
        local result = {}
        for _, id in ipairs(sortedKeys(server.ioClients)) do
            local client = server.ioClients[id]
            result[#result + 1] = {id = id, online = client.online, computerId = client.computerId,
                sides = sortedKeys(client.capabilities or {})}
        end
        return result
    end
    function api.pickIO(windowId, key, direction, current)
        local win = state.windows[windowId]
        if not win or type(key) ~= "string" or (direction ~= "input" and direction ~= "output") then
            return false, "Invalid IO selector request"
        end
        if win.width < 14 or win.height < 8 then return false, "IO settings need a 12x6 content area" end
        local app = definition(win.appName)
        if not app or not app.handleIOSelection then return false, "App has no IO selection handler" end
        server.dialogs[windowId] = Picker.new(key, direction, current)
        invalidateInput(win.monitorId)
        return true
    end
    function api.pickColour(windowId, target)
        local win = state.windows[windowId]
        target = target or "app"
        local option = systemColours[target]
        if not win or (target ~= "app" and not option) then return false, "Invalid colour selector" end
        if option and win.appName ~= "@settings" then return false, "Open OS settings for system colours" end
        if win.width < 14 or win.height < 8 then return false, "Colour settings need a 12x6 content area" end
        server.dialogs[windowId] = {kind = "colour", target = target,
            current = option and state.appearance[option.field] or api.getAppColour(win.appName)}
        invalidateInput(win.monitorId)
        return true
    end
    function api.getSensor(clientId, name)
        local client = server.sensorClients[clientId]
        if client and client.online then return copy(client.values[name]) end
    end
    function api.getClients()
        local result = {}
        for kind, group in pairs({io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients}) do
            for id, client in pairs(group) do
                result[#result + 1] = {id = id, type = kind, online = client.online, computerId = client.computerId}
            end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    function api.getSystem() return {gameTime = server.gameTime, clockSource = server.clockSource,
        playerOnline = server.playerOnline} end

    local function windowsFor(monitorId, stable)
        local list = {}
        for _, win in pairs(state.windows) do
            if win.monitorId == monitorId then list[#list + 1] = win end
        end
        table.sort(list, function(a, b) return stable and a.id < b.id or not stable and a.order < b.order end)
        return list
    end
    local function desktopState(id)
        if type(state.desktops[id]) ~= "table" then state.desktops[id] = {scroll = 1} end
        return state.desktops[id]
    end
    local function focus(win)
        local order = 0
        for _, other in pairs(state.windows) do order = math.max(order, other.order) end
        win.order, win.minimized = order + 1, false
        invalidateInput(win.monitorId)
        local monitor, visible = server.monitors[win.monitorId], false
        for _, hit in ipairs(monitor and monitor.taskbar or {}) do
            if hit.action == "window" and hit.id == win.id then visible = true end
        end
        if not visible then
            for index, item in ipairs(windowsFor(win.monitorId, true)) do
                if item.id == win.id then desktopState(win.monitorId).scroll = index; break end
            end
        end
    end
    local function validRelative(value)
        if type(value) ~= "table" then return false end
        for _, key in ipairs({"x", "y", "width", "height"}) do
            if type(value[key]) ~= "number" or value[key] ~= value[key] or value[key] < 0 or value[key] > 1 then return false end
        end
        return value.width > 0 and value.height > 0
    end
    local function fit(win, monitor)
        local app = definition(win.appName)
        if not app then win.doesNotFit = true; return false end
        win.title = app.title or win.appName
        if not validRelative(win.relative) then win.relative = nil end
        local rect
        if win.layout and win.layout ~= "normal" then
            rect = Desktop.zone(win.layout, monitor)
            if not Desktop.fits(rect, app, monitor) then win.doesNotFit = true; return false end
        else
            win.layout = "normal"
            rect = Desktop.free(win, win.relative, app, monitor)
            if not rect then win.doesNotFit = true; return false end
            if not win.relative then win.relative = Desktop.relative(rect, monitor) end
        end
        win.x, win.y, win.width, win.height = rect.x, rect.y, rect.width, rect.height
        win.doesNotFit = false
        return true
    end
    local function compatible(name, monitor)
        local app = definition(name)
        local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
        return app.render and maxW >= minW and maxH >= minH
    end
    local function discardSmallDialog(win)
        if win.width < 14 or win.height < 8 then server.dialogs[win.id] = nil end
    end

    function api.openApp(name, monitorId, x, y, width, height)
        local app, monitor = definition(name), server.monitors[monitorId]
        if not app then return nil, "Unknown app" end
        if not monitor or not monitor.online then return nil, "Monitor is offline or unknown" end
        if not compatible(name, monitor) then return nil, "App does not fit this monitor" end
        local win = {id = state.nextWindowId, appName = name, monitorId = monitorId,
            x = x, y = y, width = width, height = height, order = 0, layout = "normal"}
        fit(win, monitor)
        if not x and not y then
            local existing, placed = windowsFor(monitorId), false
            for cy = 1, monitor.height - win.height do
                for cx = 1, monitor.width - win.width + 1 do
                    local free = true
                    for _, other in ipairs(existing) do
                        if not other.minimized and fit(other, monitor) and cx < other.x + other.width
                            and cx + win.width > other.x and cy < other.y + other.height
                            and cy + win.height > other.y then free = false; break end
                    end
                    if free then win.x, win.y, placed = cx, cy, true; break end
                end
                if placed then break end
            end
        end
        win.relative = Desktop.relative(win, monitor)
        state.windows[win.id], state.nextWindowId = win, win.id + 1
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[win.id] = nil; return nil, err end
        ok, err = startApp(name)
        if not ok then state.windows[win.id] = nil; server.save(); return nil, err end
        return win.id
    end
    function api.closeWindow(id)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        state.windows[id] = nil
        local ok, err = server.save()
        if not ok then state.windows[id] = win; return false, err end
        server.views[id], server.dialogs[id] = nil, nil
        local monitor = server.monitors[win.monitorId]
        if monitor then
            if monitor.layoutMenu and monitor.layoutMenu.windowId == id then monitor.layoutMenu = nil end
            if monitor.placement and monitor.placement.windowId == id then monitor.placement = nil end
        end
        stopApp(win.appName)
        invalidateInput(win.monitorId)
        return true
    end
    function api.placeWindow(id, x, y, width, height)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        for _, value in pairs({x = x, y = y, width = width, height = height}) do
            if not integer(value, 1, 512) then return false, "Expected positive integer coordinates/sizes" end
        end
        local previous = copy(win)
        win.x, win.y, win.width, win.height = x or win.x, y or win.y, width or win.width, height or win.height
        win.layout, win.relative, win.restore = "normal", nil, nil
        if not fit(win, monitor) then state.windows[id] = previous; return false, "App does not fit" end
        win.relative = Desktop.relative(win, monitor)
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        return true
    end
    function api.layoutWindow(id, mode)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        if not definition(win.appName) then return false, "App is not available" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        local previous = copy(win)
        if mode ~= "restore" and win.layout == mode then return true end
        if mode == "restore" then
            local restore = win.restore or {layout = "normal", relative = win.relative}
            win.layout, win.relative, win.restore = restore.layout, copy(restore.relative), nil
        else
            local rect = Desktop.zone(mode, monitor)
            if not Desktop.fits(rect, definition(win.appName), monitor) then return false, "Layout does not fit this app" end
            win.restore = {layout = win.layout or "normal", relative = copy(win.relative)}
            win.layout = mode
        end
        if not fit(win, monitor) then state.windows[id] = previous; return false, "Layout does not fit" end
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        return true
    end
    local function beginPlacement(monitor, win, kind)
        monitor.launcher, monitor.layoutMenu = false, nil
        monitor.placement = {windowId = win.id, kind = kind}
    end

    local function renderMonitor(id, monitor)
        local desktopColour = state.appearance.backgroundColour
        local borderColour, taskbarColour = state.appearance.windowBorderColour, state.appearance.taskbarColour
        local surface = Gui.new(monitor.width, monitor.height, Gui.contrast(desktopColour), desktopColour)
        local function write(x, y, text, limit)
            surface.write(x, y, text, nil, nil, limit)
        end
        local active
        for _, win in ipairs(windowsFor(id)) do
            if fit(win, monitor) and not win.minimized and server.running[win.appName] then active = win.id end
        end
        for _, win in ipairs(windowsFor(id)) do
            if fit(win, monitor) and not win.minimized and server.running[win.appName] then
                surface.fill(win.x, win.y, win.width, win.height, Gui.contrast(borderColour), borderColour)
                surface.fill(win.x + 1, win.y + 1, win.width - 2, win.height - 2, 32768, 256)
                surface.fill(win.x, win.y, win.width, 1, Gui.contrast(borderColour), borderColour)
                write(win.x, win.y, win.title, win.width - 9)
                for _, control in ipairs(Desktop.controls(win)) do
                    local controlColour = control.action == "close" and 16384 or borderColour
                    surface.write(control.x1, win.y, control.label, Gui.contrast(controlColour), controlColour)
                end
                local ok, content
                if server.dialogs[win.id] then
                    local dialog = server.dialogs[win.id]
                    ok = true
                    if dialog.kind == "colour" then
                        local option = systemColours[dialog.target]
                        dialog.current = option and state.appearance[option.field] or api.getAppColour(win.appName)
                        content, dialog.hits = Gui.palette(win.width - 2, win.height - 2, dialog.current,
                            dialog.error or (option and option.title or "UI colour"))
                    else content = Picker.render(dialog, win.width - 2, win.height - 2, api.getIOClients()) end
                else
                    ok, content = appCall(win.appName, "render", win.width - 2, win.height - 2,
                        state.appStates[win.appName], api, viewContext(win))
                end
                if not ok or type(content) ~= "table" then content = {"App render failed"} end
                for y = 1, win.height - 2 do write(win.x + 1, win.y + y, content[y] or "", win.width - 2) end
                for _, style in ipairs(type(content.styles) == "table" and content.styles or {}) do
                    if type(style) == "table" and integer(style.x, 1, win.width - 2)
                        and integer(style.y, 1, win.height - 2) and integer(style.width, 1, 512)
                        and integer(style.height or 1, 1, 512) then
                        surface.style(win.x + style.x, win.y + style.y,
                            math.min(style.width, win.width - 1 - style.x), math.min(style.height or 1, win.height - 1 - style.y),
                            style.fg, style.bg)
                    end
                end
            end
        end
        local taskbar
        taskbar, monitor.taskbar = Desktop.taskbar(windowsFor(id, true), monitor, server.gameTime, desktopState(id), active)
        write(1, monitor.height, taskbar)
        surface.style(1, monitor.height, monitor.width, 1, Gui.contrast(taskbarColour), taskbarColour)
        for _, hit in ipairs(monitor.taskbar) do
            if (hit.action == "launcher" and monitor.launcher) or (hit.action == "window" and hit.id == active) then
                local highlight = Gui.contrast(taskbarColour)
                surface.style(hit.x1, monitor.height, hit.x2 - hit.x1 + 1, 1, Gui.contrast(highlight), highlight)
            end
        end
        if monitor.launcher or monitor.layoutMenu then
            local items, title, model
            if monitor.launcher then
                model, title = monitor, "Start"
                items = {{label = "OS settings", value = "@settings", enabled = compatible("@settings", monitor)}}
                for _, name in ipairs(sortedKeys(server.apps)) do
                    if compatible(name, monitor) then
                        items[#items + 1] = {label = (server.apps[name].title or name) .. (server.running[name] and " *" or ""), value = name, enabled = true}
                    end
                end
                if #items == 1 then
                    items[2] = {label = next(server.apps) and "No apps fit" or "No apps installed", enabled = false}
                end
            else
                model, title = monitor.layoutMenu, monitor.layoutMenu.error or "Layout"
                local win = state.windows[model.windowId]
                items = win and Desktop.layoutOptions(win, definition(win.appName), monitor) or {}
            end
            local win = monitor.layoutMenu and state.windows[monitor.layoutMenu.windowId]
            local anchor = win and {x = win.x + win.width - 26, y = win.y + 1}
            local rect, content, hits, page, pages
            if win then rect, content, hits, page, pages = Desktop.layoutPicker(win, definition(win.appName), monitor, model.menuPage, model.error, model.grid)
            else rect, content, hits, page, pages = Desktop.menu(monitor, title, items, model.menuPage, anchor) end
            model.menuPage, model.menuPages, model.menuHits = page, pages, hits
            surface.fill(rect.x, rect.y, rect.width, rect.height, 32768, 1)
            for row = 1, rect.height do write(rect.x, rect.y + row - 1, content[row], rect.width) end
            surface.style(rect.x, rect.y, rect.width, 1, 1, 128)
            if content.styles then
                for _, style in ipairs(content.styles) do
                    surface.style(rect.x + style.x - 1, rect.y + style.y - 1, style.width, style.height or 1, style.fg, style.bg)
                end
            else
                for _, hit in ipairs(hits) do
                    surface.style(hit.x1, hit.y, hit.x2 - hit.x1 + 1, 1,
                        hit.item and hit.item.enabled == false and 128 or 32768, hit.action == "item" and 256 or 128)
                end
            end
        end
        local placement = monitor.placement
        if placement then
            local rect = placement.preview
            if rect then
                local win = state.windows[placement.windowId]
                placement.valid = win and Desktop.fits(rect, definition(win.appName), monitor) and true or false
                if not placement.valid then placement.error = "Does not fit" end
                local border = placement.error and 16384 or 32
                surface.fill(rect.x, rect.y, rect.width, 1, 1, border)
                if rect.height > 1 then surface.fill(rect.x, rect.y + rect.height - 1, rect.width, 1, 1, border) end
                for y = rect.y + 1, rect.y + rect.height - 2 do
                    surface.fill(rect.x, y, 1, 1, 1, border); surface.fill(rect.x + rect.width - 1, y, 1, 1, 1, border)
                end
            end
            if placement.first then write(placement.first.x, placement.first.y, "+") end
            local hint = placement.error or (rect and "OK to apply" or placement.kind == "move" and "Pick position"
                or placement.first and "Other corner" or "First corner")
            if rect and not placement.error then hint = "OK: " .. rect.width .. "x" .. rect.height end
            write(1, 1, hint .. string.rep(" ", monitor.width))
            write(1, monitor.height, "[OK][Cancel]" .. string.rep(" ", math.max(0, monitor.width - 12)))
            surface.style(1, 1, monitor.width, 1, 1, 128)
            surface.style(1, monitor.height, 4, 1, 1, 8192)
            surface.style(5, monitor.height, 8, 1, 1, 16384)
            placement.hits = {}
            if placement.kind == "move" and rect then
                if placement.valid then placement.hits = Desktop.moveArrows(rect, monitor) end
                for _, hit in ipairs(placement.hits) do surface.write(hit.x1, hit.y, hit.label, 1, 128) end
                local x = monitor.width - 4
                surface.write(x, 1, "Place", 32768, 256)
                placement.hits[#placement.hits + 1] = {x1 = x, x2 = monitor.width, y = 1, action = "place"}
            end
        end
        return surface.frame()
    end

    function server.refreshMonitors(force)
        for id, monitor in pairs(server.monitors) do
            if monitor.online then
                local lines, foreground, background = renderMonitor(id, monitor)
                local signature = table.concat(lines, "\n") .. table.concat(foreground, "\n")
                    .. table.concat(background, "\n") .. tostring(monitor.inputRevision or 0)
                if force or signature ~= monitor.lastRender then
                    monitor.frameId = (monitor.frameId or 0) + 1
                    if net.toClient(monitor, {type = "render", clientId = id, monitorId = id,
                        serverSession = server.session, lines = lines, width = monitor.width, height = monitor.height,
                        colourFormat = "rle1", foreground = foreground, background = background,
                        frameId = monitor.frameId, inputRevision = monitor.inputRevision or 0}) then
                        monitor.lastRender = signature
                    end
                end
            end
        end
    end

    local function touch(id, x, y)
        local monitor = server.monitors[id]
        if not integer(x, 1, monitor.width) or not integer(y, 1, monitor.height) then return end
        local placement = monitor.placement
        if placement then
            local win = state.windows[placement.windowId]
            if not win then monitor.placement = nil; return end
            if y == monitor.height then
                if x >= 5 and x <= 12 then monitor.placement = nil
                elseif x <= 4 and placement.preview and placement.valid then
                    local rect = placement.preview
                    if not Desktop.fits(rect, definition(win.appName), monitor) then
                        placement.valid, placement.error = false, "Does not fit"; return
                    end
                    local ok, err = api.placeWindow(win.id, rect.x, rect.y, rect.width, rect.height)
                    if ok then monitor.placement = nil else placement.error = tostring(err) end
                end
                return
            end
            for _, hit in ipairs(placement.hits or {}) do
                if Gui.hit(hit, x, y) then
                    if hit.action == "place" then
                        placement.preview, placement.valid, placement.error = nil, false, nil
                        return
                    end
                    local rect = placement.preview
                    rect.x, rect.y = rect.x + hit.dx, rect.y + hit.dy
                    placement.valid = Desktop.fits(rect, definition(win.appName), monitor) and true or false
                    placement.error = not placement.valid and "Does not fit" or nil
                    return
                end
            end
            if placement.kind == "move" then
                if placement.preview then return end
                placement.preview = {x = math.max(1, math.min(x, monitor.width - win.width + 1)),
                    y = math.max(1, math.min(y, monitor.height - win.height)), width = win.width, height = win.height}
            elseif not placement.first then placement.first = {x = x, y = y}
            else
                placement.preview = {x = math.min(x, placement.first.x), y = math.min(y, placement.first.y),
                    width = math.abs(x - placement.first.x) + 1, height = math.abs(y - placement.first.y) + 1}
            end
            placement.valid = Desktop.fits(placement.preview, definition(win.appName), monitor) and true or false
            placement.error = placement.preview and not placement.valid and "Does not fit" or nil
            return
        end
        if y == monitor.height then
            for _, hit in ipairs(monitor.taskbar or {}) do
                if x >= hit.x1 and x <= hit.x2 then
                    monitor.layoutMenu = nil
                    if hit.action == "launcher" then
                        monitor.launcher = not monitor.launcher; monitor.menuPage = 1
                    elseif hit.action == "previous" or hit.action == "next" then
                        local saved = desktopState(id)
                        saved.scroll = (saved.scroll or 1) + (hit.action == "next" and 1 or -1)
                        server.save()
                    elseif hit.action == "window" then
                        local win = state.windows[hit.id]
                        local active
                        for _, other in ipairs(windowsFor(id)) do
                            if not other.minimized and not other.doesNotFit then active = other.id end
                        end
                        if active == win.id then win.minimized = true else focus(win) end
                        monitor.launcher = false; server.save()
                    end
                    return
                end
            end
            return
        end
        local model = monitor.launcher and monitor or monitor.layoutMenu
        if model then
            for _, hit in ipairs(model.menuHits or {}) do
                if Gui.hit(hit, x, y) then
                    if hit.action == "previous" then model.menuPage = math.max(1, model.menuPage - 1)
                    elseif hit.action == "next" then model.menuPage = math.min(model.menuPages, model.menuPage + 1)
                    elseif hit.item.enabled ~= false then
                        if monitor.launcher then
                            local existing
                            for _, win in ipairs(windowsFor(id)) do if win.appName == hit.item.value then existing = win end end
                            if existing then focus(existing); server.save() else api.openApp(hit.item.value, id) end
                            monitor.launcher = false
                        else
                            local win = state.windows[model.windowId]
                            local mode = hit.item.value
                            local grid = mode:match("^choose_([1-3]x[1-3])$")
                            if grid then
                                model.grid, model.rootPage, model.menuPage, model.error = grid, model.menuPage, 1, nil
                            elseif mode == "back" then
                                model.grid, model.menuPage, model.error = nil, model.rootPage or 1, nil
                            elseif mode == "custom" or mode == "move" then beginPlacement(monitor, win, mode)
                            elseif mode == "cancel" then monitor.layoutMenu = nil
                            else
                                local ok, err = api.layoutWindow(win.id, mode)
                                if ok then monitor.layoutMenu = nil else model.error = tostring(err) end
                            end
                        end
                    else model.error = "Does not fit" end
                    return
                end
            end
            monitor.launcher, monitor.layoutMenu = false, nil
            return
        end
        local list = windowsFor(id)
        for index = #list, 1, -1 do
            local win = list[index]
            if not win.minimized and not win.doesNotFit and x >= win.x and x < win.x + win.width
                and y >= win.y and y < win.y + win.height then
                if y == win.y then
                    for _, control in ipairs(Desktop.controls(win)) do
                        if x >= control.x1 and x <= control.x2 then
                            if control.action == "close" then api.closeWindow(win.id)
                            elseif control.action == "layout" then
                                focus(win); monitor.layoutMenu = {windowId = win.id, menuPage = 1}; server.save()
                            else win.minimized = true; server.save() end
                            return
                        end
                    end
                    focus(win); beginPlacement(monitor, win, "move"); server.save()
                    return
                end
                focus(win)
                if x > win.x and x < win.x + win.width - 1 and y < win.y + win.height - 1 then
                    local dialog = server.dialogs[win.id]
                    if dialog then
                        local action, address
                        if dialog.kind == "colour" then
                            for _, hit in ipairs(dialog.hits or {}) do
                                if Gui.hit(hit, x - win.x, y - win.y) then action, address = hit.action, hit.value; break end
                            end
                            if action == "colour" then
                                local ok, err
                                if systemColourSetters[dialog.target] then ok, err = systemColourSetters[dialog.target](address)
                                else ok, err = api.setAppColour(win.appName, address) end
                                if ok then server.dialogs[win.id] = nil else dialog.error = tostring(err) end
                            elseif action == "cancel" then server.dialogs[win.id] = nil end
                        else action, address = Picker.touch(dialog, x - win.x, y - win.y) end
                        if action == "cancel" then server.dialogs[win.id] = nil
                        elseif action == "selected" then
                            local ok, accepted, err = appCall(win.appName, "handleIOSelection", dialog.key,
                                address, state.appStates[win.appName], api, viewContext(win))
                            if ok and accepted ~= false then server.dialogs[win.id] = nil
                            else dialog.error = tostring(ok and err or accepted) end
                        end
                    else
                        local ok, handled, replacement = appCall(win.appName, "handleTouch", x - win.x, y - win.y,
                            win.width - 2, win.height - 2, state.appStates[win.appName], api, viewContext(win))
                        if ok and type(replacement) == "table" then state.appStates[win.appName] = replacement end
                    end
                end
                server.save()
                return
            end
        end
    end

    local function registered(group, message, replyChannel)
        local client = group[message.clientId]
        if client and client.online and client.computerId == message.sender and client.channel == replyChannel
            and message.serverSession == server.session then return client end
    end

    function server.handle(message, replyChannel, now)
        if type(message.clientId) ~= "string" or #message.clientId == 0 or #message.clientId > 64 then return end
        local id = message.clientId
        if message.type == "announce" then
            if not integer(message.nonce, 1, 2147483647) then return end
            local groups = {io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients}
            local group = groups[message.clientType]
            if not group then return end
            for _, otherGroup in pairs(groups) do
                local other = otherGroup[id]
                if other and (otherGroup ~= group or (other.online and other.computerId ~= message.sender)) then
                    log("Duplicate clientId rejected: " .. id .. " (computer " .. message.sender .. ")")
                    return
                end
            end
            if message.clientType == "monitor" and (not integer(message.width, 1, 256)
                or not integer(message.height, 2, 128)) then return end
            local client = group[id]
            local reconnect = not client or not client.online or client.computerId ~= message.sender
            client = client or {inputs = {}, values = {}, revision = 0, ackedRevision = -1}
            local ioReset, ioChanged = false, false
            client.computerId, client.channel, client.lastSeen, client.online = message.sender, replyChannel, now, true
            if reconnect then client.inputs, client.values = {}, {} end
            group[id] = client
            if message.clientType == "monitor" then
                if reconnect or client.width ~= message.width or client.height ~= message.height then invalidateInput(id) end
                client.width, client.height = message.width, message.height
                client.touchProtocol = message.touchProtocol == 1
                client.lastRender = nil -- Periodic full repaint also recovers a lost frame.
            elseif message.clientType == "io" then
                ioReset = reconnect or client.announceNonce ~= nil and message.nonce <= client.announceNonce
                local previousCapabilities = client.capabilities
                client.capabilities = {}
                if type(message.capabilities) == "table" then
                    for side, flags in pairs(message.capabilities) do
                        if sideSet[side] and type(flags) == "table" and flags.bundled and flags.digital then
                            client.capabilities[side] = true
                        end
                    end
                end
                if previousCapabilities then
                    for side in pairs(sideSet) do
                        if previousCapabilities[side] ~= client.capabilities[side] then ioChanged = true end
                    end
                end
                ioChanged = ioChanged or ioReset and not reconnect
                ioReset = ioReset or ioChanged
                client.announceNonce = message.nonce
            end
            net.toClient(client, {type = "welcome", clientId = id, nonce = message.nonce, serverSession = server.session})
            if reconnect then log(message.clientType .. " connected: " .. id .. " (computer " .. message.sender .. ")") end
            if message.clientType == "io" then
                -- Routine announcements resend the same snapshot as a health
                -- check. They do not revoke an acknowledgement already earned.
                if ioReset then client.ackedRevision = -1 end
                server.syncIO(id, ioChanged)
            end
            server.refreshMonitors(false)
        elseif message.type == "inputData" then
            local client = registered(server.ioClients, message, replyChannel)
            if not client or not client.capabilities[message.side] or not integer(message.value, 0, 65535)
                or type(message.digital) ~= "boolean" then return end
            client.inputs[message.side] = {value = message.value, digital = message.digital}
            client.lastSeen = now
        elseif message.type == "ioAck" then
            local client = registered(server.ioClients, message, replyChannel)
            if client and message.revision == client.revision then
                client.ackedRevision, client.lastSeen = message.revision, now
            end
        elseif message.type == "sensorData" then
            local client = registered(server.sensorClients, message, replyChannel)
            if not client or type(message.varName) ~= "string" then return end
            local value = message.value
            if type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "boolean" then return end
            if message.varName == "playerOnline" then
                if type(value) ~= "boolean" then return end
                server.playerOnline = value
            elseif message.varName == "gameTime" then
                if type(value) ~= "string" then return end
            end
            -- Never assign arbitrary network-provided keys into OS state.
            client.values[message.varName], client.lastSeen = value, now
            if message.varName == "gameTime" then updateClock() end
        elseif message.type == "touch" then
            local client = registered(server.monitors, message, replyChannel)
            if client then
                if not client.touchProtocol or message.inputRevision == (client.inputRevision or 0) then
                    invalidateInput(id)
                    touch(id, message.x, message.y)
                else client.lastRender = nil end -- Recover a lost reply without applying an old tap twice.
                server.refreshMonitors(false)
            end
        elseif message.type == "resize" then
            local client = registered(server.monitors, message, replyChannel)
            if client and integer(message.width, 1, 256) and integer(message.height, 2, 128) then
                invalidateInput(id)
                client.width, client.height = message.width, message.height
                client.lastRender, client.lastSeen = nil, now
                server.refreshMonitors(false)
            end
        end
    end

    function server.start()
        -- A persisted boot generation prevents stale output commands after an OS reboot.
        assert(server.save(), "Cannot checkpoint OS startup")
        for _, file in ipairs(fs.list("")) do
            local name = file:match("^apps_([%w_-]+)%.lua$")
            if name and not fs.isDir(file) then
                -- Files and an old auto-populated registry are not consent to
                -- run an app. Only explicitly enabled user apps may execute.
                if config.enabledApps and config.enabledApps[name] == true then
                    local chunk, err = loadfile(file)
                    local ok, app = false, err
                    if chunk then ok, app = pcall(chunk) end
                    if ok and validApp(app) then
                        server.apps[name], state.appRegistry[name] = app, true
                        if type(state.appStates[name]) ~= "table" then state.appStates[name] = {} end
                        log("Loaded app: " .. name)
                    else log("Cannot load app " .. name .. ": " .. tostring(app)) end
                end
            end
        end
        for _, name in ipairs(sortedKeys(server.apps)) do
            if isService(server.apps[name]) or hasViews(name) then startApp(name) end
        end
        for _, name in ipairs(sortedKeys(server.systemApps)) do if hasViews(name) then startApp(name) end end
        net.ensureModem()
        log("SmartHome OS computer " .. net.id .. ", network " .. net.config.networkId)
        if not net.modem then log("Attach a wireless modem; waiting...") end
    end

    function server.tick(now)
        net.ensureModem()
        for _, group in ipairs({server.ioClients, server.monitors, server.sensorClients}) do
            for id, client in pairs(group) do
                if client.online and now - client.lastSeen >= config.clientTimeout then
                    client.online = false
                    log("Client offline: " .. id)
                    if client.values then
                        if client.values.playerOnline ~= nil then server.playerOnline = false end
                        if client.values.gameTime ~= nil then server.gameTime = "?:??" end
                    end
                end
            end
        end
        local dt = math.max(0, now - server.lastTick)
        server.lastTick = now
        updateClock()
        for name in pairs(server.running) do appCall(name, "background", dt, state.appStates[name], api) end
        for id, client in pairs(server.ioClients) do
            if client.online and client.ackedRevision ~= client.revision
                and now - (client.lastSent or -math.huge) >= config.retryInterval then server.syncIO(id, false) end
        end
        server.refreshMonitors(false)
        -- Keep checkpoints within one second even when an older config says 30.
        if now - server.lastSave >= math.min(config.saveInterval, 1) then server.save() end
    end

    function server.command(line)
        local args = {}
        for word in line:gmatch("%S+") do args[#args + 1] = word end
        local cmd = args[1]
        if not cmd then return {} end
        if cmd == "help" then return {
            "clients | inputs <client> | outputs | apps",
            "map <name> <client> <side> <color|digital>",
            "set <name> <on|off> | toggle <name>",
            "open <app> <monitor> | close <windowId>",
            "move <id> <x> <y> | resize <id> <width> <height>",
            "clear | save | quit (saves and exits)",
        } end
        if cmd == "clear" then return {}, false, "clear"
        elseif cmd == "clients" then
            local lines = {}
            for _, item in ipairs(api.getClients()) do
                lines[#lines + 1] = item.id .. " " .. item.type .. " " .. (item.online and "ONLINE" or "offline")
                    .. " computer=" .. item.computerId
            end
            if #lines == 0 then lines[1] = "No clients connected yet" end
            return lines
        elseif cmd == "outputs" then
            local lines = {}
            for _, item in ipairs(api.getOutputs()) do
                lines[#lines + 1] = item.name .. "=" .. (item.value and "ON" or "OFF") .. " -> " .. item.clientId
                    .. ":" .. item.side .. ":" .. tostring(item.color or "digital")
                    .. (item.confirmed and " confirmed" or " pending/offline")
            end
            if #lines == 0 then lines[1] = "No mappings. Use: map test io_ID left white" end
            return lines
        elseif cmd == "inputs" then
            local client = server.ioClients[args[2]]
            if not client or not client.online then return {"Client unknown or offline"} end
            local lines = {}
            for _, side in ipairs(sortedKeys(client.inputs)) do
                local input = client.inputs[side]
                lines[#lines + 1] = side .. ": bundled=" .. input.value .. " digital=" .. tostring(input.digital)
            end
            return lines
        elseif cmd == "apps" then return sortedKeys(server.apps)
        elseif cmd == "map" then
            local color = args[5] ~= "digital" and (colors[args[5] or ""] or tonumber(args[5])) or nil
            if args[5] ~= "digital" and not colour(color) then return {"Choose a CC color name/bit or digital"} end
            local ok, err = api.mapOutput(args[2], args[3], args[4], color)
            return {ok and "Mapping saved" or tostring(err)}
        elseif cmd == "set" or cmd == "toggle" then
            if not args[2] then return {"Specify an output name"} end
            if cmd == "set" and args[3] ~= "on" and args[3] ~= "off" then return {"Use set <name> on|off"} end
            local value = args[3] == "on"
            if cmd == "toggle" then value = not api.getOutput(args[2]) end
            local ok, err = api.setOutput(args[2], value)
            return {ok and "Desired state saved; use outputs to check acknowledgement" or tostring(err)}
        elseif cmd == "open" then
            local id, err = api.openApp(args[2], args[3])
            server.refreshMonitors(false)
            return {id and ("Opened window " .. id) or tostring(err)}
        elseif cmd == "close" then
            local ok, err = api.closeWindow(tonumber(args[2]))
            server.refreshMonitors(false)
            return {ok and "Window closed" or tostring(err)}
        elseif cmd == "move" or cmd == "resize" then
            local a, b = tonumber(args[3]), tonumber(args[4])
            if not a or not b then return {"Specify two positive integers"} end
            local ok, err
            if cmd == "move" then ok, err = api.placeWindow(tonumber(args[2]), a, b)
            else ok, err = api.placeWindow(tonumber(args[2]), nil, nil, a, b) end
            server.refreshMonitors(false)
            return {ok and "Window updated" or tostring(err)}
        elseif cmd == "save" or cmd == "quit" then
            local ok, err = server.save()
            return {ok and "State saved" or tostring(err)}, cmd == "quit" and ok
        end
        return {"Unknown command; type help"}
    end

    return server
end

return Server
]=],
    ["lib_io.lua"] = [=[local IO = {}
local sides = {"top", "bottom", "left", "right", "front", "back"}

local function integer(value, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= 0 and value <= high
end

function IO.new(net, config)
    assert(type(config.clientId) == "string" and #config.clientId > 0, "Invalid IO clientId")
    assert(type(config.safeOff) == "boolean", "safeOff must be boolean")
    local outputInterval = config.outputInterval or 0.6
    assert(type(outputInterval) == "number" and outputInterval >= 0.5 and outputInterval < math.huge,
        "outputInterval must be at least 0.5 seconds")
    local validSides = {}
    for _, side in ipairs(sides) do validSides[side] = true end
    for _, side in ipairs(config.sides) do assert(validSides[side], "Invalid IO side: " .. tostring(side)) end
    local client = {connected = false, nonce = 0, lastRevision = -1, appliedRevision = -1, lastAnnounce = -math.huge,
        lastInputs = -math.huge, lastServer = 0, inputs = {}}
    local outputs, targets, pendingRevision = {}, {}, nil

    local function allowed(side)
        if side == net.side then return false end
        for _, name in ipairs(config.sides) do if name == side then return true end end
        return false
    end

    local function outputState(side, now)
        if not outputs[side] then
            outputs[side] = {bundled = redstone.getBundledOutput(side), digital = redstone.getOutput(side),
                nextWrite = now + outputInterval}
        end
        return outputs[side]
    end

    local function acknowledge()
        if client.connected and client.appliedRevision >= 0 then
            net.send(net.config.channel, client.serverId, {type = "ioAck", clientId = config.clientId,
                serverSession = client.serverSession, revision = client.appliedRevision})
        end
    end

    local function flushOutputs(now)
        local complete = true
        for side, wanted in pairs(targets) do
            if allowed(side) then
                local actual = outputState(side, now)
                if now + 0.000001 >= actual.nextWrite then
                    local kind
                    -- IDT-Fix shares one cooldown between bundled and digital
                    -- writes on each side. Prefer clearing an old signal first.
                    if actual.bundled ~= wanted.bundled and wanted.bundled == 0 then kind = "bundled"
                    elseif actual.digital ~= wanted.digital and not wanted.digital then kind = "digital"
                    elseif actual.bundled ~= wanted.bundled then kind = "bundled"
                    elseif actual.digital ~= wanted.digital then kind = "digital" end
                    if kind then
                        if kind == "bundled" then redstone.setBundledOutput(side, wanted[kind])
                        else redstone.setOutput(side, wanted[kind]) end
                        actual[kind], actual.nextWrite = wanted[kind], now + outputInterval
                    end
                end
                if actual.bundled ~= wanted.bundled or actual.digital ~= wanted.digital then complete = false end
            else
                targets[side] = nil
            end
        end
        if complete then
            client.clearing = false
            if client.connected and pendingRevision ~= nil then
                client.appliedRevision, pendingRevision = pendingRevision, nil
                acknowledge()
            end
        end
    end

    function client.clearOutputs()
        local now = os.clock()
        targets, pendingRevision, client.appliedRevision, client.clearing = {}, nil, -1, true
        for _, side in ipairs(sides) do
            if allowed(side) then
                outputState(side, now)
                targets[side] = {bundled = 0, digital = false}
            end
        end
        flushOutputs(now)
    end

    function client.disconnect()
        if client.connected then print("OS disconnected; retrying") end
        client.connected = false
        client.lastAnnounce, client.appliedRevision, client.clearing = -math.huge, -1, false
        targets, pendingRevision = {}, nil
        if config.safeOff then client.clearOutputs() end
    end

    function client.announce(now)
        client.nonce = client.nonce + 1
        local capabilities = {}
        for _, side in ipairs(sides) do
            if allowed(side) then capabilities[side] = {bundled = true, digital = true} end
        end
        net.toServer({type = "announce", clientType = "io", clientId = config.clientId,
            nonce = client.nonce, capabilities = capabilities})
        client.lastAnnounce = now
    end

    function client.readInputs(force)
        if not client.connected then return end
        for _, side in ipairs(sides) do
            if allowed(side) then
                local value = redstone.getBundledInput(side)
                local digital = redstone.getInput(side)
                local previous = client.inputs[side]
                if force or not previous or previous.value ~= value or previous.digital ~= digital then
                    net.send(net.config.channel, client.serverId, {type = "inputData", clientId = config.clientId,
                        side = side, value = value, digital = digital,
                        serverSession = client.serverSession})
                    client.inputs[side] = {value = value, digital = digital}
                end
            end
        end
    end

    function client.handle(message, now)
        if message.clientId ~= config.clientId then return end
        if message.type == "welcome" then
            if message.nonce ~= client.nonce or type(message.serverSession) ~= "string" then return end
            if client.clearing then return end
            if client.connected and message.sender ~= client.serverId then return end
            local restarted = message.serverSession ~= client.serverSession
            local reconnected = not client.connected or restarted
            client.serverId, client.serverSession = message.sender, message.serverSession
            client.connected, client.lastServer = true, now
            if restarted then
                client.lastRevision, client.appliedRevision = -1, -1
                targets, pendingRevision = {}, nil
            end
            if reconnected then
                print("Connected to OS computer " .. client.serverId)
                client.readInputs(true)
            end
        elseif message.type == "ioCommand" and client.connected
            and message.sender == client.serverId and message.serverSession == client.serverSession
            and message.command == "syncOutputs" and integer(message.revision, 2147483647)
            and type(message.outputs) == "table" then
            -- Validate the entire snapshot before changing any wire.
            for side, values in pairs(message.outputs) do
                if not allowed(side) or type(values) ~= "table" or not integer(values.bundled, 65535)
                    or type(values.digital) ~= "boolean" then return end
            end
            client.lastServer = now
            if message.revision < client.lastRevision
                or (message.revision == client.appliedRevision and pendingRevision == nil) then
                acknowledge()
                return
            end
            if message.revision > client.lastRevision or pendingRevision == nil then
                targets = {}
                for side, values in pairs(message.outputs) do
                    targets[side] = {bundled = values.bundled, digital = values.digital}
                end
                client.lastRevision, pendingRevision = message.revision, message.revision
            end
            flushOutputs(now)
        end
    end

    function client.tick(now)
        local modemPresent = net.ensureModem()
        if not modemPresent then
            if client.connected then client.disconnect() end
        end
        if client.connected and now - client.lastServer >= config.timeout then client.disconnect() end
        -- Timer-driven writes keep all modem/input events flowing during cooldown.
        -- Finish startup/safe-off before accepting restored output commands.
        flushOutputs(now)
        if not modemPresent or client.clearing then return end
        if now - client.lastAnnounce >= config.announceInterval then client.announce(now) end
        if now - client.lastInputs >= config.announceInterval then
            client.readInputs(true)
            client.lastInputs = now
        end
    end

    return client
end

return IO
]=],
    ["lib_monitor.lua"] = [=[-- A display/input bridge only. All app code and hit testing stay on the OS.
local Monitor = {}
local Gui = dofile("lib_gui.lua")
local sides = {"top", "bottom", "left", "right", "front", "back"}

function Monitor.new(net, config)
    assert(type(config.clientId) == "string" and #config.clientId > 0, "Invalid monitor clientId")
    local client = {devices = {}, config = config}
    local function status(device, text)
        if device.peripheral.setBackgroundColor then device.peripheral.setBackgroundColor(32768) end
        if device.peripheral.setTextColor then device.peripheral.setTextColor(1) end
        device.peripheral.clear()
        device.peripheral.setCursorPos(1, 1)
        device.peripheral.write(text:sub(1, device.width))
        device.cache = {}
    end
    function client.scan()
        local present = {}
        for _, side in ipairs(sides) do
            if peripheral.getType(side) == "monitor" then
                present[side] = true
                local device = client.devices[side]
                local wrapped = peripheral.wrap(side)
                if not device or device.textScale ~= config.textScale then
                    if wrapped.setBackgroundColor then wrapped.setBackgroundColor(colors.black) end
                    if wrapped.setTextColor then wrapped.setTextColor(colors.white) end
                    wrapped.setTextScale(config.textScale)
                end
                local width, height = wrapped.getSize()
                if not device then
                    device = {id = config.clientId .. ":" .. side, side = side, peripheral = wrapped,
                        width = width, height = height, nonce = 0, lastAnnounce = -math.huge,
                        lastServer = 0, connected = false, textScale = config.textScale,
                        colour = (wrapped.isColor or wrapped.isColour) and (wrapped.isColor or wrapped.isColour)() or false}
                    client.devices[side] = device
                    status(device, "Connecting to SmartHome OS...")
                else
                    local oldColour = device.colour
                    device.peripheral = wrapped
                    device.textScale = config.textScale
                    device.colour = (wrapped.isColor or wrapped.isColour) and (wrapped.isColor or wrapped.isColour)() or false
                    if oldColour ~= device.colour then device.cache = {} end
                    if width ~= device.width or height ~= device.height then
                        device.width, device.height, device.lastAnnounce = width, height, -math.huge
                        device.cache = {}
                        device.inputRevision, device.hasFrame = nil, false
                    end
                end
            end
        end
        for side in pairs(client.devices) do if not present[side] then client.devices[side] = nil end end
    end
    function client.handle(message, now)
        for _, device in pairs(client.devices) do
            if message.clientId == device.id then
                if message.type == "welcome" and message.nonce == device.nonce
                    and type(message.serverSession) == "string"
                    and (not device.connected or message.sender == device.serverId) then
                    local changed = not device.connected or device.serverSession ~= message.serverSession
                    device.connected, device.lastServer = true, now
                    device.serverId, device.serverSession = message.sender, message.serverSession
                    if changed then
                        print("Monitor " .. device.side .. " connected to OS " .. message.sender)
                        device.cache = {}
                        device.frameId, device.inputRevision, device.hasFrame = nil, nil, false
                    end
                elseif message.type == "render" and device.connected
                    and message.sender == device.serverId and message.serverSession == device.serverSession
                    and message.width == device.width and message.height == device.height
                    and type(message.lines) == "table" then
                    if message.frameId and (type(message.frameId) ~= "number" or message.frameId < 1 or message.frameId ~= math.floor(message.frameId)
                        or (device.frameId and message.frameId <= device.frameId)) then return end
                    local foreground, background = {}, {}
                    local paint = {}
                    for y = 1, device.height do
                        if message.colourFormat == "rle1" then
                            foreground[y] = Gui.unpack(type(message.foreground) == "table" and message.foreground[y], device.width)
                            background[y] = Gui.unpack(type(message.background) == "table" and message.background[y], device.width)
                            if not foreground[y] or not background[y] then return end
                        else foreground[y], background[y] = string.rep("0", device.width), string.rep("f", device.width) end
                    end
                    for y = 1, device.height do
                        local line = message.lines[y]
                        if type(line) ~= "string" then line = "" end
                        line = line:sub(1, device.width)
                        line = line .. string.rep(" ", device.width - #line)
                        local signature = line .. foreground[y] .. background[y]
                        if device.cache[y] ~= signature then
                            Gui.drawRow(device.peripheral, y, line, foreground[y], background[y], device.colour, paint)
                            device.cache[y] = signature
                        end
                    end
                    device.lastServer = now
                    device.frameId, device.inputRevision = message.frameId, message.inputRevision
                    device.hasFrame = true
                end
                return
            end
        end
    end
    function client.touch(side, x, y, revision)
        local device = client.devices[side]
        if device and device.connected and device.hasFrame then
            local offset = type(config.touchOffsets) == "table" and config.touchOffsets[side] or nil
            x, y = x + (offset and offset.x or 0), y + (offset and offset.y or 0)
            net.send(net.config.channel, device.serverId, {type = "touch", clientId = device.id,
                monitorId = device.id, x = x, y = y, serverSession = device.serverSession,
                inputRevision = revision == nil and device.inputRevision or revision})
        end
    end
    function client.tick(now)
        -- CC 1.5 may not emit monitor_resize; polling also discovers late screens.
        client.scan()
        local available = net.ensureModem()
        for _, device in pairs(client.devices) do
            if device.connected and (not available or now - device.lastServer >= config.timeout) then
                device.connected = false
                status(device, "OS offline; reconnecting...")
            end
            if available and now - device.lastAnnounce >= config.announceInterval then
                device.nonce = device.nonce + 1
                net.toServer({type = "announce", clientType = "monitor", clientId = device.id,
                    nonce = device.nonce, width = device.width, height = device.height, touchProtocol = 1})
                device.lastAnnounce = now
            end
        end
    end
    function client.calibrate(side, mode)
        local device = assert(client.devices[side], "No monitor on that side")
        local w, h = device.width, device.height
        device.cache = {}
        assert(w >= 12 and h >= 8, "Calibration needs at least 12x8 characters")
        local targets = {}
        for _, y in ipairs({3, math.floor(h / 2), h - 3}) do
            for _, x in ipairs({math.max(3, math.floor(w / 6)), math.floor(w / 2), math.min(w - 2, math.floor(5 * w / 6))}) do
                targets[#targets + 1] = {x, y}
            end
        end
        local previous = config.touchOffsets and config.touchOffsets[side] or {x = 0, y = 0}
        local candidate = {x = previous.x, y = previous.y}
        local stage, last, mixed = mode == "test" and "preview" or "samples", nil, false
        local function draw(surface)
            local paint = {}
            for row = 1, h do Gui.drawRow(device.peripheral, row, surface.lines[row], surface.foreground[row], surface.background[row], device.colour, paint) end
        end
        local function event()
            while true do
                local kind, value, x, y = os.pullEvent()
                if kind == "monitor_touch" and value == side and type(x) == "number" and type(y) == "number"
                    and x == math.floor(x) and y == math.floor(y) and x >= 1 and x <= w and y >= 1 and y <= h then return "touch", x, y end
                if kind == "char" and type(value) == "string" then
                    local actions = {r = "retry", c = "cancel", q = "cancel", s = "save", ["0"] = "reset", z = "reset"}
                    if actions[value:lower()] then return actions[value:lower()] end
                elseif kind == "key" then
                    local actions = {[1] = "cancel", [203] = "left", [205] = "right", [200] = "up", [208] = "down"}
                    if actions[value] then return actions[value] end
                end
            end
        end
        local function footer(surface, first)
            local third = math.floor(w / 3)
            local labels = {w < 15 and first == "Retry" and "R" or first, w >= 15 and "Reset" or "0", w >= 18 and "Cancel" or "Exit"}
            for index, label in ipairs(labels) do
                local x, stop = (index - 1) * third + 1, index == 3 and w or index * third
                surface.fill(x, h, stop - x + 1, 1, 1, index == 3 and 16384 or index == 1 and 8192 or 128)
                surface.write(x + math.floor((stop - x + 1 - #label) / 2), h, label)
            end
        end
        local function footerAction(action, x, y, first)
            if action == "touch" and y == h then
                local third = math.floor(w / 3)
                return x <= third and first or x <= third * 2 and "reset" or "cancel"
            end
            return action
        end
        while true do
            if stage == "samples" then
                local xs, ys, interrupted = {}, {}, false
                for index, target in ipairs(targets) do
                    local surface = Gui.new(w, h, 1, 2048)
                    surface.write(1, 1, "Circle " .. index .. "/" .. #targets)
                    for row, pixels in ipairs({"01110", "10001", "01110"}) do
                        for column = 1, #pixels do
                            if pixels:sub(column, column) == "1" then
                                surface.fill(target[1] + column - 3, target[2] + row - 2, 1, 1, 1, 1)
                            end
                        end
                    end
                    surface.write(target[1], target[2], "+", 32768, 1)
                    footer(surface, "Retry"); draw(surface)
                    while true do
                        local action, x, y = event()
                        action = footerAction(action, x, y, "retry")
                        if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                        if action == "reset" then
                            candidate, last, mixed, stage, interrupted = {x = 0, y = 0}, nil, false, "preview", true; break
                        elseif action == "retry" then interrupted = true; break
                        elseif action == "touch" then
                            if math.abs(target[1] - x) <= 4 and math.abs(target[2] - y) <= 4 then
                                xs[index], ys[index] = target[1] - x, target[2] - y
                                print("Sample " .. index .. ": expected " .. target[1] .. "," .. target[2]
                                    .. "; received " .. x .. "," .. y .. "; offset " .. xs[index] .. "," .. ys[index])
                                break
                            end
                            surface.write(1, h - 1, "Tap circle centre"); draw(surface)
                        end
                    end
                    if interrupted then break end
                end
                if not interrupted then
                    table.sort(xs); table.sort(ys)
                    local dx, dy = xs[5], ys[5]
                    local consistent = math.abs(dx) <= 3 and math.abs(dy) <= 3
                    local countX, countY, totalX, totalY = 0, 0, 0, 0
                    for index = 1, #targets do
                        consistent = consistent and math.abs(xs[index] - dx) <= 1 and math.abs(ys[index] - dy) <= 1
                            and math.abs(xs[index]) <= 3 and math.abs(ys[index]) <= 3
                        countX, countY = countX + (xs[index] == dx and 1 or 0), countY + (ys[index] == dy and 1 or 0)
                        totalX, totalY = totalX + xs[index], totalY + ys[index]
                    end
                    print(string.format("Average measured X:%.2f Y:%.2f cells; median agreement X:%d/9 Y:%d/9",
                        totalX / #targets, totalY / #targets, countX, countY))
                    if consistent then
                        mixed = countX < 7 or countY < 7
                        -- A near half-cell split cannot be represented faithfully.
                        -- Do not turn an uncertain measurement into a forced 1-cell shift.
                        if countX < 7 then dx = 0 end
                        if countY < 7 then dy = 0 end
                        candidate, last, stage = {x = dx, y = dy}, nil, "preview"
                        if mixed then print("Mixed readings: testing stock on uncertain axes; no fractional touch data is available.") end
                        print("Test proposed offset " .. dx .. "," .. dy .. ". Arrows adjust; 0 resets; S saves; R remeasures; C cancels.")
                    else stage = "retry" end
                end
            elseif stage == "retry" then
                local surface = Gui.new(w, h, 1, 32768)
                surface.write(1, 1, "Calibration needs retry", 1, 16384)
                surface.write(1, 2, "Taps differ too much")
                surface.write(1, 3, "Old offset kept")
                surface.write(1, 4, "R:retry 0:reset C:exit")
                footer(surface, "Retry"); draw(surface)
                print("Samples differ too much. Retry, Reset or Cancel; previous offset is unchanged.")
                local action, x, y = event()
                action = footerAction(action, x, y, "retry")
                if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                if action == "retry" then stage = "samples"
                elseif action == "reset" then candidate, last, mixed, stage = {x = 0, y = 0}, nil, false, "preview" end
            else
                local surface = Gui.new(w, h, 1, 2048)
                surface.write(1, 1, "Test before saving", 1, 128)
                surface.write(1, 2, "X:" .. candidate.x .. " Y:" .. candidate.y .. "  S:save")
                local points = {}
                for _, y in ipairs({3, 3 + math.floor((h - 6) / 2), h - 3}) do
                    for _, x in ipairs({2, math.floor(w / 2), w - 1}) do
                        surface.write(x, y, "+", 32768, 1); points[x .. ":" .. y] = true
                    end
                end
                if last then
                    local x, y = last.x + candidate.x, last.y + candidate.y
                    if x >= 1 and x <= w and y >= 3 and y <= h - 3 then
                        surface.write(x, y, "X", 1, points[x .. ":" .. y] and 8192 or 16384)
                    end
                end
                local arrows, quarter = {" < ", " > ", " ^ ", " v "}, math.floor(w / 4)
                for index, label in ipairs(arrows) do
                    local x = (index - 1) * quarter + 1
                    surface.fill(x, h - 2, index == 4 and w - x + 1 or quarter, 1, 1, 128)
                    surface.write(x, h - 2, label)
                end
                surface.write(1, h - 1, mixed and "Mixed readings: test!" or "R:remeasure 0:stock")
                footer(surface, "Save"); draw(surface)
                local action, x, y = event()
                action = footerAction(action, x, y, "save")
                if action == "touch" and y == h - 2 then
                    action = ({"left", "right", "up", "down"})[math.min(4, math.floor((x - 1) / quarter) + 1)]
                end
                if action == "save" then return {x = candidate.x, y = candidate.y} end
                if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                if action == "retry" then stage = "samples"
                elseif action == "reset" then candidate, last, mixed = {x = 0, y = 0}, nil, false
                elseif action == "left" then candidate.x = math.max(-3, candidate.x - 1)
                elseif action == "right" then candidate.x = math.min(3, candidate.x + 1)
                elseif action == "up" then candidate.y = math.max(-3, candidate.y - 1)
                elseif action == "down" then candidate.y = math.min(3, candidate.y + 1)
                elseif action == "touch" and y >= 3 and y <= h - 3 then last = {x = x, y = y} end
            end
        end
    end
    function client.showStatus(side, text)
        status(assert(client.devices[side], "No monitor on that side"), text)
    end
    return client
end
return Monitor
]=],
    ["main_os.lua"] = [=[-- Start from / with: main_os.lua
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Server = dofile("lib_server.lua")
local Console = dofile("lib_console.lua")
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_os.txt", {
    saveFile = "configs_os_state.txt", tickInterval = 0.5,
    saveInterval = 1, clientTimeout = 15, retryInterval = 2, enabledApps = {},
})
assert(type(config.enabledApps) == "table", "Invalid enabledApps setting")
for _, name in ipairs({"tickInterval", "saveInterval", "clientTimeout", "retryInterval"}) do
    assert(type(config[name]) == "number" and config[name] > 0, "Invalid OS setting: " .. name)
end
local console = Console.new(term)
local net = Network.new(networkConfig, true, console.log)
local server = Server.new(net, storage, config, console.log)
server.start()
console.log("Type help for commands; clear clears this console")

-- The bottom-row editor owns its cursor independently of asynchronous logs.
-- Network/timer events continue while commands are being edited.
parallel.waitForAny(function()
    local timer = os.startTimer(config.tickInterval)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        if event == "modem_message" then
            local message = net.receive(p1, p2, p3, p4)
            if message then server.handle(message, p3, os.clock()) end
        elseif event == "timer" and p1 == timer then
            server.tick(os.clock())
            timer = os.startTimer(config.tickInterval)
        elseif event == "peripheral" or event == "peripheral_detach" then
            net.peripheralChanged(p1)
        end
    end
end, function()
    while true do
        local line = console.handle(os.pullEvent())
        if line ~= nil then
            local lines, quit, action = server.command(line)
            if action == "clear" then console.clear() end
            for _, output in ipairs(lines) do console.log(output) end
            if quit then console.finish(); return end
        end
    end
end)
]=],
    ["clients_io_client.lua"] = [=[-- Run from the computer root. Configs survive program updates.
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local IO = dofile("lib_io.lua")
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_io.txt", {
    clientId = "io_" .. os.getComputerID(), sides = Network.sides,
    announceInterval = 5, timeout = 15, safeOff = true, outputInterval = 0.6,
})
assert(type(config.announceInterval) == "number" and config.announceInterval >= 1, "Invalid announceInterval")
assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid timeout")
assert(type(config.sides) == "table", "Invalid IO sides")
local net = Network.new(networkConfig, false)
local client = IO.new(net, config)
net.ensureModem()
client.clearOutputs()
print("IO client: " .. config.clientId .. " (computer " .. net.id .. ")")
if not net.modem then print("Attach a wireless modem; waiting...") end
client.tick(os.clock())
local timer = os.startTimer(0.1)
while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" then
        local message = net.receive(p1, p2, p3, p4)
        if message then client.handle(message, os.clock()) end
    elseif event == "redstone" then
        client.readInputs(false)
    elseif event == "timer" and p1 == timer then
        client.tick(os.clock())
        timer = os.startTimer(0.1)
    elseif event == "peripheral" or event == "peripheral_detach" then
        net.peripheralChanged(p1)
        if not net.modem then client.disconnect() end
        client.lastAnnounce = -math.huge
        client.tick(os.clock())
    end
end
]=],
    ["clients_monitor_client.lua"] = [=[local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Monitor = dofile("lib_monitor.lua")
local args = {...}
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_monitor.txt", {
    clientId = "monitor_" .. os.getComputerID(), textScale = 0.5,
    announceInterval = 5, timeout = 15,
    touchOffsets = {},
})
assert(type(config.textScale) == "number" and config.textScale >= 0.5 and config.textScale <= 5
    and config.textScale * 2 == math.floor(config.textScale * 2), "Invalid textScale")
assert(type(config.announceInterval) == "number" and config.announceInterval >= 1, "Invalid announceInterval")
assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid timeout")
assert(type(config.touchOffsets) == "table", "Invalid touchOffsets")
for _, offset in pairs(config.touchOffsets) do
    assert(type(offset) == "table" and type(offset.x) == "number" and type(offset.y) == "number"
        and offset.x == math.floor(offset.x) and offset.y == math.floor(offset.y)
        and math.abs(offset.x) <= 3 and math.abs(offset.y) <= 3, "Invalid touch offset")
end
local net = Network.new(networkConfig, false)
local client = Monitor.new(net, config)
print("Monitor client: " .. config.clientId)
client.scan()
if args[1] then
    local usage = "Usage: clients_monitor_client.lua calibrate [side] [--reset|--test]"
    assert(args[1] == "calibrate" and not args[4], usage)
    local side, mode
    for index = 2, #args do
        if args[index] == "--reset" or args[index] == "--test" then assert(not mode, usage); mode = args[index]
        else assert(not side and client.devices[args[index]], usage); side = args[index] end
    end
    side = side or next(client.devices)
    assert(side, "Attach a monitor first")
    print("Calibrating " .. side .. "; stock offset is X:0 Y:0")
    print("Measurement uses nine circles; aim at each centre from your usual viewing position")
    print("Preview: arrows adjust, 0 resets, S saves, R remeasures, C cancels")
    local offset, err
    if mode == "--reset" then offset = {x = 0, y = 0}
    else offset, err = client.calibrate(side, mode == "--test" and "test" or nil) end
    local saved = false
    if offset then
        local previous = config.touchOffsets[side]
        config.touchOffsets[side] = offset
        local ok, saveError = storage.save("configs_monitor.txt", config)
        if ok then saved, err = true, "Saved touch offset: x=" .. offset.x .. " y=" .. offset.y
        else config.touchOffsets[side], err = previous, "Cannot save calibration: " .. tostring(saveError) end
    end
    print(err)
    client.showStatus(side, saved and "Calibration saved; reboot" or offset and "Calibration not saved; reboot" or "Calibration cancelled; reboot")
    print("Reboot to return to the monitor client")
    return
end
if not next(client.devices) then print("Attach one or more monitors; waiting...") end
client.tick(os.clock())
local timer = os.startTimer(1)
local function process(item)
    local event, p1, p2, p3, p4 = unpack(item)
    if event == "modem_message" then
        local message = net.receive(p1, p2, p3, p4)
        if message then client.handle(message, os.clock()) end
    elseif event == "monitor_touch" then
        client.touch(p1, p2, p3, p4)
    elseif event == "timer" then
        client.tick(os.clock())
    elseif event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then
        if event ~= "monitor_resize" then net.peripheralChanged(p1) end
        client.tick(os.clock())
    end
end
-- Keep input/modem events while native drawing or peripheral calls yield. Each
-- tap retains the UI revision visible when it arrived, not the revision after a repaint.
local pending, head = {}, 1
parallel.waitForAny(function()
    while true do
        local item = {os.pullEvent()}
        local event, keep = item[1], false
        if event == "monitor_touch" then
            local device = client.devices[item[2]]
            if device and device.connected and device.hasFrame then
                item[5], keep = device.inputRevision or 0, true
            end
        elseif event == "timer" and item[2] == timer then
            timer, keep = os.startTimer(1), true
        elseif event == "modem_message" or event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then keep = true end
        if keep then pending[#pending + 1] = item; os.queueEvent("smarthome_monitor_work") end
    end
end, function()
    while true do
        if head <= #pending then
            local item = pending[head]
            pending[head], head = false, head + 1
            process(item)
            if head > #pending then pending, head = {}, 1 end
        else os.pullEvent("smarthome_monitor_work") end
    end
end)
]=],
}
local args = {...}
local role, autorun = args[1], false
local entry = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua"}
print("SmartHome installer: bundled-v14")
local appUsage = "Usage: inst app NAME [--ref REF] | inst app NAME PASTE_ID | inst app NAME --file PATH"
if not entry[role] and role ~= "app" then
    print("Usage: inst server|io|monitor [--startup]")
    print(appUsage)
    return
end
assert(shell.dir() == "", "Run cd / first")
local files
if role == "app" then
    local name, source = args[2], args[3]
    assert(type(name) == "string" and name:match("^[%w_-]+$"), "Specify a simple app name without .lua")
    assert(not source and not args[4]
        or (source == "--file" or source == "--ref") and args[4] and not args[5]
        or source and source:match("^%w+$") and not args[4], appUsage)
    local github = source == nil or source == "--ref"
    local ref = source == "--ref" and args[4] or "main"
    assert(not github or ref:match("^[%w_./-]+$") and not ref:find("..", 1, true)
        and ref:sub(1, 1) ~= "/" and ref:sub(-1) ~= "/", "Invalid GitHub branch or commit")
    assert(fs.exists("main_os.lua") and fs.exists("lib_server.lua"), "Install apps on the central OS computer")
    local path = "apps_" .. name .. ".lua"
    local contents
    if github then
        assert(http and type(http.get) == "function", "HTTP is disabled; GitHub app downloads need HTTP enabled")
        local url = "https://raw.githubusercontent.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/" .. ref .. "/" .. path
        print("Downloading " .. path .. " from GitHub (" .. ref .. ")")
        local function download(address)
            -- A child coroutine catches native request errors without preventing
            -- http.get from yielding on Lua 5.1. Terminate still aborts the install.
            local request = coroutine.create(function() return http.get(address) end)
            local result = {coroutine.resume(request)}
            while result[1] and coroutine.status(request) ~= "dead" do
                result = {coroutine.resume(request, os.pullEvent(result[2]))}
            end
            if not result[1] then return nil, "Request error: " .. tostring(result[2]) end
            local response = result[2] or result[4] -- Newer CC may return an error handle.
            if not response then return nil, tostring(result[3] or "No response; CC supplied no reason") end
            -- Reading/closing response handles does not yield, unlike http.get.
            local ok, code, body = pcall(function()
                return response.getResponseCode and response.getResponseCode() or 200, response.readAll()
            end)
            local closed, closeError = pcall(response.close)
            if not ok then return nil, "Cannot read response: " .. tostring(code) end
            if not closed then return nil, "Cannot close response: " .. tostring(closeError) end
            if code ~= 200 then return nil, "GitHub returned HTTP " .. tostring(code) end
            if not result[2] then return nil, tostring(result[3] or "HTTP request failed") end
            if type(body) ~= "string" or #body == 0 then return nil, "Empty app source" end
            return body
        end
        local function checkLua(body)
            if body == nil then return nil end
            local chunk, err = loadstring(body, path)
            if not chunk then return nil, "Invalid app Lua: " .. tostring(err) end
            return body
        end
        local function apiSource(body)
            -- Read only GitHub's known base64 content field; no JSON API or
            -- execution of downloaded text is needed on old ComputerCraft.
            if not body:match('"type"%s*:%s*"file"') or not body:match('"encoding"%s*:%s*"base64"')
                or body:match('"name"%s*:%s*"([^"]*)"') ~= path then
                return nil, "GitHub API did not return the requested base64 file"
            end
            local encoded = body:match('"content"%s*:%s*"([^"]*)"')
            if not encoded then return nil, "GitHub API response has no file content" end
            encoded = encoded:gsub("\\n", ""):gsub("\\r", ""):gsub("\\/", "/"):gsub("%s", "")
            local padding = encoded:match("=*$")
            local data = encoded:sub(1, #encoded - #padding)
            if #encoded % 4 ~= 0 or #padding > 2 or data:find("[^A-Za-z0-9+/]") then
                return nil, "Invalid base64 in GitHub API response"
            end
            local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local output, value, bits = {}, 0, 0
            for index = 1, #data do
                value, bits = value * 64 + alphabet:find(data:sub(index, index), 1, true) - 1, bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    output[#output + 1] = string.char(math.floor(value / 2 ^ bits))
                    value = value % 2 ^ bits
                end
            end
            local decoded = table.concat(output)
            if value ~= 0 or tonumber(body:match('"size"%s*:%s*(%d+)')) ~= #decoded then
                return nil, "GitHub API file size/encoding mismatch"
            end
            if #decoded == 0 then return nil, "Empty app source" end
            return decoded
        end
        local rawError, apiError, body
        local apiUrl = "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/"
            .. path .. "?ref=" .. ref
        body, apiError = download(apiUrl)
        if body then contents, apiError = apiSource(body) end
        if contents then contents, apiError = checkLua(contents) end
        if contents then
            print("Downloaded via GitHub API")
        else
            print("GitHub API failed; trying raw download")
            contents, rawError = download(url)
            if contents then contents, rawError = checkLua(contents) end
            if not contents then
                print("Raw: " .. tostring(rawError))
                print("API: " .. tostring(apiError))
                print("No response from both? Ask the server admin to check GitHub HTTPS access and the Java/server log.")
                error("GitHub app download failed; installed files were not changed", 0)
            end
            print("Downloaded via GitHub raw")
        end
    elseif source == "--file" then
        local file = assert(fs.open(args[4], "r"), "Cannot read app source: " .. args[4])
        contents = file.readAll(); file.close()
    else
        local temporary = path .. ".download"
        if fs.exists(temporary) then fs.delete(temporary) end
        assert(shell.run("pastebin", "get", source, temporary) and fs.exists(temporary), "Pastebin app download failed")
        local file = assert(fs.open(temporary, "r"), "Cannot read downloaded app")
        contents = file.readAll(); file.close()
        fs.delete(temporary)
    end
    assert(type(contents) == "string" and #contents > 0, "Empty app source")
    local chunk, err = loadstring(contents, path)
    assert(chunk, "Invalid app Lua: " .. tostring(err))
    -- Read settings without resetting them or executing the app at install time.
    local storageChunk = assert(loadstring(sources["lib_storage.lua"], "lib_storage.lua"))
    setfenv(storageChunk, getfenv(1))
    local storage = storageChunk()
    local configPath = "configs_os.txt"
    local settings = storage.load(configPath)
    if not settings then
        for _, suffix in ipairs({"", ".tmp", ".bak"}) do
            assert(not fs.exists(configPath .. suffix), "Unreadable OS settings")
        end
        settings = {}
    end
    if settings.enabledApps == nil then settings.enabledApps = {} end
    assert(type(settings.enabledApps) == "table", "Invalid enabledApps setting")
    settings.enabledApps[name] = true -- Explicit app installation opts this app in.
    sources[path], sources[configPath] = contents, textutils.serialize(settings)
    files = {path, configPath}
else
    for index = 2, #args do
        assert(args[index] == "--startup", "Usage: inst server|io|monitor [--startup]")
        autorun = true
    end
    files = {"lib_storage.lua", "lib_network.lua"}
    if role ~= "io" then files[#files + 1] = "lib_gui.lua" end
    if role == "server" then
        files[#files + 1] = "lib_console.lua"
        files[#files + 1] = "lib_settings.lua"
        files[#files + 1] = "lib_io_picker.lua"
        files[#files + 1] = "lib_desktop.lua"
        files[#files + 1] = "lib_server.lua"
    elseif role == "io" then files[#files + 1] = "lib_io.lua"
    else files[#files + 1] = "lib_monitor.lua" end
    files[#files + 1] = entry[role]
    if autorun then
        sources.startup = 'shell.setDir("/")\nshell.run("' .. entry[role] .. '")\n'
        files[#files + 1] = "startup"
    end
end
if role ~= "app" then
    -- Upgrade old folder-based installations without resetting IDs, apps or state.
    -- Existing flat files take precedence; old files remain recovery copies.
    local storageChunk = assert(loadstring(sources["lib_storage.lua"], "lib_storage.lua"))
    setfenv(storageChunk, getfenv(1))
    local storage = storageChunk()
    local function existsAny(path)
        return fs.exists(path) or fs.exists(path .. ".tmp") or fs.exists(path .. ".bak")
    end
    local function addFile(path, contents)
        sources[path] = contents
        for _, present in ipairs(files) do if present == path then return end end
        files[#files + 1] = path
    end
    local function readTable(path)
        local value = storage.load(path)
        assert(value or not existsAny(path), "Unreadable saved data: " .. path)
        return value
    end
    local function migrate(target, legacy)
        if existsAny(target) then return readTable(target), false end
        if not existsAny(legacy) then return nil, false end
        local value = assert(readTable(legacy))
        addFile(target, textutils.serialize(value))
        print("Migrating " .. legacy .. " to " .. target)
        return value, true
    end
    migrate("configs_network.txt", "Configs/network.txt")
    if role == "io" then migrate("configs_io.txt", "Configs/io.txt")
    elseif role == "monitor" then migrate("configs_monitor.txt", "Configs/monitor.txt")
    else
        local settings, migrated = migrate("configs_os.txt", "Configs/os.txt")
        local legacyState = settings and settings.saveFile or "Configs/os_state.txt"
        assert(type(legacyState) == "string", "Invalid saved state path")
        migrate("configs_os_state.txt", legacyState)
        if settings then
            if settings.saveFile and settings.saveFile ~= "configs_os_state.txt" then
                settings.saveFile = "configs_os_state.txt"
                addFile("configs_os.txt", textutils.serialize(settings))
            end
            if migrated then
                assert(settings.enabledApps == nil or type(settings.enabledApps) == "table", "Invalid enabledApps setting")
                for name, enabled in pairs(settings.enabledApps or {}) do
                    if enabled == true then
                        assert(type(name) == "string" and name:match("^[%w_-]+$"), "Invalid enabled app name")
                        local path, oldPath = "apps_" .. name .. ".lua", "Apps/" .. name .. ".lua"
                        if not fs.exists(path) and fs.exists(oldPath) then
                            local file = assert(fs.open(oldPath, "r"), "Cannot read legacy app: " .. oldPath)
                            local contents = file.readAll(); file.close()
                            addFile(path, contents)
                            print("Migrating enabled app: " .. name)
                        end
                    end
                end
            end
        end
    end
end
-- Check every file before replacing any installed program.
for _, path in ipairs(files) do
    local contents = assert(sources[path], "Missing bundled file: " .. path)
    if path:match("%.lua$") or path == "startup" then
        local chunk, err = loadstring(contents, path)
        assert(chunk, "Invalid Lua: " .. path .. ": " .. tostring(err))
    else assert(type(textutils.unserialize(contents)) == "table", "Invalid settings: " .. path) end
end
for _, path in ipairs(files) do
    assert(not path:find("/", 1, true), "Install targets must be root filenames")
    local file = assert(fs.open(path .. ".download", "w"), "Cannot stage " .. path)
    file.write(sources[path])
    file.close()
end
for _, path in ipairs(files) do
    if fs.exists(path) then
        if fs.exists(path .. ".pre_update") then fs.delete(path .. ".pre_update") end
        fs.move(path, path .. ".pre_update")
    end
    fs.move(path .. ".download", path)
    print("Installed " .. path)
end
if role == "app" then
    print("Installed and enabled user app: " .. args[2])
    print("Restart the central OS to load it")
    return
end
print("Installed " .. role .. " from the bundled files")
if autorun then
    print("Autorun enabled; an existing startup is kept as startup.pre_update")
    print("Run reboot to start automatically")
else print("Autorun unchanged; add --startup to enable it") end
print("Start with: " .. entry[role])
