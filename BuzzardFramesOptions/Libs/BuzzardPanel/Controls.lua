-- ============================================================
-- BuzzardPanel: Controls.lua
-- The built-in control types.
--
-- Each control is a table of four functions:
--     create(app, parent)      build the widget (pooled per app)
--     apply(w, node, ctx)      bind it to a node and write its statics
--     refresh(w, node, ctx)    re-read the value and predicates
--     measure(node)            preferred width, minimum width, height
--
-- `measure` is the layout contract from the plan: a control declares what
-- it needs and the grid gives it whole columns rather than shaving it.
-- That is what stops a four-option segmented control losing its last
-- button to a sliver.
--
-- Art: the panel owns its own. Media/round8.tga is a white rounded rect
-- used nine-sliced for every pill, track and card; circle.tga is the
-- switch knob; check.tga is the tick. All white with an alpha channel,
-- tinted at runtime from skin tokens, so one file serves every skin.
-- ============================================================
local ADDON, ns = ...

-- Where this copy's art lives. Derived in Skin.lua, which loads first --
-- the default skin names a font out of the same folder, so the path has to
-- exist before that table is built. Bound to a local here because this
-- file reads it on nearly every control.
local MEDIA = ns.MEDIA

-- checker.tga is 8x8 with 4px squares. The swatch divides its own size by
-- this to work out how many times to repeat -- see color.create.
local CHECKER_TILE = 8

local ROW_H = 22

-- ── Helpers ────────────────────────────────────────────────────

-- Rounded art comes in a SET of authored radii, and the helpers snap to the
-- nearest one.
--
-- This matters more than it looks. Nine-slicing draws the corner region
-- 1:1, so the slice margin must equal the radius the texture was authored
-- at. Slicing the 8px texture with a 5px margin samples only part of the
-- arc and draws a subtly wrong curve; slicing it with an 8px margin on a
-- 16px-tall control leaves NO middle band to stretch, and the corners get
-- squashed into the flat-sided shape the switch had.
-- 0 is a real member of the set: a square corner is a legitimate choice,
-- not the absence of one. round0.tga is a plain filled square, so the fills
-- and the corner patches keep working at radius 0 with no special case
-- beyond the slice margin below.
--
-- Outlines are the exception, and there is no ring0.tga: a square outline
-- is four plain color textures, which are exact at any scale, where art
-- would be a 1px arc resampled onto a non-integer number of pixels. See
-- ns.Outline.
local RADII = { 0, 4, 6, 8, 12 }
local function nearestRadius(r)
    r = r or 8
    local best, bestd = RADII[1], math.abs(r - RADII[1])
    for i = 2, #RADII do
        local d = math.abs(r - RADII[i])
        if d < bestd then best, bestd = RADII[i], d end
    end
    return best
end

local function sliced(parent, layer, radius, prefix)
    local r = nearestRadius(radius)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(MEDIA .. prefix .. r .. ".tga")
    if t.SetTextureSliceMargins then
        -- At radius 0 the margin is 1, not 0: the square outline's edge is
        -- one pixel, and a zero margin would stretch that pixel across the
        -- whole texture instead of keeping it at the rim.
        local m = (r == 0) and 1 or r
        t:SetTextureSliceMargins(m, m, m, m)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    -- Snap texel edges to pixel edges. Note TRUE: assigning a texture trips
    -- the client's AutoDisablePixelSnap hook, so snapping has to be turned
    -- back ON afterwards, not off. Buzzard Frames' own rounded ring does
    -- exactly this (PixelPerfect.lua, StampRingPixelHost) and it is half of
    -- why those borders look sharp; the other half is the pixel host below.
    if t.SetSnapToPixelGrid   then t:SetSnapToPixelGrid(true) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)  end

    -- Remember which SET this texture came from. Re-pointing it at another
    -- radius has to stay in the same set: the panel's border is an outline,
    -- and swapping it for a fill turns the whole panel into the border
    -- color again.
    t.bpRadius, t.bpPrefix = r, prefix
    return t
end

-- The OPPOSITE choice for the pieces a hairline border is made of.
--
-- A control's border is a ring with the surface drawn ONE PIXEL inset over
-- it, so the stroke is the strip of ring the surface leaves uncovered. With
-- pixel snapping on (the client's default for a plain texture) the ring's
-- edge and the surface's edge snap to the grid INDEPENDENTLY, and whenever
-- either lands on a half pixel they can snap the same way -- the strip
-- between them is then two pixels, or nothing. That is a border that is
-- missing along one side and doubled along another, changing as the panel
-- is resized. The soft-edged Blizzard art other option dialogs draw their
-- frames with never shows this, because a 16-texel edge blurred half a
-- pixel is still a frame; a one-pixel strip snapped away is a gap.
--
-- Unsnapped, a half-pixel edge is drawn half-covered on both textures --
-- the strip is a faint pixel wider rather than absent. On a whole pixel
-- (which the panel's own scaling arranges wherever it can) the result is
-- identical to the snapped one: crisp. Set after every SetTexture, which
-- re-arms the client's own snapping.
local function NoSnap(t)
    if t.SetSnapToPixelGrid   then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)   end
end
ns.NoSnap = NoSnap

-- Filled rounded rect.
function ns.RoundTex(parent, layer, radius)
    return sliced(parent, layer or "BACKGROUND", radius, "round")
end

-- A rounded outline, drawn 1:1.
--
-- One nine-sliced ring texture -- which is the obvious thing, and which I
-- had abandoned because it looked soft. It was soft for a reason that has
-- nothing to do with the art: the corner is drawn at `radius` UI UNITS, and
-- a UI unit is almost never a physical pixel, so an 8-texel arc was being
-- resampled onto 5.6 pixels or 11.3 pixels and smeared either way.
--
-- Buzzard Frames solves this for its own rounded frame borders and the fix
-- is a PIXEL HOST: put the ring on a child frame whose scale is stamped to
-- pixelSize / effectiveScale, and one art texel renders as exactly one
-- physical pixel at any UI scale. See ns.PixelHost.
--
-- Radius 0 still uses four plain color textures -- a square border needs no
-- art, and lines cannot be resampled at all.
function ns.Outline(parent, radius, stroke)
    local o = { parent = parent, stroke = stroke or 1,
                color = { 1, 1, 1, 1 }, shown = true, radius = 0 }
    o.lines = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        NoSnap(t)   -- see NoSnap: a snapped one-pixel line can snap to nothing
        t.side = side
        o.lines[#o.lines + 1] = t
    end

    local function placeLines()
        local w = o.stroke
        for _, t in ipairs(o.lines) do
            t:ClearAllPoints()
            if t.side == "TOP" then
                t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(w)
            elseif t.side == "BOTTOM" then
                t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(w)
            elseif t.side == "LEFT" then
                t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(w)
            else
                t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(w)
            end
        end
    end
    placeLines()

    function o:Paint()
        local c = self.color
        local square = (self.radius == 0)
        for _, t in ipairs(self.lines) do
            t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            t:SetShown(self.shown and square)
        end
        if self.ring then
            self.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            self.ring:SetShown(self.shown and not square)
        end
    end

    function o:SetRadius(r)
        self.radius = nearestRadius(r)
        if self.radius > 0 then
            if not self.ring then
                self.ring = sliced(parent, "OVERLAY", self.radius, "ring")
                self.ring:SetAllPoints(parent)
            else
                ns.SetTexRadius(self.ring, self.radius)
            end
        end
        self:Paint()
    end

    function o:SetColor(c) self.color = c; self:Paint() end
    function o:SetShown(b)  self.shown = b and true or false; self:Paint() end

    o:SetRadius(radius)
    return o
end

-- Re-point an existing sliced texture at a different radius. Used by the
-- live border controls in the demo.
function ns.SetTexRadius(t, radius)
    if not t or not t.bpRadius then return end
    local r = nearestRadius(radius)
    if r == t.bpRadius then return end
    t:SetTexture(MEDIA .. (t.bpPrefix or "round") .. r .. ".tga")
    if t.SetTextureSliceMargins then
        local m = (r == 0) and 1 or r
        t:SetTextureSliceMargins(m, m, m, m)
    end
    t.bpRadius = r
end

local function C(c, mul, alpha)
    mul = mul or 1
    return c[1] * mul, c[2] * mul, c[3] * mul, alpha or c[4] or 1
end
-- Exported because the navigators paint from the same tokens and there is
-- no reason for two copies of "read a color, brighten it, set an alpha".
ns.C = C

-- ── Square style ───────────────────────────────────────────────
--
-- Three bars in this panel can drop their cards and become one divided
-- strip instead: the rail's footer buttons, the section button bar, and
-- the status strip. They want the identical thing -- a flat fill that is
-- the whole of a button's share, a full-height rule between neighbors,
-- and a horizontal rule between wrapped rows -- so the textures and their
-- painting live here rather than in a third copy.
--
-- The rules are FULL height and the fill is the WHOLE cell, because that is
-- the difference between a bar that has been divided and a row of things
-- that happen to be adjacent. It follows that a square bar has no padding
-- and no gaps: a cell inset inside its band leaves its rules short of the
-- band's edges, which reads as decoration rather than division.
function ns.AttachSquare(b)
    if b.sqFill then return b end
    b.sqFill = b:CreateTexture(nil, "BORDER")
    b.sqFill:SetAllPoints(b)
    b.sqFill:Hide()

    b.sqRight = b:CreateTexture(nil, "OVERLAY")
    b.sqRight:SetWidth(1)
    b.sqRight:SetPoint("TOPRIGHT",    b, "TOPRIGHT",    0, 0)
    b.sqRight:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.sqRight:Hide()

    b.sqTop = b:CreateTexture(nil, "OVERLAY")
    b.sqTop:SetHeight(1)
    b.sqTop:SetPoint("TOPLEFT",  b, "TOPLEFT",  0, 0)
    b.sqTop:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.sqTop:Hide()

    -- The LEFT edge, for the first cell of a row. Without it a divided bar
    -- is open at one end and closed at the other, which reads as a mistake
    -- rather than as a choice.
    b.sqLeft = b:CreateTexture(nil, "OVERLAY")
    b.sqLeft:SetWidth(1)
    b.sqLeft:SetPoint("TOPLEFT",    b, "TOPLEFT",    0, 0)
    b.sqLeft:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.sqLeft:Hide()
    return b
end

-- `on` is the square style's own switch: off, the rounded art is shown and
-- these textures are not, so one call flips a widget between the two.
function ns.PaintSquare(b, skin, on, opts)
    if not b.sqFill then return end
    opts = opts or {}
    if not on then
        b.sqFill:Hide(); b.sqRight:Hide(); b.sqTop:Hide(); b.sqLeft:Hide()
        if b.border then b.border:Show() end
        if b.bg then b.bg:Show() end
        return
    end
    if b.border then b.border:Hide() end
    if b.bg then b.bg:Hide() end

    local c = opts.fill or skin.controlBg
    b.sqFill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    b.sqFill:Show()

    local d = skin.divider
    b.sqRight:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
    if ns.NoSnap then ns.NoSnap(b.sqRight) end
    b.sqRight:SetShown(opts.right and true or false)
    b.sqTop:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
    if ns.NoSnap then ns.NoSnap(b.sqTop) end
    b.sqTop:SetShown(opts.top and true or false)
    b.sqLeft:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
    if ns.NoSnap then ns.NoSnap(b.sqLeft) end
    b.sqLeft:SetShown(opts.left and true or false)
end

-- ── The one border treatment ───────────────────────────────────
--
-- A FILLED rounded rect tinted as the border, with a second copy inset by
-- the stroke carrying the fill. Two opaque textures give a crisp hairline
-- edge at any size.
--
-- There used to be a rounded 1px OUTLINE texture (ring*.tga) as well, and
-- it is gone. Nine-slicing draws the corner 1:1 and stretches the middle,
-- so an outline authored at radius 8 needs a control taller than 16px or
-- there is no middle band left and the corners squash the stroke into a
-- gray smear. That is why the switch, the segmented picker, the swatch and
-- the text box all looked soft and wrong while the slider's value box --
-- which happened to use the two-fill trick -- looked right. One treatment
-- now, so they cannot drift apart again.
--
-- It is built from ns.RoundedFill now, not from nine-sliced art, and that
-- is the second half of the same fix the cards got. Two things were wrong
-- with the sliced version and neither is about the treatment: the corner
-- was drawn at its texel size in UI UNITS, so at any UI scale but 1 an
-- 8-texel arc was resampled onto 5.6 or 11.3 pixels and came out soft; and
-- the two shapes were sliced at the SAME radius, so the stroke between
-- their corners was the inset times root two while the edges got the inset
-- -- a border noticeably heavier at all four corners than along the sides.
-- RoundedFill draws its corners at a size it chooses, in pixels, and
-- shrinks the inner radius by the stroke, so both faults go at once.
--
-- Returns border, fill -- not textures but the shapes wearing a texture's
-- face (see ns.ShapeTexture), which is every method the call sites use.
-- Both want a color on every refresh.
--
-- The stroke follows the CONTROL group, so one setting re-strokes every
-- control at once. An explicit `stroke` opts out and pins a width.
function ns.BorderedRound(parent, radius, borderLayer, fillLayer, stroke)
    local ringPaint = ns.RoundedFill(parent, borderLayer or "BACKGROUND",
                                     radius, nil, { 0, 0, 0, 0 }, 0)
    local fillPaint
    if stroke then
        fillPaint = ns.RoundedFill(parent, fillLayer or "BORDER",
                                   radius, nil, { 0, 0, 0, 0 }, stroke)
    else
        fillPaint = ns.StrokedFill(parent, fillLayer or "BORDER",
                                   radius, nil, { 0, 0, 0, 0 }, "control")
    end
    return ns.ShapeTexture(ringPaint), ns.ShapeTexture(fillPaint)
end

-- A rounded fill with some of its corners squared off again, built from
-- pieces that DO NOT OVERLAP.
--
-- It used to be one full-size rounded rect with square patches laid over the
-- edges that needed squaring. That is invisible while the surface is opaque
-- and obvious the moment it is not: the patch and the rect both draw at the
-- surface's alpha, so wherever they overlapped the color composited twice --
-- 0.45 over 0.45 reads as 0.70. That was the darker strip along the top and
-- right of the rail and under the title bar, exactly `radius` wide.
--
-- So the shape is decomposed into disjoint pieces instead: a full-width
-- middle band, two inset bands top and bottom, and four corners that are
-- either a cropped quadrant of the rounded art or a plain square. Every
-- pixel is painted exactly once at exactly the intended alpha.
--
-- `sides` lists the edges that should stay SQUARE, any of "T", "B", "L", "R".
-- Returns paint(color) and setRadius(r).
-- `inset` insets the whole shape, so two of these -- one at 0 in the border
-- color, one at the stroke in the surface color -- make a bordered card
-- whose corners are drawn one texel to one PHYSICAL pixel. It is counted in
-- PIXELS, not UI units, and it also shrinks the corner radius by its own
-- width, so the inner shape is concentric with the outer one and the stroke
-- between them is the same width on the corners as on the edges.
--
-- That last part is why a card uses this rather than ns.BorderedRound. A
-- nine-sliced corner is drawn at its texel size in UI UNITS, which is only
-- the same as pixels at UI scale 1; scaling the slice margins would fix it
-- but SetTextureSliceScale does not exist on this client. Here the corner is
-- a cropped quadrant whose SIZE we choose, so r texels can be drawn across
-- exactly r pixels at any scale.
-- Every live RoundedFill's place(), keyed weakly by its paint(). A scale
-- change moves the size of a physical pixel in UI units for every frame
-- in the panel at once, and each shape's corner sizes and insets were
-- computed in those units the last time it was placed. Weak keys: `paint`
-- is what every holder of a shape keeps (directly or inside a
-- ShapeTexture shim), so an entry dies with its widget.
local shapeReg = setmetatable({}, { __mode = "k" })

-- Re-derive every shape's pixel geometry where it stands, then repaint it
-- (a gradient's span is pixel-derived too). Called by ns.RestampPanel
-- after a scale change: without this, a live change left every border's
-- pieces at the OLD pixel size -- strokes half gone -- while a reload,
-- which builds everything at the new scale from scratch, looked right.
function ns.RestampShapes()
    for paint, place in pairs(shapeReg) do
        place()
        paint()
    end
end

function ns.RoundedFill(frame, layer, radius, sides, color, inset)
    layer = layer or "BACKGROUND"
    sides = tostring(sides or "")
    local square = {
        TOPLEFT     = sides:find("T") or sides:find("L"),
        TOPRIGHT    = sides:find("T") or sides:find("R"),
        BOTTOMLEFT  = sides:find("B") or sides:find("L"),
        BOTTOMRIGHT = sides:find("B") or sides:find("R"),
    }

    local mid    = frame:CreateTexture(nil, layer)
    local top    = frame:CreateTexture(nil, layer)
    local bottom = frame:CreateTexture(nil, layer)
    -- The two side strips a FACE needs (see setFace): a relief that is lit
    -- along its left edge and shaded along its right cannot be carried by
    -- a middle piece that stretches across the whole width, so in face
    -- mode the middle is flanked by an r-wide strip each side sampling the
    -- art's own edge columns. Hidden for a flat color, which has no edges
    -- to carry.
    local left   = frame:CreateTexture(nil, layer)
    local right  = frame:CreateTexture(nil, layer)
    left:Hide(); right:Hide()
    local corner = {}
    for _, pt in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        corner[pt] = frame:CreateTexture(nil, layer)
    end

    local ins = inset or 0
    -- A FACE: one texture sampled across all seven pieces instead of a
    -- flat color -- set by setFace below. The art is a 32x32 with 8-texel
    -- corners baked into its alpha (Media/buttonface.tga): each corner
    -- piece samples its own quadrant, the bands the strip between them,
    -- and the middle the middle -- so the art's relief joins up across the
    -- shape at any size, and its arc scales with the piece it is drawn on.
    -- Every piece is then TINTED (vertex color) rather than filled.
    local face
    -- THE BOTTOM EDGE'S OWN INSET, when it differs.
    --
    -- Normally a shape is inset by the same amount all round. One case is
    -- not: a bordered shape that has to be OPEN along one edge -- a
    -- square-bottomed selected tab, which runs into the page beneath it. The
    -- border is a ring with the fill drawn inset over it, so there is no way
    -- to leave one edge out by painting; drawing the FILL out to the frame's
    -- bottom covers that edge instead, and nothing has to guess a color to
    -- patch it with. nil means "same as `ins`".
    local insBottom
    local rPx, last = 0, color or { 1, 1, 1, 1 }

    local function place()
        -- The corner pieces are sized in PHYSICAL pixels, not UI units, so
        -- a region's rounding matches the panel background and border --
        -- both of which are drawn on pixel hosts. Without this the regions
        -- round more (or less) than the shape behind them and their arcs
        -- cross it.
        local u = (ns.PixelUnit and ns.PixelUnit(frame)) or 1

        -- THE INSET IS IN PHYSICAL PIXELS, like the radius.
        --
        -- It used to be UI units, so a 1px stroke drew as 0.67 of a pixel at
        -- one UI scale and 1.5 at another -- a border that was faint along
        -- one edge and doubled along the next, which is what made the cards
        -- look uneven while the panel's own border (on a pixel host) did
        -- not. One unit here is one pixel at any scale.
        local insU = ins * u

        -- AND THE INNER SHAPE IS CONCENTRIC WITH THE OUTER ONE.
        --
        -- Two of these make a border: the ring at inset 0 and the body at
        -- the stroke. They used to be drawn at the SAME corner radius, and
        -- two equal-radius arcs offset diagonally are not parallel -- the
        -- gap between them along the 45 degree line is the inset times root
        -- two, so every corner wore a border ~41% thicker than its edges.
        -- Shrinking the inner radius by the inset makes the arcs share a
        -- center, and the stroke is the same width the whole way round.
        --
        -- The ART stays the one it was authored as (rPx below): the corner
        -- is a cropped quadrant drawn at a size we choose, so the same
        -- quadrant scaled to r draws the smaller arc.
        local r = math.max(0, rPx - ins) * u

        -- The bottom's own inset and its own corner radius, which are the
        -- shared ones unless this shape opens at the bottom.
        local insB  = (insBottom or ins)
        local insUB = insB * u
        local rB    = math.max(0, rPx - insB) * u

        mid:ClearAllPoints()
        mid:SetPoint("TOPLEFT",     frame, "TOPLEFT",      insU, -(r + insU))
        mid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insU,   rB + insUB)

        top:ClearAllPoints()
        top:SetPoint("TOPLEFT",  frame, "TOPLEFT",    r + insU, -insU)
        top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(r + insU), -insU)
        top:SetHeight(math.max(r, 0.01))
        top:SetShown(r > 0)

        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",    rB + insU, insUB)
        bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(rB + insU), insUB)
        bottom:SetHeight(math.max(rB, 0.01))
        bottom:SetShown(rB > 0)

        for pt, t in pairs(corner) do
            t:ClearAllPoints()
            local isBottom = pt:find("BOTTOM") and true or false
            local cr_ = isBottom and rB or r
            t:SetShown(cr_ > 0)
            if cr_ > 0 then
                t:SetSize(cr_, cr_)
                t:SetPoint(pt, frame, pt,
                           pt:find("RIGHT") and -insU or insU,
                           isBottom and insUB or -insU)
                if face then
                    t:SetTexture(face)
                    local l = pt:find("RIGHT")  and 0.75 or 0
                    local tp = pt:find("BOTTOM") and 0.75 or 0
                    t:SetTexCoord(l, l + 0.25, tp, tp + 0.25)
                elseif square[pt] then
                    -- THE TEXCOORD GOES WITH THE TEXTURE.
                    --
                    -- A round corner samples a sub-rect of round<r>.tga --
                    -- (0, 0.1875, 0.8125, 1) for a 6px bottom-left. Squaring
                    -- it cleared the texture and left that sub-rect behind,
                    -- and `paint` then supplies a 1x1 solid through
                    -- SetColorTexture: the stale rect samples it degenerately
                    -- and the corner draws NOTHING. Since mid/top/bottom stop
                    -- short of the corners on purpose, what showed was an
                    -- r-by-r hole straight through to the page -- the dark
                    -- notches on the bottom corners of every square-bottomed tab.
                    --
                    -- Reset before clearing, so no state of the round look
                    -- outlives it.
                    t:SetTexCoord(0, 1, 0, 1)
                    t:SetTexture(nil)
                else
                    t:SetTexture(MEDIA .. "round" .. rPx .. ".tga")
                    local f  = rPx / 32
                    local rt = pt:find("RIGHT")  and 1 or f
                    local l  = pt:find("RIGHT")  and (1 - f) or 0
                    local bt = pt:find("BOTTOM") and 1 or f
                    local tp = pt:find("BOTTOM") and (1 - f) or 0
                    t:SetTexCoord(l, rt, tp, bt)
                end
            end
        end
        if face then
            top:SetTexture(face);    top:SetTexCoord(0.25, 0.75, 0,    0.25)
            mid:SetTexture(face);    mid:SetTexCoord(0.25, 0.75, 0.25, 0.75)
            bottom:SetTexture(face); bottom:SetTexCoord(0.25, 0.75, 0.75, 1)
            -- The middle gives up r each side to the strips.
            mid:ClearAllPoints()
            mid:SetPoint("TOPLEFT",     frame, "TOPLEFT",      r + insU, -(r + insU))
            mid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(r + insU),  rB + insUB)
            left:SetTexture(face);  left:SetTexCoord(0,    0.25, 0.25, 0.75)
            right:SetTexture(face); right:SetTexCoord(0.75, 1,    0.25, 0.75)
            left:ClearAllPoints()
            left:SetPoint("TOPLEFT",    frame, "TOPLEFT",    insU, -(r + insU))
            left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insU,   rB + insUB)
            left:SetWidth(math.max(r, 0.01))
            right:ClearAllPoints()
            right:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -insU, -(r + insU))
            right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insU,   rB + insUB)
            right:SetWidth(math.max(r, 0.01))
            left:SetShown(r > 0); right:SetShown(r > 0)
        else
            left:Hide(); right:Hide()
        end
        -- Every piece, every placement: a SetTexture above re-arms snapping.
        NoSnap(mid); NoSnap(top); NoSnap(bottom); NoSnap(left); NoSnap(right)
        for _, t in pairs(corner) do NoSnap(t) end
    end

    -- A VERTICAL GRADIENT across the whole shape, or nil for the flat
    -- color. Set by setGradient below and applied here piece by piece:
    -- each of the seven pieces spans a slice of the shape's height, so it
    -- gets the gradient's colors AT ITS OWN top and bottom, and the seven
    -- slices join into one continuous ramp. The base color's alpha still
    -- applies, so ShapeTexture can hide the shape as it always has.
    local gTop, gBot
    local hadGrad = false

    local function paint(c)
        last = c or last
        local cr, cg, cb, ca = last[1], last[2], last[3], last[4] or 1
        if face then
            -- The art carries the color and the shape; the paint is a tint.
            for _, t in ipairs({ mid, top, bottom, left, right }) do
                t:SetVertexColor(cr, cg, cb, ca)
            end
            for _, t in pairs(corner) do t:SetVertexColor(cr, cg, cb, ca) end
            return
        end
        if gTop and gBot and CreateColor then
            hadGrad = true
            local h = frame:GetHeight() or 0
            local u = (ns.PixelUnit and ns.PixelUnit(frame)) or 1
            local insU  = ins * u
            local insUB = (insBottom or ins) * u
            local r  = math.max(0, rPx - ins) * u
            local rB = math.max(0, rPx - (insBottom or ins)) * u
            local span = math.max(1, h - insU - insUB)
            -- Where a piece starts and ends, as fractions of the shape.
            local function at(f)
                return gTop[1] + (gBot[1] - gTop[1]) * f,
                       gTop[2] + (gBot[2] - gTop[2]) * f,
                       gTop[3] + (gBot[3] - gTop[3]) * f
            end
            local function ramp(t, f0, f1)
                local r0, g0, b0 = at(f0)
                local r1, g1, b1 = at(f1)
                -- VERTICAL: the first color is the BOTTOM, the second the top.
                t:SetGradient("VERTICAL", CreateColor(r1, g1, b1, ca),
                                          CreateColor(r0, g0, b0, ca))
            end
            local fTop = math.min(1, r / span)
            local fBot = math.max(0, 1 - rB / span)
            for _, t in ipairs({ mid, top, bottom }) do
                t:SetColorTexture(1, 1, 1, 1)
            end
            ramp(top,    0,    fTop)
            ramp(mid,    fTop, fBot)
            ramp(bottom, fBot, 1)
            for pt, t in pairs(corner) do
                if square[pt] then t:SetColorTexture(1, 1, 1, 1) end
                if pt:find("BOTTOM") then ramp(t, fBot, 1) else ramp(t, 0, fTop) end
            end
            return
        end
        for _, t in ipairs({ mid, top, bottom }) do
            t:SetColorTexture(cr, cg, cb, ca)
            -- A ramp is vertex color, which SetColorTexture leaves alone:
            -- once a piece has carried one it has to be told it is flat.
            if hadGrad then t:SetVertexColor(1, 1, 1, 1) end
        end
        for pt, t in pairs(corner) do
            if square[pt] then
                -- A square corner carries its color in the TEXTURE, a round
                -- one in the vertex color. The two multiply, so a corner
                -- that has been both needs the other half neutralised or it
                -- paints at color-squared. White costs nothing when the
                -- corner has only ever been square.
                t:SetColorTexture(cr, cg, cb, ca)
                t:SetVertexColor(1, 1, 1, 1)
            else
                t:SetVertexColor(cr, cg, cb, ca)
            end
        end
        hadGrad = false
    end

    -- The ramp, top color then bottom color ({r, g, b}); nil, nil for
    -- flat. Takes effect on the next paint.
    local function setGradient(topC, botC)
        gTop, gBot = topC, botC
    end

    -- The face texture (a path), or nil for a flat color. Re-places, so
    -- every piece takes its sub-rect of the art.
    local function setFace(path)
        face = path
        place()
        paint()
    end

    local function setRadius(newRadius)
        rPx = nearestRadius(newRadius)
        place()
        paint()
    end

    -- The inset is a live knob too, so a caller whose stroke can change --
    -- the menu, whose border width is a style option -- re-insets the one
    -- shape it already has instead of building a second one over the first.
    -- The bottom edge on its own. nil puts it back with the rest.
    local function setInsetBottom(newInset)
        if insBottom == newInset then return end
        insBottom = newInset
        place()
        paint()
    end

    local function setInset(newInset)
        ins = newInset or 0
        place()
        paint()
    end

    -- Which corners stay square is a live knob too: a collapsed TAB header
    -- has nothing under it, so its bottom corners should round like its top
    -- ones -- and the same shape, re-sided, is cheaper and more honest than
    -- a second set of textures shown and hidden in turn.
    local function setSides(newSides)
        newSides = tostring(newSides or "")
        square.TOPLEFT     = newSides:find("T") or newSides:find("L")
        square.TOPRIGHT    = newSides:find("T") or newSides:find("R")
        square.BOTTOMLEFT  = newSides:find("B") or newSides:find("L")
        square.BOTTOMRIGHT = newSides:find("B") or newSides:find("R")
        place()
        paint()
    end

    setRadius(radius)
    shapeReg[paint] = place
    return paint, setRadius, setInset, setSides, setInsetBottom, setGradient, setFace
end

-- ── A button's relief ──────────────────────────────────────────
--
-- The overlay every button in the panel wears above its fill: Media/
-- buttonface.tga -- a bright bevel and gloss along the top, a shadow and
-- dark bevel along the bottom, the rounded shape in its alpha -- drawn
-- through the same seven-piece geometry as the fill under it, inset by
-- the control stroke so it sits inside the border. A flat rounded well
-- did not read as something to press; this is what makes it, on a plain
-- button, a green Add, a red Remove and the rail's own cells alike,
-- because the art only lightens and darkens whatever color is beneath.
--
-- Returns a ShapeTexture shim: SetVertexColor(1, 1, 1, strength) is how
-- it is painted, with `strength` the skin's buttonSheen (1 = the art as
-- authored, 0 = flat). `group` is the stroke group the inset follows
-- ("control" for everything so far).
function ns.ButtonFace(frame, layer, radius, group)
    local paint, _, _, setSides, _, _, setFace =
        ns.StrokedFill(frame, layer or "ARTWORK", radius or 8, nil,
                       { 1, 1, 1, 0 }, group or "control")
    setFace(MEDIA .. "buttonface.tga")
    return ns.ShapeTexture(paint, setSides)
end

-- The strength a face is painted at: the skin's buttonSheen, 1 when the
-- skin predates the token. `a` is the control's disabled alpha.
function ns.FaceAlpha(skin, a)
    local sheen = skin and skin.buttonSheen
    if sheen == nil then sheen = 1 end
    return sheen * (a or 1)
end

-- Dim a color by BLENDING it toward the surface behind it, keeping full
-- opacity, rather than by dropping alpha.
--
-- Alpha is the wrong tool wherever two drawn parts overlap: on a disabled
-- slider a translucent thumb let the end of the translucent fill show
-- straight through the circle. Blending leaves both opaque, so they still
-- hide each other while reading as inactive.
function ns.Faded(c, backdrop, off, mul)
    mul = mul or 1
    if not off then return c[1] * mul, c[2] * mul, c[3] * mul, c[4] or 1 end
    local k = 0.62   -- how far toward the backdrop a disabled surface goes
    return c[1] * mul * (1 - k) + backdrop[1] * k,
           c[2] * mul * (1 - k) + backdrop[2] * k,
           c[3] * mul * (1 - k) + backdrop[3] * k,
           1
end

-- A horizontal pill, for slider tracks.
--
-- It needs its own art and its own slice. A full pill has a corner radius
-- of half its height, and nine-slicing such a shape from a rounded RECT is
-- impossible: the top and bottom margins would consume the entire height
-- and leave nothing to stretch, so the caps get squashed and the bar comes
-- out with the odd flattened-then-rounded ends it had. bar.tga is authored
-- as a pill and sliced HORIZONTALLY ONLY -- margins (4, 0, 4, 0) -- so the
-- caps are drawn 1:1 and only the straight middle stretches.
function ns.BarTex(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(MEDIA .. "bar.tga")
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(4, 0, 4, 0)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    return t
end

-- ── Scrollbar ──────────────────────────────────────────────────
--
-- Ours, for the same reason the dropdown is: it has to match, and it has
-- to work on a plain ScrollFrame.
--
-- It lives in a gutter that is ALWAYS reserved, whether or not the bar is
-- currently needed. Reserving it costs 10px and removes a whole class of
-- bug: if the content width changed when the bar appeared, then appearing
-- could make the content tall enough to need the bar, or short enough not
-- to, and the layout would oscillate.
--
-- `sc` is the ScrollFrame; it must carry `contentHeight`. Returns the bar,
-- which exposes Update().
-- Wide enough to be an easy target, and wide enough for its corners.
--
-- The thumb is the rounded RECT the text boxes use, not the pill the slider
-- track uses. A pill is all cap and no middle, so at scrollbar widths it was
-- being scaled rather than drawn 1:1 and came out soft. Radius 4 rather than
-- the usual 8: nine-slicing spends `radius` on each side, so a 12px-wide
-- thumb at radius 8 would have no middle band left horizontally -- the same
-- squashing that made the old switch look flat-sided.
ns.SCROLLBAR_W  = 14
-- The bar hangs 2px clear of the scroll frame's right edge, so the space a
-- page must reserve for it is that gap PLUS its width. Exported because
-- getting this wrong is invisible until the bar hangs over the panel's
-- border by exactly the gap.
ns.SCROLLBAR_GUTTER = ns.SCROLLBAR_W + 2
local SB_RADIUS = 4
local SB_INSET  = 2   -- border stroke plus a hairline

function ns.AttachScrollBar(sc, skinFn)
    local SB_W = ns.SCROLLBAR_W
    local host = sc:GetParent()
    local sb = CreateFrame("Frame", nil, host)
    sb:SetWidth(SB_W)
    -- ANCHORED TO THE HOST'S RIGHT EDGE, not to the scroll frame's.
    --
    -- It used to hang two pixels outside the scroll frame, which put it
    -- inside the panel only while the scroll frame was inset by the
    -- gutter. A host that gives that gutter back when nothing overflows --
    -- the page body does, so the cards get the room -- then had a bar
    -- hanging off its own right edge whenever the two decisions disagreed,
    -- which on a page whose height tracks the viewport is every few pixels
    -- of a resize. Anchored to the host it cannot leave the host, whatever
    -- the gutter is doing; for a host that always reserves one (the tree
    -- pane) this is the same place it already sat.
    --
    -- Vertically it still follows the SCROLL FRAME: the bar spans what is
    -- scrolling, not what is around it -- so the x comes from the host and
    -- the y is measured against the scroll frame in Update, where both
    -- frames have been laid out and their tops can actually be compared.
    sb:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    sb:SetHeight(1)
    sb:Hide()

    -- The track wears the panel's one border treatment, like every other
    -- surface. SB_INSET is the room that leaves for the thumb: the 1px
    -- stroke plus a hairline, so the thumb never sits on the border.
    sb.trackBorder, sb.trackTex = ns.BorderedRound(sb, SB_RADIUS, "BACKGROUND", "BORDER")

    local thumb = CreateFrame("Button", nil, sb)
    thumb:SetPoint("LEFT",  sb, "LEFT",   SB_INSET, 0)
    thumb:SetPoint("RIGHT", sb, "RIGHT", -SB_INSET, 0)
    thumb.tex = ns.RoundTex(thumb, "ARTWORK", SB_RADIUS)
    thumb.tex:SetAllPoints(thumb)
    sb.thumb = thumb

    local function paint()
        local skin = skinFn()
        sb.trackBorder:SetVertexColor(C(skin.controlBorder, 1, 1))
        sb.trackTex:SetVertexColor(C(skin.controlBg, 1, 1))
        local hot = thumb.dragging or thumb.hovered
        -- Opaque, not translucent: the track sits directly behind the thumb
        -- and would otherwise show through it.
        local c = hot and skin.accent or skin.textMuted
        thumb.tex:SetVertexColor(c[1], c[2], c[3], 1)
    end

    -- Position the thumb from the scroll offset, and hide the whole bar
    -- when everything fits.
    function sb:Update()
        local view    = sc:GetHeight()
        local content = sc.contentHeight or 0
        local over    = content - view
        if over <= 1 or view <= 0 then self:Hide(); return end
        -- The host, ASKED FOR each time rather than captured: an in-page
        -- tree's scroll frame is re-parented as it moves between pooled
        -- cards (see ns.nav's RenderTree), and a bar anchored to the frame
        -- that used to hold it is a bar drawn somewhere else entirely.
        local h = sc:GetParent()
        if h and self:GetParent() ~= h then self:SetParent(h) end
        h = h or host
        -- Level with what it scrolls. The host's top and the scroll
        -- frame's differ by whatever inset the host gave it (6px under a
        -- page header, none in a tree pane), and that is only knowable
        -- once both are laid out -- which is here.
        local drop = 0
        local ht, st = h:GetTop(), sc:GetTop()
        if ht and st then drop = math.max(0, ht - st) end
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -drop)
        -- The TRACK can be shorter than the view. A scroll frame whose
        -- bottom edge is the panel's own has the resize grip sitting in
        -- its corner, and a bar drawn to the very bottom is drawn under
        -- the grip. `barClearBottom` on the scroll frame is how much to
        -- stop short; the thumb's proportions still come from the view,
        -- since that is what is being scrolled.
        local track = math.max(1, view - (sc.barClearBottom or 0))
        self:SetHeight(track)
        self:Show()
        local th  = math.max(24, (track - SB_INSET * 2) * (view / content))
        local pos = SB_INSET + (sc:GetVerticalScroll() / over)
                             * math.max(0, track - th - SB_INSET * 2)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT",  self, "LEFT",   SB_INSET, 0)
        thumb:SetPoint("RIGHT", self, "RIGHT", -SB_INSET, 0)
        thumb:SetPoint("TOP",   self, "TOP",    0, -pos)
        paint()
    end

    -- Dragging. OnUpdate is registered only while the mouse is down, so an
    -- idle panel runs no per-frame code at all.
    local function onDrag(self)
        local view    = sc:GetHeight()
        local content = sc.contentHeight or 0
        local over    = content - view
        if over <= 0 then return end
        local track = math.max(1, view - (sc.barClearBottom or 0))
        local th    = math.max(24, (track - SB_INSET * 2) * (view / content))
        local range = track - th - SB_INSET * 2
        if range <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / (sb:GetEffectiveScale() or 1)
        local moved = (self.grabY - cy)
        sc:SetVerticalScroll(math.floor(math.max(0, math.min(over,
            self.grabScroll + (moved / range) * over)) + 0.5))
    end

    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.grabY      = cy / (sb:GetEffectiveScale() or 1)
        self.grabScroll = sc:GetVerticalScroll()
        self.dragging   = true
        self:SetScript("OnUpdate", onDrag)
        paint()
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        paint()
    end)
    thumb:SetScript("OnEnter", function(self) self.hovered = true;  paint() end)
    thumb:SetScript("OnLeave", function(self) self.hovered = false; paint() end)

    -- Clicking the track pages by a viewport at a time.
    sb:EnableMouse(true)
    sb:SetScript("OnMouseDown", function()
        local view    = sc:GetHeight()
        local over    = (sc.contentHeight or 0) - view
        if over <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / (sb:GetEffectiveScale() or 1)

        -- A click BESIDE the thumb is not a click on the track.
        --
        -- The thumb is inset on both sides so it never paints over the
        -- track's border, which leaves a sliver of track down each edge at
        -- the thumb's own height. A click there reached this handler, and
        -- the test below -- "is the cursor under the thumb?" -- answers no
        -- for a point level with it, so it paged UP. Clicking down the side
        -- of the bar walked the panel to the top, which is what got
        -- reported. Paging only means anything above or below the thumb.
        local top, bottom = thumb:GetTop(), thumb:GetBottom()
        if top and bottom and cy <= top and cy >= bottom then return end

        local dir = (cy < (bottom or 0)) and 1 or -1
        sc:SetVerticalScroll(math.floor(math.max(0, math.min(over,
            sc:GetVerticalScroll() + dir * view * 0.9)) + 0.5))
    end)

    sc:HookScript("OnVerticalScroll", function() sb:Update() end)
    sc:HookScript("OnSizeChanged",    function() sb:Update() end)

    sc.scrollbar = sb
    return sb
end

-- ── Hover ──────────────────────────────────────────────────────
--
-- One contract for every control: the border lifts toward the accent on
-- mouseover and further again while the control is "active" (focused, or
-- with its menu open). Each control tells the helper which texture is its
-- border and what that border's resting color is; nothing else differs,
-- so a control cannot silently end up with no hover state -- which is what
-- had happened to the switch, the segmented picker and the swatch.
--
-- Call SetBorder(w, tex) once at create, MarkBorder(w, skin, color, a) on
-- every refresh, and InstallHover(w) in apply -- apply, not create, because
-- releasing a widget to the pool scrubs its OnEnter/OnLeave scripts.

function ns.SetBorder(w, tex) w.bpBorder = tex end

function ns.MarkBorder(w, skin, color, alpha)
    w.bpSkin, w.bpBorderColor, w.bpAlpha = skin, color, alpha or 1
    ns.PaintBorder(w, w.bpActive and "active" or (w.bpHovered and "hover") or nil)
end

function ns.PaintBorder(w, state)
    local skin = w and w.bpSkin
    if not (skin and w.bpBorder) then return end
    local a = w.bpAlpha or 1
    if state == "active" then
        w.bpBorder:SetVertexColor(C(skin.accent, 1, 0.90 * a))
    elseif state == "hover" then
        w.bpBorder:SetVertexColor(C(skin.accent, 1, 0.55 * a))
    else
        local c = w.bpBorderColor or skin.controlBorder
        w.bpBorder:SetVertexColor(C(c, 1, (c[4] or 1) * a))
    end
end

-- `target` is the mouse-enabled frame, which is usually the widget itself
-- but is the pill for a switch and each segment for a segmented picker.
function ns.InstallHover(target, w, node, ctx)
    -- A pooled widget can come back still believing it is hovered.
    w.bpHovered, w.bpActive = false, false
    target:SetScript("OnEnter", function()
        if ns.IsDisabled(node, ctx) then return end
        w.bpHovered = true
        if not w.bpActive then ns.PaintBorder(w, "hover") end
        if w.bpOnHover then w.bpOnHover(w, true) end
    end)
    target:SetScript("OnLeave", function()
        w.bpHovered = false
        if not w.bpActive then ns.PaintBorder(w, nil) end
        if w.bpOnHover then w.bpOnHover(w, false) end
    end)
end

-- ── Text fields: the caret and the double click ────────────────
--
-- An EditBox has no OnDoubleClick. That script belongs to Button, so
-- `if box:HasScript("OnDoubleClick")` was false on BOTH text fields and
-- quietly installed nothing -- a guard that reads as caution and behaves as
-- deletion. Double click selecting nothing was never a broken handler; it
-- was no handler at all. Two presses inside the client's own double-click
-- window are what a double click IS, so time them here instead.
--
-- OnMouseDown, not OnMouseUp: OnMouseUp is where Context.lua hooks the
-- right-click menu, and a script here must not sit in front of that. Nor
-- does it sit in front of the caret: the click handling that places the
-- cursor is the client's own, C-side, and a Lua script on the same frame
-- adds to it rather than replacing it -- exactly as the slider's own
-- OnMouseDown does not stop the thumb from dragging.
local function DoubleClickWindow()
    -- pcall'd: an unknown CVar name is an error on some clients, and a
    -- text field must not depend on this one existing at all.
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, raw = pcall(get, "doubleClickTime")
    local v = ok and tonumber(raw) or nil
    -- 0.4 is the client's own default, used when the CVar cannot be read.
    return (v and v > 0) and v or 0.4
end

function ns.InstallTextFieldMouse(box)
    box.bpDblDown = box.bpDblDown or function(self, button)
        if button ~= "LeftButton" then return end
        local now, last = GetTime(), self.bpLastDown or 0
        self.bpLastDown = now
        if now - last > DoubleClickWindow() then
            -- A single click after a selection drops it and leaves the
            -- caret where you clicked, which is what clicking into
            -- selected text does anywhere else.
            self:HighlightText(0, 0)
        end
        if now - last <= DoubleClickWindow() then
            -- A third click is not a second double click.
            self.bpLastDown = 0
            -- Next frame, not now. The release that follows this press is
            -- the end of the client's own click-drag selection, and it
            -- settles the highlight on whatever that drag covered -- which
            -- for a stationary double click is nothing. Selecting from
            -- inside the press would be selecting before that runs.
            if C_Timer then
                C_Timer.After(0, function() if self:HasFocus() then self:HighlightText() end end)
            else
                self:HighlightText()
            end
        end
    end
    -- SetScript rather than HookScript, and from apply() rather than
    -- create(): apply runs on every render and hooks accumulate, while the
    -- pool scrubs OnMouseDown on release -- so a handler installed once at
    -- creation is gone the second time the widget is used.
    box:SetScript("OnMouseDown", box.bpDblDown)
end

-- Resolve a node's value through either an explicit get/set pair or a
-- `bind` path into the page's db root. Binding covers the common case in
-- one string; get/set stays available for anything computed.
-- Walk a dotted path into a table and return the container plus the final
-- key, so the caller can read or write it. Exported because defaults live
-- in a table of the same shape as the db and are looked up the same way.
function ns.ResolvePath(root, path)
    local t = root
    if type(t) ~= "table" or not path then return nil end
    local last
    for seg in path:gmatch("[^%.]+") do
        if last then t = t[last]; if type(t) ~= "table" then return nil end end
        last = seg
    end
    return t, last
end

local function Resolve(ctx, path)
    return ns.ResolvePath(ctx.db, path)
end

function ns.GetValue(node, ctx)
    if node.get then
        local v = node.get(node, ctx)
        -- A getter that finds nothing stored answers nil, and nil is not a
        -- value a control can show -- the `bind` path below has always
        -- fallen back to the default for exactly this, and a computed
        -- getter has the same gap. It mattered most for UNDO: a setting
        -- never written recorded nil as its undo point, so undoing it wrote
        -- nil back and looked like nothing had happened.
        if v == nil then return node.default end
        return v
    end
    if node.bind then
        local t, k = Resolve(ctx, node.bind)
        if t and k then return t[k] end
    end
    return node.default
end

-- How long a run of writes counts as ONE change for undo purposes.
--
-- Dragging a slider writes on every step. Recording each one would make
-- "undo" mean "go back one pixel", which is useless: what the reader wants
-- back is the value before they touched it. Writes to the same setting
-- inside this window therefore keep the FIRST previous value.
local UNDO_COALESCE = 0.75

-- Write without recording an undo point. For restores and corrections --
-- anything that is putting a value BACK rather than changing it.
function ns.SetValueQuiet(node, ctx, v)
    if node.set then node.set(node, ctx, v); return end
    if node.bind then
        local t, k = Resolve(ctx, node.bind)
        if t and k then t[k] = v end
    end
end

-- Record what a setting was, WITHOUT changing it. One level, per setting,
-- per session -- enough for "undo that", which is all the right-click menu
-- offers.
--
-- Split out of SetValue because a write is not the only thing that should be
-- undoable. A button that acts on a setting through the consuming addon's
-- own writer -- "center this axis" -- never passes through SetValue, so
-- nothing was recorded and the menu, which opens only when it has an entry
-- to show, did not open at all. Such a caller records the point itself and
-- then writes however it likes.
--
-- The coalescing window is what keeps a drag from filling the slot with the
-- value from one notch ago: inside it the existing record stands and only
-- its timestamp moves.
function ns.RecordUndo(node, ctx)
    local app = ctx and ctx.app
    local key = node and (node.bind or node.id)
    if not (app and key) then return end
    app.undo = app.undo or {}
    local now  = GetTime and GetTime() or 0
    local prev = app.undo[key]
    if not prev or (now - (prev.at or 0)) > UNDO_COALESCE then
        app.undo[key] = { value = ns.GetValue(node, ctx), at = now }
    else
        prev.at = now
    end
end

-- THE ONE FUNNEL EVERY WRITE GOES THROUGH -- the controls' own commits, a
-- composite writing three binds for one gesture, the right-click menu's undo
-- and reset. Which is why the re-render is scheduled here rather than in
-- ns.Commit: every one of those can change the page's SHAPE, and only this
-- line is on all of their paths.
--
-- ns.SetValueQuiet deliberately is NOT: it puts a value BACK -- a slider
-- correcting itself against its own step, a field being reseeded -- and a
-- correction that scheduled a render could be re-entered by the render it
-- asked for.
function ns.SetValue(node, ctx, v)
    ns.RecordUndo(node, ctx)

    if node.set then
        node.set(node, ctx, v)
    elseif node.bind then
        local t, k = Resolve(ctx, node.bind)
        if t and k then t[k] = v end
    end

    -- The host this field was drawn in, which the render stamped on the ctx
    -- (see ns.page.ScheduleRender). A ctx with none -- a caller that built
    -- its own -- schedules every host that asks a question, which
    -- over-renders and never under-renders.
    local app = ctx and ctx.app
    if app and ns.page and ns.page.ScheduleRender then
        ns.page.ScheduleRender(app, ctx.bpScope)
    end
end

-- The single path a control takes when the reader changes something.
--
-- Every control used to open-code this: SetValue, then RefreshBinding, then
-- onChange. Eleven copies of three lines, which meant the side effect was
-- always immediate because there was nowhere for a policy to live. Now there
-- is one place, and the three steps are explicitly on different schedules:
--
--   the WRITE      immediate, always. The profile is never behind the UI.
--   the REPAINT    immediate, always. One index lookup and a :refresh().
--   the SIDE EFFECT scheduled by the node's `refresh` tier -- see Effects.lua.
--
-- A node opts in with:
--
--   refresh    = "write" | "debounce" | "mouseup"
--                (default: the control's own defaultTier -- "debounce" on
--                 slider and color, inline everywhere else)
--   refreshKey = "containers"   -- what this effect COALESCES with.
--                                  Defaults to the bind path, which keeps
--                                  independent settings independent.
--   refreshId  = "walk"         -- which effect this is within the key.
--   rank       = 2              -- higher supersedes lower on the same key.
--   delay      = 0.2            -- override the tier's default wait.
--
-- Nothing has to declare any of it. Where a node says nothing, the CONTROL's
-- own `defaultTier` decides, and where the control says nothing either, the
-- effect runs inline.
--
-- The default is per control KIND because the tiers answer a question only
-- some controls raise. A slider or a color wheel fires its setter on every
-- tick of a drag, so there is a stream to coalesce and debouncing it is most
-- of the point. A switch, a dropdown pick or a button fires exactly once per
-- click: there is nothing to coalesce, and a tier there would only put 150ms
-- between the click and the addon reacting to it, for no gain.

-- Schedule a node's side effect, without writing anything.
--
-- Split out from Commit because two callers legitimately write SEVERAL
-- settings and then want ONE effect: a composite that owns three binds, and
-- the undo / reset menu that restores a whole group. Firing per write would
-- run the addon's callback three times for one gesture.
function ns.FireEffect(node, ctx)
    if not node.onChange then return end
    local app = ctx and ctx.app
    local function fire() node.onChange(node, ctx) end

    if not (app and ns.effects) then fire(); return end

    -- The control kind supplies the default tier. Looked up the same way
    -- Page.LayoutGroup resolves a control, so an app's OWN registered
    -- control can declare one too.
    local def = node.control and ((app.controls and app.controls[node.control])
                                  or ns.builtinControls[node.control])
    ns.effects.Schedule(app, {
        tier  = node.refresh or (def and def.defaultTier),
        -- Falling back to the NODE TABLE itself as a last resort. A field
        -- with no refreshKey, no bind and no id -- a composite declared
        -- inline, say -- would otherwise share one anonymous bucket with
        -- every other such field on the page, and they would supersede each
        -- other's effects at random. The table is a perfectly good key and
        -- is unique per declared field by construction.
        key   = node.refreshKey or node.bind or node.id or node,
        id    = node.refreshId,
        rank  = node.rank,
        delay = node.delay,
    }, fire)
end

function ns.Commit(node, ctx, v)
    ns.SetValue(node, ctx, v)
    local app = ctx and ctx.app
    if app then app:RefreshBinding(node.bind or node.id) end
    ns.FireEffect(node, ctx)
    -- The app's own hook, after the field's effect is scheduled: "a setting
    -- on this panel changed". A consuming addon uses it for the work that
    -- belongs to the PANEL rather than to any one field -- a preview sweep,
    -- a dirty flag -- without every field having to remember to ask for it.
    -- Whatever it costs, it should be scheduled: this runs on every step of
    -- a slider drag.
    if app and app.onWrite then app.onWrite(app, node, ctx) end
end

-- The default for a setting: an explicit `default` on the node, otherwise
-- the same path looked up in the page's `defaults` table. A page that
-- declares no defaults simply has no Reset entry.
function ns.DefaultFor(node, ctx, bindPath)
    local path = bindPath or node.bind
    if not bindPath and node.default ~= nil then return node.default, true end

    local d = ctx and ctx.page and ctx.page.defaults
    if type(d) == "function" then d = d() end
    if type(d) ~= "table" or not path then return nil, false end

    local t, k = ns.ResolvePath(d, path)
    if t and k and t[k] ~= nil then return t[k], true end
    return nil, false
end

-- COMBAT, FOR THE WHOLE APP.
--
-- `disabled = "combat"` is per node, and an addon whose settings ALL refuse
-- in combat then has to remember it on every one of them -- which is a rule
-- kept by hand, so it is a rule with holes: the field somebody added last
-- week looks live in combat and silently does nothing.
--
-- `app:SetCombatDisablesAll(true)` states it once. Every node is then
-- disabled while the player is in combat, whatever it declares, and a node
-- that genuinely works in combat opts out with `combat = false` -- the same
-- word a collection's add/remove already uses for the same escape.
local function CombatLocked(node, ctx)
    local app = ctx and ctx.app
    if not (app and app.combatDisablesAll) then return false end
    if node and node.combat == false then return false end
    return InCombatLockdown()
end

-- A DIMMED CARD, FOR EVERY FIELD IN IT AT ONCE.
--
-- A gated card normally collapses when its switch is off, and that is
-- still the right answer nearly everywhere. `toggle.dims` is the card that
-- must stay readable while it is off -- one whose body EXPLAINS what the
-- switch turns on, where collapsing takes the explanation away with it.
--
-- Dimming the body alone would be a lie: half-lit controls that still take
-- a click and still write. So the card's fields report disabled too, and
-- they report it from HERE rather than each declaring a predicate of its
-- own -- every control in the library asks this one function, so one rule
-- reaches all of them, and a field added to such a card later inherits it
-- without anybody remembering to.
--
-- The set is keyed by the field table and rebuilt by LayoutGroup on every
-- render, but it is NOT torn down with the pass the way app.bpHiddenNow
-- is: a control asks this again when it is CLICKED, which happens between
-- renders. A per-pass set would answer "not dimmed" at exactly that
-- moment, and the card would be grayed and still writing. Nothing is
-- stamped onto the declaration, so a field shared between a dimmed card
-- and a live one is disabled only where it is dimmed -- as of the last
-- render, which is also the last time either card could have changed.
local function GateDimmed(node, ctx)
    local app = ctx and ctx.app
    local memo = app and app.bpDimmed
    return (memo and node and memo[node]) and true or false
end

function ns.IsDisabled(node, ctx)
    if GateDimmed(node, ctx) then return true end
    local d = node.disabled
    if d == "combat" then return InCombatLockdown() end
    if type(d) == "function" then
        if d(node, ctx) then return true end
        return CombatLocked(node, ctx)
    end
    if d then return true end
    return CombatLocked(node, ctx)
end

-- Hidden is not disabled: a disabled field is still THERE, grayed, and
-- still tells the reader the setting exists. A hidden one takes no space
-- at all, which is right only where the setting is meaningless -- "Show in
-- Combat" under a tooltip that is switched off. The page layout skips
-- these entirely, and a field whose `hidden` is a FUNCTION makes its host
-- re-render on the next write, so flipping the thing it depends on re-lays
-- the page out.
-- ONE ANSWER PER RENDER.
--
-- A predicate is asked from two places -- ns.page's GroupShown, deciding
-- whether the card draws at all, and LayoutGroup, deciding whether the
-- field inside it does -- and it was asked independently at each. A
-- predicate that reads addon state can answer differently between the two,
-- and the page is then drawn on one answer and laid out on the other: a
-- card that draws because a field is visible, holding a field that was
-- measured out of existence. That is a control disappearing from a card
-- that stays on screen, and no error to say so.
--
-- So a render opens a memo (app.bpHiddenNow) and every ask inside it goes
-- through the memo: the declaration is sampled ONCE and the whole pass --
-- the draw decision and the layout -- agrees with itself. Outside a render
-- there is no memo and NOTHING is remembered at all: the answer lives
-- exactly as long as the render that asked for it, which is what stops a
-- sample taken mid-rebuild from outliving the frame it was wrong in.
function ns.IsHidden(node, ctx)
    local memo = ctx and ctx.app and ctx.app.bpHiddenNow
    if memo then
        local v = memo[node]
        if v ~= nil then return v end
    end
    local h = node.hidden
    local v
    if type(h) == "function" then v = h(node, ctx) and true or false
    else v = h and true or false end
    if memo then memo[node] = v end
    return v
end

-- ── Label ──────────────────────────────────────────────────────
-- Every control that carries a label shares this, so label placement is
-- one decision made in one place (group preset: "above" or "left").

local function AttachLabel(w, parent)
    w.label = ns.FS(parent, "OVERLAY", "GameFontNormalSmall")
    w.label:SetJustifyH("LEFT")
    w.label:SetWordWrap(false)
    return w.label
end

-- ── switch (pill toggle) ───────────────────────────────────────

local switch = {}
-- The switch's size, which is also the size its art is authored at: see
-- Tools/BuzzardPanel/make_pill.py before changing either number.
local SW_W, SW_H = 28, 15
ns.SWITCH_W, ns.SWITCH_H = SW_W, SW_H

-- The pill on its own: a track, a ring and a knob, at the size the switch
-- control wears. Factored out because the MENU shows toggles too, and a
-- toggle that is nearly the addon's switch is worse than no switch at all.
-- The track is its own frame purely so it can carry the shared border.
-- The pill is FIXED ART, not a sliced rounded rect.
--
-- A switch is only ever SW_W x SW_H, so slicing bought nothing and cost the
-- shape: a full capsule's corner radius is half its height, which cannot be
-- nine-sliced from a rounded rect at all -- the top and bottom margins
-- consume the whole height and leave nothing to stretch. That is why the
-- switch read as a rounded rectangle rather than the capsule it should be.
--
-- pill.tga and pillring.tga are drawn by Tools/BuzzardPanel/make_pill.py at
-- 2x the display size inside a 128x64 canvas, so the art is downscaled
-- rather than magnified and its distance-field edge stays clean above UI
-- scale 1. The crop below is that canvas.
local PILL_U, PILL_V = (SW_W * 2) / 128, (SW_H * 2) / 64

function ns.SwitchPill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(SW_W, SW_H)
    p.track = p:CreateTexture(nil, "BACKGROUND")
    p.track:SetTexture(MEDIA .. "pill.tga")
    p.track:SetTexCoord(0, PILL_U, 0, PILL_V)
    p.track:SetAllPoints(p)
    -- The ring sits ON the fill's edge rather than around it, so there is
    -- no hairline of track color outside the border at any scale.
    p.ring = p:CreateTexture(nil, "ARTWORK")
    p.ring:SetTexture(MEDIA .. "pillring.tga")
    p.ring:SetTexCoord(0, PILL_U, 0, PILL_V)
    p.ring:SetAllPoints(p)
    -- A circle, as the mockup has it -- not a small rounded square.
    p.knob = p:CreateTexture(nil, "ARTWORK")
    p.knob:SetTexture(MEDIA .. "circle.tga")
    p.knob:SetSize(SW_H - 5, SW_H - 5)
    return p
end

-- Paint a pill for a state and RETURN the color its border wants, so the
-- caller marks that border however it marks borders -- the control through
-- ns.MarkBorder, which also carries hover; the menu directly, which has no
-- hover state of its own to keep.
--
-- The knob sits ON the track, so both dim by blending rather than by alpha;
-- otherwise the track shows through a disabled knob.
function ns.PaintSwitchPill(p, skin, on, off)
    p.knob:ClearAllPoints()
    if on then
        p.track:SetVertexColor(ns.Faded(skin.accent, skin.panelBg, off, 0.42))
        p.knob:SetVertexColor(ns.Faded(skin.accent, skin.panelBg, off, 1.25))
        p.knob:SetPoint("RIGHT", p, "RIGHT", -2.5, 0)
        -- The "on" border is the accent already, so hover lifts from there.
        return { skin.accent[1], skin.accent[2], skin.accent[3], 0.7 }
    end
    p.track:SetVertexColor(ns.Faded(skin.controlBg, skin.panelBg, off))
    p.knob:SetVertexColor(ns.Faded(skin.textMuted, skin.panelBg, off))
    p.knob:SetPoint("LEFT", p, "LEFT", 2.5, 0)
    return skin.controlBorder
end

function switch.create(app, parent)
    local w = CreateFrame("Button", nil, parent)
    w:SetSize(SW_W, ROW_H)

    w.pill = ns.SwitchPill(w)
    w.pill:SetPoint("LEFT", w, "LEFT", 0, 0)
    w.ring, w.track, w.knob = w.pill.ring, w.pill.track, w.pill.knob
    ns.SetBorder(w, w.ring)
    return w
end

-- The switch is the one control whose VISUAL is narrower than its frame:
-- the layout gives it a field's worth of width, and the pill uses 36 of it.
-- The hit rect is trimmed to the pill so the clickable area is exactly what
-- you can see -- clicking the empty space beside a switch used to toggle it,
-- which is indistinguishable from a misaligned control.
local function LockSwitchHitRect(w)
    local extra = math.max(0, (w:GetWidth() or SW_W) - SW_W)
    w:SetHitRectInsets(0, extra, 0, 0)
end

function switch.apply(w, node, ctx)
    ns.InstallHover(w, w, node, ctx)
    LockSwitchHitRect(w)
    w:SetScript("OnSizeChanged", LockSwitchHitRect)
    w:SetScript("OnClick", function()
        if ns.IsDisabled(node, ctx) then return end
        ns.Commit(node, ctx, not ns.GetValue(node, ctx))
    end)
end

function switch.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local on   = ns.GetValue(node, ctx) and true or false
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1

    ns.MarkBorder(w, skin, ns.PaintSwitchPill(w.pill, skin, on, off), a)
    w:SetEnabled(not off)
end

-- The PILL, and nothing else.
--
-- This used to claim 110 preferred and 90 minimum for a control that is 36
-- pixels wide, which is a third label allowance stacked on two that already
-- work: FieldMetrics widens a field to its label either way -- max(width,
-- labelW) with the label above, width + labelW + 8 with it beside. So the
-- extra was pure padding, and it showed as a row of switches spread across
-- a line with large empty gaps between them.
--
-- Spacing between fields belongs to the group preset's gapX, not baked into
-- a control's own measurement. A switch that wants more room asks for it:
-- `width = 180` on the field, which now means something, because the
-- default no longer over-reserves.
function switch.measure() return SW_W, SW_W, ROW_H end
switch.stretch = false

-- ── slider ─────────────────────────────────────────────────────
-- A native Slider frame (real WoW input handling: drag, click, wheel)
-- wearing our own art, plus an editable value box and a min/max footer.

local slider = {}
local BAR_H = 6           -- bar.tga is authored 8px tall; 6 reads slimmer

-- Two heights. The full one carries the min/max footer; the compact one
-- does not, and is exported so a composite can stack sliders against a
-- neighbor of a known height without guessing.
-- The compact height is the compact BOX plus a hair of separation, and
-- nothing else: with no footer under it and the bar centered on it, the box
-- is the only thing in the row that has a height. Derived rather than
-- written down, so shortening the box shortens the row -- and, two rows up,
-- the anchor pad built out of it.
local SLIDER_H_FULL = ROW_H + 12
local SLIDER_H_COMPACT

-- ── Where the value box goes ───────────────────────────────────
--
-- "side"  -- the box sits in a gap reserved at the right of the track.
-- "below" -- the track takes the full width and the box centers under it,
--            level with the min/max labels. The classic arrangement, and
--            what a reader coming from other panels expects.
--
-- Resolved nearest-first, the same three tiers `railChildren` uses:
--
--   node.valuePlacement          this field, outright
--   app:SetSliderValuePlacement  the panel's default
--   (neither)                    "side"
--
-- It is read in MEASURE as well as in apply, because the two layouts are
-- not the same height and a row measured for one and drawn as the other
-- either clips the box or leaves a gap under it.
local BOX_W, BOX_H = 46, 19
local BOX_GAP      = 6      -- room reserved beside the track in "side"

-- Published because a composite that forces a SIDE box has to add them back:
-- the box is drawn inside the widget's own width, so a widget of
-- ns.CONTROL_W has a track of ns.CONTROL_W minus these two.
ns.SLIDER_BOX_W   = BOX_W
ns.SLIDER_BOX_GAP = BOX_GAP

-- COMPACT sliders get a shorter box. A compact slider is a PART of
-- something -- the two offsets inside a position widget -- and there the
-- box is the tallest thing in the row, so it is what the row's height
-- actually costs. Two of them stacked is the whole height of an anchor
-- pad, and the pad is the whole height of the composite; two pixels here
-- are four there, twice over.
--
-- 17 is the floor for the font the box uses. Below that the digits start
-- meeting the border.
local BOX_H_COMPACT = 17

-- The slider bar's own frame, which the compact layout centers on the box
-- rather than hanging at a fixed inset -- 14 and 17 are close enough that
-- anything else reads as crooked.
local BAR_FRAME_H = 14

-- 4px of separation under the box: enough that two stacked compact sliders
-- read as two rows, and not a pixel more, because the anchor pad is two of
-- these and nothing else.
SLIDER_H_COMPACT = BOX_H_COMPACT + 4
ns.SLIDER_H_COMPACT = SLIDER_H_COMPACT

-- A compact slider that still shows its range. One line of the small font
-- and the hair of separation it needs -- NOT the full layout's footer, which
-- is taller because that layout also carries a taller value box. A composite
-- asks for this with `range = true`: the numbers are worth the ten pixels
-- there, where the reader has no other clue what the track spans.
local RANGE_H = 10
-- Not SLIDER_H_COMPACT + RANGE_H. That constant carries a 4px tail so two
-- BARE compact sliders stack as two rows; with a footer under each, that
-- tail lands between one row's numbers and the next row's box, where it
-- reads as a gap rather than as separation. One pixel is enough there.
local SLIDER_H_COMPACT_RANGE = BOX_H_COMPACT + 1 + RANGE_H
ns.SLIDER_H_COMPACT_RANGE = SLIDER_H_COMPACT_RANGE

-- Does this slider draw its min/max? Every full one does; a compact one only
-- when the field asks.
local function ShowsRange(node)
    return (not node.compact) or (node.range and true or false)
end

-- The width a labeled control asks for when it has nothing better to say.
-- ONE number for every kind of control, which is the point of it: a page
-- of dropdowns and sliders reads as a column, and a row of them packs the
-- same way wherever it appears.
--
-- It started as the older options dialog's own number -- 170, its
-- `width_multiplier`, the width every option there gets when it declares
-- no `width` of its own -- so that a reader coming from that panel met
-- rows of the same shape. 150 is a deliberate step down from it: the
-- panel's controls carry their labels ABOVE rather than beside, so they
-- need less width for the same text, and a narrower default fits more of
-- a card on one line.
--
-- A field still overrules it with `width`, and the flow packer may squeeze
-- toward the minimum below it -- the one thing that layout could not do.
ns.CONTROL_W = 150

-- What `wide = true` MEANS for a switch.
--
-- `wide` gives a field the whole row, which is right for a note or a
-- segmented picker with six options -- and wrong for a switch, whose control
-- is 28 pixels. A switch is marked wide because its LABEL is long, and with
-- the label above it that bought a full row to hold one toggle and one line
-- of text, three of which is a card of mostly nothing.
--
-- So for a switch it means a control's width: enough for the caption to sit
-- above without being truncated, and narrow enough that several still share
-- a line. Declared here rather than special-cased in the layout, so any
-- other control that wants its own reading of `wide` says so the same way.
switch.wideWidth = ns.CONTROL_W

-- Below-mode heights: the box (19) replaces the min/max line (~12) on the
-- row under the track, so both variants grow by the difference.
local SLIDER_H_BELOW_FULL    = SLIDER_H_FULL + 5
local SLIDER_H_BELOW_COMPACT = SLIDER_H_COMPACT + BOX_H + 1

-- SetTextInsets, but only when the value ACTUALLY changes.
--
-- A post-creation SetTextInsets wipes the caret on a box whose width comes
-- from anchors, and box:GetTextInsets() does not return what was set
-- (rounding, or the frame's own scale) -- so a guard that asks the client
-- never fires and every refresh and keystroke rewrites the insets, taking
-- the caret with them. Remembering what we applied is the guard that works.
-- The text field learned this the hard way; the slider's value box, which
-- now has a unit to make room for, would have learned it again.
local function SetBoxInsets(box, left, right)
    if box.bpInsetL == left and box.bpInsetR == right then return end
    box.bpInsetL, box.bpInsetR = left, right
    -- Counted, so a caller can tell whether a pass moved them at all: the
    -- text field re-seeds its text after a change (see textinput.apply).
    box.bpInsetGen = (box.bpInsetGen or 0) + 1
    box:SetTextInsets(left, right, 0, 0)
end
ns.SetBoxInsets = SetBoxInsets

local function ValueBelow(node, ctx)
    local p = node and node.valuePlacement
    if p == nil and ctx and ctx.app then p = ctx.app.sliderValuePlacement end
    return p == "below"
end
ns.SliderValueBelow = ValueBelow
function slider.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetHeight(SLIDER_H_FULL)

    w.slider = CreateFrame("Slider", nil, w)
    w.slider:SetOrientation("HORIZONTAL")
    w.slider:SetHeight(BAR_FRAME_H)
    w.slider:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -4)

    w.track = ns.BarTex(w.slider, "BACKGROUND")
    w.track:SetHeight(BAR_H)
    w.track:SetPoint("LEFT",  w.slider, "LEFT",  0, 0)
    w.track:SetPoint("RIGHT", w.slider, "RIGHT", 0, 0)

    w.thumbTex = w.slider:CreateTexture(nil, "OVERLAY")
    w.thumbTex:SetTexture(MEDIA .. "circle.tga")
    w.thumbTex:SetSize(12, 12)
    w.slider:SetThumbTexture(w.thumbTex)

    -- The fill runs from the track's left edge to the CENTER of the thumb,
    -- by anchor rather than by arithmetic, so there is never a gap.
    w.fill = ns.BarTex(w.slider, "BORDER")
    w.fill:SetHeight(BAR_H)
    w.fill:SetPoint("LEFT",  w.track, "LEFT", 0, 0)
    w.fill:SetPoint("RIGHT", w.thumbTex, "CENTER", 0, 0)

    -- Value box. It needs a border and a hover state or it reads as a bare
    -- number floating in space: round8 tinted as the border, inset by 1px to
    -- leave a hairline, and the text CENTERED in the field.
    w.box = CreateFrame("EditBox", nil, w)
    w.box:SetSize(BOX_W, BOX_H)
    -- Anchored in apply, not here: the placement is a per-field setting and
    -- a pooled widget can be reused for a field that wants the other one.
    w.box:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -2)
    w.box:SetAutoFocus(false)
    ns.SetFontObject(w.box, GameFontHighlightSmall)
    w.box:SetJustifyH("CENTER")
    w.box:SetTextInsets(3, 3, 0, 0)

    w.boxBorder, w.boxBg = ns.BorderedRound(w.box, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(w.box, w.boxBorder)

    -- A fixed unit beside the value -- the familiar "50%" -- as a
    -- FontString rather than as text in the box, so it cannot be selected,
    -- deleted or re-typed and the box's contents stay a bare number for
    -- tonumber. Pinned to the box's right edge; apply reserves its width.
    w.boxSuffix = ns.FS(w.box, "OVERLAY", "GameFontDisableSmall")
    w.boxSuffix:SetPoint("RIGHT", w.box, "RIGHT", -4, 0)
    w.boxSuffix:Hide()

    -- Min and max sit on ONE line, both hung off the bottom of the slider so
    -- they are level with each other and clear of the track.
    w.minText = ns.FS(w, "OVERLAY", "GameFontDisableSmall")
    w.minText:SetPoint("TOPLEFT", w.slider, "BOTTOMLEFT", 0, -1)
    w.maxText = ns.FS(w, "OVERLAY", "GameFontDisableSmall")
    w.maxText:SetPoint("TOPRIGHT", w.slider, "BOTTOMRIGHT", 0, -1)

    -- ── Right-click must not move the thumb ──
    --
    -- A Slider is moved by the ENGINE, on any button, and the engine's value
    -- change fires OnValueChanged (byUser) before our own OnMouseDown script
    -- is guaranteed to have run. This used to be handled by capturing the
    -- value on the way down and writing it back on the way up, which is a
    -- race it can lose: if the engine got there first the capture read the
    -- ALREADY-CHANGED value and the "restore" faithfully restored it. That is
    -- the bug where right-clicking a slider changed its value.
    --
    -- The button cannot be refused. EnableMouseButton("RightButton", false)
    -- was tried here and a Slider still moved under a right-click on 12.1,
    -- so the input cannot be turned away -- it has to be UNDONE before it is
    -- ever drawn.
    --
    -- Which is what OnValueChanged does below: the thumb's on-screen position
    -- is derived from the value at DRAW time, and OnValueChanged runs
    -- synchronously inside the engine's click handling, before any render. So
    -- the correction is applied there, in the same call, rather than on the
    -- way up -- a mouse-up restore is a frame or more later, which is a
    -- visible twitch-and-snap. The setting is never written either way.
    --
    -- The container takes mouse so the field menu has a frame to open from
    -- across the whole control rather than only the track: Context.AttachField
    -- hooks frames that already take mouse input. Its children sit above it
    -- and consume their own clicks, so the track and the value box are
    -- unaffected.
    w:EnableMouse(true)

    -- ── Mouse handling ──
    --
    -- A left-press opens a drag and a left-release closes it. That is
    -- what makes the "mouseup" refresh tier exact rather than polled: the
    -- library knows precisely when the gesture ended, instead of watching
    -- a global mouse-button state on a timer.
    --
    -- The order on release matters. The final commit runs while the drag
    -- is still open, so a mouseup-tier effect only ENQUEUES; EndDrag then
    -- flushes it. One run, on the value the thumb came to rest on. Fire
    -- them the other way round and the commit lands after the flush,
    -- which is the silent failure this tier exists to avoid -- the effect
    -- would sit pending until something else happened to flush it.
    w.slider:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not self.bpDragging then
            self.bpDragging = true
            ns.effects.BeginDrag(w.bpCtx and w.bpCtx.app)
        end
    end)
    w.slider:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            -- Only reachable on a client that did not honor the button
            -- refusal. Nothing was committed, so the stored value is still
            -- the truth: put the thumb back on it.
            local cur = w.bpNode and ns.GetValue(w.bpNode, w.bpCtx)
            if type(cur) == "number" then
                self:SetValue(cur)
                w.box:SetText(tostring(math.floor(cur + 0.5)))
            end
            return
        end
        if button == "LeftButton" and self.bpDragging then
            self.bpDragging = nil
            if w.bpCommit then w.bpCommit(self:GetValue()) end
            ns.effects.EndDrag(w.bpCtx and w.bpCtx.app)
        end
    end)

    return w
end
-- A numeric bound that may be a FUNCTION.
--
-- `min` and `max` are normally literals, and one place they cannot be is
-- a bound that depends on another setting: the Aggro Border Size stepper
-- floors at 1 for one highlight style and 2 for another, and a literal
-- floor of 1 under a setter that clamps to 2 is a control that shows a
-- minimum it will not accept. Resolved on every apply and every refresh,
-- so a bound that moves takes the control with it.
function ns.Bound(v, node, ctx, fallback)
    if type(v) == "function" then v = v(node, ctx) end
    if type(v) ~= "number" then return fallback end
    return v
end

-- What the value box SAYS, at the precision the field actually steps in.
--
-- It used to be math.floor(v + 0.5) unconditionally, which is right for
-- the integer sliders that make up most of the panel and wrong for every
-- other one: an intensity that steps in tenths displayed its whole range
-- as "0" or "1", so dragging it appeared to do nothing at all. The step
-- decides the decimals -- 1 -> none, 0.1 -> one, 0.25 or 0.05 -> two --
-- because the step is what the reader can actually land on.
function ns.SliderText(node, v, ctx)
    local step = ns.Bound(node and node.step, node, ctx, 1) or 1
    local dec  = 0
    if step > 0 and step < 1 then
        if math.abs(step * 10 - math.floor(step * 10 + 0.5)) < 1e-6 then
            dec = 1
        elseif math.abs(step * 100 - math.floor(step * 100 + 0.5)) < 1e-6 then
            dec = 2
        else
            dec = 3
        end
    end
    if dec == 0 then return tostring(math.floor(v + 0.5)) end
    return string.format("%." .. dec .. "f", v)
end

function slider.apply(w, node, ctx)
    w.slider:SetMinMaxValues(ns.Bound(node.min, node, ctx, 0),
                             ns.Bound(node.max, node, ctx, 100))
    w.slider:SetValueStep(ns.Bound(node.step, node, ctx, 1))
    w.slider:SetObeyStepOnDrag(true)
    -- ── The two layouts ──
    --
    -- Re-anchored from scratch on every apply. A widget comes out of the
    -- pool wearing whatever the last field asked for, and SetPoint ADDS a
    -- point rather than replacing the set -- so a "below" box reused for a
    -- "side" field would hold both anchors and be stretched between them.
    local below   = ValueBelow(node, ctx)
    local compact = node.compact and true or false

    -- The box's height is a per-field decision, so it is set here rather
    -- than in create: a pooled widget arrives wearing the last field's.
    local boxH = (compact and not below) and BOX_H_COMPACT or BOX_H

    -- The unit sits at the box's RIGHT EDGE, and the box grows by its width
    -- so the digits keep the room they had without it.
    --
    -- It used to be placed against the digits, measured per value -- exact
    -- when the measurement is right, and stacked on top of the number when
    -- it is not (a box styled by SetFontObject can answer GetFont() with
    -- nil, and then every string measures as zero wide). A fixed right edge
    -- cannot be wrong: the right inset is the unit's own width, so the value
    -- has nowhere to run into it.
    local sfx = node.suffix or ""
    w.boxSuffix:SetText(sfx)
    w.boxSuffix:SetShown(sfx ~= "")
    local unitW = (sfx ~= "") and ((w.boxSuffix:GetStringWidth() or 8) + 4) or 0
    local boxW  = BOX_W + unitW
    w.box:SetSize(boxW, boxH)
    -- Equal insets: the value sits in the CENTER of the box, which is where
    -- a value sits in every other box in this panel. The unit lives inside
    -- the box at its right edge, in the width the box was widened by, so it
    -- is beside the value rather than instead of it.
    SetBoxInsets(w.box, 3, 3)

    -- Where the bar sits. Beside a box it is CENTERED on it, so the two
    -- halves of the control share a midline; the fixed inset that used to
    -- be here was tuned for one box height and went crooked the moment
    -- there were two.
    -- -1 in "below", not -4. The label above a field already ends one pixel
    -- clear of the control (see LABEL_H), so a further four put the track a
    -- visible step below its own caption -- other panels' sliders sit
    -- right under theirs. Beside a box the bar is CENTERED on it instead, so
    -- the two halves share a midline whatever the box's height.
    local barY = below and 0 or -((boxH - BAR_FRAME_H) / 2)

    w.slider:ClearAllPoints()
    w.slider:SetPoint("TOPLEFT", w, "TOPLEFT", 0, barY)
    w.slider:SetPoint("TOPRIGHT", w, "TOPRIGHT",
                      below and 0 or -(boxW + BOX_GAP), barY)

    w.box:ClearAllPoints()
    if below then
        -- Centered under the track, on the line the min/max labels share.
        w.box:SetPoint("TOP", w.slider, "BOTTOM", 0, -1)
    else
        -- Flush with the top of the widget in compact mode: there is no
        -- footer under it, so an inset here is height nothing pays for.
        w.box:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, compact and 0 or -2)
    end

    -- The labels sit level with whatever shares their row: tight under the
    -- track beside nothing, or dropped to the box's middle beside it.
    --
    -- A compact slider showing its range pulls them TIGHTER still. The
    -- footer there is a row's whole cost rather than slack in an already
    -- taller layout, and the numbers only have to clear the box.
    local labelY = below and -4 or (compact and 1 or -1)
    w.minText:ClearAllPoints()
    w.minText:SetPoint("TOPLEFT",  w.slider, "BOTTOMLEFT",  0, labelY)
    w.maxText:ClearAllPoints()
    w.maxText:SetPoint("TOPRIGHT", w.slider, "BOTTOMRIGHT", 0, labelY)

    -- A commit that does not change anything is not a commit.
    --
    -- This is not an optimization, it is a correctness guard. Writing the
    -- same value again still fires the consuming addon's effect and still
    -- re-arms any debounce behind it, so a stream of no-change commits can
    -- keep a trailing timer permanently un-elapsed -- the timer is reset
    -- faster than it can run.
    local function commit(v)
        v = math.max(ns.Bound(node.min, node, ctx, 0),
                     math.min(ns.Bound(node.max, node, ctx, 100), v))
        local cur = ns.GetValue(node, ctx)
        if type(cur) == "number" and math.abs(cur - v) < 1e-6 then return end
        ns.Commit(node, ctx, v)
    end

    -- The mouse handlers live in create(), so they are installed ONCE per
    -- pooled widget rather than once per render. apply() hands them the
    -- current field through the widget instead.
    --
    -- They used to be HookScript calls in here, which is a leak: apply runs
    -- on every render and hooks accumulate, so a slider revisited twenty
    -- times carried twenty copies of the same handler.
    w.bpNode, w.bpCtx, w.bpCommit = node, ctx, commit

    -- No fill arithmetic here. The fill's right edge is ANCHORED to the
    -- thumb, so it follows the thumb exactly and cannot fall out of step --
    -- which is what the old width calculation did in two ways: it measured
    -- against the full track while the thumb only travels between its own
    -- half-widths (the gap before the circle), and it only ran when the
    -- value actually CHANGED, so a pooled slider reused at the same value
    -- kept the previous field's fill width. That is why one of the two
    -- sliders was wrong on every visit, alternating between them.
    w.slider:SetScript("OnValueChanged", function(self, v, byUser)
        -- Our own correction, re-entering. Nothing to decide.
        if self.bpSnapBack then
            w.box:SetText(ns.SliderText(w.bpNode or node, v, w.bpCtx or ctx))
            return
        end

        -- The engine moves a Slider on ANY button, so `byUser` is also true
        -- for the right-click that was meant for the field menu. Put the
        -- value straight back, HERE: this runs inside the engine's click
        -- handling, before the frame is drawn, so the wrong value never
        -- reaches a render pass and the thumb does not visibly move. Asked
        -- of the mouse itself rather than a flag one of our handlers set,
        -- because the engine's change can arrive before that handler runs.
        if byUser and IsMouseButtonDown and IsMouseButtonDown("RightButton") then
            local cur = w.bpNode and ns.GetValue(w.bpNode, w.bpCtx)
            if type(cur) == "number" then
                self.bpSnapBack = true
                self:SetValue(cur)
                self.bpSnapBack = nil
                w.box:SetText(ns.SliderText(w.bpNode or node, cur, w.bpCtx or ctx))
                return
            end
            -- No stored number to go back to (an unbound slider): leave the
            -- thumb where it landed, but still refuse the write.
            w.box:SetText(ns.SliderText(w.bpNode or node, v, w.bpCtx or ctx))
            return
        end

        w.box:SetText(ns.SliderText(w.bpNode or node, v, w.bpCtx or ctx))
        if byUser then commit(v) end
    end)
    w.box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then commit(v); w.slider:SetValue(v) end
        self:ClearFocus()
    end)
    w.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Hover and focus feedback, on the shared border contract.
    --
    -- Same text-field behavior as the standalone text control: a click
    -- puts the caret where you clicked and selects nothing, a double click
    -- selects the value, and the selection is dropped on blur. A number
    -- box is still a text box, and the two should not disagree about what
    -- clicking into one does.
    ns.InstallHover(w.box, w.box, node, ctx)
    w.box:EnableMouse(true)
    w.box:SetScript("OnEditFocusGained", function(self)
        self.bpActive = true
        ns.PaintBorder(self, "active")
    end)
    w.box:SetScript("OnEditFocusLost", function(self)
        self.bpActive = false
        ns.PaintBorder(self, self.bpHovered and "hover" or nil)
        self:HighlightText(0, 0)
    end)
    ns.InstallTextFieldMouse(w.box)

    -- The track and thumb light up too, so the whole control responds as
    -- one object rather than only its number field.
    local function hoverTrack(hovered)
        local skin = ctx.app.skin
        local off  = ns.IsDisabled(node, ctx)
        local m    = (hovered and not off) and 1.35 or 1.15
        w.thumbTex:SetVertexColor(C(skin.accent, m, off and 0.4 or 1))
    end
    w.slider:SetScript("OnEnter", function() hoverTrack(true) end)
    w.slider:SetScript("OnLeave", function() hoverTrack(false) end)

    -- Compact mode is used where a slider is a PART of something -- the
    -- offsets inside a position widget -- rather than a field in its own
    -- right. It keeps the short box and the short row; whether it also
    -- keeps the min/max footer is the composite's call (`range`), because
    -- ten pixels twice over is a real cost in a stacked pair and the
    -- numbers are not always worth it.
    local range = ShowsRange(node)
    w.minText:SetShown(range)
    w.maxText:SetShown(range)
    if below then
        w:SetHeight(compact and SLIDER_H_BELOW_COMPACT or SLIDER_H_BELOW_FULL)
    elseif compact then
        w:SetHeight(range and SLIDER_H_COMPACT_RANGE or SLIDER_H_COMPACT)
    else
        w:SetHeight(SLIDER_H_FULL)
    end

    -- `suffix` is the field's unit: on the range, and pinned inside the
    -- value box (see boxSuffix in create). The box's CONTENTS stay a bare
    -- number, so what the reader types is what tonumber parses.
    local sfx = node.suffix or ""
    w.minText:SetText(tostring(ns.Bound(node.min, node, ctx, 0)) .. sfx)
    w.maxText:SetText(tostring(ns.Bound(node.max, node, ctx, 100)) .. sfx)


end
function slider.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    -- The track, the fill and the thumb overlap each other, so they dim by
    -- blending toward the panel background and stay fully opaque.
    -- THE SWITCH'S COLORS (owner, 2026-09-14): the filled part of the
    -- track is the track of a switch that is on, and the thumb is its
    -- knob -- ns.PaintSwitchPill's two accent multipliers, so the two
    -- controls read as one family and a retuned switch retunes the slider.
    local back = skin.panelBg
    w.track:SetVertexColor(ns.Faded(skin.controlBg, back, off))
    w.fill:SetVertexColor(ns.Faded(skin.accent, back, off, 0.42))
    w.thumbTex:SetVertexColor(ns.Faded(skin.accent, back, off, 1.25))
    ns.MarkBorder(w.box, skin, skin.controlBorder, a)
    w.boxBg:SetVertexColor(C(skin.controlBg, 1, a))
    w.box:SetTextColor(C(skin.text, 1, a))
    w.slider:SetEnabled(not off)
    w.box:SetEnabled(not off)

    -- Do NOT write the value back into a slider the reader is dragging.
    --
    -- This closed a feedback loop that ran every frame of a held drag:
    -- commit -> RefreshBinding -> here -> SetValue -> OnValueChanged. While
    -- the button is down the client reports that scripted SetValue as USER
    -- input, so byUser is true and it commits again, and again, with the
    -- mouse perfectly still. Two visible consequences: the setter ran per
    -- frame rather than per notch, and anything debounced behind it never
    -- elapsed, because every frame canceled and re-armed its timer. The
    -- first quiet moment was the mouse-up, which made a trailing debounce
    -- look like a mouse-up gate.
    --
    -- The dragged slider is also the one widget that cannot need this: its
    -- thumb IS the value. Every other widget bound to the same setting
    -- still refreshes, which is the point of the binding index.
    local sl = w.slider
    if sl.bpDragging and not IsMouseButtonDown("LeftButton") then
        -- Self-heal, as ns.effects.IsDragging does: a drag is only open
        -- while the button is down, so a flag left set means a release was
        -- missed. Left alone it would freeze this slider's display for the
        -- rest of the session.
        sl.bpDragging = nil
    end
    -- The bounds may be functions of other settings, so they are resolved
    -- again here rather than only at apply: a floor that moved while the
    -- page was up must reach the track before the value is put back into
    -- it, or the value is clamped against the old one.
    sl:SetMinMaxValues(ns.Bound(node.min, node, ctx, 0),
                       ns.Bound(node.max, node, ctx, 100))
    if not sl.bpDragging then
        local v = ns.GetValue(node, ctx) or ns.Bound(node.min, node, ctx, 0)
        sl:SetValue(v)
        -- Written OUTRIGHT, not left to OnValueChanged: SetValue fires that
        -- handler only when the value actually CHANGES, so a re-render at
        -- the same value -- the common case -- left whatever text the box
        -- happened to be carrying.
        w.box:SetText(ns.SliderText(node, v, ctx))
    end
end
-- Sliders want room: the track is the control. They stretch to use it.
function slider.measure(node, _, ctx)
    -- The box no longer eats into the track in "below", but a slider still
    -- wants room: the track IS the control, so the widths do not change.
    -- The classic width, and a minimum well below it: a slider that cannot be
    -- squeezed is a slider that never shares a row, and the flow packer
    -- is the reason this panel reflows at all.
    if ValueBelow(node, ctx) then
        return ns.CONTROL_W, 140,
               (node.compact and SLIDER_H_BELOW_COMPACT or SLIDER_H_BELOW_FULL)
    end
    if node.compact then
        return ns.CONTROL_W, 140,
               ShowsRange(node) and SLIDER_H_COMPACT_RANGE or SLIDER_H_COMPACT
    end
    return ns.CONTROL_W, 140, ROW_H + 14
end
slider.stretch = true

-- Continuous: the setter fires on every notch of a drag, so what is behind
-- it is a stream to coalesce rather than a single event.
slider.defaultTier = "debounce"

ns.builtinControls = {
    switch = switch,
    toggle = switch,
    slider = slider,
    range  = slider,
}

-- ── dropdown ───────────────────────────────────────────────────
--
-- Ours, not WowStyle1DropdownTemplate.
--
-- The native one was tried first and gave two problems that could not be
-- fixed from outside it. Its closed-state label is derived from whichever
-- radio is checked AT MENU GENERATION TIME, so selecting an option left the
-- button showing the previous one until the menu was opened again -- the
-- "selection lags one click behind" bug -- and forcing a regeneration to
-- work around that meant regenerating the menu on every refresh, which is
-- what made the labels flicker. It also carries Blizzard's own hover art,
-- which cannot be restyled to match the rest of the panel.
--
-- This one holds its own value, writes its own label, and is drawn from the
-- same tokens and the same border treatment as every other control.

local dropdown = {}
local DD_ROW_H, DD_PAD = 20, 4

-- A field's option list may be a FUNCTION, resolved every time it is read
-- rather than once when the page is declared -- a list of the user's own
-- layouts, profiles or containers changes while the panel is open, and a
-- list frozen at declaration would go stale the moment one was added.
-- Every reader goes through here, so no control can accidentally support
-- only the table form.
local function OptionList(node)
    local o = node.options
    if type(o) == "function" then o = o(node) end
    return o or {}
end
ns.OptionList = OptionList

-- A field's LABEL may be a function too, resolved every time it is read
-- rather than once when the page was declared.
--
-- The library already resolves `options`, `desc`, `hidden` and `disabled`
-- that way, and a label is the same kind of thing: a button whose label IS
-- its state ("Select All" while anything is off, "Deselect All" once
-- everything is on) has no honest static text. Without this the function
-- reached SetText untouched and threw, which is a poor way to find out.
--
-- Every reader goes through here -- the width measure, the two "does this
-- field have a label" tests, the FontString, and the search index -- so no
-- consumer can accidentally support only the string form.
function ns.FieldLabel(field)
    local l = field and field.label
    if type(l) == "function" then l = l(field) end
    if l == nil or l == false then return nil end
    return tostring(l)
end

-- A composite's `binds` entry: either a bare path, or a table that carries
-- the same reader/writer fields an ordinary field does.
--
--     binds = { point = "buffAnchorPoint",              -- a plain path
--               x     = { bind = "offsetX",             -- or a full node
--                         get = Get("offsetX"),
--                         set = Set("offsetX"),
--                         id = "offsetX", default = 0 } }
--
-- The table form exists because a composite's settings are not always plain
-- storage. An anchor point that ALSO writes that anchor's default grow
-- direction, or a container setting behind a two-tier inherit, has a writer
-- of its own -- and until this existed a composite had one write path for
-- all of its binds and nowhere to hang that. Every position triplet in an
-- addon with such a setter had to stay three separate controls because of
-- it.
--
-- Both forms are read through the same two helpers, so no consumer can
-- accidentally support only one of them.

-- The storage PATH an entry names, for the things that key on a path:
-- the widget index, the refresh index and the search haystack.
function ns.BindPath(entry)
    if type(entry) == "table" then return entry.bind end
    return entry
end

-- The NODE an entry is read and written through. `extra` is the sub-node
-- the composite has already built (its control kind, its range); the
-- entry's own fields are laid over it.
local BIND_FIELDS = { "bind", "get", "set", "id", "default" }
function ns.BindNode(entry, extra)
    local n = extra or {}
    if type(entry) == "table" then
        for _, k in ipairs(BIND_FIELDS) do
            if n[k] == nil then n[k] = entry[k] end
        end
    else
        n.bind = entry
    end
    return n
end

-- An option is either a bare value or a table carrying its own text, icon
-- and description. The third return is that description, which is what
-- lets a single option explain itself rather than borrowing the field's.
local function OptionAt(node, i)
    local opt = OptionList(node)[i]
    if opt == nil then return nil end
    if type(opt) == "table" then return opt.value, opt.text, (opt.desc or opt.tooltip) end
    return opt, tostring(opt), nil
end

-- Resolved on HOVER, for the same reason a field's desc is: an option
-- description may be a function of the current state, and capturing it at
-- render time would freeze it at whatever was true when the page was built.
local function OptionDesc(d, node, ctx)
    if type(d) == "function" then return d(node, ctx) end
    return d
end

local function DisplayText(node, ctx)
    local cur = ns.GetValue(node, ctx)
    for i = 1, #OptionList(node) do
        local v, t = OptionAt(node, i)
        if v == cur then return t end
    end
    return tostring(cur or "")
end

-- One shared click-catcher: a transparent full-screen button that sits just
-- under whichever menu is open, so clicking anywhere else closes it. It is
-- created on the library, not per app, because only one menu can be open at
-- a time across the whole UI -- and it holds no app state.
local catcher
local function EnsureCatcher()
    if catcher then return catcher end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()
    return catcher
end

local openMenu   -- the one menu currently up, if any

local ARROW_CLOSED, ARROW_OPEN = -math.pi / 2, math.pi / 2

local function CloseDropdown()
    local m = openMenu
    if not m then return end
    -- Clear the state FIRST: Hide fires OnHide, which calls back in here.
    openMenu = nil
    local w  = m.owner
    local cb = m.bpOnClose
    m.bpOnClose = nil
    m:Hide()
    if catcher then catcher:Hide() end
    if w then
        w.bpActive = false
        ns.PaintBorder(w, w.bpHovered and "hover" or nil)
        if w.arrow then w.arrow:SetRotation(ARROW_CLOSED) end
    end
    if cb then cb() end
end
ns.CloseDropdown = CloseDropdown

-- ── The menu, shared ───────────────────────────────────────────
--
-- ONE menu frame for the whole library, not one per control.
--
-- The dropdown CONTROL and the dropdown NAVIGATOR want exactly the same
-- object: a list of rows, a check beside the current one, a click-catcher
-- behind it and Escape to close. Two copies of that would drift -- the
-- navigator's would quietly miss the edge-flip near the bottom of the
-- screen, or the row highlight, or the tooltip. So the menu is a service:
-- callers hand it an anchor and a list of items and know nothing about how
-- it is drawn.
--
-- Only one menu can be open across the whole UI, which is what makes a
-- single frame correct rather than merely economical.

local function MenuRow(menu, i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu.content)
    r:SetHeight(DD_ROW_H)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints(r)
    r.hl:Hide()
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetTexture(MEDIA .. "check.tga")
    r.check:SetSize(10, 10)
    r.check:SetPoint("LEFT", r, "LEFT", 7, 0)
    -- The preview bar a media option can ask for: the texture itself,
    -- drawn across the row with the name over it, which is how a texture
    -- picker has always shown what it is offering. BORDER rather than
    -- BACKGROUND so it sits above the row highlight and below the label.
    r.preview = r:CreateTexture(nil, "BORDER")
    r.preview:Hide()
    r.text = ns.FS(r, "OVERLAY", "GameFontNormalSmall")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    -- A row that drew a FONT preview has to be put back when the pool hands
    -- it to a plain row later. Rows are reused; a SetFont with no way home
    -- is a menu that slowly turns into whatever fonts happened to scroll
    -- past. The way home is ns.BaseFont, asked for at the time rather than
    -- cached at birth -- a cache taken here would restore the face the
    -- panel wore when the row was built, not the one it wears now.
    -- A separator borrows the same row object rather than being a second
    -- kind of thing to pool: one rule, centered, with the row's mouse off.
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetHeight(1)
    r.rule:Hide()
    -- The addon's own switch, for a row that is a setting rather than a
    -- choice. Built with the row, shown only where a row asks for it.
    r.pill = ns.SwitchPill(r)
    r.pill:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.pill:Hide()
    menu.rows[i] = r
    return r
end

-- The slider a menu row can carry (kind = "slider"): a two-line row, the
-- caption and its value over a draggable track. Built on demand, so a
-- menu of plain rows pays nothing for it.
local function EnsureMenuSlider(r)
    if r.strack then return end
    local t = CreateFrame("Frame", nil, r)
    t:SetHeight(4)
    t.bg = t:CreateTexture(nil, "ARTWORK")
    t.bg:SetAllPoints(t)
    t.fill = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.fill:SetPoint("TOPLEFT",    t, "TOPLEFT",    0, 0)
    t.fill:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    t.thumb = t:CreateTexture(nil, "OVERLAY")
    t.thumb:SetTexture(MEDIA .. "circle.tga")
    t.thumb:SetSize(11, 11)
    r.strack = t
    r.sval = ns.FS(r, "OVERLAY", "GameFontNormalSmall")
    r.sval:SetJustifyH("RIGHT")
    r.sval:SetWordWrap(false)
end

-- A media option previews ITSELF: a font row is drawn in that font, a
-- texture row draws the texture behind its name. Both are optional and
-- both are per-option, so a menu of ordinary words costs one table lookup
-- a row and nothing else.
--
-- pcall around SetFont: the path comes from whatever registered the media,
-- the file may not be there, and a failed SetFont leaves a FontString with
-- no font at all -- an invisible row. Falling back to the row's own font
-- shows the name in plain text, which is what the row would have been.
local function SetRowFont(r, item)
    local f = { ns.BaseFont(r.text) }
    if item.font then
        local ok = pcall(r.text.SetFont, r.text, item.font, f[2] or 12, f[3])
        if not ok then r.text:SetFont(f[1], f[2] or 12, f[3]) end
    elseif item.texture then
        -- OUTLINED over a texture row, which is what the picker this
        -- copies does: its rows draw the bar at full strength and put
        -- outlined white text on top. An outline is what lets a label sit
        -- over a bright bar without either being dimmed for the other.
        r.text:SetFont(f[1], f[2] or 12, "OUTLINE")
    else
        r.text:SetFont(f[1], f[2] or 12, f[3])
    end
end

local function PaintRowPreview(r, item, textLeft)
    -- Set again here, and not only in the width pass: rows are pooled, and
    -- the pass that measures them is skipped outright for a menu of fixed
    -- width.
    SetRowFont(r, item)

    if item.texture then
        r.preview:ClearAllPoints()
        r.preview:SetPoint("LEFT",  r, "LEFT",  textLeft - 4, 0)
        r.preview:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        r.preview:SetHeight(math.max(10, (r:GetHeight() or DD_ROW_H) - 6))
        r.preview:SetTexture(item.texture)
        -- FULL STRENGTH. A texture picker is for judging the texture, and
        -- a dimmed bar is a different texture to look at than the one you
        -- are choosing. The label stays readable by being outlined (see
        -- SetRowFont) rather than by the bar being faded under it.
        r.preview:SetVertexColor(1, 1, 1, 1)
        r.preview:Show()
    else
        r.preview:Hide()
    end
end

local MENU_BAR_W = 10

-- Repaint the shared menu's scrollbar from the CURRENT app's skin (stored on
-- the menu as bpApp each open), the way the rail tree's bar paints itself.
local function MenuPaintBar(m)
    local app = m.bpApp
    if not (app and m.bar) then return end
    local skin = app.skin
    local bar  = m.bar
    bar.trackBorder:SetVertexColor(C(skin.controlBorder, 1, 1))
    bar.trackTex:SetVertexColor(C(skin.controlBg, 1, 1))
    local hot = bar.thumb.dragging or bar.thumb.hovered
    local c   = hot and skin.accent or skin.textMuted
    bar.thumb.tex:SetVertexColor(c[1], c[2], c[3], 1)
end

-- Size and place the thumb from the SHARE of the content on screen and the
-- current pixel scroll -- both handed in on m by ShowMenu.
local function MenuUpdateThumb(m)
    local bar   = m.bar
    local range = m.bpRange or 0
    if not bar or range <= 0 then if bar then bar:Hide() end return end
    local track = math.max(1, (bar:GetHeight() or 0) - 4)
    local th    = math.max(20, track * ((m.bpViewportH or 1) / (m.bpContentH or 1)))
    local pos   = (m.scroll:GetVerticalScroll() or 0) / range
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("LEFT",  bar, "LEFT",   2, 0)
    bar.thumb:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.thumb:SetPoint("TOP",   bar, "TOP",    0, -(2 + pos * (track - th)))
    bar.thumb:SetHeight(th)
end

local menuFrame
local function EnsureMenu()
    if menuFrame then return menuFrame end
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(10)
    -- One unit per pixel, like the panel it opens from (Frame.lua
    -- StampPanelScale); re-stamped on every open in case the scale moved.
    if ns.StampPanelScale then ns.StampPanelScale(m) end
    m:EnableMouse(true)
    m:Hide()
    -- The same two-piece shape a group card wears, NOT ns.BorderedRound: a
    -- nine-sliced corner is drawn at its texel size in UI units, so at any
    -- UI scale but 1 its arc lands between pixels and reads as blur. Here
    -- the ring is drawn at inset 0 and the surface at the stroke, both with
    -- corners sized in physical pixels, so the menu's corners match the
    -- panel's exactly. Radius and stroke are re-stated on every open.
    m.paintRing, m.setRingRadius = ns.RoundedFill(m, "BACKGROUND", 8, nil, { 0, 0, 0, 1 }, 0)
    m.paintBody, m.setBodyRadius, m.setBodyInset =
        ns.RoundedFill(m, "BORDER", 8, nil, { 0, 0, 0, 1 }, 1)
    m.rows = {}
    -- Long menus scroll: the rows live in a content frame inside this
    -- viewport, so a menu taller than its cap clips and scrolls rather than
    -- running off the screen. Sized per open in ShowMenu.
    m.scroll = CreateFrame("ScrollFrame", nil, m)
    m.scroll:EnableMouseWheel(true)
    m.content = CreateFrame("Frame", nil, m.scroll)
    m.content:SetPoint("TOPLEFT", m.scroll, "TOPLEFT", 0, 0)
    m.scroll:SetScrollChild(m.content)
    m.scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = m.bpRange or 0
        if range <= 0 then return end
        local step = (m.bpRowH or DD_ROW_H) * 2
        local v = math.max(0, math.min(range,
            (self:GetVerticalScroll() or 0) - delta * step))
        self:SetVerticalScroll(v)
        MenuUpdateThumb(m)
    end)

    -- The scrollbar, built once and shown only when the menu overflows.
    local bar = CreateFrame("Frame", nil, m)
    bar:EnableMouse(true)
    bar.trackBorder, bar.trackTex = ns.BorderedRound(bar, 4, "BACKGROUND", "BORDER")
    local thumb = CreateFrame("Button", nil, bar)
    thumb.tex = ns.RoundTex(thumb, "ARTWORK", 4)
    thumb.tex:SetAllPoints(thumb)
    bar.thumb = thumb
    m.bar = bar
    local function onThumbDrag(self)
        local range = m.bpRange or 0
        if range <= 0 then return end
        local track  = math.max(1, (bar:GetHeight() or 0) - 4)
        local th     = math.max(20, track * ((m.bpViewportH or 1) / (m.bpContentH or 1)))
        local trange = track - th
        if trange <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / (bar:GetEffectiveScale() or 1)
        local v = self.grabScroll + ((self.grabY - cy) / trange) * range
        m.scroll:SetVerticalScroll(math.floor(math.max(0, math.min(range, v)) + 0.5))
        MenuUpdateThumb(m)
    end
    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.grabY      = cy / (bar:GetEffectiveScale() or 1)
        self.grabScroll = m.scroll:GetVerticalScroll() or 0
        self.dragging   = true
        self:SetScript("OnUpdate", onThumbDrag)
        MenuPaintBar(m)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        MenuPaintBar(m)
    end)
    thumb:SetScript("OnEnter", function(self) self.hovered = true;  MenuPaintBar(m) end)
    thumb:SetScript("OnLeave", function(self) self.hovered = false; MenuPaintBar(m) end)
    -- A click on the track pages by a viewportful, as every list does.
    bar:SetScript("OnMouseDown", function(self)
        local range = m.bpRange or 0
        if range <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / (bar:GetEffectiveScale() or 1)
        local top, bottom = thumb:GetTop(), thumb:GetBottom()
        if top and bottom and cy <= top and cy >= bottom then return end
        local dir = (cy < (bottom or 0)) and 1 or -1
        local v = (m.scroll:GetVerticalScroll() or 0) + dir * (m.bpViewportH or 0)
        m.scroll:SetVerticalScroll(math.floor(math.max(0, math.min(range, v)) + 0.5))
        MenuUpdateThumb(m)
    end)
    -- The heading is a band of its own rather than a row that happens to be
    -- bold, because it can carry its own background color -- and a band
    -- with a background has to reach the menu's edges, which a padded row
    -- cannot. Sublevel 1 puts it over the menu's fill, which is on the same
    -- layer.
    m.titleBg = m:CreateTexture(nil, "BORDER", nil, 1)
    m.titleBg:Hide()
    m.titleRule = m:CreateTexture(nil, "ARTWORK")
    m.titleRule:SetHeight(1)
    m.titleRule:Hide()
    m.title = ns.FS(m, "OVERLAY", "GameFontNormalSmall")
    m.title:SetWordWrap(false)
    m.title:Hide()
    -- Escape closes, and nothing else is swallowed.
    m:EnableKeyboard(true)
    m:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CloseDropdown()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    m:SetScript("OnHide", function() if openMenu then CloseDropdown() end end)
    menuFrame = m
    return m
end

-- Is the menu currently open FOR this anchor? A control uses this to close
-- its own menu when it is disabled without closing somebody else's.
function ns.MenuIsOpenFor(owner) return openMenu and openMenu.owner == owner end

-- A bar renderer offers each cell it has just placed: the one whose key
-- matches the open menu's ownerKey becomes the menu's new anchor frame.
-- Pooled cells lose their identity across a re-render; the key keeps it.
function ns.RebindOpenMenu(frame, key)
    local m = openMenu
    if not (m and m.bpOwnerKey and frame) then return end
    if key == nil or tostring(key) ~= m.bpOwnerKey then return end
    m.owner = frame
end

-- ── Menu style ─────────────────────────────────────────────────
--
-- Every knob a menu has is resolved in one place, from three sources in
-- order: the `opts` handed to this call, the app's own menu style (see
-- App:SetMenuStyle), and the defaults below -- with colors falling back to
-- the app's skin tokens instead, so an unstyled menu looks exactly as it
-- always did. Any value may be a FUNCTION, read at open time, so a menu can
-- take its width or its heading color from state that changes.
local MENU_DEFAULTS = {
    grow         = "auto",   -- "up" | "down" | "left" | "right" | "auto"
    align        = "start",  -- along the anchor's other axis
    offset       = 2,
    rowHeight    = DD_ROW_H,
    padding      = DD_PAD,
    sepHeight    = 7,
    -- A function, read at open time: the menu is a CARD-shaped surface and
    -- wears the card stroke unless a caller pins its own.
    borderSize   = function() return ns.BorderStroke("card") end,
    closeOnPick  = true,
    -- radius: unset, a menu wears the panel's own corner (skin.borderRadius).
    titleHeight  = 20,
    titleJustify = "LEFT",
    titleRule    = true,
    -- Rows before a scrollbar appears. 21+ items scroll; configurable via
    -- opts.maxItems or App:SetMenuStyle{ maxItems = n }.
    maxItems     = 20,
}

local function MenuOpt(app, opts, key)
    local v = opts and opts[key]
    if v == nil then v = app.menuStyle and app.menuStyle[key] end
    if v == nil then v = MENU_DEFAULTS[key] end
    if type(v) == "function" then v = v() end
    return v
end

local function MenuColor(app, opts, key, fallback)
    return MenuOpt(app, opts, key) or fallback
end

-- A row's state may be a function, so a toggle row can re-read it after it
-- has been flipped without the menu being rebuilt.
local function Selected(item)
    local v = item.selected
    if type(v) == "function" then v = v() end
    return v and true or false
end

-- items[i] = { text, desc, selected, onPick } or { kind = "separator" }
--
-- `desc` may be a function, called on hover rather than now, so a row can
-- describe state that changes. `onPick` is called with the menu already
-- closed, so anything it triggers -- a re-render, a navigation -- happens
-- against a settled UI.
--
-- `opts` is the style table described above. It is optional: without it the
-- menu drops down from the anchor, is at least as wide as it, and is
-- painted from the skin.
local function BuildMenu(owner, app, items, opts)
    local m    = EnsureMenu()
    if ns.StampPanelScale then ns.StampPanelScale(m) end
    local skin = app.skin
    m.owner = owner
    m.bpApp = app
    -- Kept for ns.ReanchorMenu, which re-runs this whole build in place
    -- when the panel's scale or layout moves under an open menu.
    m.bpItems, m.bpOpts = items, opts
    -- The owner's IDENTITY, when the caller supplies one (opts.ownerKey).
    -- The owner FRAME is pooled: a bar re-render releases and re-acquires
    -- its cells, so the frame the menu opened from may stand for a
    -- different cell a render later. The key is what survives -- see
    -- ns.RebindOpenMenu.
    m.bpOwnerKey = opts and opts.ownerKey ~= nil
        and tostring(opts.ownerKey) or nil
    -- Called when this menu closes, however it closes -- a pick, a click
    -- outside, Escape. A bar whose cell opened the menu refreshes HERE
    -- rather than on the click, because re-rendering the bar while the menu
    -- is up would release the very button the menu is anchored to.
    m.bpOnClose = opts and opts.onClose or nil

    local rowH   = MenuOpt(app, opts, "rowHeight")
    local pad    = MenuOpt(app, opts, "padding")
    local sepH   = MenuOpt(app, opts, "sepHeight")
    local stroke = MenuOpt(app, opts, "borderSize")
    local closeOnPick = MenuOpt(app, opts, "closeOnPick")
    local radius = MenuOpt(app, opts, "radius") or skin.borderRadius or 8

    local cBorder = MenuColor(app, opts, "border",       skin.controlBorder)
    -- controlBg, not panelBg: a menu is the control it opened from, made
    -- tall enough to show its options -- so it wears the control surface
    -- rather than the page behind it, and the two no longer step a shade
    -- apart as the list drops. A caller can still name its own `bg`.
    local cBg     = MenuColor(app, opts, "bg",           skin.controlBg)
    local cText   = MenuColor(app, opts, "text",         skin.text)
    local cSel    = MenuColor(app, opts, "textSelected", skin.accent)
    local cHl     = MenuColor(app, opts, "highlight",    skin.accentDim)
    local cCheck  = MenuColor(app, opts, "check",        cSel)
    local cRule   = MenuColor(app, opts, "divider",      skin.divider)

    -- The frame is shared, so every render re-states the shape as well as
    -- the color: a menu opened with a 12px radius must not leave the next
    -- one rounded. The surface is a SECOND shape inset by the stroke rather
    -- than a fill inside a border texture, which is what keeps the corner
    -- one texel to one physical pixel -- see ns.RoundedFill.
    m.setBodyInset(stroke)
    m.setRingRadius(radius)
    m.setBodyRadius(radius)
    m.paintRing(cBorder)
    m.paintBody(cBg)

    -- ── Heading ──
    local title  = MenuOpt(app, opts, "title")
    local titleH = title and MenuOpt(app, opts, "titleHeight") or 0
    if title then
        local cTitle   = MenuColor(app, opts, "titleColor", skin.textHeading)
        local cTitleBg = MenuOpt(app, opts, "titleBg")
        m.titleBg:ClearAllPoints()
        m.titleBg:SetPoint("TOPLEFT",  m, "TOPLEFT",   stroke, -stroke)
        m.titleBg:SetPoint("TOPRIGHT", m, "TOPRIGHT", -stroke, -stroke)
        m.titleBg:SetHeight(titleH)
        if cTitleBg then
            m.titleBg:SetColorTexture(C(cTitleBg, 1, 1))
            m.titleBg:Show()
        else
            m.titleBg:Hide()
        end
        local just = MenuOpt(app, opts, "titleJustify")
        m.title:ClearAllPoints()
        m.title:SetPoint("LEFT",  m, "TOPLEFT",   stroke + 8, -stroke - titleH / 2)
        m.title:SetPoint("RIGHT", m, "TOPRIGHT", -stroke - 8, -stroke - titleH / 2)
        m.title:SetJustifyH(just)
        m.title:SetText(title)
        m.title:SetTextColor(C(cTitle, 1, 1))
        m.title:Show()
        m.titleRule:ClearAllPoints()
        m.titleRule:SetPoint("TOPLEFT",  m, "TOPLEFT",   stroke, -stroke - titleH)
        m.titleRule:SetPoint("TOPRIGHT", m, "TOPRIGHT", -stroke, -stroke - titleH)
        m.titleRule:SetColorTexture(C(cRule, 1, 1))
        if ns.NoSnap then ns.NoSnap(m.titleRule) end
        m.titleRule:SetShown(MenuOpt(app, opts, "titleRule") and true or false)
    else
        m.titleBg:Hide()
        m.title:Hide()
        m.titleRule:Hide()
    end

    -- ── Width ──
    --
    -- A fixed width wins outright; otherwise the menu is as wide as its
    -- widest label, never narrower than `minWidth` (the anchor, by default,
    -- so a dropdown lines up with its control) and never wider than
    -- `maxWidth`, where labels truncate rather than run off the screen.
    local fixed  = MenuOpt(app, opts, "width")
    local minW   = MenuOpt(app, opts, "minWidth")
    local maxW   = MenuOpt(app, opts, "maxWidth")
    if minW == nil then minW = owner:GetWidth() or 0 end
    local widest = fixed or minW
    if not fixed and title then
        widest = math.max(widest, m.title:GetStringWidth() + 16 + stroke * 2)
    end

    local n = #items

    -- One indent for the whole menu, not one per row. A menu with any
    -- toggle in it reserves the switch column on EVERY row, so a toggle's
    -- label starts where a plain row's label starts instead of the two
    -- stepping in and out down the list.
    local anyToggle = false
    for i = 1, n do
        if items[i].kind == "toggle" then anyToggle = true; break end
    end
    local textLeft = anyToggle and (6 + SW_W + 8) or 22

    for i = 1, n do
        local item = items[i]
        if not fixed and item.kind ~= "separator" then
            local r = MenuRow(m, i)
            -- In the font the row will actually be drawn in. A font picker
            -- previews its own faces, and they are not all the width the
            -- menu's own font would have made them -- measuring in one and
            -- drawing in another is a menu whose longest names truncate.
            SetRowFont(r, item)
            r.text:SetText(item.text)
            widest = math.max(widest, r.text:GetStringWidth() + textLeft + 22)
            -- A slider row carries its value beside the caption and wants
            -- room for the track to be usable at all.
            if item.kind == "slider" then
                widest = math.max(widest, r.text:GetStringWidth() + textLeft + 96)
            end
        end
    end
    if not fixed and maxW then widest = math.min(widest, maxW) end

    -- ── Rows ──
    --
    -- Painting a row is its own function because a TOGGLE row repaints
    -- itself in place: flipping a setting from a menu leaves the menu open,
    -- so the switch has to show the new state without the menu being rebuilt
    -- underneath the cursor.
    local function PaintRow(r, item)
        local on = Selected(item)
        r.text:SetTextColor(C(on and cSel or cText, on and 1.15 or 1, 1))
        if item.kind == "toggle" then
            ns.PaintSwitchPill(r.pill, skin, on, false)
            r.pill.ring:SetVertexColor(C(on
                and { skin.accent[1], skin.accent[2], skin.accent[3], 0.7 }
                or cBorder, 1, 1))
        else
            r.check:SetShown(on)
        end
    end

    -- Rows live in the scrolling content, laid from its own top; `pad` is
    -- the content's top and bottom margin. `rowTops[i]` is where row i
    -- begins, so the viewport can be sized to show exactly `maxItems` rows.
    local maxItems = MenuOpt(app, opts, "maxItems") or 20
    local overflow = n > maxItems
    local gutter   = overflow and (MENU_BAR_W + 4) or 0
    widest = widest + gutter
    local rowTops = {}
    local y = pad
    for i = 1, n do
        local item   = items[i]
        local r      = MenuRow(m, i)
        local sep     = (item.kind == "separator")
        local toggle  = (item.kind == "toggle")
        local sliderK = (item.kind == "slider")
        -- A toggle row carries the switch at its full height, so it is
        -- never shorter than the pill plus a little air; a slider row is
        -- two lines, the caption and value over the track.
        local h = sep and sepH
            or (toggle and math.max(rowH, SW_H + 6))
            or (sliderK and (rowH + 14))
            or rowH

        rowTops[i] = y
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  m.content, "TOPLEFT",   pad, -y)
        r:SetPoint("TOPRIGHT", m.content, "TOPRIGHT", -pad, -y)
        r:SetHeight(h)
        r:EnableMouse(not sep)

        if sep then
            r.rule:ClearAllPoints()
            r.rule:SetPoint("LEFT",  r, "LEFT",   2, 0)
            r.rule:SetPoint("RIGHT", r, "RIGHT", -2, 0)
            r.rule:SetColorTexture(C(cRule, 1, 1))
            if ns.NoSnap then ns.NoSnap(r.rule) end
            r.rule:Show()
            r.text:Hide()
            r.preview:Hide()
            r.check:Hide()
            r.pill:Hide()
            r.hl:Hide()
            if r.strack then r.strack:Hide(); r.sval:Hide() end
            r:SetScript("OnEnter", nil)
            r:SetScript("OnLeave", nil)
            r:SetScript("OnClick", nil)
            r:SetScript("OnMouseDown", nil)
            r:SetScript("OnMouseUp", nil)
            r:SetScript("OnUpdate", nil)
        elseif sliderK then
            r.rule:Hide()
            r.preview:Hide()
            r.pill:Hide()
            r.check:SetShown(false)
            r.hl:SetColorTexture(cHl[1], cHl[2], cHl[3], cHl[4] or 0.18)
            r.hl:Hide()
            EnsureMenuSlider(r)
            r.text:ClearAllPoints()
            r.text:SetPoint("TOPLEFT", r, "TOPLEFT", textLeft, -4)
            r.text:SetText(item.text)
            r.text:Show()
            r.sval:ClearAllPoints()
            r.sval:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -4)
            r.sval:Show()
            PaintRow(r, item)
            r.sval:SetTextColor(C(cText, 1, 0.9))
            local t = r.strack
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT",  r, "BOTTOMLEFT",  textLeft, 7)
            t:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -12, 7)
            -- The switch's colors, like the page slider: the filled part
            -- is an ON switch track, the thumb its knob.
            t.bg:SetColorTexture(C(cRule, 1, 1))
            t.fill:SetColorTexture(C(skin.accent, 0.42, 1))
            t.thumb:SetVertexColor(C(skin.accent, 1.25, 1))
            if ns.NoSnap then ns.NoSnap(t.bg); ns.NoSnap(t.fill) end
            t:Show()
            local minV = tonumber(item.min) or 0
            local maxV = tonumber(item.max) or 1
            local step = tonumber(item.step) or 0.05
            if maxV <= minV then maxV = minV + 1 end
            local function Cur()
                local v = tonumber(item.get and item.get()) or minV
                if v < minV then v = minV elseif v > maxV then v = maxV end
                return v
            end
            -- The value being dragged, not yet committed. Declared ABOVE
            -- Paint, which reads it.
            local dragV
            local function Paint()
                local v   = dragV or Cur()
                local w   = t:GetWidth() or 0
                local pos = (v - minV) / (maxV - minV)
                if item.format then r.sval:SetText(item.format(v))
                else r.sval:SetText(string.format("%.2f", v)) end
                if w > 0 then
                    t.fill:SetWidth(math.max(0.01, w * pos))
                    t.thumb:ClearAllPoints()
                    t.thumb:SetPoint("CENTER", t, "LEFT", w * pos, 0)
                end
            end
            -- The track has no width until the menu is sized, and changes
            -- it if the menu reopens wider; geometry follows from here.
            t:SetScript("OnSizeChanged", Paint)
            -- While dragging, the value SHOWN follows the mouse but the
            -- setter waits for the release: applying a panel scale per
            -- step mid-drag re-lays the whole panel out under the cursor,
            -- and the reader asked for the size they let go on, not every
            -- size on the way there.
            local function ValueAt(absLeft, absW, commit)
                local x   = GetCursorPosition()
                local rel = (x - absLeft) / absW
                if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
                local v = minV + rel * (maxV - minV)
                v = minV + math.floor((v - minV) / step + 0.5) * step
                v = math.floor(v * 1000 + 0.5) / 1000
                if v > maxV then v = maxV end
                if commit then
                    dragV = nil
                    if v ~= Cur() and item.set then item.set(v) end
                else
                    dragV = v
                end
                Paint()
            end
            r.bpDesc, r.bpTipOwner, r.bpText = item.desc, owner, item.text
            r:SetScript("OnEnter", function(self)
                self.hl:Show()
                local dd = self.bpDesc
                if type(dd) == "function" then dd = dd() end
                if dd then ns.context.Show(self, app, self.bpText, dd) end
            end)
            r:SetScript("OnLeave", function(self)
                self.hl:Hide()
                ns.context.Hide()
            end)
            -- Dragging IS the interaction: the value follows the mouse
            -- from the press, quantized to `step`, and the menu stays up.
            --
            -- The track's place and length are taken ONCE, at the press, in
            -- absolute (scale-free) coordinates, and the whole drag is
            -- measured against that frozen ruler. Live geometry feeds back:
            -- setting the value re-stamps the panel and this very menu, the
            -- track shifts under a motionless cursor, the next frame reads
            -- a new position, and the value runs away to an end of the
            -- range.
            r:SetScript("OnClick", nil)
            local grabLeft, grabW
            r:SetScript("OnMouseDown", function(self)
                local eff  = t:GetEffectiveScale() or 1
                local left = t:GetLeft()
                local w    = t:GetWidth() or 0
                if not left or w <= 0 then return end
                grabLeft, grabW = left * eff, w * eff
                ValueAt(grabLeft, grabW, false)
                self:SetScript("OnUpdate", function()
                    ValueAt(grabLeft, grabW, false)
                end)
            end)
            r:SetScript("OnMouseUp", function(self)
                self:SetScript("OnUpdate", nil)
                if grabLeft and grabW then
                    ValueAt(grabLeft, grabW, true)
                end
            end)
            Paint()
        else
            r.rule:Hide()
            if r.strack then r.strack:Hide(); r.sval:Hide() end
            r:SetScript("OnMouseDown", nil)
            r:SetScript("OnMouseUp", nil)
            r:SetScript("OnUpdate", nil)
            -- The switch leads, then the label: a setting reads as its
            -- state and then its name, the way a row of fields does.
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT",  r, "LEFT",  textLeft, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.text:SetText(item.text)
            r.text:Show()
            r.check:SetShown(false)
            r.check:ClearAllPoints()
            -- Centered in the switch column where there is one, so a check
            -- and a switch sit on the same axis.
            r.check:SetPoint("LEFT", r, "LEFT",
                anyToggle and (6 + (SW_W - 10) / 2) or 7, 0)
            r.check:SetVertexColor(C(cCheck, 1.15, 1))
            r.pill:SetShown(toggle)
            r.hl:SetColorTexture(cHl[1], cHl[2], cHl[3], cHl[4] or 0.18)
            r.hl:Hide()
            PaintRowPreview(r, item, textLeft)
            PaintRow(r, item)

            -- The menu is a UIParent-level frame of its own, so a row's
            -- tooltip cannot collide with the field tooltip attached across
            -- a control's own subtree. Anchored to the row, which is where
            -- the reader is.
            r.bpDesc, r.bpTipOwner, r.bpText = item.desc, owner, item.text
            r:SetScript("OnEnter", function(self)
                self.hl:Show()
                local dd = self.bpDesc
                if type(dd) == "function" then dd = dd() end
                if dd then ns.context.Show(self, app, self.bpText, dd) end
            end)
            r:SetScript("OnLeave", function(self)
                self.hl:Hide()
                ns.context.Hide()
            end)
            r:SetScript("OnClick", function(self)
                -- A toggle NEVER closes the menu: you came here to change
                -- settings, and a menu that shuts on every flip makes you
                -- reopen it for the next one. Anything else closes first,
                -- so whatever the pick triggers -- a navigation, another
                -- window -- happens against a settled UI, unless the item
                -- or the menu asks to stay open.
                if item.kind == "toggle" then
                    if item.onPick then item.onPick() end
                    PaintRow(self, item)
                    return
                end
                if closeOnPick and not item.keepOpen then CloseDropdown() end
                if item.onPick then item.onPick() end
            end)
        end
        r:Show()
        y = y + h
    end
    for i = n + 1, #m.rows do m.rows[i]:Hide() end

    -- ── Viewport & scroll ──
    --
    -- The rows scroll inside a fixed viewport once there are more than
    -- `maxItems`; a shorter menu sizes the viewport to its whole content and
    -- shows no bar. The heading stays put above the viewport.
    local contentH  = y + pad
    local viewportH = overflow and (rowTops[maxItems + 1] or contentH) or contentH
    local innerW    = widest - stroke * 2 - gutter

    m.bpRowH = rowH
    m.content:SetSize(innerW, contentH)
    m.scroll:ClearAllPoints()
    m.scroll:SetPoint("TOPLEFT", m, "TOPLEFT", stroke, -(stroke + titleH))
    m.scroll:SetSize(innerW, viewportH)
    m.scroll:SetVerticalScroll(0)
    m.scroll:Show()

    if overflow then
        m.bpContentH  = contentH
        m.bpViewportH = viewportH
        m.bpRange     = contentH - viewportH
        m.bar:ClearAllPoints()
        m.bar:SetPoint("TOPRIGHT",    m, "TOPRIGHT",    -stroke - 2, -(stroke + titleH) - 2)
        m.bar:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -stroke - 2,  stroke + 2)
        m.bar:SetWidth(MENU_BAR_W)
        m.bar:Show()
        MenuPaintBar(m)
        MenuUpdateThumb(m)
    else
        m.bpRange = 0
        m.bar:Hide()
    end

    m:SetSize(widest, stroke + titleH + viewportH + stroke)

    -- ── Placement ──
    --
    -- `grow` is the direction the menu opens FROM the anchor and `align`
    -- how it lines up on the other axis, so a footer button at the bottom
    -- of a panel can say "up" outright rather than relying on the library
    -- noticing there is no room below. "auto" is that noticing, and stays
    -- the default.
    local grow  = MenuOpt(app, opts, "grow")
    local align = MenuOpt(app, opts, "align")
    local off   = MenuOpt(app, opts, "offset")
    if grow == "auto" then
        local below = owner:GetBottom() or 9999   -- unknown: assume room
        grow = (below - m:GetHeight() < 0) and "up" or "down"
    end
    m:ClearAllPoints()
    if grow == "left" or grow == "right" then
        local pre = (align == "end" and "BOTTOM") or (align == "center" and "") or "TOP"
        if grow == "left" then
            m:SetPoint(pre .. "RIGHT", owner, pre .. "LEFT", -off, 0)
        else
            m:SetPoint(pre .. "LEFT",  owner, pre .. "RIGHT", off, 0)
        end
    else
        local suf = (align == "end" and "RIGHT") or (align == "center" and "") or "LEFT"
        if grow == "up" then
            m:SetPoint("BOTTOM" .. suf, owner, "TOP" .. suf, 0, off)
        else
            m:SetPoint("TOP" .. suf, owner, "BOTTOM" .. suf, 0, -off)
        end
    end
    m:Show()

    local cat = EnsureCatcher()
    cat:SetScript("OnClick", CloseDropdown)
    cat:Show()
    m:SetFrameLevel(cat:GetFrameLevel() + 10)

    openMenu = m
    -- The anchor lights up while its menu is open, and its chevron turns.
    -- Both are optional: a navigator's button has them, and so does the
    -- control, but the service does not require either.
    owner.bpActive = true
    ns.PaintBorder(owner, "active")
    if owner.arrow then owner.arrow:SetRotation(ARROW_OPEN) end
end

function ns.ShowMenu(owner, app, items, opts)
    -- Clicking the anchor of the open menu closes it. That is what makes
    -- the anchor a toggle rather than a thing that reopens what is there.
    if ns.MenuIsOpenFor(owner) then CloseDropdown(); return end
    CloseDropdown()
    return BuildMenu(owner, app, items, opts)
end

-- Rebuild the open menu against its anchor's CURRENT geometry -- size,
-- scale and placement -- without closing it. Called after a reflow: a
-- scale change moves and rescales the panel, the footer cell the menu
-- hangs from moves with it, and a menu left where it was opened stands
-- beside the panel at the old size. An owner that is gone takes the menu
-- with it.
function ns.ReanchorMenu()
    local m = openMenu
    if not m then return end
    local owner = m.owner
    if not (owner and owner.IsVisible and owner:IsVisible() and m.bpApp) then
        CloseDropdown()
        return
    end
    BuildMenu(owner, m.bpApp, m.bpItems or {}, m.bpOpts)
end

local function OpenDropdown(w, node, ctx)
    local cur   = ns.GetValue(node, ctx)
    local list  = OptionList(node)
    local items = {}
    for i = 1, #list do
        local value, text, desc = OptionAt(node, i)
        -- The option's own table, for the keys a menu ITEM carries through
        -- rather than re-derives. A media option previews itself -- `font`
        -- draws the row in that face, `texture` draws it behind the name --
        -- and this loop builds a fresh item table, so anything it does not
        -- copy is dropped on the way to the menu. That is exactly what
        -- happened: the pages passed the paths, the control read the value
        -- and the text, and the previews never left this function.
        local opt = list[i]
        if type(opt) ~= "table" then opt = nil end
        items[i] = {
            text     = text,
            font     = opt and opt.font or nil,
            texture  = opt and opt.texture or nil,
            selected = (value == cur),
            -- Wrapped rather than resolved: an option description may be a
            -- function of the current state, and resolving it here would
            -- freeze it at the moment the menu was built.
            desc     = desc and function() return OptionDesc(desc, node, ctx) end or nil,
            onPick   = function()
                -- COMMIT FIRST, then write our own label from what is now
                -- stored -- so the control is correct even if nothing else
                -- is bound to this setting, and even where the effect is
                -- deferred.
                --
                -- It used to write the value QUIETLY first and commit
                -- after, which cost the undo point: Commit records "what
                -- this was before" by READING the setting, and by then the
                -- quiet write had already made it the new value. Undo
                -- restored the value it was undoing.
                ns.Commit(node, ctx, value)
                -- The whole control, not only its text: a media option
                -- previews itself on the closed control too, and the face
                -- or the bar has to change with the name. `dropdown` is
                -- declared above this function and its refresh is assigned
                -- below -- resolved when the row is clicked, by which point
                -- both are long since loaded.
                dropdown.refresh(w, node, ctx)
            end,
        }
    end
    ns.ShowMenu(w, ctx.app, items, node.maxItems and { maxItems = node.maxItems } or nil)
end

function dropdown.create(app, parent)
    local w = CreateFrame("Button", nil, parent)
    w:SetHeight(ROW_H)
    w.border, w.bg = ns.BorderedRound(w, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(w, w.border)

    w.arrow = w:CreateTexture(nil, "ARTWORK")
    w.arrow:SetTexture(MEDIA .. "chevron.tga")
    -- 11, not 9: the chevron is the one glyph the panel draws at a size of
    -- its own rather than a font's, and at 9 it read as a speck beside the
    -- text it belongs to. Every chevron in the panel is this size -- the
    -- dropdown's, the menu anchor's, the rail's disclosure and the card
    -- caret -- so they cannot drift apart.
    w.arrow:SetSize(11, 11)
    w.arrow:SetPoint("RIGHT", w, "RIGHT", -8, 0)
    -- chevron.tga points right; a quarter turn clockwise points it down.
    w.arrow:SetRotation(ARROW_CLOSED)

    -- The chosen option's own preview, on the control itself: a font
    -- picker that previews only inside its menu makes you open the menu to
    -- see what you already picked.
    w.preview = w:CreateTexture(nil, "BORDER")
    w.preview:SetPoint("LEFT",  w, "LEFT",   4, 0)
    w.preview:SetPoint("RIGHT", w, "RIGHT", -18, 0)
    w.preview:Hide()

    w.text = ns.FS(w, "OVERLAY", "GameFontNormalSmall")
    w.text:SetPoint("LEFT",  w, "LEFT",  8, 0)
    w.text:SetPoint("RIGHT", w, "RIGHT", -22, 0)
    w.text:SetJustifyH("LEFT")
    w.text:SetWordWrap(false)
    return w
end

-- The option table currently selected, or nil -- for a list of bare
-- strings, or a value that is no longer in the list, there is nothing to
-- preview and nothing to look up.
local function SelectedOption(node, ctx)
    local cur = ns.GetValue(node, ctx)
    local list = OptionList(node)
    for i = 1, #list do
        local opt = list[i]
        if type(opt) == "table" and opt.value == cur then return opt end
    end
    return nil
end

function dropdown.apply(w, node, ctx)
    ns.InstallHover(w, w, node, ctx)
    w:SetScript("OnClick", function()
        if ns.IsDisabled(node, ctx) then return end
        OpenDropdown(w, node, ctx)
    end)
end

function dropdown.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    w.text:SetText(DisplayText(node, ctx))
    w.text:SetTextColor(C(skin.text, 1, a))

    -- The same preview the menu rows draw, for the option that won.
    local sel = SelectedOption(node, ctx)
    -- The face to draw a plain option in, and to fall back to when a
    -- previewed one will not load. Read now, not cached at birth: the panel
    -- can be re-pointed at another font while this control exists.
    local f   = { ns.BaseFont(w.text) }
    if sel and sel.font then
        local ok = pcall(w.text.SetFont, w.text, sel.font, f[2] or 12, f[3])
        if not ok then w.text:SetFont(f[1], f[2] or 12, f[3]) end
    else
        w.text:SetFont(f[1], f[2] or 12, f[3])
    end
    if sel and sel.texture then
        w.preview:SetHeight(math.max(10, ROW_H - 8))
        w.preview:SetTexture(sel.texture)
        -- Half strength on the CONTROL, full strength in the menu -- the
        -- same split the picker this copies uses. Here the bar sits behind
        -- a name being read rather than a texture being judged, and the
        -- judging happens in the menu.
        w.preview:SetVertexColor(1, 1, 1, off and 0.2 or 0.5)
        w.preview:Show()
    else
        w.preview:Hide()
    end

    w.bg:SetVertexColor(C(skin.controlBg, 1, a))
    w.arrow:SetVertexColor(C(skin.textMuted, 1, a))
    ns.MarkBorder(w, skin, skin.controlBorder, a)
    w:SetEnabled(not off)
    if off and ns.MenuIsOpenFor(w) then CloseDropdown() end
end

-- 140 preferred, 100 minimum. It was 200/130, which is a text INPUT's
-- width -- a dropdown shows one chosen option, not a sentence somebody is
-- typing, and at 200 a row of two filled the page while saying very little.
-- A field that genuinely needs more asks: `width = 200`.
function dropdown.measure() return ns.CONTROL_W, 100, ROW_H end
dropdown.stretch = true

-- ── multiselect ────────────────────────────────────────────────
--
-- Several independent switches behind one control: the panel's Addon
-- Options menu, as a field.
--
-- A dropdown picks ONE of a list and shows which; this picks any number of
-- them and shows none -- the menu is the display, and a card of six toggles
-- becomes one row that opens to six. Built on the same menu ns.ShowMenu
-- draws for Addon Options, with the same `kind = "toggle"` rows, so the two
-- behave identically: a row repaints in place when it is flipped and the
-- menu stays up.
--
-- The field supplies `items` -- a table or a function -- in exactly the
-- shape that menu takes ({ kind = "toggle", text, desc, selected, onPick }),
-- which is why this control has no `bind`, no `get` and no `set` of its own:
-- every row owns its setting, as the Addon Options rows own theirs.
local multiselect = {}

function multiselect.create(app, parent)
    return dropdown.create(app, parent)
end

local function MultiItems(node, ctx)
    local items = node.items
    if type(items) == "function" then items = items(ctx and ctx.app, node, ctx) end
    return items
end

function multiselect.apply(w, node, ctx)
    ns.InstallHover(w, w, node, ctx)
    w:SetScript("OnClick", function(self)
        if ns.IsDisabled(node, ctx) then return end
        local items = MultiItems(node, ctx)
        if not (items and #items > 0) then return end

        -- The field's own `onChange`, after whichever row was picked.
        --
        -- A menu row is built by the page and knows nothing about the panel
        -- -- it has no ctx, so it cannot refresh a page or invalidate a
        -- route on its own. Wrapping here gives the field one hook that runs
        -- after any of its rows, with the ctx the field was rendered in.
        -- The items are rebuilt on every open, so the wrapper cannot stack.
        if node.onChange then
            for i = 1, #items do
                local it   = items[i]
                local pick = it.onPick
                if pick then
                    it.onPick = function(...)
                        pick(...)
                        node.onChange(node, ctx)
                    end
                end
            end
        end
        local style = {}
        for k, v in pairs(node.menuStyle or {}) do style[k] = v end
        -- Down out of the control, like a dropdown's list -- the Addon
        -- Options button grows UP because it sits at the panel's bottom
        -- edge, which a field never does.
        if style.grow == nil then style.grow = "down" end
        ns.ShowMenu(self, ctx.app, items, style)
    end)
end

function multiselect.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    -- `text` is the control's own caption, fixed: what is ON is in the menu,
    -- and a summary here would be a second place for the same truth to be
    -- wrong in.
    w.text:SetText(node.text or "")
    w.text:SetTextColor(C(skin.text, 1, a))
    w.bg:SetVertexColor(C(skin.controlBg, 1, a))
    w.arrow:SetVertexColor(C(skin.textMuted, 1, a))
    ns.MarkBorder(w, skin, skin.controlBorder, a)
    w:SetEnabled(not off)
end

function multiselect.measure() return ns.CONTROL_W, 100, ROW_H end
multiselect.stretch = true

-- ── segmented ──────────────────────────────────────────────────
-- Two to five exclusive values, all visible. Its intrinsic width is the
-- sum of its labels, which the grid reads via measure() -- so a wide one
-- claims two columns instead of compressing.

local segmented = {}
local SEG_RADIUS = 6     -- an authored radius; 8 read as a lozenge, not a bar
-- The segments sit 2px inside the body, whose own surface starts 1px in
-- behind its stroke -- so a segment's fill is 1px inside that surface, and
-- the radius that stays concentric with it is the surface's (6 - 1) less
-- that pixel. 4 is an authored radius, which is why it is drawn rather than
-- squashed.
local SEG_INSET      = 2
local SEG_SEL_RADIUS = 4

-- A segment's hover and selected fills, rounded to follow the body.
--
-- They were plain SetAllPoints color textures, and a square fill inside a
-- rounded box squares off the two end segments: the lit segment's corners
-- crossed the body's arc, which is the one place the control stopped
-- looking like one object. ns.RoundedFill paints a COLOR rather than
-- handing back a texture, so this wraps it in the small part of a texture's
-- interface the segment uses -- SetColorTexture, Show, Hide, SetShown --
-- and hiding is painting it fully transparent. `SetSides` is live because
-- which segment is first and last changes with the option list.
local function SegShape(b, layer)
    local paint, _, _, setSides =
        ns.RoundedFill(b, layer, SEG_SEL_RADIUS, "LR", { 0, 0, 0, 0 }, 0)
    local o = ns.ShapeTexture(paint, setSides)
    o:Hide()
    return o
end

function segmented.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetHeight(ROW_H)
    -- Same border treatment as the slider's value box: a filled rounded rect
    -- tinted as the border with the body inset 1px on top of it. The old
    -- OVERLAY ring drew a soft outline over the segments and read badly.
    w.ring, w.bg = ns.BorderedRound(w, SEG_RADIUS, "BACKGROUND", "BORDER")
    ns.SetBorder(w, w.ring)
    w.buttons  = {}
    w.dividers = {}
    return w
end

-- Position the segments. This is deliberately NOT part of refresh.
--
-- refresh runs on every click, and it used to re-anchor and re-size every
-- button each time -- so any moment where the control's width was not yet
-- settled put all the labels at the wrong x, overlapping each other. Layout
-- now happens exactly when it can change: when the option list is applied,
-- and when the control is resized.
local function LayoutSegments(w)
    local n = w.count or 0
    if n == 0 or w:GetWidth() <= 0 then return end
    -- Segments sit 2px in, inside the body's own stroke.
    local inset = SEG_INSET
    local each  = (w:GetWidth() - inset * 2) / n
    local h     = w:GetHeight() - inset * 2

    for i = 1, n do
        local b = w.buttons[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", w, "TOPLEFT", inset + (i - 1) * each, -inset)
        b:SetSize(each, h)
        -- Which corners a segment rounds is its POSITION, and position is
        -- decided here: the first keeps its left corners, the last its
        -- right, everything between is square on both sides so neighbors
        -- meet flush across the divider. A control with one option rounds
        -- all four. `sides` names the corners to SQUARE.
        local sides = (n == 1) and ""
                   or (i == 1) and "R"
                   or (i == n) and "L"
                   or "LR"
        if b.hl  then b.hl:SetSides(sides)  end
        if b.sel then b.sel:SetSides(sides) end
    end
    for i = 1, n - 1 do
        local d = w.dividers[i]
        if not d then
            d = w:CreateTexture(nil, "OVERLAY")
            d:SetWidth(1)
            w.dividers[i] = d
        end
        d:ClearAllPoints()
        d:SetPoint("TOP",    w, "TOPLEFT",    inset + i * each, -inset)
        d:SetPoint("BOTTOM", w, "BOTTOMLEFT", inset + i * each,  inset)
        d:Show()
    end
    for i = n, #w.dividers do
        if w.dividers[i] then w.dividers[i]:Hide() end
    end
end

-- Debug aid for the label-position bug: /bpd segdiag dumps what the control
-- actually thinks its geometry is, including the pooled buttons that should
-- be hidden.
function ns.DumpSegmented(w)
    print(("|cff11ace9segdiag|r w=%.1f h=%.1f count=%s buttons=%d")
        :format(w:GetWidth(), w:GetHeight(), tostring(w.count), #w.buttons))
    local wl = w:GetLeft()
    for i = 1, #w.buttons do
        local b = w.buttons[i]
        local bl = b:GetLeft()
        print(("  [%d] shown=%s text=%q x=%.1f w=%.1f value=%s")
            :format(i, tostring(b:IsShown()), b.text:GetText() or "",
                    (bl and wl) and (bl - wl) or -1,
                    b:GetWidth() or -1, tostring(b.value)))
    end
end

-- Does an option that has no `desc` of its own show the FIELD's?
--
--   "own"      no. The option is silent unless it describes itself.
--   "inherit"  yes, which is what hovering any part of a control has
--              always done.
--
-- The default is decided by the field rather than fixed, because the two
-- cases want opposite things. A field whose options say nothing is one
-- object as far as the reader is concerned, and hovering any part of it
-- should explain it. But the moment ONE option carries its own text, the
-- others are silent by contrast on purpose -- repeating the field's
-- sentence on them would bury the option that actually had something to
-- say. So: no option descriptions anywhere means inherit; any option
-- description at all means own. `optionDesc` overrides either way.
--
-- Dropdown menu rows never inherit, whatever the mode. A row sits in a
-- column with four others, and the same sentence repeated down all five is
-- noise rather than help; a segment is part of a control the reader is
-- already pointing at.
local function OptionDescMode(node)
    if node.optionDesc then return node.optionDesc end
    for _, o in ipairs(OptionList(node)) do
        if type(o) == "table" and (o.desc or o.tooltip) then return "own" end
    end
    return "inherit"
end

function segmented.apply(w, node, ctx)
    for _, b in ipairs(w.buttons) do b:Hide() end
    local opts = OptionList(node)
    local mode = OptionDescMode(node)
    for i, opt in ipairs(opts) do
        local b = w.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, w)
            -- A Button offsets its regions in the pushed state. Ours must
            -- not move a pixel when clicked.
            if b.SetPushedTextOffset then b:SetPushedTextOffset(0, 0) end
            b.hl = SegShape(b, "BACKGROUND")
            b.hl:Hide()
            -- The selected state fills the WHOLE segment, flat. The earlier
            -- version drew a rounded pill inset inside each segment, which
            -- read as a little floating button sitting in a box rather than
            -- as one segmented control with a lit segment. It is still the
            -- whole segment: only the two ENDS are rounded, to the body's
            -- own curve, so the fill stops where the box does.
            b.sel = SegShape(b, "ARTWORK")
            b.text = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
            b.text:SetPoint("CENTER")
            b:SetScript("OnClick", function(self)
                if ns.IsDisabled(self.bpNode, self.bpCtx) then return end
                ns.Commit(self.bpNode, self.bpCtx, self.value)
            end)
            b:SetScript("OnEnter", function(self)
                if ns.IsDisabled(self.bpNode, self.bpCtx) then return end
                self.hl:Show()
                local d = OptionDesc(self.bpDesc, self.bpNode, self.bpCtx)
                if d then ns.context.Show(self, self.bpCtx.app, self.bpText, d) end
            end)
            b:SetScript("OnLeave", function(self)
                self.hl:Hide()
                if self.bpDesc then ns.context.Hide() end
            end)
            w.buttons[i] = b
        end
        local value = (type(opt) == "table") and opt.value or opt
        local text  = (type(opt) == "table") and opt.text  or tostring(opt)
        local icon  = (type(opt) == "table") and opt.icon  or nil
        b.value = value

        -- An option may be an ICON rather than a word. A bare name is one
        -- of the panel's own files; anything with a path separator is the
        -- consuming addon's own art, so an addon can supply icons without
        -- adding files to this library.
        if icon then
            if not b.icon then
                b.icon = b:CreateTexture(nil, "OVERLAY")
                b.icon:SetPoint("CENTER")
            end
            local art = ns.IconVariant(icon, ctx and ctx.app)
            b.icon:SetTexture(art:find("[\\/]") and art
                              or (MEDIA .. art .. ".tga"))
            b.icon:SetSize(node.iconSize or 15, node.iconSize or 15)
            b.icon:Show()
            b.text:Hide()
            -- Kept, so a tooltip or a screen reader still has the word.
            b.text:SetText(text)
        else
            if b.icon then b.icon:Hide() end
            b.text:SetText(text)
            b.text:Show()
        end
        b:Show()

        -- Per-option state, read by the scripts installed at creation.
        --
        -- The scripts used to be re-installed on every apply, closing over
        -- that render's node and ctx. That quietly broke tooltips: the
        -- field tooltip is attached by HOOKING OnEnter, and a later
        -- SetScript replaces the hook along with the handler, while the
        -- once-only guard stopped it being re-hooked. So the segments read
        -- their state from themselves and their handlers are installed once.
        b.bpNode, b.bpCtx, b.bpText = node, ctx, text
        b.bpDesc = (type(opt) == "table") and (opt.desc or opt.tooltip) or nil
        -- bpTipOwn makes the field tooltip's walk over this subtree step
        -- past the segment. Set it when the option speaks for itself, and
        -- under "own" when it deliberately says nothing. Cleared, not just
        -- set, because these buttons are reused for other fields and a
        -- stale claim would block the field's text from ever arriving.
        b.bpTipOwn = (mode == "own" or b.bpDesc) and true or nil
    end
    w.count = #opts
    w.bpNode, w.bpCtx = node, ctx
    LayoutSegments(w)
    -- Re-layout on resize only. OnSizeChanged is scrubbed when the widget
    -- goes back to the pool, so it is installed here rather than at create.
    w:SetScript("OnSizeChanged", function(self) LayoutSegments(self) end)
end

function segmented.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local cur  = ns.GetValue(node, ctx)
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1

    w.bg:SetVertexColor(C(skin.controlBg, 1, a))
    ns.MarkBorder(w, skin, skin.controlBorder, a)

    local n = w.count or 0
    if n == 0 then return end

    -- Color only. Geometry belongs to LayoutSegments.
    for i = 1, n do
        local b = w.buttons[i]
        local on = (b.value == cur)
        local hd = skin.accentDim
        b.hl:SetColorTexture(hd[1], hd[2], hd[3], (hd[4] or 0.18) * 0.55 * a)
        -- Icons take the label's color, so selected/unselected reads the
        -- same whichever form an option is in.
        -- The selected segment's label is the plain TEXT color at full
        -- strength (owner, 2026-09-14: not the accent-lifted light blue the
        -- mockup drew it in); the tinted well under it is what says
        -- selected. Unselected labels sit at 72% of it, as before.
        if b.icon and b.icon:IsShown() then
            if on then
                b.icon:SetVertexColor(C(skin.text, 1, a))
            else
                b.icon:SetVertexColor(C(skin.text, 0.72, a))
            end
        end
        b.sel:SetShown(on)
        if on then
            -- accentDim is the mockup's rgba(accent, .18): a tint, not a slab.
            local d = skin.accentDim
            b.sel:SetColorTexture(d[1], d[2], d[3], (d[4] or 0.18) * a)
            b.text:SetTextColor(C(skin.text, 1, a))
        else
            b.text:SetTextColor(C(skin.text, 0.72, a))
        end
        b:SetEnabled(not off)
    end

    -- Hairline between segments, matching the border.
    for i = 1, n - 1 do
        local d = w.dividers[i]
        if d then
            d:SetColorTexture(C(skin.controlBorder, 1, a))
            if ns.NoSnap then ns.NoSnap(d) end
        end
    end
end

-- Intrinsic width is the sum of the option labels. A segmented control
-- cannot shrink below that without shaving a button, so minimum == preferred.
function segmented.measure(node)
    local n, chars, icons = 0, 0, 0
    for _, opt in ipairs(OptionList(node)) do
        n = n + 1
        if type(opt) == "table" and opt.icon then
            -- An icon is a fixed square: it does not care how long the
            -- word behind it is.
            icons = icons + 1
        else
            chars = chars + #tostring((type(opt) == "table") and opt.text or opt)
        end
    end
    local wide = 16 + chars * 6.6 + (n - icons) * 14
                    + icons * ((node.iconSize or 15) + 16)
    return wide, wide, ROW_H
end
segmented.stretch = false

-- ── color swatch ──────────────────────────────────────────────

local color = {}
function color.create(app, parent)
    local w = CreateFrame("Button", nil, parent)
    w:SetHeight(ROW_H)
    -- Border, then the transparency backing, then the color itself.
    --
    -- A previous version had no backing at all: the color's alpha was
    -- blended against controlBg in Lua and the fill drawn opaque. That is
    -- pixel-identical for the COLOR, but it throws away the only thing
    -- that distinguishes transparent from dark -- controlBg is nearly
    -- black, so alpha 0 and opaque black rendered the same swatch. The
    -- backing has to be patterned, not flat, or there is no cue at all.
    --
    -- The backing takes the FILL'S OWN SILHOUETTE, corners included, by
    -- wearing a nine-sliced rounded MASK -- not by being inset into a
    -- square that fits inside the curve.
    --
    -- A mask is the right tool and a proven one here: Buzzard Auras masks
    -- its rounded bar bodies exactly this way, nine-sliced, and the split it
    -- records is the one that matters -- SLICED masks for bar-shaped regions
    -- whose width varies, STRETCHED for squares. A swatch is a bar body: it
    -- is wide, short, and re-packed to whatever the row leaves it, so a
    -- stretched mask would pull its corners into ellipses while the fill
    -- above kept true arcs.
    --
    -- The earlier flat backing failed for a reason worth keeping in view: at
    -- the fill's own inset its antialiased edge composited with the fill's
    -- and gave a dark halo. That is the ns.RoundedFill problem above, and it
    -- has not gone away -- it has been priced. Backing and fill are now
    -- exactly coincident, so at MID alpha ~1px of rim composites twice and
    -- reads marginally stronger. At alpha 1 the fill is opaque and at alpha
    -- 0 it contributes nothing, so the artifact exists only between, only on
    -- the antialiased edge, and only against the ring it sits on. A square
    -- backing visibly inside a rounded control costs more than that.
    --
    -- Sublevels, not layers: the ring owns BACKGROUND/0 and the fill sits
    -- on BORDER, so the two backing textures go at BACKGROUND/1 and /2 to
    -- land between them without a third draw layer.
    w.ring, w.fill = ns.BorderedRound(w, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(w, w.ring)

    -- A light base for the pattern to sit on, so a fully transparent swatch
    -- reads as empty rather than as another dark control.
    -- The mask, if this client has them. Everything below adapts to whether
    -- it exists: a missing mask is not an error, it is the older look.
    local mask
    if w.CreateMaskTexture then
        mask = w:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "round8.tga")
        if mask.SetTextureSliceMargins then
            mask:SetTextureSliceMargins(8, 8, 8, 8)
            if mask.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
                mask:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
            end
        end
        -- A mask that loads asynchronously applies LATE, and a late mask is
        -- a wrong mask -- the region draws unmasked for a frame or keeps a
        -- stale shape. Blocking the load is what Buzzard Auras does on every
        -- one of its masks, for the same reason.
        if mask.SetBlockingLoadsRequested then mask:SetBlockingLoadsRequested(true) end
        w.checkerMask = mask
    end

    -- Where the backing sits. With a mask it is coincident with the fill, so
    -- the pattern reaches the corners. Without one it falls back to the
    -- square that fits INSIDE the curve: inset 3px from the fill, which at
    -- radius 8 clears the corner's ~1.8px pull-in with room to spare.
    local inset = mask and 1 or 4

    w.alphaBase = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.alphaBase:SetColorTexture(1, 1, 1, 1)
    w.alphaBase:SetPoint("TOPLEFT",     w, "TOPLEFT",      inset, -inset)
    w.alphaBase:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -inset,  inset)
    w.alphaBase:Hide()
    if mask then w.alphaBase:AddMaskTexture(mask) end

    -- The pattern itself, TILED rather than stretched.
    --
    -- A swatch is wide and short, and its width changes with the row, so a
    -- texture stretched across it turns square checks into rectangles that
    -- get wider the more room the field has. Tiling fixes the square size in
    -- texels and lets the COUNT vary instead, which is the way round that
    -- survives any width.
    --
    -- Two things make that legal. The source is our own 8x8 file, so it is
    -- power-of-two and REPEAT wrap is valid -- a non-power-of-two texture
    -- silently refuses to wrap. And it draws only ALTERNATE squares, in
    -- alpha, so the base above shows through as the other tone: one texture
    -- carries one tint, and a checkerboard needs two.
    w.checkers = w:CreateTexture(nil, "BACKGROUND", nil, 2)
    w.checkers:SetTexture(MEDIA .. "checker.tga", "REPEAT", "REPEAT")
    -- Guarded because a call to a method that is not there is an ERROR, not
    -- a no-op, and it would take the whole page down with it. The wrap mode
    -- passed to SetTexture above is what actually enables repeating; these
    -- two are belt and braces on clients that want them set explicitly.
    if w.checkers.SetHorizTile then w.checkers:SetHorizTile(true) end
    if w.checkers.SetVertTile  then w.checkers:SetVertTile(true)  end
    w.checkers:SetAllPoints(w.alphaBase)
    w.checkers:Hide()
    if mask then
        -- The mask covers the same rect as the things it masks. Anchored to
        -- alphaBase rather than to w, so one anchor decides the geometry and
        -- the mask cannot drift out of step with the pair it clips.
        mask:SetAllPoints(w.alphaBase)
        w.checkers:AddMaskTexture(mask)
    end

    -- How many tiles fit, recomputed whenever the row re-packs. TexCoord
    -- beyond 0-1 is what repeats under REPEAT wrap, so the pitch stays a
    -- fixed number of texels and only the count changes.
    local function TileCheckers()
        local cw = math.max(1, w.alphaBase:GetWidth()  or 1)
        local ch = math.max(1, w.alphaBase:GetHeight() or 1)
        w.checkers:SetTexCoord(0, cw / CHECKER_TILE, 0, ch / CHECKER_TILE)
    end
    w.bpTileCheckers = TileCheckers
    -- The swatch's own size drives it: alphaBase is anchored to w, so it has
    -- no size of its own to change until w does.
    w:HookScript("OnSizeChanged", TileCheckers)

    return w
end
function color.apply(w, node, ctx)
    ns.InstallHover(w, w, node, ctx)
    w:SetScript("OnClick", function()
        if ns.IsDisabled(node, ctx) then return end
        local c = ns.GetValue(node, ctx) or { 1, 1, 1, 1 }
        -- The value AS THE PICKER OPENS, copied out by component: this is
        -- what Cancel puts back. Copied, because the table GetValue hands
        -- over can be the stored one, and a setter that edits in place
        -- would have moved it under us by the time Cancel is pressed.
        local r0, g0, b0, a0 = c[1], c[2], c[3], c[4] or 1
        -- ONLY WHILE THE PICKER IS ON SCREEN -- the classic color widget's
        -- own rule, and the one that has always kept it right. The client
        -- keeps calling the swatch and opacity callbacks after the picker
        -- closes, and what it reports then is not the reader's choice: on
        -- Cancel it is the wheel being reset, which a session still
        -- listening committed as white at full alpha on top of the value
        -- Cancel had just put back. While the picker is up every tick is
        -- committed live, so nothing said after it closes is news. Cancel
        -- ends the session outright as well, whatever order the client
        -- fires its callbacks in, and a session superseded by a later open
        -- of the same picker is ignored too.
        local live = true
        local function onChange()
            if not live or not ColorPickerFrame:IsVisible() then return end
            local current = ColorPickerFrame.swatchFunc
            if current ~= nil and current ~= onChange then return end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local alpha = node.alpha and ColorPickerFrame:GetColorAlpha() or 1
            ns.Commit(node, ctx, { r, g, b, alpha })
        end
        -- The modern one-call setup (10.2.5+). Everything the panel needs
        -- is native here; only the swatch is ours.
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0, opacity = a0,
            hasOpacity = node.alpha and true or false,
            swatchFunc = onChange, opacityFunc = onChange,
            -- Through the funnel too: cancelling has to put the addon's
            -- own state back, not just the swatch's. From OUR copy, not
            -- the table the picker passes: the shape of that table is
            -- the client's (it has carried `a` rather than `opacity`),
            -- and reading it by the wrong keys canceled every color to
            -- white at full alpha.
            cancelFunc = function()
                live = false
                ns.Commit(node, ctx, { r0, g0, b0, a0 })
            end,
        })
    end)
end
function color.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local c    = ns.GetValue(node, ctx) or { 1, 1, 1, 1 }
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    ns.MarkBorder(w, skin, skin.controlBorder, a)

    -- Only a swatch that can HOLD alpha shows the pattern. Everything else
    -- keeps the original two-texture rendering: a stored value with a stray
    -- alpha on a node that never offered opacity is a profile artifact, not
    -- something to advertise.
    local hasAlpha = node.alpha and true or false
    local sa = hasAlpha and (c[4] or 1) or 1

    if hasAlpha then
        -- The fill carries its real alpha now, so the pattern beneath shows
        -- through in proportion. Disabled dims the whole stack together --
        -- the backing fades toward the panel the same way the fill does, or
        -- a disabled transparent swatch would still glare white.
        w.alphaBase:Show()
        w.checkers:Show()
        local back = skin.panelBg
        w.alphaBase:SetVertexColor(ns.Faded({ 0.82, 0.82, 0.82, 1 }, back, off))
        -- The drawn squares are the DARKER half; the base is the lighter.
        w.checkers:SetVertexColor(ns.Faded({ 0.62, 0.62, 0.62, 1 }, back, off))
        w.checkers:SetAlpha(1)
        -- Retile here too. refresh runs after the layout has sized the row,
        -- so on a first render this is the call that has real numbers to
        -- work with -- OnSizeChanged alone can fire before the width is set.
        if w.bpTileCheckers then w.bpTileCheckers() end
        w.fill:SetVertexColor(c[1], c[2], c[3], sa * a)
    else
        w.alphaBase:Hide()
        w.checkers:Hide()
        w.fill:SetVertexColor(c[1], c[2], c[3], a)
    end

    w:SetEnabled(not off)
end
function color.measure() return 90, 70, ROW_H end
color.stretch = false

-- Continuous for the same reason, though the drag is not ours to see: the
-- picker's wheel calls swatchFunc on every tick while it is dragged.
color.defaultTier = "debounce"

-- ── text input ─────────────────────────────────────────────────

-- Two shapes of the same control.
--
--   { control = "text" }                    Enter commits. No button, ever.
--   { control = "text", search = true }     A magnifier inside the box's
--                                           left edge, the one the client's
--                                           own search boxes wear, and no
--                                           button whatever `submit` says.
--                                           Enter commits.
--   { control = "text", submit = "Add" }    Plus a button inside the box's
--                                           right edge, ALWAYS there and
--                                           grayed out until the field
--                                           differs from the stored value
--                                           -- and Enter still commits.
--
-- The button used to appear only once the field was dirty (owner,
-- 2026-09-14: a field whose whole point is the button -- Add Spell Name or
-- ID -- reads better with the button always in view, and its caption
-- should say what it does: "Add", "Rename", "Create", not "Okay").
local TEXT_PAD    = 7      -- the box's own text inset
local SUBMIT_GAP  = 4      -- between the text and the button
local CLEAR_W     = 14     -- the X, when `clear` asks for one
-- `search = true`: the magnifier the client's SearchBoxTemplate wears,
-- at the box's left, and the text inset that clears it.
local SEARCH_ICON   = "Interface\\Common\\UI-Searchbox-Icon"
-- 2026-09-14: the ATLAS the client's SearchBoxTemplate draws its own
-- magnifier from -- the panel's top search box wears that template, and
-- the file texture above (a 16px legacy sheet) came out soft beside it.
-- The atlas is preferred and the file is the fallback for a client that
-- does not have it.
local SEARCH_ATLAS  = "common-search-magnifyingglass"
local SEARCH_ICON_W = 14
local SEARCH_INSET  = 5 + SEARCH_ICON_W + 4

-- ── The third shape: a box with rows ───────────────────────────
--
--   { control = "text", multiline = 10 }   ten visible rows, wrapping,
--                                          scrolling, the whole row wide
--
-- Everything else about the field is unchanged, deliberately. Enter
-- COMMITS here as it does on a one-line box, which is not what a text
-- editor would do -- a multi-line box is usually where Enter means a
-- newline. This one is not an editor: what gets pasted into it is one
-- long string that arrived from somewhere else, and the reader's next
-- move after pasting is to accept it. Escape still reverts, `submit`
-- still draws its button, `clear` still draws its X, and the mouse still
-- selects on a double click. A stray newline typed before the commit
-- costs nothing: committing clears the focus, and refresh re-seeds an
-- unfocused box from the stored value.
local MULTI_LINE_H = 14    -- one line of GameFontHighlightSmall
local MULTI_PAD    = 6     -- inside the border, above and below the text

-- `multiline` is a ROW COUNT. Anything that is not a positive number is
-- not a multi-line field, so a client that wrote `multiline = true` gets
-- the one-line box rather than a box of no height at all.
local function MultiRows(node)
    local r = tonumber(node and node.multiline)
    if not r or r < 1 then return nil end
    return r
end

-- The height of the BOX -- the rows and the padding around them.
local function MultiHeight(node)
    local r = MultiRows(node)
    if not r then return ROW_H end
    return r * MULTI_LINE_H + MULTI_PAD * 2
end

-- The height the field ASKS the layout for and the height the wrapper is
-- SET to, from one function: the two have to agree, or the box draws over
-- whatever the card puts under it. A field with a submit button is one
-- button row taller than its box: the button sits UNDER the box, in a row
-- of its own, the way a multi-line box's Accept button always has -- a
-- button inside a wrapping box sits on top of whatever line the text
-- reached.
local MULTI_BTN_GAP = 4
local function MultiFieldHeight(node)
    local h = MultiHeight(node)
    if node and node.submit then h = h + MULTI_BTN_GAP + ROW_H end
    return h
end

-- Which of the two boxes the field in hand is using.
--
-- A widget is pooled by CONTROL NAME (Page.lua's Acquire("ctl:text")), so
-- the frame that served a ten-row box on one page serves a one-line field
-- on the next. Once it has ever been asked for the multi-line box it keeps
-- it, so the answer is the NODE's, recorded on the widget by apply().
local function Box(w) return (w.multi and w.mbox) or w.box end
-- And which submit button: the in-field one, or the full-height one the
-- multi-line shape draws under its box (EnsureMultiSubmit).
local function Submit(w) return (w.multi and w.msubmit) or w.submit end

-- A painter dressed as a texture. (Declared here, above the text field,
-- because the multi-line box's Accept button is built the way the button
-- control is -- see EnsureMultiSubmit.)
--
-- ns.RoundedFill returns a paint FUNCTION, while SetBorder/PaintBorder --
-- which own every border state in this library -- expect something they can
-- call SetVertexColor on. Rather than teach the border code about a second
-- shape, the shape learns the one method the border code uses. Everything
-- else about hover, focus and the disabled fade then works unchanged.
local function PaintAsTexture(paint)
    return { SetVertexColor = function(_, r, g, b, a) paint({ r, g, b, a }) end }
end

local textinput = {}

local function SubmitLabel(node)
    -- `submit = true` takes the client's own word for it, so the default
    -- is localised without this file carrying a string table.
    if node.submit == true then return OKAY or "Okay" end
    return tostring(node.submit)
end

-- Dirty is measured against the STORED value, not the previous keystroke.
--
-- The obvious implementation keeps a `lasttext` and compares each change to
-- the one before it. That leaves the button showing after you type a
-- character and delete it again: the text is back where it started, but the
-- last two keystrokes differed. Comparing against the setting itself makes
-- "dirty" mean what it says.
local function IsDirty(w, node, ctx)
    local stored = tostring(ns.GetValue(node, ctx) or "")
    return tostring(Box(w):GetText() or "") ~= stored
end

-- Only when it ACTUALLY changes -- tracked here, not asked of the client.
--
-- A post-creation SetTextInsets wipes the caret on a box whose width comes
-- from anchors. This function was already meant to be a no-op when nothing
-- moved, but it guarded on box:GetTextInsets(), and that getter does not
-- return what was set (rounding, or the frame's own scale), so the guard
-- never fired: every apply, every refresh and every keystroke rewrote the
-- insets, and the caret went with them. Remembering the value we applied
-- makes the guard true, which means a field with no submit button never
-- touches its insets again after create().
local function SetInsets(box, right)
    SetBoxInsets(box, TEXT_PAD, right)
end

-- ONE function decides what sits inside the box's right edge, because the
-- two affordances share that space and the text inset has to clear
-- whichever of them is showing. The X is nearest the text and the button is
-- outermost, so a field with both reads left to right as "what you typed,
-- get rid of it, apply it".
local function UpdateSubmit(w, node, ctx)
    local box   = Box(w)
    local right = TEXT_PAD

    -- `w.submit` can be absent even when the node asks for one: the seed
    -- in apply fires OnTextChanged, and on some paths that lands here
    -- before EnsureSubmit has built the button. Nothing to hide if it was
    -- never built, which is the point: a field that never asks for a
    -- button never grows one.
    -- ALWAYS SHOWN, and LIVE only while the field is dirty: a button the
    -- reader can see is a button they know is coming, and one that grays
    -- out again the moment the box matches the store says "nothing to
    -- apply" without taking the affordance away.
    local submit = node.submit and not node.search and Submit(w)
    local dirty  = submit and IsDirty(w, node, ctx) or false
    -- `submitOnDirty` (2026-09-14, owner): the button APPEARS only while
    -- the text differs from the stored value -- a Rename that shows up as
    -- you type -- instead of standing grayed beside an unedited field.
    local showSubmit = submit and ((not node.submitOnDirty) or dirty) or false
    local liveSubmit = showSubmit and dirty
                       and not ns.IsDisabled(node, ctx) or false
    if submit then
        submit:SetShown(showSubmit)
        submit:SetEnabled(liveSubmit)
        submit.bpLive = liveSubmit
        if submit.bpPaint then submit.bpPaint() end
    end
    if showSubmit and not w.multi then
        right = submit:GetWidth() + SUBMIT_GAP + 2
    end

    -- The X shows only while there is something to clear -- an X over an
    -- empty box is a control that does nothing, which is the same reason
    -- the submit button hides on an unedited field.
    local showClear = node.clear and w.clear
                      and (box:GetText() or "") ~= ""
                      and not ns.IsDisabled(node, ctx) or false
    if w.clear then
        w.clear:SetShown(showClear)
        if showClear then
            w.clear:ClearAllPoints()
            if w.multi then
                -- Anchored to the box's FRAME, never to the box: the box
                -- is a scroll child and slides under the reader's thumb,
                -- and an X that scrolled away with the first line would be
                -- an X that works only at the top. It steps over the
                -- scrollbar's gutter rather than sharing it.
                w.clear:SetPoint("TOPRIGHT", w.mhost, "TOPRIGHT",
                                 -TEXT_PAD, -MULTI_PAD)
                -- ABOVE the box, not beside it in level. The X was built
                -- one level over the one-line box, which is the level the
                -- host sits at; the scroll frame and its EditBox stack
                -- higher still, and the first line of text ran right
                -- under the X, so the click went to the box every time.
                w.clear:SetFrameLevel(w.mbox:GetFrameLevel() + 2)
            elseif showSubmit then
                w.clear:SetPoint("RIGHT", w.submit, "LEFT", -SUBMIT_GAP, 0)
            else
                w.clear:SetPoint("RIGHT", w.box, "RIGHT", -4, 0)
            end
            right = right + CLEAR_W + SUBMIT_GAP
        end
    end

    -- The inset follows whatever is showing, so text never runs underneath
    -- it and a field carrying neither has no gap where one might one day be.
    --
    -- One-line only. The multi-line box's affordances sit in the margins
    -- the padding and the scrollbar gutter have already reserved, so
    -- nothing has to move out of their way -- and rewriting a WRAPPING
    -- box's insets re-wraps every line of it, for a button that was never
    -- in the text's path.
    if not w.multi then
        SetBoxInsets(w.box, (node.search and not w.multi)
                            and (w.searchInset or SEARCH_INSET) or TEXT_PAD, right)
    end
end

-- ── The suggestion flyout ──────────────────────────────────────
--
-- `suggest` on a text field: a function the control asks, on every
-- keystroke, for the rows to offer under the box.
--
--     suggest = function(text, max, ctx)
--         return { { value = 774, text = "|T…|t Rejuvenation |cff888888(774)|r",
--                    desc = "…" }, … }
--     end
--
-- A row's `value` is what lands in the box when the row is picked -- a
-- spell ID, where the text beside it is only what the reader sees -- and
-- `text` is used when a row states no value. Returning nothing opens no
-- flyout, which is what an empty box and a query that matched nothing both
-- do; the field is otherwise exactly the field it was, so a client that
-- never passes `suggest` pays for none of this.
--
-- Its OWN frame rather than ns.ShowMenu, which would be the obvious reuse:
-- the menu service puts a full-screen click-catcher behind itself and takes
-- the keyboard to hear Escape, and while somebody is typing both of those
-- belong to the EditBox. This draws the same shape and does nothing else --
-- no catcher, no keyboard, no focus of its own -- so the caret, the typing
-- and Escape all keep working as they do on a plain field.
local SUG_ROW_H, SUG_PAD, SUG_MAX = 20, 4, 12

-- One flyout for the whole library. Only one text field can have focus, so
-- a second frame could never be showing.
local sugFrame

-- Re-stamp the frames that wear the panel's scale but do not hang off the
-- panel frame -- for a scale change that happens while one is up. A Panel
-- Scale moved from the open menu must reach that menu now, not on its
-- next open. Called by ns.RestampPanel.
function ns.RestampFloaters()
    if not ns.StampPanelScale then return end
    if menuFrame and menuFrame:IsShown() then ns.StampPanelScale(menuFrame) end
    if sugFrame  and sugFrame:IsShown()  then ns.StampPanelScale(sugFrame)  end
end

local function SugRow(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f)
    r:SetHeight(SUG_ROW_H)
    -- MOUSE DOWN, not up. Clicking a row takes the focus off the box, and
    -- the focus-lost script is what hides the flyout -- so on a click-up
    -- row the hide and the click race, and the hide wins often enough to
    -- read as "the suggestions do nothing". On mouse down the row has
    -- already been picked before the focus moves.
    r:RegisterForClicks("LeftButtonDown")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints(r)
    r.hl:Hide()
    r.text = ns.FS(r, "OVERLAY", "GameFontNormalSmall")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.text:SetPoint("LEFT",  r, "LEFT",   6, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    f.rows[i] = r
    return r
end

local function EnsureSuggest()
    if sugFrame then return sugFrame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:Hide()
    if ns.StampPanelScale then ns.StampPanelScale(f) end
    -- The menu's two-piece shape: a ring at inset 0 and the surface inset
    -- by the stroke, both with corners sized in physical pixels, so the
    -- flyout's corners match the panel's at any UI scale.
    f.paintRing, f.setRingRadius = ns.RoundedFill(f, "BACKGROUND", 8, nil, { 0, 0, 0, 1 }, 0)
    f.paintBody, f.setBodyRadius, f.setBodyInset =
        ns.RoundedFill(f, "BORDER", 8, nil, { 0, 0, 0, 1 }, 1)
    f.rows = {}
    f.bpIndex = 0
    sugFrame = f
    return f
end

-- Hide it, but only if it belongs to this field: a stale hide from a widget
-- the pool has moved on from must not close the flyout of the box the user
-- is actually typing in.
local function HideSuggest(w)
    if not sugFrame then return end
    if w and sugFrame.bpOwner and sugFrame.bpOwner ~= w then return end
    sugFrame:Hide()
    sugFrame.bpOwner, sugFrame.bpItems, sugFrame.bpCount = nil, nil, 0
    sugFrame.bpIndex = 0
end

-- Is the flyout up for THIS field, with rows in it?
local function SuggestOpen(w)
    return sugFrame and sugFrame:IsShown() and sugFrame.bpOwner == w
           and (sugFrame.bpCount or 0) > 0
end

local function HighlightSuggest(i)
    local f = sugFrame
    if not f then return end
    f.bpIndex = i or 0
    -- Guarded on the ROW, not just the count: the count is what the frame
    -- last said it had, and the rows are built one at a time -- so a walk
    -- driven by the count alone reads past the end of the pool the first
    -- time a longer list is shown than has ever been built.
    for j = 1, (f.bpCount or 0) do
        local r = f.rows[j]
        if r then r.hl:SetShown(j == f.bpIndex) end
    end
end

-- Up and down walk the rows and wrap. Nothing is committed on the way: the
-- highlight says which row Enter would take, exactly as the box's own text
-- says what Enter would take without one.
local function MoveSuggest(w, delta)
    if not SuggestOpen(w) then return false end
    local n = sugFrame.bpCount
    local i = (sugFrame.bpIndex or 0) + delta
    if i < 1 then i = n elseif i > n then i = 1 end
    HighlightSuggest(i)
    return true
end

-- Picking a row is a COMMIT, through the field's own commit path -- see
-- apply(). The value is put in the box first so every route to the setter
-- passes the same thing the box shows.
local function PickSuggest(w, node, ctx, item)
    if not item then return end
    local v = item.value
    if v == nil then v = item.text end
    HideSuggest(w)
    w.box:SetText(tostring(v))
    ns.Commit(node, ctx, w.box:GetText())
    w.box:ClearFocus()
    UpdateSubmit(w, node, ctx)
end

-- Asked on every keystroke. Cheap when there is nothing to show: a field
-- with no `suggest`, a disabled one, or an unfocused one never calls the
-- client at all.
local function UpdateSuggest(w, node, ctx)
    if not node.suggest or ns.IsDisabled(node, ctx) or not w.box:HasFocus() then
        HideSuggest(w)
        return
    end

    local items = node.suggest(tostring(w.box:GetText() or ""), SUG_MAX, ctx)
    local n = (type(items) == "table") and #items or 0
    if n > SUG_MAX then n = SUG_MAX end
    if n == 0 then HideSuggest(w); return end

    local f      = EnsureSuggest()
    local skin   = ctx.app.skin
    local stroke = ns.BorderStroke("card")
    local radius = skin.borderRadius or 8
    f.setBodyInset(stroke)
    f.setRingRadius(radius)
    f.setBodyRadius(radius)
    f.paintRing(skin.controlBorder)
    f.paintBody(skin.controlBg)

    f.bpOwner, f.bpItems = w, items

    local y = SUG_PAD + stroke
    for i = 1, n do
        local r = SugRow(f, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  f, "TOPLEFT",   stroke, -y)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -stroke, -y)
        r.text:SetText(items[i].text or "")
        r.text:SetTextColor(C(skin.text, 1, 1))
        -- The menu's own highlight, alpha included: C() would take the
        -- alpha argument over the token's, and accentDim is a color that
        -- IS its alpha -- at 1 it paints a solid accent bar.
        local hl = skin.accentDim
        r.hl:SetColorTexture(hl[1], hl[2], hl[3], hl[4] or 0.18)
        r.hl:Hide()
        r.bpItem, r.bpW, r.bpNode, r.bpCtx = items[i], w, node, ctx
        r:SetScript("OnEnter", function(self)
            HighlightSuggest(0)
            self.hl:Show()
        end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self)
            PickSuggest(self.bpW, self.bpNode, self.bpCtx, self.bpItem)
        end)
        r:Show()
        y = y + SUG_ROW_H
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end

    -- The count and the highlight are set HERE, after the rows exist:
    -- HighlightSuggest walks bpCount rows, and this is the first moment
    -- there are that many of them.
    --
    -- Reset every time, because the list is rebuilt under the highlight on
    -- every keystroke -- a remembered row number would point at a different
    -- spell than the one the reader was looking at. Typing clears it; the
    -- arrows put it back.
    f.bpCount = n
    HighlightSuggest(0)

    f:SetWidth(math.max(120, w.box:GetWidth() or 120))
    f:SetHeight(y + SUG_PAD + stroke)
    f:ClearAllPoints()
    -- Down from the box, or up from it when the list would run off the
    -- bottom of the screen -- the same flip the menu does.
    if ns.StampPanelScale then ns.StampPanelScale(f) end
    if ((w.box:GetBottom() or 9999) - f:GetHeight()) < 0 then
        f:SetPoint("BOTTOMLEFT", w.box, "TOPLEFT", 0, 2)
    else
        f:SetPoint("TOPLEFT", w.box, "BOTTOMLEFT", 0, -2)
    end
    f:Show()
    -- After Show, which is when the strata is settled: the flyout must draw
    -- over the panel it is anchored into, submit button included.
    f:SetFrameLevel((w.box:GetFrameLevel() or 1) + 20)
end

-- The EditBox is a CHILD of the pooled widget, not the pooled widget itself.
--
-- Worth the extra frame. As the pooled object the EditBox went through
-- Acquire/Release on every render -- hidden, unparented onto the app frame,
-- scripts scrubbed, then re-parented, re-anchored and shown again. A plain
-- Frame takes that cycle instead, and the box inside it is created once and
-- neither hidden nor re-parented for the rest of the session. The pool
-- keeps doing its job: frames are never destroyed in this client, so a page
-- that built a new EditBox per render would grow one forever.
function textinput.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetHeight(ROW_H)

    -- Constructed ONCE and never resized. Both halves matter.
    --
    -- The box takes its width from two HORIZONTAL anchors, which is what
    -- lets it fill the row, but its height is set EXPLICITLY rather than
    -- coming from a second vertical anchor -- and nothing resizes it after
    -- this function returns. That combination is what draws a caret. Every
    -- version of this control that lost its caret either derived the height
    -- from a BOTTOMRIGHT anchor or wrote the box's size again later (from
    -- the wrapper's OnSizeChanged, or with a SetWidth on every apply); the
    -- slider's number box, which never lost its caret, is created at a
    -- fixed size and never touched again. Six side-by-side probes stepping
    -- from that number box's geometry to this one confirmed it: with the
    -- box left alone after creation, every geometry drew a caret, this one
    -- included. So do not add a SetSize, a SetWidth or a BOTTOMRIGHT anchor
    -- here or in apply(), however much tidier it looks.
    w.box = CreateFrame("EditBox", nil, w)
    w.box:SetPoint("TOPLEFT")
    w.box:SetPoint("TOPRIGHT")
    w.box:SetHeight(ROW_H)
    w.box:SetAutoFocus(false)
    ns.SetFontObject(w.box, GameFontHighlightSmall)
    w.box:SetJustifyH("LEFT")
    w.box:SetTextInsets(TEXT_PAD, TEXT_PAD, 0, 0)
    w.box.bpInsetR = TEXT_PAD   -- what SetInsets guards on; see above.

    w.ring, w.bg = ns.BorderedRound(w.box, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(w.box, w.ring)

    return w
end

-- The submit button, built on first use and never for a field that does not
-- want one.
local function EnsureSubmit(w)
    if w.submit then return w.submit end
    local b = CreateFrame("Button", nil, w)
    -- Two pixels inside the box top and bottom, and the box's own corner
    -- radius (owner, 2026-09-14): a smaller, rounder button inside a
    -- rounder well read as a pill dropped into a slot.
    b:SetHeight(ROW_H - 4)
    b:SetPoint("RIGHT", w.box, "RIGHT", -2, 0)
    -- The button and the box are SIBLINGS, both children of the wrapper, so
    -- without this they sit at the same frame level and which one's
    -- textures win is creation order rather than anything specified. The
    -- button sits inside the box and must draw over it, border included.
    b:SetFrameLevel(w.box:GetFrameLevel() + 1)
    b.ring, b.bg = ns.BorderedRound(b, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(b, b.ring)
    b.face = ns.ButtonFace(b, "ARTWORK", 8, "control")
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    b:Hide()
    w.submit = b
    return b
end

-- The multi-line box's button: a full-height button drawn exactly the way
-- the `button` control draws one (same nine-piece rounded fill, same font,
-- same lift on hover), because it sits in a row of its own under the box,
-- beside the page's other buttons -- and a page's Accept and its Reset
-- should not be two different shapes. The one-line field keeps the small
-- in-field button above; that one lives INSIDE the text and is sized to
-- fit there. Built once, on first use.
local function EnsureMultiSubmit(w)
    if w.msubmit then return w.msubmit end
    local b = CreateFrame("Button", nil, w)
    b:SetHeight(ROW_H)
    local ringPaint = ns.RoundedFill(b, "BACKGROUND", 8, nil, { 0, 0, 0, 0 }, 0)
    local bgPaint   = ns.StrokedFill(b, "BORDER",     8, nil, { 0, 0, 0, 0 }, "control")
    b.bgPaint = bgPaint
    b.ring    = PaintAsTexture(ringPaint)
    ns.SetBorder(b, b.ring)
    b.face = ns.ButtonFace(b, "ARTWORK", 8, "control")
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    b:Hide()
    w.msubmit = b
    return b
end

-- The X that empties the box, for a field that asks for `clear`. A search
-- is the case that wants it: emptying one is the second thing anybody does
-- with it, and selecting the text to delete it is a fiddly way to say so.
--
-- No border and no fill -- it sits INSIDE a control that already has both,
-- and a second ring inside the first reads as a button bolted into the
-- field. The glyph alone, muted until hovered, is what the panel's own
-- search box does.
local function EnsureClear(w)
    if w.clear then return w.clear end
    local b = CreateFrame("Button", nil, w)
    b:SetSize(CLEAR_W, CLEAR_W)
    b:SetFrameLevel(w.box:GetFrameLevel() + 1)
    b.art = b:CreateTexture(nil, "OVERLAY")
    b.art:SetTexture(MEDIA .. "x.tga")
    b.art:SetSize(8, 8)
    b.art:SetPoint("CENTER")
    b:Hide()
    w.clear = b
    return b
end

-- How tall the wrapped text has turned out to be, told to the scroll frame
-- and to the bar. A multi-line EditBox that is a scroll child grows its own
-- height to fit its text, so this is a read, not a calculation -- and it is
-- the only thing the bar needs to know.
local function MultiContent(w)
    if not w.mscroll then return end
    w.mscroll.contentHeight = w.mbox:GetHeight() or 0
    if w.msb then w.msb:Update() end
end

-- The multi-line box, its scroll frame and its bar, built on first use and
-- never for a field that does not ask for one.
--
-- A SECOND EditBox rather than SetMultiLine on the first. create() is
-- handed no node -- the pool is keyed on the control's name alone -- so the
-- one box would have to be switched between the two shapes on every reuse,
-- and the one-line box's CARET is the product of a geometry that is set
-- once at creation and never touched again (see create(), which says so at
-- length). Resizing it per render is exactly what used to take the caret
-- away. Two boxes, one shown at a time, and the one-line path is the one it
-- always was.
local function EnsureMulti(w)
    if w.mhost then return w.mhost end

    -- The bordered surface is the FRAME, not the EditBox: the box is the
    -- scroll child and slides underneath, so a border drawn on it would
    -- slide too.
    --
    -- The host stops one scrollbar gutter short of the wrapper's right
    -- edge: the bar lives BESIDE the box, in that reserved strip, never
    -- over the text -- and the strip is reserved whether or not the bar is
    -- up, so the text does not re-wrap the moment it grows past the bottom
    -- of the box. The wrapper's height is set by apply(), so the host is
    -- anchored by its top corners and given its own height there.
    local host = CreateFrame("Frame", nil, w)
    host:SetPoint("TOPLEFT")
    host:SetPoint("TOPRIGHT", w, "TOPRIGHT", -ns.SCROLLBAR_GUTTER, 0)
    host.ring, host.bg = ns.BorderedRound(host, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(host, host.ring)

    -- The scroll frame is the WRAPPER's child, not the host's, and is laid
    -- inside the host's padding: ns.AttachScrollBar hangs its bar off the
    -- scroll frame's parent's right edge, and the parent whose right edge
    -- is the gutter is the wrapper. Drawn a level above the host so its
    -- text sits on the host's fill rather than under it.
    local sc = CreateFrame("ScrollFrame", nil, w)
    sc:SetPoint("TOPLEFT",     host, "TOPLEFT",     TEXT_PAD, -MULTI_PAD)
    sc:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -TEXT_PAD, MULTI_PAD)
    sc:SetFrameLevel(host:GetFrameLevel() + 1)

    local box = CreateFrame("EditBox", nil, sc)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    ns.SetFontObject(box, GameFontHighlightSmall)
    box:SetJustifyH("LEFT")
    -- The padding is the host's, so the box's own insets are nothing. Told
    -- to SetBoxInsets' bookkeeping as well, so nothing writes them again.
    box:SetTextInsets(0, 0, 0, 0)
    box.bpInsetL, box.bpInsetR = 0, 0
    -- NO SetMaxLetters and NO SetMaxBytes, on purpose. The reason this
    -- shape exists is a pasted string tens of thousands of characters long;
    -- a cap put here for tidiness would silently truncate one, and a string
    -- that is quietly one character short is a string that decodes to
    -- nothing with no way to see why.
    box:SetWidth(1)
    box:SetHeight(MULTI_LINE_H)
    sc:SetScrollChild(box)

    sc:SetScript("OnSizeChanged", function(self)
        -- The scroll child takes the viewport's WIDTH and keeps its own
        -- height: a multi-line EditBox with a width wraps to it and grows
        -- to fit, which is what gives the scroll frame a content height
        -- worth measuring.
        box:SetWidth(math.max(1, self:GetWidth() or 1))
        MultiContent(w)
    end)
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, delta)
        local maxs = math.max(0, (self.contentHeight or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxs,
            self:GetVerticalScroll() - delta * MULTI_LINE_H * 3)))
    end)

    -- Follow the caret. Typing past the bottom of a box that does not
    -- scroll to keep up is typing into a box that has stopped showing what
    -- you type; `y` is measured down from the box's own top, which is the
    -- same origin the scroll offset uses.
    box:SetScript("OnCursorChanged", function(_, _, y, _, ch)
        local top    = -(y or 0)
        local bottom = top + (ch or MULTI_LINE_H)
        local off    = sc:GetVerticalScroll() or 0
        local view   = sc:GetHeight() or 0
        if top < off then
            sc:SetVerticalScroll(math.max(0, top))
        elseif view > 0 and bottom > off + view then
            sc:SetVerticalScroll(math.max(0, bottom - view))
        end
    end)

    -- The HOST takes the mouse, for the whole box. The EditBox is only as
    -- tall as its text -- one line, on an empty box -- so a click below
    -- the text lands on nothing and the field looks dead everywhere but
    -- its first line. A press anywhere on the box focuses it with the
    -- caret at the end, which is what a click past the end of the text
    -- means; a press ON the text is the box's own and places the caret
    -- there, since the box sits above the host. Hover is installed on the
    -- host by apply(), beside the box's, so the border lights for both.
    host:EnableMouse(true)
    host:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if not box:IsEnabled() then return end
        box:SetFocus()
        box:SetCursorPosition(box:GetNumLetters())
    end)

    w.mhost, w.mscroll, w.mbox = host, sc, box
    -- The library's own bar, in the gutter the scroll frame stepped out of.
    -- It anchors to the scroll frame's PARENT, which is why the host is a
    -- frame of its own rather than the pooled wrapper -- the wrapper is
    -- also what the one-line box fills.
    w.msb = ns.AttachScrollBar(sc, function() return w.bpSkinNow end)
    host:Hide()
    return host
end

-- Three things here are load-bearing for the CARET, and none is obvious.
--
-- The field spent a long time drawing its text with no cursor at all while
-- the slider's number box, built from the same art and the same focus
-- wiring, always had one. Construction, pooling, draw layers, insets,
-- height, justification, frame level and the whole parent chain were each
-- ruled out by measurement -- while focused the two boxes were
-- indistinguishable. What this control was missing was the number box's
-- explicit `EnableMouse(true)`, a text seed in apply rather than only on
-- refresh, and -- the piece that let the other two work -- a width the box
-- actually HELD at the moment of the seed, set synchronously below rather
-- than derived from anchors a layout pass later. See create(). Do not drop
-- any of the three as redundant.

function textinput.apply(w, node, ctx)
    -- WHICH SHAPE, decided once here and remembered on the widget: every
    -- helper below asks the widget rather than the node, because the pool
    -- will hand this same frame to a one-line field next render.
    w.bpSkinNow = ctx.app.skin
    w.multi = MultiRows(node) and true or nil
    -- The scroll frame and its bar are the WRAPPER's children, not the
    -- host's (see EnsureMulti), so hiding the host does not take them
    -- with it: they are shown and hidden by name. Left out, a pasted
    -- string stayed painted over whatever one-line field this pooled
    -- widget served next.
    if w.multi then
        EnsureMulti(w)
        w.box:Hide()
        w.mhost:Show()
        w.mscroll:Show()
        w.mhost:SetHeight(MultiHeight(node))
        w:SetHeight(MultiFieldHeight(node))
    else
        if w.mhost then
            w.mhost:Hide()
            w.mscroll:Hide()
            if w.msb then w.msb:Hide() end
        end
        w.box:Show()
        w:SetHeight(ROW_H)
    end

    local box = Box(w)
    -- Where the BORDER lives. On a one-line field it is the box's own, as
    -- it always was; on a multi-line one it belongs to the host, and the
    -- hover and focus states are painted there instead. Same three calls
    -- either way, so the two shapes cannot drift apart.
    local border = (w.multi and w.mhost) or box

    -- Everything slider.apply does to its number box, in its order.
    ns.InstallHover(box, border, node, ctx)
    -- The multi-line host is the surface the reader actually meets --
    -- the box itself is only as tall as its text -- so it hovers too, and
    -- paints the same border.
    if w.multi then ns.InstallHover(w.mhost, border, node, ctx) end
    box:EnableMouse(true)
    box:SetScript("OnEditFocusGained", function()
        border.bpActive = true
        ns.PaintBorder(border, "active")
    end)
    box:SetScript("OnEditFocusLost", function(self)
        border.bpActive = false
        ns.PaintBorder(border, border.bpHovered and "hover" or nil)
        self:HighlightText(0, 0)
        -- `commitOnBlur`: what is in the box is committed when the focus
        -- leaves it, not only on Enter. For a field whose value another
        -- control on the page is about to READ -- a name typed and then
        -- the button beside it clicked: the click takes the focus first,
        -- so the value is stored by the time the button's own handler
        -- runs. Escape is the one way out that must NOT commit; the
        -- Escape handler says so before it drops the focus, and refresh()
        -- puts the stored value back a moment later.
        if node.commitOnBlur and not w.bpEscaping
           and IsDirty(w, node, ctx) and not ns.IsDisabled(node, ctx) then
            HideSuggest(w)
            ns.Commit(node, ctx, self:GetText())
            UpdateSubmit(w, node, ctx)
        end
        -- ONE FRAME LATER, and not at all while the cursor is over the
        -- flyout. A click on a suggestion row lands here first (the row is
        -- a frame of its own, so taking it steals the focus), and hiding
        -- the list on the spot would pull the row out from under the click
        -- that is already on it.
        if sugFrame and sugFrame:IsShown() and sugFrame.bpOwner == w then
            C_Timer.After(0, function()
                if sugFrame and sugFrame:IsShown() and sugFrame:IsMouseOver() then return end
                HideSuggest(w)
            end)
        end
    end)
    -- A single click puts the caret where you clicked and selects nothing;
    -- a double click selects the value. See ns.InstallTextFieldMouse.
    ns.InstallTextFieldMouse(box)

    -- ONE commit path. Enter and the button both come here, so the two
    -- cannot drift into meaning different things.
    local function commit()
        HideSuggest(w)
        ns.Commit(node, ctx, box:GetText())
        box:ClearFocus()
        UpdateSubmit(w, node, ctx)
    end

    -- Enter takes the HIGHLIGHTED suggestion when there is one, and what
    -- is typed when there is not. Nothing is highlighted until the reader
    -- arrows onto a row, so Enter on a freshly typed name still means the
    -- name -- picking a row is always something they asked for.
    -- 2026-09-14 (owner ruling): on a MULTI-LINE box Enter is a NEWLINE,
    -- as it is in a text editor -- the box is a paragraph now (a list of
    -- names, one per line), not only a pasted string. Committing is the
    -- `submit` button's job there (blur commits too, with commitOnBlur);
    -- Escape still reverts. With no handler installed the client inserts
    -- the newline itself.
    if w.multi then
        box:SetScript("OnEnterPressed", nil)
    else
        box:SetScript("OnEnterPressed", function()
            if SuggestOpen(w) and (sugFrame.bpIndex or 0) > 0 then
                PickSuggest(w, node, ctx, sugFrame.bpItems[sugFrame.bpIndex])
                return
            end
            commit()
        end)
    end

    -- Up and down move through the list. Neither key does anything in a
    -- one-line EditBox, and the handler leaves every other key to the box
    -- itself -- nothing is swallowed, so typing is untouched.
    box:SetScript("OnKeyDown", function(_, key)
        if key == "DOWN" then MoveSuggest(w, 1)
        elseif key == "UP" then MoveSuggest(w, -1) end
    end)

    box:SetScript("OnEscapePressed", function(self)
        -- Escape closes the SUGGESTIONS first, keeping the text and the
        -- focus: the reader is dismissing the list, not abandoning what
        -- they typed. A second Escape does what it always did.
        if SuggestOpen(w) then HideSuggest(w); return end
        -- Escape ABANDONS the edit: the blur below must not commit it.
        w.bpEscaping = true
        self:ClearFocus()
        w.bpEscaping = nil
        -- Puts the stored value back, which also un-dirties the field and
        -- takes the button with it.
        ctx.app:RefreshBinding(node.bind or node.id)
        UpdateSubmit(w, node, ctx)
    end)

    -- The EditBox grows to fit its text a moment AFTER the text changes,
    -- so a bar measured from OnTextChanged alone read the height the text
    -- HAD and stayed one edit behind -- never appearing for a box that
    -- overflowed by one line. The box's own OnSizeChanged is the event
    -- that carries the new height. Installed here, with the rest of the
    -- box's scripts, because the pool scrubs them on release.
    if w.multi then
        box:SetScript("OnSizeChanged", function() MultiContent(w) end)
    end
    box:SetScript("OnTextChanged", function(_, byUser)
        -- The wrapped text just changed height, so the bar's idea of what
        -- it is scrolling has to change with it -- before anything else,
        -- because a pasted string is the case that needs a bar at all.
        if w.multi then MultiContent(w) end
        UpdateSubmit(w, node, ctx)
        -- Only for text the USER typed. Every seed -- apply's, refresh's,
        -- the one a pick writes -- also fires this, and a flyout that
        -- reopened on its own answer would reappear over the list the pick
        -- just changed.
        if byUser then UpdateSuggest(w, node, ctx) end
    end)

    if node.clear then
        EnsureClear(w)
        -- Clearing COMMITS. A box that looks empty while the setting it
        -- stands for still holds the old text is the same disagreement the
        -- panel's own search box had when its X only changed the text, and
        -- for a filter it means a list still filtered by a query nothing
        -- shows any more.
        w.clear:SetScript("OnClick", function()
            box:SetText("")
            ns.Commit(node, ctx, "")
            -- Focus stays: clearing a search is usually the start of typing
            -- the next one.
            box:SetFocus()
            UpdateSubmit(w, node, ctx)
            UpdateSuggest(w, node, ctx)
        end)
        w.clear:SetScript("OnEnter", function(self)
            local a = ctx.app.skin.accent
            self.art:SetVertexColor(a[1], a[2], a[3], 1)
        end)
        w.clear:SetScript("OnLeave", function(self)
            local m = ctx.app.skin.textMuted
            self.art:SetVertexColor(m[1], m[2], m[3], 1)
        end)
    elseif w.clear then
        w.clear:SetScript("OnClick", nil)
        w.clear:Hide()
    end

    -- Whichever shape is NOT in use puts its button away: the pool hands
    -- this frame to either shape next. A search field has neither.
    local wantSubmit = node.submit and not node.search
    if (w.multi or not wantSubmit) and w.submit then
        w.submit:SetScript("OnClick", nil); w.submit:Hide()
    end
    if (not w.multi or not wantSubmit) and w.msubmit then
        w.msubmit:SetScript("OnClick", nil); w.msubmit:Hide()
    end
    -- The box spans the field; a button lives INSIDE it (or under it).
    if not w.multi then w.box:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0) end

    -- The magnifier, for a search field: built on first use, at the box's
    -- left, in the muted text color, and put away on a frame the pool
    -- hands to a field that is not one.
    if node.search and not w.multi then
        if not w.searchIcon then
            w.searchIcon = w.box:CreateTexture(nil, "OVERLAY")
            -- THE PANEL'S OWN SEARCH BOX'S ICON, COPIED. The top search box
            -- is the client's SearchBoxTemplate, and "the same magnifier
            -- as that one" is best answered by asking it: its art (atlas
            -- or file) and its size, whatever this client's template
            -- draws. Guessing was wrong twice -- the legacy file was soft
            -- beside it, and the atlas at a guessed size was too large.
            -- Only when the panel has no search box yet does this fall
            -- back to the atlas at a small fixed size, then the file.
            local src = ctx.app.searchBox and ctx.app.searchBox.searchIcon
            -- Two locals from a plain call: `src and src:GetSize()` keeps only
            -- the FIRST return (the `and` truncates the list), which handed
            -- SetSize a nil height.
            local sw, sh
            if src then sw, sh = src:GetSize() end
            if src and sw and sw > 0 and sh and sh > 0 then
                local atlas = src.GetAtlas and src:GetAtlas()
                if atlas then
                    w.searchIcon:SetAtlas(atlas)
                else
                    w.searchIcon:SetTexture(src:GetTexture())
                    local l, r, t, b = src:GetTexCoord()
                    if l then w.searchIcon:SetTexCoord(l, r, t, b) end
                end
                w.searchIcon:SetSize(sw, sh)
            else
                local atlas = C_Texture and C_Texture.GetAtlasInfo
                              and C_Texture.GetAtlasInfo(SEARCH_ATLAS)
                if atlas then
                    w.searchIcon:SetAtlas(SEARCH_ATLAS)
                    w.searchIcon:SetSize(11, 11)
                else
                    w.searchIcon:SetTexture(SEARCH_ICON)
                    w.searchIcon:SetSize(SEARCH_ICON_W, SEARCH_ICON_W)
                end
            end
            w.searchIcon:SetPoint("LEFT", w.box, "LEFT", 5, -1)
            -- The text inset clears whichever glyph was drawn.
            w.searchInset = 5 + math.ceil(w.searchIcon:GetWidth() or SEARCH_ICON_W) + 4
        end
        local m = ctx.app.skin.textMuted
        w.searchIcon:SetVertexColor(m[1], m[2], m[3], 0.9)
        w.searchIcon:Show()
    elseif w.searchIcon then
        w.searchIcon:Hide()
    end

    if wantSubmit and w.multi then
        -- The full-height button, in the row reserved UNDER the box
        -- (MultiFieldHeight), flush with the box's right edge: on a
        -- wrapping box there is no "end of the text" to sit at, and a
        -- button over the text covers whatever line it reached. Sized as
        -- the button control sizes itself, so it matches one beside it.
        local b = EnsureMultiSubmit(w)
        local caption = SubmitLabel(node)
        b.label:SetText(caption)
        b:SetWidth(34 + #caption * 6.6)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", w.mhost, "BOTTOMRIGHT", 0, -(MULTI_BTN_GAP + ROW_H))
        b:SetScript("OnClick", commit)
        -- The button control's own hover: the fill lifts as well as the
        -- border, because the whole surface is the target.
        b.bpOnHover = function(self, hovered)
            -- A button that is not live does not lift: the dim paint IS
            -- its answer to the hover. Off the hover, back to whatever
            -- liveness says (refresh's bpPaint).
            if not self.bpLive then
                if self.bpPaint then self.bpPaint() end
                return
            end
            local skin = ctx.app.skin
            self.bgPaint({ C(ns.ButtonFill(skin, node, "primary"), hovered and 2.2 or 1, 1) })
        end
        ns.InstallHover(b, b, node, ctx)
    elseif wantSubmit then
        EnsureSubmit(w)
        w.submit.label:SetText(SubmitLabel(node))
        -- Sized from its own label. A fixed width either clips "Rename" or
        -- leaves a hole beside "Add". Inside the right end of the text.
        w.submit:SetWidth(math.max(32, math.ceil(w.submit.label:GetStringWidth() + 18)))
        w.submit:ClearAllPoints()
        w.submit:SetPoint("RIGHT", w.box, "RIGHT", -2, 0)
        w.submit:SetFrameLevel(w.box:GetFrameLevel() + 1)
        w.submit:SetScript("OnClick", commit)
        w.submit:SetScript("OnEnter", function(self)
            if self.bpLive then ns.PaintBorder(self, "hover") end
        end)
        w.submit:SetScript("OnLeave", function(self)
            ns.PaintBorder(self, nil)
        end)
    end

    -- Seeded here, the way the slider seeds its box from SetValue.
    -- refresh() puts it back afterwards, but only when unfocused.
    local insetGen = box.bpInsetGen
    box:SetText(tostring(ns.GetValue(node, ctx) or ""))
    if w.multi then MultiContent(w) end

    UpdateSubmit(w, node, ctx)
    -- 2026-09-14: THE CARET FOLLOWS THE INSETS ONLY THROUGH A SetText. The
    -- pool hands this frame to a plain field straight after a `search`
    -- one, whose left inset is the magnifier's; UpdateSubmit puts the
    -- plain inset back, but the client lays the caret out from the insets
    -- it had when the text was last set -- so the caret sat where the
    -- (hidden) magnifier used to be. Seed once more whenever this pass
    -- moved the insets, so the caret is laid out against the new ones.
    if not w.multi and box.bpInsetGen ~= insetGen then
        box:SetText(box:GetText() or "")
    end
end

function textinput.refresh(w, node, ctx)
    local box  = Box(w)
    local skin = ctx.app.skin
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    w.bpSkinNow = skin
    -- The border and the fill are the HOST's on a multi-line field and the
    -- box's own on a one-line one; everything else below is the same.
    local border = (w.multi and w.mhost) or box
    local fill   = (w.multi and w.mhost.bg) or w.bg
    -- Same four lines slider.refresh applies to its number box, same order.
    ns.MarkBorder(border, skin, skin.controlBorder, a)
    fill:SetVertexColor(C(skin.controlBg, 1, a))
    box:SetTextColor(C(skin.text, 1, a))
    box:SetEnabled(not off)

    if not box:HasFocus() then
        box:SetText(tostring(ns.GetValue(node, ctx) or ""))
        -- A field the reader has left, or one combat has just disabled,
        -- has no business holding a list of suggestions open over the page.
        HideSuggest(w)
    end

    if w.clear then
        local m = skin.textMuted
        w.clear.art:SetVertexColor(m[1], m[2], m[3], a)
    end

    -- BOTH submit buttons take the PRIMARY pair -- the plain button
    -- colors the top strip's buttons wear (owner, 2026-09-14: not the
    -- green confirm pair; being grayed until the field is dirty is what
    -- marks the button as live, so it needs no color of its own).
    if w.submit then
        -- Painted through a function the button keeps, because its
        -- liveness changes on every keystroke (UpdateSubmit) and not only
        -- on a refresh: live, the confirm pair at full strength; not,
        -- the same button dimmed the way a disabled control is.
        local b = w.submit
        b.bpPaint = function()
            local live = b.bpLive and not off
            local la   = live and 1 or 0.4
            b.bg:SetVertexColor(C(ns.ButtonFill(skin, node, "primary"), 1.35, a * la))
            b.face:SetVertexColor(1, 1, 1, ns.FaceAlpha(skin, a * la))
            ns.MarkBorder(b, skin, skin.controlBorder, a * la)
            b.label:SetTextColor(C(ns.ButtonText(skin, node, "primary"), 1, a * la))
        end
        b.bpPaint()
    end
    -- The multi-line button is painted the way button.refresh paints a
    -- button, so the two cannot drift apart.
    -- 2026-09-14: and, like the in-field button, DIMMED until the field
    -- is dirty. It was enabled/disabled with the field's state but painted
    -- at full strength regardless, so an Accept under an empty paste box
    -- looked clickable. The same bpPaint hook UpdateSubmit calls on every
    -- keystroke, so the two buttons cannot drift apart.
    if w.msubmit then
        local b = w.msubmit
        b.bpPaint = function()
            local live = b.bpLive and not off
            local la   = live and 1 or 0.4
            b.bgPaint({ C(ns.ButtonFill(skin, node, "primary"), 1, a * la) })
            b.face:SetVertexColor(1, 1, 1, ns.FaceAlpha(skin, a * la))
            ns.MarkBorder(b, skin, skin.controlBorder, a * la)
            b.label:SetTextColor(C(ns.ButtonText(skin, node, "primary"), 1, a * la))
        end
        b.bpPaint()
    end

    if w.multi then MultiContent(w) end

    UpdateSubmit(w, node, ctx)
end
-- A one-line field prefers 200 and will take 120 at a squeeze, one row
-- tall. A MULTI-LINE one takes the whole row -- 9999 is what a note asks
-- for, and FieldMetrics clamps it to the content width -- and is exactly
-- as tall as the rows it declared, so the space the layout leaves is the
-- space apply() is about to set the wrapper to -- button row included.
function textinput.measure(node)
    if MultiRows(node) then return 9999, 9999, MultiFieldHeight(node) end
    return 200, 120, ROW_H
end
textinput.stretch = true

-- ── search (a text field in a pool of its own) ─────────────────
--
--   { control = "search", label = "Search", clear = true, get = …, set = … }
--
-- The same control as `text` with `search = true` -- the magnifier, the
-- wider left inset, no submit button -- but registered under ITS OWN NAME so
-- it is pooled apart from plain text fields. Widgets are pooled by control
-- name (Page.lua's Acquire("ctl:" .. control)), and a frame that had served
-- a search box carried its magnifier inset into the plain field it served
-- next: the caret sat a magnifier's width from the left edge until the text
-- was re-set. Two pools, and the two shapes can never meet.
local searchinput = setmetatable({}, { __index = textinput })
function searchinput.apply(w, node, ctx)
    node.search = true
    return textinput.apply(w, node, ctx)
end


-- ── button ─────────────────────────────────────────────────────

-- A button's CAPTION. `text` or `label`, and either may be a FUNCTION: a
-- button whose caption is its own state ("Select All" while anything is
-- off, "Deselect All" once everything is on) writes one.
--
-- Nothing resolved them here. `node.text or node.label` handed the raw
-- function to SetText, which refuses it, and to `#tostring(...)` in
-- measure, which sized the button for "function: 0x...". FieldLabel is the
-- resolver every other control's label goes through; `text` gets the same
-- treatment, one step earlier, because it is the caption's first name.
local function ButtonText(node)
    local t = node.text
    if type(t) == "function" then t = t(node) end
    if t == nil or t == false then t = ns.FieldLabel(node) end
    return t and tostring(t) or ""
end

-- ── Which pair of button colors ───────────────────────────────
--
-- One place, because four callers ask: the `button` control's apply (the
-- hover lift) and refresh, and the text field's two submit buttons. `kind`
-- names the pair outright where the node cannot say it for itself -- a
-- submit button is a node like any other and carries no `danger` -- and
-- otherwise it is read off the node: `danger = true` for the red pair,
-- `confirm = true` for the green one (an Add button), else primary.
--
-- Every lookup falls back to the token that color came from before these
-- existed, so a skin registered by a consuming addon that predates them
-- paints exactly as it did.
local function ButtonKind(node, kind)
    if kind then return kind end
    if node and node.danger  then return "danger"  end
    if node and node.confirm then return "confirm" end
    return "primary"
end
ns.ButtonKind = ButtonKind

-- The border a button wears: the color its caption is drawn in for
-- danger and confirm -- red and green, the two pairs that mirror each
-- other -- and the control border for the rest, as before.
function ns.ButtonBorder(skin, node, kind)
    kind = ButtonKind(node, kind)
    if kind == "danger"  then return skin.danger end
    if kind == "confirm" then return skin.buttonConfirmText or skin.controlBorder end
    return skin.controlBorder
end

function ns.ButtonFill(skin, node, kind)
    kind = ButtonKind(node, kind)
    if kind == "danger"  then return skin.buttonDangerBg  or skin.controlBg end
    if kind == "confirm" then return skin.buttonConfirmBg or skin.controlBg end
    if kind == "nav"     then return skin.buttonNavBg     or skin.railBg    end
    return skin.buttonPrimaryBg or skin.controlBg
end

function ns.ButtonText(skin, node, kind)
    kind = ButtonKind(node, kind)
    if kind == "danger"  then return skin.buttonDangerText  or skin.danger end
    if kind == "confirm" then return skin.buttonConfirmText or skin.text   end
    if kind == "nav"     then return skin.buttonNavText     or skin.text   end
    return skin.buttonPrimaryText or skin.text
end

local button = {}

-- The size a caption is drawn at when nothing else says -- the same 12 the
-- group presets carry as their header size, stated here as well because
-- `measure` runs before there is a widget or a skin to ask.
local BUTTON_FONT_SIZE = 12

-- One hidden FontString to ask how wide a caption really is. Made through
-- ns.FS like every other string in the panel, so a re-pointed panel font
-- re-points this one too and the measurement stays honest.
local buttonMeasureFS
local function ButtonTextWidth(text)
    if not buttonMeasureFS then
        buttonMeasureFS = ns.FS(UIParent, "BACKGROUND", "GameFontNormalSmall")
        buttonMeasureFS:Hide()
    end
    ns.SetFontSize(buttonMeasureFS, BUTTON_FONT_SIZE)
    buttonMeasureFS:SetText(text or "")
    return buttonMeasureFS:GetStringWidth() or 0
end

function button.create(app, parent)
    local w = CreateFrame("Button", nil, parent)
    w:SetHeight(ROW_H)

    -- NINE PIECES, not a nine-SLICED texture.
    --
    -- ns.BorderedRound leans on SetTextureSliceMargins, whose corner is
    -- expressed in UI units: it is resampled by the UI scale, and on a
    -- control barely taller than 2 x radius the corner pieces eat almost the
    -- whole height, so the shape changes with the control's size. Which is
    -- how a 17px icon button ended up with visibly rounder corners than a
    -- 22px text button carrying the same radius.
    --
    -- ns.RoundedFill instead draws four cropped quadrants at a size we
    -- choose, with bands between them -- r texels across exactly r physical
    -- pixels, whatever the control's size or the UI scale. It is the
    -- construction the group cards use, and structurally the one Blizzard's
    -- own UIPanelButtonTemplate uses: fixed corner pieces, stretchy edges and
    -- middle, which is why a small stock button and a wide one have the same
    -- corners.
    local ringPaint = ns.RoundedFill(w, "BACKGROUND", 8, nil, { 0, 0, 0, 0 }, 0)
    local bgPaint   = ns.StrokedFill(w, "BORDER",     8, nil, { 0, 0, 0, 0 }, "control")
    w.bgPaint = bgPaint
    w.ring    = PaintAsTexture(ringPaint)
    ns.SetBorder(w, w.ring)
    -- The relief, over the fill and under the caption. See ns.ButtonFace.
    w.face = ns.ButtonFace(w, "ARTWORK", 8, "control")

    w.text = ns.FS(w, "OVERLAY", "GameFontNormalSmall")
    w.text:SetPoint("CENTER")
    return w
end

-- The button's face: the flat fill at `mul` (the hover lift) and the
-- relief over it, both at `a` (the disabled alpha).
local function PaintButtonFace(w, skin, node, mul, a)
    w.bgPaint({ C(ns.ButtonFill(skin, node), mul, a) })
    if w.face then w.face:SetVertexColor(1, 1, 1, ns.FaceAlpha(skin, a)) end
end
-- ── Icon variants ──────────────────────────────────────────────
--
-- Some of the panel's icons come in more than one drawing of the same idea,
-- and which one a panel wears is a matter of taste rather than of meaning.
-- So a page names the icon SEMANTICALLY -- "center-h" -- and the library
-- picks the art, which is what makes one setting move every such icon in the
-- panel instead of each caller hardcoding a filename.
--
-- Only names listed here have a variant; anything else -- an addon's own art,
-- an icon with no second drawing -- passes through untouched.
local ICON_VARIANTS = { ["center-h"] = true, ["center-v"] = true }

function ns.IconVariant(name, app)
    if type(name) ~= "string" then return name end
    local style = app and app.iconStyle or 1
    if style == 1 or not ICON_VARIANTS[name] then return name end
    return name .. tostring(style)
end

-- An ICON on a button, exactly as the segmented control takes one: a bare
-- name is one of the panel's own files, anything with a path separator is the
-- consuming addon's own art. The button stays a button -- border, hover,
-- disabled fade, right-click menu -- and the caption moves to the tooltip,
-- which is what a caption on an icon button is for anyway.
local function ButtonIcon(w, node, ctx)
    local icon = node.icon
    if not icon then
        if w.icon then w.icon:Hide() end
        return nil
    end
    if not w.icon then
        w.icon = w:CreateTexture(nil, "OVERLAY")
        w.icon:SetPoint("CENTER")
    end
    icon = ns.IconVariant(icon, ctx and ctx.app)
    w.icon:SetTexture(icon:find("[\\/]") and icon or (MEDIA .. icon .. ".tga"))
    local size = node.iconSize or 15
    w.icon:SetSize(size, size)
    w.icon:Show()
    return size
end

function button.apply(w, node, ctx)
    -- The caption still goes in, and is simply hidden under an icon: it is
    -- what measure sizes a text button by, and it costs nothing to keep.
    w.text:SetShown(not node.icon)
    ButtonIcon(w, node, ctx)
    w.text:SetText(ButtonText(node))
    w:SetScript("OnClick", function()
        if ns.IsDisabled(node, ctx) then return end
        if node.onClick then node.onClick(node, ctx) end
    end)
    -- The button lifts its fill as well as its border, because it is the
    -- one control whose whole surface is the target.
    w.bpOnHover = function(self, hovered)
        local skin = ctx.app.skin
        -- Lighten the fill rather than swapping in a translucent wash, so
        -- the border underneath never shows through it. `buttonBg`, not
        -- controlBg: a button carries its own color so it can be picked
        -- out from the wells around it, and ships at the control's.
        PaintButtonFace(self, skin, node, hovered and 2.2 or 1, 1)
    end
    ns.InstallHover(w, w, node, ctx)
end
function button.refresh(w, node, ctx)
    -- Re-read the caption, not just the colors: a caption that IS the
    -- state has to change when the state does, and apply runs once.
    w.text:SetText(ButtonText(node))
    local skin = ctx.app.skin
    -- A caption at the group HEADER's size, not a label's. bpHeaderSize is
    -- the preset's, published by Page.lua; the skin token is the fallback
    -- for a button drawn outside any group.
    ns.SetFontSize(w.text, w.bpHeaderSize or skin.buttonFontSize or BUTTON_FONT_SIZE)
    local off  = ns.IsDisabled(node, ctx)
    local a    = off and 0.4 or 1
    -- The button's own pair -- primary or danger -- falling back to the
    -- control's so a skin that predates them is unchanged.
    local fg   = ns.ButtonText(skin, node)
    PaintButtonFace(w, skin, node, 1, a)
    ns.MarkBorder(w, skin, ns.ButtonBorder(skin, node), a)
    w.text:SetTextColor(C(fg, 1, a))
    -- The icon takes the caption's color, so an icon button and a text
    -- button gray out identically.
    if w.icon and w.icon:IsShown() then
        w.icon:SetVertexColor(C(fg, 1, a))
    end
    w:SetEnabled(not off)
end
function button.measure(node)
    -- An icon button is sized by its icon and its padding, not by the caption
    -- it is not showing. Wider than tall on purpose: a square button at row
    -- height is a small target and reads as a decoration rather than a
    -- control.
    if node.icon then
        local size = node.iconSize or 15
        local wdt  = size + 16
        return wdt, wdt, ROW_H
    end
    -- MEASURED, not counted.
    --
    -- This used to be `34 + #text * 6.6 * (size / 10)` -- a per-character
    -- estimate, and a generous one: at 7.9px a character a 34-character
    -- caption reserved ~300px for text that draws in about 180, and the
    -- button is DRAWN at the width it measures, so the surplus became side
    -- padding. A count of bytes is the wrong unit anyway -- it is bytes, so
    -- every accented or multi-byte character widened the button further,
    -- and escape codes counted as text while taking no width at all.
    --
    -- The same hidden-FontString trick the chips use, at the size the
    -- caption is actually drawn in. 22 is the padding either side.
    local wdt = math.max(60, ButtonTextWidth(ButtonText(node)) + 22)
    return wdt, wdt, ROW_H
end
button.stretch = false
-- A button's caption is ON the button. The form must not draw a second copy
-- of it above, which is what every button on a labeled-above card used to
-- get: the same words twice, once as a heading and once on its face.
button.ownLabel = true

-- ── keybind (press a key to bind) ──────────────────────────────
--
--   { control = "keybind", label = "Add/Remove Name Keybind",
--     bind = "toggleNameKey" }            -- or get/set; "" means unbound
--
-- The classic keybinding widget, drawn as this library's button, and run the
-- way that widget runs: its caption is the binding it holds ("SHIFT-F",
-- "CTRL-BUTTON4") or Not Bound. A click ARMS it -- the caption asks for a
-- key and the border lights -- and the next key pressed becomes the value,
-- modifiers prefixed the way the client writes a binding; a modifier on its
-- own is not a key. Escape while armed CLEARS the binding; a second click
-- while armed CANCELS, keeping the binding; the middle and side mouse
-- buttons bind as BUTTON3/4/5 and the wheel as MOUSEWHEELUP/DOWN. The
-- value is committed at once; there is nothing to accept.
--
-- KEYBOARD: arming is EnableKeyboard(true) and nothing else. A frame with
-- keyboard input enabled consumes the keys it receives, so the captured key
-- never reaches the panel's own Escape handler or the game.
-- SetPropagateKeyboardInput is deliberately never called: set true inside
-- OnKeyDown it releases the key being handled, which is how an Escape that
-- cleared the binding went on to close the panel. Never armed in combat
-- (keyboard changes are protected there).
--
-- DISARMING WAITS FOR THE KEY UP. The client delivers a key's up event to
-- the frame that consumed its down; a frame that turns its keyboard off
-- inside OnKeyDown never receives that up, and the client keeps routing
-- every later press of the same key to it -- swallowed, since the keyboard
-- is off -- until a reload. With Escape that is the whole key dead: no
-- panel close, no game menu. So OnKeyDown only notes the key as held and
-- OnKeyUp, which the still-enabled frame receives, is what turns the
-- keyboard off. Every other disarm (mouse button, wheel, cancel click,
-- hide, refresh while disabled) has no key down and turns it off at once;
-- one that lands while a key IS held is deferred to that key's up.
local keybind = {}

local KEYBIND_IGNORE = {
    BUTTON1 = true, BUTTON2 = true, UNKNOWN = true,
    LSHIFT = true, LCTRL = true, LALT = true, LMETA = true,
    RSHIFT = true, RCTRL = true, RALT = true, RMETA = true,
}

local function KeybindCaption(node, ctx, w)
    if w.bpArmed then return "Press a key..." end
    local v = ns.GetValue(node, ctx)
    if v == nil or v == "" then return NOT_BOUND or "Not Bound" end
    return tostring(v)
end

-- Turn the keyboard off -- now, or once the held key has come back up.
local function KeybindReleaseKeyboard(w)
    if w.bpHeld and next(w.bpHeld) then
        w.bpReleasePending = true
        -- Should the up never arrive (the frame lost it somehow), the
        -- keyboard must still come off: a second later is late enough
        -- for any real key press and far better than never.
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                if w.bpReleasePending and not w.bpArmed then
                    w.bpHeld = {}
                    KeybindReleaseKeyboard(w)
                end
            end)
        end
        return
    end
    w.bpReleasePending = false
    w:EnableKeyboard(false)
    -- AND AGAIN NEXT FRAME, FROM OUTSIDE THE KEY EVENT. In the field, an
    -- EnableKeyboard(false) issued from inside a key handler left the
    -- button still taking keys -- Escape and Enter dead until the reader
    -- armed and canceled it by mouse, which is this same call from a
    -- click. A timer callback runs from the frame loop, as a click does.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not w.bpArmed then w:EnableKeyboard(false) end
        end)
    end
end

local function KeybindDisarm(w)
    if not w.bpArmed then return end
    w.bpArmed = false
    w.bpActive = false
    KeybindReleaseKeyboard(w)
    w:EnableMouseWheel(false)
end

-- The key, with the modifiers the client would write in front of it, or
-- "" for Escape (clear), or nil for a key that is not a binding.
local function KeybindCompose(key)
    if key == "ESCAPE" then return "" end
    if KEYBIND_IGNORE[key] then return nil end
    local out = key
    if IsShiftKeyDown()   then out = "SHIFT-" .. out end
    if IsControlKeyDown() then out = "CTRL-"  .. out end
    if IsAltKeyDown()     then out = "ALT-"   .. out end
    return out
end

function keybind.create(app, parent)
    local w = button.create(app, parent)
    w:RegisterForClicks("AnyUp")
    w:EnableKeyboard(false)
    w:EnableMouseWheel(false)
    w.bpHeld = {}      -- keys down on this frame, by name
    return w
end

function keybind.apply(w, node, ctx)
    -- A pooled button never comes back armed: whatever it was doing for
    -- its last page, this page did not ask for it.
    KeybindDisarm(w)
    w.text:Show()
    if w.icon then w.icon:Hide() end
    w.text:SetText(KeybindCaption(node, ctx, w))

    local function take(key)
        local v = KeybindCompose(key)
        if v == nil then return end            -- a bare modifier: stay armed
        KeybindDisarm(w)
        ns.Commit(node, ctx, v)
        w.text:SetText(KeybindCaption(node, ctx, w))
        ns.PaintBorder(w, w.bpHovered and "hover" or nil)
    end

    w:SetScript("OnClick", function(self, mouse)
        if ns.IsDisabled(node, ctx) then return end
        if mouse == "LeftButton" or mouse == "RightButton" then
            if self.bpArmed then
                -- A second click CANCELS: the binding stays as it was.
                KeybindDisarm(self)
                self.text:SetText(KeybindCaption(node, ctx, self))
                ns.PaintBorder(self, self.bpHovered and "hover" or nil)
                return
            end
            if InCombatLockdown() then return end
            self.bpArmed = true
            self.bpActive = true
            self:EnableKeyboard(true)
            self:EnableMouseWheel(true)
            self.text:SetText(KeybindCaption(node, ctx, self))
            ns.PaintBorder(self, "active")
            return
        end
        if not self.bpArmed then return end
        -- The other mouse buttons ARE keys while armed.
        if mouse == "MiddleButton" then take("BUTTON3")
        elseif mouse == "Button4"  then take("BUTTON4")
        elseif mouse == "Button5"  then take("BUTTON5") end
    end)
    w:SetScript("OnKeyDown", function(self, key)
        -- Noted as held BEFORE the take, so the disarm inside it (and any
        -- disarm a page refresh runs during the commit) defers the
        -- keyboard-off to this key's up.
        self.bpHeld[key] = true
        if not self.bpArmed then return end
        take(key)
    end)
    w:SetScript("OnKeyUp", function(self, key)
        self.bpHeld[key] = nil
        if self.bpReleasePending and not next(self.bpHeld) then
            KeybindReleaseKeyboard(self)
        end
    end)
    w:SetScript("OnMouseWheel", function(self, delta)
        if not self.bpArmed then return end
        take((delta or 0) >= 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
    w:SetScript("OnHide", function(self)
        -- A hidden frame gets no key up, so nothing is held any more as
        -- far as it can tell; a pending release goes through now.
        self.bpHeld = {}
        if self.bpArmed then
            KeybindDisarm(self)
            self.text:SetText(KeybindCaption(node, ctx, self))
        elseif self.bpReleasePending then
            KeybindReleaseKeyboard(self)
        end
    end)

    w.bpOnHover = function(self, hovered)
        PaintButtonFace(self, ctx.app.skin, node, hovered and 2.2 or 1, 1)
    end
    ns.InstallHover(w, w, node, ctx)
end

function keybind.refresh(w, node, ctx)
    local skin = ctx.app.skin
    -- A refresh while armed leaves the prompt in place; the stored value
    -- has not changed and the reader is mid-press.
    w.text:SetText(KeybindCaption(node, ctx, w))
    ns.SetFontSize(w.text, w.bpHeaderSize or skin.buttonFontSize or BUTTON_FONT_SIZE)
    local off = ns.IsDisabled(node, ctx)
    if off then KeybindDisarm(w) end
    -- Safety net: a button that is not armed and not waiting on a key up
    -- has no business taking keys, whatever state it came back in.
    if not w.bpArmed and not w.bpReleasePending and w:IsKeyboardEnabled() then
        KeybindReleaseKeyboard(w)
    end
    local a   = off and 0.4 or 1
    local fg  = ns.ButtonText(skin, node)
    PaintButtonFace(w, skin, node, 1, a)
    ns.MarkBorder(w, skin, ns.ButtonBorder(skin, node), a)
    -- The prompt in the accent, so an armed button reads as waiting
    -- rather than as bound to the words "Press a key".
    if w.bpArmed then
        w.text:SetTextColor(C(skin.accent, 1, a))
    else
        w.text:SetTextColor(C(fg, 1, a))
    end
    w:SetEnabled(not off)
end

-- Sized for a long binding ("CTRL-SHIFT-BUTTON5"), not for the caption it
-- happens to show now, so it does not jump as the value changes.
function keybind.measure(node)
    local wdt = math.max(140, ButtonTextWidth("CTRL-SHIFT-BUTTON5") + 22)
    return wdt, math.min(wdt, 110), ROW_H
end
keybind.stretch = false
-- The label names the SETTING and sits above the button, as a dropdown's
-- does; the button's face is the value.

-- ── note (read-only text spanning the row) ─────────────────────

local note = {}
function note.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.text = ns.FS(w, "OVERLAY", "GameFontDisableSmall")
    -- Anchored on the LEFT only, with its width set explicitly below.
    --
    -- It used to be anchored TOPLEFT *and* TOPRIGHT and left to derive its
    -- own width from those. WoW resolves anchor-derived sizes in a later
    -- layout pass, so on the render that built the note the string still had
    -- no usable wrap width: it laid out as one line and truncated. Nudging
    -- the panel forced a re-render a frame later, by which time the width
    -- existed -- which is exactly why it only wrapped after a resize.
    w.text:SetPoint("TOPLEFT")
    w.text:SetJustifyH("LEFT")
    w.text:SetWordWrap(true)
    -- The picture a note may carry. Built with the note rather than on
    -- demand: a texture costs nothing while it has none set, and a note is
    -- the one control whose whole job is to be looked at.
    w.img = w:CreateTexture(nil, "ARTWORK")
    w.img:Hide()
    return w
end
-- `text` may be a function, for a note that reports live state rather than
-- standing prose. It is resolved on every refresh, and Page.IsDynamic counts
-- a function here as dynamic so the field is swept like any other computed
-- one.
local function NoteText(node, ctx)
    local t = node.text
    if type(t) ~= "function" then
        -- Marked here rather than at every call site, so the measure pass
        -- and the paint pass see the SAME string. They must: escape codes
        -- do not occupy width, but a measurement taken from the unmarked
        -- text and a paint taken from the marked one is the kind of
        -- mismatch that shows up as a note clipped by one line.
        return ns.search.Mark(ctx and ctx.app, t or "")
    end
    -- pcall because this runs during LAYOUT as well as during paint. A note
    -- that reports live state is the most likely place for a nil index, and
    -- a throw there takes the whole page down mid-render rather than
    -- spoiling one row.
    local ok, out = pcall(t, node, ctx)
    if not ok then return "" end
    return ns.search.Mark(ctx and ctx.app, tostring(out or ""))
end

-- ── A note's picture ───────────────────────────────────────────
--
-- `image = "<texture path>"` draws a picture UNDER the note's text, left
-- aligned with it, and the note is measured tall enough for both. Text is
-- optional: a note that is only an image is the picture on its own.
--
-- `imageWidth` / `imageHeight` size it. The default is 448x224, which is
-- the size the screenshots this was added for are authored at -- a 2:1
-- shot of the frames, wide enough to read at the panel's usual width. A
-- picture is drawn at the size it states whatever the row is: it is a
-- picture, not a control, and scaling one to the row would stretch it.
local NOTE_IMG_W, NOTE_IMG_H = 448, 224
local NOTE_IMG_GAP = 6   -- between the text and the picture under it

local function NoteImage(node)
    local path = node and node.image
    if not path then return nil end
    return path, node.imageWidth or NOTE_IMG_W, node.imageHeight or NOTE_IMG_H
end

-- How far down the picture starts. Nothing at all when there is no text --
-- an empty note must not leave a line's worth of white above its picture,
-- and neither must it leave the gap.
local function NoteImageDrop(body, textH)
    if body == nil or body == "" then return 0 end
    return textH + NOTE_IMG_GAP
end

function note.apply(w, node, ctx)
    w.text:SetText(NoteText(node, ctx))
    -- A note takes the mouse ONLY when it has something more to say. The
    -- page attaches a field's tooltip to whatever frames take the mouse,
    -- so a note that declares a `desc` -- a read-out of icons, whose
    -- meaning is exactly what a tooltip is for -- can be hovered, and a
    -- note that is only prose stays out of the way of what is under it.
    w:EnableMouse(node.desc ~= nil)
    -- Re-wrap if the row is resized under us.
    w:SetScript("OnSizeChanged", function(self)
        self.text:SetWidth(math.max(1, self:GetWidth()))
    end)
end
-- `font` names a font OBJECT, for a note that is a heading rather than
-- prose -- the title of a tree pane, say, where the subject changes with
-- the selection and so cannot be a card's static title. Default is the
-- note's own small face; the measure pass below reads the same field, or a
-- heading would be measured at body size and clipped.
local NOTE_FONT = "GameFontDisableSmall"
-- The default note SIZE: 11, a step above GameFontDisableSmall's own 10
-- (owner, 2026-09-15: description text read as fine print). Resolved by
-- NoteSize, which the draw (refresh) and the measure (WrappedHeight) both
-- ask, so a row is reserved at the size the string is drawn at. A note
-- naming its own font keeps that font's size; a note naming a size keeps
-- its size.
local NOTE_SIZE = 11
local function NoteSize(font, size)
    if size then return size end
    if font and font ~= NOTE_FONT then return ns.FontObjectSize(font) end
    return NOTE_SIZE
end

function note.refresh(w, node, ctx)
    local skin = ctx.app.skin
    local body = NoteText(node, ctx)
    -- The size is stated UNCONDITIONALLY, every render.
    --
    -- `if node.fontSize then` was the whole of the bug: a note that asks for
    -- no size of its own said nothing about size at all, and left the
    -- question to whatever the string happened to be wearing. Notes are
    -- pooled, so "whatever it happened to be wearing" is the last field that
    -- used that widget -- which is why two prose notes in adjacent cards
    -- could draw at different sizes, and why which ones did changed with
    -- what had been on screen before.
    --
    -- The default is the font object's own size rather than a constant, so
    -- a note that names a heading font still gets that font's size unless it
    -- overrides it -- which is what the old code MEANT, and got right only
    -- while the reset it relied on happened to work.
    local fobj = node.font or NOTE_FONT
    ns.SetFontObject(w.text, fobj)
    ns.SetFontSize(w.text, NoteSize(node.font, node.fontSize))
    w.text:SetText(body)
    -- `color` may be a FUNCTION, so a note can wear a skin token rather
    -- than a copy of one: a literal table is read once at build time and
    -- then drifts the moment the reader repaints that token.
    local col = node.color
    if type(col) == "function" then col = col(node, ctx) end
    w.text:SetTextColor(C(col or skin.textNote or skin.textMuted, 1, 1))
    -- The frame's width was SET by the layout, not derived, so it is
    -- readable now -- unlike the anchor-derived width the string had.
    w.text:SetWidth(math.max(1, w:GetWidth()))

    local path, iw, ih = NoteImage(node)
    if path then
        -- Measured from the STRING, the same quantity measure() got from
        -- its hidden FontString at the same width and font. The two have to
        -- agree: a picture placed lower than the row was measured for is a
        -- picture drawn over whatever comes next.
        local drop = NoteImageDrop(body, w.text:GetStringHeight() or 0)
        w.img:SetTexture(path)
        w.img:SetSize(iw, ih)
        w.img:ClearAllPoints()
        w.img:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -drop)
        w.img:Show()
        w:SetHeight(math.max(16, drop + ih + 4))
        return
    end

    -- Pooled: a note reused for a field with no picture must lose the one
    -- the last field gave it.
    w.img:Hide()
    if node.compact then
        w:SetHeight(math.max(1, w.text:GetStringHeight() or 1))
    else
        w:SetHeight(math.max(16, w.text:GetStringHeight() + 4))
    end
end

-- One hidden FontString, reused, purely to ask how tall some text will be
-- at a given width. It has to be a real FontString: the height depends on
-- the font, the wrap points and the line spacing, and estimating it from
-- the character count is wrong the moment a note has more than one
-- paragraph.
-- One per FONT, not one in total: a note that asks for a heading face
-- measured against the body face comes back a line short and draws over
-- whatever follows it.
local measureFS = {}
local function WrappedHeight(text, width, font, size)
    -- The same size refresh will draw at, resolved the same way (NoteSize):
    -- the note's own if it states one, else its named font's, else the
    -- library default. Measuring at one size and drawing at another
    -- reserves the wrong height for the row.
    size = NoteSize(font, size)
    font = font or NOTE_FONT
    -- Keyed by font AND size: a note drawn at a size of its own is measured
    -- at that size, or the row is reserved for the font's own and the
    -- string is drawn into the wrong height.
    local key = font .. "#" .. tostring(size or "")
    local fs = measureFS[key]
    if not fs then
        fs = ns.FS(UIParent, "BACKGROUND", font)
        fs:SetWordWrap(true)
        fs:Hide()
        measureFS[key] = fs
    end
    -- Re-stated on every use, not only at creation: these strings are
    -- tracked, so a face change under an open panel re-points them, and a
    -- size set once at birth is a size nothing puts back.
    ns.SetFontSize(fs, size)
    fs:SetWidth(math.max(1, width or 1))
    fs:SetText(text or "")
    return fs:GetStringHeight() or 16
end

-- A note always takes the whole row: FieldMetrics clamps 9999 to the row
-- width, and minimum matches so it never shares a line.
--
-- Its HEIGHT is measured, not assumed. It used to return a flat 20 -- one
-- line -- so a note that wrapped to three lines was given the space for
-- one, and the rest of it drew over whatever came next.
function note.measure(node, contentW, ctx)
    -- Resolved, not raw: `text` may be a function, and handing one to
    -- SetText is an error rather than a silent miss. measure runs BEFORE
    -- the widget exists, so this is the one path that cannot go through the
    -- widget -- it has to resolve the value itself.
    local body = NoteText(node, ctx)
    local textH = WrappedHeight(body, contentW or 400, node.font, node.fontSize)
    local path, _, ih = NoteImage(node)
    if path then
        -- The picture's own height, plus the text above it if there is any.
        -- Same arithmetic refresh does, from the same two numbers.
        return 9999, 9999, math.max(20, NoteImageDrop(body, textH) + ih + 4)
    end
    -- `compact`: the string's own height and nothing more. A note is
    -- normally at least a control's row tall with a few pixels under it --
    -- it sits among controls and should not read as crammed between them --
    -- but a note used as a HEADING or a caption in a band is a line of
    -- text, and that floor is then a gap nobody asked for.
    if node.compact then return 9999, 9999, math.max(1, textH) end
    return 9999, 9999, math.max(20, textH + 4)
end
note.stretch = false


-- ── list (removable items, as rows or as chips) ────────────────
--
-- A read-only list of things the page HOLDS -- the presets a container
-- carries, the spells on a whitelist -- each with an X that takes it out.
-- It is not a value: nothing binds to it, and it stores nothing. `items`
-- (a table, or a function asked on every render) supplies the rows, and
-- `onRemove(item, ctx, node)` is what the X calls. Whatever it changes, the
-- caller refreshes the page afterwards, exactly as a Remove button would.
--
--   { control = "list",
--     items    = function() return { { value = "a", text = "Alpha",
--                                      tooltip = "…" } } end,
--     onRemove = function(item, ctx) … end,
--     layout   = "rows" | "inline",   -- default rows
--     emptyText = "Nothing here yet." }
--
-- ROWS puts one item per line with a bordered danger X at the left -- the
-- collection's corner X, one per row. INLINE packs the items as chips that
-- flow left to right and wrap, each a small button with a plain X glyph at
-- its left edge -- the text field's clear X, muted until hovered, with no
-- border or fill of its own -- for a list that should take as little room
-- as a row of buttons.

local list = {}

local LIST_ROW_H   = 20    -- one row, both layouts
local LIST_GAP_Y   = 4     -- between rows
local LIST_GAP_X   = 6     -- between chips
local LIST_X_SIDE  = 18    -- the rows layout's bordered X
local LIST_GLYPH   = 8     -- the x.tga art, both layouts
local LIST_CHIP_PAD = 8    -- chip: edge to glyph, and text to edge

local function ListItems(node, ctx)
    local it = node.items
    if type(it) == "function" then
        -- pcall for the same reason NoteText does: this runs during LAYOUT,
        -- and an error thrown mid-layout takes the whole page down.
        local ok, out = pcall(it, node, ctx)
        if not ok then
            -- BUT IT IS REPORTED. Swallowing it turned a broken items
            -- function into an empty list -- a card that draws its Add
            -- control and nothing else, with no error, nothing in the log
            -- and no way to tell "nothing to show" from "the code that says
            -- what to show is broken". The layout still survives (the list
            -- comes back empty either way); the error now reaches the
            -- client's handler, once, like any other addon error.
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(out) end
            out = nil
        end
        it = out
    end
    return type(it) == "table" and it or {}
end

local function ListInline(node) return node.layout == "inline" end

local function ItemText(item)
    if type(item) ~= "table" then return tostring(item) end
    return tostring(item.text or item.value or "")
end

-- One hidden FontString per font, to ask how wide a chip's caption is.
-- Escape codes take no width, so a count of characters is wrong for any
-- colored label -- and a chip that is measured narrow clips its text.
local listMeasureFS = {}
local function TextWidth(text, font)
    local fs = listMeasureFS[font]
    if not fs then
        fs = ns.FS(UIParent, "BACKGROUND", font)
        fs:Hide()
        listMeasureFS[font] = fs
    end
    fs:SetText(text or "")
    return fs:GetStringWidth() or 0
end

local LIST_FONT = "GameFontHighlightSmall"

local function ChipWidth(text)
    return LIST_CHIP_PAD + LIST_GLYPH + 5 + TextWidth(text, LIST_FONT) + LIST_CHIP_PAD
end

-- The chip flow, shared by measure and refresh so the height the layout
-- reserves is the height the paint uses. Returns the rows as lists of
-- { item, width }.
local function ChipRows(items, contentW)
    local rows, row, used = {}, {}, 0
    for i = 1, #items do
        local wdt = math.min(contentW, ChipWidth(ItemText(items[i])))
        if #row > 0 and used + LIST_GAP_X + wdt > contentW then
            rows[#rows + 1] = row
            row, used = {}, 0
        end
        row[#row + 1] = { item = items[i], width = wdt }
        used = used + (#row > 1 and LIST_GAP_X or 0) + wdt
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
end

function list.create(app, parent)
    local w = CreateFrame("Frame", nil, parent)
    w.rowPool, w.chipPool = {}, {}
    w.empty = ns.FS(w, "OVERLAY", NOTE_FONT)
    w.empty:SetPoint("TOPLEFT")
    w.empty:SetJustifyH("LEFT")
    w.empty:SetWordWrap(true)
    w.empty:Hide()
    return w
end

-- A ROW: the bordered X and the caption beside it. The X is the attach
-- layer's corner button, drawn here as a child so it is pooled with the row.
local function EnsureRow(w, i)
    local r = w.rowPool[i]
    if r then return r end
    r = CreateFrame("Frame", nil, w)
    r:SetHeight(LIST_ROW_H)
    local b = CreateFrame("Button", nil, r)
    b:SetSize(LIST_X_SIDE, LIST_X_SIDE)
    b:SetPoint("LEFT", 0, 0)
    b.ring, b.bg = ns.BorderedRound(b, 6, "BACKGROUND", "BORDER")
    ns.SetBorder(b, b.ring)
    b.art = b:CreateTexture(nil, "OVERLAY")
    b.art:SetTexture(MEDIA .. "x.tga")
    b.art:SetSize(LIST_GLYPH, LIST_GLYPH)
    b.art:SetPoint("CENTER")
    -- Its own tooltip, not the field's: the X says what it removes.
    b.bpTipOwn = true
    r.x = b
    r.text = ns.FS(r, "OVERLAY", LIST_FONT)
    -- LEFT only, with the width SET in refresh. Anchored LEFT *and* RIGHT
    -- the string derives its width from the row, the row derives its own
    -- from the list frame, and the list frame is sized by the layout on the
    -- very render that builds all three -- so at paint time the chain has
    -- no resolved width and the caption draws as nothing. The note control
    -- learned this first; see the anchor note in note.create.
    r.text:SetPoint("LEFT", b, "RIGHT", 7, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    w.rowPool[i] = r
    return r
end

-- A CHIP: one button, the glyph at its left, the caption after it. The
-- whole chip is the target, as a button's whole surface is.
local function EnsureChip(w, i)
    local c = w.chipPool[i]
    if c then return c end
    c = CreateFrame("Button", nil, w)
    c:SetHeight(LIST_ROW_H)
    local ringPaint = ns.RoundedFill(c, "BACKGROUND", 6, nil, { 0, 0, 0, 0 }, 0)
    local bgPaint   = ns.StrokedFill(c, "BORDER",     6, nil, { 0, 0, 0, 0 }, "control")
    c.bgPaint = bgPaint
    c.ring    = PaintAsTexture(ringPaint)
    ns.SetBorder(c, c.ring)
    c.art = c:CreateTexture(nil, "OVERLAY")
    c.art:SetTexture(MEDIA .. "x.tga")
    c.art:SetSize(LIST_GLYPH, LIST_GLYPH)
    c.art:SetPoint("LEFT", LIST_CHIP_PAD, 0)
    c.text = ns.FS(c, "OVERLAY", LIST_FONT)
    -- LEFT only, width set in refresh -- the row's rule, for the row's
    -- reason: a caption whose width is derived from a chip that is itself
    -- being sized on this very render has no width to draw in yet.
    c.text:SetPoint("LEFT", c.art, "RIGHT", 5, 0)
    c.text:SetJustifyH("LEFT")
    c.text:SetWordWrap(false)
    c.bpTipOwn = true
    w.chipPool[i] = c
    return c
end

local function ItemTip(node, item)
    if type(item) ~= "table" then return nil, nil end
    local tip = item.tooltip or item.desc
    if type(tip) == "function" then tip = tip(item) end
    return item.tooltipTitle or ItemText(item), tip or node.removeTooltip or "Remove"
end

local function WireRemove(target, w, node, ctx, item)
    target:SetScript("OnClick", function()
        if ns.IsDisabled(node, ctx) then return end
        if node.onRemove then node.onRemove(item, ctx, node) end
    end)
    local title, tip = ItemTip(node, item)
    ns.context.AttachOwnTooltip(target, ctx.app, title, tip)
end

function list.apply(w, node, ctx)
    -- Re-wired on every render: the items are read afresh, and a pooled
    -- widget's rows may belong to a different field's list by now.
    local items  = ListItems(node, ctx)
    local inline = ListInline(node)
    local skin   = ctx.app.skin
    for i = 1, #w.rowPool  do w.rowPool[i]:Hide()  end
    for i = 1, #w.chipPool do w.chipPool[i]:Hide() end
    w.empty:Hide()
    w.items, w.inline = items, inline

    if inline then
        for i = 1, #items do
            local c = EnsureChip(w, i)
            c.text:SetText(ns.search.Mark(ctx.app, ItemText(items[i])))
            -- The fill lifts on hover as the button's does; the glyph goes
            -- to the accent as the text field's clear X does.
            c.bpOnHover = function(self, hovered)
                local a = hovered and skin.accent or skin.textMuted
                self.art:SetVertexColor(a[1], a[2], a[3], 1)
                self.bgPaint({ C(skin.controlBg, hovered and 2.2 or 1, 1) })
            end
            -- Hover first, tooltip second: the tooltip HOOKS OnEnter, and
            -- the hover SETS it, so the order is load-bearing.
            ns.InstallHover(c, c, node, ctx)
            WireRemove(c, w, node, ctx, items[i])
            c:Show()
        end
    else
        for i = 1, #items do
            local r = EnsureRow(w, i)
            r.text:SetText(ns.search.Mark(ctx.app, ItemText(items[i])))
            r.x.bpOnHover = function(self, hovered)
                local m = hovered and 1.25 or 0.85
                local d = skin.danger
                self.art:SetVertexColor(math.min(1, d[1] * m),
                    math.min(1, d[2] * m), math.min(1, d[3] * m), 1)
            end
            ns.InstallHover(r.x, r.x, node, ctx)
            WireRemove(r.x, w, node, ctx, items[i])
            r:Show()
        end
    end
    if #items == 0 and node.emptyText then
        w.empty:SetText(tostring(node.emptyText))
        w.empty:Show()
    end
    -- Re-flow the chips if the row is resized under us.
    w:SetScript("OnSizeChanged", function(self)
        if self.inline then list.refresh(self, node, ctx) end
    end)
end

function list.refresh(w, node, ctx)
    local skin  = ctx.app.skin
    local off   = ns.IsDisabled(node, ctx)
    local a     = off and 0.4 or 1
    local items = w.items or {}
    local width = math.max(1, w:GetWidth())
    local t     = skin.text

    -- THE LIST FRAME'S OWN HEIGHT.
    --
    -- The layout sets a control's width and leaves its height to the
    -- control, because every other control has a fixed one it sets at
    -- create. This one's height is its content, and nothing was setting it
    -- -- the frame stayed 0 tall however many rows it held, so the rows
    -- hung off a parent with no rect. The number is the one `measure`
    -- reserved space for, computed the same way.
    local rowCount = #items
    if rowCount > 0 then
        w:SetHeight(rowCount * LIST_ROW_H + (rowCount - 1) * LIST_GAP_Y)
    else
        w:SetHeight(LIST_ROW_H)
    end

    if w.inline then
        local rows = ChipRows(items, width)
        local n, y = 0, 0
        for ri = 1, #rows do
            local x = 0
            for ci = 1, #rows[ri] do
                n = n + 1
                local c = w.chipPool[n]
                if c then
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y)
                    c:SetWidth(rows[ri][ci].width)
                    c.text:SetWidth(math.max(1, rows[ri][ci].width
                        - LIST_CHIP_PAD - LIST_GLYPH - 5 - LIST_CHIP_PAD))
                    c.bgPaint({ C(skin.controlBg, 1, a) })
                    ns.MarkBorder(c, skin, skin.controlBorder, a)
                    c.text:SetTextColor(C(t, 1, a))
                    local m = skin.textMuted
                    c.art:SetVertexColor(m[1], m[2], m[3], a)
                    c:SetEnabled(not off)
                    x = x + rows[ri][ci].width + LIST_GAP_X
                end
            end
            y = y + LIST_ROW_H + LIST_GAP_Y
        end
        -- The wrapped chip flow's real height, for the same reason.
        if #rows > 0 then
            w:SetHeight(#rows * LIST_ROW_H + (#rows - 1) * LIST_GAP_Y)
        end
    else
        for i = 1, #items do
            local r = w.rowPool[i]
            if r then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -((i - 1) * (LIST_ROW_H + LIST_GAP_Y)))
                -- SIZED, not anchored to the list's right edge: see the note
                -- on r.text in EnsureRow. The caption's width is set from
                -- the same number, so neither depends on a rect that does
                -- not exist yet.
                r:SetSize(width, LIST_ROW_H)
                r.text:SetWidth(math.max(1, width - LIST_X_SIDE - 7))
                r.x.bg:SetVertexColor(skin.controlBg[1], skin.controlBg[2], skin.controlBg[3], a)
                ns.MarkBorder(r.x, skin, skin.danger, a)
                local d = skin.danger
                r.x.art:SetVertexColor(d[1] * 0.85, d[2] * 0.85, d[3] * 0.85, a)
                r.text:SetTextColor(C(t, 1, a))
                r.x:SetEnabled(not off)
            end
        end
    end
    if w.empty:IsShown() then
        w.empty:SetWidth(width)
        w.empty:SetTextColor(C(skin.textNote or skin.textMuted, 1, 1))
    end

end

function list.measure(node, contentW, ctx)
    local items = ListItems(node, ctx)
    local h
    if #items == 0 then
        h = node.emptyText
            and (WrappedHeight(tostring(node.emptyText), contentW or 400) + 4)
            or 0
    elseif ListInline(node) then
        local rows = ChipRows(items, contentW or 400)
        h = #rows * LIST_ROW_H + (#rows - 1) * LIST_GAP_Y
        -- 2026-09-14: an inline list asks for the width its chips need on
        -- ONE line, not the row. Asking for the row (9999, as the rows
        -- layout does) forced a handful of chips onto a line of their own
        -- under the control that adds them; sized to the chips, the packer
        -- sets them beside it when they fit and wraps them to a new line
        -- only when they do not. Capped at the row, and then the chip flow
        -- above -- measured at that same width -- is what the paint draws.
        -- Preferred == minimum: the list is not stretchy and must not be
        -- shrunk under its chips, so a line that cannot pay wraps instead.
        if #rows == 1 then
            local wdt = 0
            local row = rows[1]
            for i = 1, #row do
                wdt = wdt + (i > 1 and LIST_GAP_X or 0) + row[i].width
            end
            wdt = math.ceil(math.min(wdt, contentW or 400))
            return wdt, wdt, math.max(1, h)
        end
    else
        h = #items * LIST_ROW_H + (#items - 1) * LIST_GAP_Y
    end
    return 9999, 9999, math.max(1, h)
end
list.stretch  = false
-- The list has no caption of its own to draw above it: the card's title
-- names it, and a label would be a second heading.
list.ownLabel = true

local B = ns.builtinControls
B.dropdown    = dropdown
B.select      = dropdown
B.multiselect = multiselect
B.segmented = segmented
B.color     = color
B.text      = textinput
B.input     = textinput
B.search    = searchinput
B.button    = button
B.keybind   = keybind
B.keybinding = keybind
B.note      = note
B.list      = list
