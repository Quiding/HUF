-- HUF: unlock mode. Shows a preview of every frame that is on (made-up
-- units), drawn with the same code and settings as the real frames. Drag a
-- preview to move the frame, right-click it for its settings.
-- /huf unlock, /huf lock.

local _, ns = ...
local Frame = ns.Frame
local UI = ns.UI
local A = ns.ACCENT

local Movers = {}
ns.Movers = Movers
ns.unlocked = false

-- made-up characters for unlock mode (never real names)
local PEOPLE = {
    { first = "Apple",  last = "Bikini",       class = "PRIEST",  slot = 1, classIndex = 1, hp = 3420, incoming = 1200 },
    { first = "Monika", last = "Songspike",    class = "BARD",    slot = 2, classIndex = 1, hp = 2650 },
    { first = "John",   last = "Multiboxer",   class = "WARRIOR", slot = 3, classIndex = 1, hp = 4100,
      powerToken = "RAGE", maxpower = 100, power = 35 },
    { first = "Elsa",   last = "Lookingglass", class = "PRIEST",  slot = 4, classIndex = 2, hp = 1900, incoming = 2600 },
    { first = "Salsa",  last = "Berry",        class = "WARLOCK", slot = 5, classIndex = 1, hp = 4100 },
}
local function Person(i)
    local m = PEOPLE[i]
    return { first = m.first, last = m.last, class = m.class, player = true, level = 60,
        maxhp = 4100, hp = m.hp, maxpower = m.maxpower or 3000, power = m.power or 2100,
        powerToken = m.powerToken or "MANA", slot = m.slot, classIndex = m.classIndex, incoming = m.incoming }
end

local FAKE = {
    player = function() return Person(1) end,
    targettarget = function() return Person(2) end,
    pet = function()
        return { first = "Fluffy", level = 60, maxhp = 2400, hp = 1900, maxpower = 100, power = 70, powerToken = "FOCUS" }
    end,
    target = function()
        return { first = "Northshire Guard", level = 55, classification = "elite", hostile = true,
            maxhp = 12500, hp = 7300, maxpower = 2400, power = 1650, powerToken = "MANA" }
    end,
}

-- the group preview: the 5 made-up characters (the first one stands for you)
local function FakeMember(i) return Person(i) end

local previews = {}

-- dragging: the frame keeps its anchor (screen or another frame); only the
-- offsets change by how far it was moved
local function DragStart(self)
    if InCombatLockdown() then ns.Print("Frames can't be moved in combat.") return end
    self.dragFrom = { self:GetLeft() or 0, self:GetTop() or 0 }
    self:StartMoving()
end

local function DragStop(self, key)
    self:StopMovingOrSizing()
    local from = self.dragFrom
    if not from then return end
    self.dragFrom = nil
    local dx, dy = (self:GetLeft() or 0) - from[1], (self:GetTop() or 0) - from[2]
    local p = ns.db.units[key].point
    p[3] = math.floor((p[3] or 0) + dx + 0.5)
    p[4] = math.floor((p[4] or 0) + dy + 0.5)
    ns.Log("move", "%s moved by %d,%d to %s %s %s,%s", key, dx, dy, p[1], p[2], p[3], p[4])
    ns.Refresh(true)
end

local function Lookup(k) return previews[k] end

local function Preview(key)
    if previews[key] then return previews[key] end
    local f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("HIGH")
    Frame.Build(f, key, false)
    f.previewTitle = ns.UNIT_BY_KEY[key].title
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 14)
    f.label:SetText(f.previewTitle)
    f.box = CreateFrame("Frame", nil, f)
    f.box:SetPoint("TOPLEFT", -4, 4)
    f.box:SetPoint("BOTTOMRIGHT", 4, -4)
    f.box:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    UI.Fill(f.box, A[1], A[2], A[3], 0.10)
    UI.Border(f.box, A[1], A[2], A[3], 0.8)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", function(self) DragStop(self, key) end)
    f:RegisterForClicks("RightButtonUp")
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" and ns.ToggleConfig then ns.ToggleConfig(key, true) end
    end)
    previews[key] = f
    return f
end

local function Layout(key)
    local s = ns.db.units[key]
    local f = Preview(key)
    f.s = s
    f.fake = f.fake or FAKE[key]()
    f.label:SetTextColor(A[1], A[2], A[3])
    f:SetScale(s.scale)
    ns.Units.ApplyPoint(f, s, ns.Units.AnchorFrame(key, s, Lookup))
    f:SetSize(s.width, s.height)
    Frame.LayoutInner(f)
    Frame.Update(f)
    f:SetShown(ns.unlocked and s.enabled)
end

---------------------------------------------------------------------------
-- Group preview: a box with 5 made-up members, laid out like the header does
---------------------------------------------------------------------------
local group
local function GroupPreview()
    if group then return group end
    local box = CreateFrame("Button", nil, UIParent)
    box:SetFrameStrata("HIGH")
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:RegisterForClicks("RightButtonUp")
    box:SetScript("OnDragStart", DragStart)
    box:SetScript("OnDragStop", function(self) DragStop(self, "party") end)
    box:SetScript("OnClick", function() if ns.ToggleConfig then ns.ToggleConfig("party", true) end end)
    box.fill = UI.Fill(box, A[1], A[2], A[3], 0.10)
    box.border = UI.Border(box, A[1], A[2], A[3], 0.8)
    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 22)
    box.label:SetText("Group")
    box.members = {}
    for i = 1, 5 do
        local f = CreateFrame("Frame", nil, box)
        Frame.Build(f, "party", false)
        f.fake = FakeMember(i)
        f:EnableMouse(false)
        box.members[i] = f
    end
    group = box
    return box
end

local function LayoutGroup()
    local s = ns.db.units.party
    local box = GroupPreview()
    local o = s.group
    local first = o.showPlayer and 1 or 2
    local n = 6 - first
    local g = ns.Group.Growth(o)
    local vertical = g.dx == 0
    box:SetScale(s.scale)
    box.label:SetTextColor(A[1], A[2], A[3])
    local sp = ns.Group.Spacing(o)
    local w = vertical and s.width or (n * s.width + (n - 1) * sp)
    local h = vertical and (n * s.height + (n - 1) * sp) or s.height
    box:SetSize(w, h)
    ns.Group.Place(box, s)
    for i, f in ipairs(box.members) do
        f.s = s
        local pos = i - first
        f:ClearAllPoints()
        if pos < 0 then
            f:Hide()
        else
            -- from the box corner the header grows from
            f:SetPoint(g.corner, box, g.corner, g.dx * pos * (s.width + sp), g.dy * pos * (s.height + sp))
            f:SetSize(s.width, s.height)
            Frame.LayoutInner(f)
            Frame.Update(f)
            f:Show()
        end
    end
    box:SetShown(ns.unlocked and s.enabled)
end

function Movers.LayoutAll()
    for _, info in ipairs(ns.UNITS) do Layout(info.key) end
    LayoutGroup()
end

function ns.UpdatePreviews()
    if not ns.unlocked then return end
    for _, f in pairs(previews) do
        if f:IsShown() then Frame.Update(f) end
    end
    if group and group:IsShown() then
        for _, f in ipairs(group.members) do if f:IsShown() then Frame.Update(f) end end
    end
end

function Movers.SetUnlocked(on)
    if on and InCombatLockdown() then ns.Print("Not in combat.") return end
    ns.unlocked = on and true or false
    ns.Log("move", "unlock mode %s", ns.unlocked and "on" or "off")
    if ns.unlocked then
        Movers.LayoutAll()
    else
        for _, f in pairs(previews) do f:Hide() end
        if group then group:Hide() end
    end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

function Movers.Toggle() Movers.SetUnlocked(not ns.unlocked) end

ns.OnRefresh(function() if ns.unlocked then Movers.LayoutAll() end end)
ns.On("PLAYER_REGEN_DISABLED", function() if ns.unlocked then Movers.SetUnlocked(false) end end)
