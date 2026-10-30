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
    local keys = {}; for key in pairs(state) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do state[key] = nil end
    for key, value in pairs(old) do state[key] = value end
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
local function buttonColour(button, theme)
    return button.displayColour or button.route and button.route.color or theme.unbound
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
    assert(api.sharedOutputs and api.ui and api.pickIO and api.setAppColour, "Switchboard requires the bundled-v14 OS update")
    appName = context and context.appName or "switchboard"
    if state.version == nil then
        state.version, state.boards, state.nextBoardId, state.nextButtonId = 1, {}, 1, 1
        state.settings = {background = 32768, border = 128, unbound = 128, density = "roomy"}
    end
    if type(state.settings) == "table" then
        if state.settings.active == nil then state.settings.active = 32 end
        if state.settings.inactive == nil then state.settings.inactive = state.settings.border end
    end
    assert(state.version == 1 and type(state.boards) == "table" and #state.boards <= MAX_VIEWS, "Invalid saved switchboard")
    assert(type(state.settings) == "table" and colour(state.settings.background) and colour(state.settings.border)
        and colour(state.settings.unbound) and colour(state.settings.active) and colour(state.settings.inactive)
        and (state.settings.density == "roomy" or state.settings.density == "compact"), "Invalid saved switchboard style")
    local boardIds, buttonIds, maxBoard, maxButton = {}, {}, 0, 0
    for _, board in ipairs(state.boards) do
        assert(type(board) == "table" and integer(board.id, 1, 2147483000) and not boardIds[board.id]
            and name(board.name, 32) and integer(board.columns, 1, MAX_AXIS) and integer(board.rows, 1, MAX_AXIS)
            and type(board.buttons) == "table" and #board.buttons == board.columns * board.rows, "Invalid saved view")
        boardIds[board.id], maxBoard = true, math.max(maxBoard, board.id)
        for _, button in ipairs(board.buttons) do
            assert(type(button) == "table" and integer(button.id, 1, 2147483000) and not buttonIds[button.id]
                and name(button.name, 24) and type(button.customName) == "boolean"
                and (button.displayColour == nil or colour(button.displayColour)), "Invalid saved switch")
            local route = button.route
            assert(route == nil or type(route) == "table" and type(route.clientId) == "string" and route.clientId ~= ""
                and sideSet[route.side] and (route.color == nil or colour(route.color)), "Invalid saved routing")
            buttonIds[button.id], maxButton = true, math.max(maxButton, button.id)
        end
    end
    assert(integer(state.nextBoardId, maxBoard + 1, 2147483001)
        and integer(state.nextButtonId, maxButton + 1, 2147483001), "Invalid saved switch IDs")
    ready = true
end

-- Normal app lifecycle: closing its last OS window stops the UI. Output intent
-- belongs to the OS and remains saved/applied, just like a physical switch.
local function build(width, height, state, api, context)
    local view, theme = context.view, state.settings
    local screen = view.screen or "home"
    local board = boardById(state, view.boardId)
    local needsBoard = {board = true, edit = true, switches = true, button = true, confirm = true}
    if needsBoard[screen] and not board and not (screen == "confirm" and view.confirm == "allOff") then screen, view.screen = "home", "home" end
    if screen == "grid" and view.gridDraft.target ~= "new" and not board then screen, view.screen = "home", "home" end
    if screen == "button" and not buttonById(board, view.buttonId) then screen, view.screen = "edit", "edit" end
    if screen == "palette" and view.colourField == "switch" and not buttonById(board, view.buttonId) then
        screen, view.screen = board and "switches" or "home", board and "switches" or "home"
    end
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
    local function menu(title, items, key, back)
        ui.heading(title, accent)
        local slots = #items <= height - 2 and height - 2 or height - 3
        local pages = math.max(1, math.ceil(#items / slots))
        local page = getPage(key, pages)
        local gap = pages == 1 and height >= #items * 2 + 2 and 2 or 1
        local first = pages == 1 and height >= #items * gap + 3 and 3 or 2
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
    local function switchStatus(switch, wire)
        local status = not switch.route and "SET IO" or not wire and "ROUTE!" or not wire.online and (wire.value and "ON offline" or "OFF offline")
            or not wire.confirmed and (wire.value and "ON ..." or "OFF ...") or wire.value and "ON" or "OFF"
        local statusColour = not switch.route and theme.unbound or (not wire or not wire.online) and 16384
            or not wire.confirmed and 2 or wire.value and theme.active or theme.inactive
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
        footer("Settings", "settings")
    elseif screen == "sources" then
        local items = {{label = "+ Empty view", action = "empty"}}
        for _, client in ipairs(api.getIOClients()) do
            items[#items + 1] = {label = (client.online and "+ " or "- ") .. client.id, action = "client", value = client.id}
        end
        menu("New view", items, "sources", "home")
    elseif screen == "sides" then
        local available = sides
        for _, client in ipairs(api.getIOClients()) do if client.id == view.newClient then available = client.sides; break end end
        local items = {}
        for _, side in ipairs(available) do items[#items + 1] = {label = side, action = "side", value = side} end
        menu("Select side", items, "sides", "sources")
        if #items == 0 then ui.text(2, "No free sides", true) end
    elseif screen == "create" then
        ui.heading("16 switches", accent)
        ui.text(2, view.newClient or "Choose client", true)
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
                local fill = buttonColour(switch, theme)
                tile(rect, switch.name, screen == "switches" and ("#" .. index .. " Edit") or status,
                    screen == "switches" and "editSwitch" or "toggle", switch.id, fill, statusColour)
            end)
        if screen == "board" then footer("Back", "home", "Edit", "edit") else footer("Back", "edit") end
    elseif screen == "edit" then
        local _, index = boardById(state, board.id)
        menu("View settings", {{label = "Rename view", action = "renameView"}, {label = "Edit switches", action = "switches"},
            {label = "Grid size", action = "resizeGrid"}, {label = "All OFF", action = "askOff"},
            {label = "Move earlier", action = "reorder", value = -1, enabled = index > 1},
            {label = "Move later", action = "reorder", value = 1, enabled = index < #state.boards},
            {label = "Delete view", action = "askDelete"}}, "edit", "board")
    elseif screen == "button" then
        local switch = buttonById(board, view.buttonId)
        ui.heading(fit(switch.name, width), accent)
        local route = switch.route
        ui.text(2, route and route.clientId or "Not connected", true)
        if height >= 8 then ui.text(3, route and (route.side .. " / " .. (route.color and api.ui.colourName(route.color) or "Digital")) or "Choose Routing", true) end
        if height >= 10 and route then
            local wire = wireFor(switch, outputs(api))
            ui.text(4, not wire and "Routing changed" or not wire.online and "IO offline" or not wire.confirmed and "Waiting for IO" or wire.value and "ON" or "OFF", true)
        end
        local half = math.floor(width / 2)
        button(height - 3, "Rename", "renameSwitch", nil, 1, half)
        button(height - 3, width - half >= 13 and "Button colour" or "Colour", "switchColour", nil,
            half + 1, width, true, buttonColour(switch, theme))
        button(height - 2, "Routing", "route")
        button(height - 1, "Disconnect", "askClear", nil, nil, nil, route ~= nil)
        footer("Back", "switches")
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
        menu("App settings", {{label = "UI colour", action = "accent"}, {label = "Background", action = "palette", value = "background"},
            {label = "Button borders", action = "palette", value = "border"}, {label = "Unwired tiles", action = "palette", value = "unbound"},
            {label = "Active colour", action = "palette", value = "active"}, {label = "Inactive colour", action = "palette", value = "inactive"},
            {label = "Density: " .. theme.density, action = "density"}, {label = "All switches OFF", action = "askAllOff"}}, "settings", "home")
    elseif screen == "palette" then
        local switch = view.colourField == "switch" and buttonById(board, view.buttonId)
        local titles = {accent = "UI colour", background = "Background", border = "Button borders", unbound = "Unwired tiles",
            active = "Active colour", inactive = "Inactive colour"}
        local draft = switch and view.colourAuto and (switch.route and switch.route.color or theme.unbound)
            or view.colourDraft or (view.colourField == "accent" and accent or theme[view.colourField])
        local title = switch and (width >= 20 and "Button colour" or "Colour") or titles[view.colourField]
        ui.lines, ui.hits = api.ui.palette(width, height, not (switch and view.colourAuto) and draft or nil, title)
        table.remove(ui.hits) -- Replace the stock Back action with Apply/Cancel.
        ui.lines.hits = ui.hits
        local preview = copy(theme)
        local previewAccent = view.colourField == "accent" and draft or accent
        if not switch and view.colourField ~= "accent" then preview[view.colourField] = draft end
        ui.style(1, 1, width, 1, api.ui.contrast(previewAccent), previewAccent)
        if width >= 24 and height >= 15 then
            local ph = math.min(5, height - 12)
            local py = height - ph - 1
            ui.style(1, py - 1, width, ph + 1, api.ui.contrast(preview.background), preview.background)
            ui.text(py - 1, "Preview", true)
            ui.style(2, py - 1, width - 2, 1, api.ui.contrast(previewAccent), previewAccent)
            if switch then
                local status, statusColour = switchStatus(switch, wireFor(switch, outputs(api)))
                tile({x = 2, y = py, w = width - 2, h = ph}, switch.name, status, nil, nil, draft, statusColour, preview)
            else
                local half = math.floor((width - 3) / 2)
                tile({x = 2, y = py, w = half, h = ph}, "Bundled", "ON", nil, nil, 8, preview.active, preview)
                tile({x = half + 3, y = py, w = width - half - 3, h = ph}, "Digital", "OFF", nil, nil, preview.unbound, preview.inactive, preview)
            end
        end
        if switch then
            local third = math.floor(width / 3)
            button(height, third >= 5 and "Apply" or "Save", "applyColour", nil, 1, third, true, previewAccent)
            button(height, third >= 9 and "IO default" or "Auto", "autoColour", nil, third + 1, 2 * third,
                true, view.colourAuto and previewAccent or theme.border)
            button(height, width - 2 * third >= 6 and "Cancel" or "Back", "cancel", nil, 2 * third + 1, width)
        else
            local half = math.floor(width / 2)
            button(height, "Apply", "applyColour", nil, 1, half, true, previewAccent)
            button(height, "Cancel", "cancel", nil, half + 1, width)
        end
    elseif screen == "keyboard" then
        local keyboard = view.keyboard
        local letters = keyboard.bank == "123" and "1234567890-_/.:!?+()@#&=,%*'\"" or "qwertyuiopasdfghjklzxcvbnm"
        if keyboard.bank == "ABC" then letters = letters:upper() end
        local narrow = width < 24
        local columns = narrow and math.max(4, math.floor(width / 2)) or 10
        local slots = columns * 3
        local pages = math.ceil(#letters / slots)
        keyboard.page = math.min(keyboard.page or 1, pages)
        local fieldRow, top = height >= 9 and 2 or 1, height >= 9 and 4 or 2
        if height >= 9 then ui.heading(keyboard.kind == "view" and "View name" or "Switch name", accent) end
        ui.style(1, fieldRow, width, 1, 32768, 1)
        ui.text(fieldRow, (keyboard.draft .. "_"):sub(-width))
        local available = height - 2 - top + 1
        local gap = width >= 32 and 1 or 0
        local rowGap = available >= 8 and 1 or 0
        for row = 0, 2 do
            local length = not narrow and keyboard.bank ~= "123" and ({10, 9, 7})[row + 1] or columns
            local start = not narrow and keyboard.bank ~= "123" and ({0, 10, 19})[row + 1] or row * columns
            for column = 0, length - 1 do
                local index = (keyboard.page - 1) * slots + start + column + 1
                local letter = letters:sub(index, index)
                if letter ~= "" then
                    local cellWidth = math.floor((width + gap) / columns)
                    local offset = math.floor((width - (cellWidth * length - gap)) / 2)
                    local x1 = 1 + offset + column * cellWidth
                    local y1 = top + math.floor(row * (available + rowGap) / 3)
                    local y2 = top - 1 + math.floor((row + 1) * (available + rowGap) / 3) - rowGap
                    local rect = {x = x1, y = y1, w = cellWidth - gap, h = y2 - y1 + 1}
                    tile(rect, letter, nil, "key", letter, theme.border)
                end
            end
        end
        local controls = pages > 1 and 4 or 3
        local labels = {keyboard.bank == "abc" and "ABC" or keyboard.bank == "ABC" and "123" or "abc", "Space", "Del", keyboard.page .. "/" .. pages}
        local actions = {"bank", "space", "backspace", "keyPage"}
        for index = 1, controls do
            local x1, x2 = 1 + math.floor((index - 1) * width / controls), math.floor(index * width / controls)
            button(height - 1, x2 - x1 + 1 < 5 and (index == 2 and "Sp" or labels[index]) or labels[index], actions[index], nil, x1, x2)
        end
        local third = math.floor(width / 3)
        button(height, "Save", "saveName", nil, 1, third, keyboard.draft:match("%S") ~= nil, accent)
        button(height, third >= 5 and "Clear" or "Clr", "clearName", nil, third + 1, 2 * third)
        button(height, width - 2 * third >= 6 and "Cancel" or "Back", "cancelName", nil, 2 * third + 1, width)
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

function app.render(width, height, state, api, context)
    if not ready then return {"Switchboard blocked", "Check OS log"} end
    return (build(width, height, state, api, context))
end

local function createBoard(state, api, view, columns, rows, clientId, side)
    if #state.boards >= MAX_VIEWS then notify(view, "Maximum 64 views"); return end
    local created
    local ok = commit(state, api, view, function()
        created = {id = state.nextBoardId, name = clientId and (clientId .. " " .. side):sub(1, 32) or "View " .. state.nextBoardId,
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
                local ok, err = api.setOutput(outputName(switch), not wire.value)
                if not ok then notify(view, "Could not save: " .. tostring(err)) end
            end
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
    elseif action == "bank" then
        local keyboard = view.keyboard
        keyboard.bank, keyboard.page = keyboard.bank == "abc" and "ABC" or keyboard.bank == "ABC" and "123" or "abc", 1
    elseif action == "keyPage" then view.keyboard.page = view.keyboard.page == 1 and 2 or 1
    elseif action == "key" or action == "space" then
        local keyboard = view.keyboard
        if #keyboard.draft < (keyboard.kind == "view" and 32 or 24) then keyboard.draft = keyboard.draft .. (action == "space" and " " or value) end
    elseif action == "backspace" then view.keyboard.draft = view.keyboard.draft:sub(1, -2)
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
        view.colourField, view.colourDraft, view.screen = "accent", api.getAppColour(context.appName or appName), "palette"
    elseif action == "palette" then view.colourField, view.colourDraft, view.screen = value, state.settings[value], "palette"
    elseif action == "switchColour" then
        view.colourField, view.colourDraft, view.colourBefore = "switch", buttonColour(switch, state.settings), switch.displayColour
        view.colourAuto, view.screen = switch.displayColour == nil, "palette"
    elseif action == "colour" then view.colourDraft, view.colourAuto = value, false
    elseif action == "autoColour" then view.colourAuto = true
    elseif action == "applyColour" then
        local ok, err
        if view.colourField == "switch" then
            if switch.displayColour ~= view.colourBefore then
                notify(view, "Button colour changed in another window; reopen Colour", "button")
            else
                ok = commit(state, api, view, function()
                    if view.colourAuto then switch.displayColour = nil else switch.displayColour = view.colourDraft end
                end)
            end
        elseif view.colourField == "accent" then
            ok, err = api.setAppColour(context.appName or appName, view.colourDraft)
            if not ok then notify(view, "Could not save: " .. tostring(err)) end
        else ok = commit(state, api, view, function() state.settings[view.colourField] = view.colourDraft end) end
        if ok then view.screen = view.colourField == "switch" and "button" or "settings" end
    elseif action == "cancel" then view.screen = view.colourField == "switch" and "button" or "settings"
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
