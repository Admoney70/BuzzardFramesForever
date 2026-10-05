-- ============================================================
-- BuzzardFramesOptions: Pages_Borders.lua
-- The Raid/Party Frames > Borders & Highlights section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Borders.lua: the
-- same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by five BuzzardPanel pages -- one per
-- subtab (borderTab, targetHighlightTab, mouseoverTab, aggroTab,
-- debuffTab), each a route of its own under `raidPartyFrames/borders`,
-- drawn as a strip by the `tabs` navigator that node declares -- the
-- Pages_Icons arrangement exactly.
--
-- Storage: rpDB.profile.borders.* (the global pseudo-layout), or
-- flat.borders.* for whichever keys belong to a subtab whose own
-- borders_<subtab> toggle is on. That routing is PER KEY and it is not
-- this file's business: reads go through BF:GetSectionProfile("borders",
-- ...) -- which answers with the merged view -- and writes through
-- BF:WriteSectionKey / BF:SectionKeyTable, exactly as the Ace page's
-- getSP/writeSP do. Nothing here touches a db table directly, which is
-- what keeps the two panels in step.
--
-- The debuff subtab (Ace: debuffTab) stores NOTHING here: the debuff
-- highlight settings moved to auras.dispelIndicator long ago, and its page
-- is a signpost -- a note and a button that navigates to Debuffs >
-- Dispellable Debuffs (Ace: goToDispelIndicatorNote / goToDispelIndicator
-- deep-linking to raidPartyFrames > aurasDebuffs > tabDispel).
--
-- Scalar fields are BOUND through the write-through ROOT below, which is
-- what makes right-click Undo and Reset work on them for free. The color
-- fields cannot bind -- the panel's color control trades in { r, g, b, a }
-- ARRAYS while Buzzard Frames stores named { r=, g=, b=, a= } tables -- so
-- they carry get/set adapters that keep storing the named shape, plus an
-- `id` and a `default` so undo and reset still work on them.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- The section as it reads right now: the merged view for the modifying
-- Layout, which degrades to the global wherever no subtab is per-Layout.
-- The Ace page's getSP().
local function GetSP()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("borders", bf:GetModifyingProfile())
end

-- One key out of the merged view -- the Ace page's getSPKey(), used by
-- every disabled/hidden predicate on these pages.
local function Key(key)
    local sp = GetSP()
    return sp and sp[key]
end

-- Is a ROUNDED frame border actually being drawn? A rounded borderStyle
-- with the border switched OFF draws nothing, so rectangular highlight
-- art (Blizzard Style / Glow Border) is legal in that case. Same rule as
-- the container's own `enableBorder and IsRoundedStyle(style)`.
local function IsRoundedActive()
    local bf = BF()
    if not bf then return false end
    if Key("enableBorder") == false then return false end
    return bf.IsRoundedBorderStyle(Key("borderStyle")) and true or false
end

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db and reading or writing the slot it lands on. Borders has no such
-- table: what a key READS from and what it WRITES to are decided per key,
-- by that key's subtab and that subtab's per-Layout toggle, and the read
-- side is a CACHED COPY that must never be written to. So the page hands
-- the library a table shaped like the one it wants and routed like the
-- one Buzzard Frames has -- the Pages_Icons ROOT/SubTable pattern.
local subCache = {}

local function SubTable(key)
    local w = subCache[key]
    if w then return w end
    w = setmetatable({}, {
        __index = function(_, k)
            local sp = GetSP()
            local t = sp and sp[key]
            return t and t[k]
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local bf = BF()
            -- SectionKeyTable returns the table to MUTATE -- the flat's own
            -- copy when this key's subtab is per-Layout, the global's
            -- otherwise. Never the merged view.
            local t = bf and bf:SectionKeyTable("borders", key)
            if t then t[k] = v end
        end,
    })
    subCache[key] = w
    return w
end

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local sp = GetSP()
        local v = sp and sp[k]
        if type(v) == "table" then return SubTable(k) end
        return v
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if bf then bf:WriteSectionKey("borders", k, v) end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.borders
end

-- A color default in the shape the panel's color control trades in --
-- built from the addon's own defaults table, never restated here. Nil for
-- a key the defaults table does not carry (there is then no Reset entry,
-- exactly as the Ace page had no default for it either).
local function ColorDefault(key, withAlpha)
    local d = Defaults()
    local c = d and d[key]
    if type(c) ~= "table" then return nil end
    if withAlpha then return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 } end
    return { c.r, c.g, c.b, 1 }
end

-- ── Side effects ───────────────────────────────────────────────
--
-- The Ace setters' effect chains, one function per chain link, named for
-- the debounce key each uses. The keys are the SAME ones the Ace page
-- uses ("bordersLayout", "bordersThreat", "bordersTargetHL"), so an edit
-- in either panel coalesces with the other's pending work rather than
-- running beside it.

local function BordersLayout()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("bordersLayout", function()
        for f in pairs(bf.activeFrames or {}) do bf:LayoutFrame(f) end
    end)
end

local function BordersThreat()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("bordersThreat", function()
        for f in pairs(bf.activeFrames or {}) do bf:UpdateThreat(f) end
    end)
end

local function BordersTargetHL()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("bordersTargetHL", function()
        for f in pairs(bf.activeFrames or {}) do bf:UpdateTarget(f) end
    end)
end

local function PreviewLayout()
    local bf = BF()
    if bf and bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

local function PreviewAggro()
    local bf = BF()
    if bf and bf.RefreshPreviewAggro then bf:RefreshPreviewAggro() end
end

-- The border-style highlights follow `enableBorder AND rounded`
-- (IsRoundedActive), so toggling the border or changing its style switches
-- them ring<->edges -- refresh all three the way the Ace setters do
-- (owner report: the target highlight stayed rounded after disabling a
-- rounded border). Immediate, not debounced, exactly as in the source.
local function RefreshHighlights()
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do
        bf:UpdateTarget(f)
        bf:UpdateThreat(f)
        if bf.UpdateDebuffHighlight then bf:UpdateDebuffHighlight(f) end
    end
end

-- Write debuffBorderWidth, which lives in the AURAS section
-- (auras.dispelIndicator), not borders -- routed exactly like the Ace
-- page's setDebuffBorderWidth so per-layout ON/OFF both land right.
-- Used when a rounded border style seeds the border-highlight widths.
-- Routes on the dispelIndicator sub-category's OWN per-layout toggle
-- (auras_dispelIndicator) rather than the coarse "auras" alias, which
-- would answer true whenever some unrelated sub-category was ON and send
-- this write to a flat that nothing reads it from. The invalidation call
-- likewise takes that exact toggle key -- InvalidateGlobalSectionFlatCaches
-- early-returns when its argument's toggle is ON.
local function SetDebuffBorderWidth(sz)
    local bf = BF()
    if not bf then return end
    local modifying = bf:GetModifyingProfile()
    if bf:IsPerLayoutAurasSubcat("dispelIndicator") then
        local sub = bf:GetOrCreateAurasSubCategory(modifying, "dispelIndicator")
        if sub then sub.debuffBorderWidth = sz end
        bf:InvalidateFlatAuraCache(modifying)
    else
        local gp = bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.auras
        if gp then
            gp.dispelIndicator = gp.dispelIndicator or {}
            gp.dispelIndicator.debuffBorderWidth = sz
        end
        bf:InvalidateGlobalSectionFlatCaches("auras_dispelIndicator")
    end
    bf:InvalidateRaidProfileCache()
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Borders carries FOUR per-Layout toggles, one per storing subtab
-- (borders_border through borders_aggro), so the strip belongs to the
-- subtab rather than the section -- and Copy to moves that subtab's keys
-- and no others. The debuff subtab stores nothing and takes no strip.
-- This is the Pages_Icons ScopeStrip with the section key swapped.

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

    local keys = bf.SECTION_SUBTAB_KEYS and bf.SECTION_SUBTAB_KEYS.borders
    keys = keys and keys[subtabId]
    if not keys then return end

    local srcSection = rawget(src, "borders")
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.borders end
    if type(srcSection) ~= "table" then return end

    if type(rawget(dst, "borders")) ~= "table" then
        dst.borders = {}
        -- A flat's section table falls THROUGH to the global for anything
        -- it does not hold. A table created without that wiring answers nil
        -- for every key this copy does not carry.
        if bf.WireSectionFallback then bf:WireSectionFallback(dst, "borders") end
    end
    local dstSection = rawget(dst, "borders")

    for _, k in ipairs(keys) do
        local v = srcSection[k]
        if v ~= nil then
            dstSection[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("borders") end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function TogKey(subtabId)
    local bf = BF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and bf.SECTION_SUBTAB_TOGGLE.borders
    return m and m[subtabId]
end

local function NotPerLayout(subtabId)
    return function()
        local bf = BF()
        return not (bf and bf:IsPerLayoutSectionSubtab("borders", subtabId))
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
          id = TogKey(subtabId) or ("borders_" .. subtabId), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give " .. label .. " its own "
              .. "settings per Layout -- the other Borders & Highlights "
              .. "subtabs keep their own toggles.",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSectionSubtab("borders", subtabId)
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
              .. "Borders & Highlights is left alone.",
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

-- ── Color adapters ────────────────────────────────────────────
--
-- The color control reads and writes { r, g, b, a } ARRAYS; the profile
-- stores named tables. These adapters translate at the field boundary and
-- keep storing the named shape, so the Ace panel and the runtime readers
-- see exactly what they always saw.

-- Read a stored color as an array, with the Ace getter's own fallback.
local function GetColor(key, fr, fg, fb, withAlpha)
    return function()
        local c = Key(key)
        local r = c and c.r or fr
        local g = c and c.g or fg
        local b = c and c.b or fb
        if withAlpha then
            local a = (c and c.a ~= nil) and c.a or 1
            return { r, g, b, a }
        end
        return { r, g, b, 1 }
    end
end

-- Write a highlight color IN PLACE on the section sub-table so any
-- metatable fallback remains intact (AceDB defaults re-seed missing
-- sub-tables on profile reset, not individual color keys) -- exactly the
-- Ace setter's branch pair for targetHighlightColor / mouseoverHighlightColor.
local function SetHighlightColor(key, effect)
    return function(_, _, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if not bf then return end
        local c = Key(key)
        if c then
            c.r, c.g, c.b = v[1], v[2], v[3]
        else
            bf:WriteSectionKey("borders", key, { r = v[1], g = v[2], b = v[3] })
        end
        if effect then effect() end
    end
end

-- The three threat colors differ by nothing but their key, name, desc and
-- fallback, so they are declared as data and built.
local DisabledUnlessAggro = function()
    return InCombatLockdown() or not Key("aggroEnabled")
end

-- `newRow` is passed for the FIRST of the three, which is what puts the
-- threat colors on a line of their own rather than letting them flow up
-- behind whichever style-dependent field happened to be showing.
local function AggroColorField(key, label, desc, fr, fg, fb, newRow)
    return {
        control = "color", label = label, desc = desc,
        id = key, default = ColorDefault(key, false),
        newRow = newRow or nil,
        disabled = DisabledUnlessAggro,
        get = GetColor(key, fr, fg, fb, false),
        set = function(_, _, v)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            bf:WriteSectionKey("borders", key, { r = v[1], g = v[2], b = v[3] })
            BordersThreat()
            PreviewAggro()
        end,
    }
end

-- ── The five pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list that
-- builds the pages: the first four ids ARE the subtab ids in
-- BF.SECTION_SUBTABS.borders, so the per-Layout toggles line up by
-- construction. The fifth (debuff) is the signpost tab and owns no storage
-- and no toggle. Order is the Ace page's own tab order (borderTab,
-- targetHighlightTab, mouseoverTab, aggroTab, debuffTab).
BuzzardFramesOptions.BORDERS_SUBTABS = {
    { id = "border",          title = "Border" },
    { id = "targetHighlight", title = "Target Highlight" },
    { id = "mouseover",       title = "Mouseover Highlight" },
    { id = "aggro",           title = "Aggro Highlight" },
    { id = "debuff",          title = "Debuff Highlight" },
}

-- A gate in the card HEADER, and the card collapses when it is off --
-- the Ace page's hiddenUnless() made visible. `id` and `default` are what
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
            if effect then effect(v) end
        end,
    }
end

local PAGES = {}

-- borderTab. The Ace page DISABLES the style, color and thickness while
-- the border is off (it does not hide them), so this card takes no gate:
-- enableBorder is an ordinary switch and the other three keep the Ace
-- disabled predicates verbatim. borderHeader "Border" is the card title.
function PAGES.border()
    local disabledUnlessBorder = function()
        return InCombatLockdown() or not Key("enableBorder")
    end

    -- Shape and weight, over the one `borderStyle` section key. This page
    -- has no Blizzard-Style option: the frame border is drawn by this addon
    -- either way, so the only shapes are Square and Rounded.
    local borderStyleField, borderWeightField =
        BuzzardFramesOptions:BorderStyleFields({
            id = "borderStyle",
            default = (function()
                local d = Defaults()
                return d and d.borderStyle
            end)(),
            desc = "Square draws a flat colored border at the chosen "
                .. "thickness. Rounded draws a rounded frame with the frame "
                .. "content masked to the corner radius.",
            options = {
                { value = "square",  text = "Square"  },
                { value = "rounded", text = "Rounded" },
            },
            disabled = disabledUnlessBorder,
            get = function() return Key("borderStyle") or "square" end,
            set = function(_, _, val)
                if InCombatLockdown() then return end
                local bf = BF()
                if not bf then return end
                bf:WriteSectionKey("borders", "borderStyle", val)
                if bf.IsRoundedBorderStyle(val) and Key("enableBorder") ~= false then
                    -- Blizzard / Glow Border aggro styles use separate
                    -- rectangular art that can't be the rounded ring --
                    -- coerce them to Border. Only when the rounded border
                    -- is actually DRAWN (border off => no ring).
                    local as = Key("aggroStyle")
                    if as == "blizzard" or as == "glowBorder" then
                        bf:WriteSectionKey("borders", "aggroStyle", "border")
                    end
                    -- Seed all border-highlight widths to the rounded
                    -- weight (Rounded=1, Thick=2); user can change after.
                    -- This runs for the Thin/Thick strip too, which is the
                    -- point of both controls sharing one writer.
                    local sz = (val == "rounded_thick") and 2 or 1
                    bf:WriteSectionKey("borders", "targetHighlightWidth", sz)
                    bf:WriteSectionKey("borders", "aggroBorderWidth", sz)
                    SetDebuffBorderWidth(sz)
                end
                BordersLayout()
                -- The border-style highlights switch ring<->edges in
                -- their Update, so refresh them on a style change.
                RefreshHighlights()
                PreviewLayout()
            end,
        })

    return {
        { title = "Border", preset = "form", fields = {
            { control = "switch", label = "Enable Border",
              bind = "enableBorder", disabled = "combat",
              onChange = function()
                  BordersLayout()
                  RefreshHighlights()
                  PreviewLayout()
              end },
            borderStyleField,
            borderWeightField,
            -- A stepper, not a slider: five whole numbers, and the reader
            -- wants "one more pixel" rather than a position on a track.
            { control = "stepper", label = "Border Thickness",
              bind = "borderThickness", min = 1, max = 5, step = 1,
              -- Rounded styles have fixed art thickness; this applies to
              -- the square border only -- the rounded frame's weight is
              -- the Thin/Thick strip under the style.
              hidden = function()
                  local bf = BF()
                  return bf and bf.IsRoundedBorderStyle(Key("borderStyle"))
                      and true or false
              end,
              disabled = disabledUnlessBorder,
              onChange = function()
                  BordersLayout()
                  PreviewLayout()
              end },
            { control = "color", label = "Border Color", alpha = true,
              -- The separate Border Opacity slider was folded into this
              -- picker's alpha (the container reads borderColor.a).
              id = "borderColor", default = ColorDefault("borderColor", true),
              disabled = disabledUnlessBorder,
              get = GetColor("borderColor", 0, 0, 0, true),
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf:WriteSectionKey("borders", "borderColor",
                      { r = v[1], g = v[2], b = v[3], a = v[4] })
                  BordersLayout()
                  PreviewLayout()
              end },
        }},
    }
end

-- targetHighlightTab. The Ace page HIDES the color, opacity and width
-- while the highlight is off (hiddenUnless), which is the gate collapse.
-- targetHighlightHeader is the card title; targetHighlightNote is the
-- bare note above it.
function PAGES.targetHighlight()
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Shows a colored border on the frame of your current "
                  .. "target." },
        }},
        { title = "Target Highlight", preset = "form",
          toggle = Gate("enableTargetHighlight", "Enable Target Highlight",
                        BordersTargetHL),
          fields = {
            { control = "color", label = "Target Highlight Color",
              id = "targetHighlightColor",
              default = ColorDefault("targetHighlightColor", false),
              disabled = "combat",
              get = GetColor("targetHighlightColor", 1, 1, 1, false),
              set = SetHighlightColor("targetHighlightColor", BordersTargetHL) },
            { control = "slider", label = "Target Highlight Opacity",
              bind = "targetHighlightOpacity",
              min = 0.1, max = 1.0, step = 0.05, disabled = "combat",
              onChange = BordersTargetHL },
            { control = "stepper", label = "Target Highlight Width",
              bind = "targetHighlightWidth",
              min = 1, max = 8, step = 1, disabled = "combat",
              -- LayoutFrame re-sizes the square edges; UpdateTarget
              -- re-applies the rounded ring at the new width (the ring is
              -- set in Update, not Layout).
              onChange = function()
                  BordersLayout()
                  BordersTargetHL()
              end },
        }},
    }
end

-- mouseoverTab. Same shape: mouseoverHeader is the card title,
-- mouseoverNote the bare note, hiddenUnless(enableMouseoverHighlight)
-- becomes the gate. The color and opacity have NO side effects -- the
-- runtime reads them live in OnEnter.
function PAGES.mouseover()
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Shows a color overlay on a frame when your mouse is "
                  .. "over it." },
        }},
        { title = "Mouseover Highlight", preset = "form",
          toggle = Gate("enableMouseoverHighlight", "Enable Mouseover Highlight",
              function(v)
                  -- Hide the overlay on all frames immediately when disabled.
                  if v then return end
                  local bf = BF()
                  if not bf then return end
                  for f in pairs(bf.activeFrames or {}) do
                      if f.mouseoverHighlight then
                          f.mouseoverHighlight:SetColorTexture(1, 1, 1, 0)
                      end
                  end
              end),
          fields = {
            { control = "color", label = "Mouseover Highlight Color",
              id = "mouseoverHighlightColor",
              default = ColorDefault("mouseoverHighlightColor", false),
              disabled = "combat",
              get = GetColor("mouseoverHighlightColor", 1, 1, 1, false),
              set = SetHighlightColor("mouseoverHighlightColor", nil) },
            { control = "slider", label = "Mouseover Highlight Opacity",
              bind = "mouseoverHighlightOpacity",
              min = 0.05, max = 0.5, step = 0.05, disabled = "combat" },
        }},
    }
end

-- aggroTab. A gated card and a gated card: the Ace page hides everything
-- but the enable toggle while aggro is off (hiddenUnless on every group),
-- which is exactly the gate collapse.
--
-- The Ace inline groups (aggroHighlightGroup, cornersOptionsGroup,
-- aggroColorsGroup, arrowOptionsGroup) fold into the FIRST card as runs of
-- fields, in the Ace order, each keeping its own style-dependent hidden
-- predicate -- see the notes file. The aggroPreviewHeader does not: its
-- switch governs the one control under it, which is what a gate IS, so it
-- is a card of its own headed by that switch. It carries the enable
-- toggle's own predicate as a group `hidden`, so the whole thing goes when
-- aggro is off, exactly as it did while it was a run of fields inside the
-- card above.
function PAGES.aggro()
    return {
        { title = "Aggro Highlight", preset = "form",
          toggle = (function()
              local g = Gate("aggroEnabled", "Enable Aggro Highlight", nil)
              local baseSet = g.set
              g.set = function(node, ctx, v)
                  if InCombatLockdown() then return end
                  baseSet(node, ctx, v)
                  -- Turning the highlight off also switches its test off:
                  -- a test left running would come back invisibly armed.
                  if not v then
                      local bf = BF()
                      if bf then bf.db.global.testAggroHighlight = false end
                  end
                  BordersThreat()
              end
              return g
          end)(),
          fields = {
            { control = "dropdown", label = "Highlight Style",
              bind = "aggroStyle", disabled = "combat",
              -- Blizzard Style / Glow Border draw rectangular art, so
              -- they're offered whenever the frame is NOT rounded -- that
              -- includes borders being switched OFF entirely (no border ==
              -- nothing rounded to conflict with). Same rule the Ace
              -- values/sorting functions applied.
              options = function()
                  local out = {}
                  if not IsRoundedActive() then
                      out[#out + 1] = { value = "blizzard",   text = "Blizzard Style" }
                      out[#out + 1] = { value = "glowBorder", text = "Glow Border" }
                  end
                  out[#out + 1] = { value = "border",      text = "Border" }
                  out[#out + 1] = { value = "corners",     text = "Corners" }
                  out[#out + 1] = { value = "arrowSingle", text = "Arrow (Single)" }
                  out[#out + 1] = { value = "arrow",       text = "Arrow (Double)" }
                  return out
              end,
              onChange = function()
                  -- Immediate in the Ace setter, so immediate here too.
                  local bf = BF()
                  if not bf then return end
                  for f in pairs(bf.activeFrames or {}) do
                      bf:LayoutFrame(f)
                      bf:UpdateThreat(f)
                  end
              end },

            -- The Ace aggroHighlightGroup ("Aggro Highlight", inline):
            -- hidden for the corners and arrow styles, whose options
            -- replace it below.
            { control = "slider", label = "Aggro Highlight Intensity",
              bind = "aggroScale", min = 0.1, max = 1.0, step = 0.1,
              hidden = function()
                  local s = Key("aggroStyle")
                  return s == "arrow" or s == "arrowSingle" or s == "corners"
              end,
              disabled = DisabledUnlessAggro,
              onChange = BordersThreat },
            { control = "stepper", label = "Aggro Border Width",
              bind = "aggroBorderWidth", min = 1, max = 5, step = 1,
              hidden = function()
                  local s = Key("aggroStyle")
                  -- Its own Ace predicate (blizzard/glowBorder use the
                  -- sized variant below) plus its group's (corners/arrow
                  -- styles hide the whole run).
                  return s ~= "border"
              end,
              disabled = DisabledUnlessAggro,
              onChange = function()
                  BordersLayout()
                  BordersThreat()
              end },
            -- The Ace aggroBorderWidthBlizzard widget: a second view over
            -- the SAME aggroBorderWidth key, clamped for the per-width art
            -- (Blizzard Style corner/edge art covers 1-5; Glow Border art
            -- starts at 2, so its setter clamps).
            { control = "stepper", label = "Aggro Border Size",
              -- The floor FOLLOWS THE STYLE. Blizzard Style is drawn from
              -- per-width corner and edge art covering 1-5; Glow Border's
              -- art starts at 2. The Ace panel had to write a literal 1
              -- here -- AceConfigDialog reads `min` raw at slider setup --
              -- so its setter clamped to 2 and the control advertised a
              -- minimum it would not accept. The panel resolves `min` on
              -- every render, so it can say the truth instead; the setter
              -- keeps its clamp, for a stored value that predates this.
              min = function()
                  return (Key("aggroStyle") == "blizzard") and 1 or 2
              end,
              max = 5, step = 1,
              id = "aggroBorderWidth",
              default = (function()
                  local d = Defaults()
                  return d and d.aggroBorderWidth
              end)(),
              hidden = function()
                  local s = Key("aggroStyle")
                  return s ~= "blizzard" and s ~= "glowBorder"
              end,
              disabled = DisabledUnlessAggro,
              get = function()
                  local lo = (Key("aggroStyle") == "blizzard") and 1 or 2
                  return math.max(lo, math.min(5, Key("aggroBorderWidth") or 2))
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  -- Glow Border art only exists for 2-5.
                  if Key("aggroStyle") ~= "blizzard" and val < 2 then
                      val = 2
                  end
                  bf:WriteSectionKey("borders", "aggroBorderWidth", val)
                  BordersLayout()
                  BordersThreat()
              end },

            -- The Ace cornersOptionsGroup ("Corners", inline). Shown for
            -- the corners style alone. No shipped default in the defaults
            -- table -- the getter's "lg" fallback is the Ace page's own.
            { control = "segmented", label = "Corner Scale",
              id = "aggroCornersScale",
              options = {
                  -- Smallest to largest, which is what a scale reads as.
                  -- The Ace dialog showed lg/md/sm because it sorted the
                  -- keys alphabetically, not because that was an order
                  -- anyone chose.
                  { value = "sm", text = "Small"  },
                  { value = "md", text = "Medium" },
                  { value = "lg", text = "Large"  },
              },
              hidden = function()
                  return Key("aggroStyle") ~= "corners"
              end,
              disabled = DisabledUnlessAggro,
              get = function() return Key("aggroCornersScale") or "lg" end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf:WriteSectionKey("borders", "aggroCornersScale", val)
                  BordersThreat()
                  PreviewAggro()
              end },

            -- The Ace aggroColorsGroup ("Threat Colors", inline). Shown for
            -- every style while the highlight is on.
            AggroColorField("aggroColor1", "No Aggro, High Threat",
                "Does not have aggro, but is high on threat.", 1, 0.94, 0, true),
            AggroColorField("aggroColor2", "Has Aggro, Low Threat",
                "Has aggro, but is low on threat.", 1, 0.5, 0),
            AggroColorField("aggroColor3", "Has Aggro, High Threat",
                "Has aggro, and is high on threat.", 1, 0.306, 0),

            -- The Ace arrowOptionsGroup ("Arrow", inline): direction, the
            -- position/offset triplet as one anchor pad, then size.
            -- Starts its own row, so the arrow settings cannot flow up
            -- onto the threat colors' line above them.
            { control = "segmented", label = "Arrow Direction", newRow = true,
              bind = "aggroArrowDirection",
              options = {
                  -- Vertical pair then horizontal pair, rather than the
                  -- alphabetical order the Ace dialog fell into by sorting
                  -- its keys.
                  { value = "down",  text = "Down"  },
                  { value = "up",    text = "Up"    },
                  { value = "left",  text = "Left"  },
                  { value = "right", text = "Right" },
              },
              hidden = function()
                  local s = Key("aggroStyle")
                  return s ~= "arrow" and s ~= "arrowSingle"
              end,
              disabled = DisabledUnlessAggro,
              onChange = function()
                  BordersLayout()
                  BordersThreat()
                  PreviewAggro()
              end },
            -- aggroArrowPosition + aggroArrowOffsetX + aggroArrowOffsetY:
            -- three settings that only mean anything together, as one
            -- widget. The Ace point setter also refreshed threat and the
            -- offset setters did not; the composite fires one effect for
            -- all three binds, so it runs the union.
            { control = "anchor", label = "Arrow Position",
              binds = { point = "aggroArrowPosition",
                        x     = "aggroArrowOffsetX",
                        y     = "aggroArrowOffsetY" },
              min = -20, max = 20,
              hidden = function()
                  local s = Key("aggroStyle")
                  return s ~= "arrow" and s ~= "arrowSingle"
              end,
              disabled = DisabledUnlessAggro,
              onChange = function()
                  BordersLayout()
                  BordersThreat()
                  PreviewAggro()
              end },
            { control = "slider", label = "Arrow Size",
              bind = "aggroArrowSize", min = 8, max = 32, step = 1,
              hidden = function()
                  local s = Key("aggroStyle")
                  return s ~= "arrow" and s ~= "arrowSingle"
              end,
              disabled = DisabledUnlessAggro,
              onChange = function()
                  BordersLayout()
                  PreviewAggro()
              end },

        }},

        -- The Ace aggroPreviewHeader ("Preview") and its two test controls,
        -- as a GATED card: the switch is the card's header and the level it
        -- governs is the only thing inside, so the card collapses to the
        -- switch when the test is off. The flags live on BF.db.global
        -- (reset on every reload) -- the convention every test flag follows
        -- -- so they are the two things on this page that do not route
        -- through the borders section, and the gate's own combat guard is
        -- its setter's, since a gate takes no `disabled`.
        { title = "Test Aggro Highlight", preset = "form",
          hidden = function() return not Key("aggroEnabled") end,
          toggle = {
            id = "testAggroHighlight", default = false,
            tooltip = "Test Aggro Highlight",
            desc = "Display the aggro highlight on all frames for preview "
                .. "purposes.",
            get = function()
                local bf = BF()
                return bf and bf.db.global.testAggroHighlight
            end,
            set = function(_, _, v)
                if InCombatLockdown() then return end
                local bf = BF()
                if not bf then return end
                bf.db.global.testAggroHighlight = v
                PreviewAggro()
            end,
          },
          fields = {
            { control = "dropdown", label = "Test Aggro Level",
              id = "testAggroLevel", default = 3,
              desc = "Which threat level to simulate on the preview frames.",
              options = {
                  { value = 1, text = "No Aggro, High Threat" },
                  { value = 2, text = "Has Aggro, Low Threat" },
                  { value = 3, text = "Has Aggro, High Threat" },
              },
              -- No `disabled` on the test flag any more: the card is
              -- collapsed while the switch is off, so there is nothing to
              -- disable. The combat guard stays -- that one is not about
              -- the switch.
              disabled = "combat",
              get = function()
                  local bf = BF()
                  return (bf and bf.db.global.testAggroLevel) or 3
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testAggroLevel = v
                  PreviewAggro()
              end },
        }},
    }
end

-- debuffTab: the signpost. Stores nothing; the settings it once held live
-- in Debuffs > Dispellable Debuffs (auras.dispelIndicator). The button is
-- the Ace goToDispelIndicator execute, retargeted at the panel's own
-- route tree; the note above it is goToDispelIndicatorNote.
function PAGES.debuff()
    -- Which section the signpost points INTO. Read at BUILD time, which is
    -- when the scope is bound: the same page is built once for Raid /
    -- Party and once for each Custom Frame Groups render, and a button
    -- that sent a reader from the Custom Frame Groups Borders subtab to
    -- the RAID Dispel Indicators tab would have moved them to a different
    -- set of frames without saying so.
    local bf   = BF()
    local root = (bf and bf.BFOScopeFlat) and "customFrames"
                 or "raidPartyFrames"
    return {
        { preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Debuff Highlight settings have moved to Debuffs -> "
                  .. "Dispellable Debuffs subtab." },
        }},
        { preset = "bare", fields = {
            -- `text` is the button's caption; no `label`, which would
            -- render the same words a second time above it.
            { control = "button", text = "Dispellable Debuffs settings",
              desc = "Open the Debuffs -> Dispellable Debuffs tab to "
                  .. "configure the dispel indicator and debuff "
                  .. "highlight/overlay shown on unit frames.",
              onClick = function(_, ctx)
                  -- DEFERRED for the same reason the Ace execute deferred
                  -- its SelectGroup: navigating re-renders synchronously
                  -- and would release the clicked button mid-click.
                  local app = ctx.app
                  C_Timer.After(0, function()
                      -- The Ace target is raidPartyFrames > aurasDebuffs >
                      -- tabDispel. Until the Debuffs migration lands its
                      -- subtab routes, the deep segment does not resolve
                      -- and Navigate refuses the whole path -- so fall back
                      -- to the section, which descends to its first leaf.
                      if not app:Navigate(root, "aurasDebuffs",
                              "tabDispel") then
                          app:Navigate(root, "aurasDebuffs")
                      end
                  end)
              end },
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:BordersPage(subtabId, label)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end

    local groups = {}
    -- The debuff subtab stores nothing in the borders section, so it takes
    -- no scope strip: there is no borders_debuff toggle and nothing a copy
    -- could move.
    if TogKey(subtabId) then
        groups[#groups + 1] = ScopeStrip(subtabId, label or subtabId)
    end
    for _, g in ipairs(build()) do groups[#groups + 1] = g end

    return {
        -- The routed storage, wearing the shape of a table. Every `bind` on
        -- this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- what makes the
        -- right-click "Reset to default" work on every bound field without
        -- any of them declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end
