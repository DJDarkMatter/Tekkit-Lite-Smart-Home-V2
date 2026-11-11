-- Cooperative work and event buffering through the actual central entry point.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local function drain(thread,hook)
        local count=0
        while true do
            local result={coroutine.resume(thread)}; assert(result[1],tostring(result[2]))
            if coroutine.status(thread)=="dead" then return result[2],count end
            equal(result[2],"pause"); count=count+1; assert(count<10000)
            if hook then hook() end
        end
    end
    function tests.work_startup_with_saved_state_recovers_when_software_wake_events_are_lost()
        local bus=newBus()
        local saved={appStates={retained={rows={}}},windows={},outputs={},outputMap={},managedSides={}}
        for i=1,1600 do saved.appStates.retained.rows[i]={id=i,text="Saved configuration "..i} end
        local disk={files={["configs_os_state.txt"]=serialize(saved)},dirs={[""]=true}}
        local central=bus.computer(10,"server",{disk=disk})
        -- Fill the native queue before boot, then drop a software event when
        -- that computer already has 256 pending events. The old startup never
        -- reached modem discovery after its first yield marker was dropped.
        for i=1,256 do bus.queue(central,{"queued_before_boot",i}) end
        local nativeQueue,dropped=central.env.os.queueEvent,0
        central.env.os.queueEvent=function(name,...)
            local count=0
            for _,item in ipairs(bus.events) do if item.comp==central then count=count+1 end end
            if count>=256 then dropped=dropped+1;return end
            nativeQueue(name,...)
        end
        central:start(); bus.advance(.2)
        assert(dropped>0,"Test did not exercise a dropped wake-up event")
        assert(central.server and central.open[45231],"OS startup stalled before opening its modem")
        local bridge=bus.computer(11,"io"):start(); bus.advance(1)
        assert(bridge.client.connected,"IO could not connect after saved-state startup")
        equal(#central.server.state.appStates.retained.rows,1600)
        equal(assert(unserialize(disk.files["configs_os_state.txt"])).appStates.retained.rows[1600].id,1600)
        assert(not disk.files["diagnostics_os_error.txt"])
    end
    function tests.work_running_os_handles_clients_and_commands_without_software_wake_events()
        local bus=newBus(); local central=bus.computer(10,"server"):start()
        central.env.os.queueEvent=function() end
        local bridge=bus.computer(11,"io"):start()
        local display=bus.computer(13,"monitor",{monitors={top=monitor(40,18)}}):start()
        local sensor=bus.computer(14,"sensor"):start()
        local relay=bus.computer(15,"relay"):start()
        bus.advance(2)
        assert(bridge.client.connected,"Lost software wake-up stalled IO discovery")
        assert(central.server.monitors["monitor_13:top"].online)
        assert(central.server.sensorClients["sensor_14"].online)
        assert(central.server.relayClients["relay_15"].online)
        bus.command(central,"help"); bus.advance(.1)
        assert(table.concat(central.console.lines,"\n"):find("clear | save | errorlog | quit",1,true))
        assert(central.server.lastTick>0)
    end
    function tests.work_boot_errors_leave_visible_progress_and_saved_diagnostics()
        local central=newBus().computer(10,"server")
        central.disk.files["configs_os.txt"]=serialize({tickInterval="invalid"})
        local ok,err=pcall(central.start)
        equal(ok,false);assert(tostring(err):find("Invalid OS setting: tickInterval",1,true))
        local lines=table.concat(central.console.lines,"\n")
        assert(lines:find("SmartHome OS v45: starting",1,true))
        assert(lines:find("OS stopped at: Loading OS configuration",1,true))
        assert(lines:find("Invalid OS setting: tickInterval",1,true))
        local report=assert(central.disk.files["diagnostics_os_error.txt"])
        assert(report:find("Loading OS configuration",1,true))
        assert(report:find("Invalid OS setting: tickInterval",1,true))
    end
    function tests.work_fast_startup_pauses_share_one_native_fallback_timer()
        local bus=newBus();local rows={}
        for i=1,1600 do rows[i]={id=i,text="Saved configuration "..i} end
        local central=bus.computer(10,"server")
        central.disk.files["configs_os_state.txt"]=serialize({appStates={retained={rows=rows}}})
        local startTimer,nativeFallbacks=central.env.os.startTimer,0
        central.env.os.startTimer=function(delay)
            if delay==0 then nativeFallbacks=nativeFallbacks+1 end
            return startTimer(delay)
        end
        central:start()
        assert(central.env.__smarthomeWork.yields>10)
        equal(nativeFallbacks,1,"Fast cooperative pauses must not accumulate fallback timers")
        assert(central.open[45231]);bus.advance(1);assert(central.active)
    end
    function tests.work_modem_checkpoint_survives_watchdog_rejection_of_software_wake()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        local bridge=bus.computer(11,"io"):start();bus.advance(.2)
        local rows={}
        for i=1,1600 do rows[i]={id=i,text="Saved configuration "..i} end
        central.server.state.appStates.retained={rows=rows}
        local queueEvent,startTimer=central.env.os.queueEvent,central.env.os.startTimer
        local rejected,saved=0,false
        central.env.os.startTimer=function(delay) return startTimer(delay==0 and .05 or delay) end
        central.env.os.queueEvent=function(name,...)
            if name=="smarthome_server_yield" and central.env.__smarthomeWork.stage=="Saving OS state" then
                rejected=rejected+1
                error("main_os.lua:67: Too long without yielding",0)
            end
            queueEvent(name,...)
        end
        local handle=central.server.handle
        central.server.handle=function(message,...)
            handle(message,...)
            if message.type=="inputData" and message.side=="front" and message.value==4 then
                assert(central.server.save());saved=true
            end
        end
        bridge.bundledInputs.front=4;bridge.client.readInputs(true)
        bus.advance(3)
        assert(rejected>0,"Checkpoint never exercised the failing wake-up call")
        assert(saved and central.active,"Watchdog rejection interrupted the checkpoint")
        local snapshot=assert(unserialize(central.disk.files["configs_os_state.txt"]))
        equal(#snapshot.appStates.retained.rows,1600)
        assert(not central.disk.files["diagnostics_os_error.txt"])
        bus.command(central,"help");bus.advance(2)
        assert(table.concat(central.console.lines,"\n"):find("clear | save | errorlog | quit",1,true))
    end
    function tests.work_modem_decode_survives_watchdog_rejection_of_software_wake()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        local bridge=bus.computer(11,"io"):start();bus.advance(.2)
        local queueEvent,startTimer=central.env.os.queueEvent,central.env.os.startTimer
        local rejected=0
        central.env.os.startTimer=function(delay) return startTimer(delay==0 and .05 or delay) end
        central.env.os.queueEvent=function(name,...)
            if name=="smarthome_server_yield" and central.env.__smarthomeWork.stage=="Receiving modem message" then
                rejected=rejected+1
                error("main_os.lua:67: Too long without yielding",0)
            end
            queueEvent(name,...)
        end
        local packet=serialize({protocol="SmartHomeOS/1",networkId="home",sender=11,recipient=10,
            clientId="io_11",type="unknown",padding=string.rep("X",40000)})
        bus.queue(central,{"modem_message",central.modemSide,45231,1011,packet,1})
        bus.advance(.3)
        assert(rejected>0 and central.active)
        bridge.bundledInputs.front=4;bridge.client.readInputs(true);bus.advance(.2)
        equal(central.server.api.getInput("io_11","front").value,4)
        assert(not central.disk.files["diagnostics_os_error.txt"])
    end
    function tests.work_checkpoint_bounds_buffered_packet_bytes_and_preserves_console_commands()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        local rows={}
        for i=1,6000 do rows[i]={id=i,text="Saved configuration "..i} end
        central.server.state.appStates.retained={rows=rows}
        local packet=string.rep("?",65536)
        local decode,queueEvent=central.env.textutils.unserialize,central.env.os.queueEvent
        local decoded,injected=0,false
        central.env.textutils.unserialize=function(raw)
            if raw==packet then decoded=decoded+1;return nil end
            return decode(raw)
        end
        central.env.os.queueEvent=function(name,...)
            queueEvent(name,...)
            if name=="smarthome_server_yield" and not injected and central.env.__smarthomeWork.stage=="Saving OS state" then
                injected=true
                for i=1,48 do bus.queue(central,{"modem_message",central.modemSide,45231,1011,packet,1}) end
                for char in ("help"):gmatch(".") do bus.queue(central,{"char",char}) end
                bus.queue(central,{"key",28})
            end
        end
        bus.command(central,"save");bus.advance(.2)
        assert(injected and central.active)
        equal(decoded,16,"The OS must cap buffered packets at one MiB during a save")
        local lines=table.concat(central.console.lines,"\n")
        assert(lines:find("OS receive queue full",1,true))
        assert(lines:find("clear | save | errorlog | quit",1,true))
        equal(#assert(unserialize(central.disk.files["configs_os_state.txt"])).appStates.retained.rows,6000)
        assert(not central.disk.files["diagnostics_os_error.txt"])
    end
    function tests.work_nested_protected_calls_yield_portably_preserve_nil_results_and_ignore_unowned_callers()
        local comp=newBus().computer(10,"server"); local work=comp.env.dofile("lib_work.lua")
        local calls=0
        local thread=coroutine.create(function()
            work.enable(function() calls=calls+1; coroutine.yield("pause") end,1)
            local ok,a,b,c=work.call(function()
                local success,x,y,z=work.call(function() work.check(1); return nil,"value",false end)
                assert(success); return x,y,z
            end)
            assert(ok); equal(a,nil); equal(b,"value"); equal(c,false)
            local failure={why="unchanged object"}
            local good,err=work.call(function() error(failure) end); equal(good,false)
            -- Old LuaJ stringifies non-string errors at its coroutine boundary.
            if type(err)=="string" then assert(err:find(tostring(failure),1,true)) else equal(err,failure) end
            work.disable(); return true
        end)
        local result,pauses=drain(thread,function() work.check(100000) end)
        equal(result,true); equal(pauses,1); equal(calls,1)
    end
    function tests.work_large_serializer_yields_and_round_trips_legacy_plain_data_without_shared_references()
        local comp=newBus().computer(10,"server"); local work=comp.env.dofile("lib_work.lua")
        local value={rows={},holes={[1]="first",[99]="last"},text="quotes \" slash \\ newline\n tab\t zero\000",flag=false,big="9007199254740991",
            precise={10/24,31/81,math.pi,1/100,9007199254740991,1e-20}}
        for i=1,1200 do value.rows[i]={id=i,name="item "..i,count=i*17} end
        local thread=coroutine.create(function()
            work.enable(function() coroutine.yield("pause") end,512)
            local text=work.serialize(value); work.disable(); return text
        end)
        local text,pauses=drain(thread); assert(pauses>20)
        local saved=assert(unserialize(text)); equal(#saved.rows,1200); equal(saved.rows[1200].count,20400)
        equal(saved.text,value.text); equal(saved.holes[99],"last"); equal(saved.holes[2],nil); equal(saved.flag,false); equal(saved.big,value.big)
        for index,number in ipairs(value.precise) do equal(saved.precise[index],number,"Saved numbers must round-trip exactly") end
    end
    function tests.work_serializer_rejects_cycles_without_replacing_saved_state()
        local comp=newBus().computer(10,"server"); local storage=comp.env.dofile("lib_storage.lua")
        local work=comp.env.dofile("lib_work.lua"); assert(storage.save("state",{safe=true}))
        local original=comp.disk.files.state; local shared={}; local cycle={};cycle.self=cycle
        for _,value in ipairs({{a=shared,b=shared},cycle}) do
            local thread=coroutine.create(function()
                work.enable(function() coroutine.yield("pause") end,8)
                local ok,err=storage.save("state",value); equal(ok,false); assert(tostring(err):find("recursive",1,true))
                work.disable(); return true
            end)
            drain(thread); equal(comp.disk.files.state,original)
        end
    end
    function tests.work_storage_reuses_validated_bytes_but_detects_external_corruption_before_rotating_backup()
        local comp=newBus().computer(10,"server"); local storage=comp.env.dofile("lib_storage.lua")
        local native,count=comp.env.textutils.unserialize,0
        comp.env.textutils.unserialize=function(...) count=count+1; return native(...) end
        assert(storage.save("state",{value=1})); assert(storage.save("state",{value=2})); equal(count,0)
        comp.disk.files.state="broken"; assert(storage.save("state",{value=3})); equal(count,1)
        equal(assert(unserialize(comp.disk.files["state.bak"])).value,1)
        comp.disk.files.state=serialize({value=99}); assert(storage.save("state",{value=4})); equal(count,2)
        equal(assert(unserialize(comp.disk.files["state.bak"])).value,99)
    end
    function tests.work_large_save_buffers_io_and_console_commands_until_the_transaction_finishes()
        local bus=newBus(); local app=[[return {backgroundService=true,
            init=function(s) s.phase="ready" end,
            background=function(dt,s,api)
                if s.once then return end; s.once=true; s.phase="writing";s.rows={}
                for i=1,1200 do s.rows[i]={id=i,count=i*17,name="item "..i} end
                assert(api.save());s.phase="ready"
            end}]]
        local central=bus.computer(10,"server",{apps={["apps_heavy.lua"]=app}}):start()
        local bridge=bus.computer(11,"io"):start(); local injected,commandPhase,inputPhase=false
        local nativeQueue=central.env.os.queueEvent
        local command=central.server.command
        central.server.command=function(line) commandPhase=central.server.state.appStates.heavy.phase;return command(line) end
        local handle=central.server.handle
        central.server.handle=function(message,...) if message.type=="inputData" and message.side=="front" then inputPhase=central.server.state.appStates.heavy.phase end;return handle(message,...) end
        central.env.os.queueEvent=function(event,...)
            nativeQueue(event,...)
            if event=="smarthome_server_yield" and not injected and central.env.__smarthomeWork.stage=="Saving OS state" then
                injected=true;bridge.bundledInputs.front=4;bridge.client.readInputs(true)
                for char in ("save"):gmatch(".") do bus.queue(central,{"char",char}) end
                bus.queue(central,{"key",28})
            end
        end
        bus.advance(1)
        assert(injected);equal(commandPhase,"ready");equal(inputPhase,"ready")
        equal(central.server.api.getInput("io_11","front").value,4)
        local state=assert(unserialize(central.disk.files["configs_os_state.txt"])).appStates.heavy
        equal(#state.rows,1200);equal(state.phase,"ready");equal(state.rows[1200].count,20400)
        assert(central.env.__smarthomeWork.yields>10)
    end
    function tests.work_large_render_buffers_a_monitor_touch_exactly_once()
        local bus=newBus(); local app=[[return {minWidth=8,minHeight=4,preferredWidth=120,preferredHeight=40,
            render=function(w,h,s,api) local ui=api.ui.content(w,h);ui.style(1,1,w,h,1,2048);ui.text(2,"Touch me");return ui.lines end,
            handleTouch=function(x,y,w,h,s) s.touches=(s.touches or 0)+1;return true end}]]
        local central=bus.computer(10,"server",{apps={["apps_heavy.lua"]=app}}):start()
        local screen=monitor(128,48);local display=bus.computer(13,"monitor",{monitors={top=screen}}):start()
        local id=assert(central.server.api.openApp("heavy","monitor_13:top",1,1));central.server.refreshMonitors(true);bus.pump()
        local injected=false;local nativeQueue=central.env.os.queueEvent
        central.env.os.queueEvent=function(event,...)
            nativeQueue(event,...)
            if event=="smarthome_server_yield" and not injected and central.env.__smarthomeWork.stage=="App heavy.render" then
                injected=true;local win=central.server.state.windows[id]
                bus.queue(display,{"monitor_touch","top",win.x+3,win.y+3})
            end
        end
        bus.advance(1);assert(injected);equal(central.server.state.appStates.heavy.touches,1)
        equal(central.server.state.windows[id].monitorId,"monitor_13:top")
    end
    function tests.work_large_live_me_catalog_uses_yield_safe_solar_sampling_and_remains_complete()
        local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
        local t=setup("solar_farm")
        for i=4,1500 do t.farm[i]={Name="Farm item "..i,RawName="item.farm"..i,DamageValue=0,Size=i*10} end
        local before=t.central.env.__smarthomeWork.yields
        t.configure();t.advance(3)
        local reading=t.api.getSensorReading({clientId="sensor_14",side="top",target="farm"},{profile="ae_items"})
        equal(reading.status,"ok");equal(reading.data.ItemsComplete,true)
        assert(t.central.env.__smarthomeWork.yields>before+10)
        assert(not t.central.disk.files["diagnostics_os_error.txt"],table.concat(t.central.log,"\n"))
        t.farm[1500].Size=t.farm[1500].Size+17;t.advance(3)
        local lines=t.text();assert(lines:find("Live",1,true));assert(not lines:find("App render failed",1,true))
        local saved=assert(unserialize(t.central.disk.files["configs_os_state.txt"])).appStates.solar_farm
        equal(saved.sources.farm.target,"farm");assert(saved.averages.farm.seconds>0)
    end
    function tests.work_fullscreen_screensavers_yield_in_real_server_frames_without_exceeding_modem_limit()
        local setup=assert(loadfile("tests_app_helpers.lua"))()(newBus,monitor,serialize,unserialize,equal)
        local t=setup("screensaver",false,{monitorWidth=256,monitorHeight=128})
        local before=t.central.env.__smarthomeWork.yields
        for design=1,15 do
            t.view().design=design;t.advance(.6)
            assert(t.central.active);assert(t.central.server.monitors["monitor_13:top"].lastRender)
            assert(not t.central.disk.files["diagnostics_os_error.txt"],table.concat(t.central.log,"\n"))
        end
        assert(t.central.env.__smarthomeWork.yields>before+100)
        local packets=0
        for _,packet in ipairs(t.bus.wire) do if packet.sender==t.central and packet.message.type=="render" then
            assert(#packet.raw<=61440);packets=packets+1
        end end
        assert(packets>=15)
    end
    function tests.work_app_errors_are_saved_once_and_remain_readable_after_reboot()
        local bus=newBus();local central=bus.computer(10,"server",{apps={["apps_fault.lua"]=[[return {backgroundService=true,
            background=function() error("simulated app failure",0) end}]]}}):start()
        bus.advance(1);local report=assert(central.disk.files["diagnostics_os_error.txt"])
        assert(report:find("App fault.background",1,true));assert(report:find("simulated app failure",1,true))
        local lines=central.server.command("errorlog");assert(table.concat(lines,"\n"):find("simulated app failure",1,true))
        central=bus.computer(10,"server",{disk=central.disk}):start()
        assert(table.concat(central.console.lines,"\n"):find("type errorlog",1,true));assert(central.active)
        bus.command(central,"errorlog");assert(table.concat(central.console.lines,"\n"):find("simulated app failure",1,true))
    end
    function tests.work_caught_watchdog_message_is_recorded_even_when_an_app_handles_the_failure()
        local comp=newBus().computer(10,"server");local work=comp.env.dofile("lib_work.lua")
        local thread=coroutine.create(function()
            work.enable(function() coroutine.yield("pause") end)
            work.stage="Handled ME sampling"
            local ok=work.call(function() error("Too long without yielding (caught)",0) end)
            equal(ok,false);work.disable();return true
        end)
        drain(thread)
        local report=assert(comp.disk.files["diagnostics_os_error.txt"])
        assert(report:find("Handled ME sampling",1,true));assert(report:find("Too long without yielding",1,true))
    end
    function tests.work_uncaught_worker_error_is_saved_without_an_automatic_reboot_loop()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        central.server.tick=function() error("Too long without yielding (simulated)",0) end
        local ok,err=pcall(bus.advance,1);equal(ok,false);assert(tostring(err):find("Too long without yielding",1,true))
        local report=assert(central.disk.files["diagnostics_os_error.txt"])
        assert(report:find("Background tick",1,true));assert(report:find("Too long without yielding",1,true))
        central=bus.computer(10,"server",{disk=central.disk}):start();bus.advance(1);assert(central.active)
        assert(table.concat(central.server.command("errorlog"),"\n"):find("Too long without yielding",1,true))
    end
    function tests.work_ordinary_termination_with_a_parallel_prefix_does_not_replace_a_saved_error()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        central.disk.files["diagnostics_os_error.txt"]="Earlier actual error"
        bus.queue(central,{"terminate"})
        local ok,err=pcall(bus.pump);equal(ok,false);assert(tostring(err):find("Terminated",1,true))
        equal(central.disk.files["diagnostics_os_error.txt"],"Earlier actual error")
        equal(central.env.__smarthomeWork.lastReport,nil)
    end
    function tests.work_health_announcements_render_only_the_monitor_being_resynchronized()
        local bus=newBus();local central=bus.computer(10,"server"):start()
        local display=bus.computer(13,"monitor",{monitors={top=monitor(60,24),left=monitor(40,18)}}):start()
        local ioClient=bus.computer(11,"io"):start();local server=central.server
        local top,left=server.monitors["monitor_13:top"],server.monitors["monitor_13:left"]
        top.lastRender,left.lastRender=nil,nil
        ioClient.client.announce(bus.now);bus.pump();equal(top.lastRender,nil);equal(left.lastRender,nil)
        local device=display.client.devices.top
        server.handle({type="announce",clientType="monitor",clientId=device.id,sender=13,nonce=device.nonce+1,
            width=60,height=24,touchProtocol=1},top.channel,bus.now)
        assert(top.lastRender);equal(left.lastRender,nil)
    end
end
