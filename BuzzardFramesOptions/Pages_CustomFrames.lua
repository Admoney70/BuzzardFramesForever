-- ============================================================
-- BuzzardFramesOptions: Pages_CustomFrames.lua
-- The three Custom Frame Groups pages that are NOT a Raid/Party page
-- under a scope:
--
--   * the section ROOT -- the description and the master switch
--     (Options_CustomFrames.lua:1833-1861);
--   * "Custom Frame Groups" -- add, remove, rename and the unit filters
--     (buildCustomFrameGroupOptions, :256-1161);
--   * "Frames - Size & Position" (:1313-1568), which is half its own and
--     half the Raid/Party Size and Scale cards: those two bind exactly the
--     keys a custom frame group stores on its own flat, so they are
--     REUSED rather than restated.
--
-- Everything else in the section is a Raid/Party page builder rendered
-- under the custom frame group scope -- see Pages_CustomFrameSections.lua.
--
-- SECURE HEADER CONSTRAINT, as the Ace file records it: the name list is
-- mutually exclusive with the role and group filters, because combining
-- them would need an insecure header. Role and group filters CAN be
-- combined (strictFiltering on the secure header template handles that
-- natively). The Filter Mode dropdown is what enforces it.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- Through the panel's scope accessor, not straight to the global: the
-- Frames - Size & Position page below is rendered under a custom frame
-- group scope and asks the proxy which flat it is editing.
local function BF() return BuzzardFramesOptions:BF() end

-- The CFG grid fallbacks (what a nil maxColumns / unitsPerColumn means),
-- from the main addon's BF:GetCFGGridDims. Asked rather than copied: the
-- render path, the setup preview and these steppers disagreeing about the
-- default is exactly the bug this replaced -- the block rendered on 8
-- columns while the stepper said 4.
local function GridDims(sorting)
    local bf = BF()
    if not (bf and bf.GetCFGGridDims) then return nil end
    return bf:GetCFGGridDims(sorting)
end

-- ── The groups ─────────────────────────────────────────────────

local function CFGProfile()
    local bf = BF()
    return bf and bf.cfgDB and bf.cfgDB.profile or nil
end

local function Groups()
    local p = CFGProfile()
    if not p then return {} end
    p.customFrameGroups = p.customFrameGroups or {}
    return p.customFrameGroups
end

-- Each custom frame group's flat carries a stable ID so it can be named
-- after a delete or a reorder. Minted here for a group that predates the
-- scheme, exactly as newCFGFlatID did.
local function NewCFGFlatID()
    local used = {}
    for _, grp in ipairs(Groups()) do
        if grp and grp.flat and grp.flat.cfgFlatID then
            used[grp.flat.cfgFlatID] = true
        end
    end
    local i = 1
    while used["cfg_flat_" .. i] do i = i + 1 end
    return "cfg_flat_" .. i
end

local function EnsureCFGFlatIDs()
    for _, grp in ipairs(Groups()) do
        if grp and grp.flat and not grp.flat.cfgFlatID then
            grp.flat.cfgFlatID = NewCFGFlatID()
        end
    end
end

-- The group a member route names. Resolved BY KEY on every access rather
-- than by the index the template was built with: an earlier delete
-- renumbers the array under us, and a page still holding the old index
-- would edit its neighbor without saying so.
local function ByKey(flatID)
    local list = Groups()
    for i = 1, #list do
        local g = list[i]
        if g and g.flat and g.flat.cfgFlatID == flatID then return g, i end
    end
    return nil, nil
end

-- ── The two refresh paths ──────────────────────────────────────
--
-- Lightweight (visual settings: size, spacing, scale, grow direction) and
-- full (structural: add, remove, enable, filters, visibility). Ports of
-- RefreshCustomFrames and ReloadCustomFrames, guards included.

local function RefreshCustomFrames()
    local bf = BF()
    if not bf then return end
    if InCombatLockdown() then return end
    if bf.RefreshCustomFrameHeaders then bf:RefreshCustomFrameHeaders() end
    if bf.UpdateCustomFrameTestFrames then bf:UpdateCustomFrameTestFrames() end
end

local function ReloadCustomFrames()
    local bf = BF()
    if not bf then return end
    if InCombatLockdown() then return end
    if bf.ReloadCustomFrameHeadersOnly then
        bf:ReloadCustomFrameHeadersOnly()
    elseif bf.ReloadLayout then
        bf:ReloadLayout(true)
    end
    if bf.UpdateCustomFrameTestFrames then bf:UpdateCustomFrameTestFrames() end
end

-- ── The source layouts a new group is seeded from ──────────────

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts
            and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Raid flats only: a custom frame group is a raid-shaped block, and the
-- Ace dropdown never offered a party flat as a seed.
local function RaidFlatIDs()
    local fl = FlatLayouts()
    local ids = {}
    for id, flat in pairs(fl) do
        if type(flat) == "table" and flat.type ~= "party" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        return ((fl[a].name or a):lower()) < ((fl[b].name or b):lower())
    end)
    return ids
end

local function DefaultSourceID()
    return RaidFlatIDs()[1]
end

-- Raid layouts first, then the existing custom frame groups in tab order:
-- a new group can be seeded from another one.
local function SourceOptions()
    EnsureCFGFlatIDs()
    local fl  = FlatLayouts()
    local out = {}
    for _, id in ipairs(RaidFlatIDs()) do
        out[#out + 1] = { value = id, text = fl[id].name or id }
    end
    for i, grp in ipairs(Groups()) do
        if grp and grp.flat and grp.flat.cfgFlatID then
            out[#out + 1] = {
                value = grp.flat.cfgFlatID,
                text  = "Custom Frame Group: "
                        .. (grp.flat.name or grp.name or ("Group " .. i)),
            }
        end
    end
    return out
end

local function SourceFlat(flatID)
    if not flatID then return nil end
    if flatID:match("^cfg_flat_") then
        local g = ByKey(flatID)
        return g and g.flat or nil
    end
    return FlatLayouts()[flatID]
end

-- ── Add a group ────────────────────────────────────────────────
--
-- Options_CustomFrames.lua:1584-1764, step for step and in the same order:
-- deep-copy the seed flat, replace the sections whose per-Layout toggle is
-- OFF with the current globals (so the new group starts with what the user
-- can actually see), reseed the aura sub-categories the same way ONE AT A
-- TIME, name it, re-wire the metatables DeepCopy stripped, force cast bars
-- off, then save an initial position so the sliders have a value at once.
--
-- No override flags are seeded, and that is a deliberate choice rather
-- than a default by omission: a new group starts SHARED, reading every
-- section from the active Layout until the reader ticks the Override
-- toggle on the page they want to diverge.
local function AddGroup()
    local bf = BF()
    if not bf then return nil end
    if InCombatLockdown() then return nil end
    local cfgp = CFGProfile()
    if not cfgp then return nil end
    local list = Groups()

    local baseID   = cfgp.cfgBaseLayoutID or DefaultSourceID()
    local baseFlat = SourceFlat(baseID)

    local flat
    if baseFlat then
        flat = bf:DeepCopy(baseFlat)
        local globalP = bf.rpDB and bf.rpDB.profile
        if globalP then
            for _, entry in ipairs(bf.CFG_OVERRIDABLE_SECTIONS or {}) do
                local sec = entry.section
                if not bf:IsPerLayoutSection(sec) and globalP[sec] then
                    flat[sec] = bf:DeepCopy(globalP[sec])
                end
            end
            if globalP.auras then
                for subcat in pairs(bf.AURAS_SUBCAT_GROUP or {}) do
                    if not bf:IsPerLayoutAurasSubcat(subcat)
                       and type(globalP.auras[subcat]) == "table" then
                        -- rawget, NOT flat.auras: were the fallback
                        -- metatables ever wired before this point, plain
                        -- indexing would resolve to the SHARED global auras
                        -- table and these copies would be written into it,
                        -- corrupting every layout.
                        local fa = rawget(flat, "auras")
                        if type(fa) ~= "table" then
                            fa = {}
                            flat.auras = fa
                        end
                        fa[subcat] = bf:DeepCopy(globalP.auras[subcat])
                    end
                end
            end
        end
    else
        flat = { type = "raid", anchorX = -260, anchorY = -200 }
    end

    -- "Group N", where N is one past the highest existing one.
    local maxN = 0
    for _, g in ipairs(list) do
        if g and g.name then
            local n = g.name:match("^Group (%d+)$")
            if n and tonumber(n) > maxN then maxN = tonumber(n) end
        end
    end
    local groupName = "Group " .. (maxN + 1)
    flat.name      = groupName
    flat.type      = "raid"
    flat.cfgFlatID = NewCFGFlatID()
    if flat.anchorX == nil then flat.anchorX = -260 end
    if flat.anchorY == nil then flat.anchorY = -200 end
    if flat.raidLayoutAnchor == nil then flat.raidLayoutAnchor = "TOPLEFT" end
    if not flat.sorting then flat.sorting = {} end
    -- Seeded from the shared fallback, so a new group starts on the same
    -- number the render path and the preview assume.
    if not flat.sorting.maxColumns then
        flat.sorting.maxColumns = GridDims(nil)
    end
    if not flat.auras then flat.auras = {} end

    bf:WireFlatDefaults(flat)
    for _, sec in ipairs(bf._perLayoutSections or {}) do
        bf:WireSectionFallback(flat, sec)
    end
    if type(rawget(flat, "auras")) == "table" then
        bf:WireAurasSubCategoryFallbacks(flat.auras)
    end

    -- Cast bars: a new group always seeds with cast bars OFF (owner rule
    -- 2026-08-13). The deep copy above may have carried enabled = true --
    -- dormant until something makes it live -- so the rawkey is forced now.
    do
        local cb = rawget(flat, "castBar")
        if type(cb) ~= "table" then
            cb = {}
            flat.castBar = cb
        end
        cb.enabled = false
        bf:WireSectionFallback(flat, "castBar")
    end

    local newGroup = {
        name               = groupName,
        enabled            = true,
        nameListEnabled    = false,
        roleFilterEnabled  = false,
        roleFilter         = {},
        groupFilterEnabled = false,
        groupFilter        = {},
        classFilterEnabled = false,
        classFilter        = {},
        nameList           = "",
        enableKeybindAdd   = false,
        flat               = flat,
    }
    table.insert(list, newGroup)

    -- The same fallback ReloadCustomFrameHeadersOnly uses when a group has
    -- no saved position: CENTER + (200, 100 - (n-1) * 60).
    local gi = #list
    cfgp.customFrameGroupPositions = cfgp.customFrameGroupPositions or {}
    cfgp.customFrameGroupPositions["customFrame_" .. gi] =
        { flat.raidLayoutAnchor or "TOPLEFT", 200, 100 - (gi - 1) * 60 }

    ReloadCustomFrames()
    return flat.cfgFlatID
end

-- ── Remove a group ─────────────────────────────────────────────
--
-- The position store is keyed POSITIONALLY ("customFrame_N"), so removing
-- a group has to shift every key above it down or each surviving group
-- inherits its neighbor's position. Same for the setup-mode test header
-- pool, which the addon keeps in step with the array itself.
local function RemoveGroup(index)
    local bf = BF()
    if not bf then return end
    if InCombatLockdown() then return end
    local list = Groups()
    local cfgp = CFGProfile()
    if cfgp and cfgp.customFrameGroupPositions then
        local pos = cfgp.customFrameGroupPositions
        pos["customFrame_" .. index] = nil
        for j = index + 1, #list do
            pos["customFrame_" .. (j - 1)] = pos["customFrame_" .. j]
            pos["customFrame_" .. j] = nil
        end
    end
    if bf.RemoveCustomFrameTestHeader then
        bf:RemoveCustomFrameTestHeader(index)
    end
    table.remove(list, index)
    ReloadCustomFrames()
end

-- ── The header row both the root and every group page carry ───
--
-- The Ace Groups tree entry put the seed dropdown and the Add button above
-- its tab strip, so they showed on every group's tab. That is the page
-- header here -- `headerFields`, drawn under the breadcrumb and above the
-- strip -- declared by the collection's own page AND by each member's, so
-- the row is there whichever of them is on screen. (Until 2026-09-13 it
-- was a card at the top of each page, under the tabs it belonged above.)
local function AddHeaderRows()
    return { {
        { control = "dropdown", label = "Initial Source Layout",
          width = 170, disabled = "combat",
          desc = "New custom frame groups are seeded from this layout. All "
              .. "settings (size, auras, text, borders and the rest) are "
              .. "copied at creation time.",
          options = SourceOptions,
          get = function()
              local cfgp = CFGProfile()
              if not cfgp then return nil end
              local id = cfgp.cfgBaseLayoutID
              if id and SourceFlat(id) then return id end
              local def = DefaultSourceID()
              cfgp.cfgBaseLayoutID = def
              return def
          end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local cfgp = CFGProfile()
              if cfgp then cfgp.cfgBaseLayoutID = v end
          end },

        { control = "button", text = "Add Custom Frame Group",
          confirm = true, disabled = "combat",
          desc = "Create a new custom frame group, seeded from the layout "
              .. "chosen beside this button.",
          onClick = function(_, ctx)
              local key = AddGroup()
              if not key then return end
              BuzzardFramesOptions:CFGSelectByFlatID(key)
              -- Structural: a new member means a new route. The FIRST
              -- group is structural one level up as well: the section
              -- pages (Frames, Buffs, Debuffs and the rest) are not
              -- emitted while there is no group to configure
              -- (CustomFramesRoutes), so the tree is re-declared the way
              -- the master switch re-declares it.
              if #Groups() == 1 then
                  BuzzardFramesOptions:RebuildRoutes(ctx.app)
              end
              ctx.app:Invalidate()
              -- Deferred for the same reason the Ace add deferred its
              -- SelectGroup: navigating re-renders synchronously and would
              -- release the very button that was clicked.
              C_Timer.After(0, function()
                  ctx.app:Navigate("customFrames", "groups", key)
              end)
          end },
    } }
end

-- ── One group's cards ──────────────────────────────────────────

local ROLE_ORDER = {
    { key = "MAINTANK",   label = "Main Tank",   width = 0.6,
      desc = "Show units assigned as Main Tank (manual raid assignment)." },
    { key = "MAINASSIST", label = "Main Assist", width = 0.6,
      desc = "Show units assigned as Main Assist (manual raid assignment)." },
    { key = "TANK",       label = "Tank"    },
    { key = "HEALER",     label = "Healer"  },
    { key = "DAMAGER",    label = "DPS"     },
}

-- Class-colored, from the client's own table, exactly as the Ace name
-- callback colored it. Falls back to the plain display name where the
-- table is not there.
local function ClassLabel(token)
    local bf = BF()
    local display = (bf and bf.CLASS_DISPLAY_NAMES
                     and bf.CLASS_DISPLAY_NAMES[token]) or token
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if cc then
        return string.format("|cff%02x%02x%02x%s|r",
            cc.r * 255, cc.g * 255, cc.b * 255, display)
    end
    return display
end

-- Cards go into SLOTS rather than being appended, so this page reads in
-- the Ace page's own order however the code below happens to build them.
-- The bracketed numbers are Ace's `order` values
-- (Options_CustomFrames.lua): Visibility is 55, i.e. second to last, just
-- above Manage -- not first, which is where an append order put it.
-- 2026-09-14 (owner ruling): the group's own card -- Enable, its name, and
-- the remove X in its header -- leads the page, above Unit Filters, where
-- Ace's Manage card sat last.
local SLOT = {
    manage      = 1,    -- Custom Frame Group         (was Manage, 100)
    filters     = 2,    -- Unit Filters               (10 - 12)
    filterBy    = 3,    -- Filter By                  (13)
    roles       = 4,    -- Role Filter                (20)
    classes     = 5,    -- Class Filter               (25)
    raidGroups  = 6,    -- Group Filter               (30)
    sorting     = 7,    -- Sorting                    (40)
    nameList    = 8,    -- Name List Filter           (50 - 53)
    keybind     = 9,    -- Mouseover Keybind          (53.2)
    nameSorting = 10,   -- Sorting, name-list mode    (53.5 - 53.6)
    grow        = 11,   -- Grow Direction             (54)
    columns     = 12,   -- Layout                     (54.5)
    visibility  = 13,   -- Show Custom Frame Group    (55)
}

local function GroupCards(flatID)
    local function G() return (ByKey(flatID)) end
    local function Index() local _, i = ByKey(flatID); return i end
    local function Flat() local g = G(); return g and g.flat or nil end
    local function Sorting()
        local f = Flat()
        return f and f.sorting or nil
    end

    local function isNameList()
        local g = G()
        return (g and g.nameListEnabled) == true
    end
    local function isRoleGroup() return not isNameList() end

    -- The plain "read a key, write a key and reload" pair every filter
    -- toggle on this page uses.
    local function Get(key, fallback)
        return function()
            local g = G()
            if not g then return fallback end
            local v = g[key]
            if v == nil then return fallback end
            return v
        end
    end
    local function Set(key, heavy)
        return function(_, _, v)
            if InCombatLockdown() then return end
            local g = G()
            if not g then return end
            g[key] = v
            if heavy then ReloadCustomFrames() else RefreshCustomFrames() end
        end
    end

    -- The saved position is recomputed when the grow direction changes, so
    -- the block does not jump: read the NEW corner off the anchor frame --
    -- whose full-grid rect is stable, unlike the secure header's, which
    -- tracks its children -- and store it. Called BEFORE the config change,
    -- while the frame still reflects the old layout.
    local function RecalcPosition(newLA)
        local bf  = BF()
        local idx = Index()
        if not (bf and idx and bf.GetOrCreateCFGAnchorFrame) then return end
        local af = bf:GetOrCreateCFGAnchorFrame(idx)
        if not af or not af:GetLeft() then return end
        local ux, uy = UIParent:GetCenter()
        if not (ux and uy) then return end
        local newX = newLA:find("LEFT") and af:GetLeft() or af:GetRight()
        local newY = newLA:find("TOP")  and af:GetTop()  or af:GetBottom()
        if not (newX and newY) then return end
        local cfgp = CFGProfile()
        if not cfgp then return end
        cfgp.customFrameGroupPositions = cfgp.customFrameGroupPositions or {}
        cfgp.customFrameGroupPositions["customFrame_" .. idx] = {
            newLA,
            math.floor(newX - ux + 0.5),
            math.floor(newY - uy + 0.5),
        }
    end

    local function GrowIsHorizontal()
        local s = Sorting()
        local d = s and s.raidGrowDirection
        return d == "RIGHT" or d == "LEFT"
    end

    local cards = {}

    -- ── Visibility ────────────────────────────────────────────
    cards[SLOT.visibility] = { title = "Show Custom Frame Group", preset = "form",
        reorderable = false, fields = {
        { control = "switch", label = "Show Solo", id = "showSolo",
          default = true, disabled = "combat",
          desc = "Show this custom frame group when solo.",
          get = function() local g = G(); return not g or g.showSolo ~= false end,
          set = Set("showSolo", true) },
        { control = "switch", label = "Show in Party", id = "showInParty",
          default = true, disabled = "combat",
          desc = "Show this custom frame group when in a party.",
          get = function() local g = G(); return not g or g.showInParty ~= false end,
          set = Set("showInParty", true) },
        { control = "switch", label = "Show in Raid", id = "showInRaid",
          default = true, disabled = "combat",
          desc = "Show this custom frame group when in a raid.",
          get = function() local g = G(); return not g or g.showInRaid ~= false end,
          set = Set("showInRaid", true) },
    }}

    -- ── Unit Filters ──────────────────────────────────────────
    cards[SLOT.filters] = { title = "Unit Filters", preset = "form",
        reorderable = false, fields = {
        { control = "note", wide = true,
          text = "Choose a filter mode. Role and Group filters can be "
              .. "combined, but Name List filtering is a separate mode and "
              .. "cannot be used with Role or Group filters." },
        { control = "dropdown", label = "Filter Mode", id = "filterMode",
          labelPlacement = "above", default = "rolegroup", disabled = "combat",
          desc = "|cff00ff00Role / Group|r -- filter by assigned role and/or "
              .. "raid group number; these can be combined and a unit must "
              .. "match both.\n\n|cff00ff00Name List|r -- show only specific "
              .. "players by name. Cannot be combined with Role or Group "
              .. "filters.",
          options = {
              { value = "rolegroup", text = "Role / Group Filter" },
              { value = "namelist",  text = "Name List Filter"    },
          },
          get = function() return isNameList() and "namelist" or "rolegroup" end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              if v == "namelist" then
                  g.nameListEnabled = true
                  -- Mutually exclusive: the secure header cannot express
                  -- a name list combined with role or group filters.
                  g.roleFilterEnabled  = false
                  g.groupFilterEnabled = false
              else
                  g.nameListEnabled = false
              end
              ReloadCustomFrames()
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
        { control = "switch", label = "Exclude Self (Party/Solo Only)",
          id = "excludePlayer", default = false, disabled = "combat",
          -- NO `width` override, deliberately: `width = "full"` gave a 28px
          -- toggle the whole row and so pushed it under the Filter Mode
          -- dropdown. Left to measure itself it packs onto the SAME line as
          -- that dropdown, which is stretchy and takes the leftover width.
          labelSide = "after",
          desc = "When enabled, your own character will not appear in this "
              .. "custom frame group when in a party or solo.",
          hidden = isNameList,
          get = Get("excludePlayer", false),
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.excludePlayer = v or nil
              ReloadCustomFrames()
          end },
    }}

    -- ── Filter By ─────────────────────────────────────────────
    cards[SLOT.filterBy] = { title = "Filter By", preset = "form",
        reorderable = false, hidden = isNameList, fields = {
        { control = "switch", label = "Role", id = "roleFilterEnabled",
          default = false, disabled = "combat",
          desc = "When enabled, only units matching the selected roles will "
              .. "be shown.",
          get = Get("roleFilterEnabled", false),
          set = function(_, ctx, v)
              Set("roleFilterEnabled", true)(nil, ctx, v)
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
        { control = "switch", label = "Class", id = "classFilterEnabled",
          default = false, disabled = "combat",
          desc = "When enabled, only units of the selected classes will be "
              .. "shown.",
          get = Get("classFilterEnabled", false),
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.classFilterEnabled = v
              -- Turning the category off clears its picks, so it cannot
              -- come back carrying a selection the reader has forgotten.
              if not v and g.classFilter then table.wipe(g.classFilter) end
              ReloadCustomFrames()
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
        { control = "switch", label = "Raid Group", id = "groupFilterEnabled",
          default = false, disabled = "combat",
          desc = "When enabled, only units in the selected raid groups will "
              .. "be shown.",
          get = Get("groupFilterEnabled", false),
          set = function(_, ctx, v)
              Set("groupFilterEnabled", true)(nil, ctx, v)
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
    }}

    -- ── Role Filter ───────────────────────────────────────────
    do
        local fields = {}
        for _, r in ipairs(ROLE_ORDER) do
            local token = r.key
            fields[#fields + 1] = {
                control = "switch", label = r.label,
                id = "roleFilter_" .. token, default = false,
                disabled = "combat", desc = r.desc,
                get = function()
                    local g = G()
                    return (g and g.roleFilter and g.roleFilter[token]) or false
                end,
                set = function(_, ctx, v)
                    if InCombatLockdown() then return end
                    local g = G()
                    if not g then return end
                    g.roleFilter = g.roleFilter or {}
                    g.roleFilter[token] = v or nil
                    ReloadCustomFrames()
                    -- The class list narrows to the classes that can hold
                    -- the roles now selected, so the card below re-lays out.
                    if ctx and ctx.app then ctx.app:RefreshPage() end
                end,
            }
        end
        cards[SLOT.roles] = { title = "Role Filter", preset = "form",
            reorderable = false, fields = fields,
            hidden = function()
                if isNameList() then return true end
                local g = G()
                return not (g and g.roleFilterEnabled)
            end }
    end

    -- ── Class Filter ──────────────────────────────────────────
    --
    -- The list narrows to the classes eligible for the SPEC roles that are
    -- checked. Main Tank and Main Assist are raid assignments any class can
    -- hold, so either of those showing leaves the full list.
    do
        local bf = BF()
        local fields = {}
        for _, cls in ipairs((bf and bf.CLASS_SORT_ORDER_ALPHA) or {}) do
            local token = cls
            fields[#fields + 1] = {
                control = "switch", label = ClassLabel(token),
                id = "classFilter_" .. token, default = false,
                disabled = "combat",
                hidden = function()
                    local g = G()
                    if not g then return true end
                    if g.roleFilterEnabled and g.roleFilter then
                        local rf = g.roleFilter
                        if rf.MAINTANK or rf.MAINASSIST then return false end
                        local b  = BF()
                        local anySpecRole, eligible = false, false
                        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                            if rf[role] then
                                anySpecRole = true
                                local rc = b and b.ROLE_CLASSES
                                           and b.ROLE_CLASSES[role]
                                if rc and rc[token] then eligible = true end
                            end
                        end
                        if anySpecRole then return not eligible end
                    end
                    return false
                end,
                get = function()
                    local g = G()
                    return (g and g.classFilter and g.classFilter[token]) or false
                end,
                set = function(_, _, v)
                    if InCombatLockdown() then return end
                    local g = G()
                    if not g then return end
                    g.classFilter = g.classFilter or {}
                    g.classFilter[token] = v or nil
                    ReloadCustomFrames()
                end,
            }
        end
        cards[SLOT.classes] = { title = "Class Filter", preset = "form",
            reorderable = false, fields = fields,
            hidden = function()
                if isNameList() then return true end
                local g = G()
                return not (g and g.classFilterEnabled)
            end }
    end

    -- ── Group Filter ──────────────────────────────────────────
    do
        local fields = {}
        for i = 1, 8 do
            local n = i
            fields[n] = {
                control = "switch", label = "Group " .. n,
                id = "groupFilter_" .. n, default = false, disabled = "combat",
                get = function()
                    local g = G()
                    return (g and g.groupFilter and g.groupFilter[n]) or false
                end,
                set = function(_, _, v)
                    if InCombatLockdown() then return end
                    local g = G()
                    if not g then return end
                    g.groupFilter = g.groupFilter or {}
                    g.groupFilter[n] = v or nil
                    ReloadCustomFrames()
                end,
            }
        end
        cards[SLOT.raidGroups] = { title = "Group Filter", preset = "form",
            reorderable = false, fields = fields,
            hidden = function()
                if isNameList() then return true end
                local g = G()
                return not (g and g.groupFilterEnabled)
            end }
    end

    -- ── Name List ─────────────────────────────────────────────
    cards[SLOT.nameList] = { title = "Name List Filter", preset = "form",
        reorderable = false, hidden = isRoleGroup, fields = {
        { control = "note", wide = true,
          text = "Enter player names separated by commas. Only players whose "
              .. "names appear in this list will be shown. Names are "
              .. "case-sensitive and should match the in-game character name "
              .. "exactly." },
        -- Ace: multiline = 5 with its Accept button under the box. A list
        -- of names is a paragraph, not a line: the multi-line shape wraps,
        -- scrolls, and puts the button in a row of its own beneath.
        { control = "text", label = "Player Names", id = "nameList",
          wide = true, multiline = 5, clear = true, submit = "Accept",
          disabled = "combat",
          desc = "Enter player names separated by commas.",
          get = function()
              local g = G()
              if not (g and g.nameList) then return "" end
              return (g.nameList:gsub(",", ", "))
          end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              -- Split on newline, comma or semicolon; trim; rejoin. The
              -- stored form is always comma-separated with no spaces.
              local names = {}
              for name in tostring(v or ""):gmatch("[^,;\n]+") do
                  name = strtrim(name)
                  if name ~= "" then names[#names + 1] = name end
              end
              g.nameList = table.concat(names, ",")
              ReloadCustomFrames()
          end },
        -- 2026-09-14 (owner ruling): the Clear Name List button is gone --
        -- the field's own X (`clear`) empties and commits the list.
    }}

    -- ── Mouseover keybind (name list mode only) ───────────────
    -- 2026-09-14 (owner ruling): the Enable switch is the card's own
    -- header gate, and the binding is the library's keybind control -- a
    -- press-a-key button, as the Ace widget was -- rather than a typed
    -- string.
    cards[SLOT.keybind] = { title = "Enable Mouseover Keybind", preset = "form",
        reorderable = false, hidden = isRoleGroup,
        toggle = { id = "enableKeybindAdd", default = false, disabled = "combat",
            desc = "When enabled, you can press a keybind while mousing over a "
                .. "player to add or remove them from this group's name list.",
            get = Get("enableKeybindAdd", false),
            set = Set("enableKeybindAdd", true) },
        fields = {
        { control = "keybind", label = "Add/Remove Name Keybind",
          id = "toggleNameKey", disabled = "combat",
          desc = "Click, then press the key to bind. Pressing it while mousing "
              .. "over a player adds them to the name list; pressing it again "
              .. "over them removes them. Escape clears the binding.",
          get = function() local g = G(); return (g and g.toggleNameKey) or "" end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              v = strtrim(tostring(v or "")):upper()
              g.toggleNameKey = (v ~= "") and v or nil
              ReloadCustomFrames()
          end },
    }}

    -- ── Sorting (role/group mode) ─────────────────────────────
    cards[SLOT.sorting] = { title = "Sorting", preset = "form",
        reorderable = false, hidden = isNameList, fields = {
        { control = "dropdown", label = "Group By", id = "groupBy",
          labelPlacement = "above", default = "NONE", disabled = "combat",
          desc = "Pre-sort units into visual sub-groups within this custom "
              .. "frame group.",
          options = {
              { value = "NONE",         text = "None"       },
              { value = "GROUP",        text = "Raid Group" },
              { value = "ASSIGNEDROLE", text = "Role"       },
              { value = "CLASS",        text = "Class"      },
          },
          get = function() local g = G(); return (g and g.groupBy) or "NONE" end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.groupBy = (v ~= "NONE") and v or nil
              ReloadCustomFrames()
          end },
        { control = "dropdown", label = "Sort Method", id = "sortMethod",
          labelPlacement = "above", default = "INDEX", disabled = "combat",
          desc = "How units are sorted within each sub-group, or overall when "
              .. "Group By is None.",
          options = {
              { value = "INDEX", text = "Index (default)" },
              { value = "NAME",  text = "Name"            },
          },
          get = function() local g = G(); return (g and g.sortMethod) or "INDEX" end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.sortMethod = (v ~= "INDEX") and v or nil
              ReloadCustomFrames()
          end },
    }}

    -- ── Sort By (name list mode) ──────────────────────────────
    cards[SLOT.nameSorting] = { title = "Sorting", preset = "form",
        reorderable = false, hidden = isRoleGroup, fields = {
        { control = "dropdown", label = "Sort By", id = "nameListGroupBy",
          labelPlacement = "above", default = "NONE", disabled = "combat",
          desc = "|cff00ff00Name List Order|r -- display in the order names "
              .. "were entered.\n|cff00ff00Class|r -- group units by class.",
          options = {
              { value = "NONE",  text = "Name List Order" },
              { value = "CLASS", text = "Class"           },
          },
          get = function()
              local g = G()
              return (g and g.nameListGroupBy) or "NONE"
          end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.nameListGroupBy = (v ~= "NONE") and v or nil
              RefreshCustomFrames()
          end },
    }}

    -- ── Grow Direction ────────────────────────────────────────
    cards[SLOT.grow] = { title = "Grow Direction", preset = "form",
        reorderable = false, fields = {
        { control = "dropdown", label = "Grow Direction",
          id = "raidGrowDirection", labelPlacement = "above",
          default = "DOWN", disabled = "combat",
          desc = "Which direction frames grow from the anchor point.",
          options = {
              { value = "DOWN",  text = "Down (vertical)"    },
              { value = "UP",    text = "Up (vertical)"      },
              { value = "RIGHT", text = "Right (horizontal)" },
              { value = "LEFT",  text = "Left (horizontal)"  },
          },
          get = function()
              local s = Sorting()
              local d = s and s.raidGrowDirection
              if d == "RIGHT" or d == "UP" or d == "LEFT" then return d end
              return "DOWN"
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf, flat = BF(), Flat()
              if not (bf and flat) then return end
              flat.sorting = flat.sorting or {}
              local s = flat.sorting
              local oldDir = s.raidGrowDirection or "DOWN"
              local oldH = (oldDir == "RIGHT" or oldDir == "LEFT")
              local newH = (v == "RIGHT" or v == "LEFT")
              local newSec = s.raidSecondaryGrowDirection
              -- Crossing the axis invalidates the secondary direction:
              -- "Down, then Right" has no meaning once the primary is
              -- horizontal, so it reverts to that axis's own default.
              if oldH ~= newH then newSec = nil end
              if not newSec then newSec = newH and "DOWN" or "RIGHT" end
              local newLA = bf:DeriveGroupAnchor(v, newSec)
              RecalcPosition(newLA)
              if oldH ~= newH then s.raidSecondaryGrowDirection = nil end
              s.raidGrowDirection = v
              flat.raidLayoutAnchor = newLA
              RefreshCustomFrames()
              -- The secondary dropdown beside this one now offers a
              -- different pair of values.
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
        { control = "dropdown", label = "Secondary Grow Direction",
          id = "raidSecondaryGrowDirection", labelPlacement = "above",
          disabled = "combat",
          desc = "Which direction columns or rows extend perpendicular to "
              .. "the primary grow direction.",
          options = function()
              if GrowIsHorizontal() then
                  return { { value = "DOWN",  text = "Down"  },
                           { value = "UP",    text = "Up"    } }
              end
              return { { value = "RIGHT", text = "Right" },
                       { value = "LEFT",  text = "Left"  } }
          end,
          get = function()
              local s = Sorting()
              local horiz = GrowIsHorizontal()
              local sec = s and s.raidSecondaryGrowDirection
              -- A stale cross-axis value is not in the option list and
              -- would render the dropdown blank, so it falls back to the
              -- axis-appropriate default rather than being shown.
              if sec then
                  if horiz then
                      if sec == "DOWN" or sec == "UP" then return sec end
                  else
                      if sec == "RIGHT" or sec == "LEFT" then return sec end
                  end
              end
              return horiz and "DOWN" or "RIGHT"
          end,
          set = function(_, _, v)
              if InCombatLockdown() then return end
              local bf, flat = BF(), Flat()
              if not (bf and flat) then return end
              flat.sorting = flat.sorting or {}
              local s = flat.sorting
              local dir = s.raidGrowDirection or "DOWN"
              local isDefault =
                  ((dir == "RIGHT" or dir == "LEFT") and v == "DOWN")
                  or ((dir == "DOWN" or dir == "UP") and v == "RIGHT")
              local secVal = (not isDefault) and v or nil
              local newLA = bf:DeriveGroupAnchor(dir, secVal)
              RecalcPosition(newLA)
              s.raidSecondaryGrowDirection = secVal
              flat.raidLayoutAnchor = newLA
              RefreshCustomFrames()
          end },
    }}

    -- ── Columns ───────────────────────────────────────────────
    --
    -- One setting, two labels: the Ace widget's name swapped Column for
    -- Row with the grow direction, and a panel label is a string -- so it
    -- is two fields over one stored key with complementary predicates,
    -- which is how the aura pages express the same swap.
    do
        local function Cols(label, horiz)
            return {
                control = "stepper", label = label, id = "cfMaxColumns",
                min = 1, max = 40, step = 1, default = GridDims(nil),
                disabled = "combat",
                desc = "Maximum number of columns (vertical) or rows "
                    .. "(horizontal) to display. Held to whatever it takes to "
                    .. "show 40 units at the current Units per Column -- a raid "
                    .. "cannot field more than that, and every slot in the grid "
                    .. "is a frame that gets built.",
                hidden = function() return GrowIsHorizontal() ~= horiz end,
                get = function()
                    local maxCols = GridDims(Sorting())
                    return maxCols
                end,
                set = function(_, _, v)
                    if InCombatLockdown() then return end
                    local bf, flat = BF(), Flat()
                    if not (bf and flat) then return end
                    flat.sorting = flat.sorting or {}
                    -- The stepper still travels its whole range; the VALUE is
                    -- what is held to the unit ceiling.
                    local _, upc = GridDims(flat.sorting)
                    flat.sorting.maxColumns = math.min(v, bf:GetGridMaxColumns(upc))
                    RefreshCustomFrames()
                end,
            }
        end
        local function PerCol(label, horiz)
            return {
                control = "stepper", label = label, id = "cfUnitsPerColumn",
                min = 1, max = 40, step = 1, default = select(2, GridDims(nil)),
                disabled = "combat",
                desc = "Units per column (vertical) or per row (horizontal).",
                hidden = function() return GrowIsHorizontal() ~= horiz end,
                get = function()
                    local _, upc = GridDims(Sorting())
                    return upc
                end,
                set = function(_, _, v)
                    if InCombatLockdown() then return end
                    local flat = Flat()
                    if not flat then return end
                    flat.sorting = flat.sorting or {}
                    flat.sorting.unitsPerColumn = v
                    -- A wider column means fewer of them fit under the unit
                    -- ceiling, so bring a now-too-large stored value down with
                    -- it rather than leaving the panel showing one number and
                    -- the grid built on another.
                    local bf = BF()
                    local cap = bf and bf:GetGridMaxColumns(v)
                    if cap and (flat.sorting.maxColumns or 0) > cap then
                        flat.sorting.maxColumns = cap
                    end
                    RefreshCustomFrames()
                end,
            }
        end
        -- Units per Column first: the Max below is derived from it (see
        -- BF:GetGridMaxColumns), so the reader sets the row width and then
        -- how many rows of it to show.
        cards[SLOT.columns] = { title = "Layout", preset = "form",
            reorderable = false, fields = {
            PerCol("Units per Column",  false),
            PerCol("Units per Row",     true),
            Cols("Max Columns to Show", false),
            Cols("Max Rows to Show",    true),
        }}
    end

    -- ── Manage ────────────────────────────────────────────────
    --
    -- The Ace page hid these behind a "[+] Manage" execute, which is an
    -- affordance for a flat list of widgets rather than a setting. A card
    -- already separates them, so the collapse goes and the three controls
    -- are simply the last card on the page.
    cards[SLOT.manage] = { title = "Custom Frame Group",
        preset = "form", reorderable = false, fields = {
        { control = "switch", label = "Enable", id = "cfgEnabled",
          default = true, disabled = "combat", labelSide = "after",
          desc = "Enable or disable this custom frame group.",
          get = function() local g = G(); return not g or g.enabled ~= false end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g = G()
              if not g then return end
              g.enabled = v
              ReloadCustomFrames()
              -- The tab's own label carries "(Disabled)".
              ctx.app:Invalidate()
          end },
        { control = "text", label = "Custom Frame Group Name",
          id = "cfgName", submit = "Rename", submitOnDirty = true, disabled = "combat",
          desc = "The name shown on this group's tab and in every group "
              .. "selector.",
          get = function() local g = G(); return (g and g.name) or "" end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g, i = ByKey(flatID)
              if not g then return end
              v = strtrim(tostring(v or ""))
              g.name = (v ~= "") and v or ("Group " .. (i or 1))
              -- The flat carries the name too: it is what the Copy
              -- dropdowns and the source-layout list read.
              if g.flat then g.flat.name = g.name end
              -- Structural: the member's route title is the name.
              ctx.app:Invalidate()
          end },
        },
        -- The remove X, in the card's header row at its right end -- the
        -- container cards' shape (Pages_AuraContainers.lua) -- in place of
        -- the Remove button the card used to end with.
        attach = { {
            id = "bpRemove", zone = "outerTopRight",
            icon = "x", danger = true, x = -2, y = -1, size = 20,
            tooltip = "Delete this custom frame group and everything "
                .. "configured on it.",
            disabled = function() return InCombatLockdown() end,
            onClick = function(_, ctx)
                if InCombatLockdown() then return end
                local _, i = ByKey(flatID)
                if not i then return end
                ctx.app:Confirm("Remove this custom frame group?", function()
                    RemoveGroup(i)
                    -- The selection is panel-wide and this ID no longer names
                    -- anything, so it falls back to the first group; saying so
                    -- outright beats leaving a dangling key behind.
                    BuzzardFramesOptions:CFGSelectGroup(1)
                    -- Removing the LAST group takes the section pages
                    -- away with it (CustomFramesRoutes emits them only
                    -- while a group exists), so the tree is re-declared
                    -- before navigating to the collection's own page.
                    if #Groups() == 0 then
                        BuzzardFramesOptions:RebuildRoutes(ctx.app)
                    end
                    ctx.app:Navigate("customFrames", "groups")
                    ctx.app:Invalidate()
                end)
            end,
        } },
    }

    return cards
end

-- ── The "Custom Frame Groups" collection ───────────────────────

-- The collection's own page: with `descend` on the route (below) it is on
-- screen only while there are no groups, so it says so -- as a STRIP, the
-- same card CFGChromeCard draws on a section page, rather than a bare
-- note that reads as a line with text under it.
local function GroupsRootPage()
    EnsureCFGFlatIDs()
    local groups = {}
    groups[#groups + 1] = { preset = "strip", reorderable = false, fields = {
        { control = "note", wide = true,
          text = "No custom frame groups yet. Add one using the button above.",
          hidden = function() return #Groups() > 0 end },
        { control = "note", wide = true,
          text = "Pick a group from the strip above to configure it.",
          hidden = function() return #Groups() == 0 end },
    }}
    return { headerFields = AddHeaderRows(), groups = groups }
end

local function GroupMemberPage(ctx)
    local flatID = ctx and ctx.key
    local groups = {}
    for _, card in ipairs(GroupCards(flatID)) do
        groups[#groups + 1] = card
    end
    return { headerFields = AddHeaderRows(), groups = groups }
end

function BuzzardFramesOptions:CustomFrameGroupsRoute()
    return {
        node   = "collection",
        id     = "groups",
        title  = "Custom Frame Groups",
        -- The Ace entry was childGroups = "tab": one tab per group, with
        -- the seed dropdown and the Add button above the strip -- and it
        -- opened on the FIRST tab. `descend` is that: arriving here lands
        -- on the first group, and the collection's own page shows only
        -- while there is no group to land on.
        navigator = "tabs",
        railChildren = false,
        descend = true,
        page   = GroupsRootPage,
        source = function()
            EnsureCFGFlatIDs()
            return Groups()
        end,
        key    = function(item)
            return item and item.flat and item.flat.cfgFlatID or nil
        end,
        memberTitle = function(item)
            local label = (item and item.name) or "Group"
            if item and item.enabled == false then
                label = "|cff888888" .. label .. " (Disabled)|r"
            end
            return label
        end,
        template = GroupMemberPage,
        -- NO `remove` block, and that is the point rather than an omission:
        -- the library's corner X attaches to the FIRST card of the member's
        -- page, and an X on a filter card that removes the whole group is
        -- not what the reader expects. Declaring nothing leaves the Remove
        -- button in the Manage card, which is the Ace affordance, as the
        -- only way out.
        emptyText = "No custom frame groups yet. Add one using the button above.",
    }
end

-- ── Frames - Size & Position ───────────────────────────────────
--
-- Half its own and half Raid/Party. The Position card writes
-- cfgDB.profile.customFrameGroupPositions (a different store from the
-- Raid/Party anchorX/anchorY on the flat, with different setters), and
-- useActiveLayoutSize is custom-frame-only -- but Frame Size and Frame
-- Scale bind exactly the keys this page writes on cf.flat, so the two
-- Raid/Party cards are reused rather than restated.

-- The flat, wearing the shape the library binds into. Reads and writes
-- resolve through the SCOPE, so the two reused cards land on the selected
-- group's flat without a word of change to them.
local CFG_FLAT_ROOT = setmetatable({}, {
    __index = function(_, k)
        local bf = BF()
        local f  = bf and bf.BFOScopeFlat and bf:BFOScopeFlat()
        return f and f[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        local f  = bf and bf.BFOScopeFlat and bf:BFOScopeFlat()
        if not f then return end
        f[k] = v
        if bf.InvalidateRaidProfileCache then bf:InvalidateRaidProfileCache() end
    end,
})

-- What a key resets TO: the flat's own WireFlatDefaults template, which is
-- what an untouched key already reads through -- so reset and read cannot
-- give two answers.
local function CFGFlatDefaults()
    local bf = BF()
    local f  = bf and bf.BFOScopeFlat and bf:BFOScopeFlat()
    local mt = f and getmetatable(f)
    return mt and mt.__index or nil
end

-- The saved position for the selected group. Keyed positionally, as the
-- runtime keys it.
local function PositionEntry(create)
    local cfgp = CFGProfile()
    local idx  = BuzzardFramesOptions:CFGSelectedIndex()
    if not (cfgp and idx) then return nil end
    cfgp.customFrameGroupPositions = cfgp.customFrameGroupPositions or {}
    local key = "customFrame_" .. idx
    local pos = cfgp.customFrameGroupPositions[key]
    if not pos and create then
        local g = BuzzardFramesOptions:CFGSelectedGroup()
        local anchor = (g and g.flat and g.flat.raidLayoutAnchor) or "TOPLEFT"
        pos = { anchor, 0, 0 }
        cfgp.customFrameGroupPositions[key] = pos
    end
    return pos, key
end

-- Move what is already on screen: the live header if the group has one,
-- and the setup-mode test header either way.
local function MoveHeaders(posKey)
    local bf = BF()
    if not bf then return end
    for _, header in ipairs(bf.groupsUsed or {}) do
        if header.isCustomFrame and header.headerPosKey == posKey then
            if bf.RestoreDetachedHeaderPosition then
                bf:RestoreDetachedHeaderPosition(header)
            end
            break
        end
    end
    if bf.RestoreCustomFrameTestHeaderPosition then
        bf:RestoreCustomFrameTestHeaderPosition(
            BuzzardFramesOptions:CFGSelectedIndex())
    end
end

-- The Ace sliders carried softMin/softMax re-derived from the live screen
-- on every get, because resolutions change mid-session. Same bounds here,
-- seeded when the field is built and re-derived on every get.
local function PositionSlider(label, slot, id, desc)
    local bf   = BF()
    local half = 1024
    if bf then
        half = (slot == 2) and bf:GetPositionHalfW() or bf:GetPositionHalfH()
    end
    return {
        control = "slider", label = label, id = id,
        min = -half, max = half, step = 1, default = 0,
        disabled = "combat", desc = desc, refresh = "mouseup",
        get = function(node)
            local b = BF()
            if b then
                local h = (slot == 2) and b:GetPositionHalfW()
                                       or b:GetPositionHalfH()
                node.min, node.max = -h, h
            end
            local pos = PositionEntry(false)
            return (pos and pos[slot]) or 0
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local pos, key = PositionEntry(true)
            if not pos then return end
            pos[slot] = math.floor(v + 0.5)
            MoveHeaders(key)
        end,
    }
end

function BuzzardFramesOptions:CFGFramesSizePosPage()
    local function noGroups() return #Groups() == 0 end
    local function usingActiveLayout()
        local g = self:CFGSelectedGroup()
        return (g and g.useActiveLayoutSize) == true
    end

    local groups = {}

    groups[#groups + 1] = { title = "Frame Position", preset = "form",
        hidden = noGroups, fields = {
        PositionSlider("X Position", 2, "cfAnchorX",
            "Horizontal position of this custom frame group, relative to "
            .. "the center of the screen."),
        PositionSlider("Y Position", 3, "cfAnchorY",
            "Vertical position of this custom frame group, relative to the "
            .. "center of the screen."),
    }}

    groups[#groups + 1] = { preset = "bare", hidden = noGroups, fields = {
        { control = "switch", width = "full", labelSide = "after",
          label = "Use Active Raid/Party Layout's Size & Spacing",
          id = "useActiveLayoutSize", default = false, disabled = "combat",
          desc = "When enabled, this custom frame group uses the same frame "
              .. "size, spacing and scale as the currently active raid or "
              .. "party layout instead of its own settings.",
          get = function() return usingActiveLayout() end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local g = self:CFGSelectedGroup()
              if not g then return end
              g.useActiveLayoutSize = v
              RefreshCustomFrames()
              -- The two cards below appear or go with it.
              if ctx and ctx.app then ctx.app:RefreshPage() end
          end },
    }}

    -- The Raid/Party cards, reused verbatim. Their binds resolve against
    -- this page's db -- the selected group's flat -- so they need no
    -- change; the gate below is the Ace hidden on sizeGroup / spacingGroup
    -- / scaleGroup, which the assembler chains its own onto.
    local function sizeGate() return noGroups() or usingActiveLayout() end
    if self.FramesSizeCard then
        local card = self:FramesSizeCard()
        card.hidden = sizeGate
        groups[#groups + 1] = card
    end
    if self.FramesScaleCard then
        local card = self:FramesScaleCard()
        card.hidden = sizeGate
        groups[#groups + 1] = card
    end

    return {
        db       = function() return CFG_FLAT_ROOT end,
        defaults = CFGFlatDefaults,
        groups   = groups,
    }
end

-- ── The section root ───────────────────────────────────────────

function BuzzardFramesOptions:CustomFramesRootPage()
    -- One GATED card. The master switch is what the card is about, so it
    -- belongs in the header rather than as a field under the text that
    -- explains it, and the title says what the switch does.
    --
    -- `dims = true` because the usual gated card -- collapse to the
    -- header -- would take the explanation away with it, and this body is
    -- nothing BUT the explanation. Off, the note stays readable at 0.4
    -- alpha; the library disables every field in a dimmed card, so
    -- nothing here is live while it is grayed.
    return { groups = {
        { title = "Enable Custom Frame Groups", preset = "form",
          reorderable = false,
          toggle = {
              id = "customFramesEnabled", default = true, dims = true,
              disabled = "combat",
              tooltip = "Enable Custom Frame Groups",
              desc = "Master toggle for all custom frame groups. When "
                  .. "disabled, no custom frame headers are created.",
              get = function()
                  local p = CFGProfile()
                  return not p or p.customFramesEnabled ~= false
              end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  local p = CFGProfile()
                  if not p then return end
                  p.customFramesEnabled = v
                  ReloadCustomFrames()
                  -- STRUCTURAL, exactly as the Ace tree hid every child
                  -- while this was off: the section's children are not
                  -- emitted at all, so the tree is re-declared rather than
                  -- the page re-rendered. SetRoutes re-points an orphaned
                  -- route at the first section, so turning this off from a
                  -- page that is about to vanish lands somewhere real.
                  if ctx and ctx.app then
                      BuzzardFramesOptions:RebuildRoutes(ctx.app)
                  end
              end,
          },
          fields = {
            { control = "note", wide = true,
              text = "|cff11ace9Custom Frame Groups|r can be used to show "
                  .. "frames for specific groups of units.\n\n"
                  .. "For example, to show frames for |cff76CC4BMain Tank|r "
                  .. "and |cff76CC4BMain Assist|r in a raid:\n\n"
                  .. "1. Add a Custom Frame Group.\n\n"
                  .. "2. Select |cff76CC4BRole/Group Filter|r Mode.\n\n"
                  .. "3. |cffddddddFilter By|r |cff76CC4BRole|r, and select "
                  .. "|cff76CC4BMain Tank|r and |cff76CC4BMain Assist|r.\n\n"
                  .. "Custom Frame Groups are fully separate from the Raid / "
                  .. "Party Frames and can be positioned in "
                  .. "|cff76CC4BSetup Mode|r." },
        }},
    }}
end
