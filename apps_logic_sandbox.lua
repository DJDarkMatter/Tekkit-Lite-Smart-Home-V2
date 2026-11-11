-- User-wired Boolean circuits. The OS owns routing, persistence and popups.
local app = {title = "Logic Sandbox", minWidth = 12, minHeight = 6, preferredWidth = 37, preferredHeight = 15, backgroundService = true}
local Me = dofile("lib_me.lua")
local appName = "logic_sandbox"
local kinds = {"Input", "Item amount", "AND", "OR", "NOT", "XOR", "Delay", "Sequence", "Output",
    "Wait", "Set output", "Alarm", "Output target"}
local comparisons = {under = "<", over = ">", exact = "="}
local timedKinds = {Delay = true, Sequence = true}
local actionKinds = {Wait = true, ["Set output"] = true, Alarm = true}
local maxSteps = 24
local sources, previews, itemLists, nextWatch, nextRead = {}, {}, {}, 0, 0
local timing = {}
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
local function isOutput(node) return node.kind == "Output" or node.kind == "Output target" end
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
local function alarmName(circuit, node) return node.alarmName or circuit.name end
local function alertKey(node) return "logic_" .. (node.alertNodeId or node.id) .. "_" .. node.alert end
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
local function timedValue(node, input, nodes, api, now, plan)
    local run = timing[node.id]
    local revision = node.timingRevision or 0
    if run and run.revision ~= revision then run = nil end
    if not now then
        if run then return run.value end
        return nil
    end
    run = run and copy(run) or {revision = revision}
    if node.kind == "Delay" then
        if input == true then
            run.deadline = run.deadline or now + math.ceil((node.delayHundredths or 50) / 5) / 20
            run.value = now + 0.000001 >= run.deadline
            if not run.value then api.wakeAt(run.deadline) end
        else run.deadline, run.value = nil, input end
    else
        if input ~= nil then
            if input and not run.high and not run.step then run.step = 1 end
            run.high = input
            if run.value == nil then run.value = false end
        end
        if run.deadline and now + 0.000001 >= run.deadline then run.deadline = nil end
        while run.step and not run.deadline do
            local blockId = node.steps and node.steps[run.step]
            if not blockId then run.step = nil
            else
                run.step = run.step + 1
                local block = nodes[blockId]
                if block and block.kind == "Wait" then
                    run.deadline = now + math.ceil((block.waitHundredths or 50) / 5) / 20
                elseif block and block.kind == "Set output" then
                    local target = nodes[block.targetId]
                    if target and target.kind == "Output target" then plan.outputs[target.id] = block.on == true end
                elseif block and block.kind == "Alarm" then plan.alarms[block.id] = true end
            end
        end
        if run.value ~= nil then run.value = run.step ~= nil end
        if run.deadline then api.wakeAt(run.deadline) end
    end
    plan.timing[node.id] = run
    return run.value
end
local function evaluate(circuit, api, now, plan)
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
            if timedKinds[node.kind] then v = timedValue(node, a, nodes, api, now, plan)
            elseif node.kind == "Output" then v = a
            elseif node.kind == "Output target" and node.route then v = api.getOutput(logical(node))
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
                local message = node.kind == "Alarm" and alarmName(circuit, node)
                    or circuit.name .. " / " .. node.name .. " ON"
                entries[#entries + 1] = {key = alertKey(node), title = "Alarm", message = message}
            end
        end
    end
    return api.setNotifications(appName, entries)
end
local last = {}
function app.init(state, api, context)
    assert(api.wakeAt and api.ui.durationHundredths, "Logic Sandbox requires bundled-v42 OS; run inst server")
    appName, last, timing = context.appName, {}, {}
    sources, previews, itemLists, nextWatch, nextRead = {}, {}, {}, 0, 0
    if not state.circuits then state.circuits, state.nextCircuit, state.nextNode, state.nextAlert = {}, 1, 1, 1 end
    local before, migrated = Me.copy(state), false
    for _, circuit in ipairs(state.circuits) do
        local count = #circuit.nodes
        for index = 1, count do
            local node = circuit.nodes[index]
            if node.kind == "Alarm" then
                if not node.alarmName and node.name ~= "Alarm " .. node.id then
                    node.alarmName, migrated = node.name, true
                end
            elseif node.kind == "Item amount" and (node.popup or node.alert) then
                local ruleId, alarmId = state.nextNode, state.nextNode + 1
                circuit.nodes[#circuit.nodes + 1] = {id = ruleId, kind = "Sequence", name = "Rule " .. ruleId,
                    a = node.id, steps = {alarmId}}
                circuit.nodes[#circuit.nodes + 1] = {id = alarmId, kind = "Alarm", name = "Alarm " .. alarmId,
                    alarmName = circuit.name .. " / " .. node.name .. " ON", alert = node.alert,
                    alertNodeId = node.alert and node.id or nil}
                timing[ruleId] = {revision = 0, high = node.high}
                state.nextNode = alarmId + 1
                node.popup, node.high, node.alert = nil, nil, nil
                migrated = true
            end
        end
    end
    local mapped, changes = {}, {}
    for _, item in ipairs(api.getOutputs()) do mapped[item.name] = item end
    for _, circuit in ipairs(state.circuits) do
        local needsFreshState = false
        for _, node in ipairs(circuit.nodes) do
            if node.kind == "Item amount" or timedKinds[node.kind] then needsFreshState = true; break end
        end
        for _, node in ipairs(circuit.nodes) do
            if isOutput(node) then
                local existing = mapped[logical(node)]
                if circuit.enabled and node.route and not same(existing, node.route) then
                    changes[#changes + 1] = outputChange(node)
                elseif existing then
                    if not circuit.enabled or not node.route then changes[#changes + 1] = outputChange(node, true)
                    elseif (needsFreshState or node.kind == "Output target") and existing.value then
                        -- Wait for fresh stock or a new timed run after startup.
                        changes[#changes + 1] = {name = logical(node), value = false}
                    end
                end
            end
        end
    end
    if #changes > 0 or migrated then
        local ok, err
        if #changes > 0 then ok, err = api.updateOutputs(changes) else ok, err = api.save() end
        if not ok then Me.restore(state, before); error(err, 0) end
    end
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
    local plan = {timing = {}, alarms = {}, outputs = {}}
    local pendingCount = 0
    for _, circuit in ipairs(state.circuits) do
        for _, node in ipairs(circuit.nodes) do if node.alert then pendingCount = pendingCount + 1 end end
    end
    for _, circuit in ipairs(state.circuits) do
        if circuit.enabled then
            local values = evaluate(circuit, api, now, plan)
            for _, node in ipairs(circuit.nodes) do
                local on = values[node.id]
                if node.kind == "Output" and node.route then
                    local wanted = on == true
                    nextLast[node.id] = wanted
                    if last[node.id] ~= wanted and api.getOutput(logical(node)) ~= wanted then
                        changes[#changes + 1] = {name = logical(node), value = wanted}
                    end
                elseif node.kind == "Output target" and node.route then
                    local wanted = plan.outputs[node.id]
                    if wanted ~= nil and api.getOutput(logical(node)) ~= wanted then
                        changes[#changes + 1] = {name = logical(node), value = wanted}
                    end
                end
                local changed = node.popup and on ~= nil and on ~= node.high
                local raise = (changed and on or plan.alarms[node.id]) and not node.alert and pendingCount < 128
                if changed or raise then
                    updates[#updates + 1] = {node = node, high = node.high, alert = node.alert}
                    if changed then node.high = on end
                    if raise then
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
    last, timing = nextLast, plan.timing
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
            if node.alert and key == alertKey(node) then
                local previous, previousNode = node.alert, node.alertNodeId
                node.alert, node.alertNodeId = nil, nil
                local ok, err = api.save()
                if not ok then node.alert, node.alertNodeId = previous, previousNode; return false, err end
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
local function nodeLabel(node, index)
    if not node then return "Unwired" end
    local generated = node.kind == "Sequence" and "Rule" or node.kind
    local label = node.name
    if label == generated .. " " .. node.id then label = node.kind == "Sequence" and "If / Then" or node.kind
    elseif node.kind == "Alarm" then label = "Alarm - " .. label end
    return (index or node.id) .. " " .. label
end
local function setupTips(circuit, api)
    local nodes, actions, tips, hasRule = {}, {}, {}, false
    for _, node in ipairs(circuit.nodes) do
        nodes[node.id] = node
        if node.kind == "Sequence" then
            hasRule = true
            for _, id in ipairs(node.steps or {}) do actions[id] = true end
        end
    end
    for index, node in ipairs(circuit.nodes) do
        local title, message
        if node.kind == "Item amount" and (not node.amount or not validAmount(node.amount)) then
            title, message = "Choose ME item", "Open Set item count. Select the ME source, item, comparison and level, then Save."
        elseif node.kind == "Input" and not node.route then
            title, message = "Choose input", "Use Select redstone to choose the IO client, side and wire for this input."
        elseif node.kind == "Sequence" and not nodes[node.a] then
            title, message = "Choose When", "Open When and select the condition that should start this If / Then rule."
        elseif node.kind == "Sequence" and #(node.steps or {}) == 0 then
            title, message = "Add Then blocks", "Open Then blocks and + Block to add the actions this rule should run."
        elseif actionKinds[node.kind] and not actions[node.id] then
            if hasRule then
                title, message = "Add action to rule", "This action runs inside If / Then. Open that rule's Then blocks, tap + Block, and select this action."
            else
                title, message = "Add If / Then", "Add an If / Then block. Choose its When condition, then put this action in Then blocks."
            end
        elseif node.kind == "Set output" and not (nodes[node.targetId] and nodes[node.targetId].kind == "Output target") then
            title, message = "Choose target", "Use Choose target to select or create the output target this action will set."
        elseif isOutput(node) and not node.route then
            title, message = "Choose output", "Use Select redstone to choose the IO client, side and wire for this output."
        elseif (node.kind == "Output" or node.kind == "Delay" or node.kind == "NOT") and not nodes[node.a] then
            title, message = "Choose source", "Select the source under From, When or A to connect this block to a condition."
        elseif (node.kind == "AND" or node.kind == "OR" or node.kind == "XOR") and (not nodes[node.a] or not nodes[node.b]) then
            title, message = "Connect A and B", "Select both A and B sources so this gate can combine their conditions."
        end
        if title then tips[#tips + 1] = {id = node.id, label = index .. " " .. title, message = message} end
        api.cooperate(24)
    end
    return tips
end
local function routeLabel(api, route)
    if not route then return "Select redstone" end
    return api.clientName(route.clientId) .. " / " .. route.side .. " / "
        .. (route.color and api.ui.colourName(route.color) or "Digital")
end
local function actionLabel(api, circuit, block)
    if not block then return "Missing block" end
    if block.kind == "Wait" then return "Wait " .. api.ui.seconds(block.waitHundredths or 50) .. "s" end
    if block.kind == "Set output" then
        return "Set " .. nodeLabel(find(circuit.nodes, block.targetId)) .. (block.on and " ON" or " OFF")
    end
    if block.kind == "Alarm" then return "Alarm / " .. alarmName(circuit, block) end
    return block.name
end
local function flowLines(circuit, api)
    local rows = {}
    for index, node in ipairs(circuit.nodes) do
        local a, b = nodeLabel(find(circuit.nodes, node.a)), nodeLabel(find(circuit.nodes, node.b))
        local kind, detail = node.kind
        if kind == "Input" then detail = routeLabel(api, node.route)
        elseif kind == "Item amount" then detail = node.amount and (node.amount.item.name .. " " .. amountCaption(node.amount)) or "Select ME item"
        elseif kind == "NOT" then detail = "NOT " .. a
        elseif kind == "Delay" then detail = "Wait " .. api.ui.seconds(node.delayHundredths or 50) .. "s while " .. a .. " is ON"
        elseif kind == "Sequence" then detail = "IF " .. a .. " goes ON THEN"
        elseif kind == "Output" then detail = a .. " -> " .. routeLabel(api, node.route)
        elseif kind == "Output target" then detail = routeLabel(api, node.route)
        elseif actionKinds[kind] then detail = actionLabel(api, circuit, node)
        else detail = a .. " " .. kind .. " " .. b end
        rows[#rows + 1] = nodeLabel(node, index) .. " = " .. detail
        if kind == "Sequence" then
            for index, id in ipairs(node.steps) do
                rows[#rows + 1] = index .. ". " .. actionLabel(api, circuit, find(circuit.nodes, id))
            end
        end
        api.cooperate(24)
    end
    if #rows == 0 then rows[1] = "Add nodes to build a rule" end
    return rows
end
local sequenceScreens = {steps = true, addStep = true, step = true, removeStep = true}
local function editTime(view, api, node, hundredths, field)
    view.time = {draft = api.ui.seconds(hundredths), field = field, revision = node.timingRevision or 0}
    view.screen = "timeNumber"
end
local function retime(node)
    node.timingRevision = (node.timingRevision or 0) + 1
end
local function build(w, h, state, api, context)
    local view, id = context.view, context.windowId
    local ui = api.ui.form(w, h, view, api.getAppColour(appName))
    local screen = view.screen or "home"
    local circuit = find(state.circuits, view.circuitId)
    local node = find(circuit and circuit.nodes, view.nodeId)
    local k = view.keyboard
    if screen == "keyboard" and (not k or type(k.purpose) ~= "string" or (k.purpose == "renameCircuit" and not circuit)
        or ((k.purpose == "renameNode" or k.purpose == "renameAlarm") and not node)) then
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
    if (screen == "node" or screen == "sources" or screen == "targets" or screen == "deleteNode") and not node then screen = "circuit" end
    if sequenceScreens[screen] and not (node and node.kind == "Sequence") then screen = node and "node" or "circuit" end
    if screen == "addStep" and #node.steps >= maxSteps then screen = "steps" end
    if (screen == "step" or screen == "removeStep") and
        (view.stepRevision ~= (node.timingRevision or 0) or not find(circuit.nodes, node.steps[view.stepIndex])) then screen = "steps" end
    local time = view.time
    if screen == "timeNumber" then
        local field = node and (node.kind == "Delay" and "delayHundredths" or node.kind == "Wait" and "waitHundredths")
        if not field or not time or time.field ~= field or time.revision ~= (node.timingRevision or 0) then
            screen = node and "node" or "circuit"
        end
    end
    if not circuit and screen == "circuit" then screen = "home" end
    if screen == "sources" and view.port ~= "a" and view.port ~= "b" then screen = "node" end
    view.screen = screen
    local tips = circuit and setupTips(circuit, api) or {}
    local rule = view.amountDraft
    local binding = rule and rule.sensor
    local previewBinding = amountScreens[screen] and binding
        or screen == "node" and node.kind == "Item amount" and node.amount and node.amount.sensor
    if previewBinding then
        previews[id] = {binding = previewBinding, expires = os.clock() + 4}
    else previews[id] = nil end
    if screen == "home" then
        local rows = {{"+ New circuit", "newCircuit", nil, #state.circuits < 24}}
        for _, item in ipairs(state.circuits) do
            rows[#rows + 1] = {item.name .. (item.enabled and " [ON]" or " [OFF]"), "open", item.id}
        end
        ui.menu("Logic Sandbox", rows, "circuits", {{"Close", "close"}})
    elseif screen == "circuit" then
        local values, rows = circuit.enabled and evaluate(circuit, api) or {}, {}
        rows[1] = {circuit.enabled and "ON - Disable" or "OFF - Enable", "toggleCircuit"}
        if #tips > 0 then rows[#rows + 1] = {"Setup tips (" .. #tips .. ")", "setup"} end
        for index, item in ipairs(circuit.nodes) do
            local value = values[item.id]
            local label, status = nodeLabel(item, index), ""
            if actionKinds[item.kind] then status = item.alert and "Alert" or "Action"
            elseif circuit.enabled then
                if item.kind == "Sequence" then status = value == nil and "Waiting" or value and "Running" or "Ready"
                else status = value == nil and "Waiting" or value and "ON" or "OFF" end
            end
            local gap = w - #label - #status
            if status ~= "" and gap >= 2 then label = label .. string.rep(" ", gap) .. status end
            if #label < w then label = label .. string.rep(" ", w - #label) end
            rows[#rows + 1] = {label, "selectNode", item.id}
        end
        if #circuit.nodes == 0 then rows[#rows + 1] = {"Add a node", nil, nil, false} end
        local footer = {{"Back", "home"}, {"+ Add", "addNode", nil, #circuit.nodes < 48}}
        if w >= 24 then footer[#footer + 1] = {"Flow", "flow"} end
        footer[#footer + 1] = {"Menu", "circuitMenu"}
        ui.menu(circuit.name, rows, "nodes", footer)
    elseif screen == "circuitMenu" then
        local rows = {{circuit.enabled and "Disable circuit" or "Enable circuit", "toggleCircuit"},
            {"Check setup", "setup"}, {"Rename circuit", "renameCircuit"}, {"Delete circuit", "deleteCircuit"}}
        if w < 24 then table.insert(rows, 1, {"View flow", "flow"}) end
        ui.menu(circuit.name, rows, "circuitMenu", {{"Back", "circuit"}})
    elseif screen == "setup" then
        local rows = {}
        for _, tip in ipairs(tips) do rows[#rows + 1] = {tip.label, "tip", tip.id} end
        if #rows > 0 then ui.menu("Setup tips", rows, "setup", {{"Back", "circuit"}})
        else ui.info("Check setup", {"Connections are set. Live readings still depend on the selected clients."}, "setup", "circuit") end
    elseif screen == "tip" then
        local tip = find(tips, view.tipNode)
        if tip then
            ui.info("Setup tip", {nodeLabel(find(circuit.nodes, tip.id)), tip.message}, "tip", "setup")
            ui.footer({{"Back", "setup"}, {"Edit", "editTip", tip.id}})
        else ui.info("Check setup", {"This connection is now set."}, "tip", "setup") end
    elseif screen == "flow" then ui.info("Circuit flow", flowLines(circuit, api), "flow", "circuit")
    elseif screen == "addNode" then
        local rows = {}
        for _, kind in ipairs(kinds) do
            local label = kind == "Sequence" and "If / Then" or kind == "Input" and w >= 14 and "Redstone input"
                or kind == "Output" and w >= 15 and "Redstone output" or kind
            rows[#rows + 1] = {label, "createNode", kind}
        end
        ui.menu("Add logic node", rows, "nodeKinds", {{"Back", "circuit"}})
    elseif screen == "node" then
        local rows = {}
        if node.kind == "Input" or isOutput(node) then
            rows[#rows + 1] = {routeLabel(api, node.route), "route"}
            if node.route then rows[#rows + 1] = {"Clear routing", "clearRoute"} end
        end
        if node.kind == "Item amount" then
            local configured = node.amount
            rows[#rows + 1] = {configured and "Edit count" or "Set item count", "editAmount"}
            if configured then
                rows[#rows + 1] = {configured.item.name .. " " .. amountCaption(configured), nil, nil, false}
                rows[#rows + 1] = {"Count " .. Me.amount(itemCount(node)), nil, nil, false}
                local snapshot = stock(configured.sensor)
                if not snapshot or snapshot.status ~= "ok" then
                    rows[#rows + 1] = {snapshot and (snapshot.error or snapshot.status) or "Waiting for ME", nil, nil, false}
                end
            end
        elseif node.kind ~= "Input" and node.kind ~= "Output target" and not actionKinds[node.kind] then
            local label = timedKinds[node.kind] and "When " or node.kind == "Output" and "From " or "A "
            rows[#rows + 1] = {label .. nodeLabel(find(circuit.nodes, node.a)), "source", "a"}
        end
        if node.kind == "AND" or node.kind == "OR" or node.kind == "XOR" then
            rows[#rows + 1] = {"B " .. nodeLabel(find(circuit.nodes, node.b)), "source", "b"}
        end
        if node.kind == "Delay" or node.kind == "Wait" then
            rows[#rows + 1] = {"Wait " .. api.ui.seconds((node.kind == "Delay" and node.delayHundredths or node.waitHundredths) or 50) .. "s", "editTime"}
        elseif node.kind == "Sequence" then
            rows[#rows + 1] = {"Then blocks (" .. #node.steps .. ")", "steps"}
        elseif node.kind == "Set output" then
            local target = find(circuit.nodes, node.targetId)
            rows[#rows + 1] = {target and "Target " .. target.name or "Choose target", "targets"}
            rows[#rows + 1] = {node.on and "Set ON" or "Set OFF", "outputLevel"}
            if target then rows[#rows + 1] = {routeLabel(api, target.route), "routeTarget"} end
        end
        if node.kind == "Delay" then rows[#rows + 1] = {"+ Link output", "addLinkedOutput", nil, #circuit.nodes < 48} end
        if not actionKinds[node.kind] and node.kind ~= "Output target" and node.kind ~= "Item amount" then
            rows[#rows + 1] = {node.popup and "Popup ON" or "Popup OFF", "popup"}
        end
        if node.kind == "Alarm" then rows[#rows + 1] = {"Name " .. alarmName(circuit, node), "renameAlarm"}
        else rows[#rows + 1] = {"Rename node", "renameNode"} end
        if (node.kind == "Alarm" or node.kind == "Item amount") and find(tips, node.id) then
            rows[#rows + 1] = {"Setup tip", "tip", node.id}
        end
        rows[#rows + 1] = {"Delete node", "deleteNode"}
        local title = node.kind == "Sequence" and "If / Then" or node.kind
        if node.name ~= title then title = title .. " / " .. node.name end
        local rule = actionKinds[node.kind] and find(circuit.nodes, view.ruleId)
        ui.menu(title, rows, "node", {{rule and "Rule" or "Back", rule and "returnRule" or "circuit"}})
    elseif screen == "sources" then
        local rows = {{"Unwired", "assignSource", 0}}
        for index, item in ipairs(circuit.nodes) do
            if not isOutput(item) and not actionKinds[item.kind] and not wouldCycle(circuit, item.id, node.id) then
                rows[#rows + 1] = {nodeLabel(item, index), "assignSource", item.id}
            end
        end
        ui.menu(node.name .. " / " .. view.port:upper(), rows, "sources", {{"Back", "node"}})
    elseif screen == "targets" then
        local rows = {{"+ New target", "newTarget", nil, #circuit.nodes < 48}}
        for _, item in ipairs(circuit.nodes) do
            if item.kind == "Output target" then rows[#rows + 1] = {item.name, "chooseTarget", item.id} end
        end
        ui.menu("Output target", rows, "targets", {{"Back", "node"}})
    elseif screen == "steps" then
        local rows = {}
        for index, id in ipairs(node.steps) do
            rows[#rows + 1] = {index .. ". " .. actionLabel(api, circuit, find(circuit.nodes, id)), "selectStep", index}
        end
        if #rows == 0 then rows[1] = {"Add a block", nil, nil, false} end
        ui.menu("IF " .. nodeLabel(find(circuit.nodes, node.a)), rows, "steps",
            {{"Back", "node"}, {"+ Block", "addStep", nil, #node.steps < maxSteps}})
    elseif screen == "addStep" then
        local rows = {}
        for _, kind in ipairs({"Wait", "Set output", "Alarm"}) do
            rows[#rows + 1] = {"+ " .. kind, "createAction", kind, #circuit.nodes < 48}
        end
        for _, block in ipairs(circuit.nodes) do
            if actionKinds[block.kind] then
                local label = w >= 28 and block.kind ~= "Alarm" and block.name .. " / " .. actionLabel(api, circuit, block) or block.name
                rows[#rows + 1] = {label, "useAction", block.id}
            end
        end
        ui.menu("Then add block", rows, "addStep", {{"Back", "steps"}})
    elseif screen == "step" then
        local index, rows = view.stepIndex, {}
        local block = find(circuit.nodes, node.steps[index])
        rows[#rows + 1] = {"Edit block", "editAction"}
        rows[#rows + 1] = {"Move earlier", "moveStep", -1, index > 1}
        rows[#rows + 1] = {"Move later", "moveStep", 1, index < #node.steps}
        rows[#rows + 1] = {"Remove step", "removeStep"}
        ui.menu(actionLabel(api, circuit, block), rows, "step", {{"Back", "steps"}})
    elseif screen == "removeStep" then
        ui.info("Remove from rule?", {actionLabel(api, circuit, find(circuit.nodes, node.steps[view.stepIndex]))}, "removeStep", "step")
        ui.footer({{"Cancel", "step"}, {"Remove", "confirmStep", nil, true, 16384}})
    elseif screen == "timeNumber" then
        ui.numberPad("Wait (s)", time.draft, "node", true)
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
    if node and node.kind == "Set output" then node = find(circuit.nodes, node.targetId) end
    if not node or (node.kind ~= "Input" and not isOutput(node)) or key ~= "node_" .. node.id then return false, "Node changed" end
    if isOutput(node) then
        for _, item in ipairs(state.circuits) do
            for _, other in ipairs(item.nodes) do
                if other ~= node and isOutput(other) and same(other.route, address) then
                    return false, "Already a Logic output"
                end
            end
        end
    end
    local route = copy(address)
    local changes = circuit.enabled and isOutput(node) and {
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
    elseif action == "tip" then view.tipNode, view.screen, view.pages.tip = value, "tip", 1
    elseif action == "editTip" then view.nodeId, view.screen, view.ruleId, view.pages.node = value, "node", nil, 1
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "open" then view.circuitId, view.screen, view.pages, view.ruleId = value, "circuit", {}, nil
    elseif action == "addNode" then view.pages.nodeKinds, view.screen = 1, "addNode"
    elseif action == "addStep" then view.pages.addStep, view.screen = 1, "addStep"
    elseif action == "selectNode" then view.nodeId, view.screen, view.pages.node, view.ruleId = value, "node", 1, nil
    elseif action == "newCircuit" then keyboard(view, action, "Circuit " .. state.nextCircuit, "home")
    elseif action == "renameCircuit" then keyboard(view, action, circuit.name, "circuitMenu")
    elseif action == "renameNode" then keyboard(view, action, node.name, "node")
    elseif action == "renameAlarm" then keyboard(view, action, node.alarmName or "", "node")
    elseif action == "editTime" then
        local field = node.kind == "Delay" and "delayHundredths" or "waitHundredths"
        editTime(view, api, node, node[field] or 50, field)
    elseif action == "useAction" and #node.steps < maxSteps then
        if commit(state, api, view, function()
            node.steps[#node.steps + 1] = value
            retime(node)
        end) then view.screen = "steps" end
    elseif action == "selectStep" then
        view.stepIndex, view.stepRevision, view.screen = value, node.timingRevision or 0, "step"
    elseif action == "editAction" then
        view.ruleId, view.nodeId, view.screen, view.pages.node = node.id, node.steps[view.stepIndex], "node", 1
    elseif action == "returnRule" then
        view.nodeId, view.screen, view.ruleId = view.ruleId, "steps", nil
    elseif action == "chooseTarget" then
        if commit(state, api, view, function() node.targetId = value end) then view.screen = "node" end
    elseif action == "outputLevel" then
        commit(state, api, view, function() node.on = not node.on end)
    elseif action == "moveStep" or action == "confirmStep" then
        local index = view.stepIndex
        if commit(state, api, view, function()
            local step = table.remove(node.steps, index)
            if action == "moveStep" then table.insert(node.steps, index + value, step) end
            retime(node)
        end) then view.screen = "steps" end
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
    elseif action == "digit" and view.screen == "timeNumber" then
        view.time.draft = api.ui.editNumber(view.time.draft, value, 12)
    elseif action == "setNumber" and view.screen == "timeNumber" then
        local time = view.time
        local hundredths = api.ui.durationHundredths(time.draft, 1)
        if not hundredths then notice(view, "Use positive seconds with up to two decimal places", "timeNumber")
        elseif commit(state, api, view, function()
            node[time.field] = hundredths
            retime(node)
        end) then view.screen, view.time = "node", nil end
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
        elseif k.purpose == "renameAlarm" or k.purpose == "renameNode" and node.kind == "Alarm" then
            if commit(state, api, view, function()
                node.alarmName = text ~= "" and text or nil
                node.name = node.alarmName or "Alarm " .. node.id
            end) then view.screen = k.back end
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
            if isOutput(item) and item.route then changes[#changes + 1] = outputChange(item, circuit.enabled) end
        end
        if commit(state, api, view, function()
            circuit.enabled = not circuit.enabled
            if not circuit.enabled then for _, item in ipairs(circuit.nodes) do item.high, item.alert, item.alertNodeId = nil, nil, nil end end
        end, changes) then
            for _, item in ipairs(circuit.nodes) do timing[item.id] = nil end
            view.screen = "circuit"
        end
    elseif (action == "createNode" or action == "addLinkedOutput" or action == "newTarget" or action == "createAction")
        and #circuit.nodes < 48 then
        local id = state.nextNode
        local source = action == "addLinkedOutput" and node.id or nil
        local kind = source and "Output" or action == "newTarget" and "Output target" or value
        local label = kind == "Sequence" and "Rule" or kind
        local newNode = {id = id, kind = kind, name = label .. " " .. id, a = source,
            steps = kind == "Sequence" and {} or nil, on = kind == "Set output" and true or nil}
        if commit(state, api, view, function()
            circuit.nodes[#circuit.nodes + 1] = newNode
            state.nextNode = id + 1
            if action == "newTarget" then node.targetId = id
            elseif action == "createAction" then
                node.steps[#node.steps + 1] = id
                retime(node)
            end
        end) then
            if action ~= "newTarget" then
                view.nodeId = id
                view.ruleId = action == "createAction" and node.id or nil
            end
            view.screen, view.pages.node = "node", 1
            if source or action == "newTarget" then
                local ok, err = api.pickIO(context.windowId, "node_" .. id, "output")
                if not ok then notice(view, err, "node") end
            end
        end
    elseif action == "source" then view.port, view.screen, view.pages.sources = value, "sources", 1
    elseif action == "assignSource" then
        if commit(state, api, view, function()
            local source = value ~= 0 and value or nil
            if timedKinds[node.kind] and node[view.port] ~= source then retime(node) end
            node[view.port] = source
        end) then view.screen = "node" end
    elseif action == "route" or action == "routeTarget" then
        local target = action == "routeTarget" and find(circuit.nodes, node.targetId) or node
        local ok, err = api.pickIO(context.windowId, "node_" .. target.id, target.kind == "Input" and "input" or "output", target.route)
        if not ok then notice(view, err, "node") end
    elseif action == "clearRoute" then
        local changes = isOutput(node) and circuit.enabled and {outputChange(node, true)} or nil
        commit(state, api, view, function() node.route = nil end, changes)
    elseif action == "popup" and node.kind ~= "Item amount" then
        commit(state, api, view, function() node.popup, node.high, node.alert = not node.popup, nil, nil end)
    elseif action == "confirmDelete" then
        local whole = view.screen == "deleteCircuit"
        local changes = {}
        for _, item in ipairs(whole and circuit.nodes or {node}) do
            if isOutput(item) and item.route and circuit.enabled then changes[#changes + 1] = outputChange(item, true) end
        end
        if commit(state, api, view, function()
            if whole then table.remove(state.circuits, circuitIndex)
            else
                table.remove(circuit.nodes, nodeIndex)
                for _, item in ipairs(circuit.nodes) do
                    if item.a == node.id then
                        item.a = nil
                        if timedKinds[item.kind] then retime(item) end
                    end
                    if item.b == node.id then item.b = nil end
                    if item.targetId == node.id then item.targetId = nil end
                    if item.steps then
                        for index = #item.steps, 1, -1 do
                            if item.steps[index] == node.id then table.remove(item.steps, index); retime(item) end
                        end
                    end
                end
            end
        end, changes) then view.screen = whole and "home" or "circuit" end
    else view.screen = action end
    api.invalidateAppViews(appName)
    return true
end
return app
