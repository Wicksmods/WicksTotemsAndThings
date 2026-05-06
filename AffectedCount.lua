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
local POLL_INTERVAL = 0.5

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
    local list = {}
    if IsInRaid() then
        local n = (GetNumGroupMembers and GetNumGroupMembers())
               or (GetNumRaidMembers and GetNumRaidMembers())
               or 0
        for i = 1, n do table.insert(list, "raid" .. i) end
    elseif IsInGroup() then
        table.insert(list, "player")
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                table.insert(list, "party" .. i)
            end
        end
    else
        table.insert(list, "player")
    end
    return list
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
-- Active totem tracking
-- ============================================================

local function refreshActive()
    local any = false
    for slot = 1, 4 do
        local have, name, startTime, duration = GetTotemInfo(slot)
        if have and name and name ~= "" then
            any = true
            local meta = WT:GetTotemMeta(name)
            local range = meta and meta.range or 20
            local affected = AC:CountFor(range)
            AC.active[slot] = {
                name      = name,
                element   = WT.ELEMENT_BY_SLOT[slot],
                startTime = startTime,
                duration  = duration,
                range     = range,
                kind      = meta and meta.kind,
                affected  = affected,
            }
        else
            AC.active[slot] = nil
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
