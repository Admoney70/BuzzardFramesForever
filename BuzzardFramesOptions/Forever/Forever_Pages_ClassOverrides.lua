-- ============================================================
-- BuzzardFramesOptions: Forever/Forever_Pages_ClassOverrides.lua
-- WoW Forever only. "Add Class Overrides" in place of "Add Spec
-- Overrides" (plan Phase D, section 15.1 "Phase D collections"), on the
-- three override collections:
--
--   roleSpec       Raid/Party Layouts > Layout Assignments
--                  storage: layouts.classOverrides[TOKEN][slot] (+ _present)
--   ufRoleSpec     Unit Frames > Layouts > Layout Assignments
--                  storage: ufClassLayouts[TOKEN] (presence),
--                           ufClassLayoutAssignment[TOKEN],
--                           enableUFClassLayouts (derived, as
--                           SyncEnableFlags derives the spec flag)
--   buffsAssigned  Buffs > Buff Preset/Filter
--                  storage: <preset store>.classOverrides[TOKEN]
--                           = { preset = ..., _present = true }
--
-- Each collection's Retail source / onAdd / onRemove / template branch
-- role-vs-spec; a `-- [FOREVER]` hook in each sends `kind == "class"`
-- here, so a class entry can never fall into the spec branch and write
-- specOverrides. Existing spec entries are not listed on Forever, and each
-- "Add Spec Overrides" dropdown and spec sentence has a `-- [FOREVER]`
-- branch at its definition that takes the builder or the wording below.
-- ============================================================
-- Gate on the client build, NOT on the BuzzardFrames object: this load-on-
-- demand addon must never look the main addon up in its main chunk (see the
-- Panel.lua header -- two earlier versions failed exactly that way). Same
-- test as BF.isForever in BuzzardFrames/Defaults.lua; the runtime's
-- BF.Forever table is created by the runtime files, never here.
local _cli = select(4, GetBuildInfo())
if not (_cli >= 16000 and _cli < 20000) then return end -- not WoW Forever
local function BF() return _G.BuzzardFrames end

local BuzzardFramesOptions = _G.BuzzardFramesOptions
local FUI   = BuzzardFramesOptions.ForeverUI

-- The class wording for every sentence on these surfaces that names a
-- spec. Each is read by a `-- [FOREVER]` branch at the sentence itself.
local TEXT = {}
FUI.TEXT = TEXT

local CLASS_BADGE = "|cff1d9e75Class override|r"
FUI.CLASS_BADGE = CLASS_BADGE

local function ClassItem(token)
    return { kind = "class", entryKey = token, id = "class_" .. token,
             title = FUI.ClassLabel(token) }
end
FUI.ClassItem = ClassItem

-- Present class entries, in the sorted class order, appended to `out`.
local function AppendPresent(out, store, isPresent)
    if type(store) ~= "table" then return out end
    for _, c in ipairs(FUI.SortedClasses()) do
        if isPresent(store[c.token]) then out[#out + 1] = ClassItem(c.token) end
    end
    return out
end

local function PresentMarker(e) return type(e) == "table" and e._present and true or false end
local function Truthy(e) return e and true or false end

-- An "Add Class Overrides" dropdown: classes without an entry yet,
-- alphabetical by name. Adding is an ACTION, so it never shows a value.
local function AddClassField(collectionId, existing, extra)
    return {
        control = "dropdown", label = "Add Class Overrides",
        labelPlacement = "above",
        widthMul = extra and extra.widthMul or nil,
        disabled = extra and extra.disabled or nil,
        options = function()
            local out = {}
            local have = existing() or {}
            for _, c in ipairs(FUI.SortedClasses()) do
                if not have[c.token] then
                    out[#out + 1] = { value = c.token, text = FUI.ClassLabel(c.token) }
                end
            end
            return out
        end,
        get = function() return nil end,
        set = function(_, ctx, val)
            ctx.app:CollectionAdd(collectionId, "class", val)
        end,
    }
end

-- ══ Raid/Party Layout Assignments (Pages_Layouts.lua) ══════════

local function Layouts()
    local bf = BF()
    local p = bf and bf.rpDB and bf.rpDB.profile
    return p and p.layouts
end

-- The overrides table for one class entry, created on first touch, as
-- OverridesTable does for a role or a spec.
function FUI.LayoutClassTable(p, token)
    if not (p and token) then return nil end
    p.classOverrides = p.classOverrides or {}
    p.classOverrides[token] = p.classOverrides[token] or {}
    return p.classOverrides[token]
end

function FUI.AppendLayoutClassMembers(out, l)
    return AppendPresent(out, l and l.classOverrides, PresentMarker)
end

function FUI.LayoutClassAdd(bf, p, token)
    if not (bf and p and FUI.IsClass(token)) then return nil end
    local t = FUI.LayoutClassTable(p, token)
    t._present = true
    bf:InvalidateRaidProfileCache()
    if bf.RefreshAll then bf:RefreshAll() end
    return ClassItem(token)
end

function FUI.LayoutClassRemove(bf, p, token)
    if not (bf and p) then return end
    if p.classOverrides then p.classOverrides[token] = nil end
    bf:InvalidateRaidProfileCache()
    if bf.RefreshAll then bf:RefreshAll() end
end

-- "Add Class Overrides" on the Layout Assignments page.
function FUI.LayoutAddClassField()
    return AddClassField("roleSpec", function()
        local l = Layouts()
        local have = {}
        for token, e in pairs((l and l.classOverrides) or {}) do
            if PresentMarker(e) then have[token] = true end
        end
        return have
    end)
end

TEXT.layoutsPrecedence =
    "If conflicting Role and Class overrides are defined (e.g. both "
    .. "Healer and Priest are defined and have different settings), "
    .. "the Class overrides take priority."
TEXT.layoutsGlobal =
    "These settings are active unless an override exists for the "
    .. "current Role or Class."

-- ══ Unit Frame Layout Assignments (Pages_UFLayouts.lua) ════════

local function UFProfileNow()
    local bf = BF()
    return bf and bf.ufDB and bf.ufDB.profile
end

-- In-use report for a layout being deleted: the class half of the
-- Retail role/spec check.
function FUI.UFClassUsages(p, layoutID, usages)
    if not p then return end
    local present = p.ufClassLayouts or {}
    for token, assigned in pairs(p.ufClassLayoutAssignment or {}) do
        if assigned == layoutID and present[token] then
            usages[#usages + 1] = "Class: " .. FUI.ClassName(token)
        end
    end
end

-- enableUFClassLayouts, DERIVED from the entry list exactly as
-- SyncEnableFlags derives enableUFSpecLayouts on Retail.
function FUI.SyncUFClassFlag(p)
    if not p then return end
    local any = false
    for _ in pairs(p.ufClassLayouts or {}) do any = true break end
    p.enableUFClassLayouts = any
end

-- Pages_UFLayouts.lua's SyncEnableFlags on Forever: the role flag exactly
-- as the Retail path writes it, the class flag in place of the spec flag
-- (Forever never writes enableUFSpecLayouts), then the page's own
-- ApplyRoleSpec. `anyRole` and `applyRoleSpec` are the caller's, so the
-- role half cannot drift from Retail's.
function FUI.SyncUFClassFlags(p, anyRole, applyRoleSpec)
    if not p then return end
    p.enableUFRoleLayouts = anyRole
    FUI.SyncUFClassFlag(p)
    if applyRoleSpec then applyRoleSpec() end
end

function FUI.AppendUFClassMembers(out, p)
    return AppendPresent(out, p and p.ufClassLayouts, Truthy)
end

-- Is the player's own class override currently winning over a role
-- override? The Forever answer to SpecOverrideActive.
function FUI.UFClassOverrideActive(p)
    local pc = FUI.PlayerClass()
    if not (p and pc) then return false end
    return (p.ufClassLayouts and p.ufClassLayouts[pc]
            and p.ufClassLayoutAssignment and p.ufClassLayoutAssignment[pc]) and true or false
end

function FUI.UFClassAdd(p, token, sync)
    if not (p and FUI.IsClass(token)) then return nil end
    p.ufClassLayouts = p.ufClassLayouts or {}
    p.ufClassLayouts[token] = true
    -- A new entry starts at "use the global setting", as a new role or
    -- spec entry does.
    if p.ufClassLayoutAssignment then p.ufClassLayoutAssignment[token] = nil end
    if sync then sync() end
    return ClassItem(token)
end

function FUI.UFClassRemove(p, token)
    if not p then return end
    if p.ufClassLayouts then p.ufClassLayouts[token] = nil end
    if p.ufClassLayoutAssignment then p.ufClassLayoutAssignment[token] = nil end
end

-- A class entry's pane: the role/spec pane's shape, writing the class
-- assignment. `UFProfile`, `options` and `apply` are the page's own.
function FUI.UFClassMemberPage(mctx, UFProfile, options, apply)
    local item = mctx.item
    local key  = item.entryKey
    return { groups = {
        { preset = "bare", fields = {
            { control = "note", wide = true, font = "GameFontNormalLarge",
              color = { 1, 1, 1, 1 },
              text = item.title .. "    " .. CLASS_BADGE },
        }},
        { title = "Layout", preset = "form", fields = {
            { control = "dropdown", label = "Layout",
              labelPlacement = "above",
              desc = "The Unit Frame Layout used while you are playing this class.",
              id      = "ufClassLayout_" .. key,
              default = "__global",
              options = options,
              get = function()
                  local p = UFProfile()
                  local t = p and p.ufClassLayoutAssignment
                  return (t and t[key]) or "__global"
              end,
              set = function(_, ctx, val)
                  local p = UFProfile()
                  if not p then return end
                  p.ufClassLayoutAssignment = p.ufClassLayoutAssignment or {}
                  p.ufClassLayoutAssignment[key] = (val ~= "__global") and val or nil
                  apply()
                  ctx.app:RefreshPage()
              end },
        }},
    }}
end

-- "Add Class Overrides" on the Unit Frame Layout Assignments page.
function FUI.UFAddClassField()
    return AddClassField("ufRoleSpec", function()
        local p = UFProfileNow()
        return (p and p.ufClassLayouts) or {}
    end)
end

TEXT.ufIntro =
    "Give a role or a class its own Unit Frame Layout. If both are "
    .. "defined for what you are currently playing, the Class "
    .. "override takes priority."
TEXT.ufGlobal =
    "This Layout is used unless an override exists for the current "
    .. "Role or Class."
TEXT.ufGlobalDesc =
    "The Unit Frame Layout used when no Role or Class override "
    .. "applies. The Layout currently in use is shown in green."
TEXT.ufRoleBeaten =
    "|cffff9900|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertOther:14:14:0:0|t "
    .. "The current class has an active class-specific layout which "
    .. "overrides this role.|r"

-- ══ Buffs presets (Pages_AuraContainers.lua, buffsAssigned) ════

-- Through the page accessor, not the addon: under a Custom Frame Group's
-- scope it answers with that group's proxy, as the Retail page's BF() does.
local function ScopedBF() return BuzzardFramesOptions:BF() end

local function PresetStoreNow()
    local bf = ScopedBF()
    return bf and bf.GetBuffsPresetContainer and bf:GetBuffsPresetContainer()
end

local function PresetsRebuild()
    local bf = ScopedBF()
    if bf and bf.RefreshAllCustomContainersWithRebuild then
        bf:RefreshAllCustomContainersWithRebuild()
    end
end

function FUI.AppendPresetClassMembers(out, t)
    return AppendPresent(out, t and t.classOverrides, PresentMarker)
end

-- Does the player's class have a preset override that beats a role one?
-- One with no preset falls through in the resolver and beats nothing.
local function PresetClassOverrideWins()
    local pc = FUI.PlayerClass()
    local t  = PresetStoreNow()
    local e  = pc and t and t.classOverrides and t.classOverrides[pc]
    return (type(e) == "table" and e._present and e.preset) and true or false
end

function FUI.PresetClassAdd(t, token)
    if not (t and FUI.IsClass(token)) then return nil end
    t.classOverrides = t.classOverrides or {}
    t.classOverrides[token] = t.classOverrides[token] or {}
    -- `_present` marks "exists in the UI", separately from having a value,
    -- as on a role or a spec entry.
    t.classOverrides[token]._present = true
    PresetsRebuild()
    return ClassItem(token)
end

function FUI.PresetClassRemove(t, token)
    if not t then return end
    if t.classOverrides then t.classOverrides[token] = nil end
    PresetsRebuild()
end

-- A class entry's card, the role/spec card's shape. `store`, `options`
-- and `refresh` are the page's own.
function FUI.PresetClassCard(mctx, store, options, refresh)
    local item  = mctx.item
    local token = item.entryKey
    local function entry()
        local t = store()
        return t and t.classOverrides and t.classOverrides[token] or nil
    end
    return { groups = {
        { title = item.title .. "    " .. CLASS_BADGE, preset = "form", fields = {
            { control = "dropdown", label = "Preset",
              desc = "The filter to use in this case, instead of the Global "
                  .. "Preset.",
              options = options,
              widthMul = 1.56,
              id = "preset_" .. item.id, disabled = "combat",
              get = function()
                  local e = entry()
                  return e and e.preset or nil
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local e = entry()
                  if not e then return end
                  e.preset = val
                  refresh(ctx)
              end },
        }},
    }}
end

-- "Add Class Overrides" on the Buff Preset/Filter page.
function FUI.PresetAddClassField()
    return AddClassField("buffsAssigned", function()
        local t = PresetStoreNow()
        local have = {}
        for token, e in pairs((t and t.classOverrides) or {}) do
            if PresentMarker(e) then have[token] = true end
        end
        return have
    end, { widthMul = 1.2, disabled = "combat" })
end

FUI.PresetClassOverrideWins = PresetClassOverrideWins

TEXT.presetsIntro =
    "The Global Preset decides which buffs the Buffs display shows. "
    .. "Add a Role or Class override below to use a different one in "
    .. "those cases.\n\nWhere a role and a class override both apply, "
    .. "the class override wins."
TEXT.presetsEmpty =
    "|cffaaaaaaNo role or class overrides yet. Every case uses the "
    .. "Global Preset above.|r"
TEXT.presetsRoleBeaten = "Current class has an override which takes priority."
