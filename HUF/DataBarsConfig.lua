-- HUF: settings for the data bars, a tab of the Minimap page (FRAMES >
-- Minimap > Data bar). For now the minimap data bar.

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function D() return ns.db.dataBars.minimap end
local function Opt(k) return function() return D()[k] end, function(v) D()[k] = v end end

function ns.DataBarsTab(page)
    local on = UI.Check(page, 300, "Minimap data bar", function() return D().enabled end,
        function(v) D().enabled = v end, "A strip under the minimap with friends and guild members online.")
    on:SetPoint("TOPLEFT", 0, 0)

    local L = UI.Column(page, 0, -28, COL_W)
    L:Header("Minimap data bar")
    L:Cycle("Place", {
        { value = "BELOW", text = "Under the map" },
        { value = "ABOVE", text = "Over the map" },
    }, Opt("position"))
    L:Slider("Height", 14, 40, 1, Opt("height"))
    L:Slider("Space to the map", 0, 10, 1, Opt("gap"))
    L:Color("Background colour", Opt("bgColor"))
    L:Slider("Background opacity", 0, 1, 0.05, function() return D().bgAlpha end, function(v) D().bgAlpha = v end, "%.2f")
    L:Slider("Line around it", 0, 2, 1, Opt("borderSize"))

    local R = UI.Column(page, COL2_X, -28, COL_W)
    R:Header("What it shows")
    local gf, sf = Opt("friends")
    R:Check("Friends online", gf, sf, "Click: the friends list.")
    local gg, sg = Opt("guild")
    R:Check("Guild members online", gg, sg, "Click: the guild window. Not shown outside a guild.")
    R:Cycle("Layout", {
        { value = "SIDE", text = "Icon, then the count" },
        { value = "STACK", text = "Count above a small icon" },
    }, Opt("layout"))
    R:Cycle("Icon colour", {
        { value = "MONO", text = "Flat grey" },
        { value = "GAME", text = "The game's colours" },
        { value = "CLASS", text = "Class colour" },
        { value = "ACCENT", text = "Accent colour" },
        { value = "CUSTOM", text = "Own colour" },
    }, Opt("iconColor"))
    R:Color("Own icon colour", Opt("iconCustom"))
    R:Slider("Text size", 8, 20, 1, Opt("fontSize"))
    R:Slider("Space between them", 0, 40, 1, Opt("spacing"))
    R:Note("The tracking button sits on the bar's left end when Minimap > Icons > Tracking is at \"Below, left\".")
end
