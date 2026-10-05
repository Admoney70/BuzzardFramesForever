-- ============================================================
-- BuzzardFramesOptions: Pages_AuraShared.lua
-- The storage routing, the refresh dispatch and the scope strip that
-- every aura page shares.
--
-- WHY THIS FILE EXISTS. The Ace aura options are one 5,000-line builder
-- called twice -- once for Buffs, once for Debuffs -- and everything
-- that makes them work lives in helpers passed down from Options.lua as
-- `deps`: getAuras_shared, setAuras_shared, setAurasBigDef_shared,
-- getAurasProfile_shared, and the two Copy dropdown builders. Splitting
-- that builder into one page file per section means those helpers have
-- nowhere to live unless they get a home of their own. This is that
-- home. Three page files read from it; none of them re-implements the
-- routing, which is the whole point -- an aura key routed two different
-- ways by two pages is a setting that reads from one place and writes to
-- another.
--
-- STORAGE DID NOT MOVE, and must not. Every key still lives at
-- rpDB.profile.auras.<subcat>[key] (per-Layout OFF) or
-- flat.auras.<subcat>[key] (ON). What decides which is the key's own
-- toggle -- its SCOPE's toggle if it has one (the Debuff Preset/Filter
-- keys), else its sub-category's -- and BF answers that question, not
-- this file: BF:AurasKeyToggle and BF:IsPerLayoutAurasKey. Reproducing
-- that decision here would be a second answer to a question that already
-- has one.
--
-- NOTHING AT FILE SCOPE TOUCHES THE OTHER ADDON. Same rule as every
-- other page file: BF() is read inside the functions, at the moment the
-- panel is used.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- ── The modifying flat ─────────────────────────────────────────
--
-- The panel's copy of getAurasProfile_shared's flat resolution: the
-- Layout being modified, falling back to the party flat exactly as the
-- Ace helper does. Called with no sub-category it answers "which flat",
-- which is the question the Copy dropdown and the container scope ask.

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile
            and bf.rpDB.profile.layouts
            and bf.rpDB.profile.layouts.flatLayouts) or {}
end
BuzzardFramesOptions.AuraFlatLayouts = FlatLayouts

local function ModifyingFlat()
    local bf = BF()
    -- The one question the proxy cannot answer by method: `_modifyingFlat`
    -- is a FIELD, and its value is an ID looked up in the Raid/Party
    -- flatLayouts -- where a Custom Frame Group's flat does not appear at
    -- all. So the scope is asked outright, and this one branch routes
    -- SubcatView, WriteAuraKey and AuraRoot for all three aura pages.
    if bf and bf.BFOScopeFlat then return bf:BFOScopeFlat() end
    local fl = FlatLayouts()
    local mf = bf and bf._modifyingFlat
    if mf and fl[mf] then return fl[mf] end
    -- Post-migration flat_party always exists; the loop is the same
    -- last-resort the Ace helper's fallback chain ends in.
    if fl.flat_party then return fl.flat_party end
    for _, flat in pairs(fl) do
        if type(flat) == "table" then return flat end
    end
    return nil
end
BuzzardFramesOptions.AuraModifyingFlat = ModifyingFlat

local function CurrentFlatID()
    local bf = BF()
    local fl = FlatLayouts()
    local cur = bf and bf._modifyingFlat
    if cur and fl[cur] then return cur end
    if fl.flat_party then return "flat_party" end
    for id in pairs(fl) do return id end
    return nil
end

-- The resolved READ view of one sub-category: BF answers, including the
-- merged view a scoped sub-category serves when its two toggles
-- disagree. NEVER written to -- a merged view is a copy, and a write to
-- it is a write that disappears at the next invalidation.
local function SubcatView(subcat)
    local bf = BF()
    if not (bf and bf.GetAurasSubcatProfile) then return nil end
    return bf:GetAurasSubcatProfile(subcat, ModifyingFlat())
end
BuzzardFramesOptions.AuraSubcatView = SubcatView

-- ── The write ──────────────────────────────────────────────────
--
-- writeAurasValue from Options.lua, key for key. The per-Layout question
-- is asked PER KEY (BF:IsPerLayoutAurasKey), because a scoped key on the
-- Debuff Preset/Filter subtab follows a different toggle from its
-- neighbors on the Debuffs tab, and asking the coarse sub-category
-- question would route half of them wrong.
--
-- The invalidation that follows is not decoration: the aura size cache
-- and the flat caches are read by the render path, so a write that does
-- not mark them stale is a setting that takes effect on the next reload.
local function WriteAuraKey(key, val)
    local bf = BF()
    if not bf then return nil end
    local subcat = bf.AURAS_SUBCATEGORY_OF and bf.AURAS_SUBCATEGORY_OF[key]
    if subcat then
        local togKey = bf:AurasKeyToggle(key) or "auras_buffs"
        if bf:IsPerLayoutAurasKey(key) then
            local flat = ModifyingFlat()
            local sub  = flat and bf:GetOrCreateAurasSubCategory(flat, subcat)
            if sub then sub[key] = val end
            bf:InvalidateFlatAuraCache(flat)
        else
            local gp = bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.auras
            if gp then
                gp[subcat] = gp[subcat] or {}
                gp[subcat][key] = val
            end
            bf:InvalidateGlobalSectionFlatCaches(togKey)
        end
        -- A scoped sub-category may be serving merged views; they copy
        -- values at build time, so any write makes them stale. A no-op
        -- for an unscoped sub-category.
        bf:InvalidateAurasSubcatViews(subcat)
    else
        -- The legacy flat-root path. Defensive: no current widget lands
        -- here, and the coarse "auras" alias is the right question in
        -- this one place, because a flat-root key belongs to no
        -- sub-category.
        local flat = ModifyingFlat()
        if flat then flat[key] = val end
        if bf:IsPerLayoutSection("auras") then
            bf:InvalidateFlatAuraCache(flat)
        else
            bf:InvalidateGlobalSectionFlatCaches("auras_buffs")
        end
    end
    return subcat
end

-- ── The refresh ────────────────────────────────────────────────
--
-- One scoped refresh per sub-category, as SUBCAT_REFRESH in Options.lua.
-- The broad RefreshAllAuras is the fallback for a key with no routable
-- sub-category, not the normal path: it walks every frame and every
-- indicator, and a slider that fires it per drag tick is what the scoped
-- refreshes exist to avoid.
local SUBCAT_REFRESH = {
    buffs           = "RefreshBuffsOnly",
    debuffs         = "RefreshDebuffsOnly",
    bigDef          = "RefreshBigDefOnly",
    dispelIndicator = "RefreshDispelOnly",
}

-- The position caches an anchor / offset / grow / per-row / size change
-- invalidates. Lifted verbatim from setAuras_shared: an icon holds the
-- index it was last laid out at, and a geometry change that leaves it
-- set re-uses a stale slot.
local function ClearIconIndexCache(key)
    local bf = BF()
    if not bf then return end
    if not (key:find("Anchor") or key:find("Offset") or key:find("GrowDir")
            or key:find("PerRow") or key:find("Size")) then
        return
    end
    for _, frame in next, bf.registeredFrames or {} do
        if frame.buffFrames then
            for _, icon in ipairs(frame.buffFrames) do icon.SF_LastIndex = nil end
        end
        if frame.debuffFrames then
            for _, icon in ipairs(frame.debuffFrames) do icon.SF_LastIndex = nil end
        end
    end
end

-- The refresh half of setAuras_shared.
--
-- The Ace file hand-rolled a mouse-up gate here (v76: no work at all
-- while the button is held, because a 0.15s trailing timer still ran the
-- full frame walk mid-drag whenever the user paused). The library owns
-- that scheduler now -- `refresh = "mouseup"` on a field is the same
-- ruling, expressed once -- so this function is the WORK and the field
-- declares WHEN. Sliders and colors on the aura pages declare
-- "mouseup"; everything else takes the default.
local function RunAuraRefresh(subcat, bigDef)
    local bf = BF()
    if not bf then return end
    bf:InvalidateRaidProfileCache()
    local fnName = subcat and SUBCAT_REFRESH[subcat]
    if not (fnName and bf[fnName]) then
        fnName = bigDef and "RefreshBigDef" or "RefreshAllAuras"
    end
    if bf[fnName] then bf[fnName](bf) end
    if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
end
BuzzardFramesOptions.RunAuraRefresh = RunAuraRefresh

-- ── The bind-through root, per sub-category ────────────────────
--
-- The library resolves a `bind` by walking a dotted path into the page's
-- db. Auras has no such table: what a key reads from and what it writes
-- to are decided per key. So each sub-category hands the library a table
-- shaped like the one it wants and routed like the one BuzzardFrames
-- has -- reads fall through to the resolved view, writes go through
-- WriteAuraKey.
--
-- Binding rather than get/set is what makes the library's right-click
-- "Undo change" and "Reset to default" work on every field without any
-- of them declaring anything: both are keyed on the bind path.
--
-- A key whose value is a TABLE (a color, a position) answers with a
-- second wrapper reading from the view and writing the whole table back
-- through WriteAuraKey, because there is no per-field mutation entry
-- point for auras the way SectionKeyTable is one for the flat sections.
local rootCache, subCache = {}, {}

local function AuraSubTable(subcat, key)
    local ck = subcat .. "\001" .. key
    local w = subCache[ck]
    if w then return w end
    w = setmetatable({}, {
        __index = function(_, k)
            local view = SubcatView(subcat)
            local t = view and view[key]
            return t and t[k]
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            local view = SubcatView(subcat)
            local cur  = view and view[key]
            -- Copied before mutation: `cur` may BE the global table (the
            -- per-Layout-off case) or a merged view (a scoped
            -- sub-category), and mutating either in place writes
            -- somewhere the next read will not look.
            local out = {}
            if type(cur) == "table" then
                for ck2, cv in pairs(cur) do out[ck2] = cv end
            end
            out[k] = v
            WriteAuraKey(key, out)
        end,
    })
    subCache[ck] = w
    return w
end

-- The page's `db`. One per sub-category, memoised, because the library
-- compares db identity across renders.
function BuzzardFramesOptions:AuraRoot(subcat)
    local r = rootCache[subcat]
    if r then return r end
    r = setmetatable({}, {
        __index = function(_, k)
            local view = SubcatView(subcat)
            local v = view and view[k]
            if type(v) == "table" then return AuraSubTable(subcat, k) end
            return v
        end,
        __newindex = function(_, k, v)
            if InCombatLockdown() then return end
            WriteAuraKey(k, v)
        end,
    })
    rootCache[subcat] = r
    return r
end

-- What a key resets TO. BuzzardFrames' own defaults table is the single
-- source, and it is the same SHAPE as the storage, so the library
-- resolves a bind path straight into it.
function BuzzardFramesOptions:AuraDefaults(subcat)
    return function()
        local bf = BF()
        local d  = bf and bf.raidPartyFrameDefaults
        d = d and d.profile and d.profile.auras
        return d and d[subcat]
    end
end

-- ── Field shorthands ───────────────────────────────────────────
--
-- Every aura field binds into its sub-category's root and names the
-- refresh its sub-category needs. These say that once instead of at
-- every one of the several hundred call sites.

-- The onChange for one sub-category. `bigDef` picks RefreshBigDef as the
-- fallback rather than RefreshAllAuras, which is what setAurasBigDef_-
-- shared did for the Big Defensive widgets.
function BuzzardFramesOptions:AuraEffect(subcat, bigDef)
    return function(node)
        local key = node and node.bind
        if key then ClearIconIndexCache(key) end
        RunAuraRefresh(subcat, bigDef)
    end
end

-- ── The scope strip ────────────────────────────────────────────
--
-- Every aura SUBTAB carries its own per-Layout toggle -- the toggles are
-- per sub-category, and a scoped subtab (Debuff Preset/Filter) has one
-- of its own again -- so the strip belongs to the subtab rather than to
-- the section, exactly as the Ace page emitted it inside each subtab
-- rather than at the section root.
--
-- `scopeToggle` names a scope from BF.AURAS_SUBCAT_SCOPES for a scoped
-- subtab; without it the strip is the sub-category's own.

-- Party flats first, then raid, each alphabetical by name; the ACTIVE
-- Layout is tinted green, which is how the Ace dropdown has always shown
-- the difference between "active" and "being edited".
-- A page rebuild on the next frame. A control on the scope strip that
-- changes which flat the page reads is structural -- RefreshPage re-reads
-- live fields on the page table it already has and never re-runs the
-- builder; only Invalidate clears the page cache. Deferred a frame, as the
-- Combine menu defers its own, because the rebuild releases the very row
-- the reader just clicked.
local function RebuildSoon(app)
    if C_Timer then
        C_Timer.After(0, function() app:Invalidate() end)
    else
        app:Invalidate()
    end
end

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
BuzzardFramesOptions.AuraFlatOptions = FlatOptions

-- Every OTHER Layout: the ones a copy could target. No same-type
-- restriction -- aura keys are type-neutral, which is what the Ace
-- builder's own comment says.
local function CopyTargets()
    local fl  = FlatLayouts()
    local cur = CurrentFlatID()
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

-- What the Copy dialog calls each sub-category. A scoped subtab uses its
-- scope's own label (BF.AURAS_SCOPE_TOGGLE_INFO carries it) instead.
local SUBCAT_LABELS = {
    buffs           = "Buffs",
    debuffs         = "Debuffs",
    bigDef          = "Big Defensive",
    dispelIndicator = "Dispellable Debuffs",
}

-- Which keys a subtab's Copy carries.
--
-- Scoped subtab  -> only its scope's keys.
-- A sub-category that HAS scopes -> everything except its scopes' keys.
-- A plain sub-category -> everything.
--
-- That is the rule from buildAurasSubcatCopyToDropdown, and it is what
-- makes each Copy move exactly what its own subtab shows: without it the
-- Debuffs tab's Copy would carry the Preset/Filter settings that live on
-- a different subtab under a different toggle.
local function CopiesKey(subcat, scopeInfo, k)
    local bf = BF()
    if scopeInfo then return scopeInfo.keySet[k] == true end
    local tog = bf and bf.AURAS_KEY_SCOPE_TOGGLE and bf.AURAS_KEY_SCOPE_TOGGLE[k]
    if tog == nil then return true end
    local info = bf.AURAS_SCOPE_TOGGLE_INFO and bf.AURAS_SCOPE_TOGGLE_INFO[tog]
    return not (info and info.subcat == subcat)
end

-- Copy one sub-category (or one scope of it) onto another Layout.
--
-- The source is the RESOLVED view, so an un-materialised sub-category on
-- the source flat falls through to the global and a pristine source
-- still produces a copy populated with defaults. The destination is
-- materialised through GetOrCreateAurasSubCategory, which wires the
-- metatable chain -- a table created without it answers nil for every
-- key the copy does not carry.
local function CopySubcatTo(subcat, scopeInfo, targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local srcFlat, dstFlat = fl[CurrentFlatID()], fl[targetID]
    if not (bf and srcFlat and dstFlat) then return end

    local srcSub = bf:GetAurasSubcatProfile(subcat, srcFlat)
    if type(srcSub) ~= "table" then return end
    local dstSub = bf:GetOrCreateAurasSubCategory(dstFlat, subcat)
    if type(dstSub) ~= "table" then return end

    for k, v in pairs(srcSub) do
        if CopiesKey(subcat, scopeInfo, k) then
            dstSub[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    bf:InvalidateAurasSubcatViews(subcat)
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

-- The strip. `subcat` is the sub-category the subtab shows;
-- `scopeToggle` names its scope when it has one.
function BuzzardFramesOptions:AuraScopeStrip(subcat, scopeToggle)
    local function scopeInfo()
        local bf = BF()
        return scopeToggle and bf and bf.AURAS_SCOPE_TOGGLE_INFO
               and bf.AURAS_SCOPE_TOGGLE_INFO[scopeToggle] or nil
    end
    local function gateToggle()
        local bf = BF()
        return scopeToggle
            or (bf and bf.AURAS_SUBCAT_TOGGLE and bf.AURAS_SUBCAT_TOGGLE[subcat])
    end
    local function label()
        local si = scopeInfo()
        if si and si.label then return si.label end
        return SUBCAT_LABELS[subcat] or "Auras"
    end
    local function isOn()
        local bf = BF()
        local tog = gateToggle()
        return tog and bf and bf:IsPerLayoutSection(tog) or false
    end
    local function notPer() return not isOn() end

    -- `scopeStrip` marks this card as the RAID/PARTY per-Layout row.
    -- "Per-Layout" means "per Raid/Party Layout", and a Custom Frame
    -- Group is not a Layout -- it is its own scope -- so the Custom
    -- Frame Groups assembler drops the card rather than rendering a
    -- control that would edit the wrong thing.
    return { preset = "strip", scopeStrip = true, fields = {
        { control = "switch", label = "Enable per-Layout Config",
          -- State first, then what it is the state of.
          labelSide = "after",
          -- The id is the TOGGLE key, so an undo on this switch is
          -- recorded against the thing it flips.
          id = scopeToggle or ("auras_" .. subcat), default = false,
          -- Ace's |cff87ceeb sky blue, kept to the digit: this switch
          -- configures the CONFIGURATION rather than the addon, and the
          -- color is how a reader has always been told the difference.
          labelColor = { 0.53, 0.81, 0.92, 1.00 },
          desc = "By default these settings are global and affect every "
              .. "Layout. Turn this on to give this subtab its own settings "
              .. "per Layout -- the other aura subtabs keep their own "
              .. "toggles.",
          disabled = "combat",
          get = function() return isOn() end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local bf = BF()
              local tog = gateToggle()
              if not (bf and tog) then return end
              -- Routed through the timing wrapper, so the cost can be
              -- measured in-game with debugTiming. A straight
              -- pass-through while that flag is off.
              bf:_TimeSectionPerLayout(tog, v)
              -- STRUCTURAL, not value-level: every field below now reads
              -- a different flat, and the Debuff Preset/Filter page decides
              -- which category cards EXIST from that flat's container
              -- claims -- so the memoised page is stale, not merely
              -- unread. Rebuilt on the NEXT frame, so the switch is not
              -- released under the reader's cursor.
              RebuildSoon(ctx.app)
          end },

        { control = "dropdown", label = "Modifying",
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited for. "
              .. "The currently active Layout is shown in green.",
          hidden = notPer, disabled = "combat",
          options = FlatOptions,
          get = function() return CurrentFlatID() end,
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
              -- STRUCTURAL: which cards a page carries can depend on the
              -- Modifying flat (the Preset/Filter categories follow the
              -- flat's container claims), and RefreshPage never re-runs
              -- the page builder. The same call the Size & Position strip
              -- makes, deferred a frame so the dropdown row survives the
              -- click that changed it.
              RebuildSoon(ctx.app)
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy all settings in this subtab to another Layout.",
          disabled = "combat",
          -- Nothing to copy TO is the same as nothing to copy, and while
          -- the subtab is global a copy between Layouts is a no-op.
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
              local si   = scopeInfo()
              local lbl  = label()
              local from = LayoutName(CurrentFlatID())
              local text
              if v == "__all" then
                  text = ("Copy all %s settings from \"%s\" to all other "
                      .. "Layouts? This will overwrite the %s settings of "
                      .. "every other Layout."):format(lbl, from, lbl)
              else
                  text = ("Copy all %s settings from \"%s\" to \"%s\"? This "
                      .. "will overwrite the %s settings of the \"%s\" "
                      .. "Layout."):format(lbl, from, LayoutName(v), lbl,
                      LayoutName(v))
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do
                          CopySubcatTo(subcat, si, e.id)
                      end
                  else
                      CopySubcatTo(subcat, si, v)
                  end
              end)
          end },
    }}
end

-- ── The Aura Preview dropdown ──────────────────────────────────
--
-- Three INDEPENDENT account-wide values: the Buffs section writes
-- db.global.previewModeBuffs, the Debuffs section previewModeDebuffs, and
-- Aura Cooldown Text previewModeAuraText, so each section configures its
-- own preview. The key is decided by the SECTION, not by whichever subtab
-- is on screen -- the Buffs instance must always write the Buffs key.
--
-- "No preview auras" is expressed by the master showPreview toggle,
-- which hides the whole pane, so this dropdown has no Off value and goes
-- with it.
function BuzzardFramesOptions:AuraPreviewField(group)
    local key = (group == "aurasDebuffs") and "previewModeDebuffs"
             or (group == "auraText") and "previewModeAuraText"
             or "previewModeBuffs"
    return { control = "dropdown", label = "Aura Preview",
        labelPlacement = "above",
        desc = "Choose which dummy auras appear on the preview frames when "
            .. "viewing this section.",
        id = key, default = "all",
        hidden = function()
            local bf = BF()
            return bf and bf.db.global.showPreview == false
        end,
        options = {
            { value = "all",           text = "All Auras" },
            { value = "allDispel",     text = "All Auras (+ Dispel Indicators)" },
            { value = "buffs",         text = "Buffs" },
            { value = "debuffs",       text = "Debuffs" },
            { value = "debuffsDispel", text = "Debuffs (+ Dispel Indicators)" },
        },
        get = function()
            local bf = BF()
            return (bf and bf.db.global[key]) or "all"
        end,
        set = function(_, _, v)
            local bf = BF()
            if not bf then return end
            bf.db.global[key] = v
            if bf.RefreshPreviewDummyAuras then bf:RefreshPreviewDummyAuras() end
        end }
end
