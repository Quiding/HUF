-- HUF: move the game's own windows (character, spellbook, professions, quest,
-- map, mail, merchant, ...) by dragging them; their places are remembered.
--
-- Way of BlizzMove-like addons: SetMovable + a drag hook on the window itself
-- (HookScript, never SetScript), the place saved relative to UIParent and put
-- back after the game's panel manager placed the window (UpdateUIPanelPositions
-- hook, OnShow). Protected windows are left alone in combat. Shift + right-click
-- on a window puts it back where the game wants it.

local _, ns = ...
local W = {}
ns.Windows = W

-- window name -> load-on-demand addon (nil: loaded with the game). Names that
-- don't exist on a client are skipped.
local LIST = {
    CharacterFrame = false, InspectFrame = "Blizzard_InspectUI", DressUpFrame = false,
    PlayerSpellsFrame = "Blizzard_PlayerSpells", SpellBookFrame = false,
    ProfessionsBookFrame = "Blizzard_ProfessionsBook", ProfessionsFrame = "Blizzard_Professions",
    TradeSkillFrame = "Blizzard_TradeSkillUI", ClassTrainerFrame = "Blizzard_TrainerUI",
    ProfessionsCustomerOrdersFrame = "Blizzard_ProfessionsCustomerOrders",
    WorldMapFrame = false, QuestFrame = false, GossipFrame = false, ItemTextFrame = false,
    MerchantFrame = false, MailFrame = false, OpenMailFrame = false, TradeFrame = false,
    BankFrame = false, GuildBankFrame = "Blizzard_GuildBankUI", AuctionHouseFrame = "Blizzard_AuctionHouseUI",
    FriendsFrame = false, CommunitiesFrame = "Blizzard_Communities", ChannelFrame = "Blizzard_Channels",
    PVEFrame = false, EncounterJournal = "Blizzard_EncounterJournal", AchievementFrame = "Blizzard_AchievementUI",
    CollectionsJournal = "Blizzard_Collections", WardrobeFrame = "Blizzard_Collections",
    CalendarFrame = "Blizzard_Calendar", TimeManagerFrame = "Blizzard_TimeManager",
    MacroFrame = "Blizzard_MacroUI", AddonList = false, HelpFrame = false,
    ItemSocketingFrame = "Blizzard_ItemSocketingUI", ItemUpgradeFrame = "Blizzard_ItemUpgradeUI",
    ItemInteractionFrame = "Blizzard_ItemInteractionUI", TransmogFrame = "Blizzard_Transmog",
    LegacySystemFrame = "Blizzard_LegacySystem", TabardFrame = false, GuildRegistrarFrame = false,
    PetitionFrame = false, TaxiFrame = false, FlightMapFrame = "Blizzard_FlightMap",
    PetStableFrame = false, StableFrame = false,
}
W.LIST = LIST

local function S() return ns.db.windows end
local function Saved() local s = S() s.positions = s.positions or {} return s.positions end

local hooked = {}        -- name -> frame
local orig = {}          -- name -> the game's own anchors (taken when hooked)
local pending = {}       -- name -> put back after combat

local function CanTouch(f)
    return f and not (f.IsForbidden and f:IsForbidden()) and not (InCombatLockdown() and f:IsProtected())
end

local function TakePoints(f)
    local t = {}
    for i = 1, f:GetNumPoints() do
        local p, rel, rp, x, y = f:GetPoint(i)
        t[i] = { p, rel, rp, x, y }
    end
    return t
end

-- put a window at its saved place
local function Place(name)
    local f, pos = hooked[name], Saved()[name]
    if not (f and pos and S().enabled) then return end
    if not CanTouch(f) then pending[name] = true return end
    f:ClearAllPoints()
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end
W.Place = Place

-- back where the game wants it
local function Reset(name)
    Saved()[name] = nil
    local f = hooked[name]
    if not (f and CanTouch(f)) then return end
    f:ClearAllPoints()
    for _, pt in ipairs(orig[name] or {}) do
        if pt[2] == nil or type(pt[2]) == "table" then f:SetPoint(pt[1], pt[2] or UIParent, pt[3], pt[4], pt[5]) end
    end
    if f:IsShown() and UIPanelWindows and UIPanelWindows[name] and UpdateUIPanelPositions then
        pcall(UpdateUIPanelPositions, f)
    end
end
W.Reset = Reset

function W.ResetAll()
    local names = {}
    for name in pairs(Saved()) do names[#names + 1] = name end
    for _, name in ipairs(names) do Reset(name) end
    ns.Print("Every window is back where the game puts it.")
end

function W.Count()
    local n = 0
    for _ in pairs(Saved()) do n = n + 1 end
    return n
end

local function Hook(name)
    if hooked[name] then return end
    local f = _G[name]
    if type(f) ~= "table" or not f.SetMovable or (f.IsForbidden and f:IsForbidden()) then return end
    hooked[name] = f
    orig[name] = TakePoints(f)
    if not CanTouch(f) then pending[name] = true end
    if not (InCombatLockdown() and f:IsProtected()) then
        f:SetMovable(true)
        if f.SetClampedToScreen then f:SetClampedToScreen(true) end
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
    end
    f:HookScript("OnDragStart", function(self)
        local s = S()
        if not s.enabled or (s.shift and not IsShiftKeyDown()) then return end
        if not CanTouch(self) then return end
        self.hufMoving = true
        self:StartMoving()
    end)
    f:HookScript("OnDragStop", function(self)
        if not self.hufMoving then return end
        self.hufMoving = nil
        self:StopMovingOrSizing()
        if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end   -- not in the game's layout cache
        local p, _, rp, x, y = self:GetPoint(1)
        if p then
            Saved()[name] = { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
            Place(name)
            ns.Log("windows", "%s moved to %s %s %d,%d", name, p, rp, x, y)
        end
    end)
    f:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" and IsShiftKeyDown() and S().enabled and Saved()[name] then
            Reset(name)
            ns.Log("windows", "%s reset", name)
        end
    end)
    f:HookScript("OnShow", function()
        Place(name)
        C_Timer.After(0, function() Place(name) end)   -- after the game's own placing on show
    end)
    if f:IsShown() then Place(name) end
end

local function HookAll(addon)
    if not (ns.db and S().enabled) then return end
    for name, lod in pairs(LIST) do
        if (addon == nil and (not lod or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(lod))))
            or (addon ~= nil and lod == addon) then
            pcall(Hook, name)
        end
    end
end

function W.Apply()
    if not ns.db then return end
    if S().enabled then HookAll() end
end

ns.OnLogin(function()
    W.Apply()
    -- the panel manager places windows when one opens or closes: ours go back after it
    if UpdateUIPanelPositions then
        hooksecurefunc("UpdateUIPanelPositions", function()
            if not S().enabled then return end
            for name, f in pairs(hooked) do
                if f:IsShown() and Saved()[name] then Place(name) end
            end
        end)
    end
end)

ns.On("ADDON_LOADED", function(addon)
    if not (ns.db and HUFDB) then return end
    C_Timer.After(0, function() HookAll(addon) end)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for name in pairs(pending) do
        pending[name] = nil
        local f = hooked[name]
        if f and not f:IsMovable() then
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
        end
        Place(name)
    end
end)

-- debug report line
function W.Report(add)
    local names = {}
    for name in pairs(hooked) do names[#names + 1] = name end
    table.sort(names)
    local moved = {}
    for name, p in pairs(Saved()) do moved[#moved + 1] = ("%s=%s %s %d,%d"):format(name, p[1], p[2], p[3], p[4]) end
    table.sort(moved)
    add(("windows: enabled=%s shift=%s hooked=%d moved=%s"):format(tostring(S().enabled), tostring(S().shift),
        #names, #moved > 0 and table.concat(moved, " ") or "none"))
end
