-- ============================================================
-- BuzzardFramesOptions: Pages_Testing.lua
-- The Testing page: every knob the panel itself has, in one place.
--
-- This page configures the PANEL, not Buzzard Frames. It exists because
-- the only way to judge a layout, a color or a bar style is to live with
-- it for a while -- so every choice here is stored in
-- db.global.panelTesting and re-applied when the panel opens, and none of
-- it touches a frame setting.
--
-- It is also the widest sweep of the library's own API in one file: if
-- something here cannot be expressed, the library is missing it.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- ── The store ──────────────────────────────────────────────────
--
-- One table, one set of defaults, and a getter that never returns nil --
-- a page whose fields have to guard every read reads as if the settings
-- might not exist, and they always do.
-- These are the settled ones, not the first guesses: every value here is
-- what the panel was actually being used with once each knob had been
-- lived with, so a fresh profile opens on the arrangement rather than on
-- the sketch. The page still moves every one of them.
local DEFAULTS = {
    -- "nav": the section buttons wear the same bordered, filled shape the
    -- rail's Setup Mode and Unlock buttons do, so the panel's two rows of
    -- buttons read as the same kind of thing.
    navStyle        = "nav",       -- title / top button bars
    headerShape     = "plain",     -- group headers: bar | tab | plain

    -- Subtab strips (the `tabs` navigator a node declares for itself).
    tabStyle        = "tab",       -- button (pills) | tab (Ace-style)
    railSubtabs     = false,       -- does the rail list them as well?

    -- Where a slider's value box sits. The panel's DEFAULT: a field can
    -- still say `valuePlacement` for itself.
    sliderValue     = "below",     -- side | below (the Ace arrangement)

    -- Which drawing of an icon that ships in more than one. Today that is
    -- the pair of centering glyphs; anything without a second drawing is
    -- unaffected either way.
    iconStyle       = 2,           -- 1 = box and rule | 2 = converging arrows

    footerRows      = "two",       -- how the three action cells are grouped
    footerSpan      = "rail",
    footerStyle     = "rounded",
    footerMaxRows   = 1,           -- 0 = as many as needed

    statusShown     = true,
    statusSpan      = "body",
    statusStyle     = "plain",
    statusHeight    = 22,

    searchPlacement = "rail",      -- or "auto" | "off"
    searchWidth     = 0,           -- 0 = the placement's own default
    searchPlaceholder = "Search settings",

    breadcrumb      = false,
    pageHeaderExtra = 0,
    tooltipAnchor   = "ANCHOR_TOPRIGHT",

    borderShown     = true,
    borderRadius    = 8,
    -- The two border widths INSIDE the panel, in physical pixels. Separate
    -- knobs: a card is a surface and a control is a thing, and the weight
    -- that suits one does not follow for the other.
    controlBorder   = 1,
    cardBorder      = 2,

    menuGrow        = "down",
    menuAlign       = "start",
    menuWidth       = 0,           -- 0 = as wide as its anchor
}

local function S()
    local g = BF() and BF().db and BF().db.global
    if not g then return DEFAULTS end
    g.panelTesting = g.panelTesting or {}
    return g.panelTesting
end

local function Val(key)
    local v = S()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

-- ── Applying it ────────────────────────────────────────────────
--
-- Each piece is its own function, because each is also called on its own:
-- changing the status strip's span should not re-declare the search box.
-- Apply() is the whole set, for the panel opening.

function BuzzardFramesOptions:ApplyNavFooter(app)
    local setup, unlock, opts = self:PanelActionCells(app, "footer")
    local rows = Val("footerMaxRows")
    -- A SLOT is a row. Two slots put the options button under the other
    -- two whatever the bar's width; one slot puts all three side by side
    -- and lets them wrap only if they genuinely do not fit -- which they
    -- always did across the whole panel, and never could while the shape
    -- was declared as two rows.
    local slots
    if Val("footerRows") == "one" then
        slots = { { cells = { setup, unlock, opts } } }
    else
        slots = { { cells = { setup, unlock } }, { cells = { opts } } }
    end
    app:SetNavFooter(slots, {
        span    = Val("footerSpan"),
        style   = Val("footerStyle"),
        maxRows = (rows > 0) and rows or nil,
    })
end

function BuzzardFramesOptions:ApplySearch(app)
    local where = Val("searchPlacement")
    if where == "off" then app:SetSearch(nil); return end
    local w = Val("searchWidth")
    app:SetSearch{
        placement   = where,
        placeholder = Val("searchPlaceholder"),
        width       = (w > 0) and w or nil,
    }
end

function BuzzardFramesOptions:ApplyPanelChrome(app)
    -- Both of these are DEFAULTS for nodes that do not say for themselves,
    -- which is every node the panel has today -- so the two knobs on this
    -- page move the whole panel and a section can still overrule them
    -- later with `tabStyle` / `railChildren` of its own.
    app:SetTabStyle(Val("tabStyle"))
    app:SetRailChildren(Val("railSubtabs"))
    app:SetSliderValuePlacement(Val("sliderValue"))
    app:SetIconStyle(Val("iconStyle"))
    app:SetBreadcrumbShown(Val("breadcrumb"))
    app:SetPageHeaderExtra(Val("pageHeaderExtra"))
    app:SetTooltipAnchor(Val("tooltipAnchor"))
    app:SetBorderShown(Val("borderShown"))
    app:SetBorderRadius(Val("borderRadius"))
    app:SetControlBorderSize(Val("controlBorder"))
    app:SetCardBorderSize(Val("cardBorder"))
    local w = Val("menuWidth")
    app:SetMenuStyle{
        grow     = Val("menuGrow"),
        align    = Val("menuAlign"),
        minWidth = (w > 0) and w or nil,
    }
    -- Group headers are a PRESET token, so the shape is set by redefining
    -- the app's own copies of the presets rather than by touching a group.
    --
    -- ALL of them, not just `default`: `form` and `bare` were COPIED from
    -- default when the app opened, and a copy does not track its source --
    -- so redefining default alone left every page that names another preset
    -- (which is most of them) with the old shape. `extends = <itself>`
    -- overrides one token in place.
    local shape = Val("headerShape")
    for _, name in ipairs({ "default", "form", "bare", "strip" }) do
        app:DefineGroup(name, { extends = name, headerShape = shape })
    end
end

function BuzzardFramesOptions:ApplyPanelSettings(app)
    self:ApplyStoredPanelColors(app)
    self:ApplyPanelChrome(app)
    self:ApplySearch(app)
    self:ApplyNavFooter(app)
    -- Last, because the layout re-declares both the footer and the strip.
    self:SetPanelLayout(app, BF().db.global.panelLayout or BuzzardFramesOptions.DEFAULT_PANEL_LAYOUT)
end

-- ── Panel colors ──────────────────────────────────────────────
--
-- Every one is a SKIN TOKEN, so the panel repaints itself the moment a
-- swatch changes -- and the choice is stored and re-applied on open, so a
-- color survives a reload rather than reverting to the shipped skin.
--
-- Alpha matters more here than anywhere else: the panel background is the
-- only layer between the panel and the frames it exists to configure, so
-- its alpha IS the panel's transparency.
local PANEL_COLOR_TOKENS = {
    { token = "panelBg",      label = "Panel Background" },
    { token = "panelBorder",  label = "Panel Border" },
    { token = "titlebarBg",   label = "Title Bar" },
    { token = "railBg",       label = "Sidebar" },
    { token = "railBorder",   label = "Sidebar Border" },
    { token = "footerBg",     label = "Sidebar Footer" },
    { token = "statusbarBg",  label = "Status Strip" },
    { token = "divider",      label = "Dividers" },
    { token = "accent",       label = "Accent" },
    { token = "controlBg",    label = "Control Background" },
    { token = "controlBorder", label = "Control Border" },
    { token = "groupHeaderBg", label = "Group Header" },
    { token = "groupBg",       label = "Group Background" },
    { token = "groupBorder",   label = "Group Border" },
    { token = "groupHeading",  label = "Group Heading Text" },
    { token = "groupLabel",    label = "Control Label Text" },
    { token = "text",         label = "Text" },
    { token = "textNote",     label = "Note Text" },
    { token = "textMuted",    label = "Muted Text" },
    { token = "tooltipTitle", label = "Tooltip Heading" },
    { token = "tooltipText",  label = "Tooltip Text" },
}

-- The tab strip's own six, kept in their own list so they can be their
-- own card. They share the store, the capture and the field builder with
-- the panel colors above -- only the group they land in differs.
local TAB_COLOR_TOKENS = {
    { token = "tabSelBorder", label = "Selected Tab Border" },
    { token = "tabSelBg",     label = "Selected Tab Background" },
    -- Named for tabs, but every selected label reads it: the rail's
    -- selected row and the selected section button take it too.
    { token = "tabSelText",   label = "Selected Tab Text" },
    { token = "tabBorder",    label = "Unselected Tab Border" },
    { token = "tabBg",        label = "Unselected Tab Background" },
    { token = "tabText",      label = "Unselected Tab Text" },
}

-- The buttons' four pairs, in their own card for the same reason the tabs'
-- six are: they share the store, the capture and the field builder, and
-- only the group they land in differs.
--
-- FOUR KINDS, because a button's color is the first thing that says what
-- pressing it costs. Primary is a plain action on a page (Export, Import,
-- Clone); Confirmation is a text field's Accept; Destructive is any button
-- declaring `danger` -- deleting a profile, reverting to defaults;
-- Navigation is the chrome's own action cells (Setup Mode, Unlock, Addon
-- Options) and, with the bar set to Navigation style, the section buttons
-- beside them.
local BUTTON_COLOR_TOKENS = {
    { token = "buttonPrimaryBg",   label = "Primary Button Color" },
    { token = "buttonPrimaryText", label = "Primary Button Text Color" },
    { token = "buttonConfirmBg",   label = "Confirmation Button Color" },
    { token = "buttonConfirmText", label = "Confirmation Button Text Color" },
    { token = "buttonDangerBg",    label = "Destructive Button Color" },
    { token = "buttonDangerText",  label = "Destructive Button Text Color" },
    { token = "buttonNavBg",       label = "Navigation Button Color" },
    { token = "buttonNavText",     label = "Navigation Button Text Color" },
}

-- The colors the app was created with. Captured once, before anything
-- stored is applied, so "Reset" means the skin as shipped rather than
-- whatever was in the saved variables when the panel first opened.
local defaultColors

local function CaptureDefaultColors(app)
    if defaultColors then return end
    defaultColors = {}
    local skin = app:GetSkin()
    for _, list in ipairs({ PANEL_COLOR_TOKENS, BUTTON_COLOR_TOKENS, TAB_COLOR_TOKENS }) do
        for _, e in ipairs(list) do
            local c = skin[e.token]
            if c then defaultColors[e.token] = { c[1], c[2], c[3], c[4] or 1 } end
        end
    end
end

local function StoredColors()
    local g = BF() and BF().db and BF().db.global
    if not g then return nil end
    g.panelColors = g.panelColors or {}
    return g.panelColors
end

-- "Use Accent Color" -- the switch that hands the tab strip back to the
-- accent and leaves the six tokens unread. Stored beside the colors
-- rather than in the testing store, because it is a fact about the same
-- card and restoring it is the same pass.
local function TabAccentOn()
    local store = StoredColors()
    return (store and store.tabUseAccent) and true or false
end

function BuzzardFramesOptions:ApplyStoredPanelColors(app)
    CaptureDefaultColors(app)
    local store = StoredColors()
    if not store then return end
    for _, list in ipairs({ PANEL_COLOR_TOKENS, BUTTON_COLOR_TOKENS, TAB_COLOR_TOKENS }) do
        for _, e in ipairs(list) do
            local c = store[e.token]
            if type(c) == "table" and #c >= 3 then
                app:SetSkinColor(e.token, { c[1], c[2], c[3], c[4] or 1 })
            end
        end
    end
    -- Not a color, so it is set on the skin directly. Before the nav is
    -- first painted, which is why this runs on open rather than lazily.
    app:GetSkin().tabUseAccent = TabAccentOn()
end

local function ColorFields(app, list, disabled)
    CaptureDefaultColors(app)
    local fields = {}
    for _, e in ipairs(list or PANEL_COLOR_TOKENS) do
        local fallback = defaultColors[e.token]
        fields[#fields + 1] = {
            control = "color", label = e.label, alpha = true,
            disabled = disabled,
            -- `id` and `default` are what make the panel's own right-click
            -- reset work on a field with no `bind`.
            id      = "panelColor_" .. e.token,
            default = fallback and { fallback[1], fallback[2], fallback[3], fallback[4] },
            get = function(_, ctx) return ctx.app:GetSkin()[e.token] end,
            set = function(_, ctx, c)
                ctx.app:SetSkinColor(e.token, c)
                local store = StoredColors()
                if not store then return end
                -- Back at the shipped color is not an override: clearing it
                -- means a later change to the skin's own default reaches
                -- this reader instead of being masked by a saved copy.
                local d = defaultColors[e.token]
                if d and d[1] == c[1] and d[2] == c[2] and d[3] == c[3]
                   and (d[4] or 1) == (c[4] or 1) then
                    store[e.token] = nil
                else
                    store[e.token] = { c[1], c[2], c[3], c[4] or 1 }
                end
            end,
        }
    end
    return fields
end

-- The Tab Colors card: the switch, then the six swatches it governs.
-- The swatches stay VISIBLE while the accent is driving -- grayed, not
-- gone, so what the switch is overriding is still readable.
local function TabColorFields(app)
    local fields = {
        { control = "switch", label = "Use Accent Color",
          id = "panelColor_tabUseAccent", default = false,
          desc = "Color the subtab strip from the panel's Accent, as it "
              .. "did before these swatches existed. The six below are "
              .. "ignored while this is on.",
          get = function() return TabAccentOn() end,
          set = function(_, ctx, v)
              local store = StoredColors()
              if store then store.tabUseAccent = v or nil end
              ctx.app:GetSkin().tabUseAccent = v and true or false
              ctx.app:RefreshNav()
              -- The swatches' own disabled state is a change of SHAPE, so
              -- the page is re-rendered -- next frame, because we are
              -- inside the handler of the control the render will release.
              if C_Timer then
                  C_Timer.After(0, function() ctx.app:RenderPage() end)
              else
                  ctx.app:RenderPage()
              end
          end },
    }
    for _, f in ipairs(ColorFields(app, TAB_COLOR_TOKENS, TabAccentOn)) do
        fields[#fields + 1] = f
    end
    return fields
end

-- ── Field helpers ──────────────────────────────────────────────
--
-- Every option on this page is the same shape: read the store, write the
-- store, then re-apply the piece of the panel it belongs to. `apply` names
-- which piece, so no field has to remember more than that.

local function Opt(spec)
    local key = spec.key
    return {
        control  = spec.control,
        label    = spec.label,
        desc     = spec.desc,
        options  = spec.options,
        min      = spec.min, max = spec.max, step = spec.step,
        width    = spec.width,
        wide     = spec.wide,
        id       = "panelTesting_" .. key,
        default  = DEFAULTS[key],
        get      = function() return Val(key) end,
        set      = function(_, ctx, v)
            S()[key] = v
            if spec.apply then spec.apply(ctx.app) end
        end,
    }
end

local function ApplyChrome(app)  BuzzardFramesOptions:ApplyPanelChrome(app)  end
local function ApplyFooter(app)  BuzzardFramesOptions:ApplyNavFooter(app)    end
local function ApplySearch(app)  BuzzardFramesOptions:ApplySearch(app)       end
local function ApplyStatus(app)  BuzzardFramesOptions:ApplyPanelStatusBar(app) end
-- A preset change is a change of SHAPE, so the page is rebuilt rather than
-- refreshed -- and on the next frame, because we are inside the handler of
-- a control the rebuild will release.
local function ApplyGroups(app)
    BuzzardFramesOptions:ApplyPanelChrome(app)
    if C_Timer then
        C_Timer.After(0, function() app:RenderPage() end)
    else
        app:RenderPage()
    end
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:TestingPage(app)
    return {
        groups = {
            { title = "Navigation", fields = {
                -- The layout predates this page and lives in db.global on
                -- its own, so it is written there rather than moved into
                -- the testing store and left in two places.
                { control = "dropdown", label = "Panel Layout",
                  id = "panelLayout", default = BuzzardFramesOptions.DEFAULT_PANEL_LAYOUT,
                  desc = "How the seven top-level sections are presented. "
                      .. "Every layout shows the same routes -- only the "
                      .. "navigator differs.",
                  options = self.PANEL_LAYOUT_OPTIONS,
                  get = function() return BF().db.global.panelLayout or BuzzardFramesOptions.DEFAULT_PANEL_LAYOUT end,
                  set = function(_, ctx, v)
                      BuzzardFramesOptions:SetPanelLayout(ctx.app, v)
                  end },
                Opt{ key = "navStyle", control = "segmented", label = "Button Bar Style",
                     desc = "Rounded cards, one divided bar, or the shape the "
                         .. "rail's Setup Mode and Unlock buttons wear -- "
                         .. "bordered and filled at rest rather than blank "
                         .. "until you touch them. Applies to the title-bar, "
                         .. "top-strip and full-height-rail layouts -- the "
                         .. "ones with a section button bar.",
                     options = { { value = "rounded", text = "Rounded" },
                                 { value = "square",  text = "Square" },
                                 { value = "nav",     text = "Navigation" } },
                     apply = function(app)
                         BuzzardFramesOptions:SetPanelLayout(
                             app, BF().db.global.panelLayout or BuzzardFramesOptions.DEFAULT_PANEL_LAYOUT)
                     end },
                Opt{ key = "tabStyle", control = "segmented", label = "Subtab Style",
                     desc = "How a section's subtab strip looks. Buttons are "
                         .. "rounded pills; Tabs sit on a rule across the page "
                         .. "with the selected one breaking it, which is how "
                         .. "the Ace panel's tabs read.",
                     options = { { value = "button", text = "Buttons" },
                                 { value = "tab",    text = "Tabs" } },
                     apply = ApplyChrome },
                Opt{ key = "iconStyle", control = "segmented",
                     label = "Center Icon Style",
                     desc = "Which drawing the Center Horizontally / Center "
                         .. "Vertically buttons wear. Box draws the axis line "
                         .. "through a frame; Arrows drops the frame and shows "
                         .. "two arrowheads converging on the line instead."
                         .. "\n\nBoth say the same thing about the same axis "
                         .. "-- pick whichever reads faster.",
                     options = { { value = 1, text = "Box"    },
                                 { value = 2, text = "Arrows" } },
                     apply = ApplyChrome },
                Opt{ key = "railSubtabs", control = "switch", label = "Subtabs in Sidebar",
                     desc = "Also list a section's subtabs in the sidebar tree. "
                         .. "Off, the strip owns them -- which is one control "
                         .. "for one move rather than the same six rows twice.",
                     apply = ApplyChrome },
                Opt{ key = "sliderValue", control = "segmented",
                     label = "Slider Value Box",
                     desc = "Where a slider's editable value sits. Side keeps "
                         .. "it in a gap at the right of the track; Below "
                         .. "centers it underneath, level with the min and max "
                         .. "-- which is how the Ace panel's sliders read, and "
                         .. "a taller row.\n\nThis is the panel's default; a "
                         .. "single slider can still ask for the other one.",
                     options = { { value = "side",  text = "Side"  },
                                 { value = "below", text = "Below" } },
                     apply = ApplyChrome },
                { control = "note", wide = true,
                  text = "Layouts are a chrome declaration, not a mode the "
                      .. "library knows about: the routes are the same in all "
                      .. "five." },
            }},

            { title = "Sidebar Buttons", fields = {
                Opt{ key = "footerRows", control = "segmented", label = "Rows",
                     desc = "Two rows keeps Addon Options under the other "
                         .. "two; one row puts all three side by side and "
                         .. "lets them wrap only if they do not fit.",
                     options = { { value = "two", text = "Two" },
                                 { value = "one", text = "One" } },
                     apply = ApplyFooter },
                Opt{ key = "footerSpan", control = "segmented", label = "Span",
                     desc = "Under the tree, or across the whole bottom of the panel.",
                     options = { { value = "rail", text = "Sidebar" },
                                 { value = "full", text = "Whole panel" } },
                     apply = ApplyFooter },
                Opt{ key = "footerStyle", control = "segmented", label = "Style",
                     options = { { value = "rounded", text = "Rounded" },
                                 { value = "square",  text = "Square" } },
                     apply = ApplyFooter },
                Opt{ key = "footerMaxRows", control = "stepper", label = "Max Rows",
                     desc = "0 lets a row of buttons wrap as far as it needs. "
                         .. "At 1 the labels truncate instead.",
                     min = 0, max = 4, step = 1, apply = ApplyFooter },
            }},

            { title = "Status Strip",
              toggle = { id = "statusShown", default = DEFAULTS.statusShown,
                         tooltip = "Show the status strip",
                         get = function() return Val("statusShown") end,
                         set = function(_, ctx, v)
                             S().statusShown = v
                             ctx.app:SetStatusBarShown(v)
                         end },
              fields = {
                Opt{ key = "statusSpan", control = "segmented", label = "Span",
                     options = { { value = "full", text = "Whole panel" },
                                 { value = "body", text = "Beside the sidebar" } },
                     apply = ApplyStatus },
                Opt{ key = "statusStyle", control = "segmented", label = "Style",
                     options = { { value = "plain",  text = "Plain" },
                                 { value = "square", text = "Square" } },
                     apply = ApplyStatus },
                Opt{ key = "statusHeight", control = "slider", label = "Height",
                     min = 16, max = 34, step = 1, apply = ApplyStatus },
            }},

            { title = "Search", fields = {
                Opt{ key = "searchPlacement", control = "dropdown", label = "Placement",
                     desc = "Auto follows the section navigator: the sidebar "
                         .. "when there is one, the title bar when there is not.",
                     options = { { value = "auto",     text = "Auto" },
                                 { value = "rail",     text = "Sidebar" },
                                 { value = "titlebar", text = "Title bar" },
                                 { value = "top",      text = "Top strip" },
                                 { value = "strip",    text = "Button bar" },
                                 { value = "off",      text = "No search box" } },
                     apply = ApplySearch },
                Opt{ key = "searchWidth", control = "slider", label = "Width",
                     desc = "0 uses whatever the placement decides.",
                     min = 0, max = 320, step = 10, apply = ApplySearch },
                Opt{ key = "searchPlaceholder", control = "text", label = "Placeholder",
                     apply = ApplySearch },
            }},

            { title = "Groups", fields = {
                Opt{ key = "headerShape", control = "segmented", label = "Header Shape",
                     desc = "A band across the card, a tab sized to its own "
                         .. "title and sitting above the card, or a plain "
                         .. "heading with no background or border at all.",
                     options = { { value = "bar",   text = "Band" },
                                 { value = "tab",   text = "Tab" },
                                 { value = "plain", text = "Plain" } },
                     apply = ApplyGroups },
            }},

            { title = "Page Header", fields = {
                Opt{ key = "breadcrumb", control = "switch", label = "Breadcrumb",
                     desc = "The path to the page you are on, above it.",
                     apply = ApplyChrome },
                Opt{ key = "pageHeaderExtra", control = "slider", label = "Extra Space",
                     desc = "Room reserved below the header for anything a page "
                         .. "anchors there.",
                     min = 0, max = 40, step = 2, apply = ApplyChrome },
                Opt{ key = "tooltipAnchor", control = "dropdown", label = "Tooltip Anchor",
                     options = { { value = "ANCHOR_TOPRIGHT",    text = "Top right" },
                                 { value = "ANCHOR_RIGHT",       text = "Right" },
                                 { value = "ANCHOR_BOTTOMRIGHT", text = "Bottom right" },
                                 { value = "ANCHOR_LEFT",        text = "Left" },
                                 { value = "ANCHOR_CURSOR",      text = "At the cursor" } },
                     apply = ApplyChrome },
            }},

            { title = "Panel Frame", fields = {
                Opt{ key = "borderShown", control = "switch", label = "Outer Border",
                     apply = ApplyChrome },
                Opt{ key = "borderRadius", control = "dropdown", label = "Corner Radius",
                     desc = "Snaps to an authored radius: the art exists at "
                         .. "these sizes and nowhere between them.",
                     options = { { value = 0,  text = "Square" },
                                 { value = 4,  text = "4" },
                                 { value = 6,  text = "6" },
                                 { value = 8,  text = "8" },
                                 { value = 12, text = "12" } },
                     apply = ApplyChrome },
                -- Both are re-strokes, not re-renders: every bordered shape
                -- re-insets itself where it stands, so the change lands on
                -- the page you are looking at rather than after a rebuild.
                Opt{ key = "controlBorder", control = "segmented",
                     label = "Control Border",
                     desc = "The stroke on every control's border -- "
                         .. "dropdowns, switches, value boxes, swatches, "
                         .. "chips, subtabs and tracks -- in PHYSICAL pixels, "
                         .. "so it is the same weight at any UI scale.",
                     options = { { value = 1, text = "1px" },
                                 { value = 2, text = "2px" } },
                     apply = ApplyChrome },
                Opt{ key = "cardBorder", control = "segmented",
                     label = "Card Border",
                     desc = "The same for the surfaces that HOLD controls: a "
                         .. "group's box and header, the tab shape, pop-up "
                         .. "menus and the suggestion list.",
                     options = { { value = 1, text = "1px" },
                                 { value = 2, text = "2px" } },
                     apply = ApplyChrome },
            }},

            { title = "Menus", fields = {
                Opt{ key = "menuGrow", control = "segmented", label = "Opens",
                     desc = "Which way a menu opens from the control that owns "
                         .. "it. Auto drops down unless there is no room below.",
                     options = { { value = "up",   text = "Up" },
                                 { value = "down", text = "Down" },
                                 { value = "auto", text = "Auto" } },
                     apply = ApplyChrome },
                Opt{ key = "menuAlign", control = "segmented", label = "Aligns",
                     options = { { value = "start",  text = "Start" },
                                 { value = "center", text = "Center" },
                                 { value = "end",    text = "End" } },
                     apply = ApplyChrome },
                Opt{ key = "menuWidth", control = "slider", label = "Min Width",
                     desc = "0 makes a menu at least as wide as its anchor.",
                     min = 0, max = 320, step = 10, apply = ApplyChrome },
            }},

            { title = "Panel Colors", preset = "form", fields = ColorFields(app) },

            { title = "Buttons", preset = "form",
              fields = ColorFields(app, BUTTON_COLOR_TOKENS) },

            { title = "Tab Colors", preset = "form", fields = TabColorFields(app) },
        },
    }
end
