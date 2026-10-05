-- ============================================================
-- BuzzardPanel: Composites.lua
-- Controls built out of other controls.
--
-- A composite is an ordinary control def -- create / apply / refresh /
-- measure -- whose widget happens to host several primitive widgets of its
-- own. It reads and writes MORE THAN ONE setting, named in `binds`:
--
--     { control = "textposition", label = "Name Text",
--       binds = { point = "name.point", x = "name.x",
--                 y = "name.y", justify = "name.justify" } }
--
-- Page.lua indexes the widget under every key in `binds`, so a change to
-- any one of them refreshes the whole composite.
--
-- The sub-controls are the real primitives from Controls.lua, so they get
-- the panel's art, the border treatment and the hover contract for free,
-- and a change to any of those reaches composites without being re-done.
-- Unlike page fields the sub-widgets are NOT pooled individually: they are
-- built once and live for as long as the composite widget does, which the
-- pool already manages.
-- ============================================================
local ADDON, ns = ...

local ROW_H = 22
local C = function(c, mul, alpha)
    mul = mul or 1
    return c[1] * mul, c[2] * mul, c[3] * mul, alpha or c[4] or 1
end

-- ── Scaffolding ────────────────────────────────────────────────

-- Build (once) and return a sub-control of the given kind.
-- One sub-control, remembered by key AND BY KIND.
--
-- It used to be remembered by key alone, which is fine while a composite's
-- rows are always the same control -- and wrong the moment they are not. A
-- pooled `offsets` that had served a pair of STEPPERS (frame spacing) handed
-- its steppers straight to the next field that asked for row "x", so a pair
-- of SLIDERS (frame width and height) rendered as steppers, or the other way
-- round, depending on which was built first.
--
-- A kind that is not currently in use is parked rather than discarded: a
-- composite that flips back gets its widgets back instead of building a
-- third set.
local function Sub(w, key, kind, parent)
    w.subs  = w.subs or {}
    w.spare = w.spare or {}
    local s = w.subs[key]
    if s and s.kind ~= kind then
        s.w:Hide()
        w.spare[key .. ":" .. tostring(s.kind)] = s
        w.subs[key] = nil
        s = nil
    end
    if not s then
        s = w.spare[key .. ":" .. kind]
        w.spare[key .. ":" .. kind] = nil
        if not s then
            local def = ns.builtinControls[kind]
            s = { def = def, w = def.create(w.bpApp, parent or w), kind = kind }
        end
        w.subs[key] = s
    end
    return s
end

-- A small caption above or beside a sub-control.
--
-- The same font object and the same color a FIELD's label wears: a caption
-- names its row exactly as a label names its field, and drawn in the muted
-- description color instead it read as a hint about the control rather than
-- as the control's name.
local function Caption(w, key, text)
    w.caps = w.caps or {}
    local f = w.caps[key]
    if not f then
        f = ns.FS(w, "OVERLAY", "GameFontNormalSmall")
        f:SetJustifyH("LEFT")
        w.caps[key] = f
    end
    f:SetText(text)
    return f
end

-- Recolor every caption from the skin. Composites do this in refresh so a
-- skin change reaches them like it reaches everything else.
--
-- `labelFg` with no preset in hand, which resolves to the skin's groupLabel
-- -- the same token a field label falls back to when its card's preset does
-- not override it (ns.PresetColor). A composite is handed the page's ctx
-- rather than the card's preset, so it cannot ask for that override; every
-- preset that ships uses the token anyway.
local function PaintCaptions(w, skin, alpha)
    local c = ns.PresetColor(nil, skin, "labelFg")
    for _, f in pairs(w.caps or {}) do
        f:SetTextColor(C(c, 1, alpha or 1))
    end
end

-- A composite lays its children out by hand, at heights it knows. So a
-- slider inside one keeps its value box at the SIDE, whatever the panel's
-- default placement is.
--
-- A "below" box is a taller widget, and the composite's geometry does not
-- move to meet it: the anchor pad is sized as exactly two compact sliders,
-- so under a panel-wide "below" default the X slider's box was drawn over
-- the Y slider's track. Fixing that by growing the pad instead would make a
-- position widget the tallest thing on any page it appears on -- and the
-- box beside the track is the arrangement these composites were drawn for.
--
-- Set on the sub-node's extras rather than forced afterwards, so a field
-- can still ask for something else by hand if it ever has a reason to.
local function SideBox(extra)
    if extra.valuePlacement == nil then extra.valuePlacement = "side" end
    return extra
end

-- Build the node a sub-control sees. It is a real control node: its own
-- bind path, its own min/max, and a `disabled` that inherits the
-- composite's own disabled state so the whole thing grays out together.
-- Fields a sub-node inherits from the composite that owns it. The composite
-- is the thing the page declared; its sub-controls are an implementation
-- detail, so anything the page said about the composite has to reach them.
local INHERITED = { "refresh", "refreshKey", "refreshId", "rank", "delay" }

local function SubNode(node, ctx, bindKey, extra)
    -- The entry may be a bare path or a full reader/writer -- ns.BindNode
    -- lays whichever it is over the sub-node the composite built.
    local n = ns.BindNode(node.binds and node.binds[bindKey], extra)
    n.disabled = function() return ns.IsDisabled(node, ctx) end

    -- Carry the composite's effect down.
    --
    -- Without this a sub-control WROTE its setting and repainted itself and
    -- then stopped: the composite's onChange lived on the composite's node,
    -- which no sub-control ever saw. Dragging the offset sliders inside a
    -- position widget, or the size slider in a font row, changed the profile
    -- and never told the addon to move anything -- silently, because the
    -- panel itself looked completely correct. Only the anchor pad worked,
    -- and only because WirePad fires the effect by hand.
    --
    -- The tier fields come too, so a composite that asks for "mouseup"
    -- gets it on the sliders that actually drag, and a refreshKey shared by
    -- the whole composite keeps its three settings coalescing together
    -- instead of firing three times for one gesture.
    for _, key in ipairs(INHERITED) do
        if n[key] == nil then n[key] = node[key] end
    end

    -- onChange is WRAPPED rather than copied. The handler belongs to the
    -- composite and was written against the composite's node -- it reads
    -- `binds`, and often several settings at once. Handing it a sub-node
    -- would give it one binding and no way to find the others.
    if n.onChange == nil and node.onChange then
        n.onChange = function() return node.onChange(node, ctx) end
    end
    -- The effect is the COMPOSITE's, so it must coalesce under the
    -- composite's identity rather than under whichever sub-binding happened
    -- to move. Otherwise x and y are two keys and a diagonal drag runs the
    -- addon's callback twice.
    if n.refreshKey == nil then
        n.refreshKey = node.refreshKey or node.id or node.bind or node
    end
    return n
end

-- Apply and refresh in one go, and REMEMBER the node. Every composite
-- refresh then just re-runs its sub-controls against the nodes apply built,
-- instead of each refresh reconstructing them and risking drift.
local function Bind(w, key, node, ctx, sub)
    sub.node = node
    sub.def.apply(sub.w, node, ctx)
    sub.def.refresh(sub.w, node, ctx)
end

-- Refresh every sub-control against its remembered node.
local function RefreshSubs(w, ctx)
    for _, s in pairs(w.subs or {}) do
        if s.node then s.def.refresh(s.w, s.node, ctx) end
    end
end

-- ── Anchor pad ─────────────────────────────────────────────────
-- Nine points in a 3x3 grid. The pad is the primary control; the offsets
-- sit beside it because an offset only means anything relative to a point.

local POINTS = {
    { "TOPLEFT",    1, 1, "Top Left"    }, { "TOP",    2, 1, "Top"    },
    { "TOPRIGHT",   3, 1, "Top Right"   }, { "LEFT",   1, 2, "Left"   },
    { "CENTER",     2, 2, "Center"      }, { "RIGHT",  3, 2, "Right"  },
    { "BOTTOMLEFT", 1, 3, "Bottom Left" }, { "BOTTOM", 2, 3, "Bottom" },
    { "BOTTOMRIGHT",3, 3, "Bottom Right"},
}
-- The pad is nine loose cells, with no container behind them: no backing
-- panel, no border around the group. The cells ARE the control, so the
-- gaps between them read as the frame the anchor sits on.
--
-- Its size is not arbitrary. The X and Y sliders stack beside it, and the
-- pad is exactly two of them high, so the two halves of the control finish
-- on the same line. Change the cell or the gap and that equality is what
-- has to survive: the cells are sized FROM the slider pitch, not the other
-- way round.
--
-- It is as small as that equality allows. A composite is still taller than
-- a labeled dropdown -- two stacked rows cannot be one -- but every pixel
-- above two slider rows was slack, and it is gone.
--
-- The sliders are COMPACT ones -- no min/max footer -- so that the pad can
-- stay the size it wants to be. Matching the heights by growing the pad
-- instead would make a position widget the biggest thing on any page it
-- appears on, for no benefit.
-- The row pitch is the compact slider's height and NOTHING added to it. A
-- compact slider already carries its own trailing slack -- its content ends
-- at 21 of 26 -- so the extra gap that used to be here was double-spacing
-- two rows that were already spaced, and the whole widget wore the cost
-- twice over.
local SLIDER_H = ns.SLIDER_H_COMPACT           -- row pitch

-- Written in the order the sizes actually depend on each other, so the
-- equality cannot be broken by editing one number. The pad IS two slider
-- rows; the gap is held at what it has always been; the CELL takes
-- whatever is left.
--
-- That order is the whole point. When cell and gap were both picked and
-- the pad was their sum, making the pad shorter meant shaving the gaps as
-- hard as the squares -- and the gaps are what read as the frame the
-- anchor sits on, while the squares are only targets. Shrink the frame and
-- the pad stops looking like a frame; shrink the squares and it just looks
-- like a smaller pad.
local PAD_SIZE = SLIDER_H * 2                   -- 42
local PAD_GAP  = 3
local PAD_CELL = (PAD_SIZE - PAD_GAP * 2) / 3   -- 12

-- Which justification a point implies. Used when the anchor changes: the
-- justification follows it, and stays freely adjustable afterwards.
local JUSTIFY_FOR = {
    TOPLEFT = "LEFT",   LEFT   = "LEFT",   BOTTOMLEFT  = "LEFT",
    TOP     = "CENTER", CENTER = "CENTER", BOTTOM      = "CENTER",
    TOPRIGHT= "RIGHT",  RIGHT  = "RIGHT",  BOTTOMRIGHT = "RIGHT",
}

local function BuildPad(w)
    if w.pad then return w.pad end
    local pad = CreateFrame("Frame", nil, w)
    pad:SetSize(PAD_SIZE, PAD_SIZE)
    pad.cells = {}
    for i, p in ipairs(POINTS) do
        local name, cx, cy = p[1], p[2], p[3]
        local b = CreateFrame("Button", nil, pad)
        b:SetSize(PAD_CELL, PAD_CELL)
        b:SetPoint("TOPLEFT", pad, "TOPLEFT",
                   (cx - 1) * (PAD_CELL + PAD_GAP),
                   -((cy - 1) * (PAD_CELL + PAD_GAP)))
        -- Each cell is a bordered square in its own right -- the same
        -- border treatment as every other control, at the radius a cell
        -- this small can carry.
        b.border, b.fill = ns.BorderedRound(b, 4, "BACKGROUND", "BORDER")
        b.point      = name
        b.pointName  = p[4] or name
        -- NO tooltip on a cell. A 3x3 grid of squares says where each one
        -- points by where it IS, so naming them was nine tooltips telling
        -- the reader what they could already see, popping up under the
        -- cursor while they aimed at one.
        --
        -- `bpTipOwn` stays: it is what stops the FIELD's tooltip being
        -- attached to all nine cells instead, which is the same nuisance
        -- with worse text. The pad's own frame still carries it.
        b.bpTipOwn = true
        b:SetScript("OnEnter", function(self)
            self.hovered = true
            if w.repaintPad then w.repaintPad() end
        end)
        b:SetScript("OnLeave", function(self)
            self.hovered = false
            if w.repaintPad then w.repaintPad() end
        end)
        pad.cells[i] = b
    end
    w.pad = pad
    return pad
end

-- Color the nine cells and wire their clicks. Split out because both the
-- anchor and the text-position composite use it.
local function WirePad(w, node, ctx, onPick)
    local pad = w.pad

    -- The node the POINT is read and written through, built once for the
    -- gesture rather than per repaint. It is deliberately NOT a SubNode: a
    -- sub-node carries the composite's onChange, and WirePad already fires
    -- the effect itself -- one effect for the whole gesture, which is the
    -- point of doing it by hand here.
    --
    -- It matters that this is a real node rather than `{ bind = ... }`: a
    -- field whose anchor write has a side effect -- resetting the grow
    -- direction to that anchor's default, choosing between a repaint and a
    -- rebuild -- declares that side effect as the entry's own `set`, and it
    -- has to fire when the pad is clicked exactly as it did when the
    -- dropdown this replaced was picked from.
    local pointEntry = node.binds and node.binds.point
    local pointNode  = pointEntry and ns.BindNode(pointEntry, {}) or nil
    local pointPath  = ns.BindPath(pointEntry)

    local function repaint()
        local skin = ctx.app.skin
        local off  = ns.IsDisabled(node, ctx)
        local cur  = pointNode and ns.GetValue(pointNode, ctx)
        for _, b in ipairs(pad.cells) do
            if b.point == cur then
                b.border:SetVertexColor(ns.Faded(skin.accent, skin.panelBg, off, 1.15))
                b.fill:SetVertexColor(ns.Faded(skin.accent, skin.panelBg, off, 1.15))
            elseif b.hovered and not off then
                b.border:SetVertexColor(C(skin.accent, 1, 0.8))
                b.fill:SetVertexColor(C(skin.accent, 1, 0.35))
            else
                b.border:SetVertexColor(ns.Faded(skin.controlBorder, skin.panelBg, off))
                b.fill:SetVertexColor(ns.Faded(skin.controlBg, skin.panelBg, off))
            end
            b:SetEnabled(not off)
        end
    end
    w.repaintPad = repaint

    for _, b in ipairs(pad.cells) do
        b:SetScript("OnClick", function(self)
            if ns.IsDisabled(node, ctx) or not pointNode then return end
            ns.SetValue(pointNode, ctx, self.point)
            if onPick then onPick(self.point) end
            ctx.app:RefreshBinding(pointPath or node.id)
            -- One effect for the whole gesture, not one per bind the pad
            -- happens to touch -- picking a point can also write a
            -- justification, and that is still a single edit.
            ns.FireEffect(node, ctx)
        end)
    end
    repaint()
end

-- Lay the offsets out beside the pad: X above Y, the pair exactly as tall
-- as the pad, so the control reads as two halves of one object rather than
-- a square with some sliders trailing off it.
--
-- The captions sit to the LEFT of each slider rather than above it. A
-- caption row would add 13px per slider and break the height match, and "X"
-- and "Y" are short enough that a column for them costs almost nothing.
--
-- Each caption is centered on its slider's VALUE BOX, which is the thing at
-- eye level on that row. The box's own offset and height do the positioning,
-- so this stays right if either changes.
-- The caption column beside the pad's offsets. Measured from the captions
-- rather than fixed at one letter's worth: they say "X Offset" and "Y
-- Offset" now -- which is what they ARE, and "X" alone beside an anchor pad
-- read as a coordinate rather than as a nudge from the point.
local CAP_MIN, CAP_MAX = 14, 90

local function PadCaptionW(w)
    local widest = 0
    for _, f in pairs(w.caps or {}) do
        widest = math.max(widest, (f:GetStringWidth() or 0))
    end
    return math.max(CAP_MIN, math.min(CAP_MAX, widest + 4))
end

-- An offset slider is a fixed width, and it is the SAME width as a slider
-- anywhere else on the page -- ns.CONTROL_W, box included, since a "side"
-- box is drawn inside the widget's own width rather than beyond it. So the
-- track here is shorter than a standalone slider's by the width of the box,
-- and the two controls still line up as one column.
--
-- It does NOT grow to fill the row: an offset is a small number over a
-- small range, and a 300px track for it just makes the control hard to aim
-- and the group lopsided.
local OFFSET_W = ns.CONTROL_W

-- The pair is headed "Offsets", so each row needs only its axis. "X Offset"
-- on both rows said the same word twice and pushed the tracks right by the
-- width of it; the heading says it once.
--
-- It is drawn ABOVE the widget, on the field's own label line -- the same
-- line "Anchor Point" is on -- so the composite's two halves are each named
-- where a label belongs rather than the right half being named a row lower.
-- The lift is a label line, which is what Page.lua reserves above a control.
local OFFSETS_HDR_LIFT = 12

local function LayOffsets(w, top, right)
    local capW = PadCaptionW(w)
    -- The offsets start clear of the FIELD'S OWN LABEL, not at a fixed
    -- distance from the pad. Both headings sit on the same line -- the
    -- field's label over the pad, "Offsets" over the tracks -- so a long
    -- label ("Stack Text Position") ran into the heading beside it while a
    -- short one ("Location") looked fine, which is why this was only ever
    -- wrong on some pages.
    --
    -- Measured from the label FontString Page.lua parks on the widget, so
    -- it is the drawn width in the drawn font rather than an estimate.
    -- Capped so the tracks keep a usable length on a narrow card: past
    -- that the label is the thing that gives, and it has a tooltip.
    local labelW = (w.bpLabel and w.bpLabel:GetStringWidth()) or 0
    local left   = math.max(PAD_SIZE + 14, labelW + 16)
    if right and right > 0 then
        left = math.min(left, math.max(PAD_SIZE + 14, right - capW - 4 - 90))
    end
    local barL = left + capW + 4
    local barW = math.max(90, math.min(OFFSET_W, right - barL))
    local rowH = ns.SLIDER_H_COMPACT_RANGE or SLIDER_H

    -- Left-aligned with the first track, on the label line above the widget.
    if w.hdr then
        w.hdr:ClearAllPoints()
        w.hdr:SetPoint("TOPLEFT", w, "TOPLEFT", barL, OFFSETS_HDR_LIFT)
    end

    for i, key in ipairs({ "x", "y" }) do
        local rowY = top + (i - 1) * rowH
        local s = w.subs[key].w
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", w, "TOPLEFT", barL, -rowY)
        s:SetWidth(barW)

        -- "LEFT" on a FontString is the middle of its left edge, so this
        -- puts the caption's center level with the value box's center.
        local boxTop = 2                       -- slider.create's box inset
        local boxMid = boxTop + (s.box:GetHeight() or 19) / 2
        w.caps[key]:ClearAllPoints()
        w.caps[key]:SetPoint("LEFT", s, "TOPLEFT", -(capW + 4), -boxMid)
    end
end

local function OffsetNodes(w, node, ctx)
    local sx = Sub(w, "x", "slider")
    local sy = Sub(w, "y", "slider")
    local lo, hi = node.min or -200, node.max or 200
    -- `range`: the min and max under each track. Beside a pad the numbers
    -- are the only thing saying how far a nudge can go.
    Bind(w, "x", SubNode(node, ctx, "x",
        SideBox({ control = "slider", min = lo, max = hi,
                  compact = true, range = true })), ctx, sx)
    Bind(w, "y", SubNode(node, ctx, "y",
        SideBox({ control = "slider", min = lo, max = hi,
                  compact = true, range = true })), ctx, sy)
    -- The axis alone; the heading above them carries the noun.
    Caption(w, "x", "X")
    Caption(w, "y", "Y")
    if not w.hdr then
        w.hdr = ns.FS(w, "OVERLAY", "GameFontNormalSmall")
        w.hdr:SetJustifyH("LEFT")
    end
    w.hdr:SetText("Offsets")
    w.hdr:Show()
end

local anchor = {}
function anchor.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(PAD_SIZE)
    BuildPad(w)
    -- A cell's worth of gap above the grid, the same PAD_GAP that separates
    -- its rows: flush with the widget's top the pad read as pinned to the
    -- card rather than as a block of nine squares, and the offsets beside it
    -- start below their own heading anyway.
    w.pad:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -PAD_GAP)
    return w
end

function anchor.apply(w, node, ctx)
    OffsetNodes(w, node, ctx)
    WirePad(w, node, ctx)
    LayOffsets(w, 0, w:GetWidth())
    w:SetScript("OnSizeChanged", function(self) LayOffsets(self, 0, self:GetWidth()) end)
end

function anchor.refresh(w, node, ctx)
    if w.repaintPad then w.repaintPad() end
    RefreshSubs(w, ctx)
    local alpha = ns.IsDisabled(node, ctx) and 0.4 or 1
    PaintCaptions(w, ctx.app.skin, alpha)
    -- The heading wears a field label's color AND its size: it is drawn
    -- on the label line, beside the field's own label, so anything else
    -- reads as a second font rather than as the other half of the same
    -- heading. `bpLabelSize` is the group preset's, published by Page.lua
    -- (a composite cannot see the group it was drawn into).
    if w.hdr then
        local c = ns.PresetColor(nil, ctx.app.skin, "labelFg")
        w.hdr:SetTextColor(C(c, 1, alpha))
        ns.SetFontSize(w.hdr, w.bpLabelSize or 11)
    end
    -- After the label has its text: the offsets are laid out clear of it,
    -- and at apply time it may not have been set yet.
    LayOffsets(w, 0, w:GetWidth())
end

-- Wide enough for the pad, a caption column and one offset track -- and no
-- wider. Not stretchy: extra room on the line goes to controls that can use
-- it, not to a position widget that cannot.
function anchor.measure(field)
    -- The caption column cannot be measured before the captions exist, so
    -- measure uses the same per-character estimate FieldMetrics does for a
    -- label; the layout then uses the real string width.
    local capW = math.max(CAP_MIN, math.min(CAP_MAX, #"X" * 5.4 + 4))
    -- The left half is the pad OR the field's own label, whichever is
    -- wider: the label sits over the pad and the "Offsets" heading starts
    -- where the tracks do, so a label longer than the pad pushes the whole
    -- right half across. Asked for HERE as well as applied in LayOffsets,
    -- or the cell is measured for a narrower widget than the one that gets
    -- drawn and the tracks are squeezed to pay for the label.
    local labelW = ns.TextWidth(ns.FieldLabel(field) or "")
    local leftW  = math.max(PAD_SIZE + 14, labelW + 16)
    local wide   = leftW + capW + 4 + OFFSET_W
    -- The heading plus two rows that carry their range is taller than the
    -- pad, so the widget is as tall as whichever side is taller rather than
    -- as tall as the pad it used to match exactly.
    local rows = (ns.SLIDER_H_COMPACT_RANGE or SLIDER_H) * 2
    return wide, wide - 60, math.max(PAD_SIZE + PAD_GAP, rows)
end
anchor.stretch = false

-- ── Offsets (X and Y, no pad) ──────────────────────────────────
--
-- The anchor widget's right-hand half, standing on its own: two numbers
-- that position something, where there is no point to hang them off. The
-- Frames page's anchor X/Y are that -- the flat is positioned by
-- coordinates against a fixed anchor -- and as two separate slider fields
-- they read as two unrelated settings that happen to sit in one card.
--
-- The captions are the field's own words rather than "X" and "Y", so the
-- column is measured from them instead of fixed: "X Position" is the whole
-- label, and a caption column sized for one letter would clip it.
local OFFSET_CAP_MIN = 14
local OFFSET_CAP_MAX = 90

local function CaptionFor(node, key, fallback)
    local caps = node.captions
    local c = (type(caps) == "table") and caps[key] or nil
    if type(c) == "function" then c = c(node) end
    return tostring(c or fallback)
end

-- The caption column: as wide as the wider of the two, within bounds. The
-- font is GameFontDisableSmall, so the per-character estimate is the same
-- one FieldMetrics uses for labels, a shade narrower.
local function CaptionW(w)
    local widest = 0
    for _, f in pairs(w.caps or {}) do
        widest = math.max(widest, (f:GetStringWidth() or 0))
    end
    return math.max(OFFSET_CAP_MIN, math.min(OFFSET_CAP_MAX, widest + 4))
end

-- An optional BUTTON on each row, to the right of its slider: "center this
-- axis", "reset this axis" -- an action that belongs to the number beside
-- it rather than to the card. Both are sized to the wider of the two, so
-- the pair reads as a column rather than as two buttons that happen to be
-- near each other.
local BTN_GAP = 8

-- A row button is as tall as the value BOX on its row, not as tall as a
-- standalone button: SLIDER_H_COMPACT is defined as the box plus 4, so this
-- is the box's own height, and the 4px that separates the two rows separates
-- the two buttons. ROW_H (22) is TALLER than the row pitch (21), so a pair
-- built at that height overlapped by a pixel -- the lower button drawn over
-- the upper one's bottom border -- and the centring offset landed on a half
-- pixel as well.
local BTN_H = math.max(14, SLIDER_H - 4)

local function ButtonKey(key) return key .. "Btn" end

-- Both buttons take the width of the wider, so the pair reads as a column.
-- The width itself is the BUTTON control's answer, icon or text alike -- this
-- does not second-guess it.
local function ButtonColW(w)
    local widest = 0
    for _, key in ipairs({ "x", "y" }) do
        local sub = w.subs and w.subs[ButtonKey(key)]
        if sub and sub.node then
            widest = math.max(widest, (sub.def.measure(sub.node)) or 0)
        end
    end
    return widest
end

-- Which control the two rows are made of. `slider` unless the field says
-- otherwise -- a pair of stepped whole numbers (frame spacing) reads better
-- as two steppers, and it is the same composite either way.
local function SubKind(node)
    local k = node and node.sub
    return (k == "stepper") and "stepper" or "slider"
end

-- One row's WIDTH and HEIGHT, asked of the control rather than assumed.
--
-- Both used to be written down here -- the compact-slider height, and a
-- track width of this file's own choosing -- which is right only while the
-- rows are compact sliders. A row that shows its range is taller, a stepper
-- is taller again and narrower, and a control's DEFAULT WIDTH is the
-- control's business: a slider inside a composite is a slider's width, a
-- stepper a stepper's, exactly as they are anywhere else on the page.
--
-- `valuePlacement = "side"`, because that is what SideBox puts on the real
-- sub-node: a probe that let the panel's "below" default through would
-- measure a taller layout than the rows are actually built with.
local function SubMetrics(node, ctx)
    local kind = SubKind(node)
    local def  = ns.builtinControls[kind]
    if not def then return ns.CONTROL_W, SLIDER_H end
    local probe = { control = kind, compact = true, range = true,
                    valuePlacement = "side", min = 0, max = 100 }
    local pref, _, h = def.measure(probe, ns.CONTROL_W, ctx)
    pref = pref or ns.CONTROL_W

    -- Match the TRACK, not the widget.
    --
    -- A slider measures ns.CONTROL_W either way, but that width means two
    -- different things: with the box BELOW the track it is all track, and
    -- with the box beside it the box and its gap come out of it. A composite
    -- forces the box beside (SideBox), so its track is short by 46 + 6 --
    -- which the file used to describe as "the same width as a slider
    -- anywhere else", true only if you measure the widget rather than the
    -- thing the reader drags.
    if kind == "slider" then
        pref = pref + (ns.SLIDER_BOX_W or 46) + (ns.SLIDER_BOX_GAP or 6)
    end
    return pref, h or SLIDER_H
end

local function LayPlainOffsets(w, right)
    local capW = CaptionW(w)
    local barL = capW + 4
    local btnW = ButtonColW(w)
    local room = right - barL - ((btnW > 0) and (btnW + BTN_GAP) or 0)
    -- The control's OWN default width, never more.
    local barW = math.max(90, math.min(w.bpSubW or ns.CONTROL_W, room))
    local rowH = w.bpRowH or SLIDER_H

    for i, key in ipairs({ "x", "y" }) do
        local rowY = (i - 1) * rowH
        local s = w.subs[key].w
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", w, "TOPLEFT", barL, -rowY)
        s:SetWidth(barW)
        -- Shown explicitly: a widget parked by Sub above is hidden, and the
        -- one that replaced it has to say it is not.
        s:Show()

        -- Centered on the thing at eye level on that row: a slider's value
        -- box, or -- for a control that has none -- the control itself.
        w.caps[key]:ClearAllPoints()
        if s.box then
            local boxMid = 2 + (s.box:GetHeight() or 19) / 2
            w.caps[key]:SetPoint("LEFT", s, "TOPLEFT", -(capW + 4), -boxMid)
        else
            w.caps[key]:SetPoint("RIGHT", s, "LEFT", -4, 0)
        end

        local b = w.subs[ButtonKey(key)]
        if b and b.node then
            -- Anchored to the slider's VALUE BOX, not positioned by
            -- arithmetic against the row. The box is the thing at eye level
            -- on that row, and the three pieces of the row were each
            -- measuring from a different reference -- the caption from the
            -- box's create-time inset, the button from the row's pitch --
            -- which is why they did not line up. An anchor cannot drift.
            b.w:ClearAllPoints()
            b.w:SetSize(btnW, BTN_H)
            b.w:SetPoint("LEFT", s.box or s, "RIGHT", BTN_GAP, 0)
            b.w:Show()
        end
    end
end

-- Per-AXIS settings, unlike the pad's shared pair: the two axes of a frame
-- position are bounded by the screen's half-width and half-height, which
-- are not the same number. A bind entry may carry its own min/max/step (and
-- its own desc); the composite's are the fallback.
local function AxisOpt(node, key, field, fallback)
    local e = node.binds and node.binds[key]
    local v = (type(e) == "table") and e[field] or nil
    if v == nil then v = node[field] end
    if v == nil then v = fallback end
    return v
end

local offsets = {}
function offsets.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(SLIDER_H * 2)
    return w
end

function offsets.apply(w, node, ctx)
    local kind = SubKind(node)
    w.bpSubW, w.bpRowH = SubMetrics(node, ctx)
    w:SetHeight(w.bpRowH * 2)
    for _, key in ipairs({ "x", "y" }) do
        local sub = Sub(w, key, kind)
        Bind(w, key, SubNode(node, ctx, key, SideBox({
            control = kind, compact = true,
            -- The min and max under the track. A field in its own right
            -- carries its range in the footer; a pair inside a composite
            -- had nothing saying what the track spanned.
            range = true,
            min  = AxisOpt(node, key, "min",  -200),
            max  = AxisOpt(node, key, "max",   200),
            step = AxisOpt(node, key, "step",    1),
            -- The tooltip comes down with the rest: a slider inside a
            -- composite has no label of its own to carry one.
            desc = AxisOpt(node, key, "desc",  nil),
        })), ctx, sub)
    end
    Caption(w, "x", CaptionFor(node, "x", "X"))
    Caption(w, "y", CaptionFor(node, "y", "Y"))

    -- The row buttons, if the field declared any. A button is not bound to
    -- anything, so it does not go through SubNode: what it inherits is the
    -- composite's disabled state, plus its own if it declared one.
    for _, key in ipairs({ "x", "y" }) do
        local spec = node.buttons and node.buttons[key]
        if spec then
            local sub  = Sub(w, ButtonKey(key), "button")
            local text = spec.text or spec.label
            Bind(w, ButtonKey(key), {
                control = "button",
                -- The caption rides along under the icon: the button hides
                -- it, and it is what the tooltip below says.
                text     = text,
                icon     = spec.icon,
                iconSize = spec.iconSize,
                desc    = spec.desc,
                danger  = spec.danger,
                -- The click records an undo point for its OWN axis before
                -- the page's handler runs.
                --
                -- A row button acts on the setting beside it through the
                -- page's own writer, which never passes through ns.SetValue
                -- -- so nothing was recorded, and the field menu, which
                -- opens only when it has an entry to offer, did not open at
                -- all. Right-clicking a centered slider looked broken when
                -- it was merely empty.
                --
                -- The sub-node is the one the slider on this row is bound
                -- through, so the record lands under the key the menu reads
                -- and cannot name the wrong setting: the buttons are
                -- per-axis by construction.
                onClick = spec.onClick and function(bnode, bctx)
                    local axis = w.subs and w.subs[key]
                    if axis and axis.node then
                        ns.RecordUndo(axis.node, bctx or ctx)
                    end
                    return spec.onClick(bnode, bctx)
                end or nil,
                disabled = function()
                    return ns.IsDisabled(node, ctx)
                        or (spec.disabled ~= nil and ns.IsDisabled(spec, ctx))
                end,
            }, ctx, sub)

            -- Its OWN tooltip, carrying the words the icon replaced.
            --
            -- WRAPPED around the scripts, not hooked onto them. button.apply
            -- ends by calling InstallHover, which SetScripts OnEnter/OnLeave
            -- -- and a SetScript drops any HookScript chain already on the
            -- frame. So the library's once-only hook (AttachOwnTooltip)
            -- survived the first apply and was wiped by the second, taking
            -- the tooltip with it. Re-wrapping the CURRENT script after every
            -- apply cannot come adrift, and does not stack: the next apply
            -- replaces the wrapper before this one puts a new one on.
            --
            -- `bpTipOwn` still marks the button as spoken for, so
            -- AttachFieldTooltip's walk leaves it alone rather than putting
            -- the composite's description on it -- the same claim the anchor
            -- pad's cells make.
            sub.w.bpTipOwn = true
            local tipTitle, tipDesc = text, spec.desc
            local app = ctx.app
            local prevEnter = sub.w:GetScript("OnEnter")
            local prevLeave = sub.w:GetScript("OnLeave")
            sub.w:SetScript("OnEnter", function(self, ...)
                if prevEnter then prevEnter(self, ...) end
                ns.context.Show(self, app, tipTitle, tipDesc)
            end)
            sub.w:SetScript("OnLeave", function(self, ...)
                if prevLeave then prevLeave(self, ...) end
                ns.context.Hide()
            end)
            sub.w:Show()
        else
            -- Pooled widgets outlive the field they were built for: an
            -- `offsets` reused for a field with no buttons must not keep
            -- the last one's. Cleared as well as hidden, because the
            -- layout and the width both key off the remembered node.
            local stale = w.subs and w.subs[ButtonKey(key)]
            if stale then stale.node = nil; stale.w:Hide() end
        end
    end

    LayPlainOffsets(w, w:GetWidth())
    w:SetScript("OnSizeChanged", function(self) LayPlainOffsets(self, self:GetWidth()) end)
end

function offsets.refresh(w, node, ctx)
    RefreshSubs(w, ctx)
    PaintCaptions(w, ctx.app.skin, ns.IsDisabled(node, ctx) and 0.4 or 1)

    -- A caption may be a function, and a sub-slider's `get` may have moved
    -- its own bounds, so the column is re-measured rather than frozen at
    -- apply. Cheap: two string widths and two SetPoints.
    Caption(w, "x", CaptionFor(node, "x", "X"))
    Caption(w, "y", CaptionFor(node, "y", "Y"))
    LayPlainOffsets(w, w:GetWidth())
end

-- A caption column and one offset track. Not stretchy, for the reason the
-- anchor widget is not: an offset is a small number over a small range, and
-- a 300px track for it just makes the control hard to aim.
function offsets.measure(node, _, ctx)
    local capW = math.max(OFFSET_CAP_MIN, math.min(OFFSET_CAP_MAX,
        math.max(#CaptionFor(node, "x", "X"), #CaptionFor(node, "y", "Y")) * 5.4 + 4))
    -- The button column, from the button control's own sizing rule. Asked
    -- here rather than measured off the widgets, because measure runs
    -- before any of them exist.
    local btnW = 0
    for _, key in ipairs({ "x", "y" }) do
        local spec = node.buttons and node.buttons[key]
        if spec then
            btnW = math.max(btnW, ns.builtinControls.button.measure({
                text = spec.text or spec.label,
                icon = spec.icon, iconSize = spec.iconSize,
            }))
        end
    end
    local subW, rowH = SubMetrics(node, ctx)
    local wide = capW + 4 + subW + ((btnW > 0) and (btnW + BTN_GAP) or 0)
    return wide, math.max(120, wide - 60), rowH * 2
end
offsets.stretch = false

-- ── Text position (anchor + justification) ─────────────────────

-- Icons, not words. Justification is the one setting whose icon says it
-- better than its name does, and three glyphs take a third of the width of
-- three labels. The text is still carried on each option, so nothing that
-- wants the word has lost it.
local JUSTIFY_OPTS = {
    { value = "LEFT",   text = "Left",   icon = "justify-left"   },
    { value = "CENTER", text = "Center", icon = "justify-center" },
    { value = "RIGHT",  text = "Right",  icon = "justify-right"  },
}

local textpos = {}
function textpos.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(PAD_SIZE + 12 + 13 + ROW_H + 4)
    BuildPad(w)
    -- A cell's worth of gap above the grid, the same PAD_GAP that separates
    -- its rows: flush with the widget's top the pad read as pinned to the
    -- card rather than as a block of nine squares, and the offsets beside it
    -- start below their own heading anyway.
    w.pad:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -PAD_GAP)
    return w
end

function textpos.apply(w, node, ctx)
    OffsetNodes(w, node, ctx)

    local sj = Sub(w, "justify", "segmented")
    local jn = SubNode(node, ctx, "justify",
                       { control = "segmented", options = node.justifyOptions or JUSTIFY_OPTS })
    Bind(w, "justify", jn, ctx, sj)
    Caption(w, "justify", "Justification")

    -- Justification follows the anchor when the anchor changes, and is
    -- freely adjustable afterwards. There is no "auto" value to get stuck
    -- in: picking a point simply writes a justification too.
    WirePad(w, node, ctx, function(point)
        local j = JUSTIFY_FOR[point]
        if j and node.binds.justify then
            ns.SetValue({ bind = node.binds.justify }, ctx, j)
            ctx.app:RefreshBinding(node.binds.justify)
        end
    end)

    -- Justification sits UNDER the pad-and-offsets block, not beside it:
    -- those two are now exactly the same height and read as one unit, so
    -- anything else belongs on its own line rather than wedged in.
    local function layout(self)
        LayOffsets(self, 0, self:GetWidth())
        local top = PAD_SIZE + 10
        self.caps.justify:ClearAllPoints()
        self.caps.justify:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
        local j = self.subs.justify.w
        j:ClearAllPoints()
        j:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(top + 13))
        -- A segmented control sizes itself from the width it is GIVEN.
        -- Without this it is zero wide and simply does not appear.
        j:SetWidth(self.subs.justify.def.measure(self.subs.justify.node))
    end
    layout(w)
    w:SetScript("OnSizeChanged", layout)
end

function textpos.refresh(w, node, ctx)
    anchor.refresh(w, node, ctx)   -- RefreshSubs covers the justify picker too
end

function textpos.measure()
    -- Same estimate the anchor uses, and the same reason: the captions do
    -- not exist yet when this runs.
    local capW = math.max(CAP_MIN, math.min(CAP_MAX, #"X" * 5.4 + 4))
    local wide = PAD_SIZE + 14 + capW + 4 + OFFSET_W
    -- The pad-and-offsets block, then the justification row under it. The
    -- block is as tall as its taller half, which is now the heading plus the
    -- two rows.
    local block = math.max(PAD_SIZE + PAD_GAP,
                           (ns.SLIDER_H_COMPACT_RANGE or SLIDER_H) * 2)
    return wide, wide - 60, block + 12 + 13 + ROW_H + 4
end
textpos.stretch = false

-- ── Font row ───────────────────────────────────────────────────
-- Face, size and outline are always set together, so they are one control
-- on one line rather than three fields the reader has to associate.

local OUTLINES = {
    { value = "NONE", text = "None" }, { value = "OUTLINE", text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick" },
}

local fontrow = {}
function fontrow.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(ROW_H + 28)
    return w
end

function fontrow.apply(w, node, ctx)
    local sf = Sub(w, "face",    "dropdown")
    local ss = Sub(w, "size",    "slider")
    local so = Sub(w, "outline", "segmented")

    Bind(w, "face", SubNode(node, ctx, "face",
        { control = "dropdown", options = node.fonts or {} }), ctx, sf)
    Bind(w, "size", SubNode(node, ctx, "size",
        SideBox({ control = "slider",
                  min = node.min or 6, max = node.max or 32 })), ctx, ss)
    Bind(w, "outline", SubNode(node, ctx, "outline",
        { control = "segmented", options = node.outlines or OUTLINES }), ctx, so)

    Caption(w, "face", "Font")
    Caption(w, "size", "Size")
    Caption(w, "outline", "Outline")

    local function layout(self)
        local total = self:GetWidth()
        local outW  = 170
        local sizeW = 150
        local faceW = math.max(110, total - outW - sizeW - 20)
        local col   = { 0, faceW + 10, faceW + sizeW + 20 }
        local wid   = { faceW, sizeW, outW }
        for i, key in ipairs({ "face", "size", "outline" }) do
            self.caps[key]:ClearAllPoints()
            self.caps[key]:SetPoint("TOPLEFT", self, "TOPLEFT", col[i], 0)
            local sw = self.subs[key].w
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", self, "TOPLEFT", col[i], -13)
            sw:SetWidth(wid[i])
        end
    end
    layout(w)
    w:SetScript("OnSizeChanged", layout)
end

function fontrow.refresh(w, node, ctx)
    RefreshSubs(w, ctx)
    PaintCaptions(w, ctx.app.skin, ns.IsDisabled(node, ctx) and 0.4 or 1)
end

function fontrow.measure() return 470, 360, ROW_H + 28 end
fontrow.stretch = true

-- ── Color with a class-color override ────────────────────────
-- The swatch stays visible when "use class color" is on, but disabled --
-- hiding it would make the row jump, and the stored color is still what
-- you get back when the toggle goes off again.

local colorclass = {}
function colorclass.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(ROW_H)
    return w
end

local function UsingClass(node, ctx)
    return node.binds.useClass
       and ns.GetValue({ bind = node.binds.useClass }, ctx) and true or false
end

function colorclass.apply(w, node, ctx)
    local sc = Sub(w, "color", "color")
    local su = Sub(w, "useClass", "switch")

    local cn = SubNode(node, ctx, "color", { control = "color", alpha = node.alpha })
    cn.disabled = function()
        return ns.IsDisabled(node, ctx) or UsingClass(node, ctx)
    end
    Bind(w, "color", cn, ctx, sc)
    Bind(w, "useClass", SubNode(node, ctx, "useClass", { control = "switch" }), ctx, su)
    Caption(w, "useClass", node.classLabel or "Use class color")

    local function layout(self)
        self.subs.color.w:ClearAllPoints()
        self.subs.color.w:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        self.subs.color.w:SetWidth(52)
        self.subs.useClass.w:ClearAllPoints()
        self.subs.useClass.w:SetPoint("TOPLEFT", self, "TOPLEFT", 62, 0)
        self.caps.useClass:ClearAllPoints()
        self.caps.useClass:SetPoint("LEFT", self.subs.useClass.w, "RIGHT", 6, 0)
    end
    layout(w)
    w:SetScript("OnSizeChanged", layout)
end

function colorclass.refresh(w, node, ctx)
    RefreshSubs(w, ctx)
    PaintCaptions(w, ctx.app.skin, ns.IsDisabled(node, ctx) and 0.4 or 1)
end

function colorclass.measure(node)
    local wdt = 74 + #tostring(node.classLabel or "Use class color") * 6.2 + 40
    return wdt, wdt, ROW_H
end
colorclass.stretch = false

-- ── Stepper ────────────────────────────────────────────────────
-- One number, changed by a click rather than by aiming at a slider. For
-- small integer ranges where a slider is imprecise and oversized.

-- The min/max footer, as a slider wears it: one line of the small font
-- under the control, the low end at the left and the high end at the right.
-- A stepper hides its range worse than a slider does -- there is no track to
-- read a position off -- so it says the numbers too.
-- One line of the small font, the 2px the buttons are inset from the body's
-- bottom edge, and a gap so the numbers clear the border rather than sitting
-- on it.
local STEPPER_RANGE_H = 14

local function StepperShowsRange(node)
    return node.range ~= false
end

local stepper = {}
function stepper.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bpApp = app
    w:SetHeight(ROW_H + STEPPER_RANGE_H)

    -- The CONTROL is a frame of its own inside the widget, so the footer can
    -- sit under it without the border art -- which fills whatever it is
    -- anchored to -- stretching down over the numbers.
    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT",  w, "TOPLEFT",  0, 0)
    w.body:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
    w.body:SetHeight(ROW_H)

    w.border, w.bg = ns.BorderedRound(w.body, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(w, w.border)

    w.minText = ns.FS(w, "OVERLAY", "GameFontDisableSmall")
    w.maxText = ns.FS(w, "OVERLAY", "GameFontDisableSmall")

    -- The readout is an EDIT BOX, not a label: a stepper's number is always
    -- a number, and typing 17 beats clicking + fourteen times. It reads as
    -- the same centered figure until you click into it, which is the point.
    --
    -- Three things here are load-bearing for the CARET, and none is obvious
    -- -- see the note above textinput.apply in Controls.lua, which cost a
    -- long hunt: an explicit EnableMouse, a text seed in apply rather than
    -- only in refresh, and a width the box actually HOLDS at the moment of
    -- that seed. Hence an explicit width below (kept up to date from
    -- OnSizeChanged) rather than one derived from anchors a layout pass
    -- later, and no LEFT/RIGHT anchor pair, which would override it.
    w.value = CreateFrame("EditBox", nil, w.body)
    w.value:SetPoint("CENTER")
    w.value:SetHeight(ROW_H - 6)
    w.value:SetAutoFocus(false)
    ns.SetFontObject(w.value, GameFontHighlightSmall)
    w.value:SetJustifyH("CENTER")
    w.value:SetTextInsets(2, 2, 0, 0)
    w.value:EnableMouse(true)
    ns.InstallTextFieldMouse(w.value)

    local function SizeBox(self)
        -- Whatever is left between the two buttons, and never less than a
        -- caret's worth: the widget is not stretchy, but a page may still
        -- pack it narrower than its preferred width.
        local room = (self:GetWidth() or 110) - 2 * (ROW_H - 4) - 10
        self.value:SetWidth(math.max(24, room))
    end
    w.bpSizeBox = SizeBox
    w:SetScript("OnSizeChanged", SizeBox)
    SizeBox(w)

    for _, side in ipairs({ "minus", "plus" }) do
        local b = CreateFrame("Button", nil, w.body)
        b:SetSize(ROW_H - 4, ROW_H - 4)
        b:SetPoint(side == "minus" and "LEFT" or "RIGHT", w.body,
                   side == "minus" and "LEFT" or "RIGHT",
                   side == "minus" and 2 or -2, 0)
        -- Plain 1px bars, not the pill art: a 2px-tall pill is all cap
        -- and no middle, which is the squashing trap from Controls.lua.
        b.glyph = b:CreateTexture(nil, "ARTWORK")
        b.glyph:SetSize(9, 1)
        b.glyph:SetPoint("CENTER")
        if side == "plus" then
            b.glyph2 = b:CreateTexture(nil, "ARTWORK")
            b.glyph2:SetSize(1, 9)
            b.glyph2:SetPoint("CENTER")
        end
        w[side] = b
    end

    -- The numbers sit under the BUTTON each belongs to, not out at the
    -- widget's corners. A stepper's ends are its two buttons -- that is
    -- where the eye is when it asks "how far does this go?" -- and hung off
    -- the frame's edges they read as belonging to the row rather than to
    -- the control. Anchored after the buttons exist, for obvious reasons.
    -- -5, not -1: the buttons are inset 2 from the body's bottom edge, so a
    -- 1px drop put the numbers a pixel INSIDE the border. Two to clear the
    -- edge, three to breathe.
    w.minText:SetPoint("TOP", w.minus, "BOTTOM", 0, -5)
    w.maxText:SetPoint("TOP", w.plus,  "BOTTOM", 0, -5)
    return w
end

function stepper.apply(w, node, ctx)
    ns.InstallHover(w, w, node, ctx)

    -- Bounds may be FUNCTIONS of other settings (ns.Bound), so they are
    -- asked for at the moment they are used rather than captured: a floor
    -- that depends on the highlight style has to move when that style does.
    local function clamp(v)
        local lo = ns.Bound(node.min, node, ctx, 0)
        local hi = ns.Bound(node.max, node, ctx, 100)
        return math.max(lo, math.min(hi, v))
    end
    local function bump(by)
        if ns.IsDisabled(node, ctx) then return end
        local v = clamp((ns.GetValue(node, ctx) or ns.Bound(node.min, node, ctx, 0))
                        + by * ns.Bound(node.step, node, ctx, 1))
        ns.Commit(node, ctx, v)
    end
    w.minus:SetScript("OnClick", function() bump(-1) end)
    w.plus:SetScript("OnClick",  function() bump( 1) end)

    -- The typed value commits through the SAME path the buttons take, so
    -- the effect, the undo point and the repaint are identical however the
    -- number got there.
    local box = w.value
    box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v and not ns.IsDisabled(node, ctx) then ns.Commit(node, ctx, clamp(v)) end
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- The border belongs to the FRAME here rather than to the box, so focus
    -- lights the stepper itself -- which is what the reader is editing.
    box:SetScript("OnEditFocusGained", function()
        w.bpActive = true
        ns.PaintBorder(w, "active")
    end)
    box:SetScript("OnEditFocusLost", function(self)
        w.bpActive = false
        ns.PaintBorder(w, w.bpHovered and "hover" or nil)
        self:HighlightText(0, 0)
        -- Whatever was half-typed goes back to the stored value: leaving a
        -- rejected string in the box would have the control showing a
        -- number the setting does not have.
        self:SetText(ns.SliderText(node,
            ns.GetValue(node, ctx) or ns.Bound(node.min, node, ctx, 0), ctx))
    end)

    -- Seeded HERE, not only in refresh -- one of the three caret
    -- requirements, and it also means a pooled box never shows the last
    -- field's number for a frame.
    if w.bpSizeBox then w.bpSizeBox(w) end
    box:SetText(ns.SliderText(node,
        ns.GetValue(node, ctx) or ns.Bound(node.min, node, ctx, 0), ctx))
end

function stepper.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    local v    = ns.GetValue(node, ctx) or ns.Bound(node.min, node, ctx, 0)
    local lo   = ns.Bound(node.min, node, ctx, 0)
    local hi   = ns.Bound(node.max, node, ctx, 100)

    -- The range, in the same place and the same muted color a slider puts
    -- it. Sized here as well: a widget that drops the footer should not keep
    -- the height it needed.
    local range = StepperShowsRange(node)
    w.minText:SetShown(range)
    w.maxText:SetShown(range)
    if range then
        -- Same `suffix` a slider's range takes, and for the same reason it
        -- is kept off the editable box.
        local sfx = node.suffix or ""
        w.minText:SetText(tostring(lo) .. sfx)
        w.maxText:SetText(tostring(hi) .. sfx)
        w.minText:SetTextColor(C(skin.textMuted, 1, a))
        w.maxText:SetTextColor(C(skin.textMuted, 1, a))
    end
    w:SetHeight(ROW_H + (range and STEPPER_RANGE_H or 0))

    -- Not while the reader is typing in it: a repaint mid-edit would put
    -- the stored number back under the caret.
    -- Formatted at the field's own step, like a slider's box: a stepper
    -- that steps in tenths must not display its value as a whole number.
    if not w.value:HasFocus() then w.value:SetText(ns.SliderText(node, v, ctx)) end
    w.value:SetTextColor(C(skin.text, 1, a))
    w.value:SetEnabled(not off)
    w.bg:SetVertexColor(C(skin.controlBg, 1, a))
    ns.MarkBorder(w, skin, skin.controlBorder, a)

    -- An end of the range grays its own button rather than the whole
    -- control: you can still step the other way.
    for side, atEnd in pairs({ minus = v <= lo, plus = v >= hi }) do
        local b = w[side]
        local ba = (off or atEnd) and 0.35 or 1
        b.glyph:SetColorTexture(C(skin.textMuted, 1.3, ba))
        if b.glyph2 then b.glyph2:SetColorTexture(C(skin.textMuted, 1.3, ba)) end
        b:SetEnabled(not off and not atEnd)
    end
end

function stepper.measure(node)
    return 110, 90, ROW_H + (StepperShowsRange(node or {}) and STEPPER_RANGE_H or 0)
end
stepper.stretch = false

-- ── Registration ───────────────────────────────────────────────

local B = ns.builtinControls
B.anchor       = anchor
B.offsets      = offsets
B.offset       = offsets
-- The same control holding a pair of anything -- frame width and height,
-- spacing across and down -- so it answers to the general name too.
B.pair         = offsets
B.position     = anchor
B.textposition = textpos
B.textpos      = textpos
B.fontrow      = fontrow
B.font         = fontrow
B.colorclass   = colorclass
B.stepper      = stepper
