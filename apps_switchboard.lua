-- Optional single-file app. The OS owns all IO, checkpoints and monitor drawing.
local app = {title = "Switchboard", minWidth = 12, minHeight = 6, preferredWidth = 42, preferredHeight = 18}
local appName, ready = "switchboard", false
local sides = {"top", "bottom", "left", "right", "front", "back"}
local sideSet = {top = true, bottom = true, left = true, right = true, front = true, back = true}
local MAX_VIEWS, MAX_AXIS = 64, 16

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function restore(state, old)
    local keys = {}; for key in pairs(state) do if old[key] == nil then keys[#keys + 1] = key end end
    for _, key in ipairs(keys) do state[key] = nil end
    for key, value in pairs(old) do
        if type(value) == "table" and type(state[key]) == "table" then restore(state[key], value)
        else state[key] = value end
    end
end
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function colour(value)
    for i = 0, 15 do if value == 2 ^ i then return true end end
    return false
end
local function name(value, limit)
    return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%c]")
end
local function outputName(button) return appName .. "_switch_" .. button.id end
local function boardById(state, id)
    for index, board in ipairs(state.boards) do if board.id == id then return board, index end end
end
local function buttonById(board, id)
    for index, button in ipairs(board and board.buttons or {}) do if button.id == id then return button, index end end
end
local function sameRoute(a, b)
    return a and b and a.clientId == b.clientId and a.side == b.side and a.color == b.color or a == b
end
local function outputs(api)
    local result = {}
    for _, item in ipairs(api.getOutputs()) do result[item.name] = item end
    return result
end
local function wireFor(button, all)
    local wire = all[outputName(button)]
    if button.route and sameRoute(button.route, wire) then return wire end
end
local function stateColour(button, board, theme, field)
    return button and button.stateColors and button.stateColors[field]
        or board and board.stateColors and board.stateColors[field] or theme[field]
end
local function buttonColour(button, theme, statusColour)
    if button.fillMode == "state" then return statusColour or theme.inactive end
    return button.displayColour or button.route and button.route.color or theme.unbound
end
local function validStateColors(value)
    if value == nil then return true end
    if type(value) ~= "table" then return false end
    for key, color in pairs(value) do
        if not ({active=true,inactive=true,pending=true})[key] or not colour(color) then return false end
    end
    return true
end
local function notify(view, text, back)
    view.message, view.messageBack, view.screen = tostring(text), back or view.screen or "home", "message"
    if view.pages then view.pages.message = nil end
end
local function commit(state, api, view, change, makeChanges)
    local previous = copy(state)
    change()
    local changes = makeChanges and makeChanges()
    local ok, err
    if changes then ok, err = api.updateOutputs(changes) else ok, err = api.save() end
    if not ok then
        restore(state, previous)
        notify(view, "Could not save: " .. tostring(err))
        return false, err
    end
    return true
end
local function newButton(state, index, api, route)
    local button = {id = state.nextButtonId, name = route and api.ui.colourName(route.color) or "Switch " .. index,
        customName = false, route = copy(route)}
    state.nextButtonId = state.nextButtonId + 1
    return button
end
local function mapping(button, value)
    local route = button.route
    return {name = outputName(button), clientId = route.clientId, side = route.side, color = route.color, initialValue = value}
end

function app.init(state, api, context)
    ready = false
    assert(api.pulseOutput and api.ui.durationHundredths, "Switchboard requires bundled-v42 OS; run inst server")
    appName = context and context.appName or "switchboard"
    if state.version == nil then
        state.version, state.boards, state.nextBoardId, state.nextButtonId = 1, {}, 1, 1
        state.settings = {background = 32768, border = 128, unbound = 128, density = "roomy"}
    end
    if type(state.settings) == "table" then
        if state.settings.active == nil then state.settings.active = 32 end
        if state.settings.inactive == nil then state.settings.inactive = state.settings.border end
        if state.settings.pending == nil then state.settings.pending = 2 end
    end
    assert(state.version == 1 and type(state.boards) == "table" and #state.boards <= MAX_VIEWS, "Invalid saved switchboard")
    assert(type(state.settings) == "table" and colour(state.settings.background) and colour(state.settings.border)
        and colour(state.settings.unbound) and colour(state.settings.active) and colour(state.settings.inactive) and colour(state.settings.pending)
        and (state.settings.density == "roomy" or state.settings.density == "compact"), "Invalid saved switchboard style")
    local boardIds, buttonIds, maxBoard, maxButton = {}, {}, 0, 0
    for _, board in ipairs(state.boards) do
        assert(type(board) == "table" and integer(board.id, 1, 2147483000) and not boardIds[board.id]
            and name(board.name, 32) and integer(board.columns, 1, MAX_AXIS) and integer(board.rows, 1, MAX_AXIS)
            and type(board.buttons) == "table" and #board.buttons == board.columns * board.rows and validStateColors(board.stateColors), "Invalid saved view")
        boardIds[board.id], maxBoard = true, math.max(maxBoard, board.id)
        for _, button in ipairs(board.buttons) do
            assert(type(button) == "table" and integer(button.id, 1, 2147483000) and not buttonIds[button.id]
                and name(button.name, 24) and type(button.customName) == "boolean"
                and (button.displayColour == nil or colour(button.displayColour)) and (button.fillMode == nil or button.fillMode == "state")
                and (button.buttonMode == nil or button.buttonMode == true)
                and (button.pulseHundredths == nil or integer(button.pulseHundredths, 50, 2147483647))
                and validStateColors(button.stateColors), "Invalid saved switch")
            local route = button.route
            assert(route == nil or type(route) == "table" and type(route.clientId) == "string" and route.clientId ~= ""
                and sideSet[route.side] and (route.color == nil or colour(route.color)), "Invalid saved routing")
            buttonIds[button.id], maxButton = true, math.max(maxButton, button.id)
        end
    end
    assert(integer(state.nextBoardId, maxBoard + 1, 2147483001)
        and integer(state.nextButtonId, maxButton + 1, 2147483001), "Invalid saved switch IDs")
    state.scenes, state.nextSceneId = state.scenes or {}, state.nextSceneId or 1
    ready = true
end

-- Normal app lifecycle: closing its last OS window stops the UI. Output intent
-- belongs to the OS and remains saved/applied, just like a physical switch.
local function build(width, height, state, api, context)
    local view, theme = context.view, state.settings
    local screen = view.screen or "home"
    local board = boardById(state, view.boardId)
    local needsBoard = {board = true, edit = true, switches = true, button = true, behavior = true, pulseLength = true,
        confirm = true, buttonColors = true, viewColors = true}
    if needsBoard[screen] and not board and not (screen == "confirm" and view.confirm == "allOff") then screen, view.screen = "home", "home" end
    if screen == "grid" and view.gridDraft.target ~= "new" and not board then screen, view.screen = "home", "home" end
    local selectedSwitch = buttonById(board, view.buttonId)
    if (screen == "button" or screen == "buttonColors" or screen == "behavior" or screen == "pulseLength") and not selectedSwitch then
        screen, view.screen = board and "edit" or "home", board and "edit" or "home"
    elseif screen == "pulseLength" and (not selectedSwitch.buttonMode or not view.pulseDraft) then
        screen, view.screen = "behavior", "behavior"
    end
    if screen == "palette" and view.colourField == "switch" and not buttonById(board, view.buttonId) then
        screen, view.screen = board and "switches" or "home", board and "switches" or "home"
    end
    if screen == "palette" and (view.colourScope == "button" and not buttonById(board, view.buttonId)
        or view.colourScope == "board" and not board) then screen, view.screen = "home", "home" end
    if screen == "confirm" and view.confirm == "clear" and not buttonById(board, view.buttonId) then screen, view.screen = "edit", "edit" end
    local ui = api.ui.content(width, height)
    local accent = api.getAppColour(context.appName or appName)
    ui.style(1, 1, width, height, api.ui.contrast(theme.background), theme.background)
    local function text(x, y, value, span, centred)
        if y < 1 or y > height then return end
        span = math.min(span or width - x + 1, width - x + 1)
        value = tostring(value):sub(1, span)
        if centred then value = string.rep(" ", math.floor((span - #value) / 2)) .. value end
        local line = ui.lines[y]
        ui.lines[y] = line:sub(1, x - 1) .. value .. line:sub(x + #value)
    end
    local function fit(value, span)
        return #value > span and span >= 4 and value:sub(1, span - 2) .. ".." or value:sub(1, span)
    end
    local function button(y, label, action, value, x1, x2, enabled, bg)
        ui.button(y, label, action, x1, x2, enabled, bg or theme.border, nil, value)
    end
    local function footer(label, action, otherLabel, otherAction)
        if otherLabel then
            local half = math.floor(width / 2)
            button(height, label, action, nil, 1, half)
            button(height, otherLabel, otherAction, nil, half + 1, width, true, accent)
        else button(height, label, action) end
    end
    local function pager(key, page, pages, row)
        view.pages = view.pages or {}
        view.pages[key] = {page = page, pages = pages}
        if pages <= 1 then return end
        local wing = math.max(2, math.floor(width / 4))
        button(row, "<", "page", {key = key, delta = -1}, 1, wing, page > 1)
        button(row, ">", "page", {key = key, delta = 1}, width - wing + 1, width, page < pages)
        text(wing + 1, row, page .. "/" .. pages, width - 2 * wing, true)
    end
    local function getPage(key, pages)
        return math.max(1, math.min(view.pages and view.pages[key] and view.pages[key].page or 1, pages))
    end
    local function menu(title, items, key, back, previous)
        ui.heading(title, accent)
        local path = previous and api.ui.breadcrumb(previous,width,height)
        local header = path and 2 or 1
        if path then ui.text(2,path); ui.style(1,2,width,1,api.ui.contrast(theme.background),theme.background) end
        local slots = #items <= height-header-1 and height-header-1 or height-header-2
        local pages = math.max(1, math.ceil(#items / slots))
        local page = getPage(key, pages)
        local gap = pages == 1 and height >= #items * 2 + 2 and 2 or 1
        local first = pages == 1 and height >= #items * gap + header+2 and header+2 or header+1
        local inset = width >= 24 and 2 or 0
        for row = 1, slots do
            local item = items[(page - 1) * slots + row]
            if item then button(first + (row - 1) * gap, item.label, item.action, item.value, 1 + inset, width - inset, item.enabled) end
        end
        pager(key, page, pages, height - 1)
        footer("Back", back)
    end
    local function tile(rect, title, status, action, value, fill, statusColour, previewTheme)
        local x, y, w, h = rect.x, rect.y, rect.w, rect.h
        local border = previewTheme and previewTheme.border or theme.border
        ui.style(x, y, w, h, api.ui.contrast(border), border)
        local insetX, insetY = w >= 7 and 1 or 0, h >= 5 and 1 or 0
        local innerX, innerY, innerW, innerH = x + insetX, y + insetY, w - 2 * insetX, h - 2 * insetY
        ui.style(innerX, innerY, innerW, innerH, api.ui.contrast(fill), fill)
        local labelRow = innerY + math.max(0, math.floor((innerH - (status and 2 or 1)) / 2))
        text(innerX, labelRow, fit(title, innerW), innerW, true)
        if status and innerH >= 2 then
            local row = math.min(innerY + innerH - 1, labelRow + 1)
            ui.style(innerX, row, innerW, 1, api.ui.contrast(statusColour or fill), statusColour or fill)
            text(innerX, row, fit(status, innerW), innerW, true)
        end
        if action then ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + w - 1, y1 = y, y2 = y + h - 1, action = action, value = value} end
    end
    local function switchStatus(switch, wire, previewTheme, previewBoard)
        local on = wire and (wire.pulse or wire.value)
        local status = not switch.route and "SET IO" or not wire and "ROUTE!" or not wire.online and (on and "ON offline" or "OFF offline")
            or not wire.confirmed and (on and "ON ..." or "OFF ...") or on and "ON" or switch.buttonMode and "PRESS" or "OFF"
        local theme = previewTheme or theme
        local field = wire and wire.online and wire.confirmed and (on and "active" or "inactive") or "pending"
        local statusColour = not switch.route and theme.unbound or stateColour(switch, previewBoard or board, theme, field)
        return status, statusColour
    end
    local function grid(count, wantedColumns, wantedRows, key, bottom, minWidth, minHeight, draw)
        local gap = theme.density == "roomy" and width >= 20 and height >= 10 and 1 or 0
        local columns = math.min(wantedColumns, math.max(1, math.floor((width + gap) / (minWidth + gap))))
        local function rowCount(last) return math.min(wantedRows, math.max(1, math.floor((last - 1 + gap) / (minHeight + gap)))) end
        local rows = rowCount(bottom)
        if count > columns * rows then bottom = bottom - 1; rows = rowCount(bottom) end
        local slots = columns * rows
        local pages = math.max(1, math.ceil(count / slots))
        local page = getPage(key, pages)
        for slot = 1, slots do
            local index = (page - 1) * slots + slot
            if index <= count then
                local column, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
                local x1 = 1 + math.floor(column * (width + gap) / columns)
                local x2 = math.floor((column + 1) * (width + gap) / columns) - gap
                local y1 = 2 + math.floor(row * (bottom - 1 + gap) / rows)
                local y2 = 1 + math.floor((row + 1) * (bottom - 1 + gap) / rows) - gap
                draw(index, {x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1})
            end
        end
        pager(key, page, pages, bottom + 1)
    end

    if screen == "home" then
        ui.heading("Views", accent)
        local all = outputs(api)
        if #state.boards == 0 then
            tile({x = 1, y = 2, w = width, h = height - 2}, "+ Add view", width >= 22 and "IO side or custom grid" or nil,
                "add", nil, accent)
        else
            grid(#state.boards, 3, MAX_VIEWS, "home", height - 2, 12, 3, function(index, rect)
                local item, on = state.boards[index], 0
                for _, switch in ipairs(item.buttons) do
                    local wire = wireFor(switch, all)
                    if wire and wire.value then on = on + 1 end
                end
                tile(rect, item.name, on .. " ON / " .. #item.buttons, "open", item.id, accent)
            end)
            button(height - 1, "+ Add view", "add", nil, nil, nil, #state.boards < MAX_VIEWS, accent)
        end
        button(height, "Scenes", "scenes", nil, 1, math.floor(width / 2))
        button(height, "Settings", "settings", nil, math.floor(width / 2) + 1, width)
    elseif screen == "sources" then
        local items = {{label = "+ Empty view", action = "empty"}}
        for _, client in ipairs(api.getIOClients()) do
            items[#items + 1] = {label = (client.online and "+ " or "- ") .. (client.displayName or client.id), action = "client", value = client.id}
        end
        menu("New view", items, "sources", "home")
    elseif screen == "sides" then
        local available = sides
        for _, client in ipairs(api.getIOClients()) do if client.id == view.newClient then available = client.sides; break end end
        local items = {}
        for _, side in ipairs(available) do items[#items + 1] = {label = side, action = "side", value = side} end
        menu("Select side", items, "sides", "sources", {(api.clientName or tostring)(view.newClient)})
        if #items == 0 then ui.text(3, "No free sides", true) end
    elseif screen == "create" then
        ui.heading("16 switches", accent)
        ui.text(2, view.newClient and (api.clientName or tostring)(view.newClient) or "Choose client", true)
        ui.text(3, "Side: " .. (view.newSide or "?"), true)
        if height >= 7 then ui.text(4, "New wires start OFF", true) end
        button(height - 1, "Create", "create", nil, nil, nil, true, accent)
        footer("Back", "sides")
    elseif screen == "board" or screen == "switches" then
        ui.heading(screen == "switches" and "Edit switches" or board.name, accent)
        local all = outputs(api)
        grid(#board.buttons, board.columns, board.rows, "switches", height - 1,
            (width < 20 or theme.density == "compact") and 5 or 7, 2, function(index, rect)
                local switch = board.buttons[index]
                local wire = wireFor(switch, all)
                local status, statusColour = switchStatus(switch, wire)
                -- Appearance overrides are local to this saved switch, not its wire.
                local fill = buttonColour(switch, theme, statusColour)
                tile(rect, switch.name, screen == "switches" and ("#" .. index .. " Edit") or status,
                    screen == "switches" and "editSwitch" or "toggle", switch.id, fill, statusColour)
            end)
        if screen == "board" then footer("Back", "home", "Edit", "edit") else footer("Back", "edit") end
    elseif screen == "edit" then
        local _, index = boardById(state, board.id)
        menu("View settings", {{label = "Rename view", action = "renameView"}, {label = "Edit switches", action = "switches"},
            {label = "State colors", action = "viewColors"}, {label = "Grid size", action = "resizeGrid"}, {label = "All OFF", action = "askOff"},
            {label = "Move earlier", action = "reorder", value = -1, enabled = index > 1},
            {label = "Move later", action = "reorder", value = 1, enabled = index < #state.boards},
            {label = "Delete view", action = "askDelete"}}, "edit", "board")
    elseif screen == "button" then
        local switch = buttonById(board, view.buttonId)
        ui.heading(fit(switch.name, width), accent)
        local route = switch.route
        ui.text(2, route and (api.clientName or tostring)(route.clientId) or "Not connected", true)
        if height >= 8 then ui.text(3, route and (route.side .. " / " .. (route.color and api.ui.colourName(route.color) or "Digital")) or "Choose Routing", true) end
        if height >= 10 and route then
            local wire = wireFor(switch, outputs(api))
            ui.text(4, not wire and "Routing changed" or not wire.online and "IO offline" or not wire.confirmed and "Waiting for IO"
                or (wire.value or wire.pulse) and "ON" or "OFF", true)
        end
        local third = math.floor(width / 3)
        button(height - 3, third>=6 and "Rename" or "Name", "renameSwitch", nil, 1, third)
        local _, statusColor = switchStatus(switch, wireFor(switch, outputs(api)))
        button(height - 3, "Color", "switchColour", nil, third + 1, 2 * third, true, buttonColour(switch, theme, statusColor))
        button(height - 3, third>=11 and "State colors" or "States", "buttonColors", nil, 2 * third + 1, width)
        local half = math.floor(width / 2)
        button(height - 2, half >= 7 and "Routing" or "Route", "route", nil, 1, half)
        button(height - 2, width - half >= 8 and "Behavior" or "Mode", "behavior", nil, half + 1, width)
        button(height - 1, "Disconnect", "askClear", nil, nil, nil, route ~= nil)
        footer("Back", "switches")
    elseif screen == "behavior" then
        ui.heading("Switch mode", accent)
        local half = math.floor(width / 2)
        button(2, "Switch", "setMode", "switch", 1, half, true, not selectedSwitch.buttonMode and accent or nil)
        button(2, "Button", "setMode", "button", half + 1, width, true, selectedSwitch.buttonMode and accent or nil)
        if selectedSwitch.buttonMode then
            button(3, "Time " .. api.ui.seconds(selectedSwitch.pulseHundredths or 100) .. "s", "editPulseLength")
            local minimum = api.outputPulseMinimum(outputName(selectedSwitch))
            if minimum then ui.text(4, "Min " .. api.ui.seconds(minimum) .. "s", true) end
        else ui.text(4, "Tap to toggle", true) end
        footer("Back", "button")
    elseif screen == "pulseLength" then
        local pad = api.ui.form(width, height, {}, accent, theme.background, theme.border)
        pad.numberPad("Length (s)", view.pulseDraft, "behavior", true)
        return pad.lines, pad.hits
    elseif screen == "buttonColors" or screen == "viewColors" then
        local scope = screen == "buttonColors" and "button" or "board"
        local target = scope == "button" and buttonById(board, view.buttonId) or board
        local items = {}
        for _, field in ipairs({"active", "inactive", "pending"}) do
            local inherited = not (target.stateColors and target.stateColors[field])
            local resolved = stateColour(scope == "button" and target or nil, board, theme, field)
            local label = field:sub(1,1):upper()..field:sub(2)..": "..api.ui.colourName(resolved)
            if inherited and width>=27 then label=label.." (inherit)" end
            items[#items+1]={label=label,action="statePalette",value={scope=scope,field=field}}
        end
        menu(scope == "button" and "Button state colors" or "View state colors",items,screen,scope == "button" and "button" or "edit")
    elseif screen == "grid" then
        local draft = view.gridDraft
        ui.heading(draft.target == "new" and "Empty view" or "Grid size", accent)
        ui.text(2, draft.columns .. " x " .. draft.rows .. " = " .. draft.columns * draft.rows, true)
        local third = math.floor(width / 3)
        for _, item in ipairs({{row = 3, key = "columns", short = "C", label = "Cols"}, {row = 4, key = "rows", short = "R", label = "Rows"}}) do
            button(item.row, "-", "gridStep", {key = item.key, delta = -1}, 1, third, draft[item.key] > 1)
            text(third + 1, item.row, (third >= 7 and item.label .. " " or item.short) .. draft[item.key], width - 2 * third, true)
            button(item.row, "+", "gridStep", {key = item.key, delta = 1}, width - third + 1, width, draft[item.key] < MAX_AXIS)
        end
        if height >= 10 then
            local pw, ph = math.min(width - 2, draft.columns * 3), math.min(height - 7, draft.rows * 2)
            local left = 1 + math.floor((width - pw) / 2)
            local previewColumns, previewRows = math.min(draft.columns, pw), math.min(draft.rows, ph)
            for row = 0, previewRows - 1 do
                for column = 0, previewColumns - 1 do
                    local x1, x2 = left + math.floor(column * pw / previewColumns), left + math.floor((column + 1) * pw / previewColumns) - 1
                    local y1, y2 = 6 + math.floor(row * ph / previewRows), 5 + math.floor((row + 1) * ph / previewRows)
                    ui.style(x1, y1, x2 - x1 + 1, y2 - y1 + 1, nil, (row + column) % 2 == 0 and accent or theme.border)
                end
            end
        end
        button(height - 1, draft.target == "new" and "Create" or "Save grid", "saveGrid", nil, nil, nil, true, accent)
        footer("Cancel", draft.target == "new" and "sources" or "edit")
    elseif screen == "settings" then
        menu("App settings", {{label = "UI color", action = "accent"}, {label = "Background", action = "palette", value = "background"},
            {label = "Button borders", action = "palette", value = "border"}, {label = "Unwired tiles", action = "palette", value = "unbound"},
            {label = "Active color", action = "palette", value = "active"}, {label = "Inactive color", action = "palette", value = "inactive"},
            {label = "Pending color", action = "palette", value = "pending"},
            {label = "Density: " .. theme.density, action = "density"}, {label = "All switches OFF", action = "askAllOff"}}, "settings", "home")
    elseif screen == "palette" then
        local isFill = view.colourField == "switch"
        local switch = (isFill or view.colourScope == "button") and buttonById(board, view.buttonId)
        local target = view.colourScope == "button" and switch or view.colourScope == "board" and board
        local preview, previewBoard, previewSwitch = copy(theme), (isFill or view.colourScope) and copy(board), copy(switch)
        local titles = {accent = "UI color", background = "Background", border = "Button borders", unbound = "Unwired tiles",
            active = "Active color", inactive = "Inactive color", pending = "Pending color"}
        local draft = view.colourDraft or (view.colourField == "accent" and accent or theme[view.colourField])
        if isFill then
            if view.colourMode == "io" then previewSwitch.displayColour, previewSwitch.fillMode = nil, nil
            elseif view.colourMode == "state" then previewSwitch.displayColour, previewSwitch.fillMode = nil, "state"
            else previewSwitch.displayColour, previewSwitch.fillMode = draft, nil end
            local _, statusColor = switchStatus(previewSwitch,wireFor(switch,outputs(api)))
            draft = buttonColour(previewSwitch,theme,statusColor)
        elseif target then
            local nextTarget = view.colourScope == "button" and previewSwitch or previewBoard
            nextTarget.stateColors = nextTarget.stateColors or {}
            nextTarget.stateColors[view.colourField] = not view.colourAuto and draft or nil
            draft = stateColour(previewSwitch,previewBoard,preview,view.colourField)
        elseif view.colourField ~= "accent" then preview[view.colourField] = draft end
        ui.lines, ui.hits = api.ui.palette(width,height,
            not (isFill and view.colourMode~="fixed" or target and view.colourAuto) and draft or nil,
            isFill and "Button color" or titles[view.colourField])
        table.remove(ui.hits)
        ui.lines.hits = ui.hits
        local previewAccent = view.colourField == "accent" and draft or accent
        ui.style(1,1,width,1,api.ui.contrast(previewAccent),previewAccent)
        if width>=24 and height>=15 then
            local ph=math.min(5,height-12); local py=height-ph-1
            ui.style(1,py-1,width,ph+1,api.ui.contrast(preview.background),preview.background)
            ui.text(py-1,"Preview",true)
            ui.style(2,py-1,width-2,1,api.ui.contrast(previewAccent),previewAccent)
            if isFill then
                local status,statusColor=switchStatus(previewSwitch,wireFor(switch,outputs(api)))
                tile({x=2,y=py,w=width-2,h=ph},switch.name,status,nil,nil,draft,statusColor,preview)
            else
                for i,field in ipairs({"active","inactive","pending"}) do
                    local left=2+math.floor((i-1)*(width-2)/3)
                    local right=1+math.floor(i*(width-2)/3)
                    local statusColor=stateColour(previewSwitch,previewBoard,preview,field)
                    local fill=previewSwitch and buttonColour(previewSwitch,preview,statusColor) or (i==1 and 8 or preview.unbound)
                    tile({x=left,y=py,w=right-left,h=ph},i==1 and "ON" or i==2 and "OFF" or "...",field,nil,nil,fill,statusColor,preview)
                end
            end
        end
        if isFill then
            local labels={width>=28 and "Apply" or "Set",width>=44 and "IO default" or "IO",width>=36 and "By state" or width>=24 and "State" or "St",width>=24 and "Cancel" or "Back"}
            if view.colourMode=="io" then labels[2]="*"..labels[2] end
            if view.colourMode=="state" then labels[3]="*"..labels[3] end
            for i,action in ipairs({"applyColour","autoColour","stateFill","cancel"}) do
                button(height,labels[i],action,nil,1+math.floor((i-1)*width/4),math.floor(i*width/4),true,i==1 and previewAccent or theme.border)
            end
        elseif target then
            local third=math.floor(width/3)
            button(height,third>=5 and "Apply" or "Set","applyColour",nil,1,third,true,previewAccent)
            button(height,third>=7 and "Inherit" or "Base","autoColour",nil,third+1,2*third,true,view.colourAuto and previewAccent or theme.border)
            button(height,third>=6 and "Cancel" or "Back","cancel",nil,2*third+1,width)
        else
            local half=math.floor(width/2)
            button(height,"Apply","applyColour",nil,1,half,true,previewAccent)
            button(height,"Cancel","cancel",nil,half+1,width)
        end
    elseif screen == "keyboard" then
        local keyboard = view.keyboard
        api.ui.keyboard(ui, width, height, keyboard, accent,
            {{"Save", "saveName", nil, keyboard.draft:find("%S") ~= nil}, {"Clr", "clearName"}, {"Back", "cancelName"}})
    elseif screen == "confirm" then
        local labels = {delete = "Delete view?", clear = "Disconnect?", shrink = "Remove cells?", off = "All OFF?", allOff = "All OFF?"}
        ui.heading(labels[view.confirm] or "Confirm?", accent)
        ui.text(2, view.confirm == "shrink" and "Last cells removed" or view.confirm == "allOff" and "Every view" or board and board.name or "Switchboard", true)
        ui.text(3, (view.confirm == "off" or view.confirm == "allOff") and "Saved and sent" or width >= 22 and "Unused wires turn OFF" or "Unshared OFF", true)
        button(height - 1, "Confirm", "confirm", nil, nil, nil, true, 16384)
        footer("Cancel", "cancelConfirm")
    elseif screen == "message" then
        ui.heading("Switchboard", accent)
        local chunks, remaining = {}, view.message or "Something changed"
        repeat chunks[#chunks + 1], remaining = remaining:sub(1, width), remaining:sub(width + 1) until #remaining == 0
        local slots = #chunks <= height - 2 and height - 2 or height - 3
        local pages = math.max(1, math.ceil(#chunks / slots))
        local page = getPage("message", pages)
        for row = 1, slots do ui.text(row + 1, chunks[(page - 1) * slots + row] or "") end
        pager("message", page, pages, height - 1)
        footer("Back", "messageBack")
    end
    return ui.lines, ui.hits
end

local function sceneById(state, id)
    for i, scene in ipairs(state.scenes) do if scene.id == id then return scene, i end end
end

local function sceneUI(w, h, state, api, view)
    view.sceneView = view.sceneView or {}
    local ui = api.ui.form(w, h, view.sceneView, api.getAppColour(appName))
    local screen, scene = view.screen, sceneById(state, view.sceneId)
    if screen == "sceneBoards" then
        local rows = {{"All views", "capture", 0}}
        for _, board in ipairs(state.boards) do rows[#rows + 1] = {board.name, "capture", board.id} end
        ui.menu("Capture scene", rows, "sources", {{"Back", "scenes"}})
    elseif screen == "sceneName" and view.sceneKeyboard then ui.keyboard(view.sceneKeyboard)
    elseif screen == "sceneDelete" and scene then
        ui.info("Delete scene?", {scene.name}, "delete", "sceneEdit")
        ui.footer({{"Cancel", "sceneEdit"}, {"Delete", "delete", nil, true, 16384}})
    elseif screen == "sceneEdit" and scene then
        ui.menu(scene.name, {{#scene.entries .. " saved switches", nil, nil, false},
            {"Rename", "rename"}, {"Delete", "sceneDelete"}}, "edit", {{"Back", "sceneListEdit"}})
    else
        local rows = {}
        for _, item in ipairs(state.scenes) do rows[#rows + 1] = {item.name,
            screen == "sceneListEdit" and "edit" or "apply", item.id} end
        rows[#rows + 1] = {"+ New scene", "sceneBoards", nil, #state.scenes < 24 and #state.boards > 0}
        local footer = screen == "sceneListEdit" and {{"Back", "scenes"}} or {{"Back", "home"}, {"Edit", "sceneListEdit"}}
        ui.menu(view.sceneStatus or "Scenes", rows, "scenes", footer)
    end
    return ui
end

local function sceneTouch(x, y, w, h, state, api, view)
    local action, value = api.ui.actionAt(sceneUI(w, h, state, api, view).hits, x, y)
    if not action then return false end
    local scene, index = sceneById(state, view.sceneId)
    local keyboard = view.sceneKeyboard
    if action == "page" then view.sceneView.pages[value.key] = value.page
    elseif action == "capture" or action == "rename" then
        view.captureBoard = action == "capture" and value or nil
        view.sceneKeyboard = {draft = action == "rename" and scene.name or "Scene " .. state.nextSceneId,
            bank = 0, page = 1, back = view.screen}
        view.screen = "sceneName"
    elseif view.screen == "sceneName" and api.ui.editText(keyboard, action, value, 32) then return true
    elseif action == "saveText" then
        local label = keyboard.draft:match("^%s*(.-)%s*$")
        if label == "" then return true end
        if view.captureBoard ~= nil then
            if #state.scenes >= 24 then view.screen = "scenes"; return true end
            local entries, all = {}, outputs(api)
            for _, board in ipairs(state.boards) do
                if view.captureBoard == 0 or view.captureBoard == board.id then
                    for _, switch in ipairs(board.buttons) do
                        local wire = wireFor(switch, all)
                        if wire and not switch.buttonMode then entries[#entries + 1] = {id = switch.id, route = copy(switch.route), value = wire.value} end
                    end
                end
            end
            if #entries == 0 or #entries > 256 then
                view.sceneStatus = #entries == 0 and "No routed switches" or "Choose up to 256"
                view.screen = "scenes"
                return true
            end
            if commit(state, api, view, function()
                state.scenes[#state.scenes + 1] = {id = state.nextSceneId, name = label, entries = entries}
                state.nextSceneId = state.nextSceneId + 1
            end) then view.screen, view.sceneStatus = "scenes", nil end
        elseif scene then
            if commit(state, api, view, function() scene.name = label end) then view.screen = "sceneEdit" end
        else view.screen = "scenes" end
    elseif action == "edit" then view.sceneId, view.screen = value, "sceneEdit"
    elseif action == "delete" and scene then
        if commit(state, api, view, function() table.remove(state.scenes, index) end) then view.screen = "scenes" end
    elseif action == "apply" then
        local selected = sceneById(state, value)
        if not selected then return true end
        local all, changes, switches = outputs(api), {}, {}
        for _, board in ipairs(state.boards) do
            for _, switch in ipairs(board.buttons) do if not switch.buttonMode then switches[switch.id] = true end end
        end
        for _, entry in ipairs(selected.entries) do
            local logical = appName .. "_switch_" .. entry.id
            if switches[entry.id] and sameRoute(entry.route, all[logical]) then
                changes[#changes + 1] = {name = logical, value = entry.value}
            end
        end
        if #changes > 0 then
            local ok, err = api.updateOutputs(changes)
            if not ok then notify(view, tostring(err), "scenes")
            else view.sceneStatus = #changes == #selected.entries and "Scene applied" or "Applied valid routes" end
        else view.sceneStatus = "No matching routes" end
    else view.screen, view.sceneStatus = action, nil end
    api.invalidateAppViews(appName)
    return true
end

function app.render(width, height, state, api, context)
    if ready and (context.view.screen or ""):match("^scene") then
        return sceneUI(width, height, state, api, context.view).lines
    end
    if not ready then return {"Switchboard blocked", "Check OS log"} end
    return (build(width, height, state, api, context))
end

local function createBoard(state, api, view, columns, rows, clientId, side)
    if #state.boards >= MAX_VIEWS then notify(view, "Maximum 64 views"); return end
    local created
    local ok = commit(state, api, view, function()
        created = {id = state.nextBoardId, name = clientId and ((api.clientName or tostring)(clientId) .. " " .. side):sub(1, 32) or "View " .. state.nextBoardId,
            columns = columns, rows = rows, buttons = {}}
        state.nextBoardId = state.nextBoardId + 1
        for index = 1, columns * rows do
            local route = clientId and {clientId = clientId, side = side, color = 2 ^ (index - 1)} or nil
            created.buttons[index] = newButton(state, index, api, route)
        end
        state.boards[#state.boards + 1] = created
    end, function()
        local changes = {}
        for _, switch in ipairs(created.buttons) do if switch.route then changes[#changes + 1] = mapping(switch, false) end end
        return changes
    end)
    if ok then
        -- Return to the selection so the newly created view is visible there.
        view.screen, view.boardId, view.pages = "home", created.id, {home = {page = MAX_VIEWS, pages = MAX_VIEWS}}
    end
end

local function resizeBoard(state, api, view, board)
    local draft, removed = view.gridDraft, {}
    if board.columns ~= draft.beforeColumns or board.rows ~= draft.beforeRows then
        notify(view, "Grid changed in another window; open Grid size again", "edit"); return
    end
    local count = draft.columns * draft.rows
    local ok = commit(state, api, view, function()
        for index = #board.buttons, count + 1, -1 do
            removed[#removed + 1] = {name = outputName(board.buttons[index]), remove = true}
            table.remove(board.buttons, index)
        end
        for index = #board.buttons + 1, count do board.buttons[index] = newButton(state, index, api) end
        board.columns, board.rows = draft.columns, draft.rows
    end, function() return removed end)
    if ok then view.screen, view.pages = "edit", {} end
end

function app.handleIOSelection(key, address, state, api, context)
    local boardId, buttonId = key:match("^route_(%d+)_(%d+)$")
    local board = boardById(state, tonumber(boardId))
    local switch = buttonById(board, tonumber(buttonId))
    local view = context and context.view
    if not switch or not view then return false, "That switch was removed" end
    if view.routeKey ~= key or not sameRoute(switch.route, view.routeBefore) then return false, "Routing changed in another window; cancel and retry" end
    if type(address) ~= "table" or type(address.clientId) ~= "string" or not sideSet[address.side]
        or address.color ~= nil and not colour(address.color) then return false, "Choose a valid output" end
    if sameRoute(switch.route, address) and wireFor(switch, outputs(api)) then
        view.routeKey, view.routeBefore = nil, nil
        return true -- Re-selecting the existing route must not turn it OFF.
    end
    local previous = copy(state)
    switch.route = copy(address)
    if not switch.customName then switch.name = address.color and api.ui.colourName(address.color) or "Digital" end
    local ok, err = api.updateOutputs({mapping(switch, false)})
    if not ok then restore(state, previous); return false, err end
    view.routeKey, view.routeBefore = nil, nil
    return true
end

function app.handleTouch(x, y, width, height, state, api, context)
    if not ready then return false end
    if (context.view.screen or ""):match("^scene") then
        return sceneTouch(x, y, width, height, state, api, context.view)
    end
    local _, hits = build(width, height, state, api, context)
    local action, value
    for _, hit in ipairs(hits) do
        if hit.enabled ~= false and api.ui.hit(hit, x, y) then action, value = hit.action, hit.value; break end
    end
    if not action then return false end
    local view = context.view
    local board, boardIndex = boardById(state, view.boardId)
    local switch = buttonById(board, view.buttonId)
    if action == "page" then
        local p = view.pages[value.key]
        p.page = math.max(1, math.min(p.pages, p.page + value.delta))
    elseif action == "open" then view.boardId, view.screen, view.pages = value, "board", {}
    elseif action == "add" then view.screen, view.pages = "sources", {}
    elseif action == "client" then view.newClient, view.screen, view.pages = value, "sides", {}
    elseif action == "side" then view.newSide, view.screen = value, "create"
    elseif action == "create" then createBoard(state, api, view, 4, 4, view.newClient, view.newSide)
    elseif action == "empty" or action == "resizeGrid" then
        view.gridDraft = {target = action == "empty" and "new" or "existing", columns = action == "empty" and 4 or board.columns,
            rows = action == "empty" and 4 or board.rows, beforeColumns = board and board.columns, beforeRows = board and board.rows}
        view.screen = "grid"
    elseif action == "gridStep" then
        local draft = view.gridDraft
        draft[value.key] = math.max(1, math.min(MAX_AXIS, draft[value.key] + value.delta))
    elseif action == "saveGrid" then
        if view.gridDraft.target == "new" then createBoard(state, api, view, view.gridDraft.columns, view.gridDraft.rows)
        elseif not board then view.screen = "home"
        elseif view.gridDraft.columns * view.gridDraft.rows < #board.buttons then
            view.confirm, view.confirmBack, view.screen = "shrink", "grid", "confirm"
        else resizeBoard(state, api, view, board) end
    elseif action == "toggle" or action == "editSwitch" then
        view.buttonId = value
        switch = buttonById(board, value)
        if action == "editSwitch" or not switch.route then view.screen = "button"
        else
            local wire = wireFor(switch, outputs(api))
            if not wire then notify(view, "Routing missing or changed. Use Edit > Routing to reconnect this switch.")
            else
                local ok, err
                if switch.buttonMode then ok, err = api.pulseOutput(outputName(switch), switch.pulseHundredths or 100)
                else
                    ok, err = api.setOutput(outputName(switch), not (wire.pulse or wire.value))
                    if not ok then err = "Could not save: " .. tostring(err) end
                end
                if not ok then notify(view, err) end
            end
        end
    elseif action == "setMode" then
        local isButton = value == "button"
        if isButton ~= (switch.buttonMode == true) then
            local changes
            if isButton and switch.route then
                local all, id = outputs(api), outputName(switch)
                local wire = wireFor(switch, all)
                if wire and wire.value then
                    local shared = false
                    for name, other in pairs(all) do
                        if name ~= id and sameRoute(wire, other) then shared = true; break end
                    end
                    if not shared then changes = {{name = id, value = false}} end
                end
            end
            if commit(state, api, view, function() switch.buttonMode = isButton or nil end, function() return changes end) then
                api.cancelOutputPulse(outputName(switch))
                api.invalidateAppViews(appName)
            end
        end
    elseif action == "editPulseLength" then
        view.pulseBefore = switch.pulseHundredths
        view.pulseDraft, view.screen = api.ui.seconds(switch.pulseHundredths or 100), "pulseLength"
    elseif action == "digit" then view.pulseDraft = api.ui.editNumber(view.pulseDraft, value, 12)
    elseif action == "setNumber" then
        local minimum = api.outputPulseMinimum(outputName(switch)) or 50
        local hundredths = api.ui.durationHundredths(view.pulseDraft, minimum)
        if switch.pulseHundredths ~= view.pulseBefore then notify(view, "Length changed; open it again", "behavior")
        elseif not hundredths then notify(view, "Minimum " .. api.ui.seconds(minimum) .. "s. Use up to two decimal places.", "pulseLength")
        elseif commit(state, api, view, function() switch.pulseHundredths = hundredths end) then
            view.screen, view.pulseDraft = "behavior", nil
            api.invalidateAppViews(appName)
        end
    elseif action == "route" then
        local key = "route_" .. board.id .. "_" .. switch.id
        view.routeKey, view.routeBefore = key, copy(switch.route)
        local ok, err = api.pickIO(context.windowId, key, "output", switch.route)
        if not ok then notify(view, err) end
    elseif action == "renameView" or action == "renameSwitch" then
        local target = action == "renameView" and board or switch
        view.keyboard = {kind = action == "renameView" and "view" or "switch", id = target.id, draft = target.name,
            original = target.name, bank = "abc", page = 1, back = view.screen}
        view.screen = "keyboard"
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value,
        view.keyboard.kind == "view" and 32 or 24) then return true
    elseif action == "clearName" then view.keyboard.draft = ""
    elseif action == "cancelName" then view.screen = view.keyboard.back; view.keyboard = nil
    elseif action == "saveName" then
        local keyboard = view.keyboard
        local target = keyboard.kind == "view" and boardById(state, keyboard.id) or buttonById(board, keyboard.id)
        if not target then notify(view, "This item was removed in another window", "home")
        elseif target.name ~= keyboard.original then notify(view, "Name changed in another window; open the editor again", keyboard.back)
        else
            local clean = keyboard.draft:gsub("^%s+", ""):gsub("%s+$", "")
            local ok = commit(state, api, view, function()
                target.name = clean
                if keyboard.kind == "switch" then target.customName = true end
            end)
            if ok then view.screen, view.keyboard = keyboard.back, nil end
        end
    elseif action == "accent" then
        view.colourScope = nil
        view.colourField, view.colourDraft, view.screen = "accent", api.getAppColour(context.appName or appName), "palette"
    elseif action == "palette" then
        view.colourScope, view.colourAuto = nil, false
        view.colourField, view.colourDraft, view.screen = value, state.settings[value], "palette"
    elseif action == "statePalette" then
        local target = value.scope == "button" and switch or board
        view.colourScope, view.colourField = value.scope, value.field
        view.colourBefore = target.stateColors and target.stateColors[value.field]
        view.colourDraft = stateColour(value.scope == "button" and switch or nil, board, state.settings, value.field)
        view.colourAuto, view.screen = view.colourBefore == nil, "palette"
    elseif action == "switchColour" then
        view.colourScope = nil
        view.colourField, view.colourDraft, view.colourBefore = "switch", buttonColour(switch, state.settings), switch.displayColour
        view.colourModeBefore = switch.fillMode
        view.colourMode = switch.fillMode == "state" and "state" or switch.displayColour and "fixed" or "io"
        view.colourAuto, view.screen = switch.displayColour == nil and switch.fillMode ~= "state", "palette"
    elseif action == "colour" then view.colourDraft, view.colourAuto, view.colourMode = value, false, "fixed"
    elseif action == "autoColour" then view.colourAuto, view.colourMode = true, "io"
    elseif action == "stateFill" then view.colourMode, view.colourAuto = "state", false
    elseif action == "applyColour" then
        local ok, err
        if view.colourField == "switch" then
            if switch.displayColour ~= view.colourBefore or switch.fillMode ~= view.colourModeBefore then
                notify(view, "Button color changed in another window; reopen Color", "button")
            else
                ok = commit(state, api, view, function()
                    switch.displayColour = view.colourMode == "fixed" and view.colourDraft or nil
                    switch.fillMode = view.colourMode == "state" and "state" or nil
                end)
            end
        elseif view.colourScope then
            local target = view.colourScope == "button" and switch or board
            if (target.stateColors and target.stateColors[view.colourField]) ~= view.colourBefore then
                notify(view,"State color changed in another window; reopen the editor",view.colourScope == "button" and "buttonColors" or "viewColors")
            else
                ok = commit(state,api,view,function()
                    target.stateColors = target.stateColors or {}
                    target.stateColors[view.colourField] = not view.colourAuto and view.colourDraft or nil
                end)
            end
        elseif view.colourField == "accent" then
            ok, err = api.setAppColour(context.appName or appName, view.colourDraft)
            if not ok then notify(view, "Could not save: " .. tostring(err)) end
        else ok = commit(state, api, view, function() state.settings[view.colourField] = view.colourDraft end) end
        if ok then view.screen = view.colourScope == "button" and "buttonColors" or view.colourScope == "board" and "viewColors"
            or view.colourField == "switch" and "button" or "settings"; api.invalidateAppViews(appName) end
    elseif action == "cancel" then view.screen = view.colourScope == "button" and "buttonColors" or view.colourScope == "board" and "viewColors"
        or view.colourField == "switch" and "button" or "settings"
    elseif action == "density" then
        commit(state, api, view, function() state.settings.density = state.settings.density == "roomy" and "compact" or "roomy" end)
    elseif action == "reorder" then
        commit(state, api, view, function()
            state.boards[boardIndex], state.boards[boardIndex + value] = state.boards[boardIndex + value], state.boards[boardIndex]
        end)
    elseif action == "askOff" or action == "askAllOff" or action == "askDelete" or action == "askClear" then
        local kinds = {askOff = "off", askAllOff = "allOff", askDelete = "delete", askClear = "clear"}
        view.confirm, view.confirmBack, view.screen = kinds[action], view.screen, "confirm"
    elseif action == "cancelConfirm" then view.screen = view.confirmBack
    elseif action == "confirm" then
        if view.confirm == "shrink" then resizeBoard(state, api, view, board)
        else
            local changes = {}
            local ok = commit(state, api, view, function()
                if view.confirm == "delete" then
                    for _, item in ipairs(board.buttons) do changes[#changes + 1] = {name = outputName(item), remove = true} end
                    table.remove(state.boards, boardIndex)
                elseif view.confirm == "clear" then
                    local _, index = buttonById(board, switch.id)
                    changes[1] = {name = outputName(switch), remove = true}
                    switch.route = nil
                    if not switch.customName then switch.name = "Switch " .. index end
                else
                    local all = outputs(api)
                    for _, item in ipairs(view.confirm == "allOff" and state.boards or {board}) do
                        for _, sw in ipairs(item.buttons) do
                            if all[outputName(sw)] then changes[#changes + 1] = {name = outputName(sw), value = false} end
                        end
                    end
                end
            end, function() return changes end)
            if ok then view.screen = view.confirm == "delete" and "home" or view.confirmBack end
        end
    elseif action == "messageBack" then view.screen = view.messageBack or "home"
    else view.screen = action end
    return true
end

return app
