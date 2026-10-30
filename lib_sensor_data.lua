-- Shared bounded sensor data and OCS 1.4.7 field adapters. No peripherals here.
local Data = {protocol = 1, chunkSize = 12000, maxParts = 16, maxTargets = 4096}
local sides = {top = true, bottom = true, left = true, right = true, front = true, back = true}
function Data.number(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
function Data.integer(v, lo, hi) return Data.number(v) and v == math.floor(v) and v >= lo and v <= hi end
function Data.string(v, limit) return type(v) == "string" and #v > 0 and #v <= limit and not v:find("[%c]") end
function Data.address(a)
    return type(a) == "table" and Data.string(a.clientId, 64) and sides[a.side] and Data.string(a.target, 128)
        and (a.card == nil or Data.string(a.card, 128))
end
function Data.clean(value)
    local seen, count = {}, 0
    local function walk(v, depth)
        count = count + 1
        if count > 12000 or depth > 8 then error("Sensor reading is too large or deeply nested", 0) end
        if type(v) == "number" then assert(Data.number(v), "Invalid sensor number"); return v end
        if type(v) == "boolean" or v == nil then return v end
        if type(v) == "string" then assert(#v <= 2048, "Sensor string too long"); return v end
        assert(type(v) == "table" and not seen[v], "Invalid sensor value")
        seen[v] = true
        local result = {}
        for key, item in pairs(v) do
            assert(type(key) == "string" and #key <= 256 or Data.integer(key, -1000000000, 1000000000), "Invalid sensor key")
            result[key] = walk(item, depth + 1)
        end
        seen[v] = nil
        return result
    end
    local ok, result = pcall(walk, value, 0)
    if ok then return result end
    return nil, tostring(result)
end
function Data.cardKind(card)
    local value = tostring(card or ""):lower():gsub("[%s_-]", "")
    if value:find("energistics", 1, true) or value:find("aesensor", 1, true) or value:find("appeng", 1, true) then return "ae" end
    if value:find("industrial", 1, true) or value:find("ic2", 1, true) or value:find("machine", 1, true) then return "machine" end
    if value:find("inventory", 1, true) then return "inventory" end
    if value:find("proximity", 1, true) then return "proximity" end
    if value:find("power", 1, true) then return "power" end
    if value:find("world", 1, true) then return "world" end
    return "unknown"
end
function Data.target(key, basic)
    basic = type(basic) == "table" and basic or {}
    local function name(value, limit)
        if type(value) ~= "string" then return nil end
        value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
        if #value > 0 then return value end
    end
    -- OCS 1.4.7 normally supplies Name/RawName, rather than Type. An empty
    -- display name must not poison an otherwise valid whole-side catalog.
    local raw = name(basic.RawName or basic.rawName, 128)
    local display = name(basic.Type, 96) or name(basic.type, 96) or name(basic.Name, 96)
        or raw and raw:sub(1, 96) or "Unknown"
    local identity = (display .. " " .. (raw or "")):lower()
    local result = {key = tostring(key), label = display, type = display, rawName = raw,
        kind = identity:find("reactor", 1, true) and "reactor" or "other"}
    local p = basic.Position or basic.position
    if type(p) == "table" and Data.number(p.X) and Data.number(p.Y) and Data.number(p.Z) then result.position = {X = p.X, Y = p.Y, Z = p.Z} end
    return result
end
local function numeric(data, names)
    for _, key in ipairs(names) do if Data.number(data[key]) and data[key] >= 0 then return data[key] end end
end
function Data.reactor(data)
    if type(data) ~= "table" then return nil end
    local heat = numeric(data, {"Heat", "heat", "Temperature"})
    local maximum = numeric(data, {"MaxHeat", "maxHeat", "MaximumHeat"})
    if not heat or not maximum or maximum <= 0 or heat > 1000000000000 or maximum > 1000000000000 then return nil end
    local result = {heat = heat, maxHeat = maximum, output = numeric(data, {"Output", "output", "EUOutput"}),
        energyEmitted = numeric(data, {"EnergyEmitted", "energyEmitted"}),
        energySunken = numeric(data, {"EnergySunken", "EnergySunk", "energySunken"})}
    for _, key in ipairs({"Active", "active", "IsActive"}) do
        if type(data[key]) == "boolean" then result.active = data[key]; break end
    end
    result.melting = numeric(data, {"Melting", "MeltingPoint", "MeltingTemperature"})
    if not result.melting then result.melting, result.meltingDerived = math.floor(maximum * 0.85), true end
    local function duration(value, ticks)
        if type(value) == "string" then
            value = value:match("^%s*(.-)%s*$")
            local h, m, s = value:match("^(%d+):(%d%d):(%d%d)$")
            if not ticks and h and tonumber(m) < 60 and tonumber(s) < 60 then
                value = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
            else value = tonumber(value) end
        end
        if Data.number(value) and value >= 0 and value <= 1000000000000 then return value end
    end
    for _, key in ipairs({"RemainingTime", "TimeRemaining", "Remaining", "remainingTime", "FuelRemainingSeconds",
        "RemainingSeconds", "remainingSeconds", "RemainingTimeSeconds", "TimeLeft", "timeLeft"}) do
        local value = duration(data[key])
        if value ~= nil then result.remaining, result.remainingField = value, key; break end
    end
    if result.remaining == nil then
        for _, key in ipairs({"RemainingTicks", "remainingTicks", "TimeLeftTicks"}) do
            local value = duration(data[key], true)
            if value ~= nil then result.remaining, result.remainingField = value / 20, key; break end
        end
    end
    result.heatToMelting, result.heatToMax = result.melting - heat, maximum - heat
    result.percent = heat / maximum * 100
    return result
end
return Data
