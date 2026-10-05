-- ============================================================
-- BuzzardFramesOptions: Pages_Colors.lua
-- The Global Styles > Colors page, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Colors.lua
-- (BF:BuildColorsOptions): the same five inline groups -- Power Bar
-- Colors, Class Colors, Cast Bar Colors, Health Gradient Colors,
-- Background Health Gradient Colors -- as five cards on one page, with
-- the same storage and the same post-set cascades in the same order.
--
-- Storage, and why it is not the routed kind every other page uses:
--
--   * Power Bar Colors -> rpDB.profile.healthPower.customPowerColors, a
--     historical carve-out from the Health & Power Bars section, kept
--     where it is for save-file compatibility.
--   * Class Colors, Health Gradient and Background Health Gradient ->
--     rpDB.profile.colors, a top-level section of its own.
--   * Cast Bar Colors -> ufDB.profile.castBar* -- cast bars are a Unit
--     Frame feature and the raid/party frames have none.
--
-- All four bypass GetSectionProfile / WriteSectionKey deliberately: they
-- are GLOBAL, shared across every Layout and across the Raid/Party frames
-- and the Unit Frames at once, and they mutate process-wide tables
-- (BF.PowerTypeColors, BF.classColors) that indicator and unit frame code
-- reads directly. The Ace page reached the same two profile tables by the
-- same two accessors; this file is those accessors and nothing more, which
-- is what keeps the two panels in step while both exist.
--
-- Every field keeps get/set (the read side is a live process table, not
-- the stored one) and so carries an `id` and a `default` instead of a
-- `bind`, which is what makes right-click Undo and Reset work on each
-- swatch. The defaults come from Buzzard Frames' own pristine tables --
-- BF._DefaultPowerTypeColors, BF._DefaultClassColors,
-- BF.raidPartyFrameDefaults.profile.colors, BF.unitFrameDefaults.profile
-- -- never from literals restated here.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- Nothing at file scope reads the addon: this page is built long after
-- load, and asked for again on every render.
local function BF() return _G.BuzzardFrames end

-- ── The three profile tables ───────────────────────────────────
--
-- The Ace file's getGP / getColorsP, verbatim in behavior: ALWAYS the
-- global pseudo-layout, whatever the per-Layout toggles say, because
-- nothing on this page is per-Layout.

local function GetGP()
    local bf = BF()
    local db = bf and bf.rpDB
    return db and db.profile and db.profile.healthPower
end

local function GetColorsP()
    local bf = BF()
    local db = bf and bf.rpDB
    return db and db.profile and db.profile.colors
end

local function GetUFP()
    local bf = BF()
    local db = bf and bf.ufDB
    return db and db.profile
end

-- ── What a swatch resets TO ────────────────────────────────────
--
-- Buzzard Frames' own tables, in the shape the color control speaks
-- ({ r, g, b, a } as an array). A copy of the numbers here would be a
-- second answer to the same question, and the two would part company the
-- first time a default changed.

-- Named table -> the control's array. `a` is carried only where the
-- picker offers opacity, so a swatch with `alpha = false` stores exactly
-- what its Ace twin stored: three components and no fourth.
local function ColorArray(c, withAlpha)
    if not c then return nil end
    if withAlpha then return { c.r, c.g, c.b, c.a or 1 } end
    return { c.r, c.g, c.b }
end

-- The array (or an undo's, or a reset's) back to the stored named table.
-- A FRESH table every time, as every Ace setter here built one -- never a
-- reference to something else's.
local function ColorTable(v, withAlpha)
    local r, g, b = v.r or v[1], v.g or v[2], v.b or v[3]
    if not withAlpha then return { r = r, g = g, b = b } end
    local a = v.a
    if a == nil then a = v[4] end
    if a == nil then a = 1 end
    return { r = r, g = g, b = b, a = a }
end

-- The pristine power type color, before any custom overlay -- exactly
-- what the group's "Reset to Defaults" restores by nilling the whole
-- customPowerColors table.
local function PowerDefault(key)
    local bf = BF()
    local d  = bf and bf._DefaultPowerTypeColors
    return ColorArray(d and d[key], true)
end

-- The pristine class color. BF._DefaultClassColors is seeded from
-- RAID_CLASS_COLORS at login and never mutated, which makes it the
-- baseline the Ace reset returns to; RAID_CLASS_COLORS itself is the
-- fallback for the window before that seeding has run.
local function ClassDefault(className)
    local bf = BF()
    local d  = bf and bf._DefaultClassColors
    local c  = d and d[className]
    if not c then
        c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[className]
    end
    return ColorArray(c, false)
end

-- rpDB.profile.colors' shipped defaults -- the six gradient colors.
local function ColorsDefault(key)
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile and d.profile.colors
    return d and d[key]
end

-- ufDB.profile's shipped default for one key, or the Ace getter's own
-- fallback table when the defaults have not been reached yet. The
-- fallbacks are the Ace file's, to the digit.
local function UFDefault(key, fallback)
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    d = d and d.profile
    return (d and d[key]) or fallback
end

-- ── The post-set cascades ──────────────────────────────────────
--
-- One function per chain the Ace setters ran, in the order those setters
-- ran it, call for call -- including which of them are dot calls and
-- which are colon calls, because the Ace file is not consistent about it
-- and the receivers differ.
--
-- The WRITE has already happened in the setter; these are the frame
-- refreshes, scheduled by the color control's own tier (debounce), so a
-- drag round the color wheel coalesces into one cascade.

local function RefreshPowerColors()
    local bf = BF()
    if not bf then return end
    if bf.ApplyCustomPowerColors then bf:ApplyCustomPowerColors() end
    for frame in pairs(bf.activeFrames or {}) do bf:UpdatePower(frame) end
    if bf._RefreshAllOUFPowerColors then bf:_RefreshAllOUFPowerColors() end
    if bf.RefreshPreviewPowerBar then bf.RefreshPreviewPowerBar() end
end

-- The class cascade ends with the preview NAME as well as the preview
-- health bar: preview names are class-colored out of BF.classColors, and
-- without that last call they kept the color they were drawn with.
local function RefreshClassColors()
    local bf = BF()
    if not bf then return end
    if bf.ApplyCustomClassColors then bf:ApplyCustomClassColors() end
    for frame in pairs(bf.activeFrames or {}) do bf:UpdateHealth(frame) end
    if bf._RefreshAllOUFClassColors then bf:_RefreshAllOUFClassColors() end
    if bf.RefreshPreviewHealthBar then bf.RefreshPreviewHealthBar() end
    if bf.RefreshPreviewName      then bf:RefreshPreviewName()      end
end

-- The gradient cascade rebuilds the color curves first -- stale curves
-- repainted are the wrong colors, briefly and visibly -- then walks the
-- raid/party frames, the preview and every unit frame that consumes them.
--
-- The last block is not redundant with the UpdateAllElements walk above
-- it: the on-tick health update only refreshes a frame's BACKGROUND
-- color when that frame already carries the gradient flag, and the flag
-- is wired at layout time -- so toggling back into gradient mode needs
-- the explicit background pass.
local function RefreshHealthGradientColors()
    local bf = BF()
    if not bf then return end
    if bf.RebuildHealthGradientCurves then bf:RebuildHealthGradientCurves() end
    for frame in pairs(bf.activeFrames or {}) do bf:UpdateHealth(frame) end
    if bf.RefreshHealthBarLayout  then bf:RefreshHealthBarLayout()  end
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
    if bf.oufPlayer         then bf.oufPlayer:UpdateAllElements("Manual")         end
    if bf.oufTarget         then bf.oufTarget:UpdateAllElements("Manual")         end
    if bf.oufFocus          then bf.oufFocus:UpdateAllElements("Manual")          end
    if bf.oufPet            then bf.oufPet:UpdateAllElements("Manual")            end
    if bf.oufTargetOfTarget then bf.oufTargetOfTarget:UpdateAllElements("Manual") end
    if bf.oufFocusTarget    then bf.oufFocusTarget:UpdateAllElements("Manual")    end
    if bf.oufBoss then
        for i = 1, 5 do
            if bf.oufBoss[i] then bf.oufBoss[i]:UpdateAllElements("Manual") end
        end
    end
    if bf._ApplyOUFHealthBgColor then
        local function apply(f) if f then bf:_ApplyOUFHealthBgColor(f) end end
        apply(bf.oufPlayer); apply(bf.oufTarget); apply(bf.oufFocus); apply(bf.oufPet)
        apply(bf.oufTargetOfTarget); apply(bf.oufFocusTarget)
        if bf.oufBoss then for i = 1, 5 do apply(bf.oufBoss[i]) end end
    end
end

-- The cast bar cascade, shared by all three of its swatches bar the call
-- that differs: the fill and the uninterruptible color repaint through
-- _ApplyOUFCastbarColors, the background through _ApplyOUFCastbarBgColor.
-- The Incoming Casts party preview is re-shown after either, but only
-- while it is up -- it is a preview, and rebuilding one nobody is looking
-- at would put it on screen.
local function RefreshCastBar(which)
    return function()
        local bf = BF()
        if not bf then return end
        if which == "bg" then
            if bf._ApplyOUFCastbarBgColor then bf:_ApplyOUFCastbarBgColor() end
        else
            if bf._ApplyOUFCastbarColors then bf:_ApplyOUFCastbarColors() end
        end
        if bf.IncomingCasts and bf.IncomingCasts._partyPreviewShown then
            bf.IncomingCasts:ShowPartyPreview()
        end
    end
end

-- ── Field factories ────────────────────────────────────────────
--
-- The Ace file's three widget factories, one for one. They are what
-- stopped the Ace page being sixteen near-identical copies of the same
-- twelve lines, and they do the same job here.

-- Hidden unless the group's own "use custom" switch is on -- the Ace
-- `hidden` predicates, unchanged. A hidden field takes no room, and the
-- library watches a function predicate, so flipping the switch reveals
-- the swatches without the setter asking for anything.
local function PowerColorsOff()
    local gp = GetGP()
    return not (gp and gp.useCustomPowerColors)
end

local function ClassColorsOff()
    local cp = GetColorsP()
    return not (cp and cp.useCustomClassColors)
end

-- `key` is the BF.PowerTypeColors / customPowerColors token ("MANA").
-- The READ is the live shared table, not the stored override: that is
-- what the frames are actually painting, which is what the Ace getter
-- read and the only value that is right while the override is absent.
local function PowerColor(id, label, key)
    return {
        control = "color", label = label, id = id, alpha = true,
        default = PowerDefault(key),
        hidden = PowerColorsOff, disabled = "combat",
        onChange = RefreshPowerColors,
        get = function()
            local bf = BF()
            local c = bf and bf.PowerTypeColors and bf.PowerTypeColors[key]
            if not c then return { 0, 0, 0, 1 } end
            return { c.r, c.g, c.b, c.a or 1 }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local gp = GetGP()
            if gp then
                gp.customPowerColors = gp.customPowerColors or {}
                gp.customPowerColors[key] = ColorTable(v, true)
            end
        end,
    }
end

-- `className` is the BF.classColors key ("DEATHKNIGHT"). No alpha: the
-- Ace widget had hasAlpha = false and its setter stored three components.
local function ClassColor(id, label, className)
    return {
        control = "color", label = label, id = id,
        default = ClassDefault(className),
        hidden = ClassColorsOff, disabled = "combat",
        onChange = RefreshClassColors,
        get = function()
            local bf = BF()
            local c = bf and bf.classColors and bf.classColors[className]
            if not c then return { 1, 1, 1 } end
            return { c.r, c.g, c.b }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local cp = GetColorsP()
            if cp then
                cp.customClassColors = cp.customClassColors or {}
                cp.customClassColors[className] = ColorTable(v, false)
            end
        end,
    }
end

-- `key` is the rpDB.profile.colors key ("healthGradientHigh"). The Ace
-- factory took a `fallback` table for the window before the key exists;
-- here that fallback IS the shipped default, read from the defaults
-- table, so the getter's fallback and the field's reset value cannot
-- disagree.
local function GradientColor(id, label, key)
    local fallback = ColorsDefault(key)
    return {
        control = "color", label = label, id = id, alpha = true,
        default = ColorArray(fallback, true),
        disabled = "combat",
        onChange = RefreshHealthGradientColors,
        get = function()
            local cp = GetColorsP()
            local c  = (cp and cp[key]) or fallback
            if not c then return { 0, 0, 0, 1 } end
            return { c.r, c.g, c.b, c.a or 1 }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local cp = GetColorsP()
            if cp then cp[key] = ColorTable(v, true) end
        end,
    }
end

-- A cast bar swatch. ufDB.profile, written whole as the Ace setters did.
local function CastBarColor(id, label, desc, alpha, fallback, effect)
    return {
        control = "color", label = label, id = id, desc = desc,
        alpha = alpha or nil,
        default = ColorArray(UFDefault(id, fallback), alpha),
        disabled = "combat", onChange = effect,
        get = function()
            local p = GetUFP()
            local c = (p and p[id]) or fallback
            return ColorArray(c, alpha)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local p = GetUFP()
            if p then p[id] = ColorTable(v, alpha) end
        end,
    }
end

-- A group's "Reset to Defaults". `clear` empties whatever the Ace `func`
-- emptied, then the cascade runs and the page is re-read: every swatch on
-- the card is computed, not bound, so nothing else would notice that the
-- values under them had changed. (The Ace dialog re-read the whole tab
-- after every set for the same reason.)
local function ResetButton(clear, effect, hidden)
    return {
        -- Destructive: it throws away every color on the card, and
        -- pressing it again does not bring them back.
        control = "button", label = "Reset to Defaults", danger = true,
        disabled = "combat", hidden = hidden,
        onClick = function(_, ctx)
            if InCombatLockdown() then return end
            clear()
            effect()
            ctx.app:RefreshPage()
        end,
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:ColorsPage()
    return {
        groups = {
            -- powerBarColorsGroup
            { title = "Power Bar Colors", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "These colors are shared with the Unit Frames power "
                      .. "bar. Changes here apply to all Raid/Party and Unit "
                      .. "Frame power bars across every Layout." },
                { control = "switch", label = "Use Custom Power Colors",
                  id = "useCustomPowerColors",
                  default = (function()
                      local bf = BF()
                      local d  = bf and bf.raidPartyFrameDefaults
                      d = d and d.profile and d.profile.healthPower
                      return d and d.useCustomPowerColors
                  end)(),
                  desc = "Override the default power type colors with custom "
                      .. "colors.",
                  width = "full", labelSide = "after", disabled = "combat",
                  onChange = RefreshPowerColors,
                  get = function()
                      local gp = GetGP()
                      return gp and gp.useCustomPowerColors == true
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local gp = GetGP()
                      if gp then gp.useCustomPowerColors = v end
                  end },
                PowerColor("manaColor",       "Mana",         "MANA"),
                PowerColor("rageColor",       "Rage",         "RAGE"),
                PowerColor("focusColor",      "Focus",        "FOCUS"),
                PowerColor("energyColor",     "Energy",       "ENERGY"),
                PowerColor("runicPowerColor", "Runic Power",  "RUNIC_POWER"),
                PowerColor("insanityColor",   "Insanity",     "INSANITY"),
                PowerColor("maelstromColor",  "Maelstrom",    "MAELSTROM"),
                PowerColor("lunarPowerColor", "Astral Power", "LUNAR_POWER"),
                PowerColor("holyPowerColor",  "Holy Power",   "HOLY_POWER"),
                PowerColor("furyColor",       "Fury",         "FURY"),
                PowerColor("painColor",       "Pain",         "PAIN"),
                PowerColor("essenceColor",    "Essence",      "ESSENCE"),
                ResetButton(function()
                    local gp = GetGP()
                    if gp then gp.customPowerColors = nil end
                end, RefreshPowerColors, PowerColorsOff),
            }},

            -- classColorsGroup
            { title = "Class Colors", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "These colors are shared with the Unit Frames. "
                      .. "Changes here apply to class-colored text and health "
                      .. "bars on both the Raid/Party Frames and the Unit "
                      .. "Frames across every Layout." },
                { control = "switch", label = "Use Custom Class Colors",
                  id = "useCustomClassColors",
                  default = (function()
                      local d = ColorsDefault("useCustomClassColors")
                      return d
                  end)(),
                  desc = "Override the default class colors with custom "
                      .. "colors. When disabled, BuzzardFrames uses the "
                      .. "standard Blizzard class colors (or whatever an "
                      .. "external class-color addon has set).",
                  width = "full", labelSide = "after", disabled = "combat",
                  onChange = RefreshClassColors,
                  get = function()
                      local cp = GetColorsP()
                      return cp and cp.useCustomClassColors == true
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local cp = GetColorsP()
                      if cp then cp.useCustomClassColors = v end
                  end },
                -- 13 classes in the order Blizzard's own UI shows them,
                -- which is alphabetical rather than by class ID.
                ClassColor("deathknightColor", "Death Knight", "DEATHKNIGHT"),
                ClassColor("demonhunterColor", "Demon Hunter", "DEMONHUNTER"),
                ClassColor("druidColor",       "Druid",        "DRUID"),
                ClassColor("evokerColor",      "Evoker",       "EVOKER"),
                ClassColor("hunterColor",      "Hunter",       "HUNTER"),
                ClassColor("mageColor",        "Mage",         "MAGE"),
                ClassColor("monkColor",        "Monk",         "MONK"),
                ClassColor("paladinColor",     "Paladin",      "PALADIN"),
                ClassColor("priestColor",      "Priest",       "PRIEST"),
                ClassColor("rogueColor",       "Rogue",        "ROGUE"),
                ClassColor("shamanColor",      "Shaman",       "SHAMAN"),
                ClassColor("warlockColor",     "Warlock",      "WARLOCK"),
                ClassColor("warriorColor",     "Warrior",      "WARRIOR"),
                -- The Ace page put an invisible full-width description
                -- above this button to break the row of swatches. A field
                -- that must head its own row says so itself here, and it
                -- says it only while the button is showing.
                (function()
                    local b = ResetButton(function()
                        local cp = GetColorsP()
                        if cp then cp.customClassColors = nil end
                    end, RefreshClassColors, ClassColorsOff)
                    b.newRow = true
                    return b
                end)(),
            }},

            -- castBarColorsGroup
            { title = "Cast Bar Colors", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "These colors are shared by the Unit Frames cast "
                      .. "bars and the Incoming Casts module." },
                CastBarColor("castBarColor", "Cast Color",
                    "Bar color when the cast can be interrupted. Applies to "
                    .. "all unit frame cast bars.",
                    false, { r = 1, g = 0.84, b = 0 }, RefreshCastBar("fill")),
                CastBarColor("castBarUninterruptibleColor",
                    "Uninterruptible Color",
                    "Bar color when the cast cannot be interrupted. Applies "
                    .. "to all unit frame cast bars.",
                    false, { r = 0.565, g = 0.557, b = 0.545 },
                    RefreshCastBar("fill")),
                CastBarColor("castBarBgColor", "Background Color",
                    "Cast bar background color. Applies to all unit frame "
                    .. "cast bars.",
                    true, { r = 0, g = 0, b = 0, a = 0.6 },
                    RefreshCastBar("bg")),
                -- The card's own Reset, as every other color card here
                -- has. These three live on ufDB.profile rather than on the
                -- colors table, so clearing them is three nils there; the
                -- swatches then read the same fallbacks their `default`
                -- names, which is what the right-click reset on each one
                -- already restores individually.
                ResetButton(function()
                    local p = GetUFP()
                    if p then
                        p.castBarColor                = nil
                        p.castBarUninterruptibleColor = nil
                        p.castBarBgColor              = nil
                    end
                end, function()
                    -- Both halves: the fill colors and the background are
                    -- applied by different functions, and this clears both.
                    RefreshCastBar("fill")()
                    RefreshCastBar("bg")()
                end, nil),
            }},

            -- healthGradientColorsGroup
            { title = "Health Gradient Colors", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "These colors are shared by the Raid/Party Frames "
                      .. "and the Unit Frames." },
                GradientColor("healthGradientHigh", "Full Health",
                               "healthGradientHigh"),
                GradientColor("healthGradientMid",  "Half Health",
                               "healthGradientMid"),
                GradientColor("healthGradientLow",  "Low Health",
                               "healthGradientLow"),
                ResetButton(function()
                    local cp = GetColorsP()
                    if cp then
                        cp.healthGradientHigh = nil
                        cp.healthGradientMid  = nil
                        cp.healthGradientLow  = nil
                    end
                end, RefreshHealthGradientColors, nil),
            }},

            -- bgGradientColorsGroup
            { title = "Background Health Gradient Colors", preset = "form",
              fields = {
                { control = "note", wide = true,
                  text = "These colors are shared by the Raid/Party Frames "
                      .. "and the Unit Frames." },
                GradientColor("bgGradientHigh", "Full Health", "bgGradientHigh"),
                GradientColor("bgGradientMid",  "Half Health", "bgGradientMid"),
                GradientColor("bgGradientLow",  "Low Health",  "bgGradientLow"),
                ResetButton(function()
                    local cp = GetColorsP()
                    if cp then
                        cp.bgGradientHigh = nil
                        cp.bgGradientMid  = nil
                        cp.bgGradientLow  = nil
                    end
                end, RefreshHealthGradientColors, nil),
            }},
        },
    }
end
