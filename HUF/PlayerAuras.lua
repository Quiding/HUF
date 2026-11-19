-- HUF: buff bar and debuff bar (replacing Blizzard's icons at the top right).
-- Forever has no SecureAuraHeaderTemplate, so HUF draws the icons itself
-- from your own auras (readable on yourself): C_UnitAuras by index on
-- UNIT_AURA, plus weapon enchants on the buff bar. Plain frames, nothing
-- secure: they update in combat too. Right-click cancels a buff out of
-- combat (the game allows addons to cancel buffs only then).
-- Settings: ns.db.auraBars.buffs / .debuffs.

local _, ns = ...
local PA = {}
ns.PlayerAuras = PA

local A = ns.ACCENT
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) return v ~= nil and not IsSecret(v) end

local KINDS = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local bars = {}                  -- kind -> bar frame with .icons
local movers = {}

local function S(kind) return ns.db.auraBars[kind] end

local DEBUFF_COLORS = {
    Magic = { 0.20, 0.60, 1.00 }, Curse = { 0.60, 0.00, 1.00 }, Disease = { 0.60, 0.40, 0.00 },
    Poison = { 0.00, 0.60, 0.00 }, none = { 0.80, 0.00, 0.00 },
}

---------------------------------------------------------------------------
-- Layout: growth direction -> where icon n goes
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Time text
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
    if not exp then b.time:SetText("") return end
    local left = exp - GetTime()
    if left <= 0 then b.time:SetText("") return end
    b.time:SetText(FormatTime(left, S(b.kind).timerFormat))
    if left < 5 then b.time:SetTextColor(1, 0.3, 0.3) else b.time:SetTextColor(1, 1, 1) end
end

---------------------------------------------------------------------------
-- One icon
---------------------------------------------------------------------------
local function OnEnter(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    local d = b.data
    if not d then return end
    if d.slot then
        GameTooltip:SetInventoryItem("player", d.slot)
    elseif d.instance and GameTooltip.SetUnitAuraByAuraInstanceID then
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", d.instance)
    else
        pcall(GameTooltip.SetUnitAura, GameTooltip, "player", d.index, KINDS[b.kind])
    end
    if b.kind == "buffs" then GameTooltip:AddLine("Right-click: cancel (out of combat)", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function OnClick(b, button)
    if button ~= "RightButton" or b.kind ~= "buffs" or not b.data then return end
    if InCombatLockdown() then
        ns.Print("Buffs can only be cancelled out of combat.")
        return
    end
    local d = b.data
    if d.slot then
        pcall(CancelItemTempEnchantment, d.slot - 15)
    elseif d.instance and C_UnitAuras and C_UnitAuras.CancelAuraByAuraInstanceID
        and pcall(C_UnitAuras.CancelAuraByAuraInstanceID, "player", d.instance) then
        -- done
    elseif CancelUnitBuff then
        pcall(CancelUnitBuff, "player", d.index, "HELPFUL")
    end
end

local function NewIcon(bar)
    local b = CreateFrame("Button", nil, bar)
    b.kind = bar.kind
    b:RegisterForClicks("RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    local layer = CreateFrame("Frame", nil, b)
    layer:SetAllPoints()
    layer:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.time = layer:CreateFontString(nil, "OVERLAY")
    b.count = layer:CreateFontString(nil, "OVERLAY")
    b:SetScript("OnUpdate", OnUpdate)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", OnClick)
    b:Hide()
    return b
end

-- the icon's look
local function Dress(b, s)
    b:SetSize(s.size, s.size)
    local z = math.max(0, math.min(0.4, s.zoom))
    b.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    local bs = s.borderSize
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", bs, -bs)
    b.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
    b.border:SetShown(bs > 0)
    ns.ApplyFont(b.time, s.font, s.timerSize, s.outline)
    ns.ApplyFont(b.count, s.font, s.countSize, s.outline)
    b.time:ClearAllPoints()
    if s.timerPos == "BELOW" then b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
    else b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 2) end
    b.time:SetShown(s.timer)
    b.count:ClearAllPoints()
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
end

local function Fill(b, d, s)
    b.data = d
    pcall(b.icon.SetTexture, b.icon, d.icon)
    local count = d.count
    if Plain(count) and count > 1 then b.count:SetText(count)
    elseif IsSecret(count) then pcall(b.count.SetText, b.count, count)
    else b.count:SetText("") end
    if Plain(d.expires) and d.expires > 0 then b.expires = d.expires else b.expires = nil b.time:SetText("") end
    b.tick = 1
    if s.swipe and Plain(d.duration) and Plain(d.expires) and d.duration > 0 and d.expires > 0 then
        b.cd:SetCooldown(d.expires - d.duration, d.duration)
        b.cd:Show()
    else
        b.cd:Clear()
        b.cd:Hide()
    end
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    if b.kind == "debuffs" and s.typeColors then
        local t = Plain(d.dispel) and DEBUFF_COLORS[d.dispel] or DEBUFF_COLORS.none
        b.border:SetColorTexture(t[1], t[2], t[3], 1)
    else
        b.border:SetColorTexture(c.r, c.g, c.b, 1)
    end
    b:Show()
end

---------------------------------------------------------------------------
-- Reading your auras
---------------------------------------------------------------------------
local function Collect(kind)
    local list = {}
    local filter = KINDS[kind]
    local now = GetTime()
    if kind == "buffs" and GetWeaponEnchantInfo then
        local ok, hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = pcall(GetWeaponEnchantInfo)
        if ok then
            if hasMain then list[#list + 1] = { slot = 16, icon = GetInventoryItemTexture("player", 16), count = mainCharges,
                expires = mainExp and now + mainExp / 1000, duration = 0, order = 0, name = "" } end
            if hasOff then list[#list + 1] = { slot = 17, icon = GetInventoryItemTexture("player", 17), count = offCharges,
                expires = offExp and now + offExp / 1000, duration = 0, order = 0, name = "" } end
        end
    end
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok or not a then break end
        list[#list + 1] = { index = i, instance = a.auraInstanceID, icon = a.icon, count = a.applications,
            duration = a.duration, expires = a.expirationTime, dispel = a.dispelName, name = a.name, order = i }
    end
    return list
end

local function SortList(list, s)
    local desc = s.sortDir ~= "+"
    local function key(d)
        if s.sort == "NAME" then return Plain(d.name) and d.name or "" end
        if s.sort == "TIME" then
            -- no end (permanent) counts as the longest
            if Plain(d.expires) and d.expires > 0 then return d.expires end
            return math.huge
        end
        return d.order
    end
    local ok = pcall(table.sort, list, function(a, b)
        local ka, kb = key(a), key(b)
        if ka == kb then return a.order < b.order end
        if desc then return ka > kb end
        return ka < kb
    end)
    if not ok then table.sort(list, function(a, b) return a.order < b.order end) end
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function BuildBar(kind)
    if bars[kind] then return bars[kind] end
    local bar = CreateFrame("Frame", "HUF_" .. (kind == "buffs" and "Buffs" or "Debuffs"), UIParent)
    bar.kind = kind
    bar.icons = {}
    bar:SetFrameStrata("LOW")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bars[kind] = bar

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
        m.from = { bar:GetLeft(), bar:GetTop() }
        bar:StartMoving()
    end)
    m:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        if bar.SetUserPlaced then bar:SetUserPlaced(false) end
        local from = m.from
        if not from then return end
        m.from = nil
        local p = S(kind).point
        p[3] = math.floor((p[3] or 0) + (bar:GetLeft() or 0) - (from[1] or 0) + 0.5)
        p[4] = math.floor((p[4] or 0) + (bar:GetTop() or 0) - (from[2] or 0) + 0.5)
        PA.Apply()
    end)
    m:SetScript("OnClick", function() if ns.ToggleConfig then ns.ToggleConfig("aurabars", true) end end)
    m:Hide()
    movers[kind] = m
    return bar
end

function PA.Update(kind)
    local bar = bars[kind]
    if not bar or not bar:IsShown() then return end
    local s = S(kind)
    local g = bar.geo or Geometry(s)
    local list = Collect(kind)
    SortList(list, s)
    local n = math.min(#list, s.max, g.perLine * g.lines)
    for i = 1, n do
        local b = bar.icons[i]
        if not b then
            b = NewIcon(bar)
            bar.icons[i] = b
            Dress(b, s)
        end
        local line = math.floor((i - 1) / g.perLine)
        local col = (i - 1) % g.perLine
        b:ClearAllPoints()
        b:SetPoint(g.point, bar, g.point, col * g.x + line * g.wx, col * g.y + line * g.wy)
        Fill(b, list[i], s)
    end
    for i = n + 1, #bar.icons do
        bar.icons[i].data = nil
        bar.icons[i]:Hide()
    end
    bar.count = n
end

local function ApplyBar(kind)
    local s = S(kind)
    if not s.enabled then
        if bars[kind] then bars[kind]:Hide() end
        if movers[kind] then movers[kind]:Hide() end
        return
    end
    local bar = BuildBar(kind)
    local g = Geometry(s)
    bar.geo = g
    bar:ClearAllPoints()
    bar:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    bar:SetSize(g.w, g.h)
    bar:SetScale(s.scale)
    for _, b in ipairs(bar.icons) do Dress(b, s) end
    bar:Show()
    PA.Update(kind)
    local m = movers[kind]
    m:ClearAllPoints()
    m:SetAllPoints(bar)
    m:SetScale(s.scale)
    m:SetShown(ns.unlocked and true or false)
end

function PA.Apply()
    if not (HUFDB and ns.db) then return end
    ApplyBar("buffs")
    ApplyBar("debuffs")
    if ns.Units and ns.Units.HideBlizzardBars then ns.Units.HideBlizzardBars() end
end

function PA.SetUnlocked(on)
    for kind, m in pairs(movers) do m:SetShown(on and S(kind).enabled and true or false) end
end

function PA.Report(add)
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local s, bar = S(kind), bars[kind]
        add(("aura bar %s: enabled=%s shown=%s icons=%d grow=%s max=%d %dx%d size=%d"):format(kind,
            tostring(s.enabled), tostring(bar and bar:IsShown()), bar and bar.count or 0,
            s.grow, s.max, s.columns, s.rows, s.size))
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if not (HUFDB and ns.db) then return end
    if event == "UNIT_AURA" then
        PA.Update("buffs")
        PA.Update("debuffs")
    else
        PA.Update("buffs")
    end
end)
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_INVENTORY_CHANGED", "player")
pcall(ev.RegisterEvent, ev, "WEAPON_ENCHANT_CHANGED")
-- weapon enchants come and go without an event on some clients
C_Timer.NewTicker(2, function()
    if HUFDB and ns.db and S("buffs").enabled and GetWeaponEnchantInfo then
        local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
        local state = ok and (tostring(hasMain) .. tostring(hasOff)) or ""
        if state ~= PA.weaponState then
            PA.weaponState = state
            PA.Update("buffs")
        end
    end
end)

ns.OnLogin(PA.Apply)
ns.OnRefresh(PA.Apply)
