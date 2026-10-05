-- ============================================================
-- BuzzardFramesOptions: Pages_Layouts.lua
-- The Raid/Party Frames > Layouts section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Layouts.lua
-- (BF:BuildLayoutsOptions): the same settings, the same storage and the
-- same side effects, with the AceConfig args table replaced by one
-- BuzzardPanel page plus one COLLECTION route under
-- `raidPartyFrames/roleSpecLayouts`, drawn as a strip by the `tabs`
-- navigator that node declares:
--
--   roleSpec       "Layouts" -- a TREE-GROUP COLLECTION, which
--                  is the Ace childGroups="tree" wrapper itself: the
--                  precedence note and the two Add dropdowns stay at the
--                  top of the page, and below them one tree card lists
--                  every added role/spec override with the selected
--                  entry's slot cards drawn in the pane beside it. Each
--                  entry is a ROUTE again, so a deep link, a search hit
--                  or a route observer can name one. Add/remove go
--                  through the library's collection calls, so the
--                  rebuild-and-reselect plumbing the Ace file does by
--                  hand (regenerateTreeArgs + deferred SelectGroup) is
--                  the library's own. The LAST entry in that tree is
--                  "Global": the Ace instanceTypes tab's own slot
--                  dropdowns, which are what every override falls back
--                  to, so they are the foot of the list rather than a tab
--                  of their own.
--   management     "Layout Management" -- the Ace Create / Edit / Remove
--                  sub-sub-tabs as CARDS on one page (Create, Rename,
--                  Copy, Remove): each held two to four controls, and
--                  three routes for ten controls is navigation nobody
--                  asked for.
--
-- Storage: rpDB.profile.layouts.* -- instanceLayoutAssignment,
-- flatLayouts, showLayoutAnnounce, roleOverrides, specOverrides. This
-- section takes NO per-Layout scope row and NO Modifying dropdown (a
-- Layout is what it manages; picking one here would change nothing), the
-- same rule the Ace injectSubTab follows for it. Every write lands on the
-- same tables the Ace page writes, with the same invalidation chains in
-- the same order, which is what keeps the two panels in step. The
-- section-tab state the Ace page keeps on BF (_createFlatType,
-- _createFlatCopyFrom, _renameFlatID, _copyFlatFrom, _copyFlatTo) is
-- shared rather than duplicated, so a selection made in one panel shows
-- in the other.
--
-- The source has NO combat guards anywhere in this section, so none are
-- added here -- and the role/spec collection's add/remove declare
-- `combat = false` to switch OFF the library's default combat gate,
-- matching the Ace behavior exactly.
--
-- Ace args keys with no field of their own here, for the audit:
--   tabInstanceTypes / tabLayoutManagement / tabLayoutsWrapper (wrapper)
--                                     -> the three routes
--   tabCreateFlat / tabEditFlat / tabRemoveFlat
--                                     -> the management cards
--   openWorldGroup / dungeonGroup / raidGroup / pvpGroup
--                                     -> the slot cards (both pages)
--   renameHeader / copyHeader / titleHeader
--                                     -> card titles
--   instanceTypesDesc / managementDesc / rootPrecedenceDesc / noFlatsNote
--                                     -> kept, as notes
--   removeSpacer                      -> a pure spacer description,
--                                        dropped (the flow layout needs
--                                        none)
--   removeButton                      -> the member pane's Remove button
--                                        (plus the library's corner X,
--                                        which a tree group puts in the
--                                        PANE's corner rather than on the
--                                        entry's first card -- both run
--                                        the same remove path)
--   _sectionTracker                   -> Ace chrome plumbing (stamps
--                                        BF._currentSection for the Ace
--                                        dialog's own header widgets);
--                                        no panel equivalent
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The layouts profile table. Everything on this section lives under it.
local function Layouts()
    local bf = BF()
    return bf and bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts
end

local function FlatLayouts()
    local l = Layouts()
    return (l and l.flatLayouts) or {}
end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source; a copy here would be a second answer to the same question.
local function DefaultLayouts()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.layouts
end

-- Seeded flats are created by the migration / fresh-install defaults and
-- must not be renamed or deleted, so the user can always rely on their
-- presence as fallbacks. Same list as the Ace builder's SEEDED_FLATS.
local SEEDED_FLATS = {
    flat_party  = true,
    flat_raid20 = true,
    flat_raid30 = true,
    flat_raid40 = true,
}
local function IsSeededFlat(id)
    return SEEDED_FLATS[id] == true
end

-- Generate a unique flat-layout ID (flat_1, flat_2, ...), skipping IDs
-- already present -- the seeded IDs stay recognizable by prefix alone.
local function NewFlatID()
    local fl = FlatLayouts()
    local i = 1
    repeat
        local id = "flat_" .. i
        if not fl[id] then return id end
        i = i + 1
    until false
end

-- Stable order used by every flat dropdown on this section, the Ace
-- flatSorting/sortFlats order: seeded flats first (flat_party,
-- flat_raid20/30/40, in that order), then any other flats alphabetically
-- by id -- each only included if its type matches filterType (nil = any)
-- and, with excludeSeeded, only non-seeded ones at all.
local PREFERRED_SEEDED = { "flat_party", "flat_raid20", "flat_raid30", "flat_raid40" }

local function SortedFlatIDs(filterType, excludeSeeded)
    local fl = FlatLayouts()
    local keys, seen = {}, {}
    if not excludeSeeded then
        for _, id in ipairs(PREFERRED_SEEDED) do
            local layout = fl[id]
            if layout and (filterType == nil or layout.type == filterType) then
                keys[#keys + 1] = id; seen[id] = true
            end
        end
    end
    local extras = {}
    for id, layout in pairs(fl) do
        if not seen[id] then
            local typeOk   = (filterType == nil) or (layout.type == filterType)
            local seededOk = (not excludeSeeded) or (not IsSeededFlat(id))
            if typeOk and seededOk then
                extras[#extras + 1] = id
            end
        end
    end
    table.sort(extras)
    for _, id in ipairs(extras) do keys[#keys + 1] = id end
    return keys
end

-- The same list as {value, text} options, with "None" prepended where a
-- slot allows it (only solo does).
local function FlatOptionsList(filterType, excludeSeeded, includeNone)
    local fl  = FlatLayouts()
    local out = {}
    if includeNone then out[#out + 1] = { value = "none", text = "None" } end
    for _, id in ipairs(SortedFlatIDs(filterType, excludeSeeded)) do
        out[#out + 1] = { value = id, text = fl[id].name or id }
    end
    return out
end

-- Is there any non-seeded flat at all? Used to hide the Remove selector
-- when there is nothing to act on.
local function AnyUserFlats()
    for id in pairs(FlatLayouts()) do
        if not IsSeededFlat(id) then return true end
    end
    return false
end

-- Ace's |cff76CC4B, kept to the digit: the ACTIVE slot's label is tinted
-- green, which is how the Ace dropdown names have always shown it.
local ACTIVE_GREEN = { 0.46, 0.80, 0.29, 1.00 }

-- ── Layouts by Instance Type ───────────────────────────────────
--
-- One dropdown per slot. The slot's required flat type comes from
-- BF.SLOT_TYPE (party-typed slots only offer party flats, raid-typed
-- slots only raid flats), which Options_Layouts.lua publishes on the
-- addon; if that file is ever retired, SLOT_TYPE and SLOT_LABELS must
-- move into a core file first.
local function SlotAssignField(slotKey, label, slotDesc, includeNone)
    return {
        control = "dropdown", label = label,
        desc    = slotDesc,
        -- The undo/reset identity: the shipped assignment for this slot,
        -- from the defaults table rather than restated.
        id      = "instanceSlot_" .. slotKey,
        default = (function()
            local d = DefaultLayouts()
            d = d and d.instanceLayoutAssignment
            return d and d[slotKey]
        end)(),
        -- The green tint marks the slot the addon is USING right now --
        -- the Ace name function, as a label color.
        labelColor = function()
            local bf = BF()
            if bf and bf.GetActiveSlot and bf:GetActiveSlot() == slotKey then
                return ACTIVE_GREEN
            end
        end,
        -- Re-read every open: the list changes as Layouts are created,
        -- renamed and removed on the Management tab.
        options = function()
            local bf = BF()
            local requiredType = bf and bf.SLOT_TYPE and bf.SLOT_TYPE[slotKey]
            return FlatOptionsList(requiredType, false, includeNone)
        end,
        get = function()
            local p = Layouts()
            if not p then return nil end
            if not p.instanceLayoutAssignment then p.instanceLayoutAssignment = {} end
            return p.instanceLayoutAssignment[slotKey]
        end,
        set = function(_, ctx, val)
            local bf = BF()
            local p  = Layouts()
            if not (bf and p) then return end
            if not p.instanceLayoutAssignment then p.instanceLayoutAssignment = {} end
            p.instanceLayoutAssignment[slotKey] = val
            -- Invalidating the raid profile cache and calling RefreshAll
            -- is what makes the live frames rebuild against the
            -- newly-assigned flat; without it the assignment only took
            -- effect when something else (setup mode, zoning) triggered
            -- a refresh.
            bf:InvalidateRaidProfileCache()
            -- If the slot being changed is the currently-active slot, the
            -- active flat just changed. Point _modifyingFlat at the
            -- newly-resolved active flat so the Modifying dropdowns and
            -- Setup Mode's test frames follow the user's intent; without
            -- this sync, setup mode keeps editing the previous flat's
            -- settings via GetModifyingProfile(). No writes to either
            -- flat happen here; only the pointer is retargeted.
            if slotKey == bf:GetActiveSlot() then
                local fl        = p.flatLayouts or {}
                local newActive = bf:ResolveActiveFlat(slotKey)
                if newActive and newActive ~= "none" and fl[newActive] then
                    bf._modifyingFlat = newActive
                else
                    bf._modifyingFlat = fl.flat_party and "flat_party" or nil
                end
            end
            if bf.RefreshAll then bf:RefreshAll() end
            -- When Setup Mode is active, RefreshAll -> ApplyProfile
            -- rebuilds the real frames and re-anchors the test anchor but
            -- does NOT rebuild the test header itself. If the modifying
            -- flat just retargeted has different dimensions, grow
            -- direction or frame count, the header needs reconfiguring to
            -- match -- the same pattern ToggleSetupMode's enter path uses.
            if bf.db and bf.db.global and bf.db.global.setupModeActive then
                if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
                if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
            end
            -- The Ace setter ends in NotifyChangeSafe (plus a poke at the
            -- Ace dialog's own chrome dropdown, which has no panel
            -- equivalent); the panel's whole-page re-read covers both.
            ctx.app:RefreshPage()
        end,
    }
end

-- ── Layout Management: the four actions ────────────────────────

-- Overwrite one flat with all of another's settings. The Ace
-- copyFlatExecute body, verbatim -- including what it does NOT do: no
-- cache invalidation and no RefreshAll (the Ace button never had them
-- either; see the notes).
local function CopyFlatSettings(ctx)
    local bf = BF()
    local p  = Layouts()
    if not (bf and p) then return end
    local fl   = p.flatLayouts or {}
    local from = bf._copyFlatFrom
    local to   = bf._copyFlatTo
    if not from or not to or not fl[from] or not fl[to] then return end
    if fl[from].type ~= fl[to].type then
        print("BuzzardFrames: Cannot copy \"" .. fl[from].name .. "\" into \"" .. fl[to].name .. "\" — Layouts are different types.")
        return
    end
    local toName = fl[to].name
    local copy   = bf:DeepCopy(fl[from])
    copy.name = toName          -- preserve destination's name
    copy.type = fl[to].type     -- and type (sanity)
    -- Wire the metatable __index template on the copy so unmodified keys
    -- fall through to the factory defaults; DeepCopy strips metatables,
    -- and the per-section / per-aura-subcategory fallbacks need re-wiring
    -- too or un-customized keys read nil on the copy. RehydrateFlats runs
    -- the full wiring pass and is idempotent.
    bf:WireFlatDefaults(copy)
    fl[to] = copy
    bf:RehydrateFlats()
    print("BuzzardFrames: Copied settings from \"" .. fl[from].name .. "\" into \"" .. toName .. "\"")
    bf._copyFlatFrom = nil
    bf._copyFlatTo   = nil
    ctx.app:RefreshPage()
end

-- Delete one flat, with the usage checks and the setup-mode escape hatch.
-- The Ace removeFlat set body, verbatim; the confirmation has already
-- happened by the time this runs, as it had there.
local function RemoveFlat(ctx, val)
    local bf = BF()
    local p  = Layouts()
    if not (bf and p) then return end
    local fl = p.flatLayouts or {}
    if not fl[val] or IsSeededFlat(val) then return end
    local name = fl[val].name or val
    -- Usage check: is this flat assigned to any slot?
    local usages = {}
    if p.instanceLayoutAssignment then
        for slotKey, assignedID in pairs(p.instanceLayoutAssignment) do
            if assignedID == val then
                table.insert(usages, (bf.SLOT_LABELS and bf.SLOT_LABELS[slotKey]) or slotKey)
            end
        end
    end
    -- The one live Custom Frame Groups reference to a raid/party flat is
    -- the "Initial Source Layout" dropdown selection, so warn on that.
    -- (Per-group flats are deep copies with no live link.)
    local cfgp = bf.cfgDB and bf.cfgDB.profile
    if cfgp and cfgp.cfgBaseLayoutID == val then
        table.insert(usages, "Custom Frame Groups: Initial Source Layout")
    end
    if #usages > 0 then
        local msg = "Cannot delete Layout \"" .. name .. "\" — it is assigned in " .. #usages .. " slot(s):\n"
        for _, u in ipairs(usages) do
            msg = msg .. "\n• " .. u
        end
        StaticPopup_Show("BUZZARDFRAMES_LAYOUT_IN_USE", msg)
        return
    end
    -- If Setup Mode is on and the flat being deleted is the one currently
    -- being edited, exit Setup Mode first: GetModifyingProfile() would
    -- return nil on the next setup-mode tick otherwise, and any pending
    -- drag/resize MouseUp would try to write anchorX/Y/frameWidth back to
    -- a profile that no longer exists.
    if bf._modifyingFlat == val
       and bf.db and bf.db.global and bf.db.global.setupModeActive
       and bf.ExitSetupMode then
        bf:ExitSetupMode()
    end
    fl[val] = nil
    -- Drop any stale references to the deleted flat.
    local pp = bf.rpDB.profile
    if pp._unpinnedPreviewFlats then pp._unpinnedPreviewFlats[val] = nil end
    if pp._previewUnitsByFlat  then pp._previewUnitsByFlat[val]  = nil end
    if bf._modifyingFlat == val then bf._modifyingFlat = nil end
    print("BuzzardFrames: Removed Layout \"" .. name .. "\"")
    if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    ctx.app:RefreshPage()
end

-- ── The two plain pages ────────────────────────────────────────

local PAGES = {}

-- NO instanceTypes PAGE. The global assignments are not a tab any more:
-- they are the "Global" entry at the foot of the Layouts tree, built from
-- the same SlotAssignField calls in GlobalSlotCards below. One list of
-- slots, read the same way whether you are setting the global assignment
-- or a Healer's override, instead of a tab and a tree saying the same
-- thing in two shapes.

function PAGES.management()
    return {
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Create, rename, copy, or remove Layouts." },
            }},

            -- The Ace Create sub-tab, as a card.
            { title = "Create", preset = "form", fields = {
                -- Ace: createFlatType.
                { control = "dropdown", label = "Type",
                  desc = "Party Layouts are used for 5-player groups (Solo, "
                      .. "Party, Dungeon, Arena). Raid Layouts are used "
                      .. "for raid groups and battlegrounds.",
                  options = { { value = "party", text = "Party" },
                              { value = "raid",  text = "Raid"  } },
                  get = function()
                      local bf = BF()
                      return (bf and bf._createFlatType) or "party"
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._createFlatType = val
                      -- Reset copy-from when type changes; it may no longer
                      -- be valid under the new type.
                      bf._createFlatCopyFrom = nil
                      ctx.app:RefreshPage()
                  end },

                -- Ace: createFlatCopyFrom.
                { control = "dropdown", label = "Copy Settings From",
                  desc = "Choose an existing Layout of the same type to copy "
                      .. "settings from. Defaults to the seeded Layout for "
                      .. "the chosen type.",
                  options = function()
                      local bf = BF()
                      local t  = (bf and bf._createFlatType) or "party"
                      return FlatOptionsList(t, false)
                  end,
                  get = function()
                      local bf = BF()
                      if not bf then return nil end
                      local t = bf._createFlatType or "party"
                      local defaultID = (t == "party") and "flat_party" or "flat_raid40"
                      local chosen = bf._createFlatCopyFrom
                      local fl = FlatLayouts()
                      if chosen and fl[chosen] and fl[chosen].type == t then return chosen end
                      if fl[defaultID] then return defaultID end
                      -- Fallback: first flat of the right type.
                      for id, layout in pairs(fl) do
                          if layout.type == t then return id end
                      end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._createFlatCopyFrom = val
                      ctx.app:RefreshPage()
                  end },

                -- Ace: createFlatName. `submit = true` draws the same
                -- localized OK button the Ace input had; Enter commits too.
                { control = "text", label = "Create Layout", submit = "Create",
                  desc = "Type a name and press Enter (or click OK) to "
                      .. "create the new Layout.",
                  get = function() return "" end,
                  set = function(_, ctx, val)
                      if not val or val:match("^%s*$") then return end
                      local bf = BF()
                      local p  = Layouts()
                      if not (bf and p) then return end
                      p.flatLayouts = p.flatLayouts or {}
                      -- Name-uniqueness check across all flats.
                      for _, layout in pairs(p.flatLayouts) do
                          if layout.name == val then
                              print("BuzzardFrames: A Layout named \"" .. val .. "\" already exists.")
                              return
                          end
                      end
                      local newType = bf._createFlatType or "party"
                      local src     = bf._createFlatCopyFrom
                                    or ((newType == "party") and "flat_party" or "flat_raid40")
                      local newID   = NewFlatID()
                      local flat
                      if p.flatLayouts[src] and p.flatLayouts[src].type == newType then
                          flat = bf:DeepCopy(p.flatLayouts[src])
                      else
                          -- Source invalid/missing -> seed from factory
                          -- defaults.
                          if newType == "party" then
                              flat = bf:CreateFlatPartyLayout(val)
                          else
                              flat = bf:CreateFlatRaidLayout(val, -260, -200)
                          end
                      end
                      flat.name = val
                      flat.type = newType
                      -- Wire the __index template so unmodified keys fall
                      -- through to the factory defaults -- required for any
                      -- newly-created flat.
                      bf:WireFlatDefaults(flat)
                      -- Deliberately NO forced-off of cast bars here (owner
                      -- rule 2026-08-13): copies are faithful; the raid
                      -- seed-OFF rule applies only to the global fan-out
                      -- seed and to Custom Frame Groups.
                      p.flatLayouts[newID] = flat
                      -- DeepCopy strips metatables; RehydrateFlats re-runs
                      -- the full wiring pass (top-level template plus the
                      -- per-section and per-aura-subcategory fallbacks) and
                      -- is idempotent.
                      bf:RehydrateFlats()
                      -- New flat has no _auraCache yet; mark it dirty so
                      -- the next UpdateAuraSizeCache builds one.
                      if bf.InvalidateFlatAuraCache then bf:InvalidateFlatAuraCache(flat) end
                      bf._createFlatCopyFrom = nil
                      local srcName = (p.flatLayouts[src] and p.flatLayouts[src].name) or src
                      print("BuzzardFrames: Created Layout \"" .. val .. "\" (" .. newType .. ", copied from \"" .. srcName .. "\")")
                                        if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
                      ctx.app:RefreshPage()
                  end },
            }},

            -- The Ace Edit sub-tab's first header, as a card.
            { title = "Rename Layout", preset = "form", fields = {
                -- Ace: renameFlatSelect.
                { control = "dropdown", label = "Rename Layout",
                  desc = "Select a Layout to rename.",
                  options = function() return FlatOptionsList(nil, false) end,
                  get = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      if bf and bf._renameFlatID and fl[bf._renameFlatID] then
                          return bf._renameFlatID
                      end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._renameFlatID = val
                      ctx.app:RefreshPage()
                  end },

                -- Ace: renameFlatInput.
                { control = "text", label = "New Name", submit = "Rename",
                  desc = "Type a new name and press Enter (or click OK) to "
                      .. "rename the selected Layout.",
                  hidden = function()
                      local bf = BF()
                      return not (bf and bf._renameFlatID)
                  end,
                  get = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      local id = bf and bf._renameFlatID
                      if id and fl[id] then return fl[id].name or "" end
                      return ""
                  end,
                  set = function(_, ctx, val)
                      if not val or val:match("^%s*$") then return end
                      local bf = BF()
                      local p  = Layouts()
                      if not (bf and p) then return end
                      local fl = p.flatLayouts or {}
                      local id = bf._renameFlatID
                      if not id or not fl[id] then return end
                      for oid, layout in pairs(fl) do
                          if oid ~= id and layout.name == val then
                              print("BuzzardFrames: A Layout named \"" .. val .. "\" already exists.")
                              return
                          end
                      end
                      local oldName = fl[id].name
                      fl[id].name   = val
                      print("BuzzardFrames: Renamed Layout \"" .. oldName .. "\" to \"" .. val .. "\"")
                      ctx.app:RefreshPage()
                  end },
            }},

            -- The Ace Edit sub-tab's second header, as a card.
            { title = "Copy Layout Settings", preset = "form", fields = {
                -- Ace: copyFlatFrom.
                { control = "dropdown", label = "Copy From",
                  desc = "Select the source Layout to copy settings from.",
                  options = function() return FlatOptionsList(nil, false) end,
                  get = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      if bf and bf._copyFlatFrom and fl[bf._copyFlatFrom] then
                          return bf._copyFlatFrom
                      end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._copyFlatFrom = val
                      -- Reset destination when source changes; it may no
                      -- longer share the source's type.
                      bf._copyFlatTo = nil
                      ctx.app:RefreshPage()
                  end },

                -- Ace: copyFlatTo.
                { control = "dropdown", label = "To",
                  desc = "Select the destination Layout to overwrite. Only "
                      .. "Layouts of the same type as the source are shown.",
                  options = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      local fromID = bf and bf._copyFlatFrom
                      if not fromID or not fl[fromID] then return {} end
                      local srcType = fl[fromID].type
                      local out = {}
                      for _, id in ipairs(SortedFlatIDs(srcType, false)) do
                          if id ~= fromID then
                              out[#out + 1] = { value = id, text = fl[id].name or id }
                          end
                      end
                      return out
                  end,
                  get = function()
                      local bf = BF()
                      return bf and bf._copyFlatTo
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._copyFlatTo = val
                      ctx.app:RefreshPage()
                  end },

                -- Ace: copyFlatExecute. The confirm wording is the Ace
                -- one, through the panel's own dialog.
                { control = "button", label = "Copy Settings",
                  desc = "Overwrite the destination Layout with all settings "
                      .. "from the source Layout.",
                  disabled = function()
                      local bf = BF()
                      return not (bf and bf._copyFlatFrom and bf._copyFlatTo)
                  end,
                  onClick = function(_, ctx)
                      local bf = BF()
                      if not bf then return end
                      local fl = FlatLayouts()
                      local fromName = bf._copyFlatFrom and fl[bf._copyFlatFrom] and fl[bf._copyFlatFrom].name or "?"
                      local toName   = bf._copyFlatTo   and fl[bf._copyFlatTo]   and fl[bf._copyFlatTo].name   or "?"
                      ctx.app:Confirm("Copy all settings from \"" .. fromName
                          .. "\" into \"" .. toName .. "\"? This will overwrite "
                          .. "all of \"" .. toName .. "\"'s settings.",
                          function() CopyFlatSettings(ctx) end)
                  end },
            }},

            -- The Ace Remove sub-tab, as a card.
            { title = "Remove", preset = "form", fields = {
                -- Ace: removeFlat. The Ace dropdown deleted on the PICK --
                -- opening a list and moving down it was the act of
                -- destroying a Layout, with a confirmation as the only thing
                -- between a mis-click and a gone Layout. Here the pick only
                -- SELECTS; the Remove button below is what asks. Two
                -- deliberate acts for a destructive one, and the reader can
                -- read the name they chose before committing to it.
                { control = "dropdown", label = "Remove Layout",
                  desc = "Select a Layout to delete. Seeded Layouts cannot "
                      .. "be deleted.",
                  hidden = function() return not AnyUserFlats() end,
                  options = function() return FlatOptionsList(nil, true) end,
                  get = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      local id = bf and bf._removeFlatID
                      -- Only if it is still there: the Layout may have been
                      -- deleted from here, or renamed away, since the pick.
                      if id and fl and fl[id] then return id end
                      return nil
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf._removeFlatID = val
                      -- The button below turns on with the selection.
                      ctx.app:RefreshPage()
                  end },

                { control = "button", text = "Remove", danger = true,
                  desc = "Permanently delete the selected Layout.",
                  hidden = function() return not AnyUserFlats() end,
                  disabled = function()
                      local bf = BF()
                      local fl = FlatLayouts()
                      local id = bf and bf._removeFlatID
                      return not (id and fl and fl[id])
                  end,
                  onClick = function(_, ctx)
                      local bf = BF()
                      local fl = FlatLayouts()
                      local id = bf and bf._removeFlatID
                      if not (id and fl and fl[id]) then return end
                      local name = fl[id].name or id
                      ctx.app:Confirm("Are you sure you want to delete Layout \""
                          .. name .. "\"? This cannot be undone.",
                          function()
                              RemoveFlat(ctx, id)
                              -- Cleared only if it actually went: RemoveFlat
                              -- REFUSES a Layout that is still assigned to a
                              -- slot, and a dropdown that empties itself
                              -- after a refusal says the opposite of what
                              -- the popup just said.
                              local now = FlatLayouts()
                              if not (now and now[id]) then
                                  bf._removeFlatID = nil
                              end
                          end)
                  end },
                -- Ace: noFlatsNote.
                { control = "note", wide = true,
                  hidden = AnyUserFlats,
                  text = "No custom Layouts to remove. Seeded Layouts "
                      .. "(Party, Raid (40), etc.) cannot be deleted." },
            }},
        },
    }
end

-- ── Role/Spec Layouts: the collection ──────────────────────────
--
-- The Ace tabLayoutsWrapper: role/spec override entries, each an 11-slot
-- override grid. Presence of the entry (the _present marker) is the sole
-- enable gate; there are no toggles. Spec overrides take precedence over
-- role overrides (BF:ResolveActiveFlat).

-- Fixed role definitions, in the order the Ace tree showed them.
local ROLE_DEFS = {
    { key = "TANK",    label = "Tank",   atlas = "roleicon-tiny-tank"   },
    { key = "HEALER",  label = "Healer", atlas = "roleicon-tiny-healer" },
    { key = "DAMAGER", label = "DPS",    atlas = "roleicon-tiny-dps"    },
}

-- The four slot cards of the GLOBAL entry -- what the "Layouts by Instance
-- Type" tab used to be, verbatim: same fields, same descriptions, same
-- order. It is a member of the tree now rather than a tab of its own,
-- because "which Layout for a raid" and "which Layout for a Healer in a
-- raid" are the same question asked at two levels, and the overrides
-- already read as a list of entries.
local function GlobalSlotCards()
    return {
        { title = "Open World", preset = "form", fields = {
            SlotAssignField("solo",           "Solo",              "Layout used when you are alone in the open world.", true),
            SlotAssignField("openWorldParty", "Party",             "Layout used when you are in a 5-player party in the open world."),
            SlotAssignField("raidOpen",       "Raid (Open World)", "Layout used when you are in a raid group in the open world."),
        }},
        { title = "Dungeon", preset = "form", fields = {
            SlotAssignField("dungeon", "Dungeon", "Layout used when you are in a 5-player dungeon or party."),
        }},
        { title = "Raid", preset = "form", fields = {
            SlotAssignField("raid20", "Raid (20 Man)", "Layout used when you are in a 20-player raid instance."),
            SlotAssignField("raid25", "Raid (25 Man)", "Layout used when you are in a 25-player raid instance."),
            SlotAssignField("raid30", "Raid (30 Man)", "Layout used when you are in a 30-player raid instance."),
            SlotAssignField("raid40", "Raid (40 Man)", "Layout used when you are in a 40-player raid instance."),
        }},
        { title = "PvP", preset = "form", fields = {
            SlotAssignField("arena", "Arena",                 "Layout used when you are in an Arena match."),
            SlotAssignField("bg15",  "Battleground (15 Man)", "Layout used when you are in a 15-player Battleground."),
            SlotAssignField("bg40",  "Battleground (40 Man)", "Layout used when you are in a 40-player Battleground."),
        }},
    }
end

-- The overrides table for one entry, created on first touch exactly as
-- the Ace overridesTable does.
local function OverridesTable(kind, entryKey)
    local p = Layouts()
    if not p then return nil end
    if kind == "role" then
        p.roleOverrides = p.roleOverrides or { HEALER = {}, TANK = {}, DAMAGER = {} }
        p.roleOverrides[entryKey] = p.roleOverrides[entryKey] or {}
        return p.roleOverrides[entryKey]
    else
        p.specOverrides = p.specOverrides or {}
        p.specOverrides[entryKey] = p.specOverrides[entryKey] or {}
        return p.specOverrides[entryKey]
    end
end

-- Options for one slot-override dropdown: "Use global setting (<name>)"
-- first (naming what the Layouts-by-Instance-Type tab assigns to this
-- slot right now), "None" for the solo slot only, then the type-matching
-- flats in the section's stable order.
local function OverrideSlotOptions(slotKey, includeNone)
    local bf = BF()
    local fl = FlatLayouts()
    local l  = Layouts()
    local ila = (l and l.instanceLayoutAssignment) or {}
    local required = bf and bf.SLOT_TYPE and bf.SLOT_TYPE[slotKey]
    local globalID = ila[slotKey]
    local globalName
    if not globalID or globalID == "none" then
        globalName = "None"
    elseif fl[globalID] then
        globalName = fl[globalID].name or globalID
    else
        globalName = globalID
    end
    local out = { { value = "__global", text = "Use global setting (" .. globalName .. ")" } }
    if includeNone then out[#out + 1] = { value = "none", text = "None" } end
    for _, id in ipairs(SortedFlatIDs(required, false)) do
        out[#out + 1] = { value = id, text = fl[id].name or id }
    end
    return out
end

-- One per-slot dropdown for a role or spec entry. Absence of the key is
-- "use the global assignment", so "__global" is the sentinel the Ace
-- dropdown used and the value a reset restores.
local function OverrideSlotField(kind, entryKey, slotKey, label)
    local includeNone = (slotKey == "solo")
    return {
        control = "dropdown", label = label,
        id      = kind .. "Override_" .. entryKey .. "_" .. slotKey,
        default = "__global",
        options = function() return OverrideSlotOptions(slotKey, includeNone) end,
        get = function()
            local ot = OverridesTable(kind, entryKey)
            return (ot and ot[slotKey]) or "__global"
        end,
        set = function(_, _, val)
            local bf = BF()
            local ot = OverridesTable(kind, entryKey)
            if not (bf and ot) then return end
            ot[slotKey] = (val == "__global") and nil or val
            bf:InvalidateRaidProfileCache()
            if bf.RefreshAll then bf:RefreshAll() end
        end,
    }
end

-- The collection's source: present role overrides in fixed
-- Tank -> Healer -> DPS order, then present spec overrides alphabetically
-- by spec name -- the Ace buildTreeArgs order.
local function RoleSpecMembers()
    local l = Layouts()
    if not l then return {} end
    local bf  = BF()
    local ro  = l.roleOverrides or {}
    local so  = l.specOverrides or {}
    local out = {}
    for _, def in ipairs(ROLE_DEFS) do
        if ro[def.key] and ro[def.key]._present then
            local icon = (CreateAtlasMarkup and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
            out[#out + 1] = { kind = "role", entryKey = def.key,
                              id = "role_" .. def.key,
                              title = icon .. " " .. def.label }
        end
    end
    local specList = {}
    for idStr, entry in pairs(so) do
        if type(entry) == "table" and entry._present then
            local id = tonumber(idStr)
            local s  = bf and bf.specByID and bf.specByID[id]
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
    -- GLOBAL, always and always LAST: it is what every override above it
    -- falls back to, and a fallback belongs at the foot of the list rather
    -- than at its head. Not sourced from the profile like the others --
    -- there is nothing to add or remove, so it is simply always there.
    out[#out + 1] = { kind = "global", entryKey = "global", id = "global",
                      title = "Global" }
    return out
end

-- One member's cards -- flat, as the Ace overrideGroup was: the title
-- header and the four slot cards. No memberTabs: an Ace override entry had
-- no sub-sub-tabs to split across a strip. The Ace Remove button is gone --
-- see the note at the end of the template.
--
-- The first card is the Ace titleHeader, the entry's own label and its
-- type badge on one line, colors kept to the digit. A tree group's pane
-- draws exactly what the template returns and nothing else -- the entry's
-- name is on the row it was clicked from, not on the pane -- so the pane
-- states its own heading, the same shape the Buff List's pane uses.
local function RoleSpecMemberPage(mctx)
    local item = mctx.item
    -- The GLOBAL entry: the same heading shape, then the slot cards the
    -- instance-type tab drew. `db`/`defaults` come with it because these
    -- fields write the profile's own instanceLayoutAssignment.
    if item.kind == "global" then
        local groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true, font = "GameFontNormalLarge",
                  color = { 1, 1, 1, 1 }, text = "Global" },
                -- The explanation at NOTE size, under the heading rather
                -- than trailing it: it is a sentence to read, and at the
                -- heading's size it competed with the name.
                { control = "note", wide = true,
                  text = "These settings are active unless an override "
                      .. "exists for the current Role or Spec." },
            }},
        }
        for _, g in ipairs(GlobalSlotCards()) do groups[#groups + 1] = g end
        return { db = function() return Layouts() or {} end,
                 defaults = DefaultLayouts, groups = groups }
    end

    local badge = (item.kind == "role")
        and "|cff7f77ddRole override|r"
        or  "|cff1d9e75Spec override|r"
    local function Slot(slotKey, label)
        return OverrideSlotField(item.kind, item.entryKey, slotKey, label)
    end
    return { groups = {
        { preset = "bare", fields = {
            { control = "note", wide = true, font = "GameFontNormalLarge",
              color = { 1, 1, 1, 1 },
              text = item.title .. "    " .. badge },
        }},
        { title = "Open World", preset = "form", fields = {
            Slot("solo",           "Solo"),
            Slot("openWorldParty", "Party"),
            Slot("raidOpen",       "Raid (Open World)"),
        }},
        { title = "Dungeon", preset = "form", fields = {
            Slot("dungeon", "Dungeon"),
        }},
        { title = "Raid", preset = "form", fields = {
            Slot("raid20", "Raid (20 Man)"),
            Slot("raid25", "Raid (25 Man)"),
            Slot("raid30", "Raid (30 Man)"),
            Slot("raid40", "Raid (40 Man)"),
        }},
        { title = "PvP", preset = "form", fields = {
            Slot("arena", "Arena"),
            Slot("bg15",  "Battleground (15 Man)"),
            Slot("bg40",  "Battleground (40 Man)"),
        }},
        -- NO Remove BUTTON. The Ace entry carried one (removeButton, at the
        -- bottom of the group) because that surface had no corner
        -- affordance; this pane has the X in its top right, running the
        -- very same path -- confirmation included. Two controls for one
        -- action is one of them the reader has to rule out, and the button
        -- was the one buried under four cards of slots. Same call the Buff
        -- List made.
    }}
end

-- The collection's own page: the precedence note and the two Add
-- dropdowns (the Ace wrapper's root page), and then the tree card that
-- lists the entries with the selected one's pane beside it.
local function RoleSpecRootPage()
    -- `db`/`defaults`: the Announce switch below is BOUND, and the table it
    -- binds against is the layouts table itself -- exactly where the Ace
    -- setter wrote, and what the instance-type page declared for it.
    return {
      db       = function() return Layouts() or {} end,
      defaults = DefaultLayouts,
      groups = {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "If conflicting Role and Spec overrides are defined "
                  .. "(e.g. both Healer and Resto Shaman are defined and "
                  .. "have different settings), the Spec overrides take "
                  .. "priority." },

            -- Ace: addRoleDropdown. Adding is an ACTION, so the dropdown
            -- never shows a current value; it lists only roles without an
            -- entry yet, in the fixed Tank -> Healer -> DPS order.
            { control = "dropdown", label = "Add Role Overrides",
              labelPlacement = "above",
              options = function()
                  local out = {}
                  local p = Layouts()
                  if not p then return out end
                  p.roleOverrides = p.roleOverrides or { HEALER = {}, TANK = {}, DAMAGER = {} }
                  for _, def in ipairs(ROLE_DEFS) do
                      if not (p.roleOverrides[def.key] and p.roleOverrides[def.key]._present) then
                          local icon = (CreateAtlasMarkup and CreateAtlasMarkup(def.atlas, 16, 16)) or ""
                          out[#out + 1] = { value = def.key, text = icon .. " " .. def.label }
                      end
                  end
                  return out
              end,
              get = function() return nil end,
              set = function(_, ctx, val)
                  ctx.app:CollectionAdd("roleSpec", "role", val)
              end },

            -- Ace: addSpecDropdown. Specs without an entry, alphabetical
            -- by name.
            { control = "dropdown", label = "Add Spec Overrides",
              labelPlacement = "above",
              options = function()
                  local out = {}
                  local bf = BF()
                  local p  = Layouts()
                  if not (bf and p) then return out end
                  p.specOverrides = p.specOverrides or {}
                  local list = {}
                  if bf.specData then
                      for _, s in ipairs(bf.specData) do
                          local idStr = tostring(s.id)
                          local entry = p.specOverrides[idStr]
                          if not (type(entry) == "table" and entry._present) then
                              list[#list + 1] = { id = idStr, name = s.name, icon = s.icon }
                          end
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
                  ctx.app:CollectionAdd("roleSpec", "spec", val)
              end },

            -- The Ace showLayoutAnnounce, which rode the instance-type tab
            -- until that tab became the Global entry. It is about layout
            -- SWITCHING rather than about any one assignment, so it sits on
            -- the collection's own page with the two Add dropdowns instead
            -- of inside the Global entry beside the slots.
            { control = "switch", label = "Announce Layout changes",
              wide = true, bind = "showLayoutAnnounce",
              desc = "Shows a private notification in your chat window "
                  .. "when the addon automatically switches your layout." },
        }},

        -- The list, and whichever entry is selected -- the Ace
        -- childGroups="tree" wrapper itself. Last, so the precedence note
        -- and the two Add dropdowns are what the reader meets first and
        -- what stays put while they move through the list; ACD replaced
        -- them with the selected child's args instead, which is the one
        -- deliberate divergence here and the Buff List's shape too.
        --
        -- 175 wide: the Ace tree group's default column, which is the
        -- width this list has always been read at. `height = "fill"`: the
        -- card takes whatever the panel has left below the cards above it
        -- and follows a resize, which is how the Ace tree sat -- it ran to
        -- the bottom of the dialog rather than stopping at a fixed height
        -- with the page scrolling underneath it. `listTopPad = 0`: the
        -- card's own top pad is all the room the first row needs, and it
        -- is the same pad the pane uses above the entry's heading, so the
        -- two columns start level. `flush = 2`: the list belongs to the
        -- cards above it, but a hairline between them keeps the two
        -- surfaces legible as two.
        --
        -- The route is the collection's own key: raidPartyFrames (the
        -- section) / roleSpecLayouts (the Layouts node) / roleSpec (the
        -- collection's id below).
        { preset = "form", flush = 2,
          tree = { route = "raidPartyFrames/roleSpecLayouts/roleSpec",
                   width = 175, height = "fill", minHeight = 240,
                   listTopPad = 0 } },
    }}
end

-- ── Publishing ─────────────────────────────────────────────────
--
-- The one plain subtab, for Panel.lua to build routes from -- and the
-- collection node as a function of its own, because a collection is a
-- ROUTE NODE rather than a page and carries its member machinery with it.
BuzzardFramesOptions.LAYOUTS_SUBTABS = {
    { id = "management",    title = "Layout Management" },
}

function BuzzardFramesOptions:LayoutsPage(subtabId)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end
    return build()
end

-- The third subtab: the Role/Spec Layouts collection node, spliced into
-- the route children AFTER the two above. A TREE GROUP -- the Ace
-- wrapper's own childGroups = "tree" -- so the entries are ROUTES and the
-- list that selects them is a CARD on this page rather than chrome. That
-- is what makes the shape available under a section that already carries
-- a tab strip: a tree group asks for no navigator and no second strip, so
-- nothing lands on top of the section's own (Panel.lua's rule about
-- nesting one contextual strip inside another).
--
-- No `memberTabs`: an Ace override entry was one flat pane of four slot
-- grids and a Remove button, with no sub-sub-tabs to split it across. No
-- `sections` either: the Ace tree carried no headings, just roles (order
-- 1-3) then specs (order 100+i), which RoleSpecMembers already emits in
-- that order.
--
-- `combat = false` on add and remove switches OFF the library's default
-- combat gate: the Ace page allowed both in combat, and matching it is
-- what keeps the two panels agreeing about what is possible when.
function BuzzardFramesOptions:LayoutsRoleSpecRoute()
    return {
        node        = "collection",
        id          = "roleSpec",
        -- "Layout Assignments", not "Role/Spec Layouts": the tab carries
        -- the global assignment as well as the overrides, so naming it for
        -- the overrides alone names half of it -- and not plain "Layouts"
        -- either, which is what the SECTION is called. What every entry
        -- here does is assign a Layout to a situation.
        title       = "Layout Assignments",
        treeGroup   = true,
        -- The entries are listed BY THE PAGE, in the tree card above. The
        -- rail listing them as well would be the same list twice.
        railChildren = false,
        page        = RoleSpecRootPage,
        source      = RoleSpecMembers,
        key         = function(item) return item.id end,
        memberTitle = function(item) return item.title end,
        template    = RoleSpecMemberPage,
        add = {
            combat = false,
            -- Entries are routes, so adding LANDS on the new one with its
            -- pane already drawn -- the deferred SelectGroup the Ace file
            -- fires onto the freshly-minted tree child.
            select = true,
            onAdd  = function(kind, val)
                local bf = BF()
                local p  = Layouts()
                if not (bf and p) then return end
                if kind == "role" then
                    p.roleOverrides = p.roleOverrides or { HEALER = {}, TANK = {}, DAMAGER = {} }
                    p.roleOverrides[val] = p.roleOverrides[val] or {}
                    p.roleOverrides[val]._present = true
                else
                    p.specOverrides = p.specOverrides or {}
                    p.specOverrides[val] = p.specOverrides[val] or {}
                    p.specOverrides[val]._present = true
                end
                bf:InvalidateRaidProfileCache()
                if bf.RefreshAll then bf:RefreshAll() end
                return { kind = kind, entryKey = val, id = kind .. "_" .. val }
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
            -- The Ace removeButton's confirm wording, verbatim.
            confirm = function(item)
                return "Remove this " .. item.kind .. " override? The "
                    .. item.kind .. " will revert to using global settings."
            end,
            onRemove = function(item)
                local bf = BF()
                local p  = Layouts()
                if not (bf and p) then return end
                if item.kind == "role" then
                    if p.roleOverrides then p.roleOverrides[item.entryKey] = nil end
                else
                    if p.specOverrides then p.specOverrides[item.entryKey] = nil end
                end
                bf:InvalidateRaidProfileCache()
                if bf.RefreshAll then bf:RefreshAll() end
            end,
        },
    }
end
