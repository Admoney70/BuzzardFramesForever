-- ============================================================
-- BuzzardFramesOptions: Pages_UnitFramesGeneral.lua
-- The Unit Frames SECTION ROOT and its Global subtabs, in BuzzardPanel.
--
-- The panel equivalent of two things in BuzzardFrames:
--
--   * the root of `ptfArgs` in UnitFrames/Options_oUF_Other.lua
--     (BF:BuildPTFOptionsTable) -- the ptfEnabled master switch and the
--     six "Hide Blizzard Frames" toggles. That page replaces the
--     placeholder note on the `unitFrames` route.
--   * `globalOpts` (UnitFrames/Options_oUF_Player_Target.lua, the
--     `globalTab` entry of ptfArgs) -- eleven pages under
--     `unitFrames/globalTab`, drawn as a strip by the `tabs` navigator
--     that node declares.
--
-- Storage: BF.ufDB.profile.* -- the Unit Frames module's OWN AceDB
-- namespace (SavedVariable BuzzardFramesUnitFramesDB), declared in
-- UnitFrames/Defaults_UnitFrames.lua. It is NOT the raid/party section
-- profile system: there is no GetSectionProfile, no per-Layout toggle
-- and no flat here, which is why these pages carry no scope strip --
-- the Ace source has none either.
--
-- Nearly every field BINDS into ROOT below, which is `ufDB.profile`
-- wearing the shape the library wants: a plain table, with the Ace
-- getters' own nil-fallbacks and their `~= false` / `== true` readings
-- reproduced per key, and colors converted between the stored
-- { r=, g=, b=, a= } tables and the panel color control's
-- { r, g, b, a } arrays. Binding is what makes right-click Undo and
-- Reset work on all two hundred-odd fields without one of them
-- declaring anything; `defaults` is BuzzardFrames' own
-- BF.unitFrameDefaults.profile, in the same shape.
--
-- THE ptfEnabled GATE. In the Ace panel `syncPTFTabs()` NILS every
-- sub-tab out of the args table while ptfEnabled is off, and globalOpts
-- carries `hidden = not ptfEnabled` on top of that. A BuzzardPanel route
-- cannot hide -- only groups and fields can -- so the gate lands one
-- level down: every card on every Unit Frames page declares
-- `hidden = BuzzardFramesOptions.UnitFramesOff`, and a note appears in
-- their place saying why the page is empty. Both halves are PUBLISHED
-- (UnitFramesOff / UnitFramesDisabledNote) so the pages this file does
-- not own -- Player, Target and Unit Frame Layouts -- gate themselves
-- the same way rather than inventing a second answer.
--
-- Ace args keys with no field of their own here, for the audit:
--   hideBlizzardGroup     -> the "Hide Blizzard Frames" card's title
--   globalTab             -> the eleven routes under unitFrames/globalTab
--   classIconTab colorsTab bordersTab aurasTab fontsTab texturesTab
--   indicatorsTab tooltipsTab healthBarsSubTab backgroundSubTab
--   namesSubTab powerBarsSubTab
--                         -> those same eleven routes
--   showClassIcon         -> the "Show Class Icon" switch, whose storage
--                            key has always been playerShowClassIcon
--                            (and which writes targetShowClassIcon too)
--   oufBuffBorderStyle oufDebuffBorderStyle oufBuffUseBlizzardBorders
--   oufDebuffUseBlizzardBorders oufBuffBorderColor oufDebuffBorderColor
--   oufBuffBorderThickness oufDebuffBorderThickness
--                         -> the two aura border cards, which are BUILT
--                            from the kind's prefix (AuraBorderCard) and
--                            so name no key literally
--   oufRingColor          -> the rounded-mode "Border Color" picker,
--                            which has always WRITTEN frameBorderColor
--   hostileColor neutralColor friendlyColor
--                         -> the Hostility Colors cards, whose three
--                            pickers write globalNpcRegularColor /
--                            NeutralColor / FriendlyColor
--   colorsNote openColorsBtn gradientNote pingNote stackDesc
--   clickBindingsDesc     -> notes and buttons, kept as notes and buttons
--   every hdr* header      -> card boundaries
--   *Group wrappers (raidTargetGroup, pingGroup, buffBordersGroup,
--   debuffBordersGroup, cooldownSwipeGroup, stackFontGroup,
--   playerFrameColorsGroup, playerColorsGroup, npcColorsGroup,
--   classificationColorsGroup, hostilityColorsGroup,
--   npcHealthColorGroup, petHealthColorsGroup, healthColorGroup,
--   nameColorGroup, playerFrameNameColorsGroup, playerNameColorsGroup,
--   npcNameColorsGroup, npcNameColorGroup, petNameColorsGroup,
--   powerBarBackgroundGroup, healthBarTextureGroup, powerBarTextureGroup)
--                         -> cards, one per group, titles kept
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The Unit Frames profile. Every read and write on these pages lands
-- here, exactly as the Ace get/set closures' `self.ufDB.profile` does.
local function P()
    local bf = BF()
    return bf and bf.ufDB and bf.ufDB.profile
end

-- ── The write-through root ─────────────────────────────────────
--
-- Three tables of per-key quirks, each copied from the Ace getter it
-- replaces. They are NOT a second copy of the shipped defaults: AceDB
-- merges BF.unitFrameDefaults into the profile, so every one of these
-- fallbacks is dead in a healthy profile and fires only for a key that
-- is genuinely absent -- which is the case the Ace getter was written
-- for. `defaults` below is where reset and undo get their values.

-- Keys the Ace getter read as `p[key] ~= false`: absent means ON.
local TRUE_IF_ABSENT = {
    oufAdjustFonts           = true,
    oufShowRaidTarget        = true,
    oufShowPingIndicator     = true,
    oufAuraShowStealable     = true,
    oufStackShow             = true,
    auraShowSwipe            = true,
    auraShowSpark            = true,
    classIconBorderEnabled   = true,
    showEliteDragonBorder    = true,
    showUnitTooltip          = true,
    showUnitTooltipInCombat  = true,
}

-- Keys the Ace getter read as `p[key] == true`: absent means OFF.
local FALSE_IF_ABSENT = {
    auraShowDuration     = true,
    auraReverseSwipe     = true,
    oufSeparateFonts     = true,
    oufStackAutoScale    = true,
    oufRoundedSeparators = true,
    nameBorderEnabled    = true,
    healthBorderEnabled  = true,
    powerBorderEnabled   = true,
}

-- Scalar fallbacks, `or <value>` in the Ace getters, kept to the digit.
local FALLBACK = {
    iconSize                 = 51,
    iconOpacity              = 1.0,
    iconOffsetX              = 0,
    iconOffsetY              = 0,
    classIconBorderThickness = 2,
    auraFontSize             = 9,
    oufStackScale            = 1.0,
    oufStackFontSize         = 9,
    oufStackFontBorder       = "OUTLINE",
    oufStackAnchor           = "BOTTOMRIGHT",
    oufStackX                = 4,
    oufStackY                = -3,
    oufBorderMode            = "square",
    oufSeparatorStyle        = "rings",
    nameBorderThickness      = 1,
    healthBorderThickness    = 1,
    powerBorderThickness     = 1,
    oufRaidTargetSize        = 20,
    oufRaidTargetOffsetX     = 0,
    oufRaidTargetOffsetY     = 0,
    oufRaidTargetLocation    = "center",
    oufHealthBarOpacity      = 1,
    playerFrameHealthBarOpacity = 1,
    oufBackgroundColorMode   = "static",
    oufBackgroundAlpha       = 0.6,
    oufBgClassDarken         = 0,
    oufPowerBarBgAlpha       = 0.6,
    oufHealthBarTexture      = "Blizzard Raid Bar",
    oufPowerBarTexture       = "Blizzard Raid Bar",
    globalPlayerHealthColorMode = "class",
    playerFrameHealthColorMode  = "class",
    globalNpcHealthColorMode    = "classification",
    globalPlayerNameColorMode   = "class",
    playerFrameNameColorMode    = "class",
    globalNpcNameColorMode      = "classification",
}

-- Color keys, with the Ace getters' own fallback tables. The value the
-- control sees is an ARRAY; the value stored stays a NAMED table.
local COLOR_FALLBACK = {
    classIconBorderColor  = { r = 0,    g = 0,    b = 0            },
    frameBorderColor      = { r = 0,    g = 0,    b = 0,   a = 1   },
    nameBorderColor       = { r = 0,    g = 0,    b = 0,   a = 1   },
    healthBorderColor     = { r = 0,    g = 0,    b = 0,   a = 1   },
    powerBorderColor      = { r = 0,    g = 0,    b = 0,   a = 1   },
    globalHealthColor       = { r = 0.24, g = 0.78,  b = 0.24  },
    playerFrameHealthColor  = { r = 0.24, g = 0.78,  b = 0.24  },
    globalNpcHealthColor    = { r = 0.24, g = 0.78,  b = 0.24  },
    globalNpcFriendlyColor  = { r = 0.00, g = 0.65,  b = 0.00  },
    globalNpcNeutralColor   = { r = 0.90, g = 0.70,  b = 0.00  },
    globalNpcRegularColor   = { r = 0.745, g = 0.188, b = 0.114 },
    globalNpcBossColor      = { r = 1.00, g = 0.00,  b = 1.00  },
    globalNpcLieutenantColor= { r = 0.576, g = 0.439, b = 0.859 },
    globalNpcCasterColor    = { r = 0.00, g = 0.820, b = 1.00  },
    globalNpcTrivialColor   = { r = 0.592, g = 0.612, b = 0.592 },
    globalNameColor         = { r = 1,    g = 1,     b = 1     },
    playerFrameNameColor    = { r = 1,    g = 1,     b = 1     },
    globalNpcNameColor      = { r = 1,    g = 1,     b = 1     },
    oufBackgroundColor      = { r = 0.08, g = 0.08,  b = 0.08  },
    oufPowerBarBgColor      = { r = 0.08, g = 0.08,  b = 0.08  },
}

-- The two per-kind aura border colors fall through the LEGACY shared
-- key before they reach a literal, which no flat table can express --
-- so they are read by hand, in the same order the Ace getter reads
-- them. The same is true of the two thicknesses.
local AURA_BORDER_COLOR_FALLBACK = { r = 0, g = 0, b = 0, a = 0.8 }

local function ColorArray(c)
    return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
end

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local p = P()
        if not p then return nil end
        local v = p[k]

        if k == "oufBuffBorderColor" or k == "oufDebuffBorderColor" then
            local c = v or p.oufAuraBorderColor or AURA_BORDER_COLOR_FALLBACK
            return ColorArray(c)
        end
        if k == "oufBuffBorderThickness" or k == "oufDebuffBorderThickness" then
            return v or p.oufAuraBorderThickness or 2
        end
        if COLOR_FALLBACK[k] then
            return ColorArray(v or COLOR_FALLBACK[k])
        end
        if TRUE_IF_ABSENT[k]  then return v ~= false end
        if FALSE_IF_ABSENT[k] then return v == true  end
        if v == nil then return FALLBACK[k] end
        return v
    end,

    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local p = P()
        if not p then return end
        local isColor = COLOR_FALLBACK[k]
            or k == "oufBuffBorderColor" or k == "oufDebuffBorderColor"
        if isColor and type(v) == "table" then
            -- From the control (or an undo) the value is an array; from a
            -- reset it is the defaults table's named copy. Either way a
            -- FRESH named table is stored, exactly as the Ace setters do.
            local a = v.a
            if a == nil then a = v[4] end
            p[k] = { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3], a = a }
        else
            p[k] = v
        end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. BuzzardFrames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library
-- resolves a bind path straight into it -- `pet.healthColor` included.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    return d and d.profile
end

-- ── Per-unit reads and writes ──────────────────────────────────
--
-- The Ace ufGet/ufSet, verbatim: a per-unit sub-table, created on
-- demand. Only the pet color controls on the Colors pages use these;
-- everything else on this file's pages is a flat profile key.
local function UfGet(unit, key)
    local p = P()
    local uf = (p and p[unit]) or {}
    return uf[key]
end

local function UfSet(unit, key, val)
    if InCombatLockdown() then return end
    local p = P()
    if not p then return end
    p[unit] = p[unit] or {}
    p[unit][key] = val
end

-- ── Side effects ───────────────────────────────────────────────
--
-- The Ace file's own helpers, name for name and debounce key for
-- debounce key, so both panels share one trailing timer while both
-- exist. The comments on why each is debounced are the Ace source's.

local function RelayoutPlayer()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutPlayer", function()
        if bf.oufPlayer then bf:ApplyOUFPlayerLayout() end
    end)
end

local function UpdatePlayer()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdatePlayer", function()
        if bf.oufPlayer then bf.oufPlayer:UpdateAllElements("Manual") end
        -- The detached power bar is no longer refreshed by
        -- Power.PostUpdate, so the options update path must reach it
        -- directly -- UpdateOUFPowerBar re-bakes text visibility and
        -- format from the profile.
        if bf.UpdateOUFPowerBar then bf:UpdateOUFPowerBar() end
    end)
end

local function RelayoutTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutTarget", function()
        if bf.oufTarget then bf:ApplyOUFTargetLayout() end
    end)
end

local function UpdateTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdateTarget", function()
        if bf.oufTarget then bf.oufTarget:UpdateAllElements("Manual") end
    end)
end

local function RelayoutFocus()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutFocus", function()
        if bf.oufFocus then bf:ApplyOUFFocusLayout() end
    end)
end

local function RelayoutPet()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutPet", function()
        if bf.oufPet then bf:ApplyOUFPetLayout() end
    end)
end

local function RelayoutTot()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutTot", function()
        if bf.oufTargetOfTarget then bf:ApplyOUFTargetOfTargetLayout() end
    end)
end

local function RelayoutFocusTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutFocusTarget", function()
        if bf.oufFocusTarget then bf:ApplyOUFFocusTargetLayout() end
    end)
end

local function RelayoutBoss()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufLayoutBoss", function()
        if bf.oufBoss then bf:ApplyOUFBossFrameLayout() end
    end)
end

-- Relayout and update every active unit frame -- what the Global tab's
-- settings use. relayoutAll debounces through its per-unit
-- constituents, so a drag on a Global slider still lands one relayout
-- per frame type.
local function RelayoutAll()
    RelayoutPlayer()
    RelayoutTarget()
    RelayoutFocus()
    RelayoutPet()
    RelayoutTot()
    RelayoutFocusTarget()
    RelayoutBoss()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufFonts", function()
        if bf.RefreshOUFFonts then bf:RefreshOUFFonts() end
    end)
end

local function UpdateAll()
    UpdatePlayer()
    UpdateTarget()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("oufUpdateOthers", function()
        if bf.oufFocus          then bf.oufFocus:UpdateAllElements("Manual")          end
        if bf.oufPet            then bf.oufPet:UpdateAllElements("Manual")            end
        if bf.oufTargetOfTarget then bf.oufTargetOfTarget:UpdateAllElements("Manual") end
        if bf.oufFocusTarget    then bf.oufFocusTarget:UpdateAllElements("Manual")    end
        if bf.oufBoss then
            for i = 1, 5 do
                local f = bf.oufBoss[i]
                if f then f:UpdateAllElements("Manual") end
            end
        end
    end)
end

local function RelayoutAndUpdateAll()
    RelayoutAll()
    UpdateAll()
end

local function RestyleAuras()
    local bf = BF()
    if bf then bf:RestyleOUFAuraButtons() end
end

local function RefreshFonts()
    local bf = BF()
    if bf and bf.RefreshOUFFonts then bf:RefreshOUFFonts() end
end

local function ApplyPingIndicators()
    local bf = BF()
    if bf then bf:ApplyOUFPingIndicators() end
end

-- The stack-text restyle, with the Ace source's own retry rather than a
-- plain call: RestyleOUFAuraButtons bails while auras are engine-secret
-- (combat, and a window outside it), so a value written just before
-- that window would stay persisted but unapplied until some unrelated
-- aura edit triggered another walk. Backs off to 1s so a long combat is
-- not polled at the drag interval.
local _stackRestyleTimer
local function RestyleStackNow(delay)
    if _stackRestyleTimer then _stackRestyleTimer:Cancel() end
    _stackRestyleTimer = C_Timer.NewTimer(delay or 0.1, function()
        _stackRestyleTimer = nil
        local bf = BF()
        if not bf then return end
        if InCombatLockdown()
           or (bf.IsAuraCreationRestricted and bf:IsAuraCreationRestricted()) then
            RestyleStackNow(1.0)
            return
        end
        bf:RestyleOUFAuraButtons()
    end)
end

-- If the pet has "Match Player Color" on, push the current player health
-- color through to the pet bar immediately. Called whenever anything
-- that affects the player health color changes.
local function RefreshPetMatchColor()
    local bf = BF()
    local p  = P()
    if not (bf and p) then return end
    local petPf = p.pet or {}
    if petPf.petMatchPlayerColor == false then return end
    local f = bf.oufPet
    if f and f.Health and f.__unit then
        local r, g, b, isGradient, gradAlpha = bf:_GetOUFHealthColor(f.__unit, nil, "pet")
        local fillAlpha = bf:_GetOUFHealthBarFillAlpha("pet", isGradient, gradAlpha)
        f.Health:SetStatusBarColor(r, g, b, fillAlpha)
        f._bf_healthR, f._bf_healthG, f._bf_healthB = r, g, b
        f._bf_healthA = fillAlpha
        f._bf_healthGradient = isGradient
    end
end

-- Re-stamp the player frame's own health color, the chain the two
-- player-frame-override setters run before RefreshPetMatchColor.
local function RestampPlayerHealthColor()
    local bf = BF()
    if not bf then return end
    local f = bf.oufPlayer
    if f and f.Health and f.__unit then
        local r, g, b, isGradient, gradAlpha = bf:_GetOUFHealthColor(f.__unit, nil, "player")
        local fillAlpha = bf:_GetOUFHealthBarFillAlpha("player", isGradient, gradAlpha)
        f.Health:SetStatusBarColor(r, g, b, fillAlpha)
        f._bf_healthR, f._bf_healthG, f._bf_healthB = r, g, b
        f._bf_healthA = fillAlpha
        f._bf_healthGradient = isGradient
    end
end

local function RebuildGradients()
    local bf = BF()
    if bf and bf.RebuildHealthGradientCurves then bf:RebuildHealthGradientCurves() end
end

-- Does anything on the Health Bars page currently read from the global
-- Colors section? Only class mode and gradient mode do -- static, and
-- the NPC-only classification/hostility modes, take their colors from
-- the pickers on this page, so the "customize them in Colors" pointer
-- is hidden then rather than sending the reader somewhere that cannot
-- affect what they are looking at.
local function UsesGlobalColorsSection()
    local p = P()
    if not p then return true end
    local function reads(mode) return mode == "class" or mode == "gradient" end
    if p.separatePlayerFrameColor and reads(p.playerFrameHealthColorMode or "class") then
        return true
    end
    if reads(p.globalPlayerHealthColorMode or "class") then return true end
    -- NPCs have no class, so only their gradient mode qualifies.
    if (p.globalNpcHealthColorMode or "classification") == "gradient" then return true end
    return false
end

-- Push the power bar background color to every unit frame without a
-- relayout. The regions are created once per frame, so coloring them
-- here survives later layout passes.
local function RefreshPowerBarBg()
    local bf = BF()
    if not bf then return end
    local function apply(f)
        if f then bf:_ApplyOUFPowerBgColor(f) end
    end
    apply(bf.oufPlayer)
    apply(bf.oufTarget)
    apply(bf.oufFocus)
    apply(bf.oufPet)
    apply(bf.oufTargetOfTarget)
    apply(bf.oufFocusTarget)
    if bf.oufBoss then
        for i = 1, 5 do apply(bf.oufBoss[i]) end
    end
    -- Detached player power bar: lives on UIParent with its own bg
    -- texture, so it is not reached by the frame walk above.
    local pb = bf.oufDetachedPowerBar
    if pb and pb._bg then
        pb._bg:SetColorTexture(bf:_GetOUFPowerBgColor())
    end
end

-- The power bar OPACITY walk: SetAlpha on every Power StatusBar and its
-- border box, plus the standalone detached bar and its border.
local function ApplyPowerBarOpacity(v)
    local bf = BF()
    if not bf then return end
    local function apply(f)
        if not f then return end
        if f.Power then f.Power:SetAlpha(v) end
        local fb = f._frameBorder
        if fb and fb.power then fb.power:SetAlpha(v) end
    end
    apply(bf.oufPlayer)
    apply(bf.oufTarget)
    apply(bf.oufFocus)
    apply(bf.oufPet)
    apply(bf.oufTargetOfTarget)
    apply(bf.oufFocusTarget)
    if bf.oufBoss then
        for i = 1, 5 do apply(bf.oufBoss[i]) end
    end
    local pb = bf.oufDetachedPowerBar
    if pb then
        pb:SetAlpha(v)
        if pb._border then pb._border:SetAlpha(v) end
    end
end

-- The standalone-bar re-stamp that follows a border change: the resource
-- bar can exist without the player frame (ClassPower host path), and the
-- castbar and detached-bar borders must re-stamp even if a layout path
-- above early-outed.
local function RestampStandaloneBorders()
    local bf = BF()
    if not bf then return end
    if bf.ApplyOUFResourceBarLayout then bf:ApplyOUFResourceBarLayout() end
    if bf.ApplyOUFPowerBarLayout    then bf:ApplyOUFPowerBarLayout()    end
    if bf.ApplyOUFAltPowerBarLayout then bf:ApplyOUFAltPowerBarLayout() end
    if bf.oufTarget then bf:_ApplyOUFCastbarBorder(bf.oufTarget) end
    if bf.oufFocus  then bf:_ApplyOUFCastbarBorder(bf.oufFocus)  end
    if bf.oufBoss then
        for i = 1, 5 do
            if bf.oufBoss[i] then bf:_ApplyOUFCastbarBorder(bf.oufBoss[i]) end
        end
    end
end

local function BorderModeEffect()
    RelayoutAll()
    RestampStandaloneBorders()
end

-- The resource bar's pips share the power bar texture, so the texture
-- fields reach it directly: relayoutAll only gets there through
-- ApplyOUFPlayerLayout, and there may be no player frame.
local function PowerTextureEffect()
    RelayoutAll()
    local bf = BF()
    if bf and bf.ApplyOUFResourceBarLayout then bf:ApplyOUFResourceBarLayout() end
end

local function IsRounded()
    local bf = BF()
    return bf and bf.IsOUFRounded and bf:IsOUFRounded()
end

-- ── The ptfEnabled gate ────────────────────────────────────────
--
-- Published, because it gates pages in three files. See the header.
function BuzzardFramesOptions.UnitFramesOff()
    local p = P()
    return not (p and p.ptfEnabled)
end

local UFOff = BuzzardFramesOptions.UnitFramesOff

-- The card that stands in for everything the gate hid. It is a widget
-- the Ace panel does not have: there, the tabs themselves vanish, and a
-- panel route cannot. Without it a gated page is a blank body with no
-- explanation of what to do about it.
function BuzzardFramesOptions:UnitFramesDisabledNote()
    return { preset = "bare",
             hidden = function() return not UFOff() end,
             fields = {
        { control = "note", wide = true,
          text = "Unit Frames are turned off. Switch on |cffffff00Enable Unit "
              .. "Frames|r on the Unit Frames page to configure them." },
    }}
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every ordinary field on these pages binds into ROOT and names its
-- effect. These say that once each rather than two hundred times. Each
-- takes an `opts` table merged over the result, for the desc, the
-- hidden predicate and anything else that field alone carries.
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

-- A stepper, not a slider: a handful of whole numbers, where the reader
-- wants "one more" rather than a position on a track, and the number can be
-- typed directly. Same arguments as Sl, so a field converts by its name.
local function St(bind, label, lo, hi, step, effect, opts)
    return Merge({ control = "stepper", label = label, bind = bind,
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

-- A 0-1 fraction shown on the 0-100 scale the Ace dialog showed
-- (isPercent = true). The library's slider value box prints whole
-- numbers, so a 0-1 slider would read 0 or 1 for every value. The
-- STORED value is unchanged; only the presentation is scaled, and the
-- declared default is scaled with it so reset and undo work in the
-- units the reader sees.
local function Pct(key, label, hi, step, effect, opts)
    local d = Defaults()
    local dv = d and d[key]
    return Merge({
        control = "slider", label = label,
        id = key, default = dv and math.floor(dv * 100 + 0.5) or nil,
        min = 0, max = hi, step = step,
        onChange = effect, disabled = "combat",
        get = function() return math.floor((ROOT[key] or 0) * 100 + 0.5) end,
        set = function(_, _, v) ROOT[key] = math.floor(v + 0.5) / 100 end,
    }, opts)
end

-- ── Shared option lists ────────────────────────────────────────

-- LSM lists, resolved every time the menu opens, so media registered
-- after the panel is built still appears. LSM:List returns the names
-- already sorted -- the order the Ace dialog showed.
local function FontOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            -- `font` is the preview: the dropdown draws the row -- and the
            -- control, once picked -- in the face it names, which is what
            -- the Ace font picker did and the whole point of choosing one
            -- by eye rather than by name.
            out[#out + 1] = { value = name, text = name,
                              font = LSM:Fetch("font", name) }
        end
    end
    return out
end

local function StatusbarOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            -- `texture` is the preview: the row draws the bar behind its
            -- name, as the Ace statusbar picker did.
            out[#out + 1] = { value = name, text = name,
                              texture = LSM:Fetch("statusbar", name) }
        end
    end
    return out
end

local HEALTH_MODE_OPTIONS = {
    { value = "class",    text = "Use Class Colors" },
    { value = "gradient", text = "Use Color Gradient (Health Percent)" },
    { value = "static",   text = "Use Static Color" },
}

local NPC_HEALTH_MODE_OPTIONS = {
    { value = "classification", text = "Color by Classification" },
    { value = "hostility",      text = "Color by Hostility" },
    { value = "gradient",       text = "Use Color Gradient (Health Percent)" },
    { value = "static",         text = "Use Static Color" },
}

local NAME_MODE_OPTIONS = {
    { value = "class",  text = "Use Class Colors" },
    { value = "static", text = "Use Static Color" },
}

local NPC_NAME_MODE_OPTIONS = {
    { value = "classification", text = "Color by Classification" },
    { value = "hostility",      text = "Color by Hostility" },
    { value = "static",         text = "Use Static Color" },
}

-- Background lists the DEFAULT (static) first, unlike the health fill
-- dropdowns which default to class. Sorted differently on purpose --
-- the Ace `sorting` table, kept.
local BACKGROUND_MODE_OPTIONS = {
    { value = "static",   text = "Use Static Color" },
    { value = "gradient", text = "Use Color Gradient (Health Percent)" },
    { value = "class",    text = "Use Class Colors" },
}

local STACK_FONT_BORDER_OPTIONS = {
    { value = "",                         text = "None" },
    { value = "OUTLINE",                  text = "Outline" },
    { value = "THICKOUTLINE",             text = "Thick Outline" },
    { value = "MONOCHROME",               text = "Monochrome" },
    { value = "OUTLINE, MONOCHROME",      text = "Outline + Monochrome" },
    { value = "THICKOUTLINE, MONOCHROME", text = "Thick Outline + Monochrome" },
}

local STACK_ANCHOR_OPTIONS = {
    { value = "TOPLEFT",     text = "Top Left"     },
    { value = "TOP",         text = "Top"          },
    { value = "TOPRIGHT",    text = "Top Right"    },
    { value = "LEFT",        text = "Left"         },
    { value = "CENTER",      text = "Center"       },
    { value = "RIGHT",       text = "Right"        },
    { value = "BOTTOMLEFT",  text = "Bottom Left"  },
    { value = "BOTTOM",      text = "Bottom"       },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

-- The shared classification descriptions, used by both the Health Bars
-- and the Names pages.
local DESC_FRIENDLY   = "NPCs with a friendly reaction."
local DESC_NEUTRAL    = "NPCs with a neutral (yellow) reaction. In combat, they get classified as an enemy type instead."
local DESC_REGULAR    = "All other hostile NPCs that don't match a more specific classification."
local DESC_BOSS       = "World bosses, level ?? enemies, and enemies 2+ levels above you."
local DESC_LIEUTENANT = "Enemies 1 level above you, or flagged as lieutenants."
local DESC_CASTER     = "Enemies with mana, plus Paladin and Mage class NPCs."
local DESC_TRIVIAL    = "Trivial and minus (gray) enemies."

-- The seven classification pickers, which differ by nothing but their
-- key, their label and their description -- so they are declared as
-- data and built. The Ace order is the order below.
local CLASSIFICATION_COLORS = {
    { key = "globalNpcFriendlyColor",   label = "Friendly",   desc = DESC_FRIENDLY   },
    { key = "globalNpcNeutralColor",    label = "Neutral",    desc = DESC_NEUTRAL    },
    { key = "globalNpcRegularColor",    label = "Regular",    desc = DESC_REGULAR    },
    { key = "globalNpcBossColor",       label = "Boss",       desc = DESC_BOSS       },
    { key = "globalNpcLieutenantColor", label = "Lieutenant", desc = DESC_LIEUTENANT },
    { key = "globalNpcCasterColor",     label = "Caster",     desc = DESC_CASTER     },
    { key = "globalNpcTrivialColor",    label = "Trivial",    desc = DESC_TRIVIAL    },
}

-- The three hostility pickers write the SAME three keys the
-- classification ones do -- Hostile is globalNpcRegularColor. Two
-- fields over one bind would collide in the library's widget index, so
-- the hostility trio uses get/set with an id of its own, and the
-- classification trio keeps the bind (and with it the right-click Undo
-- and Reset for the value they share).
local HOSTILITY_COLORS = {
    { key = "globalNpcRegularColor",  id = "npcHostileColor",  label = "Hostile"  },
    { key = "globalNpcNeutralColor",  id = "npcNeutralColor",  label = "Neutral"  },
    { key = "globalNpcFriendlyColor", id = "npcFriendlyColor", label = "Friendly" },
}

local function ClassificationFields(effect)
    local out = {}
    for i, e in ipairs(CLASSIFICATION_COLORS) do
        out[i] = Col(e.key, e.label, false, effect, { desc = e.desc })
    end
    return out
end

local function HostilityFields(what, effect)
    local out = {}
    for i, e in ipairs(HOSTILITY_COLORS) do
        local d = Defaults()
        out[i] = {
            control = "color", label = e.label,
            id = e.id, default = d and d[e.key],
            desc = ("%s color for %s NPCs."):format(what, e.label:lower()),
            disabled = "combat", onChange = effect,
            get = function() return ROOT[e.key] end,
            set = function(_, _, v) ROOT[e.key] = v end,
        }
    end
    return out
end

-- The "these are customized in the global Colors section" pointer, and
-- the button that goes there. The Ace execute deferred its SelectGroup
-- a frame to dodge an AceConfigDialog error; the panel's Navigate has
-- no such constraint, so the button navigates directly.
local function ColorsLinkFields(text, when)
    return {
        { control = "note", wide = true, text = text, hidden = when },
        { control = "button", text = "Colors", hidden = when,
          onClick = function(_, ctx) ctx.app:Navigate("globalStyles", "colors") end },
    }
end

-- ── The eleven Global pages ────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages.
--
-- The Ace `globalTab` had EIGHT subtabs, one of which -- colorsTab --
-- declared `childGroups = "tab"` of its own and carried four more. A
-- BuzzardPanel node that declares a contextual navigator cannot have
-- another one under it (MountContextual anchors both strips at the same
-- place, and smoke_pages.lua refuses the shape outright), so the four
-- Colors sub-subtabs are FLATTENED into the same strip, named for where
-- they came from. That is the one structural change on this file's
-- pages, and it is forced.
-- The Global strip, in the Ace `order` values' own sequence: Class Icon 1,
-- Colors 1.5, Borders 2, Auras 3, Fonts 3.5, Textures 5, Icons/Indicators
-- 8.5, Tooltips 9.
--
-- Colors is a BRANCH, exactly as `colorsTab` is in the Ace source: it
-- declared `childGroups = "tab"` and carried four sub-tabs of its own, so
-- the dialog drew an outer row of tabs and an inner row beneath it.
--
-- The first migration pass spliced those four into this strip as
-- "Colors - Health Bars", "Colors - Background" and so on, because the
-- library mounted every contextual navigator at one anchor and a nested
-- strip drew on top of its parent. That is fixed -- ns.chrome.CtxNavTopFor
-- gives each strip its own row and the band is their sum -- so the shape
-- here is the Ace one again, and the eleven-wide strip is gone.
BuzzardFramesOptions.UNITFRAMES_GLOBAL_SUBTABS = {
    { id = "classIcon",  title = "Class Icon" },
    { id = "colors",     title = "Colors", children = {
        { id = "colorsHealthBars", title = "Health Bars" },
        { id = "colorsBackground", title = "Background"  },
        { id = "colorsNames",      title = "Names"       },
        { id = "colorsPowerBars",  title = "Power Bars"  },
    }},
    { id = "borders",    title = "Borders" },
    { id = "auras",      title = "Auras" },
    { id = "fonts",      title = "Fonts" },
    { id = "textures",   title = "Textures" },
    { id = "indicators", title = "Icons/Indicators" },
    { id = "tooltips",   title = "Tooltips" },
}

local PAGES = {}

-- ── Class Icon ─────────────────────────────────────────────────

local function NoClassIcon()
    local p = P()
    return not (p and p.playerShowClassIcon)
end

function PAGES.classIcon()
    local d = Defaults()
    return {
        { title = "Class Icon", preset = "form", fields = {
            -- Two keys, one switch: the Ace setter writes the target
            -- frame's flag alongside the player's, so the icon slot is
            -- shown or hidden on every frame at once.
            { control = "switch", label = "Show Class Icon",
              id = "playerShowClassIcon", default = d and d.playerShowClassIcon,
              desc = "Show the class icon slot on all unit frames.",
              disabled = "combat",
              get = function() return ROOT.playerShowClassIcon end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local p = P()
                  if not p then return end
                  p.playerShowClassIcon = val
                  p.targetShowClassIcon = val
                  RelayoutAndUpdateAll()
              end },
            Dd("iconStyle", "Icon Style", {
                { value = "classicon", text = "Class Icon" },
                { value = "portrait",  text = "Portrait"   },
                { value = "model",     text = "Model"      },
              }, RelayoutAndUpdateAll,
              { desc = "Class Icon: shows the class icon for players, portrait "
                    .. "for NPCs.\nPortrait: always shows the unit portrait.",
                hidden = NoClassIcon }),
            Dd("iconShape", "Icon Shape", {
                { value = "circular", text = "Circular" },
                { value = "square",   text = "Square"   },
              }, RelayoutAndUpdateAll,
              { hidden = function()
                    local p = P()
                    return NoClassIcon() or (p and p.iconStyle) == "model"
                end }),
            Sl("iconSize", "Icon Size", 20, 80, 1, RelayoutAndUpdateAll,
               { hidden = NoClassIcon }),
            Pct("iconOpacity", "Icon Opacity", 100, 1, RelayoutAndUpdateAll,
                { hidden = NoClassIcon }),
        }},

        { title = "Icon Position", preset = "form", hidden = NoClassIcon, fields = {
            Sl("iconOffsetX", "X Offset", -30, 30, 1, RelayoutAll,
               { desc = "Moves all icons horizontally.", hidden = NoClassIcon }),
            Sl("iconOffsetY", "Y Offset", -30, 30, 1, RelayoutAll,
               { desc = "Moves all icons vertically by the same amount.",
                 hidden = NoClassIcon }),
            Dd("iconLocation", "Location", {
                { value = "outer",  text = "Outer"  },
                { value = "center", text = "Center" },
                { value = "inner",  text = "Inner"  },
              }, RelayoutAll,
              { desc = "Where the icon sits relative to the bar frame edge.\n"
                    .. "Outer: fully outside the bars (default).\n"
                    .. "Center: icon center sits on the edge.\n"
                    .. "Inner: fully inside the bars.",
                hidden = NoClassIcon }),
        }},

        { title = "Icon Border", preset = "form", hidden = NoClassIcon, fields = {
            Sw("classIconBorderEnabled", "Enable Icon Border", RelayoutAndUpdateAll,
               { hidden = NoClassIcon }),
            St("classIconBorderThickness", "Border Thickness", 1, 10, 1,
               RelayoutAndUpdateAll,
               { hidden = function()
                     return NoClassIcon() or not ROOT.classIconBorderEnabled
                 end }),
            Sw("classIconBorderUseHealthColor", "Use Health Bar Colors",
               RelayoutAndUpdateAll,
               { desc = "Match the icon border color to the unit's health bar "
                     .. "color. Updates automatically when the target changes.",
                 hidden = function()
                     return NoClassIcon() or not ROOT.classIconBorderEnabled
                 end }),
            Col("classIconBorderColor", "Border Color", false, RelayoutAll,
                { hidden = function()
                      local p = P()
                      return NoClassIcon() or not ROOT.classIconBorderEnabled
                          or (p and p.classIconBorderUseHealthColor) and true or false
                  end }),
        }},

        { title = "Elite Dragon Border", preset = "form",
          hidden = function()
              local p = P()
              return NoClassIcon()
                  or ((p and p.iconStyle) or "classicon") == "model"
                  or ((p and p.iconShape) or "circular") ~= "circular"
          end,
          fields = {
            Sw("showEliteDragonBorder", "Show Elite Dragon Border",
               RelayoutAndUpdateAll,
               { desc = "Display the gold or silver dragon border around the "
                     .. "portrait icon for elite, rare-elite, and worldboss "
                     .. "enemies.",
                 hidden = function()
                     local p = P()
                     return NoClassIcon()
                         or ((p and p.iconStyle) or "classicon") == "model"
                         or ((p and p.iconShape) or "circular") ~= "circular"
                 end }),
        }},

        { title = "Click Bindings", preset = "form", hidden = NoClassIcon, fields = {
            -- The Ace description named a third-party click-casting addon
            -- by name. House rule: no other addon is named here, so it
            -- says what it does instead.
            { control = "note", wide = true, hidden = NoClassIcon,
              text = "Use the toggle below to disable custom left- and "
                  .. "right-click bindings on the Unit Frame Icons (the rest "
                  .. "of the Unit Frame will still respect the custom "
                  .. "bindings).\n\nThis feature can be useful if you rebind "
                  .. "mouse buttons to spells, but still want easy access to "
                  .. "target units and open the unit menu without needing a "
                  .. "modifier key.\n\n*Only works with a third-party "
                  .. "click-casting addon, not Blizzard click-casting." },
            Sw("iconIgnoreClickBinds",
               "Icon ignores custom left- and right-click binds", RelayoutAll,
               { wide = true, hidden = NoClassIcon,
                 desc = "When enabled, left-clicking the icon will always "
                     .. "target the unit and right-clicking will always open "
                     .. "the unit menu, ignoring any custom click-cast "
                     .. "bindings." }),
        }},
    }
end

-- ── Colors: Health Bars ────────────────────────────────────────

local function NoSeparatePlayerHealth()
    local p = P()
    return not (p and p.separatePlayerFrameColor)
end

function PAGES.colorsHealthBars()
    local d = Defaults()
    local noColorsLink = function() return not UsesGlobalColorsSection() end
    return {
        { preset = "bare", fields = {
            { control = "switch", label = "Separate Configuration for Player Frame",
              labelSide = "after", wide = true,
              id = "separatePlayerFrameColor",
              default = d and d.separatePlayerFrameColor,
              desc = "When enabled, the player frame uses its own color mode "
                  .. "instead of the Player Health Bar Colors setting.",
              get = function() return ROOT.separatePlayerFrameColor end,
              set = function(_, _, v)
                  ROOT.separatePlayerFrameColor = v
                  RebuildGradients()
                  UpdateAll()
              end },
        }},

        { title = "Player Frame Health Bar Color", preset = "form",
          hidden = NoSeparatePlayerHealth, fields = {
            Dd("playerFrameHealthColorMode", "Color Mode", HEALTH_MODE_OPTIONS,
               nil, {
                 hidden = NoSeparatePlayerHealth,
                 -- The Ace setter had NO combat guard on this one; the
                 -- widget was not combat-disabled either. Kept as found.
                 disabled = false,
                 set = function(_, _, v)
                     ROOT.playerFrameHealthColorMode = v
                     RebuildGradients()
                     RestampPlayerHealthColor()
                     RefreshPetMatchColor()
                 end }),
            Col("playerFrameHealthColor", "Health Color", false, nil, {
                desc = "Static health bar color for the player frame.",
                hidden = function()
                    return NoSeparatePlayerHealth()
                        or (ROOT.playerFrameHealthColorMode or "class") ~= "static"
                end,
                set = function(_, _, v)
                    ROOT.playerFrameHealthColor = v
                    RestampPlayerHealthColor()
                    RefreshPetMatchColor()
                end }),
            Pct("playerFrameHealthBarOpacity", "Player Health Bar Opacity",
                100, 5, RelayoutAndUpdateAll, {
                desc = "Opacity of the player frame's health bar fill. Only "
                    .. "applies when this color mode is class or static; "
                    .. "gradient mode uses the alpha channel of the gradient "
                    .. "color stops in the Colors section.",
                hidden = function()
                    return NoSeparatePlayerHealth()
                        or (ROOT.playerFrameHealthColorMode or "class") == "gradient"
                end }),
        }},

        { title = "Player Health Bar Colors", preset = "form", fields = {
            Dd("globalPlayerHealthColorMode", "Color Mode", HEALTH_MODE_OPTIONS,
               nil, { disabled = false, set = function(_, _, v)
                   ROOT.globalPlayerHealthColorMode = v
                   RebuildGradients()
                   UpdateAll()
               end }),
            Col("globalHealthColor", "Health Color", false, UpdateAll, {
                desc = "Static health bar color for player targets.",
                hidden = function()
                    return (ROOT.globalPlayerHealthColorMode or "class") ~= "static"
                end }),
        }},

        { title = "NPC Health Bar Colors", preset = "form", fields = {
            Dd("globalNpcHealthColorMode", "Color Mode", NPC_HEALTH_MODE_OPTIONS,
               nil, { disabled = false, set = function(_, _, v)
                   ROOT.globalNpcHealthColorMode = v
                   RebuildGradients()
                   UpdateAll()
               end }),
        }},

        -- The Ace inline groups inside npcColorsGroup, as cards of their
        -- own: a card cannot nest in this library, and three mutually
        -- exclusive sets of pickers read better as three cards that come
        -- and go than as one card that changes shape.
        { title = "Classification Colors", preset = "form",
          hidden = function()
              return (ROOT.globalNpcHealthColorMode or "classification") ~= "classification"
          end,
          fields = ClassificationFields(UpdateAll) },

        { title = "Hostility Colors", preset = "form",
          hidden = function()
              return (ROOT.globalNpcHealthColorMode or "classification") ~= "hostility"
          end,
          fields = HostilityFields("Health bar", UpdateAll) },

        { title = "Health Color", preset = "form",
          hidden = function()
              return (ROOT.globalNpcHealthColorMode or "classification") ~= "static"
          end,
          fields = {
            Col("globalNpcHealthColor", "NPC Health Color", false, UpdateAll,
                { desc = "Static health bar color for all NPCs." }),
        }},

        { title = "Pet Frame Health Bar Color", preset = "form",
          hidden = function()
              local p = P()
              return not (p and p.showPetFrame)
          end,
          fields = {
            { control = "switch", label = "Match Player Color", wide = true,
              labelSide = "after",
              id = "petMatchPlayerColor",
              default = d and d.pet and d.pet.petMatchPlayerColor,
              desc = "Use the same health bar color as the player frame.",
              disabled = "combat",
              get = function() return UfGet("pet", "petMatchPlayerColor") ~= false end,
              set = function(_, _, v)
                  UfSet("pet", "petMatchPlayerColor", v)
                  RelayoutAndUpdateAll()
              end },
            { control = "color", label = "Health Bar Color",
              id = "petHealthColor",
              default = d and d.pet and d.pet.healthColor,
              desc = "Custom health bar color for the pet frame.",
              disabled = "combat",
              hidden = function()
                  return UfGet("pet", "petMatchPlayerColor") ~= false
              end,
              get = function()
                  local c = UfGet("pet", "healthColor") or { r = 0.24, g = 0.78, b = 0.24 }
                  return ColorArray(c)
              end,
              set = function(_, _, v)
                  UfSet("pet", "healthColor",
                        { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3] })
                  RelayoutAndUpdateAll()
              end },
        }},

        { preset = "bare", fields = {
            Pct("oufHealthBarOpacity", "Health Bar Opacity", 100, 5,
                RelayoutAndUpdateAll,
                { desc = "Opacity of the health bar fill." }),
        }},

        { preset = "bare", fields = ColorsLinkFields(
            "Class Colors and Health Gradient Colors can be customized in the "
            .. "global Colors section:", noColorsLink) },
    }
end

-- ── Colors: Background ─────────────────────────────────────────

local function NoCustomBackground()
    local p = P()
    return not (p and p.oufUseCustomBackgroundColor)
end

function PAGES.colorsBackground()
    local d = Defaults()
    local notGradient = function()
        return NoCustomBackground()
            or (ROOT.oufBackgroundColorMode or "static") ~= "gradient"
    end
    return {
        { preset = "bare", fields = {
            { control = "switch", label = "Use Custom Background Color",
              labelSide = "after", wide = true,
              id = "oufUseCustomBackgroundColor",
              default = d and d.oufUseCustomBackgroundColor,
              desc = "Override the default dark health bar background.",
              get = function() return ROOT.oufUseCustomBackgroundColor end,
              set = function(_, _, v)
                  ROOT.oufUseCustomBackgroundColor = v
                  RebuildGradients()
                  RelayoutAndUpdateAll()
              end },
        }},

        { title = "Health Bar Background", preset = "form",
          hidden = NoCustomBackground, fields = {
            Dd("oufBackgroundColorMode", "Color Mode", BACKGROUND_MODE_OPTIONS,
               nil, { hidden = NoCustomBackground, disabled = false,
                      set = function(_, _, v)
                          ROOT.oufBackgroundColorMode = v
                          RebuildGradients()
                          RelayoutAndUpdateAll()
                      end }),
            -- The label and the tooltip are FUNCTIONS: in class mode this
            -- color is used for non-player units, which have no class
            -- color, and the Ace widget renamed itself to say so.
            Col("oufBackgroundColor", nil, false, RelayoutAndUpdateAll, {
                label = function()
                    if (ROOT.oufBackgroundColorMode or "static") == "class" then
                        return "NPC Background Color"
                    end
                    return "Background Color"
                end,
                desc = function()
                    if (ROOT.oufBackgroundColorMode or "static") == "class" then
                        return "Background color used for non-player (NPC) "
                            .. "units, which have no class color."
                    end
                    return "Static background color for health bars."
                end,
                hidden = function()
                    local mode = ROOT.oufBackgroundColorMode or "static"
                    return NoCustomBackground()
                        or (mode ~= "static" and mode ~= "class")
                end }),
            Pct("oufBackgroundAlpha", "Background Opacity", 100, 5,
                RelayoutAndUpdateAll, {
                desc = "Opacity of the health bar background.",
                -- In gradient mode the opacity comes from the per-stop
                -- alpha of the bg gradient pickers in the Colors section.
                hidden = function()
                    return NoCustomBackground()
                        or (ROOT.oufBackgroundColorMode or "static") == "gradient"
                end }),
            Pct("oufBgClassDarken", "Background Darkening", 80, 5,
                RelayoutAndUpdateAll, {
                desc = "Darkens the class-colored background of player units. "
                    .. "0% = full class color; higher values multiply the "
                    .. "color toward black for a dimmer backdrop behind the "
                    .. "fill. Does not affect non-player units.",
                hidden = function()
                    return NoCustomBackground()
                        or (ROOT.oufBackgroundColorMode or "static") ~= "class"
                end }),
        }},

        { preset = "bare", fields = ColorsLinkFields(
            "Background gradient colors can be customized in the global "
            .. "Colors section:", notGradient) },
    }
end

-- ── Colors: Names ──────────────────────────────────────────────

local function NoSeparatePlayerName()
    local p = P()
    return not (p and p.separatePlayerFrameNameColor)
end

function PAGES.colorsNames()
    local d = Defaults()
    return {
        { preset = "bare", fields = {
            { control = "switch", label = "Separate Configuration for Player Frame",
              labelSide = "after", wide = true,
              id = "separatePlayerFrameNameColor",
              default = d and d.separatePlayerFrameNameColor,
              desc = "When enabled, the player frame uses its own name color "
                  .. "mode instead of the Player Name Colors setting.",
              get = function() return ROOT.separatePlayerFrameNameColor end,
              set = function(_, _, v)
                  ROOT.separatePlayerFrameNameColor = v
                  RelayoutAndUpdateAll()
              end },
        }},

        { title = "Player Frame Name Color", preset = "form",
          hidden = NoSeparatePlayerName, fields = {
            Dd("playerFrameNameColorMode", "Color Mode", NAME_MODE_OPTIONS, nil, {
                hidden = NoSeparatePlayerName, disabled = false,
                set = function(_, _, v)
                    ROOT.playerFrameNameColorMode = v
                    -- The Ace setter only ran the refresh when a live
                    -- player frame existed; kept as found.
                    local bf = BF()
                    local f  = bf and bf.oufPlayer
                    if f and f.__unit then RelayoutAndUpdateAll() end
                end }),
            Col("playerFrameNameColor", "Name Color", false, RelayoutAndUpdateAll, {
                desc = "Static name text color for the player frame.",
                hidden = function()
                    return NoSeparatePlayerName()
                        or (ROOT.playerFrameNameColorMode or "class") ~= "static"
                end }),
        }},

        { title = "Player Name Colors", preset = "form", fields = {
            Dd("globalPlayerNameColorMode", "Color Mode", NAME_MODE_OPTIONS,
               RelayoutAndUpdateAll, { disabled = false }),
            Col("globalNameColor", "Name Color", false, RelayoutAndUpdateAll, {
                desc = "Static name text color for player targets.",
                hidden = function()
                    return (ROOT.globalPlayerNameColorMode or "class") ~= "static"
                end }),
        }},

        { title = "NPC Name Colors", preset = "form", fields = {
            Dd("globalNpcNameColorMode", "Color Mode", NPC_NAME_MODE_OPTIONS,
               RelayoutAndUpdateAll, { disabled = false }),
        }},

        { title = "Classification Colors", preset = "form",
          hidden = function()
              return (ROOT.globalNpcNameColorMode or "classification") ~= "classification"
          end,
          -- The SAME seven keys the Health Bars page's classification
          -- card writes: one color per classification, shared by the
          -- health bar and the name. The bind lives there (a bind is
          -- indexed once), so here they are get/set with their own ids.
          fields = (function()
              local out = {}
              for i, e in ipairs(CLASSIFICATION_COLORS) do
                  local dd = Defaults()
                  out[i] = {
                      control = "color", label = e.label,
                      id = e.key .. "_name", default = dd and dd[e.key],
                      desc = e.desc, disabled = "combat",
                      get = function() return ROOT[e.key] end,
                      set = function(_, _, v)
                          ROOT[e.key] = v
                          RelayoutAndUpdateAll()
                      end,
                  }
              end
              return out
          end)() },

        { title = "Hostility Colors", preset = "form",
          hidden = function()
              return (ROOT.globalNpcNameColorMode or "classification") ~= "hostility"
          end,
          fields = (function()
              local out = {}
              for i, e in ipairs(HOSTILITY_COLORS) do
                  local dd = Defaults()
                  out[i] = {
                      control = "color", label = e.label,
                      id = e.id .. "_name", default = dd and dd[e.key],
                      desc = ("Name color for %s NPCs."):format(e.label:lower()),
                      disabled = "combat",
                      get = function() return ROOT[e.key] end,
                      set = function(_, _, v)
                          ROOT[e.key] = v
                          RelayoutAndUpdateAll()
                      end,
                  }
              end
              return out
          end)() },

        { title = "Name Color", preset = "form",
          hidden = function()
              return (ROOT.globalNpcNameColorMode or "classification") ~= "static"
          end,
          fields = {
            Col("globalNpcNameColor", "NPC Name Color", false, RelayoutAndUpdateAll,
                { desc = "Static name text color for all NPCs." }),
        }},

        { title = "Pet Frame Name Color", preset = "form",
          hidden = function()
              local p = P()
              return not (p and p.showPetFrame)
          end,
          fields = {
            { control = "switch", label = "Match Player Color", wide = true,
              labelSide = "after",
              id = "petMatchPlayerNameColor",
              default = d and d.pet and d.pet.petMatchPlayerNameColor,
              desc = "Use the same name color as the player frame.",
              disabled = "combat",
              get = function() return UfGet("pet", "petMatchPlayerNameColor") ~= false end,
              set = function(_, _, v)
                  UfSet("pet", "petMatchPlayerNameColor", v)
                  RelayoutAndUpdateAll()
              end },
            { control = "color", label = "Name Color",
              id = "petNameColor",
              default = d and d.pet and d.pet.nameColor,
              desc = "Custom name text color for the pet frame.",
              disabled = "combat",
              hidden = function()
                  return UfGet("pet", "petMatchPlayerNameColor") ~= false
              end,
              get = function()
                  local c = UfGet("pet", "nameColor") or { r = 1, g = 1, b = 1 }
                  return ColorArray(c)
              end,
              set = function(_, _, v)
                  UfSet("pet", "nameColor",
                        { r = v.r or v[1], g = v.g or v[2], b = v.b or v[3] })
                  RelayoutAndUpdateAll()
              end },
        }},
    }
end

-- ── Colors: Power Bars ─────────────────────────────────────────

local function NoCustomPowerBg()
    local p = P()
    return not (p and p.oufUseCustomPowerBarBgColor)
end

function PAGES.colorsPowerBars()
    local d = Defaults()
    return {
        { preset = "bare", fields = {
            { control = "slider", label = "Power Bar Opacity",
              id = "oufPowerBarOpacity",
              default = (function()
                  local v = d and d.oufPowerBarOpacity
                  if v == nil then return 100 end
                  return math.floor(v * 100 + 0.5)
              end)(),
              min = 0, max = 100, step = 5, disabled = "combat",
              desc = "Opacity of the power bar (and its border) on all Unit "
                  .. "Frames (Player, Target, Focus, Pet, Target of Target, "
                  .. "Focus Target, Boss).",
              get = function()
                  local v = ROOT.oufPowerBarOpacity
                  if v == nil then v = 1 end
                  return math.floor(v * 100 + 0.5)
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local frac = math.floor(v + 0.5) / 100
                  ROOT.oufPowerBarOpacity = frac
                  ApplyPowerBarOpacity(frac)
              end },
        }},

        { title = "Power Bar Background", preset = "form", fields = {
            Sw("oufUseCustomPowerBarBgColor", "Use Custom Background Color",
               RefreshPowerBarBg,
               { wide = true,
                 desc = "Override the default dark power bar background." }),
            Col("oufPowerBarBgColor", "Background Color", false, RefreshPowerBarBg,
                { desc = "Color of the power bar background.",
                  hidden = NoCustomPowerBg }),
            Pct("oufPowerBarBgAlpha", "Background Opacity", 100, 5,
                RefreshPowerBarBg, {
                desc = "Opacity of the power bar background. The background "
                    .. "sits behind the whole bar including the fill, so it "
                    .. "shows through only where the fill is transparent -- "
                    .. "and the Power Bar Opacity slider above multiplies "
                    .. "with this value.",
                hidden = NoCustomPowerBg }),
        }},

        { preset = "bare", fields = ColorsLinkFields(
            "Power Colors can be customized in the global Colors section:") },
    }
end

-- ── Borders ────────────────────────────────────────────────────

function PAGES.borders()
    local d = Defaults()

    -- Border Mode is one value at three spellings: two shapes and, for
    -- the rounded one, two weights. BorderStyleFields (Pages_-
    -- BorderStyle.lua) is the shared control for exactly that, and it is
    -- what the six raid/party border pickers already use -- so the
    -- reader meets one control rather than a seventh list mixing a
    -- weight in with the shapes. STORAGE IS UNCHANGED: oufBorderMode
    -- still holds square, rounded or rounded_thick.
    local style, weight = BuzzardFramesOptions:BorderStyleFields({
        label   = "Border Mode",
        desc    = "Square draws flat per-bar borders at the chosen thickness. "
               .. "Rounded draws a single rounded frame around each unit frame "
               .. "with the bar content masked to the corner radius; Thick is "
               .. "the same frame slightly heavier. Rounded modes also round "
               .. "the castbars, detached bars, and the resource bar "
               .. "(including pips).",
        options = { { value = "square",  text = "Square"  },
                    { value = "rounded", text = "Rounded" } },
        thin    = "rounded",
        thick   = "rounded_thick",
        bind    = "oufBorderMode",
        default = d and d.oufBorderMode,
        onChange = BorderModeEffect,
        get     = function() return ROOT.oufBorderMode end,
        set     = function(_, _, v) ROOT.oufBorderMode = v end,
    })

    -- One card per bar: they differ by nothing but their three keys.
    local function BarCard(title, prefix)
        local enabled = prefix .. "BorderEnabled"
        return { title = title, preset = "form",
                 hidden = function() return IsRounded() end,
                 fields = {
            Sw(enabled, "Enable Border", RelayoutAll,
               { wide = true, hidden = function() return IsRounded() end }),
            Sl(prefix .. "BorderThickness", "Thickness", 1, 6, 1, RelayoutAll,
               { hidden = function() return IsRounded() or not ROOT[enabled] end }),
            Col(prefix .. "BorderColor", "Color", true, RelayoutAll,
                { hidden = function() return IsRounded() or not ROOT[enabled] end }),
        }}
    end

    return {
        { title = "Border Mode", preset = "form", fields = {
            style, weight,
            Sw("oufRoundedSeparators", "Bar Separators", RelayoutAll,
               { desc = "Give each bar (name, health, power) its own full "
                     .. "rounded border instead of one border around the "
                     .. "whole frame.",
                 hidden = function() return not IsRounded() end }),
            Dd("oufSeparatorStyle", "Bar Separator Style", {
                { value = "rings", text = "Full Borders (per bar)" },
                { value = "lines", text = "Divider Lines" },
              }, RelayoutAll,
              { desc = "Full Borders: every bar keeps its own rounded border, "
                    .. "with shared edges overlapped so the border between "
                    .. "bars is never double thickness. Divider Lines: one "
                    .. "rounded border around the whole frame plus straight "
                    .. "single-thickness lines between the bars.",
                hidden = function()
                    return not IsRounded() or not ROOT.oufRoundedSeparators
                end }),
            -- The ring is ONE border for the whole outline, so it reuses
            -- the single frameBorderColor (and its alpha) rather than the
            -- per-bar colors. Ace called this widget oufRingColor; the
            -- key it writes has always been frameBorderColor.
            Col("frameBorderColor", "Border Color", true, BorderModeEffect, {
                desc = "Color and opacity of the rounded border ring (shared "
                    .. "by every unit frame, castbar, detached bar, resource "
                    .. "bar, and pip).",
                hidden = function() return not IsRounded() end }),
        }},

        BarCard("Name Bar",   "name"),
        BarCard("Health Bar", "health"),
        BarCard("Power Bar",  "power"),
    }
end

-- ── Auras ──────────────────────────────────────────────────────

local function NoStackText()
    local p = P()
    return p and p.oufStackShow == false
end

-- The two aura-border cards differ by nothing but their kind, so they
-- are built. The style picker writes TWO keys (the per-kind style and
-- its Blizzard-borders flag), and the buff one writes the two legacy
-- SHARED keys as well -- exactly as the Ace setters do, debuffs
-- included in not doing so.
local function AuraBorderCard(title, kind, prefix, syncLegacy)
    local d = Defaults()
    local styleKey  = prefix .. "BorderStyle"
    local blizzKey  = prefix .. "UseBlizzardBorders"
    local function CurrentStyle()
        local bf = BF()
        return bf and bf:GetOUFAuraBorderStyle(kind)
    end
    local style, weight = BuzzardFramesOptions:BorderStyleFields({
        label   = "Border Style",
        desc    = "Blizzard-Style uses Blizzard's aura border art. Square "
               .. "draws the flat colored border. Rounded masks the icon to a "
               .. "rounded rectangle inside a colored frame (rounded cooldown "
               .. "swipe included); Thick is the same frame ~1px heavier.",
        options = { { value = "blizzard", text = "Blizzard-Style" },
                    { value = "flat",     text = "Square"         },
                    { value = "rounded",  text = "Rounded"        } },
        thin    = "rounded",
        thick   = "rounded_thick",
        id      = styleKey,
        default = d and d[styleKey],
        onChange = RestyleAuras,
        get = function() return CurrentStyle() end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            p[blizzKey] = (v == "blizzard")
            p[styleKey] = v
            if syncLegacy then
                -- Legacy shared key sync -- the Buff setter's own, and
                -- only the Buff setter's.
                p.oufAuraUseBlizzardBorders = (v == "blizzard")
                p.oufAuraBorderStyle = v
            end
        end,
    })
    return { title = title, preset = "form", fields = {
        style, weight,
        Col(prefix .. "BorderColor", "Border Color", true, RestyleAuras,
            { hidden = function() return CurrentStyle() == "blizzard" end }),
        Sl(prefix .. "BorderThickness", "Border Thickness", 0, 5, 1, RestyleAuras,
           { hidden = function() return CurrentStyle() ~= "flat" end }),
    }}
end

function PAGES.auras()
    local d = Defaults()
    -- Every stack widget shares one setter shape: write the key, then
    -- re-stamp live through the retrying aura restyle walk.
    local function StackSet(key)
        return function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = v
            RestyleStackNow()
        end
    end
    return {
        { title = "Duration Text", preset = "form", fields = {
            Sw("auraShowDuration", "Show Duration Text", RestyleAuras,
               { desc = "Show the countdown timer on aura icons on all unit "
                     .. "frames. Disabled by default." }),
            Sl("auraFontSize", "Font Size", 6, 20, 1, RestyleAuras, {
                desc = "Size of the duration text on aura icons on all unit "
                    .. "frames.",
                -- The Ace widget carried BOTH a disabled and a hidden
                -- predicate on the same condition. Kept.
                disabled = function()
                    local p = P()
                    return InCombatLockdown() or not (p and p.auraShowDuration)
                end,
                hidden = function()
                    local p = P()
                    return not (p and p.auraShowDuration)
                end }),
        }},

        { title = "Cooldown Swipe", preset = "form", fields = {
            Sw("auraShowSwipe", "Show Cooldown Swipe", RestyleAuras,
               { desc = "Show the cooldown swipe animation on aura icons on "
                     .. "all unit frames." }),
            Sw("auraReverseSwipe", "Reverse Cooldown Swipe", RestyleAuras, {
                desc = "Reverse the direction of the cooldown swipe on aura "
                    .. "icons on all unit frames.",
                hidden = function()
                    local p = P()
                    return p and p.auraShowSwipe == false
                end }),
            Sw("auraShowSpark", "Show Cooldown Spark", RestyleAuras,
               { desc = "Show the spark at the edge of the cooldown swipe on "
                     .. "aura icons on all unit frames." }),
        }},

        AuraBorderCard("Buff Borders",   "buffs",   "oufBuff",   true),
        AuraBorderCard("Debuff Borders", "debuffs", "oufDebuff", false),

        { title = "Stealable Buffs", preset = "form", fields = {
            Sw("oufAuraShowStealable", "Stealable Buff Border", RestyleAuras,
               { wide = true,
                 desc = "Show the sparkling stealable border on buffs you can "
                     .. "spellsteal or purge (target, focus, and boss frames). "
                     .. "Driven by the game engine, so it works in combat." }),
        }},

        { title = "Stack Text", preset = "form", fields = {
            { control = "note", wide = true,
              text = "Controls the font and position of the stack count text "
                  .. "shown on aura icons on all unit frames." },
            Sw("oufStackShow", "Show Stack Text", RestyleAuras),
            Sw("oufStackAutoScale", "Auto Scale Stack Text", RestyleAuras, {
                desc = "When enabled, stack text size scales proportionally "
                    .. "with the aura icon size. Use the scale slider to "
                    .. "fine-tune. When disabled, a fixed font size is used "
                    .. "instead.",
                hidden = NoStackText,
                disabled = function()
                    return InCombatLockdown() or NoStackText()
                end }),
            -- 0.1-3.0 at step 0.1 has no honest integer scale, so it stays
            -- a direct bind: the thumb, the step and the stored value are
            -- exact and only the value BOX rounds. See the notes.
            Sl("oufStackScale", "Stack Text Scale", 0.1, 3.0, 0.1, nil, {
                hidden = function()
                    local p = P()
                    return NoStackText() or not (p and p.oufStackAutoScale == true)
                end,
                disabled = function()
                    return InCombatLockdown() or NoStackText()
                end,
                set = StackSet("oufStackScale") }),
        }},

        { title = "Stack Text Font", preset = "form", hidden = NoStackText, fields = {
            Sl("oufStackFontSize", "Font Size", 6, 20, 1, nil, {
                hidden = function()
                    local p = P()
                    return NoStackText() or (p and p.oufStackAutoScale == true)
                end,
                set = StackSet("oufStackFontSize") }),
            { control = "dropdown", label = "Font",
              id = "oufStackFont", default = d and d.oufStackFont,
              desc = "Choose a font for aura stack count text",
              disabled = "combat", options = FontOptions,
              hidden = NoStackText,
              -- Its own normalizer rather than the shared one: the aura
              -- default is the bundled Roboto Condensed Bold.
              get = function()
                  local bf = BF()
                  local p  = P()
                  if not (bf and p) then return nil end
                  return bf:NormalizeFontName(p.oufStackFont, "Roboto Condensed Bold")
              end,
              set = StackSet("oufStackFont") },
            Dd("oufStackFontBorder", "Font Border", STACK_FONT_BORDER_OPTIONS,
               nil, { hidden = NoStackText, set = StackSet("oufStackFontBorder") }),
        }},

        { title = "Stack Text Position", preset = "form", hidden = NoStackText, fields = {
            Dd("oufStackAnchor", "Anchor Point", STACK_ANCHOR_OPTIONS, nil,
               { hidden = NoStackText, set = StackSet("oufStackAnchor") }),
            Sl("oufStackX", "Horizontal Offset", -20, 20, 1, nil,
               { hidden = NoStackText, set = StackSet("oufStackX") }),
            Sl("oufStackY", "Vertical Offset", -20, 20, 1, nil,
               { hidden = NoStackText, set = StackSet("oufStackY") }),
        }},
    }
end

-- ── Fonts ──────────────────────────────────────────────────────

local function NoFonts()
    local p = P()
    return not (p and p.oufAdjustFonts)
end

local function NoSeparateFonts()
    local p = P()
    return not (p and p.oufAdjustFonts) or not (p and p.oufSeparateFonts)
end

-- The eight per-element font pickers. Each reads through the shared
-- normalizer (a legacy path or an unregistered name would otherwise
-- select nothing in the dropdown) and writes without one, exactly as
-- the Ace getFont/setFont pair does.
local function FontField(key, label, desc)
    local d = Defaults()
    return {
        control = "dropdown", label = label, desc = desc,
        id = key, default = d and d[key],
        options = FontOptions, disabled = "combat",
        hidden = NoSeparateFonts,
        get = function()
            local bf = BF()
            local p  = P()
            if not (bf and p) then return nil end
            return bf:NormalizeFontName(p[key])
        end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            p[key] = val
            RefreshFonts()
        end,
    }
end

function PAGES.fonts()
    local d = Defaults()
    return {
        { title = "Unit Frames Font", preset = "form", fields = {
            Sw("oufAdjustFonts", "Adjust Unit Frames Font", RelayoutAll, {
                wide = true,
                desc = "Enable custom font settings for unit frame text. When "
                    .. "disabled, the standard game font is used." }),
            {   -- The global font picker: same shape as the eight below,
                -- but its own hidden predicate (it does not need the
                -- per-element switch).
                control = "dropdown", label = "Unit Frames Font",
                id = "oufGlobalFont", default = d and d.oufGlobalFont,
                desc = "Font applied to all text on unit frames. Per-element "
                    .. "overrides below take priority when enabled.",
                options = FontOptions, disabled = "combat",
                hidden = NoFonts,
                get = function()
                    local bf = BF()
                    local p  = P()
                    if not (bf and p) then return nil end
                    return bf:NormalizeFontName(p.oufGlobalFont)
                end,
                set = function(_, _, val)
                    if InCombatLockdown() then return end
                    local p = P()
                    if not p then return end
                    p.oufGlobalFont = val
                    RefreshFonts()
                end },
            Sw("oufSeparateFonts", "Configure Separate Fonts Per Element",
               RefreshFonts,
               { wide = true, hidden = NoFonts,
                 desc = "When enabled, allows setting a different font for "
                     .. "each text element." }),
        }},

        { title = "Names", preset = "form", hidden = NoSeparateFonts, fields = {
            FontField("oufNameFont",  "Name Font",  "Font for unit name text."),
            FontField("oufLevelFont", "Level Font", "Font for unit level text."),
        }},

        { title = "Health", preset = "form", hidden = NoSeparateFonts, fields = {
            FontField("oufHealthPctFont", "Health Percent Font"),
            FontField("oufHealthValFont", "Health Value Font"),
        }},

        { title = "Power", preset = "form", hidden = NoSeparateFonts, fields = {
            FontField("oufPowerPctFont", "Power Percent Font"),
            FontField("oufPowerValFont", "Power Value Font"),
        }},

        { title = "Alt Power", preset = "form", hidden = NoSeparateFonts, fields = {
            FontField("oufAltPowerPctFont", "Alt Power Percent Font"),
            FontField("oufAltPowerValFont", "Alt Power Value Font"),
        }},
    }
end

-- ── Textures ───────────────────────────────────────────────────

function PAGES.textures()
    return {
        { title = "Health Bar Texture", preset = "form", fields = {
            Sw("oufUseCustomHealthBarTexture", "Use Custom Health Texture",
               RelayoutAll),
            Dd("oufHealthBarTexture", "Health Bar Texture", StatusbarOptions,
               RelayoutAll, {
                desc = "Texture for the health bar fill.",
                hidden = function()
                    local p = P()
                    return not (p and p.oufUseCustomHealthBarTexture)
                end }),
        }},

        { title = "Power Bar Texture", preset = "form", fields = {
            Sw("oufUseCustomPowerBarTexture", "Use Custom Power Texture",
               PowerTextureEffect),
            Dd("oufPowerBarTexture", "Power Bar Texture", StatusbarOptions,
               PowerTextureEffect, {
                desc = "Texture for the power bar fill.",
                hidden = function()
                    local p = P()
                    return not (p and p.oufUseCustomPowerBarTexture)
                end }),
        }},
    }
end

-- ── Icons/Indicators ───────────────────────────────────────────

local function NoRaidTarget()
    return not ROOT.oufShowRaidTarget
end

function PAGES.indicators()
    local d = Defaults()
    return {
        { title = "Raid Target Marker", preset = "form", fields = {
            Sw("oufShowRaidTarget", "Show Raid Target Marker", RelayoutAll,
               { wide = true,
                 desc = "Show the raid target marker icon (skull, cross, star, "
                     .. "etc.) on all unit frames." }),
            Sl("oufRaidTargetSize", "Size", 10, 48, 1, RelayoutAll,
               { hidden = NoRaidTarget }),
        }},

        { title = "Icon Position", preset = "form", hidden = NoRaidTarget, fields = {
            Sl("oufRaidTargetOffsetX", "X Offset", -30, 30, 1, RelayoutAll,
               { desc = "Moves the raid target marker horizontally.",
                 hidden = NoRaidTarget }),
            Sl("oufRaidTargetOffsetY", "Y Offset", -30, 30, 1, RelayoutAll,
               { desc = "Moves the raid target marker vertically.",
                 hidden = NoRaidTarget }),
            Dd("oufRaidTargetLocation", "Location", {
                { value = "center", text = "Center" },
                { value = "outer",  text = "Outer"  },
                { value = "inner",  text = "Inner"  },
              }, RelayoutAll,
              { desc = "Where the marker sits relative to the bar frame.\n"
                    .. "Center: marker center sits at the frame center "
                    .. "(default).\nOuter: marker sits outside the frame "
                    .. "bounds.\nInner: marker sits fully inside the frame "
                    .. "bounds.",
                hidden = NoRaidTarget }),
        }},

        -- The whole card goes on a client build with no ping-pin events:
        -- the feature cannot run there, and the gate is on the GROUP for
        -- the same reason the Ace source moved it off the subtab -- the
        -- Raid Target settings above must stay reachable.
        { title = "Ping Indicator", preset = "form",
          hidden = function()
              local bf = BF()
              return not (bf and bf.HasPingPinEvents and bf.HasPingPinEvents())
          end,
          fields = {
            { control = "note", wide = true,
              text = "Shows the ping pin when a group member pings the unit. "
                  .. "Target and focus pins mirror the game's own target/focus "
                  .. "ping receivers; the player pin mirrors the raid-frame "
                  .. "receiver, so it only works while grouped and requires "
                  .. "|cffffff00Show Pings on Raid Frames|r to be enabled in "
                  .. "the game's Ping settings. Pet, target-of-target and boss "
                  .. "frames have no receiver in the game and cannot show "
                  .. "pings." },
            Sw("oufShowPingIndicator", "Show Ping Indicator", ApplyPingIndicators,
               { wide = true,
                 desc = "Show the ping pin on unit frames when a group member "
                     .. "pings the unit." }),
            { control = "dropdown", label = "Ping Indicator Position",
              id = "oufPingIndicatorPosition",
              default = d and d.oufPingIndicatorPosition,
              desc = "Where the ping pin sits on the frame. Class Icon centers "
                  .. "it on the class icon (available while the class icon is "
                  .. "shown).",
              disabled = "combat",
              hidden = function() return not ROOT.oufShowPingIndicator end,
              -- Class Icon is only offered while the class icon is shown;
              -- the Ace `sorting` put it first when it was there.
              options = function()
                  local p = P()
                  local out = {}
                  if p and p.playerShowClassIcon ~= false then
                      out[#out + 1] = { value = "CLASSICON", text = "Class Icon" }
                  end
                  out[#out + 1] = { value = "CENTER", text = "Center" }
                  return out
              end,
              get = function()
                  local p = P()
                  local v = (p and p.oufPingIndicatorPosition) or "CENTER"
                  -- LEFT/RIGHT were removed; fold any saved value back to
                  -- Center.
                  if v ~= "CLASSICON" then v = "CENTER" end
                  return v
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  ROOT.oufPingIndicatorPosition = v
                  ApplyPingIndicators()
              end },
        }},
    }
end

-- ── Tooltips ───────────────────────────────────────────────────

function PAGES.tooltips()
    return {
        -- No refresh of any kind: the OnEnter hooks in BluzzardStyle read
        -- these keys live from the profile on every mouseover.
        { title = "Tooltips", preset = "form", fields = {
            Sw("showUnitTooltip", "Show Unit Tooltips", nil,
               { desc = "Enable tooltip when mousing over unit frames." }),
            Sw("showUnitTooltipInCombat", "Show In Combat", nil, {
                desc = "Enable unit frame tooltips when in combat.",
                -- Gated by Show Unit Tooltips: no point tuning combat
                -- behavior when the whole feature is off.
                hidden = function()
                    local p = P()
                    return p and p.showUnitTooltip == false
                end }),
        }},
    }
end

-- ── The section root page ──────────────────────────────────────

-- The reload prompt, verbatim: deferred a frame, because the popup must
-- not open inside the widget's own handler.
local function PromptReload()
    C_Timer.After(0, function() StaticPopup_Show("BUZZARDFRAMES_RELOAD_UI") end)
end

-- The six Hide Blizzard toggles differ by nothing but their key and
-- their names. HIDING applies live (ApplyBlizzardFrameVisibility);
-- un-hiding still needs a reload, because oUF:DisableBlizzard
-- unregisters Blizzard's frames irreversibly.
local function HideBlizzardField(key, label, desc)
    local d = Defaults()
    return {
        control = "switch", label = label, desc = desc,
        id = key, default = d and d[key],
        disabled = "combat",
        get = function() return ROOT[key] end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            p[key] = val
            if val then
                local bf = BF()
                if bf then bf:ApplyBlizzardFrameVisibility() end
            else
                PromptReload()
            end
        end,
    }
end

-- The seven per-frame enable toggles, which differ by nothing but their
-- key and their name -- so, like the six Hide Blizzard toggles below,
-- they are built rather than written out seven times.
--
-- They used to live one per page, each the single control its page kept
-- while its frame was off, because it was the switch that turned the
-- frame back on. Gathered here they are readable as a set -- which frames
-- are on is one glance rather than seven -- and each page is left with
-- the settings for a frame rather than the question of whether to have
-- one. The setter is the one those pages carried, unchanged: enabling is
-- LIVE, since oUF spawns a frame post-login out of combat, and only the
-- master switch above needs the reload.
-- `hideKey` is the frame's own "Hide Blizzard" key, cleared when the frame
-- is turned OFF: leaving it set hides Blizzard's frame for a frame of ours
-- that is no longer there, which is a unit with no frame at all. That is
-- the master switch's off-branch applied one frame at a time, and it wants
-- the same reload for the same reason -- oUF:DisableBlizzard unregisters
-- Blizzard's frames irreversibly, so un-hiding is a reload rather than a
-- repaint. Either direction acts only when the key is not already where it
-- is going: toggling a frame whose Blizzard counterpart already agrees
-- costs nothing and must not ask for a reload.
--
-- Focus Target passes no `hideKey`. There is no Blizzard focus-target
-- frame to un-hide, which is why the card below has six toggles and this
-- list has seven.
--
-- Turning a frame ON ticks the key back, which is the same move mirrored:
-- our frame and Blizzard's should not be stacked on the same unit any more
-- than the unit should end up with neither. Hiding is LIVE
-- (ApplyBlizzardFrameVisibility), so that direction needs no reload -- the
-- asymmetry in what follows is Blizzard's, not this card's. A reader who
-- wants both frames can untick the Hide Blizzard toggle afterwards, as
-- they always could.
local function FrameEnableField(key, label, desc, hideKey)
    local d = Defaults()
    return {
        control = "switch", label = label, desc = desc,
        id = key, default = d and d[key],
        disabled = "combat",
        get = function() return ROOT[key] end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local p = P()
            if not p then return end
            p[key] = val
            local bf = BF()
            if bf then bf:ApplyOUFVisibility() end
            if hideKey then
                if val and not p[hideKey] then
                    p[hideKey] = true
                    if bf then bf:ApplyBlizzardFrameVisibility() end
                elseif not val and p[hideKey] then
                    p[hideKey] = false
                    PromptReload()
                end
            end
        end,
    }
end

function BuzzardFramesOptions:UnitFramesRootPage()
    local d = Defaults()
    return {
        db       = Root,
        defaults = Defaults,
        groups = {
            -- The master switch is the card's HEADER GATE rather than a
            -- field, the way the Raid/Party enables are: the card reads
            -- "[switch] Unit Frames" and collapses to that header when it
            -- is off, which takes the seven frame toggles with it. They
            -- are meaningless while the master is off, and this is the
            -- library saying so structurally rather than seven predicates
            -- saying it one at a time.
            { title = "Enable Unit Frames", preset = "form",
              toggle = {
                id = "ptfEnabled", default = d and d.ptfEnabled,
                tooltip = "Enable Unit Frames",
                desc = "Master switch for all Player & Target frame "
                    .. "functionality. Requires a UI reload to take effect.",
                get = function() return ROOT.ptfEnabled end,
                -- The Ace setter's chain, in the Ace setter's order.
                set = function(_, ctx, val)
                    if InCombatLockdown() then return end
                    local p = P()
                    if not p then return end
                    p.ptfEnabled = val
                    if val then
                        -- When enabling unit frames for the first time,
                        -- auto-tick all "Hide Blizzard" checkboxes so the
                        -- built-in frames are hidden. The reader can
                        -- individually untick them afterwards.
                        p.hideBlizzardPlayerFrame = true
                        p.hideBlizzardTargetFrame = true
                        p.hideBlizzardFocusFrame  = true
                        p.hideBlizzardPetFrame    = true
                        -- hideBlizzardTargetOfTargetFrame is NOT
                        -- auto-ticked because the Target of Target frame
                        -- is disabled by default.
                        p.showBossFrames         = true
                        p.hideBlizzardBossFrames = true
                    else
                        -- Mirror of the enable branch: when disabling,
                        -- auto-untick every "Hide Blizzard" checkbox so
                        -- Blizzard's default frames come back after the
                        -- required UI reload.
                        -- hideBlizzardTargetOfTargetFrame IS cleared here
                        -- (unlike the enable branch) so any user-set value
                        -- is fully reset.
                        p.hideBlizzardPlayerFrame         = false
                        p.hideBlizzardTargetFrame         = false
                        p.hideBlizzardFocusFrame          = false
                        p.hideBlizzardPetFrame            = false
                        p.hideBlizzardTargetOfTargetFrame = false
                        p.showBossFrames                  = false
                        p.hideBlizzardBossFrames          = false
                    end
                    -- syncPTFTabs' place in the chain, and the same job:
                    -- it NILLED the eight sub-tabs out of the args table
                    -- while unit frames were off, so the equivalent here
                    -- is rebuilding the route tree without them.
                    -- RebuildRoutes re-runs Panel.lua's declaration, which
                    -- asks this same flag; SetRoutes re-points a route
                    -- that no longer exists at the first section, so
                    -- turning the switch off from a page that is about to
                    -- vanish lands somewhere real rather than nowhere.
                    --
                    -- The pages keep their own ptfEnabled predicates on
                    -- top of this. Not belt-and-braces: the write above
                    -- has already happened, and a page can render between
                    -- it and the rebuild.
                    if ctx and ctx.app then
                        BuzzardFramesOptions:RebuildRoutes(ctx.app)
                    end
                    -- A reload is required for the frames themselves, but
                    -- the shared ping mirror is live NOW and its collected
                    -- pins are gated on this flag. Re-resolve so the
                    -- pre-reload window stays coherent: without it the
                    -- ticker keeps mirroring onto frames the profile now
                    -- says are off, and the mirror's retarget handler
                    -- (also gated on this flag) has stopped clearing them.
                    local bf = BF()
                    if bf and bf.RebuildPingMirror then bf:RebuildPingMirror() end
                    PromptReload()
                end,
              },
              fields = {
                FrameEnableField("showPlayerFrame", "Player",
                    "Show the Player unit frame.",
                    "hideBlizzardPlayerFrame"),
                FrameEnableField("showTargetFrame", "Target",
                    "Show the Target unit frame.",
                    "hideBlizzardTargetFrame"),
                FrameEnableField("showFocusFrame", "Focus",
                    "Show the Focus unit frame.",
                    "hideBlizzardFocusFrame"),
                FrameEnableField("showPetFrame", "Pet",
                    "Show the Pet unit frame.",
                    "hideBlizzardPetFrame"),
                FrameEnableField("showTargetOfTargetFrame", "Target of Target",
                    "Show the Target of Target unit frame.",
                    "hideBlizzardTargetOfTargetFrame"),
                FrameEnableField("showFocusTargetFrame", "Focus Target",
                    "Show the Focus Target unit frame."),
                FrameEnableField("showBossFrames", "Boss Frames",
                    "Show the Boss unit frames.",
                    "hideBlizzardBossFrames"),
            }},

            { title = "Hide Blizzard Frames", preset = "form",
              -- The Ace group sat below the master switch and was visible
              -- whatever it said, so this card is NOT gated on ptfEnabled.
              fields = {
                HideBlizzardField("hideBlizzardPlayerFrame", "Player",
                    "Hides Blizzard's player unit frame (health bar, power "
                    .. "bar, portrait)."),
                HideBlizzardField("hideBlizzardTargetFrame", "Target",
                    "Hides Blizzard's target unit frame."),
                HideBlizzardField("hideBlizzardFocusFrame", "Focus",
                    "Hides Blizzard's focus unit frame."),
                HideBlizzardField("hideBlizzardPetFrame", "Pet",
                    "Hides Blizzard's pet unit frame."),
                HideBlizzardField("hideBlizzardTargetOfTargetFrame",
                    "Target of Target",
                    "Hides Blizzard's target of target unit frame."),
                HideBlizzardField("hideBlizzardBossFrames", "Boss Frames",
                    "Hides Blizzard's boss unit frames."),
            }},

            -- There is no Blizzard focus-target frame to hide, so no
            -- hideBlizzardFocusTargetFrame toggle is needed.
        },
    }
end

-- ── The Global page ────────────────────────────────────────────

-- The Global strip's routes, one level deep where the list says so.
--
-- SubtabRoutes in Panel.lua builds a flat list; this is the same idea with
-- a `children` entry honored, which only this section needs today. A node
-- with children gets `navigator = "tabs"` and NO page of its own, so
-- selecting Colors descends to Health Bars -- the Ace behavior, where
-- picking a parent tab lands you on its first child.
function BuzzardFramesOptions:UnitFramesGlobalRoutes()
    local out = {}
    for i, st in ipairs(self.UNITFRAMES_GLOBAL_SUBTABS or {}) do
        if st.children then
            local kids = {}
            for j, k in ipairs(st.children) do
                kids[j] = {
                    id = k.id, title = k.title,
                    page = function() return self:UnitFramesGlobalPage(k.id) end,
                }
            end
            out[i] = { id = st.id, title = st.title,
                       navigator = "tabs", children = kids }
        else
            out[i] = {
                id = st.id, title = st.title,
                page = function() return self:UnitFramesGlobalPage(st.id) end,
            }
        end
    end
    return out
end

function BuzzardFramesOptions:UnitFramesGlobalPage(subtabId)
    local build = PAGES[subtabId]
    if not build then return { db = Root, defaults = Defaults, groups = {} } end

    local groups = { self:UnitFramesDisabledNote() }
    for _, g in ipairs(build()) do
        -- The Ace globalTab carried `hidden = not ptfEnabled` on the tab
        -- itself. A route cannot hide, so the gate lands on every card,
        -- composed with whatever predicate that card already had.
        local own = g.hidden
        if own == nil then
            g.hidden = UFOff
        elseif type(own) == "function" then
            g.hidden = function(node, ctx) return UFOff() or own(node, ctx) end
        else
            g.hidden = function() return UFOff() or own end
        end
        groups[#groups + 1] = g
    end

    return { db = Root, defaults = Defaults, groups = groups }
end
