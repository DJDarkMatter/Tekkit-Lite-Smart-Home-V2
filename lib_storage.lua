-- Lua 5.1 / ComputerCraft 1.5. Only plain, serializable data belongs here.
local storage = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local Codec = rawget(_G, "__smarthomeCodec") or dofile("lib_codec.lua")
local validatedContents = {}
local checkpoints = {}

local function readFile(path, mode, read)
    local file = fs.open(path, mode)
    if not file then return nil end
    local ok, contents = Work.call(read, file)
    local closed, err = pcall(file.close)
    if not ok then error(contents, 0) end
    if not closed then error(err, 0) end
    return contents
end

local function readBinary(file)
    if file.readAll then return file.readAll() or "" end
    local parts, block = {}, {}
    while true do
        local byte = file.read()
        if byte == nil then break end
        block[#block + 1] = string.char(byte)
        if #block == 256 then
            parts[#parts + 1], block = table.concat(block), {}
            Work.check(4096)
        end
    end
    parts[#parts + 1] = table.concat(block)
    return table.concat(parts)
end

function storage.readBytes(path, expected)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local size = fs.getSize and fs.getSize(path)
    if expected and size and size ~= #expected then return nil end
    local contents = readFile(path, "r", function(file) return file.readAll() end)
    if contents and (not size or #contents == size) and (not expected or contents == expected) then return contents end
    -- Legacy text handles can normalize line endings and omit the final LF.
    -- Check the binary bytes before writing off a complete program as corrupt.
    return readFile(path, "rb", readBinary)
end

local function readTable(path)
    local contents = storage.readBytes(path)
    if not contents then return nil end
    local ok, value = pcall(textutils.unserialize, contents)
    if ok and type(value) == "table" then validatedContents[path] = contents; return value, contents end
end

function storage.load(path, validate)
    for _, candidate in ipairs({path, path .. ".tmp", path .. ".bak"}) do
        local value, contents = readTable(candidate)
        if value and (not validate or validate(value, candidate, contents)) then return value, candidate, contents end
    end
end

function storage.freeSpace(path)
    if not fs.getFreeSpace then return nil end
    local directory = path:match("^(.*)/[^/]+$") or ""
    local bytes = fs.getFreeSpace(directory ~= "" and directory or "/")
    if type(bytes) == "number" then return bytes end
end

function storage.writeVerified(path, contents)
    assert(not fs.isDir(path), "Cannot replace directory " .. path)
    local directory = path:match("^(.*)/[^/]+$") or ""
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local available = storage.freeSpace(path)
    local existing = fs.exists(path) and (fs.getSize and fs.getSize(path) or #(storage.readBytes(path) or "")) or 0
    if available and available + existing < #contents then
        error("Not enough disk space for " .. path .. " (need " .. (#contents - existing)
            .. " bytes free, have " .. available .. ")", 0)
    end
    local file = assert(fs.open(path, "w"), "Cannot write " .. path)
    local wrote, err = pcall(file.write, contents)
    local closed, closeError = pcall(file.close)
    local read, actual
    if wrote and closed then read, actual = Work.call(storage.readBytes, path, contents) end
    if not read or actual ~= contents then
        pcall(fs.delete, path)
        local reason = err or closeError or not read and actual or "incomplete file or readback mismatch"
        error("Write failed for " .. path .. ": " .. tostring(reason), 0)
    end
end

local function compactState(contents)
    if #contents < 16384 then return contents end
    local packed = Codec.pack(contents)
    if not packed then return contents end
    packed.format = "smarthome-os-state"
    local encoded = Work.serialize(packed)
    return #encoded < #contents and encoded or contents
end

function storage.loadState(path, validate)
    local state, payload
    local _, source, contents = storage.load(path, function(value, _, raw)
        local decoded = raw
        if value.format == "smarthome-os-state" then
            local ok, result = Work.call(Codec.unpack, value)
            if not ok then return false end
            decoded, value = result, textutils.unserialize(result)
        end
        if type(value) ~= "table" or validate and not validate(value) then return false end
        state, payload = value, decoded
        return true
    end)
    checkpoints[path] = source == path and {raw = contents, payload = payload} or nil
    return state, source, contents, payload
end

-- Rotate the previous verified state directly into its recovery file. The
-- primary can then be replaced with two files' worth of space and no move.
function storage.saveState(path, value, validate, forgetPrevious)
    return Work.call(function()
        local payload = Work.serialize(value)
        local recovery, temporary = path .. ".bak", path .. ".tmp"
        local source, raw, previous
        local checkpoint = checkpoints[path]
        if checkpoint and checkpoint.raw == storage.readBytes(path) then
            source, raw, previous = path, checkpoint.raw, checkpoint.payload
        else
            local _
            _, source, raw, previous = storage.loadState(path, validate)
        end
        if source and source ~= temporary and fs.exists(temporary) and not fs.isDir(temporary) then fs.delete(temporary) end
        if source and source ~= recovery then
            local bytes = raw == previous and compactState(previous) or raw
            if storage.readBytes(recovery) ~= bytes then storage.writeVerified(recovery, bytes) end
        end
        if source == path and previous == payload and not forgetPrevious then return end
        local contents = compactState(payload)
        storage.writeVerified(path, contents)
        checkpoints[path] = {raw = contents, payload = payload}
        local cleared, err = pcall(function()
            if forgetPrevious and fs.exists(recovery) and not fs.isDir(recovery) then fs.delete(recovery) end
            if fs.exists(temporary) and not fs.isDir(temporary) then fs.delete(temporary) end
        end)
        if not cleared then return "State saved. Recovery cleanup failed: " .. tostring(err) end
    end)
end

function storage.save(path, value, forgetPrevious)
    -- An interrupted reset must never be recovered as an ordinary pending save.
    local staged = path .. (forgetPrevious and ".reset" or ".tmp")
    local movedPrevious = false
    local ok, err = Work.call(function()
        local contents = Work.serialize(value)
        -- fs.getDir was only added in CC 1.63; Tekkit Lite uses older CC.
        local dir = path:match("^(.*)/[^/]+$") or ""
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local file = assert(fs.open(staged, "w"), "Cannot write " .. path)
        file.write(contents)
        file.close()
        if fs.exists(path) then
            -- Compare with the last validated/written bytes before parsing the
            -- entire old state again. External corruption still gets checked.
            local oldFile = fs.open(path, "r")
            local previous = oldFile and oldFile.readAll()
            if oldFile then oldFile.close() end
            if previous and previous == validatedContents[path] or readTable(path) then
                if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
                fs.move(path, path .. ".bak")
                movedPrevious = true
            else
                -- A corrupt primary must not replace a good backup.
                fs.delete(path)
            end
        end
        fs.move(staged, path)
        validatedContents[path] = contents
    end)
    if forgetPrevious then
        if not ok then
            pcall(fs.delete, staged)
            if movedPrevious and not fs.exists(path) then pcall(fs.move, path .. ".bak", path) end
        else
            local cleared, cleanupError = pcall(function()
                for _, suffix in ipairs({".tmp", ".bak"}) do
                    if fs.exists(path .. suffix) then fs.delete(path .. suffix) end
                end
            end)
            if not cleared then err = "Reset saved. Recovery cleanup failed: " .. tostring(cleanupError) end
        end
    end
    return ok, err
end

function storage.config(path, defaults)
    local value = storage.load(path)
    if value then
        for key, default in pairs(defaults) do
            if value[key] == nil then value[key] = default end
        end
        return value
    end
    for _, suffix in ipairs({"", ".tmp", ".bak"}) do
        assert(not fs.exists(path .. suffix), "Unreadable config: " .. path .. suffix)
    end
    local ok, err = storage.save(path, defaults)
    assert(ok, err)
    return defaults
end

return storage
