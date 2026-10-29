-- Start from / with: main_os.lua
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
local console = Console.new(term)
local net = Network.new(networkConfig, true, console.log)
local server = Server.new(net, storage, config, console.log)
server.start()
console.log("Type help for commands; clear clears this console")

-- The bottom-row editor owns its cursor independently of asynchronous logs.
-- Network/timer events continue while commands are being edited.
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
        local line = console.handle(os.pullEvent())
        if line ~= nil then
            local lines, quit, action = server.command(line)
            if action == "clear" then console.clear() end
            for _, output in ipairs(lines) do console.log(output) end
            if quit then console.finish(); return end
        end
    end
end)
