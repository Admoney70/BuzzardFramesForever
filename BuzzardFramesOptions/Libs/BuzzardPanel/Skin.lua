-- ============================================================
-- BuzzardPanel: Skin.lua
-- Color, spacing and metric tokens.
--
-- A skin is a flat table of tokens. Nothing in the library reads a
-- literal color: every drawn surface asks the app for a token, so a
-- consuming addon can restyle the whole panel by registering one skin
-- and naming it in NewApp.
--
-- Skins are registered on the LIBRARY (they are immutable data, shared
-- safely), but each app resolves and copies its own working table at
-- creation. Nothing an app does to its skin can reach another app --
-- see the isolation rule in BuzzardPanel.lua.
-- ============================================================
local ADDON, ns = ...

-- ── Diagnostics ────────────────────────────────────────────────
--
-- Somewhere to say "this should not have happened" that is neither an
-- error nor silence.
--
-- The failures that cost the most to find in this library have all been
-- QUIET ones: a route the reader could not have asked for, a frame drawn
-- by a page that had already left. Nothing threw, so nothing pointed at
-- them, and the report that reached us was a description of the symptom
-- several steps downstream. A library cannot throw on these -- a reader
-- mid-session does not want an error box because a navigator repaired
-- itself -- but it must not swallow them either.
--
-- Three behaviors, in order: the host's own handler if it registered one;
-- otherwise the game's error handler when the app is in `strict` mode,
-- which is what a developer wants and what a taint-free error display
-- shows; otherwise nothing at all. Living here because Skin.lua loads
-- first, so every other file can call it at load time as well as at
-- runtime.
function ns.Report(app, msg)
    if not msg then return end
    local fn = app and app.onDiagnostic
    if fn then
        local ok = pcall(fn, msg)
        if ok then return end
    end
    if app and app.strict and geterrorhandler then
        geterrorhandler()("BuzzardPanel: " .. tostring(msg))
    end
end

-- Where this copy's art lives, worked out rather than written down.
--
-- The library is used two ways: as its own addon, and VENDORED into a
-- consuming addon's Libs folder the way embedded libraries are. Those are
-- different paths on disk, and a hardcoded one means the vendored copy
-- silently finds no textures -- silently, because a missing texture file
-- draws nothing and raises nothing.
--
-- ADDON is the HOSTING addon's name, which the client passes to every file
-- it loads. When that is this library's own folder the art sits beside it;
-- otherwise this is an embedded copy at the conventional location, and the
-- path is the host plus that. Nothing per-copy has to be edited, which is
-- what stops the two drifting.
local MEDIA
if ADDON == "BuzzardPanel" then
    MEDIA = "Interface\\AddOns\\BuzzardPanel\\Media\\"
else
    -- An embedded copy sits at ONE conventional place: the host's Libs
    -- folder, in a folder named for the library. Tools/vendor_buzzardpanel.py
    -- is what puts it there, so the two agree by construction -- and getting
    -- this wrong costs no error, just a panel with no art.
    MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Libs\\BuzzardPanel\\Media\\"
end
ns.MEDIA = MEDIA

ns.skins = {}

-- Colors are {r, g, b, a}, 0-1. Metrics are pixels at UI scale 1.
ns.skins.default = {
    -- surfaces
    --
    -- The panel and the rail are slightly translucent, so what is behind
    -- them stays legible while you are configuring it -- the frames the
    -- panel exists to lay out are usually right underneath it. Everything a
    -- reader has to READ sits on an opaque surface: the group cards, the
    -- controls and the title bar are all solid, so text never has to fight
    -- the world behind it.
    -- The panel background is the ONLY layer between the panel and the
    -- world, so its alpha is the real transparency. Everything else on the
    -- chrome is a TINT drawn over it -- their alphas compound with this
    -- one, so they are low.
    -- The mockup's palette, to the digit (BuzzardPanel_TextLayouts.html):
    -- body #1b1a17, rail #151412, rail-hi #201e1b, lines #33302a/#413d34.
    -- The older options panel's own background, to the digit: it sets its
    -- tree frame and its content border to 0.1/0.1/0.1 at 0.92,
    -- and the two panels sitting side by side on the same screen should not
    -- disagree about what color Buzzard Frames is. Neutral rather than the
    -- mockup's warm #1b1a17, and a shade more transparent. Settled by
    -- living with it: a shade darker again, and a little less transparent
    -- than that panel, which is what a panel this size wants when the
    -- frames it configures are underneath it.
    panelBg        = { 0.090, 0.090, 0.086, 0.95 },   -- #171716 @ 0.95
    panelBorder    = { 0.255, 0.239, 0.204, 1.00 },   -- #413d34
    -- A TINT rather than nothing at all. The title bar is still the panel
    -- with a rule under it, but at this weight the top reads as its own
    -- band without becoming a separate darker one -- and it is the rail's
    -- color, so the two meet at the corner without a seam.
    titlebarBg     = { 0.078, 0.078, 0.071, 0.70 },   -- #141412 @ 0.70
    -- Translucent, like the panel itself. Opaque, the rail was the one
    -- piece of chrome that hid what was behind it outright.
    railBg         = { 0.078, 0.078, 0.071, 0.80 },   -- #141412 @ 0.80
    railBorder     = { 0.200, 0.188, 0.165, 1.00 },   -- #33302a
    bodyBg         = { 0.11, 0.10, 0.09, 0.00 },  -- transparent: panelBg shows through
    footerBg       = { 0.082, 0.078, 0.071, 1.00 },   -- the rail's own color
    statusbarBg    = { 0.125, 0.118, 0.106, 1.00 },   -- #201e1b
    divider        = { 0.200, 0.188, 0.165, 1.00 },   -- #33302a

    -- text
    text           = { 0.914, 0.898, 0.855, 1.00 },   -- #e9e5da
    textMuted      = { 0.518, 0.490, 0.431, 1.00 },   -- #847d6e
    textHeading    = { 0.914, 0.898, 0.855, 1.00 },   -- #e9e5da
    -- Description / note text. Lighter than textMuted, which is for things
    -- you are meant to skip -- a note is meant to be READ, and dimming it to
    -- the same level as a disabled label made it hard work.
    textNote       = { 0.957, 0.937, 0.894 , 1.00 },  -- #f4efe4

    -- accent (the consuming addon almost always overrides this one)
    -- A step darker than the #11ace9 it shipped as (owner, 2026-09-14):
    -- the switch knob, the slider thumb and the lit button border all
    -- wear it, and at full brightness they shouted.
    accent         = { 0.063, 0.627, 0.863, 1.00 },   -- #10a0dc
    -- The SELECTION tint -- a segmented control's chosen segment, the
    -- rail's selected row, a selected top-strip button -- at 0.30 rather
    -- than the mockup's 0.18 (owner, 2026-09-14: "a bit less dark").
    accentDim      = { 0.06, 0.63, 0.86, 0.30 },

    -- resize grip lines
    gripLine       = { 0.52, 0.49, 0.43, 0.80 },   -- textMuted at 0.8

    -- controls
    -- Nearly black, and darker than every surface a control can sit on --
    -- the card, the strip, the rail. A control is a WELL in the page, and
    -- at #1a1815 it was within a shade of the card behind it, so its border
    -- was doing all the work of saying where it began.
    controlBg      = { 0.063, 0.063, 0.059, 1.00 },   -- #10100f
    -- Lighter than the cards' own border: a control is a THING, and at the
    -- card's weight its edge disappeared into the surface holding it.
    controlBorder  = { 0.706, 0.627, 0.569, 1.00 },   -- #b4a091
    danger         = { 1.00, 0.42, 0.42, 1.00 },

    -- BUTTONS, four pairs rather than controlBg and text.
    --
    -- A button is the one control whose whole surface is the target, so it
    -- is also the one a reader may want to pick out from the wells around
    -- it -- and until these existed, tinting a button meant tinting every
    -- dropdown, box and swatch with it. Four pairs and not one, because a
    -- button's color is the first thing that says what pressing it costs:
    --
    --   primary  a plain action on a page -- Export, Import, Clone.
    --   confirm  a text field's Accept, and any button that says
    --            `confirm = true` -- Add Container, Add Custom Frame
    --            Group: the action that makes something. Its own pair
    --            because it is the one button a reader is looking FOR
    --            rather than reading past. It ships as the danger pair's
    --            mirror (owner, 2026-09-13): the control's dark fill with a
    --            muted green caption and border, beside danger's red.
    --   danger   `danger = true`: deleting a profile, reverting to
    --            defaults. Anything that cannot be undone by doing it
    --            again.
    --   nav      the chrome's action cells -- Setup Mode, Unlock, Addon
    --            Options. They sit on the rail rather than in a card, so
    --            their fill ships as the rail's rather than the control's.
    --
    -- Every pair but confirm's text ships at the color that button
    -- already wore, so a panel that never touches them looks as it did.
    buttonPrimaryBg   = { 0.063, 0.063, 0.059, 1.00 },   -- controlBg
    buttonPrimaryText = { 0.914, 0.898, 0.855, 1.00 },   -- text
    buttonConfirmBg   = { 0.063, 0.063, 0.059, 1.00 },   -- controlBg
    buttonConfirmText = { 0.42,  0.72,  0.42,  1.00 },   -- muted green, danger's mirror
    buttonDangerBg    = { 0.063, 0.063, 0.059, 1.00 },   -- controlBg
    buttonDangerText  = { 1.00,  0.42,  0.42,  1.00 },   -- danger
    buttonNavBg       = { 0.078, 0.078, 0.071, 1.00 },   -- railBg, opaque
    -- WHITE, at full strength at rest (owner, 2026-09-15): the nav cells,
    -- the top strip's buttons and the rail tree's rows all wore the body
    -- text color dimmed to 80-90%, and together they read as grayed out.
    -- navText is the same white for the strip and the tree, so the three
    -- places a reader navigates from agree.
    buttonNavText     = { 1.00, 1.00, 1.00, 1.00 },
    navText           = { 1.00, 1.00, 1.00, 1.00 },
    -- The nav buttons' BORDER, at rest and hovered: the accent, at the
    -- strength the hover used to have at rest, and brighter under the
    -- mouse. A nav button is a button all the time, not only when touched.
    navBorderAlpha      = 0.45,
    navBorderHoverAlpha = 0.90,
    -- How strongly a button wears its relief -- Media/buttonface.tga, the
    -- bevel, gloss and shadow drawn over every button's fill by
    -- ns.ButtonFace (Controls.lua). 1 is the art as authored; 0 restores
    -- the flat look.
    buttonSheen       = 1,

    -- Groups (the cards on a page). These are SKIN tokens rather than
    -- preset ones, so a card's colors can be changed for the whole panel
    -- in one place -- a preset that wants to differ still says so outright,
    -- which is how the strip stays a shade lighter than the page and the
    -- bare preset stays invisible.
    -- Neutral rather than the mockup's warm browns: the cards sit on a
    -- neutral page (panelBg above), and a warm card on a cold page read as
    -- a color cast rather than as depth.
    groupHeaderBg  = { 0.153, 0.153, 0.137, 1.00 },   -- #272723
    groupBg        = { 0.129, 0.122, 0.118, 1.00 },   -- #211f1e
    groupBorder    = { 0.416, 0.365, 0.337, 1.00 },   -- #6a5d56
    -- GOLD, not off-white. A card's heading is the one piece of text on a
    -- page that is not a setting, and coloring it says so at a glance --
    -- the same gold the tab labels wear, so the two levels of heading in
    -- the panel agree.
    groupHeading   = { 0.980, 0.702, 0.000, 1.00 },   -- #fab300
    groupLabel     = { 0.930, 0.920, 0.900, 1.00 },

    -- Tooltips. The heading is the control's own label, in the accent --
    -- it names WHICH setting is being explained, and the accent is already
    -- the panel's "this one" color -- and the body is white, because a
    -- tooltip is text somebody stopped to read rather than chrome to skim.
    tooltipTitle   = { 0.07, 0.67, 0.91, 1.00 },
    tooltipText    = { 1.00, 1.00, 1.00, 1.00 },

    -- Tabs (a `tabs` navigator's strip). These are FULL colors rather
    -- than derivations: the accent decided all six until they existed,
    -- which meant the one control that could change a tab was the one
    -- that changed everything else as well.
    --
    -- The values are what PaintTab drew from the accent for the `button`
    -- style, to the digit -- except the selected label, which is white:
    -- the accent lightened is the panel's "this one" color everywhere
    -- else, and on a tab it read as a link rather than as the page you
    -- are on.
    --
    -- `tabUseAccent = true` puts the old derivation back, accent and all,
    -- and the six tokens below are then unread. It is a boolean, not a
    -- color, so it is set directly on the skin rather than through
    -- SetSkinColor.
    tabUseAccent   = false,
    -- The card's border, BRIGHTENED: still the same color family every
    -- other tab wears -- a second hue on one of them would say "different
    -- sort of tab" rather than "this one" -- but lifted enough to hold its
    -- own around the selected fill.
    tabSelBorder   = { 0.580, 0.510, 0.470, 1.00 },   -- groupBorder, lifted
    tabSelBg       = { 0.07, 0.67, 0.91, 0.18 },      -- accentDim
    -- Every SELECTED label in the panel: a tab, a rail row, a section
    -- button. White, and the one token to change to move all three.
    tabSelText     = { 1.00, 1.00, 1.00, 1.00 },
    -- The CARD's border, at full strength: a tab is the top edge of the
    -- surface under it, and at the old controlBorder @ 0.55 it was a
    -- lighter, thinner line meeting the card's own. The selected tab keeps
    -- the accent below -- that one is not a border, it is the selection.
    tabBorder      = { 0.416, 0.365, 0.337, 1.00 },   -- groupBorder
    tabBg          = { 0.043, 0.039, 0.035, 0.75 },   -- controlBg @ 0.75
    -- Gold, the same as groupHeading: an unselected tab is a heading for a
    -- page you are not on, and dimmed text made the strip read as disabled
    -- rather than as the other pages waiting.
    tabText        = { 0.980, 0.702, 0.000, 1.00 },   -- #fab300

    -- The color a search term is tinted where it is found. Pale yellow
    -- rather than the accent: the accent already means "selected", and a
    -- match is a different kind of "look here".
    searchHit      = { 1.00, 0.85, 0.26, 1.00 },

    -- interactive
    hoverBg        = { 1.00, 1.00, 1.00, 0.06 },
    pressedBg      = { 0.00, 0.00, 0.00, 0.20 },

    -- metrics
    titlebarHeight = 30,
    statusbarHeight = 22,
    railWidth      = 188,
    railWidthMin   = 140,
    railWidthMax   = 320,
    borderSize     = 1,
    borderRadius   = 8,      -- corner radius; snaps to 0/4/6/8/12
    -- The two border strokes INSIDE the panel, in physical pixels, 1 or 2.
    -- Separate knobs because they are separate decisions: a card is a
    -- surface holding things and a control is a thing, and the weight that
    -- suits one does not follow for the other. See ns.SetBorderStroke.
    controlBorderSize = 1,
    -- 2, not 1: a card is a surface holding things, and at a single pixel
    -- its edge read as a hairline rather than as a boundary.
    cardBorderSize    = 2,

    -- The face every string in the panel is drawn in. Sizes and flags still
    -- come from the templates -- only the face is re-pointed. See
    -- ns.SetPanelFont.
    --
    -- The library SHIPS this face and names it here, because it is part of
    -- what the panel IS rather than a preference of whichever addon happens
    -- to be hosting it. A skin that names a font it does not carry is a
    -- skin that cannot be honored, and the demo proved the cost: depending
    -- on the library alone, it drew in the game font and looked like a
    -- different panel from the one it exists to demonstrate.
    --
    -- Addressed through MEDIA, so it resolves in the source tree and in
    -- every vendored copy with nothing per-copy edited. A host that wants
    -- its own face calls App:SetPanelFont; one that wants the game's calls
    -- it with nil.
    font = MEDIA .. "PTSansNarrow.ttf",

    -- A button's caption is drawn at the group HEADER's size rather than a
    -- label's: a button is a thing you press, not a row you read, and at the
    -- label size it read as a caption that happened to have a border.
    buttonFontSize = 12,
    borderInset    = 0,      -- push the border in from the frame edge
    showBorder     = true,   -- an addon can turn the outer border off entirely
    padding        = 10,

    -- size limits, used for the resize grip
    minWidth       = 620,
    minHeight      = 420,
    maxWidth       = 2400,
    maxHeight      = 1600,
}

-- Shallow copy: skins are one level deep by design, so this is the whole
-- of "instantiate a skin for an app".
function ns.CopySkin(base, overrides)
    local out = {}
    for k, v in pairs(base) do
        if type(v) == "table" then
            local t = {}
            for i = 1, #v do t[i] = v[i] end
            out[k] = t
        else
            out[k] = v
        end
    end
    if overrides then
        for k, v in pairs(overrides) do out[k] = v end
    end
    return out
end

-- ── Border stroke groups ───────────────────────────────────────
--
-- Two surfaces wear a border in this panel and they are not the same
-- decision: the CONTROLS (every dropdown, switch, box, swatch, chip, tab
-- and track) and the CARDS (a group's box, its header art, the pop-up
-- menu, the suggestion list). Each has its own width, in physical pixels,
-- and 1 or 2 are the only widths worth having -- 3 stops reading as a
-- hairline and starts reading as a frame.
--
-- The width is library-wide rather than per app because it is the same
-- decision for every panel on screen, and because a shape is created long
-- before anything hands it a skin.
local strokes       = { control = 1, card = 1 }
local strokeSetters = { control = {}, card = {} }

function ns.BorderStroke(group) return strokes[group] or 1 end

-- Live: every shape built through ns.StrokedFill re-insets itself, so the
-- width changes under an open panel without a re-render. The shapes are
-- pooled and long-lived, so the list of setters is bounded by the number of
-- widgets the panel has ever built rather than growing with every render.
function ns.SetBorderStroke(group, px)
    px = (tonumber(px) == 2) and 2 or 1
    if not strokes[group] or strokes[group] == px then return end
    strokes[group] = px
    for _, setInset in ipairs(strokeSetters[group]) do setInset(px) end
end

-- ns.RoundedFill with its inset taken from -- and kept in step with -- one
-- of those groups. The OUTER shape of a border is always at inset 0; this
-- is for the inner one, whose inset IS the stroke.
function ns.StrokedFill(frame, layer, radius, sides, color, group)
    local paint, setRadius, setInset, setSides, setInsetBottom, setGradient, setFace =
        ns.RoundedFill(frame, layer, radius, sides, color, ns.BorderStroke(group))
    local list = strokeSetters[group]
    if list then list[#list + 1] = setInset end
    -- EVERYTHING RoundedFill returns passes through: `setInsetBottom` for
    -- a caller that has to OPEN the bottom edge of a stroked shape (a
    -- selected square-bottomed tab), and `setGradient` / `setFace` for a
    -- button's relief (ns.ButtonFace). Dropping one here cost an in-game
    -- "attempt to call a nil value" the first time the footer was drawn.
    return paint, setRadius, setInset, setSides, setInsetBottom, setGradient, setFace
end

-- A rounded shape wearing the small part of a TEXTURE's interface that the
-- panel's widgets ask of one.
--
-- ns.RoundedFill is five textures and paints a COLOR; a widget expects one
-- texture it can tint, show and hide. Rather than teach forty call sites the
-- difference, the shape is handed back looking like what they already hold.
-- Hiding is painting fully transparent, because the pieces are shown and
-- hidden by the shape's own geometry (a squared corner draws nothing) and
-- taking that over here would fight it.
-- One repaint is seven SetColorTexture calls rather than one, and a
-- control's refresh runs on every write -- so a repaint that would change
-- nothing is skipped. Every field on a page refreshes when any of them is
-- written, and nearly all of them are painting the color they already
-- wear.
function ns.ShapeTexture(paint, setSides)
    local o = { bpColor = { 0, 0, 0, 0 }, bpShown = true }
    local lr, lg, lb, la
    local function repaint()
        local c = o.bpColor
        local a = o.bpShown and (c[4] or 1) or 0
        if c[1] == lr and c[2] == lg and c[3] == lb and a == la then return end
        lr, lg, lb, la = c[1], c[2], c[3], a
        paint({ c[1], c[2], c[3], a })
    end
    function o:SetVertexColor(r, g, b, a)
        self.bpColor = { r or 1, g or 1, b or 1, a or 1 }
        repaint()
    end
    o.SetColorTexture = o.SetVertexColor
    function o:Show()      self.bpShown = true;                 repaint() end
    function o:Hide()      self.bpShown = false;                repaint() end
    function o:SetShown(v) self.bpShown = v and true or false;  repaint() end
    function o:IsShown()   return self.bpShown end
    function o:SetSides(s) if setSides then setSides(s) end end
    return o
end

-- ── The panel's font ───────────────────────────────────────────
--
-- Every string in the panel is born from a Blizzard font OBJECT --
-- GameFontNormalSmall and its relatives -- which carries a face, a size and
-- flags together. That is the right way to inherit sizes and colors, and
-- the wrong way to state a face: the object's face is the game font, and
-- there is no object for "the game's size at somebody else's face".
--
-- So a string keeps the object's size and flags and has its FACE
-- re-pointed, here, in one place. The library remembers every string it
-- makes, which is what lets the face change under an open panel.
--
-- Two faces matter per string: the one in force now, and the one it was
-- BORN with. Clearing the override has to put back the font the template
-- actually gave it -- not "GameFontNormalSmall's face", which this file has
-- no way to look up once it has been overwritten.
local fontStrings = {}
local panelFace                 -- nil = whatever each template gave it

local function RememberFace(fs)
    if fs.bpBornFace then return end
    local face = fs:GetFont()
    fs.bpBornFace = face
end

-- A failed SetFont leaves a string with NO font -- invisible text, not a
-- fallback -- so the result is checked and the born face put back if the
-- file is not there. pcall as well: a malformed path throws rather than
-- returning false.
local function ApplyFace(fs)
    if not fs then return end
    RememberFace(fs)
    local face, size, flags = fs:GetFont()
    local want = panelFace or fs.bpBornFace
    if not (want and size) or want == face then return end
    local ok, set = pcall(fs.SetFont, fs, want, size, flags)
    if not (ok and set ~= false) and fs.bpBornFace then
        pcall(fs.SetFont, fs, fs.bpBornFace, size, flags)
    end
end

local function TrackFont(fs)
    if fs.bpFontTracked then return fs end
    fs.bpFontTracked = true
    fontStrings[#fontStrings + 1] = fs
    return fs
end

-- Every FontString the library makes goes through here instead of
-- CreateFontString, which is the whole of "the panel knows its own text".
function ns.FS(parent, layer, template)
    local fs = parent:CreateFontString(nil, layer, template)
    TrackFont(fs)
    ApplyFace(fs)
    return fs
end

-- A font OBJECT assigned after birth replaces face, size and flags at once,
-- so the panel's face has to be re-stated after it -- and the string's
-- remembered birth face is now that object's. Works on an EditBox too,
-- which is why the text controls use it.
-- A NAME is resolved to the object before it is assigned. Callers name a
-- font as often as they hand one over -- "GameFontNormalSmall" reads better
-- at the call site than the global does -- and the two must not behave
-- differently: this call is the one thing that puts a string's size back to
-- the font's own, and a note that keeps the previous occupant's size is a
-- pooled widget wearing someone else's face.
-- The face, size and flags are read from the OBJECT, never back off the
-- string: assigning an object the string already wears is a no-op in the
-- client, so the string keeps whatever was last SetFont on it -- the panel
-- face, on any string this file has touched -- and remembering that as its
-- birth face pins it to the panel face for good. That is how the nav rows,
-- pooled and re-pointed at the same object on every render, stayed in the
-- panel face after the switch to the game font.
function ns.SetFontObject(fs, obj)
    if not fs then return fs end
    local want = obj
    if type(want) == "string" then want = _G[want] or obj end
    fs:SetFontObject(want)
    local oFace, oSize, oFlags
    if type(want) == "table" and want.GetFont then
        oFace, oSize, oFlags = want:GetFont()
    end
    fs.bpBornFace = oFace or nil
    if oFace and oSize then
        local face, size, flags = fs:GetFont()
        if face ~= oFace or size ~= oSize or (flags or "") ~= (oFlags or "") then
            pcall(fs.SetFont, fs, oFace, oSize, oFlags or "")
        end
    end
    TrackFont(fs)
    ApplyFace(fs)
    return fs
end

-- The size a font OBJECT draws at, for a caller that needs to state a size
-- explicitly and wants the object's own as the default. Names resolve the
-- same way ns.SetFontObject resolves them.
function ns.FontObjectSize(obj)
    if type(obj) == "string" then obj = _G[obj] end
    if not (obj and obj.GetFont) then return nil end
    local _, size = obj:GetFont()
    return size
end

-- The face, size and flags a string should wear with nothing previewing
-- over it. The font and texture pickers draw their rows in the face being
-- offered and put this back afterwards; caching it at birth would restore
-- the face the panel wore then rather than the one it wears now.
function ns.BaseFont(fs)
    local face, size, flags = fs:GetFont()
    RememberFace(fs)
    return (panelFace or fs.bpBornFace or face), size, flags
end

-- The face the panel currently wears, for anything that keys a cached
-- layout on it: a font has a width, so a signature that skips a re-render
-- must change when the face does. nil is the game font.
function ns.PanelFace()
    return panelFace
end

-- Point the whole panel at a font file, or at nothing for the game font.
-- Live: every string the library has ever made is re-pointed where it
-- stands. An OPEN panel is then rendered again, because a face has a
-- width: the strip and footer buttons are sized to their captions at
-- render, and wrapped notes to their line count, so re-pointing alone
-- left a wider face poking out of last render's buttons.
-- The first SetFont on a font file the client has not loaded yet fails and
-- the string draws blank; that failed call is what starts the load, and the
-- file then stays loaded until the client exits -- so it shows up only on a
-- fresh login, never after a reload. A throwaway string takes that first
-- call here, when the face is named (NewApp, at the host's load), so the
-- file is in before any real string is drawn in it. Without this the rail's
-- first row came up blank and the close button's X, which is enlarged once
-- off its own GetFont at birth, stayed small for the session.
local fontPrimer
local primedFaces = {}
local function PrimeFace(path)
    if not path or primedFaces[path] then return end
    primedFaces[path] = true
    if not fontPrimer then
        fontPrimer = UIParent:CreateFontString(nil, "BACKGROUND")
        fontPrimer:Hide()
    end
    pcall(fontPrimer.SetFont, fontPrimer, path, 12, "")
end

function ns.SetPanelFont(app, path)
    if app then app.skin.font = path end
    if path == panelFace then return end
    PrimeFace(path)
    panelFace = path
    for i = 1, #fontStrings do ApplyFace(fontStrings[i]) end
    if app and app.frame and app.frame:IsShown() then
        if ns.nav and ns.nav.Refresh then ns.nav.Refresh(app) end
        if ns.chrome then
            if ns.chrome.RenderFooter    then ns.chrome.RenderFooter(app)    end
            if ns.chrome.RenderStatusBar then ns.chrome.RenderStatusBar(app) end
        end
        if ns.page and ns.page.RefreshPage then ns.page.RefreshPage(app) end
    end
end
