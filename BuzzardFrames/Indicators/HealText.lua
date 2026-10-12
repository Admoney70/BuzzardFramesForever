-- ============================================================
-- BuzzardFrames: Indicators/HealText.lua
-- Floating heal numbers on the raid/party frames and the oUF unit frames
-- (player, target, focus, pet, target-of-target, focus-target).
--
-- The combat log is off limits on Forever: even REGISTERING or
-- UNREGISTERING COMBAT_LOG_EVENT_UNFILTERED is a protected action there
-- (ADDON_ACTION_FORBIDDEN, which pcall cannot catch), so this module never
-- names that event. The data source is UNIT_COMBAT -- the unit's own
-- feedback event (what Blizzard's portrait feedback text uses). It names
-- no caster and no spell, and a HoT tick looks exactly like a direct heal,
-- so two things are rebuilt around it:
--        * Direct heals: each of the player's own direct-heal casts
--          (UNIT_SPELLCAST_SUCCEEDED) grants a short window in which that
--          many heal events may show. With HoT ticks off, only heals that
--          land inside such a window show -- your direct heals.
--        * Overhealing: estimated from the unit's health just before the
--          heal (cached from UNIT_HEALTH) against its max health.
--      Any secret value on this engine is only ever handed to the
--      FontString, never computed with.
--
-- Settings live in their own small AceDB (BuzzardFramesHealTextDB), one
-- account-wide profile, edited from the options panel's "Heal Text" page.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local CreateFrame   = CreateFrame
local UnitGUID      = UnitGUID
local UnitExists    = UnitExists
local UnitHealth    = UnitHealth
local UnitHealthMax = UnitHealthMax
local GetTime       = GetTime
local math_min      = math.min
local pcall         = pcall
local type          = type
local tostring      = tostring
local math_floor    = math.floor
local string_format = string.format
local issecretvalue = issecretvalue or function() return false end

local HT = {}
BF.HealText = HT

BF.healTextDefaults = {
    profile = {
        enabled      = true,
        showHoTs     = false,
        showOverheal = true,
        showSpell    = false,
        biggerCrits  = true,
        raidParty    = true,
        unitFrames   = true,
        font         = "Friz Quadrata TT",
        fontOutline  = "OUTLINE",
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

local LSM = LibStub("LibSharedMedia-3.0", true)

local function ApplyFont(fs, cfg, crit)
    local size = cfg.fontSize or 14
    if crit and cfg.biggerCrits then size = math_floor(size * 1.35 + 0.5) end
    local path = (LSM and cfg.font and LSM:Fetch("font", cfg.font, true)) or STANDARD_TEXT_FONT
    local outline = cfg.fontOutline or "OUTLINE"
    if fs._bfSize ~= size or fs._bfPath ~= path or fs._bfOutline ~= outline then
        if not fs:SetFont(path, size, outline) then
            fs:SetFont(STANDARD_TEXT_FONT, size, outline)
        end
        fs._bfSize, fs._bfPath, fs._bfOutline = size, path, outline
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

-- Calls fn(frame) for every shown frame on exactly this unit token.
-- UNIT_COMBAT fires once per token naming the unit (party1 AND target), so
-- an exact match shows each heal once per frame, never twice.
local function ForEachFrame(unit, fn)
    local cfg = Cfg()
    local function test(frame)
        if frame and frame:IsVisible() and FrameUnit(frame) == unit then
            fn(frame)
        end
    end
    VisitFrames(cfg, test)
end

-- ── UNIT_COMBAT helpers: direct-heal credits and overheal estimate ──

-- The player's direct heals, by name, with how many targets one cast can
-- land on. Names rather than IDs: Forever's spell IDs (and ranks) are not
-- the retail ones, and every rank shares its name.
local DIRECT_HEALS = {
    ["Healing Touch"] = 1, ["Regrowth"] = 1, ["Swiftmend"] = 1,
    ["Healing Wave"] = 1, ["Lesser Healing Wave"] = 1, ["Chain Heal"] = 3,
    ["Holy Light"] = 1, ["Flash of Light"] = 1, ["Holy Shock"] = 1,
    ["Lay on Hands"] = 1,
    ["Lesser Heal"] = 1, ["Heal"] = 1, ["Greater Heal"] = 1,
    ["Flash Heal"] = 1, ["Prayer of Healing"] = 5, ["Holy Nova"] = 5,
    ["Desperate Prayer"] = 1,
}
local CREDIT_WINDOW = 1.0   -- seconds from cast success to the heal landing
local credits = {}          -- { expires, left, seen = { [key] = time } }

local function SpellNameOf(spellID)
    if not spellID or issecretvalue(spellID) then return nil end
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    if name and not issecretvalue(name) then return name end
end

local function OnPlayerCast(spellID)
    local name = SpellNameOf(spellID)
    local n = name and DIRECT_HEALS[name]
    if not n then return end
    credits[#credits + 1] = { expires = GetTime() + CREDIT_WINDOW, left = n,
                              seen = {}, name = name }
end

-- The same heal reaches UNIT_COMBAT once per token naming the unit
-- (party1 AND target, say), all in one frame: a unit already counted
-- against a credit in THIS frame passes again without using it up.
local function UnitKey(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and guid and not issecretvalue(guid) then return guid end
    return unit
end

local function TakeCredit(unit)
    local now, key = GetTime(), UnitKey(unit)
    local i = 1
    while i <= #credits do
        local c = credits[i]
        if c.expires < now then
            table.remove(credits, i)
        else
            if c.seen[key] == now then return c end
            if c.left > 0 and not c.seen[key] then
                c.left = c.left - 1
                c.seen[key] = now
                return c
            end
            i = i + 1
        end
    end
    return nil
end

-- unit token -> { prev, cur, t }: the last two health values seen.
local healthLog = {}

local function ReadHealth(unit)
    local ok, h, m = pcall(function() return UnitHealth(unit), UnitHealthMax(unit) end)
    if not ok or issecretvalue(h) or issecretvalue(m) then return nil end
    return h, m
end

local function OnUnitHealth(unit)
    local h = ReadHealth(unit)
    if not h then return end
    local e = healthLog[unit]
    if not e then e = {}; healthLog[unit] = e end
    if e.cur ~= h then
        e.prev, e.cur, e.t = e.cur, h, GetTime()
    end
end

-- How much of `amount` was overhealing. UNIT_COMBAT and UNIT_HEALTH come
-- from the same server update, in either order:
--   * UnitHealth already differs from the cache: UNIT_HEALTH is still to
--     come, so the cached value is the health before the heal;
--   * the cache moved THIS frame: UNIT_HEALTH came first, prev is "before";
--   * otherwise the heal is not applied yet, and current health is "before".
local function EstimateOverheal(unit, amount)
    local now, max = ReadHealth(unit)
    if not now or not max or max <= 0 then return nil end
    local e = healthLog[unit]
    local before
    if e and e.cur and e.cur ~= now then
        before = e.cur
    elseif e and e.t == GetTime() and e.prev then
        before = e.prev
    else
        before = now
    end
    local effective = math_min(amount, max - before)
    if effective < 0 then effective = 0 end
    return amount - effective
end

local function OnUnitCombat(unit, action, descriptor, amount)
    if action ~= "HEAL" or not unit then return end
    local cfg = Cfg()
    -- No way to tell a HoT tick from a direct heal, or whose heal it was,
    -- except by matching it to one of the player's own direct-heal casts.
    local credit = TakeCredit(unit)
    if not cfg.showHoTs and not credit then return end
    local crit = (descriptor == "CRITICAL")
    local text
    if not issecretvalue(amount) and type(amount) == "number" then
        if amount <= 0 then return end
        local overheal = cfg.showOverheal and EstimateOverheal(unit, amount) or 0
        text = "+" .. FormatAmount(amount - overheal) .. (crit and "!" or "")
        if overheal > 0 then
            text = text .. " |cff999999(" .. FormatAmount(overheal) .. ")|r"
        end
        if cfg.showSpell and credit then text = credit.name .. " " .. text end
    end
    ForEachFrame(unit, function(f) Show(f, text, amount, crit) end)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "UNIT_HEALTH" then
        OnUnitHealth((...))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        OnPlayerCast(spellID)
    elseif event == "PLAYER_LOGIN" then
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
    eventFrame:UnregisterEvent("UNIT_COMBAT")
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    if not (cfg and cfg.enabled) then return end
    eventFrame:RegisterEvent("UNIT_COMBAT")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
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
            .. ".  /bfheal test shows sample numbers.")
    end
end
