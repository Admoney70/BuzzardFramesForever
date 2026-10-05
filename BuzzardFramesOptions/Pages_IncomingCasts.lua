-- ============================================================
-- BuzzardFramesOptions: Pages_IncomingCasts.lua
-- The Incoming Casts section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' IncomingCasts/Options_-
-- IncomingCasts.lua: the same settings, the same storage and the same side
-- effects, with the AceConfig args table replaced by one section page and
-- six subtab pages. Both descriptions exist while both panels do; an edit
-- in either lands in the same place, so they cannot drift apart in what
-- they STORE -- only in what they show.
--
-- ROUTE SHAPE. The Ace section is a plain group with two child GROUPS
-- (icFrameTab, partyTab), each of which is itself `childGroups = "tab"`
-- with three tabs of its own (Options, Position, Display). So the two
-- displays are rail children of the section -- as they are in the Ace
-- tree -- and each declares its own `tabs` navigator over three subtab
-- routes. Nothing nests a contextual navigator inside another one: the
-- section itself has none.
--
--   incomingCasts                 page (the master toggle)
--     /icFrameTab                 tabs
--        /optionsTab /positionTab /displayTab
--     /partyTab                   tabs
--        /optionsTab /positionTab /displayTab
--
-- STORAGE: BuzzardFramesIncomingCastsDB, reached as BF.icDB.profile -- the
-- module's OWN namespace database, not the raid/party section profiles.
-- There is no per-Layout anything here and the Ace page has no Modifying
-- row, so this section takes NO scope strip.
--
-- THE TWO DISPLAYS SHARE EVERY OPTION NAME AND NO STORAGE. Incoming Casts
-- draws two independent displays -- the bar on the party player frame and
-- the detached "Incoming Casts Frame" -- and the Ace file builds both from
-- one generator, resolving the storage key from the option's PATH:
--
--     party display   ->  incomingCasts<Suffix>
--     detached frame  ->  incomingCastsPlayer<Suffix>
--
-- and only for the suffixes in BF.incomingCastsPerDisplayKeys. Everything
-- else -- the master toggle, the two "show on ..." toggles, and the
-- position keys, which are ALREADY called incomingCastsPlayerAnchorX and
-- friends -- is stored under its own name (which is why ResolveKeyName
-- guards on the per-display list rather than prefixing blindly; without it
-- "incomingCastsPlayerAnchorX" on the detached tab would resolve to
-- "incomingCastsPlayerPlayerAnchorX").
--
-- Here that resolution happens ONCE, when a field is built: a field's
-- `bind` is the RESOLVED key. So the two pages bind different paths, the
-- widget index cannot collide, and an undo recorded on the detached tab
-- can never be offered on the party one -- which binding the shared
-- option name would have allowed.
--
-- Every field binds into ROOT below, which is BF.icDB.profile wearing the
-- shape of a plain table with the Ace getters' own quirks folded into
-- __index. A bind path is what the library records an undo against and
-- looks a default up by, so binding is what makes right-click "Undo
-- change" and "Reset to default" work on all hundred-odd fields without
-- one of them declaring anything.
--
-- Ace args keys with no field of their own here, for the audit:
--   icFrameTab / partyTab / optionsTab / positionTab / displayTab
--                                     -> the routes
--   castsGroup, targetNameGroup, castBarGroup, castBarAppearanceGroup,
--   castBarBorderGroup, castBarIconGroup, castBarTextGroup, iconGroup,
--   timerTextGroup                    -> group cards, by their own names
--   positionHeader, displayHeader, previewHeader
--                                     -> card titles
--   desc                              -> the two intro notes (kept, as notes)
--   _posTracker                       -> Ace plumbing: a description whose
--                                        NAME function re-clamped the two
--                                        position sliders' soft bounds as a
--                                        render side effect. The panel's
--                                        position fields re-derive their own
--                                        bounds on every get, so there is
--                                        nothing left for it to do.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The module's own namespace profile. Nothing on this page reads it at
-- file scope: every one of these runs after the panel is opened.
local function Profile()
    local bf = BF()
    return bf and bf.icDB and bf.icDB.profile
end

-- ── Per-display key resolution ─────────────────────────────────
--
-- BF.incomingCastsPerDisplayKeys is the single source of truth for which
-- suffixes belong to a display (the defaults, the dbVersion 64 migration,
-- the Ace generator and the runtime all drive off it), so it is read from
-- there rather than restated. Cached on first use, because the list is
-- built at load and never changes afterwards.
local perDisplayCache

local function PerDisplay()
    if perDisplayCache then return perDisplayCache end
    local bf = BF()
    local list = bf and bf.incomingCastsPerDisplayKeys
    if not list then return {} end
    local t = {}
    for _, suffix in ipairs(list) do t[suffix] = true end
    perDisplayCache = t
    return t
end

local function ResolveKeyName(prefix, name)
    local suffix = name and name:match("^incomingCasts(.+)$")
    if suffix and PerDisplay()[suffix] then
        return prefix .. suffix
    end
    return name
end

-- The other direction: a stored key back to its per-display suffix, so the
-- getter quirks below can be declared once per SETTING rather than twice
-- per setting. "incomingCastsPlayerBarColor" and "incomingCastsBarColor"
-- both answer "BarColor"; "incomingCastsPlayerAnchorX" answers "AnchorX",
-- which is in none of the quirk tables, so it falls through untouched.
local function SuffixOf(key)
    if type(key) ~= "string" then return nil end
    local s = key:match("^incomingCastsPlayer(.+)$")
    if s and PerDisplay()[s] then return s end
    return key:match("^incomingCasts(.+)$")
end

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db and reading or writing the slot it lands on. That is exactly what
-- icGet/icSet do, minus the per-key reading quirks the Ace page spread
-- across a dozen hand-written getters -- so those live here, each copied
-- from the getter it replaces:
--
--   colors       stored as { r=, g=, b=, a= } tables; the panel's color
--                 control speaks { r, g, b, a } arrays, so the two shapes
--                 are converted here, with the Ace icColorGet fallbacks
--                 kept to the digit
--   fonts         normalized through BF:NormalizeFontName -- a legacy path
--                 or an unregistered name would otherwise select nothing
--   ShowBorder /  nil reads as true ("~= false"), as in the Ace getters
--   ShowIcon /
--   ShowSpellName /
--   TintNotAimed /
--   TargetNameClassColor
--   BorderStyle   nil -> "square"
--   CastFilter    nil -> the legacy ShowAllCasts boolean of the SAME
--                 display, mapped exactly as BuildCfg does at runtime.
--                 The stored value is deliberately never migrated.
local COLOR_FALLBACK = {
    BarColor      = { r = 1,    g = 0.84, b = 0,   a = 1    },
    NotAimedColor = { r = 0.35, g = 0.35, b = 0.4, a = 0.75 },
    BorderColor   = { r = 0,    g = 0,    b = 0,   a = 0.8  },
}

-- NameColor and TimeColor fall back to the LEGACY single text color, so
-- an old profile's swatch shows its real color until it is changed. The
-- Ace page baked that lookup in when the args table was built; reading it
-- live is the same value and survives a profile switch.
local LEGACY_TEXT = { BarColor = false, NameColor = true, TimeColor = true }

local FONT_KEYS = {
    NameFont = true, BarTimerFont = true, IconTimerFont = true,
}

local TRUE_UNLESS_FALSE = {
    ShowBorder = true, ShowIcon = true, ShowSpellName = true,
    TintNotAimed = true, TargetNameClassColor = true,
}

local function ColorFallback(suffix)
    if LEGACY_TEXT[suffix] then
        local p = Profile()
        local c = p and p.incomingCastsTextColor
        if type(c) == "table" then return c end
        return { r = 1, g = 1, b = 1, a = 1 }
    end
    return COLOR_FALLBACK[suffix]
end

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local p = Profile()
        if not p then return nil end
        local v = p[k]
        local s = SuffixOf(k)
        if not s then return v end

        if COLOR_FALLBACK[s] or LEGACY_TEXT[s] then
            local c = v or ColorFallback(s)
            return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
        end
        if FONT_KEYS[s] then
            local bf = BF()
            if bf and bf.NormalizeFontName then return bf:NormalizeFontName(v) end
            return v
        end
        if TRUE_UNLESS_FALSE[s] then return v ~= false end
        if s == "BorderStyle" then return v or "square" end
        if s == "CastFilter" then
            if v == nil then
                -- The sibling legacy boolean of the SAME display: the key
                -- minus its own suffix is that display's prefix.
                local prefix = k:sub(1, #k - #s)
                return p[prefix .. "ShowAllCasts"] and "all" or "aimed"
            end
            return v
        end
        return v
    end,

    __newindex = function(_, k, v)
        -- The Ace setters each open with this guard; every write path here
        -- -- including the panel's own undo and reset -- goes through this
        -- one.
        if InCombatLockdown() then return end
        local p = Profile()
        if not p then return end
        local s = SuffixOf(k)
        if s and (COLOR_FALLBACK[s] or LEGACY_TEXT[s]) and type(v) == "table" then
            -- From the control (or an undo) the value is an array; from a
            -- reset it is the defaults table's named copy. Either way a
            -- FRESH named table is stored, as icColorSet does -- never a
            -- reference to a table something else holds.
            local a = v.a
            if a == nil then a = v[4] end
            p[k] = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3], a = a }
        else
            p[k] = v
        end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage -- the detached
-- display's defaults included, since Defaults_IncomingCasts derives
-- incomingCastsPlayer<Suffix> from the party key at load. So a bind path
-- resolves straight into it.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.incomingCastsDefaults
    return d and d.profile
end

local function DefaultFor(key)
    local d = Defaults()
    return d and d[key]
end

-- ── Side effects ───────────────────────────────────────────────
--
-- One function per chain the Ace setters run, in the SAME order they run
-- it. The WRITE happens in ROOT's __newindex; these are what a field names
-- in `onChange`, and the library decides when to run them (a slider
-- coalesces its drag into one call).

-- The Setup Mode overlay for Incoming Casts (`icPlayerFrame`) is sized by
-- GetUFTestFrameSize from the bar width/height/icon settings, and
-- ShowUFTestFrames is the only thing that re-applies that size. Without
-- this, editing e.g. Bar Width left the overlay at its old size until
-- Setup Mode was closed and reopened.
local function RefreshSetupOverlay()
    local bf = BF()
    if bf and bf.db and bf.db.global and bf.db.global.setupModeActive
       and bf.ShowUFTestFrames then
        bf:ShowUFTestFrames()
    end
end

-- The mover handle and the party preview, each re-shown only if it is
-- already up -- the tail of setAndRefresh and setAndReposition alike.
local function RefreshOpenPreviews(ic)
    if ic._playerAnchor and ic._playerAnchor._handle
       and ic._playerAnchor._handle:IsShown() then
        ic:ShowPlayerMover()
    end
    if ic._partyPreviewShown then
        ic:ShowPartyPreview()
    end
end

-- setAndRefresh: the settings-change chain. OnSettingChanged rebinds the
-- context and bumps the style generation; Refresh drops the resolved
-- per-display config and releases the live casts.
local function SetAndRefresh()
    local bf = BF()
    if not bf then return end
    local ic = bf.IncomingCasts
    if ic then
        ic:OnSettingChanged()
        ic:Refresh()
        RefreshOpenPreviews(ic)
    end
    RefreshSetupOverlay()
end

-- setAndReposition: the same without OnSettingChanged -- a geometry change
-- needs no rebind.
local function SetAndReposition()
    local bf = BF()
    if not bf then return end
    local ic = bf.IncomingCasts
    if ic then
        ic:Refresh()
        RefreshOpenPreviews(ic)
    end
    RefreshSetupOverlay()
end

-- icColorSet's own chain, which is NOT either of the two above: the setup
-- overlay is refreshed FIRST, there is no OnSettingChanged, and the mover
-- is not re-shown. Only the party preview is, and only if it is up --
-- without which the Test Position preview keeps the old color until
-- something else forces a rebuild.
local function ColorChanged()
    RefreshSetupOverlay()
    local bf = BF()
    local ic = bf and bf.IncomingCasts
    if ic then
        ic:Refresh()
        if ic._partyPreviewShown then
            ic:ShowPartyPreview()
        end
    end
end

-- The master toggle's chain: OnSettingChanged and nothing else. The Ace
-- setter deliberately does not call Refresh here.
local function MasterChanged()
    local bf = BF()
    local ic = bf and bf.IncomingCasts
    if ic then ic:OnSettingChanged() end
end

-- A per-display "show on ..." toggle: Refresh and nothing else, as in the
-- Ace setter.
local function DisplayShownChanged()
    local bf = BF()
    local ic = bf and bf.IncomingCasts
    if ic then ic:Refresh() end
end

-- The detached frame's X/Y sliders: move the anchor, then refresh, then
-- mirror the SetUFAnchor pattern so the icPlayerFrame test overlay tracks
-- the slider edit while Setup Mode is on.
local function PlayerAnchorMoved()
    local bf = BF()
    local ic = bf and bf.IncomingCasts
    if ic then
        ic:UpdatePlayerAnchorPosition()
        ic:Refresh()
    end
    RefreshSetupOverlay()
end

-- ── Reading the current display ────────────────────────────────
--
-- Every predicate below reads through ROOT rather than the raw profile, so
-- it sees the same value the widget beside it shows. The Ace predicates
-- read raw and spelled the nil case out at each site (`~= false`,
-- `== false`); ROOT folds those in, so `not ROOT[showIcon]` is the same
-- test `ic.incomingCastsShowIcon == false` was.

local function Cfg(prefix, name)
    return ROOT[ResolveKeyName(prefix, name)]
end

local function IsShowingAll(prefix)
    return Cfg(prefix, "incomingCastsCastFilter") == "all"
end

local function NotCastBar(prefix)
    return Cfg(prefix, "incomingCastsDisplayType") ~= "castbar"
end

local function NotIconType(prefix)
    return Cfg(prefix, "incomingCastsDisplayType") ~= "icon"
end

local function NoIcon(prefix)
    return NotCastBar(prefix) or not Cfg(prefix, "incomingCastsShowIcon")
end

local function NoBorder(prefix)
    return NotCastBar(prefix) or not Cfg(prefix, "incomingCastsShowBorder")
end

-- ── Gating ─────────────────────────────────────────────────────
--
-- Two levels, exactly as the Ace page had them: the section's master
-- toggle hides the whole icFrameTab / partyTab GROUP, and inside each of
-- those every generated option is wrapped in "or this display is turned
-- off". The panel's tabs are ROUTES and a route cannot hide, so the two
-- tests come down onto the groups and fields instead -- and each page
-- carries a note saying which switch is off, because otherwise those
-- pages are a column of empty cards with no explanation.

local function Off()
    local p = Profile()
    return not (p and p.incomingCastsEnabled)
end

local function DisplayOff(showKey)
    local p = Profile()
    if not p or not p.incomingCastsEnabled then return true end
    return not p[showKey]
end

-- The Ace wrapper verbatim: master off or display off hides it outright,
-- otherwise the option's own predicate decides.
local function Gate(showKey, extra)
    return function()
        if DisplayOff(showKey) then return true end
        if extra then return extra() and true or false end
        return false
    end
end

-- ── Option lists ───────────────────────────────────────────────
--
-- Lists with an Ace `sorting` keep it verbatim; lists without one keep the
-- order AceConfigDialog actually showed, which is alphabetical by stored
-- key.

local DISPLAYTYPE_OPTIONS = {
    { value = "castbar", text = "Cast Bar" },
    { value = "icon",    text = "Icon" },
}

local CASTFILTER_OPTIONS = {
    { value = "aimed",    text = "Aimed At You" },
    { value = "all",      text = "All Casts" },
    { value = "notAimed", text = "Not Aimed At You" },
}

local ALIGN_OPTIONS = {
    { value = "CENTER", text = "Center" },
    { value = "LEFT",   text = "Left" },
    { value = "RIGHT",  text = "Right" },
}

local FONTBORDER_OPTIONS = {
    { value = "",             text = "None" },
    { value = "MONOCHROME",   text = "Monochrome" },
    { value = "OUTLINE",      text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick Outline" },
}

-- The icon timer's own border list, which carries two combined values the
-- bar's does not.
local ICON_FONTBORDER_OPTIONS = {
    { value = "",                        text = "None" },
    { value = "MONOCHROME",              text = "Monochrome" },
    { value = "OUTLINE",                 text = "Outline" },
    { value = "OUTLINE, MONOCHROME",     text = "Outline + Monochrome" },
    { value = "THICKOUTLINE",            text = "Thick Outline" },
    { value = "THICKOUTLINE, MONOCHROME", text = "Thick Outline + Monochrome" },
}

local ICONSIDE_OPTIONS = {
    { value = "LEFT",  text = "Left" },
    { value = "RIGHT", text = "Right" },
}

-- SHAPES only. Rounded's two weights are the Thin/Thick strip beside this
-- one -- see Pages_BorderStyle.lua -- rather than a third entry here.
local BORDERSTYLE_OPTIONS = {
    { value = "square",  text = "Square"  },
    { value = "rounded", text = "Rounded" },
}

local PLAYER_GROW_OPTIONS = {
    { value = "DOWN",  text = "Down" },
    { value = "LEFT",  text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "UP",    text = "Up" },
}

local PARTY_GROW_OPTIONS = {
    { value = "AUTO",  text = "Auto (based on party orientation)" },
    { value = "DOWN",  text = "Down" },
    { value = "LEFT",  text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "UP",    text = "Up" },
}

local PARTY_ANCHOR_OPTIONS = {
    { value = "AUTO",        text = "Auto (based on party orientation)" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMLEFT",  text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "LEFT",        text = "Left" },
    { value = "RIGHT",       text = "Right" },
    { value = "TOP",         text = "Top" },
    { value = "TOPLEFT",     text = "Top Left" },
    { value = "TOPRIGHT",    text = "Top Right" },
}

-- LSM lists, resolved every time the menu opens, so media registered after
-- the panel is built still appears. LSM:List returns the names already
-- sorted -- the order the Ace dialog showed, which sorted the HashTable
-- keys it was handed.
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
-- Every field binds into ROOT under its RESOLVED key, names the chain it
-- runs, and is combat-locked -- said once each rather than a hundred
-- times. `name` is always the option's own Ace name (the party spelling);
-- the prefix decides where it lands.

local function Merge(f, opts)
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sw(prefix, name, label, effect, opts)
    return Merge({ control = "switch", label = label,
                   bind = ResolveKeyName(prefix, name),
                   onChange = effect, disabled = "combat" }, opts)
end

local function Sl(prefix, name, label, lo, hi, st, effect, opts)
    return Merge({ control = "slider", label = label,
                   bind = ResolveKeyName(prefix, name),
                   min = lo, max = hi, step = st,
                   onChange = effect, disabled = "combat" }, opts)
end

local function Dd(prefix, name, label, options, effect, opts)
    return Merge({ control = "dropdown", label = label,
                   bind = ResolveKeyName(prefix, name),
                   options = options,
                   onChange = effect, disabled = "combat" }, opts)
end

local function Col(prefix, name, label, opts)
    -- Every color in this section is hasAlpha.
    return Merge({ control = "color", label = label,
                   bind = ResolveKeyName(prefix, name), alpha = true,
                   onChange = ColorChanged, disabled = "combat" }, opts)
end

-- A fraction stored 0-1, shown 0-100: the scale the Ace dialog itself
-- showed (isPercent), and the only one the library's whole-number slider
-- value box can display. get/set do the conversion, so what is STORED
-- never changes; `id` plus a scaled `default` keep undo and reset working
-- in the shown units.
local function Pct(prefix, name, label, lo, hi, st, effect, opts)
    local key = ResolveKeyName(prefix, name)
    local d   = DefaultFor(key)
    return Merge({
        control = "slider", label = label, id = key,
        min = lo, max = hi, step = st,
        default = d and math.floor(d * 100 + 0.5) or nil,
        get = function()
            local v = ROOT[key]
            if v == nil then return nil end
            return math.floor(v * 100 + 0.5)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = v / 100
        end,
        onChange = effect, disabled = "combat",
    }, opts)
end

-- ── Screen-bounded position sliders ────────────────────────────
--
-- The Ace X/Y sliders carried softMin/softMax that ClampPositionSlider
-- re-derived from the live screen size on every get (resolutions change
-- mid-session, and login-time values lie). The panel slider has min/max
-- only, so the same bounds land there: seeded from BF:GetPositionHalfW/H
-- when the field is built, re-derived through the same methods on every
-- get. One honest difference, shared with Pages_Frames: Ace's soft bounds
-- limited only the DRAG and let the text box type past them; the panel
-- clamps the commit too.
local function PositionField(key, label, desc, axis, fallback)
    local bf   = BF()
    local half = 1024
    if bf then
        half = (axis == "x") and bf:GetPositionHalfW() or bf:GetPositionHalfH()
    end
    return {
        control = "slider", label = label, desc = desc,
        id = key, min = -half, max = half, step = 1,
        default = DefaultFor(key),
        get = function(node)
            local b = BF()
            if b then
                local h = (axis == "x") and b:GetPositionHalfW() or b:GetPositionHalfH()
                node.min, node.max = -h, h
            end
            local p = Profile()
            return (p and p[key]) or fallback
        end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            ROOT[key] = val
        end,
        onChange = PlayerAnchorMoved, disabled = "combat",
    }
end

-- ── The displays ───────────────────────────────────────────────
--
-- Everything that differs between the two of them, in one place. The ids
-- are the Ace args keys, so Panel.lua's existing route ids are unchanged.

local DISPLAYS = {
    icFrameTab = {
        prefix  = "incomingCastsPlayer",
        showKey = "incomingCastsShowOnPlayerFrame",
        title   = "Incoming Casts Frame",
        enable  = "Enable Incoming Casts Frame",
        enableDesc = "Display incoming casts on a detached frame.",
        intro   = "A detached frame that shows incoming enemy casts targeting "
               .. "you. Unlock frames to drag it into position, or use the X/Y "
               .. "sliders on the Position tab.",
        offNote = "The Incoming Casts Frame is turned off. Turn on \"Enable "
               .. "Incoming Casts Frame\" on the Options tab to edit these "
               .. "settings.",
    },
    partyTab = {
        prefix  = "incomingCasts",
        showKey = "incomingCastsShowOnPartyFrame",
        title   = "Party Player Frame",
        enable  = "Show on Player Party Frame",
        enableDesc = "Display incoming casts on your frame within the party frames.",
        intro   = "Show incoming enemy casts anchored to your frame within the "
               .. "party frames.",
        offNote = "The party player frame display is turned off. Turn on \"Show "
               .. "on Player Party Frame\" on the Options tab to edit these "
               .. "settings.",
    },
}

BuzzardFramesOptions.INCOMINGCASTS_SUBTABS = {
    { id = "icFrameTab", title = "Incoming Casts Frame" },
    { id = "partyTab",   title = "Party Player Frame" },
}

BuzzardFramesOptions.INCOMINGCASTS_DISPLAY_TABS = {
    { id = "optionsTab",  title = "Options" },
    { id = "positionTab", title = "Position" },
    { id = "displayTab",  title = "Display" },
}

-- The Ace tabs hide outright when their switch is off; a route cannot, so
-- the reason sits at the top of the page instead. Two notes rather than
-- one with a computed body: a note's text is read once per render, and two
-- mutually exclusive predicates say which case is which without either
-- pretending to be the other.
local function OffNotes(d)
    return { preset = "bare", fields = {
        { control = "note", wide = true,
          hidden = function() return not Off() end,
          text = "Incoming Casts is disabled. Turn on \"Enable Incoming "
              .. "Casts\" on the Incoming Casts page to edit these settings." },
        { control = "note", wide = true,
          hidden = function() return Off() or not DisplayOff(d.showKey) end,
          text = d.offNote },
    }}
end

-- ── The Options subtab ─────────────────────────────────────────

local function OptionsPage(d)
    local prefix, showKey = d.prefix, d.showKey

    return {
        -- The Ace `desc` description, kept: it says what the display IS,
        -- which no label on the page does.
        { preset = "bare", hidden = Off, fields = {
            { control = "note", wide = true, text = d.intro },
        }},

        -- The display's own enable toggle lives in the card HEADER: every
        -- card below it is gone while it is off, and a card that collapses
        -- says that more plainly than two fields that vanish. `id` and
        -- `default` are what make it reset with the rest of its card.
        { title = d.title, preset = "form", hidden = Off,
          toggle = {
            id      = showKey,
            default = DefaultFor(showKey),
            tooltip = d.enableDesc,
            get     = function() return ROOT[showKey] end,
            set     = function(_, _, v)
                if InCombatLockdown() then return end
                ROOT[showKey] = v
                DisplayShownChanged()
            end,
          },
          fields = {
            { control = "segmented", label = "Display Type",
              bind = ResolveKeyName(prefix, "incomingCastsDisplayType"),
              options = DISPLAYTYPE_OPTIONS,
              onChange = SetAndRefresh, disabled = "combat",
              desc = "How to display incoming casts.\n\n"
                  .. "|cffffffffCast Bar|r: A progress bar showing the cast "
                  .. "name and icon.\n\n"
                  .. "|cffffffffIcon|r: A spell icon with a cooldown sweep." },
            Col(prefix, "incomingCastsBarColor", "Cast Bar Color", {
                desc = "Fill color of the incoming cast bar.",
                hidden = function() return NotCastBar(prefix) end }),
        }},

        { title = "Casts", preset = "form", hidden = Gate(showKey), fields = {
            Dd(prefix, "incomingCastsCastFilter", "Show Casts",
               CASTFILTER_OPTIONS, SetAndRefresh, {
                desc = "Which enemy casts this display shows.\n\n"
                    .. "|cffffffffAimed At You|r: only casts targeting you.\n"
                    .. "|cffffffffAll Casts|r: every tracked cast.\n"
                    .. "|cffffffffNot Aimed At You|r: every tracked cast EXCEPT those "
                    .. "targeting you.\n\n"
                    .. "|cff888888Each display has its own setting, so one can show what is "
                    .. "coming at you while the other shows everything else.\n\n"
                    .. "The module already tracks all of them -- the filter is only visual -- "
                    .. "so this costs nothing extra. The game gives addons no way to tell an "
                    .. "AoE or ground-targeted cast from one aimed at someone else, so "
                    .. "\"Not Aimed At You\" cannot be narrowed to just untargeted casts.|r" }),
            -- Only meaningful in "All Casts": in the other two modes every
            -- visible bar is on the same side of the test, so a tint would
            -- just be a second bar color.
            Sw(prefix, "incomingCastsTintNotAimed",
               "Tint Casts Not Aimed At You", SetAndRefresh, {
                hidden = function() return not IsShowingAll(prefix) end,
                desc = "Lay a color over casts that are not targeting you, so the ones "
                    .. "that are stand out.\n\n"
                    .. "|cff888888This is the only distinction the game permits: whether a "
                    .. "cast targets you is a protected value addons can hand to the display "
                    .. "engine but never read.|r" }),
            Col(prefix, "incomingCastsNotAimedColor", "Not-Aimed Tint", {
                hidden = function()
                    return not IsShowingAll(prefix)
                        or not Cfg(prefix, "incomingCastsTintNotAimed")
                end }),
            Sl(prefix, "incomingCastsHoldTime", "Hold After Cast Ends",
               0, 3, 0.1, SetAndRefresh, {
                desc = "Keep the bar on screen for a moment after the cast finishes or is "
                    .. "interrupted, so a fast interrupt is still readable. 0 hides it "
                    .. "immediately.\n\n"
                    .. "|cff888888Only applies to the Cast Bar display type.|r",
                -- Cast bars only, and PARTY display only: the linger applies
                -- to the bar on the party frame. The detached duplicate has
                -- no independent anchor once its layout bar is returned, so
                -- it is released the moment the cast ends and a hold value
                -- there could never take effect.
                hidden = function()
                    if prefix == "incomingCastsPlayer" then return true end
                    return NotCastBar(prefix)
                end }),
        }},

        { title = "Target Name", preset = "form",
          hidden = Gate(showKey, function() return NotCastBar(prefix) end),
          fields = {
            Sw(prefix, "incomingCastsShowTargetName", "Show Target Name",
               SetAndRefresh, {
                desc = "Append your name after the spell name, e.g. "
                    .. "|cffffffffFireball > Yourname|r.\n\n"
                    .. "|cff888888The game only lets addons ask whether a cast is aimed at "
                    .. "YOU, so this is always your own name. It earns its keep with "
                    .. "Show Casts set to \"All Casts\", where it marks which of the "
                    .. "visible casts are actually coming at you.\n\n"
                    .. "Only applies to the Cast Bar display type.|r" }),
            Sw(prefix, "incomingCastsTargetNameClassColor",
               "Class Color Target Name", SetAndRefresh, {
                hidden = function()
                    return not Cfg(prefix, "incomingCastsShowTargetName")
                end }),
        }},
    }
end

-- ── The Position subtab ────────────────────────────────────────
--
-- The one place the two displays do not share a generator: the detached
-- frame is positioned on the SCREEN and the party bar is positioned
-- against a frame, so they carry different settings under different keys.

local function PositionPage(d)
    local prefix, showKey = d.prefix, d.showKey

    if prefix == "incomingCastsPlayer" then
        return {
            { title = "Position", preset = "form", hidden = Gate(showKey),
              fields = {
                PositionField("incomingCastsPlayerAnchorX", "X Position",
                    "Horizontal position of the incoming cast display.", "x", 0),
                PositionField("incomingCastsPlayerAnchorY", "Y Position",
                    "Vertical position of the incoming cast display.", "y", -200),
                Dd(prefix, "incomingCastsPlayerGrowDirection", "Grow Direction",
                   PLAYER_GROW_OPTIONS, SetAndReposition, {
                    desc = "Direction in which multiple incoming casts stack." }),
                Sl(prefix, "incomingCastsPlayerSpacing", "Spacing",
                   0, 20, 1, SetAndReposition, {
                    desc = "Space between multiple incoming cast frames in pixels." }),
            }},
        }
    end

    return {
        { title = "Position", preset = "form", hidden = Gate(showKey), fields = {
            Dd(prefix, "incomingCastsAnchorPoint", "Anchor Position",
               PARTY_ANCHOR_OPTIONS, SetAndReposition, {
                desc = "Where to anchor the incoming cast display relative to "
                    .. "the party frame." }),
            Dd(prefix, "incomingCastsGrowDirection", "Grow Direction",
               PARTY_GROW_OPTIONS, SetAndReposition, {
                desc = "Direction in which multiple incoming casts stack." }),
            Sl(prefix, "incomingCastsSpacing", "Spacing", 0, 20, 1,
               SetAndReposition, {
                desc = "Space between multiple incoming cast frames in pixels." }),
            Sl(prefix, "incomingCastsOffsetX", "X Offset", -50, 50, 1,
               SetAndReposition, {
                desc = "Horizontal offset from the anchor point." }),
            Sl(prefix, "incomingCastsOffsetY", "Y Offset", -50, 50, 1,
               SetAndReposition, {
                desc = "Vertical offset from the anchor point." }),
        }},
    }
end

-- ── The Display subtab ─────────────────────────────────────────

local function DisplayPage(d)
    local prefix, showKey = d.prefix, d.showKey

    local notCastBar = function() return NotCastBar(prefix) end
    local noIcon     = function() return NoIcon(prefix) end
    local noBorder   = function() return NoBorder(prefix) end
    local castBarGate = Gate(showKey, notCastBar)

    -- Timer text: the toggle shows for either display type; each half of
    -- the group shows only for its own type, and only while the toggle is
    -- on. Written out once each rather than at all nine sites.
    local function noBarTimer()
        return NotCastBar(prefix) or not Cfg(prefix, "incomingCastsShowTimer")
    end
    local function noIconTimer()
        return NotIconType(prefix) or not Cfg(prefix, "incomingCastsShowTimer")
    end

    -- Shape and weight over the one BorderStyle key. ROOT's __index
    -- supplies the "square" fallback for a legacy profile that has none,
    -- and its __newindex is the combat guard, so both go through it.
    local borderKey = ResolveKeyName(prefix, "incomingCastsBorderStyle")
    local borderStyleField, borderWeightField =
        BuzzardFramesOptions:BorderStyleFields({
            id = borderKey, options = BORDERSTYLE_OPTIONS,
            hidden = Gate(showKey, noBorder), onChange = SetAndRefresh,
            default = DefaultFor(borderKey),
            get = function() return ROOT[borderKey] end,
            set = function(_, _, v) ROOT[borderKey] = v end,
        })

    local groups = {
        -- displayHeader, as the card the one ungrouped field sits in.
        { title = "Appearance", preset = "form", hidden = Gate(showKey), fields = {
            Sl(prefix, "incomingCastsMaxBars", "Max Bars", 1, 20, 1,
               SetAndReposition, {
                desc = "Most bars to show at once. Oldest casts are kept, since "
                    .. "they land first.",
                -- Only "All Casts" can honor a bar cap: in the other modes
                -- the filtered-out entries collapse invisibly and the addon
                -- cannot tell which ones you can actually see, so a fixed
                -- internal ceiling is used instead.
                hidden = function() return not IsShowingAll(prefix) end }),
        }},

        { title = "Cast Bar Settings", preset = "form", hidden = castBarGate,
          fields = {
            Sl(prefix, "incomingCastsBarWidth", "Bar Width", 30, 200, 1,
               SetAndReposition),
            Sl(prefix, "incomingCastsBarHeight", "Bar Height", 6, 40, 1,
               SetAndReposition),
        }},

        { title = "Cast Bar Appearance", preset = "form", hidden = castBarGate,
          fields = {
            Sw(prefix, "incomingCastsUseCustomTexture", "Use Custom Texture",
               SetAndRefresh),
            Dd(prefix, "incomingCastsTexture", "Bar Texture",
               StatusbarOptions, SetAndRefresh, {
                hidden = function()
                    return NotCastBar(prefix)
                        or not Cfg(prefix, "incomingCastsUseCustomTexture")
                end }),
            Pct(prefix, "incomingCastsOpacity", "Opacity", 10, 100, 5,
                SetAndRefresh),
            Pct(prefix, "incomingCastsBgOpacity", "Background Opacity",
                0, 100, 5, SetAndRefresh),
        }},

        { title = "Cast Bar Border", preset = "form", hidden = castBarGate,
          fields = {
            Sw(prefix, "incomingCastsShowBorder", "Show Border", SetAndRefresh),
            borderStyleField,
            borderWeightField,
            -- A stepper, not a slider: four whole numbers, and the reader
            -- wants "one more pixel" rather than a position on a track --
            -- the same shape every other border thickness in this panel
            -- takes.
            { control = "stepper", label = "Border Thickness",
              bind = ResolveKeyName(prefix, "incomingCastsBorderThickness"),
              min = 1, max = 4, step = 1,
              onChange = SetAndRefresh, disabled = "combat",
              -- Rounded styles bake their band weight into the art, so
              -- thickness does nothing there.
              hidden = function()
                  if NoBorder(prefix) then return true end
                  local bf = BF()
                  return bf and bf.IsRoundedBorderStyle
                      and bf.IsRoundedBorderStyle(ROOT[borderKey]) or false
              end },
            Col(prefix, "incomingCastsBorderColor", "Border Color",
                { hidden = noBorder }),
        }},

        { title = "Cast Bar Icon", preset = "form", hidden = castBarGate,
          fields = {
            Sw(prefix, "incomingCastsShowIcon", "Show Spell Icon",
               SetAndReposition),
            Dd(prefix, "incomingCastsIconSide", "Icon Side",
               ICONSIDE_OPTIONS, SetAndReposition, { hidden = noIcon }),
            Pct(prefix, "incomingCastsIconSizePct", "Icon Size", 25, 300, 5,
                SetAndReposition, {
                hidden = noIcon,
                desc = "Icon size relative to the height of the cast bar." }),
            Sl(prefix, "incomingCastsIconGap", "Icon Gap", 0, 20, 1,
               SetAndReposition, {
                hidden = noIcon,
                desc = "Space between the icon and the bar, in pixels." }),
            Sl(prefix, "incomingCastsIconXOffset", "Icon X Offset", -40, 40, 1,
               SetAndReposition, { hidden = noIcon }),
            Sl(prefix, "incomingCastsIconYOffset", "Icon Y Offset", -40, 40, 1,
               SetAndReposition, { hidden = noIcon }),
        }},

        { title = "Cast Bar Text", preset = "form", hidden = castBarGate,
          fields = {
            Sw(prefix, "incomingCastsShowSpellName", "Show Spell Name",
               SetAndRefresh),
            Dd(prefix, "incomingCastsNameAlign", "Name Alignment",
               ALIGN_OPTIONS, SetAndRefresh),
            Dd(prefix, "incomingCastsNameFont", "Name Font",
               FontOptions, SetAndRefresh),
            Sl(prefix, "incomingCastsNameFontSize", "Name Font Size",
               6, 24, 1, SetAndRefresh),
            Dd(prefix, "incomingCastsNameFontBorder", "Name Font Border",
               FONTBORDER_OPTIONS, SetAndRefresh),
            Col(prefix, "incomingCastsNameColor", "Cast Name Color"),
        }},

        { title = "Icon Settings", preset = "form",
          hidden = Gate(showKey, function() return NotIconType(prefix) end),
          fields = {
            Sl(prefix, "incomingCastsIconSize", "Icon Size", 10, 50, 1,
               SetAndReposition),
        }},

        -- One shared Timer Text group for both display types: the toggle
        -- always shows, the bar-specific and icon-specific options each
        -- show only for their display type and only while it is on.
        { title = "Timer Text", preset = "form", hidden = Gate(showKey),
          fields = {
            Sw(prefix, "incomingCastsShowTimer", "Show Timer Text",
               SetAndRefresh, {
                desc = "Show remaining cast time on the cast bar or icon." }),

            Dd(prefix, "incomingCastsTimerAlign", "Timer Alignment",
               ALIGN_OPTIONS, SetAndRefresh, { hidden = noBarTimer }),
            Dd(prefix, "incomingCastsBarTimerFont", "Timer Font",
               FontOptions, SetAndRefresh, { hidden = noBarTimer }),
            Sl(prefix, "incomingCastsBarTimerFontSize", "Timer Font Size",
               6, 24, 1, SetAndRefresh, { hidden = noBarTimer }),
            Dd(prefix, "incomingCastsBarTimerFontBorder", "Timer Font Border",
               FONTBORDER_OPTIONS, SetAndRefresh, { hidden = noBarTimer }),
            -- Cast Bar timer text only; the icon timer inherits the icon's
            -- own coloring.
            Col(prefix, "incomingCastsTimeColor", "Cast Time Color",
                { hidden = noBarTimer }),

            Sw(prefix, "incomingCastsIconAutoScale", "Auto Scale Timer Text",
               SetAndReposition, {
                hidden = noIconTimer,
                desc = "When enabled, timer text size scales proportionally with the icon "
                    .. "size. Use the scale slider to fine-tune. When disabled, a fixed "
                    .. "font size is used instead." }),
            Sl(prefix, "incomingCastsIconTimerScale", "Timer Text Scale",
               0.1, 3.0, 0.1, SetAndReposition, {
                desc = "Scale of the timer text displayed on the icon.",
                hidden = function()
                    return noIconTimer()
                        or not Cfg(prefix, "incomingCastsIconAutoScale")
                end }),
            Sl(prefix, "incomingCastsIconTimerFontSize", "Timer Font Size",
               6, 24, 1, SetAndReposition, {
                desc = "Font size of the timer text displayed on the icon.",
                hidden = function()
                    return noIconTimer()
                        or Cfg(prefix, "incomingCastsIconAutoScale") and true or false
                end }),
            Dd(prefix, "incomingCastsIconTimerFont", "Timer Font",
               FontOptions, SetAndReposition, {
                desc = "Font of the timer text displayed on the icon.",
                hidden = noIconTimer }),
            Dd(prefix, "incomingCastsIconTimerFontBorder", "Timer Font Border",
               ICON_FONTBORDER_OPTIONS, SetAndReposition, {
                desc = "Border style of the timer text displayed on the icon.",
                hidden = noIconTimer }),
        }},
    }

    -- previewHeader + testPosition: the party display only.
    if prefix == "incomingCasts" then
        groups[#groups + 1] = {
            title = "Preview", preset = "form", hidden = Gate(showKey), fields = {
                -- Not a stored setting and not combat-gated -- the Ace
                -- toggle carries neither `disabled` nor a profile key. It
                -- reads and writes the module's live preview state.
                { control = "switch", label = "Test Position",
                  id = "testPosition",
                  desc = "Show preview cast bars on the party preview frame.",
                  get = function()
                      local bf = BF()
                      local ic = bf and bf.IncomingCasts
                      return ic and ic._partyPreviewShown or false
                  end,
                  set = function(_, _, v)
                      local bf = BF()
                      local ic = bf and bf.IncomingCasts
                      if not ic then return end
                      if v then ic:ShowPartyPreview()
                      else      ic:HidePartyPreview() end
                  end },
            },
        }
    end

    return groups
end

-- ── The pages ──────────────────────────────────────────────────

local SUBPAGES = {
    optionsTab  = OptionsPage,
    positionTab = PositionPage,
    displayTab  = DisplayPage,
}

function BuzzardFramesOptions:IncomingCastsSubPage(displayId, subtabId)
    local d     = DISPLAYS[displayId]
    local build = SUBPAGES[subtabId]
    if not (d and build) then return { groups = {} } end

    local groups = { OffNotes(d) }
    for _, g in ipairs(build(d)) do groups[#groups + 1] = g end

    return {
        -- The module's profile, wearing the shape of a table. Every `bind`
        -- on this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- which is what
        -- makes right-click "Reset to default" work on every bound field
        -- without any of them declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end

-- The section root. It has real settings of its own -- the intro and the
-- master toggle sit at the Ace section's root, above both display groups
-- -- so this REPLACES the placeholder page rather than letting the parent
-- descend to its first child.
function BuzzardFramesOptions:IncomingCastsPage()
    return {
        db       = Root,
        defaults = Defaults,
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Show incoming enemy casts targeting you. Tracks "
                      .. "nameplate enemies and displays cast bars or icons.\n\n"
                      .. "|cffffd100This feature only works in Dungeons and "
                      .. "Delves.|r" },
            }},
            { title = "Incoming Casts", preset = "form", fields = {
                { control = "switch", label = "Enable Incoming Casts",
                  bind = "incomingCastsEnabled", wide = true,
                  desc = "Track and display enemy casts targeting you.",
                  disabled = "combat", onChange = MasterChanged },
            }},
        },
    }
end

-- The section's route children: the two displays, each presenting its own
-- three subtabs as a strip. Built from the published lists rather than
-- restated, so the ids the pages are looked up by ARE the ids the routes
-- carry.
function BuzzardFramesOptions:IncomingCastsRoutes()
    local out = {}
    for i, display in ipairs(self.INCOMINGCASTS_SUBTABS) do
        local kids = {}
        for j, sub in ipairs(self.INCOMINGCASTS_DISPLAY_TABS) do
            kids[j] = {
                id = sub.id, title = sub.title,
                page = function()
                    return self:IncomingCastsSubPage(display.id, sub.id)
                end,
            }
        end
        out[i] = {
            id = display.id, title = display.title,
            navigator = "tabs", children = kids,
        }
    end
    return out
end
