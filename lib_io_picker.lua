-- Reusable, server-rendered IO selector. No peripheral or network calls here.
local Picker = {}
local Gui = dofile("lib_gui.lua")
local sideNames = {"top", "bottom", "left", "right", "front", "back"}
local colorNames = {"white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}

function Picker.new(key, direction, selected)
    local chosen = {}
    for k, v in pairs(selected or {}) do chosen[k] = v end
    return {key = key, direction = direction, stage = 1, page = 1, chosen = chosen}
end

local function choices(dialog, clients, label)
    local list = {}
    if dialog.stage == 1 then
        local found = false
        for _, client in ipairs(clients) do
            list[#list + 1] = {label = label(client.id) .. (client.online and " +" or " -"), value = client.id}
            if client.id == dialog.chosen.clientId then found = true end
        end
        if dialog.chosen.clientId and not found then
            list[#list + 1] = {label = label(dialog.chosen.clientId) .. " -", value = dialog.chosen.clientId}
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

function Picker.render(dialog, width, height, clients, api, testing)
    local label = api and api.clientName or function(id) return id end
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    local half = math.floor(width / 2)
    local text = ui.text
    local function button(row, x1, x2, label, action, value, enabled)
        local bg = action == "cancel" and 16384 or action == "use" and 32 or 128
        ui.button(row, label, action, x1, x2, enabled, bg, nil, value)
    end
    if dialog.stage == 4 then
        text(1, "Use this " .. dialog.direction .. "?")
        text(2, label(dialog.chosen.clientId) or "No IO client")
        text(3, "Side: " .. (dialog.chosen.side or "?"))
        local wire = colorName(dialog.chosen.color)
        if dialog.direction == "input" and api then
            local value = api.readInput(dialog.chosen)
            local status = value == nil and "Unknown" or value and "ON" or "OFF"
            local summary = wire .. " / " .. status
            text(4, #summary <= width and summary or wire:sub(1, width - #status - 1) .. " " .. status)
        else text(4, wire) end
        if dialog.error then text(4, dialog.error) end
        if dialog.direction == "output" and api then
            button(height - 1, 1, half, "< Back", "back")
            button(height - 1, half + 1, width, testing and "Wait" or "Test", "test", nil, not testing)
        else button(height - 1, 1, width, "< Back", "back") end
        button(height, 1, half, "Use", "use")
        button(height, half + 1, width, "Cancel", "cancel")
    else
        local titles = {"Select IO", "Select side", "Select wire"}
        local list = choices(dialog, clients, label)
        local path = dialog.stage>1 and Gui.breadcrumb(dialog.stage==3 and {label(dialog.chosen.clientId),dialog.chosen.side} or {label(dialog.chosen.clientId)},width,height)
        local header = path and 2 or 1
        local slots = #list <= height-header-1 and height-header-1 or math.max(1,height-header-2)
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        text(1, titles[dialog.stage] .. (pages > 1 and (" " .. dialog.page .. "/" .. pages) or ""))
        if path then text(2,path); ui.style(1,2,width,1,256,32768) end
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then
                button(row + header, 1, width, (item.colour and "  " or "") .. item.label, "select", item.value)
                if item.colour then ui.style(1, row + header, 2, 1, nil, item.colour) end
            end
        end
        if #list == 0 then text(header+1, "No IO clients") end
        if pages > 1 then
            button(height - 1, 1, half, "< Prev", "prev", nil, dialog.page > 1)
            button(height - 1, half + 1, width, "Next >", "next", pages, dialog.page < pages)
        end
        button(height, 1, half, "Back", "back")
        button(height, half + 1, width, "Cancel", "cancel")
    end
    ui.style(1, 1, width, 1, 1, 2048)
    local lines, hits = ui.finish()
    dialog.hits = hits
    return lines
end

function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do
        if Gui.hit(hit, x, y) then
            if hit.enabled == false then return end
            dialog.error = nil
            if hit.action == "cancel" then return "cancel"
            elseif hit.action == "test" then return "test", dialog.chosen
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
