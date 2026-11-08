-- Bounded, shared history of IO side snapshots. A single event represents
-- all 16 bundled wires and the digital wire on that side.
local History = {}
local CAPACITY, HORIZON = 192, 300
local function stateAt(sample, color)
    if not sample or sample.mask == nil then return "?" end
    if color then
        if math.floor((sample.pending or 0) / color) % 2 == 1 then return "p" end
        return math.floor(sample.mask / color) % 2 == 1 and "1" or "0"
    end
    if sample.digitalPending then return "p" end
    return sample.digital and "1" or "0"
end

function History.new()
    local clients = {}
    local history = {}
    local function find(id, side, direction)
        local client = clients[id]
        return client and client[direction] and client[direction][side]
    end
    function history.record(id, side, direction, at, mask, digital, pending, digitalPending)
        local trail = find(id, side, direction)
        if not trail then
            if mask == nil then return end
            clients[id] = clients[id] or {input = {}, output = {}}
            trail = {first = 1, last = 0}
            clients[id][direction][side] = trail
        end
        local previous = trail[trail.last % CAPACITY]
        if previous and previous.mask == mask and previous.digital == digital and previous.pending == pending
            and previous.digitalPending == digitalPending then return end
        trail.last = trail.last + 1
        trail[trail.last % CAPACITY] = {at = previous and math.max(at, previous.at) or at, mask = mask,
            digital = digital, pending = pending, digitalPending = digitalPending}
        trail.first = math.max(trail.first, trail.last - CAPACITY + 1)
        while trail.first < trail.last and trail[(trail.first + 1) % CAPACITY].at < at - HORIZON do
            trail[trail.first % CAPACITY] = nil
            trail.first = trail.first + 1
        end
    end
    function history.offline(id, at)
        for direction, sides in pairs(clients[id] or {}) do
            for side in pairs(sides) do history.record(id, side, direction, at) end
        end
    end
    function history.trace(address, finish, seconds, width)
        local trail = find(address.clientId, address.side, address.direction)
        if not trail then return string.rep("?", width), "?" end
        local now = stateAt(trail[trail.last % CAPACITY], address.color)
        local start = finish - seconds
        local index, value = trail.first, "?"
        while index <= trail.last and trail[index % CAPACITY].at <= start do
            value = stateAt(trail[index % CAPACITY], address.color)
            index = index + 1
        end
        local cells = {}
        for x = 1, width do
            local deadline = start + seconds * x / width
            local changed = false
            while index <= trail.last and trail[index % CAPACITY].at <= deadline do
                local nextValue = stateAt(trail[index % CAPACITY], address.color)
                changed = changed or nextValue ~= value
                value, index = nextValue, index + 1
            end
            cells[x] = changed and "|" or value
        end
        return table.concat(cells), now
    end
    return history
end
return History
