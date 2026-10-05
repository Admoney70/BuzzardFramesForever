-- ============================================================
-- BuzzardPanel: Attach.lua
-- Elements anchored to a node, by ZONE NAME rather than by frame.
--
-- A page, a group or a row can carry small elements that are not fields --
-- a remove X in a card's corner, a reset button in a header. The obvious
-- way to build those is to reach for the frame and anchor to it. That is
-- what the panel this replaces does, and it is why removing a container
-- there costs 120 lines of re-parenting one shared button onto whichever
-- pooled widget happens to be showing at the time.
--
-- -- Zones, not frames --
--
-- An attachment names a ZONE that its host publishes, and the library
-- resolves the name to a frame at build time. Two things fall out of that:
--
--   * The consuming addon never holds a frame reference, which is what
--     keeps the isolation rule intact -- one app cannot reach another's
--     widgets, or its own pooled ones after they have been released.
--   * A zone survives layout changes. If a card later grows a footer,
--     `outerTopRight` still means the same corner.
--
-- -- Pooled with the host --
--
-- Attachments are acquired from the app's pool when their host is built
-- and released with it. A pooled host never keeps an attachment from its
-- previous life, because the release scrubs it -- the alternative is the
-- stale-state class in §22.8, where a widget comes back still wearing
-- something the last field left on it.
--
-- -- Scope --
--
-- Only what has a consumer: `float` mode, and the two zones a collection's
-- corner X needs. `flow` mode and the full zone table in §4 are real, and
-- they are not built here, because a zone nothing anchors to is a guess
-- about a layout that does not exist yet.
-- ============================================================
local ADDON, ns = ...

ns.attach = {}

-- ── Zones ──────────────────────────────────────────────────────
--
-- A zone resolver returns the frame to anchor against and the anchor
-- points to use. Adding a zone is adding a row here; nothing else in the
-- library needs to know about it.

local ZONES = {
    -- A card's outer top-right corner, OVERHANGING the card edge. For the
    -- affordance that acts on the card as a whole -- remove, collapse --
    -- rather than on anything inside it.
    group_outerTopRight = function(host)
        return host, "TOPRIGHT", "TOPRIGHT"
    end,
    -- Inside the card's header row, right-aligned.
    group_headerRight = function(host)
        return host.header or host, "RIGHT", "RIGHT"
    end,
    -- The group's own top-right corner, INSET so the X sits inside the
    -- group's bounds rather than overhanging its edge. For a PLAIN or TAB
    -- header, which has no full-width header row for the X to live in -- the
    -- affordance acts on the whole group, so it hangs from the group corner.
    group_innerTopRight = function(host)
        -- The BOX, not the frame. A tab or plain header sits ABOVE the box,
        -- so the group frame's top-right is up at the header's level, out of
        -- the visible group. The box (host.surface) is the group the reader
        -- sees; its top-right corner is where the X belongs.
        return host.surface or host, "TOPRIGHT", "TOPRIGHT"
    end,
    -- The page header strip, right-aligned.
    page_pageheaderRight = function(host)
        return host, "RIGHT", "RIGHT"
    end,
    -- A tree group's top-right corner. The affordance that acts on the
    -- member the pane is showing -- remove -- belongs to the pane rather
    -- than to whichever card happens to be drawn first in it: the pane is
    -- the member, and a card is one part of it.
    --
    -- Anchored to the CARD, not to the pane. They share a right edge, so
    -- the offsets read the same horizontally -- but the pane starts a
    -- card's padding BELOW the card's top border, so the same two numbers
    -- meant 5 from the border across and 5 + the padding down, and the X
    -- sat visibly lower than it was inset. The card's corner is the corner
    -- the reader sees, so that is the corner it hangs off: equal offsets,
    -- equal gaps, nothing to compensate for.
    pane_topRight = function(host)
        return (host.bpCard or host), "TOPRIGHT", "TOPRIGHT"
    end,
}

function ns.attach.HasZone(hostKind, zone)
    return ZONES[hostKind .. "_" .. zone] ~= nil
end

-- Which corner of a CARD an X that acts on the whole card belongs in, and
-- the offsets that put it there: `headerRight` inside the header row of a
-- bar-headed card, `innerTopRight` -- the body's own corner -- for a PLAIN
-- or TAB header, which has no full-width header row to hold it (plain draws
-- no header chrome, a tab's header is only as wide as its label), and
-- `outerTopRight` for a card with no title at all. One answer for the
-- collection's corner X and for any page that hangs its own X on a card,
-- so the two cannot disagree when the card style changes.
--
-- The offsets are negative so the button clears the card's own 1px border
-- rather than sitting on it. Returns zone, x, y.
function ns.attach.CardCornerZone(app, group)
    local presets = app and app.groupPresets
    local preset  = presets and (presets[group.preset or "default"] or presets.default)
    local shape   = preset and preset.headerShape
    local zone
    if shape == "plain" or shape == "tab" then
        zone = "innerTopRight"
    else
        zone = group.title and "headerRight" or "outerTopRight"
    end
    return zone, ns.attach.CornerOffsets(zone)
end

-- The x, y an X wears in each corner zone. `topRight` is the tree pane's.
function ns.attach.CornerOffsets(zone)
    if zone == "headerRight" then return -4, 0 end
    if zone == "topRight" or zone == "innerTopRight" then return -5, -5 end
    return -6, -6
end

-- ── Building ───────────────────────────────────────────────────

local function AttachFactory(app)
    local b = CreateFrame("Button", nil, app:GetRegion("body"))
    b:SetSize(18, 18)
    b.ring, b.bg = ns.BorderedRound(b, 6, "BACKGROUND", "BORDER")
    ns.SetBorder(b, b.ring)
    -- An optional icon from Media, for an attachment that wants art.
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER", 0, 0)
    b.icon:Hide()

    -- The label. GameFontNormalLarge, then SCALED to the button -- the same
    -- treatment the title bar's close button uses, and the reason that one
    -- looks right. A glyph set in a small font inside a larger button is
    -- small and sits oddly, which is a sizing problem rather than a reason
    -- to reach for a texture.
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalLarge")
    b.label:SetPoint("CENTER", 0, 0)
    return b
end

local function Paint(app, w, spec, hovered)
    local skin = app.skin
    local c    = spec.danger and skin.danger or skin.text
    if not spec.bare then
        w.bg:SetVertexColor(skin.controlBg[1], skin.controlBg[2], skin.controlBg[3], 1)
        ns.MarkBorder(w, skin, spec.danger and skin.danger or skin.controlBorder, 1)
    end
    local m = hovered and 1.25 or 0.85
    w.label:SetTextColor(math.min(1, c[1] * m), math.min(1, c[2] * m), math.min(1, c[3] * m), 1)
    w.icon:SetVertexColor(math.min(1, c[1] * m), math.min(1, c[2] * m), math.min(1, c[3] * m), 1)
end

-- Build one attachment against a host.
--
-- `hostKind` is what publishes the zones -- "group", "page" -- and `host`
-- is that node's frame. The spec is the declaration from the node or from
-- its group preset.
function ns.attach.Build(app, hostKind, host, spec, ctx)
    local resolver = ZONES[hostKind .. "_" .. (spec.zone or "")]
    if not resolver then return nil end

    local anchorTo, point, relPoint = resolver(host)
    if not anchorTo then return nil end

    local w = app:Acquire("attach", AttachFactory)
    w:SetParent(host)
    w:ClearAllPoints()
    -- `float` reserves nothing and overlays, with its offsets measured from
    -- the zone's own point. A flow mode that inserts into the zone's layout
    -- is specified in §4 and deliberately not built until something asks
    -- for it.
    w:SetPoint(point, anchorTo, relPoint, spec.x or 0, spec.y or 0)
    -- ABOVE the header's own hit frames, not merely above the card body.
    -- A card's header carries a full-width right-click catcher (g.headerHit)
    -- and its label/read-out hit areas, built at host+5 .. host+8; a
    -- mouse-enabled frame swallows hit-testing for EVERY button whatever it
    -- is registered for, so an X sharing the header's level got no hover and
    -- no click. +10 clears the whole header stack for every zone -- the one
    -- inside the header row (headerRight) and the ones at the card's own
    -- corner (outerTopRight, a band/tab's inner corner) alike.
    w:SetFrameLevel(host:GetFrameLevel() + 10)

    local side = spec.size or 26
    w:SetSize(side, side)

    -- `bare` draws the mark and nothing else -- no border, no fill -- which
    -- is what the title bar's close button is. A bordered button is right
    -- for an affordance that has to announce itself; the X does not, and a
    -- 26px box inside a 26px header row has nowhere to put its border
    -- anyway.
    local bare = spec.bare
    w.ring:SetShown(not bare)
    w.bg:SetShown(not bare)

    if spec.icon then
        w.icon:SetTexture(ns.MEDIA .. spec.icon .. ".tga")
        -- Inset inside the button so the border reads as a border rather
        -- than as a box drawn tight around the mark. The art already
        -- carries its own margin, so this is a small one.
        local art = math.max(6, side - 6)
        w.icon:SetSize(art, art)
        w.icon:Show()
        w.label:SetText("")
    else
        w.icon:Hide()
        w.label:SetText(spec.text or "")
        -- ABSOLUTE, not a multiplier.
        --
        -- This read the CURRENT size and multiplied it, and Build runs on
        -- every render against a pooled button that comes back carrying
        -- last time's font -- so the glyph grew on every visit: 1.6, 2.56,
        -- 4.1. The title bar does the same arithmetic exactly once at
        -- creation, which is why it never drifts. Sizing from the button
        -- instead is idempotent by construction: applying it twice is the
        -- same as applying it once.
        local face, _, flags = w.label:GetFont()
        if face then
            w.label:SetFont(face, math.max(8, side * (spec.glyphScale or 0.95)), flags)
        end
    end

    -- `disabled` may be a bool or a predicate, resolved now: a disabled
    -- attachment dims, ignores clicks, and still shows its tooltip (which is
    -- where the REASON it is disabled belongs). `tooltip` may be a function,
    -- so that reason can be live state.
    local isOff = spec.disabled
    if type(isOff) == "function" then isOff = isOff() end
    isOff = isOff and true or false
    local function Tip(self)
        local tip = spec.tooltip
        if type(tip) == "function" then tip = tip() end
        if tip then ns.context.Show(self, app, tip) end
    end
    Paint(app, w, spec, false)
    w:SetAlpha(isOff and 0.4 or 1)
    w:SetScript("OnEnter", function(self)
        Paint(app, self, spec, not isOff)
        Tip(self)
    end)
    w:SetScript("OnLeave", function(self)
        Paint(app, self, spec, false)
        ns.context.Hide()
    end)
    w:SetScript("OnClick", function()
        if isOff then return end
        if spec.onClick then spec.onClick(spec, ctx) end
    end)
    w:Show()

    -- Which host's render built it; see the render-scope note above
    -- ns.page.ReleaseScope. An attachment on a card inside a tree pane goes
    -- back when that pane re-renders; one on a page-body card does not.
    w.bpScope = app.bpScope
    app.liveAttachments = app.liveAttachments or {}
    app.liveAttachments[#app.liveAttachments + 1] = w
    return w
end

-- Every attachment a host should carry: the ones it declares itself, plus
-- the ones its group preset gives every host of that kind. Declared ones
-- come last so a node can override a preset's by id.
function ns.attach.Specs(node, preset)
    local out, seen = {}, {}
    for _, spec in ipairs((preset and preset.attach) or {}) do
        out[#out + 1] = spec
        if spec.id then seen[spec.id] = #out end
    end
    for _, spec in ipairs(node.attach or {}) do
        local at = spec.id and seen[spec.id]
        if at then out[at] = spec else out[#out + 1] = spec end
    end
    return out
end

function ns.attach.BuildAll(app, hostKind, host, node, preset, ctx)
    for _, spec in ipairs(ns.attach.Specs(node, preset)) do
        ns.attach.Build(app, hostKind, host, spec, ctx)
    end
end

function ns.attach.ReleaseAll(app)
    for _, w in ipairs(app.liveAttachments or {}) do
        w:SetScript("OnClick", nil)
        w:SetScript("OnEnter", nil)
        w:SetScript("OnLeave", nil)
        app:Release(w)
    end
    app.liveAttachments = {}
end

-- The same, for ONE host's attachments.
--
-- `scopes` is a set of render scopes (see ns.page.ReleaseScope). An
-- attachment whose scope is in it goes back to the pool; every other one
-- stays live, in order, because the render that built it is not the render
-- being redone.
function ns.attach.ReleaseScope(app, scopes)
    local live = app.liveAttachments
    if not live then return end
    local keep = 0
    for i = 1, #live do
        local w = live[i]
        live[i] = nil
        if scopes[w.bpScope] then
            w:SetScript("OnClick", nil)
            w:SetScript("OnEnter", nil)
            w:SetScript("OnLeave", nil)
            app:Release(w)
        else
            keep = keep + 1
            live[keep] = w
        end
    end
end
