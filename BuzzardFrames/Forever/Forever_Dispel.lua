local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_Dispel.lua  (WoW Forever only)
--
-- "Dispellable by Me" on Forever. Forever has no specializations, so the
-- Retail per-spec table (DISPEL_TYPES_BY_SPEC, Indicators/DebuffIcons.lua)
-- is replaced by a per-CLASS table with the same three layers:
--
--   base     always-on types for the class
--   talents  spell-keyed layers. "Only when talented" ON (default) gates each
--            layer on IsPlayerSpell (on Forever these are trainer-learned
--            spells, so the toggle means "only once learned"); OFF folds them
--            all in unconditionally.
--   longCd   spell-keyed long-cooldown layers (the cleansing totems, as Retail
--            does with Poison Cleansing Totem). Counted only with "Include
--            Long-Cooldown Dispels" ON, and always IsPlayerSpell-gated.
--
-- Data: Forever client tables, build 1.60.1.70790 (SpellEffect Effect 38,
-- MiscValue = dispel type). Plan section 12.4. Every rank ID is listed so
-- IsPlayerSpell answers for whichever rank the player has learned.
--
-- WARLOCK (owner rulings Q4 + 2026-11-05 follow-up): Magic (Felhunter Devour
-- Magic, a pet ability) never depends on the active pet.
--   "Only when talented" ON  -> Magic only at UnitLevel("player") >= 30
--                               (Summon Felhunter's trainer level).
--   "Only when talented" OFF -> Magic at ANY level.
-- The level gate is carried by `minLevel` and folded into the dispel cache
-- key (BF.Forever.MyDispelKey); the toggle is already part of that key in
-- BF:MyDispelTypes, so both toggle states cache correctly.
-- ============================================================

local UnitClass     = UnitClass
local UnitLevel     = UnitLevel
local IsPlayerSpell = IsPlayerSpell
local pairs         = pairs

local DISPEL_TYPES_BY_CLASS = {
    PRIEST = {
        talents = {
            [527]  = { Magic = true },                                  -- Dispel Magic (Rank 1)
            [988]  = { Magic = true },                                  -- Dispel Magic (Rank 2)
            [528]  = { Disease = true },                                -- Cure Disease
            [552]  = { Disease = true },                                -- Abolish Disease
        },
    },
    PALADIN = {
        talents = {
            [1152] = { Disease = true, Poison = true },                 -- Purify
            [4987] = { Poison = true, Disease = true, Magic = true },   -- Cleanse
        },
    },
    DRUID = {
        talents = {
            [2782] = { Curse = true },                                  -- Remove Curse
            [8946] = { Poison = true },                                 -- Cure Poison
            [2893] = { Poison = true },                                 -- Abolish Poison
        },
    },
    MAGE = {
        talents = {
            [475]  = { Curse = true },                                  -- Remove Lesser Curse
        },
    },
    SHAMAN = {
        talents = {
            [526]  = { Poison = true },                                 -- Cure Poison
            [2870] = { Disease = true },                                -- Cure Disease
        },
        longCd = {
            [8166] = { Poison = true },                                 -- Poison Cleansing Totem
            [8170] = { Disease = true },                                -- Disease Cleansing Totem
        },
    },
    WARLOCK = {
        base     = { Magic = true },   -- Felhunter Devour Magic (pet), see minLevel
        minLevel = 30,                 -- level gate, applied only with "Only when talented" ON
    },
    -- HUNTER / ROGUE / WARRIOR: no entry -> empty set.
}
BF.Forever.DISPEL_TYPES_BY_CLASS = DISPEL_TYPES_BY_CLASS

local playerClass = select(2, UnitClass("player"))

-- PLAYER_LEVEL_UP can fire before UnitLevel("player") reports the new level;
-- the event's own payload is noted here and the higher of the two is used.
local _notedLevel = 0

local function PlayerLevel()
    local lvl = UnitLevel("player") or 0
    if _notedLevel > lvl then return _notedLevel end
    return lvl
end

-- Cache-key component that replaces the Retail spec ID in BF:MyDispelTypes.
-- Class token, plus ":1" / ":0" for a level-gated class so the gate is part
-- of the key. A class with no table returns false (no dispel), mirroring the
-- Retail "spec unknown / no entry" result.
function BF.Forever.MyDispelKey()
    local def = playerClass and DISPEL_TYPES_BY_CLASS[playerClass]
    if not def then return false end
    if def.minLevel then
        return playerClass .. ((PlayerLevel() >= def.minLevel) and ":1" or ":0")
    end
    return playerClass
end

-- Layered definition for a key from MyDispelKey. `talented` is the resolved
-- "Only when talented" toggle from BF:MyDispelTypes: the level gate applies
-- only when it is ON (nil returned below the level); OFF ignores the level.
-- The returned table is shared and must not be mutated.
function BF.Forever.DispelDefForKey(key, talented)
    if not key then return nil end
    local def = DISPEL_TYPES_BY_CLASS[playerClass]
    if not def then return nil end
    if def.minLevel and talented and key ~= playerClass .. ":1" then return nil end
    return def
end

-- Integer fingerprint of everything the Forever type set depends on outside
-- the two settings toggles: the level gate and each table spell's
-- IsPlayerSpell answer. Allocation-free. Used to drop the (frequent, often
-- in-combat) SPELLS_CHANGED events that did not change anything dispel-wise.
local function Fingerprint()
    local def = playerClass and DISPEL_TYPES_BY_CLASS[playerClass]
    if not def then return 0 end
    local acc = 1
    if def.minLevel then
        acc = acc * 2 + ((PlayerLevel() >= def.minLevel) and 1 or 0)
    end
    if IsPlayerSpell then
        if def.talents then
            for sid in pairs(def.talents) do
                acc = acc * 2 + (IsPlayerSpell(sid) and 1 or 0)
            end
        end
        if def.longCd then
            for sid in pairs(def.longCd) do
                acc = acc * 2 + (IsPlayerSpell(sid) and 1 or 0)
            end
        end
    end
    return acc
end

local _lastFingerprint = nil
local _pendingRefresh  = false   -- a level/spell change arrived in combat

local InCombatLockdown = InCombatLockdown

-- Called once from Indicators/DebuffIcons.lua's refresh block with that
-- file's event owner and its OnDispelRefresh handler. Adds the two Forever
-- triggers (plan section 15.1 "Q4 implementation"):
--   PLAYER_LEVEL_UP  the warlock level gate (and any level-trained dispel)
--   SPELLS_CHANGED   trainer-learned dispel ranks
-- Both route through OnDispelRefresh (cache wipe + MyDispelGen bump + light
-- container refresh) ONLY when the fingerprint moved.
--
-- Never in combat (owner ruling 2026-11-05): while InCombatLockdown() is true
-- the handlers only set a pending flag (and PLAYER_LEVEL_UP keeps its level
-- payload, one number store, because UnitLevel may not report it yet).
-- PLAYER_REGEN_ENABLED is subscribed only while a refresh is pending, runs
-- the fingerprint check + OnDispelRefresh once, and unsubscribes itself.
function BF.Forever.SubscribeDispelRefresh(owner, onRefresh)
    if not (playerClass and DISPEL_TYPES_BY_CLASS[playerClass]) then return end
    local function RefreshIfChanged(o, event)
        local fp = Fingerprint()
        if fp == _lastFingerprint then return end
        _lastFingerprint = fp
        onRefresh(o, event)
    end
    local function OnRegenEnabled(o, event)
        o:Unsub("PLAYER_REGEN_ENABLED")
        _pendingRefresh = false
        RefreshIfChanged(o, event)
    end
    local function Defer(o)
        if _pendingRefresh then return end
        _pendingRefresh = true
        o:Sub("PLAYER_REGEN_ENABLED", OnRegenEnabled, "unitless")
    end
    owner:Sub("PLAYER_LEVEL_UP", function(o, event, level)
        if type(level) == "number" and level > _notedLevel then _notedLevel = level end
        if InCombatLockdown() then Defer(o) return end
        RefreshIfChanged(o, event)
    end, "unitless")
    owner:Sub("SPELLS_CHANGED", function(o, event)
        if InCombatLockdown() then Defer(o) return end
        RefreshIfChanged(o, event)
    end, "unitless")
end
