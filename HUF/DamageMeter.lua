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

local roster = { byGUID = {}, byName = {}, byClass = {} }   -- rebuilt on roster changes
local specGUID = {}      -- "HUNTER:132215" -> guid (false: two members share it)

local function RebuildRoster()
    roster = { byGUID = {}, byName = {}, byClass = {} }
    for _, u in ipairs(GroupUnits()) do
        local okG, g = pcall(UnitGUID, u)
        if okG and Plain(g) then roster.byGUID[g] = u end
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
local function Short(v)
    if v == nil then return "" end
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok and s ~= nil then return s end
    end
    local ok, s = pcall(string.format, "%d", v)
    return ok and s or ""
end

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
local win
local ROW_POOL = 40

local function SessionLabel()
    local c = S()
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
    local c = S()
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
    win.rows[i] = r
    return r
end

function DM.Refresh()
    if not win or not win:IsShown() then return end
    local c = S()
    local session, t = GetSession()
    t = t or TYPES[1]
    win.typeText:SetText(t.text)
    win.sessionText:SetText(SessionLabel())
    local sources = session and session.combatSources or {}
    local n = #sources
    if t.threat then
        win.sessionText:SetText(session and session.title or "")
        win.empty:SetText(session and session.empty or "No threat yet")
    else
        win.empty:SetText("No data yet")
    end
    for k, b in pairs(win.quick or {}) do
        local a = ns.ACCENT
        if k == c.meterType then b.text:SetTextColor(a[1], a[2], a[3]) else b.text:SetTextColor(0.6, 0.6, 0.6) end
    end
    win.offset = math.max(0, math.min(win.offset or 0, n - c.rows))
    local maxAmount = sources[1] and sources[1].totalAmount
    local shown = 0
    for i = 1, c.rows do
        local r = Row(i)
        local src = sources[i + win.offset]
        if src then
            shown = shown + 1
            local rank = i + win.offset
            local name = DM.RowName(src)
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
            r:Hide()
        end
    end
    for i = c.rows + 1, #win.rows do win.rows[i]:Hide() end
    win.empty:SetShown(shown == 0)
end

local function Layout()
    local c = S()
    local w = win
    w:SetScale(c.scale)
    w:SetSize(c.width, 20 + c.rows * (c.rowHeight + c.rowGap) + 2)
    w:ClearAllPoints()
    w:SetPoint(c.point[1], UIParent, c.point[2], c.point[3], c.point[4])
    local a = ns.ACCENT
    w.fill:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
    w.title:SetColorTexture(0.08, 0.08, 0.09, math.min(1, c.bgAlpha + 0.15))
    w.line:SetColorTexture(a[1], a[2], a[3], 0.9)
    for _, fs in ipairs({ w.typeText, w.sessionText, w.resetText }) do
        ns.ApplyFont(fs, c.font, c.titleSize, c.outline)
    end
    for _, b in pairs(w.quick) do ns.ApplyFont(b.text, c.font, c.titleSize, c.outline) end
    w.typeText:GetParent():SetWidth(math.max(60, c.width * 0.42))
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
        if i > c.rows then r:Hide() end
    end
    ns.ApplyFont(w.empty, c.font, c.fontSize, c.outline)
end

local function Cycle(list, cur, step)
    local idx = 1
    for i, e in ipairs(list) do if e == cur then idx = i end end
    idx = (idx - 1 + step) % #list + 1
    return list[idx]
end

local function TitleButton(parent, onClick, tip)
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

local function Build()
    if win then return end
    local w = CreateFrame("Frame", "HUF_DamageMeter", UIParent)
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
        local p = S().point
        p[3] = math.floor(p[3] + (w:GetLeft() or 0) - from[1] + 0.5)
        p[4] = math.floor(p[4] + (w:GetTop() or 0) - from[2] + 0.5)
        Layout()
    end)
    w.title = title:CreateTexture(nil, "BORDER")
    w.title:SetAllPoints()
    w.line = title:CreateTexture(nil, "ARTWORK")
    w.line:SetPoint("BOTTOMLEFT")
    w.line:SetPoint("BOTTOMRIGHT")
    w.line:SetHeight(1)

    local keys = {}
    for _, t in ipairs(TYPES) do keys[#keys + 1] = t.key end
    local typeB = TitleButton(title, function(_, button)
        S().meterType = Cycle(keys, S().meterType, button == "RightButton" and -1 or 1)
        w.offset = 0
        DM.Refresh()
    end, "Click: next list, right-click: previous (damage, healing, taken, interrupts, dispels, deaths)")
    typeB:SetPoint("TOPLEFT", 6, 0)
    typeB:SetPoint("BOTTOMLEFT", 6, 0)
    typeB:SetWidth(120)
    typeB.text:SetJustifyH("LEFT")
    w.typeText = typeB.text

    -- quick switches: damage, healing, threat
    w.quick = {}
    local prev
    for _, q in ipairs({ { "DamageDone", "D", "Damage done" }, { "HealingDone", "H", "Healing done" }, { "Threat", "T", "Threat on your enemy" } }) do
        local b = TitleButton(title, function()
            S().meterType = q[1]
            w.offset = 0
            DM.Refresh()
        end, q[3])
        b:SetWidth(14)
        b.text:SetText(q[2])
        w.quick[q[1]] = b
        if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0) b:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 2, 0)
        else b:SetPoint("TOPLEFT", typeB, "TOPRIGHT", 4, 0) b:SetPoint("BOTTOMLEFT", typeB, "BOTTOMRIGHT", 4, 0) end
        prev = b
    end
    w.quickLast = prev

    local reset = TitleButton(title, function()
        UI.Confirm("Reset all damage meter data?", "Reset", function()
            if Available() and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
            S().session = "CURRENT"
            DM.Refresh()
        end)
    end, "Reset all fights")
    reset:SetPoint("TOPRIGHT", -4, 0)
    reset:SetPoint("BOTTOMRIGHT", -4, 0)
    reset:SetWidth(16)
    reset.text:SetText("x")
    w.resetText = reset.text

    local sessB = TitleButton(title, function(_, button)
        local ids = {}
        for _, e in ipairs(DM.Sessions()) do ids[#ids + 1] = e.id end
        S().session = Cycle(ids, S().session, button == "RightButton" and -1 or 1)
        w.offset = 0
        DM.Refresh()
    end, "Click: next fight, right-click: previous (current, overall, earlier fights)")
    sessB:SetPoint("TOPRIGHT", reset, "TOPLEFT", -4, 0)
    sessB:SetPoint("BOTTOMRIGHT", reset, "BOTTOMLEFT", -4, 0)
    sessB:SetPoint("LEFT", w.quickLast, "RIGHT", 4, 0)
    sessB.text:SetJustifyH("RIGHT")
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

function DM.Apply()
    DM.ApplyBlizzard()
    if not Available() then
        if win then win:Hide() end
        return
    end
    if not WantShown() then
        if win then win:Hide() end
        return
    end
    Build()
    Layout()
    win.empty:SetText("No data yet")
    win:Show()
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
ns.On("DAMAGE_METER_RESET", function() S().session = "CURRENT" Soon() end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if cvarPending then DM.ApplyBlizzard() end
    C_Timer.After(0.5, function() Learn() DM.Refresh() end)
end)
-- threat view: the game's threat events, and twice a second in combat
local function ThreatSoon()
    if (TYPE_BY_KEY[S().meterType] or TYPES[1]).threat then Soon() end
end
ns.On("UNIT_THREAT_LIST_UPDATE", ThreatSoon)
ns.On("UNIT_THREAT_SITUATION_UPDATE", ThreatSoon)
ns.On("PLAYER_TARGET_CHANGED", ThreatSoon)
ns.On("UNIT_TARGET", function(u) if u == "target" then ThreatSoon() end end)
local ticker
ns.On("PLAYER_REGEN_DISABLED", function()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.5, ThreatSoon)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if ticker then ticker:Cancel() ticker = nil end
    ThreatSoon()
end)
ns.On("GROUP_ROSTER_UPDATE", function() RebuildRoster() DM.Apply() end)
ns.On("PLAYER_ENTERING_WORLD", function() RebuildRoster() Learn() DM.Apply() end)
ns.On("ZONE_CHANGED_NEW_AREA", function() DM.Apply() end)
ns.OnLogin(function() RebuildRoster() DM.Apply() end)
ns.OnRefresh(function() if HUFDB then DM.Apply() end end)

function DM.Toggle()
    S().enabled = not S().enabled
    DM.Apply()
    ns.Print("Damage meter %s.", S().enabled and "on" or "off")
end

-- debug report: what the meter hands out right now
function DM.Report(add)
    local c = S()
    add(("damage meter: available=%s enabled=%s shown=%s type=%s session=%s blizzard cvar=%s saved=%s"):format(
        tostring(Available()), tostring(c.enabled), tostring(win and win:IsShown()), tostring(c.meterType),
        tostring(c.session), tostring(GetCV("damageMeterEnabled")), tostring(HUFDB.damageMeterCVar and HUFDB.damageMeterCVar.old)))
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
