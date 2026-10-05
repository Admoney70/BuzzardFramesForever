--[[
BuzzardFrames: Indicators/VehicleText.lua
Vehicle text — shows the vehicle name when a unit is in a vehicle.

Vehicle icon visibility and vehicle text are driven by StatusIcons:_UpdateVehicle.
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local VehicleText = BF.indicatorPrototype:new("vehicleText")

function VehicleText:Create(parent)
	if parent.vehicleText then
		parent[self.name] = parent.vehicleText
		return
	end

	local clipParent = parent.nameClip or parent
	local hBar = parent.healthBar

	local fs = clipParent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(GameFontNormalSmall)
	local font, size, flags = fs:GetFont()
	font  = font  or BF.font or "Fonts\\FRIZQT__.TTF"
	size  = size  or 10
	flags = flags or ""
	fs.SF_defaultFont  = font
	fs.SF_defaultSize  = size
	fs.SF_defaultFlags = flags
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)

	local tp = BF:GetSectionProfileForFrame("text", parent) or {}
	local vnp = tp.vehicleNamePosition or { point = "CENTER", x = 0, y = 0 }
	fs:SetPoint(vnp.point, hBar or parent, vnp.point, vnp.x, vnp.y)
	fs:SetJustifyH("CENTER")
	fs:SetWordWrap(false)
	fs:Hide()

	parent[self.name] = fs
	parent.vehicleText = fs
end

-- ============================================================
-- Resolved config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded,
-- into a block the indicator holds (modules/IndicatorText.lua:251), and Layout
-- then writes that block with no decisions left in it (:106). The fallback
-- chain is baked in at RESOLVE time, which is exactly why Layout needs no
-- `if not tp then return end` -- the block handed to it is always complete.
-- See BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- SCOPE KEY = THE SECTION TABLE ITSELF. This is an established in-tree
-- pattern, not a new one: BFStatus.lua:993-1005 memoizes the composed name
-- entry the same way, weak-keyed, and states the rationale -- "Frames sharing
-- a flat share one entry; CFG flats get their own." The active flat, each
-- Custom Frame Group and each preview frame resolve to different section
-- tables out of GetSectionProfileForFrame (Core_ProfileAPI.lua:1255), so the
-- table identity IS the scope, with no scope list to enumerate or keep in
-- sync. `tp == nil` is a scope too, and takes the constant key below rather
-- than being turned back into an early return.
--
-- WEAK KEYS, and the generation key below, cover the two different lifetimes a
-- section table can have. A per-Layout or per-CFG section resolves to a MERGED
-- VIEW allocated by BuildMergedSectionView and cached at
-- flat._sectionCache[section] (Core_ProfileAPI.lua:1187-1189); invalidation
-- drops that cache, so the next resolve mints a NEW table and a strong key
-- would pin the dead one for the session. The degenerate paths instead return
-- rpDB.profile[section] itself -- a long-lived AceDB table the options UI
-- mutates IN PLACE (BFStatus.lua:999-1001), whose identity never changes on an
-- edit. Keying on the table alone would never notice those edits; that is what
-- the generation key is for.
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
-- re-resolves.
--
-- The PUSH half only, and an optimization rather than the correctness
-- guarantee: the generation key in ResolveVehicleTextBlock is what makes
-- staleness impossible on the paths that reach indicator:Layout without ever
-- reaching RefreshIndicatorSettings (plan §6.1(b)).
function VehicleText:UpdateSettings()
	self._cfgBlocks = nil
end

-- Default position, used when the profile carries no vehicleNamePosition.
-- Matches what :Create anchors with, above.
local _DEFAULT_VEHICLE_POS = { point = "CENTER", x = 0, y = 0 }

-- Resolve (or reuse) this frame's block. Declared ABOVE VehicleText:Layout on
-- purpose: a Lua local is only in scope after its declaration, so a resolver
-- placed below its caller compiles to a nil global lookup and throws only on
-- the path that reaches it. Tests/check_locals.py exists for that.
local function ResolveVehicleTextBlock(parent)
	-- Route by frame so Custom Frame Groups and preview frames reflect their
	-- own per-layout edits. See BF:GetSectionProfileForFrame.
	local tp  = BF:GetSectionProfileForFrame("text", parent)
	local key = tp or _NO_SECTION

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

	local blocks = VehicleText._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		VehicleText._cfgBlocks = blocks
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
	-- per-FontString state: fs.SF_defaultFont / SF_defaultSize / SF_defaultFlags
	-- are what the old Layout read, and that read is what made the resolution
	-- per-frame. Dropping it is safe because :Create stamps those three fields on
	-- EVERY vehicleText it builds, from this same chain -- note the order here is
	-- GameFontNormalSmall's font FIRST, then BF.font, which is this file's
	-- spelling (:24) and NOT StatusText_Overlay's. BF.font is a file-scope
	-- constant (Core.lua:87), never reassigned, so resolving it here rather than
	-- at Create time cannot diverge.
	local baseFont, baseSize, baseFlags
	if GameFontNormalSmall then
		baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
	end
	baseFont  = baseFont  or BF.font or "Fonts\\FRIZQT__.TTF"
	baseSize  = baseSize  or 10
	baseFlags = baseFlags or ""

	-- adjustVehicleFont semantics unchanged: ON takes the configured face, the
	-- configured size falling back to the default size, and the configured
	-- border falling back to none; OFF takes the default triple whole.
	-- BF:ResolveFontPath (PixelPerfect.lua:656) always returns a path, so
	-- block.fontPath is never nil.
	if tp and tp.adjustVehicleFont then
		block.fontPath  = BF:ResolveFontPath(tp.vehicleFont)
		block.fontSize  = tp.vehicleFontSize or baseSize
		block.fontFlags = tp.vehicleFontBorder or ""
	else
		block.fontPath  = baseFont
		block.fontSize  = baseSize
		block.fontFlags = baseFlags
	end

	-- Position. vehicleNamePosition is a {point,x,y} TABLE in the profile, so
	-- the fields are copied out rather than the table being held: holding it
	-- would make the block alias profile storage the options UI mutates in
	-- place, and the generation key could not tell the difference.
	local vnp = (tp and tp.vehicleNamePosition) or _DEFAULT_VEHICLE_POS
	block.point = vnp.point
	block.x     = vnp.x
	block.y     = vnp.y

	return block
end

function VehicleText:Layout(parent)
	local fs = parent[self.name]
	-- Widget-existence guard, NOT a config guard: with no FontString there is
	-- nothing to write to. The config guard that used to sit below it
	-- (`if not tp then return end`) is gone -- the block is complete even when
	-- no section profile resolves, so Layout has nothing left to decide.
	if not fs then return end

	local block = ResolveVehicleTextBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout). Every field is written on every
	-- call; this function cannot leave the widget holding its Create-time
	-- defaults. The anchor stays per-frame -- it is frame state, not config.
	local hBar = parent.healthBar
	fs:ClearAllPoints()
	fs:SetPoint(block.point, hBar or parent, block.point, block.x, block.y)

	fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)
end

-- Vehicle text content is set by StatusIcons:_UpdateVehicle.
function VehicleText:Update(parent, unit)
end

BF:RegisterIndicator(VehicleText)
