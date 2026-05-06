-- Wick's Totems and Things
-- SwingTimer.lua: main-hand and (when dual-wielding) off-hand swing
-- progress bars. Useful for enhancement shamans timing Stormstrike,
-- Maelstrom Weapon stack management, and Windfury procs.
--
-- Detection: COMBAT_LOG_EVENT_UNFILTERED for SWING_* subevents from the
-- player. Swing duration via UnitAttackSpeed on equipment changes.
--
-- The bars only render while in combat (lighter on idle CPU + screen
-- clutter); they fade out 4s after combat ends.

local ADDON, ns = ...
local WT = WicksTotems

WT.SwingTimer = {}
local SW = WT.SwingTimer

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_OH_BLUE     = { 0.45,  0.65,  0.95,  1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local BAR_W   = 220
local BAR_H   = 12
local BAR_GAP = 2
local PADDING = 4

SW._mh = { lastSwing = 0, duration = 0 }
SW._oh = { lastSwing = 0, duration = 0 }
SW._inCombat = false
SW._fadeAt   = 0

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

-- ============================================================
-- Frame construction
-- ============================================================
local function buildBar(host, color, label, top)
    local b = CreateFrame("StatusBar", nil, host)
    b:SetSize(BAR_W - PADDING * 2, BAR_H)
    b:SetPoint("TOPLEFT", host, "TOPLEFT", PADDING, top)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b:SetStatusBarColor(color[1], color[2], color[3], 0.92)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)

    local bg = NewTexture(b, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetAllPoints(b)

    local lbl = b:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    lbl:SetPoint("LEFT", 4, 0)
    lbl:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1)
    lbl:SetText(label)

    local timeText = b:CreateFontString(nil, "OVERLAY")
    timeText:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    timeText:SetPoint("RIGHT", -4, 0)
    timeText:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    timeText:SetText("")
    b._timeText = timeText

    return b
end

local function buildHost()
    WicksTotemsDB.swing = WicksTotemsDB.swing or {}
    local cfg = WicksTotemsDB.swing
    cfg.point = cfg.point or "CENTER"
    cfg.x = cfg.x or 0
    cfg.y = cfg.y or 100
    if cfg.hidden == nil then cfg.hidden = false end

    local host = CreateFrame("Frame", "WicksTotemsSwingBar", UIParent)
    host:SetFrameStrata("MEDIUM")
    host:SetSize(BAR_W, PADDING * 2 + BAR_H * 2 + BAR_GAP)
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

    -- MH bar (top), OH bar (below)
    SW.mhBar = buildBar(host, C_GREEN, "MH", -PADDING)
    SW.ohBar = buildBar(host, C_OH_BLUE, "OH", -PADDING - BAR_H - BAR_GAP)

    return host, cfg
end

-- ============================================================
-- Swing-time refresh from equipment
-- ============================================================
local function refreshSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    SW._mh.duration = mh or 0
    SW._oh.duration = oh or 0
    -- Hide OH bar if no off-hand weapon
    if SW.ohBar then
        if (oh and oh > 0) then
            SW.ohBar:Show()
            -- Slide host height to two bars
            if SW.host then SW.host:SetHeight(PADDING * 2 + BAR_H * 2 + BAR_GAP) end
        else
            SW.ohBar:Hide()
            if SW.host then SW.host:SetHeight(PADDING * 2 + BAR_H) end
        end
    end
end

-- ============================================================
-- OnUpdate: drive bar fill + auto-fade out of combat
-- ============================================================
local function onUpdate(self, elapsed)
    local now = GetTime()
    local function setBar(bar, info)
        if not bar then return end
        if info.duration <= 0 then
            bar:SetValue(0); bar._timeText:SetText("")
            return
        end
        local since = now - info.lastSwing
        local remaining = info.duration - since
        if remaining < 0 then remaining = 0 end
        local pct = 0
        if info.duration > 0 then pct = math.min(1, since / info.duration) end
        bar:SetValue(pct)
        if remaining > 0 then
            bar._timeText:SetText(string.format("%.1fs", remaining))
        else
            bar._timeText:SetText("ready")
        end
    end
    setBar(SW.mhBar, SW._mh)
    setBar(SW.ohBar, SW._oh)

    if not SW._inCombat and SW._fadeAt > 0 and now > SW._fadeAt then
        if SW.host then SW.host:Hide() end
        SW._fadeAt = 0
    end
end

-- ============================================================
-- Init
-- ============================================================
function SW:Init()
    if self.initialized then return end
    self.initialized = true

    local host, cfg = buildHost()
    self.host = host
    self.cfg = cfg

    refreshSpeeds()
    if cfg.hidden then host:Hide() end

    -- Combat log hook for swing detection
    local cl = CreateFrame("Frame")
    cl:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    cl:RegisterEvent("UNIT_ATTACK_SPEED")
    cl:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    cl:RegisterEvent("PLAYER_REGEN_DISABLED")
    cl:RegisterEvent("PLAYER_REGEN_ENABLED")
    cl:RegisterEvent("PLAYER_ENTER_COMBAT")
    cl:RegisterEvent("PLAYER_LEAVE_COMBAT")

    cl:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- TBC 2.5.5 passes combat-log args via the global function
            local _, subevent, _, srcGUID, _, srcFlags = CombatLogGetCurrentEventInfo()
            if srcGUID ~= UnitGUID("player") then return end
            if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
                local now = GetTime()
                -- We don't have a reliable way to distinguish MH vs OH
                -- swings in TBC's combat log. Heuristic: whichever bar
                -- is closer to its full duration gets the swing reset.
                local mhSince = now - SW._mh.lastSwing
                local ohSince = now - SW._oh.lastSwing
                if SW._oh.duration > 0 and ohSince > mhSince then
                    SW._oh.lastSwing = now
                else
                    SW._mh.lastSwing = now
                end
            end
        elseif event == "UNIT_ATTACK_SPEED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            refreshSpeeds()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTER_COMBAT" then
            SW._inCombat = true
            SW._fadeAt = 0
            if not cfg.hidden and SW.host then SW.host:Show() end
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LEAVE_COMBAT" then
            SW._inCombat = false
            SW._fadeAt = GetTime() + 4
        end
    end)

    -- Drive the bars
    local upd = CreateFrame("Frame")
    upd:SetScript("OnUpdate", onUpdate)
end

function SW:Show()
    if not self.host then return end
    self.host:Show()
    self.cfg.hidden = false
end
function SW:Hide()
    if not self.host then return end
    self.host:Hide()
    self.cfg.hidden = true
end
function SW:Toggle()
    if not self.host then return end
    if self.host:IsShown() then self:Hide() else self:Show() end
end
function SW:ResetPosition()
    if not self.cfg or not self.host then return end
    self.cfg.point = "CENTER"
    self.cfg.x = 0; self.cfg.y = 100
    self.host:ClearAllPoints()
    self.host:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    self.host:Show()
    self.cfg.hidden = false
end

WT:On("LOGIN", function() SW:Init() end)
