-- Built-in settings. Destructive confirmations are kept in memory per window.
local System = dofile("lib_system.lua")
local Settings = {}

function Settings.new(actions)
    local app = {title = "Settings", minWidth = 12, minHeight = 6, preferredWidth = 34, preferredHeight = 13}
    local pending = {}

    function app.init(state)
        state.overview = type(state.overview) == "table" and state.overview or {}
        System.init(state.overview)
    end

    local function overviewContext(context)
        local view = context.view
        view.overview = view.overview or {}
        return {windowId = context.windowId, monitorId = context.monitorId, view = view.overview, hits = context.hits}
    end

    local function build(w, h, state, api, context)
        local view = context.view
        if view.section == "overview" then
            local lines = System.render(w, h, state.overview, api, overviewContext(context))
            return lines, lines.hits
        end
        local ui = api.ui.form(w, h, view, 2048)
        local section = view.section or "home"
        if section == "nameClient" or section == "nameKeyboard" then
            if type(view.nameId) ~= "string" then
                view.section, view.keyboard = "names", nil
            elseif section == "nameKeyboard" and not view.keyboard then
                view.section = "nameClient"
            end
            section = view.section
        end
        local draft = pending[context.windowId]
        if draft then
            local title = "Are you sure?"
            if draft.mode == "reset" and draft.final then title = w >= 20 and "Are you really sure?" or "Really sure?"
            elseif draft.mode == "delete" then title = "Delete app?"
            elseif draft.mode == "restore" then title = "Restore data?"
            elseif draft.mode == "backup" then title = "Replace backup?" end
            ui.heading(draft.error and "Action failed" or title, 16384)
            ui.put(1, 2, draft.label, w, true)
            local message = draft.error or draft.detail
            if message then ui.put(1, 3, message, w); ui.put(1, 4, message:sub(w + 1), w)
            elseif draft.mode == "delete" then ui.put(1, 3, "Settings kept", w, true)
            elseif draft.target == "@all" then ui.put(1, 3, "All app data", w, true); ui.put(1, 4, "OS + routes", w, true)
            elseif draft.target == "@settings" then ui.put(1, 3, "OS data + layouts", w, true)
            else ui.put(1, 3, "Data, routes", w, true); ui.put(1, 4, "and layouts", w, true) end
            if draft.mode == "reset" and draft.target == "@all" and not draft.final then
                ui.action(h - 1, "Continue", "confirmAgain", nil, nil, nil, true, 16384)
                ui.action(h, "Cancel", "cancel")
            else
                local button = draft.mode == "reset" and (draft.final and "Erase all" or "Delete data")
                    or draft.mode == "delete" and "Uninstall" or draft.mode == "backup" and "Replace" or "Restore"
                ui.action(h - 1, "Cancel", "cancel")
                ui.action(h, button, "commit", nil, nil, nil, true, 16384)
            end
        elseif section == "home" then
            ui.menu(app.title, {{"Appearance", "appearance"}, {"System overview", "overview"},
                {"Client names", "names"}, {"Screensavers", "screensavers"}, {"App data", "data"}}, "settings", {{"Close", "close"}})
        elseif section == "appearance" then
            local settings = api.getOSSettings()
            local function label(text, color) return w >= 24 and text .. " " .. api.ui.colourName(color) or text end
            ui.menu("Appearance", {{label("Background", settings.backgroundColour), "background", nil, true, settings.backgroundColour},
                {label(w >= 13 and "Window border" or "Borders", settings.windowBorderColour), "windowBorder", nil, true, settings.windowBorderColour},
                {"Taskbar", "taskbar"}}, "appearance")
        elseif section == "taskbar" then
            local settings = api.getOSSettings()
            local position = settings.taskbarPosition == "top" and "Top" or "Bottom"
            ui.menu("Taskbar", {{"Color " .. api.ui.colourName(settings.taskbarColour), "taskbarColour", nil, true, settings.taskbarColour},
                {"Position " .. position, "taskbarPosition"}}, "taskbar", {{"Back", "appearance"}})
        elseif section == "taskbarPosition" then
            local position = api.getOSSettings().taskbarPosition
            ui.menu("Taskbar position", {{position == "top" and "* Top" or "Top", "setTaskbarPosition", "top"},
                {position == "bottom" and "* Bottom" or "Bottom", "setTaskbarPosition", "bottom"}},
                "taskbarPosition", {{"Back", "taskbar"}})
        elseif section == "screensavers" then
            local names, installed = api.getScreensavers()
            local rows = {}
            for index, name in ipairs(names) do rows[#rows + 1] = index .. ". " .. name end
            if #rows == 0 then rows[1] = installed and "Update or enable Screensaver" or "Install Screensaver to see designs" end
            ui.info("Screensavers", rows, "screensavers", "home")
        elseif section == "names" then
            local rows = {}
            for _, item in ipairs(api.getClientNameTargets()) do
                rows[#rows + 1] = {(item.online and "+ " or "- ") .. item.displayName, "nameClient", item.id}
            end
            if #rows == 0 then rows[1] = {"No known clients", nil, nil, false} end
            ui.menu("Client names", rows, "names")
        elseif section == "nameClient" then
            local id = view.nameId
            ui.info("Client name", {api.clientName(id), "ID " .. id}, "nameClient", "names")
            ui.footer({{"Back", "names"}, {"Rename", "editName"}, {"Reset", "clearName", nil, api.clientName(id) ~= id}})
        elseif section == "nameKeyboard" then ui.keyboard(view.keyboard)
        elseif section == "data" then
            ui.menu(view.status or "App data", {{"Backup & restore", "backupMenu"}, {"Reset data", "resetData"},
                {"Delete apps", "deleteApps"}}, "data")
        elseif section == "backupMenu" then
            ui.menu(view.status or "Backup & restore", {{"Create backup", "backupList"}, {"Restore backup", "restoreList"}},
                "backupMenu", {{"Back", "data"}})
        elseif section == "resetData" or section == "deleteApps" or section == "backupList" or section == "restoreList" then
            local mode = ({resetData = "reset", deleteApps = "delete", backupList = "backup", restoreList = "restore"})[section]
            local targets = mode == "delete" and actions.installed() or mode == "restore" and actions.backups() or actions.targets()
            local rows = {}
            for _, item in ipairs(targets) do rows[#rows + 1] = {item.label, "selectScope", {id = item.id, label = item.label, mode = mode}} end
            if #rows == 0 then rows[1] = {mode == "delete" and "No installed apps" or "No backups yet", nil, nil, false} end
            local title = ({reset = "Reset data", delete = "Delete apps", backup = "Create backup", restore = "Restore backup"})[mode]
            local back = (mode == "backup" or mode == "restore") and "backupMenu" or "data"
            ui.menu(view.status or title, rows, section, {{"Back", back}})
        else ui.info(app.title, {view.status or "Select an option"}, "status", view.back or "home") end
        return ui.finish()
    end

    function app.render(w, h, state, api, context) return (build(w, h, state, api, context)) end

    function app.handleTouch(x, y, w, h, state, api, context)
        local id, view = context.windowId, context.view
        if view.section == "overview" then
            local ctx = overviewContext(context)
            local result = System.handleTouch(x, y, w, h, state.overview, api, ctx)
            if ctx.view.exit then ctx.view.exit, view.section = nil, "home" end
            return result
        end
        local hits = context.hits
        if not hits then local _; _, hits = build(w, h, state, api, context) end
        local action, value = api.ui.actionAt(hits, x, y)
        if not action then return false end
        if action == "page" then view.pages[value.key] = value.page
        elseif action == "close" then return api.closeWindow(id)
        elseif action == "background" or action == "windowBorder" then return api.pickColour(id, action)
        elseif action == "taskbarColour" then return api.pickColour(id, "taskbar")
        elseif action == "setTaskbarPosition" then
            local ok, err = api.setTaskbarPosition(value)
            view.section, view.status, view.back = ok and "taskbar" or "status", err, "taskbar"
        elseif action == "nameClient" then
            if value then view.nameId = value end
            view.section, view.keyboard, view.status = "nameClient", nil, nil
        elseif action == "editName" then
            view.keyboard = {draft = api.clientName(view.nameId) ~= view.nameId and api.clientName(view.nameId) or "",
                bank = 0, page = 1, back = "nameClient"}
            view.section = "nameKeyboard"
        elseif view.section == "nameKeyboard" and api.ui.editText(view.keyboard, action, value, 32) then return true
        elseif action == "saveText" or action == "clearName" then
            local ok, err = api.setClientName(view.nameId, action == "clearName" and "" or view.keyboard.draft)
            view.section = ok and "nameClient" or "status"
            view.status, view.back = err, "nameClient"
            view.keyboard = nil
        elseif action == "selectScope" then
            local mode = value.mode
            local info = (mode == "restore" or mode == "backup") and actions.backupInfo(value.id) or nil
            if mode == "backup" and not info then
                local ok, err = actions.backup(value.id)
                view.status = ok and "Backup saved" or tostring(err)
            else pending[id] = {target = value.id, label = value.label, mode = mode, detail = info} end
        elseif action == "confirmAgain" then pending[id].final = true
        elseif action == "cancel" then pending[id] = nil
        elseif action == "commit" then
            local draft = pending[id]
            local ok, err = actions[draft.mode](draft.target)
            if ok then
                pending[id] = nil
                view.status = err or ({reset = "Data reset", delete = "App deleted", restore = "Data restored", backup = "Backup saved"})[draft.mode]
            else draft.error = tostring(err) end
        else view.section, view.status = action, nil end
        api.invalidateAppViews("@settings")
        return true
    end

    function app.onClose(state, api, context) pending[context.windowId] = nil end
    return app
end

return Settings
