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

-- the game's micro menu art; a plain texture where the client has no atlas
local function SetIcon(tex, atlas, file)
    if not (atlas and pcall(tex.SetAtlas, tex, atlas)) or not tex:GetAtlas() then
        tex:SetTexture(file)
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

local BLOCKS = {
    { key = "friends", title = "Friends online", atlas = "UI-HUD-MicroMenu-SocialJournal-Up",
      file = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon", count = FriendsOnline,
      click = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { key = "guild", title = "Guild members online", atlas = "UI-HUD-MicroMenu-GuildCommunities-Up",
      file = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", count = GuildOnline,
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
        SetIcon(b.icon, info.atlas, info.file)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function() info.click() end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(info.title)
            GameTooltip:AddLine(tostring(info.count() or 0), 1, 1, 1)
            GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    local size = stack and math.max(6, math.floor(s.height * 0.45)) or math.max(8, s.height - 6)
    local widths, total = {}, 0
    for i, b in ipairs(shown) do
        b.icon:SetSize(size, size)
        b.icon:ClearAllPoints()
        b.text:ClearAllPoints()
        local w
        if stack then
            b.icon:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
            b.text:SetPoint("BOTTOM", b.icon, "TOP", 0, 0)
            w = math.max(size, b.text:GetStringWidth() or 0)
        else
            b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
            w = size + 2 + math.max(6, b.text:GetStringWidth() or 0)
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
    for _, b in pairs(blocks) do ns.ApplyFont(b.text, "GLOBAL", s.fontSize, "GLOBAL") end
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
