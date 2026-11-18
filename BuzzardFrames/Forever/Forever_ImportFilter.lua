local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_ImportFilter.lua  (WoW Forever only)
--
-- Phase H (plan sections 13 and 15.1): import / export compatibility.
--
--   F.StampExportEnvelope(envelope)
--       Called by BF:ExportProfileString on Forever only. Writes
--       envelope.game = "forever". Retail never writes the field, so a
--       string WITHOUT it is a Retail string (that includes every string
--       made before this change).
--
--   F.FilterDecodedImport(decoded [, srcDbVersion])
--       (srcDbVersion is accepted for the caller's convenience but unused:
--       no imported buff container survives to need the dbVersion stamp.)
--       Called by BF:DecodeProfileString on Forever, after the module
--       tables are flattened into `decoded`. A Forever string passes
--       through untouched. A Retail string has everything Forever cannot
--       use DISCARDED (owner ruling: discard everything incompatible), and
--       the discards are listed, one line per kind, in
--       decoded._importDiscarded for the import report. The options page
--       must also call this for the legacy (pre-"!4!") decode path -- those
--       strings are always Retail.
--
-- The reverse direction (a Forever string imported on Retail) is handled
-- by StripForeverOnlyKeys in ProfileExport.lua, because this file does not
-- load on Retail.
--
-- Retail -> Forever discard list (what this file removes):
--   AuraCustomizations
--     * EVERY buff container -- Buff List entries (single buffs) and
--       multi-icon Buff containers alike, in either shape (the sbPortable
--       block with its curated diffs and whole entries, or a schema-1
--       customBuffContainers array). Owner ruling 2026-11-05: buff
--       containers are specific to the game they were created on. With
--       both keys gone the merge leaves this profile's own (seeded) Buff
--       List untouched.
--     * spellAssign and every spec-keyed table (keys starting "spec":
--       specSpell*, specBuffs*, specSpellPrevAssign).
--     * buffsDisplay.specOverrides (Buffs preset Spec overrides).
--     * loadSpec / loadSpecTypes on every buff and debuff container.
--     * options Forever hides: showRaidBuffs (Show Raid Buff Out of
--       Combat), showSatedDebuffs, showSkyridingDebuffs,
--       showArcaneEmpowermentDebuffs, showTimeTrialDebuffs.
--   RaidPartyFrames (module sections AND every flat's per-Layout copy)
--     * layouts.specOverrides (Layout Assignment Spec overrides).
--     * auras.dispelIndicator.dispelIndicatorOnlyIfReady /
--       dispelBorderOnlyIfReady / dispelOverlayOnlyIfReady /
--       dispelHealthColorOnlyIfReady ("Only Show if Dispel Available").
--     * healthPower.showPowerBarBloodDK.
--     * castBar.showEmpowerPips / pipColor / pipWidth (Empowered Casts).
--     * icons.showMissingSymbiotic.
--     * icons.missingRaidBuffs entries for Retail-only buffs (Symbiotic
--       Relationship, Blessing of the Bronze, Skyfury) and
--       icons.missingRaidBuffInstanceTypes.delve (no delves on Forever).
--     * healthPower.customPowerColors entries for powers Forever lacks.
--     * colors.customClassColors entries for classes Forever lacks.
--     * _previewUnitsByFlat[*].class for classes Forever lacks.
--   CustomFrameGroups
--     * classFilter entries for classes Forever lacks; each group flat gets
--       the same per-section discards as a raid/party flat.
--   UnitFrames
--     * ufSpecLayouts / ufSpecLayoutAssignment / enableUFSpecLayouts.
--     * altPowerBarDruidSpecs (Druid Specializations).
--     * oufResourceBarPartialFill (Partial Fill: Essence / Destruction).
--   _globalColors
--     * customClassColors entries for classes Forever lacks.
--
-- Same-game imports (a Forever string on Forever) are not filtered at all.
--
-- Runs once per Decode click; never at runtime.
-- ============================================================

local F = BF.Forever

-- Power tokens that exist on Forever (plan 12.4: the Forever PowerType
-- table). The "POWER_TYPE_*" NPC variants are left alone.
local FOREVER_POWERS = {
    MANA = true, RAGE = true, FOCUS = true, ENERGY = true,
    COMBO_POINTS = true, HAPPINESS = true,
}

-- Fallback only for a load-order accident; Forever_Class.lua builds the
-- real set from CLASS_SORT_ORDER.
local FALLBACK_CLASS_SET = {
    DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
    ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true,
}
local function ClassSet()
    local s = F.CLASS_SET
    if type(s) == "table" and next(s) ~= nil then return s end
    return FALLBACK_CLASS_SET
end

-- Section-relative paths of options Forever hides (plan section 7). Each is
-- removed from the module's section AND from every flat's per-Layout copy.
-- Removing a key from a flat section is safe under ProfileExport's DEPTH
-- RULE: a top-level section key falls back to the global section, and the
-- four dispelIndicator keys are false-default booleans (nil reads false).
local HIDDEN_SECTION_PATHS = {
    { "auras", "dispelIndicator", "dispelIndicatorOnlyIfReady" },
    { "auras", "dispelIndicator", "dispelBorderOnlyIfReady" },
    { "auras", "dispelIndicator", "dispelOverlayOnlyIfReady" },
    { "auras", "dispelIndicator", "dispelHealthColorOnlyIfReady" },
    { "healthPower", "showPowerBarBloodDK" },
    { "castBar", "showEmpowerPips" },
    { "castBar", "pipColor" },
    { "castBar", "pipWidth" },
    { "icons", "showMissingSymbiotic" },
    { "icons", "missingRaidBuffs", "DRUID_SYMBIOTIC" },
    { "icons", "missingRaidBuffs", "EVOKER_BRONZE" },
    { "icons", "missingRaidBuffs", "SHAMAN_SKYFURY" },
    { "icons", "missingRaidBuffInstanceTypes", "delve" },
}

local AC_HIDDEN_KEYS = {
    "showRaidBuffs", "showSatedDebuffs", "showSkyridingDebuffs",
    "showArcaneEmpowermentDebuffs", "showTimeTrialDebuffs",
}

local UF_SPEC_KEYS = {
    "ufSpecLayouts", "ufSpecLayoutAssignment", "enableUFSpecLayouts",
    "altPowerBarDruidSpecs", "oufResourceBarPartialFill",
}

local function Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- Removes the value at `path` under `root`. Returns 1 when something was
-- removed, else 0.
local function StripPath(root, path)
    local t = root
    for i = 1, #path - 1 do
        if type(t) ~= "table" then return 0 end
        t = t[path[i]]
    end
    if type(t) ~= "table" then return 0 end
    local k = path[#path]
    if t[k] == nil then return 0 end
    t[k] = nil
    return 1
end

-- Removes every key of map `t` that `keep` does not accept. Returns count.
local function StripMapKeys(t, keep)
    if type(t) ~= "table" then return 0 end
    local doomed = {}
    for k in pairs(t) do
        if not keep(k) then doomed[#doomed + 1] = k end
    end
    for i = 1, #doomed do t[doomed[i]] = nil end
    return #doomed
end

local function KeepPower(k)
    return FOREVER_POWERS[k] or (type(k) == "string" and k:find("^POWER_TYPE_") ~= nil)
end

-- Section-level discards on one holder of sections (the RP module table or
-- one flat). Accumulates into `acc`.
local function ScrubSections(holder, acc, classSet)
    if type(holder) ~= "table" then return end
    for i = 1, #HIDDEN_SECTION_PATHS do
        acc.hidden = acc.hidden + StripPath(holder, HIDDEN_SECTION_PATHS[i])
    end
    local hp = holder.healthPower
    if type(hp) == "table" then
        acc.powers = acc.powers + StripMapKeys(hp.customPowerColors, KeepPower)
    end
    local colors = holder.colors
    if type(colors) == "table" then
        acc.classColors = acc.classColors
            + StripMapKeys(colors.customClassColors, function(k) return classSet[k] end)
    end
end

local function ScrubSpecCondition(e)
    if type(e) ~= "table" then return 0 end
    if e.loadSpec == nil and e.loadSpecTypes == nil then return 0 end
    e.loadSpec, e.loadSpecTypes = nil, nil
    return 1
end

local function FilterAuraCustomizations(ac, Note)
    if type(ac) ~= "table" then return end

    -- Every buff container out (see header), counted by kind.
    local nSingle, nMulti, nSpecCond = 0, 0, 0
    local function Tally(e)
        if type(e) ~= "table" then return end
        if e.singleBuff then nSingle = nSingle + 1 else nMulti = nMulti + 1 end
    end
    local sbp = ac.sbPortable
    if type(sbp) == "table" then
        if type(sbp.diffs) == "table" then nSingle = nSingle + #sbp.diffs end
        if type(sbp.whole) == "table" then
            for _, w in ipairs(sbp.whole) do
                if type(w) == "table" then Tally(w.entry) end
            end
        end
    end
    if type(ac.customBuffContainers) == "table" then
        for _, e in pairs(ac.customBuffContainers) do Tally(e) end
    end
    ac.sbPortable, ac.customBuffContainers = nil, nil
    Note("Buff List entries (Single Buffs) created on Retail", nSingle)
    Note("Buff containers created on Retail", nMulti)

    local debuffs = ac.customDebuffContainers
    if type(debuffs) == "table" then
        for _, e in pairs(debuffs) do nSpecCond = nSpecCond + ScrubSpecCondition(e) end
    end
    Note("Spec load conditions on debuff containers", nSpecCond)

    -- spellAssign + every spec-keyed table.
    local nSpecTables = 0
    local doomed = {}
    for k in pairs(ac) do
        if k == "spellAssign" or (type(k) == "string" and k:find("^spec")) then
            doomed[#doomed + 1] = k
        end
    end
    for i = 1, #doomed do ac[doomed[i]] = nil end
    nSpecTables = #doomed
    Note("Spec-keyed spell customization tables", nSpecTables)

    local bd = ac.buffsDisplay
    if type(bd) == "table" and bd.specOverrides ~= nil then
        Note("Buffs preset: Spec overrides", Count(bd.specOverrides))
        bd.specOverrides = nil
    end

    local nHidden = 0
    for i = 1, #AC_HIDDEN_KEYS do
        local k = AC_HIDDEN_KEYS[i]
        if ac[k] ~= nil then ac[k] = nil; nHidden = nHidden + 1 end
    end
    Note("Buffs/Debuffs options not available on this game", nHidden)
end

function F.StampExportEnvelope(envelope)
    if type(envelope) == "table" then envelope.game = "forever" end
end

function F.FilterDecodedImport(decoded, srcDbVersion)
    if type(decoded) ~= "table" then return end
    if decoded.game == "forever" then return end

    local lines = {}
    local function Note(label, n)
        if n and n > 0 then lines[#lines + 1] = string.format("%s (%d)", label, n) end
    end
    local classSet = ClassSet()
    local function KeepClass(k) return classSet[k] end
    local acc = { hidden = 0, powers = 0, classColors = 0 }

    -- Raid/Party Frames
    local rp = decoded.RaidPartyFrames
    if type(rp) == "table" then
        local lp = rp.layouts
        if type(lp) == "table" then
            if lp.specOverrides ~= nil then
                Note("Raid/Party Layout Assignments: Spec overrides", Count(lp.specOverrides))
                lp.specOverrides = nil
            end
            if type(lp.flatLayouts) == "table" then
                for _, flat in pairs(lp.flatLayouts) do ScrubSections(flat, acc, classSet) end
            end
        end
        ScrubSections(rp, acc, classSet)
        local pu = rp._previewUnitsByFlat
        if type(pu) == "table" then
            local n = 0
            for _, u in pairs(pu) do
                if type(u) == "table" and u.class ~= nil and not classSet[u.class] then
                    u.class = nil
                    n = n + 1
                end
            end
            Note("Preview units set to classes this game does not have", n)
        end
    end

    -- Custom Frame Groups
    local cfg = decoded.CustomFrameGroups
    if type(cfg) == "table" and type(cfg.customFrameGroups) == "table" then
        local n = 0
        for _, g in pairs(cfg.customFrameGroups) do
            if type(g) == "table" then
                n = n + StripMapKeys(g.classFilter, KeepClass)
                ScrubSections(g.flat, acc, classSet)
            end
        end
        Note("Custom Frame Group class filters for classes this game does not have", n)
    end

    -- Buffs & Debuffs
    FilterAuraCustomizations(decoded.AuraCustomizations, Note)

    -- Unit Frames
    local uf = decoded.UnitFrames
    if type(uf) == "table" then
        local n = 0
        for i = 1, #UF_SPEC_KEYS do
            local k = UF_SPEC_KEYS[i]
            if uf[k] ~= nil then uf[k] = nil; n = n + 1 end
        end
        Note("Unit Frames: Spec layouts and spec-only options", n)
    end

    -- Colors sidecar
    local gc = decoded._globalColors
    if type(gc) == "table" then
        acc.classColors = acc.classColors + StripMapKeys(gc.customClassColors, KeepClass)
    end

    Note("Raid/Party options not available on this game", acc.hidden)
    Note("Power colors for powers this game does not have", acc.powers)
    Note("Class colors for classes this game does not have", acc.classColors)

    if #lines > 0 then
        decoded._importDiscarded = lines
    end
end
