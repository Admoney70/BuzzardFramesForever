-- ============================================================
-- BuzzardFramesOptions: Pages_UnitFramesPlayer.lua
-- The Unit Frames > Player Frame section, in BuzzardPanel.
--
-- The panel equivalent of the `playerTab` branch of BuzzardFrames'
-- UnitFrames/Options_oUF_Player_Target.lua (`BF:_BuildPlayerTargetOpts`):
-- the same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by eight BuzzardPanel pages -- one per
-- subtab, each a route of its own under `unitFrames/playerTab`, drawn as a
-- strip by the `tabs` navigator that node declares.
--
-- The first four subtabs (Size & Position, Name Bar, Health Bar, Power
-- Bar) come from the shared factory in Pages_UnitFramesShared.lua, which
-- is this panel's copy of the Ace `makeFrameOpts`. This file adds what the
-- Ace file adds to the player tab and nothing else: the Raid Group Text
-- group inside the Name Bar tab, and the Alt Power Bar, Resource Bar,
-- Auras and Combat Indicator subtabs.
--
-- Storage: BF.ufDB (SavedVariable BuzzardFramesUnitFramesDB). Per-unit
-- keys route through `unit.<key>` (BF.ufDB.profile.player), flat-root keys
-- through `prof.<key>` (BF.ufDB.profile) -- the two namespaces of the
-- write-through root in Pages_UnitFramesShared.lua, which is what keeps
-- this panel and the Ace one writing to the same places. NO per-Layout
-- scope row: this is not a raid/party section, and Unit Frame Layouts are
-- a section of their own.
--
-- Ace args keys with no field of their own here, for the audit:
--   sizeTab / nameTab / healthTab / powerTab / altPowerTab / resourceTab
--   aurasTab / playerIconsTab       -> the eight routes
--   barHeightGroup, detachedGroup, nameTextGroup, levelTextGroup,
--   raidGroupTextGroup, healthPctPosGroup, healthValPosGroup,
--   powerPctPosGroup, powerValPosGroup, altPowerPctPosGroup,
--   altPowerValPosGroup             -> cards (their inline group titles)
--   hdrPosition, hdrSize, hdrAlpha, hdrText, hdrNameBar, hdrNameBarText,
--   hdrPowerBar, hdrDruidForms, hdrPlacement, hdrCombat, hdrAttach,
--   hdrColor, hdrBorder, hdrPipBorder, hdrEmpty, hdrPartial, hdrDebuffs,
--   hdrBuffs                        -> card titles
--   altPowerBarNote, druidFormsDesc -> notes (kept, as notes)
--   _posTracker                     -> Ace chrome plumbing: a description
--                                      whose NAME function re-derived the
--                                      position sliders' soft bounds as a
--                                      render side effect. The panel
--                                      re-derives them in the sliders' own
--                                      get (see AnchorField in the shared
--                                      file), so there is nothing left for
--                                      it to do
--   useClassColor, healthColor      -> built by the Ace factory and then
--                                      nil'd off the player tab by the Ace
--                                      file itself (health colors live in
--                                      Global > Health Bar Colors); never
--                                      shown on this tab, so not migrated
--
-- Ace args keys that ARE migrated but under the storage key they write,
-- because the Ace inline group they sat in is what named them:
--   druidRestoration / druidGuardian / druidBalance / druidFeral
--                       -> prof.altPowerBarDruidSpecs.restoration /
--                          .guardian / .balance / .feral
--   raidGroupTextGroup.show / numberOnly / fontSize / offsetX / offsetY /
--   color               -> the card's header gate, then
--                          unit.raidGroupNumberOnly, raidGroupFontSize,
--                          raidGroupOffsetX/Y, raidGroupColor
--   altPower*PosGroup.show / showSymbol / point / x / y
--                       -> the cards' header gates, the Show % Symbol
--                          switch, and prof.altPowerPctPos /
--                          altPowerValPos .point/.x/.y
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function UF() return BuzzardFramesOptions.UnitFramesShared end

-- The Ace `unit`/`enableKey`/`relayout`/`update` arguments to
-- makeFrameOpts, as one table. Built lazily -- nothing at file scope
-- touches BuzzardFrames.
local function Spec()
    local uf = UF()
    return {
        unit      = "player",
        label     = "Player Frame",
        enableKey = "showPlayerFrame",
        -- The raid-style twin flag the shared factory's Size & Position
        -- switch writes; profile ROOT, next to the enable key above.
        raidStyleKey = "playerRaidStyle",
        relayout  = uf.RelayoutPlayer,
        update    = uf.UpdatePlayer,
        frame     = function()
            local bf = BF()
            return bf and bf.oufPlayer
        end,
    }
end

local function Prof()
    local uf = UF()
    return uf and uf.Prof()
end

-- The Ace `playerFrameDisabled`, verbatim: the player frame's own enable
-- toggle and nothing else. The whole-page gate (which also folds in
-- ptfEnabled) is UF().FrameOff -- the two are kept apart because several
-- Ace predicates on these tabs test this one on its own.
local function PlayerFrameDisabled()
    local p = Prof()
    return not (p and p.showPlayerFrame)
end

-- ── Side effects ───────────────────────────────────────────────
--
-- One function per thing the addon has to be told, named for what it
-- tells it, each under the SAME BF:DebounceOption key its Ace counterpart
-- uses so a drag from either panel coalesces into one walk.

-- The Alt Power Bar pair. These were direct calls in an earlier version
-- of the Ace file, so a slider drag ran a full alt-bar layout on every
-- notch while the equivalent power-bar slider ran one at the end.
local function AltLayout()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutAltPower", function()
        if bf.ApplyOUFAltPowerBarLayout then bf:ApplyOUFAltPowerBarLayout() end
    end)
end

local function AltUpdate()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdateAltPower", function()
        if bf.UpdateOUFAltPowerBar then bf:UpdateOUFAltPowerBar() end
    end)
end

local function AltLayoutUpdate()
    AltLayout(); AltUpdate()
end

-- The DIRECT player relayout several Alt Power Bar setters run on top of
-- the debounced pair: the alt bar reserves space from the health bar, so
-- turning it on or resizing it re-lays the player frame out as well.
-- Undebounced, exactly as in the Ace setters.
local function PlayerLayoutNow()
    local bf = BF()
    if bf and bf.oufPlayer then bf:ApplyOUFPlayerLayout() end
end

local function AltLayoutAndPlayer()
    AltLayout(); PlayerLayoutNow()
end

local function AltLayoutUpdateAndPlayer()
    AltLayoutUpdate(); PlayerLayoutNow()
end

-- The Resource Bar pair.
local function ResourceLayout()
    local bf = BF()
    if bf and bf.ApplyOUFResourceBarLayout then bf:ApplyOUFResourceBarLayout() end
end

-- oUF 14.0.0 internalised __isEnabled/__cur/__max/__powerType into a
-- private STATE table. GetOUFClassPowerState pairs the public
-- IsElementEnabled check with the values Buzzard Frames' own ClassPower
-- PostUpdate caches on the host frame.
local function ResourceUpdate()
    local bf = BF()
    if not bf then return end
    -- Whichever frame currently HOSTS ClassPower/Runes: with the player
    -- raid-style twin on, the oUF player frame is hidden and the
    -- elements live on the insecure host instead.
    local host = (bf._ClassPowerOwner and bf:_ClassPowerOwner())
                 or bf.oufPlayer or bf._classPowerHost
    local cpOn, cpCur, cpMax, cpType = bf:GetOUFClassPowerState(host)
    if cpOn then
        bf:UpdateOUFResourceBar(cpCur, cpMax, cpType)
    elseif host and host.IsElementEnabled and host:IsElementEnabled("Runes") then
        -- Death Knights: ClassPower is never enabled, so without this
        -- branch every setting wired to this refresh (bar color,
        -- use-type-color, show-empty, empty-dim) is inert for them.
        -- ForceUpdate rather than UpdateOUFRuneBar: the latter only
        -- repaints the dim _fill backing, while the bright rune color
        -- comes from runes.UpdateColor, which only runs via oUF's
        -- ColorPath -- i.e. from ForceUpdate, a spec change, or an event.
        if host.Runes and host.Runes.ForceUpdate then host.Runes:ForceUpdate() end
    end
end

local function ResourceBorder()
    local bf = BF()
    if bf and bf._ApplyOUFResourceBarBorder then bf:_ApplyOUFResourceBarBorder() end
end

local function ResourceEnabled()
    local p = Prof()
    return (p and p.oufResourceBarEnabled) == true
end

-- When the player frame is disabled the bar is always treated as
-- detached, which is the Ace getter's own first branch.
local function ResourceDetached()
    if not ResourceEnabled() then return false end
    if PlayerFrameDisabled() then return true end
    local bf = BF()
    return bf and bf:GetUFDetachState("playerResourceBar")
end

local function IsRounded()
    local bf = BF()
    return bf and bf.IsOUFRounded and bf:IsOUFRounded()
end

-- ── The Name Bar tab's Raid Group Text card ────────────────────
--
-- Player only. The Ace group hides with the Name Bar Text master toggle,
-- and its own Show toggle hides everything below it -- which is the card's
-- header gate here.
local function RaidGroupCard(spec)
    local uf   = UF()
    local root = uf.Root(spec.unit)
    local off  = uf.FrameOff(spec.enableKey)
    local relayout = spec.relayout

    return {
        title = "Raid Group Text", preset = "form",
        hidden = function()
            return off() or root.unit.showNameBarText == false
        end,
        toggle = {
            id      = "showRaidGroup",
            default = uf.DefaultUnit(spec.unit, "showRaidGroup"),
            tooltip = "Show Raid Group",
            desc    = "Show a raid group indicator on the player frame name "
                   .. "bar. Only visible when in a raid group.",
            get     = function() return root.unit.showRaidGroup == true end,
            set     = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit.showRaidGroup = v
                relayout()
            end,
        },
        fields = {
            uf.Sw("unit.raidGroupNumberOnly", "Number Only", relayout,
                  { wide = true,
                    desc = "Show just the group number [X] instead of [Group X]." }),
            uf.Sl("unit.raidGroupFontSize", "Font Size", 6, 20, 1, relayout),
            uf.Sl("unit.raidGroupOffsetX", "X Offset", -50, 50, 1, relayout),
            uf.Sl("unit.raidGroupOffsetY", "Y Offset", -50, 50, 1, relayout),
            uf.Col("unit.raidGroupColor", "Color", false, relayout),
        },
    }
end

-- ── The three-way anchor rows ──────────────────────────────────
--
-- The Alt Power Bar's position groups offer LEFT / CENTER / RIGHT and
-- nothing else, so they are NOT the nine-cell anchor pad the other
-- position triplets use -- a pad would offer six points the alt bar's
-- layout code does not read. A segmented picker and two sliders instead,
-- with the Ace names, ranges and defaults.
local function AltPosFields(base, xLo, xHi, yLo, yHi, effect)
    local uf = UF()
    return {
        { control = "segmented", label = "Anchor",
          bind = "prof." .. base .. ".point", disabled = "combat",
          options = {
              { value = "LEFT",   text = "Left"   },
              { value = "CENTER", text = "Center" },
              { value = "RIGHT",  text = "Right"  },
          },
          onChange = effect },
        uf.Sl("prof." .. base .. ".x", "X Offset", xLo, xHi, 1, effect),
        uf.Sl("prof." .. base .. ".y", "Y Offset", yLo, yHi, 1, effect),
    }
end

-- ── The four player-only sub-tabs ──────────────────────────────

local PAGES = {}

function PAGES.altPowerTab(spec)
    local uf   = UF()
    local root = uf.Root(spec.unit)
    local off  = uf.FrameOff(spec.enableKey)

    local function altOff()
        return off() or root.prof.showAltPowerBar == false
    end
    local function notDetached()
        return altOff() or root.prof.altPowerBarDetached ~= true
    end

    return {
        -- Above the toggle rather than in its tooltip: it describes a
        -- sizing consequence the reader sees on the frame whether or not
        -- they hover the option.
        { preset = "bare", hidden = off, fields = {
            { control = "note", wide = true,
              text = "Due to combat restrictions that prevent resizing the "
                  .. "player frame when shapeshifting, the Alt Power bar "
                  .. "reserves space from the Health Bar and increases "
                  .. "Health Bar height to accommodate when not shapeshifted." },
        }},
        { title = "Alt Power Bar", preset = "form", hidden = off, fields = {
            uf.Sw("prof.showAltPowerBar", "Enable Alt Power Bar",
                  AltLayoutUpdateAndPlayer,
                  { wide = true,
                    desc = "Show a secondary power bar when in a shapeshift form." }),
        }},
        { title = "Druid Specializations", preset = "form", hidden = altOff,
          fields = {
            { control = "note", wide = true,
              text = "Enable/disable the alt power (mana) bar per Druid "
                  .. "specialization." },
            uf.Sw("prof.altPowerBarDruidSpecs.restoration", "Restoration",
                  AltLayoutUpdate),
            uf.Sw("prof.altPowerBarDruidSpecs.guardian", "Guardian",
                  AltLayoutUpdate),
            -- Balance re-lays the player frame out as well, as its Ace
            -- setter does; the other three do not.
            uf.Sw("prof.altPowerBarDruidSpecs.balance", "Balance",
                  AltLayoutUpdateAndPlayer),
            uf.Sw("prof.altPowerBarDruidSpecs.feral", "Feral",
                  AltLayoutUpdate),
        }},
        { title = "Placement", preset = "form", hidden = altOff, fields = {
            uf.Sw("prof.altPowerBarDetached", "Detach", AltLayoutAndPlayer,
                  { desc = "When detached, the bar can be positioned "
                        .. "independently. Unlock frames to drag it."
                        .. "\n\nWhen detached, the Alt Power Bar will hide "
                        .. "when not shapeshifted." }),
        }},
        { title = "Size", preset = "form", hidden = altOff, fields = {
            uf.Sl("prof.altPowerBarHeight", "Height", 1, 20, 1,
                  AltLayoutAndPlayer),
            uf.Sl("prof.oufAltPowerBarWidth", "Width", 30, 300, 1, AltLayout,
                  { hidden = notDetached }),
        }},
        -- altLayoutUpdate, not altLayout: the Power Bar tab's Font Size
        -- does relayout + update for the same reason -- the layout pass
        -- restyles the FontStrings but the value pass is what re-stamps
        -- their text.
        { title = "Text", preset = "form", hidden = altOff, fields = {
            uf.Sl("prof.altPowerFontSize", "Font Size", 6, 16, 1,
                  AltLayoutUpdate),
        }},
        { title = "Alt Power Percent", preset = "form", hidden = altOff,
          toggle = {
              id = "altPowerShowPct", default = uf.DefaultProf("altPowerShowPct"),
              tooltip = "Show Percent",
              get = function() return root.prof.altPowerShowPct ~= false end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root.prof.altPowerShowPct = v
                  AltUpdate()
              end,
          },
          fields = (function()
              local f = { uf.Sw("prof.altPowerShowPctSymbol", "Show % Symbol",
                                AltUpdate, { wide = true }) }
              for _, e in ipairs(AltPosFields("altPowerPctPos", -20, 20, -10, 10,
                                              AltLayout)) do
                  f[#f + 1] = e
              end
              return f
          end)(),
        },
        { title = "Alt Power Value", preset = "form", hidden = altOff,
          toggle = {
              id = "altPowerShowVal", default = uf.DefaultProf("altPowerShowVal"),
              tooltip = "Show Value",
              get = function() return root.prof.altPowerShowVal == true end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root.prof.altPowerShowVal = v
                  AltUpdate()
              end,
          },
          fields = AltPosFields("altPowerValPos", -20, 20, -10, 10, AltLayout),
        },
    }
end

function PAGES.resourceTab(spec)
    local uf  = UF()
    local off = uf.FrameOff(spec.enableKey)

    local function rbOff()      return off() or not ResourceEnabled() end
    local function placeOff()   return rbOff() or PlayerFrameDisabled() end
    local function gapOff()     return placeOff() or ResourceDetached() end
    local function widthOff()   return off() or not ResourceDetached() end

    return {
        { title = "Resource Bar", preset = "form", hidden = off, fields = {
            { control = "switch", label = "Enable Resource Bar", wide = true,
              desc = "Show a resource bar (Holy Power, Combo Points, Rage, "
                  .. "etc.) below the player power bar. Can be enabled "
                  .. "independently of the Player Frame.",
              id = "oufResourceBarEnabled",
              default = uf.DefaultProf("oufResourceBarEnabled"),
              disabled = "combat",
              get = function() return ResourceEnabled() end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufResourceBarEnabled = v
                  ResourceLayout()
              end },
        }},
        { title = "Placement", preset = "form", hidden = placeOff, fields = {
            { control = "switch", label = "Detach from Player Frame",
              wide = true,
              desc = "When detached, the resource bar can be positioned "
                  .. "independently. Unlock frames to drag it.",
              id = "oufResourceBarDetached",
              default = uf.DefaultProf("oufResourceBarDetached"),
              disabled = "combat",
              get = function()
                  if PlayerFrameDisabled() then return true end
                  local bf = BF()
                  return bf and bf:GetUFDetachState("playerResourceBar")
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf:SetUFDetachState("playerResourceBar", v)
                  ResourceLayout()
              end },
            uf.St("prof.oufResourceBarGap", "Gap Below Power Bar", 0, 10, 1,
                  ResourceLayout, { hidden = gapOff }),
        }},
        { title = "Size", preset = "form", hidden = rbOff, fields = {
            uf.Sl("prof.oufResourceBarHeight", "Bar Height", 4, 80, 1,
                  ResourceLayout),
            uf.Sl("prof.oufResourceBarWidth", "Bar Width", 40, 600, 1,
                  ResourceLayout, { hidden = widthOff }),
            uf.Sl("prof.oufResourceBarPipGap", "Pip Spacing", 0, 20, 1,
                  ResourceLayout),
        }},
        { title = "Color", preset = "form", hidden = rbOff, fields = {
            uf.Sw("prof.oufResourceBarUseTypeColor", "Use Resource Type Color",
                  ResourceUpdate),
            uf.Col("prof.oufResourceBarColor", "Custom Color", false,
                   ResourceUpdate,
                   { hidden = function()
                         local p = Prof()
                         return rbOff() or (p and p.oufResourceBarUseTypeColor) ~= false
                     end }),
            uf.Sw("prof.oufResourceBarShowBg", "Show Background",
                  ResourceLayout),
            uf.Col("prof.oufResourceBarBgColor", "Background Color", true,
                   ResourceLayout,
                   { hidden = function()
                         local p = Prof()
                         return rbOff() or (p and p.oufResourceBarShowBg) == false
                     end }),
        }},
        -- Border and Pip Border stay VISIBLE in rounded modes: the Enable
        -- toggles and Colors drive the rounded rings. Only the Thickness
        -- sliders are square-only -- the sliced ring band is fixed by the
        -- art (1px Rounded, 1.5px Thick).
        { title = "Border", preset = "form", hidden = rbOff,
          toggle = {
              id = "oufResourceBarBorderEnabled",
              default = uf.DefaultProf("oufResourceBarBorderEnabled"),
              tooltip = "Enable Border",
              get = function()
                  local p = Prof()
                  return (p and p.oufResourceBarBorderEnabled) == true
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufResourceBarBorderEnabled = v
                  ResourceBorder()
              end,
          },
          fields = {
            uf.St("prof.oufResourceBarBorderThickness", "Thickness", 1, 6, 1,
                  ResourceBorder, { hidden = IsRounded }),
            uf.Col("prof.oufResourceBarBorderColor", "Color", true,
                   ResourceBorder),
        }},
        { title = "Pip Border", preset = "form", hidden = rbOff,
          toggle = {
              id = "oufResourceBarPipBorderEnabled",
              default = uf.DefaultProf("oufResourceBarPipBorderEnabled"),
              tooltip = "Enable Pip Border",
              get = function()
                  local p = Prof()
                  return (p and p.oufResourceBarPipBorderEnabled) == true
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufResourceBarPipBorderEnabled = v
                  ResourceBorder()
              end,
          },
          fields = {
            uf.St("prof.oufResourceBarPipBorderThickness", "Thickness", 1, 6, 1,
                  ResourceBorder, { hidden = IsRounded }),
            uf.Col("prof.oufResourceBarPipBorderColor", "Color", true,
                   ResourceBorder),
        }},
        -- Empty Pip Brightness is stored 0-0.5 and shown on the 0-50 scale
        -- it implies: the library's slider value box shows whole numbers,
        -- so the stored fraction would read "0" at every setting. The
        -- STORED value is unchanged.
        { title = "Empty Pips", preset = "form", hidden = rbOff,
          toggle = {
              id = "oufResourceBarShowEmpty",
              default = uf.DefaultProf("oufResourceBarShowEmpty"),
              tooltip = "Show Empty Pips",
              get = function()
                  local p = Prof()
                  return (p and p.oufResourceBarShowEmpty) ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufResourceBarShowEmpty = v
                  ResourceUpdate()
              end,
          },
          fields = {
            { control = "slider", label = "Empty Pip Brightness",
              id = "oufResourceBarEmptyDim",
              min = 0, max = 50, step = 5,
              default = (uf.DefaultProf("oufResourceBarEmptyDim") or 0) * 100,
              disabled = "combat", onChange = ResourceUpdate,
              get = function()
                  local root = uf.Root("player")
                  return math.floor((root.prof.oufResourceBarEmptyDim or 0) * 100 + 0.5)
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufResourceBarEmptyDim = v / 100
              end },
        }},
        { title = "Partial Fill", preset = "form", hidden = rbOff, fields = {
            uf.Sw("prof.oufResourceBarPartialFill", "Show Partial Fill",
                  ResourceUpdate,
                  { wide = true,
                    desc = "Fills a pip in proportion to how far it has "
                        .. "charged instead of leaving it empty until it "
                        .. "completes. Applies to Evoker Essence, which fills "
                        .. "as it recharges, and to Destruction soul shard "
                        .. "fragments. Every other resource is whole points "
                        .. "only and is unaffected; Death Knight runes always "
                        .. "animate and ignore this setting." }),
        }},
    }
end

function PAGES.aurasTab(spec)
    local uf       = UF()
    local root     = uf.Root(spec.unit)
    local off      = uf.FrameOff(spec.enableKey)
    local relayout = spec.relayout

    -- The player aura keys are the per-unit ones, prefixed with the unit
    -- name so _ApplyOUFRightFrameLayout can look them up generically.
    local function Gate(key, tooltip)
        return {
            id = key, default = uf.DefaultUnit(spec.unit, key),
            tooltip = tooltip,
            get = function() return root.unit[key] == true end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit[key] = v
                relayout()
            end,
        }
    end

    return {
        { title = "Debuffs", preset = "form", hidden = off,
          toggle = Gate("playerShowDebuffs", "Show Debuffs"),
          fields = {
            uf.Sl("unit.playerDebuffSize", "Icon Size", 10, 36, 1, relayout),
            uf.Sl("unit.playerDebuffsPerRow", "Per Row", 1, 32, 1, relayout),
            uf.Sl("unit.playerMaxDebuffs", "Max Icons", 1, 40, 1, relayout),
            uf.St("unit.playerDebuffSpacing", "Spacing", 0, 10, 1, relayout),
            uf.Sl("unit.playerDebuffOffsetX", "X Offset", -50, 50, 1, relayout),
            uf.Sl("unit.playerDebuffOffsetY", "Y Offset", -50, 50, 1, relayout),
        }},
        { title = "Buffs", preset = "form", hidden = off,
          toggle = Gate("playerShowBuffs", "Show Buffs"),
          fields = {
            uf.Sl("unit.playerBuffSize", "Icon Size", 10, 36, 1, relayout),
            uf.Sl("unit.playerBuffsPerRow", "Per Row", 1, 32, 1, relayout),
            uf.Sl("unit.playerMaxBuffs", "Max Icons", 1, 32, 1, relayout),
            uf.St("unit.playerBuffSpacing", "Spacing", 0, 10, 1, relayout),
            uf.Sl("unit.playerBuffOffsetX", "X Offset", -50, 50, 1, relayout),
            uf.Sl("unit.playerBuffOffsetY", "Y Offset", -50, 50, 1, relayout),
        }},
    }
end

function PAGES.playerIconsTab(spec)
    local uf       = UF()
    local off      = uf.FrameOff(spec.enableKey)
    local relayout = spec.relayout

    return {
        { title = "Combat Indicator", preset = "form", hidden = off,
          toggle = {
              id = "oufShowCombatIndicator",
              default = uf.DefaultProf("oufShowCombatIndicator"),
              tooltip = "Show Combat Indicator",
              desc = "Show a combat icon in the center of the player health "
                  .. "bar when in combat.",
              get = function()
                  local p = Prof()
                  return (p and p.oufShowCombatIndicator) ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.oufShowCombatIndicator = v
                  relayout()
              end,
          },
          fields = {
            uf.Sl("prof.oufCombatIndicatorSize", "Size", 6, 40, 1, relayout),
        }},
    }
end

-- ── The eight pages ────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The ids are the Ace args keys, and the order is
-- the Ace `order` values': size 1, name 2, health 3, power 4, alt power 5,
-- resource 6, auras 7, combat indicator 8.
BuzzardFramesOptions.UNITFRAMES_PLAYER_SUBTABS = {
    { id = "sizeTab",        title = "Size & Position" },
    { id = "nameTab",        title = "Name Bar"        },
    { id = "healthTab",      title = "Health Bar"      },
    { id = "powerTab",       title = "Power Bar"       },
    { id = "altPowerTab",    title = "Alt Power Bar"   },
    { id = "resourceTab",    title = "Resource Bar"    },
    { id = "aurasTab",       title = "Auras"           },
    { id = "playerIconsTab", title = "Combat Indicator" },
}

function BuzzardFramesOptions:UnitFramesPlayerPage(subtabId)
    local uf = UF()
    if not uf then return { groups = {} } end

    local spec   = Spec()
    local groups = uf.SharedGroups(spec, subtabId)

    if groups then
        -- The one thing the Ace file adds to a SHARED tab on the player
        -- side: the Raid Group Text group, appended to the Name Bar tab
        -- after Level Text, which is where its order = 40 put it.
        if subtabId == "nameTab" then
            groups[#groups + 1] = RaidGroupCard(spec)
        end
    else
        local build = PAGES[subtabId]
        groups = build and build(spec) or {}
    end

    return uf.Page(spec, subtabId, groups)
end
