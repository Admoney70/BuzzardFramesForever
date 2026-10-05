-- ============================================================
-- BuzzardFramesOptions: Pages_Debuffs.lua
-- The Raid/Party Frames > Debuffs section, in BuzzardPanel.
--
-- The panel equivalent of the DEBUFFS HALF of BuzzardFrames'
-- Options/Options_Auras.lua -- `BF:BuildAurasOptions` called with
-- `deps.group == "aurasDebuffs"`, which emits exactly three subtabs
-- (GROUP_TABS.aurasDebuffs):
--
--   tabDebuffs         "Debuffs"              sub-category `debuffs`
--   debuffPresetFilter "Debuff Preset/Filter" sub-category `debuffs`,
--                                             SCOPED to auras_debuffFilter
--   tabDispel          "Dispellable Debuffs"  sub-category `dispelIndicator`
--
-- Each is a ROUTE of its own under `raidPartyFrames/aurasDebuffs`, drawn as
-- a strip by the `tabs` navigator that node declares -- the Pages_Icons
-- shape.
--
-- NOT IN THIS FILE: the custom debuff CONTAINER subtabs
-- (`debuffContainer_<i>`) and the "Add Container" pseudo-tab. Those are
-- spliced into the Ace section by BuildAurasOptions only when a
-- `deps.containerHost` is passed, they are the same builder the Buffs
-- section uses, and ANOTHER AGENT OWNS THEIR MIGRATION. This file reads the
-- container CLAIMS -- a claimed debuff type renders in a container, so its
-- row here shows the claim instead of its own Show/Size controls -- and
-- links to those routes, but does not build them.
--
-- STORAGE DID NOT MOVE. Every key still lives at
-- rpDB.profile.auras.<subcat>[key] (per-Layout OFF) or
-- flat.auras.<subcat>[key] (ON), and which of the two is decided PER KEY by
-- BuzzardFrames -- the Preset/Filter keys follow auras_debuffFilter while
-- their neighbors on the Debuffs tab follow auras_debuffs, over the SAME
-- storage table. None of that routing is re-implemented here: it lives in
-- Pages_AuraShared.lua, which hands this file the bind-through db
-- (`AuraRoot`), the defaults (`AuraDefaults`), the refresh dispatch
-- (`AuraEffect`), the per-subtab scope strip (`AuraScopeStrip`) and the
-- Aura Preview dropdown (`AuraPreviewField`).
--
-- Nearly every field is BOUND rather than given a get/set pair, because a
-- bind path is what the library's right-click "Undo change" and "Reset to
-- default" are keyed on. Where the Ace widget had a nil-aware getter
-- (`~= false` for a default-on toggle) the field keeps its `bind` AND
-- declares a `get`: reads then answer the way Ace answered, writes still go
-- through the routed bind, and undo/reset still resolve.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON. BF() is read inside the
-- functions, at the moment the panel is used.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- ── The two resolved views ─────────────────────────────────────
--
-- The panel's copy of getAurasProfile("debuffs") / ("dispelIndicator"):
-- BuzzardFrames answers, including the merged view a scoped sub-category
-- serves when its two toggles disagree. Read-only, always -- a merged view
-- is a copy, and a write to it disappears at the next invalidation.
local function DP()
    return BuzzardFramesOptions.AuraSubcatView("debuffs") or {}
end

local function IP()
    return BuzzardFramesOptions.AuraSubcatView("dispelIndicator") or {}
end

-- The routed write side. `AuraRoot` is memoised per sub-category, so these
-- are cheap and the table identity the library compares stays stable.
local function DebuffRoot() return BuzzardFramesOptions:AuraRoot("debuffs") end
local function DispelRoot() return BuzzardFramesOptions:AuraRoot("dispelIndicator") end

-- What a key resets TO, for the handful of fields that cannot bind.
-- BuzzardFrames' own defaults table is the single source: a copy here would
-- be a second answer to the same question.
local function DefaultOf(subcat, key)
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile and d.profile.auras
    d = d and d[subcat]
    return d and d[key]
end

-- ── Predicates, from the Ace builder ───────────────────────────

-- debuffsHidden / enlargeDebuffsHidden (the latter is the former since v67).
local function DebuffsOff()
    return DP().showDebuffs == false
end

-- SIMPLE MODE: ONE predicate, read by every mode-aware widget on the
-- Preset/Filter subtab, so the page can never disagree with
-- ResolveDebuffShape about which mode it is in (both test `== true`, so nil
-- is normal mode on both sides).
local function SimpleMode()
    return DP().debuffSimpleMode == true
end

-- The two composed gates. Everything on the Preset/Filter subtab is already
-- gated on "Show Debuffs off hides the lot"; these ADD the mode gate rather
-- than replacing it, so a widget never becomes visible with debuffs off.
local function NormalOnlyHidden()   -- hidden while Simple Mode is ON
    return DebuffsOff() or SimpleMode()
end

local function SimpleOnlyHidden()   -- hidden while Simple Mode is OFF
    return DebuffsOff() or not SimpleMode()
end

-- The Sort Order list drops its "Blizzard" entry unless the Base Filter IS
-- the Blizzard Filter -- that is the only filter under which
-- DebuffGroupSortFor may hand Other Debuffs the tiered UnitFrameDebuff
-- method. Unset reads as the "none" default, never "blizzard".
local function BaseFilterIsBlizzard()
    return (DP().debuffBaseFilter or "none") == "blizzard"
end

-- The shipped Sort Order default; Base Filter's setter falls back to it when
-- it has to clear a now-unavailable "blizzard".
local DEBUFF_SORT_ORDER_DEFAULT = "recentLast"

-- The Ace border-style helper, key for key: the legacy *BlizzardBorders flag
-- is OR'd in exactly as the runtime does, and Rounded is checked first so a
-- genuinely rounded pick is never masked by a leftover flag.
local function AuraBorderStyle(prof, styleKey, blizzKey)
    local v = prof[styleKey]
    if v == "rounded" or v == "rounded_thick" then return v end
    if v == "blizzard" or prof[blizzKey] then return "blizzard" end
    return v or "flat"
end

local function DebuffBorderStyle()
    return AuraBorderStyle(DP(), "debuffBorderStyle", "debuffBlizzardBorders")
end

-- Vertical-primary predicate: decides whether the two affected sliders are
-- called "Per Row"/"Row Spacing" or "Per Column"/"Column Spacing".
-- Normalized the same way the runtime normalizes it.
local function DebuffGrowIsVertical()
    local bf = BF()
    if not bf then return false end
    local sp = DP()
    return bf.GrowDirectionIsVertical(
        bf.NormalizeGrowDirection(sp.debuffGrowDirection, sp.debuffAnchorPoint))
end

-- tabDispel's predicates, verbatim. "blizzard" mode retires the whole custom
-- surface: the runtime forces those features off in the AuraCache hoist, so
-- a control for one of them could not do anything.
local function DispelBlizzardMode()
    return IP().dispelIndicatorOverlayMode == "blizzard"
end

local function DispelCustomMode()
    return IP().dispelIndicatorOverlayMode == "custom"
end

local function DispelHidden()
    if DispelBlizzardMode() then return true end
    return not IP().showDispelIndicator
end

local function OverlayHidden()
    if DispelBlizzardMode() then return true end
    return not IP().enableDebuffOverlay
end

local function BorderHidden()
    return DispelBlizzardMode()
end

local function HealthColorSubHidden()
    if DispelBlizzardMode() then return true end
    return not IP().enableDebuffHealthColor
end

-- ── Shared value shapes ────────────────────────────────────────

-- Values are "PRIMARY_SECONDARY" (fill direction, then wrap direction).
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
    .. "a colored frame; Thick is the same frame ~1px heavier."

-- The three dispel-visual scopes, shared by the border, overlay and health
-- tint mode pickers.
local HIGHLIGHT_MODE_OPTIONS = {
    { value = "dispellable",    text = "Dispellable by Me" },
    { value = "allDispellable", text = "All Dispellable"   },
    { value = "all",            text = "All Debuffs"       },
}

-- Four widgets read this same sentence in the Ace source. Four copies of a
-- sentence drift, so it is written once.
local ONLY_IF_READY_DESC =
    "When enabled, the %s only shows when your dispel spell is off cooldown. "
    .. "The GCD is not counted as a cooldown."

-- ── Side effects ───────────────────────────────────────────────

local function SweepDebuffHighlight()
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do bf:UpdateDebuffHighlight(f) end
end

-- The dispel indicator's own layout pass, under the SAME BF mouse-up key the
-- Ace setters use, so the two panels coalesce into one another's drags
-- rather than each running their own.
local function DispelIndicatorLayout()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("aurasDispelIndLayout", function()
        local ind = bf:GetIndicatorByName("dispelDebuffIndicator")
        if ind then ind:LayoutAllFrames() end
    end)
end

-- ══ THE DEBUFF PRIORITY LIST ═══════════════════════════════════
--
-- Seven rows carrying UNIQUE ranks 1..7. The list is the single precedence
-- authority: main-row group order, main-row dedup negations AND
-- custom-container preset ranking all read it.
--
-- A ticked Combine box collapses its pair into ONE row at the pair's better
-- (lower) rank, displaying the FIRST member's Show + Relative Size storage.
-- Unticking restores each member's own stored values and rank.
--
-- `showKey` / `sizeKey` / `maxKey` / `rankKey` ARE the storage keys, and must
-- match Defaults_RaidPartyFrames.lua.
--
-- `pairFollow` marks a pair the RUNTIME follows as one unit (the two entries
-- of DEBUFF_COMBINE_PAIRS): while its Combine box is ticked such a pair is
-- CLAIM-COHERENT, which is what lets a CLAIMED pair keep the combined row
-- shape here. Priority/Other has no runtime pair and therefore no coherence.
--
-- The SAME row definitions serve Simple Mode, deliberately: the mode only
-- changes what a row is CALLED, what it explains and which of its widgets
-- are shown.
local DEBUFF_LIST_ROWS = {
    { id = "boss", label = "Boss Auras", pairLabel = "Boss/Role Debuffs",
      claim = "boss", rankKey = "debuffRankBoss", defRank = 1,
      showKey = "debuffTypeBoss", sizeKey = "debuffSizeBoss",
      maxKey = "debuffMaxBoss",
      combineKey = "debuffCombineBossRole", combineDefault = true,
      pairWith = "role", owns = true, expand = { "boss", "role" },
      pairFollow = true,
      simpleLabel = "Boss/Role Debuffs",
      simpleDesc = "Debuffs the game flags as boss or role debuffs.",
      desc = "Debuffs the game flags as boss auras." },
    { id = "role", label = "Role Auras",
      claim = "role", rankKey = "debuffRankRole", defRank = 2,
      showKey = "debuffTypeRole", sizeKey = "debuffSizeRole",
      maxKey = "debuffMaxRole",
      combineKey = "debuffCombineBossRole", combineDefault = true,
      pairWith = "boss", pairFollow = true,
      desc = "Debuffs the game flags for your role (tank / healer / DPS)." },
    { id = "cc", label = "Crowd Control Debuffs",
      claim = "cc", rankKey = "debuffRankCC", defRank = 3,
      showKey = "debuffTypeCC", sizeKey = "debuffSizeCC",
      maxKey = "debuffMaxCC",
      desc = "Stuns, fears, silences, roots and slows (the CROWD_CONTROL filter)." },
    { id = "dispMe", label = "Dispellable by Me",
      pairLabel = "Dispellable Debuffs",
      claim = "dispelMe", rankKey = "debuffRankDispMe", defRank = 4,
      showKey = "debuffTypeDispMe", sizeKey = "debuffSizeDispMe",
      maxKey = "debuffMaxDispMe",
      -- Boss/Role and Priority/Other Combines default ON, the dispel pair
      -- defaults SPLIT.
      combineKey = "debuffCombineDispel", combineDefault = false,
      pairWith = "dispOthers", owns = true, expand = { "dispMe", "dispOthers" },
      pairFollow = true,
      simpleLabel = "Dispellable by Me",
      simpleDesc = "Debuffs you can dispel. In Simple Mode this uses the game's "
          .. "own check, so the talent and long-cooldown options do not apply.",
      desc = "Debuffs YOU can dispel, resolved from your spec and talents." },
    { id = "dispOthers", label = "Dispellable by Others",
      claim = "dispelOthers", rankKey = "debuffRankDispOthers", defRank = 5,
      showKey = "debuffTypeDispOthers", sizeKey = "debuffSizeDispOthers",
      maxKey = "debuffMaxDispOthers",
      combineKey = "debuffCombineDispel", combineDefault = false,
      pairWith = "dispMe", pairFollow = true,
      desc = "Dispellable debuffs your character cannot remove." },
    { id = "priority", label = "Priority Auras",
      claim = "priority", rankKey = "debuffRankPriority", defRank = 6,
      showKey = "debuffTypePriority", sizeKey = "debuffSizePriority",
      maxKey = "debuffMaxPriority",
      combineKey = "debuffCombinePriorityOther", combineDefault = true,
      pairWith = "other",
      desc = "Debuffs on Blizzard's priority-aura list." },
    { id = "other", label = "Other Debuffs",
      pairLabel = "Priority/Other Debuffs",
      rankKey = "debuffRankOther", defRank = 7,
      showKey = "debuffShowOther", maxKey = "debuffMaxOther",
      combineKey = "debuffCombinePriorityOther", combineDefault = true,
      pairWith = "priority", owns = true, expand = { "priority", "other" },
      simpleLabel = "Other Debuffs",
      simpleDesc = "Every other debuff the default raid frames would show.",
      desc = "Every remaining debuff (the Base Filter row)." },
}

local DEBUFF_ROW_BY_ID = {}
for i = 1, #DEBUFF_LIST_ROWS do
    DEBUFF_ROW_BY_ID[DEBUFF_LIST_ROWS[i].id] = DEBUFF_LIST_ROWS[i]
end

-- Row id -> the claiming container's preset key. A claimed row still shows
-- Relative Size, backed by the SAME storage the container settings page
-- edits.
local DEBUFF_ROW_PRESET_KEY = {
    boss = "boss", role = "role", cc = "crowdControl",
    dispMe = "meDispellable", dispOthers = "othersDispellable",
    priority = "priority",
}

-- A debuff TYPE claimed by a custom debuff container renders THERE, so its
-- main-row group parks and its Show/Size controls here go: a control that
-- cannot do anything is worse than no control. Claim beats the toggle.
local function TypeClaimed(claimId)
    if not claimId then return false end
    local bf = BF()
    local claims = bf and bf.GetDebuffTypeClaims and bf:GetDebuffTypeClaims()
    if not claims then return false end
    return claims[claimId] == true
end

-- The claiming container's (name, index) for a claimed row, or nil when the
-- row is not claimed. `index` is the GetCustomDebuffContainers array
-- position -- the <i> of that container's `debuffContainer_<i>` route.
local function ClaimContainer(row)
    if not TypeClaimed(row.claim) then return nil end
    local bf = BF()
    local info = bf and bf.GetDebuffTypeClaimInfo and bf:GetDebuffTypeClaimInfo()
    local e = info and info[row.claim]
    if not e then return "a custom container", nil end
    return e.names, e.index
end

-- Is `row`'s Combine box ticked? (nil reads as the shipped default.)
local function RowCombineOn(row)
    if not row.combineKey then return false end
    -- SIMPLE MODE: Boss/Role is ALWAYS one row there and the other two pairs
    -- never combine -- the normal-mode boxes are hidden and ignored. Mirror
    -- of CombineFlagOn, which forces the same answer at runtime so a
    -- container claim of either member claims the pair.
    if SimpleMode() then return row.combineKey == "debuffCombineBossRole" end
    local v = DP()[row.combineKey]
    if v == nil then return row.combineDefault end
    return v == true
end

-- ...and does it actually apply?
--
-- For a `pairFollow` pair the answer is simply "yes": the pair is ONE unit
-- owned by the FIRST member's container, so either BOTH members are claimed
-- or NEITHER is, and there is no mixed state left for a split shape to
-- represent. Splitting it anyway showed two rows for one run of icons and
-- let the two members be ranked apart while every runtime consumer collapses
-- the pair to min(member ranks).
--
-- PRIORITY/OTHER KEEPS THE SPLIT: it has no runtime pair, so nothing makes
-- Priority's claim and Other's follow each other.
local function RowCombined(row)
    if not RowCombineOn(row) then return false end
    if row.pairFollow then return true end
    local o = DEBUFF_ROW_BY_ID[row.pairWith]
    if TypeClaimed(row.claim) then return false end
    if o and TypeClaimed(o.claim) then return false end
    return true
end

-- ── SIMPLE MODE: which rows the list shows ─────────────────────
--
-- A row with no live group behind it is a control that does nothing, so the
-- list follows the mode's group rule. BF:ResolveSimpleDebuffRows IS that
-- rule and the engine reads the same function; what stays local to this page
-- is the two things the runtime has no opinion about -- the pair collapse
-- (`role` never renders its own row) and CLAIMED-but-not-live rows.
--
-- The CLAIM test comes FIRST, so a claimed row survives even while the
-- combine box is ticked: a claimed category stays orderable (its rank drives
-- container-preset precedence) and its Max Debuffs slider is the ONLY place
-- that type's cap can be edited at all.
--
-- The claims table is reused rather than reallocated -- this runs once per
-- row per render and the resolver does not retain it.
local _simpleRowClaims = {}

local function SimpleRowShown(row)
    -- Boss/Role is ONE row here: `role` follows `boss` and never renders on
    -- its own.
    if row.id == "role" then return false end
    local bf = BF()
    if not (bf and bf.ResolveSimpleDebuffRows) then return false end
    _simpleRowClaims.boss     = TypeClaimed("boss")
    _simpleRowClaims.role     = TypeClaimed("role")
    _simpleRowClaims.dispelMe = TypeClaimed("dispelMe")
    -- The PROFILE table, not the aura cache: this page edits the profile,
    -- and the resolver reads only keys whose nil defaults resolve the same
    -- either way.
    local _, byId = bf:ResolveSimpleDebuffRows(DP(), _simpleRowClaims)
    if row.id == "boss" then
        if byId.boss.claimed then return true end
        return byId.boss.live
    end
    if TypeClaimed(row.claim) then return true end
    if row.id == "other" or row.id == "dispMe" then return true end
    return false
end

-- The row that actually renders: the second member of a combined pair is
-- absorbed into the first (`owns`).
local function RowVisible(row)
    if SimpleMode() then return SimpleRowShown(row) end
    if RowCombined(row) and not row.owns then return false end
    return true
end

local function RowLabel(row)
    if SimpleMode() then
        -- Boss/Role is always the pair in this mode, claimed or not.
        if row.simpleLabel then return row.simpleLabel end
        return row.label
    end
    if RowCombined(row) and row.pairLabel then return row.pairLabel end
    return row.label
end

-- ── The two modes do not share ranks ───────────────────────────
--
-- BF:DebuffRankKeyOf / BF:DebuffRankOf decide which of the two key sets a
-- read or a write means, off the profile's own debuffSimpleMode -- so a
-- reorder in one mode cannot move the other's list.
local function RankKeyOf(row)
    local bf = BF()
    return (bf and bf:DebuffRankKeyOf(DP(), row.id)) or row.rankKey
end

local function RowRank(row)
    local bf = BF()
    local p = DP()
    local r = (bf and bf:DebuffRankOf(p, row.id)) or row.defRank
    -- In Simple Mode RowCombined is true for exactly the Boss/Role pair, so
    -- the pair collapses to its better rank there too.
    if RowCombined(row) then
        local o = DEBUFF_ROW_BY_ID[row.pairWith]
        local r2 = (o and bf and bf:DebuffRankOf(p, o.id)) or r
        if r2 < r then r = r2 end
    end
    return r
end

-- ── OTHER DEBUFFS IS LAST -- IN NORMAL MODE ────────────────────
--
-- In normal mode the list is a PRECEDENCE list over overlapping groups and
-- the residual row would swallow everything below it. NOT true in Simple
-- Mode: there the groups are engine-classified and disjoint, so the list is
-- pure display order and Other is free to sit anywhere. The two modes store
-- their ranks separately, which is what makes holding both rules at once
-- possible.
local function RowIsResidual(row)
    return row.id == "other" and not SimpleMode()
end

-- Every VISIBLE row, sorted by effective rank.
local function VisibleRows()
    local out = {}
    for i = 1, #DEBUFF_LIST_ROWS do
        local row = DEBUFF_LIST_ROWS[i]
        if RowVisible(row) then out[#out + 1] = row end
    end
    table.sort(out, function(a, b)
        -- The residual sorts last before rank is even consulted.
        local ea, eb = RowIsResidual(a), RowIsResidual(b)
        if ea ~= eb then return eb end
        local ra, rb = RowRank(a), RowRank(b)
        if ra ~= rb then return ra < rb end
        return a.defRank < b.defRank
    end)
    return out
end

-- ── The reorder ────────────────────────────────────────────────
--
-- Rewrite ALL SEVEN ranks as 1..7 from a new visible order. Rebuilding the
-- whole assignment rather than swapping two stored numbers is what makes the
-- UNIQUE-RANK INVARIANT unbreakable: combined rows expand into their two
-- members in DISPLAY order (Boss,Role / DispMe,DispOthers / Priority,Other --
-- Priority first because that is where it sits once the box is unticked and
-- it gets its own group back), so unticking a Combine box leaves both
-- members exactly where the combined row sat.
local function RewriteNormalRanks(list)
    local root = DebuffRoot()
    local rank = 0
    for k = 1, #list do
        local r = list[k]
        local ids = (RowCombined(r) and r.expand) or nil
        if ids then
            for n = 1, #ids do
                rank = rank + 1
                root[RankKeyOf(DEBUFF_ROW_BY_ID[ids[n]])] = rank
            end
        else
            rank = rank + 1
            root[RankKeyOf(r)] = rank
        end
    end
end

-- ── SIMPLE MODE REWRITE ────────────────────────────────────────
--
-- Same invariant -- ranks stay UNIQUE 1..7 over all SEVEN types -- reached
-- differently, because the simple list shows a SUBSET of them: the visible
-- rows take their new order, then the types this mode does not show are
-- spliced in NEXT TO THEIR NATURAL PARTNER (Role after Boss, Dispellable by
-- Others after Dispellable by Me, Priority before Other). Each pair is one
-- unit in the user's head, and it is where the row would have been had it
-- been visible all along. A hidden type with no visible partner keeps its
-- relative order and goes after the visible rows.
--
-- Their stored ranks are READ before the first write: the profile view is
-- live, so sorting after the visible rows had been renumbered would sort on
-- values this very function had just overwritten.
local SIMPLE_PARTNER = {
    role       = { anchor = "boss",       after = true  },
    boss       = { anchor = "role",       after = false },
    dispOthers = { anchor = "dispMe",     after = true  },
    dispMe     = { anchor = "dispOthers", after = false },
    priority   = { anchor = "other",      after = false },
}

local function RewriteSimpleRanks(list)
    local bf = BF()
    if not bf then return end
    local placed = {}
    for k = 1, #list do placed[list[k].id] = true end

    local p = DP()
    local rest = {}
    for k = 1, #DEBUFF_LIST_ROWS do
        local r = DEBUFF_LIST_ROWS[k]
        if not placed[r.id] then
            rest[#rest + 1] = { row = r, rank = bf:DebuffRankOf(p, r.id) }
        end
    end
    table.sort(rest, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.row.defRank < b.row.defRank
    end)

    local seqRows = {}
    for k = 1, #list do seqRows[#seqRows + 1] = list[k] end
    local function indexOf(id)
        for k = 1, #seqRows do
            if seqRows[k].id == id then return k end
        end
        return nil
    end
    local leftovers = {}
    for k = 1, #rest do
        local r  = rest[k].row
        local pr = SIMPLE_PARTNER[r.id]
        local at = pr and indexOf(pr.anchor)
        if at then
            table.insert(seqRows, pr.after and (at + 1) or at, r)
        else
            leftovers[#leftovers + 1] = r
        end
    end
    for k = 1, #leftovers do seqRows[#seqRows + 1] = leftovers[k] end

    -- Simple Mode writes its OWN rank keys, so this reorder leaves the
    -- normal-mode list exactly where it was.
    local root = DebuffRoot()
    for k = 1, #seqRows do root[RankKeyOf(seqRows[k])] = k end
end

-- Move `row` to position `toIndex` of the visible list and rewrite.
--
-- The residual row does not move, and nothing moves past it: both rules are
-- normal-mode-only and both are enforced here, exactly as debuffMoveTarget
-- enforced them for the Ace arrows.
local function MoveRowTo(row, toIndex)
    if InCombatLockdown() then return end
    if RowIsResidual(row) then return end

    local list = VisibleRows()
    local from
    for i = 1, #list do
        if list[i] == row then from = i end
    end
    if not (from and toIndex) then return end

    for i = 1, #list do
        if RowIsResidual(list[i]) and toIndex >= i then toIndex = i - 1 end
    end
    if toIndex < 1 then toIndex = 1 end
    if toIndex > #list then toIndex = #list end
    if toIndex == from then return end

    table.remove(list, from)
    table.insert(list, toIndex, row)

    if SimpleMode() then
        RewriteSimpleRanks(list)
    else
        RewriteNormalRanks(list)
    end
    BuzzardFramesOptions.RunAuraRefresh("debuffs")
end

-- ── Field shorthands ───────────────────────────────────────────

local function Opts(f, opts)
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A default-ON toggle: nil must read as checked, so the field keeps its
-- `bind` for the write and declares a nil-aware `get` for the read.
local function OnUnlessFalse(prof, key)
    return function() return prof()[key] ~= false end
end

-- A default-OFF toggle whose Ace getter tested `== true`.
local function OffUnlessTrue(prof, key)
    return function() return prof()[key] == true end
end

-- A percentage STORED as a multiplier (0.1 .. 2.0) or a fraction (0 .. 1).
--
-- The panel's slider draws whole numbers -- there is no isPercent -- so the
-- control works in percent and the adapters do the arithmetic, the shape
-- Pages_CastBar uses. It is `id` rather than `bind` on purpose: Reset
-- resolves a BIND path against the page's defaults table, which holds the
-- multiplier, and would hand 1.4 to a 10..200 slider. With an `id` the
-- field's own `default` answers instead, already in percent.
--
-- `onChange` is handed a SYNTHETIC node carrying the storage key -- the same
-- `{ key }` trick the Ace file uses for its own out-of-band writes -- so the
-- shared aura effect can still see which key changed and clear the icon
-- index cache for a *Size key.
local function PctField(subcat, root, prof, key, label, lo, hi, st, effect, opts)
    local d = DefaultOf(subcat, key)
    local f = {
        control = "slider", label = label, id = key,
        -- Percent by construction -- the getter multiplies the stored
        -- fraction by 100 -- so the unit belongs on every one of these.
        suffix = "%",
        min = lo, max = hi, step = st,
        default = d and math.floor(d * 100 + 0.5) or nil,
        refresh = "mouseup", disabled = "combat",
        onChange = function() effect({ bind = key }) end,
        get = function()
            local v = prof()[key]
            if v == nil then return nil end
            return math.floor(v * 100 + 0.5)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            root()[key] = v / 100
        end,
    }
    return Opts(f, opts)
end

-- ══════════════════════════════════════════════════════════════
-- SUBTAB 1: Debuffs
-- ══════════════════════════════════════════════════════════════

local function DebuffsGroups(effect)
    local root = DebuffRoot

    -- The two sliders whose LABEL depends on the grow direction. AceConfig
    -- took a function there; a BuzzardPanel label is a string (it is
    -- measured and search-marked), so it is resolved at BUILD time and the
    -- two setters that can change it ask for a rebuild.
    local vertical  = DebuffGrowIsVertical()
    local perRowLbl = vertical and "Debuffs Per Column" or "Debuffs Per Row"
    local rowGapLbl = vertical and "Column Spacing"     or "Row Spacing"

    -- The Ace position triplet -- Anchor Point, X Offset, Y Offset -- as one
    -- anchor pad over the same three flat keys.
    --
    -- The point carries its own `set`, which is why this could not be a
    -- composite until the library grew the table form of a `binds` entry:
    -- writing an anchor point also writes that anchor's DEFAULT grow
    -- direction (BF.GROW_DEFAULT_FOR_ANCHOR), and the pad used to have one
    -- write path for all three binds with nowhere to hang that.
    local anchorField = {
        control = "anchor", label = "Anchor Point",
        desc = "Changing the anchor point resets the Grow Direction to that "
            .. "anchor's default.",
        binds = {
            point = {
                bind = "debuffAnchorPoint",
                set = function(_, ctx, v)
                    if InCombatLockdown() then return end
                    local bf = BF()
                    root().debuffAnchorPoint = v
                    local def = bf and bf.GROW_DEFAULT_FOR_ANCHOR
                                and bf.GROW_DEFAULT_FOR_ANCHOR[v]
                    if def then root().debuffGrowDirection = def end
                    -- The grow direction moved with it, so the two labels
                    -- below may have to change: a rebuild, not a repaint.
                    ctx.app:Invalidate()
                end,
            },
            x = "debuffOffsetX",
            y = "debuffOffsetY",
        },
        min = -60, max = 60, refresh = "mouseup",
        hidden = DebuffsOff, disabled = "combat", onChange = effect,
    }

    local borderStyleField, borderWeightField =
        BuzzardFramesOptions:BorderStyleFields({
            bind = "debuffBorderStyle", options = BORDER_STYLE_OPTIONS,
            desc = BORDER_STYLE_DESC,
            hidden = DebuffsOff, onChange = effect,
            get = DebuffBorderStyle,
            -- Legacy-toggle sync first, then the style key's own write: the
            -- 12.0 engine reads the flag, and a stale `true` would report
            -- Blizzard borders over flat-rendering frames.
            set = function(_, _, v)
                if InCombatLockdown() then return end
                root().debuffBlizzardBorders = (v == "blizzard")
                root().debuffBorderStyle = v
            end,
        })

    local function NotFlatBorder()
        if DebuffsOff() then return true end
        return DebuffBorderStyle() ~= "flat"
    end

    local borderColorDefault = DefaultOf("debuffs", "debuffBorderColor")
    if type(borderColorDefault) == "table" then
        borderColorDefault = { borderColorDefault.r, borderColorDefault.g,
                                borderColorDefault.b, borderColorDefault.a }
    else
        borderColorDefault = nil
    end

    return {
        -- _debuffsHeader. Never hidden, so the tab still reads as "Debuffs"
        -- when Show Debuffs is off and the rest of the page is gone. The
        -- master toggle moves into the card's HEADER: everything under it
        -- only means anything while it is on, and a card that collapses says
        -- that more plainly than a field that vanishes.
        { title = "Debuffs", preset = "form",
          toggle = {
              id = "showDebuffs", default = DefaultOf("debuffs", "showDebuffs"),
              tooltip = "Show Debuffs",
              get = function() return DP().showDebuffs end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root().showDebuffs = v
                  BuzzardFramesOptions.RunAuraRefresh("debuffs")
              end,
          },
          fields = {
            { control = "slider", label = "Debuff Size", bind = "debuffSize",
              min = 2, max = 50, step = 1, refresh = "mouseup",
              hidden = DebuffsOff, disabled = "combat", onChange = effect },
            -- A stepper, not a slider: eight whole numbers, where the
            -- reader wants "one more icon" rather than a position on a
            -- track, and no `refresh = "mouseup"` -- a stepper has no drag
            -- to coalesce, so the write IS the gesture.
            { control = "stepper", label = perRowLbl, bind = "debuffsPerRow",
              min = 1, max = 8, step = 1,
              hidden = DebuffsOff, disabled = "combat", onChange = effect },
        }},

        -- debuffPositionGroup.
        { title = "Position", preset = "form", fields = {
            anchorField,
            { control = "dropdown", label = "Grow Direction",
              bind = "debuffGrowDirection",
              desc = "Fill direction, then the direction new rows/columns wrap.",
              options = GROW_OPTIONS,
              hidden = DebuffsOff, disabled = "combat", onChange = effect,
              -- Legacy single-axis stored values are normalized on read
              -- (anchor-aware, appearance-preserving) so the dropdown always
              -- shows a valid selection.
              get = function()
                  local bf = BF()
                  if not bf then return nil end
                  local sp = DP()
                  return bf.NormalizeGrowDirection(sp.debuffGrowDirection,
                                                   sp.debuffAnchorPoint)
              end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  root().debuffGrowDirection = v
                  -- Per Row / Per Column and Row / Column Spacing are named
                  -- for this value.
                  ctx.app:Invalidate()
              end },
        }},

        -- debuffSpacingGroup.
        { title = "Debuff Spacing", preset = "form", fields = {
            { control = "stepper", label = "Icon Spacing", bind = "debuffSpacing",
              desc = "Gap in pixels between icons within a row.",
              min = 0, max = 10, step = 1,
              hidden = DebuffsOff, disabled = "combat", onChange = effect },
            { control = "stepper", label = rowGapLbl, bind = "debuffRowSpacing",
              desc = "Gap in pixels between rows/columns.",
              min = 0, max = 10, step = 1,
              hidden = DebuffsOff, disabled = "combat", onChange = effect },
        }},

        -- debuffBorderGroup.
        { title = "Border", preset = "form", fields = {
            borderStyleField,
            borderWeightField,
            -- Steppers, not sliders: six whole numbers each, and the
            -- reader wants "one more pixel" rather than a position on a
            -- track. No `refresh = "mouseup"` either -- a stepper has no
            -- drag to coalesce, so the write IS the gesture.
            { control = "stepper", label = "Border Thickness",
              bind = "debuffBorderThickness",
              desc = "Border thickness in pixels. 0 removes the border.",
              min = 0, max = 5, step = 1,
              hidden = NotFlatBorder, disabled = "combat", onChange = effect },
            { control = "stepper", label = "Dispel Border Thickness",
              bind = "debuffDispelBorderThickness",
              desc = "Thickness in pixels of the opaque dispel-colored border "
                  .. "shown for debuffs with a dispel type. Independent of "
                  .. "the base Border Thickness; values larger than it grow "
                  .. "inward over the icon. 0 removes the dispel border.",
              min = 0, max = 5, step = 1,
              hidden = NotFlatBorder, disabled = "combat", onChange = effect },
            { control = "color", label = "Border Color", alpha = true,
              id = "debuffBorderColor", default = borderColorDefault,
              refresh = "mouseup",
              desc = "Base border color for debuff icons without a dispel "
                  .. "type. Debuffs with a dispel type (Magic, Curse, "
                  .. "Disease, Poison, Bleed) draw a fully opaque border in "
                  .. "their dispel color on top of it.",
              disabled = "combat", onChange = effect,
              hidden = function()
                  if DebuffsOff() then return true end
                  return DebuffBorderStyle() == "blizzard"
              end,
              -- Storage is a KEYED table; the control reads an array. `id`
              -- rather than `bind` for the same reason PctField uses one --
              -- Reset would otherwise hand the keyed default to the array
              -- setter.
              get = function()
                  local c = DP().debuffBorderColor
                  if type(c) ~= "table" then return nil end
                  return { c.r, c.g, c.b, c.a }
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  root().debuffBorderColor =
                      { r = v[1], g = v[2], b = v[3], a = v[4] }
              end },
            -- A line of its own to start: everything above is the border
            -- itself, everything from here down is the dispel treatment on
            -- top of it.
            { control = "switch", label = "Color Border by Dispel Type",
              bind = "debuffColorBorderByDispel", wide = true, newRow = true,
              desc = "Color a dispellable debuff's border by its dispel type "
                  .. "(Magic blue, Curse purple, Poison green, Disease "
                  .. "brown), overriding the Border Color. Debuffs with no "
                  .. "dispel type keep the Border Color. Applies to the "
                  .. "flat/Square and Rounded styles (Blizzard style always "
                  .. "uses the game's own dispel border).",
              hidden = DebuffsOff, disabled = "combat", onChange = effect,
              -- Default on: nil reads as true.
              get = OnUnlessFalse(DP, "debuffColorBorderByDispel") },
            -- The five dispel types themselves, inline in the label, at the
            -- size they are drawn on a debuff. A reader who has never turned
            -- this on has no idea what "dispel type icon" looks like, and the
            -- art says it in less space than a sentence would.
            --
            -- The live icon does not name an atlas -- AddDispelTypeTexture
            -- with style Icon lets the ENGINE pick one per dispel type
            -- (ContainerFactory) -- so these are the assets that engine draws,
            -- and the set is ALL_DISPEL_TYPES (DebuffIcons): Bleed included.
            --
            -- No width of its own: ns.TextWidth measures the escapes as the
            -- pictures they are, so the field sizes itself to the label the
            -- way every other field does.
            { control = "switch",
              label = "Show Dispel Type Icon ("
                  .. "|A:RaidFrame-Icon-DebuffMagic:12:12|a"
                  .. "|A:RaidFrame-Icon-DebuffCurse:12:12|a"
                  .. "|A:RaidFrame-Icon-DebuffDisease:12:12|a"
                  .. "|A:RaidFrame-Icon-DebuffPoison:12:12|a"
                  .. "|A:RaidFrame-Icon-DebuffBleed:12:12|a)",
              bind = "showDebuffDispelTypeIcon",
              desc = "Show the debuff's dispel-type icon (Magic, Curse, "
                  .. "Poison, Disease) in the top-right corner. Only appears "
                  .. "on debuffs that have a dispel type.",
              hidden = DebuffsOff, disabled = "combat", onChange = effect },
            { control = "slider", label = "Dispel Type Icon Size",
              bind = "debuffDispelTypeIconScale",
              desc = "Size of the dispel-type corner icon, as a percentage of "
                  .. "the debuff icon.",
              -- The range reads as a percentage, which is what the number
              -- IS. The value box stays bare so it can still be typed into.
              suffix = "%",
              min = 10, max = 100, step = 5, refresh = "mouseup",
              disabled = "combat", onChange = effect,
              hidden = function()
                  if DebuffsOff() then return true end
                  return not DP().showDebuffDispelTypeIcon
              end },
        }},
    }
end

-- ══════════════════════════════════════════════════════════════
-- SUBTAB 2: Debuff Preset/Filter
-- ══════════════════════════════════════════════════════════════

-- The acDB toggles at the foot of the subtab bypass the aura routing on
-- purpose: they live in acDB.profile, are ONE value for the whole profile and
-- cannot be set per Layout. Routing them through the aura write would
-- silently relocate the value away from the key every runtime reader already
-- uses. The group is named for the SCOPE, not the behavior, because the
-- scope is the non-obvious part.
local GLOBAL_SCOPE_NOTE =
    "\n\nApplies to every Layout in this profile, not just the one you are "
    .. "editing."

local LONG_TERM_DEBUFFS = {
    { key = "showSatedDebuffs", label = "Sated / Exhaustion",
      desc = "Show Sated, Exhaustion, and similar "
          .. "bloodlust debuffs on raid/party frames when out of combat." },
    { key = "showDeserterDebuffs", label = "Deserter",
      desc = "Show BG Deserter and Dungeon Deserter debuffs on raid/party "
          .. "frames when out of combat." },
}

-- One MENU ROW per long-term debuff, in the shape the panel's own menu
-- takes -- the same rows the Addon Options button opens. `selected` is a
-- function so a flipped row repaints itself in place without the page
-- rebuilding, and `onPick` writes exactly where the switches wrote.
local function GlobalAuraItem(entry)
    return {
        kind = "toggle",
        text = entry.label,
        desc = entry.desc .. GLOBAL_SCOPE_NOTE,
        selected = function()
            local bf = BF()
            return bf and bf.acDB and bf.acDB.profile[entry.key]
        end,
        onPick = function()
            if InCombatLockdown() then return end
            local bf = BF()
            if not (bf and bf.acDB) then return end
            bf.acDB.profile[entry.key] = not bf.acDB.profile[entry.key]
            bf:RefreshAllCustomContainersWithRebuild()
        end,
    }
end

-- One row of the priority list, as a CARD.
--
-- Ordering IS the card's position and the cards are emitted in rank order, so
-- a reorder is a page rebuild -- see the reorder spec on the page.
local function RowCard(row, effect)
    local root = DebuffRoot
    local function claimed() return TypeClaimed(row.claim) end

    -- Claimed: the claim replaces the Show and Relative Size controls.
    -- ...and Simple Mode has NO Show toggles at all -- the simple groups are
    -- always on, and the hidden types have no group to switch.
    local function ctrlHidden()
        if SimpleMode() then return true end
        return claimed()
    end

    -- ...and the size slider additionally hides when the row is off. In
    -- Simple Mode the row's normal-mode Show storage is NOT read -- there is
    -- no toggle writing it, so a stale `false` left over from normal mode
    -- must not hide the slider of a group that is live.
    local function sizeHidden()
        if claimed() then return true end
        if SimpleMode() then
            -- Max Debuffs 0 is the Dispellable by Me row's off switch in this
            -- mode; a size for a parked group is noise.
            if row.id == "dispMe" then return DP()[row.maxKey] == 0 end
            return false
        end
        return DP()[row.showKey] == false
    end

    local function maxDefault()
        local bf = BF()
        return (bf and bf.DEBUFF_TYPE_MAX_DEFAULT) or 3
    end

    local fields = {}

    -- The claim, as ONE control: a button reading "Container: <name>" that
    -- opens that container's own route.
    --
    -- It was a note saying the name and a button saying "Open Container
    -- Settings" -- two rows to carry one fact and one action, and the note
    -- read as a heading for the button rather than as its subject. The name
    -- is the label because the name is what the reader is looking for; what
    -- clicking does is a tooltip's job. Still read live -- a button's `text`
    -- may be a function -- so a container rename shows without a rebuild.
    local function ClaimText()
        local nm = ClaimContainer(row)
        return nm and ("Container: " .. nm) or nil
    end

    fields[#fields + 1] = {
        control = "button",
        text = function() return ClaimText() or "" end,
        desc = "Open this container's settings.",
        -- The row's subject, not one more control in it: centered on the
        -- whole row rather than on the band under the other two captions,
        -- where a control with no caption of its own reads as dropped to
        -- the bottom.
        rowAlign = "center",
        hidden = function() return ClaimContainer(row) == nil end,
        disabled = function()
            local _, gi = ClaimContainer(row)
            return gi == nil
        end,
        onClick = function(_, ctx)
            local bf = BF()
            local _, gi = ClaimContainer(row)
            if not gi then return end
            -- The Ace button ran SelectGroup on "debuffContainer_<i>", and
            -- the panel's route is the same idea keyed by the container's
            -- own containerKey rather than by the array index, which
            -- renumbers on a delete. Pages_AuraContainers publishes the id
            -- rule so this file addresses the route rather than guessing at
            -- it; the fallback keeps the button working if that file is
            -- absent.
            local cc = bf and bf:GetCustomDebuffContainers()[gi]
            local key = (type(cc) == "table" and type(cc.containerKey) == "string")
                        and cc.containerKey or ("i" .. tostring(gi))
            local O  = _G.BuzzardFramesOptions
            local id = (O and O.ContainerRouteId)
                       and O.ContainerRouteId("debuff", key)
                       or ("debuffContainer_" .. key)
            -- Under a Custom Frame Groups scope the same container route
            -- lives under that section; sending the reader to the raid
            -- copy would move them to a different set of frames.
            local root = bf.BFOScopeFlat and "customFrames" or "raidPartyFrames"
            ctx.app:Navigate(root, "aurasDebuffs", id)
        end,
    }

    -- A claimed row keeps a Relative Size slider, editing the SAME
    -- c.presetRelativeSize[<preset>] value the container settings page edits
    -- (raw percent 10..200; 100 stores nil).
    local presetKey = DEBUFF_ROW_PRESET_KEY[row.id]
    if presetKey then
        fields[#fields + 1] = {
            control = "slider", label = "Relative Size",
            id = "debuffClaimSize" .. row.id, default = 100,
            desc = "Size of this category's icons relative to the container's "
                .. "icon size. At 100% it matches the container. When two "
                .. "categories overlap in one container, the larger one wins "
                .. "the shared aura and flows first.",
            suffix = "%",
            min = 10, max = 200, step = 5,
            refresh = "mouseup", disabled = "combat",
            hidden = function()
                local _, gi = ClaimContainer(row)
                return gi == nil
            end,
            -- WHERE THIS VALUE LIVES: the DEBUFFS sub-category, not the
            -- container.
            --
            -- It is edited on this page, so it obeys THIS page's per-Layout
            -- toggle -- the debuffs sub-category's own -- and the routed
            -- view/root handle that: with the toggle on, the read and the
            -- write are the Layout being modified; with it off, they are the
            -- shared table. It used to be stored on the claiming container,
            -- which meant one size shared by every Layout no matter what
            -- this page's toggle said.
            --
            -- The container's own value is still READ as a fallback, so a
            -- profile that set a size before this moved keeps it until the
            -- slider is next touched.
            get = function()
                local rs = DP().presetRelativeSize
                local v  = rs and rs[presetKey]
                if v == nil then
                    local bf = BF()
                    local _, gi = ClaimContainer(row)
                    local cc = gi and bf and bf:GetCustomDebuffContainers()[gi]
                    v = cc and cc.presetRelativeSize
                        and cc.presetRelativeSize[presetKey]
                end
                return v or 100
            end,
            set = function(_, _, val)
                if InCombatLockdown() then return end
                local bf = BF()
                local _, gi = ClaimContainer(row)
                local cc = gi and bf and bf:GetCustomDebuffContainers()[gi]
                if not cc then return end
                -- A COMBINED row writes BOTH members' ratios: a container's
                -- two presets stay two engine groups with independent ratios,
                -- so writing only the rendered member would leave the pair
                -- drawing at two sizes while presenting as one row. Only
                -- members the claiming container actually holds are written.
                local writeKeys = { presetKey }
                if RowCombined(row) and row.expand then
                    writeKeys = {}
                    for i = 1, #row.expand do
                        local pk = DEBUFF_ROW_PRESET_KEY[row.expand[i]]
                        if pk and cc.presets and cc.presets[pk] then
                            writeKeys[#writeKeys + 1] = pk
                        end
                    end
                    if #writeKeys == 0 then writeKeys = { presetKey } end
                end
                -- Through the sub-category's routed write, which is what
                -- makes this page's per-Layout toggle mean something: on, it
                -- lands on the Layout being modified; off, on the shared
                -- table. See the note on `get` above.
                --
                -- The container's own copy is CLEARED for the same keys, so
                -- the legacy fallback in `get` cannot outvote a value the
                -- reader has just set here.
                -- The WHOLE table, not a field of it: AuraRoot only hands
                -- back a per-field wrapper for a key the view already has, so
                -- the first write for a Layout would be an index into nil.
                -- Copied from the resolved view -- which may be the shared
                -- table or a merged per-Layout one -- and written back
                -- through the routed setter, exactly as AuraSubTable does.
                local out = {}
                local cur = DP().presetRelativeSize
                if type(cur) == "table" then
                    for k, v in pairs(cur) do out[k] = v end
                end
                for i = 1, #writeKeys do
                    local pk = writeKeys[i]
                    out[pk] = (val ~= 100) and val or nil
                    if cc.presetRelativeSize then
                        cc.presetRelativeSize[pk] = nil
                    end
                end
                DebuffRoot().presetRelativeSize = out
                if cc.presetRelativeSize and next(cc.presetRelativeSize) == nil then
                    cc.presetRelativeSize = nil
                end
                if bf.InvalidateContainerSettingsCache then
                    bf.InvalidateContainerSettingsCache()
                end
                if bf.InvalidateContainerIconCaches then
                    bf.InvalidateContainerIconCaches()
                end
                bf:RefreshContainersWithRebuildDebounced()
                bf:MouseUpOption("acPanelPreviewNotify", function()
                    if bf.RefreshPreviewDummyAuras then
                        bf:RefreshPreviewDummyAuras()
                    end
                end)
            end,
        }
    end

    -- Show + Relative Size ride the row. A COMBINED row reads the FIRST
    -- member's keys, which are this (owning) row's own -- so nothing special
    -- is needed, and unticking restores the second member's stored values
    -- untouched.
    --
    -- Unticking a TYPE row no longer HIDES those debuffs -- they fall back
    -- into the Other Debuffs flow (subject to its Base Filter). The suffix
    -- says so; the "other" row has nowhere to fall back TO, so it keeps the
    -- bare category description.
    local showDesc = row.desc
    if row.id ~= "other" then
        showDesc = showDesc
            .. " Unticked, these debuffs show with Other Debuffs instead."
    end
    fields[#fields + 1] = {
        control = "switch", label = "Show", bind = row.showKey,
        desc = showDesc, hidden = ctrlHidden, disabled = "combat",
        onChange = effect,
        -- Default ON: nil reads as true.
        get = OnUnlessFalse(DP, row.showKey),
    }

    if row.sizeKey then
        fields[#fields + 1] = PctField("debuffs", root, DP, row.sizeKey,
            "Relative Size", 10, 200, 5, effect,
            { desc = "Icon size for this section, relative to the Debuff Size.",
              hidden = sizeHidden })
    end

    -- Simple Mode's ONE box rides the Other Debuffs row, directly before its
    -- Max Debuffs slider. Default OFF: boss/role debuffs are
    -- Debuff-classified and flow INSIDE this group, sorted to the front by
    -- the tiered sort -- what the default raid frames do. Ticked, bigBoss
    -- becomes its own row with its own rank, Relative Size and Max.
    if row.id == "other" then
        fields[#fields + 1] = {
            control = "switch", label = "Separate Boss Debuffs",
            bind = "debuffSimpleSeparateBoss", wide = true,
            desc = "Show Boss/Role debuffs as their own group with a separate "
                .. "Max setting and a Relative Size option.",
            disabled = "combat",
            hidden = function()
                if SimpleOnlyHidden() then return true end
                -- The container renders those debuffs whatever this box says,
                -- so it would be a control that does nothing.
                return TypeClaimed("boss") or TypeClaimed("role")
            end,
            get = OffUnlessTrue(DP, "debuffSimpleSeparateBoss"),
            set = function(_, ctx, v)
                if InCombatLockdown() then return end
                root().debuffSimpleSeparateBoss = v
                BuzzardFramesOptions.RunAuraRefresh("debuffs")
                -- The Boss/Role row appears or goes with this box, and a row
                -- is a CARD: that is a structural change.
                ctx.app:Invalidate()
            end,
        }
    end

    -- MAX DEBUFFS, per type. Rides the row exactly like Show and Relative
    -- Size, so a combined row reads the FIRST member's key.
    --
    -- NOT hidden while the row is CLAIMED, unlike Show and Relative Size: the
    -- claim moves the type into a container and the type takes its cap with
    -- it. This slider is the only place that cap can be edited -- debuff
    -- containers have no Max Icons of their own -- so hiding it would strand
    -- the setting.
    if row.maxKey then
        fields[#fields + 1] = {
            control = "stepper", label = "Max Debuffs", bind = row.maxKey,
            desc = "Most icons this section may show at once, in the Debuffs "
                .. "display or in a container that claims it.",
            min = 1, max = 8, step = 1,
            disabled = "combat", onChange = effect,
            hidden = function()
                -- The CLAIM test comes FIRST. A claimed row's cap belongs to
                -- the container and is edited here whatever the mode -- the
                -- 0-based simple slider hides while claimed, so testing
                -- Simple Mode first stranded the setting with no slider.
                if claimed() then return false end
                -- The Dispellable by Me row shows its OWN 0-based slider in
                -- Simple Mode (below); this one steps aside there.
                if row.id == "dispMe" and SimpleMode() then return true end
                -- No Show toggle in Simple Mode, so nothing gates this on one
                -- (see sizeHidden).
                if SimpleMode() then return false end
                return DP()[row.showKey] == false
            end,
            get = function()
                local v = DP()[row.maxKey]
                if v == nil then v = maxDefault() end
                return v
            end,
        }
    end

    -- Simple Mode's OWN Max Debuffs slider for the Dispellable by Me row -- a
    -- SEPARATE widget rather than a mode-dependent `min`. Range 0..8: the row
    -- has no Show toggle in this mode, so 0 IS its off switch (the runtime
    -- parks the group and the engine never sees the 0). Same storage key as
    -- the normal slider. Shown only in Simple Mode and only while unclaimed.
    if row.id == "dispMe" then
        fields[#fields + 1] = {
            control = "stepper", label = "Max Debuffs", bind = row.maxKey,
            desc = "Most icons this section may show at once. 0 turns the "
                .. "group off.",
            min = 0, max = 8, step = 1,
            disabled = "combat", onChange = effect,
            hidden = function()
                if not SimpleMode() then return true end
                return claimed()
            end,
            get = function()
                local v = DP()[row.maxKey]
                if v == nil then v = maxDefault() end
                return v
            end,
        }
    end

    -- The two governors of BF:MyDispelTypes ride the Dispellable by Me row:
    -- they move the By Me / By Others boundary, so both dispel sections,
    -- every dispel subtraction and the meDispellable container preset
    -- re-resolve when either flips. They ALSO show while the row is claimed
    -- (the resolver serves the container's preset just the same).
    --
    -- BOTH are HIDDEN in Simple Mode: there, "dispellable by me" is the
    -- engine's own check and BF's spec/talent resolver is not consulted, so
    -- these would be controls with no effect. Their stored values are
    -- untouched and apply again the moment the mode is off.
    if row.id == "dispMe" then
        local function dispToggleHidden()
            if SimpleMode() then return true end
            if claimed() then return false end
            return DP()[row.showKey] == false
        end
        -- Both governors are stored in the DEBUFFS sub-category, so the
        -- standard dispatch is RefreshDebuffsOnly -- which walks the
        -- debuffIcons indicator and nothing else. The dispel VISUALS (border
        -- / dot / overlay / health tint) resolve their slot candidates from
        -- the SAME BF:MyDispelTypes and so have to be re-pushed too; without
        -- this they kept the old type set until some unrelated
        -- Dispellable-Debuffs setting happened to fire RefreshDispelOnly. Not
        -- debounced: these are toggles, one write per click.
        local function governorEffect(node)
            effect(node)
            local bf = BF()
            if bf and bf.RefreshDispelOnly then bf:RefreshDispelOnly() end
        end
        fields[#fields + 1] = {
            control = "switch", label = "Only when talented",
            bind = "debuffDispMeTalented", wide = true,
            desc = "Factor in Dispel talents. e.g. Exclude Poison & Curse for "
                .. "Druid when Improved Nature's Cure is not talented.",
            hidden = dispToggleHidden, disabled = "combat",
            onChange = governorEffect,
            get = OnUnlessFalse(DP, "debuffDispMeTalented"),
        }
        fields[#fields + 1] = {
            control = "switch", label = "Include Long-Cooldown Dispels",
            bind = "debuffDispMeLongCd", wide = true,
            desc = "Factor in long-cd dispel abilities. e.g. Include poisons "
                .. "for Shaman when Poison Cleansing Totem is talented.",
            hidden = dispToggleHidden, disabled = "combat",
            onChange = governorEffect,
            get = OffUnlessTrue(DP, "debuffDispMeLongCd"),
        }
    end

    return {
        title = RowLabel(row),
        preset = "form",
        -- The row's SIMPLE-MODE explanation. In the Ace page this could only
        -- be surfaced on the arrows, because AceConfigDialog renders an
        -- inline group's name as a plain title bar with no tooltip. A
        -- BuzzardPanel card header HAS one, so the text goes where it
        -- belongs -- on the row itself.
        desc = function()
            if not SimpleMode() then return nil end
            if claimed() then return nil end
            return row.simpleDesc
        end,
        -- The residual row is pinned last and cannot move at all; the
        -- library's `pinned` rule also stops anything being dragged past a
        -- card that declares this, which is exactly debuffMoveTarget's second
        -- rule.
        reorderable = not RowIsResidual(row),
        -- Collapsible, and remembered: this tab is a stack of eight or more
        -- category cards, and a reader working on one of them should not
        -- have to scroll past the rest of it every time. `id` is what the
        -- collapsed state is keyed by, so it survives a reorder and a
        -- rename -- the row's own id, which is what a row IS.
        collapsible = true,
        id = "debuffRow_" .. row.id,
        -- Collapsed, the card still says which container claimed it -- that
        -- is the one fact a reader scanning the shut list needs, and the
        -- only way to it otherwise is to open the card. Same words and the
        -- same navigation as the button inside; nil when nothing claims the
        -- row, and the header then carries only its title.
        headerButton = {
            text = ClaimText,
            desc = "Open this container's settings.",
            onClick = function(_, ctx)
                local bf = BF()
                local _, gi = ClaimContainer(row)
                if not (bf and gi) then return end
                local cc = bf:GetCustomDebuffContainers()[gi]
                local key = (type(cc) == "table" and type(cc.containerKey) == "string")
                            and cc.containerKey or ("i" .. tostring(gi))
                local O  = _G.BuzzardFramesOptions
                local id = (O and O.ContainerRouteId)
                           and O.ContainerRouteId("debuff", key)
                           or ("debuffContainer_" .. key)
                -- Section-aware for the same reason as the row above.
                local root = bf.BFOScopeFlat and "customFrames" or "raidPartyFrames"
                ctx.app:Navigate(root, "aurasDebuffs", id)
            end,
        },
        debuffRow = row,
        fields = fields,
    }
end

local function PresetFilterGroups(effect)
    local root = DebuffRoot
    local groups = {}

    -- debuffSortingHeader and the five widgets under it.
    groups[#groups + 1] = { title = "Sorting & Filtering", preset = "form",
      fields = {
        { control = "switch", label = "Simple Mode", bind = "debuffSimpleMode",
          desc = "Show debuffs the way the default raid frames do: one Other "
              .. "Debuffs group in Blizzard's priority order, with "
              .. "Dispellable by Me (and optionally Boss/Role) as separate "
              .. "groups. Base Filter and Sort Order do not apply in this "
              .. "mode.",
          hidden = DebuffsOff, disabled = "combat",
          -- Default OFF: nil reads as false.
          get = OffUnlessTrue(DP, "debuffSimpleMode"),
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              root().debuffSimpleMode = v
              BuzzardFramesOptions.RunAuraRefresh("debuffs")
              -- The mode decides WHICH rows exist, what they are called and
              -- which rank set they order by, and a row is a CARD: this is
              -- structural, not a value change.
              ctx.app:Invalidate()
          end },
        { control = "switch", label = "Exclude Applied by Friendly",
          bind = "debuffSimpleExcludeFriendly", wide = true,
          desc = "Hide debuffs applied by players and the environment.",
          hidden = SimpleOnlyHidden, disabled = "combat", onChange = effect,
          get = OffUnlessTrue(DP, "debuffSimpleExcludeFriendly") },
        { control = "dropdown", label = "Base Filter", bind = "debuffBaseFilter",
          -- Half again as wide as a normal control: these two carry the
          -- longest option texts on the page ("Blizzard (Boss > Priority >
          -- Dispellable > Other)"), and at the default width the name of
          -- the current setting is the part that gets cut.
          widthMul = 1.5,
          desc = "Which debuffs the \"Other Debuffs\" row shows before the "
              .. "debuff types below are separated out of it.\n\nShow All "
              .. "(Exclude Applied by Friendly) hides debuffs applied by "
              .. "players and the environment.\n\nBlizzard Filter shows only "
              .. "debuffs the game flags to show on raid frames, the same "
              .. "rule the default raid frames use.",
          options = {
              { value = "none",     text = "Show All Debuffs" },
              { value = "noplayer", text = "Show All (Exclude Applied by Friendly)" },
              { value = "blizzard", text = "Blizzard Filter" },
          },
          hidden = NormalOnlyHidden, disabled = "combat", onChange = effect,
          -- The "Blizzard" Sort Order is meaningful ONLY under the Blizzard
          -- Filter -- it is the UnitFrameDebuff tiered order, and
          -- DebuffGroupSortFor may only hand that to Other Debuffs when every
          -- member carries a debuffType, which only that filter guarantees.
          -- Switching AWAY from it while it is the stored value resets Sort
          -- Order to the shipped default -- otherwise the dropdown would
          -- render blank on a value its own list no longer contains.
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              root().debuffBaseFilter = v
              if v ~= "blizzard" and DP().debuffSortOrder == "blizzard" then
                  root().debuffSortOrder = DEBUFF_SORT_ORDER_DEFAULT
              end
              ctx.app:RefreshPage()
          end },
        { control = "dropdown", label = "Sort Order", bind = "debuffSortOrder",
          widthMul = 1.5,
          desc = "Order of debuffs WITHIN each group. The debuff types keep "
              .. "their own place in the row - that is what the priority list "
              .. "below controls.\n\nExpiring Last puts permanent debuffs "
              .. "first.\n\nBlizzard orders Boss/Role, then Priority, then "
              .. "Dispellable, then everything else, with your own debuffs "
              .. "first in each tier. The tiers apply to Other Debuffs under "
              .. "the Blizzard Filter; elsewhere debuffs sort yours-first "
              .. "then by application order.",
          hidden = NormalOnlyHidden, disabled = "combat", onChange = effect,
          -- "Blizzard" is offered ONLY under the Blizzard Base Filter.
          -- Everywhere else DebuffGroupSortFor falls back to Default, so
          -- listing it advertised a setting that did nothing. Base Filter's
          -- own setter resets a stored "blizzard" when it leaves that filter,
          -- so this list can never omit the current value.
          options = function()
              local out = {}
              if BaseFilterIsBlizzard() then
                  -- Plain ">" separators: the game's fonts have no glyph for
                  -- U+2192 and it rendered as boxes.
                  out[#out + 1] = { value = "blizzard",
                      text = "Blizzard (Boss > Priority > Dispellable > Other)" }
              end
              out[#out + 1] = { value = "recentLast",
                  text = "Application Order (Most Recent Last)" }
              out[#out + 1] = { value = "recentFirst",
                  text = "Application Order (Most Recent First)" }
              out[#out + 1] = { value = "expireSoon", text = "Expiring Soonest" }
              out[#out + 1] = { value = "expireLast", text = "Expiring Last" }
              return out
          end },
        { control = "dropdown", label = "Maximum Duration",
          bind = "debuffMaxDuration",
          desc = "This can be used to filter out debuffs with no duration or "
              .. "very long max duration. Please note that this does not "
              .. "refer to the max remaining duration; if a debuff is "
              .. "filtered out by this setting, it will never show even when "
              .. "its remaining duration falls into range.",
          options = {
              { value = "none",  text = "None"       },
              { value = "sec30", text = "30 seconds" },
              { value = "min1",  text = "1 minute"   },
              { value = "min2",  text = "2 minutes"  },
              { value = "min5",  text = "5 minutes"  },
              { value = "min10", text = "10 minutes" },
              { value = "min30", text = "30 minutes" },
              { value = "hour1", text = "1 hour"     },
          },
          hidden = DebuffsOff, disabled = "combat", onChange = effect,
          -- Unset reads as "none" so the dropdown shows None, not blank.
          get = function() return DP().debuffMaxDuration or "none" end },

        -- The long-term debuffs, as a menu of toggles rather than a card of
        -- five switches -- the same menu the Addon Options button opens.
        -- Here rather than in a section of its own: it is a filter, and this
        -- is where the filters are.
        { control = "multiselect", label = "Show Non-Combat Debuffs",
          text = "Choose debuffs...", disabled = "combat",
          desc = "Long-term debuffs are always hidden in combat. These "
              .. "control whether they show out of combat.",
          -- No `title` in the menu: the field's own label names the list,
          -- and a heading inside it would be the second time.
          menuStyle = { minWidth = 230 },
          items = function()
              local out = {}
              for i = 1, #LONG_TERM_DEBUFFS do
                  out[i] = GlobalAuraItem(LONG_TERM_DEBUFFS[i])
              end
              return out
          end },
    }}

    -- debuffCombineHeader and the three Combine boxes, as one menu of
    -- toggles. A ticked box collapses its pair into one row at the pair's
    -- better rank; the row then uses the FIRST member's Show / Relative Size
    -- storage. Priority+Other is FORCE-INCLUDE: the priority group stays
    -- live at base size flowing with the residual row rather than merging
    -- into it, so priority auras never vanish under a narrow Base Filter.
    --
    -- Hidden in Simple Mode, where the resolver ignores all three flags; the
    -- ONE box that mode has rides the Other Debuffs row.
    --
    -- The rows drop the word "Combine": the control says it once, and three
    -- entries each repeating their own control's name is the noise a menu
    -- exists to remove.
    local function CombineItem(key, text, desc, getter)
        return {
            kind = "toggle",
            text = text,
            desc = desc,
            selected = getter,
            onPick = function()
                if InCombatLockdown() then return end
                root()[key] = not getter()
                BuzzardFramesOptions.RunAuraRefresh("debuffs")
            end,
        }
    end

    -- debuffPriorityHeader and the two mutually exclusive notes.
    groups[#groups + 1] = { title = "Debuff Category Priority", preset = "form",
      fields = {
        { control = "note", wide = true, hidden = NormalOnlyHidden,
          text = "Some debuffs fall into multiple categories (e.g. a Boss "
              .. "Debuff that is also Dispellable). These multi-category "
              .. "debuffs will be sorted into the highest-placed category per "
              .. "the order below.\nCategories that have \"Show\" toggled off "
              .. "below will flow in with the \"Other\" Debuffs, sorted only "
              .. "by the Sort Order setting." },
        { control = "note", wide = true, hidden = SimpleOnlyHidden,
          text = "Other Debuffs are shown in the game's own priority order "
              .. "(Boss/Role, then Priority, then the rest). Debuffs you can "
              .. "dispel (per Blizzard's categorization) are a separate "
              .. "group. Order the groups below." },
        -- The Ace list was ordered with a pair of arrow buttons per row.
        -- This one is dragged, and the gesture has to be said out loud once.
        { control = "note", wide = true,
          text = "Drag a category card by its header to move it up or down "
              .. "the list." },

        { control = "multiselect", label = "Combine Similar Debuff Types",
          text = "Combine...", disabled = "combat",
          newRow = true, hidden = NormalOnlyHidden,
          desc = "Show a pair of categories as one section instead of two.",
          menuStyle = { minWidth = 300 },
          -- A combine collapses two cards into one, or splits one into two:
          -- structural, so the page is rebuilt. On the NEXT frame, because
          -- the menu is still up and the rebuild releases the rows the
          -- reader is clicking.
          onChange = function(_, ctx)
              if C_Timer then
                  C_Timer.After(0, function() ctx.app:Invalidate() end)
              else
                  ctx.app:Invalidate()
              end
          end,
          items = function()
              return {
                  CombineItem("debuffCombineBossRole", "Boss + Role Debuffs",
                      "Show Boss and Role debuffs as ONE section, using the "
                      .. "Boss row's Show and Relative Size.",
                      OnUnlessFalse(DP, "debuffCombineBossRole")),
                  CombineItem("debuffCombinePriorityOther",
                      "Priority + Other Debuffs",
                      "Flow Priority auras directly with the remaining "
                      .. "debuffs as one run of icons, at the base debuff "
                      .. "size.",
                      OnUnlessFalse(DP, "debuffCombinePriorityOther")),
                  -- nil reads OFF: the dispel pair ships SPLIT, unlike the
                  -- other two.
                  CombineItem("debuffCombineDispel",
                      "Dispellable by Me + Dispellable by Others",
                      "Show every dispellable debuff as ONE section, using "
                      .. "the Dispellable by Me row's Show and Relative "
                      .. "Size.",
                      OffUnlessTrue(DP, "debuffCombineDispel")),
              }
          end },
    }}

    -- The rows, in rank order. `rowAt` maps a page-group index back to its
    -- row, which is what the reorder's onMove is handed.
    local rowAt = {}
    local list = VisibleRows()
    for i = 1, #list do
        groups[#groups + 1] = RowCard(list[i], effect)
        rowAt[#groups] = list[i]
    end

    -- debuffGlobalGroup. NOT gated on Show Debuffs: this group lives on the
    -- Preset/Filter subtab while the master toggle lives on the Debuffs
    -- subtab, so hiding it here would make a control vanish from a page that
    -- does not show the reason. The values survive the master toggle either
    -- way, and these are out-of-combat display options.
    return groups, rowAt
end

-- ══════════════════════════════════════════════════════════════
-- SUBTAB 3: Dispellable Debuffs
-- ══════════════════════════════════════════════════════════════

local function DispelGroups(effect)
    local root = DispelRoot

    -- A field whose Ace setter did extra work after the routed write. The
    -- write goes through the bind's root -- combat-guarded there, exactly as
    -- setAuras is -- then `extra` runs, carrying whatever guard the Ace
    -- setter put around it and no other. The sub-category's own refresh is
    -- scheduled by `onChange`, which is what the Ace debounced dispatch
    -- amounted to.
    local function Setter(key, extra)
        return function(_, _, v)
            root()[key] = v
            if extra then extra() end
        end
    end

    -- A card's MASTER SWITCH, in its header rather than as its first field.
    --
    -- Every one of these cards was "Enable X" followed by the settings that
    -- only mean anything while X is on -- the exact shape the library's
    -- `toggle` exists for. In the header the switch reads as the card's own
    -- state, the card folds to its heading when it is off, and the settings
    -- stop being a list of controls grayed out under a switch.
    --
    -- The write is the one the switch did: root()[key] = v, then whatever
    -- the old setter did after it, then `effect` -- which the field got from
    -- its own `onChange` and a gate has to ask for itself.
    local function Gate(key, tooltip, desc, extra)
        return {
            id = key, default = DefaultOf("dispelIndicator", key),
            tooltip = tooltip, desc = desc,
            -- The combat gate the bound switch had. A `bind` write is
            -- guarded at the root; a gate does its own writing, so it says
            -- so itself -- and the library grays the switch for it.
            disabled = "combat",
            -- Unwritten reads as the DEFAULT, not as off: a bound switch
            -- resolved that through the page's `defaults`, and a gate does
            -- its own reading -- so a card whose setting nobody has touched
            -- would otherwise open shut with its contents hidden.
            get = function()
                local v = IP()[key]
                if v == nil then v = DefaultOf("dispelIndicator", key) end
                return v and true or false
            end,
            set = function(_, _, v)
                -- Guarded HERE as well as in the library: `disabled` stops
                -- the click, this stops the write, and the two are not the
                -- same thing -- a gate flipped by anything other than that
                -- click must not land mid-combat either.
                if InCombatLockdown() then return end
                root()[key] = v
                if extra then extra() end
                effect({ bind = key })
            end,
        }
    end

    local function BorderOff()
        return not IP().enableDebuffBorder
    end

    local function OverlayOff()
        return not IP().enableDebuffOverlay
    end

    local function IconsOff()
        return IP().blizzardDispelShowIcons == false
    end

    local function NotBlizzMode()
        return not DispelBlizzardMode()
    end

    local function BlizzIconsHidden()
        if NotBlizzMode() then return true end
        return IconsOff()
    end

    local function BlizzOverlayHidden()
        if NotBlizzMode() then return true end
        if IconsOff() then return true end
        return IP().blizzardDispelShowOverlay == false
    end

    return {
        -- blizzardHeader / blizzardNote and customHeader / customNote: two
        -- headings at the same order, mutually exclusive by mode. One card
        -- carries the mode picker and whichever note applies.
        { title = "Dispel Indicator Mode", preset = "form", fields = {
            { control = "note", wide = true, hidden = NotBlizzMode,
              text = "Shows the same Dispellable Debuff Indicator and overlay "
                  .. "as the default Blizzard raidframes." },
            { control = "note", wide = true,
              hidden = function() return not DispelCustomMode() end,
              text = "Custom mode allows many more customization "
                  .. "possibilities." },
            { control = "segmented", label = "Dispel Indicator/Overlay Mode",
              -- NOT `wide`: a segmented control is sized by its two options,
              -- and stretching "Blizzard native | Custom" across the whole
              -- card made a two-word choice look like a settings bar.
              bind = "dispelIndicatorOverlayMode",
              desc = "Choose between Blizzard's native dispel indicator icons "
                  .. "and colored dispel overlay (rendered by Blizzard's "
                  .. "private aura container system), or the addon's fully "
                  .. "customizable custom indicator and overlay.",
              options = {
                  { value = "blizzard", text = "Blizzard native" },
                  { value = "custom",   text = "Custom"          },
              },
              onChange = effect,
              -- Every card below appears or goes with this pick. The routed
              -- write already dispatches RefreshDispelOnly, which runs the
              -- private-aura overlay refresh and the three per-frame dispel
              -- Updates -- the Ace setter's explicit calls were redundant and
              -- are not repeated here either.
              set = function(_, ctx, v)
                  root().dispelIndicatorOverlayMode = v
                  ctx.app:RefreshPage()
              end },
        }},

        -- blizzardDispelOverlayMode + blizzardDispelIconsGroup.
        { title = "Dispellable Debuff Indicator", preset = "form", fields = {
            { control = "segmented", label = "Show Dispel Types",
              bind = "blizzardDispelOverlayMode",
              -- 1 = Dispellable By Me, 2 = All Dispellable -> the
              -- dispel-indicator-option attribute, which drives BOTH the
              -- indicator icons and the overlay.
              options = {
                  { value = 2, text = "All Dispellable"   },
                  { value = 1, text = "Dispellable By Me" },
              },
              hidden = NotBlizzMode, onChange = effect },
            { control = "switch", label = "Show Dispellable Debuff Icons",
              bind = "blizzardDispelShowIcons", wide = true,
              desc = "Show the dispel-type indicator icons "
                  .. "(Magic/Curse/Disease/Poison/Bleed).",
              hidden = NotBlizzMode, onChange = effect,
              set = function(_, ctx, v)
                  root().blizzardDispelShowIcons = v
                  -- Blizzard's overlay is driven FROM the icon tracking loop,
                  -- so icons-off necessarily disables the overlay too and the
                  -- Overlay card below changes shape.
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Icon + Overlay Position",
              bind = "blizzardDispelOrgType", wide = true,
              -- The aura-organization-type attribute: Blizzard's three fixed
              -- layout presets; icon corner + overlay gradient orientation
              -- come bundled.
              desc = "Position of the dispel indicator icons. The overlay's "
                  .. "gradient direction is tied to this by Blizzard's layout "
                  .. "presets.",
              options = {
                  { value = "topRight",   text = "Top Right (Overlay Top->Bottom)" },
                  { value = "bottomLeft", text = "Bottom Left (Overlay Bottom->Top)" },
                  { value = "topLeft",    text = "Top Left (Overlay Left->Right)" },
              },
              hidden = BlizzIconsHidden, onChange = effect },
            { control = "stepper", label = "Max Indicator Icons",
              bind = "dispelIndicatorMaxIcons",
              desc = "Maximum number of dispel-type indicator icons to show.",
              min = 1, max = 3, step = 1,
              hidden = BlizzIconsHidden, onChange = effect },
        }},

        -- blizzardDispelOverlayGroup.
        { title = "Overlay", preset = "form", fields = {
            -- Shown in place of the group's widgets while the indicator-icon
            -- toggle is off.
            { control = "note", wide = true,
              hidden = function()
                  if NotBlizzMode() then return true end
                  return not IconsOff()
              end,
              text = "|cffff2020Due to Blizzard limitations, in Native mode "
                  .. "the overlay cannot be independently enabled without "
                  .. "showing the dispel indicator icons.|r" },
            { control = "switch", label = "Show Overlay",
              bind = "blizzardDispelShowOverlay", wide = true,
              desc = "Show the dispel overlay wash on the frame. The "
                  .. "overlay's border edge is part of the overlay and cannot "
                  .. "be toggled separately.",
              hidden = BlizzIconsHidden, onChange = effect,
              set = function(_, ctx, v)
                  root().blizzardDispelShowOverlay = v
                  ctx.app:RefreshPage()
              end },
            -- Stored 0..1; the panel's slider draws whole numbers, so the
            -- control works in percent.
            PctField("dispelIndicator", root, IP, "blizzardDispelOverlayOpacity",
                "Overlay Opacity", 0, 100, 5, effect,
                { desc = "Alpha of the Blizzard dispel overlay. 100% is fully "
                      .. "opaque, 0% invisible.",
                  disabled = false, hidden = BlizzOverlayHidden }),
            { control = "segmented", label = "Overlay Color",
              bind = "blizzardDispelOverlayColorMode",
              desc = "Color of the Blizzard dispel overlay: the dispel type's "
                  .. "debuff color, or black.",
              options = {
                  { value = "debuffColor", text = "Use Debuff Color" },
                  { value = "black",       text = "Black"            },
              },
              hidden = BlizzOverlayHidden, onChange = effect },
            { control = "switch", label = "Flashing Animation",
              bind = "blizzardDispelOverlayFlash",
              desc = "Pulse the Blizzard dispel overlay while a dispellable "
                  .. "debuff is present.",
              hidden = BlizzOverlayHidden, onChange = effect },
        }},

        -- dispelVisualDispMeGroup. The same two questions the "Dispellable by
        -- Me" row asks on the Preset/Filter subtab, asked SEPARATELY here:
        -- those govern the debuff ICONS, these govern the custom dispel
        -- indicator, border, color overlay and health tint (one funnel).
        -- Custom mode only: Blizzard native resolves "dispellable by me" with
        -- the game's own check, so these would be controls with no effect.
        -- No refresh wrapper: a dispelIndicator key already routes to
        -- RefreshDispelOnly, which is exactly the path these need.
        { title = "Dispellable by Me Settings", preset = "form", fields = {
            { control = "switch", label = "Only when talented",
              bind = "dispelVisualDispMeTalented", wide = true,
              desc = "Factor in Dispel talents. e.g. Exclude Poison & Curse "
                  .. "for Druid when Improved Nature's Cure is not talented.",
              hidden = function() return not DispelCustomMode() end,
              onChange = effect,
              get = OnUnlessFalse(IP, "dispelVisualDispMeTalented") },
            { control = "switch", label = "Include Long-Cooldown Dispels",
              bind = "dispelVisualDispMeLongCd", wide = true,
              desc = "Factor in long-cd dispel abilities. e.g. Include "
                  .. "poisons for Shaman when Poison Cleansing Totem is "
                  .. "talented.",
              hidden = function() return not DispelCustomMode() end,
              onChange = effect,
              get = OffUnlessTrue(IP, "dispelVisualDispMeLongCd") },
        }},

        -- dispelHeader and the custom indicator.
        { title = "Dispellable Debuff Indicator (Custom)", preset = "form",
          -- The whole custom surface belongs to Custom mode. On the GROUP
          -- now, not on every field: a gated card is shown whatever its
          -- fields say -- the switch in its header IS the card -- so the one
          -- predicate that used to hide it field by field has to move up.
          hidden = DispelBlizzardMode,
          toggle = Gate("showDispelIndicator",
              "Show Dispellable Debuff Indicator",
              "Shows a colored indicator in the corner of the frame when the "
              .. "unit has a debuff you can dispel."),
          fields = {
            { control = "segmented", label = "Indicator Style",
              bind = "dispelIndicatorStyle",
              desc = "Choose between a colored square or a dispel type icon",
              options = {
                  { value = "square", text = "Colored Square"   },
                  { value = "icon",   text = "Dispel Type Icon" },
              },
              hidden = DispelHidden, onChange = effect,
              -- The routed write already dispatches RefreshDispelOnly; the
              -- dispel-highlight sweep is separate work it does not touch.
              set = Setter("dispelIndicatorStyle", function()
                  if not InCombatLockdown() then SweepDebuffHighlight() end
              end) },
            { control = "segmented", label = "Indicator Mode",
              bind = "dispelIndicatorMode",
              options = {
                  { value = "dispellable",    text = "Dispellable by Me" },
                  { value = "allDispellable", text = "All Dispellable"   },
              },
              hidden = DispelHidden, onChange = effect,
              set = Setter("dispelIndicatorMode", SweepDebuffHighlight) },
            { control = "switch", label = "Only Show if Dispel Available",
              bind = "dispelIndicatorOnlyIfReady", wide = true,
              desc = ONLY_IF_READY_DESC:format("dispel indicator"),
              hidden = DispelHidden, onChange = effect,
              set = Setter("dispelIndicatorOnlyIfReady", function()
                  local bf = BF()
                  if bf and bf.UpdateDispelCooldownTracking then
                      bf:UpdateDispelCooldownTracking()
                  end
                  SweepDebuffHighlight()
              end) },
            { control = "slider", label = "Indicator Size",
              bind = "dispelIndicatorSize",
              desc = "Size of the dispel indicator in pixels",
              min = 2, max = 20, step = 1, refresh = "mouseup",
              hidden = DispelHidden, onChange = effect,
              set = Setter("dispelIndicatorSize", DispelIndicatorLayout) },
        }},

        -- dispelPositionGroup. The anchor point and its two offsets are ONE
        -- widget here: an offset is relative to a point, and all three share
        -- one side effect -- unlike the debuff icons' anchor, whose write
        -- also rewrites the grow direction and so cannot be a composite.
        { title = "Position", preset = "form", fields = {
            { control = "anchor", label = "Position",
              binds = { point = "dispelIndicatorPosition",
                        x     = "dispelIndicatorOffsetX",
                        y     = "dispelIndicatorOffsetY" },
              min = -60, max = 60, refresh = "mouseup",
              desc = "Anchor point on the frame for the dispel indicator",
              -- The X/Y sliders were the only widgets in this group carrying
              -- a real combat guard in the Ace page; one composite over the
              -- three takes the stricter of the two.
              disabled = "combat",
              hidden = DispelHidden,
              onChange = function(node)
                  effect(node)
                  DispelIndicatorLayout()
              end },
        }},

        -- debuffOverlayHeader and the Debuff Color Overlay section.
        { title = "Debuff Color Overlay", preset = "form",
          hidden = BorderHidden,
          toggle = Gate("enableDebuffOverlay", "Enable Debuff Color Overlay",
              "Shows a semi-transparent color overlay on the frame when a "
              .. "player has a dispellable debuff, fading from the debuff "
              .. "color at the top to transparent at the bottom. Similar to "
              .. "Blizzard's built-in raid frame overlay.",
              function()
                  if not InCombatLockdown() then SweepDebuffHighlight() end
              end),
          fields = {
            { control = "dropdown", label = "Overlay Mode",
              bind = "debuffOverlayMode", options = HIGHLIGHT_MODE_OPTIONS,
              hidden = OverlayHidden, disabled = OverlayOff, onChange = effect,
              set = Setter("debuffOverlayMode", function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
              end) },
            PctField("dispelIndicator", root, IP, "debuffOverlayAlpha",
                "Overlay Opacity", 10, 100, 5, effect,
                { hidden = OverlayHidden, disabled = OverlayOff,
                  onChange = function()
                      effect({ bind = "debuffOverlayAlpha" })
                      local bf = BF()
                      if not bf then return end
                      -- Two frame walks + a preview relayout used to run per
                      -- drag notch.
                      bf:MouseUpOption("aurasDebuffOverlay", function()
                          SweepDebuffHighlight()
                          if bf.RefreshPreviewHighlights then
                              bf:RefreshPreviewHighlights()
                          end
                      end)
                  end }),
            PctField("dispelIndicator", root, IP, "debuffOverlayHeight",
                "Overlay Height", 10, 100, 5, effect,
                { hidden = OverlayHidden, disabled = OverlayOff,
                  onChange = function()
                      effect({ bind = "debuffOverlayHeight" })
                      local bf = BF()
                      if not bf then return end
                      bf:MouseUpOption("aurasDebuffOverlay", function()
                          SweepDebuffHighlight()
                          if bf.RefreshPreviewHighlights then
                              bf:RefreshPreviewHighlights()
                          end
                      end)
                  end }),
            { control = "switch", label = "Health Fill Only",
              bind = "debuffOverlayFillOnly", wide = true,
              desc = "When enabled, the overlay only covers the filled "
                  .. "portion of the health bar instead of the entire bar "
                  .. "width.",
              hidden = OverlayHidden, disabled = OverlayOff, onChange = effect,
              set = Setter("debuffOverlayFillOnly", function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
              end) },
            { control = "switch", label = "Only Show if Dispel Available",
              bind = "dispelOverlayOnlyIfReady", wide = true, newRow = true,
              desc = ONLY_IF_READY_DESC:format("debuff overlay"),
              hidden = OverlayHidden, disabled = OverlayOff, onChange = effect,
              set = Setter("dispelOverlayOnlyIfReady", function()
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if bf and bf.UpdateDispelCooldownTracking then
                      bf:UpdateDispelCooldownTracking()
                  end
                  SweepDebuffHighlight()
              end) },
        }},

        -- debuffHealthColorHeader and the Debuff Health Color Change section.
        -- Orders 48.x sit between Debuff Color Overlay (40..47) and Debuff
        -- Border (50), which is where this card sits too.
        { title = "Debuff Health Color Change", preset = "form",
          hidden = BorderHidden,
          toggle = Gate("enableDebuffHealthColor",
              "Enable Debuff Health Color Change",
              "Tints the player's health bar in the debuff's dispel type "
              .. "color while a matching debuff is active.",
              function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
                  local bf = BF()
                  if bf and bf.RefreshPreviewDummyAuras then
                      bf:RefreshPreviewDummyAuras()
                  end
              end),
          fields = {
            { control = "dropdown", label = "Mode",
              bind = "debuffHealthColorMode", options = HIGHLIGHT_MODE_OPTIONS,
              hidden = HealthColorSubHidden, onChange = effect,
              set = Setter("debuffHealthColorMode", function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
              end) },
            PctField("dispelIndicator", root, IP, "debuffHealthColorAlpha",
                "Opacity", 10, 100, 5, effect,
                { desc = "Strength of the dispel-type-colored health bar tint.",
                  hidden = HealthColorSubHidden,
                  onChange = function()
                      effect({ bind = "debuffHealthColorAlpha" })
                      local bf = BF()
                      if not bf then return end
                      bf:MouseUpOption("aurasDebuffHealthColor",
                                       SweepDebuffHighlight)
                  end }),
            { control = "switch", label = "Only Show if Dispel Available",
              bind = "dispelHealthColorOnlyIfReady", wide = true,
              desc = ONLY_IF_READY_DESC:format("health color change"),
              hidden = HealthColorSubHidden, onChange = effect,
              set = Setter("dispelHealthColorOnlyIfReady", function()
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if bf and bf.UpdateDispelCooldownTracking then
                      bf:UpdateDispelCooldownTracking()
                  end
                  SweepDebuffHighlight()
              end) },
        }},

        -- debuffBorderHeader and the Debuff Border section.
        { title = "Debuff Border", preset = "form",
          hidden = BorderHidden,
          toggle = Gate("enableDebuffBorder", "Enable Debuff Border",
              "Shows a colored border on the frame when a player is affected "
              .. "by debuffs (dispellable or all).",
              function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
                  local bf = BF()
                  if bf and bf.RefreshPreviewDummyAuras then
                      bf:RefreshPreviewDummyAuras()
                  end
              end),
          fields = {
            { control = "dropdown", label = "Highlight Mode",
              bind = "debuffBorderMode", options = HIGHLIGHT_MODE_OPTIONS,
              hidden = BorderHidden, disabled = BorderOff, onChange = effect,
              set = Setter("debuffBorderMode", function()
                  if InCombatLockdown() then return end
                  SweepDebuffHighlight()
              end) },
            { control = "stepper", label = "Border Width",
              bind = "debuffBorderWidth",
              min = 1, max = 5, step = 1,
              hidden = BorderHidden, disabled = BorderOff, onChange = effect,
              set = Setter("debuffBorderWidth", function()
                  local bf = BF()
                  if not bf then return end
                  -- Two full frame walks plus a preview relayout used to run
                  -- per drag notch. The BF helper re-checks combat.
                  bf:MouseUpOption("aurasDebuffBorderWidth", function()
                      bf:LayoutAllIndicators()
                      SweepDebuffHighlight()
                      if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
                  end)
              end) },
            { control = "switch", label = "Only Show if Dispel Available",
              bind = "dispelBorderOnlyIfReady", wide = true,
              desc = ONLY_IF_READY_DESC:format("debuff border"),
              hidden = BorderHidden, disabled = BorderOff, onChange = effect,
              set = Setter("dispelBorderOnlyIfReady", function()
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if bf and bf.UpdateDispelCooldownTracking then
                      bf:UpdateDispelCooldownTracking()
                  end
                  SweepDebuffHighlight()
              end) },
        }},
    }
end

-- ══════════════════════════════════════════════════════════════
-- The three pages
-- ══════════════════════════════════════════════════════════════
--
-- Published so Panel.lua builds the route children from the same list that
-- builds the pages.
BuzzardFramesOptions.DEBUFFS_SUBTABS = {
    { id = "tabDebuffs",         title = "Debuffs" },
    { id = "debuffPresetFilter", title = "Debuff Preset/Filter" },
    { id = "tabDispel",          title = "Dispel Indicators" },
}

-- ── Sub-category trackers ──────────────────────────────────────
--
-- The Ace page carried an invisible `description` widget per subtab
-- (makeSubcatTracker) whose `name` callback fired on every render and
-- stamped which sub-category was on screen -- BF._currentAurasSubcat,
-- and for the scoped subtab BF._currentAurasScopeToggle. That is what
-- tells the dummy-aura preview what to show, and what the Ace Modifying
-- Layout dropdown read to decide whose toggle governs it.
--
-- A render hook hidden inside a widget has no panel equivalent and needs
-- none: the library has route observers, which say the same thing
-- outright and fire on ENTRY rather than on every repaint. The same
-- shape Pages_Buffs.lua uses for its own two subtabs -- each page file
-- arms the observers for its OWN routes, so there is one place to look
-- when a subtab reports the wrong context.
local SUBTAB_SUBCAT = {
    tabDebuffs         = "debuffs",
    debuffPresetFilter = "debuffs",
    tabDispel          = "dispelIndicator",
}

-- The one SCOPED subtab. Stamped so the scope's own per-Layout toggle is
-- the one consulted while it is on screen; cleared on the others, or a
-- stamp left behind here would outlive the subtab that set it.
local SUBTAB_SCOPE = {
    debuffPresetFilter = "auras_debuffFilter",
}

local function EnterSubcat(app, subtabId)
    local bf = BF()
    if not bf then return end
    local subcat = SUBTAB_SUBCAT[subtabId]
    if not subcat then return end

    -- Both aura sections report "auras": that value drives preview
    -- context and the Modifying-Layout dropdown, neither of which needs
    -- to tell Buffs from Debuffs, and reporting a new one would silently
    -- change both behaviors.
    -- A page built under a Custom Frame Group scope reports
    -- "customFrameAuras" instead, exactly as the Ace CFG page's own
    -- _sectionTracker did -- otherwise the preview draws for the raid.
    bf._currentSection          = (bf.BFOSectionName and bf:BFOSectionName())
                                  or "auras"
    bf._currentAurasSubcat      = subcat
    bf._currentAurasScopeSubcat = subcat
    -- Always written -- nil for a plain subtab -- so the scoped stamp
    -- never outlives the subtab that set it.
    bf._currentAurasScopeToggle = SUBTAB_SCOPE[subtabId]

    -- A plain aura subtab is not a container subtab, so the index a
    -- container subtab stamps is cleared on the way out along with the
    -- container preview filter -- without which the preview keeps
    -- showing only that one container here. Guarded on the index
    -- changing, so it fires once per container -> subtab transition.
    local leftContainer = bf._currentContainerIndex ~= nil
    if leftContainer then
        bf._currentContainerIndex = nil
        if bf.ClearAuraPreview then bf:ClearAuraPreview() end
    end
    -- REPAINTED ON EVERY ARRIVAL, not only when a container was left --
    -- see Pages_Buffs.lua's EnterSubcat: the two sections share one
    -- section key, so nothing else repaints the previews for the new
    -- sub-category, and they kept showing the one just left.
    if not InCombatLockdown() then
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
        if leftContainer and app then app:RefreshPage() end
    end
end

local observersArmed = false

-- Armed the first time a page is built rather than at file scope: the
-- app exists only once the panel has been opened.
local function EnsureObservers()
    if observersArmed then return end
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    local app = Panel and Panel:GetApp("BuzzardFrames")
    if not app then return end
    observersArmed = true
    for id in pairs(SUBTAB_SUBCAT) do
        -- WithScope(nil, ...): observers fire from the navigation, BEFORE
        -- the render that would rebind the scope, so on a Custom Frame
        -- Groups -> Raid/Party move this body would otherwise run with the
        -- group's scope still bound -- stamping "customFrameAuras" onto a
        -- Raid/Party arrival, and writing every stamp through the proxy.
        app:RegisterRouteObserver("raidPartyFrames/aurasDebuffs/" .. id,
            function(isActive, _, appNow)
                if not isActive then return end
                BuzzardFramesOptions:WithScope(nil, EnterSubcat, appNow or app, id)
            end)
        -- The Custom Frame Groups twin, run under the group's scope so
        -- the entry stamp names the custom-frame section.
        app:RegisterRouteObserver("customFrames/aurasDebuffs/" .. id,
            function(isActive, _, appNow)
                if not isActive then return end
                local scope = BuzzardFramesOptions.CFGScopeFor
                              and BuzzardFramesOptions:CFGScopeFor("aurasDebuffs")
                if scope then
                    BuzzardFramesOptions:WithScope(scope, EnterSubcat, appNow or app, id)
                else
                    EnterSubcat(appNow or app, id)
                end
            end)
    end
end

function BuzzardFramesOptions:DebuffsPage(subtabId, label)
    EnsureObservers()
    -- Stamped inline as well as by the observers, exactly as BuffsPage does:
    -- the observers above are armed by THIS build, which runs after the
    -- navigation that brought the reader here, so the session's first
    -- arrival on a Debuffs subtab fired none of them. The section observer
    -- does not cover that arrival either -- Buffs and Debuffs share one
    -- section key, so a Buffs -> Debuffs move is not a section change. With
    -- nothing stamping "debuffs", BF._currentAurasSubcat still said "buffs",
    -- GetActivePreviewMode kept reading previewModeBuffs, and the previews
    -- went on drawing the Buffs section's choice on a Debuffs page.
    EnterSubcat(nil, subtabId)
    -- The Ace section emitted its Aura Preview dropdown ONCE, on the SECTION
    -- root (order 0.2), where it rendered above the tab strip and so
    -- appeared on every subtab. A route has no section root -- `aurasDebuffs`
    -- is a pure branch with a `tabs` navigator -- so each page declares it as
    -- its `headerField`, which the library draws in the page header ABOVE
    -- the strip. Three declarations over one stored value
    -- (db.global.previewModeDebuffs), drawn once, where Ace drew it. The
    -- SECTION name is what picks the key, never the subtab.
    local preview = self:AuraPreviewField("aurasDebuffs")

    if subtabId == "tabDebuffs" then
        local groups = { self:AuraScopeStrip("debuffs") }
        for _, g in ipairs(DebuffsGroups(self:AuraEffect("debuffs"))) do
            groups[#groups + 1] = g
        end
        return {
            db       = function() return self:AuraRoot("debuffs") end,
            defaults = self:AuraDefaults("debuffs"),
            headerField = preview,
            groups   = groups,
        }
    end

    if subtabId == "debuffPresetFilter" then
        -- The SCOPED strip: this subtab's per-Layout toggle is
        -- auras_debuffFilter, over the same `debuffs` storage its neighbor
        -- edits, and its Copy carries only this scope's keys.
        local rows, rowAt = PresetFilterGroups(self:AuraEffect("debuffs"))

        local groups = { self:AuraScopeStrip("debuffs", "auras_debuffFilter") }
        -- rowAt is indexed by position within `rows`; the two leading groups
        -- shift every one of them.
        local offset  = #groups
        local shifted = {}
        for i, g in ipairs(rows) do
            groups[#groups + 1] = g
            if rowAt[i] then shifted[i + offset] = rowAt[i] end
        end
        -- A page that declares `reorder` makes EVERY card draggable unless
        -- the card says otherwise, so every card that is not a priority row
        -- says so. `reorderable = false` also means FIXED rather than merely
        -- undraggable -- a row cannot be dropped into a pinned card's
        -- position either, which is what keeps the list penned between the
        -- notes above it and the Combine card below.
        for i = 1, #groups do
            if not shifted[i] then groups[i].reorderable = false end
        end

        return {
            db       = function() return self:AuraRoot("debuffs") end,
            defaults = self:AuraDefaults("debuffs"),
            headerField = preview,
            groups   = groups,
            -- ── Drag to reorder, in place of the Ace up/down arrows ──
            --
            -- The library owns the gesture, the combat gate, the insertion
            -- line and the rebuild; this supplies the one call that changes
            -- the storage. `reorderable = false` on the residual "Other
            -- Debuffs" card and on every non-row card does the rest: the
            -- library will not drag a pinned card and will not let anything
            -- take a pinned card's position, which is exactly the pair of
            -- rules debuffMoveTarget enforced by hand.
            reorder = {
                onMove = function(group, from, to)
                    local movingRow = shifted[from] or group.debuffRow
                    local targetRow = shifted[to]
                    if not (movingRow and targetRow) then return end
                    local list = VisibleRows()
                    local ti
                    for i = 1, #list do
                        if list[i] == targetRow then ti = i end
                    end
                    MoveRowTo(movingRow, ti)
                end,
            },
        }
    end

    if subtabId == "tabDispel" then
        local groups = { self:AuraScopeStrip("dispelIndicator") }
        for _, g in ipairs(DispelGroups(self:AuraEffect("dispelIndicator"))) do
            groups[#groups + 1] = g
        end
        return {
            db       = function() return self:AuraRoot("dispelIndicator") end,
            defaults = self:AuraDefaults("dispelIndicator"),
            headerField = preview,
            groups   = groups,
        }
    end

    return { groups = {} }
end
