-- ============================================================
-- BuzzardPanel: Collections.lua
-- Repeatable, user-managed sets as a first-class node type.
--
-- A collection is a list the reader adds to and removes from, whose
-- members each get a page: aura containers, single buffs, custom frame
-- groups, saved layouts. The addon this library was written for has at
-- least six, and every one of them independently hand-rolled the same
-- machinery -- a dynamic subtab builder, an add path, a remove path with a
-- confirmation, a title that changes color by state, and a rebuild hook.
-- That duplication is the thing this file exists to delete.
--
-- -- A collection is a FILTER over a SHARED source --
--
-- Not "one list, one navigator, one page". The real storage does not work
-- that way: single buffs live in the SAME array as buff containers, marked
-- with a flag, and are filtered out of the container tabs to appear
-- somewhere else entirely. So `source` is a raw store and `filter` is this
-- collection's slice of it, and one store can back several collections
-- that present it differently.
--
-- -- Members can have DIFFERENT pages --
--
-- Also not "one template with the odd exception". A container page is
-- three tabs; a single buff is six, built by trimming the container's
-- builder down and adding four tabs a container never gets. `variant`
-- picks the template per member and differing templates are the normal
-- case.
--
-- -- Identity is never the index --
--
-- Removing member three does not renumber the others' identities, and it
-- must not renumber their routes either. Every real collection already
-- mints a stable key -- a container key, a spell key, a layout id -- so
-- `key(item)` is what a route is named by and what selection is restored
-- against. See ReselectAfter for what happens when the selected member is
-- the one that went.
--
-- -- What the library does NOT own --
--
-- Removal semantics. Deleting a container remaps spell assignments,
-- rewrites everything anchored to it, and shifts a parallel position
-- table; none of that is the library's business. `onRemove` does the
-- cleanup and the library re-keys the routes and re-selects. The same goes
-- for ordering: `onMove` persists it, because one collection stores order
-- as numbered slots and another as array position.
-- ============================================================
local ADDON, ns = ...

ns.collections = {}

-- The client is Lua 5.1, where `unpack` is a global. The fallback is for
-- the headless test harness, which runs a newer Lua that moved it onto
-- `table` -- it costs one lookup at load and makes this file runnable
-- outside the game, which is the only way its selection rules get tested
-- at all.
local unpack = unpack or table.unpack

-- ── Reading a collection ───────────────────────────────────────

local function Members(app, node)
    local src = node.source and node.source(app) or {}
    local out = {}
    for i, item in ipairs(src) do
        if (not node.filter) or node.filter(item, i) then
            out[#out + 1] = {
                item  = item,
                index = i,                     -- index in the SOURCE, not in the slice
                key   = node.key and tostring(node.key(item, i)) or tostring(i),
            }
        end
    end

    -- Pinned members are hoisted to the FRONT, keeping their order relative
    -- to each other and leaving everything else in its own order.
    --
    -- Done here rather than left to the creator's storage, so a pin means
    -- the same thing everywhere -- the tree, a tab strip, ExpandChildren --
    -- and so the drag never has to reason about a pin in the middle of a
    -- list. There is no such position: the hoist makes pinned members a
    -- prefix by construction, which is what lets the gesture clamp with a
    -- lower bound and no upper one, and is why nothing can be penned in
    -- behind a pin.
    --
    -- `index` is untouched by any of this. It is the SOURCE index, which is
    -- what onMove is handed, so hoisting changes what the reader sees
    -- without changing what the addon stores.
    local fn = node.reorder and node.reorder.pinned
    if not fn then return out end
    local pinned, rest = {}, {}
    for _, m in ipairs(out) do
        local t = fn(m.item, m.index) and pinned or rest
        t[#t + 1] = m
    end
    if #pinned == 0 then return out end
    for _, m in ipairs(rest) do pinned[#pinned + 1] = m end
    return pinned
end
ns.collections.Members = Members

-- Named `memberTitle`, not `title`.
--
-- A route node's own `title` is the collection's heading in the tree. The
-- per-member one is a different thing that happens to want a similar name,
-- and letting them share it means a collection can never have a heading of
-- its own -- the sort of collision that is obvious once and invisible
-- afterwards.
local function MemberTitle(node, m)
    if node.memberTitle then return node.memberTitle(m.item, m.index) end
    return m.key
end

local function TemplateFor(node, m)
    if node.templates then
        local which = node.variant and node.variant(m.item, m.index) or "default"
        return node.templates[which] or node.templates.default
    end
    return node.template
end

-- ── Expanding a collection into routes ─────────────────────────
--
-- Called from Nav's route indexing. A collection declares its members
-- lazily -- the page for a member is only BUILT when that member is
-- visited (a page is a function here, evaluated by Page.Render), so eight
-- containers cost one page build, not eight.

function ns.collections.ExpandChildren(app, node)
    -- An INLINE collection has no member routes at all: its members are
    -- cards on its own page, not places to navigate to. Returning nothing
    -- here is the whole of that decision -- the tree draws no rows, no tab
    -- strip appears, and no member page is ever built, because none exists.
    if node.inline then return {} end

    local kids = {}

    -- Sections group members under headings. Declared order, and a section
    -- with no members is dropped rather than rendered empty.
    if node.sections and node.section then
        local bucket = {}
        for _, m in ipairs(Members(app, node)) do
            local sid = node.section(m.item, m.index)
            bucket[sid] = bucket[sid] or {}
            table.insert(bucket[sid], m)
        end
        for _, sec in ipairs(node.sections) do
            local list = bucket[sec.id] or {}
            -- An empty section is dropped by default, because a heading over
            -- nothing usually reads as a rendering fault. `showEmpty` says
            -- otherwise, per section or for the whole collection: a list the
            -- reader moves things INTO has to exist while it is empty, or it
            -- can never be emptied. That is the collection creator's call and
            -- nothing to do with whether anything is draggable -- an always-
            -- visible pair of headings is a legitimate thing to want for its
            -- own sake.
            local keep = #list > 0
                         or (sec.showEmpty ~= nil and sec.showEmpty)
                         or (sec.showEmpty == nil and node.showEmpty)
            if keep then
                local secKids = {}
                for _, m in ipairs(list) do
                    secKids[#secKids + 1] = ns.collections.MemberNode(app, node, m)
                end
                kids[#kids + 1] = {
                    id = sec.id, title = sec.title, children = secKids,
                    -- `expanded = true|false` on a section is its default
                    -- open state in the tree, until the reader clicks its
                    -- chevron. Absent, a heading opens only while the
                    -- route is inside it, like any other branch.
                    expanded = sec.expanded,
                    -- Marked so a drag can tell a section apart from a
                    -- member without comparing against the declared list.
                    bpCollection = node, bpSection = sec,
                }
            end
        end
        return kids
    end

    for _, m in ipairs(Members(app, node)) do
        kids[#kids + 1] = ns.collections.MemberNode(app, node, m)
    end
    return kids
end

-- ── A member's subtabs ─────────────────────────────────────────
--
-- A tree-group collection may declare `memberTabs`: the classic
-- tabbed child-groups shape, where one member's settings are several pages
-- reached from a strip at the top of the pane rather than one long column.
--
--   memberTabs = {
--       { id = "position", title = "Position" },
--       { id = "icon",     title = "Icon",
--         hidden = function(item, index) return not item.custom end },
--   }
--
-- Each tab is a ROUTE under the member -- ".../<member>/<tab>" -- so a
-- deep link, a search hit and a route observer can all name one, exactly
-- as the section strips' tabs are routes. The template returns the page
-- for the whole member: its `groups` are the header the strip sits under
-- (the spell's name, the scope row -- what stays on screen whichever tab
-- is showing) and `tabs` holds one entry per tab id with that tab's own
-- groups. The tree group's pane draws the header, the strip, then the
-- selected tab's groups in the scrolling part (see LayoutTreeGroup).
--
-- `hidden` is read HERE, when the routes are indexed, and a hidden tab is
-- not minted at all: what the strip shows is what exists, and a change to
-- the answer is a structural change the host reports with app:Invalidate
-- -- which the Buff List's Display Type already does.
--
-- The declaration lives on the COLLECTION and not on the page the
-- template returns, because the routes have to exist before any member's
-- page is built -- building every member's page to learn its tab names is
-- exactly the cost a tree group exists to avoid.
function ns.collections.MemberTabs(app, node, m)
    local defs = node.memberTabs
    if not (defs and node.treeGroup) then return nil end
    local kids = {}
    for _, tab in ipairs(defs) do
        local hide = tab.hidden
        if type(hide) == "function" then hide = hide(m.item, m.index) end
        if not hide then
            kids[#kids + 1] = {
                id    = tab.id,
                title = tab.title,
                desc  = tab.desc,
                -- The same page the member shows: the one the tree sits
                -- on. A tab is a destination, so it has to be drawable.
                page  = function()
                    local base = node.page
                    if type(base) == "function" then base = base(node) end
                    return base
                end,
                bpCollection = node,
                bpMember     = m,
                bpTab        = tab,
            }
        end
    end
    if #kids == 0 then return nil end
    return kids
end

-- The groups a member page holds for one tab. `page.tabs` is either a
-- list of { id = ..., groups = ... } or a table keyed by tab id; a tab the
-- page does not describe draws nothing, which is visible rather than an
-- error because the strip still shows the tab.
function ns.collections.TabGroups(page, tabId)
    local tabs = page and page.tabs
    if not (tabs and tabId) then return nil end
    local t = tabs[tabId]
    if type(t) ~= "table" then
        for _, e in ipairs(tabs) do
            if type(e) == "table" and e.id == tabId then t = e; break end
        end
    end
    if type(t) ~= "table" then return nil end
    return t.groups or t
end

-- The template's context carries `collection` (the collection's id) as
-- well as app/item/index/key, so a template shared between two collections
-- -- a Buff List entry drawn under a container's own tree, say -- can
-- address the one it is rendered in.
function ns.collections.MemberNode(app, node, m)
    local tmpl = TemplateFor(node, m)
    local member = {
        id    = m.key,
        title = MemberTitle(node, m),

        -- The SAME title, re-computable. The string above is what the tree
        -- was indexed with -- search, the breadcrumb and the tab strip all
        -- read it -- and re-deriving it means rebuilding the routes. A row
        -- whose label carries live state (a spec icon, a warning mark) can
        -- instead be re-titled on its own through ns.nav.RefreshRow, which
        -- calls this. Nil when the collection declares no memberTitle: the
        -- row then shows its key, which cannot change.
        titleFn = node.memberTitle
                  and function() return node.memberTitle(m.item, m.index) end or nil,
        desc  = node.memberDesc and node.memberDesc(m.item, m.index) or nil,

        -- Color is a function of state, so it is resolved at paint time
        -- rather than baked into the title. Escape codes must never reach
        -- stored data, which is what happens when a title is colored by
        -- string concatenation and then written back.
        color = node.memberColor
                 and function() return node.memberColor(m.item, m.index) end or nil,

        -- The page is a FUNCTION. Nothing here builds it; Page.Render calls
        -- it when this member is actually visited.
        --
        -- A TREE GROUP collection is the exception, and it is not really an
        -- exception: the page a member route shows is the collection's OWN
        -- page, because that page is what carries the tree -- the list has
        -- to stay on screen while you read the member beside it. The
        -- member's own groups are drawn by the tree group, in its right
        -- pane, from ns.collections.MemberPage.
        page = (node.treeGroup and function()
            local base = node.page
            if type(base) == "function" then base = base(node) end
            return base
        end) or (tmpl and function()
            local page = tmpl({ app = app, item = m.item, index = m.index, key = m.key,
                          collection = node.id })
            if page and node.remove and node.remove.corner ~= false then
                ns.collections.AddCornerX(app, node, m, page)
            end
            return page
        end) or nil,

        bpCollection = node,
        bpMember     = m,

        -- The member's SUBTABS, as routes under it -- see MemberTabs.
        -- Kept out of the tree: the tree lists members, and the tabs are
        -- drawn by the pane the member's page is shown in.
        children     = ns.collections.MemberTabs(app, node, m),
    }
    -- An explicit branch: `(x and false) or nil` is unconditionally nil.
    if node.memberTabs then member.railChildren = false end
    return member
end

-- One member's own page, by key: what a tree group draws in its right
-- pane. The same template call MemberNode makes, so a collection cannot
-- present one thing as a route and another inside a tree.
-- MEMOISED, on exactly the terms ns.page.Resolve is and for exactly the
-- same reason: the search index is keyed by table identity, and a template
-- called afresh for the index and again for the render hands the two
-- different tables, so every card in the pane dims although the word inside
-- it is highlighted. Cleared by ns.page.ClearPageCache, which is the path
-- every structural change already takes.
function ns.collections.MemberPage(app, node, key)
    app.memberPages = app.memberPages or {}
    local byKey = app.memberPages[node]
    if byKey and byKey[key] ~= nil then return byKey[key] or nil end

    local page
    for _, m in ipairs(Members(app, node)) do
        if m.key == key then
            local tmpl = TemplateFor(node, m)
            if not tmpl then return nil end
            page = tmpl({ app = app, item = m.item, index = m.index, key = m.key,
                          collection = node.id })
            if page and node.remove and node.remove.corner ~= false then
                ns.collections.AddCornerX(app, node, m, page)
            end
            break
        end
    end
    -- A key that names no member is NOT cached: the member list is data
    -- the host owns, and a miss now is a member that has not been added
    -- yet as often as it is one that never existed.
    if page then
        byKey = byKey or {}
        app.memberPages[node] = byKey
        byKey[key] = page
    end
    return page
end

-- The remove affordance the library ships, as an attachment on the
-- member's first group. It is one CALLER of Remove, not the mechanism --
-- Remove is callable from any widget, and this is the default wiring so
-- that every collection does not have to build its own X.
function ns.collections.AddCornerX(app, node, m, page)
    local first = page.groups and page.groups[1]
    if not first then return end
    -- A member that cannot be removed gets no X. `corner = false` turns the
    -- affordance off for the WHOLE collection; this is the per-member form,
    -- for a list where one entry is fixed -- the Layouts tree's Global
    -- assignment, which every override above it falls back to. `canRemove`
    -- is the other half: it refuses the action, this hides the button that
    -- would ask for it, and a fixed member needs both or the reader is
    -- offered something that answers no.
    if node.remove.hidden and node.remove.hidden(m.item, m.index) then return end
    first.attach = first.attach or {}
    for _, a in ipairs(first.attach) do
        if a.id == "bpRemove" then return end          -- already there
    end
    -- INSIDE the card's header row, not overhanging its corner.
    --
    -- `outerTopRight` hangs the button off the card edge, which puts it
    -- straddling the rounded corner: half on the card, half on the panel,
    -- and its own border crossing the card's arc. It reads as clipped. The
    -- header row is where the eye already is -- the title is right there --
    -- and the whole affordance sits on the card with nothing crossing an
    -- edge. A card with no title has no header to sit in, so that case
    -- insets into the body's own top right instead.
    -- A TREE GROUP's member is a whole pane, and the X acts on the member
    -- -- so it goes in the pane's own corner rather than on the first card
    -- inside it, which is the member's name and not the member. The spec is
    -- still minted here, in one place; whichever host publishes the zone is
    -- the one that draws it, and a host that does not simply skips it.
    local zone = node.remove.zone
    if not zone then
        if node.treeGroup then
            zone = "topRight"
        else
            -- A CARD keeps its X in the header row, or in its own inner
            -- corner for a plain or tab header -- ns.attach.CardCornerZone
            -- is the one place that rule lives.
            zone = ns.attach.CardCornerZone(app, first)
        end
    end
    local ox, oy = ns.attach.CornerOffsets(zone)
    first.attach[#first.attach + 1] = {
        id      = "bpRemove",
        zone    = zone,
        icon    = "x",
        danger  = true,
        -- Negative, so it clears the card's own 1px border rather than
        -- sitting on it (see ns.attach.CornerOffsets).
        x       = ox,
        y       = oy,
        -- Smaller than the 26px header row, so its border sits inside the
        -- row rather than flush against its edges.
        size    = 20,
        tooltip = node.remove.tooltip or "Remove",
        onClick = function() ns.collections.Remove(app, node.id, m.key) end,
    }
end

-- ── Inline: members as cards rather than as routes ─────────────
--
-- Some collections are too small to deserve navigation. Five members with
-- two settings each want to be five cards on one page with an Add button
-- under them, not five routes the reader has to visit one at a time.
--
-- The templates do not change shape. A template still returns a PAGE, and
-- inline splices that page's groups into the parent's, one member after
-- another. That is what keeps everything else working unchanged: variants
-- pick the same templates, and the library's corner X still attaches to
-- `page.groups[1]`, which inline makes the member's own card.
--
-- The collection's own `page`, if it declares one, supplies the groups
-- ABOVE the members -- an intro, an Add button, a filter. `emptyText`
-- renders as a note when there is nothing to show, so an empty collection
-- says so rather than looking like a page that failed to build.
function ns.collections.InlinePage(app, node)
    local base = node.page
    if type(base) == "function" then
        local ok, built = pcall(base, node)
        base = ok and built or nil
    end

    -- EVERYTHING THE BASE PAGE DECLARED, not just its db.
    --
    -- This used to build `{ db = ..., groups = {} }` and drop the rest,
    -- which quietly threw away every other page-level key the collection's
    -- own page had set: `headerField` above all -- the Aura Preview dropdown
    -- that belongs to a whole section -- so the one subtab of that section
    -- that happens to be an inline collection lost it, and the strip moved
    -- up into the empty band. `groups` and `reorder` are the two this
    -- function builds itself; everything else is the page's own word.
    local page = {}
    for k, v in pairs(base or {}) do
        if k ~= "groups" and k ~= "reorder" then page[k] = v end
    end
    page.db     = (base and base.db) or node.db
    page.groups = {}
    for _, g in ipairs((base and base.groups) or {}) do
        page.groups[#page.groups + 1] = g
        -- The collection's own cards are not members and cannot be dragged
        -- among them.
        g.reorderable = false
    end

    local members = Members(app, node)
    for _, m in ipairs(members) do
        local tmpl = TemplateFor(node, m)
        local built = tmpl and select(2, pcall(tmpl, {
            app = app, item = m.item, index = m.index, key = m.key,
            collection = node.id,
        })) or nil
        if built and built.groups and built.groups[1] then
            -- The member's name goes on its first card, which is where a
            -- reader looks for it when there is no route to name it.
            built.groups[1].title = built.groups[1].title or MemberTitle(node, m)
            if node.remove and node.remove.corner ~= false then
                ns.collections.AddCornerX(app, node, m, built)
            end
            for i, g in ipairs(built.groups) do
                -- Only the member's FIRST card carries the member: dragging
                -- a continuation card would move something the reader does
                -- not think of as a thing.
                g.bpMemberKey = (i == 1) and m.key or nil
                g.reorderable = (i == 1)
                                and not ns.collections.IsPinned(node, m)
                page.groups[#page.groups + 1] = g
            end
        end
    end

    if #members == 0 and node.emptyText then
        page.groups[#page.groups + 1] = {
            reorderable = false,
            fields = { { control = "note", wide = true, text = node.emptyText } },
        }
    end

    -- Dragging is the group-card gesture, pointed at the collection. A
    -- collection that declares no reorder gets no draggable cards, exactly
    -- as in the tree.
    if node.reorder and node.reorder.onMove then
        page.reorder = {
            combat = node.reorder.combat,
            onMove = function(group, from, to)
                local dest = page.groups[to]
                if not (group.bpMemberKey and dest and dest.bpMemberKey) then return end
                for _, m in ipairs(Members(app, node)) do
                    if m.key == dest.bpMemberKey then
                        ns.collections.Move(app, node.id, group.bpMemberKey, m.index)
                        return
                    end
                end
            end,
        }
    end
    return page
end

-- Called by Page.Render for every route, and a no-op for everything that is
-- not an inline collection. Here rather than in Page so that Page needs to
-- know nothing about collections beyond asking.
function ns.collections.PageFor(app, node, page)
    if not (node and node.node == "collection" and node.inline) then return page end
    return ns.collections.InlinePage(app, node)
end

-- ── Finding a collection ───────────────────────────────────────

local function FindNode(app, id)
    for _, entry in pairs(app.routeIndex or {}) do
        local n = entry.node
        if n.node == "collection" and n.id == id then return n, entry end
    end
end
ns.collections.Find = FindNode

-- ── Add ────────────────────────────────────────────────────────
--
-- Callable from anything: a button, a search box's commit, a menu entry.
-- The library owns the parts that are the same every time and are
-- hand-rolled at every call site today -- the combat gate, the in-flight
-- guard against a double fire, the invalidation, and navigating to the new
-- member AFTER the routes exist.

function ns.collections.Add(app, id, ...)
    local node, entry = FindNode(app, id)
    if not (node and node.add and node.add.onAdd) then return end

    if node.add.combat ~= false and InCombatLockdown() then return end

    -- One add at a time. The panel this replaces needed both a pending flag
    -- and a one-second runaway guard because a description function could
    -- re-enter the add path; owning the guard here means no collection has
    -- to remember it.
    if app.collectionAdding then return end
    app.collectionAdding = true

    local ok, item = pcall(node.add.onAdd, ...)
    app.collectionAdding = nil
    if not ok then return end

    ns.collections.Rebuild(app, node)

    -- Navigate only once the member's route exists. Getting this order
    -- wrong is what forces the current panel to rebuild eagerly in one
    -- place and defer its selection by a frame in another.
    if node.add.select ~= false and item then
        local key = node.key and tostring(node.key(item)) or nil
        if key then ns.collections.Select(app, node, entry, key) end
    end
    return item
end

-- ── Remove ─────────────────────────────────────────────────────

function ns.collections.Remove(app, id, key)
    local node, entry = FindNode(app, id)
    if not (node and node.remove) then return end
    if node.remove.combat ~= false and InCombatLockdown() then return end

    local target
    for _, m in ipairs(Members(app, node)) do
        if m.key == key then target = m end
    end
    if not target then return end

    -- Removal can be REFUSED, with a reason. A container with spells still
    -- assigned to it says so instead of silently doing nothing.
    if node.remove.canRemove then
        local ok, reason = node.remove.canRemove(target.item, target.index)
        if not ok then
            ns.collections.Refuse(app, node, target, reason)
            return
        end
    end

    local function commit()
        local order = ns.collections.Positions(app, node)
        if node.remove.onRemove then
            node.remove.onRemove(target.item, target.index)
        end
        ns.collections.Rebuild(app, node)
        ns.collections.ReselectAfter(app, node, entry, key, order)
    end

    if node.remove.confirm then
        ns.collections.Confirm(app, node.remove.confirm(target.item, target.index), commit)
    else
        commit()
    end
end

-- ── Reorder ────────────────────────────────────────────────────
--
-- The library owns the gesture; the addon owns the storage. One collection
-- stores order as numbered slots in a side table and another as array
-- position, so assuming table.remove + table.insert would be wrong for
-- both of them half the time.
--
--   reorder = {
--       onMove = function(item, from, to) ... end,
--       combat = false,   -- to allow reordering in combat
--       grip   = false,   -- to hide the drag affordance
--       pinned = function(item, index) return item.builtin end,
--   }
--
-- A PINNED member is hoisted to the front of its list and held there: it
-- cannot be dragged, and nothing can land above it. Two pinned members
-- both go to the front, keeping their order relative to each other.
--
-- Pinning is what makes "the first three stay put" expressible without
-- the creator having to keep them first in their own storage -- and it is
-- why nothing has to police a pin in the middle of a list. There is no
-- such thing: the hoist puts every pin at the front by construction.
--
-- `from` and `to` are indices into the SOURCE array, the same numbers
-- Members reports, so an addon never has to translate between the slice it
-- sees and the table it stores. `to` is the index currently held by the
-- member being displaced.
--
-- One honest caveat: with `sections`, a section's members need not be
-- contiguous in the source, so `to` is the displaced member's index rather
-- than a position in the section. Every collection Buzzard Frames has is
-- flat, where the two are the same thing; a sectioned collection that also
-- wants drag order should say what it means in its own onMove.
--
-- ── Moving between sections ────────────────────────────────────
--
-- Reordering and MOVING are different questions and get different
-- callbacks, because they are different edits to the addon's data: one
-- changes position, the other changes what `section(item)` returns.
--
--   reorder = {
--       onMove   = function(item, from, to) end,          -- within a section
--       across   = "move",                                 -- default nil
--       onMoveTo = function(item, sectionId, before) end,  -- across sections
--   }
--
-- `before` is the member ITEM the dragged one should sit ahead of, or nil
-- for the end of that section -- not an index. Across sections an index is
-- ambiguous, because a section's members need not be contiguous in the
-- source array, and "put it before this one" is what an addon actually
-- needs in order to set its flag and place it.
--
-- A section that is not shown is not a drop target. A collection that
-- wants a list emptied completely says `showEmpty` on it; see
-- ExpandChildren.
function ns.collections.MoveTo(app, id, key, sectionId, beforeKey)
    local node = FindNode(app, id)
    if not (node and node.reorder and node.reorder.onMoveTo) then return end
    if node.reorder.combat ~= false and InCombatLockdown() then return end

    local members, moving, before = Members(app, node), nil, nil
    for _, m in ipairs(members) do
        if m.key == key      then moving = m end
        if m.key == beforeKey then before = m end
    end
    if not moving then return end
    if ns.collections.IsPinned(node, moving) then return end

    node.reorder.onMoveTo(moving.item, sectionId, before and before.item or nil)
    ns.collections.Rebuild(app, node)
end

-- The gesture itself is in Nav.lua, on the tree rows -- see InstallRowDrag.

-- Is this member fixed in place? Asked of the node rather than the widget,
-- so the answer is the same whether it is being read by the rail, a tab
-- strip, or a direct call to the API.
function ns.collections.IsPinned(node, m)
    local fn = node.reorder and node.reorder.pinned
    return (fn and m and fn(m.item, m.index)) and true or false
end

function ns.collections.Move(app, id, key, toIndex)
    local node = FindNode(app, id)
    if not (node and node.reorder and node.reorder.onMove) then return end
    -- The same gate Add and Remove apply, for the same reason: a reorder
    -- rebuilds routes and re-renders, and the reader is mid-fight.
    if node.reorder.combat ~= false and InCombatLockdown() then return end
    for _, m in ipairs(Members(app, node)) do
        if m.key == key then
            if m.index == toIndex then return end
            -- Refused here too, not only in the gesture: Move is a public
            -- call, and a pin that only the drag honors is not a pin.
            if ns.collections.IsPinned(node, m) then return end
            node.reorder.onMove(m.item, m.index, toIndex)
            ns.collections.Rebuild(app, node)
            return
        end
    end
end

-- ── Rebuilding and selection ───────────────────────────────────

function ns.collections.Positions(app, node)
    local out = {}
    for i, m in ipairs(Members(app, node)) do out[i] = m.key end
    return out
end

-- Re-index AND re-render.
--
-- These were two things a caller had to remember to do, and Add and Remove
-- only looked correct because both end in a navigation, which refreshes as
-- a side effect. A REORDER changes no selection, so it navigated nowhere,
-- and the array was genuinely being reordered while the tree carried on
-- drawing the old order -- a change with no visible effect, which reads as
-- a broken gesture. One function, both halves.
function ns.collections.Rebuild(app, node)
    ns.nav.ReindexRoutes(app)
    if ns.nav.Refresh then ns.nav.Refresh(app) end
end

function ns.collections.Select(app, node, entry, key)
    local path = {}
    for i, seg in ipairs(entry.path) do path[i] = seg end
    -- With sections the member sits one level deeper, so the route is
    -- found rather than assumed.
    local want = table.concat(path, "/") 
    for k, e in pairs(app.routeIndex or {}) do
        if e.node.bpCollection == node and e.node.id == key
           and ns.nav.RouteWithin(k, want) then
            return ns.nav.Navigate(app, unpack(e.path))
        end
    end
    return ns.nav.Navigate(app, unpack(path))
end

-- The selected member was removed. Same key if it survived, else whatever
-- is now in the same POSITION, else the collection itself.
--
-- This is the failure the current panel guards by hand, clearing its
-- remembered index and then navigating to math.min(index, remaining).
function ns.collections.ReselectAfter(app, node, entry, goneKey, orderBefore)
    local route = app.route or {}
    local onIt  = false
    for _, seg in ipairs(route) do if seg == goneKey then onIt = true end end
    if not onIt then return end

    local pos = 1
    for i, k in ipairs(orderBefore) do if k == goneKey then pos = i end end

    local now = ns.collections.Positions(app, node)
    if #now == 0 then
        return ns.nav.Navigate(app, unpack(entry.path))
    end
    local key = now[math.min(pos, #now)]
    return ns.collections.Select(app, node, entry, key)
end

-- ── Dialogs ────────────────────────────────────────────────────

local CONFIRM = "BUZZARDPANEL_COLLECTION_CONFIRM"
local REFUSE  = "BUZZARDPANEL_COLLECTION_REFUSE"

-- TWO dialogs, not one with a button hidden.
--
-- A confirmation asks a question and needs both answers. A refusal is not a
-- question -- the reader has been told the thing cannot be done -- so
-- offering Yes and No is offering a choice that does not exist, and the
-- first version did exactly that by reusing the confirmation and hiding its
-- second button. Hiding a button also leaves the first one still saying
-- "Yes", to something there is no yes to.
local function EnsurePopups()
    if not StaticPopupDialogs[CONFIRM] then
        StaticPopupDialogs[CONFIRM] = {
            text = "%s", button1 = YES or "Yes", button2 = NO or "No",
            timeout = 0, whileDead = true, hideOnEscape = true,
            -- Above the panel. A confirmation that opens BEHIND the window
            -- it was raised from is the kind of thing every dialog fixes
            -- for itself; done here, once.
            preferredIndex = 3,
            OnAccept = function(self)
                if self.data and self.data.fn then self.data.fn() end
            end,
        }
    end
    if not StaticPopupDialogs[REFUSE] then
        StaticPopupDialogs[REFUSE] = {
            text = "%s", button1 = OKAY or "Okay",
            timeout = 0, whileDead = true, hideOnEscape = true,
            preferredIndex = 3,
            -- No OnAccept at all: there is nothing to do, and a handler
            -- here would be a thing waiting to be given something to run.
        }
    end
end

function ns.collections.Confirm(app, text, fn)
    EnsurePopups()
    local d = StaticPopup_Show(CONFIRM, text or "Are you sure?")
    if d then d.data = { fn = fn } end
end

function ns.collections.Refuse(app, node, member, reason)
    EnsurePopups()
    StaticPopup_Show(REFUSE, reason or "This cannot be removed.")
end
