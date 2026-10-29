-- Optional SmartHome OS app. Install explicitly; all logic runs on the OS.
local app = {title = "Coffee", minWidth = 12, minHeight = 6, preferredWidth = 30, preferredHeight = 10, backgroundService = true}
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
    assert(api.pickIO and api.readInput and api.pickColour and api.getAppColour and api.ui, "Coffee requires the bundled-v9 OS update")
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
    if not file then notice = "Copy old save to OS first"; return false end
    local raw = file.readAll(); file.close()
    local ok, legacy = pcall(textutils.unserialize, raw)
    if not ok or type(legacy) ~= "table" or not number(legacy.remainingTime, 0, 604800)
        or type(legacy.redstoneActive) ~= "boolean" or not number(legacy.redstoneEndTime, -604800, 604800) then
        notice = "Invalid old save"; return false
    end
    ok = commit(state, api, function(s)
        s.phase = legacy.redstoneActive and "harvest" or "countdown"
        s.remainingTime, s.harvestRemaining = legacy.remainingTime, math.max(0, legacy.redstoneEndTime)
        s.paused, s.forced = true, false
    end, false)
    if ok then notice = "Imported; paused" end
    return ok
end

local digits = {
    ["0"] = {"111","101","101","101","111"}, ["1"] = {"010","110","010","010","111"},
    ["2"] = {"111","001","111","100","111"}, ["3"] = {"111","001","111","001","111"},
    ["4"] = {"101","101","111","001","001"}, ["5"] = {"111","100","111","001","111"},
    ["6"] = {"111","100","111","101","111"}, ["7"] = {"111","001","001","001","001"},
    ["8"] = {"111","101","111","101","111"}, ["9"] = {"111","101","111","001","111"},
    [":"] = {"0","1","0","1","0"},
}
local function largeClock(ui, width, height, value, accent, contrast)
    local total = -1
    for index = 1, #value do total = total + #digits[value:sub(index, index)][1] + 1 end
    local scale = height >= 20 and width >= total * 2 and 2 or 1
    local x = 1 + math.floor((width - total * scale) / 2)
    ui.style(1, 2, width, 5 * scale, nil, contrast)
    for index = 1, #value do
        local pattern = digits[value:sub(index, index)]
        for row, pixels in ipairs(pattern) do
            for column = 1, #pixels do
                if pixels:sub(column, column) == "1" then
                    ui.style(x + (column - 1) * scale, 2 + (row - 1) * scale, scale, scale, nil, accent)
                end
            end
        end
        x = x + (#pattern[1] + 1) * scale
    end
    return 5 * scale
end
local function build(width, height, state, api, context)
    local view = context.view
    local ui = api.ui.content(width, height)
    local accent = api.getAppColour(context.appName or "coffee")
    local page = view.page or "main"
    local half = math.floor(width / 2)
    local function button(y, label, action, x1, x2, enabled, bg)
        ui.button(y, label, action, x1, x2, enabled, bg)
    end
    if page == "menu" or page == "settings" or page == "maintenance" then
        local items, back, title
        if page == "menu" then
            title, back = "Menu", "main"
            items = {{label = "Settings", action = "settings"}, {label = "Stats", action = "stats"},
                {label = "Maintenance", action = "maintenance"}}
        elseif page == "settings" then
            title, back = "Settings", "menu"
            items = {{label = width >= 16 and "Player input" or "Player IO", action = "input"},
                {label = width >= 16 and "Harvest output" or "Harvest IO", action = "output"},
                {label = "Countdown", action = "countdown"}, {label = "Harvest time", action = "harvest"},
                {label = "UI colour", action = "colour"}}
        else
            title, back = "Maintenance", "menu"
            items = {{label = "Reset timer", action = "reset"}, {label = "Import save", action = "import"}}
        end
        local key = page .. "Page"
        local lines, hits, current, pages = api.ui.menu(width, height, title, items, view[key], back, accent)
        view[key], view[page .. "Pages"] = current, pages
        return lines, hits
    elseif page == "duration" then
        ui.heading(saveError and "Save failed" or view.field == "countdown" and "Countdown" or "Harvest time", accent)
        ui.text(2, clock(view.draft), true)
        button(3, "Step " .. steps[view.step] .. "s", "step")
        button(4, "-", "minus", 1, half)
        button(4, "+", "plus", half + 1, width)
        button(height - 1, "Save (next)", "saveDuration", nil, nil, true, 8192)
        button(height, "Cancel", "settings")
    elseif page == "stats" then
        ui.heading(saveError and "Save failed" or width >= 16 and "Harvest counts" or "Stats", accent)
        ui.text(2, "Total: " .. state.totalHarvests)
        ui.text(3, "Trip: " .. state.tripHarvests)
        button(4, "Reset trip", "resetTrip")
        button(height, "Back", "menu")
    elseif page == "reset" or page == "import" then
        ui.heading(page == "reset" and "Reset timer?" or "Import save?", accent)
        ui.text(2, width >= 18 and "Replaces progress" or "Replace time", true)
        ui.text(3, saveError and "Save failed" or notice or (page == "import" and
            (width >= 16 and "Starts paused" or "Paused") or (width >= 16 and "Fresh countdown" or "Starts over")), true)
        if page == "import" and width >= 20 and height >= 8 then ui.text(4, "countdown_state.txt", true) end
        button(height - 1, "Confirm", page == "reset" and "confirmReset" or "confirmImport", nil, nil, true, 16384)
        button(height, "Cancel", "maintenance")
    else
        local large = width >= 32 and height >= 14
        local inline = width >= 36 and height >= 8
        local statusRow, infoRow = 3, 4
        local limit = height - (inline and 1 or 3)
        local remaining = state.phase == "harvest" and state.harvestRemaining or state.remainingTime
        ui.heading(state.phase == "harvest" and "Harvesting" or "Next harvest", accent)
        if large then
            statusRow = 2 + largeClock(ui, width, height, clock(remaining), accent, api.ui.contrast(accent))
            infoRow = statusRow + 1
        else
            ui.text(2, clock(remaining), true)
            ui.style(1, 2, width, 1, api.ui.contrast(accent) == 1 and accent or 32768, 1)
        end
        local status = saveError and "Save failed" or notice or runtimeStatus
        if width < 20 then
            local compact = {["Set harvest IO"] = "Set output", ["Set online output first"] = "Need output",
                ["Output offline"] = "IO offline", ["Waiting for IO"] = "IO pending", ["Counting down"] = "Running"}
            status = compact[status] or status
        end
        ui.text(statusRow, status, true)
        local player = api.readInput(state.playerInput)
        local details = {"Player: " .. (player == nil and "?" or player and (width < 16 and "on" or "online")
            or (width < 16 and "off" or "away"))}
        if width >= 36 then details[#details + 1] = "Harvests: " .. state.tripHarvests .. " trip / " .. state.totalHarvests .. " total"
        elseif width >= 24 then details[#details + 1] = "Trip: " .. state.tripHarvests .. "  Total: " .. state.totalHarvests
        else details[#details + 1] = "Total: " .. state.totalHarvests end
        local available = limit - infoRow + 1
        if width >= 24 and available - #details >= 2 then
            details[#details + 1] = "Countdown: " .. clock(state.config.countdown)
            details[#details + 1] = "Harvest: " .. clock(state.config.harvest)
        end
        if width >= 30 and available - #details >= 2 then
            for _, item in ipairs({{"Input", state.playerInput}, {"Output", state.outputAddress}}) do
                local address = item[2]
                details[#details + 1] = address and item[1] .. ": " .. address.clientId .. "/" .. address.side
                    .. "/" .. (address.color and api.ui.colourName(address.color) or "Digital") or item[1] .. ": not set"
            end
        end
        for index, line in ipairs(details) do if infoRow + index - 1 <= limit then ui.text(infoRow + index - 1, line) end end
        if inline then
            local third = math.floor(width / 3)
            button(height, state.paused and "Resume" or "Pause", "pause", 1, third, true, accent)
            button(height, state.phase == "harvest" and "Active" or "Harvest now", "force", third + 1, 2 * third, state.phase ~= "harvest", 2)
            button(height, "Menu", "menu", 2 * third + 1, width)
        else
            button(height - 2, state.paused and "Resume" or "Pause", "pause", nil, nil, true, accent)
            button(height - 1, state.phase == "harvest" and (width >= 16 and "Harvest active" or "Active") or "Harvest now",
                "force", nil, nil, state.phase ~= "harvest", 2)
            button(height, "Menu", "menu")
        end
    end
    return ui.lines, ui.hits
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
        if api.ui.hit(hit, x, y) and hit.enabled ~= false then action = hit.action; break end
    end
    if not action then return false end
    notice = nil
    local view = context.view
    if action == "input" or action == "output" then
        local key = action == "input" and "playerInput" or "outputAddress"
        local ok, err = api.pickIO(context.windowId, key, action, state[key])
        if not ok then notice = err end
    elseif action == "colour" then
        local ok, err = api.pickColour(context.windowId)
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
    elseif action == "confirmImport" then
        if importLegacy(state, api) then view.page = "main" end
    elseif action == "previous" or action == "next" then
        local key = (view.page or "menu") .. "Page"
        local pages = view[(view.page or "menu") .. "Pages"] or 1
        view[key] = math.max(1, math.min(pages, (view[key] or 1) + (action == "previous" and -1 or 1)))
    else view.page = action end
    if notice then noticeUntil = os.clock() + 4 end
    return true
end

return app
