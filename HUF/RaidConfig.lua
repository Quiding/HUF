-- HUF: raid frame settings (PRIMARY FRAMES > Raid).
-- Top: "Use HUF raid frames" (everything else greyed while off) and the raid
-- profile (Basic / Healer / Custom). Tabs: Main Frames | Texts |
-- Buffs/Debuffs | Maintank | Pets (only Main Frames has options yet).

local _, ns = ...
local UI = ns.UI

local function DB() return ns.db.raid end
local function P() return ns.UnitSettings("raid") end
local function L() return P().layout end
local function RD() return ns.Raid end

local TILE_W, GAP = 344, 10
local TOP_H = 58               -- master switch row + tab strip

local GROWTHS = {
    { value = "DOWN", text = "Top > Bottom" }, { value = "UP", text = "Bottom > Top" },
    { value = "RIGHT", text = "Left > Right" }, { value = "LEFT", text = "Right > Left" },
}
local COLOR_MODES = { { value = "CLASS", text = "By class" }, { value = "STATUS", text = "By status" }, { value = "STATIC", text = "Static" } }
local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local function ClassChoices()
    local l = {}
    for _, c in ipairs(CLASSES) do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or (c:sub(1, 1) .. c:sub(2):lower())
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
        if cc then name = ("|cff%02x%02x%02x%s|r"):format(math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255), name) end
        l[#l + 1] = { value = c, text = name }
    end
    return l
end

local function KeyChoices(exclude)
    local l = {}
    for _, k in ipairs(RD().KEYS) do
        if k ~= exclude then l[#l + 1] = { value = k, text = RD().TITLES[k] } end
    end
    return l
end

-- two widgets side by side in one row of a column
local function Pair(col, parent, a, b, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(col.width, height or 36)
    local half = (col.width - 16) / 2
    for i, w in ipairs({ a, b }) do
        w:SetParent(row)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", row, "TOPLEFT", i == 1 and 0 or (half + 16), 0)
        w:SetWidth(half)
    end
    col:Add(row, height or 36)
    return row
end

-- a label with a number box (offsets: exact values)
local function NumBox(parent, width, label, get, set, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, UI.ROW)
    local fs = UI.Label(f, label)
    fs:SetPoint("LEFT", 0, 0)
    local e = UI.EditBox(f, 60, "")
    e:SetPoint("RIGHT", 0, 0)
    e:SetJustifyH("CENTER")
    e:SetMaxLetters(6)
    local function Commit()
        local v = tonumber(e:GetText())
        if v then
            v = math.floor(v + 0.5)
            if v ~= get() then set(v) ns.Refresh() end
        end
        e:SetText(tostring(get()))
    end
    e:SetScript("OnEnterPressed", function(self) Commit() self:ClearFocus() end)
    e:HookScript("OnEditFocusLost", Commit)
    e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(get())) self:ClearFocus() end)
    f.Refresh = function() if not e:HasFocus() then e:SetText(tostring(get())) end end
    if tip then f:EnableMouse(true) UI.Tooltip(f, label, tip) UI.Tooltip(e, label, tip) end
    local p = parent
    while p and type(rawget(p, "widgets")) ~= "table" do p = p:GetParent() end
    if p then table.insert(p.widgets, f) end
    return f
end

---------------------------------------------------------------------------
-- Main Frames tab
---------------------------------------------------------------------------
local function MainTab(f, page, H)
    local gated = {}
    local function Gate(w, isOn) gated[#gated + 1] = { w, isOn } return w end

    -- Size & Position ------------------------------------------------------
    local SP_H = 222
    local sp, S = ns.ConfigTile(f, 0, 0, TILE_W, SP_H, "Size & Position", "Interface\\Icons\\INV_Misc_Spyglass_03")
    local ex = S:Button("Show Example Bars", function() RD().ShowExamples() ns.RefreshConfig() end)
    UI.Tooltip(ex, "Show Example Bars", "Shows all groups, main tanks and pets with made-up members and the current settings (also in unlock mode, where each group can be dragged). Click again to hide them.")
    local half = (S.width - 16) / 2
    Pair(S, sp,
        UI.Slider(sp, half, "Width", 40, 300, 1, function() return P().width end, function(v) P().width = v end),
        UI.Slider(sp, half, "Height", 10, 80, 1, function() return P().height end, function(v) P().height = v end))
    S:Cycle("Group Growth Direction", GROWTHS, function() return L().growth end, function(v) L().growth = v end,
        "How members line up in a group; also how the groups stack while they follow each other: Top > Bottom / Bottom > Top put groups 1-4 side by side and 5-8 in a second row; Left > Right / Right > Left put all eight groups below each other. Main tanks and pets always go below the groups.")
    S:Slider("Opacity", 0.1, 1, 0.05, function() return P().alpha end, function(v) P().alpha = v end, "%.2f")
    Pair(S, sp,
        UI.Slider(sp, half, "Horizontal Padding", 0, 40, 1, function() return L().padX end, function(v) L().padX = v end),
        UI.Slider(sp, half, "Vertical Padding", 0, 40, 1, function() return L().padY end, function(v) L().padY = v end))

    -- Frame Anchoring ------------------------------------------------------
    local FA_Y = -(SP_H + GAP)
    local fa, A = ns.ConfigTile(f, 0, FA_Y, TILE_W, H + FA_Y, "Frame Anchoring", "Interface\\Icons\\INV_Misc_Rope_01")
    local sel = "G1"
    A:Cycle("Group", function() return KeyChoices() end, function() return sel end, function(v) sel = v end,
        "The group whose anchor and offsets are shown below.")
    A:Cycle("Anchored to", function()
        local l = { { value = "SCREEN", text = "Screen" } }
        for _, c in ipairs(KeyChoices(sel)) do
            if not RD().DependsOn(c.value, sel) then l[#l + 1] = c end
        end
        return l
    end, function() return (RD().Anchor(sel)) end, function(v)
        local autoTo, ax, ay = RD().Auto(sel)
        local x, y = 0, 0
        if v == autoTo then x, y = ax, ay
        elseif v == "SCREEN" then x, y = P().point[3] or 0, P().point[4] or 0 end
        RD().SetAnchor(sel, v, x, y)
    end, "Screen: the offsets are the group's top left on the screen. Another group: the offsets are from that group's corner (the corner the growth direction starts from).")
    local inner = (A.width - 16) / 2
    local function Off(i)
        return function() return select(i + 1, RD().Anchor(sel)) end,
            function(v)
                local to, x, y = RD().Anchor(sel)
                if i == 1 then x = v else y = v end
                RD().SetAnchor(sel, to, x, y)
            end
    end
    local gx, sx = Off(1)
    local gy, sy = Off(2)
    local offTip = "Changing an offset sets this group by hand: it no longer follows size, growth and padding (\"Back to automatic\" undoes that). In unlock mode the groups can be dragged too."
    local row = CreateFrame("Frame", nil, fa)
    row:SetSize(A.width, UI.ROW)
    local bx = NumBox(row, inner, "Horizontal Offset", gx, sx, offTip)
    bx:SetPoint("LEFT", row, "LEFT", 0, 0)
    local by = NumBox(row, inner, "Vertical Offset", gy, sy, offTip .. " Negative values go down.")
    by:SetPoint("LEFT", row, "LEFT", inner + 16, 0)
    A:Add(row, UI.ROW + 4)
    local state = UI.Label(fa, "")
    state:SetJustifyH("LEFT")
    state:SetWidth(A.width)
    A:Add(state, 18)
    local back = UI.Button(fa, inner, "Back to automatic", function() RD().ResetAnchor(sel) ns.Refresh() end)
    UI.Tooltip(back, "Back to automatic", "This group follows size, growth direction and padding again.")
    local all = UI.Button(fa, inner, "All groups automatic", function() RD().ResetAnchor() ns.Refresh() end)
    UI.Tooltip(all, "All groups automatic", "Every group, the main tanks and the pets follow size, growth direction and padding again.")
    Pair(A, fa, back, all, UI.ROW + 2)
    table.insert(page.widgets, { Refresh = function()
        local _, _, _, manual = RD().Anchor(sel)
        state:SetText(manual and "|cffffd100Set by hand.|r" or "|cff9d9d9dAutomatic: follows size, growth and padding.|r")
        UI.SetActive(back, manual and true or false)
    end })

    -- Look and Features ----------------------------------------------------
    local lf, R = ns.ConfigTile(f, TILE_W + GAP, 0, TILE_W, H, "Look and Features", "Interface\\Icons\\INV_Misc_Gem_Variety_01")
    local function HP(k) return function() return P().health[k] end, function(v) P().health[k] = v end end
    local function Mode(m) return function() return P().health.colorMode == m end end
    R:Cycle("Bar Texture", ns.TextureChoices, HP("texture"))
    R:Cycle("Bar Color", COLOR_MODES, HP("colorMode"), "By class: the member's class colour. By status: green / amber / red by health left. Static: one colour.")
    Gate(R:Color("Static Colour", HP("color")), Mode("STATIC"))
    Gate(R:Color("Status: above 75%", HP("high")), Mode("STATUS"))
    Gate(R:Color("Status: above 40%", HP("mid")), Mode("STATUS"))
    Gate(R:Color("Status: below 40%", HP("low")), Mode("STATUS"))
    local gd, sd = HP("deadGray")
    R:Check("Grey when dead, offline or tapped", gd, sd)
    local function HPd(k) return function() return P().healPred[k] end, function(v) P().healPred[k] = v end end
    local healsOn = function() return P().healPred.enabled end
    local ge, se = HPd("enabled")
    R:Check("Show incoming heals", ge, se, "Heals on their way to a member, after the filled part of the health bar.")
    Gate(R:Color("Incoming heals colour", HPd("color")), healsOn)
    local ga, sa = HPd("alpha")
    local go, so = HPd("overheal")
    Gate(Pair(R, lf, UI.Slider(lf, (R.width - 16) / 2, "Opacity", 0.1, 1, 0.05, ga, sa, "%.2f"),
        UI.Slider(lf, (R.width - 16) / 2, "Past the bar's end %", 0, 50, 1, go, so)), healsOn)
    local function PW(k) return function() return P().power[k] end, function(v) P().power[k] = v end end
    local pe, pse = PW("enabled")
    R:Check("Show resource bars", pe, pse, "Mana / rage / energy as a thin bar under the health bar.")
    local gsz, ssz = PW("size")
    Gate(R:Slider("Resource bar height", 1, 12, 1, gsz, ssz), function() return P().power.enabled end)
    local function CB(k) return function() return P().castBar[k] end, function(v) P().castBar[k] = v end end
    local ce, cse = CB("enabled")
    R:Check("Show cast bars", ce, cse, "Casts show on top of the resource bar (on the health bar's bottom edge without one), the spell icon at the cast bar's left inner edge.")
    local classes = R:MultiDropdown("From classes", ClassChoices,
        function(v) return P().castBar.classes[v] == true end,
        function(v) local c = P().castBar.classes c[v] = not c[v] or nil end)
    UI.Tooltip(classes, "From classes", "Only members of these classes show cast bars.")
    Gate(classes, function() return P().castBar.enabled end)
    local tg, ts = function() return P().threatBorder end, function(v) P().threatBorder = v end
    R:Check("Show red border on threat", tg, ts, "A red edge round a member while an NPC attacks them.")

    table.insert(page.widgets, { Refresh = function()
        for _, g in ipairs(gated) do UI.SetActive(g[1], DB().enabled and g[2]() and true or false) end
        if classes.Refresh then classes.Refresh() end
    end })
end

local function Later(f, text)
    local l = UI.Label(f, text, "GameFontNormal")
    l:SetPoint("TOPLEFT", 4, -8)
    l:SetTextColor(0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
ns.RegisterPage("raid", "Raid", "frames", function(page)
    local master = UI.Check(page, 300, "Use HUF raid frames", function() return DB().enabled end, function(v)
        DB().enabled = v
        if v then ns.Refresh()
        else
            ns.Refresh()
            ns.AskReload("The game's raid frames come back after a reload.")
        end
    end, "HUF's raid frames: eight groups, the main tanks and the pets, each with a small title, movable on their own or following each other. The game's raid frames are hidden while this is on.")
    master:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    table.insert(page.widgets, master)
    local prof = UI.Dropdown(page, 230, "Raid profile", RD().PROFILES, function() return DB().profile end, function(v)
        DB().profile = v
        ns.Refresh()
        ns.RefreshConfig()
    end, "Basic, Healer or Custom: each keeps its own raid frame settings. For now all three start the same.")
    prof:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    table.insert(page.widgets, prof)

    local subs, order = {}, { { "main", "Main Frames" }, { "texts", "Texts" }, { "auras", "Buffs/Debuffs" }, { "mt", "Maintank" }, { "pets", "Pets" } }
    local function Show(key)
        for k, f in pairs(subs) do f:SetShown(k == key) end
    end
    local strip = UI.SubTabs(page, order, Show)
    strip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -30)
    strip:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -30)
    local H = ns.PAGE_H - TOP_H
    for _, t in ipairs(order) do
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_H)
        f:SetSize(TILE_W * 2 + GAP, H)
        subs[t[1]] = f
    end
    -- everything but the switch waits for it (registered first: the tabs' own
    -- greying runs after it on every refresh)
    UI.Gate(page, master, function() return DB().enabled end)
    MainTab(subs.main, page, H)
    Later(subs.texts, "Texts come in the next step.")
    Later(subs.auras, "Buffs and debuffs come in a later step.")
    Later(subs.mt, "Main tank options come in a later step.")
    Later(subs.pets, "Pet options come in a later step.")
    strip:Bind(subs, function(k) strip:Select(k) Show(k) end)
    strip:Select("main")
    Show("main")
end, function() return ns.db.raid.enabled end)
