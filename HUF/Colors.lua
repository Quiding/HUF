-- HUF: bar colours. Modes: STATIC (one colour), GRADIENT (two colours),
-- CLASS (class, NPCs in reaction colours), STATUS (green above 75%, amber
-- above 40%, red below), TYPE (health green, mana blue, rage red, energy
-- yellow, ...). Status colours are worked out by the game (colour curves), so
-- they also work while a value is secret.

local _, ns = ...
local IsSecret, Bool = ns.IsSecret, ns.Bool

local REACTION = {
    hostile  = { r = 0.85, g = 0.20, b = 0.20 },
    neutral  = { r = 0.93, g = 0.80, b = 0.20 },
    friendly = { r = 0.25, g = 0.78, b = 0.35 },
}
local HEALTH_GREEN = { r = 0.20, g = 0.75, b = 0.30 }
ns.GRAY = { r = 0.45, g = 0.45, b = 0.45 }

-- classes the game may not list a colour for
local CLASS_FALLBACK = { BARD = { r = 0.93, g = 0.47, b = 0.80 } }
function ns.ClassColor(class)
    if not class or IsSecret(class) then return nil end
    return (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        or CLASS_FALLBACK[class]
end

-- class colour for players, reaction colour for NPCs (nil if not readable)
function ns.UnitColor(unit, npcReaction)
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and Bool(isPlayer) then
        local ok, _, class = pcall(UnitClass, unit)
        if ok then return ns.ClassColor(class) end
        return nil
    end
    if npcReaction == false then return nil end
    local ok, reaction = pcall(UnitReaction, unit, "player")
    if ok and reaction and not IsSecret(reaction) then
        if reaction <= 3 then return REACTION.hostile end
        if reaction == 4 then return REACTION.neutral end
        return REACTION.friendly
    end
    return nil
end

function ns.FakeColor(fake)
    if fake.class then return ns.ClassColor(fake.class) end
    return fake.hostile and REACTION.hostile or REACTION.neutral
end

local POWER_FALLBACK = {
    MANA = { r = 0.25, g = 0.45, b = 1.00 }, RAGE = { r = 0.90, g = 0.15, b = 0.15 },
    ENERGY = { r = 1.00, g = 0.85, b = 0.20 }, FOCUS = { r = 1.00, g = 0.55, b = 0.25 },
}
function ns.PowerColor(token)
    if token and not IsSecret(token) then
        -- power bars always in the game's colours (own power colours were removed)
        local c = (PowerBarColor and PowerBarColor[token]) or POWER_FALLBACK[token]
        if c then return c end
    end
    return POWER_FALLBACK.MANA
end
function ns.HealthTypeColor() return HEALTH_GREEN end

-- the gradient colours of a bar (an accent-linked colour follows the accent)
function ns.GradientColors(b)
    local a = ns.AccentColor()
    return b.gradStartAccent and a or b.gradStart, b.gradEndAccent and a or b.gradEnd
end

local function Lerp(a, b, t) return a + (b - a) * t end
function ns.LerpColor(a, b, t)
    t = math.max(0, math.min(1, t))
    return { r = Lerp(a.r, b.r, t), g = Lerp(a.g, b.g, t), b = Lerp(a.b, b.b, t) }
end

-- STATUS colour of a known fraction 0..1
function ns.StatusColor(b, pct)
    if pct > 0.75 then return b.high end
    if pct > 0.40 then return b.mid end
    return b.low
end

---------------------------------------------------------------------------
-- Step curves for STATUS (the game evaluates them, secrets included)
---------------------------------------------------------------------------
local curves = {}
local function Key(b)
    local function k(c) return ("%.3f,%.3f,%.3f"):format(c.r, c.g, c.b) end
    return k(b.low) .. "|" .. k(b.mid) .. "|" .. k(b.high)
end
local function StatusCurve(b, hideFull)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local key = Key(b) .. (hideFull and "|H" or "")
    if curves[key] then return curves[key] end
    local curve = C_CurveUtil.CreateColorCurve()
    if Enum and Enum.LuaCurveType and curve.SetType then
        curve:SetType(Enum.LuaCurveType.Step or Enum.LuaCurveType.Linear)
    end
    local function P(x, c, a) curve:AddPoint(x, CreateColor(c.r, c.g, c.b, a or 1)) end
    -- steps (also right with a linear curve: the jumps are 0.0001 wide)
    P(0, b.low); P(0.4, b.low); P(0.4001, b.mid); P(0.75, b.mid); P(0.7501, b.high)
    if hideFull then
        P(0.9999, b.high); P(1, b.high, 0)      -- full health: transparent
    else
        P(1, b.high)
    end
    curves[key] = curve
    return curve
end

-- ok, r, g, b, a of a live unit's health / power status. ok is plain; r, g,
-- b, a may be secret: only hand them to a setter. hideFull: a = 0 at 100%.
function ns.UnitStatusColor(unit, b, isPower, ptype, hideFull)
    local curve = StatusCurve(b, hideFull)
    if curve then
        local ok, color
        if isPower then
            if UnitPowerPercent then ok, color = pcall(UnitPowerPercent, unit, ptype, true, curve) end
        elseif UnitHealthPercent then
            ok, color = pcall(UnitHealthPercent, unit, true, curve)
        end
        if ok and type(color) == "table" and color.GetRGB then
            if color.GetRGBA then
                local r, g, bl, a = color:GetRGBA()
                return true, r, g, bl, a
            end
            local r, g, bl = color:GetRGB()
            return true, r, g, bl, 1
        end
    end
    local cur, max
    if isPower then cur, max = ns.Safe(UnitPower, unit, ptype), ns.Safe(UnitPowerMax, unit, ptype)
    else cur, max = ns.Safe(UnitHealth, unit), ns.Safe(UnitHealthMax, unit) end
    if cur and max and max > 0 then
        local c = ns.StatusColor(b, cur / max)
        return true, c.r, c.g, c.b, (hideFull and cur >= max) and 0 or 1
    end
    return false
end

ns.OnRefresh(function()
    local n = 0
    for _ in pairs(curves) do n = n + 1 end
    if n > 16 then curves = {} end
end)
