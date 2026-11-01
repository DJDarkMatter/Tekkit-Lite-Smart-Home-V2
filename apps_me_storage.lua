-- Optional AE1 storage overview. Sensor access and persistence belong to the OS.
local app = {title = "ME storage", minWidth = 12, minHeight = 6, preferredWidth = 50, preferredHeight = 18}
local appName, ready = "me_storage", false
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function restore(state, old)
    local keys = {}; for key in pairs(state) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do state[key] = nil end
    for key, item in pairs(old) do state[key] = item end
end
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function counter(value) return integer(value, 0, 9007199254740991) and value or nil end
local function colour(value)
    for i = 0, 15 do if value == 2 ^ i then return true end end
    return false
end
local function validName(value)
    return type(value) == "string" and #value > 0 and #value <= 24 and value:find("%S") and not value:find("[%c]")
end
local function address(value)
    return type(value) == "table" and type(value.clientId) == "string" and #value.clientId > 0 and #value.clientId <= 64
        and ({top=true,bottom=true,left=true,right=true,front=true,back=true})[value.side]
        and type(value.target) == "string" and #value.target > 0 and #value.target <= 128
end
local function same(a, b) return a and b and a.clientId == b.clientId and a.side == b.side and a.target == b.target end
local function find(list, id)
    for index, item in ipairs(list or {}) do if item.id == id then return item, index end end
end
local function key(entry, drive) return appName .. "_" .. entry.id .. (drive and "_drive_" .. drive.id or "_network") end
local function decimal(value)
    local digits = {}
    repeat
        local digit = value % 10
        digits[#digits+1] = ("0123456789"):sub(digit+1,digit+1)
        value = math.floor(value / 10)
    until value == 0
    return table.concat(digits):reverse()
end
local function number(value)
    if value == nil then return "Unavailable" end
    return decimal(value):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
end
local function percent(value)
    local tenths = math.floor(value * 10 + 0.5)
    return decimal(math.floor(tenths / 10)) .. "." .. decimal(tenths % 10)
end
local function short(value, width)
    local text = number(value)
    return #text > width and text:gsub(" ", "") or text
end
local function storage(reading)
    local data = reading.data or {}
    local result = {status = reading.status, error = reading.error, age = reading.age, powered = data.Powered}
    if data.Powered == false then result.status, result.error = "unpowered", "ME is unpowered"; return result end
    local names = {used="UsedBytes", free="FreeBytes", items="UsedCount", room="FreeCount", types="UsedTypes", freeTypes="FreeTypes"}
    local found, invalid = false, false
    for dest, source in pairs(names) do
        result[dest] = counter(data[source])
        found = found or result[dest] ~= nil
        invalid = invalid or data[source] ~= nil and result[dest] == nil
    end
    if result.used and result.free and counter(result.used + result.free) then
        result.total = result.used + result.free
        result.percent = result.total > 0 and 100 * result.used / result.total or 0
    end
    if result.items and result.room then result.totalItems = counter(result.items + result.room) end
    if result.types and result.freeTypes then result.totalTypes = counter(result.types + result.freeTypes) end
    if reading.status == "ok" and (invalid or not found) then
        result.status, result.error = "unsupported", invalid and "Invalid AE counter" or "No AE storage counters"
    end
    return result
end
local function inventory(reading)
    local result = {status = reading.status, error = reading.error, cells = {}, tiers = {}, occupied = 0, empty = 0, known = 0, unknown = 0, capacity = 0}
    local slots = reading.data and reading.data.Slots
    if type(slots) ~= "table" then
        if reading.status == "ok" then result.status, result.error = "unsupported", "No inventory Slots data" end
        return result
    end
    local keys = {}; for slot in pairs(slots) do if integer(slot, 1, 4096) then keys[#keys + 1] = slot end end
    table.sort(keys)
    for _, slot in ipairs(keys) do
        local item = slots[slot]
        if type(item) == "table" and counter(item.Size) then
            if item.Size == 0 then result.empty = result.empty + 1
            else
                local label = type(item.Name) == "string" and item.Name or "Unknown item"
                local raw = type(item.RawName) == "string" and item.RawName or ""
                local identity = (label .. " " .. raw):lower():gsub("[%s_.%-]", "")
                local tier = tonumber(identity:match("(%d+)k"))
                if not ((tier == 1 or tier == 4 or tier == 16 or tier == 64)
                    and (identity:find("storage", 1, true) or identity:find("cell", 1, true))) then tier = nil end
                result.occupied = result.occupied + 1
                local cell = {slot = slot, name = label, raw = raw, count = item.Size, tier = tier,
                    used = counter(item.UsedBytes), free = counter(item.FreeBytes), items = counter(item.UsedCount), types = counter(item.UsedTypes)}
                result.cells[#result.cells + 1] = cell
                if tier then
                    result.known = result.known + item.Size; result.tiers[tier] = (result.tiers[tier] or 0) + item.Size
                    result.capacity = result.capacity + tier * 1024 * item.Size
                else result.unknown = result.unknown + item.Size end
            end
        end
    end
    return result
end
local function notice(view, message, back)
    view.message, view.messageBack, view.screen, view.page = tostring(message), back or view.screen or "home", "message", 1
end
local function commit(state, api, view, change)
    local old = copy(state); change()
    local ok, err = api.save()
    if not ok then restore(state, old); notice(view, "Save failed: " .. tostring(err)); return false, err end
    api.invalidateAppViews(appName)
    return true
end
function app.init(state, api, context)
    ready = false
    assert(api.sensorProfiles and api.pickSensor and api.watchSensor, "ME storage requires the bundled-v21 OS")
    appName = context and context.appName or "me_storage"
    if state.version == nil then state.version, state.networks, state.nextId, state.nextDriveId = 1, {}, 1, 1 end
    assert(state.version == 1 and type(state.networks) == "table" and #state.networks <= 16, "Invalid saved ME systems")
    local ids, drives, maxId, maxDrive = {}, {}, 0, 0
    for _, entry in ipairs(state.networks) do
        assert(integer(entry.id, 1, 2147483000) and not ids[entry.id] and validName(entry.name) and address(entry.sensor)
            and type(entry.drives) == "table" and #entry.drives <= 32, "Invalid saved ME system")
        ids[entry.id], maxId = true, math.max(maxId, entry.id)
        for _, drive in ipairs(entry.drives) do
            assert(integer(drive.id, 1, 2147483000) and not drives[drive.id] and address(drive.sensor), "Invalid saved drive")
            drives[drive.id], maxDrive = true, math.max(maxDrive, drive.id)
        end
    end
    assert(integer(state.nextId, maxId + 1, 2147483001) and integer(state.nextDriveId, maxDrive + 1, 2147483001), "Invalid saved ME IDs")
    ready = true
end
function app.background(dt, state, api)
    if not ready then return end
    for _, entry in ipairs(state.networks) do
        api.watchSensor(key(entry), entry.sensor, {profile = "ae_storage"})
        for _, drive in ipairs(entry.drives) do api.watchSensor(key(entry, drive), drive.sensor) end
    end
end
function app.shutdown(state, api)
    for _, entry in ipairs(state.networks) do
        api.unwatchSensor(key(entry)); for _, drive in ipairs(entry.drives) do api.unwatchSensor(key(entry, drive)) end
    end
end
function app.handleSensorSelection(selection, selected, state, api, context)
    if not address(selected) then return false, "Invalid sensor address" end
    local view, created, oldDrives = context.view, nil, {}
    local entry = find(state.networks, tonumber(selection:match("_(%d+)$")))
    if selection ~= "new" and not entry then return false, "ME system was removed" end
    if selection == "new" and #state.networks >= 16 then return false, "Maximum 16 systems" end
    local addingDrive = selection:match("^drive_")
    if addingDrive then
        if #entry.drives >= 32 then return false, "Maximum 32 drive inventories" end
        for _, drive in ipairs(entry.drives) do if same(drive.sensor, selected) then return false, "Drive already added" end end
    end
    local ok, err = commit(state, api, view, function()
        if selection == "new" then
            created = {id = state.nextId, name = "ME " .. state.nextId, sensor = copy(selected), drives = {}}
            state.nextId = state.nextId + 1; state.networks[#state.networks + 1] = created; entry = created
        elseif addingDrive then
            entry.drives[#entry.drives + 1] = {id = state.nextDriveId, sensor = copy(selected)}
            state.nextDriveId = state.nextDriveId + 1
        else
            if not same(entry.sensor, selected) then oldDrives, entry.drives = entry.drives, {} end
            entry.sensor = copy(selected)
        end
    end)
    if not ok then return false, err end
    for _, drive in ipairs(oldDrives) do api.unwatchSensor(key(entry, drive)) end
    app.background(0, state, api)
    view.id, view.screen, view.page = entry.id, addingDrive and "cells" or "network", 1
    return true
end
local function build(width, height, state, api, context)
    local view = context.view
    local entry = find(state.networks, view.id)
    local screen = view.screen or "home"
    local global = {home=true, settings=true, about=true, message=true}
    if not global[screen] and not entry then screen, view.screen = "home", "home" end
    local drive = entry and find(entry.drives, view.driveId)
    if (screen == "drive" or screen == "driveSource" or screen == "cell" or screen == "removeDrive") and not drive then screen, view.screen = "cells", "cells" end
    local accent = api.getAppColour(context.appName or appName)
    local ui = api.ui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    local function button(y, label, action, value, x1, x2, enabled, bg)
        ui.button(y, label, action, x1, x2, enabled, bg or 128, nil, value)
    end
    local function footer(labels)
        for i, item in ipairs(labels) do
            button(height, item[1], item[2], item[3], 1 + math.floor((i-1)*width/#labels), math.floor(i*width/#labels),
                item[4], item[5] or (#labels > 1 and i % 2 == 0 and 256 or 128))
        end
    end
    local function page(count, slots, row)
        local pages = math.max(1, math.ceil(count / slots))
        view.page, view.pageCount = math.max(1, math.min(view.page or 1, pages)), pages
        if pages > 1 then
            local wing = math.max(2, math.floor(width / 4))
            button(row, "<", "prev", nil, 1, wing, view.page > 1)
            button(row, ">", "next", nil, width-wing+1, width, view.page < pages)
            local value = view.page .. "/" .. pages
            local x = wing + 1 + math.max(0, math.floor((width - 2*wing - #value)/2))
            ui.lines[row] = ui.lines[row]:sub(1,x-1) .. value .. ui.lines[row]:sub(x+#value)
        end
        return (view.page - 1)*slots
    end
    local function list(title, items, bottom, reserved)
        ui.heading(title, accent)
        local slots = math.max(1, bottom - 1)
        if #items > slots then slots = math.max(1, slots - 1) end
        local first = page(#items, slots, bottom)
        for i = 1, slots do
            local item = items[first+i]
            if item then button(i+1, item.label, item.action, item.value, nil, nil, item.enabled, item.bg) end
        end
    end
    local function info(title, lines, back)
        local wrapped = {}
        for _, line in ipairs(lines) do
            line = tostring(line):gsub("[%c]", " ")
            repeat
                local cut = #line > width and line:sub(1,width):match("^.*()%s")
                if cut and cut > 1 then wrapped[#wrapped+1],line=line:sub(1,cut-1),line:sub(cut+1)
                else wrapped[#wrapped+1],line=line:sub(1,width),line:sub(width+1) end
            until line == ""
        end
        ui.heading(title, accent)
        local slots = #wrapped <= height-2 and height-2 or height-3
        local first = page(#wrapped, slots, height-1)
        for i = 1, slots do ui.text(i+1, wrapped[first+i] or "") end
        footer({{"Back", back}})
    end
    local function sourceLines(sensor)
        return {"Client: "..sensor.clientId, "Side: "..sensor.side, "Target: "..sensor.target, "Card: "..tostring(sensor.card or "unknown")}
    end
    local function put(x, y, text, span)
        text = tostring(text):sub(1,span)
        ui.lines[y] = ui.lines[y]:sub(1,x-1) .. text .. ui.lines[y]:sub(x+#text)
    end
    if screen == "home" then
        local items = {}
        for _, item in ipairs(state.networks) do
            local value = storage(api.getSensorReading(item.sensor, {profile="ae_storage"}))
            items[#items+1] = {label = item.name .. (value.percent and " "..percent(value.percent).."%" or " / "..value.status), action="open", value=item.id}
        end
        if #items == 0 then items[1] = {label="Select an ME system", enabled=false} end
        list("ME storage", items, height-2)
        button(height-1, "+ Add system", "add", nil, nil, nil, #state.networks < 16, accent)
        footer({{"Settings","settings"}})
    elseif screen == "network" then
        local value = storage(api.getSensorReading(entry.sensor, {profile="ae_storage"}))
        local live = value.status == "ok"
        ui.heading(entry.name, accent)
        ui.text(2, (live and "Usage" or value.error or value.status) .. (value.percent and " "..percent(value.percent).."%" or ""), true)
        ui.style(1,2,width,1, live and 1 or 32768, live and 128 or 2)
        local cols, cardH = width >= 60 and 3 or width >= 38 and 2 or 1, height >= 10 and 3 or 2
        local rows = math.max(1, math.floor((height-4)/cardH))
        local metrics = {{"Bytes used",value.used},{"Bytes free",value.free},
            {"Items stored",value.items},{"Item room*",value.room},{"Item types",value.types},{"Free type slots",value.freeTypes}}
        if rows*cols >= 9 then
            metrics = {{"Bytes used",value.used},{"Bytes free",value.free},{"Total bytes",value.total},
                {"Items stored",value.items},{"Item room*",value.room},{"Total item storage*",value.totalItems},
                {"Item types",value.types},{"Free type slots",value.freeTypes},{"Total types*",value.totalTypes}}
        end
        local first = page(#metrics, rows*cols, height-1)
        for i = 1, rows*cols do
            local metric = metrics[first+i]
            if metric then
                local col, row = (i-1)%cols, math.floor((i-1)/cols)
                local x = 1 + math.floor(col*width/cols)
                local span = math.floor((col+1)*width/cols)-x+1
                if col > 0 then x,span = x+1,span-1 end
                local y = 3+row*cardH
                ui.style(x,y,span,cardH,live and 1 or 256,32768)
                ui.style(x,y,span,1,api.ui.contrast(accent),accent)
                put(x,y,metric[1],span); put(x,y+1,short(metric[2],span),span)
                if cardH == 3 and first+i == 1 and value.percent then
                    ui.style(x,y+2,span,1,nil,128)
                    local filled = math.floor(span*value.percent/100+0.5)
                    if filled > 0 then ui.style(x,y+2,filled,1,nil,live and (value.percent >= 90 and 2 or 32) or 128) end
                end
            end
        end
        if #metrics==9 and 2+math.ceil(#metrics/cols)*cardH<height-2 then
            ui.text(height-2,"* Reported headroom; see Source",true)
        end
        footer({{"Back","home"},{width >= 15 and "Cells" or "Cell","cells"},{"Edit","edit"}})
    elseif screen == "cells" then
        local items = {{label="Cell / drive totals", action="audit"}}
        for i, item in ipairs(entry.drives) do
            local inv = inventory(api.getSensorReading(item.sensor))
            items[#items+1] = {label="Drive "..i.." / "..(inv.status == "ok" and inv.known.." cells" or inv.status), action="drive", value=item.id}
        end
        list("Drive inventories",items,height-2)
        button(height-1,"+ Add drive","addDrive",nil,nil,nil,#entry.drives<32,accent)
        footer({{"Back","network"}})
    elseif screen == "audit" then
        local totals = {known=0,unknown=0,empty=0,capacity=0,live=0,tiers={}}
        for _, item in ipairs(entry.drives) do
            local inv = inventory(api.getSensorReading(item.sensor))
            if inv.status == "ok" then
                totals.live=totals.live+1
                for _, field in ipairs({"known","unknown","empty","capacity"}) do totals[field]=totals[field]+inv[field] end
                for tier,count in pairs(inv.tiers) do totals.tiers[tier]=(totals.tiers[tier] or 0)+count end
            end
        end
        local lines = {"Selected drives: "..#entry.drives, "Live inventories: "..totals.live, "Identified cells: "..totals.known}
        for _, tier in ipairs({1,4,16,64}) do lines[#lines+1]=tier.."k cells: "..(totals.tiers[tier] or 0) end
        lines[#lines+1]="Unknown items: "..totals.unknown; lines[#lines+1]="Empty slots seen: "..totals.empty
        lines[#lines+1]="Surveyed bytes: "..number(totals.capacity)
        lines[#lines+1]="Live selected inventories only. Membership is selected by you. Cell fill/NBT is not exposed by the old inventory card. Network totals include other storage too."
        info("Cell survey",lines,"cells")
    elseif screen == "drive" then
        local inv = inventory(api.getSensorReading(drive.sensor))
        local items = {}
        for _, cell in ipairs(inv.cells) do items[#items+1]={label=cell.slot..": "..cell.name,action="cell",value=cell.slot} end
        if #items == 0 then items[1]={label=inv.error or "No occupied slots",enabled=false} end
        list("Drive slots",items,height-1)
        footer({{"Back","cells"},{"Source","driveSource"},{"Remove","removeDrive"}})
    elseif screen == "cell" then
        local inv = inventory(api.getSensorReading(drive.sensor))
        local cell; for _, item in ipairs(inv.cells) do if item.slot == view.slot then cell = item end end
        if not cell then info("Cell slot",{inv.error or "Slot is now empty"},"drive")
        else info("Cell "..cell.slot,{cell.name,"Raw: "..cell.raw,"Count: "..cell.count,"Size: "..(cell.tier and cell.tier.."k" or "Unknown"),
            "Bytes used: "..number(cell.used),"Bytes free: "..number(cell.free),"Items: "..number(cell.items),"Types: "..number(cell.types),
            "Native inventory cards report names/counts, not cell NBT or per-cell fill."},"drive") end
    elseif screen == "source" or screen == "driveSource" then
        local sensor = screen == "source" and entry.sensor or drive.sensor
        local lines = sourceLines(sensor)
        local reading = api.getSensorReading(sensor, screen == "source" and {profile="ae_storage"} or nil)
        lines[#lines+1]="Status: "..reading.status; lines[#lines+1]="Age: "..(reading.age and string.format("%.1fs",reading.age) or "Unavailable")
        if reading.error then lines[#lines+1]=reading.error end
        if screen == "source" then
            local value = storage(reading)
            for _, field in ipairs({"used","free","total","items","room","totalItems","types","freeTypes","totalTypes"}) do lines[#lines+1]=field..": "..number(value[field]) end
        end
        if screen == "source" then lines[#lines+1]="* Item total = stored + reported room; new item types consume overhead. Type total = unique stored types + free per-cell slots; this is a combined indicator, not physical cell slot capacity." end
        info("Sensor source",lines,screen == "source" and "edit" or "drive")
    elseif screen == "edit" then
        list("System settings",{{label="Rename",action="rename"},{label="Change AE sensor",action="retarget"},
            {label="Source / exact figures",action="source"},{label="Drive inventories",action="cells"},{label="Remove system",action="remove"}},height-1)
        footer({{"Back","network"}})
    elseif screen == "settings" then
        list("ME settings",{{label="UI colour",action="accent"},{label="About / setup",action="about"}},height-1)
        footer({{"Back","home"}})
    elseif screen == "rename" then
        local keyboard = view.keyboard
        ui.heading(keyboard.draft:sub(-width),accent)
        local letters = keyboard.bank == 2 and "1234567890-_/.:" or keyboard.bank == 1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZ" or "abcdefghijklmnopqrstuvwxyz"
        local cols, rows = math.max(4,math.min(10,math.floor(width/2))), math.max(1,math.min(3,height-4))
        local slots = cols*rows; local pages=math.ceil(#letters/slots)
        keyboard.page=math.max(1,math.min(keyboard.page or 1,pages))
        for i=1,slots do
            local letter=letters:sub((keyboard.page-1)*slots+i,(keyboard.page-1)*slots+i)
            if letter~="" then
                local col,row=(i-1)%cols,math.floor((i-1)/cols)
                button(2+row,letter,"key",letter,1+math.floor(col*width/cols),math.floor((col+1)*width/cols),true,accent)
            end
        end
        local actions={{"ABC","bank"},{"Sp","space"},{"Del","del"},{keyboard.page.."/"..pages,"keyPage"}}
        for i,item in ipairs(actions) do button(height-1,item[1],item[2],nil,1+math.floor((i-1)*width/4),math.floor(i*width/4)) end
        footer({{"Save","saveName",nil,keyboard.draft:find("%S") ~= nil},{"Clr","clearName"},{"Back","edit"}})
    elseif screen == "remove" or screen == "removeDrive" then
        ui.heading(screen == "remove" and "Remove system?" or "Remove drive?",accent)
        ui.text(2,"Only removes this binding",true)
        button(height-1,"Confirm","confirmRemove",screen,nil,nil,true,16384)
        footer({{"Cancel",screen == "remove" and "edit" or "drive"}})
    elseif screen == "about" or screen == "message" then
        info("Information",{screen == "message" and view.message or
            "AE1: put an Applied Energistics sensor card near a powered ME Wireless Access Point on the selected network. Native fields are UsedBytes, FreeBytes, UsedCount, FreeCount, UsedTypes and FreeTypes. Item room is reported free count; new types consume extra bytes. Eight items use a data byte; type/cell overhead also uses bytes. Unique item types differ from free per-cell type slots. Individual cell counts/sizes need optional Inventory Card targets on ME drives/chests. Only add inventories from this ME system. Cell names identify standard 1k/4k/16k/64k sizes; unknown items stay unknown. Per-cell fill and NBT are not exposed by the native card. Missing/offline data is never zero. Apps can share one sensor target; subscriptions are deduplicated by the OS."},screen == "message" and "messageBack" or "settings")
    end
    return ui.lines,ui.hits
end
function app.render(width,height,state,api,context)
    if not ready then return {"ME storage blocked","Check OS console"} end
    return (build(width,height,state,api,context))
end
function app.handleTouch(x,y,width,height,state,api,context)
    if not ready then return false end
    local _,hits=build(width,height,state,api,context)
    local action,value
    for _,hit in ipairs(hits) do if hit.enabled~=false and api.ui.hit(hit,x,y) then action,value=hit.action,hit.value; break end end
    if not action then return false end
    local view=context.view
    local entry,index=find(state.networks,view.id)
    local drive,driveIndex=entry and find(entry.drives,view.driveId)
    if entry then drive,driveIndex=find(entry.drives,view.driveId) end
    if action=="prev" or action=="next" then view.page=math.max(1,math.min(view.pageCount or 1,(view.page or 1)+(action=="prev" and -1 or 1)))
    elseif action=="open" then view.id,view.screen,view.page=value,"network",1
    elseif action=="drive" then
        if value~=nil then view.driveId=value end
        view.screen,view.page="drive",1
    elseif action=="cell" then view.slot,view.screen,view.page=value,"cell",1
    elseif action=="add" or action=="retarget" or action=="addDrive" then
        local selection=action=="add" and "new" or (action=="addDrive" and "drive_" or "source_")..entry.id
        local ok,err=api.pickSensor(context.windowId,selection,action=="retarget" and entry.sensor or nil,action=="addDrive" and "inventory" or "ae")
        if not ok then notice(view,err) end
    elseif action=="accent" then
        local ok,err=api.pickColour(context.windowId); if not ok then notice(view,err) end
    elseif action=="rename" then view.keyboard,view.screen={draft=entry.name,original=entry.name,page=1,bank=0},"rename"
    elseif action=="key" or action=="space" then
        if #view.keyboard.draft<24 then view.keyboard.draft=view.keyboard.draft..(action=="space" and " " or value) end
    elseif action=="del" then view.keyboard.draft=view.keyboard.draft:sub(1,-2)
    elseif action=="clearName" then view.keyboard.draft=""
    elseif action=="bank" then view.keyboard.bank,view.keyboard.page=(view.keyboard.bank+1)%3,1
    elseif action=="keyPage" then view.keyboard.page=(view.keyboard.page or 1)+1
        local letters=view.keyboard.bank==2 and #"1234567890-_/.:" or 26
        local slots=math.max(4,math.min(10,math.floor(width/2)))*math.max(1,math.min(3,height-4))
        if view.keyboard.page>math.ceil(letters/slots) then view.keyboard.page=1 end
    elseif action=="saveName" then
        if entry.name~=view.keyboard.original then notice(view,"Name changed in another window","edit")
        else
            local clean=view.keyboard.draft:gsub("^%s+",""):gsub("%s+$","")
            if validName(clean) and commit(state,api,view,function() entry.name=clean end) then view.screen,view.page="edit",1 end
        end
    elseif action=="confirmRemove" then
        if value=="removeDrive" then
            local old=drive
            if commit(state,api,view,function() table.remove(entry.drives,driveIndex) end) then api.unwatchSensor(key(entry,old)); view.screen,view.page="cells",1 end
        else
            local old=entry
            if commit(state,api,view,function() table.remove(state.networks,index) end) then
                api.unwatchSensor(key(old)); for _,item in ipairs(old.drives) do api.unwatchSensor(key(old,item)) end
                view.screen,view.page="home",1
            end
        end
    elseif action=="messageBack" then view.screen,view.page=view.messageBack or "home",1
    else view.screen,view.page=action,1 end
    return true
end
return app
