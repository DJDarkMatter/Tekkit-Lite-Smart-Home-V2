-- Central OS. One serial loop owns state; cooperative pauses buffer incoming
-- events without running commands or changing app state during a checkpoint.
local Console = dofile("lib_console.lua")
local console = Console.new(term)
console.log("SmartHome OS v40: starting")
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
