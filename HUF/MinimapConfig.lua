-- HUF: settings page for the minimap (FRAMES > Minimap).
-- Tabs: Map (shape, size, look), Texts, Icons (the game's), Addon buttons.

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X, TOP = 330, 366, -36
local HALF = (COL_W - 8) / 2

local function M() return ns.db.minimap end
local function Opt(tbl, k) return function() return tbl()[k] end, function(v) tbl()[k] = v end end

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local OUTLINES = {
    { value = "GLOBAL", text = "General outline" },
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" },
    { value = "THICKOUTLINE", text = "Thick" },
}

local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

-- two widgets side by side in a column
local function Pair(col, a, b, height)
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", col.parent, "TOPLEFT", col.x, col.y)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", col.parent, "TOPLEFT", col.x + HALF + 8, col.y)
    col.y = col.y - (height or (UI.ROW + 2))
end

-- one placed element: show (always / mouseover / never), where, offsets
local function Element(col, title, T, extra, modes)
    col:Header(title)
    Pair(col,
        UI.Dropdown(col.parent, HALF, "Show", modes or ns.Minimap.MODES, Opt(T, "mode")),
        UI.Dropdown(col.parent, HALF, "At", ns.Minimap.POSITIONS, Opt(T, "pos")))
    Pair(col,
        UI.Slider(col.parent, HALF, "Horizontal", -200, 200, 1, Opt(T, "x")),
        UI.Slider(col.parent, HALF, "Vertical", -200, 200, 1, Opt(T, "y")), 36)
    if extra then extra(col) end
end

local function MapPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Map")
    L:Cycle("Shape", { { value = "SQUARE", text = "Square" }, { value = "ROUND", text = "Round" } }, Opt(M, "shape"))
    L:Slider("Size", 100, 400, 1, Opt(M, "size"))
    L:Slider("Scale", 0.5, 2, 0.05, function() return M().scale end, function(v) M().scale = v end, "%.2f")
    local gz, sz = Opt(M, "mouseZoom")
    L:Check("Zoom with the mouse wheel", gz, sz)
    L:Slider("Size of the game's icons", 0.5, 2, 0.05, function() return M().iconScale end,
        function(v) M().iconScale = v end, "%.2f")
    L:Button("Reset position", function()
        M().point = ns.CopyTable(ns.DEFAULTS.minimap.point)
        ns.Refresh(true)
    end)
    L:Note("Move it in unlock mode (/huf unlock): drag the minimap. Right-click it there for this page.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Border")
    R:Slider("Size", 0, 8, 1, Opt(M, "borderSize"))
    local ga, sa = Opt(M, "borderAccent")
    R:Check("Accent colour", ga, sa)
    R:Color("Colour (accent off)", Opt(M, "borderColor"))
    R:Header("Shade outside")
    R:Slider("Width", 0, 40, 1, Opt(M, "shade"))
    R:Slider("Strength", 0, 1, 0.05, function() return M().shadeAlpha end, function(v) M().shadeAlpha = v end, "%.2f")
    R:Header("Text")
    R:Cycle("Font", Fonts, Opt(M, "font"))
    R:Cycle("Outline", OUTLINES, Opt(M, "outline"))
end

local COLORS = {
    { value = "WHITE", text = "White" },
    { value = "ACCENT", text = "Accent" },
}
local function TextsPage(f)
    local function T(k) return function() return M().texts[k] end end
    local function Extra(k)
        return function(col)
            local choices = COLORS
            if k == "zone" then
                choices = { { value = "ZONE", text = "By zone (PvP)" }, COLORS[1], COLORS[2] }
            end
            Pair(col,
                UI.Slider(col.parent, HALF, "Size", 6, 24, 1, Opt(T(k), "size")),
                UI.Dropdown(col.parent, HALF, "Colour", choices, Opt(T(k), "color")), 36)
            if k == "clock" then
                Pair(col,
                    UI.Dropdown(col.parent, HALF, "Format", { { value = "24", text = "24 h" }, { value = "12", text = "12 h" } },
                        Opt(T(k), "format")),
                    UI.Check(col.parent, HALF, "Local time", Opt(T(k), "localTime")))
            elseif k == "coords" then
                col:Slider("Decimals", 0, 2, 1, Opt(T(k), "decimals"))
            elseif k == "system" then
                col:Cycle("Shows", { { value = "BOTH", text = "FPS and latency" }, { value = "FPS", text = "FPS" },
                    { value = "MS", text = "Latency" } }, Opt(T(k), "show"))
            end
        end
    end
    local L = UI.Column(f, 0, 0, COL_W)
    local R = UI.Column(f, COL2_X, 0, COL_W)
    Element(L, "Zone name", T("zone"), Extra("zone"), ns.Minimap.ZONE_MODES)
    Element(L, "Clock", T("clock"), Extra("clock"))
    Element(R, "Coordinates", T("coords"), Extra("coords"))
    Element(R, "FPS and latency", T("system"), Extra("system"))
    R:Note("Text alignment follows the position: left, centered or right. Clock: left-click stopwatch, right-click calendar.")
end

local function IconsPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    local R = UI.Column(f, COL2_X, 0, COL_W)
    for i, info in ipairs(ns.Minimap.ICONS) do
        local col = i <= 4 and L or R
        Element(col, info.title, function() return M().icons[info.key] end)
    end
end

local function ButtonsPage(f, page)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Addon buttons")
    local gb, sb = Opt(M, "addonBar")
    L:Check("Put them into the addon bar", gb, sb,
        "One button on the map instead of every addon's button. Click it: a small bar with all addon buttons; it closes after a click on one of them or after the time below.")
    L:Cycle("Bar opens", {
        { value = "AUTO", text = "Towards the screen's middle" },
        { value = "LEFT", text = "To the left" }, { value = "RIGHT", text = "To the right" },
        { value = "UP", text = "Upwards" }, { value = "DOWN", text = "Downwards" },
    }, Opt(M, "barGrow"))
    L:Cycle("Layout", {
        { value = "ROW", text = "One row" },
        { value = "GRID", text = "Grid" },
    }, Opt(M, "barLayout"))
    L:Slider("Grid columns", 1, 10, 1, Opt(M, "barColumns"))
    local gq, sq = Opt(M, "barSquare")
    L:Check("Square buttons", gq, sq, "The buttons in the bar as square icons on a dark background, without their round frame. On the map they look as the addon draws them.")
    L:Slider("Icon size in the bar", 14, 40, 1, Opt(M, "barIconSize"))
    L:Slider("Closes after", 3, 30, 1, function() return M().barTimeout end, function(v) M().barTimeout = v end, "%d s")
    Element(L, "Addon bar button", function() return M().icons.addonbar end)
    L:Note("In unlock mode (/huf unlock) the tracking button and this button can be dragged anywhere.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("On the map (addon bar off)")
    R:Cycle("Every addon button", ns.Minimap.MODES, Opt(M, "buttonMode"))
    -- one row per addon button found on the map (filled when the page shows)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", COL2_X, R.y - 4)
    list:SetSize(COL_W, 360)
    list.rows = {}
    list.empty = UI.Label(list, "No addon buttons found on the minimap.")
    list.empty:SetPoint("TOPLEFT")
    list.empty:SetTextColor(0.6, 0.6, 0.6)
    local CHOICES = { { value = "DEFAULT", text = "Like every button" } }
    for _, m in ipairs(ns.Minimap.MODES) do CHOICES[#CHOICES + 1] = m end
    list.Refresh = function()
        local l = ns.Minimap.Buttons()
        for i, b in ipairs(l) do
            local row = list.rows[i]
            if not row then
                row = UI.Dropdown(list, COL_W, "", CHOICES,
                    function() local k = row.key return k and M().buttons[k] or "DEFAULT" end,
                    function(v) if row.key then M().buttons[row.key] = (v ~= "DEFAULT") and v or nil end end)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * (UI.ROW + 2))
                list.rows[i] = row
            end
            row.key = b.key
            row.label:SetText(b.text)       -- the addon's name
            row:Show()
            row.Refresh()
        end
        for i = #l + 1, #list.rows do list.rows[i]:Hide() end
        list.empty:SetShown(#l == 0)
    end
    page.widgets = page.widgets or {}
    table.insert(page.widgets, list)
    f:HookScript("OnShow", list.Refresh)
end

ns.RegisterPage("minimap", "Minimap", "frames", function(page)
    local on = UI.Check(page, 260, "Use HUF's minimap", function() return M().enabled end,
        function(v) M().enabled = v end, "Shape, size, look, texts and icons of the minimap. Off: Blizzard's minimap after /reload.")
    on:SetPoint("TOPLEFT", 0, 4)
    local tabs = { { "map", "Map" }, { "texts", "Texts" }, { "icons", "Icons" }, { "buttons", "Addon buttons" } }
    local subs, strip = {}, nil
    local function Show(k)
        for name, sf in pairs(subs) do sf:SetShown(name == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, function(k) Show(k) end)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.map = SubFrame(page); MapPage(subs.map)
    subs.texts = SubFrame(page); TextsPage(subs.texts)
    subs.icons = SubFrame(page); IconsPage(subs.icons)
    subs.buttons = SubFrame(page); ButtonsPage(subs.buttons, page)
    if strip.Bind then strip:Bind(subs, Show) end
    Show("map")
end, function() return ns.db.minimap.enabled end)
