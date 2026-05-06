-- Wick's Totems and Things
-- AffectedCount.lua: tracks active totems and counts party/raid members
-- inside their effect radius.
--
-- Range strategy (v0.1):
--   UnitInRange(unit) reports 40yd healing range relative to the player.
--   That's an over-count for 20yd totems (most of them) but a clean lower
--   bound is "anyone not in 40yd of you is definitely not getting buffed."
--   v0.2 will tighten to per-totem precise checks with verified range
--   items via IsItemInRange. Architecture is identical; the scan() function
--   is the only thing that changes.

local ADDON, ns = ...
local WT = WicksTotems

WT.AffectedCount = {}
local AC = WT.AffectedCount

AC.active = {}    -- [slot] = { name = ..., affected = N, lastScan = t }
AC.poll = nil     -- ticker frame
local POLL_INTERVAL = 0.5

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
    -- "raid", or any number, falls through to the generic scan.
    local n = 0
    for _, u in ipairs(unitsInGroup()) do
        if UnitExists(u) and not UnitIsDeadOrGhost(u) then
            if u == "player" then
                n = n + 1
            elseif UnitInRange(u) then
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
