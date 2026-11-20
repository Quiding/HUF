-- HUF: data bars. For now one: the minimap data bar, a strip under (or over)
-- the minimap, as wide as the map: friends online and guild members online
-- (a click opens the friends list / the guild window). The tracking button
-- can sit on its left end (Minimap: tracking at "Below, left").

local _, ns = ...
local DB = {}
ns.DataBars = DB

local function S() return ns.db.dataBars.minimap end

local bar
local blocks = {}

-- the game's own art, drawn from its sheet so it can be cropped. trim: the
-- share of the art's width kept (micro menu art has a wide empty border, which
-- at 10 px leaves only a smudge); the height is cut to keep it square. Sets
-- tex.aspect (width / height of what is shown). A plain file where the client
-- has no such atlas.
local function SetIcon(tex, atlas, file, trim, shift)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local sheet = info and (info.file or info.filename)
    if sheet and info.width and info.width > 0 and info.height and info.height > 0 then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local aspect = info.width / info.height
        if trim then
            local sy = math.min(1, trim * aspect)        -- the same pixels both ways
            -- shift: the picture is off the art's centre (a share of its width)
            local cx, cy = (l + r) / 2 + (r - l) * (shift or 0), (t + b) / 2
            local hw, hh = (r - l) * trim / 2, (b - t) * sy / 2
            l, r, t, b = cx - hw, cx + hw, cy - hh, cy + hh
            aspect = 1
        end
        tex:SetTexture(sheet)
        tex:SetTexCoord(l, r, t, b)
        tex.aspect = aspect
    else
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
        tex.aspect = 1
    end
end

local function FriendsOnline()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        local ok, v = pcall(C_FriendList.GetNumOnlineFriends)
        if ok and type(v) == "number" then n = n + v end
    end
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and type(online) == "number" then n = n + online end
    end
    return n
end

local function GuildOnline()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, _, online = pcall(GetNumGuildMembers)
    return ok and type(online) == "number" and online or 0
end

-- the icons' colour: flat (the art greyed, then tinted) or the art's own;
-- the accent while the mouse is on it
local function IconColor(b, hover)
    local s = S()
    local mode = s.iconColor or "MONO"
    b.icon:SetDesaturated(mode ~= "GAME" or hover)
    if hover then
        local a = ns.ACCENT
        b.icon:SetVertexColor(a[1], a[2], a[3])
    elseif mode == "GAME" then
        b.icon:SetVertexColor(1, 1, 1)
    elseif mode == "CLASS" then
        local _, cls = UnitClass("player")
        local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        b.icon:SetVertexColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    elseif mode == "ACCENT" then
        local a = ns.ACCENT
        b.icon:SetVertexColor(a[1], a[2], a[3])
    elseif mode == "CUSTOM" and s.iconCustom then
        b.icon:SetVertexColor(s.iconCustom.r, s.iconCustom.g, s.iconCustom.b)
    else
        b.icon:SetVertexColor(0.85, 0.85, 0.88)
    end
end

local BLOCKS = {
    { key = "friends", title = "Friends online", atlas = "socialqueuing-icon-group",
      file = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", count = FriendsOnline,
      click = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { key = "guild", title = "Guild members online", atlas = "UI-HUD-MicroMenu-GuildCommunities-Up", trim = 0.62, shift = 0.05,
      file = "Interface\\GossipFrame\\TabardGossipIcon", count = GuildOnline,
      click = function()
          if ToggleGuildFrame then ToggleGuildFrame()
          elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame() end
      end },
}

local function Build()
    if bar then return end
    bar = CreateFrame("Frame", "HUF_MinimapDataBar", UIParent)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.border = ns.UI.Border(bar, 0, 0, 0, 1)
    -- the tracking button's slot at the left end (Minimap places it there)
    bar.slot = CreateFrame("Frame", nil, bar)
    bar.slot.bg = bar.slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.slot.bg:SetAllPoints()
    bar.slot.bg:SetColorTexture(1, 1, 1, 0.04)
    bar.slot.line = bar.slot:CreateTexture(nil, "ARTWORK")
    bar.slot.line:SetPoint("TOPRIGHT")
    bar.slot.line:SetPoint("BOTTOMRIGHT")
    bar.slot.line:SetWidth(1)
    bar.slot.line:SetColorTexture(0, 0, 0, 1)
    for _, info in ipairs(BLOCKS) do
        local b = CreateFrame("Button", nil, bar)
        b.info = info
        b.icon = b:CreateTexture(nil, "ARTWORK")
        SetIcon(b.icon, info.atlas, info.file, info.trim, info.shift)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function() info.click() end)
        b:SetScript("OnEnter", function(self)
            IconColor(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(info.title)
            GameTooltip:AddLine(tostring(info.count() or 0), 1, 1, 1)
            GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) IconColor(self) GameTooltip:Hide() end)
        blocks[info.key] = b
    end
    bar:Hide()
end

-- the tracking button sits on the bar's end: Minimap's tracking at
-- "Below, left" (bar under the map) or "Above, left" (bar over it)
function DB.TrackingSlot()
    local s = S()
    if not (bar and bar:IsShown() and s.enabled) then return nil end
    local t = ns.db.minimap and ns.db.minimap.icons and ns.db.minimap.icons.tracking
    if not t or t.mode == "NEVER" then return nil end
    local want = (s.position == "ABOVE") and "ABOVE_LEFT" or "BELOW_LEFT"
    if t.pos ~= want then return nil end
    return bar.slot
end

-- the counts (and which blocks show: no guild, no guild block)
function DB.Update()
    if not (bar and bar:IsShown()) then return end
    local s = S()
    local shown = {}
    for _, info in ipairs(BLOCKS) do
        local b = blocks[info.key]
        local n = info.count()
        local on = s[info.key] ~= false and n ~= nil
        b:SetShown(on)
        if on then
            b.text:SetText(tostring(n))
            shown[#shown + 1] = b
        end
    end
    -- the blocks side by side, centred: icon, then the count (SIDE), or the
    -- count above a small icon (STACK)
    local stack = s.layout == "STACK"
    -- STACK: the icon takes ~60% of the bar; the count sits tight on top (a
    -- font string has empty room under its digits, so it may overlap a little)
    local size = stack and math.max(8, math.floor(s.height * 0.6 + 0.5)) or math.max(8, s.height - 6)
    local widths, total = {}, 0
    for i, b in ipairs(shown) do
        local iw = math.floor(size * (b.icon.aspect or 1) + 0.5)
        b.icon:SetSize(iw, size)
        b.icon:ClearAllPoints()
        b.text:ClearAllPoints()
        local w
        if stack then
            b.icon:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
            b.text:SetPoint("BOTTOM", b.icon, "TOP", 0, -1)
            w = math.max(iw, b.text:GetStringWidth() or 0)
        else
            b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
            w = iw + 2 + math.max(6, b.text:GetStringWidth() or 0)
        end
        widths[i] = math.ceil(w)
        if (widths[i] - iw) % 2 == 1 then widths[i] = widths[i] + 1 end   -- the icon on a whole pixel
        total = total + w + (i > 1 and s.spacing or 0)
    end
    -- the tracking slot takes the left end; the counts centre in the rest
    local slot = DB.TrackingSlot()
    local slotW = slot and s.height or 0
    bar.slot:SetShown(slot ~= nil)
    if slot then
        bar.slot:ClearAllPoints()
        bar.slot:SetPoint("TOPLEFT")
        bar.slot:SetPoint("BOTTOMLEFT")
        bar.slot:SetWidth(slotW)
    end
    local x = math.floor(-total / 2 + slotW / 2 + 0.5)
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetSize(widths[i], s.height)
        b:SetPoint("LEFT", bar, "CENTER", x, 0)
        x = x + widths[i] + s.spacing
    end
end

function DB.Apply()
    local s = S()
    if not s.enabled or not Minimap then
        if bar then bar:Hide() end
        return
    end
    Build()
    -- under (or over) the map, as wide as it is, outside its border
    -- as wide as the map's border (drawn outside the map); touching the map,
    -- the bar's own line lies on the map's bottom line (one line, not two)
    local mm = ns.db.minimap
    local mb = mm and mm.enabled and mm.borderSize or 0
    local bs = s.borderSize or 0
    local edge = mb + (s.gap or 0)
    if (s.gap or 0) == 0 and mb > 0 and bs > 0 then edge = mb - math.min(mb, bs) end
    local holder = Minimap:GetParent() or UIParent
    bar:SetParent(holder)
    bar:SetFrameStrata(Minimap:GetFrameStrata())
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)      -- under HUF's minimap icons (tracking on its end)
    bar:ClearAllPoints()
    if s.position == "ABOVE" then
        bar:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", -mb, edge)
        bar:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", mb, edge)
    else
        bar:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -mb, -edge)
        bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", mb, -edge)
    end
    -- the bar's line as thick as set (top, bottom, left, right)
    local e = bar.border.edges
    e[1]:SetHeight(math.max(1, bs)); e[2]:SetHeight(math.max(1, bs))
    e[3]:SetWidth(math.max(1, bs)); e[4]:SetWidth(math.max(1, bs))
    bar:SetHeight(s.height)
    local c = s.bgColor
    bar.bg:SetColorTexture(c.r, c.g, c.b, s.bgAlpha)
    bar.border:SetShown((s.borderSize or 0) > 0)
    for _, b in pairs(blocks) do
        ns.ApplyFont(b.text, "GLOBAL", s.fontSize, "GLOBAL")
        IconColor(b)
    end
    bar:Show()
    DB.Update()
    -- the tracking button follows (into the slot or out of it)
    if ns.Minimap and ns.Minimap.PlaceIcons then ns.Minimap.PlaceIcons() end
end

local function Soon()
    if DB.pending then return end
    DB.pending = true
    C_Timer.After(0.5, function() DB.pending = false DB.Update() end)
end
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
                     "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
    ns.On(e, Soon)
end
ns.OnLogin(function()
    DB.Apply()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    -- the minimap is laid out after login: follow it
    C_Timer.After(1, DB.Apply)
end)
ns.OnRefresh(function() if ns.ready then DB.Apply() end end)

---------------------------------------------------------------------------
-- Free data bars: any number, anywhere on screen, each with its own blocks
-- (DataBarBlocks.lua). Drag them in unlock mode.
---------------------------------------------------------------------------
local BL = ns.DataBlocks
local A = ns.ACCENT

DB.BAR_DEFAULTS = {
    enabled = true, name = "Bar",
    point = "CENTER", relPoint = "CENTER", x = 0, y = -200,
    width = 400, height = 22,
    look = "FLAT",              -- FLAT (solid colour, a line around it) | SOFT (dark, see-through, faded ends)
    bgColor = { r = 0.067, g = 0.067, b = 0.067 }, bgAlpha = 0.95, softAlpha = 0.5,
    borderSize = 1,
    visibility = "ALWAYS",      -- ALWAYS | COMBAT | NOCOMBAT | HOVER | NEVER
    sizing = "AUTO",            -- AUTO (as wide as each block's content; one block fills the rest) | EVEN
    fontSize = 12,
    blocks = {},
}

local recs = {}         -- [bar cfg] = { frame, blocks = { block frames }, pool }
local movers = {}

local function Bars() return ns.db.dataBars.bars end

-- the colour of an icon by its block's setting; the accent under the mouse
local function PaintIcon(b, hover)
    local c = b.cfg
    b.icon:SetDesaturated(c.iconColor ~= "GAME" or hover)
    if hover then b.icon:SetVertexColor(A[1], A[2], A[3]) return end
    if c.iconColor == "GAME" then b.icon:SetVertexColor(1, 1, 1) return end
    local r, g, bl = BL.Tint(c.iconColor, c.iconCustom)
    if r then b.icon:SetVertexColor(r, g, bl) else b.icon:SetVertexColor(0.85, 0.85, 0.88) end
end

local function SetBlockIcon(b, ic)
    if not ic or b.iconKey == ic then return end
    b.iconKey = ic
    BL.SetIcon(b.icon, ic.atlas, ic.file, ic.trim, ic.shift, ic.coords)
end

-- the block's text and colour; true when its width may have changed
local function UpdateBlock(b)
    local def = BL.TYPES[b.cfg.type]
    if not def then return false end
    if def.IconFor then SetBlockIcon(b, def.IconFor(b)) end
    local ok, text, r, g, bl = pcall(def.Text, b)
    if not ok then text = "" end
    text = text or ""
    local old = b.text:GetText() or ""
    b.text:SetText(text)
    local mode = b.cfg.textColor
    if mode == "DYNAMIC" and r then
        b.text:SetTextColor(r, g, bl)
    else
        local tr, tg, tb = BL.Tint(mode, b.cfg.textCustom)
        b.text:SetTextColor(tr or 1, tg or 1, tb or 1)
    end
    return old ~= text
end

local function BuildBlock(parent)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetWordWrap(false)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        if self.cfg.showIcon then PaintIcon(self, true) end
        local def = BL.TYPES[self.cfg.type]
        if def and def.Tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            pcall(def.Tooltip, self, GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.cfg.showIcon then PaintIcon(self) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button)
        local def = BL.TYPES[self.cfg.type]
        if def and def.Click then pcall(def.Click, self, button) end
        if UpdateBlock(self) then DB.LayoutBar(self.barCfg) end
    end)
    b:SetScript("OnMouseWheel", function(self, delta)
        local def = BL.TYPES[self.cfg.type]
        if def and def.Wheel then pcall(def.Wheel, self, delta) end
        UpdateBlock(self)
    end)
    return b
end

-- the block's content: icon, then the text
local function ContentWidth(b)
    local w = 0
    if b.cfg.showIcon then w = b.iconW end
    local tw = (b.text:GetText() or "") ~= "" and (b.text:GetStringWidth() or 0) or 0
    if tw > 0 then w = w + (w > 0 and 3 or 0) + tw end
    return math.ceil(w)
end

function DB.LayoutBar(cfg)
    local rec = recs[cfg]
    if not rec then return end
    local W, H = cfg.width, cfg.height
    local list = rec.blocks
    local n = #list
    if n == 0 then return end
    local even = cfg.sizing == "EVEN"
    local widths, fillAt, sum = {}, n, 0
    for i, b in ipairs(list) do
        if b.cfg.fill then fillAt = i end
    end
    for i, b in ipairs(list) do
        local pads = even and 0 or (b.cfg.padL + b.cfg.padR)
        widths[i] = ContentWidth(b) + pads
        if i ~= fillAt then sum = sum + widths[i] end
    end
    if even then
        for i = 1, n do widths[i] = W / n end
    else
        widths[fillAt] = math.max(widths[fillAt], W - sum)
    end
    local x = 0
    for i, b in ipairs(list) do
        local cw = widths[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", rec.frame, "TOPLEFT", math.floor(x + 0.5), 0)
        b:SetSize(math.max(1, math.floor(cw + 0.5)), H)
        -- the content inside its cell
        local padL, padR = even and 0 or b.cfg.padL, even and 0 or b.cfg.padR
        local content = ContentWidth(b)
        local left
        if b.cfg.align == "LEFT" then left = padL
        elseif b.cfg.align == "RIGHT" then left = cw - padR - content
        else left = padL + (cw - padL - padR - content) / 2 end
        left = math.floor(left + 0.5)
        b.icon:ClearAllPoints()
        b.text:ClearAllPoints()
        if b.cfg.showIcon then
            b.icon:SetPoint("LEFT", b, "LEFT", left, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
        else
            b.text:SetPoint("LEFT", b, "LEFT", left, 0)
        end
        x = x + cw
    end
end

local function Fade(t, a, reverse)
    t:SetColorTexture(1, 1, 1, 1)
    local from, to = 0, a
    if reverse then from, to = a, 0 end
    local ok = CreateColor and pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(0, 0, 0, from), CreateColor(0, 0, 0, to))
    if not ok and t.SetGradientAlpha then
        t:SetGradientAlpha("HORIZONTAL", 0, 0, 0, from, 0, 0, 0, to)
    end
    t:Show()
end

local function ApplyLook(rec, cfg)
    local f = rec.frame
    local c = cfg.bgColor
    f.bg:ClearAllPoints()
    if cfg.look == "SOFT" then
        -- dark, see-through, its ends faded out
        local a = cfg.softAlpha or 0.5
        local fw = math.floor(cfg.width * 0.12 + 0.5)
        f.fadeL:SetWidth(fw); f.fadeR:SetWidth(fw)
        Fade(f.fadeL, a, false)
        Fade(f.fadeR, a, true)
        f.bg:SetColorTexture(0, 0, 0, a)
        f.bg:SetPoint("TOPLEFT", f.fadeL, "TOPRIGHT")
        f.bg:SetPoint("BOTTOMRIGHT", f.fadeR, "BOTTOMLEFT")
    else
        f.bg:SetColorTexture(c.r, c.g, c.b, cfg.bgAlpha)
        f.bg:SetAllPoints()
        f.fadeL:Hide(); f.fadeR:Hide()
    end
    local bs = cfg.borderSize or 0
    f.border:SetShown(bs > 0)
    local e = f.border.edges
    e[1]:SetHeight(math.max(1, bs)); e[2]:SetHeight(math.max(1, bs))
    e[3]:SetWidth(math.max(1, bs)); e[4]:SetWidth(math.max(1, bs))
end

local function BarFrame(cfg)
    local rec = recs[cfg]
    if rec then return rec end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("LOW")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.fadeL = f:CreateTexture(nil, "BACKGROUND")
    f.fadeL:SetPoint("TOPLEFT"); f.fadeL:SetPoint("BOTTOMLEFT")
    f.fadeR = f:CreateTexture(nil, "BACKGROUND")
    f.fadeR:SetPoint("TOPRIGHT"); f.fadeR:SetPoint("BOTTOMRIGHT")
    f.border = ns.UI.Border(f, 0, 0, 0, 1)
    rec = { frame = f, blocks = {}, pool = {} }
    recs[cfg] = rec
    return rec
end

local function Wanted(cfg, rec)
    local v = cfg.visibility
    if v == "NEVER" then return false end
    if v == "COMBAT" then return UnitAffectingCombat("player") and true or false end
    if v == "NOCOMBAT" then return not UnitAffectingCombat("player") end
    if v == "HOVER" then return rec.frame:IsMouseOver() and true or false end
    return true
end

local hoverDriver
function DB.UpdateVisibility()
    local anyHover = false
    for cfg, rec in pairs(recs) do
        if rec.frame:IsShown() then
            rec.frame:SetAlpha((ns.unlocked or Wanted(cfg, rec)) and 1 or 0)
            if cfg.visibility == "HOVER" then anyHover = true end
        end
    end
    if anyHover and not hoverDriver then
        hoverDriver = CreateFrame("Frame")
        hoverDriver.t = 0
        hoverDriver:SetScript("OnUpdate", function(self, el)
            self.t = self.t + el
            if self.t < 0.1 then return end
            self.t = 0
            DB.UpdateVisibility()
        end)
    end
    if hoverDriver then hoverDriver:SetShown(anyHover) end
end

function DB.ApplyBar(cfg)
    ns.FillDefaults(cfg, DB.BAR_DEFAULTS)
    local rec = BarFrame(cfg)
    local f = rec.frame
    if not cfg.enabled or cfg.visibility == "NEVER" then f:Hide() return end
    f:ClearAllPoints()
    f:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    f:SetSize(cfg.width, cfg.height)
    ApplyLook(rec, cfg)
    -- the blocks (frames reused)
    for _, b in ipairs(rec.blocks) do b:Hide() rec.pool[#rec.pool + 1] = b end
    wipe(rec.blocks)
    for _, bc in ipairs(cfg.blocks) do
        local def = BL.TYPES[bc.type]
        if def then
            BL.Fill(bc)
            local b = table.remove(rec.pool) or BuildBlock(f)
            b.cfg, b.barCfg = bc, cfg
            local size = math.max(6, math.floor(cfg.fontSize * bc.scale / 100 + 0.5))
            ns.ApplyFont(b.text, "GLOBAL", size, "GLOBAL")
            b.iconKey = nil
            SetBlockIcon(b, def.IconFor and def.IconFor(b) or def.icon)
            b.iconW = math.floor((size + 2) * (b.icon.aspect or 1) + 0.5)
            b.icon:SetSize(b.iconW, size + 2)
            b.icon:SetShown(bc.showIcon)
            PaintIcon(b)
            b:EnableMouseWheel(def.Wheel ~= nil)
            UpdateBlock(b)
            b:Show()
            rec.blocks[#rec.blocks + 1] = b
        end
    end
    f:Show()
    DB.LayoutBar(cfg)
end

function DB.ApplyBars()
    local live = {}
    for _, cfg in ipairs(Bars()) do
        live[cfg] = true
        DB.ApplyBar(cfg)
    end
    -- bars that were deleted (or belong to another profile)
    for cfg, rec in pairs(recs) do
        if not live[cfg] then rec.frame:Hide() recs[cfg] = nil end
    end
    DB.UpdateVisibility()
    if ns.unlocked then DB.SetUnlocked(true) end
end

-- a new bar (from the settings page), a little under the screen's centre
function DB.NewBar()
    local cfg = ns.CopyTable(DB.BAR_DEFAULTS)
    cfg.name = "Bar " .. (#Bars() + 1)
    cfg.y = -200 - 30 * #Bars()
    cfg.blocks = { BL.New("fps"), BL.New("ms"), BL.New("clock") }
    cfg.blocks[3].fill = true
    table.insert(Bars(), cfg)
    return cfg
end

-- every block's text: each second (the ticking ones) and on their events
local function Tick(onlyType)
    for cfg, rec in pairs(recs) do
        if rec.frame:IsShown() then
            local moved = false
            for _, b in ipairs(rec.blocks) do
                local def = BL.TYPES[b.cfg.type]
                if def and ((onlyType == nil and def.tick) or onlyType == b.cfg.type) then
                    if UpdateBlock(b) then moved = true end
                end
            end
            if moved then DB.LayoutBar(cfg) end
        end
    end
end
for key, def in pairs(BL.TYPES) do
    for _, e in ipairs(def.events or {}) do
        pcall(ns.On, e, function() C_Timer.After(0.1, function() Tick(key) end) end)   -- an event this client lacks: skipped
    end
end
ns.On("PLAYER_REGEN_DISABLED", function() DB.UpdateVisibility() end)
ns.On("PLAYER_REGEN_ENABLED", function() DB.UpdateVisibility() end)

---------------------------------------------------------------------------
-- Unlock mode: a mover on each bar
---------------------------------------------------------------------------
local function Mover(cfg)
    local m = movers[cfg]
    if m then return m end
    m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    ns.UI.Fill(m, A[1], A[2], A[3], 0.25)
    ns.UI.Border(m, A[1], A[2], A[3], 1)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 2)
    m:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        local sx, sy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (sx and ux) then return end
        local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        cfg.point, cfg.relPoint = "CENTER", "CENTER"
        cfg.x = math.floor((sx * k - ux) + 0.5)
        cfg.y = math.floor((sy * k - uy) + 0.5)
        DB.ApplyBar(cfg)
        DB.SetUnlocked(true)
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(cfg.name or "Data bar")
        GameTooltip:AddLine("Drag to move. Settings: Frames > Data bars.", 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    movers[cfg] = m
    return m
end

function DB.SetUnlocked(on)
    for cfg, m in pairs(movers) do
        if not recs[cfg] then m:Hide() movers[cfg] = nil end
    end
    for cfg, rec in pairs(recs) do
        local f = rec.frame
        if on and f:IsShown() then
            local m = Mover(cfg)
            m.label:SetText(cfg.name or "Data bar")
            m:ClearAllPoints()
            m:SetAllPoints(f)
            m:Show()
        elseif movers[cfg] then
            movers[cfg]:Hide()
        end
    end
    DB.UpdateVisibility()
end

ns.OnLogin(function()
    DB.ApplyBars()
    C_Timer.NewTicker(1, function() Tick() end)
end)
ns.OnRefresh(function() if ns.ready then DB.ApplyBars() end end)
