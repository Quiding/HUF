-- HUF: settings of the Loot Feed (the General page's "Loot Feed" tile) and its
-- Advanced Options window (the hidden page "lootfeed").

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local function C() return ns.db.lootFeed end
local function Opt(k) return function() return C()[k] end, function(v) C()[k] = v end end

local QUALITIES = {
    { value = 0, text = "|cff9d9d9dPoor|r" },
    { value = 1, text = "|cffffffffCommon|r" },
    { value = 2, text = "|cff1eff00Uncommon|r" },
    { value = 3, text = "|cff0070ddRare|r" },
    { value = 4, text = "|cffa335eeEpic|r" },
    { value = 5, text = "|cffff8000Legendary|r" },
}

local function Track(parent, w)
    local p = parent
    while p and type(rawget(p, "widgets")) ~= "table" do p = p:GetParent() end
    if p then table.insert(p.widgets, w) end
end

-- a label with a small number box at the right end of its width
local function NumBox(parent, width, label, key, min, max, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, UI.ROW)
    local fs = UI.Label(f, label)
    fs:SetPoint("LEFT", 0, 0)
    local e = UI.EditBox(f, 46, "")
    e:SetPoint("RIGHT", 0, 0)
    e:SetJustifyH("CENTER")
    e:SetMaxLetters(4)
    local function Commit()
        local v = tonumber(e:GetText())
        if v then
            v = math.max(min, math.min(max, math.floor(v + 0.5)))
            if v ~= C()[key] then
                C()[key] = v
                ns.Log("config", "loot feed %s = %s", key, v)
                ns.Refresh()
            end
        end
        e:SetText(tostring(C()[key]))
    end
    e:SetScript("OnEnterPressed", function(self) Commit() self:ClearFocus() end)
    e:HookScript("OnEditFocusLost", Commit)
    e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(C()[key])) self:ClearFocus() end)
    f.Refresh = function() if not e:HasFocus() then e:SetText(tostring(C()[key])) end end
    if tip then UI.Tooltip(e, label, tip) end
    Track(parent, f)
    return f
end

-- two widgets side by side in one row of the column
local function Pair(col, parent, a, b)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(col.width, UI.ROW)
    local half = (col.width - 16) / 2
    a:SetParent(row) b:SetParent(row)
    a:ClearAllPoints() b:ClearAllPoints()
    a:SetPoint("LEFT", row, "LEFT", 0, 0)
    b:SetPoint("LEFT", row, "LEFT", half + 16, 0)
    a:SetWidth(half) b:SetWidth(half)
    col:Add(row, UI.ROW + 2)
    return row
end

---------------------------------------------------------------------------
-- The General page's tile (ConfigPages.lua places it)
---------------------------------------------------------------------------
function ns.BuildLootFeedTile(page, x, y, w, h)
    local tile, L = ns.ConfigTile(page, x, y, w, h, "Loot Feed", "Interface\\Icons\\INV_Misc_Bag_10")
    local LF = ns.LootFeed
    local gated = {}
    local function Gated(wd) gated[#gated + 1] = wd return wd end

    L:Check("Faster Looting", Opt("fastLoot"),
        "Takes every item the moment the loot window opens. Hold Shift while looting to get the normal loot window.")
    L:Check("Show Loot Feed", Opt("enabled"),
        "A short list of what you gain (items, money, reputation, currencies, skill ups); each row fades out after a few seconds. Move it in unlock mode.")
    Gated(L:Cycle("Minimum Quality", QUALITIES, Opt("minQuality"), "Items below this quality are not shown."))
    Gated(L:Check("Show Vendor Price", Opt("vendorPrice"), "Items a vendor buys show what they sell for."))
    local ahTip = "Shows the price of Auctionator's last scan (when the Auctionator addon is installed)."
    local ah = Gated(L:Check("Show Auctionator Price", Opt("auctionPrice"), ahTip))
    local inner = (L.width - 16) / 2
    Gated(Pair(L, tile, NumBox(tile, inner, "Width", "width", 100, 800),
        NumBox(tile, inner, "Height", "height", 14, 80)))
    Gated(Pair(L, tile, NumBox(tile, inner, "Max Rows", "maxRows", 1, 20),
        NumBox(tile, inner, "Duration (sec)", "duration", 1, 60, "How long a row stays before it fades out.")))
    L:Space(4)
    local ex = UI.Button(tile, inner, "Show Examples", function() if LF then LF.ShowExamples() end end)
    UI.Tooltip(ex, "Show Examples", "A few made-up rows (items of each quality, money, reputation, a skill up, a currency) to look at the style.")
    local adv = UI.Button(tile, inner, "Advanced Options", function() ns.ShowLootFeedWindow() end)
    Gated(Pair(L, tile, ex, adv))

    table.insert(page.widgets, { Refresh = function()
        local on = C().enabled
        for _, wd in ipairs(gated) do UI.SetActive(wd, on) end
        if on then UI.SetActive(ah, LF and LF.HasAuctionator() or false) end
    end })
    return tile
end

---------------------------------------------------------------------------
-- Advanced Options (a window of its own)
---------------------------------------------------------------------------
ns.RegisterPage("lootfeed", "Loot Feed", "hidden", function(page)
    local W = 300
    local L = UI.Column(page, 0, 0, W)
    L:Header("Text")
    L:Cycle("Text Font", function() return ns.FontChoices(true) end, Opt("font"))
    L:Slider("Text Size", 6, 24, 1, Opt("fontSize"))
    L:Cycle("Text Outline", ns.OUTLINES_G, Opt("outline"))
    L:Header("Accent")
    local gq, sq = Opt("accentQuality")
    local colorBtn
    L:Check("Accent colour from the item quality", gq, function(v)
        sq(v)
        UI.SetActive(colorBtn, not v)
    end, "Items take their quality colour (grey, white, green, blue, ...); money is gold, reputation green, skill ups blue.")
    colorBtn = L:Color("Accent colour", Opt("accentColor"))
    L:Cycle("Accent Position", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
        { value = "TOP", text = "Top" },
        { value = "BOTTOM", text = "Bottom" },
    }, Opt("accentPos"))
    L:Slider("Accent Thickness", 1, 8, 1, Opt("accentSize"))
    table.insert(page.widgets, { Refresh = function() UI.SetActive(colorBtn, not C().accentQuality) end })

    local R = UI.Column(page, W + 30, 0, W)
    R:Header("Item Sources")
    local function Src(k) return function() return C().sources[k] ~= false end, function(v) C().sources[k] = v end end
    R:Check("Items", Src("items"))
    R:Check("Money", Src("money"))
    R:Check("Reputation", Src("reputation"))
    R:Check("Currency", Src("currency"))
    R:Check("Skill Ups", Src("skills"))
    R:Header("Layout")
    R:Cycle("Grow Direction", {
        { value = "UP", text = "Up (newest at the bottom)" },
        { value = "DOWN", text = "Down (newest at the top)" },
    }, Opt("grow"))
    R:Slider("Space between rows", 0, 10, 1, Opt("spacing"))
    local ga, sa = Opt("bgAlpha")
    R:Slider("Background opacity", 0, 1, 0.05, ga, sa, "%.2f")
    R:Space(4)
    R:Button("Show Examples", function() if ns.LootFeed then ns.LootFeed.ShowExamples() end end)
end)

local win
function ns.ShowLootFeedWindow()
    if not win then
        win = CreateFrame("Frame", "HUF_LootFeedSettings", UIParent)
        win:SetSize(660, 420)
        win:SetPoint("CENTER", 0, 10)
        win:SetFrameStrata("DIALOG")
        win:SetToplevel(true)
        win:SetClampedToScreen(true)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        UI.Fill(win, 0.05, 0.05, 0.06, 0.97)
        UI.Border(win, A[1], A[2], A[3], 0.9)
        local title = UI.Label(win, "Loot Feed - Advanced Options", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetTextColor(A[1], A[2], A[3])
        local close = UI.Button(win, 22, "x", function() win:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
        local body = CreateFrame("Frame", nil, win)
        body:SetPoint("TOPLEFT", 12, -38)
        body:SetSize(636, 370)
        body.widgets = {}
        local page = ns.configPages and ns.configPages.lootfeed
        if page then
            local ok, err = pcall(page.build, body)
            if not ok then ns.Log("config", "loot feed window: %s", tostring(err)) end
        end
        win.Refresh = function()
            for _, w in ipairs(body.widgets) do pcall(w.Refresh) end
        end
        win:SetScript("OnShow", win.Refresh)
        ns.OnRefresh(function() if win:IsShown() then win.Refresh() end end)
        UI.CloseOnEscape(win)
        win:Hide()
    end
    win:Show()
    win.Refresh()
end
