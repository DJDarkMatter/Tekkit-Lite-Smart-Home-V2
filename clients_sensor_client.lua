-- Generic OpenCCSensors bridge; all names/configuration stay in the root.
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Sensor = dofile("lib_sensor.lua")
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
