--[[
BuzzardFrames: Indicators/RoleIcon.lua
Role icon indicator — shows tank/healer/dps icon per unit.

Grid2 equivalent: IndicatorIcon.lua bound to StatusRole.

Each call to Update unconditionally overwrites stale state (Grid2 pattern).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitExists              = UnitExists
local UnitIsUnit              = UnitIsUnit
local UnitGroupRolesAssigned  = UnitGroupRolesAssigned
local GetSpecialization       = GetSpecialization
local GetSpecializationRole   = GetSpecializationRole

local RoleIcon = BF.indicatorPrototype:new("roleIcon")

-- ============================================================
-- Create
-- ============================================================
function RoleIcon:Create(parent)
	-- Skip if already created by legacy InitFrame
	if parent.roleIcon then
		parent[self.name] = parent.roleIcon
		return
	end

	-- Use a dedicated Frame parented directly to the unit frame (not nameClip)
	-- so the icon is never clipped when it extends outside the frame bounds.
	-- This matches the LeaderIcon pattern.
	local ip = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.icons
	local size = ip and ip.roleIconSize or 12

	local iconFrame = CreateFrame("Frame", nil, parent)
	iconFrame:SetSize(size, size)
	iconFrame:SetPoint("TOPLEFT", parent.healthBar or parent, "TOPLEFT", 1, -1)
	iconFrame:SetFrameLevel(parent:GetFrameLevel() + 218)
	local tex = BF.Texture(iconFrame, nil, "ARTWORK")
	tex:SetAllPoints(iconFrame)
	iconFrame.texture = tex
	iconFrame:Hide()

	parent[self.name] = iconFrame
	parent.roleIcon = iconFrame  -- backward compat alias
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
function RoleIcon:UpdateSettings()
	self._cfgBlocks = nil
end

-- Paired with NameText: these ARE NameText's fallbacks, read from it, not
-- copies of them -- see the note at their declaration
-- (Indicators/NameText.lua, BF.NAMEPOS_FALLBACK / BF.ROLEPOS_FALLBACK).
-- AdjustNameForHiddenRole below re-derives NameText's anchor, so the two must
-- fall back to the same position or they disagree about where the name sits on
-- a profile missing namePosition. Deliberately paired; change both or neither.
local _DEFAULT_NAME_POS = BF.NAMEPOS_FALLBACK
local _DEFAULT_ROLE_POS = BF.ROLEPOS_FALLBACK

-- Declared ABOVE RoleIcon:Layout on purpose: a Lua local is only in scope after
-- its declaration, so a resolver placed below its caller compiles to a nil
-- global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveRoleIconBlock(parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = RoleIcon._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		RoleIcon._cfgBlocks = blocks
	end
	local key = ip or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	block.size = (ip and ip.roleIconSize) or 12
	-- roleIconPosition is a {point,x,y} TABLE; fields are copied out rather than
	-- the table held, so the block never aliases profile storage the options UI
	-- mutates in place.
	local rp = (ip and ip.roleIconPosition) or _DEFAULT_ROLE_POS
	block.point = rp.point
	block.x     = rp.x
	block.y     = rp.y

	return block
end

-- ============================================================
-- Layout
-- ============================================================
function RoleIcon:Layout(parent)
	local icon = parent[self.name]
	-- Widget-existence guard, NOT a config guard. The config guard that used to
	-- follow it (`if not ip then return end`) is gone: the block is complete even
	-- when no section resolves, so Layout has nothing left to decide.
	if not icon then return end

	local block = ResolveRoleIconBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout shape).
	icon:SetSize(block.size, block.size)
	icon:ClearAllPoints()
	icon:SetPoint(block.point, parent, block.point, block.x, block.y)
end

-- ============================================================
-- Name repositioning when role icon is hidden for this unit.
-- NameText:Layout sets the name offset assuming the role icon
-- is visible. When the icon is hidden (globally, per-role, or
-- per-CF-module), we reposition the name with a small inset
-- so it doesn't sit flush against the frame edge.
-- ============================================================
local HIDDEN_ROLE_NAME_INSET = 3

local function AdjustNameForHiddenRole(parent)
	local fs = parent.nameText
	if not fs then return end
	-- Route by frame so preview frames see their own flat's text+icons
	-- sections while live frames see the active game context's flat.
	-- Matches NameText:Layout routing exactly.
	local tp = BF:GetSectionProfileForFrame("text",  parent)
	local ip = BF:GetSectionProfileForFrame("icons", parent)
	-- CARRY-OVER 1 (2026-09-21). This used to read
	--     if not tp or not tp.namePosition or (tp and tp.linkNameAndRole)
	-- and the first two clauses were config-presence guards of exactly the
	-- kind NameText:Layout just shed. Leaving them would have made the pair
	-- disagree: on a profile with no namePosition, NameText now anchors the
	-- name from _DEFAULT_NAME_POS while this function would have declined to
	-- adjust it. Both now fall back to the SAME shared tables, so the two
	-- derive the same anchor from the same inputs.
	--
	-- The linkNameAndRole test STAYS: that is a resolved-config feature
	-- switch (the name is anchored to the role icon, so there is no separate
	-- name position to adjust), not a "do we have config" test -- the same
	-- distinction that kept block.writeColor conditional in LevelText.
	if tp and tp.linkNameAndRole then return end
	local np = (tp and tp.namePosition) or _DEFAULT_NAME_POS
	local rp = (ip and ip.roleIconPosition) or _DEFAULT_ROLE_POS
	-- Not a config guard either: the hidden-role inset only applies when the
	-- name and the role icon share a corner. Different corners, nothing to do.
	if np.point ~= rp.point then return end

	local nameX = np.x or 0
	local nameY = np.y or 0
	if np.point:find("LEFT") then
		nameX = nameX + HIDDEN_ROLE_NAME_INSET
	elseif np.point:find("RIGHT") then
		nameX = nameX - HIDDEN_ROLE_NAME_INSET
	end

	local anchorPoint = np.point or "CENTER"
	local vAnchor
	if anchorPoint:find("TOP") then vAnchor = "TOP"
	elseif anchorPoint:find("BOTTOM") then vAnchor = "BOTTOM"
	else vAnchor = "" end
	local pinPoint = vAnchor ~= "" and (vAnchor .. "LEFT") or "LEFT"
	local anchor = parent.container or parent.healthBar or parent
	fs:ClearAllPoints()
	fs:SetPoint(pinPoint, anchor, pinPoint, nameX, nameY)
	parent._roleIconNameAdjusted = true
end

-- Exposed for NameText:Layout: when a frame is flagged
-- _roleIconNameAdjusted (this unit's role icon is hidden), a full
-- re-Layout must re-apply the hidden-role name position itself —
-- there is no role event after e.g. a border-color setter's
-- LayoutFrame sweep to run RoleIcon:Update again (field report: the
-- names of DPS units snapped back to the icon-offset position when
-- any unrelated setting re-ran LayoutFrame).
function BF:ReapplyHiddenRoleNameAdjust(parent)
	AdjustNameForHiddenRole(parent)
end

local function RestoreNameForShownRole(parent)
	if not parent._roleIconNameAdjusted then return end
	parent._roleIconNameAdjusted = nil
	-- Re-run NameText:Layout to restore the icon-offset position
	local nameInd = BF:GetIndicatorByName("nameText")
	if nameInd then nameInd:Layout(parent) end
end

-- ============================================================
-- Update: unconditionally overwrite (Grid2 pattern)
-- ============================================================
function RoleIcon:Update(parent, unit)
	local icon = parent[self.name]
	if not icon then return end

	local ip = BF:GetSectionProfileForFrame("icons", parent)

	-- Grid2 pattern: always overwrite — no cached state
	if not ip or not ip.showRoleIcons or not unit or not UnitExists(unit) then
		icon:Hide()
		AdjustNameForHiddenRole(parent)
		return
	end

	-- Pet frames: pets don't have roles
	local header = parent:GetParent()
	if header and header.isPetFrame then
		icon:Hide()
		AdjustNameForHiddenRole(parent)
		return
	end

	-- Read from role status instead of WoW API directly
	local roleStatus = BF.statuses and BF.statuses.role
	local role = roleStatus and roleStatus:GetRole(unit) or "NONE"

	-- Per-role visibility filter (Grid2 isValidRole pattern)
	if role == "TANK" and not ip.showRoleIconTank then
		icon:Hide()
		AdjustNameForHiddenRole(parent)
		return
	elseif role == "HEALER" and not ip.showRoleIconHealer then
		icon:Hide()
		AdjustNameForHiddenRole(parent)
		return
	elseif role == "DAMAGER" and not ip.showRoleIconDPS then
		icon:Hide()
		AdjustNameForHiddenRole(parent)
		return
	end

	-- Show the icon before restoring name position, so NameText:Layout
	-- sees the icon as visible when it re-runs.
	icon:Show()
	RestoreNameForShownRole(parent)

	local tex = icon.texture
	if ip.roleIconStyle == "TINY" then
		tex:SetTexture(nil)
		tex:SetTexCoord(0, 1, 0, 1)
		if role == "TANK" then
			tex:SetAtlas("roleicon-tiny-tank", false)
		elseif role == "HEALER" then
			tex:SetAtlas("roleicon-tiny-healer", false)
		elseif role == "DAMAGER" then
			tex:SetAtlas("roleicon-tiny-dps", false)
		else
			icon:Hide()
			AdjustNameForHiddenRole(parent)
		end
	elseif ip.roleIconStyle == "MODERN" then
		tex:SetTexture(nil)
		tex:SetTexCoord(0, 1, 0, 1)
		if role == "TANK" then
			tex:SetAtlas("UI-LFG-RoleIcon-Tank-Micro-GroupFinder", false)
		elseif role == "HEALER" then
			tex:SetAtlas("UI-LFG-RoleIcon-Healer-Micro-GroupFinder", false)
		elseif role == "DAMAGER" then
			tex:SetAtlas("UI-LFG-RoleIcon-DPS-Micro-GroupFinder", false)
		else
			icon:Hide()
			AdjustNameForHiddenRole(parent)
		end
	elseif ip.roleIconStyle == "GLASS" then
		-- Glass style (owner-supplied art): per-role TGA files with real
		-- alpha — translucent glass panes with colored rims.
		tex:SetTexCoord(0, 1, 0, 1)
		if role == "TANK" then
			tex:SetTexture("Interface\\AddOns\\BuzzardFrames\\Media\\role_glass_tank")
		elseif role == "HEALER" then
			tex:SetTexture("Interface\\AddOns\\BuzzardFrames\\Media\\role_glass_healer")
		elseif role == "DAMAGER" then
			tex:SetTexture("Interface\\AddOns\\BuzzardFrames\\Media\\role_glass_dps")
		else
			icon:Hide()
			AdjustNameForHiddenRole(parent)
		end
	else
		local roleTex = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
		if role == "TANK" then
			tex:SetTexture(roleTex); tex:SetTexCoord(0, 19/64, 22/64, 41/64)
		elseif role == "HEALER" then
			tex:SetTexture(roleTex); tex:SetTexCoord(20/64, 39/64, 1/64, 20/64)
		elseif role == "DAMAGER" then
			tex:SetTexture(roleTex); tex:SetTexCoord(20/64, 39/64, 22/64, 41/64)
		else
			icon:Hide()
			AdjustNameForHiddenRole(parent)
		end
	end
end

BF:RegisterIndicator(RoleIcon)
