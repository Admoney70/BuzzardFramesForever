-- ============================================================
-- BuzzardFramesOptions: Pages_UFLayouts.lua
-- The Unit Frames > Unit Frame Layouts section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' UnitFrames/Options_UFLayouts.lua
-- (BF:BuildUFLayoutsOptions): the same settings, the same storage and the
-- same side effects, with the AceConfig args table replaced by
-- BuzzardPanel routes under `unitFrames/ufLayoutsTab`, drawn as a strip by
-- the `tabs` navigator that node declares:
--
--   manage      "Manage Layouts" -- the Ace manageTab: which frames opt
--               into per-layout positioning.
--               Create, Rename Layout and Remove follow on the same page
--               (Ace tabCreate / tabEdit / tabRemove).
--   ufRoleSpec  "Layout Assignments" -- the assignment COLLECTION: the
--               Global assignment and the role and spec overrides in one
--               tree, each entry a route with its own pane, listed by a
--               tree card on that page. Global is last and cannot be
--               removed: it is what the overrides fall back to.
--
-- THE SHAPE IS THE RAID SECTION'S. Pages_Layouts.lua does the same thing
-- for raid/party Layouts -- one list of assignment entries under a
-- "Layout Assignments" tab, with the Add dropdowns above it -- and these
-- two sections answer the same question about two sets of frames, so they
-- now ask it the same way. What that replaced here: the Ace roleSpecTab, a branch of five tabs (Role Layouts, Spec
-- Layouts, Create, Edit, Remove) whose first two stated the same idea in
-- two different idioms -- three fixed role dropdowns on one, an
-- add/remove list on the other.
--
-- PRESENCE IS THE GATE. An override exists because there is an entry for
-- it. The Ace enableUFRoleLayouts / enableUFSpecLayouts switches are gone
-- from the panel; they are still written, derived from the list, because
-- BF:ApplyUFRoleSpecLayout and the Ace panel both read them. Roles gained
-- a presence table of their own (ufRoleLayouts) to make this sayable --
-- ufRoleLayoutAssignment is an AceDB default and always carries all three
-- roles, so it cannot distinguish a role the reader configured from one
-- they never opened. Migration 78 (Core_Migrations.lua) turns the old
-- data into entries.
--
-- THE "UNIT FRAME LAYOUT" PICKER IS GONE from above the strip. The Ace
-- ufLayoutSelect was a non-group arg of ufLayoutsTab, so the dialog drew
-- it above the tab strip and it stayed on screen whichever tab was
-- selected; the panel has no region for that, and it is the Global entry
-- of Layout Assignments now -- where the raid section keeps the same
-- decision. It also gained a field of its own: it wrote activeUFLayout,
-- which is the field the resolver overwrites with whatever it resolved,
-- so a reader with no overrides could not keep a layout selected -- the
-- next role change reverted it. The choice is ufGlobalLayout; the
-- resolved answer stays in activeUFLayout.
--
-- Storage: BF.ufDB.profile.* (SavedVariable BuzzardFramesUnitFramesDB) --
-- its own database, NOT the raid/party section profiles, so none of
-- GetSectionProfile / WriteSectionKey / the per-Layout scope machinery
-- applies here and this section takes NO per-Layout scope row. Reads and
-- writes go through ROOT below, a table-shaped view of ufDB.profile that
-- repeats the Ace setters' `x = x or {}` materialisation, so `bind` (and
-- with it right-click Undo and Reset) works on the plain fields.
--
-- The route itself is gated in the Ace panel by
-- `hidden = not ufDB.profile.ptfEnabled`, and Options_oUF_Other.lua's
-- syncPTFTabs nils the tab out when unit frames are off. This file
-- assumes the OWNER of that gate (the `unitFrames` section root) keeps
-- the `ufLayoutsTab` route out of the tree while ptfEnabled is false --
-- nothing here checks ptfEnabled.
--
-- Ace args keys with no field of their own here, for the audit:
--   manageTab / roleSpecTab            -> the routes
--   tabCreate / tabEdit / tabRemove    -> the Create, Rename Layout and
--                                         Remove cards on Manage Layouts
--   tabRoleLayouts / tabSpecLayouts    -> the collection: a role entry and
--                                         a spec entry are the same thing
--                                         at two scopes, so they are one
--                                         list rather than two tabs
--   hdrFrames / renameHeader           -> card titles
--   assignmentsHeader                  -> each entry's pane states its own
--                                         heading, so a rule above the
--                                         list would head nothing
--   specLayoutsGroup                   -> the collection's spec entries;
--                                         its per-spec `spec_<id>`
--                                         dropdown is the member pane
--   specCreate / specRemove            -> "Add Spec Overrides" and the
--                                         pane's corner X
--   enableUFRoleLayouts /              -> derived from the entry list, not
--   enableUFSpecLayouts                   shown (see SyncEnableFlags)
--   ufLayoutSelect                     -> the Global entry's Layout
--                                         dropdown, writing ufGlobalLayout
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The unit-frame profile. Everything on this section lives under it.
local function UFProfile()
    local bf = BF()
    return bf and bf.ufDB and bf.ufDB.profile
end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source; a copy here would be a second answer to the same question.
local function UFDefaults()
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    return d and d.profile
end

-- ── The routed root ────────────────────────────────────────────
--
-- `bind` walks a dotted path into the page's db. ufDB.profile IS that
-- table, but the Ace setters materialise `ufLayoutFrames` on write
-- (`p.ufLayoutFrames = p.ufLayoutFrames or {}`) and a bind cannot, so the
-- page hands the library a view that does. Reads fall through, writes land
-- on exactly the slots the Ace setters wrote to.
local LAYOUT_FRAMES = setmetatable({}, {
    __index = function(_, k)
        local p = UFProfile()
        local t = p and p.ufLayoutFrames
        return t and t[k]
    end,
    __newindex = function(_, k, v)
        local p = UFProfile()
        if not p then return end
        p.ufLayoutFrames = p.ufLayoutFrames or {}
        p.ufLayoutFrames[k] = v
    end,
})

local ROLE_ASSIGNMENT = setmetatable({}, {
    __index = function(_, k)
        local p = UFProfile()
        local t = p and p.ufRoleLayoutAssignment
        return t and t[k]
    end,
    __newindex = function(_, k, v)
        local p = UFProfile()
        if not p then return end
        p.ufRoleLayoutAssignment = p.ufRoleLayoutAssignment or {}
        p.ufRoleLayoutAssignment[k] = v
    end,
})

local ROOT = setmetatable({}, {
    __index = function(_, k)
        if k == "ufLayoutFrames"         then return LAYOUT_FRAMES  end
        if k == "ufRoleLayoutAssignment" then return ROLE_ASSIGNMENT end
        local p = UFProfile()
        return p and p[k]
    end,
    __newindex = function(_, k, v)
        local p = UFProfile()
        if p then p[k] = v end
    end,
})

local function Root() return ROOT end

-- ── Side effects, verbatim from the Ace builder ────────────────

-- Apply UF positions after layout or group type change. The combat guard
-- is the Ace one, kept as it stands rather than summarised.
local function ApplyPositions()
    local bf = BF()
    if not bf then return end
    if not InCombatLockdown() and bf.ApplyAllUFPositions then
        bf:ApplyAllUFPositions()
    end
end

-- Refresh UF test frames if setup mode is active.
local function RefreshTestFrames()
    local bf = BF()
    if not bf then return end
    if not bf.ShowUFTestFrames then return end
    if bf.db and bf.db.global and bf.db.global.setupModeActive then
        bf:ShowUFTestFrames()
    end
end

local function ApplyRoleSpec()
    local bf = BF()
    if bf and bf.ApplyUFRoleSpecLayout then bf:ApplyUFRoleSpecLayout() end
end

-- ── The layout list ────────────────────────────────────────────

local function UFLayouts()
    local p = UFProfile()
    return p and p.ufLayouts
end

-- The Ace get chain for the active layout, to the letter.
local function ActiveUFLayoutID()
    local bf = BF()
    local p  = UFProfile()
    return (bf and bf._ufActiveLayout) or (p and p.activeUFLayout) or "default"
end

-- ids in a stable order: alphabetical by display name, which is the order
-- AceConfigDialog itself put a `values` map in when no `sorting` was
-- given. `pairs` order is not an order, so this is the one place the
-- panel decides something the source left to chance.
local function SortedUFLayoutIDs(excludeDefault)
    local fl = UFLayouts() or {}
    local ids = {}
    for id, layout in pairs(fl) do
        if type(layout) == "table" and not (excludeDefault and id == "default") then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        local an = tostring(fl[a].name or a):lower()
        local bn = tostring(fl[b].name or b):lower()
        if an == bn then return a < b end
        return an < bn
    end)
    return ids
end

-- Ace ufLayoutValues, as an options list: every layout, the ACTIVE one
-- tinted green -- |cff76CC4B kept to the digit, because that green is how
-- the Ace dropdown has always marked "this is the one in use".
local function UFLayoutOptions()
    local fl = UFLayouts()
    if not fl then return { { value = "default", text = "Default" } } end
    local activeID = ActiveUFLayoutID()
    local out = {}
    for _, id in ipairs(SortedUFLayoutIDs(false)) do
        local name = fl[id].name or id
        out[#out + 1] = {
            value = id,
            text  = (id == activeID) and ("|cff76CC4B" .. name .. "|r") or name,
        }
    end
    return out
end

-- The rename/remove lists: every layout EXCEPT Default, plain names.
local function CustomUFLayoutOptions()
    local fl = UFLayouts() or {}
    local out = {}
    for _, id in ipairs(SortedUFLayoutIDs(true)) do
        out[#out + 1] = { value = id, text = fl[id].name or id }
    end
    return out
end

-- The two Ace `hidden` predicates around custom layouts, each kept whole
-- because they disagree about a missing ufLayouts table: the selectors
-- hide, the notes show.
local function HideWhenNoCustomLayouts()
    local p = UFProfile()
    if not (p and p.ufLayouts) then return true end
    for id in pairs(p.ufLayouts) do
        if id ~= "default" then return false end
    end
    return true
end

local function HideWhenAnyCustomLayouts()
    local p = UFProfile()
    if not (p and p.ufLayouts) then return false end
    for id in pairs(p.ufLayouts) do
        if id ~= "default" then return true end
    end
    return false
end

-- Generate a unique UF layout ID.
local function NewUFLayoutID()
    local p = UFProfile()
    if not p then return nil end
    if not p.ufLayouts then p.ufLayouts = {} end
    local i = 1
    repeat
        local id = "uflayout_" .. i
        if not p.ufLayouts[id] then return id end
        i = i + 1
    until false
end

-- ── The frame opt-in switches ──────────────────────────────────
--
-- Ace manageTab. Eight switches that differ by nothing but their key and
-- their label, so they are built rather than written out eight times.
local function FrameToggle(key, label, desc)
    return {
        control = "switch", label = label, desc = desc,
        bind = "ufLayoutFrames." .. key,
        onChange = RefreshTestFrames,
    }
end

-- Delete one layout, with the in-use checks. The Ace removeLayout set
-- body, verbatim; the confirmation has already happened by the time this
-- runs, as it had there.
local function RemoveUFLayout(ctx, val)
    local bf = BF()
    local p  = UFProfile()
    if not (bf and p) then return end
    if not p.ufLayouts or not p.ufLayouts[val] then return end
    local name = p.ufLayouts[val].name or val
    -- Check if in use
    local usages = {}
    local roles = { HEALER = "Healer", TANK = "Tank", DAMAGER = "DPS" }
    if p.ufRoleLayoutAssignment then
        for roleKey, roleLabel in pairs(roles) do
            if p.ufRoleLayoutAssignment[roleKey] == val then
                table.insert(usages, "Role: " .. roleLabel)
            end
        end
    end
    if p.ufSpecLayoutAssignment then
        for specID, assignedLayout in pairs(p.ufSpecLayoutAssignment) do
            if assignedLayout == val and p.ufSpecLayouts and p.ufSpecLayouts[specID] then
                local s = bf.specByID and bf.specByID[tonumber(specID)]
                local specName = s and s.name or ("Spec " .. specID)
                table.insert(usages, "Spec: " .. specName)
            end
        end
    end
    if #usages > 0 then
        local msg = "Cannot delete UF layout \"" .. name .. "\" — it is assigned in " .. #usages .. " place(s):\n"
        for _, u in ipairs(usages) do
            msg = msg .. "\n• " .. u
        end
        StaticPopup_Show("BUZZARDFRAMES_LAYOUT_IN_USE", msg)
        return
    end
    p.ufLayouts[val] = nil
    -- If the deleted layout was active, revert to default
    if bf._ufActiveLayout == val then
        bf._ufActiveLayout = "default"
        p.activeUFLayout   = "default"
        ApplyPositions()
    end
    ctx.app:RefreshPage()
    print("BuzzardFrames: Removed UF layout \"" .. name .. "\"")
end


-- ── Managing the layouts themselves: three cards ───────────────
--
-- The Ace tabCreate, tabEdit and tabRemove. They were three routes with a
-- strip of their own, then one "Layout Management" tab; they are three
-- cards at the foot of Manage Layouts now. Creating a layout, renaming it
-- and deleting it are what "managing layouts" means, so a tab of that name
-- beside a tab called Manage Layouts was the same promise made twice --
-- and each of the three holds one control, which is not a page.
--
-- Returned as a LIST of groups rather than as a page, because they are
-- appended to one. The cards keep the Ace order and the Ace wording.

local function ManagementCards()
    return {
            { title = "Create", preset = "form", fields = {
                -- Ace: createCopyFrom.
                { control = "dropdown", label = "Copy Settings From",
                  labelPlacement = "above",
                  desc = "Choose an existing layout to copy positions from. "
                      .. "Defaults to Default.",
                  options = UFLayoutOptions,
                  get = function()
                      local bf = BF()
                      local p  = UFProfile()
                      return (bf and bf._ufCreateCopyFrom)
                          or (bf and bf._ufActiveLayout)
                          or (p and p.activeUFLayout)
                          or "default"
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._ufCreateCopyFrom = val
                      ctx.app:RefreshPage()
                  end },

                -- Ace: createLayout. `submit = true` draws the same OK
                -- button the Ace input had; Enter commits too.
                { control = "text", label = "Create Layout", submit = "Create",
                  desc = "Type a name and press Enter (or click OK) to "
                      .. "create the new layout.",
                  get = function() return "" end,
                  set = function(_, ctx, val)
                      if not val or val:match("^%s*$") then return end
                      local bf = BF()
                      local p  = UFProfile()
                      if not (bf and p) then return end
                      if not p.ufLayouts then p.ufLayouts = {} end
                      for _, layout in pairs(p.ufLayouts) do
                          if layout.name == val then
                              print("BuzzardFrames: A UF layout named \"" .. val .. "\" already exists.")
                              return
                          end
                      end
                      local id = NewUFLayoutID()
                      local copyFrom = bf._ufCreateCopyFrom or "default"
                      if p.ufLayouts[copyFrom] then
                          p.ufLayouts[id] = bf:DeepCopy(p.ufLayouts[copyFrom])
                          p.ufLayouts[id].name = val
                          print("BuzzardFrames: Created UF layout \"" .. val .. "\" (copied from \"" .. p.ufLayouts[copyFrom].name .. "\")")
                      else
                          -- Party bucket only -- the raid buckets are dead
                          -- (see Defaults_UnitFrames.lua).
                          p.ufLayouts[id] = { name = val, party = {} }
                          print("BuzzardFrames: Created UF layout \"" .. val .. "\"")
                      end
                      bf._ufCreateCopyFrom = nil
                      ctx.app:RefreshPage()
                  end },
            }},

            { title = "Rename Layout", preset = "form", fields = {
                -- Ace: renameLayoutSelect.
                { control = "dropdown", label = "Rename Layout",
                  labelPlacement = "above",
                  desc = "Select a layout to rename.",
                  hidden  = HideWhenNoCustomLayouts,
                  options = CustomUFLayoutOptions,
                  get = function()
                      local bf = BF()
                      local p  = UFProfile()
                      if bf and bf._ufRenameLayoutID and p and p.ufLayouts
                         and p.ufLayouts[bf._ufRenameLayoutID] then
                          return bf._ufRenameLayoutID
                      end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._ufRenameLayoutID = val
                      ctx.app:RefreshPage()
                  end },

                -- Ace: noRenameNote.
                { control = "note", wide = true,
                  hidden = HideWhenAnyCustomLayouts,
                  text = "No custom layouts to rename. Create a layout first." },

                -- Ace: renameLayoutInput.
                { control = "text", label = "New Name", submit = "Rename",
                  desc = "Type a new name and press Enter (or click OK) to "
                      .. "rename the selected layout.",
                  hidden = function()
                      local bf = BF()
                      return not (bf and bf._ufRenameLayoutID)
                  end,
                  get = function()
                      local bf = BF()
                      local p  = UFProfile()
                      local id = bf and bf._ufRenameLayoutID
                      if id and p and p.ufLayouts and p.ufLayouts[id] then
                          return p.ufLayouts[id].name
                      end
                      return ""
                  end,
                  set = function(_, ctx, val)
                      if not val or val:match("^%s*$") then return end
                      local bf = BF()
                      local p  = UFProfile()
                      if not (bf and p) then return end
                      local id = bf._ufRenameLayoutID
                      if not id or not p.ufLayouts or not p.ufLayouts[id] then return end
                      for oid, layout in pairs(p.ufLayouts) do
                          if oid ~= id and layout.name == val then
                              print("BuzzardFrames: A UF layout named \"" .. val .. "\" already exists.")
                              return
                          end
                      end
                      local old_name = p.ufLayouts[id].name
                      p.ufLayouts[id].name = val
                      ctx.app:RefreshPage()
                      print("BuzzardFrames: Renamed UF layout \"" .. old_name .. "\" to \"" .. val .. "\"")
                  end },
            }},

            { title = "Remove", preset = "form", fields = {
                -- Ace: removeLayout. The Ace dropdown deleted on the PICK --
                -- opening a list and moving down it was the act of
                -- destroying a layout. Here the pick only SELECTS; the
                -- Remove button below is what asks. Same change, same
                -- reasoning, as the raid Layouts card.
                { control = "dropdown", label = "Remove Layout",
                  labelPlacement = "above",
                  desc = "Select a layout to delete.",
                  hidden  = HideWhenNoCustomLayouts,
                  options = CustomUFLayoutOptions,
                  get = function()
                      local bf = BF()
                      local p  = UFProfile()
                      local id = bf and bf._ufRemoveLayoutID
                      -- Only if it is still there: it may have been deleted
                      -- from here, or renamed away, since the pick.
                      if id and p and p.ufLayouts and p.ufLayouts[id] then
                          return id
                      end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._ufRemoveLayoutID = val
                      -- The button below turns on with the selection.
                      ctx.app:RefreshPage()
                  end },

                { control = "button", text = "Remove", danger = true,
                  desc = "Permanently delete the selected layout.",
                  hidden = HideWhenNoCustomLayouts,
                  disabled = function()
                      local bf = BF()
                      local p  = UFProfile()
                      local id = bf and bf._ufRemoveLayoutID
                      return not (id and p and p.ufLayouts and p.ufLayouts[id])
                  end,
                  onClick = function(_, ctx)
                      local bf = BF()
                      local p  = UFProfile()
                      local id = bf and bf._ufRemoveLayoutID
                      if not (id and p and p.ufLayouts and p.ufLayouts[id]) then return end
                      local name = p.ufLayouts[id].name or id
                      ctx.app:Confirm("Are you sure you want to delete UF layout \""
                          .. name .. "\"? This cannot be undone.",
                          function()
                              RemoveUFLayout(ctx, id)
                              -- Cleared only if it actually went:
                              -- RemoveUFLayout REFUSES a layout still
                              -- assigned to a role or a spec, and a dropdown
                              -- that empties itself after a refusal says the
                              -- opposite of what the popup just said.
                              local now = UFProfile()
                              if not (now and now.ufLayouts and now.ufLayouts[id]) then
                                  bf._ufRemoveLayoutID = nil
                              end
                          end)
                  end },

                -- Ace: noLayoutsNote.
                { control = "note", wide = true,
                  hidden = HideWhenAnyCustomLayouts,
                  text = "No custom layouts to remove. The Default layout "
                      .. "cannot be deleted." },
            }},
    }
end

-- ── Page 1: Manage Layouts ─────────────────────────────────────
--
-- Ace manageTab: which frames opt into per-layout positioning, and
-- then the three cards that create, rename and remove the layouts
-- themselves.
local function ManagePage()
    return {
        db       = Root,
        defaults = UFDefaults,
        groups   = {
            -- Ace: desc.
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Unit Frame Layouts currently control positioning "
                      .. "only. All other settings (size, colors, text, "
                      .. "etc.) are shared across all layouts.\n\nCheck the "
                      .. "frames below that should have per-layout "
                      .. "positioning. Unchecked frames use a single global "
                      .. "position." },
            }},
            -- Ace: hdrFrames, and the eight toggles under it.
            { title = "Include in Layout", preset = "form", fields = {
                -- Ace: frameDesc.
                { control = "note", wide = true,
                  text = "Checked frames will have their position saved "
                      .. "per-layout and per-group-type. Unchecked frames "
                      .. "use a single global position." },
                -- Ace arg key -> ufLayoutFrames storage key, in the Ace
                -- order (12..20): ufPlayer -> player,
                -- ufPlayerPowerBar -> playerPowerBar,
                -- ufPlayerResourceBar -> playerResourceBar,
                -- ufTarget -> target, ufFocus -> focus, ufPet -> pet,
                -- ufTargetOfTarget -> targettarget,
                -- ufFocusTarget -> focustarget, ufBoss -> boss.
                FrameToggle("player",            "Player"),
                FrameToggle("playerPowerBar",    "Player Power Bar",
                            "Detached power bar position."),
                FrameToggle("playerResourceBar", "Player Resource Bar",
                            "Detached resource bar position."),
                FrameToggle("target",            "Target"),
                FrameToggle("focus",             "Focus"),
                FrameToggle("pet",               "Pet"),
                FrameToggle("targettarget",      "Target of Target"),
                FrameToggle("focustarget",       "Focus Target"),
                FrameToggle("boss",              "Boss Frames"),
            }},
        },
    }
end

-- Manage Layouts as the page actually is: the frame opt-ins above, then
-- Create, Rename and Remove. Appended rather than written into the table
-- so the two halves stay separately readable -- one is about which frames
-- a layout carries, the other about the layouts themselves.
local function ManageLayoutsPage()
    local page = ManagePage()
    for _, card in ipairs(ManagementCards()) do
        page.groups[#page.groups + 1] = card
    end
    return page
end

-- ── Page 3: Layouts -- the role/spec override collection ───────
--
-- One tree of override ENTRIES, roles and specs together, which is the
-- shape the raid section's Layouts tab has (Pages_Layouts.lua). It
-- replaces a branch of two tabs -- three fixed role dropdowns on one, an
-- add/remove spec list on the other -- that asked the same question twice
-- and answered it in two different idioms.
--
-- PRESENCE IS THE GATE. An override exists because there is an entry for
-- it, exactly as a spec override always worked; the two Ace enable
-- switches are gone from the panel. They are still WRITTEN, because the
-- engine's resolver and the Ace panel both read them -- see SyncEnableFlags
-- below -- but they are derived from the list rather than set by hand.

-- Fixed role definitions, in the order the raid tree shows them.
local ROLE_DEFS = {
    { key = "TANK",    label = "Tank",   atlas = "roleicon-tiny-tank"   },
    { key = "HEALER",  label = "Healer", atlas = "roleicon-tiny-healer" },
    { key = "DAMAGER", label = "DPS",    atlas = "roleicon-tiny-dps"    },
}

local function SpecList()
    local bf = BF()
    return (bf and bf.specData) or {}
end

local function SpecInfo(idStr)
    local bf = BF()
    return bf and bf.specByID and bf.specByID[tonumber(idStr)]
end

local function RoleLayoutsTable()
    local p = UFProfile()
    if not p then return nil end
    p.ufRoleLayouts = p.ufRoleLayouts or {}
    return p.ufRoleLayouts
end

local function SpecLayoutsTable()
    local p = UFProfile()
    if not p then return nil end
    p.ufSpecLayouts = p.ufSpecLayouts or {}
    return p.ufSpecLayouts
end

-- The two enable flags, DERIVED. A kind is enabled exactly when it has at
-- least one entry.
--
-- They are not shown anywhere any more, but they are not dead:
-- BF:ApplyUFRoleSpecLayout branches on them, and the Ace panel still
-- offers them as switches. Writing them here keeps all three surfaces
-- saying the same thing, and means adding the first override turns the
-- feature on by itself rather than leaving the reader with an entry that
-- does nothing until they find a switch.
local function SyncEnableFlags()
    local p = UFProfile()
    if not p then return end
    local anyRole = false
    for _ in pairs(RoleLayoutsTable() or {}) do anyRole = true break end
    local anySpec = false
    for _ in pairs(SpecLayoutsTable() or {}) do anySpec = true break end
    p.enableUFRoleLayouts = anyRole
    p.enableUFSpecLayouts = anySpec
    ApplyRoleSpec()
end

-- The collection's source: present roles in ROLE_DEFS order, then present
-- specs alphabetically -- the raid tree's own ordering.
local function UFRoleSpecMembers()
    local rl = RoleLayoutsTable()
    local sl = SpecLayoutsTable()
    if not (rl and sl) then return {} end
    local out = {}
    for _, def in ipairs(ROLE_DEFS) do
        if rl[def.key] then
            local icon = (CreateAtlasMarkup and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
            out[#out + 1] = { kind = "role", entryKey = def.key,
                              id = "role_" .. def.key,
                              title = icon .. " " .. def.label }
        end
    end
    local specs = {}
    for idStr in pairs(sl) do
        local s = SpecInfo(idStr)
        if s then specs[#specs + 1] = { idStr = idStr, name = s.name, icon = s.icon } end
    end
    table.sort(specs, function(a, b) return a.name < b.name end)
    for _, sp in ipairs(specs) do
        out[#out + 1] = { kind = "spec", entryKey = sp.idStr,
                          id = "spec_" .. sp.idStr,
                          title = "|T" .. sp.icon .. ":14|t " .. sp.name }
    end
    -- GLOBAL, always and always LAST: it is what every override above it
    -- falls back to, and a fallback belongs at the foot of the list rather
    -- than at its head. Not sourced from the profile like the others --
    -- there is nothing to add or remove, so it is simply always there.
    -- The raid tree ends the same way, for the same reason.
    out[#out + 1] = { kind = "global", entryKey = "global", id = "global",
                      title = "Global" }
    return out
end

-- Is a spec override currently winning over the role overrides? The Ace
-- specOverrideNote asked exactly this, on the Role Layouts tab; it belongs
-- on a ROLE entry's pane now, where the reader is looking at the setting
-- being overridden.
-- The options an OVERRIDE entry offers, which are not the options the
-- Global entry offers: an override may decline to override.
--
-- "__global" is the sentinel, stored as nil -- the raid overrides' own
-- convention (OverrideSlotField in Pages_Layouts.lua), down to naming the
-- layout it defers to so the reader can see what "global" currently means
-- without leaving the pane. An entry set to it is present in the tree and
-- resolves to nothing, which is what lets a reader park an override
-- without deleting it.
local function OverrideLayoutOptions()
    local p  = UFProfile()
    local fl = UFLayouts() or {}
    local gid = p and p.ufGlobalLayout
    local gname
    if gid and fl[gid] then
        gname = fl[gid].name or gid
    else
        gname = (fl.default and fl.default.name) or "Default"
    end
    local out = { { value = "__global",
                    text  = "Use global setting (" .. gname .. ")" } }
    for _, opt in ipairs(UFLayoutOptions()) do out[#out + 1] = opt end
    return out
end

local function SpecOverrideActive()
    local p = UFProfile()
    if not p then return false end
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo
                   and tostring(select(1, GetSpecializationInfo(specIndex)))
    if not specID then return false end
    return (p.ufSpecLayouts and p.ufSpecLayouts[specID]
            and p.ufSpecLayoutAssignment and p.ufSpecLayoutAssignment[specID]) and true or false
end

-- One entry's pane: the heading the raid member pages use, then the single
-- dropdown that IS the override. Explicit get/set rather than `bind`,
-- because the two kinds write into two different tables and the setter
-- has to re-resolve the active layout either way.
local function UFRoleSpecMemberPage(mctx)
    local item = mctx.item

    -- The GLOBAL entry: the layout in use unless an override applies. What
    -- the "Unit Frame Layout" picker above the tab strip used to set, in
    -- the place the raid tree keeps the same decision -- and in a field of
    -- its own (ufGlobalLayout), so an override resolving on top of it no
    -- longer overwrites the choice.
    if item.kind == "global" then
        return { groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true, font = "GameFontNormalLarge",
                  color = { 1, 1, 1, 1 }, text = "Global" },
                { control = "note", wide = true,
                  text = "This Layout is used unless an override exists for "
                      .. "the current Role or Spec." },
            }},
            { title = "Layout", preset = "form", fields = {
                { control = "dropdown", label = "Layout",
                  labelPlacement = "above",
                  desc = "The Unit Frame Layout used when no Role or Spec "
                      .. "override applies. The Layout currently in use is "
                      .. "shown in green.",
                  -- No `bind`: the setter touches BF state as well as the
                  -- profile, so the field names itself for undo and reset
                  -- and states the shipped default outright.
                  id      = "ufGlobalLayout",
                  default = (function()
                      local d = UFDefaults()
                      return (d and d.ufGlobalLayout) or "default"
                  end)(),
                  disabled = "combat",
                  options  = UFLayoutOptions,
                  get = function()
                      local p = UFProfile()
                      return (p and p.ufGlobalLayout) or "default"
                  end,
                  set = function(_, ctx, val)
                      -- The Ace setter's own combat guard, kept as it
                      -- stands alongside `disabled` above.
                      if InCombatLockdown() then return end
                      local bf = BF()
                      local p  = UFProfile()
                      if not (bf and p) then return end
                      p.ufGlobalLayout = val
                      -- Re-resolve rather than activate: an override may be
                      -- winning right now, in which case this choice is
                      -- stored and does not take effect until that override
                      -- stops applying. ApplyUFRoleSpecLayout ends in
                      -- ApplyAllUFPositions either way.
                      ApplyRoleSpec()
                      if bf.ShowUFTestFrames and bf.db and bf.db.global
                         and bf.db.global.setupModeActive then
                          bf:ShowUFTestFrames()
                      end
                      -- The green "in use" tint may just have moved.
                      ctx.app:RefreshPage()
                  end },
            }},
        }}
    end

    local isRole = (item.kind == "role")
    local badge  = isRole and "|cff7f77ddRole override|r"
                          or  "|cff1d9e75Spec override|r"
    local key    = item.entryKey
    return { groups = {
        { preset = "bare", fields = {
            { control = "note", wide = true, font = "GameFontNormalLarge",
              color = { 1, 1, 1, 1 },
              text = item.title .. "    " .. badge },
            -- Ace: specOverrideNote, on the entry it actually concerns.
            { control = "note", wide = true,
              hidden = function() return not (isRole and SpecOverrideActive()) end,
              text = "|cffff9900|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertOther:14:14:0:0|t The current spec has an active spec-specific layout which overrides this role.|r" },
        }},

        { title = "Layout", preset = "form", fields = {
            { control = "dropdown", label = "Layout",
              labelPlacement = "above",
              desc = isRole
                  and "The Unit Frame Layout used while you are playing this role."
                  or  "The Unit Frame Layout used while you are playing this spec.",
              id      = (isRole and "ufRoleLayout_" or "ufSpecLayout_") .. key,
              -- What a reset restores: deferring to Global, not the Default
              -- layout. The two are different answers -- "no opinion" and
              -- "the layout named Default" -- and an override's shipped
              -- state is the first of them.
              default = "__global",
              options = OverrideLayoutOptions,
              get = function()
                  local p = UFProfile()
                  if not p then return "__global" end
                  local t = isRole and p.ufRoleLayoutAssignment
                                   or  p.ufSpecLayoutAssignment
                  return (t and t[key]) or "__global"
              end,
              set = function(_, ctx, val)
                  local p = UFProfile()
                  if not p then return end
                  local stored = (val ~= "__global") and val or nil
                  if isRole then
                      p.ufRoleLayoutAssignment = p.ufRoleLayoutAssignment or {}
                      p.ufRoleLayoutAssignment[key] = stored
                  else
                      p.ufSpecLayoutAssignment = p.ufSpecLayoutAssignment or {}
                      p.ufSpecLayoutAssignment[key] = stored
                  end
                  ApplyRoleSpec()
                  -- The green "in use" tint may have moved, and so may the
                  -- name inside "Use global setting (...)" on a sibling.
                  ctx.app:RefreshPage()
              end },
        }},

        -- NO Remove BUTTON: the pane carries the corner X, which runs the
        -- collection's own remove path. The raid member pages made the
        -- same call for the same reason.
    }}
end

-- The collection's own page: the active-layout picker, the precedence
-- note, the two Add dropdowns, and then the tree card listing the entries
-- with the selected one's pane beside it -- the raid root page's shape.
local function UFRoleSpecRootPage()
    return {
      db       = Root,
      defaults = UFDefaults,
      groups = {
        -- NO active-layout strip. It leads the other pages here because
        -- the Ace picker sat above the tab strip and so was visible from
        -- all of them, but nothing on THIS tab reads or writes it: an
        -- override says which layout a role or a spec gets, not which one
        -- is in use right now. A control that governs nothing on the page
        -- it heads is one the reader has to rule out.
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Give a role or a spec its own Unit Frame Layout. If "
                  .. "both are defined for what you are currently playing, "
                  .. "the Spec override takes priority." },

            -- Adding is an ACTION, so the dropdown never shows a current
            -- value; it lists only roles without an entry yet, in the
            -- fixed Tank -> Healer -> DPS order.
            { control = "dropdown", label = "Add Role Overrides",
              labelPlacement = "above",
              options = function()
                  local out = {}
                  local rl = RoleLayoutsTable()
                  if not rl then return out end
                  for _, def in ipairs(ROLE_DEFS) do
                      if not rl[def.key] then
                          local icon = (CreateAtlasMarkup and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
                          out[#out + 1] = { value = def.key, text = icon .. " " .. def.label }
                      end
                  end
                  return out
              end,
              get = function() return nil end,
              set = function(_, ctx, val)
                  ctx.app:CollectionAdd("ufRoleSpec", "role", val)
              end },

            -- Specs without an entry, alphabetical by name.
            { control = "dropdown", label = "Add Spec Overrides",
              labelPlacement = "above",
              options = function()
                  local out = {}
                  local sl = SpecLayoutsTable()
                  if not sl then return out end
                  local list = {}
                  for _, s in ipairs(SpecList()) do
                      local idStr = tostring(s.id)
                      if not sl[idStr] then
                          list[#list + 1] = { id = idStr, name = s.name, icon = s.icon }
                      end
                  end
                  table.sort(list, function(a, b) return a.name < b.name end)
                  for _, e in ipairs(list) do
                      out[#out + 1] = { value = e.id, text = "|T" .. e.icon .. ":14|t " .. e.name }
                  end
                  return out
              end,
              get = function() return nil end,
              set = function(_, ctx, val)
                  ctx.app:CollectionAdd("ufRoleSpec", "spec", val)
              end },
        }},

        -- The list, and whichever entry is selected. Last, so the note and
        -- the two Add dropdowns are what the reader meets first and what
        -- stays put while they move through the list. The measurements are
        -- the raid tree's, so the two sections read as one idiom: 175 wide,
        -- `height = "fill"` so the card follows a resize to the bottom of
        -- the panel, `listTopPad = 0` so the first row and the pane's
        -- heading start level, `flush = 2` so the list belongs to the cards
        -- above it with a hairline between.
        { preset = "form", flush = 2,
          tree = { route = "unitFrames/ufLayoutsTab/ufRoleSpec",
                   width = 175, height = "fill", minHeight = 240,
                   listTopPad = 0 } },
      }}
end

-- ── Publishing ─────────────────────────────────────────────────
--
-- Two plain subtabs and then the collection, which is a ROUTE NODE rather
-- than a page and carries its member machinery with it.
BuzzardFramesOptions.UFLAYOUTS_SUBTABS = {
    { id = "manage", title = "Manage Layouts" },
}

local PAGES = {
    manage = ManageLayoutsPage,
}

function BuzzardFramesOptions:UFLayoutsPage(subtabId)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end
    -- No active-layout strip leading the page any more. The Ace
    -- ufLayoutSelect picker sat above the tab strip and so was visible
    -- from every subtab; the Global entry of Layout Assignments is where
    -- that choice lives now, which is where the raid section keeps the
    -- same decision. A picker here as well would be the same setting in
    -- two places, and the one on this page could not say whether an
    -- override was currently winning.
    return build()
end

-- The third subtab: the override collection. A TREE GROUP -- the raid
-- Layouts tab's own construct -- so the entries are ROUTES and the list
-- that selects them is a CARD on the page rather than chrome. That is what
-- makes the shape available under a section that already carries a tab
-- strip: a tree group asks for no navigator and no second strip, so
-- nothing lands on top of the section's own.
--
-- `combat = false` on add and remove: the Ace page allowed both in combat,
-- and matching it is what keeps the two panels agreeing about what is
-- possible when.
function BuzzardFramesOptions:UFLayoutsRoleSpecRoute()
    return {
        node        = "collection",
        id          = "ufRoleSpec",
        -- The raid section's name for the same tab: every entry here
        -- assigns a layout to a situation.
        title       = "Layout Assignments",
        treeGroup   = true,
        -- The entries are listed BY THE PAGE, in the tree card. The rail
        -- listing them as well would be the same list twice.
        railChildren = false,
        page        = UFRoleSpecRootPage,
        source      = UFRoleSpecMembers,
        key         = function(item) return item.id end,
        memberTitle = function(item) return item.title end,
        template    = UFRoleSpecMemberPage,
        add = {
            combat = false,
            -- Entries are routes, so adding LANDS on the new one with its
            -- pane already drawn.
            select = true,
            onAdd  = function(kind, val)
                local p = UFProfile()
                if kind == "role" then
                    local rl = RoleLayoutsTable()
                    if not rl then return nil end
                    rl[val] = true
                    -- A new entry starts at "use the global setting", not
                    -- at whatever this role was assigned before it was last
                    -- removed. Removing clears the assignment too, so this
                    -- only catches a value left by an older build.
                    if p and p.ufRoleLayoutAssignment then
                        p.ufRoleLayoutAssignment[val] = nil
                    end
                else
                    local sl = SpecLayoutsTable()
                    if not sl then return nil end
                    sl[val] = true
                    if p and p.ufSpecLayoutAssignment then
                        p.ufSpecLayoutAssignment[val] = nil
                    end
                end
                SyncEnableFlags()
                if kind == "role" then
                    local def
                    for _, d in ipairs(ROLE_DEFS) do
                        if d.key == val then def = d end
                    end
                    local icon = (def and CreateAtlasMarkup
                                  and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
                    return { kind = "role", entryKey = val, id = "role_" .. val,
                             title = icon .. " " .. ((def and def.label) or val) }
                end
                local s = SpecInfo(val)
                return { kind = "spec", entryKey = val, id = "spec_" .. val,
                         title = "|T" .. ((s and s.icon) or "") .. ":14|t "
                                 .. ((s and s.name) or val) }
            end,
        },
        remove = {
            combat  = false,
            -- The GLOBAL entry cannot be removed: it is the fallback every
            -- override resolves against, and a list with no global
            -- assignment in it has nowhere to fall back to. Gated at BOTH
            -- ends -- `hidden` keeps the corner X off the pane, `canRemove`
            -- refuses the action itself -- so no path can take it away.
            hidden  = function(item) return item.kind == "global" end,
            canRemove = function(item)
                if item.kind ~= "global" then return true end
                return false, "The Global assignment cannot be removed."
            end,
            -- The raid collection's confirm wording, for the same action.
            confirm = function(item)
                return "Remove this " .. item.kind .. " override? The "
                    .. item.kind .. " will revert to the active Unit Frame "
                    .. "Layout."
            end,
            -- The assignment goes with the entry. A layout choice kept
            -- behind a removed override is a value that comes back
            -- unannounced the next time that role or spec is added, which
            -- is the state migration 78 exists to clear up -- this is the
            -- same rule applied as the reader works.
            onRemove = function(item)
                local p = UFProfile()
                if not p then return end
                if item.kind == "role" then
                    if p.ufRoleLayouts then p.ufRoleLayouts[item.entryKey] = nil end
                    if p.ufRoleLayoutAssignment then
                        p.ufRoleLayoutAssignment[item.entryKey] = nil
                    end
                else
                    if p.ufSpecLayouts then p.ufSpecLayouts[item.entryKey] = nil end
                    if p.ufSpecLayoutAssignment then
                        p.ufSpecLayoutAssignment[item.entryKey] = nil
                    end
                end
                SyncEnableFlags()
            end,
        },
    }
end
