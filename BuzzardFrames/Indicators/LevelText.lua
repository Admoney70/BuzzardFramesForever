--[[
BuzzardFrames: Indicators/LevelText.lua
Level text indicator — shows the unit's level on each raid/party frame.

Grid2 has no analogous indicator. This mirrors HealthText.lua's structure
(Create/Layout/Update + Grid2 unconditional-overwrite Update pattern).

Driven by the "level" status (Statuses/Level.lua), which fires
UNIT_LEVEL / PLAYER_LEVEL_UP. The initial render on unit-join is handled
by the framework's frame:UpdateIndicators() path (BFLayout.lua:OnUnitChanged).
]]

local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitLevel          = UnitLevel
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitExists         = UnitExists

-- Resolve max level once at file load. Same approach as oUF_Shared.lua:995.
-- GetMaxLevelForPlayerExpansion is the live cap; MAX_PLAYER_LEVEL is the
-- static fallback. The "or 80" guard matches oUF_Shared's pattern.
local function GetMaxLevel()
    if GetMaxLevelForPlayerExpansion then return GetMaxLevelForPlayerExpansion() end
    return MAX_PLAYER_LEVEL or 60
end

local LevelText = BF.indicatorPrototype:new("levelText")

-- ============================================================
-- Create
-- ============================================================
function LevelText:Create(parent)
    if parent.levelText then
        parent[self.name] = parent.levelText
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
    local tpInit = BF:GetSectionProfile("text", nil)
    local pos = (tpInit and tpInit.levelTextPosition) or "TOPRIGHT"
    local anchor = parent.container or hBar or parent
    fs:SetPoint(pos, anchor, pos, 0, 0)

    local c = (tpInit and tpInit.levelTextColor) or { r = 1, g = 0.82, b = 0 }
    fs:SetTextColor(c.r, c.g, c.b)

    parent[self.name] = fs
    parent.levelText  = fs  -- alias for parity with parent.healthText
end

-- ============================================================
-- Resolved config block  (Grid2 parity: Text_UpdateDB / Text_Layout)
-- ============================================================
-- Grid2 resolves an indicator's config ONCE, when the DB is known-loaded, into
-- a block the indicator holds (modules/IndicatorText.lua:251), and Layout then
-- writes that block with no decisions left in it (:106). The fallback chain is
-- baked in at RESOLVE time, which is exactly why Layout needs no
-- `if not tp then return end` -- the block handed to it is always complete.
-- See BuzzardFrames_IndicatorUpdateDB_Plan.md §2 and §5.
--
-- SCOPE KEY = THE SECTION TABLE ITSELF. Established in-tree pattern, not a new
-- one: BFStatus.lua:993-1005 memoizes the composed name entry the same way,
-- weak-keyed, and states the rationale -- "Frames sharing a flat share one
-- entry; CFG flats get their own." The active flat, each Custom Frame Group
-- and each preview frame resolve to different section tables out of
-- GetSectionProfileForFrame (Core_ProfileAPI.lua:1255), so table identity IS
-- the scope, with no scope list to enumerate. `tp == nil` is a scope too and
-- takes the constant key below, rather than becoming an early return again.
--
-- WEAK KEYS, and the generation key below, cover the two lifetimes a section
-- table can have. A per-Layout or per-CFG section resolves to a MERGED VIEW
-- allocated by BuildMergedSectionView and cached at flat._sectionCache[section]
-- (Core_ProfileAPI.lua:1187-1189); invalidation drops that cache, so the next
-- resolve mints a NEW table and a strong key would pin the dead one for the
-- session. The degenerate paths return rpDB.profile[section] itself -- a
-- long-lived AceDB table the options UI mutates IN PLACE (BFStatus.lua:999-1001),
-- whose identity never changes on an edit. Keying on the table alone would
-- never see those edits; that is what the generation key is for.
local _blockCacheMeta = { __mode = "k" }

-- Scope key for "no section profile resolvable for this frame". A table, so it
-- can never collide with a real section table.
local _NO_SECTION = {}

-- The level text's own default color, repeated at four sites in this file
-- (:66, :101, :104, and Update's three arms). Named once here so the block and
-- Update cannot drift apart.
local _DEFAULT_LEVEL_R, _DEFAULT_LEVEL_G, _DEFAULT_LEVEL_B = 1, 0.82, 0

-- ============================================================
-- UpdateSettings  (Grid2 parity: UpdateDB)
-- ============================================================
-- Implements the hook declared at BFIndicator.lua:62, dispatched by
-- BF:RefreshIndicatorSettings (BFIndicator.lua:332) from LoadLayout on every
-- profile/context switch. Drops the resolved blocks so the next Layout
-- re-resolves.
--
-- The PUSH half only, and an optimization rather than the correctness
-- guarantee: the generation key in ResolveLevelTextBlock is what makes
-- staleness impossible on the paths that reach indicator:Layout without ever
-- reaching RefreshIndicatorSettings (plan §6.1(b)).
function LevelText:UpdateSettings()
    self._cfgBlocks = nil
end

-- Resolve (or reuse) this frame's block. Declared ABOVE LevelText:Layout on
-- purpose: a Lua local is only in scope after its declaration, so a resolver
-- placed below its caller compiles to a nil global lookup and throws only on
-- the path that reaches it. Tests/check_locals.py exists for that.
local function ResolveLevelTextBlock(parent)
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

    local blocks = LevelText._cfgBlocks
    if blocks == nil then
        blocks = setmetatable({}, _blockCacheMeta)
        LevelText._cfgBlocks = blocks
    end

    local block = blocks[key]
    if block and block.gen == gen then return block end
    if block == nil then
        block = {}
        blocks[key] = block
    end
    block.gen = gen

    -- DEFAULT CHAIN, spelled out literally rather than read off the FontString.
    -- The block is shared by every frame in this scope, so it must not depend
    -- on per-FontString state: fs.SF_defaultFont / SF_defaultSize /
    -- SF_defaultFlags are what the old Layout read, and that read is what made
    -- the resolution per-frame. Dropping it is safe because :Create stamps
    -- those three fields on EVERY levelText it builds, from this same chain
    -- (:50-52) -- GameFontNormalSmall's font first, then BF.font, then FRIZQT.
    -- BF.font is a file-scope constant (Core.lua:87), never reassigned, so
    -- resolving it here rather than at Create time cannot diverge.
    local baseFont, baseSize, baseFlags
    if GameFontNormalSmall then
        baseFont, baseSize, baseFlags = GameFontNormalSmall:GetFont()
    end
    baseFont  = baseFont  or BF.font or "Fonts\\FRIZQT__.TTF"
    baseSize  = baseSize  or 10
    baseFlags = baseFlags or ""

    -- adjustLevelFont semantics unchanged: ON takes the configured face and
    -- border, OFF takes the default triple whole. BF:ResolveFontPath
    -- (PixelPerfect.lua:656) always returns a path, so fontPath is never nil.
    --
    -- ONE DELIBERATE DELTA: the size gets `or baseSize`. The old line was
    -- `fs:SetFont(fontPath, tp.levelFontSize, tp.levelFontBorder or "")` with
    -- no fallback, so a profile with adjustLevelFont ON and levelFontSize
    -- absent threw inside SetFont. A block that is "complete and usable" is the
    -- whole point of resolving here (plan §2, property 3), and an incomplete
    -- one cannot be written unconditionally, so the hole is filled with the
    -- same default Create uses. Behavior is identical wherever the size is set.
    if tp and tp.adjustLevelFont then
        block.fontPath  = BF:ResolveFontPath(tp.levelFont)
        block.fontSize  = tp.levelFontSize or baseSize
        block.fontFlags = tp.levelFontBorder or ""
    else
        block.fontPath  = baseFont
        block.fontSize  = baseSize
        block.fontFlags = baseFlags
    end

    block.point = (tp and tp.levelTextPosition) or "TOPRIGHT"
    block.x     = (tp and tp.levelTextX) or 0
    block.y     = (tp and tp.levelTextY) or 0

    -- COLOR is resolved to a three-state instruction, not to a color.
    -- `adjustLevelTextColor` ON together with `classColorLevelText` means the
    -- color is per-UNIT and belongs to Update (:145-154), so Layout must write
    -- NOTHING and leave whatever Update last painted. That third state is a
    -- decision about WHICH value applies, taken on fully resolved config -- not
    -- a "do we have any config" test -- so it survives the unconditional-write
    -- rule intact. Flattening it into an unconditional SetTextColor would
    -- repaint every class-colored level over the static color on each Layout.
    local adjust = (tp and tp.adjustLevelTextColor) and true or false
    local class  = (tp and tp.classColorLevelText) and true or false
    block.writeColor = (not adjust) or (adjust and not class)
    if adjust and not class then
        local c = (tp and tp.levelTextColor) or nil
        block.colR = c and c.r or _DEFAULT_LEVEL_R
        block.colG = c and c.g or _DEFAULT_LEVEL_G
        block.colB = c and c.b or _DEFAULT_LEVEL_B
    else
        block.colR, block.colG, block.colB =
            _DEFAULT_LEVEL_R, _DEFAULT_LEVEL_G, _DEFAULT_LEVEL_B
    end

    return block
end

-- ============================================================
-- Layout
-- ============================================================
function LevelText:Layout(parent)
    local fs = parent[self.name]
    -- Widget-existence guard, NOT a config guard: with no FontString there is
    -- nothing to write to. The config guard that used to follow it
    -- (`if not tp then return end`) is gone -- the block is complete even when
    -- no section profile resolves, so Layout has nothing left to decide.
    if not fs then return end

    local block = ResolveLevelTextBlock(parent)

    -- UNCONDITIONAL WRITE (Grid2 Text_Layout). Font and geometry are written on
    -- every call; this function cannot leave the widget holding its Create-time
    -- defaults. The anchor stays per-frame -- frame state, not config.
    fs:SetFont(block.fontPath, block.fontSize, block.fontFlags)

    local hBar = parent.healthBar
    fs:ClearAllPoints()
    local anchor = parent.container or hBar or parent
    fs:SetPoint(block.point, anchor, block.point, block.x, block.y)

    -- Static color. See block.writeColor above for why this one write stays
    -- conditional: the skipped case is "Update owns this color", not "no config".
    if block.writeColor then
        fs:SetTextColor(block.colR, block.colG, block.colB)
    end
end

-- ============================================================
-- Update: unconditionally overwrite (Grid2 pattern)
-- ============================================================
function LevelText:Update(parent, unit)
    local fs = parent[self.name]
    if not fs then return end

    local tp = BF:GetCachedSection("text", parent)

    if not tp or not tp.showLevelText or not unit or not UnitExists(unit) then
        fs:SetText("")
        fs:Hide()
        return
    end

    local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit)

    -- Boss / unknown-level (level == -1) → show "??"
    local displayText
    if level == -1 then
        displayText = "??"
    else
        if tp.hideLevelTextAtMaxLevel and level and level >= GetMaxLevel() then
            fs:SetText("")
            fs:Hide()
            return
        end
        if not level or level <= 0 then
            fs:SetText("")
            fs:Hide()
            return
        end
        displayText = tostring(level)
    end

    -- Color: mirror HealthText pattern. Class color is read from the health
    -- status (same source HealthText uses) so the class lookup path is shared.
    if tp.adjustLevelTextColor and tp.classColorLevelText then
        local healthStatus = BF.statuses and BF.statuses.health
        local className = healthStatus and healthStatus:GetClass(unit)
        if className and BF.classColors and BF.classColors[className] then
            local c = BF.classColors[className]
            fs:SetTextColor(c.r, c.g, c.b)
        else
            local c = tp.levelTextColor or { r = 1, g = 0.82, b = 0 }
            fs:SetTextColor(c.r, c.g, c.b)
        end
    elseif tp.adjustLevelTextColor then
        local c = tp.levelTextColor or { r = 1, g = 0.82, b = 0 }
        fs:SetTextColor(c.r, c.g, c.b)
    else
        fs:SetTextColor(1, 0.82, 0)
    end

    fs:SetText(displayText)
    fs:Show()
end

BF:RegisterIndicator(LevelText)
