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
function app.init(state,api,context)
    ready=false; cache,snapshots,previous,measured,frozen,structures={},{},{},{},{},{}
    assert(api.ui.form and api.migrateAppState,"Solar farm requires bundled-v30 OS")
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
    state.hv.order,state.hv.name=state.hv.order or 0,state.hv.name or "HV solar"
    assert(type(state.hv.pinned)=="boolean" and type(state.hv.stick)=="boolean"
        and integer(state.hv.order,0,Me.MAX) and Me.label(state.hv.name),"Invalid HV pin")
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
    ready=true
end
local function sample(role,state,s)
    local old=previous[role]
    if s.status~="ok" or not Me.number(s.time,0,Me.MAX) or not integer(s.sequence,0,Me.MAX) then previous[role],measured[role]=nil,false; return end
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
            measured[role]=Me.Rates.record(state.history[role],state.elapsed,dt,changes)
        end
    end
    previous[role]={key=s.key,sequence=s.sequence,time=s.time,items=s.items}
end
function app.background(dt,state,api)
    if not ready then return end
    state.elapsed=state.elapsed+math.max(0,dt or 0)
    local boots=Me.boots(api)
    for _,role in ipairs({"main","farm"}) do
        if state.sources[role] then api.watchSensor(name.."_"..role,state.sources[role],{profile="ae_items"}) end
        local s=Me.snapshot(cache,api,state.sources[role],boots); snapshots[role]=s
        if role=="farm" and s.status=="ok" then
            local keys={}; for key in pairs(s.items) do keys[#keys+1]=key end; table.sort(keys)
            local signature=table.concat(keys,"\n")
            if structures.farm~=signature then structures.farm=signature; frozen={}; api.invalidateAppViews(name) end
        end
        if role=="main" and not state.hv.item and s.status=="ok" then
            local candidates={}; for _,item in pairs(s.items) do if Me.isHVSolar(item) then candidates[#candidates+1]=item end end
            if #candidates==1 then commit(state,api,nil,function() state.hv.item=Me.identity(candidates[1]) end) end
        end
        if role=="farm" and s.status=="ok" then
            for _,m in ipairs(state.metrics) do if m.legacy and s.items[m.item.key] then m.legacy=nil; remember(state,m.item); frozen={} end end
        end
        sample(role,state,s)
    end
end
local function reading(state,key)
    local item=binding(state,key); local role=key=="hv" and "main" or "farm"; local s=snapshots[role]
    local count=Me.count(s,item and item.key); local rate,seconds,drops,removed
    if item then
        local delta; delta,seconds,drops,removed=Me.Rates.sum(state.history[role],item.key,state.elapsed,state.settings.window)
        if count~=nil and measured[role] and seconds>0 then rate=delta/seconds*state.settings.period end
    end
    return count,rate,seconds or 0,drops or 0,removed or 0
end
local function rateText(state,rate,width)
    local text=Me.rateText(rate,width):gsub("/h$",periods[state.settings.period]); return text
end
local function rowsFor(state,view,windowId,purpose)
    local role=purpose=="hv" and "main" or "farm"
    local s=snapshots[role] or {status="unconfigured",items={}}
    local signature=purpose..":"..(s.key or "")..":"..(view.query or "")..":"..(view.sort or "name")..":"..tostring(view.descending)
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
            row.hv=true; all[row.key]=row
        end
    end
    local rows,query={},(view.query or ""):lower()
    for _,item in pairs(all) do
        if (not state.hv.item or item.key~=state.hv.item.key or purpose=="hv" or item.hv)
            and (query=="" or item.name:lower():find(query,1,true) or item.raw:lower():find(query,1,true)) then rows[#rows+1]=item end
    end
    table.sort(rows,function(a,b)
        if purpose=="overview" then
            local am,bm=pinFor(state,a),pinFor(state,b)
            if (am~=nil)~=(bm~=nil) then return am~=nil end
            if am and bm then return (a.hv and am.order or am.id)<(b.hv and bm.order or bm.id) end
        end
        if view.sort=="amount" and purpose~="overview" then
            local aq,bq=Me.count(a.hv and snapshots.main or s,a.key) or -1,Me.count(b.hv and snapshots.main or s,b.key) or -1
            if aq~=bq then return view.descending and aq>bq or not view.descending and aq<bq end
        end
        local an,bn=a.name:lower(),b.name:lower()
        if an~=bn then return purpose~="overview" and view.descending and an>bn or (purpose=="overview" or not view.descending) and an<bn end
        return a.key<b.key
    end)
    if s.status=="ok" then frozen[windowId]={signature=signature,rows=rows} end
    return rows,s
end
function app.handleSensorSelection(role,selected,state,api,context)
    if (role~="main" and role~="farm") or not Me.address(selected) then return false,"Invalid source" end
    local old=state.sources[role]
    if old and Me.sourceKey(old)==Me.sourceKey(selected) and old.card==selected.card and old.targetType==selected.targetType then context.view.screen="sources"; return true end
    local ok,err=commit(state,api,context.view,function()
        state.sources[role]=copy(selected); state.history[role]=Me.Rates.new()
        if role=="main" then state.hv.item=nil else state.catalog={}; for _,m in ipairs(state.metrics) do m.legacy=true end end
    end)
    if ok then snapshots[role],previous[role],measured[role]=nil,nil,false; context.view.screen="sources" end
    return ok,err
end
local function form(w,h,state,api,context)
    local view=context.view; view.pages=view.pages or {}; local screen=view.screen or "home"
    local ui=api.ui.form(w,h,view,api.getAppColour(name),state.settings.background,state.settings.panel)
    local accent=api.getAppColour(name)
    if screen=="home" then
        local rows,s=rowsFor(state,view,context.windowId,"overview")
        local wide=w>=36; local rowH=wide and 1 or 2; local top=wide and 3 or 2
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
        ui.heading((wide and "Farm stock / net rate  " or "")..math.floor(state.settings.window/60).."m "..periods[state.settings.period]..(pages>1 and " "..page.."/"..pages or ""),accent)
        local function row(y,item,key,hv,index)
            local m=pinFor(state,item)
            local count,rate=reading(state,key)
            local bg=m and m.colour or m and m.stick and accent or (index%2==0 and state.settings.panel or state.settings.background)
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            local label=(m and (m.stick and "^ " or "* ") or "")..(m and m.name or hv and state.hv.name or item.name)
            if wide then
                local col=math.max(9,math.floor(w/3)); ui.put(2,y,label,w-2*col-3)
                local q,r=Me.amount(count,col),rateText(state,rate,col)
                ui.put(w-2*col,y,q,col,true); ui.put(w-col+1,y,r,col,true)
            else
                -- The unit is already in the header. Drop grouping/decimals
                -- before clipping either value on a one-block monitor.
                local q=Me.amount(count,0)
                local r=rateText(state,rate):gsub("/[smh]$",""):gsub(" ","")
                if #q+#r+2>w then r=Me.rateText(rate,0):gsub("/h$","") end
                if #q+#r+2<=w then ui.put(1,y,label,w,true); ui.put(1,y+1,q.."  "..r,w,true)
                else
                    local span=math.min(#r,math.max(3,w-4))
                    ui.put(1,y,hv and "HV" or label,w-span-1); ui.put(w-span+1,y,r,span)
                    ui.put(1,y+1,Me.amount(count,w),w,true)
                end
            end
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="item",value={key=key,item=hv and state.hv.item and Me.identity(state.hv.item) or not hv and Me.identity(item) or nil}}
        end
        if wide then
            local col=math.max(9,math.floor(w/3)); ui.put(2,2,"Item",w-2*col-3); ui.put(w-2*col,2,"Amount",col,true); ui.put(w-col+1,2,"Net rate",col,true)
        end
        for i,item in ipairs(sticky) do row(top+(i-1)*rowH,item,item.hv and "hv" or item.key,item.hv,i) end
        for i=1,slots do local item=scroll[first+i]; if item then row(top+(#sticky+i-1)*rowH,item,item.hv and "hv" or item.key,item.hv,first+i+#sticky) end end
        if #rows==0 then ui.put(1,top,s.status=="ok" and "No farm items" or "Select MEs in Menu",w,true) end
        if pages>1 then
            local wing=math.max(2,math.floor(w/8)); local mid=math.floor((w+2*wing)/2)
            ui.action(h,"<","page",{key="overview",page=page-1},1,wing,page>1)
            ui.action(h,">","page",{key="overview",page=page+1},wing+1,2*wing,page<pages)
            ui.action(h,"Pin item","pin",nil,2*wing+1,mid); ui.action(h,"Menu","menu",nil,mid+1,w)
        else ui.footer({{"Pin item","pin"},{"Menu","menu"}}) end
    elseif screen=="menu" then
        ui.menu("Solar farm menu",{{"ME sources","sources"},{"HV solar item","chooseHV"},{"Average: "..state.settings.window/60 .." minutes","window"},
            {"Rate unit: "..periods[state.settings.period],"period"},{"Withdrawal filter","dropSettings"},{"UI colour","accent"},{"Source status","sourceInfo"},{"About net rates","about"}},"menu")
    elseif screen=="sources" then
        ui.menu("ME sources",{{state.sources.farm and "Farm: "..state.sources.farm.clientId or "Select farm ME","source","farm"},
            {state.sources.main and "Main: "..state.sources.main.clientId or "Select main ME (HV)","source","main"}},"sources",{{"Back","menu"}})
    elseif screen=="items" then
        local rows,s=rowsFor(state,view,context.windowId,view.purpose or "pin")
        ui.heading(view.purpose=="hv" and "Select main-ME HV solar" or "Pin overview item",accent)
        local rowH=w>=32 and 1 or 2; local slots=math.max(1,math.floor((h-2)/rowH)); if #rows>slots then slots=math.max(1,math.floor((h-3)/rowH)) end
        local first=ui.page("items",#rows,slots,h-1)
        for i=1,slots do local item=rows[first+i]; if item then
            local y=2+(i-1)*rowH; local bg=i%2==0 and state.settings.panel or state.settings.background
            ui.style(1,y,w,rowH,api.ui.contrast(bg),bg)
            local q=Me.amount(Me.count(item.hv and snapshots.main or s,item.key),math.floor(w/2))
            ui.put(1,y,item.name,rowH==1 and w-#q-1 or w); ui.put(rowH==1 and w-#q+1 or 1,y+rowH-1,q,rowH==1 and #q or w,rowH>1)
            local value=Me.identity(item); value.hv=item.hv
            ui.hits[#ui.hits+1]={x1=1,x2=w,y1=y,y2=y+rowH-1,action="selectItem",value=value}
        end end
        if #rows==0 then ui.put(1,2,s.status=="ok" and "No matching items" or s.error or s.status,w,true) end
        ui.footer({{"Back",view.purpose=="hv" and "menu" or "home"},{"Find","filters"}})
    elseif screen=="filters" then
        ui.menu("Find item",{{"Search: "..(view.query or ""),"search"},{"Sort: "..(view.sort or "name"),"sort"},
            {view.descending and "Order: Down" or "Order: Up","direction"},{"Refresh list","refresh"},{"Register absent item","newManual"}},"filters",{{"Back","items"}})
    elseif screen=="manual" then
        local m=view.manual
        ui.menu("Absent item identity",{{"Name: "..m.name,"manualText","name"},{"RawName: "..m.raw,"manualText","raw"},{"Damage: "..m.damage,"manualDamage"},
            {"Use item","saveManual",nil,Me.textValue(m.raw,256) and Me.textValue(m.name,256)}},"manual",{{"Back","items"}})
    elseif screen=="item" then
        local item=view.selected; local key=view.key; local m=pinFor(state,{hv=key=="hv",key=key})
        local count,rate,seconds,drops,removed=reading(state,key)
        local lines={key=="hv" and "HV solar / main ME" or (m and m.name or item and item.name or "Item"),"Amount: "..Me.amount(count),"Net rate: "..rateText(state,rate),
            "Valid samples: "..math.floor(seconds).."s", "Average window: "..state.settings.window/60 .." minutes","Large withdrawals ignored: "..drops,"Ignored items: "..Me.amount(removed)}
        if item then lines[#lines+1]=item.raw.." / "..item.damage end
        ui.info("Item overview",lines,"item", "home")
        ui.footer({{m and "Edit pin" or "Pin item","editPin"},{"Back","home"}})
    elseif screen=="editPin" then
        local m=view.key=="hv" and state.hv or metric(state,view.key)
        if not m then view.screen="home"; return form(w,h,state,api,context) end
        local rows={}
        rows[#rows+1]={"Name: "..m.name,"rename"}
        rows[#rows+1]={m.stick and "Stick: On" or "Stick: Off","stick"}
        rows[#rows+1]={"Item colour","pinColour"}
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
        local lines,hits=api.ui.palette(w,h,m and m.colour,"Item colour"); for _,hit in ipairs(hits) do if hit.action=="cancel" then hit.action="editPin" end end
        return lines,hits
    elseif screen=="number" then ui.numberPad(view.number.key,view.number.draft,view.number.back)
    elseif screen=="keyboard" then ui.keyboard(view.keyboard)
    elseif screen=="sourceInfo" then
        local lines={}
        for _,role in ipairs({"farm","main"}) do local s=snapshots[role] or {status="unconfigured"}; local a=state.sources[role]
            lines[#lines+1]=(role=="farm" and "Farm ME: " or "Main ME (HV only): ")..s.status
            if a then lines[#lines+1]=a.clientId.." / "..a.side.." / "..a.target end
            if s.error then lines[#lines+1]=s.error end
            if state.history[role].limited then lines[#lines+1]="Rate history shortened to fit memory" end
        end
        ui.info("ME source status",lines,"info","menu")
    elseif screen=="about" or screen=="message" then
        ui.info("Solar farm",{screen=="message" and view.message or "One list combines farm inventory amounts with farm net stock-change rates. Only HV solar uses the main ME. It starts pinned with Stick enabled. Every pinned item can toggle Stick or be unpinned. Sticky items stay above scrolling rows when the group fits; smaller windows page the group first. Other main-ME items are excluded. Rates are observed net changes, not total crafting throughput: simultaneous imports and consumption can cancel out. A large withdrawal is ignored when it meets both the minimum and percentage filters. Offline, unpowered and incomplete inventories are unknown. Rates rebase after outages, restarts or sample gaps over 10 seconds. Pin items to keep them ahead of other farm items and give them a name, colour or custom withdrawal filter. Legacy main-only pins remain hidden until seen in the farm. Level emitter is the separate item alarm app."},"info",screen=="message" and view.back or "menu")
    else view.screen="home"; return form(w,h,state,api,context) end
    return ui.lines,ui.hits
end
function app.render(w,h,state,api,context) if not ready then return {"Solar farm blocked","Check OS console"} end; return (form(w,h,state,api,context)) end
local function beginText(view,target,key,value,back,limit) view.keyboard={target=target,key=key,draft=value or "",back=back,limit=limit or 24,bank=0,page=1}; view.screen="keyboard" end
local function pin(state,api,view,item)
    if item.hv or state.hv.item and item.key==state.hv.item.key then
        if state.hv.pinned then return true end
        return commit(state,api,view,function() state.hv.pinned,state.hv.stick,state.hv.order=true,false,state.nextId; state.nextId=state.nextId+1 end)
    end
    if metric(state,item.key) then return true end
    if #state.metrics>=64 then view.message,view.back,view.screen="Maximum 64 pins","home","message"; return false end
    return commit(state,api,view,function()
        state.metrics[#state.metrics+1]={id=state.nextId,name=item.name:sub(1,24),item=Me.identity(item)}; state.nextId=state.nextId+1; remember(state,item)
    end)
end
function app.handleTouch(x,y,w,h,state,api,context)
    if not ready then return false end
    local _,hits=form(w,h,state,api,context); local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view; local m=view.key=="hv" and state.hv or metric(state,view.key)
    if action=="page" then view.pages[value.key]=math.max(1,value.page)
    elseif ({home=true,menu=true,sources=true,items=true,filters=true,manual=true,dropSettings=true,sourceInfo=true,about=true,keyboard=true,number=true})[action] then view.screen=action
    elseif action=="source" then local ok,err=api.pickSensor(context.windowId,value,state.sources[value],"ae"); if not ok then view.message,view.back,view.screen=err,"sources","message" end
    elseif action=="pin" or action=="chooseHV" then view.purpose,view.screen,view.query,view.pages=action=="chooseHV" and "hv" or "pin","items","",{}; frozen[context.windowId]=nil
    elseif action=="selectItem" then
        local ok
        if view.purpose=="hv" then ok=commit(state,api,view,function() state.hv.item=Me.identity(value); state.history.main=Me.Rates.new() end); previous.main,measured.main=nil,false
        else ok=pin(state,api,view,value) end
        if ok then view.key,view.selected,view.screen=(view.purpose=="hv" or value.hv) and "hv" or value.key,Me.identity(value),"home" end
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
            if view.purpose=="hv" then ok=commit(state,api,view,function() state.hv.item=item; state.history.main=Me.Rates.new() end); previous.main,measured.main=nil,false
            else ok=pin(state,api,view,item) end
            if ok then view.screen="home" end
        end
    elseif action=="key" or action=="space" then local k=view.keyboard; if #k.draft<k.limit then k.draft=k.draft..(action=="space" and " " or value) end
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
