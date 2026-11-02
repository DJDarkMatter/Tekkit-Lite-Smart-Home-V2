-- Generic sensor bridge. Old OCS peripherals return queue IDs followed by
-- ocs_success/ocs_error events: no yielding through Lua 5.1 pcall is needed.
local Data = dofile("lib_sensor_data.lua")
local Sensor = {}
local sides = {"top", "bottom", "left", "right", "front", "back"}
function Sensor.new(net, config, logger)
    local log = logger or print
    local client = {connected = false, nonce = 0, lastAnnounce = -math.huge, lastServer = 0, ports = {}, watches = {}, sequence = 0}
    local pending, scanAt, cursor = nil, -math.huge, 0
    local expiredIds = {} -- OCS reuses small IDs independently on each sensor.
    local inspections = {}
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
        local raw, profile
        if not err then
            local port = client.ports[watch.side]
            if port and Data.cardKind(port.card) == "ae" then
                profile = watch.profile
                if profile == "ae_storage" then data = Data.aeSummary(data)
                elseif profile == "ae_items" then data,err = Data.aeItems(data) end
            end
            if not err then data, err = Data.clean(data, profile) end
            if type(data) ~= "table" then err = err or "Target not found" end
            if not err then raw = textutils.serialize(data); if #raw > Data.chunkSize * Data.parts(profile) then err = "Reading exceeds network limit"; raw = nil end end
        end
        raw = raw or ""
        local port = client.ports[watch.side]
        if not err and watch.lastRaw == raw and watch.lastFull and os.clock() - watch.lastFull < 5 then
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, profile = profile, status = "ok", part = 1, parts = 1, data = "", unchanged = true, baseSequence = watch.lastFullSequence})
            return
        end
        if not err then watch.lastRaw, watch.lastFull, watch.lastFullSequence = raw, os.clock(), client.sequence else watch.lastRaw = nil end
        local parts = math.max(1, math.ceil(#raw / Data.chunkSize))
        for part = 1, parts do
            send({type = "sensorSample", sequence = client.sequence, side = watch.side, target = watch.target,
                card = port and port.card, profile = profile, status = err and "error" or "ok", error = err and tostring(err):sub(1, 160),
                part = part, parts = parts, data = raw:sub((part - 1) * Data.chunkSize + 1, part * Data.chunkSize)})
        end
    end
    local function complete(job, value, err)
        local port = client.ports[job.side]
        if job.kind == "inspect" then
            if not port or port.generation ~= job.generation or port.card ~= job.watch.card then
                job.callback(nil, "Sensor or card changed during inspection")
            else job.callback(value, err) end
            return
        end
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
            if previousCard ~= port.card or previousStatus ~= port.status then log(port.side .. ": " .. (port.card or port.error or port.status)) end
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
            if previousCount ~= #port.targets then log(port.side .. ": " .. #port.targets .. " targets") end
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
    local function start(port, kind, method, watch, callback)
        local job = {side = port.side, generation = port.generation, kind = kind, watch = watch, callback = callback, deadline = os.clock() + config.requestTimeout}
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
                log("Connected to OS computer " .. client.serverId)
                for _, port in pairs(client.ports) do catalog(port) end
            end
        elseif message.type == "sensorWatch" and client.connected and message.sender == client.serverId
            and message.serverSession == client.serverSession and message.bootId == config.bootId
            and type(message.watches) == "table" and #message.watches <= 128 then
            local previous, watches, seen = client.watches, {}, {}
            for _, address in ipairs(message.watches) do
                if not Data.address(address) or address.clientId ~= config.clientId
                    or not Data.validProfile(address.profile) then return end
                seen[address.side] = seen[address.side] or {}
                if not seen[address.side][address.target] then
                    local watch = {side = address.side, target = address.target, card = address.card, profile = address.profile, nextRead = 0}
                    for _, old in ipairs(previous) do
                        if old.side == watch.side and old.target == watch.target and old.card == watch.card and old.profile == watch.profile then
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
    -- Read-only local inspections share the same legacy OCS event/timeout queue.
    function client.inspectTarget(side, target, callback)
        if type(callback) ~= "function" or not Data.string(target, 128) or #inspections >= 16 then
            return false, "Invalid or excessive inspection request"
        end
        local port = client.ports[side]
        if not port or port.status ~= "ok" or not port.card then return false, "Sensor or card unavailable" end
        inspections[#inspections+1] = {watch={side=side,target=target,card=port.card},callback=callback}
        return true
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
                        log("Sensor detected: " .. side)
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
        if #inspections > 0 then
            local request = table.remove(inspections, 1)
            local port = client.ports[request.watch.side]
            if port and port.status == "ok" and port.card == request.watch.card then
                start(port, "inspect", "getTargetDetails", request.watch, request.callback)
            else request.callback(nil, "Sensor or card unavailable") end
            return
        end
        if not client.connected then return end
        for _ = 1, #client.watches do
            cursor = cursor % #client.watches + 1
            local watch = client.watches[cursor]
            if now >= watch.nextRead then
                watch.nextRead = now + (watch.profile == "ae_items" and math.max(2, config.pollInterval) or config.pollInterval)
                local port = client.ports[watch.side]
                if port and port.status == "ok" and port.card == watch.card then start(port, "sample", "getTargetDetails", watch)
                else sample(watch, nil, "Sensor or card unavailable") end
                return
            end
        end
    end
    return client
end
-- Standalone report mode: never joins the wireless network, changes startup or
-- calls machine setters. Only getType/getMethods and the three OCS getters run.
function Sensor.inspect(selectedSide, selectedTarget)
    local sideSet = {top=true,bottom=true,left=true,right=true,front=true,back=true}
    assert(selectedSide == nil or selectedSide == "all" or sideSet[selectedSide], "Choose all or a sensor side")
    assert(not selectedTarget or sideSet[selectedSide] and Data.string(selectedTarget,128), "Specify SIDE before an exact TARGET")
    local storage = dofile("lib_storage.lua")
    local path, limit = "diagnostics_sensor.txt", 131072
    local report = {version=1,computerId=os.getComputerID(),started=os.clock(),mode="read-only local sensor inspection",
        selection=selectedSide or "mass_fabricators",target=selectedTarget,peripherals={},ports={},samples={}}
    if type(os.version) == "function" then local ok,value=pcall(os.version); if ok then report.craftOS=tostring(value):sub(1,128) end end
    for _,side in ipairs(sides) do
        local kind=peripheral.getType(side)
        local entry={side=side,type=kind or "none",methods={}}
        if kind and type(peripheral.getMethods)=="function" then
            local ok,methods=pcall(peripheral.getMethods,side)
            if ok and type(methods)=="table" then
                local names={}; for _,name in pairs(methods) do if type(name)=="string" then names[#names+1]=name:sub(1,64) end end
                table.sort(names)
                for i=1,math.min(32,#names) do entry.methods[i]=names[i] end
                entry.methodsOmitted=math.max(0,#names-32)
            else entry.methodsError=tostring(methods):sub(1,160) end
        elseif kind then entry.methodsError="peripheral.getMethods is unavailable" end
        report.peripherals[#report.peripherals+1]=entry
    end
    local net={config={},ensureModem=function() return false end}
    local config={clientId="inspection",bootId="inspection",requestTimeout=4,discoveryInterval=3600,announceInterval=3600,timeout=7200,pollInterval=1}
    local client=Sensor.new(net,config,function() end)
    local function save()
        while #textutils.serialize(report)>limit do
            local removed=false
            for i=#report.samples,1,-1 do
                for j=#report.samples[i].readings,1,-1 do
                    local reading=report.samples[i].readings[j]
                    if reading.data~=nil then
                        reading.data,reading.status,reading.error,reading.partial=nil,"error","Report size limit; reading omitted",true
                        removed=true; break
                    end
                end
                if removed then break end
            end
            if not removed then
                for i=#report.ports,1,-1 do
                    local port=report.ports[i]
                    if #port.targets>0 then table.remove(port.targets); port.targetsOmitted=port.targetsOmitted+1; removed=true; break end
                end
            end
            assert(removed,"Diagnostic metadata exceeds 128 KiB")
            report.truncated=true
        end
        local ok,err=storage.save(path,report); assert(ok,"Cannot save report: "..tostring(err))
    end
    local function runUntil(done,seconds)
        local deadline=os.clock()+seconds
        while not done() and os.clock()<deadline do
            client.tick(os.clock())
            if done() then return true end
            local timer=os.startTimer(0.1)
            repeat
                local event={os.pullEvent()}
                client.handleEvent(unpack(event))
                if done() then return true end
            until event[1]=="timer" and event[2]==timer
        end
        return done()
    end
    print("Read-only inspection; normal sensor service is paused")
    print("Discovering cards and targets...")
    save() -- Preserve an initial report even if a later request is interrupted.
    local discovered=runUntil(function()
        for _,side in ipairs(sides) do
            if peripheral.getType(side)=="sensor" then
                local port=client.ports[side]
                if not port or port.status=="scanning" or port.card and port.targetAt<=os.clock() then return false end
            end
        end
        return true
    end,30)
    report.discoveryComplete=discovered
    local selected,shown={},0
    for _,side in ipairs(sides) do
        local port=client.ports[side]
        if port then
            local entry={side=side,card=port.card,status=port.status,error=port.error,targets={},targetCount=#port.targets}
            for _,target in ipairs(port.targets) do
                if shown<64 then entry.targets[#entry.targets+1]=target; shown=shown+1 end
                local identity=((target.label or "").." "..(target.rawName or "").." "..(target.type or "")):lower():gsub("[%s_.%-]","")
                local matches = selectedTarget and side==selectedSide and target.key==selectedTarget
                    or not selectedTarget and (selectedSide=="all" or selectedSide==side or not selectedSide and identity:find("massfab",1,true))
                if matches then selected[#selected+1]={side=side,card=port.card,target=target} end
            end
            entry.targetsOmitted=entry.targetCount-#entry.targets
            report.ports[#report.ports+1]=entry
        end
    end
    report.matchedTargets,report.sampleLimit=#selected,32
    report.targetsOmitted=math.max(0,#selected-32)
    save()
    local function cleanReading(value)
        if type(value)~="table" then return nil,"Sensor returned no details table" end
        local clean,err=Data.clean(value)
        if clean and #textutils.serialize(clean)<=16384 then return clean end
        -- Keep scalar counters discoverable even if a catalog/nested value is huge.
        local preview,keys={},{}
        for key in pairs(value) do if type(key)=="string" and #key<=96 then keys[#keys+1]=key end end
        table.sort(keys,function(a,b)
            local function rank(key) return (Data.number(value[key]) or type(value[key])=="boolean") and 0 or 1 end
            if rank(a)~=rank(b) then return rank(a)<rank(b) end
            return a<b
        end)
        for i=1,math.min(64,#keys) do
            local key=keys[i]; local item=value[key]
            if type(item)=="string" then preview[key]=item:sub(1,256)
            elseif type(item)=="boolean" or Data.number(item) then preview[key]=item end
        end
        return preview,err or "Full details exceeded 16 KiB; scalar preview only",true
    end
    for i=1,math.min(32,#selected) do
        local source=selected[i]
        -- Old CraftOS rejects a table appearing twice, even without a cycle.
        -- Catalog and sample metadata need independent copies, including Position.
        report.samples[i]={side=source.side,card=source.card,target=assert(Data.clean(source.target)),readings={}}
    end
    -- Two dated samples expose changing counters without assuming any rate field
    -- means real production. The report never samples a GUI or the TAB screen.
    for pass=1,2 do
        if pass==2 then local due=os.clock()+2; runUntil(function() return os.clock()>=due end,3) end
        for i=1,#report.samples do
            local entry=report.samples[i]
            local reading={requestedAt=os.clock()}; entry.readings[pass]=reading
            local done=false
            print("Sample "..pass..": "..entry.side.." / "..entry.target.key)
            local ok,err=client.inspectTarget(entry.side,entry.target.key,function(value,errorText)
                reading.receivedAt=os.clock()
                if errorText then reading.status,reading.error="error",tostring(errorText):sub(1,160)
                else
                    reading.data,reading.error,reading.partial=cleanReading(value)
                    reading.status=not reading.data and "error" or reading.partial and "partial" or "ok"
                end
                done=true
            end)
            if not ok then reading.status,reading.error,done="error",err,true end
            if not runUntil(function() return done end,6) then reading.status,reading.error="error","Inspection did not complete" end
            if #textutils.serialize(report)>limit-1024 then
                reading.data,reading.status,reading.error,reading.partial=nil,"error","Report size limit; reading omitted",true
                report.truncated=true
            end
            save()
        end
    end
    report.finished=os.clock(); save()
    print("Saved "..path.." ("..#report.samples.." targets, two samples each)")
    if #selected==0 then print(selectedSide and "No matching target. See card/target discovery in the report." or "No Mass Fabricator found. See card/target discovery in the report.") end
    if report.targetsOmitted>0 then print("Target limit reached; inspect individual sides/targets for the remainder") end
    print("Share with: pastebin put "..path)
    print("Then reboot to resume the normal sensor client")
    return report
end
return Sensor
