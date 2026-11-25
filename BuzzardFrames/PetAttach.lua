-- ============================================================
-- BuzzardFrames: PetAttach.lua
-- "Attach to Party" for party pet frames: the pet block is pinned right
-- after the LAST VISIBLE party member instead of at its saved screen
-- position, so a 4-player group has no empty 5th slot between the members
-- and their pets.
--
-- The pet header is a secure frame, so it can only be moved out of combat.
-- A roster or pet change in combat is queued and applied at
-- PLAYER_REGEN_ENABLED; until then the pets keep their old spot.
--
-- Hooked into RestoreDetachedHeaderPosition, which every layout path
-- already calls to place the pet header, so an attached block is never
-- put back at its saved position by a layout pass.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer

local function PetFlat(header)
    local lp = BF.rpDB and BF.rpDB.profile and BF.rpDB.profile.layouts
    local fl = lp and lp.flatLayouts
    return header.petFlatID and fl and fl[header.petFlatID]
end

-- Party layouts only: a raid block is a grid, with no single "last member"
-- for the pets to follow.
local function WantsAttach(header)
    if BF._contextIsRaid then return false end
    local flat = PetFlat(header)
    return flat and flat.type == "party" and flat.petAttachToParty and true or false
end

-- The last shown child of the last main (non-detached) header: the secure
-- header lays its children out in index order, so that is the member the
-- column ends on.
local function LastPartyFrame()
    local last, lastHeader
    for _, h in ipairs(BF.groupsUsed or {}) do
        if not (h.isDetached or h.isPetFrame or h.isCustomFrame) and h:IsVisible() then
            local i = 1
            while true do
                local f = h:GetAttribute("child" .. i)
                if not f then break end
                if f:IsShown() then last, lastHeader = f, h end
                i = i + 1
            end
        end
    end
    return last, lastHeader
end

local function FindPetHeader()
    for _, h in ipairs(BF.groupsUsed or {}) do
        if h.isPetFrame then return h end
    end
end

-- Pin the pet header after `last`, continuing the party's own direction:
-- the main header's "point" attribute is the edge each child anchors by
-- (TOP = the column grows down, LEFT = the row grows right, ...).
local function Pin(header, last, partyHeader, flat)
    local sp = flat.petFrameSpacing or 0
    local point = partyHeader:GetAttribute("point") or "TOP"
    local ga = header.cfgLayoutAnchor or "TOPLEFT"
    local side = ga:find("RIGHT") and "RIGHT" or "LEFT"
    local vside = ga:find("BOTTOM") and "BOTTOM" or "TOP"
    header:ClearAllPoints()
    if point == "TOP" then          -- grows down: pets below
        header:SetPoint("TOP" .. side, last, "BOTTOM" .. side, 0, -sp)
    elseif point == "BOTTOM" then   -- grows up: pets above
        header:SetPoint("BOTTOM" .. side, last, "TOP" .. side, 0, sp)
    elseif point == "LEFT" then     -- grows right: pets to the right
        header:SetPoint(vside .. "LEFT", last, vside .. "RIGHT", sp, 0)
    else                            -- grows left: pets to the left
        header:SetPoint(vside .. "RIGHT", last, vside .. "LEFT", -sp, 0)
    end
    -- The header is parented to its pet anchor frame, which the saved-
    -- position path is what normally shows.
    local parent = header:GetParent()
    if parent and parent ~= UIParent then parent:Show() end
    header:Show()
end

local pending = false

-- Returns true when the header is attached (and was pinned, or will be
-- once combat ends), false when the saved position should be used.
local function Apply(header)
    header = header or FindPetHeader()
    if not header or not WantsAttach(header) then return false end
    if InCombatLockdown() then pending = true; return true end
    local last, partyHeader = LastPartyFrame()
    -- No member shown yet (roster still settling): keep the saved spot
    -- for now; the next roster event re-pins.
    if not last then return false end
    Pin(header, last, partyHeader, PetFlat(header))
    return true
end

function BF:ApplyPetAttach()
    return Apply()
end

-- Every layout path places the pet header through this.
local origRestore = BF.RestoreDetachedHeaderPosition
function BF:RestoreDetachedHeaderPosition(header)
    if header and header.isPetFrame and Apply(header) then return true end
    return origRestore(self, header)
end

-- Roster and pet changes: the secure headers show and hide their children
-- in their own event handlers, so re-pin a moment later, once they have.
local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.1, function()
        queued = false
        Apply()
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("UNIT_PET")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, unit)
    -- UNIT_PET fires for every pet owner the client knows of; only the
    -- player's and the party's pets are on these frames.
    if event == "UNIT_PET" and not (unit == "player" or (unit and unit:find("^party%d$"))) then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if not pending then return end
        pending = false
    end
    Queue()
end)
