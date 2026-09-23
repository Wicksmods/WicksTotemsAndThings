-- Wick's Totems and Things
-- Core.lua: WickCore addon object, saved variables, event dispatch, slash command.
--
-- Forever build. Under Midnight rules the twist timer, affected-count overlay,
-- range warnings, proc alerts and swing timer cannot exist: totem state and
-- the player's own auras are secret or unreadable in combat. What remains is
-- everything a shaman sets up before the pull: presets of four totems, the
-- secure cast bar, Call of the Elements sync, imbues, ankhs, and through
-- WickCore the talent layer, pre-pull checklist and racials.

local ADDON, ns = ...

local Core = WickCore
if not Core then
    -- WickCore is missing or switched off.
    --
    -- The TOC asks for it with OptionalDeps rather than Dependencies on
    -- purpose. A hard dependency makes the client refuse to load this addon
    -- at all, so nothing of ours runs and the player is told nothing beyond
    -- a greyed line in the AddOns list. Loading anyway lets us say what is
    -- wrong and where to get it.
    --
    -- One line for the lot of them, not one per addon: with the whole suite
    -- installed and WickCore switched off, a line each would be a wall.
    local need = _G.WicksNeedCore
    if not need then
        need = {}
        _G.WicksNeedCore = need
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            table.sort(need)
            print(("|cff4FC778Wick's Mods|r: %s %s WickCore, which is not installed or not switched on. It is in the same download as the rest of the suite: |cffD4C8A1wicksmods.com|r")
                :format(table.concat(need, ", "), #need == 1 and "needs" or "need"))
        end)
    end
    need[#need + 1] = "Wick's Totems and Things"
    return
end
local D, R = Core.Dialect, Core.Restrict

local PROFILE_DEFAULTS = {
    point = "CENTER", x = 0, y = 0,
    bar = { point = "CENTER", x = 0, y = -180, hidden = false, locked = false, scale = 1.0 },
    syncTotemBar = true,     -- push the active preset into Blizzard's totem bar
    kitWindow = {},
}
local CHAR_DEFAULTS = {
    activePreset = 1,
    presets = {},
    -- twist[element] = { enabled, totems = {a, b}, refresh }. The castsequence
    -- still works; the countdown cue is gone with the rules.
    twist = {},
}

local A = Core:NewAddon("WicksTotemsAndThings", {
    title    = "Wick's Totems and Things",
    version  = "1.0.0",
    savedVar = "WicksTotemsSaved",
    defaults = { profile = PROFILE_DEFAULTS, char = CHAR_DEFAULTS, global = {} },
})

-- ============================================================
-- Namespace
-- ============================================================
WicksTotems = WicksTotems or {}
local WT = WicksTotems
ns.WT = WT
WT.A = A
WT.ADDON = ADDON
WT.ELEMENTS = { "earth", "fire", "water", "air" }

-- The module files and Bindings.xml address these two names. They are
-- runtime aliases to the WickCore profile and character tables, bound in
-- OnInitialize, not saved variables of their own.
WicksTotemsDB     = WicksTotemsDB     or {}
WicksTotemsCharDB = WicksTotemsCharDB or {}

local DEFAULT_ELEMENT_ORDER = { "fire", "earth", "water", "air" }

local function isValidOrder(o)
    if type(o) ~= "table" or #o ~= 4 then return false end
    local seen = {}
    for _, name in ipairs(o) do seen[name] = (seen[name] or 0) + 1 end
    return seen.fire == 1 and seen.earth == 1 and seen.water == 1 and seen.air == 1
end

function WT.GetElementOrder()
    local preset = WT.GetActivePreset and WT:GetActivePreset() or nil
    if preset and isValidOrder(preset.elementOrder) then return preset.elementOrder end
    return DEFAULT_ELEMENT_ORDER
end

function WT.SetElementOrder(t)
    if type(t) ~= "table" or #t ~= 4 then return false, "need exactly 4 elements" end
    if not isValidOrder(t) then return false, "must contain fire, earth, water, air exactly once" end
    local preset = WT.GetActivePreset and WT:GetActivePreset() or nil
    if not preset then return false, "no active preset" end
    preset.elementOrder = { t[1], t[2], t[3], t[4] }
    WT:Emit("ELEMENT_ORDER_CHANGED")
    WT:Emit("PRESET_CHANGED")
    return true
end

local _, playerClass = UnitClass("player")
WT.playerClass = playerClass
WT.isShaman = (playerClass == "SHAMAN")

WT._listeners = {}
function WT:On(event, fn)
    self._listeners[event] = self._listeners[event] or {}
    table.insert(self._listeners[event], fn)
end
function WT:Emit(event, ...)
    local list = self._listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
    end
end

-- ============================================================
-- Active totems, read when the rules allow
-- ============================================================
-- Shape matches the old AffectedCount.active so TotemBar and the Active pane
-- keep working: { [slot] = { element, name, startTime, duration, range, kind } }.
-- Empty while totem state is secret (any combat on Forever). WT.totemsRestricted
-- tells the UI to say so instead of showing "(none)".
WT.SLOT_ELEMENT = { "fire", "earth", "water", "air" }

function WT:ActiveTotems()
    local out = {}
    self.totemsRestricted = false
    for slot = 1, 4 do
        local t = D.GetTotemInfo(slot)
        if t and t.secret then
            self.totemsRestricted = true
            return {}
        end
        if t and t.haveTotem and t.name and t.name ~= "" then
            local meta = self.GetTotemMeta and self:GetTotemMeta(t.name) or nil
            out[slot] = {
                element   = (meta and meta.element) or self.SLOT_ELEMENT[slot],
                name      = t.name,
                startTime = t.startTime,
                duration  = t.duration,
                range     = meta and meta.range,
                kind      = meta and meta.kind,
                spellID   = t.spellID,
            }
        end
    end
    return out
end

-- ============================================================
-- Lifecycle
-- ============================================================
function A:OnInitialize()
    WicksTotemsDB     = self.db.profile
    WicksTotemsCharDB = self.db.char
    WT.db = self.db

    self.db:On("OnProfileChanged", function()
        WicksTotemsDB = self.db.profile
        WT:Emit("PRESET_CHANGED")
    end)

    -- Kit: talents, pre-pull checklist, racials.
    Core.Cooldowns:New(self, { key = "cooldownBar" })

    Core.Kit:New(self, {
        racials = true,
        checklist = {
            { label = "Shield up",        aura = { "Water Shield", "Lightning Shield", "Earth Shield" }, cast = "Lightning Shield" },
            { label = "Main hand imbue",  weaponEnchant = "main", cast = "Rockbiter Weapon" },
            { label = "Off hand imbue",   weaponEnchant = "off",  check = function()
                if not GetInventoryItemLink("player", 17) then return true end
                local f = rawget(_G, "GetWeaponEnchantInfo"); if not f then return nil end
                local ok, _, _, _, _, oh = pcall(f); if not ok then return nil end
                return oh and true or false
            end },
            { label = "Ankhs in bags",    item = 17030, min = 1 },
            { label = "Totems ready",     check = function()
                local p = WT:GetActivePreset()
                if not p or not p.totems then return false end
                for _, el in ipairs(WT.ELEMENTS) do if not p.totems[el] or p.totems[el] == "" then return false end end
                return true
            end },
        },
    })
end

function A:OnEnable()
    if not WT.isShaman then
        self:Print("loaded (non-shaman: viewer mode).")
    else
        self:Print("loaded. /wtt to open, /wtt kit for talents and checklist.")
    end
    WT:Emit("LOGIN")

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then self.kit:Toggle()
            elseif WT.UI then WT.UI:Toggle() end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Totems and Things"))
            tt:AddLine("Left-click: panel   Right-click: talents and checklist", 0.5, 0.5, 0.5)
        end,
    })

    if self.cooldowns then self.cooldowns:Init() end

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local y = O:Heading(page, "Wick's Totems and Things", 0)
        y = O:Note(page, "Presets, the cast bar and twisting live in the panel (/wtt). Talents, checklist and racials live in the kit (/wtt kit).", y)
        y = O:Check(page, "Sync the active preset into Blizzard's totem bar",
            function() return WicksTotemsDB.syncTotemBar ~= false end,
            function(v) WicksTotemsDB.syncTotemBar = v; WT:Emit("PRESET_CHANGED") end, y)
        y = O:Button(page, "Open panel", function() if WT.UI then WT.UI:Toggle() end end, y, 100)
        y = O:Button(page, "Open kit", function() addon.kit:Toggle() end, y, 100)
        if addon.cooldowns then y = addon.cooldowns:OptionRow(page, y - 6) end
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

-- ============================================================
-- Game events
-- ============================================================
local f = CreateFrame("Frame")
WT.eventFrame = f
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                     "PLAYER_TOTEM_UPDATE", "GROUP_ROSTER_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        WT.inCombat = true
        WT:Emit("COMBAT_START")
    elseif event == "PLAYER_REGEN_ENABLED" then
        WT.inCombat = false
        WT:Emit("COMBAT_END")
        WT:Emit("AFFECTED_UPDATED")
    elseif event == "PLAYER_TOTEM_UPDATE" then
        -- Totem state is readable out of combat; that is when the bar and
        -- the Active pane refresh. In combat this fires into a wall.
        if not R:IsCombat() then WT:Emit("AFFECTED_UPDATED") end
    end
    WT:Emit(event, ...)
end)

-- ============================================================
-- Keybinding labels
-- ============================================================
BINDING_HEADER_WICKSTOTEMS = "Wick's Totems and Things"
_G["BINDING_NAME_CLICK WicksTotemsBar_DropAll:LeftButton"]      = "Drop active preset (all 4 totems in sequence)"
_G["BINDING_NAME_CLICK WicksTotemsBar_CallElements:LeftButton"] = "Call of the Elements (drop the synced set)"
_G["BINDING_NAME_CLICK WicksTotemsBar_FIRE:LeftButton"]         = "Cast Fire totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_EARTH:LeftButton"]        = "Cast Earth totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_WATER:LeftButton"]        = "Cast Water totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_AIR:LeftButton"]          = "Cast Air totem from active preset"
BINDING_NAME_WICKSTOTEMS_TOGGLE_PANEL = "Toggle main panel"
BINDING_NAME_WICKSTOTEMS_TOGGLE_BAR   = "Toggle totem icon bar"
BINDING_NAME_WICKSTOTEMS_CYCLE_PRESET = "Cycle to next preset"

-- ============================================================
-- Slash command
-- ============================================================
A:RegisterSlash(function(_, input)
    input = (input or ""):lower()
    if input == "" or input == "toggle" then
        if WT.UI then WT.UI:Toggle() end
        return
    end
    if input == "kit" or input == "talents" or input == "checklist" then A.kit:Toggle() return end
    if input == "cd" or input:match("^cd%s") then return A.cooldowns:Command(input:match("^%a+%s*(.*)$")) end
    if input == "help" or input == "?" then
        A:Print("commands")
        print("  /wtt              toggle main panel")
        print("  /wtt kit          talents, pre-pull checklist, racials")
        print("  /wtt bar          toggle the icon strip")
        print("  /wtt sync         push the active preset into Blizzard's totem bar")
        print("  /wtt lock|unlock  lock or unlock the icon strip")
        print("  /wtt reset        reset main panel position")
        print("  /wtt resetbar     reset icon-strip position")
        print("  /wtt resetpresets wipe presets and re-seed defaults")
        print("  /wtt status       print diagnostic info")
        print("  /wtt twist <el> on|off   totem twisting for an element")
        print("  /wtt order <e1> <e2> <e3> <e4>  totem drop order")
        return
    end
    if input == "reset" then
        WicksTotemsDB.point, WicksTotemsDB.x, WicksTotemsDB.y = "CENTER", 0, 0
        if WT.UI and WT.UI.frame then
            WT.UI.frame:ClearAllPoints()
            WT.UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        A:Print("position reset.")
        return
    end
    if input == "bar" then if WT.TotemBar then WT.TotemBar:Toggle() end return end
    if input == "sync" then
        if WT.TotemBar and WT.TotemBar.ApplyToTotemBar then
            local ok, why = WT.TotemBar:ApplyToTotemBar()
            A:Print(ok and "active preset pushed to the totem bar." or ("sync: " .. tostring(why)))
        end
        return
    end
    if input == "resetbar" then
        if WT.TotemBar then WT.TotemBar:ResetPosition() end
        A:Print("icon strip reset to center.")
        return
    end
    if input == "resetpresets" then
        WicksTotemsCharDB.presets = {}
        if WT.SeedDefaultPresets then WT:SeedDefaultPresets() end
        WT:Emit("PRESET_CHANGED")
        A:Print("presets reset to defaults.")
        return
    end
    if input == "status" then
        if WT.TotemBar and WT.TotemBar.Status then WT.TotemBar:Status() end
        A:Print("restrictions: " .. R:Summary())
        return
    end
    local orderArgs = input:match("^order%s*(.*)$")
    if orderArgs then
        if orderArgs == "" then
            A:Print("element order: " .. table.concat(WT.GetElementOrder(), ", "))
            return
        end
        local list = {}
        for word in orderArgs:gmatch("%S+") do table.insert(list, word:lower()) end
        local ok, err = WT.SetElementOrder(list)
        A:Print(ok and ("element order set to: " .. table.concat(list, ", ")) or (err or "invalid"))
        return
    end
    local twistCmd, twistArg = input:match("^twist%s+(%S+)%s*(.*)$")
    if twistCmd then
        local element, action = twistCmd, Core.trim(twistArg or "")
        WicksTotemsCharDB.twist = WicksTotemsCharDB.twist or {}
        local defaults = {
            air   = { totems = { "Windfury Totem", "Grace of Air Totem" }, refresh = 8  },
            earth = { totems = { "Strength of Earth Totem", "Stoneskin Totem" }, refresh = 20 },
            fire  = { totems = { "Searing Totem", "Magma Totem" }, refresh = 15 },
            water = { totems = { "Healing Stream Totem", "Mana Spring Totem" }, refresh = 15 },
        }
        local d = defaults[element]
        if not d then A:Print("element must be air, earth, fire, or water.") return end
        if action == "on" or action == "" then
            WicksTotemsCharDB.twist[element] = { enabled = true, totems = d.totems, refresh = d.refresh }
            WT:Emit("PRESET_CHANGED")
            A:Print(("%s twist enabled (%s)."):format(element, table.concat(d.totems, " <-> ")))
        elseif action == "off" then
            if WicksTotemsCharDB.twist[element] then WicksTotemsCharDB.twist[element].enabled = false end
            WT:Emit("PRESET_CHANGED")
            A:Print(("%s twist disabled."):format(element))
        else
            A:Print("try /wtt twist <element> on|off")
        end
        return
    end
    if input == "lock" then if WT.TotemBar then WT.TotemBar:Lock(true) end A:Print("icon strip locked.") return end
    if input == "unlock" then if WT.TotemBar then WT.TotemBar:Lock(false) end A:Print("icon strip unlocked.") return end
    if input == "bindings" then
        if WT.UI then WT.UI:SelectTab("bindings"); WT.UI:Show() end
        return
    end
    A:Print("unknown command. Try /wtt help")
end, "/wtt", "/wickstotems")
