return function(tests,newBus,monitor,serialize,unserialize,equal,githubFile)
    local Me=dofile("lib_me.lua")
    local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
    local function hv(t) return Me.Rates.sum(t.state.history.main,t.state.hv.item.key,t.state.elapsed,t.state.settings.window) end
    local function farm(t,raw)
        for _,item in ipairs(t.farm) do if item.RawName==raw then return Me.Rates.sum(t.state.history.farm,Me.itemKey(raw,item.DamageValue,item.Name),t.state.elapsed,t.state.settings.window) end end
    end
    function tests.solar_combined_overview_uses_farm_rates_and_only_main_hv()
        local t=setup("solar_farm",true); t.configure()
        equal(t.state.hv.item.raw,"solar.hv"); t.farm[2].Size=74; t.main[2].Size=1004; t.main[1].Size=210000; t.advance(2)
        equal(farm(t,"solar.lv"),10); equal(hv(t),4)
        equal(t.state.history.main.keys[Me.itemKey("ic2.matter",0,"UU Matter")],nil)
        local text=t.text(); assert(text:find("Minium Shard",1,true)); assert(text:find("HV solar",1,true)); assert(not text:find("Iron Ingot",1,true))
        local hits=t.content().hits; local buttons={}
        for _,hit in ipairs(hits) do if hit.y==t.height then buttons[#buttons+1]=hit.action end end
        equal(table.concat(buttons,","),"pin,menu")
        t.click("menu"); local menu=t.text(); assert(menu:find("ME sources",1,true)); assert(not menu:find("Farm stocks",1,true)); assert(not menu:find("Stock alarms",1,true))
        equal(t.app.handleIOSelection,nil); equal(t.app.handleNotification,nil)
    end
    function tests.solar_overview_small_pages_keep_hv_fixed_and_have_exactly_four_footer_buttons()
        local t=setup("solar_farm",true,{width=12,height=6}); t.configure()
        local first=t.content(); local hvRow=first[2]..first[3]
        local actions={}; for _,hit in ipairs(first.hits) do if hit.y==6 then actions[#actions+1]=hit.action end end
        equal(table.concat(actions,","),"page,page,pin,menu")
        t.click("page",function(v) return v.key=="overview" and v.page==2 end)
        local second=t.content(); equal(second[2]..second[3],hvRow); assert(first[4]~=second[4])
        for _,hit in ipairs(second.hits) do assert(hit.x1>=1 and hit.x2<=12 and (hit.y or hit.y1)<=6 and (hit.y2 or hit.y or hit.y1)<=6) end
    end
    function tests.solar_sources_use_real_ae_selectors_and_never_write_io()
        local t=setup("solar_farm"); t.view().screen="sources"
        for _,role in ipairs({"farm","main"}) do
            t.click("source",role); t.click("select","sensor_14"); t.click("select","top"); t.click("select",role); t.click("use")
        end
        t.advance(5); equal(t.state.sources.farm.target,"farm"); equal(t.state.sources.main.target,"main"); equal(#t.sensor.client.watches,2)
        equal(next(t.central.server.state.outputMap),nil); equal(#t.sensor.redstoneWrites,0)
        assert(t.text():find("main",1,true) or t.text():find("sensor_14",1,true))
    end
    function tests.solar_rate_filter_ignores_large_drops_and_immediately_rebases()
        local t=setup("solar_farm",true); t.configure()
        t.main[2].Size=1010; t.advance(2); equal(hv(t),10)
        t.main[2].Size=700; t.advance(2); local delta,seconds,drops,removed=hv(t)
        equal(delta,10); equal(drops,1); equal(removed,310)
        t.main[2].Size=704; t.advance(2); equal(hv(t),14)
        t.farm[1].Size=4936; t.advance(2); equal(farm(t,"ic2.matter"),-64)
    end
    function tests.solar_duplicate_samples_offline_unpowered_boot_changes_and_long_gaps_are_unknown_or_rebased()
        local t=setup("solar_farm",true); t.configure(); t.main[2].Size=1010; t.advance(2)
        local delta,seconds=hv(t)
        for _=1,4 do t.app.background(.5,t.state,t.api) end
        local _,after=hv(t); equal(after,seconds)
        t.offline=true; t.advance(2); assert(t.text():find("--",1,true)); t.main[2].Size=900000
        t.offline=false; t.advance(2); equal(hv(t),delta)
        t.main[2].Size=900001; t.advance(2); equal(hv(t),delta+1)
        t.boot=2; t.main[2].Size=1000000; t.advance(2); equal(hv(t),delta+1)
        t.main[2].Size=2000000; t.advance(30); equal(hv(t),delta+1)
        t.data.main.Powered=false; t.advance(2); assert(t.text():find("--",1,true))
        t.data.main.Powered=true; t.main[2].Size=3000000; t.advance(2); equal(hv(t),delta+1)
    end
    function tests.solar_complete_absence_is_zero_incomplete_inventory_is_unknown()
        local t=setup("solar_farm",true); t.configure(); local m=t.pin("solar.lv")
        t.farm[2]=nil; t.advance(2); t.view().key,t.view().selected,t.view().screen=m.item.key,m.item,"item"
        assert(t.text():find("Amount: 0",1,true))
        t.data.farm.ItemsOmitted=true; t.advance(2); assert(t.text():find("Amount: --",1,true))
        t.data.farm.ItemsOmitted=nil; t.advance(2); assert(t.text():find("Amount: 0",1,true))
    end
    function tests.solar_pins_reorder_only_farm_items_and_allow_names_colours_and_custom_filters()
        local t=setup("solar_farm",true); t.configure(); local m=t.pin("solar.lv")
        t.view().key,t.view().selected,t.view().screen=m.item.key,m.item,"editPin"
        t.click("rename"); t.view().keyboard.draft="Panels"; t.click("saveText"); equal(m.name,"Panels")
        t.click("pinColour"); t.click("colour",32); equal(m.colour,32)
        t.click("field","dropCount"); t.view().number.draft="1"; t.click("setNumber"); equal(m.dropCount,1)
        t.click("field","dropPercent"); t.view().number.draft="0"; t.click("setNumber"); equal(m.dropPercent,0)
        t.view().screen="home"; assert(t.text():find("Panels",1,true))
        t.farm[2].Size=63; t.advance(2); local _,_,drops=farm(t,"solar.lv"); equal(drops,1)
        t.view().screen="editPin"; t.click("unpin"); equal(#t.state.metrics,0)
    end
    function tests.solar_item_selector_filters_main_items_and_registers_absent_farm_identities()
        local t=setup("solar_farm",true); t.configure(); t.click("pin")
        for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then assert(hit.value.raw~="item.iron") end end
        t.click("filters"); t.click("newManual"); t.view().manual={raw="solar.future",damage=7,name="Future Solar"}; t.click("saveManual")
        equal(t.state.metrics[1].item.damage,7); equal(t.state.metrics[1].item.raw,"solar.future")
        t.view().screen="home"; assert(t.text():find("Future Solar",1,true))
        t.click("pin"); t.click("filters"); t.click("newManual")
        t.view().manual={raw="solar.hv",damage=0,name="HV Solar"}; t.click("saveManual")
        equal(#t.state.metrics,2,"A registered farm HV item is separate from the main-ME output pin")
        t.click("menu"); t.click("chooseHV")
        for _,hit in ipairs(t.content().hits) do if hit.action=="selectItem" then equal(hit.value.raw,"solar.hv") end end
    end
    function tests.solar_rates_units_history_budget_and_large_plain_numbers()
        local t=setup("solar_farm",true); t.configure()
        for _=1,1900 do t.main[2].Size=t.main[2].Size+1; t.advance(2) end
        equal(#t.state.history.main.buckets,60); assert(Me.Rates.valid(t.state.history.main))
        assert(#serialize(t.state)<24000); assert(not serialize(t.state):find('"Powered"',1,true))
        t.view().screen="menu"; t.click("period"); equal(t.state.settings.period,60)
        t.click("period"); equal(t.state.settings.period,1)
        t.view().screen="home"; assert(t.text():find("/s",1,true)); assert(not t.text():find("[Ee][+-]%d"))
        local history=Me.Rates.new(); local changes={}
        for i=1,8192 do changes[("long.item.identity."):rep(8)..i]={delta=1} end
        equal(Me.Rates.record(history,2,2,changes),false); equal(#history.buckets,0); equal(history.limited,true)
        assert(Me.Rates.valid(history)); assert(Me.Rates.record(history,4,2,{short={delta=2}})); assert(#serialize(history)<1000)
    end
    function tests.solar_saved_sources_pins_history_and_navigation_restore_without_counting_reboot_stock_jump()
        local t=setup("solar_farm"); t.configure(); t.pin("solar.lv"); t.main[2].Size=1003; t.advance(3)
        local delta=hv(t); t.view().screen="sourceInfo"; assert(t.api.save()); t.main[2].Size=999999; t.reboot()
        equal(hv(t),delta); equal(t.state.sources.farm.target,"farm"); equal(#t.state.metrics,1); equal(t.view().screen,"sourceInfo")
    end
    function tests.solar_failed_save_preserves_pin_settings_and_source_history()
        local t=setup("solar_farm",true); t.configure(); local before=Me.copy(t.state)
        t.view().screen="menu"; t.failSave=true; t.click("period"); equal(t.state.settings.period,before.settings.period); equal(t.state.elapsed,before.elapsed); equal(t.state.hv.item.raw,before.hv.item.raw)
        t.view().screen="home"; t.click("pin"); t.click("selectItem",function(v) return v.raw=="solar.lv" end); equal(#t.state.metrics,0)
    end
    function tests.solar_schema_upgrade_preserves_bindings_and_requires_alarm_migration_first()
        local item={raw="solar.hv",name="HV Solar",damage=0,key=Me.itemKey("solar.hv",0,"HV Solar")}
        local old={version=1,sources={},metrics={{id=1,name="HV",item=item,colour=32,history={}}},catalog={},alarms={},nextId=2,nextAlertId=1,elapsed=10,
            settings={dropCount=64,dropPercent=5,window=900,background=32768,panel=128}}
        local t=setup("solar_farm",true,{state=Me.copy(old)}); equal(t.state.version,2); equal(t.state.hv.item.raw,"solar.hv"); equal(#t.state.metrics,0)
        old.alarms={{id=1}}; local ok,err=pcall(setup,"solar_farm",true,{state=old}); equal(ok,false); assert(tostring(err):find("level_emitter",1,true)); equal(old.version,1); equal(#old.alarms,1)
    end
    function tests.solar_overview_adds_new_farm_items_and_keeps_hv_sources_separate()
        local t=setup("solar_farm",true); t.configure(); t.content()
        t.farm[#t.farm+1]={Name="New gear",RawName="gear.new",DamageValue=0,Size=7}; t.advance(2)
        assert(t.text():find("New gear",1,true))
        t.farm[#t.farm+1]={Name="HV Solar",RawName="solar.hv",DamageValue=0,Size=12}; t.advance(2)
        local found={}; for _,hit in ipairs(t.content().hits) do if hit.action=="item" and hit.value.item and hit.value.item.raw=="solar.hv" then found[hit.value.key]=true end end
        assert(found.hv and found[Me.itemKey("solar.hv",0,"HV Solar")])
    end
    function tests.v30_installer_fetches_three_real_apps_via_github_api_without_bundling_or_autostarting_screensaver()
        local bus=newBus(); local central=bus.computer(10,"server")
        central.env.shell={dir=function() return "" end}
        local install=assert(central.env.loadfile("install.lua")); install("server","--startup")
        assert(central.disk.files["lib_me.lua"])
        local downloads=0
        central.env.http={get=function(url)
            downloads=downloads+1
            local appName=assert(url:match("/contents/(apps_[%w_]+%.lua)%?ref=main$"))
            local file=assert(io.open(appName,"r")); local body=file:read("*a"); file:close()
            return {readAll=function() return githubFile(appName,body) end,close=function() end}
        end}
        for _,appName in ipairs({"level_emitter","solar_farm","screensaver"}) do
            equal(central.disk.files["apps_"..appName..".lua"],nil); install("app",appName)
        end
        equal(downloads,3); central:start(); bus.advance(1)
        equal(central.server.running.level_emitter,true); equal(central.server.running.solar_farm,true); equal(central.server.running.screensaver,nil)
        equal(next(central.server.state.windows),nil)
    end
    function tests.solar_hv_stick_can_be_disabled_unpinned_and_repinned_without_reverting_to_farm_measurements()
        local t=setup("solar_farm",true,{width=12,height=6}); t.configure()
        equal(t.state.hv.pinned,true); equal(t.state.hv.stick,true)
        t.view().key,t.view().screen="hv","editPin"; t.click("stick"); equal(t.state.hv.stick,false)
        t.view().screen="home"; t.view().pages.overview=2
        for _,hit in ipairs(t.content().hits) do if hit.action=="item" then assert(hit.value.key~="hv","Nonsticky HV must scroll with the list") end end
        t.view().key,t.view().screen="hv","editPin"; t.click("unpin"); equal(t.state.hv.pinned,false)
        t.click("pin"); t.click("selectItem",function(v) return v.hv end)
        equal(t.state.hv.pinned,true); equal(t.state.hv.stick,false); equal(#t.state.metrics,0)
        t.view().key,t.view().screen="hv","editPin"; t.click("stick"); equal(t.state.hv.stick,true)
        t.main[2].Size=1004; t.advance(2); equal(hv(t),4)
    end
    function tests.solar_any_pin_can_stick_multiple_items_stay_visible_and_small_overflow_remains_reachable()
        local t=setup("solar_farm",true,{width=12,height=10}); t.configure(); local m=t.pin("solar.lv")
        for i=1,8 do t.farm[#t.farm+1]={Name="Part "..i,RawName="item.part"..i,DamageValue=0,Size=i} end
        t.advance(2); t.view().key,t.view().screen=m.item.key,"editPin"; t.click("stick"); equal(m.stick,true)
        t.view().screen="home"; local first=t.content(); t.click("page",function(v) return v.key=="overview" and v.page==2 end)
        local second=t.content(); equal(first[2],second[2]); equal(first[4],second[4]); assert(second[4]:find("LV Solar",1,true))
        t.height=6; t.view().pages={}; local visited={}
        for page=1,20 do
            t.view().pages.overview=page; for _,hit in ipairs(t.content().hits) do if hit.action=="item" then visited[hit.value.key]=true end end
        end
        assert(visited.hv and visited[m.item.key] and visited[Me.itemKey("item.part8",0,"Part 8")])
    end
    function tests.solar_stick_and_unpin_preferences_survive_reboot_and_failed_saves_rollback()
        local t=setup("solar_farm"); t.configure(); local m=t.pin("solar.lv")
        t.view().key,t.view().screen=m.item.key,"editPin"; t.click("stick")
        t.view().key,t.view().screen="hv","editPin"; t.click("unpin"); assert(t.api.save()); t.reboot()
        equal(t.state.metrics[1].stick,true); equal(t.state.hv.pinned,false); equal(t.state.hv.stick,false)
        t.view().key,t.view().screen=t.state.metrics[1].item.key,"editPin"; t.central.disk.failWrite=true; t.click("stick")
        equal(t.state.metrics[1].stick,true); t.central.disk.failWrite=false
    end
    function tests.solar_hv_picker_and_automatic_detection_work_in_legacy_luaj_without_blocking_farm_items()
        local t=setup("solar_farm"); t.configure()
        equal(t.state.hv.item.raw,"solar.hv")
        local text=t.text(); assert(text:find("Minium Shard",1,true) and text:find("UU Matter",1,true) and text:find("LV Solar",1,true))
        t.click("menu"); t.click("chooseHV"); assert(t.text():find("HV Solar",1,true)); assert(t.text():find("main ME",1,true))
        t.click("autoHV"); t.advance(1); equal(t.state.hv.selection,"auto"); equal(t.state.hv.item.raw,"solar.hv")
        assert(t.text():find("Minium Shard",1,true)); t.view().screen="menu"; t.click("chooseHV")
        t.click("selectItem",function(v) return v.raw=="solar.hv" end); equal(t.state.hv.selection,"manual")
        t.paint(); assert(not table.concat(t.top.lines,"\n"):find("App render failed",1,true))
        assert(not table.concat(t.central.log,"\n"):find("solar_farm.background failed",1,true))
        t.click("menu"); t.click("chooseHV"); t.click("autoHV"); t.advance(3)
        local key=t.state.hv.item.key
        t.main[2]={Name="Other HV Solar",RawName="solar.other",DamageValue=0,Size=12}; t.advance(5)
        equal(t.state.hv.item.key,key,"A temporary absence must not silently change the measured output identity")
        t.view().screen="menu"; t.click("chooseHV"); t.click("autoHV"); t.advance(3); equal(t.state.hv.item.raw,"solar.other")
    end
    function tests.solar_picker_search_never_filters_the_all_farm_overview()
        local t=setup("solar_farm",true); t.configure(); t.click("menu"); t.click("chooseHV"); t.click("filters"); t.click("search")
        t.view().keyboard.draft="HV"; t.click("saveText"); t.click("selectItem",function(v) return v.raw=="solar.hv" end)
        local text=t.text(); assert(text:find("UU Matter",1,true) and text:find("LV Solar",1,true) and text:find("Minium Shard",1,true))
    end
    function tests.solar_bad_main_feed_is_reported_while_farm_inventory_and_rates_continue_and_recovery_rebases()
        local t=setup("solar_farm",true); t.configure()
        local read=t.api.getSensorReading; local broken=true
        t.api.getSensorReading=function(a,options) if broken and a.target=="main" then error("ME reader disconnected") end; return read(a,options) end
        t.farm[2].Size=70; t.advance(2); equal(farm(t,"solar.lv"),6)
        local text=t.text(); assert(text:find("Main: Error",1,true)); assert(text:find("UU Matter",1,true)); assert(text:find("Minium Shard",1,true))
        t.view().screen="sourceInfo"; local details=t.text():gsub("%s+"," "); assert(details:find("ME reader disconnected",1,true)); equal(t.state.sources.main.target,"main")
        t.main[2].Size=500000; broken=false; t.advance(2); equal(hv(t),0)
        t.main[2].Size=500002; t.advance(2); equal(hv(t),2)
    end
    function tests.solar_unconfigured_empty_partial_and_unpowered_feeds_explain_their_status_and_picker_never_crashes()
        local t=setup("solar_farm",true,{width=13,height=7}); assert(t.text():find("Farm: Not set",1,true))
        t.click("menu"); t.click("chooseHV"); assert(t.text():find("ME source",1,true) or t.text():find("unconfigured",1,true))
        t.view().screen="home"; t.configure(); t.data.farm.ItemsComplete=false; t.advance(2)
        assert(t.text():find("Farm: Incompl",1,true))
        t.data.farm.ItemsComplete=true; t.data.farm.Items={}; t.advance(2); assert(t.text():find("Farm ME is em",1,true))
        t.data.main.Powered=false; t.advance(2); assert(t.text():find("Main: Unpower",1,true))
        t.view().screen="menu"; t.click("chooseHV"); assert(not t.text():find("App render failed",1,true))
    end
    function tests.solar_large_dashboard_shows_farm_totals_direction_changes_bytes_and_hv_history()
        local t=setup("solar_farm",true,{width=80,height=30}); t.data.farm.UsedBytes=256; t.data.farm.FreeBytes=768; t.configure()
        for _=1,12 do t.main[2].Size=t.main[2].Size+8; t.farm[1].Size=t.farm[1].Size-10; t.farm[2].Size=t.farm[2].Size+2; t.advance(2) end
        local text=t.text(); assert(text:find("HV OUTPUT",1,true)); assert(text:find("FARM STOCK",1,true)); assert(text:find("FARM MOVEMENT",1,true))
        assert(text:find("1 rising / 1 falling",1,true)); assert(text:find("Bytes 25%",1,true)); assert(text:find("Change 15m",1,true)); assert(text:find("HV net trend",1,true))
        local lime=false; for _,style in ipairs(t.content().styles) do if style.y>=10 and style.y<=12 and style.bg==32 then lime=true end end; assert(lime)
        assert(not text:find("Iron Ingot",1,true)); assert(not text:find("[Ee][+-]%d"))
        t.view().screen="menu"; t.click("period"); t.view().screen="home"; assert(t.text():find("/m",1,true))
    end
    function tests.solar_dashboard_and_hv_picker_fit_all_supported_small_and_large_content_sizes()
        local t=setup("solar_farm",true); t.configure()
        for _,size in ipairs({{12,6},{13,7},{24,10},{36,6},{42,14},{56,24},{80,30},{128,64}}) do
            for _,screen in ipairs({"home","items","sourceInfo"}) do
                t.view().screen,t.view().purpose,t.view().pages=screen,"hv",{}
                local lines=t.content(nil,size[1],size[2]); equal(#lines,size[2])
                for y=1,size[2] do equal(#lines[y],size[1],screen.." row width") end
                for _,hit in ipairs(lines.hits) do assert(hit.x1>=1 and hit.x2<=size[1] and (hit.y1 or hit.y)>=1 and (hit.y2 or hit.y)<=size[2],screen) end
            end
        end
    end
end
