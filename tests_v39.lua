-- End-to-end coverage for the v39 desktop, wiring and optional app entry points.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local function read(path)
        local file = assert(io.open(path, "r"))
        local value = file:read("*a")
        file:close()
        return value
    end
    local settings, topId, leftId = "@settings", "monitor_13:top", "monitor_13:left"
    local wires = [[
        local app={title="Wiring fixture",minWidth=12,minHeight=6}
        function app.render(w,h,state,api)
            local ui=api.ui.content(w,h)
            ui.button(2,"Configure","configure")
            return ui.lines
        end
        function app.handleTouch(x,y,w,h,state,api)
            if y~=2 then return false end
            state.example=42
            return api.updateOutputs({
                {name="fixture_shared",clientId="io_11",side="front",color=1,value=true},
                {name="fixture_only",clientId="io_11",side="front",color=2,value=true},
            })
        end
        function app.handleIOSelection(key,address,state,api) state[key]=address; return api.save() end
        function app.handleSensorSelection(key,address,state,api) state[key]=address; return api.save() end
        return app
    ]]
    local alarm = [[
        local app={title="Test alarm",backgroundService=true}
        local function publish(state,api)
            return api.setNotifications("alarm",state.active and {{key="test_1",title="Test alarm",message="Wake up"}} or {})
        end
        function app.init(state,api) publish(state,api) end
        function app.handleNotification(key,state,api)
            state.active=false
            assert(api.save())
            return publish(state,api)
        end
        return app
    ]]
    local function setup(apps, width, height)
        local bus = newBus()
        local central = bus.computer(10, "server", {apps = {}, enabledApps = {}})
        local config = unserialize(central.disk.files["configs_os.txt"])
        for name, source in pairs(apps or {}) do
            local path = "apps_" .. name .. ".lua"
            config.enabledApps[name] = true
            central.disk.files[path] = source == true and read(path) or source
        end
        central.disk.files["configs_os.txt"] = serialize(config)
        central:start()
        local bridge = bus.computer(11, "io", {modemSide = "right"}):start()
        local top, left = monitor(width or 64, height or 26), monitor(15, 10)
        local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
        bus.advance(2)
        local t = {bus = bus, central = central, bridge = bridge, top = top, left = left, display = display}
        function t.reload() t.server, t.api, t.state = t.central.server, t.central.server.api, t.central.server.state end
        t.reload()
        function t.paint() t.server.refreshMonitors(true); t.bus.pump() end
        function t.touch(side, x, y) t.bus.queue(display, {"monitor_touch", side, x, y}); t.bus.pump() end
        function t.open(name, side, w, h, x, y)
            local id = assert(t.api.openApp(name, side == "left" and leftId or topId, x, y, w, h))
            t.paint()
            return id
        end
        function t.lines(id)
            local win = assert(t.state.windows[id], "Window closed")
            local app = t.server.apps[win.appName] or t.server.systemApps[win.appName]
            return app.render(win.width - 2, win.height - 2, t.state.appStates[win.appName], t.api,
                {windowId = id, monitorId = win.monitorId, appName = win.appName, view = t.server.views[id]})
        end
        function t.click(id, action, value)
            for _ = 1, 48 do
                t.paint()
                local win, dialog = t.state.windows[id], t.server.dialogs[id]
                local hits = dialog and dialog.hits or t.lines(id).hits
                local nextHit
                for _, hit in ipairs(hits) do
                    if hit.enabled ~= false then
                        if hit.action == action and (value == nil or hit.value == value or type(value) == "function" and value(hit.value)) then
                            t.touch(win.monitorId:match(":(.+)$"), win.x + hit.x1, win.y + (hit.y or hit.y1))
                            return
                        elseif hit.action == "next" or hit.action == "page" and type(hit.value) == "table" and hit.value.page then
                            local text = t.top.lines[win.y + (hit.y or hit.y1)]:sub(win.x + hit.x1, win.x + hit.x2)
                            if text:find(">", 1, true) then nextHit = hit end
                        end
                    end
                end
                if not nextHit then break end
                t.touch(win.monitorId:match(":(.+)$"), win.x + nextHit.x1, win.y + (nextHit.y or nextHit.y1))
            end
            error("Missing action " .. action .. " in " .. tostring(t.server.views[id].screen or t.server.views[id].section))
        end
        function t.reboot()
            t.central = bus.computer(10, "server", {disk = t.central.disk}):start()
            t.reload()
            bus.advance(6)
            t.paint()
        end
        return t
    end
    local function scope(target) return function(value) return value.id == target end end

    function tests.v39_catalog_uses_actual_cycle_names_and_keeps_nyan_anchor()
        local t = setup({screensaver = true})
        local names, installed = t.api.getScreensavers()
        assert(installed); equal(#names, 20); equal(names[9], "Nyan Cat")
        local win = t.open(settings, "top", 55, 25, 1, 1)
        t.click(win, "screensavers")
        local text = table.concat(t.lines(win), "\n")
        for i, name in ipairs(names) do assert(text:find(i .. ". " .. name, 1, true), name) end
        local id = t.open("screensaver")
        t.touch("top", 1, 1)
        equal(t.server.views[id].design, #names)
        t.touch("top", t.top.width, 1)
        equal(t.server.views[id].design, 1)
    end

    function tests.v39_picker_names_and_input_readout_use_stable_route_ids()
        local t = setup({wires = wires, switchboard = true})
        t.bus.computer(14, "sensor", {sensors = {top = {card = "openccsensors.item.appliedenergisticssensor",
            targets = {me = {Name = "ME Access Point"}}, details = {me = {Powered = true}}}}}):start()
        t.bus.advance(2)
        local win = t.open(settings, "top", 50, 20, 1, 1)
        t.click(win, "names"); t.click(win, "nameClient", "io_11"); t.click(win, "editName")
        t.server.views[win].keyboard.draft = "Pump Room"
        t.click(win, "saveText")
        equal(t.api.clientName("io_11"), "Pump Room")
        assert(t.api.setClientName("sensor_14", "Farm Sensor"))
        t.bridge.bundledInputs.front = 8
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump()
        local id = t.open("wires", "top", 48, 18, 1, 1)
        assert(t.api.pickIO(id, "input", "input"))
        t.paint(); assert(table.concat(t.top.lines):find("Pump Room", 1, true))
        t.click(id, "select", "io_11"); t.click(id, "select", "front"); t.click(id, "select", 8)
        assert(table.concat(t.top.lines):find("lightBlue / ON", 1, true))
        t.click(id, "use"); equal(t.state.appStates.wires.input.clientId, "io_11")
        assert(t.api.pickSensor(id, "sensor", nil, "ae"))
        t.paint(); assert(table.concat(t.top.lines):find("Farm Sensor", 1, true))
        t.click(id, "select", function(value) return value.value == "sensor_14" end)
        assert(table.concat(t.top.lines):find("Farm Sensor", 1, true))
        t.click(id, "cancel")
        local sw = t.open("switchboard", "top", 48, 18, 1, 1)
        t.click(sw, "add"); assert(table.concat(t.lines(sw)):find("Pump Room", 1, true))
        t.reboot()
        equal(t.api.clientName("io_11"), "Pump Room")
        equal(t.api.clientName("sensor_14"), "Farm Sensor")
    end

    function tests.v39_test_output_pulses_only_selected_wire_and_restores_state()
        local t = setup({wires = wires})
        assert(t.api.mapOutput("selected", "io_11", "front", 1, false))
        assert(t.api.mapOutput("untouched", "io_11", "front", 2, true))
        t.bus.advance(2)
        local id = t.open("wires", "top", 48, 21, 1, 1)
        assert(t.api.pickIO(id, "route", "output"))
        t.click(id, "select", "io_11"); t.click(id, "select", "front"); t.click(id, "select", 1)
        t.click(id, "test"); t.bus.advance(.8)
        equal(t.bridge.bundled.front, 3)
        equal(t.api.getOutput("selected"), false, "Test overlay never modifies saved intent")
        equal(t.api.getOutputs()[2].confirmed, true, "Other colors stay confirmed")
        equal(t.state.appStates.wires.route, nil)
        t.bus.advance(3)
        equal(t.bridge.bundled.front, 2)
        equal(t.api.getOutputs()[1].confirmed, true)
        t.click(id, "use")
        equal(t.state.appStates.wires.route.color, 1)
    end

    function tests.v39_reboot_clears_an_interrupted_test_on_a_previously_unused_side()
        local t = setup({wires = wires})
        local id = t.open("wires", "top", 48, 21, 1, 1)
        assert(t.api.pickIO(id, "route", "output"))
        t.click(id, "select", "io_11"); t.click(id, "select", "top"); t.click(id, "select", 1)
        t.click(id, "test"); t.bus.advance(.7)
        equal(t.bridge.bundled.top, 1)
        assert(t.state.managedSides.io_11.top)
        t.reboot()
        equal(t.bridge.bundled.top, 0)
        equal(t.state.appStates.wires.route, nil)
    end

    function tests.v39_scope_captures_short_edges_and_deduplicates_used_routes()
        local t = setup({io_scope = true})
        assert(t.api.mapOutput("alias_one", "io_11", "front", 1, false))
        assert(t.api.mapOutput("alias_two", "io_11", "front", 1))
        t.state.appStates.coffee = {playerInput = {clientId = "io_11", side = "top", color = 1}}
        local used = t.api.getUsedIO()
        equal(#used, 2)
        local address = {clientId = "io_11", side = "top", direction = "input", color = 1}
        t.bridge.bundledInputs.top = 1
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump()
        local _, current = t.api.getIOTrace(address, t.central.env.os.clock(), 1, 8)
        equal(current, "1")
        t.bus.advance(.1); t.bridge.bundledInputs.top = 0
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump()
        local trace, value = t.api.getIOTrace(address, t.central.env.os.clock(), 10, 10)
        equal(value, "0"); assert(trace:find("|", 1, true), "Short pulse disappeared between timeline cells")
        local id = t.open("io_scope", "top", 55, 20, 1, 1)
        t.click(id, "used"); t.click(id, "lane", function(wire) return wire.direction == "input" end)
        assert(table.concat(t.lines(id)):find("coffee", 1, true))
        t.click(id, "trace"); t.click(id, "menu"); t.click(id, "saveAs"); t.click(id, "saveText")
        equal(#t.state.appStates.io_scope.views[1].lanes, 2)
        t.click(id, "live")
        assert(t.server.views[id].finish)
        t.reboot()
        equal(t.server.views[id].finish, nil, "Boot starts a fresh timeline")
    end

    function tests.v39_logic_circuit_composes_gates_and_dismisses_rising_alert()
        local t = setup({logic_sandbox = true})
        t.bridge.digitalInputs.top = true
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump()
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        t.click(id, "newCircuit"); t.click(id, "saveText")
        t.click(id, "addNode"); t.click(id, "createNode", "Input"); t.click(id, "route")
        t.click(id, "select", "io_11"); t.click(id, "select", "top"); t.click(id, "select", false); t.click(id, "use")
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "NOT")
        t.click(id, "source", "a"); t.click(id, "assignSource", 1); t.click(id, "popup")
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Output")
        t.click(id, "source", "a"); t.click(id, "assignSource", 2)
        t.click(id, "route"); t.click(id, "select", "io_11"); t.click(id, "select", "front"); t.click(id, "select", 1); t.click(id, "use")
        t.click(id, "circuit"); t.click(id, "circuitMenu"); t.click(id, "toggleCircuit")
        t.bus.advance(2); equal(t.bridge.bundled.front, 0)
        t.bridge.digitalInputs.top = false
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump(); t.bus.advance(2)
        equal(t.bridge.bundled.front, 1)
        local popup = assert(t.server.monitors[topId].notification)
        t.touch("top", popup.ok.x1, popup.ok.y)
        equal(t.server.monitors[topId].notification, nil); equal(t.bridge.bundled.front, 1)
        t.bus.advance(2); equal(t.server.monitors[topId].notification, nil)
        t.click(id, "circuitMenu"); t.click(id, "toggleCircuit"); t.bus.advance(1)
        equal(t.bridge.bundled.front, 0)
        equal(t.state.outputMap.logic_sandbox_out_3, nil)
        equal(#t.api.getUsedIO(), 2, "Disabled circuit retains configured IO")
    end

    function tests.v39_presets_preview_adapt_and_keep_app_view_across_reboot()
        local t = setup({window_presets = true, notes = true, switchboard = true})
        local a = t.open("notes", "top", 26, 11, 1, 1)
        t.click(a, "newNote"); t.click(a, "saveText")
        equal(t.server.views[a].screen, "note")
        t.open("switchboard", "top", 29, 14, 30, 1)
        local id = t.open("window_presets", "top", 45, 20, 1, 1)
        t.click(id, "capture"); t.click(id, "captureScope", "one"); t.click(id, "saveText")
        t.click(id, "open", 1); t.click(id, "slot", topId); t.click(id, "assign"); t.click(id, "assignTarget", leftId)
        t.click(id, "preview")
        local slots = t.state.appStates.window_presets.presets[1].slots
        local plan, valid = t.api.previewWindowPreset(slots, {[topId] = leftId})
        assert(valid); equal(plan[1].visible, 1); equal(plan[1].minimized, 1)
        t.central.disk.failWrite = true
        equal(t.api.applyWindowPreset(slots, {[topId] = leftId}), false)
        t.central.disk.failWrite = false
        t.click(id, "confirm"); t.click(id, "apply")
        local notes
        for _, win in pairs(t.state.windows) do if win.monitorId == leftId and win.appName == "notes" then notes = win end end
        assert(notes and notes.minimized); equal(t.server.views[notes.id].noteId, 1)
        t.reboot(); equal(t.server.views[notes.id].screen, "note")
        equal(t.state.appStates.notes.notes[1].name, "Note 1")
    end

    function tests.v39_notes_export_real_markdown_task_list()
        local t = setup({notes = true})
        local id = t.open("notes", "top", 45, 18, 1, 1)
        t.click(id, "newNote"); t.click(id, "saveText"); t.click(id, "add"); t.click(id, "newLine", "check")
        t.server.views[id].keyboard.draft = "Check the relay"
        t.click(id, "saveText"); t.click(id, "toggle", 1)
        t.click(id, "menu"); t.click(id, "export")
        assert(t.central.disk.files["notes_export_1.md"]:find("- [x] Check the relay", 1, true))
        t.reboot(); assert(t.state.appStates.notes.notes[1].lines[1].checked)
    end

    function tests.v39_switchboard_scenes_save_and_apply_current_view_in_one_batch()
        local t = setup({switchboard = true})
        local id = t.open("switchboard", "top", 56, 24, 1, 1)
        t.click(id, "add"); t.click(id, "client", "io_11"); t.click(id, "side", "front"); t.click(id, "create")
        assert(t.api.setOutput("switchboard_switch_1", true))
        t.click(id, "scenes"); t.click(id, "sceneBoards"); t.click(id, "capture", 1); t.click(id, "saveText")
        assert(t.api.setOutput("switchboard_switch_1", false))
        assert(t.api.setOutput("switchboard_switch_2", true))
        t.click(id, "apply", 1); t.bus.advance(2)
        equal(t.bridge.bundled.front, 1)
        equal(#t.state.appStates.switchboard.scenes, 1)
        t.reboot(); equal(t.state.appStates.switchboard.scenes[1].name, "Scene 1")
    end

    function tests.v39_selective_backup_restores_state_views_and_routes_without_touching_other_apps()
        local t = setup({wires = wires, notes = true})
        local id = t.open("wires", "top", 42, 14, 1, 1)
        t.click(id, "configure")
        t.server.views[id].exampleView = "open"
        local settingsId = t.open(settings, "top", 48, 20, 1, 1)
        t.click(settingsId, "data"); t.click(settingsId, "backupMenu"); t.click(settingsId, "backupList")
        t.click(settingsId, "selectScope", scope("wires"))
        assert(t.central.disk.files["backup_app_wires.txt"])
        t.click(settingsId, "backupMenu"); t.click(settingsId, "data"); t.click(settingsId, "resetData")
        t.click(settingsId, "selectScope", scope("wires")); t.click(settingsId, "commit")
        equal(t.state.appStates.wires.example, nil)
        assert(t.api.setClientName("io_11", "Friendly IO"))
        t.click(settingsId, "data"); t.click(settingsId, "backupMenu"); t.click(settingsId, "restoreList")
        t.click(settingsId, "selectScope", scope("wires")); t.click(settingsId, "commit")
        equal(t.state.appStates.wires.example, 42)
        equal(t.state.outputMap.fixture_only.owner, "wires")
        equal(t.api.getOutput("fixture_only"), false)
        equal(t.api.clientName("io_11"), "Friendly IO")
        for wid, window in pairs(t.state.windows) do
            if window.appName == "wires" then equal(t.server.views[wid].exampleView, "open"); return end
        end
        error("Restored window missing")
    end

    function tests.v39_delete_app_releases_owned_routes_and_preserves_data_for_reinstall()
        local t = setup({wires = wires})
        local id = t.open("wires", "top", 42, 14, 1, 1)
        t.click(id, "configure")
        assert(t.api.mapOutput("manual", "io_11", "front", 1))
        t.bus.advance(2)
        local settingsId = t.open(settings, "top", 48, 20, 1, 1)
        t.click(settingsId, "data"); t.click(settingsId, "deleteApps"); t.click(settingsId, "selectScope", scope("wires"))
        t.central.disk.failWrite = true
        t.click(settingsId, "commit")
        equal(t.central.disk.files["apps_wires.lua"], wires); assert(t.state.windows[id])
        t.central.disk.failWrite = false
        t.click(settingsId, "commit"); t.bus.advance(2)
        equal(t.central.disk.files["apps_wires.lua"], nil); equal(t.state.windows[id], nil)
        equal(t.state.appStates.wires.example, 42); assert(t.state.archivedRoutes.wires.fixture_only)
        equal(t.bridge.bundled.front, 1)
        t.central.disk.files["apps_wires.lua"] = wires
        t.reboot()
        equal(t.state.archivedRoutes.wires, nil)
        equal(t.state.outputMap.fixture_only.owner, "wires")
        equal(t.api.getOutput("fixture_only"), false)
        equal(t.api.getOutput("fixture_shared"), true)
    end

    function tests.v39_inbox_is_below_saver_and_popup_remains_modal()
        local t = setup({alarm = alarm, screensaver = true})
        t.touch("top", t.top.width, t.top.height)
        assert(t.server.monitors[topId].inboxModel)
        local id = t.open("screensaver")
        equal(t.server.monitors[topId].inboxModel, nil)
        t.state.appStates.alarm.active = true
        assert(t.api.setNotifications("alarm", {{key = "test_1", title = "Test alarm", message = "Wake up"}}))
        assert(t.api.save()); t.paint()
        local popup = assert(t.server.monitors[topId].notification)
        t.touch("top", 1, 1)
        equal(t.server.views[id].design, 1)
        t.touch("top", popup.ok.x1, popup.ok.y)
        equal(t.server.monitors[topId].notification, nil); assert(t.state.windows[id])
        t.touch("top", 3, 3)
        assert(t.server.monitors[topId].inboxModel)
        equal(#t.state.alertHistory, 1); equal(t.state.alertHistory[1].open, nil)
        t.reboot()
        equal(#t.state.alertHistory, 1); equal(t.state.alertHistory[1].open, nil)
    end

    function tests.v39_inbox_reuses_original_active_occurrence_after_reboot()
        local t = setup({alarm = alarm})
        t.state.appStates.alarm.active = true
        assert(t.api.setNotifications("alarm", {{key = "test_1", title = "Test alarm", message = "Wake up"}}))
        local entry = t.state.alertHistory[1]
        local sequence, time, session = entry.sequence, entry.time, entry.session
        assert(t.api.save())
        t.reboot()
        assert(t.server.monitors[topId].notification)
        equal(#t.state.alertHistory, 1)
        equal(t.state.alertHistory[1].sequence, sequence)
        equal(t.state.alertHistory[1].time, time)
        equal(t.state.alertHistory[1].session, session)
    end

    function tests.v39_relay_map_lists_hops_from_os_toward_client_and_history_survives()
        local bus = newBus()
        local central = bus.computer(10, "server", {position = {0,0,0}, range = 25}):start()
        bus.computer(21, "relay", {position = {20,0,0}, range = 25}):start()
        bus.computer(22, "relay", {position = {40,0,0}, range = 25}):start()
        local bridge = bus.computer(11, "io", {position = {60,0,0}, range = 25}):start()
        local screen = monitor(60, 24)
        bus.computer(13, "monitor", {position = {0,0,0}, range = 25, monitors = {top = screen}}):start()
        bus.advance(7)
        local api = central.server.api
        assert(api.setClientName("relay_21", "Near OS")); assert(api.setClientName("relay_22", "Near IO"))
        local id = assert(api.openApp(settings, topId, 1, 1, 54, 20))
        local app = central.server.systemApps[settings]
        local view = {section = "overview", overview = {screen = "path", clientId = "io_11"}}
        local text = table.concat(app.render(52, 18, central.server.state.appStates[settings], api, {windowId = id, view = view}), "\n")
        local first, second = text:find("Near OS", 1, true), text:find("Near IO", 1, true)
        assert(first and second and first < second, "Expected OS then Near OS then Near IO")
        bridge.active = false
        bus.advance(16)
        local offline
        for _, entry in ipairs(api.getUptimeHistory()) do
            if entry.id == "io_11" and not entry.online then offline = entry end
        end
        assert(offline and offline.seconds >= 15)
        local oldCount = #api.getUptimeHistory()
        assert(api.save())
        local reboot = bus.computer(10, "server", {disk = central.disk}):start()
        assert(#reboot.server.api.getUptimeHistory() > oldCount)
    end

    function tests.v39_legacy_system_window_migrates_without_loading_old_program()
        local t = setup({system = "error('old standalone app executed')"})
        t.state.appStates.system = {version = 1, filter = "sensor"}
        t.state.windows[17] = {id = 17, appName = "system", monitorId = topId, x = 1, y = 1,
            width = 36, height = 14, order = 1, layout = "normal"}
        t.server.views[17] = {screen = "clients", pages = {}}
        assert(t.api.save()); t.reboot()
        equal(t.state.appStates.system, nil)
        equal(t.state.windows[17].appName, settings)
        equal(t.server.views[17].section, "overview")
        equal(t.server.views[17].overview.screen, "clients")
        equal(t.state.appStates[settings].overview.filter, "sensor")
        equal(t.server.apps.system, nil)
        assert(#t.api.getUptimeHistory() >= 4)
    end
end
