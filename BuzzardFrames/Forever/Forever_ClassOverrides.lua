local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_ClassOverrides.lua  (WoW Forever only)
--
-- Phase D runtime (plan sections 5 and 15.1): CLASS overrides take the
-- place of SPEC overrides on Forever, where the "spec" is the whole class.
--
--   F.ResolveLayoutClassOverride(lp, slot [, flats, requiredType])
--       Raid/party Layout Assignments. Reads
--       layouts.classOverrides[TOKEN][slot]; the entry table carries
--       `_present = true` (the UI's presence marker, same convention as
--       specOverrides). Called by BF:ResolveActiveFlat (raw) and
--       BF:ResolveValidFlatForSlot (with `flats` + `requiredType`, which
--       applies the same "existing flat of the right type" check that
--       function applies to every other layer). Returns a flat ID, the
--       literal "none", or nil (fall through to the Role layer).
--
--   F.ResolveUFClassLayout(p)
--       Unit Frame Layout Assignments. Reads p.ufClassLayouts[TOKEN]
--       (presence), p.ufClassLayoutAssignment[TOKEN] (the layout ID) and
--       p.enableUFClassLayouts (derived from the entry list by the options
--       page, as SyncEnableFlags does for spec). Returns a ufLayouts ID or
--       nil (fall through to the Role layer).
--
-- Resolution order on Forever: Class -> Role -> Global. Retail keeps
-- Spec -> Role -> Global. A Forever profile never reads specOverrides /
-- ufSpecLayouts (the hooks blank the spec step), and Retail never reads
-- the class keys (this file does not load there).
--
-- Cost: these run where the spec lookups ran -- settings change, roster
-- and zone changes (ResolveActiveFlat / ApplyUFRoleSpecLayout callers) --
-- never per aura or per frame. Three table lookups, no allocation.
--
-- SOLO ROLE ON FOREVER (documented, intended -- plan 15.1):
--   Forever has no spec role, so BF.playerSpecRole stays nil. A solo
--   player's role is therefore "NONE":
--     * raid/party Role overrides apply only in a group, where
--       UnitGroupRolesAssigned returns the assigned role
--       (Core_ProfileAPI.lua ResolveActiveFlat / ResolveValidFlatForSlot);
--     * Unit Frame Role overrides likewise (Core_UFLayout.lua
--       ApplyUFRoleSpecLayout);
--     * Custom Frame Groups' solo role filters fall back to DAMAGER
--       (BFLayout.lua `self.playerSpecRole or "DAMAGER"`).
--   A solo player who wants a different layout uses a Class override,
--   which applies with or without a group.
-- ============================================================

local F = BF.Forever

-- The player's class. Forever_Class.lua caches it at load (Grid2 pattern);
-- the UnitClass fallback only covers a load-order accident.
local function PlayerClassToken()
    local token = F.playerClass
    if token == nil and UnitClass then
        token = select(2, UnitClass("player"))
        F.playerClass = token
    end
    return token
end

-- Raid/party Layout Assignments, class layer.
function F.ResolveLayoutClassOverride(lp, slot, flats, requiredType)
    local co = type(lp) == "table" and lp.classOverrides
    if type(co) ~= "table" then return nil end
    local token = PlayerClassToken()
    local entry = token and co[token]
    if type(entry) ~= "table" then return nil end
    local id = entry[slot]
    if type(id) ~= "string" then return nil end
    if id == "none" or flats == nil then return id end
    local f = flats[id]
    if f and (not requiredType or f.type == requiredType) then
        return id
    end
    return nil
end

-- Unit Frame Layout Assignments, class layer.
--
-- The enable flag is honored only when explicitly false: presence is the
-- gate (an entry exists because the reader added it), and the flag is a
-- derived mirror of it. A nil flag (never synced) does not disable an
-- entry that exists.
function F.ResolveUFClassLayout(p)
    if type(p) ~= "table" or p.enableUFClassLayouts == false then return nil end
    local present = p.ufClassLayouts
    if type(present) ~= "table" then return nil end
    local token = PlayerClassToken()
    if not (token and present[token]) then return nil end
    local assign = p.ufClassLayoutAssignment
    local id = type(assign) == "table" and assign[token] or nil
    -- No assignment = "use the global setting" (falls through), exactly as
    -- an unassigned spec entry behaves.
    if id and type(p.ufLayouts) == "table" and p.ufLayouts[id] then
        return id
    end
    return nil
end
