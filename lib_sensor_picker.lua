-- Shared client -> sensor port -> target selection, rendered centrally.
local Gui = dofile("lib_gui.lua")
local Picker = {}
function Picker.new(key, current, kind)
    return {kind = "sensor", key = key, chosen = current or {}, filter = kind, stage = 1, page = 1}
end
function Picker.render(dialog, width, height, clients, clientName)
    local label = clientName or function(id) return id end
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
        for _, client in ipairs(clients) do
            list[#list + 1] = {label = label(client.id) .. (client.online and " +" or " -"), value = {value = client.id}}
        end
    elseif dialog.stage == 2 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            selectedClient = client
            for _, port in ipairs(client.ports) do
                local enabled = compatible(port)
                local detail = port.status ~= "ok" and port.status or port.cardKind
                list[#list + 1] = {label = port.side .. " / " .. detail .. (not enabled and port.status == "ok" and " (other card)" or ""),
                    value = {value = port.side, card = port.card}, enabled = enabled}
            end
        end end
    elseif dialog.stage == 3 then
        for _, client in ipairs(clients) do if client.id == chosen.clientId then
            for _, port in ipairs(client.ports) do if port.side == chosen.side then
                selectedPort = port
                for _, target in ipairs(port.targets) do
                    if not dialog.filter or dialog.filter == "reactor" and (target.kind == "reactor" or target.type == "Unknown")
                        or dialog.filter ~= "reactor" and port.cardKind == dialog.filter then
                        list[#list + 1] = {label = target.key .. " " .. target.label,
                            value = {value = target.key, targetType = target.type}}
                    end
                end
            end end
        end end
    end
    local ui = Gui.content(width, height)
    ui.style(1, 1, width, height, 1, 32768)
    if dialog.stage == 4 then
        ui.heading("Use sensor?", 2048)
        ui.text(2, label(chosen.clientId)); ui.text(3, chosen.side .. " / " .. chosen.target)
        if height >= 7 then ui.text(4, chosen.targetType or "") end
        local depth = height >= 9 and 2 or 1
        if dialog.error then ui.text(height - depth - 1, dialog.error) end
        ui.button(height - depth, "Back", "back")
        ui.buttonRow(height - depth + 1, {{"Use", "use", nil, true, 32}, {"Cancel", "cancel"}}, depth)
    else
        local path = dialog.stage>1 and Gui.breadcrumb(dialog.stage==3 and {label(chosen.clientId),chosen.side} or {label(chosen.clientId)},width,height)
        local header = path and 2 or 1
        local page, pages = ui.pickerList(header + 1, list, dialog.page)
        dialog.page = page
        local title = ({"Sensor client", "Sensor side", "Select target"})[dialog.stage]
        ui.heading(title .. (pages > 1 and (" " .. page .. "/" .. pages) or ""), 2048)
        if path then ui.text(2,path); ui.style(1,2,width,1,256,32768) end
        if #list == 0 then
            local message = "No sensor clients yet"
            if dialog.stage == 2 then
                message = selectedClient and selectedClient.online and "Waiting for catalog" or "Sensor client offline"
                if selectedClient and selectedClient.catalogError then
                    message = "Catalog rejected"
                    ui.text(header+2, selectedClient.catalogError)
                end
            elseif dialog.stage == 3 then
                message = selectedPort and #selectedPort.targets > 0 and "No matching targets" or "No targets yet"
            end
            ui.text(header+1, message)
        end
    end
    ui.finish(true)
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
