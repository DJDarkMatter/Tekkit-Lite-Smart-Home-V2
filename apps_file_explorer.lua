-- Browse the central computer with CraftOS filesystem and HTTP APIs.
local app = {title = "File Explorer", minWidth = 12, minHeight = 6, preferredWidth = 42, preferredHeight = 16}
local Storage = dofile("lib_storage.lua")
local appName, pastebin = "file_explorer", "https://pastebin.com"
local windows, jobs, clipboard = {}, {}, nil
local sequence = 0

local function base(path) return path:match("[^/]+$") or "/" end
local function parent(path) return path:match("^(.*)/[^/]+$") or "" end
local function join(path, name) return path == "" and name or path .. "/" .. name end
local function display(text, width, tail)
    if #text <= width then return text end
    if tail then return ".." .. text:sub(-(width - 2)) end
    return text:sub(1, width - 2) .. ".."
end
local function readOnly(path)
    return fs.isReadOnly and fs.isReadOnly(path) or path == "rom" or path:sub(1, 4) == "rom/"
end
local function canMove(path)
    if path == "" or readOnly(path) then return false end
    local drive = fs.getDrive and fs.getDrive(path)
    return not drive or drive == fs.getDrive(parent(path))
end
local function directory(view)
    local path = type(view.directory) == "string" and view.directory or ""
    while path ~= "" and not fs.isDir(path) do path = parent(path) end
    view.directory = path
    return path
end
local function openDirectory(view, window, path)
    view.directory, window.screen, window.pages, window.listing = path, "files", {}, nil
end
local function refreshLists()
    for _, window in pairs(windows) do window.listing = nil end
end
local function errorText(err)
    return (tostring(err):gsub("^.-:%d+:%s*", "", 1))
end
local function actionMenu(window, title, lines, back)
    window.message = {title = title, lines = lines, back = back}
    window.screen = "message"
    window.pages.message = nil
end
local function keyboard(window, purpose, prompt, value, back, dir)
    window.screen = "keyboard"
    window.keyboard = {purpose = purpose, prompt = prompt, draft = value or "", bank = 0, page = 1,
        back = back, directory = dir}
end
local function newPath(dir, name)
    assert(fs.isDir(dir), "The destination folder is missing")
    assert(not readOnly(dir), "This folder is read-only")
    assert(name:find("%S") and name ~= "." and name ~= ".." and not name:find('[%c/\\:*?"<>|]'), "Enter a file or folder name")
    local path = join(dir, name)
    assert(not fs.combine or fs.combine(dir, name) == path, "Use a valid CraftOS filename")
    assert(not fs.exists(path), "That name already exists")
    return path
end

local function paste(dir, name)
    assert(clipboard and fs.exists(clipboard.path), "The clipboard source is missing")
    local source, moving = clipboard.path, clipboard.moving
    local path = newPath(dir, name or base(source))
    assert(path:sub(1, #source + 1) ~= source .. "/", "Choose a folder outside the source")
    assert(not moving or canMove(source), "The source is read-only or is a drive")
    local ok, err = pcall(fs.copy, source, path)
    if not ok or err == false or not fs.exists(path) then
        if fs.exists(path) then pcall(fs.delete, path) end
        error(tostring(not ok and err or "Copy failed"), 0)
    end
    if moving then
        clipboard = nil
        local removed, reason = pcall(fs.delete, source)
        if not removed or fs.exists(source) then
            error("Copied to /" .. path .. ". Could not remove source: " .. tostring(reason or source), 0)
        end
    end
    return path
end

local function listing(window, dir, api)
    local cached = window.listing
    local now = os.clock()
    if cached and cached.path == dir and now - cached.time < 2 then return cached.items, cached.error end
    local ok, names = pcall(fs.list, dir)
    local items = {}
    if ok then
        for _, name in ipairs(names) do
            local path = join(dir, name)
            items[#items + 1] = {name = name, path = path, folder = fs.isDir(path)}
            api.cooperate(64)
        end
        table.sort(items, function(a, b)
            if a.folder ~= b.folder then return a.folder end
            local aa, bb = a.name:lower(), b.name:lower()
            return aa == bb and a.name < b.name or aa < bb
        end)
    end
    local problem = not ok and tostring(names) or nil
    window.listing = {path = dir, time = now, items = items, error = problem}
    return items, problem
end

local function readPreview(path, api)
    local file = assert(fs.open(path, "r"), "Cannot open file")
    local limit, chunks, total = 8192, {}, 0
    local ok, contents, more = api.protectedCall(function()
        if not file.readLine then
            local raw = file.readAll() or ""
            return raw:sub(1, limit), #raw > limit
        end
        while total < limit do
            local line = file.readLine()
            if not line then break end
            local piece = (line .. "\n"):sub(1, limit - total)
            chunks[#chunks + 1], total = piece, total + #piece
            api.cooperate(32 + #piece)
        end
        return table.concat(chunks), total >= limit
    end)
    file.close()
    assert(ok, contents)
    local lines = {}
    for line in (contents .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    if contents == "" then lines[1] = "Empty file" end
    if more then lines[#lines + 1] = "Preview ends at 8 KB" end
    return lines
end

local function pasteID(text, urlOnly)
    text = text:match("^%s*(.-)%s*$")
    return (not urlOnly and text:match("^([A-Za-z0-9]+)$")) or text:match("^https?://pastebin%.com/([A-Za-z0-9]+)/?$")
        or text:match("^https?://pastebin%.com/raw/([A-Za-z0-9]+)/?$")
end
local function startRequest(job, api, url, data, headers)
    sequence = sequence + 1
    local session = api.getSystem().session:gsub("[^%w]", "-")
    url = url .. (url:find("?", 1, true) and "&" or "?") .. "smarthome=" .. session .. "-" .. sequence
    local ok, err = api.requestHttp(url, data, headers)
    if not ok then return false, err end
    jobs[url] = job
    job.window.screen, job.window.job = "waiting", url
    return true
end

local function finishUpload(job, err)
    local lines = {}
    if err then lines[1] = errorText(err) end
    for line in job.output:gmatch("[^\r\n]+") do
        local receipt = line:match("^[Uu]ploaded as%s+(.+)$")
        local id = not err and not job.printedError and pasteID(receipt or line, receipt == nil)
        if id then
            actionMenu(job.window, "Paste created", {"ID: " .. id, pastebin .. "/" .. id}, "file")
            return
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then lines[1] = "The command returned no paste link" end
    actionMenu(job.window, "Pastebin error", lines, "file")
end

local function resumeUpload(job, api, ...)
    local ok, url, body, headers = coroutine.resume(job.thread, ...)
    if not ok then return finishUpload(job, url) end
    if coroutine.status(job.thread) == "dead" then return finishUpload(job, job.requestError) end
    local eventRequest = job.eventRequest
    job.eventRequest = nil
    if eventRequest and (url == nil or url == "http_success" or url == "http_failure") then
        url, body, headers = eventRequest.url, eventRequest.body, eventRequest.headers
        job.eventUrl = url
    end
    if type(url) ~= "string" or not url:match("^https?://") then
        return finishUpload(job, "The Pastebin command paused unexpectedly")
    end
    local started, err = startRequest(job, api, url, body, headers)
    if not started then finishUpload(job, err) end
end

local function putFile(window, api, path)
    assert(fs.exists(path) and not fs.isDir(path), "File is missing")
    assert(http and type(http.request) == "function", "HTTP is disabled")
    local job = {window = window, path = path, output = ""}
    local function write(text) job.output = (job.output .. tostring(text)):sub(1, 2048) end
    local function printLine(...)
        for index = 1, select("#", ...) do
            if index > 1 then write(" ") end
            write((select(index, ...)))
        end
        write("\n")
    end
    -- Older pastebin programs queue a request, then wait in os.pullEvent.
    local programHttp = setmetatable({
        request = function(url, data, headers)
            if job.eventRequest then return false, "Another Pastebin request is pending" end
            job.eventRequest = {url = url, body = data, headers = headers}
            return true
        end,
        post = function(url, data, headers) return coroutine.yield(url, data, headers) end,
        get = function(url, headers) return coroutine.yield(url, nil, headers) end,
    }, {__index = http})
    local command = assert(api.loadShellProgram("pastebin", {http = programHttp, print = printLine, write = write,
        printError = function(...) job.printedError = true; printLine(...) end}))
    job.thread = coroutine.create(command)
    resumeUpload(job, api, "put", "/" .. path)
end

function app.init(_, api)
    assert(api.requestHttp and api.loadShellProgram, "File Explorer requires the v55 server")
end

local function render(w, h, api, view, window)
    local ui = api.ui.form(w, h, window, api.getAppColour(appName))
    local dir, screen = directory(view), window.screen
    local writable = not readOnly(dir)
    local hasClipboard = clipboard ~= nil
    if screen == "files" then
        local entries, err = listing(window, dir, api)
        ui.heading(display("/" .. dir, w, true))
        local top = 2
        if w >= 22 and h >= 9 then
            local free = fs.getFreeSpace and fs.getFreeSpace(dir)
            local status = writable and type(free) == "number" and (free .. " bytes free") or not writable and "Read-only" or ""
            if clipboard then status = (clipboard.moving and "Move: " or "Copy: ") .. base(clipboard.path) end
            ui.text(2, display(status, w, false))
            top = 3
        end
        local room = h - top
        local slots = #entries <= room and room or room - 1
        local first = ui.page("files", #entries, slots, h - 1)
        local visible = math.min(#entries - first, slots)
        if visible == 0 then ui.text(top, err and "Folder unavailable" or "Empty folder", true) end
        local depth = visible > 0 and math.min(api.ui.controlHeight(h), math.floor(slots / visible)) or 1
        for i = 1, visible do
            local entry = entries[first + i]
            local y = top + (i - 1) * depth
            local bg = i % 2 == 1 and 128 or 32768
            local hit = ui.button(y, "", "open", 1, w, true, bg, 1, entry.path, depth)
            local title = (entry.folder and "> " or "  ") .. entry.name
            ui.put(1, hit.y, display(title, w, false), w)
        end
        local footer = {{"Up", "up", nil, dir ~= ""}, {"Menu", "menu"}}
        if hasClipboard then footer[3] = {w >= 15 and "Paste" or "Put", "paste", nil, writable} end
        ui.footer(footer)
    elseif screen == "menu" then
        local items = {{"New folder", "newFolder", nil, writable}, {"New file", "newFile", nil, writable},
            {"Get paste", "getPaste", nil, writable}}
        if hasClipboard then
            items[#items + 1] = {"Paste here", "paste", nil, writable}
            items[#items + 1] = {"Paste as", "pasteAs", nil, writable}
        end
        if dir ~= "" then
            items[#items + 1] = {"Copy folder", "copyFolder"}
            items[#items + 1] = {"Move folder", "moveFolder", nil, canMove(dir)}
        end
        ui.menu(display("/" .. dir, w, true), items, "menu", {{"Back", "files"}})
    elseif screen == "file" then
        local path = window.selected
        local exists = path and fs.exists(path) and not fs.isDir(path)
        local rows = {{"View text", "preview", nil, exists}, {"Copy", "copyFile", nil, exists},
            {"Move", "moveFile", nil, exists and canMove(path)}, {"Send paste", "upload", nil, exists},
            {"Details", "details", nil, exists}}
        local count = exists and (fs.getSize(path) .. " B") or "Missing"
        local title = base(path or "") .. "  " .. count
        ui.menu(display(#title <= w and title or base(path or ""), w, false), rows, "file", {{"Back", "files"}})
    elseif screen == "keyboard" then
        local k = window.keyboard
        local footer = k.purpose == "contents" and {{"Save", "accept"}, {"NL", "newLine"}, {"Back", k.back}}
            or {{"Set", "accept"}, {"Clr", "clearText"}, {"Back", k.back}}
        ui.keyboard(k, footer)
    elseif screen == "upload" then
        ui.info("Send paste?", {"/" .. window.selected, "Pastebin may publish this file."}, "upload", "file")
        ui.footer({{"Send", "sendPaste"}, {"Back", "file"}})
    elseif screen == "waiting" then
        local job = jobs[window.job]
        ui.heading(job and job.thread and "Uploading" or "Downloading")
        if job then ui.text(3, display(base(job.path), w, false), true) end
    else
        local message = window.message
        ui.info(message.title, message.lines, "message", message.back)
    end
    return ui.finish(true)
end

local function windowState(id)
    local window = windows[id]
    if not window then window = {screen = "files", pages = {}}; windows[id] = window end
    return window
end

function app.render(w, h, _, api, context)
    return render(w, h, api, context.view, windowState(context.windowId))
end

local function accept(window, api)
    local k = window.keyboard
    local text, dir = k.draft, k.directory
    if k.purpose == "folder" then
        local path = newPath(dir, text)
        fs.makeDir(path)
        assert(fs.isDir(path), "Could not create folder")
        refreshLists()
        actionMenu(window, "Folder created", {"/" .. path}, "files")
    elseif k.purpose == "file" then
        window.filename = base(newPath(dir, text))
        keyboard(window, "contents", "File text", "", "menu", dir)
    elseif k.purpose == "contents" then
        local path = newPath(dir, window.filename)
        Storage.writeVerified(path, text)
        refreshLists()
        actionMenu(window, "File created", {"/" .. path}, "files")
    elseif k.purpose == "pasteAs" then
        assert(clipboard == k.clipboard, "Clipboard changed. Open Paste as again.")
        local path = paste(dir, text)
        refreshLists()
        actionMenu(window, "Pasted", {"/" .. path}, "files")
    elseif k.purpose == "pasteID" then
        window.pasteID = assert(pasteID(text), "Enter a Pastebin ID or link")
        keyboard(window, "downloadName", "Save paste as", window.pasteID .. ".txt", "menu", dir)
    elseif k.purpose == "downloadName" then
        local path = newPath(dir, text)
        assert(startRequest({window = window, path = path}, api, pastebin .. "/raw/" .. window.pasteID))
    end
end

local function touch(window, view, api, action, value)
    local dir = directory(view)
    if window.screen == "keyboard" then
        local limit = window.keyboard.purpose == "contents" and 4096 or 128
        if api.ui.editText(window.keyboard, action, value, limit) then return end
        if action == "newLine" then api.ui.typeKey(window.keyboard, "\n", limit); return end
        if action == "accept" then
            accept(window, api)
            if window.screen ~= "keyboard" then window.keyboard = nil end
            return
        end
        window.keyboard = nil
    end
    if action == "page" then window.pages[value.key] = value.page
    elseif action == "up" then openDirectory(view, window, parent(dir))
    elseif action == "open" then
        assert(fs.exists(value), "That entry has moved")
        if fs.isDir(value) then openDirectory(view, window, value)
        else window.selected, window.screen, window.pages.file = value, "file", nil end
    elseif action == "preview" then actionMenu(window, base(window.selected), readPreview(window.selected, api), "file")
    elseif action == "details" then
        local path = window.selected
        actionMenu(window, "File details", {"/" .. path, fs.getSize(path) .. " bytes"}, "file")
    elseif action == "copyFile" or action == "moveFile" or action == "copyFolder" or action == "moveFolder" then
        local folder = action == "copyFolder" or action == "moveFolder"
        local source = folder and dir or window.selected
        local moving = action == "moveFile" or action == "moveFolder"
        assert(source and source ~= "" and fs.exists(source), "The source is missing")
        assert(not moving or canMove(source), "The source is read-only or is a drive")
        clipboard = {path = source, moving = moving}
        openDirectory(view, window, folder and parent(dir) or dir)
    elseif action == "paste" then
        local path = paste(dir)
        refreshLists()
        actionMenu(window, "Pasted", {"/" .. path}, "files")
    elseif action == "pasteAs" then
        keyboard(window, "pasteAs", "Name", base(clipboard.path), "menu", dir)
        window.keyboard.clipboard = clipboard
    elseif action == "newFolder" then keyboard(window, "folder", "Folder name", "", "menu", dir)
    elseif action == "newFile" then keyboard(window, "file", "File name", "", "menu", dir)
    elseif action == "getPaste" then keyboard(window, "pasteID", "Paste ID", "", "menu", dir)
    elseif action == "upload" then window.screen, window.pages.upload = "upload", nil
    elseif action == "sendPaste" then putFile(window, api, window.selected)
    else window.screen = action end
end

function app.handleTouch(x, y, w, h, _, api, context)
    local window = windowState(context.windowId)
    local hits = context.hits
    if not hits then local _, built = render(w, h, api, context.view, window); hits = built end
    local action, value = api.ui.actionAt(hits, x, y)
    if not action then return false end
    local back = window.screen
    local ok, err = api.protectedCall(touch, window, context.view, api, action, value)
    if not ok then
        refreshLists()
        actionMenu(window, "Action failed", {errorText(err)}, back ~= "message" and back or "files")
    end
    api.invalidateAppViews(appName)
    return true
end

function app.handleHttp(url, response, errorMessage, api)
    local job = jobs[url]
    if not job then return end
    jobs[url] = nil
    local window = job.window
    window.job = nil
    if job.thread then
        job.requestError = errorMessage
        -- The OS owns the response handle and closes it after this hook.
        local handle = response and setmetatable({close = function() end}, {__index = response})
        local eventUrl = job.eventUrl
        job.eventUrl = nil
        if eventUrl then
            local event = handle and "http_success" or "http_failure"
            resumeUpload(job, api, event, eventUrl, handle or errorMessage)
        else resumeUpload(job, api, handle, errorMessage) end
        api.invalidateAppViews(appName)
        return
    end
    local ok, err = api.protectedCall(function()
        assert(response, errorMessage)
        local status = response.getResponseCode and response.getResponseCode()
        assert(not status or status == 200, "Pastebin HTTP " .. tostring(status))
        local text = assert(response.readAll(), "Pastebin returned no data")
        local path = newPath(parent(job.path), base(job.path))
        Storage.writeVerified(path, text)
        refreshLists()
        actionMenu(window, "Paste saved", {"/" .. path}, "files")
    end)
    if not ok then actionMenu(window, "Pastebin error", {errorText(err)}, "files") end
    api.invalidateAppViews(appName)
end

function app.onClose(_, _, context)
    local window = windows[context.windowId]
    if window and window.job then jobs[window.job] = nil end
    windows[context.windowId] = nil
end

function app.shutdown()
    windows, jobs, clipboard = {}, {}, nil
end

return app
