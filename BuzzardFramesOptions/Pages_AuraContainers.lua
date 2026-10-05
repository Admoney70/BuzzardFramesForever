-- ============================================================
-- BuzzardFramesOptions: Pages_AuraContainers.lua
-- Custom aura CONTAINERS, the Buff List and the Buff Preset/Filter
-- surface, in BuzzardPanel.
--
-- The panel equivalent of the container half of BuzzardFrames'
-- Options/Options_Auras.lua (registerContainerHost, applyContainerSubtabs,
-- applySingleBuffSubtab, applyPresetsSubtab and the "Add Container"
-- pseudo-tab) together with the page those subtabs showed,
-- AuraCustomizations/Options_AuraCustomizations.lua's
-- buildContainerMgmtOptions.
--
-- FOUR THINGS LIVE HERE, and three of them are COLLECTIONS:
--
--   BuffContainersRoute()    a collection node over
--                            BF:GetCustomBuffContainers(), FILTERED to the
--                            entries whose `singleBuff` marker is NOT set.
--   DebuffContainersRoute()  the same over BF:GetCustomDebuffContainers(),
--                            unfiltered -- debuff containers have no
--                            single-buff variant.
--   SingleBuffsPage()        an INLINE collection over the other half of
--                            the buff array: the entries the filter above
--                            excludes.
--   AssignedSpellsPage()     the Buff Preset/Filter page -- the Global
--                            Preset plus the role and spec overrides, a
--                            second inline collection.
--
-- WHY A COLLECTION AND NOT A LIST OF ROUTES. The Ace side hand-rolled the
-- whole of it: a dynamic subtab builder keyed by array index, a create path
-- that fired from a fake tab's RENDER, a remove path with its own confirm
-- and its own re-selection arithmetic, a tab label that changed color by
-- state, and a rebuild hook (BF:RebuildBuffsContainerSubtabs) walking a
-- registry of pages so both surfaces showing the array stayed in step.
-- BuzzardPanel owns every one of those. What is left in this file is what
-- the library says is the addon's: where the data is, what a member is
-- called, and what a create or a delete DOES to the saved variables.
--
-- STORAGE DID NOT MOVE. A container's settings live at the container's own
-- top level, or -- when its own perLayoutConfig flag is on AND the page has
-- a Layout to edit -- in c.groupSettings[<flat id>]. That two-gate model is
-- host.scopeFlat(c) from the Ace side, reproduced here as ContainerScopeKey,
-- and it is the ONE place this file decides where a write lands.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON: BF() is read inside the
-- functions, at the moment the panel is used.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- FORWARD-DECLARED: defined with the Buff List further down, used by the
-- container routes above them (a container's Assigned Spells subtab IS a
-- Buff List view -- the same records, template and tabs -- filtered to the
-- entries anchored to that container). Assigned where they are defined;
-- read only at route-build time, long after this file has loaded.
local SingleBuffCard, AllSingleBuffRecords, BuffListMemberTitle, BuffListMemberTabs

-- The curated buff rows the two "Add Spell Name or ID" fields offer while
-- you type, which is what the Ace input did through its search predictor.
-- BuzzardFrames owns the curated table (SpellSearch\SpellSuggest.lua); this
-- is a thin pass-through so the two surfaces cannot suggest different things.
--
-- Read at CALL time like every other cross-addon call here, and nil-safe on
-- both halves: an older BuzzardFrames without the export simply gives a
-- field with no suggestions, which is the plain text box it was before.
local function SpellSuggestions(text, max)
    local bf = BF()
    local f  = bf and bf.SpellSuggestions
    return f and f(text, max) or nil
end

-- ── Value tables ───────────────────────────────────────────────
--
-- ANCHOR_VALUES / GROW_VALUES from Options_AuraCustomizations.lua.
--
-- A BUFF container's anchor is now the panel's anchor PAD, which has no
-- list to sort -- the nine points are the grid. Only the two lists that
-- carry a tenth, non-positional value survive as dropdowns, and both of
-- those declared grid order with the sentinel last in the Ace file, which
-- is the order kept here.

-- The nine points in GRID order, which is what the two sentinel-bearing
-- lists sort by.
local ANCHOR_GRID = {
    { value = "TOPLEFT",     text = "Top Left" },
    { value = "TOP",         text = "Top" },
    { value = "TOPRIGHT",    text = "Top Right" },
    { value = "LEFT",        text = "Left" },
    { value = "CENTER",      text = "Center" },
    { value = "RIGHT",       text = "Right" },
    { value = "BOTTOMLEFT",  text = "Bottom Left" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local GROW_OPTIONS = {
    { value = "DOWN_LEFT",  text = "Down, then Left" },
    { value = "DOWN_RIGHT", text = "Down, then Right" },
    { value = "LEFT_DOWN",  text = "Left, then Down" },
    { value = "LEFT_UP",    text = "Left, then Up" },
    { value = "RIGHT_DOWN", text = "Right, then Down" },
    { value = "RIGHT_UP",   text = "Right, then Up" },
    { value = "UP_LEFT",    text = "Up, then Left" },
    { value = "UP_RIGHT",   text = "Up, then Right" },
}

-- A debuff container's tenth value. Not an anchor point: it means "render my
-- claimed categories inside the main Debuffs row, at their Debuff Category
-- Priority position".
local function DebuffAnchorOptions()
    local out = {}
    for i = 1, #ANCHOR_GRID do out[i] = ANCHOR_GRID[i] end
    out[#out + 1] = { value = "DEBUFFS", text = "Debuffs" }
    return out
end

-- A single buff's anchor list: the nine points, then the flow hosts. Built
-- per render, because one of the hosts is "every multi-icon buff container"
-- and the user creates those.
local function SingleBuffAnchorOptions()
    local out = {}
    for i = 1, #ANCHOR_GRID do out[i] = ANCHOR_GRID[i] end
    out[#out + 1] = { value = "BUFFS",  text = "Buffs" }
    out[#out + 1] = { value = "BIGDEF", text = "Big Defensive" }
    local bf  = BF()
    local arr = bf and bf:GetCustomBuffContainers()
    for i = 1, #(arr or {}) do
        local c = arr[i]
        -- Single buffs are skipped: they are not hosts (one icon has no flow
        -- to join), which also skips the entry being edited.
        if type(c) == "table" and not c.singleBuff
           and type(c.containerKey) == "string" then
            out[#out + 1] = { value = "C:" .. c.containerKey,
                              text  = c.name or c.containerKey }
        end
    end
    return out
end

local FONT_BORDER_OPTIONS = {
    { value = "",                          text = "None" },
    { value = "OUTLINE",                   text = "Outline" },
    { value = "THICKOUTLINE",              text = "Thick Outline" },
    { value = "MONOCHROME",                text = "Monochrome" },
    { value = "OUTLINE, MONOCHROME",       text = "Outline + Monochrome" },
    { value = "THICKOUTLINE, MONOCHROME",  text = "Thick Outline + Monochrome" },
}

-- SHAPES only. Rounded's two weights are the Thin/Thick strip beside this
-- one -- see Pages_BorderStyle.lua -- rather than a fourth entry here.
local BORDER_STYLE_OPTIONS = {
    { value = "blizzard", text = "Blizzard-Style" },
    { value = "flat",     text = "Square" },
    { value = "rounded",  text = "Rounded" },
}

-- The tab-label colors, as color tables. The Ace builder concatenated
-- escape codes onto the container's own name to produce these, which is
-- exactly what a route's `color` callback exists to avoid: an escape code
-- built by concatenation is one careless write away from reaching stored
-- data. The library paints the SELECTED row itself, so the third Ace case
-- ("force white when this tab is selected, or the color overrides
-- AceConfigDialog's own selected-white") has no counterpart and is dropped.
local CONTAINER_BLUE     = { 0.07, 0.67, 0.91, 1.00 }   -- |cff11ace9
local CONTAINER_BLUE_OFF = { 0.03, 0.34, 0.46, 1.00 }   -- |cff085674

-- ── Reading the arrays ─────────────────────────────────────────

local function Containers(kind)
    local bf = BF()
    if not bf then return {} end
    if kind == "debuff" then return bf:GetCustomDebuffContainers() or {} end
    return bf:GetCustomBuffContainers() or {}
end

-- A container's stable identity. `containerKey` is what the anchor
-- sentinels already use ("C:c_3"), so it is the identity the rest of the
-- addon has already agreed on; a single buff carries singleBuffKey instead.
-- The index is the last resort, and it is the thing a collection key must
-- NOT normally be -- removing member three renumbers the array, and an
-- index-keyed route would then point at the wrong container.
local function ContainerKeyOf(c, index)
    if type(c) ~= "table" then return tostring(index) end
    if type(c.containerKey)  == "string" then return c.containerKey end
    if type(c.singleBuffKey) == "string" then return "sb_" .. c.singleBuffKey end
    return "i" .. tostring(index)
end

-- Resolve a member back to (container, index) by key, fresh on every call:
-- the array index shifts whenever an earlier container is deleted, and a
-- callback can outlive the rebuild that would have re-captured it. Same
-- rule buildSingleBuffEntry's getC() follows.
local function FindByKey(kind, key)
    local arr = Containers(kind)
    for i = 1, #arr do
        if ContainerKeyOf(arr[i], i) == key then return arr[i], i end
    end
    return nil, nil
end

-- ── The scope: two gates, exactly as host.scopeFlat(c) had them ─
--
-- Gate 1 is the PAGE's: which Layout is being edited. On this page that is
-- the aura pages' Modifying Layout, so the answer comes from the shared
-- aura module rather than from a second resolution here.
-- Gate 2 is the CONTAINER's own perLayoutConfig flag.
--
-- nil means "the edit lands on the SHARED container top level", which is
-- what the shared-scope note announces. Called with no container it answers
-- gate 1 alone -- the page-level question the Ace subtab-root callers asked.
local function PageScopeKey()
    local bf = BF()
    -- Reached from a Custom Frame Groups aura page, gate 1 is that group's
    -- own flat identity rather than a Layout -- which is what makes a
    -- container edit made there land in c.groupSettings[cfg_flat_N] instead
    -- of on the shared container top level.
    if bf and bf.BFOScopeFlatID then return bf:BFOScopeFlatID() end
    local fl = BuzzardFramesOptions.AuraFlatLayouts
               and BuzzardFramesOptions.AuraFlatLayouts() or {}
    local mf = bf and bf._modifyingFlat
    if mf and fl[mf] then return mf end
    if fl.flat_party then return "flat_party" end
    for id in pairs(fl) do return id end
    return nil
end

local function ContainerScopeKey(c)
    if type(c) == "table" and c.perLayoutConfig ~= true then return nil end
    return PageScopeKey()
end

-- The table an edit MUTATES: the per-scope copy when the per-Layout tier is
-- active, else the container itself. Materialises the per-scope table on
-- demand, exactly as the Ace getEffectiveSource does -- so it is a WRITE
-- path helper and a `hidden` predicate must never call it. (The Ace file
-- makes the same distinction, and for the same reason.)
local function EffectiveSource(c)
    local key = ContainerScopeKey(c)
    if key then
        if not c.groupSettings then c.groupSettings = {} end
        if not c.groupSettings[key] then c.groupSettings[key] = {} end
        return c.groupSettings[key]
    end
    return c
end

-- The two-tier READ: the per-scope value, falling back to the container top
-- level. Read-only -- it never materialises anything.
local function ScopeField(c, field)
    if type(c) ~= "table" then return nil end
    local key = ContainerScopeKey(c)
    local v
    if key then
        local gs = c.groupSettings and c.groupSettings[key]
        v = gs and gs[field]
    end
    if v == nil then v = c[field] end
    return v
end

-- The anchorPoint this container resolves to in the scope being EDITED.
-- Deliberately not the runtime resolver, which answers for the ACTIVE
-- frame's Layout -- the user can be editing party while standing in a raid.
local function AnchorForScope(c)
    return ScopeField(c, "anchorPoint")
end

-- A single buff's caption for a chip or a dropdown row: the entry's icon
-- and name (the Buff List's own label, without its warning and spec marks
-- -- a chip is a name, not a status line).
local function SingleBuffLabel(bf, sb, i)
    local sid   = bf.GetSingleBuffSpellID and bf:GetSingleBuffSpellID(sb)
    local label = sb.name or (sid and tostring(sid)) or ContainerKeyOf(sb, i)
    local ov = sid and bf.SPELL_DISPLAY_NAME_OVERRIDES
               and bf.SPELL_DISPLAY_NAME_OVERRIDES[sid]
    if ov then
        local apiName = C_Spell and C_Spell.GetSpellName
                        and C_Spell.GetSpellName(sid)
        if label == apiName or label == tostring(sid) then label = ov end
    end
    label = (bf.ClassColorSpellName and bf.ClassColorSpellName(sid, label))
            or label
    local tex = sid and ((bf.CuratedSpellIcon and bf.CuratedSpellIcon(sid))
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)))
    return (tex and ("|T" .. tex .. ":14:14:0:0|t ") or "") .. label, sid
end

local function AuraCache(key)
    local bf = BF()
    return bf and bf.AuraCache and bf.AuraCache[key]
end

-- ── Refresh helpers ────────────────────────────────────────────
--
-- One function per thing the addon has to be told, named for what it tells
-- it. The Ace setters routed through BF:MouseUpOption / the *Debounced
-- refreshers under named keys; the SAME keys are used here, so a mixed
-- burst of edits from either panel still coalesces into one pass.

local function RefreshContainersLight()
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("acCustomContainers", function()
        bf:RefreshAllCustomContainers()
        -- A single buff anchored to Buffs or Big Defensive is painted by the
        -- ROW assemblers, which RefreshAllCustomContainers does not walk.
        if bf.IsPreviewingBuffList and bf:IsPreviewingBuffList()
           and bf.RefreshPreviewDummyAuras then
            bf:RefreshPreviewDummyAuras()
        end
    end)
end

-- The coalesced preview + panel repaint the Ace border/duration setters
-- shared. Same key ("acPanelPreviewNotify"), so a rapid mix of edits is one
-- pass; ctx.app:RefreshPage() replaces NotifyChangeSafe.
local function RefreshPreviewSoon(ctx)
    local bf = BF()
    if not bf then return end
    bf:MouseUpOption("acPanelPreviewNotify", function()
        if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end)
end

local function InvalidateContainerCaches()
    local bf = BF()
    if not bf then return end
    if bf.InvalidateContainerSettingsCache then bf:InvalidateContainerSettingsCache() end
    if bf.InvalidateContainerIconCaches    then bf:InvalidateContainerIconCaches()    end
end

-- The HEAVY path: a change that moves spell claims between a container and
-- the regular row, so the per-frame pool-hide sweep has to run or the old
-- icons sit beside the new ones until something else forces a rebuild.
local function RefreshContainersHeavy()
    local bf = BF()
    if bf then bf:RefreshAllCustomContainersWithRebuild() end
end

-- ── The shared-scope note ──────────────────────────────────────
--
-- ── The per-container scope row ────────────────────────────────
--
-- The Ace widgets containerPerLayout (0.1) and containerPerLayoutCopyTo
-- (0.2), which since 2026-08-25 sit at the TOP of a container page as page
-- chrome -- the same position and the same job the aura subtabs' own scope
-- row has. `preset = "strip"` is the panel's word for that row.

local function CopyTargets(c)
    local bf  = BF()
    local out = {}
    local src = ContainerScopeKey(c)
    if not (bf and src) then return out end
    local fl = BuzzardFramesOptions.AuraFlatLayouts
               and BuzzardFramesOptions.AuraFlatLayouts() or {}
    for id, flat in pairs(fl) do
        if id ~= src then out[#out + 1] = { id = id, name = flat.name or id } end
    end
    for i, g in ipairs(bf:GetCustomFrameGroups() or {}) do
        if g and g.enabled ~= false then
            local id = bf.GetCFGFlatID and bf:GetCFGFlatID(i)
            if id and id ~= src then
                out[#out + 1] = { id = id,
                    name = "Custom Frame Group: " .. (g.name or ("Group " .. i)) }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- NOTHING STORED FOR A LAYOUT IS STILL SOMETHING TO COPY.
--
-- This used to hide the copy control whenever the Layout being edited had
-- no stored table of its own, on the reasoning that an ABSENT
-- groupSettings[src] is not the same as an empty one. It reads as the
-- control vanishing for no stated reason -- and a reader looking at a
-- Layout on its defaults may well want those defaults somewhere else,
-- which is a copy like any other.
--
-- Checked rather than assumed: every reader of a per-scope table takes it
-- per FIELD and falls back to the container's own value
-- (ResolveGroupSource and the fallback chain below it), and the one place
-- that tests the table's mere existence -- ShouldSkipContainerForGroupType
-- -- returns the same answer for an absent table and an empty one, because
-- it goes on to ask `gs.showForGroupType == false` and nil is not false.
-- So an empty table at the destination reads exactly as no table does:
-- the destination falls back to the shared settings, which is precisely
-- what "copy a Layout that stores nothing" means.

local function CopyScopeTo(c, targetID, ctx)
    if InCombatLockdown() then return end
    local bf     = BF()
    local srcKey = c and ContainerScopeKey(c)
    if not (bf and c and srcKey and targetID and targetID ~= srcKey) then return end
    -- An absent source is copied as an EMPTY one rather than refused: the
    -- destination then falls back to the shared settings, which is what the
    -- source is doing. Copy means "make the destination match", and it has
    -- to mean that for a Layout on its defaults too.
    local src = c.groupSettings and c.groupSettings[srcKey] or {}
    if type(src) ~= "table" then return end
    local dst = {}
    for k, v in pairs(src) do
        if type(v) == "table" then dst[k] = bf:DeepCopy(v) else dst[k] = v end
    end
    -- Materialised here rather than assumed: the source no longer has to
    -- exist, so neither does the table it would have lived in.
    if not c.groupSettings then c.groupSettings = {} end
    c.groupSettings[targetID] = dst
    -- The LIGHT path: this writes container per-scope settings only, so
    -- there is no spell reassignment to rebuild for.
    bf:InvalidateClaimedSpellCache()
    bf:RefreshAllCustomContainers()
    if ctx and ctx.app then ctx.app:RefreshPage() end
end

-- `subject` is the noun the two descriptions use: a container page says
-- "container", a single buff's card says "buff". Exactly the relabeling
-- buildSingleBuffEntry applied to the same two widgets.
-- Reached from a Custom Frame Groups aura page? Two of the three fields
-- in the strip below are Layout controls, and a Custom Frame Group is not
-- a Layout: the "Modifying" dropdown would offer a list its own scope key
-- is not in, and a copy made from it would name the wrong source. The
-- per-container "Enable per-Layout Config" toggle stays -- it is the
-- container half of the two-gate model, and the Ace page kept it there
-- too.
local function UnderCFG()
    local bf = BF()
    return (bf and bf.BFOScopeFlatID) ~= nil
end

-- Which SECTION of the route tree this page is rendering in. The container
-- routes are spliced into both the Raid/Party Buffs strip and the Custom
-- Frame Groups one, so every route this file names -- the tree card's list,
-- and the three navigations that follow an add or a remove -- has to name
-- the one the reader is actually in, or an edit made under a custom frame
-- group would land them back on the raid frames.
local function SectionRoot()
    local bf = BF()
    return (bf and bf.BFOScopeFlatID) and "customFrames" or "raidPartyFrames"
end

local function ScopeStrip(getC, subject, kind)
    local function scopeKey() return ContainerScopeKey(getC()) end
    return { preset = "strip", fields = {
        { control = "switch", label = "Enable per-Layout Config",
          labelSide = "after",
          -- Ace's |cff87ceeb sky blue: this switch configures the
          -- CONFIGURATION rather than the addon.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          id = "containerPerLayout", default = false,
          desc = "By default this " .. subject .. "'s settings are shared by "
              .. "every Layout and Custom Frame Group. Enable this to give it "
              .. "a separate copy of its settings per Layout, including whether "
              .. "it appears at all.",
          disabled = "combat",
          hidden = function() return getC() == nil end,
          get = function()
              local c = getC()
              return (c and c.perLayoutConfig == true) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              -- EXPLICIT false, never nil. Reads treat the two identically --
              -- nil just means "never enabled" -- but the explicit false is
              -- what a future seed-only-when-nil pass would need to tell
              -- "turned off" from "never touched".
              c.perLayoutConfig = val and true or false
              -- This flag decides whether a container is skipped for the
              -- current scope, so a buff container's spell claims can move
              -- between it and the regular row.
              bf:InvalidateClaimedSpellCache()
              if kind == "debuff" then
                  bf:RefreshAllCustomContainers()
              else
                  RefreshContainersHeavy()
              end
              ctx.app:RefreshPage()
          end },

        -- WHICH LAYOUT IS BEING EDITED, on the page that edits it.
        --
        -- The scope this strip writes through is the aura pages' Modifying
        -- Layout (see PageScopeKey), and every other section's strip
        -- carries the dropdown that sets it -- so a reader who enabled
        -- per-Layout here had no way to say which Layout they meant
        -- without leaving for another page. The Ace panel could live with
        -- that because its container scope came from the chrome's own
        -- Modifying Layout selector; this panel puts the control where the
        -- setting it qualifies is.
        --
        -- The SAME state as those strips, deliberately: one Modifying
        -- Layout for the whole aura surface, so a buff and the section it
        -- sits in cannot be edited for two different Layouts at once.
        { control = "dropdown", label = "Modifying",
          labelPlacement = "above",
          desc = "Which Layout this " .. subject .. "'s per-Layout settings "
              .. "are edited for. The currently active Layout is shown in "
              .. "green.\n\nShared with the aura subtabs: changing it here "
              .. "changes what they are editing too.",
          disabled = "combat",
          -- Nothing to choose while the settings are shared by every
          -- Layout -- the same gate the copy dropdown beside it uses.
          hidden = function()
              if UnderCFG() then return true end
              local c = getC()
              return not (c and scopeKey())
          end,
          options = function()
              local f = BuzzardFramesOptions.AuraFlatOptions
              return (f and f()) or {}
          end,
          get = function() return PageScopeKey() end,
          set = function(_, ctx, val)
              local bf = BF()
              if not bf then return end
              bf._modifyingFlat = val
              -- The same post-change chain the aura strips run: the scope
              -- decides what every reader on the page resolves to, so the
              -- caches keyed on it go, and the frames drawn from it follow.
              bf:InvalidateRaidProfileCache()
              if bf.UpdateAuraSizeCache     then bf:UpdateAuraSizeCache()     end
              if bf.UpdateSetupFrames       then bf:UpdateSetupFrames()       end
              if bf.UpdateAnchorPosition    then bf:UpdateAnchorPosition()    end
              if bf.RefreshPreviewFrames    then bf:RefreshPreviewFrames()    end
              if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
              -- STRUCTURAL, as on the aura strips: the flat decides which
              -- cards other pages of this section carry, and a memoised
              -- page built for the old flat would be served stale on the
              -- next visit. Deferred a frame so the dropdown row is not
              -- released under the reader's cursor.
              if C_Timer then
                  C_Timer.After(0, function() ctx.app:Invalidate() end)
              else
                  ctx.app:Invalidate()
              end
          end },

        { control = "dropdown", label = "Copy these settings to",
          labelPlacement = "above",
          desc = "Copy this " .. subject .. "'s settings for the Layout you "
              .. "are editing to another Layout or Custom Frame Group. Only "
              .. "this " .. subject .. " is affected.",
          disabled = "combat",
          -- The two reasons a copy is IMPOSSIBLE, in cost order: the
          -- settings are shared by every Layout, so there is no per-Layout
          -- copy to make; or there is nowhere to copy to. "This Layout
          -- stores nothing yet" is not one of them -- see the note above
          -- CopyScopeTo.
          hidden = function()
              -- Hidden under a Custom Frame Group for a second reason
              -- besides the one above: the confirmation dialog runs the
              -- copy AFTER the scope has been unbound, so the source it
              -- resolved would not be the group the reader was looking at.
              if UnderCFG() then return true end
              local c = getC()
              if not (c and scopeKey()) then return true end
              return #CopyTargets(c) == 0
          end,
          options = function()
              local out = {}
              for _, e in ipairs(CopyTargets(getC())) do
                  out[#out + 1] = { value = e.id, text = e.name }
              end
              return out
          end,
          -- A copy is an ACTION, not a setting: no current value.
          get = function() return nil end,
          set = function(_, ctx, val)
              local c = getC()
              if not c then return end
              local name
              for _, e in ipairs(CopyTargets(c)) do
                  if e.id == val then name = e.name end
              end
              ctx.app:Confirm("Copy \"" .. ((c and c.name) or ("this " .. subject))
                  .. "\" settings from \"" .. tostring(scopeKey() or "the current Layout")
                  .. "\" to \"" .. tostring(name or val) .. "\"? This will overwrite "
                  .. "this " .. subject .. "'s settings there.",
                  function() CopyScopeTo(getC(), val, ctx) end)
          end },
    }}
end

-- ── Card-level hide, pushed down onto the fields ───────────────
--
-- The Ace builder hid whole GROUPS -- the Position section, the Border
-- section, the Assigned Spells tab -- with one predicate each, and chained
-- the container's global Enabled gate onto every one of them.
--
-- BuzzardPanel has no group-level `hidden`: Page.Render walks `page.groups`
-- unconditionally, and only a FIELD's predicate is evaluated and watched.
-- So a card's predicate is pushed down onto each of its fields here, which
-- preserves the behavior that matters (the settings go, and the page
-- re-lays out the moment the predicate flips, because the library watches
-- every function predicate it meets). What it does NOT preserve is the
-- card's own chrome: a fully-hidden card still draws its header and an empty
-- body. See the notes -- this is the one place the library is missing
-- something the Ace surface used.
--
-- `group.hidden` is left in place as well, so the day the library honors it
-- the cards disappear properly with no edit here.
local function PushDownGroupHidden(groups)
    for _, g in ipairs(groups or {}) do
        local pred = g.hidden
        if pred ~= nil then
            for _, f in ipairs(g.fields or {}) do
                local own = f.hidden
                f.hidden = function(...)
                    local outer = (type(pred) == "function") and pred(...) or (pred == true)
                    if outer then return true end
                    if type(own) == "function" then return own(...) end
                    return own == true
                end
            end
        end
    end
    return groups
end

-- ── Conditions ─────────────────────────────────────────────────
--
-- BF.BuildContainerConditionsTab, as cards. One builder, because the SAME
-- three container fields (containerCasterScope, loadSpec, loadSpecTypes)
-- back a multi-icon container's Conditions and a single buff's -- only the
-- noun differs, which is what `subject` is for.
--
-- Storage convention, NOT to be inverted: an absent loadSpecTypes table
-- means every spec is ON, and an absent KEY means that spec is ON. Only an
-- explicit `false` is OFF.

-- Densify on first write, mirroring the Ace setters: the first un-tick has
-- to write `true` for every other spec or the un-ticked one is the only
-- entry and the Select/Deselect All label has nothing to reason about. A
-- WRITE-path helper -- a getter must never call it.
local function EnsureSpecTypes(c, specList)
    local t = c.loadSpecTypes
    if type(t) ~= "table" then
        t = {}
        for i = 1, #specList do t[specList[i].id] = true end
        c.loadSpecTypes = t
    end
    return t
end

local function SpecList()
    local bf = BF()
    return (bf and bf.specData) or {}
end

-- Bucket the flat spec list by class token. BF.specData is alphabetical by
-- SPEC NAME and must stay that way for the other spec pickers, so the
-- grouping is built as an index rather than by regrouping the source.
-- Classes run alphabetically by TOKEN; specs keep their alphabetical order
-- inside each class, which falls out of iterating specList in order.
local function SpecsByClass()
    local specList = SpecList()
    local classOrder, byClass = {}, {}
    for i = 1, #specList do
        local s = specList[i]
        -- Fallback bucket, never hit with the shipped table: a spec with no
        -- class token still has to get a row, or it is a spec the user
        -- cannot uncheck while the runtime gate still honors it.
        local cls = s.class or "OTHER"
        if not byClass[cls] then
            byClass[cls] = {}
            classOrder[#classOrder + 1] = cls
        end
        byClass[cls][#byClass[cls] + 1] = s
    end
    table.sort(classOrder)
    return classOrder, byClass
end

local function ClassColored(cls, text)
    -- RAID_CLASS_COLORS.colorStr already carries the alpha byte, hence "|c"
    -- and not "|cff".
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if cc and cc.colorStr then return "|c" .. cc.colorStr .. text .. "|r" end
    return text
end

local function ConditionsRefresh(ctx)
    local bf = BF()
    if not bf then return end
    bf:RefreshContainersWithRebuildDebounced()
    if ctx and ctx.app then ctx.app:RefreshPage() end
end

-- `onChanged` is the caller's TARGETED refresh for a spec toggle: what
-- changed is a value on this page and one row in a list beside it, never
-- the shape of either, so a page refresh is more than the job needs. The
-- Buff List passes one (two cards and one tree row); a caller that passes
-- none refreshes the page, which is what the container pages do.
-- The "Applied By" caster scope. Lives in a single buff's Conditions card
-- only: each buff carries its own Applied By, so the per-container copy
-- (an "Applied By" card on Container Settings) had nothing left to decide
-- and was removed (2026-09-15, owner ruling). The container record's
-- containerCasterScope field is untouched; only the widget is gone.
local function AppliedByField(getC, subject)
    return { control = "dropdown", label = "Applied By",
      desc = "Which caster's copy to show for " .. subject .. "."
          .. "\n\nMe Only: only when YOU applied it.\nNot Me: only when "
          .. "someone ELSE applied it.\nAnyone: whoever applied it.",
      options = { { value = "mine",  text = "Me Only" },
                  { value = "notme", text = "Not Me" },
                  { value = "any",   text = "Anyone" } },
      id = "containerCasterScope", default = "mine",
      disabled = "combat",
      -- Read through BF.GetContainerCasterScope -- the same function
      -- the runtime filter uses, so the widget and the engine cannot
      -- disagree about what a stored value means, and the pre-v64
      -- containerAnyCaster boolean needs no migration.
      get = function()
          local bf = BF()
          return (bf and bf.GetContainerCasterScope
                  and bf.GetContainerCasterScope(getC())) or "mine"
      end,
      set = function(_, ctx, val)
          if InCombatLockdown() then return end
          local c = getC()
          if not c then return end
          -- "mine" is the default and stores nothing, keeping the
          -- sparse convention.
          c.containerCasterScope = (val ~= "mine") and val or nil
          -- Retire the legacy field on first write, or a profile
          -- carries two sources for one setting.
          c.containerAnyCaster = nil
          ConditionsRefresh(ctx)
      end }
end

local function ConditionsCards(getC, subject, onChanged)
    local function refresh(ctx)
        local bf = BF()
        if bf then bf:RefreshContainersWithRebuildDebounced() end
        if onChanged then onChanged(ctx)
        elseif ctx and ctx.app then ctx.app:RefreshPage() end
    end

    local function specOff()
        local c = getC()
        return not (c and c.loadSpec)
    end
    local function specOn() return not specOff() end

    local specFields = {
        -- WHAT THE GRID BELOW ADDS UP TO, at the top of the card the grid
        -- is in. Description text rather than a heading: it reports the
        -- state of the switches under it, which is a remark about them and
        -- not a section of its own. Icons only -- the grid spells the names
        -- out, and this line's job is to be scannable rather than readable.
        -- Same order as the grid, so an icon's position here maps onto a
        -- position there; the tooltip names them, which an icon cannot.
        { control = "note", wide = true,
          desc = function()
              local c = getC()
              local t = c and c.loadSpecTypes
              -- Untouched storage means every spec is on, and naming all
              -- thirty-odd of them is a tooltip nobody reads.
              if type(t) ~= "table" then return "Every specialization." end
              local order, buckets = SpecsByClass()
              local out, n, total = {}, 0, #SpecList()
              for ci = 1, #order do
                  local cls   = order[ci]
                  local cname = (LOCALIZED_CLASS_NAMES_MALE
                                 and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
                  local specs = buckets[cls]
                  for j = 1, #specs do
                      local s = specs[j]
                      if type(t) ~= "table" or t[s.id] ~= false then
                          n = n + 1
                          local ic = s.icon and (s.icon:gsub("\\", "/"))
                          out[#out + 1] = (ic and ("|T" .. ic .. ":14:14:0:0|t ") or "")
                              .. ClassColored(cls, s.name .. " (" .. cname .. ")")
                      end
                  end
              end
              if n == 0 then
                  return "|cffff4444No specs are selected, so " .. subject
                      .. " will never show.|r"
              end
              if n >= total then return "Every specialization." end
              return table.concat(out, "\n")
          end,
          text = function()
              local lead = "|cffffd100Enabled for Specs:|r "
              local c = getC()
              local t = c and c.loadSpecTypes
              -- An absent table means every spec is on, so an untouched
              -- profile reads as All without being densified.
              if type(t) ~= "table" then return lead .. "All" end
              local order, buckets = SpecsByClass()
              local out, n, total = {}, 0, #SpecList()
              for ci = 1, #order do
                  local specs = buckets[order[ci]]
                  for j = 1, #specs do
                      local s = specs[j]
                      if t[s.id] ~= false then
                          n = n + 1
                          local icon = s.icon and (s.icon:gsub("\\", "/"))
                          if icon then out[#out + 1] = "|T" .. icon .. ":18:18:0:0|t" end
                      end
                  end
              end
              -- None FIRST, so an empty spec table can never report "All".
              if n == 0 then
                  return lead .. "|cffff4444None|r |cffaaaaaaNo specs are "
                      .. "selected, so " .. subject .. " will never show. "
                      .. "Tick at least one below, or turn the Spec "
                      .. "condition off above.|r"
              end
              if n >= total then return lead .. "All" end
              return lead .. table.concat(out, " ")
          end },

        { control = "button",
          disabled = "combat",
          -- The read-out above takes the row it is on; the buttons start
          -- the next one.
          newRow = true,
          -- The label IS the state: "Select All" while anything is off.
          label = function()
              local c = getC()
              local t = c and c.loadSpecTypes
              if type(t) ~= "table" then return "Deselect All" end
              local list = SpecList()
              for i = 1, #list do
                  if t[list[i].id] == false then return "Select All" end
              end
              return "Deselect All"
          end,
          onClick = function(_, ctx)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              local list = SpecList()
              local t, allChecked = c.loadSpecTypes, true
              if type(t) == "table" then
                  for i = 1, #list do
                      if t[list[i].id] == false then allChecked = false; break end
                  end
              end
              local target = not allChecked
              t = {}
              for i = 1, #list do t[list[i].id] = target end
              c.loadSpecTypes = t
              refresh(ctx)
          end },
        { control = "button", label = "Select Current Spec",
          desc = "Check only the specialization you are in right now, and "
              .. "uncheck every other.",
          disabled = function()
              return InCombatLockdown()
                  or not (GetSpecialization and GetSpecialization())
          end,
          onClick = function(_, ctx)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              local idx = GetSpecialization and GetSpecialization()
              local cur = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
              if not cur then return end
              -- The same dense write toggleAll makes: only an explicit false
              -- is OFF, so every other spec gets one.
              local list, t = SpecList(), {}
              for i = 1, #list do t[list[i].id] = (list[i].id == cur) end
              c.loadSpecTypes = t
              refresh(ctx)
          end },
    }

    local classOrder, byClass = SpecsByClass()
    for ci = 1, #classOrder do
        local cls   = classOrder[ci]
        local specs = byClass[cls]
        local classIDs = {}
        for j = 1, #specs do classIDs[j] = specs[j].id end
        local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls])
                      or cls

        specFields[#specFields + 1] = {
            control = "switch", label = ClassColored(cls, cname),
            labelSide = "after",
            -- A FIXED COLUMN, as the Ace toggle had (width 0.9 -> 153px):
            -- sized to the class name, not to each class's own name, so
            -- every row's specs start at the same x. Without it the icons
            -- stepped left and right down the page with the name lengths.
            cellWidth = 130,
            -- ONE CLASS PER ROW, as the Ace surface had it: the class
            -- toggle starts the line and its own specs follow it, so a
            -- row of icons always belongs to the name at its left.
            newRow = true,
            desc = "Check or uncheck every " .. cname .. " specialization.",
            disabled = "combat",
            -- Checked only when EVERY spec in the class is on. `== false`
            -- rather than falsy: absent means ON, so a sparse table must not
            -- read as unchecked. No tri-state -- a partly-checked class shows
            -- UNCHECKED, so clicking it turns the whole class ON.
            get = function()
                local c = getC()
                local t = c and c.loadSpecTypes
                if type(t) ~= "table" then return true end
                for k = 1, #classIDs do
                    if t[classIDs[k]] == false then return false end
                end
                return true
            end,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                local t = EnsureSpecTypes(c, SpecList())
                local on = val and true or false
                for k = 1, #classIDs do t[classIDs[k]] = on end
                refresh(ctx)
            end,
        }

        for j = 1, #specs do
            local s    = specs[j]
            local id   = s.id
            local icon = s.icon and (s.icon:gsub("\\", "/")) or nil
            specFields[#specFields + 1] = {
                control = "switch", labelSide = "after",
                -- The spec column: Ace's width 0.3 -> 51px, which is the
                -- switch, its icon and a little air -- two more here for
                -- the 16px icon. Fixed for the same reason the class
                -- column is.
                cellWidth = 54,
                -- Icon only; the name moves into the tooltip. The class is
                -- spelled out because six spec names are shared between
                -- classes and color alone does not separate them.
                -- 16px, a step up from the 14 a tree row uses: this one is
                -- the whole label, and the row is a grid of them.
                label = icon and ("|T" .. icon .. ":16:16:0:0|t")
                    or ClassColored(cls, s.name),
                -- The whole phrase on the title line. Taking the label as
                -- the title put the icon on one line and the name on the
                -- next, which reads as a break in the middle of a name.
                tooltipTitle = (icon and ("|T" .. icon .. ":16:16:0:0|t ") or "")
                    .. s.name .. " (" .. cname .. ")",
                disabled = "combat",
                get = function()
                    local c = getC()
                    local t = c and c.loadSpecTypes
                    return type(t) ~= "table" or t[id] ~= false
                end,
                set = function(_, ctx, val)
                    if InCombatLockdown() then return end
                    local c = getC()
                    if not c then return end
                    EnsureSpecTypes(c, SpecList())[id] = val and true or false
                    refresh(ctx)
                end,
            }
        end
    end

    return {
        { title = "Conditions", preset = "form", fields = {
            AppliedByField(getC, subject),

            -- The caster-scope dropdown above ends its row here: this
            -- switch is a condition of its own and what follows it is that
            -- condition's list, not more fields beside it. A break says
            -- that; the Ace page's width = "full" said it by making a
            -- two-word toggle claim the whole row.
            { control = "linebreak" },
            { control = "switch", label = "Spec", labelSide = "after",
              desc = "Only show " .. subject .. " while your current "
                  .. "specialization is checked below. When off, it shows on "
                  .. "every spec.",
              id = "loadSpec", default = false, disabled = "combat",
              get = function()
                  local c = getC()
                  return (c and c.loadSpec) and true or false
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local c = getC()
                  if not c then return end
                  c.loadSpec = val and true or nil
                  -- The FIRST enable seeds every spec toggle OFF. The storage
                  -- is fail-open, so without this the user starts from
                  -- everything checked and has to un-tick every other spec to
                  -- pin one. First time only: an existing table is left alone.
                  if val and type(c.loadSpecTypes) ~= "table" then
                      local list, t = SpecList(), {}
                      for i = 1, #list do t[list[i].id] = false end
                      c.loadSpecTypes = t
                  end
                  ConditionsRefresh(ctx)
              end },

            { control = "note", wide = true, hidden = specOn,
              text = "|cffaaaaaaWith no condition enabled " .. subject
                  .. " shows on every specialization.|r" },
        }},

        { title = "Specs", preset = "form", hidden = specOff,
          id = "bfSpecs", fields = specFields },
    }
end

-- ── A container's own settings page ────────────────────────────
--
-- buildContainerMgmtOptions, as one page of cards.
--
-- WHAT CHANGED SHAPE, and nothing else did. The Ace builder emitted TWO
-- layouts of the same widget set: "Advanced" (everything flat in one pane,
-- assigned spells as a tree beneath it) and "Basic" (the same widgets
-- partitioned into an Assigned Spells subtab and a Container Settings
-- subtab, with a handful left at the root above the strip). The partition
-- existed because AceConfigDialog gives a pane a scrollbar only when it has
-- no subtabs of its own -- content stranded at the root of a tab-carrying
-- pane cannot be scrolled to. BuzzardPanel scrolls a page whatever is on
-- it, so the partition has no job here and both layouts collapse to ONE
-- page of cards, in the Ace `order` sequence.
--
-- 2026-09-14 (owner ruling): the Basic/Advanced distinction is GONE from
-- this panel. Every buff container is what Basic was -- one Order per
-- assigned buff -- and the Container Type control and the Advanced-only
-- per-buff Display Type dropdown are not built. A `containerType` a
-- profile still stores is ignored here; nothing at runtime reads it.

local function ContainerCards(kind, getC)
    local isDebuff = (kind == "debuff")
    local sectionWord      = isDebuff and "Debuffs" or "Buffs"
    local sizeToggleField  = isDebuff and "containerUsesDebuffSettings"
                                      or  "containerUsesBuffSettings"
    local borderToggleField = isDebuff and "containerUsesDebuffBorder"
                                       or  "containerUsesBuffBorder"
    local durToggleField   = isDebuff and "containerUsesDebuffDurationSettings"
                                      or  "containerUsesBuffDurationSettings"
    local baseSpacingKey    = isDebuff and "debuffSpacing"    or "buffSpacing"
    local baseRowSpacingKey = isDebuff and "debuffRowSpacing" or "buffRowSpacing"
    local basePerRowKey     = isDebuff and "debuffsPerRow"    or "buffsPerRow"
    local baseBorderColorKey = isDebuff and "debuffBorderColor"     or "buffBorderColor"
    local baseBorderThickKey = isDebuff and "debuffBorderThickness" or "buffBorderThickness"

    local function field(name) return ScopeField(getC(), name) end

    -- The generic two-tier get/set every ordinary container setting uses.
    -- Named by the field rather than derived from info[#info], which is the
    -- Ace shape's only difference.
    local function Get(name)
        return function() return field(name) end
    end
    local function Set(name)
        return function(_, _, val)
            if InCombatLockdown() then return end
            local c = getC()
            if not c then return end
            EffectiveSource(c)[name] = val
            -- The WRITE stays immediate; only the container walk coalesces.
            RefreshContainersLight()
        end
    end

    -- Is this container globally OFF? While it is, every widget except the
    -- Enabled toggle and the Container Name field hides -- rename must stay
    -- reachable, and delete is the collection's own X. Never true for a
    -- single buff, whose whitelist/blacklist machinery owns that question.
    local function containerOff()
        local c = getC()
        return (c and not c.singleBuff and c.enabled == false) and true or false
    end
    -- Per-Layout on AND "Enabled for this Layout" off: nothing on this page
    -- can mean anything for the Layout being edited.
    local function groupTypeHidden()
        local c = getC()
        if not c then return false end
        local key = ContainerScopeKey(c)
        if not key then return false end
        local gs = c.groupSettings and c.groupSettings[key]
        return (gs and gs.showForGroupType == false) and true or false
    end
    -- The gate every card below its own header carries: the Ace chainDisabled
    -- pass, expressed once.
    local function offOrHidden()
        return containerOff() or groupTypeHidden()
    end
    local function containerOffOnly() return containerOff() end

    local function growVertical()
        local bf = BF()
        if not bf then return false end
        return bf.GrowDirectionIsVertical(
            bf.NormalizeGrowDirection(field("growDirection"),
                field("anchorPoint") or "BOTTOMRIGHT"))
    end

    -- A debuff container flowing inside the main Debuffs row: everything that
    -- positions it as a BLOCK is the host row's business and hides.
    local function debuffsAnchored()
        return isDebuff and AnchorForScope(getC()) == "DEBUFFS"
    end
    local function blockPositionHidden()
        return offOrHidden() or debuffsAnchored()
    end

    local cards = {}

    -- ── Container ──────────────────────────────────────────────
    cards[#cards + 1] = { title = isDebuff and "Debuff Container" or "Buff Container",
        -- The card the container's remove X hangs on (ContainerRouteList).
        bpContainerCard = true,
        preset = "form", fields = {
        -- Ace: containerEnabled. The master switch, read FIRST.
        { control = "switch", label = "Enabled", labelSide = "after",
          desc = "Master switch for this container. While off, it shows "
              .. "nothing anywhere, releases anything it claimed from the "
              .. "regular rows, and its settings are hidden.",
          id = "containerEnabled", default = true, disabled = "combat",
          hidden = function()
              local c = getC()
              return (not c) or c.singleBuff == true
          end,
          get = function()
              local c = getC()
              return (not c) or c.enabled ~= false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              c.enabled = val and true or false
              bf:InvalidateClaimedSpellCache()
              if isDebuff then
                  -- Light path: the debuff layout recomputes claims, parks or
                  -- revives the groups, all change-guarded.
                  bf:RefreshAllCustomContainers()
              else
                  -- Buff claims move spells between containers and the regular
                  -- row: full rebuild, same as spell reassignment.
                  RefreshContainersHeavy()
              end
              ctx.app:RefreshPage()
          end },

        -- Ace: showForGroupType.
        { control = "switch", label = "Enabled for this Layout",
          labelSide = "after",
          desc = "When disabled, this container will not appear on frames of "
              .. "the selected Layout or Custom Frame Group.",
          id = "showForGroupType", default = true, disabled = "combat",
          hidden = function()
              local c = getC()
              if containerOff() then return true end
              return not (c and ContainerScopeKey(c))
          end,
          get = function()
              local c = getC()
              local key = c and ContainerScopeKey(c)
              if not key then return true end
              local gs = c.groupSettings and c.groupSettings[key]
              return (not gs) or gs.showForGroupType ~= false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              local key = ContainerScopeKey(c)
              if not key then return end
              if not c.groupSettings then c.groupSettings = {} end
              if not c.groupSettings[key] then c.groupSettings[key] = {} end
              c.groupSettings[key].showForGroupType = val
              -- Default showInRegularBuffs to true when hiding the container.
              -- Buff kind only: debuff containers have no assigned spells to
              -- route back, and nothing on the debuff path reads the field.
              if not isDebuff and not val
                 and c.groupSettings[key].showInRegularBuffs == nil then
                  c.groupSettings[key].showInRegularBuffs = true
              end
              bf:InvalidateClaimedSpellCache()
              bf:RefreshAllCustomContainers()
              ctx.app:RefreshPage()
          end },

        -- Ace: containerName.
        { control = "text", label = "Container Name",
          desc = "Rename this container. Clear the field to restore an "
              .. "automatic name.",
          -- The Rename button, live once the text differs from the stored
          -- name -- the same shape the Custom Frame Group's name field has.
          id = "containerName", submit = "Rename", submitOnDirty = true, disabled = "combat",
          hidden = function()
              local c = getC()
              return (not c) or c.singleBuff == true
          end,
          get = function()
              local c = getC()
              return (c and c.name) or ""
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              -- Clearing the box restores an AUTO name, re-derived through the
              -- shared minter so it matches what creation would produce and
              -- cannot collide with a live "Custom <n>".
              if val == "" then
                  local arr = Containers(kind)
                  c.name = (bf.NextCustomContainerName
                            and bf.NextCustomContainerName(arr)) or c.name
                  c.autoNamed = true
              else
                  c.name = val
                  c.autoNamed = nil
              end
              -- REBUILD, not Invalidate, for the same reason the add and
              -- remove paths do it: a container's tab is a DECLARED route
              -- (ContainerRouteList) whose title is the name as a plain
              -- string, and Invalidate re-indexes the declared tree --
              -- recomputing titles only for a COLLECTION's members. So the
              -- rename wrote the new name and the strip went on showing the
              -- old one. The route id is keyed on the container's key rather
              -- than its name, so the rebuild lands on this same tab.
              BuzzardFramesOptions:RebuildRoutes(ctx.app)
              ctx.app:RefreshPage()
          end },

        -- Ace: showInRegularBuffs. Offered only while the container is hidden
        -- for this Layout -- it is what happens to the spells then.
        { control = "switch", width = "full", labelSide = "after",
          label = "Show assigned spells in default buff container",
          desc = "When enabled, spells assigned to this container will appear "
              .. "in the regular buff row for this group type instead of being "
              .. "hidden entirely.",
          id = "showInRegularBuffs", default = false, disabled = "combat",
          hidden = function()
              if isDebuff or containerOff() then return true end
              local c = getC()
              local key = c and ContainerScopeKey(c)
              if not key then return true end
              local gs = c.groupSettings and c.groupSettings[key]
              return (not gs) or gs.showForGroupType ~= false
          end,
          get = function()
              local c = getC()
              local key = c and ContainerScopeKey(c)
              if not key then return false end
              local gs = c.groupSettings and c.groupSettings[key]
              return (gs and gs.showInRegularBuffs == true) or false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              local key = ContainerScopeKey(c)
              if not key then return end
              if not c.groupSettings then c.groupSettings = {} end
              if not c.groupSettings[key] then c.groupSettings[key] = {} end
              c.groupSettings[key].showInRegularBuffs = val
              bf:InvalidateClaimedSpellCache()
              bf:RefreshAllCustomContainers()
              ctx.app:RefreshPage()
          end },
    }}

    -- ── Sort Order / Maximum Duration (debuff containers only) ──
    --
    -- On the main card, after Container Name, rather than a Filtering card
    -- of their own. Stored at the container TOP LEVEL rather than through
    -- the per-Layout pair, because the runtime resolver reads c.sortOrder /
    -- c.maxDuration there -- the same top-level storage presetRelativeSize
    -- uses.
    if isDebuff then
        local function topLevelSelect(fieldName, label, desc, options)
            return { control = "dropdown", label = label,
                desc = desc, options = options,
                id = fieldName, default = "", disabled = "combat",
                hidden = offOrHidden,
                get = function()
                    local c = getC()
                    return (c and c[fieldName]) or ""
                end,
                set = function(_, _, val)
                    if InCombatLockdown() then return end
                    local bf, c = BF(), getC()
                    if not (bf and c) then return end
                    c[fieldName] = (val ~= "" and val) or nil
                    if bf.InvalidateContainerSettingsCache then
                        bf:InvalidateContainerSettingsCache()
                    end
                    RefreshContainersHeavy()
                end }
        end
        local main = cards[1].fields
        main[#main + 1] = topLevelSelect("sortOrder", "Sort Order",
            "Order of icons within each of this container's categories. "
            .. "\"Use Debuffs Setting\" uses the Sort Order chosen on the "
            .. "Debuffs tab.",
            { { value = "",            text = "Use Debuffs Setting" },
              { value = "recentLast",  text = "Application Order (Most Recent Last)" },
              { value = "recentFirst", text = "Application Order (Most Recent First)" },
              { value = "expireSoon",  text = "Expiring Soonest" },
              { value = "expireLast",  text = "Expiring Last" } })
        main[#main + 1] = topLevelSelect("maxDuration", "Maximum Duration",
            "Hide debuffs in this container whose maximum (total) duration "
            .. "exceeds this. Filters on the declared max duration, not "
            .. "remaining time, and also hides permanent debuffs. \"Use "
            .. "Debuffs Setting\" uses the Maximum Duration chosen on the "
            .. "Debuffs tab.",
            { { value = "",      text = "Use Debuffs Setting" },
              { value = "none",  text = "None" },
              { value = "sec30", text = "30 seconds" },
              { value = "min1",  text = "1 minute" },
              { value = "min2",  text = "2 minutes" },
              { value = "min5",  text = "5 minutes" },
              { value = "min10", text = "10 minutes" },
              { value = "min30", text = "30 minutes" },
              { value = "hour1", text = "1 hour" } })
    end

    -- ── Position ───────────────────────────────────────────────

    -- Writing an anchor point also writes that anchor's default grow
    -- direction, and for a flow anchor it changes which display the icons
    -- render in -- a routing change, not a geometry one. Lifted out of the
    -- field so the dropdown and the pad below can share the one writer.
    local function SetAnchorPoint(_, ctx, val)
        if InCombatLockdown() then return end
        local bf, c = BF(), getC()
        if not (bf and c) then return end
        -- Read the OLD value BEFORE overwriting it: a transition OUT of
        -- a flow anchor is as much a routing change as one into it.
        local prevVal = field("anchorPoint")
        local s = EffectiveSource(c)
        s.anchorPoint = val
        local def = bf.GROW_DEFAULT_FOR_ANCHOR
                    and bf.GROW_DEFAULT_FOR_ANCHOR[val]
        if def then s.growDirection = def end
        -- A flow anchor moves icons between this container and a host
        -- row, and that reassignment needs the heavy path's per-frame
        -- pool-hide sweep -- the light path does not hide pools, so the
        -- stale icons would sit beside the new ones. A plain anchor
        -- change is pure geometry, resolved live at Layout.
        if c.singleBuff or bf.IsFlowAnchorValue(val)
           or bf.IsFlowAnchorValue(prevVal) then
            bf:RefreshContainersWithRebuildDebounced()
        else
            bf:RefreshContainersDebounced()
        end
        ctx.app:RefreshPage()
    end

    -- A BUFF container's anchor is the nine points and nothing else, so it
    -- is the panel's anchor pad, with the two offsets folded in beside it.
    --
    -- A DEBUFF container's is not: its list carries a tenth value, Debuffs,
    -- which is not a position at all but "render inside the main Debuffs
    -- row". A 3x3 pad cannot say that, so those keep the dropdown and their
    -- offsets stay separate fields -- which they must anyway, since a
    -- container flowing into Debuffs hides its offsets and keeps its anchor.
    local anchorField
    if isDebuff then
        anchorField = {
          control = "dropdown", label = "Anchor Point",
          id = "anchorPoint", disabled = "combat",
          desc = isDebuff
              and ("Changing the anchor point resets the Grow Direction to that "
                .. "anchor's default.\n\n|cffffd100Debuffs|r renders this "
                .. "container's categories INSIDE the main Debuffs display "
                .. "instead of positioning them separately. Each category flows "
                .. "at its own position in the Debuff Category Priority list, "
                .. "and the icons still use this container's Icon Size, Sort "
                .. "Order, Maximum Duration, Border, Duration text and "
                .. "per-category Relative Size.\n\nPosition, Grow Direction, "
                .. "Icons Per Row and Spacing come from the Debuffs display in "
                .. "that mode.")
              or "Changing the anchor point resets the Grow Direction to that "
                .. "anchor's default.",
          options = DebuffAnchorOptions,
          get = Get("anchorPoint"),
          set = SetAnchorPoint }
    else
        anchorField = {
          control = "anchor", label = "Anchor Point",
          id = "anchorPoint", disabled = "combat",
          desc = "Changing the anchor point resets the Grow Direction to that "
              .. "anchor's default.",
          binds = {
              point = { id = "anchorPoint",
                        get = Get("anchorPoint"), set = SetAnchorPoint },
              x     = { id = "offsetX",
                        get = Get("offsetX"), set = Set("offsetX") },
              y     = { id = "offsetY",
                        get = Get("offsetY"), set = Set("offsetY") },
          },
          min = -60, max = 60, refresh = "mouseup" }
    end

    local positionFields = {
        anchorField,

        -- Ace: dbcDebuffsOffNote. Shown ONLY while this container is anchored
        -- to a Debuffs display the edited Layout has switched off -- the
        -- difference between "nothing renders" and "nothing renders and the
        -- user cannot see why". The cheap anchor test runs first, so the DB
        -- walk is skipped on every non-anchored render.
        { control = "note", wide = true,
          text = "|cffff8080The Debuffs display is switched off in this Layout, "
              .. "so this container will not render here.|r",
          hidden = function()
              local bf = BF()
              if not debuffsAnchored() then return true end
              if not (bf and bf.DebuffContainerDebuffsOffForScope) then return true end
              return not bf.DebuffContainerDebuffsOffForScope(getC(),
                  ContainerScopeKey)
          end },
    }

    -- The offsets, for a DEBUFF container only: the buff pad above already
    -- carries them, and a container flowing into Debuffs hides them while
    -- keeping the anchor that put it there.
    --
    -- Appended rather than written into the constructor with an `and/or`: a
    -- nil in a positional slot of a table constructor leaves a hole, and
    -- ipairs would stop at it -- taking Grow Direction and everything after
    -- it off the page.
    if isDebuff then
        positionFields[#positionFields + 1] =
        { control = "slider", label = "X Offset", min = -60, max = 60, step = 1,
          id = "offsetX", disabled = "combat", hidden = blockPositionHidden,
          get = Get("offsetX"), set = Set("offsetX") }
        positionFields[#positionFields + 1] =
        { control = "slider", label = "Y Offset", min = -60, max = 60, step = 1,
          id = "offsetY", disabled = "combat", hidden = blockPositionHidden,
          get = Get("offsetY"), set = Set("offsetY") }
    end

    for _, f in ipairs({
        { control = "dropdown", label = "Grow Direction",
          desc = "Fill direction, then the direction new rows/columns wrap.",
          options = GROW_OPTIONS, id = "growDirection", disabled = "combat",
          hidden = blockPositionHidden,
          get = function()
              local bf = BF()
              if not bf then return nil end
              -- Legacy single-axis stored values are normalized on read
              -- (anchor-aware) so the dropdown always shows a valid selection.
              return bf.NormalizeGrowDirection(field("growDirection"),
                  field("anchorPoint") or "BOTTOMRIGHT")
          end,
          set = Set("growDirection") },

        -- Per-field inherit: container-own when set, the section's value when
        -- untouched, and the display shows the effective one either way.
        { control = "stepper", min = 1, max = 8, step = 1,
          label = function()
              return growVertical() and "Icons Per Column" or "Icons Per Row"
          end,
          id = "buffsPerRow", disabled = "combat", hidden = blockPositionHidden,
          get = function()
              local v = field("buffsPerRow")
              if v == nil then v = AuraCache(basePerRowKey) or 3 end
              return v
          end,
          set = Set("buffsPerRow") },
    }) do
        positionFields[#positionFields + 1] = f
    end

    cards[#cards + 1] = { title = "Position", preset = "form",
        hidden = offOrHidden, fields = positionFields }

    -- ── Icon Size ──────────────────────────────────────────────
    local function sizeOwn() return field(sizeToggleField) ~= false end
    local function sizeInherited() return offOrHidden() or sizeOwn() end
    local function spacingHidden() return sizeInherited() or debuffsAnchored() end

    local iconSizeFields = {
        -- The stored key means "use the section's settings" (default true), so
        -- presenting it directly removes the double inversion the pre-v61
        -- "Override Buff Icon Size" label carried.
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBUse " .. sectionWord
              .. (isDebuff and " Icon Size" or " Icon Size/Spacing") .. "|r",
          desc = "When enabled, this container inherits Icon Size, "
              .. (isDebuff and "" or "Max Icons, ")
              .. "Icon Spacing and Row Spacing from the active " .. sectionWord
              .. " settings. Disable it to give this container its own. Icons "
              .. "Per Row is always configurable above; leave it untouched to "
              .. "follow the " .. sectionWord .. " settings.",
          id = sizeToggleField, default = true, disabled = "combat",
          get = function()
              -- nil means inherit (the creation default is true).
              return field(sizeToggleField) ~= false
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              EffectiveSource(c)[sizeToggleField] = val and true or false
              bf:RefreshAllCustomContainers()
          end },

        { control = "slider", label = "Icon Size", min = 2, max = 50, step = 1,
          id = "buffSize", disabled = "combat", hidden = sizeInherited,
          desc = isDebuff and function()
              if debuffsAnchored() then
                  return "Size of this container's icons inside the Debuffs "
                      .. "display. Each category's Relative Size multiplies "
                      .. "this, exactly like the Debuffs display's own category "
                      .. "sizes."
              end
              return "Icon size for this container."
          end or nil,
          get = Get("buffSize"), set = Set("buffSize") },
    }

    -- BUFF containers only. A debuff container's cap is set per debuff type
    -- ("Max Debuffs", in each category's card in the Preset/Filter section).
    -- Omitted rather than hidden: a hidden-but-live widget would keep writing
    -- c.maxBuffs, and nothing reads it for debuffs now.
    if not isDebuff then
        iconSizeFields[#iconSizeFields + 1] = {
            control = "stepper", label = "Max Icons", min = 1, max = 8, step = 1,
            id = "maxBuffs", disabled = "combat", hidden = sizeInherited,
            get = Get("maxBuffs"), set = Set("maxBuffs") }
    end

    iconSizeFields[#iconSizeFields + 1] = {
        control = "stepper", label = "Icon Spacing", min = 0, max = 10, step = 1,
        desc = "Gap between icons within a row.",
        id = "spacing", disabled = "combat", hidden = spacingHidden,
        get = function()
            local v = field("spacing")
            if v == nil then v = AuraCache(baseSpacingKey) or 1 end
            return v
        end,
        set = Set("spacing") }
    iconSizeFields[#iconSizeFields + 1] = {
        control = "stepper", min = 0, max = 10, step = 1,
        label = function()
            return growVertical() and "Column Spacing" or "Row Spacing"
        end,
        desc = "Gap between rows/columns.",
        id = "rowSpacing", disabled = "combat", hidden = spacingHidden,
        get = function()
            local v = field("rowSpacing")
            if v == nil then v = AuraCache(baseRowSpacingKey) or 0 end
            return v
        end,
        set = Set("rowSpacing") }

    cards[#cards + 1] = { title = "Icon Size", preset = "form",
        hidden = offOrHidden, fields = iconSizeFields }

    -- ── Border ─────────────────────────────────────────────────
    --
    -- The Border group the aura subtabs carry, against per-container storage.
    local function borderInherits()
        local v = field(borderToggleField)
        return v ~= false
    end
    local function borderOwnHidden() return offOrHidden() or borderInherits() end

    -- What the container currently resolves to, for the widgets' own hidden
    -- predicates: the two-tier source, then the section it inherits from.
    local function borderStyle()
        local v = field("borderStyle")
        if v == nil then
            -- OR the legacy Blizzard-borders flag in, matching AuraBorderStyle
            -- and BorderStyleOf -- otherwise a profile that chose Blizzard
            -- borders before the style key existed would show Square here.
            -- Explicit branch: `isDebuff and X or Y` would fall through to the
            -- buff value when the debuff style is unset.
            local style, blizz
            if isDebuff then
                style, blizz = AuraCache("debuffBorderStyle"), AuraCache("debuffBlizzardBorders")
            else
                style, blizz = AuraCache("buffBorderStyle"), AuraCache("buffBlizzardBorders")
            end
            if style == "blizzard" or blizz then
                v = "blizzard"
            else
                v = style or "flat"
            end
        end
        return v
    end

    -- The border lands in the buttonSpec, stamped at Layout time -- and the
    -- LIGHT refresh does run that Layout, with no cache between the write and
    -- the read, so it applies a border change fully. Debounced so dragging the
    -- color wheel coalesces.
    local function refreshBorder(ctx)
        local bf = BF()
        if bf then bf:RefreshContainersDebounced() end
        RefreshPreviewSoon(ctx)
    end
    local function borderSet(name)
        return function(_, ctx, val)
            if InCombatLockdown() then return end
            local c = getC()
            if not c then return end
            EffectiveSource(c)[name] = val
            refreshBorder(ctx)
        end
    end

    -- Shape and weight, over this container's one `borderStyle` key.
    local containerBorderStyle, containerBorderWeight =
        BuzzardFramesOptions:BorderStyleFields({
            id = "borderStyle", options = BORDER_STYLE_OPTIONS,
            desc = "Blizzard-Style uses Blizzard's aura border art. Square "
                .. "draws the flat colored border. Rounded masks the icon to "
                .. "a rounded rectangle inside a colored frame.",
            hidden = borderOwnHidden,
            get = borderStyle, set = borderSet("borderStyle"),
        })

    local borderFields = {
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBUse " .. sectionWord .. " Border|r",
          desc = "When enabled, this container uses the Border settings from "
              .. "the active " .. sectionWord .. " settings. Disable it to give "
              .. "this container its own border.",
          id = borderToggleField, default = true, disabled = "combat",
          -- Direct polarity: true or ABSENT means inherit. Absent must mean
          -- inherit -- before this group existed a container's border was
          -- always the section's, so any other default changes how existing
          -- containers look.
          get = borderInherits,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              EffectiveSource(c)[borderToggleField] = val and true or false
              refreshBorder(ctx)
          end },

        containerBorderStyle,
        containerBorderWeight,

        -- A stepper, not a slider: six whole numbers, and the reader wants
        -- "one more pixel" rather than a position on a track.
        { control = "stepper", label = "Border Thickness", min = 0, max = 5, step = 1,
          desc = "Border thickness in pixels. 0 removes the border.",
          id = "borderThickness", disabled = "combat",
          -- Thickness only means anything for the flat square border;
          -- Blizzard art carries its own weight, and the rounded frame's is
          -- the Thin/Thick strip under the style.
          hidden = function()
              return borderOwnHidden() or borderStyle() ~= "flat"
          end,
          get = function()
              local v = field("borderThickness")
              if v == nil then v = AuraCache(baseBorderThickKey) or 1 end
              return v
          end,
          set = borderSet("borderThickness") },

        { control = "color", label = "Border Color", alpha = true,
          desc = "Color of this container's icon border (tints the rounded "
              .. "frame in Rounded styles).",
          id = "borderColor", disabled = "combat",
          -- Blizzard's own border art is not tintable.
          hidden = function()
              return borderOwnHidden() or borderStyle() == "blizzard"
          end,
          get = function()
              local col = field("borderColor")
                  or AuraCache(baseBorderColorKey)
                  or { r = 0, g = 0, b = 0, a = 0.8 }
              return { col.r or 0, col.g or 0, col.b or 0, col.a or 1 }
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              EffectiveSource(c).borderColor =
                  { r = val[1], g = val[2], b = val[3], a = val[4] }
              refreshBorder(ctx)
          end },
    }

    -- The two dispel extras FOLLOW the single "Use Debuffs Border" toggle --
    -- the runtime resolvers gate on that same flag -- so they hide exactly
    -- when the other border widgets do.
    if isDebuff then
        local function dispelIconOn()
            local v = field("dispelTypeIcon")
            if v == nil then v = AuraCache("showDebuffDispelTypeIcon") == true end
            return v and true or false
        end
        borderFields[#borderFields + 1] = {
            control = "switch", label = "Color Border by Dispel Type",
            -- Heads its own row, as the same switch does on the Debuffs
            -- page (Pages_Debuffs.lua): the two dispel extras read as a
            -- pair below the color row, not as a tail on it.
            labelSide = "after", newRow = true,
            desc = "Color a dispellable debuff's border by its dispel type, "
                .. "overriding the Border Color. Typeless debuffs keep the "
                .. "Border Color.",
            id = "colorBorderByDispel", disabled = "combat",
            hidden = borderOwnHidden,
            get = function()
                local v = field("colorBorderByDispel")
                if v == nil then v = AuraCache("debuffColorBorderByDispel") ~= false end
                return v and true or false
            end,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                EffectiveSource(c).colorBorderByDispel = val and true or false
                refreshBorder(ctx)
            end }
        borderFields[#borderFields + 1] = {
            control = "switch", label = "Show Dispel Type Icon",
            labelSide = "after",
            desc = "Show the debuff's dispel-type icon in the top-right corner. "
                .. "Only appears on debuffs that have a dispel type.",
            id = "dispelTypeIcon", disabled = "combat",
            hidden = borderOwnHidden,
            get = dispelIconOn,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                EffectiveSource(c).dispelTypeIcon = val and true or false
                refreshBorder(ctx)
            end }
        borderFields[#borderFields + 1] = {
            control = "slider", label = "Dispel Type Icon Size",
            desc = "Size of the dispel-type corner icon, as a percentage of "
                .. "the container's icon.",
            min = 10, max = 100, step = 5,
            id = "dispelTypeIconScale", disabled = "combat",
            hidden = function() return borderOwnHidden() or not dispelIconOn() end,
            get = function()
                local v = field("dispelTypeIconScale")
                if v == nil then v = AuraCache("debuffDispelTypeIconScale") or 40 end
                return v
            end,
            set = borderSet("dispelTypeIconScale") }
    end

    cards[#cards + 1] = { title = "Border", preset = "form",
        hidden = offOrHidden, fields = borderFields }

    -- ── Duration Text ──────────────────────────────────────────
    --
    -- When the inherit toggle is OFF, unset fields still SHOW the section
    -- baseline (an effective read), so an untouched field tracks the section
    -- live rather than reading blank.
    local DUR_BASELINE = isDebuff and {
        showDuration = "showDebuffDuration", autoScale = "debuffAutoScale",
        timerScale = "debuffTimerScale", fontSize = "debuffFontSize",
        durationFont = "debuffDurationFont", durationBorder = "debuffDurationBorder",
        fontColor = "debuffFontColor",
        -- The runtime inherits these from the section when unset, so the
        -- toggles must SHOW that inherited value or a tick-untick writes an
        -- explicit false that silently overrides the section.
        disableSwipe = "disableDebuffSwipe", disableSpark = "disableDebuffSpark",
        reverseSwipe = "reverseDebuffSwipe",
    } or {
        showDuration = "showBuffDuration", autoScale = "buffAutoScale",
        timerScale = "buffTimerScale", fontSize = "buffFontSize",
        durationFont = "buffDurationFont", durationBorder = "buffDurationBorder",
        fontColor = "buffFontColor",
        disableSwipe = "disableBuffSwipe", disableSpark = "disableBuffSpark",
        reverseSwipe = "reverseBuffSwipe",
    }

    local function durBaseline(name)
        local acKey = DUR_BASELINE[name]
        local v = acKey and AuraCache(acKey)
        if v == nil then
            if name == "timerScale"     then return 1.0 end
            if name == "fontSize"       then return 11 end
            if name == "durationBorder" then return "OUTLINE" end
            if name == "showDuration"   then return true end
        end
        return v
    end
    local function durEff(name)
        local v = field(name)
        if v == nil then v = durBaseline(name) end
        return v
    end
    local function durInherits() return field(durToggleField) ~= false end
    local function durOwnHidden() return offOrHidden() or durInherits() end
    local function durShowOff()
        return durOwnHidden() or durEff("showDuration") == false
    end
    local function durRefresh(ctx)
        local bf = BF()
        if bf then bf:RefreshContainersDebounced() end
        RefreshPreviewSoon(ctx)
    end
    local function durSet(name)
        return function(_, ctx, val)
            if InCombatLockdown() then return end
            local c = getC()
            if not c then return end
            EffectiveSource(c)[name] = val
            durRefresh(ctx)
        end
    end
    local function durColorGet(name, dflt)
        return function()
            local col = field(name) or dflt or { r = 1, g = 1, b = 1, a = 1 }
            return { col.r or 1, col.g or 1, col.b or 1, col.a or 1 }
        end
    end
    local function durColorSet(name)
        return function(_, ctx, val)
            if InCombatLockdown() then return end
            local c = getC()
            if not c then return end
            EffectiveSource(c)[name] = { r = val[1], g = val[2], b = val[3], a = val[4] }
            durRefresh(ctx)
        end
    end
    local function thresholdOff() return not field("thresholdColorEnabled") end
    local function threshold2Off()
        return not (field("thresholdColorEnabled") and field("threshold2ColorEnabled"))
    end

    cards[#cards + 1] = { title = "Duration Text", preset = "form",
        hidden = offOrHidden, fields = {
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBUse " .. sectionWord .. " Duration Settings|r",
          desc = "When enabled, this container inherits its duration text "
              .. "(show, font, size, scale, color, swipe/spark and threshold "
              .. "colors) from the active " .. sectionWord .. " settings. "
              .. "Disable it to give this container its own.",
          id = durToggleField, default = true, disabled = "combat",
          get = durInherits,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              EffectiveSource(c)[durToggleField] = val and true or false
              durRefresh(ctx)
          end },

        { control = "switch", label = "Show Duration Numbers", labelSide = "after",
          id = "showDuration", disabled = "combat", hidden = durOwnHidden,
          get = function() return durEff("showDuration") end,
          set = durSet("showDuration") },
        { control = "switch", width = "full", labelSide = "after",
          label = "Hide Duration Text Above 1 Minute",
          id = "hideDurationAbove1Min", default = false,
          disabled = "combat", hidden = durShowOff,
          get = function() return durEff("hideDurationAbove1Min") == true end,
          set = durSet("hideDurationAbove1Min") },
        { control = "switch", label = "Auto Scale Duration Text", labelSide = "after",
          id = "autoScale", disabled = "combat", hidden = durShowOff,
          get = function() return durEff("autoScale") end,
          set = durSet("autoScale") },
        { control = "slider", label = "Duration Text Scale",
          min = 0.1, max = 3.0, step = 0.1,
          id = "timerScale", disabled = "combat",
          hidden = function()
              return durShowOff() or durEff("autoScale") ~= true
          end,
          get = function() return durEff("timerScale") or 1.0 end,
          set = durSet("timerScale") },
        { control = "slider", label = "Font Size", min = 6, max = 24, step = 1,
          id = "fontSize", disabled = "combat",
          hidden = function()
              return durShowOff() or durEff("autoScale") == true
          end,
          get = function() return durEff("fontSize") or 11 end,
          set = durSet("fontSize") },

        { control = "dropdown", label = "Font",
          id = "durationFont", disabled = "combat", hidden = durShowOff,
          options = function()
              local bf = BF()
              local out = {}
              for name in pairs((bf and bf:LSMFontValues()) or {}) do
                  out[#out + 1] = { value = name, text = name }
              end
              table.sort(out, function(a, b) return a.text < b.text end)
              return out
          end,
          -- The effective value can be a PATH (the aura cache stores resolved
          -- paths), so it is normalized onto a real key on read.
          get = function()
              local bf = BF()
              if not bf then return nil end
              return bf:NormalizeFontName(durEff("durationFont"),
                  "Roboto Condensed Bold")
          end,
          set = durSet("durationFont") },
        { control = "dropdown", label = "Font Border",
          options = FONT_BORDER_OPTIONS,
          id = "durationBorder", disabled = "combat", hidden = durShowOff,
          get = function() return durEff("durationBorder") or "" end,
          set = durSet("durationBorder") },

        { control = "color", label = "Duration Text Color", alpha = true,
          desc = "Color of the duration timer text. When Threshold Color is "
              .. "on, this is the color used above the threshold.",
          id = "fontColor", disabled = "combat", hidden = durShowOff,
          get = function()
              local base = AuraCache(DUR_BASELINE.fontColor) or { r = 1, g = 1, b = 1 }
              return durColorGet("fontColor", base)()
          end,
          set = durColorSet("fontColor") },
        -- colorAuraBorder ("Also Color Aura Border") is deliberately NOT
        -- exposed: duration-driven border color has no container expression --
        -- the container duration pass stamps the text curve, not the border.
        { control = "switch", width = "full", labelSide = "after",
          label = "Change Color based on Remaining Time",
          id = "thresholdColorEnabled", default = false,
          disabled = "combat", hidden = durShowOff,
          get = function() return field("thresholdColorEnabled") == true end,
          set = durSet("thresholdColorEnabled") },
        { control = "color", label = "Threshold Color", alpha = true,
          id = "thresholdColor", disabled = "combat",
          hidden = function() return durShowOff() or thresholdOff() end,
          get = function()
              local bf = BF()
              return durColorGet("thresholdColor",
                  bf and bf.DEFAULT_THRESHOLD_COLOR)()
          end,
          set = durColorSet("thresholdColor") },
        { control = "slider", label = "Threshold (seconds)",
          min = 1, max = 59, step = 1,
          id = "thresholdColorThreshold", default = 8, disabled = "combat",
          hidden = function() return durShowOff() or thresholdOff() end,
          get = function() return field("thresholdColorThreshold") or 8 end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              local s = EffectiveSource(c)
              s.thresholdColorThreshold = val
              -- Keep the secondary threshold below the primary.
              local t2 = s.threshold2ColorThreshold
              if t2 and t2 >= val then
                  s.threshold2ColorThreshold = math.max(1, val - 1)
              end
              durRefresh(ctx)
          end },
        { control = "switch", width = "full", labelSide = "after",
          label = "Enable Secondary Threshold",
          id = "threshold2ColorEnabled", default = false, disabled = "combat",
          hidden = function() return durShowOff() or thresholdOff() end,
          get = function() return field("threshold2ColorEnabled") == true end,
          set = durSet("threshold2ColorEnabled") },
        { control = "color", label = "Secondary Threshold Color", alpha = true, id = "threshold2Color", disabled = "combat",
          hidden = function() return durShowOff() or threshold2Off() end,
          get = function()
              local bf = BF()
              return durColorGet("threshold2Color",
                  bf and bf.DEFAULT_THRESHOLD2_COLOR)()
          end,
          set = durColorSet("threshold2Color") },
        { control = "slider", label = "Secondary Threshold (seconds)", min = 1, max = 58, step = 1,
          id = "threshold2ColorThreshold", default = 5, disabled = "combat",
          hidden = function() return durShowOff() or threshold2Off() end,
          get = function() return field("threshold2ColorThreshold") or 5 end,
          set = durSet("threshold2ColorThreshold") },

        { control = "switch", label = "Hide Cooldown Swipe", labelSide = "after",
          id = "disableSwipe", disabled = "combat", hidden = durOwnHidden,
          get = function() return durEff("disableSwipe") == true end,
          set = durSet("disableSwipe") },
        { control = "switch", label = "Hide Cooldown Spark", labelSide = "after",
          id = "disableSpark", disabled = "combat", hidden = durOwnHidden,
          get = function() return durEff("disableSpark") == true end,
          set = durSet("disableSpark") },
        { control = "switch", label = "Reverse Swipe Direction", labelSide = "after",
          id = "reverseSwipe", disabled = "combat", hidden = durOwnHidden,
          get = function() return durEff("reverseSwipe") == true end,
          set = durSet("reverseSwipe") },
    }}

    -- ── Effects (debuff containers only) ───────────────────────
    --
    -- NOTHING invalidated these fields before this group existed, so the
    -- setters below ARE the invalidation: container settings live in acDB and
    -- do not bump the aura cache generation, which is why each one kicks both
    -- container caches explicitly.
    if isDebuff then
        local function iconFx()  return field("containerIconEffect")  or "none" end
        local function frameFx() return field("containerFrameEffect") or "none" end
        local function fxRefresh(ctx)
            local bf = BF()
            InvalidateContainerCaches()
            if bf then bf:RefreshContainersWithRebuildDebounced() end
            RefreshPreviewSoon(ctx)
        end
        local function fxSet(name)
            return function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                EffectiveSource(c)[name] = val
                fxRefresh(ctx)
            end
        end
        local function fxSetColor(name)
            return function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                EffectiveSource(c)[name] = { r = val[1], g = val[2], b = val[3], a = val[4] }
                fxRefresh(ctx)
            end
        end
        local function fxColor(name, dr, dg, db, da)
            local c = field(name)
            if type(c) ~= "table" then return { dr, dg, db, da } end
            return { c.r or dr, c.g or dg, c.b or db, c.a or da }
        end
        -- The inherit fallback reads the EDITED scope, not the active frame's
        -- aura cache: on a scope with an overridden dispel Border Width the
        -- active-cache read would show one number while the effect rendered
        -- another.
        local function dispelField(name, dflt)
            local bf = BF()
            local dP = bf and bf.AurasSubcatForScope
                       and bf.AurasSubcatForScope(getC(), ContainerScopeKey,
                                                  "dispelIndicator")
            return (dP and dP[name]) or dflt
        end

        cards[#cards + 1] = { title = "Effects", preset = "form",
            hidden = offOrHidden, fields = {
            { control = "dropdown", label = "Icon Effect",
              desc = "An animated effect drawn on EVERY icon this container "
                  .. "shows, for as long as it is shown.",
              options = { { value = "none",  text = "None" },
                          { value = "glow",  text = "Glow" },
                          { value = "ants",  text = "Marching Ants" },
                          { value = "flash", text = "Flash" } },
              id = "containerIconEffect", default = "none", disabled = "combat",
              get = iconFx,
              set = function(node, ctx, val)
                  fxSet("containerIconEffect")(node, ctx,
                      (val ~= "none") and val or nil)
              end },
            -- ONLY these two glow styles, by design: every other one is
            -- OnUpdate-driven, and SetScript is refused on engine-owned aura
            -- buttons and their descendants. Do not expose dead options.
            { control = "dropdown", label = "Glow Style",
              desc = "Steady draws the ring at a constant strength; Pulsing "
                  .. "fades it in and out.",
              options = { { value = "steady", text = "Steady" },
                          { value = "pulse",  text = "Pulsing" } },
              id = "containerIconEffectGlowStyle", default = "steady",
              disabled = "combat",
              hidden = function() return offOrHidden() or iconFx() ~= "glow" end,
              get = function() return field("containerIconEffectGlowStyle") or "steady" end,
              set = function(node, ctx, val)
                  fxSet("containerIconEffectGlowStyle")(node, ctx,
                      (val ~= "steady") and val or nil)
              end },
            { control = "color", label = "Effect Color", alpha = true,
              desc = "Tint of the icon effect. For Flash, the alpha sets the "
                  .. "pulse's peak strength.",
              id = "containerIconEffectColor", disabled = "combat",
              hidden = function() return offOrHidden() or iconFx() == "none" end,
              get = function()
                  return fxColor("containerIconEffectColor", 1, 0.82, 0.25, 1)
              end,
              set = fxSetColor("containerIconEffectColor") },

            { control = "dropdown", label = "Frame Effect",
              desc = "A whole-frame effect shown while this container has a "
                  .. "debuff to display.\n\nDraws BELOW the Dispel Indicators' "
                  .. "matching effect. Per-spell buff frame effects sit above "
                  .. "or below it according to their own Prioritise settings."
                  .. "\n\nWith more than one category in this container the "
                  .. "effect is drawn once per MATCHING category, so it looks "
                  .. "stronger while several match at once. Full alpha on the "
                  .. "color below, or one category per container, avoids it.",
              options = { { value = "none",        text = "None" },
                          { value = "healthColor", text = "Change Health Color" },
                          { value = "border",      text = "Show Frame Border" },
                          { value = "overlay",     text = "Show Overlay" } },
              id = "containerFrameEffect", default = "none", disabled = "combat",
              get = frameFx,
              set = function(node, ctx, val)
                  fxSet("containerFrameEffect")(node, ctx,
                      (val ~= "none") and val or nil)
              end },
            { control = "color", label = "Effect Color", alpha = true,
              -- There is no dispel color to inherit for a whole container
              -- (the section's dispel colors are per debuff TYPE), so this
              -- picker IS the effect's color, alpha included.
              desc = "Color of the frame effect. The alpha channel sets its "
                  .. "opacity.",
              id = "containerFrameEffectColor", disabled = "combat",
              hidden = function() return offOrHidden() or frameFx() == "none" end,
              get = function()
                  return fxColor("containerFrameEffectColor", 1, 0, 0, 0.5)
              end,
              set = fxSetColor("containerFrameEffectColor") },
            { control = "stepper", label = "Border Width",
              min = 1, max = 5, step = 1,
              id = "containerFrameEffectBorderWidth", disabled = "combat",
              hidden = function() return offOrHidden() or frameFx() ~= "border" end,
              get = function()
                  local v = field("containerFrameEffectBorderWidth")
                  if v == nil then v = dispelField("debuffBorderWidth", 2) end
                  return v
              end,
              set = fxSet("containerFrameEffectBorderWidth") },
            { control = "slider", label = "Overlay Height",
              min = 0.1, max = 1.0, step = 0.05,
              id = "containerFrameEffectOverlayHeight", disabled = "combat",
              hidden = function() return offOrHidden() or frameFx() ~= "overlay" end,
              get = function()
                  local v = field("containerFrameEffectOverlayHeight")
                  if v == nil then v = dispelField("debuffOverlayHeight", 0.7) end
                  return v
              end,
              set = fxSet("containerFrameEffectOverlayHeight") },
            { control = "switch", label = "Health Fill Only",
              labelSide = "after",
              desc = "When enabled, the overlay only covers the filled portion "
                  .. "of the health bar instead of the entire bar width.",
              id = "containerFrameEffectOverlayFillOnly", default = false,
              disabled = "combat",
              hidden = function() return offOrHidden() or frameFx() ~= "overlay" end,
              get = function()
                  return field("containerFrameEffectOverlayFillOnly") == true
              end,
              set = function(node, ctx, val)
                  fxSet("containerFrameEffectOverlayFillOnly")(node, ctx, val or nil)
              end },
        }}
    end

    return cards, containerOffOnly, groupTypeHidden
end

-- ── The Presets / Assigned Spells surface ──────────────────────
--
-- The Ace side made each preset and each assigned spell a TREE NODE inside
-- the container's own subtab. Here they are CARDS on the container's page:
-- a preset holds one note plus a Remove button (and, on a debuff container,
-- a Relative Size slider), and a spell holds three controls. Four routes for
-- three controls is navigation nobody asked for, and it is the same trade
-- Pages_Layouts made for the Layout Management sub-sub-tabs.

-- Session-only form state, deliberately module-level and shared across every
-- container page -- exactly as the Ace `containerSpecFilter` was. It is
-- PRESENTATIONAL: it hides cards and changes nothing any edit writes.
local containerSpecFilter = 0
-- The Assigned Spells subtab's Add Mode (2026-09-14): which of the three
-- ways of adding to a container the strip shows -- a preset, an existing
-- Buff List entry, or a new buff typed in. Session-scoped, shared by every
-- container page like the spec filter beside it.
local containerAddMode = "buffList"
-- The New Buff box's text and its error note, keyed BY CONTAINER: there are
-- N container pages, and a shared string would make text typed into one
-- container's box appear in every other container's box.
local containerAddText = {}
local containerAddNote = {}

local function SpecFilterOptions()
    local bf  = BF()
    local out = { { value = 0, text = "All" } }
    local order = (bf and bf.HEALER_SPEC_ORDER) or {}
    for i = 1, #order do
        local s = order[i]
        out[#out + 1] = { value = s.id,
            text = (bf and bf.SpecFilterLabel and bf.SpecFilterLabel(s))
                   or s.tabName or s.name or tostring(s.id) }
    end
    return out
end

-- Filtering is by which spec's CURATED list the spell belongs to, so a spell
-- typed in by ID belongs to no list and is reachable under "All" only. Stated
-- in the dropdown's description.
local function SpecFilterHides(sid)
    local bf = BF()
    local f  = containerSpecFilter
    if not f or f == 0 then return false end
    if not sid then return true end
    return not (bf and bf:SingleBuffSpellInSpecList(sid, f))
end

-- 2026-09-14 (owner ruling): what the container page's Add Buff dropdown
-- offers -- the BUFF LIST's entries, not a typed spell. Whitelisted single
-- buffs only (a blacklisted one never renders, so it has nowhere to be
-- anchored), minus the ones already anchored to this container, filtered
-- by the page's Filter by Spec under the Buff List's own rule: an enabled
-- Spec condition claims the entry for the specs it ticks; otherwise the
-- spec's curated list decides, and an entry in no list shows under All
-- only. Sorted by plain name, as the Buff List sorts.
-- The container pages' Filter by Spec, applied to a Buff List ENTRY under
-- the Buff List's own rule: an enabled Spec condition claims the entry for
-- the specs it ticks (an empty condition is incomplete and stays visible);
-- otherwise the spec's curated list decides. Shared by the Add Buff dropdown
-- and the Assigned Spells tree, so the two cannot disagree.
local function ContainerSpecFilterHidesEntry(sb, sid)
    local bf = BF()
    local f  = containerSpecFilter
    if not f or f == 0 then return false end
    if type(sb) == "table" and sb.loadSpec then
        if sb.loadSpecTypes == nil then return false end
        local empty = bf and bf.SingleBuffSpecConditionEmpty
                      and bf.SingleBuffSpecConditionEmpty(sb)
        return (not empty) and (sb.loadSpecTypes[f] == false) or false
    end
    return SpecFilterHides(sid)
end

local function AddBuffOptions(c)
    local bf  = BF()
    local out = {}
    if not (bf and type(c) == "table" and type(c.containerKey) == "string") then
        return out
    end
    local here = "C:" .. c.containerKey
    local arr  = bf:GetCustomBuffContainers() or {}
    local rows = {}
    for i = 1, #arr do
        local sb = arr[i]
        if type(sb) == "table" and sb.singleBuff
           and type(sb.singleBuffKey) == "string"
           and not sb.singleBuffHidden
           and AnchorForScope(sb) ~= here then
            local text, sid = SingleBuffLabel(bf, sb, i)
            if not ContainerSpecFilterHidesEntry(sb, sid) then
                rows[#rows + 1] = {
                    value = sb.singleBuffKey, text = text,
                    sortName = (sb.name or (sid and tostring(sid)) or sb.singleBuffKey):lower(),
                }
            end
        end
    end
    table.sort(rows, function(x, y)
        if x.sortName ~= y.sortName then return x.sortName < y.sortName end
        return x.value < y.value
    end)
    for i = 1, #rows do
        out[i] = { value = rows[i].value, text = rows[i].text }
    end
    return out
end

-- ── The collection nodes ───────────────────────────────────────

-- The blocking check the Ace remove path made in TWO places -- once as the
-- confirm text and once as a silent early-return inside the delete body. The
-- library's `canRemove` is the single place for it: it REFUSES with a reason
-- instead of doing nothing, which is what the Ace silent return did whenever
-- the confirm's own listing was somehow bypassed.
local function AssignedSpellReport(kind, c)
    -- 2026-09-14 (owner ruling): nothing refuses any more. The per-spec
    -- assignment model this reported on is retired (migration 80 turned every
    -- assignment into a Buff List entry anchored to the container), and
    -- removing a container re-points its anchored entries at the Buffs row
    -- (BF:RemoveCustomBuffContainer), so there is no orphan to protect. Kept
    -- as a function so the call sites read the same; it answers nil.
    return nil
end

-- Move a container within its array, and rewrite the ONE index-keyed
-- reference the addon stores: the per-spec assignment string "c:<index>".
--
-- The Ace panel had no reorder gesture at all, so this is the one place this
-- file adds behavior rather than carrying it across -- see the notes. Every
-- OTHER cross-reference is key-based and travels with the table: the flow
-- anchors store "C:<containerKey>", groupSettings and presetRelativeSize live
-- ON the container, and single buffs left spellAssign entirely.
local function MoveContainer(kind, from, to)
    if InCombatLockdown() then return end
    local bf  = BF()
    local arr = Containers(kind)
    if not (bf and arr[from] and arr[to]) or from == to then return end
    local moving = table.remove(arr, from)
    table.insert(arr, to, moving)
    if kind ~= "debuff" then
        -- oldIndex -> newIndex for every slot the move disturbed.
        local remap = {}
        if from < to then
            for i = from + 1, to do remap[i] = i - 1 end
        else
            for i = to, from - 1 do remap[i] = i + 1 end
        end
        remap[from] = to
        local p = bf.acDB and bf.acDB.profile
        for _, perSpec in pairs((p and p.spellAssign) or {}) do
            for sid, assign in pairs(perSpec) do
                if type(assign) == "string" then
                    local n = tonumber(assign:match("^c:(%d+)$"))
                    if n and remap[n] then perSpec[sid] = "c:" .. remap[n] end
                end
            end
        end
        bf:InvalidateClaimedSpellCache()
    end
    InvalidateContainerCaches()
    RefreshContainersHeavy()
end

local function RemoveContainer(kind, c, index)
    if InCombatLockdown() then return end
    local bf = BF()
    if not bf then return end
    -- The buff guard, kept: a container with spells still assigned is not
    -- deleted. canRemove already refused, so reaching here means the state
    -- changed underneath us.
    if kind ~= "debuff" and c and c.selectedSpells then
        for _, on in pairs(c.selectedSpells) do
            if on then return end
        end
    end
    if kind == "debuff" then
        bf:RemoveCustomDebuffContainer(index)
        bf:RefreshAllCustomContainers()
        return
    end
    bf:RemoveCustomBuffContainer(index)
    bf:RefreshAllCustomContainers()
end

-- ── The container member page ──────────────────────────────────

-- The route id for one container. The KEY, never the index: removing an
-- earlier container renumbers the array, and an index-addressed route
-- would then point at its neighbor.
local function ContainerRouteId(kind, key)
    return ((kind == "debuff") and "debuffContainer_" or "container_") .. key
end
BuzzardFramesOptions.ContainerRouteId = ContainerRouteId

local function SectionOf(kind)
    return (kind == "debuff") and "aurasDebuffs" or "aurasBuffs"
end

-- The Assigned Spells tree's members: the Buff List's own records (the same
-- shape SingleBuffMembers hands the Buff List), kept to the entries whose
-- Anchor Point in the scope being edited is THIS container, and narrowed by
-- the page's Filter by Spec. No Whitelist/Blacklist sections: a blacklisted
-- entry never renders, so it has no place in a container.
local function ContainerSpellMembers(kind, key)
    local out = {}
    local c = FindByKey(kind, key)
    if not (type(c) == "table" and type(c.containerKey) == "string") then return out end
    local here = "C:" .. c.containerKey
    for _, rec in ipairs(AllSingleBuffRecords()) do
        if not rec.blacklisted and AnchorForScope(rec.c) == here
           and not ContainerSpecFilterHidesEntry(rec.c, rec.sid) then
            out[#out + 1] = rec
        end
    end
    return out
end

-- A BUFF container's page (2026-09-14, owner ruling): the identity card at
-- the top, then an in-page strip of two subtabs -- Container Settings (the
-- per-Layout scope strip, the setting cards) first, and
-- Assigned Spells (the Add/Filter surface, the preset cards and the tree of
-- anchored entries). The strip is in the page rather than in the header
-- band so the card can sit above it. A debuff container has one page, as
-- before (scope strip, identity, presets, then settings).
local function ContainerMemberPage(kind)
    return function(mctx)
        local key = mctx.key
        -- Resolved by KEY on every call: an earlier delete renumbers the
        -- array, and a closure can outlive the rebuild that would have
        -- re-captured the index.
        local function getC() return (FindByKey(kind, key)) end

        local isDebuff = (kind == "debuff")
        local cards, containerOff = ContainerCards(kind, getC)
        local page = { groups = {} }

        -- The scope row FIRST, above the container's own settings: the read
        -- order is per-Layout -> per-Layout detail -> settings, exactly as
        -- the aura subtabs read. A BUFF container puts it inside its
        -- Container Settings subtab instead, off the Assigned Spells one.
        local scope = ScopeStrip(getC, "container", kind)
        if isDebuff then page.groups[#page.groups + 1] = scope end
        -- The Aura Preview dropdown goes in the PAGE HEADER, above the
        -- subtab strip, which is where the Ace section root drew it: it
        -- belongs to the section rather than to the tab you are on, and as
        -- a card it was the first thing on every one of them. Set below,
        -- once the page table exists.
        -- The identity card (Enabled / Name / Type) leads. For a BUFF the
        -- remaining setting cards follow it, then the Assigned Spells surface.
        -- For a DEBUFF the Presets surface comes BEFORE the settings, so those
        -- cards are deferred and appended after the preset cards below.
        page.groups[#page.groups + 1] = cards[1]
        -- Buff setting cards do NOT go here: they live in the Container
        -- Settings subtab appended after the Assigned Spells surface. Debuff
        -- setting cards are appended after the Presets surface below.

        -- A BUFF container's cards below the identity card go into the
        -- two subtabs; `page.groups` keeps the identity card and the strip.
        local spellsGroups = {}
        local into = isDebuff and page.groups or spellsGroups

        -- The Presets / Assigned Spells surface.
        local listFields = {}
        local function modeIsnt(mode)
            return function() return containerAddMode ~= mode end
        end
        if not isDebuff then
            listFields[#listFields + 1] = {
                control = "segmented", label = "Add Mode",
                desc = "Preset: add a game category of buffs.\n\nSelect from "
                    .. "Buff List: anchor an existing Buff List entry to this "
                    .. "container.\n\nNew Buff: type a spell to create a new "
                    .. "Buff List entry, anchored to this container.",
                options = { { value = "preset",   text = "Preset" },
                            { value = "buffList", text = "Select from Buff List" },
                            { value = "newBuff",  text = "New Buff" } },
                id = "containerAddMode", default = "buffList",
                get = function() return containerAddMode end,
                set = function(_, ctx, val)
                    containerAddMode = val
                    ctx.app:RefreshPage()
                end }
            listFields[#listFields + 1] = {
                control = "dropdown", label = "Filter by Spec",
                hidden = modeIsnt("buffList"),
                desc = "Show only buffs whose spell is in that spec's curated "
                    .. "list in Aura Customizations. A spell that is in no "
                    .. "curated list (any spell ID you typed in yourself) "
                    .. "appears under All only.",
                options = SpecFilterOptions,
                get = function() return containerSpecFilter end,
                set = function(_, ctx, val)
                    containerSpecFilter = tonumber(val) or 0
                    ctx.app:RefreshPage()
                end }
        end
        listFields[#listFields + 1] = {
            control = "dropdown", label = "Add Preset",
            hidden = (not isDebuff) and modeIsnt("preset") or nil,
            desc = isDebuff
                and "Add a category of debuffs to this container.\n\nDispellable "
                 .. "by Me shows only the debuffs your character can dispel; "
                 .. "Dispellable by Others shows the dispellable debuffs it "
                 .. "cannot. Boss, Priority and Role Auras are the game's own "
                 .. "classifications.\n\nA preset shows whatever the game puts "
                 .. "in that category, so it needs no spell list and updates "
                 .. "itself as the game changes."
                or "Add a category of buffs to this container, rather than one "
                 .. "spell.\n\nImportant, Big Defensive and External Defensive "
                 .. "are the game's own classifications. Applied by Me shows any "
                 .. "buff you cast.\n\nA preset shows whatever the game puts in "
                 .. "that category, so it needs no spell list and updates itself "
                 .. "as the game changes.",
            disabled = "combat",
            -- An action, not a stored value.
            get = function() return nil end,
            options = function()
                local bf = BF()
                local out = {}
                local defs  = bf and (isDebuff and bf.DEBUFF_CONTAINER_PRESETS
                                              or  bf.CONTAINER_PRESETS)
                local order = bf and (isDebuff and bf.DEBUFF_CONTAINER_PRESET_ORDER
                                              or  bf.CONTAINER_PRESET_ORDER)
                if not (defs and order) then return out end
                local c = getC()
                for i = 1, #order do
                    local k = order[i]
                    -- A preset already on THIS container would add nothing. For
                    -- a DEBUFF container a preset is a mutually-exclusive claim
                    -- on a game category, so one already held by ANY debuff
                    -- container is dropped from every container's list.
                    local taken = (c and c.presets and c.presets[k]) and true or false
                    if not taken and isDebuff then
                        local all = Containers("debuff")
                        for j = 1, #all do
                            if all[j] and all[j].presets and all[j].presets[k] then
                                taken = true
                            end
                        end
                    end
                    if defs[k] and not taken then
                        out[#out + 1] = { value = k, text = defs[k].name }
                    end
                end
                return out
            end,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                if type(val) ~= "string" or val == "" then return end
                local bf, c = BF(), getC()
                local defs = bf and (isDebuff and bf.DEBUFF_CONTAINER_PRESETS
                                             or  bf.CONTAINER_PRESETS)
                if not (bf and c and defs and defs[val]) then return end
                if type(c.presets) ~= "table" then c.presets = {} end
                c.presets[val] = true
                InvalidateContainerCaches()
                RefreshContainersHeavy()
                if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
                ctx.app:RefreshPage()
            end }

        if not isDebuff then
            -- 2026-09-14 (owner ruling): Add Buff picks a BUFF LIST entry
            -- and anchors it to this container -- the same write the
            -- entry's own Anchor Point dropdown makes when it chooses this
            -- container. Nothing is created and no spell is typed: the
            -- Buff List is where entries come from.
            listFields[#listFields + 1] = {
                control = "dropdown", label = "Add Buff",
                hidden = modeIsnt("buffList"),
                desc = "Anchor a buff from the Buff List to this container. "
                    .. "Filter by Spec narrows this list too.",
                disabled = "combat",
                -- An action, not a stored value.
                get = function() return nil end,
                options = function() return AddBuffOptions(getC()) end,
                set = function(_, ctx, val)
                    if InCombatLockdown() then return end
                    if type(val) ~= "string" or val == "" then return end
                    local bf, c = BF(), getC()
                    if not (bf and c and type(c.containerKey) == "string") then return end
                    local arr = bf:GetCustomBuffContainers() or {}
                    local sb
                    for i = 1, #arr do
                        if type(arr[i]) == "table" and arr[i].singleBuffKey == val then
                            sb = arr[i]
                            break
                        end
                    end
                    if not sb then return end
                    local src = EffectiveSource(sb)
                    src.anchorPoint = "C:" .. c.containerKey
                    local def = bf.GROW_DEFAULT_FOR_ANCHOR
                                and bf.GROW_DEFAULT_FOR_ANCHOR[src.anchorPoint]
                    if def then src.growDirection = def end
                    -- A routing change: the heavy path clears the old
                    -- host's icons.
                    bf:RefreshContainersWithRebuildDebounced()
                    -- STRUCTURAL: the entry now belongs in this container's
                    -- Assigned Spells tree (and its Buff List row is
                    -- unchanged but re-indexed with it).
                    ctx.app:Invalidate("singleBuffs")
                end }
            -- NEW BUFF: a net new Buff List entry, created exactly as the Buff
            -- List's own Add creates one (BF:CreateSingleBuffContainer -- the
            -- same name resolution, the same defaults), then anchored to
            -- this container instead of the Buffs row.
            listFields[#listFields + 1] = {
                control = "text", label = "Add Spell Name or ID",
                hidden = modeIsnt("newBuff"),
                submit = "Add", disabled = "combat",
                suggest = SpellSuggestions,
                desc = "Start typing a buff name for suggestions from the "
                    .. "curated buff list, or paste any spell ID.\n\nThe buff is "
                    .. "added to the Buff List, anchored to this container, as "
                    .. "soon as you press Enter.",
                get = function() return containerAddText[key] or "" end,
                set = function(_, ctx, val)
                    local bf = BF()
                    local text = tostring(val or "")
                    containerAddText[key] = text
                    containerAddNote[key] = nil
                    -- Empty box + Enter is not an attempt to add anything.
                    if text:match("^%s*$") then return end
                    if InCombatLockdown() then
                        containerAddNote[key] = "|cffff8080Not available in combat.|r"
                        ctx.app:RefreshPage()
                        return
                    end
                    local c = getC()
                    if not (bf and c and type(c.containerKey) == "string") then return end
                    local newIndex, err, sbKey = bf:CreateSingleBuffContainer(text, nil, false)
                    if not newIndex then
                        containerAddNote[key] = "|cffff8080" .. tostring(err) .. "|r"
                        ctx.app:RefreshPage()
                        return
                    end
                    local sb = sbKey and bf:FindSingleBuffByKey(sbKey)
                        or Containers("buff")[newIndex]
                    if sb then
                        -- A NEW entry has no per-Layout tier yet, so this is
                        -- its shared top level -- the same write the Anchor
                        -- Point dropdown makes.
                        local src = EffectiveSource(sb)
                        src.anchorPoint = "C:" .. c.containerKey
                        local def = bf.GROW_DEFAULT_FOR_ANCHOR
                                    and bf.GROW_DEFAULT_FOR_ANCHOR[src.anchorPoint]
                        if def then src.growDirection = def end
                        -- A spec filter that would hide what was just added
                        -- reads as "nothing happened": clear it, but only
                        -- when it actually excludes the new entry.
                        local sid = bf:GetSingleBuffSpellID(sb)
                        if ContainerSpecFilterHidesEntry(sb, sid) then
                            containerSpecFilter = 0
                        end
                    end
                    containerAddText[key] = ""
                    bf:RefreshContainersWithRebuildDebounced()
                    -- STRUCTURAL: a new Buff List row, and a new row in this
                    -- container's tree.
                    ctx.app:Invalidate("singleBuffs")
                end }
            listFields[#listFields + 1] = {
                control = "note", wide = true,
                hidden = function() return containerAddNote[key] == nil end,
                text = function() return containerAddNote[key] or "" end }
        end

        -- A DEBUFF container's presets are a LIST under the Add Preset
        -- dropdown -- one CHIP per held preset, the X inside the button --
        -- rather than a card each: a debuff preset has nothing to configure
        -- here (its Relative Size lives on the Debuffs Preset/Filter subtab's
        -- row card), so a card per preset was a heading and a Remove button.
        -- Chips rather than rows because a preset name is two words and a
        -- handful of them are a set the reader takes in at a glance, not a
        -- column to read down -- and they wrap, so six cost one line or two
        -- rather than six.
        if isDebuff then
            local function removePreset(item, ctx)
                if InCombatLockdown() then return end
                local b, c = BF(), getC()
                if not (b and c and c.presets) then return end
                c.presets[item.value] = nil
                if next(c.presets) == nil then c.presets = nil end
                InvalidateContainerCaches()
                RefreshContainersHeavy()
                if b.RefreshPreviewDummyAuras then b:RefreshPreviewDummyAuras() end
                ctx.app:RefreshPage()
            end
            listFields[#listFields + 1] = {
                control = "list", layout = "inline", disabled = "combat",
                removeTooltip = "Stop showing this category in this container.",
                -- Says so out loud when the container holds none. Without
                -- it an empty list is indistinguishable from a list that
                -- failed to draw -- the card shows the Add dropdown and
                -- nothing under it either way.
                emptyText = "|cffaaaaaaNo presets yet. Use Add Preset above.|r",
                items = function()
                    local b, c = BF(), getC()
                    local out  = {}
                    local defs  = b and b.DEBUFF_CONTAINER_PRESETS
                    local order = b and b.DEBUFF_CONTAINER_PRESET_ORDER
                    if not (defs and order and c and c.presets) then return out end
                    for i = 1, #order do
                        local pkey = order[i]
                        local def  = defs[pkey]
                        if def and c.presets[pkey] then
                            out[#out + 1] = { value = pkey, text = def.name,
                                tooltip = "Shows every debuff the game classifies as "
                                    .. def.name .. ".\n\nClick to stop showing this "
                                    .. "category in this container." }
                        end
                    end
                    return out
                end,
                onRemove = removePreset }
        end

        into[#into + 1] = {
            title = isDebuff and "Presets" or "Assigned Buffs",
            preset = "form", hidden = containerOff, fields = listFields }

        -- One card per preset the container holds (buff containers -- a
        -- debuff container's presets are the list above).
        local bf = BF()
        local c0 = getC()
        local defs  = bf and (isDebuff and bf.DEBUFF_CONTAINER_PRESETS
                                      or  bf.CONTAINER_PRESETS)
        local order = bf and (isDebuff and bf.DEBUFF_CONTAINER_PRESET_ORDER
                                      or  bf.CONTAINER_PRESET_ORDER)
        local classifyWord = isDebuff and "debuff" or "buff"
        if (not isDebuff) and defs and order and c0 and c0.presets then
            for i = 1, #order do
                local pkey = order[i]
                local def  = defs[pkey]
                if def and c0.presets[pkey] then
                    local presetFields = {
                        { control = "note", wide = true,
                          text = "|cffaaaaaaShows every " .. classifyWord
                              .. " the game classifies as |r" .. def.name
                              .. "|cffaaaaaa.|r" },
                    }
                    if isDebuff then
                        -- Scales THIS preset's icon size against the container's
                        -- base; when two overlapping presets differ in size the
                        -- larger one wins the shared aura and flows first.
                        -- STORAGE stays the raw percent (10..200) it always was;
                        -- the UI value is a 0.1..2.0 multiplier.
                        presetFields[#presetFields + 1] = {
                            control = "slider", label = "Relative Size",
                            min = 0.1, max = 2.0, step = 0.05, isPercent = true,
                            id = "presetRelativeSize_" .. pkey, default = 1,
                            desc = "Size of this category's icons relative to "
                                .. "the container's icon size. At 100% it "
                                .. "matches the container. When two categories "
                                .. "overlap, the larger one wins the shared aura "
                                .. "and flows first.",
                            disabled = "combat",
                            get = function()
                                local c = getC()
                                local v = c and c.presetRelativeSize
                                          and c.presetRelativeSize[pkey]
                                return (v or 100) / 100
                            end,
                            set = function(_, ctx, val)
                                if InCombatLockdown() then return end
                                local c = getC()
                                if not c then return end
                                val = math.floor(val * 100 + 0.5)
                                if val == 100 then
                                    if c.presetRelativeSize then
                                        c.presetRelativeSize[pkey] = nil
                                        if next(c.presetRelativeSize) == nil then
                                            c.presetRelativeSize = nil
                                        end
                                    end
                                else
                                    c.presetRelativeSize = c.presetRelativeSize or {}
                                    c.presetRelativeSize[pkey] = val
                                end
                                InvalidateContainerCaches()
                                -- The value write and the invalidations stay
                                -- immediate; the rebuild and the preview
                                -- coalesce per drag.
                                local b = BF()
                                if b then b:RefreshContainersWithRebuildDebounced() end
                                RefreshPreviewSoon(ctx)
                            end }
                    end
                    presetFields[#presetFields + 1] = {
                        control = "button", label = "Remove from Container",
                        desc = "Stop showing this category in this container.",
                        disabled = "combat",
                        onClick = function(_, ctx)
                            if InCombatLockdown() then return end
                            local b, c = BF(), getC()
                            if not (b and c and c.presets) then return end
                            c.presets[pkey] = nil
                            if next(c.presets) == nil then c.presets = nil end
                            InvalidateContainerCaches()
                            RefreshContainersHeavy()
                            if b.RefreshPreviewDummyAuras then b:RefreshPreviewDummyAuras() end
                            ctx.app:RefreshPage()
                        end }
                    into[#into + 1] = {
                        title = "|cff87ceeb" .. def.name .. "|r",
                        preset = "form", hidden = containerOff,
                        fields = presetFields }
                end
            end
        end

        -- DEBUFF: the setting cards come AFTER the Presets surface (the Ace
        -- order -- Presets subtab before Container Settings subtab).
        if isDebuff then
            for i = 2, #cards do into[#into + 1] = cards[i] end
        end

        -- 2026-09-14 (owner ruling): the per-spell cards of the retired
        -- assignment model are gone. A buff container's content is the Buff
        -- List entries anchored to it (the chips above), each edited on its
        -- own Buff List page.

        -- THE TREE (buff): the entries anchored to this container, one row
        -- each, with the selected entry's Buff List pages beside it -- the
        -- Buff List's own tree card, pointed at this container's collection
        -- (ContainerRouteList mints it as the "spells" child). Same width,
        -- same fill rule. An entry re-anchored elsewhere leaves this list on
        -- the next re-index (the Anchor Point setter invalidates).
        if not isDebuff then
            into[#into + 1] = { preset = "bare",
                hidden = function()
                    local c = getC()
                    if containerOff() then return true end
                    return #ContainerSpellMembers(kind, key) > 0
                end,
                fields = { { control = "note", wide = true,
                    text = function()
                        -- Two different absences: nothing anchored at all,
                        -- or nothing that passes Filter by Spec.
                        if containerSpecFilter and containerSpecFilter ~= 0 then
                            local c = getC()
                            local here = c and c.containerKey and ("C:" .. c.containerKey)
                            if here then
                                for _, rec in ipairs(AllSingleBuffRecords()) do
                                    if not rec.blacklisted and AnchorForScope(rec.c) == here then
                                        return "|cffaaaaaaThis spec has no buffs assigned "
                                            .. "to this container yet.|r"
                                    end
                                end
                            end
                        end
                        return "|cffaaaaaaNo buffs anchored to this container yet. "
                            .. "Use Add Buff above, or set a buff's Anchor Point to "
                            .. "this container on its Buff List page.|r"
                    end } } }
            into[#into + 1] = { preset = "form", flush = 2,
                hidden = function()
                    return containerOff() or #ContainerSpellMembers(kind, key) == 0
                end,
                tree = { route = SectionRoot() .. "/" .. SectionOf(kind) .. "/"
                             .. ContainerRouteId(kind, key) .. "/"
                             .. ContainerRouteId(kind, key) .. "_spells",
                         width = 175, height = "fill", minHeight = 240,
                         listTopPad = 0 } }
        end

        -- THE STRIP (buff): Container Settings first, then Assigned Spells.
        if not isDebuff then
            -- No "Applied By" card here: each assigned buff carries its
            -- own (see AppliedByField).
            local settingsGroups = { scope }
            for i = 2, #cards do settingsGroups[#settingsGroups + 1] = cards[i] end
            page.groups[#page.groups + 1] = {
                subtabKey = "containerSub:" .. tostring(key),
                subtabs = {
                    { id = "settings", title = "Container Settings",
                      groups = settingsGroups },
                    { id = "spells",   title = "Assigned Buffs",
                      groups = spellsGroups },
                },
            }
        end

        PushDownGroupHidden(page.groups)
        -- Above the strip, not on the page: it writes the SECTION's
        -- account-wide key, so a buff container gets the Buffs one and a
        -- debuff container the Debuffs one.
        page.headerField = BuzzardFramesOptions:AuraPreviewField(
            isDebuff and "aurasDebuffs" or "aurasBuffs")
        return page
    end
end

-- ── The two container collections ──────────────────────────────

local function ContainerCollection(kind, id, title)
    local isDebuff = (kind == "debuff")
    return {
        node   = "collection",
        id     = id,
        title  = title,
        -- The strip the members are drawn in, sitting where the Ace
        -- container_<i> subtabs sat: beside the section's own tabs.
        navigator = "tabs",
        source = function() return Containers(kind) end,
        -- The PARTITION. One array backs two surfaces, and this is the
        -- library's word for that: the entries marked `singleBuff` are routed
        -- to the Buff List instead. Debuff containers have no single-buff
        -- variant, so their collection takes no filter.
        filter = (not isDebuff) and function(item)
            return not item.singleBuff
        end or nil,
        key         = ContainerKeyOf,
        memberTitle = function(item, index)
            return item.name or ((isDebuff and "Debuff " or "")
                                 .. "Custom " .. tostring(index))
        end,
        -- Color is a function of state, resolved at paint time. The Ace side
        -- concatenated escape codes onto the container's own name to get this,
        -- which is one careless write away from putting them in stored data.
        memberColor = function(item)
            if (not item.singleBuff) and item.enabled == false then
                return CONTAINER_BLUE_OFF
            end
            return CONTAINER_BLUE
        end,
        template  = ContainerMemberPage(kind),
        emptyText = isDebuff
            and "No custom debuff containers yet. Add one to place a group of "
             .. "debuff icons independently of the main Debuffs row."
            or  "No custom buff containers yet. Add one to place a group of buff "
             .. "icons independently of the main Buffs row.",
        add = {
            -- The library's default combat gate is left ON: the Ace pseudo-tab
            -- refused in combat, and the create function refuses too.
            onAdd = function()
                if InCombatLockdown() then return nil end
                local bf = BF()
                if not bf then return nil end
                local newIndex
                if isDebuff then
                    local _ok, ni = bf:CreateCustomDebuffContainer()
                    newIndex = ni
                else
                    local _ok, ni = bf:CreateCustomBuffContainer()
                    newIndex = ni
                end
                local arr = Containers(kind)
                return newIndex and arr[newIndex] or nil
            end,
            -- Land ON the new container, which is what the Ace deferred
            -- SelectGroup did once its subtab existed.
            select = true,
        },
        remove = {
            -- Removal can be REFUSED, with a reason: a container with spells
            -- still assigned says so instead of silently doing nothing.
            canRemove = function(item)
                local reason = AssignedSpellReport(kind, item)
                if reason then return false, reason end
                return true
            end,
            confirm = function()
                return "Remove this custom " .. (isDebuff and "debuff" or "buff")
                    .. " container?"
            end,
            tooltip = "Remove container",
            onRemove = function(item, index) RemoveContainer(kind, item, index) end,
        },
        reorder = {
            onMove = function(_, from, to) MoveContainer(kind, from, to) end,
        },
    }
end

-- ── Containers as SIBLING routes ───────────────────────────────
--
-- WHY NOT THE COLLECTION ABOVE. A collection is a route node, so its
-- members are routes UNDER it, and a node that declares `navigator =
-- "tabs"` draws its own strip. Nest that inside a section that also has a
-- strip and MountContextual wants both: it collects every node on the
-- route carrying a contextual navigator and takes math.max of their
-- heights, so the two draw at the same anchor and the inner strip lands
-- ON TOP of the outer one.
--
-- The Ace panel had no nesting to begin with. Its container subtabs sat
-- at order 10 + index in the SAME strip as Buffs and Big Defensive, so
-- what matches it is sibling routes, not a child collection -- which is
-- what this builds. The collection above is kept because it is the whole
-- of the add / remove / refusal / reorder behavior written down in one
-- place, and everything below reuses its parts: the same member page, the
-- same key rule, the same create and remove calls, the same refusal
-- report.
--
-- What is lost by not being a collection, and it is worth knowing:
--
--   * the library's corner X. Replaced by a Remove Container card at the
--     foot of each container's page, carrying the same confirmation and
--     the same refusal reason.
--   * drag to reorder. Ace never had it either -- it was the one
--     behavior the collection ADDED -- so this is a return to the old
--     panel rather than a regression against it.
--
-- Everything else -- the per-Layout scope gate, the shared-scope note,
-- the preset and spell surfaces -- lives in the member page and is
-- untouched.

-- The app, for the member page's context. Looked up rather than captured:
-- this file is parsed before the panel is ever opened.
local function App()
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    return Panel and Panel:GetApp("BuzzardFrames")
end

-- The card the corner X used to be.
local function RemoveCard(kind, key)
    local isDebuff = (kind == "debuff")
    local noun = isDebuff and "debuff" or "buff"
    -- The refusal is a DISABLED button with the reason in its tooltip,
    -- rather than a dialog that says no after the click: the answer does
    -- not depend on the click, so it can be shown before it.
    local function refusal()
        local c = FindByKey(kind, key)
        if not c then return "This container no longer exists." end
        return (AssignedSpellReport(kind, c))
    end
    return { title = "Remove Container", preset = "form", fields = {
        { control = "button", label = "Remove Container", danger = true,
          disabled = function()
              return InCombatLockdown() or refusal() ~= nil
          end,
          desc = function()
              return refusal()
                  or ("Remove this custom " .. noun .. " container. Its "
                      .. "settings are deleted; the spells it showed go back "
                      .. "to wherever they would otherwise appear.")
          end,
          onClick = function(_, ctx)
              if InCombatLockdown() then return end
              local c, index = FindByKey(kind, key)
              if not c or refusal() then return end
              -- Read HERE, not inside the confirmation: the callback runs
              -- after the dialog is answered, by which point the page that
              -- knew which section it was in is no longer rendering.
              local root = SectionRoot()
              ctx.app:Confirm(
                  "Remove this custom " .. noun .. " container?",
                  function()
                      RemoveContainer(kind, c, index)
                      -- Off this route BEFORE it stops existing: the
                      -- rebuild drops the node, and a route pointing at a
                      -- node that is gone has nothing to render.
                      ctx.app:Navigate(root, SectionOf(kind))
                      -- REBUILD, not Invalidate: these tabs are declared
                      -- children rather than a collection's, so only
                      -- re-running the declaration drops the removed one.
                      -- Invalidate left the tab in the strip with a page
                      -- that could no longer find its container -- a tab
                      -- that opened onto nothing.
                      BuzzardFramesOptions:RebuildRoutes(ctx.app)
                  end)
          end },
    }}
end

-- The last tab in the strip, where Ace's "Add Container" pseudo-tab sat.
--
-- A real page with a real button. The Ace version created a container
-- from its own RENDER, one frame later, behind a pending flag and a
-- one-per-second runaway guard -- because a tab that is only a tab has
-- nowhere to put a click. A route has a page, so the click can be a
-- click.
local function AddContainerNode(kind)
    local isDebuff = (kind == "debuff")
    return {
        id    = ContainerRouteId(kind, "__add"),
        title = "Add Container",
        -- No color of its own (2026-09-14, owner ruling): the strip's
        -- plain tab text, unlike the blue container tabs beside it.
        page = function()
            return {
                -- The section's Aura Preview dropdown, as on every other
                -- tab of it. Without it the header's field row collapses on
                -- this one tab and the whole strip jumps up as you arrive
                -- -- the dropdown belongs to the SECTION, so it stays for
                -- every tab in the section, this one included.
                headerField = BuzzardFramesOptions:AuraPreviewField(
                    isDebuff and "aurasDebuffs" or "aurasBuffs"),
                groups = { { preset = "bare", fields = {
                { control = "note", wide = true, text = isDebuff
                    and "A custom debuff container is a separate group of debuff "
                     .. "icons you can size and position independently of the "
                     .. "main Debuffs row, filled from its own Add Preset list."
                    or  "A custom aura container is a separate group of buff "
                     .. "icons you can size and position independently of the "
                     .. "main Buffs row, filled from its own Add Spell box.\n\n"
                     .. "To place or hide a single spell, use the Buff List "
                     .. "subtab instead." },
                { control = "button", label = "Add Container",
                  confirm = true, disabled = "combat",
                  onClick = function(_, ctx)
                      if InCombatLockdown() then return end
                      local bf = BF()
                      if not bf then return end
                      local newIndex
                      if isDebuff then
                          local _ok, ni = bf:CreateCustomDebuffContainer()
                          newIndex = ni
                      else
                          local _ok, ni = bf:CreateCustomBuffContainer()
                          newIndex = ni
                      end
                      if not newIndex then return end
                      local arr = Containers(kind)
                      local c   = arr[newIndex]
                      if not c then return end
                      local key = ContainerKeyOf(c, newIndex)
                      -- REBUILD, not Invalidate. Invalidate re-INDEXES
                      -- the tree it already has, and recomputes children
                      -- only for a collection node -- these container tabs
                      -- are declared children, built by ContainerRouteList
                      -- when the tree was DECLARED. So the new container's
                      -- route did not exist, the strip kept the tabs it
                      -- had, and the Navigate below went nowhere.
                      -- RebuildRoutes re-runs the declaration, which reads
                      -- the array as it is now.
                      --
                      -- Before navigating, either way: Navigate to a node
                      -- that is not there fails silently. Ace hit the same
                      -- ordering with GroupExists.
                      BuzzardFramesOptions:RebuildRoutes(ctx.app)
                      ctx.app:Navigate(SectionRoot(), SectionOf(kind),
                                       ContainerRouteId(kind, key))
                  end },
            } } },
            }
        end,
    }
end

-- ── Arrival on a container tab ─────────────────────────────────
--
-- The Ace pane carried an invisible `description` widget
-- (_containerTabTracker, Options_AuraCustomizations.lua:1506-1596) whose
-- name callback fired on every render and did four things: stamped the
-- host section, stamped the sub-category, recorded which container the
-- pane belongs to, and pointed the preview at it. Two of those were Ace
-- chrome -- the panel-level remove-X tuple and the NotifyChange that made
-- the section root's `hidden` predicates re-evaluate -- and neither has a
-- panel equivalent: the X is on the container's own card and the page
-- re-renders itself. What is left is the preview, and a route observer
-- says it on ENTRY rather than on every repaint.
--
-- The container is addressed by KEY in the route and by INDEX in the
-- preview machinery, so the key is resolved through FindByKey on every
-- arrival: an earlier delete renumbers the array under a captured index.
local containerObserversArmed = false

-- The array position of the container the route names, or nil for the Add
-- tab, an unknown key, or a route that is not a container tab at all.
local function ContainerIndexForRoute(kind, routeKey)
    local seg = routeKey and routeKey:match("^[^/]+/" .. SectionOf(kind) .. "/([^/]+)")
    if not seg then return nil end
    local prefix = ContainerRouteId(kind, "")
    if seg:sub(1, #prefix) ~= prefix then return nil end
    local key = seg:sub(#prefix + 1)
    -- The Add tab shares the prefix and is not a container: `false`, so
    -- the caller can tell it from a route that is not a container tab.
    if key == "" or key == "__add" then return false end
    local _c, index = FindByKey(kind, key)
    return index
end

local function EnterContainer(kind, routeKey)
    local bf = BF()
    if not bf then return end
    local globalIndex = ContainerIndexForRoute(kind, routeKey)
    if globalIndex == nil then return end
    if globalIndex == false then
        -- The Add tab: an action, not a container. Arriving from a
        -- container tab would otherwise leave that container's narrowed
        -- preview on screen, so it gets what a sibling subtab gets --
        -- the plain section preview.
        bf._currentContainerIndex = nil
        if bf.IsPreviewingContainerMgmt and bf:IsPreviewingContainerMgmt() then
            if bf.ClearAuraPreview then bf:ClearAuraPreview() end
            if not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
                bf:RefreshPreviewDummyAuras()
            end
        end
        return
    end
    local isDebuff = (kind == "debuff")
    -- The SECTION name, which drives the dummy-aura preview's context. A
    -- page reached under a Custom Frame Group scope reports
    -- "customFrameAuras", exactly as the Ace CFG page's own tracker did.
    -- These subtabs report what their SIBLING aura subtabs report, never
    -- "customAuras" -- that value suppresses the buff and debuff previews
    -- entirely and is the Aura Customizations page's own. What narrows a
    -- buff container's tab to the buffs assigned to it (owner ruling,
    -- 2026-09-15: no regular Buffs row, no Big Defensive, no other
    -- containers) is the containerMgmt preview mode stamped below, which
    -- the dummy-aura engine reads directly (DummyAuras.lua BuildSharedState,
    -- containerTabOnly) -- not the section.
    local section = (bf.BFOSectionName and bf:BFOSectionName()) or "auras"
    if bf._currentSection ~= section then bf._currentSection = section end
    bf._currentAurasSubcat    = isDebuff and "debuffs" or "buffs"
    bf._currentContainerIndex = globalIndex
    if isDebuff then
        -- The container-management preview is BUFF-array only: it narrows
        -- on the buff container at this index, which from a debuff tab is
        -- a different container entirely. Clearing it leaves the normal
        -- section preview -- with the debuff row in it -- which is the
        -- honest view until a debuff-container preview path exists.
        if bf.IsPreviewingContainerMgmt and bf:IsPreviewingContainerMgmt() then
            if bf.ClearAuraPreview then bf:ClearAuraPreview() end
            if not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
                bf:RefreshPreviewDummyAuras()
            end
        end
    elseif bf.SetContainerPreview
           and (not bf.GetPreviewContainerIndex
                or bf:GetPreviewContainerIndex() ~= globalIndex) then
        bf:SetContainerPreview(globalIndex)
        -- 2026-09-14: the general painter draws the viewed container's
        -- anchored buffs (DummyAuras' container-tab set), so the dummies
        -- are repainted on arrival rather than waiting for a setting edit.
        if not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
            bf:RefreshPreviewDummyAuras()
        end
        -- Deferred by a frame, as Ace deferred it: the narrowing draw has
        -- to land after the render this arrival triggers, or the page's
        -- own repaint puts the unnarrowed preview back.
        -- The closure runs after WithScope has unbound, so it talks to
        -- the real addon rather than to a scope proxy that is no longer
        -- current; the narrowing state it reads is engine-wide anyway.
        if not InCombatLockdown() then
            C_Timer.After(0, function()
                local real = _G.BuzzardFrames
                if real and real.IsPreviewingContainerMgmt
                   and real:IsPreviewingContainerMgmt()
                   and real.ShowContainerPreviewOnAllFrames then
                    real:ShowContainerPreviewOnAllFrames()
                end
            end)
        end
    end
end

-- Armed while the route tree is built, which is the earliest moment the
-- app exists and is before any navigation can reach a container tab.
--
-- `true` for everyChange: moving between two container tabs of one
-- section never leaves the pattern, and each arrival has to narrow the
-- preview onto its own container.
-- Leaving a container tab (2026-09-14): the container-management preview --
-- the viewed container drawn with the buffs anchored to it -- must not
-- outlive the tab. The observer reports the LEAVE as well (isActive false),
-- and the aura subtabs beside it (Buffs, Big Defensive) stamp no preview of
-- their own, so a mode left standing would keep painting that container's
-- spells on a page that is not about it. Cleared only while it is still the
-- container mode: a sibling that stamps its own mode on arrival (the Buff
-- List) may already have replaced it by the time this runs.
local function LeaveContainer()
    local bf = BF()
    if not bf then return end
    if bf.IsPreviewingContainerMgmt and bf:IsPreviewingContainerMgmt() then
        bf._currentContainerIndex = nil
        if bf.ClearAuraPreview then bf:ClearAuraPreview() end
        if not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
            bf:RefreshPreviewDummyAuras()
        end
    end
end

local function EnsureContainerObservers()
    if containerObserversArmed then return end
    local app = App()
    if not app then return end
    containerObserversArmed = true
    for _, kind in ipairs({ "buff", "debuff" }) do
        local pattern = SectionOf(kind) .. "/" .. ContainerRouteId(kind, "*")
        -- WithScope(nil, ...): observers fire from the navigation, BEFORE
        -- the render that would rebind the scope, so on a Custom Frame
        -- Groups -> Raid/Party move this body would otherwise run with the
        -- group's scope still bound -- and every stamp it makes is a write
        -- through the proxy.
        app:RegisterRouteObserver("raidPartyFrames/" .. pattern,
            function(isActive, routeKey)
                if not isActive then
                    BuzzardFramesOptions:WithScope(nil, LeaveContainer)
                    return
                end
                BuzzardFramesOptions:WithScope(nil, EnterContainer, kind, routeKey)
            end, true)
        -- The Custom Frame Groups twin, run under the group's scope so the
        -- stamp names the custom-frame section and the container is
        -- resolved against the group's own array.
        app:RegisterRouteObserver("customFrames/" .. pattern,
            function(isActive, routeKey)
                if not isActive then
                    LeaveContainer()
                    return
                end
                local scope = BuzzardFramesOptions.CFGScopeFor
                              and BuzzardFramesOptions:CFGScopeFor(SectionOf(kind))
                if scope then
                    BuzzardFramesOptions:WithScope(scope, EnterContainer, kind, routeKey)
                else
                    EnterContainer(kind, routeKey)
                end
            end, true)
    end
end

-- One route per container, then the Add tab. Called while the route tree
-- is DECLARED, so it reads the array as it is now -- and nothing calls it
-- again until the tree is declared again. Adding or removing a container
-- therefore ends with BuzzardFramesOptions:RebuildRoutes, not Invalidate:
-- Invalidate re-indexes the declared tree and recomputes children only for
-- a collection node, so on its own it left a new container with no tab and
-- a removed one with a tab and no container.
-- One container's page, with the remove X on its identity card. `tmpl` is
-- the page builder for the part being drawn (a debuff container's whole
-- page; a buff container's Assigned Spells or Container Settings subtab).
local function ContainerPageWithRemove(kind, key, tmpl)
    local isDebuff = (kind == "debuff")
    return function()
        -- Resolved by KEY on every build: an earlier delete
        -- renumbers the array under us.
        local cc, ii = FindByKey(kind, key)
        if not cc then return { groups = {} } end
        local page = tmpl({ app = App(), item = cc, index = ii, key = key })
        page.groups = page.groups or {}
        -- The Ace corner X, restored: an X on the container's own
        -- card -- in its header row (owner ruling 2026-09-14) -- rather
        -- than on the scope strip above or a Remove Container card at
        -- the foot.
        local first
        for gi = 1, #page.groups do
            if page.groups[gi].bpContainerCard then
                first = page.groups[gi]
                break
            end
        end
        if first then
            local noun = isDebuff and "debuff" or "buff"
            -- In the card's HEADER row, at its right end -- not the body's
            -- corner CardCornerZone answers for a plain header. The group
            -- frame's top-right IS the header's level (the plain heading
            -- sits above the box), so the outer corner, inset a hair and
            -- dropped one pixel to center a 20px X in the 22px header.
            first.attach = first.attach or {}
            first.attach[#first.attach + 1] = {
                id = "bpRemove", zone = "outerTopRight",
                icon = "x", danger = true, x = -2, y = -1, size = 20,
                tooltip = function()
                    local c = FindByKey(kind, key)
                    if not c then return "This container no longer exists." end
                    return (AssignedSpellReport(kind, c))
                        or ("Remove this custom " .. noun .. " container. "
                            .. "Its settings are deleted; the buffs anchored "
                            .. "to it go back to the Buffs row.")
                end,
                disabled = function()
                    local c = FindByKey(kind, key)
                    return InCombatLockdown() or (not c)
                        or (AssignedSpellReport(kind, c) ~= nil)
                end,
                onClick = function(_, ctx)
                    if InCombatLockdown() then return end
                    local c, index = FindByKey(kind, key)
                    if not c or AssignedSpellReport(kind, c) then return end
                    -- Read HERE rather than inside the confirmation: the
                    -- callback runs after the dialog is answered, by which
                    -- point the page that knew which section it was in is
                    -- no longer rendering.
                    local root = SectionRoot()
                    ctx.app:Confirm(
                        "Remove this custom " .. noun .. " container?",
                        function()
                            RemoveContainer(kind, c, index)
                            ctx.app:Navigate(root, SectionOf(kind))
                            -- The declaration has to run again or the tab
                            -- outlives what it was a tab for.
                            BuzzardFramesOptions:RebuildRoutes(ctx.app)
                        end)
                end,
            }
        end
        return page
    end
end

local function ContainerRouteList(kind)
    EnsureContainerObservers()
    local isDebuff = (kind == "debuff")
    local tmpl = ContainerMemberPage(kind)
    local arr  = Containers(kind)
    local out  = {}
    for i = 1, #arr do
        local c = arr[i]
        -- The PARTITION, as the collection had it: entries marked
        -- `singleBuff` belong to the Buff List, not here. Debuff
        -- containers have no single-buff variant.
        if isDebuff or not c.singleBuff then
            local key   = ContainerKeyOf(c, i)
            local index = i
            out[#out + 1] = {
                id    = ContainerRouteId(kind, key),
                title = c.name or ((isDebuff and "Debuff " or "")
                                   .. "Custom " .. tostring(index)),
                -- Resolved at paint time, so a container disabled while
                -- the panel is open dims its own tab. Escape codes never
                -- touch the stored name.
                color = function()
                    local cc = FindByKey(kind, key)
                    if cc and (not cc.singleBuff) and cc.enabled == false then
                        return CONTAINER_BLUE_OFF
                    end
                    return CONTAINER_BLUE
                end,
                page = ContainerPageWithRemove(kind, key, tmpl),
                -- A BUFF container also carries a CHILD collection -- its
                -- Assigned Buffs tree -- so the entries anchored to it have
                -- member routes for the tree card on its page to list. No
                -- `navigator`: the page's own in-page strip is the subtab
                -- row, and this child draws no strip of its own. A member
                -- route shows the container's page (the tree-group rule),
                -- with the selected entry's Buff List pages in the pane.
                --
                -- `descend`: arriving on the container settles into the
                -- tree's FIRST entry (the Buff List's own behavior, where
                -- the collection is the route), so the Assigned Buffs tab
                -- opens with a buff selected rather than with nothing in
                -- the pane. With no entry to select, the library lands on
                -- the container's own page as before. Debuff containers
                -- have no child, so the flag does nothing there.
                descend  = (not isDebuff) or nil,
                children = (not isDebuff) and {
                    { node = "collection",
                      id    = ContainerRouteId(kind, key) .. "_spells",
                      title = "Assigned Buffs",
                      treeGroup = true, railChildren = false,
                      page   = ContainerPageWithRemove(kind, key, tmpl),
                      source = function() return ContainerSpellMembers(kind, key) end,
                      key    = function(item) return item.key end,
                      memberTitle = BuffListMemberTitle,
                      template    = SingleBuffCard,
                      memberTabs  = BuffListMemberTabs,
                      -- The tree row's X does not delete the entry: it
                      -- moves the buff back to the Buffs row (its Anchor
                      -- Point becomes Buffs), which is what takes it out
                      -- of this container.
                      remove = {
                          tooltip = "Move this buff back to the Buffs row",
                          confirm = function(item)
                              return "Move \"" .. ((item.c and item.c.name) or item.key)
                                  .. "\" back to the Buffs row?"
                          end,
                          onRemove = function(item)
                              if InCombatLockdown() then return end
                              local bf = BF()
                              local sb = bf and bf:FindSingleBuffByKey(item.key)
                              if not sb then return end
                              local src = EffectiveSource(sb)
                              src.anchorPoint = "BUFFS"
                              local def = bf.GROW_DEFAULT_FOR_ANCHOR
                                          and bf.GROW_DEFAULT_FOR_ANCHOR.BUFFS
                              if def then src.growDirection = def end
                              bf:RefreshContainersWithRebuildDebounced()
                          end,
                      },
                      emptyText = "|cffaaaaaaNo buffs anchored to this container.|r",
                    },
                } or nil,
            }
        end
    end
    out[#out + 1] = AddContainerNode(kind)
    return out
end

function BuzzardFramesOptions:BuffContainerRoutes()
    return ContainerRouteList("buff")
end

function BuzzardFramesOptions:DebuffContainerRoutes()
    return ContainerRouteList("debuff")
end

-- Kept for reference and for a caller that wants the nested shape: the
-- collection is still the tidier expression of add / remove / reorder,
-- and it is what a region that can host its own strip should use.
function BuzzardFramesOptions:BuffContainersRoute()
    return ContainerCollection("buff", "containers", "Containers")
end

function BuzzardFramesOptions:DebuffContainersRoute()
    return ContainerCollection("debuff", "debuffContainers", "Containers")
end

-- ── The Buff List (Single Buffs) ───────────────────────────────
--
-- The other half of the buff array: every container whose `singleBuff`
-- marker is set. A single buff is an ordinary container with maxBuffs = 1
-- carrying its own spell; the marker only routes where its options render.
--
-- Session-only form state, shared by every surface showing this list --
-- deliberately, because the container array is shared too: a half-typed
-- spell name or a "no spell found" note is about the one creation form, not
-- about the page it was typed on.
local newSingleSpellText = ""
local newSingleSpellMode = "whitelist"
local singleBuffNote     = nil
local singleBuffSearch   = ""
local singleBuffSpecFilter = 0
-- While the user has not picked a filter value themselves this session, the
-- filter FOLLOWS the player's current spec. The first manual pick (including
-- "All") ends the following for the session.
local singleBuffSpecFilterTouched = false
-- Entries CREATED this session are exempt from Filter by Spec until the user
-- changes the filter. A just-added entry must not vanish mid-setup: enabling
-- its Spec condition seeds every spec OFF, which would otherwise stop it
-- matching the active filter the moment the box is ticked. Weak keys, so a
-- deleted entry's table is not pinned by this set.
local singleBuffFilterExempt = setmetatable({}, { __mode = "k" })

-- The player's current spec id, but only if it is listed in the Filter by
-- Spec dropdown; nil otherwise (DPS/tank specs, and pre-login).
local function PlayerListedSpecID()
    local bf  = BF()
    local idx = GetSpecialization and GetSpecialization()
    local id  = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
    if not id then return nil end
    local order = (bf and bf.HEALER_SPEC_ORDER) or {}
    for i = 1, #order do
        if order[i].id == id then return id end
    end
    return nil
end

-- Default Filter by Spec to the player's own spec while the user has not
-- picked a value themselves this session. The Ace tracker ran this at order
-- -100, BEFORE any entry's `hidden` predicate; here the member list is
-- derived when the ROUTES are indexed -- on open, before any page is built
-- or any getter runs -- so the seed has to happen wherever the filter is
-- READ, not only in the dropdown's getter. Every reader below calls this
-- first; it is change-guarded and costs two API calls when it does nothing.
local function SeedSpecFilter()
    if singleBuffSpecFilterTouched then return end
    local pid = PlayerListedSpecID()
    if pid and singleBuffSpecFilter ~= pid then
        singleBuffSpecFilter = pid
    end
end

-- An ENABLED Spec condition CLAIMS the entry for the specs it selects,
-- overriding curated membership in BOTH directions: condition on, the entry
-- shows under exactly the specs the condition has ON; condition off, curated
-- membership decides and an entry in no curated list appears under All only.
local function SingleSpecFilterHides(sid, c)
    local bf = BF()
    local f  = singleBuffSpecFilter
    if not f or f == 0 then return false end
    if type(c) == "table" and singleBuffFilterExempt[c] then return false end
    if not sid then return true end
    if type(c) == "table" and c.loadSpec then
        local t = c.loadSpecTypes
        if t ~= nil then
            -- An enabled Spec condition with NOTHING ticked is an INCOMPLETE
            -- config, not a deliberate scope -- you get it the moment you click
            -- Spec to start setting one up -- so the filter keeps these visible
            -- under every selection. Without this, clicking Spec would hide the
            -- entry being configured.
            if bf and bf.SingleBuffSpecConditionEmpty
               and bf.SingleBuffSpecConditionEmpty(c) then
                return false
            end
            return t[f] == false
        end
        return false  -- condition on, no table: every spec ON (fail-open)
    end
    return not (bf and bf:SingleBuffSpellInSpecList(sid, f))
end

-- PLAIN find, not a pattern match: buff names contain "(", ")", "-" and "%",
-- and a user typing "Power Word: Shield" must not throw a malformed-pattern
-- error out of a `hidden` predicate.
local function SearchHides(hay)
    if singleBuffSearch == "" then return false end
    if not hay then return true end
    return not hay:find(singleBuffSearch, 1, true)
end

-- The entry's Display Type. Mirrors the container fields rather than
-- re-deriving: if the two disagree, an entry sits in a list its own dropdown
-- contradicts.
local function SingleBuffDisplayType(c)
    if not c then return "custom" end
    if c.singleBuffHidden then return "hide" end
    if c.singleBuffCustomized == false then return "default" end
    return "custom"
end

-- The Buff List's members: every single buff in the array, whitelist first
-- then blacklist, each sorted by the PLAIN spell name. Sorting on the
-- rendered label would order by icon path, which is why the Ace loop sorted
-- on c.name and assigned `order` from the sorted position.
function AllSingleBuffRecords()
    local bf = BF()
    if not bf then return {} end
    local arr = Containers("buff")
    local buckets = { [true] = {}, [false] = {} }
    for i = 1, #arr do
        local c = arr[i]
        -- Defensive mint: the key is the entry's identity, so a single buff
        -- without one would be unreachable rather than merely odd. Only ever
        -- fires for a hand-edited SavedVariables.
        if c.singleBuff and c.singleBuffKey == nil and bf.NewSingleBuffKey then
            local sid = bf:GetSingleBuffDisplaySpellID(c)
            if sid then c.singleBuffKey = bf:NewSingleBuffKey(sid) end
        end
        if c.singleBuff and type(c.singleBuffKey) == "string" then
            -- The DISPLAY spell id throughout: a pseudo entry reports no spell
            -- to the aura engine but still has a face spell for its key, icon,
            -- sort name and search haystack.
            local sid  = bf:GetSingleBuffDisplaySpellID(c)
            local name = (c.name or (sid and tostring(sid)) or c.singleBuffKey):lower()
            local rec = {
                c = c, key = c.singleBuffKey, sid = sid, sortName = name,
                -- Name AND spell ID, lowercased once here rather than per entry
                -- per render, so pasting an ID finds the entry that tracks it --
                -- the only way to find one whose name never resolved.
                hay = name .. (sid and (" " .. sid) or ""),
                blacklisted = (c.singleBuffHidden and true) or false,
            }
            local b = buckets[not rec.blacklisted]
            b[#b + 1] = rec
        end
    end
    local out = {}
    for _, on in ipairs({ true, false }) do
        local list = buckets[on]
        table.sort(list, function(x, y)
            if x.sortName ~= y.sortName then return x.sortName < y.sortName end
            return x.key < y.key   -- stable tiebreak; keys are unique
        end)
        for i = 1, #list do out[#out + 1] = list[i] end
    end
    return out
end

-- The collection's own source: the surviving entries.
--
-- The two filters are applied HERE rather than as a per-member `hidden`, so
-- a filtered-out entry has no route at all rather than a route leading to a
-- page nothing lists. Both are AND-ed: an entry has to survive the spec
-- filter AND the search to stay in the list. Both setters end in
-- app:Invalidate, because which members EXIST is structural.
local function SingleBuffMembers()
    SeedSpecFilter()
    local out = {}
    for _, rec in ipairs(AllSingleBuffRecords()) do
        if not (SingleSpecFilterHides(rec.sid, rec.c) or SearchHides(rec.hay)) then
            out[#out + 1] = rec
        end
    end
    return out
end

-- Create one. The whole of the Ace addSingleBuff, minus the deep link (the
-- entry's card appears on this same page, so there is nothing to navigate
-- to) and minus the eager rebuild it needed before SelectGroup.
local function AddSingleBuff(mode)
    if InCombatLockdown() then return nil end
    local bf = BF()
    if not bf then return nil end
    local blacklist = ((mode or newSingleSpellMode) == "blacklist")
    local newIndex, err = bf:CreateSingleBuffContainer(newSingleSpellText, nil, blacklist)
    if not newIndex then
        singleBuffNote = "|cffff8080" .. tostring(err) .. "|r"
        return nil
    end
    newSingleSpellText = ""
    singleBuffNote = nil
    local arr = Containers("buff")
    local c   = arr[newIndex]
    if c then singleBuffFilterExempt[c] = true end
    -- Clear a spec filter that would HIDE what was just added: the entry
    -- exists either way, but landing on a card the user cannot see reads as
    -- "nothing happened". Only when it actually excludes the new spell, so
    -- filtering by Resto Druid and adding a Resto Druid buff keeps the filter.
    if singleBuffSpecFilter and singleBuffSpecFilter ~= 0 then
        -- The DISPLAY spell, which is what the list itself files entries
        -- under -- see AllSingleBuffRecords. Asking the other accessor
        -- answers nil for a pseudo entry, so the filter would be judged
        -- against no spell at all.
        local sid = c and bf.GetSingleBuffDisplaySpellID
                    and bf:GetSingleBuffDisplaySpellID(c)
        if SingleSpecFilterHides(sid, c) then
            singleBuffSpecFilter = 0
            -- Counts as a session choice -- without this the player-spec seed
            -- would re-apply and hide the entry this reset exists to keep
            -- visible.
            singleBuffSpecFilterTouched = true
        end
    end
    -- And the same for the text search, for the same reason: adding
    -- "Rejuvenation" while the box still says "shield" would file the entry
    -- correctly and then hide it, which reads as the add having failed.
    if singleBuffSearch ~= "" then
        -- Built the same way AllSingleBuffRecords builds it, display spell
        -- included: a haystack assembled differently here would say the new
        -- entry survives a filter the list then hides it with.
        local sid = c and bf.GetSingleBuffDisplaySpellID
                    and bf:GetSingleBuffDisplaySpellID(c)
        local hay = ((c and c.name) or (sid and tostring(sid)) or ""):lower()
            .. (sid and (" " .. sid) or "")
        if SearchHides(hay) then singleBuffSearch = "" end
    end
    return c
end

-- One entry's card. The controls the Ace entry kept at its ROOT and on its
-- Display subtab (route id `position`): the spell it tracks, the scope row,
-- the Display picker and
-- Customize Buff switch, Enabled for this Layout, the anchor/offset/order
-- geometry and Icon Size, plus the
-- entry's Conditions. See the notes for the four VISUAL subtabs (Icon, Icon
-- Effects, Cooldown Text, Frame Effects), which are the per-spell
-- customization surface and belong to whoever migrates it.
-- Keep the reader on the entry they just blacklisted (or un-blacklisted).
--
-- The Whitelist and Blacklist headings are REAL ROUTE LEVELS -- an entry's
-- route is ".../singleBuffs/<section>/<key>[/<tab>]" -- so flipping Show Buff
-- moves the entry to a route that did not exist a moment ago and destroys the
-- one the reader is standing on. Left alone, the tree group finds its route
-- gone and falls back to the first row in the list, which is a DIFFERENT
-- buff's settings appearing under a switch the reader just clicked.
--
-- TWO CALLS, in this order, and the split is the whole point:
--
--   * SingleBuffRouteNow() is read BEFORE Invalidate. Invalidate re-indexes
--     the tree and repairs a route that no longer resolves, so by the time it
--     returns app.route has already been moved off this entry -- reading it
--     afterwards is reading the fallback, which is exactly the state being
--     corrected here.
--   * ReselectSingleBuff runs AFTER it, because the route it navigates to is
--     one Invalidate has just minted.
--
-- The subtab is carried across -- the reader was reading a tab, not a page --
-- and dropped only if the flip took that tab away with it (the visual tabs go
-- when a buff is blacklisted).
-- `collId` names the collection the entry is being read under: the Buff
-- List ("singleBuffs", sectioned into Whitelist/Blacklist) or a container's
-- Assigned Spells tree (unsectioned -- <coll>/<key>[/<tab>]).
local function SingleBuffRouteNow(app, key, collId)
    local route = app and app.route
    if not (route and key) then return nil end
    collId = collId or "singleBuffs"
    local sectioned = (collId == "singleBuffs")
    for i = 1, #route do
        if route[i] == collId then
            -- <coll>/<section>/<key>[/<tab>] or <coll>/<key>[/<tab>]: only
            -- a route standing on THIS entry is one to keep.
            local at = sectioned and (i + 2) or (i + 1)
            if route[at] ~= key then return nil end
            local snap = { cut = i, tab = route[at + 1], sectioned = sectioned }
            for j = 1, i do snap[j] = route[j] end
            return snap
        end
    end
    return nil
end

local function ReselectSingleBuff(app, snap, key, blacklisted)
    if not (app and snap and key and app.routeIndex) then return end
    local path = {}
    for i = 1, snap.cut do path[i] = snap[i] end
    if snap.sectioned then path[#path + 1] = blacklisted and "off" or "on" end
    path[#path + 1] = key
    if not app.routeIndex[table.concat(path, "/")] then return end
    if snap.tab then
        path[#path + 1] = snap.tab
        if not app.routeIndex[table.concat(path, "/")] then path[#path] = nil end
    end
    app:Navigate(unpack(path))
end

function SingleBuffCard(mctx)
    local key  = mctx.key
    local item = mctx.item
    -- Which collection this member is drawn under -- the Buff List, or a
    -- container's Assigned Spells tree (Collections.lua stamps it).
    local collId = mctx.collection or "singleBuffs"
    local function getC()
        local bf = BF()
        if not bf then return nil end
        return (bf:FindSingleBuffByKey(key))
    end
    local function scopeKey() return ContainerScopeKey(getC()) end
    local function notCustomized()
        return SingleBuffDisplayType(getC()) ~= "custom"
    end
    -- The flow anchors: each means "flow inside that host's icons" instead of
    -- being positioned independently. X/Y Offset are meaningless in any of
    -- those modes (the host's layout places the icon), so they give way to
    -- Relative Order.
    local function flowAnchored()
        local bf = BF()
        return (bf and bf.IsFlowAnchorValue(AnchorForScope(getC()))) and true or false
    end
    local function notFlowAnchored() return not flowAnchored() end

    local function twoTierGet(name)
        return function() return ScopeField(getC(), name) end
    end
    local function twoTierSet(name)
        return function(_, _, val)
            if InCombatLockdown() then return end
            local c = getC()
            if not c then return end
            EffectiveSource(c)[name] = val
            RefreshContainersLight()
        end
    end

    -- THE ENTRY, DECLARED THE WAY IT IS DRAWN.
    --
    -- `header` is the entry's own cards -- what stays above the tab strip
    -- whichever subtab is showing -- and `position` is the Display tab's,
    -- exactly as the Icon, Icon Effects, Cooldown Text, Frame Effects and
    -- Conditions tabs build their own lists further down. A card belongs to
    -- one or the other because it was WRITTEN into it, which is how the Ace
    -- surface said the same thing: an entry's widgets in its own args, each
    -- subtab's widgets in that subtab's args. There is no flat list and no
    -- split by position, so adding, removing or reordering a card moves
    -- that card and nothing else.
    local header   = {}
    local position = {}

    -- THE PANE'S HEADER: the spell this entry is for, on its own and first,
    -- which is where the Ace entry had it -- above the tab strip, so it
    -- stayed on screen whichever subtab was selected. It was a field inside
    -- the first form card, which put the name below the card's own frame
    -- and level with the Display picker rather than over the whole pane.
    local nameHeader = {
        { control = "note", wide = true, font = "GameFontNormalLarge",
          color = { 1, 1, 1, 1 }, text = function()
            local bf = BF()
            local c  = getC()
            if not (bf and c) then return "|cffaaaaaa(No spell assigned)|r" end

            -- The DISPLAY spell, which is the whole difference for a PSEUDO
            -- entry. GetSingleBuffSpellID answers nil for one on purpose --
            -- that nil is the single choke point keeping a row like
            -- Swiftmendable out of the aura engine -- so asking it here
            -- headed the pane "(No spell assigned)" for an entry that has a
            -- perfectly good face spell and a name of its own.
            local s = bf.GetSingleBuffDisplaySpellID
                      and bf:GetSingleBuffDisplaySpellID(c) or nil

            -- The entry's OWN name first, exactly as the tree row's
            -- memberTitle resolves it: a pseudo row is named for what it
            -- does, not for the spell wearing its icon, and the heading and
            -- the row it was clicked from must not disagree.
            local nm = (c.name ~= nil and tostring(c.name)) or nil
            if not nm then
                nm = s and ((bf.SpellDisplayName and bf.SpellDisplayName(s))
                    or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s))
                    or tostring(s)) or nil
            else
                -- A display-name override wins, but only while the stored
                -- name is still the one the GAME gave us; a name the reader
                -- typed themselves is left alone. memberTitle's rule.
                local ov = s and bf.SPELL_DISPLAY_NAME_OVERRIDES
                           and bf.SPELL_DISPLAY_NAME_OVERRIDES[s]
                if ov then
                    local apiName = C_Spell and C_Spell.GetSpellName
                                    and C_Spell.GetSpellName(s)
                    if nm == apiName or nm == tostring(s) then nm = ov end
                end
            end
            if not nm then return "|cffaaaaaa(No spell assigned)|r" end

            local tex = s and ((bf.CuratedSpellIcon and bf.CuratedSpellIcon(s))
                or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s)))
            local icon = tex and ("|T" .. tex .. ":16:16:0:0|t ") or ""

            -- A pseudo entry wears its own color rather than the plain
            -- white every other heading gets, the same one its tree row and
            -- its Ace entry wore.
            local meta = c.pseudoKind and bf.PSEUDO_ENTRY_SPEC
                         and bf.PSEUDO_ENTRY_SPEC[c.pseudoKind]
            local col  = (meta and meta.color) or "ffffffff"

            return icon .. "|c" .. col .. nm .. "|r"
                .. (s and ("  |cff888888(" .. s .. ")|r") or "")
        end },
    }

    -- WHAT THE ENTRY IS, above the tab strip rather than on Position.
    --
    -- The old single "Display Type" dropdown carried two independent
    -- decisions in one three-way list: whether the buff shows at all, and
    -- whether it uses this entry's own appearance. Split into the two
    -- controls they always were, and moved out of Position -- neither is a
    -- position setting, and the second one decides which subtabs exist, so it
    -- belongs above the strip it changes rather than inside one of its tabs.
    --
    -- BOTH KEYS ARE THE EXISTING ONES: `singleBuffHidden` (Blacklist) and
    -- `singleBuffCustomized` (nil = customized, false = default), so nothing
    -- migrates and SingleBuffDisplayType still answers for the subtab gates.
    -- The card's GATE: whether the buff shows at all. In the header rather
    -- than as a field, for the reason every other master switch in the panel
    -- is -- what is under it only means anything while it is on, and a card
    -- that collapses to its header says that more plainly than a field that
    -- grays out. Off IS the blacklist: it writes the same singleBuffHidden
    -- the old Blacklist option did, so the entry moves to the Blacklist
    -- section of the list.
    local displayToggle = {
        id = "singleBuffShow", default = true,
        tooltip = "Show Buff",
        desc = "When off, this buff never shows and moves to the Blacklist "
            .. "section of the list.",
        get = function() return SingleBuffDisplayType(getC()) ~= "hide" end,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            local bf, c = BF(), getC()
            if not (bf and c) then return end
            c.singleBuffHidden = (not val) or nil
            RefreshContainersHeavy()
            -- This decides which SECTION the entry sits in, so the member
            -- list has to be re-derived: structural, not a value change. The
            -- library re-renders the page itself after a gate flip.
            if ctx and ctx.app then
                -- Snapshot FIRST: Invalidate repairs the route it is about
                -- to invalidate, so app.route is no longer this entry's by
                -- the time it returns.
                local snap = SingleBuffRouteNow(ctx.app, key, collId)
                ctx.app:Invalidate("singleBuffs")
                -- The entry has just changed SECTION, so its route changed
                -- with it. Follow it, or the pane falls back to whichever
                -- entry is now first in the list.
                ReselectSingleBuff(ctx.app, snap, key, not val)
            end
        end,
    }

    local displayFields = {
        { control = "switch", label = "Customize Buff", labelSide = "after",
          desc = "When enabled, this buff also applies the Icon, Icon Effects, "
              .. "Cooldown Text and Frame Effects configured on this entry. "
              .. "When disabled, it shows using the container's own settings "
              .. "only.",
          -- No blacklist gate of its own: the card it sits in collapses to
          -- its header when Show Buff is off, so this is never on screen for
          -- a buff that cannot show.
          id = "singleBuffCustomize", default = true, disabled = "combat",
          get = function()
              local c = getC()
              return (not c) or c.singleBuffCustomized ~= false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              -- An explicit branch, NOT `val and nil or false`: nil vs false
              -- is load-bearing here -- nil is Customized, false is Default.
              if val then
                  c.singleBuffCustomized = nil
              else
                  c.singleBuffCustomized = false
              end
              RefreshContainersHeavy()
              -- The four visual subtabs exist only for a Customized entry, so
              -- the strip itself changes: structural.
              ctx.app:Invalidate("singleBuffs")
              ctx.app:RefreshPage()
          end },
    }

    -- "Enabled for this Layout" stays with Position, as it did in the Ace
    -- entry: it is a per-Layout setting, and settings go below the scope
    -- strip rather than above it.
    local mainFields = {
        -- The shared "Enabled for this Layout" widget, relabeled rather than
        -- redefined: its storage (groupSettings[<scope>].showForGroupType) is
        -- exactly right for a single buff, and only the wording was written
        -- for multi-spell containers. The Layout stays IN the label.
        { control = "switch", label = "Enabled for this Layout",
          labelSide = "after",
          desc = "When disabled, this buff will not appear on frames of the "
              .. "Layout or Custom Frame Group you are currently editing. It "
              .. "stays in the list either way; use Display above to "
              .. "blacklist it everywhere.",
          id = "showForGroupType", default = true, disabled = "combat",
          hidden = function() return scopeKey() == nil end,
          get = function()
              local c = getC()
              local k = c and ContainerScopeKey(c)
              if not k then return true end
              local gs = c.groupSettings and c.groupSettings[k]
              return (not gs) or gs.showForGroupType ~= false
          end,
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              local k = ContainerScopeKey(c)
              if not k then return end
              if not c.groupSettings then c.groupSettings = {} end
              if not c.groupSettings[k] then c.groupSettings[k] = {} end
              c.groupSettings[k].showForGroupType = val
              bf:InvalidateClaimedSpellCache()
              bf:RefreshAllCustomContainers()
              ctx.app:RefreshPage()
          end },
    }

    header[#header + 1] = { preset = "bare", fields = nameHeader }
    -- `flush = 2`: the strip belongs to the name above it. The full gap, on
    -- top of the name card's own bottom pad, left the two reading as
    -- separate sections with a band of nothing between them.
    local scope = ScopeStrip(getC, "buff", "buff")
    scope.flush = 2
    header[#header + 1] = scope

    -- FIRST CARD OF THE DISPLAY TAB: what this entry is, above the position
    -- settings it governs. A card of its own rather than fields inside the
    -- Position card below -- neither control is a position setting, and the
    -- Customize switch decides which of the entry's tabs exist at all.
    position[#position + 1] = { title = "Show Buff", preset = "form",
                                toggle = displayToggle, fields = displayFields }

    -- Hidden while the buff is blacklisted: where an icon that never
    -- renders would sit is not a question, and the card also carries
    -- "Enabled for this Layout" and Order, which are just as moot. The Show
    -- Buff card above stays, so the way back is always on screen.
    position[#position + 1] = { title = "Position", preset = "form",
      hidden = function() return SingleBuffDisplayType(getC()) == "hide" end,
      fields = {
        { control = "dropdown", label = "Anchor Point",
          desc = "Changing the anchor point resets the Grow Direction to that "
              .. "anchor's default.\n\n|cffffd100Buffs|r, |cffffd100Big "
              .. "Defensive|r and each buff container flow this buff inside "
              .. "that display's icons instead of positioning it on its own."
              .. "\n\nA buff anchored to |cffffd100Big Defensive|r renders in "
              .. "ADDITION to Max Defensives -- the same relationship a "
              .. "Buffs-anchored buff has to Max Buffs.\n\nIf the display it is "
              .. "anchored to is hidden or switched off for a Layout, this buff "
              .. "is hidden there too.",
          options = SingleBuffAnchorOptions,
          id = "anchorPoint", disabled = "combat",
          get = twoTierGet("anchorPoint"),
          set = function(_, ctx, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              local s = EffectiveSource(c)
              s.anchorPoint = val
              local def = bf.GROW_DEFAULT_FOR_ANCHOR
                          and bf.GROW_DEFAULT_FOR_ANCHOR[val]
              if def then s.growDirection = def end
              -- For a single buff the anchor is a ROUTING change, not just a
              -- position one: it moves the aura between the entry's own
              -- container and a host row, and that needs the heavy path's
              -- per-frame pool-hide sweep to clear the old container's icons.
              bf:RefreshContainersWithRebuildDebounced()
              -- STRUCTURAL too (2026-09-14): which container's Assigned
              -- Spells tree lists this entry follows its anchor, so the
              -- routes are re-indexed. Read under a container, an entry
              -- anchored elsewhere leaves that tree and the route falls back
              -- to the container's Assigned Spells page.
              ctx.app:Invalidate("singleBuffs")
          end },

        -- Shown only while this entry is anchored to a Big Defensive the
        -- edited Layout has switched off. Anchored entries hide WITH their
        -- host, so this is the difference between "nothing renders" and
        -- "nothing renders and the user cannot see why".
        { control = "note", wide = true,
          text = "|cffff8080Big Defensive is disabled in this Layout, so this "
              .. "buff will not render.|r",
          hidden = function()
              local bf = BF()
              if AnchorForScope(getC()) ~= "BIGDEF" then return true end
              if not (bf and bf.SingleBuffBigDefOffForScope) then return true end
              return not bf.SingleBuffBigDefOffForScope(getC(), ContainerScopeKey)
          end },

        { control = "slider", label = "X Offset", min = -60, max = 60, step = 1,
          id = "offsetX", disabled = "combat", hidden = flowAnchored,
          get = twoTierGet("offsetX"), set = twoTierSet("offsetX") },
        { control = "slider", label = "Y Offset", min = -60, max = 60, step = 1,
          id = "offsetY", disabled = "combat", hidden = flowAnchored,
          get = twoTierGet("offsetY"), set = twoTierSet("offsetY") },

        -- The stored field is host-INDEPENDENT by design: one Before/After per
        -- entry per Layout, whatever the host, which is why it goes through the
        -- same two-tier pair as every other Position field.
        { control = "segmented", label = "Relative Order",
          desc = "Whether this buff flows before or after the icons of the "
              .. "display it is anchored to.",
          options = { { value = "BEFORE", text = "Before" },
                      { value = "AFTER",  text = "After" } },
          id = "sbRelativeOrder", default = "BEFORE", disabled = "combat",
          hidden = notFlowAnchored,
          -- The shared getter returns nil for a field nobody has written, and
          -- a select with a nil value renders blank.
          get = function()
              return ScopeField(getC(), "sbRelativeOrder") or "BEFORE"
          end,
          set = twoTierSet("sbRelativeOrder") },
    }}

    -- The layout switch goes at the TOP of Position rather than in a card
    -- of their own above the strip. Inserted rather than
    -- written into the literal above, so the Position card reads as one
    -- list of position settings and this stays one decision in one place.
    do
        local pos = position[#position]
        for i = #mainFields, 1, -1 do
            table.insert(pos.fields, 1, mainFields[i])
        end
    end

    -- The Order dropdown, beside Relative Order, which is the thing it
    -- controls. NOT a new field: a single buff's Position already lives in
    -- sbVisuals.specSpellOrdering["sb"][sid], the same slot the Icon tab's
    -- Position dropdown wrote before Buzzard Frames relocated it here.
    --
    -- The legacy mirror -- acp.specSpellOrdering[<spec>][sid], the curated
    -- per-spec Position -- is written too, for EXACTLY ONE spec or none:
    -- fanning one entry's Order out across every enabled spec would
    -- silently overwrite the user's curated Position on all of them.
    do
        local pos = position[#position]
        local function displaySid()
            local bf, c = BF(), getC()
            return bf and c and bf.GetSingleBuffDisplaySpellID
                   and bf:GetSingleBuffDisplaySpellID(c) or nil
        end
        local function currentSlot()
            local c   = getC()
            local sid = displaySid()
            local fam = c and c.sbVisuals and c.sbVisuals.specSpellOrdering
            local map = fam and fam["sb"]
            local e   = map and sid and map[sid]
            if e == nil then return 0 end
            if type(e) == "number" then return e end
            if type(e) == "table" then
                if e.enabled == false then return 0 end
                return e.slot or 0
            end
            return 0
        end
        local function mirrorSpec(c)
            local bf = BF()
            if type(c) ~= "table" or not c.loadSpec then return nil end
            local t = c.loadSpecTypes
            if type(t) ~= "table" then return nil end
            local found
            for _, sp in ipairs((bf and bf.HEALER_SPEC_ORDER) or {}) do
                if t[sp.id] ~= false then
                    if found then return nil end
                    found = sp.id
                end
            end
            return found
        end
        pos.fields[#pos.fields + 1] = {
            control = "dropdown", label = "Order",
            desc = "Order relative to other single buffs anchored to the same "
                .. "display on the same side. Buffs that are not active are "
                .. "skipped -- no gap is left.",
            options = { { value = 0, text = "|cffaaaaaaNone|r" },
                        { value = 1, text = "1" }, { value = 2, text = "2" },
                        { value = 3, text = "3" }, { value = 4, text = "4" },
                        { value = 5, text = "5" }, { value = 6, text = "6" },
                        { value = 7, text = "7" }, { value = 8, text = "8" } },
            id = "sbOrder", default = 0, disabled = "combat",
            hidden = notFlowAnchored,
            get = currentSlot,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                local bf, c = BF(), getC()
                local sid = displaySid()
                if not (bf and type(c) == "table" and sid) then return end
                val = tonumber(val) or 0
                -- (a) the entry's own copy, which the group builder reads
                if val == 0 then
                    local fam = c.sbVisuals and c.sbVisuals.specSpellOrdering
                    local map = fam and fam["sb"]
                    if map then map[sid] = nil end
                else
                    if not c.sbVisuals then c.sbVisuals = {} end
                    local fam = c.sbVisuals.specSpellOrdering
                    if not fam then fam = {}; c.sbVisuals.specSpellOrdering = fam end
                    local map = fam["sb"]
                    if not map then map = {}; fam["sb"] = map end
                    local existing = map[sid]
                    if type(existing) == "table" then
                        existing.slot    = val
                        existing.enabled = nil
                    else
                        map[sid] = { slot = val }
                    end
                end
                -- (b) the legacy mirror, single-spec entries only
                local p    = bf.acDB and bf.acDB.profile
                local spec = mirrorSpec(c)
                if p and spec then
                    if val == 0 then
                        local m = p.specSpellOrdering and p.specSpellOrdering[spec]
                        if m then m[sid] = nil end
                    else
                        if not p.specSpellOrdering then p.specSpellOrdering = {} end
                        if not p.specSpellOrdering[spec] then p.specSpellOrdering[spec] = {} end
                        local existing = p.specSpellOrdering[spec][sid]
                        if type(existing) == "table" then
                            existing.slot    = val
                            existing.enabled = nil
                        else
                            p.specSpellOrdering[spec][sid] = { slot = val }
                        end
                    end
                end
                bf:RefreshContainersWithRebuildDebounced()
                ctx.app:RefreshPage()
            end,
        }
    end

    -- Icon Size: a container field, so it is built here, but it sits on the
    -- ICON tab -- size is an appearance property and belongs beside the icon
    -- type, border and color rather than beside anchor and offset.
    local iconSize = { title = "Icon Size", preset = "form", fields = {
        { control = "switch", width = "full", labelSide = "after",
          label = "|cFF87CEEBUse Buffs Icon Size|r",
          desc = "When enabled, this buff inherits its Icon Size from the "
              .. "active Buffs settings. Disable it to give this buff its own.",
          id = "containerUsesBuffSettings", default = true, disabled = "combat",
          get = function()
              return ScopeField(getC(), "containerUsesBuffSettings") ~= false
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf, c = BF(), getC()
              if not (bf and c) then return end
              EffectiveSource(c).containerUsesBuffSettings = val and true or false
              bf:RefreshAllCustomContainers()
          end },
        { control = "slider", label = "Icon Size", min = 2, max = 50, step = 1,
          id = "buffSize", disabled = "combat",
          hidden = function()
              return ScopeField(getC(), "containerUsesBuffSettings") ~= false
          end,
          get = twoTierGet("buffSize"), set = twoTierSet("buffSize") },
    }}

    -- NO Remove BUTTON. The Ace page had removeSingleBuff at the bottom of
    -- the Position tab because that surface had no corner affordance; this
    -- one does, and the X runs the very same path
    -- (ns.collections.Remove, confirmation included). Two controls for one
    -- action is one of them the reader has to rule out, and the button was
    -- the one buried a tab deep.

    -- ── The entry's remaining tabs ─────────────────────────────
    --
    -- The six Ace subtabs are Position | Icon | Icon Effects | Cooldown
    -- Text | Frame Effects | Conditions. Position and Conditions are built
    -- here; the four VISUAL tabs come from Pages_SingleBuffVisuals.lua
    -- against the entry's own sbVisuals store, and exist only for a
    -- Customized entry (see the collection's memberTabs, which is where
    -- the routes are minted and the gates applied).
    local sid = (function()
        local bf, c = BF(), getC()
        return bf and c and bf.GetSingleBuffDisplaySpellID
               and bf:GetSingleBuffDisplaySpellID(c) or nil
    end)()
    local visuals = sid and BuzzardFramesOptions.SingleBuffVisualTabs
                    and BuzzardFramesOptions:SingleBuffVisualTabs(getC, sid)
                    or { icon = {}, iconEffects = {}, cooldownText = {}, frameEffects = {} }
    local iconTab = {}
    for _, g in ipairs(visuals.icon) do iconTab[#iconTab + 1] = g end
    iconTab[#iconTab + 1] = iconSize

    return {
        groups = PushDownGroupHidden(header),
        tabs = {
            position     = { groups = PushDownGroupHidden(position) },
            icon         = { groups = PushDownGroupHidden(iconTab) },
            iconEffects  = { groups = PushDownGroupHidden(visuals.iconEffects) },
            cooldownText = { groups = PushDownGroupHidden(visuals.cooldownText) },
            frameEffects = { groups = PushDownGroupHidden(visuals.frameEffects) },
            -- A spec toggle changes three things and no more: the Specs
            -- card's own switches (they share one state), the read-out in
            -- the heading above it, and this entry's row in the list --
            -- which carries the pinned-spec icon and the "can never show"
            -- mark. Rung 3 for each, so nothing else on the page is
            -- touched and no route is re-indexed.
            conditions   = { groups = PushDownGroupHidden(
                ConditionsCards(getC, "this buff", function(ctx)
                    local app = ctx and ctx.app
                    if not app then return end
                    app:RefreshGroup("bfSpecs")
                    -- The route is on one of the entry's SUBTABS, so the
                    -- row is its parent -- but this is asked of the route
                    -- rather than assumed, so it still works from the
                    -- entry itself.
                    local full = table.concat(app.route or {}, "/")
                    if not app:RefreshRow(full) then
                        app:RefreshRow(full:match("^(.*)/[^/]+$") or full)
                    end
                end)) },
        },
    }
end

-- ── Arrival on the Buff List ───────────────────────────────────
--
-- The Ace subtab carried two invisible tracker widgets: one at the subtab
-- root (_singleBuffTracker) that stamped the section, the sub-category and
-- the "single buffs" sentinel and pointed the dummy-aura preview at the
-- Buff List with the current filter, and one on every entry
-- (_sbPreviewTracker) that told the preview WHICH entry is selected. Both
-- were render hooks; the panel says the same thing with one route
-- observer, fired on entry AND on every route change inside the list, so
-- clicking an entry updates the selection the way the per-entry tracker
-- did. Leaving is handled by whatever is entered instead: the plain aura
-- subtabs and the container pages clear the index and the preview on
-- arrival (Pages_Buffs.lua EnterSubcat and its siblings).
local singleBuffObserverArmed = false

-- The entry the route names, as its singleBuffKey -- the segment after the
-- section: ".../singleBuffs/<on|off>/<key>". nil at the list's root or on
-- a bare section.
--
-- EITHER root, not just the Raid/Party one. The Custom Frame Groups Buff
-- List is the same page under the group's scope, and matching only
-- "raidPartyFrames/..." made the selected entry nil there -- so with
-- Filter by Spec on All the group's Buff List previewed nothing and no
-- entry ever got its frame effects.
local function SelectedSingleBuffKey(routeKey)
    local rest = routeKey and routeKey:match("^[^/]+/aurasBuffs/singleBuffs/(.+)$")
    if not rest then return nil end
    -- "<section>/<key>" or "<section>/<key>/<tab>": the entry's subtabs are
    -- routes under it, and a route on one is a route on the entry.
    local _, key = rest:match("^([^/]+)/([^/]+)")
    return key
end

local function EnterSingleBuffs(routeKey)
    local bf = BF()
    if not bf then return end
    -- A page built under a Custom Frame Group scope reports
    -- "customFrameAuras" instead, exactly as the Ace CFG page's own
    -- _sectionTracker did -- otherwise the preview draws for the raid.
    local section = (bf.BFOSectionName and bf:BFOSectionName()) or "auras"
    bf._currentSection     = section
    bf._buffListSection    = section
    bf._currentAurasSubcat = "buffs"
    -- The sentinel goes in FIRST: the preview's own gate
    -- (_BuffListPreviewActive) requires it, so stamping and repainting
    -- before it is set painted nothing on the first arrival.
    local sentinel = bf.SINGLE_BUFF_SUBTAB_SENTINEL or -1
    local first = bf._currentContainerIndex ~= sentinel
    bf._currentContainerIndex = sentinel
    SeedSpecFilter()
    local sel   = SelectedSingleBuffKey(routeKey)
    local was   = bf.IsPreviewingBuffList and bf:IsPreviewingBuffList() or false
    local prevF = bf.GetBuffListPreviewFilter and bf:GetBuffListPreviewFilter() or nil
    local prevK = bf.GetBuffListPreviewKey and bf:GetBuffListPreviewKey() or nil
    local changed = (not was) or prevF ~= singleBuffSpecFilter or prevK ~= sel
    if bf.SetBuffListPreview then
        bf:SetBuffListPreview(singleBuffSpecFilter, sel)
    end
    -- The repaint is combat-gated like every other one on this surface;
    -- the stamps above are not, so a selection made in combat is already
    -- right for the first refresh after it ends.
    if (changed or first) and not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
        bf:RefreshPreviewDummyAuras()
    end
end

-- Armed the first time the page is built rather than at file scope: the
-- app exists only once the panel has been opened.
local function EnsureSingleBuffObserver()
    if singleBuffObserverArmed then return end
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    local app   = Panel and Panel:GetApp("BuzzardFrames")
    if not app then return end
    singleBuffObserverArmed = true
    -- WithScope(nil, ...): observers fire from the navigation, BEFORE the
    -- render that would rebind the scope, so on a Custom Frame Groups ->
    -- Raid/Party move this body would otherwise run with the group's scope
    -- still bound -- and every stamp it makes is a write through the proxy.
    app:RegisterRouteObserver("raidPartyFrames/aurasBuffs/singleBuffs",
        function(isActive, routeKey)
            if not isActive then return end
            BuzzardFramesOptions:WithScope(nil, EnterSingleBuffs, routeKey)
        end, true)
    -- The Custom Frame Groups twin, run under the group's scope so the
    -- stamp names the custom-frame section and the preview reads the
    -- group's own entries.
    app:RegisterRouteObserver("customFrames/aurasBuffs/singleBuffs",
        function(isActive, routeKey)
            if not isActive then return end
            local scope = BuzzardFramesOptions.CFGScopeFor
                          and BuzzardFramesOptions:CFGScopeFor("aurasBuffs")
            if scope then
                BuzzardFramesOptions:WithScope(scope, EnterSingleBuffs, routeKey)
            else
                EnterSingleBuffs(routeKey)
            end
        end, true)
end

-- The page ABOVE the member cards: the Add form and the two filters.
local function SingleBuffsRootPage()
    -- The observer replaces the Ace render-hook trackers; stamped here as
    -- well, because the first build happens after the navigation that
    -- armed nothing yet.
    EnsureSingleBuffObserver()
    do
        local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
        local app   = Panel and Panel:GetApp("BuzzardFrames")
        local r = app and app.route
        EnterSingleBuffs(type(r) == "table" and table.concat(r, "/") or nil)
    end
    return {
        -- In the page header, above the subtab strip -- where the Ace
        -- section root drew it.
        headerField = BuzzardFramesOptions:AuraPreviewField("aurasBuffs"),
        groups = {
        { title = "Add Buff", preset = "form", fields = {
            { control = "text", label = "Add Spell Name or ID",
              submit = "Add", disabled = "combat",
              suggest = SpellSuggestions,
              -- 30% wider than the text control's natural width. A
              -- MULTIPLE rather than a number: the field is still sized
              -- from the control, so it follows a restyle instead of
              -- pinning a width that was right for one font.
              widthMul = 1.3,
              -- 30% wider than the text control's natural width. A
              -- multiple rather than a number: the field is still sized
              -- FROM the control, so it follows a restyle instead of
              -- pinning a width that was right for one font.
              widthMul = 1.3,
              desc = "Start typing a buff name for suggestions from the curated "
                  .. "buff list, or paste any spell ID.\n\nThe entry is created "
                  .. "as soon as you press Enter.",
              get = function() return newSingleSpellText end,
              set = function(_, ctx, val)
                  newSingleSpellText = tostring(val or "")
                  singleBuffNote = nil
                  -- Empty box + Enter is not an attempt to add anything;
                  -- creating here would only produce a "no spell found" error
                  -- the user did not ask for.
                  if newSingleSpellText:match("^%s*$") then return end
                  ctx.app:CollectionAdd("singleBuffs")
              end },

            -- Read at COMMIT time, not stored per entry: it is a property of
            -- the add form, and each entry's own Display picker owns the
            -- value afterwards.
            { control = "segmented", label = "Mode",
              desc = "Whitelist: show this buff. Blacklist: never show it."
                  .. "\n\nSets the new entry's Display, which you can "
                  .. "change afterwards on the entry itself.",
              options = { { value = "whitelist", text = "Whitelist" },
                          { value = "blacklist", text = "|cffff6666Blacklist|r" } },
              id = "addSingleBuffMode", default = "whitelist", disabled = "combat",
              get = function() return newSingleSpellMode end,
              set = function(_, _, val)
                  newSingleSpellMode = (val == "blacklist") and "blacklist" or "whitelist"
              end },

            { control = "note", wide = true,
              hidden = function() return singleBuffNote == nil end,
              text = function() return singleBuffNote or "" end },

            -- What the list is NOT showing, and why. Counted through the
            -- SAME two predicates the list itself uses, so this cannot
            -- disagree with what is on screen. Nothing is said at all while
            -- the list has entries in it: the list is right there, and
            -- counting it back to the reader is a line they read past.
            { control = "note", wide = true,
              hidden = function()
                  SeedSpecFilter()
                  local members = AllSingleBuffRecords()
                  for i = 1, #members do
                      local m = members[i]
                      if not (SingleSpecFilterHides(m.sid, m.c)
                              or SearchHides(m.hay)) then
                          return true
                      end
                  end
                  return false
              end,
              text = function()
                SeedSpecFilter()
                local members = AllSingleBuffRecords()
                local en, di, total = 0, 0, #members
                for i = 1, #members do
                    local m = members[i]
                    if not (SingleSpecFilterHides(m.sid, m.c) or SearchHides(m.hay)) then
                        if m.blacklisted then di = di + 1 else en = en + 1 end
                    end
                end
                if en + di == 0 then
                    -- "None at all" and "none that pass the filter" are
                    -- different problems with different fixes; saying the first
                    -- when the second is true sends the user off to re-add a
                    -- buff they already have.
                    if total > 0 then
                        -- Name whichever filter is actually doing it: "Set
                        -- Filter by Spec back to All" is unhelpful advice when
                        -- the real culprit is a stale search.
                        local why
                        if singleBuffSearch ~= "" and singleBuffSpecFilter ~= 0 then
                            why = "Filter by Spec and Search"
                        elseif singleBuffSearch ~= "" then
                            why = "Search"
                        else
                            why = "Filter by Spec"
                        end
                        return "|cffaaaaaaNo single buffs match the current "
                            .. why .. ". Clear it to see the other " .. total .. ".|r"
                    end
                    return "|cffaaaaaaNo single buffs yet. Add one using the form "
                        .. "above: a single buff is a container with exactly one "
                        .. "icon, tracking one spell, positioned and sized on its "
                        .. "own.|r"
                end
                -- Reached only while something IS showing, which the
                -- predicate above has already hidden this note for.
                return ""
            end },
        }},

        -- A STRIP, not a card: Filter by Spec and Search act ON the list
        -- below rather than being settings of their own, and the strip is
        -- the panel's word for a row that is about what follows it. The
        -- list card is `flush`, so the two meet with no gap and read as one
        -- surface -- which is what the tab strip and its page do above.
        --
        -- `justify = "start"`, against the strip preset's own `spread`: these
        -- two fields are read left to right as one sentence -- these buffs, of
        -- this spec, matching this text -- so Search follows Filter by Spec at
        -- its own width instead of being pushed to the far edge with the
        -- page's width between them. Every other strip carries a switch and
        -- the things that qualify it, which is what spread is for.
        { preset = "strip", justify = "start", fields = {
            { control = "dropdown", label = "Filter by Spec",
              -- Labeled ABOVE, not beside: the strip's own placement is
              -- inline, which suits a switch and reads as cramped over a
              -- dropdown and a search box.
              labelPlacement = "above",
              desc = "Show only single buffs that belong to that spec: entries "
                  .. "whose own Spec condition selects it, plus condition-less "
                  .. "entries whose spell is in that spec's curated list in Aura "
                  .. "Customizations. A "
                  .. "condition-less entry whose spell is in no curated list "
                  .. "(any spell ID you typed in yourself) appears under All "
                  .. "only.",
              options = function()
                  local bf  = BF()
                  local out = { { value = 0, text = "All" } }
                  local order = (bf and bf.HEALER_SPEC_ORDER) or {}
                  for i = 1, #order do
                      local s = order[i]
                      out[#out + 1] = { value = s.id,
                          text = (bf and bf.SpecFilterLabel and bf.SpecFilterLabel(s))
                                 or s.tabName or s.name or tostring(s.id) }
                  end
                  return out
              end,
              get = function()
                  -- The same seed the member source applies; see
                  -- SeedSpecFilter for why it cannot live only here.
                  SeedSpecFilter()
                  return singleBuffSpecFilter
              end,
              set = function(_, ctx, val)
                  local bf = BF()
                  singleBuffSpecFilter = tonumber(val) or 0
                  -- A manual filter change ends the session exemption for
                  -- entries added this session, and ends the follow-player-spec
                  -- default for the session.
                  wipe(singleBuffFilterExempt)
                  singleBuffSpecFilterTouched = true
                  -- The filter chooses the preview's entry set, so it
                  -- repaints. The SELECTION is kept: the Ace setter passed
                  -- the selected entry's key alongside the new filter.
                  if bf and bf.SetBuffListPreview then
                      local r  = ctx.app.route
                      local rk = type(r) == "table" and table.concat(r, "/") or nil
                      bf:SetBuffListPreview(singleBuffSpecFilter, SelectedSingleBuffKey(rk))
                  end
                  if not InCombatLockdown() and bf and bf.RefreshPreviewDummyAuras then
                      bf:RefreshPreviewDummyAuras()
                  end
                  -- Which cards EXIST just changed, so this is structural.
                  ctx.app:Invalidate("singleBuffs")
                  ctx.app:RefreshPage()
              end },

            { control = "search", label = "Search", clear = true,
              labelPlacement = "above",
              desc = "Show only entries whose spell name or ID contains this "
                  .. "text. Clear the box to show them all again.",
              get = function() return singleBuffSearch end,
              set = function(_, ctx, val)
                  -- Lowercased once, here, so SearchHides can do a plain
                  -- case-insensitive compare against the pre-lowercased
                  -- haystacks without allocating per entry per render.
                  singleBuffSearch = tostring(val or ""):lower():match("^%s*(.-)%s*$")
                  ctx.app:Invalidate("singleBuffs")
                  ctx.app:RefreshPage()
              end },
        }},

        -- The Ace noneNote: shown only while there are no single buffs AT
        -- ALL. "None at all" and "none that pass the filter" are different
        -- problems with different fixes, and the summary line above says the
        -- second one.
        { preset = "bare", fields = {
            { control = "note", wide = true,
              hidden = function() return #AllSingleBuffRecords() > 0 end,
              text = "|cffaaaaaaNothing here yet. Use |r|cffffd100Add Buff|r"
                  .. "|cffaaaaaa above to whitelist a spell -- or blacklist it, "
                  .. "to stop it ever showing. Each entry can also be given its "
                  .. "own position, size and appearance.|r" },
        }},

        -- The list, and whichever entry is selected. Last, so everything
        -- above it -- Add, Search, Filter by Spec -- is what the reader
        -- meets first and what stays put while they move through the list.
        -- `height = "fill"`: the card takes whatever the panel has left
        -- below the cards above it and follows a resize, which is how the
        -- Ace tree group sat -- the list ran to the bottom of the dialog
        -- rather than stopping at a fixed height with the page scrolling
        -- underneath it.
        -- No title. The card is the list, the strip above says what is
        -- being filtered, and a "Buffs" heading on a tab already called
        -- Buff List names it a third time.
        -- `flush = 2`: the list belongs to the strip above it, but a
        -- hairline between them keeps the two surfaces legible as two.
        { preset = "form", flush = 2,
          -- 175 wide: the Ace tree group's default column, which is the
          -- width this list has always been read at.
          -- `listTopPad = 0`: the card's own top pad is all the room the
          -- first row needs, and it is the same pad the pane uses above the
          -- entry's name -- so the two columns start level.
          -- The list the tree draws is THIS section's member routes:
          -- the same collection is spliced under Custom Frame Groups
          -- too, and naming the Raid/Party one there would list the
          -- right entries and navigate out of the section on a click.
          tree = { route = SectionRoot() .. "/aurasBuffs/singleBuffs",
                   width = 175, height = "fill", minHeight = 240,
                   listTopPad = 0 } },
    }}
end

-- The Buff List's row label and its member subtabs, as values: the same
-- two serve a container's Assigned Spells tree (ContainerRouteList), so an
-- entry reads and edits identically from either place.
BuffListMemberTitle = function(item)
            local bf = BF()
            local c  = item.c
            local s  = bf and bf:GetSingleBuffSpellID(c)
            local label = (c and c.name) or (s and tostring(s)) or item.key
            -- A display-name override wins, but only while the stored name is
            -- still the one the GAME gave us; a name the user typed themselves
            -- is left alone.
            local ov = s and bf and bf.SPELL_DISPLAY_NAME_OVERRIDES
                       and bf.SPELL_DISPLAY_NAME_OVERRIDES[s]
            if ov then
                local apiName = C_Spell and C_Spell.GetSpellName
                                and C_Spell.GetSpellName(s)
                if label == apiName or label == tostring(s) then label = ov end
            end
            -- Class-colored, where the curated buff list knows which
            -- class the spell belongs to. With every curated spell in this
            -- tree, color is what makes the list scannable -- and it is
            -- what the Ace rows did. Class-less entries (anything typed in
            -- by ID, and the neutral buffs) keep the default color.
            -- Both icons sit OUTSIDE the color span, so neither is tinted.
            label = (bf.ClassColorSpellName and bf.ClassColorSpellName(s, label))
                    or label
            -- The baked curated icon first: GetSpellTexture is override-
            -- sensitive and changes the row's art with the player's spec.
            local tex = s and bf and ((bf.CuratedSpellIcon and bf.CuratedSpellIcon(s))
                or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s)))
            -- The "!" warning mark: the Spec condition is enabled with nothing
            -- ticked, so the entry can never show in game.
            local warn = (bf and bf.SingleBuffSpecConditionEmpty
                          and bf.SingleBuffSpecConditionEmpty(c))
                and " |TInterface\\GossipFrame\\AvailableQuestIcon:14:14:0:0|t" or ""
            -- When Conditions -> Spec has this buff pinned to exactly ONE spec,
            -- mark it with that spec's icon. Only the single-spec case: two
            -- icons stop being readable and a count would need a legend.
            local pinned = bf and bf.GetSingleEnabledSpec and bf.GetSingleEnabledSpec(c)
            local pinIcon = pinned and pinned.icon and (pinned.icon:gsub("\\", "/"))
            return (pinIcon and ("|T" .. pinIcon .. ":14:14:0:0|t ") or "")
                .. (tex and ("|T" .. tex .. ":14:14:0:0|t ") or "") .. label .. warn
        end

BuffListMemberTabs = (function()
            local function notCustomized(item)
                return SingleBuffDisplayType(item.c) ~= "custom"
            end
            return {
                -- "Display", not "Position": the tab leads with the
                -- Whitelist/Blacklist picker and the Customize switch, which
                -- decide whether the buff shows and which other tabs exist.
                -- The route id stays `position` so saved routes still resolve.
                { id = "position",     title = "Display" },
                { id = "icon",         title = "Icon",         hidden = notCustomized },
                { id = "iconEffects",  title = "Icon Effects", hidden = notCustomized },
                { id = "cooldownText", title = "Cooldown Text",
                  hidden = function(item)
                      if notCustomized(item) then return true end
                      local f = BuzzardFramesOptions.SingleBuffSquareColorByDuration
                      return f and f(item.c, item.sid) or false
                  end },
                { id = "frameEffects", title = "Frame Effects", hidden = notCustomized },
                { id = "conditions",   title = "Conditions" },
            }
        end)()

function BuzzardFramesOptions:SingleBuffsPage()
    return {
        node   = "collection",
        id     = "singleBuffs",
        title  = "Buff List",
        -- A TREE GROUP, the Ace surface's own shape: the page below carries
        -- the Add form and the two filters as ordinary cards, then a tree
        -- card listing every entry with the selected one's settings beside
        -- it. `treeGroup` is what makes a member route show THIS page --
        -- the list has to stay on screen while you read the entry next to
        -- it -- with the member's own cards drawn in the tree's pane.
        --
        -- Inline was the alternative and it does not survive the scale:
        -- inline builds every member's cards on every render, and a seeded
        -- profile has hundreds of entries carrying a dozen controls each,
        -- which froze the client and produced a page too tall to read. A
        -- tree group builds ONE member's cards, the one being read.
        treeGroup = true,
        -- The entries are listed BY THE PAGE, in the tree card. The rail
        -- listing them as well would be the same list twice, one of them
        -- five hundred rows long.
        railChildren = false,
        page   = SingleBuffsRootPage,
        source = SingleBuffMembers,
        key    = function(item) return item.key end,
        memberTitle = BuffListMemberTitle,
        -- The two headings, as real branches in the tree now that the
        -- members are routes: ExpandChildren buckets the members under them
        -- and drops neither, so an emptied list still says which list it is.
        -- Both OPEN by default, as the Ace tree seeded them: a heading
        -- that starts shut hides the very list the tab exists to show. A
        -- collapse the reader does themselves sticks for the session.
        sections = { { id = "on",  title = "Whitelist", showEmpty = true, expanded = true },
                     { id = "off", title = "Blacklist", showEmpty = true, expanded = true } },
        section  = function(item) return item.blacklisted and "off" or "on" end,
        template = SingleBuffCard,
        -- The entry's six subtabs, as the Ace entry had them. Each is a
        -- route under the entry; the pane draws them as a strip under the
        -- entry's header. The four visual tabs exist only for a Customized
        -- entry, and Cooldown Text also goes away while a Square is
        -- colored by remaining time (the duration text IS the square
        -- then). Read here, when the routes are minted: the Display Type
        -- and Icon Type setters Invalidate, so the strip follows them.
        memberTabs = BuffListMemberTabs,
        -- NO emptyText. The library shows it whenever the member list is
        -- empty, and this list empties for TWO different reasons -- nothing
        -- added, or everything filtered out -- which the Ace surface answered
        -- with two different sentences. Both live on the root page instead:
        -- the noneNote below (gated on "are there any at all") and the summary
        -- line, which names whichever filter emptied the list.
        add = {
            -- The new entry is a route of its own, so adding lands on it --
            -- which is what the Ace path did with selectSubtab.
            select = true,
            onAdd  = function(mode) return AddSingleBuff(mode) end,
        },
        remove = {
            confirm = function(item)
                return "Remove \"" .. ((item.c and item.c.name) or item.key) .. "\"?"
            end,
            tooltip = "Remove buff",
            onRemove = function(item)
                if InCombatLockdown() then return end
                local bf = BF()
                if not bf then return end
                local _, gi = bf:FindSingleBuffByKey(item.key)
                if not gi then return end
                bf:RemoveCustomBuffContainer(gi)
                RefreshContainersHeavy()
            end,
        },
        -- NO reorder. The Buff List's order is derived -- whitelist then
        -- blacklist, each alphabetical by spell name -- so there is no stored
        -- position for a drag to write, and dragging would appear to work and
        -- then snap back on the next render.
    }
end

-- ── Buff Preset/Filter (Assigned Spells) ───────────────────────
--
-- The Global Preset that decides which buffs the Buffs display shows, plus
-- one entry per role or spec override. The Ace surface was a tree whose
-- entries were navigable nodes carrying two widgets each; here it is a second
-- INLINE collection, for the same reason the Role/Spec Layouts one is.

-- Roles, in the same fixed order and with the same atlas icons the Role/Spec
-- Layouts surface uses -- this interface is a deliberate copy of that one, so
-- the two must not drift apart visually.
local BUFFS_ROLE_DEFS = {
    { key = "TANK",    label = "Tank",   atlas = "roleicon-tiny-tank"   },
    { key = "HEALER",  label = "Healer", atlas = "roleicon-tiny-healer" },
    { key = "DAMAGER", label = "DPS",    atlas = "roleicon-tiny-dps"    },
}

local function BuffsPresetStore()
    local bf = BF()
    return bf and bf.GetBuffsPresetContainer and bf:GetBuffsPresetContainer()
end

-- Options for every preset dropdown -- the global one and both override ones
-- -- so a preset added to BF.BUFFS_PRESETS appears in all three.
local function PresetOptions()
    local bf = BF()
    local out = {}
    local defs  = (bf and bf.BUFFS_PRESETS) or {}
    local order = (bf and bf.BUFFS_PRESET_ORDER) or {}
    for i = 1, #order do
        local k = order[i]
        if defs[k] then out[#out + 1] = { value = k, text = defs[k].name } end
    end
    return out
end

local function PresetsRefresh(ctx)
    local bf = BF()
    if not bf then return end
    bf:RefreshAllCustomContainersWithRebuild()
    if ctx and ctx.app then ctx.app:RefreshPage() end
end

local function PresetMembers()
    local bf = BF()
    local t  = BuffsPresetStore()
    if not t then return {} end
    local out = {}
    for _, def in ipairs(BUFFS_ROLE_DEFS) do
        local e = t.roleOverrides and t.roleOverrides[def.key]
        if e and e._present then
            local icon = (CreateAtlasMarkup and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
            out[#out + 1] = { kind = "role", entryKey = def.key,
                              id = "role_" .. def.key,
                              title = icon .. " " .. def.label }
        end
    end
    -- Specs sorted by name, after the roles -- visual separation without a
    -- divider, as the Layouts surface does.
    local specList = {}
    for idStr, e in pairs(t.specOverrides or {}) do
        if type(e) == "table" and e._present then
            local s = bf and bf.specByID and bf.specByID[tonumber(idStr)]
            if s then
                specList[#specList + 1] = { idStr = idStr, name = s.name, icon = s.icon }
            end
        end
    end
    table.sort(specList, function(a, b) return a.name < b.name end)
    for _, sp in ipairs(specList) do
        out[#out + 1] = { kind = "spec", entryKey = sp.idStr,
                          id = "spec_" .. sp.idStr,
                          title = "|T" .. sp.icon .. ":14|t " .. sp.name }
    end
    return out
end

local function PresetOverrideCard(mctx)
    local item = mctx.item
    local kind, entryKey = item.kind, item.entryKey
    local function entry()
        local t = BuffsPresetStore()
        local root = t and ((kind == "role") and t.roleOverrides or t.specOverrides)
        return root and root[entryKey] or nil
    end
    -- The override tag rides in the HEADER, as the Ace node's name did
    -- (label .. "    " .. tag), rather than as a note inside the body.
    local title = item.title .. "    "
        .. ((kind == "role") and "|cff7f77ddRole override|r"
                              or  "|cff1d9e75Spec override|r")
    return { groups = {
        { title = title, preset = "form", fields = {
            { control = "dropdown", label = "Preset",
              desc = "The filter to use in this case, instead of the Global "
                  .. "Preset.",
              options = PresetOptions,
              widthMul = 1.56,
              id = "preset_" .. item.id, disabled = "combat",
              get = function()
                  local e = entry()
                  return e and e.preset or nil
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local e = entry()
                  if not e then return end
                  e.preset = val
                  PresetsRefresh(ctx)
              end },

            -- Only meaningful on a role override, and only while the player's
            -- CURRENT spec has an override that would actually beat it -- an
            -- override present and carrying a preset, since one with no preset
            -- falls through in the resolver and takes priority over nothing.
            { control = "note", wide = true,
              text = "Current spec has an override which takes "
                  .. "priority.",
              hidden = function()
                  if kind ~= "role" then return true end
                  local bf = BF()
                  local sid = bf and bf.playerSpecID
                  local t = BuffsPresetStore()
                  local so = t and t.specOverrides
                  if not (sid and so) then return true end
                  local e = so[tostring(sid)]
                  if type(e) == "table" and e._present and e.preset then
                      return false
                  end
                  return true
              end },
        }},
    }}
end

local function PresetsRootPage()
    -- This subtab is one of the Buffs section's, and its arrival stamps
    -- live with the other two in Pages_Buffs.lua. Arming from here as well
    -- covers the panel opening straight onto it, when no Buffs page has
    -- been built to arm them.
    if BuzzardFramesOptions.EnsureBuffsObservers then
        BuzzardFramesOptions:EnsureBuffsObservers()
    end
    return {
        -- In the page header, as on every other subtab of the Buffs
        -- section: above the strip, where the Ace section root drew it.
        headerField = BuzzardFramesOptions:AuraPreviewField("aurasBuffs"),
        groups = {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "The Global Preset decides which buffs the Buffs "
                  .. "display shows. Add a Role or Spec override below to use a "
                  .. "different one in those cases.\n\nWhere a role and a spec "
                  .. "override both apply, the spec override wins." },
        }},

        { title = "Preset", preset = "form", fields = {
            { control = "dropdown", label = "Global Preset",
              desc = "The filter the Buffs display uses when no override "
                  .. "applies.",
              options = PresetOptions,
              widthMul = 1.56,
              id = "buffsGlobalPreset", disabled = "combat",
              get = function()
                  local bf = BF()
                  return (bf and bf.GetBuffsGlobalPreset and bf:GetBuffsGlobalPreset())
                      or (bf and bf.BUFFS_DEFAULT_PRESET)
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local t = BuffsPresetStore()
                  if not t then return end
                  t.globalPreset = val
                  PresetsRefresh(ctx)
              end },

            -- Adding is an ACTION, so the dropdown never shows a current value;
            -- it lists only the roles without an entry yet, in the fixed
            -- Tank -> Healer -> DPS order.
            { control = "dropdown", label = "Add Role Overrides",
              labelPlacement = "above", disabled = "combat",
              options = function()
                  local out = {}
                  local t = BuffsPresetStore()
                  local ro = (t and t.roleOverrides) or {}
                  for _, def in ipairs(BUFFS_ROLE_DEFS) do
                      if not (ro[def.key] and ro[def.key]._present) then
                          local icon = (CreateAtlasMarkup
                              and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
                          out[#out + 1] = { value = def.key,
                                            text = icon .. " " .. def.label }
                      end
                  end
                  return out
              end,
              get = function() return nil end,
              set = function(_, ctx, val)
                  ctx.app:CollectionAdd("buffsAssigned", "role", val)
              end },

            { control = "dropdown", label = "Add Spec Overrides",
              labelPlacement = "above", widthMul = 1.2, disabled = "combat",
              options = function()
                  local bf = BF()
                  local out, list = {}, {}
                  local t = BuffsPresetStore()
                  local so = (t and t.specOverrides) or {}
                  for _, s in ipairs((bf and bf.specData) or {}) do
                      local idStr = tostring(s.id)
                      local e = so[idStr]
                      if not (type(e) == "table" and e._present) then
                          list[#list + 1] = { id = idStr, name = s.name, icon = s.icon }
                      end
                  end
                  table.sort(list, function(a, b) return a.name < b.name end)
                  for _, e in ipairs(list) do
                      out[#out + 1] = { value = e.id,
                          text = "|T" .. e.icon .. ":14|t " .. e.name }
                  end
                  return out
              end,
              get = function() return nil end,
              set = function(_, ctx, val)
                  ctx.app:CollectionAdd("buffsAssigned", "spec", val)
              end },

            -- Buffs' Global Options, which the Ace builder relocated onto this
            -- subtab at rebuild time so it matched Debuffs -- whose own global
            -- group has always sat on its Preset/Filter subtab. Flattened,
            -- because it held exactly one widget. The wrapper's
            -- `hidden = buffsHidden` is deliberately NOT carried across: Show
            -- Buffs is on the Buffs tab, so gating this on it would make the
            -- control disappear from a page that cannot explain why.
            --
            -- STORAGE IS DELIBERATELY UNCHANGED: acDB.profile.showRaidBuffs,
            -- read straight rather than through the aura routing, which would
            -- silently relocate the value away from the key every runtime
            -- reader already uses. One consequence of keeping that storage: the
            -- rest of this surface can be per-Layout and this cannot -- it is
            -- one value for the whole profile, which is what the note says.
            { control = "switch", label = "Show Raid Buff Out of Combat",
              labelSide = "after",
              desc = "Show raid buffs (Mark of the Wild, Arcane Intellect, "
                  .. "Battle Shout, Power Word: Fortitude, Blessing of the "
                  .. "Bronze, etc.) in the Buffs display when out of combat."
                  .. "\n\n|cffaaaaaaApplies to every Layout in this profile, not "
                  .. "just the one you are editing.|r",
              id = "showRaidBuffs", disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.acDB and bf.acDB.profile.showRaidBuffs
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not (bf and bf.acDB) then return end
                  bf.acDB.profile.showRaidBuffs = val
                  bf:RefreshAllCustomContainersWithRebuild()
              end },
        }},
    }}
end

function BuzzardFramesOptions:AssignedSpellsPage()
    return {
        node   = "collection",
        id     = "buffsAssigned",
        title  = "Buff Preset/Filter",
        inline = true,
        page   = PresetsRootPage,
        source = PresetMembers,
        key    = function(item) return item.id end,
        memberTitle = function(item) return item.title end,
        template    = PresetOverrideCard,
        emptyText   = "|cffaaaaaaNo role or spec overrides yet. Every case uses "
            .. "the Global Preset above.|r",
        add = {
            select = false,
            onAdd  = function(kind, val)
                if InCombatLockdown() then return nil end
                local t = BuffsPresetStore()
                if not (t and val) then return nil end
                local root
                if kind == "role" then
                    t.roleOverrides = t.roleOverrides or {}
                    root = t.roleOverrides
                else
                    t.specOverrides = t.specOverrides or {}
                    root = t.specOverrides
                end
                root[val] = root[val] or {}
                -- `_present` marks "exists in the UI", separately from having a
                -- value: an override with no preset chosen yet falls through in
                -- the resolver, so adding one changes nothing until it is
                -- configured.
                root[val]._present = true
                local bf = BF()
                if bf then bf:RefreshAllCustomContainersWithRebuild() end
                return { kind = kind, entryKey = val, id = kind .. "_" .. val }
            end,
        },
        remove = {
            confirm = function(item)
                return "Remove this " .. item.kind .. " override? It will go "
                    .. "back to using the Global Preset."
            end,
            onRemove = function(item)
                if InCombatLockdown() then return end
                local t = BuffsPresetStore()
                if not t then return end
                local root = (item.kind == "role") and t.roleOverrides
                                                   or  t.specOverrides
                if root then root[item.entryKey] = nil end
                local bf = BF()
                if bf then bf:RefreshAllCustomContainersWithRebuild() end
            end,
        },
    }
end
