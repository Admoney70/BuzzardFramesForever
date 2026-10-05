-- ============================================================
-- BuzzardFramesOptions: Pages_Sorting.lua
-- The Raid/Party Frames > Frame Configuration > Sorting & Grow Direction
-- page, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Frames_Sorting.lua
-- (BF:BuildFramesSortingOptions): the same settings, the same storage and
-- the same side effects, with the AceConfig args table replaced by a
-- BuzzardPanel page. Both descriptions exist while both panels do; an edit
-- in either lands in the same place, so they cannot drift apart in what
-- they STORE -- only in what they show.
--
-- Storage: rpDB.profile.sorting.* (the global pseudo-layout), or
-- flat.sorting.* when layouts.perLayoutToggles.sorting is on. Every field
-- reads and writes through GetSP() -- BF:GetSectionProfile("sorting",
-- BF:GetModifyingProfile()) -- the same routed path the Ace page uses.
-- The anchor-conversion setters also write flat.anchorX / flat.anchorY /
-- flat.partyLayoutAnchor / flat.raidLayoutAnchor, exactly as the Ace
-- setters do. Nothing here writes a db table directly.
--
-- SECTION VISIBILITY is the one structural thing on this page. In the Ace
-- panel, per-layout OFF shows BOTH the Party and Raid sections (the global
-- affects every flat); per-layout ON shows only the section matching the
-- modifying flat's type. The library hides FIELDS, not GROUPS, and a card
-- whose fields all hid would still show its empty header -- so this page
-- decides section membership when it is BUILT, and the two controls that
-- can change the answer (the per-Layout switch and the Modifying dropdown)
-- schedule a structural rebuild through app:Invalidate, which re-calls the
-- route's lazy page function. Deferred a frame, the way the library's own
-- ns.page.ScheduleRender defers its re-render, so the control that caused
-- it is not released mid-click.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The section profile currently being modified. With the per-layout toggle
-- OFF, GetSectionProfile ignores the flat and returns the global; with it
-- ON it returns the modifying flat's sorting, so the user sees and edits
-- the per-flat copy.
local function GetSP()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("sorting", bf:GetModifyingProfile())
end

-- ── The write-through root ─────────────────────────────────────
--
-- The routed storage wearing the shape of a plain table, so the simple
-- fields can BIND rather than carry get/set pairs -- binding is what makes
-- right-click Undo and Reset work on them without declaring anything.
-- Sorting holds no table-valued keys, so no sub-table wrapper is needed.
--
-- The Ace setters here carry no cache invalidation (no
-- InvalidateRaidProfileCache) -- they write and reload -- so the
-- __newindex repeats exactly that: the combat guard and the write. The
-- reload lives in each field's onChange.
local ROOT = setmetatable({}, {
    __index = function(_, k)
        local sp = GetSP()
        return sp and sp[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local sp = GetSP()
        if sp then sp[k] = v end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source: a copy here would be a second answer to the same question.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.sorting
end

-- For the get/set fields, which have no bind to look a default up by.
local function DefaultSP(key)
    local d = Defaults()
    return d and d[key]
end

-- ── Side effects ───────────────────────────────────────────────

-- The plain-write chain: rebuild the layout, then keep setup mode's test
-- frames in step.
local function ReloadAndSetup()
    local bf = BF()
    if not bf then return end
    bf:ReloadLayout(true)
    if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
end

-- The anchor-touching chain: the setters that move flat.anchorX/Y also
-- re-position the anchor frame before setup mode is refreshed.
local function ReloadAnchorSetup()
    local bf = BF()
    if not bf then return end
    bf:ReloadLayout(true)
    if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
    if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
end

-- The anchor frame whose geometry should be read for position
-- calculations. In setup mode the test anchor is the one sized to match
-- the displayed layout; the real anchor may have a stale size.
local function GetVisibleAnchor()
    local bf = BF()
    if not bf then return nil end
    if bf.db and bf.db.global and bf.db.global.setupModeActive
       and bf.testAnchorFrame then
        return bf.testAnchorFrame
    end
    return bf.anchorFrame
end

-- ── External sort-override checks ──────────────────────────────
--
-- Context-aware pair: true when the override is active right now. Used by
-- disabled= on controls (settings can't be changed while overridden).
local function OverridingParty()
    local bf = BF()
    return bf and bf.IsFrameSortOverridingParty
        and bf:IsFrameSortOverridingParty() or false
end

local function OverridingRaid()
    local bf = BF()
    return bf and bf.IsFrameSortOverridingRaid
        and bf:IsFrameSortOverridingRaid() or false
end

-- Settings-based pair: true when ANY relevant area is enabled over there,
-- regardless of current context. Used by the red warning notes so they
-- show even when the user is in a different context (e.g. the raid warning
-- while solo).
local function EnabledForParty()
    local bf = BF()
    return bf and bf.IsFrameSortEnabledForParty
        and bf:IsFrameSortEnabledForParty() or false
end

local function EnabledForRaid()
    local bf = BF()
    return bf and bf.IsFrameSortEnabledForRaid
        and bf:IsFrameSortEnabledForRaid() or false
end

local function PartyDisabled()
    return InCombatLockdown() or OverridingParty()
end

local function RaidDisabled()
    return InCombatLockdown() or OverridingRaid()
end

-- Ace's |cffff4444 warning red, kept to the digit -- applied through the
-- note control's own color key rather than escape codes in the text.
local WARNING_RED = { 1.00, 0.27, 0.27, 1.00 }

-- ── Section visibility ─────────────────────────────────────────
--
-- Both return false (show) when the per-layout toggle is OFF, so the
-- global view shows every widget. When ON, they hide the section that does
-- not match the modifying flat's type -- keys in the hidden section aren't
-- reachable for that flat type anyway.
local function HidePartySection()
    local bf = BF()
    if not (bf and bf:IsPerLayoutSection("sorting")) then return false end
    local flat = bf:GetModifyingProfile()
    return flat and flat.type == "raid" or false
end

local function HideRaidSection()
    local bf = BF()
    if not (bf and bf:IsPerLayoutSection("sorting")) then return false end
    local flat = bf:GetModifyingProfile()
    return flat and flat.type == "party" or false
end

-- Structural rebuild: re-resolve this route's lazy page function so the
-- group list is decided again. Deferred a frame so the control whose
-- setter asked for it is not released mid-click (the same reason the
-- library's ns.page.ScheduleRender defers its own re-render).
local function RebuildPage(app)
    local function go()
        if app and app.frame and app.frame:IsShown() then
            app:Invalidate("bfSortingSections")
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, go) else go() end
end

-- ── The per-layout row ──────────────────────────────────────────
--
-- Three controls that are ABOUT the settings rather than settings
-- themselves: whether this section is configured per layout, which layout
-- is being edited, and copying what is here onto another layout. The last
-- two hide rather than gray while the first is off, exactly as in the Ace
-- panel. The Pages_Tooltips strip, with the section key, the copy body and
-- the labels swapped -- and the copy restricted to layouts of the SAME
-- TYPE, because sorting's keys are type-specific (raid grid keys vs the
-- party-only grow direction).

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Party flats first, then raid, each alphabetical by name; the ACTIVE
-- layout is tinted green, which is how the Ace dropdown has always shown
-- the difference between "active" and "being edited".
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

-- _modifyingFlat can be unset (a fresh session) or name a layout that has
-- since been deleted, so it falls back the same way the Ace dropdown does.
local function CurrentFlat()
    local bf = BF()
    local fl = FlatLayouts()
    local cur = bf and bf._modifyingFlat
    if cur and fl[cur] then return cur end
    if fl.flat_party then return "flat_party" end
    local opts = FlatOptions()
    return opts[1] and opts[1].value
end

local function NotPerLayout()
    local bf = BF()
    return not (bf and bf:IsPerLayoutSection("sorting"))
end

-- Every OTHER layout OF THE SAME TYPE: the ones a copy could target.
-- Party settings copied onto a raid layout (or the reverse) would plant
-- keys the target's type never reads, so cross-type targets are not
-- offered at all -- the restrictSameType behavior of the Ace dropdown.
local function CopyTargets()
    local fl  = FlatLayouts()
    local cur = CurrentFlat()
    local src = fl[cur]
    local t   = {}
    if not src then return t end
    for id, flat in pairs(fl) do
        if id ~= cur and type(flat) == "table" and flat.type == src.type then
            t[#t + 1] = { id = id, name = flat.name or id }
        end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

-- Copy the whole flat.sorting sub-table from the layout being modified
-- onto another. Tables are deep-copied, so the two layouts do not end up
-- sharing one table and silently editing each other afterwards. Falls back
-- to the global as the source when the toggle is on but this flat was
-- never seeded.
local function CopyTo(targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    local srcSection = src.sorting
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.sorting end
    if type(srcSection) ~= "table" then return end
    if type(dst.sorting) ~= "table" then dst.sorting = {} end

    for k, v in pairs(srcSection) do
        dst.sorting[k] = (type(v) == "table") and bf:DeepCopy(v) or v
    end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

local function ScopeStrip()
    return { preset = "strip", fields = {
        { control = "switch", label = "Enable per-Layout Config",
          -- State first, then what it is the state of.
          labelSide = "after",
          -- Off is the shipped state: settings are global until somebody
          -- asks for them not to be.
          id = "perLayoutSorting", default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default, these settings are global and affect all "
              .. "Layouts. Enabling this option will add the \"Modifying\" "
              .. "dropdown at the top of the panel, allowing you to have "
              .. "different settings for each Layout (e.g. Party vs Raid).",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSection("sorting")
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf = BF()
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight pass-through
              -- while that flag is off.
              if bf then bf:_TimeSectionPerLayout("sorting", v) end
              -- Flipping the toggle can change WHICH SECTIONS this page
              -- holds (per-layout ON shows only the modifying flat's
              -- type), so the page is rebuilt rather than refreshed.
              RebuildPage(ctx.app)
          end },

        { control = "dropdown", label = "Modifying",
          -- Labeled above, like any other dropdown, and sized rather than
          -- left to its 200px natural width: a layout name is short.
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited "
              .. "for. The currently active Layout is shown in green.",
          hidden = NotPerLayout, disabled = "combat",
          options = FlatOptions,
          get = function() return CurrentFlat() end,
          set = function(_, ctx, v)
              local bf = BF()
              if not bf then return end
              bf._modifyingFlat = v
              bf:InvalidateRaidProfileCache()
              if bf.UpdateAuraSizeCache then bf:UpdateAuraSizeCache() end
              -- The same post-change chain the Ace dropdown runs: swap the
              -- setup-mode test header to the new layout, re-position the
              -- test anchor to that layout's own saved anchor, and refresh
              -- the preview.
              if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
              if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              -- Every field on this page now reads a different layout's
              -- values, so the page is re-read whole...
              ctx.app:RefreshPage()
              -- ...and the new layout may be the OTHER type, which swaps
              -- which section this page holds, so it is also rebuilt.
              RebuildPage(ctx.app)
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy this Layout's sorting settings onto another Layout "
              .. "of the same type (party to party, raid to raid). Only "
              .. "available while per-Layout config is on -- without it "
              .. "every Layout already shares one set of settings.",
          disabled = "combat",
          -- Nothing to copy TO is the same as nothing to copy: the control
          -- goes rather than offering an empty list. With the same-type
          -- restriction that includes modifying the only layout of its
          -- type.
          hidden = function()
              return NotPerLayout() or #CopyTargets() == 0
          end,
          options = function()
              local out = {}
              local targets = CopyTargets()
              for _, e in ipairs(targets) do
                  out[#out + 1] = { value = e.id, text = e.name }
              end
              if #targets > 1 then
                  out[#out + 1] = { value = "__all", text = "All (same type)" }
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
                  text = ("Copy all Sorting settings from \"%s\" to all "
                      .. "other Layouts of the same type? This overwrites "
                      .. "every Sorting setting on them."):format(from)
              else
                  text = ("Copy all Sorting settings from \"%s\" to "
                      .. "\"%s\"? This overwrites every Sorting setting "
                      .. "on it."):format(from, LayoutName(v))
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do CopyTo(e.id) end
                  else
                      CopyTo(v)
                  end
              end)
          end },
    }}
end

-- ── The Party section ──────────────────────────────────────────
--
-- The Ace page's partyHeader + partyFrameSortNote + partySortingGroup +
-- partyGrowDirectionGroup, as a warning note and ONE card -- the two Ace
-- groups describe the same party layout, so they read as one. The "Party
-- Layout" header itself is folded into the card title, which already
-- carries the word.

local function PartyGroups(out)
    -- partyFrameSortNote: shown while the external sorter has ANY party
    -- area enabled, current context or not.
    out[#out + 1] = { preset = "bare", fields = {
        { control = "note", wide = true, color = WARNING_RED,
          text = function()
              local bf = BF()
              local areas = bf and bf.GetFrameSortEnabledPartyAreas
                  and bf:GetFrameSortEnabledPartyAreas()
              local areaStr = areas and table.concat(areas, ", ") or ""
              return "FrameSort is managing sort order for: " .. areaStr
                  .. ". The sorting settings below will not apply in those "
                  .. "contexts. Due to a FrameSort limitation, players "
                  .. "joining the group while in combat will not be "
                  .. "visible until combat ends."
          end,
          hidden = function() return not EnabledForParty() end },
    }}

    -- partySortingGroup + partyGrowDirectionGroup, as ONE card: the Ace
    -- panel's split put two cards' worth of chrome around four settings
    -- that all describe the same party layout.
    out[#out + 1] = { title = "Party Options", preset = "form", fields = {
        { control = "dropdown", label = "Role Order",
          bind = "groupOrderingMode",
          desc = "Order in which roles appear in the party layout.",
          options = {
              { value = "TANK_HEALER_DPS", text = "Tank / Healer / DPS" },
              { value = "HEALER_TANK_DPS", text = "Healer / Tank / DPS" },
              { value = "HEALER_DPS_TANK", text = "Healer / DPS / Tank" },
              { value = "TANK_DPS_HEALER", text = "Tank / DPS / Healer" },
              { value = "DPS_TANK_HEALER", text = "DPS / Tank / Healer" },
              { value = "DPS_HEALER_TANK", text = "DPS / Healer / Tank" },
          },
          onChange = ReloadAndSetup, disabled = PartyDisabled },

        { control = "switch", label = "Hide Self", bind = "hideSelf",
          desc = "Hide your own frame from the party layout.",
          onChange = ReloadAndSetup, disabled = PartyDisabled },

        -- The growDirection and growFromCenter setters convert the stored
        -- anchor so the frames do not move; they need the flat and the
        -- on-screen anchor geometry mid-write, so they keep get/set pairs
        -- (with id + default, so reset and undo still work) rather than
        -- binding.
        { control = "dropdown", label = "Grow Direction",
          id = "growDirection", default = DefaultSP("growDirection"),
          desc = "Which direction party frames grow from the anchor point.",
          options = {
              { value = "RIGHT", text = "Right (horizontal)" },
              { value = "LEFT",  text = "Left (horizontal)" },
              { value = "DOWN",  text = "Down (vertical)" },
              { value = "UP",    text = "Up (vertical)" },
          },
          get = function()
              local sp = GetSP()
              return sp and sp.growDirection or "RIGHT"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              sp.growDirection = val
              local flat = bf:GetModifyingProfile()
              -- Grow from Center (party): the CENTER pin is
              -- direction-independent -- the block centers on both axes
              -- regardless of grow direction, so changing direction only
              -- re-flows the frames inside; keep coordinates untouched
              -- (the corner is still stored for toggle-off).
              if flat and flat.type == "party" and sp.growFromCenter then
                  flat.partyLayoutAnchor = bf:DeriveGroupAnchor(val, nil)
              elseif flat and flat.type == "party" then
                  local newLA = bf:DeriveGroupAnchor(val, nil)
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local newX = newLA:find("LEFT") and af:GetLeft() or af:GetRight()
                      local newY = newLA:find("TOP") and af:GetTop() or af:GetBottom()
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
                  flat.partyLayoutAnchor = newLA
              end
              ReloadAnchorSetup()
          end,
          disabled = "combat" },

        { control = "switch", label = "Grow from Center",
          id = "growFromCenter", default = DefaultSP("growFromCenter"),
          desc = "Pin the party layout by its center instead of a corner. "
              .. "Frames expand evenly in both directions as party members "
              .. "are added or removed. The anchor position is converted "
              .. "so the frames don't move when toggling.",
          get = function()
              local sp = GetSP()
              return sp and sp.growFromCenter == true
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              local flat = bf:GetModifyingProfile()
              -- Grow-from-Center keeps the full-party REGION fixed and
              -- moves the frames WITHIN it. The region CENTER is the
              -- invariant -- af:GetCenter() yields it in both modes -- so:
              --   ON  -> store the region center.
              --   OFF -> store the corner = center -/+ half the FULL
              --          region extent (GetConfiguredGridExtent), NOT the
              --          content edge.
              if flat and flat.type == "party" then
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local cx, cy = af:GetCenter()
                      local newX, newY
                      if val then
                          newX, newY = cx, cy
                      else
                          local la = flat.partyLayoutAnchor or "TOPLEFT"
                          local fullW, fullH = bf:GetConfiguredGridExtent(flat, true)
                          fullW = fullW or 0
                          fullH = fullH or 0
                          newX = la:find("LEFT") and (cx - fullW / 2)
                                 or la:find("RIGHT") and (cx + fullW / 2) or cx
                          newY = la:find("TOP") and (cy + fullH / 2)
                                 or la:find("BOTTOM") and (cy - fullH / 2) or cy
                      end
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
              end
              sp.growFromCenter = val
              ReloadAnchorSetup()
          end,
          disabled = "combat" },

        -- partyLayoutAnchor: auto-derived from Grow Direction, hidden from
        -- the UI in the Ace panel and here alike. Carried across so the
        -- two pages describe the same set of settings.
        { control = "dropdown", label = "Layout Anchor",
          hidden = true,
          desc = "Which corner of the layout rectangle stays fixed on "
              .. "screen. When you change Grow Direction, frames rearrange "
              .. "within the same bounding box because this corner stays "
              .. "pinned.",
          options = {
              { value = "TOPLEFT",     text = "Top Left" },
              { value = "TOPRIGHT",    text = "Top Right" },
              { value = "BOTTOMLEFT",  text = "Bottom Left" },
              { value = "BOTTOMRIGHT", text = "Bottom Right" },
          },
          get = function()
              local bf = BF()
              local flat = bf and bf:GetModifyingProfile()
              return (flat and flat.partyLayoutAnchor) or "TOPLEFT"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local flat = bf:GetModifyingProfile()
              if not flat or flat.type ~= "party" then return end
              local af = GetVisibleAnchor()
              if af and af:GetLeft() then
                  local ux, uy = UIParent:GetCenter()
                  local newX = val:find("LEFT") and af:GetLeft() or af:GetRight()
                  local newY = val:find("TOP") and af:GetTop() or af:GetBottom()
                  if newX and newY and ux and uy then
                      flat.anchorX = math.floor(newX - ux + 0.5)
                      flat.anchorY = math.floor(newY - uy + 0.5)
                  end
              end
              flat.partyLayoutAnchor = val
              ReloadAnchorSetup()
          end,
          disabled = "combat" },
    }}
end

-- ── The Raid section ───────────────────────────────────────────
--
-- The Ace page's raidLayoutHeader + raidFrameSortNote + raidSortingGroup +
-- raidLayoutGroup, same shape as the party section.

-- Hidden while sorting is not by Group (base rule for the strict-layout
-- pair), shared by both fields below.
local function NotSortingByGroup()
    local sp = GetSP()
    return sp and sp.sortingMode ~= "GROUP"
end

-- unitsPerColumn helpers: the Ace widget renames itself by the raid grow
-- axis. The library sets a field's label once per render, so the rename is
-- two bound fields over the one storage key, each hidden on the other's
-- axis -- the predicates are watched, so flipping Grow Direction swaps
-- them on the next frame.
local function RaidGrowsHorizontally()
    local sp = GetSP()
    local dir = sp and sp.raidGrowDirection
    return dir == "RIGHT" or dir == "LEFT"
end

local function UnitsPerColumnHidden()
    local sp = GetSP()
    return sp and sp.sortingMode == "GROUP" and sp.strictGroupLayout
end

local function UnitsPerColumnDisabled()
    if RaidDisabled() then return true end
    local sp = GetSP()
    return sp and sp.sortingMode == "GROUP"
end

local function UnitsField(label, hiddenFn)
    return { control = "slider", label = label, bind = "unitsPerColumn",
        min = 1, max = 40, step = 1,
        desc = "How many units stack per column (vertical) or per row "
            .. "(horizontal).",
        hidden = hiddenFn,
        onChange = ReloadAndSetup,
        disabled = UnitsPerColumnDisabled }
end

local function RaidGroups(out)
    -- raidFrameSortNote: unlike the party note this one is settings-based
    -- too, but its text is fixed.
    out[#out + 1] = { preset = "bare", fields = {
        { control = "note", wide = true, color = WARNING_RED,
          text = "FrameSort is managing sort order for Raid. The sorting "
              .. "settings below are being overridden. Strict Group Layout "
              .. "cannot be used when FrameSort is enabled. Due to a "
              .. "FrameSort limitation, players joining the group while in "
              .. "combat will not be visible until combat ends.",
          hidden = function() return not EnabledForRaid() end },
    }}

    -- raidSortingGroup
    out[#out + 1] = { title = "Raid Sorting", preset = "form", fields = {
        { control = "dropdown", label = "Sorting Mode", bind = "sortingMode",
          desc = "How to organize raid frames. Group keeps players in "
              .. "their assigned raid groups. Role groups by "
              .. "tank/healer/dps.",
          options = {
              { value = "GROUP", text = "By Group (1-8)" },
              { value = "ROLE",  text = "By Role (Tank/Healer/DPS)" },
          },
          onChange = ReloadAndSetup, disabled = RaidDisabled },

        { control = "switch", label = "Strict Group Layout",
          bind = "strictGroupLayout",
          desc = "Each raid group always occupies its own column, even if "
              .. "the group isn't full. Only applies when sorting by Group.",
          hidden = NotSortingByGroup,
          onChange = ReloadAndSetup, disabled = RaidDisabled },

        -- strictGroupSortBy stores nil for its default (Index) rather than
        -- the value: with per-layout ON a per-flat table inherits from the
        -- global via __index, and the Ace setter's nil-normalization is
        -- part of the storage contract, so this one keeps get/set.
        { control = "dropdown", label = "Sort Within Groups",
          id = "strictGroupSortBy", default = DefaultSP("strictGroupSortBy"),
          desc = "How to sort units within each raid group column when "
              .. "using strict group layout.",
          options = {
              { value = "INDEX",        text = "Index" },
              { value = "NAME",         text = "Name" },
              { value = "ASSIGNEDROLE", text = "Role" },
              { value = "CLASS",        text = "Class" },
          },
          get = function()
              local sp = GetSP()
              return (sp and sp.strictGroupSortBy) or "INDEX"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              sp.strictGroupSortBy = (val ~= "INDEX") and val or nil
              bf:UpdatePartyFrames()
          end,
          hidden = function()
              local sp = GetSP()
              return (sp and sp.sortingMode ~= "GROUP")
                  or not (sp and sp.strictGroupLayout)
          end,
          disabled = RaidDisabled },
    }}

    -- raidLayoutGroup, in the Ace page's ORDER (1, 1.5, 1.7, 1.8, 2), not
    -- its declaration order.
    out[#out + 1] = { title = "Raid Grow Direction", preset = "form", fields = {
        { control = "dropdown", label = "Grow Direction",
          id = "raidGrowDirection", default = DefaultSP("raidGrowDirection"),
          desc = "Which direction frames grow from the anchor point.",
          options = {
              { value = "DOWN",  text = "Down (vertical)" },
              { value = "UP",    text = "Up (vertical)" },
              { value = "RIGHT", text = "Right (horizontal)" },
              { value = "LEFT",  text = "Left (horizontal)" },
          },
          get = function()
              local sp = GetSP()
              local dir = sp and sp.raidGrowDirection
              if dir == "RIGHT" or dir == "UP" or dir == "LEFT" then return dir end
              return "DOWN"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              -- Only reset secondary when orientation changes
              -- (vertical<->horizontal). DOWN<->UP and RIGHT<->LEFT stay
              -- on the same axis so the secondary is still valid.
              local oldDir = sp.raidGrowDirection or "DOWN"
              local oldH = (oldDir == "RIGHT" or oldDir == "LEFT")
              local newH = (val == "RIGHT" or val == "LEFT")
              if oldH ~= newH then
                  -- Reset to the default for the new axis. Store
                  -- explicitly rather than nil -- with per-layout ON, nil
                  -- would expose the global's stale value via __index
                  -- fallback.
                  local defaultSec = newH and "DOWN" or "RIGHT"
                  sp.raidSecondaryGrowDirection = defaultSec
              end
              sp.raidGrowDirection = val
              -- Auto-update raidLayoutAnchor to match the new grow
              -- direction and recalculate anchorX/anchorY so frames don't
              -- shift. Guard: only touch anchorX/Y and raidLayoutAnchor on
              -- raid flats -- when per-layout is OFF the modifying flat
              -- may be party-typed, and writing raid anchor coords onto a
              -- party flat would corrupt it.
              local flat = bf:GetModifyingProfile()
              -- Grow from Center: the anchor is a cross-axis EDGE derived
              -- from grow direction, so it is NOT direction-independent.
              -- Recompute anchorX/anchorY for the new edge (cross-axis
              -- center + grow-axis edge).
              if flat and flat.type == "raid" and sp.raidGrowFromCenter then
                  flat.raidLayoutAnchor = bf:DeriveGroupAnchor(val, sp.raidSecondaryGrowDirection)
                  local la = bf:GrowFromCenterAnchor(val)
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local cx, cy = af:GetCenter()
                      local newX = la:find("LEFT") and af:GetLeft()
                                   or la:find("RIGHT") and af:GetRight() or cx
                      local newY = la:find("TOP") and af:GetTop()
                                   or la:find("BOTTOM") and af:GetBottom() or cy
                      if af == bf.anchorFrame then
                          -- Live center mode: the anchor box's CROSS-axis
                          -- edges are CONTENT edges, so the reads above
                          -- are only region-correct in setup mode. Region
                          -- semantics: the new pin is the new edge's
                          -- midpoint on the OLD region -- af:GetCenter()
                          -- IS the old region's center even in center mode
                          -- -- so pin = center +/- half the OLD-direction
                          -- extent (oldDir: the new direction is already
                          -- written to sp at this point).
                          local fullW, fullH =
                              bf:GetConfiguredGridExtent(flat, false, oldDir)
                          if fullW then
                              newX = la:find("LEFT") and (cx - fullW / 2)
                                     or la:find("RIGHT") and (cx + fullW / 2) or cx
                              newY = la:find("TOP") and (cy + fullH / 2)
                                     or la:find("BOTTOM") and (cy - fullH / 2) or cy
                          end
                      end
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
              elseif flat and flat.type == "raid" then
                  local newLA = bf:DeriveGroupAnchor(val, sp.raidSecondaryGrowDirection)
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local newX = newLA:find("LEFT") and af:GetLeft() or af:GetRight()
                      local newY = newLA:find("TOP") and af:GetTop() or af:GetBottom()
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
                  flat.raidLayoutAnchor = newLA
              end
              ReloadAnchorSetup()
          end,
          disabled = "combat" },

        { control = "dropdown", label = "Secondary Grow Direction",
          id = "raidSecondaryGrowDirection",
          default = DefaultSP("raidSecondaryGrowDirection"),
          desc = "Which direction groups/columns extend perpendicular to "
              .. "the primary grow direction.",
          -- The choices depend on the primary axis, so the list is a
          -- function, resolved every time it is read.
          options = function()
              if RaidGrowsHorizontally() then
                  return { { value = "DOWN",  text = "Down" },
                           { value = "UP",    text = "Up" } }
              end
              return { { value = "RIGHT", text = "Right" },
                       { value = "LEFT",  text = "Left" } }
          end,
          get = function()
              local sp = GetSP()
              -- rawget bypasses the __index fallback to the global sorting
              -- table. When per-layout is ON the per-flat table inherits
              -- from the global via __index; a nil rawkey would expose a
              -- stale global value, showing the wrong selection (or blank
              -- if the global value doesn't match the current primary
              -- axis).
              local sec = sp and rawget(sp, "raidSecondaryGrowDirection")
              if sec then return sec end
              local dir = sp and sp.raidGrowDirection
              if dir == "RIGHT" or dir == "LEFT" then return "DOWN" end
              return "RIGHT"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              -- Always store the value explicitly rather than nilling out
              -- defaults. With per-layout ON the per-flat table has an
              -- __index fallback to the global; rawset(sp, key, nil) would
              -- just expose the global's (possibly stale) value.
              sp.raidSecondaryGrowDirection = val
              -- Auto-update raidLayoutAnchor and recalculate anchorX/Y so
              -- frames don't shift. Guard: only on raid flats (see the
              -- Grow Direction setter).
              local dir = sp.raidGrowDirection or "DOWN"
              local flat = bf:GetModifyingProfile()
              -- Grow from Center: the anchor EDGE is derived from the
              -- PRIMARY grow direction only, and the pinned edge and the
              -- cross-axis center are both invariant under a secondary
              -- flip, so anchorX/anchorY stay unchanged.
              if flat and flat.type == "raid" and sp.raidGrowFromCenter then
                  flat.raidLayoutAnchor = bf:DeriveGroupAnchor(dir, sp.raidSecondaryGrowDirection)
              elseif flat and flat.type == "raid" then
                  local newLA = bf:DeriveGroupAnchor(dir, sp.raidSecondaryGrowDirection)
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local newX = newLA:find("LEFT") and af:GetLeft() or af:GetRight()
                      local newY = newLA:find("TOP") and af:GetTop() or af:GetBottom()
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
                  flat.raidLayoutAnchor = newLA
              end
              ReloadAnchorSetup()
          end,
          disabled = "combat" },

        { control = "switch", label = "Grow from Center",
          id = "raidGrowFromCenter", default = DefaultSP("raidGrowFromCenter"),
          desc = "Pin the raid layout by its center instead of a corner. "
              .. "The frame block expands evenly in both directions as "
              .. "groups fill or empty. The anchor position is converted "
              .. "so the frames don't move when toggling.",
          get = function()
              local sp = GetSP()
              return sp and sp.raidGrowFromCenter == true
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local sp = GetSP()
              if not sp then return end
              local flat = bf:GetModifyingProfile()
              -- Convert stored anchor coordinates so the layout box stays
              -- put: CENTER-edge offsets when turning on, the
              -- raidLayoutAnchor corner offsets when turning off (party
              -- growFromCenter parity).
              if flat and flat.type == "raid" then
                  local af = GetVisibleAnchor()
                  if af and af:GetLeft() then
                      local ux, uy = UIParent:GetCenter()
                      local newX, newY
                      if val then
                          -- Turning ON: the block is pinned by its
                          -- grow-from-center EDGE anchor (TOP for DOWN,
                          -- LEFT for RIGHT, ...), which centers only the
                          -- cross-axis. Read that edge point of the
                          -- current (full-grid) anchor frame: center on
                          -- the cross-axis, edge on the grow axis, so the
                          -- block doesn't move.
                          local la = bf:GrowFromCenterAnchor(sp.raidGrowDirection or "DOWN")
                          local cx, cy = af:GetCenter()
                          newX = la:find("LEFT") and af:GetLeft()
                                 or la:find("RIGHT") and af:GetRight() or cx
                          newY = la:find("TOP") and af:GetTop()
                                 or la:find("BOTTOM") and af:GetBottom() or cy
                      else
                          -- Turning OFF: re-anchor the corner of the
                          -- configured full-grid REGION, not of the anchor
                          -- box. The region stays pinned and the frames
                          -- jump back to growing from its corner (setup
                          -- mode, whose test anchor is always full-grid
                          -- sized, is the reference behavior).
                          local la = flat.raidLayoutAnchor or "TOPLEFT"
                          newX = la:find("LEFT") and af:GetLeft() or af:GetRight()
                          newY = la:find("TOP")  and af:GetTop()  or af:GetBottom()
                          if af == bf.anchorFrame then
                              -- Live center mode: the real anchorFrame's
                              -- CROSS-axis is content-sized, so the reads
                              -- above give CONTENT edges on that axis.
                              -- Replace the cross-axis value with pin +/-
                              -- half the configured extent (the pin is the
                              -- anchor box's cross-axis center; its
                              -- grow-axis edges are full-length even in
                              -- center mode, so those reads stand).
                              local dir = sp.raidGrowDirection or "DOWN"
                              local fullW, fullH =
                                  bf:GetConfiguredGridExtent(flat, false)
                              if fullW then
                                  local px, py = af:GetCenter()
                                  if dir == "RIGHT" or dir == "LEFT" then
                                      newY = la:find("TOP") and (py + fullH / 2)
                                             or (py - fullH / 2)
                                  else
                                      newX = la:find("LEFT") and (px - fullW / 2)
                                             or (px + fullW / 2)
                                  end
                              end
                          end
                      end
                      if newX and newY and ux and uy then
                          flat.anchorX = math.floor(newX - ux + 0.5)
                          flat.anchorY = math.floor(newY - uy + 0.5)
                      end
                  end
              end
              sp.raidGrowFromCenter = val
              ReloadAnchorSetup()
          end,
          disabled = "combat" },

        -- layoutAnchor: auto-derived from Grow Direction, hidden from the
        -- UI in the Ace panel and here alike.
        { control = "dropdown", label = "Layout Anchor",
          hidden = true,
          desc = "Which corner of the layout rectangle stays fixed on "
              .. "screen. When you change Grow Direction, frames rearrange "
              .. "within the same bounding box because this corner stays "
              .. "pinned.",
          options = {
              { value = "TOPLEFT",     text = "Top Left" },
              { value = "TOPRIGHT",    text = "Top Right" },
              { value = "BOTTOMLEFT",  text = "Bottom Left" },
              { value = "BOTTOMRIGHT", text = "Bottom Right" },
          },
          get = function()
              local bf = BF()
              local flat = bf and bf:GetModifyingProfile()
              return (flat and flat.raidLayoutAnchor) or "TOPLEFT"
          end,
          set = function(_, _, val)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              local flat = bf:GetModifyingProfile()
              if not flat or flat.type ~= "raid" then return end
              -- Recalculate anchorX/anchorY so frames don't visually
              -- shift.
              local af = GetVisibleAnchor()
              if af and af:GetLeft() then
                  local ux, uy = UIParent:GetCenter()
                  local newX = val:find("LEFT") and af:GetLeft() or af:GetRight()
                  local newY = val:find("TOP") and af:GetTop() or af:GetBottom()
                  if newX and newY and ux and uy then
                      flat.anchorX = math.floor(newX - ux + 0.5)
                      flat.anchorY = math.floor(newY - uy + 0.5)
                  end
              end
              flat.raidLayoutAnchor = val
              ReloadAnchorSetup()
          end,
          disabled = RaidDisabled },

        -- unitsPerColumn, twice: same bind, the label the current grow
        -- axis wants, the other hidden.
        UnitsField("Units per Column", function()
            return UnitsPerColumnHidden() or RaidGrowsHorizontally()
        end),
        UnitsField("Units per Row", function()
            return UnitsPerColumnHidden() or not RaidGrowsHorizontally()
        end),
    }}
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:SortingPage()
    local groups = { ScopeStrip() }
    if not HidePartySection() then PartyGroups(groups) end
    if not HideRaidSection()  then RaidGroups(groups)  end
    return {
        -- The routed storage, wearing the shape of a table. Every `bind`
        -- on this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- which is what
        -- makes the right-click "Reset to default" work on every bound
        -- field without any of them declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end
