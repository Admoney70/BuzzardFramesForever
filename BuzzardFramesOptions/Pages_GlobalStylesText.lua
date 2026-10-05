-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesText.lua
-- Global Styles > Text, in BuzzardPanel.
--
-- The panel equivalent of the `gsText` branch of BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, the same write
-- fan-out and the same side effects, with the AceConfig args table
-- replaced by six BuzzardPanel pages -- one per subtab, each a route of
-- its own under `globalStyles/gsText`, drawn as a strip by the `tabs`
-- navigator that node declares (the Pages_Icons pattern).
--
-- STORAGE. This page owns none. Global Styles is a WRITE-THROUGH: one
-- change to a text key lands on the Raid/Party global text section AND on
-- every Layout flat AND on every custom frame group -- whichever of those
-- surfaces the "Apply Changes To" card has ticked. That fan-out is
-- Pages_GlobalStylesShared.lua's `GS()` table, whose entries keep the
-- names and signatures the Ace widgets called, so every setter here reads
-- as the Ace setter it replaces:
--
--     GS.ApplyText(function() GS.WriteRPText(key, val) end,
--                  function() GS.WriteCFGText(key, val) end,
--                  "textLayout", GS.RefreshRPTextLayout, nil)
--
-- The read side is GS.textSource() -- the first surface in scope -- which
-- is why every field is get/set rather than bound: there is no single
-- table a `bind` path could resolve against. Each one therefore carries
-- its own `id` (the storage key, or `<key>.<subkey>` for the two nested
-- position tables) and its own `default`, read from BuzzardFrames' own
-- defaults through BuzzardFramesOptions:GSDefault -- that pair is what
-- keeps right-click Undo and Reset working on a get/set field.
--
-- The WRITE and the refresh both happen in the setter, in the Ace order,
-- because ApplyText IS that order: write rp, write cfg, debounce the rp
-- refresh under the Ace bucket key, refresh cfg, then the preview. No
-- field declares `onChange`; there is nothing left for one to do.
--
-- Nothing at file scope reads BuzzardFrames: BF() and the GS table are
-- resolved inside the closures, after the panel is open.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The fan-out, resolved at the moment it is used. `BuzzardFramesOptions:GS()`
-- builds it on first call and memoises it; calling it from inside a getter
-- or a setter is what keeps this file's file scope clear of the addon.
local function GSF() return BuzzardFramesOptions:GS() end

-- ── The read side ──────────────────────────────────────────────

-- The text section as the page displays it: the first surface in scope,
-- exactly as the Ace page's textSource() did.
local function TSrc()
    local GS = GSF()
    return GS and GS.textSource()
end

local function TVal(key)
    local src = TSrc()
    return src and src[key]
end

local function TDefault(key)
    return BuzzardFramesOptions:GSDefault("text", key)
end

-- A nested default (namePosition.point, vehicleNamePosition.x): the same
-- defaults table, one level down.
local function TDefaultNested(key, subkey)
    local t = BuzzardFramesOptions:GSDefault("text", key)
    return type(t) == "table" and t[subkey] or nil
end

-- ── The write side ─────────────────────────────────────────────
--
-- One wrapper per Ace call shape. `bucket` is the BF:DebounceOption key
-- the Ace setter named -- the SAME key, so the Ace panel and this one
-- share one trailing timer while both exist.

local function Write(key, val, bucket, rpRefresh, preview)
    local GS = GSF()
    if not GS then return end
    GS.ApplyText(
        function() GS.WriteRPText(key, val) end,
        function() GS.WriteCFGText(key, val) end,
        bucket, rpRefresh, preview)
end

local function WriteNested(key, subkey, val, bucket, rpRefresh, preview)
    local GS = GSF()
    if not GS then return end
    GS.ApplyText(
        function() GS.WriteRPTextNested(key, subkey, val) end,
        function() GS.WriteCFGTextNested(key, subkey, val) end,
        bucket, rpRefresh, preview)
end

-- ── The refresh chains ─────────────────────────────────────────
--
-- One function per chain the Ace setters ran, in the order they ran it.
-- The layout one is the fan-out's own (it refreshes the preview too);
-- the rest are the Ace setters' inline closures, moved here so the
-- setters below read as one line each.

local function LayoutRefresh()
    local GS = GSF()
    if GS then GS.RefreshRPTextLayout() end
end

local function ForEachFrame(fn)
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do fn(bf, f) end
end

local function NamesRefresh()
    local bf = BF()
    if bf then bf:RefreshAllNames() end
end

local function PreviewName()
    local bf = BF()
    if bf and bf.RefreshPreviewName then bf:RefreshPreviewName() end
end

local function HealthUpdate()
    ForEachFrame(function(bf, f) bf:UpdateHealth(f) end)
end

local function PreviewHealthText()
    local bf = BF()
    if bf and bf.RefreshPreviewHealthText then bf:RefreshPreviewHealthText() end
end

local function StatusColors()
    local bf = BF()
    if bf then bf:RefreshAllStatusColors() end
end

-- The append toggle repainted the status colors AND relaid the text out,
-- in that order.
local function StatusColorsAndLayout()
    StatusColors()
    LayoutRefresh()
end

-- The status overlay caches its last decision per frame; clearing
-- _healthState forces the re-eval, as the Ace setter did.
local function DeadShown()
    ForEachFrame(function(_, f) f._healthState = nil end)
    StatusColors()
end

local function LevelUpdate()
    local bf = BF()
    if bf and bf.indicators and bf.indicators.levelText then
        bf.indicators.levelText:UpdateAllFrames()
    end
end

local function GroupLabels()
    local bf = BF()
    if bf then bf:UpdateGroupLabels() end
end

local function VehicleUpdate()
    ForEachFrame(function(bf, f)
        if bf.UpdateVehicle then bf:UpdateVehicle(f) end
    end)
end

-- ── Option lists ───────────────────────────────────────────────

-- The LSM font list, each row previewed in its own face -- what the Ace
-- LSM30_Font picker drew. GS.gsBuildFontVals() answers the Ace `values`
-- MAP, which carries no order and no preview path, so the list is built
-- here the way the Raid/Party Text page builds it.
local function FontOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            out[#out + 1] = { value = name, text = name,
                              font = LSM:Fetch("font", name) }
        end
    end
    return out
end

-- GS.GS_FONT_BORDER_VALUES as an ordered list, in the order the Ace
-- dialog showed it (the `values` table carried no `sorting`).
local FONT_BORDER_OPTIONS = {
    { value = "",                          text = "None (Default)" },
    { value = "MONOCHROME",                text = "Monochrome" },
    { value = "OUTLINE",                   text = "Outline" },
    { value = "OUTLINE, MONOCHROME",       text = "Outline + Monochrome" },
    { value = "THICKOUTLINE",              text = "Thick Outline" },
    { value = "THICKOUTLINE, MONOCHROME",  text = "Thick Outline + Monochrome" },
}

local HEALTH_FORMAT_OPTIONS = {
    { value = "current", text = "Current" },
    { value = "deficit", text = "Deficit" },
    { value = "percent", text = "Percent" },
}

-- How the status label is combined with the unit name. The labels follow
-- statusBeforeName, exactly as the Ace `values` function did.
local function SeparatorOptions()
    if TVal("statusBeforeName") then
        return {
            { value = "BRACKET",            text = "[Status] Name" },
            { value = "BRACKET_NOSPACE",    text = "[Status]Name" },
            { value = "NAME_COMMA",         text = "Status, Name" },
            { value = "NAME_COMMA_NOSPACE", text = "Status,Name" },
            { value = "NAME_DASH_STATUS",   text = "Status - Name" },
            { value = "NAME_NODASH",        text = "Status-Name" },
            { value = "PAREN",              text = "(Status) Name" },
            { value = "PAREN_NOSPACE",      text = "(Status)Name" },
        }
    end
    return {
        { value = "BRACKET",            text = "Name [Status]" },
        { value = "BRACKET_NOSPACE",    text = "Name[Status]" },
        { value = "NAME_COMMA",         text = "Name, Status" },
        { value = "NAME_COMMA_NOSPACE", text = "Name,Status" },
        { value = "NAME_DASH_STATUS",   text = "Name - Status" },
        { value = "NAME_NODASH",        text = "Name-Status" },
        { value = "PAREN",              text = "Name (Status)" },
        { value = "PAREN_NOSPACE",      text = "Name(Status)" },
    }
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every field is get/set (the write fans out to three surfaces), so each
-- one names its storage key as `id` and its shipped default alongside --
-- the pair the right-click menu's Undo and Reset entries run on.
-- `opts` is merged last so a caller can add a `hidden`, a `desc` or a
-- `wide` without a parameter for each.

local function Opts(f, opts)
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sw(key, label, bucket, rpRefresh, preview, opts)
    return Opts({
        control = "switch", label = label,
        id = key, default = TDefault(key), disabled = "combat",
        get = function() return TVal(key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(key, v, bucket, rpRefresh, preview)
        end,
    }, opts)
end

local function Sl(key, label, lo, hi, bucket, rpRefresh, preview, opts)
    return Opts({
        control = "slider", label = label,
        min = lo, max = hi, step = 1,
        id = key, default = TDefault(key), disabled = "combat",
        get = function() return TVal(key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(key, v, bucket, rpRefresh, preview)
        end,
    }, opts)
end

local function Dd(key, label, options, bucket, rpRefresh, preview, opts)
    return Opts({
        control = "dropdown", label = label, options = options,
        id = key, default = TDefault(key), disabled = "combat",
        get = function() return TVal(key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(key, v, bucket, rpRefresh, preview)
        end,
    }, opts)
end

-- A font-name dropdown. The value reads back through
-- BF:NormalizeFontName (GS.gsGetFont), exactly as the Ace getter did:
-- legacy paths, "DEFAULT" and unregistered names map onto a real LSM
-- name, or the control renders empty.
local function FontDd(key, label, bucket, rpRefresh, opts)
    local f = Dd(key, label, FontOptions, bucket, rpRefresh, nil, opts)
    f.get = function()
        local GS = GSF()
        return GS and GS.gsGetFont(key)
    end
    return f
end

-- A color stored {r,g,b[,a]} keyed, shown by a control that speaks
-- arrays. The set builds a FRESH keyed table and fans it out, exactly as
-- the Ace setter did. `fallback` is the Ace getter's own fallback table,
-- kept verbatim.
local function Color(key, label, alpha, fallback, bucket, rpRefresh, preview, opts)
    local dc = TDefault(key)
    local default
    if type(dc) == "table" then
        if alpha then default = { dc.r, dc.g, dc.b, (dc.a ~= nil) and dc.a or 1 }
        else default = { dc.r, dc.g, dc.b } end
    end
    return Opts({
        control = "color", label = label,
        alpha = alpha or nil, id = key, default = default,
        disabled = "combat",
        get = function()
            local src = TSrc()
            local c = (src and src[key]) or fallback
            if not c then return nil end
            if alpha then return { c.r, c.g, c.b, c.a or 1 } end
            return { c.r, c.g, c.b }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local col
            if alpha then col = { r = v[1], g = v[2], b = v[3], a = v[4] }
            else col = { r = v[1], g = v[2], b = v[3] } end
            Write(key, col, bucket, rpRefresh, preview)
        end,
    }, opts)
end

-- One bind entry of an anchor pad, over a FLAT key. A `binds` entry may
-- be a bare path or a full reader/writer (ns.BindNode), which is what
-- lets a composite stand over a fan-out that has no table to bind to.
local function AnchorKey(key, bucket, rpRefresh)
    return {
        id = key, default = TDefault(key),
        get = function() return TVal(key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(key, v, bucket, rpRefresh, nil)
        end,
    }
end

-- The same, over a key INSIDE one of the two nested position tables.
local function AnchorSub(key, subkey, bucket, rpRefresh)
    return {
        id = key .. "." .. subkey, default = TDefaultNested(key, subkey),
        get = function()
            local src = TSrc()
            local t = src and src[key]
            return t and t[subkey]
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            WriteNested(key, subkey, v, bucket, rpRefresh, nil)
        end,
    }
end

-- The Ace Location select and its two offset ranges, as the panel's one
-- anchor pad over the same three settings. Every position cluster in
-- this section runs on a -50..50 range.
local function Pos(binds, opts)
    return Opts({
        control = "anchor", label = "Location",
        binds = binds, min = -50, max = 50, disabled = "combat",
    }, opts)
end

-- A gate in the card HEADER: the Ace toggle whose `hidden` predicate the
-- rest of its inline group carried. `id` and `default` are what make it
-- reset with the rest of its card.
local function Gate(key, tooltip, desc, bucket, rpRefresh, preview)
    return {
        id = key, default = TDefault(key),
        tooltip = tooltip, desc = desc,
        get = function() return TVal(key) end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            Write(key, v, bucket, rpRefresh, preview)
        end,
    }
end

-- ── The six pages ──────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The order is the Ace tab order (names 1,
-- healthText 2, statusText 2.5, levelText 2.7, groupLabels 3,
-- vehicleName 4) and the titles are the Ace names verbatim.
BuzzardFramesOptions.GS_TEXT_SUBTABS = {
    { id = "names",       title = "Names" },
    { id = "healthText",  title = "Health Text" },
    { id = "statusText",  title = "Status Text" },
    { id = "levelText",   title = "Level Text" },
    { id = "groupLabels", title = "Raid Group Labels" },
    { id = "vehicleName", title = "Vehicle Name Text" },
}

local PAGES = {}

-- Names. Ace order: nameHeader (folded into the tab title),
-- namePositionGroup (3), nameFontGroup (4), nameColorsGroup (4.5),
-- capitalizeNamesGroup (5.3).
function PAGES.names()
    return {
        { title = "Name Position", preset = "form", fields = {
            Pos({ point = AnchorSub("namePosition", "point", "textLayout", LayoutRefresh),
                  x     = AnchorSub("namePosition", "x",     "textLayout", LayoutRefresh),
                  y     = AnchorSub("namePosition", "y",     "textLayout", LayoutRefresh) }),
        }},
        { title = "Name Font", preset = "form",
          toggle = Gate("adjustNameFont", "Adjust Name Font",
              "Enable custom font, border style, and size for name text",
              "textLayout", LayoutRefresh, nil),
          fields = {
            FontDd("nameFont", "Font", "textLayout", LayoutRefresh,
                { desc = "Choose a font for unit names" }),
            Dd("nameFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textLayout", LayoutRefresh, nil,
                { desc = "Choose an outline/border style for name text" }),
            Sl("nameFontSize", "Font Size", 6, 30, "textLayout", LayoutRefresh, nil),
        }},
        { title = "Name Colors", preset = "form",
          toggle = Gate("adjustNameColors", "Adjust Name Colors", nil,
              "textNames", NamesRefresh, PreviewName),
          fields = {
            Sw("classColorNames", "Class Color Names",
                "textNames", NamesRefresh, PreviewName),
            Color("nameColor", "Name Color", true, { r = 1, g = 1, b = 1 },
                "textNames", NamesRefresh, PreviewName,
                { desc = "Default name color. Overridden by Class Color "
                      .. "Names when enabled.",
                  hidden = function() return TVal("classColorNames") end }),
        }},
        { title = "Capitalize Names", preset = "form", fields = {
            Sw("capitalizeNames", "Capitalize Names",
                "textNames", NamesRefresh, nil,
                { desc = "Convert unit names to uppercase." }),
        }},
    }
end

-- Health Text. Ace order: healthTextHeader (the tab title),
-- showHealthText (2), healthTextFormat (3), healthTextPctSymbol (3.5),
-- healthTextPosition (4), healthFontGroup (5), healthTextColorGroup (7).
-- The three trailing groups were hidden unless showHealthText -- a group
-- `hidden`, which is the same predicate in the same place.
function PAGES.healthText()
    local noShow = function() return not TVal("showHealthText") end
    return {
        { title = "Health Text", preset = "form",
          toggle = Gate("showHealthText", "Show Health Text", nil,
              "textHealth", HealthUpdate, nil),
          fields = {
            Dd("healthTextFormat", "Health Text Format", HEALTH_FORMAT_OPTIONS,
                "textHealth", HealthUpdate, nil),
            Sw("healthTextPctSymbol", "Show % Symbol",
                "textHealth", HealthUpdate, nil,
                { hidden = function()
                      return TVal("healthTextFormat") ~= "percent"
                  end }),
        }},
        -- healthTextPosition: three FLAT keys (the Ace pos/x/y widgets).
        { title = "Health Text Position", preset = "form", hidden = noShow,
          fields = {
            Pos({ point = AnchorKey("healthTextPosition", "textLayout", LayoutRefresh),
                  x     = AnchorKey("healthTextX",        "textLayout", LayoutRefresh),
                  y     = AnchorKey("healthTextY",        "textLayout", LayoutRefresh) }),
        }},
        { title = "Health Text Font", preset = "form", hidden = noShow,
          toggle = Gate("adjustHealthFont", "Adjust Health Font",
              "Enable custom font, border style, and size for health text",
              "textLayout", LayoutRefresh, nil),
          fields = {
            FontDd("healthFont", "Font", "textLayout", LayoutRefresh,
                { desc = "Choose a font for health text" }),
            Dd("healthFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textLayout", LayoutRefresh, nil,
                { desc = "Choose an outline/border style for health text" }),
            Sl("healthFontSize", "Font Size", 6, 30, "textLayout", LayoutRefresh, nil),
        }},
        { title = "Health Text Color", preset = "form", hidden = noShow,
          toggle = Gate("adjustHealthTextColor", "Adjust Health Text Color", nil,
              "textLayout", LayoutRefresh, PreviewHealthText),
          fields = {
            Sw("classColorHealthText", "Use Class Colors",
                "textHealth", HealthUpdate, PreviewHealthText),
            Color("healthTextColor", "Health Text Color", true,
                { r = 0.5, g = 0.5, b = 0.5 },
                "textLayout", LayoutRefresh, PreviewHealthText,
                { hidden = function() return TVal("classColorHealthText") end }),
        }},
    }
end

-- Status Text. Ace order: statusTextHeader (the tab title), statusTextDesc
-- (1.5), statusTextPosition (2), statusAbbreviateNamesGroup (2.5),
-- statusFontGroup (3), capitalizeStatusGroup (4.5), statusColorSpacer
-- (a pure spacer, dropped), statusColorHeader (5.1 -- the Dead/Offline/AFK
-- cards carry their own titles), deadColorGroup (5.2), offlineColorGroup
-- (7), afkColorGroup (7.5).
function PAGES.statusText()
    local append   = function() return TVal("appendStatusTextToNames") end
    local noAppend = function() return not TVal("appendStatusTextToNames") end
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Status Labels = Dead, Ghost, Offline, AFK" },
        }},
        { title = "Status Text Position", preset = "form", fields = {
            Pos({ point = AnchorKey("statusTextPosition", "textLayout", LayoutRefresh),
                  x     = AnchorKey("statusTextX",        "textLayout", LayoutRefresh),
                  y     = AnchorKey("statusTextY",        "textLayout", LayoutRefresh) },
                { hidden = append }),
            Sw("appendStatusTextToNames", "Append Status Text to Names",
                "textStatus", StatusColorsAndLayout, nil,
                { desc = "When enabled, status labels (Dead, Offline) are "
                      .. "appended directly to the unit name instead of being "
                      .. "shown as a separate overlay text." }),
            Dd("statusAppendSeparator", "Combined Layout", SeparatorOptions,
                "textStatus", StatusColors, nil,
                { desc = "How the status label is combined with the unit name.",
                  hidden = noAppend }),
            Sw("statusBeforeName", "Status Before Name",
                "textStatus", StatusColors, nil,
                { desc = "Show the status label before the unit name instead "
                      .. "of after.",
                  hidden = noAppend }),
        }},
        { title = "Abbreviate Names when appending Status Text", preset = "form",
          hidden = noAppend,
          toggle = Gate("abbreviateStatusNames", "Abbreviate Names", nil,
              "textStatus", StatusColors, nil),
          fields = {
            Sl("maxStatusNameChars", "Max Length", 3, 20,
                "textStatus", StatusColors, nil),
        }},
        { title = "Status Text Font", preset = "form", hidden = append,
          toggle = Gate("adjustStatusFont", "Adjust Status Font",
              "Enable custom font, border style, and size for status text",
              "textLayout", LayoutRefresh, nil),
          fields = {
            FontDd("statusFont", "Font", "textLayout", LayoutRefresh,
                { desc = "Choose a font for status text" }),
            Dd("statusFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textLayout", LayoutRefresh, nil),
            Sl("statusFontSize", "Font Size", 6, 30, "textLayout", LayoutRefresh, nil),
        }},
        { title = "Additional Options", preset = "form", fields = {
            Sw("capitalizeStatusText", "Capitalize Status Text",
                "textStatus", StatusColors, nil,
                { desc = "Convert status labels (Dead, Offline, AFK) to "
                      .. "uppercase." }),
            Sw("applyStatusColorsToNames", "Apply Status Colors to Names",
                "textStatus", StatusColors, nil,
                { desc = "When enabled, the name text color is changed to the "
                      .. "status color (Dead, Offline, AFK) even when status "
                      .. "text is not shown as a separate overlay.",
                  hidden = append }),
        }},
        { title = "Dead Status Text", preset = "form", fields = {
            Sw("showDeadStatus", "Show Dead Text", "textStatus", DeadShown, nil),
            Color("deadColor", "Dead Color", false, { r = 0.8, g = 0.1, b = 0.1 },
                "textStatus", StatusColors, nil),
        }},
        { title = "Offline Status Text", preset = "form", fields = {
            Sw("showOfflineStatus", "Show Offline Text",
                "textStatus", StatusColors, nil),
            Color("offlineColor", "Offline Color", false,
                { r = 0.5, g = 0.5, b = 0.5 }, "textStatus", StatusColors, nil),
        }},
        { title = "AFK Status", preset = "form", fields = {
            Sw("showAFKStatus", "Show AFK Text", "textStatus", StatusColors, nil),
            Color("afkColor", "AFK Color", false, { r = 0.8, g = 0.6, b = 0 },
                "textStatus", StatusColors, nil),
        }},
    }
end

-- Level Text. Ace order: levelTextHeader (the tab title), showLevelText
-- (2), hideLevelTextAtMaxLevel (2.1), levelTextPosition (4),
-- levelFontGroup (5), levelTextColorGroup (7).
function PAGES.levelText()
    local noShow = function() return not TVal("showLevelText") end
    return {
        { title = "Level Text", preset = "form",
          toggle = Gate("showLevelText", "Show Level Text", nil,
              "textLevel", LevelUpdate, nil),
          fields = {
            Sw("hideLevelTextAtMaxLevel", "Hide at max Level",
                "textLevel", LevelUpdate, nil),
        }},
        { title = "Level Text Position", preset = "form", hidden = noShow,
          fields = {
            Pos({ point = AnchorKey("levelTextPosition", "textLayout", LayoutRefresh),
                  x     = AnchorKey("levelTextX",        "textLayout", LayoutRefresh),
                  y     = AnchorKey("levelTextY",        "textLayout", LayoutRefresh) }),
        }},
        { title = "Level Text Font", preset = "form", hidden = noShow,
          toggle = Gate("adjustLevelFont", "Adjust Level Font", nil,
              "textLayout", LayoutRefresh, nil),
          fields = {
            FontDd("levelFont", "Font", "textLayout", LayoutRefresh),
            Dd("levelFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textLayout", LayoutRefresh, nil),
            Sl("levelFontSize", "Font Size", 6, 30, "textLayout", LayoutRefresh, nil),
        }},
        { title = "Level Text Color", preset = "form", hidden = noShow,
          toggle = Gate("adjustLevelTextColor", "Adjust Level Text Color", nil,
              "textLayout", LayoutRefresh, LevelUpdate),
          fields = {
            Sw("classColorLevelText", "Use Class Colors",
                "textLevel", LevelUpdate, nil),
            Color("levelTextColor", "Level Text Color", false,
                { r = 1, g = 0.82, b = 0 },
                "textLayout", LayoutRefresh, LevelUpdate,
                { hidden = function() return TVal("classColorLevelText") end }),
        }},
    }
end

-- Raid Group Labels. Ace order: groupLabelsHeader (the tab title),
-- showGroupLabels (2), groupLabelYOffset (2.55), groupLabelColor (2.6),
-- groupLabelNumberOnly (2.65), groupLabelFontGroup (3.7).
function PAGES.groupLabels()
    local noShow = function() return not TVal("showGroupLabels") end
    return {
        { title = "Raid Group Labels", preset = "form",
          toggle = Gate("showGroupLabels", "Show Group Labels",
              "Display a label above each raid group column (e.g. \"Group 1\", "
              .. "\"Group 2\"). Only visible when sorting by Group.",
              "textGroupLabels", GroupLabels, nil),
          fields = {
            Sl("groupLabelYOffset", "Offset", -20, 20,
                "textGroupLabels", GroupLabels, nil),
            Color("groupLabelColor", "Label Color", false, { r = 1, g = 1, b = 1 },
                "textGroupLabels", GroupLabels, nil),
            Sw("groupLabelNumberOnly", "Show Number Only",
                "textGroupLabels", GroupLabels, nil,
                { desc = "Display only the group number (e.g. \"1\") instead "
                      .. "of the full label (e.g. \"Group 1\")." }),
        }},
        { title = "Label Font", preset = "form", hidden = noShow,
          toggle = Gate("adjustGroupLabelFont", "Adjust Label Font", nil,
              "textGroupLabels", GroupLabels, nil),
          fields = {
            FontDd("groupLabelFont", "Font", "textGroupLabels", GroupLabels),
            Dd("groupLabelFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textGroupLabels", GroupLabels, nil),
            Sl("groupLabelFontSize", "Font Size", 6, 30,
                "textGroupLabels", GroupLabels, nil),
        }},
    }
end

-- Vehicle Name Text. Ace order: vehicleNameHeader (the tab title),
-- showVehicleName (2), vehicleNamePosition (3), vehicleFontGroup (5.5).
function PAGES.vehicleName()
    local noShow = function() return not TVal("showVehicleName") end
    return {
        { title = "Vehicle Name Text", preset = "form", fields = {
            Sw("showVehicleName", "Show Vehicle Name",
                "textVehicle", VehicleUpdate, nil),
        }},
        { title = "Vehicle Name Position", preset = "form", hidden = noShow,
          fields = {
            Pos({ point = AnchorSub("vehicleNamePosition", "point",
                                    "textLayout", LayoutRefresh),
                  x     = AnchorSub("vehicleNamePosition", "x",
                                    "textLayout", LayoutRefresh),
                  y     = AnchorSub("vehicleNamePosition", "y",
                                    "textLayout", LayoutRefresh) }),
        }},
        { title = "Vehicle Name Font", preset = "form", hidden = noShow,
          toggle = Gate("adjustVehicleFont", "Adjust Vehicle Font", nil,
              "textLayout", LayoutRefresh, nil),
          fields = {
            FontDd("vehicleFont", "Font", "textLayout", LayoutRefresh),
            Dd("vehicleFontBorder", "Font Border", FONT_BORDER_OPTIONS,
                "textLayout", LayoutRefresh, nil),
            Sl("vehicleFontSize", "Font Size", 6, 30, "textLayout", LayoutRefresh, nil),
        }},
    }
end

-- ── The "Apply Changes To" card, as this section shows it ──────
--
-- The Ace gsText branch offered TWO surfaces, not three: text has no
-- unit-frame fan-out (ApplyText takes no writeUF -- the unit frames have
-- their own text handling with different keys), and the note said so. A
-- surface with no desc gets no switch; the second paragraph is the Ace
-- note's own.
local function ScopeCard()
    return BuzzardFramesOptions:GSScopeCard({
        rp  = "Writes the Text section on the base profile and on every Layout.",
        cfg = "Writes every custom frame group, whether or not the group has "
           .. "Text overridden.",
    }, "Unit Frames text settings are not configurable here yet - coming soon.")
end

-- One page per subtab: the "Apply Changes To" card first (the Ace dialog
-- drew it above the tab strip, at the section level), then that subtab's
-- own cards.

-- Mark a group as pinned without editing the builder that made it.
local function Pinned(g)
    if type(g) == "table" then g.pinned = true end
    return g
end

-- ── The section as ONE page ────────────────────────────────────
--
-- The scope strip belongs to the SECTION, not to the subtab on screen --
-- which is where the Ace dialog put it: above the tab strip, stated once.
-- As route subtabs each page could only draw it inside itself, so the same
-- strip appeared under the tabs four times over.
--
-- So the section is one page with an IN-PAGE subtab strip: the strip card
-- above it, then a `subtabs` group carrying what each tab draws. The same
-- shape a buff container page uses for Container Settings / Conditions,
-- and the reason the library has `subtabs` at all.
--
-- Each tab's `groups` is a FUNCTION, so a tab is built when it is selected
-- rather than all of them on every render -- and rebuilt when the page is,
-- which is what the per-route pages got for free.
function BuzzardFramesOptions:GlobalStylesTextPage()
    local tabs = {}
    for _, st in ipairs(BuzzardFramesOptions.GS_TEXT_SUBTABS) do
        tabs[#tabs + 1] = {
            id = st.id, title = st.title,
            groups = function()
                local build = BuzzardFramesOptions:GS() and PAGES[st.id]
                return build and build() or {}
            end,
        }
    end
    return { groups = {
        -- PINNED: the scope strip and the strip of subtabs stay put while
        -- the tab's own cards scroll under them. They are the terms the page
        -- is edited under -- which surfaces a write lands on, and which tab
        -- is on screen -- and scrolling those away leaves the reader
        -- adjusting settings whose terms are somewhere above.
        Pinned(ScopeCard()),
        { subtabKey = "gsText", subtabs = tabs, pinned = true },
    }}
end
