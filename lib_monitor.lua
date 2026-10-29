-- A display/input bridge only. All app code and hit testing stay on the OS.
local Monitor = {}
local Gui = dofile("lib_gui.lua")
local sides = {"top", "bottom", "left", "right", "front", "back"}

function Monitor.new(net, config)
    assert(type(config.clientId) == "string" and #config.clientId > 0, "Invalid monitor clientId")
    local client = {devices = {}, config = config}
    local function status(device, text)
        if device.peripheral.setBackgroundColor then device.peripheral.setBackgroundColor(32768) end
        if device.peripheral.setTextColor then device.peripheral.setTextColor(1) end
        device.peripheral.clear()
        device.peripheral.setCursorPos(1, 1)
        device.peripheral.write(text:sub(1, device.width))
        device.cache = {}
    end
    function client.scan()
        local present = {}
        for _, side in ipairs(sides) do
            if peripheral.getType(side) == "monitor" then
                present[side] = true
                local device = client.devices[side]
                local wrapped = peripheral.wrap(side)
                if not device or device.textScale ~= config.textScale then
                    if wrapped.setBackgroundColor then wrapped.setBackgroundColor(colors.black) end
                    if wrapped.setTextColor then wrapped.setTextColor(colors.white) end
                    wrapped.setTextScale(config.textScale)
                end
                local width, height = wrapped.getSize()
                if not device then
                    device = {id = config.clientId .. ":" .. side, side = side, peripheral = wrapped,
                        width = width, height = height, nonce = 0, lastAnnounce = -math.huge,
                        lastServer = 0, connected = false, textScale = config.textScale,
                        colour = (wrapped.isColor or wrapped.isColour) and (wrapped.isColor or wrapped.isColour)() or false}
                    client.devices[side] = device
                    status(device, "Connecting to SmartHome OS...")
                else
                    local oldColour = device.colour
                    device.peripheral = wrapped
                    device.textScale = config.textScale
                    device.colour = (wrapped.isColor or wrapped.isColour) and (wrapped.isColor or wrapped.isColour)() or false
                    if oldColour ~= device.colour then device.cache = {} end
                    if width ~= device.width or height ~= device.height then
                        device.width, device.height, device.lastAnnounce = width, height, -math.huge
                        device.cache = {}
                        device.inputRevision, device.hasFrame = nil, false
                    end
                end
            end
        end
        for side in pairs(client.devices) do if not present[side] then client.devices[side] = nil end end
    end
    function client.handle(message, now)
        for _, device in pairs(client.devices) do
            if message.clientId == device.id then
                if message.type == "welcome" and message.nonce == device.nonce
                    and type(message.serverSession) == "string"
                    and (not device.connected or message.sender == device.serverId) then
                    local changed = not device.connected or device.serverSession ~= message.serverSession
                    device.connected, device.lastServer = true, now
                    device.serverId, device.serverSession = message.sender, message.serverSession
                    if changed then
                        print("Monitor " .. device.side .. " connected to OS " .. message.sender)
                        device.cache = {}
                        device.frameId, device.inputRevision, device.hasFrame = nil, nil, false
                    end
                elseif message.type == "render" and device.connected
                    and message.sender == device.serverId and message.serverSession == device.serverSession
                    and message.width == device.width and message.height == device.height
                    and type(message.lines) == "table" then
                    if message.frameId and (type(message.frameId) ~= "number" or message.frameId < 1 or message.frameId ~= math.floor(message.frameId)
                        or (device.frameId and message.frameId <= device.frameId)) then return end
                    local foreground, background = {}, {}
                    local paint = {}
                    for y = 1, device.height do
                        if message.colourFormat == "rle1" then
                            foreground[y] = Gui.unpack(type(message.foreground) == "table" and message.foreground[y], device.width)
                            background[y] = Gui.unpack(type(message.background) == "table" and message.background[y], device.width)
                            if not foreground[y] or not background[y] then return end
                        else foreground[y], background[y] = string.rep("0", device.width), string.rep("f", device.width) end
                    end
                    for y = 1, device.height do
                        local line = message.lines[y]
                        if type(line) ~= "string" then line = "" end
                        line = line:sub(1, device.width)
                        line = line .. string.rep(" ", device.width - #line)
                        local signature = line .. foreground[y] .. background[y]
                        if device.cache[y] ~= signature then
                            Gui.drawRow(device.peripheral, y, line, foreground[y], background[y], device.colour, paint)
                            device.cache[y] = signature
                        end
                    end
                    device.lastServer = now
                    device.frameId, device.inputRevision = message.frameId, message.inputRevision
                    device.hasFrame = true
                end
                return
            end
        end
    end
    function client.touch(side, x, y, revision)
        local device = client.devices[side]
        if device and device.connected and device.hasFrame then
            local offset = type(config.touchOffsets) == "table" and config.touchOffsets[side] or nil
            x, y = x + (offset and offset.x or 0), y + (offset and offset.y or 0)
            net.send(net.config.channel, device.serverId, {type = "touch", clientId = device.id,
                monitorId = device.id, x = x, y = y, serverSession = device.serverSession,
                inputRevision = revision == nil and device.inputRevision or revision})
        end
    end
    function client.tick(now)
        -- CC 1.5 may not emit monitor_resize; polling also discovers late screens.
        client.scan()
        local available = net.ensureModem()
        for _, device in pairs(client.devices) do
            if device.connected and (not available or now - device.lastServer >= config.timeout) then
                device.connected = false
                status(device, "OS offline; reconnecting...")
            end
            if available and now - device.lastAnnounce >= config.announceInterval then
                device.nonce = device.nonce + 1
                net.toServer({type = "announce", clientType = "monitor", clientId = device.id,
                    nonce = device.nonce, width = device.width, height = device.height, touchProtocol = 1})
                device.lastAnnounce = now
            end
        end
    end
    function client.calibrate(side, mode)
        local device = assert(client.devices[side], "No monitor on that side")
        local w, h = device.width, device.height
        device.cache = {}
        assert(w >= 12 and h >= 8, "Calibration needs at least 12x8 characters")
        local targets = {}
        for _, y in ipairs({3, math.floor(h / 2), h - 3}) do
            for _, x in ipairs({math.max(3, math.floor(w / 6)), math.floor(w / 2), math.min(w - 2, math.floor(5 * w / 6))}) do
                targets[#targets + 1] = {x, y}
            end
        end
        local previous = config.touchOffsets and config.touchOffsets[side] or {x = 0, y = 0}
        local candidate = {x = previous.x, y = previous.y}
        local stage, last, mixed = mode == "test" and "preview" or "samples", nil, false
        local function draw(surface)
            local paint = {}
            for row = 1, h do Gui.drawRow(device.peripheral, row, surface.lines[row], surface.foreground[row], surface.background[row], device.colour, paint) end
        end
        local function event()
            while true do
                local kind, value, x, y = os.pullEvent()
                if kind == "monitor_touch" and value == side and type(x) == "number" and type(y) == "number"
                    and x == math.floor(x) and y == math.floor(y) and x >= 1 and x <= w and y >= 1 and y <= h then return "touch", x, y end
                if kind == "char" and type(value) == "string" then
                    local actions = {r = "retry", c = "cancel", q = "cancel", s = "save", ["0"] = "reset", z = "reset"}
                    if actions[value:lower()] then return actions[value:lower()] end
                elseif kind == "key" then
                    local actions = {[1] = "cancel", [203] = "left", [205] = "right", [200] = "up", [208] = "down"}
                    if actions[value] then return actions[value] end
                end
            end
        end
        local function footer(surface, first)
            local third = math.floor(w / 3)
            local labels = {w < 15 and first == "Retry" and "R" or first, w >= 15 and "Reset" or "0", w >= 18 and "Cancel" or "Exit"}
            for index, label in ipairs(labels) do
                local x, stop = (index - 1) * third + 1, index == 3 and w or index * third
                surface.fill(x, h, stop - x + 1, 1, 1, index == 3 and 16384 or index == 1 and 8192 or 128)
                surface.write(x + math.floor((stop - x + 1 - #label) / 2), h, label)
            end
        end
        local function footerAction(action, x, y, first)
            if action == "touch" and y == h then
                local third = math.floor(w / 3)
                return x <= third and first or x <= third * 2 and "reset" or "cancel"
            end
            return action
        end
        while true do
            if stage == "samples" then
                local xs, ys, interrupted = {}, {}, false
                for index, target in ipairs(targets) do
                    local surface = Gui.new(w, h, 1, 2048)
                    surface.write(1, 1, "Circle " .. index .. "/" .. #targets)
                    for row, pixels in ipairs({"01110", "10001", "01110"}) do
                        for column = 1, #pixels do
                            if pixels:sub(column, column) == "1" then
                                surface.fill(target[1] + column - 3, target[2] + row - 2, 1, 1, 1, 1)
                            end
                        end
                    end
                    surface.write(target[1], target[2], "+", 32768, 1)
                    footer(surface, "Retry"); draw(surface)
                    while true do
                        local action, x, y = event()
                        action = footerAction(action, x, y, "retry")
                        if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                        if action == "reset" then
                            candidate, last, mixed, stage, interrupted = {x = 0, y = 0}, nil, false, "preview", true; break
                        elseif action == "retry" then interrupted = true; break
                        elseif action == "touch" then
                            if math.abs(target[1] - x) <= 4 and math.abs(target[2] - y) <= 4 then
                                xs[index], ys[index] = target[1] - x, target[2] - y
                                print("Sample " .. index .. ": expected " .. target[1] .. "," .. target[2]
                                    .. "; received " .. x .. "," .. y .. "; offset " .. xs[index] .. "," .. ys[index])
                                break
                            end
                            surface.write(1, h - 1, "Tap circle centre"); draw(surface)
                        end
                    end
                    if interrupted then break end
                end
                if not interrupted then
                    table.sort(xs); table.sort(ys)
                    local dx, dy = xs[5], ys[5]
                    local consistent = math.abs(dx) <= 3 and math.abs(dy) <= 3
                    local countX, countY, totalX, totalY = 0, 0, 0, 0
                    for index = 1, #targets do
                        consistent = consistent and math.abs(xs[index] - dx) <= 1 and math.abs(ys[index] - dy) <= 1
                            and math.abs(xs[index]) <= 3 and math.abs(ys[index]) <= 3
                        countX, countY = countX + (xs[index] == dx and 1 or 0), countY + (ys[index] == dy and 1 or 0)
                        totalX, totalY = totalX + xs[index], totalY + ys[index]
                    end
                    print(string.format("Average measured X:%.2f Y:%.2f cells; median agreement X:%d/9 Y:%d/9",
                        totalX / #targets, totalY / #targets, countX, countY))
                    if consistent then
                        mixed = countX < 7 or countY < 7
                        -- A near half-cell split cannot be represented faithfully.
                        -- Do not turn an uncertain measurement into a forced 1-cell shift.
                        if countX < 7 then dx = 0 end
                        if countY < 7 then dy = 0 end
                        candidate, last, stage = {x = dx, y = dy}, nil, "preview"
                        if mixed then print("Mixed readings: testing stock on uncertain axes; no fractional touch data is available.") end
                        print("Test proposed offset " .. dx .. "," .. dy .. ". Arrows adjust; 0 resets; S saves; R remeasures; C cancels.")
                    else stage = "retry" end
                end
            elseif stage == "retry" then
                local surface = Gui.new(w, h, 1, 32768)
                surface.write(1, 1, "Calibration needs retry", 1, 16384)
                surface.write(1, 2, "Taps differ too much")
                surface.write(1, 3, "Old offset kept")
                surface.write(1, 4, "R:retry 0:reset C:exit")
                footer(surface, "Retry"); draw(surface)
                print("Samples differ too much. Retry, Reset or Cancel; previous offset is unchanged.")
                local action, x, y = event()
                action = footerAction(action, x, y, "retry")
                if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                if action == "retry" then stage = "samples"
                elseif action == "reset" then candidate, last, mixed, stage = {x = 0, y = 0}, nil, false, "preview" end
            else
                local surface = Gui.new(w, h, 1, 2048)
                surface.write(1, 1, "Test before saving", 1, 128)
                surface.write(1, 2, "X:" .. candidate.x .. " Y:" .. candidate.y .. "  S:save")
                local points = {}
                for _, y in ipairs({3, 3 + math.floor((h - 6) / 2), h - 3}) do
                    for _, x in ipairs({2, math.floor(w / 2), w - 1}) do
                        surface.write(x, y, "+", 32768, 1); points[x .. ":" .. y] = true
                    end
                end
                if last then
                    local x, y = last.x + candidate.x, last.y + candidate.y
                    if x >= 1 and x <= w and y >= 3 and y <= h - 3 then
                        surface.write(x, y, "X", 1, points[x .. ":" .. y] and 8192 or 16384)
                    end
                end
                local arrows, quarter = {" < ", " > ", " ^ ", " v "}, math.floor(w / 4)
                for index, label in ipairs(arrows) do
                    local x = (index - 1) * quarter + 1
                    surface.fill(x, h - 2, index == 4 and w - x + 1 or quarter, 1, 1, 128)
                    surface.write(x, h - 2, label)
                end
                surface.write(1, h - 1, mixed and "Mixed readings: test!" or "R:remeasure 0:stock")
                footer(surface, "Save"); draw(surface)
                local action, x, y = event()
                action = footerAction(action, x, y, "save")
                if action == "touch" and y == h - 2 then
                    action = ({"left", "right", "up", "down"})[math.min(4, math.floor((x - 1) / quarter) + 1)]
                end
                if action == "save" then return {x = candidate.x, y = candidate.y} end
                if action == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                if action == "retry" then stage = "samples"
                elseif action == "reset" then candidate, last, mixed = {x = 0, y = 0}, nil, false
                elseif action == "left" then candidate.x = math.max(-3, candidate.x - 1)
                elseif action == "right" then candidate.x = math.min(3, candidate.x + 1)
                elseif action == "up" then candidate.y = math.max(-3, candidate.y - 1)
                elseif action == "down" then candidate.y = math.min(3, candidate.y + 1)
                elseif action == "touch" and y >= 3 and y <= h - 3 then last = {x = x, y = y} end
            end
        end
    end
    function client.showStatus(side, text)
        status(assert(client.devices[side], "No monitor on that side"), text)
    end
    return client
end
return Monitor
