-- Wick's Totems and Things
-- Totems.lua: TBC shaman totem catalog (name-keyed, used for macro generation
-- and matching active totems via GetTotemInfo). Names are spell names, not
-- item names. Ranks are implicit (/cast picks the highest known).

local ADDON, ns = ...
local WT = WicksTotems

-- Slot indices used by GetTotemInfo / PLAYER_TOTEM_UPDATE in TBC 2.5.5.
-- Verify in-game: GetTotemInfo(1) should match a fire totem after dropping one.
WT.SLOT = {
    FIRE  = 1,
    EARTH = 2,
    WATER = 3,
    AIR   = 4,
}

WT.ELEMENT_BY_SLOT = { "fire", "earth", "water", "air" }

-- Range token meanings:
--   "self"       — totem only affects the shaman (Sentry, Earth Elemental etc.)
--   "enemy"      — offensive, no ally radius
--   <number>     — yards, ally aura radius
--   "raid"       — full party/raid (Mana Tide is 40yd, treat as full party)
--
-- "buff" — applies a continuous group buff (counted by AffectedCount)
-- "util" — situational utility (Tremor, Grounding); allies-in-range still useful
-- "summon" — summons an elemental, no aura

-- `buff` is the player-aura name that signals "in range of this totem."
-- Used by RangeWarning to detect when the player has stepped out of range
-- of a totem they cast. nil = no checkable aura (utility/offensive totems).
WT.TOTEMS = {
    -- ---------- EARTH ----------
    earth = {
        { name = "Earthbind Totem",          range = 10,       kind = "util"  },
        { name = "Stoneskin Totem",          range = 20,       kind = "buff",  buff = "Stoneskin"            },
        { name = "Stoneclaw Totem",          range = "self",   kind = "util"  },
        { name = "Strength of Earth Totem",  range = 20,       kind = "buff",  buff = "Strength of Earth"    },
        { name = "Tremor Totem",             range = 30,       kind = "util"  },
        { name = "Earth Elemental Totem",    range = "summon", kind = "summon"},
    },
    -- ---------- FIRE ----------
    fire = {
        { name = "Searing Totem",            range = "enemy",  kind = "util"  },
        { name = "Fire Nova Totem",          range = 10,       kind = "util"  },
        { name = "Magma Totem",              range = 10,       kind = "util"  },
        { name = "Frost Resistance Totem",   range = 20,       kind = "buff",  buff = "Frost Resistance"     },
        { name = "Flametongue Totem",        range = 20,       kind = "buff",  buff = "Flametongue Totem"    },
        { name = "Totem of Wrath",           range = 40,       kind = "buff",  buff = "Totem of Wrath"       },
        { name = "Fire Elemental Totem",     range = "summon", kind = "summon"},
    },
    -- ---------- WATER ----------
    -- Healing Stream / Mana Spring / Mana Tide tick effects directly (no
    -- sustained aura on the player), so range can't be detected via buffs.
    -- Range warning is skipped for them in v0.1.
    water = {
        { name = "Healing Stream Totem",     range = 20,       kind = "buff"                                  },
        { name = "Mana Spring Totem",        range = 20,       kind = "buff"                                  },
        { name = "Mana Tide Totem",          range = "raid",   kind = "buff"                                  },
        { name = "Poison Cleansing Totem",   range = 20,       kind = "util"  },
        { name = "Disease Cleansing Totem",  range = 20,       kind = "util"  },
        { name = "Fire Resistance Totem",    range = 20,       kind = "buff",  buff = "Fire Resistance"      },
    },
    -- ---------- AIR ----------
    air = {
        { name = "Grounding Totem",          range = "self",   kind = "util"  },
        -- Windfury Totem: only melee classes see the aura. Skip range
        -- check (no buff field) so caster shamans don't get false OOR.
        { name = "Windfury Totem",           range = 20,       kind = "buff"                                  },
        { name = "Wrath of Air Totem",       range = 20,       kind = "buff",  buff = "Wrath of Air"         },
        { name = "Grace of Air Totem",       range = 20,       kind = "buff",  buff = "Grace of Air"         },
        { name = "Tranquil Air Totem",       range = 30,       kind = "buff",  buff = "Tranquil Air"         },
        { name = "Nature Resistance Totem",  range = 20,       kind = "buff",  buff = "Nature Resistance"    },
        { name = "Sentry Totem",             range = "self",   kind = "util"  },
        { name = "Windwall Totem",           range = 20,       kind = "buff",  buff = "Windwall Totem"       },
    },
}

-- Lookup by name (case-sensitive against /cast spelling) → { element, range, kind, buff }
local byName = {}
for element, list in pairs(WT.TOTEMS) do
    for _, t in ipairs(list) do
        byName[t.name] = {
            element = element,
            range   = t.range,
            kind    = t.kind,
            buff    = t.buff,
        }
    end
end
WT.TOTEM_BY_NAME = byName

-- GetTotemInfo returns names with rank suffixes ("Strength of Earth Totem IV",
-- "Searing Totem V", "Windfury Totem III"). Our static catalog is keyed
-- without ranks, so strip the trailing roman-numeral rank before lookup.
local function stripRank(name)
    if not name then return name end
    -- Trim a trailing " <roman numerals>" — e.g. " IV", " V", " VIII"
    local stripped = name:gsub("%s+[IVX]+$", "")
    return stripped
end
WT.StripTotemRank = stripRank

function WT:GetTotemMeta(name)
    if not name then return nil end
    return byName[name] or byName[stripRank(name)]
end
