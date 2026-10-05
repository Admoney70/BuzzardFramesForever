-- ============================================================
-- BuzzardPanel: Chrome.lua
-- Footer slots, the breadcrumb, and the first two controls.
--
-- Footer slots are the bottom-of-the-rail stack: any number of slots,
-- each a horizontal strip of one or more cells with flex weights. The
-- library computes the footer height from the declaration and tells the
-- frame, so adding a slot re-flows the rail with no other change.
--
-- navbutton and navmenu are the first real controls, and therefore the
-- first exercise of the per-app pool. They are deliberately plain: P0.3
-- brings the native-template wrapping and the style-preset system.
-- ============================================================
local ADDON, ns = ...

ns.chrome = {}

local SLOT_HEIGHT   = 26
local SLOT_GAP      = 5
local FOOTER_PAD    = 7

-- ── Cell factories ─────────────────────────────────────────────

local function CellFactory(app)
    local b = CreateFrame("Button", nil, app:GetRegion("footer"))
    b:SetHeight(SLOT_HEIGHT)

    -- Rounded, like every other bordered surface in the panel. This used to
    -- be a flat fill with four 1px edge textures, which is the one square
    -- corner left in the UI once the controls were done.
    --
    -- Radius 8, the CONTROL radius, not the 6 it wore: these cells sit a few
    -- pixels from the panel's own buttons and read as the same kind of
    -- thing, so a rounder corner on one of them read as a mistake. Their
    -- border color is the control token too -- see PaintCell.
    b.border, b.bg = ns.BorderedRound(b, 8, "BACKGROUND", "BORDER")
    -- The relief every button wears (ns.ButtonFace), so these cells and
    -- the page's buttons read as the same kind of thing. Rounded style
    -- only; the square bar is a divided strip, not a row of buttons.
    b.face = ns.ButtonFace(b, "ARTWORK", 8, "control")

    -- Square style: one flat fill covering the whole cell, and a rule on
    -- its right edge dividing it from the next.
    b.flat = b:CreateTexture(nil, "BORDER")
    b.flat:SetAllPoints(b)
    b.flat:Hide()
    -- Full height, both of them. An inset rule floats inside the cell and
    -- reads as decoration; a rule that meets the bar's edges reads as the
    -- bar being divided, which is the whole point of the style.
    b.sep = b:CreateTexture(nil, "OVERLAY")
    b.sep:SetWidth(1)
    b.sep:SetPoint("TOPRIGHT",    b, "TOPRIGHT",    0, 0)
    b.sep:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.sep:Hide()

    -- And the horizontal one, on a cell in any row but the top: without it
    -- a wrapped square bar is rows of divided buttons floating over the
    -- panel rather than one grid.
    b.hsep = b:CreateTexture(nil, "OVERLAY")
    b.hsep:SetHeight(1)
    b.hsep:SetPoint("TOPLEFT",  b, "TOPLEFT",  0, 0)
    b.hsep:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.hsep:Hide()

    -- Bounded to the cell and non-wrapping, so a label that is too long for
    -- its cell is truncated rather than spilling over its neighbors.
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    -- A caption at the button size, as the page's own buttons are: these
    -- cells ARE buttons, and the two sat side by side at different sizes.
    ns.SetFontSize(b.label, (app.skin and app.skin.buttonFontSize) or 12)
    b.label:SetPoint("LEFT",  b, "LEFT",   4, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    return b
end

-- Two styles for the same cell.
--
--   "rounded"  the default: each button is its own bordered card, so the
--              bar reads as a row of separate things.
--   "square"   no card at all. The buttons abut, a 1px rule divides them,
--              and each one's fill is the whole of its share of the bar --
--              so the bar reads as one strip that has been divided rather
--              than as several objects that happen to be adjacent.
--
-- The difference is which textures are shown; the geometry differs only in
-- that square mode closes the gap between cells to nothing, because a gap
-- is exactly what stops them reading as one strip.
local function PaintCell(app, b, cell, on, enabled, hovered, square)
    local skin = app.skin
    local fill = square and b.flat or b.bg
    if square then
        b.border:Hide(); b.bg:Hide(); b.flat:Show()
        if b.face then b.face:Hide() end
    else
        b.border:Show(); b.bg:Show(); b.flat:Hide()
        if b.face then b.face:SetVertexColor(1, 1, 1, ns.FaceAlpha(skin, 1)) end
    end
    if on then
        local ac, ad = skin.accent, skin.accentDim
        if not square then b.border:SetVertexColor(ac[1], ac[2], ac[3], 0.75) end
        fill:SetVertexColor(ad[1], ad[2], ad[3], (ad[4] or 0.18) + (square and 0.10 or 0))
        b.label:SetTextColor(math.min(1, ac[1] + 0.45), math.min(1, ac[2] + 0.25),
                             math.min(1, ac[3] + 0.1))
    else
        -- The CONTROL border, not the rail's: a cell is a button, and the
        -- rail token is a quarter-strength line meant for the tree's own
        -- edges -- which is why these read as a different kind of button
        -- from the ones on the page. The fill stays the rail's, since the
        -- cell sits on the rail rather than in a card.
        -- The NAV pair: these three cells are the panel's navigation
        -- buttons, and they are the one set a reader may want to tell apart
        -- from the page's own. Shipped at the rail's color, which is what
        -- they wore before the token existed.
        local bg = skin.buttonNavBg or skin.railBg
        local lift = hovered and enabled and 0.09 or 0.04
        fill:SetVertexColor(bg[1] + lift, bg[2] + lift, bg[3] + lift, 1)
        -- The accent border at rest and brighter under the mouse, and the
        -- label at full strength (owner, 2026-09-15) -- the same rule the
        -- top strip's nav-style buttons follow, so the two rows of buttons
        -- read as one set. A disabled cell keeps the resting border and
        -- the muted label.
        if not square then
            local ac = skin.accent
            local a = (hovered and enabled) and (skin.navBorderHoverAlpha or 0.90)
                      or (skin.navBorderAlpha or 0.45)
            b.border:SetVertexColor(ac[1], ac[2], ac[3], a)
        end
        local c = enabled and (skin.buttonNavText or skin.text) or skin.textMuted
        b.label:SetTextColor(c[1], c[2], c[3])
    end
end

-- ── Footer slots ───────────────────────────────────────────────

-- opts = { span = "rail" | "full", maxRows = n }
--
-- `span` borrows the status strip's vocabulary: "rail" (the default) keeps
-- the buttons under the tree where they have always been, "full" runs them
-- across the whole panel above the status strip, with the rail and the page
-- both stopping above them.
--
-- `style` is "rounded" (the default: each button its own bordered card) or
-- "square" (the buttons abut, a 1px rule divides them, and each fill is the
-- whole of its share of the bar).
--
-- `maxRows` caps how far a slot may wrap. Unset, a slot takes as many rows
-- as its buttons genuinely need. At 1 it stays one row whatever it costs:
-- the widths no longer fit, the row clamp scales them down, and the labels
-- truncate inside their cells -- which they are already set up to do, being
-- bounded and non-wrapping.
function ns.chrome.SetNavFooter(app, slots, opts)
    app.footerSlots = slots or {}
    app.footerSpan  = (opts and opts.span) or "rail"
    app.footerStyle = (opts and opts.style) or "rounded"
    app.footerMaxRows = opts and opts.maxRows or nil
    local n = #app.footerSlots
    app.footerHeight = (n > 0) and (n * SLOT_HEIGHT + (n - 1) * SLOT_GAP + FOOTER_PAD * 2) or 0
    if app.frame then
        ns.LayoutRegions(app)
        ns.chrome.RenderFooter(app)
    end
end

-- ── Status strip ───────────────────────────────────────────────
--
-- The bottom strip. `statusbar` has existed as a region since P0.1 -- full
-- width, its own background, a divider along the top -- with nothing ever
-- rendered into it and a fixed height. This is the content.
--
-- A row of cells with flex weights, like a footer slot, but TEXT by
-- default: a status line reports, it does not offer. A cell grows a hover
-- and a click target only if it declares onClick, so the common case --
-- "this is the layout you are editing" -- does not arrive wearing button
-- chrome it never asked for.
--
-- `text` may be a function, and it is called on every render rather than
-- pushed in. That is the difference between a status line that is right and
-- one that was right when somebody last remembered to update it.

local STATUS_PAD = 8
-- The strip is the bottom-most region in both span modes, so its right end
-- runs into the resize grip in the corner. The grip is 16 wide and inset by
-- two; the cells stop clear of it rather than under it.
local STATUS_GRIP = 20

-- The gap between chained status cells, and the space a cell's optional
-- divider is drawn in. Declared ABOVE its first use: a local defined later
-- is not an upvalue at all -- the reference compiles to a global lookup and
-- finds nil, which is exactly how this file threw on its first render.
local CELL_GAP = 10

-- ── A cell's own menu ──────────────────────────────────────────
--
-- A footer or status cell may carry `items`: the library's own menu (a
-- list, or a function returning one, so it can be built from live state)
-- with `menuStyle` for its look and direction. Both bars sit at the BOTTOM
-- of the panel, so a cell's menu opens upwards by default rather than
-- waiting to be pushed there by the edge of the screen -- `menuStyle.grow`
-- overrides that like any other knob.
--
-- The bar re-renders when the menu CLOSES, not on the click that opened it
-- and not on a pick: a cell's label often reads from what the menu changes,
-- but re-rendering while the menu is up would release the very button it is
-- anchored to. The style table is copied rather than added to, because it
-- usually belongs to the caller and is shared across renders.
local function OpenCellMenu(app, cell, anchor, after)
    local items = cell.items
    if type(items) == "function" then items = items(app) end
    if not items or #items == 0 then return end

    local style = {}
    if cell.menuStyle then
        for k, v in pairs(cell.menuStyle) do style[k] = v end
    end
    if style.grow == nil then style.grow = "up" end
    -- The cell's identity, so the menu can find its anchor again after a
    -- re-render has released and re-acquired the pooled cell frames.
    local key = cell.menuKey or cell.label or cell.text
    if type(key) == "function" then
        local ok, out = pcall(key, cell, app)
        key = ok and out or nil
    end
    if style.ownerKey == nil then style.ownerKey = key end
    if after then
        local prior = style.onClose
        style.onClose = function()
            if prior then prior() end
            after()
        end
    end
    ns.ShowMenu(anchor, app, items, style)
end

local function StatusCellFactory(app)
    local f = CreateFrame("Button", nil, app:GetRegion("statusbar"))
    -- An optional rule AFTER the cell, for a strip that carries two kinds
    -- of thing: a group of buttons and then a status line, say. Drawn in
    -- the gap rather than inside either cell, so it separates them instead
    -- of belonging to one.
    f.div = f:CreateTexture(nil, "OVERLAY")
    f.div:SetWidth(1)
    f.div:SetPoint("TOP",    f, "TOPRIGHT",    CELL_GAP / 2, -3)
    f.div:SetPoint("BOTTOM", f, "BOTTOMRIGHT", CELL_GAP / 2,  3)
    f.div:Hide()
    -- Square style's own fill and full-height rules; see ns.AttachSquare.
    ns.AttachSquare(f)
    f.label = ns.FS(f, "OVERLAY", "GameFontNormalSmall")
    -- The same size every button caption draws at -- a status cell can
    -- act as a button, and sat beside the footer cells at a smaller size.
    ns.SetFontSize(f.label, (app.skin and app.skin.buttonFontSize) or 12)
    f.label:SetPoint("LEFT",  f, "LEFT",  0, 0)
    f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.label:SetWordWrap(false)
    return f
end

function ns.chrome.SetStatusBar(app, spec)
    app.statusSpec   = spec
    app.statusHeight = spec and spec.height or nil
    -- "full" crosses the whole panel below the rail's footer buttons;
    -- "body" starts at the rail's right edge and sits beside them.
    app.statusSpan   = spec and spec.span or "full"
    app.statusStyle  = spec and spec.style or "plain"
    -- One switch for the strip: declaring it shows it, clearing it hides
    -- it. SetStatusBarShown stays for an app that wants to toggle a
    -- declared strip without losing its declaration.
    app.statusbarShown = (spec ~= nil)
    if app.frame then
        ns.LayoutRegions(app)
        ns.chrome.RenderStatusBar(app)
    end
end

-- The strip lays itself out with ANCHORS, not with arithmetic.
--
-- Every cell used to be given a pixel width computed from the region's
-- width, which meant the strip only knew its shape at render time -- and
-- since a resize re-renders on a throttle rather than every frame, the
-- right-hand cell chased the frame's edge in visible steps while the grip,
-- anchored to the corner, tracked it perfectly. The fix is to stop
-- computing and start anchoring, so the C side resolves the layout on every
-- frame for free, exactly as it does for the grip.
--
-- The shape: cells before the FILL cell chain left-to-right from the
-- region's left edge; cells after it chain right-to-left from the right
-- edge, in declaration order; the fill cell takes both anchors and absorbs
-- whatever is left. Each chained cell is as wide as its own text, which
-- depends on the text rather than on the panel, so nothing here moves when
-- the panel is resized.
--
-- `flex` no longer means anything: a proportional width is precisely the
-- thing that cannot be anchored, and it was the source of the jitter.

-- The fill cell cannot come from the pool.
--
-- It is defined by two horizontal anchors, and an explicit SetWidth beats
-- a width derived from two anchors -- the bug that made the search box
-- refuse to center. A pooled frame may carry a width from an earlier use
-- as an ordinary cell, so the fill cell is its own frame, held on the app,
-- created once and never given a width.
local function FillCell(app)
    if not app.statusFill then
        app.statusFill = StatusCellFactory(app)
    end
    return app.statusFill
end

function ns.chrome.RenderStatusBar(app)
    if not app.frame then return end
    local region = app:GetRegion("statusbar")
    local spec   = app.statusSpec
    app.statusCells = app.statusCells or {}

    if not spec then
        for _, c in ipairs(app.statusCells) do app:Release(c) end
        wipe(app.statusCells)
        if app.statusFill then app.statusFill:Hide() end
        return
    end

    local skin   = app.skin
    local cells  = spec.cells or {}

    -- Square style: the cells fill the strip's whole height and abut, with
    -- a rule where they meet. Plain style (the default) is what the strip
    -- has always been -- text on the panel, with an optional divider after
    -- a cell that asks for one.
    local square = (app.statusStyle == "square")
    local pad    = square and 0 or STATUS_PAD
    local cgap   = square and 0 or CELL_GAP
    local height = (app.statusHeight or skin.statusbarHeight) - (square and 0 or 2)

    -- Exactly one cell absorbs the slack. Unset, it is the first: a strip
    -- almost always opens with the wide "what am I looking at" line.
    local fillAt = 1
    for i, cell in ipairs(cells) do
        if cell.fill then fillAt = i; break end
    end

    -- One pass to give every cell its content, then a second to place
    -- them: the chained cells are sized from their own text, so the text
    -- has to be set before any width can be known.
    -- The pooled cells are kept DENSE and consumed in order, because the
    -- fill cell is not one of them: indexing the pool by the cell's own
    -- index would leave a hole at fillAt, and the release sweep below
    -- counts on a list with no holes in it.
    local frames, pooled = {}, 0
    for i, cell in ipairs(cells) do
        local f
        if i == fillAt then
            f = FillCell(app)
        else
            pooled = pooled + 1
            f = app.statusCells[pooled]
            if not f then
                f = app:Acquire("statusCell", StatusCellFactory)
                app.statusCells[pooled] = f
            end
        end
        frames[i] = f
        f:SetParent(region)
        f:ClearAllPoints()
        f:SetHeight(height)

        local text = cell.text
        if type(text) == "function" then
            local ok, out = pcall(text, cell, app)
            text = ok and out or ""
        end
        f.label:SetText(tostring(text or ""))
        f.label:SetJustifyH(cell.justify or "LEFT")
        if ns.RebindOpenMenu then
            local mk = cell.menuKey
            if mk == nil then mk = cell.label or cell.text end
            if type(mk) == "function" then mk = text end
            ns.RebindOpenMenu(f, mk)
        end

        -- `color` resolves like `text` does, and `toggled` wins over it:
        -- a cell standing for a mode that is currently on paints in the
        -- accent, the same signal a nav-footer cell gives. Both may be
        -- functions, so a cell reports what is true NOW rather than what
        -- was true when the strip was declared.
        local c = cell.color
        if type(c) == "function" then
            local ok, out = pcall(c, cell, app)
            c = ok and out or nil
        end
        local on = cell.toggled
        if type(on) == "function" then
            local ok, out = pcall(on, cell, app)
            on = ok and out or false
        end
        c = (on and skin.accent) or c or skin.textNote or skin.textMuted
        f.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)

        -- In square style every cell but the last carries its rule, and the
        -- per-cell `divider` is not needed: the strip is divided already.
        if square then
            f.div:Hide()
            ns.PaintSquare(f, skin, true, {
                fill  = on and skin.accentDim or skin.statusbarBg,
                -- Closed at the END, open at the start: the strip always
                -- begins at the panel's own edge, and that edge is already
                -- the divider. A rule there would be a second line against
                -- the first.
                right = true,
            })
        else
            ns.PaintSquare(f, skin, false)
            if cell.divider then
                local d = skin.divider
                f.div:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
                if ns.NoSnap then ns.NoSnap(f.div) end
                f.div:Show()
            else
                f.div:Hide()
            end
        end

        -- Interactive only on request.
        if cell.onClick or cell.items then
            f:EnableMouse(true)
            f:SetScript("OnClick", function()
                if cell.items then
                    OpenCellMenu(app, cell, f,
                        function() ns.chrome.RenderStatusBar(app) end)
                elseif cell.onClick then
                    cell.onClick(cell, app)
                end
            end)
            f:SetScript("OnEnter", function()
                local a = skin.accent
                f.label:SetTextColor(a[1], a[2], a[3], 1)
                if cell.tooltip then ns.context.Show(f, app, cell.tooltip) end
            end)
            f:SetScript("OnLeave", function()
                f.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                ns.context.Hide()
            end)
        else
            f:EnableMouse(false)
            f:SetScript("OnClick", nil)
            f:SetScript("OnEnter", nil)
            f:SetScript("OnLeave", nil)
        end
        f:Show()
    end

    -- Left chain, in order, from the region's left edge.
    local prev
    for i = 1, fillAt - 1 do
        local f = frames[i]
        f:SetWidth(math.max(1, math.ceil(f.label:GetStringWidth() + 2)))
        if prev then
            f:SetPoint("LEFT", prev, "RIGHT", cgap, 0)
        else
            f:SetPoint("LEFT", region, "LEFT", pad, 0)
        end
        prev = f
    end

    -- Right chain, walked backwards from the right edge so declaration
    -- order still reads left to right on screen.
    local nextF
    for i = #cells, fillAt + 1, -1 do
        local f = frames[i]
        f:SetWidth(math.max(1, math.ceil(f.label:GetStringWidth() + 2)))
        if nextF then
            f:SetPoint("RIGHT", nextF, "LEFT", -cgap, 0)
        else
            f:SetPoint("RIGHT", region, "RIGHT", -(pad + STATUS_GRIP), 0)
        end
        nextF = f
    end

    -- And the fill cell between them, by anchors alone.
    local fill = frames[fillAt]
    if fill then
        if prev then
            fill:SetPoint("LEFT", prev, "RIGHT", cgap, 0)
        else
            fill:SetPoint("LEFT", region, "LEFT", pad, 0)
        end
        if nextF then
            fill:SetPoint("RIGHT", nextF, "LEFT", -cgap, 0)
        else
            fill:SetPoint("RIGHT", region, "RIGHT", -(pad + STATUS_GRIP), 0)
        end
    elseif app.statusFill then
        app.statusFill:Hide()
    end

    for i = #app.statusCells, pooled + 1, -1 do
        app:Release(app.statusCells[i]); app.statusCells[i] = nil
    end
end

function ns.chrome.RenderFooter(app)
    if not app.frame then return end
    local skin   = app.skin

    -- Release last pass's cells first: this must happen even when there is
    -- no footer any more, or removing the footer would strand its widgets.
    for _, c in ipairs(app.footerCells or {}) do app:Release(c) end
    app.footerCells = app.footerCells or {}
    wipe(app.footerCells)

    -- No footer declared is a legitimate configuration, not an error.
    local slots = app.footerSlots
    if not slots or #slots == 0 then return end

    local footer = app:GetRegion("footer")

    -- Square cells abut, and they fill the band.
    --
    -- The gap between them is what would stop the bar reading as one
    -- divided strip, so there is none -- and neither is there padding
    -- around the band. A cell inset by 7px inside the footer leaves its
    -- dividing rules 7px short of the bar's own edges at top and bottom,
    -- which is what "the dividers do not span the full height" was: the
    -- rules did span their cell, and the cell did not span the bar. With
    -- the padding gone the cells run edge to edge in both directions, each
    -- row's top rules join into one continuous line across the whole bar,
    -- and the vertical ones meet the band's edges. Rounded style keeps its
    -- padding, because a card needs room to sit in.
    local square = (app.footerStyle == "square")
    local gap    = square and 0 or SLOT_GAP
    local pad    = square and 0 or FOOTER_PAD


    -- The footer's width, DERIVED rather than read.
    --
    -- footer:GetWidth() comes from anchors, and anchors resolve in a later
    -- layout pass -- so immediately after LayoutRegions it still reports
    -- the previous width. Every packing decision below was then correct
    -- arithmetic on a stale number, which is why three rounds of fixing the
    -- arithmetic did not stop buttons landing outside the bar. Same trap as
    -- the status strip (27.15) and the rail tree (27.17), in a third place.
    --
    -- The footer spans either the rail or the panel, and both of those
    -- widths are values this library computes rather than ones it reads
    -- back, so they are known now.
    local full
    if app.footerSpan == "full" then
        -- The panel's width is its own, set explicitly by RestoreGeometry
        -- and by the resize handles, so reading it is safe -- unlike a
        -- region's, which is anchor-derived. LayoutRegions insets the
        -- regions by zero today; the constant is named rather than assumed.
        full = (app.frame:GetWidth() or 0) - pad * 2
    else
        local railMin = math.max(skin.railWidthMin, app.footerMinWidth or 0)
        local railW  = math.max(railMin,
                       math.min(skin.railWidthMax, app.railWidth or skin.railWidth))
        full = railW - pad * 2
    end

    -- A slot WRAPS rather than overflowing.
    --
    -- Five buttons in a rail at its minimum width used to be five cells
    -- laid out past the rail's edge, because each was given at least 24px
    -- whether or not there was room. A slot is a row's worth of buttons
    -- that the reader asked for, not a promise that they fit on one line --
    -- the same rule the top button bar already follows.
    --
    -- The minimum is the cell's own LABEL plus padding, so "Compact" claims
    -- more than "Tree" and a row breaks where the words stop fitting rather
    -- than at an arbitrary count.
    local function MinWidth(cell)
        local label = cell.label
        if type(label) == "function" then label = label() end
        if cell.icon then label = cell.icon .. (label and (" " .. label) or "") end
        return math.max(44, #tostring(label or "") * 6.6 + 18)
    end

    -- How many rows a slot needs, packing greedily.
    local function RowsNeeded(cells)
        local n, used = 1, 0
        for _, cell in ipairs(cells) do
            local need = MinWidth(cell)
            if used > 0 and (used + gap + need) > full then
                n, used = n + 1, 0
            end
            used = used + need + (used > 0 and gap or 0)
        end
        return n
    end

    -- BALANCED by default, greedy on request.
    --
    -- Greedy packing puts as many buttons as fit on the first row and the
    -- remainder on the last, which for five buttons in a narrow rail is
    -- four small ones and then one the width of the whole footer. Nothing
    -- about that says "these are the same kind of thing". Splitting the
    -- cells evenly across the rows they need gives 3 and 2, and every
    -- button stays a plausible size.
    --
    -- `slot.wrap = "fill"` keeps the greedy shape for a slot that wants it
    -- -- a row of short toggles and one long action, say, where the long
    -- one having its own line is the point.
    local rows = {}
    for s = 1, #slots do
        local slot  = slots[s]
        local cells = slot.cells or {}
        if #cells == 0 then
            -- nothing to place
        elseif slot.wrap == "fill" then
            local row, used = {}, 0
            for _, cell in ipairs(cells) do
                local need = MinWidth(cell)
                if #row > 0 and (used + gap + need) > full then
                    rows[#rows + 1] = row
                    row, used = {}, 0
                end
                row[#row + 1] = cell
                used = used + need + (#row > 1 and gap or 0)
            end
            if #row > 0 then rows[#rows + 1] = row end
        else
            -- Split into `want` rows as evenly as possible, earlier rows
            -- taking the remainder -- a 5-into-2 split is 3 then 2 rather
            -- than 2 then 3, because the eye reads a footer top-down and a
            -- widening tail looks like a mistake.
            local function Split(want)
                local out = {}
                local base, extra = math.floor(#cells / want), #cells % want
                local i = 1
                for r = 1, want do
                    local take = base + ((r <= extra) and 1 or 0)
                    local row = {}
                    for _ = 1, take do row[#row + 1] = cells[i]; i = i + 1 end
                    if #row > 0 then out[#out + 1] = row end
                end
                return out
            end

            local function Fits(split)
                for _, row in ipairs(split) do
                    local need = gap * (#row - 1)
                    for _, cell in ipairs(row) do need = need + MinWidth(cell) end
                    if need > full then return false end
                end
                return true
            end

            -- A BALANCED split is not automatically a split that fits.
            --
            -- RowsNeeded counts rows by packing greedily, which puts the
            -- cells wherever they happen to land; balancing then moves them,
            -- and an even split of uneven buttons can put the two widest on
            -- one row. With minimums 64, 64, 44, 44, 44 and 150px of room,
            -- greedy needs two rows (2 then 3) and the balanced 3 then 2
            -- overruns the first -- which drives `spare` negative and lays
            -- the row out at its minimums, past the footer's edge.
            --
            -- So the row count grows until the balanced split fits: as
            -- balanced as it can be, and never wider than the room.
            local cap = slot.maxRows or app.footerMaxRows or #cells
            local want, split = math.min(RowsNeeded(cells), cap), nil
            repeat
                split = Split(want)
                -- The cap wins over fitting. At maxRows = 1 the caller has
                -- said "one row, whatever it costs" -- the row clamp below
                -- then scales the cells down and their labels truncate.
                if Fits(split) or want >= cap then break end
                want = want + 1
            until want > #cells
            for _, row in ipairs(split or {}) do rows[#rows + 1] = row end
        end
    end

    -- The narrowest the footer can be laid out in: the widest SINGLE cell,
    -- because that is the one thing no amount of wrapping can make smaller.
    -- LayoutRegions clamps the rail to it, so the rail cannot be dragged
    -- narrower than its own buttons need -- adaptive, rather than a
    -- constant in the skin that would be wrong for a footer with one short
    -- button and wrong again for one with four long ones.
    -- Only meaningful for a rail-span footer, and only when it is allowed
    -- to wrap: a capped footer has accepted that its cells may be squeezed,
    -- so it must not also force the rail wider.
    local widest = 0
    if app.footerSpan ~= "full" and not (app.footerMaxRows or slots[1] and slots[1].maxRows) then
        for _, slot in ipairs(slots) do
            for _, cell in ipairs(slot.cells or {}) do
                widest = math.max(widest, MinWidth(cell))
            end
        end
    end
    app.footerMinWidth = (widest > 0) and (widest + pad * 2) or 0

    -- The height follows the rows actually used, not the slots declared.
    -- Guarded, and re-laid-out only on a change, which is what keeps this
    -- from looping: LayoutRegions is what gives the footer the width this
    -- function just measured.
    local rowGap = square and 0 or SLOT_GAP
    local want = (#rows > 0)
                 and (#rows * SLOT_HEIGHT + (#rows - 1) * rowGap + pad * 2) or 0
    if (app.footerHeight or 0) ~= want then
        app.footerHeight = want
        ns.LayoutRegions(app)
    end

    local y = pad
    for s = #rows, 1, -1 do                       -- bottom-up
        local cells = rows[s]

        -- Minimums first, then flex over what is LEFT.
        --
        -- Sharing the whole row by flex and flooring each cell at its own
        -- minimum let the two disagree: at the rail's maximum width five
        -- buttons get a 57px share each while "Compact" needs 64, so that
        -- cell took its minimum and the row overran by the difference --
        -- pushing the last button onto the footer's right edge while the
        -- first still started at its padding, which is the uneven margin
        -- that got reported. The packer only ever checked that the SUM of
        -- the minimums fits, which it did.
        --
        -- Allocating minimums first makes the row total exactly `avail` by
        -- construction, so it cannot overrun and the margins are symmetric
        -- at any width. It also makes `flex` mean what it should: a
        -- weighting of the SPARE room, not of a row that includes space a
        -- label was always going to need.
        local totalFlex, minSum = 0, 0
        for _, cell in ipairs(cells) do
            totalFlex = totalFlex + (cell.flex or 1)
            minSum    = minSum + MinWidth(cell)
        end
        if totalFlex <= 0 then totalFlex = 1 end
        local avail = full - gap * (#cells - 1)
        local spare = math.max(0, avail - minSum)

        -- Whatever the packing decided, the row FITS.
        --
        -- Belt and braces on purpose: this is the last thing between a
        -- layout mistake and a button drawn outside its bar, and it costs
        -- one pass over a handful of cells. If the widths still sum past
        -- the row, every one of them is scaled down until they do -- labels
        -- truncate, which is what SetWordWrap(false) is for, and nothing
        -- escapes the footer.
        local widths, sum = {}, 0
        for i, cell in ipairs(cells) do
            widths[i] = MinWidth(cell) + spare * ((cell.flex or 1) / totalFlex)
            sum = sum + widths[i]
        end
        if sum > avail and sum > 0 then
            local k = avail / sum
            for i = 1, #widths do widths[i] = widths[i] * k end
        end

        local x = pad
        for ci, cell in ipairs(cells) do
            local b = app:Acquire("footerCell", CellFactory)
            b:SetParent(footer)
            b:ClearAllPoints()
            local w = widths[ci]
            b:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", x, y)
            b:SetWidth(w)
            b:Show()

            local label = cell.label
            if type(label) == "function" then label = label() end
            if cell.icon then label = cell.icon .. (label and (" " .. label) or "") end
            b.label:SetText(label or "")
            -- If this cell's menu is open, this frame is its anchor now --
            -- the frame it opened from may have been released just above.
            if ns.RebindOpenMenu then
                local mk = cell.menuKey
                if mk == nil then mk = cell.label end
                if type(mk) == "function" then mk = label end
                ns.RebindOpenMenu(b, mk)
            end

            local on = cell.toggled and cell.toggled() or false
            local enabled = true
            if cell.disabled == "combat" then
                enabled = not InCombatLockdown()
            elseif type(cell.disabled) == "function" then
                enabled = not cell.disabled()
            end
            b:SetEnabled(enabled)
            -- The rule sits on every cell but the row's last, so a row
            -- ends at the bar's edge rather than with a hanging line.
            local d = skin.divider
            b.sep:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
            if ns.NoSnap then ns.NoSnap(b.sep) end
            b.sep:SetShown(square and ci < #cells)
            b.hsep:SetColorTexture(d[1], d[2], d[3], d[4] or 1)
            if ns.NoSnap then ns.NoSnap(b.hsep) end
            -- Rows are placed bottom-up, so s == 1 is the visual TOP row and
            -- is the one that gets no rule above it.
            b.hsep:SetShown(square and s > 1)
            PaintCell(app, b, cell, on, enabled, false, square)

            b:SetScript("OnClick", function()
                -- The library's own menu re-renders AFTER a pick, not now:
                -- re-rendering here would release the button the menu is
                -- anchored to while it is open.
                if cell.items then
                    OpenCellMenu(app, cell, b,
                        function() ns.chrome.RenderFooter(app) end)
                    return
                end
                if cell.menu and MenuUtil and MenuUtil.CreateContextMenu then
                    MenuUtil.CreateContextMenu(b, function(_, root) cell.menu(root, app) end)
                elseif cell.onClick then
                    cell.onClick(app)
                end
                ns.chrome.RenderFooter(app)
            end)
            b:SetScript("OnEnter", function(self)
                if not on and enabled then
                    PaintCell(app, self, cell, false, enabled, true, square)
                end
                if cell.tooltip then
                    ns.context.Show(self, app, cell.tooltip, nil)
                end
            end)
            b:SetScript("OnLeave", function(self)
                PaintCell(app, self, cell, on, enabled, false, square)
                ns.context.Hide()
            end)

            app.footerCells[#app.footerCells + 1] = b
            x = x + w + gap
        end
        y = y + SLOT_HEIGHT + (square and 0 or SLOT_GAP)
    end
end

-- ── Breadcrumb and body placeholder ────────────────────────────

-- The page header's height, from EVERYTHING that wants space in it.
--
-- One sum, in one place. It used to be set by whichever contributor ran
-- last: the breadcrumb wrote 26 once at creation and a contextual
-- navigator wrote its own height on every refresh, so on any page without
-- tabs the header collapsed to nothing and took the breadcrumb with it.
-- Two owners, no conversation.
--
-- Adding a third thing to this header is a term in this sum, not another
-- owner.
-- The crumb's own band. It holds one line of small text, and every pixel
-- beyond that is a gap between the trail and the page under it -- which is
-- already separated by the page's own top inset.
ns.chrome.BREADCRUMB_H = 18

-- A page's header field gets a ROW OF ITS OWN, under the breadcrumb and
-- above the tab strip -- which is where older options dialogs drew a
-- section-level setting, at the left, on its own line. Sharing the crumb's
-- line was the first attempt and it was wrong twice over: the control had
-- to go to the right to keep clear of the trail, and a band sized to the
-- taller of the two reserved less room than a control needs.
ns.chrome.HEADER_FIELD_H = 30

local function CrumbBand(app)
    return (app.breadcrumbShown ~= false) and ns.chrome.BREADCRUMB_H or 0
end

-- STACKED, not maxed: the crumb's line, then the field's.
local function HeaderTopBand(app)
    return CrumbBand(app) + (app.headerFieldH or 0)
end

-- THE ROWS the current page puts in its header, visible fields only.
--
-- A page declares `headerFields = { row, row, ... }`, each row a list of
-- field specs drawn left to right on one line; the older `headerField =
-- <spec>` is the one-row, one-field case and still works. Either may be a
-- function of (page, ctx), and so may any entry in a row. A row that is
-- itself a spec (it has a `control`) is taken as a one-field row.
--
-- Asked of ns.page.ForRoute -- the page the BODY will draw, ancestor
-- fallback included -- so the header and the body can never disagree about
-- which page is on screen.
--
-- A row every field of which is hidden takes no line: the rows that come
-- back are exactly the rows that draw, so their count IS the height.
local function HeaderRows(app, ctx)
    local page = ns.page and ns.page.ForRoute and ns.page.ForRoute(app) or nil
    if not page then return nil, nil end

    local rows = page.headerFields
    if type(rows) == "function" then rows = rows(page, ctx) end
    if type(rows) ~= "table" then
        local one = page.headerField
        if type(one) == "function" then one = one(page, ctx) end
        rows = (type(one) == "table") and { { one } } or nil
    end
    if type(rows) ~= "table" then return nil, page end

    local out
    for _, row in ipairs(rows) do
        if type(row) == "function" then row = row(page, ctx) end
        if type(row) == "table" and row.control then row = { row } end
        local vis
        for _, spec in ipairs(type(row) == "table" and row or {}) do
            if type(spec) == "function" then spec = spec(page, ctx) end
            if type(spec) == "table" and spec.control then
                -- The predicate may be asked before there is a ctx to ask
                -- it with -- the reserve pass runs before the page is
                -- rendered -- and a field's `hidden` is entitled to ignore
                -- an argument it never uses.
                local ok, hidden = pcall(ns.IsHidden, spec, ctx)
                if not (ok and hidden) then
                    vis = vis or {}
                    vis[#vis + 1] = spec
                end
            end
        end
        if vis then
            out = out or {}
            out[#out + 1] = vis
        end
    end
    return out, page
end

-- HOW MUCH ROOM the header rows need, settled BEFORE the navigators are
-- placed.
--
-- The height used to be worked out while the page was rendering, which is
-- after MountContextual has already positioned the tab strip: the strip
-- was laid out against a band that had not been told about the field yet
-- and drew straight through it, and only the NEXT render -- whatever
-- happened to cause one -- put it right. That is the "sometimes" in a
-- control that sometimes overlapped the tabs.
--
-- It asks only how many ROWS there are, never how tall this particular
-- control is: a row is a row, and a height that depended on the widget
-- would be back to needing the widget built first.
function ns.chrome.ReserveHeaderField(app)
    local rows = HeaderRows(app, nil)
    app.headerFieldH = rows and (#rows * ns.chrome.HEADER_FIELD_H) or 0
end

function ns.chrome.PageHeaderHeight(app)
    local h = HeaderTopBand(app)
    h = h + (app.ctxNavHeight or 0)
    h = h + (app.pageHeaderExtra or 0)
    return h
end

-- Where the contextual navigator BAND starts: under the breadcrumb.
--
-- The band can hold more than one navigator. A section whose children are
-- a tab strip, one of whose children is ITSELF a tab strip, mounts two --
-- which is the shape older options dialogs draw with an outer row of tabs and an
-- inner row beneath it, and the shape this library could not draw until
-- every strip stopped anchoring at this one constant.
function ns.chrome.CtxNavTop(app)
    return HeaderTopBand(app)
end

-- Where ONE navigator starts inside that band: the band's top plus the
-- height of every navigator mounted ABOVE it.
--
-- `stackIndex` is set by MountContextual in route order, so the outermost
-- section's strip is 1 and each nested one follows. A navigator that has
-- not measured itself yet contributes its declared height, which is the
-- floor rather than the answer -- the same rule the band's own total uses,
-- and it settles on the pass after the strip has packed.
function ns.chrome.CtxNavTopFor(app, nav)
    local y = ns.chrome.CtxNavTop(app)
    if not (nav and nav.stackIndex) then return y end
    for _, other in pairs(app.ctxNavs or {}) do
        if (other.stackIndex or 0) < nav.stackIndex then
            y = y + (other.dynHeight or (other.def and other.def.height) or 0)
        end
    end
    return y
end

-- ── A page's own controls, up in the header ────────────────────
--
-- `page.headerFields` puts rows of controls in the page header, under the
-- breadcrumb and ABOVE every contextual tab strip, which is where older
-- options dialogs drew a setting that belongs to a whole section rather than to the
-- subtab you happen to be on. The aura sections' Aura Preview dropdown is
-- one case: the same setting on eight subtabs, and as a card it was the
-- first thing on every one of them. A section's own chrome -- which
-- scope is being edited, and whether it is -- is the other, and it needs
-- more than one control on the line, which is why this is rows rather
-- than the single field it began as.
--
-- The label is drawn BESIDE the control rather than above it. A row is
-- one line tall; a label above would double it and push every tab strip
-- in the panel down to buy a caption a row of its own. `labelSide =
-- "after"` puts the label on the far side of the control, as it does on a
-- page, which is how a switch reads as a sentence.
--
-- One widget per (row, column, control kind), kept on the app and
-- re-applied. Acquiring from the pool on every render would need a
-- matching release on every route change, and the page's own release
-- scopes do not reach up here. The kind is part of the key so that two
-- pages putting different controls in the same slot never hand one
-- widget the other's spec.
local HEADER_FIELD_GAP = 16

function ns.chrome.RenderHeaderField(app, page, ctx)
    local rows = HeaderRows(app, ctx)

    local ph = app:GetRegion("pageheader")
    app.headerFieldWs = app.headerFieldWs or {}
    local used = {}

    -- The band's height is part of the page header's total, so a change to
    -- it has to reach the regions -- the same reconcile MountContextual
    -- does for a tab strip, and for the same reason: more than one thing
    -- lives up there and none of them may write the total. ReserveHeaderField
    -- has normally settled this before the navigators were placed; this is
    -- the backstop for a page that arrived by some other path.
    local function settle()
        local want = ns.chrome.PageHeaderHeight(app)
        if (app.pageheaderHeight or 0) ~= want then
            app.pageheaderHeight = want
            ns.LayoutRegions(app)
        end
    end

    local drawnRows = 0
    for r, row in ipairs(rows or {}) do
        drawnRows = drawnRows + 1
        -- AT THE LEFT, under the breadcrumb: lined up with the trail above
        -- and the first tab below rather than floating off the right edge.
        -- Everything on the row -- labels and controls alike -- is centered
        -- on one midline, so a 15px switch and a 22px dropdown read as one
        -- line rather than as two things hung from the same top edge.
        local x   = 12
        local top = CrumbBand(app) + 3 + (r - 1) * ns.chrome.HEADER_FIELD_H
        local mid = top + (ns.chrome.HEADER_FIELD_H - 6) / 2

        for c, spec in ipairs(row) do
            local def = (app.controls and app.controls[spec.control])
                        or ns.builtinControls[spec.control]
            if def then
                local slot = r .. ":" .. c .. ":" .. spec.control
                local w = app.headerFieldWs[slot]
                if not w then
                    w = def.create(app, ph)
                    app.headerFieldWs[slot] = w
                    w.bpHdrLabel = ns.FS(ph, "OVERLAY", "GameFontNormalSmall")
                    w.bpHdrLabel:SetJustifyH("LEFT")
                end
                used[w] = true
                w:SetParent(ph)
                w:Show()

                local prefW = def.measure and select(1, def.measure(spec, 0, ctx))
                              or ns.CONTROL_W
                local width = spec.width or prefW
                w:SetWidth(width)

                -- A control that draws its OWN caption (a button) gets no
                -- separate label, the same rule the page applies.
                local l = w.bpHdrLabel
                local labelText = (not def.ownLabel) and ns.FieldLabel(spec) or nil
                local after = (spec.labelSide == "after")

                local function placeLabel()
                    l:SetParent(ph)
                    l:ClearAllPoints()
                    l:SetPoint("LEFT", ph, "TOPLEFT", x, -mid)
                    l:SetText(labelText)
                    ns.SetFontSize(l, 11)
                    local col = ns.PresetColor(nil, app.skin, "labelFg")
                    l:SetTextColor(col[1], col[2], col[3], 1)
                    l:Show()
                    x = x + (l:GetStringWidth() or 0) + 8
                end

                if labelText and labelText ~= "" then
                    if not after then placeLabel() end
                else
                    l:Hide()
                end

                w:ClearAllPoints()
                w:SetPoint("LEFT", ph, "TOPLEFT", x, -mid)
                -- Advanced by the width that was SET, not one read back:
                -- GetWidth is anchor-derived and can answer for the last
                -- pass, and the next control on the row would be placed on
                -- top of this one.
                x = x + width + 8

                if labelText and labelText ~= "" and after then placeLabel() end

                def.apply(w, spec, ctx)
                def.refresh(w, spec, ctx)

                x = x + HEADER_FIELD_GAP - 8
            end
        end
    end

    -- Every widget a previous page left up here that this one is not
    -- using, hidden -- label and all.
    for _, w in pairs(app.headerFieldWs) do
        if not used[w] then
            w:Hide()
            if w.bpHdrLabel then w.bpHdrLabel:Hide() end
        end
    end

    app.headerFieldH = drawnRows * ns.chrome.HEADER_FIELD_H
    settle()
end

function ns.chrome.RenderBreadcrumb(app)
    local ph = app:GetRegion("pageheader")
    -- Switched off: nothing here draws. Checked BEFORE the FontString is
    -- created, because it is created shown -- so a crumb first rendered
    -- after the toggle was flipped ignored it entirely.
    if app.breadcrumbShown == false then
        if app.breadcrumb then app.breadcrumb:Hide() end
        return
    end
    -- A breadcrumb NAVIGATOR is mounted: it draws the same path in the same
    -- band, as buttons. Two of them would sit on top of each other, so the
    -- static one stands down -- without giving up the band, which the
    -- navigator is using.
    if app.crumbNav then
        if app.breadcrumb then app.breadcrumb:SetText("") end
        return
    end
    -- Shown here as well as in SetBreadcrumbShown, so turning it back on
    -- takes effect on the next render rather than needing a reload.
    if app.breadcrumb then app.breadcrumb:Show() end
    if not app.breadcrumb then
        local fs = ns.FS(ph, "OVERLAY", "GameFontNormalSmall")
        -- Anchored to the TOP of the region, in its own band, rather than
        -- vertically centered in whatever the region currently is: a tab
        -- strip below it must not push it off center, and both drawing
        -- from the region's left edge is what put them on top of each
        -- other.
        fs:SetPoint("TOPLEFT", ph, "TOPLEFT", 12, -6)
        app.breadcrumb = fs
    end

    local parts = {}
    -- Stops where the contextual band does; see ns.nav.SuppressedAt.
    local n = #(app.route or {})
    if app.ctxNavSuppressedAt and app.ctxNavSuppressedAt < n then
        n = app.ctxNavSuppressedAt
    end
    for i = 1, n do
        local e = app.routeIndex and app.routeIndex[table.concat(app.route, "/", 1, i)]
        parts[#parts + 1] = (e and (e.node.title or e.node.id)) or app.route[i]
    end
    -- The page you are ON is the one you are looking for; its ancestors are
    -- context. So the trail is muted and the last part is drawn at full
    -- contrast, which is how the mockup expresses the same difference in
    -- weight -- this font has no bold to reach for.
    local c    = app.skin.textMuted
    local lit  = app.skin.text
    app.breadcrumb:SetTextColor(c[1], c[2], c[3])
    local last = #parts
    for i = 1, last do
        if i == last then
            parts[i] = ("|cff%02x%02x%02x%s|r"):format(
                lit[1] * 255, lit[2] * 255, lit[3] * 255, parts[i])
        end
    end
    app.breadcrumb:SetText(table.concat(parts, "  \194\183  "))
end

-- P0.2 placeholder: the body shows which route is selected. P0.3 replaces
-- this entirely with built page content.
function ns.chrome.RenderPlaceholder(app, show)
    -- ASKED TO HIDE COMES FIRST, whether or not the fontstrings exist.
    --
    -- The guard used to be `app.placeholder and show == false`, so the very
    -- first call -- which is a call to HIDE, made after a page rendered
    -- perfectly well -- fell straight through it, built the placeholder and
    -- showed it. That is the "route: a/b/c" text over a real page, and it
    -- only went away on the next refresh, which is why it read as a
    -- once-off.
    if show == false then
        if app.placeholder then
            app.placeholder:Hide(); app.placeholderSub:Hide()
        end
        return
    end
    local body = app:GetRegion("body")
    if not app.placeholder then
        local fs = ns.FS(body, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("CENTER", body, "CENTER", 0, 10)
        app.placeholder = fs

        local sub = ns.FS(body, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("TOP", fs, "BOTTOM", 0, -8)
        app.placeholderSub = sub
    end

    local e = app.routeIndex and app.routeIndex[table.concat(app.route or {}, "/")]
    local t = app.skin.text
    app.placeholder:SetTextColor(t[1], t[2], t[3])
    app.placeholder:SetText(e and (e.node.title or e.node.id) or "")

    local c = app.skin.textMuted
    app.placeholderSub:SetTextColor(c[1], c[2], c[3])
    app.placeholderSub:SetText("route: " .. table.concat(app.route or {}, "/"))
    app.placeholder:Show(); app.placeholderSub:Show()
end
