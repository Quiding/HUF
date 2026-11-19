-- HUF: buff bar and debuff bar (replacing Blizzard's icons at the top right).
-- Each bar is the game's SecureAuraHeaderTemplate for the player: it makes
-- the icons (HUFAuraButtonTemplate, PlayerAuras.xml), lays them out and
-- keeps them current, also in combat; a right-click cancels a buff. HUF
-- dresses each icon: zoom, border, swipe, time left, stacks.
-- Settings: ns.db.auraBars.buffs / .debuffs. Header attributes only change
-- out of combat (else queued).

local _, ns = ...
local PA = {}
ns.PlayerAuras = PA

local A = ns.ACCENT
local FLAT = "Interface\\Buttons\\WHITE8X8"
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) return v ~= nil and not IsSecret(v) end

local KINDS = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local headers = {}               -- kind -> header
local movers = {}

local function S(kind) return ns.db.auraBars[kind] end

local DEBUFF_COLORS = {
    Magic = { 0.20, 0.60, 1.00 }, Curse = { 0.60, 0.00, 1.00 }, Disease = { 0.60, 0.40, 0.00 },
    Poison = { 0.00, 0.60, 0.00 }, none = { 0.80, 0.00, 0.00 },
}

---------------------------------------------------------------------------
-- Layout: growth direction -> header attributes
---------------------------------------------------------------------------
-- the first icon's corner, the step to the next icon and to the next line
local function Geometry(s)
    local step = s.size + s.padding
    local lineStep = s.size + s.padding + ((s.timer and s.timerPos == "BELOW") and (s.timerSize + 2) or 0)
    local g = s.grow
    local perLine, lines
    if g == "LEFT" or g == "RIGHT" then perLine, lines = s.columns, s.rows
    else perLine, lines = s.rows, s.columns end
    local t = { perLine = math.max(1, perLine), lines = math.max(1, lines) }
    if g == "LEFT" then
        t.point, t.x, t.y, t.wx, t.wy = "TOPRIGHT", -step, 0, 0, -lineStep
    elseif g == "RIGHT" then
        t.point, t.x, t.y, t.wx, t.wy = "TOPLEFT", step, 0, 0, -lineStep
    elseif g == "DOWN" then
        t.point, t.x, t.y, t.wx, t.wy = "TOPLEFT", 0, -lineStep, step, 0
    else -- UP
        t.point, t.x, t.y, t.wx, t.wy = "BOTTOMLEFT", 0, lineStep, step, 0
    end
    -- the whole area (for the header's size and the unlock box)
    if g == "LEFT" or g == "RIGHT" then
        t.w = t.perLine * step - s.padding
        t.h = t.lines * lineStep - s.padding
    else
        t.w = t.lines * step - s.padding
        t.h = t.perLine * lineStep - s.padding
    end
    return t
end
PA.Geometry = Geometry

local SORT = { TIME = "TIME", NAME = "NAME", INDEX = "INDEX" }

---------------------------------------------------------------------------
-- One icon
---------------------------------------------------------------------------
local function FormatTime(sec, fmt)
    if sec >= 3600 then
        if fmt == "MM" then return ("%dm"):format(math.floor(sec / 60 + 0.5)) end
        local h = math.floor(sec / 3600)
        return ("%d:%02d"):format(h, math.floor((sec - h * 3600) / 60))
    elseif sec >= 60 then
        return ("%dm"):format(math.floor(sec / 60 + 0.5))
    elseif sec >= 10 then
        return ("%d"):format(math.floor(sec + 0.5))
    end
    return ("%.1f"):format(sec)
end
PA.FormatTime = FormatTime

local function OnUpdate(b, elapsed)
    b.tick = (b.tick or 0) + elapsed
    if b.tick < 0.1 then return end
    b.tick = 0
    local exp = b.expires
    if not exp or exp == 0 then b.time:SetText("") return end
    local left = exp - GetTime()
    if left <= 0 then b.time:SetText("") return end
    local s = S(b.kind)
    b.time:SetText(FormatTime(left, s.timerFormat))
    if left < 5 then b.time:SetTextColor(1, 0.3, 0.3) else b.time:SetTextColor(1, 1, 1) end
end

-- the icon's look (size and position belong to the header)
local function Dress(b)
    local s = S(b.kind)
    local z = math.max(0, math.min(0.4, s.zoom))
    b.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    local bs = s.borderSize
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", bs, -bs)
    b.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
    b.border:SetShown(bs > 0)
    b.cd:SetDrawSwipe(s.swipe)
    b.cd:SetShown(s.swipe)
    ns.ApplyFont(b.time, s.font, s.timerSize, s.outline)
    ns.ApplyFont(b.count, s.font, s.countSize, s.outline)
    b.time:ClearAllPoints()
    if s.timerPos == "BELOW" then b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
    else b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 2) end
    b.time:SetShown(s.timer)
    b.count:ClearAllPoints()
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
end

local function SetBorderColor(b, r, g, bl)
    b.border:SetColorTexture(r, g, bl, 1)
end

local function Update(b)
    local header = b:GetParent()
    local kind = header and header.kind
    if not kind then return end
    b.kind = kind
    local s = S(kind)
    local slot = b:GetAttribute("target-slot")
    local index = b:GetAttribute("index")
    local icon, count, duration, expires, dispel
    if slot then
        -- weapon enchant (main hand 16, off hand 17)
        local hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = GetWeaponEnchantInfo()
        local ms, charges
        if slot == 16 then ms, charges = hasMain and mainExp, mainCharges
        else ms, charges = hasOff and offExp, offCharges end
        icon = GetInventoryItemTexture("player", slot)
        count = charges
        expires = ms and (GetTime() + ms / 1000) or nil
        duration = 0
        b.auraInstance = nil
    elseif index then
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, header:GetAttribute("filter"))
        if not ok or not a then b.icon:SetTexture(nil) b.expires = nil return end
        icon, count, duration, expires, dispel = a.icon, a.applications, a.duration, a.expirationTime, a.dispelName
        b.auraInstance = a.auraInstanceID
    else
        return
    end
    pcall(b.icon.SetTexture, b.icon, icon)
    -- stacks
    if Plain(count) and count > 1 then b.count:SetText(count)
    elseif IsSecret(count) then pcall(b.count.SetText, b.count, count)
    else b.count:SetText("") end
    -- time left (readable on yourself; a secret one leaves only the swipe)
    if Plain(expires) and expires > 0 then b.expires = expires else b.expires = nil b.time:SetText("") end
    if s.swipe and Plain(duration) and Plain(expires) and duration > 0 and expires > 0 then
        b.cd:SetCooldown(expires - duration, duration)
        b.cd:Show()
    elseif s.swipe and (IsSecret(duration) or IsSecret(expires)) then
        local ok = pcall(function() b.cd:SetCooldown(expires - duration, duration) end)
        b.cd:SetShown(ok)
    else
        b.cd:Clear()
        b.cd:Hide()
    end
    -- border: debuffs by type, else the setting's colour
    local c = s.borderColor
    if s.borderAccent then c = { r = A[1], g = A[2], b = A[3] } end
    if kind == "debuffs" and s.typeColors then
        local t = Plain(dispel) and DEBUFF_COLORS[dispel] or DEBUFF_COLORS.none
        SetBorderColor(b, t[1], t[2], t[3])
    else
        SetBorderColor(b, c.r, c.g, c.b)
    end
    -- more than "max": invisible (the header fills rows x columns)
    local over = (b.pos or 1) > s.max
    b:SetAlpha(over and 0 or 1)
    if not InCombatLockdown() then b:EnableMouse(not over) end
end

local function OnEnter(b)
    if b:GetAlpha() == 0 then return end
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    local slot = b:GetAttribute("target-slot")
    if slot then
        GameTooltip:SetInventoryItem("player", slot)
    elseif b.auraInstance and GameTooltip.SetUnitAuraByAuraInstanceID then
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", b.auraInstance)
    else
        local index = b:GetAttribute("index")
        if index then pcall(GameTooltip.SetUnitAura, GameTooltip, "player", index, b:GetParent():GetAttribute("filter")) end
    end
    GameTooltip:Show()
end

-- called by the template's OnLoad for every icon the header makes
function HUF_AuraButton_OnLoad(b)
    local header = b:GetParent()
    b.kind = header and header.kind
    header.hufCount = (header.hufCount or 0) + 1
    b.pos = header.hufCount
    b:RegisterForClicks("RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    local textLayer = CreateFrame("Frame", nil, b)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.time = textLayer:CreateFontString(nil, "OVERLAY")
    b.count = textLayer:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.time, "GLOBAL", 12)
    ns.ApplyFont(b.count, "GLOBAL", 12)
    b:SetScript("OnAttributeChanged", function(self, name)
        if name == "index" or name == "target-slot" then Update(self) end
    end)
    b:SetScript("OnUpdate", OnUpdate)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if b.kind then
        Dress(b)
        local s = S(b.kind)
        if not InCombatLockdown() then b:SetSize(s.size, s.size) else PA.pendingSize = true end
    end
end

---------------------------------------------------------------------------
-- Headers
---------------------------------------------------------------------------
local function Children(h)
    local list, i = {}, 1
    while true do
        local c = h:GetAttribute("child" .. i)
        if not c then break end
        list[#list + 1] = c
        i = i + 1
    end
    -- weapon enchant icons
    for _, k in ipairs({ "tempEnchant1", "tempEnchant2", "tempEnchant3" }) do
        local c = h:GetAttribute(k)
        if c then list[#list + 1] = c end
    end
    return list
end

local function BuildHeader(kind)
    if headers[kind] then return headers[kind] end
    local ok, h = pcall(CreateFrame, "Frame", "HUF_" .. (kind == "buffs" and "Buffs" or "Debuffs"), UIParent,
        "SecureAuraHeaderTemplate")
    if not ok or not h then
        ns.LogError("aura bar", "SecureAuraHeaderTemplate missing: " .. tostring(h))
        return nil
    end
    h.kind = kind
    h:SetFrameStrata("LOW")
    h:SetAttribute("unit", "player")
    h:SetAttribute("filter", KINDS[kind])
    h:SetAttribute("template", "HUFAuraButtonTemplate")
    if kind == "buffs" then
        h:SetAttribute("includeWeapons", 1)
        h:SetAttribute("weaponTemplate", "HUFAuraButtonTemplate")
    end
    h:SetClampedToScreen(true)
    h:SetMovable(true)
    headers[kind] = h

    -- unlock mode: drag box
    local m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("HIGH")
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("RightButtonUp")
    ns.UI.Fill(m, A[1], A[2], A[3], 0.15)
    m.border = ns.UI.Border(m, A[1], A[2], A[3], 0.8)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.label:SetPoint("CENTER")
    m.label:SetText(kind == "buffs" and "Buffs" or "Debuffs")
    m:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        m.from = { h:GetLeft(), h:GetTop() }
        h:StartMoving()
    end)
    m:SetScript("OnDragStop", function()
        h:StopMovingOrSizing()
        if h.SetUserPlaced then h:SetUserPlaced(false) end
        local from = m.from
        if not from then return end
        m.from = nil
        local p = S(kind).point
        p[3] = math.floor((p[3] or 0) + (h:GetLeft() or 0) - (from[1] or 0) + 0.5)
        p[4] = math.floor((p[4] or 0) + (h:GetTop() or 0) - (from[2] or 0) + 0.5)
        PA.Apply()
    end)
    m:SetScript("OnClick", function() if ns.ToggleConfig then ns.ToggleConfig("aurabars", true) end end)
    m:Hide()
    movers[kind] = m
    return h
end

local function ApplyHeader(kind)
    local s = S(kind)
    local h = headers[kind]
    if not s.enabled then
        if h then h:Hide() end
        if movers[kind] then movers[kind]:Hide() end
        return
    end
    h = h or BuildHeader(kind)
    if not h then return end
    local g = Geometry(s)
    h:ClearAllPoints()
    h:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    h:SetSize(g.w, g.h)
    h:SetScale(s.scale)
    h:SetAttribute("point", g.point)
    h:SetAttribute("xOffset", g.x)
    h:SetAttribute("yOffset", g.y)
    h:SetAttribute("wrapAfter", g.perLine)
    h:SetAttribute("maxWraps", g.lines)
    h:SetAttribute("wrapXOffset", g.wx)
    h:SetAttribute("wrapYOffset", g.wy)
    h:SetAttribute("minWidth", g.w)
    h:SetAttribute("minHeight", g.h)
    h:SetAttribute("sortMethod", SORT[s.sort] or "TIME")
    h:SetAttribute("sortDirection", s.sortDir == "+" and "+" or "-")
    -- the icons' first anchor point follows the growth corner
    for _, c in ipairs(Children(h)) do
        c:SetSize(s.size, s.size)
        Dress(c)
        Update(c)
    end
    h:Show()
    -- (never SecureAuraHeader_Update from here: calling it taints the header,
    -- and its own updates in combat get blocked; the attribute changes above
    -- make it lay the icons out again)
    local m = movers[kind]
    m:ClearAllPoints()
    m:SetAllPoints(h)
    m:SetScale(s.scale)
    m:SetShown(ns.unlocked and true or false)
end

function PA.Apply()
    if not (HUFDB and ns.db) then return end
    ns.RunOOC("aurabars", function()
        ApplyHeader("buffs")
        ApplyHeader("debuffs")
        if ns.Units and ns.Units.HideBlizzardBars then ns.Units.HideBlizzardBars() end
    end)
end

function PA.SetUnlocked(on)
    for kind, m in pairs(movers) do m:SetShown(on and S(kind).enabled and true or false) end
end

function PA.Report(add)
    for kind in pairs(KINDS) do
        local s, h = S(kind), headers[kind]
        add(("aura bar %s: enabled=%s header=%s shown=%s icons=%d grow=%s max=%d %dx%d size=%d"):format(kind,
            tostring(s.enabled), tostring(h ~= nil), tostring(h and h:IsShown()), h and #Children(h) or 0,
            s.grow, s.max, s.columns, s.rows, s.size))
    end
end

ns.OnLogin(PA.Apply)
ns.OnRefresh(PA.Apply)
ns.On("PLAYER_REGEN_ENABLED", function()
    if PA.pendingSize then PA.pendingSize = false PA.Apply() end
end)
