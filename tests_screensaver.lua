return function(tests,newBus,monitor,serialize,unserialize,equal)
    local Gui=dofile("lib_gui.lua")
    local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
    local function touch(t,side,x,y) t.bus.queue(t.display,{"monitor_touch",side,x,y}); t.bus.pump(); t.paint() end
    local function frame(t,w,h)
        local content=t.content(nil,w,h);local surface=Gui.new(w,h)
        for y=1,h do surface.write(1,y,content[y]) end
        for _,style in ipairs(content.styles) do surface.style(style.x,style.y,style.width,style.height,style.fg,style.bg) end
        return content,surface.foreground
    end
    function tests.screensaver_never_autostarts_and_explicit_open_is_always_fullscreen()
        local t=setup("screensaver",false,{noOpen=true}); equal(t.central.server.running.screensaver,nil)
        t.id=t.open(); local w=t.window(); equal(w.fullscreen,true); equal(w.x,1); equal(w.y,1); equal(w.width,t.top.width); equal(w.height,t.top.height)
        equal(t.central.server.monitors["monitor_13:top"].fullscreen,t.id); equal(t.central.server.nextTickInterval(),.1)
        equal(t.api.placeWindow(t.id,2,2,20,10),false)
        touch(t,"top",t.top.width,1); equal(t.view().design,2); assert(t.window()); touch(t,"top",3,3); equal(t.window(),nil); equal(t.central.server.running.screensaver,nil); equal(t.central.server.nextTickInterval(),.5)
    end
    function tests.screensaver_all_four_cells_in_each_corner_cycle_and_neighbors_exit()
        local t=setup("screensaver")
        for _,point in ipairs({{1,1},{2,1},{1,2},{2,2}}) do
            local previous=t.view().design
            touch(t,"top",point[1],point[2]);equal(t.view().design,(previous+13)%15+1);assert(t.window())
            touch(t,"top",t.top.width-point[1]+1,point[2]);equal(t.view().design,previous);assert(t.window())
        end
        local content=t.content();equal(#content.hits,2)
        for _,hit in ipairs(content.hits) do equal(hit.x2-hit.x1+1,2);equal(hit.y2-hit.y1+1,2) end
        for _,point in ipairs({{3,1},{t.top.width-2,2},{1,3},{t.top.width,3}}) do
            touch(t,"top",point[1],point[2]);equal(t.window(),nil)
            t.id=t.open()
        end
    end
    function tests.screensaver_tiny_corner_areas_never_overlap_and_leave_an_exit_row()
        for _,size in ipairs({{2,2},{3,2},{4,2},{4,3},{12,6}}) do
            local t=setup("screensaver",true);assert(t.app.onOpen(t.state,t.api,t.context()))
            local w,h=size[1],size[2];local content=t.content(nil,w,h);local closed=false
            for y=1,h do for x=1,w do
                assert(not(Gui.hit(content.hits[1],x,y) and Gui.hit(content.hits[2],x,y)),"Navigation areas overlap")
            end end
            t.api.closeWindow=function(id) equal(id,t.id);closed=true;return true end
            assert(t.app.handleTouch(1,h,w,h,t.state,t.api,t.context()));assert(closed)
        end
    end
    function tests.screensaver_corners_cycle_both_directions_and_open_rotates_saved_design()
        local t=setup("screensaver"); equal(t.view().design,1)
        touch(t,"top",1,1); equal(t.view().design,15)
        touch(t,"top",t.top.width,1); equal(t.view().design,1)
        touch(t,"top",t.top.width,1); equal(t.view().design,2)
        assert(t.api.closeWindow(t.id)); t.id=t.open(); equal(t.view().design,3)
        local left=t.open("left"); equal(t.view(left).design,4); equal(t.view().design,3)
        touch(t,"left",1,1); equal(t.view(left).design,3); equal(t.view().design,3)
        local nextDesign=t.state.nextDesign; t.reboot(); equal(t.central.server.running.screensaver,nil)
        t.id=t.open(); equal(t.view().design,nextDesign)
    end
    function tests.screensaver_transient_windows_never_restore_and_leave_underlying_normal_windows_untouched()
        local t=setup("screensaver",false,{noOpen=true}); local normal=t.open("top","solar_farm")
        assert(t.api.layoutWindow(normal,"top_left")); local old=t.central.server.state.windows[normal]; local before={x=old.x,y=old.y,width=old.width,height=old.height,layout=old.layout,order=old.order}
        t.id=t.open(); assert(t.api.save()); local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.windows[t.id],nil); assert(saved.windows[normal]); for key,value in pairs(before) do equal(t.central.server.state.windows[normal][key],value) end
        t.reboot(); equal(t.window(),nil); equal(t.central.server.running.screensaver,nil); assert(t.central.server.state.windows[normal]); equal(t.central.server.monitors["monitor_13:top"].fullscreen,nil)
    end
    function tests.screensaver_other_monitors_and_taskbars_are_isolated()
        local t=setup("screensaver",false,{noOpen=true}); local left=t.open("left","solar_farm")
        local before=table.concat(t.left.lines,"\n"); t.id=t.open(); t.advance(1)
        equal(table.concat(t.left.lines,"\n"),before)
        for _,hit in ipairs(t.central.server.monitors["monitor_13:left"].taskbar) do if hit.action=="window" then equal(hit.id,left) end end
        local Desktop=dofile("lib_desktop.lua"); local _,hits=Desktop.taskbar({{id=99,title="Hidden",hideTaskbar=true}},{width=45,height=18},"12:00",{})
        for _,hit in ipairs(hits) do assert(hit.id~=99) end
    end
    function tests.screensaver_popups_render_above_fullscreen_and_capture_corner_touches()
        local t=setup("screensaver"); local level=t.central.server.apps.level_emitter; local state=t.central.server.state.appStates.level_emitter
        local item={raw="solar.lv",name="LV Solar",damage=0,key=dofile("lib_me.lua").itemKey("solar.lv",0,"LV Solar")}
        state.rules[1]={id=1,name="Farm alert",sensor={clientId="sensor_14",side="top",target="farm"},item=item,operator="over",threshold=1,reset=0,hold=0,
            enabled=true,latched=false,revision=1,signal={kind="constant",on=0,off=1,total=0}}; state.nextId=2
        t.advance(3); assert(t.popup()); assert(table.concat(t.top.lines,"\n"):find("Farm alert",1,true))
        local design=t.view().design; touch(t,"top",1,1); equal(t.view().design,design)
        touch(t,"top",t.top.width,1); assert(t.window()); assert(t.popup())
        touch(t,"top",2,2);equal(t.view().design,design);assert(t.popup())
        touch(t,"top",t.top.width-1,2);equal(t.view().design,design);assert(t.popup())
        t.ack(); equal(t.popup(),nil); assert(t.window()); touch(t,"top",t.top.width,1); assert(t.window()); equal(t.view().design,design+1); touch(t,"top",3,3); equal(t.window(),nil)
    end
    function tests.screensaver_all_patterns_animate_fit_tiny_screens_and_keep_large_frames_under_modem_limit()
        local t=setup("screensaver",true); assert(t.app.onOpen(t.state,t.api,t.context()))
        for design=1,15 do
            t.view().design=design
            for _,size in ipairs({{2,2},{12,6},{64,26},{256,128}}) do
                local w,h=size[1],size[2]; local content=t.content(nil,w,h); equal(#content,h)
                local surface=Gui.new(w,h)
                for y=1,h do equal(#content[y],w); surface.write(1,y,content[y]) end
                for _,style in ipairs(content.styles) do surface.style(style.x,style.y,style.width,style.height,style.fg,style.bg) end
                local lines,fg,bg=surface.frame()
                local packet={type="render",clientId="monitor_12345:bottom",monitorId="monitor_12345:bottom",serverSession="12345:12345",width=w,height=h,lines=lines,
                    foreground=fg,background=bg,colourFormat="rle1",frameId=100000,inputRevision=100000,
                    protocol="smarthome_v1",networkId="home",sender=12345,recipient=12346,_transport={version=1,boot=12345,sequence=1000000,channel=45231,serverChannel=45231,path={}}}
                assert(#serialize(packet)<61440,"Pattern "..design.." frame too large: "..#serialize(packet))
            end
            local before=serialize(t.content(nil,45,18)); t.advance(1); local after=serialize(t.content(nil,45,18)); assert(before~=after,"Pattern "..design.." is static")
        end
    end
    function tests.screensaver_failed_open_or_cycle_does_not_consume_rotation_or_close_other_views()
        local t=setup("screensaver"); local old=t.view().design; local nextIndex=t.state.nextDesign
        t.central.disk.failWrite=true; touch(t,"top",t.top.width,1); equal(t.view().design,old); equal(t.state.nextDesign,nextIndex)
        local id=t.api.openApp("screensaver","monitor_13:left"); equal(id,nil); assert(t.window()); equal(t.state.nextDesign,nextIndex)
        t.central.disk.failWrite=false; touch(t,"top",t.top.width,1); equal(t.view().design,old+1)
    end
    function tests.screensaver_dense_matrix_matches_symbol_trails_with_small_expiring_gaps()
        local t=setup("screensaver",true); assert(t.app.onOpen(t.state,t.api,t.context()))
        for _,size in ipairs({{12,6},{64,26},{256,128}}) do
            for _,time in ipairs({0,2,17}) do
                t.now=time; t.view().design=2; local dense=t.content(nil,size[1],size[2])
                local blank=0
                for _,row in ipairs(dense) do
                    assert(not row:find("[A-Za-z]"),"The reference uses digits and symbols, not an alphabet wall")
                    local _,count=row:gsub(" ","");blank=blank+count
                end
                assert(blank>=size[1]*size[2]*.03,"Old Matrix trails must clear, leaving small gaps")
                assert(blank<=size[1]*size[2]*.65,"Dense Matrix must remain well populated")
                for _,style in ipairs(dense.styles) do assert(style.fg~=32768);equal(style.bg,32768) end
                t.view().design=1; local sparse=t.content(nil,size[1],size[2]); local blank=0
                for _,row in ipairs(sparse) do local _,count=row:gsub(" ",""); blank=blank+count end
                assert(blank>=size[1]*size[2]*.4,"Sparse and dense modes must be distinct")
            end
        end
    end
    function tests.screensaver_matrix_heads_move_at_original_speed_and_wall_glyphs_remain_in_their_trails()
        local t=setup("screensaver",true);assert(t.app.onOpen(t.state,t.api,t.context()))
        local w,h=64,26
        for design=1,2 do
            t.view().design=design;t.now=0;local before,oldFG=frame(t,w,h)
            t.now=design==1 and .2 or .125;local after,newFG=frame(t,w,h)
            local heads,stable,shared=0,0,0
            for y=1,h-4 do for x=1,w do
                if oldFG[y]:sub(x,x)=="0" and before[y]:sub(x,x)~=" " then
                    heads=heads+1;local moved=false
                    for offset=1,design==1 and 4 or 1 do
                        if newFG[y+offset]:sub(x,x)=="0" and after[y+offset]:sub(x,x)~=" " then moved=true end
                    end
                    assert(moved,"Matrix head did not advance at the reference speed")
                end
                if design==2 and before[y]:sub(x,x)~=" " and after[y]:sub(x,x)~=" " then
                    shared=shared+1
                    if before[y]:sub(x,x)==after[y]:sub(x,x) then stable=stable+1 end
                end
            end end
            assert(heads>=3,"Test did not observe enough falling sources")
            if design==2 then assert(stable>shared*.8,"Wall characters should remain while their trail fades") end
        end
    end
    function tests.screensaver_wall_keeps_native_cell_detail_and_full_fade_palette_on_normal_monitors()
        local t=setup("screensaver",true);assert(t.app.onOpen(t.state,t.api,t.context()));t.view().design=2
        local seen={}
        for _,time in ipairs({0,.125,.25,1,3}) do
            t.now=time;local content,fg=frame(t,64,26)
            for y=1,26 do for x=1,64 do if content[y]:sub(x,x)~=" " then seen[fg[y]:sub(x,x)]=true end end end
        end
        for _,code in ipairs({"0","5","d","7"}) do assert(seen[code],"Missing reference Matrix fade color "..code) end
        -- The same source at a given coordinate is independent of window size;
        -- native glyph columns are not duplicated or replaced by spacer cells.
        t.now=1;local small=t.content(nil,32,12);local large=t.content(nil,64,26)
        for y=1,12 do equal(small[y],large[y]:sub(1,32)) end
    end
    function tests.screensaver_large_matrix_wall_keeps_frames_sendable_across_seeds_and_long_pauses()
        local t=setup("screensaver",true);assert(t.app.onOpen(t.state,t.api,t.context()));t.view().design=2
        for _,seed in ipairs({1,48723,104728}) do
            t.view().seed=seed
            for _,time in ipairs({0,.125,17,86400}) do
                t.now=time
                local content,fg=frame(t,256,128)
                local lines,foreground,background={},{},{}
                for y=1,128 do
                    lines[y]=content[y];foreground[y]=Gui.pack(fg[y]);background[y]=Gui.pack(string.rep("f",256))
                    equal(#lines[y],256);assert(not lines[y]:find("[A-Za-z]"))
                end
                local packet={type="render",clientId="monitor_12345:bottom",monitorId="monitor_12345:bottom",
                    serverSession="12345:12345",width=256,height=128,lines=lines,foreground=foreground,background=background,
                    colourFormat="rle1",frameId=100000,inputRevision=100000,protocol="SmartHomeOS/1",networkId="home",
                    sender=12345,recipient=12346,_transport={version=1,boot=12345,sequence=1000000,channel=45231,serverChannel=45231,path={}}}
                assert(#serialize(packet)<61440,"Matrix frame cannot be sent after a seed/time change")
            end
        end
    end
    function tests.screensaver_matrix_wall_delivers_faster_animation_to_the_real_monitor_client()
        local t=setup("screensaver",false,{monitorWidth=128,monitorHeight=48})
        touch(t,"top",t.top.width-1,2);equal(t.view().design,2)
        t.advance(.6)
        local first=#t.bus.wire;t.advance(1)
        local frames=0
        for i=first+1,#t.bus.wire do
            local packet=t.bus.wire[i]
            if packet.sender==t.central and packet.channel~=65533 and packet.message.type=="render"
                and packet.message.clientId=="monitor_13:top" then
                frames=frames+1;assert(#packet.raw<61440)
            end
        end
        assert(frames>=7,"Matrix wall should deliver the reference eight updates per simulated second")
        assert(t.window());assert(not t.central.disk.files["diagnostics_os_error.txt"],table.concat(t.central.log,"\n"))
    end
    function tests.screensaver_nyan_preserves_sprite_height_and_white_eye_pixels_on_large_windows()
        local t=setup("screensaver",true); assert(t.app.onOpen(t.state,t.api,t.context()));t.view().design=9
        local lines=t.content(nil,92,32); local first,last,white=32,1,false
        for _,style in ipairs(lines.styles) do
            if style.bg==32768 then first=math.min(first,style.y); last=math.max(last,style.y+style.height-1) end
            if style.bg==1 then white=true end
        end
        assert(last-first>=10,"The Nyan sprite must not flatten with large-frame grouping");assert(white,"Nyan eye pixels must remain white")
    end
    function tests.screensaver_exit_tap_stays_on_its_monitor_and_never_reaches_underlying_controls()
        local t=setup("screensaver",false,{noOpen=true}); local normal=t.open("top","solar_farm")
        local before=serialize(t.central.server.views[normal]); local left=t.open("left")
        t.id=t.open(); touch(t,"top",5,1); equal(t.window(),nil)
        equal(serialize(t.central.server.views[normal]),before); assert(t.window(left))
        t.id=t.open(); touch(t,"top",1,t.top.height); equal(t.window(),nil); assert(t.window(left))
    end

    function tests.start_menu_sorts_displayed_titles_alphabetically_including_os_settings()
        local bus=newBus(); local sources={}
        for name,title in pairs({zebra="Alpha",alpha="zebra",middle="beta"}) do sources["apps_"..name..".lua"]='return {title="'..title..'",minWidth=2,minHeight=2,render=function() return {} end}' end
        local central=bus.computer(10,"server",{apps=sources}):start(); local screen=monitor(60,24)
        local display=bus.computer(13,"monitor",{monitors={top=screen}}):start(); bus.advance(2)
        central.server.refreshMonitors(true); bus.pump(); bus.queue(display,{"monitor_touch","top",1,24}); bus.pump(); central.server.refreshMonitors(true); bus.pump()
        local model=central.server.monitors["monitor_13:top"]; local labels={}
        assert(model.launcher)
        for _,hit in ipairs(model.menuHits) do if hit.item and hit.item.value then labels[#labels+1]=hit.item.label end end
        equal(table.concat(labels,","),"Alpha,beta,OS settings,zebra")
    end
end
