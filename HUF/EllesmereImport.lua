-- HUF: import the unit frames of an EllesmereUI profile string ("!EUI_...").
--
-- The string is read with EllesmereUI's own decoder (EllesmereUI has to be
-- loaded), so nothing is run: it is only parsed. Its Unit Frames settings
-- (player, target, target of target, pet) become HUF settings: size, position,
-- power bar, portrait, health / power texts, buffs and debuffs, bar texture,
-- colours, border, font. Everything else of the active HUF profile (group
-- frames, nameplates, accent, privacy ...) stays as it is.
-- The result looks close to Ellesmere's frames, not pixel-identical: what HUF
-- has no setting for is left out and listed after the import.

local _, ns = ...

local EUI_PREFIX = "!EUI_"
local UF_FOLDER = "EllesmereUIUnitFrames"

-- HUF frame key -> Ellesmere settings key
local UNIT_KEYS = { player = "player", target = "target", targettarget = "targettarget", pet = "pet" }

-- Ellesmere's defaults for the keys read here (a profile only stores what
-- differs, WoW Forever values). Per unit, then shared.
local EUI_DEFAULTS = {
    player = {
        frameWidth = 181, healthHeight = 46, powerHeight = 6, powerPosition = "below",
        healthClassColored = true, showPortrait = true, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "perhp",
        showBuffs = false, buffAnchor = "topleft", debuffAnchor = "none", maxDebuffs = 10,
    },
    target = {
        frameWidth = 181, healthHeight = 46, powerHeight = 6, powerPosition = "below",
        healthClassColored = true, showPortrait = true, portraitSide = "right",
        leftTextContent = "levelname", rightTextContent = "perhp",
        showBuffs = true, buffAnchor = "topleft", debuffAnchor = "bottomleft", maxDebuffs = 20,
    },
    targettarget = {
        frameWidth = 101, healthHeight = 25, powerPosition = "none",
        healthClassColored = false, showPortrait = false, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "none",
        showBuffs = false, debuffAnchor = "none",
    },
    pet = {
        frameWidth = 101, healthHeight = 25, powerHeight = 6, powerPosition = "below",
        healthClassColored = false, showPortrait = false, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "none",
        showBuffs = false, debuffAnchor = "none",
    },
    shared = {
        powerHeight = 6, powerPercentText = "none", powerTextFormat = "perpp", powerPercentSize = 9,
        portraitStyle = "attached", portraitMode = "2d",
        centerTextContent = "none", textSize = 12,
        maxBuffs = 4, buffSize = 22, debuffSize = 22,
        buffOffsetX = 0, buffOffsetY = 0, debuffOffsetX = 0, debuffOffsetY = 0,
        borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
        customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
    },
}
local EUI_POSITIONS = {
    player = { point = "CENTER", relPoint = "CENTER", x = -317, y = -193.5 },
    target = { point = "CENTER", relPoint = "CENTER", x = 317, y = -201 },
    pet = { point = "CENTER", relPoint = "CENTER", x = -300, y = -260 },
    targettarget = { point = "CENTER", relPoint = "CENTER", x = 383, y = -152.5 },
}

-- Ellesmere text contents -> HUF text templates (nil: HUF has no such value)
local CONTENT = {
    name = "[name]",
    levelname = "[level] | [name]",
    namelevel = "[name] | [level]",
    level = "[level]",
    both = "[hp] | [hp%]",
    bothdash = "[hp] - [hp%]",
    perhpnum = "[hp%] | [hp]",
    perhpnumdash = "[hp%] - [hp]",
    curhpshort = "[hp]",
    healthshort = "[hp]",
    curmaxhp = "[hp] / [hp:max]",
    perhp = "[hp%]",
    perhpnosign = "[hp%]",
    perpp = "[mp%]",
    curpp = "[mp]",
    curmaxpp = "[mp] / [mp:max]",
    curhp_curpp = "[hp] | [mp]",
    perhp_perpp = "[hp%] | [mp%]",
}
local POWER_CONTENT = {
    perpp = "[mp%]", curpp = "[mp]", curmaxpp = "[mp] / [mp:max]", both = "[mp] | [mp%]", smart = "[mp]",
}

local AURA_POS = {
    topleft = "ABOVE_LEFT", topright = "ABOVE_RIGHT",
    bottomleft = "BELOW_LEFT", bottomright = "BELOW_RIGHT",
    left = "LEFT", right = "RIGHT",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Num(v, d) if type(v) == "number" then return v end return d end
local function Color(c, d)
    if type(c) == "table" and type(c.r) == "number" then
        return { r = c.r, g = Num(c.g, 0), b = Num(c.b, 0) }
    end
    return ns.CopyTable(d)
end

-- one setting of an Ellesmere unit, its default when the profile has none
local function Getter(s, key)
    local d1, d2 = EUI_DEFAULTS[key] or {}, EUI_DEFAULTS.shared
    return function(k)
        local v = s[k]
        if v == nil then v = d1[k] end
        if v == nil then v = d2[k] end
        return v
    end
end

local function NewAnchor(text, size)
    return {
        text = text or "", font = "GLOBAL", size = size or 12, outline = "GLOBAL",
        colorMode = "WHITE", color = { r = 1, g = 1, b = 1 }, hideFull = false, x = 0, y = 0,
    }
end
local function EmptyTexts()
    local t = {}
    for _, a in ipairs(ns.ANCHORS) do t[a] = NewAnchor("", 12) end
    return t
end

-- HUF's name of an EllesmereUI bar texture (its file in EllesmereUI's folder)
local function TextureName(key)
    if key == nil or key == "none" then return "Flat" end
    if type(key) ~= "string" then return nil end
    local tail = ("textures\\" .. key):lower()
    for _, e in ipairs(ns.textures) do
        local p = type(e.path) == "string" and e.path:lower()
        if p and (p:sub(-#tail) == tail or p:sub(-#tail - 4) == tail .. ".tga") then return e.name end
    end
    -- a SharedMedia texture HUF also lists under the same name
    for _, e in ipairs(ns.textures) do
        if e.name == key then return e.name end
    end
    return nil
end

-- each note once (the texture note comes from every frame)
local function Unique(notes)
    local seen, list = {}, {}
    for _, n in ipairs(notes) do
        if not seen[n] then seen[n] = true list[#list + 1] = n end
    end
    return list
end

local function FontName(name)
    if type(name) ~= "string" then return nil end
    if name == "__blizzard" then return "Friz Quadrata" end
    local found
    for _, f in ipairs(ns.fonts) do
        if f.name == name or f.name == name .. " (EUI)" then
            -- the EllesmereUI copy first: that is the file Ellesmere draws with
            if f.ellesmere or not found then found = f.name end
        end
    end
    return found
end

---------------------------------------------------------------------------
-- Reading the string
---------------------------------------------------------------------------
function ns.IsEllesmereText(text)
    text = ns.Trim(text or "")
    return text:sub(1, #EUI_PREFIX) == EUI_PREFIX
end

-- the profile data of a decoded payload (a full-account string carries profiles)
local function ProfileOf(payload)
    local data = type(payload) == "table" and payload.data
    if type(data) ~= "table" then return nil end
    if type(data.addons) == "table" then return data end
    if type(data.profiles) == "table" then
        local name = data.activeProfile or payload.profileName or "Default"
        local p = data.profiles[name]
        if type(p) ~= "table" then
            for _, any in pairs(data.profiles) do if type(any) == "table" then p = any break end end
        end
        if type(p) == "table" then
            -- account-wide fonts live at the data root in that format
            if p.fonts == nil and type(data.fonts) == "table" then p.fonts = data.fonts end
            return p
        end
    end
    return nil
end

-- ok, Ellesmere's profile data (addons, fonts ...) or ok=false, error text
local function Decode(text)
    text = ns.Trim(text or "")
    local EUI = _G.EllesmereUI
    if type(EUI) ~= "table" or type(EUI.DecodeImportString) ~= "function" then
        return false, "EllesmereUI has to be loaded to read its strings (HUF uses its decoder)."
    end
    local ok, payload, err = pcall(EUI.DecodeImportString, text)
    if not ok then return false, "EllesmereUI could not read the text: " .. tostring(payload) end
    if not payload then return false, "EllesmereUI: " .. tostring(err or "could not read the text") end
    local prof = ProfileOf(payload)
    local uf = prof and prof.addons and prof.addons[UF_FOLDER]
    local np = prof and prof.addons and prof.addons[NP_FOLDER]
    if type(uf) ~= "table" and type(np) ~= "table" then
        return false, "This EllesmereUI string has no Unit Frames or Nameplates settings (export it with them ticked)."
    end
    return true, prof, type(uf) == "table" and uf or nil, type(np) == "table" and np or nil
end

---------------------------------------------------------------------------
-- Converting one frame
---------------------------------------------------------------------------
local function ConvertUnit(key, s, uf, u, notes)
    local G = Getter(s, key)
    local title = ns.UNIT_BY_KEY[key].title

    -- shown or not (frameSource "eui" / "blizzard" / "hidden", or the older enabledFrames flag)
    local src = type(uf.frameSource) == "table" and uf.frameSource[key]
    if src == nil and type(uf.enabledFrames) == "table" and uf.enabledFrames[key] == false then src = "hidden" end
    -- Blizzard's frame or none in Ellesmere: HUF's off (the import window can turn it on)
    u.enabled = (src == nil or src == "eui")

    -- power bar
    local pPos = G("powerPosition")
    local pH = Num(G("powerHeight"), 6)
    local power = pPos ~= "none" and pH > 0
    u.power.enabled = power
    u.power.size = math.max(1, math.floor(pH + 0.5))
    u.power.gap = 0
    if power and pPos ~= "below" then
        notes[#notes + 1] = ("%s: power bar \"%s\" is drawn below the health bar."):format(title, tostring(pPos))
    end

    -- size: Ellesmere's width is the bars', an attached portrait comes on top
    local hH = Num(G("healthHeight"), 30)
    local H = math.floor(hH + (power and pH or 0) + 0.5)
    local W = Num(G("frameWidth"), 175)
    u.height = math.max(4, H)

    -- portrait
    local style = G("portraitStyle")
    local por = G("showPortrait") and style ~= "none"
    u.portrait.enabled = por and true or false
    if por then
        local mode = G("portraitMode")
        if s.portraitMode == nil and type(uf.portraitMode) == "string" then mode = uf.portraitMode end
        u.portrait.mode = (mode == "3d" and "3D") or (mode == "class" and "CLASS") or "2D"
        u.portrait.side = (G("portraitSide") == "right") and "RIGHT" or "LEFT"
        u.portrait.gap = 0
        W = W + u.height
        if style == "detached" then
            notes[#notes + 1] = title .. ": the detached portrait is attached to the frame."
        end
    end
    u.width = math.floor(W + 0.5)

    -- position (centre of the screen based, like Ellesmere's)
    local pos = type(uf.positions) == "table" and uf.positions[key] or EUI_POSITIONS[key]
    if type(pos) == "table" then
        u.anchorTo = "SCREEN"
        u.point = { pos.point or "CENTER", pos.relPoint or pos.point or "CENTER",
                    math.floor(Num(pos.x, 0) + 0.5), math.floor(Num(pos.y, 0) + 0.5) }
    end

    -- bars: texture, colours, border
    local tex = TextureName(uf.healthBarTexture)
    if not tex then
        notes[#notes + 1] = ("Bar texture \"%s\" is not known to HUF: Flat instead."):format(tostring(uf.healthBarTexture))
        tex = "Flat"
    end
    local bSize = Num(G("borderSize"), 1)
    local bColor = Color(G("borderColor"), { r = 0, g = 0, b = 0 })
    local bg = Color(G("customBgColor"), { r = 0.067, g = 0.067, b = 0.067 })
    for _, which in ipairs({ "health", "power" }) do
        local b = u[which]
        b.texture = tex
        b.borderSize = math.floor(bSize + 0.5)
        b.borderColor = ns.CopyTable(bColor)
        b.borderAlpha = 1
        b.bgTexture = "Plain"
        b.bgColor = ns.CopyTable(bg)
        b.bgAlpha = 1
    end
    local h = u.health
    if G("healthClassColored") or not (type(s.customFillColor) == "table" or uf.darkTheme) then
        h.colorMode = "CLASS"
        h.npcReaction = true
    else
        h.colorMode = "STATIC"
        h.color = uf.darkTheme and not s.customFillColor and { r = 0.067, g = 0.067, b = 0.067 }
            or Color(s.customFillColor, h.color)
    end
    if s.bgClassColored then notes[#notes + 1] = title .. ": class coloured background is a plain colour." end
    -- power fill: Ellesmere's power colours by type (the import sets them
    -- globally), a custom fill with "power colour" off, or the class colour
    if s.powerPercentPowerColor == false then
        u.power.colorMode = "STATIC"
        u.power.color = Color(s.customPowerFillColor, { r = 0, g = 0, b = 1 })
    elseif s.powerClassColored then
        u.power.colorMode = "CLASS"
    else
        u.power.colorMode = "TYPE"
    end

    -- texts on the health bar: left / center / right, and the extra text
    -- (its own alignment). Ellesmere sets them 5 px in from the bar's edge
    -- (HUF 2) and centres them vertically; an extra text whose spot is taken
    -- goes to the bottom (or top) anchor, moved to the same place.
    local texts = EmptyTexts()
    local base = Num(G("textSize"), 12)
    local barH = math.max(1, H - (power and pH or 0))
    local function Slot(p, anchor)
        local content = G(p .. "TextContent")
        if not content or content == "none" then return end
        local tpl = CONTENT[content]
        if not tpl then
            notes[#notes + 1] = ("%s: %s text \"%s\" has no HUF value, left out."):format(title, p, tostring(content))
            return
        end
        local size = Num(s[p .. "TextSize"], base)
        local a = NewAnchor(tpl, size)
        a.x, a.y = Num(s[p .. "TextX"], 0), Num(s[p .. "TextY"], 0)
        if texts[anchor].text ~= "" then
            -- spot taken: bottom anchor (text bottom at the bar's bottom), else top
            local side = anchor == "CENTER" and "" or anchor
            local bottom, top = "BOTTOM" .. side, "TOP" .. side
            if texts[bottom].text == "" then
                anchor, a.y = bottom, a.y + barH / 2 - size / 2
            elseif texts[top].text == "" then
                anchor, a.y = top, a.y - barH / 2 + size / 2
            else
                notes[#notes + 1] = ("%s: no free spot for the %s text, left out."):format(title, p)
                return
            end
        end
        if anchor:find("LEFT") then a.x = a.x + 3 elseif anchor:find("RIGHT") then a.x = a.x - 3 end
        a.y = math.floor(a.y + 0.5)
        if s[p .. "TextClassColor"] then
            a.colorMode = "CLASS"
        elseif type(s[p .. "TextColorR"]) == "number" then
            a.colorMode = "CUSTOM"
            a.color = { r = s[p .. "TextColorR"], g = Num(s[p .. "TextColorG"], 1), b = Num(s[p .. "TextColorB"], 1) }
            if a.color.r == 1 and a.color.g == 1 and a.color.b == 1 then a.colorMode = "WHITE" end
        end
        texts[anchor] = a
    end
    Slot("left", "LEFT")
    Slot("center", "CENTER")
    Slot("right", "RIGHT")
    local align = G("extraTextAlign")
    Slot("extra", (align == "right" and "RIGHT") or (align == "center" and "CENTER") or "LEFT")
    u.texts.health = texts

    -- power text
    local ptexts = EmptyTexts()
    local ppos = G("powerPercentText")
    if power and ppos and ppos ~= "none" then
        local tpl = POWER_CONTENT[G("powerTextFormat") or "perpp"]
        if tpl then
            local anchor = (ppos == "left" and "LEFT") or (ppos == "right" and "RIGHT") or "CENTER"
            local a = NewAnchor(tpl, Num(G("powerPercentSize"), 9))
            a.x, a.y = Num(s.powerPercentX, 0), Num(s.powerPercentY, 0)
            ptexts[anchor] = a
        else
            notes[#notes + 1] = title .. ": custom power text left out."
        end
    end
    u.texts.power = ptexts

    -- buffs / debuffs (the pet has none in HUF)
    if not ns.UNIT_BY_KEY[key].noAuras and u.buffs and u.debuffs then
        local barW = u.width - (por and u.height or 0)
        local function Row(r, on, anchor, max, size, ox, oy)
            r.enabled = on and AURA_POS[anchor] ~= nil
            if not r.enabled then return end
            r.position = AURA_POS[anchor]
            r.size = math.max(8, math.floor(size + 0.5))
            r.gap = 1
            max = math.max(1, math.floor(max))
            local fit = math.max(1, math.floor((barW + r.gap) / (r.size + r.gap)))
            if r.position == "LEFT" or r.position == "RIGHT" then fit = max end
            r.perRow = math.min(max, fit)
            r.rows = math.max(1, math.ceil(max / r.perRow))
            r.offset = 1
            r.x, r.y = ox, oy
        end
        Row(u.buffs, G("showBuffs"), G("buffAnchor"), Num(G("maxBuffs"), 4), Num(G("buffSize"), 22),
            Num(G("buffOffsetX"), 0), Num(G("buffOffsetY"), 0))
        u.buffs.timer = true
        u.buffs.countSize = math.floor(Num(s.buffStackTextSize, u.buffs.countSize) + 0.5)
        u.buffs.timerText = s.buffShowCooldownText and true or false
        u.buffs.timerSize = Num(s.buffCooldownTextSize, 0)
        Row(u.debuffs, true, G("debuffAnchor"), Num(G("maxDebuffs"), 10), Num(G("debuffSize"), 22),
            Num(G("debuffOffsetX"), 0), Num(G("debuffOffsetY"), 0))
        u.debuffs.mine = s.onlyPlayerDebuffs and true or false
        u.debuffs.timer = true
        u.debuffs.countSize = math.floor(Num(s.debuffStackTextSize, u.debuffs.countSize) + 0.5)
        u.debuffs.timerText = s.debuffShowCooldownText and true or false
        u.debuffs.timerSize = Num(s.debuffCooldownTextSize, 0)
    end
    return src
end

---------------------------------------------------------------------------
-- Nameplates (EllesmereUINameplates)
---------------------------------------------------------------------------
local NP_FOLDER = "EllesmereUINameplates"
local NP_SLOTS = { { "textSlotTop", "ABOVE" }, { "textSlotLeft", "LEFT" }, { "textSlotCenter", "CENTER" }, { "textSlotRight", "RIGHT" } }
local NP_DEFAULTS = {
    healthBarWidth = 6, healthBarHeight = 17, healthBarTexture = "none",
    showBorder = true, borderSize = 1, borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    textSlotTop = "enemyName", textSlotLeft = "level", textSlotCenter = "none", textSlotRight = "healthPercent",
    textSlotTopSize = 12, textSlotLeftSize = 10, textSlotCenterSize = 10, textSlotRightSize = 10,
    textSlotTopYOffset = 3,
    castBarHeight = 17, castNameSize = 10, castBar = { r = 0.70, g = 0.40, b = 0.90 },
    debuffIconSize = 26, maxDebuffs = 5, debuffSpacing = 2,
    friendlyNameOnly = true, nameplateYOffset = 0,
}
local NP_HEALTH = { healthPercent = "[hp%]", healthPercentNoSign = "[hp%:nosign]", healthNumber = "[hp]" }

local function FontByPath(path)
    if type(path) ~= "string" then return nil end
    local want = path:lower():gsub("/", "\\")
    for _, f in ipairs(ns.fonts) do
        if type(f.path) == "string" and f.path:lower() == want then return f.name end
    end
    return nil
end

local function ConvertNameplates(s, n, notes)
    local function G(k) local v = s[k] if v == nil then v = NP_DEFAULTS[k] end return v end
    n.enabled = true
    n.width = math.floor(150 + Num(G("healthBarWidth"), 6) + 0.5)
    n.height = math.max(2, math.floor(Num(G("healthBarHeight"), 17) + 0.5))
    local texKey = G("healthBarTexture")
    n.texture = (texKey == "blizzard" and "Blizzard") or TextureName(texKey) or "Flat"
    n.borderSize = G("showBorder") and Num(G("borderSize"), 1) or 0
    n.borderColor = Color(G("borderColor"), { r = 0.067, g = 0.067, b = 0.067 })
    n.colorMode = "CLASS"
    n.tappedGray = true
    -- Ellesmere colours hostile mobs with its "enemy" colour, darkened out of combat
    n.reactionColors = "CUSTOM"
    n.hostileColor = Color(s.enemyInCombat, { r = 0.80, g = 0.137, b = 0.137 })
    n.neutralColor = Color(s.neutral, { r = 0.81, g = 0.72, b = 0.19 })
    n.friendlyColor = Color(s.friendlyNPCColor, { r = 0, g = 1, b = 0 })
    local dim = s.darkenEnemiesOOC
    if dim == nil then dim = true end
    n.dimOutOfCombat = dim and true or false
    n.yOffset = math.floor(Num(G("nameplateYOffset"), 0) + 0.5)
    n.font = FontByPath(s.font) or FontName(s.font) or "GLOBAL"

    -- texts: the slot holding the name decides where it goes
    local nameSlot, nameEl, levelSlot, hpSlot, hpEl
    for _, sl in ipairs(NP_SLOTS) do
        local el = G(sl[1])
        if el == "enemyName" or el == "levelName" or el == "nameLevel" then
            if not nameSlot then nameSlot, nameEl = sl, el end
        elseif el == "level" then
            levelSlot = sl
        elseif NP_HEALTH[el] then
            if not hpSlot then hpSlot, hpEl = sl, el end
        elseif el and el ~= "none" then
            notes[#notes + 1] = ("Nameplates: text \"%s\" has no HUF value, left out."):format(tostring(el))
        end
    end
    if nameSlot then
        n.mode = "NAME_BAR"
        n.namePosition = nameSlot[2] == "RIGHT" and "LEFT" or nameSlot[2]
        n.fontSize = math.floor(Num(G(nameSlot[1] .. "Size"), 11) + 0.5)
        n.showLevel = nameEl ~= "enemyName" or levelSlot ~= nil
        n.levelSep = nameEl == "enemyName" and " " or " | "
        if nameEl == "nameLevel" then notes[#notes + 1] = "Nameplates: the level comes before the name in HUF." end
        if nameEl == "enemyName" and levelSlot then notes[#notes + 1] = "Nameplates: the level is shown before the name." end
        if n.namePosition == "ABOVE" then n.nameGap = math.floor(Num(G("textSlotTopYOffset"), 3) + 0.5) end
        if s[nameSlot[1] .. "ClassColor"] or (nameSlot[1] == "textSlotTop" and s.enemyNameTextReactionColor) then
            n.nameColor = "REACTION"
        else
            local c = s[nameSlot[1] .. "Color"]
            if type(c) == "table" and type(c.r) == "number" and not (c.r == 1 and c.g == 1 and c.b == 1) then
                n.nameColor, n.nameCustom = "CUSTOM", Color(c, { r = 1, g = 1, b = 1 })
            else
                n.nameColor = "WHITE"
            end
        end
    else
        n.mode = "BAR"
    end
    n.showHealth = hpSlot ~= nil
    if hpSlot then
        n.healthTag = NP_HEALTH[hpEl]
        n.healthSize = math.floor(Num(G(hpSlot[1] .. "Size"), 10) + 0.5)
        if hpSlot[2] ~= "RIGHT" then notes[#notes + 1] = "Nameplates: the health text is on the right of the bar." end
    end
    n.friendlyMode = G("friendlyNameOnly") and "NAME" or "SAME"

    -- cast bar and debuffs
    n.castHeight = math.max(2, math.floor(Num(G("castBarHeight"), 17) + 0.5))
    n.castFontSize = math.floor(Num(G("castNameSize"), 10) + 0.5)
    n.castColor = Color(G("castBar"), n.castColor)
    n.castIcon = true
    n.auraSize = math.max(8, math.floor(Num(G("debuffIconSize"), 26) + 0.5))
    n.auraMax = math.max(1, math.floor(Num(G("maxDebuffs"), 5)))
    n.auraGap = math.floor(Num(G("debuffSpacing"), 2) + 0.5)
    n.auraTimer = true
    n.auraTimerSize = math.floor(Num(s.auraDurationTextSize, 11) + 0.5)
    if s.threatColorHealth ~= false then
        notes[#notes + 1] = "Nameplates: Ellesmere's threat, caster and mini-boss colours are not in HUF."
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- prof: Ellesmere profile data (addons, fonts); uf / np its Unit Frames /
-- Nameplates settings (nil: not there)
-- npOn: false when Ellesmere's nameplates are off (not loaded)
-- parts: what the import turns on or off, for the import window:
--   { title, tbl (its settings: .enabled), on, why (Ellesmere's state when off) }
local UNIT_ORDER = { "player", "target", "targettarget", "pet" }
local function Convert(prof, uf, np, npOn)
    local out = ns.CopyTable(ns.db)
    ns.FillDefaults(out, ns.DEFAULTS)
    local notes, what, parts = {}, {}, {}

    if uf then what[#what + 1] = "unit frames" end
    for _, hufKey in ipairs(uf and UNIT_ORDER or {}) do
        local s = uf[UNIT_KEYS[hufKey]]
        if type(s) ~= "table" then s = {} end
        if hufKey == "targettarget" and next(s) == nil and type(uf.totPet) == "table" then s = uf.totPet end
        local u = out.units[hufKey]
        local okC, src = pcall(ConvertUnit, hufKey, s, uf, u, notes)
        if not okC then return false, ("Could not convert the %s frame: %s"):format(hufKey, tostring(src)) end
        parts[#parts + 1] = { title = ns.UNIT_BY_KEY[hufKey].title, tbl = u, on = u.enabled,
            why = (src == "blizzard" and "Blizzard's frame in Ellesmere") or "off in Ellesmere" }
    end
    if np then
        local okN, err = pcall(ConvertNameplates, np, out.nameplates, notes)
        if not okN then return false, "Could not convert the nameplates: " .. tostring(err) end
        what[#what + 1] = "nameplates"
        out.nameplates.enabled = npOn ~= false
        parts[#parts + 1] = { title = "Nameplates", tbl = out.nameplates, on = out.nameplates.enabled,
            why = "EllesmereUI Nameplates is off" }
    end

    -- font and outline (Ellesmere's Unit Frames font, else its global one)
    if not uf then return true, out, Unique(notes), what, parts end

    -- power colours by type: Ellesmere's palette (its defaults + the profile's own)
    local EUI = _G.EllesmereUI
    local defaults = type(EUI) == "table" and type(EUI.DEFAULT_POWER_COLORS) == "table" and EUI.DEFAULT_POWER_COLORS or {}
    local own = type(prof.customColors) == "table" and type(prof.customColors.power) == "table" and prof.customColors.power or {}
    local any = false
    for _, k in ipairs({ "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER" }) do
        local c = own[k] or defaults[k]
        if type(c) == "table" and type(c.r) == "number" then
            out.global.customPower[k] = Color(c, out.global.customPower[k])
            any = true
        end
    end
    if any then out.global.powerColors = "CUSTOM" end
    local fonts = type(prof.fonts) == "table" and prof.fonts or {}
    local fontName, outline = fonts.global, fonts.outlineMode
    for _, e in ipairs(type(fonts.moduleFonts) == "table" and fonts.moduleFonts or {}) do
        if type(e) == "table" and e.folder == UF_FOLDER then
            if type(e.font) == "string" and e.font ~= "__global" then fontName = e.font end
            if type(e.outline) == "string" and e.outline ~= "__global" then outline = e.outline end
        end
    end
    local f = FontName(fontName or "Expressway")
    if f then out.global.font = f
    elseif fontName then notes[#notes + 1] = ("Font \"%s\" is not known to HUF: kept %s."):format(fontName, out.global.font) end
    outline = outline or "shadow"
    if outline == "outline" then out.global.outline, out.global.shadow = "OUTLINE", false
    elseif outline == "thick" then out.global.outline, out.global.shadow = "THICKOUTLINE", false
    elseif outline == "shadow" then out.global.outline, out.global.shadow = "NONE", true
    else out.global.outline, out.global.shadow = "NONE", false end

    -- frames that point at an imported frame keep working; a frame that is
    -- anchored to one turned off goes back to the screen
    for _, u in pairs(out.units) do
        if u.anchorTo and u.anchorTo ~= "SCREEN" and out.units[u.anchorTo] and not out.units[u.anchorTo].enabled then
            u.anchorTo = "SCREEN"
            u.point = { "CENTER", "CENTER", 0, -200 }
        end
    end

    if type(uf.focus) == "table" or type(uf.boss) == "table" then
        notes[#notes + 1] = "Focus and boss frames: HUF has none, left out."
    end
    return true, out, Unique(notes), what, parts
end

-- ok, a whole HUF profile (the active one with Ellesmere's frames), notes,
-- what was taken ({ "unit frames", "nameplates" }) or ok=false, error text
function ns.ReadEllesmereText(text)
    local ok, prof, uf, np = Decode(text)
    if not ok then return false, prof end
    return Convert(prof, uf, np)
end

-- the same from EllesmereUI's current settings in this game (no string):
-- the loaded modules' live settings, else what its active profile stored
function ns.ReadEllesmereLive()
    local EUI = _G.EllesmereUI
    if type(EUI) ~= "table" or type(EUI.SnapshotAllAddons) ~= "function" then
        return false, "EllesmereUI is not loaded."
    end
    local okS, data = pcall(EUI.SnapshotAllAddons)
    if not okS or type(data) ~= "table" then return false, "Could not read EllesmereUI's settings: " .. tostring(data) end
    data.addons = type(data.addons) == "table" and data.addons or {}
    local db = _G.EllesmereUIDB
    local stored = type(db) == "table" and type(db.profiles) == "table" and db.profiles[db.activeProfile or "Default"]
    local saved = type(stored) == "table" and type(stored.addons) == "table" and stored.addons or {}
    local uf = data.addons[UF_FOLDER] or saved[UF_FOLDER]
    local np = data.addons[NP_FOLDER] or saved[NP_FOLDER]
    -- only loaded modules are in the snapshot: from the stored copy = Ellesmere has them off
    local npOn = data.addons[NP_FOLDER] ~= nil
    if type(uf) ~= "table" and type(np) ~= "table" then
        return false, "EllesmereUI has no Unit Frames or Nameplates settings here."
    end
    return Convert(data, type(uf) == "table" and uf or nil, type(np) == "table" and np or nil, npOn)
end

-- EllesmereUI's nameplates and HUF's both on: two plates on every unit
ns.OnLogin(function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(NP_FOLDER)
    if loaded and ns.db.nameplates.enabled then
        ns.Print("EllesmereUI Nameplates is on too, so every unit gets two nameplates. Turn off one of them (HUF: /huf > Nameplates).")
    end
end)
