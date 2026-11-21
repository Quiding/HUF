-- HUF: a classic quest log window (quest list left, details right) instead of
-- the game's combined map + quest window. Off by default. While on, the quest
-- log key (ToggleQuestLog) and a click on a quest in the tracker
-- (QuestMapFrame_OpenToQuestDetails, MMT's QuestLog_OpenToQuest) open it; the
-- map key still opens the map, and a quest clicked on the open map still shows
-- in the map. Those globals are replaced while on (back after /reload when off).

local _, ns = ...
local QL = {}
ns.QuestLog = QL
local A = ns.ACCENT

local W, H, LIST_W, HEAD_H, FOOT_H, PAD = 700, 470, 260, 26, 32, 8

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
local collapsed = {}      -- header title -> true
local listOffset = 0
local entries = {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function Info(i)
    if CQ.GetInfo then return Safe(CQ.GetInfo, i) end
    if GetQuestLogTitle then
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(i)
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
local function IsTracked(id)
    if CQ.GetQuestWatchType then return Safe(CQ.GetQuestWatchType, id) ~= nil end
    if IsQuestWatched and CQ.GetLogIndexForQuestID then return Safe(IsQuestWatched, CQ.GetLogIndexForQuestID(id)) end
    return false
end
local function IndexOf(id)
    if CQ.GetLogIndexForQuestID then return Safe(CQ.GetLogIndexForQuestID, id) end
end
local function Select(id)
    if CQ.SetSelectedQuest then Safe(CQ.SetSelectedQuest, id)
    elseif SelectQuestLogEntry then Safe(SelectQuestLogEntry, IndexOf(id)) end
end

-- the list: headers (collapsible, HUF's own state) and quests
local function Collect()
    wipe(entries)
    local n = NumEntries() or 0
    local header, hidden = nil, false
    local quests = 0
    for i = 1, n do
        local q = Info(i)
        if q and q.isHeader then
            header = q.title or ""
            hidden = collapsed[header]
            entries[#entries + 1] = { header = true, title = header, collapsed = hidden }
        elseif q and q.questID and not q.isHidden and not q.isTask and not q.isBounty then
            quests = quests + 1
            if not hidden then
                entries[#entries + 1] = {
                    questID = q.questID, index = q.questLogIndex or i, title = q.title or "?", level = q.level,
                    group = q.suggestedGroup, daily = Enum and Enum.QuestFrequency and q.frequency == Enum.QuestFrequency.Daily,
                    complete = IsComplete(q), failed = IsFailed(q), tracked = IsTracked(q.questID),
                }
            end
        end
    end
    QL.count = quests
    return entries
end

local function MaxQuests()
    return (CQ.GetMaxNumQuestsCanAccept and Safe(CQ.GetMaxNumQuestsCanAccept)) or MAX_QUESTS or 25
end

local function Hex(c) return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
local function LevelColor(level)
    local c = ns.LevelColor and ns.LevelColor(level)
    return c or { r = 1, g = 0.82, b = 0 }
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Font(fs, size)
    local s = S()
    ns.ApplyFont(fs, s.font, size or s.fontSize, s.outline)
end

local function Btn(parent, text, w, onClick)
    local b = ns.UI.Button(parent, w, text, onClick)
    b:SetHeight(20)
    return b
end

local function RowH() return S().fontSize + 7 end

local rows = {}
local function NewRow(i)
    local r = CreateFrame("Button", nil, frame.list)
    r:SetHeight(RowH())
    r:SetPoint("LEFT", 0, 0)
    r:SetPoint("RIGHT", 0, 0)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(A[1], A[2], A[3], 0.25)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.text = r:CreateFontString(nil, "OVERLAY")
    Font(r.text)
    r.text:SetPoint("LEFT", 6, 0)
    r.text:SetPoint("RIGHT", -18, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.mark = r:CreateFontString(nil, "OVERLAY")
    Font(r.mark)
    r.mark:SetPoint("RIGHT", -4, 0)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            collapsed[e.title] = not collapsed[e.title] or nil
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

local function VisibleRows()
    return math.max(1, math.floor((frame.list:GetHeight() or 300) / RowH()))
end

local function DrawList()
    local n = VisibleRows()
    listOffset = math.max(0, math.min(listOffset, #entries - n))
    for i = 1, math.max(n, #rows) do
        local r = rows[i] or (i <= n and NewRow(i))
        if r then
            local e = i <= n and entries[listOffset + i]
            r.entry = e
            if e then
                r:SetHeight(RowH())
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * RowH())
                r:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", 0, -(i - 1) * RowH())
                Font(r.text)
                Font(r.mark)
                if e.header then
                    r.text:SetText((e.collapsed and "+ " or "- ") .. e.title)
                    r.text:SetTextColor(A[1], A[2], A[3])
                    r.mark:SetText("")
                    r.sel:Hide()
                else
                    local c = LevelColor(e.level)
                    local lvl = (S().levels and e.level and e.level > 0)
                        and ("[" .. e.level .. ((e.group and e.group > 1) and "+" or "") .. "] ") or ""
                    local tail = e.failed and " |cffff4040(Failed)|r" or (e.complete and " |cff40ff40(Complete)|r" or "")
                    if e.daily then tail = tail .. " |cff80c0ff(Daily)|r" end
                    r.text:SetText("   " .. lvl .. e.title .. tail)
                    r.text:SetTextColor(c.r, c.g, c.b)
                    r.mark:SetText(e.tracked and "|cffffd200*|r" or "")
                    r.sel:SetShown(e.questID == selected)
                end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    frame.count:SetText(("%d / %d"):format(QL.count or 0, MaxQuests()))
end

---------------------------------------------------------------------------
-- Details (scrolling text + rewards)
---------------------------------------------------------------------------
local texts, items = {}, {}
local function Text(i)
    local t = texts[i]
    if not t then
        t = frame.content:CreateFontString(nil, "OVERLAY")
        Font(t)
        t:SetJustifyH("LEFT")
        t:SetJustifyV("TOP")
        t:SetWordWrap(true)
        texts[i] = t
    end
    return t
end
local function Item(i)
    local b = items[i]
    if not b then
        b = CreateFrame("Button", nil, frame.content)
        b:SetSize(150, 28)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(26, 26)
        b.icon:SetPoint("LEFT", 1, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ns.UI.Border(b, 0.25, 0.25, 0.27, 1)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 1)
        b.name = b:CreateFontString(nil, "OVERLAY")
        Font(b.name)
        b.name:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.name:SetPoint("RIGHT", -2, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not (GameTooltip.SetQuestLogItem and pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.idx, self.questID))
                and self.itemID then
                pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if IsModifiedClick and IsModifiedClick("CHATLINK") and GetQuestLogItemLink then
                local link = Safe(GetQuestLogItemLink, self.kind, self.idx, self.questID)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        items[i] = b
    end
    return b
end

local function Money(c)
    return ns.Bags and ns.Bags.Money and ns.Bags.Money(c) or GetCoinTextureString and GetCoinTextureString(c) or tostring(c)
end

local function DrawDetails()
    for _, t in ipairs(texts) do t:Hide() end
    for _, b in ipairs(items) do b:Hide() end
    local id = selected
    local e
    for _, x in ipairs(entries) do if x.questID == id then e = x break end end
    local hasQuest = id and IndexOf(id) ~= nil
    frame.abandon:SetEnabled(hasQuest)
    frame.track:SetEnabled(hasQuest)
    frame.mapBtn:SetEnabled(hasQuest)
    local push = hasQuest and (CQ.IsPushableQuest and Safe(CQ.IsPushableQuest, id)) and IsInGroup and IsInGroup()
    frame.share:SetEnabled(push and true or false)
    frame.track.label:SetText(hasQuest and IsTracked(id) and "Untrack" or "Track")
    if not hasQuest then
        local t = Text(1)
        Font(t)
        t:SetWidth(frame.content:GetWidth())
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", 0, 0)
        t:SetTextColor(0.6, 0.6, 0.6)
        t:SetText((QL.count or 0) == 0 and "No quests." or "Pick a quest on the left.")
        t:Show()
        frame.content:SetHeight(40)
        return
    end
    Select(id)
    local idx = IndexOf(id)
    local desc, objText = Safe(GetQuestLogQuestText, idx)
    if not desc then desc, objText = Safe(GetQuestLogQuestText) end
    local width = frame.content:GetWidth()
    local y, n = 0, 0
    local s = S()
    local function Line(text, size, r, g, b, gap)
        if not text or text == "" then return end
        n = n + 1
        local t = Text(n)
        Font(t, size)
        t:SetWidth(width)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", 0, -y)
        t:SetTextColor(r, g, b)
        t:SetText(text)
        t:Show()
        y = y + (t:GetStringHeight() or size) + (gap or 4)
    end
    local title = (e and e.title) or (CQ.GetTitleForQuestID and Safe(CQ.GetTitleForQuestID, id)) or "?"
    Line(title, s.titleSize, A[1], A[2], A[3], 6)
    Line(objText, nil, 0.95, 0.95, 0.95, 6)
    -- objectives with progress
    local objs = CQ.GetQuestObjectives and Safe(CQ.GetQuestObjectives, id)
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            if o.text and o.text ~= "" then
                if o.finished then Line("  - " .. o.text, nil, 0.55, 0.55, 0.55, 2)
                else Line("  - " .. o.text, nil, 1, 0.82, 0, 2) end
            end
        end
    end
    if e and e.group and e.group > 1 then Line(("Suggested group: %d"):format(e.group), nil, 1, 0.5, 0.25, 2) end
    y = y + 6
    Line("Description", s.titleSize - 1, A[1], A[2], A[3], 4)
    Line(desc, nil, 0.85, 0.85, 0.85, 8)

    -- rewards
    local numR = Safe(GetNumQuestLogRewards, id) or 0
    local numC = Safe(GetNumQuestLogChoices, id, true) or 0
    local money = Safe(GetQuestLogRewardMoney, id) or 0
    local xp = Safe(GetQuestLogRewardXP, id) or 0
    if numR + numC > 0 or money > 0 or xp > 0 then
        y = y + 4
        Line("Rewards", s.titleSize - 1, A[1], A[2], A[3], 4)
        local k = 0
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
                    Font(b.name)
                    b.name:SetText(name or "")
                    local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                    if qc then b.name:SetTextColor(qc.r, qc.g, qc.b) else b.name:SetTextColor(1, 1, 1) end
                    b:SetWidth(math.floor((width - 8) / 2))
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", col * (math.floor((width - 8) / 2) + 8), -y)
                    b:Show()
                    col = col + 1
                    if col == 2 then col = 0 y = y + 32 end
                end
            end
            if col > 0 then y = y + 32 end
        end
        if numC > 0 then
            Line(numC > 1 and "Choose one of these:" or "You will receive:", nil, 0.85, 0.85, 0.85, 4)
            Items("choice", numC, function(i) return Safe(GetQuestLogChoiceInfo, i) end)
        end
        if numR > 0 then
            Line(numC > 0 and "You will also receive:" or "You will receive:", nil, 0.85, 0.85, 0.85, 4)
            Items("reward", numR, function(i) return Safe(GetQuestLogRewardInfo, i, id) end)
        end
        if money > 0 then Line("Money: " .. Money(money), nil, 1, 1, 1, 2) end
        if xp > 0 then Line(("Experience: %s"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp), nil, 1, 1, 1, 2) end
    end
    frame.content:SetHeight(math.max(y, 10))
    frame.scroll:SetVerticalScroll(0)
end

function QL.Refresh()
    if not (frame and frame:IsShown()) then return end
    Collect()
    -- keep a valid selection: the first quest when none
    local ok = false
    for _, e in ipairs(entries) do if e.questID and e.questID == selected then ok = true break end end
    if not ok then
        selected = nil
        for _, e in ipairs(entries) do if e.questID then selected = e.questID break end end
    end
    DrawList()
    DrawDetails()
end

local function Look()
    if not frame then return end
    local s = S()
    frame:ClearAllPoints()
    frame:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    frame:SetScale(s.scale)
    frame.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
    Font(frame.title, s.titleSize)
    Font(frame.count)
end
QL.Look = Look

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "HUF_QuestLog", UIParent)
    QL.frame = frame
    frame:SetSize(W, H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bg:SetAllPoints()
    ns.UI.Border(frame, A[1], A[2], A[3], 1)
    if UISpecialFrames then table.insert(UISpecialFrames, "HUF_QuestLog") end

    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() frame.from = { frame:GetLeft(), frame:GetTop() } frame:StartMoving() end)
    head:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        local from = frame.from
        frame.from = nil
        if not from then return end
        local p = S().point
        p[3] = math.floor(p[3] + (frame:GetLeft() - from[1]) + 0.5)
        p[4] = math.floor(p[4] + (frame:GetTop() - from[2]) + 0.5)
        Look()
    end)
    frame.title = head:CreateFontString(nil, "OVERLAY")
    Font(frame.title, S().titleSize)
    frame.title:SetPoint("LEFT", PAD, 0)
    frame.title:SetText("Quest Log")
    frame.count = head:CreateFontString(nil, "OVERLAY")
    Font(frame.count)
    frame.count:SetPoint("RIGHT", -30, 0)
    frame.count:SetTextColor(0.7, 0.7, 0.7)
    local close = CreateFrame("Button", nil, head)
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER")
    x:SetText("x")
    close:SetScript("OnClick", function() frame:Hide() end)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(A[1], A[2], A[3], 0.5)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -HEAD_H)
    line:SetPoint("TOPRIGHT", 0, -HEAD_H)

    -- the quest list (mouse wheel scrolls)
    frame.list = CreateFrame("Frame", nil, frame)
    frame.list:SetPoint("TOPLEFT", PAD, -(HEAD_H + PAD))
    frame.list:SetPoint("BOTTOMLEFT", PAD, FOOT_H + PAD)
    frame.list:SetWidth(LIST_W)
    frame.list:EnableMouseWheel(true)
    frame.list:SetScript("OnMouseWheel", function(_, d)
        listOffset = listOffset - d * 3
        DrawList()
    end)
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.08)
    sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", PAD / 2, 0)
    sep:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", PAD / 2, 0)

    -- the details (scrolling)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame)
    frame.scroll:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", PAD * 2, 0)
    frame.scroll:SetPoint("BOTTOMRIGHT", -PAD * 2, FOOT_H + PAD)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(W - LIST_W - PAD * 5, 10)
    frame.scroll:SetScrollChild(frame.content)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (frame.content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 30)))
    end)

    -- buttons
    frame.abandon = Btn(frame, "Abandon", 90, function()
        local id = selected
        if not id then return end
        local title = CQ.GetTitleForQuestID and Safe(CQ.GetTitleForQuestID, id) or "this quest"
        ns.UI.Confirm(("Abandon \"%s\"?"):format(title), "Abandon", function()
            Select(id)
            if CQ.SetAbandonQuest then Safe(CQ.SetAbandonQuest) elseif SetAbandonQuest then Safe(SetAbandonQuest) end
            if CQ.AbandonQuest then Safe(CQ.AbandonQuest) elseif AbandonQuest then Safe(AbandonQuest) end
        end)
    end)
    frame.abandon:SetPoint("BOTTOMLEFT", PAD, PAD)
    frame.share = Btn(frame, "Share", 90, function()
        if not selected then return end
        Select(selected)
        if QuestLogPushQuest then Safe(QuestLogPushQuest) end
    end)
    frame.share:SetPoint("LEFT", frame.abandon, "RIGHT", 6, 0)
    frame.track = Btn(frame, "Track", 90, function() if selected then QL.ToggleTrack(selected) QL.Refresh() end end)
    frame.track:SetPoint("LEFT", frame.share, "RIGHT", 6, 0)
    frame.mapBtn = Btn(frame, "Show on map", 110, function() if selected then QL.OpenMap(selected) end end)
    frame.mapBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    frame:SetScript("OnShow", function() QL.Refresh() end)
    Look()
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
    elseif O.toggle then Safe(O.toggle)
    elseif ToggleWorldMap then Safe(ToggleWorldMap) end
end

function QL.Show(id)
    Build()
    if id then
        selected = id
        local t = CQ.GetTitleForQuestID and Safe(CQ.GetTitleForQuestID, id)
        -- open its header
        for i = 1, NumEntries() or 0 do
            local q = Info(i)
            if q and q.isHeader then QL.lastHeader = q.title end
            if q and q.questID == id and QL.lastHeader then collapsed[QL.lastHeader] = nil break end
        end
    end
    if frame:IsShown() then QL.Refresh() else frame:Show() end
    -- the selected quest in view
    if selected then
        for i, e in ipairs(entries) do
            if e.questID == selected then
                local n = VisibleRows()
                if i <= listOffset or i > listOffset + n then listOffset = i - 1 DrawList() end
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

function QL.Report(add)
    add(("quest log: enabled=%s tracker=%s taken=%s shown=%s quests=%s selected=%s"):format(tostring(S().enabled),
        tostring(S().tracker), tostring(taken or false), tostring(frame and frame:IsShown() or false),
        tostring(QL.count), tostring(selected)))
end
