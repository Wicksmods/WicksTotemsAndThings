-- Wick's Totems and Things
-- CooldownTracker.lua: icon row showing common shaman cooldowns and procs.
--   * Auto-hides any spell the player doesn't know (talent-gated, faction-
--     gated). Saves screen space — non-Resto shamans never see Mana Tide.
--   * Cooldowns: greyed out + Blizzard cooldown spiral while recharging.
--   * Procs: stack count text, time-remaining when applicable.
--   * Click an icon to cast (secure button) where the spell can be cast.
--
-- Tracked list lives in COOLDOWNS / PROCS — extend there to add more.

local ADDON, ns = ...
local WT = WicksTotems

WT.CooldownTracker = {}
local CT = WT.CooldownTracker

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local ICON_SIZE = 32
local ICON_GAP  = 3
local PADDING   = 5

-- Perf caches (set on Init / refreshed on entries change). The CLEU handler
-- runs hundreds of times per second in raid combat; pre-computing these
-- avoids per-event UnitGUID() calls and a linear walk over self.entries.
local playerGUID = nil
local flashByName = {}    -- [spellName] = entry, only for kind=="flash" entries

local function rebuildFlashLookup(entries)
    wipe(flashByName)
    if not entries then return end
    for _, e in ipairs(entries) do
        if e.kind == "flash" and e.spellName then
            flashByName[e.spellName] = e
        end
    end
end

-- ============================================================
-- Tracked spells
-- ============================================================
-- `spell` = the cast name (used by /cast and GetSpellCooldown).
-- `aura`  = the buff/debuff name (used for proc detection).
-- `kind`  = "cd" (cooldown only), "proc" (aura only), "both" (cd + proc).
-- `unit`  = "player" / "target" — where the aura lives. Defaults to "player".
-- `harmful` = true if checked via UnitDebuff (e.g. Stormstrike on target).

-- icon = explicit fallback texture path. Used when GetSpellTexture fails
-- (passive talents like Maelstrom Weapon aren't always resolvable by name).
-- Exposed via WT.TRACKED so ProcAlerts can iterate the same source-of-truth
-- without duplicating the table.
local TRACKED
TRACKED = {
    -- Long cooldowns
    { spell = "Reincarnation",         kind = "cd",   short = "Ankh", icon = "Interface\\Icons\\Spell_Shaman_Reincarnation" },
    { spell = "Bloodlust",             kind = "both", aura = "Bloodlust",            short = "Lust", icon = "Interface\\Icons\\Spell_Nature_Bloodlust" },
    { spell = "Heroism",               kind = "both", aura = "Heroism",              short = "Hero", icon = "Interface\\Icons\\Ability_Shaman_Heroism" },

    -- Sated/Exhaustion debuff: 10-min lockout after Lust/Hero. Cast either
    -- Bloodlust or Heroism leaves a "Sated" or "Exhaustion" debuff. Track
    -- both names — the icon lights up when either is on the player.
    { aura = "Sated", auraAlt = "Exhaustion", kind = "proc", short = "Sated",
      displayName = "Sated / Exhaustion (Lust used)",
      icon = "Interface\\Icons\\Spell_Nature_Bloodlust" },

    -- Shock cooldown — Earth/Frost/Flame Shock all share one timer (6s base).
    -- Earth Shock is baseline at level 4 so it's the most-known proxy.
    { spell = "Earth Shock", kind = "cd", short = "Shock", displayName = "Shock CD",
      icon = "Interface\\Icons\\Spell_Nature_EarthShock" },

    -- Shield buffs — track stack count. Lightning Shield is a baseline
    -- offensive shield used by Enhance/Elemental; Water Shield is the
    -- mana-restore shield used by Resto. Both are Player buffs.
    { aura = "Lightning Shield", kind = "proc", short = "LSh",
      flashWhenMissing = true,
      displayName = "Lightning Shield charges",
      icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
    { aura = "Water Shield",     kind = "proc", short = "WSh",
      spec = "restoration", flashWhenMissing = true,
      displayName = "Water Shield charges",
      icon = "Interface\\Icons\\Ability_Shaman_WaterShield" },

    { spell = "Fire Elemental Totem",  kind = "cd",   short = "FE",   icon = "Interface\\Icons\\Spell_Fire_Elemental_Totem" },
    { spell = "Earth Elemental Totem", kind = "cd",   short = "EE",   icon = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem" },

    -- Talent CDs
    { spell = "Nature's Swiftness",    kind = "both", aura = "Nature's Swiftness",   short = "NS",   icon = "Interface\\Icons\\Spell_Nature_RavenForm" },
    { spell = "Elemental Mastery",     kind = "both", aura = "Elemental Mastery",    short = "EM",   icon = "Interface\\Icons\\Spell_Nature_WispHeal" },
    { spell = "Mana Tide Totem",       kind = "cd",   short = "MT",   icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },
    { spell = "Tidal Force",           kind = "both", aura = "Tidal Force",          short = "TF",   icon = "Interface\\Icons\\Spell_Nature_TidalForce" },
    { spell = "Shamanistic Rage",      kind = "both", aura = "Shamanistic Rage",     short = "SR",   icon = "Interface\\Icons\\Spell_Nature_ShamanRage" },

    -- Talent-gated proc trackers. `talent` field = exact talent name; the
    -- entry only shows when the player has at least 1 point in it.

    -- Flurry (Enhancement, 5-pt)
    { aura = "Flurry",                 kind = "proc",  short = "Flurry",
      talent = "Flurry",
      icon = "Interface\\Icons\\Ability_Ghoulfrenzy" },

    -- Earth Shield charges on target (Restoration, 41-pt talent in TBC)
    { aura = "Earth Shield",           kind = "proc",  short = "ES", unit = "target", harmful = false,
      talent = "Earth Shield", flashWhenMissing = true,
      displayName = "Earth Shield (target)",
      icon = "Interface\\Icons\\Spell_Nature_SkinofEarth" },

    -- Mana Tide Totem buff window (Restoration, 41-pt)
    { aura = "Mana Tide Totem",        kind = "proc",  short = "MTBuff",
      talent = "Mana Tide Totem", displayName = "Mana Tide buff",
      icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },

    -- Clearcasting from Elemental Focus (Elemental, 5-pt)
    { aura = "Clearcasting",           kind = "proc",  short = "EF",
      talent = "Elemental Focus", displayName = "Elemental Focus (Clearcasting)",
      icon = "Interface\\Icons\\Spell_Shadow_ManaBurn" },

    -- Elemental Devastation (Elemental, 3-pt)
    { aura = "Elemental Devastation",  kind = "proc",  short = "ED",
      talent = "Elemental Devastation", displayName = "Elemental Devastation",
      icon = "Interface\\Icons\\Spell_Fire_SoulBurn" },

    -- Eye of the Storm (Elemental, 3-pt)
    { aura = "Eye of the Storm",       kind = "proc",  short = "EotS",
      talent = "Eye of the Storm", displayName = "Eye of the Storm",
      icon = "Interface\\Icons\\Spell_Nature_EyeOfTheStorm" },

    -- Lightning Overload combat-log flash (Elemental, 5-pt)
    { kind = "flash", short = "LO", spellName = "Lightning Overload", flashDuration = 1.2,
      talent = "Lightning Overload", displayName = "Lightning Overload",
      icon = "Interface\\Icons\\Spell_Lightning_LightningBolt01" },

    -- Windfury Weapon proc — any melee shaman uses the imbue (no talent gate)
    { kind = "flash", short = "WF", displayName = "Windfury Weapon",
      spellName = "Windfury Attack", flashDuration = 1.5,
      icon = "Interface\\Icons\\Spell_Nature_Cyclone" },

    -- Stormstrike target debuff (Enhancement, 21-pt)
    { aura = "Stormstrike",            kind = "proc", short = "SS", unit = "target", harmful = true,
      talent = "Stormstrike",
      icon = "Interface\\Icons\\Spell_Shaman_Stormstrike" },

    -- Note: Maelstrom Weapon was added in WotLK 3.0 — not present in TBC 2.5.5.
}

-- ============================================================
-- Brand chrome helpers
-- ============================================================
local function NewTexture(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function AddBorder(frame, c)
    c = c or C_BORDER
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT",    "TOPRIGHT",    nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
    edge("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
end

local function AddCornerAccents(frame, arm, thick)
    arm = arm or 6
    thick = thick or 2
    local g = C_GREEN
    local function brk(anchor)
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(g[1], g[2], g[3], 1)
        h:SetPoint(anchor); h:SetSize(arm, thick)
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(g[1], g[2], g[3], 1)
        v:SetPoint(anchor); v:SetSize(thick, arm)
    end
    brk("TOPLEFT"); brk("TOPRIGHT"); brk("BOTTOMLEFT"); brk("BOTTOMRIGHT")
end

-- ============================================================
-- Aura scan (returns name, count, expirationTime, duration if found)
-- TBC UnitBuff/UnitDebuff returns:
--   name, rank, icon, count, debuffType, duration, expirationTime, ...
-- ============================================================
local function findAura(unit, name, harmful)
    if not unit or unit == "" then return nil end
    if unit ~= "player" and not UnitExists(unit) then return nil end
    local fn = harmful and UnitDebuff or UnitBuff
    for i = 1, 40 do
        local n, _, _, count, _, duration, expirationTime = fn(unit, i)
        if not n then return nil end
        if n == name then
            return n, count or 0, expirationTime or 0, duration or 0
        end
    end
    return nil
end

-- ============================================================
-- Spell + spec detection — only show entries relevant to the player
-- ============================================================
local function spellKnown(name)
    if not name or name == "" then return false end
    if GetSpellInfo and GetSpellInfo(name) then
        local start, dur, enabled = GetSpellCooldown(name)
        if start ~= nil then return true end
    end
    return false
end

-- Returns the player's current rank in a talent by name, or 0 if not
-- specced / not found / talents not yet loaded. Used to filter TRACKED
-- entries with a `talent` field per-talent rather than per-spec.
local function talentRank(name)
    if not GetNumTalentTabs or not GetTalentInfo then return 0 end
    local ok, rank = pcall(function()
        for tab = 1, (GetNumTalentTabs() or 0) do
            local count = (GetNumTalents and GetNumTalents(tab)) or 0
            for i = 1, count do
                local tname, _, _, _, currentRank = GetTalentInfo(tab, i)
                if tname == name then return currentRank or 0 end
            end
        end
        return 0
    end)
    if ok then return rank or 0 end
    return 0
end

-- Expose the tracked list + helpers for the ProcAlerts module.
WT.TRACKED            = TRACKED
WT.TrackerFindAura    = findAura
WT.TrackerSpellKnown  = spellKnown
WT.TalentRank         = talentRank

-- Returns "elemental" / "enhancement" / "restoration" / nil based on the
-- highest-point talent tab. Shaman tabs in TBC: 1 Elemental, 2 Enhancement,
-- 3 Restoration. Defaults to nil for non-shamans or unloaded talent data.
-- Wrapped in pcall because GetTalentTabInfo can throw on some clients
-- before PLAYER_ENTERING_WORLD has fired.
local SHAMAN_SPEC_BY_TAB = { "elemental", "enhancement", "restoration" }
local function getActiveSpec()
    if not WT.isShaman then return nil end
    if not GetNumTalentTabs or not GetTalentTabInfo then return nil end
    local ok, result = pcall(function()
        local maxIdx, maxPts = 0, -1
        local n = GetNumTalentTabs() or 0
        for i = 1, n do
            local _, _, points = GetTalentTabInfo(i)
            if (points or 0) > maxPts then
                maxPts = points or 0
                maxIdx = i
            end
        end
        if maxPts <= 0 then return nil end
        return SHAMAN_SPEC_BY_TAB[maxIdx]
    end)
    if ok then return result end
    return nil
end
WT.GetActiveSpec = getActiveSpec

-- ============================================================
-- Bar construction
-- ============================================================
local function buildHost(visibleEntries)
    local cfg = WicksTotemsDB.cd or {}
    WicksTotemsDB.cd = cfg
    cfg.point = cfg.point or "CENTER"
    cfg.x = cfg.x or 0
    cfg.y = cfg.y or 156   -- just under the totem strip
    if cfg.hidden == nil then cfg.hidden = false end

    local count = #visibleEntries
    local barW = PADDING * 2 + math.max(1, count) * ICON_SIZE + math.max(0, count - 1) * ICON_GAP
    local barH = PADDING * 2 + ICON_SIZE

    local host = CreateFrame("Frame", "WicksTotemsCDBar", UIParent)
    host:SetFrameStrata("MEDIUM")
    host:SetFrameLevel(10)
    host:SetSize(barW, barH)
    host:ClearAllPoints()
    host:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:SetClampedToScreen(true)
    host:RegisterForDrag("LeftButton")
    host:SetScript("OnDragStart", function(self)
        if cfg.locked then return end
        self:StartMoving()
    end)
    host:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        cfg.point, cfg.x, cfg.y = p, x, y
    end)

    NewTexture(host, "BACKGROUND", C_BG):SetAllPoints(host)
    AddBorder(host)
    AddCornerAccents(host)

    host:SetScale(cfg.scale or 1.0)
    return host, cfg
end

function CT:SetScale(s)
    if not self.host then return end
    s = math.max(0.5, math.min(2.5, tonumber(s) or 1.0))
    WicksTotemsDB.cd = WicksTotemsDB.cd or {}
    WicksTotemsDB.cd.scale = s
    self.host:SetScale(s)
end

local function buildIcon(host, entry, index)
    local b = CreateFrame("Button", nil, host, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:SetPoint("TOPLEFT", host, "TOPLEFT",
        PADDING + (index - 1) * (ICON_SIZE + ICON_GAP), -PADDING)

    -- Cast on click (only meaningful for cooldown entries with a spell name)
    if entry.spell then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", entry.spell)
    end

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Resolve icon: prefer spell texture, fall back to aura texture, then
    -- to an explicit curated path. Passive talents (e.g. Maelstrom Weapon)
    -- are not always in the spellbook lookup, so GetSpellTexture can fail.
    local tex
    if entry.spell then tex = GetSpellTexture and GetSpellTexture(entry.spell) end
    if not tex and entry.aura then tex = GetSpellTexture and GetSpellTexture(entry.aura) end
    if not tex and entry.icon then tex = entry.icon end
    if tex then icon:SetTexture(tex) else icon:SetColorTexture(0.1, 0.1, 0.15, 1) end
    b._icon = icon

    -- 1px frame
    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.85)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    -- Cooldown spiral
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    b._cd = cd

    -- Active glow (proc up / spell ready highlight)
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.45)
    glow:SetAllPoints(b)
    glow:Hide()
    b._glow = glow

    -- Autocast shine (the swirling sparkles like pet bar autocast highlights).
    -- Only applied to proc-kind entries — Stormstrike, Maelstrom Weapon, etc.
    -- Wrapped in pcall in case the template isn't available on this client.
    if entry.kind == "proc" then
        local ok, shine = pcall(CreateFrame, "Frame", nil, b, "AutoCastShineTemplate")
        if ok and shine then
            shine:SetAllPoints(b)
            shine:Hide()
            b._shine = shine
        end
    end

    -- Stack count
    local stack = b:CreateFontString(nil, "OVERLAY")
    stack:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    stack:SetPoint("BOTTOMRIGHT", -2, 1)
    stack:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    stack:SetText("")
    b._stack = stack

    -- Tooltip
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        local title = entry.displayName or entry.spell or entry.aura
                   or entry.spellName or entry.short or "?"
        GameTooltip:AddLine(title, C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        local sub
        if entry.kind == "flash" then
            sub = "Weapon proc tracker"
        elseif entry.kind == "proc" then
            sub = "Proc tracker"
        else
            sub = "Cooldown tracker"
        end
        GameTooltip:AddLine(sub, C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- ============================================================
-- State refresh
-- ============================================================

function CT:Refresh()
    if not self.icons then return end
    -- Skip the full per-entry aura+CD scan when the bar isn't on screen.
    -- Cuts ~400 UnitBuff calls/sec when the user has the bar toggled off.
    if not self.host or not self.host:IsShown() then return end
    for _, e in ipairs(self.entries) do
        local b = self.icons[e]
        if not b then -- skip
        else
            local now = GetTime()

            -- Aura check (if entry tracks one)
            local auraName, count, expirationTime, duration
            if e.aura then
                auraName, count, expirationTime, duration = findAura(e.unit or "player", e.aura, e.harmful)
                -- auraAlt: try alternate name if primary missed (e.g. Sated/Exhaustion)
                if not auraName and e.auraAlt then
                    auraName, count, expirationTime, duration = findAura(e.unit or "player", e.auraAlt, e.harmful)
                end
            end

            -- Cooldown check
            local onCD, cdRemaining = false, 0
            if e.spell then
                local start, dur, enabled = GetSpellCooldown(e.spell)
                if start and start > 0 and dur and dur > 1.5 then
                    -- Filter out GCD (1.5s); we want actual cooldowns
                    onCD = true
                    cdRemaining = (start + dur) - now
                end
            end

            local function setShine(on)
                if not b._shine then return end
                if on then
                    if not b._shineActive then
                        b._shine:Show()
                        if AutoCastShine_AutoCastStart then
                            pcall(AutoCastShine_AutoCastStart, b._shine)
                        end
                        b._shineActive = true
                    end
                else
                    -- Always force-hide on the off path, even if shineActive
                    -- was somehow already false (defensive against stuck
                    -- sparkles when the helper doesn't fully clean up).
                    if AutoCastShine_AutoCastStop then
                        pcall(AutoCastShine_AutoCastStop, b._shine)
                    end
                    b._shine:Hide()
                    b._shineActive = false
                end
            end

            -- Flash state: combat-log triggered (e.g. Windfury Weapon proc)
            local flashing = false
            if e.kind == "flash" and b._flashUntil and now < b._flashUntil then
                flashing = true
            end

            if auraName or flashing then
                -- Active: glow + stack/duration. Full color + desaturate off
                -- so the proc icon "lights up".
                b._glow:Show()
                setShine(e.kind == "proc" or e.kind == "flash")
                if auraName and count and count > 1 then
                    b._stack:SetText(tostring(count))
                elseif auraName and expirationTime and expirationTime > 0 then
                    local r = expirationTime - now
                    if r > 60 then b._stack:SetText(("%dm"):format(math.floor(r / 60)))
                    elseif r > 0 then b._stack:SetText(("%d"):format(math.ceil(r)))
                    else b._stack:SetText("") end
                else
                    b._stack:SetText("")  -- flash entries have no stack/timer
                end
                b._cd:Hide()
                if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                b._icon:SetVertexColor(1, 1, 1)
            elseif onCD then
                -- On cooldown: spiral + greyed out
                b._glow:Hide()
                setShine(false)
                b._stack:SetText("")
                b._cd:SetCooldown(GetSpellCooldown(e.spell))
                b._cd:Show()
                if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                b._icon:SetVertexColor(0.45, 0.45, 0.45)
            else
                -- Ready / idle. Proc + flash entries fade (desaturated + dim)
                -- like an unusable action button. Cooldown-only entries stay
                -- bright when ready so the player knows they're available.
                b._glow:Hide()
                setShine(false)
                b._stack:SetText("")
                b._cd:Hide()
                if e.kind == "proc" or e.kind == "flash" then
                    if b._icon.SetDesaturated then b._icon:SetDesaturated(true) end
                    b._icon:SetVertexColor(0.55, 0.55, 0.55)
                else
                    if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                    b._icon:SetVertexColor(1, 1, 1)
                end
            end
        end
    end
end

-- ============================================================
-- Init
-- ============================================================

-- Force re-init (clears initialized flag + tears down state). Used by
-- /wtt cdrebuild to recover from a half-built bar without /reload.
function CT:ForceReinit()
    if InCombatLockdown() then
        print("|cff4FC778Wick's Totems|r: can't rebuild CD bar in combat.")
        return
    end
    if self.icons then
        for _, b in pairs(self.icons) do
            b:Hide(); b:ClearAllPoints(); b:SetParent(nil)
        end
    end
    self.icons = nil
    self.entries = nil
    if self.host then
        self.host:Hide(); self.host:ClearAllPoints(); self.host:SetParent(nil)
    end
    self.host = nil
    self.cfg = nil
    self.activeSpec = nil
    self.initialized = false
    self:Init()
end

function CT:Init()
    if self.initialized then return end
    if not WT.isShaman then return end   -- shaman-only
    self.initialized = true
    print("|cff4FC778Wick's Totems|r CD bar init starting...")

    self.activeSpec = getActiveSpec()
    -- v0.3: CD bar now ONLY shows kind=cd and kind=both entries.
    -- Procs and flashes are rendered as individual draggable floaters
    -- by the ProcAlerts module (see ProcAlerts.lua).
    local visible = {}
    for _, e in ipairs(TRACKED) do
        local target = e.spell or e.aura
        -- Filter precedence: talent > spec > always-allowed
        local allowed
        if e.talent then
            allowed = talentRank(e.talent) > 0
        elseif e.spec then
            allowed = (e.spec == self.activeSpec)
        else
            allowed = true
        end
        if not allowed then
            -- skip — wrong spec or talent not specced
        elseif e.kind == "proc" or e.kind == "flash" then
            -- skip — handled by ProcAlerts as a floater
        elseif spellKnown(target) then
            table.insert(visible, e)
        end
    end

    -- Build the host even if the initial filter is empty (e.g. talents not
    -- yet loaded). PLAYER_TALENT_UPDATE will populate via RebuildForSpec
    -- once the data is ready.
    self.entries = visible
    rebuildFlashLookup(visible)
    playerGUID = UnitGUID("player")

    local host, cfg = buildHost(visible)
    self.host = host
    self.cfg = cfg

    self.icons = {}
    for i, e in ipairs(visible) do
        self.icons[e] = buildIcon(host, e, i)
    end

    if cfg.hidden then host:Hide() else host:Show() end

    -- Polling for proc duration tick + CD spiral updates
    if not self.poll then
        local f = CreateFrame("Frame")
        self.poll = f
        local accum = 0
        f:SetScript("OnUpdate", function(_, elapsed)
            accum = accum + elapsed
            if accum < 0.25 then return end
            accum = 0
            CT:Refresh()
        end)
    end

    -- Event-driven refresh (cheap path)
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ef:RegisterEvent("PLAYER_TARGET_CHANGED")  -- target debuffs (Stormstrike etc.)
    ef:RegisterUnitEvent("UNIT_AURA", "player")
    ef:RegisterUnitEvent("UNIT_AURA", "target")
    ef:SetScript("OnEvent", function() CT:Refresh() end)

    -- Combat log: flash entries (Windfury Weapon proc, etc.).
    -- Hot path — fires hundreds of times per second in raids. Early-out
    -- when there are no flash entries (most non-Enhance specs), then use
    -- the cached playerGUID + flashByName lookup to avoid per-event
    -- UnitGUID() calls and the linear walk over self.entries.
    local cl = CreateFrame("Frame")
    cl:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    cl:SetScript("OnEvent", function()
        if not next(flashByName) then return end
        local _, _, _, srcGUID, _, _, _, _, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()
        if srcGUID ~= (playerGUID or UnitGUID("player")) then return end
        local e = spellName and flashByName[spellName]
        if not e then return end
        local b = self.icons[e]
        if b then
            b._flashUntil = GetTime() + (e.flashDuration or 1.5)
        end
    end)

    -- Talent change → respec → re-filter visible entries by new spec.
    -- PLAYER_TALENT_UPDATE fires after the talent UI confirms a respec.
    local tf = CreateFrame("Frame")
    tf:RegisterEvent("PLAYER_TALENT_UPDATE")
    tf:RegisterEvent("CHARACTER_POINTS_CHANGED")
    tf:SetScript("OnEvent", function() CT:RebuildForSpec() end)

    print(("|cff4FC778Wick's Totems|r CD bar init done: %d entries, spec=%s"):format(
        #visible, tostring(self.activeSpec or "(unknown)")))
    self:Refresh()
end

-- Tear down icons + re-filter by current spec, then re-create. Called when
-- the player respecs (PLAYER_TALENT_UPDATE) or any time spec composition
-- might have changed. Keeps the same host frame, only the icons rebuild.
--
-- Defenses (added v0.2.2 after the bar disappeared bug):
--   * Skip if newSpec is nil — talent data isn't ready yet, don't clobber.
--   * Skip if in combat — SecureActionButtonTemplate SetParent is blocked.
--     Queue for PLAYER_REGEN_ENABLED instead.
--   * Always re-show the host after rebuild unless cfg.hidden was set.
function CT:RebuildForSpec()
    if not self.host then return end
    if InCombatLockdown() then
        self._rebuildPending = true
        return
    end

    local newSpec = getActiveSpec()
    if not newSpec then return end                  -- talents not ready
    if newSpec == self.activeSpec then return end   -- no-op if unchanged
    self.activeSpec = newSpec

    -- Destroy current icon buttons (out of combat only)
    if self.icons then
        for _, b in pairs(self.icons) do
            b:Hide()
            b:ClearAllPoints()
            b:SetParent(nil)
        end
    end
    self.icons = {}

    -- Re-filter entries (talent first, then spec, then always-allowed).
    -- Proc/flash kinds are excluded — they live in ProcAlerts as floaters.
    local visible = {}
    for _, e in ipairs(TRACKED) do
        local target = e.spell or e.aura
        local allowed
        if e.talent then
            allowed = talentRank(e.talent) > 0
        elseif e.spec then
            allowed = (e.spec == self.activeSpec)
        else
            allowed = true
        end
        if not allowed then
            -- skip
        elseif e.kind == "proc" or e.kind == "flash" then
            -- skip — handled by ProcAlerts
        elseif spellKnown(target) then
            table.insert(visible, e)
        end
    end
    self.entries = visible
    rebuildFlashLookup(visible)

    -- Resize host bar to fit new icon count
    local count = #visible
    local barW = PADDING * 2 + math.max(1, count) * ICON_SIZE + math.max(0, count - 1) * ICON_GAP
    self.host:SetWidth(barW)

    -- Recreate icons
    for i, e in ipairs(visible) do
        self.icons[e] = buildIcon(self.host, e, i)
    end

    -- Force-show after rebuild unless explicitly hidden via Options
    if not (self.cfg and self.cfg.hidden) then
        self.host:Show()
    end

    self:Refresh()
end

-- Out-of-combat hook: flush any queued rebuild
WT:On("COMBAT_END", function()
    if WT.CooldownTracker and WT.CooldownTracker._rebuildPending then
        WT.CooldownTracker._rebuildPending = false
        WT.CooldownTracker:RebuildForSpec()
    end
end)

function CT:Diagnose()
    print("|cff4FC778Wick's Totems CD diagnostic:|r")
    print(("  active spec: %s   shaman: %s"):format(
        tostring(self.activeSpec or "(unknown)"),
        tostring(WT.isShaman and true or false)))
    print(("  bar host: %s   shown: %s   hidden cfg: %s"):format(
        self.host and "exists" or "nil",
        self.host and tostring(self.host:IsShown()) or "n/a",
        tostring(self.cfg and self.cfg.hidden or false)))
    print(("  target: %s   exists: %s"):format(
        UnitName("target") or "(none)",
        tostring(UnitExists("target") and true or false)))
    if not self.entries then
        print("  no entries built")
        return
    end
    for _, e in ipairs(self.entries) do
        local b = self.icons[e]
        local glow = b and b._glow and b._glow:IsShown() and "ON" or "off"
        local shine = b and b._shineActive and "ON" or "off"
        local auraName, count
        if e.aura then
            auraName, count = findAura(e.unit or "player", e.aura, e.harmful)
        end
        print(("  [%s] kind=%s aura=%s unit=%s   glow:%s  shine:%s  auraFound:%s"):format(
            e.short or "?", tostring(e.kind), tostring(e.aura),
            tostring(e.unit or "player"), glow, shine,
            tostring(auraName) or "nil"))
    end
end

function CT:Show()
    if not self.host then return end
    self.host:Show()
    self.cfg.hidden = false
    self:Refresh()  -- give immediate state instead of up-to-0.25s blank
end
function CT:Hide()
    if not self.host then return end
    self.host:Hide()
    self.cfg.hidden = true
end
function CT:Toggle()
    if not self.host then return end
    if self.host:IsShown() then self:Hide() else self:Show() end
end
function CT:ResetPosition()
    if not self.cfg or not self.host then return end
    self.cfg.point = "CENTER"
    self.cfg.x = 0; self.cfg.y = 156
    self.host:ClearAllPoints()
    self.host:SetPoint("CENTER", UIParent, "CENTER", 0, 156)
    self.host:Show()
    self.cfg.hidden = false
end

WT:On("LOGIN", function() CT:Init() end)
