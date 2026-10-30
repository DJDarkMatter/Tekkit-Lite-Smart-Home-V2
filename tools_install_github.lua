-- Optional GitHub bootstrapper: inst server|io|monitor|sensor [ref] [--startup]
-- Fetches the flat, self-contained installer from the V2 repository.
local args = {...}
local role = args[1]
local ref = (args[2] ~= "--startup" and args[2]) or "main"
local autorun = args[2] == "--startup" or args[3] == "--startup"
if role ~= "server" and role ~= "io" and role ~= "monitor" and role ~= "sensor" then
    print("Usage: inst server|io|monitor|sensor [ref] [--startup]")
    return
end
assert(ref:match("^[%w_./-]+$"), "Invalid branch or commit")
assert(not args[4] and (not args[3] or args[3] == "--startup"), "Unexpected install argument")
assert(shell.dir() == "", "Run cd / first")
assert(http and http.get, "HTTP is disabled; use the bundled installer via Pastebin")
local url = "https://raw.githubusercontent.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/" .. ref .. "/install.lua"
local response = assert(http.get(url), "Cannot download the V2 installer; use Pastebin instead")
local code = response.getResponseCode and response.getResponseCode() or 200
local contents = response.readAll(); response.close()
assert(code == 200 and type(contents) == "string" and #contents > 0, "GitHub installer download failed")
assert(contents:find("-- Flat-root layout:", 1, true), "Expected the V2 flat-root installer")
local chunk, err = loadstring(contents, "install.lua")
assert(chunk, "Invalid installer Lua: " .. tostring(err))
local path = "install.lua"
local file = assert(fs.open(path .. ".download", "w"), "Cannot stage installer")
file.write(contents); file.close()
if fs.exists(path) then
    if fs.exists(path .. ".pre_update") then fs.delete(path .. ".pre_update") end
    fs.move(path, path .. ".pre_update")
end
fs.move(path .. ".download", path)
setfenv(chunk, getfenv(1))
if autorun then return chunk(role, "--startup") end
return chunk(role)
