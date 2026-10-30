-- All wire packets are serialized strings, including on old CC modems.
local Network = {}
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

local function validPath(path)
    if type(path) ~= "table" then return false end
    local seen, count = {}, 0
    for index, hop in pairs(path) do
        count = count + 1
        if not integer(index, 1, #path) or type(hop) ~= "table"
            or not integer(hop.computerId, 0, 2147483647)
            or type(hop.id) ~= "string" or #hop.id < 1 or #hop.id > 64
            or seen[hop.computerId] then return false end
        seen[hop.computerId] = true
    end
    return count == #path
end

local function transportValid(packet, reply, config)
    local t = packet._transport
    if type(t) ~= "table" or t.version ~= 1 or t.serverChannel ~= config.channel
        or not integer(t.boot, 1, 2147483647) or not integer(t.sequence, 1, 2147483647)
        or not integer(t.channel, 1, 65532) or not validPath(t.path) then return false end
    for _, hop in ipairs(t.path) do if hop.computerId == packet.sender then return false end end
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

-- A bounded FIFO suppresses copies, not retries: every new send has a new ID.
function Network.newCache(limit, lifetime)
    local entries, queue, head, tail = {}, {}, 1, 0
    return function(key, now)
        while head <= tail and now - queue[head].at >= lifetime do
            local entry = queue[head]
            if entries[entry.key] == entry then entries[entry.key] = nil end
            queue[head], head = nil, head + 1
        end
        if entries[key] then return false end
        if tail - head + 1 >= limit then
            local entry = queue[head]
            if entries[entry.key] == entry then entries[entry.key] = nil end
            queue[head], head = nil, head + 1
        end
        local entry = {key = key, at = now}
        tail, queue[tail + 1], entries[key] = tail + 1, entry, entry
        if head > limit then
            local compact = {}
            for i = head, tail do compact[#compact + 1] = queue[i] end
            queue, head, tail = compact, 1, #compact
        end
        return true
    end
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
    local net = {id = os.getComputerID(), config = config, isServer = isServer}
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
        local raw = textutils.serialize(packet)
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
        return net.send(config.channel, config.serverId, message)
    end

    function net.toClient(client, message)
        return net.send(client.channel, client.computerId, message)
    end

    local function decode(side, channel, replyChannel, raw)
        if side ~= net.side then return nil end
        if not integer(replyChannel, 1, 65532) or type(raw) ~= "string"
            or #raw > 65536 then return nil end
        local ok, packet = pcall(textutils.unserialize, raw)
        if not ok or type(packet) ~= "table" or packet.protocol ~= protocol
            or packet.networkId ~= config.networkId
            or not integer(packet.sender, 0, 2147483647)
            or packet.sender == net.id or type(packet.type) ~= "string"
            or packet.recipient ~= nil and not integer(packet.recipient, 0, 2147483647) then return nil end
        if packet._transport ~= nil and not transportValid(packet, replyChannel, config) then return nil end
        if channel == relayChannel then
            if config.relayEnabled == false or packet._transport == nil then return nil end
        elseif channel ~= net.listenChannel then return nil end
        return packet
    end

    function net.readRelay(side, channel, replyChannel, raw)
        if channel ~= relayChannel then return nil end
        return decode(side, channel, replyChannel, raw)
    end

    function net.forward(packet, replyChannel, id)
        if not net.ensureModem() then return false end
        local t = packet._transport
        if not t then return false end
        for _, hop in ipairs(t.path) do if hop.computerId == net.id then return false end end
        t.path[#t.path + 1] = {id = id, computerId = net.id}
        packet._route = nil
        local raw = textutils.serialize(packet)
        if #raw > 65536 then return false end
        local ok = pcall(net.modem.transmit, relayChannel, replyChannel, raw)
        if not ok then net.modem, net.side = nil, nil end
        return ok
    end

    function net.receive(side, channel, replyChannel, raw)
        local packet = decode(side, channel, replyChannel, raw)
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
        end
        return packet
    end

    return net
end

Network.sides = sides
Network.integer = integer
Network.packetKey, Network.relayChannel = packetKey, relayChannel
return Network
