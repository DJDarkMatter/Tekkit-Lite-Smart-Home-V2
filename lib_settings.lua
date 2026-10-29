-- Built-in OS settings window. This is system UI, not an installed user app.
local Settings = {title = "OS settings", minWidth = 12, minHeight = 6, preferredWidth = 28, preferredHeight = 10}
local function build(width, height, api)
    local ui = api.ui.content(width, height)
    local settings = api.getOSSettings()
    ui.style(1, 1, width, height, 1, 32768)
    ui.heading("Appearance", 128)
    local items = {{label = "Background", action = "background", colour = settings.backgroundColour},
        {label = width >= 13 and "Window border" or "Borders", action = "windowBorder", colour = settings.windowBorderColour},
        {label = "Taskbar", action = "taskbar", colour = settings.taskbarColour}}
    for index, item in ipairs(items) do
        local label = width >= 24 and item.label .. ": " .. api.ui.colourName(item.colour) or item.label
        ui.button(3 + (index - 1) * (height >= 9 and 2 or 1), label, item.action, nil, nil, true, item.colour)
    end
    ui.text(height >= 9 and 9 or height, width >= 24 and "Applies to all monitors" or "All monitors", true)
    return ui.lines, ui.hits
end
function Settings.render(width, height, state, api)
    return (build(width, height, api))
end
function Settings.handleTouch(x, y, width, height, state, api, context)
    local _, hits = build(width, height, api)
    for _, hit in ipairs(hits) do
        if api.ui.hit(hit, x, y) then
            return api.pickColour(context.windowId, hit.action)
        end
    end
    return false
end
return Settings
