-- HUF: move the game's own windows (character, spellbook, professions, quest,
-- map, mail, merchant, ...) by dragging them; their places are remembered.
--
-- Approach learned from ForeverMove (Ugge Zen, MIT): no secure snippets (Forever's
-- restricted environment can't compile them), HookScript and global-function
-- hooks only (never hooks on a Blizzard frame's own methods, which break the 12.x
-- protected positioning), every window that opens through ShowUIPanel is taken,
-- mouse-enabled inner panels covering a window (Forever's spellbook and
-- profession pages) become drag handles, full-screen scenes are left alone, and
-- the place is put back after the game lays its panels out.
-- When ForeverMove itself is enabled, HUF leaves the windows to it.

local _, ns = ...
local W = {}
ns.Windows = W

-- windows that don't (always) open through ShowUIPanel; load-on-demand ones are
-- looked for again whenever a Blizzard addon loads. Missing names are skipped.
local KNOWN = {
    "CharacterFrame", "InspectFrame", "DressUpFrame", "PlayerSpellsFrame", "SpellBookFrame",
    "ProfessionsBookFrame", "ProfessionsFrame", "TradeSkillFrame", "ClassTrainerFrame",
    "ProfessionsCustomerOrdersFrame", "WorldMapFrame", "QuestFrame", "GossipFrame", "ItemTextFrame",
    "MerchantFrame", "MailFrame", "OpenMailFrame", "TradeFrame", "BankFrame", "GuildBankFrame",
    "AuctionHouseFrame", "FriendsFrame", "CommunitiesFrame", "ChannelFrame", "PVEFrame",
    "EncounterJournal", "AchievementFrame", "CollectionsJournal", "WardrobeFrame", "CalendarFrame",
    "TimeManagerFrame", "MacroFrame", "AddonList", "HelpFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
    "ItemInteractionFrame", "TransmogFrame", "LegacySystemFrame", "TabardFrame", "GuildRegistrarFrame",
    "PetitionFrame", "TaxiFrame", "FlightMapFrame", "PetStableFrame", "StableFrame",
}
-- full-screen scenes the game lays out itself (moving them hid the barbershop's
-- Accept button and the cinematic's skip dialog), and HUF's own windows
local SKIP = {
    BarberShopFrame = true, CharCustomizeFrame = true, CinematicFrame = true, CinematicFrameCloseDialog = true,
    MovieFrame = true, CharacterCreateFrame = true, WorldFrame = true, GameMenuFrame = true,
}

local function S() return ns.db.windows end
local function Saved() local s = S() s.positions = s.positions or {} return s.positions end

-- ForeverMove does the same: leave it to that addon
local function Other()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverMove") and true or false
end
W.Other = Other
local function On() return ns.db and S().enabled and not Other() end

local hooked = {}        -- frame -> name
local byName = {}        -- name -> frame
local handles = {}       -- inner frame -> its window
local orig = {}          -- name -> the game's own anchors (taken when hooked)
local pending = {}       -- frame -> take / put back after combat

local function Name(f)
    if not f.GetName then return nil end
    local ok, n = pcall(f.GetName, f)        -- some mixins return a font string
    return ok and type(n) == "string" and n or nil
end
local function Forbidden(f) return f.IsForbidden and f:IsForbidden() end
local function Prot(f)
    local ok, p = pcall(f.IsProtected, f)
    return ok and p
end
local function Blocked(f) return InCombatLockdown() and Prot(f) end
local function Try(f, method, ...)
    if not f[method] then return false end
    return (pcall(f[method], f, ...))
end

local function TakePoints(f)
    local t = {}
    for i = 1, f:GetNumPoints() do
        local p, rel, rp, x, y = f:GetPoint(i)
        t[i] = { p, rel, rp, x, y }
    end
    return t
end

-- put a window at its saved place (only when it isn't there already: the game's
-- layout hooks call this all the time)
local restoring
local function Place(f)
    local name = hooked[f]
    local pos = name and Saved()[name]
    if not (pos and On()) or restoring then return end
    if Blocked(f) then pending[f] = true return end
    if f:GetNumPoints() == 1 then
        local p, rel, rp, x, y = f:GetPoint(1)
        if p == pos[1] and (rel == nil or rel == UIParent) and rp == pos[2]
            and math.abs((x or 0) - pos[3]) < 0.5 and math.abs((y or 0) - pos[4]) < 0.5 then return end
    end
    restoring = true
    pcall(f.ClearAllPoints, f)
    Try(f, "SetPoint", pos[1], UIParent, pos[2], pos[3], pos[4])
    restoring = nil
end

local function PlaceShown()
    if not On() then return end
    for f in pairs(hooked) do
        if f:IsShown() then Place(f) end
    end
end

-- back where the game wants it
local function Reset(name)
    Saved()[name] = nil
    local f = byName[name]
    if not f or Blocked(f) then return end
    pcall(f.ClearAllPoints, f)
    for _, pt in ipairs(orig[name] or {}) do
        Try(f, "SetPoint", pt[1], pt[2] or UIParent, pt[3], pt[4], pt[5])
    end
    if f:IsShown() and UIPanelWindows and UIPanelWindows[name] and UpdateUIPanelPositions then
        pcall(UpdateUIPanelPositions, f)
    end
end
W.Reset = Reset

-- every window that can be moved here: the known ones this client has, the
-- ones taken so far and the ones with a saved place, sorted
function W.List()
    local seen, out = {}, {}
    local function Add(n) if n and not seen[n] then seen[n] = true out[#out + 1] = n end end
    for _, n in ipairs(KNOWN) do if type(_G[n]) == "table" then Add(n) end end
    for _, n in pairs(hooked) do Add(n) end
    for n in pairs(Saved()) do Add(n) end
    table.sort(out, function(a, b) return W.Pretty(a) < W.Pretty(b) end)
    return out
end
function W.IsMoved(name) return Saved()[name] ~= nil end
-- "PlayerSpellsFrame" -> "Player Spells"
function W.Pretty(name)
    local n = name:gsub("Frame$", ""):gsub("([a-z])([A-Z])", "%1 %2")
    return n
end

function W.ResetAll()
    local names = {}
    for name in pairs(Saved()) do names[#names + 1] = name end
    for _, name in ipairs(names) do Reset(name) end
    ns.Print("Every window is back where the game puts it.")
end

local function StartDrag(f)
    local s = S()
    if not On() or (s.shift and not IsShiftKeyDown()) then return end
    if Blocked(f) then return end
    if IsShiftKeyDown() and IsControlKeyDown() then return end        -- Ctrl + Shift: click through
    if GetCursorInfo and GetCursorInfo() ~= nil then return end      -- an item on the cursor: that drag is the item's
    if not f:IsMovable() then Try(f, "SetMovable", true) end
    f.hufMoving = pcall(f.StartMoving, f)
end
local function StopDrag(f)
    if not f.hufMoving then return end
    f.hufMoving = nil
    pcall(f.StopMovingOrSizing, f)
    Try(f, "SetUserPlaced", false)       -- not in the game's layout cache
    local name = hooked[f]
    local p, _, rp, x, y = f:GetPoint(1)
    if name and p then
        Saved()[name] = { p, rp or p, math.floor(x + 0.5), math.floor(y + 0.5) }
        ns.Log("windows", "%s moved to %s %s %d,%d", name, p, rp or p, x, y)
    end
end
local function ResetClick(f, button)
    local name = hooked[f]
    if button == "RightButton" and IsShiftKeyDown() and On() and name and Saved()[name] then
        Reset(name)
        ns.Log("windows", "%s reset", name)
    end
end

-- an inner frame (title bar, a panel covering the window) that drags the window
local function AddHandle(f, h)
    if type(h) ~= "table" or not h.HookScript or not h.RegisterForDrag or handles[h] or hooked[h] then return end
    if Forbidden(h) or Blocked(h) then return end
    handles[h] = f
    if not (Try(h, "EnableMouse", true) and Try(h, "RegisterForDrag", "LeftButton")) then return end
    h:HookScript("OnDragStart", function() StartDrag(f) end)
    h:HookScript("OnDragStop", function() StopDrag(f) end)
    h:HookScript("OnMouseUp", function(_, button) ResetClick(f, button) end)
end

-- things a player clicks, types in, scrolls or drags for their own purpose
local INTERACTIVE = { "Button", "EditBox", "Slider", "ScrollFrame", "Model", "ModelScene", "SimpleHTML", "ColorSelect", "StatusBar" }
local OWN = { "OnClick", "OnDragStart", "OnReceiveDrag" }
local function Interactive(c)
    if not c.IsObjectType then return true end
    for _, t in ipairs(INTERACTIVE) do if c:IsObjectType(t) then return true end end
    if c.Thumb or c.Track or c.GetThumb or c.ScrollTarget or c.GetScrollTarget then return true end
    for _, k in ipairs(OWN) do
        local ok, fn = pcall(c.GetScript, c, k)
        if ok and fn then return true end
    end
    return false
end
local function Walk(f, parent, depth)
    if depth > 4 or not parent.GetChildren then return end
    for _, c in ipairs({ parent:GetChildren() }) do
        if type(c) == "table" and not hooked[c] and not Forbidden(c) then
            local n = Name(c)
            local own = n and UIPanelWindows and UIPanelWindows[n]
            if not own and not (handles[c] and handles[c] ~= f) and not Interactive(c) then
                if not handles[c] and c.IsMouseEnabled and c:IsMouseEnabled() then AddHandle(f, c) end
                Walk(f, c, depth + 1)
            end
        end
    end
end
local walked = {}
local function AutoHandles(f)
    if not On() then return end
    local now = GetTime()
    if walked[f] and now - walked[f] < 1 then return end
    walked[f] = now
    pcall(Walk, f, f, 1)
end

-- full screen or stretched to the screen's corners: left alone
local function Unsafe(f, name)
    if SKIP[name] or name:find("^HUF") or name:find("^Gamepad") or name:find("ActionBar") then return true end
    local corners = {}
    for i = 1, f:GetNumPoints() do
        local p, rel = f:GetPoint(i)
        if rel == nil or rel == UIParent or rel == WorldFrame then corners[p or ""] = true end
    end
    if (corners.TOPLEFT and corners.BOTTOMRIGHT) or (corners.TOPRIGHT and corners.BOTTOMLEFT) then return true end
    local w, h = f:GetSize()
    local sw, sh = UIParent:GetSize()
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (w or 0) * s >= sw * 0.95 and (h or 0) * s >= sh * 0.95
end

local function Take(f)
    if type(f) ~= "table" or hooked[f] or not f.StartMoving or Forbidden(f) then return end
    local name = Name(f)
    if not name or Unsafe(f, name) then return end
    if Blocked(f) then pending[f] = true return end
    hooked[f], byName[name] = name, f
    orig[name] = TakePoints(f)
    Try(f, "SetMovable", true)
    Try(f, "SetClampedToScreen", true)
    Try(f, "EnableMouse", true)
    Try(f, "RegisterForDrag", "LeftButton")
    f:HookScript("OnDragStart", StartDrag)
    f:HookScript("OnDragStop", StopDrag)
    f:HookScript("OnMouseUp", ResetClick)
    f:HookScript("OnShow", function(self)
        AutoHandles(self)
        Place(self)
        C_Timer.After(0, function() Place(self) end)     -- after the game's own placing on show
    end)
    for _, h in pairs({ f.TitleContainer, f.TitleBar, f.Header, f.DragBar, _G[name .. "TitleBar"], _G[name .. "DragFrame"] }) do
        AddHandle(f, h)
    end
    AutoHandles(f)
    if f:IsShown() then Place(f) end
end
W.Take = Take

local function TakeKnown()
    if not On() then return end
    for _, name in ipairs(KNOWN) do pcall(Take, _G[name]) end
    for name in pairs(UIPanelWindows or {}) do pcall(Take, _G[name]) end
end

function W.Apply() TakeKnown() end

local hooksDone
ns.OnLogin(function()
    if Other() then ns.Log("windows", "ForeverMove is enabled: HUF leaves the windows to it") return end
    TakeKnown()
    if hooksDone then return end
    hooksDone = true
    -- every standard window opens through ShowUIPanel (load-on-demand ones too)
    if ShowUIPanel then
        hooksecurefunc("ShowUIPanel", function(f)
            if not On() then return end
            pcall(Take, f)
            if hooked[f] then Place(f) end
            PlaceShown()
        end)
    end
    -- the game lays its panels out again when one opens or closes
    for _, fn in ipairs({ "HideUIPanel", "UpdateUIPanelPositions", "UIParent_ManageFramePositions" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, PlaceShown) end
    end
end)

ns.On("ADDON_LOADED", function()
    if not (ns.db and HUFDB) then return end
    C_Timer.After(0, TakeKnown)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for f in pairs(pending) do
        pending[f] = nil
        if not hooked[f] then pcall(Take, f) end
        if hooked[f] and f:IsShown() then Place(f) end
    end
end)

-- debug report line
function W.Report(add)
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    local moved = {}
    for name, p in pairs(Saved()) do moved[#moved + 1] = ("%s=%s %s %d,%d"):format(name, p[1], p[2], p[3], p[4]) end
    table.sort(moved)
    add(("windows: enabled=%s shift=%s foreverMove=%s windows=%d handles=%d moved=%s"):format(tostring(S().enabled),
        tostring(S().shift), tostring(Other()), n, (function() local h = 0 for _ in pairs(handles) do h = h + 1 end return h end)(),
        #moved > 0 and table.concat(moved, " ") or "none"))
end
