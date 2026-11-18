-- ============================================================
-- BuzzardFrames: AuraCustomizations/AuraCustomizationHelpers.lua
-- AC-specific lookup functions for per-spec spell color,
-- border color, and solid icon overrides.
--
-- Extracted from Auras/AuraConfig.lua. All reads come from the
-- AuraCustomizations namespace (BF.acDB.profile).
--
-- Must be loaded after AuraConfig.lua (needs BF.playerSpecID).
-- ============================================================
local BF = _G["BuzzardFrames"]

local canaccessvalue = canaccessvalue or function(val) return true end

-- v43 master customize flag: every per-spell lookup is gated on
-- specSpellCustomized[specId][sid]. Unflagged spells behave as if they
-- have no customizations at all (both engines; preview included).
--
-- v62 OWNER DECISION: the curated (Aura Customizations section) per-spell
-- settings drive 12.0.7 ONLY. On 12.1 per-spell visuals exist solely as
-- Single Buff entries, read through the sbC branches of the getters below.
-- Every curated per-spell getter routes through this predicate, so failing
-- it on 12.1 is the single choke point that inactivates them there -- for
-- live frames AND for the options previews, which use the same getters and
-- must show what 12.1 live shows.
--
-- v64: STILL TRUE OF VISUALS, no longer true of the feature as a whole. Order
-- was split out and is now live on 12.1: an ordered spell gets its own
-- per-spell group (GetContainerBuffConfig in AuraCustomizations.lua), because
-- layoutIndex orders groups and no sort comparator takes a user rank. That
-- group is styled by DeriveSpellButtonSpec, which starts from the plain
-- BuffButtonSpec and only layers overrides where a getter returns something --
-- so with this predicate still closed, a promoted spell is ordered but looks
-- like any other buff. That is deliberate and is the whole shape of the
-- deferral.
--
-- Un-gating THIS is what turns per-spell visuals back on for 12.1 containers,
-- and is the future "group type" dropdown. Two things must move with it, or
-- the result is inconsistent: the direct (non-helper) per-spell visual-alert
-- read in DeriveSpellButtonSpec, and the options UI that currently offers only
-- Display Type + Order per assigned spell. See
-- Docs/Per_Spell_Settings_In_Container_Subtabs_Plan.md.
--
-- v67: 12.0.7 branch removed (addon is 12.1-only). The flag is permanently
-- true, so this predicate is permanently FALSE and the curated per-spell
-- lookup below it (specSpellCustomized[specId][spellId]) is unreachable --
-- it is deleted rather than left dangling because Lua requires `return` to
-- end its block. Un-gating per-spell visuals for containers means restoring
-- that lookup here; see the note above.
local function IsCust(specId, spellId)
    return false
end

-- ============================================================
-- v62 (plan 3.67 slice 2): SINGLE-BUFF VISUAL STORE
--
-- A single buff owns its per-entry visuals, because two entries of the same
-- spell must be able to look different -- which acDB.profile.specSpell*
-- [specId][spellId] cannot express. The options side writes them through a
-- STORAGE ACCESSOR (Options_AuraCustomizations.lua) whose only difference from
-- the curated one is where the family tables live and what the first key is:
--
--   curated spell -> acDB.profile[family][<specID>][spellID]
--   single buff   -> container.sbVisuals[family]["sb"][spellID]
--
-- The specSpell* families are NOT re-keyed. This is a second source alongside
-- them; every getter below takes an OPTIONAL single-buff container and reads
-- that source instead when one is supplied. Passing nil (every pre-existing
-- caller) is byte-for-byte the old behavior, so nothing on a per-aura path
-- changes: the branch only exists where the caller already knows it is styling
-- a single buff's container, which is settings/Layout time by construction.
--
-- The master-customize flag has no analogue here. A single buff's own Display
-- Type dropdown plays that role: "Show (Default Buff)" sets
-- singleBuffCustomized = false, which nils out the store below so the icon
-- falls back to the container's own settings.
-- ============================================================
local SB_KSPEC = "sb"

-- The store root for a single-buff container, or nil (not a single buff / not
-- in Customized mode / nothing configured).
local function SBRoot(c)
    if type(c) ~= "table" or not c.singleBuff then return nil end
    if c.singleBuffCustomized == false then return nil end
    return c.sbVisuals
end
BF.GetSingleBuffVisualRoot = SBRoot

-- Display-tab redesign (owner, 2026-10-14): CUSTOMIZE BUFF APPLIES ONLY TO
-- THE ICON. SBRoot above stays the ICON root (nil while not customized); the
-- families below are read from the entry's store WHATEVER Customize Buff
-- says, because each is a customization of its own with its own switch on
-- the Display tab:
--   specSpellIconHidden / specSpellTextInPlace  Show Buff Icon / Show Text
--                                               in place of Icon
--   specSpellBar                                Show Buff Bar (+ the bar)
--   specSpellFrameFxOn                          Show Frame Effects
-- The three FRAME EFFECT families (health tint, frame border, overlay) are
-- read only while that spell's Show Frame Effects is on, customized or not.
-- Cooldown Text is an ICON family with one exception: while the entry's
-- text stands in for its icon ("text" mode) it styles that text, so it is
-- read then even when the icon is not customized (with no override set the
-- text keeps the inherited defaults, exactly as before).
-- Everything else (icon type, solid / square, border color, icon effects,
-- Show Cooldown Text) stays behind SBRoot. Order never was (GetSingleBuffOrder
-- reads the raw store).
local SB_UNGATED_FAMILIES = {
    specSpellIconHidden  = true,
    specSpellTextInPlace = true,
    specSpellBar         = true,
    specSpellFrameFxOn   = true,
}
local SB_FRAME_FX_FAMILIES = {
    specSpellColors   = true,
    specSpellBorders  = true,
    specSpellOverlays = true,
}
BF.SB_UNGATED_FAMILIES  = SB_UNGATED_FAMILIES
BF.SB_FRAME_FX_FAMILIES = SB_FRAME_FX_FAMILIES

-- One family's raw entry, ignoring Customize Buff.
local function SBRawEntry(c, family, spellId)
    if type(c) ~= "table" or not c.singleBuff then return nil end
    local root = c.sbVisuals
    local fam  = type(root) == "table" and root[family]
    local map  = type(fam) == "table" and fam[SB_KSPEC]
    return type(map) == "table" and map[spellId] or nil
end
BF.GetSingleBuffRawVisualEntry = SBRawEntry

-- One family's entry for `spellId` on a single-buff container, or nil --
-- through the gating above.
local function SBEntry(c, family, spellId)
    if SB_UNGATED_FAMILIES[family] then return SBRawEntry(c, family, spellId) end
    if SB_FRAME_FX_FAMILIES[family] then
        if SBRawEntry(c, "specSpellFrameFxOn", spellId) ~= true then return nil end
        return SBRawEntry(c, family, spellId)
    end
    if family == "specSpellCooldownText" and type(c) == "table"
       and c.singleBuff and c.singleBuffCustomized == false then
        if SBRawEntry(c, "specSpellIconHidden", spellId) == true
           and SBRawEntry(c, "specSpellTextInPlace", spellId) == true then
            return SBRawEntry(c, family, spellId)
        end
        return nil
    end
    local root = SBRoot(c)
    local fam  = root and root[family]
    local map  = fam and fam[SB_KSPEC]
    return map and map[spellId] or nil
end
BF.GetSingleBuffVisualEntry = SBEntry

-- ============================================================
-- SOLID ICON OVERRIDE HELPER
-- Returns the solid color table {r,g,b} for a spellId if configured,
-- or nil to use the normal icon texture.
-- ============================================================
-- v62: `sbC` is an optional single-buff CONTAINER. When present the entry comes
-- from that container's own store and the spec / master-flag gates do not apply
-- (a single buff has neither).
local function GetSolidIconColor(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        local e = SBEntry(sbC, "specSpellSolidIcons", spellId)
        if not e or e.enabled == false then return nil end
        return e
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local si = p and p.specSpellSolidIcons and p.specSpellSolidIcons[specId]
    local entry = si and si[spellId]
    if entry and entry.enabled == false then return nil end
    return entry
end
BF.GetSolidIconColor = GetSolidIconColor

-- v67: BF.GetBuffsSolidIconColor removed. It was the blanket "any buff visible"
-- solid icon color, a 12.0.7-only AC setting; with that client gone the stub
-- returned nil unconditionally, so every caller's fallback branch was dead.
-- Callers must drop the fallback rather than nil-guard the missing function.

-- Returns the custom border color table {r,g,b} for a spellId if configured,
-- or nil to use the default border.
local function GetSpellBorderColor(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        local e = SBEntry(sbC, "specSpellBorderColors", spellId)
        if not e or e.enabled == false then return nil end
        return e
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local bc = p and p.specSpellBorderColors and p.specSpellBorderColors[specId]
    local entry = bc and bc[spellId]
    if entry and entry.enabled == false then return nil end
    return entry
end
BF.GetSpellBorderColor = GetSpellBorderColor

-- v67: BF.GetBuffsBorderColor removed, for the same reason as
-- GetBuffsSolidIconColor above -- a 12.0.7-only blanket setting whose stub
-- returned nil unconditionally.

-- Returns the STORED icon type string for a spellId if configured:
-- "Square"; nil for default ("Icon"). Legacy saved values may still be
-- "BorderedSquare" (v69: replaced by Square + the solid entry's
-- showBorder flag) or "SquareDuration" (v69: merged into Square — the
-- glyph render path follows the entry's thresholdEnabled flag instead).
-- Consumers map both legacy values at READ time rather than migrating
-- them (profile copies dodge numbered migrations).
local function GetSpellIconType(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        return SBEntry(sbC, "specSpellIconType", spellId)
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local it = p and p.specSpellIconType and p.specSpellIconType[specId]
    return it and it[spellId]
end
BF.GetSpellIconType = GetSpellIconType

-- ============================================================
-- Per-spell SHOW ICON / TEXT IN PLACE OF ICON (Duration Bar plan §5.1-5.2)
-- Two per-entry flags, each its own family and each stored ONLY when it
-- differs from the default (absent = icon shown / no text in its place),
-- so nothing migrates:
--   specSpellIconHidden[specId][spellId]  = true  -- Show Icon OFF
--   specSpellTextInPlace[specId][spellId] = true  -- duration text stands
--                                                    in the icon's place
-- Neither is per-Layout and neither sits under the Cooldown Text override.
-- Same gates as GetSpellIconType: `sbC` routes to the single buff's own
-- store, the curated path needs the spec and the master customize flag.
-- The text area's size is NOT here: it is a container field
-- (textAreaUsesBuffSize / textAreaSize, two-tier like buffSize; an unset
-- textAreaSize shows the entry's buffSize in the options).
-- ============================================================
local function GetSpellIconHidden(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        return SBEntry(sbC, "specSpellIconHidden", spellId) == true or nil
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local t = p and p.specSpellIconHidden and p.specSpellIconHidden[specId]
    return (t and t[spellId]) == true or nil
end
BF.GetSpellIconHidden = GetSpellIconHidden

local function GetSpellTextInPlace(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        return SBEntry(sbC, "specSpellTextInPlace", spellId) == true or nil
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local t = p and p.specSpellTextInPlace and p.specSpellTextInPlace[specId]
    return (t and t[spellId]) == true or nil
end
BF.GetSpellTextInPlace = GetSpellTextInPlace

-- Display-tab redesign: SHOW COOLDOWN TEXT, per entry, default ON. Stored
-- only when OFF (specSpellCooldownTextOff[sb][sid] = true), as an ICON family:
-- it is a property of the customized icon, so it reads nil for an entry that
-- is not customized (that icon keeps its inherited duration text).
local function GetSpellCooldownTextOff(spellId, sbC)
    if not (sbC and spellId) or not canaccessvalue(spellId) then return nil end
    return SBEntry(sbC, "specSpellCooldownTextOff", spellId) == true or nil
end
BF.GetSpellCooldownTextOff = GetSpellCooldownTextOff

-- What a single-buff ENTRY's icon slot/group does (Duration Bar plan
-- §5.1-5.2), from the two flags above, read through the entry's own store:
--   nil    -- the icon is shown (every entry that never touched Show Icon;
--             since the Display-tab redesign Show Icon is read for an
--             uncustomized entry too -- it is not an icon customization)
--   "text" -- Show Icon OFF + Show Text in place of Icon ON: the slot/group
--             stays, sized by Text Area Size, and draws the duration text
--             (and the stack count) where the icon was
--   "none" -- Show Icon OFF and nothing would be drawn: no slot/group is
--             built or used at all and the entry takes no space. The entry
--             STILL claims its spell (owner's claim rule, plan §5.1) -- that
--             is the callers' business.
--
-- "none" covers two cases (owner ruling, Stage 2 follow-up): no text in the
-- icon's place, OR text in its place that resolves to drawing NOTHING in this
-- Layout -- the duration text off AND the stack count off. Those are the only
-- two things a text-mode button draws (no icon, border, swipe or icon effect
-- -- DeriveSpellButtonSpec), so with both off it is an empty box.
--
-- PER LAYOUT. Show Duration can differ per Layout (the Cooldown Text tab's
-- per-Layout tier) and per frame scope (the aura cache), so the answer takes
-- the frame's groupTypeKey and aura cache, and reads them through EXACTLY the
-- resolution DeriveSpellButtonSpec stamps onto the button spec:
--   duration text: ResolveSpellCooldownText(sid, groupTypeKey, ac, c).showDur
--                  when the entry overrides it, else ac.showBuffDuration
--                  (BuffButtonSpec's own default);
--   stack count:   ac.showStackText ~= false (BF:ApplyStackTextSpec -- Aura
--                  Text > Stack Text > Show Stack Text; single-buff entries
--                  have no stack setting of their own).
-- So the collection, the slot build/park, the size memo, the size resolver,
-- the spec and the preview can never disagree about whether the box is empty.
-- `ac` nil falls back to BF.AuraCache, as the cooldown-text resolver does.
--
-- Layout / settings time only; never reached per aura. The cooldown-text
-- resolve is cached per (entry, groupTypeKey) by its own resolver.
-- Header-fix round, item 5 (owner, 2026-10-14): the DURATION STYLE an
-- UNCUSTOMIZED entry's stand-in text takes when it flows in a multi-icon buff
-- container: that container's own (BF:ResolveContainerDuration -- the same
-- resolution ApplyContainerDuration stamps on the default icon there), so the
-- text looks like the default icon would. nil anywhere else: a customized
-- entry, a Buffs / Big Defensive / self-positioned entry (their default icon
-- carries the Buffs-section style, which is the spec's own base), or a
-- container inheriting the section style. Returns the resolved table and the
-- host container. Layout / settings time only.
local function SingleBuffTextHostDuration(c, groupTypeKey, ac)
    if type(c) ~= "table" or not c.singleBuff or c.singleBuffCustomized ~= false then
        return nil
    end
    local h = BF.GetSingleBuffAnchorHost and BF:GetSingleBuffAnchorHost(c, groupTypeKey)
    local ci = h and h.kind == "bfc" and h.ci
    if not ci then return nil end
    local all = BF.GetCustomBuffContainers and BF:GetCustomBuffContainers()
    local hostC = all and all[ci]
    if type(hostC) ~= "table" or hostC.singleBuff then return nil end
    local r = BF.ResolveContainerDuration
        and BF:ResolveContainerDuration(hostC, groupTypeKey, ac) or nil
    return r, hostC
end
BF.SingleBuffTextHostDuration = SingleBuffTextHostDuration

local function GetSingleBuffIconMode(c, groupTypeKey, ac)
    if type(c) ~= "table" or not c.singleBuff then return nil end
    local sid = BF.GetSingleBuffSpellID and BF:GetSingleBuffSpellID(c)
    if not sid or not GetSpellIconHidden(sid, c) then return nil end
    if not GetSpellTextInPlace(sid, c) then return "none" end
    ac = ac or BF.AuraCache
    local r = BF.ResolveSpellCooldownText
        and BF.ResolveSpellCooldownText(sid, groupTypeKey, ac, c)
    local showDur
    if r then
        showDur = r.showDur
    else
        -- An uncustomized entry in a buff container takes that container's
        -- duration style (item 5); everything else the Buffs section's.
        local hr = SingleBuffTextHostDuration(c, groupTypeKey, ac)
        if hr then
            showDur = hr.showDur
        else
            showDur = ac and ac.showBuffDuration
        end
    end
    if showDur then return "text" end
    -- No aura cache at all: keep the space (a false "none" would lose a
    -- display; a false "text" costs an empty box until the next Layout).
    if not ac or ac.showStackText ~= false then return "text" end
    return "none"
end
BF.GetSingleBuffIconMode = GetSingleBuffIconMode

-- ============================================================
-- Per-spell DURATION BAR (Duration Bar plan §5.4, §6)
-- Returns the bar settings table for a spellId and the raw entry, or
-- nil, nil when the bar is not shown in this scope.
--
-- Storage: specSpellBar[specId][spellId] -- the SAME per-Layout shape as
-- specSpellCooldownText: the entry's own fields, plus
-- groupSettings[<groupTypeKey>] while separateGroupConfig is on. Unlike
-- the cooldown-text resolver a missing or partial layout tier is not "off":
-- every field falls back from the tier to the entry (the options panel's
-- barField reads it the same way), so callers do field-level fallback
-- (settings field -> entry field), and Show Bar itself is resolved that way
-- here.
-- Entry / tier fields (absent = default):
--   showBar          bool                       false
--   orientation      "HORIZONTAL"|"VERTICAL"    "HORIZONTAL"
--   widthPct         fraction of health bar W   1.0 horiz / 0.05 vert
--   heightPct        fraction of health bar H   0.05 horiz / 1.0 vert
--   fillMode         "DRAIN"|"FILL"             "DRAIN"
--   reverseFill      bool                       false
--   smoothFill       bool                       true (owner, 2026-10-14;
--                                                 only an explicit false is off)
--   useHealthTexture bool                       true
--   texture          LSM statusbar name         "Solid" (when not health)
--   color            {r,g,b,a}                  {0.24, 1.0, 0.25, 1.0}
--   backgroundColor  {r,g,b,a}                  {0, 0, 0, 0.5}
--   backgroundCovers "WHOLE"|"UNFILLED"         "WHOLE"
--   borderStyle      "none"|"flat"              "none"
--   borderThickness  1-5                        1
--   borderColor      {r,g,b,a}                  {0, 0, 0, 1}
--   pandemic         bool                       false
--   pandemicColor    {r,g,b,a}                  {0.239216, 1, 0.254902, 0.15}
--   pandemicBackground bool                     false (tint the FILLED part
--                                                 only; true = the whole bar)
--   anchorPoint      grid point | BUFFS | BIGDEF | "C:<key>"   "BOTTOM"
--   offsetX, offsetY number                     0, 0
--   relativeOrder    "BEFORE"|"AFTER"           "BEFORE" (flow hosts only)
--   showEmptyBar     bool                       false (not for flow hosts)
--   placeAurasAbove  bool  horizontal bar, bottom-edge anchor
--   placeAurasBelow  bool  horizontal bar, top-edge anchor
--   pushAurasAside   bool  vertical bar, left- or right-edge anchor
--     (the three push flags apply only with showEmptyBar on, and only the
--      one matching the current Direction + anchor edge is consulted)
-- ============================================================
local function GetSpellBar(spellId, groupTypeKey, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil, nil end
    local entry
    if sbC then
        entry = SBEntry(sbC, "specSpellBar", spellId)
    else
        local specId = BF.playerSpecID
        if not specId then return nil, nil end
        if not IsCust(specId, spellId) then return nil, nil end
        local p = BF.acDB and BF.acDB.profile
        local sb = p and p.specSpellBar and p.specSpellBar[specId]
        entry = sb and sb[spellId]
    end
    if type(entry) ~= "table" then return nil, nil end
    local s = entry
    if entry.separateGroupConfig and groupTypeKey then
        s = (entry.groupSettings and entry.groupSettings[groupTypeKey]) or entry
    end
    local show = s.showBar
    if show == nil and s ~= entry then show = entry.showBar end
    if show ~= true then return nil, nil end
    return s, entry
end
BF.GetSpellBar = GetSpellBar

-- ============================================================
-- Duration Bar plan §5.5 / §6: RESOLVED BAR SPEC (Stage 3)
-- One table describing how a bar renders on ONE frame, from the settings
-- GetSpellBar returned (`s` = the per-Layout tier or the entry, `entry` =
-- the entry). Field-level fallback tier -> entry -> v1 default, exactly as
-- the options panel's barField reads. ONE derivation for the live sbb<ci>
-- slot (Indicators/BuffsAndContainers.lua) and the options preview
-- (Auras/DummyAuras.lua), so the two cannot size or color a bar
-- differently. Layout / settings time only; a FRESH table per call (colors
-- copied, never aliased to saved variables).
--
-- SIZE is a fraction of the frame's CONTENT rect (the health area inside
-- the border, minus a shown power bar): parent._bf_contentW/_bf_contentH,
-- published by Container:Layout, else BF.ComputeFrameContentSize (the same
-- arithmetic, for a consumer that runs before the frame is laid out). Never
-- GetWidth/GetHeight -- secret on 12.1 unit buttons. w/h are nil when
-- neither source answers; callers then skip the size write.
--
-- `flow` is true when the bar's anchor is a flow host (Buffs / Big
-- Defensive / a container) -- Stage 4; the self-positioned path ignores
-- such a bar.
-- ============================================================
local BAR_WHITE = "Interface\\Buttons\\WHITE8X8"
local function BarColor(c, r, g, b, a)
    if type(c) ~= "table" then return { r = r, g = g, b = b, a = a } end
    return { r = c.r or r, g = c.g or g, b = c.b or b, a = c.a or a }
end

-- BORDER EDGE (owner 2026-10-12): a self-positioned bar anchors to the
-- content rect (parent.container -- SingleBuffBarTarget,
-- BuffsAndContainers.lua), and Container:Layout deliberately extends that
-- rect HALF A PHYSICAL PIXEL under the border on every side (its seam
-- overlap: inset = borderUI - halfPx, BF.ComputeFrameContentGeometry). So:
--   * offsetX / offsetY are the EFFECTIVE offsets: the stored offset plus
--     halfPx inward on each axis whose edge the anchor point sits on
--     (LEFT/RIGHT, TOP/BOTTOM; a centered axis gets none). The bar's outer
--     edge then lands exactly on the border's inner edge -- or, at the
--     bottom with a power bar shown, exactly on the power bar's top edge
--     (the content rect overlaps the power bar by the same halfPx).
--   * w / h stay a fraction of the content size, clamped to the content
--     size minus halfPx on both sides, so a 100% bar ends exactly on the far
--     border's inner edge instead of 2 x halfPx under it.
-- Every consumer (placement, geometry sig, power-bar re-place, preview)
-- reads these two fields, so the edge rule lives here once.
function BF.ResolveSpellBarSpec(parent, s, entry)
    if type(s) ~= "table" then return nil end
    entry = entry or s
    local function f(k)
        local v = s[k]
        if v == nil and s ~= entry then v = entry[k] end
        return v
    end
    local vertical = f("orientation") == "VERTICAL"
    local bs = {}
    bs.orientation = vertical and "VERTICAL" or "HORIZONTAL"
    local anchor = f("anchorPoint") or "BOTTOM"
    bs.anchor  = anchor
    bs.flow    = (BF.IsFlowAnchorValue and BF.IsFlowAnchorValue(anchor)) and true or false
    -- Stage 4: a flow-hosted bar's Relative Order (Before / After), mapped by
    -- the host emit onto the same layoutIndex bands the icon's uses.
    bs.after   = f("relativeOrder") == "AFTER"
    -- Half a physical pixel in UI units, derived from Container:Layout's own
    -- geometry (0 with no border, or a rounded one: no seam overlap then).
    local halfPx = 0
    if parent and BF.ComputeFrameContentGeometry then
        local _, _, inset, _, _, borderUI = BF.ComputeFrameContentGeometry(parent)
        if inset and borderUI then halfPx = borderUI - inset end
    end
    local edgeX, edgeY = 0, 0
    if not bs.flow and type(anchor) == "string" then
        if anchor:find("LEFT") then edgeX = halfPx
        elseif anchor:find("RIGHT") then edgeX = -halfPx end
        if anchor:find("TOP") then edgeY = -halfPx
        elseif anchor:find("BOTTOM") then edgeY = halfPx end
    end
    bs.offsetX = (f("offsetX") or 0) + edgeX
    bs.offsetY = (f("offsetY") or 0) + edgeY
    -- Stage 5 (plan §5.6 "Static push"): Show Empty Bar When Missing and the
    -- ONE push toggle the bar's Direction + anchor edge call for -- the same
    -- rule the options page uses to show it (barPushKey,
    -- Pages_SingleBuffVisuals.lua): vertical -> Push Auras Aside on a LEFT /
    -- RIGHT edge; horizontal -> Place Auras Above on a BOTTOM edge, Place
    -- Auras Below on a TOP edge. Frame-positioned bars only, and a push only
    -- while the empty bar is on. pushEdge = "BOTTOM" / "TOP" / "LEFT" /
    -- "RIGHT", the edge whose displays move inward to clear the bar.
    bs.emptyBar = (not bs.flow) and f("showEmptyBar") == true
    if bs.emptyBar and type(anchor) == "string" then
        if vertical then
            if f("pushAurasAside") == true then
                if anchor:find("LEFT") then bs.pushEdge = "LEFT"
                elseif anchor:find("RIGHT") then bs.pushEdge = "RIGHT" end
            end
        elseif anchor:find("BOTTOM") then
            if f("placeAurasAbove") == true then bs.pushEdge = "BOTTOM" end
        elseif anchor:find("TOP") then
            if f("placeAurasBelow") == true then bs.pushEdge = "TOP" end
        end
    end
    -- Size: stored fractions, else the Direction's default (100% x 5%
    -- horizontal, 5% x 100% vertical -- the options panel's barWidth/Height).
    local wp = f("widthPct");  if wp == nil then wp = vertical and 0.05 or 1.0 end
    local hp = f("heightPct"); if hp == nil then hp = vertical and 1.0 or 0.05 end
    local cw, ch = parent and parent._bf_contentW, parent and parent._bf_contentH
    if not (cw and ch) and parent and BF.ComputeFrameContentSize then
        cw, ch = BF.ComputeFrameContentSize(parent)
    end
    if cw and ch then
        local minPx = BF.PixelsToUI and BF:PixelsToUI(1) or 1
        local w = BF:PixelRound(cw * wp)
        local h = BF:PixelRound(ch * hp)
        -- Never past the border: at most the rect inside it (see above).
        local maxW, maxH = cw - halfPx * 2, ch - halfPx * 2
        if w > maxW then w = maxW end
        if h > maxH then h = maxH end
        bs.w = (w > minPx) and w or minPx
        bs.h = (h > minPx) and h or minPx
    end
    -- Texture: the frame's ACTIVE Layout health bar texture (resolved exactly
    -- as HealthBar.lua resolves it), or the picked statusbar texture.
    if f("useHealthTexture") ~= false then
        local hpP = parent and BF.GetSectionProfileForFrame
            and BF:GetSectionProfileForFrame("healthPower", parent)
        bs.texture = (hpP and hpP.useCustomHealthBarTexture
            and BF:ResolveBarTexture(hpP.healthBarTexture)) or BAR_WHITE
    else
        bs.texture = BF:ResolveBarTexture(f("texture") or "Solid")
    end
    bs.color       = BarColor(f("color"), 0.24, 1.0, 0.25, 1.0)
    bs.bgColor     = BarColor(f("backgroundColor"), 0, 0, 0, 0.5)
    -- Owner ruling 2026-10-13: Show Empty Bar When Missing forces Whole Bar
    -- (the empty bar's background spans the whole bar; "Unfilled Part" is
    -- hidden in the options while it is on). The stored choice is untouched.
    bs.bgWhole     = bs.emptyBar or f("backgroundCovers") ~= "UNFILLED"
    bs.reverseFill = f("reverseFill") == true
    bs.border          = f("borderStyle") == "flat"
    bs.borderThickness = f("borderThickness") or 1
    bs.borderColor     = BarColor(f("borderColor"), 0, 0, 0, 1)
    bs.pandemic        = f("pandemic") == true
    bs.pandemicColor   = BarColor(f("pandemicColor"), 0.239216, 1, 0.254902, 0.15)
    -- Review item B1: Apply to Background. Off = the tint covers the filled
    -- part only (the fill-anchored overlay); on = the whole bar.
    bs.pandemicBg      = f("pandemicBackground") == true
    -- SetDurationBar options (plan §4.1): Drain = RemainingTime, Fill =
    -- ElapsedTime; Smooth Fill = the eased interpolation (applies to in-place
    -- updates only -- the engine forces Immediate on assignment). Numeric
    -- fallbacks are Grid2's literals (IndicatorBarAura: direction elapsed 0 /
    -- remaining 1; interpolation smooth 1).
    local dirE = Enum and Enum.StatusBarTimerDirection
    if f("fillMode") == "FILL" then
        bs.direction = (dirE and dirE.ElapsedTime) or 0
    else
        bs.direction = (dirE and dirE.RemainingTime) or 1
    end
    -- Smooth Fill is ON by default (owner, 2026-10-14): only an explicit
    -- false turns it off, so a bar that never set it picks the eased
    -- interpolation up on its next Layout -- bs.interpolation feeds
    -- SpellBarBindKey, which every bind guard compares.
    local intE = Enum and Enum.StatusBarInterpolation
    if f("smoothFill") ~= false then
        bs.interpolation = (intE and intE.ExponentialEaseOut) or 1
    else
        bs.interpolation = (intE and intE.Immediate) or 0
    end
    return bs
end

-- ============================================================
-- Per-spell BORDER SHAPE override (v87).
-- Returns the specSpellSolidIcons entry that carries the shared
-- border fields (useBuffsBorder / showBorder / borderStyle /
-- borderThickness), or nil when none is configured.
--
-- Unlike GetSolidIconColor this IGNORES the entry's `enabled`
-- flag: `enabled == false` only means the SOLID COLOR (Square
-- fill) is off — it is set false whenever the icon type is Icon
-- (the icon-type setter, Options_AuraCustomizations.lua). The
-- border fields on that same entry stay valid for an Icon-type
-- buff, which is exactly the case this accessor serves. The
-- render side (DeriveSpellButtonSpec) reads it ONLY on the Icon
-- path, so it never competes with the Square path's own read.
-- ============================================================
local function GetSpellBorderShape(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        return SBEntry(sbC, "specSpellSolidIcons", spellId)
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local si = p and p.specSpellSolidIcons and p.specSpellSolidIcons[specId]
    return si and si[spellId]
end
BF.GetSpellBorderShape = GetSpellBorderShape

-- Resolve "Use Buffs Border" for a border-shape entry (v87). Stored as an
-- explicit boolean once the user touches it; when ABSENT the default is
-- per-type: Icon inherits the container border (true), Square draws its own
-- (false, preserving the pre-v87 bare square). The options side
-- (Options_AuraCustomizations.lua useBuffsBorderOn) resolves identically —
-- keep the two in lockstep.
local function UseBuffsBorderOn(entry, isSquare)
    local v = entry and entry.useBuffsBorder
    if v == true then return true end
    if v == false then return false end
    return not isSquare
end
BF.UseBuffsBorderOn = UseBuffsBorderOn

-- ============================================================
-- SOLID ICON COLOR CURVE (remaining-time thresholds)
-- Builds and caches a Step color curve per spellId from the
-- threshold settings in specSpellSolidIcons. Returns the curve
-- object or nil if thresholds are not enabled.
--
-- Grid2 pattern (IndicatorIcon.lua): Step curve with AddPoint
-- at each threshold. Evaluated via EvaluateRemainingDuration.
-- ============================================================
BF._solidIconColorCurveCache = BF._solidIconColorCurveCache or {}

local function GetSolidIconColorCurve(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    local entry, cacheKey
    if sbC then
        entry    = SBEntry(sbC, "specSpellSolidIcons", spellId)
        -- Per-ENTRY cache key: two single buffs of one spell may hold different
        -- threshold colors, and the spellId-keyed cache would alias them.
        cacheKey = "sb:" .. tostring(sbC.singleBuffKey) .. ":" .. spellId
    else
        local specId = BF.playerSpecID
        if not specId then return nil end
        if not IsCust(specId, spellId) then return nil end
        local p = BF.acDB and BF.acDB.profile
        local si = p and p.specSpellSolidIcons and p.specSpellSolidIcons[specId]
        entry    = si and si[spellId]
        cacheKey = spellId
    end
    if not entry or entry.enabled == false or not entry.thresholdEnabled then return nil end

    local t1 = entry.thresholdSecs or 8
    local t2Enabled = entry.secondaryEnabled
    local t2 = entry.secondarySecs or 4
    -- 2026-09-11: the key is the curve's INPUTS, not just the entry, so the
    -- function is pure like BuildThresholdColorCurve (Auras/AuraConfig.lua):
    -- a settings edit mints a new key, unchanged settings return the SAME
    -- object -- and nothing ever needs to wipe this cache. It used to be
    -- wiped wholesale by RefreshAllCustomContainersWithRebuild in the load
    -- tail, so the first Layout after load saw a fresh curve address for
    -- identical settings; ButtonSpecSig / the style snapshot compare curves
    -- by identity, and inside a keystone that miss is a rebuilt container.
    cacheKey = cacheKey .. "|" .. tostring(t1) .. "|" .. tostring(t2Enabled and true or false)
        .. "|" .. tostring(t2)
        .. "|" .. tostring(entry.r) .. "," .. tostring(entry.g) .. "," .. tostring(entry.b) .. "," .. tostring(entry.a)
        .. "|" .. tostring(entry.thresholdR) .. "," .. tostring(entry.thresholdG) .. "," .. tostring(entry.thresholdB) .. "," .. tostring(entry.thresholdA)
        .. "|" .. tostring(entry.secondaryR) .. "," .. tostring(entry.secondaryG) .. "," .. tostring(entry.secondaryB) .. "," .. tostring(entry.secondaryA)

    -- Return cached curve if available
    local cache = BF._solidIconColorCurveCache
    if cache[cacheKey] then return cache[cacheKey] end

    -- Build step curve directly (Grid2 IndicatorIcon.lua pattern).
    -- Can't reuse BuildThresholdColorCurve because it hardcodes alpha=1
    -- for the above-threshold color, but solid icon color needs to
    -- preserve the user's Icon Color alpha on every poll tick.
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then return nil end
    -- Bounded: a color-picker drag can mint many distinct keys.
    local n = 0
    for _ in pairs(cache) do n = n + 1; if n > 256 then table.wipe(cache); break end end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    if t2Enabled and t2 < t1 then
        curve:AddPoint(0,  CreateColor(entry.secondaryR or 1, entry.secondaryG or 0, entry.secondaryB or 0, entry.secondaryA or 1))
        curve:AddPoint(t2, CreateColor(entry.thresholdR or 1, entry.thresholdG or 0.5, entry.thresholdB or 0, entry.thresholdA or 1))
        curve:AddPoint(t1, CreateColor(entry.r or 0, entry.g or 0.7, entry.b or 1, entry.a or 1))
    else
        curve:AddPoint(0,  CreateColor(entry.thresholdR or 1, entry.thresholdG or 0.5, entry.thresholdB or 0, entry.thresholdA or 1))
        curve:AddPoint(t1, CreateColor(entry.r or 0, entry.g or 0.7, entry.b or 1, entry.a or 1))
    end
    if curve then cache[cacheKey] = curve end
    return curve
end
BF.GetSolidIconColorCurve = GetSolidIconColorCurve

-- ============================================================
-- PER-SPELL COOLDOWN TEXT OVERRIDE
-- Returns the per-spell cooldown text settings table for a spellId,
-- or nil if no override is configured (enabled == false or absent).
--
-- When the entry has separateGroupConfig == true and a groupTypeKey
-- is provided, the returned table is the group-type-specific
-- sub-table (with fallback reads delegated to the caller).
-- The raw entry is always available as the second return value so
-- callers can implement field-level fallback (gs field → entry field).
--
-- Storage: acDB.profile.specSpellCooldownText[specId][spellId]
-- ============================================================
local function GetSpellCooldownText(spellId, groupTypeKey, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil, nil end
    local entry
    if sbC then
        entry = SBEntry(sbC, "specSpellCooldownText", spellId)
    else
        local specId = BF.playerSpecID
        if not specId then return nil, nil end
        if not IsCust(specId, spellId) then return nil, nil end
        local p = BF.acDB and BF.acDB.profile
        local ct = p and p.specSpellCooldownText and p.specSpellCooldownText[specId]
        entry = ct and ct[spellId]
    end
    if not entry then return nil, nil end
    -- Per-layout resolution: when separateGroupConfig is on, the enabled
    -- flag lives on the groupSettings sub-table, not on the entry itself.
    if entry.separateGroupConfig and groupTypeKey then
        local gs = entry.groupSettings and entry.groupSettings[groupTypeKey]
        if not gs or gs.enabled == false then return nil, nil end
        return gs, entry
    end
    -- Global (non-per-layout): check entry.enabled
    if entry.enabled == false then return nil, nil end
    return entry, entry
end
BF.GetSpellCooldownText = GetSpellCooldownText

-- ============================================================
-- v84 (Stage 5 §9.9) PER-SPELL ICON EFFECT
-- Returns the per-spell Icon Effects settings table for a spellId, or nil
-- when nothing is configured.
--
-- Storage: acDB.profile.specSpellIconEffect[specId][spellId]
-- Entry shape:
--   { effect    = "none"|"glow"|"ants"|"flash",
--     glowStyle = "steady"|"pulse",          -- glow only
--     color     = { r, g, b, a },            -- Effect Color
--     pandemic  = boolean, pandemicColor = { r, g, b, a },
--     desaturate = boolean,
--     recolor   = boolean, recolorColor = { r, g, b, a } }
--
-- Same shape and same gates as the retired per-spell Expiration Glow
-- resolver it replaced (removed with ExpirationGlow.lua):
-- single hash lookup on the hot path, the master customize flag applies to
-- curated spec spells, and `sbC` (a single-buff container) routes to that
-- entry's own store where neither the spec nor the flag exists.
-- ============================================================
local function GetSpellIconEffect(spellId, sbC)
    if not spellId or not canaccessvalue(spellId) then return nil end
    if sbC then
        local e = SBEntry(sbC, "specSpellIconEffect", spellId)
        if not e or e.enabled == false then return nil end
        return e
    end
    local specId = BF.playerSpecID
    if not specId then return nil end
    if not IsCust(specId, spellId) then return nil end
    local p = BF.acDB and BF.acDB.profile
    local sg = p and p.specSpellIconEffect and p.specSpellIconEffect[specId]
    local entry = sg and sg[spellId]
    if not entry or entry.enabled == false then return nil end
    return entry
end
BF.GetSpellIconEffect = GetSpellIconEffect

-- Fold a resolved Icon Effects entry onto a button spec. One place, so the
-- live container path, the single-buff slot path and the preview painters
-- cannot drift apart on what a stored entry means.
--
-- SINGLE PASS by contract: resolve everything, apply once at the tail. A
-- teardown-then-reapply restarts the animations visibly.
function BF.ApplyIconEffectToSpec(spec, e)
    if not (spec and e) then return end
    local fx = e.effect
    local c  = e.color
    if fx == "glow" then
        -- Glow rides the existing presence-glow ring (spec.showGlow), so one
        -- owner draws it; glowPulse picks Steady vs Pulsing.
        spec.showGlow  = true
        spec.glowPulse = (e.glowStyle == "pulse")
        spec.glowColor = c and { c.r or 1, c.g or 0.82, c.b or 0.25, c.a or 1 }
            or { 1, 0.82, 0.25, 1 }
    elseif fx == "ants" or fx == "flash" then
        spec.iconEffect = fx
        spec.iconEffectColor = c and { c.r or 1, c.g or 0.82, c.b or 0.25, c.a or 1 }
            or { 1, 0.82, 0.25, 1 }
    end
    if e.desaturate then spec.iconDesaturate = true end
    if e.recolor then
        spec.iconRecolor = true
        spec.iconRecolorColor = e.recolorColor
    end
    if e.pandemic then
        spec.pandemic = true
        -- v92: COPY, never alias. `spec` is retained (it is the button spec the
        -- container keeps and re-signs), while `e` may be a resolver's return --
        -- BF:ResolveContainerIconEffect hands back an INTERNED default table
        -- when the container leaves Pandemic Color unset, so aliasing would put
        -- one shared table on every such spec. Every other color here is
        -- already built fresh; this was the one that was not.
        --
        -- RECORD shape {r,g,b,a}, not the array shape used for glowColor /
        -- iconEffectColor: both consumers read it by field name --
        -- ContainerFactory's pandemic texture applier (pc.r/g/b/a) and
        -- ButtonSpecSig's pandemic fold. The `or` defaults are that applier's,
        -- restated so a sparse stored color signs and paints identically.
        local pc = e.pandemicColor
        spec.pandemicColor = {
            r = pc and pc.r or 0.239216,
            g = pc and pc.g or 1,
            b = pc and pc.b or 0.254902,
            a = pc and pc.a or 0.15,
        }
    end
end

-- ============================================================
-- PER-SPELL BOUNCE (REMOVED)
--
-- v66: bounce does nothing on 12.1 -- the engine owns the icon's position, so
-- the animation has nothing to move. Its options are hidden there, and the
-- runtime getter was reduced to an unconditional `return nil` gate.
--
-- v67: BF.GetSpellBounce / BF.ResolveSpellBounce removed with the 12.0.7
-- client. Storage (acDB.profile.specSpellBounce[specId][spellId], entry shape
-- { enabled?, threshold = <secs>, showMode = "always"|"threshold" }) is left
-- untouched in saved variables. Restoring the feature means restoring the
-- getter here plus the sbC / curated lookups the other getters above model.
-- ============================================================
