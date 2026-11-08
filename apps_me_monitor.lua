-- Optional AE1 item monitors. Saved views are independent of ME capacity apps.
local app = {title="ME monitors",minWidth=12,minHeight=6,preferredWidth=50,preferredHeight=18}
local Me = dofile("lib_me.lua")
local appName,ready,elapsed="me_monitor",false,0
local sources,pickers={},{}
local MAX_VIEWS,MAX_AXIS=64,16
local CHANGE_WINDOW = 300
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function restore(state,old)
    local keys={}; for key in pairs(state) do keys[#keys+1]=key end
    for _,key in ipairs(keys) do state[key]=nil end
    for key,value in pairs(old) do state[key]=value end
end
local function integer(value,low,high)
    return type(value)=="number" and value==math.floor(value) and value>=low and value<=high
end
local function colour(value)
    for i=0,15 do if value==2^i then return true end end
    return false
end
local function decimal(value)
    local digits={}
    repeat
        local digit=value%10; digits[#digits+1]=("0123456789"):sub(digit+1,digit+1)
        value=math.floor(value/10)
    until value==0
    return table.concat(digits):reverse()
end
local function amount(value,width)
    if value==nil then return "--" end
    local raw=decimal(value)
    local spaced=raw:reverse():gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
    return width and #spaced>width and raw or spaced
end
local function safeName(value)
    return type(value)=="string" and #value>0 and #value<=256 and not value:find("[%c]")
end
local function address(value)
    return type(value)=="table" and safeName(value.clientId) and #value.clientId<=64
        and ({top=true,bottom=true,left=true,right=true,front=true,back=true})[value.side]
        and safeName(value.target) and #value.target<=128
end
local function sourceKey(value)
    return #value.clientId..":"..value.clientId..value.side..":"..value.target
end
local function itemKey(raw,damage,name)
    local identity=raw~="" and raw~="unknown" and raw or "name:"..name
    return #identity..":"..identity..":"..decimal(damage)
end
local function find(list,id)
    for index,item in ipairs(list or {}) do if item.id==id then return item,index end end
end
local function gridShape(count)
    local bestC,bestR,bestScore=1,1,math.huge
    for c=1,MAX_AXIS do
        local r=math.ceil(count/c)
        if r<=MAX_AXIS then
            local score=(c*r-count)*100+math.abs(c-r)+(c<r and 0.1 or 0)
            if score<bestScore then bestC,bestR,bestScore=c,r,score end
        end
    end
    return bestC,bestR
end
local function watch(board) return appName.."_view_"..board.id end
local function catalog(reading,api)
    local data=reading.data or {}
    if reading.status~="ok" then return nil,reading.error or reading.status end
    if data.Powered==false then return nil,"ME unpowered" end
    if data.ItemsOmitted or data.ItemsComplete==false then return nil,"Waiting for complete item list" end
    if type(data.Items)~="table" then return nil,"No AE item list" end
    if data.ItemsFormat and data.ItemsFormat~="ae_compact_v1" then return nil,"Unknown item format" end
    local compact=data.ItemsFormat=="ae_compact_v1"
    local result,seen={},0
    for _,row in pairs(data.Items) do
        if api.cooperate then api.cooperate(64) end
        seen=seen+1
        if seen>8192 or type(row)~="table" then return nil,"Invalid item list" end
        local raw,name,damage,count
        if compact then raw,damage,name,count=row[1],row[2],row[3],row[4]
        else raw,name,damage,count=row.RawName or "",row.Name or row.RawName,row.DamageValue or row.Damagevalue or 0,row.Size end
        if type(raw)~="string" or #raw>256 or raw:find("[%c]") or type(name)~="string" or #name>256
            or not integer(damage,0,2147483647) or not integer(count,0,9007199254740991) then return nil,"Invalid item identity/count" end
        name=name:gsub("[%c]"," "); if name=="" then name=raw~="" and raw or "Unknown item" end
        local key=itemKey(raw,damage,name)
        local item=result[key]
        if not item then item={key=key,raw=raw,damage=damage,name=name,count=0,variants=0}; result[key]=item end
        if not integer(item.count+count,0,9007199254740991) then return nil,"Item count overflow" end
        item.count,item.variants=item.count+count,item.variants+1
        if name:lower()<item.name:lower() then item.name=name end
    end
    local names={}
    for _,item in pairs(result) do names[item.name]=(names[item.name] or 0)+1 end
    for _,item in pairs(result) do item.label=item.name..(names[item.name]>1 and " ["..decimal(item.damage).."]" or "") end
    return result
end
local function source(board)
    return sources[sourceKey(board.sensor)] or {status="waiting",error="Waiting for sensor",items={}}
end
local function countFor(board,tile)
    if not tile.item then return nil end
    local value=source(board)
    if value.status~="ok" then return nil end
    local item=value.items[tile.item.key]
    return item and item.count or 0
end
local function recordChanges(cached,reading,enabled,api)
    if not enabled or cached.status~="ok" or not Me.number(reading.time,0,Me.MAX)
        or not integer(reading.sequence,0,Me.MAX) then
        cached.sample,cached.history=nil,nil
        return
    end
    local previous=cached.sample
    if previous and previous.sequence==reading.sequence and previous.time==reading.time then return end
    local seconds=previous and reading.time-previous.time
    local maxInterval=reading.maxAge or 10
    if Me.number(seconds,0.001,maxInterval) then
        local changes={}
        if previous.items~=cached.items then
            for key,item in pairs(previous.items) do
                local current=cached.items[key]
                local delta=(current and current.count or 0)-item.count
                if delta~=0 then changes[key]={delta=delta} end
                if api.cooperate then api.cooperate(32) end
            end
            for key,item in pairs(cached.items) do
                if not previous.items[key] and item.count~=0 then changes[key]={delta=item.count} end
                if api.cooperate then api.cooperate(32) end
            end
        end
        cached.history=cached.history or Me.Rates.new()
        Me.Rates.record(cached.history,reading.time,seconds,changes,maxInterval)
    else cached.history=nil end
    cached.sample={time=reading.time,sequence=reading.sequence,items=cached.items}
end
local function changeFor(board,tile)
    local current=source(board)
    if not tile.item or current.status~="ok" or not current.history then return end
    local delta,seconds=Me.Rates.sum(current.history,tile.item.key,current.sample.time,CHANGE_WINDOW)
    if seconds>0 then return delta,delta/seconds*3600 end
end
local function signedAmount(delta)
    return (delta and delta>0 and "+" or "")..Me.amount(delta)
end
local function changeLabel(board,tile,width)
    local delta,rate=changeFor(board,tile)
    local hourly=Me.rateText(rate,width)
    if #hourly>width then return "Rate >" end
    local combined="5m "..signedAmount(delta).."  "..hourly
    return delta and #combined<=width and combined or hourly
end
local function notice(view,text,back)
    view.message,view.messageBack,view.screen=tostring(text),back or view.screen or "home","message"
    view.pages=view.pages or {}; view.pages.message=nil
end
local function commit(state,api,view,change)
    local old=copy(state); change()
    local ok,err=api.save()
    if not ok then restore(state,old); notice(view,"Save failed: "..tostring(err)); return false,err end
    api.invalidateAppViews(appName)
    return true
end
local function newTile(state)
    local tile={id=state.nextTileId}; state.nextTileId=state.nextTileId+1; return tile
end
function app.init(state,api,context)
    assert(api.ui and api.ui.typeKey and api.ui.breadcrumb,"me_monitor requires bundled-v33 OS; run inst server")
    ready=false; sources,pickers,elapsed={},{},0
    assert(api.aeItemProfiles and api.pickSensor and api.watchSensor,"ME monitors requires bundled-v22 OS")
    appName=context and context.appName or "me_monitor"
    if state.version==nil then
        state.version,state.boards,state.nextBoardId,state.nextTileId=1,{},1,1
        state.settings={density="roomy"}
    end
    assert(state.version==1 and type(state.boards)=="table" and #state.boards<=MAX_VIEWS
        and type(state.settings)=="table" and (state.settings.density=="roomy" or state.settings.density=="compact"),"Invalid saved ME monitors")
    local boards,tiles,maxBoard,maxTile={},{},0,0
    for _,board in ipairs(state.boards) do
        assert(type(board)=="table" and integer(board.id,1,2147483000) and not boards[board.id]
            and safeName(board.name) and #board.name<=24 and address(board.sensor)
            and (board.layout==nil or board.layout=="grid" or board.layout=="list")
            and (board.showRates==nil or type(board.showRates)=="boolean")
            and integer(board.columns,1,MAX_AXIS) and integer(board.rows,1,board.layout=="list" and MAX_AXIS^2 or MAX_AXIS)
            and (board.layout~="list" or board.columns==1)
            and type(board.tiles)=="table" and #board.tiles==board.columns*board.rows,"Invalid saved monitor view")
        boards[board.id],maxBoard=true,math.max(maxBoard,board.id)
        for _,tile in ipairs(board.tiles) do
            assert(type(tile)=="table" and integer(tile.id,1,2147483000) and not tiles[tile.id]
                and (tile.displayColour==nil or colour(tile.displayColour)),"Invalid saved monitor tile")
            if tile.item then
                local item=tile.item
                assert(type(item)=="table" and type(item.raw)=="string" and #item.raw<=256 and safeName(item.name)
                    and integer(item.damage,0,2147483647) and item.key==itemKey(item.raw,item.damage,item.name),"Invalid saved item binding")
            end
            tiles[tile.id],maxTile=true,math.max(maxTile,tile.id)
        end
    end
    assert(integer(state.nextBoardId,maxBoard+1,2147483001) and integer(state.nextTileId,maxTile+1,2147483001),"Invalid saved monitor IDs")
    ready=true
end
function app.background(dt,state,api)
    if not ready then return end
    local wanted,measure={},{}
    for _,board in ipairs(state.boards) do
        api.watchSensor(watch(board),board.sensor,{profile="ae_items"})
        local key=sourceKey(board.sensor)
        wanted[key]=board
        if board.showRates~=false then measure[key]=true end
    end
    elapsed=elapsed+(dt or 0)
    if elapsed<0.5 then return end
    elapsed=0
    local remove={}; for key in pairs(sources) do if not wanted[key] then remove[#remove+1]=key end end
    for _,key in ipairs(remove) do sources[key]=nil end
    local boots=Me.boots(api)
    for key,board in pairs(wanted) do
        local reading=api.getSensorReading(board.sensor,{profile="ae_items"})
        local cached=sources[key]
        local boot=boots[board.sensor.clientId]
        if not cached or cached.boot~=boot or cached.card~=reading.card then
            cached={items={},boot=boot,card=reading.card}
        end
        sources[key]=cached
        cached.age=reading.age
        if reading.status~="ok" then cached.status,cached.error=reading.status,reading.error or reading.status
        elseif reading.data and reading.data.Powered==false then cached.status,cached.error="unpowered","ME unpowered"
        elseif cached.sequence~=reading.dataSequence or cached.status~="ok" then
            local items,err=catalog(reading,api)
            cached.status,cached.error=items and "ok" or "unsupported",err
            if items then cached.items,cached.sequence=items,reading.dataSequence end
        end
        recordChanges(cached,reading,measure[key],api)
    end
end
function app.shutdown(state,api)
    for _,board in ipairs(state.boards) do api.unwatchSensor(watch(board)) end
    sources,pickers={},{}
end
function app.handleSensorSelection(key,selected,state,api,context)
    if not address(selected) then return false,"Invalid sensor selection" end
    local view=context.view
    if key=="new" then
        if #state.boards>=MAX_VIEWS then return false,"Maximum 64 views" end
        view.gridDraft={target="new",layout="grid",columns=4,rows=4,count=16,sensor=copy(selected)}
        view.screen="grid"; return true
    end
    local board=find(state.boards,tonumber(key:match("^source_(%d+)$")))
    if not board then return false,"View was removed" end
    local ok,err=commit(state,api,view,function() board.sensor=copy(selected) end)
    if not ok then return false,err end
    api.watchSensor(watch(board),board.sensor,{profile="ae_items"})
    pickers[context.windowId]=nil; view.screen="edit"
    return true
end
local function picker(view,board,tile,windowId)
    local cached=pickers[windowId]
    local identity=sourceKey(board.sensor)..":"..tile.id..":"..(view.sort or "name")..":"..tostring(view.descending==true)..":"..(view.query or "")
    if cached and cached.identity==identity then return cached end
    local data=source(board)
    if data.status~="ok" then return {rows={},waiting=true} end
    cached={identity=identity,rows={}}
    local query=(view.query or ""):lower()
    for _,item in pairs(data.items) do
        if query=="" or item.name:lower():find(query,1,true) or item.raw:lower():find(query,1,true) then cached.rows[#cached.rows+1]=copy(item) end
    end
    table.sort(cached.rows,function(a,b)
        if view.sort=="amount" and a.count~=b.count then return view.descending and a.count>b.count or not view.descending and a.count<b.count end
        local left,right=a.name:lower(),b.name:lower()
        if left~=right then return view.descending and left>right or not view.descending and left<right end
        return a.key<b.key
    end)
    -- Rows remain in this order until Sort/Search/Refresh, while counts update.
    pickers[windowId]=cached
    return cached
end
local function build(width,height,state,api,context)
    local view=context.view
    view.pages=view.pages or {}
    local board=find(state.boards,view.boardId)
    local screen=view.screen or "home"
    local global={home=true,settings=true,about=true,message=true}
    if screen=="grid" and view.gridDraft and view.gridDraft.target=="new" then global.grid=true end
    if screen=="keyboard" and view.keyboard and view.keyboard.kind=="search" then global.keyboard=board~=nil end
    if not global[screen] and not board then screen,view.screen="home","home" end
    local tile=board and find(board.tiles,view.tileId)
    if (screen=="item" or screen=="picker" or screen=="colour") and not tile then screen,view.screen="board","board" end
    if screen=="keyboard" and view.keyboard and view.keyboard.kind=="search" and not tile then screen,view.screen="board","board" end
    local ui=api.ui.content(width,height)
    local accent=api.getAppColour(context.appName or appName)
    ui.style(1,1,width,height,1,32768)
    local function text(x,y,value,span,center)
        value=tostring(value):gsub("[%c]"," "):sub(1,span)
        if center then x=x+math.max(0,math.floor((span-#value)/2)) end
        ui.lines[y]=ui.lines[y]:sub(1,x-1)..value..ui.lines[y]:sub(x+#value)
    end
    local function button(y,label,action,value,x1,x2,enabled,bg)
        ui.button(y,label,action,x1,x2,enabled,bg or 128,nil,value)
    end
    local function footer(items)
        for i,item in ipairs(items) do button(height,item[1],item[2],item[3],1+math.floor((i-1)*width/#items),math.floor(i*width/#items),item[4],item[5] or (#items>1 and i%2==0 and 256 or 128)) end
    end
    local function page(key,count,slots,row)
        view.pages=view.pages or {}
        local pages=math.max(1,math.ceil(count/slots))
        local current=math.max(1,math.min(view.pages[key] and view.pages[key].page or 1,pages))
        view.pages[key]={page=current,pages=pages}
        if pages>1 then
            local wing=math.max(2,math.floor(width/4))
            button(row,"<","page",{key=key,delta=-1},1,wing,current>1)
            button(row,">","page",{key=key,delta=1},width-wing+1,width,current<pages)
            local label=current.."/"..pages
            if #label>width-2*wing then label=decimal(current) end
            text(wing+1,row,label,width-2*wing,true)
        end
        return (current-1)*slots
    end
    local function menu(title,items,key,back)
        ui.heading(title,accent)
        local slots=#items<=height-2 and height-2 or height-3
        local first=page(key,#items,slots,height-1)
        for i=1,slots do local item=items[first+i]; if item then button(i+1,item[1],item[2],item[3],nil,nil,item[4],item[5]) end end
        footer({{"Back",back}})
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
    local function grid(count,wantedColumns,wantedRows,key,bottom,minWidth,minHeight,draw)
        local gap=state.settings.density=="roomy" and width>=20 and height>=10 and 1 or 0
        local cols=math.min(wantedColumns,math.max(1,math.floor((width+gap)/(minWidth+gap))))
        local function rows(last) return math.min(wantedRows,math.max(1,math.floor((last-1+gap)/(minHeight+gap)))) end
        local nrows=rows(bottom)
        if count>cols*nrows then bottom=bottom-1; nrows=rows(bottom) end
        local slots=cols*nrows
        local first=page(key,count,slots,bottom+1)
        for slot=1,slots do
            local item=first+slot
            if item<=count then
                local col,row=(slot-1)%cols,math.floor((slot-1)/cols)
                local x1=1+math.floor(col*(width+gap)/cols)
                local x2=math.floor((col+1)*(width+gap)/cols)-gap
                local y1=2+math.floor(row*(bottom-1+gap)/nrows)
                local y2=1+math.floor((row+1)*(bottom-1+gap)/nrows)-gap
                draw(item,{x=x1,y=y1,w=x2-x1+1,h=y2-y1+1})
            end
        end
    end
    local function monitorTile(rect,title,quantity,action,value,status,bg,change)
        bg=bg or 128
        local fg=api.ui.contrast(bg)
        -- The window frame already supplies its border; tiles fill their cells.
        local x,y,w,h=rect.x,rect.y,rect.w,rect.h
        ui.style(x,y,w,h,fg,bg)
        local valueText=quantity or ""
        local quantityRows=math.min(h-1,math.max(1,math.ceil(#valueText/w)))
        local showChange=change and h>=quantityRows+2
        local available=h-(showChange and 1 or 0)
        local nameRows=math.max(1,math.min(2,available-quantityRows))
        for row=1,nameRows do text(x,y+row-1,title:sub((row-1)*w+1,row*w),w,true) end
        local firstRow=y+math.max(nameRows,available-quantityRows)
        for row=1,quantityRows do
            text(x,firstRow+row-1,valueText:sub((row-1)*w+1,row*w),w,true)
        end
        if showChange then text(x,y+h-1,change,w,true) end
        ui.hits[#ui.hits+1]={x1=rect.x,x2=rect.x+rect.w-1,y1=rect.y,y2=rect.y+rect.h-1,action=action,value=value}
    end
    if screen=="home" then
        ui.heading("ME monitor views",accent)
        if #state.boards==0 then
            monitorTile({x=1,y=2,w=width,h=height-2},"+ Add view","","add",nil,"ok")
        else
            grid(#state.boards,width>=32 and 2 or 1,MAX_VIEWS,"home",height-2,12,3,function(index,rect)
                local item=state.boards[index]; local assigned=0
                for _,cell in ipairs(item.tiles) do if cell.item then assigned=assigned+1 end end
                monitorTile(rect,item.name,assigned.." / "..#item.tiles,"open",item.id,"ok")
            end)
            button(height-1,"+ Add view","add",nil,nil,nil,#state.boards<MAX_VIEWS,accent)
        end
        footer({{"Settings","settings"}})
    elseif screen=="board" or screen=="tiles" then
        local data=source(board)
        local rates=screen=="board" and board.showRates~=false
        ui.heading(screen=="tiles" and "Choose a tile" or board.name,data.status=="ok" and accent or 2)
        if board.layout=="list" then
            local rowH=width>=(rates and 48 or 28) and 1 or rates and 3 or 2
            local slots=math.max(1,math.floor((height-3)/rowH))
            local first=page("tiles",#board.tiles,slots,height-1)
            for i=1,slots do
                local cell=board.tiles[first+i]
                if cell then
                    local y=2+(i-1)*rowH
                    local bg=cell.displayColour or (i%2==0 and 128 or 32768)
                    ui.style(1,y,width,rowH,api.ui.contrast(bg),bg)
                    local title=cell.item and cell.item.name or "+ Item"
                    local quantity=cell.item and amount(countFor(board,cell),width) or "Select item"
                    if rowH==1 then
                        if rates and cell.item then quantity=quantity.."  "..changeLabel(board,cell,width-#quantity-4) end
                        local n=math.min(#quantity,width-2)
                        text(1,y,title,math.max(1,width-n-1)); text(width-n+1,y,quantity,n)
                    else
                        ui.text(y,title); ui.text(y+1,quantity,true)
                        if rates and cell.item then ui.text(y+2,changeLabel(board,cell,width),true) end
                    end
                    ui.hits[#ui.hits+1]={x1=1,x2=width,y1=y,y2=y+rowH-1,action=screen=="tiles" and "chooseTile" or "tile",value=cell.id}
                end
            end
        else
            grid(#board.tiles,board.columns,board.rows,"tiles",height-1,8,3,function(index,rect)
                local cell=board.tiles[index]
                monitorTile(rect,cell.item and cell.item.name or "+ Item",cell.item and amount(countFor(board,cell),rect.w) or "Select item",
                    screen=="tiles" and "chooseTile" or "tile",cell.id,data.status,cell.displayColour,
                    rates and cell.item and changeLabel(board,cell,rect.w))
            end)
        end
        if screen=="tiles" then footer({{"Back","edit"}}) else footer({{"Back","home"},{"Edit","edit"}}) end
    elseif screen=="picker" then
        local frozen=picker(view,board,tile,context.windowId)
        local data=source(board)
        local title=view.query and view.query~="" and "Find: "..view.query or "Select item"
        ui.heading(data.status=="ok" and title or "Items / "..data.status,data.status=="ok" and accent or 2)
        local path=api.ui.breadcrumb({board.name,board.sensor.clientId,board.sensor.side,board.sensor.target},width,height)
        local sortRow=path and 3 or 2
        if path then ui.text(2,path); ui.style(1,2,width,1,256,32768) end
        local half=math.floor(width/2)
        button(sortRow,view.sort=="amount" and "Amount" or "Name","sort",nil,1,half,true,accent)
        button(sortRow,view.sort=="amount" and (view.descending and "Hi-Low" or "Low-Hi") or (view.descending and "Z-A" or "A-Z"),"direction",nil,half+1,width)
        local rowH=width>=28 and 1 or 2
        local slots=math.max(1,math.floor((height-sortRow-2)/rowH))
        local first=frozen.waiting and 0 or page("items",#frozen.rows,slots,height-1)
        for i=1,slots do
            local item=frozen.rows[first+i]
            if item then
                local y=sortRow+1+(i-1)*rowH
                local current=data.items[item.key]
                local count=data.status=="ok" and (current and current.count or 0) or nil
                local valueText=amount(count,width)
                ui.style(1,y,width,rowH,1,i%2==0 and 128 or 32768)
                if rowH==1 then
                    local countWidth=#valueText
                    text(1,y,item.label or item.name,math.max(1,width-countWidth-1))
                    text(width-countWidth+1,y,valueText,countWidth)
                else ui.text(y,item.label or item.name); ui.text(y+1,valueText,true) end
                ui.hits[#ui.hits+1]={x1=1,x2=width,y1=y,y2=y+rowH-1,action="selectItem",value=item.key}
            end
        end
        if #frozen.rows==0 then ui.text(sortRow+1,frozen.waiting and (data.error or "Waiting for items") or view.query and view.query~="" and "No matches" or "No stored items",true) end
        footer({{width>=18 and "Search" or "Find","search"},{width>=21 and "Refresh" or "Sync","refresh"},{"Back","pickerBack"}})
    elseif screen=="item" then
        local data=source(board)
        local item=tile.item
        if not item then view.screen="picker"; return build(width,height,state,api,context) end
        local live=data.items[item.key]
        local lines={item.name,"Count: "..amount(countFor(board,tile))}
        if board.showRates~=false then
            local delta,rate=changeFor(board,tile)
            lines[#lines+1]="5m net: "..signedAmount(delta)
            lines[#lines+1]="Rate: "..Me.rateText(rate)
        end
        lines[#lines+1]="Status: "..(data.error or data.status)
        for _,line in ipairs({"Raw: "..item.raw,"Damage: "..decimal(item.damage),"Client: "..board.sensor.clientId,
            "Side: "..board.sensor.side,"Target: "..board.sensor.target}) do lines[#lines+1]=line end
        if live and live.variants>1 then lines[#lines+1]="Variants combined: "..live.variants.." (the card does not expose NBT)" end
        -- Details paginate above their own fixed action row.
        local wrapped={}
        for _,line in ipairs(lines) do repeat wrapped[#wrapped+1],line=line:sub(1,width),line:sub(width+1) until line=="" end
        ui.heading("Item monitor",accent)
        local slots=#wrapped<=height-3 and height-3 or height-4
        local first=page("item",#wrapped,slots,height-2)
        for i=1,slots do ui.text(i+1,wrapped[first+i] or "") end
        button(height-1,"Color","tileColour",nil,nil,nil,true,tile.displayColour or 128)
        -- Reserve the colour control even when details span multiple pages.
        footer({{"Item","changeItem"},{"Clear","clearItem"},{"Back","board"}})
    elseif screen=="edit" then
        local ratesLabel=(width>=17 and "Change rates: " or "Rates: ")..(board.showRates==false and "Off" or "On")
        menu("View settings",{{ratesLabel,"toggleRates"},
            {"Rename view","rename"},{"Edit items","tiles"},{"Layout / size","resize"},{"AE source","sensor"},
            {"Source information","source"},{"Delete view","delete"}},"edit","board")
    elseif screen=="settings" then
        menu("Monitor settings",{{"UI color","accent"},{"Density: "..state.settings.density,"density"},{"About","about"}},"settings","home")
    elseif screen=="grid" then
        local draft=view.gridDraft
        ui.heading(draft.target=="new" and "New view layout" or "Layout / size",accent)
        button(2,draft.layout=="list" and "List" or "Grid "..draft.columns.."x"..draft.rows,"layoutToggle",nil,nil,nil,true,accent)
        local third=math.floor(width/3)
        local controls=draft.layout=="list" and {{row=3,key="count",label="Items"}} or {{row=3,key="columns",label="Cols"},{row=4,key="rows",label="Rows"}}
        for _,item in ipairs(controls) do
            local limit=item.key=="count" and MAX_AXIS^2 or MAX_AXIS
            button(item.row,"-","gridStep",{key=item.key,delta=-1},1,third,draft[item.key]>1)
            text(third+1,item.row,item.label.." "..draft[item.key],width-2*third,true)
            button(item.row,"+","gridStep",{key=item.key,delta=1},width-third+1,width,draft[item.key]<limit)
        end
        if draft.layout=="list" then ui.text(4,"Name + amount",true) end
        if height>=10 then
            local previewRows=draft.layout=="list" and draft.count or draft.rows
            local previewCols=draft.layout=="list" and 1 or draft.columns
            local ph,pw=math.min(height-7,previewRows*2),math.min(width-2,previewCols*8)
            local x=1+math.floor((width-pw)/2)
            local rows,cols=math.min(previewRows,ph),math.min(previewCols,pw)
            for row=0,rows-1 do for col=0,cols-1 do
                local x1,x2=x+math.floor(col*pw/cols),x+math.floor((col+1)*pw/cols)-1
                local y1,y2=6+math.floor(row*ph/rows),5+math.floor((row+1)*ph/rows)
                ui.style(x1,y1,x2-x1+1,y2-y1+1,nil,(row+col)%2==0 and accent or 128)
            end end
        end
        button(height-1,draft.target=="new" and "Create" or "Save grid","saveGrid",nil,nil,nil,true,accent)
        footer({{"Cancel",draft.target=="new" and "home" or "edit"}})
    elseif screen=="colour" then
        local draft=view.colourDraft
        local lines,hits=api.ui.palette(width,height,draft.auto and nil or draft.value,"Item color")
        ui.lines,ui.hits=lines,hits
        table.remove(hits) -- Replace the palette's Back row with draft controls.
        if width>=24 and height>=14 then
            monitorTile({x=2,y=11,w=width-2,h=height-12},tile.item and tile.item.name or "+ Item",
                tile.item and amount(countFor(board,tile),width-2) or "Select item","preview",nil,"ok",draft.auto and 128 or draft.value)
        end
        footer({{"Apply","applyColour"},{"Auto","autoColour"},{"Back","item"}})
    elseif screen=="keyboard" then
        local keyboard=view.keyboard
        local letters=keyboard.bank==2 and "1234567890-_/.:" or keyboard.bank==1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZ" or "abcdefghijklmnopqrstuvwxyz"
        ui.heading(keyboard.draft:sub(-width),accent)
        local cols,rows=math.max(4,math.min(10,math.floor(width/2))),math.max(1,math.min(3,height-4))
        local slots=cols*rows; local pages=math.ceil(#letters/slots)
        keyboard.page=math.max(1,math.min(keyboard.page or 1,pages))
        for i=1,slots do
            local value=letters:sub((keyboard.page-1)*slots+i,(keyboard.page-1)*slots+i)
            if value~="" then
                local col,row=(i-1)%cols,math.floor((i-1)/cols)
                button(2+row,value,"key",value,1+math.floor(col*width/cols),math.floor((col+1)*width/cols),true,accent)
            end
        end
        local items={{"ABC","bank"},{"Sp","space"},{"Del","del"},{keyboard.page.."/"..pages,"keyPage"}}
        for i,item in ipairs(items) do button(height-1,item[1],item[2],nil,1+math.floor((i-1)*width/4),math.floor(i*width/4)) end
        footer({{keyboard.kind=="search" and "Find" or "Save","saveText",nil,keyboard.kind=="search" or keyboard.draft:find("%S")~=nil},{"Clr","clearText"},{"Back","cancelText"}})
    elseif screen=="delete" or screen=="shrink" then
        ui.heading(screen=="delete" and "Delete view?" or "Remove last tiles?",accent)
        ui.text(2,board.name,true)
        button(height-1,"Confirm","confirm",screen,nil,nil,true,16384)
        footer({{"Cancel",screen=="delete" and "edit" or "grid"}})
    elseif screen=="source" then
        local data=source(board)
        info("AE source",{"Client: "..board.sensor.clientId,"Side: "..board.sensor.side,"Target: "..board.sensor.target,
            "Status: "..(data.error or data.status),"Age: "..(data.age and amount(math.floor(data.age)).." seconds" or "Unknown")},"source","edit")
    elseif screen=="about" or screen=="message" then
        info("Information",{screen=="message" and view.message or
            "Each saved view selects an AE1 sensor client, side and ME Wireless Access Point. Choose a 1-16 by 1-16 grid or a list of up to 256 rows, then touch an entry to select an item. Item details offer Color; Auto restores the default tile or alternating list colors. Appearance does not change the item or AE source. Name/Amount and direction sort the picker; Search filters names/raw IDs. Rows keep their positions until Sort, Search or Refresh so live count changes cannot select the wrong item. Counts update about every two seconds. A live complete catalog with no selected item means zero; offline/unpowered/missing data shows --. Counts use plain decimal digits without k/M/E notation. The native card does not expose NBT; indistinguishable raw-name/damage variants are combined. Items are never moved, requested or crafted. Each app configures its own source; the OS shares physical sensor reads."},"info",screen=="message" and "messageBack" or "settings")
    end
    return ui.lines,ui.hits
end
local function resize(state,api,view,board)
    local draft=view.gridDraft
    if board.columns~=draft.beforeColumns or board.rows~=draft.beforeRows or (board.layout or "grid")~=(draft.beforeLayout or "grid") then notice(view,"Grid changed in another window","edit"); return end
    if commit(state,api,view,function()
        local count=draft.layout=="list" and draft.count or draft.columns*draft.rows
        for i=#board.tiles,count+1,-1 do table.remove(board.tiles,i) end
        for i=#board.tiles+1,count do board.tiles[i]=newTile(state) end
        board.layout,board.columns,board.rows=draft.layout,draft.layout=="list" and 1 or draft.columns,draft.layout=="list" and draft.count or draft.rows
    end) then view.screen,view.pages="edit",{} end
end
function app.render(width,height,state,api,context)
    if not ready then return {"ME monitors blocked","Check OS console"} end
    return (build(width,height,state,api,context))
end
function app.handleTouch(x,y,width,height,state,api,context)
    if not ready then return false end
    local _,hits=build(width,height,state,api,context)
    local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view
    local board,index=find(state.boards,view.boardId)
    local tile=board and find(board.tiles,view.tileId)
    if action=="page" then local page=view.pages[value.key]; page.page=math.max(1,math.min(page.pages,page.page+value.delta))
    elseif action=="open" then view.boardId,view.screen,view.pages=value,"board",{}
    elseif action=="add" then
        local ok,err=api.pickSensor(context.windowId,"new",nil,"ae"); if not ok then notice(view,err) end
    elseif action=="sensor" then
        local ok,err=api.pickSensor(context.windowId,"source_"..board.id,board.sensor,"ae"); if not ok then notice(view,err) end
    elseif action=="tile" or action=="chooseTile" then
        view.tileId=value; tile=find(board.tiles,value)
        view.pickerReturn=action=="chooseTile" and "tiles" or tile.item and "item" or "board"
        view.screen=(action=="chooseTile" or not tile.item) and "picker" or "item"
        pickers[context.windowId]=nil; view.pages.items=nil; view.pages.item=nil
    elseif action=="changeItem" then view.screen,view.pickerReturn="picker","item"; pickers[context.windowId]=nil; view.pages.items=nil
    elseif action=="pickerBack" then view.screen=view.pickerReturn or (tile.item and "item" or "board")
    elseif action=="selectItem" then
        local frozen=picker(view,board,tile,context.windowId)
        local selected; for _,item in ipairs(frozen.rows) do if item.key==value then selected=item; break end end
        if selected and commit(state,api,view,function()
            tile.item={key=selected.key,raw=selected.raw,damage=selected.damage,name=selected.name}
        end) then view.screen=view.pickerReturn=="tiles" and "tiles" or "board"; pickers[context.windowId]=nil end
    elseif action=="clearItem" then
        if commit(state,api,view,function() tile.item=nil end) then view.screen="board" end
    elseif action=="sort" or action=="direction" or action=="refresh" then
        if action=="sort" then view.sort=view.sort=="amount" and "name" or "amount"
        elseif action=="direction" then view.descending=not view.descending end
        pickers[context.windowId]=nil; view.pages.items=nil
    elseif action=="search" or action=="rename" then
        view.keyboard={kind=action=="search" and "search" or "name",draft=action=="search" and (view.query or "") or board.name,
            original=board.name,bank=0,page=1}
        view.screen="keyboard"
    elseif action=="key" or action=="space" then
        local k=view.keyboard
        api.ui.typeKey(k,action=="space" and " " or value,k.kind=="search" and 48 or 24)
    elseif action=="del" then view.keyboard.draft=view.keyboard.draft:sub(1,-2)
    elseif action=="clearText" then view.keyboard.draft=""
    elseif action=="bank" then view.keyboard.bank,view.keyboard.page=(view.keyboard.bank+1)%3,1
    elseif action=="keyPage" then
        local k=view.keyboard; local slots=math.max(4,math.min(10,math.floor(width/2)))*math.max(1,math.min(3,height-4))
        k.page=k.page%math.ceil((k.bank==2 and 15 or 26)/slots)+1
    elseif action=="cancelText" then view.screen=view.keyboard.kind=="search" and "picker" or "edit"
    elseif action=="saveText" then
        local k=view.keyboard
        if k.kind=="search" then view.query,view.screen=k.draft,"picker"; pickers[context.windowId]=nil; view.pages.items=nil
        elseif board.name~=k.original then notice(view,"Name changed in another window","edit")
        elseif commit(state,api,view,function() board.name=k.draft:gsub("^%s+",""):gsub("%s+$","") end) then view.screen="edit" end
    elseif action=="resize" then
        local columns,rows=board.columns,board.rows
        if board.layout=="list" then columns,rows=gridShape(#board.tiles) end
        view.gridDraft={target="edit",layout=board.layout or "grid",columns=columns,rows=rows,count=#board.tiles,
            beforeLayout=board.layout or "grid",beforeColumns=board.columns,beforeRows=board.rows}; view.screen="grid"
    elseif action=="layoutToggle" then
        local draft=view.gridDraft
        if draft.layout=="list" then draft.layout="grid"
        else draft.layout,draft.count="list",draft.columns*draft.rows end
    elseif action=="gridStep" then local draft=view.gridDraft; draft[value.key]=math.max(1,math.min(value.key=="count" and MAX_AXIS^2 or MAX_AXIS,draft[value.key]+value.delta))
    elseif action=="saveGrid" then
        local draft=view.gridDraft
        if draft.target=="new" then
            local created
            if #state.boards>=MAX_VIEWS then notice(view,"Maximum 64 views","home")
            elseif commit(state,api,view,function()
                created={id=state.nextBoardId,name="View "..state.nextBoardId,sensor=copy(draft.sensor),layout=draft.layout,
                    columns=draft.layout=="list" and 1 or draft.columns,rows=draft.layout=="list" and draft.count or draft.rows,tiles={}}
                state.nextBoardId=state.nextBoardId+1
                for i=1,created.columns*created.rows do created.tiles[i]=newTile(state) end
                state.boards[#state.boards+1]=created
            end) then
                view.boardId,view.screen,view.pages=created.id,"board",{}
                api.watchSensor(watch(created),created.sensor,{profile="ae_items"})
            end
        elseif (draft.layout=="list" and draft.count or draft.columns*draft.rows)<#board.tiles then view.screen="shrink"
        else resize(state,api,view,board) end
    elseif action=="confirm" then
        if value=="shrink" then resize(state,api,view,board)
        elseif commit(state,api,view,function() table.remove(state.boards,index) end) then api.unwatchSensor(watch(board)); view.screen,view.pages="home",{} end
    elseif action=="tileColour" then
        view.colourDraft={value=tile.displayColour or 128,auto=tile.displayColour==nil,before=tile.displayColour}
        view.screen="colour"
    elseif action=="colour" then view.colourDraft.value,view.colourDraft.auto=value,false
    elseif action=="autoColour" then view.colourDraft.auto=true
    elseif action=="applyColour" then
        if tile.displayColour~=view.colourDraft.before then notice(view,"Color changed in another window","item")
        elseif commit(state,api,view,function() tile.displayColour=not view.colourDraft.auto and view.colourDraft.value or nil end) then view.screen="item" end
    elseif action=="accent" then local ok,err=api.pickColour(context.windowId); if not ok then notice(view,err) end
    elseif action=="density" then commit(state,api,view,function() state.settings.density=state.settings.density=="roomy" and "compact" or "roomy" end)
    elseif action=="toggleRates" then commit(state,api,view,function() board.showRates=board.showRates==false end)
    elseif action=="messageBack" then view.screen=view.messageBack or "home"
    else view.screen=action end
    return true
end
return app
