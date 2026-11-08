-- User-wired Boolean circuits. The OS owns routing, persistence and popups.
local app = {title = "Logic Sandbox", minWidth = 12, minHeight = 6, preferredWidth = 37, preferredHeight = 15, backgroundService = true}
local appName = "logic_sandbox"
local kinds = {"Input", "AND", "OR", "NOT", "XOR", "Output"}
local function find(list, id)
    for i, item in ipairs(list or {}) do if item.id == id then return item, i end end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    return a and b and a.clientId == b.clientId and a.side == b.side and a.color == b.color
end
local function logical(node) return appName .. "_out_" .. node.id end
local function outputChange(node, remove)
    if remove then return {name = logical(node), remove = true} end
    return {name = logical(node), clientId = node.route.clientId, side = node.route.side, color = node.route.color, initialValue = false}
end
local function evaluate(circuit, api)
    local nodes, result, done = {}, {}, {}
    for _, node in ipairs(circuit.nodes) do nodes[node.id] = node end
    local function value(id)
        if not id or done[id] then return result[id] end
        local node = nodes[id]
        if not node then return nil end
        done[id] = true -- Any invalid cycle recovered from disk stays unknown.
        local v
        if node.kind == "Input" then
            if node.route then v = api.readInput(node.route) end
        else
            local a, b = value(node.a), value(node.b)
            if node.kind == "Output" then v = a
            elseif node.kind == "NOT" then if a ~= nil then v = not a end
            elseif node.kind == "AND" then
                if a == false or b == false then v = false
                elseif a == true and b == true then v = true end
            elseif node.kind == "OR" then
                if a == true or b == true then v = true
                elseif a == false and b == false then v = false end
            elseif a ~= nil and b ~= nil then v = a ~= b end
        end
        result[id] = v
        return v
    end
    for _, node in ipairs(circuit.nodes) do value(node.id) end
    return result
end

local function wouldCycle(circuit, from, target)
    local visited = {}
    local function walk(id)
        if not id or visited[id] then return false end
        if id == target then return true end
        visited[id] = true
        local node = find(circuit.nodes, id)
        return node and (walk(node.a) or walk(node.b))
    end
    return walk(from)
end
local function notifications(state, api)
    local entries = {}
    for _, circuit in ipairs(state.circuits) do
        for _, node in ipairs(circuit.nodes) do
            if node.alert then
                entries[#entries + 1] = {key = "logic_" .. node.id .. "_" .. node.alert, title = "Logic Sandbox",
                    message = circuit.name .. " / " .. node.name .. " ON"}
            end
        end
    end
    return api.setNotifications(appName, entries)
end
local last = {}
function app.init(state, api, context)
    assert(api.getUsedIO and api.ui.actionAt, "Logic Sandbox requires bundled-v39 OS")
    appName, last = context.appName, {}
    if not state.circuits then state.circuits, state.nextCircuit, state.nextNode, state.nextAlert = {}, 1, 1, 1 end
    local mapped, changes = {}, {}
    for _, item in ipairs(api.getOutputs()) do mapped[item.name] = item end
    for _, circuit in ipairs(state.circuits) do
        for _, node in ipairs(circuit.nodes) do
            if node.kind == "Output" then
                local existing = mapped[logical(node)]
                if circuit.enabled and node.route and not same(existing, node.route) then
                    changes[#changes + 1] = outputChange(node)
                elseif (not circuit.enabled or not node.route) and existing then changes[#changes + 1] = outputChange(node, true) end
            end
        end
    end
    if #changes > 0 then assert(api.updateOutputs(changes)) end
    notifications(state, api)
end
function app.ioRoutes(state)
    local result = {}
    for _, circuit in ipairs(state.circuits or {}) do
        for _, node in ipairs(circuit.nodes) do if node.route then
            result[#result + 1] = {clientId = node.route.clientId, side = node.route.side, color = node.route.color,
                direction = node.kind == "Input" and "input" or "output"}
        end end
    end
    return result
end
function app.background(dt, state, api)
    local changes, updates, nextLast, oldAlertId = {}, {}, {}, state.nextAlert
    local pendingCount = 0
    for _, circuit in ipairs(state.circuits) do
        for _, node in ipairs(circuit.nodes) do if node.alert then pendingCount = pendingCount + 1 end end
    end
    for _, circuit in ipairs(state.circuits) do
        if circuit.enabled then
            local values = evaluate(circuit, api)
            for _, node in ipairs(circuit.nodes) do
                local on = values[node.id]
                if node.kind == "Output" and node.route then
                    local wanted = on == true
                    nextLast[node.id] = wanted
                    if last[node.id] ~= wanted and api.getOutput(logical(node)) ~= wanted then
                        changes[#changes + 1] = {name = logical(node), value = wanted}
                    end
                end
                if node.popup and on ~= nil and on ~= node.high then
                    updates[#updates + 1] = {node = node, high = node.high, alert = node.alert}
                    node.high = on
                    if on and not node.alert and pendingCount < 128 then
                        node.alert, state.nextAlert = state.nextAlert, state.nextAlert + 1
                        pendingCount = pendingCount + 1
                    end
                end
                api.cooperate(24)
            end
        end
    end
    local ok, err = true
    if #changes > 0 then ok, err = api.updateOutputs(changes)
    elseif #updates > 0 then ok, err = api.save() end
    if not ok then
        state.nextAlert = oldAlertId
        for _, old in ipairs(updates) do old.node.high, old.node.alert = old.high, old.alert end
        api.log("Logic Sandbox output checkpoint: " .. tostring(err))
        return
    end
    last = nextLast
    if #updates > 0 then notifications(state, api) end
end
function app.handleNotification(key, state, api)
    for _, circuit in ipairs(state.circuits) do
        for _, node in ipairs(circuit.nodes) do
            if node.alert and key == "logic_" .. node.id .. "_" .. node.alert then
                local previous = node.alert
                node.alert = nil
                local ok, err = api.save()
                if not ok then node.alert = previous; return false, err end
                notifications(state, api)
                return true
            end
        end
    end
    return false, "Alert already closed"
end
local function notice(view, message, back)
    view.screen, view.message, view.back, view.pages = "message", tostring(message), back, {}
end
local function commit(state, api, view, mutate, changes)
    local before = copy(state)
    mutate()
    local ok, err
    if changes and #changes > 0 then ok, err = api.updateOutputs(changes) else ok, err = api.save() end
    if not ok then
        state.circuits, state.nextCircuit, state.nextNode = before.circuits, before.nextCircuit, before.nextNode
        notice(view, err, "home")
        return false, err
    end
    last = {}
    notifications(state, api)
    api.invalidateAppViews(appName)
    return true
end
local function keyboard(view, purpose, text, back)
    view.screen = "keyboard"
    view.keyboard = {purpose = purpose, draft = text, bank = 0, page = 1, back = back}
end
local function nodeLabel(node)
    return node and node.name or "Unwired"
end
local function build(w, h, state, api, view)
    local ui = api.ui.form(w, h, view, api.getAppColour(appName))
    local screen = view.screen or "home"
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    if not circuit and screen ~= "keyboard" and screen ~= "message" then screen = "home" end
    if not node and (screen == "node" or screen == "sources" or screen == "deleteNode") then screen = "circuit" end
    if screen == "home" then
        local rows = {{"+ New circuit", "newCircuit", nil, #state.circuits < 24}}
        for _, item in ipairs(state.circuits) do
            rows[#rows + 1] = {(item.enabled and "+ " or "- ") .. item.name, "open", item.id}
        end
        ui.menu("Logic Sandbox", rows, "circuits", {{"Close", "close"}})
    elseif screen == "circuit" then
        local values, rows = circuit.enabled and evaluate(circuit, api) or {}, {}
        for _, item in ipairs(circuit.nodes) do
            local value = values[item.id]
            local badge = not circuit.enabled and "- " or value == nil and "? " or value and "1 " or "0 "
            rows[#rows + 1] = {badge .. item.name, "selectNode", item.id}
        end
        if #rows == 0 then rows[1] = {"Add an input or gate", nil, nil, false} end
        ui.menu(circuit.name, rows, "nodes", {{"Back", "home"}, {"+ Add", "addNode", nil, #circuit.nodes < 48}, {"Menu", "circuitMenu"}})
    elseif screen == "circuitMenu" then
        ui.menu(circuit.name, {{circuit.enabled and "Disable circuit" or "Enable circuit", "toggleCircuit"},
            {"Rename circuit", "renameCircuit"}, {"Delete circuit", "deleteCircuit"}}, "circuitMenu", {{"Back", "circuit"}})
    elseif screen == "addNode" then
        local rows = {}
        for _, kind in ipairs(kinds) do rows[#rows + 1] = {kind, "createNode", kind} end
        ui.menu("Add logic node", rows, "nodeKinds", {{"Back", "circuit"}})
    elseif screen == "node" then
        local rows = {}
        if node.kind == "Input" or node.kind == "Output" then
            local label = node.route and api.clientName(node.route.clientId) .. " / " .. node.route.side
                .. " / " .. (node.route.color and api.ui.colourName(node.route.color) or "Digital") or "Select redstone"
            rows[#rows + 1] = {label, "route"}
            if node.route then rows[#rows + 1] = {"Clear routing", "clearRoute"} end
        end
        if node.kind ~= "Input" then rows[#rows + 1] = {"A " .. nodeLabel(find(circuit.nodes, node.a)), "source", "a"} end
        if node.kind ~= "Input" and node.kind ~= "Output" and node.kind ~= "NOT" then
            rows[#rows + 1] = {"B " .. nodeLabel(find(circuit.nodes, node.b)), "source", "b"}
        end
        rows[#rows + 1] = {node.popup and "Popup ON" or "Popup OFF", "popup"}
        rows[#rows + 1] = {"Rename node", "renameNode"}
        rows[#rows + 1] = {"Delete node", "deleteNode"}
        local title = node.name ~= node.kind and node.kind .. " / " .. node.name or node.kind
        ui.menu(title, rows, "node", {{"Back", "circuit"}})
    elseif screen == "sources" then
        local rows = {{"Unwired", "assignSource", 0}}
        for _, item in ipairs(circuit.nodes) do
            if item.kind ~= "Output" and not wouldCycle(circuit, item.id, node.id) then
                rows[#rows + 1] = {item.name .. " / " .. item.kind, "assignSource", item.id}
            end
        end
        ui.menu(node.name .. " / " .. view.port:upper(), rows, "sources", {{"Back", "node"}})
    elseif screen == "keyboard" then ui.keyboard(view.keyboard)
    elseif screen == "deleteCircuit" or screen == "deleteNode" then
        local target = screen == "deleteCircuit" and circuit or node
        local back = screen == "deleteCircuit" and "circuitMenu" or "node"
        ui.info("Delete?", {target.name}, screen, back)
        ui.footer({{"Cancel", back}, {"Delete", "confirmDelete", nil, true, 16384}})
    else ui.info("Logic Sandbox", {view.message or "Circuit changed"}, "message", view.back or "home") end
    return ui
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context.view).lines end
function app.handleIOSelection(key, address, state, api, context)
    local view = context.view
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    if not node or key ~= "node_" .. node.id then return false, "Node changed" end
    if node.kind == "Output" then
        for _, item in ipairs(state.circuits) do
            for _, other in ipairs(item.nodes) do
                if other ~= node and other.kind == "Output" and same(other.route, address) then
                    return false, "Already a Logic output"
                end
            end
        end
    end
    local route = copy(address)
    local changes = circuit.enabled and node.kind == "Output" and {
        {name = logical(node), clientId = route.clientId, side = route.side, color = route.color, initialValue = false},
    } or nil
    return commit(state, api, view, function() node.route = route end, changes)
end
function app.handleTouch(x, y, w, h, state, api, context)
    local view = context.view
    local action, value = api.ui.actionAt(build(w, h, state, api, view).hits, x, y)
    if not action then return false end
    local circuit, circuitIndex = find(state.circuits, view.circuitId)
    local node, nodeIndex = find(circuit and circuit.nodes, view.nodeId)
    if action == "page" then view.pages[value.key] = value.page
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "open" then view.circuitId, view.screen, view.pages = value, "circuit", {}
    elseif action == "selectNode" then view.nodeId, view.screen, view.pages.node = value, "node", 1
    elseif action == "newCircuit" then keyboard(view, action, "Circuit " .. state.nextCircuit, "home")
    elseif action == "renameCircuit" then keyboard(view, action, circuit.name, "circuitMenu")
    elseif action == "renameNode" then keyboard(view, action, node.name, "node")
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value, 32) then return true
    elseif action == "saveText" then
        local k = view.keyboard
        local text = k.draft:match("^%s*(.-)%s*$")
        if text == "" then return true end
        if k.purpose == "newCircuit" and #state.circuits < 24 then
            local id = state.nextCircuit
            if commit(state, api, view, function()
                state.circuits[#state.circuits + 1] = {id = id, name = text, nodes = {}, enabled = false}
                state.nextCircuit = id + 1
            end) then view.circuitId, view.screen = id, "circuit" end
        else
            local item = k.purpose == "renameCircuit" and circuit or k.purpose == "renameNode" and node
            if item and commit(state, api, view, function() item.name = text end) then view.screen = k.back
            elseif not item then view.screen = "home" end
        end
    elseif action == "toggleCircuit" then
        local changes = {}
        for _, item in ipairs(circuit.nodes) do
            if item.kind == "Output" and item.route then changes[#changes + 1] = outputChange(item, circuit.enabled) end
        end
        if commit(state, api, view, function()
            circuit.enabled = not circuit.enabled
            if not circuit.enabled then for _, item in ipairs(circuit.nodes) do item.high, item.alert = nil, nil end end
        end, changes) then view.screen = "circuit" end
    elseif action == "createNode" and #circuit.nodes < 48 then
        local id = state.nextNode
        if commit(state, api, view, function()
            circuit.nodes[#circuit.nodes + 1] = {id = id, kind = value, name = value .. " " .. id}
            state.nextNode = id + 1
        end) then view.nodeId, view.screen, view.pages.node = id, "node", 1 end
    elseif action == "source" then view.port, view.screen, view.pages.sources = value, "sources", 1
    elseif action == "assignSource" then
        if commit(state, api, view, function() node[view.port] = value ~= 0 and value or nil end) then view.screen = "node" end
    elseif action == "route" then
        local ok, err = api.pickIO(context.windowId, "node_" .. node.id, node.kind == "Input" and "input" or "output", node.route)
        if not ok then notice(view, err, "node") end
    elseif action == "clearRoute" then
        local changes = node.kind == "Output" and circuit.enabled and {outputChange(node, true)} or nil
        commit(state, api, view, function() node.route = nil end, changes)
    elseif action == "popup" then
        commit(state, api, view, function() node.popup, node.high, node.alert = not node.popup, nil, nil end)
    elseif action == "confirmDelete" then
        local whole = view.screen == "deleteCircuit"
        local changes = {}
        for _, item in ipairs(whole and circuit.nodes or {node}) do
            if item.kind == "Output" and item.route and circuit.enabled then changes[#changes + 1] = outputChange(item, true) end
        end
        if commit(state, api, view, function()
            if whole then table.remove(state.circuits, circuitIndex)
            else
                table.remove(circuit.nodes, nodeIndex)
                for _, item in ipairs(circuit.nodes) do
                    if item.a == node.id then item.a = nil end
                    if item.b == node.id then item.b = nil end
                end
            end
        end, changes) then view.screen = whole and "home" or "circuit" end
    else view.screen = action end
    api.invalidateAppViews(appName)
    return true
end
return app
