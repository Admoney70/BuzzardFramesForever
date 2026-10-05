-- ============================================================
-- BuzzardPanel-1.0
-- A standalone options-panel framework.
--
-- ADDON-NEUTRAL BY CONSTRUCTION. Nothing in this library knows about,
-- names, or reaches for any particular addon. Everything an app needs
-- to be itself -- title, icon, accent, where to persist geometry -- is
-- passed to NewApp.
--
-- ISOLATION IS THE CENTRAL RULE. All mutable state belongs to the APP
-- instance, never to the library:
--
--     app.pools      its widget pools
--     app.frame      its frame and regions
--     app.skin       its own copy of the resolved skin
--     app.controls   its registered control types
--
-- The library scope holds only pure functions and read-only data. Two
-- addons using one copy of this library therefore cannot reach each
-- other's widgets: neither holds a reference by which to try. This is
-- the failure class that makes a shared global widget pool leak state
-- between addons, and it is designed out rather than guarded against.
--
-- This file loads LAST (see the .toc) and is the ONLY file that talks
-- to LibStub. Skin.lua and Frame.lua write into the addon-private `ns`
-- table; nothing else performs a registration.
--
-- P0.1 scope: the app object, per-app pools, and a frame with named
-- regions that opens, moves, resizes and persists its geometry. Routes,
-- navigators, chrome and controls arrive in P0.2 and P0.3.
-- ============================================================
local ADDON, ns = ...

-- MINOR decides WHICH COPY WINS when more than one addon embeds this
-- library: LibStub keeps the highest and discards the rest. It sat at 2
-- through a long run of changes, so every vendored copy claimed the same
-- version and the winner was settled by addon load order instead -- which
-- let an addon that had not been re-vendored hand its older library to one
-- that had. Bump this whenever the library changes.
--
-- MINOR ENCODES THE RELEASE VERSION: major * 100 + minor, so 100 is the
-- 1.0 release, 101 would be 1.0.1, 110 would be 1.1. It must only ever go
-- UP (the pre-release run counted 2..45, all below 100), or an installed
-- older copy would beat a newer one. Keep it in step with the Version
-- line in BuzzardPanel.toc.
local MAJOR, MINOR = "BuzzardPanel-1.0", 101

assert(LibStub, MAJOR .. " requires LibStub")
local Panel, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not Panel then return end   -- a newer copy is already loaded

-- Carried across an in-place upgrade so live apps survive a newer copy
-- loading after us.
Panel.apps         = Panel.apps         or {}
Panel.skins        = Panel.skins        or {}
Panel.groupPresets = Panel.groupPresets or {}

-- Library-scope skins are immutable reference data. An app never edits
-- one; it copies it (see NewApp) and edits the copy. On an in-place
-- upgrade the NEWER copy's definitions replace the older ones: a skin or
-- preset token added in this version would otherwise never reach a client
-- that loaded an older copy first. Apps already created keep their copies.
for name, tokens in pairs(ns.skins) do
    Panel.skins[name] = tokens
end
for name, tokens in pairs(ns.groupPresets) do
    Panel.groupPresets[name] = tokens
end

-- Group presets: container styling and layout, defined once and used as a
-- group type. `extends` composes; anything omitted falls back to default.
function Panel:DefineGroup(name, tokens)
    assert(type(name) == "string", "DefineGroup: name must be a string")
    assert(type(tokens) == "table", "DefineGroup: tokens must be a table")
    local base = self.groupPresets[tokens.extends or "default"] or self.groupPresets.default
    self.groupPresets[name] = ns.CopySkin(base, tokens)
end

-- ============================================================
-- House presets and defaults
-- ============================================================
--
-- The arrangement the panel was settled on after living with every knob:
-- these are the library's DEFAULTS, so a new consumer opens on the same
-- look as every other Buzzard panel without declaring anything. Each is a
-- plain setter a consumer may still overrule after NewApp.

-- A group with no card and no header: the container disappears and its
-- fields sit straight on the page. For a standalone control that is
-- meta-configuration rather than a setting.
do
    Panel:DefineGroup("bare", {
        headerBg  = { 0, 0, 0, 0 },
        bodyBg    = { 0, 0, 0, 0 },
        border    = { 0, 0, 0, 0 },
        padding   = 0,
        -- padBottom too: a group with no card should end exactly at its
        -- content rather than inherit the default preset's bottom pad.
        padBottom = 0,
        justify   = "start",
    })
end
-- The form card: every field keeps its natural width and the remainder of
-- the row is left empty, and a line breaks as soon as a field will not fit
-- at its preferred width -- so a dropdown is the same width on every row.
do
    Panel:DefineGroup("form", { justify = "start", wrapOn = "pref" })
end

-- The default chrome: a full-height rail carrying the icon and title, the
-- sections as a rounded button strip along the top beside it, and the
-- selected section's pages as a tree in the rail (with the section's own
-- page as a first row when it has one).
function Panel:DefaultChrome()
    return {
        railSpan = "full",
        top  = { { navigator = "buttonbar", level = 1, style = "rounded" } },
        left = { { navigator = "tree",      level = 2, withParent = true } },
    }
end

local HOUSE_DEFAULTS = {
    tabStyle             = "tab",     -- subtab strips: square-bottomed tabs
    railChildren         = false,     -- the strip owns the subtabs; the rail does not repeat them
    sliderValuePlacement = "below",   -- value box under the track
    iconStyle            = 2,         -- converging-arrows centering glyphs
    breadcrumbShown      = false,
    menuStyle            = { grow = "down", align = "start" },
    search               = { placement = "rail", placeholder = "Search settings" },
}
Panel.HOUSE_DEFAULTS = HOUSE_DEFAULTS

-- ============================================================
-- Skins
-- ============================================================

-- Register a named skin. `tokens` is a flat table; see Skin.lua for the
-- full token list. Anything omitted falls back to the default skin.
-- Re-point a sliced texture at a different corner radius, snapping to one
-- of the authored sizes. Exposed because a consuming addon may want to
-- restyle at runtime.
function Panel:SetTextureRadius(tex, radius)
    return ns.SetTexRadius(tex, radius)
end

-- Diagnostic: print a segmented control's real geometry, including its
-- pooled hidden buttons. Used by the demo's /bpd segdiag.
function Panel:DumpSegmented(widget)
    return ns.DumpSegmented(widget)
end

function Panel:RegisterSkin(name, tokens)
    assert(type(name) == "string", "RegisterSkin: name must be a string")
    assert(type(tokens) == "table", "RegisterSkin: tokens must be a table")
    self.skins[name] = tokens
end

-- ============================================================
-- The app object
-- ============================================================

local App = {}
App.__index = App

-- Panel:NewApp(id, opts)
--   id    unique string, also the frame-name suffix
--   opts  title       display name in the title bar        (default: id)
--         icon        texture path for the title bar       (optional)
--         skin        registered skin name                 (default: "default")
--         tokens      per-app token overrides, e.g. accent (optional)
--         persist     function returning a table the app may store
--                     geometry in. The library owns no SavedVariables;
--                     this is how an addon lends it a home.
--         onOpen / onClose  callbacks. onClose fires from the frame's
--                     OnHide, so escape and any external :Hide() reach it
--                     as well as the title-bar X.
--         onResize    function(app, w, h), called while the frame is being
--                     resized. Fires on every step of a drag; debounce
--                     anything expensive through app:ScheduleEffect.
--         onWrite     function(app, node, ctx), called after any field on
--                     the panel commits a value -- panel-level work that
--                     no single field owns. Fires on every step of a
--                     slider drag; debounce it the same way.
function Panel:NewApp(id, opts)
    assert(type(id) == "string" and id ~= "", "NewApp: id must be a non-empty string")
    if self.apps[id] then return self.apps[id] end
    opts = opts or {}

    local app = setmetatable({}, App)
    app.id      = id
    app.title   = opts.title or id
    app.icon    = opts.icon
    -- Shown in the rail's head, which only a full-height-rail layout draws.
    -- A function is resolved at first paint, so a consumer can hand over its
    -- .toc lookup rather than the string.
    app.version = opts.version
    app.persist = opts.persist
    app.onOpen  = opts.onOpen
    app.onClose = opts.onClose
    app.onResize = opts.onResize
    -- function(app, node, ctx), called after ANY field on the panel commits
    -- a value. See ns.Commit.
    app.onWrite  = opts.onWrite

    -- Its own resolved skin. Copying rather than referencing is what
    -- stops one app's token override reaching another app.
    local base = self.skins[opts.skin or "default"] or self.skins.default
    app.skin = ns.CopySkin(base, opts.tokens)
    -- The two inner border widths are library-wide rather than per app --
    -- see ns.SetBorderStroke -- so a skin that states them states them for
    -- everything drawn from here on, and a shape built later picks up the
    -- value in force without being told.
    ns.SetBorderStroke("control", app.skin.controlBorderSize)
    ns.SetBorderStroke("card",    app.skin.cardBorderSize)
    -- Same for the face: absent, every string keeps the game font its
    -- template carries.
    ns.SetPanelFont(app, app.skin.font)

    -- Per-app state. None of this is reachable from the library scope.
    app.pools    = {}      -- kind -> array of released objects
    app.controls = {}      -- control name -> definition, this app only
    -- Initialized here rather than on first use. An app that never declares
    -- routes, chrome or a footer is a legitimate configuration, and Open()
    -- renders all three unconditionally -- so they must exist from birth
    -- rather than depend on the consumer calling things in a set order.
    app.routes      = {}
    app.routeIndex  = {}
    app.route       = {}
    app.navs        = {}
    app.navCache    = {}   -- kind:region -> reusable navigator instance
    app.footerSlots = {}
    app.footerCells = {}
    app.routeObservers = {}
    -- Born with the route observers, and for the same reason: a consumer
    -- may register one before it has declared a single route.
    app.sectionObservers = {}
    app.liveFields  = {}
    app.liveGroups  = {}
    app.bindIndex   = {}

    -- Group presets are copied per app for the same reason skins are: an
    -- app must not be able to edit another app's layout tokens.
    app.groupPresets = {}
    for name, tokens in pairs(self.groupPresets) do
        app.groupPresets[name] = ns.CopySkin(tokens)
    end
    app.railWidth       = app.skin.railWidth
    app.footerHeight    = 0
    app.pageheaderHeight = 0
    app.statusbarShown  = false

    -- House defaults (see above). Applied before the frame exists, so each
    -- is a plain assignment or a setter that only stores until Open.
    app.tabStyle             = HOUSE_DEFAULTS.tabStyle
    app.railChildren         = HOUSE_DEFAULTS.railChildren
    app.sliderValuePlacement = HOUSE_DEFAULTS.sliderValuePlacement
    app.iconStyle            = HOUSE_DEFAULTS.iconStyle
    app.breadcrumbShown      = HOUSE_DEFAULTS.breadcrumbShown
    app.menuStyle            = ns.CopySkin(HOUSE_DEFAULTS.menuStyle)
    ns.nav.SetChrome(app, self:DefaultChrome())
    ns.search.SetSearch(app, ns.CopySkin(HOUSE_DEFAULTS.search))

    self.apps[id] = app
    return app
end

-- Combat watcher.
--
-- `disabled = "combat"` reads InCombatLockdown() when a field is painted, so
-- it is correct at render time and then never revisited: entering combat with
-- the panel already open left every combat-gated control looking enabled. The
-- consuming addon cannot be relied on to poke us -- the library declares the
-- predicate, so the library watches for it.
--
-- One frame for the library, not one per app: the event is global and the
-- work is a refresh of whichever panels happen to be open.
local combatWatcher
local function EnsureCombatWatcher(self)
    if combatWatcher then return end
    combatWatcher = CreateFrame("Frame")
    combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcher:SetScript("OnEvent", function(_, event)
        for _, app in pairs(self.apps) do
            -- Effects blocked by combat are flushed for EVERY app, open or
            -- not: the pending work belongs to the consuming addon, not to
            -- the panel, and a closed panel does not make it optional.
            if event == "PLAYER_REGEN_ENABLED" then
                ns.effects.OnCombatEnd(app)
            end
            if app.frame and app.frame:IsShown() then
                -- No key: this refreshes the fields with dynamic predicates,
                -- which is exactly the set that can care about combat.
                ns.page.RefreshBinding(app, nil)
                -- ...and the page's SHAPE, for the one caller that has no
                -- ctx to name a host with. `disabled = "combat"` is handled
                -- by the refresh above, but a `hidden` predicate is free to
                -- read InCombatLockdown itself, and leaving combat is the
                -- only moment nothing wrote and the answer changed anyway.
                -- A nil scope schedules every host that asks a question.
                ns.page.ScheduleRender(app, nil)
                ns.chrome.RenderFooter(app)
            end
        end
    end)
end

function Panel:GetApp(id)
    return self.apps[id]
end

-- ============================================================
-- Lifecycle
-- ============================================================

function App:EnsureFrame()
    if not self.frame then ns.BuildFrame(self) end
    return self.frame
end

function App:Open()
    local f = self:EnsureFrame()
    EnsureCombatWatcher(Panel)
    -- Render on open rather than on declaration: routes and chrome can be
    -- declared before the frame exists, which keeps app setup free of any
    -- ordering requirement.
    ns.nav.Refresh(self)
    ns.chrome.RenderFooter(self)
    f:Show()
    f:Raise()
    -- Unconditionally, and before onOpen: observers otherwise fire only on
    -- a Navigate, so the page a session opens on -- restored, deep-linked,
    -- or simply the first one -- would arrive unstamped, and onOpen is
    -- entitled to read app:GetSectionKey() and find it already right.
    ns.nav.FireSectionChange(self, true)
    -- Then the route observers, for the same reason: the coarse stamp
    -- first, then the page's finer one on top of it, then onOpen, which
    -- is entitled to find both already right.
    ns.nav.FireArrival(self)
    if self.onOpen then self.onOpen(self) end
    return f
end

-- Closing is HIDING, and nothing else.
--
-- The geometry save and onClose live on the frame's OnHide (see
-- ns.BuildFrame), so escape -- which UISpecialFrames performs as a bare
-- f:Hide() the library never sees -- and any external :Hide() behave
-- exactly like the title-bar X. Hide() on an already-hidden frame fires no
-- OnHide, so there is no second call to guard against here.
function App:Close()
    if not self.frame then return end
    self.frame:Hide()
end

function App:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

function App:IsShown()
    return (self.frame and self.frame:IsShown()) and true or false
end

-- ============================================================
-- Regions
-- ============================================================

-- Regions are addressed BY NAME. No caller outside the library ever
-- receives a raw frame it did not create, which is what keeps one app
-- from reaching into another's.
local VALID_REGIONS = {
    titlebar = true, top = true, rail = true, footer = true,
    pane = true, pageheader = true, body = true, statusbar = true,
}

function App:GetRegion(name)
    assert(VALID_REGIONS[name], "GetRegion: unknown region '" .. tostring(name) .. "'")
    self:EnsureFrame()
    return self.regions[name]
end

-- Region sizes an app may set. Each triggers a re-layout; none of them
-- can push a region past the frame, because LayoutRegions clamps.
function App:SetRailWidth(px)
    self.railWidth = px
    if self.frame then ns.LayoutRegions(self) end
end

function App:SetFooterHeight(px)
    self.footerHeight = px or 0
    if self.frame then ns.LayoutRegions(self) end
end

-- EXTRA room in the page header, on top of what its contents ask for.
--
-- Not the header's height. The header's height is a sum owned by
-- ns.chrome.PageHeaderHeight, because more than one thing lives up there
-- and the version where each wrote the total directly ended with whichever
-- ran last winning -- and the breadcrumb losing. Setting a term is safe;
-- setting the total is not, so this API no longer offers to.
function App:SetPageHeaderExtra(px)
    self.pageHeaderExtra = px or 0
    if self.frame then ns.nav.Refresh(self) end
end

-- Hide the breadcrumb, and give its band back.
function App:SetBreadcrumbShown(shown)
    self.breadcrumbShown = shown and true or false
    if self.breadcrumb then self.breadcrumb:SetShown(self.breadcrumbShown) end
    if self.frame then ns.nav.Refresh(self) end
end

-- Which drawing of an icon that has more than one. See ns.IconVariant: the
-- pages name icons semantically, so this moves all of them at once.
function App:SetIconStyle(n)
    n = tonumber(n) or 1
    if self.iconStyle == n then return end
    self.iconStyle = n
    if not self.frame then return end
    -- The art is chosen in apply, so this is a REBUILD rather than a refresh
    -- -- a refresh only repaints the widgets it already has.
    --
    -- And on the NEXT frame, because the caller is typically the handler of
    -- the very control that picked the style, and the rebuild releases it.
    -- Same reason the Testing page defers its preset changes.
    if C_Timer then
        local app = self
        C_Timer.After(0, function() app:Invalidate() end)
    else
        self:Invalidate()
    end
end

-- Record an undo point for a setting the panel is about to change through
-- some other path -- a page's own writer, an addon action that bypasses the
-- controls. See ns.RecordUndo: without one, the right-click menu has nothing
-- to offer and so does not open.
function App:RecordUndo(node, ctx)
    return ns.RecordUndo(node, ctx or { app = self })
end

function App:SetStatusBarShown(shown)
    self.statusbarShown = shown and true or false
    if self.frame then ns.LayoutRegions(self) end
end

-- Where tooltips anchor. Any GameTooltip anchor name.
function App:SetTooltipAnchor(anchor) self.tooltipAnchor = anchor end

--- Every setting in this app refuses in combat.
---
--- The alternative is `disabled = "combat"` on each field, which is a rule
--- kept by hand and so a rule with holes -- and the holes are invisible
--- until a reader clicks one mid-fight and nothing happens. With this on,
--- every control and every card gate grays while the player is in combat;
--- a node that genuinely works in combat says `combat = false`, the same
--- word a collection's add and remove already use for the same escape.
---
--- The library's own combat watcher re-renders open panels on
--- PLAYER_REGEN_DISABLED / _ENABLED, so nothing else has to poke it.
function App:SetCombatDisablesAll(on)
    self.combatDisablesAll = on and true or false
end

-- Show or hide the panel's outer border at runtime.
function App:SetBorderShown(shown) return ns.SetBorderShown(self, shown) end

-- Change the panel's corner radius: border, background and every region
-- that reaches a corner, together. Snaps to an authored radius.
function App:SetBorderRadius(radius) return ns.SetBorderRadius(self, radius) end

-- The stroke on every CONTROL border -- dropdowns, switches, boxes,
-- swatches, chips, tabs, tracks -- in physical pixels. 1 or 2; anything
-- else is clamped to one of them. Live: the panel re-strokes itself, no
-- re-render needed.
function App:SetControlBorderSize(px)
    self.skin.controlBorderSize = (tonumber(px) == 2) and 2 or 1
    ns.SetBorderStroke("control", self.skin.controlBorderSize)
end

-- The same for the CARD borders: a group's box, its header art, the tab
-- shape, the pop-up menu and the suggestion list.
function App:SetCardBorderSize(px)
    self.skin.cardBorderSize = (tonumber(px) == 2) and 2 or 1
    ns.SetBorderStroke("card", self.skin.cardBorderSize)
end

-- Draw every string in the panel in this font FILE, or in the game font
-- when passed nothing. Sizes and flags still come from the templates; only
-- the face changes. Live, and it reaches strings built later too.
function App:SetPanelFont(path) return ns.SetPanelFont(self, path) end

-- How many physical pixels one panel unit is drawn as: a number (whole
-- numbers keep every edge on the pixel grid; fractional ones draw a hair
-- softer, never broken -- see Frame.lua, CurrentPixelMultiple), or nil for
-- automatic (the whole multiple nearest the client's own UI scale). Live:
-- an open panel re-stamps and re-lays out in place. Cleared by
-- SetPanelScale, which is the relative way to say the same thing.
function App:SetPixelMultiple(n)
    self.pixelMultiple = (type(n) == "number" and n > 0)
        and math.min(8, math.max(0.5, n)) or nil
    self.panelScaleRel = nil
    if ns.RestampPanel then ns.RestampPanel(self) end
end
function App:GetPixelMultiple()
    return ns.CurrentPixelMultiple and ns.CurrentPixelMultiple(self) or 1
end

-- The panel's scale RELATIVE to the client's own UI scale: 1 draws the
-- panel at exactly UIParent's effective scale -- the size everything else
-- on screen is drawn at -- 1.2 a fifth larger, and so on. This is the
-- setting a reader reasons about; SetPixelMultiple is the absolute form.
-- nil clears it (back to the automatic whole-pixel multiple). Live.
function App:SetPanelScale(s)
    self.panelScaleRel = (type(s) == "number" and s > 0)
        and math.min(3, math.max(0.3, s)) or nil
    self.pixelMultiple = nil
    if ns.RestampPanel then ns.RestampPanel(self) end
end
function App:GetPanelScale()
    return self.panelScaleRel
end

-- DIAGNOSTIC: which visible frames in the panel have an edge off the
-- physical pixel grid. Prints a count and the worst offenders with a
-- description (name, or the chain of parents with sizes), so a border
-- that draws soft or missing can be traced to the frame that put it on a
-- half pixel. /run LibStub("BuzzardPanel-1.0"):GetApp("BuzzardFrames"):PixelAudit()
function App:PixelAudit(limit)
    local f = self.frame
    if not f then print("BuzzardPanel: no frame") return end
    if not GetPhysicalScreenSize then print("BuzzardPanel: no GetPhysicalScreenSize") return end
    local _, ph = GetPhysicalScreenSize()
    local px = 768 / ph
    local total, bad, out = 0, 0, {}
    local function describe(r)
        local parts, p, n = {}, r, 0
        while p and n < 4 do
            local name = p.GetName and p:GetName()
            local w, h = p:GetWidth(), p:GetHeight()
            parts[#parts + 1] = (name or (p.bpKind or p.bpControl or p:GetObjectType()))
                .. string.format("[%.0fx%.0f]", w or 0, h or 0)
            p = p:GetParent(); n = n + 1
        end
        return table.concat(parts, " < ")
    end
    local function frac(v) return math.abs(v - math.floor(v + 0.5)) end
    local function visit(r, depth)
        if depth > 40 or not r:IsShown() then return end
        local eff = r:GetEffectiveScale() or 1
        local l, b, w, h = r:GetLeft(), r:GetBottom(), r:GetWidth(), r:GetHeight()
        if l and b and w and h and w > 0 and h > 0 then
            total = total + 1
            local k = eff / px
            local L, B, R, T = l * k, b * k, (l + w) * k, (b + h) * k
            local worst = math.max(frac(L), frac(B), frac(R), frac(T))
            if worst > 0.02 then
                bad = bad + 1
                out[#out + 1] = { worst, string.format(
                    "L%.2f B%.2f R%.2f T%.2f  %s", L, B, R, T, describe(r)) }
            end
        end
        if r.GetChildren then
            for _, c in ipairs({ r:GetChildren() }) do visit(c, depth + 1) end
        end
    end
    visit(f, 0)
    table.sort(out, function(x, y) return x[1] > y[1] end)
    print(string.format("BuzzardPanel pixel audit: %d visible frames, %d off-grid; scale %.4f (%.2f px/unit)",
        total, bad, f:GetEffectiveScale() or 0, (f:GetEffectiveScale() or 0) / px))
    for i = 1, math.min(limit or 15, #out) do print("  " .. out[i][2]) end
end

-- Recolor the panel's outer border.
function App:SetBorderColor(c)
    self.skin.panelBorder = c
    if self.border then self.border:SetColor(c) end
end

function App:GetSkin()
    return self.skin
end

-- Change one skin color on a live panel: the token, every surface painted
-- from it, and the render that follows. `App:SetBorderColor` is this for
-- the one token that predates it and is kept for callers that use it.
function App:SetSkinColor(token, c) return ns.SetSkinColor(self, token, c) end

-- ── Menus ───────────────────────────────────────────────────────
--
-- The panel's own menu, the same one a dropdown control and the dropdown
-- navigator open. `items` is a list of
--     { text, desc, selected, onPick }   -- desc may be a function
--     { kind = "separator" }
-- and `opts` styles it:
--
--   grow          "up" | "down" | "left" | "right" | "auto" (default)
--                 -- the direction it opens FROM the anchor. "auto" drops
--                 down unless there is no room below.
--   align         "start" | "center" | "end" -- how it lines up on the
--                 anchor's other axis.
--   offset        gap from the anchor, in pixels.
--   width         fixed width; otherwise the widest label wins, bounded by
--   minWidth      (default: the anchor's width) and
--   maxWidth      (labels truncate rather than run off the screen).
--   rowHeight, padding, sepHeight, borderSize, radius
--   border, bg, text, textSelected, highlight, check, divider  -- colors,
--                 each defaulting to the matching skin token.
--   title         a heading row, with titleColor, titleBg, titleHeight,
--                 titleJustify and titleRule (the line under it).
--
-- Every value may be a FUNCTION, read when the menu opens, so a menu can
-- take its width or its heading from state that changes.
--
-- Opening a menu whose anchor already has one open CLOSES it, which is what
-- makes any anchor a toggle without the caller tracking anything.
function App:ShowMenu(anchor, items, opts)
    return ns.ShowMenu(anchor, self, items, opts)
end

function App:CloseMenu() return ns.CloseDropdown() end

-- Defaults for every menu this app opens, in the same shape as the `opts`
-- above. A per-call `opts` overrides it key by key, so a panel styles its
-- menus once here rather than at each call site.
function App:SetMenuStyle(style) self.menuStyle = style end

-- ============================================================
-- Routes, navigation and chrome
-- ============================================================
-- Thin forwarding to Nav.lua / Chrome.lua. Kept as one-liners on purpose:
-- the app object is the whole public surface, and the split across files
-- is an implementation detail nobody outside the library should feel.

function App:SetRoutes(nodes)          return ns.nav.SetRoutes(self, nodes) end
function App:SetChrome(spec)           return ns.nav.SetChrome(self, spec) end
function App:Navigate(...)             return ns.nav.Navigate(self, ...) end
function App:GetRoute()                return ns.nav.GetRoute(self) end
function App:IsRouteActive(pattern)    return ns.nav.IsRouteActive(self, pattern) end
function App:RefreshNav()              return ns.nav.Refresh(self) end

-- How a contextual tab strip looks, for every node that does not say for
-- itself: "button" (rounded pills, the library's own default) or "tab"
-- (square-bottomed, sitting on a rule across the page, the classic
-- arrangement). A node's own `tabStyle` still wins -- this is the ADDON's
-- default, not an override.
function App:SetTabStyle(style)
    self.tabStyle = (style == "tab") and "tab" or "button"
    if self.frame then ns.nav.Refresh(self) end
end

-- Where a slider's value box sits: "side" (in a gap at the right of the
-- track) or "below" (centered under it, level with the min/max labels --
-- the classic arrangement).
--
-- The panel's DEFAULT. A field overrules it with `valuePlacement`, which
-- is the same three-tier shape SetRailChildren has: field, then app, then
-- the library's own answer.
--
-- Re-renders rather than re-navigating: the two layouts are different
-- HEIGHTS, so the page has to be measured again, not just repainted.
function App:SetSliderValuePlacement(placement)
    self.sliderValuePlacement = (placement == "below") and "below" or "side"
    if self.frame then ns.page.Render(self) end
end

-- Does the RAIL also list the children of a node that presents them
-- itself -- a subtab strip, a dropdown? Off by default: the strip owns
-- them, and the same six rows in two places is two controls for one move.
-- Per node with `railChildren`; this is the addon-wide default for the
-- nodes that do not say.
function App:SetRailChildren(shown)
    self.railChildren = shown and true or false
    if self.frame then ns.nav.Refresh(self) end
end

-- fn(isActive, routeKey, app). `everyChange` also fires while the route
-- stays inside the pattern, for observers that care about which child.
function App:RegisterRouteObserver(pattern, fn, everyChange)
    return ns.nav.RegisterRouteObserver(self, pattern, fn, everyChange)
end
function App:UnregisterRouteObserver(obs)
    return ns.nav.UnregisterRouteObserver(self, obs)
end

-- The SECTION the reader is in, which is coarser than the route: nodes
-- declare `sectionKey` and it is inherited by everything under them, so a
-- consumer that cares about "the reader is in Borders" writes one observer
-- instead of one per subtab. fn(newKey, oldKey, routeKey, app), fired only
-- when the resolved key changes -- and once on Open with oldKey nil.
function App:GetSectionKey()
    return ns.nav.GetSectionKey(self)
end
function App:RegisterSectionObserver(fn)
    return ns.nav.RegisterSectionObserver(self, fn)
end
function App:UnregisterSectionObserver(handle)
    return ns.nav.UnregisterSectionObserver(self, handle)
end

-- opts = { span = "rail"|"full", style = "rounded"|"square", maxRows = n }.
-- See ns.chrome.SetNavFooter for what each means.
function App:SetNavFooter(slots, opts) return ns.chrome.SetNavFooter(self, slots, opts) end

-- The bottom strip. `nil` removes it. The spec takes `span`
-- ("full" | "body"), `style` ("plain" | "square") and `height`.
--
-- Cells take `text` (a string or a function re-read on every render),
-- `justify`, `color` (also a string or a function), `toggled` (bool or
-- function -- an on cell paints in the accent, the same signal a nav-footer
-- cell gives), `divider` (a rule drawn in the gap AFTER the cell, for a
-- strip carrying two kinds of thing), an optional `onClick` that turns the
-- cell into a click target, and `fill`.
--
-- Exactly one cell is the FILL cell, defaulting to the first. Cells before
-- it chain from the strip's left edge and cells after it chain from the
-- right, each as wide as its own text; the fill cell takes both anchors and
-- absorbs the slack. Nothing is sized from the region's width, which is why
-- the strip does not move in Lua when the panel is resized. There is no
-- `flex`: a proportional width is exactly the thing that cannot be
-- anchored.
function App:SetStatusBar(spec)        return ns.chrome.SetStatusBar(self, spec) end
function App:RefreshStatusBar()        return ns.chrome.RenderStatusBar(self) end

-- Search. `nil` removes the box; an app that never calls this pays nothing
-- for the feature, not even an index.
-- ── Collections ────────────────────────────────────────────────
--
-- Add and Remove are plain calls, on purpose. A collection does not place
-- the control that triggers them: an add can be a button, a search box's
-- commit, or a menu entry, and the panel this replaces has all three. The
-- library owns the combat gate, the in-flight guard, the confirmation, the
-- rebuild and the re-selection; the addon owns what the widget looks like
-- and where it sits.
-- The panel's confirmation dialog: `text`, and `fn` run if they accept.
-- Collections have always had one for "remove this member?"; it is public
-- because a PAGE can need the same gate -- copying a section's settings
-- over another layout's, say -- and a second dialog would look different
-- for no reason.
function App:Confirm(text, fn)         return ns.collections.Confirm(self, text, fn) end

function App:CollectionAdd(id, ...)    return ns.collections.Add(self, id, ...) end
function App:CollectionRemove(id, key) return ns.collections.Remove(self, id, key) end
function App:CollectionMove(id, key, to) return ns.collections.Move(self, id, key, to) end
-- Where an X that acts on a whole card goes for that card's style -- the
-- header row, or the body's corner for a plain or tab header -- and the
-- offsets that put it there. For a page that hangs its own remove X on a
-- card rather than through a collection. Returns zone, x, y.
function App:CardCornerZone(group)     return ns.attach.CardCornerZone(self, group) end
function App:CollectionMembers(id)
    local node = ns.collections.Find(self, id)
    return node and ns.collections.Members(self, node) or {}
end

function App:SetSearch(spec)           return ns.search.SetSearch(self, spec) end
function App:Search(text)              return ns.search.Apply(self, text) end
function App:RebuildSearchIndex()      return ns.search.Build(self) end

-- Refresh every live widget bound to this path (usually one), and the
-- fields whose appearance depends on some OTHER setting. Values only: the
-- page's SHAPE is re-derived by the render each write schedules, and is
-- never any rung's job. See Page.lua.
-- ── The refresh ladder ─────────────────────────────────────────
--
-- Five rungs, smallest first. Ask for the smallest one that does the job:
--
--   1 RefreshBinding(path)  every live widget bound to that DB path
--   2 RefreshWidget(id)     one named widget
--   3 RefreshGroup(id)      one group's widgets, predicates and chrome
--   3 RefreshRow(routeKey)  one tree row's label -- same rung, other half
--                           of the page; answers whether it found the row
--   4 RefreshPage()         every live field, in place, plus one page
--                           re-render at the end of the frame for shape
--   5 Invalidate(key)       structural -- the only rung that CONSTRUCTS
--
-- The panel this replaces had exactly one granularity, "rebuild everything",
-- and almost every call site wanted far less: a setup-mode drag saying "the
-- X and Y sliders should follow the handle" got 2,189 nodes rebuilt for two
-- widgets.
function App:RefreshBinding(key)      return ns.page.RefreshBinding(self, key) end
function App:RefreshWidget(id)        return ns.page.RefreshWidget(self, id) end
function App:RefreshGroup(id)         return ns.page.RefreshGroup(self, id) end
function App:RefreshRow(routeKey)     return ns.nav.RefreshRow(self, routeKey) end
function App:RefreshPage()            return ns.page.RefreshPage(self) end

-- Rung 5. Structural change: the SHAPE of the tree changed, not just values
-- in it -- a container added or removed, a spec tab appearing.
--
-- Invalidation is by KEY, with any number of listeners, because the same
-- data is shown in more than one place and remembering every place is not
-- the caller's job. A page that shows containers subscribes to the
-- containers key; the add path fires that key once and knows nothing about
-- who is listening.
--
-- Listeners run BEFORE anything re-renders or navigates. That ordering is
-- the point: it is what lets a collection rebuild its routes and then have
-- the selection resolve against the new tree, instead of the two racing --
-- which is a bug class the current panel works around from both ends, one
-- place rebuilding eagerly before selecting and another deferring its
-- selection by a frame.
function App:RegisterInvalidation(key, fn)
    self.invalidators = self.invalidators or {}
    local list = self.invalidators[key]
    if not list then list = {}; self.invalidators[key] = list end
    list[#list + 1] = fn
    return fn
end

function App:UnregisterInvalidation(key, fn)
    local list = self.invalidators and self.invalidators[key]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

function App:Invalidate(key)
    for _, fn in ipairs((self.invalidators or {})[key] or {}) do
        fn(self, key)
    end

    -- Then RE-INDEX, and only then refresh.
    --
    -- This is what makes rung 5 structural. Without it, Invalidate refreshed
    -- widgets against a route index that still held the old tree: renaming a
    -- collection member updated the field the reader was typing in and
    -- nothing else, because the member's title is computed when the routes
    -- are built and the tab strip, the rail and the breadcrumb all read it
    -- from there.
    --
    -- The whole tree is re-indexed rather than the subtree the key names.
    -- Indexing is a walk, not a build -- no widgets are created, and a
    -- member's page is still only evaluated when it is visited -- so the
    -- cost is small and the alternative is a caller who has to know which
    -- parts of the tree their change could have reached. `invalidatedBy`
    -- stays available for selective rebuilds if that ever earns its keep.
    ns.nav.ReindexRoutes(self)
    ns.nav.Refresh(self)
end

-- Refresh tiers. Schedule() is what ns.Commit calls for you when a node
-- declares a tier; it is exposed here so a consuming addon can put its OWN
-- work -- a preview redraw, a frame walk not triggered by a control -- on
-- the same schedule as the settings that cause it.
function App:ScheduleEffect(spec, fn)  return ns.effects.Schedule(self, spec, fn) end
function App:FlushEffects()            return ns.effects.OnCombatEnd(self) end
function App:GetPendingEffects()       return ns.effects.GetPending(self) end
function App:IsDragging()              return ns.effects.IsDragging(self) end
function App:RenderPage()             return ns.page.Render(self) end

-- Per-app group presets: define one for this app only, or override an
-- inherited token. Never touches the library's copy.
function App:DefineGroup(name, tokens)
    local base = self.groupPresets[tokens.extends or "default"] or self.groupPresets.default
    self.groupPresets[name] = ns.CopySkin(base, tokens)
end
function App:GetGroupPreset(name) return self.groupPresets[name or "default"] end
function App:RefreshFooter()           return ns.chrome.RenderFooter(self) end

-- ============================================================
-- Per-app object pool
-- ============================================================
-- The pool is the reason a cross-addon pool leak cannot happen
-- here. A released object goes onto ITS OWN app's free list, so it can
-- only ever be handed back to the same app. `Release` also scrubs, which
-- is defense in depth WITHIN an app: a decoration left on a widget must
-- not resurface on a different page of the same panel either.

function App:Acquire(kind, factory)
    local free = self.pools[kind]
    local obj = free and table.remove(free)
    if not obj then
        obj = factory(self)
        obj._bpKind  = kind
        obj._bpOwner = self.id
    end
    obj._bpReleased = nil
    return obj
end

function App:Release(obj)
    if not obj or obj._bpReleased then return end
    assert(obj._bpOwner == self.id,
        "Release: object belongs to app '" .. tostring(obj._bpOwner) ..
        "', not '" .. self.id .. "'")

    -- Scrub. Anything an attachment or a page did to this object must
    -- not travel with it into its next use.
    --
    -- Focus first, hide second. A page refresh releases the controls of
    -- the page being redrawn; if the reader was typing in one of them the
    -- EditBox would be hidden while still focused, and Escape and Enter
    -- would then be dead until a reload (see ns.ClearFocusWithin).
    if ns.ClearFocusWithin then ns.ClearFocusWithin(obj) end
    if obj.Hide then obj:Hide() end
    if obj.ClearAllPoints then obj:ClearAllPoints() end
    if obj.SetParent then obj:SetParent(self.frame) end
    if obj.SetScript then
        for _, script in ipairs({ "OnClick", "OnEnter", "OnLeave", "OnUpdate",
                                  "OnMouseDown", "OnMouseUp", "OnValueChanged",
                                  "OnTextChanged", "OnShow", "OnHide" }) do
            if obj:HasScript(script) then obj:SetScript(script, nil) end
        end
    end
    for k in pairs(obj) do
        if type(k) == "string" and k:sub(1, 4) == "_bp_" then obj[k] = nil end
    end

    obj._bpReleased = true
    local free = self.pools[obj._bpKind]
    if not free then free = {}; self.pools[obj._bpKind] = free end
    free[#free + 1] = obj
end

-- Debug aid: how many objects each pool is holding. Used by the P0.1
-- verification step and by /bf panel poolstats later.
function App:GetPoolStats()
    local out = {}
    for kind, free in pairs(self.pools) do out[kind] = #free end
    return out
end

-- ============================================================
-- Control registration (per app, never global)
-- ============================================================
-- Registering into the APP rather than the library is deliberate: a
-- control an addon defines is that addon's, and cannot be seen -- let
-- alone overwritten -- by any other addon using this library.

function App:RegisterControl(name, def)
    assert(type(name) == "string", "RegisterControl: name must be a string")
    assert(type(def) == "table",   "RegisterControl: def must be a table")
    assert(not self.controls[name],
        "RegisterControl: '" .. name .. "' is already registered for app '" .. self.id .. "'")
    self.controls[name] = def
end

function App:GetControl(name)
    return self.controls[name]
end

Panel.App = App
