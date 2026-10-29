local storage = dofile("lib_storage.lua")
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
    assert(args[1] == "calibrate" and not args[3], "Usage: clients_monitor_client.lua calibrate [side]")
    local side = args[2] or next(client.devices)
    assert(side, "Attach a monitor first")
    print("Calibrating " .. side .. ": tap the centre of each white +")
    local offset, err = client.calibrate(side)
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
