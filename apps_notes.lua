-- Local notes and checklists. Export is a plain GitHub-flavored Markdown file.
local app = {title = "Notes", minWidth = 12, minHeight = 6, preferredWidth = 36, preferredHeight = 14}
local appName = "notes"
local function find(list, id)
    for i, item in ipairs(list or {}) do if item.id == id then return item, i end end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function notice(view, message, back)
    view.screen, view.message, view.back, view.pages = "message", tostring(message), back, {}
end
local function commit(state, api, view, change)
    local previous = copy(state)
    change()
    local ok, err = api.save()
    if not ok then
        state.notes, state.nextNote, state.nextLine = previous.notes, previous.nextNote, previous.nextLine
        notice(view, err, "home")
    end
    api.invalidateAppViews(appName)
    return ok
end
local function keyboard(view, purpose, text, back)
    view.screen = "keyboard"
    view.keyboard = {draft = text or "", bank = 0, page = 1, purpose = purpose, back = back,
        symbols = "1234567890-_/.:,?!'()&+=#"}
end
function app.init(state, api, context)
    assert(api.ui.actionAt, "Notes requires bundled-v39 OS")
    appName = context.appName
    if not state.notes then state.notes, state.nextNote, state.nextLine = {}, 1, 1 end
end
local function markdown(text)
    return (text:gsub("([\\`*_{}%[%]<>()#+.!|])", "\\%1"))
end
local function export(note, api)
    local path = "notes_export_" .. note.id .. ".md"
    local lines = {"# " .. markdown(note.name), ""}
    for _, line in ipairs(note.lines) do
        local text = markdown(line.text)
        if line.check then lines[#lines + 1] = (line.checked and "- [x] " or "- [ ] ") .. text
        else
            lines[#lines + 1] = ""
            lines[#lines + 1] = text
            lines[#lines + 1] = ""
        end
    end
    local ok, err = api.protectedCall(function()
        local file = assert(fs.open(path, "w"), "Cannot write " .. path)
        file.write(table.concat(lines, "\n") .. "\n")
        file.close()
    end)
    return ok, ok and path or err
end
local function build(w, h, state, api, view)
    local accent = api.getAppColour(appName)
    local ui = api.ui.form(w, h, view, accent)
    local screen = view.screen or "home"
    local note = find(state.notes, view.noteId)
    local line = find(note and note.lines, view.lineId)
    if not note and screen ~= "keyboard" and screen ~= "message" then screen = "home" end
    if not line and (screen == "line" or screen == "deleteLine") then screen = "note" end
    if screen == "home" then
        local rows = {{"+ New note", "newNote", nil, #state.notes < 48, accent}}
        for _, item in ipairs(state.notes) do rows[#rows + 1] = {item.name, "open", item.id} end
        ui.menu("Notes", rows, "notes", {{"Close", "close"}})
    elseif screen == "note" then
        local rows = {}
        for _, item in ipairs(note.lines) do
            local label = item.check and (item.checked and "[x] " or "[ ] ") .. item.text or item.text
            rows[#rows + 1] = {label, item.check and not view.edit and "toggle" or "openLine", item.id,
                true, item.checked and 8192 or nil}
        end
        if #rows == 0 then rows[1] = {"No lines yet", nil, nil, false} end
        ui.menu(note.name, rows, "lines", {{"Back", "home"}, {"+ Add", "add", nil, #note.lines < 96, accent}, {"Menu", "menu"}})
    elseif screen == "menu" then
        ui.menu("Note menu", {{view.edit and "Done editing" or "Edit lines", "editMode"}, {"Rename note", "rename"},
            {"Export Markdown", "export"}, {"Delete note", "deleteNote"}}, "menu", {{"Back", "note"}})
    elseif screen == "add" then
        ui.menu("Add to note", {{"Text line", "newLine", "text"}, {"Checkbox", "newLine", "check"}}, "add", {{"Back", "note"}}, true)
    elseif screen == "line" then
        ui.info(line.check and (line.checked and "Checked" or "Checkbox") or "Text line",
            {line.text}, "lineText", "note")
        ui.footer({{"Back", "note"}, {"Edit", "editLine"}, {"Delete", "deleteLine"}})
    elseif screen == "keyboard" then ui.keyboard(view.keyboard)
    elseif screen == "deleteNote" or screen == "deleteLine" then
        local back = screen == "deleteNote" and "menu" or "line"
        ui.info("Delete?", {screen == "deleteNote" and note.name or line.text}, "delete", back)
        ui.footer({{"Cancel", back}, {"Delete", "confirmDelete", nil, true, 16384}})
    else ui.info("Notes", {view.message or "Note changed"}, "message", view.back or "home") end
    ui.finish()
    return ui
end
function app.render(w, h, state, api, context) return build(w, h, state, api, context.view).lines end
function app.handleTouch(x, y, w, h, state, api, context)
    local view = context.view
    local action, value = api.ui.actionAt(context.hits or build(w, h, state, api, view).hits, x, y)
    if not action then return false end
    local note, index = find(state.notes, view.noteId)
    local line, lineIndex = find(note and note.lines, view.lineId)
    if action == "page" then view.pages[value.key] = value.page
    elseif action == "close" then return api.closeWindow(context.windowId)
    elseif action == "open" then view.noteId, view.screen, view.pages, view.edit = value, "note", {}, nil
    elseif action == "openLine" then view.lineId, view.screen, view.pages.lineText = value, "line", 1
    elseif action == "toggle" then
        local selected = find(note.lines, value)
        commit(state, api, view, function() selected.checked = not selected.checked end)
    elseif action == "editMode" then view.edit, view.screen = not view.edit, "note"
    elseif action == "newNote" then keyboard(view, "newNote", "Note " .. state.nextNote, "home")
    elseif action == "rename" then keyboard(view, "rename", note.name, "menu")
    elseif action == "newLine" then keyboard(view, value, "", "add")
    elseif action == "editLine" then keyboard(view, "editLine", line.text, "line")
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value,
        (view.keyboard.purpose == "newNote" or view.keyboard.purpose == "rename") and 32 or 160) then return true
    elseif action == "saveText" then
        local k = view.keyboard
        local value = k.draft:match("^%s*(.-)%s*$")
        if value == "" then return true end
        if k.purpose == "newNote" and #state.notes < 48 then
            local id = state.nextNote
            if commit(state, api, view, function()
                state.notes[#state.notes + 1] = {id = id, name = value, lines = {}}
                state.nextNote = id + 1
            end) then view.noteId, view.screen = id, "note" end
        elseif note then
            if k.purpose == "rename" then
                if commit(state, api, view, function() note.name = value end) then view.screen = "note" end
            elseif k.purpose == "editLine" and line then
                if commit(state, api, view, function() line.text = value end) then view.screen = "line" end
            elseif (k.purpose == "check" or k.purpose == "text") and #note.lines < 96 then
                if commit(state, api, view, function()
                    note.lines[#note.lines + 1] = {id = state.nextLine, text = value, check = k.purpose == "check"}
                    state.nextLine = state.nextLine + 1
                end) then view.screen = "note" end
            end
        else view.screen = "home" end
    elseif action == "confirmDelete" then
        local whole = view.screen == "deleteNote"
        if commit(state, api, view, function()
            if whole then table.remove(state.notes, index) else table.remove(note.lines, lineIndex) end
        end) then view.screen = whole and "home" or "note" end
    elseif action == "export" then
        local ok, file = export(note, api)
        notice(view, ok and "Saved /" .. file or file, "menu")
    else view.screen = action end
    api.invalidateAppViews(appName)
    return true
end
return app
