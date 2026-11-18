local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_Preview.lua  (WoW Forever only)
--
-- Previews and Custom Frame Groups use only the 9 Forever classes (plan
-- sections 7 F13 and 15.1), so previews match live frames (owner rule).
--
--   F.CLASS_SORT_ORDER_ALPHA
--       The 9 Forever class tokens, alphabetical. Replaces
--       BF.CLASS_SORT_ORDER_ALPHA on Forever (via F.ApplyCustomFrameClassLists)
--       for the Custom Frame Groups class filter, its "all classes"
--       fallback, the grouping order and the options page's class switches.
--
--   F.ApplyPreviewRoster(list)
--       Called on Forever by Preview/PreviewData.lua and
--       Preview/PreviewSystem.lua right after their fake-unit tables are
--       built. Rewrites, IN PLACE, every entry whose class Forever lacks
--       (Death Knight, Demon Hunter, Evoker, Monk) to a Forever class that
--       can fill the SAME role, so every roster keeps Retail's tank / healer
--       / damage mix (raid: 4 tanks, 3 healers, 3 damage). Pure-damage
--       classes cannot fill a tank or healer slot, so the 10-entry raid
--       roster cannot hold all 9 classes with that mix: it shows 8 (Shaman
--       moves to a healer slot so Hunter can take its damage slot), and the
--       Custom Frame Groups roster supplies the Rogue. Between the two
--       rosters all 9 Forever classes appear.
--
--   F.ApplyCustomFrameClassLists(roleClasses)
--       Called on Forever by CustomFrameGroups/CustomFrames.lua right after
--       ROLE_CLASSES / BF.CLASS_SORT_ORDER_ALPHA are built. ROLE_CLASSES is
--       derived from Retail spec data; on Forever every class can be
--       assigned every group role (there are no specs), so each role maps to
--       all 9 classes -- which keeps the "no class filter" fallback the
--       no-op it is meant to be ("include all classes that can perform the
--       selected roles so the class check is a no-op"). Mutated in place:
--       CustomFrames.lua and the options page both hold the same table.
--
-- Load-time only; nothing here runs per frame.
-- ============================================================

local F = BF.Forever

-- ── 9-class alphabetical list ──────────────────────────────────────────────
-- Source: F.CLASSES (Forever_Class.lua, built from Forever's own
-- CLASS_SORT_ORDER); the global CLASS_SORT_ORDER next; a literal list only
-- as the load-order fallback.
local FALLBACK_TOKENS = {
    "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local CLASS_SORT_ORDER_ALPHA = {}
do
    local seen = {}
    local function add(token)
        if type(token) == "string" and not seen[token] then
            seen[token] = true
            CLASS_SORT_ORDER_ALPHA[#CLASS_SORT_ORDER_ALPHA + 1] = token
        end
    end
    if type(F.CLASSES) == "table" and #F.CLASSES > 0 then
        for i = 1, #F.CLASSES do add(F.CLASSES[i].token) end
    elseif type(CLASS_SORT_ORDER) == "table" and #CLASS_SORT_ORDER > 0 then
        for i = 1, #CLASS_SORT_ORDER do add(CLASS_SORT_ORDER[i]) end
    else
        for i = 1, #FALLBACK_TOKENS do add(FALLBACK_TOKENS[i]) end
    end
    table.sort(CLASS_SORT_ORDER_ALPHA)
end
F.CLASS_SORT_ORDER_ALPHA = CLASS_SORT_ORDER_ALPHA

local CLASS_OK = {}
for i = 1, #CLASS_SORT_ORDER_ALPHA do CLASS_OK[CLASS_SORT_ORDER_ALPHA[i]] = true end

-- ── Preview rosters ────────────────────────────────────────────────────────
-- Keyed by the Retail entry's name (names are fixed in both tables). Every
-- swap keeps the entry's Retail ROLE (role is not rewritten), so the
-- composition matches Retail's:
--   raid  Buzzardk     DK TANK      -> Druid TANK
--         Buzzweaver   Monk HEALER  -> Shaman HEALER
--         Buzzardragon Evoker HEALER-> Druid HEALER
--         Buzzilidan   DH TANK      -> Warrior TANK
--         Buzzardsham  Shaman DAMAGE-> Hunter DAMAGE (a Forever class, swapped
--                      only so Hunter appears; Shaman now heals above)
--   CF    CFBuzzard4   DK TANK      -> Warrior TANK   (CFBuzzard3 is the Rogue)
-- `always = true` marks a swap of an entry whose class Forever HAS.
local ROSTER_SWAPS = {
    Buzzardk     = { name = "Buzzbear",    class = "DRUID"   },
    Buzzweaver   = { name = "Buzztotem",   class = "SHAMAN"  },
    Buzzardragon = { name = "Buzzleaf",    class = "DRUID"   },
    Buzzilidan   = { name = "Buzzshield",  class = "WARRIOR" },
    Buzzardsham  = { name = "Buzzhunter",  class = "HUNTER", always = true },
    CFBuzzard4   = {                       class = "WARRIOR" },
}
-- Any other entry with a missing class (none today) gets a Forever class
-- that can fill its role; the role itself is kept.
local DEFAULT_SWAP_BY_ROLE = {
    TANK    = { class = "WARRIOR" },
    HEALER  = { class = "PRIEST"  },
    DAMAGER = { class = "MAGE"    },
}
local DEFAULT_SWAP = DEFAULT_SWAP_BY_ROLE.DAMAGER

function F.ApplyPreviewRoster(list)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" then
            local swap = ROSTER_SWAPS[e.name]
            if not CLASS_OK[e.class] then
                swap = swap or DEFAULT_SWAP_BY_ROLE[e.role] or DEFAULT_SWAP
            elseif not (swap and swap.always) then
                swap = nil
            end
            if swap then
                if swap.name then e.name = swap.name end
                e.class = swap.class
            end
        end
    end
end

-- ── Custom Frame Groups ────────────────────────────────────────────────────
function F.ApplyCustomFrameClassLists(roleClasses)
    BF.CLASS_SORT_ORDER_ALPHA = CLASS_SORT_ORDER_ALPHA
    if type(roleClasses) ~= "table" then return end
    for _, set in pairs(roleClasses) do
        if type(set) == "table" then
            for token in pairs(set) do set[token] = nil end
            for i = 1, #CLASS_SORT_ORDER_ALPHA do set[CLASS_SORT_ORDER_ALPHA[i]] = true end
        end
    end
end
