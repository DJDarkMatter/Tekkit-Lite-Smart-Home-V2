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

local secondaryActions = {settings=true, edit=true, menu=true, back=true, home=true,
    cancel=true, close=true, about=true, status=true, page=true, prev=true, previous=true, next=true,
    earlier=true, later=true, stopwatchMode=true}
local secondaryLabels = {Settings=true, Edit=true, Menu=true, More=true, Back=true, Cancel=true, Close=true, Status=true}

Gui.secondaryHeight = 1

local function isSecondary(label, action)
    return secondaryActions[action] or secondaryLabels[label]
end

-- Give the same space to a row of controls, including its touch regions.
-- Rows with graphs, artwork or multi-row tiles retain their internal geometry.
local function expandRows(lines, hits, width, height)
    local target = math.min(3, Gui.controlHeight(height))
    if target == 1 then return end
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
        if first == last and hit.paint and not hit.secondary then controls[first] = true end
    end
    local free = height
    for y = 1, height do
        sizes[y] = occupied[y] and 1 or 0
        free = free - sizes[y]
    end
    if free == 0 then return end
    local count = 0
    for y = 1, height do if controls[y] and not locked[y] then count = count + 1 end end
    if count == 0 then return end
    local added = math.min(target - 1, math.floor(free / count))
    if added == 0 then return end
    -- A partially filled group of taller rows makes equal choices look different.
    for y = 1, height do if controls[y] and not locked[y] then sizes[y] = 1 + added end end
    local remaining = free - added * count
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

local function styleSecondary(lines, hits)
    local depth = Gui.secondaryHeight
    for _, hit in ipairs(hits) do
        if hit.secondary and hit.paint then
            local paint = hit.paint
            paint.bg, paint.fg = 32768, hit.enabled == false and 128 or 256
            if hit.y2 - hit.y1 + 1 > depth then
                labelAt(lines, hit.x1, hit.x2, hit.y, "")
                hit.y1 = hit.y2 - depth + 1
                hit.y = hit.y1 + math.floor((depth - 1) / 2)
                paint.y, paint.height = hit.y1, depth
                labelAt(lines, hit.x1, hit.x2, hit.y, hit.label)
            end
        end
    end
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

function Gui.finish(lines, width, height, fixed)
    local hits = lines.hits or {}
    lines.touchLayout = true
    if #hits > 0 then
        styleSecondary(lines, hits)
        if not fixed and not lines.fixedLayout then
            expandRows(lines, hits, width, height)
            styleSecondary(lines, hits)
        end
        wrapButtons(lines, hits)
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
    function ui.put(x, y, value, span, centred)
        if y < 1 or y > height or span < 1 then return end
        local text = tostring(value):gsub("[%c]", " "):sub(1, span)
        if centred then x = x + math.floor((span - #text) / 2) end
        ui.lines[y] = ui.lines[y]:sub(1, x - 1) .. text .. ui.lines[y]:sub(x + #text)
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
    function ui.band(x, y, span, text, bg, centred)
        bg = bg or 128
        local pad = not centred and span >= 14 and #text < span and 1 or 0
        ui.style(x, y, span, 1, Gui.contrast(bg), bg)
        ui.put(x + pad, y, text, span - pad, centred)
    end
    function ui.heading(text, accent)
        ui.text(1, "")
        local background = accent ~= 2048 and accent ~= 32768 and accent or 128
        ui.band(1, 1, width, text, background)
    end
    function ui.button(y, label, action, x1, x2, enabled, bg, fg, value, rows)
        x1, x2 = x1 or 1, x2 or width
        rows = rows or 1
        local middle = y + math.floor((rows - 1) / 2)
        labelAt(ui.lines, x1, x2, middle, label)
        bg = enabled == false and 32768 or bg or 128
        local paint = ui.style(x1, y, x2 - x1 + 1, rows, enabled == false and 256 or fg or Gui.contrast(bg), bg)
        local hit = {x1 = x1, x2 = x2, y = middle, y1 = y, y2 = y + rows - 1,
            action = action, value = value, enabled = enabled, paint = paint, label = label,
            secondary = isSecondary(label, action)}
        ui.hits[#ui.hits + 1] = hit
        return hit
    end
    function ui.buttonRow(y, items, depth)
        local count = #items
        if count == 0 then return end
        local gap = width >= count * 7 - 1 and 1 or 0
        local span = math.floor((width - (count - 1) * gap) / count)
        local gutters = width - count * span
        for i, item in ipairs(items) do
            local left = 1 + (i - 1) * span + math.floor((i - 1) * gutters / math.max(1, count - 1))
            ui.button(y, item[1], item[2], left, left + span - 1, item[4], item[5], nil, item[3], depth)
        end
    end
    -- Ordered lists stay in one column. Short sets of actions can opt into
    -- two columns when their labels fit. Gaps are outside the touch targets.
    function ui.choices(top, bottom, items, tiles, panel, pageSize)
        if #items == 0 then return end
        panel = panel or 128
        local inset = width >= 32 and 2 or width >= 20 and 1 or 0
        local span = width - 2 * inset
        if tiles then span = math.min(span, #items == 1 and 30 or 68) end
        local left = 1 + math.floor((width - span) / 2)
        local columns = 1
        if tiles and width >= 28 and #items > 1 then
            columns = 2
            for _, item in ipairs(items) do
                if #item[1] > math.floor((span - 2) / 2) then columns = 1; break end
            end
        end
        local rows = math.ceil((pageSize or #items) / columns)
        local room = bottom - top + 1
        if not tiles and room >= rows * 3 then top, room = top + 1, room - 1 end
        local gap = room >= rows * 3 - 1 and 1 or 0
        local depth = math.min(3, math.floor((room - (rows - 1) * gap) / rows))
        local cellWidth = columns == 2 and math.floor((span - 2) / 2) or span
        local horizontal = span - columns * cellWidth
        if tiles then top = top + math.floor((room - rows * depth - (rows - 1) * gap) / 2) end
        for i, item in ipairs(items) do
            local row, col = math.floor((i - 1) / columns), (i - 1) % columns
            local x1 = left + col * (cellWidth + horizontal)
            local x2 = x1 + cellWidth - 1
            local y = top + row * (depth + gap)
            local secondary = isSecondary(item[1], item[2])
            local buttonDepth = secondary and 1 or depth
            if secondary then y = y + math.floor((depth - 1) / 2) end
            local bg = item[5] or (gap == 0 and panel == 128 and (rows - row) % 2 == 0 and 32768 or panel)
            local hit = ui.button(y, item[1], item[2], x1, x2, item[4], bg, nil, item[3], buttonDepth)
            if not tiles then
                local pad = #item[1] < x2 - x1 + 1 and 1 or 0
                labelAt(ui.lines, x1, x2, hit.y, "")
                ui.put(x1 + pad, hit.y, item[1], x2 - x1 + 1 - pad)
            end
        end
        ui.lines.fixedLayout = true
    end
    function ui.pickerList(top, items, page)
        local room = height - top
        local paged = #items > room
        local slots = math.max(1, room - (paged and 1 or 0))
        local pages = math.max(1, math.ceil(#items / slots))
        page = math.max(1, math.min(page, pages))
        local first = (page - 1) * slots
        local size = math.min(#items, slots)
        local rows = {}
        local swatches = items[#items] and items[#items].colour
        for i = first + 1, math.min(first + slots, #items) do
            local item = items[i]
            rows[#rows + 1] = {(swatches and "  " or "") .. item.label, "select", item.value, item.enabled, 128}
        end
        local hitStart = #ui.hits
        local bottom = math.min(height - (paged and 2 or 1), top + 3 * size - 1)
        ui.choices(top, bottom, rows, false, nil, size)
        for i = 1, #rows do
            local item, hit = items[first + i], ui.hits[hitStart + i]
            if item.colour then ui.style(hit.x1, hit.y1, 2, hit.y2 - hit.y1 + 1, nil, item.colour) end
        end
        if paged then
            ui.buttonRow(height - 1, {{"< Prev", "prev", nil, page > 1}, {"Next >", "next", pages, page < pages}})
        end
        ui.buttonRow(height, {{"Back", "back"}, {"Cancel", "cancel"}})
        return page, pages
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
    local visible = {}
    for i = (page - 1) * slots + 1, math.min(page * slots, #items) do
        local item = items[i]
        visible[#visible + 1] = {item.label, item.action, item.value, item.enabled, item.bg}
    end
    ui.choices(2, height - (pages > 1 and 2 or 1), visible, false, nil, math.min(#items, slots))
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
    local depth = math.floor((available - rowGap * 3) / 4)
    local yStart = 2 + math.floor((available - 4 * depth - 3 * rowGap) / 2)
    local columnGap = width >= 15 and 1 or 0
    local swatchWidth = math.floor((width - 3 * columnGap) / 4)
    local xStart = 1 + math.floor((width - 4 * swatchWidth - 3 * columnGap) / 2)
    local short = {"White", "Orange", "Mag.", "Sky", "Yellow", "Lime", "Pink", "Gray", "L.gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
    for index = 0, 15 do
        local col, row = index % 4, math.floor(index / 4)
        local x = xStart + col * (swatchWidth + columnGap)
        local right = x + swatchWidth - 1
        local y = yStart + row * (depth + rowGap)
        local colour = 2 ^ index
        local label = colour == current and "*" or right - x >= 5 and short[index + 1] or ""
        local hit = ui.button(y, label, "colour", x, right, true, colour, nil, colour, depth)
        -- A black swatch needs a visible edge against the palette background.
        if colour == 32768 then
            ui.style(x, y, 1, depth, nil, 128)
            if swatchWidth >= 3 then ui.style(right, y, 1, depth, nil, 128) end
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
    local caption = k.masked and string.rep("*", math.min(#k.draft, width)) or k.draft:sub(-width)
    ui.heading(caption == "" and (k.prompt or "Type here") or caption, accent)
    local controlRows = math.min(3, math.max(1, math.floor((height - 2) / 6)))
    local footerGap = height >= 12 and 1 or 0
    local available = height - 1 - 2 * controlRows - footerGap
    local gap, rowGap = width >= 30 and 1 or 0, available >= 9 and 1 or 0
    local keyWidth = math.floor((width - (columns - 1) * gap) / columns)
    local keyDepth = math.floor((available - 3 * rowGap) / 3)
    local spare = available - 3 * (keyDepth + rowGap)
    local top = 2 + math.ceil(spare / 2)
    for row = 1, 3 do
        local start = (k.page - 1) * columns + 1
        local keys = letterRows[row]:sub(start, start + columns - 1)
        if mode == "ABC" then keys = keys:upper()
        elseif mode == "123" then
            start = ((k.page - 1) * 3 + row - 1) * columns + 1
            keys = chars:sub(start, start + columns - 1)
        end
        local left = 1 + math.floor((width - #keys * (keyWidth + gap) + gap) / 2)
        local y = top + (row - 1) * (keyDepth + rowGap)
        for column = 1, #keys do
            local x1 = left + (column - 1) * (keyWidth + gap)
            local key = keys:sub(column, column)
            local bg = (gap > 0 or (row + column) % 2 == 0) and 128 or 256
            ui.button(y, key, "key", x1, x1 + keyWidth - 1, true, bg, nil, key, keyDepth)
        end
    end
    local controls = {{bankName[nextBank[k.bank]] or "ABC", "bank", nil, true, accent},
        {width >= 20 and "Space" or "Sp", "space"}, {"Del", "backspace"}}
    if pages > 1 then controls[4] = {k.page .. "/" .. pages, "keyPage"} end
    ui.buttonRow(height - 2 * controlRows + 1 - footerGap, controls, controlRows)
    footer = footer or {{"Set", "saveText"}, {"Clr", "clearText"}, {"Back", k.back}}
    local actions = {}
    for index, row in ipairs(footer) do
        actions[index] = {row[1], row[2], row[3], row[4], index == 1 and accent or nil}
    end
    ui.buttonRow(height - controlRows + 1, actions, controlRows)
    ui.lines.fixedLayout = true
end

-- Common app forms keep drawing and hit regions together at 12x6 and above.
function Gui.form(width,height,view,accent,background,panel)
    local ui=Gui.content(width,height); view.pages=view.pages or {}
    background,panel=background or 32768,panel or 128
    ui.style(1,1,width,height,Gui.contrast(background),background)
    function ui.action(y,text,action,value,x1,x2,enabled,bg)
        ui.button(y,text,action,x1,x2,enabled,bg or panel,nil,value)
    end
    function ui.footer(rows, depth)
        -- A screen can replace the default Back footer supplied by info().
        for i = #ui.hits, 1, -1 do
            local hit = ui.hits[i]
            if (hit.y2 or hit.y) == height then
                if hit.paint then
                    labelAt(ui.lines, hit.x1, hit.x2, hit.y, "")
                    for index = #ui.lines.styles, 1, -1 do
                        if ui.lines.styles[index] == hit.paint then table.remove(ui.lines.styles, index); break end
                    end
                end
                table.remove(ui.hits, i)
            end
        end
        depth=depth or 1
        local items = {}
        for i, row in ipairs(rows) do
            items[i] = {row[1], row[2], row[3], row[4], row[5] or panel}
        end
        ui.buttonRow(height - depth + 1, items, depth)
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
    function ui.menu(title,rows,key,footer,tiles)
        ui.heading(title,accent)
        footer = footer or {{"Back","home"}}
        local depth = 1
        for _, row in ipairs(footer) do
            if not isSecondary(row[1], row[2]) then
                depth = math.min(3, Gui.controlHeight(height), math.max(1, height - #rows - 1))
                break
            end
        end
        local bottom = height - depth
        local paged = #rows > bottom - 1
        local slots = bottom - (paged and 2 or 1)
        local first = ui.page(key,#rows,slots,bottom)
        local visible = {}
        for i = first + 1, math.min(first + slots, #rows) do visible[#visible + 1] = rows[i] end
        ui.choices(2, bottom - (paged and 1 or 0), visible, tiles, panel, math.min(#rows, slots))
        ui.footer(footer, depth)
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
    function ui.keyboard(k, footer)
        Gui.keyboard(ui, width, height, k, accent, footer)
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
