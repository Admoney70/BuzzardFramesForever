--[[
BuzzardFrames: Indicators/RaidTargetIcon.lua
Raid target marker icon (skull, cross, moon, etc.)
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitExists       = UnitExists
local GetRaidTargetIndex = GetRaidTargetIndex

local RaidTargetIcon = BF.indicatorPrototype:new("raidTargetIcon")

function RaidTargetIcon:Create(parent)
	if parent.raidTargetIcon then
		parent[self.name] = parent.raidTargetIcon
		return
	end

	local ip = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.icons or {}
	local size = ip.raidTargetIconSize or 16
	local rtPos = ip.raidTargetIconPosition or { point = "CENTER", x = 0, y = 0 }

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame:SetPoint(rtPos.point, parent, rtPos.point, rtPos.x, rtPos.y)
	frame:SetFrameLevel(parent:GetFrameLevel() + 220)
	frame:Hide()

	local tex = BF.Texture(frame, nil, "ARTWORK")
	tex:SetAllPoints(frame)

	parent[self.name] = frame
	parent.raidTargetIcon = frame
	parent.raidTargetIconTexture = tex
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
function RaidTargetIcon:UpdateSettings()
	self._cfgBlocks = nil
end

-- Fallback position, matching what :Create anchors with (:21).
local _DEFAULT_RT_POS = { point = "CENTER", x = 0, y = 0 }

-- Declared ABOVE RaidTargetIcon:Layout on purpose: a Lua local is only in
-- scope after its declaration, so a resolver placed below its caller compiles
-- to a nil global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveRaidTargetIconBlock(parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = RaidTargetIcon._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		RaidTargetIcon._cfgBlocks = blocks
	end
	local key = ip or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	block.size = (ip and ip.raidTargetIconSize) or 16
	-- raidTargetIconPosition is a {point,x,y} TABLE in the profile. The fields
	-- are copied out rather than the table held: holding it would make the block
	-- alias profile storage the options UI mutates in place, which the generation
	-- key cannot see through.
	local rtPos = (ip and ip.raidTargetIconPosition) or _DEFAULT_RT_POS
	block.point = rtPos.point
	block.x     = rtPos.x
	block.y     = rtPos.y

	return block
end

function RaidTargetIcon:Layout(parent)
	local frame = parent[self.name]
	-- Widget-existence guard, NOT a config guard. The config guard that used to
	-- follow it (`if not ip then return end`) is gone: the block is complete even
	-- when no section resolves, so Layout has nothing left to decide.
	if not frame then return end

	local block = ResolveRaidTargetIconBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout shape).
	frame:SetSize(block.size, block.size)
	frame:ClearAllPoints()
	frame:SetPoint(block.point, parent, block.point, block.x, block.y)
end

function RaidTargetIcon:Update(parent, unit)
	local frame = parent[self.name]
	if not frame then return end
	local ip = BF:GetSectionProfileForFrame("icons", parent)

	if not ip or not ip.showRaidTargetIcon or not unit or not UnitExists(unit) then
		frame:Hide()
		return
	end

	-- Read from raidicon status instead of WoW API directly.
	-- NOTE: `index` is a SECRET number under addon taint (12.1) — truth-test
	-- and render-API use only, never compare it.
	local raidIconStatus = BF.statuses and BF.statuses.raidicon
	local index = raidIconStatus and raidIconStatus:GetIndex(unit)
	if index then
		local tex = parent.raidTargetIconTexture
		if tex then
			tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
			tex:SetSpriteSheetCell(index, 4, 4, 64, 64)
		end
		frame:Show()
	else
		frame:Hide()
	end
end

BF:RegisterIndicator(RaidTargetIcon)
