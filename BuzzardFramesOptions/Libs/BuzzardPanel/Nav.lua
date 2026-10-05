-- ============================================================
-- BuzzardPanel: Nav.lua
-- Routes, selection, and the navigators that present them.
--
-- The central idea: ROUTES ARE DATA, NAVIGATORS ARE VIEWS. A route
-- tree says what pages exist and how they nest; it says nothing about
-- how they are reached. A navigator is bound to ONE LEVEL of that tree
-- and mounted into ONE REGION, and its only job is to show that level's
-- nodes and call app:Navigate. Swap "tree" for "buttonbar" and the same
-- routes render as a rail or a top strip, because neither the routes nor
-- the pages know which is in use.
--
-- Selection is a single observable. Two navigators bound to the same
-- level therefore cannot disagree: both are views over app.route.
-- ============================================================
local ADDON, ns = ...

ns.nav = {}

-- Is `key` the route `ancestor`, or somewhere inside it?
--
-- A route key is a "/"-separated path, so a plain prefix test is not the
-- same question: "a/b/w10" starts with "a/b/w1" without being anywhere
-- inside it. That is not hypothetical -- it is what made a new widget
-- light up the tab belonging to "First" -- so the separator is part of the
-- test, and the test lives in one place because this is exactly the kind
-- of thing that gets fixed in one caller and left wrong in another.
local function RouteWithin(key, ancestor)
    if key == ancestor then return true end
    return key:sub(1, #ancestor + 1) == ancestor .. "/"
end
ns.nav.RouteWithin = RouteWithin

-- ── Route tree ─────────────────────────────────────────────────

-- Flatten the declared tree into a lookup: "a/b/c" -> node, and record
-- each node's parent path and depth. Done once per SetRoutes, so
-- navigation is a table lookup rather than a walk.
local function IndexRoutes(app, nodes, parentPath, depth, out)
    for i, node in ipairs(nodes) do
        assert(node.id, "SetRoutes: every node needs an id")
        local path = {}
        for j = 1, #parentPath do path[j] = parentPath[j] end
        path[#path + 1] = node.id

        local key = table.concat(path, "/")
        assert(not out[key], "SetRoutes: duplicate route '" .. key .. "'")
        out[key] = {
            node   = node,
            path   = path,
            key    = key,
            depth  = depth,
            index  = i,
            parent = (#parentPath > 0) and table.concat(parentPath, "/") or nil,
        }
        -- A COLLECTION supplies its children instead of declaring them: it
        -- reads its source, applies its filter, and returns one node per
        -- member. That happens here, at index time, so member routes exist
        -- before anything tries to navigate to one -- which is the ordering
        -- the whole add/remove path depends on.
        local kids = node.children
        if node.node == "collection" and ns.collections then
            kids = ns.collections.ExpandChildren(app, node)
        end
        if kids then
            IndexRoutes(app, kids, path, depth + 1, out)
        end
        -- Remembered so the navigators do not have to ask a second time.
        out[key].children = kids
    end
end

-- Rebuild the route index from the declared tree.
--
-- Separate from SetRoutes because a collection's membership changes
-- without the app re-declaring anything: Invalidate calls this, the member
-- routes come back matching the new list, and only then does selection
-- resolve against them.
function ns.nav.ReindexRoutes(app)
    if not app.routes then return end
    app.routeIndex = {}
    IndexRoutes(app, app.routes, {}, 1, app.routeIndex)
    app.searchIndex = nil
    -- Structural change: the resolved pages are stale, and the search index
    -- that was keyed against their tables goes with them.
    if ns.page and ns.page.ClearPageCache then ns.page.ClearPageCache(app) end

    -- A REBUILD CAN ORPHAN THE SELECTION, and something has to notice.
    --
    -- A collection whose filter just changed drops members: the Buff List's
    -- own find-in-list box takes the entry you were reading out of the
    -- source, and the route to it stops existing mid-keystroke. Left
    -- pointing there, app.route resolves to no node and no page -- so
    -- ns.page.Render hides the body and the placeholder draws over it, which
    -- reads as "the list vanished and left a route behind". SetRoutes has
    -- always guarded its own version of this; the rebuild path is where the
    -- membership actually moves, and it did not.
    --
    -- ns.nav.Settle is the same rule Navigate lands on -- up to a node that
    -- exists, then down to one that is a destination -- so a rebuild leaves
    -- the reader somewhere a page can actually be drawn. Stopping at the
    -- first surviving ancestor is not enough: inside a tree group that is a
    -- SECTION heading, which has children and no page of its own.
    local was  = table.concat(app.route or {}, "/")
    local path = ns.nav.Settle(app, app.route, true)
    if #path == 0 then
        -- THE LAST RESORT, and it is a relocation: the reader ends up in
        -- the first top-level section, which is somewhere they did not ask
        -- to be. It is still better than a blank body with a live route
        -- pointing at nothing, so it stays -- but it is reported, because a
        -- non-empty route can only fail to settle if its own top-level node
        -- has left the tree, and that is a fact about the declaration
        -- rather than about the reader.
        if #(app.route or {}) > 0 then
            ns.Report(app, "route '" .. was .. "' could not be settled; "
                .. "falling back to the first section")
        end
        path = app.routes[1] and ns.nav.Settle(app, { app.routes[1].id }, true) or {}
    end
    if table.concat(path, "/") ~= was then
        app.route = path
        ns.nav.MarkBranchExpanded(app, path)
        -- Every repair, not only the last-resort one: a route moving
        -- without the reader touching anything is the class of event that
        -- has been hardest to see from a bug report.
        ns.Report(app, "route repaired: '" .. was .. "' -> '"
            .. table.concat(path, "/") .. "'")
    end
    -- Asked after the route has settled, and unconditionally: a rebuild can
    -- move the selection without going through Navigate, and it can also
    -- leave it where it was while the NODE under it gained or lost a
    -- sectionKey. FireSectionChange is the one that decides nothing moved.
    ns.nav.FireSectionChange(app)
end

function ns.nav.SetRoutes(app, nodes)
    assert(type(nodes) == "table", "SetRoutes: expected a table of nodes")
    app.routes      = nodes
    app.routeIndex  = {}
    IndexRoutes(app, nodes, {}, 1, app.routeIndex)
    -- The search index is a projection of the route index, so it dies with
    -- it. Rebuilt lazily on the next query rather than here: an app that
    -- never searches should not pay to be searchable.
    app.searchIndex = nil
    app.route       = app.route or {}
    -- A tree change can orphan the current selection. Settled the same way
    -- every other landing is (ns.nav.Settle): up to a node that exists,
    -- then down to one that can be drawn -- falling back to the first
    -- top-level node when nothing on the old path survived. Stopping at
    -- that node itself is a dangling route of a second kind, whenever it
    -- is a branch with no page of its own.
    local settled = ns.nav.Settle(app, app.route, true)
    if #settled == 0 then
        -- Legitimate for an opening route, which is empty by definition.
        -- Reported for any other, where it means the reader's own top-level
        -- section is no longer in the declaration -- see ReindexRoutes.
        if #(app.route or {}) > 0 then
            ns.Report(app, "route '" .. table.concat(app.route, "/")
                .. "' did not survive SetRoutes; falling back to the first section")
        end
        settled = nodes[1] and ns.nav.Settle(app, { nodes[1].id }, true) or {}
    end
    app.route = settled
    -- Seed the opening route's branch as explicitly open, so it does not
    -- collapse the first time the reader goes somewhere else.
    ns.nav.MarkBranchExpanded(app, app.route)
    -- Same reason as in ReindexRoutes: declaring the tree is a landing too,
    -- and it fires only if the settled route resolves a different key.
    ns.nav.FireSectionChange(app)
    if app.frame then ns.nav.Refresh(app) end
end

-- Nodes at one level, given the currently selected path. Level 1 is the
-- top-level list; level N is the children of whatever is selected at
-- level N-1. This is what makes a navigator level-bound rather than
-- tree-bound.
function ns.nav.NodesAtLevel(app, level)
    if not app.routes then return {}, nil end
    if level == 1 then return app.routes, app.route[1] end

    local parentPath = {}
    for i = 1, level - 1 do
        if not app.route[i] then return {}, nil end
        parentPath[i] = app.route[i]
    end
    local entry = app.routeIndex[table.concat(parentPath, "/")]
    -- From the INDEX, not the node: a collection's children are computed,
    -- and the index is where the computed set was recorded.
    return (entry and entry.children) or {}, app.route[level]
end

-- ── Selection ──────────────────────────────────────────────────

local function RouteKey(path) return table.concat(path, "/") end

-- A node's children, from the INDEX where they were recorded.
--
-- Declared children live on the node, but a collection's are computed at
-- index time, so the node itself has none. Everything that walks the tree
-- has to ask the index, or a collection looks childless and its members
-- become unreachable.
local function KidsAt(app, key, node)
    local entry = app.routeIndex and app.routeIndex[key]
    return (entry and entry.children) or (node and node.children)
end
ns.nav.KidsAt = KidsAt

-- ── Section keys ───────────────────────────────────────────────
--
-- A route node may declare `sectionKey`, and a route's RESOLVED key is its
-- own, else the nearest ancestor's, else nil. It is a second, coarser
-- observable beside the route itself: a consuming addon usually cares which
-- SECTION of its settings is on screen -- which preview to paint, which
-- cache to drop -- and not which of a section's eight subtabs, so making it
-- follow from the tree is one declaration where every page would otherwise
-- have to remember to stamp a global on the way in.
--
-- The field is `sectionKey` and not `section` on purpose: collection nodes
-- already use `section`/`sections` for the partition a member falls in, and
-- the two would sit on the same node.
local function ResolveSectionKey(app, path)
    local idx = app.routeIndex
    if not idx or not path then return nil end
    -- Deepest first: the node's own key wins over the one it inherits, which
    -- is what lets a single subtab (a debuff-highlight page, say) name a key
    -- of its own inside a section that already has one.
    for i = #path, 1, -1 do
        local e = idx[table.concat(path, "/", 1, i)]
        local key = e and e.node and e.node.sectionKey
        if key ~= nil then return key end
    end
    return nil
end
ns.nav.ResolveSectionKey = ResolveSectionKey

function ns.nav.GetSectionKey(app)
    return ResolveSectionKey(app, app.route or {})
end

-- Fire the section observers if the resolved key has moved.
--
-- `app.sectionKey` holds the LAST FIRED key, so nothing fires while the
-- reader walks around inside one section. `force` is for Open(), which
-- fires unconditionally with oldKey = nil: route observers only ever fire
-- on a Navigate, so the page a session STARTS on -- a restored route, a
-- deep link -- otherwise arrives with nothing stamped at all.
local function FireSectionChange(app, force)
    local newKey = ResolveSectionKey(app, app.route or {})
    local oldKey = app.sectionKey
    if not force and newKey == oldKey then return false end
    app.sectionKey = newKey
    if force then oldKey = nil end

    local routeKey = RouteKey(app.route or {})
    -- Snapshotted: an observer is free to unregister itself, or another
    -- one, while it runs, and mutating the array being walked would then
    -- skip whoever moved down into the hole.
    local live = app.sectionObservers or {}
    local snapshot = {}
    for i = 1, #live do snapshot[i] = live[i] end
    for i = 1, #snapshot do
        local obs = snapshot[i]
        if obs and obs.fn then obs.fn(newKey, oldKey, routeKey, app) end
    end
    return true
end
ns.nav.FireSectionChange = FireSectionChange

function ns.nav.RegisterSectionObserver(app, fn)
    assert(type(fn) == "function", "RegisterSectionObserver: fn must be a function")
    app.sectionObservers = app.sectionObservers or {}
    local obs = { fn = fn }
    app.sectionObservers[#app.sectionObservers + 1] = obs
    return obs
end

function ns.nav.UnregisterSectionObserver(app, obs)
    for i, o in ipairs(app.sectionObservers or {}) do
        if o == obs then table.remove(app.sectionObservers, i); return true end
    end
    return false
end

-- WHERE A PATH ACTUALLY LANDS: up until it exists, then down until it is
-- somewhere worth being.
--
-- Both halves are the same rule -- a route the reader is left on has to
-- name a node that exists AND has a page -- and both were written out
-- separately before, in Navigate only, which is why every path that did
-- not go through Navigate could strand the panel on a route that drew
-- nothing.
--
--   UP    a rebuild can delete the node under the selection: a collection
--         filtered by a search box drops the member being read. The
--         nearest surviving ancestor is where that belongs -- the list it
--         was in, not the top of the tree.
--   DOWN  a parent with children and no page of its own is not a
--         destination; nor is a tree-group collection, whose page is the
--         page its list SITS on, the same one for every member. Descend
--         to the first child that is a destination.
--
-- "The first child" is the first that LEADS somewhere, not simply the
-- first. A collection's section headings survive an empty list when they
-- declare showEmpty -- a Whitelist and a Blacklist with nothing in either
-- -- and they have no page and no children, so taking the first one
-- landed on a heading that draws nothing, one level up from the member
-- that was deleted and just as blank. FirstDrawable below asks the
-- subtree instead of guessing.
--
-- The UP half is opt-in, because the two callers mean different things by
-- a route that does not exist. A rebuild is REPAIRING one and wants the
-- nearest surviving ancestor; a Navigate to a route that was never there
-- is a caller's mistake, and answering "fine, I went somewhere else" would
-- hide it. Without `up`, a missing target returns an empty path and
-- Navigate reports false exactly as it always did.
--
-- Returns a new table; the path handed in is not touched.

-- The deepest-first search the DOWN half runs on: the first route at or
-- under `path` that has a page, or nil when the whole subtree has none.
--
-- A tree-group collection is checked LAST rather than first. Its page is
-- the list, and landing on the list with nothing selected is the right
-- answer only when it has no members to select -- so its children are
-- tried, and it answers for itself if none of them can.
--
-- Bounded by the tree: each step appends a segment, so the route key grows
-- every time and a key the index does not hold ends that branch.
-- `descend = true` on a node says its page is the CHILDLESS answer only:
-- while it has children, the first of them is the destination, the way
-- older options dialogs opened a tabbed child-group entry on its first tab. A
-- collection whose members are tabs declares it, so that arriving at the
-- collection lands on a member rather than on a page saying "pick one",
-- and still lands on that page when there is nothing to pick.
local function FirstDrawable(app, path)
    local key   = RouteKey(path)
    local entry = app.routeIndex[key]
    if not entry then return nil end
    local node = entry.node
    if node.page and not node.treeGroup and not node.descend then return path end

    for _, kid in ipairs(KidsAt(app, key, node) or {}) do
        local sub = {}
        for i, id in ipairs(path) do sub[i] = id end
        sub[#sub + 1] = kid.id
        local got = FirstDrawable(app, sub)
        if got then return got end
    end

    if node.page then return path end
    return nil
end

function ns.nav.Settle(app, path, up)
    local out = {}
    for i, id in ipairs(path or {}) do out[i] = id end
    if not app.routeIndex then return out end

    if up then
        while #out > 0 and not app.routeIndex[RouteKey(out)] do out[#out] = nil end
    end
    if #out == 0 or not app.routeIndex[RouteKey(out)] then return {} end

    -- Down from here; and when there is nothing drawable below, up one and
    -- down again. That second half is what an empty collection needs: its
    -- sections lead nowhere, and the list itself -- one level up -- is
    -- exactly what should be on screen.
    while true do
        local got = FirstDrawable(app, out)
        if got then return got end
        if not up or #out <= 1 then return out end
        out[#out] = nil
    end
end

-- Pattern matching for observers and IsRouteActive.
--   "auras"          matches auras and everything under it
--   "auras/*"        matches any direct child of auras
--   "auras/buffs"    matches exactly that route (and its descendants)
-- `*` matches within one segment only.
local function MatchesPattern(routeKey, pattern)
    if pattern == "*" then return true end
    local lua = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
                       :gsub("%*", "[^/]*")
    if routeKey:match("^" .. lua .. "$") then return true end
    -- prefix: the pattern names an ancestor of this route
    if routeKey:match("^" .. lua .. "/") then return true end
    return false
end
ns.nav.MatchesPattern = MatchesPattern

function ns.nav.IsRouteActive(app, pattern)
    return MatchesPattern(RouteKey(app.route or {}), pattern)
end

-- Fire node lifecycle for the nodes left and entered, then observers.
-- Both lists are computed against the COMMON PREFIX, so navigating from
-- auras/buffs to auras/debuffs fires leave(buffs) and enter(debuffs) but
-- does NOT re-fire enter(auras) -- which is the semantics the current
-- panel hand-rolls with its section trackers.
local function FireTransition(app, oldPath, newPath)
    local common = 0
    while oldPath[common + 1] and newPath[common + 1]
          and oldPath[common + 1] == newPath[common + 1] do
        common = common + 1
    end

    for i = #oldPath, common + 1, -1 do
        local e = app.routeIndex[table.concat(oldPath, "/", 1, i)]
        local fn = e and e.node.onLeave
        if fn then fn(e.node, app) end
    end
    for i = common + 1, #newPath do
        local e = app.routeIndex[table.concat(newPath, "/", 1, i)]
        local fn = e and e.node.onEnter
        if fn then fn(e.node, app) end
    end

    local newKey = RouteKey(newPath)
    local oldKey = RouteKey(oldPath)
    for _, obs in ipairs(app.routeObservers or {}) do
        local wasIn = MatchesPattern(oldKey, obs.pattern)
        local isIn  = MatchesPattern(newKey, obs.pattern)
        if wasIn ~= isIn or (isIn and obs.everyChange) then
            obs.fn(isIn, newKey, app)
        end
    end
end

-- The route a session OPENS on, told to the route observers.
--
-- Navigate fires them on the way from one route to another, and opening
-- is not a Navigate: the route was settled when the routes were declared,
-- so the page a session opens on -- restored, deep-linked, or simply the
-- first -- arrived with no observer told. A page whose observer stamps
-- what is on screen (which aura sub-category the preview should draw)
-- then opened on a stale stamp, and the section observer had already
-- been given exactly this treatment for exactly this reason. Fired as an
-- arrival from nowhere: every observer whose pattern matches the route is
-- told it is in, none is told it left anything.
function ns.nav.FireArrival(app)
    FireTransition(app, {}, app.route or {})
end

function ns.nav.Navigate(app, ...)
    local path
    if type(select(1, ...)) == "table" then
        path = select(1, ...)
    else
        path = { ... }
    end

    -- Where the target actually lands -- see ns.nav.Settle. One rule, in
    -- one place, so a click, a rebuild and a restored route cannot each
    -- settle somewhere different.
    path = ns.nav.Settle(app, path)
    local entry = (#path > 0) and app.routeIndex[RouteKey(path)] or nil
    if not entry then return false end

    local old = app.route or {}
    if RouteKey(old) == RouteKey(path) then return true end
    app.route = path
    -- Every ancestor of the new route is opened, so navigating into a
    -- collapsed branch shows where you landed.
    ns.nav.MarkBranchExpanded(app, path)
    -- Sections BEFORE the route: the section observer is the coarse stamp,
    -- and a page's own onEnter or route observer must be able to refine it
    -- afterwards rather than have it land on top of what they just wrote.
    ns.nav.FireSectionChange(app)
    FireTransition(app, old, path)
    ns.nav.Refresh(app)
    return true
end

function ns.nav.GetRoute(app)
    local copy = {}
    for i, v in ipairs(app.route or {}) do copy[i] = v end
    return copy
end

function ns.nav.RegisterRouteObserver(app, pattern, fn, everyChange)
    app.routeObservers = app.routeObservers or {}
    local obs = { pattern = pattern, fn = fn, everyChange = everyChange }
    app.routeObservers[#app.routeObservers + 1] = obs
    return obs
end

function ns.nav.UnregisterRouteObserver(app, obs)
    for i, o in ipairs(app.routeObservers or {}) do
        if o == obs then table.remove(app.routeObservers, i); return true end
    end
    return false
end

-- ── Navigator: tree (the left rail) ────────────────────────────

local ROW_HEIGHT = 22

-- Where a row's parts sit, for the two places a tree is drawn. `rail` is
-- the panel's own navigator; `compact` is an in-page tree (see RenderTree's
-- slow path for why they differ).
local TREE_METRICS = {
    rail    = { rowInset = 4, indent = 12, chevX = 9, chevBtnX = 2, labelX = 22,
                smallBelow = false },
    compact = { rowInset = 0, indent = 8,  chevX = 4, chevBtnX = 0, labelX = 16,
                smallBelow = true },
}


local function TreeRowFactory(app)
    local row = CreateFrame("Button", nil, app:GetRegion("rail"))
    row:SetHeight(ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:Hide()

    -- Disclosure chevron: our own texture, not a font glyph and not a
    -- Blizzard button. WoW's fonts have no triangle (U+25B8 renders as a
    -- missing-glyph box), and the stock +/- plates are exactly the look this
    -- panel exists to get away from. Media/chevron.tga is white with an
    -- alpha channel, so one file serves every skin: it is tinted at runtime
    -- and rotated for the open state.
    row.chev = row:CreateTexture(nil, "OVERLAY")
    row.chev:SetTexture(ns.MEDIA .. "chevron.tga")
    row.chev:SetSize(11, 11)
    row.chev:SetPoint("LEFT", row, "LEFT", 9, 0)

    -- The chevron needs its own hit area: toggling a branch open and
    -- SELECTING it are different intentions, and one row cannot serve both
    -- from a single click.
    row.chevBtn = CreateFrame("Button", nil, row)
    row.chevBtn:SetSize(20, ROW_HEIGHT)
    row.chevBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.chevBtn:Hide()

    -- The drag affordance, shared with the group cards. Hidden unless this
    -- row turns out to be a draggable collection member.
    row.grip = ns.reorder.AttachGrip(row)

    row.label = ns.FS(row, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    return row
end

-- Expansion is its OWN state, not a side effect of the current route.
--
-- It used to be inferred -- a branch was open exactly when you were inside
-- it -- which meant you could not collapse the branch you were in, and
-- could not open any other. The inferred value is still the DEFAULT, so a
-- tree nobody has touched behaves as before; the moment a chevron is
-- clicked, that node's state is remembered instead.
local function IsExpanded(app, key, onRoute)
    local st = app.navExpanded and app.navExpanded[key]
    if st == nil then return onRoute end
    return st and true or false
end

-- The DEFAULT a node falls back to while nobody has clicked its chevron.
--
-- Normally "open exactly when the route is inside it". A node may say
-- otherwise with `expanded = true|false` -- a tree's Whitelist and
-- Blacklist headings opened by default, and a heading that starts shut
-- hides the very list it is there to label. A stored click still wins:
-- this only answers when IsExpanded has nothing remembered.
local function DefaultOpen(app, node, path)
    if node and node.expanded ~= nil then return node.expanded and true or false end
    return app.route[#path] == node.id
end

-- Mark every ancestor of a path as open.
--
-- Called when the route is SET as well as when it is navigated. Without the
-- first, a branch that was open only by inference -- because the initial
-- route happened to be inside it -- had no stored state, so the moment you
-- navigated elsewhere it fell back to the inferred value and collapsed. From
-- the reader's side a branch they never touched closed itself.
-- Every prefix, INCLUDING the path itself.
--
-- Not `#path - 1`. The opening route is often a branch rather than a leaf --
-- "controls", not "controls/switches" -- and stopping one short marks nothing
-- at all for it, which is precisely the branch that needs marking. A leaf
-- marked open is harmless: nothing ever asks whether a childless node is
-- expanded.
local function MarkBranchExpanded(app, path)
    app.navExpanded = app.navExpanded or {}
    for i = 1, #path do
        app.navExpanded[table.concat(path, "/", 1, i)] = true
    end
end
ns.nav.MarkBranchExpanded = MarkBranchExpanded

function ns.nav.ToggleExpanded(app, key, onRoute)
    app.navExpanded = app.navExpanded or {}
    app.navExpanded[key] = not IsExpanded(app, key, onRoute)
    ns.nav.Refresh(app)
end

-- Does the RAIL draw this node's children, or does the node draw them itself?
--
-- A node that declares a `navigator` of its own -- a subtab strip, a
-- dropdown -- is already presenting its children somewhere. Whether the
-- tree ALSO lists them is a judgement about that section, not a law:
-- six subtabs in the strip and the same six indented in the rail is two
-- controls for one move, but a section whose children are worth finding
-- from the rail is a real case too.
--
-- So it is a setting, in three tiers, nearest wins:
--
--   node.railChildren = true|false   this section, outright
--   app:SetRailChildren(true|false)  the addon's default for such nodes
--   (neither)                        false -- the strip owns them
--
-- A node with NO navigator of its own is untouched by any of this: the
-- rail is the only thing presenting its children, so it always draws them.
function ns.nav.RailShowsChildren(app, node)
    -- An explicit answer wins even from a node with no navigator of its
    -- own: a section whose children are presented BY ITS PAGE -- a tree
    -- group -- has somewhere to show them and does not want them listed
    -- twice, once in the page and once in the rail.
    if node and node.railChildren ~= nil then
        return node.railChildren and true or false
    end
    if not (node and node.navigator) then return true end
    if app and app.railChildren ~= nil then return app.railChildren and true or false end
    return false
end

-- Build the visible row list: every top-level node, plus the children of
-- whichever branch the current route is in. Collapsed siblings contribute
-- nothing, so a 17-section tree stays short.
-- level 1: every top-level node, with the open section's children under it.
-- level 2: ONLY the children of the section selected at level 1 -- the shape
-- you want when a top button bar owns level 1 and the rail shows that
-- section's own tree. Same routes, same navigator, different binding.
-- `owner`, where given, is a route entry: the rows are that node's
-- children rather than a level of the whole tree, which is what an in-page
-- tree draws. Everything below is the same walk -- only the starting point
-- and the base path differ.
-- `withParent` is for a rail tree bound at level 2 while a button bar owns
-- level 1: the section the bar has selected is drawn as the tree's FIRST
-- row, with its own pages under it. Without it the rail begins at the
-- section's children and the section itself is nowhere in the rail --
-- readable while the bar is the only thing selecting it, and wrong the
-- moment the section has a page of its own, because there is then a
-- destination the rail cannot reach and cannot show as current.
--
-- It needs no special selection handling: the row carries the section's
-- own path, and DeepestSelected already lights the deepest visible row the
-- route passes through -- the section row while its own page is up, the
-- child row once one is opened.
--
-- The row is a SIBLING of the section's pages, not a heading above them:
-- same depth, same indent. It is one more destination in the list, and
-- indenting the others under it would say the section row contains them --
-- which the strip above already says, and says better. It draws no
-- disclosure chevron for the same reason: the branch a chevron would open
-- is the list it is already in.
--
-- A STRING rather than `true` renames it. The section's own name is
-- already on the strip and in the breadcrumb, so repeating it in the rail
-- says nothing; what the reader wants there is what that page IS -- which
-- for a section root is usually "Enable".
local function VisibleTreeRows(app, level, owner, withParent)
    local rows = {}

    -- Recursive, to whatever depth the tree actually has.
    --
    -- This used to build exactly two levels, which was fine while every
    -- tree was two deep and silently wrong the moment one was not: a
    -- collection's members sit a level below the collection, so they were
    -- indexed as routes, reachable by Navigate, and drawn nowhere. Clicking
    -- the collection appeared to do nothing at all.
    --
    -- Depth is passed down rather than derived from the path length,
    -- because a navigator mounted at level 2 draws its own rows at depth 1
    -- -- the indentation is relative to what this navigator shows, not to
    -- where the node sits in the whole tree.
    local function Walk(nodes, path, depth)
        for _, node in ipairs(nodes) do
            local p = {}
            for i = 1, #path do p[i] = path[i] end
            p[#p + 1] = node.id
            local key = table.concat(p, "/")

            rows[#rows + 1] = { node = node, depth = depth, path = p }

            local kids = KidsAt(app, key, node)
            if kids and #kids > 0 and not app.bpFlatNav
               and ns.nav.RailShowsChildren(app, node)
               and IsExpanded(app, key, DefaultOpen(app, node, p)) then
                Walk(kids, p, depth + 1)
            end
        end
    end

    if owner then
        -- Depth 1 is the owner's CHILDREN: the owner itself is the page the
        -- tree sits on, not a row in it.
        Walk(KidsAt(app, owner.key, owner.node) or {}, owner.path, 1)
    elseif (level or 1) >= 2 then
        local base = {}
        for i = 1, level - 1 do base[i] = app.route[i] end
        -- ONLY for a section with a page of its own: the row exists so
        -- that page is reachable from the rail, and a section without one
        -- is not a destination -- selecting it descends to its first child,
        -- which is already the first row below.
        if withParent then
            local entry = app.routeIndex and app.routeIndex[table.concat(base, "/")]
            if entry and entry.node and entry.node.page then
                rows[#rows + 1] = { node = entry.node, depth = 1, path = base,
                                    title = (type(withParent) == "string")
                                            and withParent or nil,
                                    -- Its children are its siblings here.
                                    leaf = true }
            end
        end
        Walk(ns.nav.NodesAtLevel(app, level), base, 1)
    else
        Walk(app.routes or {}, {}, 1)
    end
    return rows
end

-- Shared script handlers. Defined ONCE at file scope, not per row per
-- render: the old code allocated three closures for every visible row on
-- every navigation, which is garbage generated by simply clicking around.
-- Everything they need is stashed on the row itself.
-- A parent with children but NO page of its own is not a destination --
-- there is nothing to show if you select it. For those, the whole row is
-- the disclosure control, not just the chevron: clicking anywhere on it
-- opens or closes the branch. Rows that lead somewhere still navigate.
local function RowOnClick(self)
    if self.navTogglesOnly then
        ns.nav.ToggleExpanded(self.app, self.navKey, self.navOnRoute)
    else
        ns.nav.Navigate(self.app, self.navPath)
    end
end

-- Shared, like the other row handlers: one closure for the whole tree
-- rather than one per row per render.
local function ChevOnClick(self)
    ns.nav.ToggleExpanded(self.app, self.navKey, self.onRoute)
end
local function RowOnEnter(self)
    -- A section's `desc` is hover help, exactly as a field's is. It also
    -- rescues a title too long for the rail, which is truncated rather than
    -- wrapped and would otherwise be unreadable at a narrow rail width.
    local node = self.navNode
    if node then
        local d = node.desc or node.tooltip
        if type(d) == "function" then d = d(node, self.app) end
        local truncated = self.label.IsTruncated and self.label:IsTruncated()
        if d or truncated then
            ns.context.Show(self, self.app, node.title or node.id, d)
        end
    end
    if self.isSelected then return end
    local h = self.app.skin.hoverBg
    self.bg:SetColorTexture(h[1], h[2], h[3], h[4])
    self.bg:Show()
end
local function RowOnLeave(self)
    ns.context.Hide()
    if not self.isSelected then self.bg:Hide() end
end

-- The accent, lightened. What a selected label wore before there was a
-- token for it, and what it wears again when a skin asks for the accent
-- derivation back.
local function AccentText(ac)
    return math.min(1, ac[1] + 0.45), math.min(1, ac[2] + 0.25), math.min(1, ac[3] + 0.1)
end

-- What a SELECTED label is painted, wherever one is: a rail row, a section
-- button, a tab. One token for all three, because a reader picking a
-- "selected text" color means the color selected things are, not the
-- color one of the three navigators happens to use -- and three tokens
-- that must agree to look right are three chances to disagree.
--
-- White by default. `tabUseAccent`, or a skin old enough to predate the
-- token, puts the derivation above back.
local function SelectedText(skin)
    if skin.tabUseAccent or not skin.tabSelText then
        return AccentText(skin.accent)
    end
    local t = skin.tabSelText
    return t[1], t[2], t[3]
end

-- Paint one row for its current selected state. Split out from the build
-- so a pure selection change repaints two rows instead of rebuilding the
-- whole list.
local function PaintRow(app, row, selected)
    local skin = app.skin
    row.isSelected = selected
    if selected then
        local a = skin.accentDim
        row.bg:SetColorTexture(a[1], a[2], a[3], a[4])
        row.bg:Show()
        row.label:SetTextColor(SelectedText(skin))
    else
        row.bg:Hide()
        local t = skin.navText or skin.text
        row.label:SetTextColor(t[1], t[2], t[3])
    end

    -- A node may color its own label -- a collection member that is
    -- disabled, say. Resolved at PAINT time and never written back into
    -- the title, because a color baked into a string is a color that
    -- ends up in stored data.
    if not selected and row.navNode and row.navNode.color then
        local c = row.navNode.color()
        if c then row.label:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end

    -- A live query fades the branches it did not match. The row stays in
    -- place and stays clickable: this is a contrast change, not a filter,
    -- so the shape of the tree survives the search.
    local lit = (not ns.search) or ns.search.RouteMatches(app, row.navKey)
    row:SetAlpha(lit and 1 or ns.search.DimAlpha())
end

-- ── Which row wears the highlight ──────────────────────────────
--
-- NOT an exact match on the route key. A section whose children live in
-- a tab strip has no rail row for the leaf the reader is actually on, so
-- an exact test lights nothing at all -- select a section and the tree
-- goes blank, which is precisely what it did.
--
-- The DEEPEST visible row that is the route or an ancestor of it. With
-- the subtabs listed in the rail that is the leaf itself; with them in
-- the strip it is the section row, which is the row the reader clicked
-- and the one they look at to find their place.
--
-- The ancestor test is SEGMENT-ALIGNED. "text" is not an ancestor of
-- "textExtra/foo" however much of it matches character by character --
-- the trap §27.20 records, and the reason for the trailing slash.
local function IsAncestorOrSelf(key, routeKey)
    if key == routeKey then return true end
    return routeKey:sub(1, #key + 1) == key .. "/"
end

-- `keys` is a list of route keys, in any order. Longest wins, which is
-- the deepest, because every candidate is an ancestor of the same route.
local function DeepestSelected(keys, routeKey)
    local best
    for _, k in ipairs(keys) do
        if IsAncestorOrSelf(k, routeKey) and (not best or #k > #best) then
            best = k
        end
    end
    return best
end

-- A cheap signature of what the tree WOULD draw. If it has not changed,
-- the row list is already correct and only the highlight needs moving.
local function TreeSignature(app, visible)
    local parts = {}
    for i, item in ipairs(visible) do
        parts[i] = table.concat(item.path, "/") .. ":" .. item.depth
    end
    -- The active query is PART of what the tree looks like, so it belongs in
    -- the signature.
    --
    -- Without it the fast path below returned early whenever a query changed
    -- without changing which rows were visible -- which is the common case --
    -- so the dimming never repainted. The only thing that did force a repaint
    -- was moving the selection, so the tree appeared to update when you
    -- clicked a row and at no other time, and clearing the box left every
    -- row faded. Extending the signature rather than bypassing the fast path:
    -- the fast path is what keeps switching sections cheap, and the signature
    -- is already how this file says "that is a different tree now".
    parts[#parts + 1] = "q:" .. tostring(app.searchText or "")
    -- And the rail's own reserve. Fourth time this list has been short of an
    -- input: the tree's geometry changes when the search box arrives or
    -- leaves, so that has to invalidate the cached rows like anything else.
    parts[#parts + 1] = "s:" .. tostring(ns.search.RailReserve(app))
    -- Fifth. Whether the rail draws a node's children is a CHEVRON-level
    -- decision now (RailShowsChildren, in the row renderer), and a chevron
    -- can change without the visible ROW LIST changing at all: flip the
    -- setting while nothing is expanded and every stripped section gains or
    -- loses its marker while `visible` stays identical. Without this the
    -- fast path returned early and the chevrons kept their old state until
    -- something else happened to move the selection.
    parts[#parts + 1] = "r:" .. tostring(app.railChildren)
    return table.concat(parts, "|")
end

-- ── Drag reorder, on the shared gesture ────────────────────────
--
-- The gesture itself is ns.reorder; this supplies the two things it does
-- not know: which rows count as siblings, and what a drop means.
--
-- A row knows whether it can be dragged without asking anything: a member
-- node carries bpCollection and bpMember, so `row.navNode.bpCollection`
-- with a reorder.onMove on it is the whole test.
--
-- Two modes, because they are different edits to the addon's data:
--
--   default        siblings are the members under the SAME parent. A
--                  section node is the parent of its members, so members
--                  of different sections never compare equal and a
--                  cross-section drop simply finds no slot.
--   across="move"  siblings widen to every member row of the collection
--                  PLUS the section header rows, which is what makes an
--                  empty section a place you can drop into. The section a
--                  drop lands in is whichever header it sits under.

local function RowKeyOf(row, n)
    return table.concat(row.navPath, "/", 1, n or #row.navPath)
end

local function SortedByScreen(list)
    table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    return list
end

-- Members under the same parent: the within-a-section case.
local function SameParentSiblings(row)
    local nav  = row.navNav
    local coll = row.navNode and row.navNode.bpCollection
    if not (nav and coll) then return {} end
    local parentKey = RowKeyOf(row, #row.navPath - 1)
    local out = {}
    for _, r in ipairs(nav.rows or {}) do
        if r:IsShown() and r.navNode and r.navNode.bpCollection == coll
           and r.navNode.bpMember
           and r.navPath and #r.navPath == #row.navPath
           and RowKeyOf(r, #r.navPath - 1) == parentKey then
            out[#out + 1] = r
        end
    end
    return SortedByScreen(out)
end

-- Every row belonging to this collection -- members and section headings
-- alike -- in screen order. A heading is not draggable but IS a slot, so
-- dropping just under "Blacklist" means the top of the blacklist even when
-- there is nothing in it.
local function WholeCollectionSiblings(row)
    local nav  = row.navNav
    local coll = row.navNode and row.navNode.bpCollection
    if not (nav and coll) then return {} end
    local out = {}
    for _, r in ipairs(nav.rows or {}) do
        if r:IsShown() and r.navNode and r.navNode.bpCollection == coll then
            out[#out + 1] = r
        end
    end
    return SortedByScreen(out)
end

-- A ROW's section and a SLOT's section are different questions, and
-- answering the second with the first is an off-by-one that puts a drop in
-- the wrong list.
--
-- A row sits somewhere, so its section is the nearest heading AT OR ABOVE
-- it. A slot is a GAP -- slot i means "above sibs[i]" -- so its section is
-- the nearest heading STRICTLY above the gap. The difference only shows up
-- at a section boundary, which is exactly where dropping into an empty
-- list lands: the gap under an empty "Whitelist" heading is the gap above
-- the "Blacklist" heading, and reading the row at that index answers
-- "black" for a drop the reader clearly meant as "white".
local function SectionOfRow(sibs, i)
    for k = math.min(i, #sibs), 1, -1 do
        local n = sibs[k] and sibs[k].navNode
        if n and n.bpSection then return n.bpSection.id, k end
    end
    return nil, nil
end

local function SectionOfSlot(sibs, slot)
    for k = math.min(slot - 1, #sibs), 1, -1 do
        local n = sibs[k] and sibs[k].navNode
        if n and n.bpSection then return n.bpSection.id, k end
    end
    -- Above everything: the top list. A drop there is unambiguous even
    -- though no heading precedes it.
    for k = 1, #sibs do
        local n = sibs[k] and sibs[k].navNode
        if n and n.bpSection then return n.bpSection.id, k end
    end
    return nil, nil
end

-- The member the dragged row would sit ahead of: the first member row at or
-- after the slot that is still inside the same section.
local function BeforeAt(sibs, slot, sectionId, coll)
    for i = slot, #sibs do
        local n = sibs[i] and sibs[i].navNode
        if not n then break end
        if n.bpSection then break end                 -- next heading: end of section
        if n.bpMember then
            local sid = SectionOfRow(sibs, i)
            if sid ~= sectionId then break end
            -- Pinned members hold the front of their section, so a drop
            -- aimed above one lands after it instead. Skipped rather than
            -- refused: the reader aimed at that list, and the pins are
            -- simply not positions in it.
            if not ns.collections.IsPinned(coll, n.bpMember) then
                return n.bpMember.key
            end
        end
    end
    return nil                                        -- the end of the section
end

local function OnDropWithin(app, coll, from, to, sibs)
    local moving = sibs[from] and sibs[from].navNode
    local target = sibs[to]   and sibs[to].navNode
    if not (moving and target and moving.bpMember and target.bpMember) then return end
    ns.collections.Move(app, coll.id, moving.bpMember.key, target.bpMember.index)
end

-- `to` is a position; `gap` is the raw slot. Which section a drop lands in,
-- and which member it lands above, are both questions about the GAP -- the
-- lift correction belongs to the position and answering them with it puts a
-- member dropped at the end of a list second from last.
local function OnDropAcross(app, coll, from, to, sibs, gap)
    local moving = sibs[from] and sibs[from].navNode
    if not (moving and moving.bpMember) then return end

    local destId = SectionOfSlot(sibs, gap)
    local srcId  = SectionOfRow(sibs, from)
    if not destId then return end

    if destId == srcId then
        -- Same section: an ordinary reorder, so it goes through the
        -- ordinary path and the addon's onMove sees what it always sees.
        local target = sibs[to] and sibs[to].navNode
        if target and target.bpMember then
            ns.collections.Move(app, coll.id, moving.bpMember.key, target.bpMember.index)
            return
        end
        -- ...unless the slot is the END of the section, where there is no
        -- member being displaced and so no index for onMove to take. That
        -- is still a real intention -- "put this last" -- so it goes the
        -- placement route with its own section as the destination.
    end
    ns.collections.MoveTo(app, coll.id, moving.bpMember.key, destId,
                          BeforeAt(sibs, gap, destId, coll))
end

-- Called for every tree row on every build, because Release() strips
-- scripts and a row is reused for whatever comes next -- including a row
-- that must NOT be draggable.
local function InstallRowDrag(app, nav, row, indent)
    row.navNav = nav
    local node = row.navNode
    local coll = node and node.bpCollection
    local spec = coll and coll.reorder
    -- A section heading carries bpCollection too, so that a drop can find
    -- it -- but it is a target, never a thing that moves.
    local can  = spec and spec.onMove and node.bpMember
                 and not ns.collections.IsPinned(coll, node.bpMember)
                 and true or false

    -- The grip sits where the label would, and the label moves over. Done
    -- here rather than in the render loop because whether a row is
    -- draggable is only known once its node is on it -- and a row with no
    -- grip keeps the label anchor the loop already gave it, so a tree with
    -- nothing draggable in it is untouched.
    local showGrip = can and spec.grip ~= false
    row.grip:SetShown(showGrip)
    if showGrip then
        local base = 22 + (indent or 0)
        ns.reorder.PaintGrip(row.grip, app.skin, false)
        row.grip:ClearAllPoints()
        row.grip:SetPoint("LEFT", row, "LEFT", base, 0)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT",  row, "LEFT", base + ns.reorder.GRIP_W + 5, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end

    if not can then
        ns.reorder.Install(row, nil)
        return
    end

    local across = spec.across == "move" and spec.onMoveTo
    ns.reorder.Install(row, {
        siblings   = across and WholeCollectionSiblings or SameParentSiblings,
        -- NO clamp in "move" mode.
        --
        -- The clamp's lower bound is one past the nearest pinned sibling
        -- ABOVE the dragged row -- and in this mode that sibling is the
        -- section heading it lives under, so every upward drop was pushed
        -- back inside its own section and the list above became
        -- unreachable. A pinned MEMBER above it did the same thing.
        --
        -- Crossing sections is a different question and cannot be answered
        -- with the mechanism that keeps pins at the front of ONE list, so
        -- pins are honored at the drop instead: BeforeAt skips them, and
        -- MoveTo refuses to move one at all.
        pinned     = (not across) and function(f)
            local n = f.navNode
            if not n then return true end
            if n.bpSection then return true end
            return ns.collections.IsPinned(coll, n.bpMember)
        end or nil,
        color     = function() return app.skin.accent end,
        -- The tree scrolls in ROWS and has no ScrollFrame, so what the
        -- drag auto-scrolls is the shim over that value; see RenderTree.
        scroll     = function() return nav.autoScroll end,
        lineParent = function() return nav.list end,
        onStart    = function() ns.reorder.PaintGrip(row.grip, app.skin, true) end,
        onEnd      = function() ns.reorder.PaintGrip(row.grip, app.skin, false) end,
        blocked    = function()
            return spec.combat ~= false and InCombatLockdown()
        end,
        onDrop = function(from, to, sibs, gap)
            if across then
                OnDropAcross(app, coll, from, to, sibs, gap)
            else
                OnDropWithin(app, coll, from, to, sibs)
            end
        end,
    })
end

-- The tree draws into the RAIL, or -- for a tree that is a GROUP on a page
-- -- into whatever frame that group hands it (`nav.host`). `owner` is the
-- other half of that difference: with one, the rows are that node's
-- children rather than a level of the whole tree, and the rail's own
-- furniture (the search header, the footer) is not this tree's business.
-- What a row's LABEL says. `titleFn` when the node has one -- a collection
-- member, whose title may carry live state -- and the indexed string
-- otherwise. Named because two places must agree: the render below, and
-- ns.nav.RefreshRow, which re-titles one row without rebuilding the tree.
local function RowTitle(node)
    if node.titleFn then
        local t = node.titleFn()
        if t and t ~= "" then return t end
    end
    return node.title or node.id
end

-- Forward declaration: the scrollbar below moves the window and asks the
-- tree to draw it again, and it is declared above the renderer because a
-- Lua local is only in scope after its declaration.
local RenderTree

-- ── The tree's scrollbar, in ROWS ──────────────────────────────
--
-- Not ns.AttachScrollBar, and not a ScrollFrame under it.
--
-- The list used to be a real ScrollFrame scrolled by PIXELS, with a bar
-- whose thumb height and offset were computed from GetHeight and GetTop at
-- render time -- geometry that is one pass stale during the very render
-- that re-anchors it. Every renders-nothing-new pass could therefore move
-- the bar, which is exactly what a reader sees as "the scrollbar jumps
-- about on its own".
--
-- So the tree does what a classic options tree does, and does not scroll at
-- all: `nav.scrollValue` is a ROW NUMBER, the list draws the rows from it
-- that fit, and the bar is a function of two counts -- how many rows there
-- are and how many fit. Nothing is measured against a frame that has just
-- moved, so a render that changes no rows cannot change what is on screen.
-- It also builds one row frame per VISIBLE line rather than one per entry,
-- which is what makes a list of several hundred spells cost twenty.
local TREE_BAR_W = 10

local function TreeBarUpdate(bar)
    local nav = bar.nav
    local n, per = nav.numlines or 0, nav.maxlines or 0
    local over = n - per
    if over <= 0 or per <= 0 then bar:Hide(); return end
    bar:Show()
    local h    = bar:GetHeight() or 0
    local inset = 2
    local track = math.max(1, h - inset * 2)
    -- The thumb is the visible SHARE of the list, and it sits at the
    -- scrolled share of what is left. Both from the counts, never from a
    -- measurement of the rows themselves.
    local th  = math.max(20, track * (per / n))
    local pos = (over > 0) and ((nav.scrollValue or 0) / over) or 0
    bar.thumb:SetHeight(th)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("LEFT",  bar, "LEFT",   inset, 0)
    bar.thumb:SetPoint("RIGHT", bar, "RIGHT", -inset, 0)
    bar.thumb:SetPoint("TOP",   bar, "TOP",    0, -(inset + pos * (track - th)))
end

-- Move by whole rows and redraw. ONE way in: the wheel, the thumb, a click
-- on the track and "show me the selection" all come through here, so the
-- value can never be set without the rows following it.
local function TreeScrollTo(app, nav, value)
    local over = math.max(0, (nav.numlines or 0) - (nav.maxlines or 0))
    value = math.max(0, math.min(over, math.floor(value + 0.5)))
    if value == nav.scrollValue then return end
    nav.scrollValue = value
    -- The window moved, so the rows must be redrawn -- but nothing about
    -- the tree's SHAPE changed, which is what the signature stands for.
    nav.sig = nil
    RenderTree(app, nav, nav.level or 1)
end

local function EnsureTreeBar(app, nav)
    if nav.bar then return nav.bar end
    local bar = CreateFrame("Frame", nil, nav.list)
    bar:SetWidth(TREE_BAR_W)
    bar:EnableMouse(true)
    bar.nav = nav
    bar.trackBorder, bar.trackTex = ns.BorderedRound(bar, 4, "BACKGROUND", "BORDER")
    local thumb = CreateFrame("Button", nil, bar)
    thumb.tex = ns.RoundTex(thumb, "ARTWORK", 4)
    thumb.tex:SetAllPoints(thumb)
    bar.thumb = thumb

    local function paint()
        local skin = app.skin
        bar.trackBorder:SetVertexColor(skin.controlBorder[1], skin.controlBorder[2],
                                       skin.controlBorder[3], 1)
        bar.trackTex:SetVertexColor(skin.controlBg[1], skin.controlBg[2],
                                    skin.controlBg[3], 1)
        local hot = thumb.dragging or thumb.hovered
        local c = hot and skin.accent or skin.textMuted
        thumb.tex:SetVertexColor(c[1], c[2], c[3], 1)
    end
    bar.paint = paint

    -- Dragging maps the cursor's travel to ROWS: the thumb's range is the
    -- track less the thumb, and the value's range is the rows that do not
    -- fit. No pixel offset is ever stored.
    local function onDrag(self)
        local nav2 = bar.nav
        local over = math.max(0, (nav2.numlines or 0) - (nav2.maxlines or 0))
        if over <= 0 then return end
        local h     = bar:GetHeight() or 0
        local track = math.max(1, h - 4)
        local th    = math.max(20, track * ((nav2.maxlines or 0) / (nav2.numlines or 1)))
        local range = track - th
        if range <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / (bar:GetEffectiveScale() or 1)
        TreeScrollTo(app, nav2, self.grabValue + ((self.grabY - cy) / range) * over)
    end
    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.grabY     = cy / (bar:GetEffectiveScale() or 1)
        self.grabValue = bar.nav.scrollValue or 0
        self.dragging  = true
        self:SetScript("OnUpdate", onDrag)
        paint()
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        paint()
    end)
    thumb:SetScript("OnEnter", function(self) self.hovered = true;  paint() end)
    thumb:SetScript("OnLeave", function(self) self.hovered = false; paint() end)

    -- A click on the track pages by a windowful, the way every list does.
    bar:SetScript("OnMouseDown", function(self)
        local nav2 = self.nav
        local _, cy = GetCursorPosition()
        cy = cy / (bar:GetEffectiveScale() or 1)
        local top, bottom = thumb:GetTop(), thumb:GetBottom()
        if top and bottom and cy <= top and cy >= bottom then return end
        local dir = (cy < (bottom or 0)) and 1 or -1
        TreeScrollTo(app, nav2, (nav2.scrollValue or 0) + dir * (nav2.maxlines or 1))
    end)

    nav.bar = bar
    return bar
end

function RenderTree(app, nav, level)
    local owner = nav.ownerEntry
    local rail = nav.host or app:GetRegion("rail")
    local skin = app.skin
    nav.level  = level

    -- THE LIST. A plain frame the rows are parented to -- no ScrollFrame,
    -- no scroll child, nothing whose size has to be read back. It is
    -- re-anchored below, and its height is the only measurement the tree
    -- takes: how many rows fit.
    if not nav.list then
        local list = CreateFrame("Frame", nil, rail)
        -- Rows never draw outside the list, whatever the render did last:
        -- the list is anchored between the rail's header and the footer's
        -- top, both of which move live with a resize, while the rows are
        -- placed only when the tree renders. Between the two, a shrinking
        -- panel had rows drawn across the footer buttons. Clipping makes
        -- the list's rect the truth at every frame, render or no render.
        list:SetClipsChildren(true)
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(self, delta)
            TreeScrollTo(app, self.nav, (self.nav.scrollValue or 0) - delta)
        end)
        list.nav   = nav
        nav.list   = list
        nav.rows   = nav.rows or {}
        -- What ns.reorder auto-scrolls during a drag. It speaks pixels, so
        -- this converts: a table with the five members it asks for, over
        -- the row-indexed value underneath.
        nav.autoScroll = {
            nav = nav,
            GetTop    = function(self) return self.nav.list:GetTop() end,
            GetBottom = function(self) return self.nav.list:GetBottom() end,
            GetHeight = function(self) return self.nav.list:GetHeight() end,
            GetVerticalScroll = function(self)
                return (self.nav.scrollValue or 0) * (ROW_HEIGHT + 1)
            end,
            SetVerticalScroll = function(self, px)
                TreeScrollTo(app, self.nav, px / (ROW_HEIGHT + 1))
            end,
        }
    end
    -- Scroll is the KEY's, not the surface's: it is the one thing a reader
    -- expects to find where they left it when they come back to a tree.
    -- Defaulted here rather than at creation, because with a host-owned
    -- surface the frames may already exist when this navigator is drawn for
    -- the very first time.
    nav.scrollValue = nav.scrollValue or 0
    -- Re-pointed every render, both of them: the frames outlive any one
    -- navigator now, so a handler that captured `nav` at creation would
    -- speak for whichever tree happened to be drawn here first.
    nav.list.nav = nav
    if nav.autoScroll then nav.autoScroll.nav = nav end
    nav.list:Show()

    -- Anchored BELOW the rail's header, not at a computed offset.
    --
    -- The header owns the search box and its padding and is always present,
    -- collapsing to no height when the box is elsewhere. Anchoring to it
    -- means the tree cannot disagree with the box about how much room the
    -- box takes. The subrail has no search box of its own: the box searches
    -- the whole panel and lives in the rail or the page header, and a
    -- second one over an in-page tree would be a different search in the
    -- same shape.
    local header = (not owner) and ns.search.RailHeader(app) or nil

    -- The tree stops where the FOOTER starts, not where the rail does:
    -- LayoutRegions anchors the footer inside the rail rather than taking
    -- its height off it, so a list anchored to the rail's bottom would run
    -- underneath the buttons. Only a footer INSIDE the rail takes room --
    -- a full-span footer is a band across the panel, and the rail already
    -- stops above it.
    local footerH = (not owner) and (app.footerSpan ~= "full")
                    and (app.footerHeight or 0) or 0
    local bottom  = (footerH > 0) and app:GetRegion("footer") or rail
    local edge    = (footerH > 0) and "TOPRIGHT" or "BOTTOMRIGHT"

    nav.list:SetParent(rail)
    nav.list:ClearAllPoints()
    if header then
        nav.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    else
        -- The rail's own breathing room above the first row. An IN-PAGE
        -- tree sits inside a card with a top pad of its own, so it can ask
        -- for less -- or for none, which is what the Buff List does to keep
        -- its first row level with the pane beside it.
        nav.list:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -(nav.topPad or 6))
    end
    nav.list:SetPoint("BOTTOMRIGHT", bottom, edge, -3, 0)

    local visible = VisibleTreeRows(app, level, owner, nav.withParent)

    -- HOW MANY ROWS FIT. Measured from the REGIONS, as the anchors above
    -- were: the list's own height comes from the anchor set in this very
    -- pass, so reading it back would answer for the layout before it.
    local top  = header and (header:GetHeight() or 0) or (nav.topPad or 6)
    local view = (rail:GetHeight() or 0) - top - footerH
    local rowH = ROW_HEIGHT + 1
    local maxlines = math.floor(view / rowH)
    if maxlines < 1 then maxlines = 1 end

    local numlines = #visible
    nav.numlines, nav.maxlines = numlines, maxlines

    -- WHERE THE LIST IS PARKED. A row number, so it survives anything that
    -- does not change the number of rows -- a re-render, a resize, a card
    -- appearing somewhere else on the page. Clamped against the counts and
    -- nothing else.
    local over = math.max(0, numlines - maxlines)
    nav.scrollValue = math.max(0, math.min(nav.scrollValue or 0, over))

    local selKey  = table.concat(app.route or {}, "/")
    local selRowKey
    do
        local keys = {}
        for i, item in ipairs(visible) do keys[i] = table.concat(item.path, "/") end
        selRowKey = DeepestSelected(keys, selKey)
    end

    -- SHOW THE SELECTION. Only when it has just changed: scrolling to it on
    -- every render would fight the reader, who is allowed to look at one
    -- part of a list while another is selected.
    if selRowKey and nav.selKey ~= selKey and over > 0 then
        local at
        for i, item in ipairs(visible) do
            if table.concat(item.path, "/") == selRowKey then at = i; break end
        end
        if at then
            if at <= nav.scrollValue then
                nav.scrollValue = at - 1
            elseif at > nav.scrollValue + maxlines then
                nav.scrollValue = at - maxlines
            end
            nav.scrollValue = math.max(0, math.min(nav.scrollValue, over))
        end
    end

    local needsBar = over > 0
    local barInset = needsBar and (TREE_BAR_W + 3) or 0

    -- The signature is what the tree DRAWS: its rows, the window on them,
    -- and the width they are laid out for. A pass that would draw exactly
    -- the same thing does nothing at all.
    local sig = TreeSignature(app, visible)
                .. "|m:" .. tostring(maxlines) .. "|s:" .. tostring(nav.scrollValue)
                .. "|b:" .. tostring(needsBar)
                .. "|w:" .. tostring(math.floor((rail:GetWidth() or 0) + 0.5))
                -- Which node's children these are. Two subtrees in one
                -- session share the pool and the code; they must not share
                -- a signature.
                .. "|o:" .. tostring(owner and owner.key or "")

    -- FAST PATH: same rows in the same window, different selection.
    -- Repaint the row that lost the highlight and the one that gained it.
    if nav.sig == sig then
        if nav.selKey ~= selKey then
            local keys = {}
            for i, row in ipairs(nav.rows) do keys[i] = row.navKey end
            local lit = DeepestSelected(keys, selKey)
            for _, row in ipairs(nav.rows) do
                PaintRow(app, row, row.navKey == lit)
            end
            nav.selKey = selKey
        end
        return
    end

    -- ROW METRICS. The rail's rows are inset from the rail's edges and
    -- indent generously, because the rail is a column of a dozen sections
    -- with room to spare. An IN-PAGE tree is a classic tree group --
    -- a list of a few hundred spell names inside a card -- and wearing the
    -- rail's metrics put the first letter of a member 38px in from the
    -- list's edge, against the 16px such trees give it. So an owned tree
    -- takes those numbers: rows flush with the list, 16px to
    -- the label, 8px more per level, and the small font below the top
    -- level -- the shape the reader is used to seeing that list in.
    local m = owner and TREE_METRICS.compact or TREE_METRICS.rail

    -- ONLY THE ROWS ON SCREEN. `slot` is the position in the window and `i`
    -- the position in the list; the pool holds one frame per slot, so the
    -- cost of a tree is what it shows rather than what it has.
    local first = (nav.scrollValue or 0) + 1
    local last  = math.min(numlines, first + maxlines - 1)
    local y     = 0
    local slot  = 0
    for i = first, last do
        local item = visible[i]
        slot = slot + 1
        local row = nav.rows[slot]
        if not row then
            row = app:Acquire("navTreeRow", TreeRowFactory)
            nav.rows[slot] = row
        end
        row.app = app
        row:SetParent(nav.list)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  nav.list, "TOPLEFT",  m.rowInset, -y)
        row:SetPoint("TOPRIGHT", nav.list, "TOPRIGHT", -(m.rowInset + barInset), -y)
        row:Show()

        local ik      = KidsAt(app, table.concat(item.path, "/"), item.node)
        -- `item.leaf` is the row saying it has no branch of its own,
        -- whatever the node says. Only `withParent` sets it: that row's
        -- children are the rows BESIDE it in this very list, so a chevron
        -- there would offer to open what is already open and mark the row
        -- as the parent of its own siblings.
        local hasKids = ik and #ik > 0 and not item.leaf
        local lvl      = #item.path
        local rowKey   = table.concat(item.path, "/")
        local dflt     = DefaultOpen(app, item.node, item.path)
        local expanded = IsExpanded(app, rowKey, dflt)
        local cm = skin.textMuted

        -- Any row with children gets a chevron now, not only the top ones.
        -- A collection sits at depth 2 and has members under it; without
        -- this there is nothing to say the branch opens.
        --
        -- CHILDREN THE RAIL DRAWS, not children the node has. VisibleTreeRows
        -- descends only when RailShowsChildren says so -- a node with its own
        -- `tabs` navigator keeps its subtabs in the strip -- and this renderer
        -- used to ask the plainer question. The two disagreed, and the
        -- disagreement was visible: the row drew a chevron for a branch the
        -- tree was never going to draw, and `navTogglesOnly` below then made
        -- the whole row a disclosure control, so clicking a section did
        -- nothing at all. Both now ask the same question.
        local railKids = hasKids and ns.nav.RailShowsChildren(app, item.node)
        local showChev = railKids and not app.bpFlatNav
        -- The chevron indents with its row, or a nested branch's marker
        -- sits under its parent's label instead of beside its own.
        local ind = (item.depth - 1) * m.indent
        row.chev:ClearAllPoints()
        row.chev:SetPoint("LEFT", row, "LEFT", m.chevX + ind, 0)
        row.chevBtn:ClearAllPoints()
        row.chevBtn:SetPoint("LEFT", row, "LEFT", m.chevBtnX + ind, 0)
        row.chev:SetVertexColor(cm[1], cm[2], cm[3], 0.95)
        row.chev:SetRotation(expanded and -math.pi / 2 or 0)
        -- The chevron only needs its own hit area on a row that ALSO
        -- navigates; where the whole row toggles, a second target for the
        -- same action is just something to miss.
        -- A parent with children and no page normally just opens its
        -- branch: there is nothing to show, so clicking should not pretend
        -- otherwise. A COLLECTION is the exception -- its members are its
        -- content, so selecting it descends to one AND opens the branch, or
        -- clicking it does nothing visible at all.
        --
        -- `railKids`, not `hasKids`: a section whose subtabs live in the
        -- strip has no branch in the rail to open, so its row is a
        -- destination and clicking it navigates. Navigate then descends to
        -- the first child, which is where selecting such a section has
        -- always landed.
        row.navTogglesOnly = railKids and not item.node.page
                             and item.node.node ~= "collection"
        -- The node's DEFAULT open state, which a toggle flips from: for
        -- a node declaring `expanded` that is its declaration, not
        -- whether the route is inside it.
        row.navOnRoute     = dflt
        row.chev:SetShown(showChev)
        row.chevBtn:SetShown(showChev and not row.navTogglesOnly)
        row.chevBtn.app     = app
        row.chevBtn.navKey  = rowKey
        row.chevBtn.onRoute = row.navOnRoute
        row.chevBtn:SetScript("OnClick", ChevOnClick)

        -- Marked on its way to SetText, never stored: the node's own title
        -- is untouched, so clearing the query restores it by rendering.
        -- `item.title` is the row's own override -- only `withParent` sets
        -- one -- and it wins over the node's title, which is the section
        -- name the strip is already showing.
        row.rowTitle = item.title
        row.label:SetText(ns.search.Mark(app, item.title or RowTitle(item.node)))
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT",  row, "LEFT", m.labelX + ind, 0)
        -- Pooled rows serve both trees, so the font is set per render
        -- rather than at creation. Before PaintRow, which sets the color:
        -- a font object change resets it.
        ns.SetFontObject(row.label, (m.smallBelow and item.depth > 1)
                                and "GameFontNormalSmall" or "GameFontNormal")
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        row.navNode = item.node
        row.navPath = item.path
        row.navKey  = table.concat(item.path, "/")
        PaintRow(app, row, row.navKey == selRowKey)

        -- Shared handlers, assigned by reference. Re-set on every build
        -- because Release() strips scripts, but no allocation happens.
        row:SetScript("OnClick", RowOnClick)
        row:SetScript("OnEnter", RowOnEnter)
        row:SetScript("OnLeave", RowOnLeave)
        InstallRowDrag(app, nav, row, ind)

        y = y + rowH
    end

    -- Surplus rows from a taller list or a longer window.
    for k = #nav.rows, slot + 1, -1 do
        app:Release(nav.rows[k])
        nav.rows[k] = nil
    end

    nav.sig, nav.selKey = sig, selKey

    if needsBar then
        local bar = EnsureTreeBar(app, nav)
        bar:SetParent(nav.list)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT",    nav.list, "TOPRIGHT",    0, 0)
        bar:SetPoint("BOTTOMRIGHT", nav.list, "BOTTOMRIGHT", 0, 0)
        bar.nav = nav
        bar:Show()
        bar.paint()
        TreeBarUpdate(bar)
    elseif nav.bar then
        nav.bar:Hide()
    end
end

-- Draw a node's children as a tree inside a frame that is NOT the rail:
-- the tree half of a tree GROUP on a page (see ns.page's treeGroup). The
-- caller owns the frame and its size; this owns the rows inside it.
--
-- The navigator table is cached per owner key on the app, because that is
-- what the renderer's fast path is keyed on -- a fresh table every render
-- would rebuild every row on every repaint.
-- THE SURFACE BELONGS TO THE HOST, THE STATE BELONGS TO THE KEY.
--
-- This split is the whole of why an in-page tree cannot bleed between
-- pages, and it is worth stating plainly because the obvious arrangement --
-- one navigator per route key, owning its own frames -- is the one that
-- broke.
--
-- The host frame here is a POOLED CARD's furniture. A navigator that
-- created its own list frame inside that card left it there when the page
-- changed: App:Release hides the CARD, not the list, and a frame's own
-- shown flag survives its ancestor being hidden. So when the pool later
-- dealt the same card to a different page's tree, LayoutTreeGroup showed
-- the card's list again and every row of the PREVIOUS tree reappeared with
-- it -- same parent, same frame level as the new tree's rows, and still
-- carrying the old route in `navPath`. Two lists drawn over each other,
-- and a click on the wrong one was a perfectly valid navigation into
-- another section. No error, because nothing had gone wrong: the library
-- had simply been asked to show a frame it never put away.
--
-- Hiding it on the way out would have fixed that instance. It would not
-- have fixed the class: it makes correctness depend on every future exit
-- path remembering to call a teardown, and there are several, one of which
-- (RenderTreeInto's own early return, below) had already been missed.
--
-- So the frames are not the navigator's to own. A host gets ONE surface,
-- created once and reused for whatever key is drawn into it -- which is
-- what classic tree groups do, where their buttons are permanent children of
-- its own frame and only the status table is keyed by path. What is left
-- on the navigator is state that genuinely belongs to the KEY and must
-- survive the reader leaving and coming back: the scroll position, and
-- which node's children these are. A card can then only ever hold one row
-- set, by construction. There is nothing to release, and nothing to
-- forget to release.
--
-- The draw caches (`sig`, `selKey`) travel with the SURFACE, not the key:
-- they describe what is currently drawn on these frames. `sig` already
-- carries the owner key, so a surface handed to a different tree fails the
-- comparison and rebuilds, which is exactly right.
local function TreeSurface(host)
    local s = host.bpTreeSurface
    if not s then
        s = { rows = {} }
        host.bpTreeSurface = s
    end
    return s
end

function ns.nav.RenderTreeInto(app, host, ownerKey, topPad)
    local entry = app.routeIndex and app.routeIndex[ownerKey]
    if not (entry and host) then return end
    app.groupNavs = app.groupNavs or {}
    local nav = app.groupNavs[ownerKey]
    if not nav then
        nav = { def = { region = "group" } }
        app.groupNavs[ownerKey] = nav
    end
    nav.ownerEntry = entry
    nav.host = host
    nav.topPad = topPad

    -- Bind the host's surface onto the navigator for the duration of the
    -- render. RenderTree reads and writes these fields as if they were its
    -- own; they are handed back afterwards so the next tree drawn into this
    -- host inherits the frames and the caches that describe them.
    local surf = TreeSurface(host)
    nav.list, nav.rows       = surf.list, surf.rows
    nav.bar, nav.autoScroll  = surf.bar, surf.autoScroll
    nav.sig, nav.selKey      = surf.sig, surf.selKey

    RenderTree(app, nav, 1)

    surf.list, surf.rows      = nav.list, nav.rows
    surf.bar, surf.autoScroll = nav.bar, nav.autoScroll
    surf.sig, surf.selKey     = nav.sig, nav.selKey
    return nav
end

-- ── One row's label, and nothing else ──────────────────────────
--
-- The tree's own rung of the refresh ladder. A member's row can carry live
-- state -- the spec icon a buff is pinned to, the mark that says it can
-- never show -- and the alternative to this was Invalidate: re-index every
-- route, rebuild every row, re-render the page, to change one string.
--
-- Answers whether it found the row, so a caller that is not sure which
-- route the row is under (a member, or one of its subtabs) can try the
-- parent without guessing at the tree's shape.
function ns.nav.RefreshRow(app, routeKey)
    if not routeKey then return false end
    local found = false
    local function scan(navs)
        for _, nav in pairs(navs or {}) do
            for _, row in ipairs(nav.rows or {}) do
                if row.navKey == routeKey and row.navNode and row:IsShown() then
                    row.label:SetText(ns.search.Mark(app,
                        row.rowTitle or RowTitle(row.navNode)))
                    found = true
                end
            end
        end
    end
    scan(app.navs)
    scan(app.groupNavs)
    return found
end

-- ── Navigator: buttonbar (a horizontal strip) ──────────────────

local BUTTON_HEIGHT = 24
local ROW_INSET     = 6     -- above the first row and below the last
local ROW_GAP       = 4     -- between wrapped rows

-- Parented to the frame, not to a region: the render re-parents it to
-- whichever region the chrome spec named, and a region that is currently
-- hidden must not take the pool's spare buttons down with it.
local function BarButtonFactory(app)
    local b = CreateFrame("Button", nil, app.frame)
    b:SetHeight(BUTTON_HEIGHT)
    -- The same bordered-round treatment as every control, so a selected
    -- section reads as a pill rather than a colored rectangle.
    b.border, b.bg = ns.BorderedRound(b, 6, "BACKGROUND", "BORDER")
    -- The relief every button wears (ns.ButtonFace), so a section button
    -- and a page button read as the same kind of thing. Painted per style
    -- in PaintBarButton: the square bar has no buttons to raise.
    b.face = ns.ButtonFace(b, "ARTWORK", 6, "control")
    ns.AttachSquare(b)
    b.label = ns.FS(b, "OVERLAY", "GameFontNormal")
    -- Pinned to the same size every button caption draws at, rather than
    -- whatever the template happens to carry.
    ns.SetFontSize(b.label, (app.skin and app.skin.buttonFontSize) or 12)
    b.label:SetPoint("CENTER")
    return b
end

local function BarOnClick(self)
    local app, level = self.app, self.navLevel
    local path = {}
    for i = 1, level - 1 do path[i] = app.route[i] end
    path[level] = self.navId
    ns.nav.Navigate(app, path)
end
-- An unselected button is not hidden, it is painted at zero alpha: the two
-- textures always exist, so selecting one is a recolor rather than a
-- show/hide, and nothing can be left showing by a missed branch.
local function PaintBarButton(app, b, selected, hovered)
    local skin = app.skin
    b.isSelected = selected

    -- Square style: no pill, a flat fill that is the whole of the button's
    -- share of the bar, and rules where it meets its neighbors. The color
    -- still says selected and hovered -- only the SHAPE changes.
    if b.sqStyle then
        if b.face then b.face:Hide() end
        local c
        if selected then
            local ad = skin.accentDim
            c = { ad[1], ad[2], ad[3], (ad[4] or 0.18) + 0.10 }
        elseif hovered then
            local h = skin.hoverBg
            c = { h[1], h[2], h[3], (h[4] or 0.06) + 0.06 }
        else
            c = { 0, 0, 0, 0 }
        end
        ns.PaintSquare(b, skin, true, { fill = c, right = b.sqRightOn,
                                        top = b.sqTopOn, left = b.sqLeftOn })
        -- Selected takes the selected-text token; hovered takes the plain
        -- text color. They are the same white by default and differ in
        -- their fill, and a skin that repaints one repaints every selected
        -- label in the panel with it.
        local t = skin.navText or skin.text
        if selected then
            b.label:SetTextColor(SelectedText(skin))
        else
            b.label:SetTextColor(t[1], t[2], t[3])
        end
        local lit0 = (not ns.search) or ns.search.RouteMatches(app, b.navKey)
        b:SetAlpha(lit0 and 1 or ns.search.DimAlpha())
        return
    end
    ns.PaintSquare(b, skin, false)

    -- The relief shows wherever the button has a fill to raise: always in
    -- the navigation style, and on the rounded pill only once it is
    -- selected or hovered -- at rest that pill is transparent, and relief
    -- over nothing is a ghost of a button.
    if b.face then
        local raised = b.navStyle or selected or hovered
        b.face:SetVertexColor(1, 1, 1, raised and ns.FaceAlpha(skin, 1) or 0)
    end

    -- NAVIGATION style: the same rounded pill, but drawn the way the rail's
    -- action cells are -- a border and a fill at rest rather than nothing
    -- until you touch it. The bar then reads as a row of buttons like Setup
    -- Mode and Unlock, which is what it is. Selection is unchanged: the
    -- accent border and the tinted fill still say which section you are on.
    if b.navStyle and not selected then
        local bg = skin.buttonNavBg or skin.railBg
        local ac = skin.accent
        local t  = skin.buttonNavText or skin.text
        -- The accent border at rest as well as hovered (owner, 2026-09-15):
        -- a nav button is a button all the time, so it wears the border the
        -- hover used to bring; the hover then brightens it. The label is
        -- white at full strength in both states -- dimmed to 80% at rest it
        -- read as grayed out, not as resting.
        if hovered then
            local h = skin.hoverBg
            local lift = (h[4] or 0.06) + 0.09
            b.bg:SetVertexColor(bg[1] + lift, bg[2] + lift, bg[3] + lift, 1)
            b.border:SetVertexColor(ac[1], ac[2], ac[3], skin.navBorderHoverAlpha or 0.90)
        else
            b.bg:SetVertexColor(bg[1] + 0.04, bg[2] + 0.04, bg[3] + 0.04, 1)
            b.border:SetVertexColor(ac[1], ac[2], ac[3], skin.navBorderAlpha or 0.45)
        end
        b.label:SetTextColor(t[1], t[2], t[3])
        local litNav = (not ns.search) or ns.search.RouteMatches(app, b.navKey)
        b:SetAlpha(litNav and 1 or ns.search.DimAlpha())
        return
    end

    if selected then
        local ac, ad = skin.accent, skin.accentDim
        b.border:SetVertexColor(ac[1], ac[2], ac[3], 0.75)
        b.bg:SetVertexColor(ad[1], ad[2], ad[3], ad[4] or 0.18)
        -- The accent border and the tinted fill are what mark the selection;
        -- the label takes the same selected-text token the rail's rows and
        -- the tabs do.
        b.label:SetTextColor(SelectedText(skin))
    elseif hovered then
        local ac, h = skin.accent, skin.hoverBg
        b.border:SetVertexColor(ac[1], ac[2], ac[3], skin.navBorderHoverAlpha or 0.90)
        b.bg:SetVertexColor(h[1], h[2], h[3], h[4] or 0.06)
        local t = skin.navText or skin.text
        b.label:SetTextColor(t[1], t[2], t[3])
    else
        b.border:SetVertexColor(0, 0, 0, 0)
        b.bg:SetVertexColor(0, 0, 0, 0)
        local t = skin.navText or skin.text
        b.label:SetTextColor(t[1], t[2], t[3])
    end

    -- A section with no matches fades, exactly as the rail tree's rows do.
    -- The bar and the tree render the same routes; they should not disagree
    -- about which of them the query touched.
    local lit = (not ns.search) or ns.search.RouteMatches(app, b.navKey)
    b:SetAlpha(lit and 1 or ns.search.DimAlpha())
end

local function BarOnEnter(self)
    if self.isSelected then return end
    PaintBarButton(self.app, self, false, true)
end
local function BarOnLeave(self)
    if not self.isSelected then PaintBarButton(self.app, self, false, false) end
end

local function RenderButtonBar(app, nav, level, regionName)
    local region = app:GetRegion(regionName)
    local skin   = app.skin
    nav.buttons = nav.buttons or {}

    local nodes, selectedId = ns.nav.NodesAtLevel(app, level)

    -- Same signature trick as the tree: the set of buttons at level 1 only
    -- changes when the route tree does, so switching section is a repaint.
    -- The room the buttons actually have, and what is eating into it.
    local reserve, side = ns.search.TopReserve(app, regionName)
    local avail = math.floor((region:GetWidth() or 0) + 0.5)

    local parts = {}
    for i, node in ipairs(nodes) do parts[i] = node.id end
    -- Everything that can change the layout goes in the signature, or the
    -- fast path below returns a bar that is laid out for conditions that no
    -- longer hold. That is not hypothetical: leaving the search reserve out
    -- meant moving the box left and back again left the buttons pushed
    -- across, because the button set was identical and nothing repainted.
    -- The width is here for the same reason -- wrapping depends on it, so a
    -- narrower panel has to re-wrap.
    parts[#parts + 1] = "q:" .. tostring(app.searchText or "")
    parts[#parts + 1] = "r:" .. reserve .. ":" .. tostring(side)
    parts[#parts + 1] = "w:" .. avail
    parts[#parts + 1] = "s:" .. tostring(nav.style)
    -- The FACE, because a face has a width: the buttons are sized to their
    -- captions, so swapping the panel font with the button set unchanged
    -- must still be a re-layout, not a repaint of last font's widths.
    parts[#parts + 1] = "f:" .. tostring(ns.PanelFace and ns.PanelFace() or "")
    local sig = table.concat(parts, "|")

    -- The route key a button stands for. A bar at level 1 is just the node
    -- id, but a deeper one is the current route's prefix plus the id -- the
    -- id alone would never match an indexed key and every button would fade.
    local prefix = ""
    for i = 1, level - 1 do
        prefix = prefix .. (app.route[i] or "") .. "/"
    end

    if nav.sig == sig then
        if nav.selKey ~= selectedId then
            for _, b in ipairs(nav.buttons) do
                PaintBarButton(app, b, b.navId == selectedId)
            end
            nav.selKey = selectedId
        end
        return
    end

    -- Where the first row starts, and where every row must stop.
    --
    -- Sharing the title bar means starting after the title rather than at
    -- the region's left edge, and a search box takes its width off one end:
    -- on the left it moves the origin, on the right it pulls the limit in.
    -- Both are measured once and apply to every wrapped row, so the bar
    -- stays a rectangle rather than a staircase.
    local x0 = 8
    -- IsShown, not merely present: a full-height-rail layout moves the
    -- title into the rail's head and hides this copy, and a bar that
    -- started after a title nobody can see began with a gap it could not
    -- account for.
    if regionName == "titlebar" and app.titleText and app.titleText:IsShown() then
        local tr, rl = app.titleText:GetRight(), region:GetLeft()
        if tr and rl then x0 = tr - rl + 18 end
    end
    if side == "left" then x0 = x0 + reserve end

    -- A square bar runs to the region's edge unless something is already
    -- there. With the region to itself it starts flush at 0 and the panel's
    -- own edge closes it; sharing the title bar, it keeps its origin after
    -- the logo and draws a rule of its own instead. So the rule appears
    -- exactly when the edge is occupied, which is the only case that needs
    -- one.
    local sharesEdge = (regionName == "titlebar") or (side == "left")
    if nav.style == "square" and not sharesEdge then x0 = 0 end

    -- Before the first LayoutRegions the region has no width yet. Wrapping
    -- against zero would put every button on its own row; a single row is
    -- the better guess, and the width is in the signature, so the render
    -- that follows the first layout re-wraps against the real number.
    local limit = (avail > 0) and (avail - 8) or math.huge
    if side == "right" and avail > 0 then limit = limit - reserve end
    -- Whichever region the close button is actually parented to keeps room
    -- for it. Naming the title bar outright was right while that was the
    -- only region it could be in; a full-height-rail layout puts it in the
    -- top strip, and a bar that wrapped against the full width drew its
    -- last button underneath it.
    if app.closeButton and app.closeButton:GetParent() == region and avail > 0 then
        limit = math.min(limit, avail - (app.closeButton:GetWidth() or 26) - 12)
    end

    -- WRAPPING.
    --
    -- A row that cannot fit the next button starts a new one, and the
    -- region grows to hold them. The alternative -- one row, clipped -- is
    -- worse than it sounds: the sections that fall off the end are not
    -- merely ugly, they are unreachable, and nothing on screen says they
    -- exist.
    --
    -- A button always goes on the row it starts, even if it is wider than
    -- the whole row on its own: wrapping it to the next line would not make
    -- it fit and would leave an empty row above it.
    -- Square style: the buttons abut, with rules where they meet. The gap
    -- between them and between rows closes to nothing, because a gap is
    -- what stops a divided bar reading as one strip -- the same rule the
    -- rail's footer follows.
    local square  = (nav.style == "square")
    -- The third style. Its GEOMETRY is the rounded bar's -- the difference
    -- is entirely in PaintBarButton -- so it takes the same gaps and inset.
    local navlike = (nav.style == "nav")
    local btnGap  = square and 0 or 4
    local rowGap  = square and 0 or ROW_GAP
    local inset   = square and 0 or ROW_INSET

    local x, rows = x0, 1
    for i, node in ipairs(nodes) do
        local b = nav.buttons[i]
        if not b then
            b = app:Acquire("navBarButton", BarButtonFactory)
            nav.buttons[i] = b
        end
        b.app, b.navId, b.navLevel = app, node.id, level
        b.navKey = prefix .. node.id
        b:SetParent(region)
        b.label:SetText(node.title or node.id)
        b:SetWidth(math.ceil(b.label:GetStringWidth() + 22))

        local w = b:GetWidth()
        local wrapped = false
        if x > x0 and (x + w) > limit then
            rows = rows + 1
            x = x0
            wrapped = true
        end

        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", region, "TOPLEFT", x,
                   -(inset + (rows - 1) * (BUTTON_HEIGHT + rowGap)))
        b:Show()

        -- A rule on the right of every button but the last of its row, and
        -- on top of any button that is not in the first row. Which button
        -- ends a row is only known once the NEXT one has been measured, so
        -- the right-hand rule is settled in a second pass below.
        b.sqStyle    = square
        b.navStyle   = navlike
        b.sqRow      = rows
        b.sqTopOn    = square and rows > 1
        b.sqRightOn  = square
        -- Only the very first button, and only when something else holds
        -- the edge. A wrapped row starts at the same origin, so a rule
        -- there would sit against the bar's own left edge on every row but
        -- the first -- a line down the middle of nothing.
        b.sqLeftOn   = square and sharesEdge and i == 1


        PaintBarButton(app, b, node.id == selectedId)
        b:SetScript("OnClick", BarOnClick)
        b:SetScript("OnEnter", BarOnEnter)
        b:SetScript("OnLeave", BarOnLeave)

        x = x + w + btnGap
    end
    local needed = inset * 2 + rows * BUTTON_HEIGHT + (rows - 1) * rowGap

    -- What ONE row of this bar comes to, published for anything that wants
    -- to line up with the bar's FIRST row rather than with the band as a
    -- whole. The rail's head is the case: it sits beside this bar, and a
    -- bar that wraps must not drag the rail's logo down with it.
    local oneRow = inset * 2 + BUTTON_HEIGHT
    if regionName == "titlebar" then
        app.titlebarRowHeight = math.max(skin.titlebarHeight, oneRow)
    else
        app.topRowHeight = oneRow
    end

    -- Second pass, for everything the first could not know yet: which
    -- button ends its row, and how tall a row is.
    --
    -- The bar's own height is not the sum of its buttons in square style.
    -- A title bar has a MINIMUM height of its own, so a single row of 24px
    -- buttons sits in a 36px band and its rules span the button rather than
    -- the band -- which is what "the dividers do not span the full height"
    -- was here. The band is divided into equal rows instead, so a rule runs
    -- from the top of the bar to the bottom of it.
    if square then
        local barH = needed
        if regionName == "titlebar" then
            barH = math.max(skin.titlebarHeight, needed)
        end
        local rowH = barH / rows
        for i = 1, #nodes do
            local b = nav.buttons[i]
            if b then
                    b:SetHeight(rowH)
                local pt, rel, relPt, xo = b:GetPoint(1)
                b:ClearAllPoints()
                b:SetPoint(pt, rel, relPt, xo, -((b.sqRow - 1) * rowH))
                PaintBarButton(app, b, b.navId == selectedId)
            end
        end
        needed = barH
    end
    for i = #nav.buttons, #nodes + 1, -1 do
        app:Release(nav.buttons[i]); nav.buttons[i] = nil
    end

    nav.sig, nav.selKey = sig, selectedId

    -- Tell the frame how tall the bar turned out.
    --
    -- Height does not feed back into the wrap: both regions span the full
    -- frame width, so growing them taller cannot change how many buttons
    -- fit on a row. That is what makes one measuring pass enough and why
    -- there is no re-entry to guard against here.
    if regionName == "titlebar" then
        if (app.titlebarHeight or 0) ~= needed then
            app.titlebarHeight = needed
            ns.LayoutRegions(app)
        end
    else
        if (app.topHeight or 0) ~= needed then
            app.topHeight = needed
            ns.LayoutRegions(app)
        end
    end
end

-- ── Chrome declaration and refresh ─────────────────────────────

-- ── Navigator: list (flat, no disclosure) ──────────────────────
--
-- The tree with its branches taken away: one row per sibling at this
-- level, no chevrons, no nesting. For a level whose children are all
-- leaves, where a disclosure control is a control that never does
-- anything.
--
-- It reuses the tree's rows and its render wholesale rather than growing a
-- second row implementation -- the only difference is which rows are
-- produced, so that is the only thing that differs.
local function RenderList(app, nav, level)
    local prev = app.bpFlatNav
    app.bpFlatNav = true
    RenderTree(app, nav, level)
    app.bpFlatNav = prev
end

-- ── Navigator: tabs (a strip above the page) ───────────────────
--
-- Contextual, not app-level. A node declares `navigator = "tabs"` and its
-- CHILDREN become a strip in the page header, which is what a collection
-- of two to six members wants -- the members are the page, and a rail
-- branch for them is both further away and a level of indentation nobody
-- asked for.
--
-- Mounted from the active route rather than from SetChrome: the strip
-- belongs to a node, appears when that node is on the route, and is gone
-- when it is not. §8's contextual chrome, in the one case that has a
-- consumer.

local TAB_H       = 22
local TAB_GAP     = 4      -- between tabs on a row
local TAB_ROW_GAP = 3      -- between rows, button style
local TAB_PAD_TOP = 4      -- band top to the first row
local TAB_RADIUS  = 6

-- The rule under a tab strip is the CARD's border, so its weight is the
-- card's stroke rather than a pixel -- and every piece of arithmetic about
-- the strip has to agree about that number: the height reserves it, the
-- rule is drawn at it, and the gap the selected tab leaves is inset by it.
-- One function, asked three times.
--
-- UI UNITS, and a WHOLE number of them -- deliberately not the physical
-- pixel this library converts to elsewhere. The strip's height is built
-- from this, and the height is compared for equality by SetCtxNavHeight
-- and MountContextual to decide whether the page header has to be laid out
-- again. Scaled by ns.PixelUnit it came out fractional AND dependent on
-- whether the frame had a resolved scale when it was asked, so the two
-- answers disagreed, every render re-laid the header out, and the tab
-- buttons were re-anchored under the reader's cursor -- clicks landing on
-- a button that had just moved, which reads as a strip that mostly does
-- not respond. A stable integer is worth more here than a hairline's
-- accuracy in the rule's weight.
local function TabRuleStroke()
    return (ns.BorderStroke and ns.BorderStroke("card")) or 1
end

-- Which look a strip wears. A node says so for itself; otherwise the app's
-- own default; otherwise buttons, which is what the library has always
-- drawn -- so nothing changes appearance until somebody asks it to.
--
--   node.tabStyle = "button" | "tab"
--   app:SetTabStyle("button" | "tab")
--
-- "button" is a row of rounded pills, each closed on all four sides.
-- "tab" is the classic arrangement: square-bottomed tabs sitting ON a rule
-- that runs the width of the page, the selected one leaving the rule
-- broken beneath it and taking no fill, so it reads as continuous with the
-- page below rather than as a control above it.
local function TabStyle(app, owner)
    local s = owner and owner.node and owner.node.tabStyle
    if s == nil then s = app.tabStyle end
    return (s == "tab") and "tab" or "button"
end

local function TabFactory(app)
    local b = CreateFrame("Button", nil, app:GetRegion("pageheader"))
    b:SetHeight(TAB_H)
    -- ONE shape, re-sided. RoundedFill's corners are a live knob, so the
    -- two looks are the same two textures with their bottom corners round
    -- or square -- not two sets shown and hidden in turn, which is how a
    -- surface ends up drawn twice at compounded alpha (see RoundedFill).
    local ringPaint, ringRadius, ringInset, ringSides =
        ns.RoundedFill(b, "BACKGROUND", TAB_RADIUS, "", nil, 0)
    local surfPaint, surfRadius, surfInset, surfSides, surfInsetBottom =
        ns.StrokedFill(b, "BORDER",     TAB_RADIUS, "", nil, "card")
    b.paintRing, b.sidesRing = ringPaint, ringSides
    b.paintSurf, b.sidesSurf = surfPaint, surfSides
    -- How a SELECTED tab loses its bottom edge: the fill runs out to the
    -- frame's bottom, over the ring's own bottom stroke. Nothing is patched
    -- and no color is guessed -- the edge simply is not drawn.
    b.bottomSurf = surfInsetBottom
    -- Unused today, and named rather than discarded: the radius and inset
    -- of a tab are the same live knobs every other surface has, and a
    -- future skin token for either has somewhere to arrive.
    b.radiusRing, b.insetRing = ringRadius, ringInset
    b.radiusSurf, b.insetSurf = surfRadius, surfInset
    -- The same affordance the rail rows and the group cards use. Hidden
    -- unless this tab turns out to be a draggable collection member.
    b.grip = ns.reorder.AttachGrip(b)
    b.grip:SetPoint("LEFT", b, "LEFT", 7, 0)
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    -- At the CARD HEADER's size (the button size, skin.buttonFontSize):
    -- a tab names the card set under it, and drawn smaller than the card
    -- headers it stands over, the strip read as an afterthought.
    ns.SetFontSize(b.label, (app.skin and app.skin.buttonFontSize) or 12)
    b.label:SetPoint("LEFT",  b, "LEFT",   8, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    return b
end

-- Tabs of the same collection, in screen order. A tab strip shows one
-- node's children with no section headings among them, so there is nothing
-- to move BETWEEN -- `across` stays a tree-only affair and this is always
-- the plain within-a-list case.
local function TabSiblings(tab)
    local nav = tab.navNav
    local out = {}
    for _, b in ipairs((nav and nav.buttons) or {}) do
        if b:IsShown() and b.navNode and b.navNode.bpMember
           and b.navNode.bpCollection == tab.navNode.bpCollection then
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    return out
end

local function InstallTabDrag(app, nav, b)
    b.navNav = nav
    local node = b.navNode
    local coll = node and node.bpCollection
    local spec = coll and coll.reorder
    local can  = spec and spec.onMove and node.bpMember
                 and not ns.collections.IsPinned(coll, node.bpMember)
                 and true or false

    local showGrip = can and spec.grip ~= false
    b.grip:SetShown(showGrip)
    -- The label makes room for the grip only when there is one, so a strip
    -- with nothing draggable in it looks exactly as it did.
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT",  b, "LEFT", showGrip and (7 + ns.reorder.GRIP_W + 4) or 8, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    if showGrip then ns.reorder.PaintGrip(b.grip, app.skin, false) end

    if not can then
        ns.reorder.Install(b, nil)
        return
    end
    ns.reorder.Install(b, {
        axis       = "x",
        siblings   = TabSiblings,
        pinned     = function(f)
            return ns.collections.IsPinned(coll, f.navNode and f.navNode.bpMember)
        end,
        color     = function() return app.skin.accent end,
        lineParent = function() return app:GetRegion("pageheader") end,
        onStart    = function() ns.reorder.PaintGrip(b.grip, app.skin, true) end,
        onEnd      = function() ns.reorder.PaintGrip(b.grip, app.skin, false) end,
        blocked    = function()
            return spec.combat ~= false and InCombatLockdown()
        end,
        onDrop = function(from, to, sibs)
            local moving = sibs[from] and sibs[from].navNode
            local target = sibs[to]   and sibs[to].navNode
            if not (moving and target and moving.bpMember and target.bpMember) then
                return
            end
            ns.collections.Move(app, coll.id, moving.bpMember.key, target.bpMember.index)
        end,
    })
end

-- One tab token as a paint color, with an optional alpha multiplier for
-- the hover lift. Nil-safe: a skin that predates these tokens paints
-- nothing rather than erroring.
local function TabColor(c, mul)
    if not c then return { 0, 0, 0, 0 } end
    local a = (c[4] or 1) * (mul or 1)
    if a > 1 then a = 1 end
    return { c[1], c[2], c[3], a }
end

local function PaintTab(app, b, selected, hovered, style)
    local skin = app.skin
    style = style or b.tabStyle or "button"
    local tab = (style == "tab")

    -- The bottom corners: square where the tab meets the rule, round where
    -- it is a pill. Re-sided rather than rebuilt, and only when it CHANGES
    -- -- setSides re-places nine textures, and a strip repaints on every
    -- hover.
    local want = tab and "B" or ""
    if b.tabSides ~= want then
        b.tabSides = want
        b.sidesRing(want)
        b.sidesSurf(want)
    end

    -- 2026-09-14 (owner ruling): THE SELECTED TAB KEEPS ITS BOTTOM EDGE.
    -- It used to run open into the page through a break in the rule; with
    -- rows no longer reordering, a selected tab on an upper row had to keep
    -- its edge anyway, and the closed shape was preferred on every row. The
    -- rule below the strip is unbroken to match. Restated on every paint so
    -- a pooled button never carries the old inset.
    if b.bottomSurf then b.bottomSurf(nil) end

    local ac = skin.accent
    -- A skin that predates the six tab tokens has none of them, and the
    -- derivation below is exactly what it used to get -- so a missing token
    -- means "derive", not "paint nil".
    if skin.tabUseAccent or not (skin.tabSelText and skin.tabText) then
        -- The original derivation, kept whole: the accent decides a
        -- selected tab, the control tokens decide an unselected one.
        if selected then
            if tab then
                -- No fill at all. The page below is the panel's own
                -- background, so a selected tab that paints nothing IS the
                -- page, continuous with it through the gap the rule leaves.
                b.paintRing{ ac[1], ac[2], ac[3], 0.85 }
                b.paintSurf{ 0, 0, 0, 0 }
            else
                local ad = skin.accentDim
                b.paintRing{ ac[1], ac[2], ac[3], 0.75 }
                b.paintSurf{ ad[1], ad[2], ad[3], ad[4] or 0.18 }
            end
            b.label:SetTextColor(AccentText(ac))
        else
            local br, bg = skin.controlBorder, skin.controlBg
            if tab then
                -- An unselected tab is RECESSED: dimmer ring, and a fill a
                -- shade darker than the page, so the row reads as a set of
                -- things behind the one in front.
                b.paintRing{ br[1], br[2], br[3], hovered and 0.85 or 0.5 }
                b.paintSurf{ bg[1], bg[2], bg[3], hovered and 0.9 or 0.6 }
            else
                b.paintRing{ br[1], br[2], br[3], hovered and 0.9 or 0.55 }
                b.paintSurf{ bg[1], bg[2], bg[3], hovered and 1 or 0.75 }
            end
            local t = skin.text
            b.label:SetTextColor(t[1] * 0.85, t[2] * 0.85, t[3] * 0.85)
        end
    elseif selected then
        b.paintRing(TabColor(skin.tabSelBorder))
        if tab then
            -- THE SECTION BAR'S SELECTED BLUE, composited here.
            --
            -- The bar's selected button is built the way this tab is -- a
            -- full-shape ring with the fill drawn inset over it -- so its
            -- accent ring at 0.75 shows straight through its 0.18 fill and
            -- the whole button reads bright blue. That is the blue a
            -- selected tab is compared against.
            --
            -- The tab cannot get there the same way: its ring is the card's
            -- border, so nothing blue is underneath to show through. The
            -- bar's two layers are composited here instead -- the accent at
            -- 0.75 over the page, then the selected fill over that -- and
            -- painted opaque. Read from the skin, so an addon that repaints
            -- its accent moves the tab and the bar together.
            local pg = skin.panelBg
            local ac = skin.accent
            local sb = skin.tabSelBg or skin.accentDim or { 0, 0, 0, 0 }
            local a1, a2 = 0.75, (sb[4] or 0.18)
            local function mix(i)
                return (pg[i] * (1 - a1) + ac[i] * a1) * (1 - a2) + sb[i] * a2
            end
            b.paintSurf{ mix(1), mix(2), mix(3), 1 }
        else
            b.paintSurf(TabColor(skin.tabSelBg))
        end
        local t = skin.tabSelText
        b.label:SetTextColor(t[1], t[2], t[3], t[4] or 1)
    else
        -- Hover lifts the alpha rather than changing the color, which is
        -- what the derivation did (0.55 -> 0.9 on the ring, 0.75 -> 1 on
        -- the fill) expressed as a ratio, so a token set to any alpha
        -- brightens by the same proportion instead of jumping to a fixed
        -- one.
        b.paintRing(TabColor(skin.tabBorder, hovered and 1.6 or 1))
        b.paintSurf(TabColor(skin.tabBg,     hovered and 1.33 or 1))
        local t = skin.tabText
        b.label:SetTextColor(t[1], t[2], t[3], t[4] or 1)
    end
    -- A node may color its own label -- a custom container's tab, say --
    -- exactly as the rail's rows honor it (PaintRow). Resolved at PAINT
    -- time, never baked into the title. The selected tab keeps the strip's
    -- own selected color, as the rail's selected row does.
    if not selected and b.navNode and b.navNode.color then
        local c = b.navNode.color()
        if c then b.label:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end
    local lit = (not ns.search) or ns.search.RouteMatches(app, b.navKey)
    b:SetAlpha(lit and 1 or ns.search.DimAlpha())
end

local function TabOnClick(self)
    -- A plain in-page subtab carries its own click handler and no route to
    -- navigate; a real route tab has navPath and no handler.
    --
    -- The handler is named with the `_bp_` prefix on purpose: that prefix is
    -- what App:Release scrubs, so a button cannot carry one strip's handler
    -- into its next use. Without it, a button that served an in-page strip
    -- and was later handed to a ROUTE strip kept the old closure, and
    -- because the handler wins here the route tab silently re-rendered
    -- someone else's subtab instead of navigating -- a tab that "does
    -- nothing", seemingly at random. Clearing it centrally is what pooled
    -- widget libraries do too: their Release empties the widget's whole
    -- `events` table.
    if self._bp_onSelect then self._bp_onSelect(); return end
    ns.nav.Navigate(self.app, self.navPath)
end
local function TabOnEnter(self) PaintTab(self.app, self, self.isSel, true,  self.tabStyle) end
local function TabOnLeave(self) PaintTab(self.app, self, self.isSel, false, self.tabStyle) end

-- The rule a "tab" strip sits on: one line across the page, BROKEN under
-- the selected tab.
--
-- Two textures rather than one with something painted over the gap. The
-- panel background is translucent, so "the color behind the tab" is not a
-- color this library knows -- the only honest gap is no texture at all.
--
-- Held on the APP rather than on the navigator: one strip is on screen at
-- a time, and a pair of textures per route key is a pair that outlives the
-- route (a navigator is unmounted by releasing its buttons; a texture
-- cannot be released).
-- The rule under a tab strip, and the gap the selected tab leaves in it.
--
-- One pair PER NAVIGATOR, not per app: with two strips mounted, a single
-- shared pair meant the inner one re-anchored the outer one's rule to its
-- own row, and the outer strip lost its underline. They hang off the nav
-- rather than the pool because they are not interchangeable -- each is
-- anchored for the life of its own strip.
local function TabRule(app, nav)
    local holder = nav or app
    if not holder.tabRuleL then
        local region = app:GetRegion("pageheader")
        holder.tabRuleL = region:CreateTexture(nil, "ARTWORK")
        holder.tabRuleR = region:CreateTexture(nil, "ARTWORK")
    end
    return holder.tabRuleL, holder.tabRuleR
end

-- The strip's height for the row count it turned out to need. A tab style
-- finishes ON the rule, so it reserves the rule's own weight below the last
-- row; a button style keeps a gap, because a pill sitting flush against the
-- page reads as a broken tab.
-- `flush` is the page below saying it opens with a band: a pill landing on
-- a band is not a pill sitting against the page, so the gap goes. A "tab"
-- style keeps its rule either way -- that band IS the rule.
--
-- RESERVED, not borrowed. It used to reserve exactly one pixel, and once
-- the rule became two the second one came out of the tab row: the rule
-- climbed over the tabs' bottom corners, and under the SELECTED tab -- the
-- one whose gap is meant to show the page through it -- what showed instead
-- was the strip's own background, a dark line across the very seam the gap
-- exists to open.
local function TabsHeight(rows, style, flush)
    local bottom = (style == "tab") and TabRuleStroke()
                   or (flush and 0 or 6)
    return TAB_PAD_TOP + rows * TAB_H + (rows - 1) * TAB_ROW_GAP + bottom
end

-- The page's width, DERIVED rather than read.
--
-- region:GetWidth() is anchor-derived and still reports the PREVIOUS pass's
-- number immediately after LayoutRegions -- the trap the footer (27.15) and
-- the rail tree (27.17) both fell into, and packing tabs is exactly the
-- kind of arithmetic it silently ruins. The panel's width and the rail's
-- are values this library sets, so they are known now.
local function PageWidth(app)
    local w = (app.frame and app.frame:GetWidth()) or 0
    if app.railShown ~= false then
        local skin = app.skin
        local railMin = math.max(skin.railWidthMin,
                        (app.footerSpan == "full") and 0 or (app.footerMinWidth or 0))
        w = w - math.max(railMin,
            math.min(skin.railWidthMax, app.railWidth or skin.railWidth))
    end
    return w
end

-- The contextual band is as tall as every navigator mounted in it ADDED
-- UP, and a wrapping strip only knows its own height once it has packed.
-- So it reports it here, and the band follows -- rather than the band being
-- a constant that a second row grows out of, unseen.
--
-- This was `math.max` until nesting was supported, which was right while
-- only one navigator could ever be mounted and wrong the moment two were:
-- a section with a tab strip whose child also has one mounts both, and
-- taking the tallest gave the band room for exactly one of them, so the
-- inner strip drew on top of the outer.
local function SetCtxNavHeight(app, nav, height)
    nav.dynHeight = height
    local total = 0
    for _, other in pairs(app.ctxNavs or {}) do
        total = total + (other == nav and height
            or (other.dynHeight or (other.def and other.def.height) or 0))
    end
    if (app.ctxNavHeight or 0) == total then return end
    app.ctxNavHeight = total
    local want = ns.chrome.PageHeaderHeight(app)
    if (app.pageheaderHeight or 0) ~= want then
        app.pageheaderHeight = want
        ns.LayoutRegions(app)
    end
end

local function RenderTabs(app, nav)
    local region = app:GetRegion("pageheader")
    local owner  = nav.ownerEntry
    nav.buttons  = nav.buttons or {}

    local kids   = owner and KidsAt(app, owner.key, owner.node) or {}
    local selKey = table.concat(app.route or {}, "/")
    local style  = TabStyle(app, owner)

    -- 1. A button per child, sized. Every width has to be known before
    --    anything can be placed: where a tab goes depends on whether the
    --    one before it left room on the row.
    for i, node in ipairs(kids) do
        local b = nav.buttons[i]
        if not b then
            b = app:Acquire("navTab", TabFactory)
            nav.buttons[i] = b
        end
        local path = {}
        for j = 1, #owner.path do path[j] = owner.path[j] end
        path[#path + 1] = node.id

        b.app, b.navPath, b.navNode = app, path, node
        b.navKey   = table.concat(path, "/")
        b.tabStyle = style
        -- A route tab navigates and nothing else. Said unconditionally, on
        -- every render, rather than trusted to the pool: a button reused in
        -- place (never released between the two uses) is not scrubbed, and
        -- one stale in-page handler here swallows the click entirely.
        -- Other libraries rewrite every tab's `value` on every rebuild for
        -- the same reason -- identity is restated, not inherited.
        b._bp_onSelect = nil
        b:SetParent(region)
        -- Before the width is taken, because the grip widens the tab.
        InstallTabDrag(app, nav, b)
        b.label:SetText(ns.search.Mark(app, node.title or node.id))
        b:SetWidth(math.ceil(b.label:GetStringWidth() + 22
                   + (b.grip:IsShown() and (ns.reorder.GRIP_W + 4) or 0)))
        -- A tab is selected when the route passes THROUGH it, not only when
        -- it is the leaf: a member with its own sub-pages still has to look
        -- selected while one of them is showing.
        b.isSel = RouteWithin(selKey, b.navKey)
    end
    for i = #nav.buttons, #kids + 1, -1 do
        app:Release(nav.buttons[i]); nav.buttons[i] = nil
    end

    -- 2. Pack into rows.
    --
    -- Six real subtab names are wider than the page at any sane size --
    -- Icons is some 745px of tabs in a 684px page at the default width --
    -- and a strip that cannot wrap draws the last of them off the right
    -- edge, where they are not merely ugly but unreachable.
    local limit = math.max(120, PageWidth(app) - 16)
    local rows, row, used = {}, {}, 0
    for _, b in ipairs(nav.buttons) do
        local w = b:GetWidth()
        if #row > 0 and used + TAB_GAP + w > limit then
            rows[#rows + 1] = row
            row, used = {}, 0
        end
        used = used + ((#row > 0) and TAB_GAP or 0) + w
        row[#row + 1] = b
    end
    if #row > 0 then rows[#rows + 1] = row end
    if #rows == 0 then rows[1] = {} end

    -- 2026-09-14 (owner ruling): rows stay in DECLARATION order. The
    -- selected tab's row used to be moved LAST (the classic rule, so the tab
    -- that breaks the rule always sits on it) -- which read as the strip
    -- flowing UPWARDS: select a first-row tab and the one tab that wrapped
    -- appeared above the rest. A wrapped tab now always lands below; the
    -- selected tab keeps its bottom edge on every row and the rule runs
    -- unbroken beneath the last row (PaintTab).

    -- 3. Place, paint, wire. Each tab remembers its own x, because the rule
    --    below needs to know where the selected one starts and ends.
    local top0 = ns.chrome.CtxNavTopFor(app, nav) + TAB_PAD_TOP
    for r, entries in ipairs(rows) do
        local x = 8
        local y = top0 + (r - 1) * (TAB_H + TAB_ROW_GAP)
        for _, b in ipairs(entries) do
            b.tabX = x
            b:ClearAllPoints()
            -- In the contextual navigator's own band, below the breadcrumb.
            b:SetPoint("TOPLEFT", region, "TOPLEFT", x, -y)
            b:Show()
            PaintTab(app, b, b.isSel, false, style)
            b:SetScript("OnClick", TabOnClick)
            b:SetScript("OnEnter", TabOnEnter)
            b:SetScript("OnLeave", TabOnLeave)
            x = x + b:GetWidth() + TAB_GAP
        end
    end

    -- 4. The rule, and the gap the selected tab leaves in it.
    local height = TabsHeight(#rows, style,
        ns.page and ns.page.OpensWithBand and ns.page.OpensWithBand(app))
    local ruleL, ruleR = TabRule(app, nav)
    if style == "tab" then
        -- THE RULE IS THE CARD BORDER, in color and in weight.
        --
        -- A tab strip is the top edge of the surface below it, and the tabs
        -- themselves are drawn with the card stroke -- so a rule in the
        -- divider color at a fixed single pixel was a lighter, thinner line
        -- meeting two heavier ones at every tab. `groupBorder` and the card
        -- stroke are the two numbers the cards use; this reads them rather
        -- than restating them, so a skin that repaints its cards repaints
        -- this with them.
        local c      = app.skin.groupBorder or app.skin.divider
        local stroke = TabRuleStroke()
        local ruleY  = ns.chrome.CtxNavTopFor(app, nav) + height - stroke
        -- 2026-09-14 (owner ruling): ONE UNBROKEN LINE. The rule used to
        -- break under the selected tab (anchored to the tab's own bottom
        -- corners) because that tab had no bottom edge and ran through the
        -- gap into the page. The selected tab keeps its edge now (PaintTab),
        -- and a gap would only show that edge sitting in a hole. The right
        -- piece stays allocated and hidden: it is a texture on the region,
        -- and a strip that ever drew one cannot pool it away.
        ruleL:ClearAllPoints()
        ruleL:SetHeight(stroke)
        ruleL:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -ruleY)
        ruleL:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, -ruleY)
        ruleR:Hide()
        ruleL:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        if ns.NoSnap then ns.NoSnap(ruleL) end
        ruleL:Show()
    else
        ruleL:Hide()
        ruleR:Hide()
    end

    SetCtxNavHeight(app, nav, height)
end


-- ── A tab strip inside a frame that is not the page header ─────
--
-- The same tabs, drawn wherever a caller has a frame for them: the tree
-- group's pane, where a member's subtabs sit under the member's own
-- header and above its scrolling settings. RenderTabs cannot be reused
-- directly because everything about it -- the region, the band's top, the
-- page width, the height it reports to the chrome -- is the page header's.
-- This takes a host and a width, places from the host's top-left, and
-- returns the height it used; the caller anchors what goes beneath.
--
-- `items` are ready-made: { key, title, path, selected }, one per tab, in
-- strip order. `nav` is the caller's own table, kept per strip so the
-- buttons and the rule are reused across renders -- the pool hands the
-- buttons out, but the rule is a pair of textures and cannot be pooled,
-- so it is re-parented to the host instead.
--
--   opts.top     the y the first row starts at, measured down from the
--                host's top (default 0)
--   opts.width   the width to wrap within (default the host's)
--   opts.style   "tab" | "button"; default the app's, then "button"
--   opts.inset   the strip's left margin (default 8, the header's)
function ns.nav.RenderTabStripInto(app, nav, host, items, opts)
    opts = opts or {}
    nav.buttons = nav.buttons or {}
    local style = opts.style
    if style == nil then style = app.tabStyle end
    style = (style == "tab") and "tab" or "button"
    local inset = opts.inset or 8

    for i, it in ipairs(items) do
        local b = nav.buttons[i]
        if not b then
            b = app:Acquire("navTab", TabFactory)
            nav.buttons[i] = b
        end
        b.app, b.navPath, b.navNode = app, it.path, it.node
        b.navKey   = it.key
        b._bp_onSelect = it.onSelect or nil
        b.tabStyle = style
        b.navNav   = nav
        b:SetParent(host)
        -- Never draggable: a member's subtabs are declared, not ordered.
        b.grip:Hide()
        ns.reorder.Install(b, nil)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT",  b, "LEFT",   8, 0)
        b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.label:SetText(ns.search.Mark(app, it.title or it.key))
        b:SetWidth(math.ceil(b.label:GetStringWidth() + 22))
        b.isSel = it.selected and true or false
    end
    for i = #nav.buttons, #items + 1, -1 do
        app:Release(nav.buttons[i]); nav.buttons[i] = nil
    end

    -- Pack into rows, the same way the header strip does.
    local width = opts.width or host:GetWidth() or 0
    local limit = math.max(120, width - inset * 2)
    local rows, row, used = {}, {}, 0
    for _, b in ipairs(nav.buttons) do
        local w = b:GetWidth()
        if #row > 0 and used + TAB_GAP + w > limit then
            rows[#rows + 1] = row
            row, used = {}, 0
        end
        used = used + ((#row > 0) and TAB_GAP or 0) + w
        row[#row + 1] = b
    end
    if #row > 0 then rows[#rows + 1] = row end
    if #rows == 0 then rows[1] = {} end
    -- 2026-09-14: no selected-row-last move here either -- see the
    -- page-level strip. Rows flow downwards in declaration order.

    local top0 = (opts.top or 0) + TAB_PAD_TOP
    for r, entries in ipairs(rows) do
        local x = inset
        local y = top0 + (r - 1) * (TAB_H + TAB_ROW_GAP)
        for _, b in ipairs(entries) do
            b.tabX = x
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
            b:Show()
            PaintTab(app, b, b.isSel, false, style)
            b:SetScript("OnClick", TabOnClick)
            b:SetScript("OnEnter", TabOnEnter)
            b:SetScript("OnLeave", TabOnLeave)
            x = x + b:GetWidth() + TAB_GAP
        end
    end

    -- The rule. Its textures are created on the FIRST host and follow the
    -- strip to whichever frame it is drawn in next.
    local height = TabsHeight(#rows, style, false)
    if not nav.tabRuleL then
        nav.tabRuleL = host:CreateTexture(nil, "ARTWORK")
        nav.tabRuleR = host:CreateTexture(nil, "ARTWORK")
    end
    local ruleL, ruleR = nav.tabRuleL, nav.tabRuleR
    if ruleL.SetParent then ruleL:SetParent(host); ruleR:SetParent(host) end
    if style == "tab" then
        -- The card border, in color and weight -- the page-level strip's
        -- rule above and this one are the same line in two hosts.
        local c      = app.skin.groupBorder or app.skin.divider
        local stroke = TabRuleStroke()
        local ruleY  = (opts.top or 0) + height - stroke
        -- `opts.bleed`: space the host reserves at its right that the RULE
        -- should still cross -- the tree pane's scrollbar gutter. The tabs
        -- are packed within `width`; only the rule runs the extra distance,
        -- so the strip meets the card's edge like the bands around it.
        local ruleW = width + (opts.bleed or 0)
        -- 2026-09-14: unbroken, as the page-level strip's rule -- the
        -- selected tab keeps its bottom edge now (PaintTab).
        ruleL:ClearAllPoints()
        ruleL:SetHeight(stroke)
        ruleL:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -ruleY)
        ruleL:SetPoint("TOPRIGHT", host, "TOPLEFT", ruleW, -ruleY)
        ruleR:Hide()
        ruleL:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        if ns.NoSnap then ns.NoSnap(ruleL) end
        ruleL:Show()
    else
        ruleL:Hide()
        ruleR:Hide()
    end
    return height
end

-- Put a strip away: its buttons back to the pool, its rule hidden. For a
-- pane that had tabs on one render and none on the next.
function ns.nav.HideTabStrip(app, nav)
    if not nav then return end
    for i = #(nav.buttons or {}), 1, -1 do
        app:Release(nav.buttons[i]); nav.buttons[i] = nil
    end
    if nav.tabRuleL then nav.tabRuleL:Hide(); nav.tabRuleR:Hide() end
end

-- ── Navigator: dropdown (one level, collapsed to a button) ─────
--
-- The same level a tree branch or a button bar would show, in the width of
-- one control. Two places want this and neither is served by the others:
-- a panel too narrow for a rail, and a collection with more members than a
-- tab strip can hold before it wraps into a wall of buttons.
--
-- It is BOTH app-level and contextual, which no other navigator is. The
-- distinction is only where it was declared -- in a chrome spec it takes a
-- level, and on a node it takes that node's children -- and the two render
-- identically, so `nav.ownerEntry` is the whole difference.
--
-- The menu itself is ns.ShowMenu, the same service the dropdown CONTROL
-- uses. There is one menu frame in the library and this is a second caller
-- of it, not a second copy.

local DDNAV_H = 22

local function DropNavButton(app)
    local b = CreateFrame("Button", nil, app.frame)
    b:SetHeight(DDNAV_H)
    b.border, b.bg = ns.BorderedRound(b, 8, "BACKGROUND", "BORDER")
    ns.SetBorder(b, b.border)
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetTexture(ns.MEDIA .. "chevron.tga")
    b.arrow:SetSize(11, 11)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.arrow:SetRotation(-math.pi / 2)
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("LEFT",  b, "LEFT",   8, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    return b
end

local function RenderDropNav(app, nav)
    local owner = nav.ownerEntry
    local contextual = owner and true or false
    local region = app:GetRegion(contextual and "pageheader" or nav.region)

    -- Where the options come from, and which of them is current.
    local nodes, selId, prefix
    if contextual then
        nodes = KidsAt(app, owner.key, owner.node) or {}
        selId = app.route[#owner.path + 1]
        prefix = owner.key .. "/"
    else
        nodes, selId = ns.nav.NodesAtLevel(app, nav.level)
        prefix = ""
        for i = 1, nav.level - 1 do prefix = prefix .. (app.route[i] or "") .. "/" end
    end

    -- A level with nothing in it gets no button at all.
    --
    -- An empty dropdown is worse than a missing one: it invites a click
    -- that opens nothing. This is the ordinary case for a level-2
    -- navigator on a section that has no subsections, and it must not
    -- advance the region's layout cursor either -- the level-1 dropdown
    -- beside it would shift across to make room for something that is not
    -- being drawn. Released rather than merely hidden, so a level that
    -- later gains children gets a fresh button in the right position.
    if #nodes == 0 then
        if nav.button then
            app:Release(nav.button)
            nav.button = nil
        end
        return
    end

    local b = nav.button
    if not b then
        b = app:Acquire("navDropdown", DropNavButton)
        nav.button = b
    end
    b:SetParent(region)
    b:ClearAllPoints()

    -- Wide enough for the widest option, so picking a longer one does not
    -- resize the button under the reader's cursor. Measured BEFORE it is
    -- placed, because the next navigator in this region starts where this
    -- one ends.
    local widest = 0
    for _, node in ipairs(nodes) do
        b.label:SetText(node.title or node.id)
        widest = math.max(widest, b.label:GetStringWidth())
    end
    b:SetWidth(math.min(math.max(90, math.ceil(widest + 40)), 260))

    local regionKey = contextual and "pageheader" or nav.region
    local x = app.navCursor and app.navCursor[regionKey]
    if not x then
        x = 8
        -- A search box in the same region takes its width off one end,
        -- exactly as it does for a button bar: on the left it moves the
        -- origin, on the right it only pulls the limit in, which a row of
        -- one or two buttons never meets.
        if not contextual then
            local reserve, side = ns.search.TopReserve(app, nav.region)
            if side == "left" then x = x + reserve end
        end
    end
    local y = contextual and (ns.chrome.CtxNavTopFor(app, nav) + 4) or 6
    b:SetPoint("TOPLEFT", region, "TOPLEFT", x, -y)
    if app.navCursor then app.navCursor[regionKey] = x + b:GetWidth() + 6 end

    local skin = app.skin
    local cur
    for _, node in ipairs(nodes) do if node.id == selId then cur = node end end
    b.label:SetText(ns.search.Mark(app, cur and (cur.title or cur.id) or ""))
    b.label:SetTextColor(ns.C(skin.text))
    b.bg:SetVertexColor(ns.C(skin.controlBg))
    b.arrow:SetVertexColor(ns.C(skin.textMuted))
    ns.MarkBorder(b, skin, skin.controlBorder, 1)

    b:SetScript("OnEnter", function(self)
        self.bpHovered = true
        if not self.bpActive then ns.PaintBorder(self, "hover") end
    end)
    b:SetScript("OnLeave", function(self)
        self.bpHovered = false
        if not self.bpActive then ns.PaintBorder(self, nil) end
    end)
    b:SetScript("OnClick", function(self)
        local items = {}
        for i, node in ipairs(nodes) do
            local path = {}
            if contextual then
                for j = 1, #owner.path do path[j] = owner.path[j] end
            else
                for j = 1, nav.level - 1 do path[j] = app.route[j] end
            end
            path[#path + 1] = node.id
            items[i] = {
                text     = node.title or node.id,
                desc     = node.desc,
                selected = (node.id == selId),
                onPick   = function() ns.nav.Navigate(app, path) end,
            }
        end
        ns.ShowMenu(self, app, items)
    end)
    b:Show()

    -- Dimmed with everything else a search has not matched, so the panel
    -- reads as one surface rather than one navigator opting out.
    local lit = (not ns.search) or ns.search.RouteMatches(app, prefix .. tostring(selId))
    b:SetAlpha(lit and 1 or ns.search.DimAlpha())
end


-- ── Navigator: breadcrumb (the path, made clickable) ───────────
--
-- The panel has always drawn the route as text. This makes each segment a
-- target, which is what a path is FOR: three levels down, the way back up
-- is the thing on screen that already names where you are, and asking the
-- reader to find the same node again in the rail is asking them to do the
-- work twice.
--
-- Not every segment is a destination. The LAST one is where you already
-- are; a segment whose node has no `page` of its own is a grouping rather
-- than a place, and ns.nav.Navigate descends straight past it to the first
-- leaf -- which, from inside that branch, is usually where you already are,
-- so the click does nothing. Both are DISABLED rather than omitted: they
-- must be visible for the path to read as a path, and a disabled button
-- fires no OnEnter, so nothing that cannot be clicked lights up under the
-- cursor. It is the same test the tree makes with `navTogglesOnly`.
--
-- Declared in a chrome spec, and when it is, the static breadcrumb stands
-- down (see ns.chrome.RenderBreadcrumb) -- the two draw in the same band
-- and would otherwise sit on top of each other.

local CRUMB_H  = 16
local CRUMB_SEP = "  \194\183  "

local function CrumbButton(app)
    local b = CreateFrame("Button", nil, app.frame)
    b:SetHeight(CRUMB_H)
    b.label = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.label:SetJustifyH("LEFT")
    b.sep = ns.FS(b, "OVERLAY", "GameFontNormalSmall")
    b.sep:SetPoint("LEFT", b.label, "RIGHT", 0, 0)
    return b
end

local function PaintCrumb(app, b, isLast, hovered)
    local skin = app.skin
    local c = isLast and skin.text or skin.textMuted
    if hovered and not isLast then c = skin.accent end
    b.label:SetTextColor(ns.C(c))
    local m = skin.textMuted
    b.sep:SetTextColor(m[1], m[2], m[3], 0.7)
end

local function CrumbOnClick(self) ns.nav.Navigate(self.app, self.navPath) end
local function CrumbOnEnter(self) PaintCrumb(self.app, self, false, true) end
local function CrumbOnLeave(self) PaintCrumb(self.app, self, false, false) end

local function RenderCrumbs(app, nav)
    local region = app:GetRegion("pageheader")
    nav.buttons = nav.buttons or {}
    -- Claimed here rather than in SetChrome, because a chrome spec can name
    -- this navigator for a region that is not currently laid out. Claimed
    -- even when the breadcrumb is switched off, so the static one goes on
    -- standing down and the two can never both appear.
    app.crumbNav = true

    -- SetBreadcrumbShown(false) governs the TRAIL, not just the static
    -- string: PageHeaderHeight stops reserving the band and CtxNavTop moves
    -- the tab strip up into it, so a navigator that kept drawing would draw
    -- under the tabs. Released rather than hidden -- the buttons are pooled,
    -- and a hidden one held here is one the pool cannot hand out.
    if app.breadcrumbShown == false then
        for i = #nav.buttons, 1, -1 do
            app:Release(nav.buttons[i])
            nav.buttons[i] = nil
        end
        return
    end

    local route = app.route or {}
    -- The trail stops where the contextual band does: a page that has
    -- suppressed its section's tab strip (see ns.nav.SuppressedAt) is
    -- standing in for the whole section, and naming the tab that is not
    -- on screen would be a path to somewhere the reader cannot see.
    local n = #route
    if app.ctxNavSuppressedAt and app.ctxNavSuppressedAt < n then
        n = app.ctxNavSuppressedAt
    end
    local x = 12
    for i = 1, n do
        local key = table.concat(route, "/", 1, i)
        local e   = app.routeIndex and app.routeIndex[key]
        local text = (e and (e.node.title or e.node.id)) or route[i]
        local last = (i == n)
        local goes = (not last) and e and e.node.page and true or false

        local b = nav.buttons[i]
        if not b then
            b = app:Acquire("navCrumb", CrumbButton)
            nav.buttons[i] = b
        end
        local path = {}
        for j = 1, i do path[j] = route[j] end
        b.app, b.navPath = app, path

        b:SetParent(region)
        b.label:SetText(ns.search.Mark(app, text))
        b.sep:SetText(last and "" or CRUMB_SEP)
        b:SetWidth(math.ceil(b.label:GetStringWidth() + b.sep:GetStringWidth() + 1))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", region, "TOPLEFT", x, -6)
        PaintCrumb(app, b, last, false)
        b:SetEnabled(goes)
        b:SetScript("OnClick", CrumbOnClick)
        b:SetScript("OnEnter", CrumbOnEnter)
        b:SetScript("OnLeave", CrumbOnLeave)
        b:Show()

        x = x + b:GetWidth()
    end
    for i = #nav.buttons, n + 1, -1 do
        app:Release(nav.buttons[i]); nav.buttons[i] = nil
    end
end

local NAVIGATORS = {
    tree      = { region = "rail", render = function(app, nav) RenderTree(app, nav, nav.level) end },
    list      = { region = "rail", render = function(app, nav) RenderList(app, nav, nav.level) end },
    buttonbar = { region = "top",  height = BUTTON_HEIGHT + 12,
                  render = function(app, nav) RenderButtonBar(app, nav, nav.level, nav.region) end },
    tabs      = { region = "pageheader", height = TAB_H + 10, contextual = true,
                  render = RenderTabs },
    -- Declarable in either place; see the comment above RenderDropNav.
    dropdown  = { region = "top", height = DDNAV_H + 12, contextual = true,
                  render = RenderDropNav },
    -- Draws in the breadcrumb's own band, so it asks for no height of its
    -- own -- it replaces what was already there rather than adding to it.
    breadcrumb = { region = "pageheader", height = 0, render = RenderCrumbs },
}
ns.nav.NAVIGATORS = NAVIGATORS

-- ── A page that stands in for its whole section ────────────────
--
-- A page may declare `suppressNavigators = true`: while it is on screen,
-- every CONTEXTUAL navigator on the route -- the tab strip its section
-- declared, and any nested one -- is left unmounted, and the breadcrumb
-- stops at the outermost such section. The tree is not touched. It is
-- for the page a section shows when its subtabs have nothing to offer:
-- a scope whose override is off has one page of chrome and no settings,
-- and a strip of tabs over it would be a strip of tabs to eight copies
-- of that same page.
--
-- A LIBRARY RULE rather than a route rebuild. The consumer could emit
-- the section's children only while they apply, but that re-declares
-- the whole tree, flushes every resolved page and risks a silent route
-- repair on every flip of the switch that decides it. The node keeps a
-- constant shape; only what is DRAWN for it changes.
--
-- Answers the route index of the outermost contextual navigator's owner,
-- or nil when nothing is suppressed. Asked of ns.page.ForRoute -- the page
-- the body will draw, ancestor fallback included -- so the band, the
-- trail and the body cannot disagree about which page is on screen.
local function SuppressedAt(app)
    local page = ns.page and ns.page.ForRoute and ns.page.ForRoute(app) or nil
    if not (page and page.suppressNavigators) then return nil end
    local path = {}
    for i, seg in ipairs(app.route or {}) do
        path[i] = seg
        local entry = app.routeIndex and app.routeIndex[table.concat(path, "/")]
        local kind  = entry and entry.node.navigator
        local def   = kind and NAVIGATORS[kind]
        if def and def.contextual then return i end
    end
    return nil
end
ns.nav.SuppressedAt = SuppressedAt

-- Tear a navigator down: every row and button goes back to the app's pool
-- and its scroll container is hidden. Without this, re-declaring chrome
-- orphaned the previous navigator's widgets -- they stayed parented and
-- shown while a NEW navigator drew over the top of them, which is exactly
-- the "several trees stacked on each other" mess.
local function TeardownNav(app, nav)
    -- The dropdown navigator's single button, which is not in `buttons`
    -- because there is only ever one of it.
    if nav.button then app:Release(nav.button); nav.button = nil end
    for _, row in ipairs(nav.rows or {}) do app:Release(row) end
    if nav.rows then wipe(nav.rows) end
    -- Clear the cached signatures too. A reused navigator whose rows have
    -- gone back to the pool must NOT take the fast path on its next render
    -- -- and one whose scroll frame is about to be re-hosted must re-anchor
    -- rather than trust the anchor signature of the frame it has left.
    -- The window goes back to the top: the rows this navigator was parked
    -- on are in the pool, and a row NUMBER into a list that is about to be
    -- rebuilt from scratch means nothing.
    nav.sig, nav.selKey, nav.scrollValue = nil, nil, 0
    for _, b in ipairs(nav.buttons or {}) do app:Release(b) end
    if nav.buttons then wipe(nav.buttons) end
    if nav.list then
        nav.list:Hide()
        -- The bar is a child of the list, so it goes with it -- but hide it
        -- outright rather than relying on that: a torn-down navigator must
        -- leave nothing on screen.
        if nav.bar then nav.bar:Hide() end
    end
end

-- Give a HOST's tree surface back: its rows to the pool, its list and bar
-- hidden. Keyed by the host frame rather than by a route, because the
-- frames belong to the host -- see the note above RenderTreeInto.
--
-- Not needed for correctness. A host holding a surface it is not currently
-- drawing holds hidden frames and a handful of pooled rows, and the next
-- tree drawn there reuses both; nothing can leak, because a host has only
-- ever one surface. This exists for a host that is being retired outright,
-- and so that the rows of a card the reader is unlikely to return to can be
-- handed back rather than parked.
--
-- The KEY's state is deliberately untouched: app.groupNavs keeps the scroll
-- position, which is the reader's place in a list and not a property of any
-- frame.
function ns.nav.ReleaseTreeSurface(app, host)
    local s = host and host.bpTreeSurface
    if not s then return end
    for _, row in ipairs(s.rows or {}) do app:Release(row) end
    if s.rows then wipe(s.rows) end
    s.sig, s.selKey = nil, nil
    if s.list then s.list:Hide() end
    if s.bar  then s.bar:Hide()  end
end

-- Resolving a chrome spec means walking a table of tables and validating
-- navigator names. That is cheap, but it is also PURE -- the same spec
-- always resolves to the same list -- so it is memoised. Switching between
-- two declared configurations then costs a table lookup, not a re-walk.
local function ResolveSpec(app, spec)
    local resolved, topHeight, railShown = {}, 0, true
    -- Not a region: a modifier on the one region it names. "full" runs the
    -- rail from the panel's top edge to its bottom, with the title bar and
    -- the top strip inset to the pane beside it.
    local railSpan = (spec and spec.railSpan) or "body"

    for regionName, list in pairs(spec or {}) do
        if regionName == "railSpan" then
            -- Read above; skipped here so it is never taken for a region.
        elseif list == false then
            if regionName == "left" or regionName == "rail" then railShown = false end
        else
            for _, entry in ipairs(list) do
                local def = NAVIGATORS[entry.navigator]
                assert(def, "SetChrome: unknown navigator '" .. tostring(entry.navigator) .. "'")
                local region = (regionName == "left") and "rail" or regionName
                resolved[#resolved + 1] = {
                    kind = entry.navigator, level = entry.level or 1,
                    region = region, def = def, style = entry.style,
                    -- Tree only: draw the node this level hangs off as the
                    -- first row. See VisibleTreeRows.
                    withParent = entry.withParent,
                    -- The LEVEL is part of the key. Without it two
                    -- navigators of the same kind in one region -- two
                    -- dropdowns in the top strip, say -- share a single
                    -- cached instance, and the second silently overwrites
                    -- the first's widgets and signature.
                    key = entry.navigator .. ":" .. region .. ":" .. tostring(entry.level or 1),
                }
                if region == "top" then topHeight = math.max(topHeight, def.height or 0) end
            end
        end
    end
    return { list = resolved, topHeight = topHeight, railShown = railShown,
             railSpan = railSpan }
end

function ns.nav.SetChrome(app, spec)
    -- Navigator instances are CACHED by kind+region and reused, rather than
    -- recreated. A ScrollFrame cannot be destroyed in WoW, so building a new
    -- one on every chrome change would leak one per switch.
    app.navCache = app.navCache or {}
    app.specCache = app.specCache or {}

    local resolved = app.specCache[spec]
    if not resolved then
        resolved = ResolveSpec(app, spec)
        app.specCache[spec] = resolved   -- keyed by the spec TABLE itself
    end

    for _, nav in pairs(app.navCache) do TeardownNav(app, nav) end
    -- Re-claimed by the breadcrumb navigator's next render if it is still
    -- mounted; cleared here so a spec that drops it gives the static
    -- breadcrumb its band back.
    app.crumbNav = nil

    app.navs = {}
    app.railShown = resolved.railShown
    app.railSpan  = resolved.railSpan

    for _, r in ipairs(resolved.list) do
        local nav = app.navCache[r.key]
        if not nav then nav = {}; app.navCache[r.key] = nav end
        nav.kind, nav.level, nav.region, nav.def = r.kind, r.level, r.region, r.def
        nav.style = r.style
        nav.withParent = r.withParent
        app.navs[#app.navs + 1] = nav
    end

    local topHeight = resolved.topHeight
    app.topHeight = topHeight

    -- The title bar's height override belongs to a button bar mounted
    -- there. With no such bar it has to go back to the skin's value, or a
    -- layout that once wrapped leaves the title bar permanently tall.
    local barInTitle = false
    for _, r in ipairs(resolved.list) do
        if r.region == "titlebar" then barInTitle = true end
    end
    if not barInTitle then app.titlebarHeight = nil end
    -- Published for LayoutRegions: a full-height rail collapses the title
    -- bar, and it must not do that to a bar mounted in it. The two are
    -- combinable -- sections in the title bar, the rail still full height
    -- -- and the collapse is what would have made that unreadable.
    app.titlebarOccupied = barInTitle
    if app.frame then
        ns.LayoutRegions(app)
        ns.nav.Refresh(app)
    end
end

-- Re-render every mounted navigator plus the breadcrumb and body
-- placeholder. P0.3 replaces the placeholder with real page content.
-- Contextual navigators: the ones a NODE declares rather than the app.
--
-- Walked from the active route, so a strip belongs to the node that
-- declared it, appears while that node is on the route and is gone when it
-- is not. The height it needs goes to the page header, and drops back to
-- nothing when no such node is in play -- otherwise a layout that once had
-- tabs keeps the gap where they were.
local function MountContextual(app)
    app.ctxNavs = app.ctxNavs or {}
    local wanted = {}

    local path = {}
    for i, seg in ipairs(app.route or {}) do
        path[i] = seg
        local entry = app.routeIndex and app.routeIndex[table.concat(path, "/")]
        local kind  = entry and entry.node.navigator
        local def   = kind and NAVIGATORS[kind]
        if def and def.contextual then
            wanted[#wanted + 1] = { key = entry.key, def = def, entry = entry }
        end
    end
    -- The page on screen has asked for no strip at all (SuppressedAt,
    -- settled by Refresh before anything in the header was placed): every
    -- contextual navigator is unwanted, so it gives its widgets back below
    -- exactly as one whose owner had left the route.
    if app.ctxNavSuppressedAt then wanted = {} end

    -- Anything mounted last time and not wanted now gives its widgets back.
    for key, nav in pairs(app.ctxNavs) do
        local keep = false
        for _, w in ipairs(wanted) do if w.key == key then keep = true end end
        if not keep then
            for _, b in ipairs(nav.buttons or {}) do app:Release(b) end
            nav.buttons = nil
            -- Its rule goes with it. The textures belong to this navigator
            -- rather than the pool, so nothing else will claim them, and a
            -- rule left showing would sit under a strip that is gone.
            if nav.tabRuleL then nav.tabRuleL:Hide() end
            if nav.tabRuleR then nav.tabRuleR:Hide() end
            app.ctxNavs[key] = nil
        end
    end

    local height = 0
    for i, w in ipairs(wanted) do
        local nav = app.ctxNavs[w.key]
        if not nav then nav = {}; app.ctxNavs[w.key] = nav end
        nav.def, nav.ownerEntry = w.def, w.entry
        -- Where this navigator sits in the band. `wanted` is built by
        -- walking the route from the root down, so 1 is the outermost
        -- section's strip and each nested one follows -- which is the order
        -- they are drawn in, outer row above inner.
        nav.stackIndex = i
        -- The height it MEASURED last time, where it has one. A strip that
        -- wraps does not know how tall it is until it has packed, so the
        -- declared height is the floor for a navigator that has never
        -- rendered, not the answer for one that has.
        --
        -- SUMMED, not maxed: every navigator in the band gets its own row.
        height = height + (nav.dynHeight or w.def.height or 0)
    end

    -- This navigator's own contribution, not the header's total. Chrome
    -- adds it to whatever else wants space up there and owns the answer.
    app.ctxNavHeight = height
    local want = ns.chrome.PageHeaderHeight(app)
    if (app.pageheaderHeight or 0) ~= want then
        app.pageheaderHeight = want
        ns.LayoutRegions(app)
    end
    return wanted
end

function ns.nav.Refresh(app, chromeOnly)
    if not app.frame then return end
    -- Not while something is being dragged. A refresh returns every row and
    -- card to the pool and builds them again, which would pull the dragged
    -- one out from under the cursor mid-gesture; the drop re-renders anyway.
    if ns.reorder and ns.reorder.IsDragging() then return end
    -- Before the navigators: the box's placement decides how much room the
    -- rail tree and the button bar have left, so it has to be positioned
    -- first or they lay out against last frame's answer.
    if ns.search and ns.search.Layout then ns.search.Layout(app) end
    -- Where the next navigator that lays itself out horizontally should
    -- start, per region. Reset once per pass and advanced by each one that
    -- uses it, so several in one region sit side by side in spec order
    -- rather than stacking on the same anchor point.
    app.navCursor = app.navCursor or {}
    wipe(app.navCursor)
    -- BEFORE anything is placed in the page header. A page's header field
    -- takes a row up there, and the contextual navigators below it are
    -- anchored from the band's height -- so the room has to be reserved
    -- while it is still a number, not after the strip has been drawn
    -- against the old one.
    if ns.chrome and ns.chrome.ReserveHeaderField then
        ns.chrome.ReserveHeaderField(app)
    end
    -- Likewise settled up front: the breadcrumb navigator renders with the
    -- app-level ones, BEFORE the contextual band is mounted, and both read
    -- this rather than each asking the page again.
    app.ctxNavSuppressedAt = SuppressedAt(app)
    for _, nav in ipairs(app.navs or {}) do
        nav.def.render(app, nav)
    end
    -- After the app-level ones, because a contextual navigator's height
    -- changes the page header and everything below it.
    for _, w in ipairs(MountContextual(app)) do
        local nav = app.ctxNavs[w.key]
        nav.def.render(app, nav)
    end
    -- The footer goes through here too, or it keeps the cell widths it
    -- computed for the last rail width: resizing re-anchored every region
    -- and re-rendered everything EXCEPT the buttons under the tree, so they
    -- stayed laid out for a rail that no longer existed. Same family as the
    -- status strip (27.13) and the rail tree (27.17) -- a thing that lays
    -- itself out from a region's width and is never asked to do it again.
    if ns.chrome and ns.chrome.RenderFooter then ns.chrome.RenderFooter(app) end
    if ns.chrome and ns.chrome.RenderBreadcrumb then ns.chrome.RenderBreadcrumb(app) end
    -- Re-read on every pass, so a cell declared as a function reports what
    -- is true now rather than what was true when it was declared.
    if ns.chrome and ns.chrome.RenderStatusBar then ns.chrome.RenderStatusBar(app) end
    if chromeOnly then return end
    -- A route with a `page` renders real content; one without still gets the
    -- placeholder, so a half-built tree is navigable rather than blank.
    local rendered = ns.page and ns.page.Render(app)
    if ns.chrome and ns.chrome.RenderPlaceholder then
        ns.chrome.RenderPlaceholder(app, not rendered)
    end
end

-- The navigators and chrome WITHOUT the page: what a live resize needs
-- (the strip re-wraps, the rail tree re-clips to its region, the footer
-- and status cells re-measure) at a cost that can be paid twenty times a
-- second. The rail tree and the strip are signature-guarded, so a pass
-- that would draw the same thing draws nothing. The page -- the expensive
-- rebuild, and the one that flashed -- waits for the release.
function ns.nav.RefreshChrome(app)
    return ns.nav.Refresh(app, true)
end
