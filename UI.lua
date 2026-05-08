-- Wick's Totems and Things
-- UI.lua: brand-styled main panel.

local ADDON, ns = ...
local WT = WicksTotems

WT.UI = {}
local UI = WT.UI

-- ============================================================
-- Wick brand palette (mirror of sibling addons — do not drift)
-- ============================================================
local C_BG          = { 0.051, 0.039, 0.078, 0.97 }
local C_HEADER_BG   = { 0.090, 0.067, 0.141, 1 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_ROW_HOVER   = { 0.310, 0.780, 0.471, 0.06 }

local PANEL_W = 520
local PANEL_H = 420
local TITLE_H = 28
local TAB_H   = 24
local PADDING = 10

local ELEMENT_LABEL = {
    fire  = "Fire",
    earth = "Earth",
    water = "Water",
    air   = "Air",
}
local ELEMENT_TINT = {
    fire  = { 0.95, 0.55, 0.30 },
    earth = { 0.55, 0.75, 0.45 },
    water = { 0.45, 0.65, 0.95 },
    air   = { 0.85, 0.85, 0.95 },
}
local ELEMENT_ORDER = { "fire", "earth", "water", "air" }

-- ============================================================
-- Brand helpers
-- ============================================================
local function SetRGBA(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function NewTexture(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then SetRGBA(t, c) end
    return t
end

local function NewText(parent, size, c)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont("Fonts\\FRIZQT__.TTF", (size or 11) + 1, "")
    if c then f:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    return f
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

local function AddCornerAccents(frame)
    local arm, thick = 10, 2
    local g = C_GREEN
    local function brk(anchor, sx, sy, hArm, vArm)
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(g[1], g[2], g[3], 1)
        h:SetPoint(anchor, sx, sy); h:SetSize(hArm, thick)
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(g[1], g[2], g[3], 1)
        v:SetPoint(anchor, sx, sy); v:SetSize(thick, vArm)
    end
    brk("TOPLEFT",     0,  0, arm, arm)
    brk("TOPRIGHT",    0,  0, arm, arm)
    brk("BOTTOMLEFT",  0,  0, arm, arm)
    brk("BOTTOMRIGHT", 0,  0, arm, arm)
end

local function fmtDuration(remaining)
    if not remaining or remaining <= 0 then return "" end
    if remaining >= 60 then
        return string.format("%dm", math.floor(remaining / 60))
    end
    return string.format("%ds", math.ceil(remaining))
end

-- ============================================================
-- Frame construction
-- ============================================================

local function buildTitleBar(frame)
    -- Canonical Wick title bar (slim spec): 28h, two-tone "Wick's <name>",
    -- × glyph close button. Inset by 1px so the panel border shows through.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetHeight(TITLE_H)
    bar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    NewTexture(bar, "BACKGROUND", C_HEADER_BG):SetAllPoints(bar)

    -- 1px bottom divider (no fel-green underline)
    local div = NewTexture(bar, "BORDER", C_BORDER)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT")
    div:SetHeight(1)

    -- Two-tone title: "Wick's" in fel-green, rest in cream
    local tApo = NewText(bar, 12, C_GREEN)
    tApo:SetPoint("LEFT", bar, "LEFT", 10, 0)
    tApo:SetText("Wick's")

    local tName = NewText(bar, 12, C_TEXT_NORMAL)
    tName:SetPoint("LEFT", tApo, "RIGHT", 4, 0)
    tName:SetText("Totems and Things")

    -- Whole-frame drag (per slim spec; not header-only)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        WicksTotemsDB.point = p
        WicksTotemsDB.x, WicksTotemsDB.y = x, y
    end)

    -- × close button (U+00D7 — NOT U+2715 which is tofu in FRIZQT__)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, TITLE_H)
    close:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    local closeX = close:CreateFontString(nil, "OVERLAY")
    closeX:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    closeX:SetPoint("CENTER")
    closeX:SetText("×")
    closeX:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1)
    close:SetScript("OnEnter", function() closeX:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() closeX:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1) end)
    close:SetScript("OnClick", function() UI:Hide() end)

    return bar
end

local function buildTabs(frame)
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetHeight(TAB_H)
    strip:SetPoint("TOPLEFT", 0, -TITLE_H)
    strip:SetPoint("TOPRIGHT", 0, -TITLE_H)
    local bg = NewTexture(strip, "BACKGROUND", C_HEADER_BG)
    bg:SetAllPoints(strip)
    local div = NewTexture(strip, "BORDER", C_BORDER)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT")
    div:SetHeight(1)

    local tabs = {
        { id = "active",   label = "Active" },
        { id = "presets",  label = "Presets" },
        { id = "bindings", label = "Bindings" },
        { id = "options",  label = "Options" },
    }
    UI._tabs = {}
    local x = 8
    for _, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(80, TAB_H)
        btn:SetPoint("LEFT", x, 0)
        local lbl = NewText(btn, 11, C_TEXT_DIM)
        lbl:SetPoint("CENTER")
        lbl:SetText(t.label)
        local underline = NewTexture(btn, "OVERLAY", C_GREEN)
        underline:SetPoint("BOTTOMLEFT", 8, 0)
        underline:SetPoint("BOTTOMRIGHT", -8, 0)
        underline:SetHeight(2)
        underline:Hide()
        btn._lbl = lbl
        btn._underline = underline
        btn._id = t.id
        btn:SetScript("OnEnter", function() if UI._activeTab ~= t.id then lbl:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3]) end end)
        btn:SetScript("OnLeave", function() if UI._activeTab ~= t.id then lbl:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3]) end end)
        btn:SetScript("OnClick", function() UI:SelectTab(t.id) end)
        UI._tabs[t.id] = btn
        x = x + 84
    end
    return strip
end

-- ============================================================
-- Active tab: live totem state with affected counts
-- ============================================================
local function buildActivePane(parent)
    -- parent IS the pane (pre-created by UI:Build). Treat it as our pane.
    local pane = parent

    -- 4 cards stacked vertically, one per element slot
    local cards = {}
    local cardH = 60
    for i, el in ipairs(ELEMENT_ORDER) do
        local card = CreateFrame("Frame", nil, pane)
        card:SetHeight(cardH)
        card:SetPoint("TOPLEFT",  PADDING, -(i - 1) * (cardH + 4) - PADDING)
        card:SetPoint("TOPRIGHT", -PADDING, -(i - 1) * (cardH + 4) - PADDING)

        local bg = NewTexture(card, "BACKGROUND", C_HEADER_BG)
        bg:SetAllPoints(card)
        AddBorder(card)

        -- left color band
        local band = NewTexture(card, "ARTWORK")
        local tint = ELEMENT_TINT[el]
        band:SetColorTexture(tint[1], tint[2], tint[3], 0.85)
        band:SetPoint("TOPLEFT");   band:SetPoint("BOTTOMLEFT")
        band:SetWidth(3)

        local elLabel = NewText(card, 10, C_TEXT_DIM)
        elLabel:SetPoint("TOPLEFT", 14, -8)
        elLabel:SetText(ELEMENT_LABEL[el]:upper())

        local nameText = NewText(card, 13, C_TEXT_NORMAL)
        nameText:SetPoint("TOPLEFT", 14, -22)
        nameText:SetText("(none)")

        local timer = NewText(card, 10, C_TEXT_DIM)
        timer:SetPoint("BOTTOMLEFT", 14, 8)

        local countNum = NewText(card, 22, C_GREEN)
        countNum:SetPoint("RIGHT", -16, 6)
        countNum:SetText("0")

        local countLabel = NewText(card, 9, C_TEXT_DIM)
        countLabel:SetPoint("RIGHT", -16, -12)
        countLabel:SetText("affected")

        cards[el] = {
            frame = card, name = nameText, timer = timer,
            count = countNum, countLabel = countLabel,
        }
    end
    UI._activeCards = cards
end

local function refreshActivePane()
    if not UI._activeCards then return end
    local active = WT.AffectedCount and WT.AffectedCount.active or {}
    -- index active by element rather than slot for direct lookup
    local byElement = {}
    for slot, info in pairs(active) do
        byElement[info.element] = info
    end
    for _, el in ipairs(ELEMENT_ORDER) do
        local card = UI._activeCards[el]
        local info = byElement[el]
        if info then
            card.name:SetText(info.name)
            card.name:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
            local remaining = (info.startTime or 0) + (info.duration or 0) - GetTime()
            card.timer:SetText(fmtDuration(remaining))
            if info.range == "self" or info.range == "summon" then
                card.count:SetText("-")
                card.countLabel:SetText("self")
            elseif info.range == "enemy" then
                card.count:SetText("-")
                card.countLabel:SetText("enemy")
            else
                card.count:SetText(tostring(info.affected or 0))
                card.countLabel:SetText("in range")
            end
        else
            card.name:SetText("(none)")
            card.name:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
            card.timer:SetText("")
            card.count:SetText("0")
            card.countLabel:SetText("")
        end
    end
end

-- ============================================================
-- Presets tab: editable list (rename, delete, change totems, add)
-- ============================================================

-- Picker popup: shared, anchored to whichever element pill opened it.
local function ensurePicker()
    if UI._picker then return UI._picker end
    local p = CreateFrame("Frame", "WicksTotemsPicker", UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetSize(220, 200)
    p:Hide()
    p:EnableMouse(true)
    NewTexture(p, "BACKGROUND", C_BG):SetAllPoints(p)
    AddBorder(p)
    AddCornerAccents(p)
    p._rows = {}

    -- Close X (so users always have a way out)
    local close = CreateFrame("Button", nil, p)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -2, -2)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    cx:SetPoint("CENTER")
    cx:SetText("×")
    cx:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1)
    close:SetScript("OnEnter", function() cx:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3]) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3]) end)
    close:SetScript("OnClick", function() p:Hide() end)
    p._closeBtn = close

    -- Best-effort outside-click dismissal via GLOBAL_MOUSE_DOWN (TBC 2.5.5 has it).
    -- Wrapped in pcall in case the event isn't available — close X always works.
    p:SetScript("OnHide", function()
        pcall(p.UnregisterEvent, p, "GLOBAL_MOUSE_DOWN")
    end)
    p:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" and not MouseIsOver(p) then p:Hide() end
    end)
    UI._picker = p
    return p
end

function UI:OpenPicker(anchorTo, presetIndex, element)
    local p = ensurePicker()
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)

    -- Wipe existing rows
    for _, r in ipairs(p._rows) do r:Hide(); r:SetParent(nil) end
    p._rows = {}

    local options = WT.TOTEMS[element] or {}
    local rowH = 18
    -- "(clear)" option first
    local entries = { { name = "(clear slot)", clear = true } }
    for _, t in ipairs(options) do table.insert(entries, t) end

    for i, t in ipairs(entries) do
        local btn = CreateFrame("Button", nil, p)
        btn:SetSize(220 - 30, rowH)  -- leave 25px on right for close X
        btn:SetPoint("TOPLEFT", 5, -22 - (i - 1) * rowH)  -- below close X

        local hover = NewTexture(btn, "HIGHLIGHT", C_ROW_HOVER)
        hover:SetAllPoints(btn)

        local label = NewText(btn, 11, t.clear and C_TEXT_DIM or C_TEXT_NORMAL)
        label:SetPoint("LEFT", 6, 0)
        label:SetText(t.name)

        btn:SetScript("OnClick", function()
            local preset = WicksTotemsCharDB.presets[presetIndex]
            if not preset then p:Hide(); return end
            preset.totems = preset.totems or {}
            preset.totems[element] = t.clear and nil or t.name
            p:Hide()
            WT:Emit("PRESET_CHANGED")
            UI:RefreshPresets()
        end)

        table.insert(p._rows, btn)
    end
    p:SetHeight(28 + #entries * rowH + 6)  -- close X header + rows + bottom pad
    p:Show()
    pcall(p.RegisterEvent, p, "GLOBAL_MOUSE_DOWN")
end

-- Local alias for in-file calls
local function openPicker(anchorTo, presetIndex, element)
    UI:OpenPicker(anchorTo, presetIndex, element)
end

local function buildPresetsPane(parent)
    local pane = parent

    local hint = NewText(pane, 10, C_TEXT_DIM)
    hint:SetPoint("TOPLEFT", PADDING, -PADDING)
    hint:SetText("Click an element to change its totem. Click name to rename.")

    -- + New Preset button (top-right)
    local addBtn = CreateFrame("Button", nil, pane)
    addBtn:SetSize(110, 20)
    addBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING + 2)
    NewTexture(addBtn, "BACKGROUND", C_HEADER_BG):SetAllPoints(addBtn)
    AddBorder(addBtn)
    local addLbl = NewText(addBtn, 10, C_GREEN)
    addLbl:SetPoint("CENTER")
    addLbl:SetText("+ New preset")
    addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3]) end)
    addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3]) end)
    addBtn:SetScript("OnClick", function()
        WicksTotemsCharDB.presets = WicksTotemsCharDB.presets or {}
        table.insert(WicksTotemsCharDB.presets, {
            name   = "Preset " .. (#WicksTotemsCharDB.presets + 1),
            totems = {},
        })
        WT:Emit("PRESET_CHANGED")
        UI:RefreshPresets()
    end)

    UI._presetRowHost = CreateFrame("Frame", nil, pane)
    UI._presetRowHost:SetPoint("TOPLEFT", PADDING, -PADDING - 26)
    UI._presetRowHost:SetPoint("TOPRIGHT", -PADDING, -PADDING - 26)
    UI._presetRowHost:SetHeight(1)
end

local function buildElementPill(row, element, i, total, presetIndex, totemName)
    -- 2x2 grid: i 1..4 → (col 0/1, gridRow 0/1)
    local col = (i - 1) % 2
    local gridRow = math.floor((i - 1) / 2)

    -- Panel content area is 520-2*PADDING = ~500w; row spans full content.
    -- Pill width target ~230 with 8px gutter.
    local pillW = 230
    local pillH = 16
    local pad = 12
    local x = pad + col * (pillW + 8)
    local y = -26 - gridRow * 18

    local pill = CreateFrame("Button", nil, row)
    pill:SetSize(pillW, pillH)
    pill:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)

    local hover = NewTexture(pill, "HIGHLIGHT", C_ROW_HOVER)
    hover:SetAllPoints(pill)

    local elTint = ELEMENT_TINT[element]
    local elLbl = NewText(pill, 9, { elTint[1], elTint[2], elTint[3], 1 })
    elLbl:SetPoint("LEFT", 4, 0)
    elLbl:SetText(ELEMENT_LABEL[element]:upper() .. ":")

    local nameLbl = NewText(pill, 10, totemName and C_TEXT_NORMAL or C_TEXT_DIM)
    nameLbl:SetPoint("LEFT", elLbl, "RIGHT", 6, 0)
    nameLbl:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetText(totemName or "(empty)")

    pill:SetScript("OnClick", function() openPicker(pill, presetIndex, element) end)
end

function UI:RefreshPresets()
    if not self._presetRowHost then return end
    if self._presetRows then
        for _, r in ipairs(self._presetRows) do r:Hide(); r:SetParent(nil) end
    end
    self._presetRows = {}

    local list = WicksTotemsCharDB.presets or {}
    local active = WicksTotemsCharDB.activePreset or 1

    local rowH = 70
    for i, preset in ipairs(list) do
        local row = CreateFrame("Frame", nil, self._presetRowHost)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 4))
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * (rowH + 4))

        NewTexture(row, "BACKGROUND", C_HEADER_BG):SetAllPoints(row)
        AddBorder(row)

        -- Active dot (clickable to set active)
        local dot = CreateFrame("Button", nil, row)
        dot:SetSize(16, 16)
        dot:SetPoint("TOPLEFT", 8, -6)
        local dotTex = NewTexture(dot, "ARTWORK")
        dotTex:SetAllPoints(dot)
        if i == active then
            dotTex:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        else
            dotTex:SetColorTexture(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 0.5)
        end
        dot:SetScript("OnClick", function()
            WicksTotemsCharDB.activePreset = i
            WT:Emit("PRESET_CHANGED")
            UI:RefreshPresets()
            refreshActivePane()
        end)
        dot:SetScript("OnEnter", function()
            GameTooltip:SetOwner(dot, "ANCHOR_TOP")
            GameTooltip:SetText(i == active and "Active preset" or "Click to set active")
            GameTooltip:Show()
        end)
        dot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Name (click → EditBox)
        local nameBtn = CreateFrame("Button", nil, row)
        nameBtn:SetPoint("TOPLEFT", 30, -4)
        nameBtn:SetSize(280, 20)

        local nameText = NewText(nameBtn, 13, C_TEXT_NORMAL)
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetText(preset.name or ("Preset " .. i))
        nameText:SetJustifyH("LEFT")

        local edit = CreateFrame("EditBox", nil, nameBtn)
        edit:SetFontObject(GameFontNormal)
        edit:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(32)
        edit:SetPoint("LEFT", 0, 0)
        edit:SetSize(280, 20)
        edit:Hide()
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:Hide(); nameText:Show() end)
        edit:SetScript("OnEnterPressed", function(self)
            local txt = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
            if txt ~= "" then
                preset.name = txt
                nameText:SetText(txt)
            end
            self:ClearFocus(); self:Hide(); nameText:Show()
            WT:Emit("PRESET_CHANGED")
        end)

        nameBtn:SetScript("OnClick", function()
            nameText:Hide()
            edit:SetText(preset.name or "")
            edit:Show()
            edit:SetFocus()
            edit:HighlightText()
        end)
        nameBtn:SetScript("OnEnter", function() nameText:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3]) end)
        nameBtn:SetScript("OnLeave", function() nameText:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3]) end)

        -- Delete (×)
        local del = CreateFrame("Button", nil, row)
        del:SetSize(20, 20)
        del:SetPoint("TOPRIGHT", -6, -4)
        local delX = del:CreateFontString(nil, "OVERLAY")
        delX:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        delX:SetPoint("CENTER")
        delX:SetText("×")
        delX:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1)
        del:SetScript("OnEnter", function() delX:SetTextColor(0.95, 0.32, 0.32, 1) end)
        del:SetScript("OnLeave", function() delX:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1) end)
        del:SetScript("OnClick", function()
            if #WicksTotemsCharDB.presets <= 1 then
                print("|cff4FC778Wick's Totems|r: keep at least one preset.")
                return
            end
            table.remove(WicksTotemsCharDB.presets, i)
            if WicksTotemsCharDB.activePreset > #WicksTotemsCharDB.presets then
                WicksTotemsCharDB.activePreset = #WicksTotemsCharDB.presets
            end
            WT:Emit("PRESET_CHANGED")
            UI:RefreshPresets()
        end)

        -- 4 element pills (2×2 grid)
        local totems = preset.totems or {}
        for j, el in ipairs(ELEMENT_ORDER) do
            buildElementPill(row, el, j, 4, i, totems[el])
        end

        table.insert(self._presetRows, row)
    end

    self._presetRowHost:SetHeight(math.max(1, #list * (rowH + 4)))
end

-- Backward-compat alias for existing call sites
local function refreshPresetsPane() UI:RefreshPresets() end

-- ============================================================
-- Bindings tab: stub (full editor in v0.2)
-- ============================================================
local function buildBindingsPane(parent)
    local pane = parent

    local hint = NewText(pane, 11, C_TEXT_NORMAL)
    hint:SetPoint("TOPLEFT", PADDING, -PADDING)
    hint:SetText("Assign keys via Blizzard's keybindings panel:")

    local sub = NewText(pane, 10, C_TEXT_DIM)
    sub:SetPoint("TOPLEFT", PADDING, -PADDING - 16)
    sub:SetText("Press Esc -> Key Bindings -> AddOns category -> 'Wick's Totems and Things'")

    -- Static list of the 8 binding entries
    local entries = {
        { label = "Drop active preset (all 4 totems)", binding = "CLICK WicksTotemsBar_DropAll:LeftButton" },
        { label = "Cast Fire totem",                   binding = "CLICK WicksTotemsBar_FIRE:LeftButton" },
        { label = "Cast Earth totem",                  binding = "CLICK WicksTotemsBar_EARTH:LeftButton" },
        { label = "Cast Water totem",                  binding = "CLICK WicksTotemsBar_WATER:LeftButton" },
        { label = "Cast Air totem",                    binding = "CLICK WicksTotemsBar_AIR:LeftButton" },
        { label = "Toggle main panel",                 binding = "WICKSTOTEMS_TOGGLE_PANEL" },
        { label = "Toggle icon strip",                 binding = "WICKSTOTEMS_TOGGLE_BAR" },
        { label = "Cycle to next preset",              binding = "WICKSTOTEMS_CYCLE_PRESET" },
    }

    local listTop = -PADDING - 40
    local rowH = 22
    UI._bindingRows = {}
    for i, e in ipairs(entries) do
        local row = CreateFrame("Frame", nil, pane)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT",  PADDING,        listTop - (i - 1) * (rowH + 2))
        row:SetPoint("TOPRIGHT", -PADDING,       listTop - (i - 1) * (rowH + 2))

        if i % 2 == 0 then
            local stripe = NewTexture(row, "BACKGROUND")
            stripe:SetColorTexture(1, 1, 1, 0.025)
            stripe:SetAllPoints(row)
        end

        local labelText = NewText(row, 11, C_TEXT_NORMAL)
        labelText:SetPoint("LEFT", 4, 0)
        labelText:SetText(e.label)

        local keyText = NewText(row, 11, C_GREEN)
        keyText:SetPoint("RIGHT", -4, 0)

        UI._bindingRows[i] = { keyText = keyText, binding = e.binding }
    end

    pane:SetScript("OnShow", function() UI:RefreshBindings() end)
end

function UI:RefreshBindings()
    if not self._bindingRows then return end
    for _, row in ipairs(self._bindingRows) do
        local k1, k2 = GetBindingKey(row.binding)
        if k1 then
            row.keyText:SetText(k2 and (k1 .. ", " .. k2) or k1)
        else
            row.keyText:SetText("(unbound)")
            row.keyText:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        end
    end
end

-- ============================================================
-- Options tab
-- ============================================================

local function makeCheckbox(parent, label, getter, onChange)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)

    NewTexture(cb, "BACKGROUND", { 0.05, 0.04, 0.08, 1 }):SetAllPoints(cb)
    AddBorder(cb)

    local check = NewTexture(cb, "OVERLAY", C_GREEN)
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)

    local lbl = NewText(cb, 11, C_TEXT_NORMAL)
    lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    lbl:SetText(label)

    cb._check = check
    cb._lbl = lbl

    local function refresh()
        if getter() then check:Show() else check:Hide() end
    end
    cb._refresh = refresh

    cb:SetScript("OnClick", function()
        local newVal = not getter()
        if onChange then onChange(newVal) end
        refresh()
    end)
    cb:EnableMouse(true)
    -- Whole row (button + label) clickable: extend hit area to label width
    cb:HookScript("OnEnter", function() lbl:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3]) end)
    cb:HookScript("OnLeave", function() lbl:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3]) end)

    refresh()
    return cb
end

-- Compact horizontal scale slider (Wick chrome). 120px wide track with a
-- draggable green thumb + live percentage text. Calls onChange(value) on drag.
local function makeSlider(parent, getter, onChange, minVal, maxVal, step)
    minVal = minVal or 0.6
    maxVal = maxVal or 1.8
    step   = step   or 0.05

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(120, 12)
    frame:EnableMouse(true)

    local track = NewTexture(frame, "BACKGROUND", { 0.10, 0.08, 0.16, 1 })
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(2)

    local fill = NewTexture(frame, "BORDER", C_GREEN)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(2)

    local thumb = CreateFrame("Button", nil, frame)
    thumb:SetSize(8, 12)
    NewTexture(thumb, "ARTWORK", C_GREEN):SetAllPoints(thumb)
    thumb:RegisterForDrag("LeftButton")

    local valText = NewText(frame, 10, C_TEXT_NORMAL)
    valText:SetPoint("LEFT", frame, "RIGHT", 8, 0)

    local function snap(v)
        v = math.max(minVal, math.min(maxVal, v))
        v = math.floor((v - minVal) / step + 0.5) * step + minVal
        return tonumber(string.format("%.2f", v))
    end

    local function applyVisual(v)
        local frac = (v - minVal) / (maxVal - minVal)
        local trackW = frame:GetWidth()
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", frame, "LEFT", frac * trackW, 0)
        fill:SetPoint("RIGHT", frame, "LEFT", frac * trackW, 0)
        valText:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
    end

    applyVisual(getter())

    local dragging = false
    local function onUpdate()
        if not dragging then return end
        local mx = GetCursorPosition()
        local effScale = frame:GetEffectiveScale()
        local left = frame:GetLeft() * effScale
        local frac = math.max(0, math.min(1, (mx - left) / (frame:GetWidth() * effScale)))
        local newV = snap(minVal + frac * (maxVal - minVal))
        applyVisual(newV)
        if onChange then onChange(newV) end
    end

    thumb:SetScript("OnMouseDown", function() dragging = true end)
    thumb:SetScript("OnMouseUp",   function() dragging = false end)
    frame:SetScript("OnMouseDown", function() dragging = true; onUpdate() end)
    frame:SetScript("OnMouseUp",   function() dragging = false end)
    frame:SetScript("OnUpdate", onUpdate)

    return frame
end

local function makeSmallButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(80, 18)
    NewTexture(b, "BACKGROUND", C_HEADER_BG):SetAllPoints(b)
    AddBorder(b)
    local lbl = NewText(b, 10, C_GREEN)
    lbl:SetPoint("CENTER")
    lbl:SetText(label)
    b:SetScript("OnEnter", function() lbl:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3]) end)
    b:SetScript("OnLeave", function() lbl:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3]) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeSectionHeader(parent, text, y)
    local h = NewText(parent, 12, C_GREEN)
    h:SetPoint("TOPLEFT", PADDING, y)
    h:SetText(text)
    -- thin underline
    local line = NewTexture(parent, "BORDER", C_BORDER)
    line:SetPoint("TOPLEFT", PADDING, y - 14)
    line:SetPoint("TOPRIGHT", -PADDING, y - 14)
    line:SetHeight(1)
    return h
end

local function buildOptionsPane(parent)
    local pane = parent

    -- Defensive: make sure every saved-vars subtable a getter touches
    -- exists before any checkbox's refresh() dereferences it. Prevents
    -- a single nil from aborting the rest of the panel.
    WicksTotemsDB.bar     = WicksTotemsDB.bar     or {}
    WicksTotemsDB.range   = WicksTotemsDB.range   or { enabled = true, sound = true, banner = true, vignette = true }
    WicksTotemsDB.overlay = WicksTotemsDB.overlay or { enabled = true }
    WicksTotemsDB.cd      = WicksTotemsDB.cd      or {}
    WicksTotemsDB.swing   = WicksTotemsDB.swing   or {}
    WicksTotemsCharDB.twist = WicksTotemsCharDB.twist or {}

    -- Compact 2-column layout — 3 bar sections (Show + Lock + Reset on one line each)
    -- + Range warning column + Overlay row.
    local rowH = 20
    local sectionGap = 4   -- tight spacing so all sections (incl. twist) fit
    local y = -PADDING

    -- Helper: one-line "Bar" section with Show / Lock / Reset + a Size slider
    local function barRow(label, getHidden, setHidden, getLocked, setLocked, onReset, getScale, setScale)
        makeSectionHeader(pane, label, y); y = y - 22
        local show = makeCheckbox(pane, "Show",
            function() return not getHidden() end,
            function(v) setHidden(not v) end)
        show:SetPoint("TOPLEFT", PADDING + 4, y)

        local lock = makeCheckbox(pane, "Lock",
            function() return getLocked() end,
            function(v) setLocked(v) end)
        lock:SetPoint("TOPLEFT", PADDING + 90, y)

        local rst = makeSmallButton(pane, "Reset position", onReset)
        rst:SetPoint("TOPLEFT", PADDING + 170, y - 1)

        if getScale and setScale then
            local sizeLbl = NewText(pane, 10, C_TEXT_DIM)
            sizeLbl:SetPoint("TOPLEFT", PADDING + 270, y - 3)
            sizeLbl:SetText("Size")
            local slider = makeSlider(pane, getScale, setScale, 0.6, 1.8, 0.05)
            slider:SetPoint("TOPLEFT", PADDING + 300, y - 3)
        end

        y = y - rowH - sectionGap
    end

    barRow("Totem Icon Strip",
        function() return WicksTotemsDB.bar.hidden end,
        function(v)
            WicksTotemsDB.bar.hidden = v
            if WT.TotemBar then if v then WT.TotemBar:Hide() else WT.TotemBar:Show() end end
        end,
        function() return WicksTotemsDB.bar.locked end,
        function(v) WicksTotemsDB.bar.locked = v end,
        function() if WT.TotemBar and WT.TotemBar.ResetPosition then WT.TotemBar:ResetPosition() end end,
        function() return WicksTotemsDB.bar.scale or 1.0 end,
        function(v) if WT.TotemBar and WT.TotemBar.SetScale then WT.TotemBar:SetScale(v) end end)

    barRow("Cooldown / Proc Bar",
        function()
            WicksTotemsDB.cd = WicksTotemsDB.cd or {}
            return WicksTotemsDB.cd.hidden
        end,
        function(v)
            WicksTotemsDB.cd = WicksTotemsDB.cd or {}
            WicksTotemsDB.cd.hidden = v
            if WT.CooldownTracker then if v then WT.CooldownTracker:Hide() else WT.CooldownTracker:Show() end end
        end,
        function() return (WicksTotemsDB.cd or {}).locked end,
        function(v)
            WicksTotemsDB.cd = WicksTotemsDB.cd or {}
            WicksTotemsDB.cd.locked = v
        end,
        function() if WT.CooldownTracker and WT.CooldownTracker.ResetPosition then WT.CooldownTracker:ResetPosition() end end,
        function()
            WicksTotemsDB.cd = WicksTotemsDB.cd or {}
            return WicksTotemsDB.cd.scale or 1.0
        end,
        function(v) if WT.CooldownTracker and WT.CooldownTracker.SetScale then WT.CooldownTracker:SetScale(v) end end)

    barRow("Swing Timer",
        function()
            WicksTotemsDB.swing = WicksTotemsDB.swing or {}
            return WicksTotemsDB.swing.hidden
        end,
        function(v)
            WicksTotemsDB.swing = WicksTotemsDB.swing or {}
            WicksTotemsDB.swing.hidden = v
            if WT.SwingTimer then if v then WT.SwingTimer:Hide() else WT.SwingTimer:Show() end end
        end,
        function() return (WicksTotemsDB.swing or {}).locked end,
        function(v)
            WicksTotemsDB.swing = WicksTotemsDB.swing or {}
            WicksTotemsDB.swing.locked = v
        end,
        function() if WT.SwingTimer and WT.SwingTimer.ResetPosition then WT.SwingTimer:ResetPosition() end end,
        function()
            WicksTotemsDB.swing = WicksTotemsDB.swing or {}
            return WicksTotemsDB.swing.scale or 1.0
        end,
        function(v) if WT.SwingTimer and WT.SwingTimer.SetScale then WT.SwingTimer:SetScale(v) end end)

    -- ----- Out-of-Range Warning -----
    makeSectionHeader(pane, "Out-of-Range Warning", y); y = y - 22
    local cb = makeCheckbox(pane, "Enabled", function() return WicksTotemsDB.range.enabled end, function(v)
        WicksTotemsDB.range.enabled = v
    end)
    cb:SetPoint("TOPLEFT", PADDING + 4, y)
    cb = makeCheckbox(pane, "Play sound", function() return WicksTotemsDB.range.sound end, function(v)
        WicksTotemsDB.range.sound = v
    end)
    cb:SetPoint("TOPLEFT", PADDING + 130, y)
    y = y - rowH

    cb = makeCheckbox(pane, "Top banner", function() return WicksTotemsDB.range.banner end, function(v)
        WicksTotemsDB.range.banner = v
    end)
    cb:SetPoint("TOPLEFT", PADDING + 4, y)
    cb = makeCheckbox(pane, "Screen vignette", function() return WicksTotemsDB.range.vignette end, function(v)
        WicksTotemsDB.range.vignette = v
    end)
    cb:SetPoint("TOPLEFT", PADDING + 130, y)
    y = y - rowH - sectionGap

    -- ----- Totem Frame Count Badges -----
    makeSectionHeader(pane, "Totem Frame Count Badges", y); y = y - 22
    cb = makeCheckbox(pane, "Show count badges on Blizzard's totem icons",
        function() return WicksTotemsDB.overlay.enabled end,
        function(v)
            WicksTotemsDB.overlay.enabled = v
            if WT.TotemFrameOverlay then WT.TotemFrameOverlay:Refresh() end
        end)
    cb:SetPoint("TOPLEFT", PADDING + 4, y)
    y = y - rowH - sectionGap

    -- ----- Totem Twisting -----
    -- Default totem pairs per element. Toggling on populates the saved-vars
    -- entry; toggling off clears `enabled` so single-cast resumes.
    -- Refresh = the interval after which the click-now cue fires + the
    -- /castsequence reset timeout. Air = 5s matches WF buff duration so
    -- the cue prompts you just before WF falls off.
    local TWIST_DEFAULTS = {
        fire  = { totems = { "Searing Totem", "Magma Totem" },                 refresh = 15 },
        earth = { totems = { "Strength of Earth Totem", "Stoneskin Totem" },   refresh = 20 },
        water = { totems = { "Healing Stream Totem", "Mana Spring Totem" },    refresh = 15 },
        air   = { totems = { "Windfury Totem", "Grace of Air Totem" },         refresh = 5  },
    }

    makeSectionHeader(pane, "Totem Twisting (cycles two totems on one keybind)", y); y = y - 22

    local function twistRow(element, label, x)
        WicksTotemsCharDB.twist = WicksTotemsCharDB.twist or {}
        local d = TWIST_DEFAULTS[element]
        local row = makeCheckbox(pane,
            ("%s: %s <-> %s"):format(label, d.totems[1]:gsub(" Totem", ""), d.totems[2]:gsub(" Totem", "")),
            function()
                local t = WicksTotemsCharDB.twist[element]
                return t and t.enabled
            end,
            function(v)
                WicksTotemsCharDB.twist[element] = WicksTotemsCharDB.twist[element] or {}
                local t = WicksTotemsCharDB.twist[element]
                t.enabled = v
                if not t.totems then t.totems = d.totems end
                if not t.refresh then t.refresh = d.refresh end
                WT:Emit("PRESET_CHANGED")
            end)
        row:SetPoint("TOPLEFT", PADDING + 4, x)
    end

    twistRow("fire",  "Fire",  y); y = y - rowH
    twistRow("earth", "Earth", y); y = y - rowH
    twistRow("water", "Water", y); y = y - rowH
    twistRow("air",   "Air",   y); y = y - rowH
end

-- ============================================================
-- Tab management
-- ============================================================

function UI:SelectTab(id)
    self._activeTab = id
    for tabId, btn in pairs(self._tabs or {}) do
        if tabId == id then
            btn._lbl:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3])
            btn._underline:Show()
        else
            btn._lbl:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
            btn._underline:Hide()
        end
    end
    for paneId, pane in pairs(self._panes or {}) do
        if paneId == id then pane:Show() else pane:Hide() end
    end
    if id == "active" then refreshActivePane() end
    if id == "presets" then refreshPresetsPane() end
end

function UI:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "WicksTotemsFrame", UIParent)
    f:SetSize(PANEL_W, PANEL_H)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    local p = WicksTotemsDB.point or "CENTER"
    f:SetPoint(p, UIParent, p, WicksTotemsDB.x or 0, WicksTotemsDB.y or 0)

    -- Background + chrome
    local bg = NewTexture(f, "BACKGROUND", C_BG)
    bg:SetAllPoints(f)
    AddBorder(f)
    AddCornerAccents(f)

    self.frame = f
    self.titleBar = buildTitleBar(f)
    self.tabStrip = buildTabs(f)

    -- Content area: between tabs and bottom
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + TAB_H))
    content:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Pre-create each pane Frame, then run its builder against it. If the
    -- builder errors, all the partial children are still inside the pane,
    -- so pane:Hide() correctly hides everything (no orphans).
    self._panes = {}
    local panes = {
        { id = "active",   fn = buildActivePane },
        { id = "presets",  fn = buildPresetsPane },
        { id = "bindings", fn = buildBindingsPane },
        { id = "options",  fn = buildOptionsPane },
    }
    for _, p in ipairs(panes) do
        local pane = CreateFrame("Frame", nil, content)
        pane:SetAllPoints(content)
        self._panes[p.id] = pane
        local ok, err = pcall(p.fn, pane)
        if not ok then
            print(("|cff4FC778Wick's Totems|r build %s pane failed: %s"):format(p.id, tostring(err)))
        end
    end
    for _, pane in pairs(self._panes) do pane:Hide() end

    self:SelectTab("active")

    -- Live refresh hooks
    WT:On("AFFECTED_UPDATED", function() refreshActivePane() end)
    WT:On("PRESET_CHANGED", function()
        refreshActivePane()
        refreshPresetsPane()
    end)
end

function UI:Show()
    self:Build()
    self.frame:Show()
    refreshActivePane()
    refreshPresetsPane()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    self:Build()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end

WT:On("LOGIN", function() UI:Build() end)
