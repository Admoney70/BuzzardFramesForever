-- ============================================================
-- BuzzardPanel: Reorder.lua
-- One drag-to-reorder gesture, for anything laid out in a line.
--
-- Two things in this panel are ordered lists the reader wants to
-- rearrange: a collection's members in the rail tree, and a page's group
-- cards in the body. The gesture is the same in both -- find the
-- siblings, work out which gap the cursor is in, draw a line there, and
-- on release report where the dragged thing should end up -- and the only
-- differences are what counts as a sibling and what to do with the
-- answer. So the gesture lives here once and takes those two as inputs.
--
-- What this file deliberately does NOT know: routes, collections, pages,
-- groups, or storage. It reports positions in the list it was given. The
-- caller translates that into whatever its own data means, which is the
-- same split the library draws everywhere else -- the library owns the
-- gesture, the addon owns the storage.
--
-- ── Why RegisterForDrag ──
--
-- The client applies its own movement threshold before OnDragStart fires,
-- which is exactly the click-versus-drag distinction we would otherwise
-- have to invent, and it is the one the reader is already used to from
-- the rest of the UI. OnClick is untouched, so a plain click still does
-- whatever it did before. There is no OnDragUpdate -- the client reports
-- the beginning and the end and nothing in between -- so the line is
-- followed on OnUpdate for the duration of the gesture.
--
-- ── Why the dragged thing dims rather than detaching ──
--
-- A floating ghost frame needs its own strata, its own pool and its own
-- teardown on every way a drag can end, to say something the insertion
-- line already says.
-- ============================================================
local ADDON, ns = ...

ns.reorder = {}

local LINE_H     = 2
local EDGE_ZONE  = 24     -- how close to an edge starts auto-scrolling
local EDGE_STEP  = 8      -- pixels per frame at the edge

-- The one drag in progress, if any. A drag is a modal thing: the reader
-- has a mouse button down and is holding one object. Two at once is not a
-- state this needs to represent, and a single upvalue means nothing can
-- leak onto an app table and outlive the gesture.
--
-- `drag` exists from the moment the BUTTON GOES DOWN, not from the moment
-- the client decides a drag has begun. Those are different instants: the
-- client applies a movement threshold first, and waiting for it meant the
-- item dimmed, the grip lit and the line appeared a beat after the press,
-- which reads as lag rather than as an affordance. So mouse-down ARMS the
-- gesture and mouse-up disarms it if nothing came of it, while
-- OnDragStart/OnDragStop stay the authoritative pair for the drop itself --
-- they are the reliable ones, and where the button happened to be released
-- should not decide whether anything moved.
local drag

-- In `ref`'s units: the cursor is compared with frames inside the panel,
-- which is not drawn at UIParent's scale (Frame.lua StampPanelScale).
local function Cursor(axis, ref)
    local x, y = GetCursorPosition()
    local s = (ref and ref.GetEffectiveScale and ref:GetEffectiveScale())
           or UIParent:GetEffectiveScale() or 1
    if axis == "x" then return x / s end
    return y / s
end

-- Which gap the cursor is in: 1 is above the first sibling, #sibs+1 below
-- the last. Measured against each sibling's MIDLINE, so the slot flips as
-- the cursor passes the middle of a thing rather than its edge, which is
-- what makes a short drag feel like it did nothing and a long one feel
-- like it went where you aimed.
-- Pinned siblings hold the front of the list, so nothing may land above
-- them. The slot is CLAMPED rather than refused -- the insertion line
-- snaps to the first legal gap and the drag stays live, instead of the
-- reader hunting for somewhere they are allowed to let go.
--
-- There is no upper bound and nothing can be trapped, because pinned
-- members are always a PREFIX: a collection hoists them to the front (see
-- Collections' Members), so "somewhere below the pins" is the whole rest
-- of the list. An earlier version treated any pinned sibling as a two-way
-- barrier, which penned in whatever happened to sit above one -- a free
-- item with a pinned item after it could not be dragged anywhere at all.
local function ClampSlot(sibs, slot, fromPos, pinned)
    if not (pinned and fromPos) then return slot end
    local lo, hi = 1, #sibs + 1
    for i = 1, fromPos - 1 do
        if pinned(sibs[i]) then lo = i + 1 end
    end
    for i = fromPos + 1, #sibs do
        if pinned(sibs[i]) then hi = i; break end
    end
    if slot < lo then return lo end
    if slot > hi then return hi end
    return slot
end

-- Down the list on "y", along it on "x". The test flips with the axis
-- because a vertical list runs from high coordinates to low while a
-- horizontal one runs from low to high, so "before this sibling" is
-- ">= its midline" in one and "<= its midline" in the other.
local function SlotAt(sibs, pos, axis)
    for i, f in ipairs(sibs) do
        if axis == "x" then
            local l, r = f:GetLeft(), f:GetRight()
            if l and r and pos <= (l + r) / 2 then return i end
        else
            local top, bot = f:GetTop(), f:GetBottom()
            if top and bot and pos >= (top + bot) / 2 then return i end
        end
    end
    return #sibs + 1
end

local function Line(parent, color)
    if not parent.bpDropLine then
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:Hide()
        parent.bpDropLine = t
    end
    local l = parent.bpDropLine
    l:SetColorTexture(color[1], color[2], color[3], 0.95)
    return l
end

-- On the LEADING edge of the sibling the drop would go before, or the
-- trailing edge of the last one when the drop is past the end.
local function PlaceLine(parent, color, sibs, slot, axis)
    local l = Line(parent, color)
    local anchor, past = sibs[slot], false
    if not anchor then anchor, past = sibs[#sibs], true end
    l:ClearAllPoints()
    if not anchor then l:Hide(); return end

    if axis == "x" then
        l:SetWidth(LINE_H)
        l:SetPoint("TOP",    anchor, past and "TOPRIGHT"    or "TOPLEFT",    0, 0)
        l:SetPoint("BOTTOM", anchor, past and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, 0)
    else
        l:SetHeight(LINE_H)
        l:SetPoint("LEFT",  anchor, past and "BOTTOMLEFT"  or "TOPLEFT",  0, 0)
        l:SetPoint("RIGHT", anchor, past and "BOTTOMRIGHT" or "TOPRIGHT", 0, 0)
    end
    l:Show()
end

-- A page is taller than its viewport, so a drag that has to reach the far
-- end of the list needs the list to come to it. The rail tree wants this
-- too once a collection outgrows the rail.
local function AutoScroll(scroll)
    if not scroll then return end
    local y      = Cursor("y", scroll)
    local top    = scroll:GetTop()
    local bottom = scroll:GetBottom()
    if not (top and bottom) then return end

    local cur  = scroll:GetVerticalScroll() or 0
    local maxs = math.max(0, (scroll.contentHeight or 0) - (scroll:GetHeight() or 0))
    if y > top - EDGE_ZONE then
        scroll:SetVerticalScroll(math.max(0, cur - EDGE_STEP))
    elseif y < bottom + EDGE_ZONE then
        scroll:SetVerticalScroll(math.min(maxs, cur + EDGE_STEP))
    end
end

function ns.reorder.IsDragging() return drag ~= nil end

-- Undo the armed look, whatever ended it.
local function Disarm(self)
    local d = drag
    if not d then return end
    self:SetScript("OnUpdate", nil)
    d.item:SetAlpha(d.alpha or 1)
    if d.spec.onEnd then d.spec.onEnd(d.item) end
    if d.lineParent and d.lineParent.bpDropLine then
        d.lineParent.bpDropLine:Hide()
    end
    drag = nil
end

local function Stop(self)
    local d = drag
    if not d then return end
    -- Everything the armed state put on screen comes off here, whatever
    -- happens below. onEnd is the counterpart to onStart and must fire on
    -- EVERY way a drag ends -- dropped in place, dropped somewhere invalid,
    -- dropped where it already was -- or a caller that changed how
    -- something looks for the duration is left with it changed. Disarming
    -- here also covers a mouse-up this frame never saw.
    Disarm(self)

    local sibs = d.sibs
    local fromPos
    for i, f in ipairs(sibs) do if f == d.item then fromPos = i end end
    if not fromPos then return end

    local slot = d.slot or ClampSlot(sibs, SlotAt(sibs, Cursor(d.axis, d.item), d.axis),
                                     fromPos, d.spec.pinned)

    -- A slot BELOW the source loses one position once the source is lifted
    -- out of the list, so the position the reader aimed at is the one after
    -- this adjustment. Done here rather than in every caller, because
    -- getting it wrong is an off-by-one that only shows up dragging
    -- downward and looks like the drop landing one place short.
    --
    -- The RAW slot goes through as well, because the correction turns a gap
    -- into a position and not every caller wants a position. One that asks
    -- "which section is this gap in" or "which item is just below it" needs
    -- the gap, and reading the corrected number as a gap put a
    -- dropped-at-the-end member second from last.
    local gap = slot
    if slot > fromPos then slot = slot - 1 end
    if slot == fromPos then return end          -- dropped where it already was

    d.spec.onDrop(fromPos, slot, sibs, gap)
end

local function Arm(self)
    if drag then return end                    -- already armed
    local spec = self.bpReorder
    if not spec then return end
    if spec.blocked and spec.blocked() then return end

    local sibs = spec.siblings(self)
    if not sibs or #sibs < 2 then return end

    -- The frame that is dragged is not always the frame that moves. A group
    -- card is dragged by its HEADER, because dragging the card itself would
    -- fight every control inside it -- so the header is the handle and the
    -- card is the item, and it is the card that dims and that appears among
    -- the siblings.
    local item = spec.item and spec.item(self) or self
    local lineParent = spec.lineParent and spec.lineParent(self) or item:GetParent()
    drag = {
        spec = spec, sibs = sibs, item = item, lineParent = lineParent,
        axis = spec.axis or "y",
        alpha = item:GetAlpha() or 1,
    }
    item:SetAlpha(0.45)
    if spec.onStart then spec.onStart(item) end

    local color  = spec.color and spec.color() or { 0.2, 0.6, 1 }
    local scroll  = spec.scroll and spec.scroll(self) or nil
    local axis = spec.axis or "y"
    local fromPos
    for i, f in ipairs(sibs) do if f == item then fromPos = i end end

    -- Placed once now, so the line is there on the press rather than on the
    -- first frame of movement.
    local function follow()
        if not drag then return end
        AutoScroll(scroll)
        drag.slot = ClampSlot(drag.sibs, SlotAt(drag.sibs, Cursor(axis, item), axis),
                              fromPos, spec.pinned)
        PlaceLine(lineParent, color, drag.sibs, drag.slot, axis)
    end
    follow()
    drag.follow = follow
end

-- The client has decided this is a drag rather than a click. The look is
-- already applied by Arm; all this adds is following the cursor.
local function Start(self)
    if not drag then Arm(self) end
    if not drag then return end
    -- Marks this as a real drag rather than a press, so the mouse-up that
    -- ends it is not mistaken for a click that never went anywhere.
    drag.dragging = true
    if drag.follow then self:SetScript("OnUpdate", drag.follow) end
end

-- Released without ever becoming a drag.
local function Cancel(self)
    if drag and not drag.dragging then Disarm(self) end
end

-- ── The grip ───────────────────────────────────────────────────
--
-- Three bars saying "this can be dragged". Lives here rather than in Page
-- because the rail's rows want the identical thing, and two copies of a
-- 9x7 affordance would drift in exactly the way two copies of the gesture
-- would.
--
-- DRAWN, not textured. At this size a TGA is three rows of texels scaled
-- to whatever the UI scale makes of them -- which is how the group cards'
-- corners came out soft before they were given a pixel host -- while three
-- SetColorTexture bars land on exact pixels at any scale, and cost one
-- frame and no file.
--
-- It is an INDICATOR, not a hit area. The whole header or row drags;
-- shrinking that to a 9px target would make the gesture harder to start
-- while looking like an invitation.
ns.reorder.GRIP_W, ns.reorder.GRIP_H = 9, 7

function ns.reorder.AttachGrip(parent)
    local grip = CreateFrame("Frame", nil, parent)
    grip:SetSize(ns.reorder.GRIP_W, ns.reorder.GRIP_H)
    grip.bars = {}
    for i = 1, 3 do
        local bar = grip:CreateTexture(nil, "OVERLAY")
        bar:SetHeight(1)
        local dy = ns.reorder.GRIP_H / 2 - (i - 1) * 3 - 0.5
        bar:SetPoint("LEFT",  grip, "LEFT",  0, dy)
        bar:SetPoint("RIGHT", grip, "RIGHT", 0, dy)
        grip.bars[i] = bar
    end
    grip:Hide()
    return grip
end

-- Muted at rest, accent while the thing is ACTUALLY being dragged -- not on
-- mouseover. A row or a header is a large target the reader crosses on the
-- way to everything else, and lighting the grip each time says "you are
-- doing something" when they are not.
function ns.reorder.PaintGrip(grip, skin, dragging)
    if not (grip and grip.bars) then return end
    local c = dragging and skin.accent or skin.textMuted
    for _, bar in ipairs(grip.bars) do
        bar:SetColorTexture(c[1], c[2], c[3], dragging and 1 or 0.55)
    end
end

-- Install (or remove) the gesture on one frame.
--
-- Called on every render rather than once at creation, because a pooled
-- frame is reused for whatever comes next -- including something that must
-- NOT be draggable. Passing nil is how a frame gives the gesture up.
--
-- spec = {
--   axis              -> "y" (default) or "x". A tab strip lays its
--                        siblings across rather than down; the slot is
--                        then measured horizontally and the insertion line
--                        is a vertical bar on the leading edge.
--   siblings(frame)   -> ordered array of frames this one can move among
--   onDrop(from, to, sibs, gap)
--                     -> `from` and `to` are POSITIONS in that array,
--                        1-based, with the lift already accounted for --
--                        what a caller reordering a list wants. `gap` is
--                        the raw slot the cursor was in, 1..#sibs+1, where
--                        gap i means "above sibs[i]" -- what a caller
--                        asking WHERE THE CURSOR IS wants. They are
--                        different questions and mixing them is an
--                        off-by-one at the end of a list.
--   item(frame)       -> the frame that MOVES, when the one that is
--                        dragged is only a handle                (optional)
--   onStart(item)     -> a drag has begun                        (optional)
--   onEnd(item)       -> it has ended, however it ended          (optional)
--   color()          -> the insertion line's color        (optional)
--   scroll(frame)     -> a ScrollFrame to auto-scroll       (optional)
--   lineParent(frame) -> where to draw the line             (optional)
--   pinned(frame)     -> true if that sibling is fixed in place
--                        (optional)
--   blocked()         -> true to refuse the drag right now  (optional)
-- }
function ns.reorder.Install(frame, spec)
    frame.bpReorder = spec
    if spec then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", Start)
        frame:SetScript("OnDragStop",  Stop)
        -- The armed look, on the press itself. A plain click therefore
        -- shows it for as long as the button is held, which is the honest
        -- reading of "while the button is down".
        --
        -- Hooked ONCE per frame, not on every Install. Install runs on every
        -- render and HookScript accumulates, so re-hooking here would add a
        -- handler per render forever. Safe to leave in place when the frame
        -- later becomes undraggable: Arm reads bpReorder, which Install has
        -- just set to nil, and does nothing.
        if not frame.bpReorderHooked then
            frame.bpReorderHooked = true
            frame:HookScript("OnMouseDown", Arm)
            frame:HookScript("OnMouseUp",   Cancel)
        end
    else
        frame:RegisterForDrag()
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop",  nil)
    end
end
