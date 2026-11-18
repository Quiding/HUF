-- HUF: configuration window (/huf). Same layout and look as MMT's window:
-- navigation on the left (GENERAL pages, then one entry per frame with its
-- on/off state), the selected page on the right.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local WIDTH, HEIGHT, NAV = 880, 620, 150
local NAV_ROW, NAV_HEAD, NAV_TOP = 26, 22, -58
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2.0, 0.05
ns.PAGE_W, ns.PAGE_H = WIDTH - NAV - 32, HEIGHT - 56

local window
local pages, order = {}, {}
local current

-- section: "general" or "frames"; isOn(): nil = no on/off state
function ns.RegisterPage(key, title, section, build, isOn)
    pages[key] = { key = key, title = title, section = section, build = build, isOn = isOn }
    order[#order + 1] = key
end

local function RefreshPage(page)
    if not page or not page.frame then return end
    if page.frame.OnRefresh then pcall(page.frame.OnRefresh) end
    for _, w in ipairs(page.frame.widgets) do w.Refresh() end
end

local function RefreshNav()
    if not window then return end
    for _, tab in ipairs(window.tabs) do tab.Update() end
    for _, wd in ipairs(window.navWidgets) do wd.Refresh() end
end

function ns.RefreshConfig()
    if window and window:IsShown() then
        if window.ApplyLook then window.ApplyLook() end
        RefreshPage(pages[current])
        RefreshNav()
    end
end
ns.OnRefresh(function() ns.RefreshConfig() end)
ns.Listen("PROFILE_CHANGED", function() ns.RefreshConfig() end)

local function Select(key)
    if not pages[key] then key = "general" end
    current = key
    ns.Log("config", "page %s", key)
    for k, page in pairs(pages) do
        local selected = (k == key)
        if selected and not page.frame then
            local frame = CreateFrame("Frame", nil, window)
            frame:SetPoint("TOPLEFT", NAV + 16, -44)
            frame:SetSize(ns.PAGE_W, ns.PAGE_H)
            frame.widgets = {}
            page.build(frame)
            page.frame = frame
        end
        if page.frame then page.frame:SetShown(selected) end
    end
    window.pageTitle:SetText(pages[key].title)
    RefreshPage(pages[key])
    RefreshNav()
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function Tab(parent, page)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV, NAV_ROW)
    local bg = UI.Fill(b, 1, 1, 1, 0)
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(A[1], A[2], A[3], 1)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    local label = UI.Label(b, page.title, "GameFontNormal")
    label:SetPoint("LEFT", 16, 0)
    local state = UI.Label(b, "")
    state:SetPoint("RIGHT", -10, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
    b.Update = function()
        local selected = (current == page.key)
        bar:SetShown(selected)
        bg:SetColorTexture(1, 1, 1, selected and 0.06 or 0)
        if page.isOn and not page.isOn() then
            label:SetTextColor(0.4, 0.4, 0.4)
            state:SetText("off")
            state:SetTextColor(0.4, 0.4, 0.4)
        else
            if selected then label:SetTextColor(1, 1, 1) else label:SetTextColor(0.65, 0.65, 0.65) end
            state:SetText("")
        end
    end
    b:SetScript("OnClick", function() Select(page.key) end)
    return b
end

local function Header(parent, text, y)
    local l = UI.Label(parent, text)
    l:SetPoint("TOPLEFT", 16, y - 4)
    l:SetTextColor(A[1], A[2], A[3], 0.8)
end

local function Build()
    local w = CreateFrame("Frame", "HUFConfigFrame", UIParent)
    w:SetSize(WIDTH, HEIGHT)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    UI.CloseOnEscape(w)
    w.tabs = {}

    UI.Fill(w, 0.03, 0.03, 0.04, 0.96)
    -- background picture (General > Settings window), under everything
    w.art = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.art:SetPoint("TOPLEFT", 1, -1)
    w.art:SetPoint("BOTTOMRIGHT", -1, 1)
    -- a thin accent line along the top
    w.topLine = w:CreateTexture(nil, "ARTWORK")
    w.topLine:SetPoint("TOPLEFT", 1, -1)
    w.topLine:SetPoint("TOPRIGHT", -1, -1)
    w.topLine:SetHeight(1)
    UI.Border(w, 0.22, 0.22, 0.24, 1)

    local nav = CreateFrame("Frame", nil, w)
    nav:SetPoint("TOPLEFT", 1, -1)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(NAV)
    UI.Fill(nav, 1, 1, 1, 0.025)
    local divider = w:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetPoint("TOPLEFT", nav, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT")
    divider:SetWidth(1)

    local logo = nav:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOPLEFT", 10, -8)
    logo:SetTexture(ns.LOGO)
    local title = UI.Label(nav, "HUF", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 50, -14)
    title:SetTextColor(A[1], A[2], A[3])
    local sub = UI.Label(nav, "Hivemind Unitframes")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.6, 0.6, 0.6)

    local y = NAV_TOP
    for _, section in ipairs({ { "general", "GENERAL" }, { "frames", "FRAMES" } }) do
        Header(nav, section[2], y)
        y = y - NAV_HEAD
        for _, key in ipairs(order) do
            local page = pages[key]
            if page.section == section[1] then
                local tab = Tab(nav, page)
                tab:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, y)
                y = y - NAV_ROW
                w.tabs[#w.tabs + 1] = tab
            end
        end
        y = y - 6
    end

    -- footer: unlock, window scale, version
    nav.widgets = {}
    local unlock = UI.Button(nav, NAV - 24, "Unlock frames", function() ns.Movers.Toggle() end)
    unlock:SetPoint("BOTTOMLEFT", 12, 56)
    UI.Tooltip(unlock, "Unlock frames", "Shows a preview of every frame that is on. Drag a preview to move the frame, right-click it for its settings. Also /huf unlock.")
    table.insert(nav.widgets, { Refresh = function()
        unlock.label:SetText(ns.unlocked and "Lock frames" or "Unlock frames")
        if ns.unlocked then unlock.label:SetTextColor(A[1], A[2], A[3]) else unlock.label:SetTextColor(1, 1, 1) end
    end })

    local version = UI.Label(nav, "v" .. ns.version)
    version:SetPoint("BOTTOMLEFT", 16, 12)
    version:SetTextColor(0.4, 0.4, 0.4)
    local scaleLabel = UI.Label(nav, "")
    scaleLabel:SetPoint("BOTTOMLEFT", 16, 32)
    scaleLabel:SetTextColor(0.6, 0.6, 0.6)
    local plus = UI.TextButton(nav, "+", function() ns.SetConfigScale(ns.ConfigScale() + SCALE_STEP) end, 18)
    plus:SetPoint("BOTTOMRIGHT", -10, 28)
    local minus = UI.TextButton(nav, "-", function() ns.SetConfigScale(ns.ConfigScale() - SCALE_STEP) end, 18)
    minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    for _, b in ipairs({ plus, minus }) do
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local click = b:GetScript("OnClick")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then ns.SetConfigScale(1) else click(self, button) end
        end)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Window scale")
            GameTooltip:AddLine("Size of this settings window. Right-click to reset to 100%. Also /huf scale <percent>.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table.insert(nav.widgets, { Refresh = function()
        scaleLabel:SetText(("Scale %d%%"):format(math.floor(ns.ConfigScale() * 100 + 0.5)))
    end })
    w.navWidgets = nav.widgets
    w:SetScale(ns.ConfigScale())

    w.pageTitle = UI.Label(w, "", "GameFontNormalLarge")
    w.pageTitle:SetPoint("TOPLEFT", NAV + 16, -14)
    local close = UI.TextButton(w, "x", function() w:Hide() end, 20)
    close:SetPoint("TOPRIGHT", -8, -8)

    function w.ApplyLook()
        ns.Frame.SetBackground(w.art, ns.db.global.configBg, { r = 1, g = 1, b = 1 }, 0.55)
        w.topLine:SetColorTexture(A[1], A[2], A[3], 0.8)
    end
    w:SetScript("OnShow", function()
        w.ApplyLook()
        Select(current or "general")
    end)
    w:SetScript("OnHide", function() w:SetFrameStrata("DIALOG") end)
    return w
end

---------------------------------------------------------------------------
-- Window scale (account-wide)
---------------------------------------------------------------------------
function ns.ConfigScale()
    return (HUFDB and tonumber(HUFDB.configScale)) or 1
end

function ns.SetConfigScale(v)
    v = math.floor(math.max(SCALE_MIN, math.min(SCALE_MAX, v)) * 20 + 0.5) / 20
    HUFDB.configScale = v
    if window then
        window:SetScale(v)
        RefreshNav()
    end
    return v
end

-- key: page key ("general", "player", "raid", ...); open: never close
-- not in combat: settings changes can touch secure frames (and a reload is
-- refused), so the window stays closed while fighting and opens after
local reopen   -- page to open when combat ends (false: none)
function ns.ToggleConfig(key, open)
    if InCombatLockdown() then
        if not (window and window:IsShown()) then
            reopen = key or current or "general"
            ns.Print("The settings open when the fight is over.")
        end
        return
    end
    window = window or Build()
    if key and pages[key] then
        current = key
        if window:IsShown() then Select(key) return end
    end
    if open then window:Show() else window:SetShown(not window:IsShown()) end
end

---------------------------------------------------------------------------
-- Game options entry (Esc > Options > AddOns > HUF)
---------------------------------------------------------------------------
ns.OnLogin(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexture(ns.LOGO)
    local t = UI.Label(panel, "HUF - Hivemind Unitframes", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 68, -22)
    local open = UI.Button(panel, 160, "Open settings", function()
        window = window or Build()
        window:SetFrameStrata("FULLSCREEN_DIALOG")
        window:Show()
    end)
    open:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "HUF")
    Settings.RegisterAddOnCategory(category)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
-- combat starts: the settings and their dialogs close (back after the fight)
ns.On("PLAYER_REGEN_DISABLED", function()
    if window and window:IsShown() then
        reopen = current or "general"
        window:Hide()
        ns.Print("Settings closed for the fight; they open again when it's over.")
    end
    for _, name in ipairs({ "HUFEllesmereImportFrame", "HUFConfirmFrame" }) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if reopen then
        local key = reopen
        reopen = false
        ns.ToggleConfig(key, true)
    end
end)

SLASH_HUF1 = "/huf"
SlashCmdList.HUF = function(msg)
    local raw = ns.Trim(msg)
    local cmd, arg = raw:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    ns.Log("config", "/huf %s", raw)
    if not ns.ready then ns.Print("HUF hasn't finished loading. If this stays, send a debug report (/huf debug report).") if cmd ~= "debug" then return end end
    if cmd == "" or cmd == "config" then
        ns.ToggleConfig()
    elseif cmd == "unlock" or cmd == "move" or cmd == "test" then
        ns.Movers.SetUnlocked(true)
    elseif cmd == "lock" then
        ns.Movers.SetUnlocked(false)
    elseif ns.UNIT_BY_KEY[cmd] then
        ns.ToggleConfig(cmd, true)
    elseif cmd == "scale" then
        local pct = tonumber((arg or ""):match("^(%d+)"))
        if pct then
            local v = ns.SetConfigScale(pct / 100)
            ns.Print("Settings window scale: %d%%.", math.floor(v * 100 + 0.5))
        else
            ns.Print("Use /huf scale <percent>, e.g. /huf scale 130 (60 to 200).")
        end
    elseif cmd == "debug" or cmd == "help" or cmd == "status" then
        ns.HandleDebugCommand(cmd == "status" and "report" or (cmd == "help" and "help" or arg))
    elseif cmd == "rec" or cmd == "record" then
        local a = (arg or ""):lower()
        if a == "now" then ns.Recorder.Now() ns.Print("Snapshot written to the log.")
        else
            local on = (a == "on") or (a ~= "off" and not ns.Recorder.DB().enabled)
            ns.Recorder.SetEnabled(on)
            ns.Print("Data recorder %s.", on and "on" or "off")
        end
        if ns.RefreshConfig then ns.RefreshConfig() end
    elseif cmd == "meter" or cmd == "dm" then
        if ns.DamageMeter then ns.DamageMeter.Toggle() end
    elseif cmd == "mmt" then
        local st = ns.Bridge.Status()
        ns.Print("MMT %s%s, privacy: %s, team: %d, HUF uses it: %s, privacy interface: v%s (HUF knows v%d).",
            st.loaded and "loaded" or "not loaded", st.version and (" (v" .. st.version .. ")") or "",
            ns.Bridge.ModeText(st.mode), st.teamSize, st.active and "yes" or "no",
            tostring(st.api or "-"), st.apiExpected)
    elseif cmd == "reset" then
        ns.ResetProfile()
        ns.Print("Profile \"%s\" reset to defaults.", ns.CurrentProfileName())
    else
        ns.Print("/huf - open settings")
        ns.Print("/huf unlock | lock - move frames (with previews)")
        ns.Print("/huf <frame> - settings of a frame (player, target)")
        ns.Print("/huf mmt - state of the link to MMT")
        ns.Print("/huf scale <percent> - size of the settings window")
        ns.Print("/huf reset - reset the active profile")
        ns.Print("/huf help - help and debug tools")
        ns.Print("/huf debug - debug log on/off (report, log, clear, chat)")
        ns.Print("/huf rec [on|off|now] - data recorder (names, values, hidden values)")
    end
end
