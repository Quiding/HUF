-- HUF: buff and debuff icon rows, for the unit frames and the nameplates.
--
-- 12.x: the game's own aura containers (Blizzard_AuraContainer) do the work
-- when the client has them. They read the auras in C, so they keep working
-- where an addon may not read auras itself (nameplates, party, combat). Each
-- row holds two groups with fixed filters ("all" and "mine"); the one not in
-- use is parked at 0 icons. Without containers a row falls back to a plain
-- C_UnitAuras scan, and every failure of that scan goes to the debug log.

local _, ns = ...
local A = {}
ns.Auras = A

local floor = math.floor

---------------------------------------------------------------------------
-- Does the client have aura containers?
---------------------------------------------------------------------------
local engine, spare
local function Engine()
    if engine ~= nil then return engine end
    engine = false
    if C_AddOns and C_AddOns.LoadAddOn then
        local loaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
        if not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and c and c.AddAuraGroup and c.SetUnit then
        engine = true
        c:Hide()
        spare = c
    end
    ns.Log("auras", "game aura containers: %s%s", engine and "yes" or "no (plain scan)",
        ok and "" or (" - " .. tostring(c)))
    return engine
end
A.Engine = Engine

-- are auras hidden from addons right now?
function A.Restricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and ns.Bool(r) then return true end
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
    return not pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
end

local function Filter(kind, mine) return mine and (kind .. "|PLAYER") or kind end
A.Filter = Filter

-- What a row shows: the game's own aura filters, so they also work while
-- the auras are hidden from addons. A row has up to three groups that fill
-- one after another: "lead" (crowd control first), "main" and "extra" (a
-- second filter, made not to repeat the first).
--   cfg.filter: debuffs ALL | RAID | DISPELLABLE | CC
--               buffs   ALL | RAID | DEFENSIVE | CANCELABLE
--   cfg.ccFirst (debuffs): crowd control leads the row
--   cfg.hideSated (debuffs): no Sated / Exhaustion and the like
A.SLOTS = { "lead", "main", "extra" }
-- the game's own tokens: "dispellable by anyone" (purges, enrages; whatever
-- your class) and "important". Checked by the game, so they also work on
-- enemies whose buffs addons may not read.
local AF = AuraUtil and AuraUtil.AuraFilters
local DISPELLABLE = (AF and AF.Dispellable) or "DISPELLABLE"
local IMPORTANT = (AF and AF.Important) or "IMPORTANT"
local function SortKey(t) if t:sub(1, 1) == "!" then return t:sub(2) .. "!" end return t end
-- one spelling per filter (the game reads each spelling once per unit)
local function Make(base, mine, ...)
    local rest = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then rest[#rest + 1] = t end
    end
    if mine then rest[#rest + 1] = "PLAYER" end
    table.sort(rest, function(a, b) return SortKey(a) < SortKey(b) end)
    if #rest == 0 then return base end
    return base .. "|" .. table.concat(rest, "|")
end
-- the automatic choices: "my group" when the group is your MMT team, else
-- "me" (AUTO_TEAM: debuffs my group / I can dispel; AUTO_PURGE: buffs my
-- group / I can purge)
local function GroupIsTeam()
    return ns.Bridge and ns.Bridge.GroupIsTeam and ns.Bridge.GroupIsTeam() or false
end
local lastIsTeam
local function Eff(cfg)
    local f = cfg.filter or "ALL"
    if f == "AUTO_TEAM" then
        if lastIsTeam == nil then lastIsTeam = GroupIsTeam() end
        return lastIsTeam and "TEAM" or "DISPELLABLE"
    elseif f == "AUTO_PURGE" then
        if lastIsTeam == nil then lastIsTeam = GroupIsTeam() end
        return lastIsTeam and "TEAM_PURGE" or "MINE_PURGE"
    end
    return f
end
A.Eff = Eff
-- rows that change when the group (or who of it can dispel / purge) does
local GROUP_FILTERS = { TEAM = true, TEAM_PURGE = true, AUTO_TEAM = true, AUTO_PURGE = true }

function A.Groups(cfg)
    local base, mine, f = cfg.kind, cfg.mine and true or false, Eff(cfg)
    local g = {}
    if base == "HARMFUL" then
        local lead = cfg.ccFirst and not mine and f ~= "CC"
        local nc = lead and "!CROWD_CONTROL" or nil
        if lead then g.lead = Make(base, false, "CROWD_CONTROL") end
        if f == "RAID" then
            g.main = Make(base, mine, "RAID", nc)
            g.extra = Make(base, mine, "RAID_IN_COMBAT", "!RAID", nc)
        elseif f == "DISPELLABLE" then
            g.main = Make(base, mine, "RAID_PLAYER_DISPELLABLE", nc)
        elseif f == "CC" then
            g.main = Make(base, mine, "CROWD_CONTROL")
        else
            g.main = Make(base, mine, nc)
        end
    else
        if f == "RAID" then
            g.main = Make(base, mine, "RAID")
        elseif f == "DEFENSIVE" then
            g.main = Make(base, mine, "BIG_DEFENSIVE")
            g.extra = Make(base, mine, "EXTERNAL_DEFENSIVE", "!BIG_DEFENSIVE")
        elseif f == "CANCELABLE" then
            g.main = Make(base, mine, "CANCELABLE")
        elseif f == "PURGE" or f == "TEAM_PURGE" or f == "MINE_PURGE" then
            -- enemies: the ones you (or anyone) can dispel or steal;
            -- TEAM_PURGE: of the types your group can remove (see below)
            g.main = Make(base, mine, DISPELLABLE)
        elseif f == "IMPORTANT_PURGE" then
            g.main = Make(base, mine, DISPELLABLE)
            g.extra = Make(base, mine, IMPORTANT, "!" .. DISPELLABLE)
        else
            g.main = Make(base, mine)
        end
    end
    return g
end

-- Sated, Exhaustion, Temporal Displacement, Insanity, Fatigued and kin
local SATED = { [57723] = true, [57724] = true, [80354] = true, [95809] = true,
                [160455] = true, [264689] = true, [390435] = true }
local SATED_CAND = { excludeSpellIDs = SATED }

---------------------------------------------------------------------------
-- "Ones my group can dispel" (filter TEAM): the debuff types anyone in the
-- group can remove - with MMT that is your whole team, not just the
-- character you play. Read from each member's class, and for the types
-- only healers remove (magic), from the role they have. The game then shows
-- only debuffs of those types (its own type filter: works in combat too).
---------------------------------------------------------------------------
local CLASS_DISPELS = {
    PRIEST  = { all = { "Disease" }, healer = { "Magic" } },
    PALADIN = { all = { "Poison", "Disease" }, healer = { "Magic" } },
    SHAMAN  = { all = { "Curse" }, healer = { "Magic" } },
    DRUID   = { all = { "Curse", "Poison" }, healer = { "Magic" } },
    MONK    = { all = { "Poison", "Disease" }, healer = { "Magic" } },
    EVOKER  = { all = { "Poison" }, healer = { "Magic" } },
    MAGE    = { all = { "Curse" } },
}
A.CLASS_DISPELS = CLASS_DISPELS
local TYPE_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }
local teamTypes, teamKey = {}, ""
local teamCand, teamCandSated

-- "Ones my group can purge or steal" (enemy buffs, filter TEAM_PURGE): who
-- has a spell that takes a buff off an enemy, from class and level (the
-- level the spell is learnt at); for your own character from your
-- spellbook. Warlocks count with a Felhunter out.
local PURGES = {
    SHAMAN  = { { id = 370, level = 12, types = { "Magic" } } },          -- Purge
    PRIEST  = { { id = 527, level = 18, types = { "Magic" } } },          -- Dispel Magic
    WARLOCK = { { id = 19505, level = 30, types = { "Magic" }, pet = true } }, -- Devour Magic
    HUNTER  = { { id = 19801, level = 60, types = { "Enrage" } } },       -- Tranquilizing Shot
    MAGE    = { { id = 30449, level = 70, types = { "Magic" } } },        -- Spellsteal
}
A.PURGES = PURGES
local purgeTypes, purgeKey = {}, ""
local purgeCand
local minePurgeTypes, minePurgeKey, minePurgeCand = {}, "", nil

local function Plain(v) if v == nil or ns.IsSecret(v) then return nil end return v end
-- the role of a member's spec, as far as the game knows it (others: once
-- inspected). Their group role is no help: a group made by hand, like an
-- MMT team, often has everyone as damage, healers too.
local function SpecRole(unit)
    if unit == "player" then
        if not (GetSpecialization and GetSpecializationRole) then return nil end
        local okS, spec = pcall(GetSpecialization)
        spec = okS and Plain(spec) or nil
        if not spec then return nil end
        local okR, r = pcall(GetSpecializationRole, spec)
        return okR and Plain(r) or nil
    end
    if not (GetInspectSpecialization and GetSpecializationRoleByID) then return nil end
    local okS, id = pcall(GetInspectSpecialization, unit)
    id = okS and Plain(id) or nil
    if not id or id == 0 then return nil end
    local okR, r = pcall(GetSpecializationRoleByID, id)
    return okR and Plain(r) or nil
end
local unknownSpec = {}      -- members whose spec isn't known yet
local function UnitHeals(unit)
    local role = SpecRole(unit)
    if role then return role == "HEALER" end
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if ok and Plain(r) == "HEALER" then return true end
    -- spec not known yet: they might heal, so count it, and ask the game
    if unit ~= "player" then unknownSpec[#unknownSpec + 1] = unit end
    return true
end

-- inspect one member whose spec isn't known (the game answers with
-- INSPECT_READY, which reads the group again); out of combat only, never
-- while you have the inspect window open, a few tries per member
local inspectTries, inspectBusy = {}, false
local function InspectNext()
    if inspectBusy or #unknownSpec == 0 or not NotifyInspect then return end
    if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return end
    for _, unit in ipairs(unknownSpec) do
        local okG, guid = pcall(UnitGUID, unit)
        guid = okG and Plain(guid) or nil
        local okC, can = pcall(CanInspect, unit)
        if guid and okC and Plain(can) and (inspectTries[guid] or 0) < 5 then
            inspectTries[guid] = (inspectTries[guid] or 0) + 1
            inspectBusy = true
            pcall(NotifyInspect, unit)
            C_Timer.After(3, function() inspectBusy = false end)
            return
        end
    end
end

local function Known(id, pet)
    if pet then
        if not IsSpellKnown then return nil end
        local ok, k = pcall(IsSpellKnown, id, true)
        return ok and Plain(k) or nil
    end
    local fn = IsPlayerSpell or IsSpellKnown
    if not fn then return nil end
    local ok, k = pcall(fn, id)
    return ok and Plain(k) or nil
end
local function PetOf(unit)
    if unit == "player" then return "pet" end
    local kind, n = unit:match("^(%a+)(%d+)$")
    return kind and (kind .. "pet" .. n) or nil
end
-- a Felhunter out (English name; a pet whose family can't be read counts)
local function HasFelhunter(unit)
    local pu = PetOf(unit)
    local okE, ex = pcall(UnitExists, pu or "none")
    if not (pu and okE and Plain(ex)) then return false end
    local okF, fam = pcall(UnitCreatureFamily, pu)
    fam = okF and Plain(fam) or nil
    return fam == nil or fam == "Felhunter"
end
local function CanPurge(unit, class, p)
    if unit == "player" then
        local k = Known(p.id, p.pet)
        if k ~= nil then return k end
    end
    local okL, lv = pcall(UnitLevel, unit)
    lv = okL and Plain(lv) or nil
    if lv and lv > 0 and lv < p.level then return false end
    if p.pet then return HasFelhunter(unit) end
    return true
end

local function GroupUnits()
    local list = { "player" }
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if raid then
        for i = 1, n do list[#list + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do list[#list + 1] = "party" .. i end
    end
    return list
end

-- works out the types again; true when they changed
local function ReadTeam()
    local set, pset, mset = {}, {}, {}
    wipe(unknownSpec)
    for _, unit in ipairs(GroupUnits()) do
        local okE, exists = pcall(UnitExists, unit)
        if okE and Plain(exists) then
            local okC, _, class = pcall(UnitClass, unit)
            class = okC and Plain(class) or nil
            local d = class and CLASS_DISPELS[class]
            if d then
                for _, t in ipairs(d.all or {}) do set[t] = true end
                if d.healer and UnitHeals(unit) then
                    for _, t in ipairs(d.healer) do set[t] = true end
                end
            end
            for _, p in ipairs(class and PURGES[class] or {}) do
                if CanPurge(unit, class, p) then
                    for _, t in ipairs(p.types) do
                        pset[t] = true
                        if unit == "player" then mset[t] = true end
                    end
                end
            end
        end
    end
    local key = {}
    for _, t in ipairs(TYPE_ORDER) do if set[t] then key[#key + 1] = t end end
    key = table.concat(key, ",")
    local pkey = {}
    for _, t in ipairs(TYPE_ORDER) do if pset[t] then pkey[#pkey + 1] = t end end
    pkey = table.concat(pkey, ",")
    local mkey = {}
    for _, t in ipairs(TYPE_ORDER) do if mset[t] then mkey[#mkey + 1] = t end end
    mkey = table.concat(mkey, ",")
    local isTeam = GroupIsTeam()
    if key == teamKey and pkey == purgeKey and mkey == minePurgeKey and isTeam == lastIsTeam and teamCand then
        return false
    end
    lastIsTeam = isTeam
    minePurgeKey, minePurgeTypes = mkey, mset
    minePurgeCand = { includeDispelTypes = mset }
    teamKey, teamTypes = key, set
    teamCand = { includeDispelTypes = set }
    teamCandSated = { includeDispelTypes = set, excludeSpellIDs = SATED }
    purgeKey, purgeTypes = pkey, pset
    purgeCand = { includeDispelTypes = pset }
    return true
end
function A.TeamTypes()
    if not teamCand then ReadTeam() end
    return teamKey
end

-- the candidate filter of a group slot ("lead": crowd control keeps every type)
local function Cand(cfg, key)
    local f = Eff(cfg)
    if cfg.kind ~= "HARMFUL" then
        if f ~= "TEAM_PURGE" and f ~= "MINE_PURGE" then return nil end
        if not teamCand then ReadTeam() end
        return f == "TEAM_PURGE" and purgeCand or minePurgeCand
    end
    if f == "TEAM" and key ~= "lead" then
        if not teamCand then ReadTeam() end
        return cfg.hideSated and teamCandSated or teamCand
    end
    if cfg.hideSated then return SATED_CAND end
    return nil
end
-- the group can dispel nothing: the TEAM row shows nothing
local function TeamEmpty(cfg)
    local f = Eff(cfg)
    if cfg.kind == "HELPFUL" and (f == "TEAM_PURGE" or f == "MINE_PURGE") then
        if not teamCand then ReadTeam() end
        return (f == "TEAM_PURGE" and purgeKey or minePurgeKey) == ""
    end
    if cfg.kind ~= "HARMFUL" or f ~= "TEAM" then return false end
    if not teamCand then ReadTeam() end
    return teamKey == ""
end

-- a debuff's border in its type's colour (magic blue, curse purple, ...)
-- false, "EDGE" (a ring in the type's colour) or "GLOW".
-- cfg.purge (buff filters PURGE / TEAM_PURGE / IMPORTANT_PURGE): the slot
-- "main" holds only buffs that can be removed. Every icon there gets the
-- mark from HUF itself ("EDGE_ALL": magic blue, "GLOW_ALL": the golden
-- glow), and can be bigger (cfg.purgeSize, percent).
local function Removable(cfg, key)
    return cfg.purge and (key == nil or key == "main") or false
end
local function WantDispel(cfg, key)
    local v = cfg.dispelBorder
    -- debuffs (cfg.glowAll): the golden glow on every dispellable one, the
    -- type edge kept when it is on ("EDGE_GLOW")
    if cfg.glowAll and Removable(cfg, key) then
        return v and "EDGE_GLOW" or "GLOW_ALL"
    end
    if not v then return false end
    v = v == "GLOW" and "GLOW" or "EDGE"
    return Removable(cfg, key) and (v .. "_ALL") or v
end
local function SlotSize(cfg, key)
    if not Removable(cfg, key) then return cfg.size end
    return math.floor(cfg.size * (cfg.purgeSize or 100) / 100 + 0.5)
end
-- a button's width and height (cfg.highlight: one button round the frame)
local function ButtonWH(cfg, key)
    if cfg.highlight then return cfg.width, cfg.height end
    local s = SlotSize(cfg, key)
    return s, s
end
local function BorderSize(cfg) return math.max(0, cfg.borderSize or 1) end
local DISPEL_COLORS = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 }, Bleed = { 0.8, 0, 0 }, Enrage = { 1, 0.3, 0.1 },
}
local dispelStyle
local function DispelOpts()
    if dispelStyle == nil then
        local E = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        local s = E and E.PreserveAsset
        if s == nil then
            local L = (Enum and Enum.CustomAuraButtonBorderStyle) or _G.AuraButtonBorderStyle
            s = L and L.Color
        end
        dispelStyle = s ~= nil and { style = s, showWhenHarmful = true, showWhenHelpful = true } or false
    end
    return dispelStyle or nil
end

local function Flow(token)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if not FD then return nil end
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-- the layout setters were renamed once; old names as fallback
local function Call(c, new, old, ...)
    local fn = c[new] or (old and c[old])
    if fn then return pcall(fn, c, ...) end
    return false, "no " .. new
end

---------------------------------------------------------------------------
-- A row
--   cfg: enabled, kind ("HARMFUL" / "HELPFUL"), mine, size, gap, perRow,
--        rows, point {point, rel, relPoint, x, y}, anchor (= point[1]),
--        growH ("LEFT"/"RIGHT"), growV ("UP"/"DOWN"), countSize, timer,
--        timerText (time left as numbers), timerSize (0: from the icon size)
---------------------------------------------------------------------------
local Row = {}
Row.__index = Row
local rows = {}

function A.NewRow(parent, label, plate)
    local r = setmetatable({
        parent = parent, label = label, plate = plate,
        buttons = {}, bdata = {}, icons = {}, errors = 0,
    }, Row)
    r.holder = CreateFrame("Frame", nil, parent)
    r.holder:SetSize(1, 1)
    r.holder:EnableMouse(false)
    r.ev = CreateFrame("Frame")
    r.ev:SetScript("OnEvent", function() r:Scan() end)
    rows[#rows + 1] = r
    return r
end

function Row:Fail(what, err)
    self.errors = self.errors + 1
    self.lastErr = what .. ": " .. tostring(err)
    if self.errors <= 3 then
        ns.Log("auras", "%s: %s failed: %s", self.label, what, tostring(err))
    end
end

-- time left as numbers: the cooldown's own countdown (the game counts it,
-- so it also works while the aura's times are secret)
local function TimerSize(cfg)
    local s = cfg.timerSize or 0
    if s > 0 then return s end
    return math.max(7, math.floor((cfg.size or 20) * 0.5 + 0.5))
end
local function StyleTimer(cd, cfg)
    cd:SetHideCountdownNumbers(not cfg.timerText)
    if cd.SetCountdownAbbrevThreshold then pcall(cd.SetCountdownAbbrevThreshold, cd, 100) end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        ns.ApplyFont(fs, "GLOBAL", TimerSize(cfg), "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 0)
    end
end

-- The golden proc glow round an icon: the action bars' flipbook (30 frames,
-- 5 x 6), the one a spell gets when it lights up. On the game's aura
-- buttons addon code may not hook or move anything while they show, so the
-- animation is handed to the button (AddAuraShownAnimation): the game plays
-- it while the aura is shown. The art only shows while it plays.
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local function MakeProc(b)
    local f = CreateFrame("Frame", nil, b)
    f:SetPoint("CENTER")
    f:EnableMouse(false)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetAtlas(PROC_ATLAS)
    t:SetAlpha(0)
    local g = t:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    local flip = g:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(6)
    flip:SetFlipBookColumns(5)
    flip:SetFlipBookFrames(30)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    flip:SetDuration(1)
    local on = g:CreateAnimation("Alpha")
    on:SetFromAlpha(1)
    on:SetToAlpha(1)
    on:SetDuration(1)
    f:Hide()
    return f, g
end
-- the art's glow reaches ~ 1.4 x the icon
local function ProcSize(d, size)
    if not d.proc then return end
    local s = (size or 20) * (d.glowScale or 140) / 100
    pcall(d.proc.SetSize, d.proc, s, s)
end
local function ProcShow(d, on)
    if not d.proc then return end
    pcall(on and d.proc.Show or d.proc.Hide, d.proc)
end

-- the type look for scan and preview icons (no game button to tint them)
local function ShowType(d, look, col)
    if look == "EDGE_GLOW" then
        -- the type's edge and the glow
        if col then
            d.ring:SetColorTexture(col[1], col[2], col[3], 1)
            d.ring:Show()
        else
            d.ring:Hide()
        end
        if d.proc then
            ProcShow(d, true)
            if not d.procAnim:IsPlaying() then d.procAnim:Play() end
        end
        return
    end
    if look == "GLOW_ALL" or look == "EDGE_ALL" then
        col = col or DISPEL_COLORS.Magic
        look = look == "GLOW_ALL" and "GLOW" or "EDGE"
    end
    if col and look == "GLOW" and d.proc then
        d.ring:Hide()
        ProcShow(d, true)
        if not d.procAnim:IsPlaying() then d.procAnim:Play() end
    elseif col then
        if d.proc then d.procAnim:Stop() ProcShow(d, false) end
        d.ring:SetColorTexture(col[1], col[2], col[3], 1)
        d.ring:Show()
    else
        if d.proc then d.procAnim:Stop() ProcShow(d, false) end
        d.ring:Hide()
    end
end

-- icon look shared by engine buttons and scan icons
local function Dress(b, cfg, top)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    -- the debuff type's colour over the black edge (the game shows and tints it)
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetAllPoints()
    ring:SetColorTexture(1, 1, 1, 1)
    ring:Hide()
    local icon = b:CreateTexture(nil, "ARTWORK")
    local bs = BorderSize(cfg)
    icon:SetPoint("TOPLEFT", bs, -bs)
    icon:SetPoint("BOTTOMRIGHT", -bs, bs)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(cd, cfg)
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(cd:GetFrameLevel() + 2)
    over:EnableMouse(false)
    local count = over:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(count, "GLOBAL", cfg.countSize or 9, "OUTLINE")   -- a font before any text
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    count:SetJustifyH("RIGHT")
    -- frame edge (cfg.highlight): no icon, four edges the game colours by
    -- the debuff's type
    local edges
    if cfg.highlight then
        bg:Hide()
        icon:SetAlpha(0)
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        cd:SetAlpha(0)
        edges = {}
        for i = 1, 4 do
            edges[i] = b:CreateTexture(nil, "OVERLAY")
            edges[i]:SetColorTexture(1, 1, 1, 1)
            edges[i]:Hide()
        end
    end
    -- the golden glow, above the icon and its timer
    local okP, proc, procAnim
    if not cfg.highlight then okP, proc, procAnim = pcall(MakeProc, b) end
    if okP then
        pcall(proc.SetFrameLevel, proc, over:GetFrameLevel() + 1)
    else
        if proc then A.glowErr = tostring(proc) end
        proc, procAnim = nil, nil
    end
    local d = { icon = icon, cd = cd, count = count, ring = ring, border = bs,
                proc = proc, procAnim = procAnim, edges = edges,
                timerText = cfg.timerText, timerSize = TimerSize(cfg) }
    ProcSize(d, cfg.size)
    return d
end

-- the frame edge's four sides, e thick, inside the button (which is the
-- frame plus e all round)
local function EdgePoints(d, e)
    local t = d.edges
    if not t then return end
    e = math.max(1, e or 2)
    for i = 1, 4 do t[i]:ClearAllPoints() end
    t[1]:SetPoint("TOPLEFT") t[1]:SetPoint("TOPRIGHT") t[1]:SetHeight(e)
    t[2]:SetPoint("BOTTOMLEFT") t[2]:SetPoint("BOTTOMRIGHT") t[2]:SetHeight(e)
    t[3]:SetPoint("TOPLEFT", 0, -e) t[3]:SetPoint("BOTTOMLEFT", 0, e) t[3]:SetWidth(e)
    t[4]:SetPoint("TOPRIGHT", 0, -e) t[4]:SetPoint("BOTTOMRIGHT", 0, e) t[4]:SetWidth(e)
    d.edgeSize = e
end

local function Inset(d, bs)
    d.icon:ClearAllPoints()
    d.icon:SetPoint("TOPLEFT", bs, -bs)
    d.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
end

-- the mark on a game aura button; false: denied now (tried again later).
-- "EDGE" / "GLOW": the ring, registered with the button (the game shows and
-- tints it by the aura's type). "EDGE_ALL": the ring in magic blue on every
-- icon. "GLOW_ALL": the golden glow on every icon.
local function SetDispel(b, d, on)
    if d.dispelWant == on then return true end
    local add = b.AddDispelTypeTexture or b.SetAuraBorder
    local clear = b.ClearDispelTypeTextures or b.ClearAuraBorder
    if d.dispelReg then
        if not (clear and pcall(clear, b)) then return false end
        d.dispelReg = nil
    end
    d.ring:Hide()
    if on == "GLOW_ALL" or on == "EDGE_GLOW" then
        if d.proc then
            if not d.procReg then
                if not b.AddAuraShownAnimation then
                    A.glowErr = "no AddAuraShownAnimation"
                else
                    local ok, err = pcall(b.AddAuraShownAnimation, b, d.procAnim)
                    if not ok then A.glowErr = tostring(err) return false end
                    d.procReg = true
                end
            end
            ProcShow(d, d.procReg and true or false)
        end
        if on == "GLOW_ALL" then
            d.dispelWant = on
            return true
        end
        -- EDGE_GLOW: the type's edge too (below)
    else
        ProcShow(d, false)    -- its animation stays with the button, unseen
    end
    if on == "EDGE_ALL" then
        local c = DISPEL_COLORS.Magic
        d.ring:SetColorTexture(c[1], c[2], c[3], 1)
        d.ring:Show()
        d.dispelWant = on
        return true
    end
    local opts = DispelOpts()
    if on and add and opts then
        for _, t in ipairs(d.edges or { d.ring }) do
            if not pcall(add, b, t, opts) then
                if clear then pcall(clear, b) end
                d.ring:Hide()
                return false
            end
        end
        d.dispelReg = true
    end
    d.dispelWant = on
    return true
end

---------------------------------------------------------------------------
-- Engine rows
---------------------------------------------------------------------------
local function GroupLayout(cfg, key)
    local w, h = ButtonWH(cfg, key)
    return { elementWidth = w, elementHeight = h,
             elementSpacing = cfg.gap, lineSpacing = cfg.gap }
end

-- nameplate icons: the game's own tooltip on hover (cfg.tooltips), clicks
-- still go through to the plate; otherwise no mouse at all
local function PlateMouse(b, d, cfg)
    local want = cfg.tooltips and true or false
    if d.tips == want then return true end
    local ok
    if want then
        ok = pcall(b.SetMouseClickEnabled, b, false) and pcall(b.SetMouseMotionEnabled, b, true)
    else
        ok = pcall(b.EnableMouse, b, false)
    end
    if ok then d.tips = want end
    return ok
end

function Row:InitButton(b, key)
    local cfg = self.cfg
    local size = SlotSize(cfg, key)
    local w, h = ButtonWH(cfg, key)
    -- everything is made and given a font first: registering runs the
    -- button's own update, which writes into these right away
    local d = Dress(b, cfg)
    d.slot = key
    b:SetSize(w, h)
    EdgePoints(d, cfg.edge)
    d.glowScale = cfg.glowSize or 140
    ProcSize(d, size)
    pcall(b.SetMouseClickEnabled, b, false)
    if self.plate then PlateMouse(b, d, cfg) end
    if cfg.highlight then pcall(b.EnableMouse, b, false) end   -- clicks and hovers reach the frame
    b:SetIcon(d.icon)
    b:SetDurationCooldown(d.cd)
    b:SetApplicationCount(d.count, {})
    d.size, d.w, d.h, d.countSize = size, w, h, cfg.countSize
    self.bdata[b] = d
    self.buttons[#self.buttons + 1] = b
    local okD, set = pcall(SetDispel, b, d, WantDispel(cfg, key))
    if not okD then self:Fail("type mark", set) elseif not set then self.pendingResize = true end
end

function Row:BuildEngine()
    local c = spare
    spare = nil
    if c then
        c:SetParent(self.parent)
    else
        c = CreateFrame("AuraContainer", nil, self.parent, "CustomAuraContainerTemplate")
    end
    c:ClearAllPoints()
    c:SetPoint("CENTER", self.parent, "CENTER")
    c:SetSize(1, 1)
    local cfg = self.cfg
    local cap = cfg.perRow * cfg.rows
    self.c = c
    self.kind = cfg.kind
    -- debuffs: lead (crowd control), main, extra; buffs: main, extra. The
    -- slots stay; their filters change with the settings.
    local g = A.Groups(cfg)
    self.slots = cfg.kind == "HARMFUL" and { "lead", "main", "extra" } or { "main", "extra" }
    self.filters, self.cands = {}, {}
    for _, key in ipairs(self.slots) do
        local filter = g[key] or (key == "lead" and Make(cfg.kind, false, "CROWD_CONTROL")) or g.main
        local cand = Cand(cfg, key)
        c:AddAuraGroup(key, filter, {
            maxFrameCount = cap,
            candidateFilters = cand,
            initializeFrame = function(b)
                local ok, err = pcall(self.InitButton, self, b, key)
                if not ok then self:Fail("icon setup", err) end
            end,
            layout = GroupLayout(cfg, key),
        })
        self.filters[key], self.cands[key] = filter, cand
    end
    if self.level then pcall(c.SetFrameLevel, c, self.level) end
    ns.Log("auras", "%s: game container ready (%s)", self.label, cfg.kind)
end

local function SetCap(c, key, cap)
    if c.SetAuraGroupEnabled then
        if cap > 0 then pcall(c.SetAuraGroupEnabled, c, key, true) end
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
        if cap <= 0 then pcall(c.SetAuraGroupEnabled, c, key, false) end
    else
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
    end
end

-- icon size and stack font (denied while auras are hidden: tried again later)
function Row:Resize()
    local cfg = self.cfg
    self.pendingResize = nil
    for _, b in ipairs(self.buttons) do
        local d = self.bdata[b]
        local size = SlotSize(cfg, d.slot)
        local w, h = ButtonWH(cfg, d.slot)
        if d.w ~= w or d.h ~= h or d.glowScale ~= (cfg.glowSize or 140) then
            if pcall(b.SetSize, b, w, h) then
                d.size, d.w, d.h, d.glowScale = size, w, h, cfg.glowSize or 140
                ProcSize(d, size)
            else self.pendingResize = true end
        end
        if d.edges and d.edgeSize ~= math.max(1, cfg.edge or 2) then
            if not pcall(EdgePoints, d, cfg.edge) then self.pendingResize = true end
        end
        if d.countSize ~= cfg.countSize then
            if pcall(ns.ApplyFont, d.count, "GLOBAL", cfg.countSize, "OUTLINE") then d.countSize = cfg.countSize
            else self.pendingResize = true end
        end
        if d.timer ~= cfg.timer then
            if pcall(d.cd.SetDrawSwipe, d.cd, cfg.timer ~= false) then d.timer = cfg.timer
            else self.pendingResize = true end
        end
        if d.timerText ~= cfg.timerText or d.timerSize ~= TimerSize(cfg) then
            if pcall(StyleTimer, d.cd, cfg) then d.timerText, d.timerSize = cfg.timerText, TimerSize(cfg)
            else self.pendingResize = true end
        end
        if d.border ~= BorderSize(cfg) then
            if pcall(Inset, d, BorderSize(cfg)) then d.border = BorderSize(cfg)
            else self.pendingResize = true end
        end
        if not SetDispel(b, d, WantDispel(cfg, d.slot)) then self.pendingResize = true end
        if self.plate and not PlateMouse(b, d, cfg) then self.pendingResize = true end
    end
end

function Row:ApplyEngine()
    local c, cfg = self.c, self.cfg
    c:ClearAllPoints()
    c:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    Call(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", cfg.anchor)
    Call(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", Flow(cfg.growH), Flow(cfg.growV))
    -- room for perRow icons, never perRow + 1 (works whether or not the
    -- engine counts the space after the last icon)
    Call(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", cfg.perRow * (cfg.size + cfg.gap) + 0.4)
    local cap = cfg.perRow * cfg.rows
    local g, empty = A.Groups(cfg), TeamEmpty(cfg)
    for _, key in ipairs(self.slots) do
        local cand = Cand(cfg, key)
        pcall(c.SetAuraGroupLayout, c, key, GroupLayout(cfg, key))
        local filter, show = g[key], g[key] ~= nil
        if empty and key ~= "lead" then show = false end
        if filter and filter ~= self.filters[key] then
            local ok, err = Call(c, "SetAuraGroupFilterString", nil, key, filter)
            if ok then self.filters[key] = filter
            else
                self:Fail("filter " .. filter .. " (after /reload)", err)
                if key ~= "main" then show = false end
            end
        end
        if self.cands[key] ~= cand then
            local ok = pcall(c.SetAuraGroupCandidateFilters, c, key, cand)
            if not ok and cand == nil then ok = pcall(c.SetAuraGroupCandidateFilters, c, key, {}) end
            if ok then self.cands[key] = cand end
        end
        SetCap(c, key, show and cap or 0)
    end
    self:Resize()
    c:Show()
    self:BindEngine()
end

function Row:BindEngine()
    local c = self.c
    local unit = (self.cfg and self.cfg.enabled) and self.unit or nil
    if unit then
        if self.bound ~= unit then
            local ok, err = pcall(c.SetUnit, c, unit)
            if not ok then self:Fail("SetUnit " .. unit, err) end
            self.bound = unit
        end
        pcall(c.UpdateAllAuras, c)
    elseif self.bound then
        if not pcall(c.SetUnit, c, "none") then pcall(c.SetUnit, c, nil) end
        self.bound = nil
    end
end

---------------------------------------------------------------------------
-- Scan rows (no containers, or a container couldn't be made)
---------------------------------------------------------------------------
function Row:Icon(i)
    local b = self.icons[i]
    if not b then
        b = CreateFrame("Frame", nil, self.holder)
        b.d = Dress(b, self.cfg)
        b:EnableMouse(false)
        self.icons[i] = b
    end
    local cfg = self.cfg
    b:SetSize(cfg.size, cfg.size)
    b.d.glowScale = cfg.glowSize or 140
    ProcSize(b.d, cfg.size)
    if b.d.border ~= BorderSize(cfg) then
        Inset(b.d, BorderSize(cfg))
        b.d.border = BorderSize(cfg)
    end
    ns.ApplyFont(b.d.count, "GLOBAL", cfg.countSize or 9, "OUTLINE")
    b.d.cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(b.d.cd, cfg)
    return b
end

function Row:Place(b, n)
    local cfg = self.cfg
    local i = n - 1
    local col, line = i % cfg.perRow, floor(i / cfg.perRow)
    local step = cfg.size + cfg.gap
    local dx = col * step * (cfg.growH == "LEFT" and -1 or 1)
    local dy = line * step * (cfg.growV == "DOWN" and -1 or 1)
    b:ClearAllPoints()
    b:SetPoint(cfg.anchor, self.holder, cfg.anchor, dx, dy)
end

function Row:LayoutHolder()
    local cfg = self.cfg
    local h = self.holder
    h:ClearAllPoints()
    h:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    h:SetSize(math.max(1, cfg.perRow * (cfg.size + cfg.gap)), math.max(1, cfg.rows * (cfg.size + cfg.gap)))
    if cfg.level then self:SetLevel(cfg.level) end
end

-- the holder as big as the n icons it shows: a centred row stays centred
function Row:FitHolder(n)
    local cfg = self.cfg
    if n < 1 then return end
    local cols = math.min(n, cfg.perRow)
    local lines = math.ceil(n / cfg.perRow)
    self.holder:SetSize(cols * cfg.size + (cols - 1) * cfg.gap, lines * cfg.size + (lines - 1) * cfg.gap)
end

-- above the frame's bars and texts: icons inside the frame stay visible
function Row:SetLevel(level)
    self.level = level
    self.holder:SetFrameLevel(level)
    if self.c then pcall(self.c.SetFrameLevel, self.c, level) end
end

function Row:Scan()
    local cfg = self.cfg
    local n = 0
    local unit = self.unit
    if cfg and cfg.enabled and unit and not self.c and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        and ns.Bool(UnitExists(unit)) then
        local g = A.Groups(cfg)
        local max = cfg.perRow * cfg.rows
        local seen = {}
        local sated = cfg.kind == "HARMFUL" and cfg.hideSated
        local f = Eff(cfg)
        local team = (cfg.kind == "HARMFUL" and f == "TEAM")
                     or (cfg.kind == "HELPFUL" and (f == "TEAM_PURGE" or f == "MINE_PURGE"))
        if team and not teamCand then ReadTeam() end
        local types = (cfg.kind == "HARMFUL" and teamTypes) or (f == "MINE_PURGE" and minePurgeTypes) or purgeTypes
        if team and TeamEmpty(cfg) then max = 0 end
        for _, key in ipairs(A.SLOTS) do
          local filter = g[key]
          local ring = WantDispel(cfg, key)
          for i = 1, filter and 40 or 0 do
            if n >= max then break end
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then self:Fail("reading " .. unit .. " " .. filter, a) break end
            if type(a) ~= "table" then break end
            local id, sid = a.auraInstanceID, a.spellId
            if ns.IsSecret(id) then id = nil end
            local skip = (id and seen[id]) or (sated and not ns.IsSecret(sid) and SATED[sid])
            if not skip and team and key ~= "lead" then
                local dn = a.dispelName
                if ns.IsSecret(dn) then dn = nil end
                skip = not (dn and types[dn])
            end
            if not skip then
            if id then seen[id] = true end
            n = n + 1
            local b = self:Icon(n)
            self:Place(b, n)
            local dn = ring and a.dispelName
            local col = dn and not ns.IsSecret(dn) and DISPEL_COLORS[dn]
            ShowType(b.d, ring, col)
            pcall(b.d.icon.SetTexture, b.d.icon, a.icon)
            local cnt = a.applications
            if ns.IsSecret(cnt) or type(cnt) ~= "number" or cnt < 2 then b.d.count:SetText("")
            else b.d.count:SetText(cnt) end
            local dur, exp = a.duration, a.expirationTime
            if not ns.IsSecret(dur) and not ns.IsSecret(exp) and type(dur) == "number"
                and type(exp) == "number" and dur > 0 then
                b.d.cd:SetCooldown(exp - dur, dur)
                b.d.cd:Show()
            else
                b.d.cd:Hide()
            end
            b:Show()
            end
          end
        end
    end
    self:FitHolder(n)
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Public row methods
---------------------------------------------------------------------------
function Row:Configure(cfg)
    self.cfg = cfg
    self.preview = nil
    self:LayoutHolder()
    if not cfg.enabled then
        self:Disable()
        return
    end
    if not self.c and not self.noEngine and Engine() then
        local ok, err = pcall(self.BuildEngine, self)
        if not ok then
            self:Fail("game container", err)
            if self.c then self.c:Hide() end
            self.c = nil
            self.noEngine = true       -- this row scans from now on
        end
    end
    if cfg.highlight and not self.c then
        self:Disable()          -- the frame edge needs the game's aura display
        return
    end
    if self.c then
        if self.level then pcall(self.c.SetFrameLevel, self.c, self.level) end
        for _, b in ipairs(self.icons) do b:Hide() end
        self.ev:UnregisterAllEvents()
        local ok, err = pcall(self.ApplyEngine, self)
        if not ok then self:Fail("layout", err) end
    else
        self:WatchScan()
        self:Scan()
    end
end

function Row:WatchScan()
    self.ev:UnregisterAllEvents()
    if self.unit and self.cfg and self.cfg.enabled and not self.c then
        pcall(self.ev.RegisterUnitEvent, self.ev, "UNIT_AURA", self.unit)
    end
end

function Row:Disable()
    self.ev:UnregisterAllEvents()
    for _, b in ipairs(self.icons) do b:Hide() end
    if self.c then
        self.c:Hide()
        self:BindEngine()
    end
end

function Row:SetUnit(unit)
    if ns.IsSecret(unit) then unit = nil end
    self.unit = unit
    if not self.cfg then return end
    if self.c then self:BindEngine()
    else
        self:WatchScan()
        self:Scan()
    end
end

-- the unit token now means someone else (target swapped, polled units)
function Row:Refresh()
    if not (self.cfg and self.cfg.enabled) or self.preview then return end
    if self.c then
        if self.bound then pcall(self.c.UpdateAllAuras, self.c) end
    else
        self:Scan()
    end
end

-- unlock mode: sample icons, nothing read from the game
local SAMPLE = { 136118, 135812, 136207, 132090, 136197, 135848, 132316, 136139 }
local SAMPLE_TYPES = { "Magic", "Curse", "None", "Poison", "Disease" }
function Row:Preview(cfg, n)
    self.cfg = cfg
    self.preview = true
    self:LayoutHolder()
    self.ev:UnregisterAllEvents()
    if self.c then self.c:Hide() end
    n = cfg.enabled and math.min(n or 3, cfg.perRow * cfg.rows) or 0
    for i = 1, n do
        local b = self:Icon(i)
        self:Place(b, i)
        b.d.icon:SetTexture(SAMPLE[(i - 1) % #SAMPLE + 1])
        b.d.count:SetText(i == 2 and "3" or "")
        b.d.cd:Hide()
        local col = WantDispel(cfg) and DISPEL_COLORS[SAMPLE_TYPES[(i - 1) % #SAMPLE_TYPES + 1]]
        ShowType(b.d, WantDispel(cfg), col)
        b:Show()
    end
    self:FitHolder(n)
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

function Row:Info()
    local cfg = self.cfg
    if not cfg then return "not set up" end
    if not cfg.enabled then return "off" end
    if self.preview then return "preview" end
    if self.c then
        return ("game container, unit %s, %d icons made%s"):format(tostring(self.bound), #self.buttons,
            self.pendingResize and ", resize pending" or "")
    end
    local shown = 0
    for _, b in ipairs(self.icons) do if b:IsShown() then shown = shown + 1 end end
    return ("scan, unit %s, %d shown, %d errors"):format(tostring(self.unit), shown, self.errors)
end

-- sizes the game refused while auras were hidden: once it allows them again
local function RetryResize()
    for _, r in ipairs(rows) do
        if r.pendingResize and r.c then pcall(r.Resize, r) end
    end
end
ns.On("PLAYER_REGEN_ENABLED", RetryResize)

-- the group changed: rows on "Ones my group can dispel" take the new types
local retrying = false
local function TeamChanged()
    local changed = ReadTeam()
    InspectNext()
    -- members out of range: try again in a while
    if #unknownSpec > 0 and not retrying then
        retrying = true
        C_Timer.After(10, function() retrying = false TeamChanged() end)
    end
    if not changed then return end
    ns.Log("auras", "group can dispel: %s; purge: %s", teamKey ~= "" and teamKey or "nothing",
           purgeKey ~= "" and purgeKey or "nothing")
    for _, r in ipairs(rows) do
        local cfg = r.cfg
        local uses = cfg and GROUP_FILTERS[cfg.filter]
        if uses and cfg.enabled and not r.preview then
            if r.c then
                local ok, err = pcall(r.ApplyEngine, r)
                if not ok then r:Fail("group dispels", err) end
            else
                r:Scan()
            end
        end
    end
end
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED",
                     "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(ns.On, e, TeamChanged)
end
pcall(ns.On, "INSPECT_READY", function() inspectBusy = false TeamChanged() end)
-- purges: levels, spells and pets change who can
for _, e in ipairs({ "PLAYER_LEVEL_UP", "SPELLS_CHANGED" }) do pcall(ns.On, e, TeamChanged) end
local function GroupUnitEvent(unit)
    if type(unit) == "string" and not ns.IsSecret(unit)
       and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then TeamChanged() end
end
for _, e in ipairs({ "UNIT_LEVEL", "UNIT_PET" }) do pcall(ns.On, e, GroupUnitEvent) end
ns.On("ZONE_CHANGED_NEW_AREA", RetryResize)

---------------------------------------------------------------------------
-- Diagnostics for the debug report and the recorder
---------------------------------------------------------------------------
local PROBE_FILTERS = { "HARMFUL", "HARMFUL|PLAYER", "HELPFUL", "HELPFUL|PLAYER" }
function A.ProbeUnit(unit)
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "no C_UnitAuras" end
    for _, filter in ipairs(PROBE_FILTERS) do
        local names, err = {}, nil
        for i = 1, 8 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then err = tostring(a) break end
            if type(a) ~= "table" then break end
            local nm = a.name
            names[#names + 1] = ns.IsSecret(nm) and "SECRET" or tostring(nm)
        end
        out[#out + 1] = filter .. "=" .. (err and ("ERR " .. err) or ("[" .. table.concat(names, ", ") .. "]"))
    end
    return table.concat(out, "  ")
end

-- /run HUF.Auras.PurgeReport() with an enemy targeted
function A.PurgeReport(unit)
    unit = unit or "target"
    local function S(v) return ns.IsSecret(v) and "SECRET" or tostring(v) end
    ReadTeam()
    print(("HUF purge: group can purge [%s], dispel [%s]"):format(purgeKey, teamKey))
    for _, u in ipairs(GroupUnits()) do
        local okC, _, class = pcall(UnitClass, u)
        local okL, lv = pcall(UnitLevel, u)
        local can = {}
        for _, p in ipairs(okC and PURGES[Plain(class) or ""] or {}) do
            can[#can + 1] = p.id .. "=" .. tostring(CanPurge(u, class, p)) .. (u == "player" and ("/known " .. tostring(Known(p.id, p.pet))) or "")
        end
        print(("  %s %s lv %s %s"):format(u, S(okC and class), S(okL and lv), table.concat(can, " ")))
    end
    local okE, ex = pcall(UnitExists, unit)
    local okN, nm = pcall(UnitName, unit)
    print(("  %s: exists %s, %s, auras hidden now %s"):format(unit, S(okE and ex), S(okN and nm), tostring(A.Restricted())))
    for _, f in ipairs({ "HELPFUL", "HELPFUL|" .. DISPELLABLE }) do
        for i = 1, 10 do
            if i == 1 then
                local okA, a1 = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, f)
                if okA and type(a1) ~= "table" then print("  " .. f .. ": none read (" .. type(a1) .. ")") end
            end
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, f)
            if not ok then print("  " .. f .. " error " .. tostring(a)) break end
            if type(a) ~= "table" then break end
            print(("  %s #%d %s id %s type %s"):format(f, i, S(a.name), S(a.spellId), S(a.dispelName)))
        end
    end
    local plates, bound = 0, 0
    for _, r in ipairs(rows) do
        if r.plate and r.cfg and r.cfg.kind == "HELPFUL" then
            plates = plates + 1
            if r.unit then bound = bound + 1 end
        end
    end
    print(("  plate buff rows: %d, with a unit: %d"):format(plates, bound))
    for _, r in ipairs(rows) do
        local ok, same = pcall(UnitIsUnit, r.unit or "none", unit)
        if r.plate and r.cfg and r.cfg.kind == "HELPFUL" and ok and ns.Bool(same) then
            print(("  row %s filter %s mark %s all %s cand %s: %s"):format(r.label, tostring(r.cfg.filter),
                tostring(r.cfg.dispelBorder), tostring(r.cfg.purge), r.cands and r.cands.main and "types" or "none", r:Info()))
            print("    last error: " .. tostring(r.lastErr) .. "; glow error: " .. tostring(A.glowErr))
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-Proc-Loop-Flipbook")
            print(("    atlas: %s %sx%s file %s"):format(info and "yes" or "NO", tostring(info and info.width),
                tostring(info and info.height), tostring(info and (info.file or info.filename))))
            for i, b in ipairs(r.buttons or {}) do
                local d = r.bdata[b]
                if d and i <= 3 then
                    print(("    icon %d want %s reg %s glow %s registered %s shown %s ring %s"):format(i,
                        tostring(d.dispelWant), tostring(d.dispelReg), tostring(d.proc and true or false),
                        tostring(d.procReg), tostring(d.proc and d.proc:IsShown()), tostring(d.ring:IsShown())))
                end
            end
        end
    end
end

function A.Report()
    local lines = { ("containers: %s, auras hidden now: %s"):format(tostring(Engine()), tostring(A.Restricted())) }
    for _, r in ipairs(rows) do
        if r.cfg and r.cfg.enabled and r.unit and not r.preview then
            lines[#lines + 1] = "  " .. r.label .. ": " .. r:Info()
        end
    end
    return lines
end
