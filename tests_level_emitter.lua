return function(tests,newBus,monitor,serialize,unserialize,equal)
    local Me=dofile("lib_me.lua")
    local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
    local sensor={clientId="sensor_14",side="top",target="farm"}
    local item={raw="solar.lv",name="LV Solar",damage=0,key=Me.itemKey("solar.lv",0,"LV Solar")}
    local function rule(t,options,route,dismiss)
        t.view().screen="home"; assert(t.app.handleSensorSelection("new",sensor,t.state,t.api,t.context()))
        t.view().draft.item=Me.copy(item)
        for key,value in pairs(options or {}) do t.view().draft[key]=Me.copy(value) end
        if route then assert(t.app.handleIOSelection("signal",{clientId="io_11",side="front",color=route},t.state,t.api,t.context())) end
        if dismiss then assert(t.app.handleIOSelection("dismiss",{clientId="io_11",side="back",color=dismiss},t.state,t.api,t.context())) end
        t.view().screen="edit"; t.click("saveRule"); return t.state.rules[#t.state.rules]
    end
    function tests.level_emitter_under_over_exact_comparisons_and_rearm_boundaries()
        for _,case in ipairs({{"under",65,true},{"under",64,false},{"over",63,true},{"over",64,false},{"exact",64,true},{"exact",63,false}}) do
            local t=setup("level_emitter",true); local r=rule(t,{operator=case[1],threshold=case[2],reset=case[2]}); t.advance(1)
            equal(r.alert~=nil,case[3],case[1].." "..case[2])
            if r.alert then
                t.app.handleNotification(t.notifications[1].key,t.state,t.api); equal(r.alert,nil); t.advance(1); equal(r.alert,nil,"Acknowledgement must not retrigger the same level")
                t.farm[2].Size=case[1]=="under" and 66 or case[1]=="over" and 62 or 63; t.advance(1); equal(r.latched,false)
                t.farm[2].Size=64; t.advance(1); assert(r.alert)
            end
        end
    end
    function tests.level_emitter_complete_absence_matches_zero_but_offline_unpowered_and_partial_never_do()
        local t=setup("level_emitter",true); local absent={raw="item.future",name="Future",damage=3,key=Me.itemKey("item.future",3,"Future")}
        local r=rule(t,{operator="exact",threshold=0,item=absent,hold=2})
        t.offline=true; t.advance(5); equal(r.alert,nil)
        t.offline=false; t.data.farm.Powered=false; t.advance(5); equal(r.alert,nil)
        t.data.farm.Powered=true; t.data.farm.ItemsOmitted=true; t.advance(5); equal(r.alert,nil)
        t.data.farm.ItemsOmitted=nil; t.advance(1); t.advance(1); equal(r.alert,nil); t.advance(1); assert(r.alert)
    end
    function tests.level_emitter_holds_require_continuous_known_values_and_reset_on_sensor_boot()
        local t=setup("level_emitter",true); local r=rule(t,{operator="over",threshold=60,reset=60,hold=3})
        t.advance(1); t.advance(2); equal(r.alert,nil); t.offline=true; t.advance(1)
        t.offline=false; t.advance(1); t.advance(2); equal(r.alert,nil); t.boot=2; t.advance(1); t.advance(2); equal(r.alert,nil); t.advance(1); assert(r.alert)
    end
    function tests.level_emitter_constant_and_pattern_zero_duration_continue_until_ok()
        for _,signal in ipairs({{kind="constant",on=0,off=1,total=0},{kind="pattern",on=1,off=1,total=0}}) do
            local t=setup("level_emitter",true); local r=rule(t,{operator="over",threshold=60,reset=20,signal=signal},1)
            t.advance(1); assert(r.alert); equal(t.outputs.level_emitter_rule_1,true)
            t.advance(1); equal(t.outputs.level_emitter_rule_1,signal.kind=="constant")
            t.advance(99); assert(r.alert); assert(r.ring)
            assert(t.app.handleNotification(t.notifications[1].key,t.state,t.api)); equal(r.alert,nil); equal(r.ring,nil); equal(t.outputs.level_emitter_rule_1,false); equal(#t.notifications,0)
        end
    end
    function tests.level_emitter_finite_signals_stop_while_popup_waits_and_failed_saves_retry()
        local t=setup("level_emitter",true); local r=rule(t,{operator="over",threshold=60,reset=20,signal={kind="constant",on=2,off=1,total=0}},1)
        t.failSave=true; t.advance(1); equal(t.state.rules[1].alert,nil); equal(#t.notifications,0)
        t.failSave=false; t.advance(1); r=t.state.rules[1]; assert(r.alert); equal(t.outputs.level_emitter_rule_1,true)
        t.failSave=true; t.advance(3); r=t.state.rules[1]; assert(r.ring); equal(t.outputs.level_emitter_rule_1,true)
        t.failSave=false; t.advance(3); r=t.state.rules[1]; equal(r.ring,nil); assert(r.alert); equal(t.outputs.level_emitter_rule_1,false)
        t.failSave=true; equal(t.app.handleNotification(t.notifications[1].key,t.state,t.api),false); assert(t.state.rules[1].alert)
        t.failSave=false; assert(t.app.handleNotification(t.notifications[1].key,t.state,t.api)); equal(t.state.rules[1].alert,nil)
    end
    function tests.level_emitter_high_or_unknown_dismiss_input_needs_fresh_low_then_high()
        local t=setup("level_emitter",true); t.input=true
        local r=rule(t,{operator="over",threshold=60,reset=20},1,2); t.advance(1); assert(r.alert); t.advance(1); assert(r.alert)
        t.input=false; t.advance(1); t.input=nil; t.advance(1); t.input=true; t.advance(1); assert(r.alert)
        t.input=false; t.advance(1); t.input=true; t.advance(1); equal(r.alert,nil); equal(t.outputs.level_emitter_rule_1,false)
    end
    function tests.level_emitter_real_sensor_output_popup_dismissal_and_background_survive_closed_windows()
        local t=setup("level_emitter"); local r=rule(t,{operator="over",threshold=60,reset=20,hold=1,signal={kind="constant",on=0,off=1,total=0}},1,2)
        t.advance(3); assert(r.alert); assert(t.popup()); equal(t.api.getOutput("level_emitter_rule_1"),true)
        assert(t.api.closeWindow(t.id)); equal(t.central.server.running.level_emitter,true); t.advance(2); assert(t.popup())
        t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.advance(2); equal(t.popup(),nil); equal(r.alert,nil); equal(t.api.getOutput("level_emitter_rule_1"),false)
        for _,write in ipairs(t.bridge.redstoneWrites) do assert(write.time>=0) end
    end
    function tests.level_emitter_saved_popup_sources_and_signal_restore_without_high_input_acknowledgement()
        local t=setup("level_emitter"); rule(t,{operator="over",threshold=60,reset=20},1,2); t.advance(3); assert(t.popup()); assert(t.api.save())
        t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.reboot()
        local r=t.state.rules[1]; assert(r.alert); equal(r.sensor.target,"farm"); assert(t.popup())
        t.bridge.bundledInputs.back=0; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.advance(1)
        t.bridge.bundledInputs.back=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.pump(); t.advance(2); equal(t.popup(),nil)
    end
    function tests.level_emitter_shared_wires_or_active_rules_and_deleting_alias_preserves_wire()
        local t=setup("level_emitter"); local a=rule(t,{name="One",operator="over",threshold=60,reset=20},1)
        local b=rule(t,{name="Two",operator="over",threshold=60,reset=20},1); t.advance(3); assert(a.alert and b.alert)
        t.ack(); t.advance(1); equal(t.api.getOutput("level_emitter_rule_2"),true)
        t.ack(); t.advance(1); equal(t.api.getOutput("level_emitter_rule_2"),false)
        assert(t.api.updateOutputs({{name="unrelated",clientId="io_11",side="front",color=1,value=true}}))
        t.view().id,t.view().screen=a.id,"rule"; t.click("delete"); t.click("confirmDelete"); t.advance(1)
        equal(t.api.getOutput("level_emitter_rule_2"),true); equal(t.api.getOutput("unrelated"),true)
    end
    function tests.level_emitter_rule_editor_can_rename_reroute_and_register_absent_items()
        local t=setup("level_emitter",true); local r=rule(t,{operator="over",threshold=1000,reset=900})
        t.click("editRule"); assert(t.view().draft); t.click("textField","name"); t.view().keyboard.draft="Copper low"; t.click("saveText")
        t.click("items"); t.click("filters"); t.click("newManual"); t.view().manual={raw="item.copper",name="Copper",damage=7}; t.click("saveManual")
        t.click("condition"); t.click("operator","under"); t.click("field","threshold"); t.view().number.draft="200"; t.click("setNumber"); t.click("saveRule")
        equal(r.name,"Copper low"); equal(r.operator,"under"); equal(r.threshold,200); equal(r.item.damage,7); equal(r.item.raw,"item.copper"); assert(t.state.catalog[r.item.key])
        t.advance(1); assert(r.alert)
    end
    function tests.level_emitter_concurrent_or_triggered_editors_cannot_overwrite_new_rule_state()
        local t=setup("level_emitter",true); local r=rule(t,{operator="over",threshold=60,reset=20})
        t.click("editRule"); local old=t.view().draft.revision; t.advance(1); assert(r.alert and r.revision>old)
        t.view().draft.name="Stale edit"; t.view().screen="edit"; t.click("saveRule"); equal(r.name,"Level rule"); equal(t.view().screen,"message")
    end
    function tests.level_emitter_real_sensor_and_io_pickers_support_any_me_source()
        local t=setup("level_emitter"); t.click("new"); t.click("select","sensor_14"); t.click("select","top"); t.click("select","main"); t.click("use")
        t.advance(4); t.click("selectItem",function(v) return v.raw=="item.iron" end)
        t.click("route"); t.click("select","io_11"); t.click("select","front"); t.click("select",16); t.click("use")
        t.click("field","threshold"); t.view().number.draft="50000000"; t.click("setNumber"); t.click("saveRule")
        equal(t.state.rules[1].item.raw,"item.iron"); equal(t.state.rules[1].sensor.target,"main"); equal(t.state.rules[1].route.color,16)
    end
    function tests.level_emitter_migration_atomically_moves_saved_solar_rules_routes_and_pending_alerts_once()
        local t=setup("level_emitter"); local solar=t.central.server.state.appStates.solar_farm
        local old={version=1,sources={farm=Me.copy(sensor)},metrics={},catalog={},nextId=1,nextAlertId=8,elapsed=0,
            settings={dropCount=64,dropPercent=5,window=900,background=32768,panel=128},alarms={{id=3,name="Legacy panels",item=Me.copy(item),source="farm",threshold=60,reset=20,hold=0,
            enabled=true,latched=true,revision=2,route={clientId="io_11",side="front",color=1},signal={kind="pattern",on=1,off=1,total=0},alert={id=7,inputArmed=true},ring={elapsed=4}}}}
        Me.restore(solar,old); assert(t.api.updateOutputs({{name="solar_farm_alarm_3",clientId="io_11",side="front",color=1,value=true}})); assert(t.api.save())
        t.reboot(); equal(t.central.server.running.solar_farm,true); equal(t.central.server.state.appStates.solar_farm.version,2)
        equal(#t.state.rules,1); local r=t.state.rules[1]; equal(r.operator,"at_least"); equal(r.outputName,"solar_farm_alarm_3"); equal(r.sensor.target,"farm"); assert(r.alert); assert(t.popup())
        equal(t.api.getOutput("solar_farm_alarm_3"),true); t.reboot(); equal(#t.state.rules,1); equal(t.state.imported,1)
        t.ack(); t.advance(2); equal(t.api.getOutput("solar_farm_alarm_3"),false)
    end
    function tests.level_emitter_migration_rollback_does_not_consume_legacy_alarms_or_replace_live_state_pointers()
        local t=setup("level_emitter"); local source=t.central.server.state.appStates.solar_farm
        source.testSentinel=42; local target=t.state; local before=serialize(target)
        t.central.disk.failWrite=true
        local ok=t.api.migrateAppState("solar_farm","level_emitter",function(a,b) a.testSentinel=nil; b.testSentinel=9; return true end)
        equal(ok,false); equal(source.testSentinel,42); equal(t.central.server.state.appStates.level_emitter,target); equal(serialize(target),before)
        t.central.disk.failWrite=false
        assert(t.api.migrateAppState("solar_farm","level_emitter",function(a,b) a.testSentinel=nil; b.testSentinel=9; return true end)); equal(target.testSentinel,9); equal(source.testSentinel,nil)
        local detached=t.api.getAppData("level_emitter"); detached.testSentinel=77; equal(target.testSentinel,9)
    end
    function tests.level_emitter_forms_fit_12_by_6_and_keep_all_touch_regions_inside_content()
        local t=setup("level_emitter",true,{width=12,height=6}); rule(t,{operator="over",threshold=1000,reset=900})
        t.view().screen="rule"; t.click("editRule")
        for _,screen in ipairs({"home","rule","edit","condition","items","filters","details","settings","about"}) do
            t.view().screen=screen; t.view().pages={}; local lines=t.content(); equal(#lines,6)
            for _,hit in ipairs(lines.hits or {}) do assert(hit.x1>=1 and hit.x2<=12 and (hit.y1 or hit.y)>=1 and (hit.y2 or hit.y)<=6,screen) end
        end
    end
end
