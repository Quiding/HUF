-- HUF: data recorder. While it is on, HUF writes what the client hands out
-- about your character, target, target of target, focus, pet, mouseover and
-- group into the debug log: names (every way the game offers them, with the
-- bytes of unusual characters), class, level, health, power, states, and
-- which of these the client hides as secret values. Plus what HUF and MMT
-- show for the unit. Paste the log (Help > Data recorder) for review.
--
-- Lines: "[rec] target: ..." per unit, "[rec*] ..." for context (zone,
-- combat start / end, group changes). With "Only changes" a unit's line is
-- written again only when something in it changed.

local _, ns = ...
local IsSecret = ns.IsSecret

local Rec = {}
ns.Recorder = Rec

local UNIT_CHOICES = {
    { value = "player",       text = "My character" },
    { value = "target",       text = "Target" },
    { value = "targettarget", text = "Target of target" },
    { value = "focus",        text = "Focus" },
    { value = "focustarget",  text = "Focus target" },
    { value = "pet",          text = "Pet" },
    { value = "mouseover",    text = "Mouseover" },
    { value = "group",        text = "Group / raid members" },
    { value = "nameplates",   text = "Nameplates (up to 8)" },
}
Rec.UNIT_CHOICES = UNIT_CHOICES

local DEFAULTS = {
    enabled = false,
    units = { player = true, target = true, targettarget = true, focus = false, focustarget = false,
              pet = false, mouseover = false, group = true, nameplates = false },
    interval = 1,          -- seconds between checks
    changesOnly = true,
    values = true,         -- health / power
    auras = false,         -- first buffs and debuffs
    secrets = true,        -- the client's C_Secrets answers
    keepNames = true,      -- real names in the log (off: MMT's privacy names when shown)
}

function Rec.DB()
    HUFDB.debug = HUFDB.debug or {}
    HUFDB.debug.recorder = ns.FillDefaults(HUFDB.debug.recorder or {}, DEFAULTS)
    return HUFDB.debug.recorder
end

---------------------------------------------------------------------------
-- Formatting: every value shows what it is
---------------------------------------------------------------------------
local secretCount = 0
local function V(v)
    if IsSecret(v) then secretCount = secretCount + 1 return "SECRET" end
    local t = type(v)
    if v == nil then return "nil" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v == math.floor(v) then return tostring(v) end
        return ("%.1f"):format(v)
    end
    if t == "string" then
        if v == "" then return '""' end
        -- unusual characters as byte codes: "Anna\194\160Lee" -> "Anna<c2><a0>Lee"
        if v:find("[^%w%s%-%'%.%(%)%:,/!%?]") then
            return '"' .. v:gsub("[^%w%s%-%'%.]", function(c) return ("<%02x>"):format(c:byte()) end) .. '"'
        end
        return '"' .. v .. '"'
    end
    if t == "table" then return "{table}" end
    return tostring(v)
end

-- calls fn(...); returns the formatted results, "ERR" when it errors
local function Call(fn, ...)
    if type(fn) ~= "function" then return "n/a" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "ERR" end
    if #r == 1 then return "nil" end
    local out = {}
    for i = 2, #r do out[#out + 1] = V(r[i]) end
    return table.concat(out, "/")
end

local function Raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

---------------------------------------------------------------------------
-- One unit
---------------------------------------------------------------------------
local function Snapshot(unit, db)
    secretCount = 0
    local okE, exists = pcall(UnitExists, unit)
    if not okE then return unit .. ": ERR UnitExists" end
    if not IsSecret(exists) and not exists then return unit .. ": (none)" end
    local f = {}
    local function add(k, v) f[#f + 1] = k .. "=" .. v end

    -- names, every way the client offers them
    add("UnitName", Call(UnitName, unit))
    add("UnitFullName", Call(UnitFullName, unit))
    add("GetUnitName", Call(GetUnitName, unit, true))
    if UnitNameUnmodified then add("Unmodified", Call(UnitNameUnmodified, unit)) end
    local guid = Raw(UnitGUID, unit)
    add("guid", V(guid))
    if guid and not IsSecret(guid) and GetPlayerInfoByGUID then
        -- class, token, race, raceToken, sex, name, realm
        add("byGUID", Call(GetPlayerInfoByGUID, guid))
    end
    add("isPlayer", Call(UnitIsPlayer, unit))
    add("isMe", Call(UnitIsUnit, unit, "player"))
    add("class", Call(UnitClass, unit))
    add("race", Call(UnitRace, unit))
    add("level", Call(UnitLevel, unit))
    if UnitEffectiveLevel then add("effLevel", Call(UnitEffectiveLevel, unit)) end
    add("classification", Call(UnitClassification, unit))
    add("creature", Call(UnitCreatureType, unit))
    add("reaction", Call(UnitReaction, unit, "player"))
    add("friend", Call(UnitIsFriend, "player", unit))
    add("canAttack", Call(UnitCanAttack, "player", unit))
    add("connected", Call(UnitIsConnected, unit))
    add("dead", Call(UnitIsDead, unit))
    add("ghost", Call(UnitIsGhost, unit))
    if UnitIsTapDenied then add("tapDenied", Call(UnitIsTapDenied, unit)) end
    if UnitInRange then add("inRange", Call(UnitInRange, unit)) end
    add("threat", Call(UnitThreatSituation, unit))
    if UnitPhaseReason then add("phase", Call(UnitPhaseReason, unit)) end

    if db.values then
        add("hp", Call(UnitHealth, unit))
        add("hpMax", Call(UnitHealthMax, unit))
        if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            add("hp%", Call(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100))
        end
        if UnitHealthMissing then add("hpMissing", Call(UnitHealthMissing, unit, true)) end
        local ptype = Raw(UnitPowerType, unit)
        add("powerType", Call(UnitPowerType, unit))
        if IsSecret(ptype) then ptype = nil end
        add("power", Call(UnitPower, unit, ptype))
        add("powerMax", Call(UnitPowerMax, unit, ptype))
        if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
            add("power%", Call(UnitPowerPercent, unit, ptype, true, CurveConstants.ScaleTo100))
        end
    end

    -- what the client says it hides (C_Secrets: every Should... question)
    if db.secrets and type(C_Secrets) == "table" then
        local names = {}
        for name, fn in pairs(C_Secrets) do
            if type(fn) == "function" and name:find("^Should") then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local r = Call(C_Secrets[name], unit)
            if r == "ERR" then r = Call(C_Secrets[name]) end
            -- questions that need other arguments (spell, slot ...) are left out
            if r ~= "ERR" then add((name:gsub("^Should", "secret:")), r) end
        end
    end

    if db.auras and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HARMFUL|PLAYER" }) do
            local list, err = {}, nil
            for i = 1, 5 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
                if not ok then err = tostring(a) break end
                if type(a) ~= "table" then break end
                list[#list + 1] = ("%s#%s(x%s %ss)"):format(V(a.name), V(a.spellId), V(a.applications), V(a.duration))
            end
            add("auras " .. filter, err and ("BLOCKED: " .. err) or ("[" .. table.concat(list, ", ") .. "]"))
        end
    end

    -- quest progress the nameplates would show
    if ns.Nameplates and ns.Nameplates.QuestText then
        local okQ, q = pcall(ns.Nameplates.QuestText, unit)
        add("quest", okQ and V(q) or "ERR")
    end

    -- what HUF and MMT make of it
    add("HUF[name]", V(ns.NameText(unit, "PRIVACY")))
    add("HUF[name:full]", V(ns.NameText(unit, "FULL")))
    local m = ns.Bridge and ns.Bridge.MMT()
    if m then
        local first, last = ns.UnitRealNames(unit)
        if first and not IsSecret(first) and type(m.Resolve) == "function" then
            local key
            local ok = pcall(function()
                key = last and (m.Resolve(first .. "-" .. last) or m.Resolve(first .. " " .. last)) or m.Resolve(first)
            end)
            add("MMTkey", ok and V(key) or "ERR")
            if key then add("MMTshown", Call(m.ShownName, key)) end
        end
    end
    for _, fr in ipairs(ns.allFrames or {}) do
        if fr.hunit == unit and fr:IsVisible() then
            for _, which in ipairs({ "health", "power" }) do
                for _, a in ipairs(ns.ANCHORS) do
                    local fs = fr.bars[which].texts[a]
                    if fs:IsShown() then add("shown." .. which .. "." .. a, V(fs:GetText())) end
                end
            end
        end
    end

    local secrets = secretCount
    return ("%s: secrets=%d | %s"):format(unit, secrets, table.concat(f, " | "))
end
Rec.Snapshot = function(unit) return Snapshot(unit, Rec.DB()) end

---------------------------------------------------------------------------
-- Which units, and writing
---------------------------------------------------------------------------
local function Units(db)
    local list = {}
    for _, c in ipairs(UNIT_CHOICES) do
        if c.value ~= "group" and c.value ~= "nameplates" and db.units[c.value] then list[#list + 1] = c.value end
    end
    if db.units.group then
        if IsInRaid() then
            for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
        else
            for i = 1, (GetNumSubgroupMembers() or 0) do list[#list + 1] = "party" .. i end
        end
    end
    if db.units.nameplates then
        local n = 0
        for i = 1, 40 do
            local u = "nameplate" .. i
            local ok, e = pcall(UnitExists, u)
            if ok and ns.Bool(e, true) then
                list[#list + 1] = u
                n = n + 1
                if n >= 8 then break end
            end
        end
    end
    return list
end

local last = {}   -- unit -> last line written
function Rec.Context(why)
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    local inInst, instType = IsInInstance()
    ns.LogRaw("rec*", ("%s | zone=%s instance=%s/%s combat=%s group=%s raid=%s members=%s"):format(
        why, V(zone), V(inInst), V(instType), V(InCombatLockdown()), V(IsInGroup()), V(IsInRaid()), V(GetNumGroupMembers())))
end

function Rec.IsOn() return HUFDB and Rec.DB().enabled or false end

-- a snapshot line: "unit: f1 | f2 | f3 ..."; fields by their name (text before "=")
local function Fields(line)
    local head, rest = line:match("^(.-): (.*)$")
    local list, byName = {}, {}
    for part in ((rest or line) .. " | "):gmatch("(.-) | ") do
        local name = part:match("^([^=]+)=") or part
        list[#list + 1] = name
        byName[name] = part
    end
    return head or line, list, byName
end

-- only what changed since this unit's last line (the whole snapshot the
-- first time and for "now"); all units of one moment share one log line
function Rec.Record(force, only)
    local db = Rec.DB()
    if not db.enabled and not force then return end
    local out = {}
    for _, unit in ipairs(only or Units(db)) do
        local ok, line = pcall(Snapshot, unit, db)
        if not ok then line = unit .. ": ERR " .. tostring(line) end
        local prev = last[unit]
        if force or not db.changesOnly or prev ~= line then
            last[unit] = line
            if force or not prev or not db.changesOnly then
                out[#out + 1] = line
            else
                local head, list, now = Fields(line)
                local _, _, before = Fields(prev)
                local changed = {}
                for _, name in ipairs(list) do
                    if before[name] ~= now[name] then changed[#changed + 1] = now[name] end
                end
                for name in pairs(before) do
                    if not now[name] then changed[#changed + 1] = name .. " gone" end
                end
                if #changed > 0 then out[#out + 1] = head .. ": " .. table.concat(changed, " | ") end
            end
        end
    end
    if #out == 0 then return end
    if force then
        for _, l in ipairs(out) do ns.LogRaw("rec", l) end      -- full snapshots: one per unit
    else
        ns.LogRaw("rec", table.concat(out, "  //  "))
    end
end

-- a snapshot of everything now, written whether it changed or not
function Rec.Now()
    Rec.Context("snapshot")
    Rec.Record(true)
end

local ticker
function Rec.SetEnabled(on)
    local db = Rec.DB()
    db.enabled = on and true or false
    last = {}
    if ticker then ticker:Cancel() ticker = nil end
    if db.enabled then
        Rec.Context("recorder on (HUF " .. ns.version .. ", client " .. table.concat({ GetBuildInfo() }, " ") .. ")")
        Rec.Record(true)
        ticker = C_Timer.NewTicker(math.max(0.2, db.interval), function() Rec.Record(false) end)
    else
        ns.LogRaw("rec*", "recorder off")
    end
end

function Rec.Restart()
    if Rec.DB().enabled then
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(math.max(0.2, Rec.DB().interval), function() Rec.Record(false) end)
    end
end

-- moments worth a line of their own
local function On(event, why, units)
    ns.On(event, function(arg)
        if not (HUFDB and Rec.DB().enabled) then return end
        if why then Rec.Context(why .. (arg and (" " .. tostring(arg)) or "")) end
        Rec.Record(false, units)
    end)
end
On("PLAYER_TARGET_CHANGED", nil, { "target", "targettarget" })
On("PLAYER_FOCUS_CHANGED", nil, { "focus", "focustarget" })
ns.On("UNIT_TARGET", function(unit)
    if not (HUFDB and Rec.DB().enabled) then return end
    if unit == "target" then Rec.Record(false, { "targettarget" })
    elseif unit == "focus" then Rec.Record(false, { "focustarget" }) end
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function()
    if HUFDB and Rec.DB().enabled and Rec.DB().units.mouseover then Rec.Record(false, { "mouseover" }) end
end)
On("PLAYER_REGEN_DISABLED", "combat start")
On("PLAYER_REGEN_ENABLED", "combat end")
On("GROUP_ROSTER_UPDATE", "group changed")
On("ZONE_CHANGED_NEW_AREA", "zone changed")
On("PLAYER_ENTERING_WORLD", "entering world")

ns.OnLogin(function()
    if Rec.DB().enabled then Rec.SetEnabled(true) end
end)
