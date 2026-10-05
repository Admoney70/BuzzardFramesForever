-- ============================================================
-- BuzzardFramesOptions: Pages_UnitFramesTarget.lua
-- The Unit Frames > Target Frame section, in BuzzardPanel.
--
-- The panel equivalent of the `targetTab` branch of BuzzardFrames'
-- UnitFrames/Options_oUF_Player_Target.lua (`BF:_BuildPlayerTargetOpts`):
-- the same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by six BuzzardPanel pages -- one per
-- subtab, each a route of its own under `unitFrames/targetTab`, drawn as a
-- strip by the `tabs` navigator that node declares.
--
-- The first four subtabs (Size & Position, Name Bar, Health Bar, Power
-- Bar) come from the shared factory in Pages_UnitFramesShared.lua, this
-- panel's copy of the Ace `makeFrameOpts`. This file adds what the Ace
-- file adds to the target tab and nothing else: the Auras and Cast Bar
-- subtabs.
--
-- Storage: BF.ufDB (SavedVariable BuzzardFramesUnitFramesDB). The aura
-- keys and the cast bar's font size are per-unit
-- (BF.ufDB.profile.target.*, the Ace tufGet/tufSet and ufGet/ufSet);
-- every other cast bar key is a flat-root one (BF.ufDB.profile.*). Both
-- route through the write-through root in Pages_UnitFramesShared.lua --
-- `unit.<key>` and `prof.<key>` -- which is what keeps this panel and the
-- Ace one writing to the same places. NO per-Layout scope row: this is
-- not a raid/party section.
--
-- Ace args keys with no field of their own here, for the audit:
--   sizeTab / nameTab / healthTab / powerTab / aurasTab / castBarTab
--                                   -> the six routes
--   barHeightGroup, nameTextGroup, levelTextGroup, healthPctPosGroup,
--   healthValPosGroup, powerPctPosGroup, powerValPosGroup
--                                   -> cards (their inline group titles)
--   hdrPosition, hdrSize, hdrAlpha, hdrText, hdrNameBar, hdrNameBarText,
--   hdrPowerBar, hdrPlacement, hdrBorder, hdrIcon, hdrDebuffs, hdrBuffs
--                                   -> card titles
--   _posTracker                     -> Ace chrome plumbing; the position
--                                      sliders re-derive their own bounds
--                                      (see AnchorField in the shared file)
--   useClassColor, healthColor      -> built by the Ace factory and then
--                                      nil'd off the target tab by the Ace
--                                      file itself (health colors live in
--                                      Global > Health Bar Colors)
--   oufPowerBarDetached, detachedGroup, raidGroupTextGroup
--                                   -> player-only; their Ace entries are
--                                      hidden on every other unit, so the
--                                      shared factory does not build them
--                                      here
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function UF() return BuzzardFramesOptions.UnitFramesShared end

-- The Ace makeFrameOpts arguments for the target, as one table. Built
-- lazily -- nothing at file scope touches BuzzardFrames.
local function Spec()
    local uf = UF()
    return {
        unit      = "target",
        label     = "Target Frame",
        enableKey = "showTargetFrame",
        -- The raid-style twin flag the shared factory's Size & Position
        -- switch writes; profile ROOT, next to the enable key above.
        raidStyleKey = "targetRaidStyle",
        relayout  = uf.RelayoutTarget,
        update    = uf.UpdateTarget,
        frame     = function()
            local bf = BF()
            return bf and bf.oufTarget
        end,
    }
end

local function Prof()
    local uf = UF()
    return uf and uf.Prof()
end

-- ── Side effects ───────────────────────────────────────────────

local function RelayoutTarget()
    UF().RelayoutTarget()
end

-- The two cast bar refreshes that are NOT a target relayout: the border
-- and the spell icon are applied to the bar in place.
local function CastBarBorder()
    local bf = BF()
    if bf and bf._ApplyOUFCastbarBorder then bf:_ApplyOUFCastbarBorder() end
end

local function CastBarIcon()
    local bf = BF()
    if bf and bf._ApplyOUFCastbarIcon then bf:_ApplyOUFCastbarIcon(bf.oufTarget) end
end

local function IsRounded()
    local bf = BF()
    return bf and bf.IsOUFRounded and bf:IsOUFRounded()
end

-- ── The two target-only sub-tabs ───────────────────────────────

local PAGES = {}

function PAGES.aurasTab(spec)
    local uf       = UF()
    local root     = uf.Root(spec.unit)
    local off      = uf.FrameOff(spec.enableKey)
    local relayout = spec.relayout

    -- The Ace tufGet/tufSet pair: read profile.target[key] with a default,
    -- write it under a combat guard and relayout. Both halves live in the
    -- shared root; the gate only adds the effect.
    local function Gate(key, tooltip)
        return {
            id = key, default = uf.DefaultUnit(spec.unit, key),
            tooltip = tooltip,
            get = function() return root.unit[key] end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root.unit[key] = v
                relayout()
            end,
        }
    end

    return {
        { title = "Debuffs", preset = "form", hidden = off,
          toggle = Gate("targetShowDebuffs", "Show Debuffs"),
          fields = {
            uf.Sw("unit.targetNameplateDebuffsOnly", "Nameplate Debuffs Only",
                  relayout,
                  { wide = true,
                    desc = "When enabled, only show debuffs that would appear "
                        .. "on nameplates (same filter Blizzard uses for enemy "
                        .. "nameplates)." }),
            uf.Sl("unit.targetDebuffSize", "Icon Size", 10, 36, 1, relayout),
            uf.Sl("unit.targetDebuffsPerRow", "Per Row", 1, 32, 1, relayout),
            uf.Sl("unit.targetMaxDebuffs", "Max Icons", 1, 40, 1, relayout),
            uf.St("unit.targetDebuffSpacing", "Spacing", 0, 10, 1, relayout),
            uf.Sl("unit.targetDebuffOffsetX", "X Offset", -50, 50, 1, relayout),
            uf.Sl("unit.targetDebuffOffsetY", "Y Offset", -50, 50, 1, relayout),
        }},
        { title = "Buffs", preset = "form", hidden = off,
          toggle = Gate("targetShowBuffs", "Show Buffs"),
          fields = {
            uf.Sl("unit.targetBuffSize", "Icon Size", 10, 36, 1, relayout),
            uf.Sl("unit.targetBuffsPerRow", "Per Row", 1, 32, 1, relayout),
            uf.Sl("unit.targetMaxBuffs", "Max Icons", 1, 32, 1, relayout),
            uf.St("unit.targetBuffSpacing", "Spacing", 0, 10, 1, relayout),
            uf.Sl("unit.targetBuffOffsetX", "X Offset", -50, 50, 1, relayout),
            uf.Sl("unit.targetBuffOffsetY", "Y Offset", -50, 50, 1, relayout),
        }},
    }
end

function PAGES.castBarTab(spec)
    local uf  = UF()
    local off = uf.FrameOff(spec.enableKey)

    -- The Ace cbShown / cbDetached / cbAttached predicates, with the
    -- page's own gate folded in.
    local function cbOff()
        local p = Prof()
        return off() or (p and p.targetShowCastBar) == false
    end
    local function notDetached()
        local p = Prof()
        return cbOff() or (p and p.targetCastBarDetached) ~= true
    end
    local function notAttached()
        local p = Prof()
        return cbOff() or (p and p.targetCastBarDetached) == true
    end

    return {
        { title = "Cast Bar", preset = "form", hidden = off, fields = {
            uf.Sw("prof.targetShowCastBar", "Show Cast Bar", RelayoutTarget,
                  { wide = true }),
        }},
        { title = "Placement", preset = "form", hidden = cbOff, fields = {
            uf.Sw("prof.targetCastBarDetached", "Detach from Target Frame",
                  RelayoutTarget,
                  { wide = true,
                    desc = "When detached, the cast bar can be positioned "
                        .. "independently. Unlock frames to drag it." }),
            { control = "segmented", label = "Cast Bar Position",
              bind = "prof.targetCastBarPosition", disabled = "combat",
              desc = "Where the cast bar is anchored when attached to the "
                  .. "target frame.",
              options = {
                  { value = "above", text = "Above" },
                  { value = "below", text = "Below" },
              },
              hidden = notAttached, onChange = RelayoutTarget },
            uf.Sl("prof.targetCastBarGap", "Y Offset", -50, 50, 1,
                  RelayoutTarget, { hidden = notAttached }),
            uf.Sw("prof.targetCastBarAvoidAuras", "Avoid Auras", RelayoutTarget,
                  { wide = true, hidden = notAttached,
                    desc = "Automatically push the cast bar down (or up) to "
                        .. "clear any aura icons that are currently visible, "
                        .. "based on the live row count." }),
        }},
        { title = "Size", preset = "form", hidden = cbOff, fields = {
            uf.Sl("prof.targetCastBarHeight", "Bar Height", 4, 30, 1,
                  RelayoutTarget),
            uf.Sl("prof.targetCastBarWidth", "Bar Width", 40, 600, 1,
                  RelayoutTarget, { hidden = notDetached }),
            -- The one PER-UNIT key on this tab: the Ace field reads and
            -- writes ufGet/ufSet("target", "castBarFontSize").
            uf.Sl("unit.castBarFontSize", "Font Size", 6, 16, 1,
                  RelayoutTarget),
        }},
        -- Hidden while a rounded Border Mode is active: the cast bar gets
        -- its ring from the shared rounded art (frameBorderColor tint).
        { title = "Border", preset = "form",
          hidden = function() return cbOff() or IsRounded() end,
          toggle = {
              id = "targetCastBarBorderEnabled",
              default = uf.DefaultProf("targetCastBarBorderEnabled"),
              tooltip = "Enable Border",
              get = function()
                  local p = Prof()
                  return (p and p.targetCastBarBorderEnabled) == true
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.targetCastBarBorderEnabled = v
                  CastBarBorder()
              end,
          },
          fields = {
            uf.St("prof.targetCastBarBorderThickness", "Thickness", 1, 6, 1,
                  CastBarBorder),
            uf.Col("prof.targetCastBarBorderColor", "Color", true,
                   CastBarBorder),
        }},
        { title = "Spell Icon", preset = "form", hidden = cbOff,
          toggle = {
              id = "targetCastBarShowIcon",
              default = uf.DefaultProf("targetCastBarShowIcon"),
              tooltip = "Show Spell Icon",
              get = function()
                  local p = Prof()
                  return (p and p.targetCastBarShowIcon) ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local p = Prof()
                  if not p then return end
                  p.targetCastBarShowIcon = v
                  CastBarIcon()
              end,
          },
          fields = {
            { control = "segmented", label = "Icon Side",
              bind = "prof.targetCastBarIconSide", disabled = "combat",
              options = {
                  { value = "left",  text = "Left"  },
                  { value = "right", text = "Right" },
              },
              onChange = RelayoutTarget },
            uf.Sl("prof.targetCastBarIconSize", "Icon Size", 10, 48, 1,
                  RelayoutTarget),
            uf.Sl("prof.targetCastBarIconGap", "Gap", 0, 20, 1, RelayoutTarget,
                  { desc = "Distance in pixels between the cast bar and the "
                        .. "spell icon." }),
        }},
    }
end

-- ── The six pages ──────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The ids are the Ace args keys, and the order is
-- the Ace `order` values': size 1, name 2, health 3, power 4, auras 5,
-- cast bar 6.
BuzzardFramesOptions.UNITFRAMES_TARGET_SUBTABS = {
    { id = "sizeTab",    title = "Size & Position" },
    { id = "nameTab",    title = "Name Bar"        },
    { id = "healthTab",  title = "Health Bar"      },
    { id = "powerTab",   title = "Power Bar"       },
    { id = "aurasTab",   title = "Auras"           },
    { id = "castBarTab", title = "Cast Bar"        },
}

function BuzzardFramesOptions:UnitFramesTargetPage(subtabId)
    local uf = UF()
    if not uf then return { groups = {} } end

    local spec   = Spec()
    local groups = uf.SharedGroups(spec, subtabId)
    if not groups then
        local build = PAGES[subtabId]
        groups = build and build(spec) or {}
    end

    return uf.Page(spec, subtabId, groups)
end
