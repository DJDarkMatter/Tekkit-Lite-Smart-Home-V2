-- System settings, snap diagrams, move nudges and responsive app navigation.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local Desktop = dofile("lib_desktop.lua")
    local file = assert(io.open("apps_coffee.lua", "r"))
    local coffee = file:read("*a"); file:close()
    local function setup(withCoffee, width, height, enabledApps)
        local bus = newBus()
        local apps = type(withCoffee) == "table" and withCoffee or withCoffee and {["apps_coffee.lua"] = coffee} or {}
        local central = bus.computer(10, "server", {apps = apps, enabledApps = enabledApps}):start()
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
        function t.hits(id)
            t.paint()
            local win = t.window(id)
            local dialog = t.central.server.dialogs[id]
            if dialog then return dialog.hits end
            local app = t.central.server.systemApps[win.appName] or t.central.server.apps[win.appName]
            local content = app.render(win.width - 2, win.height - 2, t.central.server.state.appStates[win.appName], t.api,
                {windowId = id, appName = win.appName, monitorId = win.monitorId, view = t.central.server.views[id]})
            return content.hits
        end
        function t.click(id, action, value)
            local win = t.window(id)
            for _, hit in ipairs(t.hits(id) or {}) do
                if hit.action == action and hit.enabled ~= false
                    and (value == nil or hit.value == value or type(value) == "function" and value(hit.value)) then
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

    function tests.appearance_all_keyboards_use_one_letter_shift_without_changing_number_or_lowercase_banks()
        local Gui=dofile("lib_gui.lua")
        for _,bank in ipairs({1,"ABC"}) do
            local k={bank=bank,draft="",page=2}; assert(Gui.typeKey(k,"A",3))
            equal(k.bank,type(bank)=="number" and 0 or "abc"); equal(k.page,2)
            assert(Gui.typeKey(k,"b",3)); equal(k.draft,"Ab")
            k.bank=bank; assert(Gui.typeKey(k," ",3)); equal(k.bank,bank)
            equal(Gui.typeKey(k,"C",3),false); equal(k.bank,bank)
        end
        for _,bank in ipairs({2,"123"}) do local k={bank=bank,draft=""}; Gui.typeKey(k,"1",4); equal(k.bank,bank) end
    end

    function tests.v49_primary_buttons_use_spare_rows_and_secondary_controls_stay_compact()
        local Gui = dofile("lib_gui.lua")
        for _, height in ipairs({6, 12, 28}) do
            local ui=Gui.form(24,height,{},2048)
            ui.menu("Actions",{{"First","first"},{"Second","second"},{"Third","third"}}, "actions",
                {{"Back","back"},{"Apply","apply"}})
            local lines, hits=ui.finish()
            local surface=Gui.new(24,height,1,32768)
            for _,style in ipairs(lines.styles) do
                surface.style(style.x,style.y,style.width,style.height,style.fg,style.bg)
            end
            for _,hit in ipairs(hits) do
                if height==6 or hit.action=="back" then equal(hit.y1,hit.y2)
                elseif height==12 then assert(hit.y2>hit.y1)
                else assert(hit.y2-hit.y1+1>=3) end
                for y=hit.y1,hit.y2 do equal(Gui.actionAt(hits,hit.x1,y),hit.action) end
            end
            for i=2,3 do
                local previous, current=hits[i-1],hits[i]
                if previous.y2+1==current.y1 then
                    assert(surface.background[previous.y2]~=surface.background[current.y1],
                        "Adjacent list entries need a visible boundary")
                end
            end
            local footer=surface.background[height]
            assert(footer:sub(1,12)~=footer:sub(13),"Adjacent footer buttons need a visible boundary")
        end
        local ui=Gui.content(20,16)
        ui.button(2,"A longer friendly client name","choose")
        local lines,hits=ui.finish()
        assert(table.concat(lines,"\n"):find("client name",1,true))
        assert(hits[1].y2>hits[1].y1)
    end

    function tests.v49_launcher_stays_single_column_and_layout_and_palette_keep_large_choices()
        local apps={}
        for i=1,12 do apps[i]={label="App "..i,value=i,enabled=true} end
        for _,size in ipairs({{51,19},{128,70}}) do
            local rect,_,hits,_,pages=Desktop.menu({width=size[1],height=size[2]},"Start",apps,1)
            equal(pages,1); assert(rect.width<=22 and rect.height<=14)
            for i,hit in ipairs(hits) do
                equal(hit.x1,rect.x); equal(hit.y1,hit.y2)
                equal(hit.item.value,i)
                if i>1 then equal(hit.y1,hits[i-1].y1+1) end
            end
        end
        local t=setup(true,58,25)
        local model=t.central.server.monitors["monitor_13:top"]
        t.touch("top",2,25)
        local function menuItem(value, menu)
            for _,hit in ipairs(menu.menuHits) do if hit.item and hit.item.value==value then return hit end end
            error("Missing menu item "..value)
        end
        local entry=menuItem("coffee",model)
        equal(entry.y2,entry.y1)
        t.touch("top",entry.x2,entry.y2)
        local id,win=next(t.central.server.state.windows)
        equal(win.appName,"coffee")
        assert(t.api.placeWindow(id,1,1,54,22)); t.paint()
        t.touch("top",win.x+win.width-5,win.y)
        local resize=menuItem("custom",model.layoutMenu)
        assert(resize.y2>resize.y1)
        t.touch("top",resize.x1,resize.y2)
        assert(model.placement and model.placement.kind=="custom")
        t.touch("top",6,25)

        local settings=t.open("@settings","top",2,2,50,20)
        t.click(settings,"appearance")
        t.click(settings,"background")
        local color,back
        for _,hit in ipairs(t.hits(settings)) do
            if hit.action=="colour" and hit.value==2048 then color=hit end
            if hit.action=="cancel" then back=hit end
        end
        assert(color.y2>color.y1); equal(back.y1,back.y2)
        local window=t.window(settings)
        t.touch("top",window.x+color.x2,window.y+color.y2)
        equal(t.api.getOSSettings().backgroundColour,2048)
    end

    function tests.v48_touch_layout_revisions_reject_taps_for_an_older_layout()
        local probe=[=[
            local app={title="Probe",minWidth=12,minHeight=6}
            function app.render(w,h,state,api)
                local ui=api.ui.content(w,h)
                ui.heading("Controls")
                for i=1,state.count or 1 do ui.button(1+i,"Choice "..i,"choose",nil,nil,true,nil,nil,i) end
                ui.button(h,"Back","back")
                return ui.finish()
            end
            function app.handleTouch(x,y,w,h,state,api,context)
                local action,value=api.ui.actionAt(context.hits,x,y)
                if action=="choose" then state.chosen=value end
            end
            return app
        ]=]
        local t=setup({["apps_probe.lua"]=probe},58,25)
        local id=t.open("probe","top",1,1,40,22)
        local window=t.window(id)
        local state=t.central.server.state.appStates.probe
        local previous=t.display.client.devices.top.inputRevision
        state.count=4
        t.paint()
        assert(previous~=t.display.client.devices.top.inputRevision)
        local hit=t.hits(id)[2]
        t.display.client.touch("top",window.x+hit.x2,window.y+hit.y2,previous)
        t.bus.pump()
        equal(state.chosen,nil)
        t.touch("top",window.x+hit.x2,window.y+hit.y2)
        equal(state.chosen,2)
    end
    function tests.v41_shared_keyboard_qwerty_paging_and_next_mode_labels()
        local Gui = dofile("lib_gui.lua")
        for _, size in ipairs({{12, 6}, {19, 8}, {20, 6}, {38, 14}, {64, 26}}) do
            local w, h = unpack(size)
            local k = {draft = "", bank = 0, page = 1, back = "home"}
            local function draw(label)
                local ui = Gui.form(w, h, {}, 2048)
                ui.keyboard(k)
                local keys, occupied, mode = {}, {}, nil
                for _, hit in ipairs(ui.hits) do
                    local y1, y2 = hit.y1 or hit.y, hit.y2 or hit.y
                    assert(hit.x1 >= 1 and hit.x2 <= w and y1 >= 1 and y2 <= h)
                    for y = y1, y2 do
                        for x = hit.x1, hit.x2 do
                            local key = x .. ":" .. y
                            assert(not occupied[key], "Overlapping keyboard keys")
                            occupied[key] = true
                        end
                    end
                    if hit.action == "key" then keys[hit.value] = hit.y
                    elseif hit.action == "bank" then mode = ui.lines[hit.y]:sub(hit.x1, hit.x2):match("%S+") end
                end
                equal(mode, label)
                return keys
            end
            local keys = draw("ABC")
            assert(keys.q == keys.w and keys.q < keys.a and keys.a < keys.z)
            if w >= 20 then equal(keys.q, keys.p); equal(k.pages, 1)
            else Gui.editText(k, "keyPage", nil, 32); assert(draw("ABC").p) end
            Gui.editText(k, "bank", nil, 32); assert(draw("123").Q)
            Gui.editText(k, "key", "Q", 32); assert(draw("ABC").q); equal(k.draft, "Q")
            Gui.editText(k, "bank", nil, 32); Gui.editText(k, "bank", nil, 32)
            local all = {}
            repeat
                for key in pairs(draw("abc")) do all[key] = true end
                if k.page == k.pages then break end
                Gui.editText(k, "keyPage", nil, 32)
            until false
            assert(all["1"] and all["!"] and all["@"] and all["{"] and all["|"] and all["~"])
            Gui.editText(k, "bank", nil, 32); assert(draw("ABC").q)
        end
    end
    function tests.v46_number_pad_covers_every_cell_between_display_and_footer()
        local Gui = dofile("lib_gui.lua")
        for _, size in ipairs({{12,6}, {27,15}, {40,20}}) do
            local width, height = unpack(size)
            for _, decimal in ipairs({false, true}) do
                local ui = Gui.form(width, height, {}, 2048)
                ui.numberPad("Level", "201000", "edit", decimal)
                local coverage, digits, lastKey = {}, 0, 0
                for _, hit in ipairs(ui.hits) do
                    if hit.action == "digit" then
                        digits = digits + 1
                        lastKey = math.max(lastKey, hit.y2)
                        assert(hit.y1 >= 3 and hit.y2 < height and hit.x1 >= 1 and hit.x2 <= width)
                        equal(ui.lines[hit.y]:sub(hit.x1, hit.x2):match("%S+"), hit.value)
                        for y = hit.y1, hit.y2 do
                            for x = hit.x1, hit.x2 do
                                local cell = (y - 3) * width + x
                                assert(not coverage[cell])
                                coverage[cell] = true
                            end
                        end
                        local action, value = Gui.actionAt(ui.hits, hit.x2, hit.y2)
                        equal(action, "digit"); equal(value, hit.value)
                    end
                end
                equal(digits, 12)
                for cell = 1, (lastKey - 2) * width do assert(coverage[cell], "Gap between keypad tiles") end
                for y = lastKey + 1, height do
                    equal(Gui.actionAt(ui.hits, 1, y), "setNumber")
                    equal(Gui.actionAt(ui.hits, width, y), "edit")
                end
                local _, firstBottomKey = Gui.actionAt(ui.hits, 1, lastKey)
                equal(firstBottomKey, "9")
                local _, secondBottomKey = Gui.actionAt(ui.hits, math.floor(width / 4) + 1, lastKey)
                equal(secondBottomKey, decimal and "." or "Clr")
                equal(Gui.actionAt(ui.hits, 1, height), "setNumber")
                equal(Gui.actionAt(ui.hits, width, height), "edit")
            end
        end
    end
    function tests.appearance_route_selectors_keep_previous_choices_visible_and_preserve_compact_paging()
        local Gui=dofile("lib_gui.lua"); local IO=dofile("lib_io_picker.lua"); local Sensor=dofile("lib_sensor_picker.lua")
        local io=IO.new("route","output",{clientId="io_12345",side="bottom"})
        for stage=2,3 do
            io.stage=stage; local lines=IO.render(io,32,12,{})
            assert(lines[2]:find("io_12345",1,true)); if stage==3 then assert(lines[2]:find("bottom",1,true)) end
            local footer=12
            for _,hit in ipairs(io.hits) do if hit.action=="prev" or hit.action=="back" then footer=math.min(footer,hit.y1) end end
            for _,hit in ipairs(io.hits) do if hit.action=="select" then assert(hit.y1>=3 and hit.y2<footer) end end
            lines=IO.render(io,12,6,{}); assert(not lines[2]:find("io_12345",1,true))
        end
        local sensor=Sensor.new("source",{clientId="sensor_12345",side="top"},"ae")
        for stage=2,3 do sensor.stage=stage; local lines=Sensor.render(sensor,40,12,{})
            assert(lines[2]:find("sensor_12345",1,true)); if stage==3 then assert(lines[2]:find("top",1,true)) end
        end
        local path=Gui.breadcrumb({string.rep("x",64),"bottom",string.rep("y",80)},30,10)
        assert(#path<=30); assert(path:find("bottom",1,true)); equal(Gui.breadcrumb({"x"},23,10),nil)
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
        assert(hit, "Settings must be available before installing apps")
        equal(hit.item.label, "Settings")
        t.touch("top", hit.x1, hit.y)
        local id
        for key, win in pairs(t.central.server.state.windows) do if win.appName == "@settings" then id = key end end
        assert(id)
        t.click(id, "appearance"); t.click(id, "background")
        t.click(id, "colour", 128)
        equal(t.api.getOSSettings().backgroundColour, 128)
        equal(t.top.bg[20][60], 128); equal(t.left.bg[2][2], 128)
        local win = t.window(id)
        equal(t.top.bg[win.y][win.x], 128, "Changing the desktop must not override the selected window-border color")
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
        local function same(a,b)
            if type(a)~="table" then return a==b end
            if type(b)~="table" then return false end
            for key,value in pairs(a) do if not same(value,b[key]) then return false end end
            for key in pairs(b) do if a[key]==nil then return false end end
            return true
        end
        local function snapshot(value)
            if type(value)~="table" then return value end
            local result={}; for key,item in pairs(value) do result[key]=snapshot(item) end
            return result
        end
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
                local previous = snapshot(t.window(id))
                local root = {}
                for _, hit in ipairs(model.menuHits) do if hit.item then root[hit.item.value] = true end end
                assert(root.custom and root.move and root.restore and root.fullscreen, "Resize/Move/Restore/Fullscreen must stay at the first level")
                t.touch("top", choice.x2, choice.y2 or choice.y)
                assert(same(t.window(id), previous), "Picking a grid alone must not change geometry")
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
            for _, height in ipairs({6, 9, 10, 11, 12, 18, 25}) do
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
                            if hit.item and hit.item.value=="fullscreen" and width>=14 and height>=12 then
                                assert(lines[hit.y-rect.y+1]:find("Fullscreen",1,true),"Fullscreen label must fit on narrow graphical menus")
                            end
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
        -- Same two-cell pixels, with white strokes on blue and side gutters.
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
            for y=win.y+1,win.y+win.height-2 do for x=win.x+1,win.x+win.width-2 do
                if t.top.lines[y]:sub(x,x)~=" " then
                    assert(t.top.fg[y][x]~=t.top.bg[y][x],"Coffee text must contrast; graphical clock gutters contain no text")
                end
            end end
        end
    end

    function tests.appearance_system_border_and_taskbar_palettes_apply_globally_and_survive_reboot()
        local t = setup(true)
        local coffee = t.open("coffee", "left")
        local settings = t.open("@settings")
        local state = t.central.server.state.appStates.coffee
        state.remainingTime = 1234
        local wiring = serialize(t.central.server.state.outputMap)
        t.click(settings, "appearance"); t.click(settings, "windowBorder"); t.click(settings, "colour", 16)
        t.click(settings, "taskbar"); t.click(settings, "taskbarColour"); t.click(settings, "colour", 8192)
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
        t.click(id, "appearance"); t.click(id, "windowBorder")
        local before = t.central.disk.files["configs_os_state.txt"]
        t.central.disk.failWrite = true; t.click(id, "colour", 2)
        equal(t.api.getOSSettings().windowBorderColour, 128)
        equal(t.central.disk.files["configs_os_state.txt"], before)
        assert(t.central.server.dialogs[id].error)
        t.central.disk.failWrite = false; t.click(id, "colour", 2)
        t.click(id, "taskbar"); t.click(id, "taskbarColour")
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

    function tests.v49_taskbar_position_moves_windows_launcher_and_panes_and_survives_reboot()
        local t=setup(true,64,27)
        local coffee=t.open("coffee","left",1,1,43,16)
        local settings=t.open("@settings","top",1,1,40,18)
        local before=t.window(settings).relative.y
        t.click(settings,"appearance"); t.click(settings,"taskbar"); t.click(settings,"taskbarPosition")
        t.click(settings,"setTaskbarPosition","top")
        equal(t.api.getOSSettings().taskbarPosition,"top")
        equal(t.top.lines[1]:sub(1,3),"[+]")
        equal(t.left.lines[1]:sub(1,3),"[+]")
        equal(t.window(settings).y,2); equal(t.window(settings).relative.y,before)
        equal(t.window(coffee).y,2)
        assert(t.api.layoutWindow(settings,"maximize")); t.paint()
        equal(t.window(settings).y,2); equal(t.window(settings).height,26)
        t.touch("top",1,1)
        local model=t.central.server.monitors["monitor_13:top"]
        assert(model.launcher and model.menuHits[1].y>=3)
        t.touch("top",1,1)
        t.reboot()
        equal(t.api.getOSSettings().taskbarPosition,"top"); equal(t.window(settings).y,2)
        assert(t.api.setTaskbarPosition("bottom")); t.paint()
        equal(t.window(settings).y,1); equal(t.top.lines[27]:sub(1,3),"[+]")
    end

    function tests.appearance_os_colours_and_reset_button_fit_compact_settings_windows()
        local t = setup(false)
        local app = t.central.server.systemApps["@settings"]
        for _, width in ipairs({12, 20, 28}) do for _, height in ipairs({6, 8, 10}) do
            for _, section in ipairs({"home", "appearance", "taskbar", "taskbarPosition", "data", "screensavers"}) do
                local lines = app.render(width, height, {}, t.api, {windowId = 1, view = {section = section}})
                local occupied = {}
                for _, hit in ipairs(lines.hits) do
                    assert(hit.y >= 1 and hit.y <= height and hit.x1 >= 1 and hit.x2 <= width)
                    for x = hit.x1, hit.x2 do
                        local key = hit.y .. ":" .. x
                        assert(not occupied[key], "Settings controls overlap")
                        occupied[key] = true
                    end
                end
            end
        end end
    end

    function tests.appearance_reset_list_pins_os_scopes_and_sorts_installed_and_saved_apps_on_small_monitors()
        local t = setup({
            ["apps_zebra.lua"] = 'return {title="Alpha"}',
            ["apps_alpha.lua"] = 'return {title="Zulu"}',
            ["apps_disabled.lua"] = 'error("Disabled app was executed")',
        }, 15, 10, {zebra = true, alpha = true})
        t.central.server.state.appStates.old_app = {setting = true}
        local id = t.open("@settings")
        t.click(id, "data"); t.click(id, "resetData")
        local listed = {}
        while true do
            local current = t.central.server.views[id].pages.resetData
            local nextPage
            for _, hit in ipairs(t.hits(id)) do
                if hit.action == "selectScope" then listed[#listed + 1] = hit.value.id end
                if hit.action == "page" and hit.enabled ~= false and hit.value.page > current then nextPage = hit.value.page end
            end
            if not nextPage then break end
            t.click(id, "page", function(value) return value.page == nextPage end)
        end
        equal(table.concat(listed, ","), "@all,@settings,zebra,disabled,old_app,alpha")
        equal(t.central.server.apps.disabled, nil)
    end

    function tests.appearance_reset_app_clears_its_windows_data_and_routes_and_preserves_shared_output()
        local panel = [[
            local starts = 0
            return {
                title = "Wire panel",
                init = function(state)
                    starts = starts + 1
                    state.starts = starts
                end,
                render = function(w, h, state, api)
                    local ui = api.ui.content(w, h)
                    ui.button(2, "Configure", "configure")
                    return ui.lines
                end,
                handleTouch = function(x, y, w, h, state, api)
                    state.configured = true
                    assert(api.mapOutput("custom_shared", "io_11", "left", 1, true))
                    assert(api.mapOutput("custom_exclusive", "io_11", "front", nil, true))
                    assert(api.watchSensor("custom_watch", {clientId="sensor_14",side="top",target="test"}))
                    return true
                end,
            }
        ]]
        local t = setup({["apps_wires.lua"] = panel, ["apps_coffee.lua"] = coffee})
        local bridge = t.bus.computer(11, "io"):start()
        local main, other = t.open("wires"), t.open("wires", "left")
        assert(t.api.mapOutput("manual_shared", "io_11", "left", 1, true))
        t.click(main, "configure")
        local state = t.central.server.state
        equal(state.outputMap.custom_shared.owner, "wires")
        assert(t.api.setAppColour("wires", 32))
        state.appStates.coffee.totalHarvests = 42
        t.bus.advance(1)
        equal(bridge.bundled.left, 1)
        equal(bridge.digital.front, true)
        local settings = t.open("@settings")
        t.click(settings, "data"); t.click(settings, "resetData")
        t.click(settings, "selectScope", function(item) return item.id == "wires" end)
        assert(state.appStates.wires.configured)
        t.click(settings, "commit")
        t.bus.advance(1)
        equal(t.window(main), nil); equal(t.window(other), nil)
        equal(t.central.server.views[other], nil)
        equal(next(state.appStates.wires), nil)
        equal(state.appearance.appColours.wires, nil)
        equal(state.outputMap.custom_shared, nil); equal(state.outputMap.custom_exclusive, nil)
        equal(t.central.server.sensors.watches.custom_watch, nil)
        equal(bridge.bundled.left, 1); equal(bridge.digital.front, false)
        equal(state.appStates.coffee.totalHarvests, 42)
        equal(t.api.getOutput("manual_shared"), true)
        assert(t.window(settings))
        t.open("wires", "left")
        equal(state.appStates.wires.starts, 1, "Reset must reload the app's private runtime")
        equal(state.appStates.wires.configured, nil)
        local backup = unserialize(t.central.disk.files["configs_os_state.txt.bak"] or "") or {}
        assert(not (backup.appStates and backup.appStates.wires and backup.appStates.wires.configured),
            "Recovery must not restore deleted app data")
    end

    function tests.appearance_reset_respects_level_emitter_routes_imported_from_solar_farm()
        local t = setup(false)
        local state = t.central.server.state
        state.appStates.solar_farm = {oldPreference = 7}
        state.appStates.level_emitter = {rules = {{outputName = "solar_farm_alarm_1"}}}
        assert(t.api.mapOutput("solar_farm_alarm_1", "io_11", "front", 1))
        state.outputMap.solar_farm_alarm_1.owner = nil
        local id = t.open("@settings")
        t.click(id, "data"); t.click(id, "resetData")
        t.click(id, "selectScope", function(item) return item.id == "solar_farm" end)
        t.click(id, "commit")
        equal(state.appStates.solar_farm, nil)
        assert(state.outputMap.solar_farm_alarm_1)
        t.click(id, "selectScope", function(item) return item.id == "level_emitter" end)
        t.click(id, "commit")
        equal(state.appStates.level_emitter, nil)
        equal(state.outputMap.solar_farm_alarm_1, nil)
    end

    function tests.v46_retired_level_emitter_keeps_rules_and_releases_only_its_wires()
        local t = setup(false)
        local bridge = t.bus.computer(11, "io", {modemSide = "right"}):start()
        t.bus.advance(2)
        local state = t.central.server.state
        local rules = {{name = "Old level rule", outputName = "solar_farm_alarm_1",
            dismissInput = {clientId = "io_11", side = "left", color = 1}}}
        state.appStates.level_emitter = {rules = rules}
        for _, route in ipairs({{"level_emitter_rule_1",1}, {"solar_farm_alarm_1",2},
            {"level_emitter_rule_2",4}, {"unrelated",4}}) do
            assert(t.api.mapOutput(route[1], "io_11", "front", route[2], true))
        end
        state.outputMap.level_emitter_rule_1.owner = nil
        state.outputMap.level_emitter_rule_2.owner = "level_emitter"
        state.outputMap.solar_farm_alarm_1.owner = "solar_farm"
        local id = t.open("@settings", "top", 1, 1, 46, 18)
        state.windows[50] = {id = 50, appName = "level_emitter", monitorId = "monitor_13:left",
            x = 1, y = 1, width = 32, height = 12, order = 50}
        local config = unserialize(t.central.disk.files["configs_os.txt"])
        config.enabledApps.level_emitter = true
        t.central.disk.files["configs_os.txt"] = serialize(config)
        t.central.disk.files["apps_level_emitter.lua"] = "error('retired app was loaded')"
        assert(t.api.save())
        t.bus.advance(2)
        equal(bridge.bundled.front, 7)
        t.reboot()
        state = t.central.server.state
        equal(t.central.server.apps.level_emitter, nil)
        equal(t.central.server.running.level_emitter, nil)
        equal(t.window(50), nil)
        equal(t.window(id).appName, "@settings")
        assert(not table.concat(t.central.log, "\n"):find("retired app was loaded", 1, true))
        equal(state.appStates.level_emitter.rules[1].name, rules[1].name)
        equal(bridge.bundled.front, 4)
        for _, name in ipairs({"level_emitter_rule_1", "level_emitter_rule_2", "solar_farm_alarm_1"}) do
            equal(state.outputMap[name], nil)
            assert(state.archivedRoutes.level_emitter[name])
        end
        local used = t.api.getUsedIO()
        equal(#used, 1); equal(used[1].color, 4)
        t.click(id, "data"); t.click(id, "deleteApps")
        t.click(id, "selectScope", function(item) return item.id == "level_emitter" end)
        t.click(id, "commit")
        equal(t.central.disk.files["apps_level_emitter.lua"], nil)
        assert(state.archivedRoutes.level_emitter.solar_farm_alarm_1)
        t.reboot()
        equal(t.central.server.state.appStates.level_emitter.rules[1].name, rules[1].name)
        equal(bridge.bundled.front, 4)
    end

    function tests.appearance_app_state_migration_preserves_live_tables_and_rolls_back_failed_saves()
        local t = setup({["apps_fixture.lua"] = "return {title='Fixture'}"})
        local state = t.central.server.state
        local source, target = {sentinel = 42}, state.appStates.fixture
        state.appStates.source = source
        local before = serialize(target)
        local function migrate(a, b) a.sentinel, b.sentinel = nil, 9; return true end
        t.central.disk.failWrite = true
        equal(t.api.migrateAppState("source", "fixture", migrate), false)
        equal(source.sentinel, 42); equal(state.appStates.fixture, target); equal(serialize(target), before)
        t.central.disk.failWrite = false
        assert(t.api.migrateAppState("source", "fixture", migrate))
        equal(source.sentinel, nil); equal(target.sentinel, 9)
        local detached = t.api.getAppData("fixture"); detached.sentinel = 77
        equal(target.sentinel, 9)
    end

    function tests.appearance_reset_os_settings_clears_desktop_and_os_routes_but_keeps_app_data_and_legacy_routes()
        local t = setup(true)
        t.open("coffee", "left")
        local id = t.open("@settings")
        local state = t.central.server.state
        state.appStates.coffee.totalHarvests = 29
        assert(t.api.setBackgroundColour(16))
        assert(t.api.setAppColour("coffee", 32))
        assert(t.api.mapOutput("coffee_harvest", "io_11", "front", nil))
        state.outputMap.coffee_harvest.owner = nil -- A mapping saved by v37.
        assert(t.api.mapOutput("manual", "io_11", "left", 1))
        t.click(id, "data"); t.click(id, "resetData")
        t.click(id, "selectScope", function(item) return item.id == "@settings" end)
        t.click(id, "commit")
        equal(next(state.windows), nil)
        equal(state.outputMap.manual, nil)
        assert(state.outputMap.coffee_harvest)
        equal(t.api.getOSSettings().backgroundColour, 2048)
        equal(t.api.getAppColour("coffee"), 32)
        equal(state.appStates.coffee.totalHarvests, 29)
        t.reboot()
        equal(next(t.central.server.state.windows), nil)
        equal(t.central.server.state.appStates.coffee.totalHarvests, 29)
        assert(t.central.server.state.outputMap.coffee_harvest)
    end

    function tests.appearance_factory_reset_requires_two_confirmations_and_clears_offline_routes_on_reconnect()
        local t = setup(true)
        local bridge = t.bus.computer(11, "io"):start()
        t.open("coffee", "left")
        local id = t.open("@settings")
        local state = t.central.server.state
        state.appStates.coffee.totalHarvests = 77
        state.appStates.old_app = {settings = "old data"}
        assert(t.api.mapOutput("manual", "io_11", "front", nil, true))
        t.bus.advance(1)
        equal(bridge.digital.front, true)
        bridge.active = false
        t.click(id, "data"); t.click(id, "resetData")
        t.click(id, "selectScope", function(item) return item.id == "@all" end)
        t.click(id, "confirmAgain")
        equal(state.appStates.coffee.totalHarvests, 77)
        assert(state.outputMap.manual)
        t.click(id, "cancel")
        equal(state.appStates.coffee.totalHarvests, 77)
        t.click(id, "selectScope", function(item) return item.id == "@all" end)
        t.click(id, "confirmAgain")
        t.reboot()
        state = t.central.server.state
        for _, hit in ipairs(t.hits(id)) do assert(hit.action ~= "commit", "A reboot must clear the pending confirmation") end
        t.click(id, "selectScope", function(item) return item.id == "@all" end)
        t.click(id, "confirmAgain")
        t.click(id, "commit")
        equal(next(state.windows), nil); equal(next(state.outputMap), nil)
        equal(state.appStates.coffee.totalHarvests, 0)
        equal(state.appStates.old_app, nil)
        assert(state.managedSides.io_11.front, "The released output needs an OFF snapshot on reconnect")
        local config = unserialize(bridge.disk.files["configs_io.txt"])
        config.safeOff = false
        bridge.disk.files["configs_io.txt"] = serialize(config)
        bridge = t.bus.computer(11, "io", {disk = bridge.disk}):start()
        t.bus.advance(3)
        equal(bridge.digital.front, false)
        t.central.disk.files["configs_os_state.txt"] = "corrupt primary"
        t.reboot()
        equal(next(t.central.server.state.outputMap), nil)
        equal(t.central.server.state.appStates.old_app, nil)
        equal(t.central.server.state.appStates.coffee.totalHarvests, 0)
    end

    function tests.appearance_failed_reset_install_keeps_old_data_even_after_restart()
        local t = setup(true)
        local id = t.open("@settings")
        local state = t.central.server.state
        state.appStates.coffee.totalHarvests = 73
        assert(t.api.mapOutput("manual", "io_11", "front", nil, true))
        t.click(id, "data"); t.click(id, "resetData")
        t.click(id, "selectScope", function(item) return item.id == "@all" end)
        t.click(id, "confirmAgain")
        local move = t.central.env.fs.move
        t.central.env.fs.move = function(from, to)
            if from:sub(-6) == ".reset" then error("Simulated reset replacement failure") end
            return move(from, to)
        end
        t.click(id, "commit")
        equal(state.appStates.coffee.totalHarvests, 73)
        assert(state.outputMap.manual); assert(t.window(id))
        equal(t.central.disk.files["configs_os_state.txt.reset"], nil)
        t.reboot()
        equal(t.central.server.state.appStates.coffee.totalHarvests, 73)
        assert(t.central.server.state.outputMap.manual)
        assert(t.window(id))
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
