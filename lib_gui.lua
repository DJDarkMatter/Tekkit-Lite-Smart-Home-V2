-- CC 1.5 colour surfaces. Uses write/setTextColor/setBackgroundColor, never blit.
local Gui = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local digits = "0123456789abcdef"
local names = {"White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray",
    "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
local nextBank = {[0] = 1, [1] = 2, [2] = 0, abc = "ABC", ABC = "123", ["123"] = "abc"}
local bankName = {[0] = "abc", [1] = "ABC", [2] = "123", abc = "abc", ABC = "ABC", ["123"] = "123"}
-- Shift applies to one accepted letter, consistently across all app keyboards.
function Gui.typeKey(keyboard, key, limit)
    if type(key) ~= "string" or #keyboard.draft >= limit then return false end
    keyboard.draft = keyboard.draft .. key
    if key:match("^[A-Z]$") then
        if keyboard.bank == 1 then keyboard.bank = 0
        elseif keyboard.bank == "ABC" then keyboard.bank = "abc" end
    end
    return true
end
function Gui.editText(keyboard, action, value, limit)
    if action == "key" then Gui.typeKey(keyboard, value, limit)
    elseif action == "space" then Gui.typeKey(keyboard, " ", limit)
    elseif action == "backspace" then keyboard.draft = keyboard.draft:sub(1, -2)
    elseif action == "clearText" then keyboard.draft = ""
    elseif action == "bank" then keyboard.bank, keyboard.page = nextBank[keyboard.bank] or 0, 1
    elseif action == "keyPage" then keyboard.page = keyboard.page % keyboard.pages + 1
    else return false end
    return true
end

function Gui.editNumber(draft, key, limit)
    if key == "Clr" then return "" end
    if key == "Del" then return draft:sub(1, -2) end
    if #draft < limit and (key ~= "." or not draft:find(".", 1, true)) then
        return (draft == "0" and key ~= "." and "" or draft) .. key
    end
    return draft
end
function Gui.durationHundredths(text, minimum)
    local value = tonumber((text:gsub(",", ".")))
    if not value or value ~= value or value < 0 or value > 21474836.47 then return nil end
    local hundredths = math.floor(value * 100 + 0.5)
    if hundredths >= minimum and math.abs(value * 100 - hundredths) < 0.00001 then return hundredths end
end
function Gui.seconds(hundredths)
    local fraction = hundredths % 100
    local decimal = fraction % 10 == 0 and tostring(fraction / 10) or string.format("%02d", fraction)
    return tostring(math.floor(hundredths / 100)) .. "." .. decimal
end

function Gui.actionAt(hits, x, y)
    for _, hit in ipairs(hits) do
        if hit.enabled ~= false and Gui.hit(hit, x, y) then return hit.action, hit.value end
    end
end

-- Keep every completed choice visible; shorten long IDs rather than losing
-- the final side/target. Small windows keep their existing usable row count.
function Gui.breadcrumb(parts,width,height)
    if width<24 or height<8 then return nil end
    local values={}
    for _,value in ipairs(parts) do if value and value~="" then values[#values+1]=tostring(value):gsub("[%c]"," ") end end
    if #values==0 then return nil end
    if #table.concat(values," / ")>width then
        local budget=math.max(1,math.floor((width-3*(#values-1))/#values))
        for i,value in ipairs(values) do if #value>budget then values[i]=value:sub(1,math.max(0,budget-2))..".." end end
    end
    return table.concat(values," / "):sub(1,width)
end
function Gui.colourName(colour)
    for index = 0, 15 do if colour == 2 ^ index then return names[index + 1] end end
    return "Unknown"
end
function Gui.contrast(colour)
    return (colour == 128 or colour == 1024 or colour == 2048 or colour == 4096
        or colour == 8192 or colour == 16384 or colour == 32768) and 1 or 32768
end
function Gui.hit(hit, x, y)
    return x >= hit.x1 and x <= hit.x2 and y >= (hit.y1 or hit.y) and y <= (hit.y2 or hit.y)
end

function Gui.controlHeight(height)
    return height < 9 and 1 or math.min(6, math.max(2, math.floor(height / 5)))
end

-- Give the same space to a row of controls, including its touch regions.
-- Rows with graphs, artwork or multi-row tiles retain their internal geometry.
local function expandRows(lines, hits, width, height)
    local target = Gui.controlHeight(height)
    if target == 1 then return end
    target = math.max(target, math.min(8, math.floor(height / 4)))
    local occupied, locked, controls, sizes = {}, {}, {}, {}
    for y = 1, height do occupied[y] = lines[y] and lines[y]:find("%S") ~= nil end
    for _, paint in ipairs(lines.styles) do
        if paint.y ~= 1 or paint.height ~= height or paint.width ~= width then
            for y = paint.y, math.min(height, paint.y + (paint.height or 1) - 1) do occupied[y] = true end
        end
    end
    for _, hit in ipairs(hits) do
        local first, last = hit.y1 or hit.y, hit.y2 or hit.y
        for y = first, last do
            occupied[y] = true
            if last > first then locked[y] = true end
        end
        if first == last and hit.paint then controls[first] = true end
    end
    local free = height
    for y = 1, height do
        sizes[y] = occupied[y] and 1 or 0
        free = free - sizes[y]
    end
    if free == 0 then return end
    local remaining = free
    -- Upgrade the footer first when there is only a little spare room.
    for depth = 2, target do
        for y = height, 1, -1 do
            if remaining > 0 and controls[y] and not locked[y] then
                sizes[y], remaining = depth, remaining - 1
            end
        end
    end
    if remaining == free then return end
    local first, last, centre, rows = {}, {}, {}, {}
    local row, blanks = 1, 0
    local empty = string.rep(" ", width)
    for y = 1, height do
        local size = sizes[y]
        if not occupied[y] then
            size = math.floor((blanks + 1) * remaining / free) - math.floor(blanks * remaining / free)
            blanks = blanks + 1
        end
        first[y], last[y] = row, row + size - 1
        centre[y] = row + math.floor((size - 1) / 2)
        for out = first[y], last[y] do rows[out] = out == centre[y] and lines[y] or empty end
        row = row + size
    end
    for y = 1, height do lines[y] = rows[y] or empty end
    for _, paint in ipairs(lines.styles) do
        local bottom = math.min(height, paint.y + (paint.height or 1) - 1)
        if first[paint.y] and last[bottom] then
            paint.y, paint.height = first[paint.y], last[bottom] - first[paint.y] + 1
        end
    end
    for _, hit in ipairs(hits) do
        local top, bottom = hit.y1 or hit.y, hit.y2 or hit.y
        hit.y1, hit.y2 = first[top], last[bottom]
        if hit.y then hit.y = centre[hit.y] end
    end
    Work.check(height * 4 + #lines.styles * 4 + #hits * 4)
end

local function labelAt(lines, x1, x2, y, label)
    local span = x2 - x1 + 1
    label = label:sub(1, span)
    local inset = math.floor((span - #label) / 2)
    lines[y] = lines[y]:sub(1, x1 - 1) .. string.rep(" ", inset) .. label
        .. string.rep(" ", span - inset - #label) .. lines[y]:sub(x2 + 1)
end

local function splitLine(value, width)
    local cut = #value > width and value:sub(1, width):match("^.*()%s")
    if cut and cut > 1 then return value:sub(1, cut - 1), value:sub(cut + 1) end
    return value:sub(1, width), value:sub(width + 1)
end

local function wrapButtons(lines, hits)
    for _, hit in ipairs(hits) do
        if hit.paint and hit.y2 > hit.y1 and #hit.label > hit.x2 - hit.x1 + 1 then
            local wrapped, rest = {}, hit.label
            local span = hit.x2 - hit.x1 + 1
            for _ = hit.y1, hit.y2 do
                wrapped[#wrapped+1], rest = splitLine(rest, span)
                if rest == "" then break end
            end
            if rest ~= "" and span >= 4 then wrapped[#wrapped] = wrapped[#wrapped]:sub(1, span - 2) .. ".." end
            labelAt(lines, hit.x1, hit.x2, hit.y, "")
            hit.y = hit.y1 + math.floor((hit.y2-hit.y1+1-#wrapped)/2)
            for i, line in ipairs(wrapped) do labelAt(lines, hit.x1, hit.x2, hit.y + i - 1, line) end
        end
    end
end

-- Use a visible seam for touching controls of the same color. Full-width
-- neutral rows can alternate fills; other controls keep their assigned color.
local function separateButtons(lines, hits, height)
    local starts, ends, empty, striped = {}, {}, {}, {}
    local function seam(hit, x, y, w, h)
        lines.styles[#lines.styles + 1] = {x=x,y=y,width=w,height=h,bg=Gui.contrast(hit.paint.bg)}
    end
    local function blank(x1, x2, first, last)
        for y = first, last do
            if lines[y]:sub(x1, x2):find("%S") then return false end
        end
        return true
    end
    for _, hit in ipairs(hits) do
        if hit.paint then
            local top, bottom = hit.y1 or hit.y, hit.y2 or hit.y
            starts[top], ends[bottom] = starts[top] or {}, ends[bottom] or {}
            table.insert(starts[top], hit); table.insert(ends[bottom], hit)
        end
    end
    for y = 1, height do
        local row = starts[y]
        if row then
            table.sort(row, function(a,b) return a.x1 < b.x1 end)
            for index, hit in ipairs(row) do
                local paint = hit.paint
                local left = row[index - 1]
                local above
                for _, previous in ipairs(ends[y - 1] or empty) do
                    if previous.x1 <= hit.x2 and previous.x2 >= hit.x1 and previous.paint.bg == paint.bg then
                        above = previous
                        break
                    end
                end
                if above and (paint.bg == 128 or paint.bg == 256) then
                    paint.bg = paint.bg == 128 and 256 or 128
                    paint.fg = hit.enabled == false and (paint.bg == 128 and 256 or 128) or Gui.contrast(paint.bg)
                elseif above then
                    local x1, x2 = math.max(above.x1, hit.x1), math.min(above.x2, hit.x2)
                    if blank(x1,x2,y,y) then seam(hit,x1,y,x2-x1+1,1)
                    elseif blank(x1,x2,y-1,y-1) then seam(above,x1,y-1,x2-x1+1,1)
                    elseif not striped[above] then
                        if blank(hit.x1,hit.x1,y,y) then seam(hit,hit.x1,y,1,1) end
                        if blank(hit.x2,hit.x2,y,y) then seam(hit,hit.x2,y,1,1) end
                        striped[hit] = true
                    end
                end
                if left and left.x2 + 1 == hit.x1 and left.paint.bg == paint.bg then
                    local bottom = math.min(left.y2 or left.y, hit.y2 or hit.y)
                    if blank(hit.x1,hit.x1,y,bottom) then seam(hit,hit.x1,y,1,bottom-y+1)
                    elseif blank(left.x2,left.x2,y,bottom) then seam(left,left.x2,y,1,bottom-y+1)
                    elseif paint.bg == 128 or paint.bg == 256 then
                        paint.bg = paint.bg == 128 and 256 or 128
                        paint.fg = Gui.contrast(paint.bg)
                    end
                end
            end
        end
    end
end

function Gui.finish(lines, width, height, fixed)
    local hits = lines.hits or {}
    lines.touchLayout = true
    if #hits > 0 then
        if not fixed then expandRows(lines, hits, width, height) end
        wrapButtons(lines, hits)
        separateButtons(lines, hits, height)
    end
    return lines, hits
end

local function sameValue(left, right, depth)
    if left == right then return true end
    if depth == 0 or type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if not sameValue(value, right[key], depth - 1) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

function Gui.sameHits(left, right)
    if #left ~= #right then return false end
    for i, hit in ipairs(left) do
        local other = right[i]
        if hit.x1 ~= other.x1 or hit.x2 ~= other.x2 or (hit.y1 or hit.y) ~= (other.y1 or other.y)
            or (hit.y2 or hit.y) ~= (other.y2 or other.y) or hit.action ~= other.action
            or hit.enabled ~= other.enabled or not sameValue(hit.value, other.value, 8) then return false end
    end
    return true
end

local blockDigits = {
    ["0"] = {"111","101","101","101","111"}, ["1"] = {"010","110","010","010","111"},
    ["2"] = {"111","001","111","100","111"}, ["3"] = {"111","001","111","001","111"},
    ["4"] = {"101","101","111","001","001"}, ["5"] = {"111","100","111","001","111"},
    ["6"] = {"111","100","111","101","111"}, ["7"] = {"111","001","001","001","001"},
    ["8"] = {"111","101","111","101","111"}, ["9"] = {"111","101","111","001","111"},
    [":"] = {"0","1","0","1","0"}, ["."] = {"0","0","0","0","1"},
    ["d"] = {"001","001","111","101","111"}, [" "] = {"0","0","0","0","0"},
}

-- App widgets return text plus clipped colour rectangles, sharing geometry with hits.
function Gui.content(width, height)
    local ui = {lines = {styles = {}}, hits = {}}
    ui.lines.hits = ui.hits
    for y = 1, height do ui.lines[y] = string.rep(" ", width); Work.check(width) end
    function ui.style(x, y, w, h, fg, bg)
        local paint = {x = x, y = y, width = w, height = h, fg = fg, bg = bg}
        ui.lines.styles[#ui.lines.styles + 1] = paint
        Work.check(w * h)
        return paint
    end
    function ui.text(y, text, centred)
        if y < 1 or y > height then return end
        text = tostring(text):sub(1, width)
        local left = centred and math.floor((width - #text) / 2) or 0
        ui.lines[y] = string.rep(" ", left) .. text .. string.rep(" ", width - left - #text)
    end
    function ui.readout(y, value, available, foreground, background)
        local glyphs, span = {}, -1
        for i = 1, #value do
            local glyph = blockDigits[value:sub(i, i)]
            if not glyph then return 0 end
            glyphs[i], span = glyph, span + #glyph[1] + 1
        end
        if span < 1 then return 0 end
        local scale = math.floor(math.min((width - 4) / span, available / 5))
        if scale < 1 then return 0 end
        local x = 1 + math.floor((width - span * scale) / 2)
        ui.style(1, y, width, 5 * scale, nil, background)
        for _, glyph in ipairs(glyphs) do
            for row, pixels in ipairs(glyph) do
                for column = 1, #pixels do
                    if pixels:sub(column, column) == "1" then
                        ui.style(x + (column - 1) * scale, y + (row - 1) * scale, scale, scale, nil, foreground)
                    end
                end
            end
            x = x + (#glyph[1] + 1) * scale
        end
        return 5 * scale
    end
    function ui.heading(text, accent)
        ui.text(1, text)
        ui.style(1, 1, width, 1, Gui.contrast(accent or 128), accent or 128)
    end
    function ui.button(y, label, action, x1, x2, enabled, bg, fg, value, rows)
        x1, x2 = x1 or 1, x2 or width
        rows = rows or 1
        local middle = y + math.floor((rows - 1) / 2)
        labelAt(ui.lines, x1, x2, middle, label)
        bg = enabled == false and 256 or bg or 128
        local paint = ui.style(x1, y, x2 - x1 + 1, rows, enabled == false and 128 or fg or Gui.contrast(bg), bg)
        local hit = {x1 = x1, x2 = x2, y = middle, y1 = y, y2 = y + rows - 1,
            action = action, value = value, enabled = enabled, paint = paint, label = label}
        ui.hits[#ui.hits + 1] = hit
        return hit
    end
    function ui.finish(fixed)
        ui.lines.hits = ui.hits
        return Gui.finish(ui.lines, width, height, fixed)
    end
    return ui
end
function Gui.menu(width, height, title, items, page, back, accent)
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    local slots = #items <= height - 2 and height - 2 or height - 3
    local pages = math.max(1, math.ceil(#items / slots))
    page = math.max(1, math.min(page or 1, pages))
    ui.heading(title .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), accent)
    local inset = width >= 24 and 1 or 0
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then ui.button(row + 1, item.label, item.action, 1 + inset, width - inset, item.enabled) end
    end
    if pages > 1 then
        local half = math.floor(width / 2)
        ui.button(height - 1, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 1, "Next >", "next", half + 1, width, page < pages)
    end
    ui.button(height, "Back", back)
    ui.finish()
    return ui.lines, ui.hits, page, pages
end
function Gui.palette(width, height, current, title, swatchBottom)
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    ui.heading(title or "UI color", 128)
    -- Existing apps may reserve rows 10 and onward for their own previews.
    local adaptive = swatchBottom ~= nil
    local footer = adaptive and math.min(Gui.controlHeight(height), height - 5) or 1
    local bottom = swatchBottom or (adaptive and height - footer or 1 + 4 * math.min(2, math.floor((height-2)/4)))
    local available = bottom - 1
    local rowGap = available >= 11 and 1 or 0
    local rows = available - rowGap * 3
    local short = {"White", "Orange", "Mag.", "Sky", "Yellow", "Lime", "Pink", "Gray", "L.gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
    for index = 0, 15 do
        local col, row = index % 4, math.floor(index / 4)
        local x = 1 + math.floor(col * (width + 1) / 4)
        local right = math.floor((col + 1) * (width + 1) / 4) - 1
        local y = 2 + math.floor(row * rows / 4) + row * rowGap
        local depth = math.floor((row + 1) * rows / 4) - math.floor(row * rows / 4)
        local colour = 2 ^ index
        local label = colour == current and "*" or right - x >= 5 and short[index + 1] or ""
        local hit = ui.button(y, label, "colour", x, right, true, colour, nil, colour, depth)
        -- A black swatch needs a visible edge against the palette background.
        if colour == 32768 then
            ui.style(x, y, 1, depth, nil, 128)
            ui.style(right, y, 1, depth, nil, 128)
        end
        hit.paint = nil
    end
    if not swatchBottom then
        ui.button(height - footer + 1, "Back", "cancel", nil, nil, nil, nil, nil, nil, footer)
        return ui.finish(true)
    end
    return ui.lines, ui.hits
end
local letterRows = {"qwertyuiop", "asdfghjkl", "zxcvbnm"}
local symbols = [=[1234567890-_/.:!?+()@#&=,%*'"$^[]{}<>\|;`~]=]
function Gui.keyboard(ui, width, height, k, accent, footer)
    local columns = math.min(10, math.floor(width / 2))
    local mode = bankName[k.bank] or "abc"
    local chars = k.symbols or symbols
    local pages = mode == "123" and math.ceil(#chars / (columns * 3)) or math.ceil(10 / columns)
    k.page, k.pages = math.max(1, math.min(k.page or 1, pages)), pages
    ui.heading(k.draft == "" and "Type here" or k.draft:sub(-width), accent)
    local keyWidth = math.floor(width / columns)
    local controlRows = math.min(Gui.controlHeight(height), math.max(1, math.floor((height - 4) / 4)))
    local gap, rowGap = width >= 30 and 1 or 0, height - 2 * controlRows >= 8 and 1 or 0
    local available = height - 1 - 2 * controlRows + rowGap
    for row = 1, 3 do
        local start = (k.page - 1) * columns + 1
        local keys = letterRows[row]:sub(start, start + columns - 1)
        if mode == "ABC" then keys = keys:upper()
        elseif mode == "123" then
            start = ((k.page - 1) * 3 + row - 1) * columns + 1
            keys = chars:sub(start, start + columns - 1)
        end
        local left = 1 + math.floor((width - #keys * keyWidth + gap) / 2)
        local y1 = 2 + math.floor((row - 1) * available / 3)
        local y2 = 1 + math.floor(row * available / 3) - rowGap
        for column = 1, #keys do
            local x1 = left + (column - 1) * keyWidth
            local span = keyWidth - gap
            local key = keys:sub(column, column)
            local bg = (row + column) % 2 == 0 and 128 or 256
            ui.button(y1, key, "key", x1, x1 + span - 1, true, bg, nil, key, y2 - y1 + 1)
        end
    end
    local controls = {{bankName[nextBank[k.bank]] or "ABC", "bank"},
        {width >= 20 and "Space" or "Sp", "space"}, {"Del", "backspace"}}
    if pages > 1 then controls[4] = {k.page .. "/" .. pages, "keyPage"} end
    for index, row in ipairs(controls) do
        ui.button(height - 2 * controlRows + 1, row[1], row[2], 1 + math.floor((index - 1) * width / #controls),
            math.floor(index * width / #controls), true, row[2] == "bank" and accent or nil, nil, nil, controlRows)
    end
    footer = footer or {{"Set", "saveText"}, {"Clr", "clearText"}, {"Back", k.back}}
    for index, row in ipairs(footer) do
        ui.button(height - controlRows + 1, row[1], row[2], 1 + math.floor((index - 1) * width / #footer),
            math.floor(index * width / #footer), row[4], index == 1 and accent or nil, nil, row[3], controlRows)
    end
end

-- Common app forms keep drawing and hit regions together at 12x6 and above.
function Gui.form(width,height,view,accent,background,panel)
    local ui=Gui.content(width,height); view.pages=view.pages or {}
    background,panel=background or 32768,panel or 128
    ui.style(1,1,width,height,Gui.contrast(background),background)
    function ui.put(x,y,value,span,center)
        if y<1 or y>height or span<1 then return end
        local text=tostring(value):gsub("[%c]"," "):sub(1,span)
        if center then x=x+math.max(0,math.floor((span-#text)/2)) end
        ui.lines[y]=ui.lines[y]:sub(1,x-1)..text..ui.lines[y]:sub(x+#text)
    end
    function ui.action(y,text,action,value,x1,x2,enabled,bg)
        ui.button(y,text,action,x1,x2,enabled,bg or panel,nil,value)
    end
    function ui.footer(rows, depth)
        -- A screen can replace the default Back footer supplied by info().
        for i=#ui.hits,1,-1 do if (ui.hits[i].y2 or ui.hits[i].y)==height then table.remove(ui.hits,i) end end
        depth=depth or 1
        for i,row in ipairs(rows) do
            ui.button(height-depth+1,row[1],row[2],1+math.floor((i-1)*width/#rows),math.floor(i*width/#rows),row[4],row[5] or panel,nil,row[3],depth)
        end
    end
    function ui.page(key,count,slots,y,draw)
        local pages=math.max(1,math.ceil(count/slots))
        local current=math.max(1,math.min(view.pages[key] or 1,pages)); view.pages[key]=current
        if pages>1 and draw~=false then
            local wing=math.max(2,math.floor(width/4))
            ui.action(y,"<","page",{key=key,page=current-1},1,wing,current>1)
            ui.action(y,">","page",{key=key,page=current+1},width-wing+1,width,current<pages)
            ui.put(wing+1,y,current.."/"..pages,width-2*wing,true)
        end
        return (current-1)*slots,current,pages
    end
    function ui.menu(title,rows,key,footer)
        ui.heading(title,accent)
        local slots=#rows<=height-2 and height-2 or height-3
        local first=ui.page(key,#rows,slots,height-1)
        for i=1,slots do local row=rows[first+i]; if row then ui.action(i+1,row[1],row[2],row[3],nil,nil,row[4],row[5]) end end
        ui.footer(footer or {{"Back","home"}})
    end
    function ui.info(title,lines,key,back)
        local columns=1
        local half=math.floor((width-1)/2)
        if width>=50 and height>=12 and #lines>=6 then
            columns=2
            for _, line in ipairs(lines) do
                if #tostring(line)>half then columns=1; break end
            end
        end
        local span=columns==2 and half or width
        local wrapped={}
        for _,line in ipairs(lines) do
            line=tostring(line):gsub("[%c]"," ")
            repeat
                wrapped[#wrapped+1],line=splitLine(line,span)
            until line==""
        end
        ui.heading(title,accent)
        local room=#wrapped<=(height-2)*columns and height-2 or height-3
        local slots=room*columns
        local first=ui.page(key,#wrapped,slots,height-1)
        local count=math.min(slots,#wrapped-first)
        local rows=math.ceil(count/columns)
        local step=rows>0 and math.min(3,math.floor(room/rows)) or 1
        for i=1,count do
            local col,row=math.floor((i-1)/rows),(i-1)%rows
            local x,y=1+col*(span+1),2+row*step
            if step>1 and row%2==0 then ui.style(x,y,span,step,Gui.contrast(panel),panel) end
            local line=wrapped[first+i]
            local inset=width>=24 and step>1 and #line<span and 1 or 0
            ui.put(x+inset,y+math.floor((step-1)/2),line,span-inset)
        end
        ui.footer({{"Back",back}})
    end
    function ui.numberPad(title,draft,back,decimal)
        ui.heading(title,accent); ui.put(1,2,draft=="" and "0" or draft,width,true)
        local footer = math.min(Gui.controlHeight(height), math.max(1, math.floor((height - 3) / 4)))
        local keyHeight = height - 2 - footer
        local primary = accent or 2048
        local alternate = panel == primary and (primary == 128 and 256 or 128) or panel
        local keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", decimal and "." or "Clr", "0", "Del"}
        for i, key in ipairs(keys) do
            local column, row = (i - 1) % 4, math.floor((i - 1) / 4)
            local x1, x2 = 1 + math.floor(column * width / 4), math.floor((column + 1) * width / 4)
            local y1, y2 = 3 + math.floor(row * keyHeight / 3), 2 + math.floor((row + 1) * keyHeight / 3)
            local bg = (column + row) % 2 == 0 and primary or alternate
            ui.button(y1, key, "digit", x1, x2, true, bg, nil, key, y2 - y1 + 1)
        end
        ui.footer({{"Set","setNumber"},{"Back",back}}, footer)
    end
    function ui.keyboard(k)
        Gui.keyboard(ui, width, height, k, accent)
    end
    return ui
end
function Gui.code(colour, fallback)
    for index = 0, 15 do if colour == 2 ^ index then return digits:sub(index + 1, index + 1) end end
    return fallback
end
function Gui.pack(row)
    local runs, x = {}, 1
    while x <= #row do
        local last = x
        while last < #row and last - x < 254 and row:sub(last + 1, last + 1) == row:sub(x, x) do last = last + 1 end
        runs[#runs + 1] = string.format("%02x", last - x + 1) .. row:sub(x, x)
        Work.check(last - x + 1)
        x = last + 1
    end
    return table.concat(runs)
end
function Gui.unpack(encoded, width)
    if type(encoded) ~= "string" or #encoded % 3 ~= 0 then return nil end
    local parts, length = {}, 0
    for x = 1, #encoded, 3 do
        local count, colour = tonumber(encoded:sub(x, x + 1), 16), encoded:sub(x + 2, x + 2)
        if not count or count < 1 or not colour:match("^[0-9a-f]$") then return nil end
        length = length + count
        if length > width then return nil end
        parts[#parts + 1] = string.rep(colour, count)
    end
    if length ~= width then return nil end
    return table.concat(parts)
end
function Gui.new(width, height, foreground, background)
    local surface = {lines = {}, foreground = {}, background = {}}
    for y = 1, height do
        surface.lines[y] = string.rep(" ", width)
        surface.foreground[y] = string.rep(Gui.code(foreground, "0"), width)
        surface.background[y] = string.rep(Gui.code(background, "f"), width)
        Work.check(width)
    end
    local function replace(row, x, value) return row:sub(1, x - 1) .. value .. row:sub(x + #value) end
    function surface.style(x, y, w, h, fg, bg)
        local first, last = math.max(1, x), math.min(width, x + w - 1)
        if last < first then return end
        for row = math.max(1, y), math.min(height, y + h - 1) do
            local f, b = Gui.code(fg), Gui.code(bg)
            if f then surface.foreground[row] = replace(surface.foreground[row], first, string.rep(f, last - first + 1)) end
            if b then surface.background[row] = replace(surface.background[row], first, string.rep(b, last - first + 1)) end
            Work.check(last - first + 1)
        end
    end
    function surface.write(x, y, value, fg, bg, limit)
        if y < 1 or y > height then return end
        local text = tostring(value or ""):sub(1, limit or width)
        local first, last = math.max(1, x), math.min(width, x + #text - 1)
        if last < first then return end
        text = text:sub(first - x + 1, last - x + 1)
        surface.lines[y] = replace(surface.lines[y], first, text)
        surface.style(first, y, #text, 1, fg, bg)
    end
    function surface.fill(x, y, w, h, fg, bg)
        for row = math.max(1, y), math.min(height, y + h - 1) do surface.write(x, row, string.rep(" ", w), fg, bg) end
    end
    function surface.frame()
        local fg, bg = {}, {}
        for y = 1, height do fg[y], bg[y] = Gui.pack(surface.foreground[y]), Gui.pack(surface.background[y]) end
        return surface.lines, fg, bg
    end
    return surface
end
function Gui.drawRow(screen, y, text, fg, bg, colour, paint)
    local setFG, setBG = screen.setTextColor or screen.setTextColour, screen.setBackgroundColor or screen.setBackgroundColour
    paint = paint or {}
    local x = 1
    screen.setCursorPos(1, y)
    while x <= #text do
        local last, f, b = x, fg:sub(x, x), bg:sub(x, x)
        while last < #text and fg:sub(last + 1, last + 1) == f and bg:sub(last + 1, last + 1) == b do last = last + 1 end
        local foreground, background = 2 ^ tonumber(f, 16), 2 ^ tonumber(b, 16)
        if not colour then
            background = (b == "0" or b == "8") and 1 or 32768
            foreground = background == 1 and 32768 or 1
        end
        if setFG and paint.fg ~= foreground then setFG(foreground); paint.fg = foreground end
        if setBG and paint.bg ~= background then setBG(background); paint.bg = background end
        screen.write(text:sub(x, last))
        x = last + 1
    end
end
return Gui
