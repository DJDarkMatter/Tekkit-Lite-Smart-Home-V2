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
            local inset = win.fullscreen and 0 or 2
            return app.render(win.width - inset, win.height - inset, t.state.appStates[win.appName], t.api,
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
    local function newWiredCircuit(t, id)
        t.click(id, "homeMenu"); t.click(id, "wiringHome")
        t.click(id, "newCircuit"); t.click(id, "saveText")
    end
    local function scope(target) return function(value) return value.id == target end end

    function tests.v39_catalog_uses_actual_cycle_names_and_keeps_nyan_anchor()
        local t = setup({screensaver = true}, 72, 34)
        local names, installed = t.api.getScreensavers()
        assert(installed); equal(#names, 25); equal(names[9], "Nyan Cat")
        equal(names[21], "DVD Bounce"); equal(names[25], "Among Us Drift")
        local win = t.open(settings, "top", 55, 30, 1, 1)
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

    function tests.v41_cancel_client_rename_retains_selected_id_and_saved_name()
        local t = setup()
        assert(t.api.setClientName("io_11", "Pump Room"))
        local win = t.open(settings, "top", 40, 18, 1, 1)
        t.click(win, "names"); t.click(win, "nameClient", "io_11"); t.click(win, "editName")
        t.click(win, "clearText"); t.click(win, "key", "x"); t.click(win, "nameClient")
        local view = t.server.views[win]
        equal(view.nameId, "io_11"); equal(view.keyboard, nil)
        equal(t.api.clientName("io_11"), "Pump Room")
        assert(table.concat(t.top.lines, "\n"):find("ID io_11", 1, true))
        t.click(win, "editName"); equal(view.keyboard.draft, "Pump Room")
        view.section, view.nameId = "nameClient", nil -- Recover views saved by the old Back action.
        assert(t.api.save())
        t.reboot(); equal(t.server.views[win].section, "names")
        t.click(win, "nameClient", "io_11")
        equal(t.api.clientName("io_11"), "Pump Room")
    end

    function tests.v41_relay_map_back_keeps_the_observed_client_path()
        local t = setup()
        local win = t.open(settings, "top", 40, 19, 1, 1)
        t.click(win, "overview"); t.click(win, "relayMap"); t.click(win, "path", "io_11")
        t.click(win, "pathClient"); t.click(win, "path")
        equal(t.server.views[win].overview.clientId, "io_11")
        assert(table.concat(t.lines(win)):find("> io_11", 1, true))
        t.click(win, "pathClient"); t.click(win, "path"); t.click(win, "relayMap")
    end

    function tests.v41_desktop_load_prunes_invalid_entries_and_keeps_valid_saved_windows()
        local t = setup()
        local win = t.open(settings, "top", 40, 18, 1, 1)
        t.click(win, "appearance")
        assert(t.api.save())
        local path = "configs_os_state.txt"
        local saved = unserialize(t.central.disk.files[path])
        saved.windows.old = true
        saved.windows[0] = {appName = settings, monitorId = topId}
        saved.appearance.appColours = {[settings] = 2048, invalid = 3, [22] = 16}
        t.central.disk.files[path] = serialize(saved)
        t.reboot()
        equal(t.state.windows.old, nil); equal(t.state.windows[0], nil)
        equal(t.state.appearance.appColours.invalid, nil); equal(t.state.appearance.appColours[22], nil)
        equal(t.state.appearance.appColours[settings], 2048)
        equal(t.server.views[win].section, "appearance")
    end

    function tests.v41_monitor_detach_keeps_the_other_screen_connected()
        local t = setup()
        local win = t.open(settings, "left", 14, 8, 1, 1)
        t.display.monitors.top = nil
        t.bus.queue(t.display, {"peripheral_detach", "top"}); t.bus.pump()
        equal(t.display.client.devices.top, nil)
        equal(t.display.client.devices.left.connected, true)
        t.click(win, "names")
        t.display.monitors.top = t.top
        t.bus.queue(t.display, {"peripheral", "top"}); t.bus.pump()
        t.bus.advance(3)
        equal(t.display.client.devices.top.connected, true)
    end

    function tests.v41_all_apps_open_on_compact_and_large_monitors_in_one_os()
        local names = {"clock", "coffee", "io_scope", "level_emitter", "logic_sandbox", "me_monitor", "me_storage",
            "notes", "reactors", "screensaver", "solar_farm", "switchboard", "window_presets"}
        local enabled = {}
        for _, name in ipairs(names) do enabled[name] = true end
        local t = setup(enabled)
        names[#names + 1] = settings
        for _, name in ipairs(names) do
            local big = t.open(name, "top", 58, 23, 1, 1)
            local small = t.open(name, "left", 14, 8, 1, 1)
            t.bus.advance(.6)
            for _, id in ipairs({big, small}) do
                local lines = t.lines(id)
                assert(#lines >= 6, name .. " returned incomplete content")
                assert(not table.concat(lines, "\n"):find("App render failed", 1, true), name)
                assert(t.api.closeWindow(id))
            end
        end
        equal(t.central.disk.files["diagnostics_os_error.txt"], nil)
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
        newWiredCircuit(t, id)
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

    local function logicAE(t)
        local iron = {Name = "Iron Ingot", RawName = "item.ingotIron", Size = 64, DamageValue = 0}
        local data = {Powered = true, Items = {iron}}
        local sensor = t.bus.computer(14, "sensor", {sensors = {top = {card = "openccsensors.item.appliedenergisticssensor",
            targets = {me = {Name = "ME Access Point"}}, details = {me = data}}}}):start()
        t.bus.advance(3)
        return sensor, data, iron
    end
    local function selectLogicME(t, id)
        if not t.server.dialogs[id] then t.click(id, "amountSensor") end
        for _, choice in ipairs({"sensor_14", "top", "me"}) do
            t.click(id, "select", function(value) return value.value == choice end)
        end
        t.click(id, "use")
    end

    local function logicRoute(t, id, side, color)
        if not t.server.dialogs[id] then t.click(id, "route") end
        t.click(id, "select", "io_11"); t.click(id, "select", side); t.click(id, "select", color); t.click(id, "use")
    end
    local function logicSource(t, id, port, source)
        t.click(id, "source", port); t.click(id, "assignSource", source)
    end
    local function logicTime(t, id, value)
        while #t.server.views[id].time.draft > 0 do t.click(id, "digit", "Del") end
        for digit in value:gmatch(".") do t.click(id, "digit", digit) end
        t.click(id, "setNumber")
    end
    local function logicInput(t, mask)
        t.bridge.bundledInputs.top = mask
        t.bus.queue(t.bridge, {"redstone"}); t.bus.pump()
    end

    function tests.v45_logic_rule_editor_creates_a_stock_alarm_in_a_12_by_6_window()
        local t = setup({logic_sandbox = true}, 15, 10)
        local _, _, iron = logicAE(t)
        local id = t.open("logic_sandbox", "top", 14, 8, 1, 1)
        t.click(id, "newRule", "Sequence")
        local view = t.server.views[id]
        equal(view.screen, "rule")
        local rows = t.lines(id)
        assert(rows[2]:find("IF", 1, true) and rows[3]:find("THEN", 1, true))
        assert(rows[5]:find("Set up IF", 1, true))
        t.click(id, "editIF"); t.click(id, "ifType", "Item amount")
        selectLogicME(t, id); t.bus.advance(3)
        equal(view.screen, "amountList")
        t.click(id, "amountItem", function(item) return item.raw == iron.RawName end)
        t.click(id, "amountOperator"); t.click(id, "setOperator", "over")
        t.click(id, "editNumber", "threshold"); t.click(id, "digit", "Clr")
        t.click(id, "digit", "7"); t.click(id, "digit", "5"); t.click(id, "setNumber")
        t.click(id, "saveAmount")
        assert(table.concat(t.lines(id), "\n"):find("Count 64", 1, true))
        assert(t.lines(id)[5]:find("Set up THEN", 1, true))
        t.click(id, "editTHEN"); t.click(id, "addStep"); t.click(id, "createAction", "Alarm")
        t.click(id, "renameAlarm")
        for char in ("craft"):gmatch(".") do t.click(id, "key", char) end
        t.click(id, "saveText"); t.click(id, "returnRule"); t.click(id, "rule")
        local circuit = t.state.appStates.logic_sandbox.circuits[1]
        equal(circuit.enabled, false)
        t.click(id, "toggleCircuit")
        t.reboot()
        equal(t.server.views[id].screen, "rule")
        equal(t.state.appStates.logic_sandbox.circuits[1].enabled, true)
        iron.Size = 76; t.bus.advance(3)
        local alarmEntry = assert(t.server.notifications.logic_sandbox[1])
        equal(alarmEntry.title, "Alarm"); equal(alarmEntry.message, "craft")
    end

    function tests.v45_logic_rule_editor_combines_if_and_runs_ordered_redstone_actions()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 52, 20, 1, 1)
        t.click(id, "newRule", "Sequence"); t.click(id, "editIF")
        t.click(id, "ifType", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "ifOptions"); t.click(id, "ifCombine"); t.click(id, "ifType", "AND")
        t.click(id, "ifChild", "b"); t.click(id, "ifType", "Input"); logicRoute(t, id, "top", 2)
        t.click(id, "invertInput"); t.click(id, "conditionBack"); t.click(id, "conditionBack")
        t.click(id, "editTHEN"); t.click(id, "addStep"); t.click(id, "createAction", "Set output")
        logicRoute(t, id, "front", 1); t.click(id, "returnRule")
        t.click(id, "addStep"); t.click(id, "createAction", "Set output")
        logicRoute(t, id, "front", 1); t.click(id, "outputLevel"); t.click(id, "returnRule")
        t.click(id, "addStep"); t.click(id, "createAction", "Wait")
        t.click(id, "editTime"); logicTime(t, id, "1.5")
        t.click(id, "actionOrder"); t.click(id, "moveStep", -1)
        local circuit = t.state.appStates.logic_sandbox.circuits[1]
        local rule = circuit.nodes[1]
        equal(#circuit.nodes, 8, "Both redstone actions should reuse the selected wire")
        equal(rule.steps[2], circuit.nodes[8].id)
        t.click(id, "rule"); t.click(id, "toggleCircuit")
        logicInput(t, 3); t.bus.advance(1)
        equal(t.bridge.bundled.front, 0)
        logicInput(t, 1); t.bus.advance(1)
        equal(t.bridge.bundled.front, 1)
        t.bus.advance(1)
        equal(t.bridge.bundled.front, 0)
    end

    function tests.v45_logic_continuous_output_can_hold_a_condition_before_turning_on()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 52, 20, 1, 1)
        t.click(id, "homeMenu"); t.click(id, "newRule", "Output"); t.click(id, "editIF")
        t.click(id, "ifCombine"); t.click(id, "ifType", "Delay")
        t.click(id, "editTime"); logicTime(t, id, "1.5")
        t.click(id, "ifChild", "a"); t.click(id, "ifType", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "conditionBack"); t.click(id, "conditionBack")
        t.click(id, "editTHEN"); logicRoute(t, id, "front", 2)
        t.click(id, "toggleCircuit")
        logicInput(t, 1); t.bus.advance(1)
        equal(t.bridge.bundled.front, 0)
        t.bus.advance(1); equal(t.bridge.bundled.front, 2)
        logicInput(t, 0); t.bus.advance(1)
        equal(t.bridge.bundled.front, 0)
    end

    function tests.v45_logic_saved_wiring_opens_as_an_if_and_then_rule_after_upgrade()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 52, 20, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Sequence")
        logicSource(t, id, "a", 1)
        t.click(id, "steps"); t.click(id, "addStep"); t.click(id, "createAction", "Alarm")
        t.server.views[id].ruleEditor = nil -- Saved v44 window in the action editor.
        assert(t.api.save())
        t.reboot()
        equal(t.server.views[id].screen, "rule")
        local nodes = t.state.appStates.logic_sandbox.circuits[1].nodes
        equal(nodes[1].route.clientId, "io_11")
        equal(nodes[2].a, nodes[1].id); equal(nodes[2].steps[1], nodes[3].id)
        t.click(id, "toggleCircuit"); logicInput(t, 1); t.bus.advance(2)
        equal(t.server.notifications.logic_sandbox[1].message, "Circuit 1")
    end

    function tests.v44_logic_saved_item_editor_reads_live_stock_while_the_circuit_is_disabled()
        local t = setup({logic_sandbox = true})
        local sensor, data, iron = logicAE(t)
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Item amount"); t.click(id, "editAmount")
        selectLogicME(t, id); t.bus.advance(3)
        t.click(id, "amountList"); t.click(id, "amountItem", function(item) return item.raw == iron.RawName end)
        t.click(id, "saveAmount"); t.bus.advance(6)
        local circuit = t.state.appStates.logic_sandbox.circuits[1]
        equal(circuit.enabled, false)
        assert(table.concat(t.lines(id), "\n"):find("Count 64", 1, true), "Saved Item amount editor lost its live ME reading")
        iron.Size = 512; t.bus.advance(3)
        assert(table.concat(t.lines(id), "\n"):find("Count 512", 1, true))
        equal(#sensor.client.watches, 1)
        data.Powered = false; t.bus.advance(3)
        assert(table.concat(t.lines(id), "\n"):find("unpowered", 1, true), "Unavailable counts need a source diagnostic")
    end

    function tests.v44_logic_item_amount_runs_a_named_alarm_through_if_then_and_rearms_after_acknowledgement()
        local t = setup({logic_sandbox = true})
        local sensor, data, iron = logicAE(t)
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Item amount"); t.click(id, "editAmount")
        selectLogicME(t, id); t.bus.advance(3)
        t.click(id, "amountList"); t.click(id, "amountItem", function(item) return item.raw == iron.RawName end)
        t.click(id, "saveAmount")
        for _, hit in ipairs(t.lines(id).hits) do assert(hit.action ~= "popup") end
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Sequence")
        logicSource(t, id, "a", 1)
        t.click(id, "steps"); t.click(id, "addStep"); t.click(id, "createAction", "Alarm")
        local circuit = t.state.appStates.logic_sandbox.circuits[1]
        equal(#circuit.nodes, 3); equal(circuit.nodes[2].a, circuit.nodes[1].id)
        equal(circuit.nodes[2].steps[1], circuit.nodes[3].id)
        t.click(id, "renameAlarm")
        for char in ("low stock"):gmatch(".") do
            if char == " " then t.click(id, "space") else t.click(id, "key", char) end
        end
        t.click(id, "saveText")
        equal(circuit.nodes[3].alarmName, "low stock")
        iron.Size = 63; t.bus.advance(2)
        equal(t.server.monitors[topId].notification, nil, "A disabled circuit must not raise its alarm")
        t.click(id, "returnRule"); t.click(id, "node"); t.click(id, "circuit")
        t.click(id, "toggleCircuit"); t.bus.advance(3)
        local entry = assert(t.server.notifications.logic_sandbox[1])
        equal(entry.title, "Alarm"); equal(entry.message, "low stock")
        local key = entry.key
        t.reboot()
        equal(t.server.notifications.logic_sandbox[1].key, key)
        equal(t.state.appStates.logic_sandbox.circuits[1].nodes[3].alarmName, "low stock")
        local popup = assert(t.server.monitors[topId].notification)
        t.touch("top", popup.ok.x1, popup.ok.y); t.bus.advance(3)
        equal(t.server.monitors[topId].notification, nil, "Acknowledging a held condition must not immediately ring again")
        data.Powered = false; t.bus.advance(3)
        data.Powered = true; t.bus.advance(3)
        equal(t.server.monitors[topId].notification, nil, "A missing reading must not rearm the alarm")
        iron.Size = 64; t.bus.advance(3)
        iron.Size = 63; t.bus.advance(3)
        assert(t.server.notifications.logic_sandbox[1].key ~= key)
        equal(t.server.notifications.logic_sandbox[1].message, "low stock")
    end

    function tests.v44_logic_rule_alarm_uses_the_circuit_name_on_small_windows()
        local t = setup({logic_sandbox = true}, 15, 10)
        local id = t.open("logic_sandbox", "top", 14, 8, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Sequence")
        logicSource(t, id, "a", 1)
        t.click(id, "steps"); t.click(id, "addStep"); t.click(id, "createAction", "Alarm")
        t.click(id, "renameAlarm")
        for char in ("cat"):gmatch(".") do t.click(id, "key", char) end
        t.click(id, "saveText")
        t.click(id, "renameAlarm"); t.click(id, "clearText"); t.click(id, "saveText")
        local circuit = t.state.appStates.logic_sandbox.circuits[1]
        equal(circuit.nodes[3].alarmName, nil)
        t.click(id, "returnRule"); t.click(id, "node"); t.click(id, "circuit"); t.click(id, "toggleCircuit")
        logicInput(t, 1); t.bus.advance(2)
        local entry = assert(t.server.notifications.logic_sandbox[1])
        equal(entry.title, "Alarm"); equal(entry.message, circuit.name)
        local popup = assert(t.server.monitors[leftId].notification)
        t.touch("left", popup.ok.x1, popup.ok.y)
        t.bus.advance(2); equal(t.server.monitors[leftId].notification, nil)
    end

    function tests.v44_logic_old_node_popups_migrate_without_duplicating_or_losing_pending_alerts()
        local t = setup({logic_sandbox = true})
        local sensor, data, iron = logicAE(t)
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Item amount"); t.click(id, "editAmount")
        selectLogicME(t, id); t.bus.advance(3)
        t.click(id, "amountList"); t.click(id, "amountItem", function(item) return item.raw == iron.RawName end)
        t.click(id, "saveAmount"); iron.Size = 63
        local state = t.state.appStates.logic_sandbox
        local circuit, node = state.circuits[1], state.circuits[1].nodes[1]
        node.popup, node.high, node.alert, state.nextAlert = true, true, 1, 2
        circuit.enabled = true
        t.api.setNotifications("logic_sandbox", {{key = "logic_1_1", title = "Logic Sandbox", message = "Old alert"}})
        assert(t.api.save())
        t.reboot()
        circuit = t.state.appStates.logic_sandbox.circuits[1]
        equal(#circuit.nodes, 3); equal(circuit.nodes[1].popup, nil)
        local rule, alarm = circuit.nodes[2], circuit.nodes[3]
        equal(rule.kind, "Sequence"); equal(rule.a, 1); equal(rule.steps[1], alarm.id)
        equal(alarm.kind, "Alarm"); equal(alarm.alert, 1)
        equal(t.server.notifications.logic_sandbox[1].key, "logic_1_1")
        local count = 0
        for _, record in ipairs(t.state.alertHistory) do if record.open then count = count + 1 end end
        equal(count, 1, "The pending alert keeps its inbox identity")
        local popup = assert(t.server.monitors[topId].notification)
        t.touch("top", popup.ok.x1, popup.ok.y); t.bus.advance(2)
        equal(alarm.alert, nil); equal(alarm.alertNodeId, nil)
        equal(t.server.monitors[topId].notification, nil)
        t.reboot()
        equal(#t.state.appStates.logic_sandbox.circuits[1].nodes, 3)
    end

    function tests.v44_logic_failed_popup_migration_preserves_saved_rule_and_notification_state()
        local t = setup({logic_sandbox = true})
        local state = t.state.appStates.logic_sandbox
        state.circuits = {{id = 1, name = "Stock warning", enabled = false, nodes = {
            {id = 1, name = "Stock", kind = "Item amount", popup = true, high = true, alert = 7},
        }}}
        state.nextCircuit, state.nextNode, state.nextAlert = 2, 2, 8
        local before = serialize(state)
        t.central.disk.failWrite = true
        local ok = pcall(t.server.apps.logic_sandbox.init, state, t.api, {appName = "logic_sandbox"})
        equal(ok, false)
        equal(serialize(state), before)
        t.central.disk.failWrite = false
        t.server.apps.logic_sandbox.init(state, t.api, {appName = "logic_sandbox"})
        equal(#state.circuits[1].nodes, 3)
        equal(t.server.notifications.logic_sandbox[1].key, "logic_1_7")
    end

    function tests.v44_logic_numbered_rows_and_setup_tips_explain_an_action_without_a_rule()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Alarm")
        t.click(id, "circuit")
        local text = table.concat(t.lines(id), "\n")
        assert(text:find("1 Input", 1, true)); assert(text:find("2 Alarm", 1, true))
        assert(text:find("Action", 1, true)); assert(not text:find("B Alarm", 1, true))
        t.click(id, "setup"); t.click(id, "tip", 2)
        assert(table.concat(t.lines(id), "\n"):find("Add an If / Then block", 1, true))
        t.click(id, "editTip", 2)
        equal(t.server.views[id].nodeId, 2); equal(t.server.views[id].screen, "node")
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Sequence")
        logicSource(t, id, "a", 1)
        t.click(id, "steps"); t.click(id, "addStep"); t.click(id, "useAction", 2)
        t.click(id, "node"); t.click(id, "circuit"); t.click(id, "circuitMenu"); t.click(id, "setup")
        assert(table.concat(t.lines(id), "\n"):find("Connections are set", 1, true))
        t.click(id, "circuit"); t.click(id, "toggleCircuit"); t.bus.advance(1)
        text = table.concat(t.lines(id), "\n")
        assert(text:find("1 Input", 1, true)); assert(text:find("OFF", 1, true))
    end

    function tests.v41_logic_item_amount_tracks_live_stock_and_runs_closed_after_reboot()
        local t = setup({logic_sandbox = true})
        local sensor, data, iron = logicAE(t)
        local id = t.open("logic_sandbox", "top", 50, 22, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Item amount"); t.click(id, "editAmount")
        selectLogicME(t, id)
        t.click(id, "amountList"); t.click(id, "amountFind"); t.click(id, "amountSearch")
        t.click(id, "key", "i"); t.click(id, "saveText")
        t.bus.advance(5); t.click(id, "amountItem", function(item) return item.raw == iron.RawName end)
        t.click(id, "editNumber", "threshold"); t.click(id, "digit", "Clr"); t.click(id, "digit", "6")
        t.click(id, "digit", "4"); t.click(id, "setNumber"); t.click(id, "saveAmount")
        local node = t.state.appStates.logic_sandbox.circuits[1].nodes[1]
        equal(node.amount.item.raw, iron.RawName); equal(node.amount.threshold, 64)
        t.click(id, "editAmount"); t.click(id, "amountOperator"); t.click(id, "setOperator", "over")
        t.click(id, "cancelAmount"); equal(node.amount.operator, "under")
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "NOT")
        t.click(id, "source", "a"); t.click(id, "assignSource", 1)
        for _, wiring in ipairs({{1, 1}, {2, 2}}) do
            t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Output")
            t.click(id, "source", "a"); t.click(id, "assignSource", wiring[1])
            t.click(id, "route"); t.click(id, "select", "io_11"); t.click(id, "select", "front")
            t.click(id, "select", wiring[2]); t.click(id, "use")
        end
        t.click(id, "circuit"); t.click(id, "circuitMenu"); t.click(id, "toggleCircuit")
        t.bus.advance(5); equal(t.bridge.bundled.front, 2, "At the threshold, Under is false")
        equal(#sensor.client.watches, 1)
        iron.Size = 63
        t.bus.advance(5); equal(t.bridge.bundled.front, 1)
        data.Powered = false
        t.bus.advance(5); equal(t.bridge.bundled.front, 0, "Unknown must stay unknown through NOT")
        data.Powered, data.Items = true, {}
        t.bus.advance(5); equal(t.bridge.bundled.front, 1, "Missing item in complete inventory is zero")
        t.click(id, "home"); t.click(id, "close")
        t.reboot(); equal(t.bridge.bundled.front, 1, "The circuit resumes after fresh stock arrives")
        sensor.active = false
        t.bus.advance(25); equal(t.bridge.bundled.front, 0, "A lost sensor must release the output")
    end

    function tests.v41_logic_item_amount_manual_identity_and_cancel_fit_small_window()
        local t = setup({logic_sandbox = true})
        logicAE(t)
        local id = t.open("logic_sandbox", "top", 14, 8, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Item amount"); t.click(id, "editAmount")
        selectLogicME(t, id)
        t.click(id, "amountList"); t.click(id, "amountFind"); t.click(id, "newManualItem")
        t.click(id, "manualText", "raw"); t.click(id, "key", "a"); t.click(id, "saveText")
        t.click(id, "editNumber", "damage"); t.click(id, "digit", "7"); t.click(id, "setNumber")
        t.click(id, "useManualItem"); t.click(id, "amountOperator"); t.click(id, "setOperator", "exact")
        t.click(id, "editNumber", "threshold"); t.click(id, "digit", "Clr"); t.click(id, "setNumber")
        t.click(id, "saveAmount")
        local rule = t.state.appStates.logic_sandbox.circuits[1].nodes[1].amount
        equal(rule.item.raw, "a"); equal(rule.item.damage, 7); equal(rule.operator, "exact"); equal(rule.threshold, 0)
        t.click(id, "editAmount"); t.click(id, "amountSensor"); t.click(id, "cancel")
        t.click(id, "cancelAmount"); equal(t.state.appStates.logic_sandbox.circuits[1].nodes[1].amount, rule)
    end

    function tests.v42_logic_sequence_wires_a_compound_rule_waits_turns_off_and_alarms_with_no_window()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 58, 24, 1, 1)
        newWiredCircuit(t, id)
        local function add(kind)
            if t.server.views[id].screen == "node" then t.click(id, "circuit") end
            t.click(id, "addNode"); t.click(id, "createNode", kind)
        end
        for _, color in ipairs({1, 2, 4}) do add("Input"); logicRoute(t, id, "top", color) end
        add("AND"); logicSource(t, id, "a", 2); logicSource(t, id, "b", 3)
        add("OR"); logicSource(t, id, "a", 1); logicSource(t, id, "b", 4)
        add("Sequence"); logicSource(t, id, "a", 5); t.click(id, "steps")
        local function block(kind)
            t.click(id, "addStep"); t.click(id, "createAction", kind)
            return t.server.views[id].nodeId
        end
        local firstWait = block("Wait")
        t.click(id, "editTime"); logicTime(t, id, "0.5"); t.click(id, "returnRule")
        block("Set output")
        t.click(id, "targets"); t.click(id, "newTarget"); logicRoute(t, id, "front", 1)
        t.click(id, "returnRule")
        block("Wait")
        t.click(id, "editTime"); logicTime(t, id, "20.17"); t.click(id, "returnRule")
        block("Set output")
        t.click(id, "targets"); t.click(id, "chooseTarget", 9); t.click(id, "outputLevel"); t.click(id, "returnRule")
        local alarm = block("Alarm")
        t.click(id, "returnRule")
        t.click(id, "addStep"); t.click(id, "useAction", firstWait)
        local nodes = t.state.appStates.logic_sandbox.circuits[1].nodes
        equal(nodes[6].steps[6], firstWait, "A second occurrence refers to the existing block")
        t.click(id, "selectStep", 6); t.click(id, "removeStep"); t.click(id, "confirmStep")
        t.click(id, "selectStep", 4); t.click(id, "moveStep", -1)
        t.click(id, "selectStep", 3); t.click(id, "moveStep", 1)
        t.click(id, "node")
        t.click(id, "circuit"); t.click(id, "flow")
        local flow = table.concat(t.lines(id), "\n")
        assert(flow:find("2 Input AND 3 Input", 1, true))
        assert(flow:find("1 Input OR 4 AND", 1, true))
        assert(flow:find("3. Wait 20.17s", 1, true))
        assert(flow:find("4. Set 9 Output target OFF", 1, true))
        t.click(id, "circuit"); t.click(id, "circuitMenu"); t.click(id, "toggleCircuit")
        logicInput(t, 2); t.bus.advance(1)
        equal(t.bridge.bundled.front, 0, "Input 2 alone is not enough")
        logicInput(t, 6); t.bus.advance(.5)
        equal(t.bridge.bundled.front, 0, "The first Wait must finish before ON")
        t.bus.advance(.5); equal(t.bridge.bundled.front, 1)
        local started = t.bridge.redstoneWrites[#t.bridge.redstoneWrites].time
        assert(t.api.closeWindow(id))
        t.bus.advance(20.19); equal(t.bridge.bundled.front, 1)
        t.bus.advance(.02); equal(t.bridge.bundled.front, 0)
        local ended = t.bridge.redstoneWrites[#t.bridge.redstoneWrites].time
        assert(math.abs(ended - started - 20.2) < .000001)
        local popup = assert(t.server.monitors[topId].notification)
        equal(t.server.notifications.logic_sandbox[1].title, "Alarm")
        equal(t.server.notifications.logic_sandbox[1].message, t.state.appStates.logic_sandbox.circuits[1].name)
        t.touch("top", popup.ok.x1, popup.ok.y)
        t.bus.advance(1.5); equal(t.bridge.bundled.front, 0, "A held condition must not trigger a second run")
        logicInput(t, 0); t.bus.advance(.5)
        logicInput(t, 1); t.bus.advance(1); equal(t.bridge.bundled.front, 1, "Input 1 alone satisfies the OR branch")
    end

    function tests.v42_logic_delay_requires_continuous_high_and_wakes_before_the_normal_tick()
        local t = setup({logic_sandbox = true})
        local id = t.open("logic_sandbox", "top", 14, 8, 1, 1)
        newWiredCircuit(t, id)
        t.click(id, "addNode"); t.click(id, "createNode", "Input"); logicRoute(t, id, "top", 1)
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Delay")
        logicSource(t, id, "a", 1); t.click(id, "editTime"); logicTime(t, id, "0.12")
        t.click(id, "circuit"); t.click(id, "addNode"); t.click(id, "createNode", "Output")
        logicSource(t, id, "a", 2); logicRoute(t, id, "front", 1)
        t.click(id, "circuit"); t.click(id, "circuitMenu"); t.click(id, "toggleCircuit")
        logicInput(t, 1); t.bus.advance(.64); equal(t.bridge.bundled.front, 0)
        logicInput(t, 0); t.bus.advance(.02); equal(t.bridge.bundled.front, 0, "A low before the deadline cancels the wait")
        logicInput(t, 1); t.bus.advance(.63); equal(t.bridge.bundled.front, 0)
        t.bus.advance(.02); equal(t.bridge.bundled.front, 1, "The 0.15s deadline runs before the next half-second tick")
        t.reboot()
        local nodes = t.state.appStates.logic_sandbox.circuits[1].nodes
        equal(nodes[2].delayHundredths, 12); equal(nodes[3].a, 2)
        equal(t.api.ui.durationHundredths("7200.37", 1), 720037)
    end

    function tests.v39_presets_preview_adapt_and_keep_app_view_across_reboot()
        local t = setup({window_presets = true, notes = true, switchboard = true})
        local a = t.open("notes", "top", 26, 11, 1, 1)
        t.click(a, "newNote"); t.click(a, "saveText")
        equal(t.server.views[a].screen, "note")
        t.open("switchboard", "top", 29, 14, 30, 1)
        local id = t.open("window_presets", "top", 45, 20, 1, 1)
        t.click(id, "capture"); t.click(id, "captureScope", "one"); t.click(id, "saveText")
        t.click(id, "open", 1); t.click(id, "slot", topId); t.click(id, "assign"); t.click(id, "slot")
        equal(t.server.views[id].slotId, topId)
        assert(table.concat(t.lines(id)):find("From " .. topId, 1, true))
        t.click(id, "assign"); t.click(id, "assignTarget", leftId)
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
