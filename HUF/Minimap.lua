-- HUF: the minimap.
--   * round or square, any size, moved in unlock mode (/huf unlock)
--   * look: a border (accent colour by default) and a dark shade outside
--   * texts placed on or around it: zone, clock, coordinates, FPS / latency
--   * the game's icons (tracking, calendar, mail, crafting orders, instance
--     difficulty, expansion summary, zoom) placed anywhere
--     on or around it, each shown always, on mouseover or never
--   * addon buttons: on the map (always / on mouseover / never, each button
--     its own), or all in the "addon bar": one button that opens a small bar
--     with them; it closes after a click on one of them or after 10 s
-- The map is taken out of Blizzard's MinimapCluster (which is made invisible)
-- into HUF's holder frame; nothing here is secure. Turning it off takes a
-- /reload to give the minimap back to Blizzard.

local _, ns = ...
local MM = {}
ns.Minimap = MM

local A = ns.ACCENT
local FLAT = "Interface\\Buttons\\WHITE8X8"
local DISK = ns.MEDIA .. "Minimap\\Disk"
local MASK_ROUND = 186178       -- the game's round minimap mask
local MASK_SQUARE = 130937      -- a plain square
local SHADE_LAYERS = 8

local function S() return ns.db.minimap end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

MM.active = false               -- the minimap is HUF's (this session)
local holder, back, textLayer, iconLayer, wheel, mover
local texts = {}                -- key -> button with .fs
local placed = {}               -- frame -> { key, ... } the game's icons HUF places
local hovering = false

---------------------------------------------------------------------------
-- Positions: inside the map (9 points) or outside (above / below)
---------------------------------------------------------------------------
-- pos -> point on the element, point on the map
local POS = {
    TOPLEFT = { "TOPLEFT", "TOPLEFT" }, TOP = { "TOP", "TOP" }, TOPRIGHT = { "TOPRIGHT", "TOPRIGHT" },
    LEFT = { "LEFT", "LEFT" }, CENTER = { "CENTER", "CENTER" }, RIGHT = { "RIGHT", "RIGHT" },
    BOTTOMLEFT = { "BOTTOMLEFT", "BOTTOMLEFT" }, BOTTOM = { "BOTTOM", "BOTTOM" }, BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT" },
    ABOVE_LEFT = { "BOTTOMLEFT", "TOPLEFT" }, ABOVE = { "BOTTOM", "TOP" }, ABOVE_RIGHT = { "BOTTOMRIGHT", "TOPRIGHT" },
    BELOW_LEFT = { "TOPLEFT", "BOTTOMLEFT" }, BELOW = { "TOP", "BOTTOM" }, BELOW_RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" },
    OUTSIDE_LEFT = { "RIGHT", "LEFT" }, OUTSIDE_RIGHT = { "LEFT", "RIGHT" },
    OUTSIDE_LEFT_TOP = { "TOPRIGHT", "TOPLEFT" }, OUTSIDE_LEFT_BOTTOM = { "BOTTOMRIGHT", "BOTTOMLEFT" },
    OUTSIDE_RIGHT_TOP = { "TOPLEFT", "TOPRIGHT" }, OUTSIDE_RIGHT_BOTTOM = { "BOTTOMLEFT", "BOTTOMRIGHT" },
}
MM.POSITIONS = {
    { value = "TOPLEFT", text = "Inside: top left" }, { value = "TOP", text = "Inside: top" },
    { value = "TOPRIGHT", text = "Inside: top right" }, { value = "LEFT", text = "Inside: left" },
    { value = "CENTER", text = "Inside: center" }, { value = "RIGHT", text = "Inside: right" },
    { value = "BOTTOMLEFT", text = "Inside: bottom left" }, { value = "BOTTOM", text = "Inside: bottom" },
    { value = "BOTTOMRIGHT", text = "Inside: bottom right" },
    { value = "ABOVE_LEFT", text = "Above, left" }, { value = "ABOVE", text = "Above, centered" },
    { value = "ABOVE_RIGHT", text = "Above, right" },
    { value = "BELOW_LEFT", text = "Below, left" }, { value = "BELOW", text = "Below, centered" },
    { value = "BELOW_RIGHT", text = "Below, right" },
    { value = "OUTSIDE_LEFT", text = "Left of the map" }, { value = "OUTSIDE_RIGHT", text = "Right of the map" },
    { value = "OUTSIDE_LEFT_TOP", text = "Left of the map, top" }, { value = "OUTSIDE_LEFT_BOTTOM", text = "Left of the map, bottom" },
    { value = "OUTSIDE_RIGHT_TOP", text = "Right of the map, top" }, { value = "OUTSIDE_RIGHT_BOTTOM", text = "Right of the map, bottom" },
}
MM.MODES = {
    { value = "ALWAYS", text = "Always" },
    { value = "HOVER", text = "On mouseover" },
    { value = "NEVER", text = "Never" },
}
-- the zone name can also show when it changes
MM.ZONE_MODES = {
    { value = "ALWAYS", text = "Always" },
    { value = "ENTER", text = "On mouseover and on a new zone" },
    { value = "HOVER", text = "On mouseover" },
    { value = "NEVER", text = "Never" },
}
local function Justify(pos)
    local p = (POS[pos] or POS.CENTER)[1]
    if p:find("LEFT") then return "LEFT" end
    if p:find("RIGHT") then return "RIGHT" end
    return "CENTER"
end
local function Place(f, cfg, extraY)
    local p = POS[cfg.pos] or POS.CENTER
    f:ClearAllPoints()
    f:SetPoint(p[1], Minimap, p[2], cfg.x or 0, (cfg.y or 0) + (extraY or 0))
end
-- ENTER (zone name): on mouseover, and for a few seconds after the zone or
-- subzone changes
local zoneShownUntil = 0
local ZONE_SECONDS = 5
local function Wanted(mode)
    if mode == "ALWAYS" then return true end
    if mode == "HOVER" then return hovering end
    if mode == "ENTER" then return hovering or GetTime() < zoneShownUntil end
    return false
end

---------------------------------------------------------------------------
-- The game's icons
---------------------------------------------------------------------------
local function Cluster() return _G.MinimapCluster end
local function Indicator() local c = Cluster() local i = c and c.IndicatorFrame return type(i) == "table" and i or nil end
MM.ICONS = {
    { key = "tracking", title = "Tracking", get = function()
        local c = Cluster()
        return (c and c.Tracking) or _G.MiniMapTracking or _G.MiniMapTrackingFrame end },
    { key = "calendar", title = "Calendar", get = function() return _G.GameTimeFrame end },
    { key = "mail", title = "Mail", get = function()
        local i = Indicator()
        return (i and i.MailFrame) or _G.MiniMapMailFrame end },
    { key = "crafting", title = "Crafting orders", get = function()
        local i = Indicator()
        return i and i.CraftingOrderFrame end },
    { key = "difficulty", title = "Instance difficulty", get = function()
        local c = Cluster()
        return (c and c.InstanceDifficulty) or _G.MiniMapInstanceDifficulty end },
    { key = "landing", title = "Expansion summary", get = function() return _G.ExpansionLandingPageMinimapButton end },
    { key = "zoom", title = "Zoom buttons", get = function()
        return Minimap.ZoomIn or _G.MinimapZoomIn, Minimap.ZoomOut or _G.MinimapZoomOut end },
}
local ICON_BY_KEY = {}
for _, i in ipairs(MM.ICONS) do ICON_BY_KEY[i.key] = i end

-- Blizzard's art HUF draws its own of (ring, top bar, north tag, clock)
local DECORATIONS = { "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture",
    "MinimapCompassTextureUnderlay", "TimeManagerClockButton", "MinimapZoneTextButton" }

local function ShowFrame(f, on, mouse)
    if not f then return end
    f:SetAlpha(on and 1 or 0)
    if f.EnableMouse and mouse ~= nil then f:EnableMouse(on and mouse) end
end

-- place one of the game's icons: on HUF's icon layer, where the setting says
-- tracking in the data bar's slot (defined below with IconVisibility)
local trackBtn, trackSlotted, TrackingButton

local function PlaceIcon(info, f, second)
    local d = placed[f]
    if not d then
        d = { info = info, second = second, mouse = f.IsMouseEnabled and f:IsMouseEnabled() or false }
        if type(f.Button) == "table" and f.Button.IsMouseEnabled then d.buttonMouse = f.Button:IsMouseEnabled() end
        placed[f] = d
        -- the game moves its icons back now and then (layouts, reparenting): put them back
        hooksecurefunc(f, "SetPoint", function(self)
            if d.busy or not MM.active then return end
            d.busy = true
            MM.PlaceIcons(self)
            d.busy = false
        end)
        if f.SetParent then
            hooksecurefunc(f, "SetParent", function(self, parent)
                if d.busy or not MM.active or parent == iconLayer then return end
                d.busy = true
                self:SetParent(iconLayer)
                d.busy = false
            end)
        end
    end
    local cfg = S().icons[info.key]
    d.busy = true
    if f:GetParent() ~= iconLayer then f:SetParent(iconLayer) end
    f:SetScale(S().iconScale)
    if second then
        -- zoom out right under zoom in
        f:ClearAllPoints()
        f:SetPoint("TOP", second, "BOTTOM", 0, -2)
    else
        local p = POS[cfg.pos] or POS.CENTER
        f:ClearAllPoints()
        local sc = S().iconScale
        -- tracking on the data bar's end: centred in its slot, above the bar
        local slot = info.key == "tracking" and ns.DataBars and ns.DataBars.TrackingSlot and ns.DataBars.TrackingSlot()
        if slot then
            f:SetPoint("CENTER", slot, "CENTER", 0, 0)
            trackSlotted = true
            TrackingButton(slot, f)
        else
            if info.key == "tracking" then
                trackSlotted = false
                if trackBtn then trackBtn:Hide() end
            end
            f:SetPoint(p[1], Minimap, p[2], (cfg.x or 0) / sc, (cfg.y or 0) / sc)
        end
    end
    d.busy = false
end

local function Tbl(v) return type(v) == "table" and v or nil end
function MM.PlaceIcons(only)
    if not MM.active then return end
    for _, info in ipairs(MM.ICONS) do
        local a, b = info.get()
        a, b = Tbl(a), Tbl(b)
        if a and (not only or only == a or only == b) then
            PlaceIcon(info, a)
            if b then PlaceIcon(info, b, a) end
        end
    end
end

-- tracking on the data bar's end: HUF's own clear button (the game's
-- magnifier art) opens the game's tracking menu; the game's button stays
-- hidden in the slot (the menu opens there)
local function OpenTracking(f)
    local b = f and (type(f.Button) == "table" and f.Button or f)
    if not b then return end
    if b.OpenMenu then pcall(b.OpenMenu, b)
    elseif b.Click then pcall(b.Click, b, "LeftButton") end
end
TrackingButton = function(slot, f)
    if not trackBtn then
        trackBtn = CreateFrame("Button", "HUF_MinimapTrackingButton", slot)
        trackBtn.icon = trackBtn:CreateTexture(nil, "ARTWORK")
        trackBtn.icon:SetAllPoints()
        -- a magnifying glass: the game's search box icon
        trackBtn.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        trackBtn.icon:SetVertexColor(0.85, 0.85, 0.88)
        trackBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        trackBtn:SetScript("OnClick", function(self) OpenTracking(self.game) end)
        trackBtn:SetScript("OnEnter", function(self)
            local a = ns.ACCENT
            self.icon:SetVertexColor(a[1], a[2], a[3])
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Tracking")
            GameTooltip:AddLine("Click: what the minimap shows", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        trackBtn:SetScript("OnLeave", function(self)
            self.icon:SetVertexColor(0.85, 0.85, 0.88)
            GameTooltip:Hide()
        end)
    end
    trackBtn.game = f
    trackBtn:SetParent(slot)
    trackBtn:SetFrameLevel(slot:GetFrameLevel() + 4)
    trackBtn:ClearAllPoints()
    trackBtn:SetPoint("CENTER", slot, "CENTER")
    local h = math.max(10, (slot:GetHeight() or 22) - 8)
    trackBtn:SetSize(h, h)
    trackBtn:Show()
end

local function IconVisibility()
    for f, d in pairs(placed) do
        local on = Wanted(S().icons[d.info.key].mode)
        if d.info.key == "tracking" and trackSlotted then
            ShowFrame(f, false, d.mouse)        -- HUF's button stands for it
            if trackBtn then trackBtn:SetShown(on) end
            on = false
        else
            ShowFrame(f, on, d.mouse)
        end
        if type(f.Button) == "table" and d.buttonMouse ~= nil then f.Button:EnableMouse(on and d.buttonMouse) end
    end
end

---------------------------------------------------------------------------
-- Addon buttons
---------------------------------------------------------------------------
local SKIP = {
    MinimapBackdrop = true, MinimapZoomIn = true, MinimapZoomOut = true, GameTimeFrame = true,
    TimeManagerClockButton = true, ExpansionLandingPageMinimapButton = true, AddonCompartmentFrame = true,
    MiniMapTracking = true, MiniMapTrackingFrame = true, MiniMapMailFrame = true, MiniMapInstanceDifficulty = true,
}
local PINS = { "^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate", "^[Pp]in", "^HUF_" }
local buttons, known = {}, {}   -- list of addon buttons; frame -> saved state
local bar, barButton

local function IsAddonButton(child)
    local name = child.GetName and child:GetName()
    if not name or SKIP[name] or placed[child] or child == wheel then return false end
    for _, pat in ipairs(PINS) do if name:match(pat) then return false end end
    if name:match("^LibDBIcon10_") then return true end
    if not child:IsObjectType("Button") then return false end
    if name:match("%d$") then return false end      -- numbered: map pins and the like
    return (child:GetWidth() or 0) >= 16
end

function MM.Scan()
    if not MM.active then return end
    local sources = { Minimap }
    if bar then sources[2] = bar end
    for _, src in ipairs(sources) do
        for _, child in ipairs({ src:GetChildren() }) do
            if not known[child] and IsAddonButton(child) then
                local d = { name = child:GetName(), mouse = child:IsMouseEnabled(), scale = child:GetScale(), points = {} }
                for i = 1, child:GetNumPoints() do d.points[i] = { child:GetPoint(i) } end
                known[child] = d
                buttons[#buttons + 1] = child
                -- a click on a button in the bar closes the bar
                child:HookScript("OnClick", function(self)
                    if bar and bar:IsShown() and self:GetParent() == bar then C_Timer.After(0, MM.CloseBar) end
                end)
                child:HookScript("OnMouseUp", function(self, b)
                    if b == "LeftButton" or b == "RightButton" then
                        if bar and bar:IsShown() and self:GetParent() == bar then C_Timer.After(0, MM.CloseBar) end
                    end
                end)
            end
        end
    end
    table.sort(buttons, function(a, b) return (known[a].name or "") < (known[b].name or "") end)
    MM.ApplyButtons()
end

-- what the settings page lists: name shown (addon) and the frame
function MM.Buttons()
    local l = {}
    for _, b in ipairs(buttons) do
        local n = known[b].name
        l[#l + 1] = { key = n, text = (n:gsub("^LibDBIcon10_", "")), frame = b }
    end
    return l
end

local function ButtonMode(b)
    local s = S()
    local m = s.buttons[known[b].name] or s.buttonMode
    if m == "PIN" then m = "ALWAYS" end         -- pinned (bag off): on the map
    return m
end

-- back on the map where the addon had it
local function ToMap(b)
    local d = known[b]
    d.pin = nil
    Unsquare(b)
    if b:GetParent() == Minimap and not d.inBar then return end
    d.inBar = nil
    b:SetParent(Minimap)
    b:SetScale(d.scale or 1)
    if d.strata then
        if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
        if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
        b:SetFrameStrata(d.strata)
        b:SetFrameLevel(d.level or 1)
        if d.fixedStrata and b.SetFixedFrameStrata then b:SetFixedFrameStrata(true) end
        if d.fixedLevel and b.SetFixedFrameLevel then b:SetFixedFrameLevel(true) end
    end
    b:ClearAllPoints()
    for _, p in ipairs(d.points) do b:SetPoint(p[1], p[2] or Minimap, p[3], p[4], p[5]) end
    if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
end

---------------------------------------------------------------------------
-- Square buttons in the bar (setting barSquare): the round frame and
-- background the minimap button library draws are hidden (recognised by the
-- game's own minimap button textures), the icon fills a dark square with a
-- thin outline. Everything comes back when the button leaves the bar.
---------------------------------------------------------------------------
local RING_FILES = { [136430] = true, [136467] = true, [136477] = true }
local RING_PATHS = { "MiniMap%-TrackingBorder", "UI%-Minimap%-Background", "UI%-Minimap%-ZoomButton%-Highlight" }
local function IsRing(r)
    if not (r and r.IsObjectType and r:IsObjectType("Texture")) then return false end
    local id = r.GetTextureFileID and r:GetTextureFileID()
    if id and RING_FILES[id] then return true end
    local path = r:GetTexture()
    if type(path) == "string" then
        for _, pat in ipairs(RING_PATHS) do if path:find(pat) then return true end end
    end
    return false
end

-- the button's picture: the library's .icon, else the first texture left
local function IconOf(b)
    local i = rawget(b, "icon")
    if type(i) == "table" and i.IsObjectType and i:IsObjectType("Texture") then return i end
    for _, r in ipairs({ b:GetRegions() }) do
        if r:IsObjectType("Texture") and not IsRing(r) and r ~= b.hufSqBg and r:GetDrawLayer() ~= "HIGHLIGHT" then return r end
    end
end

local function Square(b)
    local d = known[b]
    if d.sq then return end
    local sq = { hidden = {} }
    for _, r in ipairs({ b:GetRegions() }) do
        if IsRing(r) then
            sq.hidden[#sq.hidden + 1] = { r = r, a = r:GetAlpha() }
            r:SetAlpha(0)
        end
    end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl and IsRing(hl) then sq.hidden[#sq.hidden + 1] = { r = hl, a = hl:GetAlpha() } hl:SetAlpha(0) end
    local icon = IconOf(b)
    if icon then
        sq.icon = icon
        sq.points = {}
        for i = 1, icon:GetNumPoints() do sq.points[i] = { icon:GetPoint(i) } end
        sq.w, sq.h = icon:GetSize()
        sq.coords = { icon:GetTexCoord() }
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if not b.hufSqBg then
        b.hufSqBg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        b.hufSqBg:SetAllPoints()
        b.hufSqBg:SetColorTexture(0.04, 0.04, 0.05, 0.95)
        b.hufSqBorder = ns.UI.Border(b, 0, 0, 0, 1)
    end
    b.hufSqBg:Show()
    b.hufSqBorder:SetShown(true)
    d.sq = sq
end

local function Unsquare(b)
    local d = known[b]
    local sq = d and d.sq
    if not sq then return end
    for _, h in ipairs(sq.hidden) do h.r:SetAlpha(h.a or 1) end
    local icon = sq.icon
    if icon then
        icon:ClearAllPoints()
        for _, p in ipairs(sq.points) do icon:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        if sq.w and sq.w > 0 then icon:SetSize(sq.w, sq.h) end
        if sq.coords[1] then icon:SetTexCoord(unpack(sq.coords)) end
    end
    if b.hufSqBg then b.hufSqBg:Hide() b.hufSqBorder:SetShown(false) end
    d.sq = nil
end

local function ToBar(b)
    local d = known[b]
    if not d.inBar then
        -- remember where the addon has it now
        d.points = {}
        for i = 1, b:GetNumPoints() do d.points[i] = { b:GetPoint(i) } end
        d.scale = b:GetScale()
        d.strata, d.level = b:GetFrameStrata(), b:GetFrameLevel()
        d.fixedStrata = b.IsFrameStrataFixed and b:IsFrameStrataFixed() or false
        d.fixedLevel = b.IsFrameLevelFixed and b:IsFrameLevelFixed() or false
    end
    d.inBar = true
    if b:GetParent() ~= bar then b:SetParent(bar) end
    -- LibDBIcon fixes its buttons to MEDIUM strata: they'd sit behind the
    -- bar's background (DIALOG) and miss the clicks
    if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
    if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
    b:SetFrameStrata(bar:GetFrameStrata())
    b:SetFrameLevel(bar:GetFrameLevel() + 3)
    if b.RegisterForDrag then b:RegisterForDrag() end   -- no dragging it round the map from inside the bar
    if S().barSquare then Square(b) else Unsquare(b) end
end

-- a pinned button (buttons[name] = "PIN"): out of the bag, in a line that
-- starts at the bag button, styled like the bag's buttons
local function ToPin(b)
    local d = known[b]
    ToBar(b)                    -- saves where the addon had it (once), squares it
    d.pin = true
    if b:GetParent() ~= iconLayer then b:SetParent(iconLayer) end
    b:SetFrameStrata(iconLayer:GetFrameStrata())
    b:SetFrameLevel(iconLayer:GetFrameLevel() + 2)
end

function MM.LayoutPins()
    if not (barButton and MM.active) then return end
    local s = S()
    local list = {}
    for _, b in ipairs(buttons) do
        if known[b].pin then list[#list + 1] = b end
    end
    local order = s.pinOrder or {}
    table.sort(list, function(a, b)
        local oa, ob = order[known[a].name], order[known[b].name]
        if oa and ob and oa ~= ob then return oa < ob end
        if oa and not ob then return true end
        if ob and not oa then return false end
        return known[a].name < known[b].name
    end)
    local size, gap, grow = s.barIconSize, s.pinGap or 2, s.pinGrow or "UP"
    local show = s.addonBar and Wanted(s.icons.addonbar.mode)
    for i, b in ipairs(list) do
        local sc = size / math.max(1, b:GetWidth() or size)
        b:SetScale(sc)
        b:ClearAllPoints()
        local off = gap + (i - 1) * (size + gap)
        -- a column lines up with the bag button on its side away from the map
        -- (a bag left of the map: right edges), so it never reaches over it
        local leftOfMap = (s.icons.addonbar.pos or ""):find("^OUTSIDE_LEFT") ~= nil
        local side = leftOfMap and "RIGHT" or "LEFT"
        if grow == "RIGHT" then b:SetPoint("BOTTOMLEFT", barButton, "BOTTOMRIGHT", off / sc, 0)
        elseif grow == "LEFT" then b:SetPoint("BOTTOMRIGHT", barButton, "BOTTOMLEFT", -off / sc, 0)
        elseif grow == "DOWN" then b:SetPoint("TOP" .. side, barButton, "BOTTOM" .. side, 0, -off / sc)
        else b:SetPoint("BOTTOM" .. side, barButton, "TOP" .. side, 0, off / sc) end
        b:SetAlpha(show and 1 or 0)
        b:EnableMouse(show and known[b].mouse)
    end
end

function MM.ApplyButtons()
    if not MM.active then return end
    local s = S()
    for _, b in ipairs(buttons) do
        if s.addonBar and s.buttons[known[b].name] == "PIN" then
            ToPin(b)
        elseif s.addonBar then
            ToBar(b)
            known[b].pin = nil
            b:SetAlpha(1)
            b:EnableMouse(known[b].mouse)
        else
            ToMap(b)
            local mode = ButtonMode(b)
            local on = Wanted(mode)
            b:SetAlpha(on and 1 or 0)
            b:EnableMouse(on and known[b].mouse)
        end
    end
    if barButton then barButton:SetShown(s.addonBar and #buttons > 0 and Wanted(s.icons.addonbar.mode)) end
    MM.LayoutPins()
    if bar and bar:IsShown() then MM.LayoutBar() end
end

---------------------------------------------------------------------------
-- Addon bar
---------------------------------------------------------------------------
local function BuildBar()
    if bar then return end
    barButton = CreateFrame("Button", "HUF_MinimapAddonBarButton", iconLayer)
    barButton:SetSize(18, 18)
    barButton.bg = barButton:CreateTexture(nil, "BACKGROUND")
    barButton.bg:SetAllPoints()
    barButton.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
    barButton.border = ns.UI.Border(barButton, A[1], A[2], A[3], 1)
    barButton.dots = {}
    for i = 1, 4 do         -- a 2 x 2 grid: "more buttons in here"
        local t = barButton:CreateTexture(nil, "ARTWORK")
        t:SetSize(4, 4)
        t:SetPoint("CENTER", (i % 2 == 1) and -3 or 3, (i <= 2) and 3 or -3)
        barButton.dots[i] = t
    end
    barButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    barButton:SetScript("OnClick", function() MM.ToggleBar() end)
    barButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Addon buttons")
        GameTooltip:AddLine(("%d addons. Click to open."):format(#buttons), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    barButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar = CreateFrame("Frame", "HUF_MinimapAddonBar", UIParent)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    bar.border = ns.UI.Border(bar, A[1], A[2], A[3], 0.9)
    bar:Hide()
    -- closes after barTimeout seconds without the mouse over it
    bar:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or barButton:IsMouseOver() then self.idle = 0 return end
        self.idle = (self.idle or 0) + elapsed
        if self.idle >= (S().barTimeout or 10) then MM.CloseBar() end
    end)
end

function MM.LayoutBar()
    local s = S()
    local size, pad, gap = s.barIconSize, 4, 2
    local grow = s.barGrow
    if grow == "AUTO" then
        local x = barButton:GetCenter() or 0
        local w = UIParent:GetWidth() or 0
        grow = (x * barButton:GetEffectiveScale() / UIParent:GetEffectiveScale()) > w / 2 and "LEFT" or "RIGHT"
    end
    local vertical = grow == "UP" or grow == "DOWN"
    local grid = s.barLayout == "GRID"
    local list = {}
    for _, b in ipairs(buttons) do
        if b:IsShown() and known[b].inBar and not known[b].pin then list[#list + 1] = b end
    end
    local n = #list
    local cols = grid and math.max(1, math.min(n, s.barColumns or 4)) or (vertical and 1 or math.max(1, n))
    local rows = grid and math.max(1, math.ceil(n / cols)) or (vertical and math.max(1, n) or 1)
    for i, b in ipairs(list) do
        local bw = math.max(1, b:GetWidth() or size)
        local sc = size / bw
        b:SetScale(sc)
        b:ClearAllPoints()
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        if not grid and vertical then col, row = 0, i - 1 end
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", (pad + col * (size + gap)) / sc, -(pad + row * (size + gap)) / sc)
        b:SetAlpha(1)
    end
    bar:SetSize(pad * 2 + cols * size + (cols - 1) * gap, pad * 2 + rows * size + (rows - 1) * gap)
    bar:SetScale(holder:GetEffectiveScale() / UIParent:GetEffectiveScale())
    bar:ClearAllPoints()
    if grid then
        -- a grid opens beside the button, towards the screen's middle
        -- (up from a button in the lower half, down from one in the upper)
        local _, y = barButton:GetCenter()
        local h = UIParent:GetHeight() or 0
        local low = ((y or 0) * barButton:GetEffectiveScale() / UIParent:GetEffectiveScale()) < h / 2
        local side = (grow == "LEFT") and "LEFT" or (grow == "RIGHT" and "RIGHT")
        if not side then
            local x = barButton:GetCenter() or 0
            local w = UIParent:GetWidth() or 0
            side = (x * barButton:GetEffectiveScale() / UIParent:GetEffectiveScale()) > w / 2 and "LEFT" or "RIGHT"
        end
        if side == "LEFT" then
            bar:SetPoint(low and "BOTTOMRIGHT" or "TOPRIGHT", barButton, low and "BOTTOMLEFT" or "TOPLEFT", -3, 0)
        else
            bar:SetPoint(low and "BOTTOMLEFT" or "TOPLEFT", barButton, low and "BOTTOMRIGHT" or "TOPRIGHT", 3, 0)
        end
    elseif grow == "LEFT" then bar:SetPoint("RIGHT", barButton, "LEFT", -3, 0)
    elseif grow == "RIGHT" then bar:SetPoint("LEFT", barButton, "RIGHT", 3, 0)
    elseif grow == "UP" then bar:SetPoint("BOTTOM", barButton, "TOP", 0, 3)
    else bar:SetPoint("TOP", barButton, "BOTTOM", 0, -3) end
end

function MM.OpenBar()
    if not (bar and S().addonBar) then return end
    MM.Scan()
    bar.idle = 0
    MM.LayoutBar()
    bar:Show()
end
function MM.CloseBar() if bar then bar:Hide() end end
function MM.ToggleBar() if bar and bar:IsShown() then MM.CloseBar() else MM.OpenBar() end end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local ZONE_COLORS = {
    sanctuary = { 0.41, 0.80, 0.94 }, arena = { 1.00, 0.10, 0.10 }, hostile = { 1.00, 0.10, 0.10 },
    combat = { 1.00, 0.10, 0.10 }, friendly = { 0.10, 1.00, 0.10 }, contested = { 1.00, 0.70, 0.00 },
}
local function TextColor(fs, mode, zone)
    if mode == "ACCENT" then fs:SetTextColor(A[1], A[2], A[3]) return end
    if mode == "ZONE" and zone then
        local ok, pvp = pcall(GetZonePVPInfo)
        local c = ok and not IsSecret(pvp) and ZONE_COLORS[pvp or ""]
        if c then fs:SetTextColor(c[1], c[2], c[3]) return end
        fs:SetTextColor(1, 0.82, 0) return
    end
    fs:SetTextColor(1, 1, 1)
end

local function UpdateZone()
    local t = texts.zone
    if not t then return end
    local ok, z = pcall(GetMinimapZoneText)
    pcall(t.fs.SetText, t.fs, ok and z or "")
    TextColor(t.fs, S().texts.zone.color, true)
end

local function UpdateClock()
    local t = texts.clock
    if not t then return end
    local c = S().texts.clock
    local h, m
    if c.localTime then
        local d = date("*t")
        h, m = d.hour, d.min
    else
        h, m = GetGameTime()
    end
    if c.format == "12" then
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        t.fs:SetFormattedText("%d:%02d %s", h, m, ampm)
    else
        t.fs:SetFormattedText("%02d:%02d", h, m)
    end
end

local function UpdateCoords()
    local t = texts.coords
    if not t then return end
    local text = ""
    local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
    if okM and map and not IsSecret(map) then
        local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if okP and pos then
            local x, y = pos:GetXY()
            if x and y and not IsSecret(x) and not IsSecret(y) and (x > 0 or y > 0) then
                local d = S().texts.coords.decimals or 1
                local f = "%." .. d .. "f, %." .. d .. "f"
                text = f:format(x * 100, y * 100)
            end
        end
    end
    t.fs:SetText(text)
end

local function UpdateSystem()
    local t = texts.system
    if not t then return end
    local show = S().texts.system.show
    local fps = math.floor((GetFramerate() or 0) + 0.5)
    local _, _, home, world = GetNetStats()
    local ms = math.max(home or 0, world or 0)
    if show == "FPS" then t.fs:SetFormattedText("%d fps", fps)
    elseif show == "MS" then t.fs:SetFormattedText("%d ms", ms)
    else t.fs:SetFormattedText("%d fps  %d ms", fps, ms) end
end

local UPDATERS = { zone = UpdateZone, clock = UpdateClock, coords = UpdateCoords, system = UpdateSystem }
MM.TEXTS = {
    { key = "zone", title = "Zone name" },
    { key = "clock", title = "Clock" },
    { key = "coords", title = "Coordinates" },
    { key = "system", title = "FPS and latency" },
}

local function BuildText(key)
    local b = CreateFrame("Button", nil, textLayer)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetWordWrap(false)
    -- the text itself sits at the chosen point (as wide as its text, so the
    -- point alone decides left / center / right); the button covers the text
    b:SetAllPoints(b.fs)
    b:EnableMouse(false)
    if key == "clock" then
        -- left: stopwatch and alarm, right: calendar
        b:EnableMouse(true)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if ToggleCalendar then ToggleCalendar() end
            else
                if not TimeManager_Toggle and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager") end
                if TimeManager_Toggle then TimeManager_Toggle() end
            end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Clock")
            GameTooltip:AddLine("Left-click: stopwatch and alarm", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: calendar", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    texts[key] = b
    return b
end

local function LayoutTexts()
    local s = S()
    for _, info in ipairs(MM.TEXTS) do
        local b = texts[info.key] or BuildText(info.key)
        local c = s.texts[info.key]
        ns.ApplyFont(b.fs, s.font, c.size, s.outline)
        b.fs:SetJustifyH(Justify(c.pos))
        b.fs:SetWidth(0)
        Place(b.fs, c)
        TextColor(b.fs, c.color, info.key == "zone")
        UPDATERS[info.key]()
    end
end

local function TextVisibility()
    for _, info in ipairs(MM.TEXTS) do
        local b = texts[info.key]
        if b then
            local on = Wanted(S().texts[info.key].mode)
            if on and not b:IsShown() then UPDATERS[info.key]() end
            b:SetShown(on)
        end
    end
end

---------------------------------------------------------------------------
-- Mouseover and the ticker (texts, hover)
---------------------------------------------------------------------------
local function OverMap()
    if holder:IsMouseOver() then return true end
    for f in pairs(placed) do
        if f:IsVisible() and f:GetAlpha() > 0 and f:IsMouseOver() then return true end
    end
    if barButton and barButton:IsVisible() and barButton:IsMouseOver() then return true end
    if bar and bar:IsShown() then return true end
    for _, b in ipairs(buttons) do
        if b:IsVisible() and b:GetAlpha() > 0 and b:IsMouseOver() then return true end
    end
    return false
end

local function SetHover(on)
    if on == hovering then return end
    hovering = on
    TextVisibility()
    IconVisibility()
    MM.ApplyButtons()
end

local tick, slow = 0, 0
local function OnTick()
    if not MM.active then return end
    SetHover(OverMap())
    tick = tick + 1
    if texts.coords and texts.coords:IsShown() then UpdateCoords() end
    if tick % 5 == 0 then            -- once a second
        if texts.clock and texts.clock:IsShown() then UpdateClock() end
        if texts.system and texts.system:IsShown() then UpdateSystem() end
        IconVisibility()            -- the game re-shows its icons now and then
        local c = Cluster()
        if c and c:GetAlpha() > 0 then c:SetAlpha(0) c:EnableMouse(false) end
        slow = slow + 1
        if slow % 5 == 0 then MM.Scan() end     -- new addon buttons
    end
end

---------------------------------------------------------------------------
-- Look: border and shade behind the map
---------------------------------------------------------------------------
local function LayoutLook()
    local s = S()
    local round = s.shape == "ROUND"
    local size = s.size
    local tex = round and DISK or FLAT
    -- shade: stacked layers, each a bit larger and lighter, for a soft edge
    local a = 1 - (1 - math.min(0.99, s.shadeAlpha)) ^ (1 / SHADE_LAYERS)
    for i = 1, SHADE_LAYERS do
        local t = back.shade[i]
        t:SetTexture(tex)
        t:SetVertexColor(0, 0, 0, a)
        local w = size + 2 * s.borderSize + 2 * s.shade * i / SHADE_LAYERS
        t:ClearAllPoints()
        t:SetPoint("CENTER", Minimap, "CENTER")
        t:SetSize(w, w)
        t:SetShown(s.shade > 0 and s.shadeAlpha > 0)
    end
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    local bt = back.border
    bt:SetTexture(tex)
    bt:SetVertexColor(c.r, c.g, c.b, 1)
    bt:ClearAllPoints()
    bt:SetPoint("CENTER", Minimap, "CENTER")
    bt:SetSize(size + 2 * s.borderSize, size + 2 * s.borderSize)
    bt:SetShown(s.borderSize > 0)
end

---------------------------------------------------------------------------
-- Taking the map over
---------------------------------------------------------------------------
local function HideDecorations()
    for _, name in ipairs(DECORATIONS) do
        local f = _G[name]
        if f then
            -- textures only lose their alpha: other addons read the compass's rotation
            f:SetAlpha(0)
            if f.EnableMouse then f:EnableMouse(false) end
        end
    end
end

local function RefreshZoom()
    local z = Minimap:GetZoom() or 0
    local max = (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
    Minimap:SetZoom(z < max and z + 1 or math.max(0, z - 1))
    Minimap:SetZoom(z)
end

local function Build()
    if holder then return end
    holder = CreateFrame("Frame", "HUF_Minimap", UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetFrameLevel(1)
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)

    back = CreateFrame("Frame", nil, holder)
    back:SetAllPoints()
    back:SetFrameLevel(1)
    back.shade = {}
    for i = SHADE_LAYERS, 1, -1 do back.shade[i] = back:CreateTexture(nil, "BACKGROUND") end
    back.border = back:CreateTexture(nil, "BORDER")

    -- the wheel zooms over the whole map, also in a square map's corners (the
    -- game's own hit area is round); mouse clicks go through it
    wheel = CreateFrame("Frame", nil, Minimap)
    wheel:SetAllPoints(Minimap)
    wheel:EnableMouse(false)
    wheel:SetScript("OnMouseWheel", function(_, delta)
        local z = Minimap:GetZoom() or 0
        local max = (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
        Minimap:SetZoom(math.max(0, math.min(max, z + (delta > 0 and 1 or -1))))
    end)

    textLayer = CreateFrame("Frame", nil, Minimap)
    textLayer:SetAllPoints(Minimap)
    iconLayer = CreateFrame("Frame", nil, Minimap)
    iconLayer:SetAllPoints(Minimap)

    -- unlock mode: drag the map
    mover = CreateFrame("Button", nil, holder)
    mover:SetAllPoints(Minimap)
    mover:SetFrameStrata("HIGH")
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:RegisterForClicks("RightButtonUp")
    ns.UI.Fill(mover, A[1], A[2], A[3], 0.15)
    ns.UI.Border(mover, A[1], A[2], A[3], 0.8)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetText("Minimap")
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        mover.from = { holder:GetLeft(), holder:GetTop() }
        holder:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        holder:StopMovingOrSizing()
        if holder.SetUserPlaced then holder:SetUserPlaced(false) end
        local from = mover.from
        if not from then return end
        mover.from = nil
        local p = S().point
        p[3] = math.floor((p[3] or 0) + (holder:GetLeft() or 0) - (from[1] or 0) + 0.5)
        p[4] = math.floor((p[4] or 0) + (holder:GetTop() or 0) - (from[2] or 0) + 0.5)
        MM.Apply()
        C_Timer.After(0, function() MM.SetUnlocked(true) end)   -- the icon movers follow
    end)
    mover:SetScript("OnClick", function() if ns.ToggleConfig then ns.ToggleConfig("minimap", true) end end)
    mover:Hide()

    BuildBar()

    -- the game hands the map back to its cluster now and then (e.g. housing): take it again
    hooksecurefunc(Minimap, "SetParent", function(self, parent)
        if not MM.active or parent == holder or MM.busy then return end
        if InCombatLockdown() then MM.pending = true return end
        MM.busy = true
        self:SetParent(holder)
        MM.busy = false
        MM.Apply()
    end)
end

-- GetMinimapShape: how addons (LibDBIcon ...) place their buttons round the map
local function SetShapeGlobal()
    _G.GetMinimapShape = function()
        if MM.active and S().shape ~= "ROUND" then return "SQUARE" end
        return "ROUND"
    end
end

function MM.Apply()
    local s = S()
    if not s.enabled then
        if MM.active and not MM.warned then
            MM.warned = true
            ns.Print("The minimap goes back to Blizzard's after /reload.")
        end
        return
    end
    if not Minimap then return end
    if InCombatLockdown() then MM.pending = true return end
    Build()
    MM.active = true
    SetShapeGlobal()

    -- out of Blizzard's cluster, into HUF's holder
    local c = Cluster()
    if c then
        c:SetAlpha(0)
        c:EnableMouse(false)
    end
    MM.busy = true
    if Minimap:GetParent() ~= holder then Minimap:SetParent(holder) end
    MM.busy = false
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(holder:GetFrameLevel() + 3)
    Minimap:SetScale(1)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", holder, "CENTER")
    Minimap:SetSize(s.size, s.size)
    holder:SetSize(s.size, s.size)
    holder:SetScale(s.scale)
    holder:ClearAllPoints()
    holder:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    if not Minimap:IsShown() then Minimap:Show() end

    local round = s.shape == "ROUND"
    pcall(Minimap.SetMaskTexture, Minimap, round and MASK_ROUND or MASK_SQUARE)
    for _, m in ipairs({ "SetArchBlobRingScalar", "SetQuestBlobRingScalar", "SetTaskBlobRingScalar" }) do
        if Minimap[m] then pcall(Minimap[m], Minimap, round and 1 or 0) end
    end
    RefreshZoom()
    HideDecorations()

    textLayer:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    iconLayer:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    wheel:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    wheel:EnableMouseWheel(s.mouseZoom)

    LayoutLook()
    LayoutTexts()
    MM.PlaceIcons()
    local ab = s.icons.addonbar
    barButton:ClearAllPoints()
    local p = POS[ab.pos] or POS.RIGHT
    barButton:SetPoint(p[1], Minimap, p[2], ab.x or 0, ab.y or 0)
    if MM.LayoutPins then MM.LayoutPins() end
    -- square buttons: the bag button looks like them (their size, a thin dark
    -- outline, light dots; the accent under the mouse); else HUF's accent look
    local sqr = s.barSquare
    local bs = sqr and math.max(14, s.barIconSize or 18) or 18
    barButton:SetSize(bs, bs)
    barButton.sqr = sqr
    local dot = sqr and math.max(3, math.floor(bs / 5)) or 4
    for i, t in ipairs(barButton.dots) do
        t:SetSize(dot, dot)
        t:ClearAllPoints()
        local o = dot * 0.75 + (sqr and 1 or 0)
        t:SetPoint("CENTER", (i % 2 == 1) and -o or o, (i <= 2) and o or -o)
    end
    local function BagColors(over)
        if sqr and not over then
            barButton.border:SetColor(0, 0, 0, 1)
            for _, t in ipairs(barButton.dots) do t:SetColorTexture(0.8, 0.8, 0.82, 1) end
        else
            barButton.border:SetColor(A[1], A[2], A[3], 1)
            for _, t in ipairs(barButton.dots) do t:SetColorTexture(A[1], A[2], A[3], 1) end
        end
    end
    BagColors(false)
    if not barButton.hufHover then
        barButton.hufHover = true
        barButton:HookScript("OnEnter", function() if barButton.BagColors then barButton.BagColors(true) end end)
        barButton:HookScript("OnLeave", function() if barButton.BagColors then barButton.BagColors(false) end end)
    end
    barButton.BagColors = BagColors
    bar.border:SetColor(A[1], A[2], A[3], 0.9)
    if not s.addonBar then MM.CloseBar() end

    hovering = OverMap()
    TextVisibility()
    IconVisibility()
    MM.Scan()
    mover:SetShown(ns.unlocked and true or false)
    if not MM.ticker then MM.ticker = C_Timer.NewTicker(0.2, OnTick) end
end

function MM.Report(add)
    local s = S()
    local icons = {}
    for f, d in pairs(placed) do icons[#icons + 1] = d.info.key .. "=" .. tostring(f:GetAlpha() > 0 and "shown" or "hidden") end
    table.sort(icons)
    add(("minimap: enabled=%s active=%s shape=%s size=%d parent=%s cluster alpha=%s addonBar=%s buttons=%d hover=%s"):format(
        tostring(s.enabled), tostring(MM.active), s.shape, s.size,
        tostring(Minimap and Minimap:GetParent() == holder and "HUF" or "other"),
        tostring(Cluster() and Cluster():GetAlpha()), tostring(s.addonBar), #buttons, tostring(hovering)))
    add("minimap icons: " .. table.concat(icons, " "))
    local names = {}
    for _, b in ipairs(buttons) do names[#names + 1] = known[b].name end
    add("minimap addon buttons: " .. table.concat(names, " "))
end

-- unlock mode: the tracking button and the addon button bag can be dragged
-- anywhere, on the map or off it (saved as an offset from the map's centre)
local iconMovers = {}
local DRAGGABLE = {
    { key = "tracking", label = "Tracking", get = function() local i = ICON_BY_KEY.tracking return i and Tbl((i.get())) end },
    { key = "addonbar", label = "Bag", get = function() return barButton end },
}
local function IconMover(info)
    local m = iconMovers[info.key]
    if m then return m end
    m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    ns.UI.Fill(m, A[1], A[2], A[3], 0.35)
    ns.UI.Border(m, A[1], A[2], A[3], 1)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 2)
    m.label:SetText(info.label)
    m:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        -- the offset in the map's units (the icons are placed relative to it)
        local sx, sy = self:GetCenter()
        local mx, my = Minimap:GetCenter()
        if not (sx and mx) then return end
        local se, me = self:GetEffectiveScale(), Minimap:GetEffectiveScale()
        local cfg = S().icons[info.key]
        cfg.pos = "CENTER"
        cfg.x = math.floor((sx * se - mx * me) / me + 0.5)
        cfg.y = math.floor((sy * se - my * me) / me + 0.5)
        if cfg.mode == "NEVER" then cfg.mode = "ALWAYS" end
        MM.Apply()
        C_Timer.After(0, function() MM.SetUnlocked(true) end)
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(info.label)
        GameTooltip:AddLine("Drag it anywhere, on the map or off it.", 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconMovers[info.key] = m
    return m
end

function MM.SetUnlocked(on)
    if mover and MM.active then mover:SetShown(on and true or false) end
    for _, info in ipairs(DRAGGABLE) do
        local m = iconMovers[info.key]
        local f = MM.active and on and info.get()
        if f and f.GetCenter and f:GetCenter() then
            m = IconMover(info)
            local x, y = f:GetCenter()
            local fe, ue = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
            m:ClearAllPoints()
            m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * fe / ue, y * fe / ue)
            m:SetSize(math.max(16, (f:GetWidth() or 16) * fe / ue), math.max(16, (f:GetHeight() or 16) * fe / ue))
            m:Show()
        elseif m then
            m:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- a new zone or subzone: its name shows for a while (mode ENTER)
local function ZoneChanged()
    UpdateZone()
    if not MM.active or S().texts.zone.mode ~= "ENTER" then return end
    local t = GetTime()
    zoneShownUntil = t + ZONE_SECONDS
    TextVisibility()
    C_Timer.After(ZONE_SECONDS + 0.1, function()
        if GetTime() >= zoneShownUntil then TextVisibility() end
    end)
end
ns.On("ZONE_CHANGED", ZoneChanged)
ns.On("ZONE_CHANGED_INDOORS", ZoneChanged)
ns.On("ZONE_CHANGED_NEW_AREA", ZoneChanged)
ns.On("PLAYER_ENTERING_WORLD", ZoneChanged)
ns.On("PLAYER_ENTERING_WORLD", function()
    if not (HUFDB and ns.db and S().enabled) then return end
    MM.Apply()
    C_Timer.After(2, function() if MM.active then MM.PlaceIcons() MM.Scan() end end)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if MM.pending then MM.pending = false MM.Apply() end
end)
ns.OnLogin(function()
    if not S().enabled then return end
    if not _G.GameTimeFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager") end
    MM.Apply()
    C_Timer.After(1, function() if MM.active then MM.Scan() end end)
    C_Timer.After(5, function() if MM.active then MM.Scan() end end)
end)
ns.OnRefresh(function() if HUFDB and ns.db and (MM.active or S().enabled) then MM.Apply() end end)
