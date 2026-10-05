-- ============================================================
-- BuzzardFramesOptions: Pages_UnitFramesShared.lua
-- The shared half of the Unit Frames > Player Frame / Target Frame
-- migration, in BuzzardPanel.
--
-- The panel equivalent of the `makeFrameOpts` factory in BuzzardFrames'
-- UnitFrames/Options_oUF_Player_Target.lua, plus the ufGet/ufSet,
-- makePosGroup and relayout/update helpers that factory is handed from
-- Options_oUF_Other.lua. The Ace file builds ONE args table per unit from
-- that factory; this file builds the same four subtab pages -- Size &
-- Position, Name Bar, Health Bar, Power Bar -- for whichever unit the
-- caller names, and Pages_UnitFramesPlayer.lua / Pages_UnitFramesTarget.lua
-- add the tabs that are theirs alone.
--
-- Only the player and target branches live here. The pet/focus/tot/
-- focusTarget/boss tabs are built from the same Ace factory but belong to
-- another section's migration; nothing in this file is reached from there,
-- exactly as the assignment requires -- a copy of the behavior rather
-- than a reach across.
--
-- Storage: BF.ufDB (SavedVariable BuzzardFramesUnitFramesDB) -- its OWN
-- database, not the raid/party section profiles, so none of the
-- GetSectionProfile / WriteSectionKey routing applies and there are NO
-- per-Layout scope rows on these pages (Unit Frame Layouts are a section
-- of their own). Two shapes are in play and the pages address both
-- through ONE root:
--
--   ROOT.unit.<key>   ->  BF.ufDB.profile[<unit>][key]   (ufGet / ufSet)
--   ROOT.prof.<key>   ->  BF.ufDB.profile[key]           (the flat root)
--
-- Fields BIND through that root wherever the stored shape allows, which
-- is what makes right-click Undo and "Reset to default" work on them
-- without a per-field declaration; `defaults` answers in the same two
-- namespaces, out of BF.unitFrameDefaults. Computed fields (the screen-
-- bounded anchor sliders, the 0-1 opacity scales, the detached power bar's
-- fall-through sizes) keep get/set with an `id` and a `default` so undo
-- and reset still work on them.
--
-- COMBAT: the Ace section root (Options_oUF_Other.lua's "Player & Target"
-- group) carries `disabled = InCombatLockdown`, and AceConfig cascades
-- that to every widget underneath it. Every field on these pages
-- therefore declares `disabled = "combat"` -- including the ones whose
-- own Ace entry declared nothing, because in the Ace dialog they were
-- disabled in combat all the same. The explicit
-- `if InCombatLockdown() then return end` guards inside individual
-- setters are copied across verbatim on top of that; one never replaces
-- the other.
--
-- The Ace inline groups name their members generically -- `fontSize`,
-- `offsetX`, `offsetY`, `color`, `show`, `showSymbol`, `point`, `x`, `y`,
-- `width`, `height` -- because the group they sit in is what says WHICH
-- font size that is. A panel field has no such enclosing namespace, so
-- each one appears here under the storage key it actually writes, and the
-- card title carries the rest of the name:
--
--   nameTextGroup.fontSize / offsetX / offsetY  -> unit.nameFontSize,
--                                                  unit.nameOffsetX/Y
--   levelTextGroup.fontSize / offsetX / offsetY / color
--                                               -> unit.levelFontSize,
--                                                  unit.levelOffsetX/Y,
--                                                  unit.levelColor
--   *PosGroup.show / showSymbol / point / x / y -> the card's header gate,
--                                                  the Show % Symbol
--                                                  switch, and the anchor
--                                                  composite's three binds
--   detachedGroup.width / height                -> the Detached Width and
--                                                  Detached Height sliders
--                                                  (prof.oufPowerBarWidth /
--                                                  oufPowerBarHeight)
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local UF = {}
BuzzardFramesOptions.UnitFramesShared = UF

-- The unit-frames profile. Every read and write on these pages ends here.
local function Prof()
    local bf = BF()
    local db = bf and bf.ufDB
    return db and db.profile
end
UF.Prof = Prof

-- BF.unitFrameDefaults.profile -- Buzzard Frames' own defaults table, the
-- single source for what a key resets TO. A copy here would be a second
-- answer to the same question and the two would part company the first
-- time a default changed.
local function DefProfile()
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    return d and d.profile
end
UF.DefProfile = DefProfile

-- ── The Ace getters' own fallbacks ─────────────────────────────
--
-- Every Ace getter on these tabs reads through a fallback -- `or 156`,
-- `~= false`, `== true`. AceDB seeds the defaults table into the profile,
-- so most of them are unreachable, but they are what the source ANSWERS
-- when a key is nil and several of them differ from the shipped default
-- (frameWidth falls back to 156 where the default is 150; nameBarHeight
-- to 13 where it is 12). They are reproduced here to the digit rather
-- than corrected: this file's job is to answer what the Ace page
-- answered. What a key RESETS to still comes from the defaults table.
--
-- A boolean fallback is the `~= false` / `== true` getter written as the
-- value a nil read produces.

local UNIT_FALLBACK_SHARED = {
    -- Size & Position
    frameWidth          = 156,
    frameScale          = 1.0,
    iconScale           = 1.0,
    frameAlpha          = 1.0,
    -- Name Bar
    showNameBar         = true,
    nameBarHeight       = 13,
    showNameBarText     = true,
    showName            = true,
    nameFontSize        = 11,
    nameOffsetY         = -2,
    showLevel           = true,
    levelFontSize       = 10,
    levelOffsetY        = -2,
    hideLevelAtMax      = false,
    -- Health Bar
    healthBarHeight     = 22,
    healthFontSize      = 8,
    showHealthPct       = true,
    showHealthPctSymbol = true,
    showHealthVal       = true,
    -- Power Bar
    showPowerBar        = true,
    powerBarHeight      = 10,
    showPowerText       = true,
    powerFontSize       = 7,
    showPowerPct        = true,
    showPowerPctSymbol  = true,
    showPowerVal        = true,
    -- Raid Group text (player only; harmless elsewhere -- no field reads it)
    showRaidGroup       = false,
    raidGroupNumberOnly = false,
    raidGroupFontSize   = 11,
    raidGroupOffsetX    = 0,
    raidGroupOffsetY    = 0,
    -- Target cast bar font (the one per-unit key on the Cast Bar tab).
    -- 10, not the 8 the Ace getter used to say: castBarFontSize was the ONE
    -- key in this table with no shipped default, so its fallback was the only
    -- reachable one here -- the panel showed 8 while oUF_Castbar.lua drew 10.
    -- Defaults.lua now ships castBarFontSize = 10, so this agrees with both.
    castBarFontSize     = 10,
}

-- The two keys whose Ace fallback is written `isPlayer and A or B`.
local UNIT_FALLBACK_PLAYER = { nameOffsetX =  21, levelOffsetX = -4 }
local UNIT_FALLBACK_OTHER  = { nameOffsetX = -21, levelOffsetX =  4 }

-- The aura keys are prefixed with the unit name (playerShowBuffs,
-- targetBuffSize, ...) so one table serves both units, keyed by prefix at
-- lookup time. Player debuffs/buffs default OFF (`== true`), target's
-- default ON (`tufGet(key, true)`) -- the Ace getters differ, and so do
-- these.
local function AuraFallback(unit)
    local on = (unit ~= "player")
    return {
        [unit .. "ShowDebuffs"]   = on,
        [unit .. "DebuffSize"]    = 18,
        [unit .. "DebuffsPerRow"] = 8,
        [unit .. "MaxDebuffs"]    = 16,
        [unit .. "DebuffSpacing"] = 2,
        [unit .. "DebuffOffsetX"] = 0,
        [unit .. "DebuffOffsetY"] = 0,
        [unit .. "ShowBuffs"]     = on,
        [unit .. "BuffSize"]      = 18,
        [unit .. "BuffsPerRow"]   = 8,
        [unit .. "MaxBuffs"]      = 16,
        [unit .. "BuffSpacing"]   = 2,
        [unit .. "BuffOffsetX"]   = 0,
        [unit .. "BuffOffsetY"]   = 0,
        -- Target only; nothing on the player page reads it.
        [unit .. "NameplateDebuffsOnly"] = false,
    }
end

-- The position sub-tables (point/x/y). These fallbacks are makePosGroup's
-- OWN arguments, not the profile defaults: the Ace factory passes the
-- same defaultPoint / defaultX for every unit even where Defaults.lua
-- ships the mirrored pair, so a nil read answers the factory's literal.
local UNIT_POS_FALLBACK = {
    healthPctPos = { point = "LEFT",  x =   3, y = 0 },
    healthValPos = { point = "RIGHT", x = -10, y = 0 },
    powerPctPos  = { point = "LEFT",  x =   3, y = 0 },
    powerValPos  = { point = "RIGHT", x = -10, y = 0 },
}

-- The flat-root TABLE-valued keys, from the Alt Power Bar tab's own
-- getters: the two position tables and the Druid spec set, whose four
-- `(specs or {}).x ~= false` / `== true` getters are written here as the
-- values a nil read produces.
local PROF_TABLE_FALLBACK = {
    altPowerPctPos = { point = "RIGHT", x = -3, y = 0 },
    altPowerValPos = { point = "LEFT",  x =  3, y = 0 },
    altPowerBarDruidSpecs = {
        restoration = true, guardian = false, balance = true, feral = false,
    },
}

-- Flat-root scalars, from the Ace getters on the Alt Power Bar, Resource
-- Bar, Cast Bar and Combat Indicator tabs.
local PROF_FALLBACK = {
    -- Alt Power Bar
    showAltPowerBar                  = true,
    altPowerBarDetached              = false,
    altPowerBarHeight                = 3,
    oufAltPowerBarWidth              = 156,
    altPowerFontSize                 = 7,
    altPowerShowPct                  = true,
    altPowerShowPctSymbol            = true,
    altPowerShowVal                  = false,
    -- Resource Bar
    oufResourceBarEnabled            = false,
    oufResourceBarGap                = 2,
    oufResourceBarHeight             = 10,
    oufResourceBarWidth              = 156,
    oufResourceBarPipGap             = 2,
    oufResourceBarUseTypeColor       = true,
    oufResourceBarShowBg             = true,
    oufResourceBarBorderEnabled      = false,
    oufResourceBarBorderThickness    = 1,
    oufResourceBarPipBorderEnabled   = false,
    oufResourceBarPipBorderThickness = 1,
    oufResourceBarShowEmpty          = true,
    oufResourceBarEmptyDim           = 0.2,
    oufResourceBarPartialFill        = true,
    -- Target Cast Bar
    targetShowCastBar                = true,
    targetCastBarDetached            = false,
    targetCastBarPosition            = "below",
    targetCastBarGap                 = 0,
    targetCastBarAvoidAuras          = true,
    targetCastBarHeight              = 14,
    targetCastBarWidth               = 156,
    targetCastBarBorderEnabled       = false,
    targetCastBarBorderThickness     = 1,
    targetCastBarShowIcon            = true,
    targetCastBarIconSide            = "left",
    targetCastBarIconSize            = 20,
    targetCastBarIconGap             = 2,
    -- Combat Indicator
    oufShowCombatIndicator           = true,
    oufCombatIndicatorSize           = 18,
}

-- ── Colors ────────────────────────────────────────────────────
--
-- Storage holds { r=, g=, b=, a= } tables; the panel's color control
-- speaks { r, g, b, a } arrays. The roots convert both ways, with the Ace
-- getters' own fallback tables kept to the digit, so color fields can
-- bind and get undo and reset for free.
--
-- `alpha = false` means the Ace picker had `hasAlpha = false` and its
-- setter stored { r, g, b } with no `a` at all -- which is what is stored
-- here too, so the two panels write the same table.
local UNIT_COLOR = {
    levelColor     = { alpha = false, fallback = { r = 1, g = 0.82, b = 0 } },
    raidGroupColor = { alpha = false, fallback = { r = 1, g = 1,    b = 1 } },
}

local PROF_COLOR = {
    oufResourceBarColor          = { alpha = false, fallback = { r = 1.0, g = 0.61, b = 0.04 } },
    oufResourceBarBgColor        = { alpha = true,  fallback = { r = 0.08, g = 0.08, b = 0.08, a = 1 } },
    oufResourceBarBorderColor    = { alpha = true,  fallback = { r = 0, g = 0, b = 0, a = 1 } },
    oufResourceBarPipBorderColor = { alpha = true,  fallback = { r = 0, g = 0, b = 0, a = 1 } },
    targetCastBarBorderColor     = { alpha = true,  fallback = { r = 0, g = 0, b = 0, a = 1 } },
}

-- Read side: the stored named table (or the Ace fallback) as the array the
-- color control wants.
local function ColorOut(spec, v)
    local c = v or spec.fallback
    return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
end

-- Write side: a FRESH named table every time, as the Ace setters build
-- one -- never a reference to a table something else is holding. From the
-- control (or an undo) the value arrives as an array; from a reset it is
-- the defaults table's named copy, so both shapes are read.
local function ColorIn(spec, v)
    local r, g, b = v.r or v[1], v.g or v[2], v.b or v[3]
    if not spec.alpha then return { r = r, g = g, b = b } end
    local a = v.a
    if a == nil then a = v[4] end
    if a == nil then a = 1 end
    return { r = r, g = g, b = b, a = a }
end

-- ── The write-through root ─────────────────────────────────────
--
-- One root per unit, with two namespaces: `unit` is the per-unit
-- sub-table (ufGet/ufSet), `prof` is the flat profile root. A key whose
-- value is a TABLE answers with a wrapper of its own, so a composite can
-- bind `unit.healthPctPos.point` and a write materialises the sub-table
-- on demand exactly as makePosGroup's setters do.
--
-- The combat guard on every write is ufSet's own, kept where ufSet had
-- it. On the flat-root side the Ace setters carried it per field (and a
-- few Alt Power Bar setters carried none); it is applied uniformly here
-- because a write can also arrive from the panel's undo and reset paths,
-- which no Ace field has an equivalent of.

local roots = {}

local function BuildRoot(unit)
    local fallback = {}
    for k, v in pairs(UNIT_FALLBACK_SHARED) do fallback[k] = v end
    for k, v in pairs((unit == "player") and UNIT_FALLBACK_PLAYER or UNIT_FALLBACK_OTHER) do
        fallback[k] = v
    end
    for k, v in pairs(AuraFallback(unit)) do fallback[k] = v end

    -- profile[unit], as ufGet reads it.
    local function UnitTable()
        local p = Prof()
        return p and p[unit]
    end

    -- profile[unit][key], materialised -- ufSet's `profile[unit] =
    -- profile[unit] or {}` written once.
    local function UnitTableForWrite()
        local p = Prof()
        if not p then return nil end
        p[unit] = p[unit] or {}
        return p[unit]
    end

    local unitSubCache = {}
    local function UnitSub(key)
        local w = unitSubCache[key]
        if w then return w end
        w = setmetatable({}, {
            __index = function(_, k)
                local t = UnitTable()
                t = t and t[key]
                local v = t and t[k]
                if v ~= nil then return v end
                local f = UNIT_POS_FALLBACK[key]
                return f and f[k]
            end,
            __newindex = function(_, k, v)
                if InCombatLockdown() then return end
                local t = UnitTableForWrite()
                if not t then return end
                t[key] = t[key] or {}
                t[key][k] = v
            end,
        })
        unitSubCache[key] = w
        return w
    end

    local unitRoot = setmetatable({}, {
        __index = function(_, k)
            local t = UnitTable()
            local v = t and t[k]
            local col = UNIT_COLOR[k]
            if col then return ColorOut(col, v) end
            if v == nil then
                if UNIT_POS_FALLBACK[k] then return UnitSub(k) end
                return fallback[k]
            end
            if type(v) == "table" then return UnitSub(k) end
            return v
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local t = UnitTableForWrite()
            if not t then return end
            local col = UNIT_COLOR[k]
            if col and type(v) == "table" then
                t[k] = ColorIn(col, v)
            else
                t[k] = v
            end
        end,
    })

    local profSubCache = {}
    local function ProfSub(key)
        local w = profSubCache[key]
        if w then return w end
        w = setmetatable({}, {
            __index = function(_, k)
                local p = Prof()
                local t = p and p[key]
                local v = t and t[k]
                if v ~= nil then return v end
                local f = PROF_TABLE_FALLBACK[key]
                return f and f[k]
            end,
            __newindex = function(_, k, v)
                if InCombatLockdown() then return end
                local p = Prof()
                if not p then return end
                p[key] = p[key] or {}
                p[key][k] = v
            end,
        })
        profSubCache[key] = w
        return w
    end

    local profRoot = setmetatable({}, {
        __index = function(_, k)
            local p = Prof()
            local v = p and p[k]
            local col = PROF_COLOR[k]
            if col then return ColorOut(col, v) end
            if v == nil then
                if PROF_TABLE_FALLBACK[k] then return ProfSub(k) end
                return PROF_FALLBACK[k]
            end
            if type(v) == "table" then return ProfSub(k) end
            return v
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local p = Prof()
            if not p then return end
            local col = PROF_COLOR[k]
            if col and type(v) == "table" then
                p[k] = ColorIn(col, v)
            else
                p[k] = v
            end
        end,
    })

    return setmetatable({}, {
        __index = function(_, k)
            if k == "unit" then return unitRoot end
            if k == "prof" then return profRoot end
            return nil
        end,
    })
end

-- One root per unit, built once. The wrappers close over nothing that
-- changes, so a cached root stays correct across profile switches -- every
-- read goes back through Prof().
function UF.Root(unit)
    local r = roots[unit]
    if not r then
        r = BuildRoot(unit)
        roots[unit] = r
    end
    return r
end

-- The page's `db`: a function, so nothing touches BuzzardFrames at file
-- scope.
function UF.RootFn(unit)
    return function() return UF.Root(unit) end
end

-- Defaults in the SAME two namespaces the root uses, so the library
-- resolves a bind path straight into them -- `unit.healthPctPos.point`
-- included.
function UF.DefaultsFn(unit)
    return function()
        local d = DefProfile()
        if not d then return nil end
        return { unit = d[unit], prof = d }
    end
end

-- A single default, for the fields that keep get/set and must declare one
-- outright.
function UF.DefaultUnit(unit, key)
    local d = DefProfile()
    d = d and d[unit]
    return d and d[key]
end

function UF.DefaultProf(key)
    local d = DefProfile()
    return d and d[key]
end

-- ── Side effects ───────────────────────────────────────────────
--
-- The panel's copies of Options_oUF_Other.lua's relayout/update helpers,
-- under the SAME BF:DebounceOption keys, so a drag from either panel
-- coalesces into one layout walk rather than two.

function UF.RelayoutPlayer()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutPlayer", function()
        if bf.oufPlayer then bf:ApplyOUFPlayerLayout() end
    end)
end

function UF.UpdatePlayer()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdatePlayer", function()
        if bf.oufPlayer then bf.oufPlayer:UpdateAllElements("Manual") end
        -- The detached power bar is not reached by Power.PostUpdate, so
        -- the options update path has to reach it directly --
        -- UpdateOUFPowerBar re-bakes text visibility and format from the
        -- profile. Options-only path, zero combat cost.
        if bf.UpdateOUFPowerBar then bf:UpdateOUFPowerBar() end
    end)
end

function UF.RelayoutTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutTarget", function()
        if bf.oufTarget then bf:ApplyOUFTargetLayout() end
    end)
end

function UF.UpdateTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdateTarget", function()
        if bf.oufTarget then bf.oufTarget:UpdateAllElements("Manual") end
    end)
end

-- ── The enable gates ───────────────────────────────────────────
--
-- In the Ace panel neither of these pages EXISTS while its gate is off:
-- syncPTFTabs nils playerTab and targetTab out of the section's args when
-- ptfEnabled is false, and every non-Size subtab carries
-- `hidden = <unit>FrameDisabled`. The panel's subtabs are ROUTES and a
-- route cannot hide, so the same predicates are carried by the fields
-- instead -- nothing is reachable here that the Ace dialog hid -- and each
-- page opens with a note saying which switch brings it back. The note is a
-- widget the Ace page does not have; without it a gated-off page is a
-- column of bare card headers with no explanation.

function UF.PTFOff()
    local p = Prof()
    return not (p and p.ptfEnabled)
end

-- not ptfEnabled, or this frame's own enable toggle off -- the Ace
-- `isDisabled` / `playerFrameDisabled` / `targetFrameDisabled` helper with
-- the section gate folded in.
function UF.FrameOff(enableKey)
    return function()
        if UF.PTFOff() then return true end
        local p = Prof()
        return not (p and p[enableKey])
    end
end

-- The two notes. `hidden` is the inverse of the gate they explain, so
-- exactly one of them can be on screen at a time.
function UF.GateNotes(spec, isSizePage)
    local off = UF.FrameOff(spec.enableKey)
    local groups = {
        { preset = "bare", hidden = function() return not UF.PTFOff() end,
          fields = {
            { control = "note", wide = true,
              text = "Unit Frames are turned off. Turn on \"Enable Unit "
                  .. "Frames\" on the Unit Frames page -- these settings do "
                  .. "nothing until you do." },
        }},
    }
    -- On EVERY tab, Size & Position included. That page was exempt while
    -- it carried the frame's own enable switch -- a page with the switch on
    -- it does not need to say where the switch is. The seven switches now
    -- live together on the section root, so this page has no more to show
    -- than the others do and needs the same note. `isSizePage` is kept in
    -- the signature because both callers pass it and it still says which
    -- page is asking; nothing branches on it any more.
    groups[#groups + 1] = { preset = "bare",
        hidden = function() return UF.PTFOff() or not off() end,
        fields = {
            { control = "note", wide = true,
              text = "The " .. spec.label .. " is turned off. Enable it on "
                  .. "the Unit Frames page to configure it." },
        }}
    return groups
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every field on these pages binds into the unit's root and names its
-- effect; these say that once instead of a hundred times. `disabled` is
-- always "combat" -- see the note at the top of the file.

function UF.Sw(bind, label, effect, opts)
    local f = { control = "switch", label = label, bind = bind,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

function UF.Sl(bind, label, lo, hi, step, effect, opts)
    local f = { control = "slider", label = label, bind = bind,
                min = lo, max = hi, step = step,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A stepper, not a slider: a handful of whole numbers, where the reader
-- wants "one more" rather than a position on a track, and the number can be
-- typed directly. Same arguments as Sl, so a field converts by its name.
function UF.St(bind, label, lo, hi, step, effect, opts)
    local f = { control = "stepper", label = label, bind = bind,
                min = lo, max = hi, step = step,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

function UF.Col(bind, label, alpha, effect, opts)
    local f = { control = "color", label = label, bind = bind,
                alpha = alpha, onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- The anchor pad and its two offsets, as one field: makePosGroup's
-- point/x/y triplet, whose nine `anchorValues` are exactly the pad's nine
-- cells. The Ace sliders were -200..200 with soft bounds at -50..50; the
-- library has no soft bound, so the SHOWN range is what the field carries
-- (see the notes file -- values beyond +/-50 were reachable in Ace only by
-- typing into the box).
function UF.Pos(bind, label, effect, opts)
    local f = { control = "anchor", label = label,
                binds = { point = bind .. ".point",
                          x     = bind .. ".x",
                          y     = bind .. ".y" },
                min = -50, max = 50,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- ── Screen-bounded anchor sliders ──────────────────────────────
--
-- The Ace X/Y Position sliders carried softMin/softMax that
-- BF:ClampPositionSlider re-derived from the live screen size on every get
-- (resolutions change mid-session and login-time values lie). The panel
-- slider has min/max only, so the same bounds land there: re-derived
-- through the SAME BF methods ClampPositionSlider delegates to
-- (GetPositionHalfW / GetPositionHalfH) on every get, and written onto the
-- node, which the slider reads on every render. ClampPositionSlider itself
-- takes an Ace `info.option` table and writes softMin/softMax onto it, so
-- it cannot be called with a panel node.
--
-- The displayed value is the stored anchor MINUS the screen half-extent,
-- which is the Ace arithmetic verbatim: the slider shows a
-- center-relative coordinate and the profile stores a corner-relative one.
local function AnchorField(spec, axis, label, desc)
    local key = (axis == "x") and "anchorX" or "anchorY"
    local bf  = BF()
    local half = 1024
    if bf then
        half = (axis == "x") and bf:GetPositionHalfW() or bf:GetPositionHalfH()
    end
    return {
        control = "slider", label = label, desc = desc,
        id = "uf_" .. spec.unit .. "_" .. key,
        min = -half, max = half, step = 1,
        disabled = "combat",
        hidden = UF.FrameOff(spec.enableKey),
        get = function(node)
            local b = BF()
            local h = 0
            if b then
                h = (axis == "x") and b:GetPositionHalfW() or b:GetPositionHalfH()
                node.min, node.max = -h, h
            end
            local v
            if b and b.GetUFAnchor then
                local x, y = b:GetUFAnchor(spec.unit)
                v = (axis == "x") and x or y
            end
            if v == nil then
                local p = Prof()
                local u = p and p[spec.unit]
                v = (u and u[key]) or 0
            end
            return math.floor(v - h + 0.5)
        end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local b = BF()
            if not b then return end
            val = math.floor(val + 0.5)
            local p = Prof()
            local u = (p and p[spec.unit]) or {}
            local curX, curY = b:GetUFAnchor(spec.unit)
            if axis == "x" then
                local storeX = val + b:GetPositionHalfW()
                b:SetUFAnchor(spec.unit, storeX, curY or (u.anchorY or 0))
            else
                local storeY = val + b:GetPositionHalfH()
                b:SetUFAnchor(spec.unit, curX or (u.anchorX or 0), storeY)
            end
            spec.relayout()
        end,
    }
end

-- ── Sub-tab 1: Size & Position ─────────────────────────────────

local function SizeGroups(spec)
    local off = UF.FrameOff(spec.enableKey)
    local relayout = spec.relayout

    -- The raid-style twin switch, on the card with the enable toggle it
    -- depends on: a twin is live only when BOTH are on, which is why this
    -- one is hidden while the frame itself is off. Only the frames that
    -- HAVE a twin declare `raidStyleKey`, so the field is built or not.
    -- Experimental: the twin switch is gated behind Preview & Special
    -- Options > Experimental Options > Enable Experimental Options, with
    -- the "Raid-style Frame Scale" sliders on Raid/Party > Frames > Size &
    -- Position that size what it turns on. Composed with `off` rather than
    -- replacing it -- both reasons to hide still apply.
    local function TwinHidden(...)
        if BuzzardFramesOptions.ExperimentalOff() then return true end
        return off(...)
    end

    local function RaidStyleField()
        local key = spec.raidStyleKey
        if not key then return nil end
        return { control = "switch",
                 label = "Show as Raid/Party frame (friendly only)",
                 wide = true, disabled = "combat", hidden = TwinHidden,
                 id = key, default = UF.DefaultProf(key),
                 desc = "Uses the active Raid/Party layout's full styling "
                     .. "and buff settings for this frame while the unit is "
                     .. "friendly. Enemies keep the normal unit frame.",
                 get = function()
                     local p = Prof()
                     return p and p[key]
                 end,
                 set = function(_, _, val)
                     if InCombatLockdown() then return end
                     local p = Prof()
                     if not p then return end
                     p[key] = val
                     -- Live, like the enable switch above:
                     -- ApplyOUFVisibility builds or tears the twin down
                     -- and swaps the visibility drivers on both frames.
                     -- No reload.
                     local bf = BF()
                     if bf then bf:ApplyOUFVisibility() end
                 end }
    end

    -- The frame's OWN enable switch used to head this card, and it was the
    -- one control the page kept while the frame was off -- it was what
    -- turned the frame back on. It now lives with the other six, in the
    -- gated Unit Frames card on the section root, so this card carries the
    -- raid-style twin and nothing else, and hides with the rest of the
    -- page while the frame is off. A card whose fields all hide draws
    -- nothing, so a frame with no twin leaves no empty heading behind.
    local enableFields = { RaidStyleField() }

    return {
        { title = spec.label, preset = "form",
          hidden = off,
          fields = enableFields },

        { title = "Position", preset = "form", hidden = off, fields = {
            AnchorField(spec, "x", "X Position",
                "Horizontal position of the frame anchor."),
            AnchorField(spec, "y", "Y Position",
                "Vertical position of the frame anchor."),
        }},

        { title = "Size", preset = "form", hidden = off, fields = {
            UF.Sl("unit.frameWidth", "Width", 80, 400, 1, relayout,
                  { hidden = off }),
            UF.Sl("unit.frameScale", "Scale", 0.5, 2.0, 0.05, relayout,
                  { hidden = off }),
            UF.Sl("unit.iconScale", "Icon Scale", 0.5, 2.0, 0.05, relayout,
                  { hidden = off }),
        }},

        -- Presented on the 0-100 scale rather than the stored 0.1-1.0: the
        -- library's slider value box shows whole numbers, so the fraction
        -- would read "0" or "1" for every setting. The STORED value is
        -- unchanged. `id` plus a scaled `default` keep undo and reset
        -- working in the units shown.
        { title = "Frame Opacity", preset = "form", hidden = off, fields = {
            { control = "slider", label = "Frame Opacity",
              id = "uf_" .. spec.unit .. "_frameAlpha",
              min = 10, max = 100, step = 5,
              default = (UF.DefaultUnit(spec.unit, "frameAlpha") or 1) * 100,
              disabled = "combat", hidden = off,
              get = function()
                  local root = UF.Root(spec.unit)
                  return math.floor((root.unit.frameAlpha or 1) * 100 + 0.5)
              end,
              set = function(_, _, val)
                  local v = val / 100
                  local root = UF.Root(spec.unit)
                  root.unit.frameAlpha = v
                  local f = spec.frame()
                  if f then f:SetAlpha(v) end
              end },
        }},
    }
end

-- ── Sub-tab 2: Name Bar ────────────────────────────────────────
--
-- The Ace tab's shape, card for card: a Name Bar header with the strip
-- toggle and its height, then a Name Bar Text header whose toggle hides
-- the three text groups below it. The per-group Show toggles become the
-- cards' own header gates, which is the Ace `hidden` predicate made
-- visible -- the fields are not merely grayed while the toggle is off,
-- the card collapses to its header.

local function NameGroups(spec)
    local off      = UF.FrameOff(spec.enableKey)
    local root     = UF.Root(spec.unit)
    local relayout = spec.relayout
    local update   = spec.update
    local isPlayer = (spec.unit == "player")

    local function LayoutAndUpdate() relayout(); update() end

    local function nameBarOff() return off() or root.unit.showNameBar == false end
    local function textOff()    return off() or root.unit.showNameBarText == false end

    local groups = {
        { title = "Name Bar", preset = "form", hidden = off, fields = {
            { control = "switch", label = "Show Name Bar", wide = true,
              bind = "unit.showNameBar", disabled = "combat",
              onChange = LayoutAndUpdate },
        }},
        { title = "Bar Height", preset = "form", hidden = nameBarOff, fields = {
            UF.Sl("unit.nameBarHeight", "Name Bar Height", 8, 30, 1, relayout),
        }},
        { title = "Name Bar Text", preset = "form", hidden = off, fields = {
            { control = "switch", label = "Show Name Bar Text", wide = true,
              bind = "unit.showNameBarText", disabled = "combat",
              onChange = LayoutAndUpdate },
        }},
        { title = "Name Text", preset = "form", hidden = textOff,
          toggle = {
              id = "showName", default = UF.DefaultUnit(spec.unit, "showName"),
              tooltip = "Show Name",
              get = function() return root.unit.showName ~= false end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root.unit.showName = v
                  relayout()
              end,
          },
          fields = {
            UF.Sl("unit.nameFontSize", "Font Size", 6, 20, 1, relayout),
            UF.Sl("unit.nameOffsetX", "X Offset", -50, 50, 1, relayout),
            UF.Sl("unit.nameOffsetY", "Y Offset", -50, 50, 1, relayout),
        }},
    }

    -- Level Text. The player tab adds "Hide at Max Level" into this group,
    -- where it sits with the other level controls and hides with them.
    local levelFields = {}
    if isPlayer then
        levelFields[#levelFields + 1] = UF.Sw("unit.hideLevelAtMax",
            "Hide at Max Level", relayout,
            { wide = true,
              desc = "Hide the level text when the player is at maximum level." })
    end
    levelFields[#levelFields + 1] = UF.Sl("unit.levelFontSize", "Font Size", 6, 20, 1, relayout)
    levelFields[#levelFields + 1] = UF.Sl("unit.levelOffsetX", "X Offset", -50, 50, 1, relayout)
    levelFields[#levelFields + 1] = UF.Sl("unit.levelOffsetY", "Y Offset", -50, 50, 1, relayout)
    levelFields[#levelFields + 1] = UF.Col("unit.levelColor", "Color", false, LayoutAndUpdate)

    groups[#groups + 1] = {
        title = "Level Text", preset = "form", hidden = textOff,
        toggle = {
            id = "showLevel", default = UF.DefaultUnit(spec.unit, "showLevel"),
            tooltip = "Show Level",
            get = function() return root.unit.showLevel ~= false end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit.showLevel = v
                relayout()
            end,
        },
        fields = levelFields,
    }

    return groups
end

-- ── Sub-tab 3: Health Bar ──────────────────────────────────────
--
-- The per-frame color controls (hdrColor, useClassColor, healthColor)
-- are NOT here, and that is the Ace file's own doing: it builds them in
-- makeFrameOpts and then nils all three off both the player and the
-- target tab, because health colors live in Global > Health Bar Colors
-- (and the "Separate Configuration for Player Frame" override). Nothing
-- on these two pages ever showed them.

local function HealthGroups(spec)
    local off      = UF.FrameOff(spec.enableKey)
    local root     = UF.Root(spec.unit)
    local relayout = spec.relayout
    local update   = spec.update

    local function LayoutAndUpdate() relayout(); update() end

    return {
        { title = "Bar Height", preset = "form", hidden = off, fields = {
            UF.Sl("unit.healthBarHeight", "Health Bar Height", 8, 50, 1, relayout),
        }},
        { title = "Text", preset = "form", hidden = off, fields = {
            UF.Sl("unit.healthFontSize", "Font Size", 6, 16, 1, LayoutAndUpdate),
        }},
        { title = "Health Percent", preset = "form", hidden = off,
          toggle = {
              id = "showHealthPct",
              default = UF.DefaultUnit(spec.unit, "showHealthPct"),
              tooltip = "Show Health Percent",
              get = function() return root.unit.showHealthPct ~= false end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root.unit.showHealthPct = v
                  update()
              end,
          },
          fields = {
            { control = "switch", label = "Show % Symbol", wide = true,
              bind = "unit.showHealthPctSymbol", disabled = "combat",
              onChange = update },
            UF.Pos("unit.healthPctPos", "Position", relayout),
        }},
        { title = "Health Value", preset = "form", hidden = off,
          toggle = {
              id = "showHealthVal",
              default = UF.DefaultUnit(spec.unit, "showHealthVal"),
              tooltip = "Show Health Value",
              get = function() return root.unit.showHealthVal ~= false end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root.unit.showHealthVal = v
                  update()
              end,
          },
          fields = {
            UF.Pos("unit.healthValPos", "Position", relayout),
        }},
    }
end

-- ── Sub-tab 4: Power Bar ───────────────────────────────────────
--
-- Two toggles drive the tab. showPowerBar collapses the bar itself (the
-- StatusBar, its border and the layout); showPowerText is the master for
-- the percent and value FontStrings. Font and position controls stay
-- while the BAR is off, because they still affect the text -- exactly the
-- Ace arrangement.

local function PowerGroups(spec)
    local off      = UF.FrameOff(spec.enableKey)
    local root     = UF.Root(spec.unit)
    local relayout = spec.relayout
    local update   = spec.update
    local isPlayer = (spec.unit == "player")

    local function LayoutAndUpdate() relayout(); update() end

    -- Show Power Bar alone: the raid-style twin shows its power bar
    -- whenever the oUF frame's own is on, so this switch moves the twin
    -- too. `force` re-reads the power-bar state, not just the flat size.
    local function BarToggled()
        LayoutAndUpdate()
        local bf = BF()
        if spec.raidStyleKey and bf and bf.RefreshTwinLayout then
            bf:RefreshTwinLayout(true)
        end
    end

    local function barOff()  return off() or root.unit.showPowerBar  == false end
    local function textOff() return off() or root.unit.showPowerText == false end

    -- Detached is a PLAYER concept: the Ace field is hidden on every other
    -- unit (`unit ~= "player"`), so on the target page it could never be
    -- reached and is not built.
    local function detached()
        return isPlayer and (root.prof.oufPowerBarDetached == true)
    end

    local barFields = {
        { control = "switch", label = "Show Power Bar",
          bind = "unit.showPowerBar", disabled = "combat",
          onChange = BarToggled },
    }
    if isPlayer then
        barFields[#barFields + 1] = {
            control = "switch", label = "Detach Power Bar",
            desc = "When detached, the power bar can be positioned "
                .. "independently. Unlock frames to drag it.",
            id = "oufPowerBarDetached",
            default = UF.DefaultProf("oufPowerBarDetached"),
            disabled = "combat",
            hidden = function() return barOff() end,
            get = function()
                local bf = BF()
                return bf and bf:GetUFDetachState("playerPowerBar")
            end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                local bf = BF()
                if not bf then return end
                bf:SetUFDetachState("playerPowerBar", v)
                relayout()
            end,
        }
    end

    local groups = {
        { title = "Power Bar", preset = "form", hidden = off, fields = barFields },
        -- Height has no effect while the strip is hidden and the layout
        -- has collapsed, and none while detached either -- the Detached
        -- Power Bar card below carries its own height.
        { title = "Bar Height", preset = "form",
          hidden = function() return barOff() or detached() end,
          fields = {
            UF.Sl("unit.powerBarHeight", "Power Bar Height", 4, 20, 1, relayout),
        }},
    }

    if isPlayer then
        groups[#groups + 1] = {
            title = "Detached Power Bar", preset = "form",
            hidden = function() return barOff() or not detached() end,
            fields = {
                { control = "slider", label = "Detached Width",
                  id = "oufPowerBarWidth", min = 40, max = 600, step = 1,
                  -- oufPowerBarWidth is deliberately absent from the defaults:
                  -- nil means "inherit the frame's width" (oUF_PowerBar.lua),
                  -- not "use a default". DefaultProf therefore answers nil and
                  -- Reset would be inert, so the INHERITED width is computed
                  -- here instead -- resetting puts the detached bar back in
                  -- step with the frame, which is what nil looked like.
                  default = (root.unit.frameWidth or 156),
                  disabled = "combat",
                  get = function()
                      local p = Prof()
                      return (p and p.oufPowerBarWidth)
                          or (root.unit.frameWidth or 156)
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local p = Prof()
                      if not p then return end
                      p.oufPowerBarWidth = v
                      relayout()
                  end },
                { control = "slider", label = "Detached Height",
                  id = "oufPowerBarHeight", min = 4, max = 30, step = 1,
                  -- See Detached Width above: nil inherits, so Reset targets
                  -- the inherited height rather than a default that is absent
                  -- from the shipped table on purpose.
                  default = (root.unit.powerBarHeight or 10),
                  disabled = "combat",
                  get = function()
                      local p = Prof()
                      return (p and p.oufPowerBarHeight)
                          or (root.unit.powerBarHeight or 10)
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local p = Prof()
                      if not p then return end
                      p.oufPowerBarHeight = v
                      relayout()
                  end },
            },
        }
    end

    groups[#groups + 1] = {
        title = "Power Bar Text", preset = "form", hidden = off, fields = {
            { control = "switch", label = "Show Power Text", wide = true,
              bind = "unit.showPowerText", disabled = "combat",
              onChange = LayoutAndUpdate },
        },
    }
    groups[#groups + 1] = {
        title = "Text", preset = "form", hidden = textOff, fields = {
            UF.Sl("unit.powerFontSize", "Font Size", 6, 16, 1, LayoutAndUpdate),
        },
    }
    groups[#groups + 1] = {
        title = "Power Percent", preset = "form", hidden = textOff,
        toggle = {
            id = "showPowerPct",
            default = UF.DefaultUnit(spec.unit, "showPowerPct"),
            tooltip = "Show Power Percent",
            get = function() return root.unit.showPowerPct ~= false end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit.showPowerPct = v
                update()
            end,
        },
        fields = {
            { control = "switch", label = "Show % Symbol", wide = true,
              bind = "unit.showPowerPctSymbol", disabled = "combat",
              onChange = update },
            UF.Pos("unit.powerPctPos", "Position", relayout),
        },
    }
    groups[#groups + 1] = {
        title = "Power Value", preset = "form", hidden = textOff,
        toggle = {
            id = "showPowerVal",
            default = UF.DefaultUnit(spec.unit, "showPowerVal"),
            tooltip = "Show Power Value",
            get = function() return root.unit.showPowerVal ~= false end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit.showPowerVal = v
                update()
            end,
        },
        fields = {
            UF.Pos("unit.powerValPos", "Position", relayout),
        },
    }

    return groups
end

-- ── The four shared sub-tabs ───────────────────────────────────
--
-- The page BUILDERS, keyed by subtab id. A caller adds its own tabs to
-- this table's answer; nothing here knows about them.
local SHARED = {
    sizeTab   = SizeGroups,
    nameTab   = NameGroups,
    healthTab = HealthGroups,
    powerTab  = PowerGroups,
}

-- Build one subtab page for one unit. Returns nil when the id is not one
-- of the four shared tabs, so a caller can fall through to its own.
function UF.SharedGroups(spec, subtabId)
    local build = SHARED[subtabId]
    if not build then return nil end
    return build(spec)
end

-- The finished page: the gate notes, then whichever groups the caller
-- built, over the unit's routed root and Buzzard Frames' own defaults.
function UF.Page(spec, subtabId, groups)
    local out = UF.GateNotes(spec, subtabId == "sizeTab")
    for _, g in ipairs(groups or {}) do out[#out + 1] = g end
    return {
        db       = UF.RootFn(spec.unit),
        defaults = UF.DefaultsFn(spec.unit),
        groups   = out,
    }
end
