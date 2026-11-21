-- HUF: settings page for the classic quest log (FRAMES > Quest log).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function Q() return ns.db.questLog end
local function Opt(k) return function() return Q()[k] end, function(v) Q()[k] = v if ns.QuestLog then ns.QuestLog.Look() ns.QuestLog.Refresh() end end end

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local OUTLINES = {
    { value = "GLOBAL", text = "General outline" }, { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
}

ns.RegisterPage("questlog", "Quest log", "frames", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Quest log")
    L:Check("Use HUF's classic quest log", function() return Q().enabled end, function(v)
        Q().enabled = v
        if v then ns.QuestLog.Apply() else ns.Print("The game's quest window comes back after /reload.") end
    end, "The quest list on the left, the quest's text, objectives and rewards on the right. The quest log key opens it instead of the map + quest window; the map key still opens the map.")
    local gt, st = Opt("tracker")
    L:Check("Also from the quest tracker", gt, st, "A click on a quest in the tracker opens it here (not while the map is open: there the map shows it).")
    local gl, sl = Opt("levels")
    L:Check("Levels before the quest names", gl, sl, "\"[35] Name\" in the difficulty colour; \"+\" for group quests.")
    L:Button("Open the quest log", function() ns.QuestLog.Show() end)
    L:Note("In the list: click a header to fold it, Shift + click a quest to track it.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Cycle("Font", Fonts, Opt("font"))
    R:Slider("Text size", 8, 20, 1, Opt("fontSize"))
    R:Slider("Title size", 10, 24, 1, Opt("titleSize"))
    R:Cycle("Outline", OUTLINES, Opt("outline"))
    R:Slider("Scale", 0.5, 2, 0.05, function() return Q().scale end, function(v) Q().scale = v ns.QuestLog.Look() end, "%.2f")
    R:Color("Background", Opt("bgColor"))
    R:Slider("Background opacity", 0, 1, 0.05, function() return Q().bgAlpha end, function(v) Q().bgAlpha = v ns.QuestLog.Look() end, "%.2f")
    R:Button("Back to the middle", function()
        Q().point = { "CENTER", "CENTER", 0, 40 }
        ns.QuestLog.Look()
    end)
end, function() return ns.db.questLog.enabled end)
