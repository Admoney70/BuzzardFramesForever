-- ============================================================
-- BuzzardFramesOptions: Pages_CustomFrameSections.lua
-- The Custom Frame Groups SCOPE: one proxy over BuzzardFrames, one
-- assembler, and the route tree that renders the Raid/Party page
-- builders against a custom frame group's own flat.
--
-- WHY A PROXY RATHER THAN A SECOND SET OF PAGES. Every Raid/Party page
-- file reaches the addon through exactly one line -- `local function BF()
-- return BuzzardFramesOptions:BF() end` -- and every value it reads or
-- writes goes through a BF method: GetSectionProfile, GetModifyingProfile,
-- WriteSectionKey, SectionKeyTable, GetAurasSubcatProfile. Answer those
-- methods for the selected custom frame group and the SAME declarations
-- edit that group. Nothing is copied, so a field added to the Text page is
-- on the Custom Frame Groups Text page in the same commit, which is the
-- property the Ace panel's proxySelf had (Options_CustomFrameSections.lua)
-- and the reason this port keeps its shape.
--
-- WHAT THE SCOPE IS BOUND AROUND. Three moments, all of them in code this
-- file owns:
--   1. the page BUILD, so a structural read (the Aura Text mode switch,
--      the section-name stamp) sees the right scope -- including under the
--      search index's sweep, which builds every route's page;
--   2. the built page's own `db`, which the library calls at the top of
--      every render and every tree-group pane render, so every `bind` and
--      every predicate in that render is answered for the group;
--   3. each `set`, `get`, `hidden` and `onChange`, so a commit -- and a
--      debounced effect that fires after the reader has navigated away --
--      still lands on the group it was for.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON. Same rule as every other
-- page file: BuzzardFrames is read inside the functions, at the moment the
-- panel is used.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The REAL addon. Deliberately not the file-local `BF()` every page file
-- has: this file is the thing that decides what that accessor answers, so
-- it must always be able to reach past its own proxy.
local function RealBF() return _G.BuzzardFrames end

-- ── The bound scope ────────────────────────────────────────────
--
-- nil means Raid/Party -- the ordinary addon. Anything else is a scope
-- object (below), and BuzzardFramesOptions:BF() answers with its proxy.
local currentScope = nil

local function SetScope(scope) currentScope = scope end

-- The accessor every page file's `BF()` now calls.
function BuzzardFramesOptions:BF()
    return (currentScope and currentScope.proxy) or _G.BuzzardFrames
end

-- Bind a scope for the duration of one call and ALWAYS put it back --
-- through the error path too, or a page builder that throws would leave
-- every later Raid/Party read pointed at a custom frame group.
function BuzzardFramesOptions:WithScope(scope, fn, ...)
    local prev = currentScope
    currentScope = scope
    local ok, a, b, c = pcall(fn, ...)
    currentScope = prev
    if not ok then error(a, 0) end
    return a, b, c
end

-- ── The groups, and the ONE panel-wide selection ───────────────
--
-- The Ace panel kept a selected-group INDEX per section (one variable
-- inside the SECTION_DEFS loop, another shared by the two aura pages, a
-- third for Frames), so picking "Group 2" on Text and then opening Icons
-- put the reader back on Group 1. The owner's ruling is one selection for
-- the whole Custom Frame Groups section.
--
-- It is keyed by the group's stable cfgFlatID rather than by its position:
-- an index silently retargets when a group is removed or reordered --
-- clamping keeps it in range but points it at a DIFFERENT group, and the
-- page then edits that one without saying so. A flat ID that no longer
-- names a live group falls back to the first, which is the same
-- last-resort the Ace clamp ended in.
local selectedFlatID = nil

local function Groups()
    local bf = RealBF()
    local p  = bf and bf.cfgDB and bf.cfgDB.profile
    if not p then return {} end
    p.customFrameGroups = p.customFrameGroups or {}
    return p.customFrameGroups
end

function BuzzardFramesOptions:CFGGroups() return Groups() end

-- The selected group's position, or nil when there are no groups at all.
-- GetCFGFlatID mints an ID for a group that predates the scheme, so this
-- can never miss a live group for want of one.
function BuzzardFramesOptions:CFGSelectedIndex()
    local bf   = RealBF()
    local list = Groups()
    if #list == 0 then return nil end
    if selectedFlatID and bf and bf.GetCFGFlatID then
        for i = 1, #list do
            if bf:GetCFGFlatID(i) == selectedFlatID then return i end
        end
    end
    return 1
end

function BuzzardFramesOptions:CFGSelectedGroup()
    local i = self:CFGSelectedIndex()
    return i and Groups()[i] or nil
end

function BuzzardFramesOptions:CFGSelectGroup(index)
    local bf = RealBF()
    selectedFlatID = (bf and bf.GetCFGFlatID and index) and bf:GetCFGFlatID(index) or nil
end

-- Used by the route observer on the Custom Frame Groups collection: its
-- member routes are keyed by cfgFlatID, so entering one IS a selection.
function BuzzardFramesOptions:CFGSelectByFlatID(flatID)
    if type(flatID) == "string" and flatID:match("^cfg_flat_") then
        selectedFlatID = flatID
    end
end

-- ── The refresh the Ace setters appended ───────────────────────
--
-- Every Raid/Party side effect walks BF.activeFrames -- the raid and party
-- frames -- and does nothing whatever for a custom frame group. The Ace
-- answer was not to replace them but to APPEND
-- (Options_CustomFrameSections.lua:268-285), and running the Raid/Party
-- effect as well is wasteful but harmless: it re-reads each frame's own
-- profile and re-applies unchanged values. Kept exactly.
local function WipeCFGCaches()
    local bf = RealBF()
    local p  = bf and bf.cfgDB and bf.cfgDB.profile
    local list = p and p.customFrameGroups
    if not list then return end
    for _, grp in ipairs(list) do
        local flat = grp and grp.flat
        if flat then
            if flat._sectionCache then
                for k in pairs(flat._sectionCache) do flat._sectionCache[k] = nil end
            end
            if flat._auraCache then
                for k in pairs(flat._auraCache) do flat._auraCache[k] = nil end
            end
            -- Mark dirty so UpdateAuraSizeCache rebuilds it.
            if bf.InvalidateFlatAuraCache then bf:InvalidateFlatAuraCache(flat) end
        end
    end
end

local function RefreshCustomFrames()
    local bf = RealBF()
    if not bf then return end
    if InCombatLockdown() then return end
    if bf.RefreshCustomFrameHeaders then bf:RefreshCustomFrameHeaders() end
    if bf.UpdateCustomFrameTestFrames then bf:UpdateCustomFrameTestFrames() end
end

-- Options_CustomFrameSections.lua:145-172, step for step.
local function RefreshCFGAfterSettingChange()
    local bf = RealBF()
    if not bf then return end
    WipeCFGCaches()
    RefreshCustomFrames()
    if bf.RefreshCFGAurasOnly  then bf:RefreshCFGAurasOnly()  end
    if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
end
BuzzardFramesOptions.RefreshCFGAfterSettingChange = RefreshCFGAfterSettingChange

-- The aura pages' own version: Options_CustomFrameAuras.lua:51-90, and
-- dispatched under the SAME debounce key the Ace file used
-- ("cfgAurasRefresh"). The key matters -- the container pages coalesce on
-- "acCustomContainers" on purpose so both panels share one pass, and a CFG
-- aura edit borrowing a Raid/Party key would cancel that panel's pending
-- work instead of adding to it.
local function DoRefreshCustomFrameAuras()
    local bf = RealBF()
    if not bf then return end
    if InCombatLockdown() then return end
    WipeCFGCaches()
    if bf.RefreshCFGAurasOnly       then bf:RefreshCFGAurasOnly()       end
    if bf.UpdateCustomFrameTestFrames then bf:UpdateCustomFrameTestFrames() end
    if bf.RefreshPreviewDummyAuras  then bf:RefreshPreviewDummyAuras()  end
end

local function RefreshCustomFrameAuras()
    local bf = RealBF()
    if not bf then return end
    if bf.MouseUpOption then
        bf:MouseUpOption("cfgAurasRefresh", DoRefreshCustomFrameAuras)
    else
        DoRefreshCustomFrameAuras()
    end
end

-- ── The proxy ──────────────────────────────────────────────────
--
-- Every method NOT overridden here is called with the proxy as `self`, so
-- a BuzzardFrames method that internally calls self:GetSectionProfile or
-- self:GetModifyingProfile re-enters the override. That is the property
-- that makes the write routers and GetSectionProfileForFrame behave, and
-- it is why the Ace version worked at all.

-- The one field the proxy must NOT forward. `bf._modifyingFlat = v` is a
-- Raid/Party strip writing which Layout it edits; a custom frame group is
-- not a Layout, and letting that store through would retarget the
-- Raid/Party pages from a page that has no business doing so. The strips
-- are dropped from every page rendered under a scope, so nothing
-- legitimate lands here -- this is the belt to that braces.
local NEVER_WRITE = { _modifyingFlat = true }

local function MakeProxy(scope)
    local OVER = {
        -- The flat being edited.
        GetModifyingProfile = function() return scope:Flat(), false end,

        -- The section table for the group -- RAW, never the merged view,
        -- because GetSectionProfileForFrame reads a custom frame group's
        -- raw table too (Core_ProfileAPI.lua) and GetMergedSectionView
        -- short-circuits on IsPerLayoutSection: with every Raid/Party
        -- subtab toggle off it would hand back the GLOBAL while the
        -- runtime reads the group's own table.
        --
        -- The `flat` ARGUMENT is honored, and that is load-bearing rather
        -- than tidiness. Every un-overridden BuzzardFrames method runs with
        -- `self` = this proxy, so a Raid/Party refresh chain appended to a
        -- custom frame group setter re-enters here -- and several of those
        -- deliberately ask about the ACTIVE raid/party flat
        -- (Pages_Text.lua RefreshNameFont, Core_Refresh.lua
        -- UpdateGroupLabels, GetSectionProfileForFrame's own RP branch).
        -- Answering those with the group's table restyles the live raid
        -- frames with the group's values. The Ace proxy took the argument
        -- too (Options_CustomFrameSections.lua:183-198); dropping it was a
        -- regression against the behavior being ported.
        GetSectionProfile = function(_, section, flat)
            if flat ~= nil and flat ~= scope:Flat() then
                return RealBF():GetSectionProfile(section, flat)
            end
            return scope:ReadSection(section)
        end,

        -- "Is this section / subtab this scope's own?" -- the same question
        -- the Raid/Party pages ask of a Layout, answered for the group by
        -- the engine (BF:IsCFGSectionOverride / BF:IsCFGSubtabOverride:
        -- master AND subtab, absent = on). Until 2026-09-13 both
        -- hard-answered `true`, because the group had no per-subtab
        -- answer to give; Options_CustomFrameSections.lua:204-231 records
        -- what missing the subtab one cost when it was routed the other
        -- way (a setting persisted only while the matching Raid/Party
        -- toggle happened to be on). A section with no override flag --
        -- and the aura sections, which keep their two group-level
        -- masters -- is always the group's own.
        IsPerLayoutSection       = function(_, section)
            return scope:IsSectionOwn(section)
        end,
        IsPerLayoutSectionSubtab = function(_, section, subtabId)
            return scope:IsSubtabOwn(section, subtabId)
        end,
        IsPerLayoutAurasSubcat   = function() return true end,
        IsPerLayoutAurasKey      = function() return true end,

        -- The two write routers, answered OUTRIGHT rather than left to
        -- WriteSectionKey's subtab lookup. A key absent from
        -- SECTION_KEY_SUBTAB resolves to no subtab and falls through to
        -- rpDB.profile[section] -- a custom frame group edit silently
        -- changing the raid frames. Every bind currently declared is in
        -- that map, but the invariant is invisible and one new field
        -- breaks it, so the class is removed rather than audited.
        WriteSectionKey = function(_, section, key, val)
            local bf = RealBF()
            local t  = scope:Section(section)
            if t then t[key] = val end
            if bf and bf._InvalidateSectionViews then
                bf:_InvalidateSectionViews(section)
            end
            return true, scope:Flat(), nil
        end,
        SectionKeyTable = function(_, section, key)
            local bf = RealBF()
            local t  = scope:Section(section)
            if not t then return nil end
            local v = rawget(t, key)
            if type(v) ~= "table" then
                v = (type(t[key]) == "table" and bf and bf.DeepCopy)
                    and bf:DeepCopy(t[key]) or {}
                t[key] = v
            end
            if bf and bf._InvalidateSectionViews then
                bf:_InvalidateSectionViews(section)
            end
            return v
        end,

        -- Auras: the group's own sub-category, exactly as the override-ON
        -- branch of the runtime resolver reads it. rawget, because the
        -- flat's defaults template CARRIES an `auras` table and plain
        -- indexing would hand back a shared default to write into.
        --
        -- The `flat` argument is honored here for the same reason as
        -- above: a refresh chain asking about the ACTIVE flat must get the
        -- active flat's sub-category, not the group's.
        GetAurasSubcatProfile = function(_, subcat, flat)
            local bf = RealBF()
            if flat ~= nil and flat ~= scope:Flat() then
                return bf:GetAurasSubcatProfile(subcat, flat)
            end
            local own = scope:ReadAuras(subcat)
            if own ~= nil then return own end
            local gp = bf and bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.auras
            return gp and gp[subcat] or nil
        end,
        -- These three take a flat as their first real argument, so
        -- forwarding is simply "the one asked about, or ours when none was".
        GetOrCreateAurasSubCategory = function(_, flat, subcat)
            local bf = RealBF()
            return bf and bf:GetOrCreateAurasSubCategory(flat or scope:Flat(), subcat)
        end,
        GetOrCreateAuraTextSubCategory = function(_, flat, subcat)
            local bf = RealBF()
            return bf and bf.GetOrCreateAuraTextSubCategory
                   and bf:GetOrCreateAuraTextSubCategory(flat or scope:Flat(), subcat)
                   or nil
        end,
        InvalidateFlatAuraCache = function(_, flat)
            local bf = RealBF()
            if bf and bf.InvalidateFlatAuraCache then
                return bf:InvalidateFlatAuraCache(flat or scope:Flat())
            end
        end,

        -- The markers the shared files ask for BY NAME. A field cannot be
        -- usefully proxied here -- `_modifyingFlat` is an ID the consumer
        -- then looks up in rpDB's flatLayouts, where a custom frame group's
        -- ID does not appear -- so the three files that read it as a field
        -- ask these instead. See Pages_AuraShared.lua, Pages_AuraContainers
        -- .lua and Pages_Frames.lua.
        BFOScopeFlat   = function() return scope:Flat() end,
        BFOScopeFlatID = function() return scope:FlatID() end,
        BFOSectionName = function() return scope.tracker end,
    }
    return setmetatable({}, {
        __index = function(_, k)
            local o = OVER[k]
            if o ~= nil then return o end
            return _G.BuzzardFrames[k]
        end,
        -- Writes FORWARD to the real addon, minus the deny-list.
        --
        -- The proxy table is empty, so an empty __newindex dropped every
        -- `self.x = v` inside a BuzzardFrames method reached through it
        -- while the matching READ fell through to the real addon -- which
        -- is not a lost write, it is a broken invariant. UpdateGroupLabels
        -- (Core_Refresh.lua) assigns `self._groupLabelFrames = {}` and then
        -- indexes it: with the store swallowed the next line indexes nil
        -- and throws. InvalidateRaidProfileCache, GetRaidProfile and
        -- SetResolvedProfile all keep their caches on `self` the same way,
        -- as do the page files' own debounce timers
        -- (Pages_Frames.lua `bf._framesResizeTimer`), which under a
        -- swallowing handler cancel the Raid/Party page's pending pass and
        -- then schedule an uncancellable one per slider notch.
        __newindex = function(_, k, v)
            if NEVER_WRITE[k] then return end
            _G.BuzzardFrames[k] = v
        end,
    })
end

-- ── The scope object ───────────────────────────────────────────
--
-- One per section definition -- they differ only in which section table
-- they materialise, which override flag they read and what they stamp as
-- the current section -- and they all share the one panel-wide selection.
local function CFGScope(def)
    local s = { def = def, tracker = def.tracker }

    function s:Groups() return Groups() end
    function s:Index()  return BuzzardFramesOptions:CFGSelectedIndex() end
    function s:Group()  return BuzzardFramesOptions:CFGSelectedGroup() end

    function s:Flat()
        local g = self:Group()
        return g and g.flat or nil
    end

    function s:FlatID()
        local bf = RealBF()
        local i  = self:Index()
        return (i and bf and bf.GetCFGFlatID) and bf:GetCFGFlatID(i) or nil
    end

    -- A section with no override flag -- Frames - Size & Position, which
    -- the Ace panel never gated -- is always "overridden": its settings
    -- are the group's own and there is nothing to inherit.
    --
    -- The MASTER, and only the master: the per-subtab flags underneath it
    -- are asked through IsSubtabOwn.
    function s:Override()
        if not def.flag then return self:Group() ~= nil end
        local g = self:Group()
        return (g and g[def.flag]) == true
    end

    -- Whether `section` (any section, not only this scope's own) reads
    -- from the group's copy: the engine's answer for a section with an
    -- override flag, `true` for everything else, false with no group.
    function s:IsSectionOwn(section)
        local g = self:Group()
        if not g then return false end
        local bf = RealBF()
        local flag = bf and bf.CFG_SECTION_TO_FLAG and bf.CFG_SECTION_TO_FLAG[section]
        if flag and bf.IsCFGSectionOverride then
            return bf:IsCFGSectionOverride(g, section)
        end
        return true
    end

    function s:IsSubtabOwn(section, subtabId)
        local g = self:Group()
        if not g then return false end
        local bf = RealBF()
        local flag = bf and bf.CFG_SECTION_TO_FLAG and bf.CFG_SECTION_TO_FLAG[section]
        if flag and bf.IsCFGSubtabOverride then
            return bf:IsCFGSubtabOverride(g, section, subtabId)
        end
        return true
    end

    -- Materialise the section table and wire its fallback, so an
    -- un-customized key still inherits from the global.
    --
    -- rawget, NOT flat[section]: WireFlatDefaults hangs a profile TEMPLATE
    -- off every flat and that template carries an `auras` table, so plain
    -- indexing answers non-nil for a flat that has never stored one and
    -- the write would land in a per-flat template nothing persists.
    function s:Section(section)
        if not section then return nil end
        local bf   = RealBF()
        local flat = self:Flat()
        if not flat then return nil end
        local t = rawget(flat, section)
        if type(t) ~= "table" then
            t = {}
            -- Cast bars: a freshly materialised custom frame group castBar
            -- section always seeds OFF (owner rule 2026-08-13). There is no
            -- Cast Bars page here, but the rule belongs with the
            -- materialisation rather than with the page that used to reach
            -- it, or restoring the page would silently restore the bug.
            if section == "castBar" then t.enabled = false end
            flat[section] = t
            if bf and bf.WireSectionFallback then
                bf:WireSectionFallback(flat, section)
            end
            if section == "auras" and bf and bf.WireAurasSubCategoryFallbacks then
                bf:WireAurasSubCategoryFallbacks(t)
            end
        end
        return t
    end

    -- The READ path, which must not write.
    --
    -- Section() materialises, and a read that materialises is a page that
    -- persists `flat.auraText = {}` into SavedVariables merely by being
    -- BUILT -- which the Aura Text page is, at build time, by IsGlobalMode,
    -- and which the search index does for every route on the first
    -- keystroke. The Ace proxy materialised on read too, so this is not a
    -- regression, but it contradicts the rule the override toggle exists to
    -- state: nothing is written into the group's flat while the override is
    -- off.
    --
    -- So: the group's own table when it has one; otherwise, with the
    -- override ON, materialise (the page is live and about to be written
    -- to); with it OFF, hand back the GLOBAL -- which is what the group
    -- actually renders from in that state, so the page shows the truth
    -- rather than an empty table.
    --
    -- 2026-09-13: a section WITH an override flag is answered by the engine
    -- (BF:GetCFGSectionProfile), the same table the group's frames read:
    -- master off -> the active Layout's resolution (which is what the panel
    -- used to get wrong -- it handed back the global while the runtime read
    -- the active Layout); master on -> the raw table for a master-only
    -- section, and for a split section the merged view -- ON subtabs from
    -- the group's copy, OFF ones from the active Layout. The split pages
    -- read through that view and write through WriteSectionKey /
    -- SectionKeyTable (the proxy overrides above), never through the view.
    -- The materialise-on-read for a live page is kept, so the group's copy
    -- exists before the first write lands.
    --
    -- A section without a flag (sorting, read cross-section by the Text
    -- page) keeps the old answer: the group's own table when it has one,
    -- else the global.
    function s:ReadSection(section)
        if not section then return nil end
        local g = self:Group()
        local flat = g and g.flat
        if not flat then return nil end
        local bf = RealBF()
        local flag = bf and bf.CFG_SECTION_TO_FLAG and bf.CFG_SECTION_TO_FLAG[section]
        if flag and bf.GetCFGSectionProfile then
            if g[flag] and type(rawget(flat, section)) ~= "table" then
                self:Section(section)
            end
            return bf:GetCFGSectionProfile(section, g, flat)
        end
        local t = rawget(flat, section)
        if type(t) == "table" then return t end
        if self:Override() then return self:Section(section) end
        local gp = bf and bf.rpDB and bf.rpDB.profile
        return gp and gp[section] or nil
    end

    -- The same rule one level down, for the aura sub-categories. rawget,
    -- because the flat's defaults template CARRIES an `auras` table and
    -- plain indexing would hand back a shared default to write into.
    function s:ReadAuras(subcat)
        local flat = self:Flat()
        local a    = flat and rawget(flat, "auras")
        return a and a[subcat] or nil
    end

    s.proxy = MakeProxy(s)
    return s
end

-- ── The sections ───────────────────────────────────────────────
--
-- Ace tree order, from SECTION_DEFS (Options_CustomFrameSections.lua:39-108)
-- and Options_CustomFrameAuras.lua. `tracker` is the value the Ace
-- _sectionTracker description widget wrote into BF._currentSection, which
-- is what tells the dummy-aura preview which context it is drawing for.
--
-- Cast Bars is DELIBERATELY ABSENT (owner decision 2026-08-13). The data
-- layer keeps overrideCastBar and still seeds castBar.enabled = false on a
-- new group, so any dormant data stays inert -- there is simply no UI to
-- turn the override on.
local SECTION_DEFS = {
    { key = "framesSizePos", name = "Frames - Size & Position",
      tracker = "customFrameFramesSizePos" },
    { key = "aurasBuffs",   name = "Buffs",   section = "auras",
      flag = "overrideAurasBuffs",   tracker = "customFrameAuras", auras = true },
    { key = "aurasDebuffs", name = "Debuffs", section = "auras",
      flag = "overrideAurasDebuffs", tracker = "customFrameAuras", auras = true },
    { key = "auraText",    name = "Aura Cooldown Text",       section = "auraText",
      flag = "overrideAuraText",    tracker = "customFrameAuraText" },
    { key = "text",        name = "Text",                     section = "text",
      flag = "overrideText",        tracker = "customFrameText" },
    { key = "healthPower", name = "Health & Power Bars",      section = "healthPower",
      flag = "overrideHealthPower", tracker = "customFrameHealthPower" },
    { key = "borders",     name = "Borders & Highlights",     section = "borders",
      flag = "overrideBorders",     tracker = "customFrameBorders" },
    { key = "absorbs",     name = "Absorbs & Heal Prediction", section = "absorbs",
      flag = "overrideAbsorbs",     tracker = "customFrameAbsorbs" },
    { key = "icons",       name = "Icons",                    section = "icons",
      flag = "overrideIcons",       tracker = "customFrameIcons" },
    { key = "tooltips",    name = "Tooltips",                 section = "tooltips",
      flag = "overrideTooltips",    tracker = "customFrameTooltips" },
}

-- Published as a key -> tracker map. The route builder below stamps each
-- section node's `sectionKey` straight from SECTION_DEFS, so nothing in
-- the addon reads this any more; it is kept because it is the one written
-- statement of which Ace tracker string belongs to which section, and a
-- reader chasing "customFrameAuraText" should find it in one place.
BuzzardFramesOptions.CFG_SECTION_TRACKERS = {}
for _, d in ipairs(SECTION_DEFS) do
    BuzzardFramesOptions.CFG_SECTION_TRACKERS[d.key] = d.tracker
end

-- One scope per section, memoised: the proxy is a metatable and there is
-- no reason to mint a new one per page build.
local scopes = {}
local function ScopeFor(def)
    local s = scopes[def.key]
    if not s then
        s = CFGScope(def)
        scopes[def.key] = s
    end
    return s
end

local function DefByKey(key)
    for _, d in ipairs(SECTION_DEFS) do
        if d.key == key then return d end
    end
    return nil
end

-- The scope for a section key ("aurasBuffs", "text", ...), for the page
-- files' route observers: an observer fires on ENTRY, outside any page
-- build or render, so nothing has bound a scope for it -- and the aura
-- pages' entry stamps (which sub-category is on screen, which section the
-- dummy-aura preview draws for) have to run under the group's scope to
-- say "customFrameAuras" rather than "auras". nil for an unknown key.
function BuzzardFramesOptions:CFGScopeFor(key)
    local def = DefByKey(key)
    return def and ScopeFor(def) or nil
end

-- ── The chrome ─────────────────────────────────────────────────
--
-- What the Ace page put at the top of every Custom Frame Groups section
-- (Options_CustomFrameSections.lua:307-386,
-- Options_CustomFrameAuras.lua:495-586): the group selector and the
-- override toggle -- which is ALWAYS visible once a group exists (v65
-- §6.3), because the flag is authoritative and the choice therefore
-- exists in every state.
--
-- IN THE PAGE HEADER, not on the page. The two controls govern the whole
-- section -- which group is being edited, and whether its own settings
-- are -- so they belong above the tab strip, on every subtab, the way the
-- Ace dialog drew a section-level setting at its root and the way the
-- aura pages already put Aura Preview there. As the first card of every
-- subtab they were the same strip eight times over, and the override
-- switch lived BELOW the tabs it governed.
--
-- While the override is off the section has nothing to edit, so the page
-- is the two controls plus one line saying so (CFGChromeCard), and the
-- tab strip is not drawn at all -- the library's `suppressNavigators`
-- rule, which is the route-tree equivalent of the Ace dialog hiding
-- every child group and thereby zeroing hasChildGroups.

-- A page rebuild on the next frame. Both chrome controls are STRUCTURAL:
-- the group dropdown changes which group's master the page is built
-- against, and the master decides whether there is a page at all.
-- RefreshPage re-reads live fields on the page table it already has and
-- never re-runs the builder; only Invalidate clears the page cache and
-- re-settles the header. Deferred a frame, as the Raid/Party scope strip
-- defers its own (Pages_AuraShared.lua RebuildSoon), so the rebuild never
-- runs inside the click that asked for it.
local function RebuildSoon(app)
    if not app then return end
    if C_Timer then
        C_Timer.After(0, function() app:Invalidate() end)
    else
        app:Invalidate()
    end
end

-- The header row: group selector, then the override switch.
local function CFGHeaderRows(scope, def)
    local row = {}

    -- Group selector. NO `id` and NO `default`: this is session state, not
    -- a setting, and the right-click menu would otherwise offer an undo
    -- entry for "which group am I looking at".
    row[#row + 1] = {
        control = "dropdown", label = "Custom Frame Group",
        width = 170, disabled = "combat",
        desc = "Select which custom frame group to configure.",
        hidden = function() return #Groups() == 0 end,
        -- A FUNCTION, resolved on every read: the list changes while the
        -- panel is open.
        options = function()
            local out = {}
            local bf  = RealBF()
            for i, g in ipairs(Groups()) do
                out[i] = {
                    value = (bf and bf.GetCFGFlatID and bf:GetCFGFlatID(i)) or i,
                    text  = g.name or ("Group " .. i),
                }
            end
            return out
        end,
        get = function() return scope:FlatID() end,
        set = function(_, ctx, v)
            BuzzardFramesOptions:CFGSelectByFlatID(v)
            -- The selection is panel-wide, so every other section page
            -- picks it up on its own next build; this one is rebuilt now,
            -- because the new group's master may not be the old one's.
            RebuildSoon(ctx and ctx.app)
        end,
    }

    if def.flag then
        -- "Override for this group", not the full Ace sentence: the
        -- section's name is already in the breadcrumb directly above, and
        -- the sentence overflowed the row at the default width.
        row[#row + 1] = {
            control = "switch", labelSide = "after",
            label = "Override for this group",
            id = "override_" .. def.key, default = false,
            desc = "When enabled, this custom frame group uses its own "
                .. def.name .. " settings instead of the active Layout's.",
            disabled = "combat",
            hidden = function() return #Groups() == 0 end,
            get = function() return scope:Override() end,
            set = function(_, ctx, v)
                if InCombatLockdown() then return end
                local g = scope:Group()
                if not (g and g.flat) then return end
                local bf = RealBF()
                if bf and bf.SetCFGSectionOverride then
                    -- The engine flips the flag, materialises the group's
                    -- copy on the way ON and -- for a split section --
                    -- seeds every subtab that is on from what the group
                    -- was rendering with, so the flip changes nothing on
                    -- screen. It invalidates the section views; the
                    -- refresh chain below repaints the frames.
                    bf:SetCFGSectionOverride(g, def.section, v)
                else
                    g[def.flag] = v
                    if v then scope:Section(def.section) end
                end
                if def.auras then RefreshCustomFrameAuras()
                else               RefreshCFGAfterSettingChange() end
                RebuildSoon(ctx and ctx.app)
            end,
        }
    end

    return { row }
end

-- The page's one card while there is nothing to edit: no group yet, or
-- the override off. The controls that change either are in the header.
local function CFGChromeCard(scope, def)
    return {
        preset = "strip",
        reorderable = false,
        fields = {
            {
                control = "note", wide = true,
                text = "No custom frame groups yet. Add one using the button above.",
                hidden = function() return #Groups() > 0 end,
            },
            {
                control = "note", wide = true,
                text = "This group uses the active Layout's " .. def.name
                    .. " settings. Turn on the override above to give it "
                    .. "its own.",
                hidden = function() return #Groups() == 0 end,
            },
        },
    }
end

-- Whether the section has anything to show beyond its chrome.
local function CFGHasSettings(scope, def)
    if #Groups() == 0 then return false end
    if not def.flag then return true end
    return scope:Override()
end

-- The toggle key a (section, subtab) pair generates, or nil when the
-- section does not split -- BF.SECTION_SUBTAB_TOGGLE, the one authority.
local function SubtabToggleKey(section, subtabId)
    local bf = RealBF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and section
               and bf.SECTION_SUBTAB_TOGGLE[section]
    return m and subtabId and m[subtabId] or nil
end

-- ── The per-subtab strip ───────────────────────────────────────
--
-- What stands where the Raid/Party per-Layout strip stood, on a split
-- section's subtab: the same card asking the same question of the other
-- scope. The Raid/Party strip asks "does this subtab have its own copy
-- per Layout?"; this one asks "does this subtab have its own copy for
-- this group?". Absent = on, so a group that has never touched these
-- reads exactly as it did before they existed.
--
-- One card here rather than a branch inside the eight page files: the
-- files declare the Raid/Party strip and mark it `scopeStrip`, the
-- assembler swaps it for this, and neither knows about the other.
local function CFGSubtabStrip(scope, def, subtabId, title)
    local togKey = SubtabToggleKey(def.section, subtabId)
    local label  = title or subtabId
    local function isOn() return scope:IsSubtabOwn(def.section, subtabId) end
    return { preset = "strip", reorderable = false, fields = {
        { control = "switch", labelSide = "after",
          label = "Override " .. label .. " for this group",
          -- The id is the group-scoped toggle key, so an undo on this
          -- switch is recorded against the thing it flips. Absent = on,
          -- so the default is `true`.
          id = "cfg_" .. (togKey or subtabId), default = true,
          -- Ace's sky blue, as on the Raid/Party strip: this switch
          -- configures the CONFIGURATION rather than the addon.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "When enabled, this custom frame group uses its own "
              .. label .. " settings. Turn it off to have " .. label
              .. " follow the active Layout while the rest of "
              .. def.name .. " stays the group's own.",
          disabled = "combat",
          get = isOn,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g  = scope:Group()
              local bf = RealBF()
              if not (g and g.flat and bf and bf.SetCFGSubtabOverride) then return end
              -- On the way ON the engine seeds this subtab's keys from
              -- what the group was rendering with, so nothing moves on
              -- screen; it invalidates the section views either way.
              bf:SetCFGSubtabOverride(g, def.section, subtabId, v)
              if def.auras then RefreshCustomFrameAuras()
              else               RefreshCFGAfterSettingChange() end
              -- Every card below is gated on this answer, and their
              -- predicates are functions the library re-asks on a
              -- refresh -- the same repaint the Raid/Party strip asks for.
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
        { control = "note", wide = true,
          text = label .. " settings follow the active Layout while this "
              .. "is off.",
          hidden = isOn },
    } }
end

-- ── The assembler ──────────────────────────────────────────────
--
-- The `wrapSets` of the new panel (Options_CustomFrameSections.lua:268-408),
-- with the gate moved from field level to CARD level: a hidden group is
-- dropped whole, its fields are never measured, acquired or indexed, and
-- search cannot scroll to something invisible.

-- Callbacks that must run WITH the scope bound. Each re-asserts it for its
-- own duration, which is what makes a debounced effect fired after the
-- reader has navigated away still correct.
local SCOPED_KEYS = {
    "get", "hidden", "disabled", "desc", "tooltip", "options", "text",
    "items", "label", "color", "confirm", "suggest", "onClick", "onRemove",
    -- Both spellings, because the library resolves either as a function
    -- (Page.lua's label pass). Latent today -- no page declares one -- and
    -- listed anyway, since the cost of the omission is a predicate that
    -- silently answers for the wrong group.
    "labelColor", "labelColor",
}

local function WrapCallbacks(node, scope)
    for i = 1, #SCOPED_KEYS do
        local k = SCOPED_KEYS[i]
        local f = node[k]
        if type(f) == "function" then
            node[k] = function(a, b, c)
                return BuzzardFramesOptions:WithScope(scope, f, a, b, c)
            end
        end
    end
end

-- One field, with its composite sub-binds and its card attachments.
--
-- The CFG refresh is appended to the node's own `onChange` rather than to
-- its `set`, and a bound field that had no onChange gains one. That is not
-- a liberty: most fields on these pages BIND rather than carry a setter --
-- the write goes through the page's db and never touches `set` at all --
-- so appending to `set` alone would refresh nothing for the majority of
-- them. Riding onChange also means the node's own refresh tier applies, so
-- a slider drag coalesces instead of running the full custom-frame pass
-- per notch, which is what the Ace file's debounced dispatcher was for.
local function WrapField(node, scope, cfgRefresh)
    if type(node) ~= "table" then return end

    local set = node.set
    if type(set) == "function" then
        node.set = function(a, b, c)
            return BuzzardFramesOptions:WithScope(scope, set, a, b, c)
        end
    end
    WrapCallbacks(node, scope)

    local onc = node.onChange
    if type(onc) == "function" or node.bind or node.binds or set then
        node.onChange = function(a, b)
            if type(onc) == "function" then
                BuzzardFramesOptions:WithScope(scope, onc, a, b)
            end
            cfgRefresh()
        end
        -- Effects coalesce by refreshKey / bind / id, in per-app state, and
        -- the bind strings are IDENTICAL in both scopes -- so a custom
        -- frame group write would supersede a pending Raid/Party effect on
        -- the same bind. Namespaced, so the two never collide.
        node.refreshKey = "cfg:" .. tostring(node.refreshKey or node.bind
                                             or node.id or node)
    end

    for _, b in pairs(node.binds or {}) do
        if type(b) == "table" then
            local bset = b.set
            if type(bset) == "function" then
                b.set = function(a, c, d)
                    return BuzzardFramesOptions:WithScope(scope, bset, a, c, d)
                end
            end
            WrapCallbacks(b, scope)
        end
    end

    for _, a in ipairs(node.attach or {}) do
        if type(a) == "table" then WrapCallbacks(a, scope) end
    end
end

-- The Aura Preview dropdown is EXEMPT from the override gate (owner). It
-- writes the account-wide db.global.previewMode* keys, which the custom
-- frame groups' own preview frames read too, so it is chrome rather than
-- one of the settings the override governs. Recognized by the field id
-- AuraPreviewField declares, so neither aura page has to mark its own
-- strip and a third caller gets the same answer for free.
local PREVIEW_FIELD_IDS = {
    previewModeBuffs    = true,
    previewModeDebuffs  = true,
    previewModeAuraText = true,
}

local function IsPreviewGroup(g)
    for _, f in ipairs(g.fields or {}) do
        if f.id and PREVIEW_FIELD_IDS[f.id] then return true end
    end
    return false
end

-- The gate, at CARD level. Chained onto whatever predicate the card
-- already carries rather than replacing it.
--
-- `subtabId`, when given, narrows the gate to that subtab's own override:
-- a card on a split section's subtab is hidden while the subtab follows
-- the active Layout, exactly as it is while the whole section does.
local function GateGroup(g, scope, subtabId)
    local was = g.hidden
    g.hidden = function(n, ctx)
        if #Groups() == 0 then return true end
        if not scope:Override() then return true end
        if subtabId and not scope:IsSubtabOwn(scope.def.section, subtabId) then
            return true
        end
        if type(was) == "function" then
            return BuzzardFramesOptions:WithScope(scope, was, n, ctx)
        end
        return was and true or false
    end
end

-- What stands where a dropped Raid/Party strip stood.
--
-- A card that draws nothing -- hidden, so DrawnGroups gives it no frame,
-- no height and no slot -- but that still COUNTS. A page's own reorder map
-- is indexed by card position with the strip at 1 (Pages_Debuffs.lua's
-- Preset/Filter rows: `shifted[i + #groups]`), and onMove is handed
-- original indices. While the chrome card took the strip's slot the
-- numbers lined up by accident; now that the chrome is in the header,
-- this is what keeps them lined up on purpose.
local function StripPlaceholder()
    return { hidden = true, reorderable = false, fields = {},
             bpStripPlaceholder = true }
end

-- `strip` is the card that stands in for a dropped Raid/Party strip on
-- THIS page -- the group-scoped subtab strip on a split section's subtab
-- (CFGAssemble builds it once and hands it down), or nil for the hidden
-- placeholder. `subtabId` narrows every card's gate to that subtab.
local function AssembleGroups(list, scope, cfgRefresh, out, strip, subtabId)
    for _, g in ipairs(list or {}) do
        -- The Raid/Party per-Layout strip. "Per-Layout" means "per
        -- Raid/Party Layout" and a Custom Frame Group is not a Layout: it
        -- is its own scope. The Override switch in the header answers the
        -- section-level question here, and CFGSubtabStrip the per-subtab
        -- one; where there is no per-subtab question a placeholder keeps
        -- the card numbering (see StripPlaceholder).
        if g.scopeStrip then
            if strip then
                out[#out + 1] = strip
                -- Once: a page with two Raid/Party strips (none today)
                -- would otherwise get two of these.
                strip = nil
            else
                out[#out + 1] = StripPlaceholder()
            end
        else
            if not IsPreviewGroup(g) then GateGroup(g, scope, subtabId) end

            -- A card that carries SUBTABS holds its real cards one level
            -- down and declares no fields of its own -- the shape the
            -- buff-container member page uses for its Settings /
            -- Conditions strip. Two things follow, and both were missed by
            -- walking `fields` alone: the library tests `if group.subtabs`
            -- BEFORE it asks a card whether it is hidden, so the gate put
            -- on the wrapper above is never consulted and the gate has to
            -- be on the nested cards; and the nested fields get no scope
            -- wrapper, no appended refresh and no namespaced effect key.
            -- Recursing does all four at once.
            if type(g.subtabs) == "table" then
                for _, tb in ipairs(g.subtabs) do
                    if type(tb) == "table" and type(tb.groups) == "table" then
                        tb.groups = AssembleGroups(tb.groups, scope, cfgRefresh, {},
                                                   nil, subtabId)
                    end
                end
            end

            if g.toggle then
                WrapField(g.toggle, scope, cfgRefresh)
                -- A gated card's switch is flipped by the library's own
                -- header handler, which calls `gate.set` and re-renders --
                -- it never runs ns.Commit, so it never fires the node's
                -- onChange and the refresh WrapField appended there is
                -- dead. The setter itself is therefore where the custom
                -- frame refresh has to go for a toggle.
                local ts = g.toggle.set
                if type(ts) == "function" then
                    g.toggle.set = function(a, b, c)
                        ts(a, b, c)
                        cfgRefresh()
                    end
                end
            end

            for _, f in ipairs(g.fields or {}) do
                WrapField(f, scope, cfgRefresh)
            end
            for _, a in ipairs(g.attach or {}) do
                if type(a) == "table" then WrapCallbacks(a, scope) end
            end
            out[#out + 1] = g
        end
    end
    return out
end

-- A tree group's member splits its page across subtabs. Same treatment,
-- without a second copy of the chrome inside the pane.
local function AssembleTabs(page, out, scope, cfgRefresh)
    if type(page.tabs) ~= "table" then return end
    local tabs = {}
    for id, t in pairs(page.tabs) do
        if type(t) == "table" then
            local nt = {}
            for k, v in pairs(t) do nt[k] = v end
            nt.groups = AssembleGroups(t.groups, scope, cfgRefresh, {})
            tabs[id] = nt
        end
    end
    out.tabs = tabs
end

-- One built page, re-assembled under a scope. `chrome` is false for a
-- collection MEMBER page: a member's cards are drawn in a tree pane
-- alongside the list, and the chrome belongs to the page that hosts them.
--
-- `subtabId` / `subtabTitle` name the subtab this page IS, when it is one
-- of a split section's: the assembler then puts the group-scoped subtab
-- strip where the Raid/Party strip was and gates every card on that
-- subtab's own override. A page of a section that does not split, or a
-- member page, passes neither and gets the section-level gate alone.
function BuzzardFramesOptions:CFGAssemble(scope, def, page, chrome, subtabId, subtabTitle)
    local cfgRefresh = def.auras and RefreshCustomFrameAuras
                       or RefreshCFGAfterSettingChange
    local strip
    if chrome and subtabId and def.section
       and SubtabToggleKey(def.section, subtabId) then
        strip = CFGSubtabStrip(scope, def, subtabId, subtabTitle)
    end
    -- The gate narrows to the subtab only where the subtab has an
    -- override of its own to be gated on.
    local gateSubtab = strip and subtabId or nil

    local db = page.db
    local scopedDb = function() SetScope(scope); return db and db() end

    if chrome then
        -- The section's chrome, then whatever the page itself put in the
        -- header -- the aura pages' Aura Preview -- as the next row. That
        -- one is exempt from the override gate (owner): it writes the
        -- account-wide preview keys the group's own preview frames read.
        local rows = CFGHeaderRows(scope, def)
        if page.headerFields ~= nil then
            local more = page.headerFields
            if type(more) == "function" then more = more(page) end
            for _, r in ipairs(type(more) == "table" and more or {}) do
                rows[#rows + 1] = r
            end
        elseif page.headerField ~= nil then
            rows[#rows + 1] = { page.headerField }
        end

        -- Nothing to edit: one card, no tab strip. The settings pages are
        -- not assembled at all, so nothing on them is measured, indexed or
        -- searchable while the override is off -- which is what "off"
        -- means.
        if not CFGHasSettings(scope, def) then
            return {
                db = scopedDb,
                headerFields = rows,
                groups = { CFGChromeCard(scope, def) },
                suppressNavigators = true,
            }
        end

        local out = {}
        for k, v in pairs(page) do out[k] = v end
        out.headerField  = nil
        out.headerFields = rows
        out.groups = AssembleGroups(page.groups, scope, cfgRefresh, {}, strip, gateSubtab)
        out.db = scopedDb
        AssembleTabs(page, out, scope, cfgRefresh)
        return out
    end

    local out = {}
    for k, v in pairs(page) do out[k] = v end
    out.groups = AssembleGroups(page.groups, scope, cfgRefresh, {})
    out.db = scopedDb
    AssembleTabs(page, out, scope, cfgRefresh)
    return out
end

-- ── Binding a page's deferrable callbacks ──────────────────────
--
-- A callback is a closure that reads BF() WHEN IT RUNS, not when it was
-- scheduled, and three of them can outlive the render that built them: an
-- effect the library held pending through combat and flushed on
-- PLAYER_REGEN_ENABLED, a `set` reached through RefreshPage / RefreshGroup
-- (which re-read live fields through a stored ctx WITHOUT calling
-- page.db() again), and a button's onClick.
--
-- So a Raid/Party setting edited in combat, followed by a walk to a Custom
-- Frame Groups page -- whose `db` binds the scope and deliberately does not
-- put it back -- fires that Raid/Party effect with BF() answering for the
-- group. The CFG direction is already covered (WrapField binds all three);
-- this is the same treatment for the RP one, with no gate, no chrome and
-- no refresh.
local RP_DEFERRABLE = { "set", "onChange", "onClick" }

local function BindNodeCallbacks(node, scope)
    if type(node) ~= "table" then return end
    for i = 1, #RP_DEFERRABLE do
        local k = RP_DEFERRABLE[i]
        local f = node[k]
        if type(f) == "function" then
            node[k] = function(a, b, c)
                return BuzzardFramesOptions:WithScope(scope, f, a, b, c)
            end
        end
    end
    for _, b in pairs(node.binds or {}) do
        if type(b) == "table" then BindNodeCallbacks(b, scope) end
    end
    for _, a in ipairs(node.attach or {}) do
        if type(a) == "table" then BindNodeCallbacks(a, scope) end
    end
end

local function BindPageCallbacks(page, scope)
    if type(page) ~= "table" then return end
    local function doGroups(list)
        for _, g in ipairs(list or {}) do
            if type(g) == "table" then
                if g.toggle then BindNodeCallbacks(g.toggle, scope) end
                for _, f in ipairs(g.fields or {}) do
                    BindNodeCallbacks(f, scope)
                end
                for _, a in ipairs(g.attach or {}) do
                    if type(a) == "table" then BindNodeCallbacks(a, scope) end
                end
                -- A subtabs card holds its real cards one level down.
                if type(g.subtabs) == "table" then
                    for _, tb in ipairs(g.subtabs) do
                        if type(tb) == "table" and type(tb.groups) == "table" then
                            doGroups(tb.groups)
                        end
                    end
                end
            end
        end
    end
    doGroups(page.groups)
    for _, t in pairs(page.tabs or {}) do
        if type(t) == "table" then doGroups(t.groups or t) end
    end
end

-- ── Binding a route's page ─────────────────────────────────────
--
-- The assignment inside `db` is deliberately not save/restore: the render
-- that follows must run with the scope bound, and the next page to render
-- sets it again from its own db. Raid/Party pages go through the same
-- helper with a nil scope, so a stale binding can never leak the other way
-- either -- which matters because the search index builds every route's
-- page in one sweep.
function BuzzardFramesOptions:ScopedPage(scope, build)
    return function(node)
        local page = self:WithScope(scope, build, node) or { groups = {} }
        if not page.bpScopeDb then
            page.bpScopeDb = true
            BindPageCallbacks(page, scope)
            local db = page.db
            page.db = function() SetScope(scope); return db and db() end
        end
        return page
    end
end

function BuzzardFramesOptions:CFGSectionPage(def, build, noChrome, subtabId, subtabTitle)
    local scope = ScopeFor(def)
    return function(node)
        local page = self:WithScope(scope, build, node) or { groups = {} }
        return self:CFGAssemble(scope, def, page, not noChrome, subtabId, subtabTitle)
    end
end

-- A collection's member template: the same call shape as a page builder,
-- but it takes the library's member context and its result is drawn inside
-- the host page rather than as a page of its own.
local function ScopedTemplate(scope, def, tmpl)
    return function(ctx)
        local page = BuzzardFramesOptions:WithScope(scope, tmpl, ctx)
        if type(page) ~= "table" then return page end
        if def then
            return BuzzardFramesOptions:CFGAssemble(scope, def, page, false)
        end
        if not page.bpScopeDb then
            page.bpScopeDb = true
            BindPageCallbacks(page, scope)
            local db = page.db
            page.db = function() SetScope(scope); return db and db() end
        end
        return page
    end
end

-- Walk a route subtree and bind every page and every collection template
-- it carries. `def` nil = Raid/Party (bind to no scope, add no chrome and
-- no gate); `def` set = that section's custom frame group scope.
--
-- The mark is what lets Panel.lua run this over the WHOLE tree without
-- re-binding the Custom Frame Groups branch it has already bound.
local function BindNode(node, def)
    if type(node) ~= "table" or node.bpScopeBound then return end
    node.bpScopeBound = true

    local scope = def and ScopeFor(def) or nil

    if type(node.page) == "function" then
        node.page = def and BuzzardFramesOptions:CFGSectionPage(def, node.page)
                        or  BuzzardFramesOptions:ScopedPage(nil, node.page)
    end
    if type(node.template) == "function" then
        node.template = ScopedTemplate(scope, def, node.template)
    end
    if type(node.templates) == "table" then
        for k, t in pairs(node.templates) do
            if type(t) == "function" then
                node.templates[k] = ScopedTemplate(scope, def, t)
            end
        end
    end
    for _, child in ipairs(node.children or {}) do BindNode(child, def) end
end

-- Raid/Party: every page closure and every member template in the tree,
-- bound to no scope.
function BuzzardFramesOptions:BindRPRoutes(nodes)
    for _, node in ipairs(nodes or {}) do BindNode(node, nil) end
    return nodes
end

-- ── The route tree ─────────────────────────────────────────────
--
-- The children mirror the Raid/Party nodes shape for shape -- same
-- navigators, same subtab lists, same aura splices -- because they are the
-- same builders. Only the binding differs.

local function SectionNode(BFO, key, title, list, method)
    local def = DefByKey(key)
    local scope = ScopeFor(def)
    local children = {}
    for _, st in ipairs(list or {}) do
        -- `when` decides whether the subtab exists at all (see
        -- SubtabRoutes). Asked UNDER THIS GROUP'S SCOPE: the predicate
        -- reads a setting, and every setting on these pages means the
        -- group's copy of it -- asked outside the scope, Aura Cooldown
        -- Text's tabs would follow the Raid/Party mode rather than the
        -- group's own.
        local keep = true
        if st.when then
            keep = BFO:WithScope(scope, st.when) and true or false
        end
        if keep then
            children[#children + 1] = {
                id = st.id, title = st.title,
                -- The subtab is named to the assembler as well as to the
                -- builder: on a split section it decides which per-subtab
                -- override the page's strip and gate ask about.
                page = BFO:CFGSectionPage(def, function()
                    return BFO[method](BFO, st.id, st.title)
                end, nil, st.id, st.title),
                bpScopeBound = true,
            }
        end
    end
    return { id = key, title = title, navigator = "tabs",
             -- The Ace tracker string for this section, declared on the
             -- node and inherited by every subtab under it: it is what
             -- tells the dummy-aura preview it is drawing for a custom
             -- frame group rather than for the raid.
             sectionKey = def and def.tracker or nil,
             children = children, bpScopeBound = true }
end

function BuzzardFramesOptions:CustomFramesRoutes()
    local bf = RealBF()
    -- The Ace tree hid every Custom Frame Groups child while the master
    -- switch was off (Options_CustomFrameSections.lua:413-415). Routes
    -- carry no `hidden`, so the children are simply not emitted -- the
    -- UnitFramesRoutes shape -- and the switch's own setter rebuilds the
    -- tree. SetRoutes re-points an orphaned route at the first section, so
    -- turning the switch off from a page that is about to vanish lands
    -- somewhere real.
    if bf and bf.cfgDB and bf.cfgDB.profile
       and bf.cfgDB.profile.customFramesEnabled == false then
        return {}
    end

    local out = {}

    -- 1. Custom Frame Groups -- add / remove / rename and the filters.
    --    Nothing to share with Raid/Party, and no section scope: it edits
    --    the GROUP rather than the group's flat.
    if self.CustomFrameGroupsRoute then
        local node = self:CustomFrameGroupsRoute()
        if node then
            BindNode(node, nil)
            out[#out + 1] = node
        end
    end

    -- No group, no section pages. Every page below edits the SELECTED
    -- group's flat, and with nothing to select each of them was a strip
    -- saying so. Absent instead, the UnitFramesRoutes shape: the section is the master
    -- switch and the collection until the first group exists. The Add
    -- button and the Remove X rebuild the tree at that boundary
    -- (Pages_CustomFrames.lua), as the master switch does.
    if #Groups() == 0 then
        return out
    end

    -- 2. Frames - Size & Position. Its own page (the Position card and the
    --    useActiveLayoutSize switch are custom-frame-only), reusing the
    --    Raid/Party Size and Scale cards for the two halves that are the
    --    same keys on the same flat.
    if self.CFGFramesSizePosPage then
        local def = DefByKey("framesSizePos")
        out[#out + 1] = {
            id = "framesSizePos", title = "Frames - Size & Position",
            -- As SectionNode does for the seven sections it builds: the
            -- Ace tracker string, declared where the route is.
            sectionKey = def and def.tracker or nil,
            page = self:CFGSectionPage(def, function()
                return self:CFGFramesSizePosPage()
            end),
            bpScopeBound = true,
        }
    end

    -- 3/4. The two aura sections, with the SAME children the Raid/Party
    --      nodes carry: Buffs, Buff Preset/Filter, Buff List, Big
    --      Defensive and then one route per custom container.
    local buffsDef = DefByKey("aurasBuffs")
    do
        local kids = {}
        local subs = {}
        for i, st in ipairs(self.BUFFS_SUBTABS or {}) do
            subs[i] = {
                id = st.id, title = st.title,
                page = self:CFGSectionPage(buffsDef, function()
                    return self:BuffsPage(st.id, st.title)
                end),
                bpScopeBound = true,
            }
        end
        if subs[1] then kids[#kids + 1] = subs[1] end
        if self.AssignedSpellsPage then
            local n = self:AssignedSpellsPage()
            if n then BindNode(n, buffsDef); kids[#kids + 1] = n end
        end
        if self.SingleBuffsPage then
            local n = self:SingleBuffsPage()
            if n then BindNode(n, buffsDef); kids[#kids + 1] = n end
        end
        if subs[2] then kids[#kids + 1] = subs[2] end
        if self.BuffContainerRoutes then
            for _, n in ipairs(self:BuffContainerRoutes()) do
                BindNode(n, buffsDef)
                kids[#kids + 1] = n
            end
        end
        out[#out + 1] = { id = "aurasBuffs", title = "Buffs",
                          navigator = "tabs", children = kids,
                          sectionKey = buffsDef and buffsDef.tracker or nil,
                          bpScopeBound = true }
    end

    local debuffsDef = DefByKey("aurasDebuffs")
    do
        local kids = {}
        for i, st in ipairs(self.DEBUFFS_SUBTABS or {}) do
            kids[i] = {
                id = st.id, title = st.title,
                page = self:CFGSectionPage(debuffsDef, function()
                    return self:DebuffsPage(st.id, st.title)
                end),
                bpScopeBound = true,
            }
        end
        if self.DebuffContainerRoutes then
            for _, n in ipairs(self:DebuffContainerRoutes()) do
                BindNode(n, debuffsDef)
                kids[#kids + 1] = n
            end
        end
        out[#out + 1] = { id = "aurasDebuffs", title = "Debuffs",
                          navigator = "tabs", children = kids,
                          sectionKey = debuffsDef and debuffsDef.tracker or nil,
                          bpScopeBound = true }
    end

    -- 5-11. The seven section pages, each the Raid/Party builder under its
    --       own scope. Cast Bars is absent by design; Tooltips takes no
    --       subtab argument and is one page rather than a strip.
    out[#out + 1] = SectionNode(self, "auraText", "Aura Cooldown Text",
                                self.AURATEXT_SUBTABS, "AuraTextPage")
    out[#out + 1] = SectionNode(self, "text", "Text",
                                self.TEXT_SUBTABS, "TextPage")
    out[#out + 1] = SectionNode(self, "healthPower", "Health & Power Bars",
                                self.HEALTHPOWER_SUBTABS, "HealthPowerPage")
    out[#out + 1] = SectionNode(self, "borders", "Borders & Highlights",
                                self.BORDERS_SUBTABS, "BordersPage")
    out[#out + 1] = SectionNode(self, "absorbs", "Absorbs & Heal Prediction",
                                self.ABSORBS_SUBTABS, "AbsorbsPage")
    out[#out + 1] = SectionNode(self, "icons", "Icons",
                                self.ICONS_SUBTABS, "IconsPage")
    local tooltipsDef = DefByKey("tooltips")
    out[#out + 1] = {
        id = "tooltips", title = "Tooltips",
        sectionKey = tooltipsDef and tooltipsDef.tracker or nil,
        page = self:CFGSectionPage(tooltipsDef, function()
            return self:TooltipsPage()
        end),
        bpScopeBound = true,
    }

    return out
end
