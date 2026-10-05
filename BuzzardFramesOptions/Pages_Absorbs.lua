-- ============================================================
-- BuzzardFramesOptions: Pages_Absorbs.lua
-- The Raid/Party Frames > Absorbs & Heal Prediction section, in
-- BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Absorbs.lua: the
-- same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by four BuzzardPanel pages -- one per
-- subtab, each a route of its own under `raidPartyFrames/absorbs`, drawn
-- as a strip by the `tabs` navigator that node declares (the Pages_Icons
-- pattern).
--
-- Storage: rpDB.profile.absorbs.* (the global pseudo-layout), or
-- flat.absorbs.* for whichever keys belong to a subtab whose own
-- absorbs_<subtab> toggle is on. That routing is PER KEY and it is not
-- this file's business: reads go through
-- BF:GetSectionProfile("absorbs", ...) -- which answers with the merged
-- view -- and writes through BF:WriteSectionKey, exactly as the Ace
-- page's getIP/writeIP do. Nothing here touches a db table directly,
-- which is what keeps the two panels in step.
--
-- Scalar fields are BOUND into the write-through ROOT below, which is
-- what makes right-click Undo and Reset work without each field declaring
-- anything. The color keys are stored as KEYED tables ({r=,g=,b=,a=})
-- while the panel's color control speaks arrays, so every color keeps a
-- get/set adapter with `id` and `default` -- writes go through
-- WriteSectionKey with a fresh keyed table, the very shape the Ace
-- setters wrote.
--
-- Test flags (testAbsorb, testAbsorbSize, testHealPrediction,
-- testHealAbsorb, testReducedMaxHealth) are GLOBAL debug flags on
-- BF.db.global -- not part of the per-Layout absorbs profile, reset to
-- false on every reload by Core_DB -- so they are the fields on this page
-- that do not route through the section at all.
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
    return bf:GetSectionProfile("absorbs", bf:GetModifyingProfile())
end

-- ── The write-through root ─────────────────────────────────────
--
-- Reads fall through to the merged view, writes go to WriteSectionKey,
-- which routes per key by that key's subtab and its per-Layout toggle --
-- the same path the Ace page's writeIP takes (bare WriteSectionKey, no
-- aura-cache invalidation: absorbs feeds no aura size cache). No
-- SubTable wrapper as in Pages_Icons: no BOUND key on this page is
-- table-valued -- the colors go through get/set adapters that never
-- read through ROOT.
local ROOT = setmetatable({}, {
    __index = function(_, k)
        local ip = GetIP()
        return ip and ip[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if bf then bf:WriteSectionKey("absorbs", k, v) end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library
-- resolves a bind path straight into it.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.absorbs
end

-- ── Shared option lists ────────────────────────────────────────

-- The statusbar textures LibSharedMedia knows, alphabetical -- the same
-- list the Ace page's LSM30_Statusbar widgets offered, previews and all:
-- each entry carries its `texture`, which the dropdown draws behind the
-- name in the menu and on the control once it is picked.
local function StatusbarOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out, names = {}, {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do
            names[#names + 1] = name
        end
    end
    table.sort(names)
    -- Tables rather than bare strings, so each one can carry its own
    -- `texture`: the dropdown draws the bar behind the name, as the Ace
    -- statusbar picker did.
    for i = 1, #names do
        out[i] = { value = names[i], text = names[i],
                   texture = LSM:Fetch("statusbar", names[i]) }
    end
    return out
end

-- ── Side effects ───────────────────────────────────────────────
--
-- One function per chain the Ace setters ran, in the order they ran it:
-- the BF-side debounce keeps its Ace key ("absorbs", "healAbsorbs",
-- "healPred", "reducedMax"), so both panels share one trailing timer
-- while both exist, and the preview refresh follows it exactly as it
-- does in the Ace setters.

local function Absorbs()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("absorbs", function() bf:RefreshAllAbsorbs() end)
    if bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
end

-- The overshield style and the two custom-texture routes re-cut cached
-- textures, so the cache is stale-marked BEFORE the refresh reads
-- through it again -- the same order the Ace setters keep.
local function AbsorbsTexture()
    local bf = BF()
    if not bf then return end
    if bf.InvalidateAbsorbTextureCaches then bf:InvalidateAbsorbTextureCaches() end
    Absorbs()
end

local function HealAbsorbs()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("healAbsorbs", function() bf:RefreshAllHealAbsorbs() end)
    if bf.RefreshPreviewHealAbsorb then bf:RefreshPreviewHealAbsorb() end
end

local function HealPrediction()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("healPred", function() bf:RefreshAllHealPrediction() end)
    if bf.RefreshPreviewHealPrediction then bf:RefreshPreviewHealPrediction() end
end

local function ReducedMax()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("reducedMax", function() bf:RefreshAllReducedMaxHealth() end)
    if bf.RefreshPreviewReducedMaxHealth then bf:RefreshPreviewReducedMaxHealth() end
end

-- Re-layout on all active frames (positional/geometry changes) and
-- refresh the options-panel preview -- the Ace page's layoutFrames.
local function LayoutFrames()
    local bf = BF()
    if not bf then return end
    for frame in pairs(bf.activeFrames or {}) do
        bf:LayoutFrame(frame)
    end
    if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

-- The reduced-max % text look: re-layout, then re-run every indicator.
local function ReducedMaxTextLook()
    local bf = BF()
    if not bf then return end
    LayoutFrames()
    for frame in pairs(bf.activeFrames or {}) do
        frame:UpdateIndicators()
    end
end

-- Flipping WHAT the % text is (shown at all, appended, appended where)
-- also re-evaluates the conditional reducedmaxhealth->nameText bind:
-- without the rebind, enabling the name-append leaves the suffix stale
-- on later UNIT_MAX_HEALTH_MODIFIERS_CHANGED events.
local function ReducedMaxTextBind()
    local bf = BF()
    if not bf then return end
    if bf.RebindAbsorbStatuses then bf:RebindAbsorbStatuses() end
    ReducedMaxTextLook()
end

-- ── Visibility and enabled predicates ──────────────────────────
--
-- Copies of the Ace page's hidden/disabled bodies, one per shape, so a
-- field can name the one it had rather than restating it.

-- The Ace absorbsOff(): the missing-health master is off only when the
-- stored value is EXPLICITLY false -- an unseeded profile reads as on.
local function AbsorbsOff()
    local ip = GetIP()
    return ip and ip.showAbsorbsMissingHealth == false
end

-- The Ace color/texture GROUP predicate on the absorbs tab: hidden with
-- no profile at all, hidden when the master is explicitly off.
local function MissingOff()
    local ip = GetIP()
    if not ip then return true end
    return ip.showAbsorbsMissingHealth == false
end

-- v94: overshield is independent of the missing-health master, so its
-- options show regardless; the anchor/overlay bar options still hide in
-- Glow style (no bar there).
local function GlowStyle()
    local ip = GetIP()
    return ip and ip.overshieldStyle == "Glow"
end

local function OvershieldDisabled()
    local bf = BF()
    return InCombatLockdown()
        or not (bf and bf:IsOvershieldActive(GetIP()))
end

-- hidden = "this key is not truthy" -- the commonest Ace shape here.
local function NotShown(key)
    return function()
        local ip = GetIP()
        return not (ip and ip[key])
    end
end

-- disabled = "in combat, or this key is not truthy".
local function CombatOrNot(key)
    return function()
        local ip = GetIP()
        return InCombatLockdown() or not (ip and ip[key])
    end
end

-- Only the two "(Blizzard Style)" heal absorb styles draw the plus
-- symbols, so their color pair exists only there.
local function HealAbsorbBlizzStyle()
    local ip = GetIP()
    return ip and (ip.healAbsorbStyle == "OverlayBlizzard"
        or ip.healAbsorbStyle == "BarBlizzard")
end

-- ── Color adapters ────────────────────────────────────────────
--
-- Storage is keyed ({r=,g=,b=,a=}); the panel's color control speaks
-- arrays. Every color keeps its `id` (the undo key) and a `default` in
-- the control's own shape, converted from Buzzard Frames' defaults table
-- at page build -- never restated as a literal here.

local function ColorDefault(key, hasAlpha)
    local d = Defaults()
    local c = d and d[key]
    if type(c) ~= "table" then return nil end
    if hasAlpha then return { c.r, c.g, c.b, c.a } end
    return { c.r, c.g, c.b }
end

local function GetColor(key, hasAlpha)
    return function()
        local ip = GetIP()
        local c  = ip and ip[key]
        if type(c) ~= "table" then return nil end
        if hasAlpha then return { c.r, c.g, c.b, c.a } end
        return { c.r, c.g, c.b }
    end
end

-- Writes a FRESH keyed table through the routed path, the very call the
-- Ace setters made (WriteSectionKey("absorbs", key, {r=,g=,b=,a=})),
-- then runs the effect inline -- the effect's own DebounceOption is what
-- coalesces the picker's per-tick calls, on both panels alike.
local function SetColor(key, hasAlpha, effect)
    return function(_, _, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if not bf then return end
        if hasAlpha then
            bf:WriteSectionKey("absorbs", key, { r = v[1], g = v[2], b = v[3], a = v[4] })
        else
            bf:WriteSectionKey("absorbs", key, { r = v[1], g = v[2], b = v[3] })
        end
        effect()
    end
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Absorbs carries FOUR per-Layout toggles, one per subtab
-- (absorbs_absorbs through absorbs_reducedMax), so the strip belongs to
-- the subtab rather than the section -- and Copy to moves that subtab's
-- keys and no others. Copied from Pages_Icons with the section swapped.

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

-- _modifyingFlat can be unset (a fresh session) or name a Layout that
-- has since been deleted, so it falls back the way the Ace dropdown does.
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
-- Tables are deep-copied, or the two Layouts end up sharing one table
-- and silently editing each other afterwards. Falls back to the global
-- as the source when the toggle is on but this flat was never seeded.
local function CopySubtabTo(subtabId, targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    local keys = bf.SECTION_SUBTAB_KEYS and bf.SECTION_SUBTAB_KEYS.absorbs
    keys = keys and keys[subtabId]
    if not keys then return end

    local srcSection = rawget(src, "absorbs")
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.absorbs end
    if type(srcSection) ~= "table" then return end

    if type(rawget(dst, "absorbs")) ~= "table" then
        dst.absorbs = {}
        -- A flat's section table falls THROUGH to the global for anything
        -- it does not hold. A table created without that wiring answers
        -- nil for every key this copy does not carry.
        if bf.WireSectionFallback then bf:WireSectionFallback(dst, "absorbs") end
    end
    local dstSection = rawget(dst, "absorbs")

    for _, k in ipairs(keys) do
        local v = srcSection[k]
        if v ~= nil then
            dstSection[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("absorbs") end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function TogKey(subtabId)
    local bf = BF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and bf.SECTION_SUBTAB_TOGGLE.absorbs
    return m and m[subtabId]
end

local function NotPerLayout(subtabId)
    return function()
        local bf = BF()
        return not (bf and bf:IsPerLayoutSectionSubtab("absorbs", subtabId))
    end
end

-- A flat bar rather than a card: this row is ABOUT the settings below
-- it, not one of them. `strip` is the library's preset for exactly that.
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
          id = TogKey(subtabId) or ("absorbs_" .. subtabId), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give " .. label .. " its own "
              .. "settings per Layout -- the other Absorbs & Heal "
              .. "Prediction subtabs keep their own toggles.",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSectionSubtab("absorbs", subtabId)
          end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf = BF()
              if not bf then return end
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight
              -- pass-through while that flag is off.
              bf:_TimeSectionPerLayout(TogKey(subtabId), v)
              -- Every field below now reads a different place, and the
              -- two controls beside this one appear or go.
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
              .. "Absorbs & Heal Prediction is left alone.",
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
          -- A copy is an ACTION, not a setting: the dropdown never shows
          -- a current value, it just offers destinations.
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

-- ── The four pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages: the ids ARE the subtab ids in
-- BF.SECTION_SUBTABS.absorbs, so the per-Layout toggles line up by
-- construction. The order is the Ace tabs' own (absorbTab 1,
-- healAbsorbTab 2, healPredictionTab 3, reducedMaxHealth 4).
BuzzardFramesOptions.ABSORBS_SUBTABS = {
    { id = "absorbs",        title = "Absorbs" },
    { id = "healAbsorbs",    title = "Heal Absorbs" },
    { id = "healPrediction", title = "Heal Prediction" },
    { id = "reducedMax",     title = "Temp Reduced Max Health" },
}

local PAGES = {}

-- absorbTab. No header gate anywhere on this subtab: the Ace page HIDES
-- the missing-health cards and DISABLES the overshield controls through
-- per-widget predicates, and v94 made overshield independent of the
-- missing-health master -- so every predicate rides its own field,
-- verbatim, and the master is an ordinary switch. The Ace inline groups
-- (absorbColorGroup, overshieldColorGroup, absorbTextureGroup,
-- overshieldTextureGroup) become cards under their own names, in the Ace
-- order; the bare headers become card titles: absorbMissingHeader,
-- overshieldHeader, testAbsorbHeader -- and absorbColorsHeader /
-- absorbTexturesHeader (both hidden=absorbsOff in Ace) are folded into
-- the inline groups' own card titles beneath them, since a card title
-- and a band saying almost the same words would be two headings for one
-- thing.
function PAGES.absorbs()
    return {
        -- absorbMissingHeader.
        { title = "Absorbs (Missing Health)", preset = "form", fields = {
            -- The master for the missing-health bar. An unseeded profile
            -- reads as ON (`~= false`), so this cannot bind: nil must
            -- show as checked.
            { control = "switch", label = "Show Absorbs (Missing Health)",
              desc = "Show damage absorb shields in the missing health gap",
              id = "showAbsorbsMissingHealth",
              -- Not in the defaults table -- the shipped state is the nil
              -- that reads as true. The one restated default on this
              -- page; see the notes file.
              default = true,
              disabled = "combat",
              get = function()
                  local ip = GetIP()
                  return ip and ip.showAbsorbsMissingHealth ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  ROOT.showAbsorbsMissingHealth = v
                  Absorbs()
              end },
        }},
        -- overshieldHeader.
        { title = "Overshield (Absorbs Over Max Health)", preset = "form",
          fields = {
            { control = "switch", label = "Show Overshield",
              bind = "showOvershield", disabled = "combat",
              desc = "Show an overshield bar. With the missing-health "
                  .. "absorb bar ON it shows only the excess (absorbs "
                  .. "beyond the missing-health gap); with it OFF, the "
                  .. "Left anchor shows the total absorb.",
              onChange = Absorbs },
            { control = "dropdown", label = "Overshield Style",
              bind = "overshieldStyle",
              desc = "How to display absorbs exceeding max health",
              options = {
                  { value = "Glow",    text = "Glow"    },
                  { value = "Overlay", text = "Overlay" },
              },
              disabled = OvershieldDisabled,
              onChange = AbsorbsTexture },
            { control = "dropdown", label = "Overshield Anchor",
              bind = "overshieldAnchor",
              desc = "Position where the overshield anchors on the health bar",
              options = {
                  { value = "LEFT",  text = "Left" },
                  { value = "RIGHT", text = "Right (Blizzard Style)" },
              },
              hidden = GlowStyle,
              disabled = OvershieldDisabled,
              onChange = Absorbs },
        }},
        -- absorbColorsHeader + absorbColorGroup.
        { title = "Missing Health Absorb Colors", preset = "form", fields = {
            { control = "switch", label = "Use Custom Absorb Color",
              bind = "useCustomAbsorbColor",
              hidden = MissingOff, disabled = "combat",
              onChange = Absorbs },
            { control = "color", label = "Absorb Overlay Color", alpha = true,
              desc = "Color and opacity of the missing health absorb "
                  .. "overlay texture",
              id = "absorbOverlayColor",
              default = ColorDefault("absorbOverlayColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  if ip.showAbsorbsMissingHealth == false then return true end
                  return not ip.useCustomAbsorbColor or ip.useCustomAbsorbBarTexture
              end,
              disabled = "combat",
              get = GetColor("absorbOverlayColor", true),
              set = SetColor("absorbOverlayColor", true, Absorbs) },
            -- Absorb seam shadow (the default-UI look). Deliberately NOT
            -- gated on useCustomAbsorbColor or useCustomAbsorbBarTexture:
            -- the shadow should be usable with any bar texture, which is
            -- why it sits outside the custom-color pair.
            { control = "switch", label = "Show Absorb Shadow",
              desc = "Show a shadow where the absorb shield meets the "
                  .. "health bar (Blizzard's default look). Works with "
                  .. "custom absorb textures too.",
              id = "showAbsorbShadow",
              default = (function()
                  local d = Defaults()
                  return d and d.showAbsorbShadow
              end)(),
              hidden = MissingOff, disabled = "combat",
              -- `~= false` like the master: an unseeded value reads ON.
              get = function()
                  local ip = GetIP()
                  return ip and ip.showAbsorbShadow ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  ROOT.showAbsorbShadow = v
                  Absorbs()
              end },
            { control = "color", label = "Absorb Shadow Color", alpha = true,
              desc = "Color and opacity of the absorb seam shadow",
              id = "absorbShadowColor",
              default = ColorDefault("absorbShadowColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  if ip.showAbsorbShadow == false then return true end
                  return ip.showAbsorbsMissingHealth == false
              end,
              disabled = "combat",
              get = GetColor("absorbShadowColor", true),
              set = SetColor("absorbShadowColor", true, Absorbs) },
            -- Last in its card in the Ace order too (order 27, after the
            -- shadow pair).
            { control = "color", label = "Absorb Color", alpha = true,
              desc = "Color and opacity of the missing health absorb "
                  .. "base texture",
              id = "absorbBaseColor",
              default = ColorDefault("absorbBaseColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  if not ip.useCustomAbsorbColor then return true end
                  return ip.showAbsorbsMissingHealth == false
              end,
              disabled = "combat",
              get = GetColor("absorbBaseColor", true),
              set = SetColor("absorbBaseColor", true, Absorbs) },
        }},
        -- overshieldColorGroup.
        { title = "Overshield Absorb Colors", preset = "form", fields = {
            { control = "switch", label = "Use Custom Overshield Color",
              bind = "useCustomOvershieldColor",
              hidden = GlowStyle,
              disabled = OvershieldDisabled,
              onChange = Absorbs },
            { control = "color", label = "Overshield Color", alpha = true,
              desc = "Color and opacity of the overshield absorb base texture",
              id = "overshieldBaseColor",
              default = ColorDefault("overshieldBaseColor", true),
              hidden = function()
                  local ip = GetIP()
                  if ip and ip.overshieldStyle == "Glow" then return true end
                  return not (ip and ip.useCustomOvershieldColor)
              end,
              disabled = "combat",
              get = GetColor("overshieldBaseColor", true),
              set = SetColor("overshieldBaseColor", true, Absorbs) },
            { control = "color", label = "Overshield Overlay Color", alpha = true,
              desc = "Color and opacity of the overshield absorb overlay texture",
              id = "overshieldOverlayColor",
              default = ColorDefault("overshieldOverlayColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  if ip.overshieldStyle == "Glow" then return true end
                  return not ip.useCustomOvershieldColor
                      or ip.useCustomOvershieldBarTexture
              end,
              disabled = "combat",
              get = GetColor("overshieldOverlayColor", true),
              set = SetColor("overshieldOverlayColor", true, Absorbs) },
        }},
        -- absorbTexturesHeader + absorbTextureGroup.
        { title = "Missing Health Absorb Textures", preset = "form", fields = {
            { control = "switch", label = "Use Custom Absorb Texture",
              bind = "useCustomAbsorbBarTexture",
              hidden = MissingOff, disabled = "combat",
              onChange = AbsorbsTexture },
            { control = "dropdown", label = "Absorb Texture",
              bind = "absorbBarTexture",
              desc = "Statusbar fill texture for the missing health absorb bar.",
              options = StatusbarOptions,
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  if ip.showAbsorbsMissingHealth == false then return true end
                  return not ip.useCustomAbsorbBarTexture
              end,
              disabled = "combat",
              onChange = AbsorbsTexture },
        }},
        -- overshieldTextureGroup.
        { title = "Overshield Textures", preset = "form", fields = {
            { control = "switch", label = "Use Custom Overshield Texture",
              bind = "useCustomOvershieldBarTexture",
              hidden = GlowStyle,
              disabled = OvershieldDisabled,
              onChange = AbsorbsTexture },
            { control = "dropdown", label = "Overshield Texture",
              bind = "overshieldBarTexture",
              desc = "Statusbar fill texture for the overshield absorb bar.",
              options = StatusbarOptions,
              hidden = function()
                  local ip = GetIP()
                  if ip and ip.overshieldStyle == "Glow" then return true end
                  return not (ip and ip.useCustomOvershieldBarTexture)
              end,
              disabled = OvershieldDisabled,
              onChange = AbsorbsTexture },
        }},
        -- testAbsorbHeader. Global debug flags, cleared on every reload,
        -- hidden while the missing-health master is off -- as in the Ace
        -- page.
        { title = "Test", preset = "form", fields = {
            { control = "switch", label = "Test Absorb",
              desc = "Simulate a damage absorb on preview frames for "
                  .. "testing. Disable when done.",
              id = "testAbsorb", default = false,
              hidden = AbsorbsOff, disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testAbsorb
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testAbsorb = v
                  if bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
              end },
            { control = "dropdown", label = "Absorb Size",
              id = "testAbsorbSize", default = "medium",
              options = {
                  { value = "small",   text = "Small Absorb (10%)"    },
                  { value = "medium",  text = "Medium Absorb (40%)"   },
                  { value = "large",   text = "Large Absorb (80%)"    },
                  { value = "massive", text = "Massive Absorb (120%)" },
              },
              hidden = function()
                  local bf = BF()
                  return AbsorbsOff() or not (bf and bf.db.global.testAbsorb)
              end,
              disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and (bf.db.global.testAbsorbSize or "medium")
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testAbsorbSize = v
                  if bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
              end },
        }},
    }
end

-- healAbsorbTab. The show toggle DISABLES the style and color rather
-- than hiding them, and the plus-symbol pair hides on STYLE alone (it
-- stays visible with the show toggle off) -- so no header gate here
-- either; every predicate is the Ace one on its own field.
function PAGES.healAbsorbs()
    return {
        -- healAbsorbHeader.
        { title = "Heal Absorb", preset = "form", fields = {
            { control = "switch", label = "Show Heal Absorb",
              bind = "showHealAbsorb", disabled = "combat",
              desc = "Show heal absorption effects on frames",
              onChange = function()
                  local bf = BF()
                  if not bf then return end
                  -- The write has already happened; this reads back what
                  -- it stored. Turning the effect off also turns its test
                  -- off, so a test left on cannot linger invisibly.
                  if not ROOT.showHealAbsorb and bf.db.global.testHealAbsorb then
                      bf.db.global.testHealAbsorb = false
                  end
                  HealAbsorbs()
              end },
            { control = "dropdown", label = "Heal Absorb Style",
              bind = "healAbsorbStyle",
              desc = "How to display heal absorb effects.\n\n"
                  .. "|cffffffffOverlay|r: Base fill and right shadow. Use "
                  .. "the Color option to tint the base fill.\n\n"
                  .. "|cffffffffOverlay (Blizzard Style)|r: Base fill, plus "
                  .. "symbols overlay, and right shadow. Use the Color "
                  .. "option to tint the base fill.\n\n"
                  .. "|cffffffffBar|r: A thin bar anchored to the top of the "
                  .. "health bar, fills left-to-right proportional to heal "
                  .. "absorb vs max HP.\n\n"
                  .. "|cffffffffBar (Blizzard Style)|r: Same sizing and "
                  .. "position as Bar, but uses Blizzard's absorb textures "
                  .. "with plus symbols overlay.",
              -- The order the Ace dialog showed: no `sorting`, so its
              -- keys alphabetically.
              options = {
                  { value = "Bar",             text = "Bar" },
                  { value = "BarBlizzard",     text = "Bar (Blizzard Style)" },
                  { value = "Overlay",         text = "Overlay" },
                  { value = "OverlayBlizzard", text = "Overlay (Blizzard Style)" },
              },
              disabled = CombatOrNot("showHealAbsorb"),
              onChange = HealAbsorbs },
            { control = "color", label = "Color", alpha = true,
              desc = "Color and opacity of the heal absorb effect.\n\n"
                  .. "|cffffffffOverlay / Overlay (Blizzard Style)|r: Tints "
                  .. "the base fill texture.\n"
                  .. "|cffffffffBar|r: Sets the bar color.",
              id = "healAbsorbColor",
              default = ColorDefault("healAbsorbColor", true),
              disabled = CombatOrNot("showHealAbsorb"),
              get = GetColor("healAbsorbColor", true),
              set = SetColor("healAbsorbColor", true, HealAbsorbs) },
            -- (The Ace healAbsorbSymbolSpacer -- a full-width empty
            -- description forcing a row break before this toggle -- is
            -- dropped: the flow layout makes it unnecessary.)
            { control = "switch", label = "Use Custom + Symbol Color",
              bind = "useCustomHealAbsorbSymbolColor",
              desc = "Color the plus symbols drawn on the heal absorb "
                  .. "texture. Off uses the default white. Only the two "
                  .. "|cffffffff(Blizzard Style)|r heal absorb styles draw "
                  .. "them.",
              hidden = function() return not HealAbsorbBlizzStyle() end,
              disabled = "combat",
              onChange = HealAbsorbs },
            { control = "color", label = "+ Symbol Color", alpha = true,
              desc = "Color and opacity of the plus symbols on the heal "
                  .. "absorb texture.",
              id = "healAbsorbSymbolColor",
              default = ColorDefault("healAbsorbSymbolColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not (ip and (ip.healAbsorbStyle == "OverlayBlizzard"
                      or ip.healAbsorbStyle == "BarBlizzard")) then return true end
                  return not ip.useCustomHealAbsorbSymbolColor
              end,
              disabled = "combat",
              get = GetColor("healAbsorbSymbolColor", true),
              set = SetColor("healAbsorbSymbolColor", true, HealAbsorbs) },
            { control = "slider", label = "Bar Height",
              bind = "healAbsorbBarHeight",
              desc = "Height of the heal absorb bar in pixels",
              min = 1, max = 100, step = 1,
              hidden = function()
                  local ip = GetIP()
                  return not (ip and (ip.healAbsorbStyle == "Bar"
                      or ip.healAbsorbStyle == "BarBlizzard"))
              end,
              disabled = CombatOrNot("showHealAbsorb"),
              onChange = HealAbsorbs },
        }},
        -- healAbsorbTextureGroup. v93: custom fill texture for the heal
        -- absorb visual. Applies to all four healAbsorbStyle values (the
        -- base fill only -- the Blizzard variants keep their plus-symbol
        -- overlay). The Ace inline group hid whole on showHealAbsorb;
        -- its predicate rides both fields here.
        { title = "Heal Absorb Texture", preset = "form", fields = {
            { control = "switch", label = "Use Custom Heal Absorb Texture",
              bind = "useCustomHealAbsorbTexture",
              hidden = NotShown("showHealAbsorb"), disabled = "combat",
              onChange = HealAbsorbs },
            { control = "dropdown", label = "Heal Absorb Texture",
              bind = "healAbsorbTexture",
              desc = "Statusbar fill texture for the heal absorb visual.",
              options = StatusbarOptions,
              hidden = function()
                  local ip = GetIP()
                  if not (ip and ip.showHealAbsorb) then return true end
                  return not ip.useCustomHealAbsorbTexture
              end,
              disabled = "combat",
              onChange = HealAbsorbs },
        }},
        -- testHealAbsorbHeader.
        { title = "Test", preset = "form", fields = {
            { control = "switch", label = "Test Heal Absorb (50%)",
              desc = "Simulate a 50% heal absorb on preview frames for "
                  .. "testing. Disable when done.",
              id = "testHealAbsorb", default = false,
              hidden = NotShown("showHealAbsorb"), disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testHealAbsorb
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testHealAbsorb = v
                  if bf.RefreshPreviewHealAbsorb then bf:RefreshPreviewHealAbsorb() end
              end },
        }},
    }
end

-- healPredictionTab. The show toggle DISABLES the anchor (visible,
-- grayed) but HIDES the color, texture pair and test -- kept exactly,
-- which is why this card is not header-gated either.
function PAGES.healPrediction()
    return {
        -- healPredictionHeader.
        { title = "Heal Prediction", preset = "form", fields = {
            { control = "switch", label = "Show Heal Prediction",
              bind = "showHealPrediction", disabled = "combat",
              desc = "Show incoming heal prediction on health bars",
              onChange = function()
                  local bf = BF()
                  if not bf then return end
                  -- When disabling, clear the matching test flag so a
                  -- previously-enabled test doesn't linger invisibly.
                  if not ROOT.showHealPrediction and bf.db.global.testHealPrediction then
                      bf.db.global.testHealPrediction = false
                  end
                  HealPrediction()
              end },
            { control = "dropdown", label = "Heal Prediction Anchor",
              bind = "healPredictionAnchor",
              desc = "Position where heal prediction bar anchors.\n\n"
                  .. "|cffffffffLeft|r: Overlays the health bar from the "
                  .. "left edge, showing predicted health as a fill. "
                  .. "Incoming heals are clamped to max health.\n\n"
                  .. "|cffffffffRight (Blizzard Style)|r: Extends from the "
                  .. "right edge of the current health fill into the "
                  .. "missing health area.",
              options = {
                  { value = "LEFT",  text = "Left" },
                  { value = "RIGHT", text = "Right (Blizzard Style)" },
              },
              disabled = CombatOrNot("showHealPrediction"),
              -- RefreshAllHealPrediction clears each frame's
              -- _healPredAnchor cache before the per-frame update so the
              -- bar is re-parented and re-anchored.
              onChange = HealPrediction },
            { control = "color", label = "Heal Prediction Color", alpha = true,
              desc = "Color and opacity of the heal prediction bar",
              id = "healPredictionColor",
              default = ColorDefault("healPredictionColor", true),
              hidden = NotShown("showHealPrediction"),
              disabled = "combat",
              get = GetColor("healPredictionColor", true),
              set = SetColor("healPredictionColor", true, HealPrediction) },
        }},
        -- healPredTextureHeader.
        { title = "Heal Prediction Texture", preset = "form", fields = {
            { control = "switch", label = "Use Custom Texture",
              bind = "useCustomHealPredictionTexture",
              hidden = NotShown("showHealPrediction"), disabled = "combat",
              onChange = HealPrediction },
            { control = "dropdown", label = "Heal Prediction Texture",
              bind = "healPredictionTexture",
              desc = "Statusbar fill texture for the heal prediction bar.",
              options = StatusbarOptions,
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  return not ip.showHealPrediction
                      or not ip.useCustomHealPredictionTexture
              end,
              disabled = "combat",
              onChange = HealPrediction },
        }},
        -- testHealPredHeader.
        { title = "Test", preset = "form", fields = {
            { control = "switch", label = "Test Heal Prediction",
              desc = "Simulate a 10% incoming heal on preview frames for "
                  .. "testing. Disable when done.",
              id = "testHealPrediction", default = false,
              hidden = NotShown("showHealPrediction"), disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testHealPrediction
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testHealPrediction = v
                  if bf.RefreshPreviewHealPrediction then bf:RefreshPreviewHealPrediction() end
              end },
        }},
    }
end

-- reducedMaxHealth tab. The master reads `~= false` like the absorbs
-- one; everything below it hides when it is explicitly off. The Ace
-- inline Position group plus the two font fields that followed it at tab
-- level share one card here -- same order, same predicates.
function PAGES.reducedMax()
    -- hidden = "master explicitly off" -- with the Ace no-profile
    -- handling of each original predicate preserved per field below.
    local function ReducedOff()
        local ip = GetIP()
        return ip and ip.showReducedMaxHealth == false
    end
    -- hidden for the % text fields: master off, or the text not shown.
    local function TextOff()
        local ip = GetIP()
        if not ip then return true end
        return ip.showReducedMaxHealth == false or not ip.showReducedMaxHealthText
    end
    -- ... and additionally when the text is APPENDED to another element
    -- rather than placed on its own.
    local function TextPlacementOff()
        local ip = GetIP()
        if not ip then return true end
        return ip.showReducedMaxHealth == false
            or not ip.showReducedMaxHealthText
            or ip.appendReducedMaxText
    end
    return {
        -- reducedMaxHeader; the note is reducedMaxDesc, kept as the
        -- card's first (full-width) field, above the master switch --
        -- where the Ace page drew it.
        { title = "Temporary Reduced Max Health", preset = "form", fields = {
            { control = "note", wide = true,
              text = "Some boss abilities temporarily reduce a unit's "
                  .. "maximum health. When active, a gray bar fills from "
                  .. "the right side of the health bar to indicate the "
                  .. "unavailable portion. This mirrors the default "
                  .. "Blizzard raid frame behavior." },
            { control = "switch", label = "Show Reduced Max Health Bar",
              desc = "Show a gray overlay on the health bar when a unit's "
                  .. "maximum health is temporarily reduced.",
              id = "showReducedMaxHealth",
              default = (function()
                  local d = Defaults()
                  return d and d.showReducedMaxHealth
              end)(),
              disabled = "combat",
              get = function()
                  local ip = GetIP()
                  return ip and ip.showReducedMaxHealth ~= false
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  ROOT.showReducedMaxHealth = v
                  local bf = BF()
                  if bf and not v and bf.db.global.testReducedMaxHealth then
                      bf.db.global.testReducedMaxHealth = false
                  end
                  ReducedMax()
              end },
        }},
        -- reducedMaxBarTextureHeader.
        { title = "Reduced Max Health Bar Texture", preset = "form", fields = {
            { control = "switch", label = "Use Custom Texture",
              bind = "useCustomReducedMaxTexture",
              hidden = ReducedOff, disabled = "combat",
              onChange = ReducedMax },
            { control = "dropdown", label = "Bar Texture",
              bind = "reducedMaxHealthTexture",
              desc = "Statusbar fill texture for the reduced max health bar.",
              options = StatusbarOptions,
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  return ip.showReducedMaxHealth == false
                      or not ip.useCustomReducedMaxTexture
              end,
              disabled = "combat",
              onChange = ReducedMax },
            { control = "color", label = "Bar Color", alpha = true,
              desc = "Color of the reduced max health overlay bar.",
              id = "reducedMaxHealthColor",
              default = ColorDefault("reducedMaxHealthColor", true),
              hidden = function()
                  local ip = GetIP()
                  if not ip then return true end
                  return ip.showReducedMaxHealth == false
                      or not ip.useCustomReducedMaxTexture
              end,
              disabled = "combat",
              -- The Ace get's `c.a or 0.8` kept: a legacy color saved
              -- without alpha shows the shipped 0.8 rather than opaque.
              get = function()
                  local ip = GetIP()
                  local c  = ip and ip.reducedMaxHealthColor
                  if type(c) ~= "table" then return nil end
                  return { c.r, c.g, c.b, c.a or 0.8 }
              end,
              set = SetColor("reducedMaxHealthColor", true, ReducedMax) },
        }},
        -- reducedMaxTextHeader.
        { title = "Reduced Max Health % Text", preset = "form", fields = {
            { control = "switch", label = "Show Reduced Max Health % Text",
              bind = "showReducedMaxHealthText",
              desc = "Show a separate text element displaying the "
                  .. "remaining max health percentage when temporarily "
                  .. "reduced.",
              hidden = ReducedOff, disabled = "combat",
              onChange = ReducedMaxTextBind },
            { control = "color", label = "Text Color",
              id = "reducedMaxHealthTextColor",
              default = ColorDefault("reducedMaxHealthTextColor", false),
              hidden = TextOff, disabled = "combat",
              get = GetColor("reducedMaxHealthTextColor", false),
              set = SetColor("reducedMaxHealthTextColor", false, ReducedMaxTextLook) },
        }},
        -- appendReducedMaxGroup.
        { title = "Append", preset = "form", fields = {
            { control = "switch", label = "Append Text",
              bind = "appendReducedMaxText",
              desc = "Append the reduced max health percentage to an "
                  .. "existing text element instead of showing it "
                  .. "separately.",
              hidden = TextOff, disabled = "combat",
              onChange = ReducedMaxTextBind },
            { control = "dropdown", label = "Append To",
              bind = "appendReducedMaxTarget",
              desc = "Choose which text element to append the reduced max "
                  .. "health percentage to.",
              options = {
                  { value = "health", text = "Health Text" },
                  { value = "name",   text = "Name" },
              },
              hidden = function()
                  if TextOff() then return true end
                  local ip = GetIP()
                  return not (ip and ip.appendReducedMaxText)
              end,
              disabled = "combat",
              onChange = ReducedMaxTextBind },
        }},
        -- reducedMaxHealthTextPositionGroup -- the Ace Position inline
        -- group, plus the Font Size and Font Border fields that followed
        -- it at tab level with the same visibility -- one card, same
        -- order.
        { title = "Position", preset = "form", fields = {
            -- Anchor dropdown + X + Y offsets, as the panel's one anchor
            -- pad over the same three flat keys.
            { control = "anchor", label = "Anchor",
              binds = { point = "reducedMaxHealthTextPosition",
                        x     = "reducedMaxHealthTextX",
                        y     = "reducedMaxHealthTextY" },
              min = -20, max = 20,
              hidden = TextPlacementOff, disabled = "combat",
              onChange = LayoutFrames },
            { control = "slider", label = "Font Size",
              bind = "reducedMaxHealthFontSize",
              min = 6, max = 24, step = 1,
              hidden = TextPlacementOff, disabled = "combat",
              onChange = LayoutFrames },
            { control = "dropdown", label = "Font Border",
              bind = "reducedMaxHealthFontBorder",
              options = {
                  { value = "",             text = "None" },
                  { value = "OUTLINE",      text = "Outline" },
                  { value = "THICKOUTLINE", text = "Thick Outline" },
              },
              hidden = TextPlacementOff, disabled = "combat",
              onChange = LayoutFrames },
        }},
        -- testHeader.
        { title = "Test", preset = "form", fields = {
            { control = "switch", label = "Test Reduced Max Health (50%)",
              desc = "Simulate a 50% max health reduction on preview "
                  .. "frames for testing.",
              id = "testReducedMaxHealth", default = false,
              hidden = ReducedOff, disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testReducedMaxHealth == true
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testReducedMaxHealth = v
                  if bf.RefreshPreviewReducedMaxHealth then bf:RefreshPreviewReducedMaxHealth() end
              end },
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:AbsorbsPage(subtabId, label)
    local build = PAGES[subtabId]
    if not build then return { groups = {} } end

    local groups = { ScopeStrip(subtabId, label or subtabId) }
    for _, g in ipairs(build()) do groups[#groups + 1] = g end

    return {
        -- The routed storage, wearing the shape of a table. Every `bind`
        -- on this page resolves through it.
        db       = Root,
        -- Buzzard Frames' own defaults, in the same shape -- what makes
        -- the right-click "Reset to default" work on every bound field
        -- without it declaring a default of its own.
        defaults = Defaults,
        groups   = groups,
    }
end
