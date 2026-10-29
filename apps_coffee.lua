-- Optional SmartHome OS app. Install explicitly; all logic runs on the OS.
local app = {minWidth = 12, minHeight = 6, maxWidth = 40, maxHeight = 12}
local sinceSave, saveError, notice, runtimeStatus = 0, nil, nil, "Starting"
local ready, noticeUntil = false, 0
local steps = {1, 10, 60, 600, 3600}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function restore(state, previous)
    for key in pairs(state) do state[key] = nil end
    for key, value in pairs(previous) do state[key] = value end
end
local function number(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum
end
local function clock(seconds)
    seconds = math.max(0, math.ceil(seconds or 0))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end
local function output(state, api)
    for _, item in ipairs(api.getOutputs()) do
        if item.name == state.outputName then
            local address = state.outputAddress
            if address and item.clientId == address.clientId and item.side == address.side and item.color == address.color then
                return item
            end
        end
    end
end
local function commit(state, api, change, desired)
    local previous = copy(state)
    change(state)
    local ok, err
    if desired ~= nil and output(state, api) then ok, err = api.setOutput(state.outputName, desired)
    else ok, err = api.save() end
    if not ok then restore(state, previous); saveError = tostring(err); return false, err end
    sinceSave, saveError = 0, nil
    return true
end

function app.init(state, api, context)
    ready = false
    assert(api.pickIO and api.readInput, "Coffee requires the bundled-v4 OS update")
    if state.version == nil then
        state.version, state.config = 1, {countdown = 14400, harvest = 60}
        state.phase, state.remainingTime, state.harvestRemaining = "countdown", 14400, 0
        state.paused, state.forced, state.totalHarvests, state.tripHarvests = false, false, 0, 0
        state.outputName = (context and context.appName or "coffee") .. "_harvest"
    end
    assert(state.version == 1 and type(state.config) == "table", "Unknown saved coffee state")
    assert(number(state.config.countdown, 1, 604800) and number(state.config.harvest, 1, 604800), "Invalid saved durations")
    assert((state.phase == "countdown" or state.phase == "harvest")
        and number(state.remainingTime, 0, 604800) and number(state.harvestRemaining, 0, 604800), "Invalid saved timer")
    assert(type(state.paused) == "boolean" and type(state.forced) == "boolean"
        and number(state.totalHarvests, 0, math.huge) and number(state.tripHarvests, 0, math.huge), "Invalid saved coffee controls")
    assert(type(state.outputName) == "string" and state.outputName:match("^[%w_-]+$"), "Invalid saved output name")
    ready = true
    local ok, err = api.save()
    if not ok then saveError = tostring(err) end
    -- Live inputs are not known at boot. Reconcile output after clients report.
    if output(state, api) and api.getOutput(state.outputName) then
        local changed, message = api.setOutput(state.outputName, false)
        if not changed then saveError = tostring(message) end
    end
end

function app.background(dt, state, api)
    if not ready then return end
    if notice and os.clock() >= noticeUntil then notice = nil end
    if saveError then
        runtimeStatus = "Save failed"
        local ok = api.save()
        if ok then saveError, sinceSave = nil, 0 end
        return
    end
    local elapsed = math.min(math.max(dt, 0), 1) -- Never catch up through computer downtime.
    sinceSave = sinceSave + elapsed
    -- A recovered zero-duration harvest must finish before any ON intent is
    -- restored. This can occur if the final checkpoint was interrupted.
    if state.phase == "harvest" and state.harvestRemaining <= 0 then
        commit(state, api, function(s)
            s.phase, s.remainingTime, s.harvestRemaining, s.forced = "countdown", s.config.countdown, 0, false
            s.totalHarvests, s.tripHarvests = s.totalHarvests + 1, s.tripHarvests + 1
        end, false)
        return
    end
    local wire = output(state, api)
    local player, inputError = api.readInput(state.playerInput)
    local wanted = state.phase == "harvest" and not state.paused and wire and wire.online
        and (player ~= nil or state.forced) or false
    if wire and api.getOutput(state.outputName) ~= wanted then
        local ok, err = api.setOutput(state.outputName, wanted)
        if not ok then saveError = tostring(err); return end
        sinceSave, wire = 0, output(state, api)
    end
    if not wire then runtimeStatus = "Set harvest IO"
    elseif not wire.online then runtimeStatus = "Output offline"
    elseif state.paused then runtimeStatus = "Paused"
    elseif player == nil and not (state.phase == "harvest" and state.forced) then runtimeStatus = inputError
    elseif not player and not (state.phase == "harvest" and state.forced) then runtimeStatus = "Player away"
    elseif not wire.confirmed then runtimeStatus = "Waiting for IO"
    elseif state.phase == "countdown" then
        runtimeStatus = "Counting down"
        state.remainingTime = math.max(0, state.remainingTime - elapsed)
        if state.remainingTime <= 0 then
            commit(state, api, function(s)
                s.phase, s.harvestRemaining, s.forced = "harvest", s.config.harvest, false
            end, true)
        end
    else
        runtimeStatus = state.forced and "Manual harvest" or "Harvesting"
        state.harvestRemaining = math.max(0, state.harvestRemaining - elapsed)
        if state.harvestRemaining <= 0 then
            commit(state, api, function(s)
                s.phase, s.remainingTime, s.harvestRemaining, s.forced = "countdown", s.config.countdown, 0, false
                s.totalHarvests, s.tripHarvests = s.totalHarvests + 1, s.tripHarvests + 1
            end, false)
        end
    end
    if sinceSave >= 1 and not saveError then
        local ok, err = api.save()
        if ok then sinceSave = 0 else saveError = tostring(err) end
    end
end

function app.handleIOSelection(key, address, state, api)
    if key ~= "playerInput" and key ~= "outputAddress" then return false, "Unknown IO setting" end
    local previous = copy(state)
    state[key] = copy(address)
    local ok, err
    if key == "outputAddress" then
        if previous.outputAddress and state.phase == "harvest" then state.paused = true end
        -- Save the new address and OFF intent together before changing wires.
        ok, err = api.mapOutput(state.outputName, address.clientId, address.side, address.color, false)
    else ok, err = api.save() end
    if not ok then restore(state, previous); return false, err end
    sinceSave, saveError, notice = 0, nil, "IO setting saved"
    noticeUntil = os.clock() + 4
    return true
end

local function forceHarvest(state, api)
    if state.phase == "harvest" then notice = "Already harvesting"; return end
    local wire = output(state, api)
    if not wire or not wire.online then notice = "Set online output first"; return end
    local ok = commit(state, api, function(s)
        s.phase, s.harvestRemaining, s.remainingTime = "harvest", s.config.harvest, 0
        s.forced, s.paused = true, false
    end, true)
    if ok then notice = "Manual harvest started" end
end

local function importLegacy(state, api)
    local path = "countdown_state.txt"
    local file = fs.open(path, "r")
    if not file then notice = "Copy old save to OS first"; return end
    local raw = file.readAll(); file.close()
    local ok, legacy = pcall(textutils.unserialize, raw)
    if not ok or type(legacy) ~= "table" or not number(legacy.remainingTime, 0, 604800)
        or type(legacy.redstoneActive) ~= "boolean" or not number(legacy.redstoneEndTime, -604800, 604800) then
        notice = "Invalid old save"; return
    end
    ok = commit(state, api, function(s)
        s.phase = legacy.redstoneActive and "harvest" or "countdown"
        s.remainingTime, s.harvestRemaining = legacy.remainingTime, math.max(0, legacy.redstoneEndTime)
        s.paused, s.forced = true, false
    end, false)
    if ok then notice = "Imported; paused" end
end

local function build(width, height, state, api, context)
    local view = context.view
    local lines, hits = {}, {}
    local function text(y, value) lines[y] = tostring(value):sub(1, width) end
    local function button(y, label, action, x1, x2)
        x1, x2 = x1 or 1, x2 or width
        local line = lines[y] or string.rep(" ", width)
        label = label:sub(1, x2 - x1 + 1)
        lines[y] = line:sub(1, x1 - 1) .. label .. line:sub(x1 + #label)
        hits[#hits + 1] = {y = y, x1 = x1, x2 = x2, action = action}
    end
    for y = 1, height do lines[y] = string.rep(" ", width) end
    local page = view.page or "main"
    if page == "settings" then
        text(1, "Settings")
        local items = {{"Player IO >", "input"}, {"Harvest IO >", "output"}, {"Countdown >", "countdown"},
            {"Harvest time", "harvest"}, {"Stats >", "stats"}, {"Reset >", "reset"}, {"Import >", "import"}}
        local slots = height - 3
        view.settingsPage = math.max(1, math.min(view.settingsPage or 1, math.ceil(#items / slots)))
        for row = 1, slots do
            local item = items[(view.settingsPage - 1) * slots + row]
            if item then button(row + 1, item[1], item[2]) end
        end
        local half = math.floor(width / 2)
        button(height - 1, "< Prev", "previous", 1, half)
        button(height - 1, "Next >", "next", half + 1, width)
        button(height, "Back", "main")
    elseif page == "duration" then
        text(1, view.field == "countdown" and "Countdown" or "Harvest time")
        text(2, clock(view.draft))
        text(3, "Step " .. steps[view.step] .. "s (tap)")
        button(3, lines[3], "step")
        local half = math.floor(width / 2)
        button(4, "-", "minus", 1, half)
        button(4, "+", "plus", half + 1, width)
        button(height - 1, width >= 16 and "Save: next cycle" or "Save (next)", "saveDuration")
        button(height, "Cancel", "settings")
    elseif page == "stats" then
        text(1, "Harvests")
        text(2, "Total: " .. state.totalHarvests)
        text(3, "Trip: " .. state.tripHarvests)
        button(4, "Reset trip", "resetTrip")
        button(height, "Back", "settings")
    elseif page == "reset" or page == "import" then
        text(1, page == "reset" and "Reset timer?" or "Import old save?")
        text(2, "Replaces progress")
        if page == "import" then text(3, "countdown_state.txt") end
        button(height - 1, "Confirm", page == "reset" and "confirmReset" or "confirmImport")
        button(height, "Cancel", "settings")
    else
        text(1, state.phase == "harvest" and "Coffee harvest" or "Coffee timer")
        text(2, clock(state.phase == "harvest" and state.harvestRemaining or state.remainingTime))
        text(3, saveError and "SAVE FAILED" or notice or runtimeStatus)
        if height >= 7 then text(4, "Total: " .. state.totalHarvests) end
        if height >= 8 then text(5, "Trip: " .. state.tripHarvests) end
        if height >= 9 then
            local address = state.playerInput
            text(6, address and ("In: " .. address.clientId .. "/" .. address.side) or "Input not set")
        end
        if height >= 10 then
            local address = state.outputAddress
            text(7, address and ("Out: " .. address.clientId .. "/" .. address.side) or "Output not set")
        end
        button(height - 2, state.paused and "Resume" or "Pause", "pause")
        button(height - 1, state.phase == "harvest" and "Harvest active" or "Harvest now", "force")
        button(height, "Settings", "settings")
    end
    return lines, hits
end

function app.render(width, height, state, api, context)
    if not ready then return {"Coffee blocked", "Check OS log"} end
    return (build(width, height, state, api, context))
end

function app.handleTouch(x, y, width, height, state, api, context)
    if not ready then return false end
    local _, hits = build(width, height, state, api, context)
    local action
    for _, hit in ipairs(hits) do
        if y == hit.y and x >= hit.x1 and x <= hit.x2 then action = hit.action; break end
    end
    if not action then return false end
    notice = nil
    local view = context.view
    if action == "input" or action == "output" then
        local key = action == "input" and "playerInput" or "outputAddress"
        local ok, err = api.pickIO(context.windowId, key, action, state[key])
        if not ok then notice = err end
    elseif action == "countdown" or action == "harvest" then
        view.page, view.field, view.draft = "duration", action, state.config[action]
        view.step = action == "countdown" and 3 or 1
    elseif action == "step" then view.step = view.step % #steps + 1
    elseif action == "minus" or action == "plus" then
        view.draft = math.max(1, math.min(604800, view.draft + (action == "minus" and -1 or 1) * steps[view.step]))
    elseif action == "saveDuration" then
        local ok = commit(state, api, function(s) s.config[view.field] = view.draft end)
        if ok then view.page, notice = "settings", "Applies next cycle" end
    elseif action == "pause" then
        commit(state, api, function(s) s.paused = not s.paused end, false)
    elseif action == "force" then forceHarvest(state, api)
    elseif action == "resetTrip" then commit(state, api, function(s) s.tripHarvests = 0 end)
    elseif action == "confirmReset" then
        local ok = commit(state, api, function(s)
            s.phase, s.remainingTime, s.harvestRemaining, s.forced = "countdown", s.config.countdown, 0, false
        end, false)
        if ok then view.page, notice = "main", "Timer reset" end
    elseif action == "confirmImport" then importLegacy(state, api); view.page = "main"
    elseif action == "previous" then view.settingsPage = math.max(1, (view.settingsPage or 1) - 1)
    elseif action == "next" then view.settingsPage = (view.settingsPage or 1) + 1
    else view.page = action end
    if notice then noticeUntil = os.clock() + 4 end
    return true
end

return app
