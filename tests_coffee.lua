-- Coffee, shared settings and durability integration checks using the real app.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local file = assert(io.open("apps_coffee.lua", "r"))
    local coffeeSource = file:read("*a"); file:close()
    local function coffee(options)
        options = options or {}
        local bus = newBus()
        local central = bus.computer(10, "server", {apps = {["apps_coffee.lua"] = coffeeSource}})
        if options.saveInterval then
            local settings = unserialize(central.disk.files["configs_os.txt"])
            settings.saveInterval = options.saveInterval
            central.disk.files["configs_os.txt"] = serialize(settings)
        end
        if options.saved then central.disk.files["configs_os_state.txt"] = serialize(options.saved) end
        central:start()
        local bridge = bus.computer(11, "io", {modemSide = "right"})
        bridge.digitalInputs.left = options.player ~= false
        bridge:start()
        local app, state, api = central.server.apps.coffee, central.server.state.appStates.coffee, central.server.api
        if options.configure ~= false then
            assert(app.handleIOSelection("playerInput", {clientId = "io_11", side = "left"}, state, api))
            assert(app.handleIOSelection("outputAddress", {clientId = "io_11", side = "front"}, state, api))
            bus.pump()
        end
        return bus, central, bridge, app, state
    end
    local function press(app, state, api, context, label, width, height)
        width, height = width or 30, height or 10
        local lines = app.render(width, height, state, api, context)
        for y, line in ipairs(lines) do
            local x = line:find(label, 1, true)
            if x then assert(app.handleTouch(x, y, width, height, state, api, context)); return end
        end
        error("Missing coffee control: " .. label .. " on page " .. tostring(context.view.page))
    end
    local function player(bus, bridge, value)
        bridge.digitalInputs.left = value
        bus.queue(bridge, {"redstone"}); bus.pump()
    end
    local function shortTimers(app, state, api, countdown, harvest)
        local context = {view = {page = "duration", field = "countdown", draft = countdown, step = 1}}
        press(app, state, api, context, "Save")
        context.view = {page = "duration", field = "harvest", draft = harvest, step = 1}
        press(app, state, api, context, "Save")
        context.view = {page = "reset"}
        press(app, state, api, context, "Confirm")
    end

    function tests.coffee_autostarts_without_windows_and_preserves_original_player_pause()
        local bus, central, bridge, app, state = coffee()
        equal(next(central.server.state.windows), nil)
        equal(state.config.countdown, 14400)
        equal(state.config.harvest, 60)
        bus.advance(2)
        equal(state.remainingTime, 14398)
        player(bus, bridge, false)
        local before = state.remainingTime
        bus.advance(3)
        equal(state.remainingTime, before)
        player(bus, bridge, true)
        bus.advance(1)
        equal(state.remainingTime, before - 1)
        equal(bridge.digital.front, false)
        equal(unserialize(central.disk.files["configs_os_state.txt"]).appStates.coffee.remainingTime, state.remainingTime)
    end

    function tests.coffee_harvest_manual_pause_force_and_offline_player_behavior()
        local bus, central, bridge, app, state = coffee()
        shortTimers(app, state, central.server.api, 2, 3)
        bus.pump(); bus.advance(2)
        equal(state.phase, "harvest")
        equal(bridge.digital.front, true)
        bus.advance(0.5)
        player(bus, bridge, false)
        local remaining = state.harvestRemaining
        bus.advance(2)
        equal(state.harvestRemaining, remaining)
        equal(bridge.digital.front, true, "Original keeps harvest ON while the player is away")
        local context = {view = {}}
        press(app, state, central.server.api, context, "Pause")
        bus.pump(); bus.advance(1)
        equal(bridge.digital.front, false)
        equal(state.harvestRemaining, remaining)
        press(app, state, central.server.api, context, "Resume")
        player(bus, bridge, true)
        bus.advance(6)
        assert(state.totalHarvests >= 1)
        assert(state.tripHarvests >= 1)
        -- An explicit force harvest overrides the presence input.
        player(bus, bridge, false)
        context.view = {page = "reset"}; press(app, state, central.server.api, context, "Confirm")
        press(app, state, central.server.api, context, "Harvest now")
        equal(state.forced, true)
        bus.pump(); bus.advance(5)
        equal(state.phase, "countdown")
        equal(bridge.digital.front, false)
    end

    function tests.coffee_reboots_restore_phase_progress_and_counters_without_catchup()
        local bus, central, bridge, app, state = coffee()
        shortTimers(app, state, central.server.api, 30, 12)
        local context = {view = {}}
        press(app, state, central.server.api, context, "Harvest now")
        bus.pump(); bus.advance(4)
        local saved = unserialize(central.disk.files["configs_os_state.txt"]).appStates.coffee
        assert(saved.harvestRemaining < 12 and saved.harvestRemaining > 0)
        central.active = false
        bus.advance(20)
        local snapshot = central.disk.files["configs_os_state.txt"]
        central = bus.computer(10, "server", {disk = central.disk}):start()
        state = central.server.state.appStates.coffee
        equal(state.phase, "harvest")
        equal(state.harvestRemaining, saved.harvestRemaining)
        equal(state.forced, true)
        bus.advance(15)
        equal(state.totalHarvests, 1, "Resume remaining harvest, not a full new harvest")
        equal(state.tripHarvests, 1)
        equal(state.phase, "countdown")
        assert(central.disk.files["configs_os_state.txt.bak"])
        assert(snapshot:find("coffee", 1, true))
    end

    function tests.coffee_closing_or_minimizing_windows_does_not_stop_background_logic()
        local bus, central, bridge, app, state = coffee()
        local screen = monitor(40, 15)
        local display = bus.computer(13, "monitor", {monitors = {top = screen}}):start()
        local id = assert(central.server.api.openApp("coffee", "monitor_13:top"))
        central.server.refreshMonitors(true); bus.pump()
        local before = state.remainingTime
        bus.queue(display, {"monitor_touch", "top", 6, screen.height}); bus.pump()
        equal(central.server.state.windows[id].minimized, true)
        bus.advance(2)
        equal(state.remainingTime, before - 2)
        assert(central.server.api.closeWindow(id)); bus.advance(2)
        equal(state.remainingTime, before - 4)
    end

    function tests.coffee_duration_edits_apply_next_cycle_and_legacy_import_preserves_progress()
        local bus, central, bridge, app, state = coffee()
        local context = {view = {page = "duration", field = "countdown", draft = 120, step = 1}}
        press(app, state, central.server.api, context, "+", 12, 6)
        press(app, state, central.server.api, context, "Save", 12, 6)
        equal(state.config.countdown, 121)
        equal(state.remainingTime, 14400, "Editing duration must not reset current progress")
        central.disk.files["countdown_state.txt"] = serialize({remainingTime = 1234,
            redstoneActive = true, redstoneEndTime = 17})
        context.view = {page = "import"}
        press(app, state, central.server.api, context, "Confirm")
        equal(state.phase, "harvest")
        equal(state.harvestRemaining, 17)
        equal(state.remainingTime, 1234)
        equal(state.paused, true)
        bus.advance(2)
        equal(bridge.digital.front, false)
        equal(state.harvestRemaining, 17)
        equal(unserialize(central.disk.files["configs_os_state.txt"]).appStates.coffee.harvestRemaining, 17)
    end

    function tests.clock_uses_native_world_time_and_updates_each_display()
        local bus = newBus()
        local central = bus.computer(10, "server")
        local worldTime = 6.5
        central.env.os.time = function() return worldTime end
        central:start()
        local screen, small = monitor(40, 12), monitor(15, 10)
        bus.computer(13, "monitor", {monitors = {top = screen, left = small}}):start()
        equal(central.server.api.getSystem().gameTime, "06:30")
        equal(central.server.api.getSystem().clockSource, "computer")
        assert(screen.lines[screen.height]:find("06:30", 1, true))
        assert(small.lines[small.height]:find("06:30", 1, true), "Small displays must keep the clock visible")
        worldTime = 23.999
        bus.advance(0.5)
        equal(central.server.api.getSystem().gameTime, "23:59")
        assert(screen.lines[screen.height]:find("23:59", 1, true))
    end

    function tests.io_picker_selects_client_side_and_color_and_excludes_modem_side()
        local bus, central, bridge, app, state = coffee({configure = false})
        local screen = monitor(40, 15)
        local display = bus.computer(13, "monitor", {monitors = {top = screen}}):start()
        local api = central.server.api
        local id = assert(api.openApp("coffee", "monitor_13:top"))
        central.server.refreshMonitors(true); bus.pump()
        local function touchPicker(label)
            local dialog = assert(central.server.dialogs[id])
            local win = central.server.state.windows[id]
            local Picker = central.env.dofile("lib_io_picker.lua")
            for attempt = 1, 17 do
            local lines = Picker.render(dialog, win.width - 2, win.height - 2, api.getIOClients())
            for y, line in ipairs(lines) do
                local x = line:find(label, 1, true)
                if x then
                    for _, hit in ipairs(dialog.hits) do
                        if hit.y == y and x >= hit.x1 and x <= hit.x2 then
                            bus.queue(display, {"monitor_touch", "top", win.x + x, win.y + y}); bus.pump(); return
                        end
                    end
                end
            end
            local nextHit
            for _, hit in ipairs(dialog.hits) do if hit.action == "next" then nextHit = hit end end
            if not nextHit then break end
            bus.queue(display, {"monitor_touch", "top", win.x + nextHit.x1, win.y + nextHit.y}); bus.pump()
            end
            error("Missing IO option: " .. label)
        end
        assert(api.pickIO(id, "playerInput", "input"))
        central.server.refreshMonitors(true); bus.pump()
        touchPicker("io_11")
        local choices = central.server.dialogs[id].hits
        for _, hit in ipairs(choices) do assert(hit.value ~= "right", "Modem side must not be offered") end
        touchPicker("left"); touchPicker("Next >"); touchPicker("red"); touchPicker("Use")
        equal(state.playerInput.clientId, "io_11")
        equal(state.playerInput.side, "left")
        equal(state.playerInput.color, 16384)
        equal(central.server.dialogs[id], nil)
        bridge.bundledInputs.left = 16384
        bus.queue(bridge, {"redstone"}); bus.pump()
        equal(api.readInput(state.playerInput), true)
        bridge.bundledInputs.left = 0
        bus.queue(bridge, {"redstone"}); bus.pump()
        equal(api.readInput(state.playerInput), false)
        assert(api.pickIO(id, "outputAddress", "output"))
        central.server.refreshMonitors(true); bus.pump()
        touchPicker("io_11"); touchPicker("front"); touchPicker("Digital"); touchPicker("Use")
        equal(state.outputAddress.side, "front")
        equal(state.outputAddress.color, nil)
        local win = central.server.state.windows[id]
        bus.queue(display, {"monitor_touch", "top", win.x + 1, win.y + win.height - 3}); bus.pump()
        equal(state.forced, true)
        bus.advance(1)
        equal(bridge.digital.front, true)
    end

    function tests.coffee_save_failure_blocks_new_output_until_checkpoint_recovers()
        local bus, central, bridge, app, state = coffee()
        shortTimers(app, state, central.server.api, 1, 10)
        central.disk.failWrite = true
        bus.advance(2)
        equal(state.phase, "countdown")
        equal(bridge.digital.front, false, "Never energize an uncommitted harvest")
        central.disk.failWrite = false
        bus.advance(2)
        equal(state.phase, "harvest")
        equal(bridge.digital.front, true)
        equal(unserialize(central.disk.files["configs_os_state.txt"]).appStates.coffee.phase, "harvest")
    end

    function tests.coffee_recovered_finished_harvest_does_not_pulse_output_again()
        local bus, central, bridge, app, state = coffee()
        local saved = unserialize(central.disk.files["configs_os_state.txt"])
        saved.appStates.coffee.phase = "harvest"
        saved.appStates.coffee.harvestRemaining = 0
        saved.appStates.coffee.forced = true
        saved.outputs.coffee_harvest = true
        local restoredBus, restored, outputBridge, restoredApp, restoredState = coffee({saved = saved, configure = false})
        restoredBus.advance(2)
        equal(restoredState.phase, "countdown")
        equal(restoredState.totalHarvests, 1)
        for _, write in ipairs(outputBridge.redstoneWrites) do
            assert(write.kind ~= "digital" or write.value == false, "Finished harvest must never be re-energized")
        end
    end

    function tests.coffee_force_is_idempotent_and_output_changes_pause_the_active_harvest()
        local bus, central, bridge, app, state = coffee()
        shortTimers(app, state, central.server.api, 100, 20)
        local context = {view = {}}
        press(app, state, central.server.api, context, "Harvest now")
        bus.pump(); bus.advance(3)
        local remaining = state.harvestRemaining
        press(app, state, central.server.api, context, "Harvest active")
        equal(state.harvestRemaining, remaining, "Repeated Force must not restart a harvest")
        assert(app.handleIOSelection("outputAddress", {clientId = "io_11", side = "bottom", color = 1},
            state, central.server.api))
        bus.pump(); bus.advance(2)
        equal(state.paused, true)
        equal(state.harvestRemaining, remaining)
        equal(bridge.digital.front, false)
        equal(bridge.bundled.bottom, 0, "A rewired active app waits for explicit Resume")
        press(app, state, central.server.api, context, "Resume")
        bus.pump(); bus.advance(2)
        equal(bridge.bundled.bottom, 1)
        assert(state.harvestRemaining < remaining)
        assert(central.server.api.mapOutput("other", "io_11", "back", 1))
        local ok = app.handleIOSelection("outputAddress", {clientId = "io_11", side = "back", color = 1},
            state, central.server.api)
        equal(ok, false)
        equal(state.outputAddress.side, "bottom", "Conflicting selections preserve existing app wiring")
    end

    function tests.coffee_settings_views_are_independent_on_different_monitors()
        local bus, central, bridge, app, state = coffee()
        local small, large = monitor(15, 10), monitor(50, 20)
        bus.computer(13, "monitor", {monitors = {top = small, left = large}}):start()
        local first = assert(central.server.api.openApp("coffee", "monitor_13:top"))
        local second = assert(central.server.api.openApp("coffee", "monitor_13:left"))
        central.server.refreshMonitors(true); bus.pump()
        local win = central.server.state.windows[first]
        local display = bus.computers[13]
        bus.queue(display, {"monitor_touch", "top", win.x + 1, win.y + win.height - 2}); bus.pump()
        equal(central.server.views[first].page, "actions")
        bus.queue(display, {"monitor_touch", "top", win.x + 1, win.y + 4}); bus.pump()
        equal(central.server.views[first].page, "settings")
        equal(central.server.views[second].page, nil)
        local before = state.remainingTime
        bus.advance(2)
        equal(state.remainingTime, before - 2, "Two windows share one background timer")
        for _, line in ipairs(small.lines) do assert(#line <= small.width) end
    end

    function tests.window_layout_and_app_data_checkpoint_with_old_thirty_second_configs()
        local bus, central, bridge, app, state = coffee({saveInterval = 30})
        local screen = monitor(50, 20)
        bus.computer(13, "monitor", {monitors = {top = screen}}):start()
        local id = assert(central.server.api.openApp("coffee", "monitor_13:top"))
        assert(central.server.api.placeWindow(id, 3, 4, 24, 10))
        central.server.state.windows[id].minimized = true
        -- This models an app background update without an explicit save call.
        central.server.state.appStates.coffee.tripHarvests = 17
        bus.advance(1)
        local saved = unserialize(central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.coffee.tripHarvests, 17)
        equal(saved.windows[id].minimized, true)
        central = bus.computer(10, "server", {disk = central.disk}):start()
        equal(central.server.state.windows[id].x, 3)
        equal(central.server.state.windows[id].y, 4)
        equal(central.server.state.windows[id].width, 24)
        equal(central.server.state.windows[id].height, 10)
        equal(central.server.state.windows[id].minimized, true)
        equal(central.server.state.appStates.coffee.tripHarvests, 17)
    end
end
