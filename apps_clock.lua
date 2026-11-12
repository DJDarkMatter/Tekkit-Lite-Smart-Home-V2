-- Alarms, timers and stopwatch run centrally even with no visible windows.
-- All hardware writes pass through the OS shared-output queue and its cooldown.
local app={title="Clock",backgroundService=true,minWidth=12,minHeight=6,preferredWidth=44,preferredHeight=18}
local appName,ready,clockStatus,lastError="clock",false,"Waiting for world time",nil
local MAX_DURATION=31536000
local retryElapsed=0
local stopwatchAnchor
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function restore(state,old)
    local keys={}; for key in pairs(state) do keys[#keys+1]=key end
    for _,key in ipairs(keys) do state[key]=nil end
    for key,value in pairs(old) do state[key]=value end
end
local function number(value,low,high) return type(value)=="number" and value==value and value>=low and value<=high end
local function integer(value,low,high) return number(value,low,high) and value==math.floor(value) end
local function digits(value)
    value=math.floor(value); local out={}
    repeat local digit=value%10; out[#out+1]=("0123456789"):sub(digit+1,digit+1); value=math.floor(value/10) until value==0
    return table.concat(out):reverse()
end
local function two(value) local text=digits(value); return #text<2 and "0"..text or text end
local function duration(value,tenths)
    value=math.max(0,value or 0)
    local text=two(math.floor(value/3600))..":"..two(math.floor(value/60)%60)..":"..two(math.floor(value)%60)
    return tenths and text.."."..digits(math.floor(value*10+0.00001)%10) or text
end
local function stopwatchTime(value,clockMode,tenths)
    if clockMode=="game" then return digits(math.floor(value/86400)).."d "..duration(value%86400,false) end
    return duration(value,tenths)
end
local function rebaseStopwatch(state)
    stopwatchAnchor={at=os.clock(),elapsed=state.stopwatch.elapsed}
end
local function syncStopwatch(state)
    local sw=state.stopwatch
    if sw.mode=="real" and sw.running then
        if not stopwatchAnchor then rebaseStopwatch(state) end
        sw.elapsed=stopwatchAnchor.elapsed+math.max(0,os.clock()-stopwatchAnchor.at)
    end
end
local function alarmTime(minute) return two(math.floor(minute/60))..":"..two(minute%60) end
local function colour(value) for i=0,15 do if value==2^i then return true end end; return false end
local function route(value)
    return type(value)=="table" and type(value.clientId)=="string" and #value.clientId>0 and #value.clientId<=64
        and ({top=true,bottom=true,left=true,right=true,front=true,back=true})[value.side] and (value.color==nil or colour(value.color))
end
local function mode(value) return value=="real" or value=="game" end
local function validName(value) return type(value)=="string" and #value>0 and #value<=24 and value:find("%S") and not value:find("[%c]") end
local function signal(value)
    return type(value)=="table" and (value.kind=="constant" or value.kind=="pattern")
        and integer(value.on,value.kind=="constant" and 0 or 1,86400)
        and integer(value.off,1,86400) and integer(value.total,0,MAX_DURATION)
end
local function find(list,id) for index,item in ipairs(list or {}) do if item.id==id then return item,index end end end
local function each(state,fn)
    for _,item in ipairs(state.alarms) do fn(item,"alarm") end
    for _,item in ipairs(state.timers) do fn(item,"timer") end
end
local function outputName(item,kind) return appName.."_"..kind.."_"..item.id end
local function wire(value) return value.clientId..":"..value.side..":"..tostring(value.color or "digital") end
local function signalLength(item) return item.signal.kind=="constant" and item.signal.on or item.signal.total end
local function signalOn(item)
    if not item.ring or signalLength(item)>0 and item.ring.elapsed>=signalLength(item) then return false end
    return item.signal.kind=="constant" or item.ring.elapsed%(item.signal.on+item.signal.off)<item.signal.on
end
local function trim(state,previous)
    local keep=state.settings.history
    for i=#state.timers,1,-1 do
        local item=state.timers[i]
        if item.status=="done" or item.status=="cancelled" then
            local old=previous and find(previous.timers,item.id)
            if not item.ring and not item.alert and not (old and (old.ring or old.alert)) then
                if keep==0 then table.remove(state.timers,i) else keep=keep-1 end
            end
        end
    end
end
-- Numeric world time only. The legacy display-string fallback cannot drive clocks.
local function sample(state,api)
    local sys=api.getSystem()
    if not number(sys.worldTime,0,23.999999999) then return nil end
    local seconds=sys.worldTime*3600
    local civilDay,hasDay
    if integer(sys.worldDay,0,2147483647) then
        -- Minecraft's day counter rolls at 06:00; alarms use civil midnight.
        civilDay=sys.worldDay+(seconds<21600 and 1 or 0); hasDay=true
    else
        local old=state.cursor
        civilDay=old and old.civilDay or 0
        if old and seconds<old.seconds-43200 then civilDay=civilDay+1 end
        hasDay=false
    end
    return {seconds=seconds,civilDay=civilDay,hasDay=hasDay,absolute=civilDay*86400+seconds}
end
local function alertKey(item,kind) return kind.."_"..digits(item.id).."_"..digits(item.alert.id) end
local function publish(state,api)
    local entries={}
    each(state,function(item,kind)
        if item.alert then entries[#entries+1]={key=alertKey(item,kind),title=kind=="alarm" and "Alarm" or "Timer",message=item.name,id=item.alert.id} end
    end)
    table.sort(entries,function(a,b) return a.id<b.id end)
    return api.setNotifications(appName,entries)
end
local function raiseAlert(state,item,api)
    if item.alert then return end -- One outstanding occurrence per alarm/timer.
    item.alert={id=state.nextAlertId,inputArmed=item.dismissInput and api.readInput(item.dismissInput)==false or false}
    state.nextAlertId=state.nextAlertId+1
    if item.route then item.ring={elapsed=0} end
end
local function wireChanges(state,touched,api)
    local groups={}
    each(state,function(item,kind)
        if item.route and touched[wire(item.route)] then
            local key=wire(item.route)
            groups[key]=groups[key] or {name=outputName(item,kind),value=false}
            groups[key].value=groups[key].value or signalOn(item)
        end
    end)
    local changes={}
    for _,change in pairs(groups) do if api.getOutput(change.name)~=change.value then changes[#changes+1]=change end end
    return changes
end
local function commit(state,api,change,changes,view)
    local old=copy(state); change()
    local ok,err=api.updateOutputs(type(changes)=="function" and changes() or changes or {})
    if not ok then
        restore(state,old); lastError="Save/output failed: "..tostring(err)
        if view then view.message,view.back,view.screen=lastError,view.screen or "home","message" end
        return false,err
    end
    lastError=nil; assert(publish(state,api)); api.invalidateAppViews(appName)
    return true
end
local function mapping(item,kind)
    return {name=outputName(item,kind),clientId=item.route.clientId,side=item.route.side,color=item.route.color,initialValue=false}
end
local function offChanges(state,item,kind)
    if not item.ring or not item.route then return {} end
    local on=false
    each(state,function(other) if other~=item and other.route and wire(other.route)==wire(item.route) and signalOn(other) then on=true end end)
    return {{name=outputName(item,kind),value=on}}
end
function app.init(state,api,context)
    assert(api.ui and api.ui.keyboard and api.ui.breadcrumb,"clock requires bundled-v41 OS; run inst server")
    ready=false; lastError,retryElapsed=nil,0
    assert(api.updateOutputs and api.setNotifications,"Clock requires bundled-v25 OS")
    appName=context and context.appName or "clock"
    if state.version==nil then
        state.version,state.alarms,state.timers,state.nextId,state.nextAlertId=2,{},{},1,1
        state.stopwatch={mode="real",elapsed=0,running=false,laps={},lapCounter=0}
        state.settings={history=20}
    end
    local legacy=state.version==1
    if legacy then state.nextAlertId=1 end
    assert((legacy or state.version==2) and type(state.alarms)=="table" and #state.alarms<=64 and type(state.timers)=="table" and #state.timers<=114
        and type(state.settings)=="table" and ({[10]=true,[20]=true,[50]=true})[state.settings.history],"Invalid saved clock")
    local ids,maxId,alerts,maxAlert={},0,{},0
    each(state,function(item,kind)
        if type(item)=="table" and type(item.signal)=="table" and item.signal.kind=="pulse" then item.signal.kind="constant" end
        assert(type(item)=="table" and integer(item.id,1,2147483000) and not ids[item.id] and validName(item.name)
            and integer(item.revision,1,2147483000) and signal(item.signal) and (item.route==nil or route(item.route))
            and (item.dismissInput==nil or route(item.dismissInput)),"Invalid saved clock entry")
        ids[item.id],maxId=true,math.max(maxId,item.id)
        if kind=="alarm" then
            assert(integer(item.minute,0,1439) and type(item.enabled)=="boolean" and type(item.daily)=="boolean"
                and (item.lastDay==nil or integer(item.lastDay,0,2147483648)),"Invalid saved alarm")
        else assert(mode(item.mode) and integer(item.duration,1,MAX_DURATION) and number(item.remaining,0,item.duration)
            and ({running=true,paused=true,done=true,cancelled=true})[item.status],"Invalid saved timer") end
        if item.ring then
            assert(type(item.ring)=="table" and number(item.ring.elapsed,0,9007199254740991) and item.route,"Invalid saved signal")
            if legacy then local progress=item.ring; raiseAlert(state,item,api); item.ring=progress end
            assert(item.alert,"A saved signal requires a pending alert")
        end
        if item.alert then
            assert(type(item.alert)=="table" and integer(item.alert.id,1,2147483000) and not alerts[item.alert.id]
                and type(item.alert.inputArmed)=="boolean","Invalid saved clock alert")
            alerts[item.alert.id],maxAlert=true,math.max(maxAlert,item.alert.id)
            item.alert.inputArmed=false -- Reconnect/boot HIGH is not a new press.
        end
    end)
    assert(integer(state.nextAlertId,maxAlert+1,2147483001),"Invalid saved alert IDs")
    state.version=2
    assert(integer(state.nextId,maxId+1,2147483001),"Invalid saved clock IDs")
    local sw=state.stopwatch
    assert(type(sw)=="table" and mode(sw.mode) and number(sw.elapsed,0,9007199254740991) and type(sw.running)=="boolean"
        and type(sw.laps)=="table" and #sw.laps<=50 and integer(sw.lapCounter,0,2147483000),"Invalid saved stopwatch")
    for _,lap in ipairs(sw.laps) do assert(type(lap)=="table" and integer(lap.number,1,2147483000) and number(lap.elapsed,0,sw.elapsed) and number(lap.split,0,sw.elapsed),"Invalid saved lap") end
    rebaseStopwatch(state)
    if state.cursor then
        assert(type(state.cursor)=="table" and number(state.cursor.seconds,0,86400) and integer(state.cursor.civilDay,0,2147483648),"Invalid saved world cursor")
    end
    -- Rebase at boot. Countdown/pattern progress resumes from its checkpoint;
    -- computer downtime is never invented as elapsed real/game time.
    state.cursor=sample(state,api)
    clockStatus=state.cursor and "World clock ready" or "World clock unavailable"
    local known={}; for _,item in ipairs(api.getOutputs()) do known[item.name]=item end
    local changes={}
    each(state,function(item,kind)
        if item.route and not known[outputName(item,kind)] then changes[#changes+1]=mapping(item,kind) end
    end)
    if #changes>0 then assert(api.updateOutputs(changes)) end
    ready=true
    assert(publish(state,api))
end
function app.background(dt,state,api)
    if not ready then return end
    dt=math.max(0,dt or 0)
    local old=copy(state)
    local current,previous=sample(state,api),state.cursor
    local gameDt,worldDelta=0,nil
    if current and previous and current.hasDay==previous.hasDay then
        worldDelta=current.absolute-previous.absolute
        if worldDelta>=-0.001 and worldDelta<=math.max(180,(dt+retryElapsed)*144+10) then
            gameDt=math.max(0,worldDelta); clockStatus="World clock ready"
        else clockStatus="World time changed; rebased"; worldDelta=nil end
    else clockStatus=current and "World clock ready" or "World clock unavailable" end
    state.cursor=current
    local touched,important={},false
    each(state,function(item,kind)
        if item.ring then
            touched[wire(item.route)]=true
            item.ring.elapsed=item.ring.elapsed+dt
            if signalLength(item)>0 and item.ring.elapsed+0.000001>=signalLength(item) then item.ring=nil; important=true end
        end
    end)
    for _,item in ipairs(state.alarms) do
        if item.enabled and current and previous and worldDelta and worldDelta>0 then
            local dueDay=current.civilDay
            local due=dueDay*86400+item.minute*60
            if due>current.absolute+0.000001 then dueDay,due=dueDay-1,due-86400 end
            if due>previous.absolute+0.000001 and due<=current.absolute+0.000001 and (item.lastDay==nil or item.lastDay<dueDay) then
                item.lastDay,item.revision=dueDay,item.revision+1
                if not item.daily then item.enabled=false end
                if not item.alert then raiseAlert(state,item,api); if item.route then touched[wire(item.route)]=true end end
                important=true
            end
        end
    end
    for _,item in ipairs(state.timers) do
        if item.status=="running" then
            item.remaining=math.max(0,item.remaining-(item.mode=="game" and gameDt or dt))
            if item.remaining<0.000001 then
                item.remaining,item.status=0,"done"
                if not item.alert then raiseAlert(state,item,api); if item.route then touched[wire(item.route)]=true end end
                important=true
            end
        end
    end
    local sw=state.stopwatch
    if sw.running then
        if sw.mode=="game" then sw.elapsed=sw.elapsed+gameDt else syncStopwatch(state) end
    end
    each(state,function(item)
        if item.alert and item.dismissInput then
            local input=api.readInput(item.dismissInput)
            if input==false then item.alert.inputArmed=true
            elseif input==nil then item.alert.inputArmed=false
            elseif item.alert.inputArmed then
                if item.route and item.ring then touched[wire(item.route)]=true end
                item.alert,item.ring,item.revision=nil,nil,item.revision+1
                important=true
            end
        end
    end)
    local changes=wireChanges(state,touched,api)
    -- Remove mappings of history entries that trim away, without leaving aliases.
    trim(state,old)
    local retained={}; each(state,function(item,kind) retained[outputName(item,kind)]=true end)
    each(old,function(item,kind) if item.route and not retained[outputName(item,kind)] then changes[#changes+1]={name=outputName(item,kind),remove=true} end end)
    if #changes>0 or important then
        local ok,err=api.updateOutputs(changes)
        if not ok then
            restore(state,old); retryElapsed=retryElapsed+dt; lastError="Checkpoint pending: "..tostring(err)
        else lastError,retryElapsed=nil,0 end
    else retryElapsed=0 end
    assert(publish(state,api))
end
local function notice(view,text,back) view.message,view.back,view.screen=text,back or view.screen or "home","message" end
local function draftFor(item,kind)
    return {kind=kind,id=item and item.id,revision=item and item.revision,
        name=item and item.name or (kind=="alarm" and "Alarm" or "Timer"),minute=item and item.minute or 360,
        enabled=item==nil or item.enabled,daily=item==nil or item.daily,mode=item and item.mode or "real",
        duration=item and item.duration or 60,route=item and copy(item.route),dismissInput=item and copy(item.dismissInput),
        signal=item and copy(item.signal) or {kind="constant",on=2,off=2,total=10}}
end
function app.handleIOSelection(key,address,state,api,context)
    if (key~="signal" and key~="dismiss") or not context.view.draft then return false,"Editor was closed" end
    if not route(address) then return false,"Invalid IO route" end
    context.view.draft[key=="dismiss" and "dismissInput" or "route"]=copy(address)
    return true -- Draft only; Save applies and checkpoints the route.
end
local function build(width,height,state,api,context)
    local view=context.view; view.pages=view.pages or {}
    if view.draft and view.draft.signal and view.draft.signal.kind=="pulse" then view.draft.signal.kind="constant" end
    local screen=view.screen or "home"
    local kind=view.kind or "alarm"
    local item=find(kind=="alarm" and state.alarms or state.timers,view.id)
    if (screen=="detail" or screen=="delete" or screen=="routeInfo") and not item then
        screen=kind=="alarm" and "alarms" or "timers"; view.screen=screen
    end
    if (screen=="edit" or screen=="number" or screen=="keyboard") and not view.draft then screen,view.screen="home","home" end
    local accent=api.getAppColour(context.appName or appName)
    if screen=="number" then
        local field=view.number
        local pad=api.ui.form(width,height,view,accent)
        pad.numberPad(field.key=="minute" and "World time HHMM" or field.key.." (seconds)",field.draft,"edit")
        return pad.finish()
    end
    local ui=api.ui.content(width,height)
    ui.style(1,1,width,height,1,32768)
    local function button(y,label,action,value,x1,x2,enabled,bg,rows)
        ui.button(y,label,action,x1,x2,enabled,bg or 128,nil,value,rows)
    end
    local function footer(items,rows)
        rows=rows or 1
        ui.buttonRow(height-rows+1,items,rows)
    end
    local function page(key,count,slots,row)
        local pages=math.max(1,math.ceil(count/slots))
        local current=math.max(1,math.min(view.pages[key] or 1,pages)); view.pages[key]=current
        if pages>1 then
            local half=math.floor(width/2)
            button(row,"< "..current.."/"..pages,"page",{key=key,page=current-1},1,half,current>1)
            button(row,">","page",{key=key,page=current+1},half+1,width,current<pages)
        end
        return (current-1)*slots
    end
    local function menu(title,items,key,bottom,foot)
        ui.heading(title,accent)
        local slots=#items<=bottom-1 and bottom-1 or bottom-2
        local first=page(key,#items,slots,bottom)
        local choices={}
        for i=first+1,math.min(first+slots,#items) do choices[#choices+1]=items[i] end
        ui.choices(2,bottom-(#items>slots and 1 or 0),choices)
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
        for i=1,slots do ui.text(i+1,wrapped[first+i] or "") end
        footer({{"Back",back}})
    end
    if screen=="home" then
        local running=0; for _,timer in ipairs(state.timers) do if timer.status=="running" then running=running+1 end end
        local clock=api.getSystem()
        local time=clock.gameTime or "?:??"
        local day=clock.worldDay and "Day "..digits(clock.worldDay)
        local digitRoom=math.min(10,height-(width>=28 and 11 or 17))
        local readout=ui.readout(2,time,digitRoom,1,32768)
        local header=readout>0 and readout+2 or 1
        if readout>0 then
            if day then ui.text(header,day,true); ui.style(1,header,width,1,256) end
        else
            local text=day and time.."  "..day or time
            ui.text(1,#text<=width and text or time,true)
            ui.style(1,1,width,1,api.ui.contrast(accent),accent)
        end
        local bottom=height-1
        if bottom-header>=8 then bottom=bottom-1 end
        ui.choices(header+1,bottom,{{"Alarms","alarms"},{"Timers","timers"},
            {"Stopwatch","stopwatch"},{"World time","worldTime"}},true)
        local counts={digits(#state.alarms).." set",digits(running).." running"}
        for i,text in ipairs(counts) do
            local hit=ui.hits[i]
            local span=hit.x2-hit.x1+1
            if hit.y<hit.y2 and #text<=span then
                ui.put(hit.x1,hit.y+1,text,span,true)
                ui.style(hit.x1,hit.y+1,span,1,256)
            end
        end
        footer({{width>=17 and "Settings" or "Setup","settings"},{"Status","status"}})
    elseif screen=="worldTime" then
        local clock=api.getSystem()
        ui.heading("World time",accent)
        local value=clock.gameTime or "?:??"
        local readout=height>=10 and ui.readout(2,value,height-5,api.ui.contrast(accent),accent) or 0
        if readout==0 then
            ui.text(2,value,true)
            ui.style(1,2,width,1,api.ui.contrast(accent),accent)
        end
        local row=2+math.max(1,readout)
        if clock.worldDay~=nil then ui.text(row,"Day "..digits(clock.worldDay),true); row=row+1 end
        if value=="?:??" then ui.text(row,width>=20 and "Waiting for world time" or "Unavailable",true) end
        footer({{"Back","home"}})
    elseif screen=="alarms" or screen=="timers" then
        local list=screen=="alarms" and state.alarms or state.timers
        ui.heading(screen=="alarms" and "World-time alarms" or "Timers / recent",accent)
        local depth=math.min(api.ui.controlHeight(height),math.max(1,math.floor((height-4)/4)))
        local nav=api.ui.secondaryHeight
        local bottom=height-depth-nav
        local rowH=width>=32 and 1 or 2
        if #list>0 then rowH=math.min(math.max(rowH,depth),math.max(rowH,math.floor((bottom-2)/#list))) end
        local slots=math.max(1,math.floor((bottom-2)/rowH))
        local first=page(screen,#list,slots,bottom)
        for i=1,slots do
            local index=first+i
            local row=list[screen=="timers" and (#list-index+1) or index]
            if row then
                local y=2+(i-1)*rowH
                local bg=row.alert and 2 or (row.enabled==true or row.status=="running") and accent or 128
                local label=screen=="alarms" and alarmTime(row.minute).." "..(row.enabled and "ON" or "OFF")
                    or (row.status=="done" and "Done" or row.status=="cancelled" and "Cancelled" or duration(math.ceil(row.remaining))..(row.status=="paused" and " ||" or ""))
                ui.style(1,y,width,rowH,api.ui.contrast(bg),bg)
                local stripe=i%2==0 and 1 or 0
                if width>=32 then
                    local span=math.min(width-stripe-2,#label)
                    local title=row.name:sub(1,width-stripe-span-1)
                    local middle=y+math.floor((rowH-1)/2)
                    ui.lines[middle]=title..string.rep(" ",width-stripe-span-#title)..label:sub(1,span)..string.rep(" ",stripe)
                else ui.text(y,row.name:sub(1,width-stripe)); ui.text(y+1,label:sub(1,width-stripe),true) end
                if stripe>0 then
                    -- Keep the state color and give same-state rows a distinct edge.
                    ui.style(width,y,1,rowH,nil,api.ui.contrast(bg))
                end
                ui.hits[#ui.hits+1]={x1=1,x2=width,y1=y,y2=y+rowH-1,action="open",value={kind=screen=="alarms" and "alarm" or "timer",id=row.id}}
            end
        end
        if #list==0 then ui.text(2,screen=="alarms" and "No alarms" or "No timers",true) end
        button(bottom+1,screen=="alarms" and "+ Add alarm" or "+ Add timer","new",screen=="alarms" and "alarm" or "timer",nil,nil,#list<64,accent,depth)
        footer({{"Back","home"}},nav)
    elseif screen=="detail" then
        local rows={}
        if kind=="alarm" then
            rows={{"Time: "..alarmTime(item.minute),"noop",nil,false},{item.enabled and "Enabled / disable" or "Disabled / enable","toggle"},
                {item.daily and "Repeats daily" or "One time","noop",nil,false}}
        else
            rows={{duration(math.ceil(item.remaining)).." / "..(item.mode=="real" and "Real" or "Game"),"noop",nil,false},
                {"Status: "..item.status,"noop",nil,false},
                {item.status=="running" and "Pause" or item.status=="paused" and "Resume" or "Restart","timerToggle"}}
            if item.status=="running" or item.status=="paused" then rows[#rows+1]={"Cancel timer","cancelTimer"} end
        end
        if item.alert then rows[#rows+1]={"Dismiss / OK","stopSignal",nil,true,16384} end
        rows[#rows+1]={"Output / signal details","routeInfo"}
        rows[#rows+1]={"Edit","edit",nil,not item.alert and (kind=="alarm" or item.status~="running")}
        rows[#rows+1]={"Delete","delete"}
        menu(item.name,rows,"detail:"..item.id,height-1,{{"Back",kind=="alarm" and "alarms" or "timers"}})
    elseif screen=="edit" then
        local draft=view.draft
        local rows={{"Name: "..draft.name,"name"}}
        if draft.kind=="alarm" then
            rows[#rows+1]={"Time: "..alarmTime(draft.minute),"field","minute"}
            rows[#rows+1]={draft.daily and "Repeat: Daily" or "Repeat: Once","draftDaily"}
            rows[#rows+1]={draft.enabled and "Enabled: Yes" or "Enabled: No","draftEnabled"}
        else
            rows[#rows+1]={"Time: "..duration(draft.duration),"field","duration"}
            rows[#rows+1]={"Clock: "..(draft.mode=="real" and "Real time" or "Game time"),"draftMode"}
        end
        rows[#rows+1]={draft.route and "Output: "..draft.route.clientId or "Select output","route"}
        if draft.route then rows[#rows+1]={"Disconnect output","disconnect"} end
        rows[#rows+1]={draft.dismissInput and "Dismiss: "..draft.dismissInput.clientId or "Select dismiss input","dismissInput"}
        if draft.dismissInput then rows[#rows+1]={"Clear dismiss input","clearDismissInput"} end
        rows[#rows+1]={draft.signal.kind=="constant" and "Signal: Constant" or "Signal: Pattern","draftSignal"}
        rows[#rows+1]={draft.signal.kind=="constant" and ("Length: "..(draft.signal.on==0 and "Until OK" or duration(draft.signal.on))) or "ON: "..duration(draft.signal.on),"field","on"}
        if draft.signal.kind=="pattern" then
            rows[#rows+1]={"OFF: "..duration(draft.signal.off),"field","off"}
            rows[#rows+1]={"Total: "..(draft.signal.total==0 and "Until OK" or duration(draft.signal.total)),"field","total"}
        end
        menu(draft.kind=="alarm" and "Alarm settings" or "Timer settings",rows,"edit",height-1,
            {{draft.id and "Save" or draft.kind=="timer" and "Start" or "Save","saveDraft"},{"Cancel","cancelDraft"}})
    elseif screen=="keyboard" then
        local keyboard = view.keyboard
        api.ui.keyboard(ui, width, height, keyboard, accent,
            {{"Set","saveName"},{"Clr","clearName"},{"Back","edit"}})
    elseif screen=="routeInfo" then
        local output=item.route
        local lines={output and (output.clientId.." / "..output.side.." / "..(output.color and api.ui.colourName(output.color) or "Digital")) or "No output selected",
            "Mode: "..(item.signal.kind=="constant" and "Constant" or "Pattern"),
            item.signal.kind=="constant" and (signalLength(item)==0 and "Length: Until dismissed" or "Length: "..item.signal.on.." real seconds") or "ON: "..item.signal.on.." real seconds"}
        if item.signal.kind=="pattern" then lines[#lines+1]="OFF: "..item.signal.off.." real seconds"; lines[#lines+1]=item.signal.total==0 and "Total: Until dismissed" or "Total: "..item.signal.total.." real seconds" end
        if output then
            local found
            for _,entry in ipairs(api.getOutputs()) do if entry.name==outputName(item,kind) then found=entry end end
            lines[#lines+1]="Desired wire: "..(found and found.value and "ON" or "OFF")
            lines[#lines+1]="Client: "..(found and found.online and "Online" or "Offline")
            lines[#lines+1]="Acknowledged: "..(found and found.confirmed and "Yes" or "Pending")
        end
        if item.dismissInput then
            local input=item.dismissInput
            lines[#lines+1]="Dismiss: "..input.clientId.." / "..input.side.." / "..(input.color and api.ui.colourName(input.color) or "Digital")
        else lines[#lines+1]="Dismiss input: Not selected" end
        lines[#lines+1]=item.alert and "Popup: Awaiting OK / input" or "Popup: None"
        lines[#lines+1]=item.ring and "Signal active: "..duration(item.ring.elapsed).." elapsed" or "No active signal"
        info("Output signal",lines,"routeInfo","detail")
    elseif screen=="stopwatch" then
        local sw=state.stopwatch
        ui.heading("Stopwatch / "..(sw.mode=="real" and "Real" or "Game"),accent)
        local label=stopwatchTime(sw.elapsed,sw.mode,width>=12)
        local depth=math.min(api.ui.controlHeight(height),math.max(1,math.floor((height-5)/3)))
        local nav=api.ui.secondaryHeight
        local bottom=height-depth-nav
        local readout=width>=50 and height>=19 and ui.readout(2,label,math.floor((bottom-3)*.6),api.ui.contrast(accent),accent) or 0
        if readout==0 then ui.text(2,label,true); ui.style(1,2,width,1,api.ui.contrast(accent),accent) end
        local status=2+math.max(1,readout)
        if height>=8 then
            ui.text(status,sw.running and (sw.mode=="game" and clockStatus~="World clock ready" and "Waiting for world clock" or "Running") or "Stopped",true)
        end
        local start=status+(height>=8 and 1 or 0)
        local available=bottom-start+1
        local slots=math.max(1,#sw.laps<=available and available or available-1)
        local first=page("laps",#sw.laps,slots,bottom)
        for i=1,slots do
            local lap=sw.laps[#sw.laps-first-i+1]
            if lap then
                local y=start+i-1
                ui.text(y,"#"..lap.number.." "..stopwatchTime(lap.split,sw.mode,width>=18)..(width>=36 and " / "..stopwatchTime(lap.elapsed,sw.mode,true) or ""))
                if i%2==0 then ui.style(1,y,width,1,1,128) end
            end
        end
        local controls={{sw.running and "Stop" or "Start","stopwatchToggle"},{"Lap","lap"},{"Reset","resetStopwatch"}}
        for i,row in ipairs(controls) do
            button(bottom+1,row[1],row[2],nil,1+math.floor((i-1)*width/3),math.floor(i*width/3),row[2]~="lap" or sw.running,i==1 and accent or 128,depth)
        end
        footer({{"Back","home"},{sw.mode=="real" and "Real" or "Game","stopwatchMode",nil,not sw.running and sw.elapsed==0}},nav)
    elseif screen=="delete" then
        ui.heading("Delete "..kind.."?",accent); ui.text(2,item.name,true)
        button(height-1,"Delete","confirmDelete",nil,nil,nil,true,16384); footer({{"Cancel","detail"}})
    elseif screen=="settings" then
        menu("Clock settings",{{"UI color","accent"},{"Timer history: "..state.settings.history,"history"},{"Clock status","status"},{"About / restart rules","about"}},"settings",height-1)
    elseif screen=="status" then
        info("Clock status",{clockStatus,lastError or "No pending errors","World: "..api.getSystem().gameTime,
            "Background service: active even with no windows. Outputs use the shared IO cooldown. Offline signals are not replayed after their time has expired."},"status","home")
    elseif screen=="about" or screen=="message" then
        info("Clock information",{screen=="message" and view.message or
            "Alarms use world HH:MM and repeat daily or once. Timers and stopwatch choose real computer uptime or sampled game-clock seconds. Every trigger shows an OK popup on all monitors. OK or a fresh selected input press dismisses it everywhere. Constant length 0 or Pattern total 0 runs until dismissed. Pattern ON/OFF use real seconds, at least 1 each. Saves resume countdowns, stopwatch, laps and active patterns from the last checkpoint; no time is counted while the OS is off. Missed alarms during downtime are skipped. Large time-set/sleep jumps rebase without catch-up, and an alarm fires at most once per observed world day. Missing world time pauses game clocks only. Shared output routes are allowed; overlapping Clock signals on one wire are combined. Unrelated apps still share that physical wire. Close stops only this window."},"info",screen=="message" and "messageBack" or "settings")
    end
    return ui.finish()
end
function app.render(w,h,state,api,context)
    if not ready then return {"Clock unavailable","Check OS console"} end
    syncStopwatch(state)
    return (build(w,h,state,api,context))
end
local function saveDraft(state,api,view)
    local draft=view.draft
    if not validName(draft.name) or not signal(draft.signal) or (draft.route and not route(draft.route))
        or (draft.dismissInput and not route(draft.dismissInput)) then notice(view,"Invalid settings","edit"); return end
    local list=draft.kind=="alarm" and state.alarms or state.timers
    local item=find(list,draft.id)
    if draft.id and (not item or item.revision~=draft.revision or item.alert or draft.kind=="timer" and item.status=="running") then
        notice(view,"Entry changed or is running; reopen settings","detail"); return
    end
    if not item and #list>=64 then notice(view,"Maximum 64 entries; delete old timers/alarms first","edit"); return end
    local created=item or {id=state.nextId,revision=0}
    local changes={}
    if draft.route then changes[1]={name=outputName(created,draft.kind),clientId=draft.route.clientId,side=draft.route.side,color=draft.route.color,initialValue=false}
    elseif item and item.route then changes[1]={name=outputName(created,draft.kind),remove=true} end
    local ok=commit(state,api,function()
        if not item then list[#list+1]=created; state.nextId=state.nextId+1 end
        created.name,created.route,created.signal,created.revision=draft.name,copy(draft.route),copy(draft.signal),created.revision+1
        created.dismissInput=copy(draft.dismissInput)
        if draft.kind=="alarm" then
            if created.minute~=draft.minute then created.lastDay=nil end
            created.minute,created.enabled,created.daily=draft.minute,draft.enabled,draft.daily
        else
            if not item or created.duration~=draft.duration or created.mode~=draft.mode then created.remaining=draft.duration end
            created.duration,created.mode=draft.duration,draft.mode
            created.status=item and "paused" or "running"
        end
    end,changes,view)
    if ok then view.id,view.kind,view.screen,view.pages,view.draft=created.id,draft.kind,"detail",{},nil end
end
function app.handleNotification(key,state,api)
    local selected
    each(state,function(item,kind) if item.alert and alertKey(item,kind)==key then selected=item end end)
    if not selected then return publish(state,api) end
    local touched={}
    if selected.route and selected.ring then touched[wire(selected.route)]=true end
    return commit(state,api,function()
        selected.ring,selected.alert,selected.revision=nil,nil,selected.revision+1
    end,function() return wireChanges(state,touched,api) end)
end
function app.handleTouch(x,y,w,h,state,api,context)
    if not ready then return false end
    syncStopwatch(state)
    local hits = context.hits
    if not hits then local _; _, hits = build(w,h, state, api, context) end
    local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view; local kind=view.kind or "alarm"
    local list=kind=="alarm" and state.alarms or state.timers
    local item,index=find(list,view.id)
    if action=="page" then view.pages[value.key]=value.page
    elseif action=="open" then view.id,view.kind,view.screen,view.pages=value.id,value.kind,"detail",{}
    elseif action=="new" then view.draft,view.screen,view.pages=draftFor(nil,value),"edit",{}
    elseif action=="edit" and item then view.draft,view.screen,view.pages=draftFor(item,kind),"edit",{}
    elseif action=="cancelDraft" then view.screen=view.draft.id and "detail" or view.draft.kind=="alarm" and "alarms" or "timers"; view.draft=nil
    elseif action=="saveDraft" then saveDraft(state,api,view)
    elseif action=="draftMode" then view.draft.mode=view.draft.mode=="real" and "game" or "real"
    elseif action=="draftDaily" then view.draft.daily=not view.draft.daily
    elseif action=="draftEnabled" then view.draft.enabled=not view.draft.enabled
    elseif action=="draftSignal" then view.draft.signal.kind=view.draft.signal.kind=="constant" and "pattern" or "constant"
        if view.draft.signal.kind=="pattern" and view.draft.signal.on==0 then view.draft.signal.on=1 end
    elseif action=="route" then local ok,err=api.pickIO(context.windowId,"signal","output",view.draft.route); if not ok then notice(view,err,"edit") end
    elseif action=="disconnect" then view.draft.route=nil
    elseif action=="dismissInput" then local ok,err=api.pickIO(context.windowId,"dismiss","input",view.draft.dismissInput); if not ok then notice(view,err,"edit") end
    elseif action=="clearDismissInput" then view.draft.dismissInput=nil
    elseif action=="field" then
        local val=value=="minute" and two(math.floor(view.draft.minute/60))..two(view.draft.minute%60) or view.draft[value] or view.draft.signal[value]
        view.number={key=value,draft=tostring(val)}; view.screen="number"
    elseif action=="digit" then
        local field=view.number
        if value=="Clr" then field.draft="" elseif value=="Del" then field.draft=field.draft:sub(1,-2)
        elseif #field.draft<8 then field.draft=field.draft..value end
    elseif action=="setNumber" then
        local field=view.number; local val=tonumber(field.draft)
        local allowZero=field.key=="minute" or field.key=="total" or field.key=="on" and view.draft.signal.kind=="constant"
        local valid=integer(val,allowZero and 0 or 1,(field.key=="on" or field.key=="off") and 86400 or MAX_DURATION)
        if field.key=="minute" then valid=val and integer(val,0,2359) and val%100<60; if valid then val=math.floor(val/100)*60+val%100 end end
        if not valid then notice(view,field.key=="minute" and "Use HHMM, 0000-2359" or (allowZero and "Use whole seconds; 0 = until OK" or "Use whole seconds, at least 1"),"number")
        else if field.key=="on" or field.key=="off" or field.key=="total" then view.draft.signal[field.key]=val else view.draft[field.key]=val end; view.screen="edit" end
    elseif action=="name" then view.keyboard={draft=view.draft.name,bank=0,page=1}; view.screen="keyboard"
    elseif view.screen == "keyboard" and api.ui.editText(view.keyboard, action, value, 24) then return true
    elseif action == "clearName" then view.keyboard.draft = ""
    elseif action=="saveName" then
        local name=view.keyboard.draft:gsub("^%s+",""):gsub("%s+$","")
        if validName(name) then view.draft.name,view.screen=name,"edit" end
    elseif action=="toggle" and item then commit(state,api,function() item.enabled=not item.enabled; item.revision=item.revision+1 end,{},view)
    elseif action=="timerToggle" and item then
        local changes=offChanges(state,item,kind)
        commit(state,api,function()
            if item.status=="running" then item.status="paused"
            elseif item.status=="paused" then item.status="running"
            else item.remaining,item.status=item.duration,"running" end
            item.ring,item.alert=nil,nil; item.revision=item.revision+1
        end,changes,view)
    elseif (action=="cancelTimer" or action=="stopSignal") and item then
        local changes=offChanges(state,item,kind)
        commit(state,api,function() item.ring,item.alert=nil,nil; if action=="cancelTimer" then item.status="cancelled" end; item.revision=item.revision+1 end,changes,view)
    elseif action=="confirmDelete" and item then
        local changes=offChanges(state,item,kind)
        -- One explicit value for a surviving Clock reference when another signal
        -- still owns this wire; then release only the deleted reference.
        if item.route then
            if #changes>0 then
                local other
                each(state,function(candidate,candidateKind) if candidate~=item and candidate.route and wire(candidate.route)==wire(item.route) then other={name=outputName(candidate,candidateKind),value=changes[1].value} end end)
                if not other then
                    for _,output in ipairs(api.getOutputs()) do
                        if output.name~=outputName(item,kind) and wire(output)==wire(item.route) then other={name=output.name,value=changes[1].value}; break end
                    end
                end
                changes=other and {other} or {}
            end
            changes[#changes+1]={name=outputName(item,kind),remove=true}
        end
        if commit(state,api,function() table.remove(list,index) end,changes,view) then view.screen=kind=="alarm" and "alarms" or "timers" end
    elseif action=="stopwatchToggle" then
        if commit(state,api,function() state.stopwatch.running=not state.stopwatch.running end,{},view) then rebaseStopwatch(state) end
    elseif action=="lap" then
        commit(state,api,function()
            local sw=state.stopwatch; local previous=sw.laps[#sw.laps]
            sw.lapCounter=sw.lapCounter+1
            sw.laps[#sw.laps+1]={number=sw.lapCounter,elapsed=sw.elapsed,split=sw.elapsed-(previous and previous.elapsed or 0)}
            if #sw.laps>50 then table.remove(sw.laps,1) end
        end,{},view)
    elseif action=="resetStopwatch" then if commit(state,api,function()
        local sw=state.stopwatch; sw.elapsed,sw.running,sw.laps,sw.lapCounter=0,false,{},0
    end,{},view) then rebaseStopwatch(state) end; view.pages.laps=1
    elseif action=="stopwatchMode" then
        if commit(state,api,function() state.stopwatch.mode=state.stopwatch.mode=="real" and "game" or "real" end,{},view) then rebaseStopwatch(state) end
    elseif action=="history" then
        local changes={}; local retained={}
        local old=copy(state)
        state.settings.history=state.settings.history==10 and 20 or state.settings.history==20 and 50 or 10; trim(state)
        each(state,function(entry,k) retained[outputName(entry,k)]=true end)
        each(old,function(entry,k) if entry.route and not retained[outputName(entry,k)] then changes[#changes+1]={name=outputName(entry,k),remove=true} end end)
        local ok,err=api.updateOutputs(changes); if not ok then restore(state,old); notice(view,tostring(err),"settings") else assert(publish(state,api)); api.invalidateAppViews(appName) end
    elseif action=="accent" then local ok,err=api.pickColour(context.windowId); if not ok then notice(view,err) end
    elseif action=="messageBack" then view.screen=view.back or "home"
    elseif action~="noop" then view.screen=action end
    return true
end
return app
