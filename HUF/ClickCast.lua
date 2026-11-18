-- HUF: click-casting on HUF's unit frames (player, target, target of target,
-- group). Each binding: a spell, a key or mouse button (with Shift / Ctrl /
-- Alt) and when it works: always, only in combat, only out of combat.
--
-- Mouse buttons are attributes on the unit buttons ("shift-type1" = macro).
-- Keys and the mouse wheel are bound while the mouse is over a frame: a
-- secure handler wraps OnEnter / OnLeave and sets override bindings that
-- click the frame with a virtual button ("hufkey3"). Every binding runs
--   /cast [@mouseover,combat] Spell; [@mouseover] Other spell
-- so it hits the unit under the mouse, like a @mouseover macro. Spell names
-- are the real ones (the game resolves them), never privacy names.
--
-- Bindings belong to the character (spells differ by class), not to the
-- profile: HUFDB.clickcast["First Last-Realm"].

local _, ns = ...

local CC = {}
ns.ClickCast = CC

local registered = {}       -- unit buttons that take click-casting
local handler               -- secure handler for key bindings

CC.WHEN = {
    { value = "BOTH", text = "Always" },
    { value = "COMBAT", text = "In combat" },
    { value = "NOCOMBAT", text = "Out of combat" },
}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
function CC.Data()
    HUFDB.clickcast = HUFDB.clickcast or {}
    local key = ns.CharKey()
    local d = HUFDB.clickcast[key]
    if type(d) ~= "table" then
        d = { enabled = true, bindings = {} }
        HUFDB.clickcast[key] = d
    end
    if type(d.bindings) ~= "table" then d.bindings = {} end
    if d.enabled == nil then d.enabled = true end
    return d
end

function CC.Bindings() return CC.Data().bindings end

function CC.Add()
    local list = CC.Bindings()
    list[#list + 1] = { spell = "", key = "", when = "BOTH" }
    return #list
end

function CC.Remove(i)
    table.remove(CC.Bindings(), i)
    CC.Apply()
end

---------------------------------------------------------------------------
-- Keys: "ALT-CTRL-SHIFT-BUTTON1", "SHIFT-F", "MOUSEWHEELUP"
---------------------------------------------------------------------------
local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
                Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MOUSE_TEXT = { BUTTON1 = "Left click", BUTTON2 = "Right click", BUTTON3 = "Middle click",
                     BUTTON4 = "Mouse button 4", BUTTON5 = "Mouse button 5",
                     MOUSEWHEELUP = "Wheel up", MOUSEWHEELDOWN = "Wheel down" }

-- modifiers and the key itself ("-" is a key of its own: "SHIFT--")
local function Split(key)
    if type(key) ~= "string" or key == "" then return nil end
    local base = key:match("%-(%-)$") or key:match("([^%-]+)$") or key
    local mods = key:sub(1, #key - #base)
    return base, mods:find("ALT%-") ~= nil, mods:find("CTRL%-") ~= nil, mods:find("SHIFT%-") ~= nil
end
CC.Split = Split

-- the key with modifiers in the game's order
function CC.MakeKey(base, alt, ctrl, shift)
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. base
end

function CC.MouseKey(button) return MOUSE[button] end

function CC.KeyText(key)
    local base, alt, ctrl, shift = Split(key)
    if not base then return "not set" end
    local parts = {}
    if alt then parts[#parts + 1] = "Alt" end
    if ctrl then parts[#parts + 1] = "Ctrl" end
    if shift then parts[#parts + 1] = "Shift" end
    local name = MOUSE_TEXT[base]
    if not name then
        name = (GetBindingText and GetBindingText(base, "KEY_")) or base
        if type(name) ~= "string" or name == "" then name = base end
    end
    parts[#parts + 1] = name
    return table.concat(parts, " + ")
end

local function MouseNumber(base) return base and tonumber(base:match("^BUTTON(%d)$")) end

-- the attribute prefix the secure code builds from held modifiers
local function Prefix(alt, ctrl, shift)
    return (alt and "alt-" or "") .. (ctrl and "ctrl-" or "") .. (shift and "shift-" or "")
end

---------------------------------------------------------------------------
-- Macros: one per key, combat-only and out-of-combat clauses first
---------------------------------------------------------------------------
local function Clause(b)
    local cond = (b.when == "COMBAT" and ",combat") or (b.when == "NOCOMBAT" and ",nocombat") or ""
    return ("[@mouseover%s] %s"):format(cond, b.spell)
end

-- { key = { macro text } } of the usable bindings
function CC.Plan()
    local byKey, order = {}, {}
    local d = CC.Data()
    if not d.enabled then return {}, {} end
    for _, b in ipairs(d.bindings) do
        local spell = type(b.spell) == "string" and ns.Trim(b.spell) or ""
        if spell ~= "" and Split(b.key) then
            local k = b.key
            if not byKey[k] then byKey[k] = { first = {}, rest = {} } order[#order + 1] = k end
            local e = { spell = spell, when = b.when }
            if b.when == "COMBAT" or b.when == "NOCOMBAT" then table.insert(byKey[k].first, e)
            else table.insert(byKey[k].rest, e) end
        end
    end
    local macros = {}
    for _, k in ipairs(order) do
        local clauses = {}
        for _, e in ipairs(byKey[k].first) do clauses[#clauses + 1] = Clause(e) end
        for _, e in ipairs(byKey[k].rest) do clauses[#clauses + 1] = Clause(e) end
        macros[k] = "/cast " .. table.concat(clauses, "; ")
    end
    return macros, order
end

---------------------------------------------------------------------------
-- Secure side
---------------------------------------------------------------------------
local ENTER = [[
    self:ClearBindings()
    local n = owner:GetAttribute("huf-keys") or 0
    for i = 1, n do
        local key = owner:GetAttribute("huf-key" .. i)
        if key then self:SetBindingClick(true, key, self, "hufkey" .. i) end
    end
]]
local LEAVE = [[ self:ClearBindings() ]]

local function Handler()
    if handler then return handler end
    handler = CreateFrame("Frame", "HUF_ClickCastHandler", UIParent, "SecureHandlerBaseTemplate")
    handler:SetAttribute("huf-keys", 0)
    return handler
end

local function Wrap(b)
    if b.hufWrapped then return end
    local h = Handler()
    h:WrapScript(b, "OnEnter", ENTER)
    h:WrapScript(b, "OnLeave", LEAVE)
    h:WrapScript(b, "OnHide", LEAVE)
    b.hufWrapped = true
end

-- clears what an earlier Apply put on the button, then sets the plan
local function ApplyTo(b, macros, keys)
    for _, name in ipairs(b.hufCC or {}) do b:SetAttribute(name, nil) end
    local set = {}
    local function Set(name, value)
        b:SetAttribute(name, value)
        set[#set + 1] = name
    end
    for i, k in ipairs(keys) do
        local base, alt, ctrl, shift = Split(k)
        local n = MouseNumber(base)
        if n then
            local p = Prefix(alt, ctrl, shift)
            Set(p .. "type" .. n, "macro")
            Set(p .. "macrotext" .. n, macros[k])
        else
            Set("*type-hufkey" .. i, "macro")
            Set("*macrotext-hufkey" .. i, macros[k])
        end
    end
    b.hufCC = set
    b.hufCCSet = {}
    for _, name in ipairs(set) do b.hufCCSet[name] = true end
end

function CC.Apply()
    ns.RunOOC("clickcast", function()
        local macros, keys = CC.Plan()
        local h = Handler()
        local n = 0
        for i, k in ipairs(keys) do
            local base = Split(k)
            if not MouseNumber(base) then
                n = math.max(n, i)
                h:SetAttribute("huf-key" .. i, k)
            else
                h:SetAttribute("huf-key" .. i, nil)
            end
        end
        for i = #keys + 1, (h.hufMax or 0) do h:SetAttribute("huf-key" .. i, nil) end
        h.hufMax = #keys
        h:SetAttribute("huf-keys", n)
        for b in pairs(registered) do
            local ok, err = pcall(ApplyTo, b, macros, keys)
            if not ok then ns.LogError("click-cast " .. tostring(b.hufLabel), err) end
        end
        local count = 0
        for _ in pairs(registered) do count = count + 1 end
        ns.Log("clickcast", "applied %d bindings to %d frames", #keys, count)
    end)
end

-- a unit button that takes click-casting (made outside combat)
function CC.Register(b)
    if registered[b] then return end
    ns.RunOOC("clickcast:" .. tostring(b), function()
        Wrap(b)
        registered[b] = true
        local macros, keys = CC.Plan()
        local ok, err = pcall(ApplyTo, b, macros, keys)
        if not ok then ns.LogError("click-cast " .. tostring(b.hufLabel), err) end
    end)
end

function CC.Report(add)
    local d = CC.Data()
    local macros, keys = CC.Plan()
    local count = 0
    for _ in pairs(registered) do count = count + 1 end
    add(("click-cast: enabled=%s bindings=%d usable=%d frames=%d"):format(tostring(d.enabled), #d.bindings, #keys, count))
    for _, k in ipairs(keys) do add(("  %s: %s"):format(k, macros[k])) end
end

---------------------------------------------------------------------------
-- Spells for the picker: the spellbook, by tab
---------------------------------------------------------------------------
function CC.Spells()
    local list, seen = {}, {}
    local function Add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = { value = name, text = name }
        end
    end
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local okN, lines = pcall(SB.GetNumSpellBookSkillLines)
        for l = 1, (okN and lines or 0) do
            local ok, info = pcall(SB.GetSpellBookSkillLineInfo, l)
            if ok and type(info) == "table" then
                list[#list + 1] = { header = true, text = info.name or ("Tab " .. l) }
                local first = info.itemIndexOffset or 0
                for i = first + 1, first + (info.numSpellBookItems or 0) do
                    local okI, item = pcall(SB.GetSpellBookItemInfo, i, bank)
                    if okI and type(item) == "table" and not item.isPassive and not item.isOffSpec then
                        local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
                        if not spellType or item.itemType == spellType then Add(item.name) end
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        for t = 1, GetNumSpellTabs() do
            local name, _, offset, num = GetSpellTabInfo(t)
            list[#list + 1] = { header = true, text = name or ("Tab " .. t) }
            for i = offset + 1, offset + num do
                local passive = IsPassiveSpell and IsPassiveSpell(i, "spell")
                if not passive then Add(GetSpellBookItemName(i, "spell")) end
            end
        end
    end
    -- drop empty headers
    local out = {}
    for i, e in ipairs(list) do
        if not (e.header and (not list[i + 1] or list[i + 1].header)) then out[#out + 1] = e end
    end
    return out
end

ns.OnLogin(function() CC.Apply() end)
