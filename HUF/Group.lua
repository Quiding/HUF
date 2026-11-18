-- HUF: group frames (party). A secure group header (SecureGroupHeaderTemplate)
-- makes one SecureUnitButton per member, so they are real unit frames:
-- clicks, @mouseover macros and click-casting work on them.
--
-- Options: myself in the group or not, horizontal / vertical, sorted by name,
-- by Blizzard's party order or by class. Raid frames come later: in a raid
-- the group frames hide.
--
-- The header makes its buttons itself (also in combat), so all 5 are made
-- right after login, outside combat; HUF builds its bars into each one there.

local _, ns = ...
local Frame = ns.Frame

local G = {}
ns.Group = G
G.buttons = {}

local CLASS_ORDER = "WARRIOR,PALADIN,DEATHKNIGHT,DEMONHUNTER,ROGUE,MONK,DRUID,HUNTER,SHAMAN,EVOKER,MAGE,WARLOCK,PRIEST"
local VISIBILITY = "[group:raid] hide; [group] show; hide"

local function S() return ns.db.units.party end

-- growth directions: header point, x / y step sign, the corner the header
-- is anchored by (the first member stays where s.point puts its top left)
local GROWTH = {
    DOWN  = { point = "TOP",    dx = 0,  dy = -1, corner = "TOPLEFT" },
    UP    = { point = "BOTTOM", dx = 0,  dy = 1,  corner = "BOTTOMLEFT" },
    RIGHT = { point = "LEFT",   dx = 1,  dy = 0,  corner = "TOPLEFT" },
    LEFT  = { point = "RIGHT",  dx = -1, dy = 0,  corner = "TOPRIGHT" },
}
G.GROWTH = GROWTH
function G.Growth(o)
    local key = o.orientation
    if key == "VERTICAL" then key = "DOWN" elseif key == "HORIZONTAL" then key = "RIGHT" end
    return GROWTH[key] or GROWTH.DOWN, key
end

-- puts a group frame (the header or its preview) so its first member's top
-- left corner is at s.point
function G.Place(frame, s)
    local g = G.Growth(s.group)
    local p = s.point
    local x, y = p[3] or 0, p[4] or 0
    if g.corner == "BOTTOMLEFT" then y = y - s.height
    elseif g.corner == "TOPRIGHT" then x = x + s.width end
    frame:ClearAllPoints()
    frame:SetPoint(g.corner, UIParent, p[2] or "TOPLEFT", x, y)
end

-- runs in the header's restricted environment for every new button
local function InitSnippet(w, h)
    return ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("useOnKeyDown", false)
        self:GetParent():CallMethod("HUFInitButton", self:GetName())
    ]]):format(w, h)
end

-- HUF's bars and texts go into a button the header just made
local function InitButton(header, name)
    local b = name and _G[name]
    if not b or b.hufBuilt then return end
    b.hufBuilt = true
    local n = #G.buttons + 1
    b.hufLabel = "party" .. n
    b.previewTitle = "Group"
    local ok, err = pcall(Frame.Build, b, "party", true)
    if not ok then ns.LogError("group button " .. n, err) return end
    b:HookScript("OnShow", function(self) Frame.Update(self) end)
    G.buttons[n] = b
    Frame.SetUnit(b, b:GetAttribute("unit"))
    if ns.ClickCast then ns.ClickCast.Register(b) end
    ns.Log("frame", "made group button %d (%s)", n, name)
end

-- Every change to the header runs inside a secure snippet (a secure
-- handler's Execute): the header and its update code then never carry HUF's
-- taint. Set from plain addon code, the header remembered that taint and its
-- own later updates in combat were blocked (ADDON_ACTION_BLOCKED
-- HUF_Party:SetHeight() and friends, 5x a second).
local APPLY = [[
    local h = self:GetFrameRef("header")
    local point = self:GetAttribute("huf-point")
    if h:GetAttribute("point") ~= point then
        -- the header adds a new anchor to the old one: clear the old first
        for i = 1, 5 do
            local b = self:GetFrameRef("button" .. i)
            if b then b:ClearAllPoints() end
        end
    end
    h:SetAttribute("showPlayer", self:GetAttribute("huf-showPlayer"))
    h:SetAttribute("point", point)
    h:SetAttribute("xOffset", self:GetAttribute("huf-xOffset"))
    h:SetAttribute("yOffset", self:GetAttribute("huf-yOffset"))
    h:SetAttribute("groupBy", self:GetAttribute("huf-groupBy"))
    h:SetAttribute("groupingOrder", self:GetAttribute("huf-groupingOrder"))
    h:SetAttribute("sortMethod", self:GetAttribute("huf-sortMethod"))
    h:SetAttribute("initialConfigFunction", self:GetAttribute("huf-init"))
]]

-- makes all 5 buttons now, outside combat: one unit (me, solo) shown from
-- index -3 = 5 buttons, then back to normal
local CREATE = [[
    local h = self:GetFrameRef("header")
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("showParty", true)
    h:SetAttribute("showRaid", false)
    h:SetAttribute("showSolo", true)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("startingIndex", -3)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    h:SetAttribute("showSolo", false)
    h:SetAttribute("showPlayer", self:GetAttribute("huf-showPlayer"))
]]

-- the wanted header settings, as attributes of the controller
local function Wanted(ctl)
    local s = S()
    local o = s.group
    local g = G.Growth(o)
    ctl:SetAttribute("huf-showPlayer", o.showPlayer and true or false)
    ctl:SetAttribute("huf-point", g.point)
    ctl:SetAttribute("huf-xOffset", g.dx * o.spacing)
    ctl:SetAttribute("huf-yOffset", g.dy * o.spacing)
    if o.sort == "CLASS" then
        ctl:SetAttribute("huf-groupBy", "CLASS")
        ctl:SetAttribute("huf-groupingOrder", CLASS_ORDER)
        ctl:SetAttribute("huf-sortMethod", "NAME")
    else
        ctl:SetAttribute("huf-groupBy", nil)
        ctl:SetAttribute("huf-groupingOrder", nil)
        ctl:SetAttribute("huf-sortMethod", o.sort == "INDEX" and "INDEX" or "NAME")
    end
    ctl:SetAttribute("huf-init", InitSnippet(s.width, s.height))
end

local function RefButtons(ctl)
    for i, b in ipairs(G.buttons) do ctl:SetFrameRef("button" .. i, b) end
end

local function Create()
    if G.header then return end
    local h = CreateFrame("Frame", "HUF_Party", UIParent, "SecureGroupHeaderTemplate")
    G.header = h
    h.HUFInitButton = InitButton
    h:SetClampedToScreen(true)
    local ctl = CreateFrame("Frame", "HUF_PartyControl", UIParent, "SecureHandlerBaseTemplate")
    G.control = ctl
    ctl:SetFrameRef("header", h)
    Wanted(ctl)
    ctl:Execute(APPLY)
    ctl:Execute(CREATE)
    RefButtons(ctl)
    ns.Log("frame", "group header made, %d buttons", #G.buttons)
end

function G.Apply()
    local h = G.header
    if not h then return end
    local s = S()
    ns.RunOOC("group:apply", function()
        local ctl = G.control
        RefButtons(ctl)
        Wanted(ctl)
        ctl:Execute(APPLY)
        h:SetScale(s.scale)
        G.Place(h, s)
        local want = s.enabled and VISIBILITY or "hide"
        if h.hufWatch ~= want then
            UnregisterStateDriver(h, "visibility")
            RegisterStateDriver(h, "visibility", want)
            h.hufWatch = want
        end
        for _, b in ipairs(G.buttons) do Frame.LayoutSecure(b) end
        ns.Log("frame", "apply party: enabled=%s me=%s %s sort=%s size=%sx%s point=%s %s %s,%s",
            s.enabled, s.group.showPlayer, s.group.orientation, s.group.sort, s.width, s.height,
            s.point[1], s.point[2], s.point[3], s.point[4])
    end)
    for _, b in ipairs(G.buttons) do
        b.s = s
        ns.Try("layout group", Frame.LayoutInner, b)
        ns.Try("update group", Frame.Update, b)
    end
end

-- names, classes and units move around when the group changes
local function RosterChanged()
    for _, b in ipairs(G.buttons) do
        local unit = b:GetAttribute("unit")
        if unit ~= b.hunit then Frame.SetUnit(b, unit) elseif unit then Frame.Update(b) end
    end
end
ns.On("GROUP_ROSTER_UPDATE", RosterChanged)
ns.On("PLAYER_ENTERING_WORLD", RosterChanged)

function G.Report(add)
    local h = G.header
    if not h then add("group: header not made") return end
    add(("group: shown=%s buttons=%d driver=%s"):format(tostring(h:IsShown()), #G.buttons, tostring(h.hufWatch)))
    for i, b in ipairs(G.buttons) do
        add(("  party%d: unit=%s shown=%s"):format(i, tostring(b:GetAttribute("unit")), tostring(b:IsShown())))
    end
end

ns.OnLogin(function()
    ns.RunOOC("create:group", function()
        Create()
        G.Apply()
    end)
end)
ns.OnRefresh(function() if G.header then G.Apply() end end)
