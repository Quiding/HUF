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
    -- never one of the bags (a client whose bank ids overlap the bag ids)
    local bags = {}
    for _, b in ipairs(BagIDs()) do bags[b] = true end
    local out = {}
    for _, b in ipairs(l) do if not bags[b] then out[#out + 1] = b end end
    return out
end

-- the keyring (classic bag id -2), if the client has one
local function KeyringID()
    local BI = Enum and Enum.BagIndex
    return (BI and BI.Keyring) or KEYRING_CONTAINER
end
Bags.KeyringID = KeyringID

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

-- the reagent bag (Forever's own bag slot) or any bag that only takes some items
-- (a bag family other than 0)
local function IsReagentBag(bag)
    local BI = Enum and Enum.BagIndex
    if BI and BI.ReagentBag and bag == BI.ReagentBag then return true end
    if bag == 0 or not (C_Container and C_Container.GetContainerNumFreeSlots) then return false end
    local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
    return ok and type(family) == "number" and family ~= 0 or false
end
Bags.IsReagentBag = IsReagentBag

local function ReadContainers(ids)
    local out = {}
    for _, bag in ipairs(ids) do
        local n = NumSlots(bag)
        local b = { bag = bag, size = n, items = {}, reagent = IsReagentBag(bag) or nil }
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
    local kr = KeyringID()
    if kr and NumSlots(kr) > 0 then me.keys = ReadContainers({ kr }) end
    me.time = time()
end

-- holds anything: at least one slot
local function HasSlots(list)
    if type(list) ~= "table" then return false end
    for _, b in ipairs(list) do if (b.size or 0) > 0 then return true end end
    return false
end

function Bags.SnapshotBank()
    local list = ReadContainers(BankIDs())
    if not HasSlots(list) then return end
    local me = Me()
    me.bank = list
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

local function SkinSlot(b, s, reagent)
    if not b.hufBg then
        b.hufBg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
        b.hufBg:SetAllPoints()
        b.hufEdge = ns.UI.Border(b, 0.15, 0.15, 0.17, 1)
    end
    b.hufReagent = reagent and s.reagentTint or nil
    if b.hufReagent then
        local c = s.reagentColor
        b.hufBg:SetColorTexture(c.r, c.g, c.b, 0.9)
    else
        b.hufBg:SetColorTexture(0.02, 0.02, 0.03, 0.85)
    end
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
    local kr = KeyringID()
    if kr then need = math.max(need, NumSlots(kr)) end
    for _ = #live + 1, need + 4 do NewLive() end
end

local function Place(b, i, s, cols, grid)
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = s.padding + col * (s.size + s.spacing)
    local y = -(row * (s.size + s.spacing))
    local target = b.hufParent or b
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", grid or frame.grid, "TOPLEFT", x, y)
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

-- money with the coin icons ("12,345 [g] 6 [s] 7 [c]"); parts that are 0 left out
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) .. COIN:format("Gold") end
    if sv > 0 then parts[#parts + 1] = sv .. COIN:format("Silver") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COIN:format("Copper") end
    return table.concat(parts, " ")
end
Bags.Money = Money

-- tooltip over the money: every character's gold
local function MoneyTooltip(owner)
    local list, total = {}, 0
    local me = ns.CharKey()
    for key, d in pairs(Store()) do
        local m = key == me and (GetMoney and GetMoney()) or d.money
        m = tonumber(m)
        if m then list[#list + 1] = { key = key, class = d.class, money = m, me = key == me } end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return a.money > b.money
    end)
    GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Gold")
    for _, e in ipairs(list) do
        local c = e.class and ns.ClassColor(e.class) or { r = 1, g = 1, b = 1 }
        GameTooltip:AddDoubleLine(CharLabel(e.key), Money(e.money), c.r, c.g, c.b, 1, 1, 1)
        total = total + e.money
    end
    if #list > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total", Money(total), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:Show()
end
Bags.MoneyTooltip = MoneyTooltip

-- the game's own sort (server side, the one Blizzard's bag button uses)
local function SortFn()
    if Bags.view == "KEYS" then return nil end
    local CC = C_Container
    if Bags.view == "BANK" then
        if not (bankOpen and (Bags.char == nil or Bags.char == ns.CharKey())) then return nil end
        if CC and CC.SortBank and Enum and Enum.BankType and Enum.BankType.Character then
            return function() CC.SortBank(Enum.BankType.Character) end
        end
        return (CC and CC.SortBankBags) or SortBankBags
    end
    if Bags.char ~= nil and Bags.char ~= ns.CharKey() then return nil end
    return (CC and CC.SortBags) or SortBags
end
function Bags.Sort()
    local fn = SortFn()
    if not fn then return end
    if InCombatLockdown() then ns.Print("Bags can't be sorted in combat.") return end
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then pcall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01) end
    local ok, err = pcall(fn)
    if not ok then ns.Log("bags", "sort failed: %s", tostring(err)) end
end

function Bags.Refresh()
    if not frame or not frame:IsShown() then return end
    local s = S()
    local cols = math.max(1, s.cols)
    for _, b in ipairs(live) do b.hufParent:Hide() end
    for _, b in ipairs(shows) do b:Hide() end
    local mine = Bags.char == nil or Bags.char == ns.CharKey()
    local sep = s.reagentSeparate
    -- every slot to show: { bag, slot, it (snapshot) / live, reagent }
    local main, rea = {}, {}
    local cnt = { main = { 0, 0 }, rea = { 0, 0 } }     -- used, all
    local function Add(e, used)
        local c = (e.reagent and sep) and cnt.rea or cnt.main
        c[2] = c[2] + 1
        if used then c[1] = c[1] + 1 end
        if used or s.showEmpty then
            local l = (e.reagent and sep) and rea or main
            l[#l + 1] = e
        end
    end
    local keys = Bags.view == "KEYS"
    local isLive = mine and (Bags.view == "BAGS" or (keys and KeyringID() ~= nil and NumSlots(KeyringID()) > 0))
    if isLive then
        for _, bag in ipairs(keys and { KeyringID() } or BagIDs()) do
            local r = IsReagentBag(bag)
            for slot = 1, NumSlots(bag) do
                Add({ bag = bag, slot = slot, reagent = r }, ItemInfo(bag, slot) ~= nil)
            end
        end
        frame.money:SetText(Money(GetMoney and GetMoney() or 0))
        frame.empty:Hide()
    else
        local d = Store()[Bags.char or ns.CharKey()] or {}
        local list
        if Bags.view == "BANK" then list = d.bank elseif keys then list = d.keys else list = d.bags end
        local RB = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
        if not HasSlots(list) then
            frame.empty:SetText(Bags.view == "BANK" and "No bank data yet: visit a banker with this character."
                or keys and "No keyring saved for this character yet." or "Nothing saved for this character yet.")
            frame.empty:Show()
        else
            frame.empty:Hide()
            for _, bag in ipairs(list) do
                local r = bag.reagent or (Bags.view == "BAGS" and RB ~= nil and bag.bag == RB) or false
                for slot = 1, bag.size or 0 do
                    local it = bag.items and bag.items[slot]
                    Add({ it = it, reagent = r }, it ~= nil)
                end
            end
        end
        frame.money:SetText(Money(d.money))
    end
    -- draw
    local n = 0
    local function Draw(list, grid, c)
        for i, e in ipairs(list) do
            if isLive then
                n = n + 1
                local b = live[n] or NewLive()
                if not b then frame.short = true return end
                SkinSlot(b, s, e.reagent)
                Place(b, i, s, c, grid)
                UpdateLive(b, e.bag, e.slot, s)
            else
                n = n + 1
                local b = shows[n] or NewShow()
                SkinSlot(b, s, e.reagent)
                Place(b, i, s, c, grid)
                UpdateShow(b, e.it, s)
            end
        end
    end
    Draw(main, frame.grid, cols)
    frame.free:SetText(("%d / %d"):format(cnt.main[1], cnt.main[2]))
    -- size
    local rows = math.max(1, math.ceil(#main / cols))
    local w = s.padding * 2 + cols * s.size + (cols - 1) * s.spacing
    local gridH = rows * s.size + (rows - 1) * s.spacing
    local searchH = frame.searchBox:IsShown() and SEARCH_H or 0
    frame.grid:ClearAllPoints()
    frame.grid:SetPoint("TOPLEFT", 0, -(HEADER_H + searchH))
    frame.grid:SetSize(w, gridH)
    frame:SetSize(math.max(w, 260), HEADER_H + searchH + gridH + s.padding + FOOTER_H)
    -- the reagent bag beside the window
    local rp = frame.reagent
    if sep and cnt.rea[2] > 0 then
        local rc = math.max(1, s.reagentCols)
        Draw(rea, rp.grid, rc)
        local rrows = math.max(1, math.ceil(#rea / rc))
        local rw = s.padding * 2 + rc * s.size + (rc - 1) * s.spacing
        local rh = rrows * s.size + (rrows - 1) * s.spacing
        rp.grid:SetSize(rw, rh)
        rp:SetSize(math.max(rw, 90), HEADER_H + rh + s.padding + FOOTER_H)
        rp:ClearAllPoints()
        if s.reagentSide == "RIGHT" then
            rp:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
        else
            rp:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
        end
        rp.free:SetText(("%d / %d"):format(cnt.rea[1], cnt.rea[2]))
        rp:Show()
    else
        rp:Hide()
    end
    Bags.UpdateHeader()
end

-- header texts: which character and view
function Bags.UpdateHeader()
    local key = Bags.char or ns.CharKey()
    frame.charText:SetText(CharLabel(key))
    frame.viewText:SetText(Bags.view == "BANK" and "Bank" or Bags.view == "KEYS" and "Keyring" or "Bags")
    if frame.sortButton then
        frame.sortButton:SetShown(S().sortButton ~= false)
        local can = SortFn() ~= nil
        frame.sortButton.icon:SetDesaturated(not can)
        frame.sortButton:SetAlpha(can and 1 or 0.4)
    end
end

local function Look()
    local s = S()
    frame:SetScale(s.scale)
    frame.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    frame.edge:SetColor(c.r, c.g, c.b, s.borderSize > 0 and 1 or 0)
    if frame.reagent then
        frame.reagent.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
        frame.reagent.edge:SetColor(c.r, c.g, c.b, s.borderSize > 0 and 1 or 0)
    end
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
    frame.viewDD = Dropdown(head, 72, function() return Bags.view end, function()
        local l = { { value = "BAGS", text = "Bags" }, { value = "BANK", text = "Bank" } }
        local kr = KeyringID()
        local d = Store()[Bags.char or ns.CharKey()]
        if kr and (NumSlots(kr) > 0 or (d and d.keys)) then l[#l + 1] = { value = "KEYS", text = "Keyring" } end
        return l
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

    -- sort: the game's own sort
    local so = CreateFrame("Button", nil, head)
    so:SetSize(18, 18)
    so:SetPoint("RIGHT", sb, "LEFT", -4, 0)
    so.icon = so:CreateTexture(nil, "ARTWORK")
    so.icon:SetAllPoints()
    if not (so.icon.SetAtlas and pcall(so.icon.SetAtlas, so.icon, "bags-button-autosort-up")) then
        so.icon:SetTexture("Interface\\Icons\\INV_Pet_Broom")
        so.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    so:SetScript("OnClick", function() Bags.Sort() end)
    so:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Bags.view == "BANK" and "Sort the bank" or "Sort the bags")
        if not SortFn() then GameTooltip:AddLine(Bags.view == "BANK" and "Only while you're at the bank." or Bags.view == "KEYS" and "Not the keyring." or "Only your own bags.", 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    so:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.sortButton = so

    frame.grid = CreateFrame("Frame", nil, frame)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOP", frame.grid, "TOP", 0, -10)
    frame.empty:Hide()

    -- footer: money and used / all slots
    frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.money:SetPoint("BOTTOMRIGHT", -8, 5)
    local mh = CreateFrame("Frame", nil, frame)
    mh:SetPoint("TOPLEFT", frame.money, "TOPLEFT", -2, 2)
    mh:SetPoint("BOTTOMRIGHT", frame.money, "BOTTOMRIGHT", 2, -2)
    mh:EnableMouse(true)
    mh:SetScript("OnEnter", function(self) MoneyTooltip(self) end)
    mh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.moneyHover = mh
    frame.free = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.free:SetPoint("BOTTOMLEFT", 8, 5)

    -- the reagent bag on its own, beside the window (option)
    local rp = CreateFrame("Frame", nil, frame)
    rp:EnableMouse(true)
    rp:Hide()
    rp.bg = rp:CreateTexture(nil, "BACKGROUND", nil, -8)
    rp.bg:SetAllPoints()
    rp.edge = ns.UI.Border(rp, A[1], A[2], A[3], 1)
    rp.title = rp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rp.title:SetPoint("TOPLEFT", 8, -7)
    rp.title:SetText("Reagents")
    rp.grid = CreateFrame("Frame", nil, rp)
    rp.grid:SetPoint("TOPLEFT", 0, -HEADER_H)
    rp.free = rp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rp.free:SetPoint("BOTTOMLEFT", 8, 5)
    frame.reagent = rp
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
    local kr = KeyringID()
    local rb = {}
    for _, b in ipairs(BagIDs()) do if IsReagentBag(b) then rb[#rb + 1] = b end end
    add(("bags: enabled=%s oneBag=%s pool=%d characters=%d bank seen=%s view=%s bags=%s bank=%s keyring=%s (%d slots) reagent bags=%s separate=%s"):format(
        tostring(s.enabled), tostring(s.oneBag), #live, n, tostring(me.bank ~= nil), Bags.view,
        table.concat(BagIDs(), ","), table.concat(BankIDs(), ","), tostring(kr), kr and NumSlots(kr) or 0,
        table.concat(rb, ","), tostring(s.reagentSeparate)))
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
    if frame and frame:IsShown() then Bags.UpdateHeader() end
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
