-- HUF: profile export / import as one line of text (copy & paste between
-- accounts). "HUF1:" + base64 of a small length-prefixed serialization:
--   table {k v k v ...}  string s<len>:<bytes>  number n<value>;  true t  false f
-- Nothing is run when importing: the text is only parsed.

local _, ns = ...

local PREFIX = "HUF1:"

---------------------------------------------------------------------------
-- Serialize / parse
---------------------------------------------------------------------------
local function Ser(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "table" then
        if depth > 20 then error("too deep") end
        out[#out + 1] = "{"
        -- sorted keys: the same settings give the same text
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local vt = type(val)
            if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
                Ser(k, out, depth)
                Ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

local function Parse(s)
    local pos = 1
    local function Value(depth)
        if depth > 20 then error("too deep") end
        local c = s:sub(pos, pos)
        if c == "s" then
            local len, colon = s:match("^(%d+)():", pos + 1)
            if not len then error("bad text at " .. pos) end
            len = tonumber(len)
            local start = colon + 1
            local v = s:sub(start, start + len - 1)
            if #v ~= len then error("text cut off") end
            pos = start + len
            return v
        elseif c == "n" then
            local num, after = s:match("^([^;]+);()", pos + 1)
            local v = tonumber(num or "")
            if not v then error("bad number at " .. pos) end
            pos = after
            return v
        elseif c == "t" then pos = pos + 1 return true
        elseif c == "f" then pos = pos + 1 return false
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while true do
                if pos > #s then error("text cut off") end
                if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
                local k = Value(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
                t[k] = Value(depth + 1)
            end
        end
        error("unexpected '" .. c .. "' at " .. pos)
    end
    local v = Value(0)
    if pos <= #s then error("extra text at the end") end
    return v
end

---------------------------------------------------------------------------
-- Base64 (letters, digits, + and /: safe in edit boxes and chat)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end

local function Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Decode(text)
    text = text:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #text, 4 do
        local q = { text:byte(i, i + 3) }
        local n, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j]
            local v
            if not ch or ch == 61 then v = 0 pad = pad + 1 else v = DEC[ch] end
            if not v then error("not a HUF text") end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- only what differs from the defaults (import fills the rest back in)
local function Diff(t, d)
    if type(t) ~= "table" or type(d) ~= "table" then
        if t == d then return nil end
        return t
    end
    local out, any = {}, false
    for k, v in pairs(t) do
        local dv = d[k]
        local x
        if type(v) == "table" then x = Diff(v, dv) if x == nil and type(dv) ~= "table" then x = {} end
        elseif v ~= dv then x = v end
        if x ~= nil then out[k] = x any = true end
    end
    return any and out or nil
end

function ns.ExportProfile()
    local out = {}
    local changed = Diff(ns.db, ns.DEFAULTS) or {}
    changed.units = changed.units or {}       -- marks it as HUF settings
    Ser(changed, out, 0)
    return PREFIX .. Encode(table.concat(out))
end

-- ok, table or ok=false, error text
function ns.ReadProfileText(text)
    text = ns.Trim(text or "")
    if text == "" then return false, "Paste a HUF profile text first." end
    if text:sub(1, #PREFIX) ~= PREFIX then return false, "That is not a HUF profile text (it starts with " .. PREFIX .. ")." end
    local ok, data = pcall(Decode, text:sub(#PREFIX + 1))
    if not ok then return false, "The text is damaged (incomplete copy?)." end
    local okP, t = pcall(Parse, data)
    if not okP or type(t) ~= "table" then return false, "The text is damaged (incomplete copy?)." end
    if type(t.units) ~= "table" and type(t.global) ~= "table" then return false, "No HUF settings in this text." end
    return true, t
end

-- replaces every setting of the active profile
function ns.ImportProfile(t)
    local name = ns.CurrentProfileName()
    HUFDB.profiles[name] = ns.CopyTable(t)
    ns.SetProfile(name)
    ns.Log("config", "profile imported into %s", name)
end

ns.ShareTest = { Ser = Ser, Parse = Parse, Encode = Encode, Decode = Decode }
