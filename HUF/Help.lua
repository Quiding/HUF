-- HUF: Help page (GENERAL section): debug tools with a how-to, commands and
-- a short guide for the API other addons (MMT) can use.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local COL_W, COL2_X = 330, 366

---------------------------------------------------------------------------
-- Text window: shows a long text selected, ready for Ctrl+C
---------------------------------------------------------------------------
local textWindow
function ns.ShowText(title, text)
    if not textWindow then
        local f = CreateFrame("Frame", "HUFTextWindow", UIParent)
        f:SetSize(760, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.97)
        UI.Border(f, A[1], A[2], A[3], 0.6)
        f.title = UI.Label(f, "", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 14, -12)
        local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
        close:SetPoint("TOPRIGHT", -8, -8)
        f.area = UI.TextArea(f, 732, 432)
        f.area:SetPoint("TOPLEFT", 14, -36)
        local e = f.area.edit
        e:SetMaxLetters(0)
        -- read-only: typing puts the text back
        e:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(f.value or "") end
        end)
        local select = UI.Button(f, 140, "Select all", function()
            e:SetFocus()
            e:HighlightText()
        end)
        select:SetPoint("BOTTOMLEFT", 14, 14)
        local hint = UI.Label(f, "Select all, then Ctrl+C to copy. Paste it to Claude.")
        hint:SetPoint("LEFT", select, "RIGHT", 12, 0)
        hint:SetTextColor(0.6, 0.6, 0.6)
        UI.CloseOnEscape(f)
        textWindow = f
    end
    local f = textWindow
    -- "Keep real names in the log" off: MMT's privacy names (team members)
    local rec = ns.Recorder and ns.Recorder.DB()
    local m = ns.Bridge and ns.Bridge.MMT()
    if rec and not rec.keepNames and m and type(m.ReplaceNames) == "function" then
        local ok, t = pcall(m.ReplaceNames, text, true)
        if ok and type(t) == "string" then text = t end
    end
    f.value = text
    f.title:SetText(title or "")
    f:SetScale(ns.ConfigScale and ns.ConfigScale() or 1)
    f:Show()
    f.area.edit:SetText(text)
    f.area.edit:SetCursorPosition(0)
    f.area.edit:SetFocus()
    f.area.edit:HighlightText()
end

---------------------------------------------------------------------------
-- /huf debug [on | off | report | log | clear | chat | frames]
---------------------------------------------------------------------------
function ns.HandleDebugCommand(arg)
    arg = ns.Trim(arg or ""):lower()
    if arg == "" then
        ns.SetDebug(not ns.DebugOn())
        ns.Print("Debug log %s.", ns.DebugOn() and "on" or "off")
    elseif arg == "on" or arg == "off" then
        ns.SetDebug(arg == "on")
        ns.Print("Debug log %s.", ns.DebugOn() and "on" or "off")
    elseif arg == "report" or arg == "dump" then
        ns.ShowText("HUF debug report", ns.DebugReport())
    elseif arg == "log" then
        ns.ShowText("HUF debug log", ns.LogText())
    elseif arg == "clear" then
        ns.ClearLog()
        ns.Print("Debug log cleared.")
    elseif arg == "chat" then
        HUFDB.debug.chat = not HUFDB.debug.chat
        ns.Print("Log lines in chat %s.", HUFDB.debug.chat and "on" or "off")
    elseif arg == "frames" then
        local was = ns.DebugOn()
        if not was then ns.SetDebug(true) end
        ns.LogFrames("frame state (/huf debug frames)")
        if not was then ns.SetDebug(false) end
        ns.Print("Frame state written to the log.")
    elseif arg == "help" then
        ns.ToggleConfig("help", true)
    else
        ns.Print("/huf debug [on|off|report|log|clear|chat|frames]")
    end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local STEPS = table.concat({
    "1. Tick \"Debug log\" (or type /huf debug).",
    "2. Press \"Clear log\" so the report only shows the new problem.",
    "3. For problems right after login: tick the log, then /reload.",
    "4. Do what goes wrong: target something, open a menu, join a group, change a setting ...",
    "5. Press \"Frame state\" while the problem is visible.",
    "6. Press \"Debug report\", then Select all and Ctrl+C, and paste it to Claude.",
}, "\n")

local COMMANDS = table.concat({
    "/huf help                  this page",
    "/huf debug                 debug log on/off",
    "/huf debug report          copyable report (also /huf status)",
    "/huf debug log | clear     show or clear the log",
    "/huf debug chat            also print log lines to chat",
    "/huf debug frames          write the state of every frame to the log",
    "/huf rec [on|off|now]      data recorder on/off, one snapshot now",
    "/huf unlock | lock         move frames (previews)",
    "/huf mmt                   state of the link to MMT",
}, "\n")

local API = [[
-- HUF's public table: _G.HUF (API_VERSION 1)

-- show other names on HUF's frames (e.g. a privacy setting):
-- fn(unit, first, last) returns the name to show, or nil
HUF.RegisterNameProvider("MyAddon", function(unit, first, last)
    if first == "Gunter" then return "Tank 1" end
end)
HUF.RefreshNames()          -- your names changed: redraw them

HUF.Refresh(true)           -- re-apply every HUF setting
HUF.ToggleConfig("target", true) -- open the settings (a page)
HUF.Bridge.Status()         -- { loaded, version, mode, teamSize, active }

-- MMT needs nothing: HUF reads MMT.db.privacy and the team, and hooks
-- MMT.PrivacyChanged, so names follow MMT > Team > Privacy at once.
]]

local function CodeBox(parent, width, height, text)
    local area = UI.TextArea(parent, width, height)
    local e = area.edit
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text) end end)
    return area
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
ns.RegisterPage("help", "Help", "general", function(page)
    local subs, strip = {}, nil
    local function Show(k)
        for name, sf in pairs(subs) do sf:SetShown(name == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, { { "log", "Debug log" }, { "rec", "Data recorder" }, { "cmd", "Commands & API" } }, Show)
    strip:SetPoint("TOPLEFT", 0, -2)
    strip:SetPoint("TOPRIGHT", 0, -2)
    local function Sub()
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", 0, -36)
        f:SetSize(ns.PAGE_W, ns.PAGE_H - 36)
        return f
    end
    local half = (COL_W - 8) / 2

    -- Debug log ---------------------------------------------------------
    local f = Sub()
    subs.log = f
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Debug log")
    L:Check("Debug log", function() return ns.DebugOn() end, function(v) ns.SetDebug(v) end,
        "Logs what HUF does: frames made and placed, units, shown / hidden, clicks, setting changes, combat queue, MMT link. Errors are always logged. The log keeps the last 4000 lines and survives /reload.")
    L:Check("Also print log lines to chat", function() return HUFDB.debug.chat end,
        function(v) HUFDB.debug.chat = v end)
    local size = UI.Label(f, "")
    size:SetTextColor(0.6, 0.6, 0.6)
    L:Add(size)
    table.insert(page.widgets, { Refresh = function()
        size:SetText(("%d lines in the log."):format(#(HUFDB.debug.log or {})))
    end })
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Copy and clear")
    local report = UI.Button(f, half, "Debug report", function() ns.HandleDebugCommand("report") end)
    R:Add(report, 0)
    UI.Tooltip(report, "Debug report", "Client, settings, the state of every frame and the log in one text to copy.")
    local log = UI.Button(f, half, "Show log", function() ns.HandleDebugCommand("log") end)
    log:SetPoint("LEFT", report, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)
    local clear = UI.Button(f, half, "Clear log", function() ns.HandleDebugCommand("clear") end)
    R:Add(clear, 0)
    local frames = UI.Button(f, half, "Frame state", function() ns.HandleDebugCommand("frames") end)
    frames:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    UI.Tooltip(frames, "Frame state", "Writes where every HUF frame is, whether it is shown, its size, unit and texts into the log.")
    R:Space(UI.ROW + 2)
    local col = UI.Column(f, 0, math.min(L.y, R.y) - 8, ns.PAGE_W)
    col:Header("How to report a problem")
    col:Note(STEPS)

    -- Data recorder -----------------------------------------------------
    f = Sub()
    subs.rec = f
    local D = function() return ns.Recorder.DB() end
    L = UI.Column(f, 0, 0, COL_W)
    L:Header("Data recorder")
    L:Check("Record unit data", function() return D().enabled end, function(v) ns.Recorder.SetEnabled(v) end,
        "Writes what the client hands out about the units below into the log while you play: names in every form, class, level, health, power, states, and which values the client hides (SECRET). Works without the debug log.")
    L:MultiDropdown("Units", ns.Recorder.UNIT_CHOICES,
        function(v) return D().units[v] end,
        function(v) D().units[v] = not D().units[v] end)
    L:Slider("Check every (seconds)", 0.2, 10, 0.1, function() return D().interval end,
        function(v) D().interval = v ns.Recorder.Restart() end, "%.1f")
    local gc, sc = function() return D().changesOnly end, function(v) D().changesOnly = v end
    L:Check("Only when something changed", gc, sc, "A unit's line is written again only when one of its values changed. Off: every check writes every unit (a lot of lines).")
    L:Check("Health and power values", function() return D().values end, function(v) D().values = v end)
    L:Check("Hidden values (C_Secrets)", function() return D().secrets end, function(v) D().secrets = v end,
        "Asks the client's C_Secrets functions for each unit: what it says it hides right now.")
    L:Check("Buffs and debuffs (first 5)", function() return D().auras end, function(v) D().auras = v end)
    L:Check("Keep real names in the log", function() return D().keepNames end, function(v) D().keepNames = v end,
        "Off: when you open the log or report, names of your MMT team are shown the way MMT's privacy setting says.")

    R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Record")
    local now = UI.Button(f, half, "Snapshot now", function()
        ns.Recorder.Now()
        ns.Print("Snapshot written to the log.")
        ns.RefreshConfig()
    end)
    R:Add(now, 0)
    UI.Tooltip(now, "Snapshot now", "Writes every chosen unit into the log right now, changed or not (also /huf rec now).")
    local show = UI.Button(f, half, "Show log", function() ns.HandleDebugCommand("log") end)
    show:SetPoint("LEFT", now, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)
    local clr = UI.Button(f, half, "Clear log", function() ns.HandleDebugCommand("clear") end)
    R:Add(clr, 0)
    local rep = UI.Button(f, half, "Debug report", function() ns.HandleDebugCommand("report") end)
    rep:SetPoint("LEFT", clr, "RIGHT", 8, 0)
    R:Space(UI.ROW + 6)
    R:Note("How to use it:\n1. Clear log, tick \"Record unit data\".\n2. Play: target things, group up, fight, change zone.\n3. Untick it, press Show log, Select all, Ctrl+C, paste it to Claude.")
    R:Note("Each line: unit, how many values were SECRET, then name=value pairs. \"SECRET\" = the client hides it, \"ERR\" = the call failed, \"n/a\" = this client has no such function. Unusual characters in names show as byte codes, e.g. <c2><a0>.")
    local stat = UI.Label(f, "")
    stat:SetTextColor(0.6, 0.6, 0.6)
    R:Add(stat)
    table.insert(page.widgets, { Refresh = function()
        stat:SetText(("Recorder %s, %d lines in the log."):format(D().enabled and "|cff66dd66on|r" or "off", #(HUFDB.debug.log or {})))
    end })

    -- Commands & API ----------------------------------------------------
    f = Sub()
    subs.cmd = f
    col = UI.Column(f, 0, 0, ns.PAGE_W)
    col:Header("Commands")
    col:Add(CodeBox(f, ns.PAGE_W, 128, COMMANDS), 136)
    col:Header("For addon authors")
    col:Add(CodeBox(f, ns.PAGE_W, 190, API), 198)

    Show("log")
end)
