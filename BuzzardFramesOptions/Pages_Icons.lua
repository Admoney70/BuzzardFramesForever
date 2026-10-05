-- ============================================================
-- BuzzardFramesOptions: Pages_Icons.lua
-- The Raid/Party Frames > Icons section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Icons.lua: the
-- same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by six BuzzardPanel pages -- one per
-- subtab, each a route of its own under `raidPartyFrames/icons`, drawn as
-- a strip by the `tabs` navigator that node declares.
--
-- THE FIRST SECTION WITH SUBTABS, and they are routes rather than page
-- furniture: a subtab is then deep-linkable, observable (the preview
-- system can show role icons while Role Icons is open), searchable on its
-- own, and remembers its own scroll position. The rail does NOT list them
-- -- `icons` says nothing, so the app's own default decides, and that is
-- off: the strip owns them, and six rows in two places is two controls
-- for one move.
--
-- Storage: rpDB.profile.icons.* (the global pseudo-layout), or flat.icons.*
-- for whichever keys belong to a subtab whose own icons_<subtab> toggle is
-- on. That routing is PER KEY and it is not this file's business: reads go
-- through BF:GetSectionProfile("icons", ...) -- which answers with the
-- merged view -- and writes through BF:WriteSectionKey / BF:SectionKeyTable,
-- exactly as the Ace page's getIP/writeIP do. Nothing here touches a db
-- table directly, which is what keeps the two panels in step.
--
-- Every field is BOUND rather than given a get/set pair. A bind path is
-- what the library's right-click menu records an undo against and looks a
-- default up by, so binding is what makes "Undo change" and "Reset to
-- default" work on all sixty-odd fields without one of them declaring
-- anything. The paths resolve against ROOT below, which is the routed
-- storage wearing the shape of a plain table.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- The section as it reads right now: the merged view for the modifying
-- Layout, which degrades to the global wherever no subtab is per-Layout.
local function GetIP()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("icons", bf:GetModifyingProfile())
end

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db and reading or writing the slot it lands on. Icons has no such table:
-- what a key READS from and what it WRITES to are decided per key, by that
-- key's subtab and that subtab's per-Layout toggle, and the read side is a
-- CACHED COPY that must never be written to.
--
-- So the page hands the library a table shaped like the one it wants and
-- routed like the one Buzzard Frames has: reads fall through to the merged
-- view, writes go to WriteSectionKey. The composites need one more level --
-- an anchor pad binds `roleIconPosition.point` -- so a key whose value is a
-- table answers with a wrapper of its own, reading from the view and
-- writing through SectionKeyTable, which materialises the per-flat copy on
-- demand exactly as the Ace setters do.
--
-- The alternative was a get/set pair on all sixty-odd fields, and with it
-- no undo and no reset, since both are keyed on the bind path.
local subCache = {}

local function SubTable(key)
    local w = subCache[key]
    if w then return w end
    w = setmetatable({}, {
        __index = function(_, k)
            local ip = GetIP()
            local t = ip and ip[key]
            return t and t[k]
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local bf = BF()
            -- SectionKeyTable returns the table to MUTATE -- the flat's own
            -- copy when this key's subtab is per-Layout, the global's
            -- otherwise. Never the merged view.
            local t = bf and bf:SectionKeyTable("icons", key)
            if t then t[k] = v end
        end,
    })
    subCache[key] = w
    return w
end

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local ip = GetIP()
        local v = ip and ip[k]
        if type(v) == "table" then return SubTable(k) end
        return v
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if bf then bf:WriteSectionKey("icons", k, v) end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library resolves
-- a bind path straight into it -- `roleIconPosition.point` included.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.icons
end

-- ── Side effects ───────────────────────────────────────────────
--
-- One function per thing the addon has to be told, named for what it tells
-- it. A field names the one it needs in `onChange`; the library decides
-- WHEN to run it (a slider coalesces its drag into one call), and these
-- decide what it is.

local function ForEachFrame(fn)
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do fn(bf, f) end
end

-- Reposition icons on every active frame without a full RefreshAll.
--
-- Debounced through BF:DebounceOption, under the SAME key the Ace page
-- uses: every icon size and offset routes here and fires on every drag
-- tick, and a full LayoutFrame walk per tick stutters the client. The
-- profile write has already happened, so the trailing run applies the
-- final value.
local function LayoutFrames()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("iconsLayout", function()
        for f in pairs(bf.activeFrames or {}) do bf:LayoutFrame(f) end
        if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
    end)
end

local function RoleIcons()
    ForEachFrame(function(bf, f) bf:UpdateRoleIcon(f) end)
    local bf = BF()
    if bf and bf.RefreshPreviewRoleIcon then bf:RefreshPreviewRoleIcon() end
end

-- The show toggle both repositions and restyles: turning role icons on
-- gives every frame something it did not have to make room for.
local function RoleIconsShown()
    LayoutFrames()
    RoleIcons()
end

local function RaidTargetIcons()
    ForEachFrame(function(bf, f) bf:UpdateRaidTargetIcon(f) end)
end

local function LeaderIcons()
    ForEachFrame(function(bf, f) bf:UpdateLeaderIcon(f) end)
end

-- The ping pin is a MIRROR of the default UI's raid-frame ping receivers,
-- so turning it on is a rebuild rather than a restyle. Ensure comes first:
-- with the unit-frames module off the mirror may not exist yet, and
-- RebuildPingMirror alone cannot start the ticker (SetPingTicker bails on
-- `not pingMirror`).
local function PingIndicator()
    local bf = BF()
    if not bf then return end
    ForEachFrame(function(_, f)
        local pin = f.pingIndicatorTex
        if pin then pin:Hide(); pin:PostUpdate(nil); pin._mirrorKey = false end
    end)
    if bf.EnsurePingMirror  then bf:EnsurePingMirror()  end
    if bf.RebuildPingMirror then bf:RebuildPingMirror() end
end

-- Turning the toggle off in every Layout unregisters the tracker, so a
-- reader who does not use the feature pays nothing per aura update.
-- Turning it on registers and backfills.
local function MissingRaidBuffTrackers()
    local bf = BF()
    if not bf then return end
    if bf.EnsureMissingRaidBuffTrackers then bf:EnsureMissingRaidBuffTrackers() end
    bf:RefreshAllCustomContainersWithRebuild()
end

local function MissingRaidBuffLook()
    local bf = BF()
    if not bf then return end
    if bf.RefreshMissingRaidBuffOnly then bf:RefreshMissingRaidBuffOnly()
    else bf:RefreshAllAuras() end
end

local function StatusIcons()
    local bf = BF()
    if bf and bf.RefreshPreviewStatusIcons then bf:RefreshPreviewStatusIcons() end
end

-- ── The status icons, one row each ─────────────────────────────
--
-- Five settings that differ by nothing but which indicator they update and
-- which test flag they clear, so they are declared as data and built.
--
-- Clearing the test flag is the part worth keeping: a test left on while
-- its icon is turned off lingers invisibly, and comes back the next time
-- the icon does.
local STATUS_ICONS = {
    { key = "showReadyCheck",       test = "testReadyCheck",
      label = "Show Ready Check",   update = "UpdateReadyCheck",
      testLabel = "Test Ready Check" },
    { key = "showPhased",           test = "testPhased",
      label = "Show Phased",        update = "UpdatePhased",
      desc = "Show an icon when a unit is in a different phase.",
      testLabel = "Test Phased" },
    { key = "showSummonPending",    test = "testSummonPending",
      label = "Show Summon Pending", update = "UpdateSummonPending",
      desc = "Show an icon when a unit has a pending summon awaiting acceptance.",
      testLabel = "Test Summon Pending" },
    { key = "showResurrectPending", test = "testResurrectPending",
      label = "Show Resurrection Pending", update = "UpdateResurrectPending",
      desc = "Show an icon when a unit has an incoming resurrection awaiting acceptance.",
      testLabel = "Test Resurrection Pending",
      -- ApplyPreviewStatus's dead branch reads showResurrectPending to
      -- decide whether the preview frame carries the pending icon, so this
      -- one needs the status refresh as well as the icon one.
      extra = "RefreshPreviewStatus" },
    { key = "showVehicleIcon",      test = "testVehicleIcon",
      label = "Show Vehicle Icon",  update = "UpdateVehicle",
      desc = "Show an icon when a unit is in a vehicle.",
      testLabel = "Test Vehicle Icon" },
}

local function StatusIconShown(entry)
    return function()
        local bf = BF()
        if not bf then return end
        -- The write has already happened; this reads back what it stored.
        if not ROOT[entry.key] and bf.db.global[entry.test] then
            bf.db.global[entry.test] = false
        end
        ForEachFrame(function(b, f)
            if b[entry.update] then b[entry.update](b, f) end
        end)
        if entry.extra and bf[entry.extra] then bf[entry.extra](bf) end
        StatusIcons()
    end
end

-- A test flag is a GLOBAL debug switch (BF.db.global), reset on every
-- reload by Core_DB. It is not part of the per-Layout icons profile, so it
-- is the one thing on this page that does not bind to ROOT.
local function TestField(entry)
    return {
        control = "switch", label = entry.testLabel,
        id = entry.test, default = false, disabled = "combat",
        hidden = function() return not ROOT[entry.key] end,
        get = function() local bf = BF(); return bf and bf.db.global[entry.test] end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            bf.db.global[entry.test] = v
            ForEachFrame(function(b, f)
                if b[entry.update] then b[entry.update](b, f) end
            end)
            StatusIcons()
        end,
    }
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Icons carries SIX per-Layout toggles, one per subtab (icons_roleIcons
-- through icons_statusIcons), so the strip belongs to the subtab rather
-- than the section -- and Copy to moves that subtab's keys and no others,
-- which is what stops copying Role Icons onto the raid Layout quietly
-- overwriting its Status Icons.

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Party flats first, then raid, each alphabetical; the ACTIVE Layout is
-- tinted green, which is how the Ace dropdown has always shown the
-- difference between "active" and "being edited".
local function FlatOptions()
    local bf = BF()
    local fl = FlatLayouts()
    local activeID = bf and bf.ResolveActiveFlat and bf:ResolveActiveFlat(bf:GetActiveSlot())
    local party, raid = {}, {}
    for id, flat in pairs(fl) do
        if type(flat) == "table" then
            local into = (flat.type == "party") and party or raid
            into[#into + 1] = id
        end
    end
    local function byName(a, b)
        return ((fl[a].name or a):lower()) < ((fl[b].name or b):lower())
    end
    table.sort(party, byName)
    table.sort(raid,  byName)

    local out = {}
    local function add(id)
        local name = fl[id].name or id
        out[#out + 1] = {
            value = id,
            text  = (id == activeID) and ("|cff76CC4B" .. name .. "|r") or name,
        }
    end
    for _, id in ipairs(party) do add(id) end
    for _, id in ipairs(raid)  do add(id) end
    return out
end

-- _modifyingFlat can be unset (a fresh session) or name a Layout that has
-- since been deleted, so it falls back the way the Ace dropdown does.
local function CurrentFlat()
    local bf = BF()
    local fl = FlatLayouts()
    local cur = bf and bf._modifyingFlat
    if cur and fl[cur] then return cur end
    if fl.flat_party then return "flat_party" end
    local opts = FlatOptions()
    return opts[1] and opts[1].value
end

local function CopyTargets()
    local fl  = FlatLayouts()
    local cur = CurrentFlat()
    local t   = {}
    for id, flat in pairs(fl) do
        if id ~= cur and type(flat) == "table" then
            t[#t + 1] = { id = id, name = flat.name or id }
        end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

-- Copy ONE SUBTAB's keys from the Layout being modified onto another.
-- Tables are deep-copied, or the two Layouts end up sharing one table and
-- silently editing each other afterwards. Falls back to the global as the
-- source when the toggle is on but this flat was never seeded.
local function CopySubtabTo(subtabId, targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    local keys = bf.SECTION_SUBTAB_KEYS and bf.SECTION_SUBTAB_KEYS.icons
    keys = keys and keys[subtabId]
    if not keys then return end

    local srcSection = rawget(src, "icons")
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.icons end
    if type(srcSection) ~= "table" then return end

    if type(rawget(dst, "icons")) ~= "table" then
        dst.icons = {}
        -- A flat's section table falls THROUGH to the global for anything
        -- it does not hold. A table created without that wiring answers nil
        -- for every key this copy does not carry.
        if bf.WireSectionFallback then bf:WireSectionFallback(dst, "icons") end
    end
    local dstSection = rawget(dst, "icons")

    for _, k in ipairs(keys) do
        local v = srcSection[k]
        if v ~= nil then
            dstSection[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("icons") end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function TogKey(subtabId)
    local bf = BF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and bf.SECTION_SUBTAB_TOGGLE.icons
    return m and m[subtabId]
end

local function NotPerLayout(subtabId)
    return function()
        local bf = BF()
        return not (bf and bf:IsPerLayoutSectionSubtab("icons", subtabId))
    end
end

-- A flat bar rather than a card: this row is ABOUT the settings below it,
-- not one of them. `strip` is the library's preset for exactly that.
local function ScopeStrip(subtabId, label)
    local notPer = NotPerLayout(subtabId)
    -- `scopeStrip` marks this card as the RAID/PARTY per-Layout row.
    -- "Per-Layout" means "per Raid/Party Layout", and a Custom Frame
    -- Group is not a Layout -- it is its own scope -- so the Custom
    -- Frame Groups assembler drops the card rather than rendering a
    -- control that would edit the wrong thing.
    return { preset = "strip", scopeStrip = true, fields = {
        { control = "switch", label = "Enable per-Layout Config",
          -- State first, then what it is the state of.
          labelSide = "after",
          -- Off is the shipped state: settings are global until somebody
          -- asks for them not to be. The id is the TOGGLE key, so an undo
          -- on this switch is recorded against the thing it flips.
          id = TogKey(subtabId) or ("icons_" .. subtabId), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give " .. label .. " its own "
              .. "settings per Layout -- the other Icons subtabs keep "
              .. "their own toggles.",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSectionSubtab("icons", subtabId)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight pass-through
              -- while that flag is off.
              bf:_TimeSectionPerLayout(TogKey(subtabId), v)
              -- Every field below now reads a different place, and the two
              -- controls beside this one appear or go.
              ctx.app:RefreshPage()
          end },

        { control = "dropdown", label = "Modifying",
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited for. "
              .. "The currently active Layout is shown in green.",
          hidden = notPer, disabled = "combat",
          options = FlatOptions,
          get = function() return CurrentFlat() end,
          set = function(_, ctx, v)
              local bf = BF()
              if not bf then return end
              bf._modifyingFlat = v
              bf:InvalidateRaidProfileCache()
              if bf.UpdateAuraSizeCache  then bf:UpdateAuraSizeCache()  end
              -- The same post-change chain the Ace dropdown runs.
              if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
              if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              ctx.app:RefreshPage()
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy this Layout's " .. label .. " settings onto another "
              .. "Layout. Only this subtab's settings move; the rest of "
              .. "Icons is left alone.",
          disabled = "combat",
          -- Nothing to copy TO is the same as nothing to copy.
          hidden = function()
              return notPer() or #CopyTargets() == 0
          end,
          options = function()
              local out = {}
              local targets = CopyTargets()
              for _, e in ipairs(targets) do
                  out[#out + 1] = { value = e.id, text = e.name }
              end
              if #targets > 1 then
                  out[#out + 1] = { value = "__all", text = "All Layouts" }
              end
              return out
          end,
          -- A copy is an ACTION, not a setting: the dropdown never shows a
          -- current value, it just offers destinations.
          get = function() return nil end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local from = LayoutName(CurrentFlat())
              local text
              if v == "__all" then
                  text = ("Copy the %s settings from \"%s\" to all other "
                      .. "Layouts? This overwrites every %s setting on "
                      .. "them."):format(label, from, label)
              else
                  text = ("Copy the %s settings from \"%s\" to \"%s\"? This "
                      .. "overwrites every %s setting on it."):format(
                      label, from, LayoutName(v), label)
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do
                          CopySubtabTo(subtabId, e.id)
                      end
                  else
                      CopySubtabTo(subtabId, v)
                  end
              end)
          end },
    }}
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every field on this page binds into ROOT and names its effect. These
-- three say that once each instead of sixty times.

local function Sw(bind, label, effect, opts)
    local f = { control = "switch", label = label, bind = bind,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

local function Sl(bind, label, lo, hi, effect, opts)
    local f = { control = "slider", label = label, bind = bind,
                min = lo, max = hi, step = 1,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- The anchor pad and its two offsets, as one field.
--
-- Three settings that only mean anything together: an offset is relative
-- to a point, and the shape of the control is the shape of the answer --
-- which a nine-item Location dropdown never was. `binds` is what makes it
-- one widget over three bindings, so a change to any of them repaints the
-- whole thing.
local function Pos(bind, label, effect, lo, hi)
    return { control = "anchor", label = label,
             binds = { point = bind .. ".point", x = bind .. ".x", y = bind .. ".y" },
             min = lo or -50, max = hi or 50,
             onChange = effect, disabled = "combat" }
end

-- ── The six pages ──────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list that
-- builds the pages: the ids ARE the subtab ids in BF.SECTION_SUBTABS, so
-- the per-Layout toggles line up by construction rather than by a table
-- somebody has to keep in step.
BuzzardFramesOptions.ICONS_SUBTABS = {
    -- In the Ace strip's own order (its `order` values: 1, 2, 3, 6, 6.5, 7).
    { id = "roleIcons",       title = "Role Icons" },
    { id = "raidTarget",      title = "Raid Target Markers" },
    { id = "leaderAssistant", title = "Leader/Assistant" },
    { id = "statusIcons",     title = "Status Icons" },
    { id = "pingIndicator",   title = "Ping Indicator" },
    { id = "missingRaidBuff", title = "Missing Raid Buff Icon" },
}

-- A gate in the card HEADER, and the card collapses when it is off. That
-- is the Ace page's `hidden` predicate made visible: the Style, Position
-- and Per-Role groups are not merely grayed while role icons are off, they
-- are not there -- and the header says why.
--
-- A gate is the one thing on this page that cannot bind: the library reads
-- it through get/set (it is a group's declaration, not a field's), so the
-- routing and the effect are written out here. `id` and `default` are what
-- make it reset with the rest of its card from the header's own menu.
local function Gate(key, tooltip, effect)
    local d = Defaults()
    return {
        id      = key,
        default = d and d[key],
        tooltip = tooltip,
        get     = function() return ROOT[key] end,
        set     = function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = v
            if effect then effect() end
        end,
    }
end

local PAGES = {}

function PAGES.roleIcons()
    return {
        { title = "Role Icons", preset = "form",
          toggle = Gate("showRoleIcons", "Show Role Icons", RoleIconsShown),
          fields = {
            { control = "segmented", label = "Role Icon Style",
              bind = "roleIconStyle", onChange = RoleIcons, disabled = "combat",
              desc = "Modern 10.1.5 icons, the classic circular set, small "
                  .. "atlas icons, or translucent glass.",
              options = {
                  { value = "MODERN",   text = "Modern"   },
                  { value = "BLIZZARD", text = "Circular" },
                  { value = "TINY",     text = "Tiny"     },
                  { value = "GLASS",    text = "Glass"    },
              } },
            Sl("roleIconSize", "Role Icon Size", 6, 24, LayoutFrames),
        }},
        { title = "Position", preset = "form", fields = {
            Pos("roleIconPosition", "Location", LayoutFrames),
        }},
        { title = "Show Per-Role", preset = "form", fields = {
            Sw("showRoleIconTank",   "Show Tank Icons",   RoleIcons,
               { desc = "Show the role icon on units assigned as Tank." }),
            Sw("showRoleIconHealer", "Show Healer Icons", RoleIcons,
               { desc = "Show the role icon on units assigned as Healer." }),
            Sw("showRoleIconDPS",    "Show DPS Icons",    RoleIcons,
               { desc = "Show the role icon on units assigned as DPS." }),
        }},
    }
end

function PAGES.raidTarget()
    return {
        { title = "Raid Target Markers", preset = "form",
          toggle = Gate("showRaidTargetIcon", "Show Raid Target Icon", RaidTargetIcons),
          fields = {
            Sl("raidTargetIconSize", "Icon Size", 8, 32, LayoutFrames),
            Pos("raidTargetIconPosition", "Position", LayoutFrames),
        }},
    }
end

function PAGES.pingIndicator()
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Shows the ping pin when a group member pings a unit. "
                  .. "Mirrors the default UI's raid-frame ping receivers, so it "
                  .. "works while grouped and needs |cffffff00Show Pings on Raid "
                  .. "Frames|r enabled in the game's Ping settings." },
        }},
        { title = "Ping Indicator", preset = "form",
          toggle = Gate("showPingIndicator", "Show Ping Indicator", PingIndicator),
          fields = {
            Sl("pingIndicatorSize", "Indicator Size", 8, 48, LayoutFrames),
            Pos("pingIndicatorPosition", "Position", LayoutFrames),
        }},
    }
end

function PAGES.leaderAssistant()
    return {
        { title = "Leader Icon", preset = "form",
          toggle = Gate("showLeaderIcon", "Show Leader Icon", LeaderIcons),
          fields = {
            Sl("leaderIconSize", "Icon Size", 8, 24, LayoutFrames),
            Pos("leaderIconPosition", "Position", LayoutFrames),
        }},
        { title = "Assistant Icon", preset = "form",
          toggle = Gate("showAssistantIcon", "Show Assistant Icon", LeaderIcons),
          fields = {
            Sl("assistantIconSize", "Icon Size", 8, 24, LayoutFrames),
            Pos("assistantIconPosition", "Position", LayoutFrames),
        }},
    }
end

function PAGES.missingRaidBuff()
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Since Patch 12.1 the Missing Raid Buff icon can only be "
                  .. "shown |cffffff00out of combat|r." },
        }},
        -- The Symbiotic toggle is INSIDE the card but not gated by its
        -- header: it is a second, independent reason for the indicator to
        -- appear, exactly as it is in the Ace page, where the size and
        -- position groups show if EITHER is on.
        { title = "Missing Raid Buff", preset = "form",
          toggle = Gate("showMissingRaidBuff", "Show Missing Raid Buff",
                        MissingRaidBuffTrackers),
          fields = {
            Sl("missingRaidBuffSize", "Icon Size", 2, 40, MissingRaidBuffLook,
               { desc = "Size of the missing raid buff icon, in pixels." }),
            Sw("missingRaidBuffShowGlow", "Show Glow", MissingRaidBuffLook,
               { desc = "Show an action-button glow on the missing raid buff icon." }),
            -- Three FLAT keys rather than a position table, so the pad is
            -- bound to them by name.
            { control = "anchor", label = "Position",
              binds = { point = "missingRaidBuffAnchor",
                        x     = "missingRaidBuffOffsetX",
                        y     = "missingRaidBuffOffsetY" },
              min = -60, max = 60,
              onChange = MissingRaidBuffLook, disabled = "combat" },
        }},
        { title = "Symbiotic Relationship", preset = "form", fields = {
            Sw("showMissingSymbiotic", "Show Missing Symbiotic Relationship (Druid)",
               MissingRaidBuffTrackers,
               { wide = true,
                 desc = "Show an indicator on the player frame when you have the "
                     .. "Symbiotic Relationship talent but are missing the "
                     .. "personal buff it grants." }),
        }},
    }
end

function PAGES.statusIcons()
    local shown, tests = {}, {}
    for i, e in ipairs(STATUS_ICONS) do
        shown[i] = Sw(e.key, e.label, StatusIconShown(e), { desc = e.desc })
        tests[i] = TestField(e)
    end
    return {
        { title = "Status Icons", preset = "form", fields = shown },
        { title = "Status Icon Position", preset = "form", fields = {
            Sl("statusIconSize", "Size", 8, 40, LayoutFrames),
            Pos("statusIconPosition", "Position", LayoutFrames),
        }},
        { title = "Customize Icons", preset = "form", fields = {
            { control = "segmented", label = "Resurrection Pending Icon",
              bind = "resurrectPendingIconStyle",
              options = { { value = "blizzard", text = "Blizzard" },
                          { value = "buzzard",  text = "Buzzard"  } },
              -- The setting is meaningless while the icon is off, and it is
              -- one control rather than a group, so it grays rather than
              -- going: a field that vanishes on its own reads as a bug.
              disabled = function()
                  return InCombatLockdown() or not ROOT.showResurrectPending
              end,
              onChange = function()
                  ForEachFrame(function(bf, f) bf:LayoutFrame(f) end)
                  StatusIcons()
              end },
        }},
        -- Global debug flags, cleared on every reload -- and each row is
        -- there only while the icon it fakes is turned on.
        { title = "Test Status Icons", preset = "form", fields = tests },
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:IconsPage(subtabId, label)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end

    local groups = { ScopeStrip(subtabId, label or subtabId) }
    for _, g in ipairs(build()) do groups[#groups + 1] = g end

    return {
        -- The routed storage, wearing the shape of a table. Every `bind` on
        -- this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- which is what
        -- makes the right-click "Reset to default" work on every field
        -- without any of them declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end
