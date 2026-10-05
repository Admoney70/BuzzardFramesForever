local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

-- Spell IDs for aura filtering
BF.SATED_SPELL_IDS = {
    [57723]  = true,  -- Exhaustion (Shaman)
    [57724]  = true,  -- Sated (Mage)
    [80354]  = true,  -- Temporal Displacement (Mage)
    [95809]  = true,  -- Insanity (Hunter pet)
    [160455] = true,  -- Fatigued (Hunter pet)
    [264689] = true,  -- Fatigued (Hunter pet)
}
BF.DESERTER_SPELL_IDS = {
    [26013]  = true,  -- Deserter (BG)
    [71041]  = true,  -- Dungeon Deserter
}
-- (DEBUFF_BLACKLIST removed: its only entry, Challenger's Burden, no
-- longer exists in Midnight, and the table had no remaining consumers.)
-- Raid buff spell IDs per class, used for the "missing buff" indicator.
-- Keyed by UnitClassBase() return value (uppercase English class name).
-- Each entry is a single spell ID (number).
BF.CLASS_RAID_BUFF = {
    ["DRUID"]   = 1126,    -- Mark of the Wild
    ["PRIEST"]  = 21562,   -- Power Word: Fortitude
    ["WARRIOR"] = 6673,    -- Battle Shout
    ["MAGE"]    = 1459,    -- Arcane Intellect
}

-- Per-spec raid buff spell IDs to show out of combat when the Raid Buffs setting is on.
-- Only list spells that are actually cast by that spec.
BF.SPEC_RAID_BUFF_IDS = {
    -- Druid
    [105] = { [1126] = true },     -- Restoration: Mark of the Wild
    [102] = { [1126] = true },     -- Balance: Mark of the Wild
    [103] = { [1126] = true },     -- Feral: Mark of the Wild
    [104] = { [1126] = true },     -- Guardian: Mark of the Wild
    -- Priest
    [256] = { [21562] = true },    -- Discipline: Power Word: Fortitude
    [257] = { [21562] = true },    -- Holy: Power Word: Fortitude
    [258] = { [21562] = true },    -- Shadow: Power Word: Fortitude
    -- Warrior
    [71]  = { [6673] = true },     -- Arms: Battle Shout
    [72]  = { [6673] = true },     -- Fury: Battle Shout
    [73]  = { [6673] = true },     -- Protection: Battle Shout
    -- Mage
    [62]  = { [1459] = true },     -- Arcane: Arcane Intellect
    [63]  = { [1459] = true },     -- Fire: Arcane Intellect
    [64]  = { [1459] = true },     -- Frost: Arcane Intellect
}

-- ============================================================
-- MASTER SPELL TABLE
--
-- Single source of truth for all tracked spells, shared with
-- Options_CustomAuras.lua via BF.SPEC_SPELLS.
--
-- Each entry: { id=spellID, name="Spell Name", untracked=true|nil }
--   untracked=true  -> hidden by default; user can promote to Default or a container
--   untracked=nil   -> shown in regular buffFrames by default
--
-- profile.spellAssign[specId][sid]:
--   nil         = not added by user (untracked spells are suppressed)
--   "default"   = show in regular buffFrames
--   "untracked" = suppress entirely
--   "c:N"       = assigned to container index N
-- ============================================================
BF.SPEC_SPELLS = {
    [256] = {
        { id = 194384,   name = "Atonement"          },
        { id = 17,       name = "Power Word: Shield", icon = "Interface/Icons/Spell_Holy_PowerWordShield" },
        { id = 41635,    name = "Prayer of Mending"  },
        { id = 1253593,  name = "Void Shield"        },
        { id = 10060,    name = "Power Infusion" },
    },
    [65] = {
        { id = 156910,   name = "Beacon of Faith",      noDuration = true },
        { id = 53563,    name = "Beacon of Light",      noDuration = true },
        { id = 1244893,  name = "Beacon of the Savior", noDuration = true },
        { id = 200025,   name = "Beacon of Virtue"     },
        { id = 156322,   name = "Eternal Flame"        },
        -- v70: plain spell-ID rows. These were "secret detection" entries
        -- (elimination-by-fingerprint, hero-tree resolution, Holy Bulwark
        -- aliased onto Holy Armaments) — 12.0.7-era machinery for auras
        -- whose spellId was secret. On 12.1 they match by spell ID like
        -- every other aura, so the flags, the alias, and the hero-tree
        -- split are gone; Sacred Weapon and Holy Bulwark are ordinary
        -- separate rows now.
        -- class: these auras are absent from the SpellSearch dataset
        -- (ns.SpellData.BYID) that normally supplies the class token for
        -- list coloring — stated explicitly instead (classColorSpellName's
        -- curated fallback).
        { id = 1044,     name = "Blessing of Freedom", class = "PALADIN" },
        { id = 431381,   name = "Dawnlight",           class = "PALADIN" },
        { id = 432502,   name = "Sacred Weapon",       class = "PALADIN" },
        { id = 432496,   name = "Holy Bulwark",        class = "PALADIN" },
    },
    [257] = {
        { id = 41635,    name = "Prayer of Mending" },
        { id = 139,      name = "Renew"             },
        { id = 77489,    name = "Echo of Light",    untracked = true },
        { id = 10060,    name = "Power Infusion" },
    },
    [105] = {
        { id = 33763,    name = "Lifebloom"        },
        { id = 8936,     name = "Regrowth"         },
        { id = 774,      name = "Rejuvenation"     },
        { id = 155777,   name = "Rejuvenation (Germination)" },
        { id = 439530,   name = "Symbiotic Blooms", untracked = true },
        { id = 48438,    name = "Wild Growth"      },
    },
    [264] = {
        { id = 974,      name = "Earth Shield"       },
        { id = 383648,   name = "Earth Shield (Self)" },
        { id = 61295,    name = "Riptide"             },
        { id = 207400,   name = "Ancestral Vigor",    untracked = true },
        { id = 382024,   name = "Earthliving Weapon", untracked = true },
        { id = 444490,   name = "Hydrobubble",        untracked = true },
    },
}

-- ── v65: DISPLAY NAME OVERRIDES ───────────────────────────────────────────
-- Some spells share a name with another spell in the same list, so the name
-- the game returns cannot tell them apart.
--
-- Restoration Shaman's self-cast Earth Shield is a SEPARATE aura with its own
-- spell ID, and the API returns the same name for both. Every list is built
-- from the API name, because that is the localized one, so this overrides
-- only where the API is ambiguous.
--
-- Add an entry here whenever two curated spells collide on name; nothing else
-- needs changing.
BF.SPELL_DISPLAY_NAME_OVERRIDES = {
    [383648] = "Earth Shield (Self)",   -- self-cast copy of 974 Earth Shield
}

-- The name to show for a spell: the override when one exists, else the game's
-- own name, else the id. `fallback` lets a caller supply a name it already has
-- (the curated table's, say) for when the API has not cached the spell yet.
function BF.SpellDisplayName(spellID, fallback)
    if type(spellID) ~= "number" then return fallback end
    local o = BF.SPELL_DISPLAY_NAME_OVERRIDES[spellID]
    if o then return o end
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
        or fallback or tostring(spellID)
end