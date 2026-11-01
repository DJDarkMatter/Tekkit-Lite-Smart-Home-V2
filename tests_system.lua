-- Read-only diagnostics across all device roles and real monitor navigation.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local function read(path) local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s end
    local source=read("apps_system.lua")
    local function setup()
        local bus=newBus()
        local central=bus.computer(10,"server",{apps={["apps_system.lua"]=source,["apps_clock.lua"]=read("apps_clock.lua")}}):start()
        local bridge=bus.computer(11,"io",{modemSide="right"}):start()
        local sensor=bus.computer(14,"sensor",{sensors={top={card="openccsensors.item.industrialcraftsensor",
            targets={["1,0,0"]={Name="Core 1",RawName="ic2.reactor"}},details={["1,0,0"]={Heat=42,MaxHeat=10000,Active=false,Output=0}}}}}):start()
        local relay=bus.computer(15,"relay"):start()
        local screen=monitor(64,26); local display=bus.computer(13,"monitor",{monitors={top=screen}}):start()
        local t={bus=bus,central=central,bridge=bridge,sensor=sensor,relay=relay,screen=screen,display=display}
        function t.reload() t.api,t.app,t.state=central.server.api,central.server.apps.system,central.server.state.appStates.system end
        t.reload()
        function t.view() return central.server.views[t.id] end
        function t.content()
            local win=central.server.state.windows[t.id]
            return t.app.render(win.width-2,win.height-2,t.state,t.api,{appName="system",windowId=t.id,view=t.view()})
        end
        function t.paint() central.server.refreshMonitors(true); bus.pump() end
        function t.click(action,value)
            for _=1,80 do
                t.paint(); local nextHit,previous
                for _,hit in ipairs(t.content().hits) do if hit.enabled~=false then
                    if hit.action==action and (value==nil or hit.value==value) then
                        local win=central.server.state.windows[t.id]
                        bus.queue(display,{"monitor_touch","top",win.x+hit.x1,win.y+(hit.y or hit.y1)}); bus.pump(); return
                    end
                    if hit.action=="page" and hit.value.page>t.view().pages[hit.value.key] then nextHit=hit end
                    if hit.action=="page" and hit.value.page<t.view().pages[hit.value.key] then previous=hit end
                end end
                local hit=nextHit or previous; if not hit then break end
                local win=central.server.state.windows[t.id]
                bus.queue(display,{"monitor_touch","top",win.x+hit.x1,win.y+hit.y}); bus.pump()
            end
            error("Missing system action "..action.." on "..tostring(t.view().screen))
        end
        function t.text() return table.concat(t.content(),"\n") end
        bus.advance(2); t.id=assert(t.api.openApp("system","monitor_13:top")); t.paint()
        return t
    end
    function tests.system_overview_lists_original_devices_sensor_cards_targets_apps_windows_and_output_confirmations()
        local t=setup()
        local d=t.api.getDiagnostics(); equal(#d.clients,4); equal(#d.io,1); equal(#d.sensors,1); equal(#d.windows,1); equal(#d.apps,2)
        equal(d.system.computerId,10); equal(d.system.modemSide,"back"); equal(d.system.channel,45231)
        t.click("clients"); for _,id in ipairs({"io_11","sensor_14","relay_15","monitor_13:top"}) do assert(t.text():find(id,1,true),id) end
        t.click("client","sensor_14"); assert(t.text():find("industrialcraftsensor",1,true))
        t.click("targets"); t.click("target"); assert(t.text():find("Core 1",1,true)); assert(t.text():find("1,0,0",1,true))
        equal(#t.sensor.client.watches,0,"Overview never starts sensor polls")
        t.view().screen="home"; t.click("apps"); assert(t.text():find("Clock",1,true)); assert(t.text():find("background",1,true))
        t.view().screen="home"; t.click("windows"); assert(t.text():find("monitor_13:top",1,true))
        assert(t.api.mapOutput("test_lamp","io_11","front",1,true)); t.bus.advance(1)
        t.view().screen="home"; t.click("outputs"); t.click("output","test_lamp")
        assert(t.text():find("White",1,true)); assert(t.text():find("Acknowledged: Yes",1,true))
        t.bridge.active=false; t.bus.advance(16); t.view().screen="clients"; assert(t.text():find("Offline",1,true))
        local fresh=t.api.getDiagnostics(); fresh.io[1].sides[1]="invalid"; fresh.clients[1].id="bad"; fresh.sensors[1].ports[1].card="bad"
        local again=t.api.getDiagnostics(); assert(again.io[1].sides[1]~="invalid"); assert(again.sensors[1].ports[1].card~="bad")
    end
    function tests.system_overview_filters_and_window_navigation_persist_without_saving_live_client_observations()
        local t=setup(); t.click("clients"); t.click("filter"); equal(t.state.filter,"io")
        assert(t.text():find("io_11",1,true)); assert(not t.text():find("sensor_14",1,true))
        t.click("client","io_11"); assert(t.api.save())
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.system.filter,"io"); equal(saved.appStates.system.clients,nil); equal(saved.windows[t.id].viewState.clientId,"io_11")
        t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start()
        equal(t.central.server.state.appStates.system.filter,"io"); equal(t.central.server.views[t.id].screen,"client")
        equal(#t.central.server.api.getClients(),0,"Restored app choices do not fabricate online devices")
    end
    function tests.system_overview_all_pages_fit_the_smallest_window_and_do_not_change_outputs_or_sensor_watches()
        local t=setup()
        assert(t.api.mapOutput("manual","io_11","front",1,true)); t.bus.advance(1)
        local before=serialize(t.central.server.state.outputMap)
        for _,size in ipairs({{12,6},{13,7},{24,10},{38,14},{50,20},{79,30}}) do
            for _,screen in ipairs({"home","central","clients","sensors","client","targets","target","outputs","output","apps","windows","settings","about"}) do
                local view={screen=screen,pages={},clientId="sensor_14",target={side="top",key="1,0,0"},output="manual"}
                local lines=t.app.render(size[1],size[2],t.state,t.api,{appName="system",windowId=t.id,view=view})
                equal(#lines,size[2]); for _,line in ipairs(lines) do equal(#line,size[1]) end
                local occupied={}
                for _,hit in ipairs(lines.hits) do
                    assert(hit.x1>=1 and hit.x2<=size[1] and hit.y>=1 and hit.y<=size[2])
                    for x=hit.x1,hit.x2 do local key=x..":"..hit.y; assert(not occupied[key],screen.." overlapping controls"); occupied[key]=true end
                end
                for _,style in ipairs(lines.styles) do assert(style.x>=1 and style.y>=1 and style.x+style.width-1<=size[1] and style.y+style.height-1<=size[2]) end
            end
        end
        equal(serialize(t.central.server.state.outputMap),before); equal(t.api.getOutput("manual"),true); equal(#t.sensor.client.watches,0)
    end
end
