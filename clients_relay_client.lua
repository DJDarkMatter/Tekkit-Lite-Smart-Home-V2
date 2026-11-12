-- A single wireless modem bridges all updated SmartHome roles in both directions.
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
    local Backup = dofile("lib_backup.lua")
    Backup.recover(storage)
    local Network = dofile("lib_network.lua")
    local Relay = dofile("lib_relay.lua")
    local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
    local config = storage.config("configs_relay.txt", {clientId = "relay_" .. os.getComputerID(), announceInterval = 5, timeout = 15})
    assert(type(config.clientId) == "string" and #config.clientId > 0 and #config.clientId <= 64, "Invalid relay client ID")
    assert(type(config.announceInterval) == "number" and config.announceInterval >= 0.5 and config.announceInterval <= 60,
        "Invalid relay announce interval")
    assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid relay timeout")
    net = Network.new(networkConfig, false)
    net.backupSettings = Backup.clientSettings("relay", config, networkConfig)
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
