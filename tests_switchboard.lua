-- Real optional app, OS, monitor touch transport, independent disks and IO queue.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local function read(path)
        local file = assert(io.open(path, "r")); local source = file:read("*a"); file:close(); return source
    end
    local source = read("apps_switchboard.lua")
    local function setup(width, height, withCoffee)
        local bus = newBus()
        local apps = {["apps_switchboard.lua"] = source}
        if withCoffee then apps["apps_coffee.lua"] = read("apps_coffee.lua") end
        local central = bus.computer(10, "server", {apps = apps}):start()
        local ioClient = bus.computer(11, "io", {modemSide = "right"}):start()
        local other = bus.computer(12, "io", {modemSide = "top"}):start()
        local top, left = monitor(width or 64, height or 26), monitor(48, 23)
        local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
        local t = {bus = bus, central = central, io = ioClient, other = other, top = top, left = left, display = display}
        function t.reload()
            t.api, t.app, t.state = t.central.server.api, t.central.server.apps.switchboard, t.central.server.state.appStates.switchboard
        end
        t.reload()
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.open(side, w, h)
            local id = assert(t.api.openApp("switchboard", "monitor_13:" .. (side or "top"), 1, 1, w, h))
            t.paint(); return id
        end
        function t.window(id) return t.central.server.state.windows[id] end
        function t.view(id) return t.central.server.views[id] end
        function t.context(id)
            return {windowId = id, appName = "switchboard", monitorId = t.window(id).monitorId, view = t.view(id)}
        end
        function t.content(id)
            local win = t.window(id)
            return t.app.render(win.width - 2, win.height - 2, t.state, t.api, t.context(id))
        end
        function t.hits(id)
            local dialog = t.central.server.dialogs[id]
            return dialog and dialog.hits or t.content(id).hits
        end
        function t.touch(id, hit)
            local win = t.window(id)
            bus.queue(display, {"monitor_touch", win.monitorId:match(":([^:]+)$"),
                win.x + math.floor((hit.x1 + hit.x2) / 2), win.y + math.floor(((hit.y1 or hit.y) + (hit.y2 or hit.y)) / 2)})
            bus.pump()
        end
        function t.click(id, action, value)
            -- Locate a real control, including menu pagination. Never bypass its
            -- enabled state or the monitor bridge's coordinate transformation.
            for _ = 1, 40 do
                t.paint()
                local nextPage, previousPage, nextKeyPage
                for _, hit in ipairs(t.hits(id) or {}) do
                    if hit.enabled ~= false then
                        if hit.action == action and (value == nil or type(value) == "function" and value(hit.value) or hit.value == value) then
                            t.touch(id, hit); return
                        end
                        if hit.action == "page" and hit.value.delta == 1 then nextPage = hit end
                        if hit.action == "page" and hit.value.delta == -1 then previousPage = hit end
                        if action == "key" and hit.action == "keyPage" then nextKeyPage = hit end
                    end
                end
                if not nextPage and not previousPage and not nextKeyPage then break end
                t.touch(id, nextPage or previousPage or nextKeyPage)
            end
            error("Missing switchboard action " .. action .. " on " .. tostring(t.view(id).screen))
        end
        function t.preset(id, client, side)
            t.click(id, "add"); t.click(id, "client", client or "io_11"); t.click(id, "side", side or "left"); t.click(id, "create")
            return t.state.boards[#t.state.boards]
        end
        function t.grid(id, columns, rows)
            local draft = t.view(id).gridDraft
            for _, item in ipairs({{key = "columns", count = columns}, {key = "rows", count = rows}}) do
                while draft[item.key] ~= item.count do
                    local delta = draft[item.key] < item.count and 1 or -1
                    t.click(id, "gridStep", function(value) return value.key == item.key and value.delta == delta end)
                end
            end
        end
        function t.empty(id, columns, rows)
            t.click(id, "add"); t.click(id, "empty"); t.grid(id, columns or 4, rows or 4); t.click(id, "saveGrid")
            return t.state.boards[#t.state.boards]
        end
        function t.route(id, board, index, client, side, color)
            t.view(id).screen, t.view(id).boardId, t.view(id).buttonId = "button", board.id, board.buttons[index].id
            t.click(id, "route")
            t.click(id, "select", client or "io_11"); t.click(id, "select", side or "left")
            -- The OS picker has its own prev/next actions.
            for _ = 1, 10 do
                t.paint()
                local chosen, nextHit
                for _, hit in ipairs(t.hits(id)) do
                    if hit.action == "select" and hit.value == (color or false) then chosen = hit end
                    if hit.action == "next" and hit.enabled ~= false then nextHit = hit end
                end
                if chosen then t.touch(id, chosen); break end
                assert(nextHit, "Wire not reachable"); t.touch(id, nextHit)
            end
            t.click(id, "use")
        end
        function t.reboot()
            t.central = bus.computer(10, "server", {disk = t.central.disk}):start()
            t.reload(); bus.advance(6); t.paint()
        end
        bus.advance(2)
        t.id = t.open()
        return t
    end
    local function logical(button) return "switchboard_switch_" .. button.id end
    local function mappings(t) return t.central.server.state.outputMap end

    function tests.switchboard_empty_home_and_side_preset_create_all_sixteen_off_in_one_revision()
        local t = setup()
        equal(#t.state.boards, 0)
        equal(t.central.server.running.switchboard, true)
        local hits = t.content(t.id).hits
        equal(#hits, 2, "Empty selection has one Add and one Settings action")
        local before = t.central.server.ioClients.io_11.revision
        local board = t.preset(t.id)
        equal(t.view(t.id).screen, "home")
        equal(#board.buttons, 16); equal(board.columns, 4); equal(board.rows, 4)
        equal(t.central.server.ioClients.io_11.revision, before + 1)
        for index, button in ipairs(board.buttons) do
            equal(button.route.color, 2 ^ (index - 1)); equal(button.route.clientId, "io_11"); equal(button.route.side, "left")
            equal(t.api.getOutput(logical(button)), false)
        end
        equal(t.io.bundled.left, 0)
        t.click(t.id, "open", board.id)
        local count = 0
        for _, hit in ipairs(t.content(t.id).hits) do if hit.action == "toggle" then count = count + 1 end end
        equal(count, 16, "Large windows display the entire 4x4 board")
    end

    function tests.switchboard_presets_exclude_modems_and_reject_conflicts_with_coffee_atomically()
        local t = setup(nil, nil, true)
        local coffee = t.central.server.apps.coffee
        assert(coffee.handleIOSelection("outputAddress", {clientId = "io_11", side = "left", color = 16384},
            t.central.server.state.appStates.coffee, t.api))
        t.click(t.id, "add"); t.click(t.id, "client", "io_11")
        for _, hit in ipairs(t.content(t.id).hits) do assert(hit.action ~= "side" or hit.value ~= "right") end
        t.click(t.id, "side", "left")
        local before, revision = serialize(mappings(t)), t.central.server.ioClients.io_11.revision
        t.click(t.id, "create")
        equal(#t.state.boards, 0); equal(serialize(mappings(t)), before)
        equal(t.central.server.ioClients.io_11.revision, revision)
        assert(t.view(t.id).message:find("Wire already mapped", 1, true))
        t.click(t.id, "messageBack"); t.click(t.id, "sides"); t.click(t.id, "side", "front"); t.click(t.id, "create")
        equal(#t.state.boards, 1)
    end

    function tests.switchboard_switches_share_across_monitors_close_normally_and_restore_on_restart()
        local t = setup()
        local board = t.preset(t.id)
        local id2 = t.open("left")
        t.click(t.id, "open", board.id); t.click(id2, "open", board.id)
        t.click(t.id, "toggle", board.buttons[1].id)
        t.bus.advance(1)
        equal(t.io.bundled.left, 1)
        assert(table.concat(t.content(id2), "\n"):find("ON", 1, true))
        assert(t.api.closeWindow(t.id)); equal(t.central.server.running.switchboard, true)
        assert(t.api.closeWindow(id2)); equal(t.central.server.running.switchboard, nil)
        equal(t.api.getOutput(logical(board.buttons[1])), true)
        t.reboot()
        equal(t.io.bundled.left, 1, "Closing the UI keeps physical switch intent")
        equal(t.central.server.running.switchboard, nil)
        t.id = t.open()
        equal(#t.state.boards, 1)
        t.click(t.id, "open", board.id)
        t.click(t.id, "toggle", board.buttons[1].id); t.bus.advance(1)
        equal(t.io.bundled.left, 0)
    end

    function tests.switchboard_custom_routes_across_clients_support_digital_and_keep_names()
        local t = setup()
        local board = t.empty(t.id, 3, 2)
        equal(#board.buttons, 6); equal(next(mappings(t)), nil)
        t.route(t.id, board, 1, "io_11", "left", 32768)
        t.route(t.id, board, 2, "io_12", "bottom", 2)
        t.route(t.id, board, 3, "io_12", "front", nil)
        equal(board.buttons[1].name, "Black"); equal(board.buttons[2].name, "Orange"); equal(board.buttons[3].name, "Digital")
        t.view(t.id).screen = "board"
        for i = 1, 3 do t.click(t.id, "toggle", board.buttons[i].id) end
        t.bus.advance(2)
        equal(t.io.bundled.left, 32768); equal(t.other.bundled.bottom, 2); equal(t.other.digital.front, true)
        equal(t.other.bundled.front, 0)
    end

    function tests.switchboard_rerouting_an_on_switch_clears_old_wire_and_starts_new_wire_off()
        local t = setup()
        local board = t.preset(t.id)
        t.click(t.id, "open", board.id); t.click(t.id, "toggle", board.buttons[1].id); t.bus.advance(1)
        equal(t.io.bundled.left, 1)
        t.route(t.id, board, 1, "io_11", "left", 1)
        equal(t.api.getOutput(logical(board.buttons[1])), true, "Re-selecting the current route preserves the switch")
        t.route(t.id, board, 1, "io_12", "bottom", 4)
        t.bus.advance(1)
        equal(t.io.bundled.left, 0); equal(t.other.bundled.bottom, 0)
        equal(t.api.getOutput(logical(board.buttons[1])), false)
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.switchboard.boards[1].buttons[1].route.clientId, "io_12")
        equal(saved.outputMap[logical(board.buttons[1])].color, 4)
        equal(saved.outputs[logical(board.buttons[1])], false)
    end

    function tests.switchboard_failed_create_toggle_reroute_and_delete_preserve_state_and_hardware()
        local t = setup()
        t.click(t.id, "add"); t.click(t.id, "client", "io_11"); t.click(t.id, "side", "left")
        t.central.disk.failWrite = true; t.click(t.id, "create")
        equal(#t.state.boards, 0); equal(next(mappings(t)), nil)
        t.central.disk.failWrite = false; t.click(t.id, "messageBack"); t.click(t.id, "create")
        local board = t.state.boards[1]
        t.click(t.id, "open", board.id)
        t.central.disk.failWrite = true; t.click(t.id, "toggle", board.buttons[1].id)
        equal(t.api.getOutput(logical(board.buttons[1])), false); equal(t.io.bundled.left, 0)
        t.central.disk.failWrite = false; t.click(t.id, "messageBack"); t.click(t.id, "toggle", board.buttons[1].id)
        t.bus.advance(1); equal(t.io.bundled.left, 1)
        local before = serialize(t.state)
        t.central.disk.failWrite = true
        t.route(t.id, board, 1, "io_12", "left", 2)
        equal(serialize(t.state), before); equal(mappings(t)[logical(board.buttons[1])].clientId, "io_11")
        assert(t.central.server.dialogs[t.id].error)
        t.central.disk.failWrite = false; t.click(t.id, "cancel")
        t.view(t.id).screen = "edit"; t.click(t.id, "askDelete")
        t.central.disk.failWrite = true; t.click(t.id, "confirm")
        equal(#t.state.boards, 1); equal(t.api.getOutput(logical(board.buttons[1])), true)
        t.bus.advance(1); equal(t.io.bundled.left, 1)
    end

    function tests.switchboard_small_windows_page_every_switch_and_selection_without_skipping()
        local t = setup(15, 10)
        local board = t.preset(t.id)
        t.click(t.id, "open", board.id)
        local visited, pages = {}, 0
        while true do
            pages = pages + 1
            for _, hit in ipairs(t.content(t.id).hits) do
                if hit.action == "toggle" then assert(not visited[hit.value]); visited[hit.value] = true end
            end
            local p = t.view(t.id).pages.switches
            if p.page == p.pages then break end
            t.click(t.id, "page", function(v) return v.delta == 1 end)
        end
        equal(pages, 4, "A 1x1-like monitor uses four switches per page")
        for _, switch in ipairs(board.buttons) do assert(visited[switch.id]) end
        for page = 3, 1, -1 do
            t.click(t.id, "page", function(v) return v.delta == -1 end)
            equal(t.view(t.id).pages.switches.page, page)
            t.bus.advance(6); equal(t.view(t.id).pages.switches.page, page)
        end
        t.click(t.id, "home")
        t.empty(t.id, 1, 1); t.empty(t.id, 2, 1); t.empty(t.id, 1, 2)
        local p = t.view(t.id).pages.home
        equal(p.page, p.pages, "The new view is visible on the last selection page")
        local seen = {}
        t.view(t.id).pages.home.page = 1
        repeat
            for _, hit in ipairs(t.content(t.id).hits) do if hit.action == "open" then seen[hit.value] = true end end
            p = t.view(t.id).pages.home
            if p.page == p.pages then break end
            t.click(t.id, "page", function(v) return v.delta == 1 end)
        until false
        for _, item in ipairs(t.state.boards) do assert(seen[item.id]) end
    end

    function tests.switchboard_grid_shrink_confirms_and_removes_routes_without_reusing_switch_ids()
        local t = setup()
        local board = t.preset(t.id)
        t.click(t.id, "open", board.id); t.click(t.id, "toggle", board.buttons[16].id); t.bus.advance(1)
        equal(t.io.bundled.left, 32768)
        local oldLast, originalFirst = board.buttons[16].id, board.buttons[1].id
        t.click(t.id, "edit"); t.click(t.id, "resizeGrid"); t.grid(t.id, 3, 2); t.click(t.id, "saveGrid")
        equal(#board.buttons, 16, "No state change until confirmation")
        t.click(t.id, "cancelConfirm"); equal(#board.buttons, 16)
        t.click(t.id, "saveGrid"); t.click(t.id, "confirm"); t.bus.advance(1)
        equal(#board.buttons, 6); equal(board.buttons[1].id, originalFirst); equal(t.io.bundled.left, 0)
        equal(mappings(t)["switchboard_switch_" .. oldLast], nil)
        t.click(t.id, "resizeGrid"); t.grid(t.id, 4, 4); t.click(t.id, "saveGrid")
        equal(#board.buttons, 16); assert(board.buttons[7].id > oldLast); equal(board.buttons[7].route, nil)
        t.reboot(); equal(#t.state.boards[1].buttons, 16)
    end

    function tests.switchboard_offline_touches_save_latest_intent_and_reconnect_through_cooldown_queue()
        local t = setup()
        local board = t.preset(t.id)
        t.click(t.id, "open", board.id)
        t.click(t.id, "toggle", board.buttons[1].id); t.bus.advance(1)
        equal(t.io.bundled.left, 1)
        t.io.active = false
        t.bus.advance(20)
        equal(t.central.server.ioClients.io_11.online, false)
        local content = table.concat(t.content(t.id), "\n")
        assert(content:find("ON of", 1, true), "Keep saved ON intent visible even when the offline label shortens")
        t.click(t.id, "toggle", board.buttons[1].id) -- OFF while offline
        t.click(t.id, "toggle", board.buttons[2].id) -- ON then OFF then ON
        t.click(t.id, "toggle", board.buttons[2].id)
        t.click(t.id, "toggle", board.buttons[2].id)
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.outputs[logical(board.buttons[1])], false)
        equal(saved.outputs[logical(board.buttons[2])], true)
        t.io = t.bus.computer(11, "io", {disk = t.io.disk, modemSide = "right"}):start()
        t.bus.advance(3)
        equal(t.io.bundled.left, 2)
        local found
        for _, wire in ipairs(t.api.getOutputs()) do if wire.name == logical(board.buttons[2]) then found = wire end end
        assert(found and found.confirmed)
    end

    function tests.switchboard_confirmed_disconnect_delete_and_group_off_preserve_other_apps()
        local t = setup()
        assert(t.api.mapOutput("other_app", "io_12", "back", 1, true))
        local a = t.preset(t.id)
        local b = t.preset(t.id, "io_12", "left")
        t.click(t.id, "open", a.id); t.click(t.id, "toggle", a.buttons[1].id); t.click(t.id, "toggle", a.buttons[2].id)
        t.bus.advance(1)
        t.view(t.id).screen, t.view(t.id).buttonId = "button", a.buttons[1].id
        t.click(t.id, "askClear"); t.click(t.id, "confirm"); t.bus.advance(1)
        equal(a.buttons[1].route, nil); equal(mappings(t)[logical(a.buttons[1])], nil); equal(t.io.bundled.left, 2)
        t.click(t.id, "switches"); t.click(t.id, "edit"); t.click(t.id, "askOff"); t.click(t.id, "confirm"); t.bus.advance(1)
        equal(t.io.bundled.left, 0)
        t.click(t.id, "board"); t.click(t.id, "home"); t.click(t.id, "open", b.id); t.click(t.id, "toggle", b.buttons[4].id)
        t.click(t.id, "home"); t.click(t.id, "settings"); t.click(t.id, "askAllOff"); t.click(t.id, "confirm")
        t.bus.advance(1); equal(t.other.bundled.left, 0); equal(t.api.getOutput("other_app"), true)
        t.click(t.id, "home"); t.click(t.id, "open", b.id); t.click(t.id, "edit"); t.click(t.id, "askDelete"); t.click(t.id, "confirm")
        equal(#t.state.boards, 1)
        for _, switch in ipairs(b.buttons) do equal(mappings(t)[logical(switch)], nil) end
        equal(t.api.getOutput("other_app"), true)
    end

    function tests.switchboard_keyboard_edits_and_cancels_names_with_small_and_large_keyboards()
        for _, dimensions in ipairs({{15, 10}, {64, 26}}) do
            local t = setup(unpack(dimensions))
            local board = t.empty(t.id, 2, 2)
            t.click(t.id, "open", board.id); t.click(t.id, "edit"); t.click(t.id, "renameView")
            local original = board.name
            for _ = 1, #original do t.click(t.id, "backspace") end
            t.click(t.id, "bank"); t.click(t.id, "key", "P"); t.click(t.id, "bank"); t.click(t.id, "key", "1")
            t.click(t.id, "saveName"); equal(board.name, "P1")
            t.click(t.id, "renameView"); t.click(t.id, "space"); t.click(t.id, "key", "q"); t.click(t.id, "cancelName")
            equal(board.name, "P1")
            t.click(t.id, "switches"); t.click(t.id, "editSwitch", board.buttons[1].id); t.click(t.id, "renameSwitch")
            t.click(t.id, "clearName")
            t.click(t.id, "key", "a"); t.click(t.id, "space"); t.click(t.id, "key", "b"); t.click(t.id, "saveName")
            equal(board.buttons[1].name, "a b"); equal(board.buttons[1].customName, true)
            t.route(t.id, board, 1, "io_11", "front", 1)
            equal(board.buttons[1].name, "a b", "Rewiring preserves user labels")
            t.reboot(); equal(t.state.boards[1].name, "P1"); equal(t.state.boards[1].buttons[1].name, "a b")
        end
    end

    function tests.switchboard_every_keyboard_character_is_reachable_and_fields_enforce_limits()
        local t = setup(15, 10)
        local board = t.empty(t.id, 1, 1)
        t.click(t.id, "open", board.id); t.click(t.id, "edit"); t.click(t.id, "renameView")
        local found = {}
        for _, bank in ipairs({"abc", "ABC", "123"}) do
            local keyboard = t.view(t.id).keyboard
            keyboard.bank, keyboard.page = bank, 1
            for page = 1, 2 do
                for _, hit in ipairs(t.content(t.id).hits) do if hit.action == "key" then found[hit.value] = true end end
                if page == 1 then t.click(t.id, "keyPage") end
            end
        end
        for char in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.:!?+()@#&=,%*'\""):gmatch(".") do assert(found[char], "Missing key " .. char) end
        local keyboard = t.view(t.id).keyboard
        keyboard.draft, keyboard.bank, keyboard.page = "", "abc", 1
        for _ = 1, 40 do t.click(t.id, "key", "a") end
        equal(#keyboard.draft, 32)
        for _ = 1, 32 do t.click(t.id, "backspace") end
        for _, hit in ipairs(t.content(t.id).hits) do if hit.action == "saveName" then equal(hit.enabled, false) end end
    end

    function tests.switchboard_style_settings_and_view_order_persist_without_changing_wire_colours_or_os_chrome()
        local t = setup()
        local a = t.preset(t.id)
        local b = t.empty(t.id, 2, 2)
        t.click(t.id, "open", b.id); t.click(t.id, "edit"); t.click(t.id, "reorder", -1)
        equal(t.state.boards[1].id, b.id)
        t.click(t.id, "board"); t.click(t.id, "home"); t.click(t.id, "settings")
        t.click(t.id, "accent"); t.click(t.id, "colour", 8192)
        for key, value in pairs({background = 4096, border = 256, unbound = 512}) do
            t.click(t.id, "palette", key); t.click(t.id, "colour", value)
        end
        t.click(t.id, "density"); equal(t.state.settings.density, "compact")
        t.click(t.id, "home"); t.click(t.id, "open", a.id)
        local lines = t.content(t.id)
        local hit
        for _, item in ipairs(lines.hits) do if item.action == "toggle" and item.value == a.buttons[1].id then hit = item end end
        assert(hit)
        t.paint()
        local win = t.window(t.id)
        equal(t.top.bg[win.y][win.x], 128, "App settings never modify the OS border")
        local hasWhite = false
        for y = win.y + hit.y1, win.y + hit.y2 do
            for x = win.x + hit.x1, win.x + hit.x2 do if t.top.bg[y][x] == 1 then hasWhite = true end end
        end
        assert(hasWhite, "White bundled tiles remain white")
        t.reboot(); equal(t.state.settings.border, 256); equal(t.state.settings.background, 4096)
        equal(t.state.boards[1].id, b.id); equal(t.api.getAppColour("switchboard"), 8192)
    end

    function tests.switchboard_concurrent_windows_keep_navigation_and_reject_stale_routing_and_deleted_targets()
        local t = setup()
        local board = t.empty(t.id, 2, 2)
        local id2 = t.open("left")
        t.click(t.id, "open", board.id); equal(t.view(id2).screen, nil)
        t.route(t.id, board, 1, "io_11", "left", 1)
        t.click(t.id, "route") -- first window holds the old route snapshot
        t.route(id2, board, 1, "io_12", "left", 2)
        local accepted = t.app.handleIOSelection(t.view(t.id).routeKey, {clientId = "io_11", side = "front", color = 4},
            t.state, t.api, t.context(t.id))
        equal(accepted, false)
        equal(board.buttons[1].route.clientId, "io_12")
        t.click(t.id, "cancel")
        t.view(id2).screen = "edit"; t.click(id2, "askDelete"); t.click(id2, "confirm")
        t.paint(); equal(t.view(t.id).screen, "home", "A removed board does not leave a broken window")
        equal(#t.state.boards, 0)
    end

    function tests.switchboard_large_custom_grid_and_size_matrix_keep_all_controls_inside_content()
        local t = setup()
        local board = t.empty(t.id, 16, 16)
        equal(#board.buttons, 256)
        local screens = {"home", "sources", "sides", "create", "board", "switches", "edit", "button", "grid", "settings", "palette", "keyboard", "confirm", "message"}
        local checked = 0
        for _, width in ipairs({12, 13, 17, 24, 31, 42, 79}) do
            for _, height in ipairs({6, 7, 9, 12, 18, 30}) do
                for _, screen in ipairs(screens) do
                    local view = {screen = screen, boardId = board.id, buttonId = board.buttons[1].id, newClient = "io_11", newSide = "left",
                        gridDraft = {target = "new", columns = 16, rows = 16}, colourField = "background", confirm = "off", confirmBack = "edit",
                        keyboard = {kind = "view", id = board.id, draft = "Name", bank = "abc", page = 1},
                        message = "Long detailed error with client and wire information requiring pagination on a very small display"}
                    local context = {view = view, appName = "switchboard", windowId = t.id}
                    local lines = t.app.render(width, height, t.state, t.api, context)
                    equal(#lines, height)
                    for _, line in ipairs(lines) do equal(#line, width) end
                    local occupied = {}
                    for _, hit in ipairs(lines.hits) do
                        local y1, y2 = hit.y1 or hit.y, hit.y2 or hit.y
                        assert(hit.x1 >= 1 and hit.x2 <= width and hit.x1 <= hit.x2 and y1 >= 1 and y2 <= height and y1 <= y2,
                            screen .. " hit outside " .. width .. "x" .. height)
                        for y = y1, y2 do for x = hit.x1, hit.x2 do
                            local key = x .. ":" .. y
                            assert(not occupied[key], screen .. " overlapping controls at " .. key)
                            occupied[key] = true
                        end end
                    end
                    for _, style in ipairs(lines.styles) do
                        assert(style.x >= 1 and style.y >= 1 and style.width >= 1 and style.height >= 1
                            and style.x + style.width - 1 <= width and style.y + style.height - 1 <= height, screen .. " style outside content")
                    end
                    checked = checked + 1
                end
            end
        end
        equal(checked, 588)
    end

    function tests.switchboard_batch_rejects_invalid_or_duplicate_wires_and_rolls_back_whole_group()
        local t = setup()
        local before = serialize(mappings(t))
        equal(t.api.updateOutputs({{name = "a", clientId = "io_11", side = "left", color = 1, value = true},
            {name = "b", clientId = "io_11", side = "left", color = 1, value = true}}), false)
        equal(t.api.updateOutputs({{name = "a", clientId = "io_11", side = "right", color = 1}}), false)
        equal(t.api.updateOutputs({{name = "a", clientId = "io_11", side = "left", color = 3}}), false)
        equal(t.api.updateOutputs({[2] = {name = "a", clientId = "io_11", side = "left", color = 1}}), false)
        equal(t.api.updateOutputs({notAnArray = {name = "a", remove = true}}), false)
        equal(serialize(mappings(t)), before)
        assert(t.api.updateOutputs({{name = "a", clientId = "io_11", side = "left", color = 1, value = true},
            {name = "b", clientId = "io_12", side = "left", color = 2, value = true}}))
        t.bus.advance(1); equal(t.io.bundled.left, 1); equal(t.other.bundled.left, 2)
        -- Final-state validation permits an atomic swap of two previously owned wires.
        assert(t.api.updateOutputs({{name = "a", clientId = "io_12", side = "left", color = 2},
            {name = "b", clientId = "io_11", side = "left", color = 1}}))
        t.central.disk.failWrite = true
        equal(t.api.updateOutputs({{name = "a", remove = true}, {name = "b", value = false}}), false)
        equal(t.api.getOutput("a"), true); equal(t.api.getOutput("b"), true)
        t.central.disk.failWrite = false
        assert(t.api.updateOutputs({{name = "a", remove = true}, {name = "b", remove = true}}))
        t.bus.advance(1); equal(t.io.bundled.left, 0); equal(t.other.bundled.left, 0)
    end
end
