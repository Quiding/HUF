-- HUF: damage meter. Shows the game's own meter data (C_DamageMeter) in a
-- HUF window, with names that follow HUF's privacy setting and MMT's, and
-- hides Blizzard's meter window (CVar damageMeterEnabled, put back when off).
--
-- Names: out of combat the meter's names and GUIDs are readable. In combat in
-- instances the game hands them to addons as secret values: they can't be
-- looked at, only shown as they are (the real name). While names are private
-- HUF never shows a secret real name; it finds the player another way:
--   1. "this is you" (isLocalPlayer)
--   2. a readable GUID or name -> the group unit -> the privacy name
--   3. a class only one group member has -> that member
--   4. class + specialisation icon, learned from readable rows after a fight
--   5. otherwise the class name ("Hunter"): right again when the fight ends.

local _, ns = ...
local UI = ns.UI
local IsSecret = ns.IsSecret

local DM = {}
ns.DamageMeter = DM

local function S() return ns.db.damageMeter end

local TYPES = {
    { key = "DamageDone", text = "Damage done", perSecond = true },
    { key = "HealingDone", text = "Healing done", perSecond = true },
    { key = "DamageTaken", text = "Damage taken", perSecond = true },
    { key = "AvoidableDamageTaken", text = "Avoidable damage", perSecond = true },
    { key = "EnemyDamageTaken", text = "Enemy damage taken", perSecond = true },
    { key = "Interrupts", text = "Interrupts", count = true },
    { key = "Dispels", text = "Dispels", count = true },
    { key = "Deaths", text = "Deaths", deaths = true },
    { key = "Threat", text = "Threat", threat = true },     -- HUF's own: the group's threat on your enemy
}
DM.TYPES = TYPES
local TYPE_BY_KEY = {}
for i, t in ipairs(TYPES) do t.index = i TYPE_BY_KEY[t.key] = t end

local function Available()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType
        and Enum.DamageMeterSessionType and true or false
end
DM.Available = Available

local function Plain(v) return v ~= nil and not IsSecret(v) end

---------------------------------------------------------------------------
-- Blizzard's meter window: off while HUF's meter is on
---------------------------------------------------------------------------
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end
local function SetCV(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

local cvarPending
function DM.ApplyBlizzard()
    if not HUFDB or not ns.db then return end
    if InCombatLockdown() then cvarPending = true return end
    cvarPending = nil
    local cur = GetCV("damageMeterEnabled")
    if cur == nil then return end
    local want = S().enabled and S().hideBlizzard and Available()
    local saved = HUFDB.damageMeterCVar
    if want then
        if cur ~= "0" then
            if not saved then HUFDB.damageMeterCVar = { old = cur } end
            SetCV("damageMeterEnabled", "0")
        end
    elseif saved then
        if cur == "0" then SetCV("damageMeterEnabled", saved.old) end
        HUFDB.damageMeterCVar = nil
    end
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        for i = 1, (GetNumSubgroupMembers() or 0) do list[#list + 1] = "party" .. i end
    end
    return list
end

local roster = { byGUID = {}, byName = {}, byClass = {}, guidOf = {} }   -- rebuilt on roster changes
local specGUID = {}      -- "HUNTER:132215" -> guid (false: two members share it)

local function RebuildRoster()
    local oldGuid = roster.guidOf or {}
    roster = { byGUID = {}, byName = {}, byClass = {}, guidOf = {} }
    for _, u in ipairs(GroupUnits()) do
        local okG, g = pcall(UnitGUID, u)
        if okG and Plain(g) then roster.byGUID[g] = u roster.guidOf[u] = g
        elseif oldGuid[u] then roster.guidOf[u] = oldGuid[u] end
        local first, last = ns.UnitRealNames(u)
        if Plain(first) then
            roster.byName[ns.NormKey(first)] = roster.byName[ns.NormKey(first)] == nil and u or false
            if Plain(last) and last then roster.byName[ns.NormKey(first .. " " .. last)] = u end
        end
        local class = ns.Safe(function() return select(2, UnitClass(u)) end)
        if class then roster.byClass[class] = roster.byClass[class] == nil and u or false end
    end
end

local function NamesPrivate()
    if ns.db.privacy.mode ~= "FULL" then return true end
    return ns.Bridge and ns.Bridge.Active() and true or false
end

local function ClassLabel(class)
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    return names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- a readable name of someone not in the group: MMT's name for a team
-- member, else HUF's name part
local function NameFromString(name)
    local m = ns.Bridge and ns.Bridge.Active() and ns.Bridge.MMT()
    if m and m.Resolve and m.ShownName then
        local ok, key = pcall(m.Resolve, name)
        if ok and key then
            local ok2, shown = pcall(m.ShownName, key)
            if ok2 and type(shown) == "string" and shown ~= "" then return shown end
        end
    end
    local first, last = name:match("^(%S+)%s+(.+)$")
    first = first or name
    local mode = ns.db.privacy.mode
    if mode == "LAST" and last then return last end
    if mode == "FULL" then return name end
    return first
end

-- the unit (in your group) a meter row belongs to, if HUF can tell
local function RowUnit(src)
    if src.unit then return src.unit end
    local own = src.isLocalPlayer
    if Plain(own) and own == true then return "player" end
    local g = src.sourceGUID
    if Plain(g) and roster.byGUID[g] then return roster.byGUID[g] end
    local name = src.name
    if Plain(name) and type(name) == "string" then
        local u = roster.byName[ns.NormKey(name)]
        if u then return u end
        local first = name:match("^(%S+)")
        u = first and roster.byName[ns.NormKey(first)]
        if u then return u end
    end
    local class = src.classFilename
    if Plain(class) and type(class) == "string" and class ~= "" then
        local u = roster.byClass[class]
        if u then return u end
        local icon = src.specIconID
        if Plain(icon) then
            local sg = specGUID[class .. ":" .. tostring(icon)]
            if sg and roster.byGUID[sg] then return roster.byGUID[sg] end
        end
    end
end

-- is this row a player (not an NPC or a pet)?
local function IsPlayerRow(src)
    local class = src.classFilename
    if not Plain(class) then return nil end            -- can't tell
    if type(class) ~= "string" or class == "" then return false end
    local cid = src.sourceCreatureID
    if Plain(cid) and cid and cid ~= 0 then return false end
    return true
end

-- text and how it was found ("unit", "name", "class", "secret", "npc")
function DM.RowName(src)
    if src.pet then return src.name or "?", "pet" end
    local unit = RowUnit(src)
    if unit then return ns.NameText(unit, "PRIVACY"), "unit" end
    local player = IsPlayerRow(src)
    local name = src.name
    if player == false then return name or "?", "npc" end
    if Plain(name) and type(name) == "string" then
        if player then return NameFromString(name), "name" end
        return name, "npc"
    end
    -- secret name of a player (or of someone HUF can't tell apart)
    if not NamesPrivate() and name ~= nil then return name, "secret" end
    local class = src.classFilename
    if Plain(class) and type(class) == "string" and class ~= "" then return ClassLabel(class), "class" end
    return "?", "hidden"
end

-- learns class + spec icon -> GUID from readable rows (after a fight)
local function Learn()
    if not Available() or InCombatLockdown() then return end
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Overall,
        Enum.DamageMeterType.DamageDone)
    if not ok or type(s) ~= "table" or type(s.combatSources) ~= "table" then return end
    for _, src in ipairs(s.combatSources) do
        local g, cls, ic = src.sourceGUID, src.classFilename, src.specIconID
        if Plain(g) and Plain(cls) and Plain(ic) and type(cls) == "string" and cls ~= "" then
            local key = cls .. ":" .. tostring(ic)
            if specGUID[key] ~= nil and specGUID[key] ~= g then specGUID[key] = false
            else specGUID[key] = g end
        end
    end
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
-- whole numbers up to 9999, then 12.3K / 1.23M. The game's own
-- AbbreviateNumbers with HUF's tiers: it also takes secret values (in combat)
-- and never shows decimals below 10,000 (per second used to read 845.3333).
local abbrevConfig
local function AbbrevConfig()
    if abbrevConfig ~= nil then return abbrevConfig end
    abbrevConfig = false
    if CreateAbbreviateConfig then
        local ok, cfg = pcall(CreateAbbreviateConfig, {
            { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000000, abbreviation = "M", significandDivisor = 10000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 10000, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
        })
        if ok and cfg then abbrevConfig = cfg end
    end
    return abbrevConfig
end

local function Short(v)
    if v == nil then return "" end
    if Plain(v) and type(v) == "number" then
        v = math.floor(v + 0.5)
        if v < 10000 then return tostring(v) end
    end
    local cfg = AbbrevConfig()
    if AbbreviateNumbers then
        local ok, s
        if cfg then ok, s = pcall(AbbreviateNumbers, v, cfg) else ok, s = pcall(AbbreviateNumbers, v) end
        if ok and s ~= nil then return s end
    end
    local ok, s = pcall(string.format, "%.0f", v)
    return ok and s or ""
end
DM.Short = Short

local function ValueText(fs, src, t)
    local c = S()
    if t.threat then
        local ok = pcall(fs.SetFormattedText, fs, "%d%%", src.threatPct or 0)
        if not ok then fs:SetText("") end
        return
    end
    if t.deaths then
        local secs = src.deathTimeSeconds
        if Plain(secs) and type(secs) == "number" then
            fs:SetFormattedText("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
        else
            fs:SetText("")
        end
        return
    end
    local total, ps = src.totalAmount, src.amountPerSecond
    if t.count or not t.perSecond or c.numbers == "TOTAL" or ps == nil then
        fs:SetText(Short(total))
    elseif c.numbers == "PERSECOND" then
        fs:SetText(Short(ps))
    else
        local ok = pcall(fs.SetFormattedText, fs, "%s (%s)", Short(total), Short(ps))
        if not ok then fs:SetText(Short(total)) end
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- several windows (e.g. damage and threat side by side): each has its own
-- list, fight and position (S().windows[i]); size and look are shared.
-- The window code works on `win`, the window at hand.
local win
local wins = {}
local ROW_POOL = 40
local MAX_WINDOWS = 5

local function WC() return win.cfg end
-- rows of the window at hand: its own (windows[i].rows, e.g. from an
-- EllesmereUI import) or the shared setting
local function Rows()
    local r = win and win.cfg and win.cfg.rows
    if type(r) == "number" and r >= 1 then return r end
    return S().rows
end

-- per-window settings; the first window takes over the settings from
-- before there were several windows
function DM.EnsureWindows()
    local c = S()
    if type(c.windows) ~= "table" then
        c.windows = { { meterType = c.meterType or "DamageDone", session = c.session or "CURRENT",
                        point = ns.CopyTable(c.point or { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 220 }) } }
    end
    c.windowCount = math.max(1, math.min(MAX_WINDOWS, c.windowCount or 1))
    for i = 1, c.windowCount do
        local w = c.windows[i]
        if type(w) ~= "table" then
            -- a new window: left of the one before, threat if that one shows damage
            local before = c.windows[i - 1]
            local p = before.point
            w = { meterType = before.meterType == "Threat" and "DamageDone" or "Threat", session = "CURRENT",
                  point = { p[1], p[2], p[3] - c.width - 8, p[4] } }
            c.windows[i] = w
        end
        w.meterType = w.meterType or "DamageDone"
        w.session = w.session or "CURRENT"
        w.point = w.point or { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 220 }
    end
    return c.windows
end

local function SessionLabel()
    local c = WC()
    if c.session == "OVERALL" then return "Overall" end
    if type(c.session) == "number" then return DM.SessionName(c.session) or "Earlier fight" end
    return "Current"
end

function DM.Sessions()
    local list = { { id = "CURRENT", text = "Current" }, { id = "OVERALL", text = "Overall" } }
    if Available() and C_DamageMeter.GetAvailableCombatSessions then
        local ok, sess = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if ok and type(sess) == "table" then
            for i = #sess, 1, -1 do
                local s = sess[i]
                if Plain(s.sessionID) then
                    local name = Plain(s.name) and s.name or ("Fight " .. i)
                    list[#list + 1] = { id = s.sessionID, text = name }
                end
            end
        end
    end
    return list
end

function DM.SessionName(id)
    for _, e in ipairs(DM.Sessions()) do if e.id == id then return e.text end end
end

---------------------------------------------------------------------------
-- Threat: every group member's (and pet's) threat on your enemy, read with
-- UnitDetailedThreatSituation (readable on Forever)
---------------------------------------------------------------------------
local function Enemy()
    for _, u in ipairs({ "target", "targettarget" }) do
        local okE, e = pcall(UnitExists, u)
        local okA, a = pcall(UnitCanAttack, "player", u)
        local okD, d = pcall(UnitIsDead, u)
        if okE and ns.Bool(e) and okA and ns.Bool(a) and not (okD and ns.Bool(d)) then return u end
    end
end

local function ThreatSession()
    local mob = Enemy()
    if not mob then return { combatSources = {}, empty = "No enemy targeted" } end
    local list, sortable = {}, true
    local units = GroupUnits()
    local pets = {}
    for _, u in ipairs(units) do
        local p = (u == "player") and "pet" or u:gsub("^party", "partypet"):gsub("^raid", "raidpet")
        pets[#pets + 1] = p
    end
    local function Add(u, isPet)
        local okE, e = pcall(UnitExists, u)
        if not (okE and ns.Bool(e)) then return end
        local ok, tanking, status, pct, raw, value = pcall(UnitDetailedThreatSituation, u, mob)
        if not ok or pct == nil then return end
        if IsSecret(pct) or IsSecret(value) then sortable = false end
        local name
        if isPet then name = ns.Safe(function() return UnitName(u) end) or "Pet" end
        list[#list + 1] = { unit = (not isPet) and u or nil, pet = isPet, name = name, threatPct = pct,
            threatValue = value, threatStatus = status, tanking = tanking,
            classFilename = (not isPet) and ns.Safe(function() return select(2, UnitClass(u)) end) or "" }
    end
    for _, u in ipairs(units) do Add(u, false) end
    if S().threatPets then for _, u in ipairs(pets) do Add(u, true) end end
    if sortable then
        table.sort(list, function(a, b) return (a.threatValue or 0) > (b.threatValue or 0) end)
    end
    local title = ns.Safe(function() return UnitName(mob) end)
    return { combatSources = list, title = title }
end

local function GetSession()
    if not Available() then return nil end
    local c = WC()
    local t = TYPE_BY_KEY[c.meterType] or TYPES[1]
    if t.threat then return ThreatSession(), t end
    local mtype = Enum.DamageMeterType[t.key]
    if mtype == nil then return nil, t end
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, c.session, mtype)
    else
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, st, mtype)
    end
    if not ok then
        if not DM.warned then ns.Log("meter", "reading the meter failed: %s", tostring(s)) DM.warned = true end
        return nil, t
    end
    return s, t
end

---------------------------------------------------------------------------
-- Breakdown: one row's spells (like the game's own meter). The game's
-- getters refuse secret arguments, so in combat a row needs a plain GUID:
-- yours, or a group member's that HUF recognised (RowUnit).
---------------------------------------------------------------------------
local bd = { open = false }      -- guid, cid, name, unit of the shown row

local function RowIdentity(src)
    local g, cid = src.sourceGUID, src.sourceCreatureID
    if Plain(g) and (cid == nil or Plain(cid)) then return g, cid end
    local unit = RowUnit(src)
    if unit then
        local okG, ug = pcall(UnitGUID, unit)
        if okG and Plain(ug) then return ug, nil end
        if roster.guidOf[unit] then return roster.guidOf[unit], nil end
    end
end

local function GetBreakdown()
    local c = (bd.win or win).cfg
    local t = TYPE_BY_KEY[c.meterType] or TYPES[1]
    if t.threat or t.deaths then return nil, t, t.threat and "No breakdown for threat" or "No breakdown for deaths" end
    if not bd.guid and bd.unit then bd.guid = roster.guidOf[bd.unit] end
    if not bd.guid and not bd.cid then return nil, t, "Available when the fight ends" end
    local mtype = Enum.DamageMeterType[t.key]
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionSourceFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromID, c.session, mtype, bd.guid, bd.cid)
    elseif C_DamageMeter.GetCombatSessionSourceFromType then
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromType, st, mtype, bd.guid, bd.cid)
    end
    if not ok or type(s) ~= "table" or type(s.combatSpells) ~= "table" then
        return nil, t, InCombatLockdown() and "Available when the fight ends" or "Nothing in this fight"
    end
    return s.combatSpells, t
end

local function SpellInfo(id)
    local name, icon
    if id ~= nil then
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok then name = n end
        elseif GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then name = n end
        end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, id)
            if ok then icon = t end
        elseif GetSpellTexture then
            local ok, t = pcall(GetSpellTexture, id)
            if ok then icon = t end
        end
    end
    return name, icon
end

local function BarColor(bar, src)
    local c = S()
    if src.threatStatus ~= nil and c.threatColors then
        -- the game's threat colours: grey, yellow, orange, red (tanking)
        local st = src.threatStatus
        if Plain(st) and GetThreatStatusColor then
            local ok, r, g, b = pcall(GetThreatStatusColor, st)
            if ok and r then
                if st == 0 then r, g, b = 0.55, 0.55, 0.58 end
                bar:SetStatusBarColor(r, g, b)
                return
            end
        end
    end
    if c.colorMode == "ACCENT" then
        local a = ns.ACCENT
        bar:SetStatusBarColor(a[1], a[2], a[3])
        return
    elseif c.colorMode == "STATIC" then
        bar:SetStatusBarColor(c.color.r, c.color.g, c.color.b)
        return
    end
    local class = src.classFilename
    if Plain(class) then
        local col = ns.ClassColor(class)
        if col then bar:SetStatusBarColor(col.r, col.g, col.b) return end
    elseif class ~= nil and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, class)
        if ok and col and pcall(bar.SetStatusBarColor, bar, col:GetRGB()) then return end
    end
    bar:SetStatusBarColor(0.45, 0.45, 0.48)
end

local function Row(i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("StatusBar", nil, win.body)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.right = r:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(r.left, "GLOBAL", 11, "OUTLINE")
    ns.ApplyFont(r.right, "GLOBAL", 11, "OUTLINE")
    r.left:SetJustifyH("LEFT")
    r.right:SetJustifyH("RIGHT")
    r.left:SetWordWrap(false)
    r:EnableMouse(true)
    r.win = win
    r:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.src then
            win = self.win
            DM.OpenBreakdown(self.src, self.name)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.src or self.isThreat then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click: what this was made of", 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.rows[i] = r
    return r
end

local function RefreshOne()
    if not win or not win:IsShown() then return end
    local c = S()
    local wc = WC()
    local session, t = GetSession()
    t = t or TYPES[1]
    win.typeText:SetText(t.text)
    win.sessionText:SetText(SessionLabel())
    local sources = session and session.combatSources or {}
    local n = #sources
    win.sessB:SetDisabled(t.threat and true or false)    -- threat: the enemy's name stands there
    if t.threat then
        win.sessionText:SetText(session and session.title or "")
        win.empty:SetText(session and session.empty or "No threat yet")
    else
        win.empty:SetText("No data yet")
    end
    win.addB:SetShown(S().windowCount < MAX_WINDOWS)
    win.offset = math.max(0, math.min(win.offset or 0, n - Rows()))
    local maxAmount = sources[1] and sources[1].totalAmount
    local shown = 0
    for i = 1, Rows() do
        local r = Row(i)
        local src = sources[i + win.offset]
        if src then
            shown = shown + 1
            local rank = i + win.offset
            local name = DM.RowName(src)
            r.src, r.name, r.isThreat = src, name, t.threat
            if c.showRank then
                local ok = pcall(r.left.SetFormattedText, r.left, "%d. %s", rank, name)
                if not ok then r.left:SetText(name) end
            else
                r.left:SetText(name)
            end
            ValueText(r.right, src, t)
            if t.threat then
                r:SetMinMaxValues(0, 100)
                if not pcall(r.SetValue, r, src.threatPct or 0) then r:SetValue(0) end
            elseif t.deaths or maxAmount == nil then
                r:SetMinMaxValues(0, 1) r:SetValue(1)
            else
                if not pcall(r.SetMinMaxValues, r, 0, maxAmount) then r:SetMinMaxValues(0, 1) end
                if not pcall(r.SetValue, r, src.totalAmount or 0) then r:SetValue(0) end
            end
            BarColor(r, src)
            r:Show()
        else
            r.src = nil
            r:Hide()
        end
    end
    for i = Rows() + 1, #win.rows do win.rows[i]:Hide() end
    win.empty:SetShown(shown == 0)
end

function DM.Refresh()
    local keep = win
    for _, w in ipairs(wins) do
        win = w
        RefreshOne()
    end
    win = keep
    if bd.open then DM.RefreshBreakdown() end
end

---------------------------------------------------------------------------
-- Breakdown panel: beside the meter (right, or left when there's no room)
---------------------------------------------------------------------------
local panel
local TitleButton      -- defined with the window's title bar below
local function PanelRow(i)
    local r = panel.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, panel.body)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT")
    r.icon:SetPoint("BOTTOMLEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 1, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.left = r.bar:CreateFontString(nil, "OVERLAY")
    r.right = r.bar:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(r.left, "GLOBAL", 11, "OUTLINE")
    ns.ApplyFont(r.right, "GLOBAL", 11, "OUTLINE")
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r.right:SetJustifyH("RIGHT")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local id = self.spellID
        if id == nil or not Plain(id) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if pcall(GameTooltip.SetSpellByID, GameTooltip, id) then GameTooltip:Show() end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rows[i] = r
    return r
end

local function BuildPanel()
    if panel then return end
    local p = CreateFrame("Frame", "HUF_DamageMeterBreakdown", UIParent)
    panel = p
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p.rows = {}
    p.fill = p:CreateTexture(nil, "BACKGROUND")
    p.fill:SetAllPoints()
    UI.Border(p, 0.15, 0.15, 0.17, 1)
    local title = CreateFrame("Frame", nil, p)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(20)
    p.title = title:CreateTexture(nil, "BORDER")
    p.title:SetAllPoints()
    p.line = title:CreateTexture(nil, "ARTWORK")
    p.line:SetPoint("BOTTOMLEFT")
    p.line:SetPoint("BOTTOMRIGHT")
    p.line:SetHeight(1)
    local close = TitleButton(title, function() DM.CloseBreakdown() end, "Close")
    close:SetPoint("TOPRIGHT", -4, 0)
    close:SetPoint("BOTTOMRIGHT", -4, 0)
    close:SetWidth(16)
    close.text:SetText("x")
    p.closeText = close.text
    p.head = title:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(p.head, "GLOBAL", 11, "OUTLINE")
    p.head:SetPoint("LEFT", 6, 0)
    p.head:SetPoint("RIGHT", close, "LEFT", -4, 0)
    p.head:SetJustifyH("LEFT")
    p.head:SetWordWrap(false)
    p.body = CreateFrame("Frame", nil, p)
    p.body:SetPoint("TOPLEFT", 1, -21)
    p.body:SetPoint("BOTTOMRIGHT", -1, 1)
    p.body:EnableMouseWheel(true)
    p.body:SetScript("OnMouseWheel", function(_, delta)
        p.offset = math.max(0, (p.offset or 0) - delta)
        DM.RefreshBreakdown()
    end)
    p.empty = p.body:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(p.empty, "GLOBAL", 11, "OUTLINE")
    p.empty:SetPoint("TOP", 0, -8)
    p.empty:SetTextColor(0.5, 0.5, 0.5)
    p.offset = 0
    p:Hide()
end

local function LayoutPanel()
    local c = S()
    local p = panel
    p:SetScale(c.scale)
    p:SetSize(c.width, win:GetHeight())
    p:ClearAllPoints()
    local right = (win:GetRight() or 0) + c.width + 4
    local screen = (UIParent:GetRight() or GetScreenWidth and GetScreenWidth() or 1920) * (UIParent:GetEffectiveScale() or 1)
    if right * (win:GetEffectiveScale() or 1) > screen then
        p:SetPoint("TOPRIGHT", win, "TOPLEFT", -2, 0)
    else
        p:SetPoint("TOPLEFT", win, "TOPRIGHT", 2, 0)
    end
    local a = ns.ACCENT
    p.fill:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
    p.title:SetColorTexture(0.08, 0.08, 0.09, math.min(1, c.bgAlpha + 0.15))
    p.line:SetColorTexture(a[1], a[2], a[3], 0.9)
    ns.ApplyFont(p.head, c.font, c.titleSize, c.outline)
    ns.ApplyFont(p.closeText, c.font, c.titleSize, c.outline)
    ns.ApplyFont(p.empty, c.font, c.fontSize, c.outline)
    local tex = ns.TexturePath(c.texture)
    for i = 1, ROW_POOL do
        local r = PanelRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", p.body, "TOPLEFT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetHeight(c.rowHeight)
        r.icon:SetWidth(c.rowHeight)
        r.bar:SetStatusBarTexture(tex)
        r.bg:SetColorTexture(0, 0, 0, 0.35)
        ns.ApplyFont(r.left, c.font, c.fontSize, c.outline)
        ns.ApplyFont(r.right, c.font, c.fontSize, c.outline)
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", 4, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
        r.right:ClearAllPoints()
        r.right:SetPoint("RIGHT", -4, 0)
        if i > Rows() then r:Hide() end
    end
end

function DM.OpenBreakdown(src, name)
    local t = TYPE_BY_KEY[WC().meterType] or TYPES[1]
    if t.threat then return end
    if bd.open and bd.src == src then DM.CloseBreakdown() return end
    local guid, cid = RowIdentity(src)
    bd = { open = true, src = src, guid = guid, cid = cid, name = name, unit = RowUnit(src),
           color = src.classFilename, win = win }
    BuildPanel()
    LayoutPanel()
    panel.offset = 0
    panel:Show()
    DM.RefreshBreakdown()
end

function DM.CloseBreakdown()
    bd = { open = false }
    if panel then panel:Hide() end
end

function DM.RefreshBreakdown()
    if not (bd.open and panel and panel:IsShown()) then return end
    win = bd.win or win
    local c = S()
    local spells, t, why = GetBreakdown()
    local ok = pcall(panel.head.SetFormattedText, panel.head, "%s - %s", bd.name or "?", t.text)
    if not ok then panel.head:SetText(t.text) end
    spells = spells or {}
    local n = #spells
    panel.offset = math.max(0, math.min(panel.offset or 0, n - Rows()))
    -- percent of the whole row, when the numbers are readable
    local sum, plain = 0, true
    for _, sp in ipairs(spells) do
        local a = sp.totalAmount
        if Plain(a) and type(a) == "number" then sum = sum + a else plain = false end
    end
    local max = spells[1] and spells[1].totalAmount
    local col = bd.color and Plain(bd.color) and ns.ClassColor(bd.color)
    local shown = 0
    for i = 1, Rows() do
        local r = PanelRow(i)
        local sp = spells[i + panel.offset]
        if sp then
            shown = shown + 1
            local id = sp.spellID
            local sname, icon = SpellInfo(id)
            r.spellID = id
            r.icon:SetTexture(icon or 134400)          -- question mark
            if sname ~= nil then r.left:SetText(sname)
            elseif sp.creatureName ~= nil then r.left:SetText(sp.creatureName)
            else r.left:SetText("Melee / other") end
            local total = sp.totalAmount
            local txt = Short(total)
            if plain and sum > 0 then
                local okF, s2 = pcall(string.format, "%s  %d%%", txt, math.floor(total / sum * 100 + 0.5))
                if okF then txt = s2 end
            end
            r.right:SetText(txt)
            if max == nil or not pcall(r.bar.SetMinMaxValues, r.bar, 0, max) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, total or 0) then r.bar:SetValue(0) end
            if col and c.colorMode == "CLASS" then r.bar:SetStatusBarColor(col.r, col.g, col.b)
            else BarColor(r.bar, { classFilename = bd.color }) end
            r:Show()
        else
            r.spellID = nil
            r:Hide()
        end
    end
    for i = Rows() + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.empty:SetText(why or "Nothing in this fight")
    panel.empty:SetShown(shown == 0)
end

local function Layout()
    local c = S()
    local w = win
    w:SetScale(c.scale)
    w:SetSize(c.width, 20 + Rows() * (c.rowHeight + c.rowGap) + 2)
    local pt = WC().point
    w:ClearAllPoints()
    w:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    local a = ns.ACCENT
    w.fill:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
    w.title:SetColorTexture(0.08, 0.08, 0.09, math.min(1, c.bgAlpha + 0.15))
    w.line:SetColorTexture(a[1], a[2], a[3], 0.9)
    for _, fs in ipairs({ w.typeText, w.sessionText, w.resetText, w.closeText, w.addB.text }) do
        ns.ApplyFont(fs, c.font, c.titleSize, c.outline)
    end
    w.typeB:SetWidth(math.max(70, c.width * 0.42))
    w.typeText:SetTextColor(1, 1, 1)
    w.sessionText:SetTextColor(a[1], a[2], a[3])
    local tex = ns.TexturePath(c.texture)
    for i = 1, ROW_POOL do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", w.body, "TOPLEFT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetPoint("TOPRIGHT", w.body, "TOPRIGHT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetHeight(c.rowHeight)
        r:SetStatusBarTexture(tex)
        r.bg:SetColorTexture(0, 0, 0, 0.35)
        ns.ApplyFont(r.left, c.font, c.fontSize, c.outline)
        ns.ApplyFont(r.right, c.font, c.fontSize, c.outline)
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", 4, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
        r.right:ClearAllPoints()
        r.right:SetPoint("RIGHT", -4, 0)
        if i > Rows() then r:Hide() end
    end
    ns.ApplyFont(w.empty, c.font, c.fontSize, c.outline)
end


-- a dropdown in the title bar: dark box, text, arrow; opens HUF's list
local function TitleDropdown(parent, items, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.box = b:CreateTexture(nil, "BACKGROUND")
    b.box:SetPoint("TOPLEFT", 0, -3)
    b.box:SetPoint("BOTTOMRIGHT", 0, 3)
    b.box:SetColorTexture(0.13, 0.13, 0.15, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b.box)
    b.hl:SetColorTexture(1, 1, 1, 0.07)
    b.arrow = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.arrow, "GLOBAL", 9, "OUTLINE")
    b.arrow:SetPoint("RIGHT", -4, 0)
    b.arrow:SetText("v")
    b.arrow:SetTextColor(0.65, 0.65, 0.65)
    b.text = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.text, "GLOBAL", 11, "OUTLINE")
    b.text:SetPoint("LEFT", 5, 0)
    b.text:SetPoint("RIGHT", b.arrow, "LEFT", -3, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        GameTooltip:Hide()
        UI.OpenList(self, items(), get(), function(v) set(v) end)
    end)
    -- mouse wheel steps through the list without opening it
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if self.disabled then return end
        local list, cur, idx = items(), get(), nil
        local values = {}
        for _, e in ipairs(list) do if not e.header then values[#values + 1] = e.value end end
        for i, v in ipairs(values) do if v == cur then idx = i end end
        idx = ((idx or 1) - 1 - delta) % #values + 1
        set(values[idx])
    end)
    b:SetScript("OnEnter", function(self)
        if self.disabled then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:SetDisabled(off)
        self.disabled = off
        self.arrow:SetShown(not off)
        self.box:SetShown(not off)
        self:EnableMouse(not off)
    end
    return b
end

TitleButton = function(parent, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    b.text = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.text, "GLOBAL", 11, "OUTLINE")
    b.text:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build(index)
    if wins[index] then win = wins[index] return end
    local w = CreateFrame("Frame", index == 1 and "HUF_DamageMeter" or ("HUF_DamageMeter" .. index), UIParent)
    wins[index] = w
    w.index = index
    win = w
    w:SetFrameStrata("MEDIUM")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w.rows = {}
    w.fill = w:CreateTexture(nil, "BACKGROUND")
    w.fill:SetAllPoints()
    w.border = UI.Border(w, 0.15, 0.15, 0.17, 1)
    -- title bar: meter type (click: next, right-click: back), fight, reset
    local title = CreateFrame("Frame", nil, w)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(20)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if S().locked then return end
        w.dragFrom = { w:GetLeft() or 0, w:GetTop() or 0 }
        w:StartMoving()
    end)
    title:SetScript("OnDragStop", function()
        w:StopMovingOrSizing()
        local from = w.dragFrom
        if not from then return end
        w.dragFrom = nil
        local p = w.cfg.point
        p[3] = math.floor(p[3] + (w:GetLeft() or 0) - from[1] + 0.5)
        p[4] = math.floor(p[4] + (w:GetTop() or 0) - from[2] + 0.5)
        win = w
        Layout()
        if bd.open and bd.win == w then LayoutPanel() end
    end)
    w.title = title:CreateTexture(nil, "BORDER")
    w.title:SetAllPoints()
    w.line = title:CreateTexture(nil, "ARTWORK")
    w.line:SetPoint("BOTTOMLEFT")
    w.line:SetPoint("BOTTOMRIGHT")
    w.line:SetHeight(1)

    local typeB = TitleDropdown(title, function()
        local l = {}
        for _, t in ipairs(TYPES) do l[#l + 1] = { value = t.key, text = t.text } end
        return l
    end, function() return w.cfg.meterType end, function(v)
        w.cfg.meterType = v
        if v == "Threat" and not InCombatLockdown() then w.keepThreat = true end
        w.offset = 0
        DM.Refresh()
    end, "What the meter shows (damage, healing, taken, interrupts, dispels, deaths, threat). Mouse wheel: step through.")
    typeB:SetPoint("TOPLEFT", 3, 0)
    typeB:SetPoint("BOTTOMLEFT", 3, 0)
    typeB:SetWidth(120)
    w.typeB = typeB
    w.typeText = typeB.text

    -- new window
    local add = TitleButton(title, function() DM.AddWindow() end, "New window (up to 5)")
    add:SetPoint("TOPLEFT", typeB, "TOPRIGHT", 3, 0)
    add:SetPoint("BOTTOMLEFT", typeB, "BOTTOMRIGHT", 3, 0)
    add:SetWidth(14)
    add.text:SetText("+")
    w.addB = add
    w.quickLast = add

    -- close (every window but the first)
    local close = TitleButton(title, function() DM.CloseWindow(w.index) end, "Close this window")
    close:SetPoint("TOPRIGHT", -3, 0)
    close:SetPoint("BOTTOMRIGHT", -3, 0)
    close:SetWidth(index > 1 and 14 or 0.1)
    close.text:SetText("x")
    close:SetShown(index > 1)
    w.closeText = close.text

    local reset = TitleButton(title, function()
        UI.Confirm("Reset all damage meter data?", "Reset", function()
            if Available() and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
            for _, o in ipairs(wins) do if o.cfg then o.cfg.session = "CURRENT" end end
            DM.Refresh()
        end)
    end, "Reset all fights")
    reset:SetPoint("TOPRIGHT", close, "TOPLEFT", index > 1 and -2 or 0, 0)
    reset:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT", index > 1 and -2 or 0, 0)
    reset:SetWidth(14)
    reset.text:SetText("R")
    w.resetText = reset.text

    local sessB = TitleDropdown(title, function()
        local l = {}
        for _, e in ipairs(DM.Sessions()) do l[#l + 1] = { value = e.id, text = e.text } end
        return l
    end, function() return w.cfg.session end, function(v)
        w.cfg.session = v
        w.offset = 0
        DM.Refresh()
    end, "Which fight: current, overall or an earlier one. Mouse wheel: step through.")
    sessB:SetPoint("TOPRIGHT", reset, "TOPLEFT", -3, 0)
    sessB:SetPoint("BOTTOMRIGHT", reset, "BOTTOMLEFT", -3, 0)
    sessB:SetPoint("LEFT", w.quickLast, "RIGHT", 4, 0)
    w.sessB = sessB
    w.sessionText = sessB.text

    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", 1, -21)
    w.body:SetPoint("BOTTOMRIGHT", -1, 1)
    w.body:EnableMouseWheel(true)
    w.body:SetScript("OnMouseWheel", function(_, delta)
        w.offset = math.max(0, (w.offset or 0) - delta)
        DM.Refresh()
    end)
    w.empty = w.body:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(w.empty, "GLOBAL", 11, "OUTLINE")
    w.empty:SetPoint("TOP", 0, -8)
    w.empty:SetTextColor(0.5, 0.5, 0.5)
    w.offset = 0
end

---------------------------------------------------------------------------
-- Showing, updating
---------------------------------------------------------------------------
local function WantShown()
    local c = S()
    if not c.enabled or not Available() then return false end
    if c.show == "GROUP" then return IsInGroup() end
    if c.show == "INSTANCE" then return (IsInInstance()) and true or false end
    return true
end

-- threat windows out of combat (option): hidden. One switched to threat out of
-- combat stays until the next fight is over, so it doesn't vanish on the spot.
local function WindowWanted(w)
    local c = S()
    if not (c.hideThreatOOC and w.cfg and w.cfg.meterType == "Threat") then return true end
    if InCombatLockdown() then return true end
    return w.keepThreat and true or false
end

-- out of combat (option): all windows at the set opacity, full while the
-- mouse is over one (checked 10x a second while it matters)
local fader
local function Fade()
    local c = S()
    local dim = c.fadeOOC and not InCombatLockdown()
    for _, w in ipairs(wins) do
        if w:IsShown() then
            local over = w:IsMouseOver() or (bd.open and bd.win == w and panel and panel:IsShown() and panel:IsMouseOver())
            local a = (dim and not over) and c.fadeAlpha or 1
            w:SetAlpha(a)
            if bd.open and bd.win == w and panel then panel:SetAlpha(a) end
        end
    end
    if dim and not fader then
        fader = C_Timer.NewTicker(0.1, Fade)
    elseif not dim and fader then
        fader:Cancel()
        fader = nil
    end
end
DM.Fade = Fade

local function HideAll()
    for _, w in ipairs(wins) do w:Hide() end
    DM.CloseBreakdown()
end

function DM.Apply()
    DM.ApplyBlizzard()
    if not Available() or not WantShown() then HideAll() return end
    local cfgs = DM.EnsureWindows()
    local count = S().windowCount
    for i = 1, count do
        Build(i)
        win.cfg = cfgs[i]
        Layout()
        win.empty:SetText("No data yet")
        win:SetShown(WindowWanted(win))
    end
    for i = count + 1, #wins do wins[i]:Hide() end
    Fade()
    if bd.open then
        if bd.win and bd.win:IsShown() then win = bd.win LayoutPanel() else DM.CloseBreakdown() end
    end
    DM.Refresh()
end

-- refreshes at most 4x a second; the meter sends a lot of updates in combat
local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function()
        pending = false
        DM.Refresh()
    end)
end

ns.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", Soon)
ns.On("DAMAGE_METER_CURRENT_SESSION_UPDATED", Soon)
ns.On("DAMAGE_METER_RESET", function()
    for _, w in ipairs(wins) do if w.cfg then w.cfg.session = "CURRENT" end end
    Soon()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if cvarPending then DM.ApplyBlizzard() end
    C_Timer.After(0.5, function() Learn() DM.Refresh() end)
end)
-- threat view: the game's threat events, and twice a second in combat
local function ThreatSoon()
    for _, w in ipairs(wins) do
        if w:IsShown() and w.cfg and (TYPE_BY_KEY[w.cfg.meterType] or TYPES[1]).threat then Soon() return end
    end
end
ns.On("UNIT_THREAT_LIST_UPDATE", ThreatSoon)
ns.On("UNIT_THREAT_SITUATION_UPDATE", ThreatSoon)
ns.On("PLAYER_TARGET_CHANGED", ThreatSoon)
ns.On("UNIT_TARGET", function(u) if u == "target" then ThreatSoon() end end)
local ticker
ns.On("PLAYER_REGEN_DISABLED", function()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.5, ThreatSoon)
    if S().enabled then DM.Apply() end         -- threat windows back, full opacity
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if ticker then ticker:Cancel() ticker = nil end
    for _, w in ipairs(wins) do w.keepThreat = nil end
    if S().enabled then DM.Apply() end         -- threat windows away, dimmed
    ThreatSoon()
end)
ns.On("GROUP_ROSTER_UPDATE", function() RebuildRoster() DM.Apply() end)
ns.On("PLAYER_ENTERING_WORLD", function() RebuildRoster() Learn() DM.Apply() end)
ns.On("ZONE_CHANGED_NEW_AREA", function() DM.Apply() end)
ns.OnLogin(function() RebuildRoster() DM.Apply() end)
ns.OnRefresh(function() if HUFDB then DM.Apply() end end)

function DM.AddWindow()
    local c = S()
    if c.windowCount >= MAX_WINDOWS then return end
    c.windowCount = c.windowCount + 1
    DM.EnsureWindows()
    local w = c.windows[c.windowCount]
    w.keep = true
    DM.Apply()
    local nw = wins[c.windowCount]
    if nw and w.meterType == "Threat" then nw.keepThreat = true nw:Show() end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- closes window i (not the first): its settings go, the ones after move up
function DM.CloseWindow(i)
    local c = S()
    if i <= 1 or i > c.windowCount then return end
    if bd.open and bd.win == wins[i] then DM.CloseBreakdown() end
    table.remove(c.windows, i)
    c.windowCount = c.windowCount - 1
    for _, w in ipairs(wins) do w.keepThreat = nil end
    DM.Apply()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

function DM.Toggle()
    S().enabled = not S().enabled
    DM.Apply()
    ns.Print("Damage meter %s.", S().enabled and "on" or "off")
end

-- debug report: what the meter hands out right now
function DM.Report(add)
    local c = S()
    add(("damage meter: available=%s enabled=%s windows=%s blizzard cvar=%s saved=%s"):format(
        tostring(Available()), tostring(c.enabled), tostring(c.windowCount),
        tostring(GetCV("damageMeterEnabled")), tostring(HUFDB.damageMeterCVar and HUFDB.damageMeterCVar.old)))
    for i, w in ipairs(wins) do
        add(("  window %d: shown=%s type=%s session=%s"):format(i, tostring(w:IsShown()),
            tostring(w.cfg and w.cfg.meterType), tostring(w.cfg and w.cfg.session)))
    end
    win = wins[1]
    if not win or not win.cfg then return end
    local session = GetSession()
    local srcs = session and session.combatSources
    if type(srcs) ~= "table" then return end
    local function V(v) if IsSecret(v) then return "SECRET" end return tostring(v) end
    for i = 1, math.min(#srcs, 6) do
        local s = srcs[i]
        local shown, how = DM.RowName(s)
        add(("  %d: name=%s guid=%s class=%s spec=%s me=%s creature=%s total=%s ps=%s -> %s (%s)"):format(i,
            V(s.name), V(s.sourceGUID), V(s.classFilename), V(s.specIconID), V(s.isLocalPlayer),
            V(s.sourceCreatureID), V(s.totalAmount), V(s.amountPerSecond), IsSecret(shown) and "SECRET" or tostring(shown), how))
    end
end
