-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesAuras.lua
-- Global Styles > Auras, in BuzzardPanel.
--
-- The panel equivalent of the `gsAuras` branch of BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, the same write
-- fan-out and the same side effects, with the AceConfig args table
-- replaced by two BuzzardPanel pages -- one per subtab, each a route of
-- its own under `globalStyles/gsAuras`, drawn as a strip by the `tabs`
-- navigator that node declares (the Pages_Icons pattern).
--
-- STORAGE. This page owns none. One change to an aura key lands on the
-- Raid/Party global auras sub-category AND on every Layout flat AND on
-- every custom frame group -- and, for the four border keys that have a
-- unit-frame twin, on the unit frame profile as well. That fan-out is
-- Pages_GlobalStylesShared.lua's `GS()` table, whose entries keep the
-- names and signatures the Ace widgets called:
--
--     GS.ApplyAuras("buffs",
--         function() GS.WriteRPAuras("buffs", key, val) end,
--         function() GS.WriteCFGAuras("buffs", key, val) end,
--         GS.RefreshRPAurasLayout, nil,
--         function() GS.WriteUFAuras(key, val) end)
--
-- Auras routes per SUB-CATEGORY: "buffs" and "debuffs" on the Aura
-- Borders tab, "dispelIndicator" on Dispel Highlights. The read side is
-- GS.aurasGSSource(subcat) -- the first surface in scope -- so every
-- field is get/set rather than bound, and each carries its own `id` (the
-- storage key) and its own `default`, read from BuzzardFrames' own
-- defaults one level down from GSDefault("auras", subcat), which is how
-- the Raid/Party aura pages resolve theirs too. That pair is what keeps
-- right-click Undo and Reset working on a get/set field.
--
-- The WRITE and the refresh both happen in the setter, in the Ace order,
-- because ApplyAuras IS that order. No field declares `onChange`; the
-- two mouse-up gates the Ace setters asked for are the same
-- BF:MouseUpOption calls under the same keys.
--
-- Nothing at file scope reads BuzzardFrames: BF() and the GS table are
-- resolved inside the closures, after the panel is open.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function GSF() return BuzzardFramesOptions:GS() end

-- ── The read side ──────────────────────────────────────────────

local function ASrc(subcat)
    local GS = GSF()
    return GS and GS.aurasGSSource(subcat)
end

local function AVal(subcat, key)
    local src = ASrc(subcat)
    return src and src[key]
end

-- The shipped default for one aura key. The aura defaults are per
-- sub-category -- raidPartyFrameDefaults.profile.auras.<subcat>[key] --
-- so the section default is indexed one level further, exactly as
-- Pages_AuraShared's AuraDefaults resolves them.
local function ADefault(subcat, key)
    local t = BuzzardFramesOptions:GSDefault("auras", subcat)
    return type(t) == "table" and t[key] or nil
end

-- ── The write side ─────────────────────────────────────────────
--
-- `writeUF` is passed only for the keys the Ace widgets passed it for:
-- the four buff/debuff border keys that have a unit-frame twin in
-- GS.UF_AURA_BORDER_MAP. Everything else is Raid/Party and custom frame
-- groups only, which is what the Unit Frames tooltip on the scope card
-- says.

local function Write(subcat, key, val, rpRefresh, preview, withUF)
    local GS = GSF()
    if not GS then return end
    GS.ApplyAuras(subcat,
        function() GS.WriteRPAuras(subcat, key, val) end,
        function() GS.WriteCFGAuras(subcat, key, val) end,
        rpRefresh, preview,
        withUF and function() GS.WriteUFAuras(key, val) end or nil)
end

-- ── The refresh chains ─────────────────────────────────────────
--
-- One function per chain the Ace setters ran, in the order they ran it.

local function LayoutRefresh()
    local GS = GSF()
    if GS then GS.RefreshRPAurasLayout() end
end

local function ForEachFrame(fn)
    local bf = BF()
    if not bf then return end
    for _, f in pairs(bf.activeFrames or {}) do fn(bf, f) end
end

local function DispelOnly()
    local bf = BF()
    if bf and bf.RefreshDispelOnly then bf:RefreshDispelOnly() end
end

local function DebuffHighlight()
    ForEachFrame(function(bf, f) bf:UpdateDebuffHighlight(f) end)
end

local function DispelOnlyAndHighlight()
    DispelOnly()
    DebuffHighlight()
end

local function PreviewDummyAuras()
    local bf = BF()
    if bf and bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
end

-- The indicator's own relayout, mouse-up gated under the Ace key.
local function DispelIndicatorLayout()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("aurasDispelIndLayout", function()
        local ind = bf:GetIndicatorByName("dispelDebuffIndicator")
        if ind then ind:LayoutAllFrames() end
    end)
end

-- A border width change moves every icon, so the whole frame is laid out
-- again before the highlight is re-evaluated. Mouse-up gated under the
-- Ace key.
local function DebuffBorderWidthRefresh()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("aurasDebuffBorderWidth", function()
        for f in pairs(bf.activeFrames or {}) do bf:LayoutFrame(f) end
        for f in pairs(bf.activeFrames or {}) do bf:UpdateDebuffHighlight(f) end
        if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
    end)
end

local function OverlayAlphaRefresh()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("aurasDebuffOverlay", function()
        for f in pairs(bf.activeFrames or {}) do bf:UpdateDebuffHighlight(f) end
    end)
end

local function HealthColorAlphaRefresh()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("aurasDebuffHealthColor", function()
        for f in pairs(bf.activeFrames or {}) do bf:UpdateDebuffHighlight(f) end
    end)
end

-- ── Option lists ───────────────────────────────────────────────
--
-- The border SHAPES, without the thick rounded spelling: that is a
-- weight, and the shared border-style control offers it on a strip of
-- its own (see Pages_BorderStyle.lua). GS.GS_AURA_BORDER_STYLE_SORTING
-- is the order.
local BORDER_STYLE_OPTIONS = {
    { value = "blizzard", text = "Blizzard-Style" },
    { value = "flat",     text = "Square"         },
    { value = "rounded",  text = "Rounded"        },
}

local INDICATOR_STYLE_OPTIONS = {
    { value = "square", text = "Colored Square" },
    { value = "icon",   text = "Dispel Type Icon" },
}

local INDICATOR_MODE_OPTIONS = {
    { value = "dispellable",    text = "Dispellable by Me" },
    { value = "allDispellable", text = "All Dispellable" },
}

local HIGHLIGHT_MODE_OPTIONS = {
    { value = "dispellable",    text = "Dispellable by Me" },
    { value = "allDispellable", text = "All Dispellable" },
    { value = "all",            text = "All Debuffs" },
}

-- ── Field shorthands ───────────────────────────────────────────

local function Opts(f, opts)
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sw(subcat, key, label, rpRefresh, preview, withUF, opts)
    return Opts({
        control = "switch", label = label,
        id = key, default = ADefault(subcat, key), disabled = "combat",
        get = function() return AVal(subcat, key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(subcat, key, v, rpRefresh, preview, withUF)
        end,
    }, opts)
end

local function Sl(subcat, key, label, lo, hi, st, rpRefresh, preview, withUF, opts)
    return Opts({
        control = "slider", label = label,
        min = lo, max = hi, step = st,
        id = key, default = ADefault(subcat, key), disabled = "combat",
        get = function() return AVal(subcat, key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(subcat, key, v, rpRefresh, preview, withUF)
        end,
    }, opts)
end

local function Dd(subcat, key, label, options, rpRefresh, preview, opts)
    return Opts({
        control = "dropdown", label = label, options = options,
        id = key, default = ADefault(subcat, key), disabled = "combat",
        get = function() return AVal(subcat, key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(subcat, key, v, rpRefresh, preview, false)
        end,
    }, opts)
end

-- An opacity STORED as a fraction (0.1 .. 1.0) and SHOWN as a percentage.
-- The panel's slider draws whole numbers -- there is no isPercent -- so
-- the control works in percent and the adapters do the arithmetic, the
-- shape the Raid/Party Debuffs page uses for these same two keys. `id`
-- and a percent `default` rather than the stored fraction, so Reset hands
-- the slider a number from its own range.
local function Pct(subcat, key, label, lo, hi, st, rpRefresh, opts)
    local d = ADefault(subcat, key)
    return Opts({
        control = "slider", label = label, suffix = "%",
        min = lo, max = hi, step = st,
        id = key, default = d and math.floor(d * 100 + 0.5) or nil,
        disabled = "combat",
        get = function()
            local v = AVal(subcat, key)
            if v == nil then return nil end
            return math.floor(v * 100 + 0.5)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(subcat, key, v / 100, rpRefresh, nil, false)
        end,
    }, opts)
end

local function Color(subcat, key, label, fallback, opts)
    local dc = ADefault(subcat, key)
    local default
    if type(dc) == "table" then
        default = { dc.r, dc.g, dc.b, (dc.a ~= nil) and dc.a or 1 }
    end
    return Opts({
        control = "color", label = label, alpha = true,
        id = key, default = default, disabled = "combat",
        get = function()
            local src = ASrc(subcat)
            local c = (src and src[key]) or fallback
            return { c.r, c.g, c.b, c.a or 1 }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local col = { r = v[1], g = v[2], b = v[3], a = v[4] }
            Write(subcat, key, col, LayoutRefresh, nil, true)
        end,
    }, opts)
end

-- ── The border style pair ──────────────────────────────────────
--
-- The style key and the legacy *BlizzardBorders flag are ONE choice with
-- two spellings, and the Ace setter kept them in sync: picking Blizzard
-- raises the flag, picking anything else clears it and writes the style.
-- Both halves fan out, the unit frames included -- the UF profile has a
-- per-kind twin of each (GS.UF_AURA_BORDER_MAP).

local function BorderStyleGet(subcat, styleKey, blizzKey)
    return function()
        local src = ASrc(subcat)
        if not src then return "blizzard" end
        if src[blizzKey] then return "blizzard" end
        return src[styleKey] or "flat"
    end
end

local function BorderStyleSet(subcat, styleKey, blizzKey)
    return function(_, _, val)
        if InCombatLockdown() then return end
        local GS = GSF()
        if not GS then return end
        if val == "blizzard" then
            GS.ApplyAuras(subcat,
                function() GS.WriteRPAuras(subcat, blizzKey, true) end,
                function() GS.WriteCFGAuras(subcat, blizzKey, true) end,
                GS.RefreshRPAurasLayout, nil,
                function() GS.WriteUFAuras(blizzKey, true) end)
        else
            GS.ApplyAuras(subcat,
                function()
                    GS.WriteRPAuras(subcat, blizzKey, false)
                    GS.WriteRPAuras(subcat, styleKey, val)
                end,
                function()
                    GS.WriteCFGAuras(subcat, blizzKey, false)
                    GS.WriteCFGAuras(subcat, styleKey, val)
                end,
                GS.RefreshRPAurasLayout, nil,
                function()
                    GS.WriteUFAuras(blizzKey, false)
                    GS.WriteUFAuras(styleKey, val)
                end)
        end
    end
end

-- What the style strip resets to: the shipped style, unless the shipped
-- profile raises the legacy Blizzard flag -- the same question the getter
-- above answers about the live value.
local function BorderStyleDefault(subcat, styleKey, blizzKey)
    if ADefault(subcat, blizzKey) then return "blizzard" end
    return ADefault(subcat, styleKey) or "flat"
end

-- ── The two pages ──────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The order is the Ace tab order (Aura Borders 1,
-- Dispel Highlights 3) and the titles are the Ace names verbatim.
BuzzardFramesOptions.GS_AURAS_SUBTABS = {
    { id = "auraBorders",      title = "Aura Borders" },
    { id = "dispelHighlights", title = "Dispel Highlights" },
}

local PAGES = {}

-- Aura Borders. Ace order: buffBorderHeader (1) and its three widgets,
-- then debuffBorderHeader (10) and its seven. Each header starts a card.
function PAGES.auraBorders()
    local buffBlizz = function()
        local src = ASrc("buffs")
        return not src or src.buffBlizzardBorders
    end
    local buffNotFlat = function()
        local src = ASrc("buffs")
        if not src or src.buffBlizzardBorders then return true end
        return (src.buffBorderStyle or "flat") ~= "flat"
    end
    local debuffBlizz = function()
        local src = ASrc("debuffs")
        return not src or src.debuffBlizzardBorders
    end
    local debuffNotFlat = function()
        local src = ASrc("debuffs")
        if not src or src.debuffBlizzardBorders then return true end
        return (src.debuffBorderStyle or "flat") ~= "flat"
    end

    local buffStyle, buffWeight = BuzzardFramesOptions:BorderStyleFields({
        options = BORDER_STYLE_OPTIONS,
        id = "buffBorderStyle",
        default = BorderStyleDefault("buffs", "buffBorderStyle",
                                     "buffBlizzardBorders"),
        get = BorderStyleGet("buffs", "buffBorderStyle", "buffBlizzardBorders"),
        set = BorderStyleSet("buffs", "buffBorderStyle", "buffBlizzardBorders"),
    })

    local debuffStyle, debuffWeight = BuzzardFramesOptions:BorderStyleFields({
        options = BORDER_STYLE_OPTIONS,
        id = "debuffBorderStyle",
        default = BorderStyleDefault("debuffs", "debuffBorderStyle",
                                     "debuffBlizzardBorders"),
        get = BorderStyleGet("debuffs", "debuffBorderStyle",
                             "debuffBlizzardBorders"),
        set = BorderStyleSet("debuffs", "debuffBorderStyle",
                             "debuffBlizzardBorders"),
    })

    return {
        { title = "Buff Icon Borders", preset = "form", fields = {
            buffStyle, buffWeight,
            Color("buffs", "buffBorderColor", "Border Color",
                { r = 0.5, g = 0.5, b = 0.5, a = 1 },
                { hidden = buffBlizz }),
            Sl("buffs", "buffBorderThickness", "Border Thickness", 0, 5, 1,
                LayoutRefresh, nil, true, { hidden = buffNotFlat }),
        }},
        { title = "Debuff Icon Borders", preset = "form", fields = {
            debuffStyle, debuffWeight,
            Color("debuffs", "debuffBorderColor", "Border Color",
                { r = 0.5, g = 0.5, b = 0.5, a = 1 },
                { hidden = debuffBlizz }),
            Sl("debuffs", "debuffBorderThickness", "Border Thickness", 0, 5, 1,
                LayoutRefresh, nil, true, { hidden = debuffNotFlat }),
            -- Dispel border thickness, the dispel coloring and the dispel
            -- type icon are Raid/Party and custom frame groups only: the
            -- unit frames have no twin key, so the Ace widgets passed no
            -- writeUF and neither do these.
            Sl("debuffs", "debuffDispelBorderThickness",
                "Dispel Border Thickness", 0, 5, 1,
                LayoutRefresh, nil, false, { hidden = debuffNotFlat }),
            Sw("debuffs", "debuffColorBorderByDispel",
                "Color Border by Dispel Type", LayoutRefresh, nil, false,
                { hidden = debuffBlizz,
                  -- Absent means ON, which is what the Ace getter's
                  -- `~= false` said.
                  get = function()
                      local src = ASrc("debuffs")
                      return not src or src.debuffColorBorderByDispel ~= false
                  end }),
            Sw("debuffs", "showDebuffDispelTypeIcon", "Show Dispel Type Icon",
                LayoutRefresh, nil, false, { hidden = debuffBlizz }),
            -- Stored as a raw percentage (a 10..100 number), not a
            -- fraction, so the slider shows the number that is stored.
            Sl("debuffs", "debuffDispelTypeIconScale", "Dispel Type Icon Size",
                10, 100, 5, LayoutRefresh, nil, false,
                { suffix = "%",
                  hidden = function()
                      local src = ASrc("debuffs")
                      return not src or src.debuffBlizzardBorders
                          or not src.showDebuffDispelTypeIcon
                  end }),
        }},
    }
end

-- Dispel Highlights. Ace order: dispelHeader (1) and its four widgets,
-- debuffBorderHeader2 (10) and its three, debuffOverlayHeader (20) and
-- its three, debuffHealthColorHeader (30) with its note and its three.
-- Each header starts a card.
function PAGES.dispelHighlights()
    local S = "dispelIndicator"
    local noIndicator = function() return not AVal(S, "showDispelIndicator") end
    local noBorder    = function() return not AVal(S, "enableDebuffBorder") end
    local noOverlay   = function() return not AVal(S, "enableDebuffOverlay") end
    local noHealth    = function() return not AVal(S, "enableDebuffHealthColor") end
    return {
        { title = "Dispellable Debuff Indicator", preset = "form", fields = {
            Sw(S, "showDispelIndicator", "Show Dispellable Debuff Indicator",
                DispelOnly, nil, false, { wide = true }),
            Dd(S, "dispelIndicatorStyle", "Indicator Style",
                INDICATOR_STYLE_OPTIONS, DispelOnlyAndHighlight, nil,
                { hidden = noIndicator }),
            Dd(S, "dispelIndicatorMode", "Indicator Mode",
                INDICATOR_MODE_OPTIONS, DebuffHighlight, nil,
                { hidden = noIndicator }),
            Sl(S, "dispelIndicatorSize", "Indicator Size", 2, 20, 1,
                DispelIndicatorLayout, nil, false, { hidden = noIndicator }),
        }},
        { title = "Debuff Border", preset = "form", fields = {
            Sw(S, "enableDebuffBorder", "Enable Debuff Border",
                DebuffHighlight, PreviewDummyAuras, false),
            Dd(S, "debuffBorderMode", "Highlight Mode",
                HIGHLIGHT_MODE_OPTIONS, DebuffHighlight, nil,
                { hidden = noBorder }),
            Sl(S, "debuffBorderWidth", "Border Width", 1, 5, 1,
                DebuffBorderWidthRefresh, nil, false, { hidden = noBorder }),
        }},
        { title = "Debuff Color Overlay", preset = "form", fields = {
            Sw(S, "enableDebuffOverlay", "Enable Debuff Overlay",
                DispelOnlyAndHighlight, nil, false),
            Dd(S, "debuffOverlayMode", "Overlay Mode",
                HIGHLIGHT_MODE_OPTIONS, DebuffHighlight, nil,
                { hidden = noOverlay }),
            Pct(S, "debuffOverlayAlpha", "Overlay Opacity", 10, 100, 5,
                OverlayAlphaRefresh, { hidden = noOverlay }),
        }},
        { title = "Debuff Health Color Change", preset = "form", fields = {
            { control = "note", wide = true,
              text = "Tints the player's health bar in the debuff's dispel "
                  .. "type color while a matching debuff is active." },
            Sw(S, "enableDebuffHealthColor", "Enable Health Color Change",
                DebuffHighlight, PreviewDummyAuras, false),
            Dd(S, "debuffHealthColorMode", "Mode",
                HIGHLIGHT_MODE_OPTIONS, DebuffHighlight, nil,
                { hidden = noHealth }),
            Pct(S, "debuffHealthColorAlpha", "Opacity", 10, 100, 5,
                HealthColorAlphaRefresh, { hidden = noHealth }),
        }},
    }
end

-- One page per subtab: the "Apply Changes To" card first (the Ace dialog
-- drew it above the tab strip, at the section level), then that subtab's
-- own cards. Auras is the section that uses all three surfaces, so the
-- shared card is shown as it comes.
-- ── The section as ONE page ────────────────────────────────────
--
-- The scope strip belongs to the SECTION, not to the subtab on screen --
-- which is where the Ace dialog put it: above the tab strip, stated once.
-- As route subtabs each page could only draw it inside itself, so the same
-- strip appeared under the tabs on every one of them.
--
-- So the section is one page with an IN-PAGE subtab strip: the strip card
-- above it, then a `subtabs` group carrying what each tab draws. The same
-- shape a buff container page uses for Container Settings / Conditions.
--
-- Each tab's `groups` is a FUNCTION, so a tab is built when it is selected
-- rather than all of them on every render.
function BuzzardFramesOptions:GlobalStylesAurasPage()
    local tabs = {}
    for _, st in ipairs(BuzzardFramesOptions.GS_AURAS_SUBTABS) do
        tabs[#tabs + 1] = {
            id = st.id, title = st.title,
            groups = function()
                local build = BuzzardFramesOptions:GS() and PAGES[st.id]
                return build and build() or {}
            end,
        }
    end
    -- PINNED: the scope strip and the strip of subtabs stay put while the
    -- tab's own cards scroll under them -- they are the terms the page is
    -- edited under, not part of what it edits.
    local scope = BuzzardFramesOptions:GSScopeCard({
        rp  = "Writes the Auras section on the base profile and on every Layout.",
        cfg = "Writes every custom frame group, whether or not the group has "
           .. "Auras overridden.",
        uf  = "Writes aura border settings to the Unit Frames profile. Dispel "
           .. "Highlights are Raid/Party and Custom Frame Groups only.",
    })
    scope.pinned = true
    return { groups = {
        scope,
        { subtabKey = "gsAuras", subtabs = tabs, pinned = true },
    }}
end
