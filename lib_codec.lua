-- Pack repeated text in bounded blocks using printable ASCII for old CraftOS.
local Codec = rawget(_G, "__smarthomeCodec")
if Codec then return Codec end
Codec = {}
local Work = rawget(_G, "__smarthomeWork") or dofile("lib_work.lua")
local blockSize, maxPackedBytes = 32768, 8 * 1024 * 1024
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local code = {}
for i = 1, #alphabet do code[alphabet:byte(i)] = i - 1 end
local function digit(n) return alphabet:sub(n + 1, n + 1) end

local function packBlock(block)
    local pieces, positions, at, spent = {}, {}, 1, 0
    while at <= #block do
        local prefix = block:sub(at, at + 4)
        local previous = positions[prefix]
        positions[prefix] = at
        local limit, length = math.min(69, #block - at + 1), 1
        if previous and limit >= 6 and block:byte(previous + 5) == block:byte(at + 5) then
            length = 6
            while length < limit and block:byte(previous + length) == block:byte(at + length) do
                length = length + 1
            end
            local distance = at - previous - 1
            pieces[#pieces + 1] = "~" .. digit(math.floor(distance / 4096))
                .. digit(math.floor(distance / 64) % 64) .. digit(distance % 64) .. digit(length - 6)
        else
            local byte = block:byte(at)
            if byte == 126 then pieces[#pieces + 1] = "~~"
            elseif byte < 32 or byte > 126 then
                pieces[#pieces + 1] = "~." .. digit(math.floor(byte / 64)) .. digit(byte % 64)
            else pieces[#pieces + 1] = block:sub(at, at) end
        end
        at, spent = at + length, spent + length
        if spent >= 128 then Work.check(spent * 2); spent = 0 end
    end
    return table.concat(pieces)
end

local function unpackBlock(block, expected)
    assert(type(block) == "string" and #block <= expected * 4, "Invalid backup block")
    local pieces, length, at, spent = {}, 0, 1, 0
    while at <= #block do
        local token, count = block:byte(at), 1
        if token ~= 126 then
            pieces[length + 1] = block:sub(at, at)
            at = at + 1
        else
            local a, b, c, d = block:byte(at + 1, at + 4)
            if a == 126 then pieces[length + 1], at = "~", at + 2
            elseif a == 46 then
                assert(code[b] and code[b] < 4 and code[c], "Invalid backup byte")
                pieces[length + 1], at = string.char(code[b] * 64 + code[c]), at + 4
            else
                assert(code[a] and code[b] and code[c] and code[d], "Invalid backup reference")
                local distance = code[a] * 4096 + code[b] * 64 + code[c] + 1
                count = code[d] + 6
                assert(distance <= length and length + count <= expected, "Backup reference out of bounds")
                for i = 1, count do pieces[length + i] = pieces[length + i - distance] end
                at = at + 5
            end
        end
        length, spent = length + count, spent + count
        assert(length <= expected, "Backup block is too long")
        if spent >= 128 then Work.check(spent * 2); spent = 0 end
    end
    assert(length == expected, "Incomplete backup block")
    return table.concat(pieces)
end

function Codec.checksum(contents)
    local a, b = 1, 0
    for i = 1, #contents do
        a = (a + contents:byte(i)) % 65521
        b = (b + a) % 65521
        if i % 256 == 0 then Work.check(512) end
    end
    return b * 65536 + a
end

function Codec.pack(contents)
    if #contents < 4096 or #contents > maxPackedBytes then return nil end
    local blocks = {}
    for i = 1, #contents, blockSize do blocks[#blocks + 1] = packBlock(contents:sub(i, i + blockSize - 1)) end
    return {bytes = #contents, checksum = Codec.checksum(contents), blocks = blocks}
end

function Codec.unpack(value)
    local size = value.bytes
    assert(type(size) == "number" and size == math.floor(size) and size >= 1 and size <= maxPackedBytes
        and type(value.blocks) == "table" and #value.blocks == math.ceil(size / blockSize), "Invalid packed data")
    local blocks = {}
    for i, block in ipairs(value.blocks) do
        blocks[i] = unpackBlock(block, math.min(blockSize, size - (i - 1) * blockSize))
    end
    local contents = table.concat(blocks)
    assert(Codec.checksum(contents) == value.checksum, "Checksum did not match")
    return contents
end

rawset(_G, "__smarthomeCodec", Codec)
return Codec
