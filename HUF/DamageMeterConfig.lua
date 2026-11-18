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

ns.RegisterPage("damagemeter", "Damage meter", "frames", function(page)
    local on = UI.Check(page, 260, "Use HUF's damage meter", function() return D().enabled end,
        function(v) D().enabled = v end, "The game's own meter data in a HUF window, with privacy names. Also /huf meter.")
    on:SetPoint("TOPLEFT", 0, 4)

    local L = UI.Column(page, 0, -30, COL_W)
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
    L:Header("Window")
    L:Slider("Width", 120, 500, 1, Opt("width"))
    L:Slider("Rows", 1, 40, 1, Opt("rows"))
    L:Slider("Row height", 10, 40, 1, Opt("rowHeight"))
    L:Slider("Space between rows", 0, 6, 1, Opt("rowGap"))
    L:Slider("Scale", 0.5, 2, 0.05, function() return D().scale end, function(v) D().scale = v end, "%.2f")
    local gl, sl = Opt("locked")
    L:Check("Lock (no dragging by the title)", gl, sl)

    local R = UI.Column(page, COL2_X, -30, COL_W)
    R:Header("Bars")
    R:Cycle("Texture", Textures, Opt("texture"))
    R:Cycle("Colour", {
        { value = "CLASS", text = "Class" },
        { value = "ACCENT", text = "Accent" },
        { value = "STATIC", text = "Static colour" },
    }, Opt("colorMode"))
    R:Color("Static colour", Opt("color"))
    R:Slider("Background opacity", 0, 1, 0.05, function() return D().bgAlpha end, function(v) D().bgAlpha = v end, "%.2f")
    R:Header("Text")
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Size", 6, 20, 1, Opt("fontSize"))
    R:Slider("Title size", 6, 20, 1, Opt("titleSize"))
    R:Cycle("Outline", {
        { value = "GLOBAL", text = "General outline" },
        { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
    }, Opt("outline"))
    R:Cycle("Numbers", {
        { value = "BOTH", text = "Total (per second)" },
        { value = "TOTAL", text = "Total" },
        { value = "PERSECOND", text = "Per second" },
    }, Opt("numbers"))
    local gr, sr = Opt("showRank")
    R:Check("Rank before the name", gr, sr)
    local gp, sp = Opt("threatPets")
    R:Check("Threat: pets too", gp, sp)
    local gc, sc = Opt("threatColors")
    R:Check("Threat: bars in threat colours", gc, sc, "Grey, yellow, orange and red (has aggro) like the game's threat warning.")
    R:Note("Title bar: list and fight dropdowns, + new window, R reset, x close. Click a row for its breakdown. Names follow Names & MMT; in instance combat the game hides the meter's names: HUF then shows a name it recognised, else the class, never a hidden real name.")
end, function() return ns.db.damageMeter.enabled end)
