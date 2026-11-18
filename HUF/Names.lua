-- HUF: names shown on the frames.
--
-- Characters on WoW: Forever have a first and a last name. UnitName(unit)
-- returns both (the last name in the second value). Internally HUF always
-- works with the full real name; what the frames SHOW follows, in order:
--   1. a name provider (MMT's privacy setting for team members, Bridge.lua)
--   2. HUF's own privacy setting (Names page)
--   3. the name part chosen for that text (first / last / full name)
-- NPC names are never split or replaced.

local _, ns = ...
local IsSecret = ns.IsSecret

local function OwnRealm()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if IsSecret(r) then return "" end
    return r
end

function ns.NormKey(s)
    return ((s or ""):lower():gsub("[^%w\128-\255]", ""))
end

-- Real first and last name of a unit. Returns first, last (or nil), secret.
-- `first` may be a secret value; it is then only good for SetText.
function ns.UnitRealNames(unit)
    local ok, n, s = pcall(UnitName, unit)
    if not ok or n == nil then return nil end
    if IsSecret(n) then return n, nil, true end
    if n == "" then return nil end
    local isPlayer = ns.Bool(UnitIsPlayer(unit))
    if not isPlayer then return n, nil end            -- NPC: one name, never split
    local last
    if s and not IsSecret(s) and s ~= "" and ns.NormKey(s) ~= ns.NormKey(OwnRealm()) then last = s end
    if not last then
        -- some units carry "First Last" in the first value
        local a, b = n:match("^(%S+)%s+(.+)$")
        if a then n, last = a, b end
    end
    return n, last
end

-- full real name "First Last" (internal use: keys, lookups)
function ns.UnitFullName(unit)
    local first, last, secret = ns.UnitRealNames(unit)
    if not first or secret then return nil end
    return last and (first .. " " .. last) or first
end

---------------------------------------------------------------------------
-- Group order: "Slot X" and "Class X"
---------------------------------------------------------------------------
local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        for i = 1, (GetNumSubgroupMembers() or 0) do list[#list + 1] = "party" .. i end
    end
    return list
end

local function Same(a, b)
    local ok, v = pcall(UnitIsUnit, a, b)
    return ok and ns.Bool(v)
end

local function ClassLabel(class)
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    return names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- "Slot 2" / "Druid 1" for a unit in your group, else nil
function ns.PrivacyLabel(unit, mode)
    local units = GroupUnits()
    local slot
    for i, u in ipairs(units) do
        if Same(u, unit) then slot = i break end
    end
    if not slot then return nil end
    if mode == "SLOT" then return "Slot " .. slot end
    local class = ns.Safe(function() return select(2, UnitClass(unit)) end)
    if not class then return "Slot " .. slot end
    local n = 0
    for i = 1, slot do
        local c = ns.Safe(function() return select(2, UnitClass(units[i])) end)
        if c == class then n = n + 1 end
    end
    return ClassLabel(class) .. " " .. n
end

---------------------------------------------------------------------------
-- Name providers: function(unit, first, last) -> shown name or nil.
-- The first provider that returns a name wins (MMT registers one).
---------------------------------------------------------------------------
local providers = {}
function ns.RegisterNameProvider(id, fn)
    providers[id] = fn
    ns.RefreshNames()
end

-- token: PRIVACY ([name]: HUF's privacy setting) | FIRST | LAST | FULL
-- MMT team members always get MMT's privacy name (when the bridge says so).
function ns.NameText(unit, token, fake)
    if fake then
        local f, l = fake.first, fake.last
        if token == "PRIVACY" then
            local mode = ns.db.privacy.mode
            if fake.player and mode == "CLASS" then return ClassLabel(fake.class) .. " " .. (fake.classIndex or 1) end
            if fake.player and mode == "SLOT" then return "Slot " .. (fake.slot or 1) end
            token = (mode == "CLASS" or mode == "SLOT") and "FIRST" or mode
        end
        if token == "LAST" then return l or f end
        if token == "FULL" then return l and (f .. " " .. l) or f end
        return f
    end
    local first, last, secret = ns.UnitRealNames(unit)
    if first == nil then return "" end
    if secret then return first end                   -- the game hides it: shown as given
    if ns.Bool(UnitIsPlayer(unit)) then
        for _, fn in pairs(providers) do
            local ok, shown = pcall(fn, unit, first, last)
            if ok and type(shown) == "string" and shown ~= "" then return shown end
        end
        if token == "PRIVACY" then
            local mode = ns.db.privacy.mode
            if mode == "CLASS" or mode == "SLOT" then
                local label = ns.PrivacyLabel(unit, mode)
                if label then return label end
                token = "FIRST"
            else
                token = mode
            end
        end
    end
    if token == "LAST" then return last or first end
    if token == "FULL" then return last and (first .. " " .. last) or first end
    return first
end

-- names changed (privacy setting, team, group): every frame shows them again
function ns.RefreshNames()
    if ns.UpdateAllNames then ns.UpdateAllNames() end
end
ns.On("GROUP_ROSTER_UPDATE", function()
    ns.RefreshNames()
end)
