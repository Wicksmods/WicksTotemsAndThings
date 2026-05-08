-- Wick's Totems and Things
-- ProcAlerts.lua: per-proc draggable floater frames.
--
-- Each kind=proc and kind=flash entry from WT.TRACKED becomes its own
-- 44x44 framed icon button. Hidden when the proc is inactive; shown
-- (with autocast shine for procs) when the trigger fires.
--
-- Positions persist per-account in WicksTotemsDB.procs[short]. Default
-- layout is a 4-column grid below center on first run.
--
-- An "edit mode" toggle in Options forces all floaters visible (greyed
-- out) so the user can drag them into position without waiting for
-- procs to fire.

local ADDON, ns = ...
local WT = WicksTotems

WT.ProcAlerts = {}
local PA = WT.ProcAlerts

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local FRAME_SIZE = 44
local ICON_SIZE  = 36

PA.floaters    = {}  -- short -> currently-visible floater frame
PA.entries     = {}  -- visible entries for current spec/talent set
PA.editMode    = false
PA._allFrames  = {}  -- short -> floater frame (lifetime: addon load) — pool

-- ============================================================
-- Brand chrome helpers (mirrors CooldownTracker)
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
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function AddCornerAccents(frame, arm, thick)
    arm = arm or 6; thick = thick or 2
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
-- Saved-vars helpers
-- ============================================================
local function cfg()
    WicksTotemsDB.procs = WicksTotemsDB.procs or { editMode = false, perProc = {} }
    WicksTotemsDB.procs.perProc     = WicksTotemsDB.procs.perProc     or {}
    WicksTotemsDB.procs.scale       = WicksTotemsDB.procs.scale       or 1.0
    WicksTotemsDB.procs.shieldScale = WicksTotemsDB.procs.shieldScale or 1.0
    return WicksTotemsDB.procs
end

-- Returns the global scale factor for a given entry's category.
-- "shield" → cfg.shieldScale, anything else → cfg.scale.
local function categoryScale(entry)
    if entry and entry.category == "shield" then
        return cfg().shieldScale or 1.0
    end
    return cfg().scale or 1.0
end

-- Default position for the i-th visible floater. 4-column grid below
-- center, 50px between cells.
local function defaultPosition(i)
    local col = (i - 1) % 4
    local row = math.floor((i - 1) / 4)
    return "CENTER", (col - 1.5) * 50, -100 - row * 50
end

local function entryConfig(short, defaultIndex)
    local c = cfg()
    c.perProc[short] = c.perProc[short] or {}
    local pc = c.perProc[short]
    if not pc.point then
        local p, x, y = defaultPosition(defaultIndex or 1)
        pc.point = p; pc.x = x; pc.y = y
    end
    pc.scale = pc.scale or 1.0
    return pc
end

-- ============================================================
-- Floater construction
-- ============================================================
local function buildFloater(entry, defaultIndex)
    local pc = entryConfig(entry.short, defaultIndex)

    local f = CreateFrame("Frame", "WicksTotemsProc_" .. (entry.short or "X"), UIParent)
    f:SetSize(FRAME_SIZE, FRAME_SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(15)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetPoint(pc.point, UIParent, pc.point, pc.x, pc.y)
    -- Final scale = category-global * per-entry. Shields use cfg.shieldScale,
    -- procs use cfg.scale. Per-entry adjustment multiplies on top.
    f:SetScale(categoryScale(entry) * (pc.scale or 1.0))
    f:Hide()

    f:SetScript("OnDragStart", function(self)
        if cfg().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        pc.point, pc.x, pc.y = p, x, y
    end)

    -- Brand chrome
    NewTexture(f, "BACKGROUND", C_BG):SetAllPoints(f)
    AddBorder(f)
    AddCornerAccents(f, 5, 2)

    -- Icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local tex
    if entry.spell then tex = GetSpellTexture and GetSpellTexture(entry.spell) end
    if not tex and entry.aura then tex = GetSpellTexture and GetSpellTexture(entry.aura) end
    if not tex and entry.icon then tex = entry.icon end
    if tex then icon:SetTexture(tex) else icon:SetColorTexture(0.1, 0.1, 0.15, 1) end
    f._icon = icon

    -- Autocast shine for proc-kind (swirl on activation)
    if entry.kind == "proc" or entry.kind == "flash" then
        local ok, shine = pcall(CreateFrame, "Frame", nil, f, "AutoCastShineTemplate")
        if ok and shine then
            shine:SetAllPoints(f)
            shine:Hide()
            f._shine = shine
        end
    end

    -- Stack count text (bottom-right)
    local stack = f:CreateFontString(nil, "OVERLAY")
    stack:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    stack:SetPoint("BOTTOMRIGHT", -3, 2)
    stack:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    stack:SetText("")
    f._stack = stack

    -- "Missing" pulse animation: alpha 0.25 <-> 0.55, looping. Used by
    -- entries with flashWhenMissing=true (the shields) to remind the
    -- shaman to refresh a dropped buff.
    local missPulse = f:CreateAnimationGroup()
    missPulse:SetLooping("REPEAT")
    local fadeOut = missPulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.55); fadeOut:SetToAlpha(0.25); fadeOut:SetDuration(0.7); fadeOut:SetOrder(1)
    local fadeIn  = missPulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.25); fadeIn:SetToAlpha(0.55); fadeIn:SetDuration(0.7); fadeIn:SetOrder(2)
    f._missPulse = missPulse

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        local title = entry.displayName or entry.spell or entry.aura
                   or entry.spellName or entry.short or "?"
        GameTooltip:AddLine(title, C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        GameTooltip:AddLine(entry.kind == "flash" and "Weapon proc" or "Proc tracker",
            C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        if PA.editMode then
            GameTooltip:AddLine("Drag to reposition", C_GREEN[1], C_GREEN[2], C_GREEN[3])
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f._entry = entry
    f._flashUntil = 0
    return f
end

-- ============================================================
-- Show/hide a floater based on its proc state
-- ============================================================
local function setShine(f, on)
    if not f._shine then return end
    if on and not f._shineActive then
        f._shine:Show()
        if AutoCastShine_AutoCastStart then pcall(AutoCastShine_AutoCastStart, f._shine) end
        f._shineActive = true
    elseif not on then
        if AutoCastShine_AutoCastStop then pcall(AutoCastShine_AutoCastStop, f._shine) end
        f._shine:Hide()
        f._shineActive = false
    end
end

local function stopMissPulse(f)
    if f._missPulseActive and f._missPulse then
        f._missPulse:Stop()
        f._missPulseActive = false
        f:SetAlpha(1)
    end
end

local function startMissPulse(f)
    if f._missPulseActive then return end
    if not f._missPulse then return end
    f._missPulse:Play()
    f._missPulseActive = true
end

local function refreshFloater(f)
    local e = f._entry
    if not e then return end
    local now = GetTime()

    -- Edit mode: show all floaters dimmed for positioning
    if PA.editMode then
        stopMissPulse(f)
        f:Show()
        f:SetAlpha(0.55)
        f._stack:SetText(e.short or "")
        setShine(f, false)
        return
    end

    -- Aura state (proc kind)
    local auraName, count, expirationTime
    if e.aura then
        auraName, count, expirationTime = WT.TrackerFindAura(e.unit or "player", e.aura, e.harmful)
        if not auraName and e.auraAlt then
            auraName, count, expirationTime = WT.TrackerFindAura(e.unit or "player", e.auraAlt, e.harmful)
        end
    end

    -- Flash state (combat-log driven)
    local flashing = false
    if e.kind == "flash" and f._flashUntil > now then
        flashing = true
    end

    if auraName or flashing then
        -- Buff active: full bright + shine + stack/duration
        stopMissPulse(f)
        f:Show()
        f:SetAlpha(1)
        setShine(f, true)
        if auraName and count and count > 1 then
            f._stack:SetText(tostring(count))
        elseif auraName and expirationTime and expirationTime > 0 then
            local r = expirationTime - now
            if r > 60 then f._stack:SetText(("%dm"):format(math.floor(r / 60)))
            elseif r > 0 then f._stack:SetText(("%d"):format(math.ceil(r)))
            else f._stack:SetText("") end
        else
            f._stack:SetText("")
        end
    elseif e.flashWhenMissing then
        -- Buff missing but the shaman should refresh it: subtle pulse
        -- between 25% and 55% alpha. No shine, no stack count.
        setShine(f, false)
        f._stack:SetText("")
        f:Show()
        startMissPulse(f)
    else
        -- Inactive proc: fully hide
        stopMissPulse(f)
        setShine(f, false)
        f._stack:SetText("")
        f:Hide()
    end
end

function PA:Refresh()
    for _, f in pairs(self.floaters) do
        refreshFloater(f)
    end
end

-- ============================================================
-- Init
-- ============================================================
function PA:Init()
    if self.initialized then return end
    if not WT.isShaman then return end
    self.initialized = true

    self.editMode = cfg().editMode and true or false

    local activeSpec = WT.GetActiveSpec and WT.GetActiveSpec() or nil
    local talentRank = WT.TalentRank or function() return 0 end
    local visibleIndex = 0
    for _, e in ipairs(WT.TRACKED or {}) do
        if e.kind == "proc" or e.kind == "flash" then
            -- Filter precedence: talent (per-ability) > spec > always-allowed
            local allowed
            if e.talent then
                allowed = talentRank(e.talent) > 0
            elseif e.spec then
                allowed = (e.spec == activeSpec)
            else
                allowed = true
            end
            if allowed then
                visibleIndex = visibleIndex + 1
                self.entries[#self.entries + 1] = e
                -- Reuse from pool if already built (Init might be re-run after
                -- Rebuild fired pre-Init; without pooling we'd duplicate).
                local f = self._allFrames[e.short] or buildFloater(e, visibleIndex)
                self._allFrames[e.short] = f
                self.floaters[e.short] = f
            end
        end
    end

    -- Polling for proc duration tick
    if not self.poll then
        local f = CreateFrame("Frame")
        self.poll = f
        local accum = 0
        f:SetScript("OnUpdate", function(_, elapsed)
            accum = accum + elapsed
            if accum < 0.25 then return end
            accum = 0
            PA:Refresh()
        end)
    end

    -- Event-driven refresh
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_TARGET_CHANGED")
    ef:RegisterUnitEvent("UNIT_AURA", "player")
    ef:RegisterUnitEvent("UNIT_AURA", "target")
    ef:SetScript("OnEvent", function() PA:Refresh() end)

    -- Combat log: flash entries
    local cl = CreateFrame("Frame")
    cl:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    cl:SetScript("OnEvent", function()
        local _, _, _, srcGUID, _, _, _, _, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()
        if srcGUID ~= UnitGUID("player") then return end
        if not spellName then return end
        for _, e in ipairs(self.entries) do
            if e.kind == "flash" and e.spellName == spellName then
                local f = self.floaters[e.short]
                if f then f._flashUntil = GetTime() + (e.flashDuration or 1.5) end
            end
        end
    end)

    self:Refresh()
end

function PA:SetEditMode(on)
    self.editMode = on and true or false
    cfg().editMode = self.editMode
    self:Refresh()
end

-- Per-category global scale. category="shield" writes shieldScale and only
-- rescales shield floaters; default writes scale and rescales the rest.
function PA:SetScale(s, category)
    s = math.max(0.5, math.min(2.5, tonumber(s) or 1.0))
    if category == "shield" then
        cfg().shieldScale = s
    else
        cfg().scale = s
    end
    for _, f in pairs(self.floaters) do
        local e = f._entry
        if e then
            local fcat = e.category or "proc"
            -- Only rescale floaters whose category matches what we just changed
            if (category == "shield" and fcat == "shield")
               or (category ~= "shield" and fcat ~= "shield") then
                local short = e.short
                local pc = short and cfg().perProc and cfg().perProc[short] or nil
                local perEntry = (pc and pc.scale) or 1.0
                f:SetScale(categoryScale(e) * perEntry)
            end
        end
    end
end

function PA:ResetPositions()
    cfg().perProc = {}
    -- Re-anchor each existing floater to its default-grid slot
    for i, e in ipairs(self.entries) do
        local f = self.floaters[e.short]
        if f then
            local p, x, y = defaultPosition(i)
            local pc = entryConfig(e.short, i)
            pc.point, pc.x, pc.y = p, x, y
            f:ClearAllPoints()
            f:SetPoint(p, UIParent, p, x, y)
        end
    end
    self:Refresh()
end

-- Re-filter floaters by current talents/spec. Reuses existing floater
-- frames from the pool (no destroy / re-create) so we never orphan a
-- frame that might still be rendering.
function PA:Rebuild()
    if not self.initialized then
        -- Init handles the initial filter — defer to it.
        self:Init()
        return
    end
    if InCombatLockdown() then
        self._rebuildPending = true
        return
    end

    self.floaters = {}
    self.entries  = {}

    local activeSpec = WT.GetActiveSpec and WT.GetActiveSpec() or nil
    local talentRank = WT.TalentRank or function() return 0 end
    local visibleIndex = 0
    for _, e in ipairs(WT.TRACKED or {}) do
        if e.kind == "proc" or e.kind == "flash" then
            local allowed
            if e.talent then
                allowed = talentRank(e.talent) > 0
            elseif e.spec then
                allowed = (e.spec == activeSpec)
            else
                allowed = true
            end
            if allowed then
                visibleIndex = visibleIndex + 1
                self.entries[#self.entries + 1] = e
                local f = self._allFrames[e.short] or buildFloater(e, visibleIndex)
                self._allFrames[e.short] = f
                self.floaters[e.short] = f
            end
        end
    end

    -- Hide any pool frames that aren't in the new visible set
    for short, f in pairs(self._allFrames) do
        if not self.floaters[short] then
            if f._missPulse then f._missPulse:Stop() end
            f:Hide()
        end
    end

    self:Refresh()
end

-- PLAYER_TALENT_UPDATE rebuild
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
talentFrame:SetScript("OnEvent", function() PA:Rebuild() end)

-- Out-of-combat hook: flush queued rebuild
WT:On("COMBAT_END", function()
    if PA._rebuildPending then
        PA._rebuildPending = false
        PA:Rebuild()
    end
end)

WT:On("LOGIN", function() PA:Init() end)
