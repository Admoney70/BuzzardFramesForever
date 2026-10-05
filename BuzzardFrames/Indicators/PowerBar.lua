--[[
BuzzardFrames: Indicators/PowerBar.lua
Power bar indicator — mirrors Grid2's IndicatorBar.lua pattern.

Creates a StatusBar at the bottom of the frame for mana/energy/etc.
Visibility is conditional: only shown when BF:ShouldShowPowerBar(unit) is true.

Each call to Update unconditionally overwrites stale state (Grid2 pattern).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitPowerType       = UnitPowerType
local UnitPowerPercent    = UnitPowerPercent
local UnitExists          = UnitExists
local InCombatLockdown    = InCombatLockdown
local PowerBarColor       = PowerBarColor
local issecretvalue       = issecretvalue or function() return false end

local PowerBar = BF.indicatorPrototype:new("powerBar")

-- ============================================================

local function PixelsToUI(n)
	local pixelSize = 768 / select(2, GetPhysicalScreenSize())
	local uiScale = UIParent:GetEffectiveScale()
	local pixelMult = (uiScale > 0) and (pixelSize / uiScale) or 1
	return n * pixelMult
end

-- ============================================================
-- Create
-- ============================================================
function PowerBar:Create(parent)
	-- Skip if already created by legacy InitFrame
	if parent.powerBar then
		parent[self.name] = parent.powerBar
		return
	end

	local bar = BF.StatusBar(nil, parent)
	bar.indicator = self
	bar:EnableMouse(false)
	BF:DisablePixelSnapRegion(bar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local _p = BF.db and BF.db.profile
	local pbTex = (_p and _p.useCustomPowerBarTexture) and BF:ResolveBarTexture(_p.powerBarTexture) or "Interface\\Buttons\\WHITE8X8"
	bar:SetStatusBarTexture(pbTex)
	bar:Hide()

	local tex = bar:GetStatusBarTexture()
	if tex then
		BF:DisablePixelSnapRegion(tex)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
		tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	end

	-- Background frame + texture
	local bgFrame = CreateFrame("Frame", nil, parent)
	bgFrame:SetAllPoints(bar)
	bgFrame:Hide()
	local bgTex = BF.Texture(bgFrame, nil, "BACKGROUND")
	bgTex:SetAllPoints(bgFrame)
	bgTex:SetColorTexture(0.08, 0.08, 0.08, 1.0)
	bar.bg = bgTex
	bar.bgFrame = bgFrame

	parent[self.name] = bar
	parent.powerBar = bar  -- backward compat alias
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
-- The scope key is the SECTION TABLE ITSELF (here: "healthPower", "borders"), the generation
-- key is BF._sectionCfgGen, and the cache is weak-keyed. The full reasoning for
-- all three -- why table identity is the scope, why weak keys and the
-- generation key cover two different section-table lifetimes, and why the
-- generation key rather than the push is what closes the staleness window --
-- is written out once at Indicators/StatusText_Overlay.lua:197-236 and is not
-- repeated in every indicator. In-tree precedent: BFStatus.lua:993-1005 (scope
-- key) and Indicators/HealthText.lua:129/:417 (generation key).
--
-- TWO SECTIONS, so the cache is nested healthPower -> borders. Per-Layout
-- toggles are per SECTION, so two scopes can share one healthPower table while
-- differing in borders; a single-table key would hand the second scope the
-- first one's border inset.
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
function PowerBar:UpdateSettings()
	self._cfgBlocks = nil
end

-- One weak-keyed level of the nested cache. Nested because this indicator
-- reads more than one section, and per-Layout toggles are per SECTION: two
-- scopes can share one section table while differing in another, so a
-- single-table key would hand the second scope the first one's values.
local function _SubCache(t, k)
	local v = t[k]
	if v == nil then
		v = setmetatable({}, _blockCacheMeta)
		t[k] = v
	end
	return v
end

-- Declared ABOVE PowerBar:Layout on purpose: a Lua local is only in scope after
-- its declaration, so a resolver placed below its caller compiles to a nil
-- global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolvePowerBarBlock(parent)
	local hp = BF:GetSectionProfileForFrame("healthPower", parent)
	local bp = BF:GetSectionProfileForFrame("borders", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = PowerBar._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		PowerBar._cfgBlocks = blocks
	end
	blocks = _SubCache(blocks, hp or _NO_SECTION)
	local key = bp or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- RAW PIXELS AND RAW HEIGHT ONLY. Both conversions stay in Layout:
	--   * PixelsToUI multiplies by pixelMult (PixelPerfect.lua:91-93)
	--   * BF:Scale truncates to the pixel grid using the same pixelMult (:83-88)
	-- Both track screen resolution and UI scale, refreshed by RefreshPixelSize,
	-- and NEITHER is bumped by BF._sectionCfgGen. A cached converted value would
	-- survive a resolution or UI-scale change and mis-size the bar. EffectiveBorderPixels
	-- itself is pure config (Container.lua:130-135) and is cached.
	block.borderN     = BF:EffectiveBorderPixels(bp)
	block.powerHeight = (hp and hp.powerBarHeight) or 4

	-- Texture. useCustomPowerBarTexture OFF means the flat white fill, exactly as
	-- before; ResolveBarTexture (PixelPerfect.lua:747) always returns a path.
	block.texture = ((hp and hp.useCustomPowerBarTexture)
	                 and BF:ResolveBarTexture(hp.powerBarTexture))
	                or "Interface\\Buttons\\WHITE8X8"

	-- Background color, resolved to four numbers so Layout allocates nothing and
	-- branches on nothing. The old code's three arms collapse to one here: the
	-- 0.08 gray is both the "no custom color" default and the "custom color on
	-- but no color table" fallback, which is what the original arms computed.
	block.bgA = (hp and hp.powerBarBgOpacity ~= nil) and hp.powerBarBgOpacity or 1.0
	local c = (hp and hp.useCustomPowerBarBgColor) and hp.powerBarBgColor or nil
	block.bgR = c and c.r or 0.08
	block.bgG = c and c.g or 0.08
	block.bgB = c and c.b or 0.08

	return block
end

function PowerBar:Layout(parent)
	local bar = parent[self.name]
	if not bar then return end

	-- The config guard that used to stand here (`if not hp then return end`)
	-- is gone: the block is complete even when neither section resolves, so
	-- Layout has nothing left to decide. Routing by frame -- preview frames to
	-- their own flat, live frames to the active context -- now happens inside
	-- ResolvePowerBarBlock.
	local block = ResolvePowerBarBlock(parent)

	-- EffectiveBorderPixels: rounded border styles use a FIXED art
	-- thickness (2/3px) regardless of the square-border thickness
	-- slider — must match Container:Layout's content inset. Resolved in the
	-- block; converted here, never cached (see the block comment).
	local borderN = block.borderN
	local borderUI = PixelsToUI(borderN)
	-- Always set the full height — visibility is controlled by Update, not Layout.
	-- This prevents a height=0 bar when Layout runs while showPowerBar is off
	-- but a unit later becomes eligible for a power bar.
	local powerH = BF:Scale(block.powerHeight)

	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  borderUI,  borderUI)
	bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -borderUI,  borderUI)
	bar:SetHeight(powerH)

	-- Apply bar texture from profile (Grid2 pattern: Bar_Layout sets self.texture)
	bar:SetStatusBarTexture(block.texture)

	-- Background color from settings (PERF: moved here from Update — it is
	-- pure config, and Update ran it on every UNIT_POWER_UPDATE per unit).
	-- The widget test stays (bg is built separately); the three config arms are
	-- gone -- the block already resolved them to four numbers.
	if bar.bg then
		bar.bg:SetColorTexture(block.bgR, block.bgG, block.bgB, block.bgA)
	end

	-- Fix texture snap
	local tex = bar:GetStatusBarTexture()
	if tex then
		BF:DisablePixelSnapRegion(tex)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
		tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	end
end

-- ============================================================
-- Update: unconditionally overwrite (Grid2 pattern)
-- ============================================================
function PowerBar:Update(parent, unit)
	local bar = parent[self.name]
	if not bar then return end

	-- Pet frames: hide power bar (pets don't show power in raid frames)
	-- v93 (A2): read the cached parent header rather than calling GetParent()
	-- again. Not a meaningful saving on its own -- GetParent is a trivial C
	-- getter, so ~1-3 ms across the 31052 calls in the v93 profile -- but this
	-- function already resolves the header a second way two lines down, via
	-- ShouldShowPowerBar -> GetCachedSection/GetSectionProfileForFrame, both of
	-- which read _bf_parentHeader. One source, populated the same way they do.
	-- The cache stores `header or false`, so nil means "not resolved yet" and
	-- false is a valid "no parent" answer -- test for nil, never truthiness.
	local header = parent._bf_parentHeader
	if header == nil then
		header = parent:GetParent()
		parent._bf_parentHeader = header or false
	end
	if header and header.isPetFrame then
		bar:Hide()
		if bar.bgFrame then bar.bgFrame:Hide() end
		parent._bf_powerBarShown = false
		return
	end

	-- Check power bar visibility with frame awareness for CFG section overrides.
	if not BF:ShouldShowPowerBar(unit, parent) then
		local wasShown = bar:IsShown()
		bar:Hide()
		if bar.bgFrame then bar.bgFrame:Hide() end
		parent._powerColorType = nil
		-- Re-layout container so health bar reclaims the power bar space
		if wasShown then
			local containerInd = BF:GetIndicatorByName("container")
			if containerInd then containerInd:Layout(parent) end
			-- Power bar just disappeared: invalidate aura icon position caches
			-- so ScanAndDisplay re-anchors them to frame instead of
			-- healthBar.clipFrame (when aurasAbovePowerBar is enabled).
			BF:InvalidateAuraPositionCache(parent)
		end
		-- Maintain pre-resolved per-frame visibility flag used by the
		-- unified aura render path (RenderAuraGroup).
		parent._bf_powerBarShown = false
		return
	end

	local wasHidden = not bar:IsShown()
	bar:Show()
	if bar.bgFrame then bar.bgFrame:Show() end
	-- Re-layout container so health bar shrinks to make room
	if wasHidden then
		local containerInd = BF:GetIndicatorByName("container")
		if containerInd then containerInd:Layout(parent) end
		-- Power bar just appeared: invalidate aura icon position caches
		-- so ScanAndDisplay re-anchors them to healthBar.clipFrame
		-- instead of frame (when aurasAbovePowerBar is enabled).
		BF:InvalidateAuraPositionCache(parent)
	end
	-- Maintain pre-resolved per-frame visibility flag used by the
	-- unified aura render path (RenderAuraGroup).
	parent._bf_powerBarShown = true

	-- Background color is applied in Layout (pure config — see there).

	local powerStatus = BF.statuses and BF.statuses.power
	if not powerStatus then return end

	-- PERF: resolve the effective power type ONCE and hand it to the
	-- getters. GetPercent + GetColor each used to recompute it internally
	-- (UnitPowerType + druid class/role probe), so every UNIT_POWER_UPDATE
	-- paid the probe three times per unit.
	local powerType = powerStatus:GetPowerType(unit)

	-- Value from status (nil = inaccessible, keep last value)
	local pct = powerStatus:GetPercent(unit, powerType)
	if pct ~= nil then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(pct)
	end

	-- Color from status.
	-- PERF: power color + alpha depend only on the power TYPE (mana vs
	-- energy etc.), never on the per-tick value, so they change at most on a
	-- power-type / unit swap -- not on every UNIT_POWER_UPDATE. Guard the two
	-- widget writes (and the GetColor -> GetPowerColor lookup behind them) on
	-- the type key this function already maintains, mirroring the oUF side's
	-- _bf_powerCType guard (oUF_Shared.lua Power.PostUpdate). SetValue stays
	-- unconditional above -- the value genuinely changes every tick.
	-- Invalidation of the key: BFLayout clears it on unit recycle, the hide
	-- branch clears it above, and BF:UpdatePower clears it so a custom
	-- power-color settings edit still repaints (same-type refresh).
	if parent._powerColorType ~= powerType then
		parent._powerColorType = powerType
		local r, g, b, a = powerStatus:GetColor(unit, powerType)
		bar:SetStatusBarColor(r, g, b)
		bar:SetAlpha(a or 0.9)
	end
end

BF:RegisterIndicator(PowerBar)
