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
    function client.calibrate(side)
        local device = assert(client.devices[side], "No monitor on that side")
        local w, h = device.width, device.height
        device.cache = {}
        assert(w >= 12 and h >= 8, "Calibration needs at least 12x8 characters")
        local targets = {{math.floor(w / 4), math.max(3, math.floor(h / 4))},
            {math.floor(3 * w / 4), math.floor(h / 2)}, {math.floor(w / 2), math.min(h - 1, math.floor(3 * h / 4))}}
        local function draw(surface)
            local paint = {}
            for row = 1, h do Gui.drawRow(device.peripheral, row, surface.lines[row], surface.foreground[row], surface.background[row], device.colour, paint) end
        end
        local function touch()
            while true do
                local event, touched, x, y = os.pullEvent()
                if event == "monitor_touch" and touched == side and type(x) == "number" and type(y) == "number"
                    and x == math.floor(x) and y == math.floor(y) and x >= 1 and x <= w and y >= 1 and y <= h then return x, y end
                if event == "char" and type(touched) == "string" and touched:lower() == "r" then return "retry" end
                if (event == "char" and type(touched) == "string" and (touched:lower() == "c" or touched:lower() == "q"))
                    or (event == "key" and touched == 1) then return "cancel" end
            end
        end
        while true do
            local xs, ys, restart = {}, {}, false
            for index, target in ipairs(targets) do
                local surface = Gui.new(w, h, 1, 2048)
                surface.write(1, 1, "Tap white + " .. index .. "/3")
                surface.fill(target[1] - 1, target[2] - 1, 3, 3, 1, 128)
                surface.write(target[1], target[2], "+", 32768, 1)
                draw(surface)
                local x, y
                while true do
                    x, y = touch()
                    if x == "cancel" then return nil, "Calibration cancelled; previous offset kept" end
                    if x == "retry" then restart = true; break end
                    if math.abs(target[1] - x) <= 4 and math.abs(target[2] - y) <= 4 then break end
                    -- A queued repeat of the previous target is not a sample
                    -- of this target. Keep it visible and explain what to tap.
                    surface.write(1, h, "Tap centre of white +")
                    draw(surface)
                end
                if restart then break end
                xs[index], ys[index] = target[1] - x, target[2] - y
                print("Sample " .. index .. ": expected " .. target[1] .. "," .. target[2]
                    .. "; received " .. x .. "," .. y .. "; offset " .. xs[index] .. "," .. ys[index])
            end
            if not restart then
                -- A tap can round to an adjacent native cell. Use the median
                -- only when every sample lies within one cell of it on each axis.
                table.sort(xs); table.sort(ys)
                local dx, dy = xs[2], ys[2]
                local consistent = math.abs(dx) <= 3 and math.abs(dy) <= 3
                for index = 1, 3 do
                    consistent = consistent and math.abs(xs[index] - dx) <= 1 and math.abs(ys[index] - dy) <= 1
                        and math.abs(xs[index]) <= 3 and math.abs(ys[index]) <= 3
                end
                if consistent then return {x = dx, y = dy} end
                local surface = Gui.new(w, h, 1, 32768)
                surface.write(1, 1, "Calibration needs retry", 1, 16384)
                surface.write(1, 2, "Taps differ too much")
                surface.write(1, 3, "Old offset kept")
                surface.write(1, 4, "R: retry  C: cancel")
                local half = math.floor(w / 2)
                surface.fill(1, h - 2, half, 3, 1, 8192)
                surface.fill(half + 1, h - 2, w - half, 3, 1, 16384)
                surface.write(1, h - 1, "Retry"); surface.write(half + 1, h - 1, "Cancel")
                draw(surface)
                print("Samples differ too much. Tap Retry/Cancel, or press R/C on this computer. Previous offset is unchanged.")
                while true do
                    local x, y = touch()
                    if x == "cancel" or (type(x) == "number" and y >= h - 2 and x > half) then
                        return nil, "Calibration cancelled; previous offset kept"
                    end
                    if x == "retry" or (type(x) == "number" and y >= h - 2 and x <= half) then break end
                end
            end
        end
    end
    function client.showStatus(side, text)
        status(assert(client.devices[side], "No monitor on that side"), text)
    end
    return client
end
return Monitor
