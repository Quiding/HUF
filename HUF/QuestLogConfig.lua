-- HUF: settings page for the classic quest log (GENERAL > Utility Frames > Quest Log).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function Q() return ns.db.questLog end
local function Redraw() if ns.QuestLog then ns.QuestLog.Look() ns.QuestLog.Refresh() end end
local function Opt(k) return function() return Q()[k] end, function(v) Q()[k] = v Redraw() end end

local function Fonts()
    local l = { { value = "CLASSIC", text = "The game's quest fonts" }, { value = "GLOBAL", text = "HUF Global Font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local OUTLINES = {
    { value = "GLOBAL", text = "HUF Global Outline" }, { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
}

ns.RegisterPage("questlog", "Quest Log", "utility", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Quest log").hufNoGate = true
    local master = L:Check("Use HUF's classic quest log", function() return Q().enabled end, function(v)
        Q().enabled = v
        if v then ns.QuestLog.Apply() else ns.AskReload("The game's quest window comes back after a reload.") end
    end, "The quest log as in the original game: the quest list over the quest's text, objectives and rewards. The quest log key opens it instead of the map + quest window; the map key still opens the map.")
    local gt, st = Opt("tracker")
    L:Check("Also from the quest tracker", gt, st, "A click on a quest in the tracker opens it here (not while the map is open: there the map shows it).")
    local gl, sl = Opt("levels")
    L:Check("Levels before the quest names", gl, sl, "\"[35] Name\" in the difficulty colour; \"+\" for group quests.")
    L:Button("Open the quest log", function() ns.QuestLog.Show() end)
    L:Header("Own categories")
    L:Note("Right-click a quest: move it into a category of your own (or a new one), or back to its zone. Your categories show above the zones, in light blue. Right-click a category: rename, move up / down, delete.")
    L:Note("Shift + click a quest tracks it.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Cycle("Layout", { { value = "DUAL", text = "Two sides (list left, quest right)" }, { value = "CLASSIC", text = "One column (the original window)" } },
        function() return Q().layout end, function(v) Q().layout = v if ns.QuestLog then ns.QuestLog.Rebuild() end end)
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Text size", 9, 20, 1, Opt("fontSize"))
    R:Cycle("Outline", OUTLINES, Opt("outline"))
    R:Note("Text size works for both; the outline only for the HUF fonts. The title grows with it.")
    R:Slider("Scale", 0.5, 2, 0.05, function() return Q().scale end, function(v) Q().scale = v ns.QuestLog.Look() end, "%.2f")
    R:Button("Back to the middle", function()
        Q().point = { "CENTER", "CENTER", 0, 40 }
        ns.QuestLog.Look()
    end)
    R:Header("For addon authors")
    R:Note("HUF.QuestLog (API 1): GetCategories(), GetCategory(questID), SetCategory(questID, name), GetSections(), Listen(fn) - see QuestLog.lua.")
    -- everything else waits for the switch
    UI.Gate(page, master, function() return Q().enabled end)
end, function() return ns.db.questLog.enabled end)
