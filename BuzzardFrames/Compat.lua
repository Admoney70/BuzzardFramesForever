-- ============================================================
-- BuzzardFrames: Compat.lua
-- WoW Forever specialization API shim. Loads FIRST (before the libraries),
-- because several files cache these globals into locals at load time.
--
-- Forever runs the Midnight-era addon API but keeps Classic-shaped talents,
-- and its client does not provide the old global spec functions
-- (GetSpecialization, GetSpecializationInfo, GetSpecializationRole, ...).
-- Every one of them is defined here ONLY when the client lacks it, in this
-- order of preference:
--   1. the client's own global, if present (nothing is replaced);
--   2. the same function on C_SpecializationInfo, if the client has it;
--   3. a talent-tree fallback: the player's "spec" is the Classic talent tree
--      with the most points spent, mapped onto the spec IDs the rest of the
--      addon is keyed by. No points spent (e.g. below level 10) = no spec,
--      exactly as GetSpecialization behaves on retail before a spec is chosen.
-- ============================================================

local C_SI = C_SpecializationInfo

-- Spec IDs in spec-index order, per class. Classic talent trees line up with
-- the retail spec order for every class except the Druid, whose third tree
-- (Restoration) is spec index 4 -- see TREE_TO_SPEC_INDEX.
local CLASS_SPECS = {
    WARRIOR = { 71, 72, 73 },
    PALADIN = { 65, 66, 70 },
    HUNTER  = { 253, 254, 255 },
    ROGUE   = { 259, 260, 261 },
    PRIEST  = { 256, 257, 258 },
    SHAMAN  = { 262, 263, 264 },
    MAGE    = { 62, 63, 64 },
    WARLOCK = { 265, 266, 267 },
    DRUID   = { 102, 103, 104, 105 },
}
local TREE_TO_SPEC_INDEX = { DRUID = { 1, 2, 4 } }

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- id -> { name, role, class, icon }
local SPEC_INFO = {
    [71]  = { "Arms",          "DAMAGER", "WARRIOR", "Interface\\Icons\\Ability_Warrior_SavageBlow" },
    [72]  = { "Fury",          "DAMAGER", "WARRIOR", "Interface\\Icons\\Ability_Warrior_InnerRage" },
    [73]  = { "Protection",    "TANK",    "WARRIOR", "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    [65]  = { "Holy",          "HEALER",  "PALADIN", "Interface\\Icons\\Spell_Holy_HolyBolt" },
    [66]  = { "Protection",    "TANK",    "PALADIN", "Interface\\Icons\\Ability_Paladin_ShieldOfTheTemplar" },
    [70]  = { "Retribution",   "DAMAGER", "PALADIN", "Interface\\Icons\\Spell_Holy_AuraOfLight" },
    [253] = { "Beast Mastery", "DAMAGER", "HUNTER",  "Interface\\Icons\\Ability_Hunter_BeastMastery" },
    [254] = { "Marksmanship",  "DAMAGER", "HUNTER",  "Interface\\Icons\\Ability_Hunter_FocusedAim" },
    [255] = { "Survival",      "DAMAGER", "HUNTER",  "Interface\\Icons\\Ability_Hunter_Camouflage" },
    [259] = { "Assassination", "DAMAGER", "ROGUE",   "Interface\\Icons\\Ability_Rogue_DeadlyBrew" },
    [260] = { "Combat",        "DAMAGER", "ROGUE",   "Interface\\Icons\\Ability_Rogue_Waylay" },
    [261] = { "Subtlety",      "DAMAGER", "ROGUE",   "Interface\\Icons\\Ability_Stealth" },
    [256] = { "Discipline",    "HEALER",  "PRIEST",  "Interface\\Icons\\Spell_Holy_PowerWordShield" },
    [257] = { "Holy",          "HEALER",  "PRIEST",  "Interface\\Icons\\Spell_Holy_GuardianSpirit" },
    [258] = { "Shadow",        "DAMAGER", "PRIEST",  "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
    [262] = { "Elemental",     "DAMAGER", "SHAMAN",  "Interface\\Icons\\Spell_Nature_Lightning" },
    [263] = { "Enhancement",   "DAMAGER", "SHAMAN",  "Interface\\Icons\\Spell_Nature_LightningShield" },
    [264] = { "Restoration",   "HEALER",  "SHAMAN",  "Interface\\Icons\\Spell_Nature_MagicImmunity" },
    [62]  = { "Arcane",        "DAMAGER", "MAGE",    "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    [63]  = { "Fire",          "DAMAGER", "MAGE",    "Interface\\Icons\\Spell_Fire_FireBolt02" },
    [64]  = { "Frost",         "DAMAGER", "MAGE",    "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    [265] = { "Affliction",    "DAMAGER", "WARLOCK", "Interface\\Icons\\Spell_Shadow_DeathCoil" },
    [266] = { "Demonology",    "DAMAGER", "WARLOCK", "Interface\\Icons\\Spell_Shadow_Metamorphosis" },
    [267] = { "Destruction",   "DAMAGER", "WARLOCK", "Interface\\Icons\\Spell_Shadow_RainOfFire" },
    [102] = { "Balance",       "DAMAGER", "DRUID",   "Interface\\Icons\\Spell_Nature_StarFall" },
    [103] = { "Feral",         "DAMAGER", "DRUID",   "Interface\\Icons\\Ability_Druid_CatForm" },
    [104] = { "Guardian",      "TANK",    "DRUID",   "Interface\\Icons\\Ability_Racial_BearForm" },
    [105] = { "Restoration",   "HEALER",  "DRUID",   "Interface\\Icons\\Spell_Nature_HealingTouch" },
}

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Points spent in a talent tree. GetTalentTabInfo's returns differ between
-- clients: the modern form leads with the tab's numeric id and has
-- pointsSpent 5th; the legacy form leads with the name and has it 3rd.
local function TreePoints(tab)
    if not GetTalentTabInfo then return 0 end
    local ok, r1, _, r3, _, r5 = pcall(GetTalentTabInfo, tab)
    if not ok then return 0 end
    local pts
    if type(r1) == "number" then pts = r5 else pts = r3 end
    return type(pts) == "number" and pts or 0
end

-- The talent-tree fallback for GetSpecialization.
local function SpecIndexFromTalents()
    local class = PlayerClass()
    if not class or not CLASS_SPECS[class] then return nil end
    local tabs = (GetNumTalentTabs and GetNumTalentTabs()) or 3
    local best, bestPts = nil, 0
    for tab = 1, tabs do
        local pts = TreePoints(tab)
        if pts > bestPts then best, bestPts = tab, pts end
    end
    if not best then return nil end
    local map = TREE_TO_SPEC_INDEX[class]
    return map and map[best] or best
end

local function SpecIDForIndex(index, class)
    local list = CLASS_SPECS[class or PlayerClass() or ""]
    return list and index and list[index] or nil
end

if not GetSpecialization then
    if C_SI and C_SI.GetSpecialization then
        GetSpecialization = function(...) return C_SI.GetSpecialization(...) end
    else
        GetSpecialization = function() return SpecIndexFromTalents() end
    end
end

if not GetSpecializationInfo then
    if C_SI and C_SI.GetSpecializationInfo then
        GetSpecializationInfo = function(...) return C_SI.GetSpecializationInfo(...) end
    else
        GetSpecializationInfo = function(index)
            local id = SpecIDForIndex(index)
            local info = id and SPEC_INFO[id]
            if not info then return nil end
            return id, info[1], "", info[4], info[2], nil
        end
    end
end

if not GetSpecializationRole then
    if C_SI and C_SI.GetSpecializationRole then
        GetSpecializationRole = function(...) return C_SI.GetSpecializationRole(...) end
    else
        GetSpecializationRole = function(index)
            local _, _, _, _, role = GetSpecializationInfo(index)
            return role
        end
    end
end

if not GetSpecializationInfoByID then
    if C_SI and C_SI.GetSpecializationInfoByID then
        GetSpecializationInfoByID = function(...) return C_SI.GetSpecializationInfoByID(...) end
    else
        GetSpecializationInfoByID = function(id)
            local info = SPEC_INFO[id]
            if not info then return nil end
            local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info[3]] or info[3]
            return id, info[1], "", info[4], info[2], info[3], className
        end
    end
end

if not GetNumSpecializationsForClassID then
    if C_SI and C_SI.GetNumSpecializationsForClassID then
        GetNumSpecializationsForClassID = function(...) return C_SI.GetNumSpecializationsForClassID(...) end
    else
        GetNumSpecializationsForClassID = function(classID)
            for class, cid in pairs(CLASS_IDS) do
                if cid == classID then return #CLASS_SPECS[class] end
            end
            return 0
        end
    end
end

if not GetSpecializationInfoForClassID then
    if C_SI and C_SI.GetSpecializationInfoForClassID then
        GetSpecializationInfoForClassID = function(...) return C_SI.GetSpecializationInfoForClassID(...) end
    else
        GetSpecializationInfoForClassID = function(classID, index)
            for class, cid in pairs(CLASS_IDS) do
                if cid == classID then
                    local id = CLASS_SPECS[class][index]
                    local info = id and SPEC_INFO[id]
                    if not info then return nil end
                    return id, info[1], "", info[4], info[2], false, false
                end
            end
            return nil
        end
    end
end

-- The vendored oUF calls C_SpecializationInfo.GetSpecialization() and
-- C_ClassTalents.GetActiveConfigID() directly. Give it a namespace to call
-- when the client has none (or one without that member).
if not C_SpecializationInfo then
    C_SpecializationInfo = {}
end
if not C_SpecializationInfo.GetSpecialization then
    C_SpecializationInfo.GetSpecialization = GetSpecialization
end
if not C_ClassTalents then
    C_ClassTalents = {}
end
if not C_ClassTalents.GetActiveConfigID then
    C_ClassTalents.GetActiveConfigID = function() return nil end
end
