-- HUF: buff and debuff icon rows, for the unit frames and the nameplates.
--
-- 12.x: the game's own aura containers (Blizzard_AuraContainer) do the work
-- when the client has them. They read the auras in C, so they keep working
-- where an addon may not read auras itself (nameplates, party, combat). Each
-- row holds two groups with fixed filters ("all" and "mine"); the one not in
-- use is parked at 0 icons. Without containers a row falls back to a plain
-- C_UnitAuras scan, and every failure of that scan goes to the debug log.

local _, ns = ...
local A = {}
ns.Auras = A

local floor = math.floor

---------------------------------------------------------------------------
-- Does the client have aura containers?
---------------------------------------------------------------------------
local engine, spare
local function Engine()
    if engine ~= nil then return engine end
    engine = false
    if C_AddOns and C_AddOns.LoadAddOn then
        local loaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
        if not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and c and c.AddAuraGroup and c.SetUnit then
        engine = true
        c:Hide()
        spare = c
    end
    ns.Log("auras", "game aura containers: %s%s", engine and "yes" or "no (plain scan)",
        ok and "" or (" - " .. tostring(c)))
    return engine
end
A.Engine = Engine

-- are auras hidden from addons right now?
function A.Restricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and ns.Bool(r) then return true end
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
    return not pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
end

local function Filter(kind, mine) return mine and (kind .. "|PLAYER") or kind end
A.Filter = Filter

local function Flow(token)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if not FD then return nil end
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-- the layout setters were renamed once; old names as fallback
local function Call(c, new, old, ...)
    local fn = c[new] or (old and c[old])
    if fn then return pcall(fn, c, ...) end
    return false, "no " .. new
end

---------------------------------------------------------------------------
-- A row
--   cfg: enabled, kind ("HARMFUL" / "HELPFUL"), mine, size, gap, perRow,
--        rows, point {point, rel, relPoint, x, y}, anchor (= point[1]),
--        growH ("LEFT"/"RIGHT"), growV ("UP"/"DOWN"), countSize, timer,
--        timerText (time left as numbers), timerSize (0: from the icon size)
---------------------------------------------------------------------------
local Row = {}
Row.__index = Row
local rows = {}

function A.NewRow(parent, label, plate)
    local r = setmetatable({
        parent = parent, label = label, plate = plate,
        buttons = {}, bdata = {}, icons = {}, errors = 0,
    }, Row)
    r.holder = CreateFrame("Frame", nil, parent)
    r.holder:SetSize(1, 1)
    r.holder:EnableMouse(false)
    r.ev = CreateFrame("Frame")
    r.ev:SetScript("OnEvent", function() r:Scan() end)
    rows[#rows + 1] = r
    return r
end

function Row:Fail(what, err)
    self.errors = self.errors + 1
    if self.errors <= 3 then
        ns.Log("auras", "%s: %s failed: %s", self.label, what, tostring(err))
    end
end

-- time left as numbers: the cooldown's own countdown (the game counts it,
-- so it also works while the aura's times are secret)
local function TimerSize(cfg)
    local s = cfg.timerSize or 0
    if s > 0 then return s end
    return math.max(7, math.floor((cfg.size or 20) * 0.5 + 0.5))
end
local function StyleTimer(cd, cfg)
    cd:SetHideCountdownNumbers(not cfg.timerText)
    if cd.SetCountdownAbbrevThreshold then pcall(cd.SetCountdownAbbrevThreshold, cd, 100) end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        ns.ApplyFont(fs, "GLOBAL", TimerSize(cfg), "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 0)
    end
end

-- icon look shared by engine buttons and scan icons
local function Dress(b, cfg, top)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(cd, cfg)
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(cd:GetFrameLevel() + 2)
    over:EnableMouse(false)
    local count = over:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(count, "GLOBAL", cfg.countSize or 9, "OUTLINE")   -- a font before any text
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    count:SetJustifyH("RIGHT")
    return { icon = icon, cd = cd, count = count, timerText = cfg.timerText, timerSize = TimerSize(cfg) }
end

---------------------------------------------------------------------------
-- Engine rows
---------------------------------------------------------------------------
local function GroupLayout(cfg)
    return { elementWidth = cfg.size, elementHeight = cfg.size,
             elementSpacing = cfg.gap, lineSpacing = cfg.gap }
end

function Row:InitButton(b)
    local cfg = self.cfg
    -- everything is made and given a font first: registering runs the
    -- button's own update, which writes into these right away
    local d = Dress(b, cfg)
    b:SetSize(cfg.size, cfg.size)
    pcall(b.SetMouseClickEnabled, b, false)
    if self.plate then pcall(b.EnableMouse, b, false) end
    b:SetIcon(d.icon)
    b:SetDurationCooldown(d.cd)
    b:SetApplicationCount(d.count, {})
    d.size, d.countSize = cfg.size, cfg.countSize
    self.bdata[b] = d
    self.buttons[#self.buttons + 1] = b
end

function Row:BuildEngine()
    local c = spare
    spare = nil
    if c then
        c:SetParent(self.parent)
    else
        c = CreateFrame("AuraContainer", nil, self.parent, "CustomAuraContainerTemplate")
    end
    c:ClearAllPoints()
    c:SetPoint("CENTER", self.parent, "CENTER")
    c:SetSize(1, 1)
    local cfg = self.cfg
    local cap = cfg.perRow * cfg.rows
    self.c = c
    self.kind = cfg.kind
    local init = function(b)
        local ok, err = pcall(self.InitButton, self, b)
        if not ok then self:Fail("icon setup", err) end
    end
    for _, mine in ipairs({ false, true }) do
        c:AddAuraGroup(mine and "mine" or "all", Filter(cfg.kind, mine), {
            maxFrameCount = cap,
            initializeFrame = init,
            layout = GroupLayout(cfg),
        })
    end
    ns.Log("auras", "%s: game container ready (%s)", self.label, cfg.kind)
end

local function SetCap(c, key, cap)
    if c.SetAuraGroupEnabled then
        if cap > 0 then pcall(c.SetAuraGroupEnabled, c, key, true) end
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
        if cap <= 0 then pcall(c.SetAuraGroupEnabled, c, key, false) end
    else
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
    end
end

-- icon size and stack font (denied while auras are hidden: tried again later)
function Row:Resize()
    local cfg = self.cfg
    self.pendingResize = nil
    for _, b in ipairs(self.buttons) do
        local d = self.bdata[b]
        if d.size ~= cfg.size then
            if pcall(b.SetSize, b, cfg.size, cfg.size) then d.size = cfg.size
            else self.pendingResize = true end
        end
        if d.countSize ~= cfg.countSize then
            if pcall(ns.ApplyFont, d.count, "GLOBAL", cfg.countSize, "OUTLINE") then d.countSize = cfg.countSize
            else self.pendingResize = true end
        end
        if d.timer ~= cfg.timer then
            if pcall(d.cd.SetDrawSwipe, d.cd, cfg.timer ~= false) then d.timer = cfg.timer
            else self.pendingResize = true end
        end
        if d.timerText ~= cfg.timerText or d.timerSize ~= TimerSize(cfg) then
            if pcall(StyleTimer, d.cd, cfg) then d.timerText, d.timerSize = cfg.timerText, TimerSize(cfg)
            else self.pendingResize = true end
        end
    end
end

function Row:ApplyEngine()
    local c, cfg = self.c, self.cfg
    c:ClearAllPoints()
    c:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    Call(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", cfg.anchor)
    Call(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", Flow(cfg.growH), Flow(cfg.growV))
    -- room for perRow icons, never perRow + 1 (works whether or not the
    -- engine counts the space after the last icon)
    Call(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", cfg.perRow * (cfg.size + cfg.gap) + 0.4)
    local cap = cfg.perRow * cfg.rows
    for key, on in pairs({ all = not cfg.mine, mine = cfg.mine and true or false }) do
        pcall(c.SetAuraGroupLayout, c, key, GroupLayout(cfg))
        SetCap(c, key, on and cap or 0)
    end
    self:Resize()
    c:Show()
    self:BindEngine()
end

function Row:BindEngine()
    local c = self.c
    local unit = (self.cfg and self.cfg.enabled) and self.unit or nil
    if unit then
        if self.bound ~= unit then
            local ok, err = pcall(c.SetUnit, c, unit)
            if not ok then self:Fail("SetUnit " .. unit, err) end
            self.bound = unit
        end
        pcall(c.UpdateAllAuras, c)
    elseif self.bound then
        if not pcall(c.SetUnit, c, "none") then pcall(c.SetUnit, c, nil) end
        self.bound = nil
    end
end

---------------------------------------------------------------------------
-- Scan rows (no containers, or a container couldn't be made)
---------------------------------------------------------------------------
function Row:Icon(i)
    local b = self.icons[i]
    if not b then
        b = CreateFrame("Frame", nil, self.holder)
        b.d = Dress(b, self.cfg)
        b:EnableMouse(false)
        self.icons[i] = b
    end
    local cfg = self.cfg
    b:SetSize(cfg.size, cfg.size)
    ns.ApplyFont(b.d.count, "GLOBAL", cfg.countSize or 9, "OUTLINE")
    b.d.cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(b.d.cd, cfg)
    return b
end

function Row:Place(b, n)
    local cfg = self.cfg
    local i = n - 1
    local col, line = i % cfg.perRow, floor(i / cfg.perRow)
    local step = cfg.size + cfg.gap
    local dx = col * step * (cfg.growH == "LEFT" and -1 or 1)
    local dy = line * step * (cfg.growV == "DOWN" and -1 or 1)
    b:ClearAllPoints()
    b:SetPoint(cfg.anchor, self.holder, cfg.anchor, dx, dy)
end

function Row:LayoutHolder()
    local cfg = self.cfg
    local h = self.holder
    h:ClearAllPoints()
    h:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    h:SetSize(math.max(1, cfg.perRow * (cfg.size + cfg.gap)), math.max(1, cfg.rows * (cfg.size + cfg.gap)))
end

function Row:Scan()
    local cfg = self.cfg
    local n = 0
    local unit = self.unit
    if cfg and cfg.enabled and unit and not self.c and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        and ns.Bool(UnitExists(unit)) then
        local filter = Filter(cfg.kind, cfg.mine)
        local max = cfg.perRow * cfg.rows
        for i = 1, 40 do
            if n >= max then break end
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then self:Fail("reading " .. unit .. " " .. filter, a) break end
            if type(a) ~= "table" then break end
            n = n + 1
            local b = self:Icon(n)
            self:Place(b, n)
            pcall(b.d.icon.SetTexture, b.d.icon, a.icon)
            local cnt = a.applications
            if ns.IsSecret(cnt) or type(cnt) ~= "number" or cnt < 2 then b.d.count:SetText("")
            else b.d.count:SetText(cnt) end
            local dur, exp = a.duration, a.expirationTime
            if not ns.IsSecret(dur) and not ns.IsSecret(exp) and type(dur) == "number"
                and type(exp) == "number" and dur > 0 then
                b.d.cd:SetCooldown(exp - dur, dur)
                b.d.cd:Show()
            else
                b.d.cd:Hide()
            end
            b:Show()
        end
    end
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Public row methods
---------------------------------------------------------------------------
function Row:Configure(cfg)
    self.cfg = cfg
    self.preview = nil
    self:LayoutHolder()
    if not cfg.enabled then
        self:Disable()
        return
    end
    if not self.c and not self.noEngine and Engine() then
        local ok, err = pcall(self.BuildEngine, self)
        if not ok then
            self:Fail("game container", err)
            if self.c then self.c:Hide() end
            self.c = nil
            self.noEngine = true       -- this row scans from now on
        end
    end
    if self.c then
        for _, b in ipairs(self.icons) do b:Hide() end
        self.ev:UnregisterAllEvents()
        local ok, err = pcall(self.ApplyEngine, self)
        if not ok then self:Fail("layout", err) end
    else
        self:WatchScan()
        self:Scan()
    end
end

function Row:WatchScan()
    self.ev:UnregisterAllEvents()
    if self.unit and self.cfg and self.cfg.enabled and not self.c then
        pcall(self.ev.RegisterUnitEvent, self.ev, "UNIT_AURA", self.unit)
    end
end

function Row:Disable()
    self.ev:UnregisterAllEvents()
    for _, b in ipairs(self.icons) do b:Hide() end
    if self.c then
        self.c:Hide()
        self:BindEngine()
    end
end

function Row:SetUnit(unit)
    if ns.IsSecret(unit) then unit = nil end
    self.unit = unit
    if not self.cfg then return end
    if self.c then self:BindEngine()
    else
        self:WatchScan()
        self:Scan()
    end
end

-- the unit token now means someone else (target swapped, polled units)
function Row:Refresh()
    if not (self.cfg and self.cfg.enabled) or self.preview then return end
    if self.c then
        if self.bound then pcall(self.c.UpdateAllAuras, self.c) end
    else
        self:Scan()
    end
end

-- unlock mode: sample icons, nothing read from the game
local SAMPLE = { 136118, 135812, 136207, 132090, 136197, 135848, 132316, 136139 }
function Row:Preview(cfg, n)
    self.cfg = cfg
    self.preview = true
    self:LayoutHolder()
    self.ev:UnregisterAllEvents()
    if self.c then self.c:Hide() end
    n = cfg.enabled and math.min(n or 3, cfg.perRow * cfg.rows) or 0
    for i = 1, n do
        local b = self:Icon(i)
        self:Place(b, i)
        b.d.icon:SetTexture(SAMPLE[(i - 1) % #SAMPLE + 1])
        b.d.count:SetText(i == 2 and "3" or "")
        b.d.cd:Hide()
        b:Show()
    end
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

function Row:Info()
    local cfg = self.cfg
    if not cfg then return "not set up" end
    if not cfg.enabled then return "off" end
    if self.preview then return "preview" end
    if self.c then
        return ("game container, unit %s, %d icons made%s"):format(tostring(self.bound), #self.buttons,
            self.pendingResize and ", resize pending" or "")
    end
    local shown = 0
    for _, b in ipairs(self.icons) do if b:IsShown() then shown = shown + 1 end end
    return ("scan, unit %s, %d shown, %d errors"):format(tostring(self.unit), shown, self.errors)
end

-- sizes the game refused while auras were hidden: once it allows them again
local function RetryResize()
    for _, r in ipairs(rows) do
        if r.pendingResize and r.c then pcall(r.Resize, r) end
    end
end
ns.On("PLAYER_REGEN_ENABLED", RetryResize)
ns.On("ZONE_CHANGED_NEW_AREA", RetryResize)

---------------------------------------------------------------------------
-- Diagnostics for the debug report and the recorder
---------------------------------------------------------------------------
local PROBE_FILTERS = { "HARMFUL", "HARMFUL|PLAYER", "HELPFUL", "HELPFUL|PLAYER" }
function A.ProbeUnit(unit)
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "no C_UnitAuras" end
    for _, filter in ipairs(PROBE_FILTERS) do
        local names, err = {}, nil
        for i = 1, 8 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then err = tostring(a) break end
            if type(a) ~= "table" then break end
            local nm = a.name
            names[#names + 1] = ns.IsSecret(nm) and "SECRET" or tostring(nm)
        end
        out[#out + 1] = filter .. "=" .. (err and ("ERR " .. err) or ("[" .. table.concat(names, ", ") .. "]"))
    end
    return table.concat(out, "  ")
end

function A.Report()
    local lines = { ("containers: %s, auras hidden now: %s"):format(tostring(Engine()), tostring(A.Restricted())) }
    for _, r in ipairs(rows) do
        if r.cfg and r.cfg.enabled and r.unit and not r.preview then
            lines[#lines + 1] = "  " .. r.label .. ": " .. r:Info()
        end
    end
    return lines
end
