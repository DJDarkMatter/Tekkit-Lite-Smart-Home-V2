-- Farm stock changes are net rates; only HV solar is measured in the main ME.
local Me=dofile("lib_me.lua")
local app={title="Solar farm",backgroundService=true,minWidth=12,minHeight=6,preferredWidth=56,preferredHeight=22}
local name,ready="solar_farm",false
local cache,snapshots,previous,measured,frozen,structures={},{},{},{},{},{}
local copy,integer=Me.copy,Me.integer
local periods={[1]="/s",[60]="/m",[3600]="/h"}
local function metric(state,key) for _,m in ipairs(state.metrics) do if m.item.key==key then return m end end end
local function pinFor(state,item)
    if item.hv then if state.hv.pinned then return state.hv end; return nil end
    return metric(state,item.key)
end
local function binding(state,key) return key=="hv" and state.hv.item or state.catalog[key] or snapshots.farm and snapshots.farm.items[key] end
local function commit(state,api,view,change)
    local old=copy(state); change(); local ok,err=api.save()
    if not ok then Me.restore(state,old); if view then view.message,view.back,view.screen="Save failed: "..tostring(err),view.screen,"message" end; return false,err end
    frozen={}; api.invalidateAppViews(name); return true
end
local function remember(state,item)
    state.catalog[item.key]=Me.identity(item)
    local used={}; for _,m in ipairs(state.metrics) do used[m.item.key]=true end
    local unused={}; local count=0
    for key in pairs(state.catalog) do count=count+1; if not used[key] then unused[#unused+1]=key end end
    table.sort(unused)
    for i=1,math.max(0,count-1024) do state.catalog[unused[i]]=nil end
end
local function migrate(state)
    assert(not state.alarms or #state.alarms==0,"Install level_emitter before upgrading Solar farm: it moves your saved stock alarms safely")
    local pins={}; state.hv={pinned=true,stick=true,order=0,name="HV solar"}
    for _,m in ipairs(state.metrics or {}) do
        if Me.isHVSolar(m.item) then
            if not state.hv.item then state.hv={item=Me.identity(m.item),name=m.name,pinned=true,stick=true,order=0,colour=m.colour,dropCount=m.dropCount,dropPercent=m.dropPercent} end
        else
            pins[#pins+1]={id=m.id,item=Me.identity(m.item),name=m.name,colour=m.colour,dropCount=m.dropCount,dropPercent=m.dropPercent,legacy=true}
        end
    end
    state.metrics=pins; state.catalog={}
    state.version,state.history=2,{farm=Me.Rates.new(),main=Me.Rates.new()}
    state.settings.period=3600
    state.alarms,state.nextAlertId,state.alarmsMovedTo=nil,nil,nil
end
-- Lifetime estimates use all accepted deltas/observed time, independent of the
-- rolling display window. Split time and large integer strings survive LuaJ's
-- low-precision tostring without rounding a growing total at every checkpoint.
local function stored(n) return n>=-2147483648 and n<=2147483647 and n or (n<0 and "-" or "")..Me.digits(n) end
local function addTime(whole,fraction,dt)
    local value=fraction+dt; local n=math.floor(value+0.000000001)
    return whole+n,math.max(0,value-n)
end
local Long={}
function Long.new() return {seconds=0,fraction=0,values={},cost=0,full=false,invalid=false} end
function Long.record(total,dt,changes)
    total.seconds,total.fraction=addTime(total.seconds,total.fraction,dt)
    for key,change in pairs(changes) do
        local row=total.values[key]
        if not row then
            local cost=2*#key+180
            if total.cost+cost<=98304 then row={0,0,0,0,0}; total.values[key]=row; total.cost=total.cost+cost else total.full=true end
        end
        if row then
            if change.skip then
                row[2],row[5]=addTime(row[2],row[5],dt); row[3]=row[3]+1
                local removed=tonumber(row[4])+math.abs(change.delta)
                if removed>Me.MAX then total.invalid=true else row[4]=stored(removed) end
            else
                local delta=tonumber(row[1])+change.delta
                if not Me.number(delta,-Me.MAX,Me.MAX) then total.invalid=true else row[1]=stored(delta) end
            end
        end
    end
    if total.seconds>Me.MAX then total.invalid=true end
end
function Long.value(total,key)
    local row=key and total.values[key]
    local seconds=math.max(0,total.seconds+total.fraction-(row and row[2]+row[5] or 0))
    if not key or total.invalid or total.full and not row then return nil,seconds,0,0 end
    return row and tonumber(row[1]) or 0,seconds,row and row[3] or 0,row and tonumber(row[4]) or 0
end
function Long.import(history)
    local total=Long.new(); local names={}
    for key,id in pairs(history.keys) do names[id]=key end
    for _,bucket in ipairs(history.buckets) do
        total.seconds,total.fraction=addTime(total.seconds,total.fraction,bucket.seconds)
        for id,value in pairs(bucket.values) do
            local key=names[id]; local row=total.values[key]
            if not row then
                local cost=2*#key+180
                if total.cost+cost<=98304 then row={0,0,0,0,0}; total.values[key]=row; total.cost=total.cost+cost else total.full=true end
            end
            if row then
                local delta,removed=tonumber(row[1])+value[1],tonumber(row[4])+value[4]
                if not Me.number(delta,-Me.MAX,Me.MAX) or not Me.number(removed,0,Me.MAX) then total.invalid=true
                else row[1],row[4]=stored(delta),stored(removed) end
                row[2],row[5]=addTime(row[2],row[5],value[2]); row[3]=row[3]+value[3]
            end
        end
    end
    return total
end
function Long.valid(total)
    if type(total)~="table" or not integer(total.seconds,0,Me.MAX) or not Me.number(total.fraction,0,.9999999999)
        or type(total.values)~="table" or type(total.full)~="boolean" or type(total.invalid)~="boolean"
        or total.itemKey~=nil and not Me.textValue(total.itemKey,600) then return false end
    local cost=0
    local function count(n) return (type(n)=="number" or type(n)=="string" and n:match("^-?%d+$")) and integer(tonumber(n),-Me.MAX,Me.MAX) end
    for key,row in pairs(total.values) do
        if not Me.textValue(key,600) or type(row)~="table" or not count(row[1]) or not integer(row[2],0,total.seconds+1)
            or not integer(row[3],0,Me.MAX) or not count(row[4]) or tonumber(row[4])<0 or not Me.number(row[5],0,.9999999999)
            or row[2]+row[5]>total.seconds+total.fraction+.000001 then return false end
        cost=cost+2*#key+180
    end
    if cost>98304 then return false end
    total.cost=cost; return true
end
local function newTrace() return {points={},gap=true} end
local function tracePoint(state,rate)
    local trace=state.hvTrace; local points=trace.points; local last=points[#points]
    if rate==nil and trace.gap then return end
    if last and last[1]==state.elapsed then last[2]=rate or false
    else points[#points+1]={state.elapsed,rate or false} end
    trace.gap=rate==nil
    -- Native samples for the latest 15 minutes; older points are thinned to
    -- ten-second steps. No interpolation is recorded as a real observation.
    if #points>1024 or points[1] and points[1][1]<state.elapsed-3600 or #points%32==0 then
        local kept,lastSlot={},nil
        for _,point in ipairs(points) do if point[1]>=state.elapsed-3600 then
            local slot=math.floor(point[1]/10)
            if point[1]>=state.elapsed-900 or point[2]==false or kept[#kept] and kept[#kept][2]==false or slot~=lastSlot then kept[#kept+1]=point
            else kept[#kept]=point end
            lastSlot=slot
        end end
        while #kept>1024 do table.remove(kept,1) end
        trace.points=kept
    end
end
local function resetMain(state,key)
    state.history.main=Me.Rates.new(); state.averages.main=Long.new(); state.averages.main.itemKey=key; state.hvTrace=newTrace()
end
local function elapsedText(seconds)
    seconds=math.floor(seconds)
    if seconds<60 then return seconds.."s" end
    if seconds<3600 then return math.floor(seconds/60).."m "..seconds%60 .."s" end
    return math.floor(seconds/3600).."h "..math.floor(seconds%3600/60).."m"
end
function app.init(state,api,context)
    ready=false; cache,snapshots,previous,measured,frozen,structures={},{},{},{},{},{}
    assert(api.ui.form and api.migrateAppState and Me.safePatterns,"Solar farm needs bundled-v31 core: update installer, then run inst server")
    assert(api.ui and api.ui.typeKey and api.ui.breadcrumb,"solar_farm requires bundled-v33 OS; run inst server")
    name=context and context.appName or "solar_farm"
    if state.version==nil then
        state.version,state.sources,state.metrics,state.catalog,state.hv=2,{},{},{},{pinned=true,stick=true,order=0,name="HV solar"}
        state.nextId,state.elapsed=1,0
        state.history={farm=Me.Rates.new(),main=Me.Rates.new()}
        state.settings={dropCount=64,dropPercent=5,window=900,period=3600,background=32768,panel=128}
    elseif state.version==1 then migrate(state) end
    assert(state.version==2 and type(state.sources)=="table" and type(state.catalog)=="table" and type(state.metrics)=="table"
        and #state.metrics<=64 and type(state.hv)=="table" and Me.number(state.elapsed,0,Me.MAX),"Invalid saved Solar farm")
    for _,role in ipairs({"main","farm"}) do assert(state.sources[role]==nil or Me.address(state.sources[role]),"Invalid ME source") end
    local s=state.settings
    assert(type(s)=="table" and integer(s.dropCount,1,Me.MAX) and integer(s.dropPercent,0,100) and periods[s.period]
        and ({[300]=true,[900]=true,[3600]=true})[s.window] and Me.colour(s.background) and Me.colour(s.panel),"Invalid Solar settings")
    assert(type(state.history)=="table" and Me.Rates.valid(state.history.main) and Me.Rates.valid(state.history.farm),"Invalid saved rates")
    assert(not state.hv.item or Me.itemValid(state.hv.item),"Invalid HV item")
    if state.hv.pinned==nil then state.hv.pinned=true end
    if state.hv.stick==nil then state.hv.stick=true end
    if state.hv.selection==nil then state.hv.selection=state.hv.item and "manual" or "auto" end
    state.hv.order,state.hv.name=state.hv.order or 0,state.hv.name or "HV solar"
    assert(type(state.hv.pinned)=="boolean" and type(state.hv.stick)=="boolean"
        and integer(state.hv.order,0,Me.MAX) and Me.label(state.hv.name)
        and (state.hv.selection=="auto" or state.hv.selection=="manual"),"Invalid HV pin")
    assert((state.hv.colour==nil or Me.colour(state.hv.colour)) and (state.hv.dropCount==nil or integer(state.hv.dropCount,1,Me.MAX))
        and (state.hv.dropPercent==nil or integer(state.hv.dropPercent,0,100)),"Invalid HV settings")
    local ids,maxId={},0
    for _,m in ipairs(state.metrics) do
        assert(integer(m.id,1,2147483000) and not ids[m.id] and Me.itemValid(m.item) and Me.label(m.name)
            and (m.colour==nil or Me.colour(m.colour)) and (m.dropCount==nil or integer(m.dropCount,1,Me.MAX))
            and (m.dropPercent==nil or integer(m.dropPercent,0,100)) and (m.stick==nil or type(m.stick)=="boolean"),"Invalid pinned item")
        ids[m.id],maxId=true,math.max(maxId,m.id)
    end
    assert(integer(state.nextId,maxId+1,2147483001),"Invalid pin IDs")
    local count=0; for key,item in pairs(state.catalog) do assert(Me.itemValid(item) and item.key==key,"Invalid item catalog"); count=count+1 end
    assert(count<=1024,"Item catalog too large")
    if state.averages==nil then
        state.averages={farm=Long.import(state.history.farm),main=Long.import(state.history.main)}
        state.averages.main.itemKey=state.hv.item and state.hv.item.key
    end
    assert(type(state.averages)=="table" and Long.valid(state.averages.main) and Long.valid(state.averages.farm),"Invalid saved long-term rates")
    if state.hvTrace==nil then state.hvTrace=newTrace() end
    assert(type(state.hvTrace)=="table" and type(state.hvTrace.points)=="table" and #state.hvTrace.points<=1024
        and type(state.hvTrace.gap)=="boolean","Invalid saved HV trend")
    local last=-1
    for _,point in ipairs(state.hvTrace.points) do
        assert(type(point)=="table" and Me.number(point[1],0,state.elapsed) and point[1]>last
            and (point[2]==false or Me.number(point[2],-1e100,1e100)),"Invalid saved trend sample")
        last=point[1]
    end
    ready=true
end
local function sample(role,state,s)
    local old=previous[role]
    if s.status~="ok" or not Me.number(s.time,0,Me.MAX) or not integer(s.sequence,0,Me.MAX) or role=="main" and not state.hv.item then
        previous[role],measured[role]=nil,false; if role=="main" then tracePoint(state,nil) end; return
    end
    if old and old.key==s.key and old.sequence==s.sequence and old.time==s.time then return end
    measured[role]=false
    if old and old.key==s.key then
        local dt=s.time-old.time
        if Me.number(dt,0.001,10) then
            local keys,changes={},{}
            if role=="main" then if state.hv.item then keys[state.hv.item.key]=true end
            else for key in pairs(old.items) do keys[key]=true end; for key in pairs(s.items) do keys[key]=true end end
            for key in pairs(keys) do
                local before=old.items[key] and old.items[key].count or 0
                local after=s.items[key] and s.items[key].count or 0
                local delta=after-before
                if delta~=0 then
                    local m=role=="main" and state.hv or metric(state,key)
                    local minimum=m and m.dropCount or state.settings.dropCount
                    local percent=m and m.dropPercent or state.settings.dropPercent
                    changes[key]={delta=delta,skip=delta<0 and -delta>=minimum and -delta>=before*percent/100}
                end
            end
            Me.Rates.record(state.history[role],state.elapsed,dt,changes)
            Long.record(state.averages[role],dt,changes); measured[role]=true
        end
    end
    if role=="main" then
        local delta,seconds=Long.value(state.averages.main,state.hv.item.key)
        tracePoint(state,measured.main and delta and seconds>0 and delta/seconds or nil)
    end
    previous[role]={key=s.key,sequence=s.sequence,time=s.time,items=s.items}
end
local function observe(role,state,api,boots)
        if state.sources[role] then
            local ok,err=api.watchSensor(name.."_"..role,state.sources[role],{profile="ae_items"})
            if ok==false then error("Cannot subscribe: "..tostring(err),0) end
        end
        local s=Me.snapshot(cache,api,state.sources[role],boots); snapshots[role]=s
        if role=="farm" and s.status=="ok" then
            local keys={}; for key in pairs(s.items) do keys[#keys+1]=key end; table.sort(keys)
            local signature=table.concat(keys,"\n")
            if structures.farm~=signature then structures.farm=signature; frozen={}; api.invalidateAppViews(name) end
        end
        local scan=tostring(s.key)..":"..tostring(s.dataSequence)..":"..state.hv.selection
        if role=="main" and not state.hv.item and s.status=="ok" and s.hvChecked~=scan then
            s.hvChecked=scan
            local candidates={}; for _,item in pairs(s.items) do if Me.isHVSolar(item) then candidates[#candidates+1]=item end end
            s.hvCandidates=#candidates
            if #candidates==1 and (not state.hv.item or state.hv.item.key~=candidates[1].key)
                and (not state.hv.item or not s.items[state.hv.item.key]) then
                local changed=state.averages.main.itemKey~=candidates[1].key
                if commit(state,api,nil,function()
                    state.hv.item=Me.identity(candidates[1])
                    if changed then resetMain(state,candidates[1].key) end
                end) and changed then previous.main,measured.main=nil,false end
            end
        end
        if role=="farm" and s.status=="ok" then
            for _,m in ipairs(state.metrics) do if m.legacy and s.items[m.item.key] then m.legacy=nil; remember(state,m.item); frozen={} end end
        end
        sample(role,state,s)
end
function app.background(dt,state,api)
    if not ready then return end
    state.elapsed=state.elapsed+math.max(0,dt or 0)
    local ok,boots=pcall(Me.boots,api); if not ok then boots={} end
    for _,role in ipairs({"main","farm"}) do
        local success,err=pcall(observe,role,state,api,boots)
        if not success then
            snapshots[role]={status="error",error=tostring(err),items={}}
            previous[role],measured[role]=nil,false
            if role=="main" then tracePoint(state,nil) end
        end
    end
end
local function reading(state,key)
    local item=binding(state,key); local role=key=="hv" and "main" or "farm"; local s=snapshots[role]
    local count=Me.count(s,item and item.key); local rate,seconds,drops,removed,delta,windowRate,windowSeconds
    if item then
        local total; total,seconds,drops,removed=Long.value(state.averages[role],item.key)
        delta,windowSeconds=Me.Rates.sum(state.history[role],item.key,state.elapsed,state.settings.window)
        if count~=nil and measured[role] then
            if total and seconds>0 then rate=total/seconds*state.settings.period end
            if windowSeconds>0 then windowRate=delta/windowSeconds*state.settings.period else delta=nil end
        else delta=nil end
    end
    return count,rate,seconds or 0,drops or 0,removed or 0,delta,windowRate,windowSeconds or 0
end
local function rateText(state,rate,width)
    local text=Me.rateText(rate,width):gsub("/h$",periods[state.settings.period]); return text
end
local function rowsFor(state,view,windowId,purpose,api)
    local role=purpose=="hv" and "main" or "farm"
    local s=snapshots[role] or {status="unconfigured",items={}}
    local query=purpose=="overview" and "" or view.query or ""
    local order=purpose=="overview" and view.overviewSort
    if type(order)~="table" or (order.field~="name" and order.field~="amount") then order=nil end
    local signature=purpose..":"..(s.key or "")..":"..query..":"..(order and order.field or view.sort or "name")..":"..tostring(order and order.descending==true or not order and view.descending==true)
    if order and order.field=="amount" then signature=signature..":"..tostring(s.sequence)..":"..tostring(snapshots.main and snapshots.main.sequence)..":"..tostring(s.status)..":"..tostring(snapshots.main and snapshots.main.status) end
    local saved=frozen[windowId]
    if saved and saved.signature==signature then return saved.rows,s end
    local all={}
    for key,item in pairs(s.items) do if purpose~="hv" or Me.isHVSolar(item) then all[key]=Me.identity(item) end end
    if purpose~="hv" then for key,item in pairs(state.catalog) do all[key]=Me.identity(item) end
    elseif state.hv.item then all[state.hv.item.key]=Me.identity(state.hv.item) end
    if purpose~="hv" then
        local hv=state.hv.item
        if purpose=="overview" and (state.hv.pinned or hv) or purpose=="pin" then
            local row=hv and Me.identity(hv) or {key="hv",raw="",name="HV solar",damage=0}
            row.hv=true; all["@main_hv"]=row
        end
    end
    local rows={}; query=query:lower()
    for _,item in pairs(all) do
        if query=="" or item.name:lower():find(query,1,true) or item.raw:lower():find(query,1,true) then rows[#rows+1]=item end
    end
    local function label(item)
        if purpose~="overview" then return item.name:lower() end
        local m=pinFor(state,item)
        return (m and m.name or item.hv and state.hv.name or item.name):lower()
    end
    local function quantity(item)
        if item.hv and not state.hv.item then return nil end
        return Me.count(item.hv and snapshots.main or s,item.key)
    end
    table.sort(rows,function(a,b)
        if purpose=="overview" then
            local am,bm=pinFor(state,a),pinFor(state,b)
            local astick,bstick=am and am.stick or false,bm and bm.stick or false
            if astick~=bstick then return astick end
            if astick and bstick then
                local ai,bi=a.hv and am.order or am.id,b.hv and bm.order or bm.id
                if ai~=bi then return ai<bi end
            elseif not order then
                if (am~=nil)~=(bm~=nil) then return am~=nil end
                if am and bm then return (a.hv and am.order or am.id)<(b.hv and bm.order or bm.id) end
            end
        end
        local field=order and order.field or purpose~="overview" and view.sort
        local descending=order and order.descending==true or not order and purpose~="overview" and view.descending==true
        if field=="amount" then
            local aq,bq=quantity(a),quantity(b)
            if (aq==nil)~=(bq==nil) then return aq~=nil end
            if aq and bq and aq~=bq then return descending and aq>bq or not descending and aq<bq end
        end
        local an,bn=label(a),label(b)
        if an~=bn then return field~="amount" and descending and an>bn or (field=="amount" or not descending) and an<bn end
        if a.key==b.key then return a.hv==true and b.hv~=true end
        return a.key<b.key
    end)
    local identities={}; for _,item in ipairs(rows) do identities[#identities+1]=(item.hv and "main:" or "farm:")..item.key end
    local identity=table.concat(identities,"\n")
    if s.status=="ok" or purpose=="overview" then
        frozen[windowId]={signature=signature,rows=rows,identity=identity,purpose=purpose}
        if api and purpose=="overview" and saved and saved.purpose=="overview" and saved.identity~=identity then api.invalidateAppViews(name) end
    end
    return rows,s
end
function app.handleSensorSelection(role,selected,state,api,context)
    if (role~="main" and role~="farm") or not Me.address(selected) then return false,"Invalid source" end
    local old=state.sources[role]
    if old and Me.sourceKey(old)==Me.sourceKey(selected) and old.card==selected.card and old.targetType==selected.targetType then context.view.screen="sources"; return true end
    local ok,err=commit(state,api,context.view,function()
        state.sources[role]=copy(selected); state.history[role]=Me.Rates.new()
        if role=="main" then state.hv.item=nil; resetMain(state,nil)
        else state.averages.farm=Long.new(); state.catalog={}; for _,m in ipairs(state.metrics) do m.legacy=true end end
    end)
    if ok then snapshots[role],previous[role],measured[role]=nil,nil,false; context.view.screen="sources" end
    return ok,err
end
local statusNames={ok="Live",unconfigured="Not set",waiting="Waiting",offline="Offline",unpowered="Unpowered",unsupported="Incomplete",stale="Stale",card_changed="Card changed",target_changed="Target changed",missing="Missing",error="Error"}
local function source(role) return snapshots[role] or {status="unconfigured",items={}} end
local function status(role) local s=source(role); return statusNames[s.status] or s.status or "Waiting" end
local function coverage(state,role)
    local seconds=0; local first=math.floor(state.elapsed/60)-state.settings.window/60+1
    for _,bucket in ipairs(state.history[role].buckets) do if bucket.minute>=first then seconds=seconds+bucket.seconds end end
    return seconds
end
local function flow(state)
    if source("farm").status~="ok" or not measured.farm then return nil,nil end
    local sums,excluded={},{}; local first=math.floor(state.elapsed/60)-state.settings.window/60+1
    for _,bucket in ipairs(state.history.farm.buckets) do if bucket.minute>=first then
        for id,row in pairs(bucket.values) do sums[id]=(sums[id] or 0)+row[1]; excluded[id]=(excluded[id] or 0)+row[2] end
    end end
    local rising,falling,total=0,0,coverage(state,"farm")
    for key,id in pairs(state.history.farm.keys) do if source("farm").items[key] or state.catalog[key] then
        if total>(excluded[id] or 0) then
            if (sums[id] or 0)>0 then rising=rising+1 elseif (sums[id] or 0)<0 then falling=falling+1 end
        end
    end end
    return rising,falling
end
local function chart(ui,x,y,w,h,state)
    ui.style(x,y,w,h,1,32768)
    local bins={}; local first=state.elapsed-state.settings.window
    local low,high,interval=nil,nil,nil; local previousPoint
    for _,point in ipairs(state.hvTrace.points) do
        if previousPoint and point[2]~=false and previousPoint[2]~=false and point[1]-previousPoint[1]<=10 then interval=point[1]-previousPoint[1] end
        if point[1]>=first and point[1]<=state.elapsed then
            local index=1+math.min(w-1,math.floor((point[1]-first)*w/state.settings.window))
            bins[index]=point[2]
        end
        previousPoint=point
    end
    for _,value in pairs(bins) do if value~=false then low=low and math.min(low,value) or value; high=high and math.max(high,value) or value end end
    if not low then ui.put(x,y+math.floor(h/2),"Waiting for HV samples",w,true); return end
    local span=high-low
    local minimum=math.max(math.abs(low),math.abs(high),.000001)*.002
    if span<minimum then local middle=(high+low)/2; low,high=middle-minimum/2,middle+minimum/2 else low,high=low-span*.05,high+span*.05 end
    local levels=h*2
    for column,value in pairs(bins) do if value~=false then
        local level=math.max(1,math.min(levels,math.floor((value-low)/(high-low)*(levels-1)+1.5)))
        local fg=value>0 and 32 or value<0 and 2 or 256
        for row=1,h do
            local fill=level-(h-row)*2
            if fill>0 then ui.put(x+column-1,y+row-1,fill>=2 and "|" or ".",1); ui.style(x+column-1,y+row-1,1,1,fg,32768) end
        end
    end end
    return low*state.settings.period,high*state.settings.period,interval
end
local function dashboard(ui,w,h,state,api)
    local cards=w>=42 and h>=14
    local plot=cards and w>=56 and h>=24
    local half=math.floor(w/2)
    local short={ok="OK",unconfigured="SET",waiting="WAIT",offline="OFF",unpowered="PWR",unsupported="DATA",stale="OLD",error="ERR"}
    for i,role in ipairs({"farm","main"}) do
        local left=i==1 and 1 or half+1; local width=i==1 and half or w-half
        local bg=source(role).status=="ok" and 8192 or 2
        ui.style(left,1,width,1,api.ui.contrast(bg),bg)
        local label=w>=24 and (role=="farm" and "Farm: " or "Main: ")..status(role)
            or (role=="farm" and "F:" or "M:")..(short[source(role).status] or "ERR")
        ui.put(left,1,label,width,true)
    end
    if not cards then return w>=36 and 3 or 2 end
    local count=w>=72 and 3 or 2
    local hvAmount,hvRate,seconds,_,_,delta=reading(state,"hv")
    local farm=source("farm"); local farmLive=farm.status=="ok"
    for i=1,count do
        local left=1+math.floor((i-1)*w/count); local right=math.floor(i*w/count)-1; local width=right-left+1
        ui.style(left,3,width,4,api.ui.contrast(state.settings.panel),state.settings.panel)
        local accent=api.getAppColour(name)
        ui.style(left,3,width,1,api.ui.contrast(accent),accent)
        ui.put(left+1,3,({"HV OUTPUT","FARM STOCK","FARM MOVEMENT"})[i],width-2)
        if i==1 then
            ui.put(left+1,4,state.hv.item and Me.amount(hvAmount).." panels" or "Select HV panel type",width-2)
            ui.put(left+1,5,rateText(state,hvRate).." avg",width-2)
            ui.put(left+1,6,seconds>0 and ("Learned "..elapsedText(seconds)) or "Awaiting fresh samples",width-2)
            ui.hits[#ui.hits+1]={x1=left,x2=right,y1=3,y2=6,action=state.hv.item and "item" or "chooseHV",value={key="hv",item=state.hv.item and Me.identity(state.hv.item)}}
        elseif i==2 then
            ui.put(left+1,4,Me.amount(farmLive and farm.total or nil).." items",width-2)
            ui.put(left+1,5,Me.amount(farmLive and farm.types or nil).." item types",width-2)
            local data=farmLive and farm.data or {}; local used,free=data.UsedBytes,data.FreeBytes
            if Me.number(used,0,Me.MAX) and Me.number(free,0,Me.MAX) and used+free>0 then
                local ratio=used/(used+free); local colour=ratio>=.95 and 16384 or ratio>=.8 and 2 or 8192
                ui.style(left,6,math.max(1,math.floor(width*ratio)),1,1,colour)
                ui.put(left+1,6,"Bytes "..math.floor(ratio*1000+.5)/10 .."%",width-2)
            else ui.put(left+1,6,farmLive and "Complete inventory" or status("farm"),width-2) end
        else
            local rising,falling=flow(state)
            ui.put(left+1,4,Me.amount(rising).." rising / "..Me.amount(falling).." falling",width-2)
            ui.put(left+1,5,"Over "..math.floor(state.settings.window/60).." minutes",width-2)
            ui.put(left+1,6,"Observed "..math.floor(coverage(state,"farm")).."s",width-2)
        end
    end
    if plot then
        local low,high,interval=chart(ui,1,9,w,3,state)
        ui.put(1,8,"HV average  "..math.floor(state.settings.window/60).."m | "..math.floor(state.settings.window/w*10+.5)/10 .."s/column",w)
        if low then
            local text=rateText(state,low).." .. "..rateText(state,high).." | "..(interval and math.floor(interval*10+.5)/10 .."s samples" or "sampling")
            if #text<w-32 then ui.put(w-#text+1,8,text,#text) end
        end
    end
    return plot and 14 or 9
end
local function form(w,h,state,api,context)
    local view=context.view; view.pages=view.pages or {}; local screen=view.screen or "home"
    local ui=api.ui.form(w,h,view,api.getAppColour(name),state.settings.background,state.settings.panel)
    local accent=api.getAppColour(name)
    if screen=="home" then
        local rows,s=rowsFor(state,view,context.windowId,"overview",api)
        local wide=w>=36; local rowH=wide and 1 or 2; local top=dashboard(ui,w,h,state,api)
        local capacity=math.max(1,math.floor((h-top)/rowH))
        local sticky,scroll={},{}
        for _,item in ipairs(rows) do local m=pinFor(state,item)
            if m and m.stick then sticky[#sticky+1]=item else scroll[#scroll+1]=item end
        end
        -- Keep a whole sticky group visible when it fits. If it fills a tiny
        -- window, paginate the group first so no item becomes unreachable.
        if #sticky>=capacity and #scroll>0 or #sticky>capacity then
            local all={}; for _,item in ipairs(sticky) do all[#all+1]=item end
            for _,item in ipairs(scroll) do all[#all+1]=item end; sticky,scroll={},all
        end
        local slots=math.max(1,capacity-#sticky)
        local first,page,pages=ui.page("overview",#scroll,slots,h,false)
        local function row(y,item,key,hv,index)
            local m=pinFor(state,item)
            local count,rate,_,_,_,delta=reading(state,key)
            local bg=m and m.colour or m and m.stick and accent or (index%2==0 and state.settings.panel or state.settings.background)
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            local label=(m and (m.stick and "^ " or "* ") or "")..(m and m.name or hv and state.hv.name or item.name)
            if not hv and state.hv.item and item.key==state.hv.item.key then label=label.." (farm)" end
            if wide then
                local fields=w>=58 and 3 or 2; local col=math.max(9,math.floor(w/(fields+1)))
                local start=w-fields*col+1
                ui.put(2,y,label,start-3)
                ui.put(start,y,Me.amount(count,col),col,true)
                if fields==3 then ui.put(start+col,y,(delta and delta>0 and "+" or "")..Me.amount(delta,col),col,true) end
                ui.put(w-col+1,y,rateText(state,rate,col),col,true)
                local fg=api.ui.contrast(bg)==1 and (rate and rate>0 and 32 or rate and rate<0 and 2 or 256) or 32768
                ui.style(w-col+1,y,col,1,fg,nil)
            else
                -- The unit is already in the header. Drop grouping/decimals
                -- before clipping either value on a one-block monitor.
                local q=Me.amount(count,0)
                local r=rateText(state,rate):gsub(" ","")
                if #q+#r+1>w then r=Me.rateText(rate,0):gsub("/h$",periods[state.settings.period]) end
                if #q+#r+1<=w then ui.put(1,y,label,w,true); ui.put(1,y+1,q.." "..r,w,true)
                else
                    local span=math.min(#r,math.max(3,w-4))
                    ui.put(1,y,hv and "HV" or label,w-span-1); ui.put(w-span+1,y,r,span)
                    ui.put(1,y+1,Me.amount(count,w),w,true)
                end
            end
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="item",value={key=key,item=hv and state.hv.item and Me.identity(state.hv.item) or not hv and Me.identity(item) or nil}}
        end
        if wide then
            local fields=w>=58 and 3 or 2; local col=math.max(9,math.floor(w/(fields+1))); local start=w-fields*col+1
            ui.style(1,top-1,w,1,1,128)
            local order=view.overviewSort
            local function indicator(field) return order and order.field==field and (order.descending and " v" or " ^") or "" end
            ui.put(2,top-1,"Item"..indicator("name"),start-3); ui.put(start,top-1,"Amount"..indicator("amount"),col,true)
            ui.hits[#ui.hits+1]={x1=1,x2=start-1,y=top-1,action="sortColumn",value="name"}
            ui.hits[#ui.hits+1]={x1=start,x2=start+col-1,y=top-1,action="sortColumn",value="amount"}
            if fields==3 then ui.put(start+col,top-1,"Change "..math.floor(state.settings.window/60).."m",col,true) end
            ui.put(w-col+1,top-1,"Avg "..periods[state.settings.period],col,true)
        end
        for i,item in ipairs(sticky) do row(top+(i-1)*rowH,item,item.hv and "hv" or item.key,item.hv,i) end
        for i=1,slots do local item=scroll[first+i]; if item then row(top+(#sticky+i-1)*rowH,item,item.hv and "hv" or item.key,item.hv,first+i+#sticky) end end
        local farmRows=0; for _,item in ipairs(rows) do if not item.hv then farmRows=farmRows+1 end end
        if farmRows==0 then
            local line=math.min(h-1,top+(#sticky+#scroll)*rowH)
            if line>=top+#sticky*rowH and line<h then
                ui.put(1,line,s.status=="ok" and "Farm ME is empty" or "Farm: "..status("farm"),w,true)
                ui.hits[#ui.hits+1]={x1=1,x2=w,y=line,action="sourceInfo"}
            end
        end
        if pages>1 then
            local wing=math.max(2,math.floor(w/8)); local mid=math.floor((w+2*wing)/2)
            ui.action(h,"<","page",{key="overview",page=page-1},1,wing,page>1)
            ui.action(h,">","page",{key="overview",page=page+1},wing+1,2*wing,page<pages)
            ui.action(h,"Pin item","pin",nil,2*wing+1,mid); ui.action(h,"Menu","menu",nil,mid+1,w)
        else ui.footer({{"Pin item","pin"},{"Menu","menu"}}) end
    elseif screen=="menu" then
        ui.menu("Solar farm menu",{{"ME sources","sources"},{"HV panel type / detection","chooseHV"},{"Graph/change: "..state.settings.window/60 .." minutes","window"},
            {"Rate unit: "..periods[state.settings.period],"period"},{"List sorting","listSort"},{"Reset rate learning","resetRates"},{"Withdrawal filter","dropSettings"},
            {"UI color","accent"},{"Source status","sourceInfo"},{"About net rates","about"}},"menu")
    elseif screen=="listSort" then
        ui.menu("Overview order",{{"Pinned first (default)","setOrder","pins"},{"Item A-Z","setOrder","nameUp"},{"Item Z-A","setOrder","nameDown"},
            {"Amount high-low","setOrder","amountDown"},{"Amount low-high","setOrder","amountUp"}},"listSort",{{"Back","menu"}})
    elseif screen=="resetRates" then
        ui.menu("Restart learned rates",{{"Main / HV only","requestReset","main"},{"Farm only","requestReset","farm"},{"Both ME sources","requestReset","both"}},"reset",{{"Cancel","menu"}})
    elseif screen=="confirmReset" then
        ui.heading("Reset rate learning?",accent)
        ui.put(1,2,view.resetRole=="both" and "Both sources" or view.resetRole=="main" and "Main / HV" or "Farm",w,true)
        ui.put(1,3,"Keep sources and pins",w,true)
        ui.footer({{"Reset","confirmRateReset"},{"Cancel","menu"}})
    elseif screen=="sources" then
        ui.menu("ME sources",{{state.sources.farm and "Farm: "..state.sources.farm.clientId or "Select farm ME","source","farm"},
            {state.sources.main and "Main: "..state.sources.main.clientId or "Select main ME (HV)","source","main"}},"sources",{{"Back","menu"}})
    elseif screen=="items" then
        local rows,s=rowsFor(state,view,context.windowId,view.purpose or "pin",api)
        local hv=view.purpose=="hv"; local start=2
        ui.heading(hv and "HV output: main ME" or "Pin overview item",accent)
        local source=state.sources[hv and "main" or "farm"] or {}
        local path=api.ui.breadcrumb({hv and "Main ME" or "Farm ME",source.clientId,source.side,source.target},w,h)
        if path then ui.put(1,2,path,w); ui.style(1,2,w,1,256,32768); start=3 end
        local rowH=w>=32 and 1 or 2; local slots=math.max(1,math.floor((h-start)/rowH)); if #rows>slots then slots=math.max(1,math.floor((h-start-1)/rowH)) end
        local first=ui.page("items",#rows,slots,h-1)
        for i=1,slots do local item=rows[first+i]; if item then
            local y=start+(i-1)*rowH; local bg=i%2==0 and state.settings.panel or state.settings.background
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            local q=Me.amount(Me.count(item.hv and snapshots.main or s,item.key),math.floor(w/2))
            ui.put(1,y,item.name..(item.hv and " [main]" or ""),rowH==1 and w-#q-1 or w); ui.put(rowH==1 and w-#q+1 or 1,y+rowH-1,q,rowH==1 and #q or w,rowH>1)
            local value=Me.identity(item); value.hv=item.hv
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="selectItem",value=value}
        end end
        if #rows==0 then
            ui.put(1,start,s.status=="ok" and (hv and "No HV type recognised" or "No matching items") or s.error or s.status,w,true)
            if start+1<h-1 then ui.put(1,start+1,hv and "Find > register exact item" or "Find > search / register",w,true) end
        end
        ui.footer(hv and {{"Back","menu"},{"Auto","autoHV"},{"Find","filters"}} or {{"Back","home"},{"Find","filters"}})
    elseif screen=="filters" then
        ui.menu("Find item",{{"Search: "..(view.query or ""),"search"},{"Sort: "..(view.sort or "name"),"sort"},
            {view.descending and "Order: Down" or "Order: Up","direction"},{"Refresh list","refresh"},{"Register absent item","newManual"}},"filters",{{"Back","items"}})
    elseif screen=="manual" then
        local m=view.manual
        ui.menu("Absent item identity",{{"Name: "..m.name,"manualText","name"},{"RawName: "..m.raw,"manualText","raw"},{"Damage: "..m.damage,"manualDamage"},
            {"Use item","saveManual",nil,Me.textValue(m.raw,256) and Me.textValue(m.name,256)}},"manual",{{"Back","items"}})
    elseif screen=="item" then
        local item=view.selected; local key=view.key; local m=pinFor(state,{hv=key=="hv",key=key})
        local count,rate,seconds,drops,removed,delta,recent,recentSeconds=reading(state,key)
        local lines={key=="hv" and "HV solar / main ME" or (m and m.name or item and item.name or "Item"),"Amount: "..Me.amount(count),"Learned average: "..rateText(state,rate),
            "Valid observed time: "..elapsedText(seconds),"Recent "..state.settings.window/60 .."m change: "..(delta and delta>0 and "+" or "")..Me.amount(delta),
            "Recent window rate: "..rateText(state,recent),"Recent observed time: "..elapsedText(recentSeconds),"Large withdrawals ignored: "..drops,"Ignored items: "..Me.amount(removed)}
        lines[#lines+1]="Source: "..(key=="hv" and "Main ME" or "Farm ME").." / "..status(key=="hv" and "main" or "farm")
        if item then lines[#lines+1]=item.raw.." / "..item.damage end
        ui.info("Item overview",lines,"item", "home")
        ui.footer({{m and "Edit pin" or "Pin item","editPin"},{"Back","home"}})
    elseif screen=="editPin" then
        local m=view.key=="hv" and state.hv or metric(state,view.key)
        if not m then view.screen="home"; return form(w,h,state,api,context) end
        local rows={}
        rows[#rows+1]={"Name: "..m.name,"rename"}
        rows[#rows+1]={m.stick and "Stick: On" or "Stick: Off","stick"}
        rows[#rows+1]={"Item color","pinColour"}
        rows[#rows+1]={"Drop minimum: "..(m.dropCount or state.settings.dropCount),"field","dropCount"}
        rows[#rows+1]={"Drop percent: "..(m.dropPercent or state.settings.dropPercent),"field","dropPercent"}
        rows[#rows+1]={"Use default filter","defaultFilter"}
        if view.key=="hv" then rows[#rows+1]={"Select HV item","chooseHV"} end
        rows[#rows+1]={"Unpin item","unpin"}
        ui.menu("Pinned item",rows,"editPin",{{"Back","home"}})
    elseif screen=="dropSettings" then
        ui.menu("Ignore big withdrawals",{{"Minimum: "..state.settings.dropCount,"globalField","dropCount"},{"Percent: "..state.settings.dropPercent,"globalField","dropPercent"}},"drop",{{"Back","menu"}})
    elseif screen=="pinColour" then
        local m=view.key=="hv" and state.hv or metric(state,view.key)
        local lines,hits=api.ui.palette(w,h,m and m.colour,"Item color"); for _,hit in ipairs(hits) do if hit.action=="cancel" then hit.action="editPin" end end
        return lines,hits
    elseif screen=="number" then ui.numberPad(view.number.key,view.number.draft,view.number.back)
    elseif screen=="keyboard" then ui.keyboard(view.keyboard)
    elseif screen=="sourceInfo" then
        local lines={}
        for _,role in ipairs({"farm","main"}) do local s=snapshots[role] or {status="unconfigured"}; local a=state.sources[role]
            lines[#lines+1]=(role=="farm" and "Farm ME: " or "Main ME (HV only): ")..s.status
            if a then lines[#lines+1]=a.clientId.." / "..a.side.." / "..a.target end
            if s.error then lines[#lines+1]=s.error end
            if s.status=="ok" then
                lines[#lines+1]="Items: "..Me.amount(s.total).." / "..Me.amount(s.types).." types"
                lines[#lines+1]="Reading age: "..math.floor(s.age or 0).."s"
            end
            if state.history[role].limited then lines[#lines+1]="Rate history shortened to fit memory" end
            local learning=state.averages[role]
            lines[#lines+1]="Learned time: "..elapsedText(learning.seconds+learning.fraction)
            if learning.full or learning.invalid then lines[#lines+1]="Learning limit: untracked rates are unknown; reset learning to restart" end
        end
        lines[#lines+1]="HV selection: "..state.hv.selection
        lines[#lines+1]=state.hv.item and "HV item: "..state.hv.item.name.." / "..state.hv.item.raw.." / "..state.hv.item.damage or "HV not identified; use Auto or select an exact panel type"
        ui.info("ME source status",lines,"info","menu")
    elseif screen=="about" or screen=="message" then
        ui.info("Solar farm",{screen=="message" and view.message or "Average rates use all accepted changes divided by all valid observed time. Samples keep contributing across restarts, so steady production measured in batches settles with longer observation. Graph/change selects the recent display period, not the lifetime learning duration. Reset rate learning after a deliberate production change if you want a new baseline. Missing data and large withdrawals contribute neither change nor time for that item. Recent details remain available separately. The three-row curve has six height levels using . and |, with one time column per character and fresh sensor samples. It cannot measure faster than the sensor. Click Item or Amount to sort, click again to reverse; Stick items stay above the scrolling order. Menu offers the same sorting on small screens. Only HV output comes from Main; every farm item uses Farm. Level emitter owns item alarms. These are net stock changes: transfers, consumption and deposits can affect them, and no gross crafting or SMF throughput is inferred."},"info",screen=="message" and view.back or "menu")
    else view.screen="home"; return form(w,h,state,api,context) end
    return ui.lines,ui.hits
end
function app.render(w,h,state,api,context) if not ready then return {"Solar farm blocked","Check OS console"} end; return (form(w,h,state,api,context)) end
local function beginText(view,target,key,value,back,limit) view.keyboard={target=target,key=key,draft=value or "",back=back,limit=limit or 24,bank=0,page=1}; view.screen="keyboard" end
local function pin(state,api,view,item)
    if item.hv then
        if state.hv.pinned then return true end
        return commit(state,api,view,function() state.hv.pinned,state.hv.stick,state.hv.order=true,false,state.nextId; state.nextId=state.nextId+1 end)
    end
    if metric(state,item.key) then return true end
    if #state.metrics>=64 then view.message,view.back,view.screen="Maximum 64 pins","home","message"; return false end
    return commit(state,api,view,function()
        state.metrics[#state.metrics+1]={id=state.nextId,name=item.name:sub(1,24),item=Me.identity(item)}; state.nextId=state.nextId+1; remember(state,item)
    end)
end
local function setOrder(view,order,api,windowId)
    local old,page=copy(view.overviewSort),view.pages.overview
    view.overviewSort,view.pages.overview=order,1; frozen[windowId]=nil
    local ok,err=api.save()
    if ok then api.invalidateAppViews(name)
    else view.overviewSort,view.pages.overview=old,page; view.message,view.back,view.screen="Save failed: "..tostring(err),"home","message" end
    return ok
end
function app.handleTouch(x,y,w,h,state,api,context)
    if not ready then return false end
    local _,hits=form(w,h,state,api,context); local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view; local m=view.key=="hv" and state.hv or metric(state,view.key)
    if action=="page" then view.pages[value.key]=math.max(1,value.page)
    elseif ({home=true,menu=true,sources=true,items=true,filters=true,manual=true,dropSettings=true,sourceInfo=true,about=true,keyboard=true,number=true,listSort=true,resetRates=true})[action] then view.screen=action
    elseif action=="sortColumn" then
        local current=view.overviewSort
        local descending=current and current.field==value and not current.descending or not (current and current.field==value) and value=="amount"
        setOrder(view,{field=value,descending=descending==true},api,context.windowId)
    elseif action=="setOrder" then
        local order=value~="pins" and {field=value:find("amount",1,true) and "amount" or "name",descending=value:find("Down",1,true)~=nil} or nil
        if setOrder(view,order,api,context.windowId) then view.screen="home" end
    elseif action=="requestReset" then view.resetRole,view.screen=value,"confirmReset"
    elseif action=="confirmRateReset" then
        local role=view.resetRole
        if ({main=true,farm=true,both=true})[role] and commit(state,api,view,function()
            for _,r in ipairs({"main","farm"}) do if role=="both" or role==r then
                state.averages[r]=Long.new()
                if r=="main" then state.averages.main.itemKey=state.hv.item and state.hv.item.key; state.hvTrace=newTrace() end
            end end
        end) then
            for _,r in ipairs({"main","farm"}) do if role=="both" or role==r then previous[r],measured[r]=nil,false end end
            view.screen="home"
        end
    elseif action=="source" then local ok,err=api.pickSensor(context.windowId,value,state.sources[value],"ae"); if not ok then view.message,view.back,view.screen=err,"sources","message" end
    elseif action=="pin" or action=="chooseHV" then view.purpose,view.screen,view.query,view.pages=action=="chooseHV" and "hv" or "pin","items","",{}; frozen[context.windowId]=nil
    elseif action=="selectItem" then
        local ok
        if view.purpose=="hv" then
            local changed=state.averages.main.itemKey~=value.key
            ok=commit(state,api,view,function() state.hv.item=Me.identity(value); state.hv.selection="manual"; if changed then resetMain(state,value.key) end end)
            if ok and changed then previous.main,measured.main=nil,false end
        else ok=pin(state,api,view,value) end
        if ok then view.key,view.selected,view.screen=(view.purpose=="hv" or value.hv) and "hv" or value.key,Me.identity(value),"home" end
    elseif action=="autoHV" then
        if commit(state,api,view,function() state.hv.selection,state.hv.item="auto",nil end) then
            if snapshots.main then snapshots.main.hvChecked=nil end; view.screen="home"
        end
    elseif action=="item" then view.key,view.selected,view.screen,view.pages=value.key,copy(value.item),"item",{}
    elseif action=="editPin" then
        if view.key=="hv" then if pin(state,api,view,{hv=true}) then view.screen="editPin" end
        elseif m or view.selected and pin(state,api,view,view.selected) then view.screen="editPin" end
    elseif action=="stick" and m then commit(state,api,view,function() m.stick=not m.stick end)
    elseif action=="window" then commit(state,api,view,function() state.settings.window=state.settings.window==300 and 900 or state.settings.window==900 and 3600 or 300 end)
    elseif action=="period" then commit(state,api,view,function() state.settings.period=state.settings.period==3600 and 60 or state.settings.period==60 and 1 or 3600 end)
    elseif action=="unpin" and m then
        if commit(state,api,view,function()
            if view.key=="hv" then state.hv.pinned,state.hv.stick=false,false
            else local _,index=Me.find(state.metrics,m.id); table.remove(state.metrics,index); state.catalog[m.item.key]=nil end
        end) then view.screen="home" end
    elseif action=="defaultFilter" and m then commit(state,api,view,function() m.dropCount,m.dropPercent=nil,nil end)
    elseif action=="pinColour" then view.screen="pinColour"
    elseif action=="colour" and m then if commit(state,api,view,function() m.colour=value end) then view.screen="editPin" end
    elseif action=="rename" and m then beginText(view,"pin","name",m.name,"editPin")
    elseif action=="field" or action=="globalField" or action=="manualDamage" then
        local key=action=="manualDamage" and "damage" or value; local target=action=="field" and "pin" or action=="globalField" and "settings" or "manual"
        local d=target=="pin" and m or target=="settings" and state.settings or view.manual
        view.number={key=key,target=target,draft=Me.digits(d[key] or state.settings[key] or 0),back=view.screen}; view.screen="number"
    elseif action=="digit" then local n=view.number; if value=="Clr" then n.draft="" elseif value=="Del" then n.draft=n.draft:sub(1,-2) elseif #n.draft<16 then n.draft=(n.draft=="0" and "" or n.draft)..value end
    elseif action=="setNumber" then
        local n=view.number; local v=tonumber(n.draft=="" and "0" or n.draft); local lo=n.key=="dropCount" and 1 or 0; local hi=n.key=="damage" and 2147483647 or n.key=="dropPercent" and 100 or Me.MAX
        if integer(v,lo,hi) then
            if n.target=="manual" then view.manual[n.key],view.screen=v,n.back
            elseif commit(state,api,view,function() (n.target=="pin" and m or state.settings)[n.key]=v end) then view.screen=n.back end
        else view.message,view.back,view.screen="Whole number outside allowed range","number","message" end
    elseif action=="sort" then view.sort=view.sort=="amount" and "name" or "amount"; frozen[context.windowId]=nil
    elseif action=="direction" then view.descending=not view.descending; frozen[context.windowId]=nil
    elseif action=="refresh" then frozen[context.windowId]=nil; view.pages.items=nil; view.screen="items"
    elseif action=="search" then beginText(view,"search","query",view.query,"items",64)
    elseif action=="newManual" then view.manual,view.screen={name="New item",raw="",damage=0},"manual"
    elseif action=="manualText" then beginText(view,"manual",value,view.manual[value],"manual",256)
    elseif action=="saveManual" then
        local v=view.manual; local item={raw=v.raw,name=v.name,damage=v.damage,key=Me.itemKey(v.raw,v.damage,v.name)}
        if Me.itemValid(item) then
            local ok
            if view.purpose=="hv" then
                local changed=state.averages.main.itemKey~=item.key
                ok=commit(state,api,view,function() state.hv.item=item; state.hv.selection="manual"; if changed then resetMain(state,item.key) end end)
                if ok and changed then previous.main,measured.main=nil,false end
            else ok=pin(state,api,view,item) end
            if ok then view.screen="home" end
        end
    elseif action=="key" or action=="space" then api.ui.typeKey(view.keyboard,action=="space" and " " or value,view.keyboard.limit)
    elseif action=="backspace" then view.keyboard.draft=view.keyboard.draft:sub(1,-2)
    elseif action=="clearText" then view.keyboard.draft=""
    elseif action=="bank" then view.keyboard.bank,view.keyboard.page=(view.keyboard.bank+1)%3,1
    elseif action=="keyPage" then local k=view.keyboard; local slots=math.max(4,math.min(10,math.floor(w/2)))*math.max(1,math.min(3,h-4)); k.page=k.page%math.ceil((k.bank==2 and 15 or 26)/slots)+1
    elseif action=="saveText" then
        local k=view.keyboard; local text=k.draft:gsub("^%s+",""):gsub("%s+$","")
        if k.target=="search" then view.query,view.screen=text,"items"; frozen[context.windowId]=nil; view.pages.items=nil
        elseif Me.textValue(text,k.limit) then
            if k.target=="manual" then view.manual[k.key],view.screen=text,k.back
            elseif m and commit(state,api,view,function() m[k.key]=text end) then view.screen=k.back end
        end
    elseif action=="accent" then api.pickColour(context.windowId) end
    return true
end
function app.shutdown(state,api)
    for _,role in ipairs({"main","farm"}) do api.unwatchSensor(name.."_"..role) end
    cache,snapshots,previous,measured,frozen,structures={},{},{},{},{},{}
end
return app
