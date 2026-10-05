--[[
BuzzardFrames: Indicators/NameText.lua
Name text indicator — mirrors Grid2's IndicatorText.lua pattern.

Creates a FontString on each frame, positions it per profile settings,
and updates it from UnitName.

Each call to Update unconditionally overwrites stale state (Grid2 pattern).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitClass           = UnitClass
local UnitIsAFK           = UnitIsAFK
local issecretvalue       = issecretvalue or function() return false end
local canaccessvalue      = canaccessvalue or function() return true end

-- Grid2 pattern (GridUtils.lua strcututf8): UTF-8 safe string truncation.
-- Counts characters (not bytes) so multi-byte characters are never split.
local strbyte = string.byte
local function strcututf8(s, c)
    if issecretvalue(s) then return s end
    local l, i = #s, 1
    while c > 0 and i <= l do
        local b = strbyte(s, i)
        if     b < 192 then i = i + 1
        elseif b < 224 then i = i + 2
        elseif b < 240 then i = i + 3
        else                i = i + 4
        end
        c = c - 1
    end
    return s:sub(1, i - 1)
end

-- Grid2 pattern: count UTF-8 characters (not bytes).
local function strlenutf8(s)
    if issecretvalue(s) then return 0 end
    local l, i, count = #s, 1, 0
    while i <= l do
        local b = strbyte(s, i)
        if     b < 192 then i = i + 1
        elseif b < 224 then i = i + 2
        elseif b < 240 then i = i + 3
        else                i = i + 4
        end
        count = count + 1
    end
    return count
end

local NameText = BF.indicatorPrototype:new("nameText")

-- ============================================================
-- Create
-- ============================================================
function NameText:Create(parent)
	-- Skip if already created by legacy InitFrame
	if parent.nameText then
		parent[self.name] = parent.nameText
		return
	end

	-- Parent to a clip frame anchored to the health bar so long names
	-- don't overflow the frame edges.
	local textFrame = parent.textFrame
	if not textFrame then
		textFrame = CreateFrame("Frame", nil, parent)
		textFrame:SetAllPoints(parent)
		textFrame:SetFrameLevel(parent:GetFrameLevel() + 216)
		textFrame:EnableMouse(false)
		parent.textFrame = textFrame
	end

	local hBar = parent.healthBar
	local clipParent = textFrame
	if hBar then
		local nameClip = parent.nameClip
		if not nameClip then
			nameClip = CreateFrame("Frame", nil, textFrame)
			nameClip:SetAllPoints(parent.container or hBar)
			nameClip:SetFrameLevel(parent:GetFrameLevel() + 217)
			nameClip:EnableMouse(false)
			nameClip:SetClipsChildren(true)
			parent.nameClip = nameClip
		end
		clipParent = nameClip
	end

	local fs = clipParent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(GameFontNormalSmall)
	local defaultFont, defaultSize, defaultFlags = fs:GetFont()
	defaultFont = defaultFont or BF.font or "Fonts\\FRIZQT__.TTF"
	defaultSize = defaultSize or 10
	defaultFlags = defaultFlags or ""
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs.SF_defaultFont  = defaultFont
	fs.SF_defaultSize  = defaultSize
	fs.SF_defaultFlags = defaultFlags
	fs:SetJustifyH("CENTER")
	fs:SetWordWrap(false)

	if hBar then
		local anchor = parent.container or hBar
		fs:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	else
		fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
	end

	parent[self.name] = fs
	parent.nameText = fs  -- backward compat alias
end

-- ============================================================
-- Resolved config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded, into
-- a block the indicator holds (modules/IndicatorText.lua:251), and Layout then
-- writes that block with no decisions left in it (:106). The fallback chain is
-- baked in at RESOLVE time, which is why Layout needs no
-- `if not tp then return end` -- the block handed to it is always complete.
-- See BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- This file already argued the scope-keyed half of that shape, for the UPDATE
-- side: Name:GetComposed (BFStatus.lua:993-1062) memoizes a composed entry per
-- SECTION TABLE, weak-keyed, because "Frames sharing a flat share one entry;
-- CFG flats get their own". This is the same idea applied to the LAYOUT side,
-- with the generation key added -- see below for why that is not optional.
--
-- ── THREE SECTIONS, SO THREE KEY LEVELS ─────────────────────────────────────
-- Unlike its neighbors, this indicator's Layout reads text, icons AND borders:
-- the name's x offset depends on the role icon's position and size, and its
-- width depends on the border thickness. A single-table key would be WRONG
-- here. Per-Layout toggles are per SECTION, so two flats can share one `text`
-- table (both toggled off, both resolving to the global) while differing in
-- `icons` -- same tp, different ip, and a tp-keyed block would hand the second
-- scope the first scope's role-icon offsets. The cache is therefore nested
-- tp -> ip -> bp, each level weak-keyed. Cost is two extra table reads on a
-- path that runs at build and on forced reloads, not per tick (plan §7).
--
-- WEAK KEYS, and the generation key, cover the two lifetimes a section table
-- can have. A per-Layout or per-CFG section resolves to a MERGED VIEW allocated
-- by BuildMergedSectionView and cached at flat._sectionCache[section]
-- (Core_ProfileAPI.lua:1187-1189); invalidation drops that cache, so the next
-- resolve mints a NEW table and a strong key would pin the dead one for the
-- session. The degenerate paths return rpDB.profile[section] itself -- a
-- long-lived AceDB table the options UI mutates IN PLACE (BFStatus.lua:999-1001),
-- whose identity never changes on an edit. Keying on the tables alone would
-- never notice those edits; that is what the generation key is for.
local _blockCacheMeta = { __mode = "k" }

-- Scope key for "no section profile resolvable for this frame". A table, so it
-- can never collide with a real section table.
local _NO_SECTION = {}

-- Fallbacks for the two position tables this indicator reads. _DEFAULT_NAME_POS
-- reproduces what :Create anchors with (:104-109) rather than inventing a
-- position: it is reached only on a profile that has a `text` section but no
-- namePosition key, which the shipped defaults never produce
-- (Defaults_RaidPartyFrames.lua:957). _DEFAULT_ROLE_POS is the literal this
-- file already used inline -- note it is NOT the same as the shipped default
-- (Defaults_RaidPartyFrames.lua:895 is x=1, y=-1); the inline value is kept
-- byte-for-byte so the offsets it feeds cannot shift.
local _DEFAULT_NAME_POS = { point = "CENTER",  x = 0, y = 0 }
local _DEFAULT_ROLE_POS = { point = "TOPLEFT", x = 2, y = -2 }

-- PUBLISHED, not copied. RoleIcon's AdjustNameForHiddenRole re-derives this
-- indicator's anchor from the same two tables (Indicators/RoleIcon.lua:84-107)
-- and must fall back IDENTICALLY, or on a profile missing namePosition the two
-- disagree about where the name sits -- one of them positioning it and the
-- other declining to. Carry-over 1 of the 2026-09-21 indicator work: RoleIcon
-- reads these rather than keeping its own literals, so there is one source of
-- truth and no drift. Load order is guaranteed by BuzzardFrames.toc
-- (NameText.lua:122 before RoleIcon.lua:127).
BF.NAMEPOS_FALLBACK = _DEFAULT_NAME_POS
BF.ROLEPOS_FALLBACK = _DEFAULT_ROLE_POS

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Implements the hook declared at BFIndicator.lua:62, dispatched by
-- BF:RefreshIndicatorSettings (BFIndicator.lua:332) from LoadLayout on every
-- profile/context switch. Drops the resolved blocks so the next Layout
-- re-resolves.
--
-- The PUSH half only, and an optimization rather than the correctness
-- guarantee: the generation key in ResolveNameTextBlock is what makes staleness
-- impossible on the paths that reach indicator:Layout without ever reaching
-- RefreshIndicatorSettings (plan §6.1(b)).
function NameText:UpdateSettings()
	self._cfgBlocks = nil
end

-- One weak-keyed level of the nested cache.
local function _SubCache(t, k)
	local v = t[k]
	if v == nil then
		v = setmetatable({}, _blockCacheMeta)
		t[k] = v
	end
	return v
end

-- Resolve (or reuse) this frame's block. Declared ABOVE NameText:Layout on
-- purpose: a Lua local is only in scope after its declaration, so a resolver
-- placed below its caller compiles to a nil global lookup and throws only on
-- the path that reaches it. Tests/check_locals.py exists for that.
local function ResolveNameTextBlock(parent)
	-- Route by frame: preview frames resolve to their own flat (via
	-- parent._flatID) so the options preview reflects per-layout edits; live
	-- frames resolve via active game context. See BF:GetSectionProfileForFrame.
	local tp = BF:GetSectionProfileForFrame("text", parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	local bp = BF:GetSectionProfileForFrame("borders", parent)

	-- GENERATION KEY. BF._sectionCfgGen is bumped by InvalidateRaidProfileCache
	-- (Core_ProfileAPI.lua:639) and _InvalidateSectionViews (:992), which every config-changing
	-- path is REQUIRED to pass through. That is an invariant to KEEP, not an
	-- observation that holds by itself: on 2026-09-23 four writers were found
	-- that reached neither bump site -- the Global Styles text, icons and
	-- borders fan-outs (BuzzardFramesOptions/Pages_GlobalStylesShared.lua) and
	-- the Cast Bars page (Pages_CastBar.lua) -- and each was given the
	-- invalidation it was missing. All four assign into the EXISTING section
	-- table, so the scope key does not move either and the block below froze
	-- with no error of any kind. A new config writer that reaches neither does
	-- exactly the same thing. Existing in-tree pattern: HealthText
	-- stamps parent._bf_htCfgGen (Indicators/HealthText.lua:129) and re-resolves
	-- when it differs from BF._sectionCfgGen (:417). Re-resolving on a moved
	-- generation is what lets Layout write unconditionally without depending on
	-- anyone having remembered to call UpdateSettings first.
	local gen = BF._sectionCfgGen or 0

	local root = NameText._cfgBlocks
	if root == nil then
		root = setmetatable({}, _blockCacheMeta)
		NameText._cfgBlocks = root
	end
	local leaf = _SubCache(_SubCache(root, tp or _NO_SECTION), ip or _NO_SECTION)
	local bkey = bp or _NO_SECTION

	local block = leaf[bkey]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		leaf[bkey] = block
	end
	block.gen = gen

	-- DEFAULT CHAIN, spelled out literally rather than read off the FontString.
	-- The block is shared by every frame in this scope, so it must not depend on
	-- per-FontString state: fs.SF_defaultFont / SF_defaultSize / SF_defaultFlags
	-- are what the old Layout read, and that read is what made the resolution
	-- per-frame. Dropping it is safe because :Create stamps those three fields on
	-- EVERY nameText it builds, from this same chain (:92-100). BF.font is a
	-- file-scope constant (Core.lua:87), never reassigned, so resolving it here
	-- rather than at Create time cannot diverge. SF_defaultFont is still read in
	-- Layout, by the two-step SetFont -- that one is a genuine per-widget concern
	-- (it needs any font DIFFERENT from the one being set) and stays there.
	local baseFont, baseSize, baseFlags
	if GameFontNormalSmall then
		baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
	end
	baseFont  = baseFont  or BF.font or "Fonts\\FRIZQT__.TTF"
	baseSize  = baseSize  or 10
	baseFlags = baseFlags or ""

	-- adjustNameFont semantics unchanged: ON takes the configured face and
	-- border, OFF takes the default triple whole. BF:ResolveFontPath
	-- (PixelPerfect.lua:656) always returns a path, so fontPath is never nil.
	--
	-- ONE DELIBERATE DELTA: the size gets `or baseSize`. The old code assigned
	-- `cfgSize = tp.nameFontSize` bare, so a profile with adjustNameFont ON and
	-- nameFontSize absent threw inside SetFont. A block that is "complete and
	-- usable" is the point of resolving here (plan §2, property 3), and an
	-- incomplete one cannot be written unconditionally, so the hole is filled
	-- with the same default :Create uses. Behavior is identical wherever the size
	-- is set, which the shipped defaults always do.
	if tp and tp.adjustNameFont then
		block.fontPath  = BF:ResolveFontPath(tp.nameFont)
		block.fontSize  = tp.nameFontSize or baseSize
		block.fontFlags = tp.nameFontBorder or ""
	else
		block.fontPath  = baseFont
		block.fontSize  = baseSize
		block.fontFlags = baseFlags
	end

	-- ANCHOR. The role-icon offset below is pure config arithmetic -- it depends
	-- only on the name point, the role icon's point/x/size and the global
	-- showRoleIcons toggle -- so it is resolved once per scope here instead of
	-- once per frame in Layout. What stays in Layout is the per-FRAME half:
	-- which widget to anchor TO, and the hidden-role correction for units whose
	-- icon ended up hidden (parent._roleIconNameAdjusted).
	local np = (tp and tp.namePosition) or _DEFAULT_NAME_POS
	local rp = (ip and ip.roleIconPosition) or _DEFAULT_ROLE_POS
	block.link = (tp and tp.linkNameAndRole) and true or false

	local nameX = np.x or 0
	local nameY = np.y or 0
	-- Compared RAW, exactly as before. What makes that safe is the FALLBACK
	-- TABLES, not the comparison: _DEFAULT_NAME_POS and _DEFAULT_ROLE_POS both
	-- carry a `point` (:165-166), so neither side can be nil here. An earlier
	-- draft claimed a nil np.point "matches no rp.point" -- false when both are
	-- nil, since nil == nil is true and np.point:find below would then throw.
	-- Unreachable today; stated so the fallbacks are understood as load-bearing.
	if ip and ip.showRoleIcons then
		-- Default to the icon-visible offset when the global toggle is on.
		-- RoleIcon:Update corrects it with AdjustNameForHiddenRole for units
		-- where the icon ends up hidden (per-role filter, NONE role, etc.).
		if np.point == rp.point then
			local rpX = rp.x or 0
			if np.point:find("LEFT") then nameX = nameX + (ip.roleIconSize or 12) + 1 + rpX
			elseif np.point:find("RIGHT") then nameX = nameX - (ip.roleIconSize or 12) - 1 + rpX end
		end
	else
		-- Role icons globally off: small inset so the name is not flush with the
		-- frame edge.
		if np.point == rp.point then
			if np.point:find("LEFT") then nameX = nameX + 3
			elseif np.point:find("RIGHT") then nameX = nameX - 3 end
		end
	end
	block.nameX = nameX
	block.nameY = nameY

	local anchorPoint = np.point or "CENTER"
	local vAnchor
	if anchorPoint:find("TOP") then vAnchor = "TOP"
	elseif anchorPoint:find("BOTTOM") then vAnchor = "BOTTOM"
	else vAnchor = "" end
	block.pinPoint = vAnchor ~= "" and (vAnchor .. "LEFT") or "LEFT"

	if anchorPoint:find("TOP") then block.justV = "TOP"
	elseif anchorPoint:find("BOTTOM") then block.justV = "BOTTOM"
	else block.justV = "MIDDLE" end

	if anchorPoint:find("LEFT") then block.justH = "LEFT"
	elseif anchorPoint:find("RIGHT") then block.justH = "RIGHT"
	else block.justH = "CENTER" end

	-- Border thickness in PIXELS only. The pixels-to-UI conversion stays in
	-- Layout on purpose: BF:PixelsToUI multiplies by pixelMult
	-- (PixelPerfect.lua:100-103), a screen/UI-scale value refreshed by
	-- RefreshPixelSize, and a resolution or UI-scale change does NOT bump
	-- BF._sectionCfgGen. Caching the converted value here would survive such a
	-- change and silently mis-size every name.
	block.borderN = BF:EffectiveBorderPixels(bp)

	return block
end

-- ============================================================
-- Layout
-- ============================================================
function NameText:Layout(parent)
	local fs = parent[self.name]
	if not fs then return end

	-- Route by frame: preview frames resolve to their own flat (set via
	-- parent._flatID) so the options preview reflects per-layout edits;
	-- live frames resolve via active game context, matching NameText:Update.
	-- See BF:GetSectionProfileForFrame for the full breakdown.
	-- The two config guards that used to stand here -- `if not tp then return
	-- end` and `if not tp.namePosition then return end` -- are GONE. Both were
	-- "do we have config" tests, and after ResolveNameTextBlock there is no such
	-- question left: the block is complete even when no section resolves. Their
	-- removal also means the nameClip re-anchor below now runs on every Layout
	-- unconditionally, which is what its own comment says it must.
	local block = ResolveNameTextBlock(parent)
	local hBar  = parent.healthBar

	-- Re-assert the clip frame's anchoring on EVERY Layout. nameClip was
	-- previously anchored exactly once, at Create — against a container
	-- texture that had no anchors yet (Container:Layout runs later), under
	-- a hidden, unpositioned header at login. With SetClipsChildren(true), a
	-- clip rect resolved in that window can clip a perfectly painted name to
	-- nothing, and NO code path ever re-anchored it on a live frame — which
	-- is why every FontString-side fix failed for the affected user while
	-- merely MOVING the frames (a pure engine re-anchor of the ancestry)
	-- healed it. ClearAllPoints+SetAllPoints forces the engine to rebuild
	-- the clip rect from current geometry each time Layout runs (build,
	-- OnUnitChanged, LoadLayout deferred tail, resize).
	local nameClip = parent.nameClip
	if nameClip then
		nameClip:ClearAllPoints()
		nameClip:SetAllPoints(parent.container or hBar or parent)
	end

	-- Font. Configured font is cached on the FontString itself (Grid2
	-- pattern: layout state lives on the indicator's own widgets, e.g.
	-- IndicatorText caches textlength on self). The old parent._nameFont*
	-- snapshots — replayed by Update on every paint — are GONE: that replay
	-- was the stale-state bug class this refactor exists to eliminate
	-- (plan D1). Update never touches font except the Cyrillic fallback,
	-- which reads these fs-scoped values.
	-- Resolved once per scope now, not once per frame -- see
	-- ResolveNameTextBlock. Written UNCONDITIONALLY (Grid2 Text_Layout): this
	-- function can no longer leave the widget on its Create-time font.
	fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)
	fs._cfgFontPath  = block.fontPath
	fs._cfgFontSize  = block.fontSize
	fs._cfgFontFlags = block.fontFlags

	-- Anchor. The offsets arrived resolved (role-icon arithmetic included);
	-- what is decided here is per-FRAME -- which widget to anchor to.
	if not block.link then
		fs:ClearAllPoints()
		local anchor = parent.container or hBar or parent
		fs:SetPoint(block.pinPoint, anchor, block.pinPoint, block.nameX, block.nameY)
		-- This unit's role icon is currently hidden (per-role filter,
		-- NONE role, pet frame): the icon-offset anchor above is wrong
		-- for it. Re-apply the hidden-role position now — RoleIcon only
		-- corrects on role/roster events, which don't follow a plain
		-- LayoutFrame sweep (e.g. border-color setters).
		if parent._roleIconNameAdjusted and BF.ReapplyHiddenRoleNameAdjust then
			BF:ReapplyHiddenRoleNameAdjust(parent)
		end
	end

	-- Width. Set ONLY here — Update never writes width (Grid2:
	-- IndicatorText.lua:130 sets width in layout, Text_SetText never
	-- does). Width persists on the FontString; SetText does not reset it.
	-- No parent._nameWidth snapshot: a build-time width pinned there and
	-- replayed per paint was the first-login invisible-name mechanism.
	-- Staleness is healed by re-running Layout on resize/profile changes
	-- (plan Phase 4), not by replaying a possibly-bad value forever.
	local header = parent:GetParent()
	local w = header and header.frameWidth or parent:GetWidth()
	-- EffectiveBorderPixels: rounded border styles use fixed 2/3px art
	-- thickness (must agree with Container:Layout's content inset).
	local borderN = block.borderN
	local borderUI = BF:PixelsToUI(borderN)
	local barW = w - borderUI * 2
	if barW > 0 then
		fs:SetWidth(barW)
	end
	fs:SetMaxLines(1)

	-- Justify
	fs:SetJustifyV(block.justV)

	-- CRITICAL WoW QUIRK: SetFont resets JustifyH to its default (LEFT).
	-- SetJustifyH must therefore come AFTER the final SetFont call.
	-- Additionally, WoW will silently no-op a SetFont call if the font
	-- path/size/flags haven't changed from the current values — meaning
	-- the JustifyH reset never fires, and the subsequent SetJustifyH call
	-- also fails to "stick" because WoW thinks nothing changed.
	-- The fix (same pattern used in refreshNameFont in Options_Text.lua):
	-- briefly switch to a DIFFERENT font first, then set the real font.
	-- This forces WoW to flush the render state and pick up the new
	-- JustifyH reliably. DO NOT remove this two-step SetFont pattern
	-- or JustifyH changes will silently stop working on preview frames
	-- (and potentially real frames too if the font hasn't changed).
	local fp = fs._cfgFontPath
	local fz = fs._cfgFontSize
	local ff = fs._cfgFontFlags or ""
	if fp and fz then
		local altFont = (fp == (fs.SF_defaultFont or "")) and "Fonts\\FRIZQT__.TTF" or (fs.SF_defaultFont or "Fonts\\FRIZQT__.TTF")
		fs:SetFont(altFont, fz, ff)
		fs:SetFont(fp, fz, ff)
	end

	fs:SetJustifyH(block.justH)
end

-- ============================================================
-- Update — Grid2 shape (IndicatorText.lua Text_OnUpdate/Text_SetText).
--
-- STATELESS: no snapshot replays, no per-paint option branching, no
-- geometry writes. Text options come from the composed entry memoized
-- per section-table (BFStatus.lua Name:GetComposed — Grid2's UpdateDB
-- closure swap adapted for BF's per-flat/CFG profile model). Geometry
-- and font live exclusively in Layout; a bad early paint is healed by
-- the next repaint instead of replaying captured state forever.
--
-- Deliberate BF features preserved on top of the Grid2 shape (each
-- config-gated, off by default unless noted):
--   * per-frame pet-name semantics (pet header shows pet name; the same
--     pet token on a main header — vehicle swap — shows the owner)
--   * append-status-to-name handoff (StatusText_Overlay composes)
--   * reduced-max-health "(NN%)" append
--   * Cyrillic fallback font when transliteration is off
--   * showName visibility (owned HERE now; StatusText_Overlay no longer
--     hides the name — plan Phase 3)
-- ============================================================
-- Per-frame pet-header resolution, cached once per frame: a frame never
-- migrates between headers, so parent's header.isPetFrame is static.
-- Replaces the per-paint frames_of_unit scan (plan D5, review M11).
local function IsPetHeaderFrame(parent)
	local isPet = parent._bf_isPetHeader
	if isPet == nil then
		local header = parent:GetParent()
		isPet = (header and header.isPetFrame) and true or false
		parent._bf_isPetHeader = isPet
	end
	return isPet
end

-- Status-state resolution (BF append/color features). Offline and dead
-- are read from their status objects (cache reads, never the unit APIs);
-- the AFK read is secret-guarded and a secret state counts as "not AFK".
-- Shared by Update and UpdateColor.
local function ComputeStatusState(unit, entry)
	local offlineStatus = BF.statuses and BF.statuses.offline
	local deathStatus   = BF.statuses and BF.statuses.death
	local isOffline = offlineStatus and offlineStatus:IsActive(unit)
	local isDead    = deathStatus and deathStatus:IsActive(unit) or false
	local isAFK = false
	if entry.showAFK and UnitIsAFK then
		local afkVal = UnitIsAFK(unit)
		isAFK = canaccessvalue(afkVal) and afkVal == true
	end
	return isOffline or isDead or isAFK
end

-- ============================================================
-- Color companion — the SINGLE writer for nameText color/alpha
-- (Grid2 TextColor sidekick role, IndicatorText.lua:320-329).
--
-- Consolidates the three previous writers (plan 2.3/3.4, review M3):
--   * NameText's own base color (class/custom/white)
--   * LayoutFrame ApplyStatusColorToName (offline color + offline fade
--     alpha) — now a thin wrapper delegating here
--   * RangeAlpha's OOR text adjustments for the NAME (gray-blended
--     offline/dead colors, OOR alpha) — RangeAlpha keeps its
--     statusText-only writes and delegates the name here
--
-- Resolution order (deterministic; replaces the old trigger-order fights):
--   1. base: defer when a status state is active and
--      applyStatusColorsToNames is on (StatusText_Overlay paints the
--      status color); else class/custom/white, alpha 1
--   2. offline override: offline color (class variant), gray-blended
--      when out of range; alpha = offline fade
--   3. dead override: dead color only in append mode (as RangeAlpha
--      did), blended when OOR; alpha = deadColorOORFactor when OOR
--      (non-player), else 1
--   4. Swiftmend latch: suppresses ALL color writes (alpha still applies)
--   5. reduced-max append color override (Update path only)
--
-- OOR state reads the raw rangeCache exactly as RangeAlpha did: a secret
-- value counts as in-range (adjustments skipped), never branched on.
-- ============================================================
local function ApplyNameColor(parent, unit, fs, entry, inStatusState, nameStatus, reducedOverride)
	local hp = BF:GetCachedSection("healthPower", parent)

	-- OOR from the raw rangeCache. A SECRET value resolves to in-range: the
	-- plain (non-blended) outcomes are applied rather than skipping writes
	-- entirely — deterministic, and only non-secret values are ever written.
	local raw = BF.rangeCache and BF.rangeCache[unit]
	local oor = raw ~= nil and not issecretvalue(raw) and raw == false

	local r, g, b   -- nil = leave color untouched
	local alpha     -- nil = leave alpha untouched

	-- 1. Base. Defer in append mode too (review B1): in append mode the
	-- overlay owns the composed text's color (AFK/offline/dead tints), and
	-- there is no AFK override below to restore it — writing class/white here
	-- clobbered the AFK color on every range tick. Overrides still layer.
	if not (inStatusState and (entry.applyStatusColors or entry.append)) then
		alpha = 1
		if entry.adjustColors then
			if entry.classColor then
				r, g, b = nameStatus:GetClassColor(unit)
			end
			if not r then
				local nc = entry.nameColor
				if nc then
					r, g, b = nc.r, nc.g, nc.b
					-- v65: Name Color alpha channel — rides the same
					-- alpha slot the fade states use; the status alphas
					-- below still take precedence.
					alpha = nc.a or 1
				else r, g, b = 1, 1, 1 end
			end
		else
			r, g, b = 1, 1, 1
		end
	end

	-- 2. Offline handling. Offline-first precedence (review M3): a unit that
	-- died and then disconnected is still dead in the death cache, and
	-- painting dead color over an offline name is wrong — offline owns the
	-- frame, so it is tested first and the dead branch is the else.
	--
	-- Alpha: fade whenever the fade option is on (old ApplyStatusColorToName).
	-- Color: ONLY under applyStatusColorsToNames (review M1 — strict parity:
	-- the two live legacy writers both gated color on it; old RangeAlpha's
	-- ungated offline color write was unreachable dead code, cut off by its
	-- own offline early-return). The OOR gray-blend applies to that gated
	-- color, matching the fade option's documented OOR color retention.
	local deathStatus = BF.statuses and BF.statuses.death
	if parent._offline then
		if entry.fadeOfflineName and not (hp and hp.fadeOfflineFrames) then
			alpha = (hp and hp.rangeFadeAlpha) or 0.4
		end
		if inStatusState and entry.applyStatusColors then
			local _, cn = UnitClass(unit)
			-- 12.1: a secret class name is truthy but cannot index a table.
			if not canaccessvalue(cn) then cn = nil end
			local classColor = entry.offlineUseClass and cn and BF.classColors and BF.classColors[cn]
			local c = classColor or entry.offlineColor or { r=0.5, g=0.5, b=0.5 }
			local cr, cg, cb = c.r, c.g, c.b
			if oor then
				local f2 = hp and hp.deadColorOORFactor
				if f2 == nil then f2 = 0.5 end
				local gray = (cr + cg + cb) / 3
				cr = cr * f2 + gray * (1 - f2)
				cg = cg * f2 + gray * (1 - f2)
				cb = cb * f2 + gray * (1 - f2)
			end
			r, g, b = cr, cg, cb
		end
	elseif deathStatus and deathStatus:IsActive(unit) then
		-- 3. Dead override (RangeAlpha:161-181/:198-213). Name color only in
		-- append mode, exactly as RangeAlpha wrote it; alpha regardless.
		if entry.append then
			local _, cn = UnitClass(unit)
			-- 12.1: a secret class name is truthy but cannot index a table.
			if not canaccessvalue(cn) then cn = nil end
			local classColor = entry.deadUseClass and cn and BF.classColors and BF.classColors[cn]
			local c = classColor or entry.deadColor or { r=0.8, g=0.1, b=0.1 }
			local cr, cg, cb = c.r, c.g, c.b
			if oor then
				local f2 = hp and hp.deadColorOORFactor
				if f2 == nil then f2 = 0.5 end
				local gray = (cr + cg + cb) / 3
				cr = cr * f2 + gray * (1 - f2)
				cg = cg * f2 + gray * (1 - f2)
				cb = cb * f2 + gray * (1 - f2)
			end
			r, g, b = cr, cg, cb
		end
		if oor and unit ~= "player" then
			local f2 = hp and hp.deadColorOORFactor
			if f2 == nil then f2 = 0.5 end
			alpha = f2
		else
			alpha = 1
		end
	end

	-- 4. Swiftmend latch REMOVED: _bf_swiftmendNameActive was set only by
	-- BF:UpdateSwiftmendable, the pre-12.1 Lua recolor path. On 12.1 the name
	-- recolor is an engine-driven MIRROR FontString on the fxSM slot
	-- (BuffsAndContainers.lua, "nm" fx kind) laid OVER this one, so nothing
	-- here needs to yield the color any more.

	-- 5. Reduced-max append color (Update path only)
	if reducedOverride then
		r, g, b = reducedOverride.r, reducedOverride.g, reducedOverride.b
	end

	if r then fs:SetTextColor(r, g, b) end
	if alpha then fs:SetAlpha(alpha) end
end

function NameText:Update(parent, unit)
	local fs = parent[self.name]
	if not fs then return end

	-- Memoized section lookup (never caches nil, so this cannot latch —
	-- a nil tp here is re-resolved on the very next repaint).
	local tp = BF:GetCachedSection("text", parent)
	if not tp then return end

	local nameStatus = BF.statuses and BF.statuses.name
	if not unit or not nameStatus then return end

	local entry = nameStatus:GetComposed(tp)

	-- showName: visibility is owned here now (was StatusText_Overlay's
	-- nameText:Hide()). Default true; hidden frames are re-Shown by the
	-- next Update after the option is re-enabled (RefreshAllNames).
	if not entry.showName then
		fs:Hide()
		return
	end

	local inStatusState = ComputeStatusState(unit, entry)

	if inStatusState and entry.append then
		-- Append mode: StatusText_Overlay composes and owns "Name (Dead)"
		-- text + color. Non-blanking defer — the composed string stays.
		fs:Show()
		return
	end

	-- Resolve name unit: BF per-frame pet semantics (see header comment).
	local nameUnit = unit
	local owners = BF.owner_of_unit
	local owner = owners and owners[unit]
	if owner and not IsPetHeaderFrame(parent) then
		nameUnit = owner
	end

	local name = entry.getText(nameUnit)

	-- Secret name: pass straight through — every string op below is
	-- forbidden on secrets. getText composition is internally guarded.
	if issecretvalue(name) then
		fs:SetText(name)
		ApplyNameColor(parent, unit, fs, entry, inStatusState, nameStatus, nil)
		fs:Show()
		return
	end

	-- Cyrillic fallback font (BF feature): when transliteration is OFF
	-- and the name contains Cyrillic, swap to the fallback font; restore
	-- the configured font otherwise. Uses Layout's fs-scoped config cache
	-- — no parent snapshots.
	if name and BF.HasCyrillic and BF:HasCyrillic(name) then
		if not entry.translit then
			local fallback = BF.cyrillicFont or BF.font
			fs:SetFont(fallback, fs._cfgFontSize or 10, fs._cfgFontFlags or "")
		end
	elseif fs._cfgFontPath then
		fs:SetFont(fs._cfgFontPath, fs._cfgFontSize or 10, fs._cfgFontFlags or "")
	end

	-- Reduced-max-health append (BF feature; status bound conditionally
	-- in RebindAbsorbStatuses so _reducedMaxPct changes repaint us).
	local reducedOverride
	local ab = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.absorbs
	local rPct = parent._reducedMaxPct
	if ab and ab.showReducedMaxHealthText and ab.appendReducedMaxText
	   and ab.appendReducedMaxTarget == "name"
	   and rPct and not issecretvalue(rPct) and rPct > 0
	   and name then
		local remainPct = math.floor((1 - rPct) * 100 + 0.5)
		local label = string.format("%d%%", remainPct)
		if entry.append and BF.AppendStatus then
			name = BF.AppendStatus(name, label, parent)
		else
			name = name .. " (" .. label .. ")"
		end
		-- (parent._reducedMaxNameColor is no longer written: the override is
		-- passed directly to ApplyNameColor and the field has zero readers.)
		reducedOverride = ab.reducedMaxHealthTextColor
	end

	-- Truncate (Grid2 strcututf8 shape, gated on abbreviateNames — B3).
	if name and entry.maxChars and strlenutf8(name) > entry.maxChars then
		name = strcututf8(name, entry.maxChars)
	end

	-- Grid2 Text_SetText: unconditional write, empty string for nil.
	fs:SetText(name or "")

	ApplyNameColor(parent, unit, fs, entry, inStatusState, nameStatus, reducedOverride)
	fs:Show()
end

-- ============================================================
-- Public color-only entry point — the companion's external trigger.
-- Called by RangeAlpha on range flips and by BF:ApplyStatusColorToName
-- (thin wrapper) from the RefreshAll funnels. Recomputes and applies
-- color+alpha without touching text/visibility.
-- ============================================================
function NameText:UpdateColor(parent, unit)
	local fs = parent[self.name]
	if not fs then return end
	local tp = BF:GetCachedSection("text", parent)
	if not tp then return end
	local nameStatus = BF.statuses and BF.statuses.name
	if not unit or not nameStatus then return end
	local entry = nameStatus:GetComposed(tp)
	if not entry.showName then return end
	local inStatusState = ComputeStatusState(unit, entry)
	-- No append-mode early return here, deliberately: in append mode the
	-- overlay owns text + base color, but the offline/dead OOR overrides
	-- were always layered ON TOP by RangeAlpha (its dead name-color write
	-- was explicitly append-gated). ApplyNameColor reproduces that layering:
	-- base defers via applyStatusColors, overrides still apply.
	ApplyNameColor(parent, unit, fs, entry, inStatusState, nameStatus, nil)
end

BF:RegisterIndicator(NameText)
