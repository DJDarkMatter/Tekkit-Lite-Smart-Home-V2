-- Central state, app lifecycle, desktops and logical IO routing. No redstone here.
local Server = {}
local Picker = dofile("lib_io_picker.lua")
local Desktop = dofile("lib_desktop.lua")
local Gui = dofile("lib_gui.lua")
local Settings = dofile("lib_settings.lua")
local SensorHub = dofile("lib_sensor_server.lua")
local SensorPicker = dofile("lib_sensor_picker.lua")
local systemColours = {background = {field = "backgroundColour", title = "Background"},
    windowBorder = {field = "windowBorderColour", title = "Window border"}, taskbar = {field = "taskbarColour", title = "Taskbar"}}
local sideSet = {top = true, bottom = true, left = true, right = true, front = true, back = true}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function colour(value)
    if not integer(value, 1, 32768) then return false end
    while value > 1 do
        if value % 2 ~= 0 then return false end
        value = value / 2
    end
    return true
end
local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
-- Window UI state is plain bounded data, independent of sensor caches and app
-- business state. Do not persist frame hit maps or rendering styles.
local function viewSnapshot(value)
    local seen, count = {}, 0
    local function clean(item, depth)
        count = count + 1
        if count > 2048 or depth > 8 then error("Window UI state is too large", 0) end
        local kind = type(item)
        if kind == "boolean" or kind == "nil" then return item end
        if kind == "number" then return item == item and math.abs(item) < math.huge and item or nil end
        if kind == "string" then assert(#item <= 4096, "Window UI text is too large"); return item end
        if kind ~= "table" or seen[item] then return nil end
        seen[item] = true
        local result = {}
        for key, child in pairs(item) do
            if (type(key) == "string" and #key <= 96 or integer(key, 1, 2147483646)) and key ~= "hits" and key ~= "styles" then
                result[key] = clean(child, depth + 1)
            end
        end
        seen[item] = nil
        return result
    end
    local ok, result = pcall(clean, value, 0)
    return ok and type(result) == "table" and result or {}
end

local function wireGroup(groups, mapping)
    groups[mapping.clientId] = groups[mapping.clientId] or {}
    local sides = groups[mapping.clientId]
    sides[mapping.side] = sides[mapping.side] or {}
    local key = mapping.color or "digital"
    sides[mapping.side][key] = sides[mapping.side][key] or {}
    return sides[mapping.side][key]
end
local function currentWires(mappings, values)
    local groups = {}
    for name, mapping in pairs(mappings) do
        local group = wireGroup(groups, mapping)
        group.value = group.value == true or values[name] == true
    end
    return groups
end
local function sameSnapshot(a, b)
    for side, value in pairs(a) do
        if not b[side] or value.bundled ~= b[side].bundled or value.digital ~= b[side].digital then return false end
    end
    for side in pairs(b) do if not a[side] then return false end end
    return true
end

local function validState(value)
    for _, key in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if value[key] ~= nil and type(value[key]) ~= "table" then return false end
    end
    for name, mapping in pairs(value.outputMap or {}) do
        if type(name) ~= "string" or type(mapping) ~= "table" or type(mapping.clientId) ~= "string"
            or not sideSet[mapping.side] or (mapping.color ~= nil and not colour(mapping.color)) then return false end
    end
    for id, entries in pairs(value.managedSides or {}) do
        if type(id) ~= "string" or type(entries) ~= "table" then return false end
        for side, enabled in pairs(entries) do if not sideSet[side] or enabled ~= true then return false end end
    end
    return true
end

local function validApp(app)
    if type(app) ~= "table" then return false end
    if app.title ~= nil and (type(app.title) ~= "string" or #app.title < 1 or #app.title > 64) then return false end
    for _, key in ipairs({"minWidth", "maxWidth", "minHeight", "maxHeight", "preferredWidth", "preferredHeight"}) do
        if app[key] ~= nil and not integer(app[key], 1, 512) then return false end
    end
    for _,key in ipairs({"backgroundService","fullscreenOnly","transientWindow","hideTaskbar","handlesFullscreenCorner"}) do
        if app[key]~=nil and type(app[key])~="boolean" then return false end
    end
    if app.animationInterval~=nil and (type(app.animationInterval)~="number" or app.animationInterval~=app.animationInterval
        or app.animationInterval<0.1 or app.animationInterval>1) then return false end
    for _, key in ipairs({"init", "shutdown", "background", "render", "handleTouch", "handleIOSelection", "handleSensorSelection", "handleNotification", "onOpen", "onClose"}) do
        if app[key] ~= nil and type(app[key]) ~= "function" then return false end
    end
    return (not app.maxWidth or app.maxWidth >= (app.minWidth or 8))
        and (not app.maxHeight or app.maxHeight >= (app.minHeight or 2))
end

function Server.new(net, storage, config, logger)
    local log = logger or print
    local loaded, source = storage.load(config.saveFile, validState)
    local state = loaded or {}
    for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if type(state[name]) ~= "table" then state[name] = {} end
    end
    -- Older/manual saves may contain aliases with separate values. Retain the
    -- previously powered mask, then keep every reference to each wire in sync.
    local restoredWires = currentWires(state.outputMap, state.outputs)
    for name, mapping in pairs(state.outputMap) do state.outputs[name] = wireGroup(restoredWires, mapping).value end
    state.appearance = type(state.appearance) == "table" and state.appearance or {}
    if not colour(state.appearance.backgroundColour) then state.appearance.backgroundColour = 2048 end
    if not colour(state.appearance.windowBorderColour) then state.appearance.windowBorderColour = 128 end
    if not colour(state.appearance.taskbarColour) then state.appearance.taskbarColour = 128 end
    if type(state.appearance.appColours) ~= "table" then state.appearance.appColours = {} end
    for name, value in pairs(state.appearance.appColours) do
        if type(name) ~= "string" or not colour(value) then state.appearance.appColours[name] = nil end
    end
    state.appStates["@settings"] = type(state.appStates["@settings"]) == "table" and state.appStates["@settings"] or {}
    local server = {state = state, monitors = {}, ioClients = {}, sensorClients = {}, relayClients = {}, apps = {},
        systemApps = {["@settings"] = Settings}, gameTime = "?:??", playerOnline = false,
        lastSave = 0, lastTick = os.clock(), views = {}, dialogs = {}, running = {}, notifications = {}, notificationSequence = 0}
    local clientGroups = {io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients, relay = server.relayClients}
    local api, errors = {}, {}
    server.api = api
    api.ui, api.log, api.sharedOutputs, api.sensorProfiles = Gui, log, true, true
    api.aeItemProfiles = true
    local function definition(name) return server.systemApps[name] or server.apps[name] end
    local function invalidateInput(id)
        local monitor = server.monitors[id]
        if monitor then monitor.inputRevision = (monitor.inputRevision or 0) + 1 end
    end
    state.nextWindowId = 1
    local legacyDesktop = (tonumber(state.desktopVersion) or 1) < 2
    for id, win in pairs(state.windows) do
        if not integer(id, 1, 2147483646) or type(win) ~= "table"
            or type(win.appName) ~= "string" or type(win.monitorId) ~= "string" then
            state.windows[id] = nil
        else
            state.nextWindowId = math.max(state.nextWindowId, id + 1)
            win.id, win.order = id, tonumber(win.order) or id
            if not state.appStates[win.appName] and type(win.appState) == "table" then
                state.appStates[win.appName] = win.appState
            end
            win.appState = nil -- App state is shared with its background service.
            server.views[id] = viewSnapshot(win.viewState)
            win.viewState = nil
            if legacyDesktop then win.y = math.max(1, (tonumber(win.y) or 3) - 2) end
        end
    end
    state.desktopVersion = 2
    state.bootCounter = (tonumber(state.bootCounter) or 0) + 1
    server.session = tostring(net.id) .. ":" .. state.bootCounter
    local sensors = SensorHub.new(net, server.sensorClients, server.session)
    server.sensors = sensors
    if source and source ~= config.saveFile then log("Recovered state from " .. source) end
    if not loaded and fs.exists(config.saveFile) then log("Unreadable OS state; starting with defaults") end

    function server.save()
        local saved = {}
        for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides",
            "nextWindowId", "bootCounter", "desktops", "desktopVersion", "appearance"}) do saved[name] = state[name] end
        saved.windows = {}
        for id, win in pairs(state.windows) do
            if not win.transientWindow then
                saved.windows[id] = copy(win)
                saved.windows[id].viewState = viewSnapshot(server.views[id])
            end
        end
        local ok, err = storage.save(config.saveFile, saved)
        if not ok then log("State save failed: " .. tostring(err)) else server.lastSave = os.clock() end
        return ok, err
    end
    api.save = server.save
    api.fullscreenApps = true
    api.fullscreenCornerNavigation = true
    -- App-owned, synchronous upgrade transaction. The transform edits detached
    -- copies; both app namespaces checkpoint together without touching IO maps.
    function api.migrateAppState(from,to,transform)
        if from==to or not server.apps[to] or type(transform)~="function" then return false,"Invalid app migration" end
        local sourceState,targetState=state.appStates[from],state.appStates[to]
        if type(sourceState)~="table" or type(targetState)~="table" then return false,"App state is unavailable" end
        local oldSource,oldTarget=copy(sourceState),copy(targetState)
        local nextSource,nextTarget=copy(sourceState),copy(targetState)
        local ok,accepted,err=pcall(transform,nextSource,nextTarget)
        if not ok or accepted~=true then return false,tostring(ok and err or accepted) end
        local function replace(target,value)
            local keys={}; for key in pairs(target) do keys[#keys+1]=key end
            for _,key in ipairs(keys) do target[key]=nil end
            for key,item in pairs(value) do target[key]=item end
        end
        replace(sourceState,nextSource); replace(targetState,nextTarget)
        ok,err=server.save()
        if not ok then replace(sourceState,oldSource); replace(targetState,oldTarget); return false,err end
        server.notifications[from]=nil
        api.invalidateAppViews(from); api.invalidateAppViews(to)
        return true
    end
    function api.getAppData(name) return copy(state.appStates[name]) end
    function api.invalidateAppViews(name)
        local seen = {}
        for _, win in pairs(state.windows) do
            if win.appName == name and not seen[win.monitorId] then
                invalidateInput(win.monitorId)
                seen[win.monitorId] = true
            end
        end
    end

    function api.getOSSettings()
        return {backgroundMode = "solid", backgroundColour = state.appearance.backgroundColour,
            windowBorderColour = state.appearance.windowBorderColour, taskbarColour = state.appearance.taskbarColour}
    end
    function api.getAppColour(name) return state.appearance.appColours[name] or 2048 end
    local function saveAppearance(change)
        local previous = copy(state.appearance)
        change(state.appearance)
        local ok, err = server.save()
        if not ok then state.appearance = previous end
        return ok, err
    end
    function api.setBackgroundColour(value)
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.backgroundColour = value end)
    end
    function api.setWindowBorderColour(value)
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.windowBorderColour = value end)
    end
    function api.setTaskbarColour(value)
        if not colour(value) then return false, "Choose a CC color" end
        return saveAppearance(function(appearance) appearance.taskbarColour = value end)
    end
    local systemColourSetters = {background = api.setBackgroundColour,
        windowBorder = api.setWindowBorderColour, taskbar = api.setTaskbarColour}
    function api.setAppColour(name, value)
        if not definition(name) or not colour(value) then return false, "Invalid app color" end
        return saveAppearance(function(appearance) appearance.appColours[name] = value end)
    end

    local function appCall(name, hook, ...)
        local app = definition(name)
        if not app or not app[hook] then return true end
        local ok, a, b = pcall(app[hook], ...)
        if not ok then
            local key = name .. "." .. hook
            if errors[key] ~= a then log("App " .. key .. " failed: " .. tostring(a)); errors[key] = a end
        end
        return ok, a, b
    end

    local function isService(app) return app.backgroundService == true or app.render == nil end
    local function hasViews(name)
        for _, win in pairs(state.windows) do if win.appName == name then return true end end
        return false
    end
    local function startApp(name)
        if server.running[name] then return true end
        server.running[name] = true
        local ok, err = appCall(name, "init", state.appStates[name], api, {appName = name})
        if not ok then server.running[name] = nil; return false, err end
        return true
    end
    local function stopApp(name)
        if server.running[name] and not isService(definition(name)) and not hasViews(name) then
            appCall(name, "shutdown", state.appStates[name], api, {appName = name})
            server.running[name] = nil
            server.save()
        end
    end

    local function viewContext(win)
        server.views[win.id] = server.views[win.id] or {}
        return {windowId = win.id, monitorId = win.monitorId, appName = win.appName,
            fullscreen = win.fullscreen == true, view = server.views[win.id]}
    end

    local function updateClock()
        server.worldTime, server.worldDay = nil, nil
        if type(os.time) == "function" then
            local ok, value = pcall(os.time)
            if ok and type(value) == "number" and value >= 0 and value < 24 then
                local minutes = math.floor(value * 60 + 0.000001)
                server.gameTime = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
                server.clockSource, server.worldTime = "computer", value
                if type(os.day) == "function" then
                    local dayOK, day = pcall(os.day)
                    if dayOK and integer(day, 0, 2147483647) then server.worldDay = day end
                end
                return
            end
        end
        for _, id in ipairs(sortedKeys(server.sensorClients)) do
            local sensor = server.sensorClients[id]
            if sensor.online and type(sensor.values.gameTime) == "string" then
                server.gameTime, server.clockSource = sensor.values.gameTime:sub(1, 32), "sensor"
                return
            end
        end
        server.gameTime, server.clockSource = "?:??", "unavailable"
    end
    updateClock()

    local function outputSnapshot(clientId)
        local snapshot = {}
        for side in pairs(state.managedSides[clientId] or {}) do
            snapshot[side] = {bundled = 0, digital = false}
        end
        for name, mapping in pairs(state.outputMap) do
            if mapping.clientId == clientId and sideSet[mapping.side] then
                local values = snapshot[mapping.side] or {bundled = 0, digital = false}
                snapshot[mapping.side] = values
                if state.outputs[name] == true then
                    if mapping.color then values.bundled = colors.combine(values.bundled, mapping.color)
                    else values.digital = true end
                end
            end
        end
        return snapshot
    end

    function server.syncIO(clientId, changed)
        local client = server.ioClients[clientId]
        if not client then return end
        if changed then client.revision = client.revision + 1 end
        if not client.online then return end
        local snapshot = {}
        for side, values in pairs(outputSnapshot(clientId)) do
            if not client.capabilities[side] then
                log("IO " .. clientId .. ": mapped side " .. side .. " is unavailable")
            else snapshot[side] = values end
        end
        -- A snapshot ACK covers a whole revision, but unrelated wires retain
        -- their earlier confirmation. Requiring the latest client revision for
        -- every output made an entire board flash pending after one toggle.
        client.wireRevisions = client.wireRevisions or {}
        for side, wanted in pairs(snapshot) do
            local previous = client.outputSnapshot and client.outputSnapshot[side]
            local required = client.wireRevisions[side] or {}
            client.wireRevisions[side] = required
            if not previous or previous.digital ~= wanted.digital or required.digital == nil then
                required.digital = client.revision
            end
            for bit = 0, 15 do
                local color = 2 ^ bit
                if not previous or math.floor(previous.bundled / color) % 2 ~= math.floor(wanted.bundled / color) % 2
                    or required[color] == nil then required[color] = client.revision end
            end
        end
        client.outputSnapshot = copy(snapshot)
        net.toClient(client, {type = "ioCommand", command = "syncOutputs", clientId = clientId,
            serverSession = server.session, revision = client.revision, outputs = snapshot})
        client.lastSent = os.clock()
    end

    function api.getOutput(name) return state.outputs[name] == true end
    -- One checkpoint for a whole panel, reroute, removal or group action. App
    -- state changed by the caller is included in that same durable checkpoint.
    function api.updateOutputs(changes)
        if type(changes) ~= "table" then return false, "Expected output changes" end
        local count = 0
        for index in pairs(changes) do
            if not integer(index, 1, #changes) then return false, "Expected a dense array of output changes" end
            count = count + 1
        end
        if count ~= #changes then return false, "Expected a dense array of output changes" end
        local mappings, values, managed = copy(state.outputMap), copy(state.outputs), copy(state.managedSides)
        local seen, affected = {}, {}
        local oldWires = currentWires(state.outputMap, state.outputs)
        local function remember(mapping)
            if not mapping then return end
            affected[mapping.clientId] = true
            managed[mapping.clientId] = managed[mapping.clientId] or {}
            managed[mapping.clientId][mapping.side] = true
        end
        for _, change in ipairs(changes) do
            if type(change) ~= "table" or type(change.name) ~= "string" or not change.name:match("^[%w_-]+$")
                or seen[change.name] then return false, "Invalid or repeated output name" end
            if change.remove ~= nil and type(change.remove) ~= "boolean"
                or change.clientId == nil and (change.side ~= nil or change.color ~= nil or change.initialValue ~= nil)
                or change.initialValue ~= nil and type(change.initialValue) ~= "boolean"
                or change.initialValue ~= nil and change.value ~= nil then return false, "Invalid output change" end
            seen[change.name] = change
            remember(mappings[change.name])
            if change.remove == true then
                mappings[change.name], values[change.name] = nil, nil
            else
                local mapping = mappings[change.name]
                if change.clientId ~= nil then
                    if type(change.clientId) ~= "string" or change.clientId == "" or not sideSet[change.side]
                        or (change.color ~= nil and not colour(change.color)) then return false, "Invalid output mapping" end
                    mapping = {clientId = change.clientId, side = change.side, color = change.color}
                    local client = server.ioClients[mapping.clientId]
                    if client and client.online and not client.capabilities[mapping.side] then
                        return false, "That side is unavailable (possibly occupied by the modem)"
                    end
                    mappings[change.name] = mapping
                end
                if not mapping then return false, "Unknown output: " .. change.name end
                if change.value ~= nil then
                    if type(change.value) ~= "boolean" then return false, "Output value must be boolean" end
                end
                remember(mapping)
            end
        end
        local wires, groups = {}, {}
        for _, name in ipairs(sortedKeys(mappings)) do
            local mapping = mappings[name]
            local group = wireGroup(wires, mapping)
            if not group.names then
                group.names, group.previous = {}, wireGroup(oldWires, mapping).value
                groups[#groups + 1] = group
            end
            group.names[#group.names + 1] = name
            local change = seen[name]
            if change and change.value ~= nil then
                if group.wanted ~= nil and group.wanted ~= change.value then return false, "Conflicting values for a shared wire" end
                group.wanted = change.value
            elseif change and change.initialValue ~= nil and group.previous == nil then
                if group.initial ~= nil and group.initial ~= change.initialValue then return false, "Conflicting initial values for a shared wire" end
                group.initial = change.initialValue
            end
            group.fallback = group.fallback == true or values[name] == true
        end
        for _, group in ipairs(groups) do
            local wanted = group.wanted
            if wanted == nil then wanted = group.previous end
            if wanted == nil then wanted = group.initial end
            if wanted == nil then wanted = group.fallback end
            for _, name in ipairs(group.names) do values[name] = wanted end
        end
        local before = {}
        for id in pairs(affected) do before[id] = outputSnapshot(id) end
        local previousMap, previousValues, previousManaged = state.outputMap, state.outputs, state.managedSides
        state.outputMap, state.outputs, state.managedSides = mappings, values, managed
        local ok, err = server.save()
        if not ok then
            state.outputMap, state.outputs, state.managedSides = previousMap, previousValues, previousManaged
            return false, err
        end
        for _, id in ipairs(sortedKeys(affected)) do server.syncIO(id, not sameSnapshot(before[id], outputSnapshot(id))) end
        return true
    end
    function api.mapOutput(name, clientId, side, color, initialValue)
        -- Binding another reference adopts an existing wire's state. An
        -- explicit rebind to the same address can still set its initial intent.
        if clientId == nil then return false, "Invalid output mapping" end
        local old = state.outputMap[name]
        local change = {name = name, clientId = clientId, side = side, color = color, initialValue = initialValue}
        if old and old.clientId == clientId and old.side == side and old.color == color then
            change.initialValue, change.value = nil, initialValue
        end
        return api.updateOutputs({change})
    end
    function api.setOutput(name, value)
        if type(value) ~= "boolean" then return false, "Output value must be boolean" end
        return api.updateOutputs({{name = name, value = value}})
    end
    function api.getOutputs()
        local result = {}
        for _, name in ipairs(sortedKeys(state.outputMap)) do
            local item = copy(state.outputMap[name])
            local client = server.ioClients[item.clientId]
            item.name, item.value, item.online = name, api.getOutput(name), client and client.online or false
            local required = client and client.wireRevisions and client.wireRevisions[item.side]
            required = required and required[item.color or "digital"]
            item.confirmed = item.online and client.capabilities[item.side]
                and required ~= nil and client.ackedRevision >= required or false
            result[#result + 1] = item
        end
        return result
    end
    function api.getInput(clientId, side)
        local client = server.ioClients[clientId]
        if client and client.online then return copy(client.inputs[side]) end
    end
    function api.readInput(address)
        if type(address) ~= "table" or type(address.clientId) ~= "string" or not sideSet[address.side]
            or (address.color ~= nil and not colour(address.color)) then return nil, "Input not configured" end
        local reading = api.getInput(address.clientId, address.side)
        if not reading then return nil, "Input offline" end
        if address.color then return math.floor(reading.value / address.color) % 2 == 1 end
        return reading.digital
    end
    function api.getIOClients()
        local result = {}
        for _, id in ipairs(sortedKeys(server.ioClients)) do
            local client = server.ioClients[id]
            result[#result + 1] = {id = id, online = client.online, computerId = client.computerId,
                sides = sortedKeys(client.capabilities or {})}
        end
        return result
    end
    function api.pickIO(windowId, key, direction, current)
        local win = state.windows[windowId]
        if not win or type(key) ~= "string" or (direction ~= "input" and direction ~= "output") then
            return false, "Invalid IO selector request"
        end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "IO settings need a 12x6 content area" end
        local app = definition(win.appName)
        if not app or not app.handleIOSelection then return false, "App has no IO selection handler" end
        server.dialogs[windowId] = Picker.new(key, direction, current)
        invalidateInput(win.monitorId)
        return true
    end
    function api.pickColour(windowId, target)
        local win = state.windows[windowId]
        target = target or "app"
        local option = systemColours[target]
        if not win or (target ~= "app" and not option) then return false, "Invalid color selector" end
        if option and win.appName ~= "@settings" then return false, "Open OS settings for system colors" end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "Color settings need a 12x6 content area" end
        server.dialogs[windowId] = {kind = "colour", target = target,
            current = option and state.appearance[option.field] or api.getAppColour(win.appName)}
        invalidateInput(win.monitorId)
        return true
    end
    function api.getSensor(clientId, name)
        local client = server.sensorClients[clientId]
        if client and client.online then return copy(client.values[name]) end
    end
    api.getSensorClients, api.watchSensor, api.unwatchSensor, api.getSensorReading = sensors.getClients, sensors.watch, sensors.unwatch, sensors.read
    function api.pickSensor(windowId, key, current, kind)
        local win = state.windows[windowId]
        local app = win and definition(win.appName)
        if not win or not app or not app.handleSensorSelection or type(key) ~= "string" then return false, "Invalid sensor selector" end
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then return false, "Sensor settings need a 12x6 content area" end
        server.dialogs[windowId] = SensorPicker.new(key, copy(current), kind)
        invalidateInput(win.monitorId)
        return true
    end
    function api.getClients()
        local result = {}
        for kind, group in pairs(clientGroups) do
            for id, client in pairs(group) do
                local via = {}
                for _, hop in ipairs(client.route or {}) do via[#via + 1] = hop.id end
                result[#result + 1] = {id = id, type = kind, online = client.online, computerId = client.computerId,
                    via = via, hops = #via, route = copy(client.route or {}), forwarded = client.forwarded,
                    channel = client.channel, age = math.max(0, os.clock() - client.lastSeen),
                    width = client.width, height = client.height, revision = client.revision,
                    ackedRevision = client.ackedRevision, touchProtocol = client.touchProtocol}
            end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    function api.getSystem() return {gameTime = server.gameTime, clockSource = server.clockSource,
        worldTime = server.worldTime, worldDay = server.worldDay, playerOnline = server.playerOnline,
        computerId = net.id, networkId = net.config.networkId, modemSide = net.side,
        channel = net.listenChannel, relayChannel = net.config.relayEnabled ~= false and net.relayChannel or nil,
        uptime = os.clock(), session = server.session, lastSaveAge = math.max(0, os.clock()-server.lastSave)} end
    function api.getDiagnostics()
        local result = {system = api.getSystem(), clients = api.getClients(), io = api.getIOClients(),
            sensors = api.getSensorClients(), outputs = api.getOutputs(), apps = {}, windows = {}}
        for _, name in ipairs(sortedKeys(server.apps)) do
            local app = server.apps[name]
            result.apps[#result.apps+1] = {name = name, title = app.title or name,
                running = server.running[name] == true, backgroundService = isService(app)}
        end
        for _, id in ipairs(sortedKeys(state.windows)) do
            local win = state.windows[id]
            result.windows[#result.windows+1] = {id=id, appName=win.appName, title=win.title, monitorId=win.monitorId,
                x=win.x, y=win.y, width=win.width, height=win.height, minimized=win.minimized == true,
                layout=win.layout, fullscreen=win.fullscreen == true}
        end
        return result
    end

    -- Notification contents are runtime mirrors of app-owned durable state.
    -- Apps remove an entry only after their acknowledgement/output checkpoint.
    function api.setNotifications(name, entries)
        local app = definition(name)
        if not app or not app.handleNotification or not server.running[name] or type(entries) ~= "table" then
            return false, "Invalid notification publisher"
        end
        local count, seen, staged = 0, {}, {}
        for index in pairs(entries) do
            if not integer(index, 1, #entries) then return false, "Expected a notification array" end
            count = count + 1
        end
        if count ~= #entries or count > 128 then return false, "Too many notifications" end
        local function label(value, limit)
            return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%c]")
        end
        local old = server.notifications[name] or {}
        local byKey = {}; for _, item in ipairs(old) do byKey[item.key] = item end
        local changed = #old ~= #entries
        for index, item in ipairs(entries) do
            if type(item) ~= "table" or not label(item.key, 96) or seen[item.key]
                or not label(item.title, 64) or not label(item.message, 128) then return false, "Invalid notification" end
            seen[item.key] = true
            local previous = byKey[item.key]
            staged[index] = {appName=name, key=item.key, title=item.title, message=item.message,
                sequence=previous and previous.sequence}
            local before = old[index]
            changed = changed or not before or before.key ~= item.key or before.title ~= item.title or before.message ~= item.message
        end
        if not changed then return true end
        for _, item in ipairs(staged) do
            if not item.sequence then server.notificationSequence = server.notificationSequence+1; item.sequence = server.notificationSequence end
        end
        server.notifications[name] = staged
        for id, monitor in pairs(server.monitors) do
            monitor.notification, monitor.notificationError = nil, nil
            invalidateInput(id)
        end
        return true
    end
    local function firstNotification()
        local first
        for name, entries in pairs(server.notifications) do
            if server.running[name] then
                for _, item in ipairs(entries) do if not first or item.sequence < first.sequence then first = item end end
            end
        end
        return first
    end
    local function notificationModel(item, monitor)
        local available = not monitor.fullscreen and monitor.height >= 5 and monitor.height-1 or monitor.height
        local width = math.min(34, monitor.width)
        local inner = math.max(1,width-2)
        local rows,remaining = {},item.message
        repeat
            local cut = #remaining>inner and remaining:sub(1,inner):match("^.*()%s")
            if cut and cut>1 then rows[#rows+1],remaining = remaining:sub(1,cut-1),remaining:sub(cut+1)
            else rows[#rows+1],remaining = remaining:sub(1,inner),remaining:sub(inner+1) end
        until remaining==""
        local height = math.min(available, math.max(5,math.min(3,#rows)+4))
        local x,y = 1+math.floor((monitor.width-width)/2),1+math.floor((available-height)/2)
        local buttonY = y+math.max(0,height-(height>=3 and 2 or 1))
        local inset = width>=3 and 1 or 0
        return {appName=item.appName,key=item.key,lines=rows,x=x,y=y,width=width,height=height,
            ok={x1=x+inset,x2=x+width-inset-1,y=buttonY}}
    end

    local function windowsFor(monitorId, stable)
        local list = {}
        for _, win in pairs(state.windows) do
            if win.monitorId == monitorId then list[#list + 1] = win end
        end
        table.sort(list, function(a, b) return stable and a.id < b.id or not stable and a.order < b.order end)
        return list
    end
    local function desktopState(id)
        if type(state.desktops[id]) ~= "table" then state.desktops[id] = {scroll = 1} end
        return state.desktops[id]
    end
    local function focus(win)
        local order = 0
        for _, other in pairs(state.windows) do order = math.max(order, other.order) end
        win.order, win.minimized = order + 1, false
        invalidateInput(win.monitorId)
        local monitor, visible = server.monitors[win.monitorId], false
        for _, hit in ipairs(monitor and monitor.taskbar or {}) do
            if hit.action == "window" and hit.id == win.id then visible = true end
        end
        if not visible then
            for index, item in ipairs(windowsFor(win.monitorId, true)) do
                if item.id == win.id then desktopState(win.monitorId).scroll = index; break end
            end
        end
    end
    local function validRelative(value)
        if type(value) ~= "table" then return false end
        for _, key in ipairs({"x", "y", "width", "height"}) do
            if type(value[key]) ~= "number" or value[key] ~= value[key] or value[key] < 0 or value[key] > 1 then return false end
        end
        return value.width > 0 and value.height > 0
    end
    local function fit(win, monitor)
        local app = definition(win.appName)
        if not app then win.doesNotFit = true; return false end
        win.title = app.title or win.appName
        if app.fullscreenOnly then win.fullscreen=true end
        win.hideTaskbar,win.transientWindow=app.hideTaskbar==true or nil,app.transientWindow==true or nil
        if not validRelative(win.relative) then win.relative = nil end
        local rect
        win.fullscreen = win.fullscreen == true or nil
        win.tooSmall = false
        if win.fullscreen then
            win.tooSmall = Desktop.fullscreen(app, monitor) == nil
            rect = {x = 1, y = 1, width = monitor.width, height = monitor.height}
        elseif win.layout and win.layout ~= "normal" then
            rect = Desktop.zone(win.layout, monitor)
            if not Desktop.fits(rect, app, monitor) then win.doesNotFit = true; return false end
        else
            win.layout = "normal"
            rect = Desktop.free(win, win.relative, app, monitor)
            if not rect then win.doesNotFit = true; return false end
            if not win.relative then win.relative = Desktop.relative(rect, monitor) end
        end
        win.x, win.y, win.width, win.height = rect.x, rect.y, rect.width, rect.height
        win.doesNotFit = false
        return true
    end
    local function compatible(name, monitor)
        local app = definition(name)
        if app.fullscreenOnly then return app.render and Desktop.fullscreen(app,monitor)~=nil end
        local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
        return app.render and maxW >= minW and maxH >= minH
    end
    local function discardSmallDialog(win)
        local content = Desktop.contentRect(win)
        if content.width < 12 or content.height < 6 then server.dialogs[win.id] = nil end
    end
    local function fullscreenWindow(id)
        local current
        for _, win in ipairs(windowsFor(id)) do
            if win.fullscreen and not win.minimized and not win.doesNotFit and server.running[win.appName] then current = win end
        end
        return current
    end

    function api.openApp(name, monitorId, x, y, width, height)
        local app, monitor = definition(name), server.monitors[monitorId]
        if not app then return nil, "Unknown app" end
        if not monitor or not monitor.online then return nil, "Monitor is offline or unknown" end
        if not compatible(name, monitor) then return nil, "App does not fit this monitor" end
        local win = {id = state.nextWindowId, appName = name, monitorId = monitorId,
            x = x, y = y, width = width, height = height, order = 0, layout = "normal",fullscreen=app.fullscreenOnly==true or nil}
        fit(win, monitor)
        if not app.fullscreenOnly and not x and not y then
            local existing, placed = windowsFor(monitorId), false
            for cy = 1, monitor.height - win.height do
                for cx = 1, monitor.width - win.width + 1 do
                    local free = true
                    for _, other in ipairs(existing) do
                        if not other.minimized and fit(other, monitor) and cx < other.x + other.width
                            and cx + win.width > other.x and cy < other.y + other.height
                            and cy + win.height > other.y then free = false; break end
                    end
                    if free then win.x, win.y, placed = cx, cy, true; break end
                end
                if placed then break end
            end
        end
        if not app.fullscreenOnly then win.relative = Desktop.relative(win, monitor) end
        state.windows[win.id], state.nextWindowId = win, win.id + 1
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[win.id] = nil; return nil, err end
        ok, err = startApp(name)
        if not ok then state.windows[win.id] = nil; server.save(); return nil, err end
        if app.onOpen then
            local accepted
            ok,accepted,err=appCall(name,"onOpen",state.appStates[name],api,viewContext(win))
            if not ok or accepted==false then
                state.windows[win.id],server.views[win.id]=nil,nil; stopApp(name); server.save()
                return nil,tostring(ok and err or accepted)
            end
        end
        return win.id
    end
    function api.closeWindow(id)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        state.windows[id] = nil
        local ok, err = server.save()
        if not ok then state.windows[id] = win; return false, err end
        appCall(win.appName,"onClose",state.appStates[win.appName],api,viewContext(win))
        server.views[id], server.dialogs[id] = nil, nil
        local monitor = server.monitors[win.monitorId]
        if monitor then
            if monitor.layoutMenu and monitor.layoutMenu.windowId == id then monitor.layoutMenu = nil end
            if monitor.placement and monitor.placement.windowId == id then monitor.placement = nil end
        end
        stopApp(win.appName)
        invalidateInput(win.monitorId)
        return true
    end
    function api.placeWindow(id, x, y, width, height)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        local app=definition(win.appName)
        if not app then return false,"App is not available" end
        if app.fullscreenOnly then return false,"This app always fills its monitor" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        for _, value in pairs({x = x, y = y, width = width, height = height}) do
            if not integer(value, 1, 512) then return false, "Expected positive integer coordinates/sizes" end
        end
        local previous = copy(win)
        win.x, win.y, win.width, win.height = x or win.x, y or win.y, width or win.width, height or win.height
        win.layout, win.relative, win.restore, win.fullscreen = "normal", nil, nil, nil
        if not fit(win, monitor) then state.windows[id] = previous; return false, "App does not fit" end
        win.relative = Desktop.relative(win, monitor)
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        return true
    end
    function api.layoutWindow(id, mode)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        if not definition(win.appName) then return false, "App is not available" end
        if definition(win.appName).fullscreenOnly then
            if mode=="restore" then return api.closeWindow(id) end
            return mode=="fullscreen",mode~="fullscreen" and "This app always fills its monitor" or nil
        end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        local previous = copy(win)
        if mode == "fullscreen" and win.fullscreen then return true end
        if mode ~= "restore" and mode ~= "fullscreen" and not win.fullscreen and win.layout == mode then return true end
        local exitingFullscreen = mode == "restore" and win.fullscreen
        if mode == "fullscreen" then
            if not Desktop.fullscreen(definition(win.appName), monitor) then return false, "App does not fit fullscreen" end
            -- Keep the complete normal layout/restore chain, not just its rectangle.
            win.fullscreen = true
        elseif exitingFullscreen then
            win.fullscreen = nil
        elseif mode == "restore" then
            local restore = win.restore or {layout = "normal", relative = win.relative}
            win.layout, win.relative, win.restore = restore.layout, copy(restore.relative), nil
        else
            local rect = Desktop.zone(mode, monitor)
            if not Desktop.fits(rect, definition(win.appName), monitor) then return false, "Layout does not fit this app" end
            win.restore = {layout = win.layout or "normal", relative = copy(win.relative)}
            win.layout, win.fullscreen = mode, nil
        end
        if not fit(win, monitor) and not exitingFullscreen then state.windows[id] = previous; return false, "Layout does not fit" end
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        if win.fullscreen then monitor.launcher, monitor.layoutMenu, monitor.placement = false, nil, nil end
        return true
    end
    local function beginPlacement(monitor, win, kind)
        monitor.launcher, monitor.layoutMenu = false, nil
        monitor.placement = {windowId = win.id, kind = kind}
    end
    local function updateCorner(placement, win, monitor)
        local a, b = placement.first, placement.point
        placement.preview = a and b and {x = math.min(a.x, b.x), y = math.min(a.y, b.y),
            width = math.abs(a.x - b.x) + 1, height = math.abs(a.y - b.y) + 1} or nil
        placement.valid = placement.preview and Desktop.fits(placement.preview, definition(win.appName), monitor) and true or false
        placement.error = placement.preview and not placement.valid and "Does not fit" or nil
    end

    local function renderMonitor(id, monitor)
        local desktopColour = state.appearance.backgroundColour
        local borderColour, taskbarColour = state.appearance.windowBorderColour, state.appearance.taskbarColour
        local surface = Gui.new(monitor.width, monitor.height, Gui.contrast(desktopColour), desktopColour)
        local function write(x, y, text, limit)
            surface.write(x, y, text, nil, nil, limit)
        end
        local active
        for _, win in ipairs(windowsFor(id)) do
            if fit(win, monitor) and not win.minimized and server.running[win.appName] then active = win.id end
        end
        local fullscreen = fullscreenWindow(id)
        monitor.fullscreen = fullscreen and fullscreen.id or nil
        if fullscreen then active = fullscreen.id end
        for _, win in ipairs(windowsFor(id)) do
            if (not fullscreen or fullscreen.id == win.id) and fit(win, monitor) and not win.minimized and server.running[win.appName] then
                local body = Desktop.contentRect(win)
                if not win.fullscreen then
                    surface.fill(win.x, win.y, win.width, win.height, Gui.contrast(borderColour), borderColour)
                    write(win.x + 1, win.y, win.title, math.max(0, win.width - 10))
                    for _, control in ipairs(Desktop.controls(win)) do
                        local controlColour = control.action == "close" and 16384 or borderColour
                        surface.write(control.x1, win.y, control.label, Gui.contrast(controlColour), controlColour)
                    end
                end
                surface.fill(body.x, body.y, body.width, body.height, 32768, 256)
                local ok, content
                if win.tooSmall then ok, content = true, {"Window too small", "Top-right exits"}
                elseif server.dialogs[win.id] then
                    local dialog = server.dialogs[win.id]
                    ok = true
                    if dialog.kind == "colour" then
                        local option = systemColours[dialog.target]
                        dialog.current = option and state.appearance[option.field] or api.getAppColour(win.appName)
                        content, dialog.hits = Gui.palette(body.width, body.height, dialog.current,
                            dialog.error or (option and option.title or "UI color"))
                    elseif dialog.kind == "sensor" then content = SensorPicker.render(dialog, body.width, body.height, api.getSensorClients())
                    else content = Picker.render(dialog, body.width, body.height, api.getIOClients()) end
                else
                    ok, content = appCall(win.appName, "render", body.width, body.height,
                        state.appStates[win.appName], api, viewContext(win))
                end
                if not ok or type(content) ~= "table" then content = {"App render failed"} end
                for y = 1, body.height do write(body.x, body.y + y - 1, content[y] or "", body.width) end
                for _, style in ipairs(type(content.styles) == "table" and content.styles or {}) do
                    if type(style) == "table" and integer(style.x, 1, body.width)
                        and integer(style.y, 1, body.height) and integer(style.width, 1, 512)
                        and integer(style.height or 1, 1, 512) then
                        surface.style(body.x + style.x - 1, body.y + style.y - 1,
                            math.min(style.width, body.width - style.x + 1), math.min(style.height or 1, body.height - style.y + 1),
                            style.fg, style.bg)
                    end
                end
            end
        end
        monitor.taskbar = {}
        if not fullscreen then
            local taskbar
            taskbar, monitor.taskbar = Desktop.taskbar(windowsFor(id, true), monitor, server.gameTime, desktopState(id), active)
            write(1, monitor.height, taskbar)
            surface.style(1, monitor.height, monitor.width, 1, Gui.contrast(taskbarColour), taskbarColour)
        end
        for _, hit in ipairs(monitor.taskbar) do
            if (hit.action == "launcher" and monitor.launcher) or (hit.action == "window" and hit.id == active) then
                local highlight = Gui.contrast(taskbarColour)
                surface.style(hit.x1, monitor.height, hit.x2 - hit.x1 + 1, 1, Gui.contrast(highlight), highlight)
            end
        end
        if not fullscreen and (monitor.launcher or monitor.layoutMenu) then
            local items, title, model
            if monitor.launcher then
                model, title = monitor, "Start"
                items = {{label = "OS settings", value = "@settings", enabled = compatible("@settings", monitor)}}
                for _, name in ipairs(sortedKeys(server.apps)) do
                    if compatible(name, monitor) then
                        items[#items + 1] = {label = (server.apps[name].title or name) .. (server.running[name] and " *" or ""), value = name, enabled = true}
                    end
                end
                table.sort(items,function(a,b)
                    local left=(a.value=="@settings" and "OS settings" or definition(a.value).title or a.value):lower()
                    local right=(b.value=="@settings" and "OS settings" or definition(b.value).title or b.value):lower()
                    return left==right and a.value<b.value or left<right
                end)
                if #items == 1 then
                    items[2] = {label = next(server.apps) and "No apps fit" or "No apps installed", enabled = false}
                end
            else
                model, title = monitor.layoutMenu, monitor.layoutMenu.error or "Layout"
                local win = state.windows[model.windowId]
                items = win and Desktop.layoutOptions(win, definition(win.appName), monitor) or {}
            end
            local win = monitor.layoutMenu and state.windows[monitor.layoutMenu.windowId]
            local anchor = win and {x = win.x + win.width - 26, y = win.y + 1}
            local rect, content, hits, page, pages
            if win then rect, content, hits, page, pages = Desktop.layoutPicker(win, definition(win.appName), monitor, model.menuPage, model.error, model.grid)
            else rect, content, hits, page, pages = Desktop.menu(monitor, title, items, model.menuPage, anchor) end
            model.menuPage, model.menuPages, model.menuHits = page, pages, hits
            surface.fill(rect.x, rect.y, rect.width, rect.height, 32768, 1)
            for row = 1, rect.height do write(rect.x, rect.y + row - 1, content[row], rect.width) end
            surface.style(rect.x, rect.y, rect.width, 1, 1, 128)
            if content.styles then
                for _, style in ipairs(content.styles) do
                    surface.style(rect.x + style.x - 1, rect.y + style.y - 1, style.width, style.height or 1, style.fg, style.bg)
                end
            else
                for _, hit in ipairs(hits) do
                    surface.style(hit.x1, hit.y, hit.x2 - hit.x1 + 1, 1,
                        hit.item and hit.item.enabled == false and 128 or 32768, hit.action == "item" and 256 or 128)
                end
            end
        end
        local placement = not fullscreen and monitor.placement
        if placement then
            local rect = placement.preview
            if rect then
                local win = state.windows[placement.windowId]
                placement.valid = win and Desktop.fits(rect, definition(win.appName), monitor) and true or false
                if not placement.valid then placement.error = "Does not fit" end
                local border = placement.error and 16384 or 32
                surface.fill(rect.x, rect.y, rect.width, 1, 1, border)
                if rect.height > 1 then surface.fill(rect.x, rect.y + rect.height - 1, rect.width, 1, 1, border) end
                for y = rect.y + 1, rect.y + rect.height - 2 do
                    surface.fill(rect.x, y, 1, 1, 1, border); surface.fill(rect.x + rect.width - 1, y, 1, 1, 1, border)
                end
            end
            local hint = placement.error or (rect and "OK to apply" or placement.kind == "move" and "Pick position"
                or placement.first and "Other corner" or "First corner")
            if rect and not placement.error then hint = "OK: " .. rect.width .. "x" .. rect.height end
            if placement.kind == "custom" and placement.point then
                hint = placement.error or ((placement.first and "2:" or "1:") .. placement.point.x .. "," .. placement.point.y .. " OK")
            end
            write(1, 1, hint .. string.rep(" ", monitor.width))
            write(1, monitor.height, "[OK][Cancel]" .. string.rep(" ", math.max(0, monitor.width - 12)))
            surface.style(1, 1, monitor.width, 1, 1, 128)
            surface.style(1, monitor.height, 4, 1, 1, 8192)
            surface.style(5, monitor.height, 8, 1, 1, 16384)
            placement.hits = {}
            if placement.first then surface.write(placement.first.x, placement.first.y, "+", 1, 32) end
            if placement.point then surface.write(placement.point.x, placement.point.y, "+", 32768, 1) end
            if placement.kind == "move" and rect then
                if placement.valid then placement.hits = Desktop.moveArrows(rect, monitor) end
                for _, hit in ipairs(placement.hits) do surface.write(hit.x1, hit.y, hit.label, 1, 128) end
            elseif placement.kind == "custom" and placement.point then
                placement.hits, placement.pad = Desktop.pointArrows(placement.point, monitor, placement.pad)
                surface.fill(placement.pad.x, placement.pad.y, 5, 3, 1, 128)
                for _, hit in ipairs(placement.hits) do surface.write(hit.x1, hit.y, hit.label, 1, 2048) end
                local ready = not placement.first or placement.valid
                surface.style(1, monitor.height, 4, 1, 1, ready and 8192 or 128)
            end
            if placement.kind == "move" and rect or placement.kind == "custom" and placement.point then
                local x = monitor.width - 4
                surface.write(x, 1, "Place", 32768, 256)
                placement.hits[#placement.hits + 1] = {x1 = x, x2 = monitor.width, y = 1, action = "place"}
            end
        end
        local notification = firstNotification()
        monitor.notification = notification and notificationModel(notification,monitor) or nil
        if notification then
            local popup = monitor.notification
            local x,y,w,h = popup.x,popup.y,popup.width,popup.height
            surface.fill(x,y,w,h,1,16384)
            if h>=3 then
                surface.fill(x,y,w,1,1,16384)
                surface.write(x+(w>=3 and 1 or 0),y,notification.title,nil,nil,math.max(1,w-2))
                local span=math.max(1,w-2)
                for row=1,math.max(0,h-4) do
                    local text=popup.lines[row] or ""
                    surface.write(x+1+math.max(0,math.floor((span-#text)/2)),y+row,text,1,16384,span)
                end
                if monitor.notificationError and h>=5 then surface.write(x+1,y+h-3,w>=22 and "Save failed; retry OK" or "Save failed",16,16384,math.max(1,w-2)) end
            end
            local hit=popup.ok
            surface.fill(hit.x1,hit.y,hit.x2-hit.x1+1,1,16384,1)
            surface.write(hit.x1+math.max(0,math.floor((hit.x2-hit.x1-1)/2)),hit.y,"OK",16384,1,hit.x2-hit.x1+1)
        end
        return surface.frame()
    end

    function server.refreshMonitors(force)
        for id, monitor in pairs(server.monitors) do
            if monitor.online then
                local lines, foreground, background = renderMonitor(id, monitor)
                local signature = table.concat(lines, "\n") .. table.concat(foreground, "\n")
                    .. table.concat(background, "\n") .. tostring(monitor.inputRevision or 0)
                if force or signature ~= monitor.lastRender then
                    monitor.frameId = (monitor.frameId or 0) + 1
                    if net.toClient(monitor, {type = "render", clientId = id, monitorId = id,
                        serverSession = server.session, lines = lines, width = monitor.width, height = monitor.height,
                        colourFormat = "rle1", foreground = foreground, background = background,
                        frameId = monitor.frameId, inputRevision = monitor.inputRevision or 0}) then
                        monitor.lastRender = signature
                    end
                end
            end
        end
    end

    local function touch(id, x, y)
        local monitor = server.monitors[id]
        if not integer(x, 1, monitor.width) or not integer(y, 1, monitor.height) then return end
        local notification = firstNotification()
        if notification then
            local popup=monitor.notification
            if popup and popup.key==notification.key and popup.appName==notification.appName and Gui.hit(popup.ok,x,y) then
                local ok,accepted,err=appCall(notification.appName,"handleNotification",notification.key,
                    state.appStates[notification.appName],api,{appName=notification.appName,monitorId=id})
                if not ok or accepted~=true then monitor.notificationError=tostring(ok and err or accepted) end
            end
            return -- Modal: no click-through into apps, taskbar or placement.
        end
        local fullscreen = fullscreenWindow(id)
        if fullscreen and x == monitor.width and y == 1 and not definition(fullscreen.appName).handlesFullscreenCorner then
            if definition(fullscreen.appName).fullscreenOnly then api.closeWindow(fullscreen.id)
            else api.layoutWindow(fullscreen.id, "restore") end
            return -- The invisible exit cell never reaches the app underneath.
        end
        local placement = not fullscreen and monitor.placement
        if placement then
            local win = state.windows[placement.windowId]
            if not win then monitor.placement = nil; return end
            if y == monitor.height then
                if x >= 5 and x <= 12 then monitor.placement = nil
                elseif x <= 4 and placement.kind == "custom" and placement.point and not placement.first then
                    placement.first, placement.point, placement.pad = placement.point, nil, nil
                    placement.error = nil
                elseif x <= 4 and placement.preview and placement.valid then
                    local rect = placement.preview
                    if not Desktop.fits(rect, definition(win.appName), monitor) then
                        placement.valid, placement.error = false, "Does not fit"; return
                    end
                    local ok, err = api.placeWindow(win.id, rect.x, rect.y, rect.width, rect.height)
                    if ok then monitor.placement = nil else placement.error = tostring(err) end
                end
                return
            end
            for _, hit in ipairs(placement.hits or {}) do
                if Gui.hit(hit, x, y) then
                    if hit.action == "place" then
                        placement.preview, placement.point, placement.pad, placement.valid, placement.error = nil, nil, nil, false, nil
                        return
                    end
                    if placement.kind == "custom" then
                        placement.point.x, placement.point.y = placement.point.x + hit.dx, placement.point.y + hit.dy
                        updateCorner(placement, win, monitor)
                        return
                    end
                    local rect = placement.preview
                    rect.x, rect.y = rect.x + hit.dx, rect.y + hit.dy
                    placement.valid = Desktop.fits(rect, definition(win.appName), monitor) and true or false
                    placement.error = not placement.valid and "Does not fit" or nil
                    return
                end
            end
            if placement.kind == "move" then
                if placement.preview then return end
                placement.preview = {x = math.max(1, math.min(x, monitor.width - win.width + 1)),
                    y = math.max(1, math.min(y, monitor.height - win.height)), width = win.width, height = win.height}
            else
                if placement.point then return end
                placement.point = {x = x, y = y}
                updateCorner(placement, win, monitor)
                return
            end
            placement.valid = Desktop.fits(placement.preview, definition(win.appName), monitor) and true or false
            placement.error = placement.preview and not placement.valid and "Does not fit" or nil
            return
        end
        if not fullscreen and y == monitor.height then
            for _, hit in ipairs(monitor.taskbar or {}) do
                if x >= hit.x1 and x <= hit.x2 then
                    monitor.layoutMenu = nil
                    if hit.action == "launcher" then
                        monitor.launcher = not monitor.launcher; monitor.menuPage = 1
                    elseif hit.action == "previous" or hit.action == "next" then
                        local saved = desktopState(id)
                        saved.scroll = (saved.scroll or 1) + (hit.action == "next" and 1 or -1)
                        server.save()
                    elseif hit.action == "window" then
                        local win = state.windows[hit.id]
                        local active
                        for _, other in ipairs(windowsFor(id)) do
                            if not other.minimized and not other.doesNotFit then active = other.id end
                        end
                        if active == win.id then win.minimized = true else focus(win) end
                        monitor.launcher = false; server.save()
                    end
                    return
                end
            end
            return
        end
        local model = not fullscreen and (monitor.launcher and monitor or monitor.layoutMenu)
        if model then
            for _, hit in ipairs(model.menuHits or {}) do
                if Gui.hit(hit, x, y) then
                    if hit.action == "previous" then model.menuPage = math.max(1, model.menuPage - 1)
                    elseif hit.action == "next" then model.menuPage = math.min(model.menuPages, model.menuPage + 1)
                    elseif hit.item.enabled ~= false then
                        if monitor.launcher then
                            local existing
                            for _, win in ipairs(windowsFor(id)) do if win.appName == hit.item.value then existing = win end end
                            if existing then focus(existing); server.save() else api.openApp(hit.item.value, id) end
                            monitor.launcher = false
                        else
                            local win = state.windows[model.windowId]
                            local mode = hit.item.value
                            local grid = mode:match("^choose_([1-3]x[1-3])$")
                            if grid then
                                model.grid, model.rootPage, model.menuPage, model.error = grid, model.menuPage, 1, nil
                            elseif mode == "back" then
                                model.grid, model.menuPage, model.error = nil, model.rootPage or 1, nil
                            elseif mode == "custom" or mode == "move" then beginPlacement(monitor, win, mode)
                            elseif mode == "cancel" then monitor.layoutMenu = nil
                            else
                                local ok, err = api.layoutWindow(win.id, mode)
                                if ok then monitor.layoutMenu = nil else model.error = tostring(err) end
                            end
                        end
                    else model.error = "Does not fit" end
                    return
                end
            end
            monitor.launcher, monitor.layoutMenu = false, nil
            return
        end
        local list = fullscreen and {fullscreen} or windowsFor(id)
        for index = #list, 1, -1 do
            local win = list[index]
            if not win.minimized and not win.doesNotFit and x >= win.x and x < win.x + win.width
                and y >= win.y and y < win.y + win.height then
                if not win.fullscreen and y == win.y then
                    for _, control in ipairs(Desktop.controls(win)) do
                        if x >= control.x1 and x <= control.x2 then
                            if control.action == "close" then api.closeWindow(win.id)
                            elseif control.action == "layout" then
                                focus(win); monitor.layoutMenu = {windowId = win.id, menuPage = 1}; server.save()
                            else win.minimized = true; server.save() end
                            return
                        end
                    end
                    focus(win); beginPlacement(monitor, win, "move"); server.save()
                    return
                end
                focus(win)
                local body = Desktop.contentRect(win)
                local contentX, contentY = x - body.x + 1, y - body.y + 1
                if not win.tooSmall and contentX >= 1 and contentX <= body.width and contentY >= 1 and contentY <= body.height then
                    local dialog = server.dialogs[win.id]
                    if dialog then
                        local action, address
                        if dialog.kind == "colour" then
                            for _, hit in ipairs(dialog.hits or {}) do
                                if Gui.hit(hit, contentX, contentY) then action, address = hit.action, hit.value; break end
                            end
                            if action == "colour" then
                                local ok, err
                                if systemColourSetters[dialog.target] then ok, err = systemColourSetters[dialog.target](address)
                                else ok, err = api.setAppColour(win.appName, address) end
                                if ok then server.dialogs[win.id] = nil else dialog.error = tostring(err) end
                            elseif action == "cancel" then server.dialogs[win.id] = nil end
                        elseif dialog.kind == "sensor" then action, address = SensorPicker.touch(dialog, contentX, contentY)
                        else action, address = Picker.touch(dialog, contentX, contentY) end
                        if action == "cancel" then server.dialogs[win.id] = nil
                        elseif action == "selected" then
                            local hook = dialog.kind == "sensor" and "handleSensorSelection" or "handleIOSelection"
                            local ok, accepted, err = appCall(win.appName, hook, dialog.key,
                                address, state.appStates[win.appName], api, viewContext(win))
                            if ok and accepted ~= false then server.dialogs[win.id] = nil
                            else dialog.error = tostring(ok and err or accepted) end
                        end
                    else
                        local ok, handled, replacement = appCall(win.appName, "handleTouch", contentX, contentY,
                            body.width, body.height, state.appStates[win.appName], api, viewContext(win))
                        if ok and type(replacement) == "table" then state.appStates[win.appName] = replacement end
                    end
                end
                server.save()
                return
            end
        end
    end

    local function registered(group, message, replyChannel)
        local client = group[message.clientId]
        if client and client.online and client.computerId == message.sender and client.channel == replyChannel
            and message.serverSession == server.session then return client end
    end

    function server.handle(message, replyChannel, now)
        if type(message.clientId) ~= "string" or #message.clientId == 0 or #message.clientId > 64 then return end
        local id = message.clientId
        if message.type == "announce" then
            if not integer(message.nonce, 1, 2147483647) then return end
            local groups = clientGroups
            local group = groups[message.clientType]
            if not group then return end
            for _, otherGroup in pairs(groups) do
                local other = otherGroup[id]
                if other and (otherGroup ~= group or (other.online and other.computerId ~= message.sender)) then
                    log("Duplicate clientId rejected: " .. id .. " (computer " .. message.sender .. ")")
                    return
                end
            end
            if message.clientType == "monitor" and (not integer(message.width, 1, 256)
                or not integer(message.height, 2, 128)) then return end
            if message.clientType == "relay" and (message.relayProtocol ~= 1
                or not integer(message.forwarded, 0, 2147483647)) then return end
            local client = group[id]
            local reconnect = not client or not client.online or client.computerId ~= message.sender
            client = client or {inputs = {}, values = {}, revision = 0, ackedRevision = -1}
            local ioReset, ioChanged = false, false
            client.computerId, client.channel, client.lastSeen, client.online = message.sender, replyChannel, now, true
            client.route = copy(message._route or {})
            if message.clientType == "relay" then client.forwarded = message.forwarded end
            if reconnect then client.inputs, client.values = {}, {} end
            group[id] = client
            if message.clientType == "monitor" then
                if reconnect or client.width ~= message.width or client.height ~= message.height then invalidateInput(id) end
                client.width, client.height = message.width, message.height
                client.touchProtocol = message.touchProtocol == 1
                client.lastRender = nil -- Periodic full repaint also recovers a lost frame.
            elseif message.clientType == "io" then
                ioReset = reconnect or client.announceNonce ~= nil and message.nonce <= client.announceNonce
                local previousCapabilities = client.capabilities
                client.capabilities = {}
                if type(message.capabilities) == "table" then
                    for side, flags in pairs(message.capabilities) do
                        if sideSet[side] and type(flags) == "table" and flags.bundled and flags.digital then
                            client.capabilities[side] = true
                        end
                    end
                end
                if previousCapabilities then
                    for side in pairs(sideSet) do
                        if previousCapabilities[side] ~= client.capabilities[side] then ioChanged = true end
                    end
                end
                ioChanged = ioChanged or ioReset
                ioReset = ioReset or ioChanged
                client.announceNonce = message.nonce
            end
            if message.clientType == "sensor" then sensors.announce(client, message, reconnect) end
            net.toClient(client, {type = "welcome", clientId = id, nonce = message.nonce, serverSession = server.session})
            if reconnect then log(message.clientType .. " connected: " .. id .. " (computer " .. message.sender .. ")") end
            if message.clientType == "io" then
                -- Routine announcements resend the same snapshot as a health
                -- check. They do not revoke an acknowledgement already earned.
                if ioReset then
                    client.ackedRevision, client.outputSnapshot, client.wireRevisions = -1, nil, {}
                end
                server.syncIO(id, ioChanged)
            end
            server.refreshMonitors(false)
        elseif message.type == "inputData" then
            local client = registered(server.ioClients, message, replyChannel)
            if not client or not client.capabilities[message.side] or not integer(message.value, 0, 65535)
                or type(message.digital) ~= "boolean" then return end
            client.inputs[message.side] = {value = message.value, digital = message.digital}
            client.lastSeen = now
        elseif message.type == "ioAck" then
            local client = registered(server.ioClients, message, replyChannel)
            if client and message.revision == client.revision then
                client.ackedRevision, client.lastSeen = message.revision, now
            end
        elseif message.type == "sensorCatalog" or message.type == "sensorSample" then
            local client = registered(server.sensorClients, message, replyChannel)
            if client then
                if message.type == "sensorCatalog" then sensors.catalog(client, message, now) else sensors.sample(client, message, now) end
            end
        elseif message.type == "sensorData" then
            local client = registered(server.sensorClients, message, replyChannel)
            if not client or type(message.varName) ~= "string" then return end
            local value = message.value
            if type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "boolean" then return end
            if message.varName == "playerOnline" then
                if type(value) ~= "boolean" then return end
                server.playerOnline = value
            elseif message.varName == "gameTime" then
                if type(value) ~= "string" then return end
            end
            -- Never assign arbitrary network-provided keys into OS state.
            client.values[message.varName], client.lastSeen = value, now
            if message.varName == "gameTime" then updateClock() end
        elseif message.type == "touch" then
            local client = registered(server.monitors, message, replyChannel)
            if client then
                if not client.touchProtocol or message.inputRevision == (client.inputRevision or 0) then
                    invalidateInput(id)
                    touch(id, message.x, message.y)
                else client.lastRender = nil end -- Recover a lost reply without applying an old tap twice.
                server.refreshMonitors(false)
            end
        elseif message.type == "resize" then
            local client = registered(server.monitors, message, replyChannel)
            if client and integer(message.width, 1, 256) and integer(message.height, 2, 128) then
                invalidateInput(id)
                client.width, client.height = message.width, message.height
                client.lastRender, client.lastSeen = nil, now
                server.refreshMonitors(false)
            end
        end
    end

    function server.start()
        -- A persisted boot generation prevents stale output commands after an OS reboot.
        assert(server.save(), "Cannot checkpoint OS startup")
        for _, file in ipairs(fs.list("")) do
            local name = file:match("^apps_([%w_-]+)%.lua$")
            if name and not fs.isDir(file) then
                -- Files and an old auto-populated registry are not consent to
                -- run an app. Only explicitly enabled user apps may execute.
                if config.enabledApps and config.enabledApps[name] == true then
                    local chunk, err = loadfile(file)
                    local ok, app = false, err
                    if chunk then ok, app = pcall(chunk) end
                    if ok and validApp(app) then
                        server.apps[name], state.appRegistry[name] = app, true
                        if type(state.appStates[name]) ~= "table" then state.appStates[name] = {} end
                        log("Loaded app: " .. name)
                    else log("Cannot load app " .. name .. ": " .. tostring(app)) end
                end
            end
        end
        local discard={}
        for id,win in pairs(state.windows) do
            local app=definition(win.appName)
            if win.transientWindow or app and app.transientWindow then discard[#discard+1]=id end
        end
        for _,id in ipairs(discard) do state.windows[id],server.views[id]=nil,nil end
        for _, name in ipairs(sortedKeys(server.apps)) do
            if isService(server.apps[name]) or hasViews(name) then startApp(name) end
        end
        for _, name in ipairs(sortedKeys(server.systemApps)) do if hasViews(name) then startApp(name) end end
        net.ensureModem()
        log("SmartHome OS computer " .. net.id .. ", network " .. net.config.networkId)
        if not net.modem then log("Attach a wireless modem; waiting...") end
    end

    function server.tick(now)
        net.ensureModem()
        for _, group in pairs(clientGroups) do
            for id, client in pairs(group) do
                if client.online and now - client.lastSeen >= config.clientTimeout then
                    client.online = false
                    log("Client offline: " .. id)
                    if client.values then
                        if client.values.playerOnline ~= nil then server.playerOnline = false end
                        if client.values.gameTime ~= nil then server.gameTime = "?:??" end
                    end
                end
            end
        end
        local dt = math.max(0, now - server.lastTick)
        server.lastTick = now
        updateClock()
        for name in pairs(server.running) do appCall(name, "background", dt, state.appStates[name], api) end
        sensors.tick(now)
        for id, client in pairs(server.ioClients) do
            if client.online and client.ackedRevision ~= client.revision
                and now - (client.lastSent or -math.huge) >= config.retryInterval then server.syncIO(id, false) end
        end
        server.refreshMonitors(false)
        -- Keep checkpoints within one second even when an older config says 30.
        if now - server.lastSave >= math.min(config.saveInterval, 1) then server.save() end
    end
    function server.nextTickInterval()
        local interval=config.tickInterval or 0.5
        for _,monitor in pairs(server.monitors) do if monitor.online and monitor.fullscreen then
            local win=state.windows[monitor.fullscreen]
            local app=win and definition(win.appName)
            if app and app.animationInterval then interval=math.min(interval,app.animationInterval) end
        end end
        return interval
    end

    function server.command(line)
        local args = {}
        for word in line:gmatch("%S+") do args[#args + 1] = word end
        local cmd = args[1]
        if not cmd then return {} end
        if cmd == "help" then return {
            "clients | sensors [client] | inputs <client>",
            "outputs | apps",
            "map <name> <client> <side> <color|digital>",
            "set <name> <on|off> | toggle <name>",
            "open <app> <monitor> | close <windowId>",
            "move <id> <x> <y> | resize <id> <width> <height>",
            "clear | save | quit (saves and exits)",
        } end
        if cmd == "clear" then return {}, false, "clear"
        elseif cmd == "clients" then
            local lines = {}
            for _, item in ipairs(api.getClients()) do
                lines[#lines + 1] = item.id .. " " .. item.type .. " " .. (item.online and "ONLINE" or "offline")
                    .. " computer=" .. item.computerId
                    .. (#item.via > 0 and " via=" .. table.concat(item.via, ">") or " direct")
                    .. (item.type == "relay" and " forwarded=" .. tostring(item.forwarded or 0) or "")
            end
            if #lines == 0 then lines[1] = "No clients connected yet" end
            return lines
        elseif cmd == "sensors" then
            local lines = {}
            for _, client in ipairs(api.getSensorClients()) do
                if not args[2] or args[2] == client.id then
                    lines[#lines + 1] = client.id .. " " .. (client.online and "ONLINE" or "offline")
                        .. " protocol=" .. tostring(client.sensorProtocol or "legacy") .. " boot=" .. tostring(client.bootId or "unknown")
                    if #client.ports == 0 then lines[#lines + 1] = "  Waiting for sensor catalog" end
                    for _, port in ipairs(client.ports) do
                        local reactors = 0
                        for _, target in ipairs(port.targets) do if target.kind == "reactor" then reactors = reactors + 1 end end
                        lines[#lines + 1] = "  " .. port.side .. ": " .. port.status .. " / " .. port.cardKind
                            .. " / targets=" .. #port.targets .. " reactors=" .. reactors
                        lines[#lines + 1] = "    card=" .. tostring(port.card or "none")
                        if port.error then lines[#lines + 1] = "    " .. port.error end
                    end
                    for _, pending in ipairs(client.pending) do
                        lines[#lines + 1] = "  " .. pending.side .. " catalog parts=" .. pending.received .. "/" .. pending.parts
                    end
                    if client.catalogError then lines[#lines + 1] = "  Catalog rejected: " .. client.catalogError end
                end
            end
            if #lines == 0 then lines[1] = "No matching sensor clients" end
            return lines
        elseif cmd == "outputs" then
            local lines = {}
            for _, item in ipairs(api.getOutputs()) do
                lines[#lines + 1] = item.name .. "=" .. (item.value and "ON" or "OFF") .. " -> " .. item.clientId
                    .. ":" .. item.side .. ":" .. tostring(item.color or "digital")
                    .. (item.confirmed and " confirmed" or " pending/offline")
            end
            if #lines == 0 then lines[1] = "No mappings. Use: map test io_ID left white" end
            return lines
        elseif cmd == "inputs" then
            local client = server.ioClients[args[2]]
            if not client or not client.online then return {"Client unknown or offline"} end
            local lines = {}
            for _, side in ipairs(sortedKeys(client.inputs)) do
                local input = client.inputs[side]
                lines[#lines + 1] = side .. ": bundled=" .. input.value .. " digital=" .. tostring(input.digital)
            end
            return lines
        elseif cmd == "apps" then return sortedKeys(server.apps)
        elseif cmd == "map" then
            local color = args[5] ~= "digital" and (colors[args[5] or ""] or tonumber(args[5])) or nil
            if args[5] ~= "digital" and not colour(color) then return {"Choose a CC color name/bit or digital"} end
            local ok, err = api.mapOutput(args[2], args[3], args[4], color)
            return {ok and "Mapping saved" or tostring(err)}
        elseif cmd == "set" or cmd == "toggle" then
            if not args[2] then return {"Specify an output name"} end
            if cmd == "set" and args[3] ~= "on" and args[3] ~= "off" then return {"Use set <name> on|off"} end
            local value = args[3] == "on"
            if cmd == "toggle" then value = not api.getOutput(args[2]) end
            local ok, err = api.setOutput(args[2], value)
            return {ok and "Desired state saved; use outputs to check acknowledgement" or tostring(err)}
        elseif cmd == "open" then
            local id, err = api.openApp(args[2], args[3])
            server.refreshMonitors(false)
            return {id and ("Opened window " .. id) or tostring(err)}
        elseif cmd == "close" then
            local ok, err = api.closeWindow(tonumber(args[2]))
            server.refreshMonitors(false)
            return {ok and "Window closed" or tostring(err)}
        elseif cmd == "move" or cmd == "resize" then
            local a, b = tonumber(args[3]), tonumber(args[4])
            if not a or not b then return {"Specify two positive integers"} end
            local ok, err
            if cmd == "move" then ok, err = api.placeWindow(tonumber(args[2]), a, b)
            else ok, err = api.placeWindow(tonumber(args[2]), nil, nil, a, b) end
            server.refreshMonitors(false)
            return {ok and "Window updated" or tostring(err)}
        elseif cmd == "save" or cmd == "quit" then
            local ok, err = server.save()
            return {ok and "State saved" or tostring(err)}, cmd == "quit" and ok
        end
        return {"Unknown command; type help"}
    end

    return server
end

return Server
