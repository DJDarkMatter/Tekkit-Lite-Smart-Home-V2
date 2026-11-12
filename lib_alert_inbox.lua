-- Monitor-local sidebar over the desktop. History is owned by the OS.
local Inbox = {}

function Inbox.render(monitor, entries, api)
    local view = monitor.inbox
    local small = monitor.width < 34 or monitor.height < 10
    local width, height = small and monitor.width or math.min(38, math.floor(monitor.width * .48)),
        small and monitor.height or monitor.height - 1
    local x = monitor.width - width + 1
    local ui = api.ui.form(width, height, view, 2048)
    local selected
    for _, item in ipairs(entries) do if item.sequence == view.selected then selected = item; break end end
    if height < 5 or width < 8 then
        ui.heading("Alerts", 2048)
        ui.footer({{"Back", "close"}})
    elseif selected then
        local stamp = (selected.day and "Day " .. selected.day .. " " or "") .. selected.time
        ui.info(selected.title, {stamp, selected.message, selected.open and "Active" or "Closed"}, "details", "list")
    else
        local rows = {}
        for i = #entries, 1, -1 do
            local item = entries[i]
            rows[#rows + 1] = {(item.open and "* " or "") .. item.title .. " " .. item.time,
                "details", item.sequence, true, item.open and 16384 or nil}
        end
        if #rows == 0 then rows[1] = {"No alerts yet", nil, nil, false} end
        ui.menu("Alert inbox", rows, "alerts", {{"Back", "close"}})
    end
    ui.finish()
    return {x = x, width = width, height = height, lines = ui.lines, hits = ui.hits}
end

function Inbox.touch(monitor, model, api, x, y)
    if x < model.x or y > model.height then return false end
    local view = monitor.inbox
    local action, value = api.ui.actionAt(model.hits, x - model.x + 1, y)
    if action == "close" then monitor.inbox = nil
    elseif action == "list" then view.selected = nil
    elseif action == "details" then view.selected, view.pages.details = value, 1
    elseif action == "page" then view.pages[value.key] = value.page end
    return true
end

return Inbox
