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
    local text = ui.text
    if dialog.stage == 4 then
        ui.heading("Use this " .. dialog.direction .. "?", 2048)
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
        local depth = height >= 9 and 2 or 1
        local actions = {{"< Back", "back"}}
        if dialog.direction == "output" and api then
            actions[2] = {testing and "Wait" or "Test", "test", nil, not testing}
        end
        ui.buttonRow(height - depth, actions)
        ui.buttonRow(height - depth + 1, {{"Use", "use", nil, true, 32}, {"Cancel", "cancel"}}, depth)
    else
        local titles = {"Select IO", "Select side", "Select wire"}
        local list = choices(dialog, clients, label)
        local path = dialog.stage>1 and Gui.breadcrumb(dialog.stage==3 and {label(dialog.chosen.clientId),dialog.chosen.side} or {label(dialog.chosen.clientId)},width,height)
        local header = path and 2 or 1
        local page, pages = ui.pickerList(header + 1, list, dialog.page)
        dialog.page = page
        ui.heading(titles[dialog.stage] .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), 2048)
        if path then text(2,path); ui.style(1,2,width,1,256,32768) end
        if #list == 0 then text(header+1, "No IO clients") end
    end
    local lines, hits = ui.finish(true)
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
