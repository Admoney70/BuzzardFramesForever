-- ============================================================
-- BuzzardFramesOptions: Pages_HealthPower.lua
-- The Raid/Party Frames > Health & Power Bars section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_HealthPower.lua:
-- the same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by five BuzzardPanel pages -- one per
-- subtab (health, background, status, power, range), each a route of its
-- own under `raidPartyFrames/healthPower`, drawn as a strip by the `tabs`
-- navigator that node declares. The Pages_Icons pattern, subtab for
-- subtab.
--
-- Storage: rpDB.profile.healthPower.* (the global pseudo-layout), or
-- flat.healthPower.* for whichever keys belong to a subtab whose own
-- healthPower_<subtab> toggle is on. That routing is PER KEY and it is not
-- this file's business: reads go through
-- BF:GetSectionProfile("healthPower", ...) -- which answers with the
-- merged view -- and writes through BF:WriteSectionKey /
-- BF:SectionKeyTable, exactly as the Ace page's getIP/writeIP do. Nothing
-- here touches a db table directly, which is what keeps the two panels in
-- step.
--
-- One thing this section does that Icons did not: its Ace deps.set was
-- makeRpSet("healthPower", true) -- every write is followed by
-- aura-cache invalidation, routed by what WriteSectionKey reports:
-- per-Layout ON for that key's subtab invalidates that flat's aura cache,
-- OFF invalidates every flat that falls through to the global for that
-- subtab. ROOT's __newindex below reproduces that chain, so every write
-- on this page carries it -- the fields that keep get/set route their
-- writes through ROOT for exactly this reason.
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
    return bf:GetSectionProfile("healthPower", bf:GetModifyingProfile())
end

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db. Health & Power has no such table: what a key READS from and what it
-- WRITES to are decided per key, by that key's subtab and that subtab's
-- per-Layout toggle, and the read side is a CACHED COPY that must never
-- be written to. So the page hands the library a table shaped like the
-- one it wants and routed like the one Buzzard Frames has.
--
-- __newindex is the panel's copy of makeRpSet("healthPower", true): the
-- write through WriteSectionKey, then the aura-cache invalidation routed
-- by what it reports. No bound key on this page is table-valued -- the
-- color pickers keep get/set adapters (the stored shape is {r,g,b}
-- keyed, the control's is an array) and route their writes back through
-- here or through SectionKeyTable, whichever their Ace setter did.
local ROOT = setmetatable({}, {
    __index = function(_, k)
        local ip = GetIP()
        return ip and ip[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if not bf then return end
        local perFlat, flat, togKey = bf:WriteSectionKey("healthPower", k, v)
        if perFlat then
            bf:InvalidateFlatAuraCache(flat)
        else
            bf:InvalidateGlobalSectionFlatCaches(togKey or "healthPower")
        end
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
    return d and d.healthPower
end

-- ── Shared option lists ────────────────────────────────────────

-- The statusbar textures LibSharedMedia knows, alphabetical -- the same
-- list the Ace page's LSM30_Statusbar widget offered, previews and all:
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
-- One function per chain the Ace setters ran, in the same order those
-- setters ran it. The WRITE and its cache invalidation have already
-- happened (ROOT above); these are the frame refreshes, scheduled by the
-- control's refresh tier -- sliders and colors coalesce a drag into one
-- call, and the BF:DebounceOption keys are the SAME keys the Ace page
-- used, so the two panels share one trailing timer while both exist.

local function ForEachFrame(fn)
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do fn(bf, f) end
end

-- Color re-evaluation: mode/color changes on the health bar fill and
-- the status overlays route here, debounced under the Ace page's own key.
local function HealthColors()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("hpColors", function() bf:RefreshColors() end)
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
end

-- The health color MODE feeds the gradient curve cache and the oUF
-- color rebind before the repaint, exactly as the Ace setter did --
-- stale curves repainted are the wrong colors, briefly and visibly.
local function HealthColorMode()
    local bf = BF()
    if not bf then return end
    if bf.RebuildHealthGradientCurves then bf:RebuildHealthGradientCurves() end
    if bf.RebindHealthBarColor then bf:RebindHealthBarColor() end
    bf:DebounceOption("hpColors", function() bf:RefreshColors() end)
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
end

-- Texture and background changes need the health bar LAYOUT walk
-- (SetStatusBarTexture and color re-eval both live there).
local function HealthBarLayout()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("hpHealthLayout", function() bf:RefreshHealthBarLayout() end)
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
end

-- The health bar's TEXTURE needs one more call than its colors do.
--
-- RefreshPreviewHealthBar sets the preview frames' color and value and
-- nothing else -- ApplyPreviewHealthBar says so itself: "Texture and bg
-- anchors are set by HealthBar:Layout, called from LayoutPreviewFrame".
-- So a texture edit repainted the real frames and left the preview showing
-- whatever it was last laid out with: the new texture never appeared, and
-- turning the custom texture OFF left the old one painted on frames that
-- should have gone back to the default.
--
-- RefreshPreviewFrames is what does it: LAYOUT AND THEN THE DUMMY DATA.
--
-- Not RefreshPreviewLayout, which is the layout pass alone. A preview
-- frame runs every indicator's Layout, the same code path a real frame
-- runs -- and an indicator's Layout shows the bars it owns, because on a
-- real frame the update that follows decides what to hide. On a preview
-- frame that decision IS the dummy-data pass, so laying out without
-- re-applying it left absorb bars shown on frames whose Test Absorb is
-- off: the layout showed them and nothing came along to take them away.
--
-- It runs inside the same debounce as the real-frame walk, so flipping the
-- toggle repeatedly coalesces rather than rebuilding the preview once per
-- click; the color re-eval stays immediate, because it is cheap and it is
-- what the reader sees first (the class color darkens with a custom
-- texture).
local function HealthBarTexture()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("hpHealthLayout", function()
        bf:RefreshHealthBarLayout()
        if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
    end)
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
end

-- The background color mode rebuilds the gradient curves and rebinds
-- before the layout walk, as its Ace setter did.
local function BgColorMode()
    local bf = BF()
    if not bf then return end
    if bf.RebuildHealthGradientCurves then bf:RebuildHealthGradientCurves() end
    if bf.RebindHealthBarColor then bf:RebindHealthBarColor() end
    bf:DebounceOption("hpHealthLayout", function() bf:RefreshHealthBarLayout() end)
    if bf.RefreshPreviewHealthBar then bf:RefreshPreviewHealthBar() end
end

-- The offline toggle repaints offline state AND range fade -- turning the
-- custom color on changes what the range fader has to fade.
local function OfflineShown()
    ForEachFrame(function(bf, f)
        if bf.UpdateOffline then bf:UpdateOffline(f) end
        bf:UpdateRange(f)
    end)
end

local function OfflineColor()
    ForEachFrame(function(bf, f)
        if bf.UpdateOffline then bf:UpdateOffline(f) end
    end)
end

local function OfflineFade()
    ForEachFrame(function(bf, f) bf:UpdateRange(f) end)
end

-- Dead color is applied by StatusOverlay, covered by RefreshColors.
-- _healthState is cleared first to force the re-eval, as the Ace setters
-- did -- the overlay caches its last decision per frame.
local function DeadColors()
    local bf = BF()
    if not bf then return end
    ForEachFrame(function(_, f) f._healthState = nil end)
    bf:DebounceOption("hpColors", function() bf:RefreshColors() end)
end

local function HostileColors()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("hpColors", function() bf:RefreshColors() end)
end

-- Showing or hiding a power bar changes the frame's geometry, so every
-- visibility toggle re-lays the frame out and re-reads its power.
local function PowerBarsShown()
    ForEachFrame(function(bf, f)
        bf:LayoutFrame(f)
        bf:UpdatePower(f)
    end)
    local bf = BF()
    if bf and bf.RefreshPreviewPowerBar then bf:RefreshPreviewPowerBar() end
end

local function PowerBarHeightFx()
    ForEachFrame(function(bf, f)
        bf:LayoutFrame(f)
        bf:UpdatePower(f)
    end)
    local bf = BF()
    if bf and bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

-- Scoped: only re-Layouts the indicators that actually read
-- aurasAbovePowerBar, instead of the full RefreshAllAuras sweep, when the
-- addon offers the scoped walk.
local function AurasAbovePower()
    local bf = BF()
    if not bf then return end
    if bf.RefreshAurasAbovePowerBarToggle then
        bf:RefreshAurasAbovePowerBarToggle()
    else
        bf:RefreshAllAuras()
    end
    if bf.RefreshDummyAuras then bf:RefreshDummyAuras() end
end

-- Power bar background is a repaint, not a re-layout.
local function PowerBarPaint()
    ForEachFrame(function(bf, f) bf:UpdatePower(f) end)
    local bf = BF()
    if bf and bf.RefreshPreviewPowerBar then bf:RefreshPreviewPowerBar() end
end

local function PowerBarLayoutFx()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("hpPowerLayout", function() bf:RefreshPowerBarLayout() end)
    if bf.RefreshPreviewPowerBar then bf:RefreshPreviewPowerBar() end
end

local function RangeFrames()
    ForEachFrame(function(bf, f) bf:UpdateRange(f) end)
    local bf = BF()
    if bf and bf.RefreshDummyFrames then bf:RefreshDummyFrames() end
end

local function DeadOORColors()
    local bf = BF()
    if not bf then return end
    bf:RefreshAllStatusColors()
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Health & Power carries FIVE per-Layout toggles, one per subtab
-- (healthPower_health through healthPower_range), so the strip belongs to
-- the subtab rather than the section -- and Copy to moves that subtab's
-- keys and no others, which is what stops copying the Health Bar colors
-- onto the raid Layout quietly overwriting its Power settings.

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

    local keys = bf.SECTION_SUBTAB_KEYS and bf.SECTION_SUBTAB_KEYS.healthPower
    keys = keys and keys[subtabId]
    if not keys then return end

    local srcSection = rawget(src, "healthPower")
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.healthPower end
    if type(srcSection) ~= "table" then return end

    if type(rawget(dst, "healthPower")) ~= "table" then
        dst.healthPower = {}
        -- A flat's section table falls THROUGH to the global for anything
        -- it does not hold. A table created without that wiring answers
        -- nil for every key this copy does not carry.
        if bf.WireSectionFallback then bf:WireSectionFallback(dst, "healthPower") end
    end
    local dstSection = rawget(dst, "healthPower")

    for _, k in ipairs(keys) do
        local v = srcSection[k]
        if v ~= nil then
            dstSection[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("healthPower") end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function TogKey(subtabId)
    local bf = BF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and bf.SECTION_SUBTAB_TOGGLE.healthPower
    return m and m[subtabId]
end

local function NotPerLayout(subtabId)
    return function()
        local bf = BF()
        return not (bf and bf:IsPerLayoutSectionSubtab("healthPower", subtabId))
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
          id = TogKey(subtabId) or ("healthPower_" .. subtabId), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give " .. label .. " its own "
              .. "settings per Layout -- the other Health & Power subtabs "
              .. "keep their own toggles.",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSectionSubtab("healthPower", subtabId)
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
              .. "Health & Power is left alone.",
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

local function Sw(bind, label, effect, opts)
    local f = { control = "switch", label = label, bind = bind,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A fraction stored 0-1, shown 0-100. The Ace page's isPercent sliders
-- keep their storage shape (0.05 steps on a 0-1 value); the panel's
-- slider shows integers in its value box, so the control works in percent
-- units and these adapters convert at the edge. `id` + `default` (in the
-- same percent units) are what keep undo and reset working without a
-- bind.
local function Pct(key, label, lo, hi, effect, opts)
    local d  = Defaults()
    local dv = d and d[key]
    local f = {
        control = "slider", label = label, id = key,
        min = lo, max = hi, step = 5,
        default = dv and math.floor(dv * 100 + 0.5) or nil,
        onChange = effect, disabled = "combat",
        get = function()
            local ip = GetIP()
            local v = ip and ip[key]
            if v == nil then return nil end
            return math.floor(v * 100 + 0.5)
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = v / 100
        end,
    }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A color stored {r,g,b} keyed, shown by a control that speaks arrays.
-- The set builds a FRESH keyed table and routes it through ROOT --
-- exactly what the Ace setters' WriteSectionKey calls did -- so the
-- per-subtab routing and the aura-cache invalidation both apply.
local function Color(key, label, effect, opts)
    local d  = Defaults()
    local dc = d and d[key]
    local f = {
        control = "color", label = label, id = key,
        default = dc and { dc.r, dc.g, dc.b } or nil,
        onChange = effect, disabled = "combat",
        get = function()
            local ip = GetIP()
            local c = ip and ip[key]
            if not c then return nil end
            return { c.r, c.g, c.b }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = { r = v[1], g = v[2], b = v[3] }
        end,
    }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- The two colors whose Ace setters MUTATED the stored table in place
-- rather than replacing it (deadBackgroundColor, hostileColor) keep that
-- shape, through SectionKeyTable -- the router that answers with the
-- table to mutate, never the merged view, and materialises the per-flat
-- copy on demand.
local function ColorInPlace(key, label, effect, opts)
    local f = Color(key, label, effect, opts)
    f.set = function(_, _, v)
        if InCombatLockdown() then return end
        local bf = BF()
        local c = bf and bf:SectionKeyTable("healthPower", key)
        if c then c.r, c.g, c.b = v[1], v[2], v[3] end
    end
    return f
end

-- A gate in the card HEADER, and the card collapses when it is off --
-- the Ace page's `hidden` predicate made visible. A gate cannot bind
-- (it is a group's declaration, not a field's), so the routing and the
-- effect are written out here; `id` and `default` are what make it
-- reset with the rest of its card.
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

-- ── The five pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages: the ids ARE the subtab ids in
-- BF.SECTION_SUBTABS.healthPower, so the per-Layout toggles line up by
-- construction. Titles are the Ace tabs' own names, in their order.
BuzzardFramesOptions.HEALTHPOWER_SUBTABS = {
    { id = "health",     title = "Health Bar" },
    { id = "background", title = "Background" },
    { id = "status",     title = "Status" },
    { id = "power",      title = "Power" },
    { id = "range",      title = "Out of Range Frames" },
}

local PAGES = {}

-- The Ace healthTab: healthColorGroup + healthBarTextureGroup.
function PAGES.health()
    return {
        { title = "Health Bar Color", preset = "form", fields = {
            -- healthColorMode: one dropdown over TWO stored keys
            -- (useCustomHealthColor / useHealthGradient), so it keeps
            -- get/set and both writes route through ROOT.
            { control = "dropdown", label = "Color Mode",
              id = "healthColorMode", default = "class",
              disabled = "combat", onChange = HealthColorMode,
              options = {
                  { value = "class",    text = "Use Class Colors" },
                  { value = "gradient", text = "Use Color Gradient (Health Percent)" },
                  { value = "static",   text = "Use Static Color" },
              },
              get = function()
                  local ip = GetIP()
                  if not ip or not ip.useCustomHealthColor then return "class" end
                  if ip.useHealthGradient then return "gradient" end
                  return "static"
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  if v == "class" then
                      ROOT.useCustomHealthColor = false
                      ROOT.useHealthGradient    = false
                  elseif v == "gradient" then
                      ROOT.useCustomHealthColor = true
                      ROOT.useHealthGradient    = true
                  else -- "static"
                      ROOT.useCustomHealthColor = true
                      ROOT.useHealthGradient    = false
                  end
              end },
            Color("healthColor", "Health Color", HealthColors, {
                hidden = function()
                    local ip = GetIP()
                    return not ip or not ip.useCustomHealthColor
                        or (ip.useHealthGradient == true)
                end }),
            Pct("healthBarOpacity", "Health Bar Opacity", 0, 100, HealthColors, {
                desc = "Opacity of the health bar fill. Truly independent of "
                    .. "the background -- the background is only drawn in the "
                    .. "missing-health region and never bleeds through the fill.",
                -- No entry in the defaults table; the Ace getter's own
                -- fallback (1.0), in percent units.
                default = 100,
                -- In gradient mode the opacity comes from the per-stop
                -- alpha of the health gradient color pickers in the
                -- Colors section.
                hidden = function()
                    local ip = GetIP()
                    return ip and ip.useCustomHealthColor and ip.useHealthGradient
                end }),
            -- colorsNote: static mode takes its color entirely from the
            -- picker above and reads nothing from the global Colors
            -- section, so the pointer is hidden there. Class mode reads
            -- Class Colors, gradient mode the health gradient stops.
            { control = "note", wide = true,
              text = "Class Colors and Health Gradient Colors can be "
                  .. "customized in the global Colors section:",
              hidden = function()
                  local ip = GetIP()
                  return (ip and ip.useCustomHealthColor and not ip.useHealthGradient)
                      and true or false
              end },
            -- openColorsBtn: the Ace SelectGroup("globalStyles","colors"),
            -- as a route change. No deferral needed -- that C_Timer.After
            -- was an AceConfigDialog reentrancy workaround.
            { control = "button", text = "Colors",
              hidden = function()
                  local ip = GetIP()
                  return (ip and ip.useCustomHealthColor and not ip.useHealthGradient)
                      and true or false
              end,
              onClick = function(_, ctx)
                  ctx.app:Navigate("globalStyles", "colors")
              end },
        }},
        -- healthBarTextureGroup, its useCustomHealthBarTexture toggle in
        -- the header: the Ace page hid the picker while it was off, and a
        -- card that collapses says that more plainly.
        { title = "Health Bar Texture", preset = "form",
          toggle = Gate("useCustomHealthBarTexture", "Use Custom Health Texture",
                        HealthBarTexture),
          fields = {
            { control = "dropdown", label = "Health Bar Texture",
              bind = "healthBarTexture",
              desc = "Texture for the health bar fill.",
              options = StatusbarOptions,
              onChange = HealthBarTexture, disabled = "combat" },
        }},
    }
end

-- The Ace backgroundTab: backgroundGroup, gated by
-- useCustomBackgroundColor exactly as its Ace `hidden` predicates gated
-- every other widget in the group.
function PAGES.background()
    return {
        { title = "Background Color", preset = "form",
          toggle = Gate("useCustomBackgroundColor", "Use Custom Background Color",
                        HealthBarLayout),
          fields = {
            -- bgColorMode: one dropdown over useBgGradient / useBgClass.
            -- Background lists the DEFAULT (static) first, unlike the
            -- health fill above which defaults to class. The two
            -- dropdowns therefore sort differently on purpose.
            { control = "dropdown", label = "Color Mode",
              id = "bgColorMode", default = "static",
              disabled = "combat", onChange = BgColorMode,
              options = {
                  { value = "static",   text = "Use Static Color" },
                  { value = "gradient", text = "Use Color Gradient (Health Percent)" },
                  { value = "class",    text = "Use Class Colors" },
              },
              get = function()
                  local ip = GetIP()
                  if ip and ip.useBgGradient then return "gradient" end
                  if ip and ip.useBgClass then return "class" end
                  return "static"
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  ROOT.useBgGradient = (v == "gradient")
                  ROOT.useBgClass    = (v == "class")
              end },
            Color("backgroundColor", "Background Color", HealthBarLayout, {
                hidden = function()
                    local ip = GetIP()
                    return not (ip and ip.useCustomBackgroundColor)
                        or (ip and (ip.useBgGradient or ip.useBgClass))
                end }),
            -- backgroundAlpha: in gradient mode the opacity comes from
            -- the per-stop alpha of the bg gradient color pickers in the
            -- Colors section.
            Pct("backgroundAlpha", "Background Opacity", 0, 100, HealthBarLayout, {
                hidden = function()
                    local ip = GetIP()
                    if not (ip and ip.useCustomBackgroundColor) then return true end
                    return ip.useBgGradient == true
                end }),
            Pct("bgClassDarken", "Background Darkening", 0, 80, HealthBarLayout, {
                desc = "Darkens the class-colored background. 0% = full class "
                    .. "color; higher values multiply the color toward black "
                    .. "for a dimmer backdrop behind the fill.",
                hidden = function()
                    local ip = GetIP()
                    return not (ip and ip.useCustomBackgroundColor)
                        or not (ip and ip.useBgClass)
                end }),
            -- gradientNote + openColorsBtn, gradient mode only.
            { control = "note", wide = true,
              text = "Background gradient colors can be customized in the "
                  .. "global Colors section:",
              hidden = function()
                  local ip = GetIP()
                  return not (ip and ip.useCustomBackgroundColor)
                      or not ip.useBgGradient
              end },
            { control = "button", text = "Colors",
              hidden = function()
                  local ip = GetIP()
                  return not (ip and ip.useCustomBackgroundColor)
                      or not ip.useBgGradient
              end,
              onClick = function(_, ctx)
                  ctx.app:Navigate("globalStyles", "colors")
              end },
        }},
    }
end

-- The Ace statusTab: offlineGroup + deadGroup + hostileGroup.
function PAGES.status()
    return {
        -- offlineGroup keeps its toggle as a FIELD rather than a header
        -- gate: fadeOfflineFrames is independent of it in the Ace page --
        -- a gate would wrongly hide it.
        { title = "Offline Bar Color", preset = "form", fields = {
            Sw("useCustomOfflineColor", "Use Custom Offline Color", OfflineShown, {
                desc = "Replace the health bar color with a custom color for "
                    .. "offline units." }),
            Color("offlineBackgroundColor", "Offline Bar Color", OfflineColor, {
                desc = "Color that replaces the health bar for offline units.",
                hidden = function()
                    local ip = GetIP()
                    return not (ip and ip.useCustomOfflineColor)
                end }),
            Sw("fadeOfflineFrames", "Fade Offline Frames", OfflineFade, {
                desc = "Apply range fading to offline unit frames (uses the "
                    .. "Out-of-Range Opacity setting)." }),
        }},
        { title = "Dead Background Color", preset = "form",
          toggle = Gate("useCustomDeadColor", "Use Custom Dead Color", DeadColors),
          fields = {
            ColorInPlace("deadBackgroundColor", "Dead Color", DeadColors),
            -- deadBackgroundOpacity: the Ace slider had no isPercent, but
            -- it is the same 0-1/0.05 shape as its neighbors; shown in
            -- percent units like them (see the notes file).
            Pct("deadBackgroundOpacity", "Dead Background Color Opacity",
                0, 100, DeadColors),
        }},
        { title = "Hostile Health Bar Color", preset = "form",
          toggle = Gate("useCustomHostileColor", "Use Custom Hostile Color",
                        HostileColors),
          fields = {
            ColorInPlace("hostileColor", "Hostile Color", HostileColors),
        }},
    }
end

-- Are ALL the power bars off? The Ace page hid the Layout, Texture and
-- Background groups whole; the library has no group-level `hidden`, so
-- the predicate rides every field in those cards instead (their headers
-- stay -- see the notes file).
local function NoPowerBarsShown()
    local ip = GetIP()
    if not ip then return true end
    return not ip.showAllPowerBars and not ip.showPowerBarHealers
        and not ip.showPowerBarBloodDK
end

-- The Ace powerTab, cards in its `order` (powerBarVisibilityGroup 16,
-- powerBarLayoutGroup 17, texture 19, background 20 -- the source WRITES
-- background before texture, but its orders say otherwise, and order is
-- what the Ace dialog drew).
function PAGES.power()
    return {
        { title = "Show Power Bars", preset = "form", fields = {
            Sw("showAllPowerBars", "Show All Power Bars", PowerBarsShown, {
                desc = "When enabled, all units show power bars. When "
                    .. "disabled, only the selected roles below will show "
                    .. "power bars." }),
            Sw("showPowerBarHealers", "Show Healer Power Bars", PowerBarsShown, {
                hidden = function()
                    local ip = GetIP()
                    return ip and ip.showAllPowerBars
                end }),
            Sw("showPowerBarBloodDK", "Show Blood DK Power Bars", PowerBarsShown, {
                hidden = function()
                    local ip = GetIP()
                    return ip and ip.showAllPowerBars
                end }),
        }},
        { title = "Power Bar Layout", preset = "form", fields = {
            { control = "slider", label = "Power Bar Height",
              bind = "powerBarHeight", min = 1, max = 30, step = 1,
              onChange = PowerBarHeightFx, disabled = "combat",
              hidden = NoPowerBarsShown },
            Sw("aurasAbovePowerBar", "Place Auras Above Power Bar", AurasAbovePower, {
                desc = "When enabled, auras will be anchored to the health "
                    .. "bar bottom instead of the frame bottom, placing them "
                    .. "above the power bar",
                hidden = NoPowerBarsShown }),
        }},
        -- powerBarTextureGroup: NOT header-gated, because the whole card
        -- hides with the power bars and a gate switch left interactive in
        -- the header of an otherwise-hidden card would not.
        { title = "Power Bar Texture", preset = "form", fields = {
            Sw("useCustomPowerBarTexture", "Use Custom Power Texture",
               PowerBarLayoutFx, { hidden = NoPowerBarsShown }),
            { control = "dropdown", label = "Power Bar Texture",
              bind = "powerBarTexture",
              desc = "Texture for the power bar fill.",
              options = StatusbarOptions,
              onChange = PowerBarLayoutFx, disabled = "combat",
              hidden = function()
                  local ip = GetIP()
                  return NoPowerBarsShown()
                      or not (ip and ip.useCustomPowerBarTexture)
              end },
        }},
        -- powerBarBackgroundGroup: powerBarBgOpacity is NOT hidden by the
        -- custom-color toggle in the Ace page, so no gate here either.
        { title = "Power Bar Background", preset = "form", fields = {
            Sw("useCustomPowerBarBgColor", "Use Custom Background Color",
               PowerBarPaint, { hidden = NoPowerBarsShown }),
            -- powerBarBgColor carries an alpha the picker does not show;
            -- the Ace setter preserved it, so this one does too.
            { control = "color", label = "Background Color",
              id = "powerBarBgColor",
              default = (function()
                  local d  = Defaults()
                  local dc = d and d.powerBarBgColor
                  return dc and { dc.r, dc.g, dc.b } or nil
              end)(),
              desc = "Color of the power bar background.",
              onChange = PowerBarPaint, disabled = "combat",
              hidden = function()
                  local ip = GetIP()
                  return NoPowerBarsShown()
                      or not (ip and ip.useCustomPowerBarBgColor)
              end,
              get = function()
                  local ip = GetIP()
                  local c = ip and ip.powerBarBgColor
                  if not c then return nil end
                  return { c.r, c.g, c.b }
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local ip = GetIP()   -- read: merged view, for the preserved alpha
                  local c = ip and ip.powerBarBgColor
                  ROOT.powerBarBgColor =
                      { r = v[1], g = v[2], b = v[3], a = (c and c.a) or 1.0 }
              end },
            Pct("powerBarBgOpacity", "Background Opacity", 0, 100,
                PowerBarPaint, { hidden = NoPowerBarsShown }),
        }},
    }
end

-- The Ace rangeTab: its four `header` boundaries become four cards.
function PAGES.range()
    return {
        -- rangeHeader "Out of Range Fading": enableRangeFade in the card
        -- header, the alpha it gates inside.
        { title = "Out of Range Fading", preset = "form",
          toggle = Gate("enableRangeFade", "Fade Out-of-Range Frames", RangeFrames),
          fields = {
            Pct("rangeFadeAlpha", "Out-of-Range Opacity", 10, 90, RangeFrames),
        }},
        -- desatHeader "Out of Range Darkening".
        { title = "Out of Range Darkening", preset = "form",
          toggle = Gate("enableRangeDesaturate", "Darken Out-of-Range Frames",
                        RangeFrames),
          fields = {
            Pct("rangeDesaturation", "Out-of-Range Darkening", 0, 80, RangeFrames),
        }},
        -- deadColorOORHeader; the deadColorOORDesc note keeps its body.
        -- (The deadColorOORSpacer description above it is a pure spacer
        -- and is dropped -- the card gap does its job.)
        { title = "Dead Color \226\128\147 Out of Range", preset = "form", fields = {
            { control = "note", wide = true,
              text = "When a dead unit is out of range, the Dead text color "
                  .. "is blended toward gray so it's visually distinct. The "
                  .. "slider controls how much of the original color is "
                  .. "retained (100% = full color, 0% = fully gray)." },
            Pct("deadColorOORFactor", "Color Retention", 0, 100, DeadOORColors, {
                desc = "How much of the Dead color to keep when the unit is "
                    .. "out of range. 100% keeps the full color; 0% goes "
                    .. "fully gray." }),
        }},
        -- testHeader / testOOR: a preview flag, not a profile setting --
        -- and, like its Ace original, deliberately NOT combat-gated.
        { title = "Test", preset = "form", fields = {
            { control = "switch", label = "Test Out of Range",
              id = "testOOR", default = false,
              desc = "Simulate out-of-range on the preview frames to see how "
                  .. "fade and darkening settings look.",
              get = function()
                  local bf = BF()
                  return bf and bf._previewOOR == true
              end,
              set = function(_, _, v)
                  local bf = BF()
                  if not bf then return end
                  bf._previewOOR = v or nil
                  if bf.RefreshPreviewStatus then bf:RefreshPreviewStatus() end
              end },
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:HealthPowerPage(subtabId, label)
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
