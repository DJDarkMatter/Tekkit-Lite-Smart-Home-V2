-- Full snapshots are data plus locally installed app sources. Wireless
-- announcements carry only the settings used by each supported client role.
local Backup = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local statePath, journalPath = "configs_os_state.txt", "restore_pending.txt"
local transportPath = "configs_transport.txt"
local roles = {io = true, monitor = true, sensor = true, relay = true}
local sides = {top = true, bottom = true, left = true, right = true, front = true, back = true}

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function number(value, low, high)
    return type(value) == "number" and value >= low and value <= high
end

local function appName(value)
    return type(value) == "string" and value:match("^[%w_-]+$") and value ~= "system" and value ~= "level_emitter"
end

local function wireColour(value)
    if not integer(value, 1, 32768) then return false end
    while value > 1 do
        if value % 2 ~= 0 then return false end
        value = value / 2
    end
    return true
end

function Backup.validState(value)
    for _, key in ipairs({"windows", "appRegistry", "appStates", "outputs", "outputMap", "managedSides", "desktops"}) do
        if value[key] ~= nil and type(value[key]) ~= "table" then return false end
    end
    for name, mapping in pairs(value.outputMap or {}) do
        if type(name) ~= "string" or type(mapping) ~= "table" or type(mapping.clientId) ~= "string"
            or not sides[mapping.side] or (mapping.color ~= nil and not wireColour(mapping.color)) then return false end
    end
    for id, entries in pairs(value.managedSides or {}) do
        if type(id) ~= "string" or type(entries) ~= "table" then return false end
        for side, enabled in pairs(entries) do if not sides[side] or enabled ~= true then return false end end
    end
    return true
end

local function networkSettings(network)
    if type(network) ~= "table" or type(network.networkId) ~= "string" or #network.networkId < 1
        or not integer(network.channel, 1, 65532) or network.relayEnabled ~= nil and type(network.relayEnabled) ~= "boolean"
        or network.serverId ~= nil and not integer(network.serverId, 0, 2147483647) then return end
    return {networkId = network.networkId, channel = network.channel,
        relayEnabled = network.relayEnabled, serverId = network.serverId}
end

function Backup.clientSettings(role, config, network)
    local minimumAnnounce = (role == "io" or role == "monitor") and 1 or .5
    if not roles[role] or type(config) ~= "table" or type(config.clientId) ~= "string"
        or #config.clientId < 1 or #config.clientId > 64 or not number(config.announceInterval, minimumAnnounce, 2147483647)
        or not number(config.timeout, .5, 2147483647) or config.timeout <= config.announceInterval then return end
    local net = networkSettings(network)
    if not net or #net.networkId > 256 then return end
    local result = {clientId = config.clientId, announceInterval = config.announceInterval, timeout = config.timeout}
    if role == "monitor" then
        if not number(config.textScale, .5, 5) or not integer(config.textScale * 2, 1, 10)
            or type(config.touchOffsets) ~= "table" then return end
        result.textScale, result.touchOffsets = config.textScale, {}
        for side in pairs(sides) do
            local offset = config.touchOffsets[side]
            if offset ~= nil then
                if type(offset) ~= "table" or not integer(offset.x, -3, 3) or not integer(offset.y, -3, 3) then return end
                result.touchOffsets[side] = {x = offset.x, y = offset.y}
            end
        end
    elseif role == "io" then
        if type(config.sides) ~= "table" or #config.sides > 6 or type(config.safeOff) ~= "boolean"
            or not number(config.outputInterval, .5, 2147483647) then return end
        result.sides, result.safeOff, result.outputInterval = {}, config.safeOff, config.outputInterval
        for i, side in ipairs(config.sides) do
            if not sides[side] then return end
            result.sides[i] = side
        end
    elseif role == "sensor" then
        for _, key in ipairs({"discoveryInterval", "pollInterval", "requestTimeout"}) do
            if not number(config[key], .5, 60) then return end
            result[key] = config[key]
        end
        if not integer(config.bootCounter, 0, 2147483646) then return end
        result.bootCounter = config.bootCounter
    end
    return {config = result, network = net}
end

local function readFile(path)
    local file = fs.open(path, "r")
    if not file then return nil end
    local contents = file.readAll()
    file.close()
    return contents
end

function Backup.capturePrograms()
    local programs = {}
    for _, path in ipairs(fs.list("")) do
        local name = path:match("^apps_([%w_-]+)%.lua$")
        if appName(name) and not fs.isDir(path) then
            programs[name] = assert(readFile(path), "Cannot back up " .. path)
            Work.check(#programs[name])
        end
    end
    local startup
    if fs.exists("startup") and not fs.isDir("startup") then startup = assert(readFile("startup"), "Cannot back up startup") end
    return programs, startup
end

function Backup.valid(bundle, target)
    if type(bundle) ~= "table" or bundle.target ~= target or type(bundle.time) ~= "string"
        or (bundle.version ~= 1 and not (bundle.version == 2 and target == "@all")) then return false end
    local data = bundle.data
    if type(data) ~= "table" or not Backup.validState(data) then return false end
    for _, key in ipairs({"appStates", "outputMap", "windows", "appearance", "archivedRoutes", "alertHistory"}) do
        if type(data[key]) ~= "table" then return false end
    end
    if bundle.version == 1 then return true end
    if type(bundle.osConfig) ~= "table" or type(bundle.osConfig.enabledApps) ~= "table"
        or not networkSettings(bundle.network) or type(bundle.programs) ~= "table"
        or bundle.startup ~= nil and type(bundle.startup) ~= "string" or type(data.clientConfigs) ~= "table" then return false end
    for name, program in pairs(bundle.programs) do
        if not appName(name) or type(program) ~= "string" or #program == 0 then return false end
    end
    return true
end

function Backup.exists(path)
    return fs.exists(path) or fs.exists(path .. ".tmp") or fs.exists(path .. ".bak")
end

local function restorePath(path)
    return path == statePath or path == "configs_os.txt" or path == "configs_network.txt" or path == transportPath or path == "startup"
        or roles[path:match("^configs_([%w_-]+)%.txt$")] or appName(path:match("^apps_([%w_-]+)%.lua$"))
end

-- The journal exists only while renames can be incomplete. Its presence on
-- boot rolls the local computer back before loading any restored settings.
function Backup.recover(storage)
    if not fs.exists(journalPath) then return end
    local journal = assert(storage.load(journalPath), "Unreadable restore journal")
    for i = #journal, 1, -1 do
        local entry = journal[i]
        assert(type(entry.path) == "string" and restorePath(entry.path) and type(entry.existed) == "boolean", "Invalid restore journal")
        local path = entry.path
        local previous, staged = path .. ".restore_old", path .. ".restore_new"
        if fs.exists(previous) then
            if fs.exists(path) then fs.delete(path) end
            fs.move(previous, path)
        elseif not entry.existed and fs.exists(path) then fs.delete(path) end
        if fs.exists(staged) then fs.delete(staged) end
    end
    fs.delete(journalPath)
end

local function keepPrevious(path, suffix)
    local previous, recovery = path .. ".restore_old", path .. suffix
    if fs.exists(previous) then
        if fs.exists(recovery) then fs.delete(recovery) end
        fs.move(previous, recovery)
    end
end

local function replace(storage, files, suffix)
    Backup.recover(storage)
    suffix = suffix or ".before_restore"
    local paths, journal = {}, {}
    for path, contents in pairs(files) do
        assert(restorePath(path) and not fs.isDir(path), "Invalid restore target: " .. path)
        if readFile(path) ~= contents then paths[#paths + 1] = path end
    end
    table.sort(paths)
    if #paths == 0 then return true end
    local ok, err = Work.call(function()
        for _, path in ipairs(paths) do
            keepPrevious(path, suffix)
            local stage = assert(fs.open(path .. ".restore_new", "w"), "Cannot stage " .. path)
            stage.write(files[path])
            stage.close()
            journal[#journal + 1] = {path = path, existed = fs.exists(path)}
            Work.check(#files[path])
        end
        assert(storage.save(journalPath, journal, true))
        for _, entry in ipairs(journal) do
            local path = entry.path
            if entry.existed then fs.move(path, path .. ".restore_old") end
            fs.move(path .. ".restore_new", path)
        end
        fs.delete(journalPath)
    end)
    if not ok then
        local recovered, why = Work.call(Backup.recover, storage)
        if recovered then
            for _, path in ipairs(paths) do pcall(fs.delete, path .. ".restore_new") end
        else return false, tostring(err) .. ". Recovery pending: " .. tostring(why) end
        return false, err
    end
    for _, path in ipairs(paths) do pcall(keepPrevious, path, suffix) end
    return true
end

function Backup.installApps(storage, sources)
    return replace(storage, sources, ".pre_update")
end

local function includeTransport(storage, files, saved)
    if not integer(saved, 0, 2147483646) then return end
    local transport = storage.load(transportPath) or {}
    local current = tonumber(transport.bootCounter) or 0
    if saved > current then
        transport.bootCounter = saved
        files[transportPath] = Work.serialize(transport)
    end
end

function Backup.restoreServer(bundle, storage)
    assert(Backup.valid(bundle, "@all"), "Invalid Entire OS backup")
    assert(fs.exists("main_os.lua"), "Install the server role first")
    local data, files = bundle.data, {}
    local config = storage.load("configs_os.txt") or {}
    local previous = storage.load(config.saveFile or statePath, Backup.validState) or {}
    if bundle.version == 2 then
        config = bundle.osConfig
        for _, key in ipairs({"tickInterval", "saveInterval", "clientTimeout", "retryInterval"}) do
            assert(config[key] == nil or number(config[key], .0001, 2147483647), "Invalid OS setting: " .. key)
        end
        config.saveFile = statePath
        files["configs_os.txt"] = Work.serialize(config)
        files["configs_network.txt"] = Work.serialize(bundle.network)
        for name, source in pairs(bundle.programs) do
            local path = "apps_" .. name .. ".lua"
            assert(loadstring(source, path))
            files[path] = source
            Work.check(#source)
        end
        if bundle.startup then
            assert(loadstring(bundle.startup, "startup"))
            files.startup = bundle.startup
        end
        includeTransport(storage, files, bundle.transportBoot)
    else
        -- A version-one snapshot contains application state and bindings only.
        -- Import that state even when the corresponding app has yet to be installed.
        config.saveFile = statePath
        files["configs_os.txt"] = Work.serialize(config)
        data.clientConfigs = previous.clientConfigs
    end
    data.desktopVersion = 2
    data.bootCounter = math.max(tonumber(data.bootCounter) or 0, tonumber(previous.bootCounter) or 0)
    data.managedSides = data.managedSides or {}
    for id, entries in pairs(previous.managedSides or {}) do
        data.managedSides[id] = data.managedSides[id] or {}
        for side in pairs(entries) do data.managedSides[id][side] = true end
    end
    data.outputs = data.outputs or {}
    for name, route in pairs(data.outputMap) do
        local owner = route.owner
        local available = owner == "@settings" or type(config.enabledApps) == "table" and config.enabledApps[owner] == true
            and (files["apps_" .. owner .. ".lua"] or fs.exists("apps_" .. owner .. ".lua"))
        if type(owner) == "string" and not available then
            data.archivedRoutes[owner] = data.archivedRoutes[owner] or {}
            data.archivedRoutes[owner][name] = route
            data.outputMap[name], data.outputs[name] = nil, nil
        else
            data.managedSides[route.clientId] = data.managedSides[route.clientId] or {}
            data.managedSides[route.clientId][route.side] = true
        end
    end
    files[statePath] = Work.serialize(data)
    return replace(storage, files)
end

function Backup.restoreClient(bundle, storage, role, id)
    assert(Backup.valid(bundle, "@all") and bundle.version == 2 and roles[role], "This backup has no client settings")
    local clients = bundle.data.clientConfigs[role]
    local record = type(clients) == "table" and clients[id]
    local saved = type(record) == "table" and Backup.clientSettings(role, record.config, record.network)
    assert(saved and saved.config.clientId == id, "No saved " .. role .. " client named " .. tostring(id))
    local path = "configs_" .. role .. ".txt"
    if role == "sensor" then
        local current = storage.load(path) or {}
        saved.config.bootCounter = math.max(saved.config.bootCounter, tonumber(current.bootCounter) or 0)
    end
    local files = {[path] = Work.serialize(saved.config), ["configs_network.txt"] = Work.serialize(saved.network)}
    includeTransport(storage, files, record.transportBoot)
    return replace(storage, files)
end

return Backup
