-- Wick's Totems and Things
-- TotemFrameOverlay.lua: attaches a small count badge to each Blizzard
-- TotemFrame button so the affected count is visible on the active totem
-- icon next to the minimap.
--
-- Skinned UIs (ElvUI, Bartender, etc.) restyle but typically retain the
-- original child buttons. We try multiple known names and fall back to
-- walking TotemFrame children. If everything fails, the icon strip
-- (TotemBar.lua) carries the count overlay independently.

local ADDON, ns = ...
local WT = WicksTotems

WT.TotemFrameOverlay = {}
local TFO = WT.TotemFrameOverlay

local C_GREEN = { 0.310, 0.780, 0.471, 1 }

-- Cache resolved buttons by slot. Cleared on PLAYER_ENTERING_WORLD in case
-- a UI mod recreates them.
TFO._buttonBySlot = {}

local function tryGlobal(name)
    return _G[name]
end

local function resolveButton(slot)
    if TFO._buttonBySlot[slot] then return TFO._buttonBySlot[slot] end

    -- Common Blizzard / skin naming patterns
    local candidates = {
        "TotemFrameTotem" .. slot,
        "TotemFrameSlotButton" .. slot,
        "MultiCastSlotButton" .. slot,
        "MultiCastActionButton" .. slot,
    }
    for _, name in ipairs(candidates) do
        local b = tryGlobal(name)
        if b and b.CreateTexture then
            TFO._buttonBySlot[slot] = b
            return b
        end
    end

    -- Walk TotemFrame children: keep buttons that have a `slot` field
    -- matching, else fall back to position-order indexing.
    if TotemFrame and TotemFrame.GetChildren then
        local kids = { TotemFrame:GetChildren() }
        local matched = {}
        for _, k in ipairs(kids) do
            if k and k.CreateTexture then
                if k.slot == slot then
                    TFO._buttonBySlot[slot] = k
                    return k
                end
                table.insert(matched, k)
            end
        end
        if matched[slot] then
            TFO._buttonBySlot[slot] = matched[slot]
            return matched[slot]
        end
    end

    return nil
end

local function ensureBadge(btn)
    if btn._wtBadge then return btn._wtBadge end

    local bg = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    bg:SetColorTexture(0, 0, 0, 0.85)
    bg:SetSize(22, 14)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:Hide()
    btn._wtBadgeBg = bg

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    fs:SetPoint("BOTTOMRIGHT", -2, 0)
    fs:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    fs:SetText("")
    btn._wtBadge = fs

    return fs
end

function TFO:Refresh()
    local enabled = WicksTotemsDB.overlay and WicksTotemsDB.overlay.enabled
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    for slot = 1, 4 do
        local btn = resolveButton(slot)
        if btn then
            local badge = ensureBadge(btn)
            local info = active[slot]
            if enabled and info and info.range ~= "self" and info.range ~= "summon" and info.range ~= "enemy" then
                badge:SetText(tostring(info.affected or 0))
                btn._wtBadgeBg:Show()
                badge:Show()
            else
                badge:SetText("")
                btn._wtBadgeBg:Hide()
            end
        end
    end
end

function TFO:DiagnoseFrames()
    print("|cff4FC778Wick's Totems|r TotemFrame diagnostic:")
    if not TotemFrame then
        print("  TotemFrame: missing (UI mod has hidden it)")
        return
    end
    print(("  TotemFrame: present, shown=%s"):format(TotemFrame:IsShown() and "yes" or "no"))
    if TotemFrame.GetChildren then
        local kids = { TotemFrame:GetChildren() }
        print(("  child count: %d"):format(#kids))
        for i, k in ipairs(kids) do
            local n = k.GetName and k:GetName() or "(unnamed)"
            local t = k.GetObjectType and k:GetObjectType() or "?"
            print(("    [%d] %s (%s)"):format(i, n, t))
        end
    end
    for slot = 1, 4 do
        local b = resolveButton(slot)
        local n = b and b.GetName and b:GetName() or "nil"
        print(("  slot %d resolved to: %s"):format(slot, n))
    end
end

WT:On("AFFECTED_UPDATED",   function() TFO:Refresh() end)
WT:On("PLAYER_TOTEM_UPDATE", function() TFO:Refresh() end)
WT:On("LOGIN",               function() TFO:Refresh() end)
WT:On("PLAYER_ENTERING_WORLD", function()
    TFO._buttonBySlot = {}
    TFO:Refresh()
end)
