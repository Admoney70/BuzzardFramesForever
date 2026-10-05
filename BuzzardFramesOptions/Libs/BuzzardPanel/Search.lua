-- ============================================================
-- BuzzardPanel: Search.lua
-- Find a setting without knowing which page it lives on.
--
-- Two halves that are worth keeping apart: an INDEX of what exists, and a
-- QUERY that marks part of it. Neither draws anything -- Nav and Page ask
-- what matched and dim the rest themselves, so search never becomes a
-- second renderer with its own idea of what a row looks like.
--
-- -- It indexes pages that have never been drawn --
--
-- The index is built from `app.routeIndex`, not from live widgets. A route
-- node carries its page DECLARATION -- groups, fields, labels, binds -- and
-- that table exists whether or not anything has rendered it. So searching
-- reaches the whole panel on the first keystroke, including pages the
-- reader has never opened, and it does it without building a single widget.
-- That is the distinction behind the lazy-page rule: page BODIES are
-- evaluated here, page WIDGETS are not.
--
-- -- It dims, it does not filter --
--
-- Results stay where they are and everything else fades. A list of hits
-- would be easier to build and worse to use: it throws away the grouping
-- that tells you what a setting is FOR, and it moves things under the
-- cursor. Dimming keeps the map intact and just lowers the contrast on the
-- parts you did not ask about.
--
-- The one concession: a branch holding a match expands while a query is
-- live, because a match inside a collapsed branch is a match you cannot
-- see. The reader's own expansion is remembered and restored on clear.
-- ============================================================
local ADDON, ns = ...

ns.search = {}

local DIM = 0.25          -- alpha for everything the query did not match

-- ============================================================
-- Index
-- ============================================================

local function Add(parts, v)
    if v == nil then return end
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = v:lower()
    elseif t == "number" or t == "boolean" then
        parts[#parts + 1] = tostring(v):lower()
    end
end

-- Everything about one field that a reader might type. Labels and
-- descriptions are the obvious half; the BIND PATH is the other, and it is
-- the half that makes the box useful to whoever is building the options
-- rather than reading them -- "raidBuffSize" finds its own field.
local function FieldHay(field, groupTitle)
    local parts = {}
    Add(parts, ns.FieldLabel(field))
    Add(parts, field.desc)
    Add(parts, field.bind)
    Add(parts, field.id)
    for _, b in pairs(field.binds or {}) do
        Add(parts, ns.BindPath(b))
        if type(b) == "table" then Add(parts, b.id) end
    end
    -- A note has no label and no binding; its text IS its content.
    if type(field.text) == "string" then Add(parts, field.text) end
    Add(parts, groupTitle)
    return table.concat(parts, " ")
end

-- A page may be declared as a function, so that building it can be
-- deferred. Resolving one here costs a table, not a widget.
function ns.search.Build(app)
    local index = { routes = {}, fields = {} }

    for key, entry in pairs(app.routeIndex or {}) do
        local node = entry.node
        local rec  = { key = key, entry = entry, fields = {} }

        local parts = {}
        Add(parts, node.title)
        Add(parts, node.id)
        Add(parts, node.desc)
        rec.hay = table.concat(parts, " ")

        -- The SAME table the render will use -- see ns.page.Resolve. An
        -- index keyed by table identity against a page rebuilt per call
        -- matches nothing.
        local page = ns.page.Resolve(app, entry)
        -- A TREE GROUP member's route page is the COLLECTION's page -- the
        -- page the tree sits on, the same one every member shows -- so
        -- resolving it indexes the tree card over and over and the
        -- member's own settings not at all. The pane draws
        -- ns.collections.MemberPage; index that, or nothing inside a member
        -- is findable and every card in the pane dims as unmatched.
        local mNode = entry.node
        local groups
        if mNode.bpCollection and mNode.bpMember and mNode.bpCollection.treeGroup
           and ns.collections and ns.collections.MemberPage then
            page = ns.collections.MemberPage(app, mNode.bpCollection,
                                             mNode.bpMember.key) or page
            -- A member with SUBTABS: the tab route indexes that tab's
            -- groups, and the member route indexes its header -- so a hit
            -- lights the tab it is on, not the member as a whole.
            if page and mNode.bpTab then
                groups = ns.collections.TabGroups(page, mNode.bpTab.id) or {}
            end
        end
        if page then
            -- IN-PAGE SUBTABS ARE INDEXED WHOLE, not just the tab on screen.
            --
            -- A `subtabs` group carries no fields of its own -- it expands at
            -- RENDER time into the selected tab's groups -- so walking
            -- page.groups indexed nothing inside any of them: every setting
            -- on a buff container's Conditions tab, or on any tab of a
            -- section built this way, was unfindable unless it happened to
            -- be the tab last opened. Each field remembers which tab it came
            -- from, and Rematch below pulls that tab to the front when it
            -- holds a hit -- so a match is not merely counted, it is shown.
            local function Walk(list, subKey, tabId)
                for gi, group in ipairs(list or {}) do
                    local tabs = group.subtabs
                    if type(tabs) == "function" then tabs = tabs(nil) end
                    if type(tabs) == "table" then
                        local key = group.subtabKey or ("subtabs:" .. tostring(gi))
                        for _, tb in ipairs(tabs) do
                            local tg = tb.groups
                            if type(tg) == "function" then tg = tg(nil) end
                            Walk(tg, key, tb.id)
                        end
                    else
                        for _, field in ipairs(group.fields or {}) do
                            local hay = FieldHay(field, group.title)
                            rec.fields[#rec.fields + 1] = {
                                field = field, group = group, hay = hay,
                                subKey = subKey, tabId = tabId,
                            }
                        end
                    end
                end
            end
            Walk(groups or page.groups)
        end
        index.routes[key] = rec
    end

    app.searchIndex = index
    return index
end

-- ============================================================
-- Query
-- ============================================================

local function Terms(text)
    local out = {}
    for word in tostring(text or ""):lower():gmatch("%S+") do out[#out + 1] = word end
    return out
end

-- AND, not OR. Two words narrow; they do not widen. "buff size" should
-- find the one field about the size of buffs, not every field mentioning
-- either word -- which on an options panel this size is most of them.
local function Hits(hay, terms)
    for _, t in ipairs(terms) do
        if not hay:find(t, 1, true) then return false end
    end
    return true
end

function ns.search.Query(app)
    return app.searchText
end

function ns.search.IsActive(app)
    return app.searchText ~= nil and app.searchText ~= ""
end

-- Does this field survive the current query? Called per field per render,
-- so it is a set lookup rather than a re-match.
function ns.search.FieldMatches(app, field)
    if not ns.search.IsActive(app) then return true end
    return app.searchFields ~= nil and app.searchFields[field] == true
end

-- Routes on the PATH to a match count as matching, or the branch a hit
-- lives in would fade out around it.
function ns.search.RouteMatches(app, key)
    if not ns.search.IsActive(app) then return true end
    return app.searchRoutes ~= nil and app.searchRoutes[key] == true
end

function ns.search.GroupMatches(app, group)
    if not ns.search.IsActive(app) then return true end
    -- A card with NOTHING TO MATCH cannot fail to match. searchGroups is
    -- populated from matched FIELDS, so a card that has none -- a tree
    -- group, a spacer, a card that is all title -- could never be in it,
    -- and was dimmed to a quarter by any query at all. On a tree group
    -- that takes the list, the rule and the pane down with it, which is
    -- why typing read as the tree disappearing. The rows inside a tree do
    -- their own dimming; the card around them is furniture.
    if group and (group.tree or not group.fields or #group.fields == 0) then
        return true
    end
    return app.searchGroups ~= nil and app.searchGroups[group] == true
end

function ns.search.DimAlpha() return DIM end

-- ============================================================
-- Marking the matched text
-- ============================================================
--
-- Tinting the matched glyphs rather than drawing a block behind them. The
-- block version has to measure text to find where a match begins and how
-- wide it is, which works only for single-line, left-justified, untruncated
-- text -- so notes, which wrap, could not have had it. An escape code lets
-- the CLIENT do the layout, so one mechanism covers wrapped text, truncated
-- labels and repeated matches alike.
--
-- Applied at PAINT time and never written back to the node. Clearing the
-- query therefore restores the original text on the next render with
-- nothing to undo -- the marked string only ever exists on its way to
-- SetText.

local function Hex(c)
    return ("%02x%02x%02x"):format(
        math.floor((c[1] or 1) * 255 + 0.5),
        math.floor((c[2] or 1) * 255 + 0.5),
        math.floor((c[3] or 1) * 255 + 0.5))
end

-- Every span of `text` matched by any term, merged.
--
-- Merging matters: two terms that overlap or touch -- "font" and "ont", or
-- "font" and "size" in "fontsize" -- would otherwise be wrapped
-- individually, nesting one code inside another and leaving a stray |r
-- mid-word where the inner span closes.
local function Spans(text, terms)
    local lower = text:lower()
    local raw = {}
    for _, t in ipairs(terms) do
        local from = 1
        while true do
            local a, b = lower:find(t, from, true)
            if not a then break end
            raw[#raw + 1] = { a, b }
            from = a + 1          -- overlapping occurrences count
        end
    end
    if #raw == 0 then return nil end

    table.sort(raw, function(x, y) return x[1] < y[1] end)
    local out = { raw[1] }
    for i = 2, #raw do
        local prev, cur = out[#out], raw[i]
        if cur[1] <= prev[2] + 1 then
            if cur[2] > prev[2] then prev[2] = cur[2] end
        else
            out[#out + 1] = cur
        end
    end
    return out
end

function ns.search.Mark(app, text)
    if type(text) ~= "string" or text == "" then return text end
    -- Callers hand this whatever they have, including nil during layout of
    -- a field with no ctx yet, so guard rather than making every one of
    -- them check first.
    if not app then return text end
    if not ns.search.IsActive(app) then return text end
    -- Text that carries its own color codes is left exactly as it is.
    -- Splicing a span into an existing one is how a label ends up the wrong
    -- color for the rest of its line, and nothing currently needs it.
    if text:find("|c", 1, true) then return text end

    local terms = {}
    for word in app.searchText:gmatch("%S+") do terms[#terms + 1] = word end
    local spans = Spans(text, terms)
    if not spans then return text end

    local hex = Hex((app.skin and app.skin.searchHit) or { 1, 0.91, 0.63 })
    local out, at = {}, 1
    for _, sp in ipairs(spans) do
        out[#out + 1] = text:sub(at, sp[1] - 1)
        -- Sliced from the ORIGINAL, not the lowercased copy the positions
        -- came from, so "Buff" keeps its capital.
        out[#out + 1] = "|cff" .. hex .. text:sub(sp[1], sp[2]) .. "|r"
        at = sp[2] + 1
    end
    out[#out + 1] = text:sub(at)
    return table.concat(out)
end

-- Mark every ancestor of a matching route, so the tree keeps a legible
-- path down to the hit instead of a lit row inside faded parents.
local function MarkAncestors(app, key, out)
    local entry = app.routeIndex and app.routeIndex[key]
    while entry do
        out[entry.key] = true
        entry = entry.parent and app.routeIndex[entry.parent] or nil
    end
end

-- RE-MATCH THE LIVE QUERY against tables that exist NOW.
--
-- The match sets are keyed by the field and group TABLES a page was built
-- from (see FieldMatches / GroupMatches), so anything that rebuilds a page
-- leaves them pointing at tables nothing draws from any more: every card
-- fails to match and the page renders dimmed with no highlight in it. This
-- is the repair, called by ns.page.ClearPageCache -- the one path every
-- structural change already takes.
--
-- It re-runs the MATCH, not the query: no re-parse, no navigation, no
-- expansion changes, and NO render -- the caller is already on its way to
-- one. A dead query does nothing, which is what makes this cheap to call
-- from a path that runs whether or not anybody is searching.
local Rematch
function ns.search.Rematch(app) return Rematch(app) end

function ns.search.Apply(app, text)
    local terms = Terms(text)
    app.searchText = (#terms > 0) and table.concat(terms, " ") or nil

    if not ns.search.IsActive(app) then
        app.searchFields, app.searchRoutes, app.searchGroups = nil, nil, nil
        app.searchSubtabs = nil
        ns.search.RestoreExpansion(app)
        -- Refresh renders the page as its last step, so calling both would
        -- build the page twice for one keystroke.
        ns.nav.Refresh(app)
        return
    end

    Rematch(app)
    ns.search.ExpandToMatches(app)
    ns.nav.Refresh(app)
end

-- The matching half of Apply, shared with the repair above so the two
-- cannot answer differently.
function Rematch(app)
    if not ns.search.IsActive(app) then
        app.searchFields, app.searchRoutes, app.searchGroups = nil, nil, nil
        app.searchSubtabs = nil
        return
    end
    local terms = Terms(app.searchText)
    if not app.searchIndex then ns.search.Build(app) end

    local fields, routes, groups, subtabs = {}, {}, {}, {}
    for key, rec in pairs(app.searchIndex.routes) do
        local any = Hits(rec.hay, terms)
        for _, f in ipairs(rec.fields) do
            if Hits(f.hay, terms) then
                fields[f.field] = true
                groups[f.group] = true
                -- The FIRST tab of a strip that holds a hit wins it: the
                -- page opens on the tab the reader is being sent to instead
                -- of on whichever one it was left on, where the match they
                -- can see counted is nowhere on screen.
                if f.subKey and subtabs[f.subKey] == nil then
                    subtabs[f.subKey] = f.tabId
                end
                any = true
            end
        end
        -- A route whose own TITLE matched lights up whole: the reader asked
        -- for that section, so dimming every field inside it would answer a
        -- question they did not ask.
        if Hits(rec.hay, terms) then
            for _, f in ipairs(rec.fields) do
                fields[f.field] = true
                groups[f.group] = true
            end
        end
        if any then MarkAncestors(app, key, routes) end
    end

    app.searchFields, app.searchRoutes, app.searchGroups = fields, routes, groups
    app.searchSubtabs = subtabs
end

-- ============================================================
-- Expansion
-- ============================================================
--
-- Remembered ONCE, on the transition into a live query, and put back when
-- it clears. Snapshotting on every keystroke would capture the state search
-- itself just forced open, and the reader's own arrangement would be gone
-- after the first character.

function ns.search.ExpandToMatches(app)
    if not app.searchExpandSaved then
        local saved = {}
        for k, v in pairs(app.expanded or {}) do saved[k] = v end
        app.searchExpandSaved = saved
    end
    app.expanded = app.expanded or {}
    for key in pairs(app.searchRoutes or {}) do
        app.expanded[key] = true
    end
end

function ns.search.RestoreExpansion(app)
    if not app.searchExpandSaved then return end
    app.expanded = app.searchExpandSaved
    app.searchExpandSaved = nil
end

-- ============================================================
-- The box
-- ============================================================

local BOX_H = 22

local RAIL_MARGIN = 8     -- symmetric, so the box reads as centered in the rail
local RAIL_PAD    = 6     -- above AND below the box, one number for both

-- SearchBoxTemplate's border art is not flush with its frame rect, so a
-- centered frame does not look centered. This is the correction, in pixels,
-- to the right. A constant rather than a measurement: the measurement was
-- two rounds of being wrong about a number that never changes.
local RAIL_NUDGE  = 2

-- The rail's header: a real frame that OWNS the box and its padding.
--
-- The tree used to start at an offset the tree itself computed, from a
-- reserve this file returned as a constant, with each end adding its own
-- padding -- 6 from one, 10 from the other, so the gap under the box was
-- never the gap above it. Worse, it was arithmetic evaluated at render
-- time, so whether the tree got the right number depended on this file and
-- Nav having run in a particular order relative to the spec being set. On a
-- fresh open they did not line up and the box drew over the first row.
--
-- A frame fixes both. Its height is the single source of truth for how much
-- room the box takes, and the tree anchors BELOW it rather than to a
-- computed offset -- anchors resolve lazily and declaratively, so ordering
-- stops being something anyone has to think about. It is always present,
-- with zero height when there is no box, so nothing is ever anchored to a
-- frame that is not there.
function ns.search.RailHeader(app)
    if not app.railHeader then
        local rail = app:GetRegion("rail")
        if not rail then return nil end
        local h = CreateFrame("Frame", nil, rail)
        -- BELOW the rail's head, which is collapsed to nothing in every
        -- layout but the full-height-rail one. Anchoring to it rather than
        -- to the rail costs nothing in those layouts and is what keeps the
        -- search box off the panel's title in this one.
        local head = app.regions and app.regions.railbrand
        h:SetPoint("TOPLEFT",  head or rail, "BOTTOMLEFT",  0, 0)
        h:SetPoint("TOPRIGHT", head or rail, "BOTTOMRIGHT", 0, 0)
        h:SetHeight(0.001)
        app.railHeader = h
    end
    return app.railHeader
end
local function BuildBox(app)
    if app.searchBox then return app.searchBox end

    -- SearchBoxTemplate brings its own magnifier, clear button and
    -- instruction text, and its own focus behavior. Wrapping it is the
    -- whole point of the native-first rule: none of that is worth rebuilding
    -- and all of it is what a reader expects a search box to do.
    local box = CreateFrame("EditBox", nil, app.frame, "SearchBoxTemplate")
    box:SetAutoFocus(false)
    box:SetHeight(BOX_H)

    -- HOOK, not SetScript.
    --
    -- The template's own OnTextChanged is what shows and hides the clear
    -- button and the instruction text. Replacing it left the X running on
    -- nothing, and had this file hand-rolling half of what the template
    -- already did. Hooking keeps the native behavior and adds to it, which
    -- is the whole reason for wrapping a template rather than building one.
    box:HookScript("OnTextChanged", function(self)
        -- No userInput gate.
        --
        -- The clear button sets the text from code, so OnTextChanged fires
        -- with userInput false and a gate on it drops the event: the box
        -- went empty, the query did not, and the panel stayed dimmed --
        -- across a close and reopen too, since the query lives on the app
        -- and not on the frame. What actually needs guarding is redundant
        -- work, so guard on that instead. This catches every route that
        -- changes the text: typing, the X, escape, and anything that calls
        -- SetText later.
        local text = self:GetText() or ""
        if text == (app.searchPending or app.searchText or "") then return end
        app.searchPending = text

        -- Debounced on the app's own scheduler: an index scan per keystroke
        -- is exactly the shape of work the tiers exist for, and typing is
        -- the most continuous input there is.
        ns.effects.Schedule(app, { tier = "debounce", key = "bp:search", id = "query" },
            function()
                app.searchPending = nil
                ns.search.Apply(app, text)
            end)
    end)

    -- Escape clears the text and nothing else. The resulting OnTextChanged
    -- does the applying, so there is ONE route into Apply rather than two
    -- that can disagree about what the box currently says.
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- The same mouse behavior every other text field in the panel has: a
    -- click puts the caret where you clicked, a double click takes the
    -- whole query. The template does not bring it, and this was the one box
    -- in the panel where retyping a search meant selecting it by hand
    -- first. Installed once, at build: unlike a pooled field's box, this
    -- one is never released and never has its scripts scrubbed.
    if ns.InstallTextFieldMouse then ns.InstallTextFieldMouse(box) end

    app.searchBox = box
    return box
end

-- Which region a "top" box actually lands in.
--
-- "top" names a POSITION, not a region: it means "up with the section
-- buttons". Where those buttons live is the app's chrome decision -- a
-- strip under the title bar in one layout, the title bar itself in another
-- -- and the box has to follow them. Targeting the `top` region
-- unconditionally put the box in a region with no height whenever the
-- buttons were in the title bar, which is a box you cannot see.
-- Does the strip exist right now? It is only drawn when something has
-- given it height, which in practice means a button bar is mounted there.
local function StripLive(app)
    return (app.topHeight or 0) > 0
end

function ns.search.TopHost(app)
    -- An EXPLICIT region wins, when it is there to be used.
    --
    -- "top" means "up with the section buttons, wherever those are", which
    -- is the right default and the wrong answer when both a title bar and a
    -- strip are showing and the reader has an opinion about which. So the
    -- two regions are nameable outright, and a name that cannot be honored
    -- falls back rather than putting the box somewhere invisible: the title
    -- bar always exists, the strip does not.
    -- The title bar is not a constant. A full-height-rail layout collapses
    -- it to nothing, so every fallback that ended "and the title bar is
    -- always there" now has to ask.
    local titleLive = app.titlebarLive ~= false
    local want = app.searchSpec and app.searchSpec.placement
    if want == "titlebar" then
        if titleLive then return "titlebar" end
        return StripLive(app) and "top" or "rail"
    end
    if want == "strip" then
        if StripLive(app) then return "top" end
        return titleLive and "titlebar" or "rail"
    end

    -- 1. Wherever the section buttons actually are.
    for _, nav in ipairs(app.navs or {}) do
        if nav.region == "top" or nav.region == "titlebar" then return nav.region end
    end
    -- 2. The strip, if something else has given it height.
    if (app.topHeight or 0) > 0 then return "top" end
    -- 3. The title bar, which always exists and always has height.
    --
    -- This is the tree-only layout: no button bar anywhere, so there is no
    -- strip and the `top` region is zero-height and hidden. Returning it
    -- anyway put the box in a region that is not drawn -- a box you cannot
    -- see. The title bar is the honest reading of "top" when nothing else
    -- occupies it, and the anchors there hang off the title text and the
    -- close button rather than off any buttons, so nothing about that case
    -- needs a bar to exist.
    --
    -- Unless it has been collapsed, which is what a full-height rail does:
    -- there the rail is the region guaranteed to exist -- the layout is not
    -- reachable without one -- so the box goes to its header rather than
    -- into a bar with no height.
    if titleLive then return "titlebar" end
    return "rail"
end

-- How much horizontal room the box takes out of that region, and on which
-- side. Nav asks this before laying the button bar out.
function ns.search.TopReserve(app, regionName)
    local spec = app.searchSpec
    if not spec then return 0, nil end
    local p = spec.placement
    if p ~= "top" and p ~= "titlebar" and p ~= "strip" then return 0, nil end
    -- Only the region the box actually landed in gives up width. Asking
    -- for the strip in a layout that has none puts the box in the title
    -- bar, and it would be the title bar's buttons that have to move over.
    if regionName and regionName ~= ns.search.TopHost(app) then return 0, nil end
    return (spec.width or 180) + 12, (spec.align == "left") and "left" or "right"
end

-- How much vertical room the box takes off the top of the rail.
-- Kept for the tree's SIGNATURE, which needs a number it can compare rather
-- than a frame. The geometry itself no longer goes through here.
function ns.search.RailReserve(app)
    local spec = app.searchSpec
    if not spec then return 0 end
    -- A box that ASKED for a top region and could not have one is in the
    -- rail, and the tree's signature has to see that or the rows keep the
    -- height the box is now using.
    if spec.placement ~= "rail" and ns.search.TopHost(app) ~= "rail" then return 0 end
    return RAIL_PAD * 2 + BOX_H
end

function ns.search.Layout(app)
    local spec = app.searchSpec
    local header = ns.search.RailHeader(app)
    -- The header only reserves room while the box is actually in the rail.
    -- Collapsed rather than hidden, so the tree stays anchored to something
    -- real and simply finds it has no height.
    -- Collapsed to the padding, not to nothing: with no box the tree still
    -- wants its usual breathing room above the first row, and keeping that
    -- in the header means it stays one number in one place.
    if header and not spec then
        header:SetHeight(RAIL_PAD)
    end
    if not spec then
        if app.searchBox then app.searchBox:Hide() end
        return
    end

    local box = BuildBox(app)
    box:ClearAllPoints()

    -- Asking for a region is not getting one: TopHost answers "rail" when
    -- the layout has collapsed every region a top box could live in, and
    -- the box then takes the rail branch below rather than being parented
    -- to something with no height.
    local wantsRegion = (spec.placement == "top")
                     or (spec.placement == "titlebar")
                     or (spec.placement == "strip")
    local host       = wantsRegion and ns.search.TopHost(app) or "rail"
    local inRegion   = wantsRegion and host ~= "rail"

    if inRegion then
        -- The rail header gives its room back: the box is not in it.
        if header then header:SetHeight(RAIL_PAD) end
        -- One item in a row of them, so it keeps a declared width.
        local region = app:GetRegion(host)
        box:SetParent(region)
        box:SetWidth(spec.width or 180)

        if host == "titlebar" then
            -- Anchored to the things beside it rather than to the bar's
            -- edges, so it stays correct if the title or the close button
            -- ever changes size: left means "after the addon name", right
            -- means "before the X".
            -- No vertical anchor anywhere in this branch, deliberately.
            --
            -- A LEFT or RIGHT point already centers a frame vertically
            -- against what it is anchored to, so the box centers in the
            -- title bar or the strip for free, and keeps centring when a
            -- wrapped button bar makes the region taller. The version this
            -- replaced computed a row offset instead, which meant this file
            -- carried its own copy of Nav.lua's row metrics and the two had
            -- to be kept in agreement by hand.
            if spec.align == "left" then
                -- Shown, not merely present: the title moves to the rail's
                -- head in a full-height-rail layout, and anchoring after a
                -- hidden one left the box floating in from the edge.
                local titled = app.titleText and app.titleText:IsShown()
                local anchor = titled and app.titleText or region
                box:SetPoint("LEFT", anchor, titled and "RIGHT" or "LEFT", titled and 18 or 8, 0)
            elseif app.closeButton then
                box:SetPoint("RIGHT", app.closeButton, "LEFT", -8, 0)
            else
                box:SetPoint("RIGHT", region, "RIGHT", -8, 0)
            end
        elseif spec.align == "left" then
            box:SetPoint("LEFT", region, "LEFT", 8, 0)
        else
            box:SetPoint("RIGHT", region, "RIGHT", -8, 0)
        end
    else
        -- CENTERED in the rail's header, and sized from the rail.
        --
        -- The width is SET rather than derived from a left and a right
        -- anchor: an explicit width beats a width implied by two horizontal
        -- anchors, so the version that set both stayed 180 wide pinned near
        -- the left edge with the rest of the rail empty. One CENTER point
        -- and an outright width cannot be contradicted that way.
        --
        -- Re-derived on every Layout rather than once, so it follows the
        -- rail when its width is dragged.
        local rail = app:GetRegion("rail")
        header:SetHeight(RAIL_PAD * 2 + BOX_H)

        box:SetParent(header)
        local rw = rail:GetWidth() or 0
        if rw > 0 then box:SetWidth(math.max(40, rw - RAIL_MARGIN * 2)) end
        box:SetPoint("CENTER", header, "CENTER", RAIL_NUDGE, 0)
    end

    if spec.placeholder and box.Instructions then
        box.Instructions:SetText(spec.placeholder)
    end
    box:Show()
end

-- spec = {
--   placement   = "rail"      -- a strip across the top of the rail
--               | "top"       -- up with the section buttons, wherever they are
--               | "titlebar"  -- the title bar, named outright
--               | "strip"     -- the button strip, named outright
--   align       = "left"|"right",   -- the three non-rail placements
--   width, placeholder,
-- }
-- nil removes the box entirely: search is opt-in, and an app that never
-- calls this pays nothing for it -- not even an index.
function ns.search.SetSearch(app, spec)
    app.searchSpec = spec
    if not spec then
        -- Removing the box has to clear the QUERY too, or the panel is left
        -- permanently dimmed with nothing on screen to explain why and no
        -- way to type the filter back out.
        if app.searchBox then app.searchBox:SetText("") end
        app.searchText, app.searchPending = nil, nil
        app.searchFields, app.searchRoutes, app.searchGroups = nil, nil, nil
        ns.search.RestoreExpansion(app)
    end
    -- Refresh lays the box out and re-renders everything below it.
    ns.nav.Refresh(app)
end
