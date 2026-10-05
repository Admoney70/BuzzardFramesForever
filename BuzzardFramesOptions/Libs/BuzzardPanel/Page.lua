-- ============================================================
-- BuzzardPanel: Page.lua
-- Group presets, the field-grid layout engine, and page rendering.
--
-- A page is a list of GROUPS; a group is a list of FIELDS. The group
-- preset owns container concerns -- color, padding, spacing, how many
-- fields may share a row. Each field owns what control it is and how
-- many cells it needs. Those two layers never reach into each other.
--
-- Layout is a FLOW, not a fixed grid. There is no column count: every
-- control declares a natural width for its own kind plus an allowance for
-- its label, and fields are packed onto a line until the next one will not
-- fit at its MINIMUM width. So a row of switches packs tightly and a row of
-- sliders does not, without either being configured.
--
-- A line that overflows shrinks its fields toward their minimums in
-- proportion to the slack each one has -- never below the minimum, which is
-- what stops a control being shaved. A line with room left over stretches
-- only the controls that benefit from width (sliders, dropdowns, edit
-- boxes); a switch stays switch-sized however much space is going spare.
-- ============================================================
local ADDON, ns = ...

ns.page = {}

ns.groupPresets = {
    default = {
        -- No colors at all: the default card takes them from the SKIN
        -- (groupHeaderBg / groupBg / groupBorder / groupHeading /
        -- groupLabel), so one panel-wide setting moves every card. A preset
        -- that wants to differ states its own, and then the skin does not
        -- reach it -- which is exactly how `strip` and `bare` differ.
        --
        -- Every read of these goes through PresetColor below, so "unset
        -- means ask the skin" is one rule in one place rather than five
        -- fallbacks scattered through the render.
        -- Point sizes for the card's heading and its field labels. Both are
        -- a step up from GameFontNormalSmall's 10, which is legible but
        -- reads as fine print on a panel this size. nil leaves the font
        -- object's own size alone.
        headerSize = 12,
        labelSize  = 11,
        -- The heading with no background or border of its own: the house
        -- default (the "bar" and "tab" shapes remain available per preset).
        headerShape = "plain",
        radius     = 8,
        padding    = 11,
        -- The bottom pad is smaller than the top one on purpose: above the
        -- first row there is a header butting against it, below the last
        -- there is only the card's edge, and matching them leaves a card
        -- looking bottom-heavy.
        padBottom  = 7,
        headerH    = 22,
        gapX       = 12,
        gapY       = 9,
        labelPlacement = "above",   -- above | left
        justify    = "fill",        -- fill: stretch a line to the full width
                                    -- start: leave the remainder empty
        maxPerRow  = nil,           -- optional hard cap; nil = as many as fit
        minRowFill = 0.55,          -- a field may not be stretched past this
                                    -- fraction of the row on its own
        -- WHERE A LINE BREAKS, and so how wide the fields on it end up.
        --
        --   min   as many fields as will fit at their MINIMUM widths, then
        --         everything on the line is shrunk to make them fit. The
        --         densest packing, and the reason a five-field row and a
        --         two-field row came out with controls of different widths:
        --         the five-field row was squeezed, the two-field one was not.
        --
        --   pref  a field starts a new line as soon as it will not fit at
        --         its PREFERRED width. Nothing is ever squeezed, so every
        --         control of a kind is the same width on every row -- which
        --         is what a form wants, and what classic options dialogs do.
        wrapOn     = "min",
    },
}

-- A flat bar rather than a card: one row of fields with its own surface and
-- a border, no heading, labels beside their controls instead of above them,
-- and the first field held at the left while the rest go to the right edge.
--
-- It is the shape a section's META row wants -- "configure this per layout,
-- and while you are at it, which layout, and copy it where" -- which is
-- about the settings rather than one of them, and so should not look like
-- another group of settings.
ns.groupPresets.strip = {
    headerBg   = { 0, 0, 0, 0 },
    -- The mockup's rail-hi, #201e1b: a shade LIGHTER than the page, which
    -- is what lifts the band off it without giving it a card's border.
    bodyBg     = { 0.125, 0.118, 0.106, 1.00 },
    -- #33302a, the divider color -- NOT the cards' brighter #413d34. A
    -- card's border encloses it and has to hold its own against the page;
    -- a band's two rules only have to say where it starts and stops, and at
    -- the cards' weight they read as a box that forgot its sides.
    border     = { 0.200, 0.188, 0.165, 1.00 },
    -- A rule top and bottom instead of a ring: a band across the page, not
    -- a rounded box sitting on it.
    dividers   = true,
    headerFg   = { 0.980, 0.975, 0.965, 1.00 },
    labelFg    = { 0.93, 0.92, 0.90, 1.00 },
    headerSize = 12,
    labelSize  = 11,
    radius     = 0,
    padding    = 7,
    padBottom  = 7,
    headerH    = 22,
    gapX       = 8,
    gapY       = 6,
    labelPlacement = "left",
    justify    = "spread",
    maxPerRow  = nil,
    minRowFill = 0.55,
}

-- A card's color: the preset's own if it states one, the skin's otherwise.
--
-- Group colors live in the SKIN so the whole panel moves together, and a
-- preset overrides only where it means to. The mapping is explicit rather
-- than by name-mangling, so reading it tells you the whole story.
local PRESET_SKIN_TOKEN = {
    headerBg = "groupHeaderBg",
    bodyBg   = "groupBg",
    border   = "groupBorder",
    headerFg = "groupHeading",
    labelFg  = "groupLabel",
}

function ns.PresetColor(preset, skin, key)
    local c = preset and preset[key]
    if c then return c end
    local token = PRESET_SKIN_TOKEN[key]
    return (token and skin and skin[token]) or { 1, 1, 1, 1 }
end

-- ── Field metrics ──────────────────────────────────────────────
-- How wide a field WANTS to be, and how narrow it can go.
--
-- This is the heart of the layout. There is no fixed column count: each
-- control declares a natural width for its own kind (a switch is small, a
-- slider is not), plus an allowance for its label, and the packer fits as
-- many as will go on a line. A field can override with `width`:
--
--     width = "full"    the whole row
--     width = "half"    half the row
--     width = 0.33      a fraction of the row
--     width = 180       exact pixels
--
-- Or as a MULTIPLE of the control's own default width, which is what the
-- classic `width` means:
--
--     widthMul = 0.5    half a normal one of these
--     widthMul = 1.5    half again
--     widthMul = 2      twice
--
-- Kept as its own key because `width` here already means the ROW's width --
-- a fraction of it, or a pixel count -- and a field saying `width = 2` means
-- two pixels, not two controls. The multiplier is of whatever the control
-- measures for itself, so a 2x slider and a 2x stepper are each twice their
-- own kind rather than both landing on some shared number.
--
-- And `newRow = true` starts a fresh line before the field, for a boundary
-- the widths do not imply. See PackLines.
--
-- Anything omitted uses the control's own default, which is what makes a
-- row of toggles pack tightly while a row of sliders does not.
-- The line a label above its control occupies. Named because THREE places
-- have to agree about it -- the measure that adds it to a field's height,
-- the placement that drops the control by it, and the row alignment that
-- lines those labels up -- and a fourth place spelling out 14 is how they
-- stop agreeing.
-- 12, not 14. The font's line box carries leading above and below the
-- glyphs, so the label's own height overstates how much room its TEXT needs
-- -- and every labeled field paid the difference between its caption and
-- its control. The label is anchored by its top and draws at its natural
-- height, so trimming this moves the control up rather than clipping the
-- text; below about 11 a descender would start to meet the control.
local LABEL_H = 12

-- Roughly how wide a label DRAWS.
--
-- Character count times a per-character estimate, which is what this was --
-- plus the two escape sequences that draw as a picture rather than as text:
--
--     |A:atlas:h:w|a     an atlas, sized in the sequence
--     |T path:h:w...|t   a texture, likewise
--
-- Each is ~40 characters and draws as twelve pixels, so counting them as
-- text asked for a thousand pixels for four glyphs -- and any field with an
-- icon in its label had to be given a hand-measured `width` instead of
-- sizing itself. Color codes (|cffffffff ... |r) are dropped for the same
-- reason: they draw as nothing at all.
--
-- An ESTIMATE, deliberately. The real width is only knowable from a
-- FontString that has the text and the font, and measure runs before any
-- widget exists.
function ns.TextWidth(text)
    if type(text) ~= "string" then return 0 end
    local w = 0
    -- Icons: take the width the sequence declares (the last number), or the
    -- height when it names only one.
    for h, wd in text:gmatch("|[AT][^|]-:(%d+):?(%d*)") do
        w = w + (tonumber(wd) or tonumber(h) or 12)
    end
    local plain = text:gsub("|[AT][^|]-|[at]", "")     -- icons, counted above
                      :gsub("|c%x%x%x%x%x%x%x%x", "")  -- color on
                      :gsub("|r", "")                  -- color off
    return w + #plain * 6.2
end

-- ── The line break ─────────────────────────────────────────────
--
--     { control = "linebreak" }
--
-- A mark in a group's field list that ends the row. Not a field: it builds
-- nothing, measures nothing and holds no value, and a page that never uses
-- one pays a single table read per field for the question.
--
-- The other half of the same idea is `newRow = true` on a field, which says
-- the same thing from the other side -- "this one starts a row". Which
-- reads better depends on whose property the break is: a field that must
-- head its own row says `newRow`; a break that belongs to the space
-- BETWEEN two runs of fields is a linebreak, and does not make the field
-- after it responsible for a decision about the field before it.
--
-- Neither is a width. `width = "full"` says a control wants the whole row
-- and ends one as a consequence; using it to get a break gives a 28px
-- switch a row-wide cell to say so, and the two intentions then cannot be
-- told apart by anyone reading the page later.
function ns.IsLineBreak(field)
    return field ~= nil and field.control == "linebreak"
end

-- A real measurement for `width = "fit"`: one hidden FontString, in the
-- panel's live face (ns.FS registers it for re-facing), at the size the
-- field will draw at -- 12, the note default, when the field names none.
local fitFS
local function FitTextWidth(text, size)
    if not fitFS then
        fitFS = ns.FS(UIParent, "BACKGROUND", "GameFontNormalSmall")
        fitFS:Hide()
    end
    ns.SetFontSize(fitFS, size or 12)
    fitFS:SetText(text or "")
    return fitFS:GetStringWidth() or 0
end

local function FieldMetrics(def, field, preset, contentW, ctx)
    -- A width OVERRIDE is absolute -- a fraction of the row, or a pixel
    -- count -- so it is known before anything is measured, and a control
    -- whose height depends on its width has to be measured at the width it
    -- will actually get. Measuring a note at the row's width and then
    -- laying it out at 320 is how a note that wraps to two lines is given
    -- the space for one and draws over the row under it.
    local forced
    local wOverride = field.width
    if wOverride == "full" then
        -- Asked for outright: the whole row, whatever the control is.
        forced = contentW
    elseif wOverride == "fit" then
        -- The field's own single-line width, capped to the row. For a
        -- NOTE this is the way to sit in a row beside other fields: with
        -- no width a note takes the whole row and pushes its row mates to
        -- a second line, and a fixed number wraps the text the moment the
        -- face or the wording outgrows it -- "fit" asks for exactly what
        -- the words measure. MEASURED, not counted (ns.TextWidth is a
        -- per-character estimate): the hidden string wears the panel face
        -- of the moment, so a font toggle re-fits on the next render.
        local t = field.text or ns.FieldLabel(field)
        if type(t) == "function" then t = t(field, ctx) end
        if type(t) == "string" then
            forced = math.min(contentW, FitTextWidth(t, field.fontSize) + 8)
        else
            forced = contentW
        end
    elseif field.wide then
        -- `wide` is the control's to interpret. Most take the row; a switch
        -- takes a control's width (see switch.wideWidth), because it is
        -- marked wide for its LABEL and a full row for a 28px toggle is a
        -- row of nothing.
        forced = math.min(def.wideWidth or contentW, contentW)
    elseif wOverride == "half" then
        forced = (contentW - preset.gapX) / 2
    elseif type(wOverride) == "number" then
        forced = (wOverride <= 1) and (contentW * wOverride) or wOverride
    end

    -- measure gets the width it will be laid out in. Most controls ignore
    -- it -- their height is fixed -- but anything whose height depends on
    -- wrapping needs it, and cannot be measured without it.
    --
    -- It gets ctx as well, for the same reason apply and refresh do: a field
    -- whose content is COMPUTED cannot be measured without the means to
    -- compute it. Every other control ignores the argument.
    local prefW, minW, h = def.measure(field, math.min(forced or contentW, contentW), ctx)
    local stretch = def.stretch
    if stretch == nil then stretch = false end
    -- The control's OWN width, before any label allowance. Placement needs
    -- it: the label's share of a cell is whatever is left after the control
    -- has taken its own, and computing that from the same estimate twice --
    -- once here, once there -- is how a shrunk cell ended up with a label
    -- drawn across its switch.
    local ctlW = prefW

    -- A multiple of the control's OWN width. Resolved here rather than with
    -- the overrides above because it needs the measure first -- the natural
    -- width is the thing being multiplied -- and a control whose height
    -- follows its width is re-measured at the result.
    if field.widthMul then
        forced = math.max(24, math.min(contentW, ctlW * field.widthMul))
        local _, _, h2 = def.measure(field, forced, ctx)
        if h2 then h = h2 end
    end

    -- A field may override the preset: a strip whose switch reads inline
    -- can still carry dropdowns labeled above them.
    local placement = field.labelPlacement or preset.labelPlacement

    -- Label allowance. Above the control the label must fit the same
    -- width; beside it, the label adds to the width.
    -- Resolved once here and reused: a label may be a FUNCTION, and
    -- calling it three times per measure to ask the same question is both
    -- wasteful and a way for the three answers to disagree mid-layout.
    -- A control that draws its OWN caption (a button) gets no separate
    -- label: not measured for one here, not counted as a label line by the
    -- row alignment, and not drawn by the placement. Asked of the CONTROL
    -- rather than of the field, so a caller cannot forget.
    local labelText = (not def.ownLabel) and ns.FieldLabel(field) or nil
    local labelW = labelText and (ns.TextWidth(labelText) + 10) or 0
    if labelText then
        if placement == "left" then
            -- The 140 cap is for a label in the LEFT COLUMN: a column
            -- heading, one of many, and a page of them has to stay a grid
            -- rather than let the longest one set every row's width.
            --
            -- A label drawn AFTER its control is not that. It is the
            -- field's own text -- "[switch] Use global duration text
            -- config for all aura types" reads as one sentence -- so
            -- capping it cut the sentence in half. It asks for what it
            -- needs; the packer still squeezes it toward the minimum when
            -- the row cannot pay.
            local after = (field.labelSide == "after")
            local lw = after and labelW or math.min(labelW, 140)
            prefW = prefW + lw + 8
            minW  = minW + math.min(lw, after and 200 or 80) + 8
        else
            prefW = math.max(prefW, labelW)
            minW  = math.max(minW, math.min(labelW, 130))
            h = h + LABEL_H
        end
    end

    -- A COLUMN width, which is not the same thing as a width.
    --
    -- `width` forces the CONTROL: a field that asks for 180 gets a 180-wide
    -- control, and its label takes whatever is left of the cell. That is
    -- wrong for a grid of toggles -- a switch is 28px whatever column it
    -- sits in, and forcing the control to the column width leaves the label
    -- nothing and hides it.
    --
    -- `cellWidth` forces the CELL instead: the control keeps its natural
    -- width, the label takes the remainder, and every row's columns start
    -- at the same x -- which is what makes a page of class rows read as a
    -- grid rather than as ragged lines. Pixels, or a fraction of the row.
    if field.cellWidth then
        local cw = (field.cellWidth <= 1) and (contentW * field.cellWidth)
                   or field.cellWidth
        cw = math.min(cw, contentW)
        -- Not stretchy: a field that named its column has one, and the
        -- packer must not hand it more.
        prefW, minW, stretch = cw, cw, false
    end

    -- The same override, applied. Resolved once above, so the width the
    -- field is measured at and the width it is given cannot disagree.
    --
    -- `ctlW` moves with it: a field that asks for 180 means the CONTROL is
    -- 180, and placement draws a non-stretchy control at ctlW -- so leaving
    -- it at the measured width would quietly ignore the override.
    if forced then
        local cell = forced
        -- `wide` on a switch resolves to a CONTROL's width, because a full
        -- row for a 28px toggle is a row of nothing (switch.wideWidth).
        -- But the REASON a switch is marked wide is that its label is long
        -- -- and clamping the cell to the control cut that label off at
        -- exactly the width the field was widened to avoid. "Change Color
        -- based on Remaining Time" measures over 200 and was being given
        -- 150 to draw in.
        --
        -- So a `wide` field with no outright `width` takes whichever is
        -- larger, its control's wide width or what its label needs, capped
        -- at the row. An explicit `width` is still absolute: a field that
        -- named a number gets that number.
        if field.wide and wOverride == nil and labelText then
            local need = (placement == "left")
                         and (ctlW + labelW + 8) or labelW
            cell = math.min(contentW, math.max(forced, need))
        end
        if wOverride == "full" or field.wide then
            -- Not stretchy either way: a field that asked for a width has
            -- one, and the packer must not hand it more.
            prefW, minW, stretch = cell, cell, false
        else
            prefW = forced
            minW  = math.min(minW, prefW)
        end
        -- A WIDTH SIZES THE CELL. It does not size a control that has a
        -- width of its own.
        --
        -- `def.wideWidth` is a control saying "this is how wide I am,
        -- whatever you give me" -- a switch is a 36-pixel pill and nothing
        -- makes it wider. Handing such a control the whole cell leaves its
        -- LABEL nothing, and the placement pass below drops a label it
        -- cannot fit: `width = "full"` on a labeled toggle drew a toggle
        -- and no words at all, which is not a reading of "full" anybody
        -- intended. It is also unfalsifiable from the declaration -- the
        -- label is right there in the field -- so the library has to be the
        -- one that refuses to lose it.
        --
        -- So the control keeps its own width whenever it has one and there
        -- is a label beside it to spend the rest on; the cell is still
        -- exactly as wide as it was asked to be. A label ABOVE the control
        -- wants the full width under it, and a control with no natural
        -- width of its own (a dropdown, a slider) is genuinely sized by the
        -- cell -- both keep the old behavior.
        local ownsItsWidth = def.wideWidth and labelText and placement ~= "above"
        if not ownsItsWidth then
            ctlW = forced
        elseif ctlW > def.wideWidth then
            ctlW = def.wideWidth
        end
    end

    return math.min(prefW, contentW), math.min(minW, contentW), h, stretch, ctlW
end

-- Pack fields into lines, then size each line to the row.
--
-- `justifyOverride` is a GROUP's own `justify`, which wins over the preset's
-- for that one card. A preset says how its KIND of card lines up, and that is
-- right for every strip but one: the Buff List's filters are read left to
-- right as a sentence ("these buffs, of this spec, matching this text"), so
-- Search flows after Filter by Spec instead of being thrown at the far edge
-- with the rest of the strip's `spread`. Nothing else passes one, so every
-- other group lines up exactly as it did.
local function PackLines(items, preset, contentW, justifyOverride)
    local justify = justifyOverride or preset.justify
    local lines, line, lineMin = {}, {}, 0

    -- The width a field is packed AGAINST. Under `wrapOn = "pref"` it is
    -- the preferred width, so a field that would only fit by squeezing the
    -- line starts a new one instead.
    local function packW(it)
        return (preset.wrapOn == "pref") and it.prefW or it.minW
    end

    for _, it in ipairs(items) do
        -- A BREAK closes the line and is gone: it is not placed, so it
        -- takes no width, no height and no gap of its own. Two breaks in a
        -- row, or one before the first field, leave no empty line behind --
        -- a row with nothing in it is never emitted.
        if it.isBreak then
            if #line > 0 then
                lines[#lines + 1] = line
                line, lineMin = {}, 0
            end
        else

        local wouldMin = lineMin + (#line > 0 and preset.gapX or 0) + packW(it)
        local capped   = preset.maxPerRow and #line >= preset.maxPerRow
        -- `newRow` on a field starts a line, whether or not the previous one
        -- was full. The packer flows fields by width alone, which is right
        -- almost everywhere and cannot express "these belong together and
        -- those do not" -- a group of border settings and then the dispel
        -- ones, say. Making that a break rather than a `wide` field says the
        -- reason (a boundary) instead of faking it with a size.
        local breaks = it.field and it.field.newRow
        if #line > 0 and (breaks or wouldMin > contentW or capped) then
            lines[#lines + 1] = line
            line, lineMin = {}, 0
        end
        line[#line + 1] = it
        lineMin = lineMin + (#line > 1 and preset.gapX or 0) + packW(it)
        end
    end
    if #line > 0 then lines[#lines + 1] = line end

    for _, ln in ipairs(lines) do
        local gaps = preset.gapX * (#ln - 1)
        local pref, minSum, stretchers = 0, 0, 0
        for _, it in ipairs(ln) do
            pref = pref + it.prefW; minSum = minSum + it.minW
            if it.stretch then stretchers = stretchers + 1 end
        end

        local avail = contentW - gaps
        if pref > avail then
            -- Shrink toward each field's minimum, proportionally to the
            -- slack each one actually has. Nothing goes below its minimum,
            -- which is what stops a control being shaved.
            local slack = pref - minSum
            local need  = pref - avail
            for _, it in ipairs(ln) do
                local s = it.prefW - it.minW
                it.w = it.prefW - ((slack > 0) and (need * s / slack) or 0)
            end
        elseif pref < avail and justify == "spread" then
            -- The first field stays where it is and everything else is
            -- pushed to the far edge, with the slack banked in the gap
            -- after it. Nothing is stretched: a strip that reads "this
            -- switch, and over here the two things that qualify it" wants
            -- its fields at their own sizes and the SPACE between them.
            for _, it in ipairs(ln) do it.w = it.prefW; it.padAfter = nil end
            if #ln > 1 then ln[1].padAfter = avail - pref end
        elseif pref < avail and justify == "fill" then
            local extra = avail - pref
            if stretchers > 0 then
                -- Only stretchy controls grow. A switch stays switch-sized
                -- however much room is left over.
                for _, it in ipairs(ln) do
                    if it.stretch then it.w = it.prefW + extra / stretchers
                    else it.w = it.prefW end
                end
            elseif #ln == 1 and ln[1].prefW / avail < preset.minRowFill then
                -- A single non-stretchy field on a line: leave it alone
                -- rather than blowing a switch up to full width.
                ln[1].w = ln[1].prefW
            else
                for _, it in ipairs(ln) do
                    it.w = it.prefW + extra / #ln
                end
            end
        else
            for _, it in ipairs(ln) do it.w = it.prefW end
        end
        -- WHOLE PIXELS. A proportional share (extra / stretchers, a "half"
        -- of the row, a fraction) is not one, and a control whose right
        -- edge sits on a half pixel draws its border there as two pixels
        -- or none. Floored, never rounded, so a line that fit still fits;
        -- the pixel or two of slack lands after the last field. The panel
        -- is drawn at one unit per pixel (Frame.lua StampPanelScale), so
        -- an integer here IS a pixel.
        for _, it in ipairs(ln) do
            it.w = math.floor(it.w)
            if it.padAfter then it.padAfter = math.floor(it.padAfter) end
        end
    end
    return lines
end

-- ── Binding index ──────────────────────────────────────────────
-- Every built widget registers under the path it reads, so refreshing a
-- setting is a table lookup and one call per hit -- not a rebuild. A
-- widget that is not currently built is simply absent from the index.

-- A disabled field's LABEL has to dim too.
--
-- Only the control was fading, so a disabled row read as a working one and
-- the only clue that a click would do nothing was the control's own
-- shading -- which is deliberately subtle. The label is the thing the eye
-- lands on, so it carries the state.
-- Re-point a font string at a different SIZE, keeping its face and flags.
-- Guarded on the size we last set rather than on GetFont: a re-set every
-- render is wasted work on a string that has not changed.
-- Guarded on the size the string ACTUALLY reports, not on a remembered
-- one. A cached "last size I set" is a claim that goes stale the moment
-- anything else touches the font -- a font object assigned over it, a
-- preview face set by a picker -- and a stale claim here does not merely
-- waste a call, it SUPPRESSES the correcting one: the string keeps a size
-- nobody asked for, permanently, and because widgets are pooled it is a
-- different string each time. GetFont is the only record that cannot lie.
local function SetFontSize(fs, size)
    if not (fs and size) then return end
    local face, cur, flags = fs:GetFont()
    if not face or cur == size then return end
    fs:SetFont(face, size, flags)
end
ns.SetFontSize = SetFontSize

local function PaintLabel(e, ctx)
    if not e.label or not e.preset then return end
    -- A field may color its own label. Other panels do this to mark a
    -- widget that configures the CONFIGURATION rather than the addon --
    -- the per-layout switch, say -- and a whole preset is too blunt an
    -- instrument for one field among five.
    local skin = ctx and ctx.app and ctx.app.skin
    local base = ns.PresetColor(e.preset, skin, "labelFg")
    local fg   = e.node.labelColor or base
    if type(fg) == "function" then fg = fg(e.node, ctx) or base end
    local off = ns.IsDisabled(e.node, ctx)
    local m   = off and 0.55 or 1
    SetFontSize(e.label, e.preset.labelSize)
    e.label:SetTextColor(fg[1] * m, fg[2] * m, fg[3] * m, off and 0.7 or 1)
end
ns.page.PaintLabel = PaintLabel

local function IndexOne(app, key, entry)
    if not key then return end
    app.bindIndex = app.bindIndex or {}
    local list = app.bindIndex[key]
    if not list then list = {}; app.bindIndex[key] = list end
    list[#list + 1] = entry
end

-- A composite control reads and writes SEVERAL settings -- an anchor point
-- plus an x and a y, say -- so it is indexed under each of them. Changing
-- any one of them has to be able to find this widget.
local function IndexWidget(app, node, entry)
    IndexOne(app, node.bind or node.id, entry)
    for _, bound in pairs(node.binds or {}) do
        -- An entry may be a bare path or a table naming one.
        local key = ns.BindPath(bound)
        if key and key ~= node.bind then IndexOne(app, key, entry) end
        local id = type(bound) == "table" and bound.id or nil
        if id and id ~= key and id ~= node.bind then IndexOne(app, id, entry) end
    end

    -- A SEPARATE index by id, not folded into the one above.
    --
    -- The bind index keys on `bind or id`, so a field carrying both is
    -- findable by its binding and invisible to its name. Rung 2 of the
    -- refresh ladder is "refresh the widget I named", and it has to work for
    -- a field that also happens to be bound -- which is most of them.
    if node.id then
        app.idIndex = app.idIndex or {}
        local list = app.idIndex[node.id]
        if not list then list = {}; app.idIndex[node.id] = list end
        list[#list + 1] = entry
    end
end

-- Does this field's appearance depend on anything OTHER than its own value?
-- Only those need re-evaluating when a different setting changes.
local function IsDynamic(node)
    if node.disabled == "combat" then return true end
    if type(node.disabled) == "function" then return true end
    if type(node.hidden)   == "function" then return true end
    if type(node.get)      == "function" then return true end
    -- A note whose text is computed reports state that other fields change,
    -- so it has to be swept like any other computed field.
    if type(node.text)     == "function" then return true end
    -- A list whose items are computed, likewise.
    if type(node.items)    == "function" then return true end
    return false
end

function ns.page.RefreshBinding(app, key)
    -- A nil key is legitimate: a field with a get/set pair and no `bind` or
    -- `id` has nothing to index. It used to return here, which meant such a
    -- field never refreshed itself -- the control kept showing its old state
    -- while the setting behind it had changed. There is no keyed work to do,
    -- but the dynamic sweep below still applies, and a computed getter makes
    -- a field dynamic by definition.
    if not app.bindIndex then return end

    -- 1. Every widget bound to the setting that changed. Usually one.
    local list = key and app.bindIndex[key]
    if list then
        for _, e in ipairs(list) do
            if e.widget and e.widget:IsShown() then
                e.def.refresh(e.widget, e.node, e.ctx)
                PaintLabel(e, e.ctx)
            end
        end
    end

    -- 2. Only fields whose appearance can depend on OTHER settings.
    --
    -- This used to refresh EVERY live field on the page. That was wasteful,
    -- and visibly wrong: refreshing a dropdown regenerates its menu and
    -- rewrites its label, so clicking any control made every dropdown on the
    -- page flicker its text. A field with a plain `bind` and no predicate
    -- cannot be affected by another field changing, so it is skipped.
    -- Mark the ones already refreshed above so they are not done twice.
    if list then
        for _, e in ipairs(list) do e.bpJustRefreshed = true end
    end
    for _, e in ipairs(app.liveFields or {}) do
        if e.dynamic and not e.bpJustRefreshed and e.widget and e.widget:IsShown() then
            e.def.refresh(e.widget, e.node, e.ctx)
            PaintLabel(e, e.ctx)
        end
    end
    if list then
        for _, e in ipairs(list) do e.bpJustRefreshed = nil end
    end

    -- 3. Did anything APPEAR or DISAPPEAR? Not this rung's question any
    -- more, and not anyone's. This rung refreshes VALUES; the page's SHAPE
    -- is re-derived by the render a write schedules for the end of the
    -- frame (ns.SetValue -> ns.page.ScheduleRender). Sweeping for shape
    -- here was only ever necessary because the shape was remembered, and
    -- it is not remembered any more.
end

-- ── THE PAGE'S SHAPE IS DERIVED, NEVER REMEMBERED ──────────────
--
-- The page used to keep a WATCH: every `hidden` predicate's answer was
-- sampled at render time and stored beside the question, and a sweep after
-- each refresh compared the stored answer with a fresh one and re-laid the
-- page out when the two differed.
--
-- That model has one fault it cannot be patched out of. The stored answer
-- IS the page's model of its own shape -- nothing else re-asks -- so an
-- answer taken at a bad instant is LATCHED. A predicate that reads the
-- consuming addon's state ("is this container still in the list?") can say
-- "gone" for exactly one frame while a debounced rebuild is in flight, and
-- the control it hid then stays hidden until something unrelated happens to
-- render again. That is the head strip whose controls vanished when a
-- switch two cards below it was toggled. Re-checking, settling and
-- blink-guarding all narrow the window in which the bad sample can be
-- taken; none of them close it, because the window is the model.
--
-- So nothing is remembered. This is the classic dialog discipline: a setter
-- finishes, the pane is rebuilt, and `hidden` is read once during that
-- build. A stale sample cannot outlive the frame it was taken in because
-- there is nowhere for it to live.
--
-- What IS kept is one boolean per host: does anything in it ask a `hidden`
-- QUESTION at all. That is a property of the DECLARATION, not an answer, so
-- it cannot go stale the way an answer does -- and it is what keeps a page
-- of plain fields from rebuilding itself on every click to re-derive a
-- shape that provably cannot have changed.
--
-- WHICH HOST IS RE-RENDERED IS THE POINT. `app.bpScope` names the host a
-- render draws into -- "page" or "pane:<route>", see ns.page.ReleaseScope
-- -- and the ctx a field was drawn with carries it, so a write inside a
-- tree group's pane redraws THAT PANE. The list beside it, its scroll frame
-- and its scrollbar are never touched, which is what a reader means when
-- they say a switch on the right should not disturb the column on the left.
--
-- The narrowing that follows, said plainly: a predicate on the PAGE BODY
-- that depends on a setting edited inside a PANE is not re-asked by that
-- write. Nothing on the body can depend on a pane's contents without the
-- consuming addon knowing that it does -- and that addon says so by calling
-- app:RefreshPage(), which schedules the page. Treating every write as a
-- page write instead is the escalation the scope exists to avoid: it
-- rebuilt the whole list on every toggle inside the pane.
--
-- A nil scope means "wherever this landed" and schedules every host that
-- has a question in it: over-render, never under-render. That is the answer
-- for a caller with no ctx to point at -- the combat sweep is the one.

-- One host has a `hidden` predicate in it. Called from the layout at every
-- point the watch used to take an entry, and recording strictly less: which
-- host asked, and nothing whatever about what it answered.
local function NoteDynamic(app)
    app.bpDynScopes = app.bpDynScopes or {}
    app.bpDynScopes[app.bpScope or "page"] = true
end

-- Every function-valued predicate in one group, its own and its fields'.
--
-- A group that is NOT drawn still has to be counted. The predicate that hid
-- it is the same one that will bring it back, and a host that stopped
-- counting would stop re-rendering: the card would be gone until something
-- else rebuilt the page.
local function NoteDynamicGroup(app, group)
    if type(group.hidden) == "function" then NoteDynamic(app) end
    for _, field in ipairs(group.fields or {}) do
        if type(field.hidden) == "function" then NoteDynamic(app) end
    end
end

-- ONE coalesced re-render per host, at the end of the frame.
--
-- Deferred rather than run on the spot because the caller is the handler of
-- the very control that wrote: rebuilding now would release that control
-- mid-click. Coalesced because several setters -- and several
-- app:RefreshPage() calls -- inside one frame are one gesture, and a
-- gesture is worth one render.
function ns.page.ScheduleRender(app, scope)
    if not app then return end
    local dyn = app.bpDynScopes
    if not dyn then return end

    -- Nothing in the named host asks a question, so its shape cannot have
    -- moved and there is no render to do.
    local want, any = {}, false
    if scope == nil then
        for s in pairs(dyn) do want[s] = true; any = true end
    elseif dyn[scope] then
        want[scope], any = true, true
    end
    if not any then return end

    -- Already queued for this frame: widen the pass that is coming rather
    -- than start a second one.
    if app.bpRenderWant then
        for s in pairs(want) do app.bpRenderWant[s] = true end
        return
    end
    app.bpRenderWant = want

    local function run()
        -- HELD, NOT DROPPED, WHILE THE MOUSE IS DOWN.
        --
        -- Rebuilding a host returns its widgets to the pool, and the widget
        -- under the cursor is usually the one that scheduled this: a slider
        -- writes on every notch of a drag, and a card being reordered is
        -- being carried. Dropping the render would lose a real shape change
        -- at the end of the gesture, so it waits for the button to come up
        -- instead -- which also collapses a whole drag into the one render
        -- its final value deserves.
        -- Gated on C_Timer existing, because holding without a timer to
        -- come back on is not holding, it is dropping.
        if C_Timer
           and ((ns.reorder and ns.reorder.IsDragging())
                or (ns.effects and ns.effects.IsDragging
                    and ns.effects.IsDragging(app))) then
            C_Timer.After(0, run)
            return
        end
        local scopes = app.bpRenderWant
        app.bpRenderWant = nil
        if not scopes then return end
        -- Never behind the reader's back: a closed panel renders when it
        -- opens, and against the state it opens on.
        if not (app.frame and app.frame:IsShown()) then return end

        -- The page subsumes every pane on it, so it is answered alone.
        if scopes["page"] then ns.page.Render(app); return end

        -- The route is read FRESH rather than captured: between the write
        -- and this frame the reader may have moved. A pane that has gone --
        -- pooled by a full render, or showing something else now -- is
        -- answered by the full render, which is never wrong, only wasteful.
        local routeKey = table.concat(app.route or {}, "/")
        for s in pairs(scopes) do
            local g = app.paneScopes and app.paneScopes[s]
            local t = g and g.bpTree
            local live = t and t.scope == s and g:IsShown()
                and (routeKey == t.key or ns.nav.RouteWithin(routeKey, t.key))
            if not live then ns.page.Render(app); return end
            ns.page.ReleaseScope(app, { [s] = true })
            ns.page.RenderPane(app, g)
        end
    end
    if C_Timer then C_Timer.After(0, run) else run() end
end

-- ── The rest of the refresh ladder ─────────────────────────────
--
-- Rung 1 is RefreshBinding above. These are 2 to 4, and none of them build
-- anything: they re-run `refresh` on widgets that already exist. Only rung 5
-- (Invalidate, in the library file) constructs, because only a structural
-- change needs new widgets.
--
-- Callers are expected to ask for the SMALLEST rung that does the job. The
-- ladder exists because the panel it replaces had exactly one granularity --
-- rebuild everything -- and almost every call site wanted far less.

local function RefreshEntry(e)
    if not (e.widget and e.widget:IsShown()) then return end
    e.def.refresh(e.widget, e.node, e.ctx)
    PaintLabel(e, e.ctx)
end

-- Rung 2: every live widget declaring this id. Usually one.
function ns.page.RefreshWidget(app, id)
    if not id then return end
    for _, e in ipairs((app.idIndex or {})[id] or {}) do RefreshEntry(e) end
end

-- A card's own CHROME, re-read from the declaration it was drawn from.
--
-- A heading may report a live value (`headerText`, and a collapsed card's
-- `headerButton` label), and those are not fields -- nothing in the field
-- ladder touches them, so a card whose read-out had changed kept showing
-- the old one until something re-rendered the page. The frame carries what
-- it was drawn with so this can be answered without a render: the group,
-- its ctx, the preset's label size and the heading color.
--
-- No layout and no allocation: at most two SetText calls per card.
function ns.page.RefreshGroupChrome(app, g)
    if not (g and g.bpGroup and g:IsShown()) then return end
    local group, ctx = g.bpGroup, g.bpCtx
    local hx = group.headerText
    if type(hx) == "function" then hx = hx(group, ctx) end
    if group.title and hx and hx ~= "" then
        if g.bpHeadSize then ns.SetFontSize(g.headerExtra, g.bpHeadSize) end
        g.headerExtra:SetText(hx)
        if g.bpHeadFg then g.headerExtra:SetTextColor(unpack(g.bpHeadFg)) end
        g.headerExtra:Show()
        -- `headerTooltip` spells the read-out out: it is icons and counts,
        -- and what an icon MEANS is exactly what a tooltip is for. Read
        -- here rather than captured at render, so this routine keeps it
        -- current on every rung-3 refresh.
        local ht = group.headerTooltip
        if type(ht) == "function" then ht = ht(group, ctx) end
        if ht and ht ~= "" and g.headerExtraHit then
            g.headerExtraHit:ClearAllPoints()
            g.headerExtraHit:SetPoint("LEFT", g.headerExtra, "LEFT", 0, 0)
            g.headerExtraHit:SetSize(
                math.max(g.headerExtra:GetStringWidth() or 0, 1),
                math.ceil(math.max(g.headerExtra:GetStringHeight() or 12, 12)))
            g.headerExtraHit:Show()
            ns.context.AttachOwnTooltip(g.headerExtraHit, app, group.title, ht)
        elseif g.headerExtraHit then
            ns.context.AttachOwnTooltip(g.headerExtraHit, app, nil, nil)
            g.headerExtraHit:Hide()
        end
    else
        g.headerExtra:Hide()
        if g.headerExtraHit then
            ns.context.AttachOwnTooltip(g.headerExtraHit, app, nil, nil)
            g.headerExtraHit:Hide()
        end
    end
    -- The header's button carries a live label too, and only while the
    -- card is shut -- which is exactly when its own fields are not there
    -- to be refreshed.
    if g.headerBtn and g.headerBtn:IsShown() then
        local hb = group.headerButton
        if type(hb) == "function" then hb = hb(group, ctx) end
        local t = hb and hb.text
        if type(t) == "function" then t = t(group, ctx) end
        if t and t ~= "" then
            g.headerBtn.text:SetText(t)
            g.headerBtn:SetWidth(math.ceil((g.headerBtn.text:GetStringWidth() or 40) + 16))
        end
    end
end

-- Rung 3: one group's fields and its own chrome, and nothing else on the
-- page. The rung to ask for when one card reports a value that just
-- changed -- a read-out in its heading, a row of toggles that share state.
function ns.page.RefreshGroup(app, id)
    local rec = (app.groupIndex or {})[id]
    if not rec then return end
    for _, e in ipairs(app.liveFields or {}) do
        if e.group == rec.group then RefreshEntry(e) end
    end
    ns.page.RefreshGroupChrome(app, rec.frame)
end

-- Rung 4: every live field on the visible page, in place. No rebuild, so a
-- field's widget, its position and its size all survive -- this is the rung
-- for "several settings changed at once", not for "the page is now a
-- different shape".
function ns.page.RefreshPage(app)
    for _, e in ipairs(app.liveFields or {}) do RefreshEntry(e) end
    -- Headings that report a value, through the same routine rung 3 uses,
    -- so the two cannot disagree about what a card's chrome says. Guarded
    -- on the declaration, so a page of ordinary cards pays one table read
    -- each and nothing more.
    for _, g in ipairs(app.liveGroups or {}) do
        if g.bpGroup and (g.bpGroup.headerText or g.bpGroup.headerButton) then
            ns.page.RefreshGroupChrome(app, g)
        end
    end
    -- ...and the page's SHAPE, re-derived by a render at the end of the
    -- frame. Scoped to the page because that is what this rung claims to
    -- be about: a consumer reaching for it is saying "something changed
    -- that I cannot name", and the page is the honest answer to that. It
    -- costs nothing on a page that asks no questions, and one render on
    -- one that does however many times it is called in the frame.
    ns.page.ScheduleRender(app, "page")
end

-- ── Rendering ──────────────────────────────────────────────────

local function ReleaseAll(app)
    for _, e in ipairs(app.liveFields or {}) do
        app:Release(e.widget)
        if e.label then e.label:Hide() end
        if e.hit then e.hit:Hide() end
    end
    for _, g in ipairs(app.liveGroups or {}) do
        -- The chrome's backing declaration goes with the frame: a pooled
        -- card handed to a different page must not still answer for the
        -- group it used to draw.
        g.bpGroup, g.bpCtx, g.bpHeadSize, g.bpHeadFg = nil, nil, nil, nil
        -- The same for what the card says about SCOPE: which render drew
        -- it, and the pane it hosts. A pooled card that still claimed a
        -- pane would have ns.page.ReleaseScope chase a pane that is gone.
        g.bpScope, g.bpTree = nil, nil
        app:Release(g)
    end
    ns.attach.ReleaseAll(app)
    app.liveFields = {}
    app.liveGroups = {}
    app.bindIndex  = {}
    app.idIndex    = {}
    app.groupIndex = {}
    -- Which hosts ask a `hidden` question -- re-counted by the layout
    -- pass, hidden fields included. Answers are never kept; see
    -- ns.page.ScheduleRender.
    app.bpDynScopes = {}
    -- Every pane went with its card. LayoutTreeGroup re-publishes the ones
    -- this render draws.
    app.paneScopes = {}
end

-- ── RENDER SCOPE, and giving ONE host's widgets back ───────────
--
-- `app.bpScope` names the host a render is currently drawing into. Two
-- values exist:
--
--     "page"          the page body -- app.scrollContent
--     "pane:<route>"  a tree group's right-hand pane, keyed on the tree's
--                     own route key, which is stable across renders while
--                     the pooled card frame is not
--
-- Everything a render builds is stamped with it -- fields, cards,
-- attachments, and every `hidden` question on the watch -- and that stamp
-- is what lets a flip inside a pane redraw the pane and nothing else. Any
-- host that does not set a scope inherits the enclosing one, so a future
-- host that forgets simply over-renders; it can never under-render.
--
-- This is the release half. It is a PRUNE, not a wipe:
--
--   * the live lists keep every entry belonging to another host, in order;
--   * bindIndex and idIndex hold the very same entry tables, so they are
--     pruned in the same pass -- an entry left behind would send rung 1 to
--     a widget that is back in the pool and now serving a different field;
--   * bpDynScopes loses only the released hosts' entry. The other hosts
--     still have whatever predicates they were declared with -- nothing in
--     them was re-declared -- and forgetting that would leave the page
--     body unable to schedule a render of itself until something else
--     happened to draw it.
--
-- Note groupIndex keys on the group's own id and takes the last writer, as
-- it always has: two cards with the same id collide whether the render was
-- scoped or not. The scoped path narrows that, it does not widen it.
local function ReleaseScope(app, scopes)
    -- A card inside this scope may itself HOST a pane, and that pane's
    -- widgets are stamped with the inner scope, not this one. Releasing the
    -- outer card without them would leave live entries pointing at widgets
    -- whose parent has gone back to the pool. So the set is closed over
    -- nesting first: a pane whose card is being released is being released
    -- too. Depth is one today; the failure mode if it ever is not is
    -- silent, which is why this is cheaper written than detected.
    local grew = true
    while grew do
        grew = false
        for _, g in ipairs(app.liveGroups or {}) do
            local t = g.bpTree
            if t and t.scope and scopes[g.bpScope] and not scopes[t.scope] then
                scopes[t.scope] = true
                grew = true
            end
        end
    end

    local live = app.liveFields or {}
    local keep = 0
    for i = 1, #live do
        local e = live[i]
        live[i] = nil
        if scopes[e.scope] then
            app:Release(e.widget)
            if e.label then e.label:Hide() end
            if e.hit then e.hit:Hide() end
        else
            keep = keep + 1
            live[keep] = e
        end
    end

    local groups = app.liveGroups or {}
    keep = 0
    for i = 1, #groups do
        local g = groups[i]
        groups[i] = nil
        if scopes[g.bpScope] then
            g.bpGroup, g.bpCtx, g.bpHeadSize, g.bpHeadFg = nil, nil, nil, nil
            g.bpScope, g.bpTree = nil, nil
            app:Release(g)
        else
            keep = keep + 1
            groups[keep] = g
        end
    end

    ns.attach.ReleaseScope(app, scopes)

    -- The two entry indexes. An emptied list is REMOVED rather than left
    -- as an empty table: rung 1 branches on whether the list exists.
    local function PruneIndex(index)
        for key, list in pairs(index or {}) do
            local n = 0
            for i = 1, #list do
                local e = list[i]
                list[i] = nil
                if not scopes[e.scope] then
                    n = n + 1
                    list[n] = e
                end
            end
            if n == 0 then index[key] = nil end
        end
    end
    PruneIndex(app.bindIndex)
    PruneIndex(app.idIndex)

    for id, rec in pairs(app.groupIndex or {}) do
        if scopes[rec.scope] then app.groupIndex[id] = nil end
    end

    -- The predicate COUNT for each host being released. Re-derived by the
    -- render that is about to draw into it; other hosts keep theirs,
    -- because nothing in them was re-declared.
    for scope in pairs(scopes) do
        if app.bpDynScopes then app.bpDynScopes[scope] = nil end
    end

    -- app.paneScopes is deliberately NOT cleared here.
    --
    -- A scoped release is a REDRAW: the pane is about to be drawn again
    -- into the very card it was published from, and it has not gone
    -- anywhere. Clearing it un-registered the pane, so the NEXT flip found
    -- no live pane and escalated to a full page render -- and the two flips
    -- of an on/off gesture then ran down two different code paths, sampling
    -- every predicate in the pane at two different moments. That
    -- alternation is what made the fallout intermittent.
    --
    -- Only ReleaseAll drops the registry, because only a full render can
    -- take a pane's card away.
end
-- Published because ns.page.ScheduleRender, far above this line, calls it:
-- a table lookup resolves at call time where an upvalue would not exist yet.
ns.page.ReleaseScope = ReleaseScope

-- The page's own left/right margin inside the body region. Named because
-- a band group gives it back to reach the region's edges.
local PAGE_INSET = 12

-- The gap between one card and the next, and after the last one. Named
-- because two places depend on it agreeing: the tree group's
-- height = "fill" subtracts the trailing gap when working out what is
-- left of the viewport, and `flush` takes it back off the card above.
local GROUP_GAP = 10

-- How far a `toggle.dims` card's body fades while its gate is off. The
-- same 0.4 a disabled gate wears, because it says the same thing and two
-- shades of "off" on one card would read as two different states.
local DIMMED_BODY_ALPHA = 0.4


-- One shape, built at a fixed set of corners, on a frame of its own.
--
-- `owner` is the card (so the variant is not a child of the frame it
-- covers, and cannot draw over that frame's own title or switch), `over` is
-- what it is anchored to, and `level` puts it under the things that must
-- stay on top.
local function ArtVariant(owner, over, sides, level)
    local f = CreateFrame("Frame", nil, owner)
    f:SetAllPoints(over)
    f:SetFrameLevel(math.max(level, 0))
    local ring = ns.RoundedFill(f, "BACKGROUND", 8, sides, { 0, 0, 0, 0 }, 0)
    local fill = ns.StrokedFill(f, "BORDER",     8, sides, { 0, 0, 0, 0 }, "card")
    f:Hide()
    return { frame = f, ring = ring, fill = fill }
end

local function GroupFactory(app)
    local g = CreateFrame("Frame", nil, app:GetRegion("body"))
    -- The same border treatment as every control: a filled rounded rect
    -- tinted as the border with the card body inset 1px on top of it.
    -- Two RoundedFills rather than ns.BorderedRound: the border color at
    -- inset 0, the body color at inset 1. Same two-opaque-fills border, but
    -- the corners are cropped quadrants drawn at a size we choose, so r
    -- texels land on exactly r PHYSICAL pixels. A nine-sliced corner is drawn
    -- at its texel size in UI units instead, which is why the cards looked
    -- soft while the panel -- which has a pixel host -- did not.
    -- The bordered box is its own frame rather than the card itself, so a
    -- TAB header can sit ABOVE it: the box starts under the tab and the tab
    -- sticks up out of it, instead of the card's border running around the
    -- outside of both. In band mode the two are the same rectangle.
    g.surface = CreateFrame("Frame", nil, g)
    -- Levels, bottom to top: the box's art, the box's rules (on the surface
    -- itself), the header's art, then the header with its title and switch.
    -- Every level is stated, because the defaults are not what this card
    -- needs: a child frame takes parent+1, which put the BODY (whose field
    -- labels are FontStrings on it) BELOW the surface -- so the box's fill
    -- painted over every label while the field widgets, being frames of
    -- their own, stayed visible.
    --
    --   +1  surface        the box and its rules
    --   +3  body           the fields and their labels
    --   +4  header art     the header's own fill and ring
    --   +5  header         its title, switch and grip
    g.surface:SetFrameLevel(g:GetFrameLevel() + 1)
    g.surface:SetPoint("BOTTOMLEFT",  g, "BOTTOMLEFT",  0, 0)
    g.surface:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
    -- Every shape the card can take is BUILT ONCE, in both variants, and
    -- the render shows one and hides the other. Re-shaping a rounded fill
    -- at runtime is what put smudges in the joins: a variant built with the
    -- corners it needs cannot half-change.
    --
    -- Each variant is a frame of its own so its two fills (border at inset
    -- 0, surface at inset 1) travel together, and so draw order is decided
    -- by FRAME LEVEL rather than by hoping about layers.
    -- ONE box, rounded all round -- a card's corners are its corners. The
    -- tab is inset past them instead (see the render), so no rounded corner
    -- sits under a square one and there is no notch to fill with whatever
    -- is behind the panel.
    g.paintRing = ns.RoundedFill(g.surface, "BACKGROUND", 8, nil, { 0, 0, 0, 0 }, 0)
    g.paintBody = ns.StrokedFill(g.surface, "BORDER",     8, nil, { 0, 0, 0, 0 }, "card")
    -- The header sits inside that 1px stroke, and its own fill is rounded
    -- at the top and square at the bottom so it meets the body flush
    -- without painting over the card's top corners.
    g.header = CreateFrame("Frame", nil, g)
    g.header:SetFrameLevel(g:GetFrameLevel() + 5)
    g.header:SetPoint("TOPLEFT",  g, "TOPLEFT",   1, -1)
    g.header:SetPoint("TOPRIGHT", g, "TOPRIGHT", -1, -1)
    -- Two fills, so the header can be a TAB as well as a band. As a band
    -- it is one fill spanning the card; as a tab it is content-width, and a
    -- shape that stops short of the card's edges needs an outline of its
    -- own -- the card's ring is nowhere near it. Ring at inset 0, surface
    -- at inset 1, the same two-fill border every card and control wears.
    -- Square along the bottom where a body meets it, rounded all round
    -- when a collapsed tab has nothing beneath it. The surface is INSET BY
    -- ONE inside the ring, or it covers the ring completely and the tab has
    -- no border at all.
    g.headerArt = {
        open = ArtVariant(g, g.header, "B", g.header:GetFrameLevel() - 1),
        shut = ArtVariant(g, g.header, nil, g.header:GetFrameLevel() - 1),
    }
    -- Right-click target for the group menu. Registered for the right
    -- button only, so it never eats a left click on anything in the header.
    g.headerHit = ns.context.Hit(g.header, function(self, button)
        -- Left is the gate, where there is one: the header is the card's
        -- own row, and a card that collapses should collapse from anywhere
        -- along it rather than only from a 36px switch.
        if button == "LeftButton" then
            if self.bpFlip then self.bpFlip() end
            return
        end
        if self.bpGroup then
            ns.context.GroupMenu(self, self.bpApp, self.bpGroup, self.bpCtx)
        end
    end)
    -- Not SetAllPoints: the right end is re-anchored per render, because a
    -- collapsible card's caret needs a strip of header that the hit area
    -- does NOT cover. See the caret block in Render.
    g.headerHit:SetPoint("TOPLEFT",     g.header, "TOPLEFT",     0, 0)
    g.headerHit:SetPoint("BOTTOMRIGHT", g.header, "BOTTOMRIGHT", 0, 0)

    -- The drag affordance: three bars at the header's left edge, shown only
    -- on a card that can actually be dragged.
    --
    -- Drawn rather than textured. At this size a TGA is three rows of
    -- texels scaled to whatever the UI scale makes of them, which is how
    -- the card corners ended up soft before they were given a pixel host;
    -- three SetColorTexture bars land on exact pixels at any scale and cost
    -- one frame and no file.
    --
    -- It is an INDICATOR, not a hit area. The whole header drags, and
    -- shrinking that to a 9px target would make the gesture harder to start
    -- while looking like an invitation.
    g.grip = ns.reorder.AttachGrip(g.header)
    g.grip:SetPoint("LEFT", g.header, "LEFT", 10, 0)

    -- The collapse caret, just right of the card's name -- and of its header
    -- button, where it has one. Built with the card and shown only for a
    -- group that asks to be collapsible.
    --
    -- It used to sit at the header's far RIGHT, which put it a whole bar
    -- away from the thing it opens and made it the last thing the eye
    -- reached on a row it should have been the second. Anchored per render
    -- (see the caret block in Render), because what it follows depends on
    -- whether the button is showing.
    --
    -- The chevron art points DOWN as authored; a card that is open shows it
    -- as drawn (pointing into the body it is showing) and a shut one rotates
    -- it a quarter turn, which is the convention every tree in this panel
    -- already uses for its own rows.
    g.caret = CreateFrame("Button", nil, g.header)
    g.caret:SetSize(16, 16)
    g.caret:SetPoint("LEFT", g.header, "LEFT", 11, 0)
    -- ABOVE the header's own hit area, for the reason the header button is:
    -- the hit area covers the whole bar, and at equal levels it takes the
    -- mouse first. The caret used to escape that by owning a strip at the
    -- end of the bar that the hit area gave up; in the middle of the bar it
    -- has to win on level instead.
    g.caret:SetFrameLevel(g.headerHit:GetFrameLevel() + 2)
    g.caret.art = g.caret:CreateTexture(nil, "OVERLAY")
    g.caret.art:SetTexture((ns.MEDIA or "") .. "chevron.tga")
    g.caret.art:SetSize(11, 11)
    g.caret.art:SetPoint("CENTER")
    g.caret:Hide()

    -- A card can put ONE action in its header, shown only while it is
    -- collapsed: the thing a reader would have opened the card to see. It
    -- sits just right of the title, so it reads as belonging to that card's
    -- name rather than as a second piece of header chrome at the far end.
    --
    -- A real button, with the same art every other button in the panel wears
    -- -- the fixed-corner construction, not the nine-sliced one (see
    -- button.create in Controls).
    g.headerBtn = CreateFrame("Button", nil, g.header)
    g.headerBtn:SetHeight(16)
    g.headerBtn.paintRing = ns.RoundedFill(g.headerBtn, "BACKGROUND", 8, nil,
                                           { 0, 0, 0, 0 }, 0)
    g.headerBtn.paintBody = ns.StrokedFill(g.headerBtn, "BORDER", 8, nil,
                                           { 0, 0, 0, 0 }, "control")
    g.headerBtn.text = ns.FS(g.headerBtn, "OVERLAY", "GameFontNormalSmall")
    g.headerBtn.text:SetPoint("CENTER")
    g.headerBtn.text:SetWordWrap(false)
    -- ABOVE the header's own hit area, which covers the whole bar: a frame
    -- under it never sees a click, and the press becomes a reorder drag --
    -- the same trap the caret fell into. The caret escapes it by sitting in
    -- a strip the hit area gives up; this one is in the middle of the bar,
    -- so it wins on level instead.
    g.headerBtn:SetFrameLevel(g.headerHit:GetFrameLevel() + 2)
    g.headerBtn:Hide()

    g.title = ns.FS(g.header, "OVERLAY", "GameFontNormalSmall")
    g.title:SetPoint("LEFT", g.header, "LEFT", 11, 0)

    -- `headerText`: a READ-OUT beside the card's name, drawn just right of
    -- the title. For what a section adds up to -- the specs a condition
    -- leaves enabled, say -- which belongs to the heading rather than to a
    -- row of its own, and costs a whole line when it takes one. Unlike the
    -- header's button it shows whether the card is open or shut.
    g.headerExtra = ns.FS(g.header, "OVERLAY", "GameFontNormalSmall")
    g.headerExtra:SetWordWrap(false)
    g.headerExtra:SetJustifyH("LEFT")
    g.headerExtra:Hide()

    -- The read-out's own hover region. A FontString takes no mouse, so a
    -- heading that reports something the reader may want spelled out needs
    -- a frame over it -- sized to the string rather than to the header, or
    -- the empty half of the bar would answer for it. Above the header's own
    -- hit area for the same reason the header button is: at equal levels
    -- the hit area takes the mouse first.
    g.headerExtraHit = CreateFrame("Frame", nil, g.header)
    g.headerExtraHit:EnableMouse(true)
    g.headerExtraHit:SetFrameLevel(g.headerHit:GetFrameLevel() + 2)
    g.headerExtraHit:Hide()
    -- Two divider lines, for a preset that is a BAND rather than a card:
    -- no ring, no corners, just a rule across the top and another across
    -- the bottom. Created with the card and shown only when asked for.
    -- ON THE SURFACE, not on the card. The surface is a CHILD FRAME, and a
    -- child draws above its parent's textures whatever their layer -- so a
    -- rule created on the card was painted over by the box's own fill, and
    -- all that showed of a band's two rules were slivers at the corners
    -- where the fill's rounding let them through.
    g.ruleTop = g.surface:CreateTexture(nil, "OVERLAY")
    g.ruleTop:SetHeight(1)
    g.ruleTop:SetPoint("TOPLEFT",  g.surface, "TOPLEFT",  0, 0)
    g.ruleTop:SetPoint("TOPRIGHT", g.surface, "TOPRIGHT", 0, 0)
    g.ruleTop:Hide()
    g.ruleBottom = g.surface:CreateTexture(nil, "OVERLAY")
    g.ruleBottom:SetHeight(1)
    g.ruleBottom:SetPoint("BOTTOMLEFT",  g.surface, "BOTTOMLEFT",  0, 0)
    g.ruleBottom:SetPoint("BOTTOMRIGHT", g.surface, "BOTTOMRIGHT", 0, 0)
    g.ruleBottom:Hide()

    -- The box's top-left corner, squared off with a patch rather than by
    -- re-shaping the box: a TAB sits flush with the card's left edge and
    -- overlaps the box by a pixel, so the box's rounded corner curves away
    -- underneath it and the panel shows through the gap -- the black smudge
    -- in the join. Two pieces, border then surface, the same order the box
    -- itself is painted in. Shown only under a tab.
    g.patchRing = g.surface:CreateTexture(nil, "ARTWORK")
    g.patchRing:SetPoint("TOPLEFT", g.surface, "TOPLEFT", 0, 0)
    g.patchRing:Hide()
    g.patchBody = g.surface:CreateTexture(nil, "ARTWORK", nil, 1)
    g.patchBody:SetPoint("TOPLEFT", g.surface, "TOPLEFT", 1, -1)
    g.patchBody:Hide()

    -- The rule between a header and the body under it, in the border's own
    -- color: the header is a band of a different shade, and without a line
    -- the two shades simply meet.
    -- Same reason as the two above: on the surface, or the box's fill
    -- covers it.
    g.headRule = g.surface:CreateTexture(nil, "OVERLAY")
    g.headRule:SetHeight(1)
    g.headRule:Hide()

    -- The header's own switch, for a group that GATES its contents: the
    -- setting the whole card is about lives in the header rather than as
    -- the first field inside it, and turning it off collapses the card to
    -- the header alone. Built with the card, shown only when asked for.
    g.gate = CreateFrame("Button", nil, g.header)
    g.gate:SetSize(ns.SWITCH_W, ns.SWITCH_H)
    g.gate:SetPoint("LEFT", g.header, "LEFT", 10, 0)
    g.gate.pill = ns.SwitchPill(g.gate)
    g.gate.pill:SetAllPoints(g.gate)
    -- Scripts are set ONCE, here, and the render only hands over data.
    -- SetScript on every render would destroy the tooltip hook that
    -- ns.context adds on top of OnEnter -- the hook is added once, and a
    -- later SetScript takes it with it.
    g.gate:SetScript("OnEnter", function(self)
        self.bpHovered = true
        ns.PaintBorder(self, "hover")
    end)
    g.gate:SetScript("OnLeave", function(self)
        self.bpHovered = false
        ns.PaintBorder(self, nil)
    end)
    g.gate:SetScript("OnClick", function(self)
        if self.bpFlip then self.bpFlip() end
    end)
    g.gate:Hide()

    g.body = CreateFrame("Frame", nil, g)
    g.body:SetFrameLevel(g:GetFrameLevel() + 3)
    return g
end

-- ── Collapsed cards ────────────────────────────────────────────
--
-- A group that declares `collapsible = true` gets a caret in its header and
-- collapses to that header. `collapsed = true` on the group is the state it
-- starts in the first time it is seen; after that the reader's own choice
-- stands, and it is REMEMBERED -- written into the same table the panel
-- keeps its geometry in, so a card the reader shut is still shut next
-- session.
--
-- Keyed by the group's `id`, falling back to its title: an id is stable
-- across a reorder and a rename, a title is neither, and a group with
-- neither cannot be remembered at all (it collapses for the session only).
local function CollapseKey(group)
    return group.id or group.title
end

local function CollapseStore(app)
    local store = app.persist and app.persist()
    if not store then return nil end
    store.panelCollapsed = store.panelCollapsed or {}
    return store.panelCollapsed
end

local function IsCollapsed(app, group)
    if not group.collapsible then return false end
    local key = CollapseKey(group)
    if not key then return app.collapsed and app.collapsed[group] or false end
    local store = CollapseStore(app)
    local v = store and store[key]
    if v == nil then v = app.collapsed and app.collapsed[key] end
    if v == nil then return group.collapsed and true or false end
    return v and true or false
end

local function SetCollapsed(app, group, v)
    local key = CollapseKey(group)
    if not key then
        app.collapsed = app.collapsed or {}
        app.collapsed[group] = v
        return
    end
    app.collapsed = app.collapsed or {}
    app.collapsed[key] = v
    local store = CollapseStore(app)
    if store then store[key] = v end
end

local function ResolvePreset(app, name)
    return app.groupPresets[name or "default"] or app.groupPresets.default
end

-- Lay out one group's fields and return the group's total height.
local function LayoutGroup(app, g, group, preset, ctx, width)
    local pad      = preset.padding
    local contentW = width - pad * 2

    -- A DIMMED GATE, decided before a single field is measured.
    --
    -- `toggle.dims` keeps the body when the gate is off instead of
    -- collapsing to the header, so the reader can still see WHAT the
    -- switch turns on. The body is dimmed below; what happens here is the
    -- other half of that, and the half a reader would otherwise find out
    -- by clicking: every field in the card is entered into the render's
    -- dimmed set, and ns.IsDisabled answers true for all of them. Grayed
    -- AND inert, rather than grayed and secretly live.
    --
    -- Registered here rather than at paint time because the measure loop
    -- below already asks controls about themselves, and a field that
    -- reported enabled while measuring and disabled while painting is the
    -- same one-answer-per-render fault the hidden memo exists to prevent.
    local gate = group.toggle
    if gate and gate.dims and group.title then
        local on = gate.get and gate.get(group, ctx) and true or false
        if not on then
            local memo = app.bpDimmed
            if memo then
                for _, field in ipairs(group.fields or {}) do
                    if type(field) == "table" then memo[field] = true end
                end
            end
        end
    end
    -- Placement is decided per FIELD (a strip's switch can read inline
    -- while its dropdowns are labeled above), so it is resolved in the
    -- placement loop rather than once for the group.

    -- 1. measure every field
    local items = {}
    for _, field in ipairs(group.fields or {}) do
        -- A LINE BREAK is not a field. It builds no widget, takes no
        -- height and no row space, and carries no value -- it is a mark in
        -- the field list saying "the row ends here", which the packer
        -- honors and everything else ignores.
        --
        -- It still answers `hidden`, so a break can come and go with the
        -- controls around it: a break left behind by a hidden field would
        -- end a row that no longer has anything in it, which reads as a
        -- blank line down the middle of a card.
        if ns.IsLineBreak(field) then
            if not ns.IsHidden(field, ctx) then
                items[#items + 1] = { isBreak = true, field = field,
                                      prefW = 0, minW = 0, h = 0 }
            end
            if type(field.hidden) == "function" then NoteDynamic(app) end
        end
        -- `def` stays nil for a break, and the two branches below both test
        -- it -- so the marker falls straight through without a measure, a
        -- widget or a second watch entry. (Lua 5.1: no `goto`, and none
        -- wanted -- a nil `def` says the same thing.)
        local def = (not ns.IsLineBreak(field))
                    and (app.controls[field.control] or ns.builtinControls[field.control])
                    or nil
        -- A hidden field is measured out of existence rather than drawn and
        -- covered: it takes no row space, and the fields after it close up.
        -- Every field with a FUNCTION predicate is counted below, visible
        -- or not: a host holding a question is a host whose shape a write
        -- can change, and a hidden field is precisely the one with no
        -- widget of its own to notice on its behalf.
        if def and ns.IsHidden(field, ctx) then
            if type(field.hidden) == "function" then NoteDynamic(app) end
        elseif def then
            if type(field.hidden) == "function" then NoteDynamic(app) end
            local prefW, minW, h, stretch, ctlW =
                FieldMetrics(def, field, preset, contentW, ctx)
            items[#items + 1] = {
                field = field, def = def, ctlW = ctlW,
                prefW = prefW, minW = minW, h = h, stretch = stretch,
            }
        end
    end

    -- 2. pack into lines and size them
    local lines = PackLines(items, preset, contentW, group.justify)

    -- 3. place
    local y = 0
    for _, ln in ipairs(lines) do
        -- The row's height is known BEFORE anything is placed, so a field
        -- shorter than the row can be positioned within it.
        --
        -- TWO rules, because a row holds two kinds of thing.
        --
        -- A field LABELED ABOVE is aligned to the TOP. Every such label
        -- then shares one baseline and every such control starts at the
        -- same y, which is what the eye reads as a row -- and what other
        -- options dialogs do. Centring them instead put a short dropdown 7px
        -- below a tall slider and took its label down with it, so a row of
        -- two labeled controls had its two labels at different heights.
        --
        -- A field with NO label, or with its label beside it, is still
        -- CENTERED -- but within the control band, the row minus the label
        -- line. That is the case the centring was written for: a bare
        -- switch beside two labeled dropdowns should sit level with the
        -- DROPDOWNS, not with their labels, and it still does.
        local rowH, labelRow = 0, false
        for _, it in ipairs(ln) do
            -- Whole pixels: a wrapped note measures to a fractional height,
            -- and every control below it would otherwise sit on a half
            -- pixel -- its top and bottom borders drawn as two or none.
            it.h = math.ceil(it.h or 0)
            rowH = math.max(rowH, it.h)
            it.topLabel = (not it.def.ownLabel) and (ns.FieldLabel(it.field) ~= nil)
                and ((it.field.labelPlacement or preset.labelPlacement) ~= "left")
            if it.topLabel then labelRow = true end
        end
        local x = 0
        for _, it in ipairs(ln) do
            local top
            if it.topLabel then
                top = 0
            elseif labelRow and it.field.rowAlign ~= "center" then
                top = LABEL_H + (rowH - LABEL_H - it.h) / 2
            else
                -- `rowAlign = "center"` opts out of the rule above: centered
                -- on the WHOLE row, label line included. The default is
                -- right for a bare switch beside two labeled dropdowns --
                -- it should sit level with the dropdowns, not with their
                -- captions -- but a field that is the row's SUBJECT rather
                -- than one more control in it reads as dropped to the
                -- bottom, because everything it is level with has a caption
                -- above it and it does not.
                top = (rowH - it.h) / 2
            end
            local y = y + math.max(0, math.floor(top + 0.5))
            local field = it.field
            -- `scope` is which HOST this widget was drawn into -- see the
            -- render-scope note above ns.page.ReleaseScope. It rides on the
            -- entry itself, so bindIndex and idIndex (which hold these same
            -- tables) answer the question without a second stamp.
            local e = { node = field, def = it.def, ctx = ctx, scope = app.bpScope }
            -- Only fields with a predicate or a computed getter can be
            -- affected by a DIFFERENT setting changing; see RefreshBinding.
            e.dynamic = IsDynamic(field)
            e.widget = app:Acquire("ctl:" .. field.control, function(a)
                return it.def.create(a, g.body)
            end)
            e.widget:SetParent(g.body)
            e.widget:ClearAllPoints()
            e.widget:Show()

            local labelText = (not it.def.ownLabel) and ns.FieldLabel(field) or nil
            if labelText then
                if not e.widget.bpLabel then
                    e.widget.bpLabel = ns.FS(g.body, "OVERLAY", "GameFontNormalSmall")
                    e.widget.bpLabel:SetJustifyH("LEFT")
                    e.widget.bpLabel:SetWordWrap(false)
                end
                if not e.widget.bpLabelHit then
                    e.widget.bpLabelHit = ns.context.Hit(g.body, function(self)
                        if self.bpNode then
                            ns.context.FieldMenu(self, self.bpApp, self.bpNode, self.bpCtx)
                        end
                    end)
                end
                e.hit = e.widget.bpLabelHit
                e.hit:SetParent(g.body)
                e.hit.bpApp, e.hit.bpNode, e.hit.bpCtx = app, field, ctx
                e.hit:ClearAllPoints()
                e.hit:Show()

                e.label = e.widget.bpLabel
                e.label:SetParent(g.body)
                e.label:ClearAllPoints()
                e.label:SetText(ns.search.Mark(app, labelText))
                e.label:Show()
            elseif e.widget.bpLabelHit and e.widget.bpLabel then
                e.widget.bpLabelHit:Hide()
                -- Pooled widgets keep their label FontString between uses; a
                -- widget reused for an unlabeled field must hide the old text.
                e.widget.bpLabel:Hide()
            end

            local cx = pad + x
            local labelAbove = ((field.labelPlacement or preset.labelPlacement)
                                ~= "left")
            if labelAbove then
                if e.label then
                    e.label:SetPoint("TOPLEFT", g.body, "TOPLEFT", cx, -y)
                    e.label:SetWidth(it.w)
                    e.hit:SetPoint("TOPLEFT", g.body, "TOPLEFT", cx, -y)
                    e.hit:SetSize(math.min(it.w, math.ceil(e.label:GetStringWidth() + 6)), LABEL_H)
                    e.widget:SetPoint("TOPLEFT", g.body, "TOPLEFT", cx, -(y + LABEL_H))
                else
                    e.widget:SetPoint("TOPLEFT", g.body, "TOPLEFT", cx, -y)
                end
                -- A control is drawn at ITS OWN width. Never the cell's.
                --
                -- The cell can be wider for two reasons -- a long label is
                -- measured into it, or the line had room left over -- and
                -- neither is a reason for the control to grow. A slider is
                -- a slider's width on every card, a stepper is a stepper,
                -- and the spare room simply goes unused. That is what makes
                -- a column of controls read as a column.
                --
                -- The label still gets the whole cell, so captions neither
                -- clip nor wrap. The label-BESIDE branch below has always
                -- worked this way; this branch used to hand over the cell.
                e.widget:SetWidth(math.max(24, math.min(it.ctlW or it.w, it.w)))
            else
                -- The control keeps its own width and the LABEL takes
                -- what is left, rather than both being estimated
                -- independently: in a cell narrower than the two of them
                -- want, an independently-estimated label was drawn straight
                -- across its control.
                local ww = math.max(24, math.min(it.ctlW or it.w, it.w))
                local lw = e.label and math.max(0, it.w - ww - 8) or 0
                -- `labelSide = "after"` puts the label on the far side of
                -- its control. A switch reads that way round -- the state
                -- first, then what it is the state OF -- and a labeled
                -- dropdown does not, so it is a field's choice rather than
                -- the preset's.
                local after = (field.labelSide == "after")
                if e.label and lw < 10 then
                    -- No room for a label beside the control at this width.
                    -- Hidden rather than squeezed: a two-character stub of
                    -- a label is worse than none, and the tooltip still
                    -- carries the full text.
                    --
                    -- Reported, though. A field that declares a label and
                    -- draws none is the panel disagreeing with its own
                    -- declaration, and at a readable panel width it means
                    -- the field is mis-declared rather than the reader
                    -- being short of room -- which is exactly the kind of
                    -- thing that goes unnoticed until somebody reports a
                    -- toggle with no words next to it.
                    ns.Report(app, "field '"
                        .. tostring(field.id or field.bind or field.control)
                        .. "' has a label but no room to draw it")
                    e.label:Hide()
                    e.hit:Hide()
                elseif e.label then
                    local lx = after and (cx + ww + 8) or cx
                    -- A label AFTER its control sits on the control's own
                    -- baseline -- bottom aligned with the switch beside it,
                    -- not with the top of the cell -- because the two read
                    -- as one thing: the state, and what it is the state of.
                    local ly = after and (y + it.h - 15) or (y + 3)
                    e.label:SetPoint("TOPLEFT", g.body, "TOPLEFT", lx, -ly)
                    e.label:SetWidth(lw)
                    e.hit:SetPoint("TOPLEFT", g.body, "TOPLEFT", lx, -y)
                    e.hit:SetSize(lw, it.h)
                    e.label:Show()
                    e.hit:Show()
                end
                e.widget:SetPoint("TOPLEFT", g.body, "TOPLEFT",
                    cx + ((e.label and not after) and (lw + 8) or 0), -y)
                e.widget:SetWidth(ww)
            end

            it.def.apply(e.widget, field, ctx)
            it.def.refresh(e.widget, field, ctx)

            -- Search dims what it did not match, in place. The field keeps
            -- its position, its size and its behavior -- only its contrast
            -- drops -- so the page does not reflow under the reader while
            -- they are still typing, and a setting they can see but did not
            -- search for is still there to be used.
            -- Alpha is INHERITED from the group frame, so these two dims
            -- must not both apply: a dimmed field inside a dimmed group
            -- would land at 0.25 x 0.25 and read as invisible rather than
            -- as faded. When the whole group is already dimmed, the fields
            -- stay at full and let the group's alpha do the work.
            local fa = 1
            if ns.search and ns.search.GroupMatches(app, group)
               and not ns.search.FieldMatches(app, field) then
                fa = ns.search.DimAlpha()
            end
            e.widget:SetAlpha(fa)
            if e.label then e.label:SetAlpha(fa) end

            -- After apply, so the control's own scripts are in place first.
            e.preset = preset
            -- Published on the WIDGET as well, for a composite that draws a
            -- heading of its own beside the field's label -- the anchor
            -- pad's "Offsets" -- and has to match it. A composite cannot
            -- see the group it was drawn into, and a heading a point size
            -- off the label next to it reads as a different font.
            e.widget.bpLabelSize = preset.labelSize
            -- And the HEADER's size, which is what a button's caption is
            -- drawn at: a button is a thing you press rather than a row you
            -- read, and at the label size it read as a caption that happened
            -- to have a border around it.
            e.widget.bpHeaderSize = preset.headerSize
            PaintLabel(e, ctx)
            ns.context.AttachField(e.widget, app, field, ctx)
            ns.context.AttachFieldTooltip(e.widget, app, field, ctx, e.hit)

            e.group = group
            app.liveFields[#app.liveFields + 1] = e
            IndexWidget(app, field, e)

            x = x + it.w + preset.gapX + (it.padAfter or 0)
        end
        y = y + rowH + preset.gapY
    end

    return math.max(y - preset.gapY, 0)
end

-- ── Dragging a group card to reorder it ────────────────────────
--
-- The gesture is ns.reorder, the same one the rail tree uses. This
-- supplies the two things it does not know: which cards count as siblings,
-- and what a drop means.
--
-- The HEADER is the handle. Dragging the card itself would fight every
-- control inside it, and the header is already a distinct frame with a
-- right-click hit area that is registered for the right button only -- so
-- a left drag there is free.
--
--   page.reorder = { onMove = function(group, from, to) ... end,
--                    combat = false }
--
-- `from` and `to` are positions in `page.groups`, not positions among the
-- draggable cards, so a page that pins one card with
-- `group.reorderable = false` still gets indices it can use directly
-- against its own list.
-- EVERY card on the page, pinned ones included.
--
-- Leaving the pinned ones out would work for a card pinned at the top and
-- fail for one pinned in the middle: excluded from the list it stops being
-- a barrier, and the cards on either side of it would swap straight past
-- it. In the list it is a barrier, because `locked` clamps a drop to the
-- gap just above or just below it -- neither of which changes its own
-- position.
local function GroupSiblings(handle)
    local app = handle.bpApp
    local out = {}
    for _, g in ipairs((app and app.liveGroups) or {}) do
        if g:IsShown() and g.bpGroupIndex then out[#out + 1] = g end
    end
    table.sort(out, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    return out
end

local function InstallGroupDrag(app, g, page, group, index, ctx)
    g.bpGroup, g.bpGroupIndex = group, index
    local spec = page.reorder
    g.bpReorderable = (spec and spec.onMove and group.reorderable ~= false) and true or false
    g.grip:SetShown(g.bpReorderable)
    -- The title makes room for the grip only when there is one, so a page
    -- that never reorders looks exactly as it did.
    g.title:ClearAllPoints()
    g.title:SetPoint("LEFT", g.header, "LEFT", g.bpReorderable and 24 or 11, 0)
    ns.reorder.PaintGrip(g.grip, app.skin, false)

    if not g.bpReorderable then
        ns.reorder.Install(g.headerHit, nil)
        return
    end
    ns.reorder.Install(g.headerHit, {
        item       = function() return g end,
        siblings   = GroupSiblings,
        -- `reorderable = false` now means FIXED, not merely undraggable:
        -- a pinned card's position cannot be taken either.
        pinned     = function(f) return not f.bpReorderable end,
        -- The grip is the one thing that stays lit while the card itself
        -- dims, so what is being dragged is still legible.
        onStart    = function() ns.reorder.PaintGrip(g.grip, app.skin, true) end,
        onEnd      = function() ns.reorder.PaintGrip(g.grip, app.skin, false) end,
        color     = function() return app.skin.accent end,
        scroll     = function() return app.scroll end,
        lineParent = function() return app.scrollContent end,
        blocked    = function()
            return spec.combat ~= false and InCombatLockdown()
        end,
        onDrop = function(from, to, sibs)
            local moving = sibs[from]
            local target = sibs[to]
            if not (moving and target) then return end
            spec.onMove(moving.bpGroup, moving.bpGroupIndex, target.bpGroupIndex)
            app:Invalidate()
        end,
    })
end

-- Resolve a route's page ONCE and remember it.
--
-- A page may be declared as a function -- that is what makes a collection's
-- members lazy, and what lets a page depend on a setting. Every call to
-- such a function returns FRESH group and field tables, and the search
-- index is keyed by table identity: it records "this group matched" against
-- the tables it saw while indexing, and the render then shows different
-- tables the index has never heard of. The visible symptom is a group that
-- dims although the word inside it is highlighted -- the marking is
-- text-based and works, the dimming is identity-based and does not.
--
-- Memoising makes the index and the render hold the SAME tables, which is
-- what the identity lookups were always assuming. It also stops a function
-- page being built twice on every pass, once for search and once for
-- content.
--
-- Cleared by ReindexRoutes, which is the path every structural change
-- already takes -- a collection's add, remove or reorder, and Invalidate.
-- A value-level refresh does NOT clear it and must not: fields re-read
-- through get/bind, and nothing about them depended on the page table
-- being new.
-- THE PAGE THE BODY WOULD DRAW for the current route, ancestor fallback
-- and all.
--
-- A ROUTE WITHOUT A PAGE FALLS BACK TO ITS NEAREST ANCESTOR WITH ONE.
-- Blanking the body was never a safe answer to "this node has no page":
-- plenty of real nodes have none -- a section heading inside a collection,
-- a branch that exists only to hold children -- and the route lands on one
-- whenever something structural moves under the reader. Every one of those
-- took the whole panel away and left the placeholder in its place.
--
-- Named because TWO things ask it now: the render, and the page header,
-- which has to know whether this page brings a header field with it before
-- the tab strip is placed -- and the two must not disagree about which
-- page is on screen. Resolve is memoised, so asking twice costs a lookup.
function ns.page.ForRoute(app)
    local key   = table.concat(app.route or {}, "/")
    local entry = app.routeIndex and app.routeIndex[key]
    local page  = ns.page.Resolve(app, entry)
    if page then return page end

    local path = {}
    for i, id in ipairs(app.route or {}) do path[i] = id end
    while #path > 0 and not page do
        path[#path] = nil
        local up = (#path > 0)
                   and app.routeIndex and app.routeIndex[table.concat(path, "/")]
        page = up and ns.page.Resolve(app, up) or nil
    end
    return page
end

function ns.page.Resolve(app, entry)
    if not entry then return nil end
    app.pageCache = app.pageCache or {}
    local hit = app.pageCache[entry.key]
    if hit then return hit end

    local node = entry.node
    local page = node.page
    -- A page that ERRORS is not a page that HAS none, and the difference
    -- has to survive into the cache. Memoising a throw as `false` made one
    -- bad build permanent: ns.search.Build resolves every route in the
    -- panel on the first keystroke, so a page function that threw once
    -- under that sweep -- against whatever state happened to exist at that
    -- moment -- rendered as the route placeholder for the rest of the
    -- session, tree card and all, and nothing short of a structural change
    -- cleared it. Report it and leave the cache alone, so the next pass can
    -- succeed.
    local failed = false
    if type(page) == "function" then
        local ok, built = pcall(page, node)
        if ok then
            page = built
        else
            page, failed = nil, true
            if geterrorhandler then geterrorhandler()(built) end
        end
    end
    -- An inline collection assembles its own page from its members. Asked
    -- rather than detected, so this file needs to know nothing about
    -- collections beyond that they might have something to say.
    if ns.collections and ns.collections.PageFor then
        page = ns.collections.PageFor(app, node, page)
    end

    -- Only a REAL page is remembered. Caching "no page" as false made every
    -- transient nil permanent -- a builder that answered nil once, under
    -- whatever state a search sweep or a rebuild happened to catch it in,
    -- stayed answering nil for the session. A node with no page at all
    -- costs nothing to re-ask: node.page is nil and there is nothing to
    -- call.
    if not failed and page then app.pageCache[entry.key] = page end
    return page
end

function ns.page.ClearPageCache(app)
    app.pageCache = nil
    -- A collection's member pages are memoised on the same terms and for
    -- the same reason -- see ns.collections.MemberPage -- so they go with
    -- the rest of it. Anything else lets a removed member's page outlive
    -- the member.
    app.memberPages = nil

    -- AND THE SEARCH'S MATCH SETS, which are keyed by the very tables that
    -- were just thrown away.
    --
    -- ns.search.Apply records `searchFields[field] = true` and
    -- `searchGroups[group] = true` -- the field and group TABLES, not their
    -- ids. Rebuilding a page hands out new tables for the same
    -- declarations, so every card on it then fails GroupMatches and every
    -- field fails FieldMatches, and the page renders dimmed to a quarter
    -- with nothing highlighted. That is one control's setter fading
    -- controls it has nothing to do with: any Invalidate while a query is
    -- live did it.
    --
    -- Re-matched rather than merely dropped, because dropping them would
    -- read as "everything matches" while the box still holds a query. The
    -- query is the reader's, and it survives the rebuild.
    if ns.search and ns.search.IsActive and ns.search.IsActive(app) then
        app.searchIndex = nil
        ns.search.Rematch(app)
    end
end

-- Does the page under the current route OPEN with a band?
--
-- A band (`dividers`) runs to the region's edges and reads as part of the
-- chrome rather than as a card sitting on the page, so whatever sits above
-- one belongs directly ON it: the tab strip's landing gap under the last
-- pill and the page's own top inset are, between a strip and a band, a gap
-- between two things that should meet. The tab strip asks this before it
-- reserves its height and Render asks it again before it anchors the
-- scroll; `Resolve` is cached per route, so the page is built once either
-- way.
function ns.page.OpensWithBand(app)
    local key    = table.concat(app.route or {}, "/")
    local entry  = app.routeIndex and app.routeIndex[key]
    local page   = entry and ns.page.Resolve(app, entry)
    local first  = page and page.groups and page.groups[1]
    if not first then return false end
    local preset = ResolvePreset(app, first.preset)
    return preset.dividers and true or false
end

-- ── Does a group draw at all? ──────────────────────────────────
--
-- Two ways it does not.
--
--   * Its own `hidden` says so -- the group-level twin of a field's, and
--     what several pages wanted and had to fake by hiding every field
--     one by one, which emptied the card and left its heading, its
--     border and its padding behind.
--   * Every field in it is hidden. A card whose contents have all gone
--     is a heading and a box around nothing; the reader reports that as
--     "the settings hid but the box didn't".
--
-- Two deliberate exceptions, and they are not the same exception:
--
--   * a GATED card (`toggle`) stays. The switch in its header IS the
--     setting the card is about, so collapsed-to-the-header is that card
--     working rather than an empty one, and hiding it would take away
--     the only way to turn its contents back on.
--   * a group that declares NO fields at all stays. That is a spacer, a
--     note or a heading -- something whose whole content is its chrome,
--     not a card whose contents vanished.
local function GroupShown(app, group, ctx)
    if ns.IsHidden(group, ctx) then return false end
    if group.toggle then return true end
    -- Same exemption, same reason: a collapsed card shows no fields, and
    -- hiding it would take away the only way to open it again.
    if group.collapsible then return true end
    local fields = group.fields
    if not fields or #fields == 0 then return true end
    for _, field in ipairs(fields) do
        local def = app.controls[field.control] or ns.builtinControls[field.control]
        if def and not ns.IsHidden(field, ctx) then return true end
    end
    return false
end


-- ── The tree group ─────────────────────────────────────────────
--
-- A card whose body is a LIST on the left and a PAGE on the right: the
-- classic tree group, as a group rather than as a region. The list is
-- one node's children -- almost always a collection's members -- and the
-- right-hand pane is the selected member's own page.
--
-- Being a group is the whole point. Controls above it are just groups
-- above it on the same page, so a section can put its search box, its
-- filter and its Add form over the list simply by declaring them first,
-- and no panel-level layout has any say in it.
--
--   { tree = { route = "a/b/c",   -- whose children the list shows;
--                                 -- a string or a function(app)
--              width  = 180,      -- the list column
--              height = 420 } }   -- the card's body
--
-- `height = "fill"` sizes the body to whatever is left of the viewport
-- below the cards above it -- a classic tree group's own behavior, where
-- the list ran to the bottom of the dialog and grew with it. The page
-- re-renders on resize, so the card follows the panel. `minHeight`
-- (default 200) is the floor, below which the page scrolls instead.
--
-- The pane is a page in its own right, drawn by ns.page.RenderGroups --
-- the same function the body uses, so a member's cards look and behave
-- exactly as they would on a page of their own.
local TREE_W, TREE_H, TREE_MIN_H = 180, 420, 200

-- The splitter's grab strip, and what a dragged column may never be: too
-- narrow to read a name in, or wide enough to leave the pane a sliver.
local TREE_SPLIT_W  = 5
local TREE_W_MIN    = 120
local TREE_PANE_MIN = 260

-- Where a reader's own column widths live: keyed by the tree's route, in
-- the table the consuming addon hands NewApp for the panel's geometry --
-- which is what this is. A width the reader dragged is part of where they
-- left the panel, exactly as the rail's width is.
local function TreeWidths(app)
    local store = app.persist and app.persist()
    if not store then return nil end
    store.treeW = store.treeW or {}
    return store.treeW
end

-- The column width to lay out at: the reader's, else the declaration's,
-- else the default -- clamped so the pane always has room to be a page.
-- Clamped on the way OUT as well as at the drag, so a width stored by a
-- wider panel cannot survive into a narrower one.
local function TreeWidth(app, key, spec, cardW)
    local want = spec.width or TREE_W
    local wid  = TreeWidths(app)
    if wid and key and wid[key] then want = wid[key] end
    local hi = math.max(TREE_W_MIN, (cardW or 0) - TREE_PANE_MIN)
    return math.max(TREE_W_MIN, math.min(hi, want))
end

local function TreeRouteKey(app, group)
    local r = group.tree and group.tree.route
    if type(r) == "function" then r = r(app) end
    return type(r) == "string" and r or nil
end

-- The card's list, pane and divider are the card FRAME's own furniture,
-- built once and kept -- and the frame is pooled. A card that was a tree
-- group on one page comes back as an ordinary card on the next, so
-- whatever is not laid out here has to be put away here, or the last
-- page's list column and its divider draw straight through this page's
-- fields.
-- Takes `app` as well as the card: the pane's tab strip is put away here
-- too, and returning its buttons to the pool needs the app that owns it.
local function HideTreeFurniture(app, g)
    -- The pane's tab strip goes with the rest of it. Its buttons are the
    -- card's, like the list's rows, and a card that is not a tree group
    -- must not still be showing a strip of routes into one.
    if g.treeTabNav then ns.nav.HideTabStrip(app, g.treeTabNav) end
    if g.treeList then g.treeList:Hide() end
    if g.treePane then g.treePane:Hide() end
    if g.treePaneBand then g.treePaneBand:Hide() end
    if g.treeRail then g.treeRail:Hide() end
    if g.treeHead then g.treeHead:Hide() end
    -- The splitter with them: a grab strip over a card that is no longer a
    -- tree group is an invisible button that resizes something not there.
    if g.treeSplit then
        g.treeSplit:SetScript("OnUpdate", nil)
        g.treeSplit.dragging = nil
        g.treeSplit:Hide()
    end
end

-- `avail` is the viewport height left below the card's header, for
-- height = "fill"; nil means "unknown", which falls back to the minimum.
-- ── The pane, on its own ───────────────────────────────────────
--
-- Everything inside a tree group's right-hand pane: the member page's own
-- groups (the fixed head), the subtab strip, the scrolling groups below
-- it, and the pane's corner X. Called by LayoutTreeGroup as part of a full
-- render, and by ns.page.ScheduleRender on its own when a write landed in
-- this pane and nowhere else.
--
-- ONE function with two callers on purpose. The two paths cannot drift
-- into drawing the pane differently, which is the failure a second
-- "refresh the pane" routine invites.
--
-- WHY A PANE MAY BE DRAWN ALONE. LayoutTreeGroup takes the card's height
-- from `spec.height` or the viewport (`avail`) and its list column from
-- `spec.width` -- never from anything in here. So no amount of content in
-- the pane can change the card's height, the list's width, the page body's
-- total height, or the gutter decision that follows from it: the pane
-- scrolls inside a box whose size was settled before it drew. Should
-- `tree.height` ever gain a content-dependent mode, that mode must mark
-- itself on g.bpTree and ns.page.ScheduleRender must route it to a full
-- render.
--
-- Reads the route FRESH rather than trusting anything captured: between a
-- flip and the frame this runs on, the reader may have moved.
local function RenderPaneContent(app, g)
    local t = g.bpTree
    if not t then return end
    local ctx      = t.ctx
    local key      = t.key
    local paneW    = t.paneW
    local routeKey = table.concat(app.route or {}, "/")

    -- Every widget built below is stamped with the pane's scope, which is
    -- what lets ns.page.ReleaseScope give exactly these back later. Saved
    -- and restored rather than cleared: a full render is drawing the page
    -- around this call and its own scope has to survive it.
    local prevScope = app.bpScope
    app.bpScope = t.scope
    local prevHiddenMemo = app.bpHiddenNow
    app.bpHiddenNow = prevHiddenMemo or {}
    -- The dimmed set, rebuilt at the start of the OUTERMOST pass and then
    -- LEFT STANDING. Unlike the hidden memo it must outlive the render:
    -- a control asks ns.IsDisabled again at CLICK time, which is between
    -- renders, and a set torn down with the pass would answer "not
    -- dimmed" exactly then -- grayed controls that still take the click.
    -- A nested pass shares the outer one's table (same frame, same
    -- declaration); the depth count is what tells the two apart.
    app.bpDimDepth = (app.bpDimDepth or 0) + 1
    if app.bpDimDepth == 1 then app.bpDimmed = {} end

    -- WHERE THE PANE IS PARKED -- kept ON THE APP, keyed by the tree's
    -- route, beside app.groupNavs and for exactly the
    -- same reason: the CARD is pooled.
    --
    -- Two things move it. Re-pointing a ScrollFrame makes the engine
    -- re-evaluate its range and drop the offset, and this function
    -- re-points g.treeScroll; and a full render returns every card to the
    -- pool, which is LIFO, so the tree comes back in a DIFFERENT frame
    -- whose scroll frame is at zero. State kept on the card survives the
    -- first and not the second, which is why toggling a setting in the
    -- scrolling part still threw the reader back to the top.
    --
    -- The live frame wins when it is the one we rendered into last time --
    -- the reader may have used the wheel since -- and the stored value
    -- otherwise, which is the case a pooled card lands in. The stored value
    -- is kept current by the scroll frame's OnVerticalScroll hook (see
    -- LayoutTreeGroup), not only by the end of this render: a full render
    -- straight after a wheel used to restore the offset of the render
    -- BEFORE the wheel, which threw the reader back to the top.
    app.paneScroll = app.paneScroll or {}
    local st = app.paneScroll[key]
    if not st then st = {}; app.paneScroll[key] = st end
    -- The frame must still be showing THIS key, not merely be the same
    -- frame. A pooled card serves one pane and then another: `st.frame == g`
    -- alone was true even after the card had been handed to a different
    -- tree, so this pane's remembered offset was discarded in favour of the
    -- live offset of somebody else's pane.
    local keepScroll = (st.frame == g and g.bpPaneLastKey == key)
                       and (g.treeScroll:GetVerticalScroll() or 0)
                       or (st.y or 0)

    local page
    -- The member the pane is showing, and which of its subtabs (if it has
    -- any) the route names. A route on a TAB is a route on its member.
    local memberEntry, memberNode, tabId
    if routeKey ~= key and ns.nav.RouteWithin(routeKey, key) then
        local entry = app.routeIndex and app.routeIndex[routeKey]
        local node  = entry and entry.node
        local coll  = node and node.bpCollection
        if coll and node.bpMember then
            page = ns.collections.MemberPage(app, coll, node.bpMember.key)
            if node.bpTab then
                tabId = node.bpTab.id
                local mk = entry.parent
                memberEntry = mk and app.routeIndex[mk]
                memberNode  = memberEntry and memberEntry.node
            else
                memberEntry, memberNode = entry, node
            end
        elseif node then
            page = ns.page.Resolve(app, entry)
        end
    end

    -- THE PANE'S OWN ATTACHMENTS.
    --
    -- The member page's declarations again, against the pane this time --
    -- the library's corner X asks for a zone only the pane publishes (see
    -- Attach.lua), so the card render skips it and this draws it. Nothing
    -- is duplicated: a spec is drawn by whichever host publishes its zone,
    -- and by only one of them.
    if page and page.groups and page.groups[1] then
        ns.attach.BuildAll(app, "pane", g.treePane, page.groups[1], nil,
                           { app = app, db = (page.db and page.db()) or ctx.db,
                             page = page, bpScope = t.scope })
    end

    g.treeContent:SetWidth(paneW)

    -- THE MEMBER'S SUBTABS, when its collection declares memberTabs.
    --
    -- The pane then has three parts, top to bottom: the page's own groups
    -- (the header -- what stays put whichever tab is showing), the strip,
    -- and the selected tab's groups in the scrolling part below. The first
    -- two are FIXED at the top of the pane, exactly as a classic tab group
    -- kept a member's name and its tab row above the scrolling body.
    --
    -- The tabs the strip shows are the member's child ROUTES -- what
    -- ns.collections.MemberTabs minted, hidden ones already left out -- so
    -- the strip and the routes cannot disagree about what exists. With the
    -- route on the member itself, the first tab shows.
    local tabKids = memberNode and memberEntry and page and page.tabs
                    and ns.nav.KidsAt(app, memberEntry.key, memberNode) or nil
    if tabKids and #tabKids == 0 then tabKids = nil end
    local fixedH = 0
    if tabKids then
        if not g.treeHead then
            g.treeHead = CreateFrame("Frame", nil, g.treePane)
        end
        g.treeHead:ClearAllPoints()
        g.treeHead:SetPoint("TOPLEFT",  g.treePane, "TOPLEFT",  0, 0)
        g.treeHead:SetWidth(paneW)
        -- The head is NOT the scroll frame -- it is a child of the pane, so
        -- a band in it may run the pane's whole width. Its cards are still
        -- packed for paneW, so nothing reflows; only a band's own edges
        -- reach further, which is what makes the strip meet the card.
        g.treeHead.bpBandBleed = ns.SCROLLBAR_GUTTER
        g.treeHead:Show()
        local pctx  = { app = app, db = (page.db and page.db()) or ctx.db,
                        page = page, bpScope = t.scope }
        local drawn = ns.page.DrawnGroups(app, page.groups, pctx)
        local headH = ns.page.RenderGroups(app, g.treeHead, drawn, pctx, paneW, page)
        g.treeHead:SetHeight(math.max(headH, 1))

        if not tabId then tabId = tabKids[1].id end
        local items = {}
        for i, kid in ipairs(tabKids) do
            local path = {}
            for j, id in ipairs(memberEntry.path) do path[j] = id end
            path[#path + 1] = kid.id
            items[i] = { key = table.concat(path, "/"), title = kid.title,
                         path = path, node = kid, selected = (kid.id == tabId) }
        end
        -- Cached ON THE CARD, not per route on the app.
        --
        -- Keyed by route it had the tree list's own bug: the buttons are
        -- parented to g.treePane, and a pooled card came back showing the
        -- last strip drawn into it -- live TabOnClick handlers and all --
        -- underneath whichever strip the new page then drew. One card, one
        -- strip, by construction. There is no per-route state here to keep:
        -- which tab is selected comes from the route itself.
        local tnav = g.treeTabNav
        if not tnav then tnav = {}; g.treeTabNav = tnav end
        local stripH = ns.nav.RenderTabStripInto(app, tnav, g.treePane, items,
            { top = headH, width = paneW, inset = PAGE_INSET,
              -- The strip's rule is drawn in the PANE, so it reaches the
              -- card's inner edge rather than stopping at the reserved
              -- gutter -- the same bleed the bands above it take.
              bleed = ns.SCROLLBAR_GUTTER,
              style = (memberNode.tabStyle ~= nil) and memberNode.tabStyle
                      or (memberEntry.node.bpCollection
                          and memberEntry.node.bpCollection.tabStyle) })
        fixedH = headH + stripH
    else
        if g.treeHead then g.treeHead:Hide() end
        ns.nav.HideTabStrip(app, g.treeTabNav)
    end
    -- The scrolling part starts under whatever is fixed above it -- and is
    -- re-anchored ONLY when that changes (a strip appearing, a head that
    -- grew). An unconditional SetPoint is what made the pane jump: see the
    -- note on keepScroll above.
    --
    -- ALSO when this pooled card last served a DIFFERENT tree. `st` is per
    -- route and `st.frame == g` only says the frame is the same object;
    -- after the card hosted another tree (a container's Assigned Buffs,
    -- say) its scroll frame carries that tree's offset, and an equal
    -- fixedH skipped the SetPoint -- the scrolling content then sat over
    -- the fixed head and covered the per-Layout strip's controls while
    -- the band beneath stayed visible (owner report: an empty strip on
    -- one Buff List entry, fixed by clicking another).
    if st.fixedH ~= fixedH or st.frame ~= g or g.bpPaneLastKey ~= key then
        st.fixedH = fixedH
        g.treeScroll:SetPoint("TOPLEFT", g.treePane, "TOPLEFT", 0, -fixedH)
    end

    -- What scrolls: the selected tab's groups, or -- with no tabs -- the
    -- whole page.
    local groups = page and page.groups
    if tabKids then
        groups = ns.collections.TabGroups(page, tabId)
    end
    if page and groups then
        local pctx = { app = app, db = (page.db and page.db()) or ctx.db,
                       page = page, bpScope = t.scope }
        local drawn = ns.page.DrawnGroups(app, groups, pctx)
        local used = ns.page.RenderGroups(app, g.treeContent, drawn, pctx, paneW, page)
        g.treeContent:SetHeight(math.max(used, 1))
        g.treeScroll.contentHeight = used
    else
        g.treeContent:SetHeight(1)
        g.treeScroll.contentHeight = 0
    end
    -- BACK WHERE IT WAS -- unless this is different content.
    --
    -- The same rule the page body uses (see ns.page.Render, which zeroes
    -- app.scroll when the ROUTE changes and leaves it alone otherwise): a
    -- new member or a new subtab starts at the top, because it is not the
    -- thing the reader had scrolled; a re-render of what is already on
    -- screen keeps their place. Clamped to what the pane now holds, so an
    -- offset from a taller version of the same page cannot park it past
    -- the end.
    local at = routeKey .. "|" .. tostring(tabId)
    if st.at ~= at then
        st.at = at
        keepScroll = 0
    end
    -- The viewport from the two numbers this render SET -- the pane's own
    -- height and what is fixed above the scrolling part -- rather than the
    -- scroll frame's, which comes from anchors resolved after this returns.
    local view = math.max(0, (g.treePane:GetHeight() or 0) - fixedH)
    local maxScroll = math.max(0, (g.treeScroll.contentHeight or 0) - view)
    keepScroll = math.max(0, math.min(keepScroll, maxScroll))
    g.treeScroll:SetVerticalScroll(keepScroll)
    st.y, st.frame = keepScroll, g
    -- Which pane this card is currently showing, so the next render can
    -- tell "the same card, still on this pane" from "the same card, reused".
    g.bpPaneLastKey = key

    if g.treeScroll.scrollbar then g.treeScroll.scrollbar:Update() end

    app.bpScope, app.bpHiddenNow = prevScope, prevHiddenMemo
    app.bpDimDepth = (app.bpDimDepth or 1) - 1
end
-- Published for ns.page.ScheduleRender, which is declared far above this
-- line.
ns.page.RenderPane = RenderPaneContent

local function LayoutTreeGroup(app, g, group, preset, ctx, width, avail)
    local spec = group.tree or {}
    local pad  = preset.padding
    local key  = TreeRouteKey(app, group)
    local h    = spec.height
    if h == "fill" then
        h = math.max(spec.minHeight or TREE_MIN_H, math.floor(avail or 0))
        -- Sized from the viewport, so the viewport's HEIGHT now matters to
        -- this page -- see the scroll frame's OnSizeChanged in Render.
        app.pageHasFill = true
    end
    h = h or TREE_H
    -- The reader's own column width wins over the declaration: a width
    -- they dragged is a decision, and the declaration is only the default
    -- it started from. Clamped here as well as at the drag, so a width
    -- stored by a wider panel cannot survive into a narrower one.
    local listW = TreeWidth(app, key, spec, width)
    -- No route to list: the card draws no furniture and hosts no pane, so
    -- it must not still CLAIM one -- a stale claim would have
    -- ns.page.ScheduleRender redraw a pane this card no longer has.
    -- No route to list -- and that includes a route the index does not
    -- hold, not only a card that declared none.
    --
    -- RenderTreeInto returns without drawing anything when the key is not
    -- in the index, and the furniture below is shown BEFORE it is called.
    -- So a card whose route had gone drew its list, drew nothing into it,
    -- and left on screen whatever the last tree to use that surface had put
    -- there. Asking the question here, where the card can decline to be a
    -- tree at all, is the only place that cannot be half-answered.
    if not (key and app.routeIndex and app.routeIndex[key]) then
        if g.bpTree and app.paneScopes then app.paneScopes[g.bpTree.scope] = nil end
        g.bpTree = nil
        HideTreeFurniture(app, g)
        return h
    end

    -- Built once per card frame and reused: these are the card's own
    -- furniture, not pooled widgets, and the tree caches its rows against
    -- the frame it was last drawn in.
    if not g.treeList then
        g.treeList = CreateFrame("Frame", nil, g.body)
        -- The rule between the list and the pane. A plain texture rather
        -- than Frame.lua's EdgeLine, which is file-local to that file.
        g.treeEdge = g.treeList:CreateTexture(nil, "ARTWORK")
        g.treeEdge:SetWidth(1)
        -- The band behind the list, in the frame rail's own color, so an
        -- in-page tree reads as the same furniture as the navigator's rail.
        -- A frame of its own because RoundedFill fills a frame, and BELOW
        -- the list, so the rows and the rule draw over it.
        g.treeRail = CreateFrame("Frame", nil, g.body)
        g.treeRailPaint, g.treeRailRadius, g.treeRailInset, g.treeRailSides =
            ns.RoundedFill(g.treeRail, "BACKGROUND", 8, "TR", app.skin.railBg, 0)
        -- The band behind the PANE, the mirror of the rail band above, in the
        -- PAGE's color rather than the card's. Without it the pane showed
        -- the host card's own surface -- and the member cards drawn in it are
        -- that same color, so the whole right-hand side read as one flat
        -- card with nothing on it. Its own frame, and BELOW the pane, for the
        -- same reason the rail's is: RoundedFill fills a frame, and the
        -- pane's cards have to draw over it.
        g.treePaneBand = CreateFrame("Frame", nil, g.body)
        g.treePaneBandPaint, g.treePaneBandRadius,
        g.treePaneBandInset, g.treePaneBandSides =
            ns.RoundedFill(g.treePaneBand, "BACKGROUND", 8, "L", app.skin.panelBg, 0)
        g.treePane = CreateFrame("Frame", nil, g.body)
        local sc = CreateFrame("ScrollFrame", nil, g.treePane)
        -- THE SCROLLBAR'S GUTTER, reserved inside the pane.
        --
        -- ns.AttachScrollBar hangs the bar off the scroll frame's RIGHT
        -- edge, two pixels clear of it -- so a scroll frame filling the pane
        -- puts its bar outside the pane, and once the pane runs flush to the
        -- card's border, outside the card.
        --
        -- Reserved whether or not the bar is showing, like the page body's
        -- own gutter and unlike the rail tree's. The page body can afford to
        -- decide per render because it re-packs at the new width; this pane
        -- draws real cards whose fields were packed for the width they were
        -- given, so a gutter that came and went would re-flow the whole pane
        -- every time the overflow crossed a line -- which is the jumping
        -- about on resize.
        sc:SetPoint("TOPLEFT",     g.treePane, "TOPLEFT",      0, 0)
        sc:SetPoint("BOTTOMRIGHT", g.treePane, "BOTTOMRIGHT", -ns.SCROLLBAR_GUTTER, 0)
        local content = CreateFrame("Frame", nil, sc)
        content:SetSize(1, 1)
        sc:SetScrollChild(content)
        sc:EnableMouseWheel(true)
        sc:SetScript("OnMouseWheel", function(self, delta)
            local maxs = math.max(0, (self.contentHeight or 0) - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxs, self:GetVerticalScroll() - delta * 40)))
        end)
        -- WHERE THE READER PARKED IT, recorded AS THEY SCROLL.
        --
        -- RenderPaneContent keeps the pane's offset on the app, keyed by the
        -- tree's route, because the card is pooled: a full render hands the
        -- tree a different frame most times, whose own scroll frame knows
        -- nothing. That record used to be written only at the end of a
        -- render, so a wheel or a bar drag between two renders was never in
        -- it -- and a setter that escalated to a full render (RefreshPage,
        -- Invalidate) put the pane back where the LAST RENDER had left it,
        -- usually the top. Every scroll -- wheel, bar, or the render's own
        -- SetVerticalScroll -- lands here, so the record is always current.
        -- Only while this frame is the live card for that route: a pooled
        -- frame, or one that has since been handed to another tree, must
        -- not write into a pane it no longer shows.
        sc:HookScript("OnVerticalScroll", function(self, offset)
            local t   = g.bpTree
            local key = t and t.key
            local st  = key and g.bpPaneLastKey == key
                        and app.paneScroll and app.paneScroll[key]
            if st and st.frame == g then
                st.y = offset or self:GetVerticalScroll() or 0
            end
        end)
        g.treeScroll, g.treeContent = sc, content
        ns.AttachScrollBar(sc, function() return app.skin end)

        -- THE SPLITTER. The rule between the list and the pane is a
        -- handle: a classic tree group's list is resizable by dragging its
        -- edge, and a reader who has met that expects it here.
        --
        -- Its own button over the rule rather than a mouse-enabled
        -- texture, and 5px wide: a splitter you cannot grab because a row
        -- is on top of it is no splitter, and one much wider steals clicks
        -- from the rows it sits beside. Modelled on the panel's own rail
        -- splitter (Frame.lua), which does exactly this for the rail.
        local sp = CreateFrame("Button", nil, g.body)
        sp:SetWidth(TREE_SPLIT_W)
        sp.line = sp:CreateTexture(nil, "OVERLAY")
        sp.line:SetWidth(1)
        sp.line:SetPoint("TOPLEFT",    sp, "TOPLEFT",    2, 0)
        sp.line:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 2, 0)
        sp.line:Hide()
        g.treeSplit = sp
    end

    g.treeList:ClearAllPoints()
    g.treeList:SetPoint("TOPLEFT", g.body, "TOPLEFT", pad, 0)
    g.treeList:SetSize(listW, h)
    g.treeList:Show()

    -- The rail band and the rule run the full height of the card's INSIDE,
    -- not the body's: the body starts `padding` below the header rule and
    -- stops `padBottom` above the bottom border, and that is exactly the
    -- small gap that showed at either end of the rule. Two pixels short at
    -- the top when there is a header, so the header's own rule stays
    -- visible; one short at the other end, to sit inside the border.
    local headH      = group.title and preset.headerH or 0
    local padBottom  = preset.padBottom or preset.padding
    local overTop    = math.max(pad - (headH > 0 and 2 or 1), 0)
    local overBottom = math.max(padBottom - 1, 0)

    do
        local d = app.skin.divider
        g.treeEdge:ClearAllPoints()
        g.treeEdge:SetPoint("TOPRIGHT",    g.treeList, "TOPRIGHT",     0,  overTop)
        g.treeEdge:SetPoint("BOTTOMRIGHT", g.treeList, "BOTTOMRIGHT",  0, -overBottom)
        g.treeEdge:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
        if ns.NoSnap then ns.NoSnap(g.treeEdge) end
    end

    -- ── The splitter, over that rule ──
    --
    -- The drag RESIZES IN PLACE and re-renders only when it is let go.
    -- Following the cursor by moving three anchors is a few frames' work;
    -- re-packing the pane's cards at a new width on every one of those
    -- frames is not, and classic tree groups do the same -- they size the
    -- frame live and lays the content out on mouse-up.
    if g.treeSplit then
        local sp = g.treeSplit
        sp:SetParent(g.body)
        sp:ClearAllPoints()
        sp:SetPoint("TOP",    g.treeList, "TOPRIGHT",    0,  overTop)
        sp:SetPoint("BOTTOM", g.treeList, "BOTTOMRIGHT", 0, -overBottom)
        sp:SetWidth(TREE_SPLIT_W)
        sp:SetFrameLevel(g.body:GetFrameLevel() + 6)
        sp:Show()

        local function paint(hot)
            if not hot then sp.line:Hide(); return end
            local c = app.skin.accent
            sp.line:SetColorTexture(c[1], c[2], c[3], 0.9)
            if ns.NoSnap then ns.NoSnap(sp.line) end
            sp.line:Show()
        end

        -- Everything the drag needs, re-stated per render rather than
        -- captured once: the card is pooled, so a closure built on the
        -- first render would be answering for a different page by the
        -- fifth. `bpKey` is the tree whose width is being changed.
        sp.bpKey, sp.bpPad, sp.bpH, sp.bpCardW = key, pad, h, width
        sp.bpApp = app

        local function follow(self)
            local x = GetCursorPosition() / (g.body:GetEffectiveScale() or 1)
            local left = g.body:GetLeft()
            if not left then return end
            local hi = math.max(TREE_W_MIN, (self.bpCardW or 0) - TREE_PANE_MIN)
            local w  = math.max(TREE_W_MIN,
                       math.min(hi, (x - left) - self.bpPad - self.grabOff))
            w = math.floor(w + 0.5)   -- whole pixels: the column edge is a border
            if w == (self.bpW or 0) then return end
            self.bpW = w
            -- The three frames the column's width decides. Nothing is
            -- packed or built here -- see the note above.
            g.treeList:SetSize(w, self.bpH)
            g.treeRail:SetWidth(w)
            g.treePane:ClearAllPoints()
            g.treePane:SetPoint("TOPLEFT",  g.treeList, "TOPRIGHT",  0, 0)
            g.treePane:SetPoint("TOPRIGHT", g.body,     "TOPRIGHT", -1, 0)
            g.treePane:SetHeight(self.bpH)
        end

        sp:SetScript("OnEnter", function(self) paint(true) end)
        sp:SetScript("OnLeave", function(self) if not self.dragging then paint(false) end end)
        sp:SetScript("OnMouseDown", function(self)
            local x    = GetCursorPosition() / (g.body:GetEffectiveScale() or 1)
            local left = g.body:GetLeft()
            self.bpW      = g.treeList:GetWidth() or listW
            -- Where in the strip the reader grabbed, so the column does
            -- not jump to the cursor on the first frame.
            self.grabOff  = (left and (x - left) or 0) - self.bpPad - self.bpW
            self.dragging = true
            paint(true)
            self:SetScript("OnUpdate", follow)
        end)
        sp:SetScript("OnMouseUp", function(self)
            if not self.dragging then return end
            self:SetScript("OnUpdate", nil)
            self.dragging = nil
            paint(self:IsMouseOver())
            local wid = TreeWidths(self.bpApp)
            if wid and self.bpKey then
                wid[self.bpKey] = math.floor((self.bpW or 0) + 0.5)
            end
            -- NOW the work: the pane's cards are packed for a width that
            -- has changed, and the list's rows are laid out for one too.
            ns.page.Render(self.bpApp)
        end)
    end

    -- A card with no header rounds its top-left corner too, so the band
    -- keeps that corner round and squares only the two on the right.
    g.treeRail:SetFrameLevel(g.body:GetFrameLevel())
    g.treeList:SetFrameLevel(g.body:GetFrameLevel() + 2)
    g.treeRail:ClearAllPoints()
    g.treeRail:SetPoint("TOPLEFT",     g.body,     "TOPLEFT",      1,  overTop)
    g.treeRail:SetPoint("BOTTOMRIGHT", g.treeList, "BOTTOMRIGHT",  0, -overBottom)
    g.treeRailSides(headH > 0 and "TR" or "R")
    g.treeRailRadius(preset.radius or 8)
    g.treeRailPaint(app.skin.railBg)
    g.treeRail:Show()

    -- The pane's band, over the same inside of the card the rail band covers
    -- -- so the two together fill it and no strip of card color is left
    -- above, below or beside them. Squared along the left, where it meets the
    -- rule, and at the top when there is a header; the card's own corners on
    -- the right stay round.
    g.treePaneBand:SetFrameLevel(g.body:GetFrameLevel())
    g.treePaneBand:ClearAllPoints()
    g.treePaneBand:SetPoint("TOPLEFT",     g.treeList, "TOPRIGHT",     0,  overTop)
    g.treePaneBand:SetPoint("BOTTOMRIGHT", g.body,     "BOTTOMRIGHT", -1, -overBottom)
    g.treePaneBandSides(headH > 0 and "TL" or "L")
    g.treePaneBandRadius(preset.radius or 8)
    g.treePaneBandPaint(app.skin.panelBg)
    g.treePaneBand:Show()

    -- The pane is FLUSH with the rule and with the card's inner right edge,
    -- and its cards take their own margin from PAGE_INSET -- exactly the
    -- arrangement the page body has, where a BAND runs to the region's
    -- edges and a card does not. Insetting the pane by `pad` instead put a
    -- margin OUTSIDE every card in it, which a band cannot cross: a strip's
    -- rules stopped short of the tree's rule rather than meeting it.
    g.treePane:ClearAllPoints()
    g.treePane:SetPoint("TOPLEFT",  g.treeList, "TOPRIGHT",  0, 0)
    g.treePane:SetPoint("TOPRIGHT", g.body,     "TOPRIGHT", -1, 0)
    g.treePane:SetHeight(h)
    g.treePane:Show()
    -- The card this pane is in, for the corner attachment: it hangs off
    -- the card's own border corner rather than the pane's top edge, which
    -- sits a padding lower. See ns.attach's pane_topRight.
    g.treePane.bpCard = g

    ns.nav.RenderTreeInto(app, g.treeList, key, spec.listTopPad)

    -- Landed on the collection ITSELF: select its first row.
    --
    -- ns.nav.Navigate descends through a tree-group collection, so a click
    -- on the tab or the rail row already lands on a member. A route can
    -- arrive here without passing through Navigate, though -- restored from
    -- saved variables, or left behind when a member was removed -- and that
    -- is a list beside an empty pane with nothing lit. Deferred by a frame
    -- because this runs inside a render: navigating re-renders, and doing
    -- that from within the layout would re-enter it.
    local routeKey = table.concat(app.route or {}, "/")
    if routeKey == key and not app.treeAutoPick then
        local rootEntry = app.routeIndex and app.routeIndex[key]
        local kids  = rootEntry and ns.nav.KidsAt(app, key, rootEntry.node)
        local first = kids and kids[1]
        local path
        if first then
            path = {}
            for i, id in ipairs(rootEntry.path) do path[i] = id end
            path[#path + 1] = first.id
            -- Only a route that EXISTS. Navigate answers false for one that
            -- does not, which would leave the route at the root and have
            -- the next render schedule the same doomed hop again.
            if not app.routeIndex[table.concat(path, "/")] then path = nil end
        end
        if path and C_Timer then
            app.treeAutoPick = true
            C_Timer.After(0, function()
                app.treeAutoPick = nil
                ns.nav.Navigate(app, path)
            end)
        end
    end

    -- WHAT THE PANE NEEDS, kept on the card so the pane can be redrawn on
    -- its own. `key` rather than the frame, because the frame is pooled and
    -- is a different object most renders while the route key is not.
    g.bpTree = { key   = key,
                 scope = "pane:" .. key,
                 -- The pane's content is as wide as the scroll frame, which
                 -- is the pane less the gutter reserved for the bar. The
                 -- same arithmetic the anchors use, so the cards are packed
                 -- for the width they actually get.
                 paneW = math.max((width - listW - pad - 1 - ns.SCROLLBAR_GUTTER), 1),
                 -- Only for the `ctx.db` fallback: a member page that
                 -- declares no db of its own reads the card's.
                 ctx   = ctx }
    app.paneScopes = app.paneScopes or {}
    app.paneScopes[g.bpTree.scope] = g

    RenderPaneContent(app, g)

    return h
end

-- Which of a page's groups draw at all, settled BEFORE anything is
-- acquired -- see the note at the call site in ns.page.Render.
function ns.page.DrawnGroups(app, groups, ctx)
    local drawn = {}
    for gi, group in ipairs(groups or {}) do
        if group.subtabs then
            -- An IN-PAGE subtab strip. It expands here, before anything is
            -- acquired, into a strip marker followed by the selected tab's
            -- groups -- so the tab's cards lay out in the page flow exactly
            -- as ordinary cards, below the strip.
            local tabs = group.subtabs
            if type(tabs) == "function" then tabs = tabs(ctx) end
            if type(tabs) == "table" and tabs[1] then
                local key = group.subtabKey or ("subtabs:" .. tostring(gi))
                app.pageSubtabs = app.pageSubtabs or {}
                local sel = app.pageSubtabs[key]
                -- A LIVE SEARCH PICKS THE TAB. The index knows which tab
                -- each field is on, so a query whose match is on a tab the
                -- reader is not looking at opens that tab rather than
                -- lighting a strip with nothing lit under it. The reader's
                -- own choice is not overwritten -- pageSubtabs is left
                -- alone, so clearing the query puts the tab back.
                local hit = app.searchSubtabs and app.searchSubtabs[key]
                if hit then sel = hit end
                local seltab
                for _, tb in ipairs(tabs) do if tb.id == sel then seltab = tb end end
                if not seltab then
                    seltab = tabs[1]; sel = seltab.id; app.pageSubtabs[key] = sel
                end
                drawn[#drawn + 1] = { strip = { key = key, tabs = tabs, sel = sel,
                                                style = group.subtabStyle,
                                                -- `pinned` on the group pins
                                                -- the STRIP, not the tab's
                                                -- cards: the chooser stays
                                                -- put and what it chose
                                                -- scrolls under it.
                                                pinned = group.pinned },
                                      index = gi }
                local tgroups = seltab.groups
                if type(tgroups) == "function" then tgroups = tgroups(ctx) end
                for _, tg in ipairs(tgroups or {}) do
                    if GroupShown(app, tg, ctx) then
                        drawn[#drawn + 1] = { group = tg, index = gi }
                        if type(tg.hidden) == "function" then NoteDynamic(app) end
                    else
                        NoteDynamicGroup(app, tg)
                    end
                end
            end
        elseif GroupShown(app, group, ctx) then
            drawn[#drawn + 1] = { group = group, index = gi }
            if type(group.hidden) == "function" then NoteDynamic(app) end
        else
            NoteDynamicGroup(app, group)
        end
    end
    return drawn
end


-- ── Drawing a list of groups into a frame ──────────────────────
--
-- The page body is one caller of this; a GROUP that hosts page content
-- inside itself -- the tree group, whose right-hand pane is a page of its
-- own -- is the other. Nothing here knows which: it takes a host frame and
-- a width, lays the groups down it, and returns how tall they came out.
--
-- `drawn` is the already-filtered list from ns.page.DrawnGroups, so that
-- the "does this group draw at all" question is asked once, before
-- anything is acquired, exactly as it was when this was one function.
function ns.page.RenderGroups(app, host, drawn, ctx, width, page)
    local skin = app.skin
    local y = 0
    for _, entry in ipairs(drawn) do
        if entry.strip then
            -- The in-page tab row, drawn in the page flow at the current y.
            -- Its selected tab's cards were already spliced in after it by
            -- DrawnGroups, so they render as ordinary cards below. Clicking a
            -- tab remembers the choice and re-renders.
            local st = entry.strip
            app.pageStripNav = app.pageStripNav or {}
            local items = {}
            for i, tb in ipairs(st.tabs) do
                local id = tb.id
                items[i] = { key = st.key .. "/" .. id, title = tb.title,
                             selected = (id == st.sel),
                             onSelect = function()
                                 app.pageSubtabs = app.pageSubtabs or {}
                                 app.pageSubtabs[st.key] = id
                                 app:RefreshPage()
                             end }
            end
            local stripH = ns.nav.RenderTabStripInto(app, app.pageStripNav,
                host, items, { top = y, width = width, inset = PAGE_INSET,
                               style = st.style })
            y = y + stripH + GROUP_GAP
        else
        local group, gi = entry.group, entry.index
        local preset = ResolvePreset(app, group.preset)
        local band   = preset.dividers and true or false

        -- `flush = true`: no gap above this card.
        --
        -- The gap is added AFTER each card rather than before the next one,
        -- because the last card's trailing gap is real -- a page ends with
        -- it, and the tree group's height = "fill" arithmetic subtracts it
        -- by name. So flush takes the previous card's gap back rather than
        -- declining to add one, which leaves both of those untouched.
        --
        -- What it is for: a card that belongs to the one above it. A strip
        -- of filters and the list those filters act on are one control
        -- surface, and a gap between them says they are two.
        --
        -- `flush` may also be a NUMBER: the gap it keeps INSTEAD of the
        -- page's, for two cards that belong together but must not touch --
        -- a strip and the list it filters, which read as one surface with a
        -- hairline between them rather than as one welded block.
        if group.flush and y >= GROUP_GAP then
            local keep = (type(group.flush) == "number") and group.flush or 0
            if keep > GROUP_GAP then keep = GROUP_GAP end
            y = y - GROUP_GAP + keep
        end

        local g = app:Acquire("group", GroupFactory)
        g:SetParent(host)
        g:ClearAllPoints()
        -- A BAND takes no margin at all: it runs to the region's edges,
        -- the rail on one side and the panel border on the other, because
        -- a rule that stops short of both is a card without a card's shape.
        -- Every other card keeps the page's margin.
        --
        -- A host may hold back space at its right edge that a BAND should
        -- still cross: the tree pane reserves the scrollbar's gutter whether
        -- or not the bar is showing, so a strip drawn in it stopped a gutter
        -- short of the card's inner edge and left a notch where its rules
        -- should have met it. `bpBandBleed` on the host is how much of that
        -- reserve a band may take back; cards keep the margin either way.
        local bleed = (band and host.bpBandBleed) or 0
        local inset = band and 0 or PAGE_INSET
        g:SetPoint("TOPLEFT",  host, "TOPLEFT",   inset, -y)
        g:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset + bleed, -y)
        g:Show()

        -- Preset first, skin second -- see ns.PresetColor.
        local cBody   = ns.PresetColor(preset, skin, "bodyBg")
        local cBorder = ns.PresetColor(preset, skin, "border")
        local cHeadBg = ns.PresetColor(preset, skin, "headerBg")
        local cHeadFg = ns.PresetColor(preset, skin, "headerFg")
        -- Which VARIANT of each shape is showing depends on the gate, so
        -- it is read here rather than further down: a collapsed tab has
        -- nothing beneath it and is rounded all round.
        local gate   = group.toggle
        local gateOn = true
        -- The switch's OWN state, which is not the same question as
        -- whether the body shows: a dimming card is off and open at once.
        local gateLit = true
        if gate and group.title then
            gateOn = gate.get and gate.get(group, ctx) and true or false
            gateLit = gateOn
            -- `toggle.dims`: stay open, and be dimmed below instead. For a
            -- card whose body says what the switch is FOR, collapsing
            -- takes the explanation away at the one moment the reader is
            -- most likely to want it.
            if gate.dims then gateOn = true end
        end
        -- A collapsed card lays nothing out either -- the same path, so the
        -- two cannot disagree about what "shut" costs. A gated card that is
        -- OFF is shut whatever the caret says -- and a collapse beats
        -- `dims` too: the reader asked for it directly, by the caret.
        local shut = IsCollapsed(app, group)
        if shut then gateOn = false end
        local tabNow = (preset.headerShape == "tab") and group.title

        -- A collapsed tab or plain heading has NO box at all: it sits
        -- above one, so leaving it behind draws a sliver of border under a
        -- collapsed heading.
        local plainNow = (preset.headerShape == "plain") and group.title
        local showBox  = gateOn or not (tabNow or plainNow)
        g.surface:SetShown(showBox)

        local paintBody, paintRing = g.paintBody, g.paintRing

        local headArt = (tabNow and not gateOn) and g.headerArt.shut
                        or g.headerArt.open
        g.headerArt.open.frame:SetShown(headArt == g.headerArt.open)
        g.headerArt.shut.frame:SetShown(headArt == g.headerArt.shut)
        local paintHeader, paintHeaderRing = headArt.fill, headArt.ring

        paintBody(cBody)
        -- `dividers` makes the card a BAND: no ring at all, and a rule
        -- across the top and the bottom instead, full width.
        local band = preset.dividers and true or false
        paintRing(band and cBody
                  or (preset.showBorder ~= false and cBorder or cBody))
        if band then
            local d = cBorder
            g.ruleTop:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
            g.ruleBottom:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
            if ns.NoSnap then ns.NoSnap(g.ruleTop); ns.NoSnap(g.ruleBottom) end
        end
        -- The corner patch, under a tab only.
        --
        -- Sized in PHYSICAL PIXELS, because the corner it is squaring off is:
        -- ns.RoundedFill draws its arcs r pixels across, so a patch measured
        -- in UI units covers more or less than the curve it is there to hide
        -- at every scale but 1 -- either a notch of the arc left showing or a
        -- square of border over the straight edge past it.
        local upx = (ns.PixelUnit and ns.PixelUnit(g)) or 1
        local cst = ns.BorderStroke("card")
        local pr  = preset.radius or 8
        g.patchRing:SetSize(pr * upx, pr * upx)
        local pb = math.max(pr - cst, 1)
        g.patchBody:SetSize(pb * upx, pb * upx)
        -- The body patch sits inside the ring patch by the card's own stroke,
        -- in the same pixels that stroke is drawn in.
        g.patchBody:ClearAllPoints()
        g.patchBody:SetPoint("TOPLEFT", g.surface, "TOPLEFT", cst * upx, -(cst * upx))
        g.patchRing:SetColorTexture(cBorder[1], cBorder[2], cBorder[3], cBorder[4] or 1)
        g.patchBody:SetColorTexture(cBody[1], cBody[2], cBody[3], cBody[4] or 1)
        g.patchRing:SetShown(tabNow and gateOn and true or false)
        g.patchBody:SetShown(tabNow and gateOn and true or false)

        -- THE CARET IS THE ONLY THING THAT COLLAPSES THE CARD.
        --
        -- The header used to flip it too (bpFlip, below), which made every
        -- click anywhere along the bar a collapse -- including the ones
        -- aimed at the header button, at the read-out, or at nothing in
        -- particular on the way to a drag. A card that folds up when you
        -- click near it is a card you cannot click near, so the bar now
        -- does nothing and the arrow does the one thing it advertises.
        --
        -- It still has to win the mouse: `headerHit` covers the whole bar,
        -- and a frame under it never sees a click -- the press goes to the
        -- header and starts a REORDER drag instead. The caret is above it
        -- on frame level, the way the header button is.
        --
        -- chevron.tga points RIGHT as authored, so a quarter turn each way
        -- gives down and up: SHUT points down (click to open, the body comes
        -- down), OPEN points up (click to fold it back up).
        if group.collapsible then
            local c = skin.textMuted
            g.caret.art:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            g.caret.art:SetRotation(shut and (-math.pi / 2) or (math.pi / 2))
            g.caret.bpApp, g.caret.bpGroup = app, group
            g.caret:SetScript("OnClick", function(self)
                SetCollapsed(self.bpApp, self.bpGroup,
                             not IsCollapsed(self.bpApp, self.bpGroup))
                if C_Timer then
                    C_Timer.After(0, function() ns.page.Render(self.bpApp) end)
                else
                    ns.page.Render(self.bpApp)
                end
            end)
            g.caret:SetScript("OnEnter", function(self)
                local a = self.bpApp.skin.accent
                self.art:SetVertexColor(a[1], a[2], a[3], 1)
            end)
            g.caret:SetScript("OnLeave", function(self)
                local m = self.bpApp.skin.textMuted
                self.art:SetVertexColor(m[1], m[2], m[3], m[4] or 1)
            end)
            g.caret:Show()
        else
            g.caret:Hide()
            g.caret:SetScript("OnClick", nil)
        end
        -- WHERE the caret sits is settled below, once the header button has
        -- been measured: it follows that button when one is showing, and the
        -- title when none is.
        -- The header's own action, while the card is shut.
        --
        -- Its spec may be a function, and its `text` may be too: the button
        -- reads "In Container: <name>", and a container renamed elsewhere
        -- should say so without this page rebuilding.
        local hb = group.headerButton
        if type(hb) == "function" then hb = hb(group, ctx) end
        local hbText = hb and hb.text
        if type(hbText) == "function" then hbText = hbText(group, ctx) end
        local showHB = (shut and hb and hbText and hbText ~= "") and true or false
        if showHB then
            g.headerBtn.text:SetText(hbText)
            g.headerBtn:SetWidth(math.ceil((g.headerBtn.text:GetStringWidth() or 40) + 16))
            -- Anchored in the render, not at creation: the title's own
            -- position moves with the header's shape (a gate, a grip), and
            -- the button follows whatever it turned out to be.
            g.headerBtn:ClearAllPoints()
            g.headerBtn:SetPoint("LEFT", g.title, "RIGHT", 10, 0)
            g.headerBtn.bpApp, g.headerBtn.bpSpec = app, hb
            g.headerBtn.bpCtx, g.headerBtn.bpGroup = ctx, group
            g.headerBtn.bpTitle = hbText
            local function paint(hovered)
                local sk = skin
                g.headerBtn.paintBody(sk.controlBg)
                g.headerBtn.paintRing(hovered and sk.accent or sk.controlBorder)
                local t = sk.text
                g.headerBtn.text:SetTextColor(t[1], t[2], t[3], 1)
            end
            paint(false)
            g.headerBtn:SetScript("OnClick", function(self)
                if self.bpSpec and self.bpSpec.onClick then
                    self.bpSpec.onClick(self.bpGroup, self.bpCtx)
                end
            end)
            g.headerBtn:SetScript("OnEnter", function(self)
                paint(true)
                local d = self.bpSpec and self.bpSpec.desc
                if type(d) == "function" then d = d(self.bpGroup, self.bpCtx) end
                if d then ns.context.Show(self, self.bpApp, self.bpTitle, d) end
            end)
            g.headerBtn:SetScript("OnLeave", function()
                paint(false)
                ns.context.Hide()
            end)
            g.headerBtn:Show()
        else
            g.headerBtn:Hide()
            g.headerBtn:SetScript("OnClick", nil)
        end

        -- The caret, right after whatever the card's name is followed by:
        -- the header button when one is showing, the title otherwise. Both
        -- anchors are relative, so it does not matter that the title itself
        -- is positioned further down.
        if group.collapsible then
            g.caret:ClearAllPoints()
            if showHB then
                g.caret:SetPoint("LEFT", g.headerBtn, "RIGHT", 6, 0)
            else
                g.caret:SetPoint("LEFT", g.title, "RIGHT", 8, 0)
            end
        end

        -- The hit area covers the whole bar now. It used to stop 26px short
        -- so the caret at the far end could take its own clicks; the caret
        -- has moved into the bar and wins on frame level instead, so the gap
        -- would only be a dead strip at the end of every collapsible card.
        g.headerHit:SetPoint("BOTTOMRIGHT", g.header, "BOTTOMRIGHT", 0, 0)

        g.ruleTop:SetShown(band and showBox)
        g.ruleBottom:SetShown(band and showBox)
        -- A TAB header is content-width and outlined; a BAND header spans
        -- the card and is not. The tab is painted below, once its width is
        -- known -- it depends on the title, which is set further down.
        -- Three header shapes:
        --   "bar"   a band across the card, filled       (the default)
        --   "tab"   content-width, outlined, above the box
        --   "plain" no fill and no outline, ABOVE the box: the heading
        --           stands clear of the card entirely, which is the
        --           quietest a heading can be while still being one
        local tab   = (preset.headerShape == "tab")
        local plain = (preset.headerShape == "plain")
        local CLEAR = { 0, 0, 0, 0 }
        -- A tab is ringed and its surface sits inside that ring; a band has
        -- no ring, so it paints the ring in its own color rather than
        -- leaving a 1px gutter of card around the header.
        paintHeader(plain and CLEAR or cHeadBg)
        paintHeaderRing(tab and cBorder or (plain and CLEAR or cHeadBg))

        -- A group with nothing matching fades as a unit, header included.
        -- Dimming only the fields inside it would leave a fully lit heading
        -- over an empty-looking card, which reads as a rendering fault
        -- rather than as "no matches here".
        local glit = (not ns.search) or ns.search.GroupMatches(app, group)
        g:SetAlpha(glit and 1 or ns.search.DimAlpha())
        g.headerHit.bpApp, g.headerHit.bpGroup, g.headerHit.bpCtx = app, group, ctx
        ns.context.AttachGroupTooltip(g.headerHit, app, group, ctx)
        -- Re-installed every render: a pooled card is reused for whatever
        -- comes next, including a card that must NOT be draggable.
        InstallGroupDrag(app, g, page, group, gi, ctx)
        g.header:SetHeight(group.title and preset.headerH or 0)
        g.header:SetShown(group.title ~= nil)
        -- The box starts under a tab and at the top for everything else.
        -- One pixel of overlap, so the tab's bottom edge and the box's top
        -- border are the same line rather than two a pixel apart.
        -- A TAB overlaps the box by a pixel, so its bottom edge and the
        -- box's top border are one line. A PLAIN heading has no edge to
        -- join, so the box simply starts under it.
        local boxTop = 0
        if group.title then
            if tab then boxTop = preset.headerH - 1
            elseif plain then boxTop = preset.headerH end
        end
        g.surface:ClearAllPoints()
        g.surface:SetPoint("TOPLEFT",     g, "TOPLEFT",      0, -boxTop)
        g.surface:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT",  0, 0)

        -- A band reaches both edges; a tab only its own left one, and its
        -- width is set after the title is measured.
        g.header:ClearAllPoints()
        if plain then
            -- Full width, flush with the card, and painted with nothing.
            g.header:SetPoint("TOPLEFT",  g, "TOPLEFT",  0, 0)
            g.header:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
        elseif tab then
            -- Flush with the card's left edge. The box's rounded top-left
            -- corner would show through beneath it -- see the patch below.
            g.header:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
        else
            -- Inside the card's stroke, which is ONE PHYSICAL PIXEL wide --
            -- so this offset is too. At one UI unit the band started a
            -- fraction of a pixel past the border's inner edge at any scale
            -- but 1, and the card's body color showed through the gap as a
            -- hairline along the top of every titled card.
            local hu = ((ns.PixelUnit and ns.PixelUnit(g)) or 1) * ns.BorderStroke("card")
            g.header:SetPoint("TOPLEFT",  g, "TOPLEFT",   hu, -hu)
            g.header:SetPoint("TOPRIGHT", g, "TOPRIGHT", -hu, -hu)
        end
        -- Marked like every other painted string. Group titles are already
        -- in the index -- searching one lights its fields -- so this only
        -- changes what is SHOWN, not what matches.
        ns.SetFontSize(g.title, preset.headerSize)
        g.title:SetText(ns.search.Mark(app, group.title or ""))
        g.title:SetTextColor(unpack(cHeadFg))

        -- ── The header's gate ──
        --
        -- A group may declare `toggle = { get, set }`: the setting the card
        -- is ABOUT moves into its header, and turning it off collapses the
        -- card to the header alone. Collapsed, not dimmed -- a page of
        -- half-lit cards is a page you still have to read past, and the one
        -- fact that matters ("this is off") is already in the switch.
        if gate and group.title then
            g.gate:Show()
            -- A GATE CAN BE DISABLED, like any other control: `toggle` takes
            -- the same `disabled` a field does -- "combat", or a predicate.
            -- It used to take none, so a card whose setting cannot be
            -- written in combat still offered a live-looking switch that
            -- silently refused (or, worse, wrote past a guard the bound
            -- field it replaced had).
            local gateOff = ns.IsDisabled(gate, ctx)
            g.gate:SetAlpha(gateOff and 0.4 or 1)
            -- ABOVE the header's own hit area, which covers the whole
            -- header and would otherwise take the mouse first: at equal
            -- frame levels the hit area wins by creation order, and a
            -- switch that cannot be hovered is a switch that looks dead.
            g.gate:SetFrameLevel(g.headerHit:GetFrameLevel() + 1)
            -- gateLit, not gateOn: a dimming card keeps its body open
            -- while the switch is off, and the switch must still read as
            -- off -- it is the one thing on the card saying so.
            local border = ns.PaintSwitchPill(g.gate.pill, app.skin, gateLit, false)
            -- Painted through the shared border contract rather than by
            -- setting the ring directly, so the switch lifts on hover like
            -- every other control in the panel instead of being the one
            -- thing that does not answer the cursor.
            ns.SetBorder(g.gate, g.gate.pill.ring)
            ns.MarkBorder(g.gate, app.skin, border, 1)
            -- `toggle.tooltip` names the SETTING ("Show Unit Tooltips"),
            -- which is what the header's title cannot say -- it names the
            -- section.
            ns.context.AttachToggleTooltip(g.gate, app, gate.tooltip, gate.desc)
            -- Both the switch and the header itself flip it: the header is
            -- already the card's handle, and a 36px target on a row that
            -- reads as one thing is a needless miss.
            local function flip()
                if gateOff then return end
                if gate.set then gate.set(group, ctx, not gateLit) end
                -- A card's gate is a SETTING, so it reports itself like
                -- one. It does not go through ns.Commit -- it has its own
                -- get/set on the group rather than a field's bind -- and
                -- so it was the one write on the panel that never reached
                -- the app's onWrite hook.
                if app.onWrite then app.onWrite(app, gate, ctx) end
                -- The card's SHAPE changes, so this is a re-render rather
                -- than a repaint -- deferred by a frame, because we are
                -- inside the click of a button the render will release.
                if C_Timer then
                    C_Timer.After(0, function() ns.page.Render(app) end)
                else
                    ns.page.Render(app)
                end
            end
            g.gate.bpFlip = flip
            g.headerHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            g.headerHit.bpFlip = flip
        elseif group.collapsible then
            -- A collapsible card's HEADER does nothing. The caret collapses
            -- it and the caret alone -- see the note in the caret block. A
            -- bar that folds the card away on any click is a bar you cannot
            -- click: not to press the header's own button, not to read the
            -- tooltip, and not to start the drag that reorders the card.
            g.gate:Hide()
            g.gate.bpFlip = nil
            g.headerHit:RegisterForClicks("RightButtonUp")
            g.headerHit.bpFlip = nil
        else
            g.gate:Hide()
            g.gate.bpFlip = nil
            g.headerHit:RegisterForClicks("RightButtonUp")
            g.headerHit.bpFlip = nil
        end
        -- The title steps aside for whichever the header is wearing.
        g.title:ClearAllPoints()
        g.title:SetPoint("LEFT", g.header, "LEFT",
            (gate and group.title) and (10 + ns.SWITCH_W + 8)
            or (g.bpReorderable and 24 or 11), 0)

        -- The heading's read-out, anchored AFTER the title is placed: it
        -- follows whatever the header turned out to be wearing. Its text
        -- may be a function, so a card can report a live value -- which
        -- specs are ticked -- without a row of its own to say it in.
        -- What the chrome was drawn WITH, kept on the frame so
        -- ns.page.RefreshGroupChrome can re-read the heading without a
        -- render. Cleared with everything else when the card is released.
        g.bpGroup, g.bpCtx = group, ctx
        g.bpScope = app.bpScope
        g.bpHeadSize, g.bpHeadFg = preset.labelSize, cHeadFg
        -- Anchored here, said here: the string's POSITION is the render's
        -- (it follows the title, which follows the header's shape) and its
        -- CONTENT is the chrome routine's, so a refresh and a render cannot
        -- disagree about what the heading reports.
        g.headerExtra:ClearAllPoints()
        -- After the CARET on a collapsible card: the arrow now sits between
        -- the name and the read-out, and two strings anchored to the same
        -- title would draw over each other.
        g.headerExtra:SetPoint("LEFT",
            (group.collapsible and g.caret) or g.title, "RIGHT", 10, 0)
        g.headerExtra:SetPoint("RIGHT", g.header, "RIGHT", -10, 0)
        ns.page.RefreshGroupChrome(app, g)

        -- A tab is as wide as what it carries: the gate if there is one,
        -- the title, and the padding either side. Measured here because
        -- the title's string width is only known once it has been set.
        if tab and group.title then
            local left = (gate and (10 + ns.SWITCH_W + 8))
                         or (g.bpReorderable and 24 or 11)
            g.header:SetWidth(math.ceil(left + g.title:GetStringWidth() + 12))
        end

        local headH = group.title and preset.headerH or 0
        -- The rule between header and body, in the border's own color.
        -- Not drawn on a collapsed card: there is no body under it.
        g.headRule:ClearAllPoints()
        g.headRule:SetPoint("TOPLEFT",  g.surface, "TOPLEFT",   1, -headH - 1)
        g.headRule:SetPoint("TOPRIGHT", g.surface, "TOPRIGHT", -1, -headH - 1)
        local hb = cBorder
        g.headRule:SetColorTexture(hb[1], hb[2], hb[3], hb[4] or 1)
        if ns.NoSnap then ns.NoSnap(g.headRule) end
        -- Not on a TAB. The rule separates a band header from the body
        -- beneath it; a tab is already closed on all four sides, so a rule
        -- running out from its bottom edge to the card's right edge is a
        -- second line doing the same job at a different length -- which is
        -- what made a tabbed card look like it had a full-width header as
        -- well as a tab.
        -- ...and not on a PLAIN header either: a rule is a border, and the
        -- point of plain is that the heading has none.
        g.headRule:SetShown(headH > 0 and gateOn and not tab and not plain
                            and preset.headerRule ~= false)

        g.body:ClearAllPoints()
        g.body:SetPoint("TOPLEFT",  g, "TOPLEFT",  0, -headH - preset.padding)
        g.body:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, -headH - preset.padding)

        -- A card's own attachments, plus any its preset gives every card of
        -- this kind. Built after the header exists, so a zone naming the
        -- header has something to resolve to.
        ns.attach.BuildAll(app, "group", g, group, preset, ctx)

        -- A collapsed card lays nothing out: its fields are not measured,
        -- not acquired and not indexed, so they cost nothing and cannot be
        -- found by a search that would then scroll to something invisible.
        local inner = 0
        local padBottom = preset.padBottom or preset.padding
        if gateOn then
            -- A TREE group lays out a list and a pane rather than fields;
            -- everything else about the card -- header, gate, collapse,
            -- attachments -- is the same card it always was.
            if group.tree then
                -- What a "fill" tree may take: the viewport this host
                -- scrolls in, less the cards above (y), this card's own
                -- header and padding, and the gap that follows every
                -- card -- so the page ends exactly at the viewport's
                -- bottom and grows no scrollbar of its own.
                --
                -- The page body's viewport is the panel's own scroll
                -- frame; a nested host (a tree pane) scrolls in its
                -- parent.
                local view  = (host == app.scrollContent) and app.scroll
                              or host:GetParent()
                local viewH = view and view.GetHeight and view:GetHeight() or 0
                local avail = viewH - y - headH - preset.padding - padBottom - GROUP_GAP
                inner = LayoutTreeGroup(app, g, group, preset, ctx,
                                        width - inset * 2, avail)
            else
                HideTreeFurniture(app, g)
                inner = LayoutGroup(app, g, group, preset, ctx, width - inset * 2)
            end
        else
            HideTreeFurniture(app, g)
        end
        -- Whole pixels, so the card's bottom edge and everything stacked
        -- under it land on the pixel grid (a tree group's inner height is
        -- measured, not summed from rows).
        inner = math.ceil(inner)
        g.body:SetHeight(math.max(inner, 1))
        g.body:SetShown(gateOn)
        -- The dim itself. One call, because g.body is the single frame
        -- every field widget and label in the card is parented to. Its
        -- partner is in LayoutGroup, which disabled those fields for the
        -- same render -- dimmed and inert travel together, or the card
        -- is lying about what a click will do.
        g.body:SetAlpha(gateLit and 1 or DIMMED_BODY_ALPHA)
        -- Collapsed:
        --   band  the card is its header plus the stroke above and below it
        --         -- sized to the header alone, the header's own fill
        --         covered the bottom stroke and the card looked like it had
        --         no border down there.
        --   tab   the box goes entirely. It sits BELOW the header, so
        --   plain leaving it behind left a two-pixel sliver of border under
        --         a collapsed heading rather than nothing at all.
        local aboveBox = tab or plain
        g.surface:SetShown(gateOn or not aboveBox)
        -- All four corners on a collapsed tab, which is a shape on its own;
        -- square at the bottom whenever there is a body under it to meet.
        if gateOn then
            g:SetHeight(headH + preset.padding + padBottom + inner)
        elseif aboveBox then
            g:SetHeight(math.max(headH, 1))
        else
            g:SetHeight(math.max(headH + 2, 1))
        end

        app.liveGroups[#app.liveGroups + 1] = g
        -- Groups are indexed by an OPTIONAL id. A group that never declares
        -- one simply cannot be named, which is the right cost: rung 3 exists
        -- for the caller who knows which group they mean.
        if group.id then
            app.groupIndex = app.groupIndex or {}
            app.groupIndex[group.id] =
                { frame = g, group = group, ctx = ctx, scope = app.bpScope }
        end
        y = y + g:GetHeight() + GROUP_GAP
        end
    end
    return y
end

function ns.page.Render(app)
    -- Not while a card is being dragged. Rebuilding the body returns every
    -- card to the pool, which would pull the dragged one out from under the
    -- cursor; the drop invalidates anyway.
    if ns.reorder and ns.reorder.IsDragging() then return true end
    local body = app:GetRegion("body")
    if not app.scroll then
        local sc = CreateFrame("ScrollFrame", nil, body)
        sc:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -6)
        -- The right inset reserves the scrollbar gutter whether or not the
        -- bar is showing, so content width never depends on it.
        --
        -- The BOTTOM inset is 1, not 10. A 10px band under the scroll was
        -- drawing nothing at all: the group cards are opaque, so everywhere
        -- else you see card, and below the last one you saw straight through
        -- the panel's own 85% background to the world -- a strip of daylight
        -- exactly where the content should meet the bottom edge. The top
        -- inset stays at 10 because that gap does real work, separating
        -- content from the page header; the bottom one separated content
        -- from nothing.
        -- The page's margin belongs to the CARDS, not to the scroll frame:
        -- a scroll frame clips its children, so a band anchored outside its
        -- inset was drawn and then cut off at exactly the margin it was
        -- trying to escape. Only the scrollbar's gutter is reserved here.
        --
        -- Reserved to begin with, and given back at the end of the render
        -- when the page turns out not to overflow -- see the note there.
        -- The bar itself is anchored to the BODY rather than to this frame
        -- (ns.AttachScrollBar), so it stays inside the panel whichever way
        -- that decision goes.
        app.scrollRightInset = ns.SCROLLBAR_GUTTER
        sc:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -app.scrollRightInset, 1)
        local content = CreateFrame("Frame", nil, sc)
        content:SetSize(1, 1)
        sc:SetScrollChild(content)
        sc:EnableMouseWheel(true)
        sc:SetScript("OnMouseWheel", function(self, delta)
            local maxs = math.max(0, (self.contentHeight or 0) - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxs, self:GetVerticalScroll() - delta * 40)))
        end)
        -- Responsive width. The flow packer decides how many fields fit on
        -- a line from the content width, so that decision has to be made
        -- again whenever the width changes -- otherwise the panel resizes
        -- around a layout that was packed for the old width and the last
        -- field on each line is simply clipped.
        --
        -- Re-packing means a full re-render, so it is coalesced: a drag of
        -- the resize grip fires OnSizeChanged every frame but re-renders at
        -- most twenty times a second, and only when the rounded width has
        -- actually changed.
        --
        -- HEIGHT too, but only for a page that has a "fill" tree card on
        -- it. Everything else lays out from the width alone and the scroll
        -- frame simply shows more or less of it; a fill card is sized from
        -- the viewport's HEIGHT, so a vertical resize left it at the old
        -- height -- overhanging the viewport after a shrink, so the PAGE
        -- grew a scrollbar outside the card while the list inside it, taller
        -- than anything visible, never needed one of its own.
        sc:SetScript("OnSizeChanged", function(self)
            local sameW = math.floor(self:GetWidth() + 0.5) == app.lastPageWidth
            local sameH = (not app.pageHasFill)
                          or math.floor(self:GetHeight() + 0.5) == app.lastPageHeight
            if sameW and sameH then return end
            if app.repackPending then return end
            app.repackPending = true
            C_Timer.After(0.05, function()
                app.repackPending = nil
                if app.frame and app.frame:IsShown() then ns.page.Render(app) end
            end)
        end)
        app.scroll, app.scrollContent = sc, content
        ns.AttachScrollBar(sc, function() return app.skin end)

        -- THE PINNED BAND: page content that does not scroll.
        --
        -- A group may declare `pinned = true`, and an in-page subtab strip
        -- may say `pinnedStrip = true`. Those draw HERE -- a plain frame at
        -- the top of the body, outside the scroll frame -- and the scroll
        -- frame starts beneath whatever they take. A setting that governs
        -- the whole page (which surfaces a Global Styles page writes) and
        -- the strip that chooses what is below it are not part of what they
        -- govern, and scrolling them away leaves the reader adjusting a page
        -- whose terms are off screen.
        --
        -- The same arrangement a tree group already has inside its pane --
        -- a fixed header band above a scrolling body -- at page level.
        local pinned = CreateFrame("Frame", nil, body)
        -- One horizontal anchor only, and the width SET each render, the
        -- way the scroll content is sized. Anchoring both sides makes the
        -- width anchor-derived, which reads as the PREVIOUS pass's number
        -- for the whole of this one -- and everything drawn into the band
        -- measures itself against it, so a note wraps to a width the band
        -- no longer has.
        pinned:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, -6)
        pinned:SetHeight(1)
        pinned:Hide()
        app.pagePinned = pinned
    end

    -- How far the scrollbar stops short of the body's bottom edge: set by
    -- the frame's layout, which knows whether that edge is also the
    -- panel's and therefore has the resize grip in it. Re-read every
    -- render because a status bar can come and go at runtime.
    app.scroll.barClearBottom = app.scrollbarClearBottom or 0

    -- The page's TOP INSET, decided per render rather than at creation:
    -- a page that opens with a band meets the chrome above it flush (see
    -- ns.page.OpensWithBand), anything else keeps the 6px it was created
    -- with. Re-setting the same anchor point replaces it.
    app.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0,
                        ns.page.OpensWithBand(app) and 0 or -6)

    ReleaseAll(app)

    -- THE PAGE'S OWN SCOPE, for everything this render builds that is not
    -- inside a pane (see the note above ns.page.ReleaseScope). Saved and
    -- restored because Render re-enters itself over the gutter tie-break
    -- below, and a nested pass must hand the outer one its scope back.
    local prevScope = app.bpScope
    app.bpScope = "page"

    -- ONE SAMPLE OF EVERY PREDICATE for this pass; see ns.IsHidden. A
    -- nested pass (the gutter tie-break re-enters Render) shares the
    -- outer one's memo: it is the same frame and the same declaration,
    -- and two answers inside one frame is the bug this closes.
    local prevHiddenMemo = app.bpHiddenNow
    app.bpHiddenNow = prevHiddenMemo or {}
    -- The dimmed set, rebuilt at the start of the OUTERMOST pass and then
    -- LEFT STANDING. Unlike the hidden memo it must outlive the render:
    -- a control asks ns.IsDisabled again at CLICK time, which is between
    -- renders, and a set torn down with the pass would answer "not
    -- dimmed" exactly then -- grayed controls that still take the click.
    -- A nested pass shares the outer one's table (same frame, same
    -- declaration); the depth count is what tells the two apart.
    app.bpDimDepth = (app.bpDimDepth or 0) + 1
    if app.bpDimDepth == 1 then app.bpDimmed = {} end

    local key   = table.concat(app.route or {}, "/")
    local page = ns.page.ForRoute(app)

    -- (The nearest-ancestor fallback lives in ns.page.ForRoute; the note
    -- that used to be here is on it.)
    --
    -- Blanking the body was never a safe answer to "this node has no page".
    -- Plenty of real nodes have none -- a section heading inside a
    -- collection, a branch that exists only to hold children -- and the
    -- route lands on one whenever something structural moves under the
    -- reader: a filter drops the member they were on, a member is removed,
    -- a rebuild re-derives a list. Every one of those took the whole panel
    -- away and left the placeholder in its place, which is a far worse
    -- answer than showing the page the node lives on.
    --
    -- So the body shows the nearest ancestor that HAS a page -- for a tree
    -- group's section that is the collection, which is the card carrying
    -- the list the reader was using. app.route is left alone: what is
    -- selected and what is drawable are different questions, and the
    -- navigators still light the real route.
    app.scroll:SetShown(page ~= nil)
    if app.scroll.scrollbar and not page then app.scroll.scrollbar:Hide() end

    -- A new section starts at the top. Re-rendering the SAME section -- a
    -- resize, a refresh -- keeps the reader where they were.
    if key ~= app.scrollRoute then
        app.scrollRoute = key
        app.scroll:SetVerticalScroll(0)
    end

    if not page then
        -- No page, no header field: the placeholder is what is on screen
        -- and a control left up there belongs to a page that is not.
        if ns.chrome and ns.chrome.RenderHeaderField then
            ns.chrome.RenderHeaderField(app, nil, nil)
        end
        app.bpScope, app.bpHiddenNow = prevScope, prevHiddenMemo
        app.bpDimDepth = (app.bpDimDepth or 1) - 1
        return false
    end

    -- THE HOST THIS CTX BELONGS TO, carried on the ctx because a setter is
    -- handed one and nothing else: it is what lets a write name the host to
    -- re-render without the page having to remember its own shape. See
    -- ns.page.ScheduleRender.
    local ctx  = { app = app, db = (page.db and page.db()) or nil, page = page,
                   bpScope = "page" }

    -- BEFORE the body is measured. A header field changes the page
    -- header's height, which moves the body's top edge -- doing it after
    -- the cards were laid out would lay them out for a body that is about
    -- to move.
    if ns.chrome and ns.chrome.RenderHeaderField then
        ns.chrome.RenderHeaderField(app, page, ctx)
    end

    local skin = app.skin
    local width = app.scroll:GetWidth()
    app.lastPageWidth = math.floor(width + 0.5)
    -- The height this page was laid out for, and whether any card on it
    -- was sized FROM that height -- what the scroll frame's OnSizeChanged
    -- asks before deciding a vertical resize is worth a re-render.
    -- LayoutTreeGroup sets the flag for a "fill" tree; cleared here so a
    -- page without one does not inherit the last page's answer.
    app.lastPageHeight = math.floor(app.scroll:GetHeight() + 0.5)
    app.pageHasFill    = nil
    app.scrollContent:SetWidth(width)

    -- Which groups draw at all, settled BEFORE anything is acquired.
    --
    -- A group that is not drawn must take no frame, no y advance and no
    -- slot in the index -- otherwise it is exactly the empty card this
    -- filter exists to remove. Its predicates are still counted.
    --
    -- Each entry carries the group's ORIGINAL index, because that is what
    -- a page's `reorder.onMove` is handed: an index into the page's own
    -- groups, not into the ones that happen to be showing. Renumbering
    -- them here would move the wrong card on a drop.
    -- The in-page subtab strip is a single shared nav (one page on screen at
    -- a time). Hide it up front; a page that has one re-shows it below.
    if app.pageStripNav then ns.nav.HideTabStrip(app, app.pageStripNav) end

    local drawn = ns.page.DrawnGroups(app, page.groups, ctx)

    -- PINNED FIRST, into the band above the scroll frame.
    --
    -- `DrawnGroups` has already expanded an in-page strip into a strip
    -- marker followed by the selected tab's groups, so a pinned strip is
    -- taken with its marker and the tab's own cards stay in the scrolling
    -- half -- which is the whole point: the strip stays put and what it
    -- chose scrolls under it.
    local pin, rest = nil, drawn
    for _, item in ipairs(drawn) do
        local isPin = (item.group and item.group.pinned)
                      or (item.strip and item.strip.pinned)
        if isPin then pin = pin or {}; pin[#pin + 1] = item end
    end
    if pin then
        rest = {}
        for _, item in ipairs(drawn) do
            local isPin = (item.group and item.group.pinned)
                          or (item.strip and item.strip.pinned)
            if not isPin then rest[#rest + 1] = item end
        end
    end

    local pinH = 0
    if pin then
        -- The band is WIDER than the scrolling content by the scrollbar's
        -- gutter. That gutter is reserved on the scroll frame because the
        -- bar sits in it -- but the bar cannot reach above the scroll
        -- frame, so a band that gives the space up is holding a gap open
        -- for something that will never be there: the strip's rule stopped
        -- short of the panel edge, and so did the card, but only while the
        -- page happened to overflow.
        local pinW = width + (app.scrollRightInset or 0)
        app.pagePinned:SetWidth(pinW)
        app.pagePinned:Show()
        pinH = ns.page.RenderGroups(app, app.pagePinned, pin, ctx, pinW, page)
        app.pagePinned:SetHeight(math.max(pinH, 1))
    else
        app.pagePinned:Hide()
        app.pagePinned:SetHeight(1)
    end
    -- The scroll frame starts under the band. Re-anchored every render
    -- rather than once: the band's height is its content's, and a page with
    -- none at all gives the room back.
    app.scroll:SetPoint("TOPLEFT", app:GetRegion("body"), "TOPLEFT",
                        0, -(6 + pinH))

    local y = ns.page.RenderGroups(app, app.scrollContent, rest, ctx, width, page)

    app.scrollContent:SetHeight(math.max(y, 1))
    app.scroll.contentHeight = y

    -- Widening the panel makes the content shorter. Without this the view
    -- stays scrolled past the end and the page looks empty.
    local maxs = math.max(0, y - app.scroll:GetHeight())
    if app.scroll:GetVerticalScroll() > maxs then
        app.scroll:SetVerticalScroll(maxs)
    end
    if app.scroll.scrollbar then app.scroll.scrollbar:Update() end

    -- Give the scrollbar's gutter back when there is no scrollbar, so the
    -- cards have the room -- which is what classic options dialogs do.
    --
    -- The tree can decide this before it lays anything out, because its
    -- rows are a fixed height. Field packing is not: how tall this page is
    -- depends on how wide it is, so the answer only exists AFTER the pack,
    -- and acting on it means packing again.
    --
    -- THE TIE-BREAK. The two widths can disagree: content that fits with
    -- the gutter reserved may not fit once the gutter is given back and
    -- the cards re-flow into it. Left there, the page alternates -- which
    -- is the jitter such dialogs show on a page sitting near the
    -- threshold. So when the wider pack overflows again, the gutter goes
    -- back and the bar stays: of the two answers, the one WITH a bar is
    -- always consistent with itself, because a narrower content area
    -- cannot make packed content shorter. That is what makes this finite
    -- -- at most two extra passes, and only on the render where the
    -- decision actually flips.
    local needsBar = (y - app.scroll:GetHeight()) > 1
    local want     = needsBar and ns.SCROLLBAR_GUTTER or 0
    if app.scrollRightInset ~= want and not app.repackingGutter then
        local host = app.scroll:GetParent()
        local function reserve(px)
            app.scrollRightInset = px
            app.scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -px, 1)
            app.repackingGutter = true
            ns.page.Render(app)
            app.repackingGutter = nil
        end
        reserve(want)
        -- Giving it back made the page overflow again: take it back.
        if want == 0 and ((app.scroll.contentHeight or 0)
                          - app.scroll:GetHeight()) > 1 then
            reserve(ns.SCROLLBAR_GUTTER)
        end
    end
    app.bpScope, app.bpHiddenNow = prevScope, prevHiddenMemo
    app.bpDimDepth = (app.bpDimDepth or 1) - 1
    return true
end
