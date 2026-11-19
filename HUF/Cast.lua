-- HUF: cast bars (shared by the group frames and the nameplates).
-- A cast bar is a StatusBar with .icon (texture) and .text (font string).
-- Cast times may be secret: the game's own timer (SetTimerDuration) drives
-- the bar; with readable times an OnUpdate does. "Interrupted!" is shown for
-- a moment when someone interrupted the cast (the event names the
-- interrupter; casts the caster stopped himself carry none).

local _, ns = ...
local Cast = {}
ns.Cast = Cast

local FLAT = "Interface\\Buttons\\WHITE8X8"
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- unit events a cast bar needs
Cast.EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
}
Cast.START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true }
Cast.STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true }

-- the red wash and its text, above the fill
function Cast.Decorate(c)
    c.flash = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.flash:SetAllPoints()
    c.flash:SetTexture(FLAT)
    c.flash:Hide()
end

local function OnUpdate(c)
    if not c.startMS then return end
    local now = GetTime() * 1000
    local v = (now - c.startMS) / math.max(1, c.endMS - c.startMS)
    if c.channel then v = 1 - v end
    c:SetValue(math.max(0, math.min(1, v)))
    if now > c.endMS + 200 then c:Hide() if c.text then c.text:Hide() end end
end

local function EndFlash(c)
    if c.flashTimer then c.flashTimer:Cancel() end
    c.flashTimer = nil
    c.interrupted = nil
    if c.flash then c.flash:Hide() end
end

-- the bar off (an "Interrupted!" still showing stays until its time is up)
function Cast.Stop(c, force)
    c.startMS = nil
    c:SetScript("OnUpdate", nil)
    if c.interrupted and not force then return end
    EndFlash(c)
    c:Hide()
    if c.text then c.text:Hide() end
    if c.OnCastHide then c:OnCastHide() end
end

-- the unit's current cast or channel on the bar; false when it casts nothing
function Cast.Start(c, unit)
    local channel = false
    local name, _, texture, startMS, endMS = UnitCastingInfo(unit)
    if type(name) == "nil" then
        name, _, texture, startMS, endMS = UnitChannelInfo(unit)
        channel = true
    end
    if type(name) == "nil" then Cast.Stop(c) return false end
    EndFlash(c)
    c.channel = channel
    c:SetScript("OnUpdate", nil)
    c.startMS = nil
    c:SetStatusBarColor(c.color and c.color.r or 1, c.color and c.color.g or 0.7, c.color and c.color.b or 0.2)
    local timed = false
    if c.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
        local okD, d = pcall(channel and UnitChannelDuration or UnitCastingDuration, unit)
        if okD and d then
            local dir = channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime
            timed = pcall(c.SetTimerDuration, c, d, nil, dir)
        end
    end
    if not timed and not IsSecret(startMS) and not IsSecret(endMS) and startMS and endMS then
        c:SetMinMaxValues(0, 1)
        c.startMS, c.endMS = startMS, endMS
        c:SetScript("OnUpdate", OnUpdate)
        timed = true
    end
    if not timed then Cast.Stop(c, true) return false end
    if c.icon then pcall(c.icon.SetTexture, c.icon, texture) end
    if c.text then pcall(c.text.SetText, c.text, name) end
    c:Show()
    if c.text then c.text:SetShown(c.showText ~= false) end
    if c.OnCastShow then c:OnCastShow() end
    return true
end

-- "Interrupted!" for `seconds` (by: the interrupter from the event; nil
-- when the caster stopped the cast himself, then nothing is shown)
function Cast.Interrupted(c, by, seconds)
    if type(by) == "nil" or not c.showInterrupt then Cast.Stop(c, true) return end
    c.startMS = nil
    c:SetScript("OnUpdate", nil)
    c:SetMinMaxValues(0, 1)
    c:SetValue(1)
    local col = c.interruptColor or { r = 0.85, g = 0.15, b = 0.15 }
    c.flash:SetVertexColor(col.r, col.g, col.b, 0.9)
    c.flash:Show()
    if c.text then
        c.text:SetText("Interrupted!")
        c.text:SetShown(c.showText ~= false)
    end
    c:Show()
    if c.OnCastShow then c:OnCastShow() end
    c.interrupted = true
    if c.flashTimer then c.flashTimer:Cancel() end
    c.flashTimer = C_Timer.NewTimer(seconds or 1, function()
        c.flashTimer = nil
        c.interrupted = nil
        Cast.Stop(c, true)
    end)
end

-- one handler for every cast event (args after the unit: castGUID, spellID, interruptedBy)
function Cast.OnEvent(c, unit, event, _, _, interruptedBy, seconds)
    if Cast.START[event] then
        Cast.Start(c, unit)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        Cast.Interrupted(c, interruptedBy, seconds)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and type(interruptedBy) ~= "nil" then
        Cast.Interrupted(c, interruptedBy, seconds)
    elseif Cast.STOP[event] then
        Cast.Stop(c)
    end
end
