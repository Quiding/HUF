-- HUF: raid frames (PRIMARY FRAMES > Raid).
-- Ten secure group headers: Group 1-8 (groupFilter "1".."8"), the main
-- tanks (groupFilter "MAINTANK") and the raid's pets
-- (SecureGroupPetHeaderTemplate). Each one is a real unit-frame list:
-- clicks, @mouseover macros and click-casting work on its buttons.
--
-- Same rules as the party frames (Group.lua): every header attribute is set
-- inside a secure snippet of a controller (never from plain addon code,
-- which tainted the party header in 0.3.8-0.3.10); the buttons of the eight
-- groups and the main tanks are made right after login, outside combat.
--
-- Placing: each header is anchored by its growth corner, either to the
-- screen or to another header ("Frame Anchoring"). Until a header is set by
-- hand, its anchor and offsets follow from size, growth and padding
-- (R.Auto): Top > Bottom puts groups 1-4 side by side and 5-8 in a row
-- below; Left > Right stacks all eight below each other. Main tanks and pets
-- go below the groups.
--
-- Profiles: ns.db.raid.profiles[BASIC | HEALER | CUSTOM]; the active one
-- (ns.UnitSettings("raid")) is what Frame.lua reads as the buttons' settings.

local _, ns = ...
local Frame = ns.Frame
local UI = ns.UI

local R = {}
ns.Raid = R
R.KEYS = { "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "MT", "PET" }
R.TITLES = { G1 = "Group 1", G2 = "Group 2", G3 = "Group 3", G4 = "Group 4", G5 = "Group 5",
             G6 = "Group 6", G7 = "Group 7", G8 = "Group 8", MT = "Main Tank", PET = "Pets" }
R.PROFILES = { { value = "BASIC", text = "Basic" }, { value = "HEALER", text = "Healer" }, { value = "CUSTOM", text = "Custom" } }
R.headers, R.labels, R.buttons = {}, {}, {}

local VISIBILITY = "[group:raid] show; hide"

-- the settings key of a header's buttons: groups "raid", main tanks
-- "raidmt", pets "raidpet" (own texts, everything else the profile's)
function R.FrameKey(key)
    if key == "MT" then return "raidmt" elseif key == "PET" then return "raidpet" end
    return "raid"
end
local MEMBERS = 5          -- a group's size (also the column height of main tanks / pets)

local function DB() return ns.db.raid end
local function P() return ns.UnitSettings("raid") end
local function L() return P().layout end

-- growth: header point, member step, the corner a header is anchored by,
-- where further columns go (main tanks / pets with more than 5)
local GROWTH = {
    DOWN  = { point = "TOP",    dx = 0,  dy = -1, corner = "TOPLEFT",    col = "LEFT" },
    UP    = { point = "BOTTOM", dx = 0,  dy = 1,  corner = "BOTTOMLEFT", col = "LEFT" },
    RIGHT = { point = "LEFT",   dx = 1,  dy = 0,  corner = "TOPLEFT",    col = "TOP" },
    LEFT  = { point = "RIGHT",  dx = -1, dy = 0,  corner = "TOPRIGHT",   col = "TOP" },
}
R.GROWTH = GROWTH
local function Growth() return GROWTH[L().growth] or GROWTH.DOWN end
local function Vertical() local g = L().growth return g ~= "RIGHT" and g ~= "LEFT" end

---------------------------------------------------------------------------
-- Anchors and offsets
---------------------------------------------------------------------------
-- where a header goes when nobody set it by hand: to, x, y
function R.Auto(key)
    local s, l = P(), L()
    local w, h, px, py, gap = s.width, s.height, l.padX or 0, l.padY or 0, l.gap or 0
    if key == "G1" then return "SCREEN", s.point[3] or 0, s.point[4] or 0 end
    local n = tonumber(key:match("^G(%d)$"))
    if Vertical() then
        local sign = l.growth == "UP" and 1 or -1
        local groupH = MEMBERS * h + (MEMBERS - 1) * gap + py
        if n then
            if n == 5 then return "G1", 0, sign * groupH end
            return "G" .. (n - 1), w + px, 0
        end
        if key == "MT" then
            if l.growth == "UP" then return "G1", 0, -groupH end   -- below the lowest row
            return "G5", 0, -groupH
        end
        return "MT", w + px, 0                                     -- pets beside the main tanks
    end
    if n then return "G" .. (n - 1), 0, -(h + py) end
    if key == "MT" then return "G8", 0, -(h + py) end
    return "MT", 0, -(h + py)
end

-- does `key` (through its chain of anchors) hang on `on`?
function R.DependsOn(key, on)
    local seen = {}
    while key and key ~= "SCREEN" and not seen[key] do
        if key == on then return true end
        seen[key] = true
        key = R.Anchor(key)
    end
    return false
end

-- the anchor in use: to, x, y, set by hand?
function R.Anchor(key)
    local a = L().anchors[key]
    if type(a) == "table" and a.to then return a.to, a.x or 0, a.y or 0, true end
    return R.Auto(key)
end

-- a group's whole box (5 members): width, height
function R.GroupSize(key)
    local s = P()
    local n = key == "MT" and 2 or MEMBERS
    local gap = L().gap or 0
    if Vertical() then return s.width, n * s.height + (n - 1) * gap end
    return n * s.width + (n - 1) * gap, s.height
end

-- put `frame` (a header or its preview) where `key` belongs; lookup(k)
-- gives the frame of another key (real headers or previews)
function R.Place(frame, key, lookup)
    local to, x, y = R.Anchor(key)
    local corner = Growth().corner
    frame:ClearAllPoints()
    local rel = to ~= "SCREEN" and not R.DependsOn(to, key) and lookup(to)
    if rel then
        frame:SetPoint(corner, rel, corner, x, y)
        return
    end
    -- the screen: x / y are the group box's top left (party frames do the same)
    if to ~= "SCREEN" then to, x, y = "SCREEN", P().point[3] or 0, P().point[4] or 0 end
    local gw, gh = R.GroupSize(key)
    if corner == "BOTTOMLEFT" then y = y - gh elseif corner == "TOPRIGHT" then x = x + gw end
    frame:SetPoint(corner, UIParent, "TOPLEFT", x, y)
end

-- set by hand from now on (Frame Anchoring, or dragged in unlock mode)
function R.SetAnchor(key, to, x, y)
    if key == "G1" and to == "SCREEN" and not L().anchors.G1 then
        P().point[3], P().point[4] = x, y
        return
    end
    L().anchors[key] = { to = to, x = x, y = y }
end
function R.ResetAnchor(key)
    if key then L().anchors[key] = nil else wipe(L().anchors) end
end

---------------------------------------------------------------------------
-- Extras on each button: leader crown / assistant "A", the threat edge
---------------------------------------------------------------------------
local LEADER = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST = "Interface\\GroupFrame\\UI-Group-AssistantIcon"

local function Extras(b)
    if b.hufRaid then return end
    b.hufRaid = true
    local icon = b.textLayer:CreateTexture(nil, "OVERLAY")
    icon:SetSize(11, 11)
    icon:SetPoint("CENTER", b, "TOPLEFT", 6, -1)
    icon:Hide()
    b.roleIcon = icon
    local t = CreateFrame("Frame", nil, b)
    t:SetPoint("TOPLEFT", -2, 2)
    t:SetPoint("BOTTOMRIGHT", 2, -2)
    t:SetFrameLevel(b:GetFrameLevel() + 8)
    t.edges = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = t:CreateTexture(nil, "OVERLAY")
        e:SetColorTexture(0.9, 0.1, 0.1, 1)
        e:SetPoint(pts[1]) e:SetPoint(pts[2])
        if i <= 2 then e:SetHeight(2) else e:SetWidth(2) end
        t.edges[i] = e
    end
    t:Hide()
    b.threatEdge = t
end

local function Flag(fn, unit)
    local ok, v = pcall(fn, unit)
    return ok and not ns.IsSecret(v) and v and true or false
end

function R.UpdateExtras(b)
    if not b.hufRaid then return end
    local unit, fake = b.hunit, b.fake
    local lead, assist
    if fake then lead, assist = fake.leader, fake.assist
    elseif unit then lead, assist = Flag(UnitIsGroupLeader, unit), Flag(UnitIsGroupAssistant, unit) end
    if lead then b.roleIcon:SetTexture(LEADER) b.roleIcon:Show()
    elseif assist then b.roleIcon:SetTexture(ASSIST) b.roleIcon:Show()
    else b.roleIcon:Hide() end
    local threat = false
    if b.s.threatBorder then
        if fake then threat = fake.threat
        elseif unit then
            local ok, st = pcall(UnitThreatSituation, unit)
            threat = ok and not ns.IsSecret(st) and type(st) == "number" and st >= 2
        end
    end
    b.threatEdge:SetShown(threat and true or false)
end

---------------------------------------------------------------------------
-- The headers
---------------------------------------------------------------------------
local function InitSnippet(w, h)
    return ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("useOnKeyDown", false)
        self:GetParent():CallMethod("HUFInitButton", self:GetName())
    ]]):format(w, h)
end

local function InitButton(header, name)
    local b = name and _G[name]
    if not b or b.hufBuilt then return end
    b.hufBuilt = true
    local n = #R.buttons + 1
    b.hufLabel = "raid " .. (header.hufKey or "?") .. " " .. n
    local ok, err = pcall(Frame.Build, b, R.FrameKey(header.hufKey), true)
    if not ok then ns.LogError("raid button " .. n, err) return end
    Extras(b)
    b:HookScript("OnShow", function(self) Frame.Update(self) R.UpdateExtras(self) end)
    b:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "unit" then C_Timer.After(0, function() R.UpdateExtras(self) end) end
    end)
    R.buttons[n] = b
    Frame.SetUnit(b, b:GetAttribute("unit"))
    if ns.ClickCast then ns.ClickCast.Register(b) end
end

-- one header's settings, through the controller (see Group.lua for why)
local APPLY = [[
    local h = self:GetFrameRef("h" .. self:GetAttribute("huf-i"))
    local point, col = self:GetAttribute("huf-point"), self:GetAttribute("huf-col")
    if h:GetAttribute("point") ~= point or h:GetAttribute("columnAnchorPoint") ~= col then
        -- the header adds a new anchor to the old one: clear the old first
        local kids = newtable(h:GetChildren())
        for _, b in ipairs(kids) do b:ClearAllPoints() end
    end
    h:SetAttribute("point", point)
    h:SetAttribute("columnAnchorPoint", col)
    h:SetAttribute("xOffset", self:GetAttribute("huf-x"))
    h:SetAttribute("yOffset", self:GetAttribute("huf-y"))
    h:SetAttribute("columnSpacing", self:GetAttribute("huf-colsp"))
    h:SetAttribute("unitsPerColumn", self:GetAttribute("huf-upc"))
    h:SetAttribute("maxColumns", self:GetAttribute("huf-maxcol"))
    h:SetAttribute("groupFilter", self:GetAttribute("huf-filter"))
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("initialConfigFunction", self:GetAttribute("huf-init"))
    h:SetAttribute("huf-rev", self:GetAttribute("huf-rev"))
]]

-- the buttons now, outside combat: me alone, shown from index -3 = 5 buttons
local CREATE = [[
    local h = self:GetFrameRef("h" .. self:GetAttribute("huf-i"))
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("showRaid", true)
    h:SetAttribute("showParty", false)
    h:SetAttribute("showPlayer", true)
    if self:GetAttribute("huf-create") then
        h:SetAttribute("showSolo", true)
        h:SetAttribute("startingIndex", -3)
        h:Show()
        h:SetAttribute("startingIndex", 1)
    end
    h:SetAttribute("showSolo", false)
]]

local rev = 0
local function Wanted(ctl, i, key)
    local s, l, g = P(), L(), Growth()
    local gap = l.gap or 0
    ctl:SetAttribute("huf-i", i)
    ctl:SetAttribute("huf-point", g.point)
    ctl:SetAttribute("huf-col", g.col)
    ctl:SetAttribute("huf-x", g.dx * gap)
    ctl:SetAttribute("huf-y", g.dy * gap)
    ctl:SetAttribute("huf-colsp", Vertical() and (l.padX or 0) or (l.padY or 0))
    ctl:SetAttribute("huf-upc", MEMBERS)
    ctl:SetAttribute("huf-maxcol", key == "PET" and 8 or (key == "MT" and 2 or 1))
    local filter = key:match("^G(%d)$") or (key == "MT" and "MAINTANK") or nil
    ctl:SetAttribute("huf-filter", filter)
    ctl:SetAttribute("huf-init", InitSnippet(s.width, s.height))
    ctl:SetAttribute("huf-rev", rev)
end

local function Label(key)
    local lab = R.labels[key]
    if lab then return lab end
    lab = CreateFrame("Frame", nil, UIParent)
    lab:SetSize(1, 1)
    lab.text = lab:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(lab.text, "GLOBAL", 10, "GLOBAL")
    lab.text:SetPoint("BOTTOMLEFT")
    lab.text:SetTextColor(0.75, 0.75, 0.75)
    lab.text:SetText(R.TITLES[key])
    lab:Hide()
    R.labels[key] = lab
    return lab
end

-- a label above a group (or its preview), centred
local function PlaceLabel(lab, target)
    lab:ClearAllPoints()
    lab.text:ClearAllPoints()
    lab:SetPoint("BOTTOM", target, "TOP", 0, 1)
    lab.text:SetPoint("BOTTOM")
end

local function Create()
    if R.control then return end
    local ctl = CreateFrame("Frame", "HUF_RaidControl", UIParent, "SecureHandlerBaseTemplate")
    R.control = ctl
    for i, key in ipairs(R.KEYS) do
        local template = key == "PET" and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
        local name = key == "MT" and "HUF_RaidMT" or (key == "PET" and "HUF_RaidPets" or ("HUF_Raid" .. key:sub(2)))
        local ok, h = pcall(CreateFrame, "Frame", name, UIParent, template)
        if ok and h then
            h.hufKey = key
            h.HUFInitButton = InitButton
            h:SetClampedToScreen(true)
            R.headers[key] = h
            ctl:SetFrameRef("h" .. i, h)
            Wanted(ctl, i, key)
            ctl:Execute(APPLY)
            ctl:SetAttribute("huf-create", key ~= "PET")
            ctl:Execute(CREATE)
        else
            ns.Log("frame", "raid header %s not made: %s", key, tostring(h))
        end
    end
    ns.Log("frame", "raid headers made, %d buttons", #R.buttons)
end

---------------------------------------------------------------------------
-- Who is where (for the labels)
---------------------------------------------------------------------------
local present = {}
local function Roster()
    wipe(present)
    if not IsInRaid() then return end
    for i = 1, (GetNumGroupMembers() or 0) do
        local ok, _, _, sub, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, i)
        if ok then
            if type(sub) == "number" then present["G" .. sub] = true end
            if role == "MAINTANK" then present.MT = true end
        end
        if UnitExists("raidpet" .. i) then present.PET = true end
    end
end

local function UpdateLabels()
    local on = DB().enabled and IsInRaid()
    for _, key in ipairs(R.KEYS) do
        local h = R.headers[key]
        if h then
            local lab = Label(key)
            lab:SetShown(on and present[key] and h:IsShown() or false)
        end
    end
end

---------------------------------------------------------------------------
-- Example bars (the button on the settings page, and unlock mode)
---------------------------------------------------------------------------
local FIRST = { "Ardo", "Brisa", "Corvin", "Dalia", "Emmet", "Fenna", "Gorm", "Hilde", "Ivo", "Juna",
                "Kasper", "Lotte", "Magnus", "Nele", "Oswin", "Pia", "Quirin", "Rena", "Silas", "Tilda" }
local LAST = { "Ashbrook", "Brightwater", "Coldmere", "Dunmoor", "Emberfall", "Frostvale", "Greywind", "Hollowell" }
local CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "DRUID", "SHAMAN", "MAGE", "WARLOCK", "HUNTER", "ROGUE" }
local function Fake(i, key)
    local class = CLASSES[(i - 1) % #CLASSES + 1]
    local f = { first = FIRST[(i - 1) % #FIRST + 1], last = LAST[(i - 1) % #LAST + 1], class = class, player = true,
        level = 60, maxhp = 4000, hp = 1500 + ((i * 937) % 2500), maxpower = 3000, power = 600 + ((i * 431) % 2400),
        powerToken = (class == "WARRIOR") and "RAGE" or ((class == "ROGUE") and "ENERGY" or "MANA"),
        slot = i, classIndex = math.floor((i - 1) / #CLASSES) + 1 }
    if f.powerToken ~= "MANA" then f.maxpower, f.power = 100, 20 + (i * 13) % 80 end
    if key == "PET" then f = { first = "Pet " .. i, level = 60, maxhp = 2400, hp = 1200 + (i * 211) % 1200,
        maxpower = 100, power = 60, powerToken = "FOCUS" } end
    f.leader = i == 1
    f.assist = i == 2 or i == 7
    f.threat = i == 6 or i == 41
    f.dead = i == 13
    f.offline = i == 18
    if i % 7 == 3 then f.incoming = 900 end
    return f
end

local preview = {}         -- [key] = container with .members
local function PreviewFrame(key) return preview[key] end
R.PreviewFrame = PreviewFrame

local function BuildPreview()
    if next(preview) then return end
    local idx = 0
    for _, key in ipairs(R.KEYS) do
        local box = CreateFrame("Frame", nil, UIParent)
        box:SetFrameStrata("MEDIUM")
        box.label = box:CreateFontString(nil, "OVERLAY")
        ns.ApplyFont(box.label, "GLOBAL", 10, "GLOBAL")
        box.label:SetTextColor(0.75, 0.75, 0.75)
        box.label:SetText(R.TITLES[key])
        box.members = {}
        local n = key == "MT" and 2 or MEMBERS
        for m = 1, n do
            idx = idx + 1
            local f = CreateFrame("Frame", nil, box)
            Frame.Build(f, R.FrameKey(key), false)
            Extras(f)
            f.fake = Fake(key == "MT" and m or (key == "PET" and 40 + m or idx), key)
            f:EnableMouse(false)
            box.members[m] = f
        end
        box:Hide()
        preview[key] = box
    end
end

local function LayoutPreview()
    if not next(preview) then return end
    local s, g = P(), Growth()
    local gap = L().gap or 0
    for _, key in ipairs(R.KEYS) do
        local box = preview[key]
        local gw, gh = R.GroupSize(key)
        box:SetSize(gw, gh)
        box:SetScale(s.scale or 1)
        R.Place(box, key, PreviewFrame)
        box.label:ClearAllPoints()
        box.label:SetPoint("BOTTOM", box, "TOP", 0, 1)
        local ks = ns.UnitSettings(R.FrameKey(key))
        for m, f in ipairs(box.members) do
            f.s = ks
            f:ClearAllPoints()
            local o = m - 1
            if g.dy ~= 0 then
                f:SetPoint(g.corner, box, g.corner, 0, g.dy * o * (s.height + gap))
            else
                f:SetPoint(g.corner, box, g.corner, g.dx * o * (s.width + gap), 0)
            end
            f:SetSize(s.width, s.height)
            Frame.LayoutInner(f)
            Frame.Update(f)
            if f.fake.class and Frame.CastAllowed(f) and (f.fake.slot or 0) % 4 == 1 then
                Frame.FakeCast(f, 136048, "Healing Touch")
            elseif f.cast then
                ns.Cast.Stop(f.cast, true)
            end
            R.UpdateExtras(f)
        end
    end
end

R.examples = false
function R.ShowExamples(on)
    if on == nil then on = not R.examples end
    R.examples = on and true or false
    R.LayoutPreviewNow()
end
function R.LayoutPreviewNow()
    local show = DB().enabled and (R.examples or ns.unlocked)
    if show then BuildPreview() LayoutPreview() end
    for _, box in pairs(preview) do box:SetShown(show and true or false) end
end
function R.SetUnlocked() R.LayoutPreviewNow() end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
-- the cast bar sits on the resource bar (on the health bar's bottom edge without one)
local function SyncCast(s)
    local cb, pw = s.castBar, s.power
    if pw.enabled then
        cb.height = math.max(3, pw.size)
        cb.y = -((pw.gap or 0) + pw.size / 2)
    else
        cb.height, cb.y = 4, 2
    end
    cb.x = 0
end

function R.Apply()
    local s = P()
    SyncCast(s)
    if not DB().enabled then
        if R.control then
            ns.RunOOC("raid:hide", function()
                for _, h in pairs(R.headers) do
                    if h.hufWatch ~= "hide" then
                        UnregisterStateDriver(h, "visibility")
                        RegisterStateDriver(h, "visibility", "hide")
                        h.hufWatch = "hide"
                    end
                end
            end)
        end
        UpdateLabels()
        R.LayoutPreviewNow()
        return
    end
    ns.RunOOC("raid:apply", function()
        Create()
        rev = rev + 1
        local ctl = R.control
        for i, key in ipairs(R.KEYS) do
            local h = R.headers[key]
            if h then
                Wanted(ctl, i, key)
                ctl:Execute(APPLY)
            end
        end
        for _, b in ipairs(R.buttons) do b.s = ns.UnitSettings(b.key) Frame.LayoutSecure(b) end
        for _, key in ipairs(R.KEYS) do
            local h = R.headers[key]
            if h then
                h:SetScale(s.scale or 1)
                R.Place(h, key, function(k) return R.headers[k] end)
                PlaceLabel(Label(key), h)
                if h.hufWatch ~= VISIBILITY then
                    UnregisterStateDriver(h, "visibility")
                    RegisterStateDriver(h, "visibility", VISIBILITY)
                    h.hufWatch = VISIBILITY
                end
            end
        end
        ns.Log("frame", "apply raid: profile=%s growth=%s size=%sx%s pad=%s/%s", DB().profile, L().growth, s.width, s.height, L().padX, L().padY)
    end)
    for _, b in ipairs(R.buttons) do
        b.s = ns.UnitSettings(b.key)
        ns.Try("layout raid", Frame.LayoutInner, b)
        ns.Try("update raid", Frame.Update, b)
        R.UpdateExtras(b)
    end
    Roster()
    UpdateLabels()
    R.LayoutPreviewNow()
end

local function RosterChanged()
    for _, b in ipairs(R.buttons) do
        local unit = b:GetAttribute("unit")
        if unit ~= b.hunit then Frame.SetUnit(b, unit) elseif unit then Frame.Update(b) end
        R.UpdateExtras(b)
    end
    Roster()
    UpdateLabels()
end
ns.On("GROUP_ROSTER_UPDATE", RosterChanged)
ns.On("PARTY_LEADER_CHANGED", RosterChanged)
ns.On("PLAYER_ENTERING_WORLD", RosterChanged)
ns.On("UNIT_PET", function() C_Timer.After(0.2, function() Roster() UpdateLabels() end) end)
ns.On("UNIT_THREAT_SITUATION_UPDATE", function(unit)
    for _, b in ipairs(R.buttons) do if b.hunit and (not unit or b.hunit == unit) then R.UpdateExtras(b) end end
end)

function R.Report(add)
    local d = DB()
    add(("raid: enabled=%s profile=%s headers=%d buttons=%d growth=%s examples=%s"):format(tostring(d.enabled), tostring(d.profile),
        (function() local n = 0 for _ in pairs(R.headers) do n = n + 1 end return n end)(), #R.buttons, tostring(L().growth), tostring(R.examples)))
    for _, key in ipairs(R.KEYS) do
        local h = R.headers[key]
        local to, x, y, manual = R.Anchor(key)
        add(("  %s: %s %s,%s%s shown=%s"):format(key, to, x, y, manual and " (by hand)" or "", h and tostring(h:IsShown()) or "no header"))
    end
end

ns.OnLogin(function()
    if DB().enabled then ns.RunOOC("create:raid", function() Create() R.Apply() end) end
end)
ns.OnRefresh(function() R.Apply() end)
