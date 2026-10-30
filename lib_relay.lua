-- Stateless forwarding never replaces the original endpoint identity/session.
local Network = dofile("lib_network.lua")
local Relay = {}

function Relay.new(net, config)
    assert(net.config.relayEnabled ~= false, "Relay requires relayEnabled in network settings")
    local client = {connected = false, nonce = 0, forwarded = 0, lastAnnounce = -math.huge}
    local remember = Network.newCache(4096, 60)

    function client.handleModem(side, channel, replyChannel, raw, now)
        local message = net.receive(side, channel, replyChannel, raw)
        if message and message.type == "welcome" and message.clientId == config.clientId
            and message.nonce == client.nonce and type(message.serverSession) == "string"
            and (not client.connected or message.sender == client.serverId) then
            local changed = not client.connected or client.serverSession ~= message.serverSession
            client.connected, client.serverId, client.serverSession, client.lastServer = true, message.sender, message.serverSession, now
            if changed then print("Connected to OS computer " .. client.serverId) end
        end
        local packet = net.readRelay(side, channel, replyChannel, raw)
        if not packet or packet.recipient == net.id then return end
        for _, hop in ipairs(packet._transport.path) do if hop.computerId == net.id then return end end
        if not remember(Network.packetKey(packet), now) then return end
        if net.forward(packet, replyChannel, config.clientId) then client.forwarded = client.forwarded + 1 end
    end

    function client.tick(now)
        if not net.ensureModem() or client.connected and now - client.lastServer >= config.timeout then
            if client.connected then print("OS connection lost; waiting for a route") end
            client.connected = false
        end
        if net.modem and now - client.lastAnnounce >= config.announceInterval then
            client.nonce, client.lastAnnounce = client.nonce + 1, now
            net.toServer({type = "announce", clientType = "relay", clientId = config.clientId,
                nonce = client.nonce, relayProtocol = 1, forwarded = math.min(client.forwarded, 2147483647)})
        end
    end
    return client
end

return Relay
