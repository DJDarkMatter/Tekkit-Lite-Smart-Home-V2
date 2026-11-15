-- Shared by the bundled and small installers. Only the install plan occupies
-- extra disk space. Source and rollback bytes stay in memory while installing.
local Update = {}
local Work = assert(rawget(_G, "__smarthomeWork"))
local Codec = assert(rawget(_G, "__smarthomeCodec"))
local journalPath = "install_pending.txt"
local planPath = "install_plan.txt"

function Update.signature(contents)
    return #contents .. "/" .. string.format("%.0f", Codec.checksum(contents))
end

function Update.pending(storage)
    if not fs.exists(journalPath) then return nil end
    assert(not fs.isDir(journalPath), "Install marker is a directory: " .. journalPath)
    local contents = storage.readBytes(planPath)
    local pending = contents and textutils.unserialize(contents)
    assert(type(pending) == "table" and pending.version == 1 and type(pending.command) == "string"
        and type(pending.targets) == "table" and type(pending.references) == "table"
        and type(pending.settings) == "table", "Unreadable install record: " .. planPath)
    return pending
end

function Update.programCopies(storage, bundledPaths)
    local copies, verified, bytes = {}, {}, 0
    for _, path in ipairs(fs.list("")) do
        local name = path:match("^(.*)%.pre_update$") or path:match("^(.*)%.download$")
        if not name and not fs.exists("restore_pending.txt") then name = path:match("^(.*)%.restore_new$") end
        if name and (bundledPaths[name] or name:match("^apps_[%w_-]+%.lua$")) and not fs.isDir(path) then
            if verified[name] == nil then
                local active = storage.readBytes(name)
                verified[name] = active and #active > 0 and loadstring(active, name) ~= nil or false
            end
            if verified[name] then
                copies[#copies + 1] = path
                bytes = bytes + (fs.getSize and fs.getSize(path) or #(storage.readBytes(path) or ""))
            end
            Work.check(256)
        end
    end
    return copies, bytes
end

local function removeProgramCopies(storage, bundledPaths)
    local copies = Update.programCopies(storage, bundledPaths)
    for _, path in ipairs(copies) do fs.delete(path) end
    if #copies > 0 then print("Removed " .. #copies .. " old program copies") end
end

local function finish()
    if fs.exists(journalPath) then fs.delete(journalPath) end
    if fs.exists(planPath) then pcall(fs.delete, planPath) end
end

local function preflight(storage, changes, journalBytes)
    local available = storage.freeSpace(journalPath)
    if not available then return end
    local used, peak = journalBytes, journalBytes
    for _, change in ipairs(changes) do
        used = used + #change.contents - #(change.previous or "")
        peak = math.max(peak, used)
    end
    if available < peak then
        error("Not enough disk space for install (need " .. peak .. " bytes free, have " .. available .. ")", 0)
    end
end

function Update.apply(storage, files, sources, command, pending, references, bundledPaths)
    local plan = {version = 1, command = command, targets = {}, references = references, settings = {}}
    local changes, unchanged = {}, 0
    for _, path in ipairs(files) do
        assert(not path:find("/", 1, true) and not fs.isDir(path), "Invalid install target " .. path)
        local contents = assert(sources[path], "Missing install source " .. path)
        plan.targets[path] = Update.signature(contents)
        if not references[path] and path:match("^configs_[%w_-]+%.txt$") then plan.settings[path] = contents end
        local previous = storage.readBytes(path)
        if previous == contents then unchanged = unchanged + 1
        else changes[#changes + 1] = {path = path, contents = contents, previous = previous} end
    end
    if pending then
        for path, signature in pairs(plan.targets) do
            assert(pending.targets[path] == signature, "Install source changed: " .. path)
        end
        for path in pairs(pending.targets) do assert(plan.targets[path], "Missing source to resume " .. path) end
    end

    -- Earlier releases saved a second copy of each replaced program. Reclaim
    -- those and stale download files only when the installed program compiles.
    if not pending then
        assert(not fs.isDir(planPath), "Install plan is a directory: " .. planPath)
        if fs.exists(planPath) then fs.delete(planPath) end
        removeProgramCopies(storage, bundledPaths)
    end
    if #changes == 0 then
        finish()
        if pending then removeProgramCopies(storage, bundledPaths) end
        return 0, unchanged
    end

    local journal = not pending and Work.serialize(plan)
    preflight(storage, changes, journal and #journal or 0)
    if journal then
        -- An incomplete plan has no marker and can be discarded on retry.
        storage.writeVerified(planPath, journal)
        storage.writeVerified(journalPath, "")
    end
    local started = 0
    local ok, err = Work.call(function()
        for index, change in ipairs(changes) do
            started = index
            storage.writeVerified(change.path, change.contents)
            print("Installed " .. change.path)
            Work.check(#change.contents)
        end
    end)
    if not ok then
        local rolledBack = Work.call(function()
            -- Delete additions first so restoring the previous versions can
            -- reuse their space. A failed rollback leaves the plan to resume.
            for index = 1, started do
                local change = changes[index]
                if not change.previous and fs.exists(change.path) then fs.delete(change.path) end
            end
            for index = started, 1, -1 do
                local change = changes[index]
                if change.previous and storage.readBytes(change.path) ~= change.previous then
                    storage.writeVerified(change.path, change.previous)
                end
            end
        end)
        if rolledBack and not pending then finish(); error(err, 0) end
        error(tostring(err) .. "\nUpdate pending. Run " .. command .. " again to resume.", 0)
    end
    finish()
    local cleaned, cleanupError = Work.call(removeProgramCopies, storage, bundledPaths)
    if not cleaned then print("Installed. Could not remove old program copies: " .. tostring(cleanupError)) end
    return #changes, unchanged
end

return Update
