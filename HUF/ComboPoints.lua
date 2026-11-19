-- HUF: combo points (rogues; druids in cat form) on the target frame and on
-- the target's nameplate. The number may be secret: each point is a tiny
-- StatusBar with the range (i-1, i) that gets the number as its value, so
-- point i fills when the number reaches i, without HUF ever reading it.

local _, ns = ...
local Combo = {}
ns.Combo = Combo

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MAX = 10
local CP = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- the player's class can have combo points at all (cast bar room on plates)
function Combo.ClassCan()
    local _, class = UnitClass("player")
    return class == "ROGUE" or class == "DRUID"
end

-- combo points right now: rogue, or druid with energy (cat form)
function Combo.Applies()
    local _, class = UnitClass("player")
    if class == "ROGUE" then return true end
    if class == "DRUID" then
        local ok, pt = pcall(UnitPowerType, "player")
        return ok and not IsSecret(pt) and pt == ENERGY
    end
    return false
end

-- value (may be secret) and the most there can be
function Combo.Read()
    local okM, max = pcall(UnitPowerMax, "player", CP)
    if not okM or IsSecret(max) or not max or max <= 0 then max = 5 end
    max = math.min(MAX, max)
    local ok, v = pcall(UnitPower, "player", CP)
    if not ok or v == nil then
        if GetComboPoints then ok, v = pcall(GetComboPoints, "player", "target") end
        if not ok then v = 0 end
    end
    return v or 0, max
end

local function HostileTarget()
    local okE, e = pcall(UnitExists, "target")
    if not okE or IsSecret(e) or not e then return false end
    local okA, a = pcall(UnitCanAttack, "player", "target")
    if not okA or IsSecret(a) then return true end
    local okD, dead = pcall(UnitIsDeadOrGhost, "target")
    if okD and not IsSecret(dead) and dead then return false end
    return a and true or false
end

---------------------------------------------------------------------------
-- A row of points
---------------------------------------------------------------------------
function Combo.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.pips = {}
    for i = 1, MAX do
        local p = CreateFrame("StatusBar", nil, row)
        p:SetStatusBarTexture(FLAT)
        p:SetMinMaxValues(i - 1, i)
        p:SetValue(0)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetPoint("TOPLEFT", -1, 1)
        p.bg:SetPoint("BOTTOMRIGHT", 1, -1)
        row.pips[i] = p
    end
    row:Hide()
    return row
end

-- cfg: width (0: as wide as `fill`), height, gap, color, bgAlpha
function Combo.LayoutRow(row, cfg, max, fill)
    local gap, h = cfg.gap, cfg.height
    local total = (cfg.width and cfg.width > 0) and cfg.width or (fill or 100)
    local w = math.max(2, (total - gap * (max - 1)) / max)
    row:SetSize(w * max + gap * (max - 1), h)
    for i, p in ipairs(row.pips) do
        p:ClearAllPoints()
        if i <= max then
            p:SetSize(w, h)
            p:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + gap), 0)
            p:SetStatusBarColor(cfg.color.r, cfg.color.g, cfg.color.b)
            p.bg:SetColorTexture(0, 0, 0, cfg.bgAlpha)
            p:Show()
        else
            p:Hide()
        end
    end
    row.max = max
end

function Combo.SetValue(row, v)
    for i = 1, row.max or 5 do row.pips[i]:SetValue(v) end
end

-- shown? (an empty row hides when the number can be read)
local function Wanted(cfg, v)
    if not (cfg.enabled and Combo.Applies() and HostileTarget()) then return false end
    if cfg.hideEmpty and not IsSecret(v) and v == 0 then return false end
    return true
end

---------------------------------------------------------------------------
-- Target frame
---------------------------------------------------------------------------
local POS = {
    ABOVE = { "BOTTOM", "TOP", 1 }, BELOW = { "TOP", "BOTTOM", -1 },
    INSIDE_TOP = { "TOP", "TOP", -1 }, INSIDE_BOTTOM = { "BOTTOM", "BOTTOM", 1 },
}
Combo.POSITIONS = {
    { value = "ABOVE", text = "Above the frame" }, { value = "BELOW", text = "Below the frame" },
    { value = "INSIDE_TOP", text = "Inside, top" }, { value = "INSIDE_BOTTOM", text = "Inside, bottom" },
}

local function PlaceOnFrame(row, f, cfg)
    local p = POS[cfg.pos] or POS.ABOVE
    row:ClearAllPoints()
    row:SetPoint(p[1], f, p[2], cfg.x or 0, (cfg.y or 0))
    row:SetFrameLevel(f:GetFrameLevel() + 12)
end

local targetRow
local function UpdateTarget()
    local f = ns.singles and ns.singles.target
    if not f then return end
    local cfg = ns.db.units.target.combo
    if not cfg then return end
    targetRow = targetRow or Combo.NewRow(f)
    local v, max = Combo.Read()
    Combo.LayoutRow(targetRow, cfg, max, f.s and f.s.width or 175)
    PlaceOnFrame(targetRow, f, cfg)
    Combo.SetValue(targetRow, v)
    targetRow:SetShown(Wanted(cfg, v))
end

-- unlock preview: 3 of 5
function Combo.Preview(f)
    local cfg = ns.db.units.target.combo
    f.comboRow = f.comboRow or Combo.NewRow(f)
    if not (cfg and cfg.enabled and Combo.ClassCan()) then f.comboRow:Hide() return end
    Combo.LayoutRow(f.comboRow, cfg, 5, f.s and f.s.width or 175)
    PlaceOnFrame(f.comboRow, f, cfg)
    Combo.SetValue(f.comboRow, 3)
    f.comboRow:Show()
end

---------------------------------------------------------------------------
-- Nameplate of the target
---------------------------------------------------------------------------
local plateRow
local function TargetPlate()
    local NP = ns.Nameplates
    if not NP or not NP.plates then return end
    for unit, p in pairs(NP.plates) do
        local ok, is = pcall(UnitIsUnit, unit, "target")
        if ok and not IsSecret(is) and is then return p end
    end
end

-- room the cast bar leaves for the points (the same on every plate)
function Combo.PlateRoom()
    local s = ns.db.nameplates
    if not (s.comboShow and Combo.ClassCan()) then return 0 end
    return s.comboHeight + s.comboSpace
end

local function UpdatePlate()
    local s = ns.db.nameplates
    local p = s.enabled and TargetPlate()
    if not p then if plateRow then plateRow:Hide() end return end
    plateRow = plateRow or Combo.NewRow(UIParent)
    local cfg = { enabled = s.comboShow, width = 0, height = s.comboHeight, gap = s.comboGap,
        color = s.comboColor, bgAlpha = 0.7, hideEmpty = s.comboHideEmpty }
    local v, max = Combo.Read()
    plateRow:SetParent(p)
    Combo.LayoutRow(plateRow, cfg, max, s.width)
    plateRow:ClearAllPoints()
    local bs = s.borderSize or 1
    if p.mode == "NAME" then
        plateRow:SetPoint("TOP", p.name, "BOTTOM", 0, -(s.comboSpace + bs))
    else
        plateRow:SetPoint("TOP", p, "BOTTOM", 0, -(s.comboSpace + bs))
    end
    plateRow:SetFrameLevel(p:GetFrameLevel() + 8)
    Combo.SetValue(plateRow, v)
    plateRow:SetShown(Wanted(cfg, v))
end

function Combo.Update()
    if not ns.db then return end
    UpdateTarget()
    UpdatePlate()
end

---------------------------------------------------------------------------
-- Events (some only exist on some clients: registered with pcall)
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function Soon() C_Timer.After(0, Combo.Update) end
ev:SetScript("OnEvent", function(_, event, unit, powerType)
    if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") and powerType ~= "COMBO_POINTS" then return end
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" or event == "PLAYER_TARGET_CHANGED" then
        Soon()       -- after HUF's plates attached / detached
    else
        Combo.Update()
    end
end)
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_COMBO_POINTS",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD", "UNIT_FLAGS" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
ns.OnRefresh(function() if HUFDB and ns.db then Combo.Update() end end)
ns.OnLogin(function() Combo.Update() end)
