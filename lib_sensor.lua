-- Generic sensor bridge. Old OCS peripherals return queue IDs followed by
-- ocs_success/ocs_error events: no yielding through Lua 5.1 pcall is needed.
local Data = dofile("lib_sensor_data.lua")
local Sensor = {}
local sides = {"top", "bottom", "left", "right", "front", "back"}
function Sensor.new(net, config)
    local client = {connected = false, nonce = 0, lastAnnounce = -math.huge, lastServer = 0, ports = {}, watches = {}, sequence = 0}
    local pending, scanAt, cursor = nil, -math.huge, 0
    local expiredIds = {} -- OCS reuses small IDs independently on each sensor.
    local function send(message)
        if not client.connected then return end
        message.clientId, message.serverSession, message.bootId = config.clientId, client.serverSession, config.bootId
        net.send(net.config.channel, client.serverId, message)
    end
    local function catalog(port)
        client.sequence = client.sequence + 1
        local count = math.max(1, math.ceil(#(port.targets or {}) / 64))
        for part = 1, count do
            local targets = {}
            for i = (part - 1) * 64 + 1, math.min(part * 64, #(port.targets or {})) do targets[#targets + 1] = port.targets[i] end
            send({type = "sensorCatalog", sequence = client.sequence, side = port.side, card = port.card,
                status = port.status, error = port.error, part = part, parts = count, targets = targets, truncated = port.truncated == true})
        end
    end
    local function sample(watch, data, err)
        client.sequence = client.sequence + 1
        local raw
        if not err then
            data, err = Data.clean(data)
            if type(data) ~= "table" then err = err or "Target not found" end
            if not err then raw = textutils.serialize(data); if #raw > Data.chunkSize * Data.maxParts then err = "Reading exceeds network limit"; raw = nil end end
        end
        raw = raw or ""
        local port = client.ports[watch.side]
        if not err and watch.lastRaw == raw and watch.lastFull and os.clock() - watch.lastFull < 5 then
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, status = "ok", part = 1, parts = 1, data = "", unchanged = true, baseSequence = watch.lastFullSequence})
            return
        end
        if not err then watch.lastRaw, watch.lastFull, watch.lastFullSequence = raw, os.clock(), client.sequence else watch.lastRaw = nil end
        local parts = math.max(1, math.ceil(#raw / Data.chunkSize))
        for part = 1, parts do
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, status = err and "error" or "ok", error = err and tostring(err):sub(1, 160),
                part = part, parts = parts, data = raw:sub((part - 1) * Data.chunkSize + 1, part * Data.chunkSize)})
        end
    end
    local function complete(job, value, err)
        local port = client.ports[job.side]
        if not port or port.generation ~= job.generation then return end
        if job.kind == "name" then
            local previousCard, previousStatus = port.card, port.status
            port.nameAt = os.clock() + config.discoveryInterval
            if not Data.string(value, 128) or err then
                port.card, port.targets, port.status, port.error = nil, {}, "no_card", tostring(err or "No valid sensor card"):sub(1, 160)
            else
                if port.card ~= value then
                    port.card, port.targets, port.targetAt = value, {}, -math.huge
                    for _, watch in ipairs(client.watches) do if watch.side == port.side then watch.nextRead = 0 end end
                end
                port.status, port.error = "ok", nil
            end
            if previousCard ~= port.card or previousStatus ~= port.status then print(port.side .. ": " .. (port.card or port.error or port.status)) end
            if previousCard ~= port.card or previousStatus ~= port.status then catalog(port) end
        elseif job.kind == "targets" then
            local previousCount = #(port.targets or {})
            port.targetAt = os.clock() + config.discoveryInterval
            if type(value) ~= "table" or err then
                port.targets, port.status, port.error = {}, "error", tostring(err or "Invalid target list"):sub(1, 160)
            else
                local keys = {}
                for key in pairs(value) do if Data.string(key, 128) then keys[#keys + 1] = key end end
                table.sort(keys)
                port.targets, port.truncated = {}, #keys > Data.maxTargets
                for i = 1, math.min(#keys, Data.maxTargets) do port.targets[#port.targets + 1] = Data.target(keys[i], value[keys[i]]) end
                port.status, port.error = "ok", nil
            end
            if previousCount ~= #port.targets then print(port.side .. ": " .. #port.targets .. " targets") end
            catalog(port)
        else
            local watch = job.watch
            if watch and watch.card == port.card then sample(watch, value, err) end
        end
    end
    local function finishCall(job, ok, value)
        if not ok then pending = nil; complete(job, nil, value)
        elseif coroutine.status(job.thread) ~= "dead" then job.filter = value; pending = job
        elseif type(value) == "number" then
            if value < 0 then pending = nil; complete(job, nil, "Sensor rejected request")
            elseif expiredIds[value] then pending = nil; complete(job, nil, "Expired sensor response ID; retrying")
            else job.queueId, job.thread, job.filter = value, nil, nil; pending = job end
        else pending = nil; complete(job, value) end
    end
    local function start(port, kind, method, watch)
        local job = {side = port.side, generation = port.generation, kind = kind, watch = watch, deadline = os.clock() + config.requestTimeout}
        job.thread = coroutine.create(function()
            if watch then return port.device[method](watch.target) end
            return port.device[method]()
        end)
        finishCall(job, coroutine.resume(job.thread))
    end
    function client.handleEvent(event, ...)
        local values = {...}
        local job = pending
        if not job then return end
        if job.queueId ~= nil then
            if (event == "ocs_success" or event == "ocs_error") and values[1] == job.queueId then
                pending = nil
                complete(job, event == "ocs_success" and values[2] or nil, event == "ocs_error" and tostring(values[2]) or nil)
            end
        elseif not job.filter or event == job.filter then finishCall(job, coroutine.resume(job.thread, event, unpack(values))) end
    end
    function client.handle(message, now)
        if message.clientId ~= config.clientId then return end
        if message.type == "welcome" then
            if message.nonce ~= client.nonce or type(message.serverSession) ~= "string" then return end
            if client.connected and message.sender ~= client.serverId then return end
            local changed = not client.connected or client.serverSession ~= message.serverSession
            client.connected, client.serverId, client.serverSession, client.lastServer = true, message.sender, message.serverSession, now
            if changed then
                client.watches = {}
                print("Connected to OS computer " .. client.serverId)
                for _, port in pairs(client.ports) do catalog(port) end
            end
        elseif message.type == "sensorWatch" and client.connected and message.sender == client.serverId
            and message.serverSession == client.serverSession and message.bootId == config.bootId
            and type(message.watches) == "table" and #message.watches <= 128 then
            local previous, watches, seen = client.watches, {}, {}
            for _, address in ipairs(message.watches) do
                if not Data.address(address) or address.clientId ~= config.clientId then return end
                seen[address.side] = seen[address.side] or {}
                if not seen[address.side][address.target] then
                    local watch = {side = address.side, target = address.target, card = address.card, nextRead = 0}
                    for _, old in ipairs(previous) do
                        if old.side == watch.side and old.target == watch.target and old.card == watch.card then
                            watch.nextRead, watch.lastRaw, watch.lastFull, watch.lastFullSequence = old.nextRead, old.lastRaw, old.lastFull, old.lastFullSequence
                            break
                        end
                    end
                    watches[#watches + 1], seen[address.side][address.target] = watch, true
                end
            end
            client.watches, client.lastServer = watches, now
        end
    end
    function client.tick(now)
        if not net.ensureModem() or client.connected and now - client.lastServer >= config.timeout then
            client.connected, client.watches = false, {}
        end
        if now >= scanAt then
            scanAt = now + 1
            for _, side in ipairs(sides) do
                local port = client.ports[side]
                if peripheral.getType(side) == "sensor" then
                    if not port or port.status == "detached" then
                        client.ports[side] = {side = side, device = peripheral.wrap(side), targets = {}, status = "scanning",
                            generation = (port and port.generation or 0) + 1, nameAt = 0, targetAt = 0}
                        print("Sensor detected: " .. side)
                    end
                elseif port and port.status ~= "detached" then
                    port.status, port.card, port.targets, port.error = "detached", nil, {}, "Sensor detached"
                    port.generation = port.generation + 1
                    catalog(port)
                end
            end
        end
        if net.modem and now - client.lastAnnounce >= config.announceInterval then
            client.nonce, client.lastAnnounce = client.nonce + 1, now
            net.toServer({type = "announce", clientType = "sensor", sensorProtocol = Data.protocol,
                clientId = config.clientId, nonce = client.nonce, bootId = config.bootId, pollInterval = config.pollInterval})
        end
        if pending and now >= pending.deadline then
            local job = pending
            if job.queueId ~= nil then expiredIds[job.queueId] = true end
            pending = nil; complete(job, nil, "Sensor request timed out")
        end
        if pending then return end
        -- Discovery and samples share a bounded queue; modem events keep flowing.
        for _, side in ipairs(sides) do
            local port = client.ports[side]
            if port and port.status ~= "detached" then
                if now >= port.nameAt then start(port, "name", "getSensorName"); return end
                if port.card and now >= port.targetAt then start(port, "targets", "getTargets"); return end
            end
        end
        if not client.connected then return end
        for _ = 1, #client.watches do
            cursor = cursor % #client.watches + 1
            local watch = client.watches[cursor]
            if now >= watch.nextRead then
                watch.nextRead = now + config.pollInterval
                local port = client.ports[watch.side]
                if port and port.status == "ok" and port.card == watch.card then start(port, "sample", "getTargetDetails", watch)
                else sample(watch, nil, "Sensor or card unavailable") end
                return
            end
        end
    end
    return client
end
return Sensor
