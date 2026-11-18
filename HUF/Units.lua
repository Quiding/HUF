-- HUF: the unit frames (player, target; more follow) and hiding Blizzard's
-- frames that HUF replaces.

local _, ns = ...
local Frame = ns.Frame

local Units = {}
ns.Units = Units
ns.singles = {}

---------------------------------------------------------------------------
-- Blizzard frames: events off, parked under a hidden parent (out of combat)
---------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
local handled = {}

local SUB = { "healthbar", "manabar", "healthBar", "manaBar", "HealthBar", "ManaBar", "spellbar", "castBar",
    "powerBarAlt", "PowerBarAlt", "BuffFrame", "DebuffFrame", "AurasFrame", "totFrame", "petFrame" }

local function Park(frame)
    ns.RunOOC("park:" .. tostring(frame), function()
        if frame:GetParent() ~= hiddenParent then
            frame:SetParent(hiddenParent)
            ns.Log("blizzard", "hid %s", frame)
        end
    end)
end

local function Kill(frame)
    if type(frame) == "string" then frame = _G[frame] end
    if not frame or handled[frame] then return end
    handled[frame] = true
    pcall(frame.UnregisterAllEvents, frame)
    for _, k in ipairs(SUB) do
        local child = frame[k]
        if type(child) == "table" and child.UnregisterAllEvents then pcall(child.UnregisterAllEvents, child) end
    end
    Park(frame)
    -- Edit Mode and Blizzard code may put it back: park it again (next frame,
    -- never inside Blizzard's own call)
    hooksecurefunc(frame, "SetParent", function(self, parent)
        if parent ~= hiddenParent then C_Timer.After(0, function() Park(self) end) end
    end)
end

local BLIZZARD = {
    player = { "PlayerFrame" },
    target = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    pet = { "PetFrame" },
    party = { "PartyFrame", "CompactPartyFrame", "PartyMemberFrame1", "PartyMemberFrame2",
              "PartyMemberFrame3", "PartyMemberFrame4" },
}

-- Blizzard's own buff / debuff icons (top right): an option of the player frame
local BLIZZARD_AURAS = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }

function Units.HideBlizzardAuras()
    if not ns.db.units.player.hideBlizzardAuras then return end
    for _, name in ipairs(BLIZZARD_AURAS) do Kill(name) end
end

function Units.HideBlizzard()
    Units.HideBlizzardAuras()
    if not ns.db.global.hideBlizzard then return end
    for key, list in pairs(BLIZZARD) do
        if ns.db.units[key].enabled then
            for _, name in ipairs(list) do Kill(name) end
        end
    end
end

---------------------------------------------------------------------------
-- Single frames
---------------------------------------------------------------------------
-- the frame `s` is anchored to: UIParent, or another HUF frame (lookup(key)
-- gives that frame: the real one, or its preview in unlock mode). Never a
-- frame that is itself anchored back to this one.
function Units.AnchorFrame(key, s, lookup)
    local to = s.anchorTo
    if to and to ~= "SCREEN" and to ~= key and ns.db.units[to] then
        local back = ns.db.units[to].anchorTo
        local rel = back ~= key and lookup(to)
        if rel then return rel end
    end
    return UIParent
end

local function ApplyPoint(f, s, rel)
    local p = s.point
    f:ClearAllPoints()
    f:SetPoint(p[1] or "CENTER", rel or UIParent, p[2] or p[1] or "CENTER", p[3] or 0, p[4] or 0)
end
Units.ApplyPoint = ApplyPoint

-- shown while the unit exists (a secure state driver, also in combat)
local function Visibility(key)
    if key == "player" then return "show" end
    return ("[@%s,exists] show; hide"):format(ns.UNIT_BY_KEY[key].unit)
end

function Units.Apply(key)
    local f = ns.singles[key]
    if not f then return end
    local s = ns.db.units[key]
    f.s = s
    ns.RunOOC("single:" .. key, function()
        f:SetScale(s.scale)
        ApplyPoint(f, s, Units.AnchorFrame(key, s, function(k) return ns.singles[k] end))
        Frame.LayoutSecure(f)
        local want = s.enabled and Visibility(key) or "hide"
        if f.hufWatch ~= want then
            UnregisterStateDriver(f, "visibility")
            RegisterStateDriver(f, "visibility", want)
            f.hufWatch = want
        end
        if s.enabled and key == "player" and not f:IsShown() then f:Show() end
        ns.Log("frame", "apply %s: enabled=%s driver=%s size=%sx%s scale=%s point=%s %s %s,%s shown=%s",
            key, s.enabled, want, s.width, s.height, s.scale, s.point[1], s.point[2], s.point[3], s.point[4], f:IsShown())
    end)
    ns.Try("layout " .. key, Frame.LayoutInner, f)
    ns.Try("update " .. key, Frame.Update, f)
end

function Units.ApplyAll()
    for _, info in ipairs(ns.UNITS) do
        Units.Apply(info.key)
    end
end

local function Create()
    for _, info in ipairs(ns.UNITS) do
        if not ns.singles[info.key] then
            ns.Try("create " .. info.key, function()
                local f = Frame.CreateSingle(info.key, info.unit, "HUF_" .. info.key)
                f.previewTitle = info.title
                ns.singles[info.key] = f
                if ns.ClickCast then ns.ClickCast.Register(f) end
                ns.Log("frame", "made %s (unit %s)", info.key, info.unit)
            end)
        end
    end
    for _, info in ipairs(ns.UNITS) do
        ns.Try("apply " .. info.key, Units.Apply, info.key)
    end
    ns.Try("hide Blizzard frames", Units.HideBlizzard)
end

-- a few seconds after login: every frame that should be visible, is it?
local function SelfCheck()
    if InCombatLockdown() then return end
    for _, info in ipairs(ns.UNITS) do
        local s = ns.db.units[info.key]
        local f = ns.singles[info.key]
        if s.enabled then
            local ok, exists = pcall(UnitExists, info.unit)
            exists = ok and ns.Bool(exists)
            if not f then
                ns.LogError("self-check", info.key .. " frame was not made")
            elseif exists and not f:IsVisible() then
                ns.LogError("self-check", ("%s frame is not visible (shown=%s alpha=%s parent visible=%s)"):format(
                    info.key, tostring(f:IsShown()), ns.DebugStr(f:GetEffectiveAlpha()), tostring(f:GetParent() and f:GetParent():IsVisible())))
            end
        end
    end
    ns.LogFrames("self-check after login")
end

-- secure frames are made outside combat (a /reload in combat: right after it)
ns.OnLogin(function()
    ns.RunOOC("create:singles", Create)
    C_Timer.After(3, SelfCheck)
end)
ns.OnRefresh(function()
    if next(ns.singles) then
        Units.ApplyAll()
        Units.HideBlizzard()
    end
end)
