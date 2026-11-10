-- Save and restore one screen or a group of monitor layouts.
local app = {title = "Window Presets", minWidth = 12, minHeight = 6, preferredWidth = 40, preferredHeight = 15}
local name = "window_presets"
local function find(list, id)
    for i, item in ipairs(list) do if item.id == id then return item, i end end
end
local function targetName(api, target) return target == false and "Skip" or api.clientName(target) end
local function keyboard(view, draft, back, purpose)
    view.keyboard = {draft = draft, bank = 0, page = 1, back = back, purpose = purpose}
    view.screen = "keyboard"
end
function app.init(state, api, context)
    assert(api.captureWindowPreset and api.previewWindowPreset, "Window Presets requires bundled-v39 OS")
    name = context.appName
    if not state.presets then state.presets, state.nextId = {}, 1 end
end
local function build(w, h, state, api, view)
    local ui = api.ui.form(w, h, view, api.getAppColour(name))
    local screen = view.screen or "home"
    local preset = find(state.presets, view.presetId)
    if (screen == "slot" or screen == "assign") and not (preset and find(preset.slots, view.slotId)) then
        view.screen = preset and "preview" or "home"
    elseif not preset and (screen == "preview" or screen == "confirm" or screen == "delete") then
        view.screen = "home"
    elseif screen == "keyboard" and (not view.keyboard or (view.keyboard.purpose == "rename" and not preset)) then
        view.screen, view.keyboard = "home", nil
    end
    screen = view.screen or "home"
    if screen == "home" then
        local rows = {{"+ Save layout", "capture", nil, #state.presets < 24}}
        for _, item in ipairs(state.presets) do rows[#rows + 1] = {item.name .. " / " .. #item.slots, "open", item.id} end
        ui.menu("Window Presets", rows, "home", {{"Close", "close"}})
    elseif screen == "capture" then
        ui.menu("Save layout", {{"This monitor", "captureScope", "one"}, {"All online monitors", "captureScope", "all"}}, "capture")
    elseif screen == "preview" then
        local plan, valid = api.previewWindowPreset(preset.slots, view.assignments or {})
        local rows = {}
        for _, item in ipairs(plan) do
            local label = targetName(api, item.target)
            if item.error then label = "! " .. label
            elseif item.target ~= false then label = label .. " / " .. item.visible .. " open" end
            rows[#rows + 1] = {label, "slot", item.source}
        end
        rows[#rows + 1] = {"Rename preset", "rename"}
        rows[#rows + 1] = {"Delete preset", "delete"}
        ui.menu(preset.name, rows, "preview", {{"Back", "home"}, {"Apply", "confirm", nil, valid, 8192}})
    elseif screen == "slot" then
        local plan = api.previewWindowPreset(preset.slots, view.assignments or {})
        local lines = {}
        for _, item in ipairs(plan) do if item.source == view.slotId then
            lines = {"From " .. api.clientName(item.source), "To " .. targetName(api, item.target)}
            if item.error then lines[#lines + 1] = item.error end
            for _, line in ipairs(item.items) do lines[#lines + 1] = line end
            break
        end end
        ui.info("Monitor preview", lines, "slot", "preview")
        ui.footer({{"Back", "preview"}, {"Assign", "assign"}})
    elseif screen == "assign" then
        local rows = {{"Original", "assignTarget", "original"}, {"Skip this slot", "assignTarget", "skip"}}
        for _, client in ipairs(api.getClients()) do if client.type == "monitor" then
            rows[#rows + 1] = {client.displayName, "assignTarget", client.id, client.online}
        end end
        ui.menu("Assign monitor", rows, "assign", {{"Back", "slot"}})
    elseif screen == "keyboard" then ui.keyboard(view.keyboard)
    elseif screen == "confirm" then
        local plan, valid = api.previewWindowPreset(preset.slots, view.assignments or {})
        local open, minimized, skipped = 0, 0, 0
        for _, item in ipairs(plan) do
            open, minimized, skipped = open + item.visible, minimized + item.minimized, skipped + item.skipped
        end
        ui.info("Replace layouts?", {open .. " open, " .. minimized .. " minimized", skipped .. " unavailable", "App data is kept"},
            "confirm", "preview")
        ui.footer({{"Cancel", "preview"}, {"Apply", "apply", nil, valid, 8192}})
    elseif screen == "delete" then
        ui.info("Delete preset?", {preset.name}, "delete", "preview")
        ui.footer({{"Cancel", "preview"}, {"Delete", "remove", nil, true, 16384}})
    else ui.info("Window Presets", {view.message}, "message", view.back or "home") end
    return ui
end
local function notice(view, message, back)
    view.screen, view.message, view.back, view.pages = "message", tostring(message), back, {}
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context.view).lines end
function app.handleTouch(x, y, w, h, state, api, context)
    local view = context.view
    local action, value = api.ui.actionAt(build(w, h, state, api, view).hits, x, y)
    if not action then return false end
    local preset, index = find(state.presets, view.presetId)
    if action == "page" then view.pages[value.key] = value.page
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "captureScope" then
        view.captureAll = value == "all"
        keyboard(view, "Layout " .. state.nextId, "capture", "capture")
    elseif action == "open" then
        preset = find(state.presets, value)
        view.presetId, view.screen, view.pages, view.assignments = value, "preview", {}, {}
        for source, target in pairs(preset.assignments or {}) do view.assignments[source] = target end
    elseif action == "slot" then
        if value then view.slotId, view.pages.slot = value, 1 end
        view.screen = "slot"
    elseif action == "assignTarget" then
        local target = value
        if value == "skip" then target = false elseif value == "original" then target = nil end
        view.assignments[view.slotId], view.screen = target, "slot"
    elseif action == "rename" and preset then keyboard(view, preset.name, "preview", "rename")
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value, 32) then return true
    elseif action == "saveText" then
        local draft = view.keyboard.draft:match("^%s*(.-)%s*$")
        if draft == "" then return true end
        local ok, err
        if view.keyboard.purpose == "rename" and preset then
            local previous = preset.name
            preset.name = draft
            ok, err = api.save()
            if not ok then preset.name = previous end
            view.screen = "preview"
        elseif view.keyboard.purpose == "capture" and #state.presets < 24 then
            local slots = api.captureWindowPreset(context.monitorId, view.captureAll)
            if #slots == 0 then notice(view, "No online monitors", "home"); return true end
            local count = 0
            for _, slot in ipairs(slots) do count = count + #slot.windows end
            if #slots > 24 or count > 128 then notice(view, "Layout exceeds 24 screens or 128 windows", "home"); return true end
            local id = state.nextId
            state.presets[#state.presets + 1] = {id = id, name = draft, slots = slots}
            state.nextId = id + 1
            ok, err = api.save()
            if not ok then table.remove(state.presets); state.nextId = id end
            view.screen = "home"
        end
        if not ok then notice(view, err or "Preset changed", "home") end
    elseif action == "remove" and preset then
        table.remove(state.presets, index)
        local ok, err = api.save()
        if ok then view.screen = "home"
        else table.insert(state.presets, index, preset); notice(view, err, "preview") end
    elseif action == "apply" and preset then
        local previous, assignments = preset.assignments, {}
        for source, target in pairs(view.assignments) do assignments[source] = target end
        preset.assignments = assignments
        local ok, err = api.applyWindowPreset(preset.slots, assignments)
        if not ok then preset.assignments = previous; notice(view, err, "preview")
        else view.screen = "preview"; if err then notice(view, err, "preview") end end
    else view.screen = action end
    api.invalidateAppViews(name)
    return true
end
return app
