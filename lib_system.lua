-- Read-only overview of the central computer and its live client registry.
local app={}
local function find(list,id) for _,item in ipairs(list or {}) do if item.id==id then return item end end end
local function join(values) return #values>0 and table.concat(values,", ") or "None" end
local function elapsed(seconds)
    seconds=math.floor(seconds or 0)
    return math.floor(seconds/3600).."h "..math.floor(seconds/60)%60 .."m "..seconds%60 .."s"
end
local function route(address,api)
    return api.clientName(address.clientId).." / "..address.side.." / "..(address.color and api.ui.colourName(address.color) or "Digital")
end
function app.init(state)
    if not ({all=true,io=true,monitor=true,sensor=true,relay=true})[state.filter] then state.filter="all" end
end
local function build(width,height,state,api,context)
    local view=context.view; view.pages=view.pages or {}
    local screen=view.screen or "home"
    local d=api.getDiagnostics()
    local ui=api.ui.form(width,height,view,api.getAppColour("@settings"))
    local menu=ui.menu
    local function info(title,lines,key,back)
        ui.info(title,lines,key,back and back[1][2] or "home")
        if back then ui.footer(back) end
    end
    if screen=="home" then
        local online,ports,targets,windows=0,0,0,#d.windows
        for _,client in ipairs(d.clients) do if client.online then online=online+1 end end
        for _,sensor in ipairs(d.sensors) do for _,port in ipairs(sensor.ports) do ports=ports+1; targets=targets+#(port.targets or {}) end end
        menu("System / "..online.." online",{{"Central computer","central"},{"Clients: "..#d.clients,"clients"},
            {"Sensors: "..ports.." / "..targets.." targets","sensors"},{"Outputs: "..#d.outputs,"outputs"},
            {"Apps: "..#d.apps,"apps"},{"Windows: "..windows,"windows"},{"Uptime history","uptime"},
            {"Relay map","relayMap"},{"Overview options","settings"}},"home",{{"Back","settingsHome"}})
    elseif screen=="central" then
        local s=d.system
        info("Central computer",{"Computer: "..s.computerId,"Network: "..s.networkId,"Session: "..s.session,
            "Wireless modem: "..(s.modemSide or "Detached"),"Server channel: "..tostring(s.channel),
            "Relay channel: "..tostring(s.relayChannel or "Disabled"),"Uptime: "..elapsed(s.uptime),
            "Last checkpoint: "..elapsed(s.lastSaveAge).." ago","World clock: "..s.gameTime,
            "Clock source: "..s.clockSource,"World day: "..tostring(s.worldDay or "Unavailable"),
            "Player indicator: "..(s.playerOnline and "Online" or "Offline"),
            "Only announced devices are known. No distance or chunk-loaded status is invented."},"central")
    elseif screen=="clients" or screen=="sensors" then
        local items={}
        for _,client in ipairs(d.clients) do
            if (screen=="sensors" and client.type=="sensor") or screen=="clients" and (state.filter=="all" or state.filter==client.type) then
                items[#items+1]={client.displayName.." / "..(client.online and "Online" or "Offline"),"client",client.id,true,client.online and 128 or 4096}
            end
        end
        if #items==0 then items[1]={"No known clients","noop",nil,false} end
        menu(screen=="sensors" and "Sensor clients" or "Clients / "..state.filter,items,screen,{{"Back","home"},{"Filter","filter"}})
    elseif screen=="client" then
        local client=find(d.clients,view.clientId)
        if not client then info("Client",{"Waiting for client to announce"},"client",{{"Back",view.clientBack or "clients"}})
        else
            local lines={client.displayName,"ID: "..client.id,"Role: "..client.type,"Status: "..(client.online and "Online" or "Offline"),"Computer: "..client.computerId,
                "Reply channel: "..tostring(client.channel),"Last seen: "..elapsed(client.age).." ago","Relay hops: "..client.hops,
                "Route: "..(#client.via>0 and table.concat(client.via," > ") or "Direct")}
            if client.uptime then lines[#lines+1]="Connected: "..elapsed(client.uptime) end
            if client.type=="relay" then lines[#lines+1]="Forwarded packets: "..tostring(client.forwarded or 0) end
            if client.type=="monitor" then
                lines[#lines+1]="Size: "..client.width.." x "..client.height.." characters"
                lines[#lines+1]="Revisioned touches: "..(client.touchProtocol and "Yes" or "No")
                local count=0; for _,win in ipairs(d.windows) do if win.monitorId==client.id then count=count+1 end end
                lines[#lines+1]="Saved windows: "..count
            elseif client.type=="io" then
                local io=find(d.io,client.id)
                lines[#lines+1]="Usable sides: "..join(io and io.sides or {})
                lines[#lines+1]="Output revision / ACK: "..tostring(client.revision).." / "..tostring(client.ackedRevision)
                for _,side in ipairs(io and io.sides or {}) do
                    local input=api.getInput(client.id,side)
                    lines[#lines+1]=side..": "..(input and ("digital "..tostring(input.digital)..", mask "..tostring(input.value)) or "Unavailable")
                end
            elseif client.type=="sensor" then
                local sensor=find(d.sensors,client.id)
                if sensor then
                    lines[#lines+1]="Protocol: "..tostring(sensor.sensorProtocol or "Legacy").." / boot "..tostring(sensor.bootId)
                    if sensor.catalogError then lines[#lines+1]="Catalog: "..sensor.catalogError end
                    for _,port in ipairs(sensor.ports) do
                        lines[#lines+1]=port.side..": "..(port.error or port.status or "Unknown")
                        lines[#lines+1]="Card: "..tostring(port.card or "None")
                        lines[#lines+1]="Targets: "..#(port.targets or {})
                    end
                    for _,pending in ipairs(sensor.pending) do lines[#lines+1]=pending.side..": "..pending.received.."/"..pending.parts.." catalog parts" end
                end
            end
            info("Client details",lines,"client:"..client.id,client.type=="sensor" and {{"Back",view.clientBack or "clients"},{"Targets","targets"}} or {{"Back",view.clientBack or "clients"}})
        end
    elseif screen=="targets" then
        local sensor=find(d.sensors,view.clientId); local items={}
        for _,port in ipairs(sensor and sensor.ports or {}) do for _,target in ipairs(port.targets or {}) do
            items[#items+1]={port.side..": "..(target.label or target.name or target.type or target.key),"target",{side=port.side,key=target.key}}
        end end
        if #items==0 then items[1]={"No catalog targets","noop",nil,false} end
        menu("Sensor targets",items,"targets:"..tostring(view.clientId),{{"Back","client"}})
    elseif screen=="target" then
        local lines={"Client: "..api.clientName(view.clientId),"Side: "..view.target.side,"Key: "..view.target.key}
        local sensor=find(d.sensors,view.clientId); local profile
        for _,port in ipairs(sensor and sensor.ports or {}) do if port.side==view.target.side then
            lines[#lines+1]="Card: "..tostring(port.card)
            if port.cardKind=="ae" then profile="ae_storage" end
            for _,target in ipairs(port.targets or {}) do if target.key==view.target.key then
                lines[#lines+1]="Name: "..tostring(target.label or target.name or "Unknown")
                lines[#lines+1]="Type: "..tostring(target.type or "Unknown")
                lines[#lines+1]="Raw: "..tostring(target.rawName or "Unavailable")
                lines[#lines+1]="Kind: "..tostring(target.kind or "Unknown")
                if target.position then lines[#lines+1]="Position: "..target.position.X..", "..target.position.Y..", "..target.position.Z end
            end end
        end end
        local cached=api.getSensorReading({clientId=view.clientId,side=view.target.side,target=view.target.key},{profile=profile})
        lines[#lines+1]="Cached sample: "..cached.status
        if cached.error then lines[#lines+1]=cached.error end
        if cached.age then lines[#lines+1]="Sample age: "..elapsed(cached.age) end
        if cached.status=="ok" and type(cached.data)=="table" then
            local keys={}; for key,value in pairs(cached.data) do if type(value)~="table" then keys[#keys+1]=key end end
            table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
            for i=1,math.min(#keys,48) do local key=keys[i]; lines[#lines+1]=tostring(key)..": "..tostring(cached.data[key]) end
        end
        lines[#lines+1]="Reads cached observations only; no new subscriptions or output changes."
        info("Target",lines,"target",{{"Back","targets"}})
    elseif screen=="outputs" then
        local items={}; for _,output in ipairs(d.outputs) do items[#items+1]={output.name.." / "..(output.value and "ON" or "OFF"),"output",output.name} end
        if #items==0 then items[1]={"No output routes","noop",nil,false} end
        menu("Mapped outputs",items,"outputs")
    elseif screen=="output" then
        local lines={"Route was removed"}
        for _,output in ipairs(d.outputs) do if output.name==view.output then lines={output.name,route(output,api),"Desired: "..(output.value and "ON" or "OFF"),
            "Client: "..(output.online and "Online" or "Offline"),"Acknowledged: "..(output.confirmed and "Yes" or "No / pending"),"Shared routes control the same physical wire."} end end
        info("Output details",lines,"output",{{"Back","outputs"}})
    elseif screen=="apps" then
        local lines={}
        for _,item in ipairs(d.apps) do lines[#lines+1]=item.title.." ("..item.name.."): "..(item.running and "Running" or "Stopped")..(item.backgroundService and " / background" or "") end
        if #lines==0 then lines={"No enabled user apps"} end
        info("Enabled apps",lines,"apps")
    elseif screen=="windows" then
        local lines={}
        for _,win in ipairs(d.windows) do
            lines[#lines+1]="#"..win.id.." "..(win.title or win.appName)..(win.minimized and " / minimized" or "")
            lines[#lines+1]=api.clientName(win.monitorId).." @ "..win.x..","..win.y.." "..win.width.."x"..win.height.." / "..(win.layout or "normal")
        end
        if #lines==0 then lines={"No saved windows"} end
        info("Saved windows",lines,"windows")
    elseif screen=="uptime" then
        local lines={}
        local events=api.getUptimeHistory()
        for i=#events,1,-1 do
            local item=events[i]
            local label=item.kind=="os" and "OS" or api.clientName(item.id)
            lines[#lines+1]=label.." / "..(item.kind=="os" and (item.online and "Started" or "Stopped") or item.online and "Online" or "Offline")
            local date=item.day and ("Day "..item.day.." ") or ""
            lines[#lines+1]=date..item.time..(item.seconds and " / "..elapsed(item.seconds) or "")
        end
        if #lines==0 then lines[1]="No history yet" end
        info("Uptime history",lines,"uptime")
    elseif screen=="relayMap" then
        local items={}
        for _,client in ipairs(d.clients) do
            local route={}
            for _,id in ipairs(client.via) do route[#route+1]=api.clientName(id) end
            items[#items+1]={client.displayName.." / "..(#route>0 and #route.." hops" or "Direct"),"path",client.id}
        end
        if #items==0 then items[1]={"No connected clients",nil,nil,false} end
        menu("Relay map",items,"map")
    elseif screen=="path" then
        local client=find(d.clients,view.clientId)
        local lines={"OS "..d.system.computerId}
        if client then
            for i=#client.via,1,-1 do lines[#lines+1]=" > "..api.clientName(client.via[i]) end
            lines[#lines+1]=" > "..client.displayName
            lines[#lines+1]=client.online and "Online" or "Last observed route"
            if client.type=="relay" then
                lines[#lines+1]="Devices using this relay"
                for _,device in ipairs(d.clients) do
                    for _,hop in ipairs(device.via) do
                        if hop==client.id then lines[#lines+1]=device.displayName; break end
                    end
                end
            end
        end
        info("Observed path",lines,"path",{{"Back","relayMap"},{"Details","pathClient",nil,client~=nil}})
    elseif screen=="settings" then
        menu("Overview options",{{"Client filter: "..state.filter,"filter"},{"About","about"}},"settings")
    elseif screen=="about" then
        info("About CC system",{"Live registry, routes, card catalogs, IO confirmations, enabled apps and saved windows. Offline clients remain visible during this OS session; a restart waits for announcements. Sensors and machine readings are never restored as live. Sensor bindings and app settings are saved by their owning apps. Client paths are based on received packets."},"about",{{"Back","settings"}})
    end
    return ui.finish()
end
function app.render(w,h,state,api,context) return (build(w,h,state,api,context)) end
function app.handleTouch(x,y,w,h,state,api,context)
    local hits = context.hits
    if not hits then local _; _, hits = build(w,h, state, api, context) end
    local view=context.view
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then
        local action,value=hit.action,hit.value
        if action=="page" then view.pages[value.key]=value.page
        elseif action=="client" and value then view.clientId,view.screen,view.clientBack=value,"client",view.screen or "clients"
        elseif action=="path" then
            if value then view.clientId,view.pages.path=value,1 end
            view.screen="path"
        elseif action=="pathClient" then view.screen,view.clientBack="client","path"
        elseif action=="settingsHome" then view.exit=true
        elseif action=="target" and value then view.target,view.screen=value,"target"
        elseif action=="output" and value then view.output,view.screen=value,"output"
        elseif action=="filter" then
            local options={"all","io","monitor","sensor","relay"}; local old=state.filter
            for i,item in ipairs(options) do if item==old then state.filter=options[i%#options+1]; break end end
            local ok=api.save(); if not ok then state.filter=old end
            view.pages.clients=nil
        elseif action=="accent" then api.pickColour(context.windowId)
        elseif action~="noop" and action~="refresh" then view.screen=action end
        return true
    end end
    return false
end
return app
