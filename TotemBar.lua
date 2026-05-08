-- Wick's Totems and Things
-- TotemBar.lua: visible slim icon strip + secure cast buttons.
--   * 4 visible icon buttons (Fire/Earth/Water/Air) — click casts that
--     element's totem from the active preset, secure execution.
--   * 1 hidden Drop-All button — keybind only, drops all 4 in sequence.
--   * Macrotext rebuilds happen out-of-combat only; in-combat changes are
--     deferred to PLAYER_REGEN_ENABLED.

local ADDON, ns = ...
local WT = WicksTotems

WT.TotemBar = {}
local TB = WT.TotemBar

-- ELEMENT_ORDER is now driven by saved-vars via WT.GetElementOrder().
-- Call elements() at every iteration so drop-order edits propagate live.
-- Default kept inline as a safety fallback for the brief window between
-- Core.lua loading and saved-vars hydration.
local function elements()
    if WT.GetElementOrder then return WT.GetElementOrder() end
    return { "fire", "earth", "water", "air" }
end
local ELEMENT_ORDER = { "fire", "earth", "water", "air" }   -- legacy fallback
local ELEMENT_TINT = {
    fire  = { 0.95, 0.55, 0.30 },
    earth = { 0.55, 0.75, 0.45 },
    water = { 0.45, 0.65, 0.95 },
    air   = { 0.85, 0.85, 0.95 },
}

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_HEADER_BG   = { 0.090, 0.067, 0.141, 1 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local ICON_SIZE = 36
local ICON_GAP  = 4
local PADDING   = 6

-- Compresses a Blizzard binding string ("CTRL-SHIFT-A") into something that
-- fits on a 36px icon ("csA"). Mirrors the helper in Wick's Quest Key.
local function shortBind(key)
    if not key or key == "" then return "" end
    return (key:upper()
        :gsub("ALT%-", "a")
        :gsub("CTRL%-", "c")
        :gsub("SHIFT%-", "s")
        :gsub("NUMPAD", "n")
        :gsub("BUTTON1", "M1")
        :gsub("BUTTON2", "M2")
        :gsub("BUTTON3", "M3")
        :gsub("MOUSEWHEELUP",   "MwU")
        :gsub("MOUSEWHEELDOWN", "MwD"))
end

-- ============================================================
-- Preset helpers
-- ============================================================

-- Defaults use baseline totems every shaman has at level 32+. Talent-gated
-- totems (Totem of Wrath, Wrath of Air, Mana Tide) would silently freeze
-- /castsequence when the player doesn't know the spell.
local DEFAULT_PRESETS = {
    {
        name = "Caster",
        totems = {
            fire  = "Searing Totem",
            earth = "Strength of Earth Totem",
            water = "Mana Spring Totem",
            air   = "Grace of Air Totem",
        },
    },
    {
        name = "Melee",
        totems = {
            fire  = "Searing Totem",
            earth = "Strength of Earth Totem",
            water = "Healing Stream Totem",
            air   = "Windfury Totem",
        },
    },
}

function WT:SeedDefaultPresets()
    if not WicksTotemsCharDB.presets or #WicksTotemsCharDB.presets == 0 then
        WicksTotemsCharDB.presets = {}
        for _, p in ipairs(DEFAULT_PRESETS) do
            local copy = { name = p.name, totems = {} }
            for k, v in pairs(p.totems) do copy.totems[k] = v end
            table.insert(WicksTotemsCharDB.presets, copy)
        end
        WicksTotemsCharDB.activePreset = 1
    end
end

function WT:GetActivePreset()
    local idx = WicksTotemsCharDB.activePreset or 1
    return WicksTotemsCharDB.presets and WicksTotemsCharDB.presets[idx], idx
end

-- ============================================================
-- Macro construction
-- ============================================================

local function buildPresetMacro(preset)
    -- TBC macros can't bypass the GCD, so /cast Lightning, /cast Magma only
    -- ever fires the first one. /castsequence advances on each press, so the
    -- shaman taps the keybind 4 times to drop all 4 totems (one per GCD).
    -- reset=15 (seconds) so the sequence rewinds if the rotation is paused.
    if not preset or not preset.totems then return "" end
    local names = {}
    for _, el in ipairs(elements()) do
        local n = preset.totems[el]
        if n and n ~= "" then table.insert(names, n) end
    end
    if #names == 0 then return "" end
    return "#showtooltip\n/castsequence reset=15 " .. table.concat(names, ", ")
end

local function buildElementMacro(preset, element)
    -- Twist override: if WicksTotemsCharDB.twist[element].enabled and has
    -- 2+ totems, the element button cycles through them via /castsequence.
    local twist = WicksTotemsCharDB.twist and WicksTotemsCharDB.twist[element]
    if twist and twist.enabled and twist.totems and #twist.totems >= 2 then
        return ("#showtooltip\n/castsequence reset=%d %s"):format(
            twist.refresh or 10, table.concat(twist.totems, ", "))
    end
    if not preset or not preset.totems then return "" end
    local name = preset.totems[element]
    if not name or name == "" then return "" end
    return "#showtooltip\n/cast " .. name
end

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
    arm = arm or 8
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
-- Secure-button construction
-- ============================================================

local function makeSecureButton(name, parent, visible)
    -- Both Up and Down: keybind dispatch via SetBindingClick fires Click(),
    -- which is treated as Up by default. Registering both keeps mouse-click
    -- responsiveness AND keybind dispatch working.
    -- type1 (left-click only) so the right-click is free for our picker UI.
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    if visible then
        b:SetSize(ICON_SIZE, ICON_SIZE)
    else
        b:SetSize(1, 1); b:SetAlpha(0)
    end
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext", "")
    b:SetAttribute("macrotext1", "")
    return b
end

-- Diagnostic: print current macrotext for each button
function TB:Status()
    print("|cff4FC778Wick's Totems bar status:|r")
    print(("  in combat: %s"):format(InCombatLockdown() and "yes" or "no"))
    if self.dropAll then
        local m = self.dropAll:GetAttribute("macrotext1") or self.dropAll:GetAttribute("macrotext") or ""
        print("  drop-all macrotext1: " .. (m:gsub("\n", " | ")))
    end
    for _, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn then
            local m = btn:GetAttribute("macrotext1") or btn:GetAttribute("macrotext") or ""
            local twist = WicksTotemsCharDB.twist and WicksTotemsCharDB.twist[el]
            local twistOn = twist and twist.enabled and "ON" or "off"
            print(("  %s [twist:%s]: %s"):format(el, twistOn, (m:gsub("\n", " | "))))
        end
    end
end

-- ============================================================
-- Visible icon (built on top of a secure button)
-- ============================================================

local function styleIconButton(b, element)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b._icon = icon

    -- empty-slot tint (when no totem assigned)
    local empty = b:CreateTexture(nil, "ARTWORK")
    empty:SetAllPoints(b)
    local tint = ELEMENT_TINT[element]
    empty:SetColorTexture(tint[1], tint[2], tint[3], 0.18)
    b._empty = empty

    -- 1px dark frame around the icon
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

    -- Active glow: green frame when this element's totem is currently down
    local function glow(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.95)
        t:SetPoint(p1, -1, 1 * (p1:find("TOP") and 1 or -1))
        t:SetPoint(p2, 1, 1 * (p2:find("TOP") and 1 or -1))
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:Hide()
        return t
    end
    b._glow = {
        glow("TOPLEFT", "TOPRIGHT", nil, 2),
        glow("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
        glow("TOPLEFT", "BOTTOMLEFT", 2, nil),
        glow("TOPRIGHT", "BOTTOMRIGHT", 2, nil),
    }

    -- count badge (bottom-right corner)
    local badgeBg = b:CreateTexture(nil, "OVERLAY")
    badgeBg:SetColorTexture(0, 0, 0, 0.78)
    badgeBg:SetSize(18, 13)
    badgeBg:SetPoint("BOTTOMRIGHT", 0, 0)
    badgeBg:Hide()
    b._badgeBg = badgeBg

    local badge = b:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    badge:SetPoint("BOTTOMRIGHT", -2, 1)
    badge:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    badge:SetText("")
    b._badge = badge

    -- duration text (top-left corner)
    local duration = b:CreateFontString(nil, "OVERLAY")
    duration:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    duration:SetPoint("TOPLEFT", 2, -2)
    duration:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    duration:SetText("")
    b._duration = duration

    -- Removed dead FontString — twist visual cue is the icon switching
    -- between totems + the centered countdown/"!" text + dim/bright icon.

    -- keybind label (top-right corner, mirrors Wick's Quest Key)
    local bindLbl = b:CreateFontString(nil, "OVERLAY")
    bindLbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    bindLbl:SetPoint("TOPRIGHT", -2, -2)
    bindLbl:SetTextColor(1, 1, 1, 1)
    bindLbl:SetText("")
    b._bindLbl = bindLbl

    -- Twist countdown (centered, bigger, only visible while twisting)
    local twistText = b:CreateFontString(nil, "OVERLAY")
    twistText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    twistText:SetPoint("CENTER")
    twistText:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    twistText:SetText("")
    b._twist = twistText

    -- tooltip on hover
    b:SetScript("OnEnter", function(self)
        local preset = WT:GetActivePreset()
        local name = preset and preset.totems and preset.totems[element]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if name and name ~= "" then
            GameTooltip:AddLine(name, C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
            GameTooltip:AddLine(("%s slot"):format(element:gsub("^%l", string.upper)),
                C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        else
            GameTooltip:AddLine(("(no %s totem set)"):format(element),
                C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        end
        GameTooltip:AddLine("Right-click to change totem", C_GREEN[1], C_GREEN[2], C_GREEN[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Right-click → open the totem picker for the active preset's slot.
    -- Uses PostClick (runs AFTER secure dispatch) so left-click cast is
    -- never disrupted; right-click has no secure attribute (type1 only).
    b:SetScript("PostClick", function(self, button)
        if button ~= "RightButton" then return end
        if InCombatLockdown() then return end  -- preset edits in combat are blocked anyway
        if not WT.UI or not WT.UI.OpenPicker then return end
        local idx = WicksTotemsCharDB.activePreset or 1
        WT.UI:OpenPicker(self, idx, element)
    end)
end

-- ============================================================
-- Bar construction
-- ============================================================

local function buildHost()
    -- Force a sane default if saved bar config is missing or corrupted.
    WicksTotemsDB.bar = WicksTotemsDB.bar or {}
    local cfg = WicksTotemsDB.bar
    cfg.point = cfg.point or "CENTER"
    cfg.x = cfg.x or 0
    cfg.y = cfg.y or 200    -- positive y = above center, well clear of action bars

    local host = CreateFrame("Frame", "WicksTotemsBar", UIParent)
    -- MEDIUM strata: above action bars, below DIALOG/HIGH UI windows.
    host:SetFrameStrata("MEDIUM")
    host:SetFrameLevel(10)
    local barW = PADDING * 2 + ICON_SIZE * 4 + ICON_GAP * 3
    local barH = PADDING * 2 + ICON_SIZE
    host:SetSize(barW, barH)
    host:ClearAllPoints()
    host:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:SetClampedToScreen(true)
    host:RegisterForDrag("LeftButton")
    host:SetScript("OnDragStart", function(self)
        if WicksTotemsDB.bar.locked then return end
        self:StartMoving()
    end)
    host:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        WicksTotemsDB.bar.point = p
        WicksTotemsDB.bar.x = x
        WicksTotemsDB.bar.y = y
    end)

    NewTexture(host, "BACKGROUND", C_BG):SetAllPoints(host)
    AddBorder(host)
    AddCornerAccents(host, 6, 2)

    host:SetScale(cfg.scale or 1.0)
    return host
end

function TB:SetScale(s)
    if not self.host then return end
    s = math.max(0.5, math.min(2.5, tonumber(s) or 1.0))
    WicksTotemsDB.bar.scale = s
    self.host:SetScale(s)
end

-- ============================================================
-- Public state
-- ============================================================

local pendingRebuild = false

function TB:RefreshIcons()
    local preset = WT:GetActivePreset()
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    for _, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn and btn._icon then
            local twist = WicksTotemsCharDB.twist and WicksTotemsCharDB.twist[el]
            local twistOn = twist and twist.enabled and twist.totems and #twist.totems >= 2

            local name
            if twistOn then
                -- Show the NEXT-to-cast totem icon. /castsequence cycles
                -- A→B→A→B... so if A is dropped, B is next; if B is
                -- dropped, A is next; if nothing is dropped, A is next.
                local currentlyActive
                for _, info in pairs(active) do
                    if info.element == el then
                        currentlyActive = WT.StripTotemRank
                            and WT.StripTotemRank(info.name)
                            or info.name
                        break
                    end
                end
                if currentlyActive == twist.totems[1] then
                    name = twist.totems[2]
                elseif currentlyActive == twist.totems[2] then
                    name = twist.totems[1]
                else
                    name = twist.totems[1]
                end
            else
                name = preset and preset.totems and preset.totems[el]
            end

            if name and name ~= "" then
                local tex = GetSpellTexture and GetSpellTexture(name)
                if tex then
                    btn._icon:SetTexture(tex)
                    btn._icon:Show()
                    btn._empty:Hide()
                else
                    btn._icon:Hide()
                    btn._empty:Show()
                end
            else
                btn._icon:Hide()
                btn._empty:Show()
            end
        end
    end
end

local C_OOR_RED = { 0.95, 0.32, 0.32, 0.95 }

-- Per-element "was twist ready last tick" state, so we can play a one-time
-- ping when the refresh window first opens.
local twistWasReady = { fire = false, earth = false, water = false, air = false }

function TB:RefreshActive()
    -- Active glow + count badge per element from AffectedCount data.
    -- If RangeWarning marks the slot as out-of-range, glow tints red.
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    local oorBySlot = (WT.RangeWarning and WT.RangeWarning._oorState) or {}

    local infoByElement, oorByElement = {}, {}
    for slot, info in pairs(active) do
        infoByElement[info.element] = info
        if oorBySlot[slot] then oorByElement[info.element] = true end
    end

    for _, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn and btn._glow then
            local info = infoByElement[el]
            local twist = WicksTotemsCharDB.twist and WicksTotemsCharDB.twist[el]
            local twistOn = twist and twist.enabled and twist.totems and #twist.totems >= 2

            if info then
                local oor = oorByElement[el]
                local color = oor and C_OOR_RED or C_GREEN
                for _, t in ipairs(btn._glow) do
                    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
                    t:Show()
                end
                if info.range == "self" or info.range == "summon" or info.range == "enemy" then
                    btn._badge:SetText("")
                    btn._badgeBg:Hide()
                else
                    btn._badge:SetText(tostring(info.affected or 0))
                    btn._badgeBg:Show()
                end
                local remaining = (info.startTime or 0) + (info.duration or 0) - GetTime()
                if remaining > 60 then
                    btn._duration:SetText(("%dm"):format(math.floor(remaining / 60)))
                elseif remaining > 0 then
                    btn._duration:SetText(("%ds"):format(math.ceil(remaining)))
                else
                    btn._duration:SetText("")
                end

                -- Twist countdown + click-now cue.
                if twistOn then
                    local sinceCast = GetTime() - (info.startTime or 0)
                    local untilTwist = (twist.refresh or 10) - sinceCast
                    local nowReady = untilTwist <= 0

                    if nowReady and not twistWasReady[el] then
                        -- Just entered the refresh window — chime once.
                        PlaySound(SOUNDKIT and SOUNDKIT.UI_AUTOLOOT_COMPLETE or 798, "Master")
                    end
                    twistWasReady[el] = nowReady

                    if nowReady then
                        btn._twist:SetText("!")
                        btn._twist:SetTextColor(C_OOR_RED[1], C_OOR_RED[2], C_OOR_RED[3], 1)
                        btn._icon:SetVertexColor(1, 1, 1)        -- bright = click now
                    else
                        btn._twist:SetText(string.format("%d", math.ceil(untilTwist)))
                        btn._twist:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
                        btn._icon:SetVertexColor(0.55, 0.55, 0.55)  -- dim = wait
                    end
                else
                    btn._twist:SetText("")
                    btn._icon:SetVertexColor(1, 1, 1)
                    twistWasReady[el] = false
                end
            else
                for _, t in ipairs(btn._glow) do t:Hide() end
                btn._badge:SetText("")
                btn._badgeBg:Hide()
                btn._duration:SetText("")
                btn._twist:SetText("")
                btn._icon:SetVertexColor(1, 1, 1)
                twistWasReady[el] = false
            end
        end
    end
end

function TB:Rebuild()
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local preset = WT:GetActivePreset()

    -- Set both macrotext AND macrotext1 — different TBC client builds
    -- read different attribute names when type1 is set; covering both
    -- works on every variant.
    if self.dropAll then
        self.dropAll:SetAttribute("type1", "macro")
        self.dropAll:SetAttribute("macrotext",  buildPresetMacro(preset))
        self.dropAll:SetAttribute("macrotext1", buildPresetMacro(preset))
    end
    for _, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn then
            local m = buildElementMacro(preset, el)
            btn:SetAttribute("type1", "macro")
            btn:SetAttribute("macrotext",  m)
            btn:SetAttribute("macrotext1", m)
        end
    end

    self:RefreshIcons()
    self:RefreshActive()
end

-- ============================================================
-- Init / show / toggle
-- ============================================================

-- ============================================================
-- Ankh reagent box: small icon + count anchored to the bar's left
-- ============================================================
local ANKH_ITEM_ID = 17030    -- Ankh reagent for Reincarnation in TBC

local function buildAnkhBox(barHost)
    local size = math.floor(ICON_SIZE / 2) + 4   -- bumped up 2px on each side
    local box = CreateFrame("Button", "WicksTotemsAnkhBox", barHost)
    box:SetSize(size, size)
    box:SetPoint("RIGHT", barHost, "LEFT", -3, 2)

    -- Brand chrome
    NewTexture(box, "BACKGROUND", C_BG):SetAllPoints(box)
    local function edge(p1, p2, w, h)
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.85)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Resolve item icon. GetItemInfo may return nil on first session call;
    -- we re-attempt on BAG_UPDATE.
    local function resolveIcon()
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(ANKH_ITEM_ID)
        if tex then icon:SetTexture(tex)
        else icon:SetTexture("Interface\\Icons\\Spell_Shaman_Reincarnation") end
    end
    resolveIcon()
    box._icon = icon

    local count = box:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    count:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    count:SetText("")
    box._count = count

    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Ankh", C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        GameTooltip:AddLine("Reincarnation reagent", C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        local n = GetItemCount(ANKH_ITEM_ID) or 0
        GameTooltip:AddLine(("In bags: %d"):format(n), C_GREEN[1], C_GREEN[2], C_GREEN[3])
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Refresh count from bag contents
    local function refreshCount()
        resolveIcon()    -- re-resolve in case it was nil at first
        local n = GetItemCount(ANKH_ITEM_ID) or 0
        if n <= 0 then
            count:SetText("0")
            count:SetTextColor(0.95, 0.32, 0.32, 1)   -- red — no ankhs!
        else
            count:SetText(tostring(n))
            count:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
        end
    end
    refreshCount()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BAG_UPDATE")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function() refreshCount() end)

    return box
end

-- ============================================================
-- Weapon imbue boxes — MH + OH on the right side of the bar.
-- TBC weapon imbues (Windfury / Rockbiter / Flametongue / Frostbrand)
-- show as weapon enchants, not player auras. We tooltip-scan the
-- equipped weapon to detect the imbue name and pick an icon.
-- ============================================================

-- Hidden tooltip for scanning weapon enchant lines
local imbueScan = CreateFrame("GameTooltip", "WicksTotemsImbueScan", UIParent, "GameTooltipTemplate")
imbueScan:SetOwner(UIParent, "ANCHOR_NONE")

local IMBUE_KEYWORDS = {
    { match = "Windfury",    name = "Windfury",    icon = "Interface\\Icons\\Spell_Nature_Cyclone"      },
    { match = "Rockbiter",   name = "Rockbiter",   icon = "Interface\\Icons\\Spell_Nature_RockBiter"    },
    { match = "Flametongue", name = "Flametongue", icon = "Interface\\Icons\\Spell_Fire_FlameTongue"   },
    { match = "Frostbrand",  name = "Frostbrand",  icon = "Interface\\Icons\\Spell_Frost_FrostBrand"   },
    { match = "Earthliving", name = "Earthliving", icon = "Interface\\Icons\\Spell_Nature_GiftOfTheWaterspirit" },
}

-- Returns (name, icon) for the imbue on the given inventory slot, or nil.
-- slot: 16 = main hand, 17 = off hand. Reads tooltip lines and looks for
-- known imbue keywords.
local function detectImbue(slot)
    if not GetInventoryItemLink("player", slot) then return nil end
    imbueScan:ClearLines()
    imbueScan:SetInventoryItem("player", slot)
    for i = 1, imbueScan:NumLines() do
        local line = _G["WicksTotemsImbueScanTextLeft" .. i]
        local text = line and line:GetText() or nil
        if text then
            for _, k in ipairs(IMBUE_KEYWORDS) do
                if text:find(k.match) then
                    return k.name, k.icon
                end
            end
        end
    end
    return nil
end

local function buildImbueBox(barHost, label, anchorPoint)
    local size = math.floor(ICON_SIZE / 2) + 4   -- match ankh size
    local box = CreateFrame("Frame", "WicksTotemsImbueBox_" .. label, barHost)
    box:SetSize(size, size)
    -- Anchor target defaults to barHost; can be overridden via anchorPoint.relTo
    -- (e.g. OH anchors to MH so they stack vertically).
    local relFrame = anchorPoint.relTo or barHost
    box:SetPoint(anchorPoint.point, relFrame, anchorPoint.relPoint, anchorPoint.x, anchorPoint.y)

    -- Brand chrome (mirrors ankh box)
    NewTexture(box, "BACKGROUND", C_BG):SetAllPoints(box)
    local function edge(p1, p2, w, h)
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.85)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box._icon = icon

    -- MH/OH label in the top-left corner
    local lbl = box:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    lbl:SetPoint("TOPLEFT", 1, -1)
    lbl:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    lbl:SetText(label)

    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(label .. " imbue", C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        local name = self._currentImbue
        if name then
            GameTooltip:AddLine(name .. " Weapon", C_GREEN[1], C_GREEN[2], C_GREEN[3])
        else
            GameTooltip:AddLine("(no imbue)", C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        end
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return box
end

-- Refresh both imbue boxes by re-scanning slot 16 (MH) and 17 (OH).
function TB:RefreshImbues()
    if not self.imbueMH or not self.imbueOH then return end
    local function applyTo(box, slot)
        local name, icon = detectImbue(slot)
        box._currentImbue = name
        if icon then
            box._icon:SetTexture(icon)
            box._icon:SetVertexColor(1, 1, 1)
        else
            box._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            box._icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
    applyTo(self.imbueMH, 16)
    applyTo(self.imbueOH, 17)
    -- Hide OH box when not dual-wielding (no off-hand weapon equipped)
    if GetInventoryItemLink("player", 17) then
        self.imbueOH:Show()
    else
        self.imbueOH:Hide()
    end
end

function TB:RefreshBindLabels()
    for _, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn and btn._bindLbl then
            local key = GetBindingKey("CLICK WicksTotemsBar_" .. el:upper() .. ":LeftButton")
            btn._bindLbl:SetText(shortBind(key))
        end
    end
end

function TB:Init()
    if self.initialized then return end
    self.initialized = true

    WT:SeedDefaultPresets()

    local host = buildHost()
    self.host = host

    -- Drop-All: hidden secure button, keybind only
    self.dropAll = makeSecureButton("WicksTotemsBar_DropAll", host, false)

    -- Per-element: visible icon buttons, click + keybind
    for i, el in ipairs(elements()) do
        local b = makeSecureButton("WicksTotemsBar_" .. el:upper(), host, true)
        b:SetPoint("TOPLEFT", host, "TOPLEFT",
            PADDING + (i - 1) * (ICON_SIZE + ICON_GAP),
            -PADDING)
        styleIconButton(b, el)
        self["btn_" .. el] = b
    end

    self.ankhBox = buildAnkhBox(host)

    -- Weapon imbue boxes on the right side of the bar (opposite the ankh).
    -- Stacked vertically: MH on top, OH below.
    self.imbueMH = buildImbueBox(host, "MH",
        { point = "TOPLEFT", relPoint = "TOPRIGHT", x = 3, y = 0 })
    self.imbueOH = buildImbueBox(host, "OH",
        { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -2,
          relTo = self.imbueMH })

    -- Refresh imbue display on equipment swap / load
    local imbueWatcher = CreateFrame("Frame")
    imbueWatcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
    imbueWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    imbueWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    imbueWatcher:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        TB:RefreshImbues()
    end)
    TB:RefreshImbues()

    self:Rebuild()
    self:RefreshBindLabels()

    -- Re-render keybind labels when the user changes bindings
    local bf = CreateFrame("Frame")
    bf:RegisterEvent("UPDATE_BINDINGS")
    bf:SetScript("OnEvent", function() self:RefreshBindLabels() end)

    if WicksTotemsDB.bar.hidden then
        host:Hide()
    else
        host:Show()
        host:Raise()
    end

    WT:On("COMBAT_END",      function() if pendingRebuild then TB:Rebuild() end end)
    -- PRESET_CHANGED can imply a different per-preset elementOrder, so
    -- relayout (which itself calls Rebuild) instead of just rebuilding macros.
    WT:On("PRESET_CHANGED",  function() TB:RelayoutForOrder() end)
    -- Refresh icons too on every totem change so the twist icon flips
    -- to show the next-to-cast totem after each press.
    WT:On("AFFECTED_UPDATED", function() TB:RefreshIcons(); TB:RefreshActive() end)
end

-- Reset the bar to its default position (use when "I lost the bar somewhere")
function TB:ResetPosition()
    WicksTotemsDB.bar.point = "CENTER"
    WicksTotemsDB.bar.x = 0
    WicksTotemsDB.bar.y = 200
    WicksTotemsDB.bar.hidden = false
    if self.host then
        self.host:ClearAllPoints()
        self.host:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        self.host:Show()
        self.host:Raise()
    end
end

-- Diagnostic: print state to chat
function TB:Status()
    local function tag(b) return b and "yes" or "no" end
    print("|cff4FC778Wick's Totems status|r")
    print("  initialized: " .. tag(self.initialized))
    if self.host then
        local p, _, _, x, y = self.host:GetPoint()
        print(("  bar shown: %s  point: %s  x: %d  y: %d"):format(
            tag(self.host:IsShown()), tostring(p), x or 0, y or 0))
    else
        print("  bar host: nil (init failed)")
    end
    local preset, idx = WT:GetActivePreset()
    if preset then
        print(("  active preset: [%d] %s"):format(idx, preset.name or "?"))
        for _, el in ipairs(elements()) do
            local n = preset.totems and preset.totems[el]
            print(("    %s: %s"):format(el, n or "(empty)"))
        end
    else
        print("  active preset: nil")
    end
    if self.dropAll then
        local mt = self.dropAll:GetAttribute("macrotext") or ""
        print("  dropAll macrotext (first line): " .. (mt:match("[^\n]+") or "(empty)"))
    end
    print(("  in combat: %s  pending rebuild: %s"):format(tag(InCombatLockdown()), tag(pendingRebuild)))
end

-- Re-anchor element icons after WicksTotemsDB.elementOrder changes.
-- Secure-frame anchor edits are combat-locked; defer if in combat.
function TB:RelayoutForOrder()
    if not self.host then return end
    if InCombatLockdown() then
        self._relayoutPending = true
        return
    end
    self._relayoutPending = false
    for i, el in ipairs(elements()) do
        local btn = self["btn_" .. el]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", self.host, "TOPLEFT",
                PADDING + (i - 1) * (ICON_SIZE + ICON_GAP),
                -PADDING)
        end
    end
    self:Rebuild()  -- rebuilds macros so /castsequence drops in the new order
end

WT:On("ELEMENT_ORDER_CHANGED", function() TB:RelayoutForOrder() end)
WT:On("COMBAT_END", function()
    if TB._relayoutPending then TB:RelayoutForOrder() end
end)

function TB:Show()
    if not self.host then return end
    self.host:Show()
    WicksTotemsDB.bar.hidden = false
end

function TB:Hide()
    if not self.host then return end
    self.host:Hide()
    WicksTotemsDB.bar.hidden = true
end

function TB:Toggle()
    if not self.host then return end
    if self.host:IsShown() then self:Hide() else self:Show() end
end

function TB:Lock(flag)
    WicksTotemsDB.bar.locked = flag and true or false
end

function TB:SetBinding(key, element)
    if not key or key == "" then return false, "no key" end
    if InCombatLockdown() then return false, "in combat" end
    local btn = element and self["btn_" .. element] or self.dropAll
    if not btn then return false, "no button" end
    SetBindingClick(key, btn:GetName())
    SaveBindings(GetCurrentBindingSet())
    return true
end

WT:On("LOGIN", function() TB:Init() end)
