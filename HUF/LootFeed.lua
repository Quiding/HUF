-- HUF: Loot Feed and Faster Looting (General > Loot Feed).
-- Loot Feed: a short stack of rows for what you gain (items, money,
-- reputation, currencies, skill ups). Each row fades out after a few seconds;
-- the same thing again adds to its row instead of opening another. The game's
-- own chat lines are read with its localized format strings, so every client
-- language works.
-- Faster Looting: every slot is taken the moment the loot window opens;
-- Shift held while looting shows the normal window.

local _, ns = ...
local UI = ns.UI

local LF = {}
ns.LootFeed = LF

local FADE_IN, FADE_OUT = 0.2, 0.6
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"
local CURRENCY_ICON = "Interface\\Icons\\INV_Misc_Token_ArgentDawn"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- accent colours of rows without an item quality
local COLORS = {
    money = { 1.00, 0.82, 0.00 },
    rep = { 0.30, 0.85, 0.30 },
    skill = { 0.35, 0.65, 1.00 },
    currency = { 1.00, 1.00, 1.00 },
}

local function Cfg() return ns.db.lootFeed end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Money(copper)
    if ns.Bags and ns.Bags.Money then return ns.Bags.Money(copper) end
    return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end

-- Auctionator's price of its last scan (nil: not installed, never seen)
local function AuctionPrice(link)
    local api = type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, "HUF", link)
    if ok and type(price) == "number" and price > 0 then return price end
end
LF.HasAuctionator = function()
    return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1 and true or false
end

---------------------------------------------------------------------------
-- Chat line matching: a Blizzard format string as a Lua pattern
---------------------------------------------------------------------------
local compiled = {}
local function Compile(fmt, anchored)
    local parts, i, first = {}, 1, nil
    while true do
        local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        first = first or tonumber(pos)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and ("^" .. p .. "$") or p, swap = first == 2 }
end
local function Match(key, text, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then return end
    local a, b = text:match(c.pat)
    if c.swap then return b, a end
    return a, b
end

---------------------------------------------------------------------------
-- The feed frame and its rows
---------------------------------------------------------------------------
local anchor
local active, pool = {}, {}

local function Accent(r, g, b)
    local c = Cfg()
    if c.accentQuality then return r, g, b end
    local a = c.accentColor or { r = 1, g = 1, b = 1 }
    return a.r, a.g, a.b
end

local function StyleRow(row)
    local c = Cfg()
    local w, h = c.width, c.height
    row:SetSize(w, h)
    row.bg:SetColorTexture(0.05, 0.05, 0.06, c.bgAlpha or 0.6)
    local size, pos = math.max(1, c.accentSize or 3), c.accentPos or "LEFT"
    local bar = row.bar
    bar:ClearAllPoints()
    local padL, padR = 0, 0
    if pos == "RIGHT" then
        bar:SetPoint("TOPRIGHT") bar:SetPoint("BOTTOMRIGHT") bar:SetWidth(size)
        padR = size
    elseif pos == "TOP" then
        bar:SetPoint("TOPLEFT") bar:SetPoint("TOPRIGHT") bar:SetHeight(size)
    elseif pos == "BOTTOM" then
        bar:SetPoint("BOTTOMLEFT") bar:SetPoint("BOTTOMRIGHT") bar:SetHeight(size)
    else
        bar:SetPoint("TOPLEFT") bar:SetPoint("BOTTOMLEFT") bar:SetWidth(size)
        padL = size
    end
    local isz = math.max(8, h - 8)
    row.icon:SetSize(isz, isz)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", padL + 4, 0)
    ns.ApplyFont(row.text, c.font, c.fontSize, c.outline)
    ns.ApplyFont(row.value, c.font, math.max(6, c.fontSize - 1), c.outline)
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -(padR + 6), 0)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    local r, g, b = Accent(row.r or 1, row.g or 1, row.b or 1)
    bar:SetColorTexture(r, g, b, 1)
end

local function NewRow()
    local row = table.remove(pool)
    if row then return row end
    row = CreateFrame("Frame", nil, anchor)
    row:EnableMouse(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetJustifyH("RIGHT")
    row.value:SetSpacing(1)
    return row
end

local function Layout()
    local c = Cfg()
    local gap = c.spacing or 2
    for i, row in ipairs(active) do
        row:ClearAllPoints()
        local off = (i - 1) * (c.height + gap)
        if c.grow == "DOWN" then
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -off)
        else
            row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, off)
        end
    end
end

local function Release(i)
    local row = table.remove(active, i)
    row:Hide()
    row.key, row.data = nil, nil
    pool[#pool + 1] = row
end

local function Draw(row)
    local d = row.data
    row.icon:SetTexture(d.icon or UNKNOWN_ICON)
    local text = d.text
    if (d.count or 1) > 1 then text = d.count .. "x " .. text end
    row.text:SetText(text)
    row.value:SetText(d.value and d.value(d.count or 1) or "")
end

local function OnUpdate()
    local now, removed = GetTime(), false
    for i = #active, 1, -1 do
        local row = active[i]
        local left = row.expire - now
        if left <= 0 then
            local a = 1 + left / FADE_OUT
            if a <= 0 then Release(i) removed = true else row:SetAlpha(a) end
        else
            row:SetAlpha(math.min(1, (now - row.born) / FADE_IN))
        end
    end
    if #active == 0 then anchor:SetScript("OnUpdate", nil) elseif removed then Layout() end
end

-- a gain: key groups repeats, data = { icon, text, r, g, b, count, value(count) }
local function Push(key, data)
    local c = Cfg()
    if not (c.enabled and anchor) then return end
    local now = GetTime()
    for i, row in ipairs(active) do
        if row.key == key then
            row.data.count = (row.data.count or 1) + (data.count or 1)
            table.remove(active, i)
            table.insert(active, 1, row)
            row.expire = now + c.duration
            row:SetAlpha(1)
            Draw(row)
            Layout()
            return
        end
    end
    while #active >= math.max(1, c.maxRows) do Release(#active) end
    local row = NewRow()
    row.key, row.data = key, data
    row.r, row.g, row.b = data.r, data.g, data.b
    StyleRow(row)
    Draw(row)
    row.born, row.expire = now, now + c.duration
    row:SetAlpha(0)
    row:Show()
    table.insert(active, 1, row)
    Layout()
    anchor:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local function ShowItem(link, count, retried)
    if not GetItemInfo then return end
    local name, _, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfo(link)
    if not name then
        -- not cached yet: once more when the client has it
        if not retried and Item and Item.CreateFromItemLink then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function() ShowItem(link, count, true) end)
        end
        return
    end
    local c = Cfg()
    if (quality or 0) < (c.minQuality or 0) then return end
    local r, g, b = QualityColor(quality)
    local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    Push("item:" .. name, {
        icon = icon, text = hex .. name .. "|r", r = r, g = g, b = b, count = count,
        value = function(n)
            local lines = {}
            if c.vendorPrice and (sellPrice or 0) > 0 then lines[#lines + 1] = Money(sellPrice * n) end
            if c.auctionPrice then
                local ah = AuctionPrice(link)
                if ah then lines[#lines + 1] = "|cff9d9d9dAH|r " .. Money(ah * n) end
            end
            return table.concat(lines, "\n")
        end,
    })
end

-- own loot only; the multiple formats (link and count) first: the single
-- ones match their lines too
local ITEM_KEYS = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF",
}
local function OnLoot(text)
    for _, key in ipairs(ITEM_KEYS) do
        local item, count = Match(key, text)
        if item then
            local link = item:match("|H(item:[^|]+)|h")
            if not link then
                -- some lines (fishing, crafting) carry a plain [Name]
                local nm = item:match("^%[(.-)%]$")
                local id = nm and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(nm)
                link = id and ("item:" .. id)
            end
            if link then ShowItem(link, tonumber(count) or 1) end
            return
        end
    end
end

local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
local function ShowMoney(copper)
    local col = COLORS.money
    Push("money", {
        icon = MONEY_ICON, text = MONEY or "Money", r = col[1], g = col[2], b = col[3], count = 1, amount = copper,
        value = function() return "" end,
    })
    -- money adds up its copper, not a count
    for _, row in ipairs(active) do
        if row.key == "money" then
            local d = row.data
            d.total = (d.total or 0) + copper
            d.count = 1
            local total = d.total
            d.value = function() return Money(total) end
            Draw(row)
        end
    end
end
local function OnMoney(text)
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local n = Match(key, text, true)
        if n then copper = copper + tonumber(n) * mult end
    end
    if copper > 0 then ShowMoney(copper) end
end

local function ShowReputation(faction, delta)
    local col = COLORS.rep
    local key = "rep:" .. faction
    local total = delta
    for _, row in ipairs(active) do
        if row.key == key then total = (row.data.total or 0) + delta end
    end
    Push(key, { icon = REP_ICON, text = faction, r = col[1], g = col[2], b = col[3], count = 1, value = function() return "" end })
    for _, row in ipairs(active) do
        if row.key == key then
            row.data.total, row.data.count = total, 1
            row.data.value = function()
                return (total >= 0 and "|cff40ff40+" or "|cffff4040") .. total .. "|r"
            end
            Draw(row)
        end
    end
end
local REP_UP = { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_BONUS",
                 "FACTION_STANDING_INCREASED_ACH_BONUS", "FACTION_STANDING_INCREASED" }
local function OnFaction(text)
    for _, key in ipairs(REP_UP) do
        local faction, amount = Match(key, text, true)
        if faction and tonumber(amount) then return ShowReputation(faction, tonumber(amount)) end
    end
    local faction, amount = Match("FACTION_STANDING_DECREASED", text, true)
    if faction and tonumber(amount) then ShowReputation(faction, -tonumber(amount)) end
end

local function OnCurrency(text)
    for _, key in ipairs({ "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }) do
        local cur, count = Match(key, text)
        if cur then
            local id = tonumber(cur:match("currency:(%d+)"))
            local name, icon, quality = cur:match("%[(.-)%]"), CURRENCY_ICON, nil
            local info = id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
            if type(info) == "table" then
                name = info.name or name
                icon = info.iconFileID or icon
                quality = info.quality
            end
            if not name then return end
            local r, g, b = 1, 1, 1
            if quality then r, g, b = QualityColor(quality) end
            Push("cur:" .. name, { icon = icon, text = name, r = r, g = g, b = b, count = tonumber(count) or 1 })
            return
        end
    end
end

local function OnSkill(text)
    local skill, rank = Match("ERR_SKILL_UP_SI", text)
    if not skill then return end
    local col = COLORS.skill
    Push("skill:" .. skill, {
        icon = SKILL_ICON, text = skill, r = col[1], g = col[2], b = col[3], count = 1,
        value = function() return "|cffffffff" .. tostring(rank) .. "|r" end,
    })
    for _, row in ipairs(active) do
        if row.key == "skill:" .. skill then
            row.data.count = 1
            row.data.value = function() return "|cffffffff" .. tostring(rank) .. "|r" end
            Draw(row)
        end
    end
end

local CHAT = {
    CHAT_MSG_LOOT = { "items", OnLoot },
    CHAT_MSG_MONEY = { "money", OnMoney },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { "reputation", OnFaction },
    CHAT_MSG_CURRENCY = { "currency", OnCurrency },
    CHAT_MSG_SKILL = { "skills", OnSkill },
}

---------------------------------------------------------------------------
-- Faster Looting
---------------------------------------------------------------------------
local lastLoot = 0
-- master loot: is it on (any looter); taking such a slot as the master looter
-- opens the game's assign / roll menu, so those slots stay in the window
local function MasterLoot()
    local m
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, v = pcall(C_PartyInfo.GetLootMethod)
        if ok then m = v end
        if Enum and Enum.LootMethod and m ~= nil then
            return m == (Enum.LootMethod.Masterlooter or Enum.LootMethod.MasterLooter)
        end
    end
    if GetLootMethod then
        local ok, v = pcall(GetLootMethod)
        if ok then return v == "master" end
    end
    return false
end

local function FastLoot()
    if IsShiftKeyDown() then return end
    local now = GetTime()
    if now - lastLoot < 0.3 then return end
    lastLoot = now
    local master = MasterLoot()
    local threshold = master and GetLootThreshold and GetLootThreshold() or nil
    local n = GetNumLootItems() or 0
    for i = n, 1, -1 do
        local _, _, _, _, quality, locked = GetLootSlotInfo(i)
        -- under master loot, items at or above the threshold wait for the
        -- master looter's choice (unknown quality counts as "wait")
        local held = master and (type(quality) ~= "number" or not threshold or quality >= threshold)
        local coin = GetLootSlotType and Enum and Enum.LootSlotType and GetLootSlotType(i) == Enum.LootSlotType.Money
        if not locked and (coin or not held) then LootSlot(i) end
    end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, text)
    if event == "LOOT_READY" then
        FastLoot()
        return
    end
    local h = CHAT[event]
    if h and type(text) == "string" and not ns.IsSecret(text) then
        local ok, err = pcall(h[2], text)
        if not ok then ns.LogError("lootfeed", err) end
    end
end)

function LF.Frame() return anchor end

function LF.Place()
    if not anchor then return end
    local c = Cfg()
    local p = c.point
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    local rows = math.max(1, c.maxRows)
    anchor:SetSize(c.width, rows * c.height + (rows - 1) * (c.spacing or 2))
end

function LF.Apply()
    if not ns.db then return end
    local c = Cfg()
    events:UnregisterAllEvents()
    if c.fastLoot then events:RegisterEvent("LOOT_READY") end
    if c.enabled then
        if not anchor then
            anchor = CreateFrame("Frame", "HUF_LootFeed", UIParent)
            anchor:SetFrameStrata("MEDIUM")
            anchor:EnableMouse(false)
        end
        LF.Place()
        anchor:Show()
        local src = c.sources or {}
        for ev, h in pairs(CHAT) do
            if src[h[1]] ~= false then events:RegisterEvent(ev) end
        end
        for _, row in ipairs(active) do StyleRow(row) end
        while #active > math.max(1, c.maxRows) do Release(#active) end
        Layout()
    elseif anchor then
        for i = #active, 1, -1 do Release(i) end
        anchor:Hide()
    end
end

-- a few made-up rows to look at the style
local SAMPLES = {
    { key = "item", icon = "Interface\\Icons\\INV_Fabric_Linen_01", name = "Linen Cloth", q = 1, count = 4, sell = 13, ah = 180 },
    { key = "money", copper = 23456 },
    { key = "item", icon = "Interface\\Icons\\INV_Sword_04", name = "Sample Blade", q = 2, count = 1, sell = 1675, ah = 9800 },
    { key = "rep", name = "Sample Faction", amount = 25 },
    { key = "item", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", name = "Sample Ring", q = 3, count = 1, sell = 4210 },
    { key = "skill", name = "Mining", rank = 87 },
    { key = "cur", icon = "Interface\\Icons\\INV_Misc_Token_ArgentDawn", name = "Sample Token", count = 2 },
    { key = "item", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", name = "Sample Pearl", q = 0, count = 1, sell = 5 },
}
function LF.ShowExamples()
    local c = Cfg()
    if not c.enabled then return end
    for i, s in ipairs(SAMPLES) do
        C_Timer.After((i - 1) * 0.25, function()
            if s.key == "item" then
                if s.q < (c.minQuality or 0) then return end
                local r, g, b = QualityColor(s.q)
                local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
                Push("sample:" .. s.name, { icon = s.icon, text = hex .. s.name .. "|r", r = r, g = g, b = b, count = s.count,
                    value = function(n)
                        local lines = {}
                        if c.vendorPrice and s.sell then lines[#lines + 1] = Money(s.sell * n) end
                        if c.auctionPrice and s.ah then lines[#lines + 1] = "|cff9d9d9dAH|r " .. Money(s.ah * n) end
                        return table.concat(lines, "\n")
                    end })
            elseif s.key == "money" then
                ShowMoney(s.copper)
            elseif s.key == "rep" then
                ShowReputation(s.name, s.amount)
            elseif s.key == "skill" then
                local col = COLORS.skill
                Push("sample:" .. s.name, { icon = SKILL_ICON, text = s.name, r = col[1], g = col[2], b = col[3], count = 1,
                    value = function() return "|cffffffff" .. s.rank .. "|r" end })
            elseif s.key == "cur" then
                Push("sample:" .. s.name, { icon = s.icon, text = s.name, r = 1, g = 1, b = 1, count = s.count })
            end
        end)
    end
end

ns.OnLogin(function() LF.Apply() end)
ns.OnRefresh(function() LF.Apply() end)
