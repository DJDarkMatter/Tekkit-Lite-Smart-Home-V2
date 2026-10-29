-- Real server/monitor integration checks for the bottom taskbar and touch layouts.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local Desktop = dofile("lib_desktop.lua")
    local paneSource = [[return {minWidth=8,minHeight=2,preferredWidth=20,preferredHeight=8,
        init=function(s) s.starts=(s.starts or 0)+1; s.ticks=s.ticks or 0; s.touches=s.touches or 0 end,
        background=function(dt,s) s.ticks=s.ticks+dt end,
        shutdown=function(s) s.stops=(s.stops or 0)+1 end,
        render=function(w,h,s) return {"Pane",tostring(s.ticks)} end,
        handleTouch=function(x,y,w,h,s) s.touches=s.touches+1; return true end}]]
    local serviceSource = [[return {backgroundService=true,minWidth=8,minHeight=2,
        init=function(s) s.ticks=s.ticks or 0 end,background=function(dt,s) s.ticks=s.ticks+dt end,
        render=function() return {"Service"} end}]]
    local function setup(width, height, options)
        options = options or {}
        local bus = newBus()
        local sources = {["apps_pane.lua"] = paneSource, ["apps_service.lua"] = serviceSource}
        if options.coffee then
            local f = assert(io.open("apps_coffee.lua", "r")); sources["apps_coffee.lua"] = f:read("*a"); f:close()
        end
        local central = bus.computer(10, "server", {apps = sources}):start()
        local top, left = monitor(width or 60, height or 22), monitor(45, 18)
        local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
        local test = {bus = bus, central = central, display = display, top = top, left = left, api = central.server.api}
        function test.paint() central.server.refreshMonitors(true); bus.pump() end
        function test.touch(side, x, y) bus.queue(display, {"monitor_touch", side, x, y}); bus.pump() end
        function test.open(name, side, x, y, w, h)
            local id = assert(test.api.openApp(name or "pane", "monitor_13:" .. (side or "top"), x, y, w, h))
            test.paint(); return id
        end
        function test.window(id) return central.server.state.windows[id] end
        function test.model(side) return central.server.monitors["monitor_13:" .. (side or "top")] end
        function test.task(action, side, id)
            side = side or "top"; test.paint()
            for _, hit in ipairs(test.model(side).taskbar) do
                if hit.action == action and (not id or hit.id == id) then
                    test.touch(side, hit.x1, (side == "top" and top or left).height); return
                end
            end
            error("Taskbar control missing: " .. action)
        end
        function test.layout(id, mode)
            local win = test.window(id)
            local side = win.monitorId:match(":([^:]+)$")
            test.paint(); test.touch(side, win.x + win.width - 5, win.y)
            local grid = Desktop.gridForMode(mode)
            for _ = 1, 10 do
                local model = assert(test.model(side).layoutMenu)
                local chosen
                for _, hit in ipairs(model.menuHits) do
                    if hit.action == "item" and hit.item.value == mode then test.touch(side, hit.x1, hit.y); return end
                    if not model.grid and grid and hit.item and hit.item.value == "choose_" .. grid then chosen = hit end
                end
                if chosen then
                    test.touch(side, chosen.x1, chosen.y)
                    if chosen.item.enabled == false then return end
                else
                    local nextHit
                    for _, hit in ipairs(model.menuHits) do if hit.action == "next" then nextHit = hit end end
                    assert(nextHit, "Layout choice missing: " .. mode)
                    test.touch(side, nextHit.x1, nextHit.y)
                end
            end
            error("Layout pagination did not reach " .. mode)
        end
        return test
    end

    function tests.desktop_taskbar_is_bottom_with_title_left_and_controls_top_right()
        local t = setup()
        local id = t.open()
        local win = t.window(id)
        equal(t.top.lines[win.y]:sub(win.x, win.x + 3), "pane")
        equal(t.top.lines[win.y]:sub(win.x + win.width - 9, win.x + win.width - 1), " -  +  X ")
        equal(t.top.lines[t.top.height]:sub(1, 3), "[+]")
        assert(t.top.lines[t.top.height]:find("pane", 1, true))
        t.touch("top", win.x + win.width - 8, win.y)
        equal(win.minimized, true)
        t.task("window", "top", id)
        equal(win.minimized, false)
        t.touch("top", win.x + win.width - 2, win.y)
        equal(t.window(id), nil)
        equal(t.central.server.running.pane, nil)
    end

    function tests.desktop_last_view_stops_normal_apps_but_not_background_services()
        local t = setup()
        local state = t.central.server.state.appStates
        equal(t.central.server.running.pane, nil)
        equal(state.pane.starts, nil, "Ordinary apps do not initialize with no views")
        t.bus.advance(1)
        equal(state.service.ticks, 1)
        local a, b = t.open("pane", "top"), t.open("pane", "left")
        equal(state.pane.starts, 1, "All views share one running app")
        t.bus.advance(1)
        local first = t.window(a)
        t.touch("top", first.x + first.width - 2, first.y)
        equal(t.window(a), nil)
        assert(t.window(b))
        t.bus.advance(1)
        equal(state.pane.ticks, 2)
        assert(t.api.mapOutput("lamp", "io_missing", "left", 1))
        assert(t.api.setOutput("lamp", true))
        local second = t.window(b)
        t.touch("left", second.x + second.width - 2, second.y)
        equal(t.central.server.running.pane, nil)
        equal(state.pane.stops, 1)
        t.bus.advance(2)
        equal(state.pane.ticks, 2, "Last close stops the app's background hook")
        equal(t.api.getOutput("lamp"), true, "Closing a UI must not clear latched IO")
        local service = t.open("service")
        assert(t.api.closeWindow(service))
        local before = state.service.ticks
        t.bus.advance(1)
        equal(state.service.ticks, before + 1)
        t.open("pane")
        equal(state.pane.starts, 2)
    end

    function tests.desktop_taskbar_overflow_arrows_reach_every_window_in_stable_order()
        local t = setup(24, 18)
        local ids = {}
        for _ = 1, 9 do ids[#ids + 1] = t.open() end
        t.task("previous")
        while t.central.server.state.desktops["monitor_13:top"].scroll > 1 do t.task("previous") end
        local seen = {}
        for _ = 1, 10 do
            for _, hit in ipairs(t.model().taskbar) do if hit.action == "window" then seen[hit.id] = true end end
            local nextHit
            for _, hit in ipairs(t.model().taskbar) do if hit.action == "next" then nextHit = hit end end
            if not nextHit then break end
            t.touch("top", nextHit.x1, t.top.height)
        end
        for _, id in ipairs(ids) do assert(seen[id], "An overflowed window is unreachable") end
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        assert(saved.desktops["monitor_13:top"].scroll > 1)
        equal(t.top.lines[t.top.height]:sub(1, 3), "[+]")
    end

    function tests.desktop_snap_maximize_restore_and_resolution_polling_keep_geometry()
        local t = setup(81, 25)
        local id = t.open("pane", "top", 3, 4, 25, 10)
        t.layout(id, "right")
        local win = t.window(id)
        equal(win.x, 41); equal(win.width, 41); equal(win.y, 1); equal(win.height, 24)
        t.layout(id, "maximize")
        equal(win.x, 1); equal(win.width, 81); equal(win.height, 24)
        assert(t.api.layoutWindow(id, "maximize")) -- Repeated taps must retain the restore target.
        t.layout(id, "restore")
        equal(win.layout, "right"); equal(win.x, 41)
        t.layout(id, "restore")
        equal(win.layout, "normal"); equal(win.x, 3); equal(win.y, 4); equal(win.width, 25); equal(win.height, 10)
        t.layout(id, "right")
        t.top.width, t.top.height = 101, 31
        -- No monitor_resize event: the bridge must discover it on its own.
        t.bus.advance(1)
        equal(t.model().width, 101); equal(t.model().height, 31)
        equal(win.x, 51); equal(win.width, 51); equal(win.height, 30)
        t.layout(id, "restore")
        equal(win.layout, "normal"); equal(win.width, 31); equal(win.height, 13)
        assert(win.y + win.height <= t.top.height)
    end

    function tests.desktop_small_screens_disable_layouts_that_cannot_fit()
        local t = setup(15, 10, {coffee = true})
        local id = t.open("coffee")
        local win = t.window(id)
        local original = {x = win.x, y = win.y, width = win.width, height = win.height}
        t.layout(id, "left")
        equal(win.x, original.x); equal(win.width, original.width)
        assert(t.model().layoutMenu, "Disabled layout must not close the menu or alter the window")
        equal(t.model().layoutMenu.error, "Does not fit")
        local ok = t.api.layoutWindow(id, "left")
        equal(ok, false)
        t.touch("top", 15, 1) -- dismiss the popup outside its item buttons
        t.layout(id, "maximize")
        equal(win.width, 15); equal(win.height, 9)
        assert(t.top.lines[10]:find("[+]", 1, true))
    end

    function tests.desktop_custom_area_previews_cancel_validate_and_save_without_app_touches()
        local t = setup(60, 24)
        local id = t.open("pane", "top", 1, 1, 22, 10)
        local win = t.window(id)
        t.layout(id, "custom")
        t.touch("top", 10, 4); t.touch("top", 39, 15)
        equal(t.model().placement.preview.width, 30)
        equal(t.top.bg[5][10], 32, "Valid resize previews have a coloured outline")
        equal(win.width, 22, "Preview must not move the live window")
        t.touch("top", 6, t.top.height)
        equal(t.model().placement, nil); equal(win.width, 22)
        t.layout(id, "custom")
        t.touch("top", 12, 5); t.touch("top", 14, 7)
        equal(t.model().placement.valid, false)
        equal(t.top.bg[6][12], 16384, "Invalid resize previews are red")
        t.touch("top", 2, t.top.height)
        equal(win.width, 22)
        t.touch("top", 41, 17)
        equal(t.model().placement.valid, true)
        t.central.disk.failWrite = true
        t.touch("top", 2, t.top.height)
        equal(t.window(id).width, 22, "Failed saves preserve the previous geometry")
        assert(t.model().placement.error)
        t.central.disk.failWrite = false
        t.touch("top", 2, t.top.height)
        win = t.window(id)
        equal(t.model().placement, nil)
        equal(win.x, 12); equal(win.y, 5); equal(win.width, 30); equal(win.height, 13)
        equal(t.central.server.state.appStates.pane.touches, 0, "Placement taps must not reach the app")
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.windows[id].width, 30)
    end

    function tests.desktop_title_move_uses_one_destination_and_keeps_size_inside_desktop()
        local t = setup(60, 24)
        local id = t.open("pane", "top", 1, 1, 30, 10)
        local win = t.window(id)
        t.touch("top", win.x + 1, win.y)
        equal(t.model().placement.kind, "move")
        t.touch("top", 58, 22)
        t.touch("top", 2, t.top.height)
        equal(win.x, 31); equal(win.y, 14); equal(win.width, 30); equal(win.height, 10)
        equal(win.y + win.height - 1, 23, "Moving cannot cover the taskbar")
    end

    function tests.desktop_snap_modes_and_minimized_views_restore_after_server_restart()
        local t = setup(60, 24)
        local a, b = t.open("pane", "top"), t.open("pane", "left")
        t.layout(a, "left"); t.layout(b, "bottom")
        local win = t.window(a)
        t.touch("top", win.x + win.width - 8, win.y)
        local disk = t.central.disk
        local restarted = t.bus.computer(10, "server", {disk = disk}):start()
        t.bus.advance(6)
        equal(restarted.server.state.windows[a].layout, "left")
        equal(restarted.server.state.windows[a].minimized, true)
        equal(restarted.server.state.windows[b].layout, "bottom")
        equal(restarted.server.state.windows[b].y, 9)
        equal(restarted.server.running.pane, true)
        assert(restarted.server.state.desktopVersion == 2)
    end

    function tests.desktop_coffee_has_compact_and_detailed_views_sharing_one_saved_timer()
        local t = setup(80, 25, {coffee = true})
        t.left.width, t.left.height = 15, 10
        t.bus.advance(1)
        local small = t.open("coffee", "left")
        local big = t.open("coffee", "top")
        local state = t.central.server.state.appStates.coffee
        state.remainingTime = 1234
        t.paint()
        assert(table.concat(t.left.lines, "\n"):find("Menu", 1, true))
        assert(table.concat(t.left.lines, "\n"):find("Pause", 1, true))
        assert(not table.concat(t.left.lines, "\n"):find("Countdown:", 1, true))
        t.layout(big, "maximize")
        assert(table.concat(t.top.lines, "\n"):find("TRIP / TOTAL", 1, true))
        assert(not table.concat(t.top.lines, "\n"):find("Input:", 1, true), "Wiring belongs in Settings")
        assert(table.concat(t.top.lines, "\n"):find("Pause", 1, true))
        assert(t.api.closeWindow(small)); assert(t.api.closeWindow(big))
        t.bus.advance(2)
        equal(state.remainingTime, 1234)
        equal(t.central.server.running.coffee, true)
    end

    function tests.desktop_gui_draws_colour_panels_buttons_and_colour_only_updates()
        local t = setup(60, 24, {coffee = true})
        local id = t.open("coffee")
        local win = t.window(id)
        equal(t.top.bg[win.y][win.x], 128, "Title contrasts with the blue desktop")
        equal(t.top.bg[win.y][win.x + win.width - 2], 16384, "Close is red at the far right")
        equal(t.top.lines[win.y]:sub(win.x, win.x + 5), "Coffee")
        equal(t.top.bg[win.y + 1][win.x + 1], 2048, "App heading is a filled panel")
        local content = t.central.server.apps.coffee.render(win.width - 2, win.height - 2, t.central.server.state.appStates.coffee, t.api,
            {view = t.central.server.views[id] or {}})
        local pause
        for _, hit in ipairs(content.hits) do if hit.action == "pause" then pause = hit end end
        assert(pause)
        local buttonY = win.y + pause.y
        assert(t.top.lines[buttonY]:find("Pause", 1, true))
        equal(t.top.bg[buttonY][win.x + 1], 2048)
        t.touch("top", win.x + pause.x2, buttonY) -- The padded button edge is clickable.
        equal(t.central.server.state.appStates.coffee.paused, true)
        assert(t.top.lines[buttonY]:find("Resume", 1, true))
        local pane = t.open("pane", "left")
        local p = t.window(pane)
        local colour = 2048
        t.central.server.apps.pane.render = function()
            return {"Same text", styles = {{x = 1, y = 1, width = 8, bg = colour}}}
        end
        t.paint()
        local oldText, oldWrites = t.left.lines[p.y + 1], t.left.writes
        colour = 16384
        t.central.server.refreshMonitors(false); t.bus.pump()
        equal(t.left.lines[p.y + 1], oldText)
        equal(t.left.bg[p.y + 1][p.x + 1], 16384)
        assert(t.left.writes > oldWrites, "A colour-only change must repaint")
        t.top.colour = false
        t.display.client.scan(); t.paint()
        equal(t.top.bg[win.y][win.x], 32768, "Standard monitors get a readable monochrome fallback")
    end

    local function wirePicker()
        local t = setup(30, 16, {coffee = true})
        t.bus.computer(11, "io"):start()
        local id = t.open("coffee", "top", 4, 3, 18, 9)
        assert(t.api.pickIO(id, "playerInput", "input")); t.paint()
        function t.pick(action, value)
            for _, hit in ipairs(t.central.server.dialogs[id].hits) do
                if hit.action == action and (value == nil or hit.value == value) then
                    local win = t.window(id)
                    t.touch("top", win.x + hit.x2, win.y + hit.y); return
                end
            end
            error("Picker action missing: " .. action)
        end
        t.pick("select", "io_11"); t.pick("select", "left")
        return t, id, t.central.server.dialogs[id]
    end

    function tests.desktop_wire_paging_stays_monotonic_across_announcements_and_at_boundaries()
        local t, id, dialog = wirePicker()
        equal(dialog.stage, 3)
        local slots, pages = t.window(id).height - 5, math.ceil(17 / (t.window(id).height - 5))
        equal(slots, 4)
        for page = 2, pages do
            t.pick("next"); equal(dialog.page, page)
            t.bus.advance(6)
            equal(dialog.page, page, "Announcements and background repaints cannot reset paging")
        end
        for _ = 1, 8 do t.pick("next"); equal(dialog.page, pages) end
        for page = pages - 1, 1, -1 do t.pick("prev"); equal(dialog.page, page) end
        for _ = 1, 8 do t.pick("prev"); equal(dialog.page, 1) end
        local win = t.window(id)
        equal(t.top.bg[win.y + 3][win.x + 1], 1, "White wire has a white swatch")
    end

    function tests.desktop_repeated_stale_taps_do_not_skip_pages_or_apply_actions_twice()
        local t, id, dialog = wirePicker()
        local win, nextHit = t.window(id)
        for _, hit in ipairs(dialog.hits) do if hit.action == "next" then nextHit = hit end end
        for _ = 1, 4 do t.bus.queue(t.display, {"monitor_touch", "top", win.x + nextHit.x1, win.y + nextHit.y}) end
        t.bus.pump()
        equal(dialog.page, 2, "Only the first tap on an outdated displayed page should apply")
        local packet
        for _, item in ipairs(t.bus.wire) do if item.sender.id == 13 and item.message.type == "touch" then packet = item end end
        for _ = 1, 3 do t.bus.queue(t.central, {"modem_message", t.central.modemSide, 45231, packet.reply, packet.raw, 12}) end
        t.bus.pump(); equal(dialog.page, 2)
        t.pick("next"); equal(dialog.page, 3, "A fresh tap works after the reply")
    end

    function tests.desktop_monitor_rejects_old_frames_and_recovers_a_lost_touch_reply()
        local t, id, dialog = wirePicker()
        local previous
        for _, item in ipairs(t.bus.wire) do if item.message.type == "render" and item.message.clientId == "monitor_13:top" then previous = item end end
        t.pick("next")
        local current = table.concat(t.top.lines, "\n")
        t.bus.queue(t.display, {"modem_message", t.display.modemSide, previous.channel, previous.reply, previous.raw, 12})
        t.bus.pump(); equal(table.concat(t.top.lines, "\n"), current, "An old frame cannot move the visible page backwards")
        local dropped = false
        t.bus.drop = function(packet)
            if not dropped and packet.message.type == "render" and packet.message.clientId == "monitor_13:top" then dropped = true; return true end
        end
        t.pick("next"); equal(dialog.page, 3)
        t.pick("next"); equal(dialog.page, 3, "A tap from the old screen recovers the missing reply")
        t.pick("next"); equal(dialog.page, 4)
        t.bus.drop = nil
    end

    function tests.desktop_maximum_size_colour_frames_fit_the_legacy_modem_limit()
        local t = setup(256, 128)
        local id = t.open()
        assert(t.api.layoutWindow(id, "maximize")); t.paint()
        equal(t.top.bg[127][1], 128)
        equal(t.top.bg[128][1], 2048)
        for _, packet in ipairs(t.bus.wire) do assert(#packet.raw <= 65536) end
    end

    function tests.desktop_buffers_monitor_touches_while_native_drawing_waits()
        local t, id, dialog = wirePicker()
        local blocked, first = false, true
        t.top.beforeWrite = function()
            if first then
                first, blocked = false, true
                t.display.env.os.pullEvent("monitor_write_done")
            end
        end
        t.display.client.devices.top.cache = {}
        t.paint()
        equal(blocked, true)
        local win, hit = t.window(id)
        for _, item in ipairs(dialog.hits) do if item.action == "next" then hit = item end end
        t.bus.queue(t.display, {"monitor_touch", "top", win.x + hit.x1, win.y + hit.y})
        t.bus.pump()
        equal(dialog.page, 1, "Touch waits while the native write is suspended")
        t.bus.queue(t.display, {"monitor_write_done"}); t.bus.pump()
        equal(dialog.page, 2, "The queued touch must survive a yielding peripheral call")
    end

    function tests.desktop_touch_calibration_persists_and_corrects_real_bridge_coordinates()
        local bus = newBus()
        local screen = monitor(40, 18)
        local display = bus.computer(13, "monitor", {monitors = {top = screen}})
        local work = coroutine.create(function() assert(display.env.loadfile("clients_monitor_client.lua"))("calibrate", "top") end)
        local ok, event = coroutine.resume(work)
        assert(ok, event); equal(event, nil)
        for _, point in ipairs({{10, 4}, {30, 9}, {20, 13}}) do
            ok, event = coroutine.resume(work, "monitor_touch", "top", point[1] + 1, point[2] + 1)
            assert(ok, event)
        end
        equal(coroutine.status(work), "dead")
        local config = unserialize(display.disk.files["configs_monitor.txt"])
        equal(config.touchOffsets.top.x, -1); equal(config.touchOffsets.top.y, -1)
        local central = bus.computer(10, "server", {apps = {["apps_pane.lua"] = paneSource}}):start()
        display = bus.computer(13, "monitor", {disk = display.disk, monitors = {top = screen}}):start()
        local id = assert(central.server.api.openApp("pane", "monitor_13:top", 4, 3, 25, 10))
        central.server.refreshMonitors(true); bus.pump()
        local win = central.server.state.windows[id]
        -- The native driver reports a point one row/column below the drawn target.
        bus.queue(display, {"monitor_touch", "top", win.x + win.width - 1, win.y + 1}); bus.pump()
        equal(central.server.state.windows[id], nil, "Calibration maps the visible close button back to its exact cell")
    end

    local function calibration(previous)
        local bus, screen = newBus(), monitor(40, 18)
        local display = bus.computer(13, "monitor", {monitors = {top = screen}})
        if previous then display.disk.files["configs_monitor.txt"] = serialize({clientId = "keep", textScale = 0.5,
            announceInterval = 5, timeout = 15, touchOffsets = {top = previous, left = {x = 0, y = 2}}}) end
        local work = coroutine.create(function() assert(display.env.loadfile("clients_monitor_client.lua"))("calibrate", "top") end)
        local ok, event = coroutine.resume(work); assert(ok, event)
        local function resume(...)
            local success, err = coroutine.resume(work, ...); assert(success, err)
        end
        local function sample(index, dx, dy)
            local target = ({{10, 4}, {30, 9}, {20, 13}})[index]
            resume("monitor_touch", "top", target[1] - dx, target[2] - dy)
        end
        return display, screen, work, sample, resume
    end

    function tests.desktop_calibration_collects_all_samples_and_tolerates_one_cell_tap_variation()
        local display, screen, work, sample, resume = calibration({x = 0, y = 0})
        sample(1, -1, -1)
        resume("monitor_touch", "top", 11, 5) -- Queued repeat of the old first target.
        assert(screen.lines[1]:find("2/3", 1, true), "Old-target touches must not count for the next target")
        sample(2, -2, -1)
        equal(coroutine.status(work), "suspended", "The second differing tap must not terminate calibration")
        assert(screen.lines[1]:find("3/3", 1, true))
        sample(3, -1, -2)
        equal(coroutine.status(work), "dead")
        local saved = unserialize(display.disk.files["configs_monitor.txt"])
        equal(saved.touchOffsets.top.x, -1); equal(saved.touchOffsets.top.y, -1)
        equal(saved.touchOffsets.left.y, 2)
        assert(screen.lines[1]:find("Calibration saved", 1, true))
    end

    function tests.desktop_calibration_inconsistent_samples_offer_retry_without_replacing_the_old_offset()
        local display, screen, work, sample, resume = calibration({x = 2, y = 1})
        local previous = display.disk.files["configs_monitor.txt"]
        sample(1, -3, 0); sample(2, 0, 0); sample(3, 3, 0)
        equal(coroutine.status(work), "suspended")
        equal(display.disk.files["configs_monitor.txt"], previous)
        assert(screen.lines[1]:find("needs retry", 1, true)); assert(screen.lines[17]:find("Retry", 1, true))
        resume("monitor_touch", "top", 4, 17)
        assert(screen.lines[1]:find("1/3", 1, true))
        sample(1, 0, -1); sample(2, 0, -1); sample(3, 0, -1)
        equal(coroutine.status(work), "dead")
        local saved = unserialize(display.disk.files["configs_monitor.txt"])
        equal(saved.touchOffsets.top.x, 0); equal(saved.touchOffsets.top.y, -1)
    end

    function tests.desktop_calibration_rejects_excessive_offsets_and_cancel_keeps_previous_settings()
        local display, screen, work, sample, resume = calibration({x = 1, y = -1})
        local previous = display.disk.files["configs_monitor.txt"]
        sample(1, 4, 0); sample(2, 4, 0); sample(3, 4, 0)
        equal(coroutine.status(work), "suspended")
        assert(screen.lines[1]:find("needs retry", 1, true))
        resume("char", "c")
        equal(coroutine.status(work), "dead")
        equal(display.disk.files["configs_monitor.txt"], previous)
        assert(screen.lines[1]:find("cancelled", 1, true))
    end

    function tests.desktop_calibration_failed_save_keeps_the_previous_offset_and_reports_failure()
        local display, screen, work, sample = calibration({x = 1, y = -1})
        local previous = display.disk.files["configs_monitor.txt"]
        display.disk.failWrite = true
        sample(1, -1, 0); sample(2, -1, 0); sample(3, -1, 0)
        equal(coroutine.status(work), "dead")
        equal(display.disk.files["configs_monitor.txt"], previous)
        assert(table.concat(display.log, "\n"):find("Cannot save calibration", 1, true))
        assert(screen.lines[1]:find("not saved", 1, true))
    end

    function tests.desktop_coffee_settings_paging_is_bounded_and_per_window()
        local t = setup(30, 16, {coffee = true})
        local a = t.open("coffee", "top", 3, 2, 16, 8)
        local b = t.open("coffee", "left", 3, 2, 16, 8)
        local function press(id, label)
            local win = t.window(id)
            local side = win.monitorId:match(":([^:]+)$")
            t.paint()
            for row = win.y + 1, win.y + win.height - 2 do
                local x = (side == "top" and t.top or t.left).lines[row]:find(label, win.x + 1, true)
                if x then t.touch(side, x, row); return end
            end
            error("Missing settings control " .. label)
        end
        for _, id in ipairs({a, b}) do press(id, "Menu"); press(id, "Settings") end
        local va, vb = t.central.server.views[a], t.central.server.views[b]
        press(a, "Next >"); equal(va.settingsPage, 2)
        for _ = 1, 5 do press(a, "Next >"); equal(va.settingsPage, 2) end
        equal(vb.settingsPage, 1)
        press(a, "< Prev"); equal(va.settingsPage, 1)
        for _ = 1, 5 do press(a, "< Prev"); equal(va.settingsPage, 1) end
    end
end
