--[[
BuzzardFrames: Indicators/HealthBar.lua
Health bar indicator — modular, mirrors Grid2's IndicatorBar.lua pattern.

Creates a StatusBar on each frame, positions it inside the container,
and updates it from UnitHealth / UnitHealthMax.

Depends on: BFIndicator.lua (framework), PixelPerfect.lua (pixel math)
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitHealthPercent  = UnitHealthPercent

-- ============================================================
-- Create indicator object
-- ============================================================
local HealthBar = BF.indicatorPrototype:new("healthBar")


-- ============================================================
-- Create: build the StatusBar widget on a frame
-- Grid2 equivalent: Bar_CreateHH in IndicatorBar.lua
-- ============================================================
function HealthBar:Create(parent)
	-- Container must exist (created by the container indicator or InitFrame)
	local container = parent.container
	if not container then return end

	-- Skip if already created by legacy InitFrame
	if parent.healthBar then
		parent[self.name] = parent.healthBar
		return
	end

	-- Clip frame: used as anchor reference by aura icons, reduced max
	-- health, and other elements that need the visible health bar bounds.
	local healthClip = CreateFrame("Frame", nil, parent)
	healthClip:SetAllPoints(container)
	healthClip:SetClipsChildren(true)

	local bar = BF.StatusBar(nil, healthClip)
	bar.indicator = self
	bar:EnableMouse(false)
	BF:DisablePixelSnapRegion(bar)
	bar:SetAllPoints(healthClip)
	-- Disable bar value interpolation (smoothing) so the fill snaps
	-- instantly to its new value. Matches oUF's health element default
	-- (Enum.StatusBarInterpolation.Immediate). Without this, the fill
	-- texture animates while the bg (anchored to the fill's right edge)
	-- can fall behind by sub-pixel amounts during the animation,
	-- producing a visible black seam at the fill/bg boundary.
	if bar.SetValueInterpolation and Enum and Enum.StatusBarInterpolation then
		bar:SetValueInterpolation(Enum.StatusBarInterpolation.Immediate)
	end
	local _p = BF.db and BF.db.profile
	local hbTex = (_p and _p.useCustomHealthBarTexture) and BF:ResolveBarTexture(_p.healthBarTexture) or "Interface\\Buttons\\WHITE8X8"
	bar:SetStatusBarTexture(hbTex)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	-- Background texture behind the bar.
	-- Grid2 pattern (IndicatorBar.lua Bar_Layout): anchor bg to the UNFILLED
	-- portion of the bar only, so bg and fill never overlap. This makes their
	-- opacities truly independent — a translucent fill won't show the bg
	-- bleeding through underneath it.
	local bg = BF.Texture(bar, nil, "BACKGROUND")
	bg:SetColorTexture(0.08, 0.08, 0.08, 1)
	bar.bg = bg
	-- Anchors are set in Layout (need the fill texture reference)

	bar.clipFrame = healthClip
	parent[self.name] = bar
	parent.healthBar = bar   -- alias for backward compat with existing BF code
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
-- The scope key is the SECTION TABLE ITSELF (here: "healthPower"), the generation
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
function HealthBar:UpdateSettings()
	self._cfgBlocks = nil
end

-- Declared ABOVE HealthBar:Layout on purpose: a Lua local is only in scope
-- after its declaration, so a resolver placed below its caller compiles to a
-- nil global lookup and throws only on the path that reaches it.
-- Tests/check_locals.py exists for that.
local function ResolveHealthBarBlock(parent)
	local hp = BF:GetSectionProfileForFrame("healthPower", parent)
	local gen = BF._sectionCfgGen or 0

	local blocks = HealthBar._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		HealthBar._cfgBlocks = blocks
	end
	local key = hp or _NO_SECTION

	local block = blocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = {}
		blocks[key] = block
	end
	block.gen = gen

	-- Texture. useCustomHealthBarTexture OFF means the flat white fill, exactly
	-- as before; ResolveBarTexture (PixelPerfect.lua:747) always returns a path.
	block.texture = ((hp and hp.useCustomHealthBarTexture)
	                 and BF:ResolveBarTexture(hp.healthBarTexture))
	                or "Interface\\Buttons\\WHITE8X8"

	-- BACKGROUND MODE, resolved to one enum plus the numbers each mode needs.
	-- The three-way branch in Layout is a decision about WHICH value applies,
	-- taken on fully resolved config -- not a "do we have config" test -- so it
	-- survives the unconditional-write rule and is simply moved here:
	--
	--   "gradient"  alpha is written per-tick by the HealthBarColor sidekick
	--               from the curve, so frame alpha stays 1 and the color is
	--               initialized neutral for the first frame.
	--   "class"     color is class-driven by the same sidekick; the alpha slider
	--               still applies, color initialized neutral.
	--   "solid"     the configured (or black) color at the slider's alpha.
	--
	-- Every arm ends up writing both a color and an alpha, so Layout below has no
	-- branch left that can skip a widget write.
	block.bgAlpha = (hp and hp.backgroundAlpha) or 1
	if hp and hp.useCustomBackgroundColor then
		if hp.useBgGradient then
			block.bgMode = "gradient"
		elseif hp.useBgClass then
			block.bgMode = "class"
		else
			block.bgMode = "solid"
			local c = hp.backgroundColor
			block.bgR = c and c.r or 0
			block.bgG = c and c.g or 0
			block.bgB = c and c.b or 0
		end
	else
		-- No custom background color: opaque black at the slider's alpha. This is
		-- also the arm a frame with NO healthPower section takes -- which is the
		-- same thing the OLD `else` arm wrote, so behavior is unchanged. It is NOT
		-- what :Create leaves showing: that is 0.08 gray (:68). An earlier draft of
		-- this comment claimed the two matched; they do not, and nothing depends on
		-- their matching.
		block.bgMode = "solid"
		block.bgR, block.bgG, block.bgB = 0, 0, 0
	end

	return block
end

-- ============================================================
-- Layout: position and size the health bar within the frame
-- Grid2 equivalent: Bar_Layout in IndicatorBar.lua
-- ============================================================
function HealthBar:Layout(parent)
	local bar = parent[self.name]
	if not bar then return end

	local container = parent.container
	if not container then return end

	-- The config guard that used to stand here (`if not hp then return end`)
	-- is gone: the block is complete even when no healthPower section resolves,
	-- so Layout has nothing left to decide. Routing by frame -- preview frames
	-- to their own flat, live frames to the active context -- now happens inside
	-- ResolveHealthBarBlock. The two guards ABOVE stay: both are
	-- widget-existence tests, and the container one is load-bearing -- the bar
	-- is anchored to it.
	local block = ResolveHealthBarBlock(parent)

	if bar.clipFrame then
		bar.clipFrame:ClearAllPoints()
		bar.clipFrame:SetAllPoints(container)
	end
	-- Fill the container (which already overlaps the border slightly
	-- via Container:Layout to prevent subpixel rounding gaps).
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", bar.clipFrame or container, "TOPLEFT")
	bar:SetPoint("BOTTOMRIGHT", bar.clipFrame or container, "BOTTOMRIGHT")
	bar:SetFrameLevel(parent:GetFrameLevel() + 1)

	-- Apply bar texture from profile (Grid2 pattern: Bar_Layout sets self.texture)
	bar:SetStatusBarTexture(block.texture)

	-- Grid2 does NOT re-anchor the fill texture with ClearAllPoints — the
	-- StatusBar widget must own tex's anchor points so that SetValue can
	-- dynamically size the fill. Re-anchoring tex to span the full bar
	-- would lock its right edge and break the bg anchoring below.
	-- Grid2 also does NOT disable pixel snapping on the fill texture;
	-- doing so causes sub-pixel artifacting at the fill/bg boundary
	-- (a black seam between the fill's right edge and the bg's left
	-- edge). The unit frames' health bars match Grid2's pattern and
	-- don't exhibit the issue.
	local tex = bar:GetStatusBarTexture()

	-- Background color and anchoring from profile.
	-- Grid2 pattern (IndicatorBar.lua Bar_Layout): anchor bg to the UNFILLED
	-- region only so it never overlaps the fill texture. For HORIZONTAL
	-- normal fill (left-to-right), the fill texture's right edge is the
	-- bg's left edge; the bar's right edge is the bg's right edge.
	-- Grid2.AlignPoints HORIZONTAL [true] = {"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}
	--
	-- Grid2 also places bgTex one sublayer below the fill texture (same
	-- draw layer) so they render in the correct order.
	if bar.bg then
		if tex then
			local layer, sublayer = tex:GetDrawLayer()
			bar.bg:SetDrawLayer(layer, sublayer - 1)
			bar.bg:ClearAllPoints()
			-- Overlap the bg 2 physical pixels UNDER the fill's right edge.
			-- StatusBar fill width is set via SetValue and lands at sub-pixel
			-- positions for most health values. With pixel-grid snapping the
			-- fill and bg may round in opposite directions, leaving a 1-pixel
			-- uncovered seam where the parent shows through. A 2-pixel
			-- overlap is enough to cover the worst-case round-up of bg
			-- combined with round-down of fill. Since bg is at sublayer-1
			-- the fill covers the overlap when fill alpha is 1.
			local seamOverlap = BF.PixelsToUI and BF:PixelsToUI(2) or 2
			bar.bg:SetPoint("TOPLEFT",     tex, "TOPRIGHT",     -seamOverlap, 0)
			bar.bg:SetPoint("BOTTOMLEFT",  tex, "BOTTOMRIGHT",  -seamOverlap, 0)
			-- bg TOPRIGHT → bar TOPRIGHT (bg extends to bar edge)
			bar.bg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
			-- bg BOTTOMRIGHT → bar BOTTOMRIGHT
			bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
		end
		-- Mode resolved in the block; the arms below are the widget writes only.
		if block.bgMode == "gradient" then
			-- Gradient mode: alpha comes from the curve per-tick.
			-- Frame-level SetAlpha stays at 1 so the curve's per-stop
			-- alpha is the final rendered alpha (not multiplied by
			-- the backgroundAlpha slider).
			bar.bg:SetAlpha(1)
			-- Color is set per-tick by the HealthBarColor indicator;
			-- initialize to a neutral value for the first frame.
			bar.bg:SetColorTexture(0, 0, 0, 0)
		elseif block.bgMode == "class" then
			-- Class mode: color is class-driven and set by the
			-- HealthBarColor sidekick when class data is available
			-- (it is statically bound to the `classcolor` status, so
			-- no per-tick UNIT_HEALTH cost). The backgroundAlpha slider
			-- still controls alpha, so apply it here; initialize the
			-- color to neutral for the first frame before class data.
			bar.bg:SetAlpha(block.bgAlpha)
			bar.bg:SetColorTexture(0, 0, 0, 0)
		else
			-- Solid. The two old solid arms -- "custom color on, gradient and
			-- class both off" and "custom color off" -- are one arm now: the
			-- block resolved the second to black, which is exactly what the
			-- second arm hardcoded, so the branch had nothing left to decide.
			bar.bg:SetColorTexture(block.bgR, block.bgG, block.bgB, 1)
			bar.bg:SetAlpha(block.bgAlpha)
		end
	end

	bar:Show()
end

-- GetClassHealthColor lives in BFStatus.lua (single definition).
-- It takes (r, g, b, hasCustomTexture) and conditionally applies a
-- brightness/desaturation curve. When a custom bar texture is active
-- the darkening is skipped so the texture's own shading isn't
-- compounded with the color math.

-- ============================================================
-- Update: refresh bar VALUE for the given unit.
-- Grid2 equivalent: Bar_OnUpdate in IndicatorBar.lua.
--
-- Perf 3B: this indicator is now VALUE-ONLY. Color work moved to
-- the HealthBarColor sidekick (below). Bound to the `health` status
-- for UNIT_HEALTH / UNIT_MAXHEALTH; also bound to `offline` and `death`
-- for the "reset bar to 0" transitions, since StatusOverlay overwrites
-- the bar value during those states and needs the value path to reset
-- on exit. Flags binding dropped (AFK doesn't change value).
-- ============================================================
function HealthBar:Update(parent, unit)
	local bar = parent[self.name]
	if not bar then return end

	-- Read from health status instead of WoW API directly
	local healthStatus = BF.statuses and BF.statuses.health

	-- Grid2 pattern: always overwrite — no early bail on missing unit.
	if not unit or not healthStatus or not healthStatus:IsActive(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		return
	end

	-- v94 PERF (Win 3): normalized 0..1 bar. Feed the fraction from
	-- healthStatus:GetPercent (UnitHealthPercent -- a C getter that is
	-- secret-safe, the same source Grid2's IndicatorBar and every other
	-- bar in this addon use). The bar's min/max is a constant (0,1), set
	-- once in Create and re-asserted by every StatusText_Overlay pass, so
	-- there is no per-tick SetMinMaxValues here and no absolute max that can
	-- fall out of sync with the overlay on the death/offline handoff -- the
	-- coupling that the earlier gen-counter idea would have had to manage.
	bar:SetValue(healthStatus:GetPercent(unit))
end

-- ============================================================
-- Register with the framework
-- ============================================================
BF:RegisterIndicator(HealthBar)


-- ============================================================
-- HealthBarColor: color sidekick (Perf 3B / Grid2 BarColor pattern)
--
-- Grid2 equivalent: BarColor in IndicatorBar.lua. A sidekick indicator
-- that shares the HealthBar's widget (parent.healthBar) and only writes
-- color, never value. Bound to:
--   * classcolor (UNIT_PORTRAIT_UPDATE + fg-color setting flips) -- static
--   * offline / death / flags (state-driven color handoff to StatusOverlay) -- static
--   * health (UNIT_HEALTH) -- DYNAMIC, only when useHealthGradient or
--     useBgGradient is ON (see BF:RebindHealthBarColor in BFStatus.lua)
--
-- When both gradients are OFF (the common default), this indicator does
-- NOT fire on UNIT_HEALTH. UNIT_HEALTH only drives the HealthBar value
-- update, which skips all color/profile/class-lookup work. This is the
-- main performance win of 3B.
--
-- Create and Layout are no-ops: the widget is owned by HealthBar.
-- Grid2 uses Grid2.Dummy for the same reason in BarColor.
-- ============================================================
local HealthBarColor = BF.indicatorPrototype:new("healthBarColor")

function HealthBarColor:Create(parent) end
function HealthBarColor:Layout(parent) end
-- Sidekick: no widget of its own. Disable/Release are no-ops because the
-- bar widget is owned by HealthBar and cleaned up via its indicator.
function HealthBarColor:Disable(parent) end
function HealthBarColor:Release(parent) end
function HealthBarColor:GetFrame(parent) return parent.healthBar end

function HealthBarColor:Update(parent, unit)
	local bar = parent.healthBar
	if not bar then return end

	local healthStatus = BF.statuses and BF.statuses.health

	-- Grid2 pattern: always overwrite on missing-unit.
	if not unit or not healthStatus or not healthStatus:IsActive(unit) then
		bar:SetStatusBarColor(0, 0, 0, 0)
		parent.cachedHealthR = nil
		parent.cachedHealthG = nil
		parent.cachedHealthB = nil
		parent._cachedClassName = nil
		return
	end

	-- Offline/dead units: bar color is owned by StatusOverlay.
	-- Skip the color work here so SetStatusBarColor isn't overwritten.
	-- (This is called by the offline/death status bindings to clear
	-- the cached color state on transition; StatusOverlay runs after
	-- and paints the correct state.)
	local offlineStatus = BF.statuses and BF.statuses.offline
	if offlineStatus and offlineStatus:IsActive(unit) then
		parent.cachedHealthR = nil
		return
	end
	local deathStatus = BF.statuses and BF.statuses.death
	if deathStatus and deathStatus:IsActive(unit) then
		parent.cachedHealthR = nil
		return
	end

	local hp = BF:GetCachedSection("healthPower", parent)
	if not hp then return end

	local newR, newG, newB, newA = healthStatus:GetColor(unit, parent)
	parent._cachedClassName = healthStatus:GetClass(unit)

	-- Gradient mode: Health:GetColor returns per-stop alpha interpolated
	-- from the curve, replacing the healthBarOpacity slider for that
	-- mode. Other modes pass alpha=1, in which case the slider applies.
	local fillAlpha = (hp.useCustomHealthColor and hp.useHealthGradient)
		and newA
		or (hp.healthBarOpacity or 1)
	bar:SetStatusBarColor(newR, newG, newB, fillAlpha)

	-- Background gradient: update bar.bg color based on health %.
	-- Uses a color curve evaluated by UnitHealthPercent (secret-safe).
	-- Grid2 ref: StatusHealth.lua Health:GetColor with colorCurve.
	if bar.bg and hp.useCustomBackgroundColor and hp.useBgGradient then
		-- Gradient colors are global; always use the single global curve.
		local bgCurve = BF.bgGradientCurve
		if bgCurve then
			local cr, cg, cb, ca = UnitHealthPercent(unit, true, bgCurve):GetRGBA()
			bar.bg:SetColorTexture(cr, cg, cb, ca)
		end
	elseif bar.bg and hp.useCustomBackgroundColor and hp.useBgClass then
		-- Class mode: paint the background with the unit's class color.
		-- Always darkened (hasCustomTexture=false) regardless of the health
		-- bar's own texture toggle -- the background is a plain color
		-- texture, not a StatusBar, so it has no texture of its own.
		-- This runs via the `classcolor` binding (class data arrival /
		-- profile flips), NOT per UNIT_HEALTH, so there is no per-tick cost.
		-- Frame-level alpha (backgroundAlpha) is set in HealthBar:Layout.
		local cr, cg, cb = healthStatus:GetClassColor(unit, false)
		-- Background Darkening: multiply RGB toward black by the slider.
		local d = 1 - (hp.bgClassDarken or 0)
		bar.bg:SetColorTexture(cr * d, cg * d, cb * d, 1)
	end
end

BF:RegisterIndicator(HealthBarColor)
