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
    local kind = tostring(basic.Type or basic.type or basic.Name or "Unknown"):gsub("[%c]", " "):sub(1, 96)
    local result = {key = tostring(key), label = kind, type = kind, kind = kind:lower():find("reactor", 1, true) and "reactor" or "other"}
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
    local result = {heat = heat, maxHeat = maximum, output = numeric(data, {"Output", "output", "EUOutput"})}
    for _, key in ipairs({"Active", "active", "IsActive"}) do
        if type(data[key]) == "boolean" then result.active = data[key]; break end
    end
    result.melting = numeric(data, {"Melting", "MeltingPoint", "MeltingTemperature"})
    if not result.melting then result.melting, result.meltingDerived = math.floor(maximum * 0.85), true end
    result.remaining = numeric(data, {"RemainingTime", "TimeRemaining", "Remaining", "remainingTime", "FuelRemainingSeconds"})
    if not result.remaining and Data.number(data.RemainingTicks) and data.RemainingTicks >= 0 then result.remaining = data.RemainingTicks / 20 end
    if not result.remaining then
        for _, key in ipairs({"RemainingTime", "TimeRemaining", "Remaining"}) do
            if type(data[key]) == "string" then
                local h, m, s = data[key]:match("^(%d+):(%d%d):(%d%d)$")
                if h and tonumber(m) < 60 and tonumber(s) < 60 then result.remaining = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s); break end
            end
        end
    end
    result.percent = heat / maximum * 100
    return result
end
return Data
