-- Optional reactor overview. All sensors and output switches belong to OS APIs.
local app = {title = "Reactors", minWidth = 12, minHeight = 6, preferredWidth = 50, preferredHeight = 18}
local appName, ready = "reactors", false
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function restore(state, old)
    for key in pairs(state) do state[key] = nil end
    for key, value in pairs(old) do state[key] = value end
end
local function find(state, id)
    for index, entry in ipairs(state.reactors) do if entry.id == id then return entry, index end end
end
local function logical(entry) return appName .. "_switch_" .. entry.id end
local function watchKey(entry) return appName .. "_sensor_" .. entry.id end
local function same(a, b)
    return a and b and a.clientId == b.clientId and a.side == b.side and a.color == b.color or a == b
end
local function wire(entry, api)
    for _, item in ipairs(api.getOutputs()) do if item.name == logical(entry) and same(item, entry.outputAddress) then return item end end
end
local function number(value)
    if type(value) ~= "number" then return "?" end
    return tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
end
local function clock(value)
    if type(value) ~= "number" then return "Unavailable" end
    value = math.max(0, math.floor(value))
    return string.format("%02d:%02d:%02d", math.floor(value / 3600), math.floor(value / 60) % 60, value % 60)
end
local function energy(value, compact)
    for _, unit in ipairs({{1000000000000000000, "EEU"}, {1000000000000000, "PEU"}, {1000000000000, "TEU"},
        {1000000000, "GEU"}, {1000000, "MEU"}, {1000, "kEU"}}) do
        if value >= unit[1] then return string.format(compact and "%.1f%s" or "%.2f %s", value / unit[1], unit[2]) end
    end
    return number(value) .. (compact and "EU" or " EU")
end
local function notice(view, message, back)
    view.message, view.messageBack, view.screen = tostring(message), back or view.screen or "home", "message"
end
local function commit(state, api, view, change, changes)
    local old = copy(state)
    change()
    local ok, err
    if changes then ok, err = api.updateOutputs(changes()) else ok, err = api.save() end
    if not ok then restore(state, old); notice(view, "Save failed: " .. tostring(err)); return false, err end
    api.invalidateAppViews(appName)
    return true
end
function app.init(state, api, context)
    ready = false
    assert(api.pickSensor and api.watchSensor and api.sharedOutputs, "Reactors requires bundled-v15 OS")
    appName = context and context.appName or "reactors"
    if state.version == nil then state.version, state.reactors, state.nextId, state.panelColour = 1, {}, 1, 256 end
    assert(state.version == 1 and type(state.reactors) == "table" and #state.reactors <= 64, "Invalid saved reactors")
    local ids, maximum = {}, 0
    for _, entry in ipairs(state.reactors) do
        assert(type(entry) == "table" and type(entry.id) == "number" and entry.id >= 1 and entry.id == math.floor(entry.id)
            and not ids[entry.id] and type(entry.name) == "string" and #entry.name > 0 and #entry.name <= 32
            and type(entry.sensor) == "table", "Invalid saved reactor entry")
        ids[entry.id], maximum = true, math.max(maximum, entry.id)
    end
    assert(type(state.nextId) == "number" and state.nextId > maximum and state.nextId == math.floor(state.nextId), "Invalid reactor ID counter")
    assert(api.ui.colourName(state.panelColour) ~= "Unknown", "Invalid panel colour")
    ready = true
    app.background(0, state, api)
end
function app.background(dt, state, api)
    if not ready then return end
    for _, entry in ipairs(state.reactors) do api.watchSensor(watchKey(entry), entry.sensor) end
end
function app.shutdown(state, api)
    for _, entry in ipairs(state.reactors) do api.unwatchSensor(watchKey(entry)) end
end
function app.handleSensorSelection(key, address, state, api, context)
    local view = context.view
    local entry = key ~= "new" and find(state, tonumber(key:match("^sensor_(%d+)$"))) or nil
    if key ~= "new" and not entry then return false, "Reactor was removed" end
    if key == "new" and #state.reactors >= 64 then return false, "Maximum 64 reactors" end
    local previous, created = copy(state), nil
    if key == "new" then
        created = {id = state.nextId, name = "Core " .. state.nextId, sensor = copy(address)}
        state.nextId = state.nextId + 1; state.reactors[#state.reactors + 1] = created; entry = created
    else entry.sensor = copy(address) end
    local ok, err = api.save()
    if not ok then restore(state, previous); return false, err end
    api.invalidateAppViews(appName)
    api.watchSensor(watchKey(entry), entry.sensor)
    view.id, view.screen, view.page = entry.id, "reactor", 1
    return true
end
function app.handleIOSelection(key, address, state, api, context)
    local entry = find(state, tonumber(key:match("^output_(%d+)$")))
    if not entry then return false, "Reactor was removed" end
    local view = context.view
    if view.routeKey ~= key or not same(entry.outputAddress, view.routeBefore) then return false, "Routing changed; cancel and retry" end
    if same(entry.outputAddress, address) and wire(entry, api) then return true end
    local old = copy(state)
    entry.outputAddress = copy(address)
    local ok, err = api.updateOutputs({{name = logical(entry), clientId = address.clientId, side = address.side, color = address.color, initialValue = false}})
    if not ok then restore(state, old); return false, err end
    api.invalidateAppViews(appName)
    return true
end
local function build(width, height, state, api, context)
    local view, accent = context.view, api.getAppColour(context.appName or appName)
    local screen, entry = view.screen or "home", find(state, view.id)
    if screen ~= "home" and screen ~= "settings" and screen ~= "palette" and screen ~= "about" and screen ~= "message" and not entry then
        screen, view.screen = "home", "home"
    end
    local ui = api.ui.content(width, height)
    local contrast = api.ui.contrast(state.panelColour)
    ui.style(1, 1, width, height, contrast, state.panelColour)
    local function put(x, y, value, span, centre)
        if y < 1 or y > height then return end
        span = math.min(span or width - x + 1, width - x + 1)
        value = tostring(value):gsub("[%c]", " "):sub(1, span)
        if centre then value = string.rep(" ", math.floor((span - #value) / 2)) .. value end
        ui.lines[y] = ui.lines[y]:sub(1, x - 1) .. value .. ui.lines[y]:sub(x + #value)
    end
    local function button(row, label, action, value, x1, x2, enabled, bg)
        ui.button(row, label, action, x1, x2, enabled, bg or 128, nil, value)
    end
    local function footer(left, action, right, rightAction)
        if not right then button(height, left, action)
        else
            local half = math.floor(width / 2)
            button(height, left, action, nil, 1, half)
            button(height, right, rightAction, nil, half + 1, width, true, accent)
        end
    end
    local function pages(count, slots, key, row)
        local total = math.max(1, math.ceil(count / slots))
        view.pages = view.pages or {}
        local page = math.max(1, math.min(view.pages[key] or 1, total))
        view.pages[key] = page
        if total > 1 then
            local wing = math.floor(width / 3)
            button(row, "<", "page", {key = key, delta = -1, pages = total}, 1, wing, page > 1)
            put(wing + 1, row, page .. "/" .. total, width - 2 * wing, true)
            button(row, ">", "page", {key = key, delta = 1, pages = total}, width - wing + 1, width, page < total)
        end
        return page, total
    end
    local function metrics(reactor)
        reactor = reactor or {}
        local compact = width < 24
        return {(compact and "T: " or "Heat: ") .. number(reactor.heat), (compact and "Max: " or "MaxHeat: ") .. number(reactor.maxHeat),
            (compact and (reactor.meltingDerived and "M*: " or "M: ") or reactor.meltingDerived and "Melting*: " or "Melting: ") .. number(reactor.melting),
            (compact and "Out: " or "Output: ") .. number(reactor.output) .. " EU/t",
            (compact and "R: " or "Remaining: ") .. (compact and reactor.remaining == nil and "n/a" or clock(reactor.remaining))}
    end
    local function reading(item)
        local result = api.getSensorReading(item.sensor)
        if result.status == "ok" and not result.reactor then result.status, result.error = "invalid", "Not a reactor reading" end
        return result
    end
    local function switch(item, row, x1, x2)
        local output = wire(item, api)
        local text = not output and "Set IO" or output.value and "ON" or "OFF"
        if output and (not output.online or not output.confirmed) then text = text .. " ..." end
        button(row, text, output and "toggle" or "output", item.id, x1, x2, true,
            not output and accent or not output.online and 16384 or not output.confirmed and 2 or output.value and 32 or 128)
    end
    if screen == "home" then
        ui.heading("Reactors", accent)
        local columns = math.max(1, math.min(3, math.floor((width + 1) / 23)))
        local rows = math.max(1, math.floor((height - 3) / 8))
        local bottom = height - 2
        if #state.reactors > columns * rows then bottom = bottom - 1; rows = math.max(1, math.floor((bottom - 1) / 8)) end
        local slots = rows * columns
        local page = pages(#state.reactors, slots, "home", bottom + 1)
        if #state.reactors == 0 then
            button(math.max(2, math.floor(height / 2)), "+ Add reactor", "add", nil, nil, nil, true, accent)
            footer("Settings", "settings")
        else
            ui.style(1, 2, width, bottom - 1, 1, 32768)
            for slot = 1, slots do
                local item = state.reactors[(page - 1) * slots + slot]
                if item then
                    local col, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
                    local x1, x2 = 1 + math.floor(col * width / columns) + (col > 0 and 1 or 0), math.floor((col + 1) * width / columns)
                    local y1, y2 = 2 + math.floor(row * (bottom - 1) / rows) + (row > 0 and 1 or 0), 1 + math.floor((row + 1) * (bottom - 1) / rows)
                    local w, rh = x2 - x1 + 1, y2 - y1 + 1
                    ui.style(x1, y1, w, rh, contrast, state.panelColour)
                    ui.style(x1, y1, w, 1, api.ui.contrast(accent), accent)
                    put(x1, y1, item.name, w - 4)
                    local status = reading(item)
                    local active = status.status == "ok" and status.reactor and status.reactor.active
                    local label = status.status ~= "ok" and "?" or active == nil and "?" or active and "On" or "Off"
                    put(x2 - 2, y1, label, 3)
                    ui.style(x2 - 2, y1, 3, 1, 32768, label == "On" and 32 or label == "Off" and 16384 or 2)
                    local values = metrics(status.reactor)
                    for index = 1, math.min(5, rh - 2) do put(x1, y1 + index, values[index], w) end
                    if status.status ~= "ok" then
                        put(x1, math.min(y2 - 1, y1 + 1), status.error or "Sensor unavailable", w)
                        ui.style(x1, y1 + 1, w, math.max(1, rh - 2), 128, state.panelColour)
                    end
                    ui.hits[#ui.hits + 1] = {x1 = x1, x2 = x2, y1 = y1, y2 = y2 - 1, action = "open", value = item.id}
                    switch(item, y2, x1, x2)
                end
            end
            button(height - 1, "+ Add reactor", "add", nil, nil, nil, #state.reactors < 64, accent)
            footer("Settings", "settings")
        end
    elseif screen == "reactor" then
        local status = reading(entry)
        local value = status.reactor or {}
        ui.heading(entry.name, accent)
        local active = value.active == nil and "?" or value.active and "On" or "Off"
        if status.status ~= "ok" then active = "?" end
        put(width - 2, 1, active, 3)
        ui.style(width - 2, 1, 3, 1, 32768, active == "On" and 32 or active == "Off" and 16384 or 2)
        local columns = width >= 50 and 2 or 1
        local inset, gutter = width >= 24 and 2 or 0, columns > 1 and 2 or 0
        local span = math.floor((width - 2 * inset - gutter) / columns)
        local values = metrics(value)
        local compact = width < 24
        if value.heat then
            values[#values + 1] = (compact and "M+" or "To melting") .. (value.meltingDerived and "*: " or ": ") .. number(value.heatToMelting)
            values[#values + 1] = (compact and "Max+: " or "To MaxHeat: ") .. number(value.heatToMax)
            if height < 13 then values[#values + 1] = string.format(compact and "Heat: %.1f%%" or "Heat level: %.1f%%", value.percent) end
        end
        if value.energyEmitted ~= nil then values[#values + 1] = (compact and "Emit: " or "Emitted: ") .. energy(value.energyEmitted, compact) end
        if value.energySunken ~= nil then values[#values + 1] = (compact and "In: " or "Received: ") .. energy(value.energySunken, compact) end
        values[#values + 1] = (compact and "S: " or "Sensor: ") .. entry.sensor.clientId
        values[#values + 1] = "Side: " .. entry.sensor.side
        values[#values + 1] = (compact and "At: " or "Target: ") .. entry.sensor.target
        if status.target then values[#values + 1] = "Type: " .. status.target.type end
        if value.remainingField then values[#values + 1] = "Time field: " .. value.remainingField end
        local wrapped = {}
        for _, text in ipairs(values) do
            repeat
                wrapped[#wrapped + 1] = text:sub(1, span)
                text = #text > span and "  " .. text:sub(span + 1) or ""
            until text == ""
        end
        values = wrapped
        local statusRow = height >= 9 and height - 2 or nil
        local barRow = height >= 13 and height - 3 or nil
        local pagerRow = height - (barRow and 4 or statusRow and 3 or 2)
        local bodyRows = pagerRow - 2
        local slots = bodyRows * columns
        local page = pages(#values, slots, "metrics", pagerRow)
        local count = math.min(slots, #values - (page - 1) * slots)
        local rows = math.ceil(count / columns)
        local gap = rows > 1 and math.floor((bodyRows - 1) / (rows - 1)) >= 2 and 2 or 1
        for slot = 1, count do
            local col, row = math.floor((slot - 1) / rows), (slot - 1) % rows
            put(1 + inset + col * (span + gutter), 2 + row * gap, values[(page - 1) * slots + slot], span)
        end
        if barRow then
            local fraction = math.max(0, math.min(1, (value.percent or 0) / 100))
            ui.style(2, barRow, width - 2, 1, 1, 128)
            if value.heat then
                local filled = math.floor((width - 2) * fraction)
                if filled > 0 then ui.style(2, barRow, filled, 1, nil,
                    status.status ~= "ok" and 128 or value.heat >= value.melting and 16384 or 32) end
                put(2, barRow, string.format("%.1f%% heat", value.percent), width - 2, true)
            end
        end
        if status.status ~= "ok" then
            ui.style(1, 2, width, bodyRows, 128, state.panelColour)
            local row = statusRow or 1
            ui.text(row, status.error or "Sensor unavailable", true)
            ui.style(1, row, width, 1, 1, 16384)
        elseif statusRow then ui.text(statusRow, "Data " .. math.floor(status.age or 0) .. "s old", true) end
        switch(entry, height - 1)
        footer("Back", "home", "Edit", "edit")
    elseif screen == "edit" or screen == "settings" then
        local items = screen == "edit" and {{label = "Rename", action = "rename"}, {label = "Sensor target", action = "sensor"},
            {label = "Control output", action = "output", value = entry.id}, {label = "Raw readings", action = "raw"},
            {label = "Delete reactor", action = "delete"}} or {{label = "UI colour", action = "accent"},
            {label = "Panel colour", action = "panel"}, {label = "About readings", action = "about"}}
        local lines, hits, page, total = api.ui.menu(width, height, screen == "edit" and "Reactor settings" or "App settings", items,
            view.menuPage, screen == "edit" and "reactor" or "home", accent)
        view.menuPage, view.menuPages = page, total
        for _, hit in ipairs(hits) do if hit.action == "output" then hit.value = entry.id end end
        return lines, hits
    elseif screen == "palette" then
        local previewAccent = view.colourField == "accent" and view.colourDraft or accent
        local previewPanel = view.colourField == "accent" and state.panelColour or view.colourDraft
        local lines, hits = api.ui.palette(width, height, view.colourDraft, view.colourField == "accent" and "UI colour" or "Panel colour")
        ui.lines, ui.hits = lines, hits; table.remove(ui.hits); ui.lines.hits = ui.hits
        ui.style(1, 1, width, 1, api.ui.contrast(previewAccent), previewAccent)
        if width >= 24 and height >= 15 then
            ui.style(1, height - 5, width, 4, api.ui.contrast(previewPanel), previewPanel)
            ui.style(1, height - 5, width, 1, api.ui.contrast(previewAccent), previewAccent)
            ui.text(height - 5, "Preview", true); ui.text(height - 4, "Heat: 48 036 / 58 000", true)
            ui.text(height - 3, "Output: 30 EU/t", true); ui.text(height - 2, "Remaining: 02:41:45", true)
        end
        button(height, "Apply", "applyPanel", nil, 1, math.floor(width / 2), true, previewAccent)
        button(height, "Cancel", "settings", nil, math.floor(width / 2) + 1, width)
    elseif screen == "rename" then
        local keyboard = view.keyboard
        local letters = keyboard.bank == "123" and "1234567890-_/.:!?+()@#&=" or "qwertyuiopasdfghjklzxcvbnm"
        if keyboard.bank == "ABC" then letters = letters:upper() end
        local columns = width < 24 and math.max(4, math.floor(width / 2)) or 10
        local count = columns * 3
        local total = math.ceil(#letters / count)
        keyboard.page = math.min(keyboard.page, total)
        ui.text(1, (keyboard.draft .. "_"):sub(-width))
        ui.style(1, 1, width, 1, 32768, 1)
        local available = height - 3
        for index = 1, count do
            local letter = letters:sub((keyboard.page - 1) * count + index, (keyboard.page - 1) * count + index)
            if letter ~= "" then
                local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
                local x1, x2 = 1 + math.floor(col * width / columns), math.floor((col + 1) * width / columns)
                local y1, y2 = 2 + math.floor(row * available / 3), 1 + math.floor((row + 1) * available / 3)
                ui.style(x1, y1, x2 - x1 + 1, y2 - y1 + 1, 1, (row + col) % 2 == 0 and 128 or 32768)
                put(x1, math.floor((y1 + y2) / 2), letter, x2 - x1 + 1, true)
                ui.hits[#ui.hits + 1] = {x1 = x1, x2 = x2, y1 = y1, y2 = y2, action = "key", value = letter}
            end
        end
        local actions = {{"ABC", "bank"}, {"Space", "space"}, {"Del", "del"}, {keyboard.page .. "/" .. total, "keyPage"}}
        for i, item in ipairs(actions) do button(height - 1, item[1], item[2], nil, 1 + math.floor((i - 1) * width / 4), math.floor(i * width / 4)) end
        local third = math.floor(width / 3)
        button(height, "Save", "saveName", nil, 1, third, keyboard.draft:find("%S") ~= nil, accent)
        button(height, "Clr", "clearName", nil, third + 1, 2 * third)
        button(height, "Back", "edit", nil, 2 * third + 1, width)
    elseif screen == "delete" then
        ui.heading("Delete reactor?", accent)
        ui.text(2, entry.name, true); ui.text(3, "Unshared OFF", true)
        button(height - 1, "Confirm", "confirmDelete", nil, nil, nil, true, 16384); footer("Cancel", "edit")
    elseif screen == "raw" or screen == "about" or screen == "message" then
        local lines = {}
        if screen == "raw" then
            local status = api.getSensorReading(entry.sensor)
            local function add(text)
                text = text:gsub("[%c]", " ")
                repeat
                    if #lines >= 256 then return end
                    lines[#lines + 1], text = text:sub(1, width), text:sub(width + 1)
                until text == ""
            end
            local function visit(value, path, depth)
                if #lines >= 256 then return end
                if type(value) ~= "table" then add(path .. ": " .. tostring(value)); return end
                if depth >= 4 then add(path .. ": [deeper table]" ); return end
                local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
                if #keys == 0 and path ~= "" then add(path .. ": {}") end
                for _, key in ipairs(keys) do
                    local name = type(key) == "number" and "[" .. key .. "]" or (path == "" and "" or ".") .. key
                    visit(value[key], path .. name, depth + 1)
                    if #lines >= 256 then return end
                end
            end
            visit(status.data or {}, "", 0)
            if #lines >= 256 then lines[256] = "More fields omitted" end
            if #lines == 0 then lines[1] = status.error or "No reading yet" end
        else
            local message = screen == "about" and "Melting* is 85% of maximum heat. To melting/max shows heat headroom; negative means above that threshold. Emitted/received are the card's EU counters, not saved app totals. Old IC2 cards supply no fuel lifetime or inventory, for core or chamber. Remaining needs an explicit time field; adding chambers cannot supply it. Raw readings expands nested fields. ON/OFF shows requested output; the header shows actual reactor activity." or view.message
            repeat lines[#lines + 1], message = message:sub(1, width), message:sub(width + 1) until message == ""
        end
        ui.heading(screen == "raw" and "Sensor fields" or "Information", accent)
        local slots = #lines <= height - 2 and height - 2 or height - 3
        local page = pages(#lines, slots, "info", height - 1)
        for row = 1, slots do ui.text(row + 1, (lines[(page - 1) * slots + row] or ""):gsub("[%c]", " ")) end
        footer("Back", screen == "raw" and "edit" or screen == "about" and "settings" or "messageBack")
    end
    return ui.lines, ui.hits
end
function app.render(width, height, state, api, context)
    if not ready then return {"Reactors blocked", "Check OS log"} end
    return (build(width, height, state, api, context))
end
function app.handleTouch(x, y, width, height, state, api, context)
    if not ready then return false end
    local _, hits = build(width, height, state, api, context)
    local action, value
    for _, hit in ipairs(hits) do if hit.enabled ~= false and api.ui.hit(hit, x, y) then action, value = hit.action, hit.value; break end end
    if not action then return false end
    local view = context.view
    local entry, index = find(state, view.id)
    if action == "add" or action == "sensor" then
        local ok, err = api.pickSensor(context.windowId, action == "add" and "new" or "sensor_" .. entry.id, action == "sensor" and entry.sensor or nil, "reactor")
        if not ok then notice(view, err) end
    elseif action == "open" then view.id, view.screen, view.pages = value, "reactor", {}
    elseif action == "output" then
        entry = find(state, value or view.id)
        local key = "output_" .. entry.id
        view.routeKey, view.routeBefore = key, copy(entry.outputAddress)
        local ok, err = api.pickIO(context.windowId, key, "output", entry.outputAddress)
        if not ok then notice(view, err) end
    elseif action == "toggle" then
        entry = find(state, value or view.id)
        local output = wire(entry, api)
        if output then local ok, err = api.setOutput(logical(entry), not output.value); if not ok then notice(view, err) end end
    elseif action == "page" then view.pages[value.key] = math.max(1, math.min(value.pages, view.pages[value.key] + value.delta))
    elseif action == "previous" or action == "next" then view.menuPage = math.max(1, math.min(view.menuPages, view.menuPage + (action == "next" and 1 or -1)))
    elseif action == "rename" then view.keyboard, view.screen = {draft = entry.name, original = entry.name, page = 1, bank = "abc"}, "rename"
    elseif action == "key" or action == "space" then
        if #view.keyboard.draft < 32 then view.keyboard.draft = view.keyboard.draft .. (action == "space" and " " or value) end
    elseif action == "bank" then view.keyboard.bank, view.keyboard.page = view.keyboard.bank == "abc" and "ABC" or view.keyboard.bank == "ABC" and "123" or "abc", 1
    elseif action == "keyPage" then view.keyboard.page = view.keyboard.page == 1 and 2 or 1
    elseif action == "del" then view.keyboard.draft = view.keyboard.draft:sub(1, -2)
    elseif action == "clearName" then view.keyboard.draft = ""
    elseif action == "saveName" then
        if entry.name ~= view.keyboard.original then notice(view, "Name changed in another window", "edit")
        elseif commit(state, api, view, function() entry.name = view.keyboard.draft:gsub("^%s+", ""):gsub("%s+$", "") end) then view.screen = "edit" end
    elseif action == "accent" then
        view.colourField, view.colourDraft, view.screen = "accent", api.getAppColour(context.appName or appName), "palette"
    elseif action == "panel" then view.colourField, view.colourDraft, view.screen = "panel", state.panelColour, "palette"
    elseif action == "colour" then view.colourDraft = value
    elseif action == "applyPanel" then
        local ok, err
        if view.colourField == "accent" then
            ok, err = api.setAppColour(context.appName or appName, view.colourDraft)
            if not ok then notice(view, err) end
        else ok = commit(state, api, view, function() state.panelColour = view.colourDraft end) end
        if ok then api.invalidateAppViews(appName); view.screen = "settings" end
    elseif action == "confirmDelete" then
        local id = entry.id
        if commit(state, api, view, function() table.remove(state.reactors, index) end,
            function() return {{name = logical(entry), remove = true}} end) then
            api.unwatchSensor(appName .. "_sensor_" .. id); view.screen = "home"
        end
    elseif action == "messageBack" then view.screen = view.messageBack or "home"
    else view.screen, view.menuPage = action, 1 end
    return true
end
return app
