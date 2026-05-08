-- Wick's Totems and Things
-- Core.lua: namespace, saved variables, event dispatch, slash command

local ADDON, ns = ...

WicksTotemsDB = WicksTotemsDB or {
    version = 1,
    point = "CENTER", x = 0, y = 0,
    bar = { point = "CENTER", x = 0, y = -180, hidden = false, locked = false },
    minimap = { hide = false, angle = 200 },
    range = { enabled = true, sound = true, banner = true, vignette = true },
    overlay = { enabled = true },
}
WicksTotemsDB.bar     = WicksTotemsDB.bar     or { point = "CENTER", x = 0, y = -180, hidden = false, locked = false }
-- Element drop order is now per-preset (lives in WicksTotemsCharDB.presets[i].elementOrder).
-- Account-wide WicksTotemsDB.elementOrder is no longer authoritative; left
-- here as a fallback when no preset is active.
WicksTotemsDB.range   = WicksTotemsDB.range   or { enabled = true, sound = true, banner = true, vignette = true }
WicksTotemsDB.overlay = WicksTotemsDB.overlay or { enabled = true }
WicksTotemsDB.cd      = WicksTotemsDB.cd      or {}
WicksTotemsDB.swing   = WicksTotemsDB.swing   or {}
-- Per-bar scale (1.0 = 100%, range 0.6 to 1.8)
WicksTotemsDB.bar.scale   = WicksTotemsDB.bar.scale   or 1.0
WicksTotemsDB.cd.scale    = WicksTotemsDB.cd.scale    or 1.0
WicksTotemsDB.swing.scale = WicksTotemsDB.swing.scale or 1.0

-- Presets are named bundles of up to 4 totems (one per element).
-- Empty defaults; UI seeds two starter presets on first open if list is empty.
WicksTotemsCharDB = WicksTotemsCharDB or {
    version = 1,
    activePreset = 1,
    presets = {},
    -- twist[element] = { enabled = true, totems = {"a","b"}, refresh = 10 }
    -- When enabled, the element button uses /castsequence and shows a
    -- countdown overlay until refresh. Default: air twist Windfury/Grace.
    twist = {},
}
WicksTotemsCharDB.twist = WicksTotemsCharDB.twist or {}

WicksTotems = WicksTotems or {}
local WT = WicksTotems
ns.WT = WT

WT.ADDON = ADDON
WT.ELEMENTS = { "earth", "fire", "water", "air" }

-- Element drop order is per-preset, stored on the preset itself as
-- preset.elementOrder. Falls back to the canonical default when no
-- active preset is set yet.
local DEFAULT_ELEMENT_ORDER = { "fire", "earth", "water", "air" }

local function isValidOrder(o)
    if type(o) ~= "table" or #o ~= 4 then return false end
    local seen = {}
    for _, name in ipairs(o) do seen[name] = (seen[name] or 0) + 1 end
    return seen.fire == 1 and seen.earth == 1 and seen.water == 1 and seen.air == 1
end

function WT.GetElementOrder()
    local preset = WT.GetActivePreset and WT:GetActivePreset() or nil
    if preset and isValidOrder(preset.elementOrder) then
        return preset.elementOrder
    end
    return DEFAULT_ELEMENT_ORDER
end

-- Validate + persist a new order on the ACTIVE preset. Emits both
-- ELEMENT_ORDER_CHANGED and PRESET_CHANGED so the TotemBar re-anchors
-- and rebuilds its macros.
function WT.SetElementOrder(t)
    if type(t) ~= "table" or #t ~= 4 then return false, "need exactly 4 elements" end
    if not isValidOrder(t) then
        return false, "must contain fire, earth, water, air exactly once"
    end
    local preset = WT.GetActivePreset and WT:GetActivePreset() or nil
    if not preset then return false, "no active preset" end
    preset.elementOrder = { t[1], t[2], t[3], t[4] }
    if WT.Emit then
        WT:Emit("ELEMENT_ORDER_CHANGED")
        WT:Emit("PRESET_CHANGED")
    end
    return true
end

local _, playerClass = UnitClass("player")
WT.playerClass = playerClass
WT.isShaman = (playerClass == "SHAMAN")

-- Pub/sub for module wiring (UI re-render, totem-bar refresh, count refresh)
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
        if not ok then
            print(("|cff4FC778Wick's Totems|r error in %s: %s"):format(event, tostring(err)))
        end
    end
end

-- Event frame
local f = CreateFrame("Frame")
WT.eventFrame = f

local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TOTEM_UPDATE",
    "GROUP_ROSTER_UPDATE",
}
for _, e in ipairs(EVENTS) do
    pcall(f.RegisterEvent, f, e)
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not WT.isShaman then
            print("|cff4FC778Wick's Totems and Things|r loaded (non-shaman: viewer mode).")
        else
            print("|cff4FC778Wick's Totems and Things|r loaded. /wtt to open.")
        end
        WT:Emit("LOGIN")
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        WT.inCombat = true
        WT:Emit("COMBAT_START")
    elseif event == "PLAYER_REGEN_ENABLED" then
        WT.inCombat = false
        WT:Emit("COMBAT_END")
    end

    WT:Emit(event, ...)
end)

-- ============================================================
-- Keybinding labels (Esc -> Key Bindings -> AddOns)
-- ============================================================
BINDING_HEADER_WICKSTOTEMS = "Wick's Totems and Things"

_G["BINDING_NAME_CLICK WicksTotemsBar_DropAll:LeftButton"] = "Drop active preset (all 4 totems in sequence)"
_G["BINDING_NAME_CLICK WicksTotemsBar_FIRE:LeftButton"]    = "Cast Fire totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_EARTH:LeftButton"]   = "Cast Earth totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_WATER:LeftButton"]   = "Cast Water totem from active preset"
_G["BINDING_NAME_CLICK WicksTotemsBar_AIR:LeftButton"]     = "Cast Air totem from active preset"

BINDING_NAME_WICKSTOTEMS_TOGGLE_PANEL = "Toggle main panel"
BINDING_NAME_WICKSTOTEMS_TOGGLE_BAR   = "Toggle totem icon bar"
BINDING_NAME_WICKSTOTEMS_CYCLE_PRESET = "Cycle to next preset"

-- Slash command
SLASH_WICKSTOTEMS1 = "/wtt"
SLASH_WICKSTOTEMS2 = "/wickstotems"
SlashCmdList.WICKSTOTEMS = function(input)
    input = (input or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    if input == "" or input == "toggle" then
        if WT.UI and WT.UI.Toggle then WT.UI:Toggle() end
        return
    end
    if input == "help" or input == "?" then
        print("|cff4FC778Wick's Totems and Things|r")
        print("  /wtt              toggle main panel")
        print("  /wtt bar          toggle slim icon strip")
        print("  /wtt lock         lock the icon strip in place")
        print("  /wtt unlock       allow dragging the icon strip")
        print("  /wtt bindings     jump to bindings tab")
        print("  /wtt reset        reset main panel position")
        print("  /wtt resetbar     reset icon-strip position (recovers a lost bar)")
        print("  /wtt resetpresets wipe presets and re-seed defaults")
        print("  /wtt status       print diagnostic info")
        print("  /wtt range        print range-warning diagnostic")
        print("  /wtt rangeon      enable out-of-range warnings")
        print("  /wtt rangeoff     disable out-of-range warnings")
        print("  /wtt cd           toggle cooldown / proc icon bar")
        print("  /wtt resetcd      reset cooldown bar position")
        print("  /wtt swing        toggle swing timer bar")
        print("  /wtt resetswing   reset swing timer position")
        print("  /wtt twist <el> on|off   enable totem twisting for an element")
        print("  /wtt order <e1> <e2> <e3> <e4>  set totem element drop order")
        return
    end
    if input == "reset" then
        WicksTotemsDB.point = "CENTER"
        WicksTotemsDB.x, WicksTotemsDB.y = 0, 0
        if WT.UI and WT.UI.frame then
            WT.UI.frame:ClearAllPoints()
            WT.UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        print("|cff4FC778Wick's Totems|r position reset.")
        return
    end
    if input == "bar" then
        if WT.TotemBar and WT.TotemBar.Toggle then WT.TotemBar:Toggle() end
        return
    end
    if input == "resetbar" then
        if WT.TotemBar and WT.TotemBar.ResetPosition then WT.TotemBar:ResetPosition() end
        print("|cff4FC778Wick's Totems|r icon strip reset to center.")
        return
    end
    if input == "resetpresets" then
        WicksTotemsCharDB.presets = {}
        if WT.SeedDefaultPresets then WT:SeedDefaultPresets() end
        WT:Emit("PRESET_CHANGED")
        print("|cff4FC778Wick's Totems|r presets reset to defaults.")
        return
    end
    if input == "status" then
        if WT.TotemBar and WT.TotemBar.Status then WT.TotemBar:Status() end
        if WT.TotemFrameOverlay and WT.TotemFrameOverlay.DiagnoseFrames then
            WT.TotemFrameOverlay:DiagnoseFrames()
        end
        return
    end
    if input == "range" then
        if WT.RangeWarning and WT.RangeWarning.Diagnose then WT.RangeWarning:Diagnose() end
        return
    end
    if input == "rangeon" then
        if WT.RangeWarning and WT.RangeWarning.SetEnabled then WT.RangeWarning:SetEnabled(true) end
        print("|cff4FC778Wick's Totems|r range warnings enabled.")
        return
    end
    if input == "rangeoff" then
        if WT.RangeWarning and WT.RangeWarning.SetEnabled then WT.RangeWarning:SetEnabled(false) end
        print("|cff4FC778Wick's Totems|r range warnings disabled.")
        return
    end
    if input == "cd" then
        if WT.CooldownTracker and WT.CooldownTracker.Toggle then WT.CooldownTracker:Toggle() end
        return
    end
    if input == "resetcd" then
        if WT.CooldownTracker and WT.CooldownTracker.ResetPosition then WT.CooldownTracker:ResetPosition() end
        print("|cff4FC778Wick's Totems|r cooldown bar reset.")
        return
    end
    if input == "cdtest" then
        if WT.CooldownTracker and WT.CooldownTracker.Diagnose then WT.CooldownTracker:Diagnose() end
        return
    end
    if input == "cdrebuild" then
        if WT.CooldownTracker and WT.CooldownTracker.ForceReinit then
            WT.CooldownTracker:ForceReinit()
        end
        return
    end
    -- /wtt order fire earth water air  (or any permutation)
    -- /wtt order             prints current order
    local orderArgs = input:match("^order%s*(.*)$")
    if orderArgs then
        if orderArgs == "" then
            local o = WT.GetElementOrder()
            print("|cff4FC778Wick's Totems|r element order: " .. table.concat(o, ", "))
            print("  set with: /wtt order <e1> <e2> <e3> <e4>")
            return
        end
        local list = {}
        for word in orderArgs:gmatch("%S+") do
            table.insert(list, word:lower())
        end
        local ok, err = WT.SetElementOrder(list)
        if ok then
            print("|cff4FC778Wick's Totems|r element order set to: " .. table.concat(list, ", "))
        else
            print("|cff4FC778Wick's Totems|r: " .. (err or "invalid"))
        end
        return
    end
    if input == "resetprocs" then
        if WT.ProcAlerts and WT.ProcAlerts.ResetPositions then
            WT.ProcAlerts:ResetPositions()
            print("|cff4FC778Wick's Totems|r proc floaters reset to default grid.")
        end
        return
    end
    if input == "procedit" then
        if WT.ProcAlerts and WT.ProcAlerts.SetEditMode then
            local on = not (WT.ProcAlerts.editMode or false)
            WT.ProcAlerts:SetEditMode(on)
            print(("|cff4FC778Wick's Totems|r proc edit mode: %s"):format(on and "ON" or "off"))
        end
        return
    end
    if input == "swing" then
        if WT.SwingTimer and WT.SwingTimer.Toggle then WT.SwingTimer:Toggle() end
        return
    end
    if input == "resetswing" then
        if WT.SwingTimer and WT.SwingTimer.ResetPosition then WT.SwingTimer:ResetPosition() end
        print("|cff4FC778Wick's Totems|r swing timer reset.")
        return
    end
    -- Twist commands: /wtt twist <element> on|off
    local twistCmd, twistArg = input:match("^twist%s+(%S+)%s*(.*)$")
    if twistCmd then
        local element = twistCmd
        local action = (twistArg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        WicksTotemsCharDB.twist = WicksTotemsCharDB.twist or {}
        if action == "on" or action == "" then
            local defaults = {
                air   = { totems = { "Windfury Totem", "Grace of Air Totem" }, refresh = 5  },
                earth = { totems = { "Strength of Earth Totem", "Stoneskin Totem" }, refresh = 20 },
                fire  = { totems = { "Searing Totem", "Magma Totem" }, refresh = 15 },
                water = { totems = { "Healing Stream Totem", "Mana Spring Totem" }, refresh = 15 },
            }
            local d = defaults[element]
            if not d then
                print("|cff4FC778Wick's Totems|r: element must be air, earth, fire, or water.")
                return
            end
            WicksTotemsCharDB.twist[element] = {
                enabled = true,
                totems  = d.totems,
                refresh = d.refresh,
            }
            WT:Emit("PRESET_CHANGED")
            print(("|cff4FC778Wick's Totems|r %s twist enabled (%s, refresh %ds)."):format(
                element, table.concat(d.totems, " <-> "), d.refresh))
        elseif action == "off" then
            if WicksTotemsCharDB.twist[element] then
                WicksTotemsCharDB.twist[element].enabled = false
                WT:Emit("PRESET_CHANGED")
                print(("|cff4FC778Wick's Totems|r %s twist disabled."):format(element))
            end
        else
            print("|cff4FC778Wick's Totems|r: try /wtt twist <element> on|off")
        end
        return
    end
    if input == "lock" then
        if WT.TotemBar and WT.TotemBar.Lock then WT.TotemBar:Lock(true) end
        print("|cff4FC778Wick's Totems|r icon strip locked.")
        return
    end
    if input == "unlock" then
        if WT.TotemBar and WT.TotemBar.Lock then WT.TotemBar:Lock(false) end
        print("|cff4FC778Wick's Totems|r icon strip unlocked.")
        return
    end
    if input == "bindings" then
        if WT.UI and WT.UI.SelectTab then WT.UI:SelectTab("bindings") end
        if WT.UI and WT.UI.Show then WT.UI:Show() end
        return
    end
    print("|cff4FC778Wick's Totems|r: unknown command. Try /wtt help")
end
