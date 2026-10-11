-- ============================================================
-- BuzzardFrames: Indicators/HealText.lua
-- Floating heal numbers on the raid/party frames and the oUF unit frames
-- (player, target, focus, pet, target-of-target, focus-target).
--
-- Two data sources, best first:
--   1. COMBAT_LOG_EVENT_UNFILTERED -- knows who cast the heal, the spell,
--      overhealing and crits, so "only my heals" and the HoT filter work.
--      The Midnight-era engine Forever runs on may refuse addons the combat
--      log; registration is tried under pcall, and the source only counts
--      as live once an event actually arrives.
--   2. UNIT_COMBAT -- the unit's own feedback event (what Blizzard's
--      portrait feedback text uses). No caster, so every heal on the unit
--      shows, HoT ticks included; used until (or unless) the combat log is
--      seen working. Its amount may be a secret value on this engine, so
--      it is only ever handed to the FontString, never computed with.
--
-- Settings live in their own small AceDB (BuzzardFramesHealTextDB), one
-- account-wide profile, edited from the options panel's "Heal Text" page.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local CreateFrame   = CreateFrame
local UnitGUID      = UnitGUID
local UnitExists    = UnitExists
local pcall         = pcall
local type          = type
local tostring      = tostring
local math_floor    = math.floor
local string_format = string.format
local issecretvalue = issecretvalue or function() return false end
local CLEUInfo      = CombatLogGetCurrentEventInfo
    or (C_CombatLog and C_CombatLog.GetCurrentEventInfo)

local HT = {}
BF.HealText = HT

BF.healTextDefaults = {
    profile = {
        enabled      = true,
        onlyMine     = true,
        showHoTs     = false,
        showOverheal = true,
        showSpell    = false,
        biggerCrits  = true,
        raidParty    = true,
        unitFrames   = true,
        fontSize     = 14,
        yOffset      = 0,
        duration     = 1.5,
        rise         = 24,
        color        = { r = 0.25, g = 1.00, b = 0.25, a = 1 },
    },
}

local OUF_FRAME_NAMES = {
    "BuzzardFrames_oUFPlayer", "BuzzardFrames_oUFTarget",
    "BuzzardFrames_oUFFocus", "BuzzardFrames_oUFTargetOfTarget",
    "BuzzardFrames_oUFFocusTarget", "BuzzardFrames_oUFPet",
}

local SLOTS = 4
local playerGUID
local cleuRegistered, cleuAlive = false, false
local eventFrame = CreateFrame("Frame")

local function Cfg()
    return HT.db and HT.db.profile
end

-- ── Display ───────────────────────────────────────────────────

local function FormatAmount(n)
    if n >= 1000000 then return string_format("%.1fm", n / 1000000) end
    if n >= 100000  then return string_format("%dk", math_floor(n / 1000)) end
    return tostring(n)
end

local function ApplyFont(fs, cfg, crit)
    local size = cfg.fontSize or 14
    if crit and cfg.biggerCrits then size = math_floor(size * 1.35 + 0.5) end
    if fs._bfSize ~= size then
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        fs._bfSize = size
    end
end

local function BuildHolder(frame)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetFrameLevel(frame:GetFrameLevel() + 30)
    holder.slots, holder.next = {}, 1
    for i = 1, SLOTS do
        local fs = holder:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:Hide()
        local ag = fs:CreateAnimationGroup()
        local move = ag:CreateAnimation("Translation")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        ag:SetScript("OnFinished", function() fs:Hide() end)
        fs._ag, fs._move, fs._fade = ag, move, fade
        holder.slots[i] = fs
    end
    frame._bfHealText = holder
    return holder
end

-- `text` is either a finished string, or nil with `amount` holding a value
-- that must not be touched (secret): it goes straight to SetFormattedText.
local function Show(frame, text, amount, crit)
    local cfg = Cfg()
    local holder = frame._bfHealText or BuildHolder(frame)
    local fs = holder.slots[holder.next]
    holder.next = holder.next % SLOTS + 1

    fs._ag:Stop()
    ApplyFont(fs, cfg, crit)
    local c = cfg.color
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", holder, "CENTER", 0, cfg.yOffset or 0)
    if text then
        fs:SetText(text)
    elseif not pcall(fs.SetFormattedText, fs, "+%s", amount) then
        fs:SetText("+")
    end

    local dur = cfg.duration or 1.5
    fs._move:SetOffset(0, cfg.rise or 24)
    fs._move:SetDuration(dur)
    fs._fade:SetStartDelay(dur * 0.6)
    fs._fade:SetDuration(dur * 0.4)
    fs:SetAlpha(1)
    fs:Show()
    fs._ag:Play()
end

-- ── Frame lookup ──────────────────────────────────────────────

local function FrameUnit(frame)
    return frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
end

local function SafeGUIDMatch(unit, guid)
    local ok, match = pcall(function() return UnitGUID(unit) == guid end)
    return ok and match
end

-- Calls test(frame) for every frame heal text may appear on.
local function VisitFrames(cfg, test)
    if cfg.raidParty then
        if BF.IterateHeaderChildren and BF.groupsUsed then
            BF:IterateHeaderChildren(test)
        end
        local twins = BF.twinFrames
        if twins then
            for i = 1, #twins do
                if twins[i]._bf_twinActive then test(twins[i]) end
            end
        end
    end
    if cfg.unitFrames then
        for i = 1, #OUF_FRAME_NAMES do test(_G[OUF_FRAME_NAMES[i]]) end
    end
end

-- Calls fn(frame) for every shown frame that matches. `byGUID` matches on
-- the unit's GUID (combat log), otherwise on the exact unit token
-- (UNIT_COMBAT fires once per token, so an exact match never doubles up).
local function ForEachFrame(key, byGUID, fn)
    local cfg = Cfg()
    local function test(frame)
        if not frame or not frame:IsVisible() then return end
        local u = FrameUnit(frame)
        if not u then return end
        if byGUID then
            if SafeGUIDMatch(u, key) then fn(frame) end
        elseif u == key then
            fn(frame)
        end
    end
    VisitFrames(cfg, test)
end

-- ── Sources ───────────────────────────────────────────────────

local function OnCombatLog()
    local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _,
          _, spellName, _, amount, overheal, _, crit = CLEUInfo()
    -- A combat log that hides who did what is no better than the fallback:
    -- leave UNIT_COMBAT in charge.
    if issecretvalue(sub) or issecretvalue(srcGUID) or issecretvalue(dstGUID) then return end
    if not cleuAlive then
        -- The combat log works: retire the fallback.
        cleuAlive = true
        eventFrame:UnregisterEvent("UNIT_COMBAT")
    end
    if sub ~= "SPELL_HEAL" and sub ~= "SPELL_PERIODIC_HEAL" then return end
    local cfg = Cfg()
    if sub == "SPELL_PERIODIC_HEAL" and not cfg.showHoTs then return end
    if cfg.onlyMine and srcGUID ~= playerGUID then return end
    if not dstGUID then return end

    local text
    if issecretvalue(amount) or issecretvalue(overheal) then
        text = nil
    else
        overheal = overheal or 0
        local eff = (amount or 0) - overheal
        if eff <= 0 and not (cfg.showOverheal and overheal > 0) then return end
        text = "+" .. FormatAmount(eff > 0 and eff or 0)
        if crit then text = text .. "!" end
        if cfg.showOverheal and overheal > 0 then
            text = text .. " |cff999999(" .. FormatAmount(overheal) .. ")|r"
        end
        if cfg.showSpell and spellName and not issecretvalue(spellName) then
            text = spellName .. " " .. text
        end
    end
    ForEachFrame(dstGUID, true, function(f) Show(f, text, amount, crit) end)
end

local function OnUnitCombat(unit, action, descriptor, amount)
    if action ~= "HEAL" or not unit then return end
    local crit = (descriptor == "CRITICAL")
    local text
    if not issecretvalue(amount) and type(amount) == "number" then
        if amount <= 0 then return end
        text = "+" .. FormatAmount(amount) .. (crit and "!" or "")
    end
    ForEachFrame(unit, false, function(f) Show(f, text, amount, crit) end)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- pcall: if this engine hands out secret GUIDs or amounts, a compare
        -- would throw on every combat log line; fail quietly instead.
        pcall(OnCombatLog)
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        HT:Init()
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- ── Lifecycle ─────────────────────────────────────────────────

function HT:Init()
    if not self.db then
        self.db = LibStub("AceDB-3.0"):New("BuzzardFramesHealTextDB", BF.healTextDefaults, true)
        BF.healTextDB = self.db
    end
    self:Refresh()
end

function HT:Refresh()
    local cfg = Cfg()
    eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:UnregisterEvent("UNIT_COMBAT")
    cleuRegistered, cleuAlive = false, false
    if not (cfg and cfg.enabled) then return end
    if CLEUInfo then
        cleuRegistered = pcall(eventFrame.RegisterEvent, eventFrame, "COMBAT_LOG_EVENT_UNFILTERED")
            and eventFrame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") or false
    end
    eventFrame:RegisterEvent("UNIT_COMBAT")
end

function HT:Mode()
    if cleuAlive then return "combat log" end
    if cleuRegistered then return "unit feedback (combat log registered, no events seen yet)" end
    return "unit feedback (combat log unavailable)"
end

-- Fake heals on every shown frame, for positioning and style checks.
function HT:Test()
    local cfg = Cfg()
    if not cfg then return end
    local n = 0
    local function fire(f)
        n = n + 1
        local crit = (n % 3 == 0)
        local amt = 400 + (n * 137) % 1600
        local text = "+" .. FormatAmount(amt) .. (crit and "!" or "")
        if cfg.showOverheal and n % 2 == 0 then
            text = text .. " |cff999999(" .. FormatAmount(math_floor(amt / 3)) .. ")|r"
        end
        if cfg.showSpell then text = "Regrowth " .. text end
        Show(f, text, nil, crit)
    end
    local function test(frame)
        if frame and frame:IsVisible() and FrameUnit(frame) and UnitExists(FrameUnit(frame)) then
            fire(frame)
        end
    end
    VisitFrames(cfg, test)
end

SLASH_BUZZARDHEALTEXT1 = "/bfheal"
SlashCmdList.BUZZARDHEALTEXT = function(msg)
    msg = (msg or ""):lower()
    if msg == "test" then
        HT:Test()
    else
        print("|cff11ace9Buzzard Frames|r heal text: "
            .. ((Cfg() and Cfg().enabled) and "on" or "off")
            .. ", source: " .. HT:Mode()
            .. ".  /bfheal test shows sample numbers.")
    end
end
