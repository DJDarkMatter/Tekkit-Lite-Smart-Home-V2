-- System settings, snap diagrams, move nudges and responsive app navigation.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local Desktop = dofile("lib_desktop.lua")
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
        equal(t.top.bg[win.y][win.x], 128, "Changing the desktop must not override the selected window-border colour")
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

    function tests.appearance_snap_flyout_chooses_grid_before_position_and_keeps_resize_move_on_root()
        local t = setup(true, 81, 25)
        local id = t.open("coffee", "top", 3, 4, 32, 12)
        local function choose(mode)
            local win = t.window(id)
            t.touch("top", win.x + win.width - 5, win.y)
            local model = t.central.server.monitors["monitor_13:top"].layoutMenu
            if Desktop.gridForMode(mode) then
                local choice
                for _, hit in ipairs(model.menuHits) do
                    if hit.item and hit.item.value == "choose_" .. Desktop.gridForMode(mode) then choice = hit end
                end
                assert(choice)
                local previous = serialize(t.window(id))
                local root = {}
                for _, hit in ipairs(model.menuHits) do if hit.item then root[hit.item.value] = true end end
                assert(root.custom and root.move and root.restore, "Resize/Move/Restore must stay at the first level")
                t.touch("top", choice.x2, choice.y2 or choice.y)
                equal(serialize(t.window(id)), previous, "Picking a grid alone must not change geometry")
                for _, hit in ipairs(model.menuHits) do
                    assert(not hit.item or (hit.item.value ~= "custom" and hit.item.value ~= "move"), "Position screen contains only panes and navigation")
                end
            end
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

    function tests.appearance_three_by_three_partitions_odd_desktops_and_restores_after_resize_and_reboot()
        local t = setup(true, 83, 26)
        local id = t.open("coffee", "top", 3, 4, 32, 12)
        local function chooseGrid()
            local win = t.window(id)
            t.touch("top", win.x + win.width - 5, win.y)
            local model = t.central.server.monitors["monitor_13:top"].layoutMenu
            for _, hit in ipairs(model.menuHits) do
                if hit.item and hit.item.value == "choose_3x3" then t.touch("top", hit.x1, hit.y); return model end
            end
            error("3x3 grid missing")
        end
        local covered = {}
        for row = 1, 3 do for column = 1, 3 do
            local model = chooseGrid()
            local mode = Desktop.gridMode(3, 3, column, row)
            local hit
            for _, item in ipairs(model.menuHits) do if item.item and item.item.value == mode then hit = item end end
            assert(hit and hit.item.enabled)
            t.touch("top", hit.x2, hit.y2 or hit.y)
            local win, zone = t.window(id), Desktop.zone(mode, {width = 83, height = 26})
            equal(win.x, zone.x); equal(win.y, zone.y); equal(win.width, zone.width); equal(win.height, zone.height)
            for y = win.y, win.y + win.height - 1 do for x = win.x, win.x + win.width - 1 do
                local key = x .. ":" .. y
                assert(not covered[key], "Grid panes overlap"); covered[key] = true
            end end
        end end
        local count = 0
        for _ in pairs(covered) do count = count + 1 end
        equal(count, 83 * 25, "3x3 panes must cover the workspace exactly, excluding the taskbar")
        local model = chooseGrid()
        for _, hit in ipairs(model.menuHits) do if hit.item and hit.item.value == "back" then t.touch("top", hit.x1, hit.y); break end end
        equal(model.grid, nil)
        for _, hit in ipairs(model.menuHits) do if hit.item and hit.item.value == "cancel" then t.touch("top", hit.x1, hit.y); break end end
        t.top.width, t.top.height = 86, 29
        t.bus.advance(1)
        local zone = Desktop.zone("grid_3x3_3_3", {width = 86, height = 29})
        equal(t.window(id).x, zone.x); equal(t.window(id).height, zone.height)
        t.reboot()
        equal(t.window(id).layout, "grid_3x3_3_3")
        equal(t.window(id).x, zone.x); equal(t.window(id).width, zone.width)
        assert(t.api.layoutWindow(id, "restore")); equal(t.window(id).layout, "grid_3x3_2_3")
    end

    function tests.appearance_layout_picker_bounds_and_hit_regions_fit_small_and_large_monitors()
        local app = {minWidth = 8, minHeight = 2}
        local grids = {false, "1x1", "2x1", "1x2", "2x2", "3x1", "1x3", "3x2", "2x3", "3x3"}
        for _, width in ipairs({10, 15, 25, 27, 40, 43, 81}) do
            for _, height in ipairs({6, 9, 10, 11, 18, 25}) do
                for _, grid in ipairs(grids) do
                    local monitor = {width = width, height = height}
                    local win = {x = 1, y = 1, width = width, height = height - 1, layout = "normal"}
                    local _, _, _, _, pages = Desktop.layoutPicker(win, app, monitor, 1, nil, grid)
                    for page = 1, pages do
                        local rect, lines, hits = Desktop.layoutPicker(win, app, monitor, page, nil, grid)
                        assert(rect.x >= 1 and rect.y >= 1 and rect.x + rect.width - 1 <= width and rect.y + rect.height - 1 < height)
                        equal(#lines, rect.height)
                        for _, line in ipairs(lines) do equal(#line, rect.width) end
                        for _, style in ipairs(lines.styles or {}) do
                            assert(style.x >= 1 and style.y >= 1 and style.width >= 1 and style.height >= 1
                                and style.x + style.width - 1 <= rect.width and style.y + style.height - 1 <= rect.height)
                        end
                        for index, hit in ipairs(hits) do
                            assert(hit.x1 >= rect.x and hit.x2 < rect.x + rect.width and (hit.y1 or hit.y) >= rect.y and (hit.y2 or hit.y) < rect.y + rect.height)
                            for other = index + 1, #hits do
                                local h = hits[other]
                                assert(hit.x2 < h.x1 or h.x2 < hit.x1 or (hit.y2 or hit.y) < (h.y1 or h.y) or (h.y2 or h.y) < (hit.y1 or hit.y), "Layout hit regions overlap")
                            end
                        end
                    end
                end
            end
        end
    end

    function tests.appearance_thirds_disable_only_the_positions_too_small_for_coffee()
        local t = setup(true, 41, 25) -- Thirds are 13,14,14 columns; Coffee needs 14 including its frame.
        local id = t.open("coffee")
        local win = t.window(id)
        t.touch("top", win.x + win.width - 5, win.y)
        local model = t.central.server.monitors["monitor_13:top"].layoutMenu
        for _, hit in ipairs(model.menuHits) do
            if hit.item and hit.item.value == "choose_3x3" then
                assert(hit.item.enabled); t.touch("top", hit.x1, hit.y); break
            end
        end
        equal(model.grid, "3x3")
        local disabled, enabled
        for _, hit in ipairs(model.menuHits) do
            if hit.item and hit.item.value == "grid_3x3_1_1" then disabled = hit end
            if hit.item and hit.item.value == "grid_3x3_3_3" then enabled = hit end
        end
        assert(disabled.item.enabled == false and enabled.item.enabled)
        local previous = serialize(win)
        t.touch("top", disabled.x1, disabled.y)
        equal(serialize(win), previous); equal(model.error, "Does not fit")
        t.touch("top", enabled.x2, enabled.y2)
        equal(t.window(id).layout, "grid_3x3_3_3")
        equal(t.window(id).x, 28); equal(t.window(id).width, 14); equal(t.window(id).height, 8)
    end

    function tests.appearance_large_clock_swaps_colours_keeps_original_size_and_clears_previous_digits()
        local t = setup(true)
        local id = t.open("coffee", "top", 1, 1, 64, 23)
        local state = t.central.server.state.appStates.coffee
        state.remainingTime = 5025 -- 01:23:45, with different shapes across all six digits.
        t.paint()
        local function pixels(row)
            local result = ""
            for x = 6, 58, 2 do result = result .. (t.top.bg[row][x] == 1 and "1" or "0") end
            return result
        end
        equal(pixels(3), table.concat({"111", "010", "0", "111", "111", "0", "101", "111"}, "0"))
        -- Same two-cell pixels and full-width clock band as before, with white
        -- strokes on blue instead of blue strokes on white.
        equal(t.top.bg[3][3], 2048); equal(t.top.bg[3][62], 2048)
        equal(t.top.bg[3][6], 1); equal(t.top.bg[4][7], 1)
        local before = pixels(7)
        state.remainingTime = 0; t.paint()
        assert(pixels(7) ~= before, "Changed digits must repaint even though their text cells are spaces")
        local app = t.central.server.apps.coffee
        local function textTime()
            return table.concat(app.render(30, 10, state, t.api, {view = {}}), "\n"):match("(%d+:%d+:%d+)")
        end
        equal(textTime(), "00:00:00")
        state.phase, state.harvestRemaining = "harvest", 59; t.paint()
        equal(textTime(), "00:00:59")
        equal(state.remainingTime, 0, "Rendering must not change saved countdown progress")
        state.phase, state.remainingTime = "countdown", 604800; t.paint()
        equal(textTime(), "168:00:00")
        assert(t.api.placeWindow(id, 1, 1, 30, 12)); t.paint()
        assert(table.concat(t.top.lines, "\n"):find("168:00:00", 1, true), "Small windows still show an ordinary text clock")
    end

    function tests.appearance_all_palette_colours_keep_titles_and_coffee_text_readable()
        local t = setup(true)
        local id = t.open("coffee")
        local win = t.window(id)
        for index = 0, 15 do
            local bg, accent = 2 ^ index, 2 ^ ((index + 5) % 16)
            assert(t.api.setBackgroundColour(bg)); assert(t.api.setAppColour("coffee", accent)); t.paint()
            assert(t.api.setWindowBorderColour(accent)); assert(t.api.setTaskbarColour(bg)); t.paint()
            equal(t.top.bg[win.y][win.x], accent)
            assert(t.top.fg[win.y + 1][win.x + 1] ~= t.top.bg[win.y + 1][win.x + 1])
            assert(t.top.fg[win.y + 2][win.x + 1] ~= t.top.bg[win.y + 2][win.x + 1])
        end
    end

    function tests.appearance_system_border_and_taskbar_palettes_apply_globally_and_survive_reboot()
        local t = setup(true)
        local coffee = t.open("coffee", "left")
        local settings = t.open("@settings")
        local state = t.central.server.state.appStates.coffee
        state.remainingTime = 1234
        local wiring = serialize(t.central.server.state.outputMap)
        t.click(settings, "windowBorder"); t.click(settings, "colour", 16)
        t.click(settings, "taskbar"); t.click(settings, "colour", 8192)
        local preferences = t.api.getOSSettings()
        equal(preferences.windowBorderColour, 16); equal(preferences.taskbarColour, 8192)
        for _, item in ipairs({{settings, t.top}, {coffee, t.left}}) do
            local win, screen = t.window(item[1]), item[2]
            equal(screen.bg[win.y][win.x], 16)
            equal(screen.bg[win.y + 1][win.x], 16)
            equal(screen.bg[win.y + win.height - 1][win.x], 16)
            equal(screen.fg[win.y][win.x], 32768)
            equal(screen.bg[win.y][win.x + win.width - 2], 16384, "Close stays red")
            equal(screen.bg[screen.height][screen.width], 8192)
            equal(screen.bg[screen.height - 1][screen.width], t.api.getOSSettings().backgroundColour, "Taskbar colouring must not extend upward")
            equal(screen.fg[screen.height][screen.width], 1)
        end
        equal(state.remainingTime, 1234); equal(serialize(t.central.server.state.outputMap), wiring)
        equal(t.api.pickColour(coffee, "windowBorder"), false)
        equal(t.api.pickColour(coffee, "taskbar"), false)
        t.reboot()
        equal(t.api.getOSSettings().windowBorderColour, 16); equal(t.api.getOSSettings().taskbarColour, 8192)
        equal(t.central.server.state.appStates.coffee.remainingTime, 1234)
        equal(t.left.bg[t.window(coffee).y][t.window(coffee).x], 16)
    end

    function tests.appearance_system_colours_roll_back_failed_saves_and_default_old_or_invalid_preferences()
        local t = setup(true)
        local id = t.open("@settings")
        t.click(id, "windowBorder")
        local before = t.central.disk.files["configs_os_state.txt"]
        t.central.disk.failWrite = true; t.click(id, "colour", 2)
        equal(t.api.getOSSettings().windowBorderColour, 128)
        equal(t.central.disk.files["configs_os_state.txt"], before)
        assert(t.central.server.dialogs[id].error)
        t.central.disk.failWrite = false; t.click(id, "colour", 2)
        t.click(id, "taskbar")
        t.central.disk.failWrite = true; t.click(id, "colour", 1)
        equal(t.api.getOSSettings().taskbarColour, 128)
        t.central.disk.failWrite = false; t.click(id, "colour", 1)
        equal(t.api.getOSSettings().taskbarColour, 1)
        equal(t.top.fg[t.top.height][t.top.width], 32768, "A white taskbar needs black text")
        equal(t.api.setWindowBorderColour(3), false); equal(t.api.setTaskbarColour("red"), false)
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        saved.appearance.windowBorderColour, saved.appearance.taskbarColour = nil, 3
        saved.appStates.coffee.remainingTime = 4321
        t.central.disk.files["configs_os_state.txt"] = serialize(saved)
        t.reboot()
        equal(t.api.getOSSettings().windowBorderColour, 128); equal(t.api.getOSSettings().taskbarColour, 128)
        equal(t.central.server.state.appStates.coffee.remainingTime, 4321)
    end

    function tests.appearance_all_three_os_colour_controls_fit_compact_settings_windows()
        local t = setup(false)
        local app = t.central.server.systemApps["@settings"]
        for _, width in ipairs({12, 20, 28}) do for _, height in ipairs({6, 8, 10}) do
            local lines = app.render(width, height, {}, t.api)
            local actions = {}
            for _, h in ipairs(lines.hits) do
                assert(h.y >= 1 and h.y <= height); assert(not actions[h.y], "OS appearance controls overlap")
                actions[h.y] = true
            end
            equal(#lines.hits, 3)
        end end
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
