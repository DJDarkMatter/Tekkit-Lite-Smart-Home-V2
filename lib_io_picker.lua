-- Reusable, server-rendered IO selector. No peripheral or network calls here.
local Picker = {}
local sideNames = {"top", "bottom", "left", "right", "front", "back"}
local colorNames = {"white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}

function Picker.new(key, direction, selected)
    local chosen = {}
    for k, v in pairs(selected or {}) do chosen[k] = v end
    return {key = key, direction = direction, stage = 1, page = 1, chosen = chosen}
end

local function choices(dialog, clients)
    local list = {}
    if dialog.stage == 1 then
        local found = false
        for _, client in ipairs(clients) do
            list[#list + 1] = {label = client.id .. (client.online and " +" or " -"), value = client.id}
            if client.id == dialog.chosen.clientId then found = true end
        end
        if dialog.chosen.clientId and not found then
            list[#list + 1] = {label = dialog.chosen.clientId .. " -", value = dialog.chosen.clientId}
        end
    elseif dialog.stage == 2 then
        local available
        for _, client in ipairs(clients) do
            if client.id == dialog.chosen.clientId then available = client.sides; break end
        end
        for _, side in ipairs(available or sideNames) do list[#list + 1] = {label = side, value = side} end
    elseif dialog.stage == 3 then
        list[1] = {label = "Digital", value = false}
        for i, name in ipairs(colorNames) do list[#list + 1] = {label = name, value = 2 ^ (i - 1), colour = 2 ^ (i - 1)} end
    end
    return list
end

local function colorName(value)
    if not value then return "Digital" end
    for i, name in ipairs(colorNames) do if value == 2 ^ (i - 1) then return name end end
    return "Invalid color"
end

function Picker.render(dialog, width, height, clients)
    local lines, hits = {styles = {}}, {}
    local half = math.floor(width / 2)
    local function text(row, value) lines[row] = tostring(value):sub(1, width) end
    local function button(row, x1, x2, label, action, value, enabled)
        local line = lines[row] or string.rep(" ", width)
        label = label:sub(1, x2 - x1 + 1)
        local padding = math.floor((x2 - x1 + 1 - #label) / 2)
        label = string.rep(" ", padding) .. label .. string.rep(" ", x2 - x1 + 1 - padding - #label)
        lines[row] = line:sub(1, x1 - 1) .. label .. line:sub(x2 + 1)
        hits[#hits + 1] = {y = row, x1 = x1, x2 = x2, action = action, value = value, enabled = enabled}
        lines.styles[#lines.styles + 1] = {x = x1, y = row, width = x2 - x1 + 1, height = 1,
            fg = enabled == false and 128 or action == "cancel" and 1 or 32768,
            bg = action == "cancel" and 16384 or action == "use" and 32 or action == "select" and (row % 2 == 0 and 1 or 256) or 256}
    end
    for row = 1, height do lines[row] = string.rep(" ", width) end
    if dialog.stage == 4 then
        text(1, "Use this " .. dialog.direction .. "?")
        text(2, dialog.chosen.clientId or "No IO client")
        text(3, "Side: " .. (dialog.chosen.side or "?"))
        text(4, colorName(dialog.chosen.color))
        if dialog.error then text(4, dialog.error) end
        button(height - 1, 1, width, "< Back", "back")
        button(height, 1, half, "Use", "use")
        button(height, half + 1, width, "Cancel", "cancel")
    else
        local titles = {"Select IO", "Select side", "Select wire"}
        local list, slots = choices(dialog, clients), math.max(1, height - 3)
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        text(1, titles[dialog.stage] .. " " .. dialog.page .. "/" .. pages)
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then
                button(row + 1, 1, width, (item.colour and "  " or "") .. item.label, "select", item.value)
                if item.colour then lines.styles[#lines.styles + 1] = {x = 1, y = row + 1, width = 2, height = 1, bg = item.colour} end
            end
        end
        if #list == 0 then text(2, "No IO clients") end
        button(height - 1, 1, half, "< Prev", "prev", nil, dialog.page > 1)
        button(height - 1, half + 1, width, "Next >", "next", pages, dialog.page < pages)
        button(height, 1, half, "Back", "back")
        button(height, half + 1, width, "Cancel", "cancel")
    end
    dialog.hits = hits
    lines.styles[#lines.styles + 1] = {x = 1, y = 1, width = width, height = 1, fg = 1, bg = 2048}
    return lines
end

function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do
        if hit.y == y and x >= hit.x1 and x <= hit.x2 then
            if hit.enabled == false then return end
            dialog.error = nil
            if hit.action == "cancel" then return "cancel"
            elseif hit.action == "use" then return "selected", dialog.chosen
            elseif hit.action == "prev" then dialog.page = math.max(1, dialog.page - 1)
            elseif hit.action == "next" then dialog.page = math.min(hit.value, dialog.page + 1)
            elseif hit.action == "back" then
                if dialog.stage == 1 then return "cancel" end
                dialog.stage, dialog.page = dialog.stage - 1, 1
            elseif hit.action == "select" then
                if dialog.stage == 1 then dialog.chosen.clientId = hit.value
                elseif dialog.stage == 2 then dialog.chosen.side = hit.value
                else dialog.chosen.color = hit.value or nil end
                dialog.stage, dialog.page = dialog.stage + 1, 1
            end
            return
        end
    end
end

return Picker
