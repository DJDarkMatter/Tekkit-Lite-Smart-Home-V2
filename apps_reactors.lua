-- Optional reactor overview. All sensors and output switches belong to OS APIs.
local app = {title = "Reactors", minWidth = 12, minHeight = 6, preferredWidth = 50, preferredHeight = 18}
local Me = dofile("lib_me.lua")
local appName, ready = "reactors", false
local copy, restore = Me.copy, Me.restore
local function find(state, id)
    for index, entry in ipairs(state.reactors) do if entry.id == id then return entry, index end end
end
local function logical(entry) return appName .. "_switch_" .. entry.id end
local function watchKey(entry) return appName .. "_sensor_" .. entry.id end
local function same(a, b)
    return a and b and a.clientId == b.clientId and a.side == b.side and a.color == b.color or a == b
end
local function wire(entry, api)
    for _, item in ipairs(api.getOutputs()) do if item.name == logical(entry) and same(item, entry.outputAddress) then return item end end
end
local function number(value)
    if type(value) ~= "number" or value~=value or math.abs(value)==math.huge then return "?" end
    local negative=value<0; value=math.floor(math.abs(value))
    if value>9007199254740991 then return (negative and "-" or "")..tostring(value) end
    local out={}
    repeat local digit=value%10; out[#out+1]=("0123456789"):sub(digit+1,digit+1); value=math.floor(value/10) until value==0
    local text=table.concat(out):gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
    return (negative and "-" or "")..text
end
local function decimal(value, places)
    local scale = 10 ^ places
    if value ~= value or math.abs(value) > Me.MAX / scale then return tostring(value) end
    local rounded = math.floor(math.abs(value) * scale + 0.5)
    local fraction = Me.digits(rounded % scale)
    return (value < 0 and "-" or "") .. Me.digits(math.floor(rounded / scale)) .. "."
        .. string.rep("0", places - #fraction) .. fraction
end
local function energy(value, compact)
    for _, unit in ipairs({{1000000000000000000, "EEU"}, {1000000000000000, "PEU"}, {1000000000000, "TEU"},
        {1000000000, "GEU"}, {1000000, "MEU"}, {1000, "kEU"}}) do
        if value >= unit[1] then
            return decimal(value / unit[1], compact and 1 or 2) .. (compact and "" or " ") .. unit[2]
        end
    end
    return number(value) .. (compact and "EU" or " EU")
end
local function notice(view, message, back)
    view.message, view.messageBack, view.screen = tostring(message), back or view.screen or "home", "message"
end
local function commit(state, api, view, change, changes)
    local old = copy(state)
    change()
    local ok, err
    if changes then ok, err = api.updateOutputs(changes()) else ok, err = api.save() end
    if not ok then restore(state, old); notice(view, "Save failed: " .. tostring(err)); return false, err end
    api.invalidateAppViews(appName)
    return true
end
function app.init(state, api, context)
    assert(api.ui and api.ui.keyboard and api.ui.breadcrumb,"reactors requires bundled-v41 OS; run inst server")
    ready = false
    assert(api.pickSensor and api.watchSensor and api.sharedOutputs, "Reactors requires bundled-v15 OS")
    appName = context and context.appName or "reactors"
    if state.version == nil then state.version, state.reactors, state.nextId, state.panelColour = 1, {}, 1, 256 end
    assert(state.version == 1 and type(state.reactors) == "table" and #state.reactors <= 64, "Invalid saved reactors")
    local ids, maximum = {}, 0
    for _, entry in ipairs(state.reactors) do
        assert(type(entry) == "table" and type(entry.id) == "number" and entry.id >= 1 and entry.id == math.floor(entry.id)
            and not ids[entry.id] and type(entry.name) == "string" and #entry.name > 0 and #entry.name <= 32
            and type(entry.sensor) == "table", "Invalid saved reactor entry")
        ids[entry.id], maximum = true, math.max(maximum, entry.id)
    end
    assert(type(state.nextId) == "number" and state.nextId > maximum and state.nextId == math.floor(state.nextId), "Invalid reactor ID counter")
    assert(api.ui.colourName(state.panelColour) ~= "Unknown", "Invalid panel color")
    ready = true
    app.background(0, state, api)
end
function app.background(dt, state, api)
    if not ready then return end
    for _, entry in ipairs(state.reactors) do api.watchSensor(watchKey(entry), entry.sensor) end
end
function app.shutdown(state, api)
    for _, entry in ipairs(state.reactors) do api.unwatchSensor(watchKey(entry)) end
end
function app.handleSensorSelection(key, address, state, api, context)
    local view = context.view
    local entry = key ~= "new" and find(state, tonumber(key:match("^sensor_(%d+)$"))) or nil
    if key ~= "new" and not entry then return false, "Reactor was removed" end
    if key == "new" and #state.reactors >= 64 then return false, "Maximum 64 reactors" end
    local previous, created = copy(state), nil
    if key == "new" then
        created = {id = state.nextId, name = "Core " .. state.nextId, sensor = copy(address)}
        state.nextId = state.nextId + 1; state.reactors[#state.reactors + 1] = created; entry = created
    else entry.sensor = copy(address) end
    local ok, err = api.save()
    if not ok then restore(state, previous); return false, err end
    api.invalidateAppViews(appName)
    api.watchSensor(watchKey(entry), entry.sensor)
    view.id, view.screen, view.page = entry.id, "reactor", 1
    return true
end
function app.handleIOSelection(key, address, state, api, context)
    local entry = find(state, tonumber(key:match("^output_(%d+)$")))
    if not entry then return false, "Reactor was removed" end
    local view = context.view
    if view.routeKey ~= key or not same(entry.outputAddress, view.routeBefore) then return false, "Routing changed; cancel and retry" end
    if same(entry.outputAddress, address) and wire(entry, api) then return true end
    local old = copy(state)
    entry.outputAddress = copy(address)
    local ok, err = api.updateOutputs({{name = logical(entry), clientId = address.clientId, side = address.side, color = address.color, initialValue = false}})
    if not ok then restore(state, old); return false, err end
    api.invalidateAppViews(appName)
    return true
end
local function build(width, height, state, api, context)
    local view, accent = context.view, api.getAppColour(context.appName or appName)
    local screen, entry = view.screen or "home", find(state, view.id)
    if screen ~= "home" and screen ~= "settings" and screen ~= "palette" and screen ~= "about" and screen ~= "message" and not entry then
        screen, view.screen = "home", "home"
    end
    local ui = api.ui.content(width, height)
    local contrast = api.ui.contrast(state.panelColour)
    ui.style(1, 1, width, height, contrast, state.panelColour)
    local function put(x, y, value, span, centre)
        if y < 1 or y > height then return end
        span = math.min(span or width - x + 1, width - x + 1)
        value = tostring(value):gsub("[%c]", " "):sub(1, span)
        if centre then value = string.rep(" ", math.floor((span - #value) / 2)) .. value end
        ui.lines[y] = ui.lines[y]:sub(1, x - 1) .. value .. ui.lines[y]:sub(x + #value)
    end
    local function button(row, label, action, value, x1, x2, enabled, bg, depth)
        ui.button(row, label, action, x1, x2, enabled, bg or 128, nil, value, depth)
    end
    local function footer(left, action, right, rightAction, depth)
        depth=depth or 1
        local y=height-depth+1
        if not right then button(y, left, action, nil, nil, nil, true, 128, depth)
        else
            local half = math.floor(width / 2)
            button(y, left, action, nil, 1, half, true, 128, depth)
            button(y, right, rightAction, nil, half + 1, width, true, accent, depth)
        end
    end
    local function pages(count, slots, key, row)
        local total = math.max(1, math.ceil(count / slots))
        view.pages = view.pages or {}
        local page = math.max(1, math.min(view.pages[key] or 1, total))
        view.pages[key] = page
        if total > 1 then
            local wing = math.floor(width / 3)
            button(row, "<", "page", {key = key, delta = -1, pages = total}, 1, wing, page > 1)
            put(wing + 1, row, page .. "/" .. total, width - 2 * wing, true)
            button(row, ">", "page", {key = key, delta = 1, pages = total}, width - wing + 1, width, page < total)
        end
        return page, total
    end
    local function metrics(reactor, compact, includePercent)
        reactor = reactor or {}
        local values={(compact and "T: " or "Heat: ") .. number(reactor.heat), (compact and "Max: " or "MaxHeat: ") .. number(reactor.maxHeat),
            (compact and (reactor.meltingDerived and "M*: " or "M: ") or reactor.meltingDerived and "Melting*: " or "Melting: ") .. number(reactor.melting),
            (compact and "Out: " or "Output: ") .. number(reactor.output) .. " EU/t"}
        if reactor.heat then
            if includePercent~=false then values[#values+1]=(compact and "Heat: " or "Heat level: ")..decimal(reactor.percent,1).."%" end
            values[#values+1]=(compact and "M+" or "To melting")..(reactor.meltingDerived and "*: " or ": ")..number(reactor.heatToMelting)
            values[#values+1]=(compact and "Max+: " or "To MaxHeat: ")..number(reactor.heatToMax)
        end
        if reactor.energyEmitted~=nil then values[#values+1]=(compact and "Emit: " or "Emitted: ")..energy(reactor.energyEmitted,compact) end
        if reactor.energySunken~=nil then values[#values+1]=(compact and "In: " or "Received: ")..energy(reactor.energySunken,compact) end
        return values
    end
    local function extraFields(data)
        local excluded={heat=true,temperature=true,maxheat=true,maximumheat=true,output=true,euoutput=true,active=true,isactive=true,
            heatpercentage=true,melting=true,meltingpoint=true,meltingtemperature=true,energyemitted=true,energysunken=true,energysunk=true,
            name=true,rawname=true,type=true,position=true}
        local keys,values={},{}
        for key,value in pairs(data or {}) do
            if type(key)=="string" then
                local name=key:lower():gsub("[^%a]","")
                if not excluded[name] and not name:find("remaining",1,true) and not name:find("timeleft",1,true)
                    and (type(value)=="number" and value==value and math.abs(value)<math.huge or type(value)=="boolean" or type(value)=="string") then keys[#keys+1]=key end
            end
        end
        table.sort(keys)
        for i=1,math.min(32,#keys) do
            local key=keys[i]; local value=data[key]
            if type(value)=="boolean" then value=value and "On" or "Off"
            elseif type(value)=="number" and value==math.floor(value) then value=number(value)
            else value=tostring(value):gsub("[%c]"," "):sub(1,160) end
            values[#values+1]=key:gsub("(%l)(%u)","%1 %2"):gsub("_"," ")..": "..value
        end
        if #keys>32 then values[#values+1]="More fields in Raw readings" end
        return values
    end
    local function reading(item)
        local result = api.getSensorReading(item.sensor)
        if result.status == "ok" and not result.reactor then result.status, result.error = "invalid", "Not a reactor reading" end
        return result
    end
    local function switch(item, row, x1, x2, depth)
        local output = wire(item, api)
        local text = not output and "Set IO" or output.value and "ON" or "OFF"
        if output and (not output.online or not output.confirmed) then text = text .. " ..." end
        button(row, text, output and "toggle" or "output", item.id, x1, x2, true,
            not output and accent or not output.online and 16384 or not output.confirmed and 2 or output.value and 32 or 128, depth)
    end
    if screen == "home" then
        ui.heading("Reactors", accent)
        local depth=math.min(api.ui.controlHeight(height),math.max(1,math.floor((height-4)/5)))
        local columns = math.max(1, math.min(3, math.floor((width + 1) / 23)))
        local bottom = height - 2*depth
        local rows = math.max(1, math.floor((bottom - 1) / 8))
        if #state.reactors > columns * rows then bottom = bottom - 1; rows = math.max(1, math.floor((bottom - 1) / 8)) end
        local slots = rows * columns
        local page = pages(#state.reactors, slots, "home", bottom + 1)
        if #state.reactors == 0 then
            button(math.max(2, math.floor((height-depth)/2)), "+ Add reactor", "add", nil, nil, nil, true, accent, depth)
            footer("Settings", "settings", nil, nil, depth)
        else
            ui.style(1, 2, width, bottom - 1, 1, 32768)
            local visible=math.min(slots,#state.reactors-(page-1)*slots)
            local drawColumns=math.min(columns,visible)
            local drawRows=math.min(rows,math.ceil(visible/drawColumns))
            for slot = 1, slots do
                local item = state.reactors[(page - 1) * slots + slot]
                if item then
                    local col, row = (slot - 1) % drawColumns, math.floor((slot - 1) / drawColumns)
                    local x1, x2 = 1 + math.floor(col * width / drawColumns) + (col > 0 and 1 or 0), math.floor((col + 1) * width / drawColumns)
                    local y1, y2 = 2 + math.floor(row * (bottom - 1) / drawRows) + (row > 0 and 1 or 0), 1 + math.floor((row + 1) * (bottom - 1) / drawRows)
                    local w, rh = x2 - x1 + 1, y2 - y1 + 1
                    local controlRows=math.min(depth,math.max(1,rh-2))
                    local detailEnd=y2-controlRows
                    ui.style(x1, y1, w, rh, contrast, state.panelColour)
                    ui.style(x1, y1, w, 1, api.ui.contrast(accent), accent)
                    put(x1, y1, item.name, w - 4)
                    local status = reading(item)
                    local active = status.status == "ok" and status.reactor and status.reactor.active
                    local label = status.status ~= "ok" and "?" or active == nil and "?" or active and "On" or "Off"
                    put(x2 - 2, y1, label, 3)
                    ui.style(x2 - 2, y1, 3, 1, 32768, label == "On" and 32 or label == "Off" and 16384 or 2)
                    local values = metrics(status.reactor,w<24)
                    for _,text in ipairs(extraFields(status.data)) do values[#values+1]=text end
                    for index = 1, math.min(#values, detailEnd-y1) do put(x1, y1 + index, values[index], w) end
                    if status.status ~= "ok" then
                        put(x1, math.min(detailEnd, y1 + 1), status.error or "Sensor unavailable", w)
                        ui.style(x1, y1 + 1, w, math.max(1, detailEnd-y1), 128, state.panelColour)
                    elseif status.reactor and status.reactor.percent and detailEnd-y1 > #values+1 then
                        local y=detailEnd-1
                        local filled=math.floor(w*math.max(0,math.min(100,status.reactor.percent))/100)
                        ui.style(x1,y,w,2,1,128)
                        if filled>0 then ui.style(x1,y,filled,2,1,status.reactor.percent>=85 and 16384 or 8192) end
                    end
                    ui.hits[#ui.hits + 1] = {x1 = x1, x2 = x2, y1 = y1, y2 = detailEnd, action = "open", value = item.id}
                    switch(item, detailEnd+1, x1, x2, controlRows)
                end
            end
            button(height-2*depth+1, "+ Add reactor", "add", nil, nil, nil, #state.reactors < 64, accent, depth)
            footer("Settings", "settings", nil, nil, depth)
        end
    elseif screen == "reactor" then
        local status = reading(entry)
        local value = status.reactor or {}
        ui.heading(entry.name, accent)
        local active = value.active == nil and "?" or value.active and "On" or "Off"
        if status.status ~= "ok" then active = "?" end
        put(width - 2, 1, active, 3)
        ui.style(width - 2, 1, 3, 1, 32768, active == "On" and 32 or active == "Off" and 16384 or 2)
        local columns = width >= 50 and 2 or 1
        local inset, gutter = width >= 24 and 2 or 0, columns > 1 and 2 or 0
        local span = math.floor((width - 2 * inset - gutter) / columns)
        local compact = width < 24
        local values = metrics(value,compact,height<13)
        for _,text in ipairs(extraFields(status.data)) do values[#values+1]=text end
        values[#values + 1] = (compact and "S: " or "Sensor: ") .. entry.sensor.clientId
        values[#values + 1] = "Side: " .. entry.sensor.side
        values[#values + 1] = (compact and "At: " or "Target: ") .. entry.sensor.target
        if status.target then values[#values + 1] = "Type: " .. status.target.type end
        if status.data and type(status.data.RawName)=="string" then values[#values+1]="Raw type: "..status.data.RawName end
        local position=status.data and status.data.Position or status.target and status.target.position
        if type(position)=="table" and type(position.X)=="number" and type(position.Y)=="number" and type(position.Z)=="number" then
            values[#values+1]="Position: "..number(position.X)..", "..number(position.Y)..", "..number(position.Z)
        end
        local wrapped = {}
        for _, text in ipairs(values) do
            local label,payload=text:match("^(.-:)%s+(.+)$")
            if #text>span and label and #label<=span and #payload<=span then
                wrapped[#wrapped+1]=label
                wrapped[#wrapped+1]=(#payload+2<=span and "  " or "")..payload
            else
                repeat
                    wrapped[#wrapped + 1] = text:sub(1, span)
                    text = #text > span and "  " .. text:sub(span + 1) or ""
                until text == ""
            end
        end
        values = wrapped
        local depth=math.min(api.ui.controlHeight(height),math.max(1,math.floor((height-4)/4)))
        local bottom=height-2*depth
        local statusRow = height >= 9 and bottom or nil
        local barRows = height >= 26 and 3 or height >= 18 and 2 or 1
        local barRow = height >= 13 and bottom-barRows or nil
        local pagerRow = barRow and barRow-1 or statusRow and statusRow-1 or bottom
        local bodyRows = pagerRow - 2
        local slots = bodyRows * columns
        local page = pages(#values, slots, "metrics", pagerRow)
        local count = math.min(slots, #values - (page - 1) * slots)
        local rows = math.ceil(count / columns)
        for slot = 1, count do
            local col, row = math.floor((slot - 1) / rows), (slot - 1) % rows
            local y=2+math.floor(row*bodyRows/rows)
            local spanRows=math.floor((row+1)*bodyRows/rows)-math.floor(row*bodyRows/rows)
            local x=1+inset+col*(span+gutter)
            if status.status=="ok" and row%2==0 then ui.style(x,y,span,spanRows,1,128) end
            put(x,y+math.floor((spanRows-1)/2),values[(page-1)*slots+slot],span)
        end
        if barRow then
            local fraction = math.max(0, math.min(1, (value.percent or 0) / 100))
            ui.style(2, barRow, width - 2, barRows, 1, 128)
            if value.heat then
                local filled = math.floor((width - 2) * fraction)
                if filled > 0 then ui.style(2, barRow, filled, barRows, nil,
                    status.status ~= "ok" and 128 or value.heat >= value.melting and 16384 or 32) end
                put(2, barRow+math.floor((barRows-1)/2), decimal(value.percent, 1) .. "% heat", width - 2, true)
            end
        end
        if status.status ~= "ok" then
            ui.style(1, 2, width, bodyRows, 128, state.panelColour)
            local row = statusRow or 1
            ui.text(row, status.error or "Sensor unavailable", true)
            ui.style(1, row, width, 1, 1, 16384)
        elseif statusRow then ui.text(statusRow, "Data " .. math.floor(status.age or 0) .. "s old", true) end
        switch(entry, bottom+1, nil, nil, depth)
        footer("Back", "home", "Edit", "edit", depth)
        return ui.finish(true)
    elseif screen == "edit" or screen == "settings" then
        local items = screen == "edit" and {{label = "Rename", action = "rename"}, {label = "Sensor target", action = "sensor"},
            {label = "Control output", action = "output", value = entry.id}, {label = "Raw readings", action = "raw"},
            {label = "Delete reactor", action = "delete"}} or {{label = "UI color", action = "accent"},
            {label = "Panel color", action = "panel"}, {label = "About readings", action = "about"}}
        local lines, hits, page, total = api.ui.menu(width, height, screen == "edit" and "Reactor settings" or "App settings", items,
            view.menuPage, screen == "edit" and "reactor" or "home", accent)
        view.menuPage, view.menuPages = page, total
        for _, hit in ipairs(hits) do if hit.action == "output" then hit.value = entry.id end end
        return lines, hits
    elseif screen == "palette" then
        local previewAccent = view.colourField == "accent" and view.colourDraft or accent
        local previewPanel = view.colourField == "accent" and state.panelColour or view.colourDraft
        local footerRows = api.ui.controlHeight(height)
        local preview = width >= 24 and height >= 15
        local bottom = height - footerRows - (preview and 4 or 0)
        local lines, hits = api.ui.palette(width, height, view.colourDraft, view.colourField == "accent" and "UI color" or "Panel color", bottom)
        ui.lines, ui.hits = lines, hits
        ui.style(1, 1, width, 1, api.ui.contrast(previewAccent), previewAccent)
        if preview then
            ui.style(1, bottom + 1, width, 4, api.ui.contrast(previewPanel), previewPanel)
            ui.style(1, bottom + 1, width, 1, api.ui.contrast(previewAccent), previewAccent)
            ui.text(bottom + 1, "Preview", true); ui.text(bottom + 2, "Heat: 48 036 / 58 000", true)
            ui.text(bottom + 3, "Output: 30 EU/t", true); ui.text(bottom + 4, "To melting*: 1 264", true)
        end
        button(height, "Apply", "applyPanel", nil, 1, math.floor(width / 2), true, previewAccent)
        button(height, "Cancel", "settings", nil, math.floor(width / 2) + 1, width)
    elseif screen == "rename" then
        local keyboard = view.keyboard
        api.ui.keyboard(ui, width, height, keyboard, accent,
            {{"Save","saveName",nil,keyboard.draft:find("%S")~=nil},{"Clr","clearName"},{"Back","edit"}})
    elseif screen == "delete" then
        ui.heading("Delete reactor?", accent)
        ui.text(2, entry.name, true); ui.text(3, "Unshared OFF", true)
        button(height - 1, "Confirm", "confirmDelete", nil, nil, nil, true, 16384); footer("Cancel", "edit")
    elseif screen == "raw" or screen == "about" or screen == "message" then
        local lines = {}
        if screen == "raw" then
            local status = api.getSensorReading(entry.sensor)
            local function add(text)
                text = text:gsub("[%c]", " ")
                repeat
                    if #lines >= 256 then return end
                    lines[#lines + 1], text = text:sub(1, width), text:sub(width + 1)
                until text == ""
            end
            local function visit(value, path, depth)
                if #lines >= 256 then return end
                if type(value) ~= "table" then add(path .. ": " .. tostring(value)); return end
                if depth >= 4 then add(path .. ": [deeper table]" ); return end
                local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
                if #keys == 0 and path ~= "" then add(path .. ": {}") end
                for _, key in ipairs(keys) do
                    local name = type(key) == "number" and "[" .. key .. "]" or (path == "" and "" or ".") .. key
                    visit(value[key], path .. name, depth + 1)
                    if #lines >= 256 then return end
                end
            end
            visit(status.data or {}, "", 0)
            if #lines >= 256 then lines[256] = "More fields omitted" end
            if #lines == 0 then lines[1] = status.error or "No reading yet" end
        else
            local message = screen == "about" and "Melting* is 85% of maximum heat. To melting/max shows heat headroom; negative means above that threshold. Emitted/received are the card's EU counters, not saved app totals. Old IC2 cards supply no fuel lifetime or inventory, for core or chamber. Fuel lifetime is not displayed. Extra scalar sensor fields appear when reported; nested structures remain in Raw readings. Raw readings expands nested fields. ON/OFF shows requested output; the header shows actual reactor activity." or view.message
            repeat lines[#lines + 1], message = message:sub(1, width), message:sub(width + 1) until message == ""
        end
        ui.heading(screen == "raw" and "Sensor fields" or "Information", accent)
        local slots = #lines <= height - 2 and height - 2 or height - 3
        local page = pages(#lines, slots, "info", height - 1)
        for row = 1, slots do ui.text(row + 1, (lines[(page - 1) * slots + row] or ""):gsub("[%c]", " ")) end
        footer("Back", screen == "raw" and "edit" or screen == "about" and "settings" or "messageBack")
    end
    return ui.finish()
end
function app.render(width, height, state, api, context)
    if not ready then return {"Reactors blocked", "Check OS log"} end
    return (build(width, height, state, api, context))
end
function app.handleTouch(x, y, width, height, state, api, context)
    if not ready then return false end
    local hits = context.hits
    if not hits then local _; _, hits = build(width, height, state, api, context) end
    local action, value
    for _, hit in ipairs(hits) do if hit.enabled ~= false and api.ui.hit(hit, x, y) then action, value = hit.action, hit.value; break end end
    if not action then return false end
    local view = context.view
    local entry, index = find(state, view.id)
    if action == "add" or action == "sensor" then
        local ok, err = api.pickSensor(context.windowId, action == "add" and "new" or "sensor_" .. entry.id, action == "sensor" and entry.sensor or nil, "reactor")
        if not ok then notice(view, err) end
    elseif action == "open" then view.id, view.screen, view.pages = value, "reactor", {}
    elseif action == "output" then
        entry = find(state, value or view.id)
        local key = "output_" .. entry.id
        view.routeKey, view.routeBefore = key, copy(entry.outputAddress)
        local ok, err = api.pickIO(context.windowId, key, "output", entry.outputAddress)
        if not ok then notice(view, err) end
    elseif action == "toggle" then
        entry = find(state, value or view.id)
        local output = wire(entry, api)
        if output then local ok, err = api.setOutput(logical(entry), not output.value); if not ok then notice(view, err) end end
    elseif action == "page" then view.pages[value.key] = math.max(1, math.min(value.pages, view.pages[value.key] + value.delta))
    elseif action == "previous" or action == "next" then view.menuPage = math.max(1, math.min(view.menuPages, view.menuPage + (action == "next" and 1 or -1)))
    elseif action == "rename" then view.keyboard, view.screen = {draft = entry.name, original = entry.name, page = 1, bank = "abc"}, "rename"
    elseif view.screen == "rename" and api.ui.editText(view.keyboard, action, value, 32) then return true
    elseif action == "clearName" then view.keyboard.draft = ""
    elseif action == "saveName" then
        if entry.name ~= view.keyboard.original then notice(view, "Name changed in another window", "edit")
        elseif commit(state, api, view, function() entry.name = view.keyboard.draft:gsub("^%s+", ""):gsub("%s+$", "") end) then view.screen = "edit" end
    elseif action == "accent" then
        view.colourField, view.colourDraft, view.screen = "accent", api.getAppColour(context.appName or appName), "palette"
    elseif action == "panel" then view.colourField, view.colourDraft, view.screen = "panel", state.panelColour, "palette"
    elseif action == "colour" then view.colourDraft = value
    elseif action == "applyPanel" then
        local ok, err
        if view.colourField == "accent" then
            ok, err = api.setAppColour(context.appName or appName, view.colourDraft)
            if not ok then notice(view, err) end
        else ok = commit(state, api, view, function() state.panelColour = view.colourDraft end) end
        if ok then api.invalidateAppViews(appName); view.screen = "settings" end
    elseif action == "confirmDelete" then
        local id = entry.id
        if commit(state, api, view, function() table.remove(state.reactors, index) end,
            function() return {{name = logical(entry), remove = true}} end) then
            api.unwatchSensor(appName .. "_sensor_" .. id); view.screen = "home"
        end
    elseif action == "messageBack" then view.screen = view.messageBack or "home"
    else view.screen, view.menuPage = action, 1 end
    return true
end
return app
