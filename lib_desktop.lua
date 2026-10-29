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

local grids = {{1, 1}, {2, 1}, {1, 2}, {2, 2}, {3, 1}, {1, 3}, {3, 2}, {2, 3}, {3, 3}}
local legacyGrids = {maximize = {1, 1, 1, 1}, left = {2, 1, 1, 1}, right = {2, 1, 2, 1},
    top = {1, 2, 1, 1}, bottom = {1, 2, 1, 2}, top_left = {2, 2, 1, 1}, top_right = {2, 2, 2, 1},
    bottom_left = {2, 2, 1, 2}, bottom_right = {2, 2, 2, 2}}
function Desktop.gridMode(columns, rows, column, row)
    for mode, grid in pairs(legacyGrids) do
        if grid[1] == columns and grid[2] == rows and grid[3] == column and grid[4] == row then return mode end
    end
    return "grid_" .. columns .. "x" .. rows .. "_" .. column .. "_" .. row
end
function Desktop.gridForMode(mode)
    local grid = legacyGrids[mode]
    if grid then return grid[1] .. "x" .. grid[2] end
    if type(mode) == "string" then return mode:match("^grid_([1-3]x[1-3])_[1-3]_[1-3]$") end
end
local function gridSize(name)
    if type(name) ~= "string" then return end
    local columns, rows = name:match("^([1-3])x([1-3])$")
    return tonumber(columns), tonumber(rows)
end
function Desktop.zone(mode, monitor)
    local area = Desktop.area(monitor)
    local grid = legacyGrids[mode]
    local columns, rows, column, row
    if grid then columns, rows, column, row = unpack(grid)
    elseif type(mode) == "string" then
        columns, rows, column, row = mode:match("^grid_([1-3])x([1-3])_([1-3])_([1-3])$")
        columns, rows, column, row = tonumber(columns), tonumber(rows), tonumber(column), tonumber(row)
    end
    if not columns or column > columns or row > rows then return end
    local left, top = math.floor((column - 1) * area.width / columns), math.floor((row - 1) * area.height / rows)
    return {x = left + 1, y = top + 1, width = math.floor(column * area.width / columns) - left,
        height = math.floor(row * area.height / rows) - top}
end

function Desktop.layoutOptions(win, app, monitor, selectedGrid)
    local options = {}
    local columns, rows = gridSize(selectedGrid)
    if columns then
        for row = 1, rows do for column = 1, columns do
            local mode = Desktop.gridMode(columns, rows, column, row)
            options[#options + 1] = {label = "Position " .. ((row - 1) * columns + column), value = mode,
                enabled = Desktop.fits(Desktop.zone(mode, monitor), app, monitor)}
        end end
        options[#options + 1] = {label = "Back", value = "back", enabled = true}
    else
        for _, grid in ipairs(grids) do
            local enabled = false
            for row = 1, grid[2] do for column = 1, grid[1] do
                enabled = enabled or Desktop.fits(Desktop.zone(Desktop.gridMode(grid[1], grid[2], column, row), monitor), app, monitor)
            end end
            local name = grid[1] .. "x" .. grid[2]
            options[#options + 1] = {label = name, value = "choose_" .. name, enabled = enabled}
        end
        options[#options + 1] = {label = "Restore", value = "restore", enabled = win.layout ~= nil and win.layout ~= "normal"}
        options[#options + 1] = {label = "Resize", value = "custom", enabled = true}
        options[#options + 1] = {label = "Move", value = "move", enabled = true}
    end
    options[#options + 1] = {label = "Cancel", value = "cancel", enabled = true}
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

-- First choose a grid; only the second screen places the window in a pane.
function Desktop.layoutPicker(win, app, monitor, page, title, selectedGrid)
    local area, options = Desktop.area(monitor), Desktop.layoutOptions(win, app, monitor, selectedGrid)
    local gridColumns, gridRows = gridSize(selectedGrid)
    if (area.height < 10 and not gridColumns) or (gridColumns and area.height < gridRows * 2 + 3) then
        return Desktop.menu(monitor, title or (gridColumns and selectedGrid .. " position" or "Layout"), options, page,
            {x = win.x, y = win.y + 1})
    end
    local width = math.min(gridColumns and 35 or 43, area.width)
    local columns = width >= 40 and 3 or width >= 27 and 2 or 1
    local height = math.min(area.height, gridColumns and math.max(9, gridRows * 3 + 4) or 3 + math.ceil(#grids / columns) * 6)
    local rows = math.max(1, math.floor((height - 3) / 6))
    if rows * columns < #grids then rows = math.max(1, math.floor((height - 4) / 6)) end
    local perPage, pages = rows * columns, gridColumns and 1 or math.ceil(#grids / (rows * columns))
    page = clamp(page or 1, 1, pages)
    local rect = {x = clamp(win.x + win.width - width, 1, area.width - width + 1),
        y = clamp(win.y + 1, 1, area.height - height + 1), width = width, height = height}
    local ui, byMode = Gui.content(width, height), {}
    ui.style(1, 1, width, height, 1, 32768)
    for _, item in ipairs(options) do byMode[item.value] = item end
    ui.heading((title or (gridColumns and selectedGrid .. " - position" or "Layout"))
        .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), 128)
    local function hit(x, y, w, h, item)
        ui.hits[#ui.hits + 1] = {x1 = x, x2 = x + w - 1, y = y, y1 = y, y2 = y + h - 1, action = "item", item = item}
    end
    local function pane(x, y, w, h, mode, label)
        local item = byMode[mode]
        local bg = item.enabled and (win.layout == mode and 2048 or 8) or 128
        ui.style(x, y, w, h, Gui.contrast(bg), bg)
        local textY = y + math.floor((h - 1) / 2)
        local textX = x + math.floor((w - #label) / 2)
        local line = ui.lines[textY]
        ui.lines[textY] = line:sub(1, textX - 1) .. label .. line:sub(textX + #label)
        hit(x, y, w, h, item)
    end
    if gridColumns then
        local diagramWidth, diagramHeight = width - 2, height - 4
        local usableWidth, usableHeight = diagramWidth - gridColumns + 1, diagramHeight - gridRows + 1
        for row = 1, gridRows do for column = 1, gridColumns do
            local x = 2 + math.floor((column - 1) * usableWidth / gridColumns) + column - 1
            local y = 3 + math.floor((row - 1) * usableHeight / gridRows) + row - 1
            local w = math.floor(column * usableWidth / gridColumns) - math.floor((column - 1) * usableWidth / gridColumns)
            local h = math.floor(row * usableHeight / gridRows) - math.floor((row - 1) * usableHeight / gridRows)
            pane(x, y, w, h, Desktop.gridMode(gridColumns, gridRows, column, row), tostring((row - 1) * gridColumns + column))
        end end
    else
        local cardWidth = math.floor((width - columns - 1) / columns)
        for slot = 1, perPage do
            local grid = grids[(page - 1) * perPage + slot]
            if grid then
                local x, y = 2 + (slot - 1) % columns * (cardWidth + 1), 2 + math.floor((slot - 1) / columns) * 6
                local name = grid[1] .. "x" .. grid[2]
                local item = byMode["choose_" .. name]
                local labelX = x + math.floor((cardWidth - #name) / 2)
                local line = ui.lines[y]
                ui.lines[y] = line:sub(1, labelX - 1) .. name .. line:sub(labelX + #name)
                local usableWidth, usableHeight = cardWidth - grid[1] + 1, 6 - grid[2]
                for row = 1, grid[2] do for column = 1, grid[1] do
                    local px = x + math.floor((column - 1) * usableWidth / grid[1]) + column - 1
                    local py = y + 1 + math.floor((row - 1) * usableHeight / grid[2]) + row - 1
                    local pw = math.floor(column * usableWidth / grid[1]) - math.floor((column - 1) * usableWidth / grid[1])
                    local ph = math.floor(row * usableHeight / grid[2]) - math.floor((row - 1) * usableHeight / grid[2])
                    ui.style(px, py, pw, ph, nil, item.enabled and 8 or 128)
                end end
                hit(x, y, cardWidth, 6, item)
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
    if gridColumns then
        action(height, 1, half, "back", "Back")
    else
        action(height - 1, 1, half, "restore", "Restore")
        action(height - 1, half + 1, width, "custom", "Resize")
        action(height, 1, half, "move", "Move")
    end
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
