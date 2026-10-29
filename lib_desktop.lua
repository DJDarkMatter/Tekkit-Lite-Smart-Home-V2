-- Character-based desktop geometry and widgets. No peripheral calls here.
local Desktop = {}
local Gui = dofile("lib_gui.lua")
local function clamp(value, low, high) return math.max(low, math.min(value, high)) end

function Desktop.area(monitor)
    return {x = 1, y = 1, width = monitor.width, height = monitor.height - 1}
end

function Desktop.controls(win)
    local x = win.x + win.width - 9
    return {{x1 = x, x2 = x + 2, action = "minimize", label = " - "},
        {x1 = x + 3, x2 = x + 5, action = "layout", label = " + "},
        {x1 = x + 6, x2 = x + 8, action = "close", label = " X "}}
end

function Desktop.bounds(app, monitor)
    local area = Desktop.area(monitor)
    return math.max(10, (app.minWidth or 8) + 2), (app.minHeight or 2) + 2,
        math.min(area.width, app.maxWidth and app.maxWidth + 2 or area.width),
        math.min(area.height, app.maxHeight and app.maxHeight + 2 or area.height)
end

function Desktop.fits(rect, app, monitor)
    local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
    return rect and rect.width >= minW and rect.height >= minH and rect.width <= maxW
        and rect.height <= maxH and rect.x >= 1 and rect.y >= 1
        and rect.x + rect.width - 1 <= monitor.width
        and rect.y + rect.height - 1 < monitor.height
end

function Desktop.relative(rect, monitor)
    local area = Desktop.area(monitor)
    return {x = (rect.x - 1) / area.width, y = (rect.y - 1) / area.height,
        width = rect.width / area.width, height = rect.height / area.height}
end

function Desktop.free(rect, relative, app, monitor)
    local minW, minH, maxW, maxH = Desktop.bounds(app, monitor)
    if maxW < minW or maxH < minH then return nil end
    local area = Desktop.area(monitor)
    local width, height, x, y
    if relative then
        width, height = math.floor(relative.width * area.width + 0.5), math.floor(relative.height * area.height + 0.5)
        x, y = 1 + math.floor(relative.x * area.width + 0.5), 1 + math.floor(relative.y * area.height + 0.5)
    else
        width, height = tonumber(rect.width) or (app.preferredWidth or 30) + 2,
            tonumber(rect.height) or (app.preferredHeight or 10) + 2
        x, y = tonumber(rect.x) or 1, tonumber(rect.y) or 1
    end
    width, height = clamp(math.floor(width), minW, maxW), clamp(math.floor(height), minH, maxH)
    return {x = clamp(math.floor(x), 1, area.width - width + 1),
        y = clamp(math.floor(y), 1, area.height - height + 1), width = width, height = height}
end

function Desktop.zone(mode, monitor)
    local area = Desktop.area(monitor)
    local left, top = math.floor(area.width / 2), math.floor(area.height / 2)
    local zones = {
        maximize = {1, 1, area.width, area.height},
        left = {1, 1, left, area.height}, right = {left + 1, 1, area.width - left, area.height},
        top = {1, 1, area.width, top}, bottom = {1, top + 1, area.width, area.height - top},
        top_left = {1, 1, left, top}, top_right = {left + 1, 1, area.width - left, top},
        bottom_left = {1, top + 1, left, area.height - top},
        bottom_right = {left + 1, top + 1, area.width - left, area.height - top},
    }
    local z = zones[mode]
    if z then return {x = z[1], y = z[2], width = z[3], height = z[4]} end
end

function Desktop.layoutOptions(win, app, monitor)
    local options = {{label = "Maximize", value = "maximize"}, {label = "Restore", value = "restore"},
        {label = "Left half", value = "left"}, {label = "Right half", value = "right"},
        {label = "Top half", value = "top"}, {label = "Bottom half", value = "bottom"},
        {label = "Top-left qtr", value = "top_left"}, {label = "Top-right qtr", value = "top_right"},
        {label = "Bottom-left", value = "bottom_left"}, {label = "Bottom-right", value = "bottom_right"},
        {label = "Custom area", value = "custom"}, {label = "Move", value = "move"}, {label = "Cancel", value = "cancel"}}
    for _, item in ipairs(options) do
        if item.value == "restore" then item.enabled = win.layout ~= nil and win.layout ~= "normal"
        elseif item.value == "custom" or item.value == "move" or item.value == "cancel" then item.enabled = true
        else item.enabled = Desktop.fits(Desktop.zone(item.value, monitor), app, monitor) end
    end
    return options
end

function Desktop.moveArrows(rect, monitor)
    local hits, area = {}, Desktop.area(monitor)
    local middleX, middleY = rect.x + math.floor((rect.width - 1) / 2), rect.y + math.floor(rect.height / 2)
    local function add(x, y, label, dx, dy)
        hits[#hits + 1] = {x1 = x, x2 = x + 2, y = y, label = label, dx = dx, dy = dy}
    end
    if rect.x > 1 then add(rect.x, middleY, " < ", -1, 0) end
    if rect.x + rect.width - 1 < area.width then add(rect.x + rect.width - 3, middleY, " > ", 1, 0) end
    if rect.y > 1 then add(middleX - 1, rect.y, " ^ ", 0, -1) end
    if rect.y + rect.height - 1 < area.height then add(middleX - 1, rect.y + rect.height - 1, " v ", 0, 1) end
    return hits
end

-- Windows-style snap cards: click the actual pane of a miniature desktop.
function Desktop.layoutPicker(win, app, monitor, page, title)
    local area, options = Desktop.area(monitor), Desktop.layoutOptions(win, app, monitor)
    if area.height < 8 then
        return Desktop.menu(monitor, title or "Layout", options, page, {x = win.x, y = win.y + 1})
    end
    local width = math.min(33, area.width)
    local columns = width >= 25 and 2 or 1
    local height = math.min(area.height, 3 + math.ceil(4 / columns) * 4)
    local rows = math.max(1, math.floor((height - 3) / 4))
    local paged = rows * columns < 4
    if paged then rows = math.max(1, math.floor((height - 4) / 4)) end
    local perPage, pages = rows * columns, math.ceil(4 / (rows * columns))
    page = clamp(page or 1, 1, pages)
    local rect = {x = clamp(win.x + win.width - width, 1, area.width - width + 1),
        y = clamp(win.y + 1, 1, area.height - height + 1), width = width, height = height}
    local ui, byMode = Gui.content(width, height), {}
    for _, item in ipairs(options) do byMode[item.value] = item end
    ui.heading((title or "Layout") .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), 128)
    local cards = {"Full", "Columns", "Rows", "Grid"}
    local cardWidth = math.floor((width - columns - 1) / columns)
    local function zone(x, y, w, h, mode)
        local item = byMode[mode]
        ui.style(x, y, w, h, nil, item.enabled and (win.layout == mode and 2048 or 8) or 256)
        ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + w - 1, y = y, y1 = y, y2 = y + h - 1, action = "item", item = item}
    end
    for slot = 1, perPage do
        local index = (page - 1) * perPage + slot
        if cards[index] then
            local x, y = 2 + (slot - 1) % columns * (cardWidth + 1), 2 + math.floor((slot - 1) / columns) * 4
            local line = ui.lines[y]
            local label = cards[index]:sub(1, cardWidth)
            ui.lines[y] = line:sub(1, x - 1) .. label .. line:sub(x + #label)
            local half = math.floor((cardWidth - 1) / 2)
            if index == 1 then zone(x, y + 1, cardWidth, 3, "maximize")
            elseif index == 2 then
                zone(x, y + 1, half, 3, "left"); zone(x + half + 1, y + 1, cardWidth - half - 1, 3, "right")
            elseif index == 3 then zone(x, y + 1, cardWidth, 1, "top"); zone(x, y + 3, cardWidth, 1, "bottom")
            else
                zone(x, y + 1, half, 1, "top_left"); zone(x + half + 1, y + 1, cardWidth - half - 1, 1, "top_right")
                zone(x, y + 3, half, 1, "bottom_left"); zone(x + half + 1, y + 3, cardWidth - half - 1, 1, "bottom_right")
            end
        end
    end
    local half = math.floor(width / 2)
    if pages > 1 then
        ui.button(height - 2, "< Prev", "previous", 1, half, page > 1)
        ui.button(height - 2, "Next >", "next", half + 1, width, page < pages)
    end
    local function action(y, x1, x2, mode, label)
        ui.button(y, label, "item", x1, x2, byMode[mode].enabled)
        ui.hits[#ui.hits].item = byMode[mode]
    end
    action(height - 1, 1, half, "restore", "Restore")
    action(height - 1, half + 1, width, "custom", "Custom")
    action(height, 1, half, "move", "Move")
    action(height, half + 1, width, "cancel", "Cancel")
    for _, hit in ipairs(ui.hits) do
        hit.x1, hit.x2, hit.y = hit.x1 + rect.x - 1, hit.x2 + rect.x - 1, hit.y + rect.y - 1
        if hit.y1 then hit.y1, hit.y2 = hit.y1 + rect.y - 1, hit.y2 + rect.y - 1 end
    end
    return rect, ui.lines, ui.hits, page, pages
end

-- Returns a complete taskbar line and exact touch regions, with stable window order.
function Desktop.taskbar(windows, monitor, clock, saved, active)
    local width = monitor.width
    local line, hits = string.rep(" ", width), {}
    local function put(x, label, stop)
        label = label:sub(1, math.max(0, math.min(stop or width, width) - x + 1))
        line = line:sub(1, x - 1) .. label .. line:sub(x + #label)
    end
    local function hit(x1, x2, action, id) hits[#hits + 1] = {x1 = x1, x2 = x2, action = action, id = id} end
    put(1, "[+]"); hit(1, math.min(3, width), "launcher")
    local clockWidth = (width >= 22 or (#windows == 0 and width >= 10)) and 6 or 0
    if clockWidth > 0 then put(width - 4, clock) end
    local first, last = 5, width - clockWidth
    if last < first then return line, hits end
    local labels, needed = {}, 0
    for _, win in ipairs(windows) do
        local marker = win.minimized and "_" or win.id == active and "*" or ""
        local label = " " .. marker .. (win.title or win.appName) .. " "
        if #label > 14 then label = label:sub(1, 13) .. " " end
        labels[#labels + 1] = label
        needed = needed + #labels[#labels] + 1
    end
    local overflow = needed > last - first + 2
    local scroll = tonumber(saved.scroll) or 1
    if scroll ~= scroll then scroll = 1 end
    saved.scroll = clamp(math.floor(scroll), 1, math.max(1, #windows))
    if not overflow then saved.scroll = 1 end
    if overflow then
        if saved.scroll > 1 then put(first, "<"); hit(first, first, "previous") end
        first, last = first + 1, last - 1
    end
    local x, finalVisible = first, saved.scroll - 1
    for index = saved.scroll, #windows do
        local available = last - x + 1
        if available < 3 then break end
        local label = labels[index]
        local limit = math.min(14, available)
        if #label > limit then label = label:sub(1, limit - 1) .. " " end
        put(x, label, last); hit(x, x + #label - 1, "window", windows[index].id)
        x, finalVisible = x + #label + 1, index
    end
    if overflow and finalVisible < #windows then
        put(last + 1, ">"); hit(last + 1, last + 1, "next")
    end
    return line, hits
end

-- Shared paginated popup geometry for the launcher and window layout menus.
function Desktop.menu(monitor, title, items, page, anchor)
    local area = Desktop.area(monitor)
    local width = math.min(area.width, 26)
    local height = math.min(area.height, math.max(4, #items + 3))
    local slots = math.max(1, height - 3)
    local pages = math.max(1, math.ceil(#items / slots))
    page = clamp(page or 1, 1, pages)
    local rect = {x = clamp(anchor and anchor.x or 1, 1, area.width - width + 1),
        y = clamp(anchor and anchor.y or area.height - height + 1, 1, area.height - height + 1), width = width, height = height}
    local lines, hits = {}, {}
    for y = 1, height do lines[y] = string.rep(" ", width) end
    lines[1] = (" " .. title .. string.rep(" ", width)):sub(1, width)
    lines[height] = (" " .. page .. "/" .. pages .. string.rep(" ", width)):sub(1, width)
    for row = 1, slots do
        local item = items[(page - 1) * slots + row]
        if item then
            local label = (item.enabled == false and "-" or " ") .. item.label
            lines[row + 1] = " " .. label:sub(1, width - 2) .. string.rep(" ", math.max(0, width - 2 - #label)) .. " "
            hits[#hits + 1] = {x1 = rect.x + 1, x2 = rect.x + width - 2, y = rect.y + row,
                action = "item", item = item}
        end
    end
    if #items == 0 then lines[2] = (" No apps" .. string.rep(" ", width)):sub(1, width) end
    if pages > 1 then
        local half = math.floor((width - 2) / 2)
        lines[height - 1] = " " .. ("< Prev" .. string.rep(" ", width)):sub(1, half)
            .. ("Next >" .. string.rep(" ", width)):sub(1, width - 2 - half) .. " "
        hits[#hits + 1] = {x1 = rect.x + 1, x2 = rect.x + half, y = rect.y + height - 2, action = "previous"}
        hits[#hits + 1] = {x1 = rect.x + half + 1, x2 = rect.x + width - 2, y = rect.y + height - 2, action = "next"}
    end
    return rect, lines, hits, page, pages
end

return Desktop
