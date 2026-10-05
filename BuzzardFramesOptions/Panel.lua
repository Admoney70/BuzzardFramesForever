-- ============================================================
-- BuzzardFramesOptions: Panel.lua
-- The Buzzard Frames options panel, built on BuzzardPanel.
--
-- LOAD-ON-DEMAND. Nothing here runs at login: BuzzardFrames asks for this
-- addon the first time the panel is opened, and until then neither this
-- file nor the library beneath it is parsed.
--
-- It owns no SavedVariables. Everything it reads and writes belongs to
-- BuzzardFrames -- the panel's geometry included, which the library stores
-- in db.global under keys of its own. Two addons owning one profile is how
-- a setting ends up saved in the wrong file and lost on the next login.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON.
--
-- This file builds one local table, hangs its functions off it, and
-- publishes it as a global at the end. The main addon is read inside those
-- functions, at the moment the panel is opened -- by which point it is
-- certainly there, because it is the caller.
--
-- That is not belt-and-braces. Two earlier versions of this file did the
-- lookup while loading -- once through AceAddon's GetAddon, once through
-- the global -- and both failed in the main chunk, where the traceback
-- blames this addon rather than the assumption. Load order is a thing a
-- load-on-demand addon should not have an opinion about.
-- ============================================================
local BuzzardFramesOptions = {}

-- Is "Enable Experimental Options" OFF? Written as a plain function (no
-- self) so it can be assigned straight to a field's or a card's `hidden`
-- -- the library calls those with its own arguments, which this ignores.
-- Every experimental gate on every page answers through this one copy,
-- and it defers to BF:IsExperimentalEnabled so the db key is named once
-- in the whole addon.
function BuzzardFramesOptions.ExperimentalOff()
    local bf = BuzzardFramesOptions:BF()
    if not (bf and bf.IsExperimentalEnabled) then return true end
    return not bf:IsExperimentalEnabled()
end

-- The six layouts worth comparing against the real section list.
--
-- Stored in db.global.panelLayout so a choice survives a reload -- comparing
-- them means living with each for a while, not flicking between them once.
--
-- Routes are data and navigators are views, so every one of these presents
-- the SAME seventeen sections. Which of them suits that many is the open
-- question in the plan's route-tree design, and it is answered by looking at
-- each against the real section names rather than by reasoning about them.
local PANEL_LAYOUTS = {
    -- One rail tree carrying every level.
    tree = {
        left = { { navigator = "tree", level = 1 } },
    },
    -- Sections in the title bar, that section's tree in the rail. Costs no
    -- extra height, because the title bar is already there.
    title = {
        titlebar = { { navigator = "buttonbar", level = 1 } },
        left     = { { navigator = "tree",      level = 2 } },
    },
    -- The same bar in its own strip under the title bar.
    strip = {
        top  = { { navigator = "buttonbar", level = 1 } },
        left = { { navigator = "tree",      level = 2 } },
    },
    -- Sections collapsed into a dropdown, tree still in the rail.
    menu = {
        top  = { { navigator = "dropdown", level = 1 } },
        left = { { navigator = "tree",     level = 2 } },
    },
    -- The rail from the panel's top edge to its bottom, carrying the icon
    -- and the title in its head; the section buttons in a strip that starts
    -- at the rail's right edge rather than at the panel's, with the close
    -- button at its end. The title bar is not merely empty here -- it is
    -- collapsed, so the strip is the panel's top row beside the rail.
    railtop = {
        railSpan = "full",
        top  = { { navigator = "buttonbar", level = 1 } },
        -- `withParent`: the selected section's own page gets a row in the
        -- rail, a sibling of its pages rather than a heading over them,
        -- and named for what it holds rather than repeating the section
        -- name off the strip. Without it that page is reachable only by
        -- clicking the strip button for the section you are already in.
        left = { { navigator = "tree", level = 2, withParent = "Enable" } },
    },
    -- No rail at all: a dropdown per LEVEL, and a clickable path back up.
    -- A navigator per level matters here -- a breadcrumb only goes up, so a
    -- rail-free layout with one dropdown could reach a section and nothing
    -- inside it.
    compact = {
        left       = false,
        top        = { { navigator = "dropdown", level = 1 },
                       { navigator = "dropdown", level = 2 } },
        pageheader = { { navigator = "breadcrumb" } },
    },
}

-- What a profile with no stored choice opens on. Named once here and read
-- by everything that has to fall back, so the default is one edit rather
-- than five agreeing string literals.
local DEFAULT_LAYOUT = "railtop"
BuzzardFramesOptions.DEFAULT_PANEL_LAYOUT = DEFAULT_LAYOUT

local PANEL_LAYOUT_OPTIONS = {
    { value = "tree",    text = "Rail tree" },
    { value = "title",   text = "Title bar buttons" },
    { value = "strip",   text = "Top strip buttons" },
    { value = "railtop", text = "Full-height rail" },
    { value = "menu",    text = "Dropdown" },
    { value = "compact", text = "Compact (no rail)" },
}
-- Published for Pages_Testing.lua, which offers the same list.
BuzzardFramesOptions.PANEL_LAYOUT_OPTIONS = PANEL_LAYOUT_OPTIONS

-- A chrome spec is DATA, so a style is applied to it rather than being a
-- sixth layout: every button-bar navigator in the chosen layout takes the
-- style, and a layout without one is unaffected.
local function ChromeFor(which, style)
    local src = PANEL_LAYOUTS[which] or PANEL_LAYOUTS[DEFAULT_LAYOUT]
    local out = {}
    for region, navs in pairs(src) do
        if type(navs) ~= "table" then
            out[region] = navs           -- `left = false`
        else
            local copy = {}
            for i, nav in ipairs(navs) do
                local n = {}
                for k, v in pairs(nav) do n[k] = v end
                if n.navigator == "buttonbar" then n.style = style end
                copy[i] = n
            end
            out[region] = copy
        end
    end
    return out
end

-- Setup Mode, Unlock and the options menu, in whichever shape the region
-- that is showing them wants.
--
-- A footer cell names its text `label` and a status cell names it `text`;
-- a footer cell takes `disabled` and `menu` and a status cell takes
-- neither. Everything else about them -- what they read, what they write,
-- what they say -- is the same, so this is one declaration wired to the
-- real state rather than two that drift.
--
-- Why both shapes exist at all: the footer lives in the RAIL, and Compact
-- hides the rail. Rather than lose the controls with it, they move to the
-- strip, which every layout shows.
local function LockedNow()
    -- BuzzardFrames:SetLocked works on db.global.locked, which DEFAULTS TO LOCKED when
    -- the key is absent -- hence the nil handling, matching the Ace panel.
    local locked = BuzzardFrames.db.global.locked
    if locked == nil then locked = true end
    return locked
end

-- The face the panel draws itself in.
--
-- PT Sans Narrow, which Buzzard Frames bundles and registers, unless the
-- reader has asked for the game font in Addon Options. Returning NIL is how
-- the library is told "the game font": every string then keeps the face its
-- Blizzard template carries.
--
-- Resolved through BF:ResolveFontPath so the registered name and the file
-- cannot drift apart, with the literal as the last resort -- this addon is
-- load-on-demand and is read at open, by which point BuzzardFrames is
-- certainly loaded, but a missing resolver should cost the font rather than
-- the panel.
local PT_SANS_NARROW = "Interface\\AddOns\\BuzzardFrames\\Media\\Fonts\\PTSansNarrow.ttf"

local function PanelFont()
    local bf = BuzzardFrames
    local g  = bf and bf.db and bf.db.global
    if g and g.panelGameFont then return nil end
    if bf and bf.ResolveFontPath then
        local ok, path = pcall(bf.ResolveFontPath, bf, "PT Sans Narrow")
        if ok and path then return path end
    end
    return (bf and bf.font) or PT_SANS_NARROW
end

-- The live panel, for a menu row that has to reach it. The rows are built
-- without one -- the menu knows nothing about the app that opened it -- and
-- the library hands out apps by name.
local function PanelApp()
    local P = LibStub and LibStub("BuzzardPanel-1.0", true)
    return P and P:GetApp("BuzzardFrames")
end

-- The Addon Options menu, in BuzzardPanel's own idiom rather than the
-- client's context menu: the panel styles it, it opens upwards out of the
-- button at the bottom of the panel, and clicking that button again closes
-- it -- which a context menu, closing itself on the same click that
-- reopens it, could never do.
local function OptionsItems()
    local items = {
        {
            kind     = "toggle",
            text     = "Tiny Handle",
            desc     = "Shrink the drag handle shown on unlocked frames.",
            -- A function, not a value: the row repaints itself in place
            -- when it is flipped, and re-reads the setting to do it.
            selected = function() return BuzzardFrames.db.global.tinyHandle end,
            onPick   = function()
                BuzzardFrames.db.global.tinyHandle = not BuzzardFrames.db.global.tinyHandle
                if BuzzardFrames.ApplyTinyHandle then BuzzardFrames:ApplyTinyHandle() end
            end,
        },
        {
            kind     = "toggle",
            text     = "Show Minimap Icon",
            desc     = "Show the minimap button.",
            selected = function()
                local mm = BuzzardFrames.db and BuzzardFrames.db.global
                    and BuzzardFrames.db.global.minimapIcon
                return not (mm and mm.hide)
            end,
            onPick   = function()
                local mm = BuzzardFrames.db and BuzzardFrames.db.global
                    and BuzzardFrames.db.global.minimapIcon
                if not mm then return end
                mm.hide = not mm.hide
                -- The launcher itself is registered once at load; only its
                -- visibility is toggled here.
                local LibDBIcon = LibStub("LibDBIcon-1.0", true)
                if LibDBIcon then
                    if mm.hide then LibDBIcon:Hide("BuzzardFrames")
                    else            LibDBIcon:Show("BuzzardFrames") end
                end
            end,
        },
        {
            kind     = "toggle",
            text     = "Show Grid in Setup Mode",
            desc     = "Draw the alignment grid while Setup Mode is on.",
            selected = function()
                return BuzzardFrames.db and BuzzardFrames.db.global
                    and BuzzardFrames.db.global.showSetupGrid
            end,
            onPick   = function()
                local g = BuzzardFrames.db and BuzzardFrames.db.global
                if not g then return end
                g.showSetupGrid = not g.showSetupGrid
                if BuzzardFrames.UpdateSetupGrid then BuzzardFrames:UpdateSetupGrid() end
            end,
        },
        {
            kind     = "toggle",
            text     = "Panel Uses Default Game Font",
            desc     = "Draw this panel in the game's own font instead of "
                .. "PT Sans Narrow. Only the face changes -- every size and "
                .. "outline stays as it is.",
            selected = function()
                return BuzzardFrames.db.global.panelGameFont
            end,
            onPick   = function()
                local g = BuzzardFrames.db and BuzzardFrames.db.global
                if not g then return end
                g.panelGameFont = not g.panelGameFont or nil
                -- Live: the library re-points every string it has made,
                -- including the row being clicked, so there is nothing to
                -- rebuild and the menu stays up.
                local app = PanelApp()
                if app then app:SetPanelFont(PanelFont()) end
            end,
        },
    }
    -- Panel scale, RELATIVE to the game's own UI scale: 1.00 draws the
    -- panel at exactly the size everything else on screen is drawn at,
    -- whatever the UI scale is -- pixel-perfect or not. Off the whole-pixel
    -- sizes the strokes render a hair softer (like the rest of the UI at a
    -- non-pixel-perfect scale), never broken.
    items[#items + 1] = { kind = "separator" }
    items[#items + 1] = {
        kind   = "slider",
        text   = "Panel Scale",
        desc   = "Size of this panel relative to the rest of your UI. "
            .. "1.00 matches your UI scale exactly.",
        min    = 0.6,
        max    = 1.6,
        step   = 0.05,
        format = function(v) return string.format("%.2fx", v) end,
        get    = function()
            local g = BuzzardFrames.db and BuzzardFrames.db.global
            return (g and g.panelScale) or 1
        end,
        set    = function(v)
            local g = BuzzardFrames.db and BuzzardFrames.db.global
            if not g then return end
            g.panelScale = v
            local app = PanelApp()
            if app and app.SetPanelScale then app:SetPanelScale(v) end
        end,
    }
    return items
end

local OPTIONS_MENU_STYLE = {
    grow     = "up",
    align    = "start",
    title    = "Addon Options",
    minWidth = 210,
}

function BuzzardFramesOptions:PanelActionCells(app, kind)
    local status = (kind == "status")
    local skin   = app:GetSkin()

    -- A status cell has no `disabled`, so the combat gate becomes a refusal
    -- inside onClick and a muted color while it would refuse. Saying no
    -- silently is worse than looking unavailable.
    local function gated(fn)
        return function()
            if InCombatLockdown() then return end
            fn()
        end
    end
    local function combatColor(on)
        return function()
            if InCombatLockdown() then return skin.textMuted end
            return on() and skin.accent or (skin.textNote or skin.text)
        end
    end

    -- No tooltips on these three: the labels say what they do, and a
    -- tooltip that only restates a label is noise under the cursor.
    local setup = {
        flex = 1, justify = "CENTER",
        toggled = function() return BuzzardFrames.db.global.setupModeActive end,
        onClick = gated(function()
            BuzzardFrames:ToggleSetupMode(not BuzzardFrames.db.global.setupModeActive)
        end),
    }
    local unlock = {
        flex = 1, justify = "CENTER", tooltip = "Unlock frames for dragging",
        toggled = function() return not LockedNow() end,
        onClick = gated(function() BuzzardFrames:SetLocked(not LockedNow()) end),
    }
    local opts = {
        flex = 1, justify = "CENTER",
    }

    if status then
        setup.text,  unlock.text,  opts.text = "Setup Mode", "Unlock", "Addon Options"
        setup.color  = combatColor(function() return BuzzardFrames.db.global.setupModeActive end)
        unlock.color = combatColor(function() return not LockedNow() end)
        -- The same menu the footer cell carries, anchored to the strip
        -- cell instead. A status cell has no `disabled`, but the menu is
        -- never combat-gated, so nothing is lost here.
        opts.items     = OptionsItems
        opts.menuStyle = OPTIONS_MENU_STYLE
        opts.divider   = true
    else
        setup.label, unlock.label, opts.label = "Setup Mode", "Unlock", "Addon Options"
        setup.disabled, unlock.disabled = "combat", "combat"
        opts.items     = OptionsItems
        opts.menuStyle = OPTIONS_MENU_STYLE
    end
    return setup, unlock, opts
end

-- The strip, re-declared with the chrome: in Compact it carries the three
-- actions the hidden footer would have, ahead of the route.
function BuzzardFramesOptions:ApplyPanelStatusBar(app)
    local cells = {}
    if (BuzzardFrames.db.global.panelLayout or DEFAULT_LAYOUT) == "compact" then
        local setup, unlock, opts = self:PanelActionCells(app, "status")
        cells[1], cells[2], cells[3] = setup, unlock, opts
    end
    -- The fill cell, blank. Exactly one cell absorbs the strip's slack --
    -- it is what stops the strip re-laying itself out on a resize -- but it
    -- need not SAY anything: the route is already on the page header and in
    -- the tree, and a third copy of it along the bottom was noise.
    cells[#cells + 1] = { fill = true, text = "" }
    -- The Ace panel's status line, in the panel's own strip: the instance
    -- type the frames are resolving against, and -- while the reader is in
    -- Raid/Party Frames -- which flat that resolves to.
    --
    -- Setup Mode and the lock state used to be here. Both are already
    -- controls in the footer, showing their own state, so the strip was
    -- reporting what the reader could see two inches to the left; the
    -- resolved layout is the thing the panel could not otherwise tell them.
    --
    -- Active Layout is scoped to that section because it means nothing
    -- anywhere else -- a flat is what Raid/Party Frames edits, and a
    -- layout name on the Profiles or Testing page is a number with no
    -- question attached to it.
    cells[#cells + 1] = { justify = "RIGHT", text = function()
        local bf = BuzzardFrames
        local slot = bf.GetActiveSlot and bf:GetActiveSlot()
        local context = (bf.SLOT_LABELS and slot and bf.SLOT_LABELS[slot])
                        or slot or "?"
        -- The Ace panel's own two colors, so a reader moving between the
        -- panels reads the same line: its light blue for the instance type,
        -- its green for the resolved layout. The LABELS stay in the strip's
        -- own text color -- coloring both halves of a pair leaves nothing
        -- for the color to distinguish.
        local out = "Instance Type: |cff87ceeb" .. tostring(context) .. "|r"

        local route = app.GetRoute and app:GetRoute()
        if route and route[1] == "raidPartyFrames" then
            local lp = bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts or {}
            local fl = lp.flatLayouts or {}
            local id = slot and bf.ResolveActiveFlat and bf:ResolveActiveFlat(slot)
            local name = (id and id ~= "none" and fl[id] and fl[id].name)
                         or "\226\128\148"   -- em dash: resolved to nothing
            out = out .. "   |   Active Layout: |cff76CC4B" .. name .. "|r"
        end
        return out
    end }
    local t = BuzzardFrames.db.global.panelTesting or {}
    app:SetStatusBar{
        height = t.statusHeight or 22,
        span   = t.statusSpan or "body",
        style  = t.statusStyle or "plain",
        cells  = cells,
    }
    -- Declaring a strip shows it; the setting decides whether it stays.
    if t.statusShown == false then app:SetStatusBarShown(false) end
end

function BuzzardFramesOptions:SetPanelLayout(app, which)
    -- An earlier version of this spike called the top-strip layout "bar".
    -- A stored value naming a layout that no longer exists would silently
    -- fall back to the tree while the dropdown showed nothing selected.
    if which == "bar" then which = "strip" end
    BuzzardFrames.db.global.panelLayout = which
    local t = BuzzardFrames.db.global.panelTesting or {}
    app:SetChrome(ChromeFor(which, t.navStyle or "rounded"))
    -- The strip's contents depend on the layout, so it is re-declared with
    -- it -- gaining the footer's actions when the rail goes and losing them
    -- again when it comes back.
    self:ApplyPanelStatusBar(app)
    app:RefreshFooter()
end

-- A section's subtabs as route children.
--
-- Built from the ONE list each page file publishes rather than restated
-- here: those ids are the subtab ids in BF.SECTION_SUBTABS, which is what
-- the per-Layout toggles are keyed on, so a second copy of them here is a
-- second thing to keep in step with a third.
--
-- `method` is the page builder's NAME rather than the function, because
-- the page files load after this one: the name is resolved when the route
-- is opened, by which point every file is in.
--
-- Every page is a FUNCTION, and that is load-bearing rather than a
-- micro-optimization. It defers the build until the subtab is first
-- opened, and -- more importantly -- it is the only shape `Invalidate`
-- can re-run: several of these pages rebuild their own structure (a
-- per-Layout toggle flipping, a Modifying switch changing which flat's
-- shape is on screen, the Aura Text mode switch) and a page declared as
-- a table would sit there stale.
--
-- The builder is called with (id, title). A builder that takes only the
-- id ignores the second argument, so one helper serves both shapes.
--
-- A subtab may declare `when`: a predicate asked HERE, at route-build
-- time, and a false answer emits no route at all -- the tab is gone, the
-- way the Ace dialog's `hidden` took a tab off the strip. Aura Cooldown
-- Text is the case: its mode switch decides whether the unified Duration
-- Text tab or the three per-type tabs exist. Whatever flips such a
-- setting has to rebuild the routes, or the strip keeps the tabs the last
-- build gave it.
function BuzzardFramesOptions:SubtabRoutes(list, method)
    local out = {}
    for _, st in ipairs(list or {}) do
        if (not st.when) or st.when() then
            out[#out + 1] = {
                id = st.id, title = st.title,
                page = function() return self[method](self, st.id, st.title) end,
            }
        end
    end
    return out
end

-- The two section keys that mean "an aura surface": the Raid/Party
-- sections' own string and the Custom Frame Groups twin. Crossing out of
-- this set is what clears the container preview -- see the section
-- observer in Open().
local AURA_FAMILY = { auras = true, customFrameAuras = true }

-- A section key on every child, taken from the child's own id.
--
-- The Preview section is the one place where the section the preview
-- engine compares against is per-SUBTAB rather than per-section: the Ace
-- panel put a tracker on each of Preview, Preview Units, Preview Auras
-- and Experimental Options, and the engine's allowlist names them
-- individually. The subtab list those routes come from is published by
-- the page file, and a `sectionKey` there would be a fact about the
-- preview engine stored in a list of titles -- so it is stamped here,
-- where the route is built and where the rest of the keys are declared.
local function KeyBySubtabId(nodes)
    for _, n in ipairs(nodes or {}) do n.sectionKey = n.id end
    return nodes
end

-- One child's key, overriding the section's own.
--
-- Borders is the other exception: its Debuff Highlight subtab stamps
-- `dispelDebuffBorder`, which is what makes the dummy-aura preview draw
-- the border-only view on that subtab and the normal one on its four
-- siblings.
local function KeyOneChild(nodes, id, key)
    for _, n in ipairs(nodes or {}) do
        if n.id == id then n.sectionKey = key end
    end
    return nodes
end

-- The Icons subtabs, the first section to be built this way.
function BuzzardFramesOptions:IconsRoutes()
    return self:SubtabRoutes(self.ICONS_SUBTABS, "IconsPage")
end

-- Layouts is the one section whose children are not all pages: the two
-- plain subtabs, and then the Role/Spec Layouts COLLECTION node, which
-- carries its own member machinery and is spliced on the end.
function BuzzardFramesOptions:LayoutsRoutes()
    local out = self:SubtabRoutes(self.LAYOUTS_SUBTABS, "LayoutsPage")
    if self.LayoutsRoleSpecRoute then
        out[#out + 1] = self:LayoutsRoleSpecRoute()
    end
    return out
end

-- ── The two aura sections ──────────────────────────────────────
--
-- These are the only sections whose children are not one page file's
-- list. The Ace builder emitted two PREDEFINED subtabs per section and
-- then grew the rest at runtime -- the Buff Preset/Filter and Buff List
-- surfaces, and a subtab per custom container -- from a different part
-- of the file, which is why the migration split them across two page
-- files and why the order has to be reassembled here.
--
-- The order below is the Ace strip's own, by the `order` values it gave
-- them: Buffs (1), Buff Preset/Filter (1.25), Buff List (1.5), Big
-- Defensive (2), then the containers (10 + index, i.e. always last).
-- Reading it in that order is the point -- a reader who knows the Ace
-- panel should find the same tabs in the same places.
--
-- Every splice is guarded on the builder existing, so a partially
-- vendored copy degrades to "that surface is missing" rather than to a
-- Lua error while the tree is being built.
local function Splice(out, node)
    if node then out[#out + 1] = node end
    return out
end

-- The containers are spliced in as SIBLINGS, one route per container,
-- not as a child collection.
--
-- That is the Ace strip's own shape -- its container subtabs sat at
-- order 10 + index alongside Buffs and Big Defensive -- and it is also
-- the only shape the library can draw: a collection declaring its own
-- `tabs` navigator nested under a section that has one puts two
-- contextual strips in the page header, and MountContextual anchors both
-- at the same place, so the inner one lands on top of the outer.
local function SpliceAll(out, list)
    for _, node in ipairs(list or {}) do out[#out + 1] = node end
    return out
end

function BuzzardFramesOptions:AurasBuffsRoutes()
    local subs = self:SubtabRoutes(self.BUFFS_SUBTABS, "BuffsPage")
    local out  = {}
    -- subs[1] is tabBuffs, subs[2] is tabBigDef.
    Splice(out, subs[1])
    Splice(out, self.AssignedSpellsPage and self:AssignedSpellsPage() or nil)
    Splice(out, self.SingleBuffsPage   and self:SingleBuffsPage()   or nil)
    Splice(out, subs[2])
    if self.BuffContainerRoutes then
        SpliceAll(out, self:BuffContainerRoutes())
    end
    return out
end

function BuzzardFramesOptions:AurasDebuffsRoutes()
    local out = self:SubtabRoutes(self.DEBUFFS_SUBTABS, "DebuffsPage")
    if self.DebuffContainerRoutes then
        SpliceAll(out, self:DebuffContainerRoutes())
    end
    return out
end

-- ── The route tree ─────────────────────────────────────────────
--
-- A METHOD rather than a literal inside Open, because it is re-run. The
-- Unit Frames section drops its children while unit frames are off --
-- the Ace `syncPTFTabs()` behavior -- so the tree is a function of the
-- profile and has to be rebuildable when the profile changes.
--
-- Everything else about it is unchanged: the ids are the Ace options'
-- own args keys and the titles are its own names.
--
-- The tree is a local rather than a bare return because it is handed to
-- BindRPRoutes on the way out: every page closure and every collection
-- member template in it is bound to NO scope, so a Custom Frame Groups
-- binding left behind by the last thing to render -- or by the search
-- index, which builds every route's page in one sweep -- can never leak
-- into a Raid/Party page. The Custom Frame Groups branch marks itself as
-- already bound, so that pass steps over it.
function BuzzardFramesOptions:BuildRoutes(app)
    local tree = {
        { id = "raidPartyFrames", title = "Raid/Party Frames",
            -- The Ace section root wrote "root", so the preview engine
            -- compares against that string and nothing else here.
            sectionKey = "root",
            -- A parent is a DESTINATION only if it has a page of its own:
            -- without one the library descends to the first child, which is
            -- right for a pure branch and wrong here, because the Ace dialog
            -- lets you select this section. The page is the migrated one --
            -- the enable toggles and the three Hide Blizzard rows that sit
            -- at the Ace section's root.
            page = function() return self:RaidPartyGeneralPage() end,
            -- Its children are CONDITIONAL, the same way Unit Frames'
            -- are: the Ace panel stamped raidPartyHidden() onto all
            -- fourteen sub-tabs, which took the whole strip away while
            -- both the Party and the Raid switch were off, so they are
            -- absent here too. The root page stays either way -- it
            -- carries the two switches that bring them back. The two
            -- setters call RebuildRoutes, which re-runs this
            -- declaration.
            children = self:RaidPartyRoutes(app) },
        -- The section root is a real page -- the description and the
        -- customFramesEnabled master switch, which the Ace section carries
        -- at its own root.
        --
        -- Its children are CONDITIONAL, which is the Ace tree's own
        -- behavior rather than an approximation of it: every Custom Frame
        -- Groups child hid itself while the master switch was off, so they
        -- are absent here too. The switch's own setter calls RebuildRoutes,
        -- which re-runs this declaration.
        --
        -- Every one of those children is a RAID/PARTY page builder rendered
        -- against the selected group's own flat -- see
        -- Pages_CustomFrameSections.lua. There is no second copy of any
        -- field declaration anywhere in the section.
        { id = "customFrames", title = "Custom Frame Groups",
            -- The section root and the Custom Frame Groups collection
            -- beneath it are not one of the ten configuration sections, so
            -- they get their own key rather than inheriting a stale one:
            -- the ten sections declare theirs in
            -- Pages_CustomFrameSections.lua, from the same map the Ace
            -- trackers were built from.
            sectionKey = "customFrames",
            page = function() return self:CustomFramesRootPage() end,
            children = self:CustomFramesRoutes() },
        -- The section root is a real page -- the ptfEnabled master
        -- switch and the Hide Blizzard rows, which the Ace section
        -- carries at its own root and shows whatever the switch says.
        --
        -- Its children are CONDITIONAL, which is the Ace
        -- `syncPTFTabs()` behavior rather than an approximation of
        -- it: that function nilled all eight sub-tabs out of the args
        -- table while unit frames were off, so they are absent here
        -- too. The switch's own setter calls RebuildRoutes, which
        -- re-runs this declaration.
        { id = "unitFrames", title = "Unit Frames", sectionKey = "unitFrames",
            page = function() return self:UnitFramesRootPage() end,
            children = self:UnitFramesRoutes() },
        -- The Ace section has settings at its own root (the intro and
        -- incomingCastsEnabled), so the parent is a destination. Its
        -- two displays are rail children rather than tabs: each is
        -- ITSELF a tab strip (Options / Position / Display), and that
        -- inner strip is the contextual one.
        { id = "incomingCasts", title = "Incoming Casts", sectionKey = "incomingCasts",
            page = function() return self:IncomingCastsPage() end,
            children = self:IncomingCastsRoutes() },
        -- Its five pages (General, Profile Management, Themes, Export,
        -- Import) are RAIL children -- no navigator of its own, so the
        -- rail lists them under the section and no strip repeats them:
        -- the owner's call, over the Ace tab strip. No page of its own:
        -- selecting "Profiles" descends to General. The Themes page is
        -- CONDITIONAL (experimental options), so the list is a function of
        -- the profile -- see ProfilesRoutes.
        { id = "profiles", title = "Profiles", sectionKey = "profiles",
          children = self:ProfilesRoutes() },
        { id = "globalStyles", title = "Global Styles",
            -- No page of its own (the owner's call, over the Ace dialog's
            -- selectable-but-empty section root): selecting "Global Styles"
            -- descends to Colors, and the rail lists no row for the section
            -- itself. Its children carry the Ace Global Styles twins of the
            -- Raid/Party keys, and each declares the section key the Ace
            -- page's tracker wrote; this one names its own so the dummy
            -- auras from a previous section never stay painted here.
            sectionKey = "globalStyles",
            children = self:GlobalStylesRoutes() },

    }
    -- The panel's own knobs, in Pages_Testing.lua. LAST in the tree, and
    -- only while `/bf dev panelconfig` is on (BF:IsDevPanelConfigEnabled;
    -- the command rebuilds the tree). A real page rather than footer
    -- chrome: the layout switch lives here because the footer lives in
    -- the RAIL and one of the layouts hides the rail, and a page is
    -- reachable from every navigator. Titled "Panel Config" -- what it is
    -- to the reader; the id and section key stay "testing" so saved
    -- routes and observers hold.
    if BuzzardFrames.IsDevPanelConfigEnabled and BuzzardFrames:IsDevPanelConfigEnabled() then
        tree[#tree + 1] = { id = "testing", title = "Panel Config", sectionKey = "testing",
                            page = function() return self:TestingPage(app) end }
    end
    -- Bind every Raid/Party page to no scope. See the note above.
    if self.BindRPRoutes then self:BindRPRoutes(tree) end
    return tree
end

-- Re-declare the tree and hand it to the app. Called by the ptfEnabled
-- switch, and by anything else that changes which SECTIONS exist rather
-- than what a page shows -- Invalidate is the tool for the latter.
--
-- SetRoutes re-points a route that no longer exists at the first section,
-- so turning unit frames off from a page that is about to vanish lands
-- somewhere real rather than nowhere.
function BuzzardFramesOptions:RebuildRoutes(app)
    if not app then return end
    app:SetRoutes(self:BuildRoutes(app))
end

-- The Unit Frames children, or none.
--
-- The Ace `syncPTFTabs()` nils all eight out of the args table while
-- ptfEnabled is off; an empty list here is the same thing. The section
-- keeps its own root page either way, which is what the reader needs --
-- that page carries the switch that brings the rest back.
function BuzzardFramesOptions:UnitFramesRoutes()
    if self.UnitFramesOff and self.UnitFramesOff() then return {} end
    local out = {
        { id = "globalTab", title = "Global", navigator = "tabs",
          children = self:UnitFramesGlobalRoutes() },
        { id = "playerTab", title = "Player Frame", navigator = "tabs",
          children = self:SubtabRoutes(self.UNITFRAMES_PLAYER_SUBTABS,
                                       "UnitFramesPlayerPage") },
        { id = "targetTab", title = "Target Frame", navigator = "tabs",
          children = self:SubtabRoutes(self.UNITFRAMES_TARGET_SUBTABS,
                                       "UnitFramesTargetPage") },
    }
    -- The five per-frame tabs: one list, one builder.
    for _, spec in ipairs(self.UNITFRAMES_FRAME_TABS or {}) do
        out[#out + 1] = {
            id = spec.id, title = spec.title, navigator = "tabs",
            children = self:UnitFramesFrameRoutes(spec.id),
        }
    end
    -- Unit Frame Layouts last, as in the Ace strip -- and in the same
    -- shape the raid section's Layouts tab has (LayoutsRoutes): one plain
    -- subtab, Manage Layouts, and then the override
    -- COLLECTION. The collection is a tree group, so role and spec
    -- overrides are one list of routed entries on its own page rather
    -- than a branch with a second strip of its own.
    local kids = self:SubtabRoutes(self.UFLAYOUTS_SUBTABS, "UFLayoutsPage")
    if self.UFLayoutsRoleSpecRoute then
        kids[#kids + 1] = self:UFLayoutsRoleSpecRoute()
    end
    out[#out + 1] = {
        id = "ufLayoutsTab", title = "Unit Frame Layouts",
        navigator = "tabs", children = kids,
    }
    return out
end

-- The Profiles pages, in the Ace strip's order: General, Profile
-- Management, Themes, Export, Import -- drawn down the rail here. The list is published by
-- Pages_Profiles.lua, and its Themes entry carries a `when` predicate --
-- the Ace group hid itself while experimental options were off, so the
-- route is absent then too. The experimental switch (Pages_Preview.lua)
-- calls RebuildRoutes, which re-runs this.
function BuzzardFramesOptions:ProfilesRoutes()
    return self:SubtabRoutes(self.PROFILES_SUBTABS, "ProfilesPage")
end

-- The Global Styles children, in the Ace tree's order. Every node carries
-- the section key its Ace page's tracker wrote (the Health & Power Bars
-- page wrote "colors", as its Raid/Party twin does), and the three tabbed
-- sections carry their subtabs as routes under a `tabs` navigator, as
-- every other tabbed section does. The subtab lists are published by the
-- page files.
function BuzzardFramesOptions:GlobalStylesRoutes()
    return {
        { id = "colors",          title = "Colors",              sectionKey = "colors",
          page = function() return self:ColorsPage() end },
        { id = "healthBars",      title = "Health & Power Bars", sectionKey = "colors",
          page = function() return self:GlobalStylesHealthPage() end },
        { id = "borders",         title = "Borders",             sectionKey = "borders",
          page = function() return self:GlobalStylesBordersPage() end },
        { id = "absorbsHealPred", title = "Absorbs & Heal Prediction", sectionKey = "absorbs",
          navigator = "tabs",
          children = self:SubtabRoutes(self.GS_ABSORBS_SUBTABS, "GlobalStylesAbsorbsPage") },
        { id = "gsIcons",         title = "Icons",               sectionKey = "icons",
          page = function() return self:GlobalStylesIconsPage() end },
        { id = "gsText",          title = "Text",                sectionKey = "text",
          navigator = "tabs",
          children = self:SubtabRoutes(self.GS_TEXT_SUBTABS, "GlobalStylesTextPage") },
        { id = "gsAuras",         title = "Auras",               sectionKey = "auras",
          navigator = "tabs",
          children = self:SubtabRoutes(self.GS_AURAS_SUBTABS, "GlobalStylesAurasPage") },
    }
end

-- The Raid/Party Frames children, or none.
--
-- The Ace `raidPartyHidden()` stamps a hidden() onto every one of the
-- fourteen sub-tabs, so the strip disappears while BOTH the Party and
-- the Raid switch are off; an empty list here is the same thing. The
-- predicate is `== false` on both keys, so an absent key means ON --
-- RaidPartyOff (Pages_RaidPartyGeneral.lua) is the one place that is
-- written down. Takes `app` because the Frame Configuration subtab's
-- page does.
function BuzzardFramesOptions:RaidPartyRoutes(app)
    if self.RaidPartyOff and self.RaidPartyOff() then return {} end
    return {
        -- Size & Position and Sorting are two subtabs of one
        -- section rather than two top-level entries: they configure
        -- the same frames, and the rail said so twice. No page of
        -- its own, so selecting "Frame Configuration" descends to
        -- Size & Position, the same rule the aura sections follow.
        -- Every section node below carries the `sectionKey` the preview
        -- engine compares against -- the string the Ace panel's invisible
        -- _sectionTracker widgets wrote into BF._currentSection on every
        -- render. Declaring it on the node says the same thing once, on
        -- entry, and it is INHERITED, so a subtab needs one only where it
        -- differs from its section (Borders' Debuff Highlight, and the
        -- four Preview subtabs).
        { id = "frames",        title = "Frame Config", navigator = "tabs",
          sectionKey = "frames",
          children = {
            -- Takes `app`: the page registers a route observer with it,
            -- which is what rebuilds the page when the Modifying flat was
            -- changed to one of the other TYPE from another section's
            -- strip. A party flat and a raid flat do not carry the same
            -- cards, so that is a structural change, not a value one.
            { id = "sizePos", title = "Size & Position",
              page = function() return self:FramesPage(app) end },
            { id = "sorting", title = "Sorting & Grow Direction",
              page = function() return self:SortingPage() end },
        }},
        -- No page of their own: a parent without one descends to
        -- its first child, which is what selecting "Buffs" should
        -- do -- the Buffs subtab is a destination, the section is
        -- not. See AurasBuffsRoutes for why the children come from
        -- two page files rather than one published list.
        { id = "aurasBuffs",    title = "Buffs", navigator = "tabs",
          sectionKey = "auras",
          children = self:AurasBuffsRoutes() },
        { id = "aurasDebuffs",  title = "Debuffs", navigator = "tabs",
          sectionKey = "auras",
          children = self:AurasDebuffsRoutes() },
        { id = "auraText",      title = "Aura Cooldown Text", navigator = "tabs",
          sectionKey = "auraText",
          children = self:SubtabRoutes(self.AURATEXT_SUBTABS, "AuraTextPage") },
        { id = "text",          title = "Text", navigator = "tabs",
          sectionKey = "text",
          children = self:SubtabRoutes(self.TEXT_SUBTABS, "TextPage") },
        -- "colors" rather than "healthPower", and it is not a typo: the
        -- engine's allowlist is keyed on the Ace section's own tracker
        -- string, and the Health & Power Bars section wrote "colors".
        { id = "healthPower",   title = "Health & Power Bars", navigator = "tabs",
          sectionKey = "colors",
          children = self:SubtabRoutes(self.HEALTHPOWER_SUBTABS, "HealthPowerPage") },
        { id = "borders",       title = "Borders & Highlights", navigator = "tabs",
          sectionKey = "borders",
          children = KeyOneChild(self:SubtabRoutes(self.BORDERS_SUBTABS, "BordersPage"),
                                 "debuff", "dispelDebuffBorder") },
        { id = "absorbs",       title = "Absorbs & Heal Prediction", navigator = "tabs",
          sectionKey = "absorbs",
          children = self:SubtabRoutes(self.ABSORBS_SUBTABS, "AbsorbsPage") },
        -- The FIRST section with subtabs, and they are ROUTES:
        -- six children and a `tabs` navigator, so each subtab is
        -- deep-linkable, observable and searchable on its own, and
        -- keeps its own scroll position. The strip is drawn in the
        -- page header; the rail stops here, because this node says
        -- nothing about `railChildren` and the app's default (set
        -- from the Testing page) decides.
        { id = "icons",         title = "Icons", navigator = "tabs",
          sectionKey = "icons",
          -- No page of its own: a parent without one descends to
          -- its first child, which is what selecting "Icons"
          -- should do -- Role Icons is a destination, "Icons" is
          -- not.
          children = self:IconsRoutes() },
        { id = "castBar",       title = "Cast Bars", navigator = "tabs",
          sectionKey = "castBar",
          children = self:SubtabRoutes(self.CASTBAR_SUBTABS, "CastBarPage") },
        { id = "tooltips",      title = "Tooltips",
          sectionKey = "tooltips",
          -- The first REAL page: the panel equivalent of
          -- Options_Tooltips.lua. A function, so the page is
          -- built when it is first opened rather than at
          -- declaration time -- its fields close over
          -- BuzzardFrames state that is not settled yet here.
          page = function() return self:TooltipsPage() end },
        -- Two plain subtabs and then a collection: see LayoutsRoutes.
        { id = "roleSpecLayouts", title = "Layouts", navigator = "tabs",
          sectionKey = "roleSpecLayouts",
          children = self:LayoutsRoutes() },
        -- No key on the section itself: each of its four subtabs is its
        -- own section as far as the preview engine is concerned, and the
        -- node is never a destination -- a parent without a page descends
        -- to its first child.
        { id = "preview",       title = "Preview", navigator = "tabs",
          children = KeyBySubtabId(self:SubtabRoutes(self.PREVIEW_SUBTABS, "PreviewPage")) },
    }
end

-- The entry point. BuzzardFrames calls this once the addon is loaded.
function BuzzardFramesOptions:Open()
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    if not Panel then
        print("|cff11ace9Buzzard Frames:|r the embedded BuzzardPanel library "
            .. "did not load. Re-vendor it with "
            .. "Tools\\vendor_buzzardpanel.py and check the .toc.")
        return
    end

    local app = Panel:GetApp("BuzzardFrames")
    if not app then
        app = Panel:NewApp("BuzzardFrames", {
            title = "Buzzard Frames",
            icon  = "Interface\\AddOns\\BuzzardFrames\\Media\\buzzardRes",
            -- A FUNCTION, so the .toc is read at first paint rather than
            -- while this file is loading: this addon is load-on-demand and
            -- the version wanted is BuzzardFrames', not its own.
            version = function()
                local get = C_AddOns and C_AddOns.GetAddOnMetadata
                local v = get and get("BuzzardFrames", "Version")
                return v and tostring(v) or nil
            end,
            -- Buzzard's own azure, so the prototype reads as ours from the
            -- first frame rather than wearing the library's default.
            tokens = {
                accent    = { 0.06, 0.63, 0.86, 1.00 },   -- #10a0dc, half a step darker than #11ace9
                accentDim = { 0.06, 0.63, 0.86, 0.30 },
                -- The panel's own face. Stated as a token so the first
                -- frame is already drawn in it rather than flicking from
                -- the game font a moment later.
                font      = PanelFont(),
            },
            -- The library owns no SavedVariables. It stores geometry in the
            -- table this returns, under panelX/panelY/panelW/panelH -- keys
            -- distinct from the Ace panel's optionsPanelWidth/Height, so both
            -- panels remember their own size and position independently.
            persist = function() return BuzzardFrames.db and BuzzardFrames.db.global end,
            -- ── Every write sweeps the previews ──────────────────
            --
            -- This is what the Ace panel got for free and this one did
            -- not. Nearly every Ace setter ended with
            -- AceConfigRegistry:NotifyChange, which rebuilds the panel,
            -- and SetupOptionsPanel sweeps the preview frames on every
            -- rebuild -- so ANY setting, whatever it was, repainted the
            -- previews from the profile a moment later.
            --
            -- Here each field carries its own targeted refresh instead,
            -- which is faster and exactly right when the field's author
            -- picked the right one -- and silently wrong when they did
            -- not: Test Aggro Highlight redrawn by a highlight refresh
            -- that does not repaint aggro, a texture whose preview only
            -- the layout pass applies, and so on. One field at a time is
            -- one bug at a time.
            --
            -- So the panel keeps the targeted refreshes AND ends every
            -- write with the sweep, which is the Ace behavior. Debounced,
            -- because this fires on every step of a slider drag, and
            -- gated on combat and on the panel being up.
            onWrite = function(app)
                if InCombatLockdown() then return end
                app:ScheduleEffect({ tier = "debounce", key = "bfoPreviewSweep" },
                    function()
                        local bf = BuzzardFrames
                        if InCombatLockdown() then return end
                        if not (app.frame and app.frame:IsShown()) then return end
                        if not bf then return end
                        if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
                        -- The aggro highlight is NOT part of the sweep's
                        -- dummy-data pass (ApplyAllPreviewDummyData lists
                        -- twelve Apply* functions and ApplyPreviewAggro is
                        -- not one of them), so the sweep alone would leave
                        -- a Test Aggro Highlight showing the style it was
                        -- last painted with -- which is the very thing
                        -- being reported. Asked for by name, right after.
                        if bf.RefreshPreviewAggro then bf:RefreshPreviewAggro() end
                    end)
            end,
            -- ── The preview frames ──────────────────────────────
            --
            -- The Ace dialog ran these three from its own show, hide and
            -- resize hooks; the library gives the same three seams, so the
            -- preview system is wired to the panel rather than to either
            -- panel's internals. NewApp runs once per session and these
            -- close over nothing -- BuzzardFrames is read when the callback
            -- fires, which is the only moment it is certainly there.
            --
            -- On open the library fires the section observer first, so
            -- BF._currentSection already names the page being restored by
            -- the time the sweep below decides what to draw on it.
            onOpen = function(app)
                local bf = BuzzardFrames
                -- Claim the previews for this panel BEFORE the sweep below:
                -- there is one preview engine and one set of frames, and the
                -- sweep parents them to whichever frame the engine currently
                -- calls the host. Opening this panel is the reader saying they
                -- want to work here, so they come over even if the Ace panel is
                -- also on screen.
                if bf.SetPreviewHost then bf:SetPreviewHost(app:EnsureFrame()) end
                -- The pre-open block the Ace panel runs: the Modifying flat
                -- reset, the raid-profile cache and the aura size cache.
                if bf.PrepareOptionsSession then bf:PrepareOptionsSession() end
                if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
                -- The boss preview follows its saved switch the way the
                -- raid previews follow showPreview: on while the panel is.
                if bf.ResumeBossPreview then bf:ResumeBossPreview() end
                -- AND AGAIN ON THE NEXT FRAME.
                --
                -- The first pass runs while the preview frames are being
                -- BUILT, and an indicator is laid out only once its widget
                -- exists (BF:ShouldLayoutIndicator) -- so the pass that
                -- creates the widgets cannot also paint all of them. The
                -- Ace panel never showed that because SetupOptionsPanel
                -- sweeps on every rebuild and opening it rebuilds more
                -- than once. This is that second rebuild, said once: route
                -- observers do not fire on open, so the sweep on
                -- navigation below cannot cover this moment.
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        local b = BuzzardFrames
                        if b and b.RefreshPreviewFrames and app:IsShown() then
                            b:RefreshPreviewFrames()
                        end
                    end)
                end
            end,
            -- Fired from the frame's OnHide, so ESC and the title-bar X are
            -- the same thing here.
            onClose = function()
                local bf = BuzzardFrames
                if bf.HidePreviewFrames then bf:HidePreviewFrames() end
                -- The boss preview (Boss Frames > Preview) lives on the real
                -- boss frames, not on this panel, so it is switched off here
                -- rather than hidden with the previews above.
                if bf.StopBossPreview then bf:StopBossPreview() end
                -- Drop the claim: the previews were parented and anchored to
                -- THIS frame, which is now hidden.
                if bf.SetPreviewHost then bf:SetPreviewHost(nil) end
            end,
            -- OnSizeChanged fires on every frame of a drag, so the
            -- reposition is debounced: the previews are anchored to the
            -- panel and only their final resting place matters.
            onResize = function(app)
                app:ScheduleEffect({ tier = "debounce", key = "bfPreviewReposition" },
                    function()
                        if BuzzardFrames.RepositionPreviewFrames then
                            BuzzardFrames:RepositionPreviewFrames()
                        end
                    end)
            end,
        })
    end
    -- A group with no card and no header: the container disappears and
    -- its fields sit straight on the page. For a standalone control that
    -- is meta-configuration rather than a setting -- the per-layout switch
    -- at the top of a section page -- which would read as a one-item
    -- section if it wore a card.
    if not app._bfBarePreset then
        app._bfBarePreset = true
        app:DefineGroup("bare", {
            headerBg = { 0, 0, 0, 0 },
            bodyBg   = { 0, 0, 0, 0 },
            border   = { 0, 0, 0, 0 },
            padding  = 0,
            -- padBottom too: without it the bare group inherits the default
            -- preset's 7px bottom pad, so a chromeless group reserved space
            -- below its content on top of the inter-group gap. A group with
            -- no card should end exactly at its content.
            padBottom = 0,
            justify  = "start",
        })
        -- The section groups. `justify = "start"` is the whole difference:
        -- a row keeps every field at its natural width and leaves the rest
        -- of the row empty, rather than growing the stretchy controls to
        -- fill it -- which is how the Ace panel's rows read, and what a
        -- dropdown two hundred pixels wide is FOR.
        app:DefineGroup("form", { justify = "start", wrapOn = "pref" })
    end

    -- The REAL tree, section for section: the ids are the Ace options'
    -- own args keys and the titles are its own names, so the shell is
    -- judged against the actual information architecture -- and P0.4's
    -- migration becomes a lookup rather than a translation table.
    --
    -- Only TREE nodes are routes. A section whose children are a tab strip
    -- (Buffs and its Buff List, Profiles and its five tabs) keeps them on
    -- the page, because that is where the Ace dialog puts them too. The
    -- hidden `customAuras` group is absent for the same reason it is absent
    -- there: it never appears. No option file is touched until P0.4.
    -- Declared on EVERY open rather than once. The tree is a function of
    -- the profile -- Unit Frames drops its children while it is off -- so
    -- a one-time declaration would be right only until the reader flipped
    -- that switch in a previous session.
    self:RebuildRoutes(app)

    if not app._bfRoutesSet then
        app._bfRoutesSet = true

        -- ── The section observer ───────────────────────────────
        --
        -- The Ace page carried an invisible `description` widget per
        -- section whose `name` callback fired on every render and stamped
        -- BF._currentSection -- "auras", "customFrameText",
        -- "dispelDebuffBorder" and the rest -- which is what tells the
        -- dummy-aura preview which context it is drawing for. A render
        -- hook hidden in a widget has no panel equivalent and needs none:
        -- the route tree DECLARES the string (`sectionKey`, inherited down
        -- the branch), the library resolves it for the active route, and
        -- this one observer does the work every one of those widgets did.
        --
        -- One observer rather than one per section, because the interesting
        -- events are transitions, not arrivals: the library fires this only
        -- when the resolved key actually changes, and once unconditionally
        -- on open -- the route observers get the same arrival on open, a
        -- moment after this, so the session's first page arrives stamped
        -- coarse then fine, as a navigated one does.
        app:RegisterSectionObserver(function(newKey, oldKey)
            local bf = BuzzardFrames
            if bf._currentSection ~= newKey then bf._currentSection = newKey end
            -- Leaving Buffs or Debuffs -- Raid/Party or Custom Frame
            -- Groups, which is why both spellings are in the set. The Ace
            -- panel did this between SIBLING aura subtabs, so a stale
            -- container index or Buff List sentinel could survive onto a
            -- Text page and keep that preview alive there; done at the
            -- family boundary it happens exactly once, and moving between
            -- aura subtabs is still the aura pages' own business.
            if oldKey and AURA_FAMILY[oldKey] and not AURA_FAMILY[newKey] then
                bf._currentContainerIndex = nil
                bf._currentAurasSubcat    = nil
                if bf.ClearAuraPreview then bf:ClearAuraPreview() end
            end
            -- The stamps above are unconditional and the repaint is not:
            -- a section entered in combat is already recorded correctly
            -- for the first refresh after it ends.
            if not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
                bf:RefreshPreviewDummyAuras()
            end
        end)

        -- The Custom Frame Groups collection's member routes are keyed by
        -- the group's cfgFlatID, so opening one IS choosing a group --
        -- and the selection is panel-wide, so the section pages open on
        -- the group whose tab was last read rather than on the first one.
        -- `true` for everyChange: moving between two member tabs never
        -- leaves the pattern.
        app:RegisterRouteObserver("customFrames/groups", function(isActive, routeKey)
            if not isActive then return end
            local key = routeKey and routeKey:match("^customFrames/groups/([^/]+)")
            if key then self:CFGSelectByFlatID(key) end
        end, true)

        -- ── Undo does not cross the Raid/Party ↔ Custom Frame Groups
        -- boundary ──
        --
        -- The right-click menu's undo is keyed by a field's `bind` or
        -- `id`, and those strings are IDENTICAL in the two contexts: the
        -- Text page's nameFont is "nameFont" whichever flat it is editing.
        -- Without this, editing nameFont on Raid/Party and then
        -- right-clicking Undo on Custom Frame Groups > Text > Names would
        -- write the raid layout's previous value into the group's flat.
        -- Namespacing the key is not an option -- the key IS the path into
        -- the storage -- so the record is dropped when the reader crosses
        -- the boundary, which is the honest answer: there is nothing to
        -- undo on a page you have not yet changed.
        -- "*" is the library's match-everything pattern, and everyChange
        -- is what makes it fire on each navigation rather than only when
        -- the match itself flips (it never does).
        --
        -- SEEDED FROM THE LIVE ROUTE, not from nil. Observers fire only
        -- from Navigate; SetRoutes settles the route without firing one, so
        -- a flag starting at nil is still nil on the session's first
        -- navigation -- and a `wasCFG ~= nil` guard would then suppress the
        -- wipe on exactly the first Raid/Party -> Custom Frame Groups
        -- crossing, which is the one this observer exists for.
        local wasCFG = (table.concat(app:GetRoute() or {}, "/"))
                       :match("^customFrames") ~= nil
        app:RegisterRouteObserver("*", function(_, routeKey)
            local isCFG = (routeKey or ""):match("^customFrames") ~= nil
            if isCFG ~= wasCFG then app.undo = nil end
            wasCFG = isCFG
        end, true)

        -- ── Navigating here claims the preview frames ──
        --
        -- Both panels can be open at once and there is only ONE preview
        -- engine, so the frames live on one panel at a time. Reading a page
        -- HERE is the reader saying they are working here, so every
        -- navigation pulls them over from the Ace panel; the Ace panel's own
        -- rebuild sweep pulls them back the same way.
        --
        -- THE SWEEP RUNS ON EVERY NAVIGATION, not only when the host
        -- changes.
        --
        -- Skipping it while the host was already this panel was an
        -- optimization, and it is the difference between this panel and the
        -- old dialog, which rebuilt on every navigation and swept the
        -- preview frames on every rebuild -- so over there the preview
        -- frames were re-laid-out and re-painted constantly, and any state
        -- that was not settled on one pass was settled by the next. Here
        -- they were painted once, on open, while the frames were still
        -- being built: an indicator is
        -- laid out only after its widget exists (BF:ShouldLayoutIndicator),
        -- so the pass that CREATES the widgets cannot also paint all of
        -- them. That is what showed the wrong absorb textures.
        --
        -- The cost is the cost the Ace panel paid for the same thing, and
        -- the previews being right is worth more than a sweep saved.
        --
        -- The section observer runs BEFORE route observers, so its
        -- RefreshPreviewDummyAuras can fire while the host is still the Ace
        -- frame. That is harmless: the full sweep below repaints the frames
        -- on their new host immediately afterwards.
        app:RegisterRouteObserver("*", function()
            local bf = BuzzardFrames
            if not (app.frame and app.frame:IsShown()) then return end
            if bf._previewHostFrame ~= app.frame and bf.SetPreviewHost then
                bf:SetPreviewHost(app.frame)
            end
            if not InCombatLockdown() and bf.RefreshPreviewFrames then
                bf:RefreshPreviewFrames()
            end
        end, true)
    end

    -- Applied on EVERY open, not only the first: the routes are declared
    -- once, but the layout is a stored setting and the app is created once
    -- per session, so a chrome set inside the one-time block would be right
    -- by accident rather than by construction.
    -- Everything the reader chose in a previous session, before the panel
    -- is shown -- applying it after would mean a visible flick from the
    -- shipped defaults to theirs on every open. SetPanelLayout is the last
    -- step inside it, because the footer and the strip are re-declared with
    -- the layout.
    self:ApplyPanelSettings(app)
    -- The face too: the token above is read once per session, and this is a
    -- stored setting like the others.
    app:SetPanelFont(PanelFont())
    -- The scale too (Panel Scale in the Addon Options menu): relative to
    -- the game's own UI scale, 1.00 = the size the rest of the UI draws
    -- at. The old whole-pixel choice is retired; a stored one is dropped
    -- so it cannot shadow the slider's value.
    if app.SetPanelScale then
        local g = BuzzardFrames.db and BuzzardFrames.db.global
        if g then g.panelPixelMultiple = nil end
        app:SetPanelScale((g and g.panelScale) or 1)
    end
    app:Toggle()
end

-- Published last, so a caller that sees this global sees a complete table.
_G.BuzzardFramesOptions = BuzzardFramesOptions
