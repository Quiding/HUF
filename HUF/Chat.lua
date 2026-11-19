-- HUF: the chat window.
--   * look: font, size, outline, background colour and opacity (the game's
--     own window colour / alpha, so it stays with the window)
--   * short channel names at the start of a line ([1], [2], [S], [P], [G] ...)
--   * URLs as clickable links (a copy box opens), link tooltips on mouseover
--   * class coloured names (the game's own per chat type setting)
--   * chat history kept over /reload and logout (up to 2000 lines a window)
--   * buttons beside the chat: copy, guild (members online), friends, and the
--     game's chat channel and chat menu buttons moved there; they fade out
--   * the input line below or above the chat
--   * the game's chat settings (bubbles, timestamps, style, colours) on one page
--
-- Taint rules (from EllesmereUI's chat engine): never replace a field on a
-- chat frame, never hook FCF_* functions, never reparent Blizzard chat parts.
-- The one hook is a post-hook on each window's AddMessage (hooksecurefunc):
-- it rewrites the line just stored in the window's history buffer and lets
-- the window redraw. Secret lines (chat lockdown in encounters, M+, PvP,
-- instances) are never read or changed: they stay as the game made them.

local _, ns = ...
local Chat = {}
ns.Chat = Chat

local A = ns.ACCENT
local function S() return ns.db.chat end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local hooked = {}             -- chat frame -> true
local restoring = false

---------------------------------------------------------------------------
-- Chat windows
---------------------------------------------------------------------------
local function Windows()
    local list = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then list[#list + 1] = cf end
    end
    -- whisper / pet battle windows the game opens later (ChatFrame11+)
    for i = (NUM_CHAT_WINDOWS or 10) + 1, 40 do
        local cf = _G["ChatFrame" .. i]
        if cf then list[#list + 1] = cf end
    end
    return list
end

local function SelectedWindow()
    if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
        local ok, cf = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and cf then return cf end
    end
    return SELECTED_CHAT_FRAME or ChatFrame1
end

local function IsCombatLog(cf)
    return cf == _G.ChatFrame2 or (cf.GetName and cf:GetName() == "ChatFrame2")
end

---------------------------------------------------------------------------
-- Line rewriting: short channel names, URLs
---------------------------------------------------------------------------
-- event (without CHAT_MSG_) -> setting key
local CHANNEL_KEYS = {
    PARTY = "PARTY", PARTY_LEADER = "PARTY_LEADER", PARTY_GUIDE = "PARTY_LEADER",
    GUILD = "GUILD", OFFICER = "OFFICER",
    RAID = "RAID", RAID_LEADER = "RAID_LEADER", RAID_WARNING = "RAID_WARNING",
    INSTANCE_CHAT = "INSTANCE_CHAT", INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
}
-- "%s says: " style templates (the name is a link, the rest plain text)
local SPOKEN = {
    SAY = "CHAT_SAY_GET", YELL = "CHAT_YELL_GET", WHISPER = "CHAT_WHISPER_GET",
    WHISPER_INFORM = "CHAT_WHISPER_INFORM_GET", BN_WHISPER = "CHAT_BN_WHISPER_GET",
    BN_WHISPER_INFORM = "CHAT_BN_WHISPER_INFORM_GET",
}
local SPOKEN_KEY = { SAY = "SAY", YELL = "YELL", WHISPER = "WHISPER", WHISPER_INFORM = "WHISPER",
    BN_WHISPER = "WHISPER", BN_WHISPER_INFORM = "WHISPER" }

local function Abbr(key)
    local a = S().abbr[key]
    if not a or a == "" then return nil end
    return a
end

-- the [Party] / [1. General] link at the start of a line
local function ShortChannel(msg, kind)
    local s, e, target, label = msg:find("|Hchannel:(.-)|h%[(.-)%]|h")
    if not s then return msg end
    local short
    local num = target:match("^channel:(%d+)") or target:match("^(%d+)$")
    if num then
        local fmt = S().abbr.CHANNEL or "%d"
        short = fmt:find("%%d") and fmt:format(tonumber(num)) or num
    else
        local key = (kind and CHANNEL_KEYS[kind]) or CHANNEL_KEYS[target:upper()]
        short = key and Abbr(key)
    end
    if not short then return msg end
    return msg:sub(1, s - 1) .. "|Hchannel:" .. target .. "|h[" .. short .. "]|h" .. msg:sub(e + 1)
end

-- "Name says: text" -> "[S] Name: text"
local function ShortSpoken(msg, kind)
    local tname = SPOKEN[kind]
    local short = tname and Abbr(SPOKEN_KEY[kind])
    local tpl = tname and _G[tname]
    if not (short and type(tpl) == "string") then return msg end
    local before, after = tpl:match("^(.-)%%s(.*)$")
    if not before then return msg end
    -- the name link
    local ls = msg:find("|H[Bb]?[Nn]?player", 1) or msg:find("|HBNplayer", 1, true)
    if not ls then return msg end
    local le = msg:find("|h", msg:find("|h", ls + 2, true) + 2, true)
    if not le then return msg end
    le = le + 1
    local head = msg:sub(1, ls - 1)
    local rest = msg:sub(le + 1)
    -- drop "says" after the name: " says: " -> ": "
    if after ~= "" and rest:sub(1, #after) == after then
        local colon = after:match("(:%s*)$") or ": "
        rest = colon .. rest:sub(#after + 1)
    end
    -- "To " before the name stays (whispers you send)
    local pre = ""
    if before ~= "" and head:sub(-#before) == before then
        pre = before
        head = head:sub(1, -#before - 1)
    end
    return head .. "[" .. short .. "] " .. pre .. msg:sub(ls, le) .. rest
end

-- a web address: a word starting with "scheme://" or "www."
local function WrapWord(word, hex)
    local core, tail = word:match("^(.-)([%.,;:!%?%)%]\"']*)$")
    if not core or core == "" then return word end
    if core:match("^%a[%w+.-]*://[^%s]+$") or core:match("^www%.[%w%-_]+%.%a%a+") then
        return hex .. "|HHUFurl:" .. core .. "|h[" .. core .. "]|h|r" .. tail
    end
    return word
end
local function Links(msg)
    if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then return msg end
    local hex = ("|cff%02x%02x%02x"):format(A[1] * 255, A[2] * 255, A[3] * 255)
    -- only outside existing links (|H...|h...|h)
    local out, pos = {}, 1
    while true do
        local s = msg:find("|H", pos, true)
        local seg = msg:sub(pos, s and s - 1 or #msg)
        seg = seg:gsub("[^%s|]+", function(w) return WrapWord(w, hex) end)
        out[#out + 1] = seg
        if not s then break end
        local mid = msg:find("|h", s + 2, true)
        local e = mid and msg:find("|h", mid + 2, true)
        if not e then out[#out + 1] = msg:sub(s) break end
        out[#out + 1] = msg:sub(s, e + 1)
        pos = e + 2
    end
    return table.concat(out)
end
Chat.Links, Chat.ShortChannel, Chat.ShortSpoken = Links, ShortChannel, ShortSpoken

function Chat.Transform(msg, event)
    local s = S()
    if type(msg) ~= "string" or IsSecret(msg) then return msg end
    local kind = type(event) == "string" and not IsSecret(event) and event:match("^CHAT_MSG_(.+)$") or nil
    local out = msg
    if s.abbreviate then
        local ok, r = pcall(ShortChannel, out, kind)
        if ok then out = r end
        if kind and SPOKEN[kind] then
            local ok2, r2 = pcall(ShortSpoken, out, kind)
            if ok2 then out = r2 end
        end
    end
    if s.urls then
        local ok, r = pcall(Links, out)
        if ok then out = r end
    end
    return out
end

---------------------------------------------------------------------------
-- History (per character, per window)
---------------------------------------------------------------------------
local function Store()
    HUFDB.chatHistory = HUFDB.chatHistory or {}
    local k = ns.CharKey()
    HUFDB.chatHistory[k] = HUFDB.chatHistory[k] or {}
    return HUFDB.chatHistory[k]
end

local function Remember(cf, msg, r, g, b)
    local s = S()
    if not s.history or restoring or IsCombatLog(cf) then return end
    if type(msg) ~= "string" or IsSecret(msg) then return end
    local id = cf:GetID()
    if not id or id < 1 or id > (NUM_CHAT_WINDOWS or 10) then return end
    local st = Store()
    local list = st[id]
    if not list then list = {} st[id] = list end
    list[#list + 1] = { msg, tonumber(r) and math.floor(r * 100 + 0.5) / 100 or 1,
        tonumber(g) and math.floor(g * 100 + 0.5) / 100 or 1, tonumber(b) and math.floor(b * 100 + 0.5) / 100 or 1 }
    local over = #list - s.historyLines
    if over > 50 then
        local keep = {}
        for i = over + 1, #list do keep[#keep + 1] = list[i] end
        st[id] = keep
    end
end

function Chat.Restore()
    local s = S()
    if not s.history or Chat.restored then return end
    Chat.restored = true
    local st = Store()
    restoring = true
    for id, list in pairs(st) do
        local cf = _G["ChatFrame" .. id]
        if cf and #list > 0 then
            local from = math.max(1, #list - s.historyLines + 1)
            for i = from, #list do
                local l = list[i]
                pcall(cf.AddMessage, cf, l[1], l[2], l[3], l[4])
            end
            pcall(cf.AddMessage, cf, "|cff666666-- earlier chat above --|r", 0.4, 0.4, 0.4)
        end
    end
    restoring = false
end

function Chat.ClearHistory()
    if HUFDB.chatHistory then HUFDB.chatHistory[ns.CharKey()] = nil end
end

---------------------------------------------------------------------------
-- The post-hook
---------------------------------------------------------------------------
local function OnAddMessage(cf, msg, r, g, b, _, _, _, event)
    if not (HUFDB and ns.db) then return end
    local s = S()
    if not s.enabled or IsSecret(msg) or type(msg) ~= "string" then return end
    if restoring then return end
    local shown = msg
    if not IsCombatLog(cf) and (s.abbreviate or s.urls) then
        shown = Chat.Transform(msg, event)
        if shown ~= msg then
            -- the line the window just stored: rewrite it and redraw
            local hb = cf.historyBuffer
            local e = hb and hb.GetEntryAtIndex and hb:GetEntryAtIndex(1)
            if e and type(e.message) == "string" and not IsSecret(e.message) and e.message == msg then
                e.message = shown
                if cf.MarkDisplayDirty then pcall(cf.MarkDisplayDirty, cf)
                elseif cf.RefreshDisplay then pcall(cf.RefreshDisplay, cf) end
            else
                shown = msg
            end
        end
    end
    Remember(cf, shown, r, g, b)
end

local function OnHyperlinkEnter(cf, link)
    if not S().linkTooltips or IsSecret(link) or type(link) ~= "string" then return end
    local t = link:match("^([^:]+)")
    local TYPES = { item = true, spell = true, quest = true, achievement = true, enchant = true, talent = true,
        currency = true, unit = true, trade = true, mount = true, battlepet = true, instancelock = true }
    if not TYPES[t] then return end
    GameTooltip:SetOwner(cf, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
    Chat.tipShown = true
end
local function OnHyperlinkLeave()
    if Chat.tipShown then Chat.tipShown = nil GameTooltip:Hide() end
end

local function Hook(cf)
    if hooked[cf] then return end
    hooked[cf] = true
    hooksecurefunc(cf, "AddMessage", OnAddMessage)
    cf:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
    cf:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
end

---------------------------------------------------------------------------
-- URL copy box (clicking a HUFurl link)
---------------------------------------------------------------------------
local urlBox
local function ShowURL(url)
    if not urlBox then
        local f = CreateFrame("Frame", "HUF_ChatURL", UIParent)
        f:SetSize(380, 56)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        ns.UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(f, A[1], A[2], A[3], 0.9)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOP", 0, -6)
        t:SetText("Ctrl+C to copy, Esc to close")
        local e = CreateFrame("EditBox", nil, f)
        e:SetFontObject("GameFontHighlight")
        e:SetPoint("BOTTOMLEFT", 10, 8)
        e:SetPoint("BOTTOMRIGHT", -10, 8)
        e:SetHeight(22)
        e:SetAutoFocus(true)
        ns.UI.Fill(e, 0.09, 0.09, 0.10, 1)
        e:SetTextInsets(6, 6, 0, 0)
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        e:SetScript("OnEditFocusLost", function() f:Hide() end)
        e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.url) self:HighlightText() end end)
        f.edit = e
        urlBox = f
    end
    urlBox.url = url
    urlBox.edit:SetText(url)
    urlBox:Show()
    urlBox.edit:SetFocus()
    urlBox.edit:HighlightText()
end
hooksecurefunc("SetItemRef", function(link)
    if type(link) ~= "string" or IsSecret(link) then return end
    local url = link:match("^HUFurl:(.+)$")
    if url then ShowURL(url) end
end)

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------
local function Plain(text)
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|n", "\n")
    text = text:gsub("||", "|")
    return text
end
Chat.Plain = Plain

local copyWin
function Chat.Copy()
    local cf = SelectedWindow()
    local lines = {}
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and type(text) == "string" and not IsSecret(text) then
            local ok2, p = pcall(Plain, text)
            if ok2 then lines[#lines + 1] = p end
        end
    end
    if not copyWin then
        local f = CreateFrame("Frame", "HUF_ChatCopy", UIParent)
        f:SetSize(620, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        ns.UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(f, A[1], A[2], A[3], 0.9)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 10, -8)
        t:SetText("Chat - Ctrl+A, Ctrl+C to copy")
        local close = ns.UI.Button(f, 24, "x", function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -4)
        f.area = ns.UI.TextArea(f, 600, 376)
        f.area:SetPoint("BOTTOM", 0, 8)
        if UISpecialFrames then table.insert(UISpecialFrames, "HUF_ChatCopy") end
        copyWin = f
    end
    local e = copyWin.area.edit or copyWin.area.editBox or copyWin.area.e
    local text = #lines > 0 and table.concat(lines, "\n") or "(no chat lines that can be copied)"
    if e then
        e:SetText(text)
        e:SetFocus()
        e:HighlightText()
        e:SetCursorPosition(#text)
    elseif copyWin.area.SetText then
        copyWin.area:SetText(text)
    end
    copyWin:Show()
end

---------------------------------------------------------------------------
-- Buttons beside the chat
---------------------------------------------------------------------------
local bar
local BUTTONS = {
    { key = "copy", icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", tip = "Copy chat", click = function() Chat.Copy() end },
    { key = "guild", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", tip = "Guild", click = function()
        if ToggleGuildFrame then ToggleGuildFrame() elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame() end end },
    { key = "social", icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", tip = "Friends", click = function()
        if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    -- the game's own buttons, moved here: an invisible copy of the real one
    -- lies over HUF's icon and takes the clicks (EllesmereUI's way: the
    -- game's menu opens where the button is)
    { key = "channels", atlas = "chatframe-button-icon-voicechat", icon = "Interface\\ChatFrame\\UI-ChatIcon-ArmoryChat",
      blizzard = "ChatFrameChannelButton", tip = "Chat channels" },
    { key = "chatmenu", icon = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", blizzard = "ChatFrameMenuButton",
      tip = "Language, emotes, chat type" },
}

local function GuildOnline()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, total, online = pcall(GetNumGuildMembers)
    if not ok then return 0, 0 end
    return online or 0, total or 0
end

local function GuildTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    local online, total = GuildOnline()
    local name = GetGuildInfo and GetGuildInfo("player")
    GameTooltip:SetText(name or "Guild")
    GameTooltip:AddLine(("%d of %d online"):format(online or 0, total or 0), 0.8, 0.8, 0.8)
    local shown = 0
    for i = 1, total or 0 do
        local ok, full, _, _, level, _, zone, _, _, isOnline, _, classFile = pcall(GetGuildRosterInfo, i)
        if ok and isOnline and type(full) == "string" then
            shown = shown + 1
            if shown > 25 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
            local n = full:gsub("%-.*$", "")
            n = ns.NameFromString and ns.NameFromString(n) or n
            local c = classFile and ns.ClassColor(classFile)
            GameTooltip:AddDoubleLine(("%s  |cff999999%s|r"):format(n, tostring(level or "")), zone or "",
                c and c.r or 1, c and c.g or 1, c and c.b or 1, 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:AddLine("Click: guild window", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function BuildBar()
    if bar then return end
    bar = CreateFrame("Frame", "HUF_ChatButtons", UIParent)
    bar:SetFrameStrata("LOW")
    bar.buttons = {}
    for _, info in ipairs(BUTTONS) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(22, 22)
        ns.UI.Fill(b, 0.05, 0.05, 0.06, 0.85)
        b.border = ns.UI.Border(b, 0.2, 0.2, 0.22, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        if not (info.atlas and b.icon.SetAtlas and pcall(b.icon.SetAtlas, b.icon, info.atlas)) then
            b.icon:SetTexture(info.icon)
        end
        if info.key == "guild" then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b:RegisterForClicks("LeftButtonUp")
        if info.click then b:SetScript("OnClick", info.click) end
        b.blizzard = info.blizzard
        b:SetScript("OnEnter", function(self)
            self.border:SetColor(A[1], A[2], A[3], 1)
            if info.key == "guild" then GuildTooltip(self) return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(info.tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.border:SetColor(0.2, 0.2, 0.22, 1) GameTooltip:Hide() end)
        if info.key == "guild" then
            b.count = b:CreateFontString(nil, "OVERLAY")
            ns.ApplyFont(b.count, "GLOBAL", 10, "OUTLINE")
            b.count:SetPoint("BOTTOMRIGHT", 1, -1)
        end
        b.key = info.key
        bar.buttons[#bar.buttons + 1] = b
    end
end

function Chat.UpdateGuildCount()
    if not bar then return end
    for _, b in ipairs(bar.buttons) do
        if b.key == "guild" then
            local online = GuildOnline()
            b.count:SetText(online and tostring(online) or "")
        end
    end
end

-- the game's button over HUF's slot: invisible, mouse on, above the slot
local seated = {}
local function Seat(b, on)
    local real = b.blizzard and _G[b.blizzard]
    if not real then return false end
    if not seated[real] then
        seated[real] = b
        real:HookScript("OnEnter", function()
            local slot = seated[real]
            if slot and slot:IsShown() then slot.border:SetColor(A[1], A[2], A[3], 1) Chat.Wake() end
        end)
        real:HookScript("OnLeave", function()
            local slot = seated[real]
            if slot then slot.border:SetColor(0.2, 0.2, 0.22, 1) end
        end)
    end
    real:ClearAllPoints()
    if on then
        real:SetAllPoints(b)
        if real.SetFixedFrameStrata then real:SetFixedFrameStrata(false) end
        real:SetFrameStrata(bar:GetFrameStrata())
        if real.SetFixedFrameStrata then real:SetFixedFrameStrata(true) end
        if real.SetFixedFrameLevel then real:SetFixedFrameLevel(false) end
        real:SetFrameLevel(b:GetFrameLevel() + 3)
        if real.SetFixedFrameLevel then real:SetFixedFrameLevel(true) end
        real:SetAlpha(0)
        real:EnableMouse(true)
    else
        -- not wanted: hidden away (its place belongs to the game's chat layout)
        real:SetAllPoints(b)
        real:SetAlpha(0)
        real:EnableMouse(false)
    end
    return true
end

local function LayoutBar()
    local s = S()
    BuildBar()
    local cf = ChatFrame1
    if not (s.enabled and cf) then bar:Hide() return end
    local y, n = 0, 0
    for _, b in ipairs(bar.buttons) do
        local on = s.buttons[b.key]
        if b.key == "guild" and not (IsInGuild and IsInGuild()) then on = false end
        if b.blizzard and not _G[b.blizzard] then on = false end
        b:ClearAllPoints()
        if on then
            b:SetPoint("TOP", bar, "TOP", 0, -y)
            y = y + 24
            n = n + 1
            b:Show()
        else
            b:Hide()
        end
    end
    bar:SetSize(22, math.max(1, y - 2))
    bar:ClearAllPoints()
    if s.buttonSide == "LEFT" then
        bar:SetPoint("TOPRIGHT", cf, "TOPLEFT", -6 + (s.buttonX or 0), (s.buttonY or 0))
    else
        bar:SetPoint("TOPLEFT", cf, "TOPRIGHT", 6 + (s.buttonX or 0), (s.buttonY or 0))
    end
    bar:SetShown(n > 0)
    for _, b in ipairs(bar.buttons) do
        if b.blizzard then Seat(b, b:IsShown() and n > 0) end
    end
    Chat.UpdateGuildCount()
    Chat.Wake()
end

---------------------------------------------------------------------------
-- Fading the buttons: down to fadeAlpha after fadeDelay seconds, full again
-- while the mouse is over the chat or the buttons
---------------------------------------------------------------------------
local idle = 0
function Chat.Wake()
    idle = 0
    if bar then bar:SetAlpha(1) end
end

local function MouseOverChat()
    if bar and bar:IsShown() and bar:IsMouseOver(4, -4, -4, 4) then return true end
    local cf = SelectedWindow()
    for _, f in ipairs({ cf, ChatFrame1 }) do
        -- the window with its tabs above and the input line below
        if f and f:IsVisible() and f:IsMouseOver(32, -36, -8, 8) then return true end
    end
    for real in pairs(seated) do
        if real:IsVisible() and real:IsMouseOver() then return true end
    end
    return false
end

C_Timer.NewTicker(0.2, function()
    if not (bar and HUFDB and ns.db) then return end
    local s = S()
    if not (s.enabled and s.fade) then
        if bar:GetAlpha() ~= 1 then bar:SetAlpha(1) end
        return
    end
    if MouseOverChat() then
        idle = 0
        if bar:GetAlpha() ~= 1 then bar:SetAlpha(1) end
        return
    end
    idle = idle + 0.2
    if idle >= s.fadeDelay then
        if math.abs(bar:GetAlpha() - s.fadeAlpha) > 0.01 then bar:SetAlpha(s.fadeAlpha) end
    end
end)

---------------------------------------------------------------------------
-- Input line above or below the chat (plain anchors; never hooks on the box)
---------------------------------------------------------------------------
local placedInput = {}
local function PlaceInput(cf)
    local s = S()
    local name = cf.GetName and cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if not eb then return end
    local want = s.enabled and s.inputPos or "BELOW"
    if want == "BELOW" and not placedInput[eb] then return end     -- the game's own place
    eb:ClearAllPoints()
    local off = s.inputOffset or 0
    if want == "ABOVE" then
        eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 28 + off)
        eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, 28 + off)
    else
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -2 - off)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -2 - off)
    end
    placedInput[eb] = true
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local function ApplyLook(cf)
    local s = S()
    local path = ns.FontPath(s.font == "GLOBAL" and ns.db.global.font or s.font)
    local outline = s.outline == "GLOBAL" and ns.db.global.outline or s.outline
    if outline == "NONE" then outline = "" end
    if path then
        pcall(cf.SetFont, cf, path, s.fontSize, outline)
        local name = cf.GetName and cf:GetName()
        local eb = name and _G[name .. "EditBox"]
        if eb then
            pcall(eb.SetFont, eb, path, s.fontSize, outline)
            local hdr = eb.header or _G[name .. "EditBoxHeader"]
            if hdr then pcall(hdr.SetFont, hdr, path, s.fontSize, outline) end
        end
    end
end

local function ApplyBackground(cf)
    local s = S()
    if FCF_SetWindowColor then pcall(FCF_SetWindowColor, cf, s.bgColor.r, s.bgColor.g, s.bgColor.b) end
    if FCF_SetWindowAlpha then pcall(FCF_SetWindowAlpha, cf, s.bgAlpha) end
end

-- the game's class colour per chat type
local CLASS_TYPES = { "SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }
function Chat.ApplyClassColors(on)
    local fn = SetChatColorNameByClass or (C_ChatInfo and C_ChatInfo.SetChatColorNameByClass)
    if not fn then return end
    for _, t in ipairs(CLASS_TYPES) do pcall(fn, t, on) end
    for i = 1, 20 do pcall(fn, "CHANNEL" .. i, on) end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
function Chat.Apply(full)
    if not (HUFDB and ns.db) then return end
    local s = S()
    for _, cf in ipairs(Windows()) do
        Hook(cf)
        if s.enabled then
            ApplyLook(cf)
            if full then ApplyBackground(cf) end
        end
        pcall(PlaceInput, cf)
    end
    LayoutBar()
end

function Chat.Report(add)
    local s = S()
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    local st = HUFDB.chatHistory and HUFDB.chatHistory[ns.CharKey()] or {}
    local lines = 0
    for _, l in pairs(st) do lines = lines + #l end
    add(("chat: enabled=%s windows=%d abbreviate=%s urls=%s history=%s (%d stored) classColors=%s buttons=%s"):format(
        tostring(s.enabled), n, tostring(s.abbreviate), tostring(s.urls), tostring(s.history), lines,
        tostring(s.classColors), tostring(bar and bar:IsShown())))
end

ns.OnLogin(function()
    local s = S()
    Chat.Apply(true)
    if s.enabled and s.classColors then Chat.ApplyClassColors(true) end
    if s.enabled then Chat.Restore() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end)
ns.OnRefresh(function() if HUFDB and ns.db then Chat.Apply(true) end end)
ns.On("UPDATE_CHAT_WINDOWS", function() if HUFDB and ns.db then Chat.Apply(false) end end)
ns.On("UPDATE_FLOATING_CHAT_WINDOWS", function() if HUFDB and ns.db then Chat.Apply(false) end end)
ns.On("GUILD_ROSTER_UPDATE", function() Chat.UpdateGuildCount() end)
ns.On("PLAYER_GUILD_UPDATE", function() if HUFDB and ns.db then LayoutBar() end end)
-- whisper windows open later: hook them as they appear
C_Timer.NewTicker(5, function()
    if not (HUFDB and ns.db) then return end
    for _, cf in ipairs(Windows()) do
        if not hooked[cf] then
            Hook(cf)
            if S().enabled then ApplyLook(cf) end
            pcall(PlaceInput, cf)
        end
    end
    if IsInGuild and IsInGuild() and not Chat.rosterAsked then
        Chat.rosterAsked = true
        C_Timer.After(60, function() Chat.rosterAsked = nil end)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    end
end)
