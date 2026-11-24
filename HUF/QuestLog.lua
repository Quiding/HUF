-- HUF: the classic quest log (World of Warcraft 1.12 layout and art) instead of
-- the game's combined map + quest window. Off by default.
--
-- The window is drawn from the game's own classic quest log art, which Forever
-- still ships (Interface\QuestFrame\UI-QuestLog-*, the book icon, +/- buttons,
-- title highlight, reward name frames), laid out like the 1.12 QuestLogFrame:
-- 384 x 512, six quest rows over the quest's text, Abandon / Share / Exit.
--
-- Own categories: quests can be put into categories of your own (right-click a
-- quest); they show above the zones. Other addons (MMT's quest tracker) read
-- them through HUF.QuestLog (API below).
--
-- While on, the quest log key (ToggleQuestLog / OpenQuestLog) and a click on a
-- quest in the tracker (QuestMapFrame_OpenToQuestDetails, MMT's
-- QuestLog_OpenToQuest) open it; the map key still opens the map, and a quest
-- clicked on the open map stays in the map. Off again: back after /reload.
--
-- API for other addons (HUF.QuestLog, API 1):
--   QL.API                               -> 1
--   QL.IsEnabled()                       -> HUF's quest log is on
--   QL.GetCategories()                   -> { "name", ... } in their order
--   QL.GetCategory(questID)              -> category name or nil (= its zone)
--   QL.SetCategory(questID, name|nil)    -> put a quest into a category (nil: back to its zone)
--   QL.AddCategory(name), QL.RemoveCategory(name), QL.RenameCategory(old, new), QL.MoveCategory(name, delta)
--   QL.GetSections()                     -> { { title, custom = bool, quests = { questID, ... } }, ... }
--                                           as the log shows them (own categories first, then zones)
--   QL.Listen(fn)                        -> fn("CATEGORIES_CHANGED") after any category change
--   QL.Show(questID?), QL.Toggle()

local _, ns = ...
local QL = {}
ns.QuestLog = QL
QL.API = 1

local FRAME_W, FRAME_H = 384, 512
local ROWS, ROW_H = 6, 16
local LIST_X, LIST_Y = 19, -75
local DETAIL_Y, DETAIL_W, DETAIL_H = -176, 300, 261
local INK, INK_DONE = { 0.10, 0.07, 0.03 }, { 0.38, 0.33, 0.27 }   -- text on the parchment

local function S() return ns.db.questLog end
local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end
local CQ = C_QuestLog or {}

local frame
local selected            -- questID
local collapsed = {}      -- section title -> true (this session)
local entries = {}        -- the list as shown
local sections = {}       -- QL.GetSections()

---------------------------------------------------------------------------
-- Quest data
---------------------------------------------------------------------------
local function Info(i)
    if CQ.GetInfo then return Safe(CQ.GetInfo, i) end
    if GetQuestLogTitle then
        local title, level, suggestedGroup, isHeader, _, isComplete, frequency, questID = GetQuestLogTitle(i)
        if not title then return nil end
        return { title = title, level = level, suggestedGroup = suggestedGroup, isHeader = isHeader,
            questID = questID, questLogIndex = i, frequency = frequency, hufComplete = isComplete }
    end
end
local function NumEntries()
    if CQ.GetNumQuestLogEntries then return Safe(CQ.GetNumQuestLogEntries) end
    return Safe(GetNumQuestLogEntries)
end
local function IsComplete(q)
    if CQ.IsComplete then return Safe(CQ.IsComplete, q.questID) end
    return q.hufComplete == 1 or q.hufComplete == true
end
local function IsFailed(q)
    if CQ.IsFailed then return Safe(CQ.IsFailed, q.questID) end
    return q.hufComplete == -1
end
-- elite, as the game's own quest list marks it with "+": the quest's tag info
-- (isElite, or an "Elite" tag), cached per quest
local eliteCache = {}
local function IsElite(id)
    if not id then return false end
    local c = eliteCache[id]
    if c ~= nil then return c end
    local elite = false
    if CQ.GetQuestTagInfo then
        local info = Safe(CQ.GetQuestTagInfo, id)
        if type(info) == "table" then
            elite = info.isElite == true
                or (_G.ELITE and info.tagName == _G.ELITE)
                or (type(info.tagName) == "string" and info.tagName:lower() == "elite")
        end
    elseif GetQuestTagInfo then
        local _, tagName = Safe(GetQuestTagInfo, id)
        elite = (_G.ELITE and tagName == _G.ELITE) or (type(tagName) == "string" and tagName:lower() == "elite")
    end
    eliteCache[id] = elite and true or false
    return eliteCache[id]
end
QL.IsElite = IsElite

local function IndexOf(id)
    if CQ.GetLogIndexForQuestID then return Safe(CQ.GetLogIndexForQuestID, id) end
end
local function IsTracked(id)
    if CQ.GetQuestWatchType then return Safe(CQ.GetQuestWatchType, id) ~= nil end
    if IsQuestWatched then return Safe(IsQuestWatched, IndexOf(id)) end
    return false
end
local function Select(id)
    if CQ.SetSelectedQuest then Safe(CQ.SetSelectedQuest, id)
    elseif SelectQuestLogEntry then Safe(SelectQuestLogEntry, IndexOf(id)) end
end
local function MaxQuests()
    return (CQ.GetMaxNumQuestsCanAccept and Safe(CQ.GetMaxNumQuestsCanAccept)) or MAX_QUESTS or 25
end
local function TitleOf(id)
    return CQ.GetTitleForQuestID and Safe(CQ.GetTitleForQuestID, id)
end

---------------------------------------------------------------------------
-- Own categories (profile: questLog.categories = { list = {names}, quests = {[questID] = name} })
---------------------------------------------------------------------------
local function Cat()
    local c = S().categories
    if type(c) ~= "table" then c = {} S().categories = c end
    c.list = c.list or {}
    c.quests = c.quests or {}
    return c
end
local listeners = {}
local function Changed()
    if frame and frame:IsShown() then QL.Refresh() end
    for _, fn in ipairs(listeners) do pcall(fn, "CATEGORIES_CHANGED") end
end
function QL.Listen(fn) if type(fn) == "function" then listeners[#listeners + 1] = fn end end
function QL.IsEnabled() return ns.db and S().enabled or false end
function QL.GetCategories()
    local t = {}
    for i, n in ipairs(Cat().list) do t[i] = n end
    return t
end
local function HasCat(name)
    for _, n in ipairs(Cat().list) do if n == name then return true end end
    return false
end
function QL.GetCategory(id)
    local n = Cat().quests[id]
    return (n and HasCat(n)) and n or nil
end
function QL.AddCategory(name)
    name = type(name) == "string" and ns.Trim(name) or ""
    if name == "" or HasCat(name) then return false end
    table.insert(Cat().list, name)
    Changed()
    return true
end
function QL.RemoveCategory(name)
    local c = Cat()
    for i, n in ipairs(c.list) do
        if n == name then
            table.remove(c.list, i)
            for id, cn in pairs(c.quests) do if cn == name then c.quests[id] = nil end end
            Changed()
            return true
        end
    end
    return false
end
function QL.RenameCategory(old, new)
    new = type(new) == "string" and ns.Trim(new) or ""
    if new == "" or HasCat(new) then return false end
    local c = Cat()
    for i, n in ipairs(c.list) do
        if n == old then
            c.list[i] = new
            for id, cn in pairs(c.quests) do if cn == old then c.quests[id] = new end end
            if collapsed[old] then collapsed[new], collapsed[old] = true, nil end
            Changed()
            return true
        end
    end
    return false
end
function QL.MoveCategory(name, delta)
    local l = Cat().list
    for i, n in ipairs(l) do
        if n == name then
            local j = math.max(1, math.min(#l, i + delta))
            if j ~= i then table.remove(l, i) table.insert(l, j, name) Changed() end
            return true
        end
    end
    return false
end
function QL.SetCategory(id, name)
    if name ~= nil and not HasCat(name) then return false end
    Cat().quests[id] = name
    Changed()
    return true
end

---------------------------------------------------------------------------
-- The list: own categories first, then the game's zone headers
---------------------------------------------------------------------------
local function Collect()
    wipe(entries)
    wipe(sections)
    local own, zones, order = {}, {}, {}
    for _, n in ipairs(Cat().list) do own[n] = {} end
    local zone = "?"
    local quests = 0
    for i = 1, NumEntries() or 0 do
        local q = Info(i)
        if q and q.isHeader then
            zone = q.title or "?"
        elseif q and q.questID and not q.isHidden and not q.isTask and not q.isBounty then
            quests = quests + 1
            local e = {
                questID = q.questID, index = q.questLogIndex or i, title = q.title or "?", level = q.level,
                group = q.suggestedGroup, daily = Enum and Enum.QuestFrequency and q.frequency == Enum.QuestFrequency.Daily,
                elite = IsElite(q.questID),
                complete = IsComplete(q), failed = IsFailed(q), tracked = IsTracked(q.questID),
            }
            local c = QL.GetCategory(q.questID)
            if c then
                table.insert(own[c], e)
            else
                if not zones[zone] then zones[zone] = {} order[#order + 1] = zone end
                table.insert(zones[zone], e)
            end
        end
    end
    QL.count = quests
    local function Add(title, list, custom)
        local sec = { title = title, custom = custom, quests = {} }
        for _, e in ipairs(list) do sec.quests[#sec.quests + 1] = e.questID end
        sections[#sections + 1] = sec
        entries[#entries + 1] = { header = true, title = title, custom = custom, collapsed = collapsed[title], n = #list }
        if not collapsed[title] then
            for _, e in ipairs(list) do entries[#entries + 1] = e end
        end
    end
    for _, n in ipairs(Cat().list) do Add(n, own[n], true) end
    for _, z in ipairs(order) do Add(z, zones[z], false) end
    return entries
end

function QL.GetSections()
    Collect()
    local t = {}
    for i, s in ipairs(sections) do
        local q = {}
        for j, id in ipairs(s.quests) do q[j] = id end
        t[i] = { title = s.title, custom = s.custom, quests = q }
    end
    return t
end

---------------------------------------------------------------------------
-- Fonts: the game's quest fonts (classic) or a HUF font
---------------------------------------------------------------------------
-- text size: quest text = fontSize (13 = the game's QuestFont), title + 5
-- (QuestTitleFont 18), list - 1 (GameFontNormal 12), small - 2
local function Size(kind)
    local base = S().fontSize or 13
    return base + ((kind == "title" and 5) or (kind == "list" and -1) or (kind == "small" and -2) or 0)
end
local function Font(fs, kind)
    local s = S()
    if s.font == "CLASSIC" then
        local obj = (kind == "title" and (_G.QuestTitleFont or _G.GameFontNormalLarge))
            or (kind == "list" and _G.GameFontNormal)
            or (kind == "small" and _G.GameFontHighlightSmall)
            or _G.QuestFont or _G.GameFontHighlight
        if obj then
            fs:SetFontObject(obj)
            -- the game's font at the chosen size
            local path, _, flags = fs:GetFont()
            if path then fs:SetFont(path, Size(kind), flags or "") end
        end
    else
        ns.ApplyFont(fs, s.font, Size(kind), s.outline)
    end
end
-- list rows grow with the text
local function RowH() return math.max(ROW_H, Size("list") + 4) end

local function LevelColor(level)
    local c = ns.LevelColor and ns.LevelColor(level)
    return c or { r = 1, g = 0.82, b = 0 }
end

---------------------------------------------------------------------------
-- Name prompt (a new category, a new name)
---------------------------------------------------------------------------
local prompt
local function Prompt(text, value, onOk)
    if not prompt then
        prompt = CreateFrame("Frame", "HUF_QuestLogPrompt", UIParent)
        prompt:SetSize(280, 92)
        prompt:SetFrameStrata("DIALOG")
        prompt:SetPoint("CENTER", 0, 120)
        prompt:EnableMouse(true)
        ns.UI.Fill(prompt, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(prompt, ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
        prompt.text = ns.UI.Label(prompt, "")
        prompt.text:SetPoint("TOP", 0, -10)
        prompt.box = ns.UI.EditBox(prompt, 240, "", function(t) prompt.ok:Click() end)
        prompt.box:SetPoint("TOP", 0, -30)
        prompt.ok = ns.UI.Button(prompt, 90, "OK", function()
            local v = prompt.box:GetText()
            prompt:Hide()
            if prompt.onOk then prompt.onOk(v) end
        end)
        prompt.ok:SetPoint("BOTTOMRIGHT", -40, 10)
        local cancel = ns.UI.Button(prompt, 90, "Cancel", function() prompt:Hide() end)
        cancel:SetPoint("BOTTOMLEFT", 40, 10)
        if UISpecialFrames then table.insert(UISpecialFrames, "HUF_QuestLogPrompt") end
    end
    prompt.text:SetText(text)
    prompt.box:SetText(value or "")
    prompt.onOk = onOk
    prompt:Show()
    prompt.box:SetFocus()
    prompt.box:HighlightText()
end

-- right-click menus
local function QuestMenu(row, e)
    local items, actions = {}, {}
    local cur = QL.GetCategory(e.questID)
    for _, n in ipairs(Cat().list) do
        items[#items + 1] = { value = "cat:" .. n, text = (n == cur and "> " or "Move to ") .. n }
    end
    items[#items + 1] = { value = "new", text = "New category..." }
    if cur then items[#items + 1] = { value = "zone", text = "Back to its zone" } end
    items[#items + 1] = { value = "track", text = e.tracked and "Untrack" or "Track" }
    if ns.QuestLinks then items[#items + 1] = { value = "link", text = "Link in chat" } end
    ns.UI.OpenList(row, items, nil, function(v)
        if v == "new" then
            Prompt("Name of the new category:", "", function(name)
                if QL.AddCategory(name) then QL.SetCategory(e.questID, ns.Trim(name)) end
            end)
        elseif v == "zone" then QL.SetCategory(e.questID, nil)
        elseif v == "track" then QL.ToggleTrack(e.questID) QL.Refresh()
        elseif v == "link" then ns.QuestLinks.Insert(e.questID, e.title, e.level)
        elseif type(v) == "string" and v:sub(1, 4) == "cat:" then QL.SetCategory(e.questID, v:sub(5)) end
    end)
end
local function CategoryMenu(row, e)
    ns.UI.OpenList(row, {
        { value = "rename", text = "Rename..." }, { value = "up", text = "Move up" },
        { value = "down", text = "Move down" }, { value = "delete", text = "Delete (quests go back to their zones)" },
    }, nil, function(v)
        if v == "rename" then Prompt("New name for \"" .. e.title .. "\":", e.title, function(n) QL.RenameCategory(e.title, n) end)
        elseif v == "up" then QL.MoveCategory(e.title, -1)
        elseif v == "down" then QL.MoveCategory(e.title, 1)
        elseif v == "delete" then QL.RemoveCategory(e.title) end
    end)
end

---------------------------------------------------------------------------
-- The quest list (classic title buttons)
---------------------------------------------------------------------------
local rows = {}
local function NewRow(i)
    local r = CreateFrame("Button", nil, frame.listChild)
    r:SetSize(frame.listW, RowH())
    r.expand = r:CreateTexture(nil, "ARTWORK")
    r.expand:SetSize(16, 16)
    r.expand:SetPoint("LEFT", 0, 0)
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.check:SetSize(16, 16)
    r.check:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "OVERLAY")
    Font(r.text, "list")
    r.text:SetPoint("LEFT", 20, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.tag = r:CreateFontString(nil, "OVERLAY")
    Font(r.tag, "list")
    r.tag:SetPoint("RIGHT", -2, 0)
    r.text:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    r.hl:SetBlendMode("ADD")
    r.hl:SetAllPoints()
    r.hl:Hide()
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self) if self.entry and not self.entry.header then self.hl:Show() end end)
    r:SetScript("OnLeave", function(self) if not (self.entry and self.entry.questID == selected) then self.hl:Hide() end end)
    r:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        if e.header then
            if button == "RightButton" and e.custom then CategoryMenu(self, e) return end
            collapsed[e.title] = not collapsed[e.title] or nil
        elseif button == "RightButton" then
            QuestMenu(self, e)
            return
        elseif IsShiftKeyDown() and ns.QuestLinks and ns.QuestLinks.Typing() then
            ns.QuestLinks.Insert(e.questID, e.title, e.level)   -- typing in chat: link it
            return
        elseif IsShiftKeyDown() then
            QL.ToggleTrack(e.questID)
        else
            selected = e.questID
        end
        QL.Refresh()
    end)
    rows[i] = r
    return r
end

local function DrawList()
    for i = 1, math.max(#entries, #rows) do
        local e = entries[i]
        local r = rows[i] or (e and NewRow(i))
        if r then
            r.entry = e
            if e then
                r:ClearAllPoints()
                r:SetHeight(RowH())
                r:SetPoint("TOPLEFT", frame.listChild, "TOPLEFT", 0, -(i - 1) * RowH())
                Font(r.text, "list")
                Font(r.tag, "list")
                if e.header then
                    r.expand:SetTexture(e.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                    r.expand:Show()
                    r.check:Hide()
                    r.text:SetText(e.title)
                    if e.custom then r.text:SetTextColor(0.55, 0.85, 1) else r.text:SetTextColor(1, 0.82, 0) end
                    r.tag:SetText(e.collapsed and ("(" .. e.n .. ")") or "")
                    r.tag:SetTextColor(0.6, 0.6, 0.6)
                    r.hl:Hide()
                else
                    local c = LevelColor(e.level)
                    r.expand:Hide()
                    r.check:SetShown(e.tracked)
                    local lvl = (S().levels and e.level and e.level > 0)
                        and ("[" .. e.level .. ((e.elite or (e.group and e.group > 1)) and "+" or "") .. "] ") or ""
                    r.text:SetText(lvl .. e.title)
                    r.text:SetTextColor(c.r, c.g, c.b)
                    local tag = e.failed and "(Failed)" or (e.complete and "(Complete)" or (e.daily and "(Daily)" or
                        ((e.group and e.group > 1) and ("(" .. e.group .. ")") or "")))
                    r.tag:SetText(tag)
                    r.tag:SetTextColor(c.r, c.g, c.b)
                    r.hl:SetVertexColor(c.r, c.g, c.b)
                    r.hl:SetShown(e.questID == selected)
                end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    frame.listChild:SetHeight(math.max(1, #entries * RowH()))
    frame.count:SetText(("%d/%d"):format(QL.count or 0, MaxQuests()))
    local all = true
    for _, e in ipairs(entries) do if e.header and not e.collapsed then all = false break end end
    frame.allIcon:SetTexture(all and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
end

---------------------------------------------------------------------------
-- The quest's text (on the parchment)
---------------------------------------------------------------------------
local texts, items = {}, {}
local function Text(i)
    local t = texts[i]
    if not t then
        t = frame.detailChild:CreateFontString(nil, "OVERLAY")
        Font(t)
        t:SetJustifyH("LEFT")
        t:SetJustifyV("TOP")
        t:SetWordWrap(true)
        texts[i] = t
    end
    return t
end
-- thin edges round a region (four textures on `owner`, around `anchor`)
local function Edges(owner, anchor, layer, size)
    local e = {}
    for k, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", "H" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "H" },
        { "TOPLEFT", "BOTTOMLEFT", "V" }, { "TOPRIGHT", "BOTTOMRIGHT", "V" } }) do
        local t = owner:CreateTexture(nil, layer or "BORDER")
        t:SetPoint(pts[1], anchor, pts[1], 0, 0)
        t:SetPoint(pts[2], anchor, pts[2], 0, 0)
        if pts[3] == "H" then t:SetHeight(size or 1) else t:SetWidth(size or 1) end
        e[k] = t      -- 1 top, 2 bottom, 3 left, 4 right
    end
    e.Color = function(_, r, g, b, a) for k = 1, 4 do e[k]:SetColorTexture(r, g, b, a or 1) end end
    return e
end

-- the XP icon: the game's XP_Icon when this client has it, else a purple "XP" square
local XP_ICON
local function XPIcon()
    if XP_ICON == nil then
        local id = GetFileIDFromPath and Safe(GetFileIDFromPath, "Interface\\Icons\\XP_Icon")
        XP_ICON = id and "Interface\\Icons\\XP_Icon" or false
    end
    return XP_ICON
end

-- a reward: icon with a quality edge and a dark sunken box for its name (the
-- game's modern reward look); also used for XP and money
local REWARD_H, ICON = 38, 34
local function Item(i)
    local b = items[i]
    if not b then
        b = CreateFrame("Button", nil, frame.detailChild)
        b:SetSize(150, REWARD_H)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(ICON, ICON)
        b.icon:SetPoint("LEFT", 2, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.iconEdge = Edges(b, b.icon, "OVERLAY", 1)
        b.iconText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.iconText:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
        b.iconText:SetText("XP")
        b.iconText:Hide()
        -- the sunken name box: dark, darker edge top / left, lighter bottom / right
        b.box = b:CreateTexture(nil, "BACKGROUND")
        b.box:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 3, -1)
        b.box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, (REWARD_H - ICON) / 2 + 1)
        b.box:SetColorTexture(0.10, 0.08, 0.065, 0.96)
        local e = Edges(b, b.box, "BORDER", 1)
        e[1]:SetColorTexture(0, 0, 0, 1)
        e[3]:SetColorTexture(0, 0, 0, 1)
        e[2]:SetColorTexture(0.45, 0.36, 0.24, 0.9)
        e[4]:SetColorTexture(0.45, 0.36, 0.24, 0.9)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.name:SetPoint("TOPLEFT", b.box, "TOPLEFT", 6, -2)
        b.name:SetPoint("BOTTOMRIGHT", b.box, "BOTTOMRIGHT", -4, 2)
        b.name:SetJustifyH("LEFT")
        b.name:SetJustifyV("MIDDLE")
        b:SetScript("OnEnter", function(self)
            if self.kind ~= "choice" and self.kind ~= "reward" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not (GameTooltip.SetQuestLogItem and pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.idx, self.questID))
                and self.itemID then
                pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.kind ~= "choice" and self.kind ~= "reward" then return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") and GetQuestLogItemLink then
                local link = Safe(GetQuestLogItemLink, self.kind, self.idx, self.questID)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        items[i] = b
    end
    b.iconText:Hide()
    b.icon:SetVertexColor(1, 1, 1)
    return b
end

local function Money(c)
    return ns.Bags and ns.Bags.Money and ns.Bags.Money(c) or (GetCoinTextureString and GetCoinTextureString(c)) or tostring(c)
end

local function DrawDetails()
    for _, t in ipairs(texts) do t:Hide() end
    for _, b in ipairs(items) do b:Hide() end
    local id = selected
    local e
    for _, x in ipairs(entries) do if x.questID == id then e = x break end end
    local hasQuest = id and IndexOf(id) ~= nil
    frame.abandon:SetEnabled(hasQuest and true or false)
    frame.mapBtn:SetEnabled(hasQuest and true or false)
    local push = hasQuest and (CQ.IsPushableQuest and Safe(CQ.IsPushableQuest, id)) and IsInGroup and IsInGroup()
    frame.share:SetEnabled(push and true or false)
    frame.track:SetEnabled(hasQuest and true or false)
    frame.track:SetChecked(hasQuest and IsTracked(id) or false)
    local width = frame.detailW - 8
    local y, n = 0, 0
    local function Line(text, kind, color, gap, justify)
        if not text or text == "" then return end
        n = n + 1
        local t = Text(n)
        Font(t, kind)
        t:SetWidth(width)
        t:SetJustifyH(justify or "LEFT")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", 4, -y)
        t:SetTextColor(color[1], color[2], color[3])
        t:SetText(text)
        t:Show()
        y = y + (t:GetStringHeight() or 12) + (gap or 4)
    end
    if not hasQuest then
        Line((QL.count or 0) == 0 and "No quests." or "Pick a quest above.", nil, INK_DONE, 0)
        frame.detailChild:SetHeight(40)
        return
    end
    Select(id)
    local idx = IndexOf(id)
    local desc, objText = Safe(GetQuestLogQuestText, idx)
    if not desc then desc, objText = Safe(GetQuestLogQuestText) end
    y = 4
    Line((e and e.title) or TitleOf(id) or "?", "title", INK, 8)
    Line(objText, nil, INK, 8)
    local objs = CQ.GetQuestObjectives and Safe(CQ.GetQuestObjectives, id)
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            if o.text and o.text ~= "" then Line(o.text, nil, o.finished and INK_DONE or INK, 2) end
        end
    end
    if e and e.group and e.group > 1 then Line(("Suggested Players [%d]"):format(e.group), nil, INK, 2) end
    y = y + 10
    Line(_G.QUEST_DESCRIPTION or "Description", "title", INK, 6)
    Line(desc, nil, INK, 10)

    local numR = Safe(GetNumQuestLogRewards, id) or 0
    local numC = Safe(GetNumQuestLogChoices, id, true) or 0
    local money = Safe(GetQuestLogRewardMoney, id) or 0
    local xp = Safe(GetQuestLogRewardXP, id) or 0
    -- the rewards on a dark panel (the game's modern reward look): gold heading,
    -- light text, icons with a quality edge and dark sunken boxes; XP and money first
    local panel = frame.rewardPanel
    if not panel then
        local c = frame.detailChild
        panel = { bg = c:CreateTexture(nil, "BACKGROUND", nil, -6) }
        panel.bg:SetColorTexture(0.235, 0.17, 0.12, 0.96)        -- warm bronze brown
        panel.top = c:CreateTexture(nil, "BACKGROUND", nil, -5)
        panel.top:SetColorTexture(0.50, 0.36, 0.18, 0.45)       -- bronze band behind the heading
        panel.anchor = CreateFrame("Frame", nil, c)
        panel.edge = Edges(c, panel.anchor, "BACKGROUND", 1)
        panel.edge:Color(0.62, 0.47, 0.26, 1)
        frame.rewardPanel = panel
    end
    local function ShowPanel(on) panel.bg:SetShown(on) panel.top:SetShown(on) for k = 1, 4 do panel.edge[k]:SetShown(on) end end
    ShowPanel(false)
    if numR + numC > 0 or money > 0 or xp > 0 then
        local LIGHT = { 0.92, 0.85, 0.70 }
        local GOLD = { 1, 0.82, 0 }
        y = y + 4
        local top = y
        y = y + 8
        Line(_G.REWARDS or "Rewards", "title", GOLD, 8, "CENTER")
        local half = math.floor((width - 16) / 2)
        local k = 0
        local function Place(b, col)
            b:SetWidth(half)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + col * (half + 4), -y)
            b:Show()
        end
        -- XP left, money right, on one row
        if xp > 0 or money > 0 then
            local col = 0
            if xp > 0 then
                k = k + 1
                local b = Item(k)
                b.kind = "xp"
                local icon = XPIcon()
                if icon then
                    b.icon:SetTexture(icon)
                else
                    b.icon:SetColorTexture(0.42, 0.12, 0.55, 1)
                    b.iconText:Show()
                end
                b.iconEdge:Color(0.62, 0.30, 0.80, 1)
                b.count:SetText("")
                b.name:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp))
                b.name:SetTextColor(1, 1, 1)
                Place(b, col)
                col = 1
            end
            if money > 0 then
                k = k + 1
                local b = Item(k)
                b.kind = "money"
                b.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
                b.iconEdge:Color(0.55, 0.45, 0.20, 1)
                b.count:SetText("")
                b.name:SetText(Money(money))
                b.name:SetTextColor(1, 1, 1)
                Place(b, col)
            end
            y = y + REWARD_H + 6
        end
        local function Items(kind, count, info)
            local col = 0
            for i = 1, count do
                local name, tex, num, quality, _, itemID = info(i)
                if name or tex then
                    k = k + 1
                    local b = Item(k)
                    b.kind, b.idx, b.questID, b.itemID = kind, i, id, itemID
                    b.icon:SetTexture(tex)
                    b.count:SetText((num and num > 1) and num or "")
                    b.name:SetText(name or "")
                    b.name:SetTextColor(1, 1, 1)
                    local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                    if qc then b.iconEdge:Color(qc.r, qc.g, qc.b, 1) else b.iconEdge:Color(0.4, 0.4, 0.4, 1) end
                    Place(b, col)
                    col = col + 1
                    if col == 2 then col = 0 y = y + REWARD_H + 4 end
                end
            end
            if col > 0 then y = y + REWARD_H + 4 end
            y = y + 2
        end
        local function Sub(text)
            n = n + 1
            local t = Text(n)
            Font(t, "small")
            t:SetWidth(width - 20)
            t:SetJustifyH("LEFT")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 12, -y)
            t:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3])
            t:SetText(text)
            t:Show()
            y = y + (t:GetStringHeight() or 12) + 4
        end
        if numC > 0 then
            Sub(numC > 1 and (_G.REWARD_CHOICES or "You will be able to choose one of these rewards:")
                or (_G.REWARD_ITEMS_ONLY or "You will receive:"))
            Items("choice", numC, function(i) return Safe(GetQuestLogChoiceInfo, i) end)
        end
        if numR > 0 then
            Sub(numC > 0 and (_G.REWARD_ITEMS or "You will also receive:") or (_G.REWARD_ITEMS_ONLY or "You will receive:"))
            Items("reward", numR, function(i) return Safe(GetQuestLogRewardInfo, i, id) end)
        end
        y = y + 4
        -- the panel behind it all
        panel.anchor:ClearAllPoints()
        panel.anchor:SetPoint("TOPLEFT", frame.detailChild, "TOPLEFT", 2, -top)
        panel.anchor:SetSize(width + 4, y - top)
        panel.bg:ClearAllPoints()
        panel.bg:SetAllPoints(panel.anchor)
        panel.top:ClearAllPoints()
        panel.top:SetPoint("TOPLEFT", panel.anchor, "TOPLEFT", 1, -1)
        panel.top:SetPoint("TOPRIGHT", panel.anchor, "TOPRIGHT", -1, -1)
        panel.top:SetHeight(30)
        ShowPanel(true)
        y = y + 6
    end
    frame.detailChild:SetHeight(math.max(y + 10, 10))
    frame.detail:SetVerticalScroll(0)
end

function QL.Refresh()
    if not (frame and frame:IsShown()) then return end
    Collect()
    local ok = false
    for _, e in ipairs(entries) do if e.questID and e.questID == selected then ok = true break end end
    if not ok then
        selected = nil
        for _, e in ipairs(entries) do if e.questID then selected = e.questID break end end
    end
    DrawList()
    DrawDetails()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Look()
    if not frame then return end
    local s = S()
    frame:ClearAllPoints()
    frame:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    frame:SetScale(s.scale)
end
QL.Look = Look
QL.Frame = function() return frame end

-- a scroll frame with the game's scroll bar when the template is there, else the mouse wheel only
local function Scroll(name, parent, w, h)
    local ok, sf = pcall(CreateFrame, "ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    if not ok or not sf then sf = CreateFrame("ScrollFrame", name, parent) end
    sf:SetSize(w, h)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 10)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    if not (ok and sf.ScrollBar) then
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 2 * RowH())))
        end)
    end
    return sf, child
end

local function PanelButton(text, w, onClick)
    local ok, b = pcall(CreateFrame, "Button", nil, frame, "UIPanelButtonTemplate")
    if not ok or not b then
        b = ns.UI.Button(frame, w, text, onClick)
        b:SetHeight(22)
        return b
    end
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Parchment(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    if not (t.SetAtlas and pcall(t.SetAtlas, t, "QuestDetailsBackgrounds")) then
        t:SetTexture("Interface\\QuestFrame\\QuestBG")
        t:SetTexCoord(0, 0.586, 0.02, 0.655)
    end
    return t
end

-- a sunken box (the game's inset frame, else a flat one)
local function Inset(parent)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", nil, parent)
        ns.UI.Fill(f, 0.03, 0.03, 0.03, 0.9)
        ns.UI.Border(f, 0.3, 0.3, 0.3, 1)
    end
    return f
end

-- everything both layouts share: drag, title text, count, All, Track, map, buttons
local function Common()
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    if UISpecialFrames then
        local known = false
        for _, n in ipairs(UISpecialFrames) do if n == "HUF_QuestLog" then known = true end end
        if not known then table.insert(UISpecialFrames, "HUF_QuestLog") end
    end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame.from = { frame:GetLeft(), frame:GetTop() } ns.Snap.StartDrag(frame) end)
    frame:SetScript("OnDragStop", function()
        ns.Snap.StopDrag(frame)
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        local from = frame.from
        frame.from = nil
        if not from then return end
        local p = S().point
        p[3] = math.floor(p[3] + (frame:GetLeft() - from[1]) + 0.5)
        p[4] = math.floor(p[4] + (frame:GetTop() - from[2]) + 0.5)
        Look()
    end)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    local all = CreateFrame("Button", nil, frame)
    all:SetSize(54, 16)
    frame.allIcon = all:CreateTexture(nil, "ARTWORK")
    frame.allIcon:SetSize(16, 16)
    frame.allIcon:SetPoint("LEFT")
    local allText = all:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    allText:SetPoint("LEFT", frame.allIcon, "RIGHT", 2, 0)
    allText:SetText(_G.ALL or "All")
    all:SetScript("OnClick", function()
        local open = false
        for _, e in ipairs(entries) do if e.header and not e.collapsed then open = true break end end
        for _, sec in ipairs(sections) do collapsed[sec.title] = open or nil end
        QL.Refresh()
    end)
    frame.allBtn = all

    local okT, track = pcall(CreateFrame, "CheckButton", nil, frame, "UICheckButtonTemplate")
    if not okT or not track then track = CreateFrame("CheckButton", nil, frame) end
    track:SetSize(22, 22)
    local trackText = track:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackText:SetPoint("LEFT", track, "RIGHT", 0, 1)
    trackText:SetText(_G.TRACK_QUEST_ABBREV or "Track")
    track:SetScript("OnClick", function() if selected then QL.ToggleTrack(selected) QL.Refresh() end end)
    frame.track = track

    local map = CreateFrame("Button", nil, frame)
    map:SetSize(24, 24)
    map:SetPoint("RIGHT", track, "LEFT", -6, 0)
    map:SetNormalTexture("Interface\\QuestFrame\\UI-QuestMap_Button")
    map:SetPushedTexture("Interface\\QuestFrame\\UI-QuestMap_Button")
    local nt, pt = map:GetNormalTexture(), map:GetPushedTexture()
    if nt then nt:SetTexCoord(0.125, 0.875, 0, 0.5) end
    if pt then pt:SetTexCoord(0.125, 0.875, 0.5, 1) end
    map:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    map:SetScript("OnClick", function() if selected then QL.OpenMap(selected) end end)
    map:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText("Show on the map") GameTooltip:Show() end)
    map:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.mapBtn = map

    frame.abandon = PanelButton(_G.ABANDON_QUEST_ABBREV or "Abandon", 117, function()
        local id = selected
        if not id then return end
        ns.UI.Confirm(("Abandon \"%s\"?"):format(TitleOf(id) or "this quest"), "Abandon", function()
            Select(id)
            if CQ.SetAbandonQuest then Safe(CQ.SetAbandonQuest) elseif SetAbandonQuest then Safe(SetAbandonQuest) end
            if CQ.AbandonQuest then Safe(CQ.AbandonQuest) elseif AbandonQuest then Safe(AbandonQuest) end
        end)
    end)
    frame.share = PanelButton(_G.SHARE_QUEST_ABBREV or "Share", 117, function()
        if not selected then return end
        Select(selected)
        if QuestLogPushQuest then Safe(QuestLogPushQuest) end
    end)
    frame.exit = PanelButton(_G.EXIT or "Exit", 77, function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then pcall(PlaySound, SOUNDKIT.IG_QUEST_LOG_OPEN) end
        QL.Refresh()
    end)
    frame:SetScript("OnHide", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE then pcall(PlaySound, SOUNDKIT.IG_QUEST_LOG_CLOSE) end
    end)
end

-- one column: the original game's window and art (384 x 512)
local function BuildClassic()
    frame = CreateFrame("Frame", "HUF_QuestLog", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetHitRectInsets(0, 30, 0, 70)        -- the art's see-through edges
    Common()
    local book = frame:CreateTexture(nil, "BACKGROUND")
    book:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
    book:SetSize(64, 64)
    book:SetPoint("TOPLEFT", 7, -6)
    for _, p in ipairs({ { "TopLeft", 256, "TOPLEFT" }, { "TopRight", 128, "TOPRIGHT" },
        { "BotLeft", 256, "BOTTOMLEFT" }, { "BotRight", 128, "BOTTOMRIGHT" } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\QuestFrame\\UI-QuestLog-" .. p[1])
        t:SetSize(p[2], 256)
        t:SetPoint(p[3], 0, 0)
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -17)
    title:SetText(_G.QUEST_LOG or "Quest Log")
    local okC, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if okC and close then
        close:SetPoint("TOPRIGHT", -29, -8)
        close:SetScript("OnClick", function() frame:Hide() end)
    end
    frame.count:SetPoint("TOPRIGHT", -54, -46)
    frame.allBtn:SetPoint("TOPLEFT", 74, -44)
    frame.track:SetPoint("TOPRIGHT", -130, -41)
    -- parchment under the quest's text: Forever's copy of the art is dark there
    local parch = Parchment(frame)
    parch:SetPoint("TOPLEFT", LIST_X - 2, DETAIL_Y + 2)
    parch:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", LIST_X + DETAIL_W, DETAIL_Y - DETAIL_H - 1)
    frame.listW, frame.detailW, frame.rows = DETAIL_W - 4, DETAIL_W, ROWS
    frame.list, frame.listChild = Scroll("HUF_QuestLogList", frame, frame.listW, ROWS * ROW_H)
    frame.list:SetPoint("TOPLEFT", LIST_X, LIST_Y)
    frame.detail, frame.detailChild = Scroll("HUF_QuestLogDetail", frame, DETAIL_W, DETAIL_H)
    frame.detail:SetPoint("TOPLEFT", LIST_X, DETAIL_Y)
    frame.abandon:SetSize(117, 21)
    frame.abandon:SetPoint("BOTTOMLEFT", 18, 54)
    frame.share:SetSize(117, 21)
    frame.share:SetPoint("LEFT", frame.abandon, "RIGHT", 0, 0)
    frame.exit:SetSize(77, 21)
    frame.exit:SetPoint("BOTTOMRIGHT", -34, 54)
end

-- two sides: the game's window frame, the quest list left, the quest's text right
local DUAL_W, DUAL_H, TOP_Y, BOTTOM_Y = 765, 570, -60, 26    -- 695 x 496 + 10 % wider (right side only), 15 % taller
local DUAL_MID = 347                                          -- the list side keeps its width
local function BuildDual()
    local ok, f = pcall(CreateFrame, "Frame", "HUF_QuestLog", UIParent, "ButtonFrameTemplate")
    frame = (ok and f) or CreateFrame("Frame", "HUF_QuestLog", UIParent)
    frame:SetSize(DUAL_W, DUAL_H)
    Common()
    if ok and f then
        local function T(x) return type(x) == "table" and x or nil end
        if T(frame.Inset) then frame.Inset:Hide() end
        local tc = T(frame.TitleContainer)
        if tc and T(tc.TitleText) then tc.TitleText:SetText(_G.QUEST_LOG or "Quest Log")
        elseif frame.SetTitle then pcall(frame.SetTitle, frame, _G.QUEST_LOG or "Quest Log") end
        if T(frame.CloseButton) then frame.CloseButton:SetScript("OnClick", function() frame:Hide() end) end
        local pc = T(frame.PortraitContainer)
        if pc and T(pc.portrait) then pc.portrait:SetAlpha(0) end
    else
        ns.UI.Fill(frame, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(frame, 0.35, 0.35, 0.35, 1)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -6)
        title:SetText(_G.QUEST_LOG or "Quest Log")
        local x = CreateFrame("Button", nil, frame)
        x:SetSize(18, 18)
        x:SetPoint("TOPRIGHT", -4, -3)
        local xt = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        xt:SetPoint("CENTER")
        xt:SetText("x")
        x:SetScript("OnClick", function() frame:Hide() end)
    end
    -- the book as the window's portrait
    local book = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    book:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
    book:SetSize(64, 64)
    book:SetPoint("TOPLEFT", -6, 7)

    frame.allBtn:SetPoint("TOPLEFT", 62, -36)
    frame.count:SetPoint("LEFT", frame.allBtn, "RIGHT", 8, 0)
    frame.track:SetPoint("TOPRIGHT", -70, -31)

    local mid = DUAL_MID
    local left = Inset(frame)
    left:SetPoint("TOPLEFT", 6, TOP_Y)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", mid - 1, BOTTOM_Y)
    -- near-black under the list, over the inset's own grey (its edge stays on top)
    local dark = left:CreateTexture(nil, "BACKGROUND", nil, 7)
    dark:SetColorTexture(0.02, 0.02, 0.02, 0.92)
    dark:SetPoint("TOPLEFT", 2, -2)
    dark:SetPoint("BOTTOMRIGHT", -2, 2)
    local right = Inset(frame)
    right:SetPoint("TOPLEFT", frame, "TOPLEFT", mid + 1, TOP_Y)
    right:SetPoint("BOTTOMRIGHT", -6, BOTTOM_Y)
    local parch = Parchment(right)
    parch:SetPoint("TOPLEFT", 2, -2)
    parch:SetPoint("BOTTOMRIGHT", -2, 2)

    local innerH = DUAL_H + TOP_Y - BOTTOM_Y
    frame.listW = (mid - 1 - 6) - 34
    frame.detailW = (DUAL_W - 6 - mid - 1) - 40
    frame.rows = math.floor((innerH - 12) / ROW_H)
    frame.list, frame.listChild = Scroll("HUF_QuestLogList", left, frame.listW, innerH - 12)
    frame.list:SetPoint("TOPLEFT", 6, -6)
    frame.detail, frame.detailChild = Scroll("HUF_QuestLogDetail", right, frame.detailW, innerH - 16)
    frame.detail:SetPoint("TOPLEFT", 10, -8)

    frame.abandon:SetSize(120, 22)
    frame.abandon:SetPoint("BOTTOMLEFT", 4, 3)
    frame.share:SetSize(120, 22)
    frame.share:SetPoint("LEFT", frame.abandon, "RIGHT", 4, 0)
    frame.exit:SetSize(100, 22)
    frame.exit:SetPoint("BOTTOMRIGHT", -4, 3)
end

local function Build()
    if frame then return end
    if S().layout == "CLASSIC" then BuildClassic() else BuildDual() end
    frame.layout = S().layout
    QL.frame = frame
    Look()
end

-- the layout changed: a new window in the other layout
function QL.Rebuild()
    if not frame then return end
    local shown = frame:IsShown()
    frame:Hide()
    frame = nil
    wipe(rows) wipe(texts) wipe(items)
    Build()
    if shown then frame:Show() end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function QL.ToggleTrack(id)
    if CQ.GetQuestWatchType then
        if IsTracked(id) then Safe(CQ.RemoveQuestWatch, id) else Safe(CQ.AddQuestWatch, id) end
    elseif AddQuestWatch then
        local idx = IndexOf(id)
        if IsTracked(id) then Safe(RemoveQuestWatch, idx) else Safe(AddQuestWatch, idx) end
    end
end

local O = {}       -- the game's own functions
function QL.OpenMap(id)
    if O.openDetails then Safe(O.openDetails, id)
    elseif QuestMapFrame_OpenToQuestDetails then Safe(QuestMapFrame_OpenToQuestDetails, id)
    elseif ToggleWorldMap then Safe(ToggleWorldMap) end
end

function QL.Show(id)
    Build()
    if id then
        selected = id
        local c = QL.GetCategory(id)
        if c then collapsed[c] = nil end
        local zone
        for i = 1, NumEntries() or 0 do
            local q = Info(i)
            if q and q.isHeader then zone = q.title end
            if q and q.questID == id then if zone then collapsed[zone] = nil end break end
        end
    end
    if frame:IsShown() then QL.Refresh() else frame:Show() end
    -- the selected quest in view
    if selected then
        for i, e in ipairs(entries) do
            if e.questID == selected then
                local top = frame.list:GetVerticalScroll() or 0
                local rh = RowH()
                local visible = math.max(1, math.floor((frame.list:GetHeight() or rh) / rh))
                local y = (i - 1) * rh
                if y < top or y > top + (visible - 1) * rh then frame.list:SetVerticalScroll(math.max(0, y - rh)) end
                break
            end
        end
    end
end
function QL.Toggle()
    Build()
    if frame:IsShown() then frame:Hide() else QL.Show() end
end

---------------------------------------------------------------------------
-- Taking over the quest log key and tracker clicks
---------------------------------------------------------------------------
local taken
function QL.Apply()
    if not ns.db then return end
    Build()
    Look()
    if not S().enabled or taken then QL.Refresh() return end
    taken = true
    O.toggle = _G.ToggleQuestLog
    O.openLog = _G.OpenQuestLog
    O.openDetails = _G.QuestMapFrame_OpenToQuestDetails
    O.openToQuest = _G.QuestLog_OpenToQuest
    _G.ToggleQuestLog = function(...)
        if not S().enabled then return O.toggle and O.toggle(...) end
        QL.Toggle()
    end
    if O.openLog then
        _G.OpenQuestLog = function(...)
            if not S().enabled then return O.openLog(...) end
            QL.Show()
        end
    end
    -- a click on a quest in the tracker; on the open map the map keeps it
    _G.QuestMapFrame_OpenToQuestDetails = function(id, ...)
        local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
        if not (S().enabled and S().tracker) or mapOpen then
            return O.openDetails and O.openDetails(id, ...)
        end
        QL.Show(id)
    end
    -- MMT's quest tracker (and classic code) asks for a quest log index
    _G.QuestLog_OpenToQuest = function(index, ...)
        if not (S().enabled and S().tracker) then return O.openToQuest and O.openToQuest(index, ...) end
        local q = Info(index)
        QL.Show(q and q.questID)
    end
    ns.Log("questlog", "quest log key and tracker clicks open HUF's quest log")
end

ns.OnLogin(function() if S().enabled then QL.Apply() end end)

for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    ns.On(ev, function()
        if not (frame and frame:IsShown()) or QL.pending then return end
        QL.pending = true
        C_Timer.After(0.1, function() QL.pending = nil QL.Refresh() end)
    end)
end

-- a quest that left the log loses its category
ns.On("QUEST_REMOVED", function(id)
    if ns.db and type(id) == "number" and Cat().quests[id] then
        Cat().quests[id] = nil
        for _, fn in ipairs(listeners) do pcall(fn, "CATEGORIES_CHANGED") end
    end
end)

function QL.Report(add)
    local c = Cat()
    local n = 0
    for _ in pairs(c.quests) do n = n + 1 end
    add(("quest log: enabled=%s tracker=%s taken=%s shown=%s quests=%s selected=%s categories=%d (%d quests in them) listeners=%d"):format(
        tostring(S().enabled), tostring(S().tracker), tostring(taken or false), tostring(frame and frame:IsShown() or false),
        tostring(QL.count), tostring(selected), #c.list, n, #listeners))
    -- each quest: level, group size, the game's tag info (what the elite "+" reads)
    for i = 1, NumEntries() or 0 do
        local q = Info(i)
        if q and q.questID and not q.isHeader then
            local tag = CQ.GetQuestTagInfo and Safe(CQ.GetQuestTagInfo, q.questID)
            local t = type(tag) == "table" and ("tagID=%s tagName=%s isElite=%s"):format(tostring(tag.tagID),
                tostring(tag.tagName), tostring(tag.isElite)) or "no tag"
            add(("  quest %d [%s] %s: group=%s %s -> elite=%s"):format(q.questID, tostring(q.level), tostring(q.title),
                tostring(q.suggestedGroup), t, tostring(IsElite(q.questID))))
        end
    end
end
