--[[
BuzzardFrames: Indicators/TargetHighlight.lua
Target highlight border indicator — shows a colored border when the
frame's unit is the player's current target.

Grid2 equivalent: IndicatorBorder.lua bound to StatusTarget.

Each call to Update unconditionally overwrites stale state (Grid2 pattern).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists

local TargetHighlight = BF.indicatorPrototype:new("targetHighlight")

-- ============================================================
local function MakeEdge(parent)
	local t = BF.Texture(parent, nil, "OVERLAY")
	t:SetColorTexture(0, 0, 0, 1)
	return t
end

local function PixelsToUI(n)
	local pixelSize = 768 / select(2, GetPhysicalScreenSize())
	local uiScale = UIParent:GetEffectiveScale()
	local pixelMult = (uiScale > 0) and (pixelSize / uiScale) or 1
	return n * pixelMult
end

-- ============================================================
-- Create
-- ============================================================
function TargetHighlight:Create(parent)
	-- Skip if already created by legacy InitFrame
	if parent.targetHighlight then
		parent[self.name] = parent.targetHighlight
		return
	end

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 13)
	frame:EnableMouse(false)
	frame.top    = MakeEdge(frame)
	frame.bottom = MakeEdge(frame)
	frame.left   = MakeEdge(frame)
	frame.right  = MakeEdge(frame)

	parent[self.name] = frame
	parent.targetHighlight = frame  -- backward compat alias
end

-- ============================================================
-- Layout
-- ============================================================
-- ============================================================
-- Resolved config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded, into
-- a block the indicator holds (modules/IndicatorText.lua:251), and Layout then
-- writes that block with no decisions left in it (:106). The fallback chain is
-- baked in at RESOLVE time, which is why Layout needs no early return on a
-- missing section -- the block handed to it is always complete. See
-- BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- The scope key is the SECTION TABLE ITSELF (here: "borders"), the generation
-- key is BF._sectionCfgGen, and the cache is weak-keyed. The full reasoning for
-- all three -- why table identity is the scope, why weak keys and the
-- generation key cover two different section-table lifetimes, and why the
-- generation key rather than the push is what closes the staleness window --
-- is written out once at Indicators/StatusText_Overlay.lua:197-236 and is not
-- repeated in every indicator. In-tree precedent: BFStatus.lua:993-1005 (scope
-- key) and Indicators/HealthText.lua:129/:417 (generation key).
local _blockCacheMeta = { __mode = "k" }

-- Scope key for "no section profile resolvable for this frame". A table, so it
-- can never collide with a real section table.
local _NO_SECTION = {}

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Implements the hook declared at BFIndicator.lua:62, dispatched by
-- BF:RefreshIndicatorSettings (BFIndicator.lua:332) from LoadLayout on every
-- profile/context switch. Drops the resolved blocks so the next Layout
-- re-resolves. The PUSH half only -- an optimization, not the correctness
-- guarantee (plan §6.1(b)).
function TargetHighlight:UpdateSettings()
	self._cfgBlocks = nil
end

-- Declared ABOVE TargetHighlight:Layout on purpose: a Lua local is only in
-- scope after its declaration, so a resolver placed below its caller compiles
-- to a nil global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveTargetHighlightBlock(parent)
	local bp = BF:GetSectionProfileForFrame("borders", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = TargetHighlight._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		TargetHighlight._cfgBlocks = blocks
	end
	local key = bp or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- PIXELS ONLY -- the PixelsToUI conversion deliberately stays in Layout.
	-- PixelsToUI multiplies by pixelMult (PixelPerfect.lua:91-93, :100-103), a
	-- screen/UI-scale value refreshed by RefreshPixelSize, and a resolution or
	-- UI-scale change does NOT bump BF._sectionCfgGen. A cached converted value
	-- would survive such a change and draw the highlight at the old thickness.
	-- Same rule as NameText's border width.
	block.widthPx = (bp and bp.targetHighlightWidth) or 2

	return block
end

function TargetHighlight:Layout(parent)
	local frame = parent[self.name]
	-- Widget-existence guard, NOT a config guard.
	if not frame then return end

	-- The config guard that used to stand here (`if not bp then return end`) is
	-- gone: the block is complete even when no section resolves.
	local block = ResolveTargetHighlightBlock(parent)

	local t = frame.top
	local b = frame.bottom
	local l = frame.left
	local r = frame.right
	-- Also widget existence: the four edges are built together, so this is one
	-- test for one widget set.
	if not (t and b and l and r) then return end

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout shape). Converted here, not cached.
	local targetT = PixelsToUI(block.widthPx)

	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	t:SetHeight(targetT)

	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	b:SetHeight(targetT)

	-- Corners inset so top/bottom edges don't overlap left/right
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -targetT)
	l:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, targetT)
	l:SetWidth(targetT)

	r:ClearAllPoints()
	r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -targetT)
	r:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, targetT)
	r:SetWidth(targetT)
end

-- ============================================================
-- Update: unconditionally overwrite (Grid2 pattern)
-- ============================================================
function TargetHighlight:Update(parent, unit)
	local frame = parent[self.name]
	if not frame then return end

	local bp = BF:GetSectionProfileForFrame("borders", parent)

	-- Grid2 pattern: always recompute, always set color
	local enabled = not bp or bp.enableTargetHighlight ~= false
	local opacity = (bp and bp.targetHighlightOpacity) or 1.0
	local c = (bp and bp.targetHighlightColor) or { r = 1, g = 1, b = 1 }

	-- Read from target status instead of WoW API directly
	local targetStatus = BF.statuses and BF.statuses.target
	-- SetHighlightBorder: rounded border styles draw a tinted nine-slice
	-- ring (matching the frame's rounded thickness) and hide the 4 square
	-- edges; square style behaves exactly as SetBorderColor did.
	-- Raid-style twins never draw the target highlight (plan decision 7.6):
	-- the target twin's token IS "target" so it would be permanently lit,
	-- and player/focus/boss twins follow the same rule. Per FRAME, not per
	-- unit -- in a party the "player" token is shared by the party frame
	-- (which must still light up) and the player twin.
	if enabled and not parent._bf_twinKey and targetStatus and targetStatus:IsActive(unit) then
		BF:SetHighlightBorder(frame, parent, c.r, c.g, c.b, opacity,
			(bp and bp.targetHighlightWidth) or 2)
	else
		BF:SetHighlightBorder(frame, parent, 0, 0, 0, 0)
	end
end

BF:RegisterIndicator(TargetHighlight)
