-- ============================================================
-- BuzzardFramesOptions: Pages_Preview.lua
-- The Raid/Party Frames > Preview section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Preview/Options_Preview.lua
-- (BF:BuildPreviewOptions): the same settings, the same storage and the
-- same side effects, with the AceConfig childGroups="tab" section
-- replaced by four BuzzardPanel pages -- one per subtab, each a route of
-- its own under `raidPartyFrames/preview`, drawn as a strip by the
-- `tabs` navigator that node declares. The Ace tabs map one to one:
-- tabPreview -> preview, tabPreviewUnits -> previewUnits,
-- tabPreviewAuras -> previewAuras, tabSpecialOptions -> specialOptions
-- (the route id is the STORAGE section key, which is why the last one is
-- not called "experimental" -- ShouldShowPreviewAuras and friends match
-- on it).
--
-- Preview takes NO per-Layout scope row: nothing on these pages is a
-- Layout setting. Storage is a mix, exactly as in the source --
-- BF().db.global for the toggles and counts, rpDB.profile._previewUnits-
-- ByFlat / _unpinnedPreviewFlats / _hiddenCFPreviewSlots for the preview
-- set, db.profile.previewUnits for the Custom Frame slots,
-- rpDB.profile.layouts for the experimental fitting keys, and runtime
-- BF._preview* flags for the status simulators. Both panels touch the
-- same keys through the same accessors, which is what keeps them in
-- step. The preview refresh functions themselves (RefreshPreviewFrames,
-- RefreshPreviewDummyAuras, HidePreviewFrames, ...) stay in
-- BuzzardFrames and are called, never copied.
--
-- SECTION TRACKING AND THE DYNAMIC TAB, the two things the Ace page did
-- with hidden description nodes, are done with this shell's own
-- machinery instead:
--
-- * The Ace _sectionTracker descriptions (one per tab) set
--   BF._currentSection as a side effect of RENDERING, and the invisible
--   previewRenderer description re-drew the preview frames the same way.
--   Here that is a route observer per subtab -- see EnterSection /
--   EnsureObservers -- plus one inline call on the first visit, because
--   the page function builds before its observer exists. The page
--   function is also resolved by the search indexer, so the inline call
--   is gated on the route actually being active.
--
-- * The Ace Preview Units tab REGENERATES its args whenever the preview
--   set changes (BF._regeneratePreviewArgs). Here the page is a lazy
--   function: it builds from the live set each time it is constructed,
--   the actions that change the set call ctx.app:Invalidate("previewSet")
--   to force that construction, and the previewUnits route observer
--   compares a signature of the built set against the live one on every
--   entry -- so a flat created, deleted or renamed ANYWHERE (the Ace
--   Layouts page included) is picked up the next time the tab is opened,
--   without this file hooking anything.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- ── Defaults ───────────────────────────────────────────────────
--
-- What a key resets TO. Buzzard Frames' own defaults tables are the
-- single source: a copy here would be a second answer to the same
-- question, and the two would part company the first time a default
-- changed.

local function DefaultG(key)
    local bf = BF()
    local d  = bf and bf.defaults
    d = d and d.global
    return d and d[key]
end

local function DefaultLayoutsKey(key)
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile and d.profile.layouts
    return d and d[key]
end

-- The Preview Auras page binds straight into db.global -- the storage is
-- already a plain table there, and a bind is what makes right-click Undo
-- and Reset work without every field declaring anything.
local function GlobalDB()
    local bf = BF()
    return bf and bf.db and bf.db.global
end

local function GlobalDefaults()
    local bf = BF()
    local d  = bf and bf.defaults
    return d and d.global
end

-- ── The preview set ────────────────────────────────────────────

local MAX_CF_PREVIEWS = 4

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- The active preview set in stable display order -- the panel's copy of
-- the source's computeActivePreviewOrder, kept rule for rule. Pinning
-- model: every flat is pinned by default; "Hide this preview" adds an
-- entry to rpDB.profile._unpinnedPreviewFlats, and a flat is active
-- whenever it has no entry there. Order is purely structural -- seeded
-- flats in fixed order, then the rest alphabetically -- so the tab and
-- the frames on screen stay put as the user switches editing flats. The
-- same rule lives in Options_PreviewSystem.lua's ComputeActivePreviewSet
-- and the source builder; the three must stay in lockstep.
local function ActivePreviewOrder()
    local bf = BF()
    if not bf then return {} end
    local fl       = FlatLayouts()
    local unpinned = (bf.rpDB and bf.rpDB.profile._unpinnedPreviewFlats) or {}

    local active = {}
    for id in pairs(fl) do
        if not unpinned[id] then active[id] = true end
    end

    local order, seen = {}, {}
    local preferred = { "flat_party", "flat_raid20", "flat_raid30", "flat_raid40" }
    for _, id in ipairs(preferred) do
        if active[id] and not seen[id] then
            order[#order + 1] = id
            seen[id]          = true
        end
    end
    local extras = {}
    for id in pairs(active) do
        if not seen[id] then extras[#extras + 1] = id end
    end
    table.sort(extras)
    for _, id in ipairs(extras) do order[#order + 1] = id end
    return order
end

-- The Custom Frame Group preview slots that should SHOW: slot enabled
-- and not hidden via its own Remove button. The Ace page expressed this
-- as a `hidden` function per group; a panel group cannot hide, so
-- membership is decided when the page is built and rebuilt on
-- Invalidate.
local function VisibleCFSlots()
    local bf = BF()
    local pv = bf and bf._preview
    local enabledCFs = (pv and pv.EnabledCFGroups and pv.EnabledCFGroups()) or {}
    local hidden = (bf and bf.rpDB and bf.rpDB.profile._hiddenCFPreviewSlots) or {}
    local out = {}
    for cfSlot = 1, MAX_CF_PREVIEWS do
        local entry = enabledCFs[cfSlot]
        if entry and hidden["cf" .. cfSlot] ~= true then
            out[#out + 1] = { slot = cfSlot, entry = entry }
        end
    end
    return out
end

-- What the Preview Units page was BUILT from, as a string. Compared
-- against the live set on every entry to the tab: a mismatch means a
-- flat was created, deleted, renamed, pinned or unpinned somewhere this
-- file did not see, and the page rebuilds itself.
local function UnitsSignature()
    local fl = FlatLayouts()
    local parts = {}
    for _, id in ipairs(ActivePreviewOrder()) do
        parts[#parts + 1] = id .. "=" .. tostring(fl[id] and fl[id].name)
    end
    for _, e in ipairs(VisibleCFSlots()) do
        parts[#parts + 1] = "cf" .. e.slot .. "="
            .. tostring(e.entry.group and e.entry.group.name)
    end
    return table.concat(parts, ";")
end

-- ── Section tracking ───────────────────────────────────────────
--
-- The subtab id IS the _currentSection key (that is why the ids are what
-- they are), and the body is the Ace _sectionTracker's, including its
-- combat gate. Entering the first tab also re-draws the preview frames,
-- which is what the Ace page's invisible previewRenderer description did
-- on every render -- gated on showPreview exactly as its `hidden` was.
local function EnterSection(subtabId)
    local bf = BF()
    if not bf then return end
    if bf._currentSection ~= subtabId then
        bf._currentSection = subtabId
        if bf.RefreshPreviewDummyAuras and not InCombatLockdown() then
            bf:RefreshPreviewDummyAuras()
        end
    end
    if subtabId == "preview"
       and bf.db and bf.db.global.showPreview ~= false then
        if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    end
end

-- The signature the Preview Units page was last built from. Declared
-- ABOVE EnsureObservers so the observer closure captures it.
local builtUnitsSig = nil

local observersArmed = false

local function EnsureObservers(app)
    if observersArmed or not app then return end
    observersArmed = true
    local subtabs = { "preview", "previewUnits", "previewAuras", "specialOptions" }
    for _, id in ipairs(subtabs) do
        app:RegisterRouteObserver("raidPartyFrames/preview/" .. id,
            function(isActive, _, appNow)
                if not isActive then return end
                EnterSection(id)
                -- Self-heal: the page tables are memoised by the
                -- library, so a set changed elsewhere is caught here, on
                -- entry, and forces a rebuild.
                if id == "previewUnits" and builtUnitsSig
                   and builtUnitsSig ~= UnitsSignature() then
                    appNow:Invalidate("previewSet")
                end
            end)
    end
end

-- ── Shared side-effect chains ──────────────────────────────────

local function DummyAuras()
    local bf = BF()
    if bf and bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
end

-- After any mutation of the preview set: the frames re-render, then the
-- panel's structural Invalidate -- this page's own membership changed.
local function PreviewSetChanged(ctx)
    local bf = BF()
    if bf and bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    ctx.app:Invalidate("previewSet")
end

-- ── The Preview tab (tabPreview) ───────────────────────────────

local function ShowPreviewOff()
    local bf = BF()
    return bf ~= nil and bf.db.global.showPreview == false
end

local function NotDeadStatus()
    local bf = BF()
    return ((bf and bf._previewStatus) or "alive") ~= "dead"
end

local PAGES = {}

function PAGES.preview()
    return {
        groups = {
            -- The Ace previewFramesHeader boundary, as a card -- with
            -- the setting the whole tab hangs off (showPreview) in its
            -- HEADER: everything the Ace page hid while Show Preview was
            -- off collapses with the card, which is the same statement
            -- made visibly.
            { title = "Preview Frames", preset = "form",
              toggle = {
                  id      = "showPreview",
                  default = DefaultG("showPreview"),
                  tooltip = "Show frame size previews to the left of this "
                      .. "panel whenever it is open.",
                  -- `~= false` rather than the raw value: an absent key
                  -- means ON.
                  get = function()
                      local bf = BF()
                      return bf and bf.db.global.showPreview ~= false
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf.db.global.showPreview = val
                      if not val then
                          bf:HidePreviewFrames()
                      elseif bf.RefreshPreviewFrames then
                          -- The Ace page re-drew through its invisible
                          -- previewRenderer on the NotifyChangeSafe that
                          -- followed; here the re-draw is said outright.
                          bf:RefreshPreviewFrames()
                      end
                      ctx.app:RefreshPage()
                  end,
              },
              fields = {
                  { control = "switch", label = "Preview Out of Range",
                    id = "previewOutOfRange", default = false,
                    desc = "Simulate out-of-range fade on the preview frames.",
                    -- A runtime flag (BF._previewOOR), not a saved
                    -- setting: stored as true-or-nil, reset on reload.
                    get = function()
                        local bf = BF()
                        return bf and bf._previewOOR == true
                    end,
                    set = function(_, _, val)
                        local bf = BF()
                        if not bf then return end
                        bf._previewOOR = val or nil
                        if bf.RefreshPreviewStatus then bf:RefreshPreviewStatus() end
                    end },
              }},

            -- The Ace previewStatusGroup. Its group-level hidden
            -- (showPreview off) has no panel equivalent -- a group
            -- cannot hide -- so each FIELD hides instead and the card
            -- collapses to its header while Show Preview is off.
            { title = "Preview Status", preset = "form", fields = {
                { control = "dropdown", label = "Status Action",
                  id = "previewStatusSelect", default = "alive",
                  hidden = ShowPreviewOff,
                  options = {
                      { value = "alive",   text = "Set Alive" },
                      { value = "dead",    text = "Kill the Buzzards" },
                      { value = "offline", text = "Disconnect the Buzzards" },
                      { value = "afk",     text = "Set AFK" },
                  },
                  get = function()
                      local bf = BF()
                      return (bf and bf._previewStatus) or "alive"
                  end,
                  set = function(_, _, val)
                      local bf = BF()
                      if not bf then return end
                      bf._previewStatus = (val == "alive") and nil or val
                      if val ~= "dead" then
                          bf._previewResurrect = nil
                          bf._previewGhost     = nil
                      end
                      if bf.RefreshPreviewStatus then bf:RefreshPreviewStatus() end
                  end },
                { control = "switch", label = "Set Ghost",
                  id = "setGhost", default = false,
                  hidden = function() return ShowPreviewOff() or NotDeadStatus() end,
                  get = function()
                      local bf = BF()
                      return bf and bf._previewGhost == true
                  end,
                  set = function(_, _, val)
                      local bf = BF()
                      if not bf then return end
                      bf._previewGhost = val or nil
                      if bf.RefreshPreviewStatus then bf:RefreshPreviewStatus() end
                  end },
                { control = "switch", label = "Resurrect the Buzzards",
                  id = "resurrectBuzzards", default = false,
                  hidden = function() return ShowPreviewOff() or NotDeadStatus() end,
                  get = function()
                      local bf = BF()
                      return bf and bf._previewResurrect == true
                  end,
                  set = function(_, _, val)
                      local bf = BF()
                      if not bf then return end
                      bf._previewResurrect = val or nil
                      if bf.RefreshPreviewStatus then bf:RefreshPreviewStatus() end
                  end },
            }},
        },
    }
end

-- ── The Preview Units tab (tabPreviewUnits) ────────────────────

-- The class and role lists, in the source's sorting order.
local CLASS_OPTIONS = {
    { value = "WARRIOR",     text = "Warrior" },
    { value = "PALADIN",     text = "Paladin" },
    { value = "HUNTER",      text = "Hunter" },
    { value = "ROGUE",       text = "Rogue" },
    { value = "PRIEST",      text = "Priest" },
    { value = "DEATHKNIGHT", text = "Death Knight" },
    { value = "SHAMAN",      text = "Shaman" },
    { value = "MAGE",        text = "Mage" },
    { value = "WARLOCK",     text = "Warlock" },
    { value = "MONK",        text = "Monk" },
    { value = "DRUID",       text = "Druid" },
    { value = "DEMONHUNTER", text = "Demon Hunter" },
    { value = "EVOKER",      text = "Evoker" },
}
local ROLE_OPTIONS = {
    { value = "TANK",    text = "Tank" },
    { value = "HEALER",  text = "Healer" },
    { value = "DAMAGER", text = "DPS" },
}

local function FlatTypeDefault(flatID)
    local bf = BF()
    local pv = bf and bf._preview
    return (pv and pv.GetFlatTypeDefault and pv.GetFlatTypeDefault(flatID))
        or { class = "WARRIOR", role = "TANK", hp = 0.75 }
end

-- The "+ Add preview…" dropdown: re-pins a flat previously hidden via
-- its Remove button. Lists only unpinned flats -- seeded ones first, the
-- rest alphabetical -- and is disabled when nothing is unpinned. An
-- ACTION dropdown: it never shows a current value.
local function AddPreviewField()
    return {
        control = "dropdown", label = "+ Add preview\226\128\166",
        options = function()
            local bf = BF()
            local flNow       = FlatLayouts()
            local unpinnedNow = (bf and bf.rpDB
                and bf.rpDB.profile._unpinnedPreviewFlats) or {}
            local keys   = {}
            local seeded = { "flat_party", "flat_raid20", "flat_raid30", "flat_raid40" }
            local added  = {}
            for _, id in ipairs(seeded) do
                if flNow[id] and unpinnedNow[id] then
                    keys[#keys + 1] = id
                    added[id]       = true
                end
            end
            local extras = {}
            for id in pairs(flNow) do
                if not added[id] and unpinnedNow[id] then
                    extras[#extras + 1] = id
                end
            end
            table.sort(extras)
            for _, id in ipairs(extras) do keys[#keys + 1] = id end

            local out = {}
            for _, id in ipairs(keys) do
                local flat    = flNow[id]
                local typeTag = (flat.type == "party") and "(Party)" or "(Raid)"
                out[#out + 1] = {
                    value = id,
                    text  = (flat.name or id) .. " " .. typeTag,
                }
            end
            return out
        end,
        disabled = function()
            local bf = BF()
            local unpinnedNow = bf and bf.rpDB
                and bf.rpDB.profile._unpinnedPreviewFlats
            if not unpinnedNow then return true end
            for _ in pairs(unpinnedNow) do return false end
            return true
        end,
        get = function() return nil end,
        set = function(_, ctx, flatID)
            local bf = BF()
            if not bf then return end
            local unpinnedNow = bf.rpDB.profile._unpinnedPreviewFlats
            if unpinnedNow then unpinnedNow[flatID] = nil end
            PreviewSetChanged(ctx)
        end,
    }
end

-- One card per flat in the active preview set -- the source's
-- buildFlatUnitGroup, with its classSelect / roleSelect / healthPct /
-- remove args as fields. Closes over flatID so the handlers write the
-- right key; overrides live in rpDB.profile._previewUnitsByFlat[flatID],
-- created on first write, with the flat type's defaults showing through
-- until then.
local function FlatUnitCard(flatID)
    local function getOv()
        local bf = BF()
        local p  = bf and bf.rpDB and bf.rpDB.profile
        return p and p._previewUnitsByFlat and p._previewUnitsByFlat[flatID]
    end
    local function ensureOv()
        local bf = BF()
        bf.rpDB.profile._previewUnitsByFlat =
            bf.rpDB.profile._previewUnitsByFlat or {}
        bf.rpDB.profile._previewUnitsByFlat[flatID] =
            bf.rpDB.profile._previewUnitsByFlat[flatID] or {}
        return bf.rpDB.profile._previewUnitsByFlat[flatID]
    end
    local function refresh()
        local bf = BF()
        if bf and bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    end

    local fl      = FlatLayouts()
    local flat    = fl[flatID]
    -- The type tag the Ace group name carried; its party/raid tint is
    -- left to the skin.
    local typeTag = (flat and flat.type == "party") and "(Party)" or "(Raid)"
    local title   = ((flat and flat.name) or flatID) .. " " .. typeTag
    local def     = FlatTypeDefault(flatID)

    return {
        title = title, preset = "form", fields = {
            { control = "dropdown", label = "Class",
              id = "previewUnit." .. flatID .. ".class", default = def.class,
              options = CLASS_OPTIONS,
              get = function()
                  local ov = getOv()
                  return (ov and ov.class) or FlatTypeDefault(flatID).class
              end,
              set = function(_, _, val)
                  ensureOv().class = val
                  refresh()
              end },
            { control = "dropdown", label = "Role",
              id = "previewUnit." .. flatID .. ".role", default = def.role,
              options = ROLE_OPTIONS,
              get = function()
                  local ov = getOv()
                  return (ov and ov.role) or FlatTypeDefault(flatID).role
              end,
              set = function(_, _, val)
                  ensureOv().role = val
                  refresh()
              end },
            { control = "slider", label = "Health %",
              id = "previewUnit." .. flatID .. ".hp", default = def.hp,
              min = 0, max = 1, step = 0.01,
              get = function()
                  local ov = getOv()
                  return (ov and ov.hp) or FlatTypeDefault(flatID).hp
              end,
              set = function(_, _, val)
                  ensureOv().hp = val
                  refresh()
              end },
            { control = "button", label = "Hide this preview",
              onClick = function(_, ctx)
                  local bf = BF()
                  if not bf then return end
                  bf.rpDB.profile._unpinnedPreviewFlats =
                      bf.rpDB.profile._unpinnedPreviewFlats or {}
                  bf.rpDB.profile._unpinnedPreviewFlats[flatID] = true
                  PreviewSetChanged(ctx)
              end },
        },
    }
end

-- One card per visible Custom Frame Group preview slot. Unchanged from
-- the flat model's card except in storage: overrides live in
-- db.profile.previewUnits[tierKey], the hide flag in
-- rpDB.profile._hiddenCFPreviewSlots[tierKey], and the fallbacks come
-- from CF_FAKE_UNIT_DEFAULTS.
local function CFUnitCard(cfSlot, entry)
    local tierKey = "cf" .. cfSlot
    local bfNow   = BF()
    local cfTbl   = bfNow and bfNow._preview
        and bfNow._preview.CF_FAKE_UNIT_DEFAULTS
    local cfDef   = (cfTbl and (cfTbl[cfSlot] or cfTbl[1]))
        or { class = "WARRIOR", role = "TANK", hp = 0.75 }
    local gName   = (entry.group and entry.group.name)
        or ("Group " .. (entry.index or cfSlot))

    local function getOv()
        local bf = BF()
        local p  = bf and bf.db and bf.db.profile
        return p and p.previewUnits and p.previewUnits[tierKey]
    end
    local function ensureOv()
        local bf = BF()
        bf.db.profile.previewUnits = bf.db.profile.previewUnits or {}
        bf.db.profile.previewUnits[tierKey] =
            bf.db.profile.previewUnits[tierKey] or {}
        return bf.db.profile.previewUnits[tierKey]
    end
    local function refresh()
        local bf = BF()
        if bf and bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    end

    return {
        title = "Custom Frame Group: " .. gName, preset = "form", fields = {
            { control = "dropdown", label = "Class",
              id = "previewUnit." .. tierKey .. ".class", default = cfDef.class,
              options = CLASS_OPTIONS,
              get = function()
                  local ov = getOv()
                  return (ov and ov.class) or cfDef.class
              end,
              set = function(_, _, val)
                  ensureOv().class = val
                  refresh()
              end },
            { control = "dropdown", label = "Role",
              id = "previewUnit." .. tierKey .. ".role", default = cfDef.role,
              options = ROLE_OPTIONS,
              get = function()
                  local ov = getOv()
                  return (ov and ov.role) or cfDef.role
              end,
              set = function(_, _, val)
                  ensureOv().role = val
                  refresh()
              end },
            { control = "slider", label = "Health %",
              id = "previewUnit." .. tierKey .. ".hp", default = cfDef.hp,
              min = 0, max = 1, step = 0.01,
              get = function()
                  local ov = getOv()
                  return (ov and ov.hp) or cfDef.hp
              end,
              set = function(_, _, val)
                  ensureOv().hp = val
                  refresh()
              end },
            { control = "button", label = "Hide this preview",
              onClick = function(_, ctx)
                  local bf = BF()
                  if not bf then return end
                  bf.rpDB.profile._hiddenCFPreviewSlots =
                      bf.rpDB.profile._hiddenCFPreviewSlots or {}
                  bf.rpDB.profile._hiddenCFPreviewSlots[tierKey] = true
                  PreviewSetChanged(ctx)
              end },
        },
    }
end

function PAGES.previewUnits()
    -- Remember what this build was made from, for the route observer's
    -- staleness check.
    builtUnitsSig = UnitsSignature()

    local groups = {
        { preset = "bare", fields = { AddPreviewField() } },
    }

    local order = ActivePreviewOrder()
    if #order == 0 then
        -- The Ace _empty description.
        groups[#groups + 1] = { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "No active preview. Pick a layout in \"Modifying "
                  .. "Layout\" or use the dropdown above to add one." },
        }}
    else
        for _, flatID in ipairs(order) do
            groups[#groups + 1] = FlatUnitCard(flatID)
        end
    end

    for _, e in ipairs(VisibleCFSlots()) do
        groups[#groups + 1] = CFUnitCard(e.slot, e.entry)
    end

    -- The source's resetAll, side effects verbatim: it clears the four
    -- storage tables and re-renders the frames, and does NOT regenerate
    -- the Ace args (nor does the source); the panel's own structure is
    -- rebuilt through Invalidate.
    groups[#groups + 1] = { preset = "bare", fields = {
        { control = "button", label = "Reset All to Defaults",
          onClick = function(_, ctx)
              local bf = BF()
              if not bf then return end
              bf.rpDB.profile._previewUnitsByFlat   = nil
              bf.rpDB.profile._hiddenCFPreviewSlots = nil
              bf.rpDB.profile._unpinnedPreviewFlats = nil
              bf.db.profile.previewUnits            = nil
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              ctx.app:Invalidate("previewSet")
          end },
    }}

    return { groups = groups }
end

-- ── The Preview Auras tab (tabPreviewAuras) ────────────────────
--
-- Everything here is db.global, so the whole page BINDS: db is the
-- global table, defaults is the shipped global defaults table, and undo
-- and reset come free. The three toggles gate SETUP-MODE test frames
-- only -- the options preview frames are governed by the per-tab
-- Preview dropdown on the aura tabs.

function PAGES.previewAuras()
    return {
        db       = GlobalDB,
        defaults = GlobalDefaults,
        groups = {
            -- The Ace showPreviewAurasHeader boundary.
            { title = "Show Preview Auras", preset = "form", fields = {
                { control = "switch", label = "Preview Buffs",
                  bind = "showDummyBuffs", onChange = DummyAuras,
                  desc = "Show dummy buff icons on Setup Mode test frames." },
                { control = "switch", label = "Preview Debuffs",
                  bind = "showDummyDebuffs", onChange = DummyAuras,
                  desc = "Show dummy debuff icons on Setup Mode test frames." },
                { control = "switch", label = "Preview Big Defensive",
                  bind = "showDummyBigDef", onChange = DummyAuras,
                  desc = "Show dummy Big Defensive icons on Setup Mode test frames." },
            }},
            -- The Ace previewAuraCountHeader boundary. Account-wide
            -- counts (db.global), matching where the defaults are
            -- declared.
            { title = "Number of Preview Auras", preset = "form", fields = {
                { control = "stepper", label = "Buffs",
                  bind = "previewBuffCount", min = 0, max = 8, step = 1,
                  onChange = DummyAuras,
                  desc = "Number of dummy buff icons shown on each preview frame." },
                { control = "stepper", label = "Debuffs",
                  bind = "previewDebuffCount", min = 0, max = 8, step = 1,
                  onChange = DummyAuras,
                  desc = "Number of dummy debuff icons shown on each preview frame." },
            }},
        },
    }
end

-- ── The Experimental Options tab (tabSpecialOptions) ───────────

local function NotExperimental()
    local bf = BF()
    return not (bf and bf.db.global.enableExperimentalOptions)
end

function PAGES.specialOptions()
    return {
        groups = {
            -- The master gate in the card HEADER: everything the Ace tab
            -- hid while Enable Experimental Options was off collapses
            -- with the card.
            { title = "Experimental Options", preset = "form",
              toggle = {
                  id      = "enableExperimentalOptions",
                  default = DefaultG("enableExperimentalOptions"),
                  tooltip = "Enables experimental options that may not be "
                      .. "fully tested. Use at your own risk.",
                  get = function()
                      local bf = BF()
                      return bf and bf.db.global.enableExperimentalOptions
                  end,
                  set = function(_, ctx, val)
                      if InCombatLockdown() then return end
                      local bf = BF()
                      if not bf then return end
                      bf.db.global.enableExperimentalOptions = val
                      -- The Ace Themes group carried a hidden() on this
                      -- same key, so the equivalent here is rebuilding
                      -- the route tree with or without that subtab.
                      -- RebuildRoutes re-runs Panel.lua's declaration,
                      -- which asks PROFILES_SUBTABS' `when` predicate;
                      -- SetRoutes re-points a route that no longer
                      -- exists at the first section, so turning the
                      -- switch off while standing on Themes lands
                      -- somewhere real rather than nowhere.
                      if ctx and ctx.app then
                          BuzzardFramesOptions:RebuildRoutes(ctx.app)
                      end
                      -- The Raid Frame Fitting fields below hide on this
                      -- key too, in their own card.
                      ctx.app:RefreshPage()
                  end,
              },
              fields = {
                -- No combat guard here, matching the source: this only
                -- flips a boolean that print sites read.
                { control = "switch", label = "Print Layout Timings",
                  id = "debugTiming", default = DefaultG("debugTiming"),
                  wide = true,
                  desc = "Prints how long each stage of a layout reload "
                      .. "takes, in milliseconds, to the chat frame.\n\n"
                      .. "|cffffd200Developer tool.|r The |cff11ace9"
                      .. "[deferred]|r lines measure work that runs one "
                      .. "frame after the reload returns (containers, "
                      .. "absorbs+cast, and the scoped re-layout pass), so "
                      .. "it is invisible to timing wrapped around the "
                      .. "caller even though the client still hitches on "
                      .. "it.\n\nThis only prints on a layout reload -- "
                      .. "applying a profile, changing group type, or a "
                      .. "setting that rebuilds the layout -- not during "
                      .. "normal play. It is safe to leave on, but it is "
                      .. "chatty.",
                  get = function()
                      local bf = BF()
                      return bf and bf.db.global.debugTiming
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf.db.global.debugTiming = val
                      ctx.app:RefreshPage()
                  end },
                { control = "switch", label = "Show Debug Outputs in chat",
                  id = "showDebugOutput", default = DefaultG("showDebugOutput"),
                  wide = true,
                  desc = "Prints BuzzardFrames developer/diagnostic output "
                      .. "(warm-up telemetry, /bf debug* commands, "
                      .. "profiler, layout timings) to the chat frame.\n\n"
                      .. "|cffffd200Developer tool.|r Off by default; with "
                      .. "it off, none of the debug output or /bf debug* "
                      .. "commands print anything. Real error notices stay "
                      .. "visible regardless.",
                  get = function()
                      local bf = BF()
                      return bf and bf.db.global.showDebugOutput
                  end,
                  set = function(_, ctx, val)
                      local bf = BF()
                      if not bf then return end
                      bf.db.global.showDebugOutput = val and true or false
                      ctx.app:RefreshPage()
                  end },
                { control = "button", label = "Show Welcome Message",
                  desc = "Show the Patch 12.1 welcome popup again.",
                  -- Through the notification system's replay API rather
                  -- than a StaticPopup, so the popup is built from the
                  -- same registration the login path uses.
                  onClick = function()
                      local bf = BF()
                      if bf and bf.ShowNotificationNow then
                          bf:ShowNotificationNow(bf.NOTIFICATION_WELCOME_121)
                      end
                  end },
              }},

            -- The Ace autoFitWidthHeader boundary (autoFitWidthSpacer,
            -- a pure spacer, is dropped -- the card gap does its job).
            -- The card's own header gate is the fitting toggle, so the
            -- max-width slider collapses with it exactly as its Ace
            -- `hidden` did; the whole card hiding while experimental
            -- options are off has no group-level equivalent, so the
            -- header hides its FIELDS via the gate's own hidden-like
            -- check inside get -- see the note in the migration notes.
            { title = "Raid Frame Fitting", preset = "form", fields = {
                { control = "switch",
                  label = "Auto set raidframe widths to fit",
                  id = "scaleRaidToFit",
                  default = DefaultLayoutsKey("scaleRaidToFit"),
                  wide = true,
                  desc = "Automatically widens raid frames so all columns "
                      .. "fill the same total space as a full 40-man raid. "
                      .. "E.g. in a 30-man (6 columns) the frames expand so "
                      .. "those 6 columns span the same width that 8 "
                      .. "columns would at the base setting. Has no effect "
                      .. "in 40-man raids.",
                  hidden = NotExperimental,
                  disabled = "combat",
                  get = function()
                      local bf = BF()
                      return bf ~= nil
                          and bf.rpDB.profile.layouts.scaleRaidToFit == true
                  end,
                  set = function(_, _, val)
                      if InCombatLockdown() then return end
                      local bf = BF()
                      if not bf then return end
                      bf.rpDB.profile.layouts.scaleRaidToFit = val
                      bf:InvalidateRaidProfileCache()
                      if bf.RefreshProfileCache then bf:RefreshProfileCache() end
                      bf:RebuildHeaders()
                      bf:LayoutAllIndicators()
                      -- Refresh setup mode if it's active so the flex
                      -- placeholder appears/disappears immediately.
                      if bf.db.global.setupModeActive and bf.UpdateSetupFrames then
                          bf:UpdateSetupFrames()
                      end
                  end },
                { control = "slider", label = "Frame Max Width",
                  id = "scaleRaidToFitMaxWidth",
                  default = DefaultLayoutsKey("scaleRaidToFitMaxWidth"),
                  min = 20, max = 300, step = 1,
                  desc = "Cap the fitted width at this value. If the "
                      .. "auto-fit formula would produce a wider frame, "
                      .. "this limit is used instead.",
                  hidden = function()
                      if NotExperimental() then return true end
                      local bf = BF()
                      return not (bf and bf.rpDB.profile.layouts.scaleRaidToFit)
                  end,
                  disabled = "combat",
                  get = function()
                      local bf = BF()
                      return bf
                          and (bf.rpDB.profile.layouts.scaleRaidToFitMaxWidth or 80)
                  end,
                  set = function(_, _, val)
                      if InCombatLockdown() then return end
                      local bf = BF()
                      if not bf then return end
                      bf.rpDB.profile.layouts.scaleRaidToFitMaxWidth = val
                      bf:InvalidateRaidProfileCache()
                      if bf.RefreshProfileCache then bf:RefreshProfileCache() end
                      -- Light path: setup mode resize is cheap and runs
                      -- on every slider tick so the user sees immediate
                      -- feedback while dragging.
                      if bf.db.global.setupModeActive and bf.ResizeTestFramesInPlace then
                          bf:ResizeTestFramesInPlace()
                      end
                      -- Heavy path: ResizeAllFrames iterates every header
                      -- and child. Debounced on the SAME timer the Ace
                      -- setter uses, so whichever panel wrote last owns
                      -- the trailing run.
                      if bf._fitMaxWidthTimer then bf._fitMaxWidthTimer:Cancel() end
                      bf._fitMaxWidthTimer = C_Timer.NewTimer(0.3, function()
                          bf._fitMaxWidthTimer = nil
                          if InCombatLockdown() then return end
                          if bf.ResizeAllFrames then bf:ResizeAllFrames() end
                      end)
                  end },
            }},
        },
    }
end

-- ── The pages ──────────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. The ids are the _currentSection keys the
-- preview system matches on (tabPreview / tabPreviewUnits /
-- tabPreviewAuras / tabSpecialOptions in the Ace source).
BuzzardFramesOptions.PREVIEW_SUBTABS = {
    { id = "preview",        title = "Preview" },
    { id = "previewUnits",   title = "Preview Units" },
    { id = "previewAuras",   title = "Preview Auras" },
    { id = "specialOptions", title = "Experimental Options" },
}

function BuzzardFramesOptions:PreviewPage(subtabId)
    local Panel = LibStub and LibStub("BuzzardPanel-1.0", true)
    local app   = Panel and Panel:GetApp("BuzzardFrames")
    EnsureObservers(app)

    -- The observers cover every later visit; the FIRST visit builds the
    -- page before its observer has ever fired, so the enter work runs
    -- here too -- gated on the route actually being active, because the
    -- search indexer also resolves page functions and must not drag the
    -- preview state around while it does.
    if app and app:IsRouteActive("raidPartyFrames/preview/" .. subtabId) then
        EnterSection(subtabId)
    end

    local build = PAGES[subtabId]
    if not build then return { groups = {} } end
    return build()
end
