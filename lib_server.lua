-- Central state, app lifecycle, desktops and logical IO routing. No redstone here.
local Server = {}
local Picker = dofile("lib_io_picker.lua")
local Desktop = dofile("lib_desktop.lua")
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
    for _, key in ipairs({"minWidth", "maxWidth", "minHeight", "maxHeight", "preferredWidth", "preferredHeight"}) do
        if app[key] ~= nil and not integer(app[key], 1, 512) then return false end
    end
    if app.backgroundService ~= nil and type(app.backgroundService) ~= "boolean" then return false end
    for _, key in ipairs({"init", "shutdown", "background", "render", "handleTouch", "handleIOSelection"}) do
        if app[key] ~= nil and type(app[key]) ~= "function" then return false end
    end
    return (not app.maxWidth or app.maxWidth >= (app.minWidth or 8))
        and (not app.maxHeight or app.maxHeight >= (app.minHeight or 2))
end

function Server.new(net, storage, config)
    local loaded, source = storage.load(config.saveFile, validState)
    local state = loaded or {}
    for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if type(state[name]) ~= "table" then state[name] = {} end
    end
    local server = {state = state, monitors = {}, ioClients = {}, sensorClients = {}, apps = {},
        gameTime = "?:??", playerOnline = false, lastSave = 0, lastTick = os.clock(), views = {}, dialogs = {}, running = {}}
    local api, errors = {}, {}
    server.api = api
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
            if legacyDesktop then win.y = math.max(1, (tonumber(win.y) or 3) - 2) end
        end
    end
    state.desktopVersion = 2
    state.bootCounter = (tonumber(state.bootCounter) or 0) + 1
    server.session = tostring(net.id) .. ":" .. state.bootCounter
    if source and source ~= config.saveFile then print("Recovered state from " .. source) end
    if not loaded and fs.exists(config.saveFile) then print("Unreadable OS state; starting with defaults") end

    function server.save()
        local saved = {}
        for _, name in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides",
            "nextWindowId", "bootCounter", "desktops", "desktopVersion"}) do saved[name] = state[name] end
        local ok, err = storage.save(config.saveFile, saved)
        if not ok then print("State save failed: " .. tostring(err)) else server.lastSave = os.clock() end
        return ok, err
    end
    api.save = server.save

    local function appCall(name, hook, ...)
        local app = server.apps[name]
        if not app or not app[hook] then return true end
        local ok, a, b = pcall(app[hook], ...)
        if not ok then
            local key = name .. "." .. hook
            if errors[key] ~= a then print("App " .. key .. " failed: " .. tostring(a)); errors[key] = a end
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
        if server.running[name] and not isService(server.apps[name]) and not hasViews(name) then
            appCall(name, "shutdown", state.appStates[name], api, {appName = name})
            server.running[name] = nil
            server.save()
        end
    end

    local function viewContext(win)
        server.views[win.id] = server.views[win.id] or {}
        return {windowId = win.id, monitorId = win.monitorId, appName = win.appName, view = server.views[win.id]}
    end

    local function updateClock()
        if type(os.time) == "function" then
            local ok, value = pcall(os.time)
            if ok and type(value) == "number" and value >= 0 and value < 24 then
                local minutes = math.floor(value * 60 + 0.000001)
                server.gameTime = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
                server.clockSource = "computer"
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
        local snapshot = outputSnapshot(clientId)
        for side in pairs(snapshot) do
            if not client.capabilities[side] then
                print("IO " .. clientId .. ": mapped side " .. side .. " is unavailable")
                snapshot[side] = nil
            end
        end
        net.toClient(client, {type = "ioCommand", command = "syncOutputs", clientId = clientId,
            serverSession = server.session, revision = client.revision, outputs = snapshot})
        client.lastSent = os.clock()
    end

    function api.mapOutput(name, clientId, side, color, initialValue)
        if type(name) ~= "string" or not name:match("^[%w_-]+$")
            or type(clientId) ~= "string" or clientId == "" or not sideSet[side]
            or (color ~= nil and not colour(color))
            or (initialValue ~= nil and type(initialValue) ~= "boolean") then return false, "Invalid output mapping" end
        local client = server.ioClients[clientId]
        if client and client.online and not client.capabilities[side] then
            return false, "That side is unavailable (possibly occupied by the modem)"
        end
        for other, mapping in pairs(state.outputMap) do
            if other ~= name and mapping.clientId == clientId and mapping.side == side
                and mapping.color == color then return false, "Wire already mapped to " .. other end
        end
        local previous, oldManaged, previousValue = state.outputMap[name], copy(state.managedSides), state.outputs[name]
        state.outputMap[name] = {clientId = clientId, side = side, color = color}
        if initialValue ~= nil then state.outputs[name] = initialValue end
        state.managedSides[clientId] = state.managedSides[clientId] or {}
        state.managedSides[clientId][side] = true
        if previous then
            state.managedSides[previous.clientId] = state.managedSides[previous.clientId] or {}
            state.managedSides[previous.clientId][previous.side] = true
        end
        local ok, err = server.save()
        if not ok then
            state.outputMap[name], state.managedSides, state.outputs[name] = previous, oldManaged, previousValue
            return false, err
        end
        if previous and previous.clientId ~= clientId then server.syncIO(previous.clientId, true) end
        server.syncIO(clientId, true)
        return true
    end

    function api.setOutput(name, value)
        local mapping = state.outputMap[name]
        if not mapping then return false, "Unknown output: " .. tostring(name) end
        if type(value) ~= "boolean" then return false, "Output value must be boolean" end
        local previous = state.outputs[name]
        state.outputs[name] = value
        -- Commit desired state before commanding hardware; failed writes are visible.
        local ok, err = server.save()
        if not ok then state.outputs[name] = previous; return false, err end
        server.syncIO(mapping.clientId, true)
        return true
    end

    function api.getOutput(name) return state.outputs[name] == true end
    function api.getOutputs()
        local result = {}
        for _, name in ipairs(sortedKeys(state.outputMap)) do
            local item = copy(state.outputMap[name])
            local client = server.ioClients[item.clientId]
            item.name, item.value, item.online = name, api.getOutput(name), client and client.online or false
            item.confirmed = item.online and client.capabilities[item.side]
                and client.ackedRevision == client.revision or false
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
        if win.width < 14 or win.height < 8 then return false, "IO settings need a 12x6 content area" end
        local app = server.apps[win.appName]
        if not app or not app.handleIOSelection then return false, "App has no IO selection handler" end
        server.dialogs[windowId] = Picker.new(key, direction, current)
        return true
    end
    function api.getSensor(clientId, name)
        local client = server.sensorClients[clientId]
        if client and client.online then return copy(client.values[name]) end
    end
    function api.getClients()
        local result = {}
        for kind, group in pairs({io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients}) do
            for id, client in pairs(group) do
                result[#result + 1] = {id = id, type = kind, online = client.online, computerId = client.computerId}
            end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    function api.getSystem() return {gameTime = server.gameTime, clockSource = server.clockSource,
        playerOnline = server.playerOnline} end

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
        local app = server.apps[win.appName]
        if not app then win.doesNotFit = true; return false end
        if not validRelative(win.relative) then win.relative = nil end
        local rect
        if win.layout and win.layout ~= "normal" then
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
        local app = server.apps[name]
        local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
        return app.render and maxW >= minW and maxH >= minH
    end
    local function discardSmallDialog(win)
        if win.width < 14 or win.height < 8 then server.dialogs[win.id] = nil end
    end

    function api.openApp(name, monitorId, x, y, width, height)
        local app, monitor = server.apps[name], server.monitors[monitorId]
        if not app then return nil, "Unknown app" end
        if not monitor or not monitor.online then return nil, "Monitor is offline or unknown" end
        if not compatible(name, monitor) then return nil, "App does not fit this monitor" end
        local win = {id = state.nextWindowId, appName = name, monitorId = monitorId,
            x = x, y = y, width = width, height = height, order = 0, layout = "normal"}
        fit(win, monitor)
        if not x and not y then
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
        win.relative = Desktop.relative(win, monitor)
        state.windows[win.id], state.nextWindowId = win, win.id + 1
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[win.id] = nil; return nil, err end
        ok, err = startApp(name)
        if not ok then state.windows[win.id] = nil; server.save(); return nil, err end
        return win.id
    end
    function api.closeWindow(id)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        state.windows[id] = nil
        local ok, err = server.save()
        if not ok then state.windows[id] = win; return false, err end
        server.views[id], server.dialogs[id] = nil, nil
        local monitor = server.monitors[win.monitorId]
        if monitor then
            if monitor.layoutMenu and monitor.layoutMenu.windowId == id then monitor.layoutMenu = nil end
            if monitor.placement and monitor.placement.windowId == id then monitor.placement = nil end
        end
        stopApp(win.appName)
        return true
    end
    function api.placeWindow(id, x, y, width, height)
        local win = state.windows[id]
        if not win then return false, "Unknown window" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        for _, value in pairs({x = x, y = y, width = width, height = height}) do
            if not integer(value, 1, 512) then return false, "Expected positive integer coordinates/sizes" end
        end
        local previous = copy(win)
        win.x, win.y, win.width, win.height = x or win.x, y or win.y, width or win.width, height or win.height
        win.layout, win.relative, win.restore = "normal", nil, nil
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
        if not server.apps[win.appName] then return false, "App is not available" end
        local monitor = server.monitors[win.monitorId]
        if not monitor or not monitor.online then return false, "Monitor is offline" end
        local previous = copy(win)
        if mode ~= "restore" and win.layout == mode then return true end
        if mode == "restore" then
            local restore = win.restore or {layout = "normal", relative = win.relative}
            win.layout, win.relative, win.restore = restore.layout, copy(restore.relative), nil
        else
            local rect = Desktop.zone(mode, monitor)
            if not Desktop.fits(rect, server.apps[win.appName], monitor) then return false, "Layout does not fit this app" end
            win.restore = {layout = win.layout or "normal", relative = copy(win.relative)}
            win.layout = mode
        end
        if not fit(win, monitor) then state.windows[id] = previous; return false, "Layout does not fit" end
        focus(win)
        local ok, err = server.save()
        if not ok then state.windows[id] = previous; return false, err end
        discardSmallDialog(win)
        return true
    end
    local function beginPlacement(monitor, win, kind)
        monitor.launcher, monitor.layoutMenu = false, nil
        monitor.placement = {windowId = win.id, kind = kind}
    end

    local function renderMonitor(id, monitor)
        local lines = {}
        for y = 1, monitor.height do lines[y] = string.rep(" ", monitor.width) end
        local function write(x, y, text, limit)
            if y < 1 or y > monitor.height or x < 1 or x > monitor.width then return end
            text = tostring(text or ""):sub(1, math.min(limit or monitor.width, monitor.width - x + 1))
            lines[y] = lines[y]:sub(1, x - 1) .. text .. lines[y]:sub(x + #text)
        end
        write(1, 1, "SmartHome OS")
        local active
        for _, win in ipairs(windowsFor(id)) do
            if fit(win, monitor) and not win.minimized and server.running[win.appName] then
                active = win.id
                local title = ("[X][#][_] " .. win.appName):sub(1, win.width)
                write(win.x, win.y, title .. string.rep("-", win.width - #title), win.width)
                for y = win.y + 1, win.y + win.height - 2 do
                    write(win.x, y, "|" .. string.rep(" ", win.width - 2) .. "|")
                end
                write(win.x, win.y + win.height - 1, "+" .. string.rep("-", win.width - 2) .. "+")
                local ok, content
                if server.dialogs[win.id] then
                    ok, content = true, Picker.render(server.dialogs[win.id], win.width - 2, win.height - 2, api.getIOClients())
                else
                    ok, content = appCall(win.appName, "render", win.width - 2, win.height - 2,
                        state.appStates[win.appName], api, viewContext(win))
                end
                if not ok or type(content) ~= "table" then content = {"App render failed"} end
                for y = 1, win.height - 2 do write(win.x + 1, win.y + y, content[y] or "", win.width - 2) end
            end
        end
        local taskbar
        taskbar, monitor.taskbar = Desktop.taskbar(windowsFor(id, true), monitor, server.gameTime, desktopState(id), active)
        write(1, monitor.height, taskbar)
        if monitor.launcher or monitor.layoutMenu then
            local items, title, model
            if monitor.launcher then
                model, title, items = monitor, "Apps", {}
                for _, name in ipairs(sortedKeys(server.apps)) do
                    if compatible(name, monitor) then
                        items[#items + 1] = {label = name .. (server.running[name] and " *" or ""), value = name, enabled = true}
                    end
                end
                if #items == 0 then
                    items[1] = {label = next(server.apps) and "No apps fit" or "No apps installed", enabled = false}
                end
            else
                model, title = monitor.layoutMenu, monitor.layoutMenu.error or "Layout"
                local win = state.windows[model.windowId]
                items = win and Desktop.layoutOptions(win, server.apps[win.appName], monitor) or {}
            end
            local rect, content, hits, page, pages = Desktop.menu(monitor, title, items, model.menuPage)
            model.menuPage, model.menuPages, model.menuHits = page, pages, hits
            for row = 1, rect.height do write(rect.x, rect.y + row - 1, content[row], rect.width) end
        end
        local placement = monitor.placement
        if placement then
            local rect = placement.preview
            if rect then
                local mark = placement.error and "!" or "#"
                write(rect.x, rect.y, string.rep(mark, rect.width), rect.width)
                if rect.height > 1 then write(rect.x, rect.y + rect.height - 1, string.rep(mark, rect.width), rect.width) end
                for y = rect.y + 1, rect.y + rect.height - 2 do
                    write(rect.x, y, mark); write(rect.x + rect.width - 1, y, mark)
                end
            end
            if placement.first then write(placement.first.x, placement.first.y, "+") end
            local hint = placement.error or (rect and "OK to apply" or placement.kind == "move" and "Pick position"
                or placement.first and "Other corner" or "First corner")
            if rect and not placement.error then hint = "OK: " .. rect.width .. "x" .. rect.height end
            write(1, 1, hint .. string.rep(" ", monitor.width))
            write(1, monitor.height, "[OK][Cancel]" .. string.rep(" ", math.max(0, monitor.width - 12)))
        end
        return lines
    end

    function server.refreshMonitors(force)
        for id, monitor in pairs(server.monitors) do
            if monitor.online then
                local lines = renderMonitor(id, monitor)
                local signature = table.concat(lines, "\n")
                if force or signature ~= monitor.lastRender then
                    if net.toClient(monitor, {type = "render", clientId = id, monitorId = id,
                        serverSession = server.session, lines = lines, width = monitor.width, height = monitor.height}) then
                        monitor.lastRender = signature
                    end
                end
            end
        end
    end

    local function touch(id, x, y)
        local monitor = server.monitors[id]
        if not integer(x, 1, monitor.width) or not integer(y, 1, monitor.height) then return end
        local placement = monitor.placement
        if placement then
            local win = state.windows[placement.windowId]
            if not win then monitor.placement = nil; return end
            if y == monitor.height then
                if x >= 5 and x <= 12 then monitor.placement = nil
                elseif x <= 4 and placement.preview and placement.valid then
                    local rect = placement.preview
                    if not Desktop.fits(rect, server.apps[win.appName], monitor) then
                        placement.valid, placement.error = false, "Does not fit"; return
                    end
                    local ok, err = api.placeWindow(win.id, rect.x, rect.y, rect.width, rect.height)
                    if ok then monitor.placement = nil else placement.error = tostring(err) end
                end
                return
            end
            if placement.kind == "move" then
                placement.preview = {x = math.max(1, math.min(x, monitor.width - win.width + 1)),
                    y = math.max(1, math.min(y, monitor.height - win.height)), width = win.width, height = win.height}
            elseif not placement.first then placement.first = {x = x, y = y}
            else
                placement.preview = {x = math.min(x, placement.first.x), y = math.min(y, placement.first.y),
                    width = math.abs(x - placement.first.x) + 1, height = math.abs(y - placement.first.y) + 1}
            end
            placement.valid = Desktop.fits(placement.preview, server.apps[win.appName], monitor) and true or false
            placement.error = placement.preview and not placement.valid and "Does not fit" or nil
            return
        end
        if y == monitor.height then
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
        local model = monitor.launcher and monitor or monitor.layoutMenu
        if model then
            for _, hit in ipairs(model.menuHits or {}) do
                if y == hit.y and x >= hit.x1 and x <= hit.x2 then
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
                            if mode == "custom" or mode == "move" then beginPlacement(monitor, win, mode)
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
        local list = windowsFor(id)
        for index = #list, 1, -1 do
            local win = list[index]
            if not win.minimized and not win.doesNotFit and x >= win.x and x < win.x + win.width
                and y >= win.y and y < win.y + win.height then
                if y == win.y then
                    local relative = x - win.x
                    if relative < 3 then api.closeWindow(win.id)
                    elseif relative < 6 then
                        focus(win); monitor.layoutMenu = {windowId = win.id, menuPage = 1}; server.save()
                    elseif relative < 9 then win.minimized = true; server.save()
                    else focus(win); beginPlacement(monitor, win, "move"); server.save() end
                    return
                end
                focus(win)
                if x > win.x and x < win.x + win.width - 1 and y < win.y + win.height - 1 then
                    local dialog = server.dialogs[win.id]
                    if dialog then
                        local action, address = Picker.touch(dialog, x - win.x, y - win.y)
                        if action == "cancel" then server.dialogs[win.id] = nil
                        elseif action == "selected" then
                            local ok, accepted, err = appCall(win.appName, "handleIOSelection", dialog.key,
                                address, state.appStates[win.appName], api, viewContext(win))
                            if ok and accepted ~= false then server.dialogs[win.id] = nil
                            else dialog.error = tostring(ok and err or accepted) end
                        end
                    else
                        local ok, handled, replacement = appCall(win.appName, "handleTouch", x - win.x, y - win.y,
                            win.width - 2, win.height - 2, state.appStates[win.appName], api, viewContext(win))
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
            local groups = {io = server.ioClients, monitor = server.monitors, sensor = server.sensorClients}
            local group = groups[message.clientType]
            if not group then return end
            for _, otherGroup in pairs(groups) do
                local other = otherGroup[id]
                if other and (otherGroup ~= group or (other.online and other.computerId ~= message.sender)) then
                    print("Duplicate clientId rejected: " .. id .. " (computer " .. message.sender .. ")")
                    return
                end
            end
            if message.clientType == "monitor" and (not integer(message.width, 1, 256)
                or not integer(message.height, 2, 128)) then return end
            local client = group[id]
            local reconnect = not client or not client.online or client.computerId ~= message.sender
            client = client or {inputs = {}, values = {}, revision = 0, ackedRevision = -1}
            client.computerId, client.channel, client.lastSeen, client.online = message.sender, replyChannel, now, true
            if reconnect then client.inputs, client.values = {}, {} end
            group[id] = client
            if message.clientType == "monitor" then
                client.width, client.height = message.width, message.height
                client.lastRender = nil -- Periodic full repaint also recovers a lost frame.
            elseif message.clientType == "io" then
                client.capabilities = {}
                if type(message.capabilities) == "table" then
                    for side, flags in pairs(message.capabilities) do
                        if sideSet[side] and type(flags) == "table" and flags.bundled and flags.digital then
                            client.capabilities[side] = true
                        end
                    end
                end
            end
            net.toClient(client, {type = "welcome", clientId = id, nonce = message.nonce, serverSession = server.session})
            if reconnect then print(message.clientType .. " connected: " .. id .. " (computer " .. message.sender .. ")") end
            if message.clientType == "io" then
                client.ackedRevision = -1
                server.syncIO(id, false)
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
            if registered(server.monitors, message, replyChannel) then
                touch(id, message.x, message.y)
                server.refreshMonitors(false)
            end
        elseif message.type == "resize" then
            local client = registered(server.monitors, message, replyChannel)
            if client and integer(message.width, 1, 256) and integer(message.height, 2, 128) then
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
                        print("Loaded app: " .. name)
                    else print("Cannot load app " .. name .. ": " .. tostring(app)) end
                end
            end
        end
        for _, name in ipairs(sortedKeys(server.apps)) do
            if isService(server.apps[name]) or hasViews(name) then startApp(name) end
        end
        net.ensureModem()
        print("SmartHome OS computer " .. net.id .. ", network " .. net.config.networkId)
        if not net.modem then print("Attach a wireless modem; waiting...") end
    end

    function server.tick(now)
        net.ensureModem()
        for _, group in ipairs({server.ioClients, server.monitors, server.sensorClients}) do
            for id, client in pairs(group) do
                if client.online and now - client.lastSeen >= config.clientTimeout then
                    client.online = false
                    print("Client offline: " .. id)
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
        for id, client in pairs(server.ioClients) do
            if client.online and client.ackedRevision ~= client.revision
                and now - (client.lastSent or -math.huge) >= config.retryInterval then server.syncIO(id, false) end
        end
        server.refreshMonitors(false)
        -- Keep checkpoints within one second even when an older config says 30.
        if now - server.lastSave >= math.min(config.saveInterval, 1) then server.save() end
    end

    function server.command(line)
        local args = {}
        for word in line:gmatch("%S+") do args[#args + 1] = word end
        local cmd = args[1]
        if not cmd then return {} end
        if cmd == "help" then return {
            "clients | inputs <client> | outputs | apps",
            "map <name> <client> <side> <color|digital>",
            "set <name> <on|off> | toggle <name>",
            "open <app> <monitor> | close <windowId>",
            "move <id> <x> <y> | resize <id> <width> <height>",
            "save | quit (saves and exits)",
        } end
        if cmd == "clients" then
            local lines = {}
            for _, item in ipairs(api.getClients()) do
                lines[#lines + 1] = item.id .. " " .. item.type .. " " .. (item.online and "ONLINE" or "offline")
                    .. " computer=" .. item.computerId
            end
            if #lines == 0 then lines[1] = "No clients connected yet" end
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
