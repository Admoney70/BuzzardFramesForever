--[[
BuzzardFrames: Indicators/PingIndicator.lua
Ping pin on raid/party frames.

The ping-pin events (UNIT_PING_PIN_ADDED/REMOVED) and Blizzard's
UnitPingIconFrameTemplate are both closed to addons, so this indicator
holds only the textures. They are driven by the shared ping mirror in
PingMirror.lua (BF:EnsurePingMirror), which watches the default UI's
compact-frame receivers and pushes show/hide + texture kit onto the
matching BuzzardFrames frame by GUID. That mirror is module-neutral: it
runs whether or not the unit frames module is enabled. /bf pingtest drives them
directly for testing.
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitExists = UnitExists

local PingIndicator = BF.indicatorPrototype:new("pingIndicator")

local DEFAULT_SIZE = 24
local DEFAULT_POS  = { point = "CENTER", x = 0, y = 0 }

function PingIndicator:Create(parent)
	if parent.pingIndicatorTex then
		parent[self.name] = parent.pingIndicatorFrame
		return
	end

	local ip = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.icons or {}
	local size = ip.pingIndicatorSize or DEFAULT_SIZE
	local pos  = ip.pingIndicatorPosition or DEFAULT_POS

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame:SetPoint(pos.point, parent, pos.point, pos.x, pos.y)
	frame:SetFrameLevel(parent:GetFrameLevel() + 221)
	frame:EnableMouse(false)

	-- Background must sub-layer BELOW the pin (same contract as the
	-- unit-frame widget in oUF_Shared.lua).
	local bg = BF.Texture(frame, nil, "OVERLAY", nil, 1)
	bg:SetAllPoints(frame)
	bg:Hide()
	local pin = BF.Texture(frame, nil, "OVERLAY", nil, 2)
	pin:SetAllPoints(frame)
	pin:Hide()
	pin.Background = bg
	pin.isRaidPin  = true -- gated by icons.showPingIndicator, not the oUF toggle
	-- Same shape as the oUF widget so the mirror can drive both.
	pin.PostUpdate = function(el)
		if el.Background then el.Background:SetShown(el:IsShown()) end
	end

	parent[self.name]         = frame
	parent.pingIndicatorFrame = frame
	parent.pingIndicatorTex   = pin
end

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
-- The scope key is the SECTION TABLE ITSELF (here: "icons"), the generation
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
function PingIndicator:UpdateSettings()
	self._cfgBlocks = nil
end

-- Declared ABOVE PingIndicator:Layout on purpose: a Lua local is only in scope
-- after its declaration, so a resolver placed below its caller compiles to a
-- nil global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolvePingIndicatorBlock(parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = PingIndicator._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		PingIndicator._cfgBlocks = blocks
	end
	local key = ip or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- DEFAULT_SIZE / DEFAULT_POS are this file's own module constants, already
	-- used as the inline fallbacks; the block keeps them as the fallback chain
	-- rather than introducing new literals. The position table is copied
	-- field-wise rather than held -- see RaidTargetIcon for why.
	block.size = (ip and ip.pingIndicatorSize) or DEFAULT_SIZE
	local pos = (ip and ip.pingIndicatorPosition) or DEFAULT_POS
	block.point = pos.point
	block.x     = pos.x
	block.y     = pos.y

	return block
end

function PingIndicator:Layout(parent)
	local frame = parent[self.name]
	-- Widget-existence guard, NOT a config guard. The config guard that used to
	-- follow it (`if not ip then return end`) is gone: the block is complete even
	-- when no section resolves.
	if not frame then return end

	local block = ResolvePingIndicatorBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout shape).
	frame:SetSize(block.size, block.size)
	frame:ClearAllPoints()
	frame:SetPoint(block.point, parent, block.point, block.x, block.y)
end

-- The mirror shows/hides the pin; Update only enforces the toggle and
-- clears a pin whose unit has changed under it (roster shuffles).
function PingIndicator:Update(parent, unit)
	local pin = parent.pingIndicatorTex
	if not pin then return end
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	if not ip or not ip.showPingIndicator or not unit or not UnitExists(unit) then
		pin:Hide(); pin:PostUpdate(nil); pin._mirrorKey = false
		return
	end
	-- v97: secret-safe read (same sanitizer the mirror uses). UnitGUID is a
	-- SECRET under combat secrecy and comparing it raw throws, aborting the
	-- rest of this frame's indicator sweep. Unreadable => cannot be matched
	-- to a receiver => hide, the same arm an absent unit takes.
	local guid = BF.SafePingGUID and BF.SafePingGUID(unit) or nil
	if not guid or (pin._pingGUID and pin._pingGUID ~= guid) then
		pin:Hide(); pin:PostUpdate(nil); pin._mirrorKey = false
	end
	pin._pingGUID = guid
end

BF:RegisterIndicator(PingIndicator)
