-- HUF: settings page for the buff and debuff bars (FRAMES > Buff bars).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X, TOP = 330, 366, -36

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local OUTLINES = {
    { value = "GLOBAL", text = "General outline" }, { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
}
local GROW = {
    { value = "RIGHT", text = "Left to right" }, { value = "LEFT", text = "Right to left" },
    { value = "DOWN", text = "Top to bottom" }, { value = "UP", text = "Bottom to top" },
}

local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

local function BarPage(f, kind)
    local B = function() return ns.db.auraBars[kind] end
    local function Opt(k) return function() return B()[k] end, function(v) B()[k] = v end end
    local title = kind == "buffs" and "buff" or "debuff"

    local L = UI.Column(f, 0, 0, COL_W)
    L:Header(kind == "buffs" and "Buff bar" or "Debuff bar")
    local ge, se = Opt("enabled")
    L:Check("Use HUF's " .. title .. " bar", ge, function(v)
        se(v)
        if not v then ns.Print("Blizzard's " .. title .. "s come back after /reload.") end
    end, "Replaces Blizzard's " .. title .. " icons at the top right. Right-click a buff to cancel it (out of combat).")
    L:Cycle("Growth direction", GROW, Opt("grow"))
    L:Slider("Most icons", 1, 40, 1, Opt("max"))
    L:Slider("Rows", 1, 10, 1, Opt("rows"))
    L:Slider("Columns", 1, 20, 1, Opt("columns"))
    L:Slider("Padding", 0, 20, 1, Opt("padding"))
    L:Cycle("Sort by", { { value = "TIME", text = "Time left" }, { value = "NAME", text = "Name" },
        { value = "INDEX", text = "Order gained" } }, Opt("sort"))
    L:Cycle("Order", { { value = "-", text = "Descending" }, { value = "+", text = "Ascending" } }, Opt("sortDir"))
    L:Slider("Scale", 0.5, 2, 0.05, function() return B().scale end, function(v) B().scale = v end, "%.2f")
    L:Header("Text")
    L:Slider("Stack size", 6, 20, 1, Opt("countSize"))
    L:Cycle("Font", Fonts, Opt("font"))
    L:Cycle("Outline", OUTLINES, Opt("outline"))
    L:Note("Move the bar in unlock mode (/huf unlock). Rows and columns set the area; \"Most icons\" can show fewer.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Icons")
    R:Slider("Icon size", 12, 64, 1, Opt("size"))
    R:Slider("Zoom", 0, 0.3, 0.01, function() return B().zoom end, function(v) B().zoom = v end, "%.2f")
    R:Slider("Border", 0, 4, 1, Opt("borderSize"))
    local ga, sa = Opt("borderAccent")
    R:Check("Border in the accent colour", ga, sa)
    R:Color("Border colour", Opt("borderColor"))
    if kind == "debuffs" then
        local gt, st = Opt("typeColors")
        R:Check("Border by debuff type", gt, st, "Magic blue, curse purple, disease brown, poison green, others red.")
    end
    local gw, sw = Opt("swipe")
    R:Check("Darken as time runs out (swipe)", gw, sw)
    R:Header("Time left and stacks")
    local gtm, stm = Opt("timer")
    R:Check("Show time left", gtm, stm)
    R:Cycle("An hour or more", { { value = "HHMM", text = "h:mm (1:05)" }, { value = "MM", text = "Minutes (65m)" } },
        Opt("timerFormat"))
    R:Cycle("Time position", { { value = "BELOW", text = "Below the icon" }, { value = "INSIDE", text = "On the icon" } },
        Opt("timerPos"))
    R:Slider("Time size", 6, 20, 1, Opt("timerSize"))
end

ns.RegisterPage("aurabars", "Buff bars", "frames", function(page)
    local tabs = { { "buffs", "Buffs" }, { "debuffs", "Debuffs" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.buffs = SubFrame(page); BarPage(subs.buffs, "buffs")
    subs.debuffs = SubFrame(page); BarPage(subs.debuffs, "debuffs")
    if strip.Bind then strip:Bind(subs, Show) end
    Show("buffs")
end, function() return ns.db.auraBars.buffs.enabled or ns.db.auraBars.debuffs.enabled end)
