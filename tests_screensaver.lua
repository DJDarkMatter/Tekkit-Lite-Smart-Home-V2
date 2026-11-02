return function(tests,newBus,monitor,serialize,unserialize,equal)
    local Gui=dofile("lib_gui.lua")
    local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
    local function touch(t,side,x,y) t.bus.queue(t.display,{"monitor_touch",side,x,y}); t.bus.pump(); t.paint() end
    function tests.screensaver_never_autostarts_and_explicit_open_is_always_fullscreen()
        local t=setup("screensaver",false,{noOpen=true}); equal(t.central.server.running.screensaver,nil)
        t.id=t.open(); local w=t.window(); equal(w.fullscreen,true); equal(w.x,1); equal(w.y,1); equal(w.width,t.top.width); equal(w.height,t.top.height)
        equal(t.central.server.monitors["monitor_13:top"].fullscreen,t.id); equal(t.central.server.nextTickInterval(),.2)
        equal(t.api.placeWindow(t.id,2,2,20,10),false)
        touch(t,"top",t.top.width,1); equal(t.window(),nil); equal(t.central.server.running.screensaver,nil); equal(t.central.server.nextTickInterval(),.5)
    end
    function tests.screensaver_top_left_cycles_and_every_new_open_rotates_saved_design()
        local t=setup("screensaver"); equal(t.view().design,1); touch(t,"top",1,1); equal(t.view().design,2)
        assert(t.api.closeWindow(t.id)); t.id=t.open(); equal(t.view().design,3)
        local left=t.open("left"); equal(t.view(left).design,4); equal(t.view().design,3)
        touch(t,"left",1,1); equal(t.view(left).design,5); equal(t.view().design,3)
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
        t.ack(); equal(t.popup(),nil); assert(t.window()); touch(t,"top",t.top.width,1); equal(t.window(),nil)
    end
    function tests.screensaver_all_patterns_animate_fit_tiny_screens_and_keep_large_frames_under_modem_limit()
        local t=setup("screensaver",true); assert(t.app.onOpen(t.state,t.api,t.context()))
        for design=1,8 do
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
        t.central.disk.failWrite=true; touch(t,"top",1,1); equal(t.view().design,old); equal(t.state.nextDesign,nextIndex)
        local id=t.api.openApp("screensaver","monitor_13:left"); equal(id,nil); assert(t.window()); equal(t.state.nextDesign,nextIndex)
        t.central.disk.failWrite=false; touch(t,"top",1,1); equal(t.view().design,old+1)
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
