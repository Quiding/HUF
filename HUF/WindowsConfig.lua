-- HUF: settings page for moving the game's windows (GENERAL > Windows).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function S() return ns.db.windows end

ns.RegisterPage("windows", "Windows", "general", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("The game's windows")
    L:Check("Move them by dragging", function() return S().enabled end, function(v)
        S().enabled = v
        if v then ns.Windows.Apply() else ns.Print("The windows stay where they are until /reload.") end
    end, "Character, spellbook, professions, quests, map, mail, merchant, bank, friends, guild and more: drag an empty part of a window. Its new place is remembered.")
    L:Check("Only while Shift is held", function() return S().shift end, function(v) S().shift = v end,
        "Drag with Shift held, so a window doesn't move by accident.")
    L:Header("Back to the game's place")
    L:Button("Reset every window", function()
        UI.Confirm("Put every moved window back where the game puts it?", "Reset", function() ns.Windows.ResetAll() end)
    end)
    L:Note("One window: Shift + right-click on an empty part of it.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Notes")
    R:Note("Windows the game protects (some open in combat) can't be moved during a fight; they go to their place when it ends.")
    R:Note("The places are part of the profile (and of a profile export).")
end, function() return ns.db.windows.enabled end)
