-- System settings, snap diagrams, move nudges and responsive app navigation.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local file = assert(io.open("apps_coffee.lua", "r"))
    local coffee = file:read("*a"); file:close()
    local function setup(withCoffee, width, height)
        local bus = newBus()
        local central = bus.computer(10, "server", {apps = withCoffee and {["apps_coffee.lua"] = coffee} or {}}):start()
        local top, left = monitor(width or 64, height or 24), monitor(45, 18)
        local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
        local t = {bus = bus, central = central, display = display, top = top, left = left, api = central.server.api}
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.touch(side, x, y) bus.queue(display, {"monitor_touch", side, x, y}); bus.pump() end
        function t.window(id) return t.central.server.state.windows[id] end
        function t.open(name, side, x, y, w, h)
            local id = assert(t.api.openApp(name, "monitor_13:" .. (side or "top"), x, y, w, h))
            t.paint(); return id
        end
        function t.click(id, action, value)
            t.paint()
            local win = t.window(id)
            local dialog = t.central.server.dialogs[id]
            local hits
            if dialog then hits = dialog.hits
            else
                local app = t.central.server.systemApps[win.appName] or t.central.server.apps[win.appName]
                local content = app.render(win.width - 2, win.height - 2, t.central.server.state.appStates[win.appName], t.api,
                    {windowId = id, appName = win.appName, monitorId = win.monitorId, view = t.central.server.views[id]})
                hits = content.hits
            end
            for _, hit in ipairs(hits or {}) do
                if hit.action == action and (value == nil or hit.value == value) then
                    t.touch(win.monitorId:match(":([^:]+)$"), win.x + hit.x1, win.y + (hit.y1 or hit.y)); return
                end
            end
            error("Missing action: " .. action)
        end
        function t.reboot()
            t.central = bus.computer(10, "server", {disk = t.central.disk}):start()
            t.api = t.central.server.api
            bus.advance(6); t.paint()
        end
        return t
    end

    function tests.appearance_os_settings_is_in_start_without_enabling_user_apps_and_survives_reboot()
        local t = setup(false)
        equal(t.top.lines[1], string.rep(" ", t.top.width), "Desktop has no branding")
        equal(next(t.central.server.apps), nil)
        t.touch("top", 2, t.top.height)
        local hit
        for _, item in ipairs(t.central.server.monitors["monitor_13:top"].menuHits) do
            if item.item and item.item.value == "@settings" then hit = item end
        end
        assert(hit, "OS settings must be available before installing apps")
        t.touch("top", hit.x1, hit.y)
        local id
        for key, win in pairs(t.central.server.state.windows) do if win.appName == "@settings" then id = key end end
        assert(id)
        t.click(id, "background")
        t.click(id, "colour", 128)
        equal(t.api.getOSSettings().backgroundColour, 128)
        equal(t.top.bg[20][60], 128); equal(t.left.bg[2][2], 128)
        local win = t.window(id)
        equal(t.top.bg[win.y][win.x], 32768, "A gray desktop gets a contrasting title bar")
        equal(next(t.central.server.state.appRegistry), nil)
        equal(next(unserialize(t.central.disk.files["configs_os.txt"]).enabledApps), nil)
        t.reboot()
        equal(t.api.getOSSettings().backgroundColour, 128)
        equal(t.window(id).appName, "@settings")
        equal(t.central.server.running["@settings"], true)
        equal(next(t.central.server.apps), nil)
        assert(t.api.closeWindow(id)); t.paint()
        equal(t.top.lines[1], string.rep(" ", t.top.width))
    end

    function tests.appearance_coffee_colour_is_shared_persistent_and_rolls_back_on_failed_save()
        local t = setup(true)
        local a, b = t.open("coffee"), t.open("coffee", "left")
        local state = t.central.server.state.appStates.coffee
        state.remainingTime = 1234
        local wiring = serialize(t.central.server.state.outputMap)
        t.click(a, "menu"); t.click(a, "settings"); t.click(a, "colour")
        t.click(a, "colour", 16384)
        equal(t.api.getAppColour("coffee"), 16384)
        for _, id in ipairs({a, b}) do
            local win = t.window(id)
            local screen = id == a and t.top or t.left
            equal(screen.bg[win.y + 1][win.x + 1], 16384)
            equal(screen.bg[win.y][win.x], 128)
        end
        t.click(a, "colour")
        t.central.disk.failWrite = true
        t.click(a, "colour", 8192)
        equal(t.api.getAppColour("coffee"), 16384)
        assert(t.central.server.dialogs[a].error)
        t.central.disk.failWrite = false
        t.click(a, "colour", 8192)
        equal(t.api.getAppColour("coffee"), 8192)
        equal(state.remainingTime, 1234); equal(serialize(t.central.server.state.outputMap), wiring)
        t.reboot()
        equal(t.api.getAppColour("coffee"), 8192)
        equal(t.central.server.state.appStates.coffee.remainingTime, 1234)
        local previous = t.api.getOSSettings().backgroundColour
        t.central.disk.failWrite = true
        equal(t.api.setBackgroundColour(2), false)
        equal(t.api.getOSSettings().backgroundColour, previous)
    end

    function tests.appearance_snap_flyout_has_clickable_diagrams_and_places_the_selected_pane()
        local t = setup(true, 81, 25)
        local id = t.open("coffee", "top", 3, 4, 32, 12)
        local function choose(mode)
            local win = t.window(id)
            t.touch("top", win.x + win.width - 5, win.y)
            local model = t.central.server.monitors["monitor_13:top"].layoutMenu
            local selected
            for _, hit in ipairs(model.menuHits) do if hit.item and hit.item.value == mode then selected = hit end end
            assert(selected)
            if mode == "right" then assert(selected.y2 > selected.y1, "Pane must be a clickable rectangle") end
            t.touch("top", selected.x2, selected.y2 or selected.y)
        end
        choose("right")
        equal(t.window(id).x, 41); equal(t.window(id).width, 41)
        choose("bottom_right")
        equal(t.window(id).x, 41); equal(t.window(id).y, 13)
        equal(t.window(id).width, 41); equal(t.window(id).height, 12)
        choose("restore"); equal(t.window(id).layout, "right")
    end

    function tests.appearance_move_preview_nudges_one_cell_hides_boundary_arrows_and_commits_only_on_ok()
        local t = setup(true, 40, 20)
        local id = t.open("coffee", "top", 3, 3, 20, 10)
        local win = t.window(id)
        t.touch("top", win.x + 1, win.y)
        t.touch("top", 10, 5)
        local p = t.central.server.monitors["monitor_13:top"].placement
        local function arrow(dx, dy)
            for _, hit in ipairs(p.hits) do if hit.dx == dx and hit.dy == dy then t.touch("top", hit.x1, hit.y); return end end
            error("Missing nudge arrow")
        end
        arrow(1, 0); equal(p.preview.x, 11); equal(p.preview.y, 5)
        arrow(0, -1); equal(p.preview.y, 4)
        equal(win.x, 3); equal(win.y, 3)
        for _ = 1, 10 do arrow(-1, 0) end
        for _ = 1, 3 do arrow(0, -1) end
        equal(p.preview.x, 1); equal(p.preview.y, 1)
        for _, hit in ipairs(p.hits) do assert(hit.dx ~= -1 and hit.dy ~= -1, "Boundary arrows must disappear") end
        t.touch("top", 10, 5)
        equal(p.preview.x, 1); equal(p.preview.y, 1, "An empty-area tap must not jump a positioned preview")
        local place
        for _, hit in ipairs(p.hits) do if hit.action == "place" then place = hit end end
        t.touch("top", place.x1, place.y)
        equal(p.preview, nil)
        t.touch("top", 39, 18)
        equal(p.preview.x, 21); equal(p.preview.y, 10)
        for _, hit in ipairs(p.hits) do assert(hit.dx ~= 1 and hit.dy ~= 1, "Right and bottom arrows must disappear") end
        t.touch("top", 2, t.top.height)
        equal(t.window(id).x, 21); equal(t.window(id).y, 10)
        t.reboot()
        equal(t.window(id).x, 21); equal(t.window(id).y, 10)
    end

    function tests.appearance_all_palette_colours_keep_titles_and_coffee_text_readable()
        local t = setup(true)
        local id = t.open("coffee")
        local win = t.window(id)
        for index = 0, 15 do
            local bg, accent = 2 ^ index, 2 ^ ((index + 5) % 16)
            assert(t.api.setBackgroundColour(bg)); assert(t.api.setAppColour("coffee", accent)); t.paint()
            assert(t.top.bg[win.y][win.x] ~= bg)
            assert(t.top.fg[win.y + 1][win.x + 1] ~= t.top.bg[win.y + 1][win.x + 1])
            assert(t.top.fg[win.y + 2][win.x + 1] ~= t.top.bg[win.y + 2][win.x + 1])
        end
    end

    function tests.appearance_coffee_layout_matrix_has_no_overlapping_controls_or_duplicate_menu_paths()
        local t = setup(true)
        local app, state = t.central.server.apps.coffee, t.central.server.state.appStates.coffee
        state.remainingTime = 604800 -- Three-digit hours must fit the graphical clock too.
        local parents = {menu = "main", settings = "menu", maintenance = "menu", stats = "menu", duration = "settings", reset = "maintenance", import = "maintenance"}
        for _, width in ipairs({12, 16, 24, 30, 32, 36, 50, 62}) do
            for _, height in ipairs({6, 7, 8, 10, 14, 18, 20, 21}) do
                for _, page in ipairs({"main", "menu", "settings", "maintenance", "stats", "duration", "reset", "import"}) do
                    local context = {appName = "coffee", view = {page = page, field = "countdown", draft = 604800, step = 3}}
                    local lines = app.render(width, height, state, t.api, context)
                    equal(#lines, height)
                    for _, line in ipairs(lines) do equal(#line, width) end
                    local actions = {}
                    for index, hit in ipairs(lines.hits) do
                        assert(hit.x1 >= 1 and hit.x2 <= width and hit.y >= 1 and hit.y <= height)
                        actions[hit.action] = (actions[hit.action] or 0) + 1
                        for other = index + 1, #lines.hits do
                            local h = lines.hits[other]
                            assert(hit.y ~= h.y or hit.x2 < h.x1 or h.x2 < hit.x1, "Controls overlap on " .. page)
                        end
                    end
                    for _, style in ipairs(lines.styles) do
                        assert(style.x >= 1 and style.y >= 1 and style.x + style.width - 1 <= width
                            and style.y + style.height - 1 <= height, "Style escapes " .. page)
                    end
                    if parents[page] then equal(actions[parents[page]], 1, "Back/Cancel must return to the correct parent") end
                    if page == "main" then
                        equal(actions.pause, 1); equal(actions.force, 1); equal(actions.menu, 1)
                        equal(actions.settings, nil); equal(actions.stats, nil)
                    elseif page == "settings" then
                        equal(actions.stats, nil); equal(actions.reset, nil); equal(actions.import, nil)
                    end
                end
            end
        end
    end
end
