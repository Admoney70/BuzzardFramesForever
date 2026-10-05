-- ============================================================
-- BuzzardFramesOptions: Pages_Buffs.lua
-- The Raid/Party Frames > Buffs section, in BuzzardPanel.
--
-- The panel equivalent of the BUFFS half of BuzzardFrames'
-- Options/Options_Auras.lua: BF:BuildAurasOptions with
-- deps.group == "aurasBuffs", which per GROUP_TABS emits exactly two
-- predefined subtabs --
--
--     tabBuffs   "Buffs"          order 1   sub-category `buffs`
--     tabBigDef  "Big Defensive"  order 2   sub-category `bigDef`
--
-- -- and those two are what this file carries across, each as a route of
-- its own under `raidPartyFrames/aurasBuffs`, drawn as a strip by the
-- `tabs` navigator that node declares.
--
-- WHAT THIS FILE DOES NOT OWN, and where it attaches. The Buffs section
-- grows several more subtabs at runtime, all of them built by code
-- elsewhere in Options_Auras.lua and migrated by another page file:
--
--   * applySingleBuffSubtab (Single Buffs) and applyContainerSubtabs
--     (the custom aura containers, plus the "Add Container" pseudo-tab)
--     attach to `host.args`, which IS the SECTION args table. In panel
--     terms they are SIBLING routes of tabBuffs and tabBigDef under
--     `raidPartyFrames/aurasBuffs` -- they sit beside these two in the
--     same tab strip.
--   * applyPresetsSubtab (Assigned Spells) and the Blacklist attach to
--     `host.buffsArgs`, which IS `tabBuffs.args` -- INSIDE the Buffs
--     tab, not beside it.
--
-- So the tabBuffs page below deliberately claims only what tabBuffs
-- itself declares. It does not spread into, gate, or reserve the space
-- those surfaces land in; the agent that owns them decides their shape.
--
-- Storage did not move. Every key still lives at
-- rpDB.profile.auras.<subcat>[key] (per-Layout off) or
-- flat.auras.<subcat>[key] (on), and NOTHING in this file decides which:
-- the reads, the writes, the invalidations, the scoped refresh and the
-- per-Layout scope strip all come from Pages_AuraShared.lua
-- (AuraRoot / AuraDefaults / AuraEffect / AuraScopeStrip /
-- AuraPreviewField / AuraSubcatView). An aura key routed two different
-- ways by two pages is a setting that reads from one place and writes to
-- another, which is exactly what that shared file exists to prevent.
--
-- The two exceptions are honest ones, and they are the Ace source's too:
-- `showRaidBuffs` lives in BF.acDB.profile (one value for the whole
-- profile, which is what the "Global Options" heading says), and the
-- Aura Preview dropdown lives in BF.db.global.
--
-- Nothing at file scope touches BuzzardFrames: BF() is read inside the
-- functions, at the moment the panel is used.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- Pages_AuraShared publishes these on the same table. Read through a
-- function rather than captured at file scope, because the .toc load
-- order between two page files is not this file's business.
local function View(subcat)
    return BuzzardFramesOptions.AuraSubcatView(subcat)
end

local function Root(subcat)
    return BuzzardFramesOptions:AuraRoot(subcat)
end

-- What a key resets TO, for the handful of fields that cannot bind (the
-- colors, whose stored shape is not the shape the color control reads).
-- BuzzardFrames' own defaults table is the single source.
local function Def(subcat, key)
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile and d.profile.auras and d.profile.auras[subcat]
    return d and d[key]
end

-- ── Sub-category trackers ──────────────────────────────────────
--
-- The Ace page carried an invisible `description` widget per subtab
-- (makeSubcatTracker) whose `name` callback fired on every render and
-- stamped BF._currentAurasSubcat -- which is what tells the dummy-aura
-- preview which sub-category is on screen (Auras/DummyAuras.lua). A
-- render hook hidden in a widget has no panel equivalent and needs none:
-- the panel has route observers, which say the same thing outright and
-- fire on ENTRY rather than on every repaint. Same shape Pages_Preview
-- uses for the section tracker.
--
-- BF._currentSection is stamped here too. That was the SECTION-level
-- _sectionTracker in the Ace source (both aura sections report "auras"),
-- and it drives preview context and the Modifying-Layout dropdown; the
-- section root it lived on has no panel page, so it rides the subtab
-- entries instead. If the agent owning the sibling container subtabs
-- stamps it as well, that is harmless -- it is the same value.
--
-- Not carried across: BF:ScheduleWidgetLabelRecolor(), which repaints
-- freshly-pooled AceGUI slider/dropdown labels white. It is a fix for
-- the Ace dialog's widget pool and has nothing to say about this panel.
local function EnterSubcat(app, subcat)
    local bf = BF()
    if not bf then return end
    -- The SECTION name, which drives the dummy-aura preview's context. A
    -- page built under a Custom Frame Group scope reports
    -- "customFrameAuras" instead, exactly as the Ace CFG page's own
    -- _sectionTracker did -- otherwise the preview draws for the raid.
    local section = (bf.BFOSectionName and bf:BFOSectionName()) or "auras"
    if bf._currentSection ~= section then
        bf._currentSection = section
    end
    bf._currentAurasSubcat      = subcat
    bf._currentAurasScopeSubcat = subcat
    -- Always written -- nil for a plain subtab -- so a scoped stamp left
    -- by the Debuff Preset/Filter subtab never outlives it.
    bf._currentAurasScopeToggle = nil
    -- A plain aura subtab is NOT a container subtab, so the index a
    -- container subtab stamps is cleared on the way out, along with the
    -- container preview filter -- without which the dummy-aura preview
    -- keeps showing only that one container here. Guarded by the index
    -- change, so it fires once per container -> plain-subtab transition.
    local leftContainer = bf._currentContainerIndex ~= nil
    if leftContainer then
        bf._currentContainerIndex = nil
        if bf.ClearAuraPreview then bf:ClearAuraPreview() end
    end
    -- REPAINTED ON EVERY ARRIVAL, not only when a container was left.
    -- The Ace tracker fired on every render and the dialog swept the
    -- previews on every rebuild, so the dummy auras always followed the
    -- stamp. Here the stamp is written on entry and nothing else repaints
    -- for it: Buffs and Debuffs share one section key, so the section
    -- observer's repaint does not fire between them, and the previews kept
    -- drawing the sub-category of whichever subtab was left.
    if not InCombatLockdown() then
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
        if leftContainer and app then app:RefreshPage() end
    end
end

local observersArmed = false

-- Armed the first time a page is built rather than at file scope: the app
-- exists only once the panel has been opened.
local function EnsureObservers()
    if observersArmed then return end
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    local app = Panel and Panel:GetApp("BuzzardFrames")
    if not app then return end
    observersArmed = true
    -- buffsAssigned is the Buff Preset/Filter surface, which the Ace panel
    -- tracked with a widget of its own (_presetsTracker): it is a buff
    -- subtab like the other two, so arriving on it names the section,
    -- names the sub-category and clears the container index -- without
    -- which a container tab's narrowed preview stayed on screen here.
    for id, subcat in pairs({ tabBuffs = "buffs", tabBigDef = "bigDef",
                              buffsAssigned = "buffs" }) do
        -- WithScope(nil, ...): observers fire from the navigation, BEFORE
        -- the render that would rebind the scope, so on a Custom Frame
        -- Groups -> Raid/Party move this body would otherwise run with the
        -- group's scope still bound -- stamping "customFrameAuras" onto a
        -- Raid/Party arrival, and writing every stamp through the proxy.
        app:RegisterRouteObserver("raidPartyFrames/aurasBuffs/" .. id,
            function(isActive, _, appNow)
                if not isActive then return end
                BuzzardFramesOptions:WithScope(nil, EnterSubcat, appNow or app, subcat)
            end)
        -- The Custom Frame Groups twin: the same page under the group's
        -- scope, so the entry stamp names the custom-frame section and
        -- the preview reads the group's own sub-category.
        app:RegisterRouteObserver("customFrames/aurasBuffs/" .. id,
            function(isActive, _, appNow)
                if not isActive then return end
                local scope = BuzzardFramesOptions.CFGScopeFor
                              and BuzzardFramesOptions:CFGScopeFor("aurasBuffs")
                if scope then
                    BuzzardFramesOptions:WithScope(scope, EnterSubcat, appNow or app, subcat)
                else
                    EnterSubcat(appNow or app, subcat)
                end
            end)
    end
end

-- The same arming, for the Buff Preset/Filter page -- which lives in
-- Pages_AuraContainers.lua and is therefore the one subtab in this list
-- whose own page cannot reach the local above. Without it, opening the
-- panel straight onto that subtab arms nothing, and the first move from a
-- container tab to it would leave the container's narrowed preview up.
function BuzzardFramesOptions:EnsureBuffsObservers()
    EnsureObservers()
end

-- ── Border Style (v54) ─────────────────────────────────────────
--
-- Each feature's four-value style dropdown, replacing the old
-- "Blizzard-style Borders" checkbox. Reads derive from the legacy toggle
-- when no style key is stored (no migration needed); writes keep the
-- toggle in sync.
-- SHAPES only. Rounded's two weights are the Thin/Thick strip beside this
-- one -- see Pages_BorderStyle.lua -- rather than a fourth entry here.
local BORDER_STYLE_OPTIONS = {
    { value = "blizzard", text = "Blizzard-Style" },
    { value = "flat",     text = "Square"         },
    { value = "rounded",  text = "Rounded"        },
}
local BORDER_STYLE_DESC =
    "Blizzard-Style uses Blizzard's aura border art. Square draws the flat "
    .. "colored border. Rounded masks the icon to a rounded rectangle inside "
    .. "a colored frame."

-- Mirrors BorderStyleOf in Auras/ContainerFactory.lua -- the two MUST
-- agree or the dropdown reports a style the frames don't render.
--
-- The legacy *BlizzardBorders flag is OR'd in exactly as the runtime does,
-- rather than being consulted only when the style key is absent. That
-- became load-bearing when *BorderStyle gained a "flat" default: AceDB's
-- copyDefaults rawsets a missing default straight into the live profile,
-- so a profile that had chosen Blizzard borders would suddenly carry a
-- non-nil style of "flat" and this would report Square over
-- Blizzard-rendering frames -- also un-hiding the Border Color and Border
-- Thickness widgets, whose `hidden` predicates key off this same result.
--
-- Safe because BorderStyleSet below always writes the companion flag (true
-- only for "blizzard"), so a stale `true` can only mean a profile that
-- predates the style key. Rounded is checked first so a genuinely rounded
-- pick is never masked by a leftover flag.
local function AuraBorderStyle(subcat, styleKey, blizzKey)
    local sp = View(subcat)
    local v  = sp and sp[styleKey]
    if v == "rounded" or v == "rounded_thick" then return v end
    if v == "blizzard" or (sp and sp[blizzKey]) then return "blizzard" end
    return v or "flat"
end

local function BorderStyleGet(subcat, styleKey, blizzKey)
    return function() return AuraBorderStyle(subcat, styleKey, blizzKey) end
end

-- Legacy-toggle sync FIRST, then the style key's own write -- the order
-- the Ace setter used, and the order the runtime readers assume.
local function BorderStyleSet(subcat, blizzKey)
    return function(node, _, v)
        if InCombatLockdown() then return end
        local root = Root(subcat)
        root[blizzKey] = (v == "blizzard")
        root[node.bind] = v
    end
end

-- ── Two-axis grow directions (v34) ─────────────────────────────
--
-- Values are "PRIMARY_SECONDARY" (fill direction, then wrap direction).
-- Legacy single-axis stored values are normalized on read (anchor-aware,
-- appearance-preserving) so the dropdown always shows a valid selection.
--
-- The list is in the order the Ace dialog showed it: the `values` table
-- carried no `sorting`, so it sorted alphabetically -- which for these
-- eight is also the source's own stated display order.
local GROW_OPTIONS = {
    { value = "DOWN_LEFT",  text = "Down, then Left"  },
    { value = "DOWN_RIGHT", text = "Down, then Right" },
    { value = "LEFT_DOWN",  text = "Left, then Down"  },
    { value = "LEFT_UP",    text = "Left, then Up"    },
    { value = "RIGHT_DOWN", text = "Right, then Down" },
    { value = "RIGHT_UP",   text = "Right, then Up"   },
    { value = "UP_LEFT",    text = "Up, then Left"    },
    { value = "UP_RIGHT",   text = "Up, then Right"   },
}

local function GrowGet(subcat, growKey, anchorKey)
    return function()
        local bf = BF()
        if not (bf and bf.NormalizeGrowDirection) then return nil end
        local sp = View(subcat) or {}
        return bf.NormalizeGrowDirection(sp[growKey], sp[anchorKey])
    end
end

-- Vertical-primary predicate: drives the Per Column / Column Spacing
-- label swaps.
local function GrowIsVertical(subcat, growKey, anchorKey)
    return function()
        local bf = BF()
        if not (bf and bf.NormalizeGrowDirection) then return false end
        local sp = View(subcat) or {}
        return bf.GrowDirectionIsVertical(
            bf.NormalizeGrowDirection(sp[growKey], sp[anchorKey])) and true or false
    end
end

-- Writing an anchor point auto-applies that anchor's default grow
-- direction (BF.GROW_DEFAULT_FOR_ANCHOR), then notifies -- the panel's
-- copy of makeAnchorSet. Both writes go through the routed root, so each
-- carries its own invalidation; the notify becomes a page refresh,
-- because the Grow Direction dropdown beside this one now shows a
-- different value and the Per Row / Per Column labels may have swapped.
local function AnchorSet(subcat, growKey)
    return function(node, ctx, v)
        if InCombatLockdown() then return end
        local root = Root(subcat)
        root[node.bind] = v
        local bf  = BF()
        local def = bf and bf.GROW_DEFAULT_FOR_ANCHOR
                    and bf.GROW_DEFAULT_FOR_ANCHOR[v]
        if def then root[growKey] = def end
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end
end

-- ── Colors ────────────────────────────────────────────────────
--
-- Stored as { r =, g =, b =, a = }; the color control reads and writes
-- { r, g, b, a } by index. So these keep get/set adapters rather than a
-- bind, and declare `id` + `default` so the right-click Undo and Reset
-- still work. The nil fallback is the Ace getAurasColor's own.
local function GetColor(subcat, key)
    return function()
        local sp = View(subcat)
        local c  = (sp and sp[key]) or { r = 0, g = 0, b = 0, a = 0.8 }
        return { c.r or 0, c.g or 0, c.b or 0, c.a or 1 }
    end
end

local function SetColor(subcat, key)
    return function(_, _, v)
        if InCombatLockdown() then return end
        Root(subcat)[key] = { r = v[1], g = v[2], b = v[3], a = v[4] }
    end
end

local function ColorDefault(subcat, key)
    local d = Def(subcat, key)
    if type(d) ~= "table" then return nil end
    return { d.r or 0, d.g or 0, d.b or 0, d.a or 1 }
end

-- ── Visibility predicates ──────────────────────────────────────
--
-- The library has no group-level `hidden`, so the Ace inline groups'
-- own predicates ride every field inside them instead. The card headers
-- stay while their contents are hidden -- see the notes file.
local function BuffsHidden()
    local sp = View("buffs")
    return sp and sp.showBuffs == false
end

local function BigDefHidden()
    local sp = View("bigDef")
    return not (sp and sp.showBigDef)
end

local function BigDefSingle()
    local sp = View("bigDef")
    return (sp and sp.bigDefMaxCount or 1) <= 1
end

local function BigDefNoGlow()
    if BigDefHidden() then return true end
    local sp = View("bigDef")
    return not (sp and sp.bigDefShowGlow)
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every field on these pages binds into its sub-category's root and names
-- the refresh that sub-category needs, and every slider and color
-- declares "mouseup". These say that once instead of at forty call sites.

local function Sl(bind, label, lo, hi, effect, opts)
    local f = { control = "slider", label = label, bind = bind,
                min = lo, max = hi, step = 1,
                -- The Ace file hand-rolled a mouse-up gate for exactly
                -- this: a trailing timer still ran the full frame walk
                -- mid-drag whenever the reader paused. The library owns
                -- that scheduler now.
                refresh = "mouseup",
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A stepper, not a slider: a handful of whole numbers, where the reader
-- wants "one more icon" rather than a position on a track, and the number
-- can be typed when they know it. No `refresh = "mouseup"` either -- a
-- stepper has no drag to coalesce, so the write IS the gesture.
local function St(bind, label, lo, hi, effect, opts)
    local f = { control = "stepper", label = label, bind = bind,
                min = lo, max = hi, step = 1,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sw(bind, label, effect, opts)
    local f = { control = "switch", label = label, bind = bind,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Dd(bind, label, options, effect, opts)
    local f = { control = "dropdown", label = label, bind = bind,
                labelPlacement = "above", options = options,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A gate in the card HEADER, and the card collapses when it is off --
-- the Ace page's `hidden = <subcat>Hidden` made visible. `id` and
-- `default` are what make it reset with the rest of its card from the
-- header's own menu.
--
-- The library's gate takes no `disabled`, so the Ace widget's
-- `disabled = InCombatLockdown` survives as the guard inside the setter
-- (which is also what setAuras_shared itself did). Same trade the other
-- migrated pages make.
local function Gate(subcat, key, tooltip, desc, effect)
    return {
        id      = key,
        default = Def(subcat, key),
        tooltip = tooltip,
        desc    = desc,
        get     = function()
            local sp = View(subcat)
            return sp and sp[key]
        end,
        set     = function(_, _, v)
            if InCombatLockdown() then return end
            Root(subcat)[key] = v
            if effect then effect() end
        end,
    }
end

-- ── The two subtabs ────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The ids and titles are GROUP_TABS.aurasBuffs'
-- own, in its own order.
BuzzardFramesOptions.BUFFS_SUBTABS = {
    { id = "tabBuffs",  title = "Buffs"         },
    { id = "tabBigDef", title = "Big Defensive" },
}

local PAGES = {}

-- ── tabBuffs ───────────────────────────────────────────────────
--
-- Ace order: the scope row (0.1/0.2, injected), the "Buffs" header
-- (0.35), showBuffs (0.4), buffSize (0.5), maxBuffs (0.55),
-- buffPositionGroup (21), buffSpacingGroup (31), buffBorderGroup (32),
-- buffGlobalGroup (40).
function PAGES.tabBuffs()
    local effect   = BuzzardFramesOptions:AuraEffect("buffs")
    local vertical = GrowIsVertical("buffs", "buffGrowDirection", "buffAnchorPoint")
    local horiz    = function() return not vertical() end
    local hid      = BuffsHidden

    -- Shape and weight, over the one `buffBorderStyle` key.
    local BuffBorderStyle, BuffBorderWeight =
        BuzzardFramesOptions:BorderStyleFields({
            bind = "buffBorderStyle", options = BORDER_STYLE_OPTIONS,
            desc = BORDER_STYLE_DESC, hidden = hid, onChange = effect,
            get = BorderStyleGet("buffs", "buffBorderStyle", "buffBlizzardBorders"),
            set = BorderStyleSet("buffs", "buffBlizzardBorders"),
        })

    return {
        -- The Ace "Buffs" header is never hidden, so the tab still reads
        -- as Buffs when Show Buffs is off and the rest of the page is
        -- gone. The card header is that header, and the gate in it is
        -- Show Buffs -- which had no `disabled` of its own in the source
        -- either.
        { title = "Buffs", preset = "form",
          toggle = Gate("buffs", "showBuffs", "Show Buffs", nil, effect),
          fields = {
            Sl("buffSize", "Buff Size", 2, 50, effect, { hidden = hid }),
            St("maxBuffs", "Max Buffs", 1, 8, effect,
               { hidden = hid, desc = "Maximum number of buff icons to show." }),
            -- One setting, two labels. The Ace widget's `name` was a
            -- function that swapped Row for Column with the grow
            -- direction; a panel label is a string, so the swap is two
            -- fields over one bind with complementary predicates.
            St("buffsPerRow", "Buffs Per Row", 1, 8, effect,
               { hidden = function() return hid() or vertical() end }),
            St("buffsPerRow", "Buffs Per Column", 1, 8, effect,
               { hidden = function() return hid() or horiz() end }),
        }},

        { title = "Position", preset = "form", fields = {
            -- The Ace triplet -- Anchor Point, X Offset, Y Offset -- as the
            -- panel's one anchor pad over the same three flat keys. The
            -- point is written through its own `set` so picking a cell
            -- still resets the Grow Direction to that anchor's default,
            -- exactly as picking from the dropdown did.
            { control = "anchor", label = "Anchor Point",
              binds = { point = { bind = "buffAnchorPoint",
                                  set  = AnchorSet("buffs", "buffGrowDirection") },
                        x     = "buffOffsetX",
                        y     = "buffOffsetY" },
              min = -60, max = 60, refresh = "mouseup",
              desc = "Changing the anchor point resets the Grow Direction "
                  .. "to that anchor's default.",
              hidden = hid, disabled = "combat", onChange = effect },
            Dd("buffGrowDirection", "Grow Direction", GROW_OPTIONS, effect,
               { hidden = hid,
                 desc = "Fill direction, then the direction new rows/columns wrap.",
                 get = GrowGet("buffs", "buffGrowDirection", "buffAnchorPoint") }),
        }},

        { title = "Buff Spacing", preset = "form", fields = {
            St("buffSpacing", "Icon Spacing", 0, 10, effect,
               { hidden = hid,
                 desc = "Gap in pixels between icons within a row." }),
            St("buffRowSpacing", "Row Spacing", 0, 10, effect,
               { hidden = function() return hid() or vertical() end,
                 desc = "Gap in pixels between rows/columns." }),
            St("buffRowSpacing", "Column Spacing", 0, 10, effect,
               { hidden = function() return hid() or horiz() end,
                 desc = "Gap in pixels between rows/columns." }),
        }},

        { title = "Border", preset = "form", fields = {
            BuffBorderStyle,
            BuffBorderWeight,
            -- A stepper, not a slider: six whole numbers, and the reader
            -- wants "one more pixel" rather than a position on a track.
            { control = "stepper", label = "Border Thickness",
              bind = "buffBorderThickness", min = 0, max = 5, step = 1,
              desc = "Border thickness in pixels. 0 removes the border.",
              disabled = "combat", onChange = effect,
              hidden = function()
                  if hid() then return true end
                  return AuraBorderStyle("buffs", "buffBorderStyle",
                                         "buffBlizzardBorders") ~= "flat"
              end },
            { control = "color", label = "Border Color", alpha = true,
              id = "buffBorderColor", default = ColorDefault("buffs", "buffBorderColor"),
              desc = "Color of the buff icon border (tints the rounded frame "
                  .. "in Rounded styles).",
              disabled = "combat", refresh = "mouseup",
              hidden = function()
                  if hid() then return true end
                  return AuraBorderStyle("buffs", "buffBorderStyle",
                                         "buffBlizzardBorders") == "blizzard"
              end,
              get = GetColor("buffs", "buffBorderColor"),
              set = SetColor("buffs", "buffBorderColor"),
              onChange = effect },
        }},

        -- ── No Global Options card here ────────────────────────
        --
        -- The Ace source DECLARES `buffGlobalGroup` on this tab, which is
        -- why a straight reading of the file puts it here -- but it never
        -- RENDERS here. `applyPresetsSubtab` (Options_Auras.lua ~:1524)
        -- takes it back off again on every rebuild:
        --
        --     local globalGroup = args.buffGlobalGroup
        --     if globalGroup then
        --         args.buffGlobalGroup = nil
        --         ... sa.showRaidBuffs = raidBuffs (order 4)
        --
        -- so Raid Buffs is drawn flattened onto the Assigned Spells
        -- subtab, at order 4, matching Debuffs -- whose own
        -- debuffGlobalGroup has always sat on its Preset/Filter subtab.
        -- The relocation is done at rebuild time rather than in the
        -- section assembly, which is what makes it easy to miss.
        --
        -- It lives in Pages_AuraContainers.lua's AssignedSpellsPage
        -- accordingly. Emitting it here as well would put one stored
        -- value (acDB.profile.showRaidBuffs) behind two switches on two
        -- pages, which is the bug this comment exists to prevent
        -- somebody re-introducing from the declaration site.
        --
        -- Note also that the wrapper's `hidden = buffsHidden` is NOT
        -- carried across there, deliberately: Show Buffs lives on THIS
        -- tab, so gating the control on it would make it vanish from a
        -- page that cannot explain why.
    }
end

-- ── tabBigDef ──────────────────────────────────────────────────
--
-- Ace order: the scope row (0.1/0.2, injected), the "Big Defensive"
-- header (0.35), showBigDef (0.4), bigDefSize (0.5), bigDefMaxCount
-- (0.55), bigDefShowGlow (0.6), bigDefGlowColor (4.1), bigDefGlowStyle
-- (4.2), bigDefPositionGroup (21), bigDefSpacingGroup (26),
-- bigDefBorderGroup (26.5). No Global Options group on this tab.
--
-- Every widget here writes through setAurasBigDef_shared rather than
-- setAuras_shared, which is what `bigDef = true` on AuraEffect selects:
-- RefreshBigDef as the fallback refresh instead of RefreshAllAuras.
function PAGES.tabBigDef()
    local effect   = BuzzardFramesOptions:AuraEffect("bigDef", true)
    local vertical = GrowIsVertical("bigDef", "bigDefGrowDirection", "bigDefAnchor")
    local horiz    = function() return not vertical() end
    local hid      = BigDefHidden
    -- The grow/per-row/spacing widgets are meaningless with a single
    -- icon, which is what the Ace predicates said.
    local one      = function() return hid() or BigDefSingle() end

    local BigDefBorderStyle, BigDefBorderWeight =
        BuzzardFramesOptions:BorderStyleFields({
            bind = "bigDefBorderStyle", options = BORDER_STYLE_OPTIONS,
            desc = BORDER_STYLE_DESC, hidden = hid, onChange = effect,
            get = BorderStyleGet("bigDef", "bigDefBorderStyle",
                                 "bigDefBlizzardBorders"),
            set = BorderStyleSet("bigDef", "bigDefBlizzardBorders"),
        })

    return {
        { title = "Big Defensive", preset = "form",
          toggle = Gate("bigDef", "showBigDef", "Show Big Defensive Icon",
              "Show a single large icon for BIG_DEFENSIVE auras (major "
              .. "defensive cooldowns)", effect),
          fields = {
            Sl("bigDefSize", "Icon Size", 2, 60, effect, { hidden = hid }),
            St("bigDefMaxCount", "Max Defensives", 1, 5, effect,
               { hidden = hid,
                 desc = "Maximum number of Big Defensive icons to show at once." }),
            -- One setting, two labels, as on the Buffs tab: the Ace
            -- widget's `name` swapped Row for Column with the grow
            -- direction, so the swap is two fields over one bind with
            -- complementary predicates.
            St("bigDefIconsPerRow", "Icons Per Row", 1, 5, effect,
               { hidden = function() return one() or vertical() end }),
            St("bigDefIconsPerRow", "Icons Per Column", 1, 5, effect,
               { hidden = function() return one() or horiz() end }),
        }},

        { title = "Position", preset = "form", fields = {
            { control = "anchor", label = "Anchor Point",
              binds = { point = { bind = "bigDefAnchor",
                                  set  = AnchorSet("bigDef", "bigDefGrowDirection") },
                        x     = "bigDefOffsetX",
                        y     = "bigDefOffsetY" },
              min = -60, max = 60, refresh = "mouseup",
              desc = "Changing the anchor point resets the Grow Direction "
                  .. "to that anchor's default.",
              hidden = hid, disabled = "combat", onChange = effect },
            Dd("bigDefGrowDirection", "Grow Direction", GROW_OPTIONS, effect,
               { hidden = one,
                 desc = "Fill direction, then the direction new rows/columns wrap.",
                 get = GrowGet("bigDef", "bigDefGrowDirection", "bigDefAnchor") }),
        }},

        { title = "Spacing", preset = "form", fields = {
            St("bigDefSpacing", "Icon Spacing", 0, 10, effect,
               { hidden = one, desc = "Gap in pixels between icons." }),
            St("bigDefRowSpacing", "Row Spacing", 0, 10, effect,
               { hidden = function() return one() or vertical() end,
                 desc = "Gap in pixels between rows/columns." }),
            St("bigDefRowSpacing", "Column Spacing", 0, 10, effect,
               { hidden = function() return one() or horiz() end,
                 desc = "Gap in pixels between rows/columns." }),
        }},

        { title = "Border", preset = "form", fields = {
            BigDefBorderStyle,
            BigDefBorderWeight,
            { control = "stepper", label = "Border Thickness",
              bind = "bigDefBorderThickness", min = 0, max = 5, step = 1,
              desc = "Border thickness in pixels. 0 removes the border.",
              disabled = "combat", onChange = effect,
              hidden = function()
                  if hid() then return true end
                  return AuraBorderStyle("bigDef", "bigDefBorderStyle",
                                         "bigDefBlizzardBorders") ~= "flat"
              end },
            { control = "color", label = "Border Color", alpha = true,
              id = "bigDefBorderColor",
              default = ColorDefault("bigDef", "bigDefBorderColor"),
              desc = "Color of the big defensive icon border (tints the "
                  .. "rounded frame in Rounded styles).",
              disabled = "combat", refresh = "mouseup",
              hidden = function()
                  if hid() then return true end
                  return AuraBorderStyle("bigDef", "bigDefBorderStyle",
                                         "bigDefBlizzardBorders") == "blizzard"
              end,
              get = GetColor("bigDef", "bigDefBorderColor"),
              set = SetColor("bigDef", "bigDefBorderColor"),
              onChange = effect },
        }},

        -- Glow. Show Glow is the card's HEADER gate, so the card collapses
        -- to its header when the glow is off -- the same trade the "Big
        -- Defensive" card makes with Show Big Defensive Icon. The whole
        -- card goes when the sub-category itself is hidden.
        { title = "Glow", preset = "form", hidden = hid,
          toggle = Gate("bigDef", "bigDefShowGlow", "Show Glow",
              "Show a glow ring on the Big Defensive icon while it is shown.",
              effect),
          fields = {
            -- Steady and Pulsing are the ONLY glow styles by design:
            -- every other glow style is OnUpdate-driven and SetScript is
            -- refused on engine-owned aura buttons.
            { control = "color", label = "Glow Color", alpha = true,
              id = "bigDefGlowColor", default = ColorDefault("bigDef", "bigDefGlowColor"),
              desc = "Tint of the glow ring. The alpha channel sets its "
                  .. "strength (and the pulse's peak, for Pulsing).",
              disabled = "combat", refresh = "mouseup", hidden = BigDefNoGlow,
              get = GetColor("bigDef", "bigDefGlowColor"),
              set = SetColor("bigDef", "bigDefGlowColor"),
              onChange = effect },
            Dd("bigDefGlowStyle", "Glow Style",
               { { value = "steady", text = "Steady"  },
                 { value = "pulse",  text = "Pulsing" } }, effect,
               { hidden = BigDefNoGlow,
                 desc = "Steady draws the ring at a constant strength; "
                     .. "Pulsing fades it in and out." }),
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────
--
-- Two things lead every subtab page, in this order:
--
--   1. The per-Layout SCOPE STRIP. Each aura sub-category owns its own
--      toggle, so the strip belongs to the subtab rather than to the
--      section -- exactly as the Ace page injected it inside each subtab
--      (injectSubcatScopeWidgets, orders 0.1/0.2/0.3) rather than at the
--      section root.
--
--   2. The AURA PREVIEW dropdown. The Ace SECTION root emitted this once
--      per section at order 0.2, above the tab strip, so it rendered on
--      every subtab. A BuzzardPanel route has no section-root page, so it
--      is emitted at the top of EACH subtab page instead -- which is the
--      same place, relative to the tab's own content, that order 0.2 put
--      it. Both copies are the same field over the same account-wide key
--      (db.global.previewModeBuffs), so there is one value and two views
--      of it, the way the Ace in-page and chrome copies were.
local SUBCAT_OF = { tabBuffs = "buffs", tabBigDef = "bigDef" }

function BuzzardFramesOptions:BuffsPage(subtabId, label)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end
    local subcat = SUBCAT_OF[subtabId]

    -- The route observers replace the Ace render-hook trackers; stamped
    -- here as well, because the first build happens after the navigation
    -- that armed nothing yet.
    EnsureObservers()
    EnterSubcat(nil, subcat)

    local groups = { self:AuraScopeStrip(subcat) }
    for _, g in ipairs(build()) do groups[#groups + 1] = g end

    return {
        -- The routed storage, wearing the shape of a table. Every `bind`
        -- on this page resolves through it.
        db       = function() return Root(subcat) end,
        -- Buzzard Frames' own defaults, in the same shape -- which is
        -- what makes right-click "Reset to default" work on every bound
        -- field without any of them declaring a default of its own.
        defaults = self:AuraDefaults(subcat),
        -- The Aura Preview dropdown lives in the PAGE HEADER, above the
        -- subtab strip: it belongs to the Buffs section rather than to the
        -- subtab on screen, which is where the Ace section root drew it.
        headerField = self:AuraPreviewField("aurasBuffs"),
        groups   = groups,
    }
end
