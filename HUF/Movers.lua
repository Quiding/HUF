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

---------------------------------------------------------------------------
-- Snapping (General > Frames): a frame dragged in unlock mode (or a window
-- dragged by its title) jumps onto the nearest edge or middle of another
-- one within the snap distance while it is dragged: edges lined up, side by
-- side, middles lined up, or the screen's middle; a guide line shows it.
-- Alt held: no snapping. Snap.Register lists what can be snapped to.
---------------------------------------------------------------------------
local Snap = ns.Snap              -- made in Core.lua (the list of what can be snapped to)

-- the frame's rect in UIParent units
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not (l and w) then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * k, b * k, (l + w) * k, (b + h) * k
end
-- one inside the other (a mover on its own frame): never snapped to
local function Related(a, b)
    local p = a
    while p do if p == b then return true end p = p:GetParent() end
    p = b
    while p do if p == a then return true end p = p:GetParent() end
    return false
end

-- the nearest snap within the distance, as a move (dx, dy) and the lines it
-- lines up on (gx: an x, gy: a y; nil = none), all in UIParent units
local function Solve(f, L, B, R, T)
    local g = ns.db and ns.db.global
    if not g or g.snap == false or IsAltKeyDown() then return 0, 0 end
    local d = g.snapDistance or 8
    local gap = g.snapGap or 0
    local cx, cy = (L + R) / 2, (B + T) / 2
    local bx, by, gx, gy
    local function X(v, at) if math.abs(v) <= d and (not bx or math.abs(v) < math.abs(bx)) then bx, gx = v, at end end
    local function Y(v, at) if math.abs(v) <= d and (not by or math.abs(v) < math.abs(by)) then by, gy = v, at end end
    for t in pairs(Snap.targets) do
        if t ~= f and t:IsVisible() and not Related(t, f) then
            local l, b, r, tp = Rect(t)
            if l then
                X(l - L, l) X(r - R, r) X(r + gap - L, r + gap) X(l - gap - R, l - gap) X((l + r) / 2 - cx, (l + r) / 2)
                Y(b - B, b) Y(tp - T, tp) Y(b - gap - T, b - gap) Y(tp + gap - B, tp + gap) Y((b + tp) / 2 - cy, (b + tp) / 2)
            end
        end
    end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    X(W / 2 - cx, W / 2)
    Y(H / 2 - cy, H / 2)
    -- the grid (when it shows): its lines run from the screen's middle
    if g.grid and ns.unlocked then
        local s = math.max(4, g.gridSize or 32)
        local function Near(v, mid) return mid + math.floor((v - mid) / s + 0.5) * s end
        for _, e in ipairs({ L, R }) do local at = Near(e, W / 2) X(at - e, at) end
        for _, e in ipairs({ B, T }) do local at = Near(e, H / 2) Y(at - e, at) end
    end
    -- the same padding as another frame on the other side of the screen: this
    -- frame's gap to one edge = that one's gap to the opposite edge
    for t in pairs(Snap.targets) do
        if t ~= f and t:IsVisible() and not Related(t, f) then
            local l, b, r, tp = Rect(t)
            if l then
                X((W - r) - L, W - r) X((W - l) - R, W - l)
                Y((H - tp) - B, H - tp) Y((H - b) - T, H - b)
            end
        end
    end
    return bx or 0, by or 0, gx, gy
end

function Snap.Adjust(f)
    if not f then return end
    local L, B, R, T = Rect(f)
    if not L then return end
    local bx, by = Solve(f, L, B, R, T)
    if bx == 0 and by == 0 then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local l, b = f:GetLeft(), f:GetBottom()
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l + bx / k, b + by / k)
end

---------------------------------------------------------------------------
-- Dragging with live snapping and guide lines (like EllesmereUI's unlock
-- mode): HUF moves the frame itself with the cursor, snaps it while it is
-- being dragged and draws a line across the screen wherever it lines up.
-- Unlock mode also shows the screen's middle. Movers call Snap.StartDrag /
-- Snap.StopDrag in place of StartMoving / StopMovingOrSizing.
---------------------------------------------------------------------------
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("TOOLTIP")
guides:EnableMouse(false)
local function Line(alpha)
    local t = guides:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(A[1], A[2], A[3], alpha)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
    t:Hide()
    return t
end
local midV, midH = Line(0.35), Line(0.35)
-- while dragging: the frame's distance to each screen edge
local dist = {}
for i = 1, 4 do
    local fs = guides:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(A[1], A[2], A[3])
    fs:Hide()
    dist[i] = fs
end
local function ShowDistances(L, B, R, T)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = (L + R) / 2, (B + T) / 2
    local spots = {
        { L / 2, cy, L },              -- left
        { (R + W) / 2, cy, W - R },    -- right
        { cx, B / 2, B },              -- below
        { cx, (T + H) / 2, H - T },    -- above
    }
    for i, sp in ipairs(spots) do
        local fs = dist[i]
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", guides, "BOTTOMLEFT", sp[1], sp[2])
        fs:SetText(math.floor(sp[3] + 0.5))
        fs:Show()
    end
end
local function HideDistances() for i = 1, 4 do dist[i]:Hide() end end
local lineV, lineH = Line(0.95), Line(0.95)
-- one screen pixel in UIParent units
local function Px()
    local _, ph = GetPhysicalScreenSize()
    local es = UIParent:GetEffectiveScale()
    if ph and ph > 0 and es and es > 0 then return 768 / (ph * es) end
    return 1
end
local function PlaceV(t, x)
    t:ClearAllPoints()
    t:SetPoint("TOP", guides, "TOPLEFT", x, 0)
    t:SetPoint("BOTTOM", guides, "BOTTOMLEFT", x, 0)
    t:SetWidth(Px())
    t:Show()
end
local function PlaceH(t, y)
    t:ClearAllPoints()
    t:SetPoint("LEFT", guides, "BOTTOMLEFT", 0, y)
    t:SetPoint("RIGHT", guides, "BOTTOMRIGHT", 0, y)
    t:SetHeight(Px())
    t:Show()
end
-- the grid: faint lines every gridSize from the screen's middle
local gridLines = {}
function Snap.ShowGrid(on)
    for _, t in ipairs(gridLines) do t:Hide() end
    local g = ns.db and ns.db.global
    if not (on and g and g.grid) then return end
    local s = math.max(4, g.gridSize or 32)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function Get()
        n = n + 1
        local t = gridLines[n]
        if not t then
            t = guides:CreateTexture(nil, "BACKGROUND")
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
            gridLines[n] = t
        end
        t:SetColorTexture(1, 1, 1, g.gridAlpha or 0.12)
        return t
    end
    local k = math.floor((W / 2) / s)
    for i = -k, k do
        if i ~= 0 then PlaceV(Get(), W / 2 + i * s) end
    end
    k = math.floor((H / 2) / s)
    for i = -k, k do
        if i ~= 0 then PlaceH(Get(), H / 2 + i * s) end
    end
end

function Snap.ShowMiddle(on)
    local g = ns.db and ns.db.global
    if on and g and g.snapMiddle ~= false then
        PlaceV(midV, UIParent:GetWidth() / 2)
        PlaceH(midH, UIParent:GetHeight() / 2)
    else
        midV:Hide() midH:Hide()
    end
end

local drag = CreateFrame("Frame")
drag:Hide()
drag:SetScript("OnUpdate", function()
    local f = drag.f
    if not f then drag:Hide() return end
    local s = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local nl, nb = drag.l + cx / s - drag.x0, drag.b + cy / s - drag.y0
    local w, h = f:GetWidth(), f:GetHeight()
    local k = s / UIParent:GetEffectiveScale()
    -- kept on the screen
    local W, H = UIParent:GetWidth() / k, UIParent:GetHeight() / k
    nl = math.max(0, math.min(W - w, nl))
    nb = math.max(0, math.min(H - h, nb))
    local dx, dy, gx, gy = Solve(f, nl * k, nb * k, (nl + w) * k, (nb + h) * k)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl + dx / k, nb + dy / k)
    if gx then PlaceV(lineV, gx) else lineV:Hide() end
    if gy then PlaceH(lineH, gy) else lineH:Hide() end
    local fl, fb = (nl + dx / k) * k, (nb + dy / k) * k
    ShowDistances(fl, fb, fl + w * k, fb + h * k)
end)
function Snap.StartDrag(f)
    if not f or InCombatLockdown() then return end
    local l, b = f:GetLeft(), f:GetBottom()
    if not (l and b) then return end
    local s = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    drag.f, drag.l, drag.b, drag.x0, drag.y0 = f, l, b, cx / s, cy / s
    -- a box stretched over its frame (SetAllPoints) has no size of its own:
    -- keep the one it has, or it shrinks to nothing once re-anchored
    local w, h = f:GetWidth(), f:GetHeight()
    f:ClearAllPoints()
    f:SetSize(w, h)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    drag:Show()
end
function Snap.StopDrag(f)
    if drag.f == f then
        drag:GetScript("OnUpdate")(drag)     -- the last cursor position
        drag.f = nil
        drag:Hide()
    end
    lineV:Hide() lineH:Hide()
    HideDistances()
end

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
    Snap.StartDrag(self)
end

local function DragStop(self, key)
    Snap.StopDrag(self)
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
    Snap.Register(f)
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
    if key == "target" and ns.Combo then ns.Combo.Preview(f) end
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
    Snap.Register(box)
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
            -- two of them casting, to see the cast bar
            if i == 1 then Frame.FakeCast(f, 135907, "Flash Heal")
            elseif i == 4 then Frame.FakeCast(f, 135913, "Greater Heal") end
            f:Show()
        end
    end
    box:SetShown(ns.unlocked and s.enabled)
end

---------------------------------------------------------------------------
-- Unlock mode: a box over a window that keeps its place in its own setting
-- (bags, quest log, each damage meter window). While the window is closed
-- the box stands where it would open. Drag: the setting's offsets move by
-- as much (in the window's own scale); right-click: its settings.
-- spec: { label, page, on(), frame(), point(), size() (closed: w, h),
--         scale(), apply() }
---------------------------------------------------------------------------
local boxes = {}

-- Public (other addons, e.g. MMT): put a window of yours into HUF's unlock
-- mode, with a box, snapping, guide lines and the grid.
--   HUF.RegisterMover(id, {
--       label = "My window",
--       frame = frame (or a function returning it),
--       save = function(frame) end,  -- after a drop: the frame already stands where it was
--                                    -- dropped (BOTTOMLEFT to UIParent); store its place your way
--       shown = function() return true end,  -- optional: a box only while true (default: frame:IsShown())
--       settings = function() end,           -- optional: right-click on the box
--   })
--   HUF.UnregisterMover(id)
Movers.external = {}
function ns.RegisterMover(id, spec)
    if type(id) ~= "string" or type(spec) ~= "table" or type(spec.save) ~= "function" then return false end
    -- MMT interaction switched off: MMT's windows are declined
    if ns.Bridge and not ns.Bridge.Allowed() and (id:upper():find("^MMT") or tostring(spec.addon or ""):upper() == "MMT") then
        return false
    end
    local fr = spec.frame
    local getFrame = type(fr) == "function" and fr or function() return fr end
    Movers.external[id] = {
        external = true, label = tostring(spec.label or id), save = spec.save, settings = spec.settings,
        frame = getFrame,
        on = function()
            local f = getFrame()
            if not f then return false end
            if spec.shown and not spec.shown() then return false end
            return f:IsShown()
        end,
        point = function() return { "CENTER", "CENTER", 0, 0 } end, size = function() return 100, 100 end,
    }
    if ns.unlocked and Movers.LayoutAll then Movers.LayoutAll() end
    return true
end
function ns.UnregisterMover(id)
    Movers.external[id] = nil
    local m = boxes[id]
    if m then m:Hide() end
end

function Movers.PlaceBox(id)
    local m = boxes[id]
    if not m then return end
    local s = m.spec
    local okOn, on = pcall(s.on)
    if not (ns.unlocked and okOn and on) then m:Hide() return end
    m:ClearAllPoints()
    local f = s.frame and s.frame()
    if f and f:IsShown() then
        m:SetAllPoints(f)
    else
        local p, k = s.point(), s.scale and s.scale() or 1
        local w, h = s.size()
        m:SetSize(w * k, h * k)
        m:SetPoint(p[1], UIParent, p[2], (p[3] or 0) * k, (p[4] or 0) * k)
    end
    m:Show()
end
local function Box(id, spec)
    local m = boxes[id]
    if not m then
        m = CreateFrame("Button", nil, UIParent)
        m:SetFrameStrata("DIALOG")
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        m:RegisterForClicks("RightButtonUp")
        UI.Fill(m, A[1], A[2], A[3], 0.15)
        UI.Border(m, A[1], A[2], A[3], 0.8)
        m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.label:SetPoint("CENTER")
        m:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self.from = { self:GetLeft() or 0, self:GetTop() or 0 }
            Snap.StartDrag(self)
        end)
        m:SetScript("OnDragStop", function(self)
            Snap.StopDrag(self)
            local from = self.from
            self.from = nil
            if not from then return end
            local sp = self.spec
            if sp.external then
                -- another addon's window: HUF puts it where the box is, the addon stores it
                local f = sp.frame()
                local l, b = self:GetLeft(), self:GetBottom()
                if f and l and b then
                    local k = f:GetEffectiveScale() / self:GetEffectiveScale()
                    f:ClearAllPoints()
                    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l / k, b / k)
                    local ok, err = pcall(sp.save, f)
                    if not ok then ns.Print("Moving %s: %s", sp.label, tostring(err)) end
                end
                C_Timer.After(0, function() Movers.PlaceBox(id) end)
                return
            end
            local k = sp.scale and sp.scale() or 1
            local p = sp.point()
            p[3] = math.floor((p[3] or 0) + ((self:GetLeft() or 0) - from[1]) / k + 0.5)
            p[4] = math.floor((p[4] or 0) + ((self:GetTop() or 0) - from[2]) / k + 0.5)
            if sp.apply then pcall(sp.apply) end
            C_Timer.After(0, function() Movers.PlaceBox(id) end)
        end)
        m:SetScript("OnClick", function(self)
            local sp = self.spec
            if sp.settings then pcall(sp.settings) return end
            if ns.ToggleConfig and sp.page then ns.ToggleConfig(sp.page, true) end
        end)
        Snap.Register(m)
        boxes[id] = m
    end
    m.spec = spec
    m.label:SetText(spec.label)
    return m
end
-- the windows that get a box (built when unlock mode opens: the modules load later)
local function BoxSpecs()
    local list = {}
    local Bg = ns.Bags
    if Bg and ns.db.bags then
        local b = function() return ns.db.bags end
        list.bags = { label = "Bags", page = "bags", on = function() return b().enabled end, frame = Bg.Frame,
            point = function() return b().point end, size = function() return 380, 300 end,
            scale = function() return b().scale or 1 end, apply = Bg.Look }
    end
    local QL = ns.QuestLog
    if QL and ns.db.questLog then
        local q = function() return ns.db.questLog end
        list.questlog = { label = "Quest log", page = "questlog", on = function() return q().enabled end, frame = QL.Frame,
            point = function() return q().point end, size = function() return 700, 450 end,
            scale = function() return q().scale or 1 end, apply = QL.Look }
    end
    local LF = ns.LootFeed
    if LF and ns.db.lootFeed then
        local c = function() return ns.db.lootFeed end
        list.lootfeed = { label = "Loot feed", page = "general", on = function() return c().enabled end, frame = LF.Frame,
            point = function() return c().point end,
            size = function()
                local n = math.max(1, c().maxRows)
                return c().width, n * c().height + (n - 1) * (c().spacing or 2)
            end,
            apply = LF.Place }
    end
    local DM = ns.DamageMeter
    if DM and DM.Windows and ns.db.damageMeter then
        for i, w in ipairs(DM.Windows()) do
            list["meter" .. i] = { label = (i == 1) and "Damage meter" or ("Damage meter " .. i), page = "damagemeter",
                on = function() return ns.db.damageMeter.enabled and w:IsShown() end,
                frame = function() return w end,
                point = function() return w.cfg.point end, size = function() return w:GetWidth(), w:GetHeight() end,
                scale = function() return w:GetScale() or 1 end,
                apply = function()
                    -- the window to its saved place first (a failing layout must not undo the move)
                    local p = w.cfg.point
                    w:ClearAllPoints()
                    w:SetPoint(p[1], UIParent, p[2], p[3], p[4])
                    if DM.LayoutWindows then
                        local ok, err = pcall(DM.LayoutWindows, w)
                        if not ok then ns.Print("Damage meter layout after moving: %s", tostring(err)) end
                    end
                end }
        end
    end
    for id, sp in pairs(Movers.external) do list[id] = sp end
    return list
end
local function LayoutBoxes()
    if ns.unlocked then
        for id, spec in pairs(BoxSpecs()) do
            Box(id, spec)
            Movers.PlaceBox(id)
        end
    else
        for _, m in pairs(boxes) do m:Hide() end
    end
end

function Movers.LayoutAll()
    for _, info in ipairs(ns.UNITS) do Layout(info.key) end
    LayoutGroup()
    LayoutBoxes()
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
        LayoutBoxes()
    end
    if ns.Minimap then ns.Minimap.SetUnlocked(ns.unlocked) end
    if ns.PlayerAuras then ns.PlayerAuras.SetUnlocked(ns.unlocked) end
    if ns.DataBars and ns.DataBars.SetUnlocked then ns.DataBars.SetUnlocked(ns.unlocked) end
    if ns.Chat and ns.Chat.SetUnlocked then ns.Chat.SetUnlocked(ns.unlocked) end
    Snap.ShowMiddle(ns.unlocked)
    Snap.ShowGrid(ns.unlocked)
    Movers.UnlockPanel(ns.unlocked)
    if ns.RefreshConfig then ns.RefreshConfig() end
end

function Movers.Toggle() Movers.SetUnlocked(not ns.unlocked) end

---------------------------------------------------------------------------
-- The small unlock window (top middle of the screen): the settings window
-- steps aside while frames are unlocked; Lock ends unlock mode and brings
-- it back. A few settings for moving: snapping, its distance, the lines
-- through the screen's middle.
---------------------------------------------------------------------------
local panel, settingsWereOpen
local function G() return ns.db.global end
local function UnlockPanel()
    if panel then return panel end
    local p = CreateFrame("Frame", "HUF_UnlockPanel", UIParent)
    p:SetSize(280, 344)
    p:SetPoint("TOP", UIParent, "TOP", 0, -60)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    UI.Fill(p, 0.05, 0.05, 0.06, 0.95)
    UI.Border(p, A[1], A[2], A[3], 0.9)
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Frames unlocked")
    local note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 10, -26)
    note:SetPoint("TOPRIGHT", -10, -26)
    note:SetJustifyH("LEFT")
    note:SetText("Drag a box to move it, right-click it for its settings. Alt while dragging: no snapping.")
    local y = -56
    local function Add(w, h)
        w:SetPoint("TOPLEFT", 10, y)
        y = y - h
        return w
    end
    p.snap = Add(UI.Check(p, 260, "Snap to other frames",
        function() return G().snap ~= false end, function(v) G().snap = v end), UI.ROW - 2)
    p.mid = Add(UI.Check(p, 260, "Lines through the screen's middle",
        function() return G().snapMiddle ~= false end,
        function(v) G().snapMiddle = v Snap.ShowMiddle(ns.unlocked) end), UI.ROW + 2)
    p.dist = Add(UI.Slider(p, 260, "Snap distance", 2, 30, 1,
        function() return G().snapDistance or 8 end, function(v) G().snapDistance = v end), 40)
    p.gap = Add(UI.Slider(p, 260, "Space between frames side by side", 0, 20, 1,
        function() return G().snapGap or 0 end, function(v) G().snapGap = v end), 40)
    p.grid = Add(UI.Check(p, 260, "Show a grid (frames snap to it)",
        function() return G().grid and true or false end,
        function(v) G().grid = v Snap.ShowGrid(ns.unlocked) end), UI.ROW + 2)
    p.gridSize = Add(UI.Slider(p, 260, "Grid squares", 8, 128, 4,
        function() return G().gridSize or 32 end,
        function(v) G().gridSize = v Snap.ShowGrid(ns.unlocked) end), 40)
    p.gridAlpha = Add(UI.Slider(p, 260, "Grid opacity", 0.02, 0.6, 0.02,
        function() return G().gridAlpha or 0.12 end,
        function(v) G().gridAlpha = v Snap.ShowGrid(ns.unlocked) end, "%.2f"), 40)
    local lock = UI.Button(p, 125, "Lock", function() Movers.SetUnlocked(false) end)
    lock:SetPoint("BOTTOMLEFT", 10, 10)
    local open = UI.Button(p, 125, "Settings", function()
        settingsWereOpen = false
        if ns.ToggleConfig then ns.ToggleConfig(nil, true) end
    end)
    open:SetPoint("BOTTOMRIGHT", -10, 10)
    p:Hide()
    panel = p
    return p
end
-- shown / hidden with unlock mode (Movers.SetUnlocked)
function Movers.UnlockPanel(on)
    if on then
        settingsWereOpen = ns.ConfigShown and ns.ConfigShown() or false
        if settingsWereOpen and ns.HideConfig then ns.HideConfig() end
        local p = UnlockPanel()
        for _, k in ipairs({ "snap", "mid", "dist", "grid", "gridSize", "gridAlpha" }) do
            if p[k] and p[k].Refresh then p[k].Refresh() end
        end
        p:Show()
    else
        if panel then panel:Hide() end
        if settingsWereOpen and ns.ToggleConfig then ns.ToggleConfig(nil, true) end
        settingsWereOpen = false
    end
end

ns.OnRefresh(function() if ns.unlocked then Movers.LayoutAll() end end)
ns.On("PLAYER_REGEN_DISABLED", function() if ns.unlocked then Movers.SetUnlocked(false) end end)
