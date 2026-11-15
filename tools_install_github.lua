-- Small installer. Runs the bundled installer directly from memory.
-- Usage: inst [--installer-ref REF] server|io|monitor|sensor|relay|app|apps|restore|space ...
local args = {...}
local ref = "main"
if args[1] == "--installer-ref" then
    table.remove(args, 1)
    ref = assert(table.remove(args, 1), "Missing installer branch or commit")
end
local role = args[1]
local roles = {server = true, io = true, monitor = true, sensor = true, relay = true}
if roles[role] and args[2] and args[2] ~= "--startup" then ref = table.remove(args, 2) end
if not roles[role] and role ~= "app" and role ~= "apps" and role ~= "restore" and role ~= "space" then
    print("Usage: inst [--installer-ref REF] server|io|monitor|sensor|relay [--startup]")
    print("       inst app NAME | inst apps | inst restore | inst space")
    return
end
assert(ref:match("^[%w_./-]+$") and not ref:find("..", 1, true)
    and ref:sub(1, 1) ~= "/" and ref:sub(-1) ~= "/", "Invalid branch or commit")
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
setfenv(chunk, getfenv(1))
return chunk(unpack(args))
