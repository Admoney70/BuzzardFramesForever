local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_Names.lua  (WoW Forever only)
--
-- Show Last Name (owner request 2026-11-17). Forever characters can carry a
-- surname. UnitName returns it as its SECOND value -- verified in game:
--   /dump UnitName("party1")            -> "Serina", "Hunter"
--   /dump UnitNameUnmodified("party1")  -> "Serina", "Hunter"
-- The frames only ever read the first value, so the surname is hidden by
-- default; with the text option `showLastName` on, the name builders read
-- the full name through F.UnitNameWithSurname instead of UnitName.
--
-- The second value is only a surname while regional unique names are on.
-- Otherwise it is the realm, exactly as on Retail -- Forever's own AceDB
-- branches on the same test (Libs/AceDB-3.0, RegionalUniqueNamesEnabled:
-- "name, surname" vs "name - realm") -- so the realm is never shown here.
--
-- Callers (each marked -- [FOREVER]):
--   BFStatus.lua                      BuildComposedName (the name text)
--   Indicators/StatusText_Overlay.lua GetUnitBaseName  (append mode)
-- ============================================================

local F = BF.Forever
local UnitName = UnitName

function F.UnitNameWithSurname(unit)
    local name, second = UnitName(unit)
    if name and second and second ~= ""
       and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        return name .. " " .. second
    end
    return name
end
