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
local function SetIcon(tex, atlas, file, trim)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local sheet = info and (info.file or info.filename)
    if sheet and info.width and info.width > 0 and info.height and info.height > 0 then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local aspect = info.width / info.height
        if trim then
            local sy = math.min(1, trim * aspect)        -- the same pixels both ways
            local cx, cy = (l + r) / 2, (t + b) / 2
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
    { key = "guild", title = "Guild members online", atlas = "UI-HUD-MicroMenu-GuildCommunities-Up", trim = 0.62,
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
        SetIcon(b.icon, info.atlas, info.file, info.trim)
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
        widths[i] = w
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
    local x = -total / 2 + slotW / 2
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
    local mm = ns.db.minimap
    local edge = (mm and mm.enabled and mm.borderSize or 0) + (s.gap or 0)
    local holder = Minimap:GetParent() or UIParent
    bar:SetParent(holder)
    bar:SetFrameStrata(Minimap:GetFrameStrata())
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)      -- under HUF's minimap icons (tracking on its end)
    bar:ClearAllPoints()
    if s.position == "ABOVE" then
        bar:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", 0, edge)
        bar:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", 0, edge)
    else
        bar:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, -edge)
        bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -edge)
    end
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
