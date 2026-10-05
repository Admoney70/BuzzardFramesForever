if select(2, ...).IS_LEGACY_CLIENT then return end -- HET-LEGACY-1207: no-op once Legacy1207 is deleted
-------------------------------------------------------------------------------
-- SpellData_Buffs.lua
-- THE curated BUFF spell table + the shared spell-data engine, single source
-- of truth for:
--   * the buff spell search suggestions (SpellSearchBox.lua),
--   * the External Defensives group ("External Defensive" category),
--   * the Personal Defensives group ("Personal Defensive" category).
-- Tagging a spell with one of those categories ADDS it to the matching
-- group's Defensive List (same-named IDs merge into one checkbox row).
--
-- Entry forms: a plain spellID, or { spellID, "Category" }. Every entry
-- needs its trailing comma. Categories render as a gold suffix in the
-- search rows; only the two defensive categories drive group membership.
--
-- Base list: a curated per-class player-buff table plus this addon's own
-- tracked spells.
--
-- This file also owns the shared engine (ns.SpellData) used by the sibling
-- data files SpellData_Debuffs.lua and SpellData_AbilitiesItems.lua. Those
-- register their own class-keyed tables via ns.SpellData.Register(kind, SPELLS).
-- Each "kind" ("buff", "debuff", "ability", "item") gets its own flattened
-- list + by-id lookup (ns.SpellData.KINDS[kind] = { FLAT=, BYID= }). The buff
-- kind's FLAT/BYID are ALSO exposed as ns.SpellData.FLAT/BYID for backward
-- compatibility (the defensive / Bloodlust groups read those).
-------------------------------------------------------------------------------
local addonName, ns = ...

local SPELLS = {
    ["DRUID"] = {
        { 1126, "Raid Buff" },      -- Mark of the Wild
        { 774, "Healer Buff" },     -- Rejuvenation
        { 8936, "Healer Buff" },    -- Regrowth
        { 33763, "Healer Buff" },   -- Lifebloom
        { 48438, "Healer Buff" },   -- Wild Growth
        { 155777, "Healer Buff" },  -- Germination
        { 439530, "Healer Buff" },  -- Symbiotic Blooms (HET)
        { 102342, "External Defensive" }, -- Ironbark (HET)
        { 22812, "Personal Defensive" }, -- Barkskin (HET)
        { 5487, "Personal Buff" }, -- Bear Form (HET)
        { 29166, "Healer Utility" },      -- Innervate (HET)
        { 132158, "Personal Buff" },     -- Nature's Swiftness (HET)
        { 33891, "Personal Buff" },     -- Incarnation: Tree of Life (HET)
        { 16870, "Personal Buff" },     -- Clearcasting (HET)
        { 740, "Personal Buff" },     -- Tranquility (HET)
        { 400126, "Personal Buff" },     -- Forestwalk (HET)
        { 393903, "Personal Buff" },     -- Ursine Vigor (HET)
        { 385787, "Personal Buff" },     -- Matted Fur (HET)
        { 22842, "Personal Buff" },  -- Frenzied Regeneration
        { 5215, "Personal Buff" },     -- Prowl (HET)
        { 114108, "Personal Buff" },  -- Soul of the Forest (HET)
        { 207640, "Personal Buff" },  -- Abundance (HET)
        { 1850, "Movement Buff" },     -- Dash (HET)
        { 252216, "Movement Buff" },     -- Tiger Dash (HET)
        { 77764, "Movement Buff" },     -- Stampeding Roar (HET)
		{ 192081, "Personal Buff" }, -- Ironfur
		{ 61336, "Personal Defensive" }, -- Survival Instincts
    },
    ["HUNTER"] = {
        260286, -- Tip of the Spear
        { 264667, "Bloodlust" }, -- Primal Rage (pet)
        { 466904, "Bloodlust" }, -- Harrier's Cry (Marksmanship)
		{ 264735, "Personal Defensive" }, -- Survival of the Fittest
		{ 186265, "Personal Defensive" }, -- Aspect of the Turtle
    },
    ["MAGE"] = {
        { 1459, "Raid Buff" }, -- Arcane Intellect
        { 80353, "Bloodlust" }, -- Time Warp
        205473, -- Icicles
		{ 235313, "Personal Defensive" }, -- Blazing Barrier
		{ 11426, "Personal Defensive" }, -- Ice Barrier
		{ 414658, "Personal Defensive" }, -- Ice Cold
		{ 235450, "Personal Defensive" }, -- Prismatic Barrier
    },
    ["PALADIN"] = {
        { 53563, "Healer Buff" },   -- Beacon of Light
        { 156322, "Healer Buff" },  -- Eternal Flame
        { 156910, "Healer Buff" },  -- Beacon of Faith
        { 200025, "Healer Buff" },  -- Beacon of Virtue
        { 1244893, "Healer Buff" }, -- Beacon of the Savior
        433568, -- Rite of Sanctification
        433583, -- Rite of Adjuration
        { 6940, "External Defensive" },   -- Blessing of Sacrifice (HET)
        { 1022, "External Defensive" },   -- Blessing of Protection (HET)
        { 204018, "External Defensive" }, -- Blessing of Spellwarding (HET)
        { 31821, "External Defensive" },  -- Aura Mastery (HET)
		{ 209388, "Personal Buff" }, -- Bulwark of Order
		{ 403876, "Personal Defensive" }, -- Divine Protection
		{ 498, "Personal Defensive" }, -- Divine Protection
		{ 393108, "Personal Buff" }, -- Guardian of Ancient Kings
		{ 86659, "Personal Buff" }, -- Guardian of Ancient Kings
		{ 132403, "Personal Buff" }, -- Shield of the Righteous
		{ 642, "Personal Defensive" }, -- Divine Shield
    },
    ["PRIEST"] = {
        { 21562, "Raid Buff" },    -- Power Word: Fortitude
        { 17, "Healer Buff" },     -- Power Word: Shield
        { 194384, "Healer Buff" }, -- Atonement
        { 1253593, "Healer Buff" }, -- Void Shield
        { 139, "Healer Buff" },    -- Renew
        { 41635, "Healer Buff" },  -- Prayer of Mending
        { 77489, "Healer Buff" },  -- Echo of Light
        { 33206, "External Defensive" }, -- Pain Suppression (HET)
        { 47788, "External Defensive" }, -- Guardian Spirit (HET)
        { 10060, "Offensive Buff" },     -- Power Infusion (HET)
		{ 586, "Personal Buff" }, -- Fade
		{ 19236, "Personal Defensive" }, -- Desperate Prayer
    },
    ["ROGUE"] = {
        2823,   -- Deadly Poison
        8679,   -- Wound Poison
        3408,   -- Crippling Poison
        5761,   -- Numbing Poison
        315584, -- Instant Poison
        381637, -- Atrophic Poison
        381664, -- Amplifying Poison
		{ 31224, "Personal Defensive" }, -- Cloak of Shadows
		{ 5277, "Personal Defensive" }, -- Evasion
		{ 1966, "Personal Defensive" }, -- Feint
    },
    ["SHAMAN"] = {
        { 2825, "Bloodlust" },  -- Bloodlust (Horde)
        { 32182, "Bloodlust" }, -- Heroism (Alliance)
        { 974, "Healer Buff" }, { 383648, "Healer Buff" }, -- Earth Shield
        { 61295, "Healer Buff" }, -- Riptide
        319773, -- Windfury Weapon
        319778, -- Flametongue Weapon
        382024, -- Earthliving Weapon
        457496, 457481, -- Tidecaller's Guard
        462757, 462742, -- Thunderstrike Ward
        344179, -- Maelstrom Weapon
        { 207400, "Healer Buff" }, -- Ancestral Vigor
        { 444490, "Healer Buff" }, -- Hydrobubble
		{ 108271, "Personal Defensive" }, -- Astral Shift
		{ 198103, "Personal Buff" }, -- Earth Elemental
    },
    ["WARLOCK"] = {
		{ 20707, "Personal Buff" }, -- Soulstone
		{ 104773, "Personal Defensive" }, -- Unending Resolve
    },
    ["WARRIOR"] = {
        { 6673, "Raid Buff" }, -- Battle Shout
        { 97462, "External Defensive" }, -- Rallying Cry cast (HET)
        { 97463, "External Defensive" }, -- Rallying Cry buff (HET, PTR-VERIFY)
		{ 118038, "Personal Buff" }, -- Die by the Sword
		{ 184364, "Personal Defensive" }, -- Enraged Regeneration
		{ 190456, "Personal Buff" }, -- Ignore Pain 
		{ 132404, "Personal Buff" }, -- Shield Block
		{ 23920, "Personal Defensive" }, -- Spell Reflection
		{ 385391, "Personal Defensive" }, -- Spell Reflection
		{ 12975, "Personal Buff" }, -- Last Stand
		{ 871, "Personal Buff" }, -- Shield Wall
    },
}

local CLASS_ORDER = {
    "", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN",
    "WARLOCK", "WARRIOR",
}

-- Flatten a class-keyed SPELLS table (class order preserved) into a flat
-- list + by-id lookup. Entries: { id=, class=, cat= }. Shared by every kind.
-- Entry forms in the source list: a plain spellID, or { spellID, "Category" }.
local function Flatten(spells)
    local flat, byid = {}, {}
    for _, class in ipairs(CLASS_ORDER) do
        local list = spells[class]
        if list then
            for j = 1, #list do
                local raw = list[j]
                local id, cat
                if type(raw) == "table" then
                    id, cat = raw[1], raw[2]
                else
                    id = raw
                end
                local entry = { id = id, class = class, cat = cat }
                flat[#flat + 1] = entry
                if not byid[id] then byid[id] = entry end
            end
        end
    end
    return flat, byid
end

-- Per-kind registry. The buff kind is built here from this file's SPELLS; the
-- debuff / ability / item kinds register themselves from their own files.
local KINDS = {}
local function Register(kind, spells)
    local flat, byid = Flatten(spells)
    KINDS[kind] = { SPELLS = spells, FLAT = flat, BYID = byid }
    return KINDS[kind]
end

-- Buff kind (this file). Its FLAT/BYID double as the top-level, backward-
-- compatible ns.SpellData.FLAT/BYID consumed by the defensive/Bloodlust
-- group builders and the buff search predictor.
local buffKind = Register("buff", SPELLS)
local FLAT, BYID = buffKind.FLAT, buffKind.BYID

-- Build a tracker spellList from a category: same-named IDs merge into
-- one entry (one checkbox, all its IDs tracked — e.g. Rallying Cry cast
-- + buff), alphabetical by name, key = first spell ID (locale-stable).
-- clips: optional map [spellID] = { clip, clipShort } (Media\Audio\Voice_*).
-- opts.perClass: NO name merging — every ID gets its own entry labeled
-- "Name (Class)" with the class name in class color (one row per
-- class). Sorting uses the UNCOLORED "Name Class" string so
-- escape codes never drive the order.
local GetSpellName = C_Spell.GetSpellName

-- "|cff<class color>Localized Class|r", plus the plain string for
-- sorting. nil for class-less entries.
local function ClassColoredName(class)
    if not class or class == "" then return nil end
    local plain = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class])
        or class
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc and cc.colorStr then
        return "|c" .. cc.colorStr .. plain .. "|r", plain
    end
    return plain, plain
end

local function BuildSpellList(category, clips, opts)
    local perClass = opts and opts.perClass
    local byName, order = {}, {}
    for j = 1, #FLAT do
        local e = FLAT[j]
        if e.cat == category then
            local name = GetSpellName(e.id) or ("#" .. e.id)
            if perClass then
                local colored, plain = ClassColoredName(e.class)
                local rec = {
                    key      = e.id,
                    name     = colored and (name .. " (" .. colored .. ")") or name,
                    sortName = plain and (name .. " " .. plain) or name,
                    class    = e.class,
                    ids      = { e.id },
                }
                local c = clips and clips[e.id]
                if c then rec.clip, rec.clipShort = c[1], c[2] end
                order[#order + 1] = rec
            else
                local rec = byName[name]
                if not rec then
                    rec = { key = e.id, name = name, ids = {} }
                    byName[name] = rec
                    order[#order + 1] = rec
                end
                rec.ids[#rec.ids + 1] = e.id
                local c = clips and clips[e.id]
                if c and not rec.clip then
                    rec.clip, rec.clipShort = c[1], c[2]
                end
            end
        end
    end
    table.sort(order, function(a, b)
        return (a.sortName or a.name) < (b.sortName or b.name)
    end)
    return order
end

ns.SpellData = {
    SPELLS = SPELLS,            -- buff SPELLS (backward compat)
    CLASS_ORDER = CLASS_ORDER,
    FLAT = FLAT,                -- buff FLAT (backward compat)
    BYID = BYID,                -- buff BYID (backward compat)
    BuildSpellList = BuildSpellList,
    -- Shared engine for the sibling data files:
    Flatten = Flatten,         -- (spells) -> flat, byid
    Register = Register,       -- (kind, spells) -> { SPELLS, FLAT, BYID }
    KINDS = KINDS,             -- KINDS[kind] = { SPELLS, FLAT, BYID }
}
