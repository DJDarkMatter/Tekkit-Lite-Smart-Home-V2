-- Clock service through real OS/IO/monitor roles, including checkpoints and time jumps.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local f=assert(io.open("apps_clock.lua","r")); local source=f:read("*a"); f:close()
    local function setup(options)
        options=options or {}
        local bus=newBus(); local offset=options.offset or 0
        local t={bus=bus,rate=options.rate or 72}
        function t.startCentral(disk)
            local central=bus.computer(10,"server",{disk=disk,apps=disk and nil or {["apps_clock.lua"]=source}})
            central.env.os.time=function() return ((21600+bus.now*t.rate+offset)%86400)/3600 end
            central.env.os.day=function() return 100+math.floor((bus.now*t.rate+offset)/86400) end
            central:start(); t.central=central; t.api=central.server.api; t.app=central.server.apps.clock; t.state=central.server.state.appStates.clock
        end
        function t.jump(seconds) offset=offset+seconds end
        t.startCentral()
        t.bridge=bus.computer(11,"io",{modemSide="right"}):start()
        t.top,t.left=monitor(64,26),monitor(15,10)
        t.display=bus.computer(13,"monitor",{monitors={top=t.top,left=t.left}}):start()
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.open(side) local id=assert(t.api.openApp("clock","monitor_13:"..(side or "top"),1,1)); t.paint(); return id end
        function t.view(id) return t.central.server.views[id] end
        function t.context(id) return {appName="clock",windowId=id,view=t.view(id)} end
        function t.content(id)
            local win=t.central.server.state.windows[id]
            return t.app.render(win.width-2,win.height-2,t.state,t.api,t.context(id))
        end
        function t.popup(side)
            t.paint()
            local mon=t.central.server.monitors["monitor_13:"..(side or "top")]
            return mon and mon.notification
        end
        function t.ack(side)
            local popup=assert(t.popup(side),"Expected popup")
            bus.queue(t.display,{"monitor_touch",side or "top",math.floor((popup.ok.x1+popup.ok.x2)/2),popup.ok.y}); bus.pump()
        end
        function t.ackAll()
            for _=1,128 do if not t.popup() then return end; t.ack() end
            error("Popup queue did not clear")
        end
        function t.click(id,action,value)
            if not options.manualAlerts then t.ackAll() end
            for _=1,80 do
                t.paint(); local dialog=t.central.server.dialogs[id]
                local hits=dialog and dialog.hits or t.content(id).hits
                local nextHit,prev
                for _,hit in ipairs(hits or {}) do if hit.enabled~=false then
                    local selected=type(hit.value)=="table" and hit.value.value or hit.value
                    if hit.action==action and (value==nil or type(value)=="function" and value(hit.value) or selected==value) then
                        local win=t.central.server.state.windows[id]
                        bus.queue(t.display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+math.floor((hit.x1+hit.x2)/2),win.y+(hit.y or hit.y1)})
                        bus.pump(); return
                    end
                    if hit.action=="next" or hit.action=="page" and hit.value.page>(t.view(id).pages[hit.value.key] or 1) then nextHit=hit end
                    if hit.action=="prev" or hit.action=="page" and hit.value.page<(t.view(id).pages[hit.value.key] or 1) then prev=hit end
                end end
                local hit=nextHit or prev; if not hit then break end
                local win=t.central.server.state.windows[id]
                bus.queue(t.display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+hit.x1,win.y+(hit.y or hit.y1)}); bus.pump()
            end
            error("Missing clock control "..action.." on "..tostring(t.view(id).screen))
        end
        function t.new(id,kind,values,withRoute)
            t.view(id).screen=kind=="alarm" and "alarms" or "timers"; t.paint()
            t.click(id,"new",kind)
            for key,value in pairs(values or {}) do t.view(id).draft[key]=value end
            if withRoute then
                t.click(id,"route"); t.click(id,"select","io_11"); t.click(id,"select","front"); t.click(id,"select",withRoute); t.click(id,"use")
            end
            t.click(id,"saveDraft")
            return kind=="alarm" and t.state.alarms[#t.state.alarms] or t.state.timers[#t.state.timers]
        end
        function t.output(item,kind) return t.api.getOutput("clock_"..kind.."_"..item.id) end
        bus.advance(1); t.id=t.open()
        return t
    end
    function tests.v50_clock_home_uses_a_wide_grid_and_keeps_every_compact_control_reachable()
        local t=setup({offset=18*3600-70})
        local hits={}
        for _,hit in ipairs(t.content(t.id).hits) do hits[hit.action]=hit end
        assert(hits.worldTime.y2>hits.worldTime.y1)
        assert(hits.alarms.y2-hits.alarms.y1>hits.settings.y2-hits.settings.y1)
        assert(hits.alarms.paint.bg~=hits.settings.paint.bg)
        equal(hits.alarms.y1,hits.timers.y1)
        equal(hits.stopwatch.y1,hits.worldTime.y1)
        assert(hits.alarms.x2+1<hits.timers.x1)
        equal(hits.settings.y1,hits.status.y1)
        local id=t.open("left")
        local compact={}
        for _,hit in ipairs(t.content(id).hits) do compact[hit.action]=hit end
        assert(compact.alarms.y2<compact.timers.y1 and compact.timers.y2<compact.stopwatch.y1)
        assert(compact.stopwatch.y2<compact.worldTime.y1 and compact.worldTime.y2<compact.settings.y1)
        assert(compact.settings.x2<compact.status.x1)
        t.click(id,"settings"); equal(t.view(id).screen,"settings")
        t.click(id,"home")
        t.click(id,"worldTime")
        local content=t.content(id)
        assert(content[1]:find("World time",1,true))
        assert(content[2]:find(t.api.getSystem().gameTime,1,true))
        local before=content[2]
        t.bus.advance(2)
        assert(t.content(id)[2]~=before)
        assert(table.concat(t.content(id),"\n"):find("Day 100",1,true))
        t.click(id,"home")
        equal(t.view(id).screen,"home")
    end
    function tests.v41_clock_signal_details_recover_when_alarm_is_deleted_on_another_monitor()
        local t = setup()
        local alarm = t.new(t.id, "alarm", {minute = 1200}, nil)
        t.view(t.id).screen = "alarms"
        t.click(t.id, "open", function(value) return value.id == alarm.id end)
        t.click(t.id, "routeInfo")
        local second = t.open("left")
        t.click(second, "alarms"); t.click(second, "open", function(value) return value.id == alarm.id end)
        t.click(second, "delete"); t.click(second, "confirmDelete")
        t.paint()
        equal(t.view(t.id).screen, "alarms")
        assert(table.concat(t.content(t.id), "\n"):find("No alarms", 1, true))
    end
    function tests.v46_clock_number_pad_accepts_touches_at_the_bottom_of_a_key()
        local t=setup()
        t.click(t.id,"timers"); t.click(t.id,"new","timer"); t.click(t.id,"field","duration")
        t.click(t.id,"digit","Clr")
        local key
        for _,hit in ipairs(t.content(t.id).hits) do
            if hit.action=="digit" and hit.value=="9" then key=hit end
        end
        assert(key and key.y2>key.y)
        local win=t.central.server.state.windows[t.id]
        t.bus.queue(t.display,{"monitor_touch","top",win.x+key.x2,win.y+key.y2}); t.bus.pump()
        equal(t.view(t.id).number.draft,"9")
        t.click(t.id,"setNumber")
        equal(t.view(t.id).draft.duration,9)
    end

    function tests.clock_timers_trigger_pulses_in_background_and_resume_from_checkpoints_without_counting_downtime()
        local t=setup()
        local timer=t.new(t.id,"timer",{duration=5,signal={kind="pulse",on=4,off=1,total=4}},1)
        equal(timer.route.color,1); equal(timer.remaining,5)
        assert(t.api.closeWindow(t.id)); equal(t.central.server.running.clock,true)
        t.bus.advance(2); assert(math.abs(timer.remaining-3)<0.01)
        assert(t.api.save()); local before=timer.remaining
        t.central.active=false; t.bus.advance(10)
        t.startCentral(t.central.disk)
        timer=t.state.timers[1]; equal(timer.remaining,before)
        t.bus.advance(before+0.1); equal(timer.status,"done"); equal(t.output(timer,"timer"),true)
        t.bus.advance(1); assert(timer.ring)
        assert(t.api.save()); local signalElapsed=timer.ring.elapsed
        t.startCentral(t.central.disk); timer=t.state.timers[1]; equal(timer.ring.elapsed,signalElapsed)
        t.bus.advance(5); equal(t.output(timer,"timer"),false); equal(timer.ring,nil)
        equal(t.bridge.bundled.front,0)
        local writes=t.bridge.redstoneWrites
        for i=2,#writes do if writes[i].side==writes[i-1].side then assert(writes[i].time-writes[i-1].time>=0.5-0.000001) end end
    end
    function tests.clock_pattern_timing_and_overlapping_shared_routes_are_combined_without_conflicting_batches()
        local t=setup({rate=0})
        local a=t.new(t.id,"timer",{duration=1,signal={kind="pattern",on=1,off=1,total=5}},1)
        local b=t.new(t.id,"timer",{duration=2,signal={kind="pulse",on=4,off=1,total=4}},1)
        t.bus.advance(1.1); equal(t.output(a,"timer"),true)
        t.bus.advance(1); equal(t.output(a,"timer"),true); equal(t.output(b,"timer"),true)
        t.bus.advance(3); equal(t.output(a,"timer"),true)
        t.bus.advance(1.5); equal(t.output(a,"timer"),false); equal(t.output(b,"timer"),false)
        equal(a.ring,nil); equal(b.ring,nil)
        assert(not table.concat(t.central.log,"\n"):find("Conflicting",1,true))
        local c=t.new(t.open(),"timer",{duration=1,signal={kind="pattern",on=1,off=1,total=4}},2)
        t.bus.advance(1.1); equal(t.output(c,"timer"),true)
        t.bus.advance(1); equal(t.output(c,"timer"),false)
        t.bus.advance(1); equal(t.output(c,"timer"),true)
        t.bus.advance(2); equal(t.output(c,"timer"),false)
    end
    function tests.clock_alarms_cross_midnight_and_dawn_once_per_day_and_skip_time_jumps_or_downtime()
        local t=setup({offset=64700}) -- 23:58:20 then cross midnight normally.
        local alarm=t.new(t.id,"alarm",{minute=0,daily=true,signal={kind="pulse",on=1,off=1,total=1}},4)
        t.bus.advance(1); assert(alarm.lastDay~=nil); equal(t.output(alarm,"alarm"),true)
        local fired=alarm.lastDay
        t.bus.advance(2); equal(t.output(alarm,"alarm"),false)
        t.jump(-180); t.bus.advance(0.1); t.bus.advance(3)
        equal(alarm.lastDay,fired); equal(t.output(alarm,"alarm"),false)
        t.jump(21600); t.bus.advance(0.5) -- Sleep/time-set does not catch up.
        local once=t.new(t.id,"alarm",{minute=math.floor(t.api.getSystem().worldTime*60)+1,daily=false},8)
        t.bus.advance(1); equal(once.enabled,false)
        local saved=once.lastDay; assert(t.api.save()); t.startCentral(t.central.disk)
        equal(t.state.alarms[2].lastDay,saved); equal(t.state.alarms[2].enabled,false)
        t.jump(86400); t.bus.advance(0.5); equal(t.state.alarms[1].lastDay,fired)
        local dawn=setup({offset=-100}) -- os.day changes at 06:00, not midnight.
        local morning=dawn.new(dawn.id,"alarm",{minute=360},16)
        local game=dawn.new(dawn.id,"timer",{duration=300,mode="game"})
        dawn.bus.advance(1); assert(morning.lastDay~=nil); equal(dawn.output(morning,"alarm"),true)
        assert(math.abs(game.remaining-228)<0.01,"Dawn must advance game time normally")
    end
    function tests.clock_game_time_and_real_time_are_independent_and_missing_clock_pauses_only_game_progress()
        local t=setup()
        local real=t.new(t.id,"timer",{duration=100,mode="real"})
        local game=t.new(t.id,"timer",{duration=100,mode="game"})
        t.bus.advance(1); assert(real.remaining>98 and real.remaining<100); assert(game.remaining<30 and game.remaining>26)
        local before=game.remaining
        t.central.env.os.time=nil; t.bus.advance(1)
        equal(game.remaining,before); assert(real.remaining<99)
        t.central.env.os.time=function() return 12 end; t.bus.advance(0.2); equal(game.remaining,before)
        t.jump(50000); t.bus.advance(0.2); equal(game.remaining,before)
        assert(table.concat(t.content(t.id),"\n"):find("Game",1,true))
    end
    function tests.clock_failed_checkpoints_never_actuate_and_retry_the_trigger_with_unchanged_alarm_or_timer_state()
        local t=setup({rate=0})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="pulse",on=2,off=1,total=2}},1)
        t.central.disk.failWrite=true
        t.bus.advance(1.1); equal(t.output(timer,"timer"),false); equal(t.bridge.bundled.front,0)
        equal(t.state.timers[1].status,"running")
        t.central.disk.failWrite=false; t.bus.advance(1)
        timer=t.state.timers[1]; equal(timer.status,"done"); equal(t.output(timer,"timer"),true)
        t.bus.advance(3); equal(t.output(timer,"timer"),false)
        local id=t.open(); t.view(id).screen="alarms"; t.click(id,"new","alarm")
        t.central.disk.failWrite=true; t.click(id,"saveDraft"); equal(#t.state.alarms,0)
        t.central.disk.failWrite=false
        t.click(id,"messageBack"); t.click(id,"saveDraft"); equal(#t.state.alarms,1)
    end
    function tests.clock_stopwatch_start_stop_laps_reset_and_game_mode_are_saved_across_views_and_restart()
        local t=setup(); t.click(t.id,"stopwatch")
        t.click(t.id,"stopwatchToggle"); t.bus.advance(2); t.click(t.id,"lap")
        t.bus.advance(1); t.click(t.id,"stopwatchToggle")
        equal(#t.state.stopwatch.laps,1); assert(math.abs(t.state.stopwatch.elapsed-3)<0.01)
        local old=t.state.stopwatch.elapsed
        t.bus.advance(2); equal(t.state.stopwatch.elapsed,old)
        local other=t.open("left"); t.click(other,"stopwatch")
        assert(t.api.save()); t.startCentral(t.central.disk); equal(t.state.stopwatch.elapsed,old)
        equal(t.view(other).screen,"stopwatch"); equal(#t.state.stopwatch.laps,1)
        t.bus.advance(5) -- Clients reannounce after an OS reboot.
        t.click(other,"resetStopwatch"); equal(t.state.stopwatch.elapsed,0)
        t.click(other,"stopwatchMode"); equal(t.state.stopwatch.mode,"game")
        t.click(other,"stopwatchToggle"); t.bus.advance(1); assert(math.abs(t.state.stopwatch.elapsed-72)<0.01)
        t.click(other,"lap"); equal(t.state.stopwatch.laps[1].number,1)
    end
    function tests.clock_real_stopwatch_records_between_ticks_without_quantizing_start_laps_or_stop()
        local t=setup(); t.click(t.id,"stopwatch")
        t.bus.advance(.13); t.click(t.id,"stopwatchToggle")
        t.bus.advance(.23); t.click(t.id,"lap")
        assert(math.abs(t.state.stopwatch.laps[1].elapsed-.23)<.00001)
        t.bus.advance(.31); t.click(t.id,"stopwatchToggle")
        assert(math.abs(t.state.stopwatch.elapsed-.54)<.00001)
        t.bus.advance(3); assert(math.abs(t.state.stopwatch.elapsed-.54)<.00001)
        t.click(t.id,"stopwatchToggle"); t.bus.advance(.17); t.click(t.id,"stopwatchToggle")
        assert(math.abs(t.state.stopwatch.elapsed-.71)<.00001)
        assert(t.api.save()); t.startCentral(t.central.disk)
        assert(math.abs(t.state.stopwatch.elapsed-.71)<.00001)
    end
    function tests.clock_real_stopwatch_uses_elapsed_clock_even_if_background_delivery_or_another_signal_save_fails()
        local t=setup({rate=0,manualAlerts=true})
        t.new(t.id,"timer",{duration=1,signal={kind="constant",on=1,off=1,total=1}})
        t.view(t.id).screen="stopwatch"; t.click(t.id,"stopwatchToggle")
        local start=t.bus.now
        t.central.disk.failWrite=true; t.bus.advance(2.37); t.content(t.id)
        assert(math.abs(t.state.stopwatch.elapsed-(t.bus.now-start))<.00001)
        t.central.disk.failWrite=false; t.bus.advance(.44)
        t.content(t.id); assert(math.abs(t.state.stopwatch.elapsed-(t.bus.now-start))<.00001)
        -- One late callback must not use a guessed nominal callback interval.
        t.bus.now=t.bus.now+7.25; t.app.background(.5,t.state,t.api)
        assert(math.abs(t.state.stopwatch.elapsed-(t.bus.now-start))<.00001)
    end
    function tests.clock_game_stopwatch_and_laps_show_days_without_subseconds_on_small_or_large_windows()
        local t=setup(); local sw=t.state.stopwatch
        sw.mode,sw.elapsed,sw.lapCounter="game",90061.9,1
        sw.laps={{number=1,elapsed=90061.9,split=90061.9}}; t.view(t.id).screen="stopwatch"
        for _,size in ipairs({{12,6},{44,18}}) do
            local lines=t.app.render(size[1],size[2],t.state,t.api,t.context(t.id))
            assert(lines[2]:find("1d 01:01:01",1,true))
            local text=table.concat(lines,"\n"); assert(not text:find("01:01:01.",1,true)); assert(text:find("1d",1,true))
        end
    end

    function tests.clock_timer_history_is_bounded_without_dropping_active_timers_or_leaving_output_routes()
        local t=setup({rate=0})
        local active=t.new(t.id,"timer",{duration=10000})
        for i=1,22 do
            t.new(t.id,"timer",{duration=1},1); t.bus.advance(4)
        end
        t.ackAll(); t.bus.advance(1)
        equal(#t.state.timers,21); equal(t.state.timers[1].id,active.id)
        local outputs=t.api.getOutputs(); equal(#outputs,20)
        for _,output in ipairs(outputs) do equal(output.value,false) end
        t.view(t.id).screen="settings"; t.click(t.id,"history") -- 20 -> 50
        t.click(t.id,"history"); equal(t.state.settings.history,10); equal(#t.state.timers,11)
        equal(#t.api.getOutputs(),10)
    end
    function tests.clock_output_deletion_releases_only_its_reference_and_finishes_its_active_signal_on_shared_wires()
        local t=setup({rate=0})
        assert(t.api.mapOutput("manual","io_11","front",1,false))
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="pulse",on=10,off=1,total=10}},1)
        t.bus.advance(2); equal(t.api.getOutput("manual"),true)
        t.click(t.id,"delete"); t.click(t.id,"confirmDelete")
        equal(#t.state.timers,0); equal(t.api.getOutput("manual"),false); equal(#t.api.getOutputs(),1)
        t.bus.advance(1); equal(t.bridge.bundled.front,0)
    end
    function tests.clock_touch_editors_validate_world_time_duration_and_pattern_seconds_and_preserve_selected_routes()
        local t=setup(); t.view(t.id).screen="alarms"; t.click(t.id,"new","alarm")
        t.click(t.id,"field","minute"); t.click(t.id,"digit","Clr")
        for digit in ("2360"):gmatch(".") do t.click(t.id,"digit",digit) end
        t.click(t.id,"setNumber"); equal(t.view(t.id).screen,"message")
        t.click(t.id,"messageBack"); t.click(t.id,"digit","Clr")
        for digit in ("0715"):gmatch(".") do t.click(t.id,"digit",digit) end
        t.click(t.id,"setNumber"); equal(t.view(t.id).draft.minute,435)
        t.click(t.id,"draftSignal"); t.click(t.id,"field","off"); t.click(t.id,"digit","Clr"); t.click(t.id,"digit","0")
        t.click(t.id,"setNumber"); equal(t.view(t.id).screen,"message")
        t.click(t.id,"messageBack"); t.click(t.id,"digit","Clr"); t.click(t.id,"digit","3"); t.click(t.id,"setNumber")
        t.click(t.id,"route"); t.click(t.id,"select","io_11"); t.click(t.id,"select","front"); t.click(t.id,"select",32768); t.click(t.id,"use")
        t.click(t.id,"field","total"); t.click(t.id,"digit","Clr"); t.click(t.id,"digit","0"); t.click(t.id,"setNumber")
        equal(t.view(t.id).draft.signal.total,0)
        t.click(t.id,"draftSignal"); t.click(t.id,"field","on"); t.click(t.id,"digit","Clr"); t.click(t.id,"digit","0"); t.click(t.id,"setNumber")
        equal(t.view(t.id).draft.signal.on,0); equal(t.view(t.id).screen,"edit")
        assert(table.concat(t.content(t.id),"\n"):find("Constant",1,true))
        t.click(t.id,"draftSignal"); equal(t.view(t.id).draft.signal.on,1)
        t.click(t.id,"saveDraft")
        local alarm=t.state.alarms[1]; equal(alarm.minute,435); equal(alarm.signal.kind,"pattern"); equal(alarm.signal.off,3); equal(alarm.route.color,32768)
        assert(t.api.save()); t.startCentral(t.central.disk)
        alarm=t.state.alarms[1]; equal(alarm.route.clientId,"io_11"); equal(alarm.route.side,"front"); equal(alarm.route.color,32768)
    end
    function tests.clock_expired_offline_signals_are_not_replayed_and_inactive_reference_deletion_preserves_other_apps()
        local t=setup({rate=0}); local timer=t.new(t.id,"timer",{duration=2},1)
        t.bridge.active=false; t.bus.advance(6)
        equal(timer.status,"done"); equal(timer.ring,nil); equal(t.output(timer,"timer"),false)
        local oldWrites=#t.bridge.redstoneWrites
        t.bridge=t.bus.computer(11,"io",{disk=t.bridge.disk,modemSide="right"}):start(); t.bus.advance(1)
        equal(t.bridge.bundled.front,0)
        assert(t.api.setOutput("clock_timer_"..timer.id,true))
        assert(t.api.mapOutput("other_app","io_11","front",1,false)); equal(t.api.getOutput("other_app"),true)
        t.click(t.id,"delete"); t.click(t.id,"confirmDelete")
        equal(t.api.getOutput("other_app"),true); equal(#t.api.getOutputs(),1)
    end
    function tests.clock_alarm_checkpoint_failure_retries_without_losing_the_crossing_or_double_firing_after_restart()
        local t=setup(); local alarm=t.new(t.id,"alarm",{minute=362},1)
        t.central.disk.failWrite=true; t.bus.advance(8)
        equal(t.output(alarm,"alarm"),false); equal(t.state.alarms[1].lastDay,nil)
        t.central.disk.failWrite=false; t.bus.advance(0.5)
        alarm=t.state.alarms[1]; assert(alarm.lastDay); equal(t.output(alarm,"alarm"),true)
        local day=alarm.lastDay; assert(t.api.save()); t.startCentral(t.central.disk); t.bus.advance(3)
        equal(t.state.alarms[1].lastDay,day); equal(t.output(t.state.alarms[1],"alarm"),false)
    end
    function tests.clock_alarm_fallback_without_os_day_keeps_midnight_rollover_and_restart_progress()
        local t=setup({offset=64700}); t.central.env.os.day=nil
        t.bus.advance(0.5) -- Rebase after the capability change.
        local alarm=t.new(t.id,"alarm",{minute=1},1)
        t.bus.advance(2); assert(alarm.lastDay~=nil)
        local day=alarm.lastDay; t.bus.advance(3); equal(alarm.lastDay,day)
    end
    function tests.clock_popups_fire_without_windows_or_output_routes_and_dismiss_globally()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{name="No IO needed",duration=1})
        assert(t.api.closeWindow(t.id)); equal(next(t.central.server.state.windows),nil)
        t.bus.advance(1)
        assert(timer.alert); equal(timer.ring,nil)
        local top,left=t.popup(),t.popup("left"); assert(top and left); equal(top.key,left.key)
        assert(table.concat(t.top.lines,"\n"):find("No IO needed",1,true)); assert(table.concat(t.left.lines,"\n"):find("OK",1,true))
        t.ack("left"); equal(timer.alert,nil); equal(t.popup(),nil); equal(t.popup("left"),nil)
        equal(next(t.central.server.state.windows),nil); equal(#t.api.getOutputs(),0)
    end
    function tests.clock_constant_zero_runs_until_ok_and_finite_constant_keeps_its_popup_after_output_ends()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=0,off=1,total=10}},1)
        t.bus.advance(20); assert(timer.ring); assert(timer.alert); equal(t.output(timer,"timer"),true)
        t.ack(); equal(timer.ring,nil); equal(timer.alert,nil); equal(t.output(timer,"timer"),false)
        t.bus.advance(1); equal(t.bridge.bundled.front,0)
        local finite=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=1,off=1,total=10}},2)
        t.bus.advance(3); equal(finite.ring,nil); assert(finite.alert); equal(t.output(finite,"timer"),false)
        assert(t.popup()); t.ack(); equal(finite.alert,nil)
    end
    function tests.clock_pattern_zero_keeps_cycling_and_can_be_dismissed_during_an_off_phase()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="pattern",on=1,off=2,total=0}},1)
        t.bus.advance(1.1); equal(t.output(timer,"timer"),true)
        t.bus.advance(1); equal(t.output(timer,"timer"),false); assert(t.popup())
        t.bus.advance(2); equal(t.output(timer,"timer"),true)
        t.bus.advance(1); equal(t.output(timer,"timer"),false)
        t.ack("left"); equal(timer.alert,nil); equal(timer.ring,nil)
        t.bus.advance(10); equal(t.output(timer,"timer"),false); equal(t.bridge.bundled.front,0)
    end
    function tests.clock_selectable_bundled_dismiss_input_stops_the_signal_and_closes_every_popup()
        local t=setup({rate=0,manualAlerts=true})
        t.click(t.id,"timers"); t.click(t.id,"new","timer")
        t.view(t.id).draft.duration=1; t.view(t.id).draft.signal={kind="constant",on=0,off=1,total=10}
        t.click(t.id,"route"); t.click(t.id,"select","io_11"); t.click(t.id,"select","front"); t.click(t.id,"select",1); t.click(t.id,"use")
        t.click(t.id,"dismissInput"); t.click(t.id,"select","io_11"); t.click(t.id,"select","left"); t.click(t.id,"select",4); t.click(t.id,"use")
        t.click(t.id,"saveDraft"); local timer=t.state.timers[1]
        equal(timer.dismissInput.clientId,"io_11"); equal(timer.dismissInput.side,"left"); equal(timer.dismissInput.color,4)
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"]).appStates.clock
        equal(saved.timers[1].dismissInput.color,4)
        t.bus.advance(1); assert(timer.alert); equal(t.output(timer,"timer"),true)
        t.bridge.bundledInputs.left=2; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5); assert(timer.alert)
        t.bridge.bundledInputs.left=4; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5)
        equal(timer.alert,nil); equal(timer.ring,nil); equal(t.popup(),nil); equal(t.popup("left"),nil); equal(t.output(timer,"timer"),false)
        t.bus.advance(1); equal(t.bridge.bundled.front,0)
    end
    function tests.clock_dismiss_input_requires_a_new_press_after_held_high_offline_or_restart()
        local t=setup({rate=0,manualAlerts=true})
        t.bridge.digitalInputs.left=true; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5)
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=0,off=1,total=10},dismissInput={clientId="io_11",side="left"}},1)
        t.bus.advance(2); assert(timer.alert); equal(timer.alert.inputArmed,false)
        t.bridge.digitalInputs.left=false; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5); equal(timer.alert.inputArmed,true)
        assert(t.api.save()); t.startCentral(t.central.disk)
        timer=t.state.timers[1]; equal(timer.alert.inputArmed,false)
        t.bridge.digitalInputs.left=true; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(5); assert(timer.alert)
        t.bridge.digitalInputs.left=false; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5); equal(timer.alert.inputArmed,true)
        t.bridge.active=false; t.bus.advance(16); equal(timer.alert.inputArmed,false)
        t.bridge=t.bus.computer(11,"io",{disk=t.bridge.disk,modemSide="right"})
        t.bridge.digitalInputs.left=true; t.bridge:start(); t.bus.advance(1); assert(timer.alert)
        t.bridge.digitalInputs.left=false; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5)
        t.bridge.digitalInputs.left=true; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(0.5)
        equal(timer.alert,nil); equal(timer.ring,nil); equal(t.popup(),nil)
    end
    function tests.clock_popup_queue_and_indefinite_phase_restore_after_reboot_and_reach_late_monitors()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="pattern",on=1,off=1,total=0}},1)
        t.bus.advance(2.5); assert(t.api.save())
        local id,progress=timer.alert.id,timer.ring.elapsed
        t.central.active=false; t.bus.advance(20); t.startCentral(t.central.disk)
        timer=t.state.timers[1]; equal(timer.alert.id,id); equal(timer.ring.elapsed,progress)
        t.bus.advance(5); assert(t.popup()); assert(t.popup("left"))
        local late=t.bus.computer(16,"monitor",{monitors={top=monitor(20,10)}}):start(); t.paint()
        assert(t.central.server.monitors["monitor_16:top"].notification)
        t.ack("left"); equal(timer.alert,nil); equal(timer.ring,nil)
        equal(t.central.server.monitors["monitor_16:top"].notification,nil)
        equal(t.popup(),nil); equal(t.output(timer,"timer"),false)
    end
    function tests.clock_old_pulse_states_migrate_without_resetting_progress_or_alerting_for_finished_history()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=10,off=1,total=10}},1)
        t.new(t.id,"timer",{duration=1})
        t.bus.advance(1.5); assert(t.api.save())
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        local old=saved.appStates.clock; old.version,old.nextAlertId=1,nil
        for _,item in ipairs(old.timers) do item.signal.kind,item.alert="pulse",nil end
        local progress=old.timers[1].ring.elapsed
        t.central.disk.files["configs_os_state.txt"]=serialize(saved); t.startCentral(t.central.disk)
        equal(t.state.version,2); equal(t.state.timers[1].signal.kind,"constant"); equal(t.state.timers[1].ring.elapsed,progress)
        assert(t.state.timers[1].alert); equal(t.state.timers[2].alert,nil)
        equal(#t.central.server.notifications.clock,1)
    end
    function tests.clock_ok_and_redstone_dismissal_keep_popup_and_output_until_the_checkpoint_succeeds()
        local t=setup({rate=0,manualAlerts=true})
        local timer=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=0,off=1,total=10}},1)
        t.bus.advance(1); local id=timer.alert.id
        t.central.disk.failWrite=true; t.ack("left")
        equal(t.state.timers[1].alert.id,id); equal(t.output(t.state.timers[1],"timer"),true); assert(t.popup()); assert(t.popup("left"))
        assert(t.central.server.monitors["monitor_13:left"].notificationError)
        t.central.disk.failWrite=false; t.ack("left"); equal(t.state.timers[1].alert,nil); equal(t.output(t.state.timers[1],"timer"),false)
        local second=t.new(t.id,"timer",{duration=1,signal={kind="constant",on=0,off=1,total=10},dismissInput={clientId="io_11",side="left"}},2)
        t.bus.advance(1); assert(second.alert.inputArmed)
        t.central.disk.failWrite=true; t.bridge.digitalInputs.left=true; t.bus.queue(t.bridge,{"redstone"}); t.bus.advance(1)
        assert(t.state.timers[2].alert); equal(t.output(t.state.timers[2],"timer"),true)
        t.central.disk.failWrite=false; t.bus.advance(0.5)
        equal(t.state.timers[2].alert,nil); equal(t.output(t.state.timers[2],"timer"),false); equal(t.popup(),nil)
    end
    function tests.clock_ok_on_one_shared_signal_leaves_the_other_popup_and_signal_running()
        local t=setup({rate=0,manualAlerts=true})
        local a=t.new(t.id,"timer",{name="First",duration=1,signal={kind="constant",on=0,off=1,total=10}},1)
        local b=t.new(t.id,"timer",{name="Second",duration=2,signal={kind="constant",on=0,off=1,total=10}},1)
        t.bus.advance(2.5); assert(a.alert and b.alert); local first=t.popup().key
        t.ack("left"); equal(a.alert,nil); assert(b.alert); equal(t.output(a,"timer"),true); equal(t.output(b,"timer"),true)
        assert(t.popup().key~=first); equal(t.popup().key,t.popup("left").key)
        t.ack(); equal(b.alert,nil); equal(t.output(a,"timer"),false); equal(t.popup(),nil)
    end
    function tests.clock_repeated_or_stale_popup_taps_never_acknowledge_the_next_alarm_or_click_through()
        local t=setup({rate=0,manualAlerts=true})
        local a=t.new(t.id,"timer",{duration=1}); local b=t.new(t.id,"timer",{duration=1})
        t.bus.advance(1)
        local popup=t.popup()
        for _=1,4 do t.bus.queue(t.display,{"monitor_touch","top",popup.ok.x1,popup.ok.y}) end
        t.bus.pump(); equal(a.alert,nil); assert(b.alert)
        local packet; for _,p in ipairs(t.bus.wire) do if p.sender.id==13 and p.message.type=="touch" then packet=p end end
        for _=1,3 do t.bus.queue(t.central,{"modem_message",t.central.modemSide,45231,packet.reply,packet.raw,12}) end
        t.bus.pump(); assert(b.alert); t.ack(); equal(b.alert,nil)
    end
    function tests.clock_popup_geometry_tracks_resizes_and_invalid_publications_cannot_replace_pending_alerts()
        local t=setup({rate=0,manualAlerts=true}); local timer=t.new(t.id,"timer",{duration=1})
        t.bus.advance(1); local original=t.popup().key
        equal(t.api.setNotifications("clock",{{key="same",title="A",message="B"},{key="same",title="C",message="D"}}),false)
        equal(t.api.setNotifications("clock",{{key="bad",title="A\n",message="B"}}),false)
        equal(t.popup().key,original)
        local mon=t.central.server.monitors["monitor_13:top"]
        for _,size in ipairs({{1,2},{8,4},{13,7},{20,10},{64,26}}) do
            mon.width,mon.height=size[1],size[2]
            -- Render directly to avoid sending sizes unlike the physical mock.
            t.central.server.refreshMonitors(true); t.bus.events={}
            local p=mon.notification
            assert(p.x>=1 and p.y>=1 and p.x+p.width-1<=size[1] and p.y+p.height-1<=size[2])
            assert(p.ok.x1>=p.x and p.ok.x2<=p.x+p.width-1 and p.ok.y>=p.y and p.ok.y<=p.y+p.height-1)
        end
        mon.width,mon.height=64,26; t.paint(); t.ack(); equal(timer.alert,nil)
    end
    function tests.clock_all_screens_keep_touch_rectangles_and_styles_disjoint_at_every_supported_size()
        local t=setup(); local alarm=t.new(t.id,"alarm",{minute=600},1)
        local timer=t.new(t.id,"timer",{duration=1000})
        for _,size in ipairs({{12,6},{13,7},{24,10},{38,14},{44,18},{79,30}}) do
            for _,screen in ipairs({"home","alarms","timers","detail","edit","number","keyboard","routeInfo","stopwatch","delete","settings","status","about","message"}) do
                for _,kind in ipairs({"alarm","timer"}) do
                    local item=kind=="alarm" and alarm or timer
                    local draft={kind=kind,id=item.id,revision=item.revision,name="Test",minute=600,enabled=true,daily=true,mode="game",duration=1000,
                        route={clientId="io_11",side="front",color=1},signal={kind="pattern",on=2,off=2,total=10}}
                    local view={screen=screen,kind=kind,id=item.id,pages={},draft=draft,number={key="on",draft="10"},keyboard={draft="Test",bank=0,page=1},message="Test"}
                    -- Force both the lap pager and long wrapping paths.
                    t.state.stopwatch.laps={}; for i=1,20 do t.state.stopwatch.laps[i]={number=i,elapsed=i,split=1} end
                    local lines=t.app.render(size[1],size[2],t.state,t.api,{appName="clock",windowId=t.id,view=view})
                    equal(#lines,size[2]); for _,line in ipairs(lines) do equal(#line,size[1]) end
                    local occupied={}
                    for _,hit in ipairs(lines.hits) do
                        local y1,y2=hit.y or hit.y1,hit.y or hit.y2
                        assert(hit.x1>=1 and hit.x2<=size[1] and y1>=1 and y2<=size[2],screen.." hit out of bounds")
                        for y=y1,y2 do for x=hit.x1,hit.x2 do local key=x..":"..y; assert(not occupied[key],screen.." overlapping controls"); occupied[key]=true end end
                    end
                    for _,style in ipairs(lines.styles) do assert(style.x>=1 and style.y>=1 and style.width>=1 and style.height>=1 and style.x+style.width-1<=size[1] and style.y+style.height-1<=size[2],screen.." style out of bounds") end
                end
            end
        end
    end
end
