-- A single wireless modem bridges all updated SmartHome roles in both directions.
local storage = dofile("lib_storage.lua")
local Network = dofile("lib_network.lua")
local Relay = dofile("lib_relay.lua")
local networkConfig = storage.config("configs_network.txt", {networkId = "home", channel = 45231})
local config = storage.config("configs_relay.txt", {clientId = "relay_" .. os.getComputerID(), announceInterval = 5, timeout = 15})
assert(type(config.clientId) == "string" and #config.clientId > 0 and #config.clientId <= 64, "Invalid relay client ID")
assert(type(config.announceInterval) == "number" and config.announceInterval >= 0.5 and config.announceInterval <= 60,
    "Invalid relay announce interval")
assert(type(config.timeout) == "number" and config.timeout > config.announceInterval, "Invalid relay timeout")
local net = Network.new(networkConfig, false)
local client = Relay.new(net, config)
print("Relay client: " .. config.clientId .. " (computer " .. net.id .. ")")
print("Relay channel " .. net.relayChannel .. "; automatic multi-hop forwarding")
client.tick(os.clock())
local timer = os.startTimer(0.1)
while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" then client.handleModem(p1, p2, p3, p4, os.clock())
    elseif event == "timer" and p1 == timer then client.tick(os.clock()); timer = os.startTimer(0.1)
    elseif event == "peripheral" or event == "peripheral_detach" then net.peripheralChanged(p1) end
end
