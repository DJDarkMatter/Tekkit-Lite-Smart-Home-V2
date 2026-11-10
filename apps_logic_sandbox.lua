-- User-wired Boolean circuits. The OS owns routing, persistence and popups.
local app = {title = "Logic Sandbox", minWidth = 12, minHeight = 6, preferredWidth = 37, preferredHeight = 15, backgroundService = true}
local Me = dofile("lib_me.lua")
local appName = "logic_sandbox"
local kinds = {"Input", "AND", "OR", "NOT", "XOR", "Output", "Item amount"}
local comparisons = {under = "<", over = ">", exact = "="}
local sources, previews, itemLists, nextWatch, nextRead = {}, {}, {}, 0, 0
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
local function sourceKey(binding)
    local card, targetType = binding.card or "", binding.targetType or ""
    local address = Me.sourceKey(binding)
    return #address .. ":" .. address .. #card .. ":" .. card .. targetType
end
local function stock(binding)
    local source = Me.address(binding) and sources[sourceKey(binding)]
    return source and source.snapshot or nil
end
local function itemCount(node)
    local rule = node.amount
    return rule and Me.count(stock(rule.sensor), rule.item.key)
end
local function readAmounts(state, api, now)
    local needed = {}
    local function include(binding)
        if Me.address(binding) then needed[sourceKey(binding)] = binding end
    end
    for _, circuit in ipairs(state.circuits) do
        if circuit.enabled then
            for _, node in ipairs(circuit.nodes) do
                if node.kind == "Item amount" and node.amount then include(node.amount.sensor) end
            end
        end
    end
    local visible = {}
    for id, preview in pairs(previews) do
        if preview.expires >= now then
            include(preview.binding)
            visible[id] = preview
        end
    end
    previews = visible
    local boots = next(needed) and Me.boots(api)
    local live = {}
    for key, binding in pairs(needed) do
        local source = sources[key]
        if not source then
            nextWatch = nextWatch + 1
            source = {watch = appName .. "_amount_" .. nextWatch, cache = {}}
        end
        api.watchSensor(source.watch, binding, {profile = "ae_items"})
        source.snapshot = Me.snapshot(source.cache, api, binding, boots)
        live[key] = source
        api.cooperate(24)
    end
    for key, source in pairs(sources) do if not live[key] then api.unwatchSensor(source.watch) end end
    sources = live
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
        elseif node.kind == "Item amount" then
            local count, rule = itemCount(node), node.amount
            if count ~= nil then
                if rule.operator == "under" then v = count < rule.threshold
                elseif rule.operator == "over" then v = count > rule.threshold
                else v = count == rule.threshold end
            end
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
    sources, previews, itemLists, nextWatch, nextRead = {}, {}, {}, 0, 0
    if not state.circuits then state.circuits, state.nextCircuit, state.nextNode, state.nextAlert = {}, 1, 1, 1 end
    local mapped, changes = {}, {}
    for _, item in ipairs(api.getOutputs()) do mapped[item.name] = item end
    for _, circuit in ipairs(state.circuits) do
        local usesStock = false
        for _, node in ipairs(circuit.nodes) do
            if node.kind == "Item amount" then usesStock = true; break end
        end
        for _, node in ipairs(circuit.nodes) do
            if node.kind == "Output" then
                local existing = mapped[logical(node)]
                if circuit.enabled and node.route and not same(existing, node.route) then
                    changes[#changes + 1] = outputChange(node)
                elseif existing then
                    if not circuit.enabled or not node.route then changes[#changes + 1] = outputChange(node, true)
                    elseif usesStock and existing.value then
                        -- Wait for live stock before restoring a stock circuit's output.
                        changes[#changes + 1] = {name = logical(node), value = false}
                    end
                end
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
    local now = os.clock()
    if now >= nextRead then
        readAmounts(state, api, now)
        nextRead = now + 0.5
    end
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
function app.onClose(state, api, context)
    previews[context.windowId], itemLists[context.windowId] = nil, nil
end
function app.shutdown(state, api)
    for _, source in pairs(sources) do api.unwatchSensor(source.watch) end
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
local function validAmount(rule)
    return Me.address(rule.sensor) and Me.itemValid(rule.item) and comparisons[rule.operator]
        and Me.integer(rule.threshold, 0, Me.MAX) or false
end
local function amountCaption(rule)
    return comparisons[rule.operator] .. " " .. Me.amount(rule.threshold)
end
local amountScreens = {amountEdit = true, amountOperator = true, amountList = true,
    amountFind = true, amountManual = true, amountNumber = true}
local function amountEditor(view, node)
    return node and node.kind == "Item amount" and view.amountDraft
        and view.amountNode == node.id and view.amountRevision == (node.amountRevision or 0)
end
local function clearAmountEditor(view, id)
    previews[id], itemLists[id] = nil, nil
    view.amountDraft, view.amountNode, view.amountRevision = nil, nil, nil
    view.manualItem, view.amountQuery, view.amountNumber = nil, nil, nil
end
local function drawItems(ui, w, h, view, id, api)
    local binding = view.amountDraft.sensor
    local snapshot = stock(binding)
    local rows = itemLists[id]
    if not rows and snapshot and snapshot.status == "ok" then
        rows = {}
        local query = (view.amountQuery or ""):lower()
        for _, item in pairs(snapshot.items) do
            local label = item.name:lower()
            if label:find(query, 1, true) or item.raw:lower():find(query, 1, true) then
                rows[#rows + 1] = {item = Me.identity(item), sort = label}
            end
            api.cooperate(32)
        end
        table.sort(rows, function(a, b)
            if a.sort ~= b.sort then return a.sort < b.sort end
            return a.item.key < b.item.key
        end)
        itemLists[id] = rows
    end
    rows = rows or {}
    ui.heading("Select item")
    local path = api.ui.breadcrumb({api.clientName(binding.clientId), binding.side, binding.target}, w, h)
    local start = path and 3 or 2
    if path then ui.put(1, 2, path, w) end
    local slots = h - start
    if #rows > slots then slots = slots - 1 end
    local first = ui.page("amountItems", #rows, slots, h - 1)
    for i = 1, slots do
        local row = rows[first + i]
        if row then
            local item, y = row.item, start + i - 1
            local count = Me.amount(Me.count(snapshot, item.key), math.floor(w / 2))
            local span = math.min(#count, math.floor(w / 2))
            local label = item.name .. (item.damage > 0 and (" [" .. item.damage .. "]") or "")
            ui.action(y, "", "amountItem", item)
            ui.put(1, y, label, w - span - 1)
            ui.put(w - span + 1, y, count, span)
        end
    end
    if #rows == 0 then
        ui.put(1, start, snapshot and (snapshot.status == "ok" and "No matching items" or snapshot.error or snapshot.status)
            or "Waiting for ME", w)
    end
    ui.footer({{"Back", "amountEdit"}, {"Find", "amountFind"}})
end
local function nodeLabel(node)
    return node and node.name or "Unwired"
end
local function build(w, h, state, api, context)
    local view, id = context.view, context.windowId
    local ui = api.ui.form(w, h, view, api.getAppColour(appName))
    local screen = view.screen or "home"
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    local k = view.keyboard
    if screen == "keyboard" and (not k or type(k.purpose) ~= "string" or (k.purpose == "renameCircuit" and not circuit)
        or (k.purpose == "renameNode" and not node)) then
        screen, view.keyboard = circuit and "circuit" or "home", nil
    end
    if amountScreens[screen] or (screen == "keyboard" and k.purpose:sub(1, 6) == "amount") then
        if not amountEditor(view, node) then
            clearAmountEditor(view, id)
            screen, view.keyboard = node and "node" or "circuit", nil
        elseif screen == "amountList" and not Me.address(view.amountDraft.sensor) then
            screen = "amountEdit"
        elseif (screen == "amountManual" and not view.manualItem) or (screen == "amountNumber" and not view.amountNumber) then
            screen = "amountEdit"
        end
    end
    if not circuit and screen ~= "keyboard" and screen ~= "message" then screen = "home" end
    if (screen == "node" or screen == "sources" or screen == "deleteNode") and not node then screen = "circuit" end
    if screen == "sources" and view.port ~= "a" and view.port ~= "b" then screen = "node" end
    view.screen = screen
    local rule = view.amountDraft
    local binding = rule and rule.sensor
    if amountScreens[screen] and binding then
        previews[id] = {binding = binding, expires = os.clock() + 4}
    else previews[id] = nil end
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
        if node.kind == "Item amount" then
            local configured = node.amount
            rows[#rows + 1] = {configured and "Edit count" or "Set item count", "editAmount"}
            if configured then
                rows[#rows + 1] = {configured.item.name .. " " .. amountCaption(configured), nil, nil, false}
                rows[#rows + 1] = {"Count " .. Me.amount(itemCount(node)), nil, nil, false}
            end
        elseif node.kind ~= "Input" then
            rows[#rows + 1] = {"A " .. nodeLabel(find(circuit.nodes, node.a)), "source", "a"}
        end
        if node.kind == "AND" or node.kind == "OR" or node.kind == "XOR" then
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
    elseif screen == "amountEdit" then
        ui.menu("Item amount", {{binding and "ME " .. api.clientName(binding.clientId) or "Select ME", "amountSensor"},
            {rule.item and rule.item.name or "Select item", "amountList", nil, binding ~= nil},
            {"Compare " .. comparisons[rule.operator], "amountOperator"},
            {"Level " .. Me.amount(rule.threshold), "editNumber", "threshold"}}, "amountEdit",
            {{"Cancel", "cancelAmount"}, {"Save", "saveAmount", nil, validAmount(rule)}})
    elseif screen == "amountOperator" then
        ui.menu("Compare count", {{"Under (<)", "setOperator", "under"}, {"Over (>)", "setOperator", "over"},
            {"Exactly (=)", "setOperator", "exact"}}, "amountOperator", {{"Back", "amountEdit"}})
    elseif screen == "amountList" then drawItems(ui, w, h, view, id, api)
    elseif screen == "amountFind" then
        ui.menu("Find item", {{"Search " .. (view.amountQuery or ""), "amountSearch"}, {"Refresh", "refreshItems"},
            {"Manual item", "newManualItem"}}, "amountFind", {{"Back", "amountList"}})
    elseif screen == "amountManual" then
        local m = view.manualItem
        ui.menu("Manual item", {{"Name " .. m.name, "manualText", "name"}, {"RawName " .. m.raw, "manualText", "raw"},
            {"Damage " .. m.damage, "editNumber", "damage"}}, "amountManual",
            {{"Back", "amountFind"}, {"Use", "useManualItem", nil, Me.textValue(m.raw, 256) and Me.textValue(m.name, 256)}})
    elseif screen == "amountNumber" then
        local n = view.amountNumber
        ui.numberPad(n.field == "damage" and "Damage" or "Item level", n.draft, n.back)
    elseif screen == "keyboard" then ui.keyboard(view.keyboard)
    elseif screen == "deleteCircuit" or screen == "deleteNode" then
        local target = screen == "deleteCircuit" and circuit or node
        local back = screen == "deleteCircuit" and "circuitMenu" or "node"
        ui.info("Delete?", {target.name}, screen, back)
        ui.footer({{"Cancel", back}, {"Delete", "confirmDelete", nil, true, 16384}})
    else ui.info("Logic Sandbox", {view.message or "Circuit changed"}, "message", view.back or "home") end
    return ui
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context).lines end
function app.handleSensorSelection(key, binding, state, api, context)
    local view = context.view
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    if not amountEditor(view, node) or key ~= "amount_" .. node.id or not Me.address(binding) then
        return false, "Item amount editor changed"
    end
    view.amountDraft.sensor, view.amountQuery, view.pages.amountItems = copy(binding), nil, nil
    itemLists[context.windowId] = nil
    view.screen = "amountEdit"
    api.invalidateAppViews(appName)
    return true
end
function app.handleIOSelection(key, address, state, api, context)
    local view = context.view
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    if not node or (node.kind ~= "Input" and node.kind ~= "Output") or key ~= "node_" .. node.id then return false, "Node changed" end
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
    local action, value = api.ui.actionAt(build(w, h, state, api, context).hits, x, y)
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
    elseif action == "editAmount" then
        clearAmountEditor(view, context.windowId)
        view.amountDraft = copy(node.amount or {operator = "under", threshold = 64})
        view.amountNode, view.amountRevision, view.screen = node.id, node.amountRevision or 0, "amountEdit"
    elseif action == "amountSensor" then
        local ok, err = api.pickSensor(context.windowId, "amount_" .. node.id, view.amountDraft.sensor, "ae")
        if not ok then notice(view, err, "amountEdit") end
    elseif action == "setOperator" then view.amountDraft.operator, view.screen = value, "amountEdit"
    elseif action == "amountItem" then view.amountDraft.item, view.screen = Me.identity(value), "amountEdit"
    elseif action == "amountSearch" then
        keyboard(view, action, view.amountQuery or "", "amountFind")
        view.keyboard.limit = 64
    elseif action == "refreshItems" then
        itemLists[context.windowId], view.pages.amountItems, view.screen = nil, 1, "amountList"
    elseif action == "newManualItem" then
        view.manualItem = view.amountDraft.item and Me.identity(view.amountDraft.item) or {name = "New item", raw = "", damage = 0}
        view.screen = "amountManual"
    elseif action == "manualText" then
        keyboard(view, "amountManualText", view.manualItem[value], "amountManual")
        view.keyboard.limit, view.keyboard.field = 256, value
    elseif action == "useManualItem" then
        local item = view.manualItem
        item.key = Me.itemKey(item.raw, item.damage, item.name)
        view.amountDraft.item, view.screen = Me.identity(item), "amountEdit"
    elseif action == "editNumber" then
        local number = value == "damage" and view.manualItem.damage or view.amountDraft.threshold
        view.amountNumber = {field = value, draft = Me.digits(number), back = view.screen}
        view.screen = "amountNumber"
    elseif action == "digit" then
        local n = view.amountNumber
        if value == "Clr" then n.draft = ""
        elseif value == "Del" then n.draft = n.draft:sub(1, -2)
        elseif #n.draft < 16 then n.draft = (n.draft == "0" and "" or n.draft) .. value end
    elseif action == "setNumber" then
        local n = view.amountNumber
        local number = tonumber(n.draft == "" and "0" or n.draft)
        if not Me.integer(number, 0, n.field == "damage" and 2147483647 or Me.MAX) then
            notice(view, "Use a whole number in range", "amountNumber")
        else
            local target = n.field == "damage" and view.manualItem or view.amountDraft
            target[n.field], view.screen = number, n.back
        end
    elseif action == "cancelAmount" then
        clearAmountEditor(view, context.windowId)
        view.screen = "node"
    elseif action == "saveAmount" then
        local draft = view.amountDraft
        if validAmount(draft) and commit(state, api, view, function()
            node.amount = copy(draft)
            node.amountRevision = (node.amountRevision or 0) + 1
        end) then
            clearAmountEditor(view, context.windowId)
            view.screen = "node"
        end
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value, view.keyboard.limit or 32) then return true
    elseif action == "saveText" then
        local k = view.keyboard
        local text = k.draft:match("^%s*(.-)%s*$")
        if k.purpose == "amountSearch" then
            view.amountQuery, view.pages.amountItems, view.screen = text, 1, "amountList"
            itemLists[context.windowId] = nil
        elseif k.purpose == "amountManualText" then
            view.manualItem[k.field], view.screen = text, k.back
        elseif text == "" then return true
        elseif k.purpose == "newCircuit" and #state.circuits < 24 then
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
