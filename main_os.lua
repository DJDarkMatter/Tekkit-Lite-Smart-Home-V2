-- Central OS. The collector buffers events while one serial worker changes
-- app state, paints monitors or checkpoints. No command can interleave a save.
local Work = dofile("lib_work.lua")
local console
local ok, err = Work.protect(function()
    Work.stage = "Loading OS configuration"
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
    console = Console.new(term)
    local net = Network.new(networkConfig, true, console.log)
    local server, timer
    local pending, head, sequence = {}, 1, 0
    local function enqueue(item)
        local empty = head > #pending
        item.received = os.clock()
        pending[#pending + 1] = item
        if empty then os.queueEvent("smarthome_server_work") end
    end
    parallel.waitForAny(function()
        while true do
            local item = {os.pullEvent()}
            local event = item[1]
            if event == "modem_message" or event == "peripheral" or event == "peripheral_detach" then enqueue(item)
            elseif event == "timer" and item[2] == timer then enqueue(item)
            else
                local command = console.handle(unpack(item))
                if command ~= nil then enqueue({"command", command}) end
            end
        end
    end, function()
        Work.enable(function()
            sequence = sequence + 1
            os.queueEvent("smarthome_server_yield", sequence)
            local _, current
            repeat _, current = os.pullEvent("smarthome_server_yield") until current == sequence
        end)
        Work.stage = "Loading saved OS state"
        server = Server.new(net, storage, config, console.log)
        server.start()
        console.log("Type help for commands; clear clears this console")
        if fs.exists("diagnostics_os_error.txt") then console.log("Saved OS error: type errorlog to read it") end
        timer = os.startTimer(server.nextTickInterval())
        while true do
            if head > #pending then
                Work.stage = "Waiting for events"
                os.pullEvent("smarthome_server_work")
            else
                local item = pending[head]
                pending[head], head = false, head + 1
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
                if head > #pending then pending, head = {}, 1 end
                Work.check(16384)
            end
        end
    end)
end)
Work.disable()
if not ok then
    local cancelled = tostring(err) == "Terminated" or tostring(err):match(":%s*Terminated$")
    if not cancelled then Work.report(Work.stage, err) end
    if console then pcall(console.finish) end
    error(err, 0)
end
