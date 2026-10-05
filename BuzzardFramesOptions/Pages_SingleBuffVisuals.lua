-- ============================================================
-- BuzzardFramesOptions: Pages_SingleBuffVisuals.lua
--
-- The four VISUAL subtabs of a Buff List entry -- Icon, Icon Effects,
-- Cooldown Text and Frame Effects -- as BuzzardPanel groups. These are the
-- per-spell customization surface: what a "Show (Customized Buff)" entry
-- gets over and above its container's own settings.
--
-- Storage is the entry's OWN copy of the visual families, under the
-- container record:
--
--     c.sbVisuals[<family>]["sb"][<spellID>]
--
-- the same shape the curated per-spec store has (acDB.profile[family]
-- [<specID>][spellID]) with the container standing in for the spec, so
-- two entries of one spell can differ. Nothing here reads or writes the
-- curated store; the render side resolves the entry's copy through
-- BF.GetSingleBuffVisualEntry, and the Display Type dropdown on the
-- Position tab is what switches it on and off ("Show (Default Buff)" sets
-- singleBuffCustomized = false, and the reader ignores the store).
--
-- Widget for widget, the Ace visual tabs: same fields, same defaults, same
-- gates, same refresh keys, so an edit from either panel coalesces into
-- the same pass. What is NOT here: the Icon tab's container-assignment
-- widgets (a single buff is not an assignment target) and its Position
-- dropdown (relocated to the Position tab as "Order", where Buzzard Frames
-- moved it), and the Icon Size card, which the Buff List's own page builds
-- and appends to the Icon tab, since it is a container field rather than a
-- visual family.
--
-- Entry point: BuzzardFramesOptions:SingleBuffVisualTabs(getC, sid), which
-- returns { icon = groups, iconEffects = groups, cooldownText = groups,
-- frameEffects = groups }. `getC` resolves the entry's container fresh on
-- every call -- by KEY, never by array index, because deleting another
-- entry renumbers the array under a closure that outlives the rebuild.
-- ============================================================

local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

local SB_KSPEC = "sb"

-- Icon Effects defaults. Never handed out by reference: the setters copy
-- on write, so a saved-variables table can never alias one of these.
local IE_DEFAULT_COLOR    = { r = 1, g = 0.82, b = 0.25, a = 1 }
local IE_DEFAULT_PANDEMIC = { r = 0.239216, g = 1, b = 0.254902, a = 0.15 }
local IE_DEFAULT_RECOLOR  = { r = 1, g = 1, b = 1, a = 0.5 }
local IE_EMPTY = {}

-- A store for an entry that no longer resolves: writes land here and are
-- lost, which is the right thing for a widget outliving its record.
local orphanStore = {}

local FONT_BORDER_OPTIONS = {
    { value = "",                          text = "None" },
    { value = "OUTLINE",                   text = "Outline" },
    { value = "THICKOUTLINE",              text = "Thick Outline" },
    { value = "MONOCHROME",                text = "Monochrome" },
    { value = "OUTLINE, MONOCHROME",       text = "Outline + Monochrome" },
    { value = "THICKOUTLINE, MONOCHROME",  text = "Thick Outline + Monochrome" },
}

-- ── Refresh helpers ────────────────────────────────────────────
--
-- The same named keys the Ace setters used, so a burst of edits from
-- either panel is one pass. ctx.app:RefreshPage() stands in for
-- NotifyChangeSafe: it repaints values and re-evaluates every hidden
-- predicate on the visible page.

local function Rebuild()
    local bf = BF()
    if bf then bf:RefreshContainersWithRebuildDebounced() end
end

local function PreviewSoon()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("acPanelPreviewNotify", function()
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
    end)
end

-- The Buff List preview pass paints these entries' icon effects itself,
-- so the right thing after an Icon Effects edit is to repaint that pass.
local function IconEffectsPreviewSoon()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("sbPreviewRefresh", function()
        if InCombatLockdown() then return end
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
    end, 0.05)
end

-- The debounced cooldown-text refresh, mirroring the spec tabs': a full
-- aura refresh per slider notch is what this coalesces.
local function CooldownTextRefreshSoon()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("acSpellCTRefresh", function()
        if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
        if bf.InvalidateContainerIconCaches    then bf.InvalidateContainerIconCaches()    end
        bf:RebuildExpiringColorCurves()
        bf:RefreshAllAuras()
        if bf.RefreshPreviewDummyContainers then bf:RefreshPreviewDummyContainers() end
        -- A single buff anchored to Buffs or Big Defensive is painted by the
        -- ROW assemblers, not the container pass, so the full refresh covers
        -- every bucket.
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
    end, 0.05)
end

local function WipeCurveCache()
    local bf = BF()
    if bf and bf._solidIconColorCurveCache then table.wipe(bf._solidIconColorCurveCache) end
end

local function Repaint(ctx)
    if ctx and ctx.app then ctx.app:RefreshPage() end
end

-- Color tables cross the panel boundary as { r, g, b, a } arrays; the
-- store keeps named fields.
local function ColorOut(r, g, b, a) return { r, g, b, a } end

-- ── The Layout/Custom Frame Group selector the Cooldown Text tab uses ──
--
-- The per-spell cooldown-text entries keep their own live "Enable
-- per-Layout Config" toggle and therefore their own in-page scope
-- selector. Session state, shared by every entry, so the selection
-- persists while moving through the list -- exactly as the Ace panel kept
-- it.
local spellEditingGroupType = nil

local function DefaultGroupType()
    local bf = BF()
    local fl = bf and bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts
               and bf.rpDB.profile.layouts.flatLayouts or {}
    local mf = bf and bf._modifyingFlat
    if mf and fl[mf] then return mf end
    if fl.flat_party then return "flat_party" end
    for id in pairs(fl) do return id end
    return "flat_party"
end

local function EditingGroupType()
    return spellEditingGroupType or DefaultGroupType()
end

-- Seeded flats first (flat_party, flat_raid20/30/40), then user flats
-- alphabetical, then the enabled custom frame groups in tab order.
local function GroupTypeOptions()
    local bf  = BF()
    local out = {}
    local fl = bf and bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts
               and bf.rpDB.profile.layouts.flatLayouts or {}
    local seeded = { "flat_party", "flat_raid20", "flat_raid30", "flat_raid40" }
    local seen   = {}
    local function flatText(id)
        local flat = fl[id]
        local typeTag = (flat.type == "party") and "Party" or "Raid"
        return (flat.name or id) .. " (" .. typeTag .. ")"
    end
    for _, id in ipairs(seeded) do
        if fl[id] then
            out[#out + 1] = { value = id, text = flatText(id) }
            seen[id] = true
        end
    end
    local extras = {}
    for id in pairs(fl) do
        if not seen[id] then extras[#extras + 1] = id end
    end
    table.sort(extras)
    for _, id in ipairs(extras) do
        out[#out + 1] = { value = id, text = flatText(id) }
    end
    local cfGroups = (bf and bf.GetCustomFrameGroups and bf:GetCustomFrameGroups()) or {}
    for i, group in ipairs(cfGroups) do
        if group.enabled ~= false then
            local id = bf.GetCFGFlatID and bf:GetCFGFlatID(i)
            if id then
                out[#out + 1] = { value = id,
                                  text  = "Custom Frame Group: " .. (group.name or ("Group " .. i)) }
            end
        end
    end
    return out
end

-- ── The tabs ───────────────────────────────────────────────────

function BuzzardFramesOptions:SingleBuffVisualTabs(getC, sid)
    local kSpec = SB_KSPEC

    -- The store root: the entry's own visual families, created on first
    -- write. An entry that no longer resolves gets the orphan store.
    local function SROOT()
        local c = getC()
        if type(c) ~= "table" then return orphanStore end
        if not c.sbVisuals then c.sbVisuals = {} end
        return c.sbVisuals
    end

    -- ── Icon Effects storage ───────────────────────────────────
    -- ONE entry table per spell: sbVisuals.specSpellIconEffect["sb"][sid].
    -- IE_GET never creates -- a widget merely rendering cannot litter
    -- saved variables. IE_SET creates the row, applies one mutation, drops
    -- the row again when it is left empty, and runs the one refresh path.
    local function IE_GET()
        local p = SROOT()
        local t = p.specSpellIconEffect and p.specSpellIconEffect[kSpec]
        return (t and t[sid]) or IE_EMPTY
    end
    local function IE_SET(ctx, mutate)
        if InCombatLockdown() then return end
        local p = SROOT()
        if not p.specSpellIconEffect then p.specSpellIconEffect = {} end
        if not p.specSpellIconEffect[kSpec] then p.specSpellIconEffect[kSpec] = {} end
        local e = p.specSpellIconEffect[kSpec][sid]
        if not e then e = {}; p.specSpellIconEffect[kSpec][sid] = e end
        mutate(e)
        if next(e) == nil then p.specSpellIconEffect[kSpec][sid] = nil end
        Rebuild()
        IconEffectsPreviewSoon()
        Repaint(ctx)
    end

    -- ── Icon-type resolution, shared by the Icon and Border cards ──
    -- Two former dropdown choices are gone but their stored values are
    -- mapped at READ time rather than migrated: "BorderedSquare" is Square
    -- with the border on, "SquareDuration" is Square whose glyph path is
    -- now driven by the entry's thresholdEnabled flag. Setters that touch
    -- square state normalize the stored value (NormalizeStoredIconType).
    local function storedIconType()
        local p = SROOT()
        return p.specSpellIconType and p.specSpellIconType[kSpec]
               and p.specSpellIconType[kSpec][sid]
    end
    local function effIconType()
        local it = storedIconType()
        if it == "BorderedSquare" or it == "SquareDuration" then return "Square" end
        return it
    end
    local function solidEntry()
        local p = SROOT()
        return p.specSpellSolidIcons and p.specSpellSolidIcons[kSpec]
               and p.specSpellSolidIcons[kSpec][sid]
    end
    -- Get-or-create the solidIcons entry for WRITING border-shape fields on
    -- an Icon-type buff. Born with the SQUARE fill disabled: the entry
    -- exists only to carry border fields; if the buff is switched to
    -- Square, the icon-type setter clears `enabled`.
    local function ensureSolidEntry()
        local p = SROOT()
        if not p.specSpellSolidIcons then p.specSpellSolidIcons = {} end
        if not p.specSpellSolidIcons[kSpec] then p.specSpellSolidIcons[kSpec] = {} end
        local e = p.specSpellSolidIcons[kSpec][sid]
        if not e then
            e = { r = 0.0, g = 0.7, b = 1.0, a = 1.0, enabled = false }
            p.specSpellSolidIcons[kSpec][sid] = e
        end
        return e
    end
    local function ensureSquareEntry()
        local p = SROOT()
        if not p.specSpellSolidIcons then p.specSpellSolidIcons = {} end
        if not p.specSpellSolidIcons[kSpec] then p.specSpellSolidIcons[kSpec] = {} end
        if not p.specSpellSolidIcons[kSpec][sid] then
            p.specSpellSolidIcons[kSpec][sid] = { r = 0.0, g = 0.7, b = 1.0, a = 1.0 }
        end
        return p.specSpellSolidIcons[kSpec][sid]
    end
    local function squareBorderShown()
        if storedIconType() == "BorderedSquare" then return true end
        local e = solidEntry()
        return (e and e.showBorder) or false
    end
    -- "Use Buffs Border": inherit the container's Buffs-section border. An
    -- explicit boolean once touched; when ABSENT the default is per type --
    -- Icon inherits (on), Square draws its own (off). The render side
    -- resolves this identically via BF.UseBuffsBorderOn.
    local function useBuffsBorderOn()
        local e = solidEntry()
        local v = e and e.useBuffsBorder
        if v == true then return true end
        if v == false then return false end
        return effIconType() ~= "Square"
    end
    local function NormalizeStoredIconType()
        local p = SROOT()
        local t = p.specSpellIconType and p.specSpellIconType[kSpec]
                  and p.specSpellIconType[kSpec][sid]
        if t ~= "BorderedSquare" and t ~= "SquareDuration" then return end
        p.specSpellIconType[kSpec][sid] = "Square"
        if t == "BorderedSquare" then
            ensureSquareEntry().showBorder = true
        end
    end
    local function isSquare()    return effIconType() == "Square" end
    local function notSquare()   return effIconType() ~= "Square" end
    local function thresholdOff()
        local e = solidEntry()
        return not (e and e.thresholdEnabled)
    end
    local function secondaryOff()
        local e = solidEntry()
        return not (e and e.thresholdEnabled and e.secondaryEnabled)
    end

    -- The square-write setter shape every Icon Color widget shares: wipe
    -- the curve cache (single-buff entries cache under "sb:<key>:<sid>"
    -- keys a [sid] nil would miss), rebuild, repaint the preview.
    local function squareChanged(ctx)
        WipeCurveCache()
        Rebuild()
        PreviewSoon()
        Repaint(ctx)
    end

    -- ══════════════════════════════════════════════════════════
    -- ICON
    -- ══════════════════════════════════════════════════════════
    local icon = {}

    icon[#icon + 1] = { title = "Buff Icon", preset = "form", fields = {
        { control = "dropdown", label = "Icon Type",
          desc = "Icon: normal spell texture. Square: solid color square -- "
              .. "border configurable in the Icon Border group, and its color "
              .. "can change based on the buff's remaining time (Icon Color "
              .. "group).",
          options = { { value = "Icon", text = "Icon" },
                      { value = "Square", text = "Square" } },
          id = "sbIconType", default = "Icon", disabled = "combat",
          get = function() return effIconType() or "Icon" end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellIconType then p.specSpellIconType = {} end
              if not p.specSpellIconType[kSpec] then p.specSpellIconType[kSpec] = {} end
              if val == "Icon" then
                  p.specSpellIconType[kSpec][sid] = nil
              else
                  p.specSpellIconType[kSpec][sid] = val
              end
              if not p.specSpellSolidIcons then p.specSpellSolidIcons = {} end
              if not p.specSpellSolidIcons[kSpec] then p.specSpellSolidIcons[kSpec] = {} end
              if val == "Icon" then
                  if p.specSpellSolidIcons[kSpec][sid] then
                      p.specSpellSolidIcons[kSpec][sid].enabled = false
                  end
              else
                  if not p.specSpellSolidIcons[kSpec][sid] then
                      p.specSpellSolidIcons[kSpec][sid] = { r = 0.0, g = 0.7, b = 1.0, a = 1.0 }
                  else
                      p.specSpellSolidIcons[kSpec][sid].enabled = nil
                  end
              end
              Rebuild()
              PreviewSoon()
              -- Whether the Cooldown Text tab EXISTS depends on the type
              -- (a Square colored by remaining time owns its duration
              -- text), so the entry's tab routes are re-derived.
              ctx.app:Invalidate("singleBuffs")
              Repaint(ctx)
          end },
    }}

    icon[#icon + 1] = { title = "Icon Color", preset = "form", fields = {
        { control = "color", label = "Icon Color", alpha = true,
          id = "sbSolidIconColor", disabled = "combat", hidden = notSquare,
          get = function()
              local c = solidEntry() or { r = 0.0, g = 0.7, b = 1.0, a = 1.0 }
              return ColorOut(c.r, c.g, c.b, c.a or 1.0)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellSolidIcons then p.specSpellSolidIcons = {} end
              if not p.specSpellSolidIcons[kSpec] then p.specSpellSolidIcons[kSpec] = {} end
              if not p.specSpellSolidIcons[kSpec][sid] then p.specSpellSolidIcons[kSpec][sid] = {} end
              local e = p.specSpellSolidIcons[kSpec][sid]
              e.r, e.g, e.b, e.a = v[1], v[2], v[3], v[4]
              -- Icon Color is the above-threshold color of the curve.
              squareChanged(nil)
          end },
        -- `width = "full"`, not `wide`: this label is a sentence, and
        -- `wide` on a switch caps the cell at a control's width -- enough
        -- for the toggle and not for what it says, so the text was clipped.
        -- The Ace widget says width = "full" for the same reason.
        { control = "switch", width = "full", labelSide = "after",
          label = "Change Color Based on Remaining Time",
          desc = "Change the square's color when the buff's remaining time "
              .. "drops below a threshold. While enabled, the square is drawn "
              .. "by the engine's duration text (that is what makes the color "
              .. "change possible), so the Cooldown Text subtab is hidden and "
              .. "buffs with NO duration cannot display a square. Color alpha "
              .. "is also ignored -- the square renders fully opaque.",
          id = "sbThresholdEnabled", default = false, disabled = "combat",
          hidden = notSquare,
          get = function()
              local e = solidEntry()
              return (e and e.thresholdEnabled) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              NormalizeStoredIconType()
              ensureSquareEntry().thresholdEnabled = val or nil
              -- The Cooldown Text tab comes and goes with this flag.
              ctx.app:Invalidate("singleBuffs")
              squareChanged(ctx)
          end },
        { control = "color", label = "Threshold Color",
          desc = "Color of the square while remaining time is below the threshold.",
          id = "sbThresholdColor", disabled = "combat",
          hidden = function() return notSquare() or thresholdOff() end,
          get = function()
              local e = solidEntry()
              if not e then return ColorOut(1, 0.5, 0, 1) end
              return ColorOut(e.thresholdR or 1, e.thresholdG or 0.5, e.thresholdB or 0, 1)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local e = solidEntry()
              if not e then return end
              e.thresholdR, e.thresholdG, e.thresholdB = v[1], v[2], v[3]
              squareChanged(nil)
          end },
        -- max 59, not 60: these are SUB-MINUTE thresholds (the duration
        -- formatter switches to "1m" at 60), and the pair must be able to
        -- straddle a whole second -- 59/58 is the highest legal pair.
        { control = "slider", label = "Threshold (seconds)",
          desc = "Remaining time below which the square uses the Threshold Color.",
          min = 1, max = 59, step = 1,
          id = "sbThresholdSecs", default = 8, disabled = "combat",
          hidden = function() return notSquare() or thresholdOff() end,
          get = function()
              local e = solidEntry()
              return (e and e.thresholdSecs) or 8
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local e = solidEntry()
              if not e then return end
              e.thresholdSecs = val
              -- Push the secondary down with the primary: the curve's
              -- `t2 < t1` test would otherwise fail and the secondary color
              -- silently stop rendering while its slider showed a value.
              if e.secondarySecs and e.secondarySecs >= val then
                  e.secondarySecs = math.max(1, val - 1)
              end
              squareChanged(nil)
          end },
        -- A BREAK, not a width: "Secondary Threshold" is two words and has
        -- no use for a row-wide cell -- what the Ace page's width = "full"
        -- is doing here is ending the row, above it and after it.
        { control = "linebreak" },
        { control = "switch", labelSide = "after",
          label = "Secondary Threshold",
          desc = "Add a second, lower threshold with its own color (takes "
              .. "priority below its time).",
          id = "sbSecondaryEnabled", default = false, disabled = "combat",
          hidden = function() return notSquare() or thresholdOff() end,
          get = function()
              local e = solidEntry()
              return (e and e.secondaryEnabled) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local e = solidEntry()
              if not e then return end
              e.secondaryEnabled = val or nil
              squareChanged(ctx)
          end },
        { control = "linebreak" },
        { control = "color", label = "Secondary Threshold Color",
          desc = "Color of the square while remaining time is below the "
              .. "secondary threshold.",
          id = "sbSecondaryColor", disabled = "combat",
          hidden = function() return notSquare() or secondaryOff() end,
          get = function()
              local e = solidEntry()
              if not e then return ColorOut(1, 0, 0, 1) end
              return ColorOut(e.secondaryR or 1, e.secondaryG or 0, e.secondaryB or 0, 1)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local e = solidEntry()
              if not e then return end
              e.secondaryR, e.secondaryG, e.secondaryB = v[1], v[2], v[3]
              squareChanged(nil)
          end },
        -- SNAPPED to primary-minus-one in BOTH get and set: the slider's own
        -- max cannot express "below the other slider", so the clamp lives
        -- in the accessors -- set never stores an illegal value, and get
        -- re-clamps a value stored before the primary moved.
        { control = "slider", label = "Secondary Threshold (seconds)",
          desc = "Remaining time below which the square uses the Secondary "
              .. "Threshold Color. Must be lower than the first threshold.",
          min = 1, max = 59, step = 1,
          id = "sbSecondarySecs", default = 4, disabled = "combat",
          hidden = function() return notSquare() or secondaryOff() end,
          get = function()
              local e = solidEntry()
              if not e then return 4 end
              local limit = math.max(1, (e.thresholdSecs or 8) - 1)
              return math.min(e.secondarySecs or 4, limit)
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local e = solidEntry()
              if not e then return end
              local limit = math.max(1, (e.thresholdSecs or 8) - 1)
              e.secondarySecs = math.min(val, limit)
              squareChanged(nil)
          end },
        -- Icon-type only: these act on the real spell texture, so they only
        -- apply -- and only show -- when Icon Type is Icon. Storage is the
        -- Icon Effects row (IE_GET/IE_SET), unchanged.
        { control = "switch", labelSide = "after", label = "Desaturate",
          desc = "Draw this aura's icon in grayscale.",
          id = "sbIconDesaturate", default = false, disabled = "combat",
          hidden = isSquare,
          get = function() return IE_GET().desaturate == true end,
          set = function(_, ctx, val)
              IE_SET(ctx, function(e) e.desaturate = val or nil end)
          end },
        { control = "switch", labelSide = "after", label = "Recolor",
          desc = "Tint this aura's icon with a colored overlay.",
          id = "sbIconRecolor", default = false, disabled = "combat",
          hidden = isSquare,
          get = function() return IE_GET().recolor == true end,
          set = function(_, ctx, val)
              IE_SET(ctx, function(e) e.recolor = val or nil end)
          end },
        { control = "color", label = "Recolor Tint", alpha = true,
          id = "sbIconRecolorColor", disabled = "combat",
          hidden = function() return isSquare() or IE_GET().recolor ~= true end,
          get = function()
              local c = IE_GET().recolorColor or IE_DEFAULT_RECOLOR
              return ColorOut(c.r or 1, c.g or 1, c.b or 1, c.a or 0.5)
          end,
          set = function(_, ctx, v)
              IE_SET(nil, function(e)
                  e.recolorColor = { r = v[1], g = v[2], b = v[3], a = v[4] }
              end)
          end },
    }}

    -- Border color lives in its own family, keyed the same way.
    local function borderColorEntry()
        local p = SROOT()
        return p.specSpellBorderColors and p.specSpellBorderColors[kSpec]
               and p.specSpellBorderColors[kSpec][sid]
    end
    -- Inheriting the Buffs border? Its color lives in the Buffs section --
    -- no per-spell color here. Square: only while the border is shown.
    -- Icon: the border is always drawn when opted out, so the color
    -- always applies.
    local function adjustColorHidden()
        if useBuffsBorderOn() then return true end
        if isSquare() then return not squareBorderShown() end
        return false
    end

    -- The ICON type's border shape: blizzard / flat / rounded, with
    -- rounded_thick folded into the weight strip.
    local function iconBorderStyleValue()
        local e  = solidEntry()
        local bs = e and e.borderStyle
        if bs == "blizzard" or bs == "rounded" or bs == "rounded_thick" then
            return bs
        end
        return "flat"
    end
    local iconBorderStyle, iconBorderWeight = BuzzardFramesOptions:BorderStyleFields({
        id = "sbIconBorderStyle", default = "flat",
        options = { { value = "blizzard", text = "Blizzard" },
                    { value = "flat",     text = "Square" },
                    { value = "rounded",  text = "Rounded" } },
        desc = "Blizzard uses the game's default icon border. Square draws "
            .. "a flat colored border; Rounded masks the icon to a rounded "
            .. "rectangle inside a colored frame.",
        hidden = function()
            if isSquare() then return true end
            return useBuffsBorderOn()
        end,
        get = iconBorderStyleValue,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            ensureSolidEntry().borderStyle = (val ~= "flat") and val or nil
            Rebuild()
            PreviewSoon()
        end,
    })
    -- The SQUARE's border shape: flat / rounded, same weight strip. The
    -- static square rounds its fill via the icon mask; with remaining-time
    -- coloring on, via a rounded-corner glyph font. Same value either way.
    local squareBorderStyle, squareBorderWeight = BuzzardFramesOptions:BorderStyleFields({
        id = "sbSquareBorderStyle", default = "flat",
        options = { { value = "flat",    text = "Square" },
                    { value = "rounded", text = "Rounded" } },
        desc = "Square draws the flat colored border. Rounded masks the "
            .. "square to a rounded rectangle inside a colored frame.",
        hidden = function()
            if notSquare() or useBuffsBorderOn() then return true end
            return not squareBorderShown()
        end,
        get = function()
            local e  = solidEntry()
            local bs = e and e.borderStyle
            return (bs == "rounded" or bs == "rounded_thick") and bs or "flat"
        end,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            local e = solidEntry()
            if not e then return end
            e.borderStyle = (val ~= "flat") and val or nil
            Rebuild()
            PreviewSoon()
        end,
    })

    icon[#icon + 1] = { title = "Icon Border", preset = "form", fields = {
        -- Shown for BOTH icon types. Turning it OFF exposes that type's own
        -- border controls -- the Icon set (style/thickness) or the Square
        -- set (Show Border/style). All stored on the shared solidIcons
        -- entry, so switching icon type keeps them.
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBUse Buffs Border|r",
          desc = "When enabled, this buff inherits the border (style, "
              .. "thickness, color) from the active Buffs settings. Disable it "
              .. "to give this buff its own border below.",
          id = "sbUseBuffsBorder", default = true, disabled = "combat",
          get = useBuffsBorderOn,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              -- The EXPLICIT boolean, not nil: Square's default is off, so
              -- opting IN needs a stored true.
              ensureSolidEntry().useBuffsBorder = val and true or false
              Rebuild()
              PreviewSoon()
              Repaint(ctx)
          end },
        -- Icon type has NO Show Border toggle: an Icon that opts out of the
        -- Buffs border always draws its own.
        --
        -- Shape and weight over the one `borderStyle` key, as every border
        -- on this panel is: the strip says Blizzard / Square / Rounded, and
        -- a second strip beside it says Thin / Thick for the rounded frame.
        iconBorderStyle,
        iconBorderWeight,
        { control = "stepper", label = "Border Thickness", min = 1, max = 5, step = 1,
          desc = "Thickness of this buff's border. Ignored for the Blizzard style.",
          id = "sbIconBorderThickness", default = 1, disabled = "combat",
          hidden = function()
              if isSquare() or useBuffsBorderOn() then return true end
              -- The rounded frame's weight is the Thin/Thick strip; only
              -- the flat square border has a thickness in pixels.
              return iconBorderStyleValue() ~= "flat"
          end,
          get = function()
              local e = solidEntry()
              return (e and e.borderThickness) or 1
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              ensureSolidEntry().borderThickness = val
              Rebuild()
              PreviewSoon()
          end },
        -- Show Border and the style it applies to read as one decision --
        -- whether there is a border, and which -- so they share a row and
        -- the break comes after the pair rather than between them.
        { control = "switch", labelSide = "after",
          label = "Show Border",
          desc = "Draw a border around the square.",
          id = "sbShowBorder", default = false, disabled = "combat",
          hidden = function()
              if notSquare() then return true end
              return useBuffsBorderOn()
          end,
          get = squareBorderShown,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              NormalizeStoredIconType()
              ensureSquareEntry().showBorder = val or nil
              Rebuild()
              PreviewSoon()
              Repaint(ctx)
          end },
        squareBorderStyle,
        { control = "linebreak" },
        squareBorderWeight,
        { control = "switch", labelSide = "after", label = "Adjust Border Color",
          desc = "Override the default border color for this spell's aura "
              .. "icon. Threshold timer colors will take priority when active.",
          id = "sbAdjustBorderColor", default = false, disabled = "combat",
          hidden = adjustColorHidden,
          get = function()
              local e = borderColorEntry()
              return e ~= nil and e.enabled ~= false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellBorderColors then p.specSpellBorderColors = {} end
              if not p.specSpellBorderColors[kSpec] then p.specSpellBorderColors[kSpec] = {} end
              local e = p.specSpellBorderColors[kSpec][sid]
              if val then
                  if not e then
                      p.specSpellBorderColors[kSpec][sid] = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
                  else
                      e.enabled = nil
                  end
              elseif e then
                  e.enabled = false
              end
              Rebuild()
              PreviewSoon()
              Repaint(ctx)
          end },
        { control = "color", label = "Border Color", alpha = true,
          id = "sbBorderColor", disabled = "combat",
          hidden = function()
              if adjustColorHidden() then return true end
              local e = borderColorEntry()
              return not e or e.enabled == false
          end,
          get = function()
              local c = borderColorEntry() or { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
              return ColorOut(c.r, c.g, c.b, c.a or 1.0)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellBorderColors then p.specSpellBorderColors = {} end
              if not p.specSpellBorderColors[kSpec] then p.specSpellBorderColors[kSpec] = {} end
              if not p.specSpellBorderColors[kSpec][sid] then p.specSpellBorderColors[kSpec][sid] = {} end
              local e = p.specSpellBorderColors[kSpec][sid]
              e.r, e.g, e.b, e.a = v[1], v[2], v[3], v[4]
              Rebuild()
              PreviewSoon()
          end },
    }}

    -- ══════════════════════════════════════════════════════════
    -- ICON EFFECTS
    -- ══════════════════════════════════════════════════════════
    -- One entry table holds every icon effect (Icon Effect + Glow Style +
    -- color, Pandemic + color); Desaturate and Recolor read the same row
    -- from the Icon tab. The old threshold-driven "Glow Border" could never
    -- evaluate its threshold on 12.1 (remaining duration is secret); the
    -- ENGINE-COMPUTED Pandemic Effect is its replacement.
    local iconEffects = {}

    iconEffects[#iconEffects + 1] = { title = "Icon Effect", preset = "form", fields = {
        { control = "dropdown", label = "Icon Effect",
          desc = "An animated effect drawn on this aura's icon while it is shown.",
          options = { { value = "none",  text = "None" },
                      { value = "glow",  text = "Glow" },
                      { value = "ants",  text = "Marching Ants" },
                      { value = "flash", text = "Flash" } },
          id = "sbIconEffect", default = "none", disabled = "combat",
          get = function() return IE_GET().effect or "none" end,
          set = function(_, ctx, val)
              IE_SET(ctx, function(e) e.effect = (val ~= "none") and val or nil end)
          end },
        -- ONLY these two, by design: every other glow style is
        -- OnUpdate-driven, and SetScript is refused on engine-owned aura
        -- buttons and their descendants.
        { control = "dropdown", label = "Glow Style",
          desc = "Steady draws the ring at a constant strength; Pulsing fades "
              .. "it in and out.",
          options = { { value = "steady", text = "Steady" },
                      { value = "pulse",  text = "Pulsing" } },
          id = "sbIconEffectGlowStyle", default = "steady", disabled = "combat",
          hidden = function() return IE_GET().effect ~= "glow" end,
          get = function() return IE_GET().glowStyle or "steady" end,
          set = function(_, ctx, val)
              IE_SET(ctx, function(e) e.glowStyle = (val ~= "steady") and val or nil end)
          end },
        { control = "color", label = "Effect Color", alpha = true,
          desc = "Tint of the effect. For Flash, the alpha sets the pulse's "
              .. "peak strength.",
          id = "sbIconEffectColor", disabled = "combat",
          hidden = function()
              local fx = IE_GET().effect
              return not fx or fx == "none"
          end,
          get = function()
              local c = IE_GET().color or IE_DEFAULT_COLOR
              return ColorOut(c.r or 1, c.g or 0.82, c.b or 0.25, c.a or 1)
          end,
          set = function(_, ctx, v)
              IE_SET(nil, function(e)
                  e.color = { r = v[1], g = v[2], b = v[3], a = v[4] }
              end)
          end },
    }}

    iconEffects[#iconEffects + 1] = { title = "Pandemic Effect", preset = "form", fields = {
        { control = "switch", labelSide = "after", label = "Pandemic Effect",
          desc = "Recolor the icon when the aura reaches its pandemic window "
              .. "(<30% duration). Only applies to auras that have a pandemic "
              .. "refresh window (HoTs and DoTs).",
          id = "sbPandemicEffect", default = false, disabled = "combat",
          get = function() return IE_GET().pandemic == true end,
          set = function(_, ctx, val)
              IE_SET(ctx, function(e) e.pandemic = val or nil end)
          end },
        { control = "color", label = "Pandemic Color", alpha = true,
          id = "sbPandemicColor", disabled = "combat",
          hidden = function() return IE_GET().pandemic ~= true end,
          get = function()
              local c = IE_GET().pandemicColor or IE_DEFAULT_PANDEMIC
              return ColorOut(c.r or 0.239216, c.g or 1, c.b or 0.254902, c.a or 0.15)
          end,
          set = function(_, ctx, v)
              IE_SET(nil, function(e)
                  e.pandemicColor = { r = v[1], g = v[2], b = v[3], a = v[4] }
              end)
          end },
    }}

    -- ══════════════════════════════════════════════════════════
    -- COOLDOWN TEXT
    -- ══════════════════════════════════════════════════════════
    -- sbVisuals.specSpellCooldownText["sb"][sid], with an optional
    -- groupSettings[<layout>] tier under it when "Enable per-Layout Config"
    -- is on. Every widget displays the EFFECTIVE value -- the entry's, then
    -- the global Aura Cooldown Text baseline (BF.AuraCache) -- so the UI and
    -- ResolveSpellCooldownText agree; touching a widget writes an explicit
    -- per-spell value, and untouched fields keep inheriting live.
    local function cdtEntry()
        local p  = SROOT()
        local ct = p.specSpellCooldownText and p.specSpellCooldownText[kSpec]
        return ct and ct[sid]
    end
    local function ensureCdtEntry()
        local p = SROOT()
        if not p.specSpellCooldownText then p.specSpellCooldownText = {} end
        if not p.specSpellCooldownText[kSpec] then p.specSpellCooldownText[kSpec] = {} end
        if not p.specSpellCooldownText[kSpec][sid] then p.specSpellCooldownText[kSpec][sid] = {} end
        return p.specSpellCooldownText[kSpec][sid]
    end
    -- The effective source: the layout tier when per-Layout is on, else
    -- the entry. Returns the source and the entry.
    local function cdtEffective()
        local entry = cdtEntry()
        if not entry then return nil, nil end
        if entry.separateGroupConfig then
            local key = EditingGroupType()
            if not entry.groupSettings then entry.groupSettings = {} end
            if not entry.groupSettings[key] then entry.groupSettings[key] = {} end
            return entry.groupSettings[key], entry
        end
        return entry, entry
    end
    local function cdtWriteTarget()
        local entry = ensureCdtEntry()
        if entry.separateGroupConfig then
            local key = EditingGroupType()
            if not entry.groupSettings then entry.groupSettings = {} end
            if not entry.groupSettings[key] then entry.groupSettings[key] = {} end
            return entry.groupSettings[key], entry
        end
        return entry, entry
    end
    local function cdtField(name)
        local s, entry = cdtEffective()
        if not s then return nil end
        local v = s[name]
        if v == nil and s ~= entry then v = entry[name] end
        return v
    end
    local CDT_BASELINE = {
        showDuration = "showBuffDuration", autoScale = "buffAutoScale",
        timerScale = "buffTimerScale", fontSize = "buffFontSize",
        durationFont = "buffDurationFont", durationBorder = "buffDurationBorder",
        disableSwipe = "disableBuffSwipe", disableSpark = "disableBuffSpark",
        reverseSwipe = "reverseBuffSwipe",
    }
    local function cdtBaseline(name)
        local bf    = BF()
        local acKey = CDT_BASELINE[name]
        local ac    = bf and bf.AuraCache
        local v     = acKey and ac and ac[acKey]
        if v == nil then
            if name == "timerScale"     then return 1.0 end
            if name == "fontSize"       then return 11 end
            if name == "durationBorder" then return "OUTLINE" end
            if name == "showDuration"   then return true end
        end
        return v
    end
    local function cdtEff(name)
        local v = cdtField(name)
        if v == nil then v = cdtBaseline(name) end
        return v
    end
    -- The plain setter: write the field, drop the settings cache, rebuild
    -- the containers on mouse-up (the sliders fire per drag tick).
    local function cdtSet(name)
        return function(_, ctx, val)
            if InCombatLockdown() then return end
            local s = cdtWriteTarget()
            s[name] = val
            local bf = BF()
            if not bf then return end
            if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
            bf:MouseUpOption("acSpellCdtRebuild", function()
                bf:RefreshAllCustomContainersWithRebuild()
            end)
            Repaint(ctx)
        end
    end
    -- The curve setter: a field the expiring-color curves are built from.
    local function cdtCurveSet(name)
        return function(_, ctx, val)
            if InCombatLockdown() then return end
            local s = cdtWriteTarget()
            s[name] = val
            local bf = BF()
            if not bf then return end
            bf:RebuildExpiringColorCurves()
            if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
            bf:RefreshContainersWithRebuildDebounced()
            Repaint(ctx)
        end
    end
    local function cdtEnabledForScope()
        local entry = cdtEntry()
        if not entry then return false end
        if entry.separateGroupConfig then
            local gs = entry.groupSettings and entry.groupSettings[EditingGroupType()]
            if gs then return gs.enabled ~= false end
            return false
        end
        return entry.enabled ~= false
    end
    local function cdtSettingsHidden() return not cdtEnabledForScope() end
    local function durShowOff() return cdtEff("showDuration") == false end
    local function perLayoutOff()
        local entry = cdtEntry()
        return not entry or not entry.separateGroupConfig
    end

    local cooldownText = {}

    cooldownText[#cooldownText + 1] = { preset = "form", fields = {
        { control = "switch", width = "full", labelSide = "after",
          label = "|cff87ceebEnable per-Layout Config|r",
          desc = "Enabling this option will allow you to have different "
              .. "settings for each Layout (e.g. Party vs. Raid) or Custom "
              .. "Frame Group.",
          id = "sbCdtSeparateGroupConfig", default = false, disabled = "combat",
          get = function()
              local entry = cdtEntry()
              return (entry and entry.separateGroupConfig) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local entry = ensureCdtEntry()
              entry.separateGroupConfig = val
              if val and not entry.groupSettings then entry.groupSettings = {} end
              local bf = BF()
              if bf then
                  if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
                  bf:RefreshContainersWithRebuildDebounced()
              end
              Repaint(ctx)
          end },
        { control = "dropdown", label = "Layout/Custom Frame Group",
          desc = "Select which Layout or Custom Frame Group to configure "
              .. "settings for.",
          options = GroupTypeOptions,
          id = "sbCdtEditingGroupType", disabled = "combat",
          hidden = perLayoutOff,
          get = function() return EditingGroupType() end,
          set = function(_, ctx, val)
              spellEditingGroupType = val
              Repaint(ctx)
          end },
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBOverride Aura Cooldown Text Settings|r",
          desc = "When enabled, this spell uses its own duration text, scale, "
              .. "swipe, and spark settings instead of inheriting from the "
              .. "Aura Cooldown Text tab.",
          id = "sbCdtEnabled", default = false, disabled = "combat",
          get = cdtEnabledForScope,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellCooldownText then p.specSpellCooldownText = {} end
              if not p.specSpellCooldownText[kSpec] then p.specSpellCooldownText[kSpec] = {} end
              local isNew = not p.specSpellCooldownText[kSpec][sid]
              if isNew then p.specSpellCooldownText[kSpec][sid] = {} end
              local entry = p.specSpellCooldownText[kSpec][sid]
              if entry.separateGroupConfig then
                  if not entry.groupSettings then entry.groupSettings = {} end
                  local gk = EditingGroupType()
                  if val then
                      if not entry.groupSettings[gk] then
                          entry.groupSettings[gk] = {}
                      else
                          entry.groupSettings[gk].enabled = nil
                      end
                  else
                      if not entry.groupSettings[gk] then
                          entry.groupSettings[gk] = { enabled = false }
                      else
                          entry.groupSettings[gk].enabled = false
                      end
                  end
              else
                  if val then entry.enabled = nil else entry.enabled = false end
              end
              -- Baseline values on first enable, so the widgets match the
              -- inherited runtime behavior.
              local bf = BF()
              if val and isNew and bf and bf.AuraCache then
                  local ac = bf.AuraCache
                  local target = entry
                  if entry.separateGroupConfig then
                      local gk = EditingGroupType()
                      target = (entry.groupSettings and entry.groupSettings[gk]) or entry
                  end
                  if target.showDuration    == nil then target.showDuration    = ac.showBuffDuration ~= false end
                  if target.autoScale       == nil then target.autoScale       = ac.buffAutoScale == true end
                  if target.timerScale      == nil then target.timerScale      = ac.buffTimerScale or 1.0 end
                  if target.fontSize        == nil then target.fontSize        = ac.buffFontSize or 11 end
                  if target.disableSwipe    == nil then target.disableSwipe    = ac.disableBuffSwipe or false end
                  if target.disableSpark    == nil then target.disableSpark    = ac.disableBuffSpark or false end
                  if target.reverseSwipe    == nil then target.reverseSwipe    = ac.reverseBuffSwipe == true end
                  if target.colorAuraBorder == nil then target.colorAuraBorder = ac.buffColorAuraBorder == true end
              end
              if bf then
                  bf:RebuildExpiringColorCurves()
                  if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
                  bf:RefreshContainersWithRebuildDebounced()
              end
              Repaint(ctx)
          end },
    }}

    cooldownText[#cooldownText + 1] = { title = "Cooldown Swipe", preset = "form",
        hidden = cdtSettingsHidden, fields = {
        { control = "switch", labelSide = "after", label = "Disable Cooldown Swipe",
          id = "sbDisableSwipe", default = false, disabled = "combat",
          get = function() return cdtEff("disableSwipe") end,
          set = cdtSet("disableSwipe") },
        { control = "switch", labelSide = "after", label = "Reverse Swipe Direction",
          id = "sbReverseSwipe", default = false, disabled = "combat",
          hidden = function() return cdtEff("disableSwipe") == true end,
          get = function() return cdtEff("reverseSwipe") end,
          set = cdtSet("reverseSwipe") },
        { control = "switch", labelSide = "after", label = "Disable Cooldown Spark",
          id = "sbDisableSpark", default = false, disabled = "combat",
          get = function() return cdtEff("disableSpark") end,
          set = cdtSet("disableSpark") },
    }}

    cooldownText[#cooldownText + 1] = { title = "Duration Text", preset = "form",
        hidden = cdtSettingsHidden, fields = {
        { control = "switch", labelSide = "after", label = "Show Duration Numbers",
          id = "sbShowDuration", default = true, disabled = "combat",
          get = function() return cdtEff("showDuration") end,
          set = cdtSet("showDuration") },
        { control = "switch", labelSide = "after", label = "Auto Scale Duration Text",
          desc = "When enabled, duration text size scales proportionally with "
              .. "the aura icon size. Use the scale slider to fine-tune. When "
              .. "disabled, a fixed font size is used instead.",
          id = "sbAutoScale", default = false, disabled = "combat",
          hidden = durShowOff,
          get = function() return cdtEff("autoScale") end,
          set = cdtSet("autoScale") },
        { control = "slider", label = "Duration Text Scale",
          min = 0.1, max = 3.0, step = 0.1,
          id = "sbTimerScale", default = 1.0, disabled = "combat",
          hidden = function() return durShowOff() or cdtEff("autoScale") ~= true end,
          get = function()
              local bf = BF()
              return cdtField("timerScale")
                  or (bf and bf.AuraCache and bf.AuraCache.buffTimerScale) or 1.0
          end,
          set = cdtSet("timerScale") },
        { control = "slider", label = "Font Size", min = 6, max = 24, step = 1,
          id = "sbFontSize", default = 11, disabled = "combat",
          hidden = function() return durShowOff() or cdtEff("autoScale") == true end,
          get = function() return cdtField("fontSize") or cdtBaseline("fontSize") end,
          set = cdtSet("fontSize") },
        { control = "switch", width = "full", labelSide = "after",
          label = "Hide Duration Text Above 1 Minute",
          desc = "When enabled, the duration text is hidden when the remaining "
              .. "time is above 59 seconds.",
          id = "sbHideDurationAbove1Min", default = false, disabled = "combat",
          hidden = durShowOff,
          get = function() return cdtField("hideDurationAbove1Min") end,
          set = cdtCurveSet("hideDurationAbove1Min") },
    }}

    cooldownText[#cooldownText + 1] = { title = "Font", preset = "form",
        hidden = function() return cdtSettingsHidden() or durShowOff() end, fields = {
        { control = "dropdown", label = "Font",
          id = "sbDurationFont", disabled = "combat",
          options = function()
              local bf  = BF()
              local out = {}
              for name in pairs((bf and bf:LSMFontValues()) or {}) do
                  out[#out + 1] = { value = name, text = name }
              end
              table.sort(out, function(a, b) return a.text < b.text end)
              return out
          end,
          -- The stored or baseline value can be a PATH, so it is normalized
          -- onto a real key on read.
          get = function()
              local bf = BF()
              if not bf then return nil end
              return bf:NormalizeFontName(cdtField("durationFont") or cdtBaseline("durationFont"),
                                          "Roboto Condensed Bold")
          end,
          set = cdtSet("durationFont") },
        { control = "dropdown", label = "Font Border", options = FONT_BORDER_OPTIONS,
          id = "sbDurationBorder", disabled = "combat",
          get = function()
              local v = cdtField("durationBorder")
              if v == nil then v = cdtBaseline("durationBorder") end
              return v or ""
          end,
          set = cdtSet("durationBorder") },
    }}

    local function cdtColorSet(name, keepAlpha)
        return function(_, ctx, v)
            if InCombatLockdown() then return end
            local s = cdtWriteTarget()
            if keepAlpha then
                s[name] = { r = v[1], g = v[2], b = v[3], a = v[4] }
            else
                s[name] = { r = v[1], g = v[2], b = v[3] }
            end
            CooldownTextRefreshSoon()
        end
    end
    local function cdtThresholdOff()  return not cdtField("thresholdColorEnabled") end
    local function cdtThreshold2Off() return cdtThresholdOff() or not cdtField("threshold2ColorEnabled") end

    cooldownText[#cooldownText + 1] = { title = "Duration Numbers Color", preset = "form",
        hidden = function() return cdtSettingsHidden() or durShowOff() end, fields = {
        { control = "color", label = "Duration Text Color", alpha = true,
          desc = "Color of the duration timer text. When Threshold Color is "
              .. "enabled, this is the color used above the threshold.",
          id = "sbFontColor", disabled = "combat",
          get = function()
              local s, entry = cdtEffective()
              local bf = BF()
              if not s then return ColorOut(1, 1, 1, 1) end
              local col = s.fontColor or (s ~= entry and entry.fontColor)
                  or (bf and bf.AuraCache and bf.AuraCache.buffFontColor)
                  or { r = 1, g = 1, b = 1 }
              return ColorOut(col.r, col.g, col.b, 1)
          end,
          set = cdtColorSet("fontColor", false) },
        -- colorAuraBorder ("Also Color Aura Borders") is deliberately absent:
        -- duration-driven border color has no container expression.
        { control = "switch", width = "full", labelSide = "after",
          label = "Change Color based on Remaining Time",
          id = "sbThresholdColorEnabled", default = false, disabled = "combat",
          get = function() return cdtField("thresholdColorEnabled") end,
          set = cdtCurveSet("thresholdColorEnabled") },
        { control = "color", label = "Threshold Color", alpha = true,
          id = "sbCdtThresholdColor", disabled = "combat", hidden = cdtThresholdOff,
          get = function()
              local s, entry = cdtEffective()
              local bf = BF()
              local dc = (bf and bf.DEFAULT_THRESHOLD_COLOR) or { r = 1, g = 0.5, b = 0, a = 1 }
              if not s then return ColorOut(dc.r, dc.g, dc.b, dc.a or 1) end
              local col = s.thresholdColor or (s ~= entry and entry.thresholdColor) or dc
              return ColorOut(col.r, col.g, col.b, col.a or 1)
          end,
          set = cdtColorSet("thresholdColor", true) },
        { control = "slider", label = "Threshold (seconds)", min = 1, max = 59, step = 1,
          id = "sbCdtThreshold", default = 8, disabled = "combat", hidden = cdtThresholdOff,
          get = function()
              local s, entry = cdtEffective()
              if not s then return 8 end
              local v = s.thresholdColorThreshold
              if v == nil and s ~= entry then v = entry.thresholdColorThreshold end
              return v or 8
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = cdtWriteTarget()
              s.thresholdColorThreshold = val
              -- Keep the secondary threshold below the primary.
              local t2 = s.threshold2ColorThreshold
              if t2 and t2 >= val then
                  s.threshold2ColorThreshold = math.max(1, val - 1)
              end
              CooldownTextRefreshSoon()
          end },
        { control = "switch", width = "full", labelSide = "after",
          label = "Enable Secondary Threshold",
          id = "sbThreshold2ColorEnabled", default = false, disabled = "combat",
          hidden = cdtThresholdOff,
          get = function() return cdtField("threshold2ColorEnabled") end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s, entry = cdtWriteTarget()
              s.threshold2ColorEnabled = val
              -- Store the seconds the slider is SHOWING on first enable, so
              -- the displayed value -- not the resolver's fallback -- decides
              -- when the color flips.
              if val and s.threshold2ColorThreshold == nil
                 and (s == entry or entry.threshold2ColorThreshold == nil) then
                  local t1 = s.thresholdColorThreshold
                      or (s ~= entry and entry.thresholdColorThreshold) or 8
                  s.threshold2ColorThreshold = math.min(4, math.max(1, t1 - 1))
              end
              local bf = BF()
              if bf then
                  bf:RebuildExpiringColorCurves()
                  if bf.InvalidateContainerSettingsCache then bf.InvalidateContainerSettingsCache() end
                  bf:RefreshContainersWithRebuildDebounced()
              end
              Repaint(ctx)
          end },
        { control = "color", label = "Secondary Threshold Color", alpha = true,
          id = "sbCdtThreshold2Color", disabled = "combat", hidden = cdtThreshold2Off,
          get = function()
              local s, entry = cdtEffective()
              local bf = BF()
              local dc = (bf and bf.DEFAULT_THRESHOLD2_COLOR) or { r = 1, g = 0, b = 0, a = 1 }
              if not s then return ColorOut(dc.r, dc.g, dc.b, dc.a or 1) end
              local col = s.threshold2Color or (s ~= entry and entry.threshold2Color) or dc
              return ColorOut(col.r, col.g, col.b, col.a or 1)
          end,
          set = cdtColorSet("threshold2Color", true) },
        { control = "slider", label = "Secondary Threshold (seconds)",
          min = 1, max = 58, step = 1,
          id = "sbCdtThreshold2", default = 4, disabled = "combat", hidden = cdtThreshold2Off,
          get = function()
              local s, entry = cdtEffective()
              if not s then return 4 end
              local t2 = s.threshold2ColorThreshold or (s ~= entry and entry.threshold2ColorThreshold) or 4
              local t1 = s.thresholdColorThreshold  or (s ~= entry and entry.thresholdColorThreshold)  or 8
              return math.min(t2, math.max(1, t1 - 1))
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s, entry = cdtWriteTarget()
              local t1 = s.thresholdColorThreshold or (s ~= entry and entry.thresholdColorThreshold) or 8
              s.threshold2ColorThreshold = math.min(val, math.max(1, t1 - 1))
              CooldownTextRefreshSoon()
          end },
    }}

    -- ══════════════════════════════════════════════════════════
    -- FRAME EFFECTS
    -- ══════════════════════════════════════════════════════════
    -- What the unit FRAME does while this buff is on the unit: a health
    -- bar tint, a frame border, an overlay. Three families, one entry each.
    local function specColors()
        local p = SROOT()
        if not p.specSpellColors then p.specSpellColors = {} end
        if not p.specSpellColors[kSpec] then p.specSpellColors[kSpec] = {} end
        return p.specSpellColors[kSpec]
    end
    local function colorOff()
        local e = specColors()[sid]
        return not e or e.enabled == false
    end
    local function borderEntry()
        local p = SROOT()
        return p.specSpellBorders and p.specSpellBorders[kSpec] and p.specSpellBorders[kSpec][sid]
    end
    local function borderOff()
        local e = borderEntry()
        return not e or e.enabled == false
    end
    local function overlayEntry()
        local p = SROOT()
        return p.specSpellOverlays and p.specSpellOverlays[kSpec] and p.specSpellOverlays[kSpec][sid]
    end
    local function overlayOff()
        local e = overlayEntry()
        return not e or e.enabled == false
    end
    local function overlayHorizontal()
        local s = overlayEntry()
        local d = s and s.gradientDir
        return d == "leftToRight" or d == "rightToLeft"
    end

    local frameEffects = {}

    frameEffects[#frameEffects + 1] = { title = "Buff Health Bar Color", preset = "form", fields = {
        { control = "switch", labelSide = "after", label = "Change Health Color",
          desc = "Tint this unit's health bar when they have this spell active.",
          id = "sbColorEnabled", default = false, disabled = "combat",
          get = function() return not colorOff() end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local sc = specColors()
              if val then
                  if not sc[sid] then
                      sc[sid] = { r = 0.0, g = 1.0, b = 0.5, priority = false }
                  else
                      sc[sid].enabled = nil
                  end
              elseif sc[sid] then
                  sc[sid].enabled = false
              end
              local bf = BF()
              if bf then bf:InvalidateSpellColorCache() end
              Rebuild()
              Repaint(ctx)
          end },
        { control = "color", label = "Color", alpha = true,
          id = "sbColor", disabled = "combat", hidden = colorOff,
          get = function()
              local c = specColors()[sid] or { r = 0.0, g = 1.0, b = 0.5, a = 1 }
              return ColorOut(c.r, c.g, c.b, c.a or 1)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local sc = specColors()
              if not sc[sid] then sc[sid] = {} end
              sc[sid].r, sc[sid].g, sc[sid].b, sc[sid].a = v[1], v[2], v[3], v[4]
              local bf = BF()
              if bf then
                  if bf.activeFrames then
                      for frame in pairs(bf.activeFrames) do
                          if frame.buffColorOverlay then frame.buffColorOverlay:Hide() end
                      end
                  end
                  bf:InvalidateSpellColorCache()
              end
              Rebuild()
          end },
        { control = "switch", labelSide = "after", label = "Prioritise Over Debuff Recolor",
          desc = "When both this buff health color and the dispel health color "
              .. "would show, this buff color renders above the dispel recolor.",
          id = "sbColorPriority", default = false, disabled = "combat", hidden = colorOff,
          get = function()
              local s = specColors()[sid]
              return (s and s.priority) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local sc = specColors()
              if sc[sid] then sc[sid].priority = val end
              Rebuild()
          end },
    }}

    frameEffects[#frameEffects + 1] = { title = "Buff Frame Border", preset = "form", fields = {
        { control = "switch", labelSide = "after", label = "Show Border When Active",
          desc = "Show a colored border around the unit frame when this buff is active.",
          id = "sbBuffBorderEnabled", default = false, disabled = "combat",
          get = function() return not borderOff() end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellBorders then p.specSpellBorders = {} end
              if not p.specSpellBorders[kSpec] then p.specSpellBorders[kSpec] = {} end
              local e = p.specSpellBorders[kSpec][sid]
              if val then
                  if not e then
                      p.specSpellBorders[kSpec][sid] = { color = { r = 0, g = 1, b = 0 }, priority = false }
                  else
                      e.enabled = nil
                  end
              elseif e then
                  e.enabled = false
              end
              Rebuild()
              Repaint(ctx)
          end },
        { control = "color", label = "Border Color", alpha = true,
          id = "sbBuffBorderColor", disabled = "combat", hidden = borderOff,
          get = function()
              local s = borderEntry()
              local c = (s and s.color) or { r = 0, g = 1, b = 0, a = 1 }
              return ColorOut(c.r, c.g, c.b, c.a or 1)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local s = borderEntry()
              if s then s.color = { r = v[1], g = v[2], b = v[3], a = v[4] } end
              Rebuild()
          end },
        { control = "slider", label = "Border Thickness", min = 1, max = 5, step = 1,
          desc = "Thickness of the buff border in pixels. Applies only to this spell's border.",
          id = "sbBuffBorderThickness", default = 2, disabled = "combat", hidden = borderOff,
          get = function()
              local bf = BF()
              local s  = borderEntry()
              return (s and s.thickness)
                  or (bf and bf.db and bf.db.profile and bf.db.profile.buffBorderWidth) or 2
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = borderEntry()
              if s then s.thickness = val end
              Rebuild()
              local bf = BF()
              if bf then
                  bf:MouseUpOption("acPanelPreviewNotify", function()
                      if bf.RefreshPreviewLayout     then bf:RefreshPreviewLayout()     end
                      if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
                  end)
              end
          end },
        { control = "switch", labelSide = "after", label = "Prioritise Over Debuff Border",
          desc = "When both buff and debuff borders would show, this buff border "
              .. "takes priority and hides the debuff border.",
          id = "sbBuffBorderPriority", default = false, disabled = "combat", hidden = borderOff,
          get = function()
              local s = borderEntry()
              return (s and s.priority) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = borderEntry()
              if s then s.priority = val end
              Rebuild()
          end },
    }}

    frameEffects[#frameEffects + 1] = { title = "Buff Overlay", preset = "form", fields = {
        { control = "switch", labelSide = "after", label = "Show Overlay When Active",
          desc = "Show a colored gradient overlay on the health bar when this buff is active.",
          id = "sbBuffOverlayEnabled", default = false, disabled = "combat",
          get = function() return not overlayOff() end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local p = SROOT()
              if not p.specSpellOverlays then p.specSpellOverlays = {} end
              if not p.specSpellOverlays[kSpec] then p.specSpellOverlays[kSpec] = {} end
              local e = p.specSpellOverlays[kSpec][sid]
              if val then
                  if not e then
                      p.specSpellOverlays[kSpec][sid] = {
                          color = { r = 0, g = 1, b = 0, a = 0.5 }, style = "gradient",
                          height = 0.7, width = 0.7, fillOnly = false, priority = false }
                  else
                      e.enabled = nil
                  end
              elseif e then
                  e.enabled = false
              end
              Rebuild()
              Repaint(ctx)
          end },
        -- Alpha lives in the color; the old "Overlay Opacity" slider is
        -- gone, and existing profiles' `alpha` still reads.
        { control = "color", label = "Overlay Color", alpha = true,
          id = "sbBuffOverlayColor", disabled = "combat", hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              local c = (s and s.color) or { r = 0, g = 1, b = 0 }
              return ColorOut(c.r, c.g, c.b, (c.a or (s and s.alpha) or 0.5))
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then
                  s.color = { r = v[1], g = v[2], b = v[3], a = v[4] }
                  s.alpha = nil
              end
              Rebuild()
          end },
        { control = "dropdown", label = "Overlay Style",
          desc = "Solid fills the overlay evenly in the chosen color. Gradient "
              .. "fades it out along the Gradient Direction.",
          options = { { value = "solid",    text = "Solid" },
                      { value = "gradient", text = "Gradient" } },
          id = "sbBuffOverlayStyle", default = "gradient", disabled = "combat", hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              return (s and s.style) or "gradient"
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then s.style = val end
              Rebuild()
              Repaint(ctx)
          end },
        -- Stays visible for Solid: it also picks the edge the overlay is
        -- anchored to, so the size slider always eats into the far end.
        { control = "dropdown", label = "Gradient Direction",
          desc = "Direction the overlay fades, and the edge it is anchored to. "
              .. "The overlay grows away from that edge, so Solid overlays use "
              .. "this purely as an anchor. With Map to Remaining Duration "
              .. "enabled, the bar also drains along this axis, retreating "
              .. "toward the anchored edge.",
          options = { { value = "bottomToTop", text = "Bottom to Top" },
                      { value = "topToBottom", text = "Top to Bottom" },
                      { value = "leftToRight", text = "Left to Right" },
                      { value = "rightToLeft", text = "Right to Left" } },
          id = "sbBuffOverlayGradientDir", default = "topToBottom", disabled = "combat",
          hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              return (s and s.gradientDir) or "topToBottom"
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then s.gradientDir = val end
              Rebuild()
              -- A re-RENDER, not a refresh: two labels below read the
              -- direction (Width/Height), and labels are laid out, not
              -- painted.
              if ctx and ctx.app then ctx.app:RenderPage() end
          end },
        { control = "switch", width = "full", labelSide = "after",
          label = function()
              return overlayHorizontal() and "Map Width to Remaining Duration"
                                         or  "Map Height to Remaining Duration"
          end,
          desc = "When enabled, the overlay drains along the gradient direction "
              .. "with the remaining buff duration as a percentage of total "
              .. "duration. The Overlay Height/Width slider is unused while this "
              .. "is active -- the overlay spans the whole bar and drains from "
              .. "there.",
          id = "sbBuffOverlayDurationMap", default = false, disabled = "combat",
          hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              return (s and s.durationMap) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then s.durationMap = val end
              Rebuild()
              Repaint(ctx)
          end },
        -- One slider, two meanings: a horizontal direction sizes the
        -- overlay across the bar (`width`), a vertical one down it
        -- (`height`). Separate keys, so flipping direction keeps both.
        { control = "slider",
          label = function()
              return overlayHorizontal() and "Overlay Width" or "Overlay Height"
          end,
          min = 0.1, max = 1.0, step = 0.05, isPercent = true,
          id = "sbBuffOverlaySize", default = 0.7, disabled = "combat",
          hidden = function()
              local s = overlayEntry()
              if not s or s.enabled == false then return true end
              return s.durationMap and true or false
          end,
          get = function()
              local s = overlayEntry()
              if not s then return 0.7 end
              if overlayHorizontal() then return s.width or 0.7 end
              return s.height or 0.7
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then
                  if overlayHorizontal() then s.width = val else s.height = val end
              end
              -- Coalesced to the end of the drag: each tick would otherwise
              -- force a full container rebuild.
              local bf = BF()
              if bf then
                  bf:MouseUpOption("acOverlaySize", function()
                      bf:RefreshAllCustomContainersWithRebuild()
                  end)
              end
          end },
        { control = "switch", labelSide = "after", label = "Health Fill Only",
          desc = "Overlay covers only the filled portion of the health bar "
              .. "instead of the full width.",
          id = "sbBuffOverlayFillOnly", default = false, disabled = "combat", hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              return (s and s.fillOnly) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then s.fillOnly = val end
              Rebuild()
          end },
        { control = "switch", labelSide = "after", label = "Prioritise Over Debuff Overlay",
          desc = "When both buff and debuff overlays would show, this buff "
              .. "overlay takes priority and hides the debuff overlay.",
          id = "sbBuffOverlayPriority", default = false, disabled = "combat", hidden = overlayOff,
          get = function()
              local s = overlayEntry()
              return (s and s.priority) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local s = overlayEntry()
              if s then s.priority = val end
              Rebuild()
          end },
    }}

    return {
        icon         = icon,
        iconEffects  = iconEffects,
        cooldownText = cooldownText,
        frameEffects = frameEffects,
    }
end

-- TRUE while the entry is a Square colored by remaining time: the duration
-- text IS the square then (font, format and curve owned by the render
-- path), so the Cooldown Text tab has nothing to apply and is not offered.
-- Read from the RECORD rather than through a store, because the Buff List
-- asks this when it mints the entry's tab routes, before any page exists.
function BuzzardFramesOptions.SingleBuffSquareColorByDuration(c, sid)
    local root = type(c) == "table" and c.sbVisuals
    if not (root and sid) then return false end
    local it = root.specSpellIconType and root.specSpellIconType[SB_KSPEC]
               and root.specSpellIconType[SB_KSPEC][sid]
    if it ~= "Square" and it ~= "BorderedSquare" and it ~= "SquareDuration" then
        return false
    end
    local e = root.specSpellSolidIcons and root.specSpellSolidIcons[SB_KSPEC]
              and root.specSpellSolidIcons[SB_KSPEC][sid]
    return (e and e.thresholdEnabled) and true or false
end
