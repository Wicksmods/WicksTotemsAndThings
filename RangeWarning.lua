-- Wick's Totems and Things
-- RangeWarning.lua: persistent visual + audio cue when the shaman has
-- stepped out of range of any of their own active aura totems.
--
-- Detection: for buff-aura totems, the player has the named aura while
-- in range. If the totem is still active per GetTotemInfo but the aura
-- is missing, the player is out of range. Tick-effect totems (Mana
-- Spring, Healing Stream, Mana Tide) don't apply a sustained aura, so
-- they're omitted from range checking (range = nil in Totems.lua).
--
-- UX:
--   * Big red banner across the top of the screen while OOR ("OUT OF
--     RANGE: <totem name>")
--   * Screen-edge red vignette (subtle, eight overlapping textures)
--   * Sound on transition into OOR (RAID_WARNING)
--   * State-tracked: cue only fires on enter-OOR, banner sustains while
--     OOR, both clear instantly when back in range.

local ADDON, ns = ...
local WT = WicksTotems

WT.RangeWarning = {}
local RW = WT.RangeWarning

local C_RED  = { 0.95, 0.32, 0.32 }
local C_TEXT = { 0.95, 0.32, 0.32 }

local DROP_GRACE    = 4    -- seconds after cast before warnings fire (pulse + aura latency)
local POLL_INTERVAL = 0.5
local REPING_INTERVAL = 15 -- re-flash every N seconds while OOR (visual only, no sound)

-- Defaults synced from WicksTotemsDB.range on Init.
RW.enabled        = true
RW._oorState      = {}     -- slot → true while currently OOR
RW._lastDropAt    = {}     -- slot → cast time
RW._previousActive = {}    -- slot → name (detect fresh drops)
RW._lastSoundAt   = {}     -- slot → t (re-ping throttle)
RW._poll          = nil

local function cfg()
    WicksTotemsDB.range = WicksTotemsDB.range or { enabled = true, sound = true, banner = true, vignette = true }
    return WicksTotemsDB.range
end

-- ============================================================
-- Aura check
-- ============================================================
-- Same trick as the totem-name lookup: UnitBuff in TBC returns names
-- with rank suffixes ("Strength of Earth IV"), and our table is keyed
-- without ranks. Strip both sides before comparing.
local function stripRank(name)
    if not name then return name end
    return (name:gsub("%s+[IVX]+$", ""))
end

local function playerHasBuff(buffName)
    if not buffName or buffName == "" then return false end
    local target = stripRank(buffName)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if stripRank(n) == target then return true end
        -- Some totem buffs are stored under the totem's full name
        -- (e.g. "Windfury Totem"), others under the short name
        -- (e.g. "Strength of Earth"). Try a prefix match as a fallback.
        if n:sub(1, #target) == target then return true end
    end
    return false
end

-- ============================================================
-- Visual: top-screen banner (auto-fade, briefly re-shows on reminder ping)
-- ============================================================
local function ensureBanner()
    if RW._banner then return RW._banner end

    local f = CreateFrame("Frame", "WicksTotemsRangeBanner", UIParent)
    f:SetSize(620, 44)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.16, 0.04, 0.04, 0.92)
    bg:SetAllPoints(f)

    local function edge(p1, p2, w, h, alpha)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C_RED[1], C_RED[2], C_RED[3], alpha or 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 2)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    text:SetPoint("CENTER")
    text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
    f._text = text

    -- Auto-fade: visible 1.6s at full alpha, fade out 0.5s, then hide.
    local fade = f:CreateAnimationGroup()
    local hold = fade:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.6); hold:SetOrder(1)
    local out = fade:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.5); out:SetOrder(2)
    fade:SetScript("OnFinished", function() f:Hide(); f:SetAlpha(1) end)
    f._fade = fade

    RW._banner = f
    return f
end

-- ============================================================
-- Visual: screen-edge red vignette (8 textures, soft)
-- ============================================================
local function ensureVignette()
    if RW._vignette then return RW._vignette end

    local f = CreateFrame("Frame", "WicksTotemsRangeVignette", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:Hide()

    -- Subtle red bands at the screen edges (toned down: alpha 0.12, 60px)
    local edges = {}
    local function band(p1, p2, w, h, alpha)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C_RED[1], C_RED[2], C_RED[3], alpha or 0.12)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(edges, t)
        return t
    end
    band("TOPLEFT",    "TOPRIGHT",    nil, 60, 0.12)
    band("BOTTOMLEFT", "BOTTOMRIGHT", nil, 60, 0.12)
    band("TOPLEFT",    "BOTTOMLEFT",  60,  nil, 0.12)
    band("TOPRIGHT",   "BOTTOMRIGHT", 60,  nil, 0.12)
    f._edges = edges

    -- Auto-fade vignette in sync with banner
    local fade = f:CreateAnimationGroup()
    local hold = fade:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.6); hold:SetOrder(1)
    local out = fade:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.5); out:SetOrder(2)
    fade:SetScript("OnFinished", function() f:Hide(); f:SetAlpha(1) end)
    f._fade = fade

    RW._vignette = f
    return f
end

-- ============================================================
-- State transitions
-- ============================================================

-- Show banner+vignette briefly. Called on enter-OOR transition and on
-- the reminder-ping interval. The fade animation auto-hides them.
local function flashWarning(message)
    local c = cfg()
    if c.banner then
        local banner = ensureBanner()
        banner._text:SetText(message)
        banner._fade:Stop()
        banner:SetAlpha(1)
        banner:Show()
        banner._fade:Play()
    end
    if c.vignette then
        local vignette = ensureVignette()
        vignette._fade:Stop()
        vignette:SetAlpha(1)
        vignette:Show()
        vignette._fade:Play()
    end
end

-- When we re-enter range, kill the warning immediately even if mid-fade.
local function dismissWarning()
    local banner = RW._banner
    local vignette = RW._vignette
    if banner then banner._fade:Stop(); banner:Hide(); banner:SetAlpha(1) end
    if vignette then vignette._fade:Stop(); vignette:Hide(); vignette:SetAlpha(1) end
end

-- ============================================================
-- Core check loop
-- ============================================================

function RW:Check()
    if not cfg().enabled then
        dismissWarning()
        return
    end
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    local now = GetTime()

    local enteringOOR = {}    -- slots that just transitioned OOR (fresh warning)
    local repingOOR   = {}    -- slots still OOR past the reminder interval
    local anyInRange  = false

    for slot = 1, 4 do
        local info = active[slot]
        -- Cross-check with GetTotemInfo: AC.active may be stale during the
        -- 1-frame window between UNIT_AURA (buff drops) and PLAYER_TOTEM_UPDATE
        -- (totem actually removed). Without this, Totemic Call triggers a
        -- false-positive OOR flash because the buff drops first.
        local stillUp = false
        if info and GetTotemInfo then
            stillUp = (select(1, GetTotemInfo(slot))) and true or false
        end
        if info and stillUp then
            if RW._previousActive[slot] ~= info.name then
                RW._lastDropAt[slot] = now
                RW._previousActive[slot] = info.name
                RW._oorState[slot] = false
            end

            local meta = WT:GetTotemMeta(info.name)
            local buff = meta and meta.buff
            if buff then
                local since = now - (RW._lastDropAt[slot] or 0)
                if since > DROP_GRACE then
                    local inRange = playerHasBuff(buff)
                    local wasOOR = RW._oorState[slot]
                    if not inRange then
                        if not wasOOR then
                            RW._oorState[slot] = true
                            RW._lastSoundAt[slot] = now
                            table.insert(enteringOOR, info)
                        else
                            local lastSnd = RW._lastSoundAt[slot] or 0
                            if now - lastSnd >= REPING_INTERVAL then
                                RW._lastSoundAt[slot] = now
                                table.insert(repingOOR, info)
                            end
                        end
                    else
                        if wasOOR then anyInRange = true end
                        RW._oorState[slot] = false
                    end
                end
            end
        else
            RW._previousActive[slot] = nil
            RW._oorState[slot] = false
        end
    end

    -- Just stepped back in range: kill any in-flight warning instantly.
    if anyInRange then dismissWarning() end

    -- Fresh OOR transitions: loud sound + banner flash
    if #enteringOOR > 0 then
        local names = {}
        for _, t in ipairs(enteringOOR) do table.insert(names, t.name) end
        flashWarning("OUT OF RANGE: " .. table.concat(names, ", "))
        if cfg().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
    end

    -- Still-OOR reminder: visual only, NO sound (audited 2026-05-06).
    -- A persistent OOR situation gets one sound at the start; further pings
    -- would just be noise.
    if #repingOOR > 0 and #enteringOOR == 0 then
        local names = {}
        for _, t in ipairs(repingOOR) do table.insert(names, t.name) end
        flashWarning("STILL OUT OF RANGE: " .. table.concat(names, ", "))
    end

    -- Push the OOR state to the icon strip so its borders turn red while OOR.
    if WT.TotemBar and WT.TotemBar.RefreshActive then
        WT.TotemBar:RefreshActive()
    end
end

-- ============================================================
-- Polling: only run while at least one buff totem is active
-- ============================================================

local function anyBuffTotemActive()
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    for slot = 1, 4 do
        local info = active[slot]
        if info then
            local meta = WT:GetTotemMeta(info.name)
            if meta and meta.buff then return true end
        end
    end
    return false
end

local function ensurePoller()
    if RW._poll then return end
    if not anyBuffTotemActive() then return end
    local f = CreateFrame("Frame")
    RW._poll = f
    local accum = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < POLL_INTERVAL then return end
        accum = 0
        RW:Check()
        if not anyBuffTotemActive() then
            f:SetScript("OnUpdate", nil)
            RW._poll = nil
            for slot = 1, 4 do RW._oorState[slot] = false end
            dismissWarning()
            if WT.TotemBar and WT.TotemBar.RefreshActive then WT.TotemBar:RefreshActive() end
        end
    end)
end

-- ============================================================
-- Diagnostics
-- ============================================================

function RW:Diagnose()
    print("|cff4FC778Wick's Totems range diagnostic:|r")
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    local any = false
    for slot = 1, 4 do
        local info = active[slot]
        if info then
            any = true
            local meta = WT:GetTotemMeta(info.name)
            local buff = meta and meta.buff or "(none — tick effect or utility)"
            local has = meta and meta.buff and playerHasBuff(meta.buff)
            local oor = RW._oorState[slot] and "YES" or "no"
            print(("  slot %d [%s] %s"):format(slot, info.element, info.name))
            print(("    expected buff: %s"):format(buff))
            if meta and meta.buff then
                print(("    buff on player: %s    out of range: %s"):format(has and "yes" or "NO", oor))
            end
        end
    end
    if not any then print("  no active totems") end
    print(("  range warnings enabled: %s"):format(self.enabled and "yes" or "no"))
    print(("  poller running: %s"):format(self._poll and "yes" or "no"))

    -- Dump all player buffs so we can spot name mismatches
    print("|cff4FC778player buffs:|r")
    local found = false
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then break end
        found = true
        print(("  [%d] %s"):format(i, n))
    end
    if not found then print("  (none)") end
end

-- ============================================================
-- Wiring
-- ============================================================

WT:On("PLAYER_TOTEM_UPDATE", function()
    RW:Check()
    ensurePoller()
end)

WT:On("AFFECTED_UPDATED", function() RW:Check() end)

-- UNIT_AURA fires on every buff/debuff change, very high frequency in raids.
-- Two guards before triggering Check() (which scans 4 totem slots × 40 buff
-- slots): no-op if there's no buff totem to check, then a 0.2s throttle so
-- a burst of aura events still produces at most one Check call.
local UNIT_AURA_THROTTLE = 0.2
local lastAuraCheck = 0

local auraFrame = CreateFrame("Frame")
auraFrame:RegisterUnitEvent("UNIT_AURA", "player")
auraFrame:SetScript("OnEvent", function()
    if not anyBuffTotemActive() then return end
    local now = GetTime()
    if now - lastAuraCheck < UNIT_AURA_THROTTLE then return end
    lastAuraCheck = now
    RW:Check()
end)

function RW:SetEnabled(flag)
    self.enabled = flag and true or false
    if not self.enabled then
        for slot = 1, 4 do self._oorState[slot] = false end
        dismissWarning()
        if WT.TotemBar and WT.TotemBar.RefreshActive then WT.TotemBar:RefreshActive() end
    end
end

WT:On("LOGIN", function() ensurePoller() end)
