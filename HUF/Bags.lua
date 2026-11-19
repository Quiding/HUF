-- HUF: bags (one bag window), bank and other characters, search, item counts
-- in tooltips.
--   * your own bags: the game's real item buttons (ContainerFrameItemButton-
--     Template, made out of combat only), so using, moving and selling items
--     works as in Blizzard's bags, also in combat
--   * bank and other characters: from snapshots (just to look at, tooltips);
--     the bank is read whenever it is open, your bags on every change
--   * search: dims everything whose name doesn't match
--   * tooltips: "Name: 8 | 12" (bags | bank) for this and every other character
-- Snapshots live in HUFDB.inventory (account-wide, never in a profile export).
-- The game's own "combined bags" option (one bag) is switched on with a setting.

local _, ns = ...
local Bags = {}
ns.Bags = Bags

local A = ns.ACCENT
local FLAT = "Interface\\Buttons\\WHITE8X8"
local function S() return ns.db.bags end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local HEADER_H, SEARCH_H, FOOTER_H = 26, 24, 20
local function T(v) return type(v) == "table" and v or nil end   -- a region of a template, if there

---------------------------------------------------------------------------
-- Bag ids
---------------------------------------------------------------------------
local function BagIDs()
    local l = {}
    local BI = Enum and Enum.BagIndex
    local last = NUM_BAG_SLOTS or 4
    for b = 0, last do l[#l + 1] = b end
    local reagent = BI and BI.ReagentBag
    if reagent and (NUM_REAGENTBAG_SLOTS or 0) > 0 then l[#l + 1] = reagent end
    return l
end

local function BankIDs()
    local l = {}
    local BI = Enum and Enum.BagIndex
    local base = (BI and BI.Bank) or BANK_CONTAINER or -1
    l[#l + 1] = base
    if BI then
        for i = 1, 9 do
            local id = BI["CharacterBankTab_" .. i]
            if id then l[#l + 1] = id end
        end
    end
    if not (BI and BI.CharacterBankTab_1) then
        -- classic layout: bank bags after the bag slots
        local first = (NUM_BAG_SLOTS or 4) + 1
        for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do l[#l + 1] = b end
    end
    return l
end

local function NumSlots(bag)
    if not C_Container then return 0 end
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    return ok and tonumber(n) or 0
end

local function ItemInfo(bag, slot)
    if not C_Container then return nil end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then return info end
end

---------------------------------------------------------------------------
-- Snapshots: HUFDB.inventory[charKey] = { class, money, time, bags = {...},
-- bank = {...}, bankTime }; a list = { {size, items = {[slot] = {link, count}}}, ... }
---------------------------------------------------------------------------
local function Store()
    HUFDB.inventory = HUFDB.inventory or {}
    return HUFDB.inventory
end

local function Me()
    local st = Store()
    local k = ns.CharKey()
    st[k] = st[k] or {}
    return st[k]
end

local function ReadContainers(ids)
    local out = {}
    for _, bag in ipairs(ids) do
        local n = NumSlots(bag)
        local b = { bag = bag, size = n, items = {} }
        for slot = 1, n do
            local info = ItemInfo(bag, slot)
            if info and info.hyperlink and not IsSecret(info.hyperlink) then
                b.items[slot] = { info.hyperlink, info.stackCount or 1, info.itemID }
            end
        end
        out[#out + 1] = b
    end
    return out
end

function Bags.SnapshotBags()
    local me = Me()
    local _, class = UnitClass("player")
    me.class = class
    me.money = GetMoney and GetMoney() or 0
    me.bags = ReadContainers(BagIDs())
    me.time = time()
end

function Bags.SnapshotBank()
    local me = Me()
    me.bank = ReadContainers(BankIDs())
    me.bankTime = time()
end

local bankOpen = false
local pendingSnap
local function SnapSoon()
    if pendingSnap then return end
    pendingSnap = true
    C_Timer.After(0.5, function()
        pendingSnap = nil
        if not (HUFDB and ns.db) then return end
        Bags.SnapshotBags()
        if bankOpen then Bags.SnapshotBank() end
        if Bags.frame and Bags.frame:IsShown() then Bags.Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Counting (tooltips)
---------------------------------------------------------------------------
local function CountIn(list, id)
    local n = 0
    if type(list) ~= "table" then return 0 end
    for _, b in ipairs(list) do
        for _, it in pairs(b.items or {}) do
            if it[3] == id then n = n + (it[2] or 1) end
        end
    end
    return n
end

local function CharLabel(key)
    local name = key:gsub("%-.*$", "")
    return ns.NameFromString and ns.NameFromString(name) or name
end
Bags.CharLabel = CharLabel

function Bags.Counts(id)
    local list = {}
    local mine = ns.CharKey()
    for key, d in pairs(Store()) do
        local bag, bank
        if key == mine then
            local ok, c = pcall(C_Item.GetItemCount, id, false)
            bag = ok and tonumber(c) or CountIn(d.bags, id)
            if bankOpen then
                local ok2, all = pcall(C_Item.GetItemCount, id, true)
                bank = ok2 and math.max(0, (tonumber(all) or 0) - bag) or CountIn(d.bank, id)
            else
                bank = CountIn(d.bank, id)
            end
        else
            bag, bank = CountIn(d.bags, id), CountIn(d.bank, id)
        end
        if bag > 0 or bank > 0 then
            list[#list + 1] = { key = key, class = d.class, bag = bag, bank = bank, me = key == mine }
        end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.bag + a.bank) > (b.bag + b.bank)
    end)
    return list
end

local function AddCounts(tt, data)
    if not (ns.db and S().tooltipCounts) then return end
    local id = data and data.id
    if IsSecret(id) or type(id) ~= "number" then return end
    if tt.hufCountsFor == id and tt.hufCountsDone then return end
    local list = Bags.Counts(id)
    if #list == 0 then return end
    tt:AddLine(" ")
    local tb, tk = 0, 0
    for _, e in ipairs(list) do
        local c = e.class and ns.ClassColor(e.class) or { r = 1, g = 1, b = 1 }
        tt:AddDoubleLine(CharLabel(e.key) .. ":", ("%d | %d"):format(e.bag, e.bank), c.r, c.g, c.b, 1, 1, 1)
        tb, tk = tb + e.bag, tk + e.bank
    end
    if #list > 1 then tt:AddDoubleLine("Total:", ("%d | %d"):format(tb, tk), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
    tt.hufCountsFor, tt.hufCountsDone = id, true
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        pcall(AddCounts, tt, data)
    end)
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then tt:HookScript("OnTooltipCleared", function(self) self.hufCountsFor, self.hufCountsDone = nil, nil end) end
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame
local live = {}               -- pool of the game's item buttons (each on its own bag-id parent)
local shows = {}              -- pool of display buttons (snapshots)
Bags.view = "BAGS"            -- BAGS | BANK
Bags.char = nil               -- nil: this character, else a character key
Bags.search = ""

local function Matches(link)
    local q = Bags.search
    if q == "" then return true end
    if type(link) ~= "string" or IsSecret(link) then return true end
    local name = link:match("%[(.-)%]")
    return name and name:lower():find(q, 1, true) ~= nil
end

local function SkinSlot(b, s)
    if not b.hufBg then
        b.hufBg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
        b.hufBg:SetAllPoints()
        b.hufEdge = ns.UI.Border(b, 0.15, 0.15, 0.17, 1)
    end
    b.hufBg:SetColorTexture(0.02, 0.02, 0.03, 0.85)
    b:SetSize(s.size, s.size)
    local icon = T(b.icon) or T(b.Icon)
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if T(b.NewItemTexture) then b.NewItemTexture:SetAlpha(0) end
    if T(b.BattlepayItemTexture) then b.BattlepayItemTexture:SetAlpha(0) end
    local count = T(b.Count) or (b.GetName and b:GetName() and _G[b:GetName() .. "Count"])
    if count then
        ns.ApplyFont(count, s.font, s.countSize, "OUTLINE")
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
end

-- quality edge: the slot's own border in the quality colour
local function QualityEdge(b, quality, s)
    if s.qualityBorders and quality and not IsSecret(quality) and quality >= 2 then
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if c then b.hufEdge:SetColor(c.r, c.g, c.b, 1) return end
    end
    b.hufEdge:SetColor(0.15, 0.15, 0.17, 1)
end

-- one game item button per slot of the pool
local function NewLive()
    if InCombatLockdown() then return nil end
    local parent = CreateFrame("Frame", nil, frame.grid)
    local b = CreateFrame("ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
    b:SetAllPoints(parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    if T(b.IconBorder) then b.IconBorder:SetAlpha(0) end
    b.hufParent = parent
    live[#live + 1] = b
    return b
end

local function NewShow()
    local b = CreateFrame("Button", nil, frame.grid)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.Count = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.Count, "GLOBAL", 12, "OUTLINE")
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end)
    shows[#shows + 1] = b
    return b
end

-- the game's buttons for the bags (made outside combat: enough for every slot)
function Bags.WarmPool()
    if not frame or InCombatLockdown() then return end
    local need = 0
    for _, bag in ipairs(BagIDs()) do need = need + NumSlots(bag) end
    for _ = #live + 1, need + 4 do NewLive() end
end

local function Place(b, i, s, cols)
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = s.padding + col * (s.size + s.spacing)
    local y = -(row * (s.size + s.spacing))
    local target = b.hufParent or b
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", frame.grid, "TOPLEFT", x, y)
    target:SetSize(s.size, s.size)
end

local function UpdateLive(b, bag, slot, s)
    b.hufParent:SetID(bag)
    b:SetID(slot)
    local info = ItemInfo(bag, slot)
    SetItemButtonTexture(b, info and info.iconFileID)
    SetItemButtonCount(b, info and info.stackCount or 0)
    SetItemButtonDesaturated(b, info and info.isLocked or false)
    if T(b.IconBorder) then b.IconBorder:SetAlpha(0) end
    QualityEdge(b, info and info.quality, s)
    local cd = T(b.Cooldown) or (b.GetName and b:GetName() and _G[b:GetName() .. "Cooldown"])
    if cd and C_Container.GetContainerItemCooldown then
        local ok, start, dur, enable = pcall(C_Container.GetContainerItemCooldown, bag, slot)
        if ok and CooldownFrame_Set then pcall(CooldownFrame_Set, cd, start, dur, enable) end
    end
    local link = info and info.hyperlink
    b:SetAlpha((not info or Matches(link)) and 1 or 0.2)
    b.hufParent:Show()
    b:Show()
end

local function UpdateShow(b, it, s)
    b.link = it and it[1]
    b.icon:SetTexture(it and (C_Item.GetItemIconByID and C_Item.GetItemIconByID(it[3]) or (GetItemIcon and GetItemIcon(it[3]))) or nil)
    b.Count:SetText(it and it[2] and it[2] > 1 and it[2] or "")
    local quality
    if it then
        local ok, _, _, q = pcall(C_Item.GetItemInfo, it[1])
        if ok then quality = q end
    end
    QualityEdge(b, quality, s)
    b:SetAlpha((not it or Matches(it[1])) and 1 or 0.2)
    b:Show()
end

local function Money(copper)
    copper = tonumber(copper) or 0
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function Bags.Refresh()
    if not frame or not frame:IsShown() then return end
    local s = S()
    local cols = math.max(1, s.cols)
    for _, b in ipairs(live) do b.hufParent:Hide() end
    for _, b in ipairs(shows) do b:Hide() end
    local mine = Bags.char == nil or Bags.char == ns.CharKey()
    local n, free, total = 0, 0, 0
    if mine and Bags.view == "BAGS" then
        -- live: the game's buttons
        for _, bag in ipairs(BagIDs()) do
            for slot = 1, NumSlots(bag) do
                total = total + 1
                local info = ItemInfo(bag, slot)
                if not info then free = free + 1 end
                if info or s.showEmpty then
                    n = n + 1
                    local b = live[n] or NewLive()
                    if not b then frame.short = true break end
                    SkinSlot(b, s)
                    Place(b, n, s, cols)
                    UpdateLive(b, bag, slot, s)
                end
            end
        end
        frame.money:SetText(Money(GetMoney and GetMoney() or 0))
    else
        local d = Store()[Bags.char or ns.CharKey()] or {}
        local list = Bags.view == "BANK" and d.bank or d.bags
        if not list then
            frame.empty:SetText(Bags.view == "BANK" and "Bank not seen yet: visit a banker with this character." or "Nothing saved for this character yet.")
            frame.empty:Show()
        else
            frame.empty:Hide()
            for _, bag in ipairs(list) do
                for slot = 1, bag.size or 0 do
                    total = total + 1
                    local it = bag.items and bag.items[slot]
                    if not it then free = free + 1 end
                    if it or s.showEmpty then
                        n = n + 1
                        local b = shows[n] or NewShow()
                        SkinSlot(b, s)
                        Place(b, n, s, cols)
                        UpdateShow(b, it, s)
                    end
                end
            end
        end
        frame.money:SetText(Money(d.money))
    end
    if mine and Bags.view == "BAGS" then frame.empty:Hide() end
    frame.free:SetText(("%d / %d"):format(total - free, total))
    -- size
    local rows = math.max(1, math.ceil(n / cols))
    local w = s.padding * 2 + cols * s.size + (cols - 1) * s.spacing
    local gridH = rows * s.size + (rows - 1) * s.spacing
    local searchH = frame.searchBox:IsShown() and SEARCH_H or 0
    frame.grid:ClearAllPoints()
    frame.grid:SetPoint("TOPLEFT", 0, -(HEADER_H + searchH))
    frame.grid:SetSize(w, gridH)
    frame:SetSize(math.max(w, 220), HEADER_H + searchH + gridH + s.padding + FOOTER_H)
    Bags.UpdateHeader()
end

-- header texts: which character and view
function Bags.UpdateHeader()
    local key = Bags.char or ns.CharKey()
    frame.charText:SetText(CharLabel(key))
    frame.viewText:SetText(Bags.view == "BANK" and "Bank" or "Bags")
end

local function Look()
    local s = S()
    frame:SetScale(s.scale)
    frame.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    frame.edge:SetColor(c.r, c.g, c.b, s.borderSize > 0 and 1 or 0)
    frame:ClearAllPoints()
    frame:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
end

local function Dropdown(parent, w, get, choices, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 18)
    ns.UI.Fill(b, 0.09, 0.09, 0.10, 1)
    ns.UI.Border(b, 0.25, 0.25, 0.27, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -14, 0)
    b.text:SetJustifyH("LEFT")
    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("v")
    b:SetScript("OnClick", function(self)
        ns.UI.OpenList(self, choices(), get(), function(v) set(v) end)
    end)
    return b
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "HUF_Bags", UIParent)
    Bags.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bg:SetAllPoints()
    frame.edge = ns.UI.Border(frame, A[1], A[2], A[3], 1)
    if UISpecialFrames then table.insert(UISpecialFrames, "HUF_Bags") end

    -- header: drag to move
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEADER_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function()
        frame.from = { frame:GetLeft(), frame:GetTop() }
        frame:StartMoving()
    end)
    head:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        local from = frame.from
        if not from then return end
        frame.from = nil
        local p = S().point
        p[3] = math.floor((p[3] or 0) + (frame:GetLeft() or 0) - (from[1] or 0) + 0.5)
        p[4] = math.floor((p[4] or 0) + (frame:GetTop() or 0) - (from[2] or 0) + 0.5)
        Look()
    end)

    -- character and view dropdowns
    frame.charDD = Dropdown(head, 110, function() return Bags.char or ns.CharKey() end, function()
        local l = {}
        local keys = {}
        for k in pairs(Store()) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if a == ns.CharKey() then return true end
            if b == ns.CharKey() then return false end
            return a < b
        end)
        for _, k in ipairs(keys) do l[#l + 1] = { value = k, text = CharLabel(k) } end
        return l
    end, function(v)
        Bags.char = (v ~= ns.CharKey()) and v or nil
        Bags.Refresh()
    end)
    frame.charDD:SetPoint("LEFT", head, "LEFT", 6, 0)
    frame.charText = frame.charDD.text
    frame.viewDD = Dropdown(head, 64, function() return Bags.view end, function()
        return { { value = "BAGS", text = "Bags" }, { value = "BANK", text = "Bank" } }
    end, function(v) Bags.view = v Bags.Refresh() end)
    frame.viewDD:SetPoint("LEFT", frame.charDD, "RIGHT", 4, 0)
    frame.viewText = frame.viewDD.text

    local close = CreateFrame("Button", nil, head)
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER")
    x:SetText("x")
    close:SetScript("OnClick", function() Bags.Hide() end)

    -- search icon and bar
    local sb = CreateFrame("Button", nil, head)
    sb:SetSize(18, 18)
    sb:SetPoint("RIGHT", close, "LEFT", -4, 0)
    sb.icon = sb:CreateTexture(nil, "ARTWORK")
    sb.icon:SetAllPoints()
    if not (sb.icon.SetAtlas and pcall(sb.icon.SetAtlas, sb.icon, "common-search-magnifyingglass")) then
        sb.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    end
    local box = ns.UI.EditBox(frame, 200, "Search items", function(_, self) self:ClearFocus() end)
    box:SetPoint("TOPLEFT", 6, -(HEADER_H + 1))
    box:SetPoint("TOPRIGHT", -6, -(HEADER_H + 1))
    box:Hide()
    box:HookScript("OnTextChanged", function(self)
        Bags.search = (self:GetText() or ""):lower()
        Bags.Refresh()
    end)
    frame.searchBox = box
    sb:SetScript("OnClick", function()
        if box:IsShown() then
            box:SetText("")
            box:ClearFocus()
            box:Hide()
            Bags.search = ""
        else
            box:Show()
            box:SetFocus()
        end
        Bags.Refresh()
    end)
    sb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Search")
        GameTooltip:Show()
    end)
    sb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.grid = CreateFrame("Frame", nil, frame)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOP", frame.grid, "TOP", 0, -10)
    frame.empty:Hide()

    -- footer: money and used / all slots
    frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.money:SetPoint("BOTTOMRIGHT", -8, 5)
    frame.free = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.free:SetPoint("BOTTOMLEFT", 8, 5)
    Look()
end

function Bags.Show()
    if not S().enabled then return end
    Build()
    Look()
    frame:Show()
    Bags.Refresh()
end
function Bags.Hide()
    if frame then frame:Hide() end
end
function Bags.Toggle()
    Build()
    if frame:IsShown() then Bags.Hide() else Bags.Show() end
end

---------------------------------------------------------------------------
-- Taking over the bag keys (as EllesmereUI: ToggleAllBags replaced, the rest
-- hooked, Blizzard's bag frames parked under a hidden parent)
---------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()
local function KillBlizzard()
    local KEYRING = Enum and Enum.BagIndex and Enum.BagIndex.Keyring
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f and not (KEYRING and f:IsShown() and f.MatchesBagID and f:MatchesBagID(KEYRING)) then f:SetParent(hidden) end
    end
    if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetParent(hidden) end
end

local lastToggle = 0
local function Takeover()
    if Bags.took then return end
    Bags.took = true
    local function Toggle()
        if GetTime() == lastToggle then return end
        lastToggle = GetTime()
        Bags.Toggle()
    end
    ToggleAllBags = Toggle
    hooksecurefunc("ToggleBackpack", function() Toggle() KillBlizzard() end)
    hooksecurefunc("OpenAllBags", function() Bags.Show() KillBlizzard() end)
    if OpenBackpack then hooksecurefunc("OpenBackpack", function() Bags.Show() KillBlizzard() end) end
    hooksecurefunc("CloseAllBags", function() Bags.Hide() end)
    if CloseBackpack then hooksecurefunc("CloseBackpack", function() Bags.Hide() end) end
    hooksecurefunc("ToggleBag", function(id)
        local KEYRING = Enum and Enum.BagIndex and Enum.BagIndex.Keyring
        if KEYRING and id == KEYRING then return end
        Toggle()
        KillBlizzard()
    end)
    KillBlizzard()
end

-- the game's "combined bags" option (one bag)
local function OneBag()
    local s = S()
    if not s.oneBag then return end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, v = pcall(get, "combinedBags")
    if ok and v ~= nil and v ~= "1" then pcall(set, "combinedBags", "1") end
end

function Bags.Apply()
    if not (HUFDB and ns.db) then return end
    OneBag()
    if S().enabled then
        Build()
        Takeover()
        Look()
        Bags.WarmPool()
        if frame:IsShown() then Bags.Refresh() end
    elseif frame then
        frame:Hide()
    end
end

function Bags.Report(add)
    local s = S()
    local n = 0
    for _ in pairs(Store()) do n = n + 1 end
    local me = Store()[ns.CharKey()] or {}
    add(("bags: enabled=%s oneBag=%s pool=%d characters=%d bank seen=%s view=%s bags=%s bank=%s"):format(
        tostring(s.enabled), tostring(s.oneBag), #live, n, tostring(me.bank ~= nil), Bags.view,
        table.concat(BagIDs(), ","), table.concat(BankIDs(), ",")))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.OnLogin(function()
    Bags.Apply()
    Bags.SnapshotBags()
end)
ns.OnRefresh(function() if HUFDB and ns.db then Bags.Apply() end end)
ns.On("BAG_UPDATE_DELAYED", function() SnapSoon() end)
ns.On("ITEM_LOCK_CHANGED", function() if frame and frame:IsShown() then Bags.Refresh() end end)
ns.On("BAG_UPDATE_COOLDOWN", function() if frame and frame:IsShown() then Bags.Refresh() end end)
ns.On("PLAYER_MONEY", function() if HUFDB and ns.db then Me().money = GetMoney() if frame and frame:IsShown() then Bags.Refresh() end end end)
ns.On("BANKFRAME_OPENED", function()
    bankOpen = true
    if not (HUFDB and ns.db) then return end
    C_Timer.After(0.3, function() Bags.SnapshotBank() if frame and frame:IsShown() then Bags.Refresh() end end)
    if S().enabled and S().openWithBank then Bags.Show() end
end)
ns.On("BANKFRAME_CLOSED", function()
    if bankOpen and HUFDB and ns.db then Bags.SnapshotBank() end
    bankOpen = false
end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() SnapSoon() end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if frame and frame.short then frame.short = nil Bags.WarmPool() Bags.Refresh() end
end)
ns.On("PLAYER_LOGOUT", function()
    if HUFDB and ns.db then pcall(Bags.SnapshotBags) end
end)
-- the game's merchant / mail / trade windows open the bags
for _, e in ipairs({ "MERCHANT_SHOW", "MAIL_SHOW", "TRADE_SHOW", "AUCTION_HOUSE_SHOW" }) do
    ns.On(e, function() if HUFDB and ns.db and S().enabled then Bags.Show() end end)
end
