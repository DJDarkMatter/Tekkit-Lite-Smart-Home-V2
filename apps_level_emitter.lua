-- Independent item-level alarms. All physical writes use the OS IO queue.
local Me=dofile("lib_me.lua")
local app={title="Level emitter",backgroundService=true,minWidth=12,minHeight=6,preferredWidth=50,preferredHeight=20}
local name,ready,lastError="level_emitter",false,nil
local caches,values,holds,frozen={},{},{},{}
local copy,integer,number=Me.copy,Me.integer,Me.number
local function find(state,id) return Me.find(state.rules,id) end
local function output(rule) return rule.outputName or name.."_rule_"..rule.id end
local function wire(route) return route.clientId..":"..route.side..":"..tostring(route.color or "digital") end
local function validSignal(s)
    return type(s)=="table" and (s.kind=="constant" or s.kind=="pattern")
        and integer(s.on,s.kind=="constant" and 0 or 1,86400) and integer(s.off,1,86400) and integer(s.total,0,31536000)
end
local function length(rule) return rule.signal.kind=="constant" and rule.signal.on or rule.signal.total end
local function active(rule)
    return rule.ring and (length(rule)==0 or rule.ring.elapsed<length(rule))
        and (rule.signal.kind=="constant" or rule.ring.elapsed%(rule.signal.on+rule.signal.off)<rule.signal.on) or false
end
local operators={under="Under",over="Over",exact="Exactly",at_least="At least"}
local function condition(rule,q)
    return rule.operator=="under" and q<rule.threshold or rule.operator=="over" and q>rule.threshold
        or rule.operator=="exact" and q==rule.threshold or rule.operator=="at_least" and q>=rule.threshold
end
local function rearm(rule,q)
    if rule.operator=="exact" then return q~=rule.threshold end
    return rule.operator=="under" and q>=rule.reset or rule.operator~="under" and q<=rule.reset
end
local function publish(state,api)
    local entries={}
    for _,r in ipairs(state.rules) do if r.alert then entries[#entries+1]={key="level_"..r.id.."_"..r.alert.id,title="Level emitter",message=r.name,id=r.alert.id} end end
    table.sort(entries,function(a,b) return a.id<b.id end)
    return api.setNotifications(name,entries)
end
local function wireChanges(state,touched,api)
    local groups={}
    for _,r in ipairs(state.rules) do if r.route and touched[wire(r.route)] then
        local key=wire(r.route); groups[key]=groups[key] or {name=output(r),value=false}
        groups[key].value=groups[key].value or active(r)
    end end
    local result={}; for _,change in pairs(groups) do if api.getOutput(change.name)~=change.value then result[#result+1]=change end end
    return result
end
local function notice(view,text,back) view.message,view.back,view.screen=tostring(text),back or view.screen or "home","message" end
local function commit(state,api,view,change,outputs)
    local old=copy(state); change()
    local ok,err=api.updateOutputs(type(outputs)=="function" and outputs() or outputs or {})
    if not ok then Me.restore(state,old); lastError=tostring(err); if view then notice(view,"Save failed: "..lastError) end; return false,err end
    lastError=nil; assert(publish(state,api)); api.invalidateAppViews(name); return true
end
local function remember(state,item)
    if not state.catalog[item.key] then
        local count=0; for _ in pairs(state.catalog) do count=count+1 end
        if count>=1024 then
            local used,remove={},{}
            for _,r in ipairs(state.rules) do used[r.item.key]=true end
            for key in pairs(state.catalog) do if not used[key] then remove[#remove+1]=key end end
            table.sort(remove); assert(remove[1],"Saved catalog is full"); state.catalog[remove[1]]=nil
        end
    end
    state.catalog[item.key]=Me.identity(item)
end
local function migrate(state,api)
    local old=api.getAppData("solar_farm")
    if not old or old.version~=1 or type(old.alarms)~="table" or #old.alarms==0 then return end
    assert(api.migrateAppState("solar_farm",name,function(src,dst)
        if #dst.rules+#src.alarms>64 then return false,"Too many rules to migrate; remove unused Level emitter rules first" end
        local ordered=copy(src.alarms)
        table.sort(ordered,function(a,b) return (a.alert and a.alert.id or Me.MAX)<(b.alert and b.alert.id or Me.MAX) end)
        for _,oldRule in ipairs(ordered) do
            local r=copy(oldRule)
            r.id,dst.nextId=dst.nextId,dst.nextId+1
            r.sensor=copy(src.sources and src.sources[oldRule.source]); r.sourceLabel=oldRule.source=="main" and "Main ME" or "Farm ME"
            r.source,r.operator,r.outputName=nil,"at_least","solar_farm_alarm_"..oldRule.id
            if r.alert then r.alert.id,dst.nextAlertId=dst.nextAlertId,dst.nextAlertId+1 end
            dst.rules[#dst.rules+1]=r; dst.catalog[r.item.key]=Me.identity(r.item)
        end
        src.alarms={}; src.alarmsMovedTo=name
        -- Retain registered absent identities for future rule selection too.
        local count,used,unused=0,{},{}
        for _,r in ipairs(dst.rules) do used[r.item.key]=true end
        for key in pairs(dst.catalog) do count=count+1; if not used[key] then unused[#unused+1]=key end end
        table.sort(unused)
        for i=1,math.max(0,count-1024) do dst.catalog[unused[i]]=nil; count=count-1 end
        for key,item in pairs(src.catalog or {}) do
            if not dst.catalog[key] and count<1024 and Me.itemValid(item) then dst.catalog[key]=Me.identity(item); count=count+1 end
        end
        dst.imported=(dst.imported or 0)+#ordered
        return true
    end))
end
function app.init(state,api,context)
    ready=false; caches,values,holds,frozen,lastError={},{},{},{},nil
    assert(api.migrateAppState and api.getAppData and api.ui.form,"Level emitter requires bundled-v30 OS")
    name=context and context.appName or "level_emitter"
    if state.version==nil then
        state.version,state.rules,state.catalog,state.nextId,state.nextAlertId=1,{},{},1,1
        state.settings={background=32768,panel=128}
    end
    assert(state.version==1 and type(state.rules)=="table" and #state.rules<=64 and type(state.catalog)=="table"
        and type(state.settings)=="table" and Me.colour(state.settings.background) and Me.colour(state.settings.panel),"Invalid saved Level emitter")
    migrate(state,api)
    local ids,alerts,maxId,maxAlert={},{},0,0
    local count=0
    for key,item in pairs(state.catalog) do assert(Me.itemValid(item) and key==item.key,"Invalid level item catalog"); count=count+1 end
    assert(count<=1024,"Level item catalog is full")
    for _,r in ipairs(state.rules) do
        assert(type(r)=="table" and integer(r.id,1,2147483000) and not ids[r.id] and Me.label(r.name) and Me.itemValid(r.item)
            and (r.sensor==nil or Me.address(r.sensor)) and operators[r.operator] and integer(r.threshold,0,Me.MAX)
            and (r.operator=="exact" or integer(r.reset,0,Me.MAX)) and integer(r.hold,0,86400)
            and type(r.enabled)=="boolean" and type(r.latched)=="boolean" and integer(r.revision,1,Me.MAX)
            and validSignal(r.signal) and (r.route==nil or Me.route(r.route)) and (r.dismissInput==nil or Me.route(r.dismissInput))
            and (r.outputName==nil or Me.textValue(r.outputName,96) and r.outputName:match("^[%w_-]+$")),"Invalid saved level rule")
        ids[r.id],maxId=true,math.max(maxId,r.id)
        if r.alert then
            assert(integer(r.alert.id,1,2147483000) and not alerts[r.alert.id] and type(r.alert.inputArmed)=="boolean","Invalid saved level alert")
            alerts[r.alert.id],maxAlert,r.alert.inputArmed=true,math.max(maxAlert,r.alert.id),false
        end
        if r.ring then assert(r.alert and r.route and number(r.ring.elapsed,0,Me.MAX),"Invalid saved output signal") end
    end
    assert(integer(state.nextId,maxId+1,2147483001) and integer(state.nextAlertId,maxAlert+1,2147483001),"Invalid level rule IDs")
    local known={}; for _,o in ipairs(api.getOutputs()) do known[o.name]=true end
    local changes={}; for _,r in ipairs(state.rules) do if r.route and not known[output(r)] then
        changes[#changes+1]={name=output(r),clientId=r.route.clientId,side=r.route.side,color=r.route.color,initialValue=false}
    end end
    if #changes>0 then assert(api.updateOutputs(changes)) end
    ready=true; assert(publish(state,api))
end
function app.background(dt,state,api)
    if not ready then return end
    dt=math.max(0,dt or 0)
    if dt>10 then holds={} end
    local boots=Me.boots(api); local snapshots={}
    for _,r in ipairs(state.rules) do
        if r.sensor then
            api.watchSensor(name.."_rule_"..r.id,r.sensor,{profile="ae_items"})
            local key=Me.sourceKey(r.sensor)
            if not snapshots[key] then snapshots[key]=Me.snapshot(caches,api,r.sensor,boots) end
            values[r.id]=snapshots[key]
        else values[r.id]={status="unconfigured",items={}} end
    end
    local old,touched,important=copy(state),{},false
    for _,r in ipairs(state.rules) do
        if r.ring then
            touched[wire(r.route)]=true; r.ring.elapsed=r.ring.elapsed+dt
            if length(r)>0 and r.ring.elapsed>=length(r) then r.ring=nil; important=true end
        end
        local s=values[r.id]; local q=Me.count(s,r.item.key)
        local hold=holds[r.id]
        if hold and hold.key~=s.key then hold=nil; holds[r.id]=nil end
        if r.enabled and q~=nil then
            if r.latched and not r.alert and rearm(r,q) then r.latched=false; important=true end
            if not r.latched and not r.alert and condition(r,q) then
                hold=hold or {elapsed=0,key=s.key}; holds[r.id]=hold
                if hold.started then hold.elapsed=hold.elapsed+dt else hold.started=true end
                if hold.elapsed>=r.hold then
                    r.alert={id=state.nextAlertId,inputArmed=r.dismissInput and api.readInput(r.dismissInput)==false or false}
                    state.nextAlertId,r.latched,r.revision=state.nextAlertId+1,true,r.revision+1
                    if r.route then r.ring={elapsed=0}; touched[wire(r.route)]=true end
                    important=true
                end
            else holds[r.id]=nil end
        else holds[r.id]=nil end
        if r.alert and r.dismissInput then
            local input=api.readInput(r.dismissInput)
            if input==false then r.alert.inputArmed=true elseif input==nil then r.alert.inputArmed=false
            elseif r.alert.inputArmed then
                if r.route then touched[wire(r.route)]=true end
                r.alert,r.ring,r.revision=nil,nil,r.revision+1; important=true
            end
        end
    end
    local changes=wireChanges(state,touched,api)
    if important or #changes>0 then
        local ok,err=api.updateOutputs(changes)
        if not ok then Me.restore(state,old); lastError="Checkpoint pending: "..tostring(err) else lastError=nil end
    end
    assert(publish(state,api))
end
function app.handleNotification(key,state,api)
    local selected
    for _,r in ipairs(state.rules) do if r.alert and key=="level_"..r.id.."_"..r.alert.id then selected=r end end
    if not selected then return publish(state,api) end
    local touched={}; if selected.route then touched[wire(selected.route)]=true end
    return commit(state,api,nil,function() selected.alert,selected.ring,selected.revision=nil,nil,selected.revision+1 end,
        function() return wireChanges(state,touched,api) end)
end
local function newDraft() return {name="Level rule",operator="over",threshold=10000,reset=10000,hold=0,enabled=true,signal={kind="constant",on=0,off=1,total=0}} end
function app.handleSensorSelection(key,binding,state,api,context)
    if not Me.address(binding) then return false,"Invalid ME target" end
    local view=context.view
    if key=="new" then view.draft=newDraft() end
    if not view.draft then return false,"Editor was closed" end
    view.draft.sensor,view.draft.sourceLabel=copy(binding),nil
    view.screen=key=="new" and "items" or "edit"; view.pages={}; frozen[context.windowId]=nil
    return true
end
function app.handleIOSelection(key,address,state,api,context)
    if not context.view.draft or not Me.route(address) or (key~="signal" and key~="dismiss") then return false,"Editor was closed" end
    context.view.draft[key=="signal" and "route" or "dismissInput"]=copy(address); return true
end
local function itemsFor(view,state,api,windowId)
    local d=view.draft; if not d or not d.sensor then return {},{status="unconfigured"} end
    api.watchSensor(name.."_picker_"..windowId,d.sensor,{profile="ae_items"})
    local s=Me.snapshot(caches,api,d.sensor)
    local key=Me.sourceKey(d.sensor)..":"..(view.query or "")..":"..(view.sort or "name")..":"..tostring(view.descending)
    if frozen[windowId] and frozen[windowId].key==key then return frozen[windowId].rows,s end
    local all={}; for k,item in pairs(s.items) do all[k]=Me.identity(item) end
    for k,item in pairs(state.catalog) do all[k]=Me.identity(item) end
    local rows,query={},(view.query or ""):lower()
    for _,item in pairs(all) do if query=="" or item.name:lower():find(query,1,true) or item.raw:lower():find(query,1,true) then rows[#rows+1]=item end end
    table.sort(rows,function(a,b)
        if view.sort=="amount" then local x,y=Me.count(s,a.key) or -1,Me.count(s,b.key) or -1
            if x~=y then return view.descending and x>y or not view.descending and x<y end end
        local x,y=a.name:lower(),b.name:lower()
        if x~=y then return view.descending and x>y or not view.descending and x<y end
        return a.key<b.key
    end)
    if s.status=="ok" then frozen[windowId]={key=key,rows=rows} end
    return rows,s
end
local function form(w,h,state,api,context)
    local view=context.view; view.pages=view.pages or {}
    local screen=view.screen or "home"; local r=find(state,view.id)
    if (screen=="rule" or screen=="details" or screen=="delete") and not r then view.screen,screen="home","home" end
    if (screen=="edit" or screen=="items") and not view.draft then view.screen,screen="home","home" end
    local accent=api.getAppColour(name)
    local ui=api.ui.form(w,h,view,accent,state.settings.background,state.settings.panel)
    local function caption(rule) return operators[rule.operator].." "..Me.amount(rule.threshold) end
    if screen=="home" then
        ui.heading("Level emitter",accent)
        local rowH=w>=34 and 1 or 2; local slots=math.max(1,math.floor((h-3)/rowH))
        if #state.rules>slots then slots=math.max(1,math.floor((h-4)/rowH)) end
        local first=ui.page("rules",#state.rules,slots,h-2)
        for i=1,slots do local rule=state.rules[first+i]; if rule then
            local y=2+(i-1)*rowH; local q=Me.count(values[rule.id],rule.item.key)
            local bg=rule.alert and 2 or rule.enabled and accent or state.settings.panel
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            if rowH==1 then
                local text=Me.amount(q); ui.put(1,y,rule.name,w-#text-1); ui.put(w-#text+1,y,text,#text)
            else ui.put(1,y,rule.name,w); ui.put(1,y+1,(rule.enabled and "ON " or "OFF ")..caption(rule),w,true) end
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="open",value=rule.id}
        end end
        if #state.rules==0 then ui.put(1,2,"No level rules",w,true) end
        ui.footer({{"+ Add","new",nil,#state.rules<64},{"Menu","settings"}})
    elseif screen=="rule" then
        ui.menu(r.name,{{"Current: "..Me.amount(Me.count(values[r.id],r.item.key)),"noop",nil,false},
            {caption(r),"noop",nil,false},{r.enabled and "Disable" or "Enable","toggle"},{"Edit rule","editRule",nil,not r.alert},
            {"Item and IO details","details"},{"Delete rule","delete"}},"rule")
    elseif screen=="edit" then
        local d=view.draft
        local rows={{"Name: "..d.name,"textField","name"},{"Item: "..(d.item and d.item.name or "Select"),"items"},
            {d.sourceLabel or (d.sensor and "ME: "..d.sensor.clientId or "Select ME"),"source"},
            {"Condition: "..operators[d.operator],"condition"},{"Level: "..Me.amount(d.threshold),"field","threshold"},
            {"Hold: "..d.hold.."s","field","hold"},{d.enabled and "Enabled: Yes" or "Enabled: No","draftEnabled"}}
        if d.operator~="exact" then rows[#rows+1]={"Rearm: "..Me.amount(d.reset),"field","reset"} end
        rows[#rows+1]={d.route and "Output: "..d.route.clientId or "Select output (optional)","route"}
        rows[#rows+1]={d.dismissInput and "Dismiss: "..d.dismissInput.clientId or "Select dismiss input","dismissInput"}
        rows[#rows+1]={"Signal: "..d.signal.kind,"signal"}
        rows[#rows+1]={d.signal.kind=="constant" and ("Length: "..(d.signal.on==0 and "Until OK" or d.signal.on.."s")) or "On: "..d.signal.on.."s","field","on"}
        if d.signal.kind=="pattern" then rows[#rows+1]={"Off: "..d.signal.off.."s","field","off"}; rows[#rows+1]={"Total: "..(d.signal.total==0 and "Until OK" or d.signal.total.."s"),"field","total"} end
        if d.route then rows[#rows+1]={"Disconnect output","clearRoute"} end
        if d.dismissInput then rows[#rows+1]={"Clear dismiss input","clearInput"} end
        ui.menu("Level rule",rows,"edit",{{"Save","saveRule"},{"Cancel","cancelEdit"}})
    elseif screen=="condition" then
        ui.menu("Compare item count",{{"Under (<)","operator","under"},{"Over (>)","operator","over"},{"Exactly (=)","operator","exact"}},"condition",{{"Back","edit"}})
    elseif screen=="items" then
        local rows,s=itemsFor(view,state,api,context.windowId)
        ui.heading("Select item",s.status=="ok" and accent or 2)
        local rowH=w>=32 and 1 or 2; local slots=math.max(1,math.floor((h-2)/rowH))
        if #rows>slots then slots=math.max(1,math.floor((h-3)/rowH)) end
        local first=ui.page("items",#rows,slots,h-1)
        local same={}; for _,item in ipairs(rows) do same[item.name]=(same[item.name] or 0)+1 end
        for i=1,slots do local item=rows[first+i]; if item then
            local y=2+(i-1)*rowH; local text=Me.amount(Me.count(s,item.key)); local label=item.name..(same[item.name]>1 and " ["..item.damage.."]" or "")
            local bg=i%2==0 and state.settings.panel or state.settings.background
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            if rowH==1 then local span=math.min(#text,math.floor(w/2)); ui.put(1,y,label,w-span-1); ui.put(w-span+1,y,text,span)
            else ui.put(1,y,label,w); ui.put(1,y+1,text,w,true) end
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="selectItem",value=Me.identity(item)}
        end end
        if #rows==0 then ui.put(1,2,s.status=="ok" and "No items" or s.error or s.status,w,true) end
        ui.footer({{"Back","edit"},{"Find","filters"}})
    elseif screen=="filters" then
        ui.menu("Item list",{{"Search: "..(view.query or ""),"search"},{"Sort: "..(view.sort or "name"),"sort"},
            {view.descending and "Order: Down" or "Order: Up","direction"},{"Refresh","refresh"},{"Manual item","newManual"}},"filters",{{"Back","items"}})
    elseif screen=="manual" then
        local m=view.manual
        ui.menu("Register absent item",{{"Name: "..m.name,"manualText","name"},{"RawName: "..m.raw,"manualText","raw"},{"Damage: "..m.damage,"manualDamage"},
            {"Use item","saveManual",nil,Me.textValue(m.raw,256) and Me.textValue(m.name,256)}},"manual",{{"Back","items"}})
    elseif screen=="details" then
        local function path(a) return a and a.clientId.." / "..a.side.." / "..(a.color and api.ui.colourName(a.color) or "Digital") or "None" end
        ui.info(r.name,{r.item.name,"Raw: "..r.item.raw.." / "..r.item.damage,r.sourceLabel or "ME source",
            r.sensor and r.sensor.clientId.." / "..r.sensor.side.." / "..r.sensor.target or "Not selected",
            caption(r).." for "..r.hold.." seconds",r.operator=="exact" and "Rearms when count differs" or "Rearm level: "..Me.amount(r.reset),
            "Output: "..path(r.route),"Dismiss: "..path(r.dismissInput),"Constant length 0 or Pattern total 0 continues until OK or a new input press.",
            "Source: "..(values[r.id] and values[r.id].status or "waiting")},"details","rule")
    elseif screen=="delete" then
        ui.heading("Delete level rule?",accent); ui.put(1,2,r.name,w,true)
        ui.action(h-1,"Delete","confirmDelete",nil,nil,nil,true,16384); ui.footer({{"Cancel","rule"}})
    elseif screen=="settings" then
        ui.menu("Level emitter menu",{{"UI colour","accent"},{"About / alarm behavior","about"},
            {"Imported Solar rules: "..(state.imported or 0),"noop",nil,false}},"settings")
    elseif screen=="number" then ui.numberPad(view.number.key,view.number.draft,view.number.back)
    elseif screen=="keyboard" then ui.keyboard(view.keyboard)
    elseif screen=="message" or screen=="about" then
        ui.info("Level emitter",{screen=="message" and view.message or
            "Each rule selects its own AE sensor, item and Under / Over / Exactly condition. Any item may be registered even while absent. Comparisons use fresh complete inventories; offline is unknown, not zero. A hold needs continuous known matching data. Alerts latch until acknowledged, then rearm when the reset condition is observed. Exactly rearms when the count differs. Imported Solar rules retain their inclusive At least thresholds. Outputs use Constant or Pattern; zero length/total runs until OK or a fresh LOW-to-HIGH dismiss input. All rules and pending alerts survive reboot and continue with windows closed. High inputs at boot do not dismiss alerts. A popup is always shown; leave output unselected for popup-only alarms. Multiple rules can share an output; active signals are combined."},"info",screen=="message" and view.back or "settings")
    else view.screen="home"; return form(w,h,state,api,context) end
    return ui.lines,ui.hits
end
function app.render(w,h,state,api,context) if not ready then return {"Level emitter blocked","Check OS console"} end; return (form(w,h,state,api,context)) end
local function beginText(view,target,key,value,back,limit)
    view.keyboard={target=target,key=key,draft=value or "",bank=0,page=1,back=back,limit=limit or 24}; view.screen="keyboard"
end
local function saveRule(state,api,view)
    local d=view.draft; local r=d and d.id and find(state,d.id)
    if not d or not Me.label(d.name) or not Me.itemValid(d.item) or not Me.address(d.sensor) or not operators[d.operator]
        or not integer(d.threshold,0,Me.MAX) or not integer(d.hold,0,86400) or not validSignal(d.signal) or type(d.enabled)~="boolean"
        or (d.route and not Me.route(d.route)) or (d.dismissInput and not Me.route(d.dismissInput)) then notice(view,"Complete the item/source and settings","edit"); return end
    if d.operator~="exact" and (not integer(d.reset,0,Me.MAX) or d.operator=="under" and d.reset<d.threshold
        or d.operator~="under" and d.reset>d.threshold or d.operator=="at_least" and d.reset>=d.threshold) then notice(view,"Rearm level must be on the non-trigger side","edit"); return end
    if d.id and (not r or r.revision~=d.revision or r.alert) then notice(view,"Rule changed; reopen its editor","home"); return end
    if not r and #state.rules>=64 then notice(view,"Maximum 64 rules","home"); return end
    local created=r or {id=state.nextId,revision=0}
    local changes={}
    if d.route then changes[1]={name=output(created),clientId=d.route.clientId,side=d.route.side,color=d.route.color,initialValue=false}
    elseif r and r.route then changes[1]={name=output(created),remove=true} end
    if commit(state,api,view,function()
        if not r then state.rules[#state.rules+1]=created; state.nextId=state.nextId+1 end
        remember(state,d.item)
        for _,key in ipairs({"name","sensor","sourceLabel","item","operator","threshold","reset","hold","enabled","signal","route","dismissInput"}) do created[key]=copy(d[key]) end
        created.latched,created.revision=false,created.revision+1
    end,changes) then holds[created.id]=nil; view.id,view.draft,view.screen,view.pages=created.id,nil,"rule",{} end
end
function app.handleTouch(x,y,w,h,state,api,context)
    if not ready then return false end
    local _,hits=form(w,h,state,api,context); local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view; local r=find(state,view.id)
    if action=="page" then view.pages[value.key]=math.max(1,value.page)
    elseif ({home=true,settings=true,rule=true,details=true,edit=true,items=true,filters=true,manual=true,condition=true,number=true,keyboard=true,about=true})[action] then view.screen=action
    elseif action=="open" then view.id,view.screen=value,"rule"
    elseif action=="new" or action=="source" then
        local ok,err=api.pickSensor(context.windowId,action,view.draft and view.draft.sensor,"ae")
        if not ok then notice(view,err,"home") end
    elseif action=="editRule" and r then view.draft,view.screen=copy(r),"edit"
    elseif action=="selectItem" then
        view.draft.item=Me.identity(value)
        if view.draft.name=="Level rule" then view.draft.name=value.name:sub(1,24) end
        view.screen="edit"
    elseif action=="operator" then view.draft.operator,view.draft.reset,view.screen=value,view.draft.threshold,"edit"
    elseif action=="textField" then beginText(view,"draft",value,view.draft[value],"edit")
    elseif action=="field" or action=="manualDamage" then
        local key=action=="manualDamage" and "damage" or value
        local d=view.draft; local current=key=="damage" and view.manual.damage or d[key] or d.signal[key]
        view.number={key=key,draft=Me.digits(current or 0),back=action=="manualDamage" and "manual" or "edit"}; view.screen="number"
    elseif action=="draftEnabled" then view.draft.enabled=not view.draft.enabled
    elseif action=="signal" then
        local s=view.draft.signal; s.kind=s.kind=="constant" and "pattern" or "constant"; if s.kind=="pattern" and s.on==0 then s.on=1 end
    elseif action=="route" or action=="dismissInput" then
        local d=view.draft; local ok,err=api.pickIO(context.windowId,action=="route" and "signal" or "dismiss",action=="route" and "output" or "input",action=="route" and d.route or d.dismissInput)
        if not ok then notice(view,err,"edit") end
    elseif action=="clearRoute" then view.draft.route=nil
    elseif action=="clearInput" then view.draft.dismissInput=nil
    elseif action=="saveRule" then saveRule(state,api,view)
    elseif action=="cancelEdit" then view.screen=view.draft and view.draft.id and "rule" or "home"; view.draft=nil
    elseif action=="toggle" and r then
        local touched={}; if r.route then touched[wire(r.route)]=true end
        if commit(state,api,view,function() r.enabled=not r.enabled; r.revision=r.revision+1
            if not r.enabled then r.alert,r.ring,r.latched=nil,nil,false end end,function() return wireChanges(state,touched,api) end) then holds[r.id]=nil end
    elseif action=="delete" and r then view.screen="delete"
    elseif action=="confirmDelete" and r then
        local id=r.id
        if commit(state,api,view,function() local _,index=find(state,id); table.remove(state.rules,index) end,r.route and {{name=output(r),remove=true}} or {}) then
            api.unwatchSensor(name.."_rule_"..id); values[id],holds[id],view.screen=nil,nil,"home"
        end
    elseif action=="sort" then view.sort=view.sort=="amount" and "name" or "amount"; frozen[context.windowId]=nil
    elseif action=="direction" then view.descending=not view.descending; frozen[context.windowId]=nil
    elseif action=="refresh" then frozen[context.windowId]=nil; view.pages.items=nil; view.screen="items"
    elseif action=="search" then beginText(view,"search","query",view.query,"filters",64)
    elseif action=="newManual" then view.manual,view.screen={raw="",name="New item",damage=0},"manual"
    elseif action=="manualText" then beginText(view,"manual",value,view.manual[value],"manual",256)
    elseif action=="saveManual" then
        local m=view.manual; local item={raw=m.raw,name=m.name,damage=m.damage,key=Me.itemKey(m.raw,m.damage,m.name)}
        if Me.itemValid(item) then
            view.draft.item=item
            if view.draft.name=="Level rule" then view.draft.name=m.name:sub(1,24) end
            view.screen="edit"
        end
    elseif action=="digit" then
        local n=view.number
        if value=="Clr" then n.draft="" elseif value=="Del" then n.draft=n.draft:sub(1,-2)
        elseif #n.draft<16 then n.draft=(n.draft=="0" and "" or n.draft)..value end
    elseif action=="setNumber" then
        local n=view.number; local v=tonumber(n.draft=="" and "0" or n.draft); local low,high=0,Me.MAX
        if n.key=="hold" then high=86400 elseif n.key=="damage" then high=2147483647 elseif n.key=="total" then high=31536000
        elseif n.key=="on" or n.key=="off" then high=86400; low=(n.key=="off" or view.draft.signal.kind=="pattern") and 1 or 0 end
        if not integer(v,low,high) then notice(view,"Use a whole number in range","number")
        elseif n.key=="damage" then view.manual.damage,view.screen=v,"manual"
        else
            local d=view.draft
            if n.key=="on" or n.key=="off" or n.key=="total" then d.signal[n.key]=v else d[n.key]=v end
            if n.key=="threshold" then d.reset=d.operator=="at_least" and math.max(0,v-1) or v end
            view.screen="edit"
        end
    elseif action=="key" or action=="space" then local k=view.keyboard; if #k.draft<k.limit then k.draft=k.draft..(action=="space" and " " or value) end
    elseif action=="backspace" then view.keyboard.draft=view.keyboard.draft:sub(1,-2)
    elseif action=="clearText" then view.keyboard.draft=""
    elseif action=="bank" then view.keyboard.bank,view.keyboard.page=(view.keyboard.bank+1)%3,1
    elseif action=="keyPage" then
        local k=view.keyboard; local slots=math.max(4,math.min(10,math.floor(w/2)))*math.max(1,math.min(3,h-4)); k.page=k.page%math.ceil((k.bank==2 and 15 or 26)/slots)+1
    elseif action=="saveText" then
        local k=view.keyboard; local text=k.draft:gsub("^%s+",""):gsub("%s+$","")
        if k.target=="search" then view.query,view.screen=text,"items"; frozen[context.windowId]=nil; view.pages.items=nil
        elseif not Me.textValue(text,k.limit) then notice(view,"Enter a nonempty value","keyboard")
        else view[k.target][k.key],view.screen=text,k.back end
    elseif action=="accent" then local ok,err=api.pickColour(context.windowId); if not ok then notice(view,err,"settings") end end
    return true
end
function app.shutdown(state,api)
    for _,r in ipairs(state.rules) do api.unwatchSensor(name.."_rule_"..r.id) end
    caches,values,holds,frozen={},{},{},{}
end
return app
