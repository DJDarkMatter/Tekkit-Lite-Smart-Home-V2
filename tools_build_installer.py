"""Build the one-paste installer using only the repository's current Lua sources."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
PATHS = [
    "lib_storage.lua", "lib_network.lua", "lib_console.lua", "lib_gui.lua", "lib_settings.lua", "lib_io_picker.lua", "lib_desktop.lua", "lib_server.lua", "lib_io.lua", "lib_monitor.lua",
    "main_os.lua", "clients_io_client.lua", "clients_monitor_client.lua",
]

def lua_string(value):
    equals = "="
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"

header = '''-- SmartHome OS installer: bundled-v12
-- Flat-root layout: lib_*, clients_*, apps_*, configs_*.
-- Upload this ONE file to Pastebin. All role files are included below.
-- Usage: inst server|io|monitor [--startup]
-- User apps: inst app NAME [--ref BRANCH_OR_COMMIT] (GitHub)
-- Alternatives: inst app NAME PASTE_ID   or   inst app NAME --file PATH
-- OS/client installation is offline. Apps are fetched only on request.
local sources = {
'''
entries = [f'    ["{path}"] = {lua_string((ROOT / path).read_text())},\n' for path in PATHS]
runner = r'''}
local args = {...}
local role, autorun = args[1], false
local entry = {server = "main_os.lua", io = "clients_io_client.lua", monitor = "clients_monitor_client.lua"}
print("SmartHome installer: bundled-v12")
local appUsage = "Usage: inst app NAME [--ref REF] | inst app NAME PASTE_ID | inst app NAME --file PATH"
if not entry[role] and role ~= "app" then
    print("Usage: inst server|io|monitor [--startup]")
    print(appUsage)
    return
end
assert(shell.dir() == "", "Run cd / first")
local files
if role == "app" then
    local name, source = args[2], args[3]
    assert(type(name) == "string" and name:match("^[%w_-]+$"), "Specify a simple app name without .lua")
    assert(not source and not args[4]
        or (source == "--file" or source == "--ref") and args[4] and not args[5]
        or source and source:match("^%w+$") and not args[4], appUsage)
    local github = source == nil or source == "--ref"
    local ref = source == "--ref" and args[4] or "main"
    assert(not github or ref:match("^[%w_./-]+$") and not ref:find("..", 1, true)
        and ref:sub(1, 1) ~= "/" and ref:sub(-1) ~= "/", "Invalid GitHub branch or commit")
    assert(fs.exists("main_os.lua") and fs.exists("lib_server.lua"), "Install apps on the central OS computer")
    local path = "apps_" .. name .. ".lua"
    local contents
    if github then
        assert(http and type(http.get) == "function", "HTTP is disabled; GitHub app downloads need HTTP enabled")
        local url = "https://raw.githubusercontent.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/" .. ref .. "/" .. path
        print("Downloading " .. path .. " from GitHub (" .. ref .. ")")
        local function download(address)
            -- A child coroutine catches native request errors without preventing
            -- http.get from yielding on Lua 5.1. Terminate still aborts the install.
            local request = coroutine.create(function() return http.get(address) end)
            local result = {coroutine.resume(request)}
            while result[1] and coroutine.status(request) ~= "dead" do
                result = {coroutine.resume(request, os.pullEvent(result[2]))}
            end
            if not result[1] then return nil, "Request error: " .. tostring(result[2]) end
            local response = result[2] or result[4] -- Newer CC may return an error handle.
            if not response then return nil, tostring(result[3] or "No response; CC supplied no reason") end
            -- Reading/closing response handles does not yield, unlike http.get.
            local ok, code, body = pcall(function()
                return response.getResponseCode and response.getResponseCode() or 200, response.readAll()
            end)
            local closed, closeError = pcall(response.close)
            if not ok then return nil, "Cannot read response: " .. tostring(code) end
            if not closed then return nil, "Cannot close response: " .. tostring(closeError) end
            if code ~= 200 then return nil, "GitHub returned HTTP " .. tostring(code) end
            if not result[2] then return nil, tostring(result[3] or "HTTP request failed") end
            if type(body) ~= "string" or #body == 0 then return nil, "Empty app source" end
            return body
        end
        local function checkLua(body)
            if body == nil then return nil end
            local chunk, err = loadstring(body, path)
            if not chunk then return nil, "Invalid app Lua: " .. tostring(err) end
            return body
        end
        local function apiSource(body)
            -- Read only GitHub's known base64 content field; no JSON API or
            -- execution of downloaded text is needed on old ComputerCraft.
            if not body:match('"type"%s*:%s*"file"') or not body:match('"encoding"%s*:%s*"base64"')
                or body:match('"name"%s*:%s*"([^"]*)"') ~= path then
                return nil, "GitHub API did not return the requested base64 file"
            end
            local encoded = body:match('"content"%s*:%s*"([^"]*)"')
            if not encoded then return nil, "GitHub API response has no file content" end
            encoded = encoded:gsub("\\n", ""):gsub("\\r", ""):gsub("\\/", "/"):gsub("%s", "")
            local padding = encoded:match("=*$")
            local data = encoded:sub(1, #encoded - #padding)
            if #encoded % 4 ~= 0 or #padding > 2 or data:find("[^A-Za-z0-9+/]") then
                return nil, "Invalid base64 in GitHub API response"
            end
            local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local output, value, bits = {}, 0, 0
            for index = 1, #data do
                value, bits = value * 64 + alphabet:find(data:sub(index, index), 1, true) - 1, bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    output[#output + 1] = string.char(math.floor(value / 2 ^ bits))
                    value = value % 2 ^ bits
                end
            end
            local decoded = table.concat(output)
            if value ~= 0 or tonumber(body:match('"size"%s*:%s*(%d+)')) ~= #decoded then
                return nil, "GitHub API file size/encoding mismatch"
            end
            if #decoded == 0 then return nil, "Empty app source" end
            return decoded
        end
        local rawError, apiError, body
        local apiUrl = "https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/"
            .. path .. "?ref=" .. ref
        body, apiError = download(apiUrl)
        if body then contents, apiError = apiSource(body) end
        if contents then contents, apiError = checkLua(contents) end
        if contents then
            print("Downloaded via GitHub API")
        else
            print("GitHub API failed; trying raw download")
            contents, rawError = download(url)
            if contents then contents, rawError = checkLua(contents) end
            if not contents then
                print("Raw: " .. tostring(rawError))
                print("API: " .. tostring(apiError))
                print("No response from both? Ask the server admin to check GitHub HTTPS access and the Java/server log.")
                error("GitHub app download failed; installed files were not changed", 0)
            end
            print("Downloaded via GitHub raw")
        end
    elseif source == "--file" then
        local file = assert(fs.open(args[4], "r"), "Cannot read app source: " .. args[4])
        contents = file.readAll(); file.close()
    else
        local temporary = path .. ".download"
        if fs.exists(temporary) then fs.delete(temporary) end
        assert(shell.run("pastebin", "get", source, temporary) and fs.exists(temporary), "Pastebin app download failed")
        local file = assert(fs.open(temporary, "r"), "Cannot read downloaded app")
        contents = file.readAll(); file.close()
        fs.delete(temporary)
    end
    assert(type(contents) == "string" and #contents > 0, "Empty app source")
    local chunk, err = loadstring(contents, path)
    assert(chunk, "Invalid app Lua: " .. tostring(err))
    -- Read settings without resetting them or executing the app at install time.
    local storageChunk = assert(loadstring(sources["lib_storage.lua"], "lib_storage.lua"))
    setfenv(storageChunk, getfenv(1))
    local storage = storageChunk()
    local configPath = "configs_os.txt"
    local settings = storage.load(configPath)
    if not settings then
        for _, suffix in ipairs({"", ".tmp", ".bak"}) do
            assert(not fs.exists(configPath .. suffix), "Unreadable OS settings")
        end
        settings = {}
    end
    if settings.enabledApps == nil then settings.enabledApps = {} end
    assert(type(settings.enabledApps) == "table", "Invalid enabledApps setting")
    settings.enabledApps[name] = true -- Explicit app installation opts this app in.
    sources[path], sources[configPath] = contents, textutils.serialize(settings)
    files = {path, configPath}
else
    for index = 2, #args do
        assert(args[index] == "--startup", "Usage: inst server|io|monitor [--startup]")
        autorun = true
    end
    files = {"lib_storage.lua", "lib_network.lua"}
    if role ~= "io" then files[#files + 1] = "lib_gui.lua" end
    if role == "server" then
        files[#files + 1] = "lib_console.lua"
        files[#files + 1] = "lib_settings.lua"
        files[#files + 1] = "lib_io_picker.lua"
        files[#files + 1] = "lib_desktop.lua"
        files[#files + 1] = "lib_server.lua"
    elseif role == "io" then files[#files + 1] = "lib_io.lua"
    else files[#files + 1] = "lib_monitor.lua" end
    files[#files + 1] = entry[role]
    if autorun then
        sources.startup = 'shell.setDir("/")\nshell.run("' .. entry[role] .. '")\n'
        files[#files + 1] = "startup"
    end
end
if role ~= "app" then
    -- Upgrade old folder-based installations without resetting IDs, apps or state.
    -- Existing flat files take precedence; old files remain recovery copies.
    local storageChunk = assert(loadstring(sources["lib_storage.lua"], "lib_storage.lua"))
    setfenv(storageChunk, getfenv(1))
    local storage = storageChunk()
    local function existsAny(path)
        return fs.exists(path) or fs.exists(path .. ".tmp") or fs.exists(path .. ".bak")
    end
    local function addFile(path, contents)
        sources[path] = contents
        for _, present in ipairs(files) do if present == path then return end end
        files[#files + 1] = path
    end
    local function readTable(path)
        local value = storage.load(path)
        assert(value or not existsAny(path), "Unreadable saved data: " .. path)
        return value
    end
    local function migrate(target, legacy)
        if existsAny(target) then return readTable(target), false end
        if not existsAny(legacy) then return nil, false end
        local value = assert(readTable(legacy))
        addFile(target, textutils.serialize(value))
        print("Migrating " .. legacy .. " to " .. target)
        return value, true
    end
    migrate("configs_network.txt", "Configs/network.txt")
    if role == "io" then migrate("configs_io.txt", "Configs/io.txt")
    elseif role == "monitor" then migrate("configs_monitor.txt", "Configs/monitor.txt")
    else
        local settings, migrated = migrate("configs_os.txt", "Configs/os.txt")
        local legacyState = settings and settings.saveFile or "Configs/os_state.txt"
        assert(type(legacyState) == "string", "Invalid saved state path")
        migrate("configs_os_state.txt", legacyState)
        if settings then
            if settings.saveFile and settings.saveFile ~= "configs_os_state.txt" then
                settings.saveFile = "configs_os_state.txt"
                addFile("configs_os.txt", textutils.serialize(settings))
            end
            if migrated then
                assert(settings.enabledApps == nil or type(settings.enabledApps) == "table", "Invalid enabledApps setting")
                for name, enabled in pairs(settings.enabledApps or {}) do
                    if enabled == true then
                        assert(type(name) == "string" and name:match("^[%w_-]+$"), "Invalid enabled app name")
                        local path, oldPath = "apps_" .. name .. ".lua", "Apps/" .. name .. ".lua"
                        if not fs.exists(path) and fs.exists(oldPath) then
                            local file = assert(fs.open(oldPath, "r"), "Cannot read legacy app: " .. oldPath)
                            local contents = file.readAll(); file.close()
                            addFile(path, contents)
                            print("Migrating enabled app: " .. name)
                        end
                    end
                end
            end
        end
    end
end
-- Check every file before replacing any installed program.
for _, path in ipairs(files) do
    local contents = assert(sources[path], "Missing bundled file: " .. path)
    if path:match("%.lua$") or path == "startup" then
        local chunk, err = loadstring(contents, path)
        assert(chunk, "Invalid Lua: " .. path .. ": " .. tostring(err))
    else assert(type(textutils.unserialize(contents)) == "table", "Invalid settings: " .. path) end
end
for _, path in ipairs(files) do
    assert(not path:find("/", 1, true), "Install targets must be root filenames")
    local file = assert(fs.open(path .. ".download", "w"), "Cannot stage " .. path)
    file.write(sources[path])
    file.close()
end
for _, path in ipairs(files) do
    if fs.exists(path) then
        if fs.exists(path .. ".pre_update") then fs.delete(path .. ".pre_update") end
        fs.move(path, path .. ".pre_update")
    end
    fs.move(path .. ".download", path)
    print("Installed " .. path)
end
if role == "app" then
    print("Installed and enabled user app: " .. args[2])
    print("Restart the central OS to load it")
    return
end
print("Installed " .. role .. " from the bundled files")
if autorun then
    print("Autorun enabled; an existing startup is kept as startup.pre_update")
    print("Run reboot to start automatically")
else print("Autorun unchanged; add --startup to enable it") end
print("Start with: " .. entry[role])
'''
contents = header + "".join(entries) + runner
path = ROOT / "install.lua"
if "--check" in sys.argv:
    if not path.exists() or path.read_text() != contents:
        raise SystemExit("install.lua is stale; run python3 tools_build_installer.py")
    print("Bundled installer matches all current source files")
else:
    path.write_text(contents)
    print(f"Built {path.name}: {len(contents.encode())} bytes, {len(PATHS)} bundled source files")
