-- ============================================================
-- BuzzardFramesOptions: Pages_AuraText.lua
-- The Raid/Party Frames > Aura Cooldown Text section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_AuraText.lua:
-- the same settings, the same storage and the same side effects, with
-- the AceConfig args table replaced by five BuzzardPanel pages -- one
-- per subtab, each a route of its own under `raidPartyFrames/auraText`,
-- drawn as a strip by the `tabs` navigator that node declares.
--
-- Storage: rpDB.profile.auraText.<subcat>.* (the global pseudo-layout),
-- or flat.auraText.<subcat>.* when layouts.perLayoutToggles.auraText is
-- on. auraText is nested ONE LEVEL DEEPER than the other sections: every
-- key belongs to a sub-category (stackText / global / buffs / debuffs /
-- bigDef, per BF.AURA_TEXT_SUBCATEGORY_OF), reads resolve through
-- BF:GetSectionProfile("auraText", ...) and the two-tier metatable
-- fallback, and writes land on the flat's own sparse sub-table via
-- BF:GetOrCreateAuraTextSubCategory (per-Layout ON) or on
-- rpDB.profile.auraText.<subcat> (OFF) -- exactly the routing the Ace
-- page's getATKey/setATKey use. Nothing here touches a db table
-- directly, which is what keeps the two panels in step.
--
-- Fields BIND through ROOT below with dotted paths ("buffs.buffFontSize"),
-- so right-click Undo and Reset work without per-field declarations, and
-- the page's `defaults` is BuzzardFrames' own NESTED auraText defaults
-- table -- the same shape, so a bind path resolves straight into it.
--
-- THE MODE SWITCH (globalAuraTextConfig, a TOP-LEVEL auraText key): when
-- ON, one unified "Duration Text" subtab configures every aura type;
-- when OFF, per-type subtabs (Buffs / Debuffs / Big Defensive) do. The
-- Ace dialog HIDES the inapplicable subtabs; the panel's subtabs are
-- ROUTES and routes are static, so the pragmatic answer taken here is:
--
--   * all five subtab routes are always declared (the strip always shows
--     five tabs);
--   * each page builder checks the mode at BUILD time -- a subtab that
--     does not apply in the current mode renders only its scope strip,
--     the mode switch and a short note saying where the settings are;
--   * the mode switch's setter calls ctx.app:Invalidate("bfAuraTextMode")
--     (the panel's NotifyChangeSafe), which re-calls every lazy page
--     builder, and then NAVIGATES to the subtab that just became the
--     right one -- the panel equivalent of AceConfigDialog landing on
--     the first visible tab when the current one hides.
--
--   The per-Layout toggle and the Modifying dropdown ALSO Invalidate
--   rather than merely RefreshPage: with per-Layout on, each flat can
--   hold its own globalAuraTextConfig, so changing which storage is
--   read can change the mode and with it the page's SHAPE.
--
--   Known limitation, recorded in the notes: a mode flip made from the
--   ACE panel while this panel is open is not noticed until this panel
--   next rebuilds (navigate, reopen, or any Invalidate) -- the reverse
--   has always been true of the Ace dialog too.
--
-- Ace args keys with no field of their own here, for the audit:
--   durationText / buffDurationText / debuffDurationText /
--   bigDefDurationText / stackText     -> the five routes
--   durationTextHeader, stackHeader, stackFontHeader,
--   stackAnchorHeader                  -> card titles
--   globalFontGroup / buffFontGroup / debuffFontGroup / bigDefFontGroup
--   / stackFontGroup / thresholdColorGroup
--                                      -> folded into the gated
--                                         "Duration Text" / "Stack Text"
--                                         cards (see the notes)
--   cooldownSwipeGroup                 -> the "Cooldown Swipe" card
--   stackDesc                          -> the note atop the Stack page
--   stackFontSpacer                    -> a pure spacer, dropped (the
--                                         flow layout needs none)
--   debuffThresholdBorderEnabled       -> hidden = true in the source
--                                         (feature removed); it never
--                                         renders, so it has no field
--   _sectionTracker / _subcatTracker   -> Ace chrome plumbing (stamps
--                                         BF._currentSection and
--                                         BF._currentAuraTextSubcat for
--                                         the Ace dialog's own injected
--                                         widgets); no panel equivalent
--                                         -- each subtab here is a route
--                                         that KNOWS its sub-category
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- The auraText section as the modifying Layout reads it: the merged view
-- (per-Layout OFF ignores the flat and returns the global).
local function GetAT()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("auraText", bf:GetModifyingProfile())
end

-- One sub-category of that view. May be the flat's own sub-table (with
-- its fallback metatable) or the global's -- either way READ ONLY here.
local function GetSub(subcat)
    local at = GetAT()
    return at and at[subcat]
end

-- The mode: globalAuraTextConfig defaults ON, so nil reads as true --
-- the Ace isGlobal predicate, kept to the digit.
local function IsGlobalMode()
    local at = GetAT() or {}
    return at.globalAuraTextConfig ~= false
end

-- ── Key classification ─────────────────────────────────────────
--
-- The stored color shape is { r=, g=, b=, a= } named tables; the
-- panel's color control speaks { r, g, b, a } arrays. Which keys are
-- colors is knowable up front, so the conversion lives in the routed
-- root rather than on twelve fields.
local COLOR_KEYS = {}
for _, k in ipairs({
    "globalFontColor", "globalThresholdColor", "globalThreshold2Color",
    "buffFontColor",   "buffThresholdColor",   "buffThreshold2Color",
    "debuffFontColor", "debuffThresholdColor", "debuffThreshold2Color",
    "bigDefFontColor", "bigDefThresholdColor", "bigDefThreshold2Color",
}) do COLOR_KEYS[k] = true end

-- Fonts store an LSM display name, but legacy profiles hold a file path
-- or "DEFAULT"; the Ace getters normalize on read so the picker never
-- renders blank, and the aura default is the bundled Roboto Condensed
-- Bold. Same normalization, same fallback.
local FONT_KEYS = {
    globalDurationFont = true, buffDurationFont = true,
    debuffDurationFont = true, bigDefDurationFont = true,
    stackTextFont = true,
}

-- Threshold pairing: the secondary threshold must stay BELOW the
-- primary. The Ace page clamps in both directions -- the secondary's
-- get/set clamp against primary-1, and lowering the primary drags a now-
-- too-high secondary down with it.
local PRIMARY_TO_SECONDARY = {
    globalThresholdColorThreshold = "globalThreshold2ColorThreshold",
    buffThresholdColorThreshold   = "buffThreshold2ColorThreshold",
    debuffThresholdColorThreshold = "debuffThreshold2ColorThreshold",
    bigDefThresholdColorThreshold = "bigDefThreshold2ColorThreshold",
}
local SECONDARY_TO_PRIMARY = {}
for p, s in pairs(PRIMARY_TO_SECONDARY) do SECONDARY_TO_PRIMARY[s] = p end

-- Turning "Hide Duration Text Above 1 Minute" ON auto-disables the
-- matching dispel-color toggle. Both dispel toggles are REMOVED from
-- the UI (12.1 cut), but the scrub keeps cleaning stale true values out
-- of existing profiles -- copied from the Ace setter, not summarised.
local HIDE_TO_DISPEL = {
    debuffHideDurationAbove1Min = "debuffDurationDispelColor",
    globalHideDurationAbove1Min = "globalDebuffDurationDispelColor",
}

-- ── The routed write ───────────────────────────────────────────
--
-- The Ace setATKey, as a function of (subcat, key, value): per-Layout ON
-- lazily materialises flat.auraText.<subcat> so the write lands on the
-- flat's sparse rawkeys; OFF writes the always-populated global
-- sub-table. The matching cache invalidation runs with the write, in
-- the same order.
local function WriteSub(subcat, key, val)
    local bf = BF()
    if not bf then return end
    if bf:IsPerLayoutSection("auraText") then
        local flat = bf:GetModifyingProfile()
        local sub  = bf:GetOrCreateAuraTextSubCategory(flat, subcat)
        if sub then sub[key] = val end
        bf:InvalidateFlatAuraCache(flat)
    else
        local gp = bf.rpDB.profile.auraText
        if gp then
            gp[subcat] = gp[subcat] or {}
            gp[subcat][key] = val
        end
        bf:InvalidateGlobalSectionFlatCaches("auraText")
    end
end

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the
-- page's db. auraText has no such table -- reads come from a merged
-- view that must never be written, and writes route per sub-category --
-- so the page hands the library a table shaped like the one it wants
-- and routed like the one Buzzard Frames has. ROOT answers each
-- sub-category name with a wrapper of its own; the wrapper reads the
-- merged view and writes through WriteSub, converting color shapes,
-- normalizing fonts and clamping thresholds exactly where the Ace
-- get/set pairs did.
local subCache = {}

local function SubTable(subcat)
    local w = subCache[subcat]
    if w then return w end
    w = setmetatable({}, {
        __index = function(_, k)
            local sub = GetSub(subcat)
            local v = sub and sub[k]
            if COLOR_KEYS[k] then
                -- The Ace getColor fallback, verbatim.
                local c = v or { r = 1, g = 1, b = 1 }
                return { c.r, c.g, c.b, c.a or 1 }
            end
            if FONT_KEYS[k] then
                local bf = BF()
                if bf and bf.NormalizeFontName then
                    return bf:NormalizeFontName(v, "Roboto Condensed Bold")
                end
                return v
            end
            local pri = SECONDARY_TO_PRIMARY[k]
            if pri then
                -- The clamped read of the secondary threshold, with the
                -- Ace getter's own inline fallbacks.
                local limit = math.max(1, ((sub and sub[pri]) or 8) - 1)
                return math.min(v or 4, limit)
            end
            return v
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            if COLOR_KEYS[k] and type(v) == "table" then
                -- From the control (or an undo) the value is an array;
                -- from a reset it is the defaults table's named copy.
                -- Either way a FRESH named table is stored, as the Ace
                -- setColor_Threshold does -- never a reference to a
                -- table something else holds.
                local a = v.a
                if a == nil then a = v[4] end
                v = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3], a = a }
            end
            local pri = SECONDARY_TO_PRIMARY[k]
            if pri and type(v) == "number" then
                -- The secondary threshold never reaches the primary.
                local sub = GetSub(subcat)
                local limit = math.max(1, ((sub and sub[pri]) or 8) - 1)
                v = math.min(v, limit)
            end
            WriteSub(subcat, k, v)
            local sec = PRIMARY_TO_SECONDARY[k]
            if sec and type(v) == "number" then
                -- Lowering the primary drags the secondary down under it.
                local sub = GetSub(subcat)
                local cur = sub and sub[sec]
                if cur and cur >= v then
                    WriteSub(subcat, sec, math.max(1, v - 1))
                end
            end
            if v == true and HIDE_TO_DISPEL[k] then
                -- The dispel-color scrub -- see HIDE_TO_DISPEL above.
                WriteSub(subcat, HIDE_TO_DISPEL[k], false)
            end
            bf:InvalidateRaidProfileCache()
        end,
    })
    subCache[subcat] = w
    return w
end

local SUBCAT_NAMES = {
    stackText = true, global = true, buffs = true,
    debuffs = true, bigDef = true,
}

local ROOT = setmetatable({}, {
    __index = function(_, k)
        if SUBCAT_NAMES[k] then return SubTable(k) end
        -- Top-level auraText key (globalAuraTextConfig).
        local at = GetAT()
        return at and at[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if not bf then return end
        -- The Ace setATKey's top-level branch: write through the merged
        -- view (per-Layout ON lands on the flat, OFF on the global) and
        -- invalidate the matching caches.
        local at = GetAT()
        if at then at[k] = v end
        if bf:IsPerLayoutSection("auraText") then
            bf:InvalidateFlatAuraCache(bf:GetModifyingProfile())
        else
            bf:InvalidateGlobalSectionFlatCaches("auraText")
        end
        bf:InvalidateRaidProfileCache()
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the
-- single source, and it is the same NESTED shape as the storage, so the
-- library resolves a dotted bind path straight into it.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.auraText
end

local function DefaultSub(subcat, key)
    local d = Defaults()
    d = d and d[subcat]
    return d and d[key]
end

local function DefaultTop(key)
    local d = Defaults()
    return d and d[key]
end

-- ── Side effects ───────────────────────────────────────────────
--
-- The Ace page dispatches every refresh PER SUB-CATEGORY so a buff
-- setting only re-lays buff indicators: per-type keys go to their
-- RefreshXOnly, global and stackText fall through to RefreshAllAuras.
-- Copied whole, debounce timers included -- those timers are the Ace
-- builder's own locals, so this file carries its own pair under the
-- same delays rather than pretending to share them.

local SUBCAT_REFRESH = {
    buffs   = "RefreshBuffsOnly",
    debuffs = "RefreshDebuffsOnly",
    bigDef  = "RefreshBigDefOnly",
}

local function SubcatOf(key)
    local bf = BF()
    local m  = bf and bf.AURA_TEXT_SUBCATEGORY_OF
    return m and m[key]
end

-- Repaint ONLY the touched aura type on the Options preview frames --
-- a no-op while the preview is not showing.
local function RefreshPreviewForSubcat(subcat)
    local bf = BF()
    if not (bf and subcat) then return end
    if     subcat == "buffs"     then
        if bf.RefreshPreviewDummyBuffs     then bf:RefreshPreviewDummyBuffs()     end
    elseif subcat == "debuffs"   then
        if bf.RefreshPreviewDummyDebuffs   then bf:RefreshPreviewDummyDebuffs()   end
    elseif subcat == "bigDef"    then
        if bf.RefreshPreviewDummyBigDef    then bf:RefreshPreviewDummyBigDef()    end
    elseif subcat == "stackText" then
        if bf.RefreshPreviewDummyStackText then bf:RefreshPreviewDummyStackText() end
    elseif subcat == "global"    then
        if bf.RefreshPreviewDummyGlobal    then bf:RefreshPreviewDummyGlobal()    end
    end
end

-- The scoped refresh, immediate. The swipe/spark toggles use this --
-- one click, one refresh, as in the Ace source.
local function DispatchRefreshForKey(key)
    local bf = BF()
    if not bf then return end
    local subcat = key and SubcatOf(key)
    local fnName = subcat and SUBCAT_REFRESH[subcat]
    if fnName and bf[fnName] then
        bf[fnName](bf)
    else
        bf:RefreshAllAuras()
    end
end

-- The scoped refresh, debounced: sliders fire their setter on EVERY
-- drag tick, and a full frame walk per tick stutters the client. Value
-- writes stay immediate; pending refreshes accumulate by method name so
-- rapid edits across sub-categories each land once, and RefreshAllAuras
-- supersedes the narrower ones. Combat is checked at fire time, as in
-- the source.
local _atDispatchTimer
local _atPendingFns = {}
local function DispatchRefreshForKeyDebounced(key)
    local bf = BF()
    if not bf then return end
    local subcat = key and SubcatOf(key)
    local fnName = subcat and SUBCAT_REFRESH[subcat]
    if not (fnName and bf[fnName]) then fnName = "RefreshAllAuras" end
    _atPendingFns[fnName] = true
    if _atDispatchTimer then _atDispatchTimer:Cancel() end
    _atDispatchTimer = C_Timer.NewTimer(0.15, function()
        _atDispatchTimer = nil
        if InCombatLockdown() then return end
        local b = BF()
        if not b then return end
        if _atPendingFns.RefreshAllAuras then
            b:RefreshAllAuras()
        else
            for fn in pairs(_atPendingFns) do
                if b[fn] then b[fn](b) end
            end
        end
        wipe(_atPendingFns)
    end)
end

-- The threshold family (enables, colors, thresholds, hide-above-1min)
-- coalesces into one RebuildExpiringColorCurves + scoped refresh +
-- preview repaint after 50ms, per touched sub-category -- so a drag
-- that spans a buff slider and a debuff slider inside the window still
-- refreshes both.
local _thresholdRefreshTimer
local _thresholdPendingSubcats = {}
local function ThresholdRefreshDebounced()
    if _thresholdRefreshTimer then _thresholdRefreshTimer:Cancel() end
    _thresholdRefreshTimer = C_Timer.NewTimer(0.05, function()
        _thresholdRefreshTimer = nil
        local bf = BF()
        if not bf then return end
        bf:RebuildExpiringColorCurves()
        for subcat in pairs(_thresholdPendingSubcats) do
            local fnName = SUBCAT_REFRESH[subcat]
            if fnName and bf[fnName] then
                bf[fnName](bf)
            else
                bf:RefreshAllAuras()
                break -- RefreshAllAuras covers everything
            end
        end
        for subcat in pairs(_thresholdPendingSubcats) do
            RefreshPreviewForSubcat(subcat)
            _thresholdPendingSubcats[subcat] = nil
        end
    end)
end

local function ThresholdRefreshDebouncedFor(key)
    local subcat = key and SubcatOf(key)
    if subcat then _thresholdPendingSubcats[subcat] = true end
    ThresholdRefreshDebounced()
end

-- The two onChange shapes, matching the two Ace setter shapes. Both are
-- declared with refresh = "write" on their fields: the heavy work
-- debounces ITSELF above (0.15s / 0.05s, the Ace delays), and running
-- the handler inline is what keeps the preview repaint on every drag
-- tick -- the live feedback the Ace setters give.
local function Effect(key)
    return function()
        DispatchRefreshForKeyDebounced(key)
        RefreshPreviewForSubcat(SubcatOf(key))
    end
end

local function ThresholdEffect(key)
    return function() ThresholdRefreshDebouncedFor(key) end
end

-- ── Option lists ───────────────────────────────────────────────

-- The LSM font list, resolved every time the menu opens, so media
-- registered after the panel is built still appears. The names are the
-- stored values, as with every LSM30_Font picker.
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

-- The font-border values, in the order the Ace dialog showed them
-- (alphabetical by stored value, the empty string first).
local FONT_BORDER_OPTIONS = {
    { value = "",                         text = "None" },
    { value = "MONOCHROME",               text = "Monochrome" },
    { value = "OUTLINE",                  text = "Outline" },
    { value = "OUTLINE, MONOCHROME",      text = "Outline + Monochrome" },
    { value = "THICKOUTLINE",             text = "Thick Outline" },
    { value = "THICKOUTLINE, MONOCHROME", text = "Thick Outline + Monochrome" },
}

-- ── The scope strip ────────────────────────────────────────────
--
-- auraText carries ONE section-level per-Layout toggle, but its Copy
-- follows the SUBTAB: each subtab is one sub-category, and the copy
-- moves that sub-category and no other -- which is what stops copying
-- Stack Text onto the raid Layout quietly overwriting its Debuff
-- duration colors. The Ace page tracks the visible subtab through
-- BF._currentAuraTextSubcat; here every subtab is a route that closes
-- over its own sub-category, so no tracking is needed.

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Party flats first, then raid, each alphabetical; the ACTIVE Layout is
-- tinted green, which is how the Ace dropdown has always shown the
-- difference between "active" and "being edited".
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

-- _modifyingFlat can be unset (a fresh session) or name a Layout that
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
    return not (bf and bf:IsPerLayoutSection("auraText"))
end

-- Every OTHER Layout. NO same-type restriction: auraText keys are
-- type-neutral (stack fonts and threshold colors are party/raid-
-- agnostic), exactly as the Ace copy helper says.
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

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

-- Copy ONE SUB-CATEGORY from the Layout being modified onto another --
-- the Ace doCopy, kept to the digit. The source is read through
-- GetSectionProfile so an un-materialised sub-category on the source
-- flat falls through to the global and a pristine source still copies
-- populated values; the destination is lazily materialised with its
-- metatable chain wired, then written rawkey by rawkey. Tables are
-- deep-copied so the two Layouts never share one table.
local function CopySubcatTo(subcat, targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local srcFlat, dstFlat = fl[CurrentFlat()], fl[targetID]
    if not (bf and srcFlat and dstFlat) then return end

    local srcSection = bf:GetSectionProfile("auraText", srcFlat)
    local srcSub     = srcSection and srcSection[subcat]
    if type(srcSub) ~= "table" then return end
    local dstSub = bf:GetOrCreateAuraTextSubCategory(dstFlat, subcat)
    if type(dstSub) ~= "table" then return end

    for k, v in pairs(srcSub) do
        dstSub[k] = (type(v) == "table") and bf:DeepCopy(v) or v
    end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

-- What the Copy control calls this subtab's settings -- the Ace
-- AURA_TEXT_SUBCAT_LABELS, verbatim.
local SUBCAT_COPY_LABELS = {
    stackText = "Stack Text",
    global    = "Duration Text",
    buffs     = "Buffs",
    debuffs   = "Debuffs",
    bigDef    = "Big Defensive",
}

-- The Modifying dropdown's post-change chain -- and the mode itself can
-- change with the storage (each flat can hold its own
-- globalAuraTextConfig when per-Layout is on), so the page is REBUILT,
-- not merely re-read.
local function InvalidateMode(ctx)
    ctx.app:Invalidate("bfAuraTextMode")
    -- And the ROUTES, not only the pages: which subtabs exist follows the
    -- mode (AURATEXT_SUBTABS' `when` predicates), and the mode follows the
    -- storage -- so the Modifying dropdown and the per-Layout toggle can
    -- change the set of tabs without touching the mode switch itself.
    if ctx and ctx.app then
        BuzzardFramesOptions:RebuildRoutes(ctx.app)
    end
end

-- ── The mode switch ────────────────────────────────────────────
--
-- The Ace panel injects this into the per-Layout row's own group, on its
-- own full-width line under the toggle and the Copy dropdown (order 0.7),
-- and it governs WHICH SUBTABS EXIST: on, the unified "Duration Text"
-- tab; off, the three per-type tabs. AURATEXT_SUBTABS carries the same
-- rule as `when` predicates, so the tabs appear and disappear here as
-- they do there.
--
-- Its setter is the Ace setter's write and side effects, with
-- NotifyChangeSafe replaced by InvalidateMode -- which rebuilds the route
-- tree as well as the pages, because the set of subtabs is part of what
-- changed -- and a Navigate off a tab that has just stopped existing.
local PER_TYPE_SUBTABS = {
    buffDurationText = true, debuffDurationText = true,
    bigDefDurationText = true,
}

local function ModeSwitchField(subtabId)
    -- Shaped like the per-Layout toggle above it, because it sits under it
    -- and the two must line up: `labelSide = "after"` puts the switch first
    -- and the label beside it, which is what a switch reads like in a
    -- left-placement preset -- without it the strip puts the label in the
    -- label column and the row starts somewhere else entirely.
    --
    -- `newRow` rather than `wide`: on a switch `wide` sizes the field for
    -- its label and the packer may still flow it up beside the Modifying
    -- dropdown. A break says what is meant -- this row is UNDER those, not
    -- with them.
    return { control = "switch", newRow = true, labelSide = "after",
        label = "Use global duration text config for all aura types",
        id = "globalAuraTextConfig",
        default = DefaultTop("globalAuraTextConfig"),
        -- Ace's sky blue, as the per-Layout toggle beside it wears: this
        -- switch configures the CONFIGURATION rather than the addon.
        labelColor = { 0.53, 0.81, 0.92, 1.00 },
        desc = "When enabled, a unified \"Duration Text\" subtab "
            .. "applies the same font, threshold, and swipe settings "
            .. "to Buffs, Debuffs, Big Defensives, Private Auras, and "
            .. "Crowd Control. Disable this to configure each aura "
            .. "type independently (per-type subtabs appear instead).",
        disabled = "combat",
        get = function() return IsGlobalMode() end,
        set = function(_, ctx, v)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            local at = GetAT()
            if at then at.globalAuraTextConfig = v end
            bf:InvalidateRaidProfileCache()
            bf:RefreshAllAuras()
            InvalidateMode(ctx)
            -- The subtab under the cursor may have just stopped existing;
            -- land on the one that took over from it, in the section the
            -- reader is actually in. This page is built under a Custom
            -- Frame Group scope too, and naming the Raid/Party section
            -- there would move them to a different set of frames.
            local root = (bf.BFOScopeFlat and "customFrames")
                         or "raidPartyFrames"
            if v and PER_TYPE_SUBTABS[subtabId] then
                ctx.app:Navigate(root, "auraText", "durationText")
            elseif (not v) and subtabId == "durationText" then
                ctx.app:Navigate(root, "auraText", "buffDurationText")
            end
        end }
end

-- A flat bar rather than a card: this row is ABOUT the settings below
-- it, not one of them. `strip` is the library's preset for exactly that.
local function ScopeStrip(subcat, subtabId)
    local copyLabel = SUBCAT_COPY_LABELS[subcat] or "Aura Cooldown Text"
    -- `scopeStrip` marks this card as the RAID/PARTY per-Layout row.
    -- "Per-Layout" means "per Raid/Party Layout", and a Custom Frame
    -- Group is not a Layout -- it is its own scope -- so the Custom
    -- Frame Groups assembler drops the card rather than rendering a
    -- control that would edit the wrong thing.
    return { preset = "strip", scopeStrip = true, fields = {
        { control = "switch", label = "Enable per-Layout Config",
          -- State first, then what it is the state of.
          labelSide = "after",
          -- Off is the shipped state: settings are global until somebody
          -- asks for them not to be.
          id = "perLayoutAuraText", default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default, these settings are global and affect all "
              .. "Layouts. Enabling this option will add the \"Modifying "
              .. "Layout\" dropdown at the top of the panel, allowing you "
              .. "to have different settings for each Layout (e.g. Party "
              .. "vs Raid).",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSection("auraText")
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight
              -- pass-through while that flag is off.
              bf:_TimeSectionPerLayout("auraText", v)
              -- Every field now reads a different place -- and the flat
              -- may hold its own mode, so the page's SHAPE can change.
              InvalidateMode(ctx)
          end },

        { control = "dropdown", label = "Modifying",
          -- Labeled above, like any other dropdown, and sized rather
          -- than left to its 200px natural width: a layout name is short.
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited for. "
              .. "The currently active Layout is shown in green.",
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
              -- the setup-mode test header to the new layout, re-position
              -- the test anchor, and refresh the preview.
              if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
              if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              -- Rebuilt rather than refreshed: the new flat may hold a
              -- different globalAuraTextConfig, changing the page shape.
              InvalidateMode(ctx)
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy all settings in the current subtab to another "
              .. "Layout.",
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
                  text = ("Copy all %s settings from \"%s\" to all other "
                      .. "Layouts? This will overwrite the %s settings of "
                      .. "every other Layout."):format(copyLabel, from, copyLabel)
              else
                  local toName = LayoutName(v)
                  text = ("Copy all %s settings from \"%s\" to \"%s\"? "
                      .. "This will overwrite the %s settings of the "
                      .. "\"%s\" Layout."):format(
                      copyLabel, from, toName, copyLabel, toName)
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do
                          CopySubcatTo(subcat, e.id)
                      end
                  else
                      CopySubcatTo(subcat, v)
                  end
                  ctx.app:RefreshPage()
              end)
          end },

        -- Its own full-width row under the two above, which is exactly
        -- where the Ace panel injects it (order 0.7, under the toggle at
        -- 0.5 and the Copy dropdown at 0.6). It belongs on this bar rather
        -- than on the page: like the toggle beside it, it decides how the
        -- settings are ORGANISED, not what any of them are.
        ModeSwitchField(subtabId),
    }}
end

-- ── The duration subtabs ───────────────────────────────────────
--
-- Four subtabs that differ by nothing but their key names and a few
-- descriptions, so they are declared as data and built. Each spec names
-- its sub-category and its seventeen keys.
local DURATION_SPECS = {
    durationText = {
        subcat = "global", mode = "global",
        show = "globalDurationShow",
        showDesc = "Show duration text on Buffs, Debuffs, Big Defensives, "
            .. "and Private Auras.",
        auto = "globalAutoScale", scale = "globalTimerScale",
        size = "globalFontSize",
        font = "globalDurationFont", border = "globalDurationBorder",
        hide1m = "globalHideDurationAbove1Min",
        color = "globalFontColor",
        colorDesc = "Color of the duration timer text. When Threshold "
            .. "Color is enabled, this is the color used above the "
            .. "threshold.",
        thrOn = "globalThresholdColorEnabled",
        thrCol = "globalThresholdColor",
        thrSec = "globalThresholdColorThreshold",
        thr2On = "globalThreshold2ColorEnabled",
        thr2Col = "globalThreshold2Color",
        thr2Sec = "globalThreshold2ColorThreshold",
        swipeOff = "globalDisableSwipe", swipeRev = "globalReverseSwipe",
        sparkOff = "globalDisableSpark",
        swipeId = "globalShowSwipe", sparkId = "globalShowSpark",
    },
    buffDurationText = {
        subcat = "buffs", mode = "perType",
        show = "showBuffDuration",
        auto = "buffAutoScale", scale = "buffTimerScale",
        size = "buffFontSize",
        font = "buffDurationFont", border = "buffDurationBorder",
        hide1m = "buffHideDurationAbove1Min",
        color = "buffFontColor",
        colorDesc = "Color of the buff duration timer text. When "
            .. "Threshold Color is enabled, this is the color used above "
            .. "the threshold.",
        thrOn = "buffThresholdColorEnabled",
        thrCol = "buffThresholdColor",
        thrSec = "buffThresholdColorThreshold",
        thr2On = "buffThreshold2ColorEnabled",
        thr2Col = "buffThreshold2Color",
        thr2Sec = "buffThreshold2ColorThreshold",
        swipeOff = "disableBuffSwipe", swipeRev = "reverseBuffSwipe",
        sparkOff = "disableBuffSpark",
        swipeId = "showBuffSwipe", sparkId = "showBuffSpark",
    },
    debuffDurationText = {
        subcat = "debuffs", mode = "perType",
        show = "showDebuffDuration",
        auto = "debuffAutoScale", scale = "debuffTimerScale",
        size = "debuffFontSize",
        font = "debuffDurationFont", border = "debuffDurationBorder",
        hide1m = "debuffHideDurationAbove1Min",
        color = "debuffFontColor",
        colorDesc = "Color of the debuff duration timer text. When "
            .. "Threshold Color is enabled, this is the color used above "
            .. "the threshold. When 'Use Dispel Type Color' is enabled, "
            .. "the dispel color overrides this.",
        thrOn = "debuffThresholdColorEnabled",
        thrCol = "debuffThresholdColor",
        thrSec = "debuffThresholdColorThreshold",
        thr2On = "debuffThreshold2ColorEnabled",
        thr2Col = "debuffThreshold2Color",
        thr2Sec = "debuffThreshold2ColorThreshold",
        swipeOff = "disableDebuffSwipe", swipeRev = "reverseDebuffSwipe",
        sparkOff = "disableDebuffSpark",
        swipeId = "showDebuffSwipe", sparkId = "showDebuffSpark",
    },
    bigDefDurationText = {
        subcat = "bigDef", mode = "perType",
        show = "showBigDefDuration",
        auto = "bigDefAutoScale", scale = "bigDefTimerScale",
        size = "bigDefFontSize",
        font = "bigDefDurationFont", border = "bigDefDurationBorder",
        hide1m = "bigDefHideDurationAbove1Min",
        color = "bigDefFontColor",
        colorDesc = "Color of the big defensive duration timer text. "
            .. "When Threshold Color is enabled, this is the color used "
            .. "above the threshold.",
        thrOn = "bigDefThresholdColorEnabled",
        thrCol = "bigDefThresholdColor",
        thrSec = "bigDefThresholdColorThreshold",
        thr2On = "bigDefThreshold2ColorEnabled",
        thr2Col = "bigDefThreshold2Color",
        thr2Sec = "bigDefThreshold2ColorThreshold",
        swipeOff = "disableBigDefSwipe", swipeRev = "reverseBigDefSwipe",
        sparkOff = "disableBigDefSpark",
        swipeId = "showBigDefSwipe", sparkId = "showBigDefSpark",
    },
}

-- A predicate over one stored key, read through the merged view.
local function SubIs(subcat, key, want)
    return function()
        local s = GetSub(subcat)
        local v = s and s[key]
        return (v == true) == want
    end
end

-- A gate in the card HEADER, and the card collapses when it is off --
-- the show-duration toggle's Ace `hidden`/`disabled` web made visible.
-- `id` and `default` make it reset with the rest of its card.
local function Gate(subcat, key, tooltip, desc, effect)
    return {
        id      = key,
        default = DefaultSub(subcat, key),
        tooltip = tooltip,
        desc    = desc,
        get     = function() return SubTable(subcat)[key] end,
        set     = function(_, _, v)
            if InCombatLockdown() then return end
            SubTable(subcat)[key] = v
            effect()
        end,
    }
end

-- The Cooldown Swipe card, FIRST on every duration subtab (Ace order
-- 0.1, ahead of the Duration Text header) and not gated by the show
-- toggle -- the swipe draws whether or not the text does.
--
-- "Show Cooldown Swipe" / "Show Cooldown Spark" INVERT their storage
-- (globalDisableSwipe etc.), so they keep get/set with `id` (the Ace
-- widget's own key) and a default derived from the stored one -- and
-- their refresh is IMMEDIATE, one click one refresh, as in the source.
local function SwipeGroup(spec)
    local subcat = spec.subcat
    local function inverted(id, storeKey, label)
        return {
            control = "switch", label = label,
            id = id, default = not DefaultSub(subcat, storeKey),
            disabled = "combat",
            get = function()
                local s = GetSub(subcat)
                return not ((s and s[storeKey]) or false)
            end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                SubTable(subcat)[storeKey] = not v
                DispatchRefreshForKey(storeKey)
                RefreshPreviewForSubcat(subcat)
            end,
        }
    end
    return { title = "Cooldown Swipe", preset = "form", fields = {
        inverted(spec.swipeId, spec.swipeOff, "Show Cooldown Swipe"),
        { control = "switch", label = "Reverse Swipe Direction",
          bind = subcat .. "." .. spec.swipeRev,
          onChange = Effect(spec.swipeRev), refresh = "write",
          disabled = "combat",
          -- Meaningless while the swipe is off, and hidden rather than
          -- grayed, as in the Ace page.
          hidden = SubIs(subcat, spec.swipeOff, true) },
        inverted(spec.sparkId, spec.sparkOff, "Show Cooldown Spark"),
    }}
end

-- The Duration Text card: the show toggle in the HEADER, everything the
-- Ace page hid or grayed while it was off collapsed under it -- the
-- Font and Duration Text Color inline groups folded in, so the whole
-- block vanishes with the gate exactly as the Ace `hidden` predicates
-- had it (see the notes for the one place this is stronger than Ace).
local function DurationGroup(spec)
    local subcat = spec.subcat
    local B = function(key) return subcat .. "." .. key end
    local autoOff = SubIs(subcat, spec.auto, false)
    local autoOn  = SubIs(subcat, spec.auto, true)
    local thrOff  = SubIs(subcat, spec.thrOn, false)
    local function thr2Hidden()
        local s = GetSub(subcat)
        return not (s and s[spec.thr2On]) or not (s and s[spec.thrOn])
    end

    local autoDesc = "When enabled, duration text size scales "
        .. "proportionally with the aura icon size. Use the scale slider "
        .. "to fine-tune. When disabled, a fixed font size is used instead."

    return { title = "Duration Text", preset = "form",
        toggle = Gate(subcat, spec.show, "Show Duration Text",
                      spec.showDesc, Effect(spec.show)),
        fields = {
            -- The rows are DECLARED, with `newRow` on the field that heads
            -- each one, rather than left to the packer's widths. The
            -- grouping is the meaning here -- scale with size, a threshold
            -- with its color and its seconds -- and the packer, which
            -- flows by width alone, cannot know that.
            --
            -- Row 1: the scale switch and whichever size control it leaves
            -- showing -- the two are alternatives (auto on, a scale; auto
            -- off, a fixed size), so only one of them is ever on this row.
            { control = "switch", label = "Auto Scale Duration Text",
              newRow = true,
              bind = B(spec.auto), desc = autoDesc,
              onChange = Effect(spec.auto), disabled = "combat" },
            { control = "slider", label = "Duration Text Scale",
              bind = B(spec.scale), min = 0.1, max = 3.0, step = 0.1,
              hidden = autoOff, refresh = "write",
              onChange = Effect(spec.scale), disabled = "combat" },
            { control = "slider", label = "Font Size",
              bind = B(spec.size), min = 6, max = 24, step = 1,
              hidden = autoOn, refresh = "write",
              onChange = Effect(spec.size), disabled = "combat" },

            -- Row 2: on its own, because it is about WHEN the text shows
            -- rather than how it looks.
            { control = "switch", newRow = true,
              label = "Hide Duration Text Over 1 Minute",
              bind = B(spec.hide1m),
              desc = "When enabled, the duration text is hidden when the "
                  .. "remaining time is above 59 seconds.",
              onChange = ThresholdEffect(spec.hide1m), disabled = "combat" },

            -- Row 3: the two font dropdowns. The face gets half again the
            -- default width -- a font name is longer than a border style,
            -- and at equal widths the names were the ones truncating.
            { control = "dropdown", label = "Font", newRow = true,
              widthMul = 1.5,
              bind = B(spec.font), options = FontOptions,
              onChange = Effect(spec.font), disabled = "combat" },
            { control = "dropdown", label = "Font Border",
              bind = B(spec.border), options = FONT_BORDER_OPTIONS,
              onChange = Effect(spec.border), disabled = "combat" },

            -- Row 4: the base color, alone -- the two threshold rows below
            -- are the exceptions to it, and reading it first is what makes
            -- them read as exceptions.
            { control = "color", label = "Font Color", newRow = true,
              bind = B(spec.color), alpha = true, desc = spec.colorDesc,
              refresh = "write",
              onChange = ThresholdEffect(spec.color), disabled = "combat" },

            -- Row 5: the primary threshold -- the switch, its color and
            -- its seconds. The color and the slider hide with the switch,
            -- so the row collapses to the switch alone when it is off.
            { control = "switch", newRow = true,
              label = "Change Color Based on Remaining Time",
              bind = B(spec.thrOn),
              desc = "When enabled, the duration text changes color when "
                  .. "the remaining duration falls below the threshold.",
              onChange = ThresholdEffect(spec.thrOn), disabled = "combat" },
            { control = "color", label = "Threshold Color",
              bind = B(spec.thrCol), alpha = true,
              hidden = thrOff, refresh = "write",
              onChange = ThresholdEffect(spec.thrCol), disabled = "combat" },
            { control = "slider", label = "Threshold (seconds)",
              bind = B(spec.thrSec), min = 1, max = 59, step = 1,
              hidden = thrOff, refresh = "write",
              onChange = ThresholdEffect(spec.thrSec), disabled = "combat" },

            -- Row 6: the secondary threshold, the same three in the same
            -- order -- so the two rows read as one pattern twice.
            { control = "switch", newRow = true,
              label = "Enable Secondary Threshold",
              bind = B(spec.thr2On),
              desc = "When enabled, a second color is applied when the "
                  .. "remaining duration falls below a lower threshold.",
              hidden = thrOff,
              onChange = ThresholdEffect(spec.thr2On), disabled = "combat" },
            { control = "color", label = "Secondary Threshold Color",
              bind = B(spec.thr2Col), alpha = true,
              hidden = thr2Hidden, refresh = "write",
              onChange = ThresholdEffect(spec.thr2Col), disabled = "combat" },
            -- Clamped against the primary on read AND write -- in the
            -- routed root, where the Ace get/set pair did it.
            { control = "slider", label = "Secondary Threshold (seconds)",
              bind = B(spec.thr2Sec), min = 1, max = 59, step = 1,
              hidden = thr2Hidden, refresh = "write",
              onChange = ThresholdEffect(spec.thr2Sec), disabled = "combat" },
        },
    }
end

-- ── The Stack Text subtab ──────────────────────────────────────
--
-- Always applicable, whatever the mode. The Ace page's Stack Text Font
-- and Stack Text Position header runs fold into the one gated card, and
-- the anchor dropdown + X + Y offset triplet becomes the anchor pad --
-- three settings that only mean anything together, as one control.
local function StackGroups()
    local subcat = "stackText"
    local autoOff = SubIs(subcat, "stackAutoScale", false)
    local autoOn  = SubIs(subcat, "stackAutoScale", true)
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Controls the font and position of the stack count "
                  .. "text shown on aura icons (buffs, debuffs, and custom "
                  .. "container buffs)." },
        }},
        { title = "Stack Text", preset = "form",
          toggle = Gate(subcat, "showStackText", "Show Stack Text",
                        nil, Effect("showStackText")),
          fields = {
            { control = "switch", label = "Auto Scale Stack Text",
              bind = "stackText.stackAutoScale",
              desc = "When enabled, stack text size scales proportionally "
                  .. "with the aura icon size. Use the scale slider to "
                  .. "fine-tune. When disabled, a fixed font size is used "
                  .. "instead.",
              onChange = Effect("stackAutoScale"), disabled = "combat" },
            { control = "slider", label = "Stack Text Scale",
              bind = "stackText.stackTimerScale",
              min = 0.1, max = 3.0, step = 0.1,
              hidden = autoOff, refresh = "write",
              onChange = Effect("stackTimerScale"), disabled = "combat" },
            { control = "slider", label = "Font Size",
              bind = "stackText.stackTextSize", min = 6, max = 20, step = 1,
              hidden = autoOn, refresh = "write",
              onChange = Effect("stackTextSize"), disabled = "combat" },
            { control = "dropdown", label = "Font",
              bind = "stackText.stackTextFont", options = FontOptions,
              desc = "Choose a font for aura stack count text",
              onChange = Effect("stackTextFont"), disabled = "combat" },
            { control = "dropdown", label = "Font Border",
              bind = "stackText.stackTextBorder",
              options = FONT_BORDER_OPTIONS,
              onChange = Effect("stackTextBorder"), disabled = "combat" },
            -- stackTextAnchor + stackTextX + stackTextY, as one pad.
            -- "Position", not "Stack Text Position": this card is the
            -- stack text's, so the noun is already said above it -- and the
            -- longer label crowded the "Offsets" heading beside it.
            { control = "anchor", label = "Position",
              binds = { point = "stackText.stackTextAnchor",
                        x     = "stackText.stackTextX",
                        y     = "stackText.stackTextY" },
              min = -20, max = 20, refresh = "write",
              onChange = Effect("stackTextAnchor"), disabled = "combat" },
        }},
    }
end

-- ── The five pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages: the ids are the Ace subtab args keys, and each
-- page function must be declared LAZY (page = function() ... end) --
-- the mode switch rebuilds them through Invalidate, and Invalidate only
-- re-calls a builder the route declares as a function.
--
-- `when` is what makes the mode switch hide tabs rather than empty them:
-- SubtabRoutes emits no route for an entry whose predicate says no, so
-- the strip has the same tabs the Ace dialog would show. The predicate is
-- read at ROUTE-BUILD time, and InvalidateMode rebuilds the routes, so it
-- is asked again every time the mode, the Modifying flat or the
-- per-Layout toggle changes.
local function GlobalMode()    return IsGlobalMode() end
local function PerTypeMode()   return not IsGlobalMode() end

BuzzardFramesOptions.AURATEXT_SUBTABS = {
    { id = "durationText",       title = "Duration Text",
      when = GlobalMode },
    { id = "buffDurationText",   title = "Buff Duration Text",
      when = PerTypeMode },
    { id = "debuffDurationText", title = "Debuff Duration Text",
      when = PerTypeMode },
    { id = "bigDefDurationText", title = "Big Defensive Duration Text",
      when = PerTypeMode },
    -- Stack text is the same in either mode, so it is always there.
    { id = "stackText",          title = "Stack Text" },
}

function BuzzardFramesOptions:AuraTextPage(subtabId)
    local groups
    local spec = DURATION_SPECS[subtabId]
    if spec then
        -- No mode check: a subtab whose settings the mode has moved
        -- elsewhere is not built, because AURATEXT_SUBTABS did not emit a
        -- route for it. The tab is gone, as it is in the Ace dialog,
        -- rather than present and explaining itself.
        groups = { ScopeStrip(spec.subcat, subtabId) }
        groups[#groups + 1] = SwipeGroup(spec)
        groups[#groups + 1] = DurationGroup(spec)
    elseif subtabId == "stackText" then
        groups = { ScopeStrip("stackText", subtabId) }
        for _, g in ipairs(StackGroups()) do groups[#groups + 1] = g end
    else
        return { groups = {} }
    end

    -- The Custom Frame Groups assembler DROPS the per-Layout strip -- a
    -- group is not a Layout -- and the mode switch would go with it. A
    -- group has its own mode, and its own subtabs follow it, so the switch
    -- comes back here as a bar of its own. Raid/Party keeps it on the
    -- strip, which is where the Ace panel puts it.
    local bf = BF()
    if bf and bf.BFOScopeFlat then
        table.insert(groups, 1, { preset = "strip",
                                  fields = { ModeSwitchField(subtabId) } })
    end

    return {
        -- The routed storage, wearing the shape of a nested table. Every
        -- `bind` on this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same nested shape --
        -- which is what makes right-click "Reset to default" work on
        -- every bound field without declaring anything.
        defaults = Defaults,
        -- The Aura Preview dropdown, in the page header above the subtab
        -- strip as on the Buffs and Debuffs sections, over this section's
        -- own account-wide key (previewModeAuraText).
        headerField = BuzzardFramesOptions:AuraPreviewField("auraText"),
        groups   = groups,
    }
end
