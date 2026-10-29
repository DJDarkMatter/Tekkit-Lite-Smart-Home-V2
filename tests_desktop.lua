-- Real server/monitor integration checks for the bottom taskbar and touch layouts.
return function(tests, newBus, monitor, serialize, unserialize, equal)
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
            test.paint(); test.touch(side, win.x + 4, win.y)
            for _ = 1, 10 do
                local model = assert(test.model(side).layoutMenu)
                for _, hit in ipairs(model.menuHits) do
                    if hit.action == "item" and hit.item.value == mode then test.touch(side, hit.x1, hit.y); return end
                end
                local nextHit
                for _, hit in ipairs(model.menuHits) do if hit.action == "next" then nextHit = hit end end
                assert(nextHit, "Layout choice missing: " .. mode)
                test.touch(side, nextHit.x1, nextHit.y)
            end
            error("Layout pagination did not reach " .. mode)
        end
        return test
    end

    function tests.desktop_taskbar_is_bottom_and_title_controls_are_top_left()
        local t = setup()
        local id = t.open()
        local win = t.window(id)
        equal(t.top.lines[win.y]:sub(win.x, win.x + 8), "[X][#][_]")
        equal(t.top.lines[t.top.height]:sub(1, 3), "[+]")
        assert(t.top.lines[t.top.height]:find("pane", 1, true))
        t.touch("top", win.x + 7, win.y)
        equal(win.minimized, true)
        t.task("window", "top", id)
        equal(win.minimized, false)
        t.touch("top", win.x + 1, win.y)
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
        t.touch("top", first.x + 1, first.y)
        equal(t.window(a), nil)
        assert(t.window(b))
        t.bus.advance(1)
        equal(state.pane.ticks, 2)
        assert(t.api.mapOutput("lamp", "io_missing", "left", 1))
        assert(t.api.setOutput("lamp", true))
        local second = t.window(b)
        t.touch("left", second.x + 1, second.y)
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
        equal(win.width, 22, "Preview must not move the live window")
        t.touch("top", 6, t.top.height)
        equal(t.model().placement, nil); equal(win.width, 22)
        t.layout(id, "custom")
        t.touch("top", 12, 5); t.touch("top", 14, 7)
        equal(t.model().placement.valid, false)
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
        t.touch("top", win.x + 10, win.y)
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
        t.touch("top", win.x + 7, win.y)
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
        assert(not table.concat(t.left.lines, "\n"):find("Pause", 1, true))
        t.layout(big, "maximize")
        assert(table.concat(t.top.lines, "\n"):find("Countdown:", 1, true))
        assert(table.concat(t.top.lines, "\n"):find("Pause", 1, true))
        assert(t.api.closeWindow(small)); assert(t.api.closeWindow(big))
        t.bus.advance(2)
        equal(state.remainingTime, 1234)
        equal(t.central.server.running.coffee, true)
    end
end
