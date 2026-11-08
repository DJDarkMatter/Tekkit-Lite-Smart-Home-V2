-- Optional shared-history viewer. Capture belongs to the OS event loop.
local app = {title = "IO Scope", minWidth = 12, minHeight = 6, preferredWidth = 56, preferredHeight = 18}
local name = "io_scope"
local ranges = {10, 30, 60, 120}
local status = {["1"] = "ON", ["0"] = "OFF", p = "Pending", ["?"] = "Unknown"}
local ink = {["1"] = 8192, ["0"] = 128, p = 2, ["?"] = 32768, ["|"] = 32}
local sideNames = {"top", "bottom", "left", "right", "front", "back"}
local function find(list, id)
    for i, item in ipairs(list) do if item.id == id then return item, i end end
end
local function same(a, b)
    return a.clientId == b.clientId and a.side == b.side and a.color == b.color and a.direction == b.direction
end
local function lane(address, direction)
    return {clientId = address.clientId, side = address.side, color = address.color, direction = direction or address.direction}
end
local function colorLabel(api, address) return address.color and api.ui.colourName(address.color) or "Digital" end
local function sideLanes(clientId, side, direction)
    local result = {{clientId = clientId, side = side, direction = direction}}
    for i = 0, 15 do result[#result + 1] = {clientId = clientId, side = side, direction = direction, color = 2 ^ i} end
    return result
end
local function lanes(state, api, view)
    if view.mode == "used" then return api.getUsedIO(), "Used by apps" end
    if view.mode == "side" then
        return sideLanes(view.clientId, view.side, view.direction), api.clientName(view.clientId) .. " / " .. view.side
    end
    local selected = find(state.views, view.viewId)
    return selected and selected.lanes or {}, selected and selected.name or "View removed"
end
local function notice(view, message, back)
    view.screen, view.message, view.back = "notice", message, back
    view.pages = {}
end
local function setView(view, mode, id)
    view.screen, view.mode, view.viewId, view.finish, view.pages = "trace", mode, id, nil, {}
end
local function keyboard(view, purpose, title, back)
    view.screen = "keyboard"
    view.keyboard = {draft = title or "", bank = 0, page = 1, purpose = purpose, back = back}
end
local function saveList(state, api, view, nextViews, nextId)
    local old, previousId = state.views, state.nextId
    state.views, state.nextId = nextViews, nextId or state.nextId
    local ok, err = api.save()
    if not ok then
        state.views, state.nextId = old, previousId
        notice(view, tostring(err), "home")
    end
    return ok
end
local function changeView(state, api, view, selected, change)
    local items = {}
    for i, item in ipairs(state.views) do
        if item == selected then
            local nextView = {id = item.id, name = item.name, lanes = {}}
            for _, address in ipairs(item.lanes) do nextView.lanes[#nextView.lanes + 1] = lane(address) end
            if change(nextView) ~= false then items[#items + 1] = nextView end
        else items[#items + 1] = item end
    end
    return saveList(state, api, view, items)
end
function app.init(state, api, context)
    assert(api.getIOTrace and api.getUsedIO, "IO Scope requires bundled-v39 OS")
    name = context.appName
    if not state.views then state.views, state.nextId = {}, 1 end
end
local function build(w, h, state, api, view)
    local ui = api.ui.form(w, h, view, api.getAppColour(name))
    local screen = view.screen or "home"
    local selected = find(state.views, view.viewId)
    if screen == "home" then
        local rows = {{"Used by apps", "used"}, {"Client side", "clients"}, {"+ New view", "new", nil, #state.views < 32}}
        for _, item in ipairs(state.views) do rows[#rows + 1] = {item.name, "open", item.id} end
        ui.menu("IO Scope", rows, "home", {{"Close", "close"}})
    elseif screen == "clients" then
        local rows = {}
        for _, client in ipairs(api.getIOClients()) do
            rows[#rows + 1] = {(client.online and "+ " or "- ") .. client.displayName, "client", client.id}
        end
        if #rows == 0 then rows[1] = {"No IO clients", nil, nil, false} end
        ui.menu("IO clients", rows, "clients")
    elseif screen == "sides" then
        local rows, sides = {}, sideNames
        for _, client in ipairs(api.getIOClients()) do if client.id == view.clientId then sides = client.sides; break end end
        for _, side in ipairs(sides) do rows[#rows + 1] = {side, "side", side} end
        ui.menu(api.clientName(view.clientId), rows, "sides", {{"Back", "clients"}})
    elseif screen == "direction" then
        ui.menu(view.side .. " wires", {{"Outputs", "directionPick", "output"}, {"Inputs", "directionPick", "input"}},
            "direction", {{"Back", "sides"}})
    elseif screen == "trace" then
        local session = api.getSystem().session
        if view.historySession ~= session then view.historySession, view.finish = session, nil end
        local entries, title = lanes(state, api, view)
        local seconds = ranges[view.range or 2] or 30
        local finish = view.finish or os.clock()
        local keys = math.max(5, math.min(23, math.floor(w * .38)))
        local span = w - keys
        ui.heading(title, 2048)
        local edge = view.finish and ("-" .. math.floor(math.max(0, os.clock() - finish)) .. "s") or "Now"
        local from = seconds + (view.finish and math.floor(math.max(0, os.clock() - finish)) or 0)
        ui.put(keys + 1, 2, "-" .. from .. "s", math.max(0, span - #edge - 1))
        ui.put(w - #edge + 1, 2, edge, #edge)
        local slots = #entries <= h - 3 and h - 3 or h - 4
        local first = ui.page("lanes", #entries, slots, h - 1)
        for i = 1, slots do
            local address = entries[first + i]
            if address then
                local label = colorLabel(api, address)
                if keys >= 16 and view.mode ~= "side" then label = label .. " " .. api.clientName(address.clientId) end
                local trace, current = api.getIOTrace(address, finish, seconds, span)
                local badge = address.direction == "input" and "I " or "O "
                local keyColor = address.color or 256
                ui.action(i + 2, badge .. label, "lane", lane(address), 1, keys, true, keyColor)
                local col = 1
                while col <= #trace do
                    local char = trace:sub(col, col)
                    local last = col
                    while last < #trace and trace:sub(last + 1, last + 1) == char do last = last + 1 end
                    local glyph = char == "?" and "." or char == "0" and "_" or char == "|" and "|" or " "
                    ui.put(keys + col, i + 2, glyph:rep(last - col + 1), last - col + 1)
                    ui.style(keys + col, i + 2, last - col + 1, 1, char == "?" and 128 or 1, ink[char])
                    col = last + 1
                end
                if not view.finish and current == "p" then ui.put(w, i + 2, "?", 1) end
            end
        end
        if #entries == 0 then ui.put(1, 3, "No lines yet", w, true) end
        ui.footer({{w < 16 and "..." or "Menu", "menu"}, {"<", "earlier"}, {">", "later", nil, view.finish ~= nil},
            {view.finish and (w < 16 and ">>" or "Live") or (w < 16 and "||" or "Hold"), "live"}})
    elseif screen == "menu" then
        local rows = {{"Range " .. (ranges[view.range or 2] or 30) .. "s", "range"}, {"All views", "home"}}
        if selected and view.mode == "saved" then
            rows[#rows + 1] = {"Add output", "add", "output", #selected.lanes < 64}
            rows[#rows + 1] = {"Add input", "add", "input", #selected.lanes < 64}
            rows[#rows + 1] = {"Rename view", "rename"}
            rows[#rows + 1] = {"Delete view", "askDelete"}
        else rows[#rows + 1] = {"Save as view", "saveAs", nil, #state.views < 32} end
        ui.menu("Scope menu", rows, "menu", {{"Back", "trace"}})
    elseif screen == "detail" and view.address then
        local address = view.address
        local _, current = api.getIOTrace(address, os.clock(), 1, 1)
        local lines = {api.clientName(address.clientId), "ID " .. address.clientId, address.side .. " / " .. colorLabel(api, address),
            address.direction .. " / " .. (status[current] or "Unknown")}
        local applications = {}
        for _, item in ipairs(api.getUsedIO()) do if same(item, address) then applications = item.apps; break end end
        lines[#lines + 1] = #applications > 0 and ("Used by " .. table.concat(applications, ", ")) or "No app binding"
        ui.info("Wire details", lines, "detail", "trace")
        if selected and view.mode == "saved" then ui.footer({{"Back", "trace"}, {"Remove", "removeLane"}}) end
    elseif screen == "keyboard" and view.keyboard then ui.keyboard(view.keyboard)
    elseif screen == "askDelete" then
        ui.info("Delete view?", {selected and selected.name or "View removed"}, "delete", "menu")
        ui.footer({{"Cancel", "menu"}, {"Delete", "delete", nil, selected ~= nil, 16384}})
    else ui.info("IO Scope", {view.message or "Select a view"}, "notice", view.back or "home") end
    return ui
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context.view).lines end
function app.handleIOSelection(key, address, state, api, context)
    local view = context.view
    local selected = find(state.views, view.viewId)
    if not selected or #selected.lanes >= 64 or (key ~= "input" and key ~= "output") then return false, "View changed" end
    local entry = lane(address, key)
    for _, old in ipairs(selected.lanes) do if same(old, entry) then return false, "Line already in view" end end
    local ok = changeView(state, api, view, selected, function(nextView) nextView.lanes[#nextView.lanes + 1] = entry end)
    if ok then view.screen = "trace"; api.invalidateAppViews(name) end
    return ok
end
function app.handleTouch(x, y, w, h, state, api, context)
    local view = context.view
    local action, value = api.ui.actionAt(build(w, h, state, api, view).hits, x, y)
    if not action then return false end
    local selected = find(state.views, view.viewId)
    local seconds = ranges[view.range or 2] or 30
    if action == "page" then view.pages[value.key] = value.page
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "used" or action == "open" then setView(view, action == "used" and "used" or "saved", value)
    elseif action == "client" then view.clientId, view.screen = value, "sides"
    elseif action == "side" then view.side, view.screen = value, "direction"
    elseif action == "directionPick" then view.direction = value; setView(view, "side")
    elseif action == "lane" then view.address, view.screen, view.pages.detail = value, "detail", 1
    elseif action == "live" then
        if view.finish then view.finish = nil else view.finish = os.clock() end
    elseif action == "earlier" or action == "later" then
        local now = os.clock()
        view.finish = math.max(0, now - 300 + seconds, math.min(now, (view.finish or now) + (action == "earlier" and -1 or 1) * seconds / 2))
    elseif action == "range" then view.range = (view.range or 2) % #ranges + 1
    elseif action == "add" then
        local ok, err = api.pickIO(context.windowId, value, value)
        if not ok then notice(view, err, "menu") end
    elseif action == "removeLane" and selected then
        if changeView(state, api, view, selected, function(nextView)
            for i, address in ipairs(nextView.lanes) do if same(address, view.address) then table.remove(nextView.lanes, i); break end end
        end) then view.screen = "trace" end
    elseif action == "delete" and selected then
        if changeView(state, api, view, selected, function() return false end) then view.screen = "home" end
    elseif action == "new" or action == "saveAs" or action == "rename" then
        keyboard(view, action, action == "rename" and selected.name or action == "new" and "View " .. state.nextId or "IO view",
            action == "new" and "home" or "menu")
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value, 32) then
        return true
    elseif action == "saveText" and view.keyboard then
        local draft, purpose = view.keyboard.draft:match("^%s*(.-)%s*$"), view.keyboard.purpose
        if draft == "" then return true end
        if purpose == "rename" and selected then
            if changeView(state, api, view, selected, function(item) item.name = draft end) then view.screen = "trace" end
        elseif #state.views < 32 then
            local source = purpose == "saveAs" and lanes(state, api, view) or {}
            if #source > 64 then notice(view, "A saved view fits up to 64 lines", "trace"); return true end
            local items, saved = {}, {id = state.nextId, name = draft, lanes = {}}
            for i, item in ipairs(state.views) do items[i] = item end
            for _, address in ipairs(source) do saved.lanes[#saved.lanes + 1] = lane(address) end
            items[#items + 1] = saved
            if saveList(state, api, view, items, state.nextId + 1) then setView(view, "saved", saved.id) end
        end
    else view.screen = action end
    api.invalidateAppViews(name)
    return true
end
return app
