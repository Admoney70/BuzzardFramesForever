-- ============================================================
-- BuzzardFrames: InterruptProbe.lua
-- /bf kickprobe: a temporary test of what Forever lets an addon see about
-- interrupts without the combat log (which is protected there):
--   * a party member's finished cast (UNIT_SPELLCAST_SUCCEEDED): is the
--     spell ID / name readable in combat, in a dungeon?
--   * an enemy cast being interrupted (UNIT_SPELLCAST_INTERRUPTED on
--     target / focus / nameplates): is the interrupter's GUID readable?
-- Prints one chat line per event; nothing is stored or shown on frames.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local issecretvalue = issecretvalue or function() return false end

local function Show(v)
    if v == nil then return "nil" end
    if issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

local function SpellName(id)
    if id == nil or issecretvalue(id) then return "?" end
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if n == nil or issecretvalue(n) then return "?" end
    return n
end

local function P(...)
    print("|cff11ace9BF kick|r", ("%.2f"):format(GetTime()),
          InCombatLockdown() and "[combat]" or "[no combat]", ...)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not (unit and (unit:find("^party%d$") or unit:find("^raid%d+$"))) then return end
        local _, spellID = ...
        P(unit, "cast", "id", Show(spellID), SpellName(spellID))
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not unit or unit:find("^party") or unit:find("^raid") or unit == "player" then return end
        local _, spellID, interruptedBy = ...
        P(unit, "INTERRUPTED", "spell", Show(spellID), SpellName(spellID),
          "by", Show(interruptedBy))
    end
end)

function BF:ToggleKickProbe()
    self._kickProbe = not self._kickProbe
    if self._kickProbe then
        frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    else
        frame:UnregisterAllEvents()
    end
    print("|cff11ace9Buzzard Frames|r interrupt probe " .. (self._kickProbe and "on" or "off"))
end
