-- HUF: settings page for the damage meter (GENERAL > Damage Meter).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function D() return ns.db.damageMeter end
-- the window whose settings the page shows (the dropdown at the top)
local sel = 1
local function Win()
    local list = D().windows or {}
    if sel > #list or sel > (D().windowCount or 1) then sel = 1 end
    return list[sel]
end
local function PW(k) return ns.DamageMeter and ns.DamageMeter.PER_WINDOW and ns.DamageMeter.PER_WINDOW[k] end
-- per-window keys: the selected window's own value, else the shared one; a
-- change goes to that window only. Meter-wide keys: the shared settings.
local function Opt(k)
    return function()
        local w = PW(k) and Win()
        if w and w[k] ~= nil then return w[k] end
        return D()[k]
    end, function(v)
        local w = PW(k) and Win()
        if w then w[k] = v else D()[k] = v end
    end
end

local TYPE_NAMES = { DamageDone = "Damage done", HealingDone = "Healing done", DamageTaken = "Damage taken",
    AvoidableDamageTaken = "Avoidable damage", EnemyDamageTaken = "Enemy damage taken", Interrupts = "Interrupts",
    Dispels = "Dispels", Deaths = "Deaths", Threat = "Threat" }
local function WindowChoices()
    if ns.DamageMeter and ns.DamageMeter.EnsureWindows then ns.DamageMeter.EnsureWindows() end
    local l = {}
    for i = 1, (D().windowCount or 1) do
        local w = D().windows and D().windows[i]
        local t = w and (TYPE_NAMES[w.meterType] or w.meterType) or ""
        l[#l + 1] = { value = i, text = ("Window %d%s"):format(i, t ~= "" and (" (" .. t .. ")") or "") }
    end
    return l
end

-- every window takes the selected window's size and look
local function ApplyToAll()
    local src = Win()
    if not src then return end
    local n = 0
    for i = 1, (D().windowCount or 1) do
        local w = D().windows[i]
        if w and i ~= sel then
            for k in pairs(ns.DamageMeter.PER_WINDOW) do
                local v = src[k]
                if v == nil then v = D()[k] end
                w[k] = type(v) == "table" and ns.CopyTable(v) or v
            end
            n = n + 1
        end
    end
    ns.Log("config", "damage meter: window %d's settings to %d other windows", sel, n)
    ns.Refresh()
end

local function Fonts()
    local l = { { value = "GLOBAL", text = "HUF Global Font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local function Textures()
    local l = {}
    for _, t in ipairs(ns.textures) do l[#l + 1] = { value = t.name, text = t.name } end
    return l
end

local TOP = -64
local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

-- tab 1: meter and windows
local function MeterPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Meter (all windows)")
    local gb, sb = Opt("hideBlizzard")
    L:Check("Hide Blizzard's damage meter", gb, sb, "Switches the game's meter window off while HUF's is on, and back on when HUF's is off.")
    L:Cycle("Show", {
        { value = "ALWAYS", text = "Always" },
        { value = "GROUP", text = "In a group" },
        { value = "INSTANCE", text = "In instances" },
        { value = "COMBAT", text = "In combat" },
    }, Opt("show"))
    L:Slider("Windows", 1, 5, 1, Opt("windowCount"))
    local gf, sf = Opt("fadeOOC")
    L:Check("Reduce opacity out of combat", gf, sf, "All windows at the opacity below while out of combat; a window under the mouse is fully visible.")
    L:Slider("Opacity out of combat", 0, 1, 0.05, function() return D().fadeAlpha end, function(v) D().fadeAlpha = v end, "%.2f")
    local gh, sh = Opt("hideThreatOOC")
    L:Check("Hide threat windows out of combat", gh, sh, "A window showing threat appears when a fight starts and goes when it ends. Switched to threat out of combat, it stays until the next fight is over. While these settings are open or in unlock mode every window shows, so you can move and change them.")
    local gp, sp = Opt("threatPets")
    L:Check("Threat: pets too", gp, sp)
    local gc, sc = Opt("threatColors")
    L:Check("Threat: bars in threat colours", gc, sc, "Grey, yellow, orange and red (has aggro) like the game's threat warning.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Window (the one chosen above)")
    R:Slider("Width", 120, 500, 1, Opt("width"))
    R:Slider("Rows", 1, 40, 1, Opt("rows"))
    R:Slider("Row height", 10, 40, 1, Opt("rowHeight"))
    R:Slider("Space between rows", 0, 6, 1, Opt("rowGap"))
    local gsc, ssc = Opt("scale")
    R:Slider("Scale", 0.5, 2, 0.05, gsc, ssc, "%.2f")
    local gl, sl = Opt("locked")
    R:Check("Lock (no dragging by the title)", gl, sl)
    local gw, sw = Opt("windowBorder")
    R:Check("Line around the window", gw, sw)
    local gk, sk = Opt("breakdownInline")
    R:Check("Breakdown and meter list inside the window", gk, sk, "Clicking a name shows its spells in the same window; right-clicking the names shows the list of meters to pick one. < or a right-click goes back to the names. Off: the breakdown in a panel beside the window. On by default.")
    local gn, sn = Opt("nameHover")
    R:Check("Hover a name: its top spells", gn, sn, "A box beside the window with the player's spells while the mouse is on the name. A click still opens the whole breakdown.")
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
    local gba, sba = Opt("bgAlpha")
    L:Slider("Background opacity", 0, 1, 0.05, gba, sba, "%.2f")
    L:Cycle("Icons", {
        { value = "NONE", text = "None" },
        { value = "CLASS", text = "Class icon before the bar" },
    }, Opt("icons"))
    L:Slider("Border around each bar", 0, 3, 1, Opt("rowBorder"))
    local gbb, sbb = Opt("barBgAlpha")
    L:Slider("Empty part of a bar: opacity", 0, 1, 0.05, gbb, sbb, "%.2f")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Text")
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Size", 6, 20, 1, Opt("fontSize"))
    R:Cycle("Outline", {
        { value = "GLOBAL", text = "HUF Global Outline" },
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
    R:Slider("Icon size (at most the title bar's height - 2)", 10, 32, 1, Opt("titleIconSize"))
    local gm, sm = Opt("titleIconsMuted")
    R:Check("Muted icons", gm, sm, "Grey and dimmed to fit the dark title bar; the accent colour under the mouse. Off: the icons in their own colours.")
    R:Note("Title bar: meter type and fight (click: list, mouse wheel: step through; the fight list ends with \"Reset all fights\"), + new window, x close (the window and its settings; the last window turns the meter off).")
end

ns.RegisterPage("damagemeter", "Damage meter", "general", function(page)
    -- open page: hidden threat windows show (DM.Editing), closed: hidden again
    page:HookScript("OnShow", function() if ns.DamageMeter then ns.DamageMeter.Apply() end end)
    page:HookScript("OnHide", function() if ns.DamageMeter then C_Timer.After(0, ns.DamageMeter.Apply) end end)
    local on = UI.Check(page, 260, "Use HUF's damage meter", function() return D().enabled end,
        function(v) D().enabled = v end, "The game's own meter data in a HUF window, with privacy names. Also /huf meter.")
    on:SetPoint("TOPLEFT", 0, 4)
    -- which window the size / look settings below change
    local pick = UI.Dropdown(page, 330, "Settings of", WindowChoices, function() return sel end, function(v)
        sel = v
        ns.RefreshConfig()
    end, "Each damage meter window has its own size and look (Window, Bars & text, Title bar). The Meter settings are the same for all windows.")
    pick:SetPoint("TOPLEFT", 0, -22)
    table.insert(page.widgets, pick)
    local all = UI.Button(page, 220, "Apply settings to all frames", function()
        UI.Confirm(("Give every damage meter window the size and look of window %d?"):format(sel), "Apply", ApplyToAll, "Cancel")
    end)
    all:SetPoint("LEFT", pick, "RIGHT", 16, 0)
    UI.Tooltip(all, "Apply settings to all frames", "Copies the chosen window's size and look (Window, Bars & text, Title bar) to every other window. Their meter type, fight and place stay their own.")
    table.insert(page.widgets, { Refresh = function() UI.SetActive(all, (D().windowCount or 1) > 1) end })
    local tabs = { { "meter", "Meter & windows" }, { "bars", "Bars & text" }, { "title", "Title bar" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -50)
    strip:SetPoint("TOPRIGHT", 0, -50)
    subs.meter = SubFrame(page); MeterPage(subs.meter)
    subs.bars = SubFrame(page); BarsPage(subs.bars)
    subs.title = SubFrame(page); TitlePage(subs.title)
    strip:Bind(subs, Show)
    Show("meter")
end, function() return ns.db.damageMeter.enabled end)
