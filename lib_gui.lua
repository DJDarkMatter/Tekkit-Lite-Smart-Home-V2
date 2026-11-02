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
    function ui.footer(rows)
        for i,row in ipairs(rows) do ui.action(height,row[1],row[2],row[3],1+math.floor((i-1)*width/#rows),math.floor(i*width/#rows),row[4],row[5]) end
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
        local first=ui.page(key,#wrapped,slots,height-1)
        for i=1,slots do ui.put(1,i+1,wrapped[first+i] or "",width) end
        ui.footer({{"Back",back}})
    end
    function ui.numberPad(title,draft,back)
        ui.heading(title,accent); ui.put(1,2,draft=="" and "0" or draft,width,true)
        for i,key in ipairs({"1","2","3","4","5","6","7","8","9","Clr","0","Del"}) do
            local col,row=(i-1)%4,math.floor((i-1)/4)
            ui.action(3+row,key,"digit",key,1+math.floor(col*width/4),math.floor((col+1)*width/4),true,accent)
        end
        ui.footer({{"Set","setNumber"},{"Back",back}})
    end
    function ui.keyboard(k)
        local bank=k.bank==2 and "1234567890-_/.:" or k.bank==1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZ" or "abcdefghijklmnopqrstuvwxyz"
        ui.heading(k.draft=="" and "Type here" or k.draft:sub(-width),accent)
        local cols,rows=math.max(4,math.min(10,math.floor(width/2))),math.max(1,math.min(3,height-4))
        local slots=cols*rows; local pages=math.ceil(#bank/slots); k.page=math.max(1,math.min(k.page or 1,pages))
        for i=1,slots do local ch=bank:sub((k.page-1)*slots+i,(k.page-1)*slots+i); if ch~="" then
            local col,row=(i-1)%cols,math.floor((i-1)/cols)
            ui.action(2+row,ch,"key",ch,1+math.floor(col*width/cols),math.floor((col+1)*width/cols),true,accent)
        end end
        for i,row in ipairs({{"ABC","bank"},{"Sp","space"},{"Del","backspace"},{k.page.."/"..pages,"keyPage"}}) do
            ui.action(height-1,row[1],row[2],nil,1+math.floor((i-1)*width/4),math.floor(i*width/4))
        end
        ui.footer({{"Set","saveText"},{"Clr","clearText"},{"Back",k.back}})
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
