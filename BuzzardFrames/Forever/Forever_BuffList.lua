local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_BuffList.lua  (WoW Forever only)
--
-- The Forever Buff List (plan Phase J as finalized in section 17):
--
--   * BUFF_LIST_SEEDS -- the 25 class buffs Blizzard's own raid frames list
--     (SpellAuraVisibility, section 16), each holding the UNION of its IDs
--     (SpellAuraVisibility IDs + trainer ranks + Grid2's same-name IDs; every
--     ID name-checked in SpellName, build 1.60.1.70790).
--   * SeedBuffList(acp) -- seeds them once per profile, plus the Swiftmendable
--     pseudo entry for Druids. Dispatched from the Buff List accessor through
--     the BF:SeedLateCuratedSingleBuffs hook (Core_Migrations.lua), which is
--     the dual-caller path that reaches new, copied, reset and imported
--     profiles; the Retail seeders are skipped on Forever (plan E1).
--   * GetSingleBuffSpellSet(c, sid) -- the Forever half of the R2 accessor
--     BF:GetSingleBuffSpellSet: the entry's rank-ID map + signature, built
--     ONCE per entry and cached (Grid2 Auras_UpdateDB pattern).
--   * OnSingleBuffCreated(c, sid) -- add by spell ID fills c.foreverSpellIDs
--     with every same-name rank (BF.Forever.ExpandSpellToRanks).
--
-- Entry fields (Forever-only keys; Retail never reads them):
--   foreverSpellIDs   array of every rank ID the entry matches. The entry
--                     still has ONE slot / group / fx slot per frame: the IDs
--                     only widen that slot's include map (plan 17.1).
--   loadClass / loadClassTypes   the Class load condition (Forever_Class.lua)
-- singleBuffSpellID stays the PRIMARY id (lowest rank number) so every
-- Retail-shaped reader -- icon, name, keys, per-entry settings -- keeps working.
-- ============================================================

local F = BF.Forever

-- ── Seed data (plan section 17) ────────────────────────────────────────────
-- sid = the primary ID: rank 1 where the spell has trainer ranks, else the
-- first ID of the row. ids = every ID the entry matches (includes sid).
F.BUFF_LIST_SEEDS = {
    -- DRUID (6)
    { class = "DRUID", name = "Mark of the Wild", sid = 1126,
      ids = { 1126, 5232, 5234, 6756, 8907, 9884, 9885, 16878, 24752, 364163 } },
    { class = "DRUID", name = "Gift of the Wild", sid = 21849,
      ids = { 21849, 21850 } },
    { class = "DRUID", name = "Rejuvenation", sid = 774,
      ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,
              417057, 417058, 417059, 417060, 417061, 417062, 417063, 417064,
              417065, 417066, 417068 } },
    { class = "DRUID", name = "Regrowth", sid = 8936,
      ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858,
              436937, 436938, 436939, 436940, 436942, 436943, 436944, 436945,
              436946 } },
    { class = "DRUID", name = "Lifebloom", sid = 408124,
      ids = { 408124 } },
    { class = "DRUID", name = "Wild Growth", sid = 408120,
      ids = { 408120, 1238214, 1238215 } },
    -- MAGE (3)
    { class = "MAGE", name = "Arcane Intellect", sid = 1459,
      ids = { 1459, 1460, 1461, 10156, 10157, 16876, 364161 } },
    { class = "MAGE", name = "Arcane Brilliance", sid = 23028,
      ids = { 23028 } },
    { class = "MAGE", name = "Temporal Beacon", sid = 400735,
      ids = { 400735 } },
    -- PALADIN (8)
    { class = "PALADIN", name = "Devotion Aura", sid = 465,
      ids = { 465, 643, 1032, 10290, 10291, 10292, 10293 } },
    { class = "PALADIN", name = "Retribution Aura", sid = 7294,
      ids = { 7294, 8990, 10298, 10299, 10300, 10301, 13008 } },
    { class = "PALADIN", name = "Concentration Aura", sid = 19746,
      ids = { 19746 } },
    { class = "PALADIN", name = "Sanctity Aura", sid = 20218,
      ids = { 20218 } },
    { class = "PALADIN", name = "Fire Resistance Aura", sid = 19891,
      ids = { 19891, 19899, 19900 } },
    { class = "PALADIN", name = "Frost Resistance Aura", sid = 19888,
      ids = { 19888, 19897, 19898 } },
    { class = "PALADIN", name = "Shadow Resistance Aura", sid = 19876,
      ids = { 19876, 19895, 19896 } },
    { class = "PALADIN", name = "Light's Vigil", sid = 1310909,
      ids = { 1310909, 1310911, 1311590, 1311593, 1311595, 1311597 } },
    -- PRIEST (8)
    { class = "PRIEST", name = "Power Word: Fortitude", sid = 1243,
      ids = { 1243, 1244, 1245, 2791, 10937, 10938 } },
    { class = "PRIEST", name = "Prayer of Fortitude", sid = 21562,
      ids = { 21562, 21564, 450086 } },
    { class = "PRIEST", name = "Divine Spirit", sid = 14752,
      ids = { 14752, 14818, 14819, 27841 } },
    { class = "PRIEST", name = "Prayer of Spirit", sid = 27681,
      ids = { 27681 } },
    { class = "PRIEST", name = "Shadow Protection", sid = 976,
      ids = { 976, 10957, 10958 } },
    { class = "PRIEST", name = "Prayer of Shadow Protection", sid = 27683,
      ids = { 27683 } },
    { class = "PRIEST", name = "Renew", sid = 139,
      ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315,
              27606, 425268, 425269, 425270, 425271, 425272, 425273, 425274,
              425275, 425276, 425277 } },
    { class = "PRIEST", name = "Prayer of Mending", sid = 401859,
      ids = { 401859, 401877, 1240826, 1240827, 1240848, 1240849 } },
}

-- Swiftmendable (plan 15.1): the pseudo entry configures the feature and
-- carries no aura of its own (BF:GetSingleBuffSpellID returns nil for it), so
-- foreverSpellIDs is not set; its runtime IDs are BF.Forever.SWIFTMENDABLE_IDS.
local PSEUDO_SEEDS = {
    { kind = "swiftmendable", sid = 18562, name = "Swiftmendable", class = "DRUID" },
}

-- The 9 Forever classes, used for "every other class OFF". Normally
-- BF.Forever.CLASSES (from CLASS_SORT_ORDER); the literal list is only the
-- fallback for a client that does not expose CLASS_SORT_ORDER.
local FALLBACK_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- loadClassTypes with only `class` ON: every other class explicitly false
-- (absent = ON, the Spec condition's convention).
local function OnlyClass(class)
    local t = {}
    local list = F.CLASSES
    if type(list) == "table" and #list > 0 then
        for i = 1, #list do
            local token = list[i].token
            if token ~= class then t[token] = false end
        end
    else
        for i = 1, #FALLBACK_CLASSES do
            local token = FALLBACK_CLASSES[i]
            if token ~= class then t[token] = false end
        end
    end
    return t
end

local function CopyIDs(ids)
    local out = {}
    for i = 1, #ids do out[i] = ids[i] end
    table.sort(out)
    return out
end

local function SeedName(sid, fallback)
    return (BF.SpellDisplayName and BF.SpellDisplayName(sid, fallback))
        or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid))
        or fallback or tostring(sid)
end

-- Seed once per profile. The entry shape mirrors _AuraMig_CuratedSpells
-- (Core_Migrations.lua) field for field -- an inert Show (Default Buff) entry
-- anchored to Buffs, inheriting the Buffs icon size -- with the Class
-- condition in place of the Spec condition and the rank IDs added. Own Only:
-- containerCasterScope is left nil ("mine"), as CreateSingleBuffContainer
-- stores it.
function F.SeedBuffList(acp)
    if type(acp) ~= "table" then return end
    if acp._foreverBuffListSeedV1 then return end
    acp._foreverBuffListSeedV1 = true

    local containers = acp.customBuffContainers
    if type(containers) ~= "table" then
        containers = {}
        acp.customBuffContainers = containers
    end

    -- Do not duplicate an entry the profile already holds (an imported
    -- Forever profile, or a re-run on a restored sentinel).
    local held, pseudoHeld = {}, {}
    for _, c in ipairs(containers) do
        if type(c) == "table" and c.singleBuff then
            if c.pseudoKind then
                pseudoHeld[c.pseudoKind] = true
            elseif type(c.singleBuffSpellID) == "number" then
                held[c.singleBuffSpellID] = true
            end
        end
    end

    local seeds = F.BUFF_LIST_SEEDS
    for i = 1, #seeds do
        local seed = seeds[i]
        if not held[seed.sid] then
            held[seed.sid] = true
            containers[#containers + 1] = {
                singleBuff        = true,
                maxBuffs          = 1,
                singleBuffSpellID = seed.sid,
                singleBuffKey     = BF:NewSingleBuffKey(seed.sid, containers),
                foreverSpellIDs   = CopyIDs(seed.ids),
                selectedSpells    = {},
                name              = SeedName(seed.sid, seed.name),
                autoNamed         = false,
                loadClass         = true,
                loadClassTypes    = OnlyClass(seed.class),
                anchorPoint       = "BUFFS",
                sbRelativeOrder   = "BEFORE",
                -- Show (Default Buff): `false`, not nil (nil = Customized).
                singleBuffCustomized = false,
                containerUsesBuffSettings = true,
            }
        end
    end

    for i = 1, #PSEUDO_SEEDS do
        local seed = PSEUDO_SEEDS[i]
        if not pseudoHeld[seed.kind] then
            containers[#containers + 1] = {
                singleBuff        = true,
                pseudoKind        = seed.kind,
                maxBuffs          = 1,
                singleBuffSpellID = seed.sid,
                singleBuffKey     = BF:NewSingleBuffKey(seed.sid, containers),
                selectedSpells    = {},
                name              = seed.name,
                autoNamed         = false,
                -- Descriptive pin, like the Retail pseudo entry's loadSpec:
                -- the runtime gate is BF.Forever.IsSwiftmendableActive.
                loadClass         = true,
                loadClassTypes    = OnlyClass(seed.class),
                anchorPoint       = "BUFFS",
                sbRelativeOrder   = "BEFORE",
                singleBuffCustomized = false,
                containerUsesBuffSettings = true,
            }
        end
    end
end

-- ── R2 accessor, Forever half ──────────────────────────────────────────────
-- map = { [id] = true } for the primary sid plus every c.foreverSpellIDs ID;
-- sig = the sorted IDs joined with "," (just tostring(sid) for a one-ID
-- entry, the same as Retail). Cached per ENTRY table (weak keys: a profile
-- swap drops the old entries with their cache), revalidated by three O(1)
-- compares -- primary id, foreverSpellIDs table identity, its length -- so an
-- edit that replaces or resizes the list rebuilds on the next read with no
-- explicit invalidation. An in-place edit that keeps the length must call
-- BF.Forever.InvalidateSingleBuffSpellSet(c). Every frame of a Layout pass
-- reuses the same map; nothing is allocated per frame or per UNIT_AURA.
local _setCache = setmetatable({}, { __mode = "k" })

function F.GetSingleBuffSpellSet(c, sid)
    local ids = c.foreverSpellIDs
    if type(ids) ~= "table" then ids = nil end
    local n = ids and #ids or 0
    local e = _setCache[c]
    if e and e.sid == sid and e.src == ids and e.n == n then
        return e.map, e.sig
    end
    local map, list = { [sid] = true }, { sid }
    if ids then
        for i = 1, n do
            local id = ids[i]
            if type(id) == "number" and id > 0 and not map[id] then
                map[id] = true
                list[#list + 1] = id
            end
        end
    end
    table.sort(list)
    local sig = (#list == 1) and tostring(sid) or table.concat(list, ",")
    _setCache[c] = { sid = sid, src = ids, n = n, map = map, sig = sig }
    return map, sig
end

function F.InvalidateSingleBuffSpellSet(c)
    if c then _setCache[c] = nil end
end

-- ── Add by spell ID (BF:CreateSingleBuffContainer hooks) ──────────────────
-- Owner ruling 2026-11-06: the entry's primary ID is the LOWEST RANK of the
-- typed spell's rank set (rank NUMBER, the seeds' rule -- Battle Shout's rank
-- 1 is 6673, not the lower-numbered 5242), and every rank goes in
-- c.foreverSpellIDs.
--
-- Rank number, in order of trust:
--   1. a seeded entry (BUFF_LIST_SEEDS) holding the ID -> its curated sid;
--   2. the client's own rank text, C_Spell.GetSpellSubtext -> "Rank N";
--   3. neither known for any ID -> the lowest spell ID (the only order left).
-- Options time only (one call per add); never on a runtime path.
local GetSpellSubtext = C_Spell and C_Spell.GetSpellSubtext

local function RankNumber(id)
    local sub = GetSpellSubtext and GetSpellSubtext(id)
    local n = type(sub) == "string" and tonumber(sub:match("(%d+)"))
    return n
end

local function SeedPrimaryFor(id)
    local seeds = F.BUFF_LIST_SEEDS
    for i = 1, #seeds do
        local ids = seeds[i].ids
        for j = 1, #ids do
            if ids[j] == id then return seeds[i].sid end
        end
    end
    return nil
end

-- typed ID -> primaryID, ranks (sorted array, includes primaryID).
function F.ResolveAddedSpell(sid)
    if type(sid) ~= "number" then return sid, nil end
    local ranks = F.ExpandSpellToRanks and F.ExpandSpellToRanks(sid) or { sid }
    local primary = SeedPrimaryFor(sid)
    if not primary then
        local bestN
        for i = 1, #ranks do
            local n = RankNumber(ranks[i])
            if n and (bestN == nil or n < bestN
                      or (n == bestN and ranks[i] < primary)) then
                bestN, primary = n, ranks[i]
            end
        end
    end
    primary = primary or ranks[1] or sid   -- ranks is sorted ascending
    local found = false
    for i = 1, #ranks do if ranks[i] == primary then found = true; break end end
    if not found then
        ranks[#ranks + 1] = primary
        table.sort(ranks)
    end
    return primary, ranks
end

-- Fills c.foreverSpellIDs after creation. `ranks` comes from
-- ResolveAddedSpell; without it the set is expanded from sid.
function F.OnSingleBuffCreated(c, sid, ranks)
    if type(c) ~= "table" or type(sid) ~= "number" then return end
    if type(ranks) ~= "table" then
        ranks = F.ExpandSpellToRanks and F.ExpandSpellToRanks(sid) or { sid }
    end
    c.foreverSpellIDs = ranks
    _setCache[c] = nil
end
