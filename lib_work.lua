-- Cooperative central work, portable to Lua 5.1 and legacy LuaJ.
-- One serial worker owns OS state; the event collector remains responsive.
local existing = rawget(_G, "__smarthomeWork")
if existing then return existing end
local Work = {stage = "Starting OS", yields = 0}
local parents, owner, pause, budget, spent = {}, nil, nil, 16384, 0
local function pack(...) return {n = select("#", ...), ...} end
local function active()
    local thread = coroutine.running()
    while thread do
        if thread == owner then return pause ~= nil end
        thread = parents[thread]
    end
    return false
end
function Work.protect(fn, ...)
    local thread = coroutine.create(fn)
    parents[thread] = coroutine.running()
    local args = pack(...)
    while true do
        local result = pack(coroutine.resume(thread, unpack(args, 1, args.n)))
        if not result[1] or coroutine.status(thread) == "dead" then
            parents[thread] = nil
            if not result[1] and tostring(result[2]):lower():find("too long without yielding", 1, true) then
                Work.report(Work.stage, result[2])
            end
            return unpack(result, 1, result.n)
        end
        args = pack(coroutine.yield(unpack(result, 2, result.n)))
    end
end
function Work.call(fn, ...)
    if active() then return Work.protect(fn, ...) end
    return pcall(fn, ...)
end
function Work.enable(callback, limit)
    owner, pause, budget, spent = coroutine.running(), callback, limit or 16384, 0
end
function Work.disable() owner, pause, spent, parents = nil, nil, 0, {} end
function Work.check(cost)
    if not pause or not active() then return end
    spent = spent + (cost or 1)
    if spent >= budget then
        spent = 0; Work.yields = Work.yields + 1
        pause()
    end
end
-- Serialize plain saved data in small steps. Repeated references are rejected,
-- matching old CraftOS, and output remains readable by textutils.unserialize.
function Work.serialize(value)
    if not pause or not active() then return textutils.serialize(value) end
    local parts, seen = {}, {}
    local function write(item)
        local kind = type(item)
        Work.check(16)
        if kind == "string" then
            parts[#parts + 1] = string.format("%q", item); Work.check(#item)
        elseif kind == "number" then
            assert(item == item and math.abs(item) < math.huge, "Cannot serialize non-finite number")
            parts[#parts + 1] = tostring(item)
        elseif kind == "boolean" or kind == "nil" then parts[#parts + 1] = tostring(item)
        else
            assert(kind == "table", "Cannot serialize " .. kind)
            assert(not seen[item], "Cannot serialize table with recursive entries")
            seen[item] = true; parts[#parts + 1] = "{"
            for key, child in pairs(item) do
                parts[#parts + 1] = "["; write(key); parts[#parts + 1] = "]="
                write(child); parts[#parts + 1] = ","
            end
            parts[#parts + 1] = "}"
        end
    end
    write(value)
    return table.concat(parts)
end
function Work.report(stage, err)
    local message = "SmartHome OS error\nStage: " .. tostring(stage or Work.stage)
        .. "\nError: " .. tostring(err) .. "\n"
    message = message:sub(1, 16384)
    if Work.lastReport == message then return true end
    local ok = pcall(function()
        local path = "diagnostics_os_error.txt"
        local file = assert(fs.open(path .. ".tmp", "w"), "Cannot write OS error report")
        file.write(message); file.close()
        if fs.exists(path) then fs.delete(path) end
        fs.move(path .. ".tmp", path)
    end)
    if ok then Work.lastReport = message end
    return ok
end
rawset(_G, "__smarthomeWork", Work)
return Work
