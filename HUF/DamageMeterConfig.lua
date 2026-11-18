-- HUF: settings page for the damage meter (FRAMES > Damage meter).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function D() return ns.db.damageMeter end
local function Opt(k) return function() return D()[k] end, function(v) D()[k] = v end end

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local function Textures()
    local l = {}
    for _, t in ipairs(ns.textures) do l[#l + 1] = { value = t.name, text = t.name } end
    return l
end

local TOP = -36
local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

-- tab 1: meter and windows
local function MeterPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Meter")
    local gb, sb = Opt("hideBlizzard")
    L:Check("Hide Blizzard's damage meter", gb, sb, "Switches the game's meter window off while HUF's is on, and back on when HUF's is off.")
    L:Cycle("Show", {
        { value = "ALWAYS", text = "Always" },
        { value = "GROUP", text = "In a group" },
        { value = "INSTANCE", text = "In instances" },
    }, Opt("show"))
    L:Slider("Windows", 1, 5, 1, Opt("windowCount"))
    local gf, sf = Opt("fadeOOC")
    L:Check("Reduce opacity out of combat", gf, sf, "All windows at the opacity below while out of combat; a window under the mouse is fully visible.")
    L:Slider("Opacity out of combat", 0, 1, 0.05, function() return D().fadeAlpha end, function(v) D().fadeAlpha = v end, "%.2f")
    local gh, sh = Opt("hideThreatOOC")
    L:Check("Hide threat windows out of combat", gh, sh, "A window showing threat appears when a fight starts and goes when it ends. Switched to threat out of combat, it stays until the next fight is over.")
    local gp, sp = Opt("threatPets")
    L:Check("Threat: pets too", gp, sp)
    local gc, sc = Opt("threatColors")
    L:Check("Threat: bars in threat colours", gc, sc, "Grey, yellow, orange and red (has aggro) like the game's threat warning.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Window")
    R:Slider("Width", 120, 500, 1, Opt("width"))
    local gr, sr = Opt("rows")
    -- every window: drops the windows' own row counts (an EllesmereUI import sets them)
    R:Slider("Rows", 1, 40, 1, gr, function(v)
        sr(v)
        for _, w in ipairs(ns.db.damageMeter.windows or {}) do w.rows = nil end
    end)
    R:Slider("Row height", 10, 40, 1, Opt("rowHeight"))
    R:Slider("Space between rows", 0, 6, 1, Opt("rowGap"))
    R:Slider("Scale", 0.5, 2, 0.05, function() return D().scale end, function(v) D().scale = v end, "%.2f")
    local gl, sl = Opt("locked")
    R:Check("Lock (no dragging by the title)", gl, sl)
    local gw, sw = Opt("windowBorder")
    R:Check("Line around the window", gw, sw)
    local gk, sk = Opt("breakdownInline")
    R:Check("Breakdown inside the window", gk, sk, "Clicking a name shows its spells in the same window; < (or a right-click) goes back to the names. Off: a panel beside the window.")
    R:Note("Click a row for its breakdown. Names follow Names & MMT; in instance combat the game hides the meter's names: HUF then shows a name it recognised, else the class, never a hidden real name.")
end

-- tab 2: bars and text
local function BarsPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Bars")
    L:Cycle("Texture", Textures, Opt("texture"))
    L:Cycle("Colour", {
        { value = "CLASS", text = "Class" },
        { value = "ACCENT", text = "Accent" },
        { value = "STATIC", text = "Static colour" },
    }, Opt("colorMode"))
    L:Color("Static colour", Opt("color"))
    L:Slider("Background opacity", 0, 1, 0.05, function() return D().bgAlpha end, function(v) D().bgAlpha = v end, "%.2f")
    L:Cycle("Icons", {
        { value = "NONE", text = "None" },
        { value = "CLASS", text = "Class icon before the bar" },
    }, Opt("icons"))
    L:Slider("Border around each bar", 0, 3, 1, Opt("rowBorder"))
    L:Slider("Empty part of a bar: opacity", 0, 1, 0.05, function() return D().barBgAlpha end, function(v) D().barBgAlpha = v end, "%.2f")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Text")
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Size", 6, 20, 1, Opt("fontSize"))
    R:Cycle("Outline", {
        { value = "GLOBAL", text = "General outline" },
        { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
    }, Opt("outline"))
    R:Cycle("Numbers", {
        { value = "BOTH", text = "Total (per second)" },
        { value = "BAR", text = "Total | per second" },
        { value = "TOTAL", text = "Total" },
        { value = "PERSECOND", text = "Per second" },
    }, Opt("numbers"))
    local gr, sr = Opt("showRank")
    R:Check("Rank before the name", gr, sr)
end

-- tab 3: title bar
local function TitlePage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Title bar")
    L:Slider("Height", 12, 30, 1, Opt("titleHeight"))
    L:Slider("Title size", 6, 20, 1, Opt("titleSize"))
    L:Color("Colour", Opt("titleColor"))
    local gt, st = Opt("titleLine")
    L:Check("Accent line under it", gt, st)
    local ga, sa = Opt("titleAccent")
    L:Check("Fight in the accent colour", ga, sa)

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Icons")
    local gi, si = Opt("titleIcons")
    R:Check("Icons for meter type and fight", gi, si, "The meter type's name at the left, icon buttons for the meter type and the fight at the right (their names in the tooltips).")
    R:Slider("Icon size", 10, 32, 1, Opt("titleIconSize"))
    R:Note("Title bar: meter type and fight (click: list, mouse wheel: step through), + new window, R reset, x close.")
end

ns.RegisterPage("damagemeter", "Damage meter", "frames", function(page)
    local on = UI.Check(page, 260, "Use HUF's damage meter", function() return D().enabled end,
        function(v) D().enabled = v end, "The game's own meter data in a HUF window, with privacy names. Also /huf meter.")
    on:SetPoint("TOPLEFT", 0, 4)
    local tabs = { { "meter", "Meter & windows" }, { "bars", "Bars & text" }, { "title", "Title bar" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.meter = SubFrame(page); MeterPage(subs.meter)
    subs.bars = SubFrame(page); BarsPage(subs.bars)
    subs.title = SubFrame(page); TitlePage(subs.title)
    Show("meter")
end, function() return ns.db.damageMeter.enabled end)
