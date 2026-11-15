-- Exercise the installed app through real monitor touches and HTTP events.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local name = "file_explorer"
    local file = assert(io.open("apps_file_explorer.lua", "r"))
    local source = file:read("*a"); file:close()
    local function setup()
        local bus = newBus()
        local central = bus.computer(10, "server", {apps = {["apps_file_explorer.lua"] = source}})
        local disk = central.disk
        disk.dirs.rom = true
        disk.dirs.alpha = true
        disk.dirs["alpha/nested"] = true
        disk.files["alpha/nested/item.txt"] = "keep me"
        disk.files["rom/help"] = "ROM help"
        disk.files["guide.lua"] = "print('hello & goodbye')\n"
        central:start()
        local display = bus.computer(13, "monitor", {monitors = {top = monitor(72, 30), left = monitor(16, 10)}}):start()
        local t = {bus = bus, central = central, disk = disk}
        function t.open(side)
            local id = assert(central.server.api.openApp(name, "monitor_13:" .. side, 1, 1,
                side == "left" and 14 or 58, side == "left" and 8 or 24))
            central.server.refreshMonitors(true); bus.pump()
            return id
        end
        function t.lines(id)
            local win = central.server.state.windows[id]
            return central.server.apps[name].render(win.width - 2, win.height - 2, central.server.state.appStates[name],
                central.server.api, {windowId = id, view = central.server.views[id]})
        end
        function t.hit(id, action, value, disabled)
            local lines = t.lines(id)
            for _, hit in ipairs(lines.hits) do
                if hit.action == action and (disabled or hit.enabled ~= false)
                    and (value == nil or hit.value == value or type(value) == "function" and value(hit)) then return hit end
            end
        end
        function t.tap(id, hit)
            central.server.refreshMonitors(true); bus.pump()
            local win = central.server.state.windows[id]
            local side = win.monitorId:match("[^:]+$")
            bus.queue(display, {"monitor_touch", side, win.x + hit.x1, win.y + (hit.y or hit.y1)})
            bus.pump()
        end
        function t.click(id, action, value)
            for attempt = 1, 30 do
                local hit = t.hit(id, action, value)
                if hit then t.tap(id, hit); return end
                local nextPage = t.hit(id, "page", function(h) return h.label == ">" end)
                if not nextPage then break end
                t.tap(id, nextPage)
            end
            error("Missing File Explorer action " .. action .. " " .. tostring(value), 0)
        end
        function t.type(id, text)
            for char in text:gmatch(".") do
                for bank = 1, 3 do
                    local hit = t.hit(id, "key", char)
                    local page = t.hit(id, "keyPage")
                    local pages = page and tonumber(page.label:match("/(%d+)$")) or 1
                    for j = 2, pages do
                        if hit then break end
                        t.tap(id, assert(t.hit(id, "keyPage")))
                        hit = t.hit(id, "key", char)
                    end
                    if hit then t.tap(id, hit); break end
                    assert(bank < 3, "Missing key " .. char)
                    t.click(id, "bank")
                end
            end
        end
        function t.text(id) return table.concat(t.lines(id), "\n") end
        return t
    end

    function tests.v54_file_explorer_creates_and_pages_files_and_folders_on_a_compact_monitor()
        local t = setup()
        local id = t.open("left")
        local lines = t.lines(id)
        equal(lines.hits[3].value, "alpha", "Folders precede files")
        assert(t.hit(id, "page", function(hit) return hit.label == ">" end))
        t.click(id, "menu"); t.click(id, "newFolder"); t.type(id, "work"); t.click(id, "accept")
        assert(t.disk.dirs.work)
        t.click(id, "files"); t.click(id, "open", "work"); t.click(id, "menu")
        t.click(id, "newFile"); t.type(id, "test.txt"); t.click(id, "accept")
        t.type(id, "hello"); t.click(id, "newLine"); t.type(id, "world"); t.click(id, "accept")
        equal(t.disk.files["work/test.txt"], "hello\nworld")
        t.click(id, "files"); t.click(id, "open", "work/test.txt"); t.click(id, "preview")
        assert(t.text(id):find("hello", 1, true) and t.text(id):find("world", 1, true))
        assert(t.central.server.save())
        local restarted = t.bus.computer(10, "server", {disk = t.disk}):start()
        equal(restarted.server.views[id].directory, "work")
    end

    function tests.v54_file_explorer_shares_clipboard_preserves_originals_and_blocks_invalid_destinations()
        local t = setup()
        local a, b = t.open("top"), t.open("left")
        t.click(a, "open", "guide.lua"); t.click(a, "copyFile")
        t.click(b, "open", "alpha"); t.click(b, "paste")
        equal(t.disk.files["alpha/guide.lua"], t.disk.files["guide.lua"])
        t.click(b, "files"); t.click(b, "paste")
        assert(t.text(b):find("Action faile", 1, true))
        equal(t.disk.files["alpha/guide.lua"], t.disk.files["guide.lua"])
        t.click(b, "files"); t.click(b, "menu"); t.click(b, "pasteAs"); t.click(b, "clearText")
        t.type(b, "copy.lua"); t.click(b, "accept")
        equal(t.disk.files["alpha/copy.lua"], t.disk.files["guide.lua"])
        t.click(b, "files"); t.click(b, "menu"); t.click(b, "moveFolder")
        t.click(a, "open", "alpha"); t.click(a, "open", "alpha/nested"); t.click(a, "paste")
        assert(t.text(a):find("outside the source", 1, true))
        assert(not t.disk.dirs["alpha/nested/alpha"])
        t.click(a, "files"); t.click(a, "up"); t.click(a, "up")
        t.click(a, "menu"); t.click(a, "pasteAs"); t.click(a, "clearText"); t.type(a, "moved")
        local copy = t.central.env.fs.copy
        t.central.env.fs.copy = function(_, path) t.disk.dirs[path] = true; error("Partial copy") end
        t.click(a, "accept")
        equal(t.disk.dirs.moved, nil)
        equal(t.disk.files["alpha/nested/item.txt"], "keep me")
        t.central.env.fs.copy = copy
        t.click(a, "keyboard"); t.click(a, "accept")
        equal(t.disk.files["moved/nested/item.txt"], "keep me")
        equal(t.disk.dirs.alpha, nil)
        t.click(a, "files"); t.click(a, "open", "rom"); t.click(a, "menu")
        for _, action in ipairs({"newFile", "newFolder", "moveFolder", "getPaste"}) do
            equal(assert(t.hit(a, action, nil, true)).enabled, false)
        end
        assert(t.hit(a, "copyFolder"))
    end

    function tests.v54_file_explorer_pastebin_round_trip_is_async_and_keeps_keys_out_of_saved_state()
        local t = setup()
        local id = t.open("top")
        local requests = {}
        t.central.env.http = {request = function(url, body, headers)
            requests[#requests + 1] = {url = url, body = body, headers = headers}
            -- CraftOS versions may return nothing for a queued request.
        end}
        t.click(id, "menu"); t.click(id, "getPaste"); t.type(id, "abc"); t.click(id, "accept"); t.click(id, "accept")
        equal(#requests, 1); equal(requests[1].body, nil)
        assert(requests[1].url:match("^https://pastebin%.com/raw/abc%?"))
        equal(t.disk.files["abc.txt"], nil)
        local before = t.central.server.lastTick
        t.bus.advance(1)
        assert(t.central.server.lastTick > before, "HTTP should not block the OS tick")
        local function respond(request, body)
            local closed = false
            t.bus.queue(t.central, {"http_success", request.url, {readAll = function() return body end,
                close = function() closed = true end, getResponseCode = function() return 200 end}})
            t.bus.pump()
            assert(closed)
        end
        local bytes = "return 1\n-- café + &"
        respond(requests[1], bytes)
        equal(t.disk.files["abc.txt"], bytes)
        t.click(id, "files"); t.click(id, "open", "abc.txt"); t.click(id, "upload"); t.type(id, "fakekey")
        assert(t.text(id):find("*******", 1, true) and not t.text(id):find("fakekey", 1, true))
        t.click(id, "accept")
        equal(#requests, 1, "Wait for the explicit send confirmation")
        assert(t.text(id):find("Anyone with the link", 1, true))
        t.click(id, "sendPaste")
        equal(#requests, 2)
        assert(requests[2].url:match("^https://pastebin%.com/api/api_post%.php%?"))
        assert(requests[2].body:find("api_paste_private=1", 1, true))
        assert(requests[2].body:find("api_paste_code=return%201%0A--%20caf%C3%A9%20%2B%20%26", 1, true))
        respond(requests[2], "https://pastebin.com/z9p3\n")
        assert(t.text(id):find("ID: z9p3", 1, true))
        assert(t.central.server.save())
        for path, raw in pairs(t.disk.files) do assert(not raw:find("fakekey", 1, true), path) end
        t.click(id, "file"); t.click(id, "files"); t.click(id, "menu"); t.click(id, "getPaste")
        t.type(id, "def"); t.click(id, "accept"); t.click(id, "accept")
        t.disk.files["def.txt"] = "created while waiting"
        respond(requests[3], "older contents")
        equal(t.disk.files["def.txt"], "created while waiting")
        assert(t.text(id):find("already exists", 1, true))
        t.click(id, "files"); t.click(id, "menu"); t.click(id, "getPaste")
        t.type(id, "late"); t.click(id, "accept"); t.click(id, "accept")
        t.bus.advance(31)
        assert(t.text(id):find("timed out", 1, true))
        respond(requests[4], "late response")
        equal(t.disk.files["late.txt"], nil)
    end
end
