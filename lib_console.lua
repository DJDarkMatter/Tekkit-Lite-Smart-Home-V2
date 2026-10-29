-- Local CC 1.5 terminal: log output above an independently edited bottom line.
-- No read(), term.redirect(), window API, or peripheral drawing is required.
local Console = {}
local codes = {enter = 28, numPadEnter = 156, backspace = 14, delete = 211,
    left = 203, right = 205, home = 199, ["end"] = 207, up = 200, down = 208}
for name, fallback in pairs(codes) do codes[name] = keys and keys[name] or fallback end

function Console.new(screen)
    local console = {lines = {}, history = {}, text = "", cursor = 0, offset = 0}
    local cache, previousWidth, previousHeight = {}, nil, nil
    local function clean(value)
        return tostring(value):gsub("\r", ""):gsub("\t", "    "):gsub("[%z\1-\8\11\12\14-\31\127]", " ")
    end
    function console.redraw(force)
        local width, height = screen.getSize()
        assert(width >= 3 and height >= 2, "Console needs at least 3x2 characters")
        if width ~= previousWidth or height ~= previousHeight then
            force, previousWidth, previousHeight = true, width, height
        end
        if screen.setCursorBlink then screen.setCursorBlink(false) end
        local setFG, setBG = screen.setTextColor or screen.setTextColour, screen.setBackgroundColor or screen.setBackgroundColour
        if setFG then setFG(1) end
        if setBG then setBG(32768) end
        local rows = {}
        for _, line in ipairs(console.lines) do
            if line == "" then rows[#rows + 1] = "" end
            for first = 1, #line, width do rows[#rows + 1] = line:sub(first, first + width - 1) end
        end
        local function paint(y, line)
            line = line:sub(1, width)
            line = line .. string.rep(" ", width - #line)
            if force or cache[y] ~= line then
                screen.setCursorPos(1, y); screen.write(line); cache[y] = line
            end
        end
        for y = 1, height - 1 do paint(y, rows[#rows - height + 1 + y] or "") end
        local available = width - 2
        if console.cursor < console.offset then console.offset = console.cursor end
        if console.cursor >= console.offset + available then console.offset = console.cursor - available + 1 end
        console.offset = math.max(0, math.min(console.offset, math.max(0, #console.text - available + 1)))
        paint(height, "> " .. console.text:sub(console.offset + 1, console.offset + available))
        screen.setCursorPos(3 + console.cursor - console.offset, height)
        if screen.setCursorBlink then screen.setCursorBlink(true) end
    end
    function console.log(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = clean(select(index, ...)) end
        for line in (table.concat(parts, " ") .. "\n"):gmatch("(.-)\n") do
            console.lines[#console.lines + 1] = line
        end
        while #console.lines > 200 do table.remove(console.lines, 1) end
        console.redraw()
    end
    function console.clear()
        console.lines, cache = {}, {}
        console.redraw(true)
    end
    local function changed()
        console.historyIndex, console.draft = nil, nil
    end
    function console.handle(event, value)
        if event == "char" or event == "paste" then
            if type(value) ~= "string" then return end
            value = clean(value):gsub("\n", " "):sub(1, math.max(0, 4096 - #console.text))
            console.text = console.text:sub(1, console.cursor) .. value .. console.text:sub(console.cursor + 1)
            console.cursor = console.cursor + #value
            changed()
        elseif event == "term_resize" then console.redraw(true); return
        elseif event == "key" then
            if value == codes.enter or value == codes.numPadEnter then
                local command = console.text
                if command:match("%S") and console.history[#console.history] ~= command then
                    console.history[#console.history + 1] = command
                    if #console.history > 50 then table.remove(console.history, 1) end
                end
                console.text, console.cursor, console.offset = "", 0, 0
                changed()
                console.log("> " .. command)
                return command
            elseif value == codes.left then console.cursor = math.max(0, console.cursor - 1)
            elseif value == codes.right then console.cursor = math.min(#console.text, console.cursor + 1)
            elseif value == codes.home then console.cursor = 0
            elseif value == codes["end"] then console.cursor = #console.text
            elseif value == codes.backspace then
                if console.cursor > 0 then
                    console.text = console.text:sub(1, console.cursor - 1) .. console.text:sub(console.cursor + 1)
                    console.cursor = console.cursor - 1; changed()
                end
            elseif value == codes.delete then
                console.text = console.text:sub(1, console.cursor) .. console.text:sub(console.cursor + 2)
                changed()
            elseif value == codes.up then
                if #console.history > 0 then
                    if not console.historyIndex then console.draft = console.text end
                    console.historyIndex = math.max(1, (console.historyIndex or (#console.history + 1)) - 1)
                    console.text = console.history[console.historyIndex]; console.cursor = #console.text
                end
            elseif value == codes.down then
                if console.historyIndex then
                    console.historyIndex = console.historyIndex + 1
                    if console.historyIndex > #console.history then console.text = console.draft or ""; changed()
                    else console.text = console.history[console.historyIndex] end
                    console.cursor = #console.text
                end
            else return end
        else return end
        console.redraw()
    end
    function console.finish()
        local width, height = screen.getSize()
        screen.setCursorPos(1, height); screen.write(string.rep(" ", width))
        screen.setCursorPos(1, height)
        if screen.setCursorBlink then screen.setCursorBlink(false) end
    end
    console.redraw(true)
    return console
end
return Console
