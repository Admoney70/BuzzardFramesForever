local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_SpellData.lua  (WoW Forever only)
--
-- Phase I data tables (plan sections 12.3, 12.4, 13, 17). Each replaces its
-- Retail table on Forever through a `-- [FOREVER]` hook:
--
--   CLASS_RAID_BUFF + RAID_BUFF_ORDER   Missing Raid Buff tracker
--   MISSING_RAID_BUFFS, IsRaidBuffKnown  its per-buff list (Priest: three)
--                                       (hook: AuraCustomizations/TrackedAuras.lua)
--   MakeAnyOfSetResolver(set)           its "any of these IDs" resolver
--                                       (hook: Statuses/SingleAuraTrackers.lua)
--   SATED / DESERTER / SKYRIDING /
--   ARCANE_EMPOWERMENT / TIME_TRIAL     out-of-combat debuff filter sets
--                                       (hook: TrackedAuras.lua)
--   SWIFTMENDABLE_IDS,
--   IsSwiftmendableActive()             Swiftmendable (hooks: AuraCustomizations.lua)
--   RANGE_SPELLS, RANGE_PET_SPELL,
--   RangeSpellGetters(class)            range-check spells (hooks: Range.lua)
--
-- Every ID was read from the Forever client tables, build 1.60.1.70790.
-- No Symbiotic Relationship tracker exists on Forever (the spell does not).
-- ============================================================

local F = BF.Forever
local GetUnitAuraBySpellID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID

-- ── Missing Raid Buff ──────────────────────────────────────────────────────
-- Forever spells have ranks, and the group versions (Gift of the Wild,
-- Arcane Brilliance, Prayer of Fortitude) apply the same buff family, so a
-- unit "has" the class buff when it carries ANY of these IDs.
--
-- Ordered for the any-of scan: highest trainer rank first (a max-level group
-- almost always carries it, so the scan usually stops at the first lookup),
-- then the group version, then the lower ranks and the remaining IDs. The ID
-- sets are the section 17 unions for Mark/Gift of the Wild, Arcane
-- Intellect/Brilliance and Power Word/Prayer of Fortitude; Battle Shout is
-- the section 12.3 rank list.
F.RAID_BUFF_ORDER = {
    DRUID = {
        9885, 21850,                                  -- MotW r7, GotW r2
        9884, 21849, 8907, 5234, 6756, 5232, 1126,    -- lower ranks
        16878, 24752, 364163,                         -- other MotW IDs
    },
    MAGE = {
        10157, 23028,                                 -- AI r5, Arcane Brilliance
        10156, 1461, 1460, 1459,                      -- lower ranks
        16876, 364161,                                -- other AI IDs
    },
    PRIEST = {
        10938, 21564,                                 -- PW:F r6, PoF r2
        10937, 21562, 2791, 1245, 1244, 1243,         -- lower ranks
        450086,                                       -- other PoF ID
    },
    WARRIOR = {
        25289, 11551, 11550, 11549, 6192, 5242, 6673, -- Battle Shout r7..r1
    },
}

-- Same data as sets, the shape BF.CLASS_RAID_BUFF carries on Retail for its
-- table entries. F.RAID_BUFF_ORDER_BY_SET maps each set back to its ordered
-- array so the resolver can scan in the order above.
F.CLASS_RAID_BUFF = {}
F.RAID_BUFF_ORDER_BY_SET = {}
for class, list in pairs(F.RAID_BUFF_ORDER) do
    local set = {}
    for i = 1, #list do set[list[i]] = true end
    F.CLASS_RAID_BUFF[class] = set
    F.RAID_BUFF_ORDER_BY_SET[set] = list
end

-- Priest's two other group buffs, same shape as the lists above: highest
-- single-target rank, then the group version, then the lower ranks. IDs from
-- the Forever Buff List table (Forever/Forever_BuffList.lua).
F.PRIEST_SPIRIT_ORDER = {
    27841, 27681,                                 -- Divine Spirit r4, Prayer of Spirit r1
    14819, 14818, 14752,                          -- lower ranks
}
F.PRIEST_SHADOW_ORDER = {
    10958, 27683,                                 -- Shadow Protection r3, PoSP r1
    10957, 976,                                   -- lower ranks
}

local function OrderedSet(list)
    local set = {}
    for i = 1, #list do set[list[i]] = true end
    F.RAID_BUFF_ORDER_BY_SET[set] = list
    return set
end

-- Every buff the Missing Raid Buff indicator can remind about on Forever --
-- the Forever replacement for BF.MISSING_RAID_BUFFS (hook:
-- AuraCustomizations/TrackedAuras.lua; field meanings documented there).
-- Each `ids` is a RANK SET: AddSpellId installs the any-of resolver for it.
-- knownAny: tracked only while the player knows at least one of its IDs
-- (F.IsRaidBuffKnown) -- Divine Spirit is a talent and the rest are trained.
F.MISSING_RAID_BUFFS = {
    { class = "DRUID",   key = "DRUID_MOTW",       name = "Mark of the Wild",
      spell = F.RAID_BUFF_ORDER.DRUID[1],   ids = F.CLASS_RAID_BUFF.DRUID,   knownAny = true },
    { class = "MAGE",    key = "MAGE_INTELLECT",   name = "Arcane Intellect",
      spell = F.RAID_BUFF_ORDER.MAGE[1],    ids = F.CLASS_RAID_BUFF.MAGE,    knownAny = true },
    { class = "PRIEST",  key = "PRIEST_FORTITUDE", name = "Power Word: Fortitude",
      spell = F.RAID_BUFF_ORDER.PRIEST[1],  ids = F.CLASS_RAID_BUFF.PRIEST,  knownAny = true },
    { class = "PRIEST",  key = "PRIEST_SPIRIT",    name = "Divine Spirit",
      spell = F.PRIEST_SPIRIT_ORDER[1],     ids = OrderedSet(F.PRIEST_SPIRIT_ORDER), knownAny = true },
    { class = "PRIEST",  key = "PRIEST_SHADOW",    name = "Shadow Protection",
      spell = F.PRIEST_SHADOW_ORDER[1],     ids = OrderedSet(F.PRIEST_SHADOW_ORDER), knownAny = true },
    { class = "WARRIOR", key = "WARRIOR_SHOUT",    name = "Battle Shout",
      spell = F.RAID_BUFF_ORDER.WARRIOR[1], ids = F.CLASS_RAID_BUFF.WARRIOR, knownAny = true },
}

-- True when the player knows ANY ID of the entry's set. Deliberately not
-- Grid2's per-ID drop (ignoreUnknownSpells): a priest who knows Fortitude
-- rank 3 must still see a rank-6 Fortitude from another priest as present,
-- so the whole set stays in the scan and only the register/skip decision
-- reads the spellbook. Settings-time only (tracker sync), never per aura.
local IsPlayerSpell = IsPlayerSpell
function F.IsRaidBuffKnown(entry)
    if not IsPlayerSpell then return true end
    for id in pairs(entry.ids) do
        if IsPlayerSpell(id) then return true end
    end
    return false
end

-- Grid2 StatusAurasMissing.lua pattern: loop the ID set with
-- GetUnitAuraBySpellID and stop at the first hit. Installed as the tracker's
-- resolveSpellID (SingleAuraTracker:AddSpellId hook), so the framework's
-- existing scan/compare/dispatch is reused unchanged: the resolver returns
-- the ID the unit actually carries, or the first ID of the list when it
-- carries none (the framework's own lookup then finds nothing = absent).
--
-- Cost: out of combat only (the tracker framework is combat-inert), at most
-- #list lookups per unit per UNIT_AURA when the buff is missing, usually ONE
-- when it is present, plus the framework's own lookup of the returned ID.
-- Built once per tracker registration; no per-call allocation.
function F.MakeAnyOfSetResolver(set)
    local list = F.RAID_BUFF_ORDER_BY_SET[set]
    if not list then
        list = {}
        for id in pairs(set) do
            if type(id) == "number" then list[#list + 1] = id end
        end
        table.sort(list, function(a, b) return a > b end)
    end
    local n, first = #list, list[1]
    return function(_, unit)
        if not GetUnitAuraBySpellID then return first end
        for i = 1, n do
            local id = list[i]
            if GetUnitAuraBySpellID(unit, id) then return id end
        end
        return first
    end
end

-- ── Out-of-combat debuff filters (plan 12.4) ───────────────────────────────
-- Only BG Deserter (26013) exists on Forever. The other four filters are
-- hidden on Forever (options) and their sets are empty, so the long-term
-- debuff exclude builder adds nothing for them.
F.SATED_SPELL_IDS              = {}
F.DESERTER_SPELL_IDS           = { [26013] = true }   -- Deserter (BG)
F.SKYRIDING_SPELL_IDS          = {}
F.ARCANE_EMPOWERMENT_SPELL_IDS = {}
F.TIME_TRIAL_SPELL_IDS         = {}

-- ── Swiftmendable (plan 15.1) ──────────────────────────────────────────────
-- Every Rejuvenation / Regrowth / Wild Growth ID from section 17, both the
-- trainer rank family and the alternate SpellAuraVisibility family (owner:
-- "include both" until the in-game check in section 16 is done).
F.SWIFTMENDABLE_IDS = {}
do
    local ids = {
        -- Rejuvenation
        774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,
        417057, 417058, 417059, 417060, 417061, 417062, 417063, 417064,
        417065, 417066, 417068,
        -- Regrowth
        8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858,
        436937, 436938, 436939, 436940, 436942, 436943, 436944, 436945, 436946,
        -- Wild Growth
        408120, 1238214, 1238215,
    }
    for i = 1, #ids do F.SWIFTMENDABLE_IDS[ids[i]] = true end
end

F.SWIFTMEND_SPELL_ID = 18562

-- The Retail gate is `specId2 == 105` (Restoration Druid). Forever: a Druid
-- who knows Swiftmend (a talent there). Settings-time only -- read in the
-- GetContainerBuffConfig build, which talent / spell changes invalidate.
function F.IsSwiftmendableActive()
    if F.playerClass ~= "DRUID" then return false end
    return (IsPlayerSpell and IsPlayerSpell(F.SWIFTMEND_SPELL_ID)) and true or false
end

-- ── Range-check spells ─────────────────────────────────────────────────────
-- Replaces Range.lua's Retail class table (Grid2 StatusRange.lua's list).
-- Several of those IDs do not exist on Forever (Lightning Bolt 188196, Hand
-- of Reckoning 62124, Cobra Shot 193455, Steady Shot 132031, Shadowstep
-- 36554, Arcane Blast 30451), and Range.lua checks by spell NAME, which only
-- answers for a spell the character has learned. So each pick is the
-- earliest-learned spell of its kind; a name check follows the highest rank
-- the character knows. Learn levels are SpellLevels.SpellLevel, build
-- 1.60.1.70790. Read once at login, as the Retail table is.
F.RANGE_SPELLS = {
    DRUID   = { hostile = 5176,  friendly = 5185 }, -- Wrath (1), Healing Touch (1)
    PRIEST  = { hostile = 585,   friendly = 2050 }, -- Smite (1), Lesser Heal (1)
    SHAMAN  = { hostile = 403,   friendly = 331  }, -- Lightning Bolt (1), Healing Wave (1)
    PALADIN = { hostile = 20271, friendly = 635  }, -- Judgement (4, 10 yd), Holy Light (1)
    WARLOCK = { hostile = 686,   friendly = 20707 }, -- Shadow Bolt (1), Soulstone (18)
    WARRIOR = { hostile = 355 },                    -- Taunt (10); no friendly spell
    HUNTER  = { hostile = 75 },                     -- Auto Shot (1); no friendly spell
    ROGUE   = { hostile = 6770 },                   -- Sap (10); no friendly spell
    MAGE    = { hostile = 133,   friendly = 1459 }, -- Fireball (1), Arcane Intellect (1)
}

-- The pet frame's range spell: Health Funnel (12) for Warlock, as Grid2 has
-- it (it was only removed from Retail), and Mend Pet (12) for Hunter.
F.RANGE_PET_SPELL = { HUNTER = 136, WARLOCK = 755 }

-- The two getters Range.lua's class table builds, for `class`.
function F.RangeSpellGetters(class)
    local r = F.RANGE_SPELLS[class] or {}
    local h, f = r.hostile, r.friendly
    return function() return h end, function() return f end
end
