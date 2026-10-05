--[[
BuzzardFrames: Indicators/LeaderIcon.lua
Leader and assistant icons.
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitExists            = UnitExists
local UnitIsGroupLeader     = UnitIsGroupLeader
local UnitIsGroupAssistant  = UnitIsGroupAssistant

local LeaderIcon = BF.indicatorPrototype:new("leaderIcon")

function LeaderIcon:Create(parent)
	if parent.leaderIcon then
		parent[self.name] = parent.leaderIcon
		return
	end

	local ip = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.icons or {}

	-- Leader icon
	local lFrame = CreateFrame("Frame", nil, parent)
	lFrame:SetSize(ip.leaderIconSize or 12, ip.leaderIconSize or 12)
	local lPos = ip.leaderIconPosition or { point = "TOPLEFT", x = 2, y = -2 }
	lFrame:SetPoint(lPos.point, parent, lPos.point, lPos.x, lPos.y)
	lFrame:SetFrameLevel(parent:GetFrameLevel() + 219)
	local lTex = BF.Texture(lFrame, nil, "ARTWORK")
	lTex:SetAllPoints(lFrame)
	lTex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	lFrame:Hide()
	parent.leaderIcon = lFrame
	parent.leaderIconTexture = lTex

	-- Assistant icon
	local aFrame = CreateFrame("Frame", nil, parent)
	aFrame:SetSize(ip.assistantIconSize or 12, ip.assistantIconSize or 12)
	local aPos = ip.assistantIconPosition or { point = "TOPLEFT", x = 2, y = -2 }
	aFrame:SetPoint(aPos.point, parent, aPos.point, aPos.x, aPos.y)
	aFrame:SetFrameLevel(parent:GetFrameLevel() + 219)
	local aTex = BF.Texture(aFrame, nil, "ARTWORK")
	aTex:SetAllPoints(aFrame)
	aTex:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
	aFrame:Hide()
	parent.assistantIcon = aFrame
	parent.assistantIconTexture = aTex

	parent[self.name] = lFrame
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
function LeaderIcon:UpdateSettings()
	self._cfgBlocks = nil
end

-- Fallbacks, matching what :Create anchors both icons with (:25, :38).
local _DEFAULT_LEADER_POS    = { point = "TOPLEFT", x = 2, y = -2 }
local _DEFAULT_ASSISTANT_POS = { point = "TOPLEFT", x = 2, y = -2 }

-- Declared ABOVE LeaderIcon:Layout on purpose: a Lua local is only in scope
-- after its declaration, so a resolver placed below its caller compiles to a
-- nil global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveLeaderIconBlock(parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = LeaderIcon._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		LeaderIcon._cfgBlocks = blocks
	end
	local key = ip or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- Both icons come out of one block: they share a scope, so resolving them
	-- together costs one lookup instead of two. Position tables are copied
	-- field-wise rather than held -- see RaidTargetIcon for why.
	block.leaderSize = (ip and ip.leaderIconSize) or 12
	local lPos = (ip and ip.leaderIconPosition) or _DEFAULT_LEADER_POS
	block.leaderPoint = lPos.point
	block.leaderX     = lPos.x
	block.leaderY     = lPos.y

	block.assistantSize = (ip and ip.assistantIconSize) or 12
	local aPos = (ip and ip.assistantIconPosition) or _DEFAULT_ASSISTANT_POS
	block.assistantPoint = aPos.point
	block.assistantX     = aPos.x
	block.assistantY     = aPos.y

	return block
end

function LeaderIcon:Layout(parent)
	-- The config guard that used to stand here (`if not ip then return end`) is
	-- gone: the block is complete even when no section resolves. The two
	-- `if parent.xIcon` tests below STAY -- those are widget-existence guards,
	-- and this indicator owns two widgets that are created independently.
	local block = ResolveLeaderIconBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout shape).
	if parent.leaderIcon then
		parent.leaderIcon:SetSize(block.leaderSize, block.leaderSize)
		parent.leaderIcon:ClearAllPoints()
		parent.leaderIcon:SetPoint(block.leaderPoint, parent, block.leaderPoint,
		                           block.leaderX, block.leaderY)
	end
	if parent.assistantIcon then
		parent.assistantIcon:SetSize(block.assistantSize, block.assistantSize)
		parent.assistantIcon:ClearAllPoints()
		parent.assistantIcon:SetPoint(block.assistantPoint, parent, block.assistantPoint,
		                              block.assistantX, block.assistantY)
	end
end

function LeaderIcon:Update(parent, unit)
	if not unit or not UnitExists(unit) then
		if parent.leaderIcon then parent.leaderIcon:Hide() end
		if parent.assistantIcon then parent.assistantIcon:Hide() end
		return
	end
	local ip = BF:GetSectionProfileForFrame("icons", parent)

	-- Read from leader status instead of WoW API directly
	local leaderStatus = BF.statuses and BF.statuses.leader

	-- Leader
	if parent.leaderIcon then
		if ip and ip.showLeaderIcon and leaderStatus and leaderStatus:IsLeader(unit) then
			parent.leaderIcon:Show()
		else
			parent.leaderIcon:Hide()
		end
	end

	-- Assistant
	if parent.assistantIcon then
		if ip and ip.showAssistantIcon and leaderStatus and leaderStatus:IsAssistant(unit) then
			parent.assistantIcon:Show()
		else
			parent.assistantIcon:Hide()
		end
	end
end

BF:RegisterIndicator(LeaderIcon)
