-- Shared fixtures for item monitoring and fullscreen apps. Real-mode tests run
-- actual OS, sensor, IO and monitor entry points with separate computer disks.
return function(newBus,monitor,serialize,unserialize,equal)
    local function read(path) local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s end
    return function(which,unit,options)
        options=options or {}; local t={now=0,sequence=0,boot=1,unit=unit,which=which}
        t.main={{Name="UU Matter",RawName="ic2.matter",DamageValue=0,Size=200000},
            {Name="HV Solar",RawName="solar.hv",DamageValue=0,Size=1000},
            {Name="LV Solar",RawName="solar.lv",DamageValue=0,Size=40},
            {Name="Iron Ingot",RawName="item.iron",DamageValue=0,Size=37389404}}
        t.farm={{Name="UU Matter",RawName="ic2.matter",DamageValue=0,Size=5000},
            {Name="LV Solar",RawName="solar.lv",DamageValue=0,Size=64},
            {Name="Minium Shard",RawName="item.minium",DamageValue=0,Size=32}}
        t.data={main={Powered=true,Items=t.main},farm={Powered=true,Items=t.farm}}
        t.width,t.height=options.width or 54,options.height or 20
        local sources={}
        for _,name in ipairs({"solar_farm","level_emitter","screensaver"}) do sources["apps_"..name..".lua"]=read("apps_"..name..".lua") end
        if unit then
            local env=setmetatable({os={clock=function() return t.now end}},{__index=_G})
            t.app=assert(loadstring(sources["apps_"..which..".lua"])); setfenv(t.app,env); t.app=t.app()
            t.state=options.state or {}; t.views={[1]={}}; t.outputs={}; t.outputMap={}; t.notifications={}
            local api={aeItemProfiles=true,fullscreenApps=true,fullscreenCornerNavigation=true,ui=dofile("lib_gui.lua"),getAppColour=function() return 2048 end,
                getSensorClients=function() return {{id="sensor_14",bootId=t.boot}} end,watchSensor=function() end,unwatchSensor=function() end,
                getOutput=function(name) return t.outputs[name]==true end,readInput=function() return t.input end,
                pickIO=function() return true end,pickSensor=function() return true end,pickColour=function() return true end}
            function api.getOutputs() local out={}; for name in pairs(t.outputMap) do out[#out+1]={name=name} end; return out end
            function api.getSensorReading(binding)
                return {status=t.offline and "offline" or "ok",error=t.offline and "Sensor offline" or nil,
                    time=t.now,age=0,sequence=t.sequence,dataSequence=t.sequence,data=t.data[binding.target]}
            end
            function api.save() if t.failSave then return false,"Simulated save failure" end; t.saved=serialize(t.state); return true end
            function api.updateOutputs(changes)
                if t.failSave then return false,"Simulated save failure" end
                for _,c in ipairs(changes) do
                    if c.remove then t.outputMap[c.name],t.outputs[c.name]=nil,nil
                    else
                        if c.clientId then t.outputMap[c.name]={clientId=c.clientId,side=c.side,color=c.color} end
                        if c.value~=nil then t.outputs[c.name]=c.value elseif t.outputs[c.name]==nil then t.outputs[c.name]=c.initialValue or false end
                    end
                end
                return api.save()
            end
            function api.setNotifications(_,entries) t.notifications=entries; return true end
            function api.invalidateAppViews() t.invalidated=(t.invalidated or 0)+1 end
            function api.getAppData() return nil end
            function api.migrateAppState() return false,"Use real OS for migration tests" end
            t.api=api; t.app.init(t.state,api,{appName=which})
            function t.paint() end
            function t.view(id) return t.views[id or 1] end
            function t.window() return {width=t.width+2,height=t.height+2} end
            function t.advance(seconds) t.now,t.sequence=t.now+seconds,t.sequence+1; if t.app.background then t.app.background(seconds,t.state,t.api) end end
        else
            t.bus=newBus()
            t.central=t.bus.computer(10,"server",{apps=sources}):start()
            t.card={card="openccsensors.item.appliedenergisticssensor",targets={main={Name="ME Wireless Access Point"},farm={Name="ME Wireless Access Point"}},details=t.data}
            t.sensor=t.bus.computer(14,"sensor",{sensors={top=t.card}}):start()
            t.bridge=t.bus.computer(11,"io",{modemSide="right"}):start()
            t.top,t.left=monitor(options.monitorWidth or 64,options.monitorHeight or 26),monitor(15,10)
            t.display=t.bus.computer(13,"monitor",{monitors={top=t.top,left=t.left}}):start()
            function t.reload() t.api,t.app,t.state=t.central.server.api,t.central.server.apps[which],t.central.server.state.appStates[which] end
            t.reload()
            function t.paint() t.central.server.refreshMonitors(true); t.bus.pump() end
            function t.view(id) return t.central.server.views[id or t.id] end
            function t.window(id) return t.central.server.state.windows[id or t.id] end
            function t.advance(seconds) t.bus.advance(seconds) end
            function t.open(side,appName) local id=assert(t.api.openApp(appName or which,"monitor_13:"..(side or "top"),1,1)); t.paint(); return id end
            function t.popup(side) t.paint(); return t.central.server.monitors["monitor_13:"..(side or "top")].notification end
            function t.ack(side) local p=assert(t.popup(side)); t.bus.queue(t.display,{"monitor_touch",side or "top",p.ok.x1,p.ok.y}); t.bus.pump() end
            function t.reboot() t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start(); t.reload(); t.advance(6); t.paint() end
            t.advance(2)
            if options.noOpen~=true then t.id=t.open() end
        end
        if unit then t.id=1 end
        function t.context(id) return {appName=which,windowId=id or t.id,view=t.view(id),fullscreen=not unit and t.window(id) and t.window(id).fullscreen or false} end
        function t.content(id,w,h)
            local win=t.window(id); local inset=win.fullscreen and 0 or 2
            return t.app.render(w or win.width-inset,h or win.height-inset,t.state,t.api,t.context(id))
        end
        function t.text(id) return table.concat(t.content(id),"\n") end
        function t.touchHit(hit,id)
            id=id or t.id; local x,y=math.floor((hit.x1+hit.x2)/2),hit.y or hit.y1
            if unit then t.app.handleTouch(x,y,t.width,t.height,t.state,t.api,t.context(id))
            else local win=t.window(id); local inset=win.fullscreen and 0 or 1
                t.bus.queue(t.display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+inset+x-1,win.y+inset+y-1}); t.bus.pump() end
        end
        function t.click(action,value,id)
            id=id or t.id
            for _=1,100 do
                t.paint(); local dialog=not unit and t.central.server.dialogs[id]
                local hits=dialog and dialog.hits or t.content(id).hits; local nextHit
                for _,hit in ipairs(hits or {}) do if hit.enabled~=false then
                    local v=type(hit.value)=="table" and hit.value.value or hit.value
                    if hit.action==action and (value==nil or type(value)=="function" and value(hit.value) or v==value) then t.touchHit(hit,id); return end
                    local page=type(hit.value)=="table" and (hit.value.page or hit.value.value)
                    if hit.action=="next" or hit.action=="page" and page and page>(t.view(id).pages[hit.value.key] or 1) then nextHit=hit end
                end end
                if not nextHit then break end
                t.touchHit(nextHit,id)
            end
            error("Missing "..which.." action "..action.." on "..tostring(t.view(id).screen))
        end
        function t.configure()
            for _,role in ipairs({"main","farm"}) do
                assert(t.app.handleSensorSelection(role,{clientId="sensor_14",side="top",target=role},t.state,t.api,t.context()))
            end
            t.advance(3); t.advance(3); t.view().screen="home"
        end
        function t.pin(raw)
            t.view().screen="home"; t.click("pin"); t.click("selectItem",function(v) return v.raw==raw end)
            for _,m in ipairs(t.state.metrics) do if m.item.raw==raw then return m end end
        end
        return t
    end
end
