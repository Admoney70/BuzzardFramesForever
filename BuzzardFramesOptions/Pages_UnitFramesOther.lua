-- ============================================================
-- BuzzardFramesOptions: Pages_UnitFramesOther.lua
-- The five per-frame Unit Frames sections, in BuzzardPanel:
-- Focus, Pet, Target of Target, Focus Target and Boss.
--
-- The panel equivalent of the five tabs BF:BuildPTFOptionsTable assembles
-- in UnitFrames/Options_oUF_Other.lua -- petOpts, bluzzFocusOpts,
-- bluzzTotOpts, bluzzFocusTargetOpts and bluzzBossOpts. Each is the
-- makeFrameOpts factory's four sub-tabs (Size & Position, Name Bar,
-- Health Bar, Power Bar), plus the post-hoc edits the assembler applies:
-- the health COLOR controls removed from every one of them (they live
-- in Global > Colors > Health Bars), the Auras and Cast Bar sub-tabs
-- added to Focus and Boss, and the Grow Direction and Frame Spacing
-- settings added to Boss's Size & Position.
--
-- Player and Target are NOT here: they are built by makeFrameOpts too,
-- but with a different set of post-hoc edits, and they belong to
-- Options_oUF_Player_Target.lua's own migration. Unit Frame Layouts
-- likewise. What all three share with this file is the ptfEnabled gate
-- below.
--
-- Storage: BF.ufDB.profile -- the Unit Frames module's own AceDB
-- namespace, in TWO shapes, exactly as the Ace get/set closures use it:
--
--   ufGet/ufSet   ufDB.profile[unit][key]   the per-frame sub-table
--   get/set       ufDB.profile[key]         flat profile keys
--
-- ROOT below routes between them by key, so a field can `bind` whichever
-- it needs and still get right-click Undo and Reset for free; DEFAULTS
-- is the same routing over BF.unitFrameDefaults.profile, so a reset
-- lands on BuzzardFrames' own shipped value rather than on a copy of it
-- kept here.
--
-- THE TWO GATES. Every card on these pages is hidden twice over:
--
--   * `BuzzardFramesOptions.UnitFramesOff` -- the section master switch,
--     which in the Ace panel NILLED these tabs out of the args table
--     altogether (syncPTFTabs). Published by Pages_UnitFramesGeneral.lua
--     so all three page files answer it the same way.
--   * this frame's own enable key (showFocusFrame, showPetFrame, ...),
--     which in the Ace panel hid every sub-tab EXCEPT Size & Position --
--     the one that carries the switch to turn it back on.
--
-- A BuzzardPanel route cannot hide, so both land on the cards, and a
-- note appears in their place saying which switch to look for.
--
-- REFRESH, and one asymmetry worth keeping. The Ace file declares a
-- DEBOUNCED relayout per unit at the top (BF:DebounceOption, keys
-- oufLayoutPet / oufLayoutFocus / ...), and then, in the assembler,
-- shadows four of them with plain undebounced locals. Only BOSS still
-- reaches the debounced one. That is reproduced here rather than
-- tidied: a slider drag on the boss tab coalesces into one relayout and
-- the other four do not, which is how the addon behaves today.
--
-- ── The Ace args keys, and where each one went ──────────────────
--
-- The aura fields are BUILT from the frame's prefix rather than written
-- out twice (AuraCard below), so their keys do not appear literally
-- anywhere in this file. Spelled out here so a reader -- and
-- Tools/audit_keys.py -- can see that none of them was dropped:
--
--   focusShowDebuffs focusDebuffSize focusDebuffsPerRow focusMaxDebuffs
--   focusDebuffSpacing focusDebuffOffsetX focusDebuffOffsetY
--   focusShowBuffs focusBuffSize focusBuffsPerRow focusMaxBuffs
--   focusBuffSpacing focusBuffOffsetX focusBuffOffsetY
--   bossShowDebuffs bossDebuffSize bossDebuffsPerRow bossMaxDebuffs
--   bossDebuffSpacing bossDebuffOffsetX bossDebuffOffsetY
--   bossShowBuffs bossBuffSize bossBuffsPerRow bossMaxBuffs
--   bossBuffSpacing bossBuffOffsetX bossBuffOffsetY
--       -> the Debuffs and Buffs cards on each frame's Auras page.
--
-- The cast bar keys are built the same way from `prefix`:
--   focusCastBarPosition focusCastBarGap focusCastBarHeight
--   focusCastBarBorderEnabled focusCastBarBorderThickness
--   focusCastBarBorderColor focusCastBarShowIcon focusCastBarIconSide
--   focusCastBarIconSize focusCastBarIconGap
--   bossCastBarPosition bossCastBarGap bossCastBarHeight bossCastBarWidth
--   bossCastBarBorderEnabled bossCastBarBorderThickness
--   bossCastBarBorderColor bossCastBarShowIcon bossCastBarIconSide
--   bossCastBarIconSize bossCastBarIconGap
--       -> the Cast Bar page's five cards. (They are listed by name in
--          FLAT below, which is where the routing decision is made.)
--
-- And the Ace HEADER nodes, which are card boundaries here rather than
-- widgets of their own:
--   hdrDebuffs -> "Debuffs"      hdrBuffs      -> "Buffs"
--   hdrPlacement -> "Placement"  hdrSize       -> "Size"
--   hdrBorder  -> "Border"       hdrIcon       -> "Spell Icon"
--   hdrSpacing -> "Frame Spacing"
--   hdrPosition -> "Position"    hdrAlpha      -> "Frame Opacity"
--   hdrText    -> "Text" / "Power Bar Text"
--   hdrNameBar -> "Name Bar"     hdrNameBarText-> "Name Bar Text"
--   hdrPowerBar-> "Power Bar"    hdrColor      -> gone with its fields
--
-- Not migrated, deliberately: `_posTracker`, an AceConfig description
-- node whose NAME function re-derived the two position sliders' soft
-- bounds as a render side effect. Each slider does that in its own
-- getter here, so the hidden widget has nothing left to do.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function P()
    local bf = BF()
    return bf and bf.ufDB and bf.ufDB.profile
end

-- ── Flat keys ──────────────────────────────────────────────────
--
-- Everything else on these pages lives in the per-frame sub-table.
-- These are the keys the Ace source reads and writes at the profile
-- ROOT instead -- the five enable switches, the two boss layout
-- settings, and the two cast bars, which were built against
-- `self.ufDB.profile.<prefix>CastBar*` rather than against ufGet/ufSet.
--
-- The one exception inside a cast bar is focusCastBarFontSize, whose
-- Ace getter is `ufGet("focus", "castBarFontSize")` -- a per-unit key,
-- under a different name, while its boss twin is a flat one. That
-- asymmetry is in the source and is kept; see the notes.
local FLAT = {
    showFocusFrame = true, showPetFrame = true,
    showTargetOfTargetFrame = true, showFocusTargetFrame = true,
    showBossFrames = true,
    bossGrowDirection = true, bossFrameSpacing = true,
    focusRaidStyle = true, bossRaidStyle = true,

    focusShowCastBar = true, focusCastBarDetached = true,
    focusCastBarPosition = true, focusCastBarGap = true,
    focusCastBarAvoidAuras = true, focusCastBarHeight = true,
    focusCastBarWidth = true, focusCastBarBorderEnabled = true,
    focusCastBarBorderThickness = true, focusCastBarBorderColor = true,
    focusCastBarShowIcon = true, focusCastBarIconSide = true,
    focusCastBarIconSize = true, focusCastBarIconGap = true,

    bossShowCastBar = true, bossCastBarPosition = true,
    bossCastBarGap = true, bossCastBarHeight = true,
    bossCastBarWidth = true, bossCastBarFontSize = true, bossCastBarBorderEnabled = true,
    bossCastBarBorderThickness = true, bossCastBarBorderColor = true,
    bossCastBarShowIcon = true, bossCastBarIconSide = true,
    bossCastBarIconSize = true, bossCastBarIconGap = true,
}

-- ── Per-key getter quirks ──────────────────────────────────────
--
-- Copied from the Ace getters they replace, and dead in a healthy
-- profile: AceDB merges BF.unitFrameDefaults in, so a fallback only
-- fires for a key that is genuinely absent -- which is the case the Ace
-- getter was written for. DEFAULTS below is where reset gets its values.

-- `p[key] ~= false` (and the aura getters' `fufGet(key, true)`, which is
-- the same reading): absent means ON.
local TRUE_IF_ABSENT = {
    showHealthPct = true, showHealthPctSymbol = true, showHealthVal = true,
    showNameBar = true, showNameBarText = true, showName = true,
    showLevel = true,
    showPowerBar = true, showPowerText = true,
    showPowerPct = true, showPowerPctSymbol = true, showPowerVal = true,
    focusShowBuffs = true, focusShowDebuffs = true,
    bossShowBuffs = true, bossShowDebuffs = true,
    focusShowCastBar = true, focusCastBarAvoidAuras = true,
    focusCastBarShowIcon = true,
    bossShowCastBar = true, bossCastBarShowIcon = true,
}

-- `p[key] == true`: absent means OFF.
local FALSE_IF_ABSENT = {
    -- The raid-style twin flags: absent means off, as their shipped
    -- default is false.
    focusRaidStyle = true, bossRaidStyle = true,
    focusCastBarDetached = true,
    focusCastBarBorderEnabled = true,
    bossCastBarBorderEnabled = true,
}

-- The `or <value>` fallbacks in the Ace getters, kept to the digit.
local FALLBACK = {
    frameWidth = 156, frameScale = 1.0, iconScale = 1.0, frameAlpha = 1.0,
    healthBarHeight = 22, healthFontSize = 8,
    nameBarHeight = 13, nameFontSize = 11,
    -- The Ace getters branch on `unit == "player"` for these four. None
    -- of the five frames in this file is the player, so the non-player
    -- arm is the only one reachable and it is the only one stated.
    nameOffsetX = -21, nameOffsetY = -2,
    levelFontSize = 10, levelOffsetX = 4, levelOffsetY = -2,
    powerBarHeight = 10, powerFontSize = 7,
    -- 10, matching Defaults.lua's new castBarFontSize and oUF_Castbar.lua's
    -- own fallback. The Ace getter said 8 and was the only reachable fallback
    -- in this table, so focus cast bar text drew 10 while the panel showed 8.
    castBarFontSize = 10,

    bossGrowDirection = "DOWN", bossFrameSpacing = 4,

    focusCastBarPosition = "below", focusCastBarGap = 0,
    focusCastBarHeight = 14, focusCastBarWidth = 156,
    focusCastBarBorderThickness = 1,
    focusCastBarIconSide = "left", focusCastBarIconSize = 20,
    focusCastBarIconGap = 2,

    bossCastBarPosition = "below", bossCastBarGap = 0,
    bossCastBarHeight = 14, bossCastBarWidth = 150, bossCastBarFontSize = 10,
    bossCastBarBorderThickness = 1,
    bossCastBarIconSide = "left", bossCastBarIconSize = 16,
    bossCastBarIconGap = 2,
}

-- Color keys, with the Ace getters' own fallback tables. The value the
-- control sees is an ARRAY; the value stored stays a NAMED table.
local COLOR_FALLBACK = {
    levelColor              = { r = 1, g = 0.82, b = 0          },
    focusCastBarBorderColor = { r = 0, g = 0,    b = 0, a = 1    },
    bossCastBarBorderColor  = { r = 0, g = 0,    b = 0, a = 1    },
}

local function ColorArray(c)
    return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
end

-- The aura fallbacks differ per frame -- boss ships 8 max buffs and 8
-- max debuffs where focus ships 16 -- so they are part of the frame's
-- own spec rather than of the shared table above.
local function AuraFallback(prefix, maxAuras)
    return {
        [prefix .. "BuffSize"]      = 18,
        [prefix .. "BuffsPerRow"]   = 8,
        [prefix .. "MaxBuffs"]      = maxAuras,
        [prefix .. "BuffSpacing"]   = 2,
        [prefix .. "BuffOffsetX"]   = 0,
        [prefix .. "BuffOffsetY"]   = 0,
        [prefix .. "DebuffSize"]    = 18,
        [prefix .. "DebuffsPerRow"] = 8,
        [prefix .. "MaxDebuffs"]    = maxAuras,
        [prefix .. "DebuffSpacing"] = 2,
        [prefix .. "DebuffOffsetX"] = 0,
        [prefix .. "DebuffOffsetY"] = 0,
    }
end

-- ── The five frames ────────────────────────────────────────────
--
-- Everything that differs between them, in one place. `id` is the route
-- id Panel.lua already declares for that tab.
--
-- `unit` is the per-frame sub-table's key AND the aura keys' prefix,
-- which is why Target of Target's sub-table is `targettarget` while its
-- route is `totTab`.
local FRAMES = {
    { id = "focusTab",       unit = "focus",        enableKey = "showFocusFrame",
      title = "Focus Frame",  label = "Focus Frame",
      raidStyleKey = "focusRaidStyle",
      auraPrefix = "focus", auraMax = 16, castBar = "focus" },
    { id = "petTab",         unit = "pet",          enableKey = "showPetFrame",
      title = "Pet Frame",    label = "Pet Frame" },
    { id = "totTab",         unit = "targettarget", enableKey = "showTargetOfTargetFrame",
      title = "Target of Target", label = "Target of Target Frame" },
    { id = "focusTargetTab", unit = "focustarget",  enableKey = "showFocusTargetFrame",
      title = "Focus Target", label = "Focus Target Frame" },
    { id = "bossTab",        unit = "boss",         enableKey = "showBossFrames",
      title = "Boss Frames",  label = "Boss Frames",
      raidStyleKey = "bossRaidStyle",
      auraPrefix = "boss", auraMax = 8, castBar = "boss",
      preview = true },
}

-- Published for Panel.lua, which builds one route per entry. The ids and
-- titles are the Ace args keys and names; keeping ONE list means the route
-- tree and the page builders cannot disagree about which frames exist.
BuzzardFramesOptions.UNITFRAMES_FRAME_TABS = FRAMES

local FRAME_BY_ID = {}
for _, spec in ipairs(FRAMES) do
    spec.auraFallback = spec.auraPrefix
        and AuraFallback(spec.auraPrefix, spec.auraMax) or nil
    FRAME_BY_ID[spec.id] = spec
end

-- ── The routed root, per frame ─────────────────────────────────
--
-- One per unit, built once and cached: the library resolves a `bind` by
-- walking a dotted path into the page's db, and what these pages want
-- is one flat namespace over two tables.
local rootCache, defaultsCache = {}, {}

local function MakeRoot(spec)
    local fb = spec.auraFallback
    return setmetatable({}, {
        __index = function(_, k)
            local p = P()
            if not p then return nil end
            local v
            if FLAT[k] then
                v = p[k]
            else
                v = (p[spec.unit] or {})[k]
            end
            if COLOR_FALLBACK[k] then
                return ColorArray(v or COLOR_FALLBACK[k])
            end
            if TRUE_IF_ABSENT[k]  then return v ~= false end
            if FALSE_IF_ABSENT[k] then return v == true  end
            if v == nil then
                if fb and fb[k] ~= nil then return fb[k] end
                return FALLBACK[k]
            end
            return v
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            if COLOR_FALLBACK[k] and type(v) == "table" then
                -- From the control (or an undo) the value is an array;
                -- from a reset it is the defaults table's named copy.
                -- Either way a FRESH named table is stored, as the Ace
                -- setters do -- never a reference to a table something
                -- else holds.
                local a = v.a
                if a == nil then a = v[4] end
                v = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3], a = a }
                -- The two level-color setters store no alpha at all
                -- (hasAlpha = false), so neither does this.
                if k == "levelColor" then v.a = nil end
            end
            if FLAT[k] then
                p[k] = v
            else
                p[spec.unit] = p[spec.unit] or {}
                p[spec.unit][k] = v
            end
        end,
    })
end

-- The same routing over BuzzardFrames' own defaults, so a right-click
-- "Reset to default" answers with the shipped value rather than with a
-- copy of it kept in this file.
local function MakeDefaults(spec)
    return setmetatable({}, {
        __index = function(_, k)
            local bf = BF()
            local d  = bf and bf.unitFrameDefaults
            d = d and d.profile
            if not d then return nil end
            if FLAT[k] then return d[k] end
            return (d[spec.unit] or {})[k]
        end,
    })
end

local function Root(spec)
    if not rootCache[spec.id] then rootCache[spec.id] = MakeRoot(spec) end
    return rootCache[spec.id]
end

local function DefaultsFor(spec)
    if not defaultsCache[spec.id] then defaultsCache[spec.id] = MakeDefaults(spec) end
    return defaultsCache[spec.id]
end

-- ── Side effects ───────────────────────────────────────────────
--
-- The relayout and update pair each frame's own widgets call. Boss's
-- relayout is the DEBOUNCED one from the top of the Ace file; the other
-- four are the plain locals the assembler shadowed it with. See the
-- header.
local function Relayout(spec)
    return function()
        local bf = BF()
        if not bf then return end
        if spec.unit == "focus" then
            if bf.oufFocus then bf:ApplyOUFFocusLayout() end
        elseif spec.unit == "pet" then
            if bf.oufPet then bf:ApplyOUFPetLayout() end
        elseif spec.unit == "targettarget" then
            if bf.oufTargetOfTarget then bf:ApplyOUFTargetOfTargetLayout() end
        elseif spec.unit == "focustarget" then
            if bf.oufFocusTarget then bf:ApplyOUFFocusTargetLayout() end
        elseif spec.unit == "boss" then
            bf:DebounceOption("oufLayoutBoss", function()
                if bf.oufBoss then bf:ApplyOUFBossFrameLayout() end
            end)
        end
    end
end

local function Update(spec)
    return function()
        local bf = BF()
        if not bf then return end
        if spec.unit == "focus" then
            if bf.oufFocus then bf.oufFocus:UpdateAllElements("Manual") end
        elseif spec.unit == "pet" then
            if bf.oufPet then bf.oufPet:UpdateAllElements("Manual") end
        elseif spec.unit == "targettarget" then
            if bf.oufTargetOfTarget then bf.oufTargetOfTarget:UpdateAllElements("Manual") end
        elseif spec.unit == "focustarget" then
            if bf.oufFocusTarget then bf.oufFocusTarget:UpdateAllElements("Manual") end
        elseif spec.unit == "boss" then
            if bf.oufBoss then
                for i = 1, 5 do
                    local f = bf.oufBoss[i]
                    if f then f:UpdateAllElements("Manual") end
                end
            end
        end
    end
end

-- The live oUF frame this tab configures. Boss answers with frame 1,
-- which is what makeFrameOpts was handed.
local function OufFrame(spec)
    local bf = BF()
    if not bf then return nil end
    if spec.unit == "focus"        then return bf.oufFocus        end
    if spec.unit == "pet"          then return bf.oufPet          end
    if spec.unit == "targettarget" then return bf.oufTargetOfTarget end
    if spec.unit == "focustarget"  then return bf.oufFocusTarget  end
    if spec.unit == "boss"         then return bf.oufBoss and bf.oufBoss[1] end
    return nil
end

local function IsRounded()
    local bf = BF()
    return bf and bf.IsOUFRounded and bf:IsOUFRounded()
end

-- The four cast bar re-stamps a boss castbar change needs, across all
-- five frames. Focus reaches its one frame directly instead.
local function ApplyBossCastbars()
    local bf = BF()
    if not (bf and bf.oufBoss) then return end
    for i = 1, 5 do
        local f = bf.oufBoss[i]
        if f then
            bf:_ApplyOUFCastbarColors(f)
            bf:_ApplyOUFCastbarBgColor(f)
            bf:_ApplyOUFCastbarBorder(f)
            bf:_ApplyOUFCastbarIcon(f)
        end
    end
end

local function ApplyFocusCastbarBorder()
    local bf = BF()
    if bf then bf:_ApplyOUFCastbarBorder(bf.oufFocus) end
end

local function ApplyFocusCastbarIcon()
    local bf = BF()
    if bf then bf:_ApplyOUFCastbarIcon(bf.oufFocus) end
end

-- ── Field shorthands ───────────────────────────────────────────

local function Merge(f, opts)
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sw(bind, label, effect, opts)
    return Merge({ control = "switch", label = label, bind = bind,
                   onChange = effect, disabled = "combat" }, opts)
end

local function Sl(bind, label, lo, hi, step, effect, opts)
    return Merge({ control = "slider", label = label, bind = bind,
                   min = lo, max = hi, step = step,
                   onChange = effect, disabled = "combat" }, opts)
end

local function Dd(bind, label, options, effect, opts)
    return Merge({ control = "dropdown", label = label, bind = bind,
                   options = options, onChange = effect,
                   disabled = "combat" }, opts)
end

local function Col(bind, label, alpha, effect, opts)
    return Merge({ control = "color", label = label, bind = bind,
                   alpha = alpha or nil, onChange = effect,
                   disabled = "combat" }, opts)
end

-- ── Shared option lists ────────────────────────────────────────

local BELOW_ABOVE = {
    { value = "below", text = "Below" },
    { value = "above", text = "Above" },
}

-- Boss cast bar: Below/Above plus the three side/bottom placements
-- (oUF_BossFrames.lua _ApplyOUFBossCastbarLayout). Focus keeps BELOW_ABOVE.
local BOSS_CAST_POSITIONS = {
    { value = "below",  text = "Below"  },
    { value = "above",  text = "Above"  },
    { value = "bottom", text = "Bottom" },
    { value = "left",   text = "Left"   },
    { value = "right",  text = "Right"  },
}

local LEFT_RIGHT = {
    { value = "left",  text = "Left"  },
    { value = "right", text = "Right" },
}

local GROW_OPTIONS = {
    { value = "DOWN",  text = "Down"  },
    { value = "UP",    text = "Up"    },
    { value = "LEFT",  text = "Left"  },
    { value = "RIGHT", text = "Right" },
}

-- ── The position triplets ──────────────────────────────────────
--
-- The Ace makePosGroup built a Position dropdown over the nine standard
-- anchor points plus an X and a Y slider, all three reading and writing
-- one `{ point, x, y }` table in the frame's sub-table. That is what the
-- `anchor` composite IS -- a 3x3 pad with the two offsets beside it --
-- and the shape of the control is the shape of the answer, which a
-- nine-item dropdown never was.
--
-- The three entries carry their own reader and writer rather than a bind
-- path, because each has its OWN fallback: the Ace getter answers
-- `(uf[posKey] or {}).point or defaultPoint`, and the defaults differ
-- per position group.
local function PosField(spec, name, posKey, defaultPoint, defaultX, relayout)
    local unit = spec.unit

    local function slot()
        local p = P()
        local uf = (p and p[unit]) or {}
        return uf[posKey] or {}
    end

    -- Write, then relayout -- the Ace setter's order, including its
    -- ufSet-the-whole-table-first step, which is what materialises the
    -- sub-table and the position table on a profile that has neither.
    local function write(field)
        return function(_, _, v)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            p[unit] = p[unit] or {}
            p[unit][posKey] = p[unit][posKey] or {}
            p[unit][posKey][field] = v
            if relayout then relayout() end
        end
    end

    local function defaultOf(field)
        local bf = BF()
        local d  = bf and bf.unitFrameDefaults
        d = d and d.profile and d.profile[unit] and d.profile[unit][posKey]
        return d and d[field]
    end

    return {
        control = "anchor", label = name,
        id = unit .. "." .. posKey,
        -- The SOFT bounds. Ace set min/max -200..200 with softMin/softMax
        -- -50..50, and the dialog drew the soft pair -- so -50..50 is the
        -- range this control has always presented. Matches Pages_Frames.lua
        -- and the migrated Player/Target pages.
        min = -50, max = 50, disabled = "combat",
        binds = {
            point = { id = unit .. "." .. posKey .. ".point",
                      default = defaultOf("point"),
                      get = function() return slot().point or defaultPoint end,
                      set = write("point") },
            x     = { id = unit .. "." .. posKey .. ".x",
                      default = defaultOf("x"),
                      get = function() return slot().x or defaultX end,
                      set = write("x") },
            y     = { id = unit .. "." .. posKey .. ".y",
                      default = defaultOf("y"),
                      get = function() return slot().y or 0 end,
                      set = write("y") },
        },
    }
end

-- ── The gates ──────────────────────────────────────────────────

local function FrameOff(spec)
    return function()
        local p = P()
        return not (p and p[spec.enableKey])
    end
end

-- Compose the section gate, this frame's gate and whatever predicate a
-- card already carried, into the one `hidden` the library reads.
local function GateGroups(spec, groups, gateOnFrame)
    local off = FrameOff(spec)
    local ufOff = BuzzardFramesOptions.UnitFramesOff
    for _, g in ipairs(groups) do
        local own = g.hidden
        g.hidden = function(node, ctx)
            if ufOff() then return true end
            if gateOnFrame and off() then return true end
            if type(own) == "function" then return own(node, ctx) and true or false end
            return own and true or false
        end
    end
    return groups
end

-- The card that stands in for everything this frame's own switch hid.
-- The Ace panel hid the TAB; a panel route cannot, so the page says
-- where the switch is instead.
local function DisabledFrameNote(spec)
    local off = FrameOff(spec)
    local ufOff = BuzzardFramesOptions.UnitFramesOff
    return { preset = "bare",
             hidden = function() return ufOff() or not off() end,
             fields = {
        { control = "note", wide = true,
          text = ("The %s is turned off. Enable it on the |cffffff00Unit "
              .. "Frames|r page to configure it."):format(spec.label) },
    }}
end

-- ── Size & Position ────────────────────────────────────────────
--
-- `ufGet(unit, key) or 0`: the fallback arm of the two anchor getters,
-- for a profile whose frame has never been positioned. Above its caller,
-- as a local must be.
local function AnchorOr0(spec, key)
    local p = P()
    local uf = (p and p[spec.unit]) or {}
    return uf[key] or 0
end

-- The Ace `_posTracker` description is not migrated: it is AceConfig
-- plumbing that re-derived the two position sliders' soft bounds as a
-- render side effect. Here each slider re-derives its own bounds in its
-- own getter, which is the same thing without the hidden widget.
local function SizePage(spec)
    local relayout = Relayout(spec)
    local off      = FrameOff(spec)
    local d        = DefaultsFor(spec)

    -- The Ace sliders carried softMin/softMax only, which
    -- ClampPositionSlider re-derived from the live screen size on every
    -- get (resolutions change mid-session). The panel slider has min and
    -- max, so the same bounds land there and are re-derived the same way.
    local function PositionEntry(axis)
        local bf   = BF()
        local half = 1024
        if bf then
            half = (axis == "x") and bf:GetPositionHalfW() or bf:GetPositionHalfH()
        end
        return {
            id = spec.unit .. ".ufAnchor" .. axis:upper(),
            min = -half, max = half, step = 1,
            get = function(node)
                local b = BF()
                if not b then return 0 end
                local h = (axis == "x") and b:GetPositionHalfW() or b:GetPositionHalfH()
                node.min, node.max = -h, h
                local x, y = b:GetUFAnchor(spec.unit)
                local v = (axis == "x") and x or y
                v = v or AnchorOr0(spec, (axis == "x") and "anchorX" or "anchorY")
                return math.floor(v - h + 0.5)
            end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                local b = BF()
                if not b then return end
                v = math.floor(v + 0.5)
                local h = (axis == "x") and b:GetPositionHalfW() or b:GetPositionHalfH()
                local curX, curY = b:GetUFAnchor(spec.unit)
                if axis == "x" then
                    b:SetUFAnchor(spec.unit, v + h,
                                  curY or AnchorOr0(spec, "anchorY"))
                else
                    b:SetUFAnchor(spec.unit, curX or AnchorOr0(spec, "anchorX"),
                                  v + h)
                end
                relayout()
            end,
        }
    end

    local groups = {
        -- The frame's own enable switch used to open this card, and it was
        -- the one control here that was NOT gated on the frame's state --
        -- it was the switch that turned it back on. All seven now live
        -- together in the gated Unit Frames card on the section root, so
        -- what is left is the twin switch, which was always gated.
        { preset = "bare", fields = {
            -- The raid-style twin switch. A twin is live only when the
            -- frame and the twin are BOTH on, which is why this one hides
            -- while the frame is off. Only focus and boss declare
            -- `raidStyleKey`; the other three frames have no twin and get
            -- no field.
            --
            -- Experimental: hidden as well behind Preview & Special Options
            -- > Experimental Options > Enable Experimental Options, with
            -- the player/target switches and the "Raid-style Frame Scale"
            -- sliders that size them.
            spec.raidStyleKey and
            { control = "switch",
              label = "Show as Raid/Party frame (friendly only)",
              labelSide = "after", wide = true,
              disabled = "combat",
              hidden = function(...)
                  if BuzzardFramesOptions.ExperimentalOff() then return true end
                  return off(...)
              end,
              id = spec.raidStyleKey, default = d[spec.raidStyleKey],
              desc = "Uses the active Raid/Party layout's full styling and "
                  .. "buff settings for this frame while the unit is "
                  .. "friendly. Enemies keep the normal unit frame.",
              get = function()
                  local p = P()
                  return p and p[spec.raidStyleKey]
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local p = P()
                  if not p then return end
                  p[spec.raidStyleKey] = val
                  -- Live, like the enable switch above: ApplyOUFVisibility
                  -- builds or tears the twin down and swaps the visibility
                  -- drivers on both frames. No reload.
                  local bf = BF()
                  if bf then bf:ApplyOUFVisibility() end
              end } or nil,
        }},

        { title = "Position", preset = "form", hidden = off, fields = {
            -- One field, not two sliders: X and Y are one position, and
            -- the `offsets` composite says so.
            { control = "offsets", id = spec.unit .. ".ufAnchor",
              disabled = "combat",
              captions = { x = "X Position", y = "Y Position" },
              binds = {
                  x = Merge(PositionEntry("x"),
                            { desc = "Horizontal position of the frame anchor." }),
                  y = Merge(PositionEntry("y"),
                            { desc = "Vertical position of the frame anchor." }),
              } },
        }},

        { title = "Size", preset = "form", hidden = off, fields = {
            Sl("frameWidth", "Width", 80, 400, 1, relayout, { hidden = off }),
            Sl("frameScale", "Scale", 0.5, 2.0, 0.05, relayout, { hidden = off }),
            Sl("iconScale", "Icon Scale", 0.5, 2.0, 0.05, relayout, { hidden = off }),
        }},

        { title = "Frame Opacity", preset = "form", hidden = off, fields = {
            -- The one slider on this tab whose effect is not a relayout:
            -- it sets the live frame's alpha directly, as the Ace setter
            -- does.
            Sl("frameAlpha", "Frame Opacity", 0.1, 1.0, 0.05, nil, {
                hidden = off,
                set = function(_, _, v)
                    if InCombatLockdown() then return end
                    Root(spec).frameAlpha = v
                    local f = OufFrame(spec)
                    if f then f:SetAlpha(v) end
                end }),
        }},
    }

    -- Boss alone carries the stacking settings, added to this tab by the
    -- assembler rather than by makeFrameOpts.
    if spec.unit == "boss" then
        groups[#groups + 1] = { title = "Grow Direction", preset = "form",
                                hidden = off, fields = {
            Dd("bossGrowDirection", "Grow Direction", GROW_OPTIONS, relayout,
               { hidden = off,
                 desc = "Direction in which boss frames 2-5 stack relative to "
                     .. "boss frame 1." }),
        }}
        groups[#groups + 1] = { title = "Frame Spacing", preset = "form",
                                hidden = off, fields = {
            Sl("bossFrameSpacing", "Spacing Between Frames", 0, 80, 1, relayout,
               { hidden = off,
                 desc = "Gap between boss frames. Increase to leave room for "
                     .. "aura icons." }),
        }}
    end

    return groups
end

-- ── Name Bar ───────────────────────────────────────────────────

local function NamePage(spec)
    local relayout = Relayout(spec)
    local update   = Update(spec)
    local function bothEffect() relayout(); update() end

    local function NameBarOff()
        return Root(spec).showNameBar == false
    end
    local function NameTextOff()
        return Root(spec).showNameBarText == false
    end
    local function NameOff()
        return Root(spec).showName == false
    end
    local function LevelOff()
        return Root(spec).showLevel == false
    end

    return {
        { title = "Name Bar", preset = "form", fields = {
            Sw("showNameBar", "Show Name Bar", bothEffect, { wide = true }),
        }},

        -- Hidden when the name bar is off: height has no effect when the
        -- strip is hidden and the layout has collapsed.
        { title = "Bar Height", preset = "form", hidden = NameBarOff, fields = {
            Sl("nameBarHeight", "Name Bar Height", 8, 30, 1, relayout,
               { hidden = NameBarOff }),
        }},

        -- The header stays whatever the text switch says, so the switch
        -- can always be flipped back on.
        { title = "Name Bar Text", preset = "form", fields = {
            Sw("showNameBarText", "Show Name Bar Text", bothEffect, { wide = true }),
        }},

        -- Name color is NOT here: it lives in Global > Colors > Names
        -- (and its per-frame overrides), so the per-frame Name Bar tab
        -- intentionally has no color picker.
        { title = "Name Text", preset = "form", hidden = NameTextOff, fields = {
            Sw("showName", "Show Name", relayout,
               { wide = true, hidden = NameTextOff }),
            Sl("nameFontSize", "Font Size", 6, 20, 1, relayout, { hidden = NameOff }),
            Sl("nameOffsetX", "X Offset", -50, 50, 1, relayout, { hidden = NameOff }),
            Sl("nameOffsetY", "Y Offset", -50, 50, 1, relayout, { hidden = NameOff }),
        }},

        { title = "Level Text", preset = "form", hidden = NameTextOff, fields = {
            Sw("showLevel", "Show Level", relayout,
               { wide = true, hidden = NameTextOff }),
            Sl("levelFontSize", "Font Size", 6, 20, 1, relayout, { hidden = LevelOff }),
            Sl("levelOffsetX", "X Offset", -50, 50, 1, relayout, { hidden = LevelOff }),
            Sl("levelOffsetY", "Y Offset", -50, 50, 1, relayout, { hidden = LevelOff }),
            Col("levelColor", "Color", false, bothEffect, { hidden = LevelOff }),
        }},
    }
end

-- ── Health Bar ─────────────────────────────────────────────────
--
-- The Ace healthTab's Color section (hdrColor / useClassColor /
-- healthColor) is absent by construction: makeFrameOpts hides all three
-- on any frame that is not the player, and the assembler then nils them
-- off every one of these five tabs outright. They are on
-- Global > Colors > Health Bars.
local function HealthPage(spec)
    local relayout = Relayout(spec)
    local update   = Update(spec)
    local function bothEffect() relayout(); update() end

    local function PctOff() return Root(spec).showHealthPct == false end
    local function ValOff() return Root(spec).showHealthVal == false end

    return {
        { title = "Bar Height", preset = "form", fields = {
            Sl("healthBarHeight", "Health Bar Height", 8, 50, 1, relayout),
        }},

        { title = "Text", preset = "form", fields = {
            Sl("healthFontSize", "Font Size", 6, 16, 1, bothEffect),
        }},

        { title = "Health Percent", preset = "form", fields = {
            Sw("showHealthPct", "Show Health Percent", update,
               { wide = true, disabled = false }),
            Sw("showHealthPctSymbol", "Show % Symbol", update,
               { wide = true, disabled = false, hidden = PctOff }),
            Merge(PosField(spec, "Position", "healthPctPos", "LEFT", 3, relayout),
                  { hidden = PctOff }),
        }},

        { title = "Health Value", preset = "form", fields = {
            Sw("showHealthVal", "Show Health Value", update,
               { wide = true, disabled = false }),
            Merge(PosField(spec, "Position", "healthValPos", "RIGHT", -10, relayout),
                  { hidden = ValOff }),
        }},
    }
end

-- ── Power Bar ──────────────────────────────────────────────────
--
-- The Detach Power Bar toggle and the Detached Power Bar group are
-- player-only in makeFrameOpts (`hidden = ... or unit ~= "player"`), so
-- they can never appear on any of these five tabs and are not emitted.
-- They belong to the Player Frame page.
local function PowerPage(spec)
    local relayout = Relayout(spec)
    local update   = Update(spec)
    local function bothEffect() relayout(); update() end

    -- Show Power Bar alone: the raid-style twin shows its power bar
    -- whenever the oUF frame's own is on, so this switch moves the twin
    -- too. `force` re-reads the power-bar state, not just the flat size.
    -- Only focus and boss have a twin.
    local function BarToggled()
        bothEffect()
        local bf = BF()
        if spec.raidStyleKey and bf and bf.RefreshTwinLayout then
            bf:RefreshTwinLayout(true)
        end
    end

    local function BarOff()  return Root(spec).showPowerBar  == false end
    local function TextOff() return Root(spec).showPowerText == false end
    local function PctOff()  return Root(spec).showPowerPct  == false end
    local function ValOff()  return Root(spec).showPowerVal  == false end

    return {
        { title = "Power Bar", preset = "form", fields = {
            Sw("showPowerBar", "Show Power Bar", BarToggled),
        }},

        { title = "Bar Height", preset = "form", hidden = BarOff, fields = {
            Sl("powerBarHeight", "Power Bar Height", 4, 20, 1, relayout,
               { hidden = BarOff }),
        }},

        -- The header stays visible so the Show Power Text toggle below it
        -- can always be flipped back on; what hides is everything under
        -- the toggle.
        { title = "Power Bar Text", preset = "form", fields = {
            Sw("showPowerText", "Show Power Text", bothEffect, { wide = true }),
            Sl("powerFontSize", "Font Size", 6, 16, 1, bothEffect,
               { hidden = TextOff }),
        }},

        { title = "Power Percent", preset = "form", hidden = TextOff, fields = {
            Sw("showPowerPct", "Show Power Percent", update,
               { wide = true, disabled = false }),
            Sw("showPowerPctSymbol", "Show % Symbol", update,
               { wide = true, disabled = false, hidden = PctOff }),
            Merge(PosField(spec, "Position", "powerPctPos", "LEFT", 3, relayout),
                  { hidden = PctOff }),
        }},

        { title = "Power Value", preset = "form", hidden = TextOff, fields = {
            Sw("showPowerVal", "Show Power Value", update,
               { wide = true, disabled = false }),
            Merge(PosField(spec, "Position", "powerValPos", "RIGHT", -10, relayout),
                  { hidden = ValOff }),
        }},
    }
end

-- ── Auras (Focus and Boss) ─────────────────────────────────────
--
-- Every widget on this tab writes through the same shape: the per-frame
-- sub-table, then a relayout. That is the Ace fufSet/bufSet -- which run
-- the relayout even for the two Show switches, so they do here too.
local function AuraCard(spec, title, kind)
    local prefix   = spec.auraPrefix
    local relayout = Relayout(spec)
    local showKey  = prefix .. "Show" .. kind .. "s"
    local function Off() return Root(spec)[showKey] == false end
    local maxHi = (kind == "Debuff") and 40 or 32
    return { title = title, preset = "form", fields = {
        -- No combat guard and no combat disable on the Show switch: the
        -- Ace toggle carried neither. The write still lands in fufSet,
        -- which has the guard.
        Sw(showKey, "Show " .. kind .. "s", relayout,
           { wide = true, disabled = false }),
        Sl(prefix .. kind .. "Size", "Icon Size", 10, 36, 1, relayout,
           { hidden = Off }),
        Sl(prefix .. kind .. "sPerRow", "Per Row", 1, 32, 1, relayout,
           { hidden = Off }),
        Sl(prefix .. "Max" .. kind .. "s", "Max Icons", 1, maxHi, 1, relayout,
           { hidden = Off }),
        Sl(prefix .. kind .. "Spacing", "Spacing", 0, 10, 1, relayout,
           { hidden = Off }),
        Sl(prefix .. kind .. "OffsetX", "X Offset", -50, 50, 1, relayout,
           { hidden = Off }),
        Sl(prefix .. kind .. "OffsetY", "Y Offset", -50, 50, 1, relayout,
           { hidden = Off }),
    }}
end

local function AurasPage(spec)
    return {
        AuraCard(spec, "Debuffs", "Debuff"),
        AuraCard(spec, "Buffs",   "Buff"),
    }
end

-- ── Cast Bar (Focus and Boss) ──────────────────────────────────
--
-- Two cast bars that are nearly but not quite the same tab. Focus can be
-- DETACHED -- which brings its own Width slider and takes the attached
-- Position, Y Offset and Avoid Auras with it -- and boss cannot; boss
-- has no Avoid Auras key at all. Their font sizes are stored in
-- different places (see FLAT above), and their side effects differ: the
-- focus bar re-stamps one frame, the boss one walks all five.
local function CastBarPage(spec)
    local relayout = Relayout(spec)
    local isBoss   = (spec.unit == "boss")
    local prefix   = spec.castBar
    local root     = Root(spec)

    local function Shown()    return root[prefix .. "ShowCastBar"] end
    local function Detached() return Shown() and root.focusCastBarDetached end
    local function Attached() return Shown() and not root.focusCastBarDetached end

    -- What each half of the tab hides on. Boss has no detach, so its
    -- placement and size controls follow the master switch alone.
    local function NotShown()    return not Shown() end
    local function NotAttached()
        if isBoss then return not Shown() end
        return not Attached()
    end
    local function NotDetached() return not Detached() end

    local borderEnabledKey = prefix .. "CastBarBorderEnabled"
    local function NoBorderSection()
        return not Shown() or IsRounded()
    end
    local function NoBorderDetail()
        return NoBorderSection() or not root[borderEnabledKey]
    end
    local iconKey = prefix .. "CastBarShowIcon"
    local function NoIconDetail()
        return not Shown() or not root[iconKey]
    end

    local borderEffect = isBoss and ApplyBossCastbars or ApplyFocusCastbarBorder
    local iconEffect   = isBoss and ApplyBossCastbars or ApplyFocusCastbarIcon
    -- The Show Spell Icon switch also changes the bar's edge insets (the
    -- bar gives the icon its room), and those are stamped by the LAYOUT,
    -- not by the icon re-stamp -- so the toggle relayouts as well, or the
    -- bar keeps reserving space for an icon that is no longer there.
    local iconToggle = function(...)
        iconEffect(...)
        relayout(...)
    end

    local placement = {
        Dd(prefix .. "CastBarPosition", "Cast Bar Position",
           isBoss and BOSS_CAST_POSITIONS or BELOW_ABOVE, relayout,
           { desc = isBoss
                and ("Where the cast bar is anchored relative to the boss frame. "
                    .. "Below and Above leave room for the buff / debuff row; "
                    .. "Bottom sits directly under the power bar and pushes the "
                    .. "buff row below the cast bar; Left and Right place a "
                    .. "frame-wide bar beside the frame.")
                or  "Where the cast bar is anchored when attached to the focus frame.",
             hidden = NotAttached }),
        Sl(prefix .. "CastBarGap", isBoss and "Offset" or "Y Offset", -50, 50, 1, relayout,
           { hidden = NotAttached,
             desc = isBoss
                and "Distance between the cast bar and the frame: vertical for "
                    .. "Below / Above / Bottom, horizontal for Left / Right."
                or nil }),
    }
    if not isBoss then
        table.insert(placement, 1,
            Sw("focusCastBarDetached", "Detach from Focus Frame", relayout, {
                wide = true, hidden = NotShown,
                desc = "When detached, the cast bar can be positioned "
                    .. "independently. Unlock frames to drag it." }))
        placement[#placement + 1] =
            Sw("focusCastBarAvoidAuras", "Avoid Auras", relayout, {
                wide = true, hidden = NotAttached,
                desc = "Automatically push the cast bar down (or up) to clear "
                    .. "any aura icons that are currently visible, based on "
                    .. "the live row count." })
    end

    local size = {
        Sl(prefix .. "CastBarHeight", "Bar Height", 4, 30, 1, relayout,
           { hidden = NotShown }),
    }
    if isBoss then
        -- Left / Right only: those bars sit beside the frame and take
        -- their own width; Below / Above / Bottom span the frame.
        local function NotSide()
            if NotShown() then return true end
            local pos = root.bossCastBarPosition
            return pos ~= "left" and pos ~= "right"
        end
        size[#size + 1] = Sl("bossCastBarWidth", "Bar Width", 40, 600, 1,
                             relayout, { hidden = NotSide,
                                 desc = "Width of a Left / Right cast bar." })
        size[#size + 1] = Sl("bossCastBarFontSize", "Font Size", 6, 16, 1,
                             relayout, { hidden = NotShown })
    else
        size[#size + 1] = Sl("focusCastBarWidth", "Bar Width", 40, 600, 1,
                             relayout, { hidden = NotDetached })
        -- The one per-unit key on this tab: the Ace getter is
        -- ufGet("focus", "castBarFontSize"), not a focusCastBar* profile
        -- key. Its setter has NO combat guard of its own -- ufSet carries
        -- one -- which is why it is written out rather than shorthanded.
        size[#size + 1] = Sl("castBarFontSize", "Font Size", 6, 16, 1,
                             relayout, { hidden = NotShown })
    end

    return {
        { title = "Cast Bar", preset = "form", fields = {
            Sw(prefix .. "ShowCastBar", "Show Cast Bar", relayout, { wide = true }),
        }},

        { title = "Placement", preset = "form", hidden = NotShown,
          fields = placement },

        { title = "Size", preset = "form", hidden = NotShown, fields = size },

        -- The Border card goes while a rounded Border Mode is active: the
        -- castbar gets a ring from the shared rounded art, tinted by
        -- frameBorderColor.
        { title = "Border", preset = "form", hidden = NoBorderSection, fields = {
            Sw(borderEnabledKey, "Enable Border", borderEffect,
               { hidden = NoBorderSection }),
            Sl(prefix .. "CastBarBorderThickness", "Thickness", 1, 6, 1,
               borderEffect, { hidden = NoBorderDetail }),
            Col(prefix .. "CastBarBorderColor", "Color", true, borderEffect,
                { hidden = NoBorderDetail }),
        }},

        { title = "Spell Icon", preset = "form", hidden = NotShown, fields = {
            Sw(iconKey, "Show Spell Icon", iconToggle, { hidden = NotShown }),
            Dd(prefix .. "CastBarIconSide", "Icon Side", LEFT_RIGHT, relayout,
               { hidden = NoIconDetail }),
            Sl(prefix .. "CastBarIconSize", "Icon Size", 10, 48, 1, relayout,
               { hidden = NoIconDetail }),
            Sl(prefix .. "CastBarIconGap", "Gap", 0, 20, 1, relayout, {
                hidden = NoIconDetail,
                desc = "Distance in pixels between the cast bar and the spell "
                    .. "icon." }),
        }},
    }
end

-- ── Preview (boss only) ────────────────────────────────────────
--
-- The switch and the per-slot Enemy / Friendly toggles are saved in
-- db.global (showBossPreview / bossPreviewFriendly, Defaults.lua) -- like
-- the Preview section's showPreview: global, so never part of a profile
-- export, and the preview runs whenever the panel is open. The engine
-- (UnitFrames/oUF_BossPreview.lua) force-shows the five real boss frames
-- with dummy data and, with the raid-style twin on, stands the raid
-- preview engine's frame in for the friendly slots.
--
-- One Enemy / Friendly switch per boss slot, read and written through the
-- engine (BF:IsBossPreviewFriendly / SetBossPreviewFriendly) rather than
-- a bind. Above its caller, as a local must be.
local function BossPreviewUnitFields()
    local fields = {}
    for i = 1, 5 do
        fields[i] = { control = "segmented", label = "Boss " .. i,
            id = "bossPreviewFriendly" .. i, default = (i >= 4) and "friendly" or "enemy",
            disabled = "combat",
            options = {
                { value = "enemy",    text = "Enemy"    },
                { value = "friendly", text = "Friendly" },
            },
            get = function()
                local bf = BF()
                local friendly = bf and bf.IsBossPreviewFriendly and bf:IsBossPreviewFriendly(i)
                return friendly and "friendly" or "enemy"
            end,
            set = function(_, _, val)
                local bf = BF()
                if bf and bf.SetBossPreviewFriendly then
                    bf:SetBossPreviewFriendly(i, val == "friendly")
                end
            end }
    end
    return fields
end

local function PreviewPage(spec)
    local function PreviewOn()
        local bf = BF()
        return bf and bf.IsBossPreviewEnabled and bf:IsBossPreviewEnabled() or false
    end
    return {
        { title = "Preview", preset = "form", fields = {
            { control = "switch", label = "Preview Boss Frames",
              id = "bossPreview", default = false, wide = true,
              disabled = "combat",
              desc = "Shows all five boss frames where they really sit, "
                  .. "with sample data: bosses 1-3 as enemies, 4-5 as "
                  .. "friendly, each with a looping cast bar and sample "
                  .. "buff / debuff icons. With the raid-style twin on, "
                  .. "the friendly slots show the twin. Shown whenever this "
                  .. "panel is open; pauses in combat.",
              get = PreviewOn,
              set = function(_, ctx, val)
                  local bf = BF()
                  if not bf or not bf.SetBossPreview then return end
                  bf:SetBossPreview(val)
                  ctx.app:RefreshPage()
              end },
            { control = "note", wide = true,
              hidden = function() return not PreviewOn() end,
              text = "Position, size, cast bar and aura edits on the other "
                  .. "tabs show on the preview as you make them." },
        }},
        { title = "Units", preset = "form", hidden = function() return not PreviewOn() end,
          fields = BossPreviewUnitFields() },
    }
end

-- ── The subtabs ────────────────────────────────────────────────

local BUILDERS = {
    sizeTab    = SizePage,
    nameTab    = NamePage,
    healthTab  = HealthPage,
    powerTab   = PowerPage,
    aurasTab   = AurasPage,
    castBarTab = CastBarPage,
    previewTab = PreviewPage,
}

-- The Ace sub-tab order, by the `order` makeFrameOpts and the assembler
-- gave them: Size & Position 1, Name Bar 2, Health Bar 3, Power Bar 4,
-- Auras 5, Cast Bar 6.
function BuzzardFramesOptions:UnitFramesFrameSubtabs(tabId)
    local spec = FRAME_BY_ID[tabId]
    if not spec then return {} end
    local out = {
        { id = "sizeTab",   title = "Size & Position" },
        { id = "nameTab",   title = "Name Bar" },
        { id = "healthTab", title = "Health Bar" },
        { id = "powerTab",  title = "Power Bar" },
    }
    if spec.auraPrefix then out[#out + 1] = { id = "aurasTab",   title = "Auras" }    end
    if spec.castBar    then out[#out + 1] = { id = "castBarTab", title = "Cast Bar" } end
    -- Not an Ace tab: the boss preview is new with the panel.
    if spec.preview    then out[#out + 1] = { id = "previewTab", title = "Preview" }  end
    return out
end

-- Route children for one of the five tabs. Panel.lua's own SubtabRoutes
-- calls a builder with (id, title) and cannot pass which FRAME the
-- subtab belongs to, so these five nodes are built here instead.
function BuzzardFramesOptions:UnitFramesFrameRoutes(tabId)
    local out = {}
    for i, st in ipairs(self:UnitFramesFrameSubtabs(tabId)) do
        out[i] = {
            id = st.id, title = st.title,
            page = function() return self:UnitFramesFramePage(tabId, st.id) end,
        }
    end
    return out
end

function BuzzardFramesOptions:UnitFramesFramePage(tabId, subtabId)
    local spec = FRAME_BY_ID[tabId]
    local build = spec and BUILDERS[subtabId]
    if not build then return { groups = {} } end

    local groups = { self:UnitFramesDisabledNote() }
    -- EVERY tab is gated on the frame now, Size & Position included. That
    -- page was the exception only because it carried the switch that turned
    -- the frame back on; with the seven switches gathered on the section
    -- root it has nothing the others do not, so it hides and explains
    -- itself the same way.
    groups[#groups + 1] = DisabledFrameNote(spec)
    for _, g in ipairs(GateGroups(spec, build(spec), true)) do
        groups[#groups + 1] = g
    end

    return {
        db       = function() return Root(spec) end,
        defaults = function() return DefaultsFor(spec) end,
        groups   = groups,
    }
end
