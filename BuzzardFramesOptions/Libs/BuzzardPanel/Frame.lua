-- ============================================================
-- BuzzardPanel: Frame.lua
-- The panel frame and its regions.
--
-- Regions are named, fixed places an app can put things into. Nothing
-- outside the library ever receives a raw frame reference: callers ask
-- for a region BY NAME and the library resolves it. That is what makes
-- the isolation guarantee hold -- an addon that cannot name another
-- app's frame cannot re-parent, hide or mutate it.
--
-- Layout, top to bottom:
--     titlebar          full width, fixed height
--     rail | body       rail fixed width, body fills the rest
--     footer            inside the rail, bottom-anchored
--     statusbar         full width, fixed height
--
-- P0.1 builds the regions empty. Navigators, chrome and content arrive
-- in P0.2 / P0.3.
-- ============================================================
local ADDON, ns = ...

-- Forward declaration. BuildResizeGrip calls LayoutRegions from a closure,
-- and LayoutRegions is defined further down this file. Without the forward
-- local the name resolves as a GLOBAL at call time and is nil -- which is
-- exactly the error this shipped with the first time.
local LayoutRegions

-- PixelUnit is the size, in UI units, of exactly one physical pixel for
-- this frame.
local function PixelUnit(f)
    if not GetPhysicalScreenSize then return nil end
    local _, ph = GetPhysicalScreenSize()
    local sc = f and f:GetEffectiveScale()
    if not ph or ph <= 0 or not sc or sc <= 0 then return nil end
    return (768 / ph) / sc
end
ns.PixelUnit = PixelUnit

-- The scale that puts ONE UI UNIT ON ONE PHYSICAL PIXEL for a direct child
-- of UIParent. The panel frame, the dropdown menu and the suggestion
-- flyout all wear it -- see StampPanelScale.
local function PixelScale()
    if not GetPhysicalScreenSize then return 1 end
    local _, ph = GetPhysicalScreenSize()
    local us = UIParent:GetEffectiveScale()
    if not ph or ph <= 0 or not us or us <= 0 then return 1 end
    return (768 / ph) / us
end
ns.PixelScale = PixelScale

-- HOW MANY PHYSICAL PIXELS ONE PANEL UNIT IS.
--
-- One is exact but, on a high-density display, small: at 4K with the
-- client's minimum UI scale a normal unit is 1.8 pixels, so a panel drawn
-- at one pixel per unit is little more than half the size of everything
-- around it. A whole-number multiple keeps every edge on the grid (an
-- integer times an integer is an integer) while letting the panel be a
-- size the reader can use. Auto picks the multiple nearest the rest of the
-- UI's own pixels-per-unit, so the panel comes out as close as it can to
-- the size it would have at the client's scale -- exactly that size on a
-- pixel-perfect UI scale, and never a fraction of a pixel off on any other.
-- A host can pin it (App:SetPixelMultiple) for a reader who wants the panel
-- larger or smaller than that.
local function AutoPixelMultiple()
    local k = PixelScale()
    if not k or k <= 0 then return 1 end
    -- UIParent's pixels per unit is 1 / k; the multiple is that, rounded.
    return math.max(1, math.floor(1 / k + 0.5))
end
ns.AutoPixelMultiple = AutoPixelMultiple

-- The multiple in force, for the frames that do not hang off the panel
-- (the menu, the flyout): whatever the panel last stamped.
--
-- FRACTIONAL multiples are allowed. A whole number keeps every edge on the
-- physical pixel grid; a fractional one puts integer offsets on fractional
-- pixels, which the strokes survive because every stroke piece is drawn
-- unsnapped (ns.NoSnap) -- a half-covered pixel on both sides, a hair
-- softer, never missing. That is the same rendering the rest of the UI
-- already has at any non-pixel-perfect UI scale.
--
-- Two ways to pin it: App:SetPixelMultiple(n) is absolute (pixels per
-- unit); App:SetPanelScale(s) is RELATIVE to the client's own UI scale --
-- s = 1 draws the panel at exactly UIParent's effective scale, the size
-- everything else on screen is drawn at. Unset, Auto picks the whole
-- multiple nearest the client's scale.
ns.pixelMultiple = nil
local function CurrentPixelMultiple(app)
    local rel = app and app.panelScaleRel
    if type(rel) == "number" and rel > 0 then
        local k = PixelScale()
        if k and k > 0 then return rel / k end
    end
    local m = app and app.pixelMultiple or ns.pixelMultiple
    if type(m) ~= "number" or m <= 0 then m = AutoPixelMultiple() end
    return m
end
ns.CurrentPixelMultiple = CurrentPixelMultiple

-- THE PANEL IS DRAWN IN PIXELS.
--
-- Every offset, inset, stroke and control size in this library is an
-- integer, and a hairline border is drawn as a ring with the surface inset
-- ONE unit over it. That only works if a unit is a pixel: at any other UI
-- scale an integer offset lands the frame's edge between two pixel
-- columns, the ring and the inset surface snap to the pixel grid
-- independently, and the stroke between them comes out as two pixels on
-- one side and none on the other -- which sides depending on how the
-- fractions happened to accumulate at that panel size. That was the
-- "borders missing on one side, changing when the panel is resized"
-- report, from the first session run without a pixel-perfect UI scale.
--
-- So the panel frame is scaled so one of its units is exactly one
-- physical pixel, whatever UIParent's scale is, and everything inside it
-- inherits that. It is what the rounded corners already did for their
-- own hosts (StampPixelHost), applied to the whole panel. The frames the
-- library parents to UIParent directly (the menu, the flyout) stamp the
-- same scale when they open, so they draw at the panel's size.
--
-- Re-stamped on UI_SCALE_CHANGED and DISPLAY_SIZE_CHANGED, because both
-- inputs move under it.
local function StampPanelScale(f, app)
    local m = CurrentPixelMultiple(app)
    if app then ns.pixelMultiple = m end
    local k = PixelScale() * m
    if f._bpPanelScale ~= k then
        f:SetScale(k)
        f._bpPanelScale = k
    end
end
ns.StampPanelScale = StampPanelScale

-- Drop keyboard focus if the EditBox holding it is `frame` or lives inside
-- it. Called before a frame is hidden (the panel closing, a pooled control
-- being released). An EditBox hidden WITH focus keeps it: the client still
-- routes Escape and Enter to it -- which, hidden, it cannot act on -- so
-- both keys go dead everywhere (no game menu, no chat) until something
-- clears the focus or the UI reloads. Every other key still works, which
-- is the fingerprint. Hiding never clears focus on its own.
local function ClearFocusWithin(frame)
    if not (frame and GetCurrentKeyBoardFocus) then return end
    local focus = GetCurrentKeyBoardFocus()
    if not (focus and focus.ClearFocus) then return end
    local p = focus
    while p do
        if p == frame then focus:ClearFocus(); return end
        p = p.GetParent and p:GetParent()
    end
end
ns.ClearFocusWithin = ClearFocusWithin

-- A child frame scaled so that ONE ART TEXEL IS ONE PHYSICAL PIXEL.
--
-- This is the piece that makes nine-sliced rounded art look sharp, and the
-- piece every earlier attempt was missing. A texture's slice corners are
-- drawn at their texel size in UI UNITS, and a UI unit is almost never a
-- physical pixel -- so an 8-texel arc lands on 5.6 or 11.3 pixels and is
-- resampled. Scale the host by pixelSize / effectiveScale and the mapping is
-- exact at any UI scale.
--
-- Buzzard Frames does the same for its own rounded frame borders
-- (PixelPerfect.lua, StampRingPixelHost); this is that technique, kept
-- addon-neutral.
local function StampPixelHost(host, scaleFrame)
    if not (host and scaleFrame) then return end
    local eff = scaleFrame:GetEffectiveScale()
    if not eff or eff <= 0 then return end
    if not GetPhysicalScreenSize then return end
    local _, ph = GetPhysicalScreenSize()
    if not ph or ph <= 0 then return end
    local k = (768 / ph) / eff
    if host._bpScale ~= k then
        host:SetScale(k)
        host._bpScale = k
    end
end
ns.StampPixelHost = StampPixelHost

-- ── Small drawing helpers ──────────────────────────────────────
-- Deliberately plain textures rather than BackdropTemplate: a backdrop
-- brings edge-file scaling and inset semantics we do not want, and its
-- behavior has shifted across expansions more than SetColorTexture has.

-- ── Live skin tokens ───────────────────────────────────────────
--
-- A region paints itself once, at build time, from a skin token. Nothing
-- kept a handle on those textures, so changing a token afterwards had
-- nowhere to land -- the color was correct in the table and stale on the
-- screen. Every painted surface is now registered against the TOKEN it was
-- painted from, so the token can be repainted without rebuilding the panel.
local function Track(app, token, paint)
    app.skinPaint = app.skinPaint or {}
    local list = app.skinPaint[token]
    if not list then list = {}; app.skinPaint[token] = list end
    list[#list + 1] = paint
end

local function Fill(frame, color)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- The panel's outer border.
--
-- A translucent rounded background with a HOLLOW outline over it.
--
-- The two-fill treatment the controls use is deliberately not used here.
-- Its "border" is a solid rect sitting behind the surface, which is fine on
-- an opaque control and wrong on a panel: it blocks anything behind the
-- panel from showing through, and recoloring the border recolors the
-- whole panel, because the border rect IS most of what you see.
--
-- The border sits BEHIND the regions rather than on an overlay above them,
-- which is why every region that reaches a panel corner (the title bar, the
-- status bar, the rail and its footer) carries a rounded fill with its
-- inward-facing edges squared off. Without that they paint over the corner
-- arcs -- the "border on the bottom right but nowhere else" inconsistency
-- in its original form.
--
-- Configurable as before: skin.showBorder, borderSize (stroke),
-- borderRadius (corner), panelBorder and panelBg (colors).
local function BuildBorder(app, f)
    local skin = app.skin

    -- The surface: one rounded rect with nothing behind it, so panelBg's
    -- alpha is the panel's real transparency.
    --
    -- On a pixel host of its own, for the same reason the border is: the
    -- border's corner is now r PHYSICAL pixels, and if the surface's corner
    -- were still r UI units the two radii would disagree at every scale
    -- except 1.0 -- the surface rounder than the border, with daylight
    -- between them at the corners.
    local bgHost = CreateFrame("Frame", nil, f)
    bgHost:SetAllPoints(f)
    bgHost:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    bgHost:EnableMouse(false)
    StampPixelHost(bgHost, f)
    app.bgFrame = bgHost

    local fill = ns.RoundTex(bgHost, "BACKGROUND", skin.borderRadius)
    fill:SetAllPoints(bgHost)
    fill:SetDrawLayer("BACKGROUND", -8)
    fill:SetVertexColor(skin.panelBg[1], skin.panelBg[2],
                        skin.panelBg[3], skin.panelBg[4] or 1)

    -- The border: a ring on a PIXEL HOST above every region. The host's
    -- scale makes one art texel one physical pixel; without it the corner
    -- arc is resampled and no amount of better art helps.
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(f)
    over:SetFrameLevel(f:GetFrameLevel() + 100)
    over:EnableMouse(false)
    StampPixelHost(over, f)
    app.borderFrame = over

    local border = ns.Outline(over, skin.borderRadius, skin.borderSize or 1)
    border:SetColor(skin.panelBorder)
    border:SetShown(skin.showBorder ~= false)

    app.border, app.panelBgTex = border, fill
    Track(app, "panelBg", function(c)
        fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end)
    Track(app, "panelBorder", function(c) border:SetColor(c) end)
    return border
end

-- Change one skin color on a LIVE panel.
--
-- Three things have to happen and none of them is optional: the token is
-- rewritten (so anything that reads the skin from now on is right), every
-- surface painted from that token is repainted (so what is already drawn
-- is right too), and the regions are re-laid-out -- which is where the
-- status strip's two fills are re-colored, since which of them is painted
-- depends on its span. The nav refresh then re-renders the page and the
-- chrome, whose controls all paint from tokens.
function ns.SetSkinColor(app, token, c)
    if not (app and token and type(c) == "table") then return end
    app.skin[token] = c
    for _, paint in ipairs((app.skinPaint or {})[token] or {}) do paint(c) end
    if not app.frame then return end

    -- The repaint above is immediate, because that is what the reader is
    -- watching. The re-layout and the page render are COALESCED to the next
    -- frame: a color picker fires on every mouse move, and rebuilding the
    -- page thirty times a second to follow a dragged opacity slider is a
    -- stutter with nothing to show for it. One pass, after the last change.
    if app.bpSkinPending then return end
    app.bpSkinPending = true
    local function settle()
        app.bpSkinPending = nil
        if not app.frame then return end
        ns.LayoutRegions(app)
        if ns.nav and ns.nav.Refresh then ns.nav.Refresh(app) end
    end
    if C_Timer then C_Timer.After(0, settle) else settle() end
end

-- Show or hide the outer border.
function ns.SetBorderShown(app, shown)
    local skin = app.skin
    skin.showBorder = shown and true or false
    if not app.border then return end
    app.border:SetShown(shown and true or false)
    LayoutRegions(app)
end

-- Change the panel's corner radius.
--
-- A panel corner is drawn by three things at once -- the border stroke, the
-- panel background inside it, and whichever region's fill reaches that
-- corner -- so changing only the border left the panel itself square behind
-- a rounded outline. This moves all of them together. The radius snaps to
-- one of the authored sizes, because the slice margin has to match the
-- radius the art was drawn at.
function ns.SetBorderRadius(app, radius)
    app.skin.borderRadius = radius
    if app.border     then app.border:SetRadius(radius) end
    if app.panelBgTex then ns.SetTexRadius(app.panelBgTex, radius) end
    for _, setRadius in ipairs(app.cornerSetters or {}) do setRadius(radius) end
end

-- One edge line, used for the dividers between regions.
local function EdgeLine(parent, color, side, size)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    size = size or 1
    if side == "RIGHT" then
        t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(size)
    elseif side == "TOP" then
        t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(size)
    elseif side == "BOTTOM" then
        t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(size)
    end
    return t
end

-- ── Pixel snapping ─────────────────────────────────────────────
--
-- WoW draws the UI through a scale, so one UI unit is almost never one
-- physical pixel: at the usual scales a 1-unit line lands astride two pixel
-- rows and is drawn twice at half strength. That is what makes a hairline
-- border look soft, and it is why the same border in a desktop app looks
-- crisp -- that one is rendered straight to the monitor's pixels with
-- nothing in between.
--
-- The fix is not better art. It is to place the panel so its edges fall ON
-- pixel boundaries, and to size the border in whole pixels.
--

-- Round a frame's size and position to whole physical pixels.
--
-- Anchored by its BOTTOM-LEFT corner, not its center: a centered frame
-- with an odd width has both side edges on half pixels however carefully
-- the center is placed, and every hairline along them is then drawn
-- across two pixel columns. The corner is what has to land on the grid.
-- UIParent's own corner is pixel 0,0 at every scale, so a whole-pixel
-- offset from it is a whole-pixel edge.
local function SnapGeometry(f)
    local u = PixelUnit(f)
    if not u or u <= 0 then return end
    local function q(v) return math.floor(v / u + 0.5) * u end

    f:SetSize(q(f:GetWidth()), q(f:GetHeight()))

    local left, bottom = f:GetLeft(), f:GetBottom()
    if not (left and bottom) then return end
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", q(left), q(bottom))
end
ns.SnapGeometry = SnapGeometry

-- Re-stamp an existing panel after its multiple (or the display) changed:
-- the frame, its pixel hosts, the geometry and the layout.
-- The panel KEEPS ITS PLACE ON SCREEN across the change. Its anchor offset
-- is in its own units, so re-scaling the frame with the offset left alone
-- moves it -- at 2x, twice as far from the corner, which put it off the
-- screen with one corner showing. The center is taken in UIParent's units
-- before the stamp and put back after, then the frame is pulled back
-- inside the screen if the new size overhangs it.
function ns.RestampPanel(app)
    local f = app and app.frame
    if not f then return end
    local cx, cy = f:GetCenter()
    local oldEff = f:GetEffectiveScale() or 1
    local uiEff  = UIParent:GetEffectiveScale() or 1
    StampPanelScale(f, app)
    if app.borderFrame then StampPixelHost(app.borderFrame, f) end
    if app.bgFrame     then StampPixelHost(app.bgFrame,     f) end
    if cx and cy then
        local newEff = f:GetEffectiveScale() or 1
        -- Center in UIParent units, then in the frame's NEW units.
        local ux, uy = cx * oldEff / uiEff, cy * oldEff / uiEff
        local nx, ny = ux * uiEff / newEff, uy * uiEff / newEff
        -- Keep it on screen: the screen in the frame's new units.
        local sw = UIParent:GetWidth()  * uiEff / newEff
        local sh = UIParent:GetHeight() * uiEff / newEff
        local w, h = f:GetWidth(), f:GetHeight()
        local left   = math.max(0, math.min(sw - w, nx - w / 2))
        local bottom = math.max(0, math.min(sh - h, ny - h / 2))
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    end
    SnapGeometry(f)
    ns.EnsureOnScreen(f)
    -- The frames that do not hang off the panel (the open menu, the
    -- suggestion flyout) wear the same scale, stamped when they open --
    -- but a scale changed FROM the open menu has to reach that menu now,
    -- not on its next open.
    if ns.RestampFloaters then ns.RestampFloaters() end
    -- Every shape's corner sizes and stroke insets were computed in the
    -- OLD pixel unit; re-derive them all where they stand, or the live
    -- change draws broken borders that a reload would then "fix".
    if ns.RestampShapes then ns.RestampShapes() end
    if f:IsShown() then
        LayoutRegions(app)
        ns.ReflowSoon(app)
        -- The panel's SIZE in its own units did not change, so OnSizeChanged
        -- will not fire -- but everything a host hangs off the panel (the
        -- preview frames) just changed its on-screen size and place. Tell
        -- the host the same way a resize would.
        if app.onResize then
            app.onResize(app, f:GetWidth(), f:GetHeight())
        end
    end
end

-- UIParent's center, in `f`'s OWN units. The saved position is a center
-- offset, and the panel and UIParent do not share a scale, so the two
-- widths cannot be subtracted until they are in the same units.
local function ParentCenterIn(f)
    local s = (UIParent:GetEffectiveScale() or 1) / (f:GetEffectiveScale() or 1)
    return UIParent:GetWidth() * s / 2, UIParent:GetHeight() * s / 2
end

-- A panel the mouse cannot reach cannot be brought back: if the title bar
-- is off the screen there is nothing left to drag. So the test is not
-- "does the panel touch the screen" but "is it USABLE": at least a fifth
-- of the panel inside the screen past the left, right and bottom edges,
-- and the top edge -- where the title bar is -- on the screen. Anything
-- else is a position that went stale (a scale change, a resolution
-- change, a bug) or a drag taken too far, and it is pulled back in.
-- Parking most of the panel off one side stays a legitimate choice.
function ns.EnsureOnScreen(f)
    local s  = (UIParent:GetEffectiveScale() or 1) / (f:GetEffectiveScale() or 1)
    local sw = UIParent:GetWidth()  * s
    local sh = UIParent:GetHeight() * s
    local l, b = f:GetLeft(), f:GetBottom()
    local w, h = f:GetWidth(), f:GetHeight()
    if not (l and b and w and h and w > 0 and h > 0) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        SnapGeometry(f)
        return
    end
    -- At least a FIFTH of the panel stays on screen past the left, right
    -- and bottom edges -- proportional, so a large panel keeps a larger
    -- grabbable share, a small one is not swallowed by a fixed number.
    local keepX, keepY = w * 0.2, h * 0.2
    local nl, nb = l, b
    if nl + w < keepX then nl = keepX - w end
    if nl > sw - keepX then nl = sw - keepX end
    -- The top edge never leaves the screen at all -- the title bar lives
    -- there, and it is the one part that must always be in reach. The top
    -- rule runs last so it wins.
    if nb + h < keepY then nb = keepY - h end
    if nb + h > sh then nb = sh - h end
    if nl ~= l or nb ~= b then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl, nb)
        SnapGeometry(f)
    end
end

-- NO SetClampedToScreen here, deliberately: it was tried, and its inset
-- semantics made the panel undraggable after a resize. The panel is kept
-- usable in code instead -- EnsureOnScreen runs at creation, on every
-- show, on every scale change, and at the release of every move and
-- resize, so no position that cannot be grabbed is ever kept.

-- ── Geometry persistence ───────────────────────────────────────
-- The library owns no SavedVariables. The consuming addon hands NewApp
-- a `persist` function returning a table it owns; we read and write four
-- keys in it and nothing else.

local function LoadGeometry(app, f)
    local store = app.persist and app.persist()
    local skin  = app.skin
    local w = store and store.panelW or 880
    local h = store and store.panelH or 640
    -- The rail width is part of the saved geometry. Clamped on the way in
    -- as well as on the way out, so a store written by an older skin with
    -- a wider maximum cannot produce a rail this one would never allow.
    if store and store.railW then
        -- Only the skin's bounds here: the footer's minimum is not known
        -- until its cells have been measured, and LayoutRegions applies it
        -- on every pass anyway.
        app.railWidth = math.max(app.skin.railWidthMin,
                        math.min(app.skin.railWidthMax, store.railW))
    end
    f:SetSize(
        math.max(skin.minWidth,  math.min(skin.maxWidth,  w)),
        math.max(skin.minHeight, math.min(skin.maxHeight, h)))
    f:ClearAllPoints()
    if store and store.panelX and store.panelY then
        local sx, sy = store.panelX, store.panelY
        -- The offsets were saved in the frame's units AT SAVE TIME, and
        -- the frame may wear a different scale now: the Panel Scale
        -- moved, the UI scale did, a pixel-perfect addon toggled. Convert
        -- through the saved effective scale so the panel comes back to
        -- the same place ON THE SCREEN, not the same number of larger or
        -- smaller units from center -- which is how it ended up off the
        -- top right corner with nothing left to drag. A store from
        -- before this field is applied as-is; EnsureOnScreen backstops.
        local eff = f:GetEffectiveScale() or 1
        local sav = store.panelScl
        if type(sav) == "number" and sav > 0 and eff > 0 then
            sx, sy = sx * (sav / eff), sy * (sav / eff)
        end
        f:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function SaveGeometry(app, f)
    local store = app.persist and app.persist()
    if not store then return end
    local x, y = f:GetCenter()
    if x and y then
        local ux, uy = ParentCenterIn(f)
        store.panelX, store.panelY = math.floor(x - ux + 0.5), math.floor(y - uy + 0.5)
    end
    store.panelW, store.panelH = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
    -- The scale the offsets were measured under -- LoadGeometry converts
    -- through it when the scale at load differs.
    local eff = f:GetEffectiveScale()
    if eff and eff > 0 then
        store.panelScl = math.floor(eff * 10000 + 0.5) / 10000
    end
    if app.railWidth then store.railW = math.floor(app.railWidth + 0.5) end
end

-- ── Resize grip ────────────────────────────────────────────────
local function BuildResizeGrip(app, f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)

    -- Three diagonal grip lines radiating in from the corner: same length
    -- progression and thickness as before, just on the diagonal.
    --
    -- CreateLine rather than textures, because a texture CANNOT be drawn on a
    -- diagonal: Texture:SetRotation rotates the texture coordinates inside the
    -- quad, and a solid color rotated is the same solid color. Lines take
    -- start/end points, so the diagonal is real geometry.
    local c = app.skin.gripLine
    for _, offset in ipairs({ 4, 8, 12 }) do
        local ln = grip:CreateLine(nil, "OVERLAY")
        ln:SetThickness(1.5)
        ln:SetColorTexture(c[1], c[2], c[3], c[4])
        ln:SetStartPoint("BOTTOMRIGHT", grip, -offset, 1)
        ln:SetEndPoint(  "BOTTOMRIGHT", grip, -1,      offset)
    end

    grip:SetScript("OnMouseDown", function()
        if app.locked then return end
        ns.BeginSizing(app)
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        ns.SnapGeometry(f)
        -- Growing a panel parked near an edge pushes that edge off the
        -- screen; pull it back to a grabbable spot before saving.
        ns.EnsureOnScreen(f)
        SaveGeometry(app, f)
        -- A file-local function, not an app method: the app object
        -- deliberately exposes no layout entry point, so nothing outside
        -- this file can re-anchor another app's regions.
        LayoutRegions(app)
        ns.EndSizing(app)
    end)
    return grip
end

-- ── Edge resize handles ────────────────────────────────────────
--
-- A few pixels down the right edge and along the bottom, so the panel can
-- be made wider OR taller without going to the corner for both at once.
-- Invisible, as most are: a visible strip down two sides would fight the
-- panel's own border, and the affordance is the resistance under the
-- cursor rather than something drawn.
--
-- They stop short of the corner and leave it to the diagonal grip, which
-- is the one place both axes are wanted at once.
--
-- One resize path, not three: the mouse-up here does exactly what the
-- grip's does. Anything that has to happen after a resize -- the pixel
-- snap, the save, the re-layout -- happens in one place or it eventually
-- happens in only some of them.
-- Wide enough to find without aiming. It can afford to be, because the
-- handle sits UNDERNEATH everything in the panel rather than over it.
local EDGE_W = 15

local function BuildEdgeHandle(app, f, side)
    local e = CreateFrame("Button", nil, f)
    -- One level above the panel frame, which is as low as this can go.
    --
    -- The point is to sit UNDER everything in the panel: a 15px strip up
    -- the right edge crosses the scrollbar and the right end of any control
    -- that reaches the edge, and a click there belongs to the control. The
    -- higher frame level wins, so the handle only ever receives what
    -- nothing else wanted, which is what makes it safe to be this wide.
    --
    -- But not the panel's OWN level: `f` is mouse-enabled -- deliberately,
    -- so clicks do not fall through it -- and at equal levels it takes the
    -- click, which left the handles inert. +1 clears `f` and still ties
    -- with the regions, which are at that level and take no mouse, so every
    -- control (deeper again) still wins.
    e:SetFrameLevel(f:GetFrameLevel() + 1)
    if side == "RIGHT" then
        e:SetWidth(EDGE_W)
        e:SetPoint("TOPRIGHT",    f, "TOPRIGHT",     0, -EDGE_W)
        e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,  18)
    else
        e:SetHeight(EDGE_W)
        e:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   EDGE_W, 0)
        e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18,     0)
    end

    e:SetScript("OnMouseDown", function()
        if app.locked then return end
        ns.BeginSizing(app)
        f:StartSizing(side)
    end)
    e:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        ns.SnapGeometry(f)
        ns.EnsureOnScreen(f)
        SaveGeometry(app, f)
        LayoutRegions(app)
        ns.EndSizing(app)
    end)
    return e
end

-- Re-render the panel's CONTENTS shortly, at most once every 0.05s.
--
-- LayoutRegions is geometry only: it moves the regions and stops. What is
-- inside them is laid out from a region's width at render time -- how a
-- button bar wraps, how wide a status cell is, where a tree row's label
-- ends -- and none of that is revisited until something renders again.
-- Anything that changes a region's size therefore owes the panel one of
-- these.
-- While the reader is still dragging a resize handle or the rail splitter
-- (app.sizing) only the navigators and chrome are refreshed -- the strip
-- re-wraps, the rail tree re-clips, the footer re-measures -- and the
-- PAGE waits for the release (ns.EndSizing). Rebuilding the page from the
-- pool twenty times a second under the cursor was the "flashing" the
-- panel used to do while being resized.
function ns.ReflowSoon(app)
    if app.sizing then app.reflowOwed = true end
    if app.resizePending then return end
    app.resizePending = true
    C_Timer.After(0.05, function()
        app.resizePending = nil
        if not (ns.nav and ns.nav.Refresh) then return end
        if app.sizing and ns.nav.RefreshChrome then
            -- Mid-drag: navigators and chrome only (the strip wraps, the
            -- rail clips, the footer re-measures); the page waits.
            ns.nav.RefreshChrome(app)
        else
            ns.nav.Refresh(app)
        end
        -- An open menu hangs from a footer cell this pass may have moved
        -- (or released): rebuild it against the anchor's new geometry.
        if ns.ReanchorMenu then ns.ReanchorMenu() end
    end)
end

-- The two ends of a live drag. EndSizing pays the reflow the drag owed.
function ns.BeginSizing(app)
    app.sizing = true
end
function ns.EndSizing(app)
    app.sizing = nil
    if app.reflowOwed then
        app.reflowOwed = nil
        if ns.nav and ns.nav.Refresh then ns.nav.Refresh(app) end
    end
    -- Whether or not a reflow was owed, the chrome the menu hangs from
    -- has moved: re-place the open menu against it.
    if ns.ReanchorMenu then ns.ReanchorMenu() end
end

-- ── Rail splitter ──────────────────────────────────────────────
--
-- The rail's right edge, draggable, so the reader can give the tree more
-- room for long titles or take it back for the page.
--
-- ABOVE the rail's contents, unlike the edge resize handles, which sit
-- below everything. The rail's right edge is exactly where its scroll rows
-- end, and a splitter you cannot grab because a row is on top of it is no
-- splitter. It is narrow for the same reason: it has priority here, so it
-- must not take more than it needs.
local SPLIT_W = 5

local function BuildRailSplitter(app, f)
    local sp = CreateFrame("Button", nil, f)
    sp:SetWidth(SPLIT_W)
    sp:SetFrameLevel(f:GetFrameLevel() + 21)

    local function follow(self)
        local x = GetCursorPosition() / (f:GetEffectiveScale() or 1)
        local left = f:GetLeft()
        if not left then return end
        local skin = app.skin
        -- The same floor the layout applies, so the drag stops where the
        -- rail would stop rather than running on and snapping back.
        local lo = math.max(skin.railWidthMin,
                   (app.footerSpan == "full") and 0 or (app.footerMinWidth or 0))
        local w = math.max(lo,
                  math.min(skin.railWidthMax, (x - left) - self.grabOff))
        -- Whole pixels: the rail's edge is a border like any other.
        w = math.floor(w + 0.5)
        if w == (app.railWidth or 0) then return end
        app.railWidth = w
        LayoutRegions(app)
        -- The rail's rows are laid out from its width, so a wider rail
        -- needs a re-render before a truncated title stops being truncated.
        ns.ReflowSoon(app)
    end

    -- The highlight is the SPLITTER'S own line, not a tint on the rail's.
    --
    -- Tinting the rail's edge line was the obvious version and it stopped
    -- at the button bar: the footer is a region drawn over the bottom of
    -- the rail, so it covers that stretch of the rail's own texture. The
    -- splitter sits above every region, so a line on the splitter runs the
    -- full height -- from the top of the rail to the bottom of the panel --
    -- and the rail's base border stays exactly as it is underneath.
    sp.line = sp:CreateTexture(nil, "OVERLAY")
    sp.line:SetWidth(1)
    sp.line:SetPoint("TOPLEFT",    sp, "TOPLEFT",    2, 0)
    sp.line:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 2, 0)
    sp.line:Hide()

    local function paint(hot)
        if not hot then sp.line:Hide(); return end
        local c = app.skin.accent
        sp.line:SetColorTexture(c[1], c[2], c[3], 0.9)
        sp.line:Show()
    end

    sp:SetScript("OnEnter", function() if not app.locked then paint(true) end end)
    sp:SetScript("OnLeave", function() if not sp.dragging then paint(false) end end)

    sp:SetScript("OnMouseDown", function(self)
        if app.locked then return end
        local x = GetCursorPosition() / (f:GetEffectiveScale() or 1)
        local left = f:GetLeft()
        -- Where in the strip the reader grabbed, so the edge does not jump
        -- to the cursor on the first frame.
        self.grabOff = (left and (x - left) or 0) - (app.railWidth or app.skin.railWidth)
        self.dragging = true
        ns.BeginSizing(app)
        paint(true)
        self:SetScript("OnUpdate", follow)
    end)
    sp:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = nil
        ns.EndSizing(app)
        paint(self:IsMouseOver())
        -- Persisted beside the panel's own geometry, and restored by the
        -- same path: a rail width the reader chose is part of where they
        -- left the panel, not a preference of its own.
        local store = app.persist and app.persist()
        if store then store.railW = math.floor((app.railWidth or 0) + 0.5) end
    end)
    -- ANCHORED HERE, not only in LayoutRegions.
    --
    -- BuildFrame lays the regions out BEFORE it builds this, so the layout
    -- pass that would have placed the splitter runs while it does not yet
    -- exist -- leaving a frame with no points, which draws nothing and
    -- catches no mouse. It came right on the first navigation, because that
    -- runs another layout pass, so the symptom was a splitter that was dead
    -- until the reader clicked something else.
    --
    -- These points are the same ones LayoutRegions sets and they never
    -- differ: the splitter straddles the rail's right edge in every layout.
    -- Setting them at birth means the frame is correct from the first
    -- paint and the layout pass merely re-states them.
    sp:SetPoint("TOPRIGHT",    app.regions.rail, "TOPRIGHT",    2, 0)
    sp:SetPoint("BOTTOMRIGHT", app.regions.rail, "BOTTOMRIGHT", 2, 0)
    sp:SetShown(app.railShown ~= false and not app.locked)

    app.railSplitter = sp
    return sp
end

-- ── Region construction ────────────────────────────────────────
local function BuildRegions(app, f)
    local skin = app.skin
    local R = {}

    -- The four regions that reach a panel corner take a rounded fill with
    -- their inward edges squared, so the border's arcs stay visible behind
    -- them. Everything else is a plain rectangle.
    -- Each one hands back a setter, collected so the whole panel can change
    -- corner radius in one call.
    local rr = skin.borderRadius
    app.cornerSetters = {}
    -- Each helper takes a TOKEN NAME rather than a color, so the surface
    -- it makes can be registered against the token and repainted later.
    local function corner(frame, sides, token)
        local paint, setRadius = ns.RoundedFill(frame, "BACKGROUND", rr, sides, skin[token])
        app.cornerSetters[#app.cornerSetters + 1] = setRadius
        Track(app, token, paint)
    end
    local function edgeFrom(frame, token, side)
        local t = EdgeLine(frame, skin[token], side)
        Track(app, token, function(c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end)
    end

    -- TWO fills apiece for the three regions whose CORNERS depend on the
    -- layout, painted the same way the status strip's are: which of them is
    -- opaque is decided in LayoutRegions and the other is transparent.
    -- RoundedFill bakes in which corners stay square and there is no
    -- re-siding it afterwards, so the alternative is rebuilding textures on
    -- a layout switch. A token change re-runs LayoutRegions (see
    -- SetSkinColor), which is why neither variant is Track'd.
    local function corners(frame, sidesA, sidesB, token)
        local paintA, radiusA = ns.RoundedFill(frame, "BACKGROUND", rr, sidesA, skin[token])
        local paintB, radiusB = ns.RoundedFill(frame, "BACKGROUND", rr, sidesB, { 0, 0, 0, 0 })
        app.cornerSetters[#app.cornerSetters + 1] = radiusA
        app.cornerSetters[#app.cornerSetters + 1] = radiusB
        return paintA, paintB
    end

    R.titlebar = CreateFrame("Frame", nil, f)
    -- Spanning the panel it owns both top corners. Inset to the pane beside
    -- a full-height rail, its top-LEFT is an interior edge butting against
    -- that rail, and a rounded corner there reads as a notch.
    app.paintTitleFull, app.paintTitlePane =
        corners(R.titlebar, "B", "BL", "titlebarBg")
    edgeFrom(R.titlebar, "divider", "BOTTOM")

    -- Full width, below the title bar. Home for a level-1 navigator when the
    -- app wants a top button bar instead of (or as well as) the rail tree.
    R.top = CreateFrame("Frame", nil, f)
    -- Square on all four normally -- it is an interior band under the title
    -- bar. With a full-height rail and no title bar left above it, its
    -- top-right IS the panel's, and it rounds that one.
    app.paintTopFlat, app.paintTopCorner =
        corners(R.top, "TB", "BL", "railBg")
    edgeFrom(R.top, "divider", "BOTTOM")

    -- The rail and its footer reach the bottom-left corner whenever the
    -- status bar is hidden, so both round that one corner.
    R.rail = CreateFrame("Frame", nil, f)
    -- Bottom-left always; top-left as well once the rail reaches the panel's
    -- top edge, where the head sits over it and rounds the same corner --
    -- both, because the head is collapsed in every other layout and the
    -- rail's own fill is what shows there.
    app.paintRailBody, app.paintRailFull =
        corners(R.rail, "TR", "R", "railBg")
    edgeFrom(R.rail, "railBorder", "RIGHT")

    -- The rail's head, and shown ONLY when the rail spans the full height:
    -- with the title bar reduced to the pane's width, the panel's icon and
    -- title have nowhere else to be, and the head is also what the reader
    -- drags. Built always and collapsed to nothing in every other layout,
    -- so the search header below it is anchored to something real rather
    -- than to a frame that may or may not exist.
    R.railbrand = CreateFrame("Frame", nil, R.rail)
    corner(R.railbrand, "BR", "titlebarBg")
    -- NO bottom divider. The head is not a bar the rail hangs under -- it
    -- is the top of the rail, and a rule across it cuts the one column the
    -- layout exists to make read as one column.
    --
    -- It does carry the rail's RIGHT edge, for the same reason the footer
    -- does: the head is a child frame drawn over the rail, so its own fill
    -- covers that stretch of the rail's edge line, and the border visibly
    -- thinned for the height of the head.
    edgeFrom(R.railbrand, "railBorder", "RIGHT")

    R.footer = CreateFrame("Frame", nil, R.rail)
    corner(R.footer, "TR", "footerBg")
    edgeFrom(R.footer, "divider", "TOP")
    -- The footer is a CHILD of the rail, so its own fill draws over the
    -- rail's right-hand edge line. It carries its own copy of that edge or
    -- the border simply stops where the footer starts.
    edgeFrom(R.footer, "railBorder", "RIGHT")

    R.pane = CreateFrame("Frame", nil, f)

    R.pageheader = CreateFrame("Frame", nil, R.pane)

    R.body = CreateFrame("Frame", nil, R.pane)

    R.statusbar = CreateFrame("Frame", nil, f)
    -- TWO fills, because RoundedFill bakes which corners stay square and
    -- there is no re-siding it afterwards.
    --
    -- Spanning the full width, the strip owns both bottom corners of the
    -- panel and rounds them. Spanning only the body, its bottom-LEFT is an
    -- interior edge butting against the rail, and a rounded corner there
    -- reads as a notch -- the panel's real bottom-left corner is the rail's
    -- in that mode, and the rail already rounds it. So both are built once
    -- and the inactive one is painted transparent, which costs two textures
    -- and no branching at layout time.
    local paintFull, setRadiusFull = ns.RoundedFill(R.statusbar, "BACKGROUND", rr, "T",  skin.statusbarBg)
    local paintBody, setRadiusBody = ns.RoundedFill(R.statusbar, "BACKGROUND", rr, "TL", { 0, 0, 0, 0 })
    app.paintStatusFull, app.paintStatusBody = paintFull, paintBody
    -- Registered like every other corner, so a radius change reaches both
    -- variants and not only whichever happens to be visible.
    app.cornerSetters[#app.cornerSetters + 1] = setRadiusFull
    app.cornerSetters[#app.cornerSetters + 1] = setRadiusBody
    edgeFrom(R.statusbar, "divider", "TOP")

    return R
end

-- Anchoring is re-run on every resize and whenever a region's declared
-- size changes (rail width, footer height as slots are added in P0.2).
function LayoutRegions(app)
    local f, R, skin = app.frame, app.regions, app.skin
    if not f then return end

    -- The rail's floor is the skin's minimum OR whatever its footer buttons
    -- need, whichever is larger. Published by RenderFooter, which is the
    -- only thing that knows how wide the widest button's label makes it.
    -- A full-span footer is not constrained by the rail, so the rail's
    -- floor goes back to the skin's own minimum.
    local railMin = math.max(skin.railWidthMin,
                    (app.footerSpan == "full") and 0 or (app.footerMinWidth or 0))
    local railW   = math.max(railMin, math.min(skin.railWidthMax, app.railWidth or skin.railWidth))
    -- The title bar grows when its button bar wraps to a second row, so its
    -- height is an app-level value with the skin token as the floor rather
    -- than a constant.
    local titleH  = math.max(skin.titlebarHeight, app.titlebarHeight or 0)
    -- The rail reaching the panel's top edge inverts the anchoring: the
    -- rail hangs off the FRAME and the title bar and top strip hang off the
    -- rail, rather than the other way round. With the head carrying the
    -- title and the strip carrying the close button, the title bar itself
    -- has nothing left in it, so it collapses.
    local railTop = (app.railSpan == "full") and (app.railShown ~= false)
    -- Collapsed only when it is EMPTY -- and only when a top strip is
    -- there to become the panel's top row in its place. A spec is free to
    -- ask for a full-height rail AND a button bar in the title bar, and
    -- collapsing a bar that has one in it would hide a navigator. With
    -- neither bar contents nor a strip, the bar stays, blank: it is what
    -- carries the close button and what the reader drags the panel by,
    -- and without it the page body ran to the panel's top edge, put the
    -- scrollbar under the X, and left the top of the pane dead to a drag.
    local collapsed = railTop and not app.titlebarOccupied
                      and (app.topHeight or 0) > 0
    if collapsed then titleH = 0 end
    -- Published for the search box, whose "title bar always exists" fallback
    -- is exactly the assumption this layout breaks.
    app.titlebarLive = titleH > 0
    local statusH = app.statusbarShown and (app.statusHeight or skin.statusbarHeight) or 0
    local footerH = app.footerHeight or 0
    local phH     = app.pageheaderHeight or 0

    R.titlebar:ClearAllPoints()
    -- Every region is inset by the border stroke, so the rounded border is
    -- never overdrawn and the corners stay clean.
    -- Regions are FLUSH with the frame, not inset by the stroke.
    --
    -- They used to be inset by 1px so the border could show past them. But
    -- a region inset by 1 while keeping the same corner radius draws an arc
    -- that CROSSES the background's arc rather than following it, leaving a
    -- sliver at every corner and three stacked anti-aliased edges. Flush and
    -- at the same radius, the two arcs coincide exactly. The border no
    -- longer needs the gap because it is drawn on an overlay above the
    -- regions -- see BuildBorder.
    -- Flush: the border is on an overlay above the regions, so it needs no
    -- gap, and a region inset by 1 at the same radius would trace an arc
    -- that crosses the background's rather than following it.
    local bi = 0
    if railTop then
        R.titlebar:SetPoint("TOPLEFT",  f, "TOPLEFT",   bi + railW, -bi)
    else
        R.titlebar:SetPoint("TOPLEFT",  f, "TOPLEFT",   bi, -bi)
    end
    R.titlebar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -bi, -bi)
    R.titlebar:SetHeight(math.max(titleH, 0.001))
    R.titlebar:SetShown(titleH > 0)

    -- The strip either crosses the whole panel, below the rail's footer
    -- buttons, or starts at the rail's right edge and sits BESIDE them,
    -- taking its width out of the body instead of out of the whole panel.
    -- With the rail hidden the two are the same thing, so "body" resolves
    -- to the frame edge rather than anchoring to a region that is not shown.
    local bodySpan = (app.statusSpan == "body") and (app.railShown ~= false)

    -- What sits at the very bottom of the panel, and what sits above it.
    --
    --   full-width footer + body strip   footer at the bottom, across the
    --                                    whole panel; the strip above it,
    --                                    inset to the body -- which is what
    --                                    "body only" is asking for.
    --   full-width footer + full strip   the strip keeps the bottom, since
    --                                    asking for full width is asking to
    --                                    reserve that band; the footer above.
    --   rail-span footer                 unchanged: the footer is inside the
    --                                    rail and neither of these applies.
    --
    -- The gap that got reported came from lowering the rail by the footer's
    -- height while placing the footer above the STRIP's height as well: with
    -- a body strip that left a statusH-tall band under the rail with nothing
    -- in it, and put the strip below the footer. Every region below now
    -- subtracts exactly what is underneath it and nothing else.
    local fullFooter = (app.footerSpan == "full") and footerH > 0
    local footerLift = fullFooter and footerH or 0
    local footerAtBottom = fullFooter and bodySpan
    local stripLift  = footerAtBottom and footerH or 0
    local footerBase = footerAtBottom and 0 or statusH

    R.statusbar:ClearAllPoints()
    if bodySpan then
        R.statusbar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
                             bi + railW, bi + stripLift)
    else
        R.statusbar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", bi, bi + stripLift)
    end
    R.statusbar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -bi, bi + stripLift)
    R.statusbar:SetHeight(math.max(statusH, 1))
    R.statusbar:SetShown(app.statusbarShown and true or false)

    local clear = { 0, 0, 0, 0 }
    if app.paintStatusFull then
        app.paintStatusFull(bodySpan and clear or skin.statusbarBg)
        app.paintStatusBody(bodySpan and skin.statusbarBg or clear)
    end

    -- Which corner each layout-dependent region rounds. `paneTitle` is the
    -- title bar inset beside a full-height rail; `topCorner` is the strip
    -- having become the panel's top row, which only happens when the title
    -- bar above it collapsed.
    local paneTitle = railTop
    local topCorner = collapsed
    if app.paintTitleFull then
        app.paintTitleFull(paneTitle and clear or skin.titlebarBg)
        app.paintTitlePane(paneTitle and skin.titlebarBg or clear)
    end
    if app.paintTopFlat then
        app.paintTopFlat(topCorner and clear or skin.railBg)
        app.paintTopCorner(topCorner and skin.railBg or clear)
    end
    if app.paintRailBody then
        app.paintRailBody(railTop and clear or skin.railBg)
        app.paintRailFull(railTop and skin.railBg or clear)
    end

    local topH = app.topHeight or 0
    R.top:ClearAllPoints()
    R.top:SetPoint("TOPLEFT",  R.titlebar, "BOTTOMLEFT",  0, 0)
    R.top:SetPoint("TOPRIGHT", R.titlebar, "BOTTOMRIGHT", 0, 0)
    R.top:SetHeight(math.max(topH, 1))
    R.top:SetShown(topH > 0)

    -- Everything below the top strip hangs off it, so adding or removing a
    -- top navigator re-flows the whole panel with no other change.
    local underTop = (topH > 0) and R.top or R.titlebar

    R.rail:ClearAllPoints()
    if railTop then
        R.rail:SetPoint("TOPLEFT", f, "TOPLEFT", bi, -bi)
    else
        R.rail:SetPoint("TOPLEFT", underTop, "BOTTOMLEFT", 0, 0)
    end
    -- In body span the strip is beside the rail, not under it, so the rail
    -- keeps its full height and its footer buttons sit level with the strip.
    -- A FULL-span footer runs the width of the panel, so the rail and the
    -- page both stop above it. Rail span (the default) keeps the footer
    -- inside the rail, where it has always been.

    R.rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", bi,
                    (bodySpan and 0 or statusH) + bi + footerLift)
    R.rail:SetWidth(railW)
    R.rail:SetShown(app.railShown ~= false)

    if app.railSplitter then
        app.railSplitter:ClearAllPoints()
        app.railSplitter:SetPoint("TOPRIGHT",    R.rail, "TOPRIGHT",    2, 0)
        app.railSplitter:SetPoint("BOTTOMRIGHT", R.rail, "BOTTOMRIGHT", 2, 0)
        app.railSplitter:SetShown(app.railShown ~= false and not app.locked)
    end

    -- The head is as tall as WHATEVER SITS BESIDE IT, so the logo lines up
    -- with the section buttons rather than with a nominal title-bar height
    -- the strip does not share. The strip is the row beside it in this
    -- layout; a live title bar takes that place when one is mounted; and
    -- with neither, the skin's title-bar height is the honest default.
    -- A bar that wraps to two rows takes the head with it, which is what
    -- keeps the two aligned at every width.
    -- ONE ROW of it, never the whole band. A bar that wraps to a second row
    -- grows the region it is in, and taking that height would walk the rail's
    -- logo downwards every time the panel got narrow enough to wrap -- a rail
    -- that changes shape because something in the PANE did. Capped at the
    -- region's real height as well, so a stale row height from a previous
    -- chrome can never make the head taller than what it sits beside.
    local brandH = 0
    if railTop then
        if titleH > 0 then
            brandH = math.min(titleH, app.titlebarRowHeight or titleH)
        elseif topH > 0 then
            brandH = math.min(topH, app.topRowHeight or topH)
        else
            brandH = math.max(skin.titlebarHeight, 1)
        end
    end
    R.railbrand:ClearAllPoints()
    R.railbrand:SetPoint("TOPLEFT",  R.rail, "TOPLEFT",  0, 0)
    R.railbrand:SetPoint("TOPRIGHT", R.rail, "TOPRIGHT", 0, 0)
    R.railbrand:SetHeight(math.max(brandH, 0.001))
    R.railbrand:SetShown(brandH > 0)
    app.railBrandHeight = brandH

    R.footer:ClearAllPoints()
    if fullFooter then
        R.footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   bi, footerBase + bi)
        R.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -bi, footerBase + bi)
    else
        R.footer:SetPoint("BOTTOMLEFT",  R.rail, "BOTTOMLEFT",  0, 0)
        R.footer:SetPoint("BOTTOMRIGHT", R.rail, "BOTTOMRIGHT", 0, 0)
    end
    R.footer:SetHeight(math.max(footerH, 1))
    R.footer:SetShown(footerH > 0)

    R.pane:ClearAllPoints()
    if railTop then
        -- Beside the rail AND below the strip: the strip's own left edge is
        -- already the rail's right one, so hanging the pane off it puts both
        -- in the same column with one anchor rather than two.
        R.pane:SetPoint("TOPLEFT", underTop, "BOTTOMLEFT", 0, 0)
    elseif app.railShown == false then
        R.pane:SetPoint("TOPLEFT", underTop, "BOTTOMLEFT", 0, 0)
    else
        R.pane:SetPoint("TOPLEFT", R.rail, "TOPRIGHT", 0, 0)
    end
    R.pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -bi, statusH + bi + footerLift)

    R.pageheader:ClearAllPoints()
    R.pageheader:SetPoint("TOPLEFT",  R.pane, "TOPLEFT",  0, 0)
    R.pageheader:SetPoint("TOPRIGHT", R.pane, "TOPRIGHT", 0, 0)
    R.pageheader:SetHeight(math.max(phH, 1))
    R.pageheader:SetShown(phH > 0)

    R.body:ClearAllPoints()
    R.body:SetPoint("TOPLEFT",     R.pane, "TOPLEFT",     0, -phH)
    R.body:SetPoint("BOTTOMRIGHT", R.pane, "BOTTOMRIGHT", 0, 0)

    -- With nothing under the pane -- no status strip, no full-width footer
    -- -- its bottom-right corner is the panel's, and the resize grip lives
    -- there. The page scrollbar stops short of it by the grip's height
    -- plus its inset (16 + 2), read by the page on each render.
    local paneAtBottom = (statusH + footerLift) == 0
    app.scrollbarClearBottom = paneAtBottom and 18 or 0
    if app.scroll then app.scroll.barClearBottom = app.scrollbarClearBottom end

    -- The title bar's furniture follows the mode. Done here rather than at
    -- build time because the layout is switchable at runtime, and a close
    -- button left in a collapsed title bar is a close button nobody can
    -- click.
    if app.PlaceChrome then app:PlaceChrome(railTop) end
end

-- ── Title bar contents ─────────────────────────────────────────
local function BuildTitlebar(app)
    local R, skin = app.regions, app.skin
    local bar = R.titlebar

    if app.icon then
        local ico = bar:CreateTexture(nil, "ARTWORK")
        ico:SetTexture(app.icon)
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", bar, "LEFT", skin.padding, 0)
        app.titleIcon = ico
    end

    -- Vertically CENTERED in the bar, whatever height it ends up.
    --
    -- These were briefly pinned to a fixed first row, on the reasoning that a
    -- button bar mounted here can wrap and anything centered would drift down
    -- with it. That optimized for the two-row case at the cost of the
    -- one-row one, which is the case actually on screen: a single row of
    -- buttons makes the bar 36 tall, the buttons center in it because their
    -- own packing is what derived that height, and a title still pinned to
    -- the 30-pixel bar's center sat three pixels high and visibly out of
    -- line with them.
    --
    -- Centered, one row lines up exactly and a wrapped bar reads as a title
    -- set against the button block, which is how such bars usually look.
    local title = ns.FS(bar, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", app.titleIcon or bar, app.titleIcon and "RIGHT" or "LEFT",
                   app.titleIcon and 7 or skin.padding, 0)
    title:SetText(app.title or app.id)
    local c = skin.textHeading
    title:SetTextColor(c[1], c[2], c[3])
    app.titleText = title

    -- Close button. Ours, on our own frame -- there is no foreign close
    -- button to find by child-scanning and hide, which is what a panel
    -- built on a shared frame has to do.
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(26, 26)
    -- Pinned to the bar's TOP right, not centered in its height. The title
    -- bar grows when a button bar mounted in it wraps to a second row, and
    -- a centered close button drifts down with it -- so the one control on
    -- the panel whose position everybody knows by muscle memory would move
    -- depending on what else is in the bar. The top edge does not move.
    --
    -- THE SAME OFFSET ON BOTH AXES. The bar's top-right corner IS the
    -- panel's, so these two numbers are the gap the reader sees between the
    -- X and the panel's border -- and they were 6 and 2, which is why the
    -- X looked pushed in from the right. Equal in, equal down.
    close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -2)
    local x = ns.FS(close, "OVERLAY", "GameFontNormalLarge")
    x:SetPoint("CENTER")
    x:SetText("\195\151")     -- multiplication sign, reads as a clean X
    -- Scaled off whatever the font object's size is rather than hardcoded,
    -- so it stays in proportion if the panel's fonts are ever restyled.
    local face, size, flags = x:GetFont()
    if face then x:SetFont(face, size * 1.92, flags) end
    local m = skin.textMuted
    x:SetTextColor(m[1], m[2], m[3])
    close:SetScript("OnEnter", function()
        local t = skin.text; x:SetTextColor(t[1], t[2], t[3])
    end)
    close:SetScript("OnLeave", function() x:SetTextColor(m[1], m[2], m[3]) end)
    close:SetScript("OnClick", function() app:Close() end)
    app.closeButton = close

    -- Dragging moves the panel. The same two handlers serve the title bar
    -- and the rail's head, because in a full-height-rail layout the title
    -- bar is collapsed and the head is the only chrome left to grab.
    local function StartDrag()
        if app.locked then return end
        app.frame:StartMoving()
    end
    local function StopDrag()
        app.frame:StopMovingOrSizing()
        -- Land on whole pixels, or every hairline in the panel is drawn
        -- across two of them for the rest of the session.
        ns.SnapGeometry(app.frame)
        -- The clamp should have refused an unusable spot already; this is
        -- the backstop for the cases it cannot see (a release outside the
        -- window, a client without the clamp API), so an unreachable
        -- position is never what gets SAVED.
        ns.EnsureOnScreen(app.frame)
        SaveGeometry(app, app.frame)
    end
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", StartDrag)
    bar:SetScript("OnMouseUp",   StopDrag)

    -- The top strip drags the panel too, from anywhere its buttons are
    -- not: the gaps between them, the inset above them, and the run
    -- between the last button and the close button. In a full-height-rail
    -- layout this strip IS the panel's top row -- the title bar it would
    -- otherwise have been dragged by is collapsed -- so without this the
    -- panel's whole top edge is dead to the mouse.
    --
    -- Safe in every other layout for the reason it works here: the buttons
    -- and the close button are child frames at a higher level and take
    -- their own clicks, so only the bar's own background reaches this.
    R.top:EnableMouse(true)
    R.top:SetScript("OnMouseDown", StartDrag)
    R.top:SetScript("OnMouseUp",   StopDrag)

    -- ── The rail's head ────────────────────────────────────────
    -- A second copy of the icon and the title rather than a reparenting of
    -- the first: the two live in regions with different anchors and
    -- different heights, and moving one widget between them meant undoing
    -- its points on every layout switch. Two widgets, one of which is
    -- hidden, is the cheaper and less breakable answer.
    -- The DRAG is on a child inset from the rail's right edge, not on the
    -- head itself. The head spans the rail's full width, and the rail
    -- splitter's grab strip straddles that same edge -- so a mouse-enabled
    -- head is a second claim on the strip the reader drags to resize the
    -- rail. Inset by the splitter's own width, the two never overlap and
    -- the rail stays resizable along its whole height.
    local head = R.railbrand
    local grab = CreateFrame("Frame", nil, head)
    grab:SetPoint("TOPLEFT",     head, "TOPLEFT",      0, 0)
    grab:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -SPLIT_W, 0)
    grab:EnableMouse(true)
    grab:SetScript("OnMouseDown", StartDrag)
    grab:SetScript("OnMouseUp",   StopDrag)
    app.railBrandGrab = grab

    if app.icon then
        local ico = head:CreateTexture(nil, "ARTWORK")
        ico:SetTexture(app.icon)
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", head, "LEFT", skin.padding, 0)
        app.railIcon = ico
    end

    local railTitle = ns.FS(head, "OVERLAY", "GameFontNormal")
    railTitle:SetPoint("LEFT", app.railIcon or head, app.railIcon and "RIGHT" or "LEFT",
                       app.railIcon and 7 or skin.padding, 0)
    -- The close button never rides here (it goes to the strip, or to the
    -- panel's own corner), so the head keeps only its ordinary padding.
    railTitle:SetPoint("RIGHT", head, "RIGHT", -skin.padding, 0)
    railTitle:SetJustifyH("LEFT")
    railTitle:SetText(app.title or app.id)
    railTitle:SetTextColor(c[1], c[2], c[3])
    app.railTitleText = railTitle

    -- The version, muted and right-aligned: an identity line rather than a
    -- second title, which is why it is smaller and dimmer than the name it
    -- follows. Declared per app because the library has no idea what it is
    -- embedded in -- a string or a function, so a consumer can read it from
    -- its .toc at first paint rather than at load.
    --
    -- The HEAD only. The title bar is the other place a title lives, and in
    -- every layout that has one the bar is also where a button bar or the
    -- search box goes -- a version competing with those for the same row is
    -- how a title bar ends up unreadable at narrow widths.
    local ver = app.version
    if type(ver) == "function" then ver = ver(app) end
    if ver and ver ~= "" then
        local vt = ns.FS(head, "OVERLAY", "GameFontNormalSmall")
        vt:SetPoint("RIGHT", head, "RIGHT", -skin.padding, 0)
        local vf, vs, vfl = vt:GetFont()
        if vf then vt:SetFont(vf, math.max(9, (vs or 12) - 1), vfl) end
        local m = skin.textMuted
        vt:SetTextColor(m[1], m[2], m[3])
        vt:SetText(tostring(ver))
        app.railVersionText = vt
        -- The title stops before it, or a long addon name draws straight
        -- through the version at a narrow rail width.
        railTitle:SetPoint("RIGHT", vt, "LEFT", -6, 0)
    end

    -- Which chrome is on show, and where the close button lives.
    --
    -- The close button is ONE button that moves, unlike the title, because
    -- its position is a single point in whichever region it lands in and
    -- there is no second one to keep in step. The strip takes it when there
    -- is a strip; the head takes it when there is not.
    function app:PlaceChrome(railTop)
        local shown = railTop and true or false
        if self.railIcon then self.railIcon:SetShown(shown) end
        if self.railTitleText then self.railTitleText:SetShown(shown) end
        if self.railVersionText then self.railVersionText:SetShown(shown) end
        if self.titleIcon then self.titleIcon:SetShown(not shown) end
        if self.titleText then self.titleText:SetShown(not shown) end

        local host = R.titlebar
        if railTop and self.titlebarLive == false then
            -- The strip first, because it is the panel's top-right corner
            -- in this layout and that is where the X has always been. With
            -- no strip either, the PANEL ITSELF: its top-right corner is
            -- the pane's, and the X belongs there, not at the top of the
            -- rail. It used to fall back to the rail's head, which put it
            -- at the top-right of the tree -- and under the head's drag
            -- frame, so a click on it started a drag instead of closing.
            host = ((self.topHeight or 0) > 0) and R.top or self.frame
        end
        local close = self.closeButton
        if close and close:GetParent() ~= host then
            close:SetParent(host)
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, -2)
            -- On the frame it overlaps the pane and whatever page header
            -- is at its top, so it sits well above them; in a bar or
            -- strip it is a child like any other and the parent's level
            -- plus one is right.
            if host == self.frame then
                close:SetFrameLevel(self.frame:GetFrameLevel() + 30)
            else
                close:SetFrameLevel(host:GetFrameLevel() + 1)
            end
        end
    end
end

-- ── Public entry point used by the library file ────────────────
function ns.BuildFrame(app)
    -- App-prefixed global name: needed for UISpecialFrames (escape-to-close),
    -- and unique per app so two apps can never collide in _G.
    local name = "BuzzardPanel_" .. tostring(app.id):gsub("[^%w_]", "_")

    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    -- One unit = a whole number of pixels inside the panel. Before anything
    -- is sized or placed, so every number below is already on the grid.
    StampPanelScale(f, app)
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function() ns.RestampPanel(app) end)
    -- NOT clamped to the screen. Dragging a panel partly off the edge is a
    -- legitimate thing to want -- to see what is underneath it, or to park
    -- it -- and clamping silently refuses. The title bar cannot be lost
    -- because the drag handle is the title bar itself.
    f:SetClampedToScreen(false)
    f:EnableMouse(true)             -- swallow clicks so they do not fall through
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(app.skin.minWidth, app.skin.minHeight,
                          app.skin.maxWidth, app.skin.maxHeight)
    end
    f:Hide()

    -- The panel background is no longer a texture of its own: it is the
    -- inner half of the border pair BuildBorder creates below, so the
    -- background and the stroke can never disagree about the corner.
    app.frame   = f
    app.regions = BuildRegions(app, f)

    LoadGeometry(app, f)
    ns.SnapGeometry(f)
    ns.EnsureOnScreen(f)
    LayoutRegions(app)
    BuildTitlebar(app)
    -- BuildTitlebar is what defines PlaceChrome, so the layout pass above
    -- could not have run it. Run it now, or the first paint of a
    -- full-height-rail layout shows both titles.
    app:PlaceChrome((app.railSpan == "full") and (app.railShown ~= false))
    app.resizeGrip  = BuildResizeGrip(app, f)
    BuildRailSplitter(app, f)
    app.resizeRight = BuildEdgeHandle(app, f, "RIGHT")
    app.resizeBottom = BuildEdgeHandle(app, f, "BOTTOM")
    BuildBorder(app, f)

    -- Live re-layout while dragging the resize grip.
    --
    -- LayoutRegions is geometry only: it moves the regions and stops. Their
    -- CONTENTS are laid out from a region's width at render time and then
    -- never revisited, so a resize left the status strip's cells sized for
    -- the old width -- the right-hand one hanging outside the frame until
    -- something else forced a render -- and left a wrapped button bar
    -- wrapped for a width that no longer existed.
    --
    -- Throttled rather than per-frame, because a grip drag fires this on
    -- every frame and a full nav refresh rebuilds every navigator and the
    -- page. Deliberately NOT on ns.effects: that scheduler gates on combat
    -- at fire time, which is right for a setting's side effect and wrong
    -- for laying out a frame the reader is dragging right now.
    f:SetScript("OnSizeChanged", function(_, w, h)
        if app.borderFrame then StampPixelHost(app.borderFrame, f) end
        if app.bgFrame     then StampPixelHost(app.bgFrame,     f) end
        LayoutRegions(app)
        ns.ReflowSoon(app)
        -- After the regions have moved, so a consumer measuring one gets the
        -- new geometry rather than the previous frame's. The size is passed
        -- through from the handler, falling back to the frame for the callers
        -- that resize it in code and supply nothing.
        if app.onResize then
            app.onResize(app, w or f:GetWidth(), h or f:GetHeight())
        end
    end)

    -- Hiding is the ONE place the panel is closed.
    --
    -- Escape closes through UISpecialFrames, which calls f:Hide() directly:
    -- App:Close() never runs, so a consumer's onClose used to be skipped and
    -- the geometry left as whatever the last drag saved. Doing both here
    -- means the X, escape and any external :Hide() are the same event, and
    -- App:Close() is now only "hide the frame".
    f:SetScript("OnShow", function(self)
        -- The screen may have changed while the panel was hidden -- UI
        -- scale, resolution, another addon's pixel-perfect toggle -- so
        -- every open re-checks that the panel is reachable.
        ns.EnsureOnScreen(self)
    end)
    f:SetScript("OnHide", function()
        -- A box still being typed in when the X (or anything else) hid the
        -- panel would otherwise keep the focus. See ClearFocusWithin.
        ClearFocusWithin(f)
        SaveGeometry(app, f)
        if app.onClose then app.onClose(app) end
    end)

    -- Escape closes the focused panel.
    tinsert(UISpecialFrames, name)

    return f
end

ns.LayoutRegions = LayoutRegions
ns.SaveGeometry  = SaveGeometry
