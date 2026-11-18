-- Run from the repository root: lua5.1 tests_run.lua
-- Executes the real entry points in separate Lua 5.1 environments. The virtual
-- modem accepts strings only; computers have independent disks and event queues.
local hostLoadfile, hostPrint = loadfile, print
local roleEntries = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua",
    sensor = "clients_sensor_client.lua", relay = "clients_relay_client.lua"}
local roleNames = {"server", "io", "monitor", "sensor", "relay"}
local function equal(actual, expected, message)
    assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function serialize(value, seen)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" or kind == "nil" then return tostring(value) end
    assert(kind == "table", "Cannot serialize " .. kind)
    seen = seen or {}
    -- Legacy CraftOS keeps a single visited set for the whole serialization,
    -- rejecting repeated references as well as actual ancestor cycles.
    assert(not seen[value], "Cannot serialize table with recursive entries")
    seen[value] = true
    local parts, keys = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    -- State comparisons must not depend on LuaJ's table traversal order.
    table.sort(keys, function(a, b)
        return type(a) .. ":" .. tostring(a) < type(b) .. ":" .. tostring(b)
    end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. serialize(key, seen) .. "]=" .. serialize(value[key], seen)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function unserialize(value)
    local fn = loadstring("return " .. value)
    if not fn then return nil end
    setfenv(fn, {})
    local ok, result = pcall(fn)
    if ok then return result end
end
local function combine(a, b)
    local result, power = 0, 1
    for _ = 1, 16 do
        if a % 2 == 1 or b % 2 == 1 then result = result + power end
        a, b, power = math.floor(a / 2), math.floor(b / 2), power * 2
    end
    return result
end
local monitor
local function newBus()
    local bus = {now = 0, computers = {}, events = {}, timers = {}, wire = {}}
    function bus.queue(comp, event)
        bus.events[#bus.events + 1] = {comp = comp, event = event}
    end
    function bus.pump()
        local count = 0
        while #bus.events > 0 do
            count = count + 1
            assert(count < 10000, "Network event loop")
            local item = table.remove(bus.events, 1)
            if item.comp.active then
                local ok, err = coroutine.resume(item.comp.thread, unpack(item.event))
                assert(ok, "Computer " .. item.comp.id .. ": " .. tostring(err))
                if coroutine.status(item.comp.thread) == "dead" then item.comp.active = false end
            end
        end
    end
    function bus.advance(seconds)
        local target = math.floor((bus.now + seconds) * 1000000 + 0.5) / 1000000
        while true do
            local nextIndex, nextTime
            for i, timer in ipairs(bus.timers) do
                if timer.time <= target and (not nextTime or timer.time < nextTime) then
                    nextIndex, nextTime = i, timer.time
                end
            end
            if not nextIndex then break end
            local timer = table.remove(bus.timers, nextIndex)
            bus.now = timer.time
            if timer.comp.active then bus.queue(timer.comp, {"timer", timer.id}) end
            bus.pump()
        end
        bus.now = target
        bus.pump()
    end
    function bus.command(comp, text)
        for i = 1, #text do bus.queue(comp, {"char", text:sub(i, i)}) end
        bus.queue(comp, {"key", 28})
        bus.pump()
    end
    function bus.computer(id, role, options)
        options = options or {}
        local previous = bus.computers[id]
        if previous then previous.active = false end
        local comp = {id = id, role = role, modemSide = options.modemSide or "back", open = {}, log = {},
            disk = options.disk or {files = {}, dirs = {[""] = true}}, bundled = {}, digital = {},
            bundledInputs = {}, digitalInputs = {}, monitors = options.monitors or {}, started = bus.now,
            sensors = options.sensors or {}, sensorCalls = {}, sensorDevices = {},
            position = options.position or previous and previous.position or {0, 0, 0},
            range = options.range or previous and previous.range or 64,
            dimension = options.dimension or previous and previous.dimension or "overworld",
            appSources = options.apps or previous and previous.appSources or {}, timerId = 0, active = true,
            redstoneWrites = {}, lastRedstoneWrite = previous and previous.lastRedstoneWrite or {}}
        for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
            comp.bundled[side] = options.bundled and options.bundled[side]
                or previous and previous.bundled[side] or 0
            comp.digital[side] = options.digital and options.digital[side]
                or previous and previous.digital[side] or false
        end
        bus.computers[id] = comp
        local env = setmetatable({}, {__index = _G})
        comp.env, env._G = env, env
        env.print = function(...)
            local parts = {}
            for _, item in ipairs({...}) do parts[#parts + 1] = tostring(item) end
            comp.log[#comp.log + 1] = table.concat(parts, " ")
        end
        env.write = function() end
        comp.terminal = options.terminal or monitor(51, 19)
        env.term = comp.terminal
        env.textutils = {serialize = serialize, unserialize = unserialize}
        env.colors = {combine = combine}
        local colorNames = {"white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
            "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}
        for i, name in ipairs(colorNames) do env.colors[name] = 2 ^ (i - 1) end
        env.os = {
            queueEvent = function(name, ...) bus.queue(comp, {name, ...}) end,
            clock = function() return bus.now - comp.started end,
            getComputerID = function() return id end,
            startTimer = function(delay)
                comp.timerId = comp.timerId + 1
                bus.timers[#bus.timers + 1] = {comp = comp,
                    time = math.floor((bus.now + delay) * 1000000 + 0.5) / 1000000, id = comp.timerId}
                return comp.timerId
            end,
            pullEvent = function(filter)
                while true do
                    local event = {coroutine.yield(filter)}
                    if event[1] == "terminate" then error("Terminated") end
                    if not filter or event[1] == filter then return unpack(event) end
                end
            end,
        }
        env.read = function()
            local text = ""
            while true do
                local event, key = env.os.pullEvent()
                if event == "char" then text = text .. key
                elseif event == "key" and key == 28 then return text end
            end
        end
        env.parallel = {waitForAny = function(...)
            local threads, filters = {}, {}
            for i, fn in ipairs({...}) do
                threads[i] = coroutine.create(fn)
                local ok, filter = coroutine.resume(threads[i])
                assert(ok, filter)
                filters[i] = filter
                if coroutine.status(threads[i]) == "dead" then return i end
            end
            while true do
                local event = {coroutine.yield()}
                for i, thread in ipairs(threads) do
                    if not filters[i] or filters[i] == event[1] or event[1] == "terminate" then
                        local ok, filter = coroutine.resume(thread, unpack(event))
                        assert(ok, filter)
                        filters[i] = filter
                        if coroutine.status(thread) == "dead" then return i end
                    end
                end
            end
        end}
        local disk = comp.disk
        local function fileSize(path, length)
            if not disk.legacyFileSizes then return length end
            return math.max(512, length + #(path:match("[^/]+$") or path))
        end
        local function freeSpace()
            if not disk.capacity then return math.huge end
            local used = 0
            for path, value in pairs(disk.files) do used = used + fileSize(path, #value) end
            if disk.legacyFileSizes then for _ in pairs(disk.dirs) do used = used + 512 end end
            return math.max(0, disk.capacity - used)
        end
        local function fits(path, length)
            if not disk.capacity then return true end
            local old = disk.files[path]
            return fileSize(path, length) - (old and fileSize(path, #old) or 0) <= freeSpace()
        end
        local function childOf(file, folder)
            return file:sub(1, #folder + 1) == folder .. "/"
        end
        local function rom(path) return path == "rom" or childOf(path, "rom") end
        env.fs = {
            exists = function(path) return disk.files[path] ~= nil or disk.dirs[path] == true end,
            isDir = function(path) return disk.dirs[path] == true end,
            getFreeSpace = freeSpace,
            getSize = function(path) return disk.files[path] and fileSize(path, #disk.files[path]) or 0 end,
            isReadOnly = rom,
            getDrive = function(path) return rom(path) and "rom" or "hdd" end,
            makeDir = function(path) assert(not rom(path)); disk.dirs[path] = true end,
            delete = function(path)
                assert(not rom(path), "Read-only path")
                local files, dirs = {}, {}
                for name in pairs(disk.files) do if childOf(name, path) then files[#files + 1] = name end end
                for name in pairs(disk.dirs) do if childOf(name, path) then dirs[#dirs + 1] = name end end
                for _, name in ipairs(files) do disk.files[name] = nil end
                for _, name in ipairs(dirs) do disk.dirs[name] = nil end
                disk.files[path], disk.dirs[path] = nil, nil
            end,
            copy = function(from, to)
                assert(not rom(to) and not disk.files[to] and not disk.dirs[to], "Invalid copy")
                if disk.files[from] then
                    assert(fits(to, #disk.files[from]), "Copy failed")
                    disk.files[to] = disk.files[from]
                else
                    assert(disk.dirs[from], "Missing source")
                    local files, dirs = {}, {}
                    for name, data in pairs(disk.files) do if childOf(name, from) then files[to .. name:sub(#from + 1)] = data end end
                    for name in pairs(disk.dirs) do if childOf(name, from) then dirs[to .. name:sub(#from + 1)] = true end end
                    disk.dirs[to] = true
                    for name in pairs(dirs) do disk.dirs[name] = true end
                    for name, data in pairs(files) do
                        assert(fits(name, #data), "Copy failed")
                        disk.files[name] = data
                    end
                end
            end,
            move = function(from, to)
                if disk.failMove and from:sub(-4) == ".tmp" then error("Simulated interrupted replace") end
                assert(disk.files[from] ~= nil and disk.files[to] == nil, "Invalid move")
                if disk.copyMove and not fits(to, #disk.files[from]) then error("Copy failed.") end
                disk.files[to], disk.files[from] = disk.files[from], nil
            end,
            list = function(path)
                local list, found = {}, {}
                local prefix = path == "" and "" or path .. "/"
                local function include(name)
                    if name:sub(1, #prefix) ~= prefix then return end
                    local file = name:sub(#prefix + 1):match("^[^/]+$")
                    if file then found[file] = true end
                end
                for name in pairs(comp.appSources) do include(name) end
                for name in pairs(disk.files) do include(name) end
                for name in pairs(disk.dirs) do include(name) end
                for name in pairs(found) do list[#list + 1] = name end
                table.sort(list)
                return list
            end,
            open = function(path, mode)
                if mode == "w" then
                    if disk.failWrite or not fits(path, 0) then return nil end
                    disk.files[path] = ""
                    return {write = function(value)
                        local contents = disk.files[path] .. value
                        if not fits(path, #contents) then error("Out of space") end
                        disk.files[path] = contents
                    end, close = function() end}
                end
                if disk.files[path] == nil then return nil end
                if mode == "rb" then
                    if not disk.legacyTextReads and not disk.legacyFileSizes then
                        return {readAll = function() return disk.files[path] end, close = function() end}
                    end
                    local offset = 0
                    return {read = function() offset = offset + 1; return disk.files[path]:byte(offset) end,
                        close = function() end}
                end
                return {readAll = function()
                    local contents = disk.files[path]
                    if disk.legacyTextReads then return (contents:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n$", "")) end
                    return contents
                end, close = function() end}
            end,
        }
        local function checkSide(side)
            assert(({top = true, bottom = true, left = true, right = true, front = true, back = true})[side], "Invalid redstone side")
            assert(role ~= "server", "Central OS touched redstone")
        end
        local function redstoneWrite(side, kind, value)
            local last = comp.lastRedstoneWrite[side]
            assert(not last or bus.now - last >= 0.5 - 0.000001,
                '[IDT-Fix] Too high redstone interval! Corresponding Port -> "' .. side .. '" (Sleep at least 0.5 sec.)')
            comp.lastRedstoneWrite[side] = bus.now
            comp.redstoneWrites[#comp.redstoneWrites + 1] = {time = bus.now, side = side, kind = kind, value = value}
        end
        env.redstone = {
            getBundledInput = function(side) checkSide(side); return comp.bundledInputs[side] or 0 end,
            getInput = function(side) checkSide(side); return comp.digitalInputs[side] or false end,
            getBundledOutput = function(side) checkSide(side); return comp.bundled[side] end,
            getOutput = function(side) checkSide(side); return comp.digital[side] end,
            setBundledOutput = function(side, value)
                checkSide(side)
                assert(type(value) == "number" and value >= 0 and value <= 65535 and value == math.floor(value), "Invalid mask")
                redstoneWrite(side, "bundled", value)
                comp.bundled[side] = value
            end,
            setOutput = function(side, value)
                checkSide(side); equal(type(value), "boolean")
                redstoneWrite(side, "digital", value)
                comp.digital[side] = value
            end,
        }
        local modem = {
            open = function(channel) comp.open[channel] = true end,
            transmit = function(channel, reply, raw)
                equal(type(raw), "string", "CC 1.5 wire format")
                assert(#raw <= 65536, "Oversized packet")
                local packet = {sender = comp, channel = channel, reply = reply, raw = raw, message = unserialize(raw)}
                bus.wire[#bus.wire + 1] = packet
                if bus.dropPhysical and bus.dropPhysical(packet) then return end
                if bus.drop then
                    -- Existing loss tests drop a logical send, including both
                    -- physical copies. Per-channel loss uses dropPhysical.
                    if bus.lossFunction ~= bus.drop then bus.lossFunction, bus.logicalLoss = bus.drop, {} end
                    local t = packet.message and packet.message._transport
                    local key = t and comp.id .. ":" .. packet.message.sender .. ":" .. t.boot .. ":" .. t.sequence
                    local dropped = key and bus.logicalLoss[key]
                    if dropped == nil then
                        dropped = bus.drop(packet) == true
                        if key then bus.logicalLoss[key] = dropped end
                    end
                    if dropped then return end
                end
                for _, receiver in pairs(bus.computers) do
                    local distance = 0
                    for axis = 1, 3 do distance = distance + (receiver.position[axis] - comp.position[axis]) ^ 2 end
                    if receiver ~= comp and receiver.active and receiver.open[channel]
                        and receiver.dimension == comp.dimension and distance <= math.max(receiver.range, comp.range) ^ 2
                        and (not bus.canHear or bus.canHear(comp, receiver, packet)) then
                        bus.queue(receiver, {"modem_message", receiver.modemSide, channel, reply, raw, 12})
                    end
                end
            end,
        }
        -- Deliberately no isWireless method: early-modem compatibility.
        env.peripheral = {
            getType = function(side)
                if side == comp.modemSide then return "modem" end
                if comp.monitors[side] then return "monitor" end
                if comp.sensors[side] then return "sensor" end
            end,
            wrap = function(side)
                if side == comp.modemSide then return modem end
                local source = comp.sensors[side]
                if source then
                    local wrapper = comp.sensorDevices[side]
                    if not wrapper or wrapper.source ~= source then
                        wrapper = {source = source, device = {}}
                        comp.sensorDevices[side] = wrapper
                        for _, method in ipairs({"getSensorName", "getTargets", "getTargetDetails"}) do
                            local methodName = method
                            wrapper.device[methodName] = function(target)
                                source.counter = ((source.counter or 0) + 1) % 1001
                                local callId = source.counter
                                comp.sensorCalls[#comp.sensorCalls + 1] = {side = side, method = methodName, target = target, id = callId, time = bus.now}
                                local result = methodName == "getSensorName" and source.card or methodName == "getTargets" and source.targets or source.details and source.details[target]
                                local err = source.errors and source.errors[methodName]
                                if methodName == "getSensorName" and not source.card then err = err or "No sensor card" end
                                if source.hang == methodName then return callId end
                                if source.yielding then bus.queue(comp, {"sensor_ready"}); env.os.pullEvent("sensor_ready") end
                                if source.async == false or source.yielding then if err then error(err) end; return result end
                                bus.queue(comp, {err and "ocs_error" or "ocs_success", callId, err or result})
                                return callId
                            end
                        end
                    end
                    return wrapper.device
                end
                return comp.monitors[side]
            end,
        }
        env.loadfile = function(path)
            local chunk, err
            if comp.appSources[path] then chunk, err = loadstring(comp.appSources[path], path)
            elseif disk.files[path] then chunk, err = loadstring(disk.files[path], path)
            else chunk, err = hostLoadfile(path) end
            if chunk then
                local chunkEnv = env
                if options.strictSensorIteration and path == "lib_sensor_server.lua" then
                    -- Reproduce the reported legacy runtime: next rejects a
                    -- cursor whose entry was removed by the preceding step.
                    chunkEnv = setmetatable({pairs = function(values)
                        return function(values, key)
                            if key ~= nil and rawget(values, key) == nil then error("invalid key to 'next'", 2) end
                            return next(values, key)
                        end, values, nil
                    end}, {__index = env})
                end
                setfenv(chunk, chunkEnv)
            end
            return chunk, err
        end
        env.dofile = function(path)
            local value = assert(env.loadfile(path))()
            if path == "lib_server.lua" or path == "lib_io.lua" or path == "lib_monitor.lua" or path == "lib_console.lua" or path == "lib_sensor.lua" or path == "lib_relay.lua" then
                local constructor = value.new
                value.new = function(...)
                    local object = constructor(...)
                    if path == "lib_server.lua" then comp.server = object
                    elseif path == "lib_console.lua" then
                        comp.console = object
                        local log = object.log
                        object.log = function(...) env.print(...); return log(...) end
                    else comp.client = object end
                    return object
                end
            end
            return value
        end
        if options.network then disk.dirs.Configs = true; disk.files["configs_network.txt"] = serialize(options.network) end
        if role == "server" and options.apps then
            local settings = unserialize(disk.files["configs_os.txt"] or "") or {}
            settings.enabledApps = options.enabledApps or {}
            if options.enabledApps == nil then
                for path in pairs(options.apps) do settings.enabledApps[assert(path:match("^apps_([%w_-]+)%.lua$"))] = true end
            end
            disk.dirs.Configs = true
            disk.files["configs_os.txt"] = serialize(settings)
        end
        function comp.start()
            local path = roleEntries[role]
            comp.thread = coroutine.create(function() env.dofile(path) end)
            local ok, err = coroutine.resume(comp.thread)
            assert(ok, "Boot computer " .. id .. ": " .. tostring(err))
            bus.pump()
            return comp
        end
        function comp.savedState()
            local saved = env.dofile("lib_storage.lua").loadState("configs_os_state.txt")
            return saved
        end
        return comp
    end
    return bus
end
monitor = function(width, height)
    local screen = {width = width, height = height, lines = {}, fg = {}, bg = {}, x = 1, y = 1,
        foreground = 1, background = 32768, colour = true, writes = 0}
    function screen.setTextScale(scale) screen.scale = scale end
    function screen.isColor() return screen.colour end
    function screen.setTextColor(colour)
        assert(screen.colour or colour == 1 or colour == 32768, "Unsupported monochrome foreground")
        screen.foreground = colour
    end
    function screen.setBackgroundColor(colour)
        assert(screen.colour or colour == 1 or colour == 32768, "Unsupported monochrome background")
        screen.background = colour
    end
    function screen.getSize() return screen.width, screen.height end
    function screen.getCursorPos() return screen.x, screen.y end
    function screen.setCursorBlink(value) screen.blink = value end
    function screen.clear() screen.lines, screen.fg, screen.bg = {}, {}, {} end
    function screen.setCursorPos(x, y)
        assert(x >= 1 and y >= 1 and x == math.floor(x) and y == math.floor(y), "Invalid monitor cursor")
        screen.x, screen.y = x, y
    end
    function screen.write(text)
        if screen.beforeWrite then screen.beforeWrite() end
        assert(screen.x + #text - 1 <= screen.width, "Monitor write overflow")
        local line = screen.lines[screen.y] or string.rep(" ", screen.width)
        line = (line .. string.rep(" ", screen.width)):sub(1, screen.width)
        screen.lines[screen.y] = line:sub(1, screen.x - 1) .. text .. line:sub(screen.x + #text)
        screen.fg[screen.y], screen.bg[screen.y] = screen.fg[screen.y] or {}, screen.bg[screen.y] or {}
        for x = screen.x, screen.x + #text - 1 do screen.fg[screen.y][x], screen.bg[screen.y][x] = screen.foreground, screen.background end
        screen.x, screen.writes = screen.x + #text, screen.writes + 1
    end
    return screen
end
local function pair(options)
    local bus = newBus()
    local os = bus.computer(10, "server", options):start()
    local io = bus.computer(11, "io", {modemSide = "right"}):start()
    return bus, os, io
end
local tests = {}
function tests.client_before_server_and_zero_inputs()
    local bus = newBus()
    local io = bus.computer(11, "io", {modemSide = "right"}):start()
    equal(io.client.connected, false)
    local os = bus.computer(10, "server", {modemSide = "left"}):start()
    bus.advance(5)
    equal(io.client.connected, true)
    equal(os.server.api.getInput("io_11", "left").value, 0)
    equal(os.server.api.getInput("io_11", "left").digital, false)
    equal(os.server.ioClients.io_11.online, true)
    io.bundledInputs.left, io.digitalInputs.left = 16384, true
    bus.queue(io, {"redstone"}); bus.pump()
    equal(os.server.api.getInput("io_11", "left").value, 16384)
    io.bundledInputs.left, io.digitalInputs.left = 0, false
    bus.queue(io, {"redstone"}); bus.pump()
    equal(os.server.api.getInput("io_11", "left").value, 0)
end
function tests.bundled_off_preserves_other_colors_and_routes_to_one_client()
    local bus, os, io = pair()
    local other = bus.computer(40011, "io", {modemSide = "right"}):start() -- same reply channel
    bus.command(os, "map white_test io_11 left white")
    bus.command(os, "map red_test io_11 left red")
    bus.command(os, "set white_test on")
    bus.command(os, "set red_test on")
    bus.advance(1.3)
    equal(io.bundled.left, 16385)
    bus.command(os, "set white_test off")
    bus.advance(0.7)
    equal(io.bundled.left, 16384)
    equal(other.bundled.left, 0)
    equal(os.server.api.getOutputs()[1].confirmed, true)
    bus.command(os, "map lamp io_11 front digital")
    bus.command(os, "set lamp on")
    bus.advance(0.7)
    equal(io.digital.front, true)
    local ok = os.server.api.mapOutput("duplicate", "io_11", "front", nil)
    equal(ok, true)
    equal(os.server.api.getOutput("duplicate"), true, "A second reference adopts the existing wire state")
    assert(os.server.api.setOutput("duplicate", false)); bus.advance(0.7)
    equal(os.server.api.getOutput("lamp"), false); equal(io.digital.front, false)
end
function tests.packet_loss_retry_ack_and_stale_revision()
    local bus, os, io = pair()
    assert(os.server.api.mapOutput("test", "io_11", "left", 1)); bus.pump()
    local dropped = false
    bus.drop = function(packet)
        if not dropped and packet.message.type == "ioCommand" then dropped = true; return true end
    end
    assert(os.server.api.setOutput("test", true)); bus.pump()
    equal(io.bundled.left, 0)
    equal(os.server.api.getOutputs()[1].confirmed, false)
    bus.advance(2)
    equal(io.bundled.left, 1)
    equal(os.server.api.getOutputs()[1].confirmed, true)
    local old
    for _, packet in ipairs(bus.wire) do if packet.message.type == "ioCommand" then old = packet end end
    equal(old.message.type, "ioCommand")
    assert(os.server.api.setOutput("test", false)); bus.pump()
    bus.advance(0.7)
    equal(io.bundled.left, 0)
    io.client.disconnect()
    io.client.lastAnnounce = -math.huge
    io.client.tick(io.env.os.clock()); bus.pump()
    equal(io.client.connected, true)
    bus.queue(io, {"modem_message", "right", 1011, 45231, old.raw, 12}); bus.pump()
    equal(io.bundled.left, 0, "Old revisions must not restore old outputs")
end
function tests.reboots_restore_desired_outputs_and_reject_old_session()
    local bus, os, io = pair()
    assert(os.server.api.mapOutput("test", "io_11", "left", 1))
    assert(os.server.api.setOutput("test", true)); bus.pump()
    bus.advance(1.3)
    local stale
    for _, packet in ipairs(bus.wire) do if packet.message.type == "ioCommand" then stale = packet end end
    local oldSession = os.server.session
    os = bus.computer(10, "server", {disk = os.disk}):start()
    bus.advance(5)
    assert(os.server.session ~= oldSession)
    equal(io.client.serverSession, os.server.session)
    equal(io.bundled.left, 1)
    io = bus.computer(11, "io", {disk = io.disk, modemSide = "right"}):start()
    bus.advance(1.3)
    equal(io.bundled.left, 1)
    assert(os.server.api.setOutput("test", false)); bus.pump()
    bus.queue(io, {"modem_message", "right", 1011, 45231, stale.raw, 12}); bus.pump()
    bus.advance(0.7)
    equal(io.bundled.left, 0)
    assert(os.server.api.setOutput("test", true)); bus.pump()
    bus.advance(0.7)
    os.active = false
    bus.advance(16)
    equal(io.client.connected, false)
    equal(io.bundled.left, 0, "Disconnect safe-off")
    os = bus.computer(10, "server", {disk = os.disk}):start()
    bus.advance(5)
    equal(io.bundled.left, 1)
end
function tests.modem_relocation_and_io_remapping_clear_old_wires()
    local bus, os, io = pair()
    assert(os.server.api.mapOutput("test", "io_11", "left", 1))
    assert(os.server.api.setOutput("test", true)); bus.pump()
    bus.advance(1.3)
    io.modemSide, io.open = nil, {}
    bus.queue(io, {"peripheral_detach", "right"}); bus.pump()
    equal(io.bundled.left, 0)
    io.modemSide = "front"
    bus.queue(io, {"peripheral", "front"}); bus.pump()
    bus.advance(0.7)
    equal(io.bundled.left, 1)
    assert(os.server.api.mapOutput("test", "io_11", "bottom", 1)); bus.pump()
    bus.advance(0.7)
    equal(io.bundled.left, 0)
    equal(io.bundled.bottom, 1)
    local other = bus.computer(12, "io"):start()
    assert(os.server.api.mapOutput("test", "io_12", "left", 1)); bus.pump()
    bus.advance(1.3)
    equal(io.bundled.bottom, 0)
    equal(other.bundled.left, 1)
end
function tests.background_clock_fault_isolation_and_periodic_save_without_network()
    local bus = newBus()
    local os = bus.computer(10, "server", {apps = {
        ["apps_clock.lua"] = "return {background=function(dt,s) s.elapsed=(s.elapsed or 0)+dt; s.ticks=(s.ticks or 0)+1 end}",
        ["apps_broken.lua"] = "return {background=function() error('deliberate app failure') end}",
    }}):start()
    for _ = 1, 50 do bus.queue(os, {"unrelated_event"}) end
    bus.pump()
    equal(os.server.state.appStates.clock.ticks, nil)
    bus.advance(31)
    equal(os.server.state.appStates.clock.elapsed, 31)
    equal(os.server.state.appStates.clock.ticks, 62)
    local saved = os.savedState()
    equal(saved.appStates.clock.elapsed, 31)
end
function tests.apps_are_disabled_by_default_even_with_an_old_enabled_registry()
    local bus = newBus()
    local os = bus.computer(10, "server", {apps = {
        ["apps_switchboard.lua"] = '_G.unwantedAppExecuted=true; return {background=function() end}',
    }, enabledApps = {}})
    os.disk.files["configs_os_state.txt"] = serialize({
        appRegistry = {switchboard = true}, appStates = {switchboard = {saved = 42}},
    })
    os:start()
    bus.advance(31)
    equal(next(os.server.apps), nil)
    equal(os.env.unwantedAppExecuted, nil, "Do not even execute a disabled app's top level")
    equal(os.server.state.appStates.switchboard.saved, 42, "Keep existing user app data")
    equal(os.server.api.openApp("switchboard", "monitor_13:top"), nil)
    equal(next(os.server.api.getOutputs()), nil)
end
function tests.monitors_forward_touches_close_minimize_resize_and_restore_window_ids()
    local file = assert(io.open("tests_fixtures_switchboard.lua", "r"))
    local fixture = file:read("*a"); file:close()
    local bus, os, io = pair({apps = {["apps_switchboard.lua"] = fixture}})
    assert(os.server.api.mapOutput("test", "io_11", "left", 1)); bus.pump()
    local top, left = monitor(50, 20), monitor(30, 12)
    local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
    assert(os.server.monitors["monitor_13:top"].online)
    assert(os.server.monitors["monitor_13:left"].online)
    -- Launcher -> app; no client-supplied window IDs.
    bus.queue(display, {"monitor_touch", "top", 2, top.height}); bus.pump()
    local launch
    for _, hit in ipairs(os.server.monitors["monitor_13:top"].menuHits) do
        if hit.item and hit.item.value == "switchboard" then launch = hit end
    end
    assert(launch)
    bus.queue(display, {"monitor_touch", "top", launch.x1, launch.y}); bus.pump()
    local win = os.server.state.windows[1]
    assert(win)
    bus.queue(display, {"monitor_touch", "top", win.x + 1, win.y + 2}); bus.pump()
    bus.advance(0.7)
    equal(io.bundled.left, 1)
    bus.queue(display, {"monitor_touch", "top", 6, top.height}); bus.pump()
    equal(win.minimized, true)
    bus.queue(display, {"monitor_touch", "top", 6, top.height}); bus.pump()
    equal(win.minimized, false)
    assert(os.server.api.placeWindow(1, 1, 3, 20, 6))
    local id = assert(os.server.api.openApp("switchboard", "monitor_13:top", nil, nil, 20, 6))
    equal(id, 2)
    local second = os.server.state.windows[id]
    assert(second.x >= 21, "Free space should be used for side-by-side windows")
    os.server.refreshMonitors(true); bus.pump()
    equal(top.lines[second.y]:sub(second.x + second.width - 3, second.x + second.width - 1), " X ")
    bus.queue(display, {"monitor_touch", "top", second.x + second.width - 2, second.y}); bus.pump()
    equal(os.server.state.windows[2], nil)
    top.width, top.height = 8, 4
    bus.queue(display, {"monitor_resize", "top"}); bus.pump()
    equal(win.doesNotFit, true)
    top.width, top.height = 50, 20
    bus.queue(display, {"monitor_resize", "top"}); bus.pump()
    equal(win.doesNotFit, false)
    assert(os.server.api.save())
    os = bus.computer(10, "server", {disk = os.disk}):start()
    bus.advance(6) -- A resize at a fractional time moves the monitor's next announcement.
    equal(os.server.state.windows[1].appName, "switchboard")
    local newId = assert(os.server.api.openApp("switchboard", "monitor_13:top"))
    assert(newId > 1, "Restored windows must not be overwritten")
end
function tests.malformed_packets_wrong_network_and_pinned_server_are_ignored()
    local bus, os, io = pair()
    local before = io.bundled.left
    for _, raw in ipairs({"hello", "{", "42", "nil", "{type='announce'}", true, {type = "announce"}}) do
        bus.queue(os, {"modem_message", "back", 45231, 1011, raw, 12})
        bus.queue(io, {"modem_message", "right", 1011, 45231, raw, 12})
    end
    bus.pump()
    equal(io.bundled.left, before)
    local stranger = bus.computer(14, "io", {network = {networkId = "other", channel = 45231}}):start()
    bus.advance(5)
    equal(stranger.client.connected, false)
    equal(os.server.ioClients.io_14, nil)
    local pinned = bus.computer(15, "io", {network = {networkId = "home", channel = 45231, serverId = 999}}):start()
    bus.advance(5)
    equal(pinned.client.connected, false)
    equal(os.server.ioClients.io_15, nil)
    equal(type(os.server.state.windows), "table")
end
function tests.failed_save_does_not_command_hardware_and_interrupted_save_recovers()
    local bus, os, io = pair()
    assert(os.server.api.mapOutput("test", "io_11", "left", 1)); bus.pump()
    os.disk.failWrite = true
    local ok = os.server.api.setOutput("test", true)
    equal(ok, false)
    equal(os.server.api.getOutput("test"), false)
    bus.pump()
    equal(io.bundled.left, 0)
    os.disk.failWrite = false
    assert(os.server.api.setOutput("test", true)); bus.pump()
    bus.advance(1.3)
    local open = os.env.fs.open
    os.env.fs.open = function(path, mode)
        local file = open(path, mode)
        if path == "configs_os_state.txt" and mode == "w" then
            file.write = function() error("Interrupted state write") end
        end
        return file
    end
    os.server.state.appearance.backgroundColour = 16
    equal(os.server.save(), false)
    assert(os.disk.files["configs_os_state.txt.bak"])
    equal(os.disk.files["configs_os_state.txt.tmp"], nil)
    os = bus.computer(10, "server", {disk = os.disk}):start()
    bus.advance(5)
    equal(io.bundled.left, 1)
    -- Malformed primary falls back to the previous complete checkpoint.
    os.disk.files["configs_os_state.txt"] = "corrupted"
    os = bus.computer(10, "server", {disk = os.disk}):start()
    bus.advance(5)
    equal(os.server.api.getOutput("test"), true)
end
function tests.lost_handshake_acknowledgement_and_render_recover()
    local bus = newBus()
    local os = bus.computer(10, "server"):start()
    assert(os.server.api.mapOutput("test", "io_11", "left", 1))
    assert(os.server.api.setOutput("test", true))
    local droppedWelcome, droppedAck, droppedRender = false, false, false
    bus.drop = function(packet)
        local kind = packet.message.type
        if kind == "welcome" and not droppedWelcome then droppedWelcome = true; return true end
        if kind == "ioAck" and not droppedAck then droppedAck = true; return true end
        if kind == "render" and not droppedRender then droppedRender = true; return true end
    end
    local io = bus.computer(11, "io"):start()
    equal(io.client.connected, false)
    bus.advance(5)
    equal(io.client.connected, true)
    equal(io.bundled.left, 1)
    equal(os.server.api.getOutputs()[1].confirmed, false)
    bus.advance(2)
    equal(os.server.api.getOutputs()[1].confirmed, true)
    local screen = monitor(40, 12)
    bus.computer(13, "monitor", {monitors = {top = screen}}):start()
    assert(screen.lines[1]:find("Connecting", 1, true))
    bus.advance(5)
    equal(screen.lines[1], string.rep(" ", screen.width))
    equal(screen.bg[1][1], 2048)
    assert(droppedWelcome and droppedAck and droppedRender)
end
function tests.sensor_data_cannot_overwrite_os_structures_and_times_out()
    local bus, os = pair()
    local sensor = bus.computer(22, "sensor")
    sensor.thread = coroutine.create(function() while true do coroutine.yield() end end)
    assert(coroutine.resume(sensor.thread))
    local net = sensor.env.dofile("lib_network.lua").new({networkId = "home", channel = 45231}, false)
    assert(net.ensureModem())
    net.toServer({type = "announce", clientType = "sensor", clientId = "sensor_22", nonce = 1}); bus.pump()
    for name, value in pairs({windows = "corrupt", playerOnline = true, gameTime = "12:34"}) do
        net.toServer({type = "sensorData", clientId = "sensor_22", varName = name, value = value,
            serverSession = os.server.session})
    end
    bus.pump()
    equal(type(os.server.state.windows), "table")
    equal(os.server.api.getSensor("sensor_22", "windows"), "corrupt")
    equal(os.server.api.getSystem().playerOnline, true)
    equal(os.server.api.getSystem().gameTime, "12:34")
    bus.advance(16)
    equal(os.server.api.getSensor("sensor_22", "windows"), nil)
    equal(os.server.api.getSystem().playerOnline, false)
end
function tests.invalid_snapshot_is_rejected_atomically_and_bad_app_metadata_isolated()
    local bus, os, io = pair({apps = {["apps_invalid.lua"] = 'return {minWidth="invalid", render=function() return {} end}'}})
    equal(os.server.apps.invalid, nil)
    local raw = serialize({protocol = "SmartHomeOS/1", networkId = "home", sender = 10, recipient = 11,
        type = "ioCommand", clientId = "io_11", serverSession = os.server.session,
        command = "syncOutputs", revision = 1234,
        outputs = {left = {bundled = 1, digital = true}, top = {bundled = -1, digital = false}}})
    bus.queue(io, {"modem_message", "right", 1011, 45231, raw, 12}); bus.pump()
    equal(io.bundled.left, 0)
    equal(io.digital.left, false)
    -- A syntactically valid but structurally invalid primary also uses the backup.
    assert(os.server.api.mapOutput("test", "io_11", "left", 1))
    assert(os.server.save())
    os.disk.files["configs_os_state.txt"] = '{outputMap={test=42}}'
    os = bus.computer(10, "server", {disk = os.disk}):start()
    equal(os.server.state.outputMap.test.clientId, "io_11")
end
function tests.idt_fix_boot_clears_both_output_types_without_redundant_writes()
    local bus = newBus()
    local io = bus.computer(11, "io", {modemSide = "top", bundled = {bottom = 7}, digital = {bottom = true}})
    io.lastRedstoneWrite.bottom = bus.now -- Cooldown can outlive a terminated program.
    io:start()
    local os = bus.computer(10, "server"):start()
    equal(#io.redstoneWrites, 0)
    equal(io.client.connected, false, "Finish startup clear before discovery")
    bus.advance(0.5)
    equal(io.bundled.bottom, 7)
    bus.advance(0.1)
    equal(io.bundled.bottom, 0)
    equal(io.digital.bottom, true)
    equal(io.client.connected, false)
    bus.advance(0.6)
    equal(io.digital.bottom, false)
    equal(io.client.connected, true)
    equal(os.server.ioClients.io_11.online, true)
    equal(#io.redstoneWrites, 2, "Do not reset outputs that are already off")
    bus.advance(10)
    equal(#io.redstoneWrites, 2, "Heartbeats must not rewrite unchanged ports")
end
function tests.idt_fix_coalesces_rapid_commands_and_confirms_only_after_application()
    local bus, os, io = pair()
    bus.command(os, "map test io_11 left white")
    bus.command(os, "map lamp io_11 left digital")
    bus.command(os, "set test on")
    bus.command(os, "set lamp on")
    equal(#io.redstoneWrites, 0)
    equal(os.server.api.getOutputs()[1].confirmed, false)
    bus.advance(0.6)
    equal(io.bundled.left, 1)
    equal(io.digital.left, false)
    equal(os.server.api.getOutputs()[1].confirmed, false, "One of two writes is still pending")
    io.bundledInputs.front, io.digitalInputs.front = 8, true
    bus.queue(io, {"redstone"}); bus.pump()
    equal(os.server.api.getInput("io_11", "front").value, 8, "Inputs continue during cooldown")
    bus.command(os, "set test off")
    bus.command(os, "set test on")
    bus.advance(0.6)
    equal(io.bundled.left, 1)
    equal(io.digital.left, true)
    equal(#io.redstoneWrites, 2, "Only the latest desired state should reach hardware")
    equal(os.server.api.getOutputs()[1].confirmed, true)
    os.server.syncIO("io_11", false)
    os.server.syncIO("io_11", false)
    bus.pump()
    equal(#io.redstoneWrites, 2, "Duplicate snapshots are acknowledged without writing")
    bus.command(os, "set test off")
    bus.command(os, "set lamp off")
    bus.advance(0.6)
    equal(io.bundled.left, 0)
    equal(io.digital.left, true)
    equal(os.server.api.getOutputs()[1].confirmed, false)
    bus.advance(0.6)
    equal(io.digital.left, false)
    equal(os.server.api.getOutputs()[1].confirmed, true)
end
function tests.idt_fix_disconnection_cancels_pending_on_and_flushes_safe_off_without_modem()
    local bus, os, io = pair()
    bus.advance(1.3)
    bus.command(os, "map test io_11 left white")
    bus.command(os, "map lamp io_11 left digital")
    bus.command(os, "set test on")
    bus.command(os, "set lamp on")
    equal(io.bundled.left, 1)
    equal(io.digital.left, false)
    io.modemSide, io.open = nil, {}
    bus.queue(io, {"peripheral_detach", "right"}); bus.pump()
    equal(io.client.connected, false)
    bus.advance(1.3)
    equal(io.bundled.left, 0)
    equal(io.digital.left, false)
    for _, call in ipairs(io.redstoneWrites) do
        assert(call.kind ~= "digital" or call.value == false, "A cancelled ON must not be applied after disconnect")
    end
    io.modemSide = "front"
    bus.queue(io, {"peripheral", "front"}); bus.pump()
    bus.advance(1.3)
    equal(io.client.connected, true)
    equal(io.bundled.left, 1)
    equal(io.digital.left, true)
    equal(os.server.api.getOutputs()[1].confirmed, true)
end
function tests.idt_fix_new_server_session_discards_an_old_pending_command()
    local bus, os, io = pair()
    bus.command(os, "map test io_11 left white")
    bus.command(os, "set test on")
    equal(io.bundled.left, 0)
    os.server.state.outputs.test = false
    assert(os.server.save())
    local oldSession = os.server.session
    os = bus.computer(10, "server", {disk = os.disk}):start()
    io.client.lastAnnounce = -math.huge
    io.client.tick(io.env.os.clock()); bus.pump()
    assert(io.client.serverSession ~= oldSession)
    bus.advance(1.3)
    equal(io.bundled.left, 0)
    equal(#io.redstoneWrites, 0, "Do not apply a queued command from the previous OS session")
    equal(os.server.api.getOutputs()[1].confirmed, true)
end
function tests.installer_installs_every_role_from_downloaded_files_and_keeps_configs()
    for _, role in ipairs(roleNames) do
        local bus = newBus()
        local comp = bus.computer(10, role)
        local existing = '{networkId="saved-home",channel=45231}'
        comp.disk.dirs.Configs = true
        comp.disk.files["configs_network.txt"] = existing
        comp.disk.files.startup = "-- previous startup"
        comp.env.shell = {dir = function() return "" end}
        comp.env.http = {get = function(url)
            local path = assert(url:match("/main/(.+)$"))
            local file = assert(io.open(path, "r"))
            local contents = file:read("*a"); file:close()
            return {readAll = function() return contents end, close = function() end}
        end}
        local entry = roleEntries[role]
        comp.disk.files[entry] = "-- previous program"
        assert(comp.env.loadfile("tools_install_github.lua"))(role, "main")
        for path in pairs(comp.disk.files) do assert(not path:match("^apps_"), "Installer downloaded an app") end
        equal(comp.disk.files["configs_network.txt"], existing)
        equal(comp.disk.files.startup, "-- previous startup")
        equal(comp.disk.files[entry .. ".pre_update"], nil)
        equal(comp.disk.files["install.lua"], nil, "The small installer runs the bundle in memory")
        -- Boot only what was downloaded, so missing role dependencies cannot hide.
        comp.env.loadfile = function(path)
            local contents = comp.disk.files[path]
            if not contents then return nil, "Missing installed file: " .. path end
            local fn, err = loadstring(contents, path)
            if fn then setfenv(fn, comp.env) end
            return fn, err
        end
        comp:start()
        assert(role == "server" and comp.server or comp.client)
    end
end
function tests.installer_download_failure_does_not_replace_existing_programs()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.disk.files["main_os.lua"] = "-- keep existing"
    comp.disk.files.startup = "-- keep previous startup"
    comp.env.shell = {dir = function() return "" end}
    local requests = 0
    comp.env.http = {get = function()
        requests = requests + 1
        return nil
    end}
    local ok = pcall(assert(comp.env.loadfile("tools_install_github.lua")), "server", "--startup")
    equal(ok, false)
    equal(comp.disk.files["main_os.lua"], "-- keep existing")
    equal(comp.disk.files["lib_network.lua"], nil)
    equal(comp.disk.files["lib_storage.lua.download"], nil)
    equal(comp.disk.files.startup, "-- keep previous startup")
end
function tests.installer_uses_only_the_v2_root_bundle_for_every_role()
    for _, role in ipairs(roleNames) do
        local bus = newBus()
        local comp = bus.computer(10, role)
        equal(comp.env.fs.getDir, nil, "Legacy CC must not expose fs.getDir")
        comp.env.shell = {dir = function() return "" end}
        local requests = 0
        comp.env.http = {get = function(url)
            equal(url, "https://raw.githubusercontent.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/main/install.lua")
            requests = requests + 1
            local file = assert(io.open("install.lua", "r"))
            local contents = file:read("*a"); file:close()
            return {readAll = function() return contents end, close = function() end}
        end}
        assert(comp.env.loadfile("tools_install_github.lua"))(role, "main")
        equal(requests, 1)
        for path in pairs(comp.disk.files) do assert(not path:find("/", 1, true), "Installer created a nested path") end
        comp.env.loadfile = function(path)
            local contents = comp.disk.files[path]
            if not contents then return nil, "Missing installed file: " .. path end
            local fn, err = loadstring(contents, path)
            if fn then setfenv(fn, comp.env) end
            return fn, err
        end
        comp:start()
        assert(role == "server" and comp.server or comp.client)
    end
end
function tests.installer_startup_flag_selects_role_without_leaving_program_copies()
    for _, role in ipairs(roleNames) do
        local bus = newBus()
        local comp = bus.computer(10, role)
        comp.disk.files.startup = "-- original startup"
        local selectedDir, selectedProgram
        comp.env.shell = {dir = function() return "" end,
            setDir = function(path) selectedDir = path end,
            run = function(path) selectedProgram = path end}
        comp.env.http = {get = function(url)
            local path = assert(url:match("/main/(.+)$"))
            local file = assert(io.open(path, "r"))
            local contents = file:read("*a"); file:close()
            return {readAll = function() return contents end, close = function() end}
        end}
        assert(comp.env.loadfile("tools_install_github.lua"))(role, "--startup")
        equal(comp.disk.files["startup.pre_update"], nil)
        local chunk = assert(loadstring(comp.disk.files.startup))
        setfenv(chunk, comp.env); chunk()
        equal(selectedDir, "/")
        equal(selectedProgram, roleEntries[role])
    end
end
function tests.bundled_installer_boots_all_roles_without_http_or_newer_fs_api()
    for _, role in ipairs(roleNames) do
        local bus = newBus()
        local comp = bus.computer(10, role)
        comp.env.http = nil
        equal(comp.env.fs.getDir, nil)
        comp.env.shell = {dir = function() return "" end}
        comp.disk.legacyTextReads, comp.disk.legacyFileSizes = true, true
        comp.disk.dirs.Configs = true
        comp.disk.files["configs_network.txt"] = '{networkId="saved-home",channel=45231}'
        comp.disk.files.startup = "-- old startup"
        local expectedProgram = roleEntries[role]
        comp.disk.files[expectedProgram] = "-- old program"
        assert(comp.env.loadfile("install.lua"))(role, "--startup")
        for path in pairs(comp.disk.files) do assert(not path:match("^apps_"), "Installer bundled an app") end
        equal(comp.disk.files[expectedProgram .. ".pre_update"], nil)
        equal(comp.disk.files["startup.pre_update"], nil)
        equal(comp.disk.files["configs_network.txt"], '{networkId="saved-home",channel=45231}')
        assert(comp.disk.files.startup:find(expectedProgram, 1, true))
        -- Use only the extracted files to boot, not the host repository sources.
        comp.env.loadfile = function(path)
            local contents = comp.disk.files[path]
            if not contents then return nil, "Missing extracted file: " .. path end
            local fn, err = loadstring(contents, path)
            if fn then setfenv(fn, comp.env) end
            return fn, err
        end
        comp:start()
        assert(role == "server" and comp.server or comp.client)
        if role == "server" then equal(next(comp.server.apps), nil) end
        assert(table.concat(comp.log, "\n"):find("SmartHome installer: bundled-v58", 1, true))
    end
end

function tests.v55_installer_verifies_program_bytes_when_legacy_text_reads_drop_newlines()
    local comp = newBus().computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    comp.disk.legacyTextReads = true
    local install = assert(comp.env.loadfile("install.lua"))
    install("server", "--startup")
    local path = "lib_codec.lua"
    local source = assert(io.open(path, "rb"))
    local expected = source:read("*a"); source:close()
    equal(comp.disk.files[path], expected)
    local handle = assert(comp.env.fs.open(path, "r"))
    local legacyText = handle.readAll(); handle.close()
    equal(legacyText, expected:sub(1, -2), "The legacy handle omits the final newline")
    local storage = comp.env.dofile("lib_storage.lua")
    equal(storage.readBytes(path), expected)
    local lines = "one\r\n\r\nthree\n"
    storage.writeVerified("example.txt", lines)
    equal(storage.readBytes("example.txt"), lines)

    comp.disk.failWrite = true
    install("server", "--startup") -- Byte-identical programs must be skipped.
    comp.disk.failWrite = false
    local open = comp.env.fs.open
    for _, damaged in ipairs({"Line\n", "lin\n", "line\r"}) do
        comp.env.fs.open = function(name, mode)
            local file = open(name, mode)
            if name == "damaged.txt" and mode == "w" then
                local write = file.write
                file.write = function() write(damaged) end
            end
            return file
        end
        local ok, err = pcall(storage.writeVerified, "damaged.txt", "line\n")
        assert(not ok and tostring(err):find("readback mismatch", 1, true), tostring(err))
        equal(comp.disk.files["damaged.txt"], nil)
    end
end
function tests.bundled_installer_does_not_contact_github_and_keeps_startup_without_flag()
    local bus = newBus()
    local comp = bus.computer(11, "io")
    comp.env.shell = {dir = function() return "" end}
    comp.env.http = {get = function() error("Installer must not attempt any HTTP download") end}
    comp.disk.files.startup = "-- user startup"
    assert(comp.env.loadfile("install.lua"))("io")
    equal(comp.disk.files.startup, "-- user startup")
    assert(comp.disk.files["lib_io.lua"])
end
function tests.bundled_installer_failed_staging_preserves_existing_program_and_startup()
    local bus = newBus()
    local comp = bus.computer(11, "io")
    comp.env.shell = {dir = function() return "" end}
    comp.disk.files.startup = "-- original startup"
    comp.disk.files["clients_io_client.lua"] = "-- original program"
    comp.disk.failWrite = true
    local ok = pcall(assert(comp.env.loadfile("install.lua")), "io", "--startup")
    equal(ok, false)
    equal(comp.disk.files.startup, "-- original startup")
    equal(comp.disk.files["clients_io_client.lua"], "-- original program")
end
function tests.app_installer_fetches_only_the_requested_app_and_defers_execution_until_boot()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server", "--startup")
    local startup = comp.disk.files.startup
    local previousSettings = serialize({saveInterval = 90, customSetting = "keep", enabledApps = {existing = true}})
    comp.disk.dirs.Configs, comp.disk.dirs.Apps = true, true
    comp.disk.files["configs_os.txt"] = previousSettings
    comp.disk.files["configs_os_state.txt"] = serialize({appStates = {test_app = {elapsed = 100}}})
    comp.disk.files["apps_test_app.lua"] = "-- previous user app"
    local app = '_G.userAppExecuted=true; return {background=function(dt,s) s.elapsed=(s.elapsed or 0)+dt end}'
    local downloads = 0
    comp.env.shell.run = function(program, command, pasteId, target)
        equal(program, "pastebin"); equal(command, "get"); equal(pasteId, "UserPaste")
        downloads = downloads + 1
        comp.disk.files[target] = app
        return true
    end
    comp.env.http = {get = function() error("Use the working built-in Pastebin program") end}
    install("app", "test_app", "UserPaste")
    equal(downloads, 1)
    equal(comp.disk.files["apps_test_app.lua"], app)
    equal(comp.disk.files["apps_test_app.lua.pre_update"], nil)
    equal(comp.disk.files["configs_os.txt.pre_update"], nil)
    equal(comp.disk.files.startup, startup)
    equal(comp.env.userAppExecuted, nil, "Installing must not execute app code")
    local settings = unserialize(comp.disk.files["configs_os.txt"])
    equal(settings.enabledApps.test_app, true)
    equal(settings.enabledApps.existing, true)
    equal(settings.saveInterval, 90)
    equal(settings.customSetting, "keep")
    local installedSettings = comp.disk.files["configs_os.txt"]
    install("server")
    equal(comp.disk.files["configs_os.txt"], installedSettings, "OS updates preserve explicit app choices")
    equal(downloads, 1, "OS installation never downloads apps")
    comp:start()
    equal(comp.env.userAppExecuted, true)
    equal(next(comp.server.state.windows), nil)
    bus.advance(2.5)
    equal(comp.server.state.appStates.test_app.elapsed, 102.5, "An explicitly enabled service runs without windows")
end
local function githubFile(name, contents)
    local alphabet, encoded = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", {}
    for index = 1, #contents, 3 do
        local a, b, c = contents:byte(index, index + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)
        for shift = 18, 0, -6 do
            local digit = math.floor(value / 2 ^ shift) % 64
            encoded[#encoded + 1] = alphabet:sub(digit + 1, digit + 1)
        end
        if not b then encoded[#encoded - 1] = "=" end
        if not c then encoded[#encoded] = "=" end
    end
    return '{"type":"file","name":"' .. name .. '","encoding":"base64","size":' .. #contents
        .. ',"content":"' .. table.concat(encoded) .. '\\n"}'
end
function tests.v49_bulk_app_install_downloads_every_catalog_entry_and_rolls_back_a_failed_swap()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server")
    local config = serialize({tickInterval=2,enabledApps={custom=true}})
    comp.disk.files["configs_os.txt"] = config
    comp.disk.files["apps_coffee.lua"] = "-- previous Coffee"
    local requests, failedDownload = {}, true
    comp.env.http = {get=function(url)
        local path = url:match("(apps_[%w_-]+%.lua)")
        assert(path and url:find("main",1,true),url)
        requests[path]=(requests[path] or 0)+1
        if path=="apps_window_presets.lua" and failedDownload then return nil,"Test connection failure" end
        local contents = "return {title=" .. string.format("%q",path) .. "}"
        return {readAll=function() return githubFile(path,contents) end,close=function() end}
    end}
    assert(not pcall(install,"apps"))
    equal(comp.disk.files["configs_os.txt"],config)
    equal(comp.disk.files["apps_coffee.lua"],"-- previous Coffee")
    equal(comp.disk.files["apps_clock.lua"],nil)
    failedDownload=false
    local open, failed=comp.env.fs.open, false
    comp.env.fs.open=function(path,mode)
        local file = open(path,mode)
        if path=="apps_coffee.lua" and mode=="w" and not failed then
            file.write=function() failed=true; error("Test swap failure") end
        end
        return file
    end
    assert(not pcall(install,"apps"))
    equal(comp.disk.files["apps_coffee.lua"],"-- previous Coffee")
    equal(comp.disk.files["apps_clock.lua"],nil)
    equal(comp.disk.files["configs_os.txt"],config)
    comp.env.fs.open=open
    requests={}
    install("apps")
    local settings=assert(unserialize(comp.disk.files["configs_os.txt"]))
    equal(settings.tickInterval,2); equal(settings.enabledApps.custom,true)
    local count=0
    for path,downloads in pairs(requests) do
        equal(downloads,1); assert(comp.disk.files[path])
        assert(settings.enabledApps[path:match("^apps_([%w_-]+)%.lua$")])
        count=count+1
    end
    equal(count,13)
    equal(comp.disk.files["apps_coffee.lua.pre_update"],nil)
end
function tests.app_installer_downloads_actual_switchboard_and_boots_it_with_only_extracted_core_files()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server", "--startup")
    equal(comp.disk.files["apps_switchboard.lua"], nil, "No apps in the core bundle")
    local file = assert(io.open("apps_switchboard.lua", "r"))
    local source = file:read("*a"); file:close()
    local requests = 0
    comp.env.http = {get = function(url)
        equal(url, "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_switchboard.lua?ref=main")
        requests = requests + 1
        return {readAll = function() return githubFile("apps_switchboard.lua", source) end, close = function() end}
    end}
    install("app", "switchboard")
    equal(requests, 1); equal(comp.disk.files["apps_switchboard.lua"], source)
    equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.switchboard, true)
    comp.env.loadfile = function(path)
        local fn, err = loadstring(assert(comp.disk.files[path], "File not extracted: " .. path), path)
        if fn then setfenv(fn, comp.env) end
        return fn, err
    end
    comp:start()
    equal(comp.server.running.switchboard, nil, "Switchboard waits until opened")
    bus.computer(13, "monitor", {monitors = {top = monitor(40, 20)}}):start()
    assert(comp.server.api.openApp("switchboard", "monitor_13:top"))
    equal(comp.server.running.switchboard, true)
    equal(comp.server.state.appStates.switchboard.version, 1)
end
function tests.app_installer_github_default_downloads_one_app_without_running_or_resetting_it()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end,
        run = function() error("GitHub apps must not need another Pastebin paste") end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server", "--startup")
    local startup = comp.disk.files.startup
    local settings = serialize({customSetting = "keep", enabledApps = {existing = true}})
    local saved = serialize({appStates = {test_app = {elapsed = 123}}})
    comp.disk.files["configs_os.txt"], comp.disk.files["configs_os_state.txt"] = settings, saved
    comp.disk.files["apps_test_app.lua"] = "-- original app"
    local app = '_G.githubAppExecuted=true; return {background=function(dt,s) s.elapsed=(s.elapsed or 0)+dt end}'
    local downloads, closed = 0, false
    comp.env.http = {get = function(url)
        equal(url, "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_test_app.lua?ref=main")
        downloads = downloads + 1
        coroutine.yield("http_success") -- CC 1.5 cannot yield through pcall.
        return {readAll = function() return githubFile("apps_test_app.lua", app) end, close = function() closed = true end}
    end}
    local thread = coroutine.create(function() install("app", "test_app") end)
    local ok, event = coroutine.resume(thread)
    assert(ok, event); equal(event, "http_success")
    equal(comp.disk.files["apps_test_app.lua"], "-- original app", "Keep the installed app while downloading")
    equal(comp.disk.files["configs_os.txt"], settings)
    ok, event = coroutine.resume(thread, "http_success")
    assert(ok, event); equal(coroutine.status(thread), "dead")
    equal(downloads, 1); equal(closed, true)
    equal(comp.env.githubAppExecuted, nil, "Installing only compiles app code")
    equal(comp.disk.files["apps_test_app.lua"], app)
    equal(comp.disk.files["apps_test_app.lua.pre_update"], nil)
    equal(comp.disk.files["configs_os.txt.pre_update"], nil)
    equal(comp.disk.files["configs_os_state.txt"], saved, "Downloading an update preserves app progress")
    equal(comp.disk.files.startup, startup)
    local enabled = unserialize(comp.disk.files["configs_os.txt"])
    equal(enabled.enabledApps.test_app, true); equal(enabled.enabledApps.existing, true)
    equal(enabled.customSetting, "keep")
    install("server")
    equal(downloads, 1, "Core OS installation never fetches apps")
    comp:start()
    equal(comp.env.githubAppExecuted, true)
    bus.advance(2)
    equal(comp.server.state.appStates.test_app.elapsed, 125)
end

function tests.app_installer_github_can_select_a_branch_or_commit()
    for _, ref in ipairs({"testing/ui", string.rep("a", 40)}) do
        local comp = newBus().computer(10, "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        install("server")
        local closed = false
        comp.env.http = {get = function(url)
            equal(url, "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_coffee.lua?ref=" .. ref)
            return {getResponseCode = function() return 200 end,
                readAll = function() return githubFile("apps_coffee.lua", "return {}") end, close = function() closed = true end}
        end}
        install("app", "coffee", "--ref", ref)
        equal(closed, true)
        equal(comp.disk.files["apps_coffee.lua"], "return {}")
        equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.coffee, true)
    end
end

function tests.app_installer_github_failures_preserve_existing_code_settings_and_progress()
    local expected = {disabled = "HTTP is disabled", missing_get = "HTTP is disabled",
        network = "GitHub app download failed", status = "GitHub returned HTTP 404",
        empty = "Empty app source", html = "Invalid app Lua", syntax = "Invalid app Lua",
        ref = "Invalid GitHub branch or commit"}
    for _, reason in ipairs({"disabled", "missing_get", "network", "status", "empty", "html", "syntax", "ref"}) do
        local comp = newBus().computer(10, "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        install("server")
        local settings = serialize({custom = 12, enabledApps = {other = true}})
        local saved = serialize({appStates = {coffee = {remainingTime = 1234}}})
        comp.disk.files["configs_os.txt"], comp.disk.files["configs_os_state.txt"] = settings, saved
        comp.disk.files["apps_coffee.lua"], comp.disk.files.startup = "-- original coffee", "-- original startup"
        local downloaded, closed = false, false
        comp.env.http = {get = function()
            downloaded = true
            if reason == "network" then return nil, "Connection refused" end
            return {getResponseCode = function() return reason == "status" and 404 or 200 end,
                readAll = function()
                    return reason == "empty" and "" or reason == "html" and "<!DOCTYPE html>"
                        or reason == "syntax" and "return {" or "return {}"
                end, close = function() closed = true end}
        end}
        if reason == "disabled" then comp.env.http = false
        elseif reason == "missing_get" then comp.env.http = {} end
        local ok, err
        if reason == "ref" then ok, err = pcall(install, "app", "coffee", "--ref", "../other")
        else ok, err = pcall(install, "app", "coffee") end
        equal(ok, false, reason .. " should fail")
        local report = table.concat(comp.log, "\n") .. "\n" .. tostring(err)
        assert(report:find(expected[reason], 1, true), report)
        if downloaded and reason ~= "network" then equal(closed, true) end
        equal(comp.disk.files["apps_coffee.lua"], "-- original coffee", reason)
        equal(comp.disk.files["configs_os.txt"], settings, reason)
        equal(comp.disk.files["configs_os_state.txt"], saved, reason)
        equal(comp.disk.files.startup, "-- original startup", reason)
        equal(comp.disk.files["apps_coffee.lua.pre_update"], nil, reason)
    end
end

function tests.app_installer_github_raw_fallback_handles_api_failure_native_errors_and_yields()
    for _, failure in ipairs({"nil", "native_error", "html", "error_handle"}) do
        local comp = newBus().computer(10, "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        install("server")
        local saved = serialize({appStates = {coffee = {remainingTime = 1234}}})
        comp.disk.files["configs_os_state.txt"] = saved
        local requests, closes = {}, 0
        local function response(code, body)
            return {getResponseCode = function() return code end, readAll = function() return body end,
                close = function() closes = closes + 1 end}
        end
        comp.env.http = {get = function(url)
            requests[#requests + 1] = url
            if #requests == 1 then
                equal(url, "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_coffee.lua?ref=main")
                coroutine.yield("http_failure")
                if failure == "nil" then return nil end -- Original screenshot: no error reason.
                if failure == "native_error" then error("Access denied") end
                if failure == "html" then return response(200, "<!DOCTYPE html>") end
                return nil, "Forbidden", response(403, "{}")
            end
            equal(url, "https://raw.githubusercontent.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/main/apps_coffee.lua")
            coroutine.yield("http_success")
            return response(200, "return {}\n")
        end}
        local work = coroutine.create(function() install("app", "coffee") end)
        local ok, event = coroutine.resume(work)
        while ok and coroutine.status(work) ~= "dead" do
            assert(event == "http_failure" or event == "http_success", tostring(event))
            ok, event = coroutine.resume(work, event)
        end
        assert(ok, event)
        equal(#requests, 2)
        equal(closes, (failure == "html" or failure == "error_handle") and 2 or 1)
        equal(comp.disk.files["apps_coffee.lua"], "return {}\n")
        equal(comp.disk.files["configs_os_state.txt"], saved)
        equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.coffee, true)
        assert(table.concat(comp.log, "\n"):find("Downloaded via GitHub raw", 1, true))
    end
end

function tests.app_installer_github_api_rejects_invalid_payloads_before_replacing_files()
    local function json(name, size, data)
        return '{"type":"file","name":"' .. name .. '","encoding":"base64","size":' .. size
            .. ',"content":"' .. data .. '"}'
    end
    local cases = {
        {body = json("apps_other.lua", 9, "cmV0dXJuIHt9"), reason = "requested base64 file"},
        {body = json("apps_coffee.lua", 9, "cmV0dXJuIHt9?"), reason = "Invalid base64"},
        {body = json("apps_coffee.lua", 9, "cmV0dXJuIHt="), reason = "size/encoding mismatch"},
        {body = json("apps_coffee.lua", 100, "cmV0dXJuIHt9"), reason = "size/encoding mismatch"},
        {body = json("apps_coffee.lua", 8, "cmV0dXJuIHs="), reason = "Invalid app Lua"},
        {body = "<!DOCTYPE html>", reason = "requested base64 file"},
        {body = "{}", code = 403, reason = "HTTP 403"},
    }
    for _, case in ipairs(cases) do
        local comp = newBus().computer(10, "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        install("server")
        local settings, saved = serialize({enabledApps = {other = true}}), serialize({appStates = {coffee = {remainingTime = 42}}})
        comp.disk.files["configs_os.txt"], comp.disk.files["configs_os_state.txt"] = settings, saved
        comp.disk.files["apps_coffee.lua"], comp.disk.files.startup = "-- keep coffee", "-- keep startup"
        local closed = false
        comp.env.http = {get = function(url)
            if url:find("raw.githubusercontent.com", 1, true) then return nil end
            return {getResponseCode = function() return case.code or 200 end,
                readAll = function() return case.body end, close = function() closed = true end}
        end}
        local ok, err = pcall(install, "app", "coffee")
        equal(ok, false)
        assert(tostring(err):find("GitHub app download failed", 1, true), tostring(err))
        assert(table.concat(comp.log, "\n"):find(case.reason, 1, true), table.concat(comp.log, "\n"))
        equal(closed, true)
        equal(comp.disk.files["apps_coffee.lua"], "-- keep coffee")
        equal(comp.disk.files["configs_os.txt"], settings)
        equal(comp.disk.files["configs_os_state.txt"], saved)
        equal(comp.disk.files.startup, "-- keep startup")
        equal(comp.disk.files["apps_coffee.lua.pre_update"], nil)
    end
end

function tests.app_installer_github_terminate_during_download_does_not_retry_or_replace_files()
    local comp = newBus().computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server")
    comp.disk.files["apps_coffee.lua"] = "-- keep coffee"
    local requests = 0
    comp.env.http = {get = function()
        requests = requests + 1
        coroutine.yield("http_success")
        error("Download should have been terminated")
    end}
    local work = coroutine.create(function() install("app", "coffee") end)
    local ok, event = coroutine.resume(work)
    assert(ok, event); equal(event, "http_success")
    ok, event = coroutine.resume(work, "terminate")
    equal(ok, false); assert(tostring(event):find("Terminated", 1, true), tostring(event))
    equal(requests, 1)
    equal(comp.disk.files["apps_coffee.lua"], "-- keep coffee")
    equal(comp.disk.files["configs_os.txt"], nil)
end

function tests.app_installer_can_install_a_local_file_without_network()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end,
        run = function() error("Local app installation must not download anything") end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server")
    local app = "return {minWidth=10,minHeight=3}"
    comp.disk.files["incoming.lua"] = app
    install("app", "my_app", "--file", "incoming.lua")
    equal(comp.disk.files["apps_my_app.lua"], app)
    equal(comp.disk.files["incoming.lua"], app)
    equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.my_app, true)
    equal(comp.disk.files.startup, nil)
end
function tests.app_installer_failures_preserve_existing_code_and_settings()
    local expectedError = {syntax = "Invalid app Lua", download = "Pastebin app download failed",
        settings = "Invalid enabledApps setting", staging = "Cannot write install_plan.txt",
        name = "Specify a simple app name", wrong_computer = "Install apps on the central OS computer"}
    for _, reason in ipairs({"syntax", "download", "settings", "staging", "name", "wrong_computer"}) do
        local bus = newBus()
        local comp = bus.computer(10, reason == "wrong_computer" and "io" or "server")
        comp.env.shell = {dir = function() return "" end}
        local install = assert(comp.env.loadfile("install.lua"))
        install(reason == "wrong_computer" and "io" or "server")
        comp.disk.dirs.Configs, comp.disk.dirs.Apps = true, true
        comp.disk.files["configs_os.txt"] = serialize({custom = 12, enabledApps = reason == "settings" and "invalid" or {}})
        comp.disk.files["apps_test_app.lua"] = "-- keep existing app"
        comp.disk.files.startup = "-- keep existing startup"
        local config = comp.disk.files["configs_os.txt"]
        comp.disk.files["incoming.lua"] = reason == "syntax" and "return {" or "return {}"
        comp.env.shell.run = function(_, _, _, target)
            comp.disk.files[target] = "-- incomplete download"
            return false
        end
        if reason == "staging" then comp.disk.failWrite = true end
        local ok, err
        if reason == "download" then ok, err = pcall(install, "app", "test_app", "UserPaste")
        else ok, err = pcall(install, "app", reason == "name" and "../test_app" or "test_app", "--file", "incoming.lua") end
        equal(ok, false, reason .. " should fail")
        assert(tostring(err):find(expectedError[reason], 1, true), reason .. ": unexpected failure: " .. tostring(err))
        equal(comp.disk.files["apps_test_app.lua"], "-- keep existing app", reason)
        equal(comp.disk.files["configs_os.txt"], config, reason)
        equal(comp.disk.files.startup, "-- keep existing startup", reason)
    end
end
function tests.flat_installer_boots_without_creating_any_directories()
    for _, role in ipairs(roleNames) do
        local bus = newBus()
        local comp = bus.computer(10, role)
        comp.env.shell = {dir = function() return "" end}
        comp.env.fs.makeDir = function(path) error("Unexpected directory: " .. path) end
        assert(comp.env.loadfile("install.lua"))(role, "--startup")
        comp:start()
        for path in pairs(comp.disk.files) do assert(not path:find("/", 1, true), path) end
    end
end
function tests.flat_upgrade_preserves_legacy_settings_progress_enabled_apps_and_windows()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    comp.disk.files["Configs/network.txt"] = serialize({networkId = "existing-home", channel = 45231})
    comp.disk.files["Configs/os.txt"] = serialize({saveFile = "Configs/custom_state.txt", saveInterval = 30,
        customSetting = "keep", enabledApps = {service = true}})
    local legacy = {bootCounter = 4, appStates = {service = {elapsed = 123}}, appRegistry = {service = true},
        windows = {[7] = {id = 7, appName = "service", monitorId = "monitor_88:left", x = 2, y = 3,
            width = 20, height = 8, minimized = true, order = 4}},
        outputMap = {lamp = {clientId = "io_custom", side = "left", color = 1}},
        managedSides = {io_custom = {left = true}}, outputs = {lamp = true}}
    comp.disk.files["Configs/custom_state.txt"] = "corrupted primary"
    comp.disk.files["Configs/custom_state.txt.bak"] = serialize(legacy)
    local app = 'return {render=function() return {"Service"} end, background=function(dt,s) s.elapsed=s.elapsed+dt end}'
    comp.disk.files["Apps/service.lua"] = app
    comp.disk.files["Apps/switchboard.lua"] = "-- old disabled example"
    install("server", "--startup")
    equal(unserialize(comp.disk.files["configs_network.txt"]).networkId, "existing-home")
    local settings = unserialize(comp.disk.files["configs_os.txt"])
    equal(settings.saveFile, "configs_os_state.txt")
    equal(settings.customSetting, "keep")
    equal(settings.enabledApps.service, true)
    equal(unserialize(comp.disk.files["configs_os_state.txt"]).appStates.service.elapsed, 123)
    equal(comp.disk.files["apps_service.lua"], app)
    equal(comp.disk.files["apps_switchboard.lua"], nil, "Never migrate a disabled bundled demo")
    equal(comp.disk.files["Apps/service.lua"], app, "Keep legacy recovery copies")
    comp:start()
    equal(comp.server.state.windows[7].minimized, true)
    equal(comp.server.state.windows[7].monitorId, "monitor_88:left")
    equal(comp.server.state.appStates.service.elapsed, 123)
    equal(comp.server.state.outputMap.lamp.clientId, "io_custom")
    equal(comp.server.state.outputs.lamp, true)
    bus.advance(1)
    equal(comp.server.state.appStates.service.elapsed, 124)
    local currentState, currentConfig = comp.disk.files["configs_os_state.txt"], comp.disk.files["configs_os.txt"]
    comp.disk.files["apps_service.lua"] = "-- keep newer user code"
    install("server", "--startup")
    equal(comp.disk.files["configs_os_state.txt"], currentState, "Do not re-import stale legacy state")
    equal(comp.disk.files["configs_os.txt"], currentConfig)
    equal(comp.disk.files["apps_service.lua"], "-- keep newer user code")
end
function tests.flat_upgrade_preserves_io_and_monitor_identity_and_configuration()
    for _, role in ipairs({"io", "monitor"}) do
        local bus = newBus()
        local comp = bus.computer(20, role)
        comp.env.shell = {dir = function() return "" end}
        comp.disk.files["Configs/network.txt"] = serialize({networkId = "custom-network", channel = 40000, serverId = 99})
        local config = role == "io" and {clientId = "io_custom", sides = {"left", "front"}, safeOff = false}
            or {clientId = "screen_custom", textScale = 1}
        comp.disk.files["Configs/" .. role .. ".txt"] = serialize(config)
        assert(comp.env.loadfile("install.lua"))(role, "--startup")
        equal(unserialize(comp.disk.files["configs_network.txt"]).serverId, 99)
        equal(unserialize(comp.disk.files["configs_" .. role .. ".txt"]).clientId, config.clientId)
        comp:start()
        if role == "io" then
            assert(table.concat(comp.log, "\n"):find("io_custom", 1, true))
            equal(unserialize(comp.disk.files["configs_io.txt"]).safeOff, false)
        else equal(unserialize(comp.disk.files["configs_monitor.txt"]).textScale, 1) end
    end
end
function tests.flat_upgrade_rejects_corrupt_legacy_data_and_failed_staging_without_resetting_it()
    for _, reason in ipairs({"corrupt", "staging"}) do
        local bus = newBus()
        local comp = bus.computer(10, "server")
        comp.env.shell = {dir = function() return "" end}
        local legacy = reason == "corrupt" and "broken" or serialize({networkId = "keep", channel = 45231})
        comp.disk.files["Configs/network.txt"] = legacy
        comp.disk.files["main_os.lua"] = "-- previous OS entry point"
        if reason == "staging" then comp.disk.failWrite = true end
        local ok = pcall(assert(comp.env.loadfile("install.lua")), "server", "--startup")
        equal(ok, false)
        equal(comp.disk.files["Configs/network.txt"], legacy)
        equal(comp.disk.files["configs_network.txt"], nil)
        equal(comp.disk.files["main_os.lua"], "-- previous OS entry point")
    end
end
local function diskBytes(disk)
    local bytes = 0
    for _, contents in pairs(disk.files) do bytes = bytes + #contents end
    return bytes
end

function tests.v56_installer_upgrades_a_legacy_disk_with_quota_sizes_and_existing_data()
    local comp = newBus().computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server", "--startup")
    local disk = comp.disk
    local current = disk.files["lib_storage.lua"]
    disk.files["lib_storage.lua"] = current .. "\n-- previous server version\n"
    disk.files["main_os.lua.pre_update"] = disk.files["main_os.lua"]
    disk.files.startup = "-- previous autorun\n"
    local config = serialize({enabledApps = {}})
    local state = serialize({clientNames = {io_11 = "Pump"}, appStates = {coffee = {totalHarvests = 44}},
        desktops = {monitor_12 = {layout = {id = "existing"}}}})
    disk.files["configs_network.txt"] = serialize({networkId = "persisted", channel = 45231})
    disk.files["configs_transport.txt"] = serialize({bootCounter = 3})
    disk.files["configs_os.txt"], disk.files["configs_os_state.txt"] = config, state
    disk.files["backup_os_all.txt"], disk.files["apps_local.lua"] = "Existing backup", "return {}\n"
    disk.legacyTextReads, disk.legacyFileSizes, disk.copyMove = true, true, true
    disk.capacity = 1000000
    disk.files["user_file.txt"] = string.rep("x", comp.env.fs.getFreeSpace("/") - 4096 - #"user_file.txt")
    equal(comp.env.fs.getFreeSpace("/"), 4096)
    equal(comp.env.fs.getSize("startup"), 512)
    equal(comp.env.fs.getSize("lib_storage.lua"), #disk.files["lib_storage.lua"] + #"lib_storage.lua")
    install("server", "--startup")
    equal(disk.files["lib_storage.lua"], current)
    equal(disk.files.startup, 'shell.setDir("/")\nshell.run("main_os.lua")\n')
    for _, path in ipairs({"install_plan.txt", "install_pending.txt", "main_os.lua.pre_update"}) do
        equal(disk.files[path], nil, path)
    end
    equal(disk.files["configs_os.txt"], config)
    equal(disk.files["configs_os_state.txt"], state)
    equal(disk.files["backup_os_all.txt"], "Existing backup")
    equal(disk.files["apps_local.lua"], "return {}\n")
    disk.failWrite = true
    install("server", "--startup") -- An unchanged install should need no writes.
    disk.failWrite = false
    comp.env.loadfile = function(path)
        local source = disk.files[path]
        if not source then return nil, "Missing installed program: " .. path end
        local chunk, err = loadstring(source, path)
        if chunk then setfenv(chunk, comp.env) end
        return chunk, err
    end
    comp:start()
    equal(comp.server.api.clientName("io_11"), "Pump")
    equal(comp.server.state.appStates.coffee.totalHarvests, 44)
end

function tests.v56_installer_reports_quota_exhaustion_before_replacing_files()
    local comp = newBus().computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    local disk = comp.disk
    disk.legacyFileSizes = true
    disk.files["main_os.lua"], disk.files["lib_server.lua"] = "-- old OS", "-- old server"
    disk.files["my_app.lua"] = "return {}"
    local config = serialize({enabledApps = {custom = true}})
    disk.files["configs_os.txt"] = config
    disk.capacity = 5 * 512 + 1024 -- Five current allocations, with space for the two journal files.
    local open, targetWrites = comp.env.fs.open, 0
    comp.env.fs.open = function(path, mode)
        if path == "apps_custom.lua" and mode == "w" then targetWrites = targetWrites + 1 end
        return open(path, mode)
    end
    local ok, err = pcall(install, "app", "custom", "--file", "my_app.lua")
    assert(not ok and tostring(err):find("Not enough disk space for install", 1, true), tostring(err))
    equal(targetWrites, 0)
    equal(disk.files["configs_os.txt"], config)
    equal(disk.files["install_plan.txt"], nil)
    equal(disk.files["install_pending.txt"], nil)
    disk.capacity = disk.capacity + 512
    install("app", "custom", "--file", "my_app.lua")
    equal(targetWrites, 1)
    equal(disk.files["apps_custom.lua"], "return {}")
    equal(disk.files["configs_os.txt"], config)
    equal(disk.files["install_pending.txt"], nil)
end

function tests.v53_small_installer_reclaims_old_program_copies_and_updates_under_quota()
    local comp = newBus().computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server")
    local disk = comp.disk
    local oldServer = disk.files["lib_server.lua"]
    disk.files["lib_server.lua"] = oldServer .. "\n-- old version"
    disk.files["lib_server.lua.pre_update"] = oldServer
    disk.files["main_os.lua.download"] = disk.files["main_os.lua"]
    disk.files["apps_coffee.lua"] = "return {}"
    disk.files["apps_coffee.lua.restore_new"] = "-- abandoned app stage"
    disk.files["apps_custom.lua.pre_update"] = "-- only copy of an old app"
    disk.files["configs_os_state.txt"] = serialize({appStates = {coffee = {totalHarvests = 44}}})
    disk.files["configs_os.txt"] = serialize({enabledApps = {coffee = true}, customSetting = "keep"})
    disk.files["backup_os_all.txt"] = "user's backup"
    disk.files.startup = "-- custom autorun"
    local state, config, startup = disk.files["configs_os_state.txt"], disk.files["configs_os.txt"], disk.files.startup
    local file = assert(io.open("install.lua", "r"))
    local bundle = file:read("*a"); file:close()
    disk.files["install_plan.txt"] = "interrupted before any program changed"
    disk.capacity, disk.copyMove = diskBytes(disk) + 1024, true
    assert(#bundle > comp.env.fs.getFreeSpace("/") + #oldServer)
    comp.env.http = {get = function(url)
        assert(url:find("/test%-release/install%.lua$"), url)
        return {readAll = function() return bundle end, close = function() end}
    end}
    local small = assert(comp.env.loadfile("tools_install_github.lua"))
    small("--installer-ref", "test-release", "space")
    assert(disk.files["lib_server.lua.pre_update"], "A storage report is read-only")
    small("--installer-ref", "test-release", "server")
    equal(disk.files["lib_server.lua"], oldServer)
    for _, path in ipairs({"install.lua", "install_pending.txt", "install_plan.txt", "lib_server.lua.pre_update", "main_os.lua.download",
        "apps_coffee.lua.restore_new"}) do equal(disk.files[path], nil, path) end
    equal(disk.files["apps_custom.lua.pre_update"], "-- only copy of an old app")
    equal(disk.files["configs_os_state.txt"], state)
    equal(disk.files["configs_os.txt"], config)
    equal(disk.files["backup_os_all.txt"], "user's backup")
    equal(disk.files.startup, startup)
    assert(comp.env.fs.getFreeSpace("/") > #oldServer)
    disk.failWrite = true
    small("--installer-ref", "test-release", "server")
end

function tests.v53_interrupted_update_blocks_boot_and_resumes_the_same_command()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    comp.env.shell = {dir = function() return "" end}
    local install = assert(comp.env.loadfile("install.lua"))
    install("server")
    local disk = comp.disk
    local backup, server = disk.files["lib_backup.lua"], disk.files["lib_server.lua"]
    disk.files["lib_backup.lua"] = backup .. "\n-- old backup"
    disk.files["lib_server.lua"] = server .. "\n-- old server"
    disk.files["configs_os_state.txt"] = serialize({clientNames = {io_11 = "Pump"}})
    local state = disk.files["configs_os_state.txt"]
    comp.env.sleep = function() coroutine.yield("cooperate") end
    local display = comp.env.print
    comp.env.print = function(line)
        display(line)
        if line == "Installed lib_backup.lua" then coroutine.yield("power lost") end
    end
    local thread = coroutine.create(function() install("server") end)
    for attempt = 1, 1000 do
        local ok, event = coroutine.resume(thread)
        assert(ok, event)
        if event == "power lost" then break end
        equal(event, "cooperate")
    end
    equal(coroutine.status(thread), "suspended")
    equal(disk.files["lib_backup.lua"], backup)
    equal(disk.files["lib_server.lua"], server .. "\n-- old server")
    assert(disk.files["install_pending.txt"])
    local restarted = bus.computer(10, "server", {disk = disk})
    restarted.env.shell = {dir = function() return "" end}
    local started, bootError = pcall(restarted.start)
    assert(not started and tostring(bootError):find("Update interrupted", 1, true))
    local resume = assert(restarted.env.loadfile("install.lua"))
    local wrong, resumeError = pcall(resume, "io")
    assert(not wrong and tostring(resumeError):find("Resume the update with inst server", 1, true))
    resume("server")
    equal(disk.files["install_pending.txt"], nil)
    equal(disk.files["install_plan.txt"], nil)
    equal(disk.files["lib_server.lua"], server)
    equal(disk.files["configs_os_state.txt"], state)
    restarted:start()
    equal(restarted.server.api.clientName("io_11"), "Pump")
end

function tests.v53_boots_with_only_counter_space_then_compacts_the_legacy_state_safely()
    local bus = newBus()
    local comp = bus.computer(10, "server")
    local rows, path = {}, "configs_os_state.txt"
    for i = 1, 800 do rows[i] = {id = i, text = "Example repeated configuration value for a large notes collection"} end
    local saved = {bootCounter = 120, appStates = {notes = {rows = rows}}, clientNames = {sensor_14 = "Solar farm"}}
    local legacy = serialize(saved)
    local disk = comp.disk
    disk.files[path] = legacy
    disk.files["configs_os.txt"] = serialize({enabledApps = {}})
    disk.files["configs_network.txt"] = serialize({networkId = "home", channel = 45231})
    disk.files["configs_transport.txt"] = serialize({bootCounter = 12})
    disk.capacity, disk.copyMove = diskBytes(disk) + 2048, true
    local storage = comp.env.dofile("lib_storage.lua")
    local old, err = storage.save(path, saved)
    assert(not old and tostring(err):find("Out of space", 1, true))
    comp:start()
    equal(disk.files[path], legacy, "Boot must leave the old live state alone")
    equal(comp.server.api.clientName("sensor_14"), "Solar farm")
    equal(comp.server.session, "10:net:13")
    local stored, reason = comp.server.save()
    assert(not stored and tostring(reason):find("Not enough disk space", 1, true))
    equal(disk.files[path], legacy)
    disk.capacity = diskBytes(disk) + math.floor(#legacy * 0.7)
    assert(comp.server.save())
    assert(#disk.files[path] + #disk.files[path .. ".bak"] < #legacy, "Both compact states fit where one old stage did not")
    equal(disk.files[path .. ".tmp"], nil)
    equal(comp.savedState().appStates.notes.rows[800].text, rows[800].text)
    disk.files[path] = "interrupted write"
    local recovered = bus.computer(10, "server", {disk = disk}):start()
    equal(recovered.server.session, "10:net:14")
    equal(recovered.server.state.appStates.notes.rows[800].id, 800)
    equal(recovered.server.api.clientName("sensor_14"), "Solar farm")
end

assert(hostLoadfile("tests_coffee.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_file_explorer.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_desktop.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_appearance.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_switchboard.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_sensors.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_me_storage.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_me_monitor.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_me.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_screensaver.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_solar_farm.lua"))()(tests, newBus, monitor, serialize, unserialize, equal, githubFile)
assert(hostLoadfile("tests_relay.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_console.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_clock.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_system.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_work.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
assert(hostLoadfile("tests_v39.lua"))()(tests, newBus, monitor, serialize, unserialize, equal)
local names, failures = {}, {}
local testFilter=rawget(_G,"SMART_HOME_TEST_FILTER") or os.getenv and os.getenv("SMART_HOME_TEST_FILTER")
for name in pairs(tests) do if not testFilter or name:find(testFilter,1,true) then names[#names + 1] = name end end
table.sort(names)
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then hostPrint("PASS " .. name)
    else failures[#failures + 1] = name; hostPrint("FAIL " .. name .. ": " .. tostring(err)) end
end
assert(#failures == 0, tostring(#failures) .. " integration tests failed")
hostPrint(#names .. " integration tests passed (" .. _VERSION .. ")")
