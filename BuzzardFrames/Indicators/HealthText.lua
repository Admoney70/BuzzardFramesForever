--[[
BuzzardFrames: Indicators/HealthText.lua
Health text indicator — shows current HP as percent/current/deficit.

Grid2 equivalent: IndicatorText.lua bound to StatusHealth.

Each call to Update unconditionally overwrites stale state (Grid2 pattern).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitHealth          = UnitHealth
local UnitHealthMax       = UnitHealthMax
local UnitHealthPercent   = UnitHealthPercent
local UnitHealthMissing   = UnitHealthMissing
local UnitExists          = UnitExists
local UnitClass           = UnitClass
local AbbreviateLargeNumbers = AbbreviateLargeNumbers
local issecretvalue       = issecretvalue or function() return false end
local ScaleTo100          = CurveConstants and CurveConstants.ScaleTo100

local HealthText = BF.indicatorPrototype:new("healthText")

-- v99 PERF: status handles, resolved once. Update re-read
-- `BF.statuses and BF.statuses.health` (and .offline and .death) on every
-- health tick for every frame -- six table lookups x 42,585 calls in a 456 s
-- raid window. Initialization.lua already hoists these exact objects as
-- S_HEALTH / S_POWER / S_ABSORBS; this indicator just never did.
-- Resolved LAZILY, not at file scope: BF.statuses is populated by
-- BF:RegisterStatus as BFStatus.lua loads, which is not guaranteed to have
-- run when this file is parsed. First Update after the statuses exist binds
-- them for the rest of the session (statuses are created once at load and
-- never replaced -- only enabled/disabled, which these handles do not cache).
local S_HEALTH, S_OFFLINE, S_DEATH
local function ResolveStatuses()
	local st = BF.statuses
	if not st then return false end
	S_HEALTH  = st.health
	S_OFFLINE = st.offline
	S_DEATH   = st.death
	return S_HEALTH ~= nil
end

-- ============================================================
-- Create
-- ============================================================
function HealthText:Create(parent)
	-- Skip if already created by legacy InitFrame
	if parent.healthText then
		parent[self.name] = parent.healthText
		return
	end

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
	size  = size  or 10
	flags = flags or ""
	fs.SF_defaultFont  = font
	fs.SF_defaultSize  = size
	fs.SF_defaultFlags = flags
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH("CENTER")

	local hBar = parent.healthBar
	-- Route via GetSectionProfile for the initial position / color read -- Create
	-- is called once per frame, typically early enough that the active context
	-- isn't set yet; fall back to the global via activeFlat=nil.
	local tpInit = BF:GetSectionProfile("text", nil)
	local pos = (tpInit and tpInit.healthTextPosition) or "CENTER"
	local anchor = parent.container or hBar or parent
	fs:SetPoint(pos, anchor, pos, 0, 0)

	local c = (tpInit and tpInit.healthTextColor) or { r = 1, g = 1, b = 1 }
	fs:SetTextColor(c.r, c.g, c.b, c.a or 1)

	parent[self.name] = fs
	parent.healthText = fs  -- backward compat alias
end

-- ============================================================
-- _StampConfig (v94 PERF, Win 4)
-- ============================================================
-- Resolve the text + absorbs section config ONCE and cache it on the frame
-- as _bf_htCfg, so per-tick Update reads plain fields instead of two
-- GetCachedSection calls + a rebuilt percent format + the reduced-max
-- toggle test every UNIT_HEALTH tick. Same source as the old Update path.
-- Staleness is handled exactly like AbsorbBars._absorbStyleGen: _bf_htCfgGen
-- is stamped from BF._sectionCfgGen, which Core_ProfileAPI bumps on every
-- section-cache invalidation (settings edit OR party<->raid context change);
-- Update re-stamps when the two differ. Returns the cfg table, or nil when
-- the text section is unavailable (mirrors the old "not tp" hide path).
function HealthText:_StampConfig(parent)
	local tp = BF:GetCachedSection("text", parent)
	if not tp then parent._bf_htCfg = nil return nil end
	local ab = BF:GetCachedSection("absorbs", parent)

	local cfg = parent._bf_htCfg
	if not cfg then cfg = {} parent._bf_htCfg = cfg end
	cfg.show        = tp.showHealthText and true or false
	cfg.format      = tp.healthTextFormat
	cfg.pctFmt      = (tp.healthTextPctSymbol ~= false) and "%d%%" or "%d"
	cfg.adjustColor = tp.adjustHealthTextColor and true or false
	cfg.classColor  = tp.classColorHealthText and true or false
	local col = tp.healthTextColor
	cfg.colR = col and col.r or 1
	cfg.colG = col and col.g or 1
	cfg.colB = col and col.b or 1
	cfg.colA = col and col.a or 1
	cfg.appendReducedMax = (ab and ab.showReducedMaxHealthText and ab.appendReducedMaxText
	                        and (ab.appendReducedMaxTarget or "health") == "health") and true or false
	local rmc = ab and ab.reducedMaxHealthTextColor
	if rmc then
		cfg.rmR, cfg.rmG, cfg.rmB, cfg.rmA = rmc.r, rmc.g, rmc.b, rmc.a or 1
	else
		cfg.rmR = nil
	end
	parent._bf_htCfgGen = BF._sectionCfgGen or 0
	return cfg
end

-- ============================================================
-- Resolved LAYOUT config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded, into
-- a block the indicator holds (modules/IndicatorText.lua:251), and Layout then
-- writes that block with no decisions left in it (:106). The fallback chain is
-- baked in at RESOLVE time, which is why Layout needs no
-- `if not tp then return end` -- the block handed to it is always complete.
-- See BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- ── WHY THIS IS NOT _bf_htCfg, WHICH ALREADY EXISTS ─────────────────────────
-- This file already carries a generation-keyed cache (_StampConfig above,
-- :104-130), so the obvious move is to let that one absorb the Layout resolve
-- instead of adding a second cache. It cannot, for two independent reasons,
-- and the first is not a style question:
--
--   1. DIFFERENT RESOLVER, DIFFERENT ANSWER. _StampConfig reads through
--      BF:GetCachedSection (Core_ProfileAPI.lua:717). That function handles CFG
--      frames and otherwise falls through to a cache keyed by the ACTIVE game
--      context (:745-754) -- it has NO preview branch. Layout reads through
--      BF:GetSectionProfileForFrame, which resolves a preview frame via its own
--      _flatID (:1267-1271). So on a preview frame the two return DIFFERENT
--      section tables, and merging the caches would silently repoint one
--      consumer at the other's data.
--
--      AUDITED 2026-09-22, and the divergence is currently UNOBSERVABLE --
--      recorded here so nobody re-derives it, and so nobody assumes it is safe
--      for a different reason than it actually is:
--        * the ONLY reader of _bf_htCfg is HealthText:Update (:378-380);
--        * indicator:Update is NEVER dispatched on a preview frame. Preview
--          frames get indicator:Layout (Preview/PreviewSystem.lua:651-660,
--          :744-751) and nothing else -- see that file's own statement at
--          :163-173, "the prototype's Layout() and UpdateIndicators() are never
--          called on preview frames";
--        * preview health text is painted by Preview/PreviewData.lua:494-514,
--          which routes through its own _rp_section (:63-68) and therefore
--          already resolves per flat.
--      So _bf_htCfg is stamped with the active-context answer on preview frames
--      and then never read there. Wrong value, no consumer.
--
--      It is a LATENT TRAP, not a live defect. The day anyone dispatches
--      indicator:Update on preview frames -- e.g. replacing PreviewData's
--      hand-painting with the real Update path, which is an obvious future
--      cleanup -- this divergence goes live in the same commit. Fix it then by
--      swapping _StampConfig's two GetCachedSection calls for
--      GetSectionProfileForFrame. That swap is CHEAP and the "it would put a
--      routing walk on a per-tick path" objection does not apply: since v94
--      Win 4, _StampConfig runs only from Layout and from Update's generation
--      gate (:379), so its cost is once per frame per BF._sectionCfgGen bump,
--      not once per UNIT_HEALTH. The GetCachedSection call is a leftover from
--      the pre-v94 shape, when Update really did resolve per tick.
--
--      (GetSectionProfileForFrame's own header says "use this from ALL
--      indicator methods -- both :Layout and :Update", :1254, so the Update
--      path is the one that deviates. Not changed here: a swap with no reader
--      is cost without benefit, and this change set is a parity fix, not a
--      cleanup of paths it did not touch.)
--   2. DIFFERENT SHAPE. _bf_htCfg is PER FRAME, and must be: it is stamped on
--      `parent` and read by the per-tick Update path (:415-419), which is the v94
--      PERF Win 4 this file exists in its current form for. The Layout block is
--      PER SCOPE -- one table shared by every frame resolving to the same
--      section -- which is the whole point of the Grid2 shape. They also hold
--      disjoint fields: _bf_htCfg has text CONTENT settings (format, percent
--      symbol, reduced-max append, per-unit colors), this block has font and
--      geometry. Neither is a subset of the other.
--
-- So: two caches, same generation idiom, deliberately separate. They are not
-- parallel copies of one thing.
--
-- SCOPE KEY = THE SECTION TABLE ITSELF. Established in-tree pattern:
-- BFStatus.lua:993-1005 memoizes the composed name entry the same way,
-- weak-keyed -- "Frames sharing a flat share one entry; CFG flats get their
-- own." Table identity IS the scope, so there is no scope list to enumerate.
-- `tp == nil` is a scope too and takes the constant key below.
--
-- WEAK KEYS, and the generation key, cover the two lifetimes a section table
-- can have. A per-Layout or per-CFG section resolves to a MERGED VIEW allocated
-- by BuildMergedSectionView and cached at flat._sectionCache[section]
-- (Core_ProfileAPI.lua:1187-1189); invalidation drops that cache, so the next
-- resolve mints a NEW table and a strong key would pin the dead one for the
-- session. The degenerate paths return rpDB.profile[section] itself -- a
-- long-lived AceDB table the options UI mutates IN PLACE (BFStatus.lua:999-1001),
-- whose identity never changes on an edit. That is what the generation key is for.
local _blockCacheMeta = { __mode = "k" }

-- Scope key for "no section profile resolvable for this frame". A table, so it
-- can never collide with a real section table.
local _NO_SECTION = {}

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Implements the hook declared at BFIndicator.lua:62, dispatched by
-- BF:RefreshIndicatorSettings (BFIndicator.lua:332) from LoadLayout on every
-- profile/context switch. Drops the resolved LAYOUT blocks so the next Layout
-- re-resolves.
--
-- Deliberately does NOT touch _bf_htCfg. That cache lives on the frames, not
-- here, and already heals itself through its own generation gate at :205; this
-- indicator has no frame list to walk and does not need one.
--
-- The PUSH half only, and an optimization rather than the correctness
-- guarantee: the generation key in ResolveHealthTextBlock is what makes
-- staleness impossible on the paths that reach indicator:Layout without ever
-- reaching RefreshIndicatorSettings (plan §6.1(b)).
function HealthText:UpdateSettings()
	self._cfgBlocks = nil
end

-- Resolve (or reuse) this frame's LAYOUT block. Declared ABOVE
-- HealthText:Layout on purpose: a Lua local is only in scope after its
-- declaration, so a resolver placed below its caller compiles to a nil global
-- lookup and throws only on the path that reaches it. Tests/check_locals.py
-- exists for that.
local function ResolveHealthTextBlock(parent)
	-- Route by frame: preview frames resolve to their own flat, live frames via
	-- the active game context. See BF:GetSectionProfileForFrame.
	local tp  = BF:GetSectionProfileForFrame("text", parent)
	local key = tp or _NO_SECTION

	-- GENERATION KEY -- the same one _StampConfig stamps at :129 and Update
	-- tests at :205, read from BF._sectionCfgGen. Bumped by
	-- InvalidateRaidProfileCache (Core_ProfileAPI.lua:639) and
	-- _InvalidateSectionViews (:992), which every config-changing
	-- path is REQUIRED to pass through. That is an invariant to KEEP, not an
	-- observation that holds by itself: on 2026-09-23 four writers were found
	-- that reached neither bump site -- the Global Styles text, icons and
	-- borders fan-outs (BuzzardFramesOptions/Pages_GlobalStylesShared.lua) and
	-- the Cast Bars page (Pages_CastBar.lua) -- and each was given the
	-- invalidation it was missing. All four assign into the EXISTING section
	-- table, so the scope key does not move either and the block below froze
	-- with no error of any kind. A new config writer that reaches neither does
	-- exactly the same thing. Re-resolving on a moved generation is what lets Layout write
	-- unconditionally without depending on anyone having remembered to call
	-- UpdateSettings first.
	local gen = BF._sectionCfgGen or 0

	local blocks = HealthText._cfgBlocks
	if blocks == nil then
		blocks = setmetatable({}, _blockCacheMeta)
		HealthText._cfgBlocks = blocks
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
	-- EVERY healthText it builds, from this same chain (:66-68). BF.font is a
	-- file-scope constant (Core.lua:87), never reassigned, so resolving it here
	-- rather than at Create time cannot diverge.
	local baseFont, baseSize, baseFlags
	if GameFontNormalSmall then
		baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
	end
	baseFont  = baseFont  or BF.font or "Fonts\\FRIZQT__.TTF"
	baseSize  = baseSize  or 10
	baseFlags = baseFlags or ""

	-- adjustHealthFont semantics unchanged: ON takes the configured face and
	-- border, OFF takes the default triple whole. BF:ResolveFontPath
	-- (PixelPerfect.lua:656) always returns a path, so fontPath is never nil.
	--
	-- ONE DELIBERATE DELTA: the size gets `or baseSize`. The old line was
	-- `fs:SetFont(fontPath, tp.healthFontSize, tp.healthFontBorder or "")` with
	-- no fallback, so a profile with adjustHealthFont ON and healthFontSize
	-- absent threw inside SetFont. A block that is "complete and usable" is the
	-- point of resolving here (plan §2, property 3), and an incomplete one
	-- cannot be written unconditionally, so the hole is filled with the same
	-- default :Create uses. Behavior is identical wherever the size is set.
	if tp and tp.adjustHealthFont then
		block.fontPath  = BF:ResolveFontPath(tp.healthFont)
		block.fontSize  = tp.healthFontSize or baseSize
		block.fontFlags = tp.healthFontBorder or ""
	else
		block.fontPath  = baseFont
		block.fontSize  = baseSize
		block.fontFlags = baseFlags
	end

	block.point = (tp and tp.healthTextPosition) or "CENTER"
	block.x     = (tp and tp.healthTextX) or 0
	block.y     = (tp and tp.healthTextY) or 0

	-- COLOR is resolved to a three-state instruction, not to a color.
	-- `adjustHealthTextColor` ON together with `classColorHealthText` means the
	-- color is per-UNIT and belongs to Update, so Layout must write NOTHING and
	-- leave whatever Update last painted. That third state is a decision about
	-- WHICH value applies, taken on fully resolved config -- not a "do we have
	-- any config" test -- so it survives the unconditional-write rule intact.
	-- Flattening it into an unconditional SetTextColor would repaint every
	-- class-colored health text over the static color on each Layout.
	local adjust = (tp and tp.adjustHealthTextColor) and true or false
	local class  = (tp and tp.classColorHealthText) and true or false
	block.writeColor = (not adjust) or (adjust and not class)
	if adjust and not class then
		local c = tp.healthTextColor
		block.colR = c and c.r or 1
		block.colG = c and c.g or 1
		block.colB = c and c.b or 1
		block.colA = c and c.a or 1
	else
		block.colR, block.colG, block.colB, block.colA = 1, 1, 1, 1
	end

	return block
end

-- ============================================================
-- Layout
-- ============================================================
function HealthText:Layout(parent)
	local fs = parent[self.name]
	-- Widget-existence guard, NOT a config guard: with no FontString there is
	-- nothing to write to. The config guard that used to follow it
	-- (`if not tp then return end`) is gone -- the block is complete even when
	-- no section profile resolves, so Layout has nothing left to decide.
	if not fs then return end

	local block = ResolveHealthTextBlock(parent)

	-- UNCONDITIONAL WRITE (Grid2 Text_Layout). Font and geometry are written on
	-- every call; this function cannot leave the widget holding its Create-time
	-- defaults. The anchor stays per-frame -- frame state, not config.
	fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)

	local hBar = parent.healthBar
	fs:ClearAllPoints()
	local anchor = parent.container or hBar or parent
	fs:SetPoint(block.point, anchor, block.point, block.x, block.y)

	-- Static color (class color is applied per-unit in Update). See
	-- block.writeColor above for why this one write stays conditional: the
	-- skipped case is "Update owns this color", not "no config".
	if block.writeColor then
		fs:SetTextColor(block.colR, block.colG, block.colB, block.colA)
	end

	-- v94 PERF (Win 4): stamp the per-FRAME text config the per-tick Update path
	-- reads. A separate cache on purpose -- see the block comment above for why
	-- it cannot be folded into the per-scope block.
	HealthText:_StampConfig(parent)
end

-- ============================================================
-- Update: unconditionally overwrite (Grid2 pattern)
-- ============================================================
-- v99: the shared hide path for every early return in Update. Guarded so a
-- dead or offline unit stops paying two widget calls per health tick. Text is
-- cleared only on the transition into hidden; a hidden FontString shows
-- nothing regardless of what it holds, and the show path always rewrites it.
--
-- The guard READS THE WIDGET rather than caching a flag on the frame, and
-- that is deliberate. StatusText_Overlay hides parent.healthText directly at
-- three sites (and the preview data path Shows/Hides it too), all behind this
-- indicator's back. A cached "is shown" flag would go stale the moment the
-- overlay hid it: the flag would still read shown, the show path below would
-- skip its Show(), and the health text would stay invisible until something
-- unrelated reset it. IsShown() is a plain C getter, not a secret value, and
-- it is also immune to frame recycling -- no reset hook to remember anywhere.
local function HideText(fs)
	if fs:IsShown() then
		fs:SetText("")
		fs:Hide()
	end
end

function HealthText:Update(parent, unit)
	local fs = parent[self.name]
	if not fs then return end

	-- v94 PERF (Win 4): read stamped per-frame config instead of two
	-- GetCachedSection calls per tick. Gen gate (mirrors AbsorbBars): re-
	-- stamp when the frame cfg is missing or BF._sectionCfgGen has moved
	-- (any settings edit or party<->raid context change bumps it).
	local cfg = parent._bf_htCfg
	if cfg == nil or parent._bf_htCfgGen ~= (BF._sectionCfgGen or 0) then
		cfg = HealthText:_StampConfig(parent)
	end

	-- Read from statuses instead of WoW APIs directly (v99: hoisted upvalues).
	local healthStatus = S_HEALTH
	if healthStatus == nil and ResolveStatuses() then healthStatus = S_HEALTH end
	local offlineStatus, deathStatus = S_OFFLINE, S_DEATH

	-- Grid2 pattern: always overwrite — decide visibility fresh every call
	if not cfg or not cfg.show or not unit
	   or not healthStatus or not healthStatus:IsActive(unit) then
		HideText(fs)
		return
	end

	local maxHealth = healthStatus:GetMaxHealth(unit)
	-- Hide when maxHealth is 0 (unit data not yet available)
	if not issecretvalue(maxHealth) and maxHealth <= 0 then
		HideText(fs)
		return
	end

	-- Dead/offline units: hide health text (other indicators own the dead/offline display)
	if offlineStatus and offlineStatus:IsActive(unit) then
		HideText(fs)
		return
	end
	if deathStatus and deathStatus:IsActive(unit) then
		HideText(fs)
		return
	end

	-- v99 PERF: transition-gated (see HideText for why this reads the widget
	-- instead of caching). Show() ran unconditionally on every health tick, and
	-- each hide path paid SetText("") + Hide() every tick for as long as a unit
	-- stayed dead or offline.
	if not fs:IsShown() then
		fs:Show()
	end

	-- Color: always set the normal health text color (mirrors NameText pattern).
	-- This ensures the color is restored every Update cycle, so transient
	-- overrides (e.g. reduced max health) don't persist once the status clears.
	if cfg.adjustColor and cfg.classColor then
		local className = healthStatus:GetClass(unit)
		if className and BF.classColors and BF.classColors[className] then
			local c = BF.classColors[className]
			fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
		end
	elseif cfg.adjustColor then
		fs:SetTextColor(cfg.colR, cfg.colG, cfg.colB, cfg.colA)
	else
		fs:SetTextColor(1, 1, 1)
	end

	-- Format: read values from health status
	local fmt = cfg.format
	local baseText
	if fmt == "percent" then
		baseText = string.format(cfg.pctFmt, healthStatus:GetPercentText(unit))
	elseif fmt == "current" then
		baseText = healthStatus:GetCurrentText(unit)
	elseif fmt == "deficit" then
		baseText = "-" .. healthStatus:GetMissingText(unit)
	end

	-- Append reduced max health text if option is enabled and target is health
	local _reducedMaxAppendedToHealth = false
	local rPct = parent._reducedMaxPct
	if baseText and cfg.appendReducedMax
	   and rPct and not issecretvalue(rPct) and rPct > 0 then
		local remainPct = math.floor((1 - rPct) * 100 + 0.5)
		baseText = baseText .. string.format(" (%d%%)", remainPct)
		_reducedMaxAppendedToHealth = true
	end

	-- Set the final text (base, or base + reduced max suffix)
	if baseText then
		fs:SetText(baseText)
	end

	-- Override color with reduced max health text color if appended
	if _reducedMaxAppendedToHealth and cfg.rmR then
		fs:SetTextColor(cfg.rmR, cfg.rmG, cfg.rmB, cfg.rmA)
	end
end

BF:RegisterIndicator(HealthText)
