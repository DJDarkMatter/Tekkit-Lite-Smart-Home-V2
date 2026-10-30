-- Shared client -> sensor port -> target selection, rendered centrally.
local Gui = dofile("lib_gui.lua")
local Picker = {}
function Picker.new(key, current, kind)
    return {kind = "sensor", key = key, chosen = current or {}, filter = kind, stage = 1, page = 1}
end
function Picker.render(dialog, width, height, clients)
    local list, chosen, selectedClient, selectedPort = {}, dialog.chosen
    local function compatible(port)
        if port.status ~= "ok" or not port.card then return false end
        if not dialog.filter then return true end
        if dialog.filter ~= "reactor" then return port.cardKind == dialog.filter end
        if port.cardKind == "machine" or port.cardKind == "unknown" then return true end
        for _, target in ipairs(port.targets) do if target.kind == "reactor" then return true end end
        return false
    end
    if dialog.stage == 1 then
        for _, client in ipairs(clients) do list[#list + 1] = {label = client.id .. (client.online and " +" or " -"), value = client.id} end
    elseif dialog.stage == 2 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            selectedClient = client
            for _, port in ipairs(client.ports) do
                local enabled = compatible(port)
                local detail = port.status ~= "ok" and port.status or port.cardKind
                list[#list + 1] = {label = port.side .. " / " .. detail .. (not enabled and port.status == "ok" and " (other card)" or ""),
                    value = port.side, card = port.card, enabled = enabled}
            end
        end end
    elseif dialog.stage == 3 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            for _, port in ipairs(client.ports) do if port.side == chosen.side then
                selectedPort = port
                for _, target in ipairs(port.targets) do
                    if not dialog.filter or dialog.filter == "reactor" and (target.kind == "reactor" or target.type == "Unknown")
                        or dialog.filter ~= "reactor" and port.cardKind == dialog.filter then
                        list[#list + 1] = {label = target.key .. " " .. target.label, value = target.key, targetType = target.type}
                    end
                end
            end end
        end end
    end
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    if dialog.stage == 4 then
        ui.heading("Use sensor?", 2048)
        ui.text(2, chosen.clientId); ui.text(3, chosen.side .. " / " .. chosen.target)
        if height >= 7 then ui.text(4, chosen.targetType or "") end
        if dialog.error then ui.text(height - 2, dialog.error) end
        ui.button(height - 1, "Back", "back")
        ui.button(height, "Use", "use", 1, math.floor(width / 2), true, 32)
        ui.button(height, "Cancel", "cancel", math.floor(width / 2) + 1, width)
    else
        local slots = #list <= height - 2 and height - 2 or height - 3
        local pages = math.max(1, math.ceil(#list / slots))
        dialog.page = math.max(1, math.min(dialog.page, pages))
        ui.heading(({"Sensor client", "Sensor side", "Select target"})[dialog.stage], 2048)
        for row = 1, slots do
            local item = list[(dialog.page - 1) * slots + row]
            if item then ui.button(row + 1, item.label, "select", nil, nil, item.enabled ~= false, nil, nil, item) end
        end
        if #list == 0 then
            local message = "No sensor clients yet"
            if dialog.stage == 2 then
                message = selectedClient and selectedClient.online and "Waiting for catalog" or "Sensor client offline"
                if selectedClient and selectedClient.catalogError then
                    message = "Catalog rejected"
                    ui.text(3, selectedClient.catalogError)
                end
            elseif dialog.stage == 3 then
                message = selectedPort and #selectedPort.targets > 0 and "No matching targets" or "No targets yet"
            end
            ui.text(2, message)
        end
        if pages > 1 then
            ui.button(height - 1, "< Prev", "prev", 1, math.floor(width / 2), dialog.page > 1)
            ui.button(height - 1, "Next >", "next", math.floor(width / 2) + 1, width, dialog.page < pages, nil, nil, pages)
        end
        ui.button(height, "Back", "back", 1, math.floor(width / 2))
        ui.button(height, "Cancel", "cancel", math.floor(width / 2) + 1, width)
    end
    dialog.hits = ui.hits
    return ui.lines
end
function Picker.touch(dialog, x, y)
    for _, hit in ipairs(dialog.hits or {}) do if hit.enabled ~= false and Gui.hit(hit, x, y) then
        dialog.error = nil
        if hit.action == "cancel" then return "cancel"
        elseif hit.action == "use" then return "selected", dialog.chosen
        elseif hit.action == "back" then
            if dialog.stage == 1 then return "cancel" end
            dialog.stage, dialog.page = dialog.stage - 1, 1
        elseif hit.action == "prev" then dialog.page = math.max(1, dialog.page - 1)
        elseif hit.action == "next" then dialog.page = math.min(hit.value, dialog.page + 1)
        elseif hit.action == "select" then
            local item = hit.value
            if dialog.stage == 1 then dialog.chosen = {clientId = item.value}
            elseif dialog.stage == 2 then dialog.chosen.side, dialog.chosen.card = item.value, item.card
            else dialog.chosen.target, dialog.chosen.targetType = item.value, item.targetType end
            dialog.stage, dialog.page = dialog.stage + 1, 1
        end
        return
    end end
end
return Picker
