-- HUF: the pages of the configuration window.
-- GENERAL: General, Names & MMT, Profiles, Help. FRAMES: one page per frame
-- with sub pages: Frame, Health bar, Power bar, Texts, Buffs & debuffs.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local COL_W = 330
local COL2_X = 366
local TOP = -36

local function U(key) return ns.db.units[key] end

-- getter / setter pair for field `k` of the table tbl() returns
local function Opt(tbl, k)
    return function() return tbl()[k] end,
           function(v) tbl()[k] = v end
end

local function FontChoices(withGlobal)
    local l = {}
    if withGlobal then l[1] = { value = "GLOBAL", text = "General font" } end
    local blizz, eui = {}, {}
    for _, f in ipairs(ns.fonts) do
        if f.ellesmere then eui[#eui + 1] = f else blizz[#blizz + 1] = f end
    end
    for _, f in ipairs(blizz) do l[#l + 1] = { value = f.name, text = f.name } end
    if #eui > 0 then
        l[#l + 1] = { header = true, text = "EllesmereUI" }
        for _, f in ipairs(eui) do l[#l + 1] = { value = f.name, text = f.name } end
    end
    return l
end

local function TextureChoices()
    local l, eui = {}, {}
    for _, t in ipairs(ns.textures) do
        if t.ellesmere then eui[#eui + 1] = t else l[#l + 1] = { value = t.name, text = t.name } end
    end
    if #eui > 0 then
        l[#l + 1] = { header = true, text = "EllesmereUI" }
        for _, t in ipairs(eui) do l[#l + 1] = { value = t.name, text = t.name } end
    end
    return l
end

local function BackgroundChoices()
    local l = {}
    for _, b in ipairs(ns.backgrounds) do l[#l + 1] = { value = b.name, text = b.name } end
    return l
end

local OUTLINES = {
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" },
    { value = "THICKOUTLINE", text = "Thick" },
    { value = "MONOCHROME,OUTLINE", text = "Mono" },
}
local OUTLINES_G = { { value = "GLOBAL", text = "General outline" } }
for _, o in ipairs(OUTLINES) do OUTLINES_G[#OUTLINES_G + 1] = o end

---------------------------------------------------------------------------
-- GENERAL
---------------------------------------------------------------------------
ns.RegisterPage("general", "General", "general", function(page)
    local G = function() return ns.db.global end
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Look")
    L:Cycle("Accent colour", ns.ACCENTS, function() return G().accent end, function(v)
        G().accent = v
        ns.ApplyAccent()
        ns.Print("Accent colour changed. The settings window takes it fully after /reload.")
    end)
    L:Color("Custom accent", function() return G().accentColor end, function(c)
        G().accentColor = c
        if G().accent == "CUSTOM" then ns.ApplyAccent() end
    end)
    L:Note("Used by the settings window and by every bar colour set to \"accent\" (the default health gradients).")
    L:Cycle("Settings window background", BackgroundChoices, Opt(G, "configBg"))

    L:Header("Text")
    L:Cycle("Font", function() return FontChoices(false) end, Opt(G, "font"))
    L:Cycle("Outline", OUTLINES, Opt(G, "outline"))
    L:Check("Text shadow", Opt(G, "shadow"))
    local ga, sa = Opt(G, "abbreviate")
    L:Check("Short numbers (12.3k)", ga, sa, "Health and power values as 12.3k instead of 12345.")
    local gs, ss = Opt(G, "statusText")
    L:Check("Dead, Ghost, Offline instead of health", gs, ss)
    local gx, sx = Opt(G, "shortenTexts")
    L:Check("Shorten a left text next to a right text", gx, sx, "A left text sharing its row with a right text is cut short (\"Burnin...\") instead of running into it.")

    L:Header("Power colours")
    L:Cycle("Power bars by type", {
        { value = "GAME", text = "The game's colours" },
        { value = "CUSTOM", text = "My colours (below)" },
    }, Opt(G, "powerColors"))
    for _, p in ipairs({ { "MANA", "Mana" }, { "RAGE", "Rage" }, { "ENERGY", "Energy" }, { "FOCUS", "Focus" } }) do
        L:Color(p[2], function() return G().customPower[p[1]] end, function(c) G().customPower[p[1]] = c end)
    end

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Frames")
    R:Button("Unlock frames (move, preview)", function() ns.Movers.Toggle() end)
    local gh, sh = Opt(G, "hideBlizzard")
    R:Check("Hide Blizzard's frames HUF replaces", gh, function(v)
        sh(v)
        if not v then ns.Print("Blizzard's frames come back after /reload.") end
    end, "Hides Blizzard's player, target and target-of-target frames while HUF's are on. Turning this off needs /reload.")
    R:Header("Clicks")
    R:Note("Left-click targets the unit, right-click opens its menu.")
    local gm, sm = Opt(G, "menuMode")
    R:Cycle("Right-click menu", {
        { value = "PROXY", text = "Secure proxy (12.x)" },
        { value = "DIRECT", text = "Direct (togglemenu)" },
    }, gm, sm)
    R:Note("If the menu doesn't open on right-click, try the other way (outside combat).")
    local gc, sc = Opt(G, "clickCast")
    R:Check("Click-casting addons (Clique)", gc, function(v)
        sc(v)
        ns.Print("Takes effect after /reload.")
    end, "Registers HUF's frames for click-casting addons.")
    R:Header("Media")
    R:Note("Barlow Condensed (default) and Roboto Condensed come with HUF. " .. (ns.ellesmere and "EllesmereUI is installed: its fonts (Expressway, ...) and bar textures are in the lists too (used from its folder)."
        or "With EllesmereUI installed, its fonts and bar textures show up in the lists too."))
end)

---------------------------------------------------------------------------
-- Names & MMT
---------------------------------------------------------------------------
ns.RegisterPage("names", "Names & MMT", "general", function(page)
    local P = function() return ns.db.privacy end
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Privacy")
    local gm, sm = Opt(P, "mode")
    L:Cycle("[name] shows players as", {
        { value = "FIRST", text = "First name" },
        { value = "LAST",  text = "Last name" },
        { value = "FULL",  text = "Full name" },
        { value = "CLASS", text = "Class X (group)" },
        { value = "SLOT",  text = "Slot X (group)" },
    }, gm, function(v) sm(v) ns.RefreshNames() end)
    L:Note("For texts using [name]. [name:first], [name:last] and [name:full] always show that part. Class X and Slot X number the members of your group; players outside it show their first name. NPC names are never changed.")

    L:Header("MMT")
    local gu, su = Opt(P, "mmt")
    L:Cycle("MMT's privacy for my team", {
        { value = "ALWAYS",  text = "Always" },
        { value = "OUTSIDE", text = "When MMT hides names outside MMT" },
        { value = "NEVER",   text = "Never" },
    }, gu, function(v) su(v) ns.RefreshNames() end)
    L:Note("Characters of your MMT team show the name MMT > Team > Privacy chooses (First name, Last name, Class X, Slot X) in every name value. With MMT set to Full name, the settings here decide.")
    local status = UI.Label(page, "")
    status:SetJustifyH("LEFT")
    status:SetWidth(COL_W)
    L:Add(status, 60)
    table.insert(page.widgets, { Refresh = function()
        local st = ns.Bridge.Status()
        local lines = {}
        if st.loaded then
            lines[#lines + 1] = ("MMT is loaded%s. Team: %d characters."):format(st.version and (" (v" .. st.version .. ")") or "", st.teamSize)
            lines[#lines + 1] = ("MMT shows characters by: %s%s."):format(ns.Bridge.ModeText(st.mode), st.hideOutside and ", hides names outside MMT" or "")
            lines[#lines + 1] = st.active and "|cff66dd66HUF follows it.|r" or "|cffaaaaaaNot used.|r"
            if st.apiState == "newer" then
                lines[#lines + 1] = ("|cffff8040MMT's privacy interface is v%d, HUF knows v%d: HUF may need an update.|r"):format(st.api, st.apiExpected)
            elseif st.apiState == "older" then
                lines[#lines + 1] = "|cffaaaaaaOlder MMT (no privacy interface version): updating MMT is recommended.|r"
            end
        else
            lines[#lines + 1] = "|cffaaaaaaMMT is not loaded.|r"
        end
        status:SetText(table.concat(lines, "\n"))
    end })

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("How HUF and MMT work together")
    R:Note("HUF reads MMT's privacy setting and team and redraws its names the moment either changes in MMT. Internally both addons always use the full real name, so targeting, menus and macros keep working.")
    R:Note("For addon authors: _G.HUF.RegisterNameProvider(id, fn) adds a name source (fn(unit, first, last) returns the name to show), HUF.RefreshNames() redraws all names.")
end)

-- Profiles
---------------------------------------------------------------------------
ns.RegisterPage("profiles", "Profiles", "general", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Profile")
    L:Note("Profiles are account-wide. Each character picks the one it uses.")
    L:Cycle("Active profile", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do l[#l + 1] = { value = n, text = n } end
        return l
    end, function() return ns.CurrentProfileName() end, function(v) ns.SetProfile(v) end)

    local status = UI.Label(page, "")
    local box = UI.EditBox(page, COL_W - 90, "new profile name", function(text, self)
        text = ns.Trim(text)
        if text == "" then return end
        ns.SetProfile(text)
        self:SetText("")
        self:ClearFocus()
        status:SetText(("Profile \"%s\" is active."):format(text))
    end)
    L:Add(box, 0)
    local create = UI.Button(page, 84, "Create", function()
        local text = ns.Trim(box:GetText())
        if text == "" then return end
        ns.SetProfile(text)
        box:SetText("")
        box:ClearFocus()
        status:SetText(("Profile \"%s\" is active."):format(text))
    end)
    create:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    L:Space(UI.ROW + 4)
    L:Note("A new profile starts with the default settings.")

    L:Header("Copy and delete")
    L:Cycle("Copy settings from", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do
            if n ~= ns.CurrentProfileName() then l[#l + 1] = { value = n, text = n } end
        end
        return l
    end, function() return nil end, function(v)
        UI.Confirm(("Replace every setting of \"%s\" with the settings of \"%s\"?"):format(ns.CurrentProfileName(), v), "Copy",
            function() ns.CopyProfile(v) status:SetText(("Copied from \"%s\"."):format(v)) end)
    end)
    L:Cycle("Delete profile", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do
            if n ~= ns.CurrentProfileName() then l[#l + 1] = { value = n, text = n } end
        end
        return l
    end, function() return nil end, function(v)
        UI.Confirm(("Delete the profile \"%s\"? Characters using it switch to \"Default\"."):format(v), "Delete",
            function() if ns.DeleteProfile(v) then status:SetText(("Deleted \"%s\"."):format(v)) ns.RefreshConfig() end end)
    end)
    L:Button("Reset active profile", function()
        UI.Confirm(("Reset every setting of \"%s\" to the defaults?"):format(ns.CurrentProfileName()), "Reset",
            function() ns.ResetProfile() status:SetText("Reset to defaults.") end)
    end)
    L:Space(4)
    L:Add(status)
    status:SetTextColor(0.6, 0.6, 0.6)

    -- export / import as text (copy & paste, e.g. to another account)
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Export and import")
    R:Note("Export: every setting of the active profile as one line of text. Copy it (Ctrl+A, Ctrl+C) and paste it into HUF on another account or PC (Ctrl+V), then Import.")
    local area = UI.TextArea(page, COL_W, 170)
    if area.edit.SetMaxLetters then area.edit:SetMaxLetters(0) end
    R:Add(area, 178)
    local msg = UI.Label(page, "")
    msg:SetWidth(COL_W)
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)
    msg:SetTextColor(0.6, 0.6, 0.6)
    local exp = UI.Button(page, (COL_W - 6) / 2, "Export", function()
        local ok, text = pcall(ns.ExportProfile)
        if not ok then msg:SetText("Export failed: " .. tostring(text)) return end
        area.edit:SetText(text)
        area.edit:SetFocus()
        area.edit:HighlightText()
        msg:SetText(("Profile \"%s\" exported (%d characters). Copy it with Ctrl+C."):format(ns.CurrentProfileName(), #text))
    end)
    R:Add(exp, 0)
    -- EllesmereUI's frames (from a string or its live settings) -> HUF's
    -- the import window: which frames to show (ticked as in Ellesmere; a
    -- frame Ellesmere has off can be turned on), and while EllesmereUI
    -- Nameplates is loaded, whether to turn it off (two plates otherwise)
    local dlg
    local MAX_ROWS, MAX_EXTRA = 8, 3
    local function ImportWindow()
        if dlg then return dlg end
        local f = CreateFrame("Frame", "HUFEllesmereImportFrame", UIParent)
        f:SetWidth(400)
        f:SetPoint("TOP", 0, -140)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.6)
        f.text = UI.Label(f, "")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetPoint("TOPRIGHT", -16, -16)
        f.text:SetJustifyH("LEFT")
        f.rows, f.extras = {}, {}
        local function NewRow()
            local row = { on = false }
            row.check = UI.Check(f, 368, "", function() return row.on end, function(v) row.on = v end)
            return row
        end
        for i = 1, MAX_ROWS do f.rows[i] = NewRow() end
        for i = 1, MAX_EXTRA do f.extras[i] = NewRow() end
        local function Accept()
            local fn = f.onAccept
            f:Hide()
            if fn then fn() end
        end
        f.accept = UI.Button(f, 116, "Import", Accept)
        f.accept:SetPoint("BOTTOMLEFT", 16, 14)
        -- every listed part on, whatever Ellesmere has
        f.all = UI.Button(f, 116, "Import all", function()
            for _, row in ipairs(f.rows) do
                if row.part then row.on = true end
            end
            Accept()
        end)
        f.all:SetPoint("BOTTOM", 0, 14)
        f.cancel = UI.Button(f, 116, "Cancel", function() f:Hide() end)
        f.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
        f:SetScript("OnHide", function() f.onAccept = nil end)
        UI.CloseOnEscape(f)
        f:Hide()
        dlg = f
        return f
    end

    -- parts: { title, tbl (.enabled), on, why, folder (the EllesmereUI module
    -- drawing the same thing, offered to be turned off while it is loaded) }
    local function EllesmereImport(ok, t, notes, what, parts)
        if not ok then msg:SetText("|cffff6060" .. t .. "|r") return end
        parts = parts or {}
        local list = table.concat(what, ", "):gsub(", ([^,]*)$", " and %1")
        local f = ImportWindow()
        f.text:SetText(("Replace the %s of \"%s\" with EllesmereUI's.\nShow in HUF:"):format(list, ns.CurrentProfileName()))
        local y = -52
        local function Place(row)
            row.check:ClearAllPoints()
            row.check:SetPoint("TOPLEFT", 16, y)
            row.check.Refresh()
            row.check:Show()
            y = y - (UI.ROW - 2)
        end
        for i, row in ipairs(f.rows) do
            local part = parts[i]
            row.part = part
            if part then
                row.on = part.on and true or false
                row.check.label:SetText(part.on and part.title or (part.title .. "  |cff888888(" .. part.why .. ")|r"))
                Place(row)
            else
                row.check:Hide()
            end
        end
        -- an EllesmereUI module drawing the same thing: offer to turn it off
        y = y - 8
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
        local n = 0
        for _, part in ipairs(parts) do
            if part.folder and loaded and loaded(part.folder) and C_AddOns.DisableAddOn and n < MAX_EXTRA then
                n = n + 1
                local row = f.extras[n]
                row.part, row.on = part, true
                row.check.label:SetText(("Turn off %s (reloads)"):format(part.module or part.folder))
                Place(row)
            end
        end
        for i = n + 1, MAX_EXTRA do
            f.extras[i].part = nil
            f.extras[i].check:Hide()
        end
        f:SetHeight(-y + 64)
        f.onAccept = function()
            for _, row in ipairs(f.rows) do
                if row.part then row.part.tbl.enabled = row.on end
            end
            ns.ImportProfile(t)
            area.edit:SetText("")
            msg:SetText(("EllesmereUI %s imported%s"):format(list, #notes > 0 and " (details in chat)." or "."))
            for _, line in ipairs(notes) do ns.Print("Ellesmere import: %s", line) end
            local reload = false
            for _, row in ipairs(f.extras) do
                local part = row.part
                if part and row.check:IsShown() then
                    if row.on then
                        pcall(C_AddOns.DisableAddOn, part.folder, UnitName("player"))
                        reload = true
                    elseif part.tbl.enabled then
                        ns.Print("%s is still on next to HUF's %s: both draw it.", part.module or part.folder, part.title:lower())
                    end
                end
            end
            if reload then
                -- the game refuses a reload in combat: ask again after the fight
                if InCombatLockdown() then
                    ns.Print("A reload has to wait for the end of the fight.")
                    ns.RunOOC("reload", function()
                        UI.Confirm("Reload now to finish turning the EllesmereUI module off?", "Reload", ReloadUI, "Later")
                    end)
                else
                    ReloadUI()
                end
            end
        end
        f:Show()
    end
    local imp = UI.Button(page, (COL_W - 6) / 2, "Import", function()
        local text = area.edit:GetText()
        if ns.IsEllesmereText(text) then
            EllesmereImport(ns.ReadEllesmereText(text))
            return
        end
        local ok, t = ns.ReadProfileText(text)
        if not ok then msg:SetText("|cffff6060" .. t .. "|r") return end
        UI.Confirm(("Replace every setting of the active profile \"%s\" with the imported ones?"):format(ns.CurrentProfileName()), "Import",
            function()
                ns.ImportProfile(t)
                area.edit:SetText("")
                msg:SetText("Imported. Frames and settings are updated.")
            end)
    end)
    imp:SetPoint("TOPLEFT", exp, "TOPRIGHT", 6, 0)
    R:Space(UI.ROW + 4)
    if _G.EllesmereUI and ns.ReadEllesmereLive then
        R:Button("Import from EllesmereUI (its current settings)", function()
            EllesmereImport(ns.ReadEllesmereLive())
        end)
    end
    R:Add(msg, 40)
    R:Note("Import replaces the active profile. To keep it, create a new profile first (left) and import into that one. Click-cast bindings belong to the character and are not part of a profile.")
    if _G.EllesmereUI then R:Note("EllesmereUI: \"Import from EllesmereUI\" or an EllesmereUI string (!EUI_...) in the box: its unit frames (player, target, target of target, pet, with the font), nameplates and damage meter replace HUF's; group frames stay. Close to Ellesmere's look, not identical.") end
end)

---------------------------------------------------------------------------
-- FRAMES: one page per frame
---------------------------------------------------------------------------
local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

-- Frame: size, position, background, portrait
local function FramePage(f, key)
    local S = function() return U(key) end
    local P = function() return U(key).portrait end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Size")
    L:Slider("Width", 60, 400, 1, Opt(S, "width"))
    L:Slider("Height", 10, 80, 1, Opt(S, "height"))
    L:Slider("Scale", 0.5, 2, 0.05, function() return S().scale end, function(v) S().scale = v end, "%.2f")
    L:Slider("Opacity", 0.1, 1, 0.05, function() return S().alpha end, function(v) S().alpha = v end, "%.2f")
    if ns.UNIT_BY_KEY[key].group then
        L:Slider("Padding (this orientation)", -10, 80, 1,
            function()
                local o = S().group
                return ns.Group.Growth(o).dx ~= 0 and (o.spacingH or 2) or o.spacing
            end, function(v)
                local o = S().group
                if ns.Group.Growth(o).dx ~= 0 then o.spacingH = v else o.spacing = v end
            end)
    end
    L:Header("Position")
    if not ns.UNIT_BY_KEY[key].group then
        L:Cycle("Anchored to", function()
            local l = { { value = "SCREEN", text = "Screen" } }
            for _, u in ipairs(ns.UNITS) do
                if u.key ~= key and U(u.key).anchorTo ~= key then l[#l + 1] = { value = u.key, text = u.title .. " frame" } end
            end
            return l
        end, function() return S().anchorTo or "SCREEN" end, function(v)
            local s = S()
            if v == s.anchorTo then return end
            s.anchorTo = v
            if v == "SCREEN" then
                -- stay where it is now, measured from the bottom left of the screen
                local f = ns.singles and ns.singles[key]
                local l, b = f and f:GetLeft(), f and f:GetBottom()
                s.point = (l and b) and { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(l + 0.5), math.floor(b + 0.5) }
                    or { "CENTER", "CENTER", 0, 0 }
            else
                s.point = { "TOPLEFT", "BOTTOMLEFT", 0, -5 }
            end
            ns.RefreshConfig()
        end)
        local POINTS = {}
        for _, a in ipairs(ns.ANCHORS) do POINTS[#POINTS + 1] = { value = a, text = ns.ANCHOR_TEXT[a] } end
        L:Cycle("Point of this frame", POINTS, function() return S().point[1] end, function(v) S().point[1] = v end)
        L:Cycle("Point it attaches to", POINTS, function() return S().point[2] end, function(v) S().point[2] = v end)
    end
    L:Slider("Horizontal offset", -2000, 2000, 1, function() return S().point[3] end, function(v) S().point[3] = v end)
    L:Slider("Vertical offset", -1200, 1200, 1, function() return S().point[4] end, function(v) S().point[4] = v end)
    L:Button("Reset position", function()
        S().point = ns.CopyTable(ns.DEFAULTS.units[key].point)
        S().anchorTo = ns.DEFAULTS.units[key].anchorTo
        ns.Refresh(true)
        ns.RefreshConfig()
    end)
    L:Note(ns.UNIT_BY_KEY[key].group
        and "Or drag the group: Unlock frames (/huf unlock). The position is the first member's top left corner. Shown in a group, hidden alone and in a raid (raid frames come later); changes wait until combat ends."
        or "Or drag the frame: Unlock frames (bottom left, /huf unlock).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    if ns.UNIT_BY_KEY[key].group then
        local O = function() return U(key).group end
        R:Header("Group")
        local gp, sp = Opt(O, "showPlayer")
        R:Check("Show myself in the group", gp, sp)
        R:Cycle("Orientation", {
            { value = "DOWN", text = "Vertical - top to bottom" },
            { value = "UP", text = "Vertical - bottom to top" },
            { value = "RIGHT", text = "Horizontal - left to right" },
            { value = "LEFT", text = "Horizontal - right to left" },
        }, function() return select(2, ns.Group.Growth(O())) end, function(v) O().orientation = v if ns.RefreshConfig then ns.RefreshConfig() end end)
        R:Cycle("Sort members by", {
            { value = "NAME", text = "Name (alphabetical)" },
            { value = "INDEX", text = "Blizzard's party order" },
            { value = "CLASS", text = "Class" },
        }, Opt(O, "sort"))
    end
    R:Header("Frame background")
    R:Cycle("Picture", BackgroundChoices, Opt(S, "frameBg"))
    R:Color("Colour", Opt(S, "frameBgColor"))
    R:Slider("Opacity", 0, 1, 0.05, function() return S().frameBgAlpha end, function(v) S().frameBgAlpha = v end, "%.2f")
    R:Slider("Reaches past the frame", 0, 12, 1, Opt(S, "framePad"))
    R:Header("Portrait")
    R:Check("Show a portrait", Opt(P, "enabled"))
    R:Cycle("Kind", {
        { value = "3D", text = "3D model" },
        { value = "2D", text = "Picture" },
        { value = "CLASS", text = "Class icon" },
    }, Opt(P, "mode"))
    R:Cycle("Side", { { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" } }, Opt(P, "side"))
    R:Slider("Border", 0, 3, 0.5, function() return P().borderSize end, function(v) P().borderSize = v end, "%.1f")
    local gt, st = Opt(S, "tooltip")
    R:Check("Unit tooltip on mouseover", gt, st)
end

-- Health bar / Power bar
local function BarPage(f, key, which)
    local B = function() return U(key)[which] end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header(which == "power" and "Power bar (mana, energy, rage)" or "Health bar")
    if which == "power" then
        L:Check("Show the power bar", Opt(B, "enabled"))
        L:Slider("Height", 2, 30, 1, Opt(B, "size"))
        L:Slider("Gap to the health bar", 0, 10, 1, Opt(B, "gap"))
        local gd, sd = Opt(B, "divider")
        L:Check("Line between health and power", gd, sd, "With no gap: a border line between the two bars. Off: one border around both, as EllesmereUI draws it.")
    end
    L:Cycle("Bar texture", TextureChoices, Opt(B, "texture"))
    L:Check("Fill from the right", Opt(B, "reverse"))
    L:Header("Colour")
    L:Cycle("Colour by", {
        { value = "STATIC", text = "Static colour" },
        { value = "GRADIENT", text = "Gradient (2 colours)" },
        { value = "CLASS", text = "Class colour" },
        { value = "STATUS", text = "Status (>75% / >40% / below)" },
        { value = "TYPE", text = "Type (health green, mana blue ...)" },
    }, Opt(B, "colorMode"))
    L:Color("Static colour", Opt(B, "color"))
    L:Color("Gradient: left", Opt(B, "gradStart"))
    L:Check("Left: accent colour", Opt(B, "gradStartAccent"))
    L:Color("Gradient: right", Opt(B, "gradEnd"))
    L:Check("Right: accent colour", Opt(B, "gradEndAccent"))
    if which == "health" then
        local HP = function() return U(key).healPred end
        L:Header("Incoming heals")
        local ge, se = Opt(HP, "enabled")
        L:Check("Show incoming heals", ge, se, "Heals on their way to this unit (yours and others'), as a semi-transparent bar after the filled part.")
        L:Color("Colour", Opt(HP, "color"))
        L:Slider("Opacity", 0.1, 1, 0.05, function() return HP().alpha end, function(v) HP().alpha = v end, "%.2f")
        L:Slider("Past the bar's end (overheal)", 0, 100, 5, function() return HP().overheal end,
            function(v) HP().overheal = v end, "%d%%")
    end

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Status colours")
    R:Color("Above 75%", Opt(B, "high"))
    R:Color("Above 40%", Opt(B, "mid"))
    R:Color("40% and below", Opt(B, "low"))
    local gn, sn = Opt(B, "npcReaction")
    R:Check("NPCs in reaction colours (class)", gn, sn, "With \"Class colour\": hostile red, neutral yellow, friendly green. Off: NPCs use the static colour.")
    if which == "health" then R:Check("Grey when dead, offline or tapped", Opt(B, "deadGray")) end
    R:Header("Background (empty part)")
    R:Cycle("Picture", BackgroundChoices, Opt(B, "bgTexture"))
    R:Color("Colour", Opt(B, "bgColor"))
    R:Slider("Opacity", 0, 1, 0.05, function() return B().bgAlpha end, function(v) B().bgAlpha = v end, "%.2f")
    R:Header("Border")
    R:Slider("Size", 0, 3, 0.5, function() return B().borderSize end, function(v) B().borderSize = v end, "%.1f")
    R:Color("Colour", Opt(B, "borderColor"))
end

-- Texts: 9 anchors per bar
local SHORT = { TOPLEFT = "TL", TOP = "T", TOPRIGHT = "TR", LEFT = "L", CENTER = "C", RIGHT = "R",
    BOTTOMLEFT = "BL", BOTTOM = "B", BOTTOMRIGHT = "BR" }

local function TextsPage(f, key, page)
    local bar, anchor = "health", nil
    -- default selection: the first anchor with text on the health bar
    for _, a in ipairs(ns.ANCHORS) do
        if not anchor and U(key).texts.health[a].text ~= "" then anchor = a end
    end
    anchor = anchor or "CENTER"
    local T = function() return U(key).texts[bar][anchor] end

    local L = UI.Column(f, 0, 0, COL_W)
    L:Cycle("Bar", {
        { value = "health", text = "Health bar" },
        { value = "power", text = "Power bar" },
    }, function() return bar end, function(v) bar = v end)
    L:Header("Anchor")

    -- 3 x 3 grid: the bar's anchors; lit = has text, outlined = selected
    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(COL_W, 72)
    UI.Fill(grid, 0.08, 0.08, 0.09, 0.9)
    UI.Border(grid, 0.22, 0.22, 0.24, 1)
    local cells = {}
    local CW, CH = (COL_W - 16) / 3, 20
    for i, a in ipairs(ns.ANCHORS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local b = CreateFrame("Button", nil, grid)
        b:SetSize(CW - 4, CH)
        b:SetPoint("TOPLEFT", 8 + col * CW, -6 - row * (CH + 2))
        b.fill = UI.Fill(b, 1, 1, 1, 0.04)
        b.sel = UI.Border(b, A[1], A[2], A[3], 1)
        b.label = UI.Label(b, ns.ANCHOR_TEXT[a])
        b.label:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            anchor = a
            ns.Log("config", "text anchor %s %s", bar, a)
            ns.RefreshConfig()
        end)
        UI.Tooltip(b, ns.ANCHOR_TEXT[a], "Click to edit the text at this anchor.")
        cells[a] = b
    end
    L:Add(grid, 80)
    table.insert(page.widgets, { Refresh = function()
        for a, b in pairs(cells) do
            local used = U(key).texts[bar][a].text ~= ""
            b.fill:SetColorTexture(A[1], A[2], A[3], used and 0.35 or 0.04)
            if b.sel.SetShown then b.sel:SetShown(a == anchor) end
            if used then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(0.5, 0.5, 0.5) end
        end
    end })

    local head = L:Header("Text")
    local box = UI.EditBox(f, COL_W, "empty: no text here")
    box:SetScript("OnTextChanged", function(self, user)
        if self.UpdatePlaceholder then self:UpdatePlaceholder() end
        if user then
            T().text = self:GetText()
            ns.Refresh()
        end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    L:Add(box, UI.ROW + 4)
    table.insert(page.widgets, { Refresh = function()
        if not box:HasFocus() then box:SetText(T().text or "") end
        box:UpdatePlaceholder()
        if head and head.SetText then head:SetText(("Text: %s, %s"):format(bar == "health" and "health bar" or "power bar", ns.ANCHOR_TEXT[anchor]:lower())) end
    end })
    L:Cycle("Insert value", ns.TAGS, function() return nil end, function(v)
        local t = T().text or ""
        if t ~= "" and not t:find("%s$") then t = t .. " " end
        T().text = t .. v
    end)
    L:Button("Clear this text", function() T().text = "" ns.Refresh() ns.RefreshConfig() end)
    L:Note("Values in [ ] are filled in, everything else shows as typed. Example: [levelclass:color] | [name] shows \"55E | Northshire Guard\".")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Cycle("Font", function() return FontChoices(true) end, Opt(T, "font"))
    R:Slider("Size", 6, 40, 1, Opt(T, "size"))
    R:Cycle("Outline", OUTLINES_G, Opt(T, "outline"))
    R:Cycle("Colour", {
        { value = "WHITE", text = "White" },
        { value = "CLASS", text = "Class / reaction" },
        { value = "ACCENT", text = "Accent colour" },
        { value = "CUSTOM", text = "Custom" },
        { value = "STATUS", text = "Health status (>75% / >40% / below)" },
    }, Opt(T, "colorMode"))
    R:Color("Custom colour", Opt(T, "color"))
    local gf, sf = Opt(T, "hideFull")
    R:Check("Status: hide at full health", gf, sf, "With \"Health status\": the text is invisible while the unit has full health (e.g. missing health would show 0). The status colours are the health bar's.")
    R:Header("Offset")
    R:Slider("Horizontal (X)", -150, 150, 1, Opt(T, "x"))
    R:Slider("Vertical (Y)", -80, 80, 1, Opt(T, "y"))
end

-- Buffs & debuffs: two icon rows, debuffs left column, buffs right
local AURA_POSITIONS = {
    { value = "BELOW_LEFT", text = "Below, from the left" },
    { value = "BELOW_RIGHT", text = "Below, from the right" },
    { value = "ABOVE_LEFT", text = "Above, from the left" },
    { value = "ABOVE_RIGHT", text = "Above, from the right" },
    { value = "LEFT", text = "Left of the frame" },
    { value = "RIGHT", text = "Right of the frame" },
}
local function AuraColumn(col, key, which, title)
    local T = function() return U(key)[which] end
    col:Header(title)
    col:Check("Show " .. which, Opt(T, "enabled"))
    local gm, sm = Opt(T, "mine")
    col:Check("Only mine", gm, sm, which == "debuffs" and "Only the debuffs you cast." or "Only the buffs you cast.")
    col:Cycle("Position", AURA_POSITIONS, Opt(T, "position"))
    col:Slider("Icon size", 8, 40, 1, Opt(T, "size"))
    col:Slider("Icons per row", 1, 12, 1, Opt(T, "perRow"))
    col:Slider("Rows", 1, 6, 1, Opt(T, "rows"))
    col:Slider("Space between icons", 0, 8, 1, Opt(T, "gap"))
    col:Slider("Distance to the frame", 0, 20, 1, Opt(T, "offset"))
    col:Slider("Horizontal offset", -200, 200, 1, Opt(T, "x"))
    col:Slider("Vertical offset", -200, 200, 1, Opt(T, "y"))
    col:Slider("Stack number size", 6, 16, 1, Opt(T, "countSize"))
    local gt, st = Opt(T, "timer")
    col:Check("Time left as a dark sweep", gt, st)
    local gx, sx = Opt(T, "timerText")
    col:Check("Time left as numbers", gx, sx)
    col:Slider("Time size (0: automatic)", 0, 20, 1, Opt(T, "timerSize"))
end

local function AuraPage(f, key)
    local L = UI.Column(f, 0, 0, COL_W)
    AuraColumn(L, key, "debuffs", "Debuffs")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    AuraColumn(R, key, "buffs", "Buffs")
    R:Note("Unlock frames to see where the icons go. They fill a row, then start the next one.")
    if key == "player" then
        local S = function() return U(key) end
        L:Header("Blizzard")
        local L2 = L
        local gb = function() return S().hideBlizzardAuras end
        L2:Check("Hide Blizzard's buff and debuff icons", gb, function(v)
            S().hideBlizzardAuras = v
            if v then
                if ns.Units then ns.Units.HideBlizzardAuras() end
            else
                ns.Print("Blizzard's buff and debuff icons come back after /reload.")
            end
        end, "The icons at the top right of the screen. HUF's own icons on the player frame replace them.")
    end
end

-- Cast bar: on the line between health and power bar
local function CastPage(f, key)
    local C = function() return U(key).castBar end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Cast bar")
    L:Check("Show the cast bar", Opt(C, "enabled"))
    L:Slider("Height", 1, 20, 1, Opt(C, "height"))
    L:Slider("Horizontal offset", -100, 100, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -40, 40, 1, Opt(C, "y"))
    L:Cycle("Bar texture", TextureChoices, Opt(C, "texture"))
    L:Color("Colour", Opt(C, "color"))
    L:Slider("Background opacity", 0, 1, 0.05, function() return C().bgAlpha end, function(v) C().bgAlpha = v end, "%.2f")
    L:Slider("Border", 0, 3, 0.5, function() return C().borderSize end, function(v) C().borderSize = v end, "%.1f")
    L:Note("Sits on the line between the health and the power bar (the bottom of the health bar).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Spell icon")
    R:Check("Show the spell icon", Opt(C, "icon"))
    R:Slider("Icon size", 4, 40, 1, Opt(C, "iconSize"))
    R:Header("Spell name")
    R:Check("Show the spell name", Opt(C, "text"))
    R:Cycle("Font", function() return FontChoices(true) end, Opt(C, "font"))
    R:Slider("Size", 6, 20, 1, Opt(C, "fontSize"))
    R:Cycle("Outline", OUTLINES_G, Opt(C, "outline"))
    R:Cycle("Aligned", {
        { value = "LEFT", text = "Left" }, { value = "CENTER", text = "Center" }, { value = "RIGHT", text = "Right" },
    }, Opt(C, "textAlign"))
    R:Header("Interrupts")
    local gi, si = Opt(C, "interrupt")
    R:Check("Show interrupts", gi, si, "The bar turns red for a moment when someone interrupts the cast (with the spell name on: \"Interrupted!\").")
    R:Color("Colour", Opt(C, "interruptColor"))
end

-- Pet happiness (hunter pets)
local function HappinessPage(f, key)
    local C = function() return U(key).happiness end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Happiness")
    local ge, se = Opt(C, "enabled")
    L:Check("Show the pet's happiness", ge, se, "Hunter pets: happy, content or unhappy, on the right side of the health bar.")
    L:Cycle("Shown as", { { value = "ICON", text = "Icon (the game's faces)" }, { value = "TEXT", text = "Text (Happy / Content / Unhappy)" } },
        Opt(C, "mode"))
    L:Slider("Size", 6, 32, 1, Opt(C, "size"))
    L:Slider("Horizontal offset", -100, 100, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -40, 40, 1, Opt(C, "y"))
end

-- Combo points (target frame)
local function ComboPage(f, key)
    local C = function() return U(key).combo end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Combo points")
    local ge, se = Opt(C, "enabled")
    L:Check("Show combo points", ge, se, "Rogues, and druids in cat form: a row of points at the target frame.")
    local gh, sh = Opt(C, "hideEmpty")
    L:Check("Hide with no points", gh, sh, "Only where the game lets addons read the number. Where it can't: after a target change the points stay hidden until you gain one.")
    L:Cycle("Position", ns.Combo.POSITIONS, Opt(C, "pos"))
    L:Slider("Horizontal offset", -200, 200, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -100, 100, 1, Opt(C, "y"))
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Slider("Width (0: the frame's width)", 0, 400, 1, Opt(C, "width"))
    R:Slider("Height", 2, 20, 1, Opt(C, "height"))
    R:Slider("Space between points", 0, 10, 1, Opt(C, "gap"))
    R:Color("Colour", Opt(C, "color"))
    R:Slider("Background opacity", 0, 1, 0.05, function() return C().bgAlpha end, function(v) C().bgAlpha = v end, "%.2f")
    R:Note("The nameplate's combo points: Nameplates > Combo points.")
end

local function UnitPage(key)
    return function(page)
        local info = ns.UNIT_BY_KEY[key]
        local on = UI.Check(page, 220, info.group and "Show the group frames" or ("Show the " .. info.title:lower() .. " frame"),
            function() return U(key).enabled end,
            function(v)
                U(key).enabled = v
                if v and ns.Units then ns.Units.HideBlizzard() end
                if not v and ns.db.global.hideBlizzard then ns.Print("Blizzard's frame comes back after /reload.") end
            end)
        on:SetPoint("TOPLEFT", 0, 4)
        local copy = UI.Dropdown(page, 200, "Copy look from", function()
            local l = {}
            for _, u in ipairs(ns.FRAME_KEYS) do
                if u.key ~= key then l[#l + 1] = { value = u.key, text = u.title } end
            end
            return l
        end, function() return nil end, function(v)
            UI.Confirm(("Copy the look of the %s frame to the %s frame? Position, texts and on/off stay."):format(
                ns.UNIT_BY_KEY[v].title, info.title), "Copy", function() ns.CopyUnitSettings(v, key) end)
        end)
        copy:SetPoint("TOPLEFT", 280, 4)
        local reset = UI.Button(page, 100, "Reset frame", function()
            UI.Confirm(("Reset every setting of the %s frame (not its position)?"):format(info.title), "Reset",
                function() ns.ResetUnit(key) end)
        end)
        reset:SetPoint("TOPRIGHT", 0, 4)

        local tabs = {
            { "frame", "Frame" }, { "health", "Health bar" }, { "power", "Power bar" }, { "texts", "Texts" },
        }
        if not info.noAuras then tabs[#tabs + 1] = { "auras", "Buffs & debuffs" } end
        if not info.polled then tabs[#tabs + 1] = { "cast", "Cast bar" } end
        if key == "target" then tabs[#tabs + 1] = { "combo", "Combo points" } end
        if key == "pet" then tabs[#tabs + 1] = { "happy", "Happiness" } end
        local subs = {}
        local strip
        local function Show(k)
            for name, sf in pairs(subs) do sf:SetShown(name == k) end
            strip:Select(k)
        end
        strip = UI.SubTabs(page, tabs, function(k) Show(k) end)
        strip:SetPoint("TOPLEFT", 0, -22)
        strip:SetPoint("TOPRIGHT", 0, -22)
        subs.frame = SubFrame(page); FramePage(subs.frame, key)
        subs.health = SubFrame(page); BarPage(subs.health, key, "health")
        subs.power = SubFrame(page); BarPage(subs.power, key, "power")
        subs.texts = SubFrame(page); TextsPage(subs.texts, key, page)
        if not info.noAuras then subs.auras = SubFrame(page); AuraPage(subs.auras, key) end
        if not info.polled then subs.cast = SubFrame(page); CastPage(subs.cast, key) end
        if key == "target" then subs.combo = SubFrame(page); ComboPage(subs.combo, key) end
        if key == "pet" then subs.happy = SubFrame(page); HappinessPage(subs.happy, key) end
        strip:Bind(subs, Show)
        Show("frame")
    end
end

for _, info in ipairs(ns.FRAME_KEYS) do
    ns.RegisterPage(info.key, info.title, "frames", UnitPage(info.key),
        function() return ns.db.units[info.key].enabled end)
end
