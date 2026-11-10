-- SmartHome OS installer: bundled-v41
-- Flat-root layout: lib_*, clients_*, apps_*, configs_*.
-- Upload this ONE file to Pastebin. All role files are included below.
-- Usage: inst server|io|monitor|sensor|relay [--startup]
-- User apps: inst app NAME [--ref BRANCH_OR_COMMIT] (GitHub)
-- Alternatives: inst app NAME PASTE_ID   or   inst app NAME --file PATH
-- OS/client installation is offline. Apps are fetched only on request.
local sources = {
    ["lib_work.lua"] = [=[-- Cooperative central work, portable to Lua 5.1 and legacy LuaJ.
-- One serial worker owns OS state; the event collector remains responsive.
local existing = rawget(_G, "__smarthomeWork")
if existing then return existing end
local Work = {stage = "Starting OS", yields = 0}
local parents, owner, pause, budget, spent, diagnostics = {}, nil, nil, 16384, 0, nil
local function pack(...) return {n = select("#", ...), ...} end
local function active()
    local thread = coroutine.running()
    while thread do
        if thread == owner then return pause ~= nil end
        thread = parents[thread]
    end
    return false
end
function Work.isWatchdog(err)
    return tostring(err):lower():find("too long without yielding", 1, true) ~= nil
end
function Work.protect(fn, ...)
    local thread = coroutine.create(fn)
    parents[thread] = coroutine.running()
    local args = pack(...)
    while true do
        local result = pack(coroutine.resume(thread, unpack(args, 1, args.n)))
        if not result[1] or coroutine.status(thread) == "dead" then
            parents[thread] = nil
            if not result[1] and Work.isWatchdog(result[2]) then
                Work.report(Work.stage, result[2])
            end
            return unpack(result, 1, result.n)
        end
        args = pack(coroutine.yield(unpack(result, 2, result.n)))
    end
end
function Work.call(fn, ...)
    if active() then return Work.protect(fn, ...) end
    return pcall(fn, ...)
end
function Work.enable(callback, limit, reportOptions)
    owner, pause, budget, spent = coroutine.running(), callback, limit or 16384, 0
    diagnostics = reportOptions
end
function Work.disable() owner, pause, spent, parents, diagnostics = nil, nil, 0, {}, nil end
function Work.check(cost)
    if not pause or not active() then return end
    spent = spent + (cost or 1)
    if spent >= budget then
        spent = 0; Work.yields = Work.yields + 1
        pause()
    end
end
-- Serialize plain saved data in small steps. Repeated references are rejected,
-- matching old CraftOS, and output remains readable by textutils.unserialize.
function Work.serialize(value)
    if not pause or not active() then return textutils.serialize(value) end
    local parts, seen = {}, {}
    local function write(item)
        local kind = type(item)
        Work.check(16)
        if kind == "string" then
            parts[#parts + 1] = string.format("%q", item); Work.check(#item)
        elseif kind == "number" then
            assert(item == item and math.abs(item) < math.huge, "Cannot serialize non-finite number")
            parts[#parts + 1] = tostring(item)
        elseif kind == "boolean" or kind == "nil" then parts[#parts + 1] = tostring(item)
        else
            assert(kind == "table", "Cannot serialize " .. kind)
            assert(not seen[item], "Cannot serialize table with recursive entries")
            seen[item] = true; parts[#parts + 1] = "{"
            for key, child in pairs(item) do
                parts[#parts + 1] = "["; write(key); parts[#parts + 1] = "]="
                write(child); parts[#parts + 1] = ","
            end
            parts[#parts + 1] = "}"
        end
    end
    write(value)
    return table.concat(parts)
end
function Work.report(stage, err, reportOptions)
    local options = reportOptions or diagnostics
    local path = options and options.path or "diagnostics_os_error.txt"
    local message = (options and options.title or "SmartHome OS error") .. "\nStage: " .. tostring(stage or Work.stage)
        .. "\nError: " .. tostring(err) .. "\n"
    message = message:sub(1, 16384)
    if Work.lastReportPath == path and Work.lastReport == message then return true end
    local ok = pcall(function()
        local file = assert(fs.open(path .. ".tmp", "w"), "Cannot write OS error report")
        file.write(message); file.close()
        if fs.exists(path) then fs.delete(path) end
        fs.move(path .. ".tmp", path)
    end)
    if ok then Work.lastReport, Work.lastReportPath = message, path end
    return ok
end
rawset(_G, "__smarthomeWork", Work)
return Work
]=],
    ["lib_storage.lua"] = [=[-- Lua 5.1 / ComputerCraft 1.5. Only plain, serializable data belongs here.
local storage = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local validatedContents = {}

local function readTable(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local file = fs.open(path, "r")
    if not file then return nil end
    local contents = file.readAll()
    file.close()
    local ok, value = pcall(textutils.unserialize, contents)
    if ok and type(value) == "table" then validatedContents[path] = contents; return value end
end

function storage.load(path, validate)
    for _, candidate in ipairs({path, path .. ".tmp", path .. ".bak"}) do
        local value = readTable(candidate)
        if value and (not validate or validate(value)) then return value, candidate end
    end
end

function storage.save(path, value, forgetPrevious)
    -- An interrupted reset must never be recovered as an ordinary pending save.
    local staged = path .. (forgetPrevious and ".reset" or ".tmp")
    local movedPrevious = false
    local ok, err = Work.call(function()
        local contents = Work.serialize(value)
        -- fs.getDir was only added in CC 1.63; Tekkit Lite uses older CC.
        local dir = path:match("^(.*)/[^/]+$") or ""
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local file = assert(fs.open(staged, "w"), "Cannot write " .. path)
        file.write(contents)
        file.close()
        if fs.exists(path) then
            -- Compare with the last validated/written bytes before parsing the
            -- entire old state again. External corruption still gets checked.
            local oldFile = fs.open(path, "r")
            local previous = oldFile and oldFile.readAll()
            if oldFile then oldFile.close() end
            if previous and previous == validatedContents[path] or readTable(path) then
                if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
                fs.move(path, path .. ".bak")
                movedPrevious = true
            else
                -- A corrupt primary must not replace a good backup.
                fs.delete(path)
            end
        end
        fs.move(staged, path)
        validatedContents[path] = contents
    end)
    if forgetPrevious then
        if not ok then
            pcall(fs.delete, staged)
            if movedPrevious and not fs.exists(path) then pcall(fs.move, path .. ".bak", path) end
        else
            local cleared, cleanupError = pcall(function()
                for _, suffix in ipairs({".tmp", ".bak"}) do
                    if fs.exists(path .. suffix) then fs.delete(path .. suffix) end
                end
            end)
            if not cleared then err = "Reset saved. Recovery cleanup failed: " .. tostring(cleanupError) end
        end
    end
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
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local sides = {"top", "bottom", "left", "right", "front", "back"}
local protocol = "SmartHomeOS/1"
local relayChannel = 65533

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= low and value <= high
end

local function replyFor(id, serverChannel)
    local channel = 1000 + (id % 40000)
    return channel == serverChannel and 41001 or channel
end

local function validPath(path, sender)
    if type(path) ~= "table" then return false end
    local seen, count, length = {}, 0, #path
    for index, hop in pairs(path) do
        count = count + 1
        if not integer(index, 1, length) or type(hop) ~= "table"
            or not integer(hop.computerId, 0, 2147483647)
            or type(hop.id) ~= "string" or #hop.id < 1 or #hop.id > 64
            or hop.computerId == sender or seen[hop.computerId] then return false end
        seen[hop.computerId] = true
        Work.check(24)
    end
    return count == length
end

local function transportValid(packet, reply, config)
    local t = packet._transport
    if type(t) ~= "table" or t.version ~= 1 or t.serverChannel ~= config.channel
        or not integer(t.boot, 1, 2147483647) or not integer(t.sequence, 1, 2147483647)
        or not integer(t.channel, 1, 65532) or not validPath(t.path, packet.sender) then return false end
    if t.channel == config.channel then
        return reply == replyFor(packet.sender, config.channel)
            and (config.serverId == nil or packet.recipient == nil or packet.recipient == config.serverId)
    end
    return packet.recipient ~= nil and t.channel == replyFor(packet.recipient, config.channel)
        and reply == config.channel and (config.serverId == nil or packet.sender == config.serverId)
end

local function packetKey(packet)
    local t = packet._transport
    return tostring(packet.sender) .. ":" .. t.boot .. ":" .. t.sequence
end

-- A fixed ring suppresses copies in constant time, even after a quiet period
-- when many old entries expire at once. Actual retries have fresh packet IDs.
function Network.newCache(limit, lifetime)
    local entries, slots, nextSlot = {}, {}, 1
    return function(key, now)
        local known = entries[key]
        if known and now - known.at < lifetime then return false end
        local previous = slots[nextSlot]
        if previous and entries[previous.key] == previous then entries[previous.key] = nil end
        local entry = {key = key, at = now}
        slots[nextSlot], entries[key] = entry, entry
        nextSlot = nextSlot % limit + 1
        return true
    end
end

-- CraftOS 1.5 probes the modem before checking whether a packet can be
-- Rednet traffic. Filter the two eligible channels in its private API
-- environment, before the expensive lookup. Every SmartHome role uses this.
local function filterLegacyRednet(id)
    local version = type(os.version) == "function" and os.version()
    if type(version) ~= "string" or version:match("^%a+OS (%d+%.%d+)") ~= "1.5" then return false end
    if type(rednet) ~= "table" or type(rednet.run) ~= "function" or type(getfenv) ~= "function" then return false end
    local ok, env = pcall(getfenv, rednet.run)
    if not ok or type(env) ~= "table" or env == _G or rawget(env, "run") ~= rednet.run then return false end
    local original = env.os
    if type(original) ~= "table" or type(original.pullEventRaw) ~= "function"
        or rawget(env, "__smarthomeRednetOS") == original or rednet.CHANNEL_BROADCAST ~= 65535 then return false end

    local privateOS = setmetatable({}, {__index = original})
    function privateOS.pullEventRaw(filter)
        if filter ~= "modem_message" then return original.pullEventRaw(filter) end
        while true do
            local event, side, channel, reply, payload, distance = original.pullEventRaw(filter)
            if event ~= "modem_message" or channel == id or channel == 65535 then
                return event, side, channel, reply, payload, distance
            end
        end
    end
    rawset(env, "os", privateOS)
    rawset(env, "__smarthomeRednetOS", privateOS)
    return true
end

function Network.new(config, isServer, logger)
    local log = logger or print
    assert(type(config.networkId) == "string" and #config.networkId > 0,
        "Set networkId in configs_network.txt")
    assert(integer(config.channel, 1, 65532), "Invalid network channel")
    assert(config.serverId == nil or integer(config.serverId, 0, 2147483647),
        "serverId must be a computer ID")
    assert(config.relayEnabled == nil or type(config.relayEnabled) == "boolean", "Invalid relayEnabled setting")
    local storage = dofile("lib_storage.lua")
    local path = "configs_transport.txt"
    local boot = storage.config(path, {bootCounter = 0})
    assert(integer(boot.bootCounter, 0, 2147483646), "Invalid transport boot counter")
    boot.bootCounter = boot.bootCounter + 1
    assert(storage.save(path, boot), "Cannot checkpoint network startup")
    local net = {id = os.getComputerID(), config = config, isServer = isServer}
    if filterLegacyRednet(net.id) then log("CraftOS 1.5 Rednet channel filter active") end
    -- Destination IDs still disambiguate computers if reply channels collide.
    net.replyChannel = replyFor(net.id, config.channel)
    net.listenChannel = isServer and config.channel or net.replyChannel
    net.relayChannel, net.sequence = relayChannel, 0
    local remember = Network.newCache(4096, 60)

    function net.ensureModem()
        if net.modem then return true end
        for _, side in ipairs(sides) do
            if peripheral.getType(side) == "modem" then
                local modem = peripheral.wrap(side)
                -- isWireless is absent in some early versions; channels are required.
                if modem and modem.transmit and modem.open
                    and (not modem.isWireless or modem.isWireless()) then
                    local ok = pcall(function()
                        modem.open(net.listenChannel)
                        if config.relayEnabled ~= false then modem.open(relayChannel) end
                    end)
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
        if net.sequence >= 2147483647 then return false end
        net.sequence = net.sequence + 1
        local packet = {}
        for key, value in pairs(message) do packet[key] = value end
        packet.protocol, packet.networkId = protocol, config.networkId
        packet.sender, packet.recipient = net.id, targetId
        packet._route = nil
        packet._transport = {version = 1, boot = boot.bootCounter, sequence = net.sequence,
            serverChannel = config.channel, channel = channel, path = {}}
        local raw = Work.serialize(packet)
        -- Leave headroom for routes; forwarding still checks CC's 64 KiB wire cap.
        if #raw > 61440 then return false end
        local ok = pcall(function()
            net.modem.transmit(channel, net.listenChannel, raw)
            if config.relayEnabled ~= false then net.modem.transmit(relayChannel, net.listenChannel, raw) end
        end)
        if not ok then net.modem, net.side = nil, nil end
        return ok
    end

    function net.toServer(message)
        return net.send(config.channel, config.serverId, message)
    end

    function net.toClient(client, message)
        return net.send(client.channel, client.computerId, message)
    end

    local function decode(side, channel, replyChannel, raw, relay)
        local relayed = channel == relayChannel
        if side ~= net.side or (relayed and config.relayEnabled == false)
            or (not relayed and channel ~= net.listenChannel) then return nil end
        if not integer(replyChannel, 1, 65532) or type(raw) ~= "string"
            or #raw > 65536 then return nil end
        if relay then Work.stage = "Decoding relay packet (" .. #raw .. " bytes)" end
        Work.check(#raw)
        local ok, packet = pcall(textutils.unserialize, raw)
        if not ok then
            if (relay or isServer) and Work.isWatchdog(packet) then
                Work.report(Work.stage, packet)
                Work.check(16384)
            end
            return nil
        end
        if type(packet) ~= "table" or packet.protocol ~= protocol
            or packet.networkId ~= config.networkId
            or not integer(packet.sender, 0, 2147483647)
            or packet.sender == net.id or type(packet.type) ~= "string"
            or packet.recipient ~= nil and not integer(packet.recipient, 0, 2147483647) then return nil end
        if packet._transport ~= nil and not transportValid(packet, replyChannel, config) then return nil end
        if relayed and packet._transport == nil then return nil end
        Work.check(#raw)
        return packet
    end

    function net.forward(packet, replyChannel, id)
        if not net.ensureModem() then return false end
        local t = packet._transport
        if not t then return false end
        for _, hop in ipairs(t.path) do if hop.computerId == net.id then return false end end
        t.path[#t.path + 1] = {id = id, computerId = net.id}
        packet._route = nil
        Work.stage = "Encoding relay packet from computer " .. packet.sender
        local encoded, raw = Work.call(Work.serialize, packet)
        if not encoded then
            if Work.isWatchdog(raw) then Work.check(16384) end
            return false
        end
        if #raw > 65536 then return false end
        local ok = pcall(net.modem.transmit, relayChannel, replyChannel, raw)
        if not ok then net.modem, net.side = nil, nil end
        return ok
    end

    local function accept(packet, replyChannel)
        if not packet then return nil end
        local t = packet._transport
        if t and t.channel ~= net.listenChannel then return nil end
        if packet.recipient ~= nil and packet.recipient ~= net.id then return nil end
        if not isServer then
            if packet.recipient ~= net.id or replyChannel ~= config.channel then return nil end
            if config.serverId and packet.sender ~= config.serverId then return nil end
        else
            local expected = replyFor(packet.sender, config.channel)
            if replyChannel ~= expected then return nil end
        end
        if t and not remember(packetKey(packet), os.clock()) then return nil end
        packet._route = {}
        for _, hop in ipairs(t and t.path or {}) do
            packet._route[#packet._route + 1] = {id = hop.id, computerId = hop.computerId}
            Work.check(24)
        end
        return packet
    end

    function net.receive(side, channel, replyChannel, raw)
        return accept(decode(side, channel, replyChannel, raw), replyChannel)
    end

    function net.receiveForRelay(side, channel, replyChannel, raw)
        local packet = decode(side, channel, replyChannel, raw, true)
        return accept(packet, replyChannel), channel == relayChannel and packet or nil
    end

    return net
end

Network.sides = sides
Network.integer = integer
Network.packetKey, Network.relayChannel = packetKey, relayChannel
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
    ["lib_gui.lua"] = [==[-- CC 1.5 colour surfaces. Uses write/setTextColor/setBackgroundColor, never blit.
local Gui = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local digits = "0123456789abcdef"
local names = {"White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray",
    "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
local nextBank = {[0] = 1, [1] = 2, [2] = 0, abc = "ABC", ABC = "123", ["123"] = "abc"}
local bankName = {[0] = "abc", [1] = "ABC", [2] = "123", abc = "abc", ABC = "ABC", ["123"] = "123"}
-- Shift applies to one accepted letter, consistently across all app keyboards.
function Gui.typeKey(keyboard, key, limit)
    if type(key) ~= "string" or #keyboard.draft >= limit then return false end
    keyboard.draft = keyboard.draft .. key
    if key:match("^[A-Z]$") then
        if keyboard.bank == 1 then keyboard.bank = 0
        elseif keyboard.bank == "ABC" then keyboard.bank = "abc" end
    end
    return true
end
function Gui.editText(keyboard, action, value, limit)
    if action == "key" then Gui.typeKey(keyboard, value, limit)
    elseif action == "space" then Gui.typeKey(keyboard, " ", limit)
    elseif action == "backspace" then keyboard.draft = keyboard.draft:sub(1, -2)
    elseif action == "clearText" then keyboard.draft = ""
    elseif action == "bank" then keyboard.bank, keyboard.page = nextBank[keyboard.bank] or 0, 1
    elseif action == "keyPage" then keyboard.page = keyboard.page % keyboard.pages + 1
    else return false end
    return true
end

function Gui.actionAt(hits, x, y)
    for _, hit in ipairs(hits) do
        if hit.enabled ~= false and Gui.hit(hit, x, y) then return hit.action, hit.value end
    end
end

-- Keep every completed choice visible; shorten long IDs rather than losing
-- the final side/target. Small windows keep their existing usable row count.
function Gui.breadcrumb(parts,width,height)
    if width<24 or height<8 then return nil end
    local values={}
    for _,value in ipairs(parts) do if value and value~="" then values[#values+1]=tostring(value):gsub("[%c]"," ") end end
    if #values==0 then return nil end
    if #table.concat(values," / ")>width then
        local budget=math.max(1,math.floor((width-3*(#values-1))/#values))
        for i,value in ipairs(values) do if #value>budget then values[i]=value:sub(1,math.max(0,budget-2))..".." end end
    end
    return table.concat(values," / "):sub(1,width)
end
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
    for y = 1, height do ui.lines[y] = string.rep(" ", width); Work.check(width) end
    function ui.style(x, y, w, h, fg, bg)
        ui.lines.styles[#ui.lines.styles + 1] = {x = x, y = y, width = w, height = h, fg = fg, bg = bg}
        Work.check(w * h)
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
    ui.heading(title or "UI color", 128)
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
local letterRows = {"qwertyuiop", "asdfghjkl", "zxcvbnm"}
local symbols = [=[1234567890-_/.:!?+()@#&=,%*'"$^[]{}<>\|;`~]=]
function Gui.keyboard(ui, width, height, k, accent, footer)
    local columns = math.min(10, math.floor(width / 2))
    local mode = bankName[k.bank] or "abc"
    local chars = k.symbols or symbols
    local pages = mode == "123" and math.ceil(#chars / (columns * 3)) or math.ceil(10 / columns)
    k.page, k.pages = math.max(1, math.min(k.page or 1, pages)), pages
    ui.heading(k.draft == "" and "Type here" or k.draft:sub(-width), accent)
    local keyWidth = math.floor(width / columns)
    local gap, rowGap = width >= 30 and 1 or 0, height >= 10 and 1 or 0
    local available = height - 3 + rowGap
    for row = 1, 3 do
        local start = (k.page - 1) * columns + 1
        local keys = letterRows[row]:sub(start, start + columns - 1)
        if mode == "ABC" then keys = keys:upper()
        elseif mode == "123" then
            start = ((k.page - 1) * 3 + row - 1) * columns + 1
            keys = chars:sub(start, start + columns - 1)
        end
        local left = 1 + math.floor((width - #keys * keyWidth + gap) / 2)
        local y1 = 2 + math.floor((row - 1) * available / 3)
        local y2 = 1 + math.floor(row * available / 3) - rowGap
        for column = 1, #keys do
            local x1 = left + (column - 1) * keyWidth
            local span = keyWidth - gap
            local key = keys:sub(column, column)
            local bg = (row + column) % 2 == 0 and 128 or 256
            ui.style(x1, y1, span, y2 - y1 + 1, Gui.contrast(bg), bg)
            ui.button(math.floor((y1 + y2) / 2), key, "key", x1, x1 + span - 1, true, bg, nil, key)
            local hit = ui.hits[#ui.hits]
            hit.y1, hit.y2 = y1, y2
        end
    end
    local controls = {{bankName[nextBank[k.bank]] or "ABC", "bank"},
        {width >= 20 and "Space" or "Sp", "space"}, {"Del", "backspace"}}
    if pages > 1 then controls[4] = {k.page .. "/" .. pages, "keyPage"} end
    for index, row in ipairs(controls) do
        ui.button(height - 1, row[1], row[2], 1 + math.floor((index - 1) * width / #controls),
            math.floor(index * width / #controls), true, row[2] == "bank" and accent or nil)
    end
    footer = footer or {{"Set", "saveText"}, {"Clr", "clearText"}, {"Back", k.back}}
    for index, row in ipairs(footer) do
        ui.button(height, row[1], row[2], 1 + math.floor((index - 1) * width / #footer),
            math.floor(index * width / #footer), row[4], index == 1 and accent or nil, nil, row[3])
    end
end

-- Common app forms keep drawing and hit regions together at 12x6 and above.
function Gui.form(width,height,view,accent,background,panel)
    local ui=Gui.content(width,height); view.pages=view.pages or {}
    background,panel=background or 32768,panel or 128
    ui.style(1,1,width,height,Gui.contrast(background),background)
    function ui.put(x,y,value,span,center)
        if y<1 or y>height or span<1 then return end
        local text=tostring(value):gsub("[%c]"," "):sub(1,span)
        if center then x=x+math.max(0,math.floor((span-#text)/2)) end
        ui.lines[y]=ui.lines[y]:sub(1,x-1)..text..ui.lines[y]:sub(x+#text)
    end
    function ui.action(y,text,action,value,x1,x2,enabled,bg)
        ui.button(y,text,action,x1,x2,enabled,bg or panel,nil,value)
    end
    function ui.footer(rows)
        -- A screen can replace the default Back footer supplied by info().
        for i=#ui.hits,1,-1 do if ui.hits[i].y==height then table.remove(ui.hits,i) end end
        for i,row in ipairs(rows) do ui.action(height,row[1],row[2],row[3],1+math.floor((i-1)*width/#rows),math.floor(i*width/#rows),row[4],row[5]) end
    end
    function ui.page(key,count,slots,y,draw)
        local pages=math.max(1,math.ceil(count/slots))
        local current=math.max(1,math.min(view.pages[key] or 1,pages)); view.pages[key]=current
        if pages>1 and draw~=false then
            local wing=math.max(2,math.floor(width/4))
            ui.action(y,"<","page",{key=key,page=current-1},1,wing,current>1)
            ui.action(y,">","page",{key=key,page=current+1},width-wing+1,width,current<pages)
            ui.put(wing+1,y,current.."/"..pages,width-2*wing,true)
        end
        return (current-1)*slots,current,pages
    end
    function ui.menu(title,rows,key,footer)
        ui.heading(title,accent)
        local slots=#rows<=height-2 and height-2 or height-3
        local first=ui.page(key,#rows,slots,height-1)
        for i=1,slots do local row=rows[first+i]; if row then ui.action(i+1,row[1],row[2],row[3],nil,nil,row[4],row[5]) end end
        ui.footer(footer or {{"Back","home"}})
    end
    function ui.info(title,lines,key,back)
        local wrapped={}
        for _,line in ipairs(lines) do
            line=tostring(line):gsub("[%c]"," ")
            repeat
                local cut=#line>width and line:sub(1,width):match("^.*()%s")
                if cut and cut>1 then wrapped[#wrapped+1],line=line:sub(1,cut-1),line:sub(cut+1)
                else wrapped[#wrapped+1],line=line:sub(1,width),line:sub(width+1) end
            until line==""
        end
        ui.heading(title,accent)
        local slots=#wrapped<=height-2 and height-2 or height-3
        local first=ui.page(key,#wrapped,slots,height-1)
        for i=1,slots do ui.put(1,i+1,wrapped[first+i] or "",width) end
        ui.footer({{"Back",back}})
    end
    function ui.numberPad(title,draft,back)
        ui.heading(title,accent); ui.put(1,2,draft=="" and "0" or draft,width,true)
        for i,key in ipairs({"1","2","3","4","5","6","7","8","9","Clr","0","Del"}) do
            local col,row=(i-1)%4,math.floor((i-1)/4)
            ui.action(3+row,key,"digit",key,1+math.floor(col*width/4),math.floor((col+1)*width/4),true,accent)
        end
        ui.footer({{"Set","setNumber"},{"Back",back}})
    end
    function ui.keyboard(k)
        Gui.keyboard(ui, width, height, k, accent)
    end
    return ui
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
        Work.check(last - x + 1)
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
        Work.check(width)
    end
    local function replace(row, x, value) return row:sub(1, x - 1) .. value .. row:sub(x + #value) end
    function surface.style(x, y, w, h, fg, bg)
        local first, last = math.max(1, x), math.min(width, x + w - 1)
        if last < first then return end
        for row = math.max(1, y), math.min(height, y + h - 1) do
            local f, b = Gui.code(fg), Gui.code(bg)
            if f then surface.foreground[row] = replace(surface.foreground[row], first, string.rep(f, last - first + 1)) end
            if b then surface.background[row] = replace(surface.background[row], first, string.rep(b, last - first + 1)) end
            Work.check(last - first + 1)
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
]==],
    ["lib_me.lua"] = [=[-- Shared AE1 item identities, safe snapshots and bounded stock-rate history.
local MAX=9007199254740991
local Work=rawget(_G,"__smarthomeWork") or dofile("lib_work.lua")
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item); Work.check(8) end; return result
end
local function restore(state,old)
    local keys={}; for key in pairs(state) do keys[#keys+1]=key end
    for _,key in ipairs(keys) do state[key]=nil end
    for key,value in pairs(old) do state[key]=value end
end
local function number(v,lo,hi) return type(v)=="number" and v==v and v>=lo and v<=hi end
local function integer(v,lo,hi) return number(v,lo,hi) and v==math.floor(v) end
local function digits(v)
    v=math.floor(math.abs(v)); local out={}
    repeat local n=v%10; out[#out+1]=("0123456789"):sub(n+1,n+1); v=math.floor(v/10) until v==0
    return table.concat(out):reverse()
end
local function amount(v,width)
    if v==nil then return "--" end
    local raw=(v<0 and "-" or "")..digits(v)
    local text=digits(v):reverse():gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
    text=(v<0 and "-" or "")..text
    return width and #text>width and raw or text
end
local function rateText(v,width)
    if v==nil then return "--/h" end
    local whole=math.floor(math.abs(v))
    local tenth=math.floor((math.abs(v)-whole)*10+0.5)
    if tenth==10 then whole,tenth=whole+1,0 end
    local text=(v<0 and "-" or v>0 and "+" or "")..amount(whole).."."..digits(tenth).."/h"
    if width and #text>width then text=(v<0 and "-" or v>0 and "+" or "")..digits(whole).."/h" end
    return text
end
local function colour(v) for i=0,15 do if v==2^i then return true end end; return false end
local function textValue(v,limit) return type(v)=="string" and #v>0 and #v<=limit and not v:find("[%c]") end
local function label(v) return textValue(v,24) and v:find("%S") end
local sides={top=true,bottom=true,left=true,right=true,front=true,back=true}
local function address(v) return type(v)=="table" and textValue(v.clientId,64) and sides[v.side] and textValue(v.target,128) end
local function route(v) return type(v)=="table" and textValue(v.clientId,64) and sides[v.side] and (v.color==nil or colour(v.color)) end
local function sourceKey(v) return #v.clientId..":"..v.clientId..v.side..":"..v.target end
local function itemKey(raw,damage,name)
    local identity=raw~="" and raw~="unknown" and raw or "name:"..name
    return #identity..":"..identity..":"..digits(damage)
end
local function itemValid(v)
    return type(v)=="table" and type(v.raw)=="string" and #v.raw<=256 and not v.raw:find("[%c]")
        and textValue(v.name,256) and integer(v.damage,0,2147483647) and v.key==itemKey(v.raw,v.damage,v.name)
end
local function identity(v) return {key=v.key,raw=v.raw,damage=v.damage,name=v.name} end
local function find(list,id) for index,item in ipairs(list) do if item.id==id then return item,index end end end
local function catalog(reading)
    local data=reading.data or {}
    if reading.status~="ok" then return nil,reading.error or reading.status end
    if data.Powered==false then return nil,"ME unpowered" end
    if data.ItemsOmitted or data.ItemsComplete==false or type(data.Items)~="table" then return nil,"Waiting for complete item list" end
    if data.ItemsFormat and data.ItemsFormat~="ae_compact_v1" then return nil,"Unknown item format" end
    local compact=data.ItemsFormat=="ae_compact_v1"
    local result,seen,total={},0,0
    for _,row in pairs(data.Items) do
        Work.check(64)
        seen=seen+1
        if seen>8192 or type(row)~="table" then return nil,"Invalid item list" end
        local raw,name,damage,count
        if compact then raw,damage,name,count=row[1],row[2],row[3],row[4]
        else raw,name,damage,count=row.RawName or "",row.Name or row.RawName,row.DamageValue or row.Damagevalue or 0,row.Size end
        if type(raw)~="string" or #raw>256 or raw:find("[%c]") or type(name)~="string" or #name>256
            or not integer(damage,0,2147483647) or not integer(count,0,MAX) then return nil,"Invalid item identity/count" end
        name=name:gsub("[%c]"," "); if name=="" then name=raw~="" and raw or "Unknown item" end
        local key=itemKey(raw,damage,name)
        local item=result[key]
        if not item then item={key=key,raw=raw,damage=damage,name=name,count=0}; result[key]=item end
        if not integer(item.count+count,0,MAX) or not integer(total+count,0,MAX) then return nil,"Item count overflow" end
        item.count,total=item.count+count,total+count
        if name:lower()<item.name:lower() then item.name=name end
    end
    return result,nil,total
end

local Me={safePatterns=true,cooperativeCalls=true,protect=Work.call,MAX=MAX,copy=copy,restore=restore,number=number,integer=integer,digits=digits,amount=amount,rateText=rateText,
    colour=colour,textValue=textValue,label=label,address=address,route=route,sourceKey=sourceKey,itemKey=itemKey,
    itemValid=itemValid,identity=identity,find=find,catalog=catalog}
function Me.boots(api)
    local result={}; for _,client in ipairs(api.getSensorClients()) do result[client.id]=client.bootId end; return result
end
function Me.snapshot(cache,api,binding,boots)
    if not address(binding) then return {status="unconfigured",error="Select an ME source",items={}} end
    local key=sourceKey(binding)..":"..tostring((boots or Me.boots(api))[binding.clientId])
    -- Forget prior boot snapshots of this address. They are never fresh data and
    -- retaining many large catalogs across client restarts wastes OS memory.
    local remove={}
    for other,value in pairs(cache) do if other~=key and value.address==sourceKey(binding) then remove[#remove+1]=other end end
    for _,other in ipairs(remove) do cache[other]=nil end
    local saved=cache[key] or {key=key,items={}}
    saved.address=sourceKey(binding)
    cache[key]=saved
    local ok,reading=Work.call(api.getSensorReading,binding,{profile="ae_items"})
    if not ok or type(reading)~="table" then
        saved.status,saved.error,saved.sequence,saved.time="error","Cannot read ME: "..tostring(reading),nil,nil
        return saved
    end
    local oldStatus=saved.status
    saved.status,saved.error,saved.age=reading.status,reading.error,reading.age
    saved.sequence,saved.time=reading.sequence,reading.time
    if reading.status~="ok" then return saved end
    if reading.data and reading.data.Powered==false then saved.status,saved.error="unpowered","ME unpowered"; return saved end
    if oldStatus~="ok" or saved.dataSequence~=reading.dataSequence then
        local parsed,items,err,total=Work.call(catalog,reading)
        if not parsed or not items then saved.status,saved.error="unsupported",tostring(parsed and err or items); return saved end
        saved.items,saved.total,saved.dataSequence=items,total,reading.dataSequence
        saved.types=0; for _ in pairs(items) do saved.types=saved.types+1 end
    end
    saved.data=reading.data
    return saved
end
function Me.count(snapshot,key)
    if not snapshot or snapshot.status~="ok" or not key then return nil end
    return snapshot.items[key] and snapshot.items[key].count or 0
end
function Me.isHVSolar(item)
    if type(item)~="table" then return false end
    local function words(value)
        if type(value)~="string" then return "" end
        return value:gsub("(%u)(%u%l)","%1 %2"):gsub("(%l)(%u)","%1 %2"):lower()
    end
    local name=words(item.raw).." "..words(item.name)
    if not name:find("solar",1,true) then return false end
    local flat=name:gsub("[^%w]","")
    -- LuaJ 2.0.3's frontier matcher indexes -1 at the start of a string. Use
    -- padded words and plain finds, including for raw names such as HVSolarArray.
    local padded=" "..name:gsub("[^a-z0-9]"," "):gsub(" +"," ").." "
    return padded:find(" hv ",1,true)~=nil or flat:find("highvoltage",1,true)~=nil or flat:find("hochspannung",1,true)~=nil
end
-- Sparse minute buckets share valid coverage for every item in a complete ME
-- snapshot. Only nonzero deltas and per-item excluded intervals need records.
local Rates={}
function Rates.new() return {buckets={},keys={},nextKey=1} end
local function trim(history,time)
    while #history.buckets>0 and history.buckets[1].minute<math.floor(time/60)-59 do table.remove(history.buckets,1) end
    local used,cost={},0
    for _,bucket in ipairs(history.buckets) do
        cost=cost+80
        for id in pairs(bucket.values) do used[id]=true; cost=cost+160 end
    end
    local remove={}
    for key,id in pairs(history.keys) do
        if not used[id] then remove[#remove+1]=key else cost=cost+2*#key+100 end
    end
    for _,key in ipairs(remove) do history.keys[key]=nil end
    return cost
end
function Rates.record(history,time,dt,changes,maxInterval)
    if not number(dt,0.001,maxInterval or 10) then return false end
    trim(history,time)
    local minute=math.floor(time/60)
    local bucket=history.buckets[#history.buckets]
    if not bucket or bucket.minute~=minute then bucket={minute=minute,seconds=0,values={}}; history.buckets[#history.buckets+1]=bucket end
    bucket.seconds=bucket.seconds+dt
    for key,change in pairs(changes) do
        local id=history.keys[key]
        if not id then id=history.nextKey; history.nextKey=id+1; history.keys[key]=id end
        local row=bucket.values[id] or {0,0,0,0}; bucket.values[id]=row
        row[1]=row[1]+(change.skip and 0 or change.delta)
        if change.skip then row[2],row[3],row[4]=row[2]+dt,row[3]+1,row[4]+math.abs(change.delta) end
        if not number(row[1],-MAX,MAX) or not number(row[4],0,MAX) then
            history.buckets,history.keys,history.limited={},{},true; return false
        end
    end
    local cost=trim(history,time)
    while cost>196608 and #history.buckets>1 do table.remove(history.buckets,1); history.limited=true; cost=trim(history,time) end
    if cost>196608 then history.buckets,history.keys,history.limited={},{},true; return false end
    return true
end
function Rates.sum(history,key,time,window)
    local id=history.keys[key]
    local delta,seconds,drops,removed=0,0,0,0
    local first=math.floor(time/60)-window/60+1
    for _,bucket in ipairs(history.buckets) do if bucket.minute>=first then
        local row=id and bucket.values[id]
        seconds=seconds+bucket.seconds-(row and row[2] or 0)
        if row then delta,drops,removed=delta+row[1],drops+row[3],removed+row[4] end
    end end
    return delta,math.max(0,seconds),drops,removed
end
function Rates.valid(history)
    if type(history)~="table" or type(history.buckets)~="table" or #history.buckets>60 or type(history.keys)~="table"
        or not integer(history.nextKey,1,MAX) then return false end
    local ids={}; for key,id in pairs(history.keys) do
        if not textValue(key,600) or not integer(id,1,history.nextKey-1) or ids[id] then return false end; ids[id]=true
    end
    local last=-1
    for _,bucket in ipairs(history.buckets) do
        if type(bucket)~="table" or not integer(bucket.minute,0,MAX) or bucket.minute<=last
            or not number(bucket.seconds,0,120) or type(bucket.values)~="table" then return false end
        last=bucket.minute
        for id,row in pairs(bucket.values) do
            if not ids[id] or type(row)~="table" or not number(row[1],-MAX,MAX) or not number(row[2],0,bucket.seconds+0.001)
                or not integer(row[3],0,MAX) or not number(row[4],0,MAX) then return false end
        end
    end
    return true
end
Me.Rates=Rates
return Me
]=],
    ["lib_settings.lua"] = [=[-- Built-in settings. Destructive confirmations are kept in memory per window.
local System = dofile("lib_system.lua")
local Settings = {}

function Settings.new(actions)
    local app = {title = "Settings", minWidth = 12, minHeight = 6, preferredWidth = 34, preferredHeight = 13}
    local pending = {}

    function app.init(state)
        state.overview = type(state.overview) == "table" and state.overview or {}
        System.init(state.overview)
    end

    local function overviewContext(context)
        local view = context.view
        view.overview = view.overview or {}
        return {windowId = context.windowId, monitorId = context.monitorId, view = view.overview}
    end

    local function build(w, h, state, api, context)
        local view = context.view
        if view.section == "overview" then
            local lines = System.render(w, h, state.overview, api, overviewContext(context))
            return lines, lines.hits
        end
        local ui = api.ui.form(w, h, view, 2048)
        local section = view.section or "home"
        if section == "nameClient" or section == "nameKeyboard" then
            if type(view.nameId) ~= "string" then
                view.section, view.keyboard = "names", nil
            elseif section == "nameKeyboard" and not view.keyboard then
                view.section = "nameClient"
            end
            section = view.section
        end
        local draft = pending[context.windowId]
        if draft then
            local title = "Are you sure?"
            if draft.mode == "reset" and draft.final then title = w >= 20 and "Are you really sure?" or "Really sure?"
            elseif draft.mode == "delete" then title = "Delete app?"
            elseif draft.mode == "restore" then title = "Restore data?"
            elseif draft.mode == "backup" then title = "Replace backup?" end
            ui.heading(draft.error and "Action failed" or title, 16384)
            ui.put(1, 2, draft.label, w, true)
            local message = draft.error or draft.detail
            if message then ui.put(1, 3, message, w); ui.put(1, 4, message:sub(w + 1), w)
            elseif draft.mode == "delete" then ui.put(1, 3, "Settings kept", w, true)
            elseif draft.target == "@all" then ui.put(1, 3, "All app data", w, true); ui.put(1, 4, "OS + routes", w, true)
            elseif draft.target == "@settings" then ui.put(1, 3, "OS data + layouts", w, true)
            else ui.put(1, 3, "Data, routes", w, true); ui.put(1, 4, "and layouts", w, true) end
            if draft.mode == "reset" and draft.target == "@all" and not draft.final then
                ui.action(h - 1, "Continue", "confirmAgain", nil, nil, nil, true, 16384)
                ui.action(h, "Cancel", "cancel")
            else
                local button = draft.mode == "reset" and (draft.final and "Erase all" or "Delete data")
                    or draft.mode == "delete" and "Uninstall" or draft.mode == "backup" and "Replace" or "Restore"
                ui.action(h - 1, "Cancel", "cancel")
                ui.action(h, button, "commit", nil, nil, nil, true, 16384)
            end
        elseif section == "home" then
            ui.menu(app.title, {{"Appearance", "appearance"}, {"System overview", "overview"},
                {"Client names", "names"}, {"Screensavers", "screensavers"}, {"App data", "data"}}, "settings", {{"Close", "close"}})
        elseif section == "appearance" then
            local settings = api.getOSSettings()
            local function label(text, color) return w >= 24 and text .. " " .. api.ui.colourName(color) or text end
            ui.menu("Appearance", {{label("Background", settings.backgroundColour), "background", nil, true, settings.backgroundColour},
                {label(w >= 13 and "Window border" or "Borders", settings.windowBorderColour), "windowBorder", nil, true, settings.windowBorderColour},
                {label("Taskbar", settings.taskbarColour), "taskbar", nil, true, settings.taskbarColour}}, "appearance")
        elseif section == "screensavers" then
            local names, installed = api.getScreensavers()
            local rows = {}
            for index, name in ipairs(names) do rows[#rows + 1] = index .. ". " .. name end
            if #rows == 0 then rows[1] = installed and "Update or enable Screensaver" or "Install Screensaver to see designs" end
            ui.info("Screensavers", rows, "screensavers", "home")
        elseif section == "names" then
            local rows = {}
            for _, item in ipairs(api.getClientNameTargets()) do
                rows[#rows + 1] = {(item.online and "+ " or "- ") .. item.displayName, "nameClient", item.id}
            end
            if #rows == 0 then rows[1] = {"No known clients", nil, nil, false} end
            ui.menu("Client names", rows, "names")
        elseif section == "nameClient" then
            local id = view.nameId
            ui.info("Client name", {api.clientName(id), "ID " .. id}, "nameClient", "names")
            ui.footer({{"Back", "names"}, {"Rename", "editName"}, {"Reset", "clearName", nil, api.clientName(id) ~= id}})
        elseif section == "nameKeyboard" then ui.keyboard(view.keyboard)
        elseif section == "data" then
            ui.menu(view.status or "App data", {{"Backup & restore", "backupMenu"}, {"Reset data", "resetData"},
                {"Delete apps", "deleteApps"}}, "data")
        elseif section == "backupMenu" then
            ui.menu(view.status or "Backup & restore", {{"Create backup", "backupList"}, {"Restore backup", "restoreList"}},
                "backupMenu", {{"Back", "data"}})
        elseif section == "resetData" or section == "deleteApps" or section == "backupList" or section == "restoreList" then
            local mode = ({resetData = "reset", deleteApps = "delete", backupList = "backup", restoreList = "restore"})[section]
            local targets = mode == "delete" and actions.installed() or mode == "restore" and actions.backups() or actions.targets()
            local rows = {}
            for _, item in ipairs(targets) do rows[#rows + 1] = {item.label, "selectScope", {id = item.id, label = item.label, mode = mode}} end
            if #rows == 0 then rows[1] = {mode == "delete" and "No installed apps" or "No backups yet", nil, nil, false} end
            local title = ({reset = "Reset data", delete = "Delete apps", backup = "Create backup", restore = "Restore backup"})[mode]
            local back = (mode == "backup" or mode == "restore") and "backupMenu" or "data"
            ui.menu(view.status or title, rows, section, {{"Back", back}})
        else ui.info(app.title, {view.status or "Select an option"}, "status", view.back or "home") end
        return ui.lines, ui.hits
    end

    function app.render(w, h, state, api, context) return (build(w, h, state, api, context)) end

    function app.handleTouch(x, y, w, h, state, api, context)
        local id, view = context.windowId, context.view
        if view.section == "overview" then
            local ctx = overviewContext(context)
            local result = System.handleTouch(x, y, w, h, state.overview, api, ctx)
            if ctx.view.exit then ctx.view.exit, view.section = nil, "home" end
            return result
        end
        local _, hits = build(w, h, state, api, context)
        local action, value = api.ui.actionAt(hits, x, y)
        if not action then return false end
        if action == "page" then view.pages[value.key] = value.page
        elseif action == "close" then return api.closeWindow(id)
        elseif action == "background" or action == "windowBorder" or action == "taskbar" then return api.pickColour(id, action)
        elseif action == "nameClient" then
            if value then view.nameId = value end
            view.section, view.keyboard, view.status = "nameClient", nil, nil
        elseif action == "editName" then
            view.keyboard = {draft = api.clientName(view.nameId) ~= view.nameId and api.clientName(view.nameId) or "",
                bank = 0, page = 1, back = "nameClient"}
            view.section = "nameKeyboard"
        elseif view.section == "nameKeyboard" and api.ui.editText(view.keyboard, action, value, 32) then return true
        elseif action == "saveText" or action == "clearName" then
            local ok, err = api.setClientName(view.nameId, action == "clearName" and "" or view.keyboard.draft)
            view.section = ok and "nameClient" or "status"
            view.status, view.back = err, "nameClient"
            view.keyboard = nil
        elseif action == "selectScope" then
            local mode = value.mode
            local info = (mode == "restore" or mode == "backup") and actions.backupInfo(value.id) or nil
            if mode == "backup" and not info then
                local ok, err = actions.backup(value.id)
                view.status = ok and "Backup saved" or tostring(err)
            else pending[id] = {target = value.id, label = value.label, mode = mode, detail = info} end
        elseif action == "confirmAgain" then pending[id].final = true
        elseif action == "cancel" then pending[id] = nil
        elseif action == "commit" then
            local draft = pending[id]
            local ok, err = actions[draft.mode](draft.target)
            if ok then
                pending[id] = nil
                view.status = err or ({reset = "Data reset", delete = "App deleted", restore = "Data restored", backup = "Backup saved"})[draft.mode]
            else draft.error = tostring(err) end
        else view.section, view.status = action, nil end
        api.invalidateAppViews("@settings")
        return true
    end

    function app.onClose(state, api, context) pending[context.windowId] = nil end
    return app
end

return Settings
]=],
    ["lib_system.lua"] = [=[-- Read-only overview of the central computer and its live client registry.
local app={}
local function find(list,id) for _,item in ipairs(list or {}) do if item.id==id then return item end end end
local function join(values) return #values>0 and table.concat(values,", ") or "None" end
local function elapsed(seconds)
    seconds=math.floor(seconds or 0)
    return math.floor(seconds/3600).."h "..math.floor(seconds/60)%60 .."m "..seconds%60 .."s"
end
local function route(address,api)
    return api.clientName(address.clientId).." / "..address.side.." / "..(address.color and api.ui.colourName(address.color) or "Digital")
end
function app.init(state)
    if not ({all=true,io=true,monitor=true,sensor=true,relay=true})[state.filter] then state.filter="all" end
end
local function build(width,height,state,api,context)
    local view=context.view; view.pages=view.pages or {}
    local screen=view.screen or "home"
    local d=api.getDiagnostics()
    local ui,accent=api.ui.content(width,height),api.getAppColour("@settings")
    ui.style(1,1,width,height,1,32768)
    local function button(y,label,action,value,x1,x2,enabled,bg)
        ui.button(y,label,action,x1,x2,enabled,bg or 128,nil,value)
    end
    local function footer(items)
        for i,item in ipairs(items) do button(height,item[1],item[2],item[3],1+math.floor((i-1)*width/#items),math.floor(i*width/#items),item[4]~=false,i%2==0 and 256 or 128) end
    end
    local function page(key,count,slots)
        local pages=math.max(1,math.ceil(count/slots))
        local current=math.max(1,math.min(view.pages[key] or 1,pages)); view.pages[key]=current
        if pages>1 then
            local half=math.floor(width/2)
            button(height-1,"< "..current.."/"..pages,"page",{key=key,page=current-1},1,half,current>1)
            button(height-1,">","page",{key=key,page=current+1},half+1,width,current<pages)
        end
        return (current-1)*slots
    end
    local function menu(title,items,key,back)
        ui.heading(title,accent)
        local slots=#items<=height-2 and height-2 or height-3
        local first=page(key,#items,slots)
        for i=1,slots do local item=items[first+i]; if item then button(i+1,item[1],item[2],item[3],nil,nil,item[4],item[5]) end end
        footer(back or {{"Back","home"}})
    end
    local function info(title,lines,key,back)
        local wrapped={}
        for _,line in ipairs(lines) do
            line=tostring(line):gsub("[%c]"," ")
            repeat
                local cut=#line>width and line:sub(1,width):match("^.*()%s")
                if cut and cut>1 then wrapped[#wrapped+1],line=line:sub(1,cut-1),line:sub(cut+1)
                else wrapped[#wrapped+1],line=line:sub(1,width),line:sub(width+1) end
            until line==""
        end
        ui.heading(title,accent)
        local slots=#wrapped<=height-2 and height-2 or height-3
        local first=page(key,#wrapped,slots)
        for i=1,slots do ui.text(i+1,wrapped[first+i] or "") end
        footer(back or {{"Back","home"}})
    end
    if screen=="home" then
        local online,ports,targets,windows=0,0,0,#d.windows
        for _,client in ipairs(d.clients) do if client.online then online=online+1 end end
        for _,sensor in ipairs(d.sensors) do for _,port in ipairs(sensor.ports) do ports=ports+1; targets=targets+#(port.targets or {}) end end
        menu("System / "..online.." online",{{"Central computer","central"},{"Clients: "..#d.clients,"clients"},
            {"Sensors: "..ports.." / "..targets.." targets","sensors"},{"Outputs: "..#d.outputs,"outputs"},
            {"Apps: "..#d.apps,"apps"},{"Windows: "..windows,"windows"},{"Uptime history","uptime"},
            {"Relay map","relayMap"},{"Overview options","settings"}},"home",{{"Back","settingsHome"}})
    elseif screen=="central" then
        local s=d.system
        info("Central computer",{"Computer: "..s.computerId,"Network: "..s.networkId,"Session: "..s.session,
            "Wireless modem: "..(s.modemSide or "Detached"),"Server channel: "..tostring(s.channel),
            "Relay channel: "..tostring(s.relayChannel or "Disabled"),"Uptime: "..elapsed(s.uptime),
            "Last checkpoint: "..elapsed(s.lastSaveAge).." ago","World clock: "..s.gameTime,
            "Clock source: "..s.clockSource,"World day: "..tostring(s.worldDay or "Unavailable"),
            "Player indicator: "..(s.playerOnline and "Online" or "Offline"),
            "Only announced devices are known. No distance or chunk-loaded status is invented."},"central")
    elseif screen=="clients" or screen=="sensors" then
        local items={}
        for _,client in ipairs(d.clients) do
            if (screen=="sensors" and client.type=="sensor") or screen=="clients" and (state.filter=="all" or state.filter==client.type) then
                items[#items+1]={client.displayName.." / "..(client.online and "Online" or "Offline"),"client",client.id,true,client.online and 128 or 4096}
            end
        end
        if #items==0 then items[1]={"No known clients","noop",nil,false} end
        menu(screen=="sensors" and "Sensor clients" or "Clients / "..state.filter,items,screen,{{"Back","home"},{"Filter","filter"}})
    elseif screen=="client" then
        local client=find(d.clients,view.clientId)
        if not client then info("Client",{"Waiting for client to announce"},"client",{{"Back",view.clientBack or "clients"}})
        else
            local lines={client.displayName,"ID: "..client.id,"Role: "..client.type,"Status: "..(client.online and "Online" or "Offline"),"Computer: "..client.computerId,
                "Reply channel: "..tostring(client.channel),"Last seen: "..elapsed(client.age).." ago","Relay hops: "..client.hops,
                "Route: "..(#client.via>0 and table.concat(client.via," > ") or "Direct")}
            if client.uptime then lines[#lines+1]="Connected: "..elapsed(client.uptime) end
            if client.type=="relay" then lines[#lines+1]="Forwarded packets: "..tostring(client.forwarded or 0) end
            if client.type=="monitor" then
                lines[#lines+1]="Size: "..client.width.." x "..client.height.." characters"
                lines[#lines+1]="Revisioned touches: "..(client.touchProtocol and "Yes" or "No")
                local count=0; for _,win in ipairs(d.windows) do if win.monitorId==client.id then count=count+1 end end
                lines[#lines+1]="Saved windows: "..count
            elseif client.type=="io" then
                local io=find(d.io,client.id)
                lines[#lines+1]="Usable sides: "..join(io and io.sides or {})
                lines[#lines+1]="Output revision / ACK: "..tostring(client.revision).." / "..tostring(client.ackedRevision)
                for _,side in ipairs(io and io.sides or {}) do
                    local input=api.getInput(client.id,side)
                    lines[#lines+1]=side..": "..(input and ("digital "..tostring(input.digital)..", mask "..tostring(input.value)) or "Unavailable")
                end
            elseif client.type=="sensor" then
                local sensor=find(d.sensors,client.id)
                if sensor then
                    lines[#lines+1]="Protocol: "..tostring(sensor.sensorProtocol or "Legacy").." / boot "..tostring(sensor.bootId)
                    if sensor.catalogError then lines[#lines+1]="Catalog: "..sensor.catalogError end
                    for _,port in ipairs(sensor.ports) do
                        lines[#lines+1]=port.side..": "..(port.error or port.status or "Unknown")
                        lines[#lines+1]="Card: "..tostring(port.card or "None")
                        lines[#lines+1]="Targets: "..#(port.targets or {})
                    end
                    for _,pending in ipairs(sensor.pending) do lines[#lines+1]=pending.side..": "..pending.received.."/"..pending.parts.." catalog parts" end
                end
            end
            info("Client details",lines,"client:"..client.id,client.type=="sensor" and {{"Back",view.clientBack or "clients"},{"Targets","targets"}} or {{"Back",view.clientBack or "clients"}})
        end
    elseif screen=="targets" then
        local sensor=find(d.sensors,view.clientId); local items={}
        for _,port in ipairs(sensor and sensor.ports or {}) do for _,target in ipairs(port.targets or {}) do
            items[#items+1]={port.side..": "..(target.label or target.name or target.type or target.key),"target",{side=port.side,key=target.key}}
        end end
        if #items==0 then items[1]={"No catalog targets","noop",nil,false} end
        menu("Sensor targets",items,"targets:"..tostring(view.clientId),{{"Back","client"}})
    elseif screen=="target" then
        local lines={"Client: "..api.clientName(view.clientId),"Side: "..view.target.side,"Key: "..view.target.key}
        local sensor=find(d.sensors,view.clientId); local profile
        for _,port in ipairs(sensor and sensor.ports or {}) do if port.side==view.target.side then
            lines[#lines+1]="Card: "..tostring(port.card)
            if port.cardKind=="ae" then profile="ae_storage" end
            for _,target in ipairs(port.targets or {}) do if target.key==view.target.key then
                lines[#lines+1]="Name: "..tostring(target.label or target.name or "Unknown")
                lines[#lines+1]="Type: "..tostring(target.type or "Unknown")
                lines[#lines+1]="Raw: "..tostring(target.rawName or "Unavailable")
                lines[#lines+1]="Kind: "..tostring(target.kind or "Unknown")
                if target.position then lines[#lines+1]="Position: "..target.position.X..", "..target.position.Y..", "..target.position.Z end
            end end
        end end
        local cached=api.getSensorReading({clientId=view.clientId,side=view.target.side,target=view.target.key},{profile=profile})
        lines[#lines+1]="Cached sample: "..cached.status
        if cached.error then lines[#lines+1]=cached.error end
        if cached.age then lines[#lines+1]="Sample age: "..elapsed(cached.age) end
        if cached.status=="ok" and type(cached.data)=="table" then
            local keys={}; for key,value in pairs(cached.data) do if type(value)~="table" then keys[#keys+1]=key end end
            table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
            for i=1,math.min(#keys,48) do local key=keys[i]; lines[#lines+1]=tostring(key)..": "..tostring(cached.data[key]) end
        end
        lines[#lines+1]="Reads cached observations only; no new subscriptions or output changes."
        info("Target",lines,"target",{{"Back","targets"}})
    elseif screen=="outputs" then
        local items={}; for _,output in ipairs(d.outputs) do items[#items+1]={output.name.." / "..(output.value and "ON" or "OFF"),"output",output.name} end
        if #items==0 then items[1]={"No output routes","noop",nil,false} end
        menu("Mapped outputs",items,"outputs")
    elseif screen=="output" then
        local lines={"Route was removed"}
        for _,output in ipairs(d.outputs) do if output.name==view.output then lines={output.name,route(output,api),"Desired: "..(output.value and "ON" or "OFF"),
            "Client: "..(output.online and "Online" or "Offline"),"Acknowledged: "..(output.confirmed and "Yes" or "No / pending"),"Shared routes control the same physical wire."} end end
        info("Output details",lines,"output",{{"Back","outputs"}})
    elseif screen=="apps" then
        local lines={}
        for _,item in ipairs(d.apps) do lines[#lines+1]=item.title.." ("..item.name.."): "..(item.running and "Running" or "Stopped")..(item.backgroundService and " / background" or "") end
        if #lines==0 then lines={"No enabled user apps"} end
        info("Enabled apps",lines,"apps")
    elseif screen=="windows" then
        local lines={}
        for _,win in ipairs(d.windows) do
            lines[#lines+1]="#"..win.id.." "..(win.title or win.appName)..(win.minimized and " / minimized" or "")
            lines[#lines+1]=api.clientName(win.monitorId).." @ "..win.x..","..win.y.." "..win.width.."x"..win.height.." / "..(win.layout or "normal")
        end
        if #lines==0 then lines={"No saved windows"} end
        info("Saved windows",lines,"windows")
    elseif screen=="uptime" then
        local lines={}
        local events=api.getUptimeHistory()
        for i=#events,1,-1 do
            local item=events[i]
            local label=item.kind=="os" and "OS" or api.clientName(item.id)
            lines[#lines+1]=label.." / "..(item.kind=="os" and (item.online and "Started" or "Stopped") or item.online and "Online" or "Offline")
            local date=item.day and ("Day "..item.day.." ") or ""
            lines[#lines+1]=date..item.time..(item.seconds and " / "..elapsed(item.seconds) or "")
        end
        if #lines==0 then lines[1]="No history yet" end
        info("Uptime history",lines,"uptime")
    elseif screen=="relayMap" then
        local items={}
        for _,client in ipairs(d.clients) do
            local route={}
            for _,id in ipairs(client.via) do route[#route+1]=api.clientName(id) end
            items[#items+1]={client.displayName.." / "..(#route>0 and #route.." hops" or "Direct"),"path",client.id}
        end
        if #items==0 then items[1]={"No connected clients",nil,nil,false} end
        menu("Relay map",items,"map")
    elseif screen=="path" then
        local client=find(d.clients,view.clientId)
        local lines={"OS "..d.system.computerId}
        if client then
            for i=#client.via,1,-1 do lines[#lines+1]=" > "..api.clientName(client.via[i]) end
            lines[#lines+1]=" > "..client.displayName
            lines[#lines+1]=client.online and "Online" or "Last observed route"
            if client.type=="relay" then
                lines[#lines+1]="Devices using this relay"
                for _,device in ipairs(d.clients) do
                    for _,hop in ipairs(device.via) do
                        if hop==client.id then lines[#lines+1]=device.displayName; break end
                    end
                end
            end
        end
        info("Observed path",lines,"path",{{"Back","relayMap"},{"Details","pathClient",nil,client~=nil}})
    elseif screen=="settings" then
        menu("Overview options",{{"Client filter: "..state.filter,"filter"},{"About","about"}},"settings")
    elseif screen=="about" then
        info("About CC system",{"Live registry, routes, card catalogs, IO confirmations, enabled apps and saved windows. Offline clients remain visible during this OS session; a restart waits for announcements. Sensors and machine readings are never restored as live. Sensor bindings and app settings are saved by their owning apps. Client paths are based on received packets."},"about",{{"Back","settings"}})
    end
    return ui.lines,ui.hits
end
function app.render(w,h,state,api,context) return (build(w,h,state,api,context)) end
function app.handleTouch(x,y,w,h,state,api,context)
    local _,hits=build(w,h,state,api,context)
    local view=context.view
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then
        local action,value=hit.action,hit.value
        if action=="page" then view.pages[value.key]=value.page
        elseif action=="client" and value then view.clientId,view.screen,view.clientBack=value,"client",view.screen or "clients"
        elseif action=="path" then
            if value then view.clientId,view.pages.path=value,1 end
            view.screen="path"
        elseif action=="pathClient" then view.screen,view.clientBack="client","path"
        elseif action=="settingsHome" then view.exit=true
        elseif action=="target" and value then view.target,view.screen=value,"target"
        elseif action=="output" and value then view.output,view.screen=value,"output"
        elseif action=="filter" then
            local options={"all","io","monitor","sensor","relay"}; local old=state.filter
            for i,item in ipairs(options) do if item==old then state.filter=options[i%#options+1]; break end end
            local ok=api.save(); if not ok then state.filter=old end
            view.pages.clients=nil
        elseif action=="accent" then api.pickColour(context.windowId)
        elseif action~="noop" and action~="refresh" then view.screen=action end
        return true
    end end
    return false
end
return app
]=],
    ["lib_alert_inbox.lua"] = [=[-- Monitor-local sidebar over the desktop. History is owned by the OS.
local Inbox = {}

function Inbox.render(monitor, entries, api)
    local view = monitor.inbox
    local small = monitor.width < 34 or monitor.height < 10
    local width, height = small and monitor.width or math.min(38, math.floor(monitor.width * .48)),
        small and monitor.height or monitor.height - 1
    local x = monitor.width - width + 1
    local ui = api.ui.form(width, height, view, 2048)
    local selected
    for _, item in ipairs(entries) do if item.sequence == view.selected then selected = item; break end end
    if height < 5 or width < 8 then
        ui.heading("Alerts", 2048)
        ui.footer({{"Back", "close"}})
    elseif selected then
        local stamp = (selected.day and "Day " .. selected.day .. " " or "") .. selected.time
        ui.info(selected.title, {stamp, selected.message, selected.open and "Active" or "Closed"}, "details", "list")
    else
        local rows = {}
        for i = #entries, 1, -1 do
            local item = entries[i]
            rows[#rows + 1] = {(item.open and "* " or "") .. item.title .. " " .. item.time,
                "details", item.sequence, true, item.open and 16384 or nil}
        end
        if #rows == 0 then rows[1] = {"No alerts yet", nil, nil, false} end
        ui.menu("Alert inbox", rows, "alerts", {{"Back", "close"}})
    end
    return {x = x, width = width, height = height, lines = ui.lines, hits = ui.hits}
end

function Inbox.touch(monitor, model, api, x, y)
    if x < model.x or y > model.height then return false end
    local view = monitor.inbox
    local action, value = api.ui.actionAt(model.hits, x - model.x + 1, y)
    if action == "close" then monitor.inbox = nil
    elseif action == "list" then view.selected = nil
    elseif action == "details" then view.selected, view.pages.details = value, 1
    elseif action == "page" then view.pages[value.key] = value.page end
    return true
end

return Inbox
]=],
    ["lib_io_history.lua"] = [=[-- Bounded, shared history of IO side snapshots. A single event represents
-- all 16 bundled wires and the digital wire on that side.
local History = {}
local CAPACITY, HORIZON = 192, 300
local function stateAt(sample, color)
    if not sample or sample.mask == nil then return "?" end
    if color then
        if math.floor((sample.pending or 0) / color) % 2 == 1 then return "p" end
        return math.floor(sample.mask / color) % 2 == 1 and "1" or "0"
    end
    if sample.digitalPending then return "p" end
    return sample.digital and "1" or "0"
end

function History.new()
    local clients = {}
    local history = {}
    local function find(id, side, direction)
        local client = clients[id]
        return client and client[direction] and client[direction][side]
    end
    function history.record(id, side, direction, at, mask, digital, pending, digitalPending)
        local trail = find(id, side, direction)
        if not trail then
            if mask == nil then return end
            clients[id] = clients[id] or {input = {}, output = {}}
            trail = {first = 1, last = 0}
            clients[id][direction][side] = trail
        end
        local previous = trail[trail.last % CAPACITY]
        if previous and previous.mask == mask and previous.digital == digital and previous.pending == pending
            and previous.digitalPending == digitalPending then return end
        trail.last = trail.last + 1
        trail[trail.last % CAPACITY] = {at = previous and math.max(at, previous.at) or at, mask = mask,
            digital = digital, pending = pending, digitalPending = digitalPending}
        trail.first = math.max(trail.first, trail.last - CAPACITY + 1)
        while trail.first < trail.last and trail[(trail.first + 1) % CAPACITY].at < at - HORIZON do
            trail[trail.first % CAPACITY] = nil
            trail.first = trail.first + 1
        end
    end
    function history.offline(id, at)
        for direction, sides in pairs(clients[id] or {}) do
            for side in pairs(sides) do history.record(id, side, direction, at) end
        end
    end
    function history.trace(address, finish, seconds, width)
        local trail = find(address.clientId, address.side, address.direction)
        if not trail then return string.rep("?", width), "?" end
        local now = stateAt(trail[trail.last % CAPACITY], address.color)
        local start = finish - seconds
        local index, value = trail.first, "?"
        while index <= trail.last and trail[index % CAPACITY].at <= start do
            value = stateAt(trail[index % CAPACITY], address.color)
            index = index + 1
        end
        local cells = {}
        for x = 1, width do
            local deadline = start + seconds * x / width
            local changed = false
            while index <= trail.last and trail[index % CAPACITY].at <= deadline do
                local nextValue = stateAt(trail[index % CAPACITY], address.color)
                changed = changed or nextValue ~= value
                value, index = nextValue, index + 1
            end
            cells[x] = changed and "|" or value
        end
        return table.concat(cells), now
    end
    return history
end
return History
]=],
    ["lib_io_picker.lua"] = [=[-- Reusable, server-rendered IO selector. No peripheral or network calls here.
local Picker = {}
local Gui = dofile("lib_gui.lua")
local sideNames = {"top", "bottom", "left", "right", "front", "back"}
local colorNames = {"white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}

function Picker.new(key, direction, selected)
    local chosen = {}
    for k, v in pairs(selected or {}) do chosen[k] = v end
    return {key = key, direction = direction, stage = 1, page = 1, chosen = chosen}
end

local function choices(dialog, clients, label)
    local list = {}
    if dialog.stage == 1 then
        local found = false
        for _, client in ipairs(clients) do
            list[#list + 1] = {label = label(client.id) .. (client.online and " +" or " -"), value = client.id}
            if client.id == dialog.chosen.clientId then found = true end
        end
        if dialog.chosen.clientId and not found then
            list[#list + 1] = {label = label(dialog.chosen.clientId) .. " -", value = dialog.chosen.clientId}
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

function Picker.render(dialog, width, height, clients, api, testing)
    local label = api and api.clientName or function(id) return id end
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
        text(2, label(dialog.chosen.clientId) or "No IO client")
        text(3, "Side: " .. (dialog.chosen.side or "?"))
        local wire = colorName(dialog.chosen.color)
        if dialog.direction == "input" and api then
            local value = api.readInput(dialog.chosen)
            local status = value == nil and "Unknown" or value and "ON" or "OFF"
            local summary = wire .. " / " .. status
            text(4, #summary <= width and summary or wire:sub(1, width - #status - 1) .. " " .. status)
        else text(4, wire) end
        if dialog.error then text(4, dialog.error) end
        if dialog.direction == "output" and api then
            button(height - 1, 1, half, "< Back", "back")
            button(height - 1, half + 1, width, testing and "Wait" or "Test", "test", nil, not testing)
        else button(height - 1, 1, width, "< Back", "back") end
        button(height, 1, half, "Use", "use")
        button(height, half + 1, width, "Cancel", "cancel")
    else
        local titles = {"Select IO", "Select side", "Select wire"}
        local list = choices(dialog, clients, label)
        local path = dialog.stage>1 and Gui.breadcrumb(dialog.stage==3 and {label(dialog.chosen.clientId),dialog.chosen.side} or {label(dialog.chosen.clientId)},width,height)
        local header = path and 2 or 1
        local slots = #list <= height-header-1 and height-header-1 or math.max(1,height-header-2)
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        text(1, titles[dialog.stage] .. (pages > 1 and (" " .. dialog.page .. "/" .. pages) or ""))
        if path then text(2,path); lines.styles[#lines.styles+1]={x=1,y=2,width=width,height=1,fg=256,bg=32768} end
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then
                button(row + header, 1, width, (item.colour and "  " or "") .. item.label, "select", item.value)
                if item.colour then lines.styles[#lines.styles + 1] = {x = 1, y = row + header, width = 2, height = 1, bg = item.colour} end
            end
        end
        if #list == 0 then text(header+1, "No IO clients") end
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
            elseif hit.action == "test" then return "test", dialog.chosen
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
        {x1 = x + 3, x2 = x + 5, action = "layout", label = " # "},
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

function Desktop.fullscreen(app, monitor)
    if monitor.width < (app.minWidth or 8) or monitor.height < (app.minHeight or 2) then return nil end
    return {x = 1, y = 1, width = monitor.width, height = monitor.height}
end

function Desktop.contentRect(win)
    local inset = win.fullscreen and 0 or 1
    return {x = win.x + inset, y = win.y + inset,
        width = win.width - inset * 2, height = win.height - inset * 2}
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
            options[#options + 1] = {label = name,
                value = name == "1x1" and Desktop.gridMode(1, 1, 1, 1) or "choose_" .. name, enabled = enabled}
        end
        options[#options + 1] = {label = "Restore", value = "restore", enabled = win.layout ~= nil and win.layout ~= "normal"}
        options[#options + 1] = {label = "Fullscreen", value = "fullscreen", enabled = Desktop.fullscreen(app, monitor) ~= nil}
        options[#options + 1] = {label = "Resize", value = "custom", enabled = true}
        options[#options + 1] = {label = "Move", value = "move", enabled = true}
    end
    options[#options + 1] = {label = "Cancel", value = "cancel", enabled = true}
    return options
end

-- A compact pad stays in its chosen corner while nudging. It is placed away
-- from the selected point and never covers the confirmation/taskbar row.
function Desktop.pointArrows(point, monitor, anchor)
    local area, hits = Desktop.area(monitor), {}
    anchor = anchor or {x = point.x > area.width / 2 and 1 or area.width - 4,
        y = point.y > area.height / 2 and 2 or area.height - 2}
    local function add(x, y, label, dx, dy)
        hits[#hits + 1] = {x1 = x, x2 = x + #label - 1, y = y, label = label, dx = dx, dy = dy}
    end
    if point.x > 1 then add(anchor.x, anchor.y + 1, "<", -1, 0) end
    if point.x < area.width then add(anchor.x + 4, anchor.y + 1, ">", 1, 0) end
    if point.y > 1 then add(anchor.x + 1, anchor.y, " ^ ", 0, -1) end
    if point.y < area.height then add(anchor.x + 1, anchor.y + 2, " v ", 0, 1) end
    return hits, anchor
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
    if (area.height < 11 and not gridColumns) or (gridColumns and area.height < gridRows * 2 + 3) then
        return Desktop.menu(monitor, title or (gridColumns and selectedGrid .. " position" or "Layout"), options, page,
            {x = win.x, y = win.y + 1})
    end
    local width = math.min(gridColumns and 35 or 43, area.width)
    local columns = width >= 40 and 3 or width >= 27 and 2 or 1
    local height = math.min(area.height, gridColumns and math.max(9, gridRows * 3 + 4) or 4 + math.ceil(#grids / columns) * 6)
    local rows = math.max(1, math.floor((height - 4) / 6))
    if rows * columns < #grids then rows = math.max(1, math.floor((height - 5) / 6)) end
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
                local item = byMode[name == "1x1" and Desktop.gridMode(1, 1, 1, 1) or "choose_" .. name]
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
        ui.button(height - 3, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 3, "Next >", "next", half + 1, width, page < pages)
    end
    local function action(y, x1, x2, mode, label)
        ui.button(y, label, "item", x1, x2, byMode[mode].enabled)
        ui.hits[#ui.hits].item = byMode[mode]
    end
    if gridColumns then
        action(height, 1, half, "back", "Back")
        action(height, half + 1, width, "cancel", "Cancel")
    elseif width < 22 then
        action(height - 2, 1, width, "fullscreen", "Fullscreen")
        action(height - 1, 1, half, "restore", "Restore")
        action(height - 1, half + 1, width, "custom", "Resize")
        action(height, 1, half, "move", "Move")
        action(height, half + 1, width, "cancel", "Cancel")
    else
        action(height - 2, 1, half, "fullscreen", "Fullscreen")
        action(height - 2, half + 1, width, "restore", "Restore")
        action(height - 1, 1, half, "custom", "Resize")
        action(height - 1, half + 1, width, "move", "Move")
        action(height, 1, width, "cancel", "Cancel")
    end
    for _, hit in ipairs(ui.hits) do
        hit.x1, hit.x2, hit.y = hit.x1 + rect.x - 1, hit.x2 + rect.x - 1, hit.y + rect.y - 1
        if hit.y1 then hit.y1, hit.y2 = hit.y1 + rect.y - 1, hit.y2 + rect.y - 1 end
    end
    return rect, ui.lines, ui.hits, page, pages
end

-- Returns a complete taskbar line and exact touch regions, with stable window order.
function Desktop.taskbar(windows, monitor, clock, saved, active)
    local visible={}; for _,win in ipairs(windows) do if not win.hideTaskbar then visible[#visible+1]=win end end; windows=visible
    local width = monitor.width
    local line, hits = string.rep(" ", width), {}
    local function put(x, label, stop)
        label = label:sub(1, math.max(0, math.min(stop or width, width) - x + 1))
        line = line:sub(1, x - 1) .. label .. line:sub(x + #label)
    end
    local function hit(x1, x2, action, id) hits[#hits + 1] = {x1 = x1, x2 = x2, action = action, id = id} end
    put(1, "[+]"); hit(1, math.min(3, width), "launcher")
    local clockWidth = (width >= 22 or (#windows == 0 and width >= 10)) and 6 or 0
    if clockWidth > 0 then put(width - 4, clock); hit(width - 4, width, "inbox") end
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
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local Picker = dofile("lib_io_picker.lua")
local Desktop = dofile("lib_desktop.lua")
local Gui = dofile("lib_gui.lua")
local Settings = dofile("lib_settings.lua")
local SensorHub = dofile("lib_sensor_server.lua")
local SensorPicker = dofile("lib_sensor_picker.lua")
local IOHistory = dofile("lib_io_history.lua")
local Inbox = dofile("lib_alert_inbox.lua")
local systemColours = {background = {field = "backgroundColour", title = "Background"},
    windowBorder = {field = "windowBorderColour", title = "Window border"}, taskbar = {field = "taskbarColour", title = "Taskbar"}}
local defaultAppearance = {backgroundColour = 2048, windowBorderColour = 128, taskbarColour = 128}
local legacyOutputNames = {
    {"^coffee_harvest$", "coffee"}, {"^switchboard_switch_%d+$", "switchboard"},
    {"^reactors_switch_%d+$", "reactors"}, {"^clock_alarm_%d+$", "clock"},
    {"^clock_timer_%d+$", "clock"}, {"^level_emitter_rule_%d+$", "level_emitter"},
    {"^solar_farm_alarm_%d+$", "solar_farm"},
}
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
    for key, item in pairs(value) do result[key] = copy(item); Work.check(8) end
    return result
end
-- Window UI state is plain bounded data, independent of sensor caches and app
-- business state. Do not persist frame hit maps or rendering styles.
local function viewSnapshot(value)
    local seen, count = {}, 0
    local function clean(item, depth)
        count = count + 1
        if count > 2048 or depth > 8 then error("Window UI state is too large", 0) end
        local kind = type(item)
        if kind == "boolean" or kind == "nil" then return item end
        if kind == "number" then return item == item and math.abs(item) < math.huge and item or nil end
        if kind == "string" then assert(#item <= 4096, "Window UI text is too large"); return item end
        if kind ~= "table" or seen[item] then return nil end
        seen[item] = true
        local result = {}
        for key, child in pairs(item) do
            if (type(key) == "string" and #key <= 96 or integer(key, 1, 2147483646)) and key ~= "hits" and key ~= "styles" then
                result[key] = clean(child, depth + 1)
            end
        end
        seen[item] = nil
        return result
    end
    local ok, result = Work.call(clean, value, 0)
    return ok and type(result) == "table" and result or {}
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
    for _,key in ipairs({"backgroundService","fullscreenOnly","transientWindow","hideTaskbar","handlesFullscreenCorner"}) do
        if app[key]~=nil and type(app[key])~="boolean" then return false end
    end
    if app.animationInterval~=nil and (type(app.animationInterval)~="number" or app.animationInterval~=app.animationInterval
        or app.animationInterval<0.1 or app.animationInterval>1) then return false end
    for _, key in ipairs({"init", "shutdown", "background", "render", "handleTouch", "handleIOSelection", "handleSensorSelection", "handleNotification", "onOpen", "onClose", "ioRoutes"}) do
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
    for field, value in pairs(defaultAppearance) do
        if not colour(state.appearance[field]) then state.appearance[field] = value end
    end
    local appColours = {}
    if type(state.appearance.appColours) == "table" then
        for name, value in pairs(state.appearance.appColours) do
            if type(name) == "string" and colour(value) then appColours[name] = value end
        end
    end
    state.appearance.appColours = appColours
    for _, key in ipairs({"clientNames", "uptimeHistory", "alertHistory", "archivedRoutes"}) do
        if type(state[key]) ~= "table" then state[key] = {} end
    end
    state.notificationSequence = tonumber(state.notificationSequence) or 0
    state.appStates["@settings"] = type(state.appStates["@settings"]) == "table" and state.appStates["@settings"] or {}
    local server = {state = state, monitors = {}, ioClients = {}, sensorClients = {}, relayClients = {}, apps = {},
        systemApps = {}, gameTime = "?:??", playerOnline = false,
        lastSave = 0, lastTick = os.clock(), views = {}, dialogs = {}, running = {}, notifications = {}}
    local clientGroups = {io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients, relay = server.relayClients}
    local api, errors, installedApps = {}, {}, {}
    local history, ioTests = IOHistory.new(), {}
    local callingApp
    server.api = api
    api.ui, api.log, api.sharedOutputs, api.sensorProfiles = Gui, log, true, true
    api.cooperate, api.protectedCall = Work.check, Work.call
    api.aeItemProfiles = true
    function api.clientName(id) return type(state.clientNames[id]) == "string" and state.clientNames[id] or id end
    local function definition(name) return server.systemApps[name] or server.apps[name] end
    local function invalidateInput(id)
        local monitor = server.monitors[id]
        if monitor then monitor.inputRevision = (monitor.inputRevision or 0) + 1 end
    end
    state.nextWindowId = 1
    local legacyDesktop = (tonumber(state.desktopVersion) or 1) < 2
    local savedWindows = state.windows
    state.windows = {}
    for id, win in pairs(savedWindows) do
        if integer(id, 1, 2147483646) and type(win) == "table"
            and type(win.appName) == "string" and type(win.monitorId) == "string" then
            state.windows[id] = win
            state.nextWindowId = math.max(state.nextWindowId, id + 1)
            win.id, win.order = id, tonumber(win.order) or id
            if not state.appStates[win.appName] and type(win.appState) == "table" then
                state.appStates[win.appName] = win.appState
            end
            win.appState = nil -- App state is shared with its background service.
            server.views[id] = viewSnapshot(win.viewState)
            win.viewState = nil
            if legacyDesktop then win.y = math.max(1, (tonumber(win.y) or 3) - 2) end
        end
    end
    -- The legacy diagnostics app now lives inside OS settings.
    local legacyOverview = state.appStates.system
    if type(legacyOverview) == "table" and not state.appStates["@settings"].overview then
        state.appStates["@settings"].overview = legacyOverview
    end
    state.appStates.system, state.appRegistry.system = nil, nil
    local legacyOverviewColor = state.appearance.appColours.system
    if legacyOverviewColor and not state.appearance.appColours["@settings"] then
        state.appearance.appColours["@settings"] = legacyOverviewColor
    end
    state.appearance.appColours.system = nil
    for id, win in pairs(state.windows) do
        if win.appName == "system" then
            win.appName = "@settings"
            server.views[id] = {section = "overview", overview = server.views[id]}
        end
    end
    state.desktopVersion = 2
    state.bootCounter = (tonumber(state.bootCounter) or 0) + 1
    server.session = tostring(net.id) .. ":" .. state.bootCounter
    local sensors = SensorHub.new(net, server.sensorClients, server.session)
    server.sensors = sensors
    if source and source ~= config.saveFile then log("Recovered state from " .. source) end
    if not loaded and fs.exists(config.saveFile) then log("Unreadable OS state; starting with defaults") end

    local function saveWindows(include)
        local windows = {}
        for id, win in pairs(state.windows) do
            if not win.transientWindow and (not include or include(win)) then
                windows[id] = copy(win)
                windows[id].viewState = viewSnapshot(server.views[id])
            end
        end
        return windows
    end
    function server.save(forgetPrevious)
        local previousStage = Work.stage
        Work.stage = "Saving OS state"
        local saved = {}
        for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides",
            "nextWindowId", "bootCounter", "desktops", "desktopVersion", "appearance",
            "clientNames", "uptimeHistory", "alertHistory", "archivedRoutes", "notificationSequence"}) do
            saved[name] = state[name]
        end
        saved.windows = saveWindows()
        local ok, err = storage.save(config.saveFile, saved, forgetPrevious)
        if ok then
            server.lastSave = os.clock()
            if err then log(err) end
        else log("State save failed: " .. tostring(err)) end
        Work.stage = previousStage
        return ok, err
    end
    function api.save() return server.save() end
    api.fullscreenApps = true
    api.fullscreenCornerNavigation = true
    -- App-owned, synchronous upgrade transaction. The transform edits detached
    -- copies; both app namespaces checkpoint together without touching IO maps.
    function api.migrateAppState(from,to,transform)
        if from==to or not server.apps[to] or type(transform)~="function" then return false,"Invalid app migration" end
        local sourceState,targetState=state.appStates[from],state.appStates[to]
        if type(sourceState)~="table" or type(targetState)~="table" then return false,"App state is unavailable" end
        local oldSource,oldTarget=copy(sourceState),copy(targetState)
        local nextSource,nextTarget=copy(sourceState),copy(targetState)
        local ok,accepted,err=Work.call(transform,nextSource,nextTarget)
        if not ok or accepted~=true then return false,tostring(ok and err or accepted) end
        local function replace(target,value)
            local keys={}; for key in pairs(target) do keys[#keys+1]=key end
            for _,key in ipairs(keys) do target[key]=nil end
            for key,item in pairs(value) do target[key]=item end
        end
        replace(sourceState,nextSource); replace(targetState,nextTarget)
        ok,err=server.save()
        if not ok then replace(sourceState,oldSource); replace(targetState,oldTarget); return false,err end
        server.notifications[from]=nil
        api.invalidateAppViews(from); api.invalidateAppViews(to)
        return true
    end
    function api.getAppData(name) return copy(state.appStates[name]) end
    function api.invalidateAppViews(name)
        local seen = {}
        for _, win in pairs(state.windows) do
            if win.appName == name and not seen[win.monitorId] then
                invalidateInput(win.monitorId)
                seen[win.monitorId] = true
            end
        end
    end

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
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.backgroundColour = value end)
    end
    function api.setWindowBorderColour(value)
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.windowBorderColour = value end)
    end
    function api.setTaskbarColour(value)
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.taskbarColour = value end)
    end
    local systemColourSetters = {background = api.setBackgroundColour,
        windowBorder = api.setWindowBorderColour, taskbar = api.setTaskbarColour}
    function api.setAppColour(name, value)
        if not definition(name) or not colour(value) then return false, "Invalid app color" end
        return saveAppearance(function(appearance) appearance.appColours[name] = value end)
    end

    local function appCall(name, hook, ...)
        local app = definition(name)
        if not app or not app[hook] then return true end
        local previousStage = Work.stage
        Work.stage = "App " .. name .. "." .. hook
        local previousApp = callingApp
        callingApp = name
        local ok, a, b = Work.call(app[hook], ...)
        callingApp = previousApp
        if not ok then
            local key = name .. "." .. hook
            if errors[key] ~= a then
                Work.report(Work.stage, a)
                log("App " .. key .. " failed: " .. tostring(a)); errors[key] = a
            end
            Work.check(16384)
        end
        Work.stage = previousStage
        return ok, a, b
    end

    local function isService(app) return app.backgroundService == true or app.render == nil end
    local function loadApp(name)
        local chunk, err = loadfile("apps_" .. name .. ".lua")
        local ok, app = false, err
        if chunk then ok, app = Work.call(chunk) end
        if not ok or not validApp(app) then
            server.apps[name] = nil
            log("Cannot load app " .. name .. ": " .. tostring(app))
            return false
        end
        server.apps[name], state.appRegistry[name] = app, true
        if type(state.appStates[name]) ~= "table" then state.appStates[name] = {} end
        log("Loaded app: " .. name)
        return true
    end
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
        return {windowId = win.id, monitorId = win.monitorId, appName = win.appName,
            fullscreen = win.fullscreen == true, view = server.views[win.id]}
    end

    local function updateClock()
        server.worldTime, server.worldDay = nil, nil
        if type(os.time) == "function" then
            local ok, value = pcall(os.time)
            if ok and type(value) == "number" and value >= 0 and value < 24 then
                local minutes = math.floor(value * 60 + 0.000001)
                server.gameTime = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
                server.clockSource, server.worldTime = "computer", value
                if type(os.day) == "function" then
                    local dayOK, day = pcall(os.day)
                    if dayOK and integer(day, 0, 2147483647) then server.worldDay = day end
                end
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
    local function stamp()
        return {time = server.gameTime, day = server.worldDay, session = server.session}
    end
    local function appendHistory(entries, item, limit)
        entries[#entries + 1] = item
        if #entries > limit then table.remove(entries, 1) end
    end
    local function logUptime(id, kind, online, at, since)
        local item = stamp()
        item.id, item.kind, item.online = id, kind, online
        if since then item.seconds = math.max(0, at - since) end
        appendHistory(state.uptimeHistory, item, 128)
    end
    function api.getUptimeHistory() return copy(state.uptimeHistory) end

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

    local function lineValue(values, color)
        if not values then return false end
        if color then return math.floor(values.bundled / color) % 2 == 1 end
        return values.digital
    end
    local function putLine(values, color, value)
        if not color then values.digital = value
        elseif lineValue(values, color) ~= value then
            values.bundled = values.bundled + (value and color or -color)
        end
    end
    local function recordOutputs(id, client, now)
        for side, values in pairs(client.outputSnapshot or {}) do
            local required, pending = client.wireRevisions[side] or {}, 0
            for bit = 0, 15 do
                local color = 2 ^ bit
                if (required[color] or client.revision) > client.ackedRevision then pending = pending + color end
            end
            history.record(id, side, "output", now, values.bundled, values.digital,
                pending, (required.digital or client.revision) > client.ackedRevision)
        end
    end

    function server.syncIO(clientId, changed)
        local client = server.ioClients[clientId]
        if not client then return end
        if changed then client.revision = client.revision + 1 end
        if not client.online then return end
        local snapshot = {}
        local wanted = outputSnapshot(clientId)
        local test = ioTests[clientId]
        if test and wanted[test.side] then putLine(wanted[test.side], test.color, test.value) end
        for side, values in pairs(wanted) do
            if not client.capabilities[side] then
                log("IO " .. clientId .. ": mapped side " .. side .. " is unavailable")
            else snapshot[side] = values end
        end
        -- A snapshot ACK covers a whole revision, but unrelated wires retain
        -- their earlier confirmation. Requiring the latest client revision for
        -- every output made an entire board flash pending after one toggle.
        client.wireRevisions = client.wireRevisions or {}
        for side, wanted in pairs(snapshot) do
            local previous = client.outputSnapshot and client.outputSnapshot[side]
            local required = client.wireRevisions[side] or {}
            client.wireRevisions[side] = required
            if not previous or previous.digital ~= wanted.digital or required.digital == nil then
                required.digital = client.revision
            end
            for bit = 0, 15 do
                local color = 2 ^ bit
                if not previous or math.floor(previous.bundled / color) % 2 ~= math.floor(wanted.bundled / color) % 2
                    or required[color] == nil then required[color] = client.revision end
            end
        end
        for side in pairs(client.outputSnapshot or {}) do
            if not snapshot[side] then history.record(clientId, side, "output", os.clock()) end
        end
        client.outputSnapshot = copy(snapshot)
        recordOutputs(clientId, client, os.clock())
        net.toClient(client, {type = "ioCommand", command = "syncOutputs", clientId = clientId,
            serverSession = server.session, revision = client.revision, outputs = snapshot})
        client.lastSent = os.clock()
    end

    local function testOutput(address)
        local id, side, color = address.clientId, address.side, address.color
        local client = server.ioClients[id]
        if not client or not client.online or not client.capabilities[side] then return false, "Output unavailable" end
        if ioTests[id] then return false, "Test in progress" end
        local value = lineValue(outputSnapshot(id)[side], color)
        local previous = state.managedSides[id]
        if not previous or not previous[side] then
            state.managedSides[id] = copy(previous or {})
            state.managedSides[id][side] = true
            -- Persist the cleared side before pulsing it so an OS reboot also
            -- restores a test of a previously unused wire.
            local ok, err = server.save()
            if not ok then state.managedSides[id] = previous; return false, err end
        end
        ioTests[id] = {side = side, color = color, value = not value, untilTime = os.clock() + 4}
        server.syncIO(id, true)
        return true
    end
    function api.getIOTrace(address, finish, seconds, width)
        if not integer(width, 1, 256) or not integer(seconds, 1, 300) or type(address) ~= "table"
            or (address.direction ~= "input" and address.direction ~= "output")
            or type(address.clientId) ~= "string" or not sideSet[address.side]
            or (address.color ~= nil and not colour(address.color))
            or type(finish) ~= "number" or finish ~= finish then return "", "?" end
        return history.trace(address, finish, seconds, width)
    end

    function api.getOutput(name) return state.outputs[name] == true end
    -- One checkpoint for a whole panel, reroute, removal or group action. App
    -- state changed by the caller is included in that same durable checkpoint.
    local function checkpointOutputs(changes, forgetPrevious, owners)
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
            if type(change) ~= "table" or type(change.name) ~= "string" or seen[change.name] then
                return false, "Invalid or repeated output name"
            end
            local legacy = forgetPrevious and (change.remove == true and mappings[change.name] or owners and owners[change.name])
            if not change.name:match("^[%w_-]+$") and not legacy then
                return false, "Invalid output name"
            end
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
                    mapping = {clientId = change.clientId, side = change.side, color = change.color,
                        owner = owners and owners[change.name] or mapping and mapping.owner or callingApp or (not mapping and "@settings" or nil)}
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
        local ok, err = server.save(forgetPrevious)
        if not ok then
            state.outputMap, state.outputs, state.managedSides = previousMap, previousValues, previousManaged
            return false, err
        end
        for _, id in ipairs(sortedKeys(affected)) do
            local snapshot = outputSnapshot(id)
            local test = ioTests[id]
            if test and lineValue(before[id][test.side], test.color) ~= lineValue(snapshot[test.side], test.color) then
                ioTests[id] = nil
                server.syncIO(id, true)
            else server.syncIO(id, not sameSnapshot(before[id], snapshot)) end
        end
        return true, err
    end
    function api.updateOutputs(changes) return checkpointOutputs(changes) end
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
            local required = client and client.wireRevisions and client.wireRevisions[item.side]
            required = required and required[item.color or "digital"]
            item.confirmed = item.online and client.capabilities[item.side]
                and required ~= nil and client.ackedRevision >= required or false
            local test = ioTests[item.clientId]
            if test and test.side == item.side and test.color == item.color then item.confirmed = false end
            result[#result + 1] = item
        end
        return result
    end
    function api.getInput(clientId, side)
        local client = server.ioClients[clientId]
        if client and client.online and client.capabilities[side] then return copy(client.inputs[side]) end
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
            result[#result + 1] = {id = id, displayName = api.clientName(id), online = client.online, computerId = client.computerId,
                sides = sortedKeys(client.capabilities or {})}
        end
        return result
    end
    function api.pickIO(windowId, key, direction, current)
        local win = state.windows[windowId]
        if not win or type(key) ~= "string" or (direction ~= "input" and direction ~= "output") then
            return false, "Invalid IO selector request"
        end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "IO settings need a 12x6 content area" end
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
        if not win or (target ~= "app" and not option) then return false, "Invalid color selector" end
        if option and win.appName ~= "@settings" then return false, "Open Settings for system colors" end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "Color settings need a 12x6 content area" end
        server.dialogs[windowId] = {kind = "colour", target = target,
            current = option and state.appearance[option.field] or api.getAppColour(win.appName)}
        invalidateInput(win.monitorId)
        return true
    end
    function api.getSensor(clientId, name)
        local client = server.sensorClients[clientId]
        if client and client.online then return copy(client.values[name]) end
    end
    api.unwatchSensor, api.getSensorReading = sensors.unwatch, sensors.read
    function api.getSensorClients()
        local clients = sensors.getClients()
        for _, client in ipairs(clients) do client.displayName = api.clientName(client.id) end
        return clients
    end
    function api.watchSensor(key, address, options)
        local ok, err = sensors.watch(key, address, options)
        if ok then sensors.watches[key].owner = callingApp or "@settings" end
        return ok, err
    end
    function api.pickSensor(windowId, key, current, kind)
        local win = state.windows[windowId]
        local app = win and definition(win.appName)
        if not win or not app or not app.handleSensorSelection or type(key) ~= "string" then return false, "Invalid sensor selector" end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "Sensor settings need a 12x6 content area" end
        server.dialogs[windowId] = SensorPicker.new(key, copy(current), kind)
        invalidateInput(win.monitorId)
        return true
    end
    function api.getClients()
        local result = {}
        for kind, group in pairs(clientGroups) do
            for id, client in pairs(group) do
                local via = {}
                for _, hop in ipairs(client.route or {}) do via[#via + 1] = hop.id end
                result[#result + 1] = {id = id, displayName = api.clientName(id), type = kind, online = client.online,
                    computerId = client.computerId, uptime = client.online and math.max(0, os.clock() - (client.since or client.lastSeen)) or nil,
                    via = via, hops = #via, route = copy(client.route or {}), forwarded = client.forwarded,
                    channel = client.channel, age = math.max(0, os.clock() - client.lastSeen),
                    width = client.width, height = client.height, revision = client.revision,
                    ackedRevision = client.ackedRevision, touchProtocol = client.touchProtocol}
            end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    function api.getClientNameTargets()
        local result, known = api.getClients(), {}
        for _, client in ipairs(result) do known[client.id] = true end
        local function include(id, kind)
            if id and not known[id] then
                known[id] = true
                result[#result + 1] = {id = id, displayName = api.clientName(id), type = kind, online = false}
            end
        end
        for _, item in ipairs(state.uptimeHistory) do if item.kind ~= "os" then include(item.id, item.kind) end end
        for id in pairs(state.clientNames) do include(id) end
        table.sort(result, function(a, b)
            local aa, bb = a.displayName:lower(), b.displayName:lower()
            return aa == bb and a.id < b.id or aa < bb
        end)
        return result
    end
    function api.setClientName(id, name)
        if type(id) ~= "string" or #id > 96 or type(name) ~= "string" or #name > 32 or name:find("[%c]") then
            return false, "Use a name up to 32 characters"
        end
        name = name:match("^%s*(.-)%s*$")
        for other, label in pairs(state.clientNames) do
            if other ~= id and name ~= "" and label:lower() == name:lower() then return false, "Name already in use" end
        end
        local old = state.clientNames[id]
        state.clientNames[id] = name ~= "" and name or nil
        local ok, err = server.save()
        if not ok then state.clientNames[id] = old; return false, err end
        for monitorId in pairs(server.monitors) do invalidateInput(monitorId) end
        return true
    end

    function api.getSystem() return {gameTime = server.gameTime, clockSource = server.clockSource,
        worldTime = server.worldTime, worldDay = server.worldDay, playerOnline = server.playerOnline,
        computerId = net.id, networkId = net.config.networkId, modemSide = net.side,
        channel = net.listenChannel, relayChannel = net.config.relayEnabled ~= false and net.relayChannel or nil,
        uptime = os.clock(), session = server.session, lastSaveAge = math.max(0, os.clock()-server.lastSave)} end
    function api.getDiagnostics()
        local result = {system = api.getSystem(), clients = api.getClients(), io = api.getIOClients(),
            sensors = api.getSensorClients(), outputs = api.getOutputs(), apps = {}, windows = {}}
        for _, name in ipairs(sortedKeys(server.apps)) do
            local app = server.apps[name]
            result.apps[#result.apps+1] = {name = name, title = app.title or name,
                running = server.running[name] == true, backgroundService = isService(app)}
        end
        for _, id in ipairs(sortedKeys(state.windows)) do
            local win = state.windows[id]
            result.windows[#result.windows+1] = {id=id, appName=win.appName, title=win.title, monitorId=win.monitorId,
                x=win.x, y=win.y, width=win.width, height=win.height, minimized=win.minimized == true,
                layout=win.layout, fullscreen=win.fullscreen == true}
        end
        return result
    end

    -- Notification contents are runtime mirrors of app-owned durable state.
    -- Apps remove an entry only after their acknowledgement/output checkpoint.
    function api.setNotifications(name, entries)
        local app = definition(name)
        if not app or not app.handleNotification or not server.running[name] or type(entries) ~= "table" then
            return false, "Invalid notification publisher"
        end
        local count, seen, staged = 0, {}, {}
        for index in pairs(entries) do
            if not integer(index, 1, #entries) then return false, "Expected a notification array" end
            count = count + 1
        end
        if count ~= #entries or count > 128 then return false, "Too many notifications" end
        local function label(value, limit)
            return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%c]")
        end
        local old = server.notifications[name] or {}
        local byKey = {}; for _, item in ipairs(old) do byKey[item.key] = item end
        local changed = #old ~= #entries
        for index, item in ipairs(entries) do
            if type(item) ~= "table" or not label(item.key, 96) or seen[item.key]
                or not label(item.title, 64) or not label(item.message, 128) then return false, "Invalid notification" end
            seen[item.key] = true
            local previous = byKey[item.key]
            staged[index] = {appName=name, key=item.key, title=item.title, message=item.message,
                sequence=previous and previous.sequence}
            local before = old[index]
            changed = changed or not before or before.key ~= item.key or before.title ~= item.title or before.message ~= item.message
        end
        local previous = {}
        for _, record in ipairs(state.alertHistory) do
            if record.appName == name and record.open then
                if seen[record.key] then previous[record.key] = record
                else record.open, changed = nil, true end
            end
        end
        if not changed then return true end
        for _, item in ipairs(staged) do
            local record = previous[item.key]
            if record then
                item.sequence = record.sequence
                record.title, record.message = item.title, item.message
            elseif not item.sequence then
                state.notificationSequence = state.notificationSequence + 1
                item.sequence = state.notificationSequence
                local entry = stamp()
                entry.appName, entry.key, entry.title, entry.message = name, item.key, item.title, item.message
                entry.sequence, entry.open = item.sequence, true
                appendHistory(state.alertHistory, entry, 128)
            end
        end
        server.notifications[name] = staged
        for id, monitor in pairs(server.monitors) do
            monitor.notification, monitor.notificationError = nil, nil
            invalidateInput(id)
        end
        return true
    end
    local function clearNotifications(name)
        server.notifications[name] = nil
        for _, entry in ipairs(state.alertHistory) do if entry.appName == name then entry.open = nil end end
    end
    local function firstNotification()
        local first
        for name, entries in pairs(server.notifications) do
            if server.running[name] then
                for _, item in ipairs(entries) do if not first or item.sequence < first.sequence then first = item end end
            end
        end
        return first
    end
    local function notificationModel(item, monitor)
        local available = not monitor.fullscreen and monitor.height >= 5 and monitor.height-1 or monitor.height
        local width = math.min(34, monitor.width)
        local inner = math.max(1,width-2)
        local rows,remaining = {},item.message
        repeat
            local cut = #remaining>inner and remaining:sub(1,inner):match("^.*()%s")
            if cut and cut>1 then rows[#rows+1],remaining = remaining:sub(1,cut-1),remaining:sub(cut+1)
            else rows[#rows+1],remaining = remaining:sub(1,inner),remaining:sub(inner+1) end
        until remaining==""
        local height = math.min(available, math.max(5,math.min(3,#rows)+4))
        local x,y = 1+math.floor((monitor.width-width)/2),1+math.floor((available-height)/2)
        local buttonY = y+math.max(0,height-(height>=3 and 2 or 1))
        local inset = width>=3 and 1 or 0
        return {appName=item.appName,key=item.key,lines=rows,x=x,y=y,width=width,height=height,
            ok={x1=x+inset,x2=x+width-inset-1,y=buttonY}}
    end

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
        if app.fullscreenOnly then win.fullscreen=true end
        win.hideTaskbar,win.transientWindow=app.hideTaskbar==true or nil,app.transientWindow==true or nil
        if not validRelative(win.relative) then win.relative = nil end
        local rect
        win.fullscreen = win.fullscreen == true or nil
        win.tooSmall = false
        if win.fullscreen then
            win.tooSmall = Desktop.fullscreen(app, monitor) == nil
            rect = {x = 1, y = 1, width = monitor.width, height = monitor.height}
        elseif win.layout and win.layout ~= "normal" then
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
        if app.fullscreenOnly then return app.render and Desktop.fullscreen(app,monitor)~=nil end
        local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
        return app.render and maxW >= minW and maxH >= minH
    end
    local function discardSmallDialog(win)
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then server.dialogs[win.id] = nil end
    end
    local function fullscreenWindow(id)
        local current
        for _, win in ipairs(windowsFor(id)) do
            if win.fullscreen and not win.minimized and not win.doesNotFit and server.running[win.appName] then current = win end
        end
        return current
    end

    function api.openApp(name, monitorId, x, y, width, height)
        local app, monitor = definition(name), server.monitors[monitorId]
        if not app then return nil, "Unknown app" end
        if not monitor or not monitor.online then return nil, "Monitor is offline or unknown" end
        if not compatible(name, monitor) then return nil, "App does not fit this monitor" end
        local win = {id = state.nextWindowId, appName = name, monitorId = monitorId,
            x = x, y = y, width = width, height = height, order = 0, layout = "normal",fullscreen=app.fullscreenOnly==true or nil}
        fit(win, monitor)
        if not app.fullscreenOnly and not x and not y then
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
        if not app.fullscreenOnly then win.relative = Desktop.relative(win, monitor) end
        state.windows[win.id], state.nextWindowId = win, win.id + 1
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[win.id] = nil; return nil, err end
        ok, err = startApp(name)
        if not ok then state.windows[win.id] = nil; server.save(); return nil, err end
        if app.onOpen then
            local accepted
            ok,accepted,err=appCall(name,"onOpen",state.appStates[name],api,viewContext(win))
            if not ok or accepted==false then
                state.windows[win.id],server.views[win.id]=nil,nil; stopApp(name); server.save()
                return nil,tostring(ok and err or accepted)
            end
        end
        return win.id
    end
    local function releaseWindow(win, appState)
        appCall(win.appName,"onClose",appState,api,viewContext(win))
        server.views[win.id], server.dialogs[win.id] = nil, nil
        local monitor = server.monitors[win.monitorId]
        if monitor then
            if monitor.layoutMenu and monitor.layoutMenu.windowId == win.id then monitor.layoutMenu = nil end
            if monitor.placement and monitor.placement.windowId == win.id then monitor.placement = nil end
        end
        invalidateInput(win.monitorId)
    end
    function api.closeWindow(id)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        state.windows[id] = nil
        local ok, err = server.save()
        if not ok then state.windows[id] = win; return false, err end
        releaseWindow(win, state.appStates[win.appName])
        stopApp(win.appName)
        return true
    end

    function api.captureWindowPreset(monitorId, allMonitors)
        local slots = {}
        for _, id in ipairs(sortedKeys(server.monitors)) do
            local monitor = server.monitors[id]
            if monitor.online and (allMonitors or id == monitorId) then
                local slot = {id = id, width = monitor.width, height = monitor.height, windows = {}}
                for _, win in ipairs(windowsFor(id)) do
                    if not win.transientWindow and win.appName ~= "window_presets" and fit(win, monitor) then
                        slot.windows[#slot.windows + 1] = {appName = win.appName, layout = win.layout,
                            fullscreen = win.fullscreen, minimized = win.minimized, relative = Desktop.relative(win, monitor),
                            restore = copy(win.restore), view = viewSnapshot(server.views[win.id])}
                    end
                end
                slots[#slots + 1] = slot
            end
        end
        return slots
    end
    local function presetPlan(slots, assignments)
        local plan, destinations, valid = {}, {}, true
        for _, slot in ipairs(slots) do
            local id = assignments[slot.id]
            if id == nil then id = slot.id end
            local entry = {source = slot.id, target = id, windows = {}, items = {}, visible = 0, minimized = 0, skipped = 0}
            plan[#plan + 1] = entry
            local monitor = server.monitors[id]
            if id ~= false and (not monitor or not monitor.online or destinations[id]) then
                entry.error = monitor and monitor.online and "Already assigned" or "Monitor offline"
                valid = false
            elseif id ~= false then
                destinations[id] = true
                local placed = {}
                local smaller = monitor.width < slot.width or monitor.height < slot.height
                for i = #slot.windows, 1, -1 do
                    local spec = slot.windows[i]
                    local app = definition(spec.appName)
                    local title = app and app.title or spec.appName
                    local win = {appName = spec.appName, monitorId = id, layout = spec.layout,
                        fullscreen = spec.fullscreen, minimized = spec.minimized, relative = copy(spec.relative), restore = copy(spec.restore)}
                    local fits = app and not app.transientWindow and fit(win, monitor) and not win.tooSmall
                    if app and not app.transientWindow and not fits then
                        win.layout, win.fullscreen = "normal", nil
                        fits = fit(win, monitor) and not win.tooSmall
                    end
                    if fits then
                        if smaller and not win.minimized then
                            for _, other in ipairs(placed) do
                                if win.x < other.x + other.width and win.x + win.width > other.x
                                    and win.y < other.y + other.height and win.y + win.height > other.y then
                                    win.minimized = true
                                    break
                                end
                            end
                        end
                        if not win.minimized then placed[#placed + 1] = win end
                        entry.windows[#entry.windows + 1] = {win = win, view = viewSnapshot(spec.view)}
                        local field = win.minimized and "minimized" or "visible"
                        entry[field] = entry[field] + 1
                        entry.items[#entry.items + 1] = title .. " / " .. (win.minimized and "Minimized" or win.width .. "x" .. win.height)
                    else
                        entry.skipped = entry.skipped + 1
                        entry.items[#entry.items + 1] = title .. " / " .. (app and "Too small" or "Missing")
                    end
                end
            end
        end
        return plan, destinations, valid and next(destinations) ~= nil
    end
    function api.previewWindowPreset(slots, assignments)
        local plan, _, valid = presetPlan(slots, assignments or {})
        for _, item in ipairs(plan) do item.windows = nil end
        return plan, valid
    end
    function api.applyWindowPreset(slots, assignments)
        local plan, destinations, valid = presetPlan(slots, assignments or {})
        if not valid then return false, "Assign an online monitor to each slot" end
        local previous, nextId = state.windows, state.nextWindowId
        local windows, added, order = {}, {}, 0
        for id, win in pairs(previous) do
            if not destinations[win.monitorId] or win.transientWindow then
                windows[id] = win
                order = math.max(order, win.order)
            end
        end
        for _, slot in ipairs(plan) do
            for i = #slot.windows, 1, -1 do
                local item, id = slot.windows[i], nextId
                local win = item.win
                order, nextId = order + 1, nextId + 1
                win.id, win.order = id, order
                windows[id], server.views[id] = win, item.view
                added[#added + 1] = win
            end
        end
        state.windows, state.nextWindowId = windows, nextId
        local ok, err = server.save(true)
        if not ok then
            state.windows, state.nextWindowId = previous, nextId - #added
            for _, win in ipairs(added) do server.views[win.id] = nil end
            return false, err
        end
        for id, win in pairs(previous) do if not windows[id] then releaseWindow(win, state.appStates[win.appName]) end end
        for _, name in ipairs(sortedKeys(server.running)) do stopApp(name) end
        local failed = false
        for _, win in ipairs(added) do
            local started = startApp(win.appName)
            if started then
                local opened, accepted = appCall(win.appName, "onOpen", state.appStates[win.appName], api, viewContext(win))
                failed = failed or not opened or accepted == false
            else failed = true end
        end
        for id in pairs(destinations) do
            local monitor = server.monitors[id]
            monitor.launcher, monitor.layoutMenu, monitor.placement = nil, nil, nil
            invalidateInput(id)
        end
        return true, failed and "Some windows failed to start" or err
    end

    local function savedOutputOwners()
        local aliases, owners = {}, {}
        local coffee = state.appStates.coffee
        if type(coffee) == "table" and type(coffee.outputName) == "string" then aliases[coffee.outputName] = "coffee" end
        local emitter = state.appStates.level_emitter
        if type(emitter) == "table" and type(emitter.rules) == "table" then
            for _, rule in ipairs(emitter.rules) do
                if type(rule) == "table" and type(rule.outputName) == "string" then aliases[rule.outputName] = "level_emitter" end
            end
        end
        for name, mapping in pairs(state.outputMap) do
            local owner = type(mapping.owner) == "string" and mapping.owner or nil
            -- Imported Solar farm rules keep their old logical output names.
            if aliases[name] == "level_emitter" and owner == "solar_farm" then owner = "level_emitter" end
            owner = owner or aliases[name]
            if not owner then
                for _, legacy in ipairs(legacyOutputNames) do
                    if name:match(legacy[1]) then owner = legacy[2]; break end
                end
            end
            owners[name] = owner or "@settings"
            Work.check(32)
        end
        return owners
    end

    function api.getUsedIO()
        local result, groups, owners = {}, {}, savedOutputOwners()
        local function add(address, direction, owner)
            if type(address) ~= "table" or type(address.clientId) ~= "string" or not sideSet[address.side]
                or address.color ~= nil and not colour(address.color) then return end
            local key = address.clientId .. "/" .. address.side .. "/" .. tostring(address.color or "digital") .. "/" .. direction
            local entry = groups[key]
            if not entry then
                entry = {clientId = address.clientId, side = address.side, color = address.color, direction = direction, apps = {}}
                result[#result + 1], groups[key] = entry, entry
            end
            local app = definition(owner)
            local title = app and app.title or owner
            for _, name in ipairs(entry.apps) do if name == title then return end end
            entry.apps[#entry.apps + 1] = title
        end
        for name, address in pairs(state.outputMap) do
            add(address, "output", owners[name])
            Work.check(32)
        end
        -- Saved inputs remain visible even when the app has no open windows.
        local coffee = state.appStates.coffee or {}
        add(coffee.playerInput, "input", "coffee")
        local clock = state.appStates.clock or {}
        local emitter = state.appStates.level_emitter or {}
        for _, item in ipairs(clock.alarms or {}) do add(item.dismissInput, "input", "clock") end
        for _, item in ipairs(clock.timers or {}) do add(item.dismissInput, "input", "clock") end
        for _, item in ipairs(emitter.rules or {}) do add(item.dismissInput, "input", "level_emitter") end
        for _, name in ipairs(sortedKeys(server.apps)) do
            local ok, routes = appCall(name, "ioRoutes", state.appStates[name])
            if ok and type(routes) == "table" then
                for _, address in ipairs(routes) do
                    if type(address) == "table" and (address.direction == "input" or address.direction == "output") then
                        add(address, address.direction, name)
                    end
                end
            end
        end
        local order = {}
        for _, wire in ipairs(result) do
            table.sort(wire.apps)
            order[wire] = api.clientName(wire.clientId):lower() .. "/" .. wire.clientId .. "/" .. wire.side
                .. "/" .. wire.direction .. string.format("%05d", wire.color or 0)
            Work.check(24)
        end
        table.sort(result, function(a, b) return order[a] < order[b] end)
        return result
    end

    function api.getScreensavers()
        local app = server.apps.screensaver
        local result = {}
        for index, title in ipairs(app and type(app.screensavers) == "table" and app.screensavers or {}) do
            if type(title) ~= "string" or #title > 64 or index > 128 then break end
            result[index] = title
        end
        return result, installedApps.screensaver == true
    end

    local function resetTargets()
        local found = {}
        local function add(name)
            if type(name) == "string" and name:match("^[%w_-]+$") then found[name] = true end
        end
        for _, group in ipairs({installedApps, state.appRegistry, state.appStates, state.appearance.appColours, state.archivedRoutes}) do
            for name in pairs(group) do add(name) end
        end
        for _, win in pairs(state.windows) do add(win.appName) end
        for _, owner in pairs(savedOutputOwners()) do add(owner) end
        local apps = {}
        for name in pairs(found) do
            local app = server.apps[name]
            apps[#apps + 1] = {id = name, label = app and app.title or name}
        end
        table.sort(apps, function(a, b)
            local left, right = a.label:lower(), b.label:lower()
            if left == right then return a.id < b.id end
            return left < right
        end)
        local targets = {{id = "@all", label = "Entire OS"}, {id = "@settings", label = definition("@settings").title}}
        for _, app in ipairs(apps) do targets[#targets + 1] = app end
        return targets
    end

    local function resetSavedData(target)
        local label
        for _, entry in ipairs(resetTargets()) do if entry.id == target then label = entry.label; break end end
        if not label then return false, "Reset target is unavailable" end
        local entire = target == "@all"
        local resetDesktop = entire or target == "@settings"
        local function ownsData(name) return entire or name == target end
        local removals = {}
        for name, owner in pairs(savedOutputOwners()) do
            if ownsData(owner) then removals[#removals + 1] = {name = name, remove = true} end
        end

        -- Save the cleared data and the output removals in one checkpoint.
        -- Running apps and monitor dialogs stay intact until it succeeds.
        local previous = {windows = state.windows, appStates = state.appStates, appRegistry = state.appRegistry,
            appearance = state.appearance, desktops = state.desktops, archivedRoutes = state.archivedRoutes,
            clientNames = state.clientNames, uptimeHistory = state.uptimeHistory, alertHistory = state.alertHistory}
        local windows, appStates, registry = {}, {}, copy(previous.appRegistry)
        if not resetDesktop then
            for id, win in pairs(previous.windows) do if win.appName ~= target then windows[id] = win end end
        end
        for name, data in pairs(previous.appStates) do if not ownsData(name) then appStates[name] = data end end
        for name in pairs(server.apps) do if ownsData(name) then appStates[name] = {} end end
        appStates["@settings"] = appStates["@settings"] or {}
        for name in pairs(previous.appRegistry) do
            if ownsData(name) and not installedApps[name] then registry[name] = nil end
        end
        local appearance = copy(resetDesktop and defaultAppearance or previous.appearance)
        if resetDesktop then appearance.appColours = entire and {} or copy(previous.appearance.appColours) end
        appearance.appColours[target] = nil
        state.windows, state.appStates, state.appRegistry, state.appearance = windows, appStates, registry, appearance
        state.archivedRoutes = {}
        for name, routes in pairs(previous.archivedRoutes) do if not ownsData(name) then state.archivedRoutes[name] = routes end end
        state.alertHistory = {}
        if resetDesktop then state.desktops, state.clientNames, state.uptimeHistory = {}, {}, {}
        else
            for _, record in ipairs(previous.alertHistory) do
                if record.appName ~= target then state.alertHistory[#state.alertHistory + 1] = record end
            end
        end
        local ok, err = checkpointOutputs(removals, true)
        if not ok then
            for key, value in pairs(previous) do state[key] = value end
            return false, err
        end

        for id, win in pairs(previous.windows) do
            if not windows[id] then releaseWindow(win, previous.appStates[win.appName]) end
        end
        local stopped = {}
        for _, name in ipairs(sortedKeys(server.running)) do
            if ownsData(name) or resetDesktop and not isService(definition(name)) then
                appCall(name, "shutdown", previous.appStates[name], api, {appName = name})
                server.running[name], stopped[name] = nil, true
            end
        end
        for _, key in ipairs(sortedKeys(sensors.watches)) do
            local owner = sensors.watches[key].owner
            if ownsData(owner) or stopped[owner] then sensors.unwatch(key) end
        end
        if entire then server.notifications = {}
        else server.notifications[target] = nil end
        for id, monitor in pairs(server.monitors) do
            if resetDesktop then monitor.launcher, monitor.layoutMenu, monitor.placement, monitor.inbox = nil, nil, nil, nil end
            invalidateInput(id)
        end
        local reloaded = {}
        for _, name in ipairs(sortedKeys(server.apps)) do
            if ownsData(name) and loadApp(name) then reloaded[#reloaded + 1] = name end
        end
        for _, name in ipairs(reloaded) do if isService(server.apps[name]) then startApp(name) end end
        log("Reset saved data for " .. label)
        return true, err
    end
    local function appPath(name) return "apps_" .. name .. ".lua" end
    local function uninstallPath(name) return "uninstall_" .. name .. ".lua" end
    local function appTitle(name)
        local app = definition(name)
        return app and app.title or name
    end
    local function installedTargets()
        local result = {}
        for name in pairs(installedApps) do result[#result + 1] = {id = name, label = appTitle(name)} end
        table.sort(result, function(a, b)
            local left, right = a.label:lower(), b.label:lower()
            return left == right and a.id < b.id or left < right
        end)
        return result
    end

    local function stopForDataChange(name, oldState)
        if server.running[name] then appCall(name, "shutdown", oldState, api, {appName = name}) end
        server.running[name] = nil
        for _, key in ipairs(sortedKeys(sensors.watches)) do
            if sensors.watches[key].owner == name then sensors.unwatch(key) end
        end
        clearNotifications(name)
    end

    local function uninstallApp(name)
        if not installedApps[name] or not fs.exists(appPath(name)) then return false, "App file is unavailable" end
        local path, staged = appPath(name), uninstallPath(name)
        -- Recoverable staging: a boot before the checkpoint restores the
        -- executable. A boot after it completes the deletion.
        local ok, err = pcall(fs.move, path, staged)
        if not ok then return false, err end
        local previousWindows, previousArchive = state.windows, state.archivedRoutes
        local routes, removals, windows = {}, {}, {}
        for logical, owner in pairs(savedOutputOwners()) do
            if owner == name then
                routes[logical] = copy(state.outputMap[logical])
                removals[#removals + 1] = {name = logical, remove = true}
            end
        end
        for id, win in pairs(previousWindows) do if win.appName ~= name then windows[id] = win end end
        state.windows, state.archivedRoutes = windows, copy(previousArchive)
        state.archivedRoutes[name] = routes
        ok, err = checkpointOutputs(removals, true)
        if not ok then
            state.windows, state.archivedRoutes = previousWindows, previousArchive
            local restored, why = pcall(fs.move, staged, path)
            if not restored then log("App file recovery pending: " .. tostring(why)) end
            return false, err
        end
        for id, win in pairs(previousWindows) do
            if not windows[id] then releaseWindow(win, state.appStates[name]) end
        end
        stopForDataChange(name, state.appStates[name])
        server.apps[name], installedApps[name] = nil, nil
        for id in pairs(server.monitors) do invalidateInput(id) end
        local removed, why = pcall(fs.delete, staged)
        if not removed then
            log("App stopped; staged file cleanup pending: " .. tostring(why))
            return true, "Cleanup pending"
        end
        return true
    end

    local function restoreArchivedRoutes(name)
        local routes = state.archivedRoutes[name]
        if not routes then return true end
        local changes, owners = {}, {}
        for logical, route in pairs(routes) do
            if state.outputMap[logical] then return false, "Route already in use: " .. logical end
            changes[#changes + 1] = {name = logical, clientId = route.clientId, side = route.side,
                color = route.color, initialValue = false}
            owners[logical] = name
        end
        state.archivedRoutes[name] = nil
        local ok, err = checkpointOutputs(changes, true, owners)
        if not ok then state.archivedRoutes[name] = routes end
        return ok, err
    end

    local function backupPath(target)
        if target == "@all" then return "backup_os_all.txt" end
        if target == "@settings" then return "backup_os_settings.txt" end
        if type(target) == "string" and target:match("^[%w_-]+$") then return "backup_app_" .. target .. ".txt" end
    end
    local function backupBundle(target)
        local path = backupPath(target)
        if not path then return nil end
        return storage.load(path, function(bundle)
            return bundle.version == 1 and bundle.target == target and type(bundle.time) == "string"
                and type(bundle.data) == "table" and validState(bundle.data)
                and type(bundle.data.appStates) == "table" and type(bundle.data.outputMap) == "table"
                and type(bundle.data.windows) == "table" and type(bundle.data.appearance) == "table"
                and type(bundle.data.archivedRoutes) == "table" and type(bundle.data.alertHistory) == "table"
        end)
    end
    local function backupInfo(target)
        local bundle = backupBundle(target)
        if not bundle then return nil end
        local day = bundle.day and "Day " .. bundle.day .. " " or ""
        return day .. bundle.time .. " / " .. #sortedKeys(bundle.data.windows) .. " windows"
    end
    local function listBackups()
        local result, found = {}, {}
        local function include(id)
            if not found[id] and backupBundle(id) then
                result[#result + 1] = {id = id, label = id == "@all" and "Entire OS" or appTitle(id)}
                found[id] = true
            end
        end
        include("@all"); include("@settings")
        for _, file in ipairs(fs.list("")) do
            local base = file:gsub("%.bak$", ""):gsub("%.tmp$", "")
            local name = base:match("^backup_app_([%w_-]+)%.txt$")
            if name then include(name) end
        end
        table.sort(result, function(a, b)
            local function key(item)
                return item.id == "@all" and "0" or item.id == "@settings" and "1" or "2" .. item.label:lower()
            end
            local left, right = key(a), key(b)
            return left == right and a.id < b.id or left < right
        end)
        return result
    end

    local function createBackup(target)
        local path = backupPath(target)
        if not path then return false, "Invalid backup scope" end
        local all, desktop = target == "@all", target == "@all" or target == "@settings"
        local data = {appStates = {}, outputMap = {}, archivedRoutes = {}, alertHistory = {},
            appearance = desktop and copy(state.appearance) or {appColours = {}}}
        if not all then
            data.appearance.appColours = {}
            if not desktop then data.appearance.appColours[target] = state.appearance.appColours[target] end
        end
        for name, value in pairs(state.appStates) do if all or name == target then data.appStates[name] = copy(value) end end
        for logical, owner in pairs(savedOutputOwners()) do
            if all or owner == target then
                data.outputMap[logical] = copy(state.outputMap[logical])
                data.outputMap[logical].owner = owner
            end
        end
        for name, value in pairs(state.archivedRoutes) do if all or name == target then data.archivedRoutes[name] = copy(value) end end
        for _, item in ipairs(state.alertHistory) do
            if desktop or item.appName == target then data.alertHistory[#data.alertHistory + 1] = copy(item) end
        end
        data.windows = saveWindows(function(win) return desktop or win.appName == target end)
        if desktop then
            data.clientNames, data.desktops = copy(state.clientNames), copy(state.desktops)
            data.uptimeHistory = copy(state.uptimeHistory)
        end
        local bundle = stamp()
        bundle.target, bundle.version, bundle.data = target, 1, data
        local ok, err = storage.save(path, bundle, true)
        if ok then log("Backup saved to " .. path) end
        return ok, err
    end

    local function restoreBackup(target)
        local bundle = backupBundle(target)
        if not bundle then return false, "Backup missing or unreadable" end
        local data = bundle.data
        local all, desktop = target == "@all", target == "@all" or target == "@settings"
        local function owns(name) return all or name == target end
        local previous = {}
        for _, key in ipairs({"windows", "appStates", "appearance", "archivedRoutes", "desktops", "clientNames",
            "uptimeHistory", "alertHistory", "notificationSequence", "nextWindowId"}) do previous[key] = state[key] end
        local owners, changes, overrides = savedOutputOwners(), {}, {}
        local archive, wantedRoutes = {}, {}
        for name, routes in pairs(state.archivedRoutes) do if not owns(name) then archive[name] = copy(routes) end end
        for name, routes in pairs(data.archivedRoutes) do if owns(name) then archive[name] = copy(routes) end end
        for logical, route in pairs(data.outputMap) do
            local owner = route.owner
            if type(owner) ~= "string" or not owns(owner) then return false, "Invalid route owner" end
            if owners[logical] and not owns(owners[logical]) then return false, "Route already in use: " .. logical end
            if owner == "@settings" or server.apps[owner] then wantedRoutes[logical] = route
            else
                archive[owner] = archive[owner] or {}
                archive[owner][logical] = copy(route)
            end
        end
        for _, name in ipairs(sortedKeys(archive)) do
            if owns(name) and server.apps[name] then
                for logical, route in pairs(archive[name]) do
                    if owners[logical] and not owns(owners[logical]) then return false, "Route already in use: " .. logical end
                    wantedRoutes[logical] = copy(route)
                    wantedRoutes[logical].owner = name
                end
                archive[name] = nil
            end
        end
        for logical, owner in pairs(owners) do
            if owns(owner) and not wantedRoutes[logical] then changes[#changes + 1] = {name = logical, remove = true} end
        end
        for logical, route in pairs(wantedRoutes) do
            changes[#changes + 1] = {name = logical, clientId = route.clientId, side = route.side,
                color = route.color, initialValue = false}
            overrides[logical] = route.owner
        end

        local windows, viewStates, nextId, appStates = {}, {}, state.nextWindowId, {}
        for id, win in pairs(state.windows) do
            if not desktop and win.appName ~= target then windows[id] = win end
        end
        local missing = 0
        for _, key in ipairs(sortedKeys(data.windows)) do
            local old = data.windows[key]
            if type(old) ~= "table" or type(old.appName) ~= "string" or type(old.monitorId) ~= "string" then return false, "Invalid saved window" end
            if not old.transientWindow and (desktop or old.appName == target) then
                if definition(old.appName) then
                    local win = copy(old)
                    viewStates[nextId] = viewSnapshot(win.viewState)
                    win.viewState, win.id = nil, nextId
                    windows[nextId], nextId = win, nextId + 1
                else missing = missing + 1 end
            end
        end
        for name, value in pairs(state.appStates) do if not owns(name) then appStates[name] = value end end
        for name, value in pairs(data.appStates) do if owns(name) then appStates[name] = copy(value) end end
        for name in pairs(server.apps) do appStates[name] = appStates[name] or {} end
        appStates["@settings"] = appStates["@settings"] or {}
        local appearance = desktop and copy(data.appearance) or copy(state.appearance)
        if not all then
            appearance.appColours = copy(state.appearance.appColours)
            if not desktop then appearance.appColours[target] = (data.appearance.appColours or {})[target] end
        end
        appearance.appColours = appearance.appColours or {}
        for key, value in pairs(defaultAppearance) do if not colour(appearance[key]) then appearance[key] = value end end
        local alerts = {}
        if not desktop then
            for _, record in ipairs(state.alertHistory) do if record.appName ~= target then alerts[#alerts + 1] = record end end
        end
        local sequence = state.notificationSequence
        for _, record in ipairs(data.alertHistory) do
            if desktop or record.appName == target then
                local entry = copy(record)
                sequence = sequence + 1
                entry.sequence, entry.open = sequence, nil
                appendHistory(alerts, entry, 128)
            end
        end

        state.windows, state.appStates, state.appearance, state.archivedRoutes = windows, appStates, appearance, archive
        state.nextWindowId, state.alertHistory, state.notificationSequence = nextId, alerts, sequence
        if desktop then
            state.desktops, state.clientNames, state.uptimeHistory = data.desktops or {}, data.clientNames or {}, data.uptimeHistory or {}
        end
        for id, view in pairs(viewStates) do server.views[id] = view end
        local ok, err = checkpointOutputs(changes, true, overrides)
        if not ok then
            for key, value in pairs(previous) do state[key] = value end
            for id in pairs(viewStates) do server.views[id] = nil end
            return false, err
        end
        for id, win in pairs(previous.windows) do if not windows[id] then releaseWindow(win, previous.appStates[win.appName]) end end
        for _, name in ipairs(sortedKeys(server.running)) do
            if owns(name) then stopForDataChange(name, previous.appStates[name])
            else stopApp(name) end
        end
        for _, name in ipairs(sortedKeys(server.apps)) do
            if owns(name) then loadApp(name) end
            if server.apps[name] and (hasViews(name) or isService(server.apps[name])) then startApp(name) end
        end
        if hasViews("@settings") then startApp("@settings") end
        for id, monitor in pairs(server.monitors) do
            if desktop then monitor.launcher, monitor.layoutMenu, monitor.placement, monitor.inbox = nil, nil, nil, nil end
            invalidateInput(id)
        end
        log("Restored backup " .. backupPath(target))
        return true, missing > 0 and "Some apps need install" or err
    end

    server.systemApps["@settings"] = Settings.new({targets = resetTargets, reset = resetSavedData,
        installed = installedTargets, delete = uninstallApp, backups = listBackups, backupInfo = backupInfo,
        backup = createBackup, restore = restoreBackup})

    function api.placeWindow(id, x, y, width, height)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        local app=definition(win.appName)
        if not app then return false,"App is not available" end
        if app.fullscreenOnly then return false,"This app always fills its monitor" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        for _, value in pairs({x = x, y = y, width = width, height = height}) do
            if not integer(value, 1, 512) then return false, "Expected positive integer coordinates/sizes" end
        end
        local previous = copy(win)
        win.x, win.y, win.width, win.height = x or win.x, y or win.y, width or win.width, height or win.height
        win.layout, win.relative, win.restore, win.fullscreen = "normal", nil, nil, nil
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
        if definition(win.appName).fullscreenOnly then
            if mode=="restore" then return api.closeWindow(id) end
            return mode=="fullscreen",mode~="fullscreen" and "This app always fills its monitor" or nil
        end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        local previous = copy(win)
        if mode == "fullscreen" and win.fullscreen then return true end
        if mode ~= "restore" and mode ~= "fullscreen" and not win.fullscreen and win.layout == mode then return true end
        local exitingFullscreen = mode == "restore" and win.fullscreen
        if mode == "fullscreen" then
            if not Desktop.fullscreen(definition(win.appName), monitor) then return false, "App does not fit fullscreen" end
            -- Keep the complete normal layout/restore chain, not just its rectangle.
            win.fullscreen = true
        elseif exitingFullscreen then
            win.fullscreen = nil
        elseif mode == "restore" then
            local restore = win.restore or {layout = "normal", relative = win.relative}
            win.layout, win.relative, win.restore = restore.layout, copy(restore.relative), nil
        else
            local rect = Desktop.zone(mode, monitor)
            if not Desktop.fits(rect, definition(win.appName), monitor) then return false, "Layout does not fit this app" end
            win.restore = {layout = win.layout or "normal", relative = copy(win.relative)}
            win.layout, win.fullscreen = mode, nil
        end
        if not fit(win, monitor) and not exitingFullscreen then state.windows[id] = previous; return false, "Layout does not fit" end
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        if win.fullscreen then monitor.launcher, monitor.layoutMenu, monitor.placement = false, nil, nil end
        return true
    end
    local function beginPlacement(monitor, win, kind)
        monitor.launcher, monitor.layoutMenu = false, nil
        monitor.placement = {windowId = win.id, kind = kind}
    end
    local function updateCorner(placement, win, monitor)
        local a, b = placement.first, placement.point
        placement.preview = a and b and {x = math.min(a.x, b.x), y = math.min(a.y, b.y),
            width = math.abs(a.x - b.x) + 1, height = math.abs(a.y - b.y) + 1} or nil
        placement.valid = placement.preview and Desktop.fits(placement.preview, definition(win.appName), monitor) and true or false
        placement.error = placement.preview and not placement.valid and "Does not fit" or nil
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
        local fullscreen = fullscreenWindow(id)
        monitor.fullscreen = fullscreen and fullscreen.id or nil
        if fullscreen then active = fullscreen.id end
        for _, win in ipairs(windowsFor(id)) do
            if (not fullscreen or fullscreen.id == win.id) and fit(win, monitor) and not win.minimized and server.running[win.appName] then
                local body = Desktop.contentRect(win)
                if not win.fullscreen then
                    surface.fill(win.x, win.y, win.width, win.height, Gui.contrast(borderColour), borderColour)
                    write(win.x + 1, win.y, win.title, math.max(0, win.width - 10))
                    for _, control in ipairs(Desktop.controls(win)) do
                        local controlColour = control.action == "close" and 16384 or borderColour
                        surface.write(control.x1, win.y, control.label, Gui.contrast(controlColour), controlColour)
                    end
                end
                surface.fill(body.x, body.y, body.width, body.height, 32768, 256)
                local ok, content
                if win.tooSmall then ok, content = true, {"Window too small", "Top-right exits"}
                elseif server.dialogs[win.id] then
                    local dialog = server.dialogs[win.id]
                    ok = true
                    if dialog.kind == "colour" then
                        local option = systemColours[dialog.target]
                        dialog.current = option and state.appearance[option.field] or api.getAppColour(win.appName)
                        content, dialog.hits = Gui.palette(body.width, body.height, dialog.current,
                            dialog.error or (option and option.title or "UI color"))
                    elseif dialog.kind == "sensor" then
                        content = SensorPicker.render(dialog, body.width, body.height, api.getSensorClients(), api.clientName)
                    else
                        content = Picker.render(dialog, body.width, body.height, api.getIOClients(), api, ioTests[dialog.chosen.clientId])
                    end
                else
                    ok, content = appCall(win.appName, "render", body.width, body.height,
                        state.appStates[win.appName], api, viewContext(win))
                end
                if not ok or type(content) ~= "table" then content = {"App render failed"} end
                for y = 1, body.height do write(body.x, body.y + y - 1, content[y] or "", body.width) end
                for _, style in ipairs(type(content.styles) == "table" and content.styles or {}) do
                    if type(style) == "table" and integer(style.x, 1, body.width)
                        and integer(style.y, 1, body.height) and integer(style.width, 1, 512)
                        and integer(style.height or 1, 1, 512) then
                        surface.style(body.x + style.x - 1, body.y + style.y - 1,
                            math.min(style.width, body.width - style.x + 1), math.min(style.height or 1, body.height - style.y + 1),
                            style.fg, style.bg)
                    end
                end
            end
        end
        monitor.taskbar = {}
        if not fullscreen then
            local taskbar
            taskbar, monitor.taskbar = Desktop.taskbar(windowsFor(id, true), monitor, server.gameTime, desktopState(id), active)
            write(1, monitor.height, taskbar)
            surface.style(1, monitor.height, monitor.width, 1, Gui.contrast(taskbarColour), taskbarColour)
        end
        for _, hit in ipairs(monitor.taskbar) do
            if (hit.action == "launcher" and monitor.launcher) or (hit.action == "window" and hit.id == active) then
                local highlight = Gui.contrast(taskbarColour)
                surface.style(hit.x1, monitor.height, hit.x2 - hit.x1 + 1, 1, Gui.contrast(highlight), highlight)
            end
        end
        if not fullscreen and (monitor.launcher or monitor.layoutMenu) then
            local items, title, model
            if monitor.launcher then
                model, title = monitor, "Start"
                items = {{label = appTitle("@settings"), value = "@settings", enabled = compatible("@settings", monitor)}}
                for _, name in ipairs(sortedKeys(server.apps)) do
                    if compatible(name, monitor) then
                        items[#items + 1] = {label = (server.apps[name].title or name) .. (server.running[name] and " *" or ""), value = name, enabled = true}
                    end
                end
                local hasClock = false
                for _, hit in ipairs(monitor.taskbar) do if hit.action == "inbox" then hasClock = true; break end end
                if not hasClock then items[#items + 1] = {label = "Alert inbox", value = "@inbox", enabled = true} end
                table.sort(items,function(a,b)
                    local left=((definition(a.value) or {}).title or a.label):lower()
                    local right=((definition(b.value) or {}).title or b.label):lower()
                    return left==right and a.value<b.value or left<right
                end)
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
        local placement = not fullscreen and monitor.placement
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
            local hint = placement.error or (rect and "OK to apply" or placement.kind == "move" and "Pick position"
                or placement.first and "Other corner" or "First corner")
            if rect and not placement.error then hint = "OK: " .. rect.width .. "x" .. rect.height end
            if placement.kind == "custom" and placement.point then
                hint = placement.error or ((placement.first and "2:" or "1:") .. placement.point.x .. "," .. placement.point.y .. " OK")
            end
            write(1, 1, hint .. string.rep(" ", monitor.width))
            write(1, monitor.height, "[OK][Cancel]" .. string.rep(" ", math.max(0, monitor.width - 12)))
            surface.style(1, 1, monitor.width, 1, 1, 128)
            surface.style(1, monitor.height, 4, 1, 1, 8192)
            surface.style(5, monitor.height, 8, 1, 1, 16384)
            placement.hits = {}
            if placement.first then surface.write(placement.first.x, placement.first.y, "+", 1, 32) end
            if placement.point then surface.write(placement.point.x, placement.point.y, "+", 32768, 1) end
            if placement.kind == "move" and rect then
                if placement.valid then placement.hits = Desktop.moveArrows(rect, monitor) end
                for _, hit in ipairs(placement.hits) do surface.write(hit.x1, hit.y, hit.label, 1, 128) end
            elseif placement.kind == "custom" and placement.point then
                placement.hits, placement.pad = Desktop.pointArrows(placement.point, monitor, placement.pad)
                surface.fill(placement.pad.x, placement.pad.y, 5, 3, 1, 128)
                for _, hit in ipairs(placement.hits) do surface.write(hit.x1, hit.y, hit.label, 1, 2048) end
                local ready = not placement.first or placement.valid
                surface.style(1, monitor.height, 4, 1, 1, ready and 8192 or 128)
            end
            if placement.kind == "move" and rect or placement.kind == "custom" and placement.point then
                local x = monitor.width - 4
                surface.write(x, 1, "Place", 32768, 256)
                placement.hits[#placement.hits + 1] = {x1 = x, x2 = monitor.width, y = 1, action = "place"}
            end
        end
        monitor.inboxModel = nil
        if not fullscreen and monitor.inbox then
            local model = Inbox.render(monitor, state.alertHistory, api)
            monitor.inboxModel = model
            for y = 1, model.height do write(model.x, y, model.lines[y], model.width) end
            for _, style in ipairs(model.lines.styles) do
                surface.style(model.x + style.x - 1, style.y, style.width, style.height or 1, style.fg, style.bg)
            end
        end
        local notification = firstNotification()
        monitor.notification = notification and notificationModel(notification,monitor) or nil
        if notification then
            local popup = monitor.notification
            local x,y,w,h = popup.x,popup.y,popup.width,popup.height
            surface.fill(x,y,w,h,1,16384)
            if h>=3 then
                surface.fill(x,y,w,1,1,16384)
                surface.write(x+(w>=3 and 1 or 0),y,notification.title,nil,nil,math.max(1,w-2))
                local span=math.max(1,w-2)
                for row=1,math.max(0,h-4) do
                    local text=popup.lines[row] or ""
                    surface.write(x+1+math.max(0,math.floor((span-#text)/2)),y+row,text,1,16384,span)
                end
                if monitor.notificationError and h>=5 then surface.write(x+1,y+h-3,w>=22 and "Save failed; retry OK" or "Save failed",16,16384,math.max(1,w-2)) end
            end
            local hit=popup.ok
            surface.fill(hit.x1,hit.y,hit.x2-hit.x1+1,1,16384,1)
            surface.write(hit.x1+math.max(0,math.floor((hit.x2-hit.x1-1)/2)),hit.y,"OK",16384,1,hit.x2-hit.x1+1)
        end
        return surface.frame()
    end

    function server.refreshMonitors(force, onlyId)
        for id, monitor in pairs(server.monitors) do
            if monitor.online and (not onlyId or onlyId == id) then
                local previousStage = Work.stage
                Work.stage = "Rendering " .. id
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
                Work.stage = previousStage
                Work.check(16384)
            end
        end
    end

    local function touch(id, x, y)
        local monitor = server.monitors[id]
        if not integer(x, 1, monitor.width) or not integer(y, 1, monitor.height) then return end
        local notification = firstNotification()
        if notification then
            local popup=monitor.notification
            if popup and popup.key==notification.key and popup.appName==notification.appName and Gui.hit(popup.ok,x,y) then
                local ok,accepted,err=appCall(notification.appName,"handleNotification",notification.key,
                    state.appStates[notification.appName],api,{appName=notification.appName,monitorId=id})
                if not ok or accepted~=true then monitor.notificationError=tostring(ok and err or accepted) end
            end
            return -- Modal: no click-through into apps, taskbar or placement.
        end
        local fullscreen = fullscreenWindow(id)
        if fullscreen and x == monitor.width and y == 1 and not definition(fullscreen.appName).handlesFullscreenCorner then
            if definition(fullscreen.appName).fullscreenOnly then api.closeWindow(fullscreen.id)
            else api.layoutWindow(fullscreen.id, "restore") end
            return -- The invisible exit cell never reaches the app underneath.
        end
        if not fullscreen and monitor.inbox and monitor.inboxModel
            and Inbox.touch(monitor, monitor.inboxModel, api, x, y) then return end
        local placement = not fullscreen and monitor.placement
        if placement then
            local win = state.windows[placement.windowId]
            if not win then monitor.placement = nil; return end
            if y == monitor.height then
                if x >= 5 and x <= 12 then monitor.placement = nil
                elseif x <= 4 and placement.kind == "custom" and placement.point and not placement.first then
                    placement.first, placement.point, placement.pad = placement.point, nil, nil
                    placement.error = nil
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
                        placement.preview, placement.point, placement.pad, placement.valid, placement.error = nil, nil, nil, false, nil
                        return
                    end
                    if placement.kind == "custom" then
                        placement.point.x, placement.point.y = placement.point.x + hit.dx, placement.point.y + hit.dy
                        updateCorner(placement, win, monitor)
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
            else
                if placement.point then return end
                placement.point = {x = x, y = y}
                updateCorner(placement, win, monitor)
                return
            end
            placement.valid = Desktop.fits(placement.preview, definition(win.appName), monitor) and true or false
            placement.error = placement.preview and not placement.valid and "Does not fit" or nil
            return
        end
        if not fullscreen and y == monitor.height then
            for _, hit in ipairs(monitor.taskbar or {}) do
                if x >= hit.x1 and x <= hit.x2 then
                    monitor.layoutMenu = nil
                    if hit.action == "launcher" then
                        monitor.launcher = not monitor.launcher; monitor.menuPage = 1
                    elseif hit.action == "inbox" then
                        if monitor.inbox then monitor.inbox = nil else monitor.inbox = {} end
                        monitor.launcher, monitor.placement = false, nil
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
        local model = not fullscreen and (monitor.launcher and monitor or monitor.layoutMenu)
        if model then
            for _, hit in ipairs(model.menuHits or {}) do
                if Gui.hit(hit, x, y) then
                    if hit.action == "previous" then model.menuPage = math.max(1, model.menuPage - 1)
                    elseif hit.action == "next" then model.menuPage = math.min(model.menuPages, model.menuPage + 1)
                    elseif hit.item.enabled ~= false then
                        if monitor.launcher then
                            local existing
                            for _, win in ipairs(windowsFor(id)) do if win.appName == hit.item.value then existing = win end end
                            if hit.item.value == "@inbox" then monitor.inbox = {}
                            elseif existing then focus(existing); server.save() else api.openApp(hit.item.value, id) end
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
        local list = fullscreen and {fullscreen} or windowsFor(id)
        for index = #list, 1, -1 do
            local win = list[index]
            if not win.minimized and not win.doesNotFit and x >= win.x and x < win.x + win.width
                and y >= win.y and y < win.y + win.height then
                if not win.fullscreen and y == win.y then
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
                local body = Desktop.contentRect(win)
                local contentX, contentY = x - body.x + 1, y - body.y + 1
                if not win.tooSmall and contentX >= 1 and contentX <= body.width and contentY >= 1 and contentY <= body.height then
                    local dialog = server.dialogs[win.id]
                    if dialog then
                        local action, address
                        if dialog.kind == "colour" then
                            for _, hit in ipairs(dialog.hits or {}) do
                                if Gui.hit(hit, contentX, contentY) then action, address = hit.action, hit.value; break end
                            end
                            if action == "colour" then
                                local ok, err
                                if systemColourSetters[dialog.target] then ok, err = systemColourSetters[dialog.target](address)
                                else ok, err = api.setAppColour(win.appName, address) end
                                if ok then server.dialogs[win.id] = nil else dialog.error = tostring(err) end
                            elseif action == "cancel" then server.dialogs[win.id] = nil end
                        elseif dialog.kind == "sensor" then action, address = SensorPicker.touch(dialog, contentX, contentY)
                        else action, address = Picker.touch(dialog, contentX, contentY) end
                        if action == "cancel" then server.dialogs[win.id] = nil
                        elseif action == "test" then
                            local ok, err = testOutput(address)
                            if not ok then dialog.error = tostring(err) end
                        elseif action == "selected" then
                            local hook = dialog.kind == "sensor" and "handleSensorSelection" or "handleIOSelection"
                            local ok, accepted, err = appCall(win.appName, hook, dialog.key,
                                address, state.appStates[win.appName], api, viewContext(win))
                            if ok and accepted ~= false then server.dialogs[win.id] = nil
                            else dialog.error = tostring(ok and err or accepted) end
                        end
                    else
                        local ok, handled, replacement = appCall(win.appName, "handleTouch", contentX, contentY,
                            body.width, body.height, state.appStates[win.appName], api, viewContext(win))
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
            local groups = clientGroups
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
            if message.clientType == "relay" and (message.relayProtocol ~= 1
                or not integer(message.forwarded, 0, 2147483647)) then return end
            local client = group[id]
            local reconnect = not client or not client.online or client.computerId ~= message.sender
            client = client or {inputs = {}, values = {}, revision = 0, ackedRevision = -1}
            local ioReset, ioChanged = false, false
            client.computerId, client.channel, client.lastSeen, client.online = message.sender, replyChannel, now, true
            client.route = copy(message._route or {})
            if message.clientType == "relay" then client.forwarded = message.forwarded end
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
                ioChanged = ioChanged or ioReset
                ioReset = ioReset or ioChanged
                client.announceNonce = message.nonce
            end
            if message.clientType == "sensor" then sensors.announce(client, message, reconnect) end
            net.toClient(client, {type = "welcome", clientId = id, nonce = message.nonce, serverSession = server.session})
            if reconnect then
                client.since = now
                logUptime(id, message.clientType, true, now)
                log(message.clientType .. " connected: " .. id .. " (computer " .. message.sender .. ")")
            end
            if message.clientType == "io" then
                -- Routine announcements resend the same snapshot as a health
                -- check. They do not revoke an acknowledgement already earned.
                if ioReset then
                    history.offline(id, now)
                    ioTests[id] = nil
                    client.ackedRevision, client.outputSnapshot, client.wireRevisions = -1, nil, {}
                end
                server.syncIO(id, ioChanged)
            end
            if message.clientType == "monitor" then server.refreshMonitors(false, id) end
        elseif message.type == "inputData" then
            local client = registered(server.ioClients, message, replyChannel)
            if not client or not client.capabilities[message.side] or not integer(message.value, 0, 65535)
                or type(message.digital) ~= "boolean" then return end
            client.inputs[message.side] = {value = message.value, digital = message.digital}
            history.record(id, message.side, "input", now, message.value, message.digital)
            client.lastSeen = now
        elseif message.type == "ioAck" then
            local client = registered(server.ioClients, message, replyChannel)
            if client and message.revision == client.revision then
                client.ackedRevision, client.lastSeen = message.revision, now
                recordOutputs(id, client, now)
                local test = ioTests[id]
                if test and not test.acknowledged then
                    test.acknowledged = true
                    test.untilTime = math.min(test.untilTime, os.clock() + 1.5)
                end
            end
        elseif message.type == "sensorCatalog" or message.type == "sensorSample" then
            local client = registered(server.sensorClients, message, replyChannel)
            if client then
                if message.type == "sensorCatalog" then sensors.catalog(client, message, now) else sensors.sample(client, message, now) end
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
        logUptime(tostring(net.id), "os", true, os.clock())
        -- A persisted boot generation prevents stale output commands after an OS reboot.
        assert(server.save(), "Cannot checkpoint OS startup")
        for _, file in ipairs(fs.list("")) do
            local name = file:match("^uninstall_([%w_-]+)%.lua$")
            if name and not fs.isDir(file) then
                local ok, err
                if state.archivedRoutes[name] or fs.exists(appPath(name)) then ok, err = pcall(fs.delete, file)
                else ok, err = pcall(fs.move, file, appPath(name)) end
                if not ok then log("App file recovery failed: " .. tostring(err)) end
            end
        end
        for _, file in ipairs(fs.list("")) do
            local name = file:match("^apps_([%w_-]+)%.lua$")
            if name and name ~= "system" and not fs.isDir(file) then
                installedApps[name] = true
                -- Files and an old auto-populated registry are not consent to
                -- run an app. Only explicitly enabled user apps may execute.
                if config.enabledApps and config.enabledApps[name] == true then
                    loadApp(name)
                end
            end
        end
        local discard={}
        for id,win in pairs(state.windows) do
            local app=definition(win.appName)
            if win.transientWindow or app and app.transientWindow then discard[#discard+1]=id end
        end
        for _,id in ipairs(discard) do state.windows[id],server.views[id]=nil,nil end
        for _, name in ipairs(sortedKeys(server.apps)) do
            local ok, err = restoreArchivedRoutes(name)
            if not ok then log("Saved routes for " .. name .. ": " .. tostring(err)) end
            if isService(server.apps[name]) or hasViews(name) then startApp(name) end
        end
        for _, name in ipairs(sortedKeys(server.systemApps)) do if hasViews(name) then startApp(name) end end
        net.ensureModem()
        log("SmartHome OS computer " .. net.id .. ", network " .. net.config.networkId)
        if not net.modem then log("Attach a wireless modem; waiting...") end
    end

    function server.tick(now)
        net.ensureModem()
        for kind, group in pairs(clientGroups) do
            for id, client in pairs(group) do
                if client.online and now - client.lastSeen >= config.clientTimeout then
                    client.online = false
                    logUptime(id, kind, false, now, client.since)
                    if kind == "io" then history.offline(id, now) end
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
        for _, name in ipairs(sortedKeys(server.running)) do
            if server.running[name] then
                appCall(name, "background", dt, state.appStates[name], api)
                Work.check(16384)
            end
        end
        sensors.tick(now)
        for _, id in ipairs(sortedKeys(ioTests)) do
            if now >= ioTests[id].untilTime then
                ioTests[id] = nil
                server.syncIO(id, true)
            end
        end
        for id, client in pairs(server.ioClients) do
            if client.online and client.ackedRevision ~= client.revision
                and now - (client.lastSent or -math.huge) >= config.retryInterval then server.syncIO(id, false) end
        end
        server.refreshMonitors(false)
        -- Keep checkpoints within one second even when an older config says 30.
        if now - server.lastSave >= math.min(config.saveInterval, 1) then server.save() end
    end
    function server.nextTickInterval()
        local interval=config.tickInterval or 0.5
        for _,monitor in pairs(server.monitors) do if monitor.online and monitor.fullscreen then
            local win=state.windows[monitor.fullscreen]
            local app=win and definition(win.appName)
            if app and app.animationInterval then interval=math.min(interval,app.animationInterval) end
        end end
        return interval
    end

    function server.command(line)
        local args = {}
        for word in line:gmatch("%S+") do args[#args + 1] = word end
        local cmd = args[1]
        if not cmd then return {} end
        if cmd == "help" then return {
            "clients | sensors [client] | inputs <client>",
            "outputs | apps",
            "map <name> <client> <side> <color|digital>",
            "set <name> <on|off> | toggle <name>",
            "open <app> <monitor> | close <windowId>",
            "move <id> <x> <y> | resize <id> <width> <height>",
            "clear | save | errorlog | quit (saves and exits)",
        } end
        if cmd == "clear" then return {}, false, "clear"
        elseif cmd == "errorlog" then
            local file = fs.open("diagnostics_os_error.txt", "r")
            if not file then return {"No saved OS error report"} end
            local report = file.readAll(); file.close()
            local lines = {}; for line in (report .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
            return lines
        elseif cmd == "clients" then
            local lines = {}
            for _, item in ipairs(api.getClients()) do
                lines[#lines + 1] = item.id .. " " .. item.type .. " " .. (item.online and "ONLINE" or "offline")
                    .. " computer=" .. item.computerId
                    .. (#item.via > 0 and " via=" .. table.concat(item.via, ">") or " direct")
                    .. (item.type == "relay" and " forwarded=" .. tostring(item.forwarded or 0) or "")
            end
            if #lines == 0 then lines[1] = "No clients connected yet" end
            return lines
        elseif cmd == "sensors" then
            local lines = {}
            for _, client in ipairs(api.getSensorClients()) do
                if not args[2] or args[2] == client.id then
                    lines[#lines + 1] = client.id .. " " .. (client.online and "ONLINE" or "offline")
                        .. " protocol=" .. tostring(client.sensorProtocol or "legacy") .. " boot=" .. tostring(client.bootId or "unknown")
                    if #client.ports == 0 then lines[#lines + 1] = "  Waiting for sensor catalog" end
                    for _, port in ipairs(client.ports) do
                        local reactors = 0
                        for _, target in ipairs(port.targets) do if target.kind == "reactor" then reactors = reactors + 1 end end
                        lines[#lines + 1] = "  " .. port.side .. ": " .. port.status .. " / " .. port.cardKind
                            .. " / targets=" .. #port.targets .. " reactors=" .. reactors
                        lines[#lines + 1] = "    card=" .. tostring(port.card or "none")
                        if port.error then lines[#lines + 1] = "    " .. port.error end
                    end
                    for _, pending in ipairs(client.pending) do
                        lines[#lines + 1] = "  " .. pending.side .. " catalog parts=" .. pending.received .. "/" .. pending.parts
                    end
                    if client.catalogError then lines[#lines + 1] = "  Catalog rejected: " .. client.catalogError end
                end
            end
            if #lines == 0 then lines[1] = "No matching sensor clients" end
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
            local previous
            if cmd == "quit" then
                previous, state.uptimeHistory = state.uptimeHistory, copy(state.uptimeHistory)
                logUptime(tostring(net.id), "os", false, os.clock(), 0)
            end
            local ok, err = server.save()
            if not ok and previous then state.uptimeHistory = previous end
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
        for _, side in ipairs(sides) do
            local wanted = targets[side]
            if wanted and allowed(side) then
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
            elseif wanted then
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
        for _, side in ipairs(sides) do
            if peripheral.getType(side) == "monitor" then
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
            else client.devices[side] = nil end
        end
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
    ["main_os.lua"] = [=[-- Central OS. One serial loop owns state; cooperative pauses buffer incoming
-- events without running commands or changing app state during a checkpoint.
local Console = dofile("lib_console.lua")
local console = Console.new(term)
console.log("SmartHome OS v41: starting")
local Work = dofile("lib_work.lua")
-- The installer and another OS run may share CraftOS globals until reboot.
Work.disable()
local storage, Network, Server, networkConfig, config, net
local function finish(ok, err)
    Work.disable()
    if ok then return end
    local cancelled = tostring(err) == "Terminated" or tostring(err):match(":%s*Terminated$")
    if not cancelled then
        Work.report(Work.stage, err)
        console.log("OS stopped at: " .. Work.stage)
        console.log(tostring(err))
    end
    pcall(console.finish)
    error(err, 0)
end
-- Keep native bootstrap calls on the program's original thread, before any
-- protected cooperative worker. Show progress before loading saved app state.
local ok, err = pcall(function()
    Work.stage = "Loading OS configuration"
    storage = dofile("lib_storage.lua")
    Network = dofile("lib_network.lua")
    Server = dofile("lib_server.lua")
    networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
    config = storage.config("configs_os.txt", {
        saveFile = "configs_os_state.txt", tickInterval = 0.5,
        saveInterval = 1, clientTimeout = 15, retryInterval = 2, enabledApps = {},
    })
    assert(type(config.enabledApps) == "table", "Invalid enabledApps setting")
    for _, name in ipairs({"tickInterval", "saveInterval", "clientTimeout", "retryInterval"}) do
        assert(type(config[name]) == "number" and config[name] > 0, "Invalid OS setting: " .. name)
    end
    Work.stage = "Opening wireless modem"
    net = Network.new(networkConfig, true, console.log)
    net.ensureModem()
end)
finish(ok, err)

local server, timer, pauseTimer
local pending, head, tail, sequence = {}, 1, 0, 0
local function enqueue(item)
    item.received = os.clock()
    tail = tail + 1; pending[tail] = item
end
local function collect(item)
    local event = item[1]
    if event == "timer" and item[2] == pauseTimer then pauseTimer = nil; return end
    if event == "modem_message" or event == "peripheral" or event == "peripheral_detach" then enqueue(item)
    elseif event == "timer" and item[2] == timer then enqueue(item)
    else
        local command = console.handle(unpack(item))
        if command ~= nil then enqueue({"command", command}) end
    end
end
local function cooperate()
    sequence = sequence + 1
    -- A queued marker is the fast path. A native timer also wakes this pause
    -- if CC drops the marker from its finite event queue. Reuse one timer so
    -- fast successive pauses do not leave hundreds of timer events behind.
    if not pauseTimer then pauseTimer = os.startTimer(0) end
    local fallback = pauseTimer
    os.queueEvent("smarthome_server_yield", sequence)
    while true do
        local item = {os.pullEvent()}
        if item[1] == "smarthome_server_yield" and item[2] == sequence then return end
        if item[1] == "timer" and item[2] == fallback then pauseTimer = nil; return end
        collect(item)
    end
end
ok, err = Work.protect(function()
    Work.enable(cooperate)
    Work.stage = "Loading saved OS state"
    console.log("Loading saved OS state...")
    server = Server.new(net, storage, config, console.log)
    Work.stage = "Starting apps"
    console.log("Starting enabled apps...")
    server.start()
    console.log("Type help for commands; clear clears this console")
    if fs.exists("diagnostics_os_error.txt") then console.log("Saved OS error: type errorlog to read it") end
    timer = os.startTimer(server.nextTickInterval())
    while true do
        if head > tail then
            Work.stage = "Waiting for events"
            collect({os.pullEvent()})
        else
            local item = pending[head]
            pending[head], head = nil, head + 1
            local event, p1, p2, p3, p4 = unpack(item)
            if event == "modem_message" then
                Work.stage = "Receiving modem message"
                local message = net.receive(p1, p2, p3, p4)
                if message then
                    Work.stage = "Message " .. message.type .. " from " .. tostring(message.clientId)
                    server.handle(message, p3, item.received)
                end
            elseif event == "timer" and p1 == timer then
                Work.stage = "Background tick"
                server.tick(os.clock())
                timer = os.startTimer(server.nextTickInterval())
            elseif event == "peripheral" or event == "peripheral_detach" then
                Work.stage = "Peripheral change"
                net.peripheralChanged(p1)
            elseif event == "command" then
                Work.stage = "Command " .. p1
                local lines, quit, action = server.command(p1)
                if action == "clear" then console.clear() end
                for _, output in ipairs(lines) do console.log(output) end
                if quit then console.finish(); return end
            end
            if head > tail then pending, head, tail = {}, 1, 0 end
            Work.check(16384)
        end
    end
end)
finish(ok, err)
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
    ["lib_sensor_data.lua"] = [=[-- Shared bounded sensor data and OCS 1.4.7 field adapters. No peripherals here.
local Data = {protocol = 1, chunkSize = 12000, maxParts = 16, maxItemParts = 64, maxTargets = 4096, maxItems = 8192}
local sides = {top = true, bottom = true, left = true, right = true, front = true, back = true}
function Data.number(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
function Data.integer(v, lo, hi) return Data.number(v) and v == math.floor(v) and v >= lo and v <= hi end
function Data.string(v, limit) return type(v) == "string" and #v > 0 and #v <= limit and not v:find("[%c]") end
function Data.address(a)
    return type(a) == "table" and Data.string(a.clientId, 64) and sides[a.side] and Data.string(a.target, 128)
        and (a.card == nil or Data.string(a.card, 128))
end
function Data.clean(value, profile)
    local seen, count = {}, 0
    local function walk(v, depth)
        count = count + 1
        if count > (profile == "ae_items" and 60000 or 12000) or depth > 8 then error("Sensor reading is too large or deeply nested", 0) end
        if type(v) == "number" then assert(Data.number(v), "Invalid sensor number"); return v end
        if type(v) == "boolean" or v == nil then return v end
        if type(v) == "string" then assert(#v <= 2048, "Sensor string too long"); return v end
        assert(type(v) == "table" and not seen[v], "Invalid sensor value")
        seen[v] = true
        local result = {}
        for key, item in pairs(v) do
            assert(type(key) == "string" and #key <= 256 or Data.integer(key, -1000000000, 1000000000), "Invalid sensor key")
            result[key] = walk(item, depth + 1)
        end
        seen[v] = nil
        return result
    end
    local ok, result = pcall(walk, value, 0)
    if ok then return result end
    return nil, tostring(result)
end
-- Native AE details include the entire item list. Storage-only subscribers do
-- not need it; project before cleaning/encoding so large networks still fit.
function Data.aeSummary(value)
    if type(value) ~= "table" then return value end
    local result = {ItemsOmitted = true}
    for _, key in ipairs({"Name", "RawName", "Position", "Powered", "FreeTypes", "FreeCount", "FreeBytes",
        "UsedTypes", "UsedCount", "UsedBytes", "TotalBytes", "CellCount", "DriveCount"}) do result[key] = value[key] end
    return result
end
function Data.validProfile(profile) return profile == nil or profile == "ae_storage" or profile == "ae_items" end
function Data.profileRank(profile) return profile == "ae_storage" and 1 or profile == "ae_items" and 2 or 3 end
function Data.parts(profile) return profile == "ae_items" and Data.maxItemParts or Data.maxParts end
-- Compact the native item maps without discarding item identity or quantities.
-- Summary counters remain available to capacity apps sharing the same target.
function Data.aeItems(value)
    if type(value) ~= "table" then return value end
    local result = Data.aeSummary(value)
    result.ItemsOmitted, result.ItemsFormat = nil, "ae_compact_v1"
    if type(value.Items) ~= "table" then return result end
    result.Items, result.ItemsComplete = {}, true
    for _, item in pairs(value.Items) do
        if type(item) ~= "table" or not Data.integer(item.Size, 0, 9007199254740991) then return nil, "Invalid AE item count" end
        local raw = type(item.RawName) == "string" and item.RawName or ""
        local name = type(item.Name) == "string" and item.Name or raw
        local damage = item.DamageValue or item.Damagevalue or 0
        if #raw > 256 or #name > 256 or not Data.integer(damage, 0, 2147483647) then return nil, "Invalid AE item metadata" end
        if #result.Items >= Data.maxItems then return nil, "AE item catalog exceeds 8192 entries" end
        result.Items[#result.Items+1] = {raw, damage, name, item.Size}
    end
    table.sort(result.Items, function(a,b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[2] ~= b[2] then return a[2] < b[2] end
        if a[3] ~= b[3] then return a[3] < b[3] end
        return a[4] < b[4]
    end)
    return result
end
function Data.cardKind(card)
    local value = tostring(card or ""):lower():gsub("[%s_-]", "")
    if value:find("energistics", 1, true) or value:find("aesensor", 1, true) or value:find("appeng", 1, true) then return "ae" end
    if value:find("industrial", 1, true) or value:find("ic2", 1, true) or value:find("machine", 1, true) then return "machine" end
    if value:find("inventory", 1, true) then return "inventory" end
    if value:find("proximity", 1, true) then return "proximity" end
    if value:find("power", 1, true) then return "power" end
    if value:find("world", 1, true) then return "world" end
    return "unknown"
end
function Data.target(key, basic)
    basic = type(basic) == "table" and basic or {}
    local function name(value, limit)
        if type(value) ~= "string" then return nil end
        value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
        if #value > 0 then return value end
    end
    -- OCS 1.4.7 normally supplies Name/RawName, rather than Type. An empty
    -- display name must not poison an otherwise valid whole-side catalog.
    local raw = name(basic.RawName or basic.rawName, 128)
    local display = name(basic.Type, 96) or name(basic.type, 96) or name(basic.Name, 96)
        or raw and raw:sub(1, 96) or "Unknown"
    local identity = (display .. " " .. (raw or "")):lower()
    local result = {key = tostring(key), label = display, type = display, rawName = raw,
        kind = identity:find("reactor", 1, true) and "reactor" or "other"}
    local p = basic.Position or basic.position
    if type(p) == "table" and Data.number(p.X) and Data.number(p.Y) and Data.number(p.Z) then result.position = {X = p.X, Y = p.Y, Z = p.Z} end
    return result
end
local function numeric(data, names)
    for _, key in ipairs(names) do if Data.number(data[key]) and data[key] >= 0 then return data[key] end end
end
function Data.reactor(data)
    if type(data) ~= "table" then return nil end
    local heat = numeric(data, {"Heat", "heat", "Temperature"})
    local maximum = numeric(data, {"MaxHeat", "maxHeat", "MaximumHeat"})
    if not heat or not maximum or maximum <= 0 or heat > 1000000000000 or maximum > 1000000000000 then return nil end
    local result = {heat = heat, maxHeat = maximum, output = numeric(data, {"Output", "output", "EUOutput"}),
        energyEmitted = numeric(data, {"EnergyEmitted", "energyEmitted"}),
        energySunken = numeric(data, {"EnergySunken", "EnergySunk", "energySunken"})}
    for _, key in ipairs({"Active", "active", "IsActive"}) do
        if type(data[key]) == "boolean" then result.active = data[key]; break end
    end
    result.melting = numeric(data, {"Melting", "MeltingPoint", "MeltingTemperature"})
    if not result.melting then result.melting, result.meltingDerived = math.floor(maximum * 0.85), true end
    local function duration(value, ticks)
        if type(value) == "string" then
            value = value:match("^%s*(.-)%s*$")
            local h, m, s = value:match("^(%d+):(%d%d):(%d%d)$")
            if not ticks and h and tonumber(m) < 60 and tonumber(s) < 60 then
                value = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
            else value = tonumber(value) end
        end
        if Data.number(value) and value >= 0 and value <= 1000000000000 then return value end
    end
    for _, key in ipairs({"RemainingTime", "TimeRemaining", "Remaining", "remainingTime", "FuelRemainingSeconds",
        "RemainingSeconds", "remainingSeconds", "RemainingTimeSeconds", "TimeLeft", "timeLeft"}) do
        local value = duration(data[key])
        if value ~= nil then result.remaining, result.remainingField = value, key; break end
    end
    if result.remaining == nil then
        for _, key in ipairs({"RemainingTicks", "remainingTicks", "TimeLeftTicks"}) do
            local value = duration(data[key], true)
            if value ~= nil then result.remaining, result.remainingField = value / 20, key; break end
        end
    end
    result.heatToMelting, result.heatToMax = result.melting - heat, maximum - heat
    result.percent = heat / maximum * 100
    return result
end
return Data
]=],
    ["lib_sensor.lua"] = [=[-- Generic sensor bridge. Old OCS peripherals return queue IDs followed by
-- ocs_success/ocs_error events: no yielding through Lua 5.1 pcall is needed.
local Data = dofile("lib_sensor_data.lua")
local Sensor = {}
local sides = {"top", "bottom", "left", "right", "front", "back"}
function Sensor.new(net, config, logger)
    local log = logger or print
    local client = {connected = false, nonce = 0, lastAnnounce = -math.huge, lastServer = 0, ports = {}, watches = {}, sequence = 0}
    local pending, scanAt, cursor = nil, -math.huge, 0
    local expiredIds = {} -- OCS reuses small IDs independently on each sensor.
    local inspections = {}
    local function send(message)
        if not client.connected then return end
        message.clientId, message.serverSession, message.bootId = config.clientId, client.serverSession, config.bootId
        net.send(net.config.channel, client.serverId, message)
    end
    local function catalog(port)
        client.sequence = client.sequence + 1
        local count = math.max(1, math.ceil(#(port.targets or {}) / 64))
        for part = 1, count do
            local targets = {}
            for i = (part - 1) * 64 + 1, math.min(part * 64, #(port.targets or {})) do targets[#targets + 1] = port.targets[i] end
            send({type = "sensorCatalog", sequence = client.sequence, side = port.side, card = port.card,
                status = port.status, error = port.error, part = part, parts = count, targets = targets, truncated = port.truncated == true})
        end
    end
    local function sample(watch, data, err)
        client.sequence = client.sequence + 1
        local raw, profile
        if not err then
            local port = client.ports[watch.side]
            if port and Data.cardKind(port.card) == "ae" then
                profile = watch.profile
                if profile == "ae_storage" then data = Data.aeSummary(data)
                elseif profile == "ae_items" then data,err = Data.aeItems(data) end
            end
            if not err then data, err = Data.clean(data, profile) end
            if type(data) ~= "table" then err = err or "Target not found" end
            if not err then raw = textutils.serialize(data); if #raw > Data.chunkSize * Data.parts(profile) then err = "Reading exceeds network limit"; raw = nil end end
        end
        raw = raw or ""
        local port = client.ports[watch.side]
        if not err and watch.lastRaw == raw and watch.lastFull and os.clock() - watch.lastFull < 5 then
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, profile = profile, status = "ok", part = 1, parts = 1, data = "", unchanged = true, baseSequence = watch.lastFullSequence})
            return
        end
        if not err then watch.lastRaw, watch.lastFull, watch.lastFullSequence = raw, os.clock(), client.sequence else watch.lastRaw = nil end
        local parts = math.max(1, math.ceil(#raw / Data.chunkSize))
        for part = 1, parts do
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, profile = profile, status = err and "error" or "ok", error = err and tostring(err):sub(1, 160),
                part = part, parts = parts, data = raw:sub((part - 1) * Data.chunkSize + 1, part * Data.chunkSize)})
        end
    end
    local function complete(job, value, err)
        local port = client.ports[job.side]
        if job.kind == "inspect" then
            if not port or port.generation ~= job.generation or port.card ~= job.watch.card then
                job.callback(nil, "Sensor or card changed during inspection")
            else job.callback(value, err) end
            return
        end
        if not port or port.generation ~= job.generation then return end
        if job.kind == "name" then
            local previousCard, previousStatus = port.card, port.status
            port.nameAt = os.clock() + config.discoveryInterval
            if not Data.string(value, 128) or err then
                port.card, port.targets, port.status, port.error = nil, {}, "no_card", tostring(err or "No valid sensor card"):sub(1, 160)
            else
                if port.card ~= value then
                    port.card, port.targets, port.targetAt = value, {}, -math.huge
                    for _, watch in ipairs(client.watches) do if watch.side == port.side then watch.nextRead = 0 end end
                end
                port.status, port.error = "ok", nil
            end
            if previousCard ~= port.card or previousStatus ~= port.status then log(port.side .. ": " .. (port.card or port.error or port.status)) end
            if previousCard ~= port.card or previousStatus ~= port.status then catalog(port) end
        elseif job.kind == "targets" then
            local previousCount = #(port.targets or {})
            port.targetAt = os.clock() + config.discoveryInterval
            if type(value) ~= "table" or err then
                port.targets, port.status, port.error = {}, "error", tostring(err or "Invalid target list"):sub(1, 160)
            else
                local keys = {}
                for key in pairs(value) do if Data.string(key, 128) then keys[#keys + 1] = key end end
                table.sort(keys)
                port.targets, port.truncated = {}, #keys > Data.maxTargets
                for i = 1, math.min(#keys, Data.maxTargets) do port.targets[#port.targets + 1] = Data.target(keys[i], value[keys[i]]) end
                port.status, port.error = "ok", nil
            end
            if previousCount ~= #port.targets then log(port.side .. ": " .. #port.targets .. " targets") end
            catalog(port)
        else
            local watch = job.watch
            if watch and watch.card == port.card then sample(watch, value, err) end
        end
    end
    local function finishCall(job, ok, value)
        if not ok then pending = nil; complete(job, nil, value)
        elseif coroutine.status(job.thread) ~= "dead" then job.filter = value; pending = job
        elseif type(value) == "number" then
            if value < 0 then pending = nil; complete(job, nil, "Sensor rejected request")
            elseif expiredIds[value] then pending = nil; complete(job, nil, "Expired sensor response ID; retrying")
            else job.queueId, job.thread, job.filter = value, nil, nil; pending = job end
        else pending = nil; complete(job, value) end
    end
    local function start(port, kind, method, watch, callback)
        local job = {side = port.side, generation = port.generation, kind = kind, watch = watch, callback = callback, deadline = os.clock() + config.requestTimeout}
        job.thread = coroutine.create(function()
            if watch then return port.device[method](watch.target) end
            return port.device[method]()
        end)
        finishCall(job, coroutine.resume(job.thread))
    end
    function client.handleEvent(event, ...)
        local values = {...}
        local job = pending
        if not job then return end
        if job.queueId ~= nil then
            if (event == "ocs_success" or event == "ocs_error") and values[1] == job.queueId then
                pending = nil
                complete(job, event == "ocs_success" and values[2] or nil, event == "ocs_error" and tostring(values[2]) or nil)
            end
        elseif not job.filter or event == job.filter then finishCall(job, coroutine.resume(job.thread, event, unpack(values))) end
    end
    function client.handle(message, now)
        if message.clientId ~= config.clientId then return end
        if message.type == "welcome" then
            if message.nonce ~= client.nonce or type(message.serverSession) ~= "string" then return end
            if client.connected and message.sender ~= client.serverId then return end
            local changed = not client.connected or client.serverSession ~= message.serverSession
            client.connected, client.serverId, client.serverSession, client.lastServer = true, message.sender, message.serverSession, now
            if changed then
                client.watches = {}
                log("Connected to OS computer " .. client.serverId)
                for _, port in pairs(client.ports) do catalog(port) end
            end
        elseif message.type == "sensorWatch" and client.connected and message.sender == client.serverId
            and message.serverSession == client.serverSession and message.bootId == config.bootId
            and type(message.watches) == "table" and #message.watches <= 128 then
            local previous, watches, seen = client.watches, {}, {}
            for _, address in ipairs(message.watches) do
                if not Data.address(address) or address.clientId ~= config.clientId
                    or not Data.validProfile(address.profile) then return end
                seen[address.side] = seen[address.side] or {}
                if not seen[address.side][address.target] then
                    local watch = {side = address.side, target = address.target, card = address.card, profile = address.profile, nextRead = 0}
                    for _, old in ipairs(previous) do
                        if old.side == watch.side and old.target == watch.target and old.card == watch.card and old.profile == watch.profile then
                            watch.nextRead, watch.lastRaw, watch.lastFull, watch.lastFullSequence = old.nextRead, old.lastRaw, old.lastFull, old.lastFullSequence
                            break
                        end
                    end
                    watches[#watches + 1], seen[address.side][address.target] = watch, true
                end
            end
            client.watches, client.lastServer = watches, now
        end
    end
    -- Read-only local inspections share the same legacy OCS event/timeout queue.
    function client.inspectTarget(side, target, callback)
        if type(callback) ~= "function" or not Data.string(target, 128) or #inspections >= 16 then
            return false, "Invalid or excessive inspection request"
        end
        local port = client.ports[side]
        if not port or port.status ~= "ok" or not port.card then return false, "Sensor or card unavailable" end
        inspections[#inspections+1] = {watch={side=side,target=target,card=port.card},callback=callback}
        return true
    end
    function client.tick(now)
        if not net.ensureModem() or client.connected and now - client.lastServer >= config.timeout then
            client.connected, client.watches = false, {}
        end
        if now >= scanAt then
            scanAt = now + 1
            for _, side in ipairs(sides) do
                local port = client.ports[side]
                if peripheral.getType(side) == "sensor" then
                    if not port or port.status == "detached" then
                        client.ports[side] = {side = side, device = peripheral.wrap(side), targets = {}, status = "scanning",
                            generation = (port and port.generation or 0) + 1, nameAt = 0, targetAt = 0}
                        log("Sensor detected: " .. side)
                    end
                elseif port and port.status ~= "detached" then
                    port.status, port.card, port.targets, port.error = "detached", nil, {}, "Sensor detached"
                    port.generation = port.generation + 1
                    catalog(port)
                end
            end
        end
        if net.modem and now - client.lastAnnounce >= config.announceInterval then
            client.nonce, client.lastAnnounce = client.nonce + 1, now
            net.toServer({type = "announce", clientType = "sensor", sensorProtocol = Data.protocol,
                clientId = config.clientId, nonce = client.nonce, bootId = config.bootId, pollInterval = config.pollInterval})
        end
        if pending and now >= pending.deadline then
            local job = pending
            if job.queueId ~= nil then expiredIds[job.queueId] = true end
            pending = nil; complete(job, nil, "Sensor request timed out")
        end
        if pending then return end
        -- Discovery and samples share a bounded queue; modem events keep flowing.
        for _, side in ipairs(sides) do
            local port = client.ports[side]
            if port and port.status ~= "detached" then
                if now >= port.nameAt then start(port, "name", "getSensorName"); return end
                if port.card and now >= port.targetAt then start(port, "targets", "getTargets"); return end
            end
        end
        if #inspections > 0 then
            local request = table.remove(inspections, 1)
            local port = client.ports[request.watch.side]
            if port and port.status == "ok" and port.card == request.watch.card then
                start(port, "inspect", "getTargetDetails", request.watch, request.callback)
            else request.callback(nil, "Sensor or card unavailable") end
            return
        end
        if not client.connected then return end
        for _ = 1, #client.watches do
            cursor = cursor % #client.watches + 1
            local watch = client.watches[cursor]
            if now >= watch.nextRead then
                watch.nextRead = now + (watch.profile == "ae_items" and math.max(2, config.pollInterval) or config.pollInterval)
                local port = client.ports[watch.side]
                if port and port.status == "ok" and port.card == watch.card then start(port, "sample", "getTargetDetails", watch)
                else sample(watch, nil, "Sensor or card unavailable") end
                return
            end
        end
    end
    return client
end
-- Standalone report mode: never joins the wireless network, changes startup or
-- calls machine setters. Only getType/getMethods and the three OCS getters run.
function Sensor.inspect(selectedSide, selectedTarget)
    local sideSet = {top=true,bottom=true,left=true,right=true,front=true,back=true}
    assert(selectedSide == nil or selectedSide == "all" or sideSet[selectedSide], "Choose all or a sensor side")
    assert(not selectedTarget or sideSet[selectedSide] and Data.string(selectedTarget,128), "Specify SIDE before an exact TARGET")
    local storage = dofile("lib_storage.lua")
    local path, limit = "diagnostics_sensor.txt", 131072
    local report = {version=1,computerId=os.getComputerID(),started=os.clock(),mode="read-only local sensor inspection",
        selection=selectedSide or "mass_fabricators",target=selectedTarget,peripherals={},ports={},samples={}}
    if type(os.version) == "function" then local ok,value=pcall(os.version); if ok then report.craftOS=tostring(value):sub(1,128) end end
    for _,side in ipairs(sides) do
        local kind=peripheral.getType(side)
        local entry={side=side,type=kind or "none",methods={}}
        if kind and type(peripheral.getMethods)=="function" then
            local ok,methods=pcall(peripheral.getMethods,side)
            if ok and type(methods)=="table" then
                local names={}; for _,name in pairs(methods) do if type(name)=="string" then names[#names+1]=name:sub(1,64) end end
                table.sort(names)
                for i=1,math.min(32,#names) do entry.methods[i]=names[i] end
                entry.methodsOmitted=math.max(0,#names-32)
            else entry.methodsError=tostring(methods):sub(1,160) end
        elseif kind then entry.methodsError="peripheral.getMethods is unavailable" end
        report.peripherals[#report.peripherals+1]=entry
    end
    local net={config={},ensureModem=function() return false end}
    local config={clientId="inspection",bootId="inspection",requestTimeout=4,discoveryInterval=3600,announceInterval=3600,timeout=7200,pollInterval=1}
    local client=Sensor.new(net,config,function() end)
    local function save()
        while #textutils.serialize(report)>limit do
            local removed=false
            for i=#report.samples,1,-1 do
                for j=#report.samples[i].readings,1,-1 do
                    local reading=report.samples[i].readings[j]
                    if reading.data~=nil then
                        reading.data,reading.status,reading.error,reading.partial=nil,"error","Report size limit; reading omitted",true
                        removed=true; break
                    end
                end
                if removed then break end
            end
            if not removed then
                for i=#report.ports,1,-1 do
                    local port=report.ports[i]
                    if #port.targets>0 then table.remove(port.targets); port.targetsOmitted=port.targetsOmitted+1; removed=true; break end
                end
            end
            assert(removed,"Diagnostic metadata exceeds 128 KiB")
            report.truncated=true
        end
        local ok,err=storage.save(path,report); assert(ok,"Cannot save report: "..tostring(err))
    end
    local function runUntil(done,seconds)
        local deadline=os.clock()+seconds
        while not done() and os.clock()<deadline do
            client.tick(os.clock())
            if done() then return true end
            local timer=os.startTimer(0.1)
            repeat
                local event={os.pullEvent()}
                client.handleEvent(unpack(event))
                if done() then return true end
            until event[1]=="timer" and event[2]==timer
        end
        return done()
    end
    print("Read-only inspection; normal sensor service is paused")
    print("Discovering cards and targets...")
    save() -- Preserve an initial report even if a later request is interrupted.
    local discovered=runUntil(function()
        for _,side in ipairs(sides) do
            if peripheral.getType(side)=="sensor" then
                local port=client.ports[side]
                if not port or port.status=="scanning" or port.card and port.targetAt<=os.clock() then return false end
            end
        end
        return true
    end,30)
    report.discoveryComplete=discovered
    local selected,shown={},0
    for _,side in ipairs(sides) do
        local port=client.ports[side]
        if port then
            local entry={side=side,card=port.card,status=port.status,error=port.error,targets={},targetCount=#port.targets}
            for _,target in ipairs(port.targets) do
                if shown<64 then entry.targets[#entry.targets+1]=target; shown=shown+1 end
                local identity=((target.label or "").." "..(target.rawName or "").." "..(target.type or "")):lower():gsub("[%s_.%-]","")
                local matches = selectedTarget and side==selectedSide and target.key==selectedTarget
                    or not selectedTarget and (selectedSide=="all" or selectedSide==side or not selectedSide and identity:find("massfab",1,true))
                if matches then selected[#selected+1]={side=side,card=port.card,target=target} end
            end
            entry.targetsOmitted=entry.targetCount-#entry.targets
            report.ports[#report.ports+1]=entry
        end
    end
    report.matchedTargets,report.sampleLimit=#selected,32
    report.targetsOmitted=math.max(0,#selected-32)
    save()
    local function cleanReading(value)
        if type(value)~="table" then return nil,"Sensor returned no details table" end
        local clean,err=Data.clean(value)
        if clean and #textutils.serialize(clean)<=16384 then return clean end
        -- Keep scalar counters discoverable even if a catalog/nested value is huge.
        local preview,keys={},{}
        for key in pairs(value) do if type(key)=="string" and #key<=96 then keys[#keys+1]=key end end
        table.sort(keys,function(a,b)
            local function rank(key) return (Data.number(value[key]) or type(value[key])=="boolean") and 0 or 1 end
            if rank(a)~=rank(b) then return rank(a)<rank(b) end
            return a<b
        end)
        for i=1,math.min(64,#keys) do
            local key=keys[i]; local item=value[key]
            if type(item)=="string" then preview[key]=item:sub(1,256)
            elseif type(item)=="boolean" or Data.number(item) then preview[key]=item end
        end
        return preview,err or "Full details exceeded 16 KiB; scalar preview only",true
    end
    for i=1,math.min(32,#selected) do
        local source=selected[i]
        -- Old CraftOS rejects a table appearing twice, even without a cycle.
        -- Catalog and sample metadata need independent copies, including Position.
        report.samples[i]={side=source.side,card=source.card,target=assert(Data.clean(source.target)),readings={}}
    end
    -- Two dated samples expose changing counters without assuming any rate field
    -- means real production. The report never samples a GUI or the TAB screen.
    for pass=1,2 do
        if pass==2 then local due=os.clock()+2; runUntil(function() return os.clock()>=due end,3) end
        for i=1,#report.samples do
            local entry=report.samples[i]
            local reading={requestedAt=os.clock()}; entry.readings[pass]=reading
            local done=false
            print("Sample "..pass..": "..entry.side.." / "..entry.target.key)
            local ok,err=client.inspectTarget(entry.side,entry.target.key,function(value,errorText)
                reading.receivedAt=os.clock()
                if errorText then reading.status,reading.error="error",tostring(errorText):sub(1,160)
                else
                    reading.data,reading.error,reading.partial=cleanReading(value)
                    reading.status=not reading.data and "error" or reading.partial and "partial" or "ok"
                end
                done=true
            end)
            if not ok then reading.status,reading.error,done="error",err,true end
            if not runUntil(function() return done end,6) then reading.status,reading.error="error","Inspection did not complete" end
            if #textutils.serialize(report)>limit-1024 then
                reading.data,reading.status,reading.error,reading.partial=nil,"error","Report size limit; reading omitted",true
                report.truncated=true
            end
            save()
        end
    end
    report.finished=os.clock(); save()
    print("Saved "..path.." ("..#report.samples.." targets, two samples each)")
    if #selected==0 then print(selectedSide and "No matching target. See card/target discovery in the report." or "No Mass Fabricator found. See card/target discovery in the report.") end
    if report.targetsOmitted>0 then print("Target limit reached; inspect individual sides/targets for the remainder") end
    print("Share with: pastebin put "..path)
    print("Then reboot to resume the normal sensor client")
    return report
end
return Sensor
]=],
    ["lib_sensor_server.lua"] = [=[-- Runtime-only sensor catalogs, bounded multipart readings and subscriptions.
local Data = dofile("lib_sensor_data.lua")
local Hub = {}
local sides = {top = true, bottom = true, left = true, right = true, front = true, back = true}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function keys(values)
    local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result
end
function Hub.new(net, clients, session)
    local hub = {watches = {}}
    function hub.announce(client, message, reconnect)
        if message.sensorProtocol ~= Data.protocol or not Data.string(message.bootId, 96) then return end
        if reconnect or client.bootId ~= message.bootId then
            client.ports, client.catalogParts, client.readings, client.sampleParts, client.sensorSent = {}, {}, {}, {}, nil
            client.catalogError, client.catalogRejected = nil, 0
        end
        client.bootId, client.sensorProtocol = message.bootId, Data.protocol
        client.sensorMaxAge = Data.number(message.pollInterval) and message.pollInterval >= 0.5 and message.pollInterval <= 60
            and math.max(10, 3 * message.pollInterval) or 10
    end
    function hub.watch(key, address, options)
        if not Data.string(key, 96) or not Data.address(address) then return false, "Invalid sensor binding" end
        if options ~= nil and (type(options) ~= "table" or not Data.validProfile(options.profile) or options.profile == nil) then return false, "Invalid sensor profile" end
        hub.watches[key] = {address = copy(address), used = os.clock(), profile = options and options.profile}
        return true
    end
    function hub.unwatch(key) hub.watches[key] = nil end
    local function wanted(id, side, target)
        for _, item in pairs(hub.watches) do
            local a = item.address
            if os.clock() - item.used < 10 and a.clientId == id and a.side == side and a.target == target then return true end
        end
        return false
    end
    function hub.catalog(client, message, now)
        local function reject(reason)
            client.catalogError = reason
            client.catalogRejected = math.min((client.catalogRejected or 0) + 1, 2147483647)
            return false, reason
        end
        if client.sensorProtocol ~= Data.protocol or client.bootId ~= message.bootId or not sides[message.side]
            or not Data.integer(message.sequence, 1, 2147483647) or not Data.integer(message.parts, 1, 64)
            or not Data.integer(message.part, 1, message.parts) or type(message.targets) ~= "table" or #message.targets > 64
            or message.card ~= nil and not Data.string(message.card, 128)
            or not ({ok = true, scanning = true, error = true, no_card = true, detached = true})[message.status] then
            return reject("Invalid catalog header or sensor version")
        end
        local targets = {}
        for _, entry in ipairs(message.targets) do
            if type(entry) ~= "table" or not Data.string(entry.key, 128)
                or entry.type ~= nil and (type(entry.type) ~= "string" or #entry.type > 96)
                or entry.rawName ~= nil and (type(entry.rawName) ~= "string" or #entry.rawName > 128) then
                return reject("Invalid target metadata")
            end
            targets[#targets + 1] = Data.target(entry.key, {Type = entry.type, RawName = entry.rawName, Position = entry.position})
        end
        local current = client.ports[message.side]
        if current and message.sequence <= current.sequence then return end
        local pending = client.catalogParts[message.side]
        if pending and message.sequence < pending.sequence then return end
        if not pending or pending.sequence ~= message.sequence then
            pending = {sequence = message.sequence, parts = message.parts, card = message.card, status = message.status, chunks = {}, time = now}
            client.catalogParts[message.side] = pending
        end
        if pending.parts ~= message.parts or pending.card ~= message.card or pending.status ~= message.status then
            return reject("Conflicting catalog parts")
        end
        pending.chunks[message.part] = targets
        if current and current.card ~= message.card then current.status = "card_changed" end
        local all, seen = {}, {}
        for part = 1, pending.parts do
            if not pending.chunks[part] then return end
            for _, target in ipairs(pending.chunks[part]) do
                if seen[target.key] then return reject("Duplicate target address") end
                seen[target.key], all[#all + 1] = true, target
            end
        end
        table.sort(all, function(a, b) return a.key < b.key end)
        client.ports[message.side] = {side = message.side, card = message.card, cardKind = Data.cardKind(message.card),
            status = message.status, error = type(message.error) == "string" and message.error:sub(1, 160) or nil,
            sequence = message.sequence, targets = all, time = now, truncated = message.truncated == true}
        client.catalogParts[message.side] = nil
        client.catalogError = nil
        client.lastSeen = now
        if not current or current.card ~= message.card or message.status ~= "ok" then
            client.readings[message.side], client.sampleParts[message.side], client.sensorSent = {}, {}, nil
        end
    end
    function hub.sample(client, message, now)
        if client.sensorProtocol ~= Data.protocol or client.bootId ~= message.bootId or not sides[message.side]
            or not Data.string(message.target, 128) or not Data.integer(message.sequence, 1, 2147483647)
            or not Data.validProfile(message.profile) or not Data.integer(message.parts, 1, Data.parts(message.profile)) or not Data.integer(message.part, 1, message.parts)
            or type(message.data) ~= "string" or #message.data > Data.chunkSize
            or (message.status ~= "ok" and message.status ~= "error") or not wanted(message.clientId, message.side, message.target) then return end
        local port = client.ports[message.side]
        if not port or port.card ~= message.card then return end
        client.readings[message.side], client.sampleParts[message.side] = client.readings[message.side] or {}, client.sampleParts[message.side] or {}
        local readings, parts = client.readings[message.side], client.sampleParts[message.side]
        local current, pending = readings[message.target], parts[message.target]
        if current and message.sequence <= current.sequence or pending and message.sequence < pending.sequence then return end
        if message.unchanged then
            if message.parts ~= 1 or message.part ~= 1 or message.status ~= "ok" or message.data ~= ""
                or not current or not current.data or current.profile ~= message.profile or current.dataSequence ~= message.baseSequence then return end
            current.sequence, current.status, current.error, current.time, current.dataTime = message.sequence, "ok", nil, now, now
            parts[message.target], client.lastSeen = nil, now
            return
        end
        if not pending or pending.sequence ~= message.sequence then
            pending = {sequence = message.sequence, parts = message.parts, status = message.status, card = message.card, profile = message.profile, chunks = {}, time = now}
            parts[message.target] = pending
        end
        if pending.parts ~= message.parts or pending.status ~= message.status or pending.card ~= message.card or pending.profile ~= message.profile then return end
        pending.chunks[message.part] = message.data
        for part = 1, pending.parts do if not pending.chunks[part] then return end end
        local data, err
        if pending.status == "ok" then
            local ok, value = pcall(textutils.unserialize, table.concat(pending.chunks))
            if not ok or type(value) ~= "table" then return end
            data, err = Data.clean(value, pending.profile)
            if not data then return end
        else err = type(message.error) == "string" and message.error:sub(1, 160) or "Sensor read failed" end
        readings[message.target] = {sequence = message.sequence, card = message.card, profile = pending.profile, status = pending.status,
            data = data or current and current.data, error = err, time = now, dataTime = data and now or current and current.dataTime,
            dataSequence = data and message.sequence or current and current.dataSequence}
        parts[message.target], client.lastSeen = nil, now
    end
    function hub.getClients()
        local result = {}
        for _, id in ipairs(keys(clients)) do
            local client = clients[id]
            local ports = {}
            for _, side in ipairs(keys(client.ports or {})) do ports[#ports + 1] = copy(client.ports[side]) end
            local pending = {}
            for _, side in ipairs(keys(client.catalogParts or {})) do
                local part, received = client.catalogParts[side], 0
                for _ in pairs(part.chunks) do received = received + 1 end
                pending[#pending + 1] = {side = side, received = received, parts = part.parts}
            end
            result[#result + 1] = {id = id, online = client.online, computerId = client.computerId, ports = ports,
                sensorProtocol = client.sensorProtocol, bootId = client.bootId,
                catalogError = client.catalogError, catalogRejected = client.catalogRejected or 0, pending = pending}
        end
        return result
    end
    function hub.read(address, options)
        if not Data.address(address) then return {status = "unconfigured", error = "Select a sensor target"} end
        local client = clients[address.clientId]
        if not client or not client.online then return {status = "offline", error = "Sensor client offline"} end
        local port = client.ports and client.ports[address.side]
        if not port then return {status = "waiting", error = "Waiting for sensor catalog"} end
        if port.status ~= "ok" then return {status = port.status, error = port.error or "Sensor unavailable"} end
        if address.card and address.card ~= port.card then return {status = "card_changed", error = "Sensor card changed"} end
        local found
        for _, target in ipairs(port.targets) do if target.key == address.target then found = target; break end end
        if not found then return {status = "missing", error = "Target missing or out of range"} end
        if address.targetType and address.targetType ~= found.type then return {status = "target_changed", error = "Target type changed"} end
        local reading = client.readings[address.side] and client.readings[address.side][address.target]
        if not reading then return {status = "waiting", error = "Waiting for reading"} end
        local result = {}
        for field, value in pairs(reading) do
            result[field] = copy(field == "data" and options and options.profile == "ae_storage" and Data.aeSummary(value) or value)
        end
        result.age, result.target = math.max(0, os.clock() - (reading.dataTime or reading.time)), copy(found)
        result.maxAge = client.sensorMaxAge
        if result.age > client.sensorMaxAge and result.status == "ok" then result.status, result.error = "stale", "Reading outdated" end
        result.reactor = Data.reactor(result.data)
        return result
    end
    function hub.tick(now)
        local requests = {}
        -- Legacy ComputerCraft next can reject a cursor after its entry was
        -- deleted. Traverse key snapshots whenever pruning runtime tables.
        for _, key in ipairs(keys(hub.watches)) do
            local item = hub.watches[key]
            if now - item.used >= 10 then hub.watches[key] = nil
            else
                local a = copy(item.address)
                a.profile = item.profile
                requests[a.clientId] = requests[a.clientId] or {}
                requests[a.clientId][#requests[a.clientId] + 1] = a
            end
        end
        for id, client in pairs(clients) do
            if client.online and client.sensorProtocol == Data.protocol then
                local list, seen = {}, {}
                table.sort(requests[id] or {}, function(a, b) return a.side .. a.target < b.side .. b.target end)
                for _, source in ipairs(requests[id] or {}) do
                    seen[source.side] = seen[source.side] or {}
                    local index = seen[source.side][source.target]
                    if not index and #list < 128 then
                        local a = copy(source)
                        local port = client.ports[a.side]
                        a.card = a.card or port and port.card
                        list[#list + 1], seen[a.side][a.target] = a, #list + 1
                    elseif index and Data.profileRank(source.profile) > Data.profileRank(list[index].profile) then
                        list[index].profile = source.profile -- Richer subscribers win; the target is still polled once.
                    end
                end
                local signature = textutils.serialize(list)
                if signature ~= client.sensorSignature or not client.sensorSent or now - client.sensorSent >= 3 then
                    net.toClient(client, {type = "sensorWatch", clientId = id, serverSession = session, bootId = client.bootId, watches = list})
                    client.sensorSignature, client.sensorSent = signature, now
                end
                for side, set in pairs(client.sampleParts or {}) do
                    for _, target in ipairs(keys(set)) do if now - set[target].time > 10 then set[target] = nil end end
                end
                for side, readings in pairs(client.readings or {}) do
                    for _, target in ipairs(keys(readings)) do if not wanted(id, side, target) then readings[target] = nil end end
                end
                for _, side in ipairs(keys(client.catalogParts or {})) do
                    if now - client.catalogParts[side].time > 10 then client.catalogParts[side] = nil end
                end
            end
        end
    end
    return hub
end
return Hub
]=],
    ["lib_sensor_picker.lua"] = [=[-- Shared client -> sensor port -> target selection, rendered centrally.
local Gui = dofile("lib_gui.lua")
local Picker = {}
function Picker.new(key, current, kind)
    return {kind = "sensor", key = key, chosen = current or {}, filter = kind, stage = 1, page = 1}
end
function Picker.render(dialog, width, height, clients, clientName)
    local label = clientName or function(id) return id end
    local list, chosen, selectedClient, selectedPort = {}, dialog.chosen
    local function compatible(port)
        if port.status ~= "ok" or not port.card then return false end
        if not dialog.filter then return true end
        if dialog.filter ~= "reactor" then return port.cardKind == dialog.filter end
        if port.cardKind == "machine" or port.cardKind == "unknown" then return true end
        for _, target in ipairs(port.targets) do if target.kind == "reactor" then return true end end
        return false
    end
    if dialog.stage == 1 then
        for _, client in ipairs(clients) do list[#list + 1] = {label = label(client.id) .. (client.online and " +" or " -"), value = client.id} end
    elseif dialog.stage == 2 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            selectedClient = client
            for _, port in ipairs(client.ports) do
                local enabled = compatible(port)
                local detail = port.status ~= "ok" and port.status or port.cardKind
                list[#list + 1] = {label = port.side .. " / " .. detail .. (not enabled and port.status == "ok" and " (other card)" or ""),
                    value = port.side, card = port.card, enabled = enabled}
            end
        end end
    elseif dialog.stage == 3 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            for _, port in ipairs(client.ports) do if port.side == chosen.side then
                selectedPort = port
                for _, target in ipairs(port.targets) do
                    if not dialog.filter or dialog.filter == "reactor" and (target.kind == "reactor" or target.type == "Unknown")
                        or dialog.filter ~= "reactor" and port.cardKind == dialog.filter then
                        list[#list + 1] = {label = target.key .. " " .. target.label, value = target.key, targetType = target.type}
                    end
                end
            end end
        end end
    end
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    if dialog.stage == 4 then
        ui.heading("Use sensor?", 2048)
        ui.text(2, label(chosen.clientId)); ui.text(3, chosen.side .. " / " .. chosen.target)
        if height >= 7 then ui.text(4, chosen.targetType or "") end
        if dialog.error then ui.text(height - 2, dialog.error) end
        ui.button(height - 1, "Back", "back")
        ui.button(height, "Use", "use", 1, math.floor(width / 2), true, 32)
        ui.button(height, "Cancel", "cancel", math.floor(width / 2) + 1, width)
    else
        local path = dialog.stage>1 and Gui.breadcrumb(dialog.stage==3 and {label(chosen.clientId),chosen.side} or {label(chosen.clientId)},width,height)
        local header = path and 2 or 1
        local slots = #list<=height-header-1 and height-header-1 or height-header-2
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        ui.heading(({"Sensor client", "Sensor side", "Select target"})[dialog.stage], 2048)
        if path then ui.text(2,path); ui.style(1,2,width,1,256,32768) end
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then ui.button(row + header, item.label, "select", nil, nil, item.enabled ~= false, nil, nil, item) end
        end
        if #list == 0 then
            local message = "No sensor clients yet"
            if dialog.stage == 2 then
                message = selectedClient and selectedClient.online and "Waiting for catalog" or "Sensor client offline"
                if selectedClient and selectedClient.catalogError then
                    message = "Catalog rejected"
                    ui.text(header+2, selectedClient.catalogError)
                end
            elseif dialog.stage == 3 then
                message = selectedPort and #selectedPort.targets > 0 and "No matching targets" or "No targets yet"
            end
            ui.text(header+1, message)
        end
        if pages > 1 then
            ui.button(height - 1, "< Prev", "prev", 1, math.floor(width / 2), dialog.page > 1)
            ui.button(height - 1, "Next >", "next", math.floor(width / 2) + 1, width, dialog.page < pages, nil, nil, pages)
        end
        ui.button(height, "Back", "back", 1, math.floor(width / 2))
        ui.button(height, "Cancel", "cancel", math.floor(width / 2) + 1, width)
    end
    dialog.hits = ui.hits
    return ui.lines
end
function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do if hit.enabled ~= false and Gui.hit(hit, x, y) then
        dialog.error = nil
        if hit.action == "cancel" then return "cancel"
        elseif hit.action == "use" then return "selected", dialog.chosen
        elseif hit.action == "back" then
            if dialog.stage == 1 then return "cancel" end
            dialog.stage, dialog.page = dialog.stage - 1, 1
        elseif hit.action == "prev" then dialog.page = math.max(1, dialog.page - 1)
        elseif hit.action == "next" then dialog.page = math.min(hit.value, dialog.page + 1)
        elseif hit.action == "select" then
            local item = hit.value
            if dialog.stage == 1 then dialog.chosen = {clientId = item.value}
            elseif dialog.stage == 2 then dialog.chosen.side, dialog.chosen.card = item.value, item.card
            else dialog.chosen.target, dialog.chosen.targetType = item.value, item.targetType end
            dialog.stage, dialog.page = dialog.stage + 1, 1
        end
        return
    end end
end
return Picker
]=],
    ["clients_sensor_client.lua"] = [=[-- Generic OpenCCSensors bridge; all names/configuration stay in the root.
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Sensor = dofile("lib_sensor.lua")
local args = {...}
if args[1] == "inspect" then
    assert(not args[4], "Usage: clients_sensor_client.lua inspect [all|SIDE [TARGET]]")
    Sensor.inspect(args[2], args[3])
    return
end
assert(args[1] == nil, "Usage: clients_sensor_client.lua [inspect [all|SIDE [TARGET]]]")
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_sensor.txt", {clientId = "sensor_" .. os.getComputerID(),
    announceInterval = 5, timeout = 15, discoveryInterval = 5, pollInterval = 1, requestTimeout = 4, bootCounter = 0})
assert(type(config.clientId) == "string" and #config.clientId > 0 and #config.clientId <= 64, "Invalid sensor client ID")
for _, field in ipairs({"announceInterval", "discoveryInterval", "pollInterval", "requestTimeout"}) do
    assert(type(config[field]) == "number" and config[field] >= 0.5 and config[field] <= 60, "Invalid " .. field)
end
assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid sensor timeout")
assert(type(config.bootCounter) == "number" and config.bootCounter >= 0 and config.bootCounter < 2147483647, "Invalid sensor boot counter")
config.bootCounter = math.floor(config.bootCounter) + 1
assert(storage.save("configs_sensor.txt", config), "Cannot checkpoint sensor startup")
config.bootId = config.clientId .. ":" .. config.bootCounter
local net = Network.new(networkConfig, false)
local client = Sensor.new(net, config)
print("Sensor client: " .. config.clientId .. " (computer " .. net.id .. ")")
client.tick(os.clock())
local timer = os.startTimer(0.1)
while true do
    local event = {os.pullEvent()}
    if event[1] == "modem_message" then
        local message = net.receive(event[2], event[3], event[4], event[5])
        if message then client.handle(message, os.clock()) end
    elseif event[1] == "timer" and event[2] == timer then
        client.tick(os.clock()); timer = os.startTimer(0.1)
    elseif event[1] == "peripheral" or event[1] == "peripheral_detach" then net.peripheralChanged(event[2]) end
    client.handleEvent(unpack(event))
end
]=],
    ["lib_relay.lua"] = [=[-- Stateless forwarding never replaces the original endpoint identity/session.
local Network = dofile("lib_network.lua")
local Relay = {}

function Relay.new(net, config)
    assert(net.config.relayEnabled ~= false, "Relay requires relayEnabled in network settings")
    local client = {connected = false, nonce = 0, forwarded = 0, lastAnnounce = -math.huge}
    local remember = Network.newCache(4096, 60)

    function client.handleModem(side, channel, replyChannel, raw, now)
        local message, packet = net.receiveForRelay(side, channel, replyChannel, raw)
        if message and message.type == "welcome" and message.clientId == config.clientId
            and message.nonce == client.nonce and type(message.serverSession) == "string"
            and (not client.connected or message.sender == client.serverId) then
            local changed = not client.connected or client.serverSession ~= message.serverSession
            client.connected, client.serverId, client.serverSession, client.lastServer = true, message.sender, message.serverSession, now
            if changed then print("Connected to OS computer " .. client.serverId) end
        end
        if not packet or packet.recipient == net.id then return end
        for _, hop in ipairs(packet._transport.path) do if hop.computerId == net.id then return end end
        if not remember(Network.packetKey(packet), now) then return end
        if net.forward(packet, replyChannel, config.clientId) then client.forwarded = client.forwarded + 1 end
    end

    function client.tick(now)
        if not net.ensureModem() or client.connected and now - client.lastServer >= config.timeout then
            if client.connected then print("OS connection lost; waiting for a route") end
            client.connected = false
        end
        if net.modem and now - client.lastAnnounce >= config.announceInterval then
            client.nonce, client.lastAnnounce = client.nonce + 1, now
            net.toServer({type = "announce", clientType = "relay", clientId = config.clientId,
                nonce = client.nonce, relayProtocol = 1, forwarded = math.min(client.forwarded, 2147483647)})
        end
    end
    return client
end

return Relay
]=],
    ["clients_relay_client.lua"] = [=[-- A single wireless modem bridges all updated SmartHome roles in both directions.
local Work = dofile("lib_work.lua")
Work.disable()
local report = {path = "diagnostics_relay_error.txt", title = "SmartHome relay v40, computer " .. os.getComputerID()}
local net, client

local function finish(ok, err)
    Work.disable()
    if ok then return end
    local message = tostring(err)
    if message ~= "Terminated" and not message:match(":%s*Terminated$") then
        print("Relay stopped during: " .. Work.stage)
        if Work.report(Work.stage, err, report) then print("Error report: " .. report.path) end
    end
    error(err, 0)
end

Work.stage = "Starting relay"
local ok, err = pcall(function()
    local storage = dofile("lib_storage.lua")
    local Network = dofile("lib_network.lua")
    local Relay = dofile("lib_relay.lua")
    local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
    local config = storage.config("configs_relay.txt", {clientId = "relay_" .. os.getComputerID(), announceInterval = 5, timeout = 15})
    assert(type(config.clientId) == "string" and #config.clientId > 0 and #config.clientId <= 64, "Invalid relay client ID")
    assert(type(config.announceInterval) == "number" and config.announceInterval >= 0.5 and config.announceInterval <= 60,
        "Invalid relay announce interval")
    assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid relay timeout")
    net = Network.new(networkConfig, false)
    client = Relay.new(net, config)
    print("Relay client v40: " .. config.clientId .. " (computer " .. net.id .. ")")
    print("Relay channel " .. net.relayChannel .. "; automatic multi-hop forwarding")
    if fs.exists(report.path) then print("Saved relay error: " .. report.path) end
end)
if not ok then finish(ok, err) end

local pending, head, tail, bytes = {}, 1, 0, 0
local timer, wakeTimer
local overflow = false
local function collect(item)
    local event = item[1]
    if event == "timer" and item[2] == wakeTimer then wakeTimer = nil; return end
    if event == "modem_message" then
        local raw = item[5]
        if (item[3] ~= net.relayChannel and item[3] ~= net.listenChannel)
            or type(raw) ~= "string" or #raw > 65536 then return end
        if tail - head + 1 >= 256 or bytes + #raw > 1048576 then
            if not overflow then print("Relay receive queue full; dropping excess packets"); overflow = true end
            return
        end
        bytes = bytes + #raw
    elseif event ~= "peripheral" and event ~= "peripheral_detach" and (event ~= "timer" or item[2] ~= timer) then return end
    tail = tail + 1
    pending[tail] = item
end

local function cooperate()
    -- Any delivered event ends the CPU slice. A native timer wakes the worker
    -- when the CraftOS queue drops the software event and traffic goes quiet.
    if not wakeTimer then wakeTimer = os.startTimer(0) end
    os.queueEvent("smarthome_relay_yield")
    collect({os.pullEvent()})
end

ok, err = Work.protect(function()
    Work.enable(cooperate, 8192, report)
    client.tick(os.clock())
    timer = os.startTimer(0.1)
    while true do
        local item
        if head <= tail then
            item = pending[head]
            pending[head], head = nil, head + 1
            if item[1] == "modem_message" then bytes = bytes - #item[5] end
        else
            pending, head, tail, overflow = {}, 1, 0, false
            Work.stage = "Waiting for relay events"
            item = {os.pullEvent()}
        end
        local event, p1, p2, p3, p4 = unpack(item)
        if event == "modem_message" then
            Work.stage = "Handling relay modem message"
            client.handleModem(p1, p2, p3, p4, os.clock())
        elseif event == "timer" and p1 == wakeTimer then wakeTimer = nil
        elseif event == "timer" and p1 == timer then
            Work.stage = "Announcing relay"
            client.tick(os.clock())
            timer = os.startTimer(0.1)
        elseif event == "peripheral" or event == "peripheral_detach" then
            Work.stage = "Relay peripheral change"
            net.peripheralChanged(p1)
        end
        if head <= tail then Work.check(128) end
    end
end)
finish(ok, err)
]=],
}
local workChunk = assert(loadstring(sources["lib_work.lua"], "lib_work.lua"))
setfenv(workChunk, getfenv(1))
workChunk()
local args = {...}
local role, autorun = args[1], false
local entry = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua", sensor = "clients_sensor_client.lua", relay = "clients_relay_client.lua"}
print("SmartHome installer: bundled-v41")
local appUsage = "Usage: inst app NAME [--ref REF] | inst app NAME PASTE_ID | inst app NAME --file PATH"
if not entry[role] and role ~= "app" then
    print("Usage: inst server|io|monitor|sensor|relay [--startup]")
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
    assert(name ~= "system", "System Overview is built into Settings")
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
        assert(args[index] == "--startup", "Usage: inst server|io|monitor|sensor|relay [--startup]")
        autorun = true
    end
    files = {"lib_work.lua", "lib_storage.lua", "lib_network.lua"}
    if role == "server" or role == "monitor" then files[#files + 1] = "lib_gui.lua" end
    if role == "server" then
        files[#files + 1] = "lib_me.lua"
        files[#files + 1] = "lib_console.lua"
        files[#files + 1] = "lib_settings.lua"
        files[#files + 1] = "lib_system.lua"
        files[#files + 1] = "lib_alert_inbox.lua"
        files[#files + 1] = "lib_io_history.lua"
        files[#files + 1] = "lib_io_picker.lua"
        files[#files + 1] = "lib_desktop.lua"
        files[#files + 1] = "lib_server.lua"
        files[#files + 1] = "lib_sensor_data.lua"
        files[#files + 1] = "lib_sensor_server.lua"
        files[#files + 1] = "lib_sensor_picker.lua"
    elseif role == "io" then files[#files + 1] = "lib_io.lua"
    elseif role == "sensor" then files[#files + 1] = "lib_sensor_data.lua"; files[#files + 1] = "lib_sensor.lua"
    elseif role == "relay" then files[#files + 1] = "lib_relay.lua"
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
    elseif role == "sensor" then migrate("configs_sensor.txt", "Configs/sensor.txt")
    elseif role == "relay" then migrate("configs_relay.txt", "Configs/relay.txt")
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
                    if enabled == true and name ~= "system" then
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
