-- HUF: text templates. Each text anchor holds a template such as
-- "[hp] ([hp%])" or "[levelclass:color] | [name]": values in square brackets,
-- everything else shown as typed.
--
-- Values the game hands out as secrets are never compared or calculated
-- with: they go through string.format / AbbreviateNumbers /
-- SetFormattedText, which accept them.

local _, ns = ...
local IsSecret, Safe, Bool = ns.IsSecret, ns.Safe, ns.Bool
local fmt = string.format

-- the values, in the order of the "Insert value" list
ns.TAGS = {
    { header = true, text = "Name" },
    { value = "[name]",       text = "Name (privacy setting)" },
    { value = "[name:first]", text = "First name" },
    { value = "[name:last]",  text = "Last name" },
    { value = "[name:full]",  text = "Full name" },
    { value = "[class]",      text = "Class" },
    { header = true, text = "Level" },
    { value = "[level]",            text = "Level" },
    { value = "[level:color]",      text = "Level (difficulty colour)" },
    { value = "[classification]",   text = "Classification (R, E, RE, B)" },
    { value = "[levelclass]",       text = "Level + classification (55E)" },
    { value = "[levelclass:color]", text = "Level + classification, coloured" },
    { header = true, text = "Health" },
    { value = "[hp]",         text = "Health (HP#)" },
    { value = "[hp:max]",     text = "Maximum health" },
    { value = "[hp%]",        text = "Health % (HP%)" },
    { value = "[hp%:nosign]", text = "Health % without the % sign" },
    { value = "[hp:missing]", text = "Missing health" },
    { value = "[hp:smart]",   text = "Smart health (max when full, else HP | %)" },
    { header = true, text = "Mana / energy / rage" },
    { value = "[mp]",         text = "Power (MP#)" },
    { value = "[mp:max]",     text = "Maximum power" },
    { value = "[mp%]",        text = "Power %" },
    { value = "[mp:missing]", text = "Missing power" },
    { header = true, text = "Other" },
    { value = "[status]",     text = "Dead / Ghost / Offline" },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Abbrev(v)
    if v == nil then return nil end
    if ns.db.global.abbreviate and AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok then return s end
    end
    local ok, s = pcall(fmt, "%d", v)
    return ok and s or nil
end
local function FakeAbbrev(v)
    if not ns.db.global.abbreviate then return tostring(math.floor(v)) end
    if v >= 1e6 then return fmt("%.1fm", v / 1e6) end
    if v >= 1e4 then return fmt("%.1fk", v / 1e3) end
    return tostring(math.floor(v))
end

local function StatusWord(unit)
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and Bool(isPlayer) then
        local ok, c = pcall(UnitIsConnected, unit)
        if ok and not IsSecret(c) and c == false then return "Offline" end
    end
    local okG, ghost = pcall(UnitIsGhost, unit)
    if okG and Bool(ghost) then return "Ghost" end
    local okD, dead = pcall(UnitIsDead, unit)
    if okD and Bool(dead) then return "Dead" end
    return nil
end
ns.StatusWord = StatusWord
local function Word(unit) return ns.db.global.statusText and StatusWord(unit) or nil end

local function HealthPct(unit)
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, v = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if ok and v ~= nil then return v end
    end
    local cur, max = Safe(UnitHealth, unit), Safe(UnitHealthMax, unit)
    if cur and max and max > 0 then return cur / max * 100 end
    return nil
end

local function PowerType(unit)
    local ok, ptype = pcall(UnitPowerType, unit)
    if ok and not IsSecret(ptype) then return ptype end
    return nil
end

function ns.HasPower(unit)
    local max = Safe(UnitPowerMax, unit, PowerType(unit))
    if max ~= nil and max <= 0 then return false end
    return true
end

local function PowerPct(unit)
    local ptype = PowerType(unit)
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, v = pcall(UnitPowerPercent, unit, ptype, true, CurveConstants.ScaleTo100)
        if ok and v ~= nil then return v end
    end
    local cur, max = Safe(UnitPower, unit, ptype), Safe(UnitPowerMax, unit, ptype)
    if cur and max and max > 0 then return cur / max * 100 end
    return nil
end

local CLASSIFICATION = { elite = "E", rareelite = "RE", rare = "R", worldboss = "B" }
local function LevelText(level)
    if level == nil or level <= 0 then return "??" end
    return tostring(level)
end
-- difficulty colour of a level (the game's own function when it gives one,
-- else the classic rules: red 5+ above you, orange 3+, yellow up to 2 below,
-- green, grey when it gives no experience)
local DIFF = {
    red = { r = 1.00, g = 0.10, b = 0.10 }, orange = { r = 1.00, g = 0.50, b = 0.25 },
    yellow = { r = 1.00, g = 0.82, b = 0.00 }, green = { r = 0.25, g = 0.75, b = 0.25 },
    grey = { r = 0.50, g = 0.50, b = 0.50 },
}
local function GreyLevel(me)
    if UnitQuestTrivialLevelRange then
        local r = Safe(UnitQuestTrivialLevelRange, "player")
        if type(r) == "number" then return me - r end
    end
    if me <= 5 then return 0 end
    if me <= 39 then return me - math.floor(me / 10) - 5 end
    if me <= 59 then return me - math.floor(me / 5) - 1 end
    return me - 9
end
local function LevelColor(level)
    if not level or level <= 0 then return DIFF.red end   -- skull
    for _, fn in ipairs({ GetCreatureDifficultyColor, GetQuestDifficultyColor }) do
        local c = Safe(fn, level)
        if type(c) == "table" and type(c.r) == "number" then return c end
    end
    local me = Safe(UnitLevel, "player")
    if type(me) ~= "number" then return nil end
    local d = level - me
    if d >= 5 then return DIFF.red end
    if d >= 3 then return DIFF.orange end
    if d >= -2 then return DIFF.yellow end
    if level > GreyLevel(me) then return DIFF.green end
    return DIFF.grey
end

local function Hex(c)
    return fmt("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end
local function Colored(c, text) return c and (Hex(c) .. text .. "|r") or text end

---------------------------------------------------------------------------
-- Live units: each returns a value (string, number or secret) or nil
---------------------------------------------------------------------------
local Live = {}

Live["name"] = function(u) return ns.NameText(u, "PRIVACY") end
Live["name:first"] = function(u) return ns.NameText(u, "FIRST") end
Live["name:last"] = function(u) return ns.NameText(u, "LAST") end
Live["name:full"] = function(u) return ns.NameText(u, "FULL") end

Live["class"] = function(u)
    local okP, isPlayer = pcall(UnitIsPlayer, u)
    if okP and Bool(isPlayer) then
        local ok, name = pcall(UnitClass, u)
        return ok and name or nil
    end
    local ok, ctype = pcall(UnitCreatureType, u)
    return ok and ctype or nil
end

local function Level(u)
    local ok, level = pcall(UnitLevel, u)
    if not ok then return nil end
    if IsSecret(level) then return level, true end
    return level, false
end
local function Classification(u)
    local ok, cl = pcall(UnitClassification, u)
    if not ok or IsSecret(cl) then return "" end
    return CLASSIFICATION[cl] or ""
end

Live["level"] = function(u)
    local level, secret = Level(u)
    if secret then return level end
    return level and LevelText(level)
end
Live["level:color"] = function(u)
    local level, secret = Level(u)
    if secret or level == nil then return level end
    return Colored(LevelColor(level), LevelText(level))
end
Live["classification"] = function(u)
    local c = Classification(u)
    return c ~= "" and c or nil
end
Live["levelclass"] = function(u)
    local level, secret = Level(u)
    if secret or level == nil then return level end
    return LevelText(level) .. Classification(u)
end
Live["levelclass:color"] = function(u)
    local level, secret = Level(u)
    if secret or level == nil then return level end
    return Colored(LevelColor(level), LevelText(level) .. Classification(u))
end

Live["hp"] = function(u)
    local w = Word(u)
    if w then return w end
    local ok, v = pcall(UnitHealth, u)
    return ok and Abbrev(v) or nil
end
Live["hp:max"] = function(u)
    local ok, v = pcall(UnitHealthMax, u)
    return ok and Abbrev(v) or nil
end
Live["hp%"] = function(u)
    local w = Word(u)
    if w then return w end
    local v = HealthPct(u)
    if v == nil then return nil end
    local ok, s = pcall(fmt, "%d%%", v)
    return ok and s or nil
end
Live["hp%:nosign"] = function(u)
    local w = Word(u)
    if w then return w end
    local v = HealthPct(u)
    if v == nil then return nil end
    local ok, s = pcall(fmt, "%d", v)
    return ok and s or nil
end
Live["hp:missing"] = function(u)
    local w = Word(u)
    if w then return w end
    local v
    if UnitHealthMissing then
        local ok, m = pcall(UnitHealthMissing, u, true)
        if ok then v = m end
    end
    if v == nil then
        local cur, max = Safe(UnitHealth, u), Safe(UnitHealthMax, u)
        if cur and max then v = max - cur end
    end
    if v == nil then return nil end
    if IsSecret(v) then
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            local ok, s = pcall(C_StringUtil.TruncateWhenZero, v)
            if ok then return s end
        end
        return Abbrev(v)
    end
    if v <= 0 then return nil end
    return "-" .. Abbrev(v)
end
Live["hp:smart"] = function(u)
    local w = Word(u)
    if w then return w end
    local okC, cur = pcall(UnitHealth, u)
    local okM, max = pcall(UnitHealthMax, u)
    if not okC or not okM then return nil end
    if not IsSecret(cur) and not IsSecret(max) then
        if max <= 0 then return nil end
        if cur >= max then return Abbrev(max) end
        return fmt("%s | %d%%", Abbrev(cur), cur / max * 100)
    end
    local pct = HealthPct(u)
    if pct == nil then return Abbrev(cur) end
    local ok, s = pcall(fmt, "%s | %d%%", Abbrev(cur), pct)
    return ok and s or Abbrev(cur)
end

Live["mp"] = function(u)
    if not ns.HasPower(u) then return nil end
    local ok, v = pcall(UnitPower, u, PowerType(u))
    return ok and Abbrev(v) or nil
end
Live["mp:max"] = function(u)
    if not ns.HasPower(u) then return nil end
    local ok, v = pcall(UnitPowerMax, u, PowerType(u))
    return ok and Abbrev(v) or nil
end
-- energy and rage are 0-100 anyway: no "%" behind them
local NO_PERCENT = { ENERGY = true, RAGE = true }
local function PowerToken(u)
    local ok, _, token = pcall(UnitPowerType, u)
    if ok and not IsSecret(token) then return token end
end
Live["mp%"] = function(u)
    if not ns.HasPower(u) then return nil end
    local v = PowerPct(u)
    if v == nil then return nil end
    local ok, s = pcall(fmt, NO_PERCENT[PowerToken(u)] and "%d" or "%d%%", v)
    return ok and s or nil
end
Live["mp:missing"] = function(u)
    if not ns.HasPower(u) then return nil end
    local cur, max = Safe(UnitPower, u, PowerType(u)), Safe(UnitPowerMax, u, PowerType(u))
    if not cur or not max or max - cur <= 0 then return nil end
    return "-" .. Abbrev(max - cur)
end
Live["status"] = function(u) return StatusWord(u) end

---------------------------------------------------------------------------
-- Previews (unlock mode)
---------------------------------------------------------------------------
local Fake = {}
Fake["name"] = function(f) return ns.NameText(nil, "PRIVACY", f) end
Fake["name:first"] = function(f) return ns.NameText(nil, "FIRST", f) end
Fake["name:last"] = function(f) return ns.NameText(nil, "LAST", f) end
Fake["name:full"] = function(f) return ns.NameText(nil, "FULL", f) end
Fake["class"] = function(f)
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    return f.class and (names[f.class] or f.class) or "Humanoid"
end
Fake["level"] = function(f) return LevelText(f.level) end
Fake["level:color"] = function(f) return Colored(LevelColor(f.level), LevelText(f.level)) end
Fake["classification"] = function(f) local c = CLASSIFICATION[f.classification or ""] return c end
Fake["levelclass"] = function(f) return LevelText(f.level) .. (CLASSIFICATION[f.classification or ""] or "") end
Fake["levelclass:color"] = function(f)
    return Colored(LevelColor(f.level), LevelText(f.level) .. (CLASSIFICATION[f.classification or ""] or ""))
end
local function FakeWord(f)
    if not ns.db.global.statusText then return nil end
    if f.offline then return "Offline" end
    if f.dead then return "Dead" end
end
Fake["hp"] = function(f) return FakeWord(f) or FakeAbbrev(f.hp) end
Fake["hp:max"] = function(f) return FakeAbbrev(f.maxhp) end
Fake["hp%"] = function(f) return FakeWord(f) or fmt("%d%%", f.hp / f.maxhp * 100) end
Fake["hp%:nosign"] = function(f) return FakeWord(f) or fmt("%d", f.hp / f.maxhp * 100) end
Fake["hp:missing"] = function(f)
    local w = FakeWord(f)
    if w then return w end
    local m = f.maxhp - f.hp
    return m > 0 and ("-" .. FakeAbbrev(m)) or nil
end
Fake["hp:smart"] = function(f)
    local w = FakeWord(f)
    if w then return w end
    if f.hp >= f.maxhp then return FakeAbbrev(f.maxhp) end
    return fmt("%s | %d%%", FakeAbbrev(f.hp), f.hp / f.maxhp * 100)
end
Fake["mp"] = function(f) return f.maxpower > 0 and FakeAbbrev(f.power) or nil end
Fake["mp:max"] = function(f) return f.maxpower > 0 and FakeAbbrev(f.maxpower) or nil end
Fake["mp%"] = function(f)
    if f.maxpower <= 0 then return nil end
    local t = f.powerToken
    return fmt((t == "ENERGY" or t == "RAGE") and "%d" or "%d%%", f.power / f.maxpower * 100)
end
Fake["mp:missing"] = function(f)
    local m = f.maxpower - f.power
    return m > 0 and ("-" .. FakeAbbrev(m)) or nil
end
Fake["status"] = function(f) return f.dead and "Dead" or (f.offline and "Offline") or nil end

---------------------------------------------------------------------------
-- Templates: "[hp] ([hp%])" -> format "%s (%s)" + tags { "hp", "hp%" }
---------------------------------------------------------------------------
local parsed = {}
local function Parse(template)
    local p = parsed[template]
    if p then return p end
    local parts, tags = {}, {}
    local pos = 1
    while true do
        local s, e, tag = template:find("%[([%w:%%]+)%]", pos)
        if not s then break end
        if Live[tag] then
            parts[#parts + 1] = template:sub(pos, s - 1):gsub("%%", "%%%%")
            parts[#parts + 1] = "%s"
            tags[#tags + 1] = tag
        else
            parts[#parts + 1] = template:sub(pos, e):gsub("%%", "%%%%")
        end
        pos = e + 1
    end
    parts[#parts + 1] = template:sub(pos):gsub("%%", "%%%%")
    p = { fmt = table.concat(parts), tags = tags }
    parsed[template] = p
    return p
end

function ns.IsKnownTag(tag) return Live[tag] ~= nil end

local vals = {}
-- writes template for frame f (live unit or preview) into fontstring fs
function ns.SetTemplateText(fs, f, template)
    if not template or template == "" then fs:SetText("") return end
    local p = Parse(template)
    local n = #p.tags
    if n == 0 then fs:SetText(template) return end
    local fake = f.fake
    local any = false
    for i = 1, n do
        local tag = p.tags[i]
        local fn = fake and Fake[tag] or Live[tag]
        local v
        local ok, r = pcall(fn, fake or f.hunit)
        if ok then v = r end
        if v == nil then v = "" else any = true end
        vals[i] = v
    end
    -- nothing to show (no unit data at all): no stray separators
    if not any then fs:SetText("") return end
    local ok = pcall(fs.SetFormattedText, fs, p.fmt, unpack(vals, 1, n))
    if not ok then fs:SetText("") end
    for i = 1, n do vals[i] = nil end
end
