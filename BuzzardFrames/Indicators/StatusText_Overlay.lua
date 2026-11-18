-- ============================================================
-- BuzzardFrames: Indicators/StatusOverlay.lua
-- Status overlay — a dark overlay shown when the unit is dead or offline.
-- Also owns the statusText FontString for Dead/Offline/AFK labels.
--
-- STATELESS. Every call repaints from the statuses alone: offline and
-- death are read through their status objects, never from the unit APIs
-- and never from per-frame render memory. This indicator keeps no
-- transition bookkeeping of its own, so no dispatch order or forced
-- "re-evaluate" flag can make it paint the wrong state.
--
-- What it owns: the overlay texture, the statusText label, the name text
-- in append mode, and the transient absorb/heal-prediction suppression.
-- What it does NOT own: the health bar VALUE (HealthBar) and the health
-- text (HealthText). Those indicators are bound to death/offline/flags
-- themselves, so they repaint on the same transitions without being
-- cross-called from here.
--
-- Offline has highest priority: when active it owns the visuals and the
-- dead/AFK pass does not run.
-- ============================================================

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitName            = UnitName
local issecretvalue  = issecretvalue  or function() return false end

-- ============================================================
-- Helpers
-- ============================================================
local function IsOutOfRange(v)
	return not issecretvalue(v) and v == false
end

-- ============================================================
-- getTextProfile / getHealthPowerProfile: when a frame is provided,
-- route through GetSectionProfileForFrame for CFG awareness.
-- When no frame is given (or for normal RP frames), use the cached
-- section profile (Perf 1A). Invalidated by
-- InvalidateRaidProfileCache on every context change.
-- See Core_ProfileAPI.lua:GetCachedSection for the full contract.
-- Return nil until the first invalidation completes if rpDB is not
-- ready; callers handle nil.
-- ============================================================
local function getTextProfile(frame)
	return BF:GetCachedSection("text", frame)
end

local function getHealthPowerProfile(frame)
	return BF:GetCachedSection("healthPower", frame)
end

-- ============================================================
-- Status label lookup: pre-stored normal and uppercase versions.
-- GetStatusLabel reads capitalizeStatusText live each call — no
-- cache invalidation needed.
-- ============================================================
local _statusLabels = {
	["Dead"]    = { normal = "Dead",    upper = "DEAD"    },
	["Ghost"]   = { normal = "Ghost",   upper = "GHOST"   },
	["Offline"] = { normal = "Offline", upper = "OFFLINE" },
	["Off"]     = { normal = "Off",     upper = "OFF"     },
	["AFK"]     = { normal = "AFK",     upper = "AFK"     },
}

local function GetStatusLabel(label, frame)
	local entry = _statusLabels[label]
	if entry then
		local tp = getTextProfile(frame)
		return (tp and tp.capitalizeStatusText) and entry.upper or entry.normal
	end
	-- Fallback for unknown labels
	local tp = getTextProfile(frame)
	return (tp and tp.capitalizeStatusText) and label:upper() or label
end

-- ============================================================
-- Name text helper: SetText without collapsing width.
-- ============================================================
local function SetNameText(frame, text)
	-- REFACTOR (plan D1): the parent._nameFont*/_nameWidth snapshot replay is
	-- gone — those fields no longer exist. Font and width are owned by
	-- NameText:Layout and persist on the FontString; SetText resets neither.
	frame.nameText:SetText(text)
end

local function ApplyNameCase(name, frame)
	local tp = getTextProfile(frame)
	if tp and tp.capitalizeNames and name and not issecretvalue(name) then
		return name:upper()
	end
	return name
end

-- ============================================================
-- AppendStatus: combine name + status label using chosen format.
-- ============================================================
local function AppendStatus(baseName, label, frame)
	-- Secret guard: concatenation on a secret string throws, so a secret
	-- name cannot be composed with a status label at all. Return it
	-- uncomposed — the name still renders, and the status state is already
	-- conveyed by the dark overlay / health bar. Matches the secret
	-- pass-through behavior of NameText:Update.
	if issecretvalue(baseName) then return baseName end
	local tp = getTextProfile(frame)
	baseName = ApplyNameCase(baseName, frame)
	label    = GetStatusLabel(label, frame)
	local sep    = tp and tp.statusAppendSeparator or "PAREN"
	local before = tp and tp.statusBeforeName
	if sep == "PAREN_NOSPACE" then
		return before and ("(" .. label .. ")" .. baseName) or (baseName .. "(" .. label .. ")")
	elseif sep == "BRACKET" then
		return before and ("[" .. label .. "] " .. baseName) or (baseName .. " [" .. label .. "]")
	elseif sep == "BRACKET_NOSPACE" then
		return before and ("[" .. label .. "]" .. baseName) or (baseName .. "[" .. label .. "]")
	elseif sep == "NAME_DASH_STATUS" then
		return before and (label .. " - " .. baseName) or (baseName .. " - " .. label)
	elseif sep == "NAME_NODASH" then
		return before and (label .. "-" .. baseName) or (baseName .. "-" .. label)
	elseif sep == "NAME_COMMA" then
		return before and (label .. ", " .. baseName) or (baseName .. ", " .. label)
	elseif sep == "NAME_COMMA_NOSPACE" then
		return before and (label .. "," .. baseName) or (baseName .. "," .. label)
	else -- PAREN (default)
		return before and ("(" .. label .. ") " .. baseName) or (baseName .. " (" .. label .. ")")
	end
end

local function GetUnitBaseName(unit, p)
	local nameUnit = BF.owner_of_unit and BF.owner_of_unit[unit] or unit
	local baseName = UnitName(nameUnit) or "?"
	if BF.isForever and p and p.showLastName then baseName = BF.Forever.UnitNameWithSurname(nameUnit) or "?" end -- [FOREVER] Show Last Name
	-- Secret guard: find/#/sub on a secret string throws. Non-player names
	-- can be secret in 12.0, and append mode routes every dead/offline/AFK
	-- unit's name through here. Return the secret untouched.
	if issecretvalue(baseName) then return baseName end
	local dash = baseName:find("-")
	if dash then baseName = baseName:sub(1, dash - 1) end
	if p and p.abbreviateNames and #baseName > (p.maxNameChars or 99) then
		baseName = baseName:sub(1, p.maxNameChars)
	end
	return baseName
end

-- ============================================================

-- ============================================================
-- Status label visibility  (Grid2 parity: IndicatorText.lua)
-- ============================================================
-- Grid2 never Hide()/Show()s a text indicator's FontString on the update
-- path. Text_Create gives each text indicator its OWN container frame with
-- the FontString inside it; Text_Layout sets the font and then calls
-- Text:Show() and Frame:Show(), so both stay shown for the indicator's life;
-- every update function toggles visibility with Frame:SetAlpha(1) /
-- Frame:SetAlpha(0) (Text_OnUpdate, Text_OnUpdateS, Text_OnUpdateP,
-- Text_OnUpdateDE). Only Text_Disable calls Text:Hide().
--
-- The status label used to live directly on the shared textFrame and be
-- switched with statusText:Hide() / :Show(). Owner report 2026-09-24: after a
-- zone / group change a label that went hidden -> shown came up in its
-- Create-time font (PT Sans Narrow at GameFontNormalSmall's size) although
-- Layout had set and stamped the configured font on that same FontString
-- (/bf statusdiag: saved 15, now 10.80); labels already showing kept theirs.
-- No Lua writer in the addon produces those values after Create, so the
-- label now follows Grid2's pattern exactly: parent.statusTextFrame is the
-- container, Layout keeps both shown, and this helper is the ONLY visibility
-- channel. The label's own alpha stays free for the offline fade.
--
-- WRITE-ONLY, like Grid2: nothing reads the container's alpha back. Writers
-- set the label's text, color and fade alpha unconditionally; the container
-- alpha alone decides whether any of it is visible. Do NOT add a reader --
-- on 12.1 GetAlpha() on this container can return a SECRET number, and
-- comparing it throws (field report 2026-10-01, a removed IsStatusTextShown).
--
-- Every writer outside this file (the preview painter) must go through this
-- too -- a direct statusText:Hide() would park the label hidden underneath an
-- alpha-1 container, and Layout's Show() would resurrect it.
local function SetStatusTextShown(parent, shown)
	local f = parent.statusTextFrame
	if f then f:SetAlpha(shown and 1 or 0) end
end

BF.SetStatusTextShown = SetStatusTextShown

local StatusOverlay = BF.indicatorPrototype:new("statusOverlay")

-- ============================================================
-- Create
-- ============================================================
function StatusOverlay:Create(parent)
	-- Overlay texture
	if not parent.statusOverlay then
		local textFrame = parent.textFrame
		if not textFrame then
			textFrame = CreateFrame("Frame", nil, parent)
			textFrame:SetAllPoints(parent)
			textFrame:SetFrameLevel(parent:GetFrameLevel() + 216)
			textFrame:EnableMouse(false)
			parent.textFrame = textFrame
		end

		local overlay = BF.Texture(textFrame, nil, "OVERLAY", nil, -1)
		overlay:SetAllPoints(parent.healthBar or parent)
		overlay:SetColorTexture(0.1, 0.1, 0.1, 0.7)
		overlay:Hide()
		parent.statusOverlay = overlay
	end

	-- Status text FontString, in its own container (Grid2 Text_Create: one
	-- frame per text indicator, FontString inside it). Container alpha is the
	-- visibility channel -- see SetStatusTextShown above. Starts at 0 so a
	-- frame with no status never flashes a label.
	if not parent.statusText then
		local textFrame = parent.textFrame
		local statusFrame = CreateFrame("Frame", nil, textFrame)
		statusFrame:SetAllPoints(textFrame)
		statusFrame:EnableMouse(false)
		statusFrame:SetAlpha(0)
		parent.statusTextFrame = statusFrame
		local fs = statusFrame:CreateFontString(nil, "OVERLAY")
		fs:SetFontObject(GameFontNormalSmall)
		local font, size, flags = fs:GetFont()
		font  = BF.font or font or "Fonts\\FRIZQT__.TTF"
		size  = size  or 10
		flags = flags or ""
		fs:SetFont(font, size, flags)
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetPoint("CENTER", parent.container or parent.healthBar or parent, "CENTER", 0, 0)
		fs:SetTextColor(0.8, 0.1, 0.1)
		fs.SF_defaultFont  = font
		fs.SF_defaultSize  = size
		fs.SF_defaultFlags = flags
		parent.statusText = fs
	end

	parent[self.name] = parent.statusOverlay
end

-- ============================================================
-- Status text config: ONE block per SCOPE, never per frame  (2026-11-17)
-- ============================================================
-- Owner rule (2026-11-17): status text font and position are dictated by the
-- scope's Layout and are IDENTICAL on every frame of that scope. The scopes:
--
--   _MAIN_SCOPE    every regular party/raid frame (and pet frames / twins,
--                  which resolve through the same active Layout). Its config
--                  is the ACTIVE Layout's text section.
--   grp (table)    one Custom Frame Group. Its config is that group's text
--                  section: its own Status Text override when on, else the
--                  active Layout's values (GetCFGSectionProfile decides).
--
-- Field report that prompted this: one party member's status text showed at
-- a different size from the rest. The previous design resolved config PER
-- FRAME at the moment that frame's Layout ran, against live state, and
-- relied on every config path remembering to re-Layout every frame. Each
-- path swept a different set of frames, so one frame could hold a value its
-- siblings did not. The structure below removes the per-frame decision:
--
--   1. A scope's block is (re)resolved ONLY by RunScopePass, and that same
--      pass re-applies the block to EVERY registered frame of the scope
--      (spares included) whose applied stamp does not match. A block value
--      can therefore never change without all of its frames changing with it.
--   2. Frames never resolve config. Layout looks up the frame's scope (by its
--      header) and writes that scope's block -- the same table every sibling
--      wrote.
--   3. Scopes are laid out separately: a pass re-applies only frames whose
--      scope block actually changed, so a Custom Frame Group edit touches
--      that group's frames alone, and an active-Layout change touches the
--      regular frames plus any group following the active Layout.
--
-- Grid2 reference: Text_UpdateDB resolves the indicator config once and
-- Grid2Frame:LayoutFrames (GridFrame.lua:403) re-Layouts every frame of every
-- header on a theme/profile change. RunScopePass is that sweep, run per scope
-- and change-guarded so it is no more expensive than Grid2's (one compare per
-- frame; SetFont/SetPoint only on frames whose scope moved).
--
-- TRIGGERS. The pass is marked dirty and scheduled for the next frame by
-- BF:ScheduleStatusTextPass, which is called from:
--   * both BF._sectionCfgGen bump sites (InvalidateRaidProfileCache and
--     _InvalidateSectionViews, Core_ProfileAPI.lua) -- every config edit and
--     every context / flat change goes through one of them;
--   * header scope changes that do NOT bump the generation: a Custom Frame
--     Group header being assigned its group (AddCustomFrameHeaders) or reset
--     for reuse (BFHeaderClass.prototype:Reset), BFLayout.lua.
-- Layout ALSO runs the pass synchronously first whenever it is dirty or the
-- generation moved, so a Layout can never write a block that is about to be
-- replaced for its siblings.
--
-- Options PREVIEW frames are not live frames and are not registered; they
-- keep the per-frame resolver below (ResolvePreviewBlock) so a preview shows
-- the Layout / group being edited, which need not be the active one.

-- Fill `block` from a text section profile. Returns true if any value moved.
-- The default chain is spelled out literally (not read off a FontString) so
-- the block never depends on per-frame state. It equals what Create stamps:
-- BF.font or GameFontNormalSmall's font or FRIZQT, its size or 10, its flags
-- or "". adjustStatusFont ON takes the configured face, the configured size
-- falling back to the default size, the configured border falling back to
-- none; OFF takes the default triple whole. BF:ResolveFontPath always
-- returns a path, so fontPath is never nil.
local function FillBlock(block, tp)
	local baseFont, baseSize, baseFlags
	if GameFontNormalSmall then
		baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
	end
	baseFont  = BF.font or baseFont or "Fonts\\FRIZQT__.TTF"
	baseSize  = baseSize  or 10
	baseFlags = baseFlags or ""

	local fontPath, fontSize, fontFlags
	if tp and tp.adjustStatusFont then
		fontPath  = BF:ResolveFontPath(tp.statusFont)
		fontSize  = tp.statusFontSize or baseSize
		fontFlags = tp.statusFontBorder or ""
	else
		fontPath  = baseFont
		fontSize  = baseSize
		fontFlags = baseFlags
	end
	local point = (tp and tp.statusTextPosition) or "CENTER"
	local x     = (tp and tp.statusTextX) or 0
	local y     = (tp and tp.statusTextY) or 0

	if block.fontPath == fontPath and block.fontSize == fontSize
	   and block.fontFlags == fontFlags and block.point == point
	   and block.x == x and block.y == y then
		return false
	end
	block.fontPath  = fontPath
	block.fontSize  = fontSize
	block.fontFlags = fontFlags
	block.point     = point
	block.x         = x
	block.y         = y
	return true
end

-- Write a block to one frame's label, unconditionally (Grid2 Text_Layout),
-- and stamp which block / version the label now holds.
local function ApplyBlock(parent, block)
	local fs = parent.statusText
	fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)
	-- Never re-set this font from fs:GetFont(): GetFont() does not round-trip
	-- exactly on the scaled headers, and a GetFont -> SetFont cycle per tick
	-- once shrank "Offline"/"Dead" below the configured size (user report).
	-- _cfgFont* is read only by /bf statusdiag.
	fs._cfgFontPath  = block.fontPath
	fs._cfgFontSize  = block.fontSize
	fs._cfgFontFlags = block.fontFlags
	fs._bf_stBlock   = block
	fs._bf_stVer     = block.ver

	fs:ClearAllPoints()
	local anchor = parent.container or parent.healthBar or parent
	fs:SetPoint(block.point, anchor, block.point, block.x, block.y)

	-- Grid2 Text_Layout: Text:Show(); Frame:Show(). Both stay shown; whether
	-- the label is visible is the container's alpha alone (SetStatusTextShown).
	fs:Show()
	if parent.statusTextFrame then parent.statusTextFrame:Show() end
end

-- ── Scopes ───────────────────────────────────────────────────
-- Key for the regular frames. A table so it can never collide with a group.
local _MAIN_SCOPE = {}
-- scope key -> block. Weak keys: a Custom Frame Group table that is gone
-- (profile switch, group deleted) takes its block with it.
local _scopeBlocks = setmetatable({}, { __mode = "k" })
-- Scopes already resolved during the current pass (reused, wiped per pass).
local _passSeen = {}
local _passGen     = nil   -- BF._sectionCfgGen the last pass ran at
local _scopesDirty = true  -- set by ScheduleStatusTextPass, cleared by a pass

-- The frame's scope, by its HEADER (read live, never cached on the frame:
-- a Custom Frame Group header can be reset and reassigned to another group).
local function ScopeOf(frame)
	local header = frame:GetParent()
	if header and header._cfgFlat and header._cfgGroup then
		return header._cfgGroup, header
	end
	return _MAIN_SCOPE, header
end

-- The text section profile for a scope. _MAIN_SCOPE is exactly what
-- GetSectionProfileForFrame returns for a regular frame; a group is exactly
-- what it returns for that group's frames.
local function ScopeProfile(key, header)
	if key == _MAIN_SCOPE then
		local activeFlat = BF:ResolveActiveIsRaid() and BF:GetRaidProfile()
		                   or BF:GetActivePartyProfile()
		return BF:GetSectionProfile("text", activeFlat)
	end
	return BF:GetCFGSectionProfile("text", header._cfgGroup, header._cfgFlat)
end

-- Resolve a scope's block. Creates it on first sight. Bumps block.ver when a
-- value moved so every frame stamped with the old version is re-applied.
local function ResolveScope(key, header)
	local block = _scopeBlocks[key]
	if block == nil then
		block = { ver = 0 }
		_scopeBlocks[key] = block
	end
	if FillBlock(block, ScopeProfile(key, header)) then
		block.ver = block.ver + 1
	end
	block.gen = BF._sectionCfgGen or 0
	return block
end

-- THE pass. Resolves each scope present among the registered frames once,
-- then re-applies the scope's block to every frame of it that does not hold
-- the current version. Frames whose scope did not change are not touched.
local function RunScopePass()
	_scopesDirty = false
	_passGen = BF._sectionCfgGen or 0
	local frames = BF.registeredFrames
	if not frames then return end
	for _, frame in next, frames do
		local fs = frame.statusText
		if fs and not frame._isPreviewFrame then
			local key, header = ScopeOf(frame)
			local block
			if _passSeen[key] then
				block = _scopeBlocks[key]
			else
				_passSeen[key] = true
				block = ResolveScope(key, header)
			end
			if fs._bf_stBlock ~= block or fs._bf_stVer ~= block.ver then
				ApplyBlock(frame, block)
			end
		end
	end
	wipe(_passSeen)
end

-- Coalesced next-frame pass. Cheap to call repeatedly: one timer per frame.
local _passQueued = false
local function QueuedPass()
	_passQueued = false
	if _scopesDirty or _passGen ~= (BF._sectionCfgGen or 0) then
		RunScopePass()
	end
end
function BF:ScheduleStatusTextPass()
	_scopesDirty = true
	if not _passQueued then
		_passQueued = true
		C_Timer.After(0, QueuedPass)
	end
end

-- ============================================================
-- Preview frames only: per-frame resolver
-- ============================================================
-- Preview frames show the Layout / group being EDITED (frame._flatID /
-- _cfgFlat), which need not be the active one, so they cannot share a live
-- scope block. Cached per section table + generation as before. The section
-- table is a weak key: merged views are re-minted on invalidation.
--
-- SECTION-TABLE CACHE KEYS (referenced by the other indicators' _cfgBlocks
-- caches, which use the scheme below for ALL their frames; status text uses it
-- for preview frames only). Kept verbatim from before the 2026-11-17 scope
-- rewrite.
-- SCOPE KEY = THE SECTION TABLE ITSELF. BF's config is per scope, not global:
-- the active flat, each Custom Frame Group (header._cfgFlat / _cfgGroup) and
-- each preview frame (frame._flatID) resolve to DIFFERENT section tables out
-- of GetSectionProfileForFrame (Core_ProfileAPI.lua:1255). Keying the cache on
-- that table gives exactly one block per scope with no scope enumeration and
-- nothing to keep in sync when a scope is added or removed -- which matters,
-- because the CFG and preview scopes are the ones a call-site inventory keeps
-- failing to cover (plan §6 table). `tp == nil` is a scope too, and gets its
-- own constant key below rather than being turned back into an early return.
--
-- WEAK KEYS, and the generation key below, cover the two DIFFERENT lifetimes
-- a section table can have -- this comment previously claimed only the first
-- and implied it was universal, which it is not. A per-Layout or per-CFG
-- section resolves to a MERGED VIEW allocated by BuildMergedSectionView and
-- cached at flat._sectionCache[section] (Core_ProfileAPI.lua:1187-1189);
-- invalidation drops that cache, so the next resolve mints a NEW table and a
-- strong key would pin the dead one for the session. The degenerate paths
-- (:1170-1174) instead return rpDB.profile[section] itself -- a long-lived
-- AceDB table the options UI mutates IN PLACE (BFStatus.lua:999-1001), whose
-- identity never changes on an edit. Keying on the table alone would never
-- notice those edits at all; that is what the generation key is for.
local _previewBlocks = setmetatable({}, { __mode = "k" })
local _NO_SECTION = {}

local function ResolvePreviewBlock(parent)
	local tp  = BF:GetSectionProfileForFrame("text", parent)
	local key = tp or _NO_SECTION
	local gen = BF._sectionCfgGen or 0
	local block = _previewBlocks[key]
	if block and block.gen == gen then return block end
	if block == nil then
		block = { ver = 0 }
		_previewBlocks[key] = block
	end
	if FillBlock(block, tp) then block.ver = block.ver + 1 end
	block.gen = gen
	return block
end

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Dispatched by BF:RefreshIndicatorSettings on every profile/context switch.
function StatusOverlay:UpdateSettings()
	wipe(_previewBlocks)
	BF:ScheduleStatusTextPass()
end

-- The block Layout writes for this frame right now. Used by /bf statusdiag.
local function BlockForFrame(parent)
	if parent._isPreviewFrame then return ResolvePreviewBlock(parent) end
	if _scopesDirty or _passGen ~= (BF._sectionCfgGen or 0) then
		RunScopePass()
	end
	local key, header = ScopeOf(parent)
	-- A scope with no block yet: no REGISTERED frame is in it (the pass just
	-- covered all of them), so this is the first frame of a new header,
	-- laid out by BuzzardFrame_Init before RegisterFrame lists it.
	-- Resolving it here cannot leave a sibling on a different value.
	return _scopeBlocks[key] or ResolveScope(key, header)
end
StatusOverlay.ResolveBlock = BlockForFrame

-- ============================================================
-- Layout
-- ============================================================
function StatusOverlay:Layout(parent)
	-- Widget-existence guard, NOT a config guard: no FontString, nothing to do.
	if not parent.statusText then return end
	ApplyBlock(parent, BlockForFrame(parent))
end

-- ============================================================
-- Update: dispatches offline first, then health/dead/afk state.
-- Ported from BF:UpdateHealth and BF:UpdateOffline (LayoutFrame.lua).
-- ============================================================
function StatusOverlay:Update(parent, unit)
	if not unit then return end

	-- Read from statuses instead of caches/APIs directly
	local offlineStatus = BF.statuses and BF.statuses.offline
	local healthStatus  = BF.statuses and BF.statuses.health

	-- ── Offline pass ──────────────────────────────────────────────────────
	local isOffline = offlineStatus and offlineStatus:IsActive(unit) or false
	parent._offline = isOffline

	if isOffline then
		self:_RenderOffline(parent, unit)
		return
	end

	-- Unit came back online — invalidate bar color cache so health re-applies it.
	parent.cachedHealthR = nil

	-- ── Health / dead / afk pass ──────────────────────────────────────────
	if not healthStatus or not healthStatus:IsActive(unit) then return end
	self:_RenderHealth(parent, unit)
end

-- ============================================================
-- Offline rendering (ported from BF:UpdateOffline)
--
-- GC: this function previously allocated two 3-field color tables per call
-- (offlineTextColor + fallback offlineBarColor) on every UNIT_HEALTH while
-- a unit was offline. Now uses three locals each (oR/oG/oB for text,
-- bR/bG/bB for bar) so no tables are allocated on the hot path. Fallback
-- values for bar color are read directly from hp.offlineBackgroundColor
-- fields when present, or the 0.3 gray default when not.
-- ============================================================
function StatusOverlay:_RenderOffline(parent, unit)
	local tp  = getTextProfile(parent)
	local hp  = getHealthPowerProfile(parent)
	local healthStatus  = BF.statuses and BF.statuses.health
	local offlineStatus = BF.statuses and BF.statuses.offline

	local r, g, b
	if offlineStatus then r, g, b = offlineStatus:GetColor(unit) end
	-- Offline text color: three locals instead of a table allocation.
	local oR = r or 0.5
	local oG = g or 0.5
	local oB = b or 0.5

	if hp and hp.useCustomOfflineColor then
		-- Bar color: read fields directly from the profile table when set,
		-- else fall through to the 0.3 gray default. No fallback table alloc.
		local obc = hp.offlineBackgroundColor
		local bR, bG, bB
		if obc then bR, bG, bB = obc.r, obc.g, obc.b
		else bR, bG, bB = 0.3, 0.3, 0.3 end
		-- 4-arg form: party↔raid transitions cause HealthBarColor:Update to
		-- run with no unit (the missing-unit branch writes alpha=0). The
		-- 3-arg SetStatusBarColor does NOT reset alpha, so the bar would
		-- inherit the alpha=0 from that earlier write and render fully
		-- transparent. Mirror HealthBar.lua's alive-path use of
		-- hp.healthBarOpacity so opacity stays consistent across states.
		parent.healthBar:SetStatusBarColor(bR, bG, bB, hp.healthBarOpacity or 1)
		parent.cachedHealthR = nil
		parent.statusOverlay:Hide()
	else
		-- Repaint the bar with the live class/health color. Without this,
		-- toggling "Use Custom Offline Color" from ON → OFF would leave
		-- the bar painted in the custom color underneath the dark overlay
		-- (HealthBarColor:Update bails for offline units so it won't
		-- repaint here). Mirrors HealthBarColor:Update's alive-path write.
		if healthStatus then
			local newR, newG, newB = healthStatus:GetColor(unit, parent)
			parent.healthBar:SetStatusBarColor(newR, newG, newB, hp and hp.healthBarOpacity or 1)
			parent.cachedHealthR = nil
		end
		parent.statusOverlay:SetColorTexture(0.1, 0.1, 0.1, 0.7)
		parent.statusOverlay:Show()
	end

	parent.healthText:Hide()

	if parent.healPrediction then parent.healPrediction:SetAlpha(0) end
	-- Was absorbMissingHealth:Hide() plus a .bg:Hide(). Both are one-way:
	-- nothing re-Shows them except _ApplyAbsorbStyle, which only runs on a
	-- style-generation bump, so a single disconnect blanked the
	-- missing-health absorb bar until a settings change or /reload -- and
	-- for every unit that frame was later recycled onto. Alpha is the
	-- transient channel (see BF.SetAbsorbSuppressed in AbsorbBars.lua) and
	-- it multiplies through .bg, so the second line is gone entirely.
	BF.SetAbsorbSuppressed(parent, true)
	if parent.absorbOverflow then parent.absorbOverflow:SetAlpha(0) end
	if parent.healAbsorb     then parent.healAbsorb:SetAlpha(0)    end
	if parent.healAbsorbBar  then parent.healAbsorbBar:SetAlpha(0) end

	local showName  = tp and tp.showName
	-- fadeOfflineFrames lives in healthPower (its UI widget is on the Health
	-- & Power tab, so it obeys the healthPower per-layout toggle).
	local fadeAlpha = (tp and tp.fadeOfflineNameText and not (hp and hp.fadeOfflineFrames)) and (hp and hp.rangeFadeAlpha or 0.4) or 1

	if tp and tp.appendStatusTextToNames then
		SetStatusTextShown(parent, false)
		if showName then
			local baseName = GetUnitBaseName(unit, tp)
			if tp.showOfflineStatus ~= false then
				if tp.abbreviateStatusNames and #baseName > (tp.maxStatusNameChars or 9) then
					baseName = baseName:sub(1, tp.maxStatusNameChars or 9)
				end
				local offlineLabel = tp.abbreviateOffline and "Off" or "Offline"
				SetNameText(parent, AppendStatus(baseName, offlineLabel, parent))
			else
				SetNameText(parent, ApplyNameCase(baseName, parent))
			end
			parent.nameText:SetTextColor(oR, oG, oB)
			parent.nameText:SetAlpha(fadeAlpha)
			parent.nameText:Show()
		end
	else
		if tp and tp.showOfflineStatus ~= false then
			local offlineLabelShort = tp.abbreviateOffline and "Off" or "Offline"
			parent.statusText:SetText(GetStatusLabel(offlineLabelShort, parent))
			parent.statusText:SetTextColor(oR, oG, oB)
			parent.statusText:SetAlpha(fadeAlpha)
			SetStatusTextShown(parent, true)
		else
			SetStatusTextShown(parent, false)
		end
		if showName then
			if tp and tp.applyStatusColorsToNames then
				parent.nameText:SetTextColor(oR, oG, oB)
			end
			parent.nameText:SetAlpha(fadeAlpha)
			parent.nameText:Show()
		end -- showName-off hiding is owned by NameText:Update now (plan Phase 3.1)
	end
end

-- ============================================================
-- Health/dead/afk rendering (ported from BF:UpdateHealth)
-- ============================================================
function StatusOverlay:_RenderHealth(parent, unit)
	local tp     = getTextProfile(parent)
	local hp     = getHealthPowerProfile(parent)
	local deathStatus  = BF.statuses and BF.statuses.death
	local flagsStatus  = BF.statuses and BF.statuses.flags
	-- Pure cache read ("Dead" / "Ghost" / nil): the label doubles as the
	-- dead flag, and nothing here touches a unit API for it.
	local isDead    = deathStatus and deathStatus:GetState(unit) or false

	local isAFK    = tp and tp.showAFKStatus and flagsStatus and flagsStatus:IsAFK(unit) or false
	local newState = (isDead and "dead") or (isAFK and "afk") or "alive"
	local showName = tp and tp.showName

	if newState == "afk" then
		-- ── AFK ──────────────────────────────────────────────────────────
		parent.statusOverlay:Hide()
		parent.healthText:Hide()
		local ar, ag, ab
		if flagsStatus then ar, ag, ab = flagsStatus:GetColor(unit) end
		-- AFK color: three locals instead of a `ac = {...}` table allocation
		-- (this branch runs on every UNIT_HEALTH for AFK units).
		local acR = ar or 0.8
		local acG = ag or 0.6
		local acB = ab or 0
		if tp and tp.appendStatusTextToNames then
			SetStatusTextShown(parent, false)
			if showName then
				local baseName = GetUnitBaseName(unit, tp)
				if tp.showAFKStatus then
					if tp.abbreviateStatusNames and #baseName > (tp.maxStatusNameChars or 9) then
						baseName = baseName:sub(1, tp.maxStatusNameChars or 9)
					end
					SetNameText(parent, AppendStatus(baseName, "AFK", parent))
					parent.nameText:SetTextColor(acR, acG, acB)
				else
					SetNameText(parent, baseName)
					parent.nameText:SetTextColor(acR, acG, acB)
				end
				parent.nameText:SetAlpha(1)
				parent.nameText:Show()
			end
		else
			if tp and tp.showAFKStatus then
				parent.statusText:SetText(GetStatusLabel("AFK", parent))
				parent.statusText:SetTextColor(acR, acG, acB)
				parent.statusText:SetAlpha(1)
				SetStatusTextShown(parent, true)
			else
				SetStatusTextShown(parent, false)
			end
			if showName then
				if tp and tp.applyStatusColorsToNames then
					parent.nameText:SetTextColor(acR, acG, acB)
				end
				parent.nameText:SetAlpha(1)
				parent.nameText:Show()
			end -- showName-off hiding is owned by NameText:Update now (plan Phase 3.1)
		end

	elseif newState == "dead" then
		-- ── Dead ─────────────────────────────────────────────────────────
		-- GC: pre-fix this branch allocated three 3-field color tables on every
		-- UNIT_HEALTH for dead units (deadTextColor, deadBarColor fallback,
		-- bg fallback). Converted to three locals per color so the hot path
		-- produces zero garbage when the user has left colors at defaults.
		local dr, dg, db
		if deathStatus then dr, dg, db = deathStatus:GetColor(unit) end
		local dtR = dr or 0.8
		local dtG = dg or 0.1
		local dtB = db or 0.1
		local isOOR = IsOutOfRange(BF.rangeCache and BF.rangeCache[unit])
		local r, g, b
		if isOOR then
			local f = hp and hp.deadColorOORFactor
			if f == nil then f = 0.5 end
			local gray = (dtR + dtG + dtB) / 3
			r = dtR * f + gray * (1 - f)
			g = dtG * f + gray * (1 - f)
			b = dtB * f + gray * (1 - f)
		else
			r, g, b = dtR, dtG, dtB
		end

		local deadLabel = isDead

		-- Dead bar color: read fields directly from hp.deadBackgroundColor
		-- when custom-dead-color is enabled AND the profile table is present,
		-- else fall through to the 0.1 gray default. No fallback table alloc.
		local dbc = (hp and hp.useCustomDeadColor and hp.deadBackgroundColor) or nil
		local dbR, dbG, dbB
		if dbc then dbR, dbG, dbB = dbc.r, dbc.g, dbc.b
		else dbR, dbG, dbB = 0.1, 0.1, 0.1 end
		local deadBarOpacity = hp and hp.useCustomDeadColor and (hp.deadBackgroundOpacity ~= nil and hp.deadBackgroundOpacity or 0.7) or 0.7
		parent.statusOverlay:SetColorTexture(dbR, dbG, dbB, deadBarOpacity)
		parent.statusOverlay:Show()
		parent.healthText:Hide()
		-- Bar VALUE is HealthBar's (it is bound to death and parks the bar
		-- itself); only the color handoff flag is cleared here.
		parent.cachedHealthR = nil
		-- Reset bar background color so a stale gradient doesn't show through.
		-- Same pattern: read fields directly, else fall through to black default.
		if parent.healthBar.bg then
			local bgc = (hp and hp.useCustomBackgroundColor and hp.backgroundColor) or nil
			local bgR, bgG, bgB
			if bgc then bgR, bgG, bgB = bgc.r, bgc.g, bgc.b
			else bgR, bgG, bgB = 0, 0, 0 end
			parent.healthBar.bg:SetColorTexture(bgR, bgG, bgB, 1)
		end

		if parent.healPrediction then parent.healPrediction:SetAlpha(0) end
		-- THE death-path bug: this was absorbMissingHealth:Hide() plus a
		-- .bg:Hide(), and the alive branch below restored neither. Since
		-- only _ApplyAbsorbStyle ever calls Show() -- and Update runs it
		-- only when BF._absorbStyleGen changes -- the first death on a
		-- frame killed its missing-health absorb bar for good:
		-- _UpdateAbsorbOverlay kept writing SetValue into a hidden frame.
		-- Suppression is alpha now, and the alive branch lifts it.
		BF.SetAbsorbSuppressed(parent, true)
		if parent.absorbOverflow then parent.absorbOverflow:SetAlpha(0) end
		if parent.healAbsorb     then parent.healAbsorb:SetAlpha(0)    end
		if parent.healAbsorbBar  then parent.healAbsorbBar:SetAlpha(0) end

		if tp and tp.appendStatusTextToNames then
			SetStatusTextShown(parent, false)
			if showName then
				local baseName = GetUnitBaseName(unit, tp)
				if tp.showDeadStatus ~= false then
					if tp.abbreviateStatusNames and #baseName > (tp.maxStatusNameChars or 9) then
						baseName = baseName:sub(1, tp.maxStatusNameChars or 9)
					end
					SetNameText(parent, AppendStatus(baseName, deadLabel, parent))
					parent.nameText:SetTextColor(r, g, b)
				else
					SetNameText(parent, baseName)
					parent.nameText:SetTextColor(r, g, b)
				end
				parent.nameText:SetAlpha(1)
				parent.nameText:Show()
			end
		else
			if tp and tp.showDeadStatus ~= false then
				parent.statusText:SetText(GetStatusLabel(deadLabel, parent))
				parent.statusText:SetTextColor(r, g, b)
				-- No SetFont here: the status font is written by Layout ONLY
				-- (Grid2 Text_Layout). An out-of-range outline strip that used
				-- to live here was removed 2026-10-01 -- owner: range must not
				-- change the outline.
				SetStatusTextShown(parent, true)
			else
				SetStatusTextShown(parent, false)
			end
			if showName then
				if tp and tp.applyStatusColorsToNames then
					parent.nameText:SetTextColor(r, g, b)
				end
				parent.nameText:SetAlpha(1)
				parent.nameText:Show()
			end -- showName-off hiding is owned by NameText:Update now (plan Phase 3.1)
		end

	else
		-- ── Alive ─────────────────────────────────────────────────────────
		parent.statusOverlay:Hide()
		SetStatusTextShown(parent, false)
		-- The nameText and healthText cross-calls that used to live here are
		-- gone: both indicators are bound to death/offline/flags themselves,
		-- so every transition that hides their content also dispatches them
		-- to bring it back. Text is repainted on name events, roster changes
		-- and bound-status transitions — not on every health tick.
		--
		-- Lift absorb suppression on the way back to alive. The three
		-- SetAlpha(0) siblings in the dead/offline branches (healPred,
		-- healAbsorb, healAbsorbBar) are restored by their own updaters on
		-- the next event; the missing-health absorb bar has no such writer,
		-- so this is its restore path. Unconditional but change-guarded
		-- inside BF.SetAbsorbSuppressed, so a steady-state alive tick costs
		-- one comparison. _ApplyAbsorbStyle still owns config visibility: a
		-- bar the settings disabled stays Hide()'d.
		BF.SetAbsorbSuppressed(parent, false)
	end
end

-- ============================================================
function StatusOverlay:GetFrame(parent)
	return parent.statusOverlay
end

-- Expose AppendStatus for other indicators (e.g. ReducedMaxHealthText appending to name)
BF.AppendStatus = AppendStatus

BF:RegisterIndicator(StatusOverlay)
