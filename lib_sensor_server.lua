-- Runtime-only sensor catalogs, bounded multipart readings and subscriptions.
local Data = dofile("lib_sensor_data.lua")
local Hub = {}
local sides = {top = true, bottom = true, left = true, right = true, front = true, back = true}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function keys(values)
    local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result
end
function Hub.new(net, clients, session)
    local hub = {watches = {}}
    function hub.announce(client, message, reconnect)
        if message.sensorProtocol ~= Data.protocol or not Data.string(message.bootId, 96) then return end
        if reconnect or client.bootId ~= message.bootId then
            client.ports, client.catalogParts, client.readings, client.sampleParts, client.sensorSent = {}, {}, {}, {}, nil
            client.catalogError, client.catalogRejected = nil, 0
        end
        client.bootId, client.sensorProtocol = message.bootId, Data.protocol
        client.sensorMaxAge = Data.number(message.pollInterval) and message.pollInterval >= 0.5 and message.pollInterval <= 60
            and math.max(10, 3 * message.pollInterval) or 10
    end
    function hub.watch(key, address)
        if not Data.string(key, 96) or not Data.address(address) then return false, "Invalid sensor binding" end
        hub.watches[key] = {address = copy(address), used = os.clock()}
        return true
    end
    function hub.unwatch(key) hub.watches[key] = nil end
    local function wanted(id, side, target)
        for _, item in pairs(hub.watches) do
            local a = item.address
            if os.clock() - item.used < 10 and a.clientId == id and a.side == side and a.target == target then return true end
        end
        return false
    end
    function hub.catalog(client, message, now)
        local function reject(reason)
            client.catalogError = reason
            client.catalogRejected = math.min((client.catalogRejected or 0) + 1, 2147483647)
            return false, reason
        end
        if client.sensorProtocol ~= Data.protocol or client.bootId ~= message.bootId or not sides[message.side]
            or not Data.integer(message.sequence, 1, 2147483647) or not Data.integer(message.parts, 1, 64)
            or not Data.integer(message.part, 1, message.parts) or type(message.targets) ~= "table" or #message.targets > 64
            or message.card ~= nil and not Data.string(message.card, 128)
            or not ({ok = true, scanning = true, error = true, no_card = true, detached = true})[message.status] then
            return reject("Invalid catalog header or sensor version")
        end
        local targets = {}
        for _, entry in ipairs(message.targets) do
            if type(entry) ~= "table" or not Data.string(entry.key, 128)
                or entry.type ~= nil and (type(entry.type) ~= "string" or #entry.type > 96)
                or entry.rawName ~= nil and (type(entry.rawName) ~= "string" or #entry.rawName > 128) then
                return reject("Invalid target metadata")
            end
            targets[#targets + 1] = Data.target(entry.key, {Type = entry.type, RawName = entry.rawName, Position = entry.position})
        end
        local current = client.ports[message.side]
        if current and message.sequence <= current.sequence then return end
        local pending = client.catalogParts[message.side]
        if pending and message.sequence < pending.sequence then return end
        if not pending or pending.sequence ~= message.sequence then
            pending = {sequence = message.sequence, parts = message.parts, card = message.card, status = message.status, chunks = {}, time = now}
            client.catalogParts[message.side] = pending
        end
        if pending.parts ~= message.parts or pending.card ~= message.card or pending.status ~= message.status then
            return reject("Conflicting catalog parts")
        end
        pending.chunks[message.part] = targets
        if current and current.card ~= message.card then current.status = "card_changed" end
        local all, seen = {}, {}
        for part = 1, pending.parts do
            if not pending.chunks[part] then return end
            for _, target in ipairs(pending.chunks[part]) do
                if seen[target.key] then return reject("Duplicate target address") end
                seen[target.key], all[#all + 1] = true, target
            end
        end
        table.sort(all, function(a, b) return a.key < b.key end)
        client.ports[message.side] = {side = message.side, card = message.card, cardKind = Data.cardKind(message.card),
            status = message.status, error = type(message.error) == "string" and message.error:sub(1, 160) or nil,
            sequence = message.sequence, targets = all, time = now, truncated = message.truncated == true}
        client.catalogParts[message.side] = nil
        client.catalogError = nil
        client.lastSeen = now
        if not current or current.card ~= message.card or message.status ~= "ok" then
            client.readings[message.side], client.sampleParts[message.side], client.sensorSent = {}, {}, nil
        end
    end
    function hub.sample(client, message, now)
        if client.sensorProtocol ~= Data.protocol or client.bootId ~= message.bootId or not sides[message.side]
            or not Data.string(message.target, 128) or not Data.integer(message.sequence, 1, 2147483647)
            or not Data.integer(message.parts, 1, Data.maxParts) or not Data.integer(message.part, 1, message.parts)
            or type(message.data) ~= "string" or #message.data > Data.chunkSize
            or (message.status ~= "ok" and message.status ~= "error") or not wanted(message.clientId, message.side, message.target) then return end
        local port = client.ports[message.side]
        if not port or port.card ~= message.card then return end
        client.readings[message.side], client.sampleParts[message.side] = client.readings[message.side] or {}, client.sampleParts[message.side] or {}
        local readings, parts = client.readings[message.side], client.sampleParts[message.side]
        local current, pending = readings[message.target], parts[message.target]
        if current and message.sequence <= current.sequence or pending and message.sequence < pending.sequence then return end
        if message.unchanged then
            if message.parts ~= 1 or message.part ~= 1 or message.status ~= "ok" or message.data ~= ""
                or not current or not current.data or current.dataSequence ~= message.baseSequence then return end
            current.sequence, current.status, current.error, current.time, current.dataTime = message.sequence, "ok", nil, now, now
            parts[message.target], client.lastSeen = nil, now
            return
        end
        if not pending or pending.sequence ~= message.sequence then
            pending = {sequence = message.sequence, parts = message.parts, status = message.status, card = message.card, chunks = {}, time = now}
            parts[message.target] = pending
        end
        if pending.parts ~= message.parts or pending.status ~= message.status or pending.card ~= message.card then return end
        pending.chunks[message.part] = message.data
        for part = 1, pending.parts do if not pending.chunks[part] then return end end
        local data, err
        if pending.status == "ok" then
            local ok, value = pcall(textutils.unserialize, table.concat(pending.chunks))
            if not ok or type(value) ~= "table" then return end
            data, err = Data.clean(value)
            if not data then return end
        else err = type(message.error) == "string" and message.error:sub(1, 160) or "Sensor read failed" end
        readings[message.target] = {sequence = message.sequence, card = message.card, status = pending.status,
            data = data or current and current.data, error = err, time = now, dataTime = data and now or current and current.dataTime,
            dataSequence = data and message.sequence or current and current.dataSequence}
        parts[message.target], client.lastSeen = nil, now
    end
    function hub.getClients()
        local result = {}
        for _, id in ipairs(keys(clients)) do
            local client = clients[id]
            local ports = {}
            for _, side in ipairs(keys(client.ports or {})) do ports[#ports + 1] = copy(client.ports[side]) end
            local pending = {}
            for _, side in ipairs(keys(client.catalogParts or {})) do
                local part, received = client.catalogParts[side], 0
                for _ in pairs(part.chunks) do received = received + 1 end
                pending[#pending + 1] = {side = side, received = received, parts = part.parts}
            end
            result[#result + 1] = {id = id, online = client.online, computerId = client.computerId, ports = ports,
                sensorProtocol = client.sensorProtocol, bootId = client.bootId,
                catalogError = client.catalogError, catalogRejected = client.catalogRejected or 0, pending = pending}
        end
        return result
    end
    function hub.read(address)
        if not Data.address(address) then return {status = "unconfigured", error = "Select a sensor target"} end
        local client = clients[address.clientId]
        if not client or not client.online then return {status = "offline", error = "Sensor client offline"} end
        local port = client.ports and client.ports[address.side]
        if not port then return {status = "waiting", error = "Waiting for sensor catalog"} end
        if port.status ~= "ok" then return {status = port.status, error = port.error or "Sensor unavailable"} end
        if address.card and address.card ~= port.card then return {status = "card_changed", error = "Sensor card changed"} end
        local found
        for _, target in ipairs(port.targets) do if target.key == address.target then found = target; break end end
        if not found then return {status = "missing", error = "Target missing or out of range"} end
        if address.targetType and address.targetType ~= found.type then return {status = "target_changed", error = "Target type changed"} end
        local reading = client.readings[address.side] and client.readings[address.side][address.target]
        if not reading then return {status = "waiting", error = "Waiting for reading"} end
        local result = copy(reading)
        result.age, result.target = math.max(0, os.clock() - (reading.dataTime or reading.time)), copy(found)
        if result.age > client.sensorMaxAge and result.status == "ok" then result.status, result.error = "stale", "Reading outdated" end
        result.reactor = Data.reactor(result.data)
        return result
    end
    function hub.tick(now)
        local requests = {}
        for key, item in pairs(hub.watches) do
            if now - item.used >= 10 then hub.watches[key] = nil
            else
                local a = item.address
                requests[a.clientId] = requests[a.clientId] or {}
                requests[a.clientId][#requests[a.clientId] + 1] = a
            end
        end
        for id, client in pairs(clients) do
            if client.online and client.sensorProtocol == Data.protocol then
                local list, seen = {}, {}
                table.sort(requests[id] or {}, function(a, b) return a.side .. a.target < b.side .. b.target end)
                for _, source in ipairs(requests[id] or {}) do
                    seen[source.side] = seen[source.side] or {}
                    if not seen[source.side][source.target] and #list < 128 then
                        local a = copy(source)
                        local port = client.ports[a.side]
                        a.card = a.card or port and port.card
                        list[#list + 1], seen[a.side][a.target] = a, true
                    end
                end
                local signature = textutils.serialize(list)
                if signature ~= client.sensorSignature or not client.sensorSent or now - client.sensorSent >= 3 then
                    net.toClient(client, {type = "sensorWatch", clientId = id, serverSession = session, bootId = client.bootId, watches = list})
                    client.sensorSignature, client.sensorSent = signature, now
                end
                for side, set in pairs(client.sampleParts or {}) do
                    for target, part in pairs(set) do if now - part.time > 10 then set[target] = nil end end
                end
                for side, readings in pairs(client.readings or {}) do
                    for target in pairs(readings) do if not wanted(id, side, target) then readings[target] = nil end end
                end
                for side, part in pairs(client.catalogParts or {}) do if now - part.time > 10 then client.catalogParts[side] = nil end end
            end
        end
    end
    return hub
end
return Hub
