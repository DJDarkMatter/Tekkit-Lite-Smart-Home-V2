-- Central OS. One serial loop owns state; cooperative pauses buffer incoming
-- events without running commands or changing app state during a checkpoint.
local Console = dofile("lib_console.lua")
local console = Console.new(term)
console.log("SmartHome OS v48: starting")
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
local packetCount, packetBytes, overflow = 0, 0, false
local wakeQueued, pauseStarted = false, -math.huge
local function armPauseTimer()
    local now = os.clock()
    -- Arm while entering a fresh event slice, before expensive work. Renew a
    -- stale ID if a full native queue also dropped its timer event.
    if not pauseTimer or now - pauseStarted >= 0.1 then
        pauseTimer, pauseStarted = os.startTimer(0), now
        wakeQueued = false
    end
end
local function enqueue(item)
    item.received = os.clock()
    tail = tail + 1; pending[tail] = item
end
local function collect(item)
    local event = item[1]
    if event == "smarthome_server_yield" then
        if item[2] == sequence then wakeQueued = false end
        return
    end
    if event == "timer" and item[2] == pauseTimer then pauseTimer, wakeQueued = nil, false; return end
    if event == "modem_message" then
        local raw = item[5]
        if (item[3] ~= net.listenChannel and item[3] ~= net.relayChannel)
            or type(raw) ~= "string" or #raw > 65536 then return end
        if packetCount >= 256 or packetBytes + #raw > 1048576 then
            if not overflow then console.log("OS receive queue full; dropping excess packets"); overflow = true end
            return
        end
        packetCount, packetBytes = packetCount + 1, packetBytes + #raw
        enqueue(item)
    elseif event == "peripheral" or event == "peripheral_detach" then enqueue(item)
    elseif event == "timer" and item[2] == timer then enqueue(item)
    else
        local command = console.handle(unpack(item))
        if command ~= nil then enqueue({"command", command}) end
    end
end
local function cooperate()
    if not wakeQueued then
        sequence, wakeQueued = sequence + 1, true
        -- A pending legacy watchdog can reject this native call before the
        -- actual yield. The already-armed timer still wakes os.pullEvent.
        local queued, why = pcall(os.queueEvent, "smarthome_server_yield", sequence)
        if not queued and not Work.isWatchdog(why) then error(why, 0) end
    end
    -- Any delivered event completes a CPU slice. Do not drain a modem burst
    -- waiting for our own marker, or queue another marker for every packet.
    collect({os.pullEvent()})
    armPauseTimer()
end
ok, err = Work.protect(function()
    Work.enable(cooperate, 8192)
    armPauseTimer()
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
            armPauseTimer()
            local item = pending[head]
            pending[head], head = nil, head + 1
            local event, p1, p2, p3, p4 = unpack(item)
            if event == "modem_message" then
                packetCount, packetBytes = packetCount - 1, packetBytes - #p4
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
            if head > tail then pending, head, tail, overflow = {}, 1, 0, false
            else Work.check(8192) end
        end
    end
end)
finish(ok, err)
