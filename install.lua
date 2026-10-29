-- SmartHome OS installer: bundled-v6
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

function Network.new(config, isServer)
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
                        print("Wireless modem: " .. side .. ", channel " .. net.listenChannel)
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
        for i, name in ipairs(colorNames) do list[#list + 1] = {label = name, value = 2 ^ (i - 1)} end
    end
    return list
end

local function colorName(value)
    if not value then return "Digital" end
    for i, name in ipairs(colorNames) do if value == 2 ^ (i - 1) then return name end end
    return "Invalid color"
end

function Picker.render(dialog, width, height, clients)
    local lines, hits = {}, {}
    local half = math.floor(width / 2)
    local function text(row, value) lines[row] = tostring(value):sub(1, width) end
    local function button(row, x1, x2, label, action, value)
        local line = lines[row] or string.rep(" ", width)
        label = label:sub(1, x2 - x1 + 1)
        lines[row] = line:sub(1, x1 - 1) .. label .. line:sub(x1 + #label)
        hits[#hits + 1] = {y = row, x1 = x1, x2 = x2, action = action, value = value}
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
        text(1, titles[dialog.stage])
        local list, slots = choices(dialog, clients), math.max(1, height - 3)
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.min(dialog.page, pages)
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then button(row + 1, 1, width, item.label, "select", item.value) end
        end
        if #list == 0 then text(2, "No IO clients") end
        button(height - 1, 1, half, "< Prev", "prev")
        button(height - 1, half + 1, width, "Next >", "next", pages)
        button(height, 1, half, "Back", "back")
        button(height, half + 1, width, "Cancel", "cancel")
    end
    dialog.hits = hits
    return lines
end

function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do
        if hit.y == y and x >= hit.x1 and x <= hit.x2 then
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
local function clamp(value, low, high) return math.max(low, math.min(value, high)) end

function Desktop.area(monitor)
    return {x = 1, y = 1, width = monitor.width, height = monitor.height - 1}
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

function Desktop.zone(mode, monitor)
    local area = Desktop.area(monitor)
    local left, top = math.floor(area.width / 2), math.floor(area.height / 2)
    local zones = {
        maximize = {1, 1, area.width, area.height},
        left = {1, 1, left, area.height}, right = {left + 1, 1, area.width - left, area.height},
        top = {1, 1, area.width, top}, bottom = {1, top + 1, area.width, area.height - top},
        top_left = {1, 1, left, top}, top_right = {left + 1, 1, area.width - left, top},
        bottom_left = {1, top + 1, left, area.height - top},
        bottom_right = {left + 1, top + 1, area.width - left, area.height - top},
    }
    local z = zones[mode]
    if z then return {x = z[1], y = z[2], width = z[3], height = z[4]} end
end

function Desktop.layoutOptions(win, app, monitor)
    local options = {{label = "Maximize", value = "maximize"}, {label = "Restore", value = "restore"},
        {label = "Left half", value = "left"}, {label = "Right half", value = "right"},
        {label = "Top half", value = "top"}, {label = "Bottom half", value = "bottom"},
        {label = "Top-left qtr", value = "top_left"}, {label = "Top-right qtr", value = "top_right"},
        {label = "Bottom-left", value = "bottom_left"}, {label = "Bottom-right", value = "bottom_right"},
        {label = "Custom area", value = "custom"}, {label = "Move", value = "move"}, {label = "Cancel", value = "cancel"}}
    for _, item in ipairs(options) do
        if item.value == "restore" then item.enabled = win.layout ~= nil and win.layout ~= "normal"
        elseif item.value == "custom" or item.value == "move" or item.value == "cancel" then item.enabled = true
        else item.enabled = Desktop.fits(Desktop.zone(item.value, monitor), app, monitor) end
    end
    return options
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
        local label = "[" .. marker .. win.appName .. "]"
        if #label > 14 then label = label:sub(1, 13) .. "]" end
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
        if #label > limit then label = label:sub(1, limit - 1) .. "]" end
        put(x, label, last); hit(x, x + #label - 1, "window", windows[index].id)
        x, finalVisible = x + #label + 1, index
    end
    if overflow and finalVisible < #windows then
        put(last + 1, ">"); hit(last + 1, last + 1, "next")
    end
    return line, hits
end

-- Shared paginated popup geometry for the launcher and window layout menus.
function Desktop.menu(monitor, title, items, page)
    local area = Desktop.area(monitor)
    local width = math.min(area.width, 26)
    local height = math.min(area.height, math.max(4, #items + 3))
    local slots = math.max(1, height - 3)
    local pages = math.max(1, math.ceil(#items / slots))
    page = clamp(page or 1, 1, pages)
    local rect = {x = 1, y = area.height - height + 1, width = width, height = height}
    local lines, hits = {}, {}
    for y = 1, height do lines[y] = "|" .. string.rep(" ", math.max(0, width - 2)) .. "|" end
    lines[1] = ("+" .. title .. string.rep("-", width)):sub(1, width - 1) .. "+"
    lines[height] = "+" .. string.rep("-", math.max(0, width - 2)) .. "+"
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then
            local label = (item.enabled == false and "-" or " ") .. item.label
            lines[row + 1] = "|" .. label:sub(1, width - 2) .. string.rep(" ", math.max(0, width - 2 - #label)) .. "|"
            hits[#hits + 1] = {x1 = rect.x + 1, x2 = rect.x + width - 2, y = rect.y + row,
                action = "item", item = item}
        end
    end
    if #items == 0 then lines[2] = "|" .. ("No apps"):sub(1, width - 2) .. string.rep(" ", math.max(0, width - 9)) .. "|" end
    if pages > 1 then
        local half = math.floor((width - 2) / 2)
        lines[height - 1] = "|" .. ("< Prev" .. string.rep(" ", width)):sub(1, half)
            .. ("Next >" .. string.rep(" ", width)):sub(1, width - 2 - half) .. "|"
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

function Server.new(net, storage, config)
    local loaded, source = storage.load(config.saveFile, validState)
    local state = loaded or {}
    for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if type(state[name]) ~= "table" then state[name] = {} end
    end
    local server = {state = state, monitors = {}, ioClients = {}, sensorClients = {}, apps = {},
        gameTime = "?:??", playerOnline = false, lastSave = 0, lastTick = os.clock(), views = {}, dialogs = {}, running = {}}
    local api, errors = {}, {}
    server.api = api
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
    if source and source ~= config.saveFile then print("Recovered state from " .. source) end
    if not loaded and fs.exists(config.saveFile) then print("Unreadable OS state; starting with defaults") end

    function server.save()
        local saved = {}
        for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides",
            "nextWindowId", "bootCounter", "desktops", "desktopVersion"}) do saved[name] = state[name] end
        local ok, err = storage.save(config.saveFile, saved)
        if not ok then print("State save failed: " .. tostring(err)) else server.lastSave = os.clock() end
        return ok, err
    end
    api.save = server.save

    local function appCall(name, hook, ...)
        local app = server.apps[name]
        if not app or not app[hook] then return true end
        local ok, a, b = pcall(app[hook], ...)
        if not ok then
            local key = name .. "." .. hook
            if errors[key] ~= a then print("App " .. key .. " failed: " .. tostring(a)); errors[key] = a end
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
        if server.running[name] and not isService(server.apps[name]) and not hasViews(name) then
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
                print("IO " .. clientId .. ": mapped side " .. side .. " is unavailable")
                snapshot[side] = nil
            end
        end
        net.toClient(client, {type = "ioCommand", command = "syncOutputs", clientId = clientId,
            serverSession = server.session, revision = client.revision, outputs = snapshot})
        client.lastSent = os.clock()
    end

    function api.mapOutput(name, clientId, side, color, initialValue)
        if type(name) ~= "string" or not name:match("^[%w_-]+$")
            or type(clientId) ~= "string" or clientId == "" or not sideSet[side]
            or (color ~= nil and not colour(color))
            or (initialValue ~= nil and type(initialValue) ~= "boolean") then return false, "Invalid output mapping" end
        local client = server.ioClients[clientId]
        if client and client.online and not client.capabilities[side] then
            return false, "That side is unavailable (possibly occupied by the modem)"
        end
        for other, mapping in pairs(state.outputMap) do
            if other ~= name and mapping.clientId == clientId and mapping.side == side
                and mapping.color == color then return false, "Wire already mapped to " .. other end
        end
        local previous, oldManaged, previousValue = state.outputMap[name], copy(state.managedSides), state.outputs[name]
        state.outputMap[name] = {clientId = clientId, side = side, color = color}
        if initialValue ~= nil then state.outputs[name] = initialValue end
        state.managedSides[clientId] = state.managedSides[clientId] or {}
        state.managedSides[clientId][side] = true
        if previous then
            state.managedSides[previous.clientId] = state.managedSides[previous.clientId] or {}
            state.managedSides[previous.clientId][previous.side] = true
        end
        local ok, err = server.save()
        if not ok then
            state.outputMap[name], state.managedSides, state.outputs[name] = previous, oldManaged, previousValue
            return false, err
        end
        if previous and previous.clientId ~= clientId then server.syncIO(previous.clientId, true) end
        server.syncIO(clientId, true)
        return true
    end

    function api.setOutput(name, value)
        local mapping = state.outputMap[name]
        if not mapping then return false, "Unknown output: " .. tostring(name) end
        if type(value) ~= "boolean" then return false, "Output value must be boolean" end
        local previous = state.outputs[name]
        state.outputs[name] = value
        -- Commit desired state before commanding hardware; failed writes are visible.
        local ok, err = server.save()
        if not ok then state.outputs[name] = previous; return false, err end
        server.syncIO(mapping.clientId, true)
        return true
    end

    function api.getOutput(name) return state.outputs[name] == true end
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
        local app = server.apps[win.appName]
        if not app or not app.handleIOSelection then return false, "App has no IO selection handler" end
        server.dialogs[windowId] = Picker.new(key, direction, current)
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
        local app = server.apps[win.appName]
        if not app then win.doesNotFit = true; return false end
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
        local app = server.apps[name]
        local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
        return app.render and maxW >= minW and maxH >= minH
    end
    local function discardSmallDialog(win)
        if win.width < 14 or win.height < 8 then server.dialogs[win.id] = nil end
    end

    function api.openApp(name, monitorId, x, y, width, height)
        local app, monitor = server.apps[name], server.monitors[monitorId]
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
        if not server.apps[win.appName] then return false, "App is not available" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        local previous = copy(win)
        if mode ~= "restore" and win.layout == mode then return true end
        if mode == "restore" then
            local restore = win.restore or {layout = "normal", relative = win.relative}
            win.layout, win.relative, win.restore = restore.layout, copy(restore.relative), nil
        else
            local rect = Desktop.zone(mode, monitor)
            if not Desktop.fits(rect, server.apps[win.appName], monitor) then return false, "Layout does not fit this app" end
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
        local lines = {}
        for y = 1, monitor.height do lines[y] = string.rep(" ", monitor.width) end
        local function write(x, y, text, limit)
            if y < 1 or y > monitor.height or x < 1 or x > monitor.width then return end
            text = tostring(text or ""):sub(1, math.min(limit or monitor.width, monitor.width - x + 1))
            lines[y] = lines[y]:sub(1, x - 1) .. text .. lines[y]:sub(x + #text)
        end
        write(1, 1, "SmartHome OS")
        local active
        for _, win in ipairs(windowsFor(id)) do
            if fit(win, monitor) and not win.minimized and server.running[win.appName] then
                active = win.id
                local title = ("[X][#][_] " .. win.appName):sub(1, win.width)
                write(win.x, win.y, title .. string.rep("-", win.width - #title), win.width)
                for y = win.y + 1, win.y + win.height - 2 do
                    write(win.x, y, "|" .. string.rep(" ", win.width - 2) .. "|")
                end
                write(win.x, win.y + win.height - 1, "+" .. string.rep("-", win.width - 2) .. "+")
                local ok, content
                if server.dialogs[win.id] then
                    ok, content = true, Picker.render(server.dialogs[win.id], win.width - 2, win.height - 2, api.getIOClients())
                else
                    ok, content = appCall(win.appName, "render", win.width - 2, win.height - 2,
                        state.appStates[win.appName], api, viewContext(win))
                end
                if not ok or type(content) ~= "table" then content = {"App render failed"} end
                for y = 1, win.height - 2 do write(win.x + 1, win.y + y, content[y] or "", win.width - 2) end
            end
        end
        local taskbar
        taskbar, monitor.taskbar = Desktop.taskbar(windowsFor(id, true), monitor, server.gameTime, desktopState(id), active)
        write(1, monitor.height, taskbar)
        if monitor.launcher or monitor.layoutMenu then
            local items, title, model
            if monitor.launcher then
                model, title, items = monitor, "Apps", {}
                for _, name in ipairs(sortedKeys(server.apps)) do
                    if compatible(name, monitor) then
                        items[#items + 1] = {label = name .. (server.running[name] and " *" or ""), value = name, enabled = true}
                    end
                end
                if #items == 0 then
                    items[1] = {label = next(server.apps) and "No apps fit" or "No apps installed", enabled = false}
                end
            else
                model, title = monitor.layoutMenu, monitor.layoutMenu.error or "Layout"
                local win = state.windows[model.windowId]
                items = win and Desktop.layoutOptions(win, server.apps[win.appName], monitor) or {}
            end
            local rect, content, hits, page, pages = Desktop.menu(monitor, title, items, model.menuPage)
            model.menuPage, model.menuPages, model.menuHits = page, pages, hits
            for row = 1, rect.height do write(rect.x, rect.y + row - 1, content[row], rect.width) end
        end
        local placement = monitor.placement
        if placement then
            local rect = placement.preview
            if rect then
                local mark = placement.error and "!" or "#"
                write(rect.x, rect.y, string.rep(mark, rect.width), rect.width)
                if rect.height > 1 then write(rect.x, rect.y + rect.height - 1, string.rep(mark, rect.width), rect.width) end
                for y = rect.y + 1, rect.y + rect.height - 2 do
                    write(rect.x, y, mark); write(rect.x + rect.width - 1, y, mark)
                end
            end
            if placement.first then write(placement.first.x, placement.first.y, "+") end
            local hint = placement.error or (rect and "OK to apply" or placement.kind == "move" and "Pick position"
                or placement.first and "Other corner" or "First corner")
            if rect and not placement.error then hint = "OK: " .. rect.width .. "x" .. rect.height end
            write(1, 1, hint .. string.rep(" ", monitor.width))
            write(1, monitor.height, "[OK][Cancel]" .. string.rep(" ", math.max(0, monitor.width - 12)))
        end
        return lines
    end

    function server.refreshMonitors(force)
        for id, monitor in pairs(server.monitors) do
            if monitor.online then
                local lines = renderMonitor(id, monitor)
                local signature = table.concat(lines, "\n")
                if force or signature ~= monitor.lastRender then
                    if net.toClient(monitor, {type = "render", clientId = id, monitorId = id,
                        serverSession = server.session, lines = lines, width = monitor.width, height = monitor.height}) then
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
                    if not Desktop.fits(rect, server.apps[win.appName], monitor) then
                        placement.valid, placement.error = false, "Does not fit"; return
                    end
                    local ok, err = api.placeWindow(win.id, rect.x, rect.y, rect.width, rect.height)
                    if ok then monitor.placement = nil else placement.error = tostring(err) end
                end
                return
            end
            if placement.kind == "move" then
                placement.preview = {x = math.max(1, math.min(x, monitor.width - win.width + 1)),
                    y = math.max(1, math.min(y, monitor.height - win.height)), width = win.width, height = win.height}
            elseif not placement.first then placement.first = {x = x, y = y}
            else
                placement.preview = {x = math.min(x, placement.first.x), y = math.min(y, placement.first.y),
                    width = math.abs(x - placement.first.x) + 1, height = math.abs(y - placement.first.y) + 1}
            end
            placement.valid = Desktop.fits(placement.preview, server.apps[win.appName], monitor) and true or false
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
                if y == hit.y and x >= hit.x1 and x <= hit.x2 then
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
                            if mode == "custom" or mode == "move" then beginPlacement(monitor, win, mode)
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
                    local relative = x - win.x
                    if relative < 3 then api.closeWindow(win.id)
                    elseif relative < 6 then
                        focus(win); monitor.layoutMenu = {windowId = win.id, menuPage = 1}; server.save()
                    elseif relative < 9 then win.minimized = true; server.save()
                    else focus(win); beginPlacement(monitor, win, "move"); server.save() end
                    return
                end
                focus(win)
                if x > win.x and x < win.x + win.width - 1 and y < win.y + win.height - 1 then
                    local dialog = server.dialogs[win.id]
                    if dialog then
                        local action, address = Picker.touch(dialog, x - win.x, y - win.y)
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
                    print("Duplicate clientId rejected: " .. id .. " (computer " .. message.sender .. ")")
                    return
                end
            end
            if message.clientType == "monitor" and (not integer(message.width, 1, 256)
                or not integer(message.height, 2, 128)) then return end
            local client = group[id]
            local reconnect = not client or not client.online or client.computerId ~= message.sender
            client = client or {inputs = {}, values = {}, revision = 0, ackedRevision = -1}
            client.computerId, client.channel, client.lastSeen, client.online = message.sender, replyChannel, now, true
            if reconnect then client.inputs, client.values = {}, {} end
            group[id] = client
            if message.clientType == "monitor" then
                client.width, client.height = message.width, message.height
                client.lastRender = nil -- Periodic full repaint also recovers a lost frame.
            elseif message.clientType == "io" then
                client.capabilities = {}
                if type(message.capabilities) == "table" then
                    for side, flags in pairs(message.capabilities) do
                        if sideSet[side] and type(flags) == "table" and flags.bundled and flags.digital then
                            client.capabilities[side] = true
                        end
                    end
                end
            end
            net.toClient(client, {type = "welcome", clientId = id, nonce = message.nonce, serverSession = server.session})
            if reconnect then print(message.clientType .. " connected: " .. id .. " (computer " .. message.sender .. ")") end
            if message.clientType == "io" then
                client.ackedRevision = -1
                server.syncIO(id, false)
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
            if registered(server.monitors, message, replyChannel) then
                touch(id, message.x, message.y)
                server.refreshMonitors(false)
            end
        elseif message.type == "resize" then
            local client = registered(server.monitors, message, replyChannel)
            if client and integer(message.width, 1, 256) and integer(message.height, 2, 128) then
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
                        print("Loaded app: " .. name)
                    else print("Cannot load app " .. name .. ": " .. tostring(app)) end
                end
            end
        end
        for _, name in ipairs(sortedKeys(server.apps)) do
            if isService(server.apps[name]) or hasViews(name) then startApp(name) end
        end
        net.ensureModem()
        print("SmartHome OS computer " .. net.id .. ", network " .. net.config.networkId)
        if not net.modem then print("Attach a wireless modem; waiting...") end
    end

    function server.tick(now)
        net.ensureModem()
        for _, group in ipairs({server.ioClients, server.monitors, server.sensorClients}) do
            for id, client in pairs(group) do
                if client.online and now - client.lastSeen >= config.clientTimeout then
                    client.online = false
                    print("Client offline: " .. id)
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
            "save | quit (saves and exits)",
        } end
        if cmd == "clients" then
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
local sides = {"top", "bottom", "left", "right", "front", "back"}

function Monitor.new(net, config)
    assert(type(config.clientId) == "string" and #config.clientId > 0, "Invalid monitor clientId")
    local client = {devices = {}}
    local function status(device, text)
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
                        lastServer = 0, connected = false, textScale = config.textScale}
                    client.devices[side] = device
                    status(device, "Connecting to SmartHome OS...")
                else
                    device.peripheral = wrapped
                    device.textScale = config.textScale
                    if width ~= device.width or height ~= device.height then
                        device.width, device.height, device.lastAnnounce = width, height, -math.huge
                        device.cache = {}
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
                    end
                elseif message.type == "render" and device.connected
                    and message.sender == device.serverId and message.serverSession == device.serverSession
                    and message.width == device.width and message.height == device.height
                    and type(message.lines) == "table" then
                    for y = 1, device.height do
                        local line = message.lines[y]
                        if type(line) ~= "string" then line = "" end
                        line = line:sub(1, device.width)
                        line = line .. string.rep(" ", device.width - #line)
                        if device.cache[y] ~= line then
                            device.peripheral.setCursorPos(1, y)
                            device.peripheral.write(line)
                            device.cache[y] = line
                        end
                    end
                    device.lastServer = now
                end
                return
            end
        end
    end
    function client.touch(side, x, y)
        local device = client.devices[side]
        if device and device.connected then
            net.send(net.config.channel, device.serverId, {type = "touch", clientId = device.id,
                monitorId = device.id, x = x, y = y, serverSession = device.serverSession})
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
                    nonce = device.nonce, width = device.width, height = device.height})
                device.lastAnnounce = now
            end
        end
    end
    return client
end
return Monitor
]=],
    ["main_os.lua"] = [=[-- Start from / with: main_os.lua
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Server = dofile("lib_server.lua")
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_os.txt", {
    saveFile = "configs_os_state.txt", tickInterval = 0.5,
    saveInterval = 1, clientTimeout = 15, retryInterval = 2, enabledApps = {},
})
assert(type(config.enabledApps) == "table", "Invalid enabledApps setting")
for _, name in ipairs({"tickInterval", "saveInterval", "clientTimeout", "retryInterval"}) do
    assert(type(config[name]) == "number" and config[name] > 0, "Invalid OS setting: " .. name)
end
local net = Network.new(networkConfig, true)
local server = Server.new(net, storage, config)
server.start()
print("Type help for commands")

-- parallel gives the console and network independent event queues. read() cannot
-- discard modem/timer events needed by the server, and there is no sleep in it.
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
        write("> ")
        local lines, quit = server.command(read())
        for _, line in ipairs(lines) do print(line) end
        if quit then return end
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
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_monitor.txt", {
    clientId = "monitor_" .. os.getComputerID(), textScale = 0.5,
    announceInterval = 5, timeout = 15,
})
assert(type(config.textScale) == "number" and config.textScale >= 0.5 and config.textScale <= 5
    and config.textScale * 2 == math.floor(config.textScale * 2), "Invalid textScale")
assert(type(config.announceInterval) == "number" and config.announceInterval >= 1, "Invalid announceInterval")
assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid timeout")
local net = Network.new(networkConfig, false)
local client = Monitor.new(net, config)
print("Monitor client: " .. config.clientId)
client.scan()
if not next(client.devices) then print("Attach one or more monitors; waiting...") end
client.tick(os.clock())
local timer = os.startTimer(1)
while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" then
        local message = net.receive(p1, p2, p3, p4)
        if message then client.handle(message, os.clock()) end
    elseif event == "monitor_touch" then
        client.touch(p1, p2, p3)
    elseif event == "timer" and p1 == timer then
        client.tick(os.clock())
        timer = os.startTimer(1)
    elseif event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then
        if event ~= "monitor_resize" then net.peripheralChanged(p1) end
        client.scan()
        client.tick(os.clock())
    end
end
]=],
}
local args = {...}
local role, autorun = args[1], false
local entry = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua"}
print("SmartHome installer: bundled-v6")
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
        -- http.get may yield on CC 1.5: do not call it inside pcall.
        local response, downloadError = http.get(url)
        assert(response, "GitHub app download failed; check the repository file and HTTP access: "
            .. tostring(downloadError or url))
        local code = response.getResponseCode and response.getResponseCode() or 200
        contents = response.readAll(); response.close()
        assert(code == 200, "GitHub returned HTTP " .. tostring(code) .. " for " .. path)
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
    if role == "server" then
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
