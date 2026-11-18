local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_SpellData_Buffs.lua  (WoW Forever only)
--
-- The Forever buff spell list: what the Buff List "Spell Name or ID" search
-- suggests on Forever, and the source of BF.Forever.ExpandSpellToRanks (add by
-- spell ID adds every same-name rank). It does NOT seed the Buff List -- that
-- is Forever_BuffList.lua (plan section 17).
--
-- SpellSearch/SpellData_Buffs.lua swaps its Retail SPELLS table for
-- BF.Forever.BUFF_SPELLS through one `-- [FOREVER]` hook; the shared
-- ns.SpellData engine (Flatten / BYID / BuildSpellList) is untouched. This
-- file therefore loads immediately BEFORE SpellSearch\SpellData_Buffs.lua.
--
-- Source: Grid2's GridPlayerSpellsForever.lua (Grid2 is distributed under the
-- zlib/libpng license), with the corrections checked in the Forever client
-- tables, build 1.60.1.70790 (plan sections 12.4 and 13, owner ruling Q6):
--   * 1038 Blessing of Salvation dropped (not in the Forever client).
--   * Nature's Swiftness: SHAMAN 16188, DRUID 17116 only (29274 dropped: no
--     skill line, no talent -- not a player spell).
--   * Enrage: DRUID 5229 (Feral Combat), WARRIOR 12880 (the buff the Enrage
--     talent 12317 applies). 1640 dropped (no class).
--
-- ENTRY FORMAT (same as SpellData_Buffs.lua): a plain spellID, or
-- { spellID, "Category" }. Every entry needs its trailing comma. Example:
--
--     ["PRIEST"] = {
--         { 10060, "Healer Utility" },         -- Power Infusion
--         { 17, "Personal Defensive" }, 592,  -- Power Word: Shield ranks
--     },
--
-- Categories render as a gold suffix in the search rows; "Personal
-- Defensive" / "External Defensive" also drive the defensive groups, and
-- "Healer Buff" / "Personal Buff" / "Personal Defensive" make an added entry
-- default to Own Only. Same-named IDs are ranks of one buff.
-- ============================================================

local F = BF.Forever

F.BUFF_SPELLS = {
    [""] = {
    },
    ["WARRIOR"] = {
        20230, 20240, 22857, 22858, -- Retaliation
        1719, 13847, -- Recklessness
        12880, -- Enrage (buff of the Enrage talent 12317)
        2565, 12169, -- Shield Block
        12322, 12964, -- Unbridled Wrath
        12975, 12976, -- Last Stand
        12328, -- Death Wish
        2458, 7366, -- Berserker Stance
        71, 7164, -- Defensive Stance
        5242, 6192, 6673, 11549, 11550, 11551, 25289, 27578, -- Battle Shout
        871, 15062, 29061, -- Shield Wall
        9941, 9943, 10074, 11818, 21118, -- Spell Reflection
        18499, -- Berserker Rage
        2457, 7165, -- Battle Stance
        12318, 12857, 12858, 12860, 12861, -- Improved Battle Shout
    },
    ["PALADIN"] = {
        642, 1020, 13874, -- Divine Shield
        20177, 20178, -- Reckoning
        20165, 20167, 20333, 20334, 20340, 20347, 20348, 20349, -- Seal of Light
        19746, -- Concentration Aura
        7294, 8990, 10298, 10299, 10300, 10301, 13008, -- Retribution Aura
        19891, 19899, 19900, -- Fire Resistance Aura
        25780, -- Righteous Fury
        864, -- Seal of Righteousness
        9800, -- Holy Shield
        19740, 19834, 19835, 19836, 19837, 19838, 25291, -- Blessing of Might
        465, 643, 1032, 10290, 10291, 10292, 10293, -- Devotion Aura
        20217, -- Blessing of Kings
        23214, -- Summon Charger
        20116, 20922, 20923, 20924, 26573, -- Consecration
        498, 5573, 13007, -- Divine Protection
        1044, -- Blessing of Freedom
        6940, 20729, -- Blessing of Sacrifice
        1022, 5599, 10278, -- Blessing of Protection
        20042, 20045, 20046, 20047, 20048, -- Improved Blessing of Might
    },
    ["MAGE"] = {
        10, 6141, 8427, 10185, 10186, 10187, 27618, -- Blizzard
        6117, 22782, 22783, -- Mage Armor
        11426, 13031, 13032, 13033, -- Ice Barrier
        48108, -- Hot Streak
        12536, -- Clearcasting
        506, -- Ice Armor
        12042, -- Arcane Power
        1463, 8494, 8495, 10191, 10192, 10193, -- Mana Shield
        12472, -- Cold Snap
        12051, -- Evocation
        543, 8457, 8458, 10223, 10225, -- Fire Ward
        130, 12438, -- Slow Fall
        1459, 1460, 1461, 10156, 10157, 16876, -- Arcane Intellect
        66, -- Lesser Invisibility
        1953, 14514, 21655, 28391, 29208, 29209, 29210, 29211, -- Blink
        12043, -- Presence of Mind
        475, -- Remove Lesser Curse
    },
    ["PRIEST"] = {
        17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 22187, 27607, -- Power Word: Shield
        6346, -- Fear Ward
        1706, 27986, -- Levitate
        7001, 27873, 27874, -- Lightwell Renew
        15286, 15290, -- Vampiric Embrace
        586, 9578, 9579, 9592, 10941, 10942, 12685, -- Fade
        588, 602, 1006, 7128, 10951, 10952, -- Inner Fire
        20711, -- Spirit of Redemption
        10060, -- Power Infusion
        15473, -- Shadowform
        14892, -- Inspiration
        14751, -- Inner Focus
        21562, 21564, -- Prayer of Fortitude
        139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315, 27606, -- Renew
        14749, 14767, -- Improved Power Word: Fortitude
    },
    ["WARLOCK"] = {
        7870, -- lesser invisibility
        711, -- Hellfire
        20707, 20762, 20763, 20764, 20765, -- Soulstone Resurrection
        689, 699, 709, 7651, 11699, 11700, -- Drain Life
        5740, 6219, 11677, 11678, 19474, -- Rain of Fire
        5697, -- Unending Breath
    },
    ["SHAMAN"] = {
        546, -- Water Walking
        16188, -- Nature's Swiftness (Restoration talent)
        30802, 30803, 30804, 30805, 30806, 30807, 30808, 30809, 30810, 30811, -- Unleashed Rage
        16246, -- Clearcasting
        379, -- Earth Shield
        324, 325, 905, 945, 8134, 10431, 10432, -- Lightning Shield
        519, -- Ghost Wolf
        5394, 6375, 6377, 10462, 10463, -- Healing Stream Totem
        8178, -- Grounding Totem Effect
        8512, 8515, 10609, 10612, 10613, 10614, 27621, -- Windfury Totem
        29192, 29193, -- Improved Weapon Totems
    },
    ["DRUID"] = {
        16870, -- Clearcasting
        20655, -- Barkskin
        5215, 6783, 9913, -- Prowl
        1126, 5232, 5234, 6756, 8907, 9884, 9885, 16878, 24752, -- Mark of the Wild
        16914, 17401, 17402, 27530, -- Hurricane
        783, -- Travel Form
        24907, -- Moonkin Aura
        24858, -- Moonkin Form
        17056, 17057, -- Furor
        16880, 16886, -- Nature's Grace
        740, 8918, 9862, 9863, -- Tranquility
        499, -- Cat Form
        5217, -- Tiger's Fury
        5229, -- Enrage (Feral Combat)
        774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, -- Rejuvenation
        1850, 9821, 23099, 23109, 23110, -- Dash
        8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, -- Regrowth
        16689, 16810, 16811, 16812, 16813, 17329, -- Nature's Grasp
        17007, 24932, -- Leader of the Pack
        5487, 7090, 18309, 19030, 27543, -- Bear Form
        17116, -- Nature's Swiftness (Restoration talent)
        29166, -- Innervate
        467, 782, 1075, 8914, 9756, 9910, 16877, -- Thorns
        17050, 17051, 17053, 17054, 17055, -- Improved Mark of the Wild
    },
    ["ROGUE"] = {
        1966, 6768, 8637, 11303, 25302, -- Feint
        13750, -- Adrenaline Rush
        5171, 6774, -- Slice and Dice
        2983, 8696, 11305, -- Sprint
        4086, 5277, 15087, -- Evasion
        1784, 1785, 1786, 1787, -- Stealth
        13877, -- Blade Flurry
    },
    ["HUNTER"] = {
        20043, 20190, -- Aspect of the Wild
        136, 3111, 3661, 3662, 13542, 13543, 13544, -- Mend Pet
        7093, -- Intimidation
        13159, -- Aspect of the Pack
        982, 23499, -- Revive Pet
        3045, -- Rapid Fire
        5118, -- Aspect of the Cheetah
        19574, -- Bestial Wrath
        13165, 14318, 14319, 14320, 14321, 14322, 25296, -- Aspect of the Hawk
        5225, -- Track Humanoids
        1462, -- Beast Lore
        19263, -- Deterrence
        1299346, 1299348, 19506, 20905, 20906, -- Trueshot Aura
    },
}

-- ── Rank expansion (Grid2 GetSimilarPlayerBuffs pattern) ───────────────────
-- A Forever buff only matches if its exact rank ID is whitelisted, so adding a
-- buff by ID has to add every rank. Ranks are grouped by spell NAME, within
-- the class the ID is listed under (Nature's Swiftness has the same name for
-- Shaman and Druid). The name index also takes in the seeded Buff List IDs
-- (BF.Forever.BUFF_LIST_SEEDS, Forever_BuffList.lua), so adding e.g.
-- Rejuvenation by hand holds the same IDs as the seeded entry.
--
-- Built lazily on the first call (options time: one GetSpellName per listed
-- ID, once per session), never at load and never in combat paths.
local GetSpellName = C_Spell and C_Spell.GetSpellName
local _byClassName, _byName, _classOf

local function IndexAdd(class, id)
    if type(id) ~= "number" then return end
    local name = GetSpellName and GetSpellName(id)
    if not name then return end
    if _classOf[id] == nil then _classOf[id] = class end
    local ck = class .. "\0" .. name
    local t = _byClassName[ck]
    if not t then t = {}; _byClassName[ck] = t end
    if not t[id] then t[id] = true; t[#t + 1] = id end
    local u = _byName[name]
    if not u then u = {}; _byName[name] = u end
    if not u[id] then u[id] = true; u[#u + 1] = id end
end

local function BuildRankIndex()
    _byClassName, _byName, _classOf = {}, {}, {}
    for class, list in pairs(F.BUFF_SPELLS) do
        for i = 1, #list do
            local raw = list[i]
            IndexAdd(class, type(raw) == "table" and raw[1] or raw)
        end
    end
    local seeds = F.BUFF_LIST_SEEDS
    if type(seeds) == "table" then
        for i = 1, #seeds do
            local s = seeds[i]
            if type(s.ids) == "table" then
                for j = 1, #s.ids do IndexAdd(s.class, s.ids[j]) end
            end
        end
    end
end

-- Array of every same-name ID (ascending, always including spellID), or
-- { spellID } when the spell is in neither list. Always a FRESH array: the
-- caller stores it in saved variables.
function F.ExpandSpellToRanks(spellID)
    spellID = tonumber(spellID)
    if not spellID then return {} end
    if not _byClassName then BuildRankIndex() end
    local name = GetSpellName and GetSpellName(spellID)
    local src
    if name then
        local class = _classOf[spellID]
        if class then
            src = _byClassName[class .. "\0" .. name]
        else
            src = _byName[name]
        end
    end
    local out, seen = { spellID }, { [spellID] = true }
    if src then
        for i = 1, #src do
            local id = src[i]
            if not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end
