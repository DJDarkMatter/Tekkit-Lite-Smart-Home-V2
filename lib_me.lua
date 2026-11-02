-- Shared AE1 item identities, safe snapshots and bounded stock-rate history.
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

local Me={MAX=MAX,copy=copy,restore=restore,number=number,integer=integer,digits=digits,amount=amount,rateText=rateText,
    colour=colour,textValue=textValue,label=label,address=address,route=route,sourceKey=sourceKey,itemKey=itemKey,
    itemValid=itemValid,identity=identity,find=find,catalog=catalog}
function Me.boots(api)
    local result={}; for _,client in ipairs(api.getSensorClients()) do result[client.id]=client.bootId end; return result
end
function Me.snapshot(cache,api,binding,boots)
    if not address(binding) then return {status="unconfigured",error="Select an ME source",items={}} end
    local key=sourceKey(binding)..":"..tostring((boots or Me.boots(api))[binding.clientId])
    -- Forget prior boot snapshots of this address. They are never fresh data and
    -- retaining many large catalogs across client restarts wastes OS memory.
    local remove={}
    for other,value in pairs(cache) do if other~=key and value.address==sourceKey(binding) then remove[#remove+1]=other end end
    for _,other in ipairs(remove) do cache[other]=nil end
    local saved=cache[key] or {key=key,items={}}
    saved.address=sourceKey(binding)
    cache[key]=saved
    local reading=api.getSensorReading(binding)
    local oldStatus=saved.status
    saved.status,saved.error,saved.age=reading.status,reading.error,reading.age
    saved.sequence,saved.time=reading.sequence,reading.time
    if reading.status~="ok" then return saved end
    if reading.data and reading.data.Powered==false then saved.status,saved.error="unpowered","ME unpowered"; return saved end
    if oldStatus~="ok" or saved.dataSequence~=reading.dataSequence then
        local items,err,total=catalog(reading)
        if not items then saved.status,saved.error="unsupported",err; return saved end
        saved.items,saved.total,saved.dataSequence=items,total,reading.dataSequence
    end
    saved.data=reading.data
    return saved
end
function Me.count(snapshot,key)
    if not snapshot or snapshot.status~="ok" or not key then return nil end
    return snapshot.items[key] and snapshot.items[key].count or 0
end
function Me.isHVSolar(item)
    local raw=(item.raw or ""):gsub("(%l)(%u)","%1 %2")
    local name=(raw.." "..(item.name or "")):lower()
    if not name:find("solar",1,true) then return false end
    local flat=name:gsub("[^%w]","")
    return name:match("%f[%a]hv%f[%A]")~=nil or flat:find("highvoltage",1,true)~=nil or flat:find("hochspannung",1,true)~=nil
end
-- Sparse minute buckets share valid coverage for every item in a complete ME
-- snapshot. Only nonzero deltas and per-item excluded intervals need records.
local Rates={}
function Rates.new() return {buckets={},keys={},nextKey=1} end
local function trim(history,time)
    while #history.buckets>0 and history.buckets[1].minute<math.floor(time/60)-59 do table.remove(history.buckets,1) end
    local used,cost={},0
    for _,bucket in ipairs(history.buckets) do
        cost=cost+80
        for id in pairs(bucket.values) do used[id]=true; cost=cost+160 end
    end
    local remove={}
    for key,id in pairs(history.keys) do
        if not used[id] then remove[#remove+1]=key else cost=cost+2*#key+100 end
    end
    for _,key in ipairs(remove) do history.keys[key]=nil end
    return cost
end
function Rates.record(history,time,dt,changes)
    if not number(dt,0.001,10) then return false end
    trim(history,time)
    local minute=math.floor(time/60)
    local bucket=history.buckets[#history.buckets]
    if not bucket or bucket.minute~=minute then bucket={minute=minute,seconds=0,values={}}; history.buckets[#history.buckets+1]=bucket end
    bucket.seconds=bucket.seconds+dt
    for key,change in pairs(changes) do
        local id=history.keys[key]
        if not id then id=history.nextKey; history.nextKey=id+1; history.keys[key]=id end
        local row=bucket.values[id] or {0,0,0,0}; bucket.values[id]=row
        row[1]=row[1]+(change.skip and 0 or change.delta)
        if change.skip then row[2],row[3],row[4]=row[2]+dt,row[3]+1,row[4]+math.abs(change.delta) end
        if not number(row[1],-MAX,MAX) or not number(row[4],0,MAX) then
            history.buckets,history.keys,history.limited={},{},true; return false
        end
    end
    local cost=trim(history,time)
    while cost>196608 and #history.buckets>1 do table.remove(history.buckets,1); history.limited=true; cost=trim(history,time) end
    if cost>196608 then history.buckets,history.keys,history.limited={},{},true; return false end
    return true
end
function Rates.sum(history,key,time,window)
    local id=history.keys[key]
    local delta,seconds,drops,removed=0,0,0,0
    local first=math.floor(time/60)-window/60+1
    for _,bucket in ipairs(history.buckets) do if bucket.minute>=first then
        local row=id and bucket.values[id]
        seconds=seconds+bucket.seconds-(row and row[2] or 0)
        if row then delta,drops,removed=delta+row[1],drops+row[3],removed+row[4] end
    end end
    return delta,math.max(0,seconds),drops,removed
end
function Rates.valid(history)
    if type(history)~="table" or type(history.buckets)~="table" or #history.buckets>60 or type(history.keys)~="table"
        or not integer(history.nextKey,1,MAX) then return false end
    local ids={}; for key,id in pairs(history.keys) do
        if not textValue(key,600) or not integer(id,1,history.nextKey-1) or ids[id] then return false end; ids[id]=true
    end
    local last=-1
    for _,bucket in ipairs(history.buckets) do
        if type(bucket)~="table" or not integer(bucket.minute,0,MAX) or bucket.minute<=last
            or not number(bucket.seconds,0,120) or type(bucket.values)~="table" then return false end
        last=bucket.minute
        for id,row in pairs(bucket.values) do
            if not ids[id] or type(row)~="table" or not number(row[1],-MAX,MAX) or not number(row[2],0,bucket.seconds+0.001)
                or not integer(row[3],0,MAX) or not number(row[4],0,MAX) then return false end
        end
    end
    return true
end
Me.Rates=Rates
return Me
