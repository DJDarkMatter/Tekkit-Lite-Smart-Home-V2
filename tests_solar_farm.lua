-- Solar farm measurement math plus real OS/sensor/IO/monitor integration.
return function(tests,newBus,monitor,serialize,unserialize,equal,githubFile)
    local function read(path) local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s end
    local source=read("apps_solar_farm.lua")
    local function setup(unit)
        local t={now=0,sequence=0,boot=1,unit=unit}
        t.main={{Name="UU Matter",RawName="ic2.matter",DamageValue=0,Size=200000},
            {Name="HV Solar",RawName="solar.hv",DamageValue=0,Size=1000},
            {Name="LV Solar",RawName="solar.lv",DamageValue=0,Size=40},
            {Name="Iron Ingot",RawName="item.iron",DamageValue=0,Size=37389404}}
        t.farm={{Name="UU Matter",RawName="ic2.matter",DamageValue=0,Size=5000},
            {Name="LV Solar",RawName="solar.lv",DamageValue=0,Size=64},
            {Name="Minium Shard",RawName="item.minium",DamageValue=0,Size=32}}
        t.data={main={Powered=true,UsedBytes=1024,FreeBytes=3072,FreeCount=16384,Items=t.main},
            farm={Powered=true,UsedBytes=512,FreeBytes=512,FreeCount=4096,Items=t.farm}}
        if unit then
            local env=setmetatable({},{__index=_G})
            t.app=assert(loadstring(source)); setfenv(t.app,env); t.app=t.app()
            t.state={}; t.views={[1]={}}; t.outputs={}; t.notifications={}
            local api={aeItemProfiles=true,ui=dofile("lib_gui.lua"),getAppColour=function() return 2048 end,
                getSensorClients=function() return {{id="sensor_14",bootId=t.boot}} end,
                watchSensor=function() end,unwatchSensor=function() end,getOutputs=function() return {} end,
                getOutput=function(name) return t.outputs[name]==true end}
            function api.getSensorReading(binding)
                return {status=t.offline and "offline" or "ok",error=t.offline and "Sensor offline" or nil,
                    time=t.now,age=0,sequence=t.sequence,dataSequence=t.sequence,data=t.data[binding.target]}
            end
            function api.updateOutputs(changes)
                if t.failSave then return false,"Simulated save failure" end
                assert(#changes==0,"Rate unit fixture must never touch outputs")
                t.saved=serialize(t.state); return true
            end
            function api.setNotifications(_,entries) t.notifications=entries; return true end
            function api.invalidateAppViews() end
            t.api=api; t.app.init(t.state,api,{appName="solar_farm"})
            t.state.sources={main={clientId="sensor_14",side="top",target="main"},farm={clientId="sensor_14",side="top",target="farm"}}
            function t.paint() end
            function t.view(id) return t.views[id or 1] end
            function t.window() return {width=56,height=22} end
            function t.advance(seconds)
                t.now,t.sequence=t.now+seconds,t.sequence+1
                t.app.background(seconds,t.state,t.api)
            end
        else
            t.bus=newBus()
            t.central=t.bus.computer(10,"server",{apps={["apps_solar_farm.lua"]=source}}):start()
            t.card={card="openccsensors.item.appliedenergisticssensor",targets={main={Name="ME Wireless Access Point"},farm={Name="ME Wireless Access Point"}},details=t.data}
            t.sensor=t.bus.computer(14,"sensor",{sensors={top=t.card}}):start()
            t.bridge=t.bus.computer(11,"io",{modemSide="right"}):start()
            t.top,t.left=monitor(64,26),monitor(15,10)
            t.display=t.bus.computer(13,"monitor",{monitors={top=t.top,left=t.left}}):start()
            function t.reload()
                t.api,t.app,t.state=t.central.server.api,t.central.server.apps.solar_farm,t.central.server.state.appStates.solar_farm
            end
            t.reload()
            function t.paint() t.central.server.refreshMonitors(true); t.bus.pump() end
            function t.view(id) return t.central.server.views[id or t.id] end
            function t.window(id) return t.central.server.state.windows[id or t.id] end
            function t.advance(seconds) t.bus.advance(seconds) end
            function t.open(side)
                local id=assert(t.api.openApp("solar_farm","monitor_13:"..(side or "top"),1,1)); t.paint(); return id
            end
            function t.popup(side) t.paint(); return t.central.server.monitors["monitor_13:"..(side or "top")].notification end
            function t.ack(side)
                local p=assert(t.popup(side)); t.bus.queue(t.display,{"monitor_touch",side or "top",p.ok.x1,p.ok.y}); t.bus.pump()
            end
            function t.reboot()
                t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start(); t.reload(); t.advance(6); t.paint()
            end
            t.advance(2); t.id=t.open()
        end
        t.id=t.id or 1
        function t.context(id) return {appName="solar_farm",windowId=id or t.id,view=t.view(id)} end
        function t.content(id,w,h)
            local win=t.window(id); local inset=win.fullscreen and 0 or 2
            return t.app.render(w or win.width-inset,h or win.height-inset,t.state,t.api,t.context(id))
        end
        function t.text(id) return table.concat(t.content(id),"\n") end
        function t.click(action,value,id)
            id=id or t.id
            for _=1,150 do
                t.paint()
                local dialog=not unit and t.central.server.dialogs[id]
                local hits=dialog and dialog.hits or t.content(id).hits
                local nextHit
                for _,hit in ipairs(hits or {}) do if hit.enabled~=false then
                    local v=type(hit.value)=="table" and hit.value.value or hit.value
                    if hit.action==action and (value==nil or type(value)=="function" and value(hit.value) or v==value) then
                        local x,y=math.floor((hit.x1+hit.x2)/2),hit.y or hit.y1
                        if unit then t.app.handleTouch(x,y,54,20,t.state,t.api,t.context(id))
                        else
                            local win=t.window(id); local inset=win.fullscreen and 0 or 1
                            t.bus.queue(t.display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+inset+x-1,win.y+inset+y-1}); t.bus.pump()
                        end
                        return
                    end
                    if hit.action=="next" or hit.action=="page" and hit.value.value>(t.view(id).pages[hit.value.key] or 1) then nextHit=hit end
                end end
                if not nextHit then break end
                local x,y=nextHit.x1,nextHit.y
                if unit then t.app.handleTouch(x,y,54,20,t.state,t.api,t.context(id))
                else local win=t.window(id); local inset=win.fullscreen and 0 or 1
                    t.bus.queue(t.display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+inset+x-1,win.y+inset+y-1}); t.bus.pump() end
            end
            error("Missing solar action "..action.." on "..tostring(t.view(id).screen))
        end
        function t.configure()
            if unit then t.advance(2); t.advance(2); return end
            for _,role in ipairs({"main","farm"}) do
                t.view().screen="sources"; t.click("source",role); t.click("select","sensor_14"); t.click("select","top"); t.click("select",role); t.click("use")
            end
            t.advance(5)
        end
        function t.pin(raw)
            t.view().screen="settings"; t.click("pin"); t.click("selectItem",function(v) return v.raw==raw end)
            return t.state.metrics[#t.state.metrics]
        end
        function t.sums(metric)
            local delta,seconds=0,0
            for _,row in ipairs(metric.history) do delta,seconds=delta+row[2],seconds+row[3] end
            return delta,seconds
        end
        function t.newAlarm(values,routeColor,dismissColor)
            t.view().screen="settings"; t.click("alarms"); t.click("addAlarm"); t.click("selectItem",function(v) return v.raw=="solar.lv" end)
            for k,v in pairs(values or {}) do t.view().alarmDraft[k]=v end
            if routeColor then t.click("route"); t.click("select","io_11"); t.click("select","front"); t.click("select",routeColor); t.click("use") end
            if dismissColor then t.click("dismissInput"); t.click("select","io_11"); t.click("select","back"); t.click("select",dismissColor); t.click("use") end
            t.click("saveAlarm"); return t.state.alarms[#t.state.alarms]
        end
        return t
    end
    function tests.solar_farm_sources_are_independently_selected_and_share_existing_ae_item_feeds()
        local t=setup(); equal(t.central.server.running.solar_farm,true)
        t.configure()
        equal(t.state.sources.main.target,"main"); equal(t.state.sources.farm.target,"farm")
        equal(#t.sensor.client.watches,2)
        for _,watch in ipairs(t.sensor.client.watches) do equal(watch.profile,"ae_items") end
        t.view().screen="sourceInfo"
        assert(t.text():find("37 590 444",1,true))
        equal(next(t.central.server.state.outputMap),nil); equal(#t.sensor.redstoneWrites,0)
    end
    function tests.solar_farm_rates_keep_small_consumption_ignore_large_player_drops_and_rebase_without_a_recovery_spike()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv"); t.advance(2)
        t.main[2].Size=1010; t.advance(2)
        equal(t.sums(m),10)
        t.main[2].Size=700; t.advance(2)
        equal(t.sums(m),10); equal(m.ignored,1); equal(m.omitted,310)
        t.main[2].Size=704; t.advance(2); equal(t.sums(m),14)
        t.main[2].Size=700; t.advance(2); equal(t.sums(m),10)
        local delta,seconds=t.sums(m); equal(seconds,8); equal(delta/seconds*3600,4500)
        t.view().screen="itemInfo"; assert(t.text():find("Excluded events: 1",1,true))
    end
    function tests.solar_farm_global_and_per_item_drop_filters_distinguish_large_uu_stocks_and_small_hv_stocks()
        local t=setup(true); t.configure(); local uu=t.pin("ic2.matter"); local hv=t.pin("solar.hv"); t.advance(2)
        t.main[1].Size=199936; t.main[2].Size=900; t.advance(2)
        equal(t.sums(uu),-64); equal(uu.ignored,0); equal(hv.ignored,1)
        t.view().metricId=uu.id; t.view().selectedItem=uu.item; t.view().screen="metricEdit"
        t.click("metricField","dropPercent"); t.view().number.draft="0"; t.click("setNumber")
        t.click("metricField","dropCount"); t.view().number.draft="1"; t.click("setNumber")
        equal(uu.dropCount,1); equal(uu.dropPercent,0); equal(t.state.settings.dropCount,64)
        t.advance(2); t.main[1].Size=199935; t.advance(2)
        equal(uu.ignored,1); equal(t.sums(uu),0)
    end
    function tests.solar_farm_duplicate_reads_outages_source_restarts_and_large_sample_gaps_never_create_production()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv"); t.advance(2)
        t.main[2].Size=1010; t.advance(2); equal(t.sums(m),10)
        local _,seconds=t.sums(m)
        for _=1,8 do t.app.background(0.5,t.state,t.api) end
        local _,after=t.sums(m); equal(after,seconds,"A cached sample cannot increase measured time")
        t.offline=true; t.advance(2); t.main[2].Size=1000000
        t.view().screen="item"; assert(t.text():find("--",1,true))
        t.offline=false; t.advance(2); equal(t.sums(m),10)
        t.main[2].Size=1000002; t.advance(2); equal(t.sums(m),12)
        t.boot=2; t.main[2].Size=2000000; t.advance(2); equal(t.sums(m),12)
        t.main[2].Size=3000000; t.advance(30); equal(t.sums(m),12)
        t.main[2].Size=3000001; t.advance(2); equal(t.sums(m),13)
    end
    function tests.solar_farm_complete_absence_is_zero_but_unpowered_or_incomplete_lists_are_unknown()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv"); t.advance(2)
        t.view().screen="itemInfo"; assert(t.text():find("Farm: 0",1,true))
        t.data.farm.Powered=false; t.advance(2)
        assert(t.text():find("Farm: --",1,true))
        t.data.farm.Powered=true; t.data.farm.ItemsOmitted=true; t.advance(2)
        assert(t.text():find("Farm: --",1,true))
        t.data.farm.ItemsOmitted=nil; t.advance(2); assert(t.text():find("Farm: 0",1,true))
    end
    function tests.solar_farm_history_is_bounded_plain_numeric_and_keeps_only_valid_sampled_time()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv")
        for _=1,1900 do t.main[2].Size=t.main[2].Size+1; t.advance(2) end
        equal(#m.history,60)
        assert(m.history[1][1]>=math.floor(t.state.elapsed/60)-59)
        t.view().screen="itemInfo"; assert(not t.text():find("[Ee][+-]%d"))
        local saved=serialize(t.state); assert(#saved<20000); assert(not saved:find('"Powered"',1,true))
    end
    function tests.solar_farm_item_lists_sort_search_and_keep_rows_stable_until_refresh()
        local t=setup(true); t.configure(); t.view().screen="home"; t.click("stocks")
        local rows=t.content().hits; local first
        for _,hit in ipairs(rows) do if hit.action=="selectItem" then first=hit.value.raw; break end end
        equal(first,"ic2.matter")
        t.farm[1].Size=1; t.farm[2].Size=100000; t.advance(2)
        local stable
        for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then stable=hit.value.raw; break end end
        equal(stable,first)
        t.click("filters"); t.click("refresh")
        for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then equal(hit.value.raw,"solar.lv"); break end end
        t.click("filters"); t.click("search"); t.view().keyboard.draft="minium"; t.click("saveText")
        local selected=0; for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then equal(hit.value.raw,"item.minium"); selected=selected+1 end end
        equal(selected,1)
    end
    function tests.solar_farm_manual_absent_items_keep_raw_identity_and_can_be_pinned_or_used_for_either_me_alarm()
        local t=setup(true); t.configure(); t.view().screen="home"; t.click("pin"); t.click("filters"); t.click("newManual")
        t.view().manual={raw="solar.future",name="Future panel",damage=7}; t.click("saveManual")
        local m=t.state.metrics[1]
        equal(m.item.raw,"solar.future"); equal(m.item.damage,7); assert(t.state.catalog[m.item.key])
        t.view().screen="itemInfo"; assert(t.text():find("Farm: 0",1,true)); assert(t.text():find("Main: 0",1,true))
    end
    function tests.solar_farm_saved_sources_pins_navigation_and_history_restore_without_replaying_stock_differences()
        local t=setup(); t.configure(); local m=t.pin("solar.hv"); t.advance(3)
        t.main[2].Size=1010; t.advance(3); local delta=t.sums(m); equal(delta,10)
        t.view().screen="itemInfo"; assert(t.api.save())
        local id=m.id; t.main[2].Size=999999; t.reboot(); m=t.state.metrics[1]
        equal(m.id,id); equal(t.sums(m),delta); equal(t.view().screen,"itemInfo")
        equal(t.state.sources.main.target,"main"); equal(t.state.sources.farm.target,"farm")
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.solar_farm.catalog[m.item.key].raw,"solar.hv")
    end
    function tests.solar_farm_buildup_popups_and_infinite_patterns_dismiss_on_fresh_selected_redstone_edges()
        local t=setup(); t.configure()
        local a=t.newAlarm({threshold=60,reset=20,hold=1,signal={kind="pattern",on=1,off=1,total=0}},1,2)
        t.advance(2); assert(a.alert); assert(t.popup()); equal(t.api.getOutput("solar_farm_alarm_"..a.id),true)
        t.advance(1); equal(t.api.getOutput("solar_farm_alarm_"..a.id),false)
        t.advance(1); equal(t.api.getOutput("solar_farm_alarm_"..a.id),true)
        t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump()
        t.advance(1); equal(a.alert,nil); equal(t.popup(),nil); equal(t.api.getOutput("solar_farm_alarm_"..a.id),false)
        t.advance(5); equal(a.alert,nil,"Acknowledging high stock must not immediately raise another popup")
        t.farm[2].Size=10; t.advance(3); equal(a.latched,false)
        t.farm[2].Size=64; t.advance(4); assert(a.alert)
        t.ack(); equal(a.alert,nil)
        for i=2,#t.bridge.redstoneWrites do
            local b,c=t.bridge.redstoneWrites[i-1],t.bridge.redstoneWrites[i]
            if b.side==c.side then assert(c.time-b.time>=0.5-0.000001) end
        end
    end
    function tests.solar_farm_finite_constant_signal_stops_while_popup_waits_for_ok_and_service_runs_without_windows()
        local t=setup(); t.configure()
        local a=t.newAlarm({threshold=60,reset=20,hold=1,signal={kind="constant",on=2,off=1,total=0}},1)
        assert(t.api.closeWindow(t.id)); equal(t.central.server.running.solar_farm,true)
        t.advance(2); assert(a.alert); assert(a.ring); assert(t.popup())
        t.advance(3); equal(a.ring,nil); assert(a.alert); equal(t.api.getOutput("solar_farm_alarm_"..a.id),false)
        t.ack("left"); equal(a.alert,nil); equal(t.popup(),nil)
    end
    function tests.solar_farm_failed_trigger_or_ack_saves_do_not_change_physical_intent_or_lose_popups()
        local t=setup(); t.configure()
        local a=t.newAlarm({threshold=60,reset=20,hold=3},1)
        t.central.disk.failWrite=true; t.advance(4)
        equal(t.state.alarms[1].alert,nil); equal(t.api.getOutput("solar_farm_alarm_"..a.id),false); equal(t.popup(),nil)
        t.central.disk.failWrite=false; t.advance(1); a=t.state.alarms[1]; assert(a.alert); assert(t.popup())
        t.central.disk.failWrite=true; t.ack(); assert(t.state.alarms[1].alert); assert(t.popup())
        equal(t.api.getOutput("solar_farm_alarm_"..a.id),true)
        t.central.disk.failWrite=false; t.ack(); equal(t.state.alarms[1].alert,nil); equal(t.popup(),nil)
    end
    function tests.solar_farm_pending_alarms_survive_restart_and_preexisting_high_inputs_do_not_auto_dismiss()
        local t=setup(); t.configure(); t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump()
        local a=t.newAlarm({source="main",threshold=30,reset=10,hold=1},1,2)
        t.advance(2); assert(a.alert); assert(t.api.save()); local occurrence=a.alert.id
        t.reboot(); a=t.state.alarms[1]; equal(a.alert.id,occurrence); assert(t.popup())
        t.bridge.bundledInputs.back=0; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.advance(1)
        t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.advance(1)
        equal(a.alert,nil); equal(t.popup(),nil)
    end
    function tests.solar_farm_filters_colours_and_sources_roll_back_failed_saves()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv"); t.advance(2)
        t.main[2].Size=1005; t.advance(2); local before=t.saved
        t.view().screen="settings"; t.click("settingField","dropCount"); t.view().number.draft="1024"; t.failSave=true; t.click("setNumber")
        equal(t.saved,before); equal(t.state.settings.dropCount,64); equal(t.sums(t.state.metrics[1]),5); equal(t.view().screen,"message")
        t.failSave=false; t.view().screen="settings"; t.click("theme","background"); t.click("colour",1); t.click("savePalette")
        equal(t.state.settings.background,1)
    end
    function tests.solar_farm_shared_alarm_wires_remain_on_until_the_last_pending_alarm_is_acknowledged()
        local t=setup(); t.configure()
        local a=t.newAlarm({source="farm",threshold=60,reset=20,hold=1},1)
        local b=t.newAlarm({source="main",threshold=30,reset=10,hold=1},1)
        t.advance(2); assert(a.alert and b.alert)
        equal(t.api.getOutput("solar_farm_alarm_"..a.id),true)
        t.ack(); equal(a.alert,nil); assert(b.alert)
        equal(t.api.getOutput("solar_farm_alarm_"..b.id),true)
        t.ack(); equal(b.alert,nil); equal(t.api.getOutput("solar_farm_alarm_"..a.id),false)
    end
    function tests.solar_farm_alarm_hold_requires_continuous_fresh_stock_and_does_not_assume_outage_time_was_high()
        local t=setup(); t.configure()
        local a=t.newAlarm({threshold=60,reset=20,hold=10})
        t.advance(5); equal(a.alert,nil)
        t.data.farm.Powered=false; t.advance(4); equal(a.alert,nil)
        t.data.farm.Powered=true; t.advance(7); equal(a.alert,nil)
        t.advance(6); assert(a.alert); t.ack()
    end
    function tests.solar_farm_concurrent_alarm_drafts_do_not_overwrite_newer_settings_or_create_invalid_routes()
        local t=setup(); t.configure()
        local a=t.newAlarm({enabled=false})
        local other=t.open("left"); t.view(other).screen,t.view(other).alarmId="alarm",a.id
        t.click("editAlarm",nil,other)
        t.view().screen,t.view().alarmId="alarm",a.id; t.click("editAlarm")
        t.view().alarmDraft.hold=42; t.click("saveAlarm"); equal(a.hold,42)
        t.view(other).alarmDraft.hold=3; t.click("saveAlarm",nil,other)
        equal(a.hold,42); equal(t.view(other).screen,"message")
        t.view().screen="alarm"; t.click("editAlarm")
        t.view().alarmDraft.route={clientId="io_11",side="right",color=1}; t.click("saveAlarm")
        equal(t.state.alarms[1].route,nil); equal(next(t.central.server.state.outputMap),nil)
    end
    function tests.solar_farm_fullscreen_small_monitor_keeps_dashboard_and_settings_controls_interactive()
        local t=setup(); t.configure(); t.pin("solar.hv")
        local small=t.open("left"); assert(t.api.layoutWindow(small,"fullscreen")); t.paint()
        equal(#t.content(small),10)
        assert(table.concat(t.left.lines,"\n"):find("HV Solar",1,true))
        t.click("settings",nil,small); equal(t.view(small).screen,"settings")
        t.click("sources",nil,small); equal(t.view(small).screen,"sources")
        t.bus.queue(t.display,{"monitor_touch","left",15,1}); t.bus.pump()
        equal(t.window(small).fullscreen,nil); equal(t.view(small).screen,"sources")
    end
    function tests.solar_farm_all_item_lists_preserve_damage_variants_sum_equivalent_stacks_and_show_plain_large_counts()
        local t=setup(true); t.configure()
        t.data.farm.Items={{RawName="item.part",Name="Part",DamageValue=1,Size=37389404},
            {RawName="item.part",Name="Part",DamageValue=1,Size=5},{RawName="item.part",Name="Part",DamageValue=2,Size=2}}
        t.advance(2); t.view().screen="home"; t.click("stocks")
        local text=t.text(); assert(text:find("37 389 409",1,true)); assert(text:find("Part [1]",1,true)); assert(text:find("Part [2]",1,true))
        local n=0; for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then n=n+1 end end
        equal(n,2)
    end
    function tests.solar_farm_responsive_screens_keep_all_styles_and_touch_regions_inside_content_without_overlap()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv")
        local a=t.newAlarm({enabled=false})
        local screens={"home","items","filters","item","itemInfo","metricEdit","manual","sources","sourceInfo","alarms",
            "alarm","alarmEdit","alarmInfo","deleteAlarm","settings","number","keyboard","palette","about","confirm","message"}
        for _,w in ipairs({12,15,24,32,54,78}) do for _,h in ipairs({6,7,10,14,20}) do for _,screen in ipairs(screens) do
            t.views[1]={screen=screen,metricId=m.id,selectedItem=unserialize(serialize(m.item)),alarmId=a.id,
                browse={role="farm"},alarmDraft=unserialize(serialize(a)),manual={raw="item.future",name="Future",damage=0},
                number={target="metric",key="dropCount",draft="64",back="metricEdit"},
                keyboard={target="manual",key="name",draft="Future",original="Future",bank=0,page=1,back="manual",limit=24},
                palette={target="background",value=1,back="settings"},confirm="reset",message="Test",messageBack="settings"}
            local lines=t.content(1,w,h)
            equal(#lines,h)
            for _,line in ipairs(lines) do equal(#line,w,"Line width on "..screen) end
            for _,style in ipairs(lines.styles or {}) do
                assert(style.x>=1 and style.y>=1 and style.width>=1 and style.height>=1
                    and style.x+style.width-1<=w and style.y+style.height-1<=h,"Style escapes "..screen.." "..w.."x"..h)
            end
            for i,hit in ipairs(lines.hits or {}) do
                assert(hit.x1>=1 and hit.x2<=w and (hit.y1 or hit.y)>=1 and (hit.y2 or hit.y)<=h,"Hit escapes "..screen)
                for j=i+1,#lines.hits do
                    local other=lines.hits[j]
                    assert(hit.x2<other.x1 or other.x2<hit.x1 or (hit.y2 or hit.y)<(other.y1 or other.y)
                        or (other.y2 or other.y)<(hit.y1 or hit.y),"Overlapping controls on "..screen.." "..w.."x"..h)
                end
            end
        end end end
    end
    function tests.solar_farm_installs_from_github_with_the_existing_v28_installer_and_starts_without_a_window()
        local bus=newBus(); local comp=bus.computer(10,"server")
        comp.env.shell={dir=function() return "" end}
        local install=assert(comp.env.loadfile("install.lua")); install("server")
        equal(comp.disk.files["apps_solar_farm.lua"],nil,"Core installation must not bundle user apps")
        local downloads=0
        comp.env.http={get=function(url)
            assert(url:find("api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_solar_farm.lua",1,true))
            downloads=downloads+1
            return {getResponseCode=function() return 200 end,readAll=function() return githubFile("apps_solar_farm.lua",source) end,close=function() end}
        end}
        install("app","solar_farm")
        equal(downloads,1); equal(comp.disk.files["apps_solar_farm.lua"],source)
        equal(unserialize(comp.disk.files["configs_os.txt"]).enabledApps.solar_farm,true)
        comp:start(); bus.advance(1)
        equal(comp.server.running.solar_farm,true); equal(next(comp.server.state.windows),nil)
        equal(comp.server.state.appStates.solar_farm.version,1)
        equal(next(comp.server.state.outputMap),nil)
    end
    function tests.solar_farm_details_and_validation_messages_return_to_their_editor_and_reselecting_a_source_keeps_history()
        local t=setup(true); t.configure(); local m=t.pin("solar.hv"); t.advance(2)
        t.main[2].Size=1010; t.advance(2); equal(t.sums(m),10)
        assert(t.app.handleSensorSelection("main",unserialize(serialize(t.state.sources.main)),t.state,t.api,t.context()))
        equal(t.sums(m),10,"Reselecting the same ME is not a source change")
        t.view().screen="item"; t.click("itemInfo"); t.click("item"); equal(t.view().screen,"item")
        t.click("metricEdit"); t.click("metricField","dropPercent"); t.view().number.draft="101"; t.click("setNumber")
        equal(t.view().screen,"message"); t.click("number"); equal(t.view().screen,"number")
        t.view().number.draft="0"; t.click("setNumber"); equal(t.view().screen,"metricEdit")
        t.click("metricName"); t.view().keyboard.draft=""; t.click("saveText")
        equal(t.view().screen,"message"); t.click("keyboard"); equal(t.view().screen,"keyboard")
        t.view().keyboard.draft="Finished HV"; t.click("saveText"); equal(t.view().screen,"metricEdit")
        equal(t.state.metrics[1].name,"Finished HV")
    end
end
