-- HUF: one unit frame. A secure button with
--   * a health bar and a power bar (mana / energy / rage), each with its own
--     texture, colour mode, background picture and thin border
--   * 9 text anchors per bar (top / middle / bottom x left / center / right),
--     each with its own template, font, size, outline, colour and offsets
--   * an optional portrait (3D, 2D or class icon; off by default)
--   * an optional frame background
-- The same code draws the previews of unlock mode (without the secure part).
--
-- Secure parts (size, attributes) only change outside combat; everything
-- drawn inside the button may change any time.

local _, ns = ...
local IsSecret, Bool = ns.IsSecret, ns.Bool

local Frame = {}
ns.Frame = Frame
ns.allFrames = {}

local BARS = { "health", "power" }
local FLAT = "Interface\\Buttons\\WHITE8X8"
local RAMP = ns.MEDIA .. "Bars\\Ramp"
Frame.BARS = BARS

local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CONNECTION", "UNIT_FACTION", "UNIT_FLAGS",
    "UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
    "UNIT_HEAL_PREDICTION",
}
local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_HEALTH_FREQUENT = true }
local POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }
local PORTRAIT_EVENTS = { UNIT_PORTRAIT_UPDATE = true, UNIT_MODEL_CHANGED = true }

---------------------------------------------------------------------------
-- Unit state helpers (secret-safe)
---------------------------------------------------------------------------
local function Exists(unit)
    if not unit then return false end
    local ok, v = pcall(UnitExists, unit)
    return ok and Bool(v, true)
end

local function IsOffline(unit)
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not (okP and Bool(isPlayer)) then return false end
    local ok, c = pcall(UnitIsConnected, unit)
    return ok and not IsSecret(c) and c == false
end
Frame.IsOffline = IsOffline

local OFFLINE_GREY = { r = 0.74, g = 0.74, b = 0.76 }   -- light: clearly not a class colour
local DEAD_GREY = { r = 0.45, g = 0.45, b = 0.45 }

local function IsGray(unit)
    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
    if okD and Bool(dead) then return true end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and Bool(isPlayer) then
        local ok, c = pcall(UnitIsConnected, unit)
        if ok and not IsSecret(c) and c == false then return true end
    elseif UnitIsTapDenied then
        local ok, t = pcall(UnitIsTapDenied, unit)
        if ok and Bool(t) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- a border of 4 lines around `target`, drawn outside it (size may be 0.5)
local function MakeBorder(parent)
    local b = { lines = {} }
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        b.lines[i] = t
    end
    return b
end

local function LayoutBorder(b, target, size, c, alpha)
    local l = b.lines
    for _, t in ipairs(l) do
        t:ClearAllPoints()
        t:SetShown(size > 0)
        t:SetColorTexture(c.r, c.g, c.b, alpha or 1)
    end
    if size <= 0 then return end
    l[1]:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -size, 0)
    l[1]:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", size, 0)
    l[1]:SetHeight(size)
    l[2]:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -size, 0)
    l[2]:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", size, 0)
    l[2]:SetHeight(size)
    l[3]:SetPoint("TOPRIGHT", target, "TOPLEFT", 0, 0)
    l[3]:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", 0, 0)
    l[3]:SetWidth(size)
    l[4]:SetPoint("TOPLEFT", target, "TOPRIGHT", 0, 0)
    l[4]:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", 0, 0)
    l[4]:SetWidth(size)
end
Frame.MakeBorder, Frame.LayoutBorder = MakeBorder, LayoutBorder

-- a background picture (None / Plain / tiled or stretched texture)
local function SetBackground(tex, name, color, alpha)
    local e = ns.Background(name)
    if not e or e.name == "None" then tex:Hide() return end
    tex:Show()
    if not e.path then
        tex:SetColorTexture(color.r, color.g, color.b, alpha)
        return
    end
    if e.tile then
        tex:SetTexture(e.path, "REPEAT", "REPEAT")
        tex:SetHorizTile(true)
        tex:SetVertTile(true)
    else
        tex:SetTexture(e.path)
        tex:SetHorizTile(false)
        tex:SetVertTile(false)
    end
    tex:SetVertexColor(color.r, color.g, color.b, alpha)
end
Frame.SetBackground = SetBackground

local function NewFont(parent)
    -- a font right away: SetText on a font string without one is an error
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.ApplyFont(fs, "GLOBAL", 12, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

local function OnEnter(self)
    if not (self.s and self.s.tooltip) then return end
    if self.fake then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("HUF: " .. (self.previewTitle or "Preview"))
        GameTooltip:AddLine(ns.unlocked and "Drag to move. Right-click: settings of this frame." or "Preview", 1, 1, 1, true)
        GameTooltip:Show()
    elseif self.hunit and Exists(self.hunit) then
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
        else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
        pcall(GameTooltip.SetUnit, GameTooltip, self.hunit)
        GameTooltip:Show()
    end
end
local function OnLeave() GameTooltip:Hide() end

local function OnUnitEvent(ev, event)
    local f = ev.owner
    if not f.hunit or f.fake then return end
    if event == "UNIT_HEAL_PREDICTION" then
        Frame.UpdateHealPred(f)
    elseif HEALTH_EVENTS[event] then
        Frame.UpdateHealth(f)
        Frame.UpdateTexts(f)
    elseif POWER_EVENTS[event] then
        Frame.UpdatePower(f)
        Frame.UpdateTexts(f)
    elseif PORTRAIT_EVENTS[event] then
        Frame.UpdatePortrait(f)
    else
        Frame.Update(f)
    end
end

local function BuildBar(f, which)
    local bar = CreateFrame("StatusBar", nil, f)
    bar.which = which
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    -- gradient layers (GRADIENT mode): the bar itself in the left colour, a
    -- copy with a transparent-to-opaque ramp in the right colour, and a copy
    -- with the bar texture multiplied over both for its shading. All three
    -- share the value; the game clips each texture to the filled part, so
    -- the colour at any point depends on its place in the whole bar, also
    -- while the value itself is secret.
    bar.grad = CreateFrame("StatusBar", nil, f)
    bar.shade = CreateFrame("StatusBar", nil, f)
    bar.edge = CreateFrame("Frame", nil, f)       -- border, above the bar
    bar.border = MakeBorder(bar.edge)
    bar.texts = {}
    for _, a in ipairs(ns.ANCHORS) do bar.texts[a] = NewFont(f.textLayer) end
    return bar
end

function Frame.Build(f, key, secure)
    f.key = key
    f.s = ns.db.units[key]
    f.secure = secure

    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)

    f.textLayer = CreateFrame("Frame", nil, f)    -- every text, above both bars
    f.textLayer:SetAllPoints()

    f.bars = {}
    for _, which in ipairs(BARS) do f.bars[which] = BuildBar(f, which) end

    -- incoming heals: two bars (mine, others) that start where the health
    -- fill ends and are as long as the whole bar, inside a clip frame that
    -- reaches past the bar's end by the allowed overheal
    local hp = { clip = CreateFrame("Frame", nil, f) }
    hp.clip:SetClipsChildren(true)
    hp.mine = CreateFrame("StatusBar", nil, hp.clip)
    hp.other = CreateFrame("StatusBar", nil, hp.clip)
    for _, b in ipairs({ hp.mine, hp.other }) do
        b:SetStatusBarTexture(FLAT)
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
    end
    hp.clip:Hide()
    f.healPred = hp
    f.health, f.power = f.bars.health, f.bars.power

    -- portrait (off by default)
    local p = CreateFrame("Frame", nil, f)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0.03, 0.03, 0.04, 1)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.model = CreateFrame("PlayerModel", nil, p)
    p.model:SetAllPoints()
    p.edge = CreateFrame("Frame", nil, f)
    p.border = MakeBorder(p.edge)
    f.portrait = p

    f:HookScript("OnEnter", OnEnter)
    f:HookScript("OnLeave", OnLeave)

    f.ev = CreateFrame("Frame")
    f.ev.owner = f
    f.ev:SetScript("OnEvent", OnUnitEvent)

    -- buff / debuff icons
    f.auraRows = {
        debuffs = ns.Auras.NewRow(f, key .. " debuffs"),
        buffs = ns.Auras.NewRow(f, key .. " buffs"),
    }

    Frame.LayoutInner(f)

    if secure then
        Frame.SetupSecure(f)
        ns.allFrames[#ns.allFrames + 1] = f
    end
    return f
end

function Frame.CreateSingle(key, unit, name)
    local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    f.hufLabel = key
    f:SetAttribute("unit", unit)
    Frame.Build(f, key, true)
    Frame.SetUnit(f, unit)
    f:HookScript("OnShow", function(self) Frame.Update(self) end)
    return f
end

---------------------------------------------------------------------------
-- Clicks: left = target, right = unit menu
---------------------------------------------------------------------------
local proxyCount = 0
-- 12.x gates the plain "togglemenu" on unit buttons; a hidden secure action
-- button opens the menu instead (the unit button runs "/click <proxy>").
local function MenuProxy(f)
    if f.menuProxy then return f.menuProxy end
    proxyCount = proxyCount + 1
    local name = "HUFMenuProxy" .. proxyCount
    local p = CreateFrame("Button", name, f, "SecureActionButtonTemplate")
    p:SetSize(1, 1)
    p:SetAlpha(0)
    p:EnableMouse(false)
    p:RegisterForClicks("AnyUp", "AnyDown")
    p:SetAttribute("type", "togglemenu")
    for i = 1, 5 do p:SetAttribute("type" .. i, "togglemenu") end
    p:SetAttribute("useparent-unit", true)
    p:SetAttribute("useOnKeyDown", false)
    p.macro = "/click " .. name
    f.menuProxy = p
    return p
end

function Frame.ApplyMenu(f)
    if not f.secure or InCombatLockdown() then return end
    if ns.db.global.menuMode == "DIRECT" then
        f:SetAttribute("*macrotext2", nil)
        f:SetAttribute("*type2", "togglemenu")
    else
        local p = MenuProxy(f)
        -- a click-cast binding on plain right-click keeps "type2"
        if not (f.hufCCSet and f.hufCCSet.type2) then f:SetAttribute("type2", nil) end
        f:SetAttribute("*type2", "macro")
        f:SetAttribute("*macrotext2", p.macro)
    end
end

function Frame.SecureClicks(f)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("useOnKeyDown", false)      -- clicks and click-cast keys act on release
    f:SetAttribute("*type1", "target")
    Frame.ApplyMenu(f)
    if ns.db.global.clickCast then
        if type(ClickCastFrames) ~= "table" then ClickCastFrames = {} end
        ClickCastFrames[f] = true
    end
end

function Frame.Label(f) return f.hufLabel or f.key or "?" end

function Frame.SetupSecure(f)
    ns.RunOOC("clicks:" .. tostring(f), function() Frame.SecureClicks(f) end)
    f:HookScript("OnAttributeChanged", function(self, name, value)
        if name == "unit" then Frame.SetUnit(self, value) end
    end)
    f:HookScript("PreClick", function(self, button)
        ns.Log("click", "%s %s on unit %s (type=%s, menu=%s)", Frame.Label(self), button, self:GetAttribute("unit"),
            self:GetAttribute(button == "RightButton" and "*type2" or "*type1"), ns.db.global.menuMode)
    end)
    f:HookScript("OnShow", function(self) ns.Log("show", "%s shown (unit %s)", Frame.Label(self), self.hunit) end)
    f:HookScript("OnHide", function(self) ns.Log("show", "%s hidden (unit %s)", Frame.Label(self), self.hunit) end)
end

---------------------------------------------------------------------------
-- Unit and events
---------------------------------------------------------------------------
local function Poll(ev, elapsed)
    ev.t = (ev.t or 0) + elapsed
    if ev.t < 0.2 then return end
    ev.t = 0
    local f = ev.owner
    if f:IsVisible() then
        Frame.Update(f)
        ev.a = (ev.a or 0) + 1
        if ev.a >= 3 then ev.a = 0 Frame.RefreshAuras(f) end   -- auras ~ every 0.6 s
    end
end

function Frame.SetUnit(f, unit)
    if IsSecret(unit) then unit = nil end
    if f.hunit == unit and f.evUnit == unit then
        if unit then Frame.Update(f) end
        return
    end
    ns.Log("unit", "%s: unit %s -> %s", Frame.Label(f), f.hunit, unit)
    f.hunit = unit
    f.evUnit = unit
    local ev = f.ev
    ev:UnregisterAllEvents()
    ev:SetScript("OnUpdate", nil)
    if not unit then Frame.SetAuraUnit(f, nil) return end
    for _, e in ipairs(UNIT_EVENTS) do pcall(ev.RegisterUnitEvent, ev, e, unit) end
    Frame.SetAuraUnit(f, unit)
    -- target of target sends no unit events of its own: looked at 5x a second
    local info = ns.UNIT_BY_KEY[f.key]
    if info and info.polled then ev:SetScript("OnUpdate", Poll) end
    Frame.Update(f)
end

---------------------------------------------------------------------------
-- Layout (allowed in combat: nothing secure)
---------------------------------------------------------------------------
local JUSTIFY = { LEFT = "LEFT", RIGHT = "RIGHT" }
local function Justify(point)
    if point:find("LEFT") then return "LEFT" end
    if point:find("RIGHT") then return "RIGHT" end
    return "CENTER"
end

local function LayoutTexts(f, which)
    local bar = f.bars[which]
    local set = f.s.texts[which]
    local w = f.barWidth or f.s.width
    for _, a in ipairs(ns.ANCHORS) do
        local t = set[a]
        local fs = bar.texts[a]
        ns.ApplyFont(fs, t.font, t.size, t.outline)
        fs:ClearAllPoints()
        local inset = (a:find("LEFT") and 2) or (a:find("RIGHT") and -2) or 0
        fs:SetPoint(a, bar, a, inset + t.x, t.y)
        fs:SetJustifyH(Justify(a))
        fs:SetWidth(0)
        fs:SetShown(t.text ~= nil and t.text ~= "")
    end
end

function Frame.LayoutInner(f)
    local s = f.s
    local W, H = s.width, s.height
    local p = s.portrait
    local pw = 0

    -- frame background
    SetBackground(f.bg, s.frameBg, s.frameBgColor, s.frameBgAlpha)
    f.bg:ClearAllPoints()
    f.bg:SetPoint("TOPLEFT", -s.framePad, s.framePad)
    f.bg:SetPoint("BOTTOMRIGHT", s.framePad, -s.framePad)

    -- portrait: a square of the frame's height at one side
    local por = f.portrait
    por:ClearAllPoints()
    if p.enabled then
        pw = H
        por:SetSize(H, H)
        if p.side == "RIGHT" then por:SetPoint("TOPRIGHT") else por:SetPoint("TOPLEFT") end
        LayoutBorder(por.border, por, p.borderSize, p.borderColor, 1)
        por:Show()
        por.edge:Show()
    else
        por:Hide()
        por.edge:Hide()
    end
    local left = (p.enabled and p.side ~= "RIGHT") and (pw + p.gap) or 0
    local right = (p.enabled and p.side == "RIGHT") and (pw + p.gap) or 0
    f.barWidth = W - left - right

    -- bars: health on top, power (8 px) below
    local pb = s.power
    local showPower = pb.enabled and f.hasPower ~= false
    local h, pwr = f.health, f.power
    h:ClearAllPoints()
    pwr:ClearAllPoints()
    h:SetPoint("TOPLEFT", left, 0)
    h:SetPoint("TOPRIGHT", -right, 0)
    if showPower then
        h:SetHeight(math.max(1, H - pb.size - pb.gap))
        pwr:SetPoint("BOTTOMLEFT", left, 0)
        pwr:SetPoint("BOTTOMRIGHT", -right, 0)
        pwr:SetHeight(pb.size)
    else
        h:SetHeight(H)
    end
    pwr:SetShown(showPower)
    pwr.edge:SetShown(showPower)

    for _, which in ipairs(BARS) do
        local b = s[which]
        local bar = f.bars[which]
        local gradient = b.colorMode == "GRADIENT"
        bar:SetStatusBarTexture(gradient and FLAT or ns.TexturePath(b.texture))
        bar.grad:SetStatusBarTexture(RAMP)
        bar.shade:SetStatusBarTexture(ns.TexturePath(b.texture))
        local st = bar.shade:GetStatusBarTexture()
        if st and st.SetBlendMode then st:SetBlendMode("MOD") end
        bar.shade:SetStatusBarColor(1, 1, 1)
        for _, layer in ipairs({ bar, bar.grad, bar.shade }) do
            layer:SetOrientation("HORIZONTAL")
            layer:SetReverseFill(b.reverse)
            local t = layer:GetStatusBarTexture()
            if t then t:SetHorizTile(false) t:SetVertTile(false) end
        end
        for i, layer in ipairs({ bar.grad, bar.shade }) do
            layer:ClearAllPoints()
            layer:SetAllPoints(bar)
            layer:SetFrameLevel(bar:GetFrameLevel() + i)
            layer:SetShown(gradient and bar:IsShown())
        end
        SetBackground(bar.bg, b.bgTexture, b.bgColor, b.bgAlpha)
        bar.edge:SetAllPoints(bar)
        bar.edge:SetFrameLevel(bar:GetFrameLevel() + 3)
        LayoutBorder(bar.border, bar, b.borderSize, b.borderColor, b.borderAlpha)
        LayoutTexts(f, which)
    end
    Frame.LayoutHealPred(f)
    f.textLayer:SetFrameLevel(math.max(h:GetFrameLevel(), pwr:GetFrameLevel()) + 5)
    por.edge:SetFrameLevel(por:GetFrameLevel() + 2)
    Frame.LayoutAuras(f)
end

---------------------------------------------------------------------------
-- Buffs and debuffs (Auras.lua does the work)
---------------------------------------------------------------------------
-- where a row sits: point on the row, point on the frame, growth, offset sign
local AURA_POS = {
    BELOW_LEFT  = { "TOPLEFT", "BOTTOMLEFT", "RIGHT", "DOWN", 0, -1 },
    BELOW_RIGHT = { "TOPRIGHT", "BOTTOMRIGHT", "LEFT", "DOWN", 0, -1 },
    ABOVE_LEFT  = { "BOTTOMLEFT", "TOPLEFT", "RIGHT", "UP", 0, 1 },
    ABOVE_RIGHT = { "BOTTOMRIGHT", "TOPRIGHT", "LEFT", "UP", 0, 1 },
    LEFT        = { "TOPRIGHT", "TOPLEFT", "LEFT", "DOWN", -1, 0 },
    RIGHT       = { "TOPLEFT", "TOPRIGHT", "RIGHT", "DOWN", 1, 0 },
}
Frame.AURA_POS = AURA_POS

local function AuraCfg(f, which)
    local a = f.s[which]
    local pos = AURA_POS[a.position] or AURA_POS.BELOW_LEFT
    return {
        enabled = a.enabled and f.s.enabled,
        kind = which == "debuffs" and "HARMFUL" or "HELPFUL",
        mine = a.mine, size = a.size, gap = a.gap, perRow = a.perRow, rows = a.rows,
        countSize = a.countSize, timer = a.timer, timerText = a.timerText, timerSize = a.timerSize,
        anchor = pos[1], growH = pos[3], growV = pos[4],
        point = { pos[1], f, pos[2], a.x + pos[5] * a.offset, a.y + pos[6] * a.offset },
    }
end

function Frame.LayoutAuras(f)
    if not f.auraRows then return end
    for which, row in pairs(f.auraRows) do
        local cfg = AuraCfg(f, which)
        if f.secure then
            row:Configure(cfg)
        else
            row:Preview(cfg, which == "debuffs" and 3 or 4)     -- unlock mode
        end
    end
end

function Frame.SetAuraUnit(f, unit)
    if not f.auraRows or not f.secure then return end
    for _, row in pairs(f.auraRows) do row:SetUnit(unit) end
end

function Frame.RefreshAuras(f)
    if not f.auraRows or not f.secure then return end
    for _, row in pairs(f.auraRows) do row:Refresh() end
end

function Frame.LayoutSecure(f)
    if f.secure and InCombatLockdown() then return false end
    f:SetSize(f.s.width, f.s.height)
    if f.secure then Frame.ApplyMenu(f) end
    return true
end

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------
-- percent 0..1 of a bar when readable, else nil
local function Fraction(f, which, ptype)
    if f.fake then
        if which == "health" then return f.fake.hp / f.fake.maxhp end
        return f.fake.maxpower > 0 and f.fake.power / f.fake.maxpower or 0
    end
    local cur, max
    if which == "health" then cur, max = ns.Safe(UnitHealth, f.hunit), ns.Safe(UnitHealthMax, f.hunit)
    else cur, max = ns.Safe(UnitPower, f.hunit, ptype), ns.Safe(UnitPowerMax, f.hunit, ptype) end
    if cur and max and max > 0 then return cur / max end
    return nil
end

function Frame.ColorBar(f, which, ptype, ptoken)
    local b = f.s[which]
    local bar = f.bars[which]
    local fake, unit = f.fake, f.hunit
    bar.grad:SetAlpha(1)
    if which == "health" then
        -- offline: a full bar in light grey, never a gradient
        local offline
        if fake then offline = fake.offline else offline = IsOffline(unit) end
        if offline then
            bar.grad:SetAlpha(0)
            bar:SetStatusBarColor(OFFLINE_GREY.r, OFFLINE_GREY.g, OFFLINE_GREY.b)
            return
        end
    end
    if b.deadGray and which == "health" then
        local gray
        if fake then gray = fake.dead else gray = IsGray(unit) end
        if gray then
            bar.grad:SetAlpha(0)
            bar:SetStatusBarColor(DEAD_GREY.r, DEAD_GREY.g, DEAD_GREY.b)
            return
        end
    end
    local mode = b.colorMode
    if mode == "GRADIENT" then
        local a, z = ns.GradientColors(b)
        bar:SetStatusBarColor(a.r, a.g, a.b)
        bar.grad:SetStatusBarColor(z.r, z.g, z.b)
        return
    end
    if mode == "STATUS" then
        if fake then
            local c = ns.StatusColor(b, Fraction(f, which) or 1)
            bar:SetStatusBarColor(c.r, c.g, c.b)
            return
        end
        local ok, r, g, bl = ns.UnitStatusColor(unit, b, which == "power", ptype)
        if ok then bar:SetStatusBarColor(r, g, bl) return end
    end
    local c
    if mode == "CLASS" then
        if fake then c = ns.FakeColor(fake) else c = ns.UnitColor(unit, b.npcReaction) end
    elseif mode == "TYPE" then
        c = which == "health" and ns.HealthTypeColor() or ns.PowerColor(ptoken)
    end
    c = c or b.color
    bar:SetStatusBarColor(c.r, c.g, c.b)
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
-- the same range and value on a bar and its gradient layers (may be secret)
local function SetValues(bar, max, cur)
    for _, layer in ipairs({ bar, bar.grad, bar.shade }) do
        pcall(layer.SetMinMaxValues, layer, 0, max)
        pcall(layer.SetValue, layer, cur)
    end
end

function Frame.UpdateHealth(f)
    local bar = f.health
    if f.fake then
        if f.fake.offline then SetValues(bar, 1, 1)
        else SetValues(bar, f.fake.maxhp, f.fake.dead and 0 or f.fake.hp) end
    elseif f.hunit and IsOffline(f.hunit) then
        SetValues(bar, 1, 1)
    elseif f.hunit then
        local okM, max = pcall(UnitHealthMax, f.hunit)
        local okC, cur = pcall(UnitHealth, f.hunit)
        if okM and okC then SetValues(bar, max, cur) end
    end
    Frame.ColorBar(f, "health")
    Frame.UpdateHealPred(f)
end

---------------------------------------------------------------------------
-- Incoming heals (the game's heal prediction; values may be secret, they
-- only go to SetMinMaxValues / SetValue)
---------------------------------------------------------------------------
function Frame.LayoutHealPred(f)
    local hp, c = f.healPred, f.s.healPred
    if not hp then return end
    if not (c and c.enabled) then hp.clip:Hide() return end
    local h = f.health
    local rev = f.s.health.reverse
    local w = f.barWidth or f.s.width
    local over = math.max(0, c.overheal or 0) * w / 100
    hp.clip:ClearAllPoints()
    if rev then
        hp.clip:SetPoint("TOPLEFT", h, "TOPLEFT", -over, 0)
        hp.clip:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    else
        hp.clip:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
        hp.clip:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", over, 0)
    end
    hp.clip:SetFrameLevel(h:GetFrameLevel() + 2)     -- above the fill and its shading, below the border
    local tex = ns.TexturePath(f.s.health.texture)
    local fill = h:GetStatusBarTexture()
    local a, b = rev and "TOPRIGHT" or "TOPLEFT", rev and "TOPLEFT" or "TOPRIGHT"
    local a2, b2 = rev and "BOTTOMRIGHT" or "BOTTOMLEFT", rev and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local prev = fill
    for i, bar in ipairs({ hp.mine, hp.other }) do
        bar:SetStatusBarTexture(tex)
        bar:SetOrientation("HORIZONTAL")
        bar:SetReverseFill(rev)
        bar:ClearAllPoints()
        bar:SetPoint(a, prev, b, 0, 0)
        bar:SetPoint(a2, prev, b2, 0, 0)
        bar:SetWidth(w)
        local alpha = i == 1 and c.alpha or c.alpha * 0.7
        bar:SetStatusBarColor(c.color.r, c.color.g, c.color.b, alpha)
        prev = bar:GetStatusBarTexture()
    end
    hp.clip:Show()
    Frame.UpdateHealPred(f)
end

local function Calculator(hp)
    if hp.calc ~= nil then return hp.calc end
    hp.calc = false
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        local ok, calc = pcall(CreateUnitHealPredictionCalculator)
        if ok and calc then
            -- clamp at maximum health, not at the missing part: the clip frame
            -- decides how far past full the bars may show
            local modes = Enum and Enum.UnitIncomingHealClampMode
            if calc.SetIncomingHealClampMode and modes and modes.MaximumHealth then
                pcall(calc.SetIncomingHealClampMode, calc, modes.MaximumHealth)
            end
            hp.calc = calc
        end
    end
    return hp.calc
end

function Frame.UpdateHealPred(f)
    local hp, c = f.healPred, f.s.healPred
    if not hp or not (c and c.enabled) then return end
    local mine, others, max
    if f.fake then
        max, mine, others = f.fake.maxhp, (not f.fake.dead and not f.fake.offline) and f.fake.incoming or 0, 0
    elseif f.hunit and not IsGray(f.hunit) then
        local unit = f.hunit
        local okM, m = pcall(UnitHealthMax, unit)
        max = okM and m or nil
        local calc = Calculator(hp)
        if calc then
            local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calc)
            if ok then
                local okI, _, my, oth = pcall(calc.GetIncomingHeals, calc)
                if okI then mine, others = my, oth end
            end
        elseif UnitGetIncomingHeals then
            local okA, all = pcall(UnitGetIncomingHeals, unit)
            local okP, my = pcall(UnitGetIncomingHeals, unit, "player")
            if okA and okP and not IsSecret(all) and not IsSecret(my) then
                mine, others = my or 0, math.max(0, (all or 0) - (my or 0))
            elseif okA then
                mine, others = all, 0
            end
        end
    end
    if max == nil then mine, others, max = 0, 0, 1 end
    for i, bar in ipairs({ hp.mine, hp.other }) do
        if not pcall(bar.SetMinMaxValues, bar, 0, max) then bar:SetMinMaxValues(0, 1) end
        if not pcall(bar.SetValue, bar, (i == 1 and mine or others) or 0) then bar:SetValue(0) end
    end
end

function Frame.UpdatePower(f)
    local pb = f.s.power
    if not pb.enabled then return end
    local bar = f.power
    local has, ptype, token
    if f.fake then
        has = f.fake.maxpower > 0
        token = f.fake.powerToken or "MANA"
        if has then SetValues(bar, f.fake.maxpower, f.fake.power) end
    else
        local unit = f.hunit
        if not unit then return end
        local ok, pt, ptoken = pcall(UnitPowerType, unit)
        if ok and not IsSecret(pt) then ptype = pt end
        if ok and not IsSecret(ptoken) then token = ptoken end
        has = ns.HasPower(unit)
        if has then
            local okM, max = pcall(UnitPowerMax, unit, ptype)
            local okC, cur = pcall(UnitPower, unit, ptype)
            if okM and okC then SetValues(bar, max, cur) end
        end
    end
    has = has and true or false
    if (f.hasPower ~= false) ~= has then
        f.hasPower = has
        Frame.LayoutInner(f)
    end
    Frame.ColorBar(f, "power", ptype, token)
end

function Frame.UpdateTexts(f)
    for _, which in ipairs(BARS) do
        local bar = f.bars[which]
        local set = f.s.texts[which]
        for _, a in ipairs(ns.ANCHORS) do
            local t = set[a]
            if t.text ~= "" then
                local fs = bar.texts[a]
                ns.SetTemplateText(fs, f, t.text)
                local c, alpha = nil, 1
                if t.colorMode == "STATUS" then
                    -- health status colours of this frame's health bar;
                    -- "Offline" / "Dead" / "Ghost" always readable in light grey
                    local word
                    if f.fake then word = f.fake.offline or f.fake.dead
                    else word = ns.StatusWord and ns.StatusWord(f.hunit) end
                    if word then
                        c = OFFLINE_GREY
                    elseif f.fake then
                        local pct = f.fake.dead and 0 or f.fake.hp / f.fake.maxhp
                        c = ns.StatusColor(f.s.health, pct)
                        if t.hideFull and pct >= 1 then alpha = 0 end
                    else
                        local ok, r, g, bl, a = ns.UnitStatusColor(f.hunit, f.s.health, false, nil, t.hideFull)
                        if ok and pcall(fs.SetTextColor, fs, r, g, bl, a) then c = false
                        elseif ok then pcall(fs.SetTextColor, fs, r, g, bl) c = false end
                    end
                elseif t.colorMode == "CUSTOM" then c = t.color
                elseif t.colorMode == "ACCENT" then c = ns.AccentColor()
                elseif t.colorMode == "CLASS" then
                    if f.fake then c = ns.FakeColor(f.fake) else c = ns.UnitColor(f.hunit, true) end
                end
                if c ~= false then
                    c = c or { r = 1, g = 1, b = 1 }
                    fs:SetTextColor(c.r, c.g, c.b, alpha)
                end
            end
        end
    end
end

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function Frame.UpdatePortrait(f)
    local p = f.s.portrait
    local por = f.portrait
    if not p.enabled then return end
    local unit, fake = f.hunit, f.fake
    if p.mode == "3D" and not fake then
        por.tex:Hide()
        por.model:Show()
        pcall(por.model.SetUnit, por.model, unit)
        pcall(por.model.SetPortraitZoom, por.model, 1)
        pcall(por.model.SetCamDistanceScale, por.model, 1)
        return
    end
    por.model:Hide()
    por.tex:Show()
    local class
    if fake then class = fake.class
    else
        local ok, _, c = pcall(UnitClass, unit)
        if ok and not IsSecret(c) then class = c end
    end
    if (p.mode == "CLASS" or fake) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        por.tex:SetTexture(CLASS_ICONS)
        por.tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    elseif fake then
        por.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        por.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        por.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if SetPortraitTexture then pcall(SetPortraitTexture, por.tex, unit) end
    end
end

function Frame.Update(f)
    if not f.fake and not (f.hunit and Exists(f.hunit)) then return end
    Frame.UpdateHealth(f)
    Frame.UpdatePower(f)
    Frame.UpdateTexts(f)
    Frame.UpdatePortrait(f)
    f:SetAlpha(f.s.alpha)
end

function Frame.Apply(f)
    f.s = ns.db.units[f.key]
    Frame.LayoutSecure(f)
    Frame.LayoutInner(f)
    Frame.Update(f)
end

---------------------------------------------------------------------------
-- Every frame at once
---------------------------------------------------------------------------
function ns.ForEachFrame(fn)
    for _, f in ipairs(ns.allFrames) do fn(f) end
end

function ns.UpdateAllNames()
    ns.ForEachFrame(function(f) if f:IsVisible() then Frame.UpdateTexts(f) end end)
    if ns.UpdatePreviews then ns.UpdatePreviews() end
end

local function UpdateUnit(unit)
    ns.ForEachFrame(function(f) if f.hunit == unit then Frame.Update(f) end end)
end
ns.UpdateUnit = UpdateUnit

local function RefreshUnitAuras(unit)
    ns.ForEachFrame(function(f) if f.hunit == unit then Frame.RefreshAuras(f) end end)
end

ns.On("PLAYER_TARGET_CHANGED", function()
    UpdateUnit("target")
    UpdateUnit("targettarget")
    RefreshUnitAuras("target")
    RefreshUnitAuras("targettarget")
end)
ns.On("UNIT_TARGET", function(unit)
    if unit == "target" then
        UpdateUnit("targettarget")
        RefreshUnitAuras("targettarget")
    end
end)
-- the pet came, went or changed
ns.On("UNIT_PET", function(unit)
    if unit == "player" then
        UpdateUnit("pet")
        RefreshUnitAuras("pet")
    end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
    ns.ForEachFrame(function(f) if f.hunit then Frame.Update(f) end end)
end)
