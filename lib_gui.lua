-- CC 1.5 colour surfaces. Uses write/setTextColor/setBackgroundColor, never blit.
local Gui = {}
local digits = "0123456789abcdef"
local names = {"White", "Orange", "Magenta", "Light blue", "Yellow", "Lime", "Pink", "Gray",
    "Light gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
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
-- App widgets return text plus clipped colour rectangles, sharing geometry with hits.
function Gui.content(width, height)
    local ui = {lines = {styles = {}}, hits = {}}
    ui.lines.hits = ui.hits
    for y = 1, height do ui.lines[y] = string.rep(" ", width) end
    function ui.style(x, y, w, h, fg, bg)
        ui.lines.styles[#ui.lines.styles + 1] = {x = x, y = y, width = w, height = h, fg = fg, bg = bg}
    end
    function ui.text(y, text, centred)
        if y < 1 or y > height then return end
        text = tostring(text):sub(1, width)
        local left = centred and math.floor((width - #text) / 2) or 0
        ui.lines[y] = string.rep(" ", left) .. text .. string.rep(" ", width - left - #text)
    end
    function ui.heading(text, accent)
        ui.text(1, text)
        ui.style(1, 1, width, 1, Gui.contrast(accent or 128), accent or 128)
    end
    function ui.button(y, label, action, x1, x2, enabled, bg, fg, value)
        x1, x2 = x1 or 1, x2 or width
        label = label:sub(1, x2 - x1 + 1)
        local left = math.floor((x2 - x1 + 1 - #label) / 2)
        local text = string.rep(" ", left) .. label .. string.rep(" ", x2 - x1 + 1 - left - #label)
        ui.lines[y] = ui.lines[y]:sub(1, x1 - 1) .. text .. ui.lines[y]:sub(x2 + 1)
        bg = enabled == false and 256 or bg or 128
        ui.style(x1, y, x2 - x1 + 1, 1, enabled == false and 128 or fg or Gui.contrast(bg), bg)
        ui.hits[#ui.hits + 1] = {x1 = x1, x2 = x2, y = y, action = action, value = value, enabled = enabled}
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
    local gap = pages == 1 and height >= #items * 2 + 2 and 2 or 1
    local first = height >= #items * gap + 3 and pages == 1 and 3 or 2
    local inset = width >= 18 and math.max(2, math.floor((width - 32) / 2)) or 0
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then ui.button(first + (row - 1) * gap, item.label, item.action, 1 + inset, width - inset, item.enabled) end
    end
    if pages > 1 then
        local half = math.floor(width / 2)
        ui.button(height - 1, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 1, "Next >", "next", half + 1, width, page < pages)
    end
    ui.button(height, "Back", back)
    return ui.lines, ui.hits, page, pages
end
function Gui.palette(width, height, current, title)
    local ui = Gui.content(width, height)
    ui.heading(title or "UI colour", 128)
    local cellWidth, cellHeight = math.floor((width - 3) / 4), math.min(2, math.floor((height - 2) / 4))
    local short = {"White", "Orange", "Mag.", "Sky", "Yellow", "Lime", "Pink", "Gray", "L.gray", "Cyan", "Purple", "Blue", "Brown", "Green", "Red", "Black"}
    for index = 0, 15 do
        local x, y = 1 + index % 4 * (cellWidth + 1), 2 + math.floor(index / 4) * cellHeight
        local colour = 2 ^ index
        ui.style(x, y, cellWidth, cellHeight, Gui.contrast(colour), colour)
        local label = colour == current and "*" or cellWidth >= 6 and short[index + 1] or ""
        local left = math.floor((cellWidth - #label) / 2)
        local row = ui.lines[y]
        ui.lines[y] = row:sub(1, x - 1) .. string.rep(" ", left) .. label
            .. string.rep(" ", cellWidth - left - #label) .. row:sub(x + cellWidth)
        ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + cellWidth - 1, y = y, y1 = y,
            y2 = y + cellHeight - 1, action = "colour", value = colour}
    end
    ui.button(height, "Back", "cancel")
    return ui.lines, ui.hits
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
    end
    local function replace(row, x, value) return row:sub(1, x - 1) .. value .. row:sub(x + #value) end
    function surface.style(x, y, w, h, fg, bg)
        local first, last = math.max(1, x), math.min(width, x + w - 1)
        if last < first then return end
        for row = math.max(1, y), math.min(height, y + h - 1) do
            local f, b = Gui.code(fg), Gui.code(bg)
            if f then surface.foreground[row] = replace(surface.foreground[row], first, string.rep(f, last - first + 1)) end
            if b then surface.background[row] = replace(surface.background[row], first, string.rep(b, last - first + 1)) end
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
