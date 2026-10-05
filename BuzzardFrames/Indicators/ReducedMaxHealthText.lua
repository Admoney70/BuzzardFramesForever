--[[
BuzzardFrames: Indicators/ReducedMaxHealthText.lua
Temporary Reduced Max Health % text — shows the current max health
reduction percentage as a separate, independently positioned text element.

Reads parent._reducedMaxPct set by AbsorbBars:_UpdateReducedMaxHealth.
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitExists    = UnitExists
local issecretvalue = issecretvalue or function() return false end

local ReducedMaxHealthText = BF.indicatorPrototype:new("reducedMaxHealthText")

-- ============================================================
-- Create
-- ============================================================
function ReducedMaxHealthText:Create(parent)
	local textFrame = parent.textFrame
	if not textFrame then
		textFrame = CreateFrame("Frame", nil, parent)
		textFrame:SetAllPoints(parent)
		textFrame:SetFrameLevel(parent:GetFrameLevel() + 216)
		textFrame:EnableMouse(false)
		parent.textFrame = textFrame
	end

	local fs = textFrame:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(GameFontNormalSmall)
	local font, size, flags = fs:GetFont()
	font  = font  or BF.font or "Fonts\\FRIZQT__.TTF"
	size  = size  or 9
	flags = flags or ""
	fs.SF_defaultFont  = font
	fs.SF_defaultSize  = size
	fs.SF_defaultFlags = flags
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH("CENTER")
	fs:SetTextColor(1, 0.8, 0.2)
	fs:Hide()

	parent[self.name] = fs
	parent.reducedMaxHealthText = fs
end

-- ============================================================
-- Resolved config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded, into
-- a block the indicator holds (modules/IndicatorText.lua:251), and Layout then
-- writes that block with no decisions left in it (:106). The fallback chain is
-- baked in at RESOLVE time, which is why Layout needs no early return -- the
-- block handed to it is always complete. See
-- BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- NOTE THE SECTION: this indicator resolves "absorbs", not "text" like its
-- neighbors. Its settings live with the absorb bars because the same
-- reduced-max-health machinery feeds both (AbsorbBars:_UpdateReducedMaxHealth
-- writes parent._reducedMaxPct, which Update reads).
--
-- SCOPE KEY = THE SECTION TABLE ITSELF. Established in-tree pattern:
-- BFStatus.lua:993-1005 memoizes the composed name entry the same way,
-- weak-keyed -- "Frames sharing a flat share one entry; CFG flats get their
-- own." The active flat, each Custom Frame Group and each preview frame
-- resolve to different section tables out of GetSectionProfileForFrame
-- (Core_ProfileAPI.lua:1255), so table identity IS the scope. `ab == nil` is a
-- scope too and takes the constant key below.
--
-- WEAK KEYS, and the generation key below, cover the two lifetimes a section
-- table can have. A per-Layout or per-CFG section resolves to a MERGED VIEW
-- allocated by BuildMergedSectionView and cached at flat._sectionCache[section]
-- (Core_ProfileAPI.lua:1187-1189); invalidation drops that cache, so the next
-- resolve mints a NEW table and a strong key would pin the dead one for the
-- session. The degenerate paths return rpDB.profile[section] itself -- a
-- long-lived AceDB table the options UI mutates IN PLACE (BFStatus.lua:999-1001),
-- whose identity never changes on an edit. That is what the generation key is for.
local _blockCacheMeta = { __mode = "k" }

-- Scope key for "no section profile resolvable for this frame". A table, so it
-- can never collide with a real section table.
local _NO_SECTION = {}

-- This indicator's own default text color, also stamped at :41 by :Create.
local _DEFAULT_RMH_R, _DEFAULT_RMH_G, _DEFAULT_RMH_B = 1, 0.8, 0.2

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Implements the hook declared at BFIndicator.lua:62, dispatched by
-- BF:RefreshIndicatorSettings (BFIndicator.lua:332) from LoadLayout on every
-- profile/context switch. Drops the resolved blocks so the next Layout
-- re-resolves.
--
-- The PUSH half only, and an optimization rather than the correctness
-- guarantee: the generation key in ResolveReducedMaxHealthBlock is what makes
-- staleness impossible on the paths that reach indicator:Layout without ever
-- reaching RefreshIndicatorSettings (plan §6.1(b)).
function ReducedMaxHealthText:UpdateSettings()
	self._cfgBlocks = nil
end

-- Resolve (or reuse) this frame's block. Declared ABOVE
-- ReducedMaxHealthText:Layout on purpose: a Lua local is only in scope after
-- its declaration, so a resolver placed below its caller compiles to a nil
-- global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveReducedMaxHealthBlock(parent)
	local ab  = BF:GetSectionProfileForFrame("absorbs", parent)
	local key = ab or _NO_SECTION

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

	local blocks = ReducedMaxHealthText._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		ReducedMaxHealthText._cfgBlocks = blocks
	end

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- DEFAULT CHAIN, spelled out literally rather than read off the FontString.
	-- The block is shared by every frame in this scope, so it must not depend on
	-- per-FontString state: the old Layout read fs.SF_defaultFont and
	-- fs.SF_defaultSize, and that read is what made the resolution per-frame.
	-- Dropping it is safe because :Create stamps those fields on EVERY widget it
	-- builds, from this same chain (:32-34). Note the DEFAULT SIZE IS 9 here, not
	-- the 10 its neighbors use -- this text is deliberately a size smaller.
	-- BF.font is a file-scope constant (Core.lua:87), never reassigned, so
	-- resolving it here rather than at Create time cannot diverge.
	local baseFont, baseSize, baseFlags
	if GameFontNormalSmall then
		baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
	end
	baseFont  = baseFont  or BF.font or "Fonts\\FRIZQT__.TTF"
	baseSize  = baseSize  or 9
	baseFlags = baseFlags or ""

	-- FONT. Unlike its neighbors this indicator has NO adjust* toggle: the face
	-- goes through ResolveFontPath unconditionally, so an unset
	-- reducedMaxHealthFont resolves to the addon's own default face
	-- ("PT Sans Narrow", PixelPerfect.lua:657-664) rather than to
	-- GameFontNormalSmall's. That is existing behavior and is preserved exactly.
	-- The `or baseFont` tail keeps the old line's shape for the case where
	-- BF.ResolveFontPath does not exist at all; ResolveFontPath itself never
	-- returns nil, so it is unreachable while the function is loaded.
	block.fontPath  = (BF.ResolveFontPath and BF:ResolveFontPath(ab and ab.reducedMaxHealthFont))
	                  or baseFont
	block.fontSize  = (ab and ab.reducedMaxHealthFontSize) or baseSize
	block.fontFlags = (ab and ab.reducedMaxHealthFontBorder) or ""

	block.point = (ab and ab.reducedMaxHealthTextPosition) or "BOTTOMRIGHT"
	block.x     = (ab and ab.reducedMaxHealthTextX) or 0
	block.y     = (ab and ab.reducedMaxHealthTextY) or 0

	-- Color. Unconditional here -- this indicator has no class-color arm, so
	-- there is no per-unit case for Update to own (contrast LevelText).
	local c = ab and ab.reducedMaxHealthTextColor or nil
	block.colR = c and c.r or _DEFAULT_RMH_R
	block.colG = c and c.g or _DEFAULT_RMH_G
	block.colB = c and c.b or _DEFAULT_RMH_B

	return block
end

-- ============================================================
-- Layout
-- ============================================================
function ReducedMaxHealthText:Layout(parent)
	local fs = parent[self.name]
	-- Widget-existence guard, NOT a config guard: with no FontString there is
	-- nothing to write to. The config guard that used to follow it
	-- (`if not ab then return end`) is gone -- the block is complete even when
	-- no section profile resolves, so Layout has nothing left to decide.
	if not fs then return end

	local block = ResolveReducedMaxHealthBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout). Every field is written on every
	-- call; this function cannot leave the widget holding its Create-time
	-- defaults. The anchor stays per-frame -- frame state, not config.
	fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)

	local anchor = parent.container or parent.healthBar or parent
	fs:ClearAllPoints()
	fs:SetPoint(block.point, anchor, block.point, block.x, block.y)

	fs:SetTextColor(block.colR, block.colG, block.colB)
end

-- ============================================================
-- Update
-- ============================================================
function ReducedMaxHealthText:Update(parent, unit)
	local fs = parent[self.name]
	if not fs then return end

	local ab = BF:GetSectionProfileForFrame("absorbs", parent)
	if not ab or not ab.showReducedMaxHealthText or ab.appendReducedMaxText then
		fs:SetText("")
		fs:Hide()
		return
	end

	if not unit or not UnitExists(unit) then
		fs:SetText("")
		fs:Hide()
		return
	end

	local rPct = parent._reducedMaxPct
	if not rPct or issecretvalue(rPct) then
		fs:SetText("")
		fs:Hide()
		return
	end

	-- rPct is the reduction amount (0.04 = 4% reduced).
	-- Show the remaining max health: (1 - rPct) * 100
	if rPct > 0 then
		local remainPct = math.floor((1 - rPct) * 100 + 0.5)
		fs:SetFormattedText("(%d%%)", remainPct)
		fs:Show()
	else
		fs:SetText("")
		fs:Hide()
	end
end

BF:RegisterIndicator(ReducedMaxHealthText)
