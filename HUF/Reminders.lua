-- HUF: hide the game's menu bar reminders (General > Frames & Features).
-- The yellow boxes pointing at a menu bar button ("You have unspent Talent
-- points.", unspent Legacy points, new collection items, ...). The game
-- shows them through MainMenuMicroButton_ShowAlert, on this client as a
-- HelpTip anchored to the button (older clients: an alert frame per button,
-- e.g. TalentMicroButtonAlert). HUF never calls the game's alert functions
-- (that taints them, EllesmereUI's note); it watches with hooksecurefunc and
-- hides the box on the next frame.
-- global.hideReminders = { talents, legacy, other }

local _, ns = ...

local function Cfg() return ns.db and ns.db.global.hideReminders end

-- which switch a reminder belongs to, from its button's (or alert's) name
local function Kind(region)
    local name = region and region.GetName and region:GetName()
    if type(name) ~= "string" then return nil end
    if not (name:find("MicroButton") or name:find("MicroMenu")) then return nil end
    if name:find("Talent") or name:find("PlayerSpells") then return "talents", name end
    if name:find("Legacy") then return "legacy", name end
    return "other", name
end

local function Wanted(kind)
    local c = Cfg()
    return kind and c and c[kind] and true or false
end

-- HelpTip path: hide the box that shows this info
local pending = {}
local function HideTips()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then wipe(pending) return end
    for tip in pool:EnumerateActive() do
        local why = tip.info and pending[tip.info]
        if why and tip:IsShown() then
            tip:Hide()
            ns.Log("reminders", "hid %s reminder at %s", why[1], why[2])
        end
    end
    wipe(pending)
end

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if HelpTip and HelpTip.Show then
        hooksecurefunc(HelpTip, "Show", function(_, parent, info, relativeRegion)
            if type(info) ~= "table" then return end
            local kind, name = Kind(relativeRegion)
            if not kind then kind, name = Kind(parent) end
            if not Wanted(kind) then return end
            pending[info] = { kind, name }
            C_Timer.After(0, HideTips)
        end)
    end
    -- older clients: one alert frame per button
    if type(MainMenuMicroButton_ShowAlert) == "function" then
        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(alert)
            if not (alert and alert.GetObjectType and alert.Hide) then return end
            local name = alert.GetName and alert:GetName() or ""
            if not name:find("Alert") then return end   -- a button: the HelpTip hook has it
            local kind = Kind(alert)
            if not Wanted(kind) then return end
            C_Timer.After(0, function()
                if alert:IsShown() then
                    alert:Hide()
                    ns.Log("reminders", "hid %s reminder %s", kind, name)
                end
            end)
        end)
    end
end

-- boxes already up when a switch is turned on
local function HideOpen()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then return end
    for tip in pool:EnumerateActive() do
        if tip:IsShown() and tip.info then
            local kind, name = Kind(tip.relativeRegion)
            if not kind then kind, name = Kind(tip:GetParent()) end
            if not kind and tip.info.system == "MicroButtons" then kind, name = "other", "MicroButtons" end
            if Wanted(kind) then pending[tip.info] = { kind, name } end
        end
    end
    if next(pending) then HideTips() end
end

local function Apply()
    local c = Cfg()
    if not c then return end
    if c.talents or c.legacy or c.other then
        Hook()
        pcall(HideOpen)
    end
end

ns.OnLogin(Apply)
ns.OnRefresh(Apply)
