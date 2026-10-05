-- ============================================================
-- BuzzardFramesOptions: Pages_CastBar.lua
-- The Raid/Party Frames > Cast Bars section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_CastBar.lua: the
-- same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by four BuzzardPanel pages -- one per
-- subtab, each a route of its own under `raidPartyFrames/castBar`, drawn
-- as a strip by the `tabs` navigator that node declares (the Ace
-- generalTab / appearanceTab / iconTab / textTab, as routes).
--
-- Storage: rpDB.profile.castBar.* (the global pseudo-layout), or
-- flat.castBar.* when layouts.perLayoutToggles.castBar is on -- castBar
-- keeps a SINGLE section-level toggle by owner ruling, so this is the
-- plain-section pattern: reads and writes both go through
-- BF:GetSectionProfile("castBar", BF:GetModifyingProfile()), the same
-- routed path the Ace page's getIP/writeIP use. Nothing here touches a db
-- table directly, which is what keeps the two panels in step.
--
-- SETTERS, same note as the Ace source: CastBar:Update never reads the
-- profile -- all styling is resolved in CastBar:Layout and cached on the
-- bar. Every change must therefore go through BF:RefreshAllCastBars(),
-- which re-runs Layout; a write alone appears to do nothing until the
-- next reload. That refresh is every field's onChange here, debounced
-- through the SAME BF:DebounceOption("castBar") key the Ace page uses.
--
-- 2026-09-23: that is no longer SUFFICIENT on its own. CastBar:Layout now
-- reads a per-scope resolved block rather than the profile, so the refresh
-- must be preceded by a section-view invalidation or Layout re-applies the
-- values it already had. See the note in Refresh() below for why this page
-- in particular has to do it by hand.
--
-- Fields BIND into ROOT below wherever the stored shape allows, which is
-- what makes right-click Undo and Reset work without per-field
-- declarations. The exceptions, each with `id` + `default` instead:
--   - the three percentage sliders (overlayHeightPct, iconSizePct,
--     bgOpacity): the library's slider displays whole numbers, so they
--     are presented on the 0-100 scale the Ace dialog SHOWED (isPercent)
--     and scaled back to the stored fraction in get/set.
--
-- Ace args keys with no field of their own here, for the audit:
--   generalTab / appearanceTab / iconTab / textTab  -> the four routes
--   positionGroup                     -> the Icon page's Position card
--   header, placementHeader, whoHeader, barHeader, bgHeader,
--   borderHeader, empowerHeader, nameHeader, timerHeader
--                                     -> card titles
--   enabledDesc, empowerInfo          -> notes (kept, as notes)
--   textureBreak                      -> a pure row-break spacer, dropped
--                                        (the flow layout needs none)
--   _sectionTracker                   -> Ace chrome plumbing (stamps
--                                        BF._currentSection for the Ace
--                                        dialog's own header widgets);
--                                        no panel equivalent
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The section profile currently being modified. With the per-layout
-- toggle OFF, GetSectionProfile ignores the flat and returns the global;
-- with it ON it returns the modifying flat's castBar, so the user sees
-- and edits the per-flat copy.
local function GetCB()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("castBar", bf:GetModifyingProfile())
end

-- ── The write-through root ─────────────────────────────────────
--
-- The routed storage wearing the shape of a plain table, so fields can
-- `bind` (and with it get free undo and reset). Reads fall through to the
-- section profile; writes go to the same table, exactly as the Ace
-- writeIP does. The Ace page's per-key getter quirks are reproduced in
-- __index, each copied from the getter it replaces:
--
--   colors       stored as { r=, g=, b=, a= } tables; the panel's color
--                 control speaks { r, g, b, a } arrays, so the two shapes
--                 are converted here (with the Ace getters' own fallback
--                 tables, kept to the digit)
--   fonts         normalized through BF:NormalizeFontName -- a legacy
--                 path or unregistered name would otherwise select
--                 nothing in the dropdown
--   frameLevel /  legacy profiles may lack the key; the Ace getters
--   borderStyle   defaulted them inline
--   showPlayer /  nil reads as true ("not (v == false)"), as in the Ace
--   partyOnly     getters
local COLOR_FALLBACK = {
    -- The Ace getColor fallbacks, verbatim.
    color       = { r = 1,    g = 0.7,  b = 0,    a = 1   },
    bgColor     = { r = 0.08, g = 0.08, b = 0.08            },
    borderColor = { r = 0,    g = 0,    b = 0,    a = 1   },
    pipColor    = { r = 1,    g = 1,    b = 1,    a = 0.8 },
    nameColor   = { r = 1,    g = 1,    b = 1,    a = 1   },
    timerColor  = { r = 1,    g = 1,    b = 1,    a = 1   },
}

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local ip = GetCB()
        local v = ip and ip[k]
        if COLOR_FALLBACK[k] then
            local c = v or COLOR_FALLBACK[k]
            return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
        end
        if k == "nameFont" or k == "timerFont" then
            local bf = BF()
            if bf and bf.NormalizeFontName then return bf:NormalizeFontName(v) end
            return v
        end
        if k == "frameLevel"  then return v or "belowAuras" end
        if k == "borderStyle" then return v or "square"     end
        if k == "showPlayer" or k == "partyOnly" then return not (v == false) end
        return v
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local ip = GetCB()
        if not ip then return end
        if COLOR_FALLBACK[k] and type(v) == "table" then
            -- From the control (or an undo) the value is an array; from a
            -- reset it is the defaults table's named copy. Either way a
            -- FRESH named table is stored, as the Ace setColor does --
            -- never a reference to a table something else holds.
            local a = v.a
            if a == nil then a = v[4] end
            ip[k] = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3], a = a }
        else
            ip[k] = v
        end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library
-- resolves a bind path straight into it.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.castBar
end

local function DefaultCB(key)
    local d = Defaults()
    return d and d[key]
end

-- ── Gates ──────────────────────────────────────────────────────
--
-- `enabled` is the master for the whole section. The Ace page hides the
-- Appearance, Icon and Text TABS while it is off; the panel's tabs are
-- routes and cannot hide, so on those pages every field carries the same
-- Off() predicate the tab carried, and a note says why the page is bare.
local function Off()
    local ip = GetCB()
    return not (ip and ip.enabled)
end

-- off() or not <key> -- the shape of every dependent-field predicate in
-- the Ace source (texture, bgColor, the pip pair, the two text blocks).
local function HiddenUnless(key)
    return function()
        local ip = GetCB()
        return Off() or not (ip and ip[key])
    end
end

local NoIcon   = HiddenUnless("showIcon")
local NoBorder = HiddenUnless("showBorder")

-- ── Side effects ───────────────────────────────────────────────

-- Every change refreshes: see the note at the top of the file. Debounced
-- under the SAME "castBar" key the Ace page uses, so a drag from either
-- panel coalesces into one Layout walk; the preview refresh runs per
-- call, as it does there.
local function Refresh()
    local bf = BF()
    if not bf then return end
    -- INVALIDATE BEFORE THE REFRESH. castBar is excluded from the per-subtab
    -- routing by owner ruling (Core_ProfileAPI.lua:2140), so a write here never
    -- reaches WriteSectionKey and therefore never reaches _InvalidateSectionViews
    -- -- the __newindex above assigns straight into the section table. That was
    -- harmless while CastBar:Layout read the profile live. It stopped being
    -- harmless when CastBar moved to a per-scope resolved block keyed on
    -- (section table, BF._sectionCfgGen) (BuzzardFrames_IndicatorUpdateDB_Plan.md):
    -- identity unchanged AND generation unchanged means ResolveCastBarBlock
    -- (Indicators/CastBar.lua:312) hands back the previous answer and
    -- RefreshAllCastBars faithfully re-applies it. That included the master
    -- switch -- block.enabled (:338) latched, so the Cast Bars on/off toggle did
    -- nothing at all.
    --
    -- BF:RefreshAllCastBars deliberately invalidates nothing of its own, and that
    -- reasoning still stands (Core_Refresh.lua:354-371) -- it is about the
    -- container and the aura position cache, not about section views. So the view
    -- is retired here instead, the way the Borders and Absorbs pages do it
    -- (Pages_Borders.lua:337, Pages_Absorbs.lua:398). Outside the debounce on
    -- purpose: the preview refresh below runs per call and needs it too.
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("castBar") end
    bf:DebounceOption("castBar", function() bf:RefreshAllCastBars() end)
    if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

-- The two context gates are applied in BF:RebindCastBarStatus, not per
-- cast, so flipping one re-binds before the refresh -- same order as the
-- Ace setters.
local function RebindAndRefresh()
    local bf = BF()
    if not bf then return end
    if bf.RebindCastBarStatus then bf:RebindCastBarStatus() end
    Refresh()
end

-- ── Option lists ───────────────────────────────────────────────
--
-- Fixed lists carry the Ace `sorting` order; lists the Ace dialog sorted
-- alphabetically by stored value keep that shown order.

local ANCHOR_OPTIONS = {
    { value = "TOP_OUTSIDE",    text = "Top (Above Frame)" },
    { value = "TOP_INSIDE",     text = "Top (Inside)" },
    { value = "CENTER",         text = "Center" },
    { value = "BOTTOM_INSIDE",  text = "Bottom (Inside, Above Power Bar)" },
    { value = "BOTTOM_OUTSIDE", text = "Bottom (Below Frame)" },
}

local FRAMELEVEL_OPTIONS = {
    { value = "belowAuras", text = "Below Auras" },
    { value = "aboveAuras", text = "Above Auras" },
}

-- SHAPES only. Rounded's two weights are the Thin/Thick strip beside this
-- one -- see Pages_BorderStyle.lua -- rather than a third entry here.
local BORDERSTYLE_OPTIONS = {
    { value = "square",  text = "Square"  },
    { value = "rounded", text = "Rounded" },
}

-- The font-border values, in the order the Ace dialog showed them
-- (alphabetical by stored value, the empty string first).
local FONTBORDER_OPTIONS = {
    { value = "",             text = "None" },
    { value = "MONOCHROME",   text = "Monochrome" },
    { value = "OUTLINE",      text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick Outline" },
}

-- {LEFT, CENTER, RIGHT} with no sorting: the Ace dialog sorted the keys.
local ALIGN_OPTIONS = {
    { value = "CENTER", text = "Center" },
    { value = "LEFT",   text = "Left" },
    { value = "RIGHT",  text = "Right" },
}

local ICONSIDE_OPTIONS = {
    { value = "LEFT",  text = "Left" },
    { value = "RIGHT", text = "Right" },
}

-- LSM lists, resolved every time the menu opens, so media registered
-- after the panel is built still appears. LSM:List returns the names
-- already sorted -- the order the Ace dialog showed.
local function FontOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            -- `font` is the preview: the dropdown draws the row -- and the
            -- control, once picked -- in the face it names, which is what
            -- the Ace font picker did and the whole point of choosing one
            -- by eye rather than by name.
            out[#out + 1] = { value = name, text = name,
                              font = LSM:Fetch("font", name) }
        end
    end
    return out
end

local function StatusbarOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            -- `texture` is the preview: the row draws the bar behind its
            -- name, as the Ace statusbar picker did.
            out[#out + 1] = { value = name, text = name,
                              texture = LSM:Fetch("statusbar", name) }
        end
    end
    return out
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every ordinary field binds into ROOT, refreshes the cast bars, and is
-- combat-locked -- said once each rather than forty times.

local function Sw(bind, label, opts)
    local f = { control = "switch", label = label, bind = bind,
                onChange = Refresh, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sl(bind, label, lo, hi, st, opts)
    local f = { control = "slider", label = label, bind = bind,
                min = lo, max = hi, step = st,
                onChange = Refresh, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Dd(bind, label, options, opts)
    local f = { control = "dropdown", label = label, bind = bind,
                options = options,
                onChange = Refresh, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Col(bind, label, alpha, opts)
    local f = { control = "color", label = label, bind = bind,
                alpha = alpha,
                onChange = Refresh, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A fraction stored 0-1, shown 0-100: the scale the Ace dialog showed
-- (isPercent), and the only one the library's whole-number slider box can
-- display. get/set do the conversion, so what is STORED never changes;
-- `id` + a scaled `default` keep undo and reset working in the shown
-- units.
local function Pct(key, label, lo, hi, st, opts)
    local d = DefaultCB(key)
    local f = {
        control = "slider", label = label, id = key,
        min = lo, max = hi, step = st,
        default = d and math.floor(d * 100 + 0.5) or nil,
        get = function()
            local ip = GetCB()
            local v = ip and ip[key]
            if v == nil then return nil end
            return math.floor(v * 100 + 0.5)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local ip = GetCB()
            if ip then ip[key] = v / 100 end
        end,
        onChange = Refresh, disabled = "combat",
    }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- ── The per-layout row ─────────────────────────────────────────
--
-- Three controls that are ABOUT the settings rather than settings
-- themselves: whether this section is configured per layout, which
-- layout is being edited, and copying what is here onto another layout.
-- The last two hide rather than gray while the first is off, exactly as
-- in the Ace panel. castBar keeps ONE section-level toggle (no
-- per-subtab toggles), so this strip is the Tooltips shape, repeated at
-- the top of each subtab page the way the Ace root row showed above
-- every tab.

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Party flats first, then raid, each alphabetical by name; the ACTIVE
-- layout is tinted green, which is how the Ace dropdown has always shown
-- the difference between "active" and "being edited".
local function FlatOptions()
    local bf = BF()
    local fl = FlatLayouts()
    local activeID = bf and bf.ResolveActiveFlat and bf:ResolveActiveFlat(bf:GetActiveSlot())
    local party, raid = {}, {}
    for id, flat in pairs(fl) do
        if type(flat) == "table" then
            local into = (flat.type == "party") and party or raid
            into[#into + 1] = id
        end
    end
    local function byName(a, b)
        return ((fl[a].name or a):lower()) < ((fl[b].name or b):lower())
    end
    table.sort(party, byName)
    table.sort(raid,  byName)

    local out = {}
    local function add(id)
        local name = fl[id].name or id
        out[#out + 1] = {
            value = id,
            text  = (id == activeID) and ("|cff76CC4B" .. name .. "|r") or name,
        }
    end
    for _, id in ipairs(party) do add(id) end
    for _, id in ipairs(raid)  do add(id) end
    return out
end

-- _modifyingFlat can be unset (a fresh session) or name a layout that
-- has since been deleted, so it falls back the way the Ace dropdown does.
local function CurrentFlat()
    local bf = BF()
    local fl = FlatLayouts()
    local cur = bf and bf._modifyingFlat
    if cur and fl[cur] then return cur end
    if fl.flat_party then return "flat_party" end
    local opts = FlatOptions()
    return opts[1] and opts[1].value
end

local function NotPerLayout()
    local bf = BF()
    return not (bf and bf:IsPerLayoutSection("castBar"))
end

-- Every OTHER layout: the ones a copy could target. No same-type
-- restriction -- the Ace Copy dropdown for this section offered every
-- other Layout, party or raid.
local function CopyTargets()
    local fl  = FlatLayouts()
    local cur = CurrentFlat()
    local t   = {}
    for id, flat in pairs(fl) do
        if id ~= cur and type(flat) == "table" then
            t[#t + 1] = { id = id, name = flat.name or id }
        end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

-- Copy flat.castBar WHOLE from the layout being modified onto another --
-- the same whole-section copy the Ace dropdown ran. Tables are
-- deep-copied, so the two layouts do not end up sharing one table and
-- silently editing each other afterwards. Falls back to the global as
-- the source when the toggle is on but this flat was never seeded.
local function CopyTo(targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    local srcSection = src.castBar
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.castBar end
    if type(srcSection) ~= "table" then return end
    if type(dst.castBar) ~= "table" then dst.castBar = {} end

    for k, v in pairs(srcSection) do
        dst.castBar[k] = (type(v) == "table") and bf:DeepCopy(v) or v
    end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

-- A flat bar rather than a card: this row is ABOUT the settings below
-- it, not one of them. `strip` is the library's preset for exactly that.
local function ScopeStrip()
    return { preset = "strip", fields = {
        { control = "switch", label = "Enable per-Layout Config",
          -- State first, then what it is the state of.
          labelSide = "after",
          -- Off is the shipped state: settings are global until somebody
          -- asks for them not to be.
          id = "perLayoutCastBar", default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give Cast Bars their own "
              .. "settings per Layout (e.g. Party vs Raid).",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSection("castBar")
          end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local bf = BF()
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight
              -- pass-through while that flag is off.
              if bf then bf:_TimeSectionPerLayout("castBar", v) end
          end },

        { control = "dropdown", label = "Modifying",
          -- Labeled above, like any other dropdown, and sized rather
          -- than left to its 200px natural width: a layout name is short.
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited "
              .. "for. The currently active Layout is shown in green.",
          hidden = NotPerLayout, disabled = "combat",
          options = FlatOptions,
          get = function() return CurrentFlat() end,
          set = function(_, ctx, v)
              local bf = BF()
              if not bf then return end
              bf._modifyingFlat = v
              bf:InvalidateRaidProfileCache()
              if bf.UpdateAuraSizeCache then bf:UpdateAuraSizeCache() end
              -- The same post-change chain the Ace dropdown runs: swap
              -- the setup-mode test header to the new layout,
              -- re-position the test anchor to that layout's own saved
              -- anchor, and refresh the preview.
              if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
              if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              -- Every field on this page now reads a different layout's
              -- values, so the page is re-read whole.
              ctx.app:RefreshPage()
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy this Layout's Cast Bar settings onto another "
              .. "Layout. Only available while per-Layout config is on "
              .. "-- without it every Layout already shares one set of "
              .. "settings.",
          disabled = "combat",
          -- Nothing to copy TO is the same as nothing to copy: the
          -- control goes rather than offering an empty list.
          hidden = function()
              return NotPerLayout() or #CopyTargets() == 0
          end,
          options = function()
              local out = {}
              local targets = CopyTargets()
              for _, e in ipairs(targets) do
                  out[#out + 1] = { value = e.id, text = e.name }
              end
              if #targets > 1 then
                  out[#out + 1] = { value = "__all", text = "All Layouts" }
              end
              return out
          end,
          -- A copy is an ACTION, not a setting: the dropdown never shows
          -- a current value, it just offers destinations.
          get = function() return nil end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local from = LayoutName(CurrentFlat())
              local text
              if v == "__all" then
                  text = ("Copy all Cast Bar settings from \"%s\" to "
                      .. "all other Layouts? This overwrites every "
                      .. "Cast Bar setting on them."):format(from)
              else
                  text = ("Copy all Cast Bar settings from \"%s\" to "
                      .. "\"%s\"? This overwrites every Cast Bar "
                      .. "setting on it."):format(from, LayoutName(v))
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do CopyTo(e.id) end
                  else
                      CopyTo(v)
                  end
              end)
          end },
    }}
end

-- The Ace panel hides the Appearance, Icon and Text tabs entirely while
-- cast bars are off. The panel's tabs are routes and do not hide, so
-- those pages carry this note instead -- shown only while the feature is
-- off, when everything below it is hidden.
local function DisabledNote()
    return { preset = "bare", fields = {
        { control = "note", wide = true,
          hidden = function() return not Off() end,
          text = "Cast Bars are disabled. Turn on \"Enable Cast Bars\" "
              .. "on the General tab to edit these settings." },
    }}
end

-- ── The four pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages (the Pages_Icons pattern).
BuzzardFramesOptions.CASTBAR_SUBTABS = {
    { id = "general",    title = "General" },
    { id = "appearance", title = "Appearance" },
    { id = "icon",       title = "Icon" },
    { id = "text",       title = "Text" },
}

local PAGES = {}

function PAGES.general()
    return {
        { title = "Cast Bars", preset = "form", fields = {
            Sw("enabled", "Enable Cast Bars", {
                desc = "Show a cast bar on each party/raid frame.\n\n"
                    .. "|cffffd100While this is off the feature costs nothing.|r "
                    .. "No spell cast events are registered and no cast bar widgets are "
                    .. "created until you turn it on." }),
            -- Context gate: only in a party group, not a raid. Shown only
            -- while per-Layout configuration is OFF -- when it is ON the
            -- user assigns a cast-bar-enabled Layout per context
            -- directly, so a party-only gate would be redundant and
            -- confusing. Both gates are applied in
            -- BF:RebindCastBarStatus, not per cast.
            Sw("partyOnly", "Enable for Party only (recommended)", {
                wide = true, onChange = RebindAndRefresh,
                hidden = function()
                    local bf = BF()
                    return Off() or (bf and bf:IsPerLayoutSection("castBar"))
                end,
                desc = "Only show cast bars while you are in a party. In a raid group the "
                    .. "feature turns itself off completely -- no cast events are registered -- "
                    .. "so a full raid never pays for it." }),
            -- Context gate: only inside a PvP instance. Always shown
            -- (while enabled). Battlegrounds are RAID groups, so they
            -- are additionally gated by partyOnly above.
            Sw("pvpOnly", "Enable for PvP only", {
                wide = true, onChange = RebindAndRefresh, hidden = Off,
                desc = "Only show cast bars while you are inside a PvP instance. "
                    .. "Outside PvP instances the feature turns itself off completely -- no "
                    .. "cast events are registered.\n\n"
                    .. "|cff888888Battlegrounds are raid groups, so with |cffffffffEnable for "
                    .. "Party only|r|cff888888 on they stay off there -- only arenas qualify. "
                    .. "Turn Party only off to include battlegrounds.|r" }),
            -- enabledDesc: shown whether or not the feature is on, as in
            -- the Ace page.
            { control = "note", wide = true,
              text = "Cast bars for the player, target and focus frames are "
                  .. "configured separately under Unit Frames." },
            Pct("overlayHeightPct", "Height", 5, 100, 5, {
                hidden = Off,
                desc = "Height of the cast bar, as a fraction of the health bar's height." }),
            Sl("holdTime", "Hold After Interrupt", 0, 3, 0.1, {
                hidden = Off,
                desc = "How long the bar stays visible after a cast is interrupted or "
                    .. "fails, so you can actually see it happen. Set to 0 to hide "
                    .. "immediately." }),
        }},
        { title = "Position", preset = "form", fields = {
            Dd("overlayAnchor", "Position", ANCHOR_OPTIONS, {
                hidden = Off,
                desc = "Where the cast bar sits.\n\n"
                    .. "|cffffffffInside|r positions draw over the health bar. "
                    .. "|cffffffffAbove|r and |cffffffffBelow|r float clear of the frame.\n\n"
                    .. "|cff888888Bottom (Inside) sits above the power bar automatically, "
                    .. "and stays correct when the power bar shows or hides.|r\n\n"
                    .. "The cast bar never reserves space in any position -- nothing moves "
                    .. "when a cast starts or stops." }),
            Sl("overlayYOffset", "Y Offset", -40, 40, 1, {
                hidden = Off,
                desc = "Nudge the cast bar up or down from its position." }),
            Dd("frameLevel", "Frame Level", FRAMELEVEL_OPTIONS, {
                hidden = Off,
                desc = "What the cast bar draws on top of when it overlaps something.\n\n"
                    .. "|cffffffffBelow Auras|r: aura icons cover the cast bar. The cast bar "
                    .. "still draws above all text, names and status icons.\n\n"
                    .. "|cffffffffAbove Auras|r: the cast bar covers everything, including aura icons.\n\n"
                    .. "|cff888888The out-of-range dimming always stays on top in both modes.|r" }),
        }},
        { title = "Which Units", preset = "form", fields = {
            Sw("showPlayer", "Show for Self", { hidden = Off }),
            Sw("showPets", "Show On Pet Frames", { hidden = Off }),
            Sw("healersOnly", "Show Only for Healers", {
                hidden = Off,
                desc = "Only show cast bars on frames whose unit is a healer." }),
        }},
    }
end

function PAGES.appearance()
    -- Shape and weight, over the one `borderStyle` key. ROOT's __index
    -- supplies the "square" fallback for a legacy profile that has none,
    -- and its __newindex is the combat guard, so both go through it.
    local borderStyleField, borderWeightField =
        BuzzardFramesOptions:BorderStyleFields({
            id = "borderStyle", options = BORDERSTYLE_OPTIONS,
            hidden = NoBorder, onChange = Refresh,
            get = function() return Root().borderStyle end,
            set = function(_, _, v) Root().borderStyle = v end,
        })

    return {
        DisabledNote(),
        { title = "Bar", preset = "form", fields = {
            Col("color", "Bar Color", true, { hidden = Off }),
            Sw("useCustomTexture", "Use Custom Texture", { hidden = Off }),
            Dd("texture", "Bar Texture", StatusbarOptions,
               { hidden = HiddenUnless("useCustomTexture") }),
        }},
        { title = "Background", preset = "form", fields = {
            Sw("useCustomBgColor", "Use Custom Background Color", { hidden = Off }),
            Col("bgColor", "Background Color", false,
                { hidden = HiddenUnless("useCustomBgColor") }),
            Pct("bgOpacity", "Background Opacity", 0, 100, 5, { hidden = Off }),
        }},
        { title = "Border", preset = "form", fields = {
            Sw("showBorder", "Show Border", { hidden = Off }),
            borderStyleField,
            borderWeightField,
            -- A stepper, not a slider: four whole numbers, and the reader
            -- wants "one more pixel" rather than a position on a track.
            { control = "stepper", label = "Border Thickness",
              bind = "borderThickness", min = 1, max = 4, step = 1,
              onChange = Refresh, disabled = "combat",
              -- Rounded styles bake their band weight into the art (2
              -- texels for Rounded, 3 for Rounded Thick), so this does
              -- nothing there -- the rounded weight is the Thin/Thick
              -- strip under the style. Same predicate the frame border
              -- uses.
              hidden = function()
                  local ip = GetCB()
                  if NoBorder() then return true end
                  local bf = BF()
                  return bf and bf.IsRoundedBorderStyle
                      and bf.IsRoundedBorderStyle(ip and ip.borderStyle) or false
              end },
            Col("borderColor", "Border Color", true, { hidden = NoBorder }),
        }},
    }
end

function PAGES.icon()
    return {
        DisabledNote(),
        { title = "Spell Icon", preset = "form", fields = {
            Sw("showIcon", "Show Spell Icon", {
                hidden = Off,
                desc = "Show the spell's icon next to the cast bar." }),
            Pct("iconSizePct", "Icon Size", 25, 300, 5, {
                hidden = NoIcon,
                desc = "Icon size relative to the height of the cast bar.\n\n"
                    .. "|cff888888The bar narrows to make room, so the icon and bar together "
                    .. "always span the frame width.|r" }),
        }},
        -- positionGroup (inline in the Ace page), as a card of its own.
        { title = "Position", preset = "form", fields = {
            Dd("iconSide", "Icon Side", ICONSIDE_OPTIONS, { hidden = NoIcon }),
            Sl("iconXOffset", "Icon X Offset", -40, 40, 1, { hidden = NoIcon }),
            Sl("iconYOffset", "Icon Y Offset", -40, 40, 1, { hidden = NoIcon }),
            Sl("iconGap", "Icon Gap", 0, 20, 1, {
                hidden = NoIcon,
                desc = "Space between the icon and the bar, in pixels." }),
        }},
    }
end

function PAGES.text()
    local noName  = HiddenUnless("showSpellName")
    local noTimer = HiddenUnless("showTimer")
    return {
        DisabledNote(),
        { title = "Cast Name", preset = "form", fields = {
            Sw("showSpellName", "Cast Name", { hidden = Off }),
            Dd("nameAlign", "Name Alignment", ALIGN_OPTIONS, { hidden = noName }),
            Dd("nameFont", "Name Font", FontOptions, { hidden = noName }),
            Sl("nameFontSize", "Name Font Size", 6, 24, 1, { hidden = noName }),
            Dd("nameFontBorder", "Name Font Border", FONTBORDER_OPTIONS,
               { hidden = noName }),
            Col("nameColor", "Name Color", true, { hidden = noName }),
        }},
        { title = "Cast Time", preset = "form", fields = {
            Sw("showTimer", "Show Cast Time", { hidden = Off }),
            Dd("timerAlign", "Time Alignment", ALIGN_OPTIONS, { hidden = noTimer }),
            Dd("timerFont", "Time Font", FontOptions, { hidden = noTimer }),
            Sl("timerFontSize", "Time Font Size", 6, 24, 1, { hidden = noTimer }),
            Dd("timerFontBorder", "Time Font Border", FONTBORDER_OPTIONS,
               { hidden = noTimer }),
            Col("timerColor", "Time Color", true, { hidden = noTimer }),
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:CastBarPage(subtabId)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end

    local groups = { ScopeStrip() }
    for _, g in ipairs(build()) do groups[#groups + 1] = g end

    return {
        -- The routed storage, wearing the shape of a table. Every `bind`
        -- on this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- which is
        -- what makes the right-click "Reset to default" work on every
        -- bound field without any of them declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end
