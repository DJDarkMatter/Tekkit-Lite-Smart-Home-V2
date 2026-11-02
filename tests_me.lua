-- Run these on LuaJ 2.0.3 as well as native Lua 5.1: its frontier matcher
-- crashes at a string boundary, unlike the native interpreter.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local Me=dofile("lib_me.lua")
    function tests.me_shared_hv_detection_handles_labels_raw_names_and_legacy_string_boundaries()
        for _,name in ipairs({"HV Solar","HV-Solar Array","High Voltage Solar Array","tile.HVSolarArray","Hochspannungs-Solarpanel"}) do
            equal(Me.isHVSolar({name=name}),true,name)
        end
        for _,name in ipairs({"LV Solar","MV Solar Array","HV Cable","Minium Shard","UU Matter",""}) do equal(Me.isHVSolar({name=name}),false,name) end
        equal(Me.isHVSolar({raw="tile.HVSolarArray",name="Solaranlage"}),true)
        equal(Me.isHVSolar(nil),false); equal(Me.isHVSolar({name=4,raw=false}),false)
    end
    function tests.me_shared_snapshots_request_complete_items_isolate_read_errors_and_recover()
        local broken=false; local sequence=1
        local api={getSensorClients=function() return {{id="sensor",bootId="boot"}} end}
        function api.getSensorReading(binding,options)
            equal(options.profile,"ae_items")
            if broken then error("Disconnected test source") end
            return {status="ok",sequence=sequence,dataSequence=sequence,time=sequence,age=0,
                data={Powered=true,Items={{RawName="iron",Name="Iron",DamageValue=0,Size=27}}}}
        end
        local cache={}; local a={clientId="sensor",side="top",target="me"}
        local s=Me.snapshot(cache,api,a); equal(s.status,"ok"); equal(s.total,27); equal(s.types,1)
        broken=true; s=Me.snapshot(cache,api,a); equal(s.status,"error"); assert(s.error:find("Disconnected test source",1,true)); equal(Me.count(s,Me.itemKey("iron",0,"Iron")),nil)
        broken=false; sequence=2; s=Me.snapshot(cache,api,a); equal(s.status,"ok"); equal(Me.count(s,Me.itemKey("iron",0,"Iron")),27)
    end
    function tests.me_shared_partial_compact_items_are_unknown_not_zero_and_malformed_rows_do_not_throw()
        local api={getSensorClients=function() return {} end}; local reading={status="ok",sequence=1,dataSequence=1,time=1,
            data={Powered=true,ItemsComplete=false,ItemsFormat="ae_compact_v1",Items={}}}
        function api.getSensorReading() return reading end
        local cache={}; local a={clientId="sensor",side="top",target="me"}; local s=Me.snapshot(cache,api,a)
        equal(s.status,"unsupported"); equal(Me.count(s,"anything"),nil)
        reading.data.ItemsComplete=true; reading.data.Items={{"item",0,"Item",3}}; reading.dataSequence=2
        s=Me.snapshot(cache,api,a); equal(s.status,"ok"); equal(s.total,3)
        reading.data.Items={{"item",0,"Item","bad"}}; reading.dataSequence=3
        s=Me.snapshot(cache,api,a); equal(s.status,"unsupported"); assert(s.error:find("Invalid",1,true))
    end
    function tests.me_shared_solar_rejects_the_unsafe_old_core_before_starting_or_changing_saved_data()
        local legacy=Me.copy(Me); legacy.safePatterns=nil
        local f=assert(loadfile("apps_solar_farm.lua")); setfenv(f,setmetatable({dofile=function(path) equal(path,"lib_me.lua"); return legacy end},{__index=_G}))
        local app=f(); local state={}; local ok,err=pcall(app.init,state,{ui={form=function() end},migrateAppState=function() end},{appName="solar_farm"})
        equal(ok,false); assert(tostring(err):find("bundled-v31",1,true)); equal(next(state),nil)
    end
end
