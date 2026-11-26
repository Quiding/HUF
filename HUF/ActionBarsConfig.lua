-- HUF: settings page for the action bars (General > Action Bars, ActionBars.lua).
-- One set of controls; the "Bar" list at the top picks which bar they change.

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local sel = "MainBar"

ns.RegisterPage("actionbars", "Action Bars", "general", function(page)
    local AB = ns.ActionBars
    local D = function() return ns.db.actionBars end
    local B = function() return D().bars[sel] end
    local function Opt(k) return function() return B()[k] end, function(v) B()[k] = v end end
    local function Max() local info = AB.BY and AB.BY[sel] return info and info.count or 12 end

    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Action bars")
    L:Check("Use HUF's action bars", function() return D().enabled end, function(v)
        D().enabled = v
        if v then AB.Apply() else ns.AskReload("The game's action bars come back after a reload.") end
    end, "The game's own action buttons in HUF's bars: placed and sized by HUF, in a flat look. Key bindings, cooldowns, stances and forms work as before. Off: the game's bars, untouched.")
    local choices = {}
    for _, info in ipairs(AB.BARS) do choices[#choices + 1] = { value = info.key, text = info.label } end
    L:Cycle("Bar", choices, function() return sel end, function(v)
        sel = v
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, "Which bar the settings below change.")
    local ge, se = Opt("enabled")
    L:Check("Show this bar", ge, function(v)
        se(v)
        if v then AB.Apply()
        elseif AB.Taken(sel) then ns.AskReload("The game's own bar comes back after a reload.") end
    end, "Off: HUF leaves the game's bar alone (it is back after a reload if HUF had taken it).")
    L:Slider("Buttons", 1, 12, 1, function() return math.min(B().buttons or 12, Max()) end, function(v) B().buttons = math.min(v, Max()) end).EnableInput()
    L:Slider("Buttons per row", 1, 12, 1, Opt("perRow")).EnableInput()
    L:Slider("Button size", 16, 64, 1, Opt("size")).EnableInput()
    L:Slider("Spacing", 0, 20, 1, Opt("spacing")).EnableInput()
    local gm, sm = Opt("mouseover")
    L:Check("Only on mouseover", gm, function(v) sm(v) AB.Fade() end,
        "The bar shows while the mouse is over it, or while you drag a spell or item.")
    local gh, sh = Opt("hideHotkey")
    L:Check("Hide key bindings", gh, sh)
    local gn, sn = Opt("hideMacro")
    L:Check("Hide macro names", gn, sn)
    L:Note("Move the bars in unlock mode (/huf unlock); right-click a bar's box for its settings. Changes wait until combat ends.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Look (every bar)")
    R:Slider("Border", 0, 3, 1, function() return D().border end, function(v) D().border = v end)
    R:Check("Border in the accent colour", function() return D().borderAccent end, function(v) D().borderAccent = v end)
    R:Color("Border colour", function() return D().borderColor end, function(c) D().borderColor = c end)
    R:Slider("Slot background", 0, 1, 0.05, function() return D().slotAlpha end, function(v) D().slotAlpha = v end, "%.2f")
    R:Header("EllesmereUI")
    local msg = UI.Label(page, "")
    msg:SetWidth(COL_W)
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)
    R:Button("Import EllesmereUI's action bars", function()
        local ok, text = AB.ImportEllesmere()
        msg:SetText(ok and ("|cff60ff60" .. text .. "|r") or ("|cffff6060" .. text .. "|r"))
        if ok and ns.RefreshConfig then ns.RefreshConfig() end
    end)
    R:Add(msg, 54)
    R:Note("Takes each bar's buttons, rows, size, spacing, place, mouseover and hidden texts. Works while EllesmereUI is on (also with its action bars off), and from the copy HUF keeps of them once EllesmereUI is switched off.")
    local copy = HUFDB and HUFDB.ellesmereActionBars
    if copy and copy.time then
        R:Note(("Copy kept: %s."):format(date("%Y-%m-%d %H:%M", copy.time)))
    end
    page.OpenTab = function(key)
        if AB.BY and AB.BY[key] then sel = key end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
end, function() return ns.db.actionBars.enabled end)
