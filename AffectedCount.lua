-- Wick's Totems and Things
-- AffectedCount.lua: tracks active totems and counts party/raid members
-- inside their effect radius.
--
-- Range strategy (v0.2):
--   LibRangeCheck-3.0 picks an in-range probe (item/spell/interact-distance)
--   per unit and returns (minRange, maxRange) buckets. We use the upper
--   bound to decide "definitely not in range" — if maxRange < totem range,
--   the unit is out of range. Falls back to UnitInRange (40yd) if the lib
--   isn't loaded for some reason.

local ADDON, ns = ...
local WT = WicksTotems

WT.AffectedCount = {}
local AC = WT.AffectedCount

AC.active = {}    -- [slot] = { name = ..., affected = N, lastScan = t }
AC.poll = nil     -- ticker frame
local POLL_INTERVAL = 0.75    -- bumped from 0.5 to halve raid-CPU cost; UX delta is sub-second

-- Pre-built unit-name pools to avoid per-poll string concatenation.
-- In a 25-man this saves ~30 string allocations per poll cycle.
local RAID_UNIT_NAMES  = {}
local PARTY_UNIT_NAMES = { "party1", "party2", "party3", "party4" }
for i = 1, 40 do RAID_UNIT_NAMES[i] = "raid" .. i end

-- Single buffer reused across calls (returned by unitsInGroup). Caller
-- treats it as read-only between calls; no concurrency in WoW Lua.
local unitsBuffer = {}

-- LibRangeCheck checker (resolved lazily on first scan since LibStub
-- finishes loading at addon-load time, but the lib's spell tables
-- need PLAYER_LOGIN to populate).
local rangeChecker = nil
local function ensureChecker()
    if rangeChecker then return rangeChecker end
    if LibStub then
        local ok, lib = pcall(LibStub, "LibRangeCheck-3.0", true)
        if ok and lib then
            rangeChecker = lib
            return rangeChecker
        end
    end
    return nil
end

-- Returns true if `unit` is within `yards` of the player. Uses
-- LibRangeCheck when available, falls back to UnitInRange (40yd).
local function unitInRangeYards(unit, yards)
    if not UnitExists(unit) then return false end
    if unit == "player" then return true end
    local rc = ensureChecker()
    if rc then
        local minR, maxR = rc:GetRange(unit)
        -- maxR can be nil for out-of-range targets; treat as "too far".
        if not maxR then return false end
        return maxR <= yards
    end
    -- Fallback: UnitInRange is 40yd. For 40yd or above, exact; for shorter
    -- totems it's an over-count (matches v0.1 behavior).
    return UnitInRange(unit) and true or false
end
WT.unitInRangeYards = unitInRangeYards

-- ============================================================
-- Core scan
-- ============================================================

local function unitsInGroup()
    wipe(unitsBuffer)
    if IsInRaid() then
        local n = (GetNumGroupMembers and GetNumGroupMembers())
               or (GetNumRaidMembers and GetNumRaidMembers())
               or 0
        for i = 1, n do unitsBuffer[#unitsBuffer + 1] = RAID_UNIT_NAMES[i] end
    elseif IsInGroup() then
        unitsBuffer[#unitsBuffer + 1] = "player"
        for i = 1, 4 do
            if UnitExists(PARTY_UNIT_NAMES[i]) then
                unitsBuffer[#unitsBuffer + 1] = PARTY_UNIT_NAMES[i]
            end
        end
    else
        unitsBuffer[#unitsBuffer + 1] = "player"
    end
    return unitsBuffer
end

-- Returns affected count for a totem with given range token.
-- range can be a number (yards), or "self" / "enemy" / "raid" / "summon".
function AC:CountFor(rangeToken)
    if rangeToken == "self" or rangeToken == "summon" then return 1 end
    if rangeToken == "enemy" then return 0 end
    -- "raid" = full party/raid (e.g. Mana Tide is 40yd-ish), use 40yd as cap.
    -- Number range = exact yards (10, 20, 30, 40).
    local maxYd = (type(rangeToken) == "number") and rangeToken or 40
    local n = 0
    for _, u in ipairs(unitsInGroup()) do
        if UnitExists(u) and not UnitIsDeadOrGhost(u) then
            if u == "player" then
                n = n + 1
            elseif unitInRangeYards(u, maxYd) then
                n = n + 1
            end
        end
    end
    return n
end

-- ============================================================
-- Active totem tracking + destruction detection
-- ============================================================

-- previousActive[slot] = snapshot of last seen totem state. Used to detect
-- when a totem disappeared before its expected expiration (= destroyed by
-- enemy, vs natural expire or recall).
local previousActive = {}

-- Detect Totemic Call so we don't false-flag a recall as destruction.
-- Set true when the player casts Totemic Call; cleared after a short
-- window during which all 4 totems vanish "expectedly".
local recallExpected = false
local recallFrame = CreateFrame("Frame")
recallFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
recallFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" then return end
    -- Spell name comparison (TBC sends spellID as 3rd arg, name varies)
    local name = spellID and GetSpellInfo and GetSpellInfo(spellID) or nil
    if name == "Totemic Call" or name == "Recall Totems" then
        recallExpected = true
        C_Timer = C_Timer or {}
        if C_Timer.After then
            C_Timer.After(2, function() recallExpected = false end)
        else
            -- Fallback: clear via OnUpdate after 2s
            local t = 0
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function(self, e)
                t = t + e
                if t >= 2 then recallExpected = false; self:SetScript("OnUpdate", nil) end
            end)
        end
    end
end)

local function refreshActive()
    local any = false
    local now = GetTime()
    for slot = 1, 4 do
        local have, name, startTime, duration = GetTotemInfo(slot)
        if have and name and name ~= "" then
            any = true
            local meta = WT:GetTotemMeta(name)
            local range = meta and meta.range or 20
            local affected = AC:CountFor(range)
            local info = {
                name      = name,
                element   = WT.ELEMENT_BY_SLOT[slot],
                startTime = startTime,
                duration  = duration,
                range     = range,
                kind      = meta and meta.kind,
                affected  = affected,
            }
            AC.active[slot] = info
            previousActive[slot] = info
        else
            -- Slot just emptied? Detect destruction.
            local prev = previousActive[slot]
            if prev and not recallExpected then
                local expectedExpire = (prev.startTime or 0) + (prev.duration or 0)
                local timeLeft = expectedExpire - now
                -- Destroyed if more than 5s of duration was remaining.
                -- (Natural expirations land within +/- 1s; recalls are caught
                -- by the recallExpected flag above.)
                if timeLeft > 5 then
                    WT:Emit("TOTEM_DESTROYED", prev.element, prev.name)
                end
            end
            AC.active[slot] = nil
            previousActive[slot] = nil
        end
    end
    WT:Emit("AFFECTED_UPDATED", AC.active)
    return any
end

local function ensurePoller()
    if AC.poll then return end
    local f = CreateFrame("Frame")
    AC.poll = f
    local accum = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < POLL_INTERVAL then return end
        accum = 0
        local any = refreshActive()
        if not any then
            f:SetScript("OnUpdate", nil)
            AC.poll = nil
        end
    end)
end

-- ============================================================
-- Wiring
-- ============================================================

WT:On("PLAYER_TOTEM_UPDATE", function()
    refreshActive()
    ensurePoller()
end)

WT:On("GROUP_ROSTER_UPDATE", function()
    refreshActive()
end)

WT:On("LOGIN", function()
    refreshActive()
    -- if any totems are still up across UI reload, kick the poller
    for slot = 1, 4 do
        if AC.active[slot] then ensurePoller() break end
    end
end)
