-- Solar farm stocks and main-ME stock-change estimates. No machine/farm control.
local app={title="Solar farm",backgroundService=true,minWidth=12,minHeight=6,preferredWidth=54,preferredHeight=20}
local appName,ready,lastError="solar_farm",false,nil
local sources,holds,pickers={},{},{}
local MAX=9007199254740991
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function restore(state,old)
    local keys={}; for key in pairs(state) do keys[#keys+1]=key end
    for _,key in ipairs(keys) do state[key]=nil end
    for key,value in pairs(old) do state[key]=value end
end
local function number(v,lo,hi) return type(v)=="number" and v==v and v>=lo and v<=hi end
local function integer(v,lo,hi) return number(v,lo,hi) and v==math.floor(v) end
local function digits(v)
    v=math.floor(math.abs(v)); local out={}
    repeat local n=v%10; out[#out+1]=("0123456789"):sub(n+1,n+1); v=math.floor(v/10) until v==0
    return table.concat(out):reverse()
end
local function amount(v,width)
    if v==nil then return "--" end
    local raw=(v<0 and "-" or "")..digits(v)
    local text=digits(v):reverse():gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
    text=(v<0 and "-" or "")..text
    return width and #text>width and raw or text
end
local function rateText(v,width)
    if v==nil then return "--/h" end
    local whole=math.floor(math.abs(v))
    local tenth=math.floor((math.abs(v)-whole)*10+0.5)
    if tenth==10 then whole,tenth=whole+1,0 end
    local text=(v<0 and "-" or v>0 and "+" or "")..amount(whole).."."..digits(tenth).."/h"
    if width and #text>width then text=(v<0 and "-" or v>0 and "+" or "")..digits(whole).."/h" end
    return text
end
local function colour(v) for i=0,15 do if v==2^i then return true end end; return false end
local function textValue(v,limit) return type(v)=="string" and #v>0 and #v<=limit and not v:find("[%c]") end
local function label(v) return textValue(v,24) and v:find("%S") end
local sides={top=true,bottom=true,left=true,right=true,front=true,back=true}
local function address(v) return type(v)=="table" and textValue(v.clientId,64) and sides[v.side] and textValue(v.target,128) end
local function route(v) return type(v)=="table" and textValue(v.clientId,64) and sides[v.side] and (v.color==nil or colour(v.color)) end
local function sourceKey(v) return #v.clientId..":"..v.clientId..v.side..":"..v.target end
local function itemKey(raw,damage,name)
    local identity=raw~="" and raw~="unknown" and raw or "name:"..name
    return #identity..":"..identity..":"..digits(damage)
end
local function itemValid(v)
    return type(v)=="table" and type(v.raw)=="string" and #v.raw<=256 and not v.raw:find("[%c]")
        and textValue(v.name,256) and integer(v.damage,0,2147483647) and v.key==itemKey(v.raw,v.damage,v.name)
end
local function identity(v) return {key=v.key,raw=v.raw,damage=v.damage,name=v.name} end
local function find(list,id) for index,item in ipairs(list) do if item.id==id then return item,index end end end
local function catalog(reading)
    local data=reading.data or {}
    if reading.status~="ok" then return nil,reading.error or reading.status end
    if data.Powered==false then return nil,"ME unpowered" end
    if data.ItemsOmitted or type(data.Items)~="table" then return nil,"Waiting for complete item list" end
    if data.ItemsFormat and data.ItemsFormat~="ae_compact_v1" then return nil,"Unknown item format" end
    local compact=data.ItemsFormat=="ae_compact_v1"
    local result,seen,total={},0,0
    for _,row in pairs(data.Items) do
        seen=seen+1
        if seen>8192 or type(row)~="table" then return nil,"Invalid item list" end
        local raw,name,damage,count
        if compact then raw,damage,name,count=row[1],row[2],row[3],row[4]
        else raw,name,damage,count=row.RawName or "",row.Name or row.RawName,row.DamageValue or row.Damagevalue or 0,row.Size end
        if type(raw)~="string" or #raw>256 or raw:find("[%c]") or type(name)~="string" or #name>256
            or not integer(damage,0,2147483647) or not integer(count,0,MAX) then return nil,"Invalid item identity/count" end
        name=name:gsub("[%c]"," "); if name=="" then name=raw~="" and raw or "Unknown item" end
        local key=itemKey(raw,damage,name)
        local item=result[key]
        if not item then item={key=key,raw=raw,damage=damage,name=name,count=0}; result[key]=item end
        if not integer(item.count+count,0,MAX) or not integer(total+count,0,MAX) then return nil,"Item count overflow" end
        item.count,total=item.count+count,total+count
        if name:lower()<item.name:lower() then item.name=name end
    end
    return result,nil,total
end
local function cached(role) return sources[role] or {status="unconfigured",error="Select "..role.." ME",items={},rates={}} end
local function count(role,key)
    local s=cached(role); if s.status~="ok" then return nil end
    return s.items[key] and s.items[key].count or 0
end
local function metricFor(state,key) for _,m in ipairs(state.metrics) do if m.item.key==key then return m end end end
local function filter(state,key)
    local metric=metricFor(state,key)
    return metric and metric.dropCount or state.settings.dropCount,metric and metric.dropPercent or state.settings.dropPercent
end
local function resetRates(state,key)
    for _,m in ipairs(state.metrics) do if not key or m.item.key==key then
        m.history,m.ignored,m.omitted,m.since={},0,0,state.elapsed
    end end
    if key and sources.main then sources.main.rates[key]=nil else sources.main=nil end
end
local function historyAdd(metric,time,delta,seconds)
    local bucket=math.floor(time/60)
    local row=metric.history[#metric.history]
    if not row or row[1]~=bucket then row={bucket,0,0}; metric.history[#metric.history+1]=row end
    row[2],row[3]=row[2]+delta,row[3]+seconds
    while #metric.history>60 or #metric.history>0 and metric.history[1][1]<bucket-59 do table.remove(metric.history,1) end
end
local function measured(state,metric)
    local delta,seconds=0,0
    local cutoff=math.floor(state.elapsed/60)-state.settings.window/60+1
    for _,row in ipairs(metric.history) do if row[1]>=cutoff then delta,seconds=delta+row[2],seconds+row[3] end end
    if cached("main").status~="ok" or not cached("main").measured then return nil,seconds end
    return seconds>0 and delta/seconds*3600 or nil,seconds
end
local function liveRate(key)
    local s=cached("main"); local r=s.rates[key]
    if s.status~="ok" or not s.measured then return nil end
    if r then return r.weight>0 and r.value/r.weight*3600 or nil end
    return 0
end
local function scanSource(role,state,api,boots)
    local binding=state.sources[role]
    if not binding then sources[role]=nil; return end
    api.watchSensor(appName.."_"..role,binding,{profile="ae_items"})
    local reading=api.getSensorReading(binding)
    local key=sourceKey(binding)..":"..tostring(boots[binding.clientId])
    local s=sources[role]
    if not s or s.key~=key then s={key=key,items={},rates={},status="waiting"}; sources[role]=s end
    s.age=reading.age
    if reading.status~="ok" or reading.data and reading.data.Powered==false then
        s.status,s.error,s.previous,s.measured=reading.status=="ok" and "unpowered" or reading.status,
            reading.status=="ok" and "ME unpowered" or reading.error or reading.status,nil,false
        return
    end
    local items,err,total
    if s.dataSequence==reading.dataSequence and s.status=="ok" then items,total=s.items,s.total
    else items,err,total=catalog(reading) end
    if not items then s.status,s.error,s.previous,s.measured="unsupported",err,nil,false; return end
    s.status,s.error,s.total,s.data="ok",nil,total,reading.data
    local fresh=s.sampleSequence~=reading.sequence or s.sampleTime~=reading.time
    s.dataSequence=reading.dataSequence
    if not fresh then return end
    local previous=s.previous
    local dt=previous and reading.time and reading.time-previous.time or 0
    local valid=previous and number(dt,0.001,10) and reading.sequence and reading.sequence>previous.sequence
    if role=="main" then
        if valid then
            local keys={}
            for k in pairs(previous.items) do keys[k]=true end
            for k in pairs(items) do keys[k]=true end
            for _,metric in ipairs(state.metrics) do keys[metric.item.key]=true end
            local rates={}
            local decay=math.exp(-dt/30)
            for k in pairs(keys) do
                local old=previous.items[k] and previous.items[k].count or 0
                local value=items[k] and items[k].count or 0
                local delta=value-old
                local minimum,percent=filter(state,k)
                local excluded=delta<0 and -delta>=math.max(minimum,math.ceil(old*percent/100))
                local rec=s.rates[k] or {value=0,weight=0}
                if not excluded then rec.value,rec.weight=rec.value*decay+delta/dt*(1-decay),rec.weight*decay+1-decay end
                rec.excluded,rec.lastDelta=excluded,delta
                rates[k]=rec
                local metric=metricFor(state,k)
                if metric and state.elapsed-dt+0.001>=metric.since then
                    if excluded then metric.ignored,metric.omitted=metric.ignored+1,math.min(MAX,metric.omitted-delta)
                    else historyAdd(metric,state.elapsed,delta,dt) end
                end
            end
            s.rates,s.measured=rates,true
        else s.rates,s.measured={},false end
    end
    s.items,s.sampleSequence,s.sampleTime=items,reading.sequence,reading.time
    if number(reading.time,0,MAX) and integer(reading.sequence,0,MAX) then
        s.previous={items=items,time=reading.time,sequence=reading.sequence}
    else s.previous,s.measured=nil,false end
end
local function outputName(alarm) return appName.."_alarm_"..alarm.id end
local function wire(v) return v.clientId..":"..v.side..":"..tostring(v.color or "digital") end
local function signalValid(v)
    return type(v)=="table" and (v.kind=="constant" or v.kind=="pattern") and integer(v.on,v.kind=="constant" and 0 or 1,86400)
        and integer(v.off,1,86400) and integer(v.total,0,31536000)
end
local function length(alarm) return alarm.signal.kind=="constant" and alarm.signal.on or alarm.signal.total end
local function signalOn(alarm)
    return alarm.ring and (length(alarm)==0 or alarm.ring.elapsed<length(alarm))
        and (alarm.signal.kind=="constant" or alarm.ring.elapsed%(alarm.signal.on+alarm.signal.off)<alarm.signal.on) or false
end
local function publish(state,api)
    local entries={}
    for _,a in ipairs(state.alarms) do if a.alert then
        entries[#entries+1]={key="alarm_"..a.id.."_"..a.alert.id,title=a.source=="main" and "Main ME buildup" or "Farm ME buildup",message=a.name,id=a.alert.id}
    end end
    table.sort(entries,function(a,b) return a.id<b.id end)
    return api.setNotifications(appName,entries)
end
local function wireChanges(state,touched,api)
    local groups={}
    for _,a in ipairs(state.alarms) do if a.route and touched[wire(a.route)] then
        local key=wire(a.route); groups[key]=groups[key] or {name=outputName(a),value=false}
        groups[key].value=groups[key].value or signalOn(a)
    end end
    local changes={}
    for _,c in pairs(groups) do if api.getOutput(c.name)~=c.value then changes[#changes+1]=c end end
    return changes
end
local function notice(view,text,back) view.message,view.messageBack,view.screen=tostring(text),back or view.screen or "home","message" end
local function commit(state,api,view,change,changes)
    local old=copy(state); change()
    local ok,err=api.updateOutputs(type(changes)=="function" and changes() or changes or {})
    if not ok then restore(state,old); lastError=tostring(err); if view then notice(view,"Save failed: "..lastError) end; return false,err end
    lastError=nil; assert(publish(state,api)); api.invalidateAppViews(appName); return true
end
local function remember(state,item)
    if state.catalog[item.key] then return end
    local n=0; for _ in pairs(state.catalog) do n=n+1 end
    if n>=1024 then
        local used,unused={},{}
        for _,m in ipairs(state.metrics) do used[m.item.key]=true end
        for _,a in ipairs(state.alarms) do used[a.item.key]=true end
        for key in pairs(state.catalog) do if not used[key] then unused[#unused+1]=key end end
        table.sort(unused); assert(unused[1],"Saved item catalog is full")
        state.catalog[unused[1]]=nil
    end
    state.catalog[item.key]=identity(item)
end
function app.init(state,api,context)
    ready=false; sources,holds,pickers,lastError={},{},{},nil
    assert(api.aeItemProfiles and api.setNotifications and api.updateOutputs,"Solar farm requires bundled-v25 OS or newer")
    appName=context and context.appName or "solar_farm"
    if state.version==nil then
        state.version,state.sources,state.metrics,state.alarms,state.catalog=1,{},{},{},{}
        state.nextId,state.nextAlertId,state.elapsed=1,1,0
        state.settings={dropCount=64,dropPercent=5,window=900,background=32768,panel=128}
    end
    assert(state.version==1 and type(state.sources)=="table" and type(state.catalog)=="table" and type(state.metrics)=="table"
        and #state.metrics<=64 and type(state.alarms)=="table" and #state.alarms<=64 and number(state.elapsed,0,MAX),"Invalid saved solar farm")
    for _,role in ipairs({"main","farm"}) do assert(state.sources[role]==nil or address(state.sources[role]),"Invalid saved ME source") end
    local settings=state.settings
    assert(type(settings)=="table" and integer(settings.dropCount,1,MAX) and integer(settings.dropPercent,0,100)
        and ({[300]=true,[900]=true,[3600]=true})[settings.window] and colour(settings.background) and colour(settings.panel),"Invalid solar settings")
    local n,ids,maxId,maxAlert=0,{},0,0
    for k,item in pairs(state.catalog) do assert(itemValid(item) and item.key==k,"Invalid saved item identity"); n=n+1 end
    assert(n<=1024,"Saved item catalog too large")
    local seen={}
    for _,m in ipairs(state.metrics) do
        assert(integer(m.id,1,2147483000) and not ids[m.id] and itemValid(m.item) and label(m.name)
            and not seen[m.item.key] and type(m.history)=="table" and #m.history<=60 and integer(m.ignored,0,MAX)
            and integer(m.omitted,0,MAX) and number(m.since,0,state.elapsed)
            and (m.colour==nil or colour(m.colour)) and (m.dropCount==nil or integer(m.dropCount,1,MAX))
            and (m.dropPercent==nil or integer(m.dropPercent,0,100)),"Invalid saved dashboard item")
        ids[m.id],seen[m.item.key],maxId=true,true,math.max(maxId,m.id)
        local last=-1
        for _,row in ipairs(m.history) do
            assert(type(row)=="table" and integer(row[1],0,MAX) and row[1]>last and number(row[2],-MAX,MAX)
                and number(row[3],0,120),"Invalid saved rate history"); last=row[1]
        end
    end
    local alerts={}
    for _,a in ipairs(state.alarms) do
        assert(integer(a.id,1,2147483000) and not ids[a.id] and label(a.name) and itemValid(a.item)
            and (a.source=="main" or a.source=="farm") and integer(a.threshold,1,MAX) and integer(a.reset,0,a.threshold-1)
            and integer(a.hold,0,86400) and integer(a.revision,1,MAX) and type(a.enabled)=="boolean" and type(a.latched)=="boolean"
            and signalValid(a.signal) and (a.route==nil or route(a.route)) and (a.dismissInput==nil or route(a.dismissInput)),"Invalid saved farm alarm")
        ids[a.id],maxId=true,math.max(maxId,a.id)
        if a.alert then
            assert(integer(a.alert.id,1,2147483000) and not alerts[a.alert.id] and type(a.alert.inputArmed)=="boolean","Invalid saved alert")
            alerts[a.alert.id],maxAlert,a.alert.inputArmed=true,math.max(maxAlert,a.alert.id),false
        end
        if a.ring then assert(a.alert and a.route and number(a.ring.elapsed,0,MAX),"Invalid saved stock signal") end
    end
    assert(integer(state.nextId,maxId+1,2147483001) and integer(state.nextAlertId,maxAlert+1,2147483001),"Invalid saved solar IDs")
    local outputs={}; for _,o in ipairs(api.getOutputs()) do outputs[o.name]=o end
    local changes={}
    for _,a in ipairs(state.alarms) do if a.route and not outputs[outputName(a)] then
        changes[#changes+1]={name=outputName(a),clientId=a.route.clientId,side=a.route.side,color=a.route.color,initialValue=false}
    end end
    if #changes>0 then assert(api.updateOutputs(changes)) end
    ready=true; assert(publish(state,api))
end
function app.background(dt,state,api)
    if not ready then return end
    dt=math.max(0,dt or 0); state.elapsed=state.elapsed+dt
    local boots={}; for _,c in ipairs(api.getSensorClients()) do boots[c.id]=c.bootId end
    for _,role in ipairs({"main","farm"}) do scanSource(role,state,api,boots) end
    local old,touched,important=copy(state),{},false
    for _,a in ipairs(state.alarms) do
        if a.ring then
            touched[wire(a.route)]=true; a.ring.elapsed=a.ring.elapsed+dt
            if length(a)>0 and a.ring.elapsed>=length(a) then a.ring=nil; important=true end
        end
        local qty=count(a.source,a.item.key)
        if a.enabled and qty~=nil then
            if not a.alert and qty<=a.reset and a.latched then a.latched=false; important=true end
            if not a.latched and not a.alert and qty>=a.threshold then
                holds[a.id]=holds[a.id] and holds[a.id]+dt or 0
                if holds[a.id]>=a.hold then
                    a.alert={id=state.nextAlertId,inputArmed=a.dismissInput and api.readInput(a.dismissInput)==false or false}
                    state.nextAlertId,a.latched=state.nextAlertId+1,true
                    if a.route then a.ring={elapsed=0}; touched[wire(a.route)]=true end
                    important=true
                end
            else holds[a.id]=nil end
        else holds[a.id]=nil end
        if a.alert and a.dismissInput then
            local input=api.readInput(a.dismissInput)
            if input==false then a.alert.inputArmed=true
            elseif input==nil then a.alert.inputArmed=false
            elseif a.alert.inputArmed then
                if a.route then touched[wire(a.route)]=true end
                a.alert,a.ring=nil,nil; important=true
            end
        end
    end
    local changes=wireChanges(state,touched,api)
    if important or #changes>0 then
        local ok,err=api.updateOutputs(changes)
        if not ok then restore(state,old); lastError="Checkpoint pending: "..tostring(err) else lastError=nil end
    end
    assert(publish(state,api))
end
function app.handleSensorSelection(role,selected,state,api,context)
    if (role~="main" and role~="farm") or not address(selected) then return false,"Invalid source selection" end
    local current=state.sources[role]
    if current and sourceKey(current)==sourceKey(selected) and current.card==selected.card and current.targetType==selected.targetType then
        context.view.screen="sources"; return true
    end
    local ok,err=commit(state,api,context.view,function()
        state.sources[role]=copy(selected)
        if role=="main" then resetRates(state) end
    end)
    if ok then sources[role],holds,pickers=nil,{},{}; context.view.screen="sources" end
    return ok,err
end
function app.handleIOSelection(key,selected,state,api,context)
    if not context.view.alarmDraft or (key~="signal" and key~="dismiss") or not route(selected) then return false,"Alarm editor closed or invalid route" end
    context.view.alarmDraft[key=="signal" and "route" or "dismissInput"]=copy(selected); return true
end
function app.handleNotification(key,state,api)
    local selected
    for _,a in ipairs(state.alarms) do if a.alert and key=="alarm_"..a.id.."_"..a.alert.id then selected=a end end
    if not selected then return publish(state,api) end
    local touched={}; if selected.route then touched[wire(selected.route)]=true end
    return commit(state,api,nil,function() selected.alert,selected.ring=nil,nil end,function() return wireChanges(state,touched,api) end)
end
local function itemRows(state,view,windowId)
    local browse=view.browse or {role="farm"}
    local key=(browse.purpose or "browse")..":"..browse.role..":"..(view.sort or "amount")..":"..tostring(view.descending~=false)..":"..(view.query or "")
    local frozen=pickers[windowId]
    if frozen and frozen.key==key then return frozen.rows end
    local merged={}
    if browse.purpose then
        for _,role in ipairs({"main","farm"}) do for k,item in pairs(cached(role).items) do merged[k]=identity(item) end end
        for k,item in pairs(state.catalog) do merged[k]=identity(item) end
    else
        for k,item in pairs(cached(browse.role).items) do merged[k]=identity(item) end
        for _,metric in ipairs(state.metrics) do merged[metric.item.key]=identity(metric.item) end
    end
    local rows,query={},(view.query or ""):lower()
    for _,item in pairs(merged) do
        if query=="" or item.name:lower():find(query,1,true) or item.raw:lower():find(query,1,true) then rows[#rows+1]=item end
    end
    table.sort(rows,function(a,b)
        local x,y
        if view.sort=="rate" then x,y=liveRate(a.key),liveRate(b.key)
        elseif view.sort~="name" then x,y=count(browse.role,a.key),count(browse.role,b.key) end
        x,y=x or -MAX,y or -MAX
        if view.sort~="name" and x~=y then return view.descending~=false and x>y or view.descending==false and x<y end
        local l,r=a.name:lower(),b.name:lower()
        if l~=r then return view.sort=="name" and view.descending~=false and l>r or (view.sort~="name" or view.descending==false) and l<r end
        return a.key<b.key
    end)
    local names,variants={},{}
    for _,row in ipairs(rows) do
        names[row.name]=(names[row.name] or 0)+1
        local key=row.name..":"..row.damage; variants[key]=(variants[key] or 0)+1
    end
    for _,row in ipairs(rows) do
        row.label=row.name
        if names[row.name]>1 then row.label=row.name.." ["..(variants[row.name..":"..row.damage]>1 and row.raw..":" or "")..row.damage.."]" end
    end
    -- Stable rows protect touches while live quantities/rates keep updating.
    if #rows>0 or cached(browse.role).status=="ok" then pickers[windowId]={key=key,rows=rows} end
    return rows
end
local function openItems(view,pickersId,role,purpose,back)
    view.browse={role=role or "farm",purpose=purpose,back=back or "home"}
    view.screen,view.query,view.sort,view.descending="items","",purpose and "name" or role=="main" and "rate" or "amount",purpose==nil
    view.pages={}; pickers[pickersId]=nil
end
local function alarmDraft(item)
    return {name=("High "..item.name):sub(1,24),item=identity(item),source="farm",threshold=10000,reset=9000,hold=30,
        enabled=true,signal={kind="constant",on=0,off=1,total=0}}
end
local function pickItem(state,api,view,item)
    local pinned=metricFor(state,item.key)
    view.metricId,view.selectedItem=pinned and pinned.id or nil,identity(item)
    if view.browse and view.browse.purpose=="pin" then
        local existing=metricFor(state,item.key)
        if existing then view.metricId,view.selectedItem,view.screen=existing.id,identity(item),"item"; return end
        if #state.metrics>=64 then notice(view,"Maximum 64 pinned items; unpin one first","items"); return end
        local created={id=state.nextId,name=item.name:sub(1,24),item=identity(item),history={},ignored=0,omitted=0,since=state.elapsed}
        if commit(state,api,view,function() remember(state,item); state.metrics[#state.metrics+1]=created; state.nextId=state.nextId+1 end) then
            view.metricId,view.selectedItem,view.screen=created.id,identity(item),"item"
        end
    elseif view.browse and view.browse.purpose=="alarm" then view.alarmDraft,view.screen=alarmDraft(item),"alarmEdit"
    else view.selectedItem,view.screen=identity(item),"item" end
end
local function beginText(view,target,key,value,back,limit)
    view.keyboard={target=target,key=key,draft=value or "",original=value,bank=0,page=1,back=back,limit=limit or 24}
    view.screen="keyboard"
end
local function beginNumber(view,target,key,value,back)
    view.number={target=target,key=key,draft=digits(value or 0),back=back}; view.screen="number"
end
local function build(width,height,state,api,context)
    local view=context.view; view.pages=view.pages or {}
    local screen=view.screen or "home"
    local metric=view.metricId and find(state.metrics,view.metricId)
    local alarm=view.alarmId and find(state.alarms,view.alarmId)
    local selected=view.selectedItem or metric and metric.item
    if screen=="metricEdit" and not metric then screen,view.screen="home","home" end
    if screen=="item" and not selected then screen,view.screen="home","home" end
    if (screen=="alarm" or screen=="deleteAlarm") and not alarm then screen,view.screen="alarms","alarms" end
    if screen=="alarmEdit" and not view.alarmDraft or screen=="number" and not view.number
        or screen=="keyboard" and not view.keyboard or screen=="manual" and not view.manual then screen,view.screen="home","home" end
    local accent=api.getAppColour(context.appName or appName)
    local ui=api.ui.content(width,height)
    ui.style(1,1,width,height,api.ui.contrast(state.settings.background),state.settings.background)
    local function put(x,y,text,span,center)
        if y<1 or y>height or span<1 then return end
        text=tostring(text):gsub("[%c]"," "):sub(1,span)
        if center then x=x+math.max(0,math.floor((span-#text)/2)) end
        ui.lines[y]=ui.lines[y]:sub(1,x-1)..text..ui.lines[y]:sub(x+#text)
    end
    local function button(y,text,action,value,x1,x2,enabled,bg)
        ui.button(y,text,action,x1,x2,enabled,bg or state.settings.panel,nil,value)
    end
    local function footer(items)
        for i,row in ipairs(items) do
            button(height,row[1],row[2],row[3],1+math.floor((i-1)*width/#items),math.floor(i*width/#items),row[4],row[5])
        end
    end
    local function page(key,n,slots,y)
        local pages=math.max(1,math.ceil(n/slots))
        local current=math.max(1,math.min(view.pages[key] or 1,pages)); view.pages[key]=current
        if pages>1 then
            local wing=math.max(2,math.floor(width/4))
            button(y,"<","page",{key=key,value=current-1},1,wing,current>1)
            button(y,">","page",{key=key,value=current+1},width-wing+1,width,current<pages)
            put(wing+1,y,current.."/"..pages,width-2*wing,true)
        end
        return (current-1)*slots
    end
    local function menu(title,rows,key,foot)
        ui.heading(title,accent)
        local slots=#rows<=height-2 and height-2 or height-3
        local first=page(key,#rows,slots,height-1)
        for i=1,slots do local row=rows[first+i]; if row then button(i+1,row[1],row[2],row[3],nil,nil,row[4],row[5]) end end
        footer(foot or {{"Back","home"}})
    end
    local function info(title,lines,key,back)
        local wrapped={}
        for _,line in ipairs(lines) do
            line=tostring(line):gsub("[%c]"," ")
            repeat
                local cut=#line>width and line:sub(1,width):match("^.*()%s")
                if cut and cut>1 then wrapped[#wrapped+1],line=line:sub(1,cut-1),line:sub(cut+1)
                else wrapped[#wrapped+1],line=line:sub(1,width),line:sub(width+1) end
            until line==""
        end
        ui.heading(title,accent)
        local slots=#wrapped<=height-2 and height-2 or height-3
        local first=page(key,#wrapped,slots,height-1)
        for i=1,slots do put(1,i+1,wrapped[first+i] or "",width) end
        footer({{"Back",back}})
    end
    local function status(role)
        local s=cached(role)
        return s.status=="ok" and "Online" or s.status=="unconfigured" and "Select source" or s.status
    end
    local function chart(m,x,y,w,h)
        ui.style(x,y,w,h,1,state.settings.panel)
        local rows,maximum,negative={},0,false
        local cutoff=math.floor(state.elapsed/60)-state.settings.window/60+1
        for _,row in ipairs(m.history) do if row[1]>=cutoff and row[3]>0 then
            local v=row[2]/row[3]*3600; rows[row[1]]=v; maximum=math.max(maximum,math.abs(v)); negative=negative or v<0
        end end
        if maximum==0 then maximum=1 end
        local zero=negative and y+math.floor((h-1)/2) or y+h-1
        ui.style(x,zero,w,1,nil,256)
        for col=1,w do
            local b=cutoff+math.floor((col-1)*(state.settings.window/60)/w)
            local value=rows[b]
            if value then
                ui.style(x+col-1,zero,1,1,nil,8) -- Observed zero is distinct from a grey missing-data gap.
                local available=value<0 and y+h-1-zero or zero-y
                local n=math.min(available,math.floor(math.abs(value)/maximum*available+0.5))
                if n>0 then ui.style(x+col-1,value<0 and zero+1 or zero-n,1,n,nil,value<0 and 2 or 32) end
            end
        end
        return maximum
    end
    if screen=="home" then
        ui.heading("Solar farm",accent)
        if not state.sources.main or not state.sources.farm then
            menu("Solar farm setup",{{"Select main ME","source","main"},{"Select farm ME","source","farm"},{"Stocks, rates and alarms","about"}},"setup",{{"Settings","settings"}})
        elseif #state.metrics==0 then
            menu("Solar farm",{{"Farm stocks","stocks"},{"Main rates / h","rates"},{"+ Pin item","pin"},{"Stock alarms","alarms"},{"ME sources","sources"}},"empty",{{"Menu","settings"}})
        else
            local compact=width<32
            put(1,2,compact and ("M:"..(cached("main").status=="ok" and "on" or "--").." F:"..(cached("farm").status=="ok" and "on" or "--"))
                or "Main: "..status("main").."  Farm: "..status("farm").."  Net "..(state.settings.window/60).."m",width,true)
            local bottom=height-1
            local columns=width>=70 and 3 or width>=36 and 2 or 1
            local rowH=height>=12 and 5 or 2
            local slots=math.max(1,columns*math.floor((bottom-2)/rowH))
            if #state.metrics>slots then bottom=bottom-1; slots=math.max(1,columns*math.floor((bottom-2)/rowH)) end
            local first=page("dashboard",#state.metrics,slots,height-1)
            local visible=math.min(slots,#state.metrics-first)
            local rows=math.ceil(visible/columns)
            for i=1,visible do
                local m=state.metrics[first+i]
                local col,row=(i-1)%columns,math.floor((i-1)/columns)
                local rowColumns=math.min(columns,visible-row*columns)
                local x=1+math.floor(col*width/rowColumns)
                local w=math.floor((col+1)*width/rowColumns)-x+1
                local y=3+math.floor(row*(bottom-2)/rows)
                local h=math.floor((row+1)*(bottom-2)/rows)-math.floor(row*(bottom-2)/rows)
                local r=measured(state,m)
                local qty=count("farm",m.item.key)
                local bg=m.colour or accent
                ui.style(x,y,w,h,api.ui.contrast(state.settings.panel),state.settings.panel)
                ui.style(x,y,w,1,api.ui.contrast(bg),bg); put(x,y,m.name,w,true)
                if h>=3 then
                    put(x,y+1,"Farm "..amount(qty,w-5),w,true)
                    put(x,y+2,"Net "..rateText(r,w-4),w,true)
                    if h>=5 then put(x,y+4,amount(count("main",m.item.key),w-5).." main",w,true) end
                else put(x,y+1,amount(qty,math.floor(w/2)).." "..rateText(r,math.ceil(w/2)-1),w,true) end
                ui.hits[#ui.hits+1]={x1=x,x2=x+w-1,y1=y,y2=y+h-1,action="metric",value=m.id}
            end
            footer({{width<18 and "ME" or "Stocks","stocks"},{"Rate","rates"},{"Menu","settings"}})
        end
    elseif screen=="items" then
        local browse=view.browse or {role="farm"}
        local rows=itemRows(state,view,context.windowId)
        ui.heading(browse.purpose and "Choose item" or browse.role=="main" and (width>=18 and "Main net/h (30s)" or "Main 30s /h") or "Farm stocks",
            browse.purpose and accent or cached(browse.role).status=="ok" and accent or 2)
        local rowH=width>=32 and 1 or 2
        local slots=math.max(1,math.floor((height-2)/rowH))
        if #rows>slots then slots=math.max(1,math.floor((height-3)/rowH)) end
        local first=page("items",#rows,slots,height-1)
        for i=1,slots do local item=rows[first+i]; if item then
            local y=2+(i-1)*rowH
            local qty=count(browse.role,item.key)
            local value=browse.role=="main" and not browse.purpose and rateText(liveRate(item.key),math.floor(width/2)) or amount(qty,math.floor(width/2))
            local m=metricFor(state,item.key)
            local bg=m and m.colour or i%2==0 and state.settings.panel or state.settings.background
            ui.style(1,y,width,rowH,api.ui.contrast(bg),bg)
            if rowH==1 then
                local right=math.min(width-4,#value)
                put(1,y,item.label or item.name,width-right-1); put(width-right+1,y,value,right)
            else put(1,y,item.label or item.name,width); put(1,y+1,value,width,true) end
            ui.hits[#ui.hits+1]={x1=1,x2=width,y1=y,y2=y+rowH-1,action="selectItem",value=identity(item)}
        end end
        if #rows==0 then put(1,2,cached(browse.role).status=="ok" and "No matching items" or status(browse.role),width,true) end
        footer({{"Back","leaveItems"},{"Find","filters"}})
    elseif screen=="filters" then
        menu("Item list",{{"Search: "..(view.query or ""),"search"},{"Sort: "..(view.sort or "amount"),"sort"},
            {view.descending~=false and "Order: Down" or "Order: Up","direction"},{"Refresh list","refresh"},{"Manual item","newManual"}},"filters",{{"Back","items"}})
    elseif screen=="item" then
        metric=metricFor(state,selected.key)
        local value,seconds
        if metric then value,seconds=measured(state,metric) else value=liveRate(selected.key) end
        if width>=32 and height>=14 and metric then
            ui.heading(metric.name,metric.colour or accent)
            put(1,2,"Farm: "..amount(count("farm",selected.key)).."   Main: "..amount(count("main",selected.key)),width,true)
            put(1,3,"Main net: "..rateText(value).." / "..(state.settings.window/60).." min",width,true)
            put(1,4,"Sampled "..amount(math.floor(seconds)).."s   Excluded drops: "..metric.ignored,width,true)
            local maximum=chart(metric,2,6,width-2,height-8)
            put(1,5,"Graph scale: +/- "..rateText(maximum):gsub("^%+",""),width,true)
            put(1,height-2,"Net / h; blue=0 grey=gap",width,true)
            button(height-1,"Item, filter and alarm details","itemInfo")
            footer({{"Back","home"},{"Edit","metricEdit"},{"Alarm","alarmFromItem"}})
        else
            local rows={{"Farm: "..amount(count("farm",selected.key)),"noop",nil,false},
                {"Main: "..amount(count("main",selected.key)),"noop",nil,false},
                {rateText(value).." main net","noop",nil,false},{"Details / coverage","itemInfo"}}
            if metric then rows[#rows+1]={"Edit pinned item","metricEdit"} else rows[#rows+1]={"Pin to dashboard","pinSelected"} end
            rows[#rows+1]={"Add buildup alarm","alarmFromItem"}
            menu(metric and metric.name or selected.name,rows,"item",{{"Back",view.browse and "items" or "home"}})
        end
    elseif screen=="itemInfo" then
        metric=selected and metricFor(state,selected.key)
        if not selected then return build(width,height,state,api,{appName=context.appName,windowId=context.windowId,view={screen="home"}}) end
        local minimum,percent=filter(state,selected.key)
        local _,seconds=metric and measured(state,metric) or nil,0
        if metric then _,seconds=measured(state,metric) end
        info("Item details",{selected.name,"Raw: "..selected.raw,"Damage: "..selected.damage,
            "Farm: "..amount(count("farm",selected.key)),"Main: "..amount(count("main",selected.key)),
            "Main: "..status("main"),"Farm: "..status("farm"),
            metric and "Pinned average: "..(state.settings.window/60).." minutes" or "Live estimate: 30-second exponential smoothing",
            metric and "Valid sampled seconds: "..amount(math.floor(seconds)) or "Only fresh sample pairs contribute",
            "Ignore downward changes of at least "..amount(minimum).." items AND "..percent.."% of the previous stock.",
            metric and "Excluded events: "..metric.ignored.." / observed drop: "..amount(metric.omitted) or "Pin this item to retain its rate history.",
            "Rates are filtered stock changes, not gross production. Consumption and transfers can lower them; production hidden by a withdrawal cannot be recovered. Gaps and restarts rebase without a catch-up spike."},"itemInfo","item")
    elseif screen=="metricEdit" then
        menu("Pinned item",{{"Name: "..metric.name,"metricName"},{"Item colour","metricColour"},
            {"Drop min: "..amount(metric.dropCount or state.settings.dropCount),"metricField","dropCount"},
            {"Drop %: "..(metric.dropPercent or state.settings.dropPercent),"metricField","dropPercent"},
            {"Use global filter","globalFilter"},{"Reset history","resetHistory"},{"Unpin item","unpin"}},"metricEdit",{{"Back","item"}})
    elseif screen=="manual" then
        local draft=view.manual
        menu("Register item",{{"Name: "..draft.name,"manualText","name"},{"RawName: "..draft.raw,"manualText","raw"},
            {"Damage: "..draft.damage,"manualDamage"},{"Use item","saveManual",nil,textValue(draft.raw,256) and textValue(draft.name,256)}},"manual",{{"Cancel","items"}})
    elseif screen=="sources" then
        local rows={}
        for _,role in ipairs({"main","farm"}) do
            local s=state.sources[role]
            rows[#rows+1]={role=="main" and "Select main ME" or "Select farm ME","source",role}
            rows[#rows+1]={s and s.clientId.." / "..s.side or "Not configured","source",role}
            rows[#rows+1]={status(role),"source",role}
        end
        rows[#rows+1]={"Source details","sourceInfo"}
        menu("ME sources",rows,"sources",{{"Back","settings"}})
    elseif screen=="sourceInfo" then
        local lines={}
        for _,role in ipairs({"main","farm"}) do
            local s=state.sources[role]; local data=cached(role)
            lines[#lines+1]=(role=="main" and "MAIN / rate source: " or "FARM / inventory source: ")..status(role)
            if s then lines[#lines+1]=s.clientId.." / "..s.side.." / "..s.target end
            if data.status=="ok" then
                local n=0; for _ in pairs(data.items) do n=n+1 end
                lines[#lines+1]="Item identities: "..n.." / stored: "..amount(data.total)
                for _,row in ipairs({{"Bytes used","UsedBytes"},{"Bytes free","FreeBytes"},{"Item room","FreeCount"}}) do
                    if integer(data.data[row[2]],0,MAX) then lines[#lines+1]=row[1]..": "..amount(data.data[row[2]]) end
                end
            end
        end
        if state.sources.main and state.sources.farm and sourceKey(state.sources.main)==sourceKey(state.sources.farm) then lines[#lines+1]="Both roles currently use the same ME target." end
        info("ME source status",lines,"sourceInfo","sources")
    elseif screen=="alarms" then
        local rows={}
        for _,a in ipairs(state.alarms) do rows[#rows+1]={a.name..(a.enabled and " ON" or " OFF"),"alarm",a.id,true,a.alert and 2 or nil} end
        rows[#rows+1]={"+ Add stock alarm","addAlarm",nil,#state.alarms<64}
        menu("Stock alarms",rows,"alarms",{{"Back","settings"}})
    elseif screen=="alarm" then
        local qty=count(alarm.source,alarm.item.key)
        menu(alarm.name,{{alarm.source..": "..amount(qty),"noop",nil,false},{"Above: "..amount(alarm.threshold),"noop",nil,false},
            {"Hold: "..alarm.hold.."s","noop",nil,false},{alarm.enabled and "Disable alarm" or "Enable alarm","toggleAlarm"},
            {"Item and signal details","alarmInfo"},{"Edit alarm","editAlarm",nil,not alarm.alert},{"Delete alarm","deleteAlarm"}},"alarm",{{"Back","alarms"}})
    elseif screen=="alarmEdit" then
        local d=view.alarmDraft
        local rows={{"Name: "..d.name,"alarmName"},{"ME: "..d.source,"alarmSource"},{"Item: "..d.item.name,"noop",nil,false},
            {"Threshold: "..amount(d.threshold),"alarmField","threshold"},{"Rearm below: "..amount(d.reset),"alarmField","reset"},
            {"Hold: "..d.hold.."s","alarmField","hold"},{d.enabled and "Enabled: Yes" or "Enabled: No","draftEnabled"},
            {d.route and "Output: "..d.route.clientId or "Select output","route"},{d.dismissInput and "Dismiss: "..d.dismissInput.clientId or "Select dismiss input","dismissInput"},
            {"Signal: "..(d.signal.kind=="constant" and "Constant" or "Pattern"),"draftSignal"},
            {d.signal.kind=="constant" and ("Length: "..(d.signal.on==0 and "Until OK" or d.signal.on.."s")) or "On: "..d.signal.on.."s","alarmField","on"}}
        if d.signal.kind=="pattern" then rows[#rows+1]={"Off: "..d.signal.off.."s","alarmField","off"}; rows[#rows+1]={"Total: "..(d.signal.total==0 and "Until OK" or d.signal.total.."s"),"alarmField","total"} end
        if d.route then rows[#rows+1]={"Disconnect output","clearRoute"} end
        if d.dismissInput then rows[#rows+1]={"Clear dismiss input","clearInput"} end
        menu("Stock alarm settings",rows,"alarmEdit",{{"Save","saveAlarm"},{"Cancel","cancelAlarm"}})
    elseif screen=="alarmInfo" then
        local function path(v) return v and v.clientId.." / "..v.side.." / "..(v.color and api.ui.colourName(v.color) or "Digital") or "None" end
        info("Alarm details",{alarm.item.name,"Raw: "..alarm.item.raw.." / "..alarm.item.damage,"ME: "..alarm.source,
            "Trigger at or above "..amount(alarm.threshold).." for "..alarm.hold.." seconds.","Rearms at or below "..amount(alarm.reset).." after acknowledgement.",
            "Output: "..path(alarm.route),"Dismiss input: "..path(alarm.dismissInput),
            "Signal: "..alarm.signal.kind.." / on "..alarm.signal.on.."s / off "..alarm.signal.off.."s / total "..alarm.signal.total.."s",
            "Constant length 0 or Pattern total 0 continues until OK or a fresh dismiss-input press.",
            "Fresh ME data is required to trigger; an existing alert remains pending if its sensor goes offline."},"alarmInfo","alarm")
    elseif screen=="deleteAlarm" then
        ui.heading("Delete alarm?",accent); put(1,2,alarm.name,width,true)
        button(height-1,"Delete","confirmDelete",nil,nil,nil,true,16384); footer({{"Cancel","alarm"}})
    elseif screen=="settings" then
        menu("Solar farm menu",{{"ME sources","sources"},{"Farm stocks","stocks"},{"Main rates / h","rates"},{"+ Pin item","pin"},{"Stock alarms","alarms"},
            {"Average: "..(state.settings.window/60).." min","window"},{"Drop min: "..amount(state.settings.dropCount),"settingField","dropCount"},
            {"Drop percent: "..state.settings.dropPercent.."%","settingField","dropPercent"},{"UI colour","accent"},{"Background colour","theme","background"},
            {"Panel colour","theme","panel"},{"Rates and restart rules","about"},{"Source status","sourceInfo"}},"settings",{{"Back","home"}})
    elseif screen=="number" then
        local n=view.number; ui.heading(n.key,accent); put(1,2,n.draft=="" and "0" or n.draft,width,true)
        for i,key in ipairs({"1","2","3","4","5","6","7","8","9","Clr","0","Del"}) do
            local col,row=(i-1)%4,math.floor((i-1)/4)
            button(3+row,key,"digit",key,1+math.floor(col*width/4),math.floor((col+1)*width/4),true,accent)
        end
        footer({{"Set","setNumber"},{"Back","cancelNumber"}})
    elseif screen=="keyboard" then
        local k=view.keyboard
        local bank=k.bank==2 and "1234567890-_/.:" or k.bank==1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZ" or "abcdefghijklmnopqrstuvwxyz"
        ui.heading(k.draft=="" and "Type here" or k.draft:sub(-width),accent)
        local cols,rows=math.max(4,math.min(10,math.floor(width/2))),math.max(1,math.min(3,height-4))
        local slots=cols*rows; local pages=math.ceil(#bank/slots); k.page=math.max(1,math.min(k.page,pages))
        for i=1,slots do local ch=bank:sub((k.page-1)*slots+i,(k.page-1)*slots+i); if ch~="" then
            local col,row=(i-1)%cols,math.floor((i-1)/cols)
            button(2+row,ch,"key",ch,1+math.floor(col*width/cols),math.floor((col+1)*width/cols),true,accent)
        end end
        for i,row in ipairs({{"ABC","bank"},{"Sp","space"},{"Del","backspace"},{k.page.."/"..pages,"keyPage"}}) do
            button(height-1,row[1],row[2],nil,1+math.floor((i-1)*width/4),math.floor(i*width/4))
        end
        footer({{"Set","saveText"},{"Clr","clearText"},{"Back","cancelText"}})
    elseif screen=="palette" then
        local p=view.palette
        if not p then view.screen="settings"; return build(width,height,state,api,context) end
        local lines,hits=api.ui.palette(width,height,p.value,p.target=="metric" and "Item colour" or p.target.." colour")
        ui.lines,ui.hits=lines,hits; table.remove(hits)
        if width>=28 and height>=14 then
            local bg=p.target=="background" and p.value or state.settings.background
            local panel=(p.target=="panel" or p.target=="metric") and p.value or state.settings.panel
            ui.style(1,height-4,width,3,api.ui.contrast(bg),bg)
            ui.style(2,height-3,width-2,1,api.ui.contrast(panel),panel)
            put(2,height-3,"Farm 1 234   Main +64.0/h",width-2,true)
        end
        footer({{"Save","savePalette"},{"Back","cancelPalette"}})
    elseif screen=="confirm" then
        ui.heading(view.confirm=="unpin" and "Unpin item?" or "Reset history?",accent)
        put(1,2,metric and metric.name or "Item removed",width,true)
        button(height-1,"Confirm","confirmMetric",nil,nil,nil,metric~=nil,16384)
        footer({{"Cancel","metricEdit"}})
    elseif screen=="about" or screen=="message" then
        info(screen=="message" and "Solar farm" or "How rates work",{screen=="message" and view.message or
            "Select independent Main and Farm AE sensor targets. Browse all items, then pin useful ones. Main rates are observed stock changes per hour, not SMF or gross crafting production. Default player-drop filter ignores a downward movement only when it reaches BOTH 64 items and 5 percent of the previous stock. Filters can be changed globally or per pin. Excluded intervals are omitted, then the next reading starts from the new stock. Small decreases count as consumption. Rates cannot recover production hidden by withdrawals, simultaneous transfers or crafting. Each pin saves up to 60 one-minute history buckets; averages use valid sampled time in the selected 5/15/60-minute window. The all-item Main list uses a 30-second live smoother. Missing readings are unknown; restarts/outages/source changes rebase and never replay stock differences. History excludes OS downtime. Item identities use RawName and DamageValue; this AE1 card cannot distinguish NBT variants. Register an absent item using Manual item. Buildup alarms work on either ME, continue in the background, and rearm only after stock falls below their reset threshold. A lack of item movement is normal and never triggers an alarm. Farm switches, transfer conditions and crafting logic remain external."},"info",screen=="message" and view.messageBack or "settings")
    else view.screen="home"; return build(width,height,state,api,context) end
    return ui.lines,ui.hits
end
function app.render(w,h,state,api,context)
    if not ready then return {"Solar farm blocked","Check OS console"} end
    return (build(w,h,state,api,context))
end
local function saveAlarm(state,api,view)
    local d=view.alarmDraft
    if not d or not label(d.name) or not itemValid(d.item) or type(d.enabled)~="boolean" or (d.source~="main" and d.source~="farm")
        or not integer(d.threshold,1,MAX) or not integer(d.reset,0,d.threshold-1) or not integer(d.hold,0,86400)
        or not signalValid(d.signal) or (d.route and not route(d.route)) or (d.dismissInput and not route(d.dismissInput)) then
        notice(view,"Invalid alarm settings","alarmEdit"); return
    end
    local a=d.id and find(state.alarms,d.id)
    if d.id and (not a or a.revision~=d.revision or a.alert) then notice(view,"Alarm changed; reopen its editor","alarms"); return end
    if not a and #state.alarms>=64 then notice(view,"Maximum 64 alarms","alarms"); return end
    local created=a or {id=state.nextId,revision=0}
    local changes={}
    if d.route then changes[1]={name=outputName(created),clientId=d.route.clientId,side=d.route.side,color=d.route.color,initialValue=false}
    elseif a and a.route then changes[1]={name=outputName(created),remove=true} end
    if commit(state,api,view,function()
        remember(state,d.item)
        if not a then state.alarms[#state.alarms+1]=created; state.nextId=state.nextId+1 end
        created.name,created.item,created.source=d.name,identity(d.item),d.source
        created.threshold,created.reset,created.hold=d.threshold,d.reset,d.hold
        created.enabled,created.latched=d.enabled,false
        created.route,created.dismissInput,created.signal=copy(d.route),copy(d.dismissInput),copy(d.signal)
        created.revision=created.revision+1
    end,changes) then
        holds[created.id]=nil; view.alarmId,view.alarmDraft,view.screen,view.pages=created.id,nil,"alarm",{}
    end
end
local function setNumber(state,api,view)
    local n=view.number
    local value=tonumber(n.draft=="" and "0" or n.draft)
    local low,high=0,MAX
    if n.key=="dropCount" or n.key=="threshold" then low=1
    elseif n.key=="dropPercent" then high=100
    elseif n.key=="damage" then high=2147483647
    elseif n.key=="hold" then high=86400
    elseif n.key=="on" or n.key=="off" then
        high=86400; low=(n.key=="off" or view.alarmDraft and view.alarmDraft.signal.kind=="pattern") and 1 or 0
    elseif n.key=="total" then high=31536000
    elseif n.key=="reset" then high=view.alarmDraft and view.alarmDraft.threshold-1 or 0 end
    if not integer(value,low,high) then notice(view,"Use a whole number from "..digits(low).." to "..digits(high),"number"); return end
    if n.target=="settings" then
        if commit(state,api,view,function() state.settings[n.key]=value; resetRates(state) end) then view.screen=n.back end
    elseif n.target=="metric" then
        local m=find(state.metrics,view.metricId)
        if not m then notice(view,"Item was unpinned","home"); return end
        if commit(state,api,view,function() m[n.key]=value; resetRates(state,m.item.key) end) then view.screen=n.back end
    elseif n.target=="alarm" then
        local d=view.alarmDraft
        if n.key=="on" or n.key=="off" or n.key=="total" then d.signal[n.key]=value else d[n.key]=value end
        if n.key=="threshold" and d.reset>=value then d.reset=math.floor(value*0.9) end
        view.screen=n.back
    elseif n.target=="manual" then view.manual.damage,view.screen=value,n.back end
end
function app.handleTouch(x,y,w,h,state,api,context)
    if not ready then return false end
    local _,hits=build(w,h,state,api,context)
    local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view
    local m=view.metricId and find(state.metrics,view.metricId)
    local a=view.alarmId and find(state.alarms,view.alarmId)
    if action=="page" then view.pages[value.key]=math.max(1,value.value)
    elseif ({home=true,settings=true,sources=true,sourceInfo=true,alarms=true,item=true,itemInfo=true,alarmInfo=true,
        about=true,metricEdit=true,items=true,number=true,keyboard=true,manual=true,alarmEdit=true,confirm=true})[action] then view.screen=action
    elseif action=="source" then
        local ok,err=api.pickSensor(context.windowId,value,state.sources[value],"ae")
        if not ok then notice(view,err,"sources") end
    elseif action=="stocks" or action=="rates" or action=="pin" or action=="addAlarm" then
        openItems(view,context.windowId,action=="rates" and "main" or "farm",action=="pin" and "pin" or action=="addAlarm" and "alarm" or nil,
            action=="addAlarm" and "alarms" or "home")
    elseif action=="metric" then
        m=find(state.metrics,value)
        if m then view.metricId,view.selectedItem,view.screen,view.browse=m.id,identity(m.item),"item",nil end
    elseif action=="selectItem" then
        view.metricId=nil; pickItem(state,api,view,value)
    elseif action=="leaveItems" then view.screen=view.browse and view.browse.back or "home"
    elseif action=="filters" then view.screen="filters"
    elseif action=="sort" then
        local values={name="amount",amount="rate",rate="name"}; view.sort=values[view.sort or "amount"]; pickers[context.windowId]=nil; view.pages.items=nil
    elseif action=="direction" then view.descending=view.descending==false; pickers[context.windowId]=nil; view.pages.items=nil
    elseif action=="refresh" then pickers[context.windowId]=nil; view.pages.items=nil; view.screen="items"
    elseif action=="search" then beginText(view,"search","query",view.query or "","filters",64)
    elseif action=="newManual" then view.manual,view.screen={raw="",name="New item",damage=0},"manual"
    elseif action=="manualText" then beginText(view,"manual",value,view.manual[value],"manual",256)
    elseif action=="manualDamage" then beginNumber(view,"manual","damage",view.manual.damage,"manual")
    elseif action=="saveManual" then
        local d=view.manual
        local item={raw=d.raw,name=d.name,damage=d.damage,key=itemKey(d.raw,d.damage,d.name)}
        if itemValid(item) and commit(state,api,view,function() remember(state,item) end) then
            view.manual=nil; pickers[context.windowId]=nil; pickItem(state,api,view,item)
        end
    elseif action=="pinSelected" then view.browse={role="farm",purpose="pin",back="home"}; pickItem(state,api,view,view.selectedItem)
    elseif action=="metricName" and m then beginText(view,"metric","name",m.name,"metricEdit")
    elseif action=="metricField" and m then beginNumber(view,"metric",value,m[value] or state.settings[value],"metricEdit")
    elseif action=="globalFilter" and m then commit(state,api,view,function() m.dropCount,m.dropPercent=nil,nil; resetRates(state,m.item.key) end)
    elseif (action=="resetHistory" or action=="unpin") and m then view.confirm,view.screen=action=="unpin" and "unpin" or "reset","confirm"
    elseif action=="confirmMetric" and m then
        local id=m.id
        if commit(state,api,view,function()
            if view.confirm=="unpin" then local _,index=find(state.metrics,id); table.remove(state.metrics,index)
            else resetRates(state,m.item.key) end
        end) then view.screen=view.confirm=="unpin" and "home" or "metricEdit" end
    elseif action=="settingField" then beginNumber(view,"settings",value,state.settings[value],"settings")
    elseif action=="window" then
        commit(state,api,view,function() state.settings.window=({[300]=900,[900]=3600,[3600]=300})[state.settings.window] end)
    elseif action=="accent" then local ok,err=api.pickColour(context.windowId); if not ok then notice(view,err,"settings") end
    elseif action=="theme" or action=="metricColour" then
        view.palette={target=action=="metricColour" and "metric" or value,value=action=="metricColour" and (m and m.colour or api.getAppColour(appName)) or state.settings[value],back=view.screen}
        view.screen="palette"
    elseif action=="colour" then view.palette.value=value
    elseif action=="savePalette" then
        local p=view.palette
        if p.target=="metric" and not m then notice(view,"Item was unpinned on another screen","home"); return true end
        if commit(state,api,view,function() if p.target=="metric" and m then m.colour=p.value else state.settings[p.target]=p.value end end) then view.screen=p.back; view.palette=nil end
    elseif action=="cancelPalette" then view.screen=view.palette.back; view.palette=nil
    elseif action=="alarmFromItem" then view.alarmDraft,view.screen=alarmDraft(view.selectedItem),"alarmEdit"
    elseif action=="alarm" then view.alarmId,view.screen=value or view.alarmId,"alarm"
    elseif action=="editAlarm" and a and not a.alert then view.alarmDraft,view.screen=copy(a),"alarmEdit"
    elseif action=="alarmName" then beginText(view,"alarm","name",view.alarmDraft.name,"alarmEdit")
    elseif action=="alarmSource" then local d=view.alarmDraft; d.source=d.source=="main" and "farm" or "main"
    elseif action=="alarmField" then
        local d=view.alarmDraft
        beginNumber(view,"alarm",value,d[value] or d.signal[value],"alarmEdit")
    elseif action=="draftEnabled" then view.alarmDraft.enabled=not view.alarmDraft.enabled
    elseif action=="draftSignal" then
        local d=view.alarmDraft; d.signal.kind=d.signal.kind=="constant" and "pattern" or "constant"
        if d.signal.kind=="pattern" and d.signal.on==0 then d.signal.on=1 end
    elseif action=="route" or action=="dismissInput" then
        local d=view.alarmDraft
        local ok,err=api.pickIO(context.windowId,action=="route" and "signal" or "dismiss",action=="route" and "output" or "input",action=="route" and d.route or d.dismissInput)
        if not ok then notice(view,err,"alarmEdit") end
    elseif action=="clearRoute" then view.alarmDraft.route=nil
    elseif action=="clearInput" then view.alarmDraft.dismissInput=nil
    elseif action=="saveAlarm" then saveAlarm(state,api,view)
    elseif action=="cancelAlarm" then view.screen=view.alarmDraft.id and "alarm" or "alarms"; view.alarmDraft=nil
    elseif action=="toggleAlarm" and a then
        local touched={}; if a.route then touched[wire(a.route)]=true end
        if commit(state,api,view,function()
            a.enabled=not a.enabled; a.revision=a.revision+1
            if not a.enabled then a.alert,a.ring,a.latched=nil,nil,false end
        end,function() return wireChanges(state,touched,api) end) then holds[a.id]=nil end
    elseif action=="deleteAlarm" and a then view.screen="deleteAlarm"
    elseif action=="confirmDelete" and a then
        local id=a.id
        if commit(state,api,view,function() local _,index=find(state.alarms,id); table.remove(state.alarms,index) end,
            a.route and {{name=outputName(a),remove=true}} or {}) then holds[id]=nil; view.screen="alarms" end
    elseif action=="digit" then
        local n=view.number
        if value=="Clr" then n.draft="" elseif value=="Del" then n.draft=n.draft:sub(1,-2)
        elseif #n.draft<16 then n.draft=(n.draft=="0" and "" or n.draft)..value end
    elseif action=="setNumber" then setNumber(state,api,view)
    elseif action=="cancelNumber" then view.screen=view.number.back
    elseif action=="key" or action=="space" then
        local k=view.keyboard; if #k.draft<k.limit then k.draft=k.draft..(action=="space" and " " or value) end
    elseif action=="backspace" then view.keyboard.draft=view.keyboard.draft:sub(1,-2)
    elseif action=="clearText" then view.keyboard.draft=""
    elseif action=="bank" then view.keyboard.bank,view.keyboard.page=(view.keyboard.bank+1)%3,1
    elseif action=="keyPage" then
        local k=view.keyboard; local slots=math.max(4,math.min(10,math.floor(w/2)))*math.max(1,math.min(3,h-4))
        k.page=k.page%math.ceil((k.bank==2 and 15 or 26)/slots)+1
    elseif action=="cancelText" then view.screen=view.keyboard.back
    elseif action=="saveText" then
        local k=view.keyboard
        local v=k.draft:gsub("^%s+",""):gsub("%s+$","")
        if k.target=="search" then view.query,view.screen=v,"items"; pickers[context.windowId]=nil; view.pages.items=nil
        elseif not textValue(v,k.limit) then notice(view,"Enter a nonempty value","keyboard")
        elseif k.target=="manual" then view.manual[k.key],view.screen=v,k.back
        elseif k.target=="alarm" then view.alarmDraft.name,view.screen=v,k.back
        elseif k.target=="metric" and m then
            if m.name~=k.original then notice(view,"Name changed on another screen; reopen the editor","metricEdit")
            elseif commit(state,api,view,function() m.name=v end) then view.screen=k.back end
        end
    end
    return true
end
function app.shutdown(state,api)
    for _,role in ipairs({"main","farm"}) do api.unwatchSensor(appName.."_"..role) end
    sources,holds,pickers={},{},{}
end
return app
