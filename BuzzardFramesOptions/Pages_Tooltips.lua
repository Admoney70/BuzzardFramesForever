-- ============================================================
-- BuzzardFramesOptions: Pages_Tooltips.lua
-- The Raid/Party Frames > Tooltips page, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Tooltips.lua:
-- the same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by a BuzzardPanel page. Both descriptions
-- exist while both panels do; an edit in either lands in the same place,
-- so they cannot drift apart in what they STORE -- only in what they show.
--
-- Storage: rpDB.profile.tooltips.* (the global pseudo-layout), or
-- flat.tooltips.* when layouts.perLayoutToggles.tooltips is on. Every
-- field reads and writes through GetTP() / SetTP(), which route through
-- BuzzardFrames:GetSectionProfile("tooltips", GetModifyingProfile()) --
-- the same routed path the Ace page uses. Nothing here writes a db table
-- directly, which is what keeps the two panels in step.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- The section profile currently being modified. With the per-layout toggle
-- OFF, GetSectionProfile ignores the flat and returns the global; with it
-- ON it returns the modifying flat's tooltips, so the user sees and edits
-- the per-flat copy.
local function GetTP()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("tooltips", bf:GetModifyingProfile())
end

-- Unit-tooltip keys feed the unit-frame Tooltip indicator, which reads its
-- settings live in OnEnter -- so changing one needs no aura refresh at all.
-- Every other key feeds ApplyAuraTooltips, which runs in the indicators'
-- restyle walk and does need one.
local UNIT_TOOLTIP_KEYS = {
    showUnitTooltip         = true,
    showUnitTooltipInCombat = true,
    unitTooltipPosition     = true,
}

-- The one setter, side effects and all -- the panel's copy of Options_-
-- Tooltips.lua's setTP. Kept in the same order for the same reason it is
-- in that order there: the caches must be stale-marked BEFORE anything
-- reads through them again.
local function SetTP(key, val)
    if InCombatLockdown() then return end
    local bf = BF()
    if not bf then return end

    local tp = GetTP()
    if tp then tp[key] = val end

    -- Mark flat caches dirty so the aura size cache picks the new value up.
    -- Per-layout ON needs the modifying flat; OFF needs every flat that
    -- falls through to the global.
    if bf:IsPerLayoutSection("tooltips") then
        bf:InvalidateFlatAuraCache(bf:GetModifyingProfile())
    else
        bf:InvalidateGlobalSectionFlatCaches("tooltips")
    end
    bf:InvalidateRaidProfileCache()

    if not UNIT_TOOLTIP_KEYS[key] then
        bf:RefreshAllAuras()
    end
    if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source: a copy here would be a second answer to the same question, and
-- the two would part company the first time a default changed.
--
-- This is what makes the panel's own right-click "Reset to default" and
-- "Reset group to defaults" work on these fields: they have no `bind` to
-- look a default up by, so they declare one outright (and an `id`, which
-- is the key an undo is recorded under).
local function DefaultTP(key)
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile and d.profile.tooltips
    return d and d[key]
end

local function Get(key)
    return function()
        local tp = GetTP()
        return tp and tp[key]
    end
end

-- A field's set is called as set(node, ctx, value) and its get as
-- get(node, ctx) -- the node and the context first, the value last.
local function Set(key)
    return function(_, _, v) SetTP(key, v) end
end

-- ── The per-layout row ──────────────────────────────────────────
--
-- Three controls that are ABOUT the settings rather than settings
-- themselves: whether this section is configured per layout, which layout
-- is being edited, and copying what is here onto another layout. The last
-- two are meaningless while the first is off -- every layout shares the
-- global then, so a copy is a no-op -- and they hide rather than gray,
-- exactly as they do in the Ace panel.

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
    return not (bf and bf:IsPerLayoutSection("tooltips"))
end

-- Every OTHER layout: the ones a copy could target.
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

-- Copy flat.tooltips from the layout being modified onto another. Tables
-- are deep-copied, so the two layouts do not end up sharing one table and
-- silently editing each other afterwards. Falls back to the global as the
-- source when the toggle is on but this flat was never seeded.
local function CopyTo(targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    local srcSection = src.tooltips
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.tooltips end
    if type(srcSection) ~= "table" then return end
    if type(dst.tooltips) ~= "table" then dst.tooltips = {} end

    for k, v in pairs(srcSection) do
        dst.tooltips[k] = (type(v) == "table") and bf:DeepCopy(v) or v
    end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

-- On 12.1 the AURA tooltip is a forbidden-partition frame with no
-- game-default-position expression, so it has no "Default" choice and a
-- legacy stored "default" reads as "Below Frame". The unit tooltip is a
-- real GameTooltip and keeps Default.
local AURA_TT_POSITIONS = {
    { value = "icon",   text = "Cursor - Bottom Right" },
    { value = "iconTR", text = "Cursor - Top Right" },
    { value = "frame",  text = "Below Frame" },
}
local UNIT_TT_POSITIONS = {
    { value = "default", text = "Default" },
    { value = "icon",    text = "Cursor - Bottom Right" },
    { value = "iconTR",  text = "Cursor - Top Right" },
    { value = "frame",   text = "Below Frame" },
}

local function GetAuraPos(key)
    return function()
        local tp = GetTP()
        local v  = tp and tp[key]
        if v == nil or v == "default" then return "frame" end
        return v
    end
end

-- One block: a show toggle, and under it the two fields that only mean
-- anything while it is on. Four of these differ by nothing but their keys
-- and their names, so they are built rather than written out four times.
local function TooltipGroup(title, showKey, combatKey, posKey, showLabel, positions, getPos)
    return {
        title  = title,
        -- Natural widths, remainder of the row left empty -- see the
        -- preset's declaration in Panel.lua.
        preset = "form",
        -- The setting the whole card is about lives in its HEADER: the two
        -- fields below only mean anything while it is on, and a card that
        -- collapses says that more plainly than two fields that vanish.
        toggle = {
            id      = showKey,
            default = DefaultTP(showKey),
            -- The header's title names the SECTION; the switch names the
            -- setting, and only its tooltip has room to say so.
            tooltip = showLabel,
            get     = function() local tp = GetTP(); return tp and tp[showKey] end,
            set     = function(_, _, v) SetTP(showKey, v) end,
        },
        fields = {
            -- Position first: it is what the card is mostly about once the
            -- gate is on, and the combat toggle is a qualifier on top of it.
            { control = "dropdown", label = "Tooltip Position", id = posKey,
              default = DefaultTP(posKey),
              options = positions,
              get = getPos or Get(posKey), set = Set(posKey),
              disabled = "combat" },
            { control = "switch", label = "Show in Combat", id = combatKey,
              default = DefaultTP(combatKey),
              get = Get(combatKey), set = Set(combatKey),
              disabled = "combat" },
        },
    }
end

function BuzzardFramesOptions:TooltipsPage()
    return {
        groups = {
            -- The per-layout switch is meta-configuration, not a tooltip
            -- setting, so it stands alone above the sections rather than
            -- leading one of them. The "bare" preset (declared in
            -- Panel.lua) is a group with no card and no header, which is
            -- what makes it read as a single standalone control.
            -- A flat bar rather than a card: this row is ABOUT the
            -- settings below it, not one of them. `strip` is the library's
            -- preset for exactly that -- own surface, own border, no
            -- heading, labels beside their controls, and the first field
            -- held at the left while the rest go to the right edge.
            -- `scopeStrip` marks this card as the RAID/PARTY per-Layout row.
            -- "Per-Layout" means "per Raid/Party Layout", and a Custom Frame
            -- Group is not a Layout -- it is its own scope -- so the Custom
            -- Frame Groups assembler drops the card rather than rendering a
            -- control that would edit the wrong thing.
            { preset = "strip", scopeStrip = true, fields = {
                { control = "switch", label = "Enable per-Layout Config",
                  -- State first, then what it is the state of.
                  labelSide = "after",
                  -- Off is the shipped state: settings are global until
                  -- somebody asks for them not to be.
                  id = "perLayoutTooltips", default = false,
                  -- Ace's |cff87ceeb sky blue, kept to the digit: this
                  -- switch configures the CONFIGURATION rather than the
                  -- addon, and the color is how a reader has always been
                  -- told the difference.
                  labelColor = { 0.53, 0.81, 0.92, 1.00 },
                  desc = "When off, these settings are global and affect "
                      .. "every Layout. Turn this on if you wish to have "
                      .. "different settings per-Layout for the options "
                      .. "below. (e.g. show Unit Tooltips on Party frames "
                      .. "but not Raid frames).",
                  disabled = "combat",
                  get = function()
                      local bf = BF()
                      return bf and bf:IsPerLayoutSection("tooltips")
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local bf = BF()
                      -- Routed through the timing wrapper, so the cost can
                      -- be measured in-game with debugTiming. A straight
                      -- pass-through while that flag is off.
                      if bf then bf:_TimeSectionPerLayout("tooltips", v) end
                  end },

                { control = "dropdown", label = "Modifying",
                  -- Labeled above, like any other dropdown, and
                  -- sized rather than left to its 200px natural
                  -- width: a layout name is short.
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
                      -- The same post-change chain the Ace dropdown runs:
                      -- swap the setup-mode test header to the new layout,
                      -- re-position the test anchor to that layout's own
                      -- saved anchor, and refresh the preview.
                      if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
                      if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
                      if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
                      -- Every field on this page now reads a different
                      -- layout's values, so the page is re-read whole.
                      ctx.app:RefreshPage()
                  end },

                { control = "dropdown", label = "Copy to",
                  -- Labeled above, like any other dropdown, and
                  -- sized rather than left to its 200px natural
                  -- width: a layout name is short.
                  labelPlacement = "above",
                  desc = "Copy this Layout's tooltip settings onto another "
                      .. "Layout. Only available while per-Layout config is "
                      .. "on -- without it every Layout already shares one "
                      .. "set of settings.",
                  disabled = "combat",
                  -- Nothing to copy TO is the same as nothing to copy: the
                  -- control goes rather than offering an empty list.
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
                          out[#out + 1] = { value = "__all", text = "All Layouts" }
                      end
                      return out
                  end,
                  -- A copy is an ACTION, not a setting: the dropdown never
                  -- shows a current value, it just offers destinations.
                  get = function() return nil end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      local from = LayoutName(CurrentFlat())
                      local text
                      if v == "__all" then
                          text = ("Copy all Tooltips settings from \"%s\" to "
                              .. "all other Layouts? This overwrites every "
                              .. "Tooltips setting on them."):format(from)
                      else
                          text = ("Copy all Tooltips settings from \"%s\" to "
                              .. "\"%s\"? This overwrites every Tooltips "
                              .. "setting on it."):format(from, LayoutName(v))
                      end
                      ctx.app:Confirm(text, function()
                          if v == "__all" then
                              for _, e in ipairs(CopyTargets()) do CopyTo(e.id) end
                          else
                              CopyTo(v)
                          end
                      end)
                  end },
            }},

            TooltipGroup("Unit Tooltips",
                "showUnitTooltip", "showUnitTooltipInCombat", "unitTooltipPosition",
                "Show Unit Tooltips", UNIT_TT_POSITIONS),

            TooltipGroup("Buff Tooltips",
                "showBuffTooltip", "showBuffTooltipInCombat", "buffTooltipPosition",
                "Show Buff Tooltips", AURA_TT_POSITIONS,
                GetAuraPos("buffTooltipPosition")),

            TooltipGroup("Debuff Tooltips",
                "showDebuffTooltip", "showDebuffTooltipInCombat", "debuffTooltipPosition",
                "Show Debuff Tooltips", AURA_TT_POSITIONS,
                GetAuraPos("debuffTooltipPosition")),

            TooltipGroup("Big Defensive Icon Tooltips",
                "showBigDefTooltip", "showBigDefTooltipInCombat", "bigDefTooltipPosition",
                "Show Big Defensive Icon Tooltips", AURA_TT_POSITIONS,
                GetAuraPos("bigDefTooltipPosition")),
        },
    }
end
