-- HUF: settings page for the bags (FRAMES > Bags).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function B() return ns.db.bags end
local function Opt(k) return function() return B()[k] end, function(v) B()[k] = v end end

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end

ns.RegisterPage("bags", "Bags", "frames", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Bags")
    local ge, se = Opt("enabled")
    L:Check("Use HUF's bag window", ge, function(v)
        se(v)
        if not v then ns.Print("Blizzard's bags come back after /reload.") end
    end, "All bags in one window with the bank and your other characters (from what HUF saw), search and the counts in tooltips. Using and moving items works as in Blizzard's bags.")
    local go, so = Opt("oneBag")
    L:Check("The game's combined bags (one bag)", go, so, "The game's own option: all bags in one window. Matters for Blizzard's bags (HUF's window is always one bag).")
    local gt, st = Opt("tooltipCounts")
    L:Check("Item counts in tooltips", gt, st, "\"Name: 8 | 12\" (bags | bank) for this character and every other one HUF saw.")
    local gb, sb = Opt("openWithBank")
    L:Check("Open with the bank", gb, sb)
    local gs, ss = Opt("sortButton")
    L:Check("Sort button", gs, function(v) ss(v) if ns.Bags and ns.Bags.frame then ns.Bags.UpdateHeader() end end,
        "The game's own sort (as Blizzard's bag button): the server sorts, so it's done in a moment. The bank sorts while you're at it.")
    local CC = C_Container
    if CC and CC.GetSortBagsRightToLeft and CC.SetSortBagsRightToLeft then
        L:Check("Sort towards the last bag", function() return CC.GetSortBagsRightToLeft() and true or false end,
            function(v) pcall(CC.SetSortBagsRightToLeft, v) end, "The game's own option: sorted items end up in the last bag instead of the backpack.")
    end
    L:Button("Open the bags", function() if ns.Bags then ns.Bags.Show() end end)
    L:Button("Forget the other characters", function()
        UI.Confirm("Forget the bags and banks HUF saved for every other character?", "Forget", function()
            local me = ns.CharKey()
            for k in pairs(HUFDB.inventory or {}) do if k ~= me then HUFDB.inventory[k] = nil end end
        end)
    end)
    L:Note("The bank shows what it held the last time you visited a banker with that character. Your other characters show after you log in with each once. Saved for this account only, never in a profile export.")

    L:Header("Reagent bag")
    local grs, srs = Opt("reagentSeparate")
    L:Check("Show reagent bag separately", grs, srs, "The reagent bag in its own small window next to the bags instead of in the one bag.")
    L:Cycle("Side", { { value = "LEFT", text = "Left of the bags" }, { value = "RIGHT", text = "Right of the bags" } }, Opt("reagentSide"))
    L:Slider("Slots per row", 1, 12, 1, Opt("reagentCols"))
    local grt, srt = Opt("reagentTint")
    L:Check("Highlight colour of reagent bag slots", grt, srt, "The reagent bag only takes reagents: its slots get this colour.")
    L:Color("Colour", Opt("reagentColor"))

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Window")
    R:Slider("Slots per row", 4, 24, 1, Opt("cols"))
    R:Slider("Slot size", 20, 56, 1, Opt("size"))
    R:Slider("Space between slots", 0, 12, 1, Opt("spacing"))
    R:Slider("Scale", 0.5, 2, 0.05, function() return B().scale end, function(v) B().scale = v end, "%.2f")
    R:Color("Background", Opt("bgColor"))
    R:Slider("Background opacity", 0, 1, 0.05, function() return B().bgAlpha end, function(v) B().bgAlpha = v end, "%.2f")
    local ga, sa = Opt("borderAccent")
    R:Check("Border in the accent colour", ga, sa)
    R:Color("Border colour", Opt("borderColor"))
    R:Slider("Border", 0, 1, 1, Opt("borderSize"))
    local gq, sq = Opt("qualityBorders")
    R:Check("Slot border in the item's quality colour", gq, sq)
    local gm, sm = Opt("showEmpty")
    R:Check("Show empty slots", gm, sm)
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Stack number size", 6, 20, 1, Opt("countSize"))
end, function() return ns.db.bags.enabled end)
