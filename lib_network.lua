-- All wire packets are serialized strings, including on old CC modems.
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
    local net = {id = os.getComputerID(), config = config, isServer = isServer, bootCounter = boot.bootCounter}
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
        if message.type == "announce" and net.backupSettings then
            net.backupSettings.transportBoot = net.bootCounter
            message.backupSettings = net.backupSettings
        end
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
