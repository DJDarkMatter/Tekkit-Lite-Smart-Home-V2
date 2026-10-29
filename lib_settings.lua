-- Built-in OS settings window. This is system UI, not an installed user app.
local Settings = {title = "OS settings", minWidth = 12, minHeight = 6, preferredWidth = 28, preferredHeight = 8}
local function build(width, height, api)
    local ui = api.ui.content(width, height)
    local settings = api.getOSSettings()
    ui.heading("Appearance", 128)
    ui.button(3, "Background", "background", nil, nil, true, settings.backgroundColour)
    ui.text(4, api.ui.colourName(settings.backgroundColour), true)
    if height >= 8 then ui.text(6, width >= 24 and "Applies to all monitors" or "All monitors", true) end
    return ui.lines, ui.hits
end
function Settings.render(width, height, state, api)
    return (build(width, height, api))
end
function Settings.handleTouch(x, y, width, height, state, api, context)
    local _, hits = build(width, height, api)
    for _, hit in ipairs(hits) do
        if api.ui.hit(hit, x, y) and hit.action == "background" then
            return api.pickColour(context.windowId, "background")
        end
    end
    return false
end
return Settings
