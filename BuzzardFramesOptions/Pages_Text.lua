-- ============================================================
-- BuzzardFramesOptions: Pages_Text.lua
-- The Raid/Party Frames > Text section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Text.lua: the
-- same settings, the same storage and the same side effects, with the
-- AceConfig args table replaced by six BuzzardPanel pages -- one per
-- subtab, each a route of its own under `raidPartyFrames/text`, drawn as
-- a strip by the `tabs` navigator that node declares (the Pages_Icons
-- pattern).
--
-- Storage: rpDB.profile.text.* (the global pseudo-layout), or flat.text.*
-- for whichever keys belong to a subtab whose own text_<subtab> toggle is
-- on. That routing is PER KEY and it is not this file's business: reads go
-- through BF:GetSectionProfile("text", ...) -- which answers with the
-- merged view -- and writes through BF:WriteSectionKey / BF:SectionKeyTable,
-- exactly as the Ace page's getT()/writeT() do. Nothing here touches a db
-- table directly, which is what keeps the two panels in step.
--
-- Every field that can bind is BOUND rather than given a get/set pair. A
-- bind path is what the library's right-click menu records an undo against
-- and looks a default up by, so binding is what makes "Undo change" and
-- "Reset to default" work without every field declaring anything. The
-- paths resolve against ROOT below, which is the routed storage wearing
-- the shape of a plain table. Color pickers keep get/set adapters (the
-- stored shape is {r,g,b[,a]} keyed, the control's is an array) and route
-- their writes back through ROOT or SectionKeyTable, whichever their Ace
-- setter did.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- The section as it reads right now: the merged view for the modifying
-- Layout, which degrades to the global wherever no subtab is per-Layout.
local function GetT()
    local bf = BF()
    if not (bf and bf.GetSectionProfile) then return nil end
    return bf:GetSectionProfile("text", bf:GetModifyingProfile())
end

local function TPv(key)
    local tp = GetT()
    return tp and tp[key]
end

-- Font-name keys read back through BF:NormalizeFontName, exactly as the
-- Ace page's getFont() does: legacy paths / "DEFAULT" / unregistered names
-- map back onto a real LSM name, or the dropdown renders empty.
local FONT_KEYS = {
    nameFont = true, healthFont = true, statusFont = true,
    levelFont = true, groupLabelFont = true, vehicleFont = true,
}

-- ── The write-through root ─────────────────────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db and reading or writing the slot it lands on. Text has no such table:
-- what a key READS from and what it WRITES to are decided per key, by that
-- key's subtab and that subtab's per-Layout toggle, and the read side is a
-- CACHED COPY that must never be written to.
--
-- So the page hands the library a table shaped like the one it wants and
-- routed like the one Buzzard Frames has: reads fall through to the merged
-- view, writes go to WriteSectionKey (the exact route of the Ace page's
-- writeT/setFont; makeRpSet("text") does no aura-cache invalidation, so
-- none is added here). The two nested position tables (namePosition,
-- vehicleNamePosition) need one more level -- an anchor pad binds
-- `namePosition.point` -- so a key whose value is a table answers with a
-- wrapper of its own, reading from the view and writing through
-- SectionKeyTable, which materialises the per-flat copy on demand exactly
-- as the Ace setters do.
local subCache = {}

local function SubTable(key)
    local w = subCache[key]
    if w then return w end
    w = setmetatable({}, {
        __index = function(_, k)
            local tp = GetT()
            local t = tp and tp[key]
            return t and t[k]
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local bf = BF()
            -- SectionKeyTable returns the table to MUTATE -- the flat's own
            -- copy when this key's subtab is per-Layout, the global's
            -- otherwise. Never the merged view.
            local t = bf and bf:SectionKeyTable("text", key)
            if t then t[k] = v end
        end,
    })
    subCache[key] = w
    return w
end

local ROOT = setmetatable({}, {
    __index = function(_, k)
        local tp = GetT()
        local v = tp and tp[k]
        if type(v) == "table" then return SubTable(k) end
        if FONT_KEYS[k] then
            local bf = BF()
            if bf and bf.NormalizeFontName then return bf:NormalizeFontName(v) end
        end
        return v
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        if bf then bf:WriteSectionKey("text", k, v) end
    end,
})

local function Root() return ROOT end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library resolves
-- a bind path straight into it -- `namePosition.point` included.
local function Defaults()
    local bf = BF()
    local d  = bf and bf.raidPartyFrameDefaults
    d = d and d.profile
    return d and d.text
end

-- ── Side effects ───────────────────────────────────────────────
--
-- One function per chain the Ace setters ran, in the order those setters
-- ran it. The WRITE has already happened (ROOT above); these are the frame
-- refreshes, scheduled by the control's refresh tier -- sliders and
-- colors coalesce a drag into one trailing call, and the BF:DebounceOption
-- keys are the SAME keys the Ace page uses (textNames, textGroupLabels),
-- so the two panels share one trailing timer while both exist.

local function ForEachFrame(fn)
    local bf = BF()
    if not bf then return end
    for f in pairs(bf.activeFrames or {}) do fn(bf, f) end
end

-- Update text positions on all active frames without a full RefreshAll.
-- The Ace page's layoutFrames(), immediate and un-debounced there too.
local function LayoutFrames()
    local bf = BF()
    if not bf then return end
    bf:LayoutAllIndicators()
    if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

-- Update only the name font without triggering a full LayoutFrame (avoids
-- flashing). IMPORTANT: reads must come from the ACTIVE flat, not the
-- modifying one. This applies the result to every frame in activeFrames --
-- if it read from GetT() (the modifying flat), editing raid30's name font
-- while the game context is party would visually push raid30's font onto
-- the live party frames. The underlying writes already landed correctly on
-- the modifying flat's text; this just needs to reflect the change
-- visually on whatever frames are actually rendering right now. Ported
-- verbatim from the Ace page's refreshNameFont.
local function RefreshNameFont()
    local bf = BF()
    if not bf then return end
    local isRaid = bf:ResolveActiveIsRaid()
    local activeFlat = isRaid and bf:GetRaidProfile() or bf:GetActivePartyProfile()
    local tp = bf:GetSectionProfile("text", activeFlat)
    if not tp then return end
    for _, frame in next, bf.registeredFrames or {} do
        if frame.nameText then
            local origFont  = frame.nameText.SF_defaultFont  or "Fonts\\FRIZQT__.TTF"
            local origSize  = frame.nameText.SF_defaultSize  or 10
            local origFlags = frame.nameText.SF_defaultFlags or ""
            local fontPath, fontSize, fontFlags
            if tp.adjustNameFont then
                fontPath  = bf:ResolveFontPath(tp.nameFont)
                fontSize  = tp.nameFontSize
                fontFlags = tp.nameFontBorder or ""
            else
                fontPath  = origFont
                fontSize  = origSize
                fontFlags = origFlags
            end
            -- Switch to a different font briefly then back, forcing the
            -- client to flush the render state and pick up the new
            -- JustifyH every time.
            local altFont = (fontPath == origFont)
                and "Fonts\\FRIZQT__.TTF"
                or origFont
            frame.nameText:SetFont(altFont, fontSize, fontFlags)
            frame.nameText:SetFont(fontPath, fontSize, fontFlags)
            -- The configured font is cached on the FontString (NameText's
            -- Layout owns it).
            frame.nameText._cfgFontPath  = fontPath
            frame.nameText._cfgFontSize  = fontSize
            frame.nameText._cfgFontFlags = fontFlags
            local np = tp.namePosition
            local anchorPoint = (np and np.point) or "CENTER"
            if anchorPoint:find("LEFT") then frame.nameText:SetJustifyH("LEFT")
            elseif anchorPoint:find("RIGHT") then frame.nameText:SetJustifyH("RIGHT")
            else frame.nameText:SetJustifyH("CENTER") end
        end
    end
    if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
end

-- The name-position composite fires ONE effect for its three binds, so it
-- runs the union of the Ace chains: the point select ran layoutFrames +
-- refreshNameFont (justification follows the anchor point), the offset
-- sliders ran layoutFrames alone. The extra RefreshNameFont after an
-- offset drag re-applies current state and is harmless.
local function NameLayoutAndFont()
    LayoutFrames()
    RefreshNameFont()
end

-- Name text repaints, debounced under the SAME key the Ace page uses.
local function NamesRefresh()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("textNames", function() bf:RefreshAllNames() end)
end

local function NamesRefreshPreview()
    NamesRefresh()
    local bf = BF()
    if bf and bf.RefreshPreviewName then bf:RefreshPreviewName() end
end

local function HealthTextUpdate()
    ForEachFrame(function(bf, f) bf:UpdateHealth(f) end)
end

local function PreviewHealthText()
    local bf = BF()
    if bf and bf.RefreshPreviewHealthText then bf:RefreshPreviewHealthText() end
end

-- Toggling the color override back ON must also run the per-unit
-- class-color path, which lives in Update rather than Layout -- the Ace
-- setter's own comment. Same order: layout walk, UpdateHealth walk,
-- preview.
local function HealthTextColorToggled()
    LayoutFrames()
    HealthTextUpdate()
    PreviewHealthText()
end

local function HealthTextClassColor()
    HealthTextUpdate()
    PreviewHealthText()
end

local function HealthTextColorPicked()
    LayoutFrames()
    PreviewHealthText()
end

local function StatusColors()
    local bf = BF()
    if bf then bf:RefreshAllStatusColors() end
end

local function AppendToggled()
    LayoutFrames()
    StatusColors()
end

-- The status overlay caches its last decision per frame; clearing
-- _healthState forces the re-eval, as the Ace setter did.
local function DeadShown()
    ForEachFrame(function(_, f) f._healthState = nil end)
    StatusColors()
end

local function LevelTextUpdate()
    local bf = BF()
    if bf and bf.indicators and bf.indicators.levelText then
        bf.indicators.levelText:UpdateAllFrames()
    end
end

local function LevelColorToggled()
    LayoutFrames()
    LevelTextUpdate()
end

local function VehicleUpdate()
    ForEachFrame(function(bf, f)
        if bf.UpdateVehicle then bf:UpdateVehicle(f) end
    end)
end

-- Raid group labels, debounced under the SAME key the Ace page uses.
local function GroupLabels()
    local bf = BF()
    if not bf then return end
    bf:DebounceOption("textGroupLabels", function() bf:UpdateGroupLabels() end)
end

-- ── Cross-section and cross-scope predicates ───────────────────

-- Group labels only mean anything under Strict Group Layout, which is a
-- SORTING key -- the same cross-section read the Ace page makes.
local function StrictGroupLayoutOn()
    local bf = BF()
    if not bf then return false end
    local sp = bf:GetSectionProfile("sorting", bf:GetModifyingProfile())
    return (sp and sp.strictGroupLayout) and true or false
end

local function StrictDisabled()
    return InCombatLockdown() or not StrictGroupLayoutOn()
end

-- Raid Group Labels only apply to raid flats. When the LABELS subtab's own
-- per-Layout toggle is ON and the user is modifying a party flat, the Ace
-- page hides the whole sub-tab; a route cannot hide, so here the same
-- predicate hides every field on the page instead (the scope strip stays,
-- because the Modifying dropdown is the way back out).
local function HideLabelsForParty()
    local bf = BF()
    if not bf then return false end
    if not bf:IsPerLayoutSectionSubtab("text", "labels") then return false end
    local flat = bf:GetModifyingProfile()
    return flat and flat.type == "party" or false
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Text carries SIX per-Layout toggles, one per subtab (text_names through
-- text_vehicle), so the strip belongs to the subtab rather than the
-- section -- and Copy to moves that subtab's keys and no others, which is
-- what stops copying the Names settings onto the raid Layout quietly
-- overwriting its Status Text.

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

    local keys = bf.SECTION_SUBTAB_KEYS and bf.SECTION_SUBTAB_KEYS.text
    keys = keys and keys[subtabId]
    if not keys then return end

    local srcSection = rawget(src, "text")
    if type(srcSection) ~= "table" then srcSection = bf.rpDB.profile.text end
    if type(srcSection) ~= "table" then return end

    if type(rawget(dst, "text")) ~= "table" then
        dst.text = {}
        -- A flat's section table falls THROUGH to the global for anything
        -- it does not hold. A table created without that wiring answers nil
        -- for every key this copy does not carry.
        if bf.WireSectionFallback then bf:WireSectionFallback(dst, "text") end
    end
    local dstSection = rawget(dst, "text")

    for _, k in ipairs(keys) do
        local v = srcSection[k]
        if v ~= nil then
            dstSection[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    if bf._InvalidateSectionViews then bf:_InvalidateSectionViews("text") end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

local function TogKey(subtabId)
    local bf = BF()
    local m  = bf and bf.SECTION_SUBTAB_TOGGLE and bf.SECTION_SUBTAB_TOGGLE.text
    return m and m[subtabId]
end

local function NotPerLayout(subtabId)
    return function()
        local bf = BF()
        return not (bf and bf:IsPerLayoutSectionSubtab("text", subtabId))
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
          id = TogKey(subtabId) or ("text_" .. subtabId), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give " .. label .. " its own "
              .. "settings per Layout -- the other Text subtabs keep "
              .. "their own toggles.",
          disabled = "combat",
          get = function()
              local bf = BF()
              return bf and bf:IsPerLayoutSectionSubtab("text", subtabId)
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
              .. "Text is left alone.",
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

-- ── Option lists ───────────────────────────────────────────────

-- LSM font names, resolved every time the menu opens, so media registered
-- after the panel is built still appears. LSM:List returns the names
-- already sorted -- the same set of names the Ace LSM30_Font picker
-- offered (BF:LSMFontValues keys), each carrying its `font` so the
-- dropdown draws every name in its own face.
local function FontOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            -- `font` is the preview: the dropdown draws the row -- and the
            -- control, once picked -- in the face it names, which is what
            -- the Ace font picker did and the whole point of choosing one
            -- by eye rather than by name.
            out[#out + 1] = { value = name, text = name,
                              font = LSM:Fetch("font", name) }
        end
    end
    return out
end

-- The Ace `values` tables had no `sorting`, so AceConfigDialog showed them
-- sorted by stored key -- the order kept here.
local FONT_BORDER_OPTIONS = {
    { value = "",                          text = "None (Default)" },
    { value = "MONOCHROME",                text = "Monochrome" },
    { value = "OUTLINE",                   text = "Outline" },
    { value = "OUTLINE, MONOCHROME",       text = "Outline + Monochrome" },
    { value = "THICKOUTLINE",              text = "Thick Outline" },
    { value = "THICKOUTLINE, MONOCHROME",  text = "Thick Outline + Monochrome" },
}

-- The status-text variant labels the empty value plain "None" -- the one
-- Ace list that differs, kept verbatim.
local STATUS_FONT_BORDER_OPTIONS = {
    { value = "",                          text = "None" },
    { value = "MONOCHROME",                text = "Monochrome" },
    { value = "OUTLINE",                   text = "Outline" },
    { value = "OUTLINE, MONOCHROME",       text = "Outline + Monochrome" },
    { value = "THICKOUTLINE",              text = "Thick Outline" },
    { value = "THICKOUTLINE, MONOCHROME",  text = "Thick Outline + Monochrome" },
}

local HEALTH_FORMAT_OPTIONS = {
    { value = "current", text = "Current" },
    { value = "deficit", text = "Deficit" },
    { value = "percent", text = "Percent" },
}

-- How the status label is combined with the unit name. The labels follow
-- statusBeforeName, exactly as the Ace `values` function did; the order is
-- the stored-key order the Ace dialog showed.
local function SeparatorOptions()
    local before = TPv("statusBeforeName")
    if before then
        return {
            { value = "BRACKET",            text = "[Status] Name" },
            { value = "BRACKET_NOSPACE",    text = "[Status]Name" },
            { value = "NAME_COMMA",         text = "Status, Name" },
            { value = "NAME_COMMA_NOSPACE", text = "Status,Name" },
            { value = "NAME_DASH_STATUS",   text = "Status - Name" },
            { value = "NAME_NODASH",        text = "Status-Name" },
            { value = "PAREN",              text = "(Status) Name" },
            { value = "PAREN_NOSPACE",      text = "(Status)Name" },
        }
    end
    return {
        { value = "BRACKET",            text = "Name [Status]" },
        { value = "BRACKET_NOSPACE",    text = "Name[Status]" },
        { value = "NAME_COMMA",         text = "Name, Status" },
        { value = "NAME_COMMA_NOSPACE", text = "Name,Status" },
        { value = "NAME_DASH_STATUS",   text = "Name - Status" },
        { value = "NAME_NODASH",        text = "Name-Status" },
        { value = "PAREN",              text = "Name (Status)" },
        { value = "PAREN_NOSPACE",      text = "Name(Status)" },
    }
end

-- ── Field shorthands ───────────────────────────────────────────

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

local function Dd(bind, label, options, effect, opts)
    local f = { control = "dropdown", label = label, bind = bind,
                options = options, onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- The anchor pad and its two offsets, as one field over three bindings.
-- Every position cluster in this section runs on a -50..50 range.
local function Pos(binds, label, effect, opts)
    local f = { control = "anchor", label = label,
                binds = binds, min = -50, max = 50,
                onChange = effect, disabled = "combat" }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- A color stored {r,g,b[,a]} keyed, shown by a control that speaks
-- arrays. The set builds a FRESH keyed table and routes it through ROOT --
-- exactly what the Ace setters' WriteSectionKey calls did. `fallback` is
-- the Ace getter's own fallback table, kept verbatim.
local function Color(key, label, alpha, fallback, effect, opts)
    local d  = Defaults()
    local dc = d and d[key]
    local default
    if dc then
        if alpha then default = { dc.r, dc.g, dc.b, (dc.a ~= nil) and dc.a or 1 }
        else default = { dc.r, dc.g, dc.b } end
    end
    local f = {
        control = "color", label = label, id = key,
        alpha = alpha or nil, default = default,
        onChange = effect, disabled = "combat",
        get = function()
            local tp = GetT()
            local c = (tp and tp[key]) or fallback
            if not c then return nil end
            if alpha then return { c.r, c.g, c.b, c.a or 1 } end
            return { c.r, c.g, c.b }
        end,
        set = function(_, _, v)
            if InCombatLockdown() then return end
            if alpha then
                ROOT[key] = { r = v[1], g = v[2], b = v[3], a = v[4] }
            else
                ROOT[key] = { r = v[1], g = v[2], b = v[3] }
            end
        end,
    }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end

-- The colors whose Ace setters MUTATED the stored table in place rather
-- than replacing it (deadColor, offlineColor, groupLabelColor). The Ace
-- side mutates the table the MERGED VIEW answers with, which the section
-- contract forbids writing; migrated to SectionKeyTable -- the router that
-- answers with the table to mutate, never the view, and materialises the
-- per-flat copy on demand. Same observable result today, routed correctly.
local function ColorInPlace(key, label, fallback, effect, opts)
    local f = Color(key, label, false, fallback, effect, opts)
    f.set = function(_, _, v)
        if InCombatLockdown() then return end
        local bf = BF()
        local c = bf and bf:SectionKeyTable("text", key)
        if c then c.r, c.g, c.b = v[1], v[2], v[3] end
    end
    return f
end

-- A gate in the card HEADER, and the card collapses when it is off -- the
-- Ace page's `hidden` predicate made visible. A gate cannot bind (it is a
-- group's declaration, not a field's), so the routing and the effect are
-- written out here. `id` and `default` are what make it reset with the
-- rest of its card from the header's own menu.
local function Gate(key, tooltip, effect, desc)
    local d = Defaults()
    return {
        id      = key,
        default = d and d[key],
        tooltip = tooltip,
        desc    = desc,
        get     = function() return TPv(key) end,
        set     = function(_, _, v)
            if InCombatLockdown() then return end
            ROOT[key] = v
            if effect then effect() end
        end,
    }
end

-- ── The six pages ──────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list that
-- builds the pages: the ids ARE the subtab ids in BF.SECTION_SUBTABS.text,
-- so the per-Layout toggles line up by construction rather than by a table
-- somebody has to keep in step. The order is the Ace tab order (names 1,
-- healthText 2, statusText 2.5, levelText 2.7, labels 3, vehicle 4).
BuzzardFramesOptions.TEXT_SUBTABS = {
    { id = "names",      title = "Names" },
    { id = "healthText", title = "Health Text" },
    { id = "statusText", title = "Status Text" },
    { id = "levelText",  title = "Level Text" },
    { id = "labels",     title = "Raid Group Labels" },
    { id = "vehicle",    title = "Vehicle" },
}

local PAGES = {}

-- Names. Ace order: nameHeader (folded into the tab title), namePosition
-- (3), nameFontGroup (4), nameColorsGroup (4.5), capitalizeNamesGroup
-- (5.3), cyrillicSpacer (a pure spacer, dropped), abbreviateNamesGroup
-- (5.5), cyrillicHeader (5.5, after by the alphabetical tie-break) with
-- the two Cyrillic toggles under it.
function PAGES.names()
    return {
        -- The Ace namePosition inline group (point/x/y selects).
        { title = "Name Position", preset = "form", fields = {
            Pos({ point = "namePosition.point",
                  x     = "namePosition.x",
                  y     = "namePosition.y" },
                "Location", NameLayoutAndFont),
        }},
        -- nameFontGroup: the Ace page hides Font/Border/Size unless
        -- adjustNameFont -- the gate collapse.
        { title = "Name Font", preset = "form",
          toggle = Gate("adjustNameFont", "Adjust Name Font", LayoutFrames,
              "Enable custom font, border style, and size for name text"),
          fields = {
            Dd("nameFont", "Font", FontOptions, RefreshNameFont,
               { desc = "Choose a font for unit names" }),
            Dd("nameFontBorder", "Font Border", FONT_BORDER_OPTIONS, RefreshNameFont,
               { desc = "Choose an outline/border style for name text" }),
            Sl("nameFontSize", "Font Size", 6, 30, RefreshNameFont),
        }},
        -- nameColorsGroup: classColorNames and nameColor hidden unless
        -- adjustNameColors -- the gate collapse.
        { title = "Name Colors", preset = "form",
          toggle = Gate("adjustNameColors", "Adjust Name Colors", NamesRefresh),
          fields = {
            Sw("classColorNames", "Class Color Names", NamesRefresh),
            Color("nameColor", "Name Color", true, { r = 1, g = 1, b = 1 },
                NamesRefreshPreview,
                { desc = "Default name color. Overridden by Class Color "
                      .. "Names when enabled.",
                  hidden = function() return TPv("classColorNames") end }),
        }},
        -- capitalizeNamesGroup.
        { title = "Capitalize Names", preset = "form", fields = {
            Sw("capitalizeNames", "Capitalize Names", NamesRefresh,
               { desc = "Convert unit names to uppercase." }),
        }},
        -- abbreviateNamesGroup: maxNameChars hidden unless abbreviateNames
        -- -- the gate collapse. The gate's tooltip carries the Ace toggle's
        -- own name.
        { title = "Abbreviate Names", preset = "form",
          toggle = Gate("abbreviateNames", "Abbreviate Long Names", NamesRefresh),
          fields = {
            Sl("maxNameChars", "Max Name Length", 3, 20, NamesRefresh),
        }},
        -- cyrillicHeader and the two loose toggles under it become a card.
        { title = "Cyrillic Names", preset = "form", fields = {
            Sw("transliterateCyrillicNames", "Transliterate Cyrillic Names",
               NamesRefreshPreview,
               { wide = true,
                 desc = "Convert Cyrillic characters in unit names to Latin "
                     .. "equivalents (e.g. \"\208\159\209\128\208\184\208\178\208\181\209\130\" \226\134\146 \"Privet\"). When "
                     .. "disabled, Cyrillic names use a fallback font that "
                     .. "supports the Cyrillic alphabet." }),
            -- A GLOBAL debug flag (BF.db.global), not a text-section key --
            -- shared across profiles and Layouts, so it is the one field on
            -- this page that does not route through ROOT.
            { control = "switch", label = "Test Cyrillic Names",
              id = "testCyrillicNames", default = false,
              wide = true, disabled = "combat",
              desc = "Replace all unit names with a Cyrillic test string "
                  .. "(\"\208\159\209\128\208\184\208\178\208\181\209\130\") so you can verify font fallback and "
                  .. "transliteration visually.",
              hidden = function()
                  local bf = BF()
                  return not (bf and bf.db.global.enableExperimentalOptions)
              end,
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testCyrillicNames
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testCyrillicNames = v
                  NamesRefreshPreview()
              end },
        }},
    }
end

-- Health Text. Ace order: healthTextHeader, showHealthText (2), format
-- (3), pctSymbol (3.5), healthTextPosition (4), healthFontGroup (5),
-- healthTextColorGroup (7). The show toggle gates the first card (format
-- and % symbol were hidden unless it); the Position, Font and Color cards
-- were whole Ace groups hidden unless showHealthText -- the library has no
-- group-level `hidden`, so the predicate rides every field in them instead
-- and the card headers stay visible (see the notes).
function PAGES.healthText()
    local noShow = function() return not TPv("showHealthText") end
    local noFont = function()
        return not (TPv("showHealthText") and TPv("adjustHealthFont"))
    end
    local noColor = function()
        return not (TPv("showHealthText") and TPv("adjustHealthTextColor"))
    end
    local showDisabled = function()
        return InCombatLockdown() or not TPv("showHealthText")
    end
    return {
        { title = "Health Text", preset = "form",
          toggle = Gate("showHealthText", "Show Health Text", HealthTextUpdate),
          fields = {
            Dd("healthTextFormat", "Health Text Format",
               HEALTH_FORMAT_OPTIONS, HealthTextUpdate),
            Sw("healthTextPctSymbol", "Show % Symbol", HealthTextUpdate,
               { hidden = function()
                     return TPv("healthTextFormat") ~= "percent"
                 end }),
        }},
        -- healthTextPosition: three FLAT keys, so the pad binds them by
        -- name (the Ace pos/x/y widgets).
        { title = "Health Text Position", preset = "form", fields = {
            Pos({ point = "healthTextPosition",
                  x     = "healthTextX",
                  y     = "healthTextY" },
                "Location", LayoutFrames,
                { hidden = noShow, disabled = showDisabled }),
        }},
        -- healthFontGroup.
        { title = "Health Text Font", preset = "form", fields = {
            Sw("adjustHealthFont", "Adjust Health Font", LayoutFrames,
               { desc = "Enable custom font, border style, and size for health text",
                 hidden = noShow }),
            Dd("healthFont", "Font", FontOptions, LayoutFrames,
               { desc = "Choose a font for health text", hidden = noFont }),
            Dd("healthFontBorder", "Font Border", FONT_BORDER_OPTIONS, LayoutFrames,
               { desc = "Choose an outline/border style for health text",
                 hidden = noFont }),
            Sl("healthFontSize", "Font Size", 6, 30, LayoutFrames,
               { hidden = noFont }),
        }},
        -- healthTextColorGroup.
        { title = "Health Text Color", preset = "form", fields = {
            Sw("adjustHealthTextColor", "Adjust Health Text Color",
               HealthTextColorToggled, { hidden = noShow }),
            Sw("classColorHealthText", "Use Class Colors",
               HealthTextClassColor, { hidden = noColor }),
            Color("healthTextColor", "Health Text Color", true,
                { r = 0.5, g = 0.5, b = 0.5 }, HealthTextColorPicked,
                { hidden = function()
                      return noColor() or TPv("classColorHealthText")
                  end }),
        }},
    }
end

-- Status Text. Ace order: statusTextHeader, statusTextDesc (1.5),
-- statusTextPosition (2), statusAbbreviateNamesGroup (2.5),
-- statusFontGroup (3), capitalizeStatusGroup (4.5), statusColorSpacer
-- (dropped), statusColorHeader (5.1 -- the Dead/Offline/AFK cards carry
-- their own titles), deadColorGroup (5.2), offlineColorGroup (7),
-- afkColorGroup (7.5).
function PAGES.statusText()
    local append   = function() return TPv("appendStatusTextToNames") end
    local noAppend = function() return not TPv("appendStatusTextToNames") end
    return {
        { preset = "bare", fields = {
            -- statusTextDesc.
            { control = "note", wide = true,
              text = "Status Labels = Dead, Ghost, Offline, AFK" },
        }},
        -- statusTextPosition: the Ace pos/x/y selects become one pad; the
        -- append toggle and its two dependents keep their places after it.
        { title = "Status Text Position", preset = "form", fields = {
            Pos({ point = "statusTextPosition",
                  x     = "statusTextX",
                  y     = "statusTextY" },
                "Location", LayoutFrames, { hidden = append }),
            Sw("appendStatusTextToNames", "Append Status Text to Names",
               AppendToggled,
               { desc = "When enabled, status labels (Dead, Offline) are "
                     .. "appended directly to the unit name instead of being "
                     .. "shown as a separate overlay text." }),
            Dd("statusAppendSeparator", "Combined Layout", SeparatorOptions,
               StatusColors,
               { desc = "How the status label is combined with the unit name.",
                 hidden = noAppend }),
            Sw("statusBeforeName", "Status Before Name", StatusColors,
               { desc = "Show the status label before the unit name instead of after.",
                 hidden = noAppend }),
        }},
        -- statusAbbreviateNamesGroup: the whole Ace group hides unless
        -- append is on; the predicate rides both fields.
        { title = "Abbreviate Names when appending Status Text",
          preset = "form", fields = {
            Sw("abbreviateStatusNames", "Abbreviate Names", StatusColors,
               { desc = "When enabled, unit names are abbreviated to the max "
                     .. "length when a status label (Dead, Offline, AFK) is "
                     .. "appended to them.",
                 hidden = noAppend }),
            Sl("maxStatusNameChars", "Max Length", 3, 20, StatusColors,
               { hidden = function()
                     return noAppend() or not TPv("abbreviateStatusNames")
                 end }),
        }},
        -- statusFontGroup: hidden WHEN appending (the overlay font is
        -- meaningless while the name text carries the label).
        { title = "Status Text Font", preset = "form", fields = {
            Sw("adjustStatusFont", "Adjust Status Font", LayoutFrames,
               { desc = "Enable custom font, border style, and size for status text",
                 hidden = append }),
            Dd("statusFont", "Font", FontOptions, LayoutFrames,
               { desc = "Choose a font for status text",
                 hidden = function()
                     return append() or not TPv("adjustStatusFont")
                 end }),
            Dd("statusFontBorder", "Font Border", STATUS_FONT_BORDER_OPTIONS,
               LayoutFrames,
               { desc = "Choose an outline/border style for status text. "
                     .. "Note: the outline is automatically removed for "
                     .. "out-of-range dead units regardless of this setting.",
                 hidden = function()
                     return append() or not TPv("adjustStatusFont")
                 end }),
            Sl("statusFontSize", "Font Size", 6, 30, LayoutFrames,
               { hidden = function()
                     return append() or not TPv("adjustStatusFont")
                 end }),
        }},
        -- capitalizeStatusGroup, titled "Additional Options" in Ace.
        { title = "Additional Options", preset = "form", fields = {
            Sw("capitalizeStatusText", "Capitalize Status Text", StatusColors,
               { desc = "Convert status labels (Dead, Offline, AFK) to uppercase." }),
            Sw("applyStatusColorsToNames", "Apply Status Colors to Names",
               StatusColors,
               { desc = "When enabled, the name text color is changed to the "
                     .. "status color (Dead, Offline, AFK) even when status "
                     .. "text is not shown as a separate overlay.",
                 hidden = append }),
        }},
        -- deadColorGroup. The color rows stay reachable while append or
        -- apply-to-names is on even with the show toggle off, so this card
        -- takes no header gate; the Ace hidden predicates ride the fields.
        { title = "Dead Status Text", preset = "form", fields = {
            Sw("showDeadStatus", "Show Dead Text", DeadShown),
            Sw("deadColorUseClassColor", "Use Class Color", StatusColors,
               { desc = "Use the unit's class color for dead status text "
                     .. "instead of a fixed color.",
                 hidden = function()
                     local tp = GetT()
                     return (tp and tp.showDeadStatus == false)
                         and not (tp and tp.appendStatusTextToNames)
                         and not (tp and tp.applyStatusColorsToNames)
                 end }),
            ColorInPlace("deadColor", "Dead Color",
                { r = 0.8, g = 0.1, b = 0.1 }, StatusColors,
                { desc = "Color of the 'Dead' text on dead frames.",
                  hidden = function()
                      local tp = GetT()
                      return ((tp and tp.showDeadStatus == false)
                              and not (tp and tp.appendStatusTextToNames)
                              and not (tp and tp.applyStatusColorsToNames))
                          or (tp and tp.deadColorUseClassColor) and true or false
                  end }),
        }},
        -- offlineColorGroup.
        { title = "Offline Status Text", preset = "form", fields = {
            Sw("showOfflineStatus", "Show Offline Text", StatusColors),
            Sw("abbreviateOffline", "Abbreviate Offline", StatusColors,
               { desc = "Abbreviate \"Offline\" to \"Off\".",
                 hidden = function()
                     local tp = GetT()
                     return (tp and tp.showOfflineStatus == false) and true or false
                 end }),
            Sw("offlineColorUseClassColor", "Use Class Color", StatusColors,
               { desc = "Use the unit's class color for offline status text "
                     .. "instead of a fixed color.",
                 hidden = function()
                     local tp = GetT()
                     return (tp and tp.showOfflineStatus == false)
                         and not (tp and tp.appendStatusTextToNames)
                         and not (tp and tp.applyStatusColorsToNames)
                 end }),
            ColorInPlace("offlineColor", "Offline Color",
                { r = 0.5, g = 0.5, b = 0.5 }, StatusColors,
                { desc = "Color of the 'Offline' text on disconnected frames.",
                  hidden = function()
                      local tp = GetT()
                      return ((tp and tp.showOfflineStatus == false)
                              and not (tp and tp.appendStatusTextToNames)
                              and not (tp and tp.applyStatusColorsToNames))
                          or (tp and tp.offlineColorUseClassColor) and true or false
                  end }),
            Sw("fadeOfflineNameText", "Fade Text", StatusColors,
               { desc = "Fade the name and offline status text of offline "
                     .. "units using the range fade alpha, and apply the "
                     .. "out-of-range color retention to them. Has no effect "
                     .. "if Fade Offline Frames (Health & Power Bars tab) is "
                     .. "also enabled, since the whole frame is already faded." }),
        }},
        -- afkColorGroup. afkColor's Ace setter REPLACED the table through
        -- WriteSectionKey (unlike dead/offline), so it writes fresh here too.
        { title = "AFK Status", preset = "form", fields = {
            Sw("showAFKStatus", "Show AFK Text", StatusColors,
               { desc = "Show 'AFK' on frames for players who are Away From Keyboard." }),
            Sw("afkColorUseClassColor", "Use Class Color", StatusColors,
               { desc = "Use the unit's class color for AFK status text "
                     .. "instead of a fixed color.",
                 hidden = function()
                     local tp = GetT()
                     return not (tp and tp.showAFKStatus)
                         and not (tp and tp.appendStatusTextToNames)
                         and not (tp and tp.applyStatusColorsToNames)
                 end }),
            Color("afkColor", "AFK Color", false,
                { r = 0.8, g = 0.6, b = 0 }, StatusColors,
                { desc = "Color of the 'AFK' text on frames.",
                  hidden = function()
                      local tp = GetT()
                      return (not (tp and tp.showAFKStatus)
                              and not (tp and tp.appendStatusTextToNames)
                              and not (tp and tp.applyStatusColorsToNames))
                          or (tp and tp.afkColorUseClassColor) and true or false
                  end }),
        }},
    }
end

-- Level Text. Ace order: levelTextHeader, showLevelText (2),
-- hideLevelTextAtMaxLevel (2.1), levelTextPosition (4), levelFontGroup
-- (5), levelTextColorGroup (7). Same shape as Health Text: the show
-- toggle gates the first card, the group-level hidden rides the fields of
-- the other three.
function PAGES.levelText()
    local noShow = function() return not TPv("showLevelText") end
    local noFont = function()
        return not (TPv("showLevelText") and TPv("adjustLevelFont"))
    end
    local noColor = function()
        return not (TPv("showLevelText") and TPv("adjustLevelTextColor"))
    end
    local showDisabled = function()
        return InCombatLockdown() or not TPv("showLevelText")
    end
    return {
        { title = "Level Text", preset = "form",
          toggle = Gate("showLevelText", "Show Level Text", LevelTextUpdate),
          fields = {
            Sw("hideLevelTextAtMaxLevel", "Hide at max Level", LevelTextUpdate,
               { desc = "Hide the level text on units that are at maximum level." }),
        }},
        -- levelTextPosition: flat keys (the Ace pos/x/y widgets).
        { title = "Level Text Position", preset = "form", fields = {
            Pos({ point = "levelTextPosition",
                  x     = "levelTextX",
                  y     = "levelTextY" },
                "Location", LayoutFrames,
                { hidden = noShow, disabled = showDisabled }),
        }},
        -- levelFontGroup.
        { title = "Level Text Font", preset = "form", fields = {
            Sw("adjustLevelFont", "Adjust Level Font", LayoutFrames,
               { desc = "Enable custom font, border style, and size for level text",
                 hidden = noShow }),
            Dd("levelFont", "Font", FontOptions, LayoutFrames,
               { desc = "Choose a font for level text", hidden = noFont }),
            Dd("levelFontBorder", "Font Border", FONT_BORDER_OPTIONS, LayoutFrames,
               { desc = "Choose an outline/border style for level text",
                 hidden = noFont }),
            Sl("levelFontSize", "Font Size", 6, 30, LayoutFrames,
               { hidden = noFont }),
        }},
        -- levelTextColorGroup.
        { title = "Level Text Color", preset = "form", fields = {
            Sw("adjustLevelTextColor", "Adjust Level Text Color",
               LevelColorToggled, { hidden = noShow }),
            Sw("classColorLevelText", "Use Class Colors", LevelTextUpdate,
               { hidden = noColor }),
            Color("levelTextColor", "Level Text Color", false,
                { r = 1, g = 0.82, b = 0 }, LevelColorToggled,
                { hidden = function()
                      return noColor() or TPv("classColorLevelText")
                  end }),
        }},
    }
end

-- Raid Group Labels. Ace order: groupLabelsHeader, showGroupLabels (2),
-- showGroupLabelsNote (2.5), groupLabelYOffset (2.55), groupLabelColor
-- (2.6), groupLabelNumberOnly (2.65), groupLabelFontGroup (3.7). In Ace
-- the whole SUB-TAB hides when the labels subtab is per-Layout and a party
-- flat is being modified; a route cannot hide, so every field hides on the
-- same predicate and an added note says why (the strip stays -- its
-- Modifying dropdown is how you leave the party flat).
function PAGES.labels()
    local noShow = function()
        return HideLabelsForParty() or not TPv("showGroupLabels")
    end
    return {
        { preset = "bare", fields = {
            -- ADDED: the panel's stand-in for the hidden Ace sub-tab.
            { control = "note", wide = true,
              hidden = function() return not HideLabelsForParty() end,
              text = "Raid Group Labels apply to raid Layouts only, and "
                  .. "this subtab is configured per Layout. Switch the "
                  .. "Modifying dropdown above to a raid Layout to edit them." },
        }},
        { title = "Raid Group Labels", preset = "form", fields = {
            Sw("showGroupLabels", "Show Group Labels", GroupLabels,
               { desc = "Display a label above each raid group column "
                     .. "(e.g. \"Group 1\", \"Group 2\"). Only visible when "
                     .. "sorting by Group.",
                 hidden = HideLabelsForParty,
                 disabled = StrictDisabled }),
            -- showGroupLabelsNote: the Ace dynamic description.
            { control = "note", wide = true, hidden = noShow,
              text = function()
                  if not StrictGroupLayoutOn() then
                      return "|cffff8800Requires Strict Group Layout to be "
                          .. "enabled (Frame Configuration > Sorting & "
                          .. "Grow Direction).|r"
                  end
                  return ""
              end },
            Sl("groupLabelYOffset", "Offset", -20, 20, GroupLabels,
               { desc = "Gap between the label and the nearest frame edge. "
                     .. "Positive values push the label further away from "
                     .. "the frames.",
                 hidden = noShow, disabled = StrictDisabled }),
            ColorInPlace("groupLabelColor", "Label Color",
                { r = 1, g = 1, b = 1 }, GroupLabels,
                { hidden = noShow, disabled = StrictDisabled }),
            Sw("groupLabelNumberOnly", "Show Number Only", GroupLabels,
               { desc = "Display only the group number (e.g. \"1\") instead "
                     .. "of the full label (e.g. \"Group 1\").",
                 hidden = noShow, disabled = StrictDisabled }),
        }},
        -- groupLabelFontGroup: the Ace group hides unless showGroupLabels
        -- AND Strict Group Layout; its inner fields hide again unless
        -- adjustGroupLabelFont. The combined predicates ride the fields.
        { title = "Label Font", preset = "form", fields = {
            Sw("adjustGroupLabelFont", "Adjust Label Font", GroupLabels,
               { desc = "Enable custom font and border style for raid group labels",
                 hidden = function()
                     return noShow() or not StrictGroupLayoutOn()
                 end }),
            Dd("groupLabelFont", "Font", FontOptions, GroupLabels,
               { desc = "Choose a font for raid group labels",
                 hidden = function()
                     return noShow() or not StrictGroupLayoutOn()
                         or not TPv("adjustGroupLabelFont")
                 end }),
            Dd("groupLabelFontBorder", "Font Border", FONT_BORDER_OPTIONS,
               GroupLabels,
               { desc = "Choose an outline/border style for raid group labels",
                 hidden = function()
                     return noShow() or not StrictGroupLayoutOn()
                         or not TPv("adjustGroupLabelFont")
                 end }),
            Sl("groupLabelFontSize", "Font Size", 6, 30, GroupLabels,
               { hidden = function()
                     return noShow() or not StrictGroupLayoutOn()
                         or not TPv("adjustGroupLabelFont")
                 end }),
        }},
    }
end

-- Vehicle. Ace order: vehicleNameHeader, showVehicleName (2),
-- vehicleNamePosition (3), vehicleFontGroup (5.5),
-- abbreviateVehicleNamesGroup (6). The three groups after the toggle are
-- whole Ace groups hidden unless showVehicleName; the predicate rides
-- their fields.
function PAGES.vehicle()
    local noShow = function() return not TPv("showVehicleName") end
    local showDisabled = function()
        return InCombatLockdown() or not TPv("showVehicleName")
    end
    return {
        { title = "Vehicle Name Text", preset = "form", fields = {
            Sw("showVehicleName", "Show Vehicle Name", VehicleUpdate,
               { desc = "Show the vehicle name on the frame when a unit is "
                     .. "in a vehicle." }),
        }},
        -- vehicleNamePosition: a nested table, so the pad binds through
        -- the SubTable wrapper (the Ace point/x/y selects).
        { title = "Vehicle Name Position", preset = "form", fields = {
            Pos({ point = "vehicleNamePosition.point",
                  x     = "vehicleNamePosition.x",
                  y     = "vehicleNamePosition.y" },
                "Location", LayoutFrames,
                { hidden = noShow, disabled = showDisabled }),
        }},
        -- vehicleFontGroup.
        { title = "Vehicle Name Font", preset = "form", fields = {
            Sw("adjustVehicleFont", "Adjust Vehicle Font", LayoutFrames,
               { desc = "Enable custom font, border style, and size for "
                     .. "vehicle name text",
                 hidden = noShow }),
            Dd("vehicleFont", "Font", FontOptions, LayoutFrames,
               { desc = "Choose a font for vehicle name text",
                 hidden = function()
                     return noShow() or not TPv("adjustVehicleFont")
                 end }),
            Dd("vehicleFontBorder", "Font Border", FONT_BORDER_OPTIONS,
               LayoutFrames,
               { desc = "Choose an outline/border style for vehicle name text",
                 hidden = function()
                     return noShow() or not TPv("adjustVehicleFont")
                 end }),
            Sl("vehicleFontSize", "Font Size", 6, 30, LayoutFrames,
               { hidden = function()
                     return noShow() or not TPv("adjustVehicleFont")
                 end }),
        }},
        -- abbreviateVehicleNamesGroup. maxVehicleNameChars has NO side
        -- effect in Ace -- the next vehicle update reads it -- so it
        -- declares no onChange here either.
        { title = "Abbreviate Vehicle Names", preset = "form", fields = {
            Sw("abbreviateVehicleNames", "Abbreviate Long Vehicle Names",
               VehicleUpdate, { hidden = noShow }),
            Sl("maxVehicleNameChars", "Max Vehicle Name Length", 3, 20, nil,
               { hidden = function()
                     return noShow() or not TPv("abbreviateVehicleNames")
                 end }),
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:TextPage(subtabId, label)
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
