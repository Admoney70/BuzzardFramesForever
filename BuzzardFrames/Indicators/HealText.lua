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
--          many heal events may show -- on the unit it was cast at
--          (UNIT_SPELLCAST_SENT), for a single-target heal. With HoT ticks off, only heals that
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
local UnitName      = UnitName
local UnitIsFriend  = UnitIsFriend
local UnitHealth    = UnitHealth
local UnitHealthMax = UnitHealthMax
local GetTime       = GetTime
local math_min      = math.min
local pcall         = pcall
local type          = type
local tostring      = tostring
local tonumber      = tonumber
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
-- A direct heal's result reaches the client with (or a hair after) the
-- server's "cast went off" that fires UNIT_SPELLCAST_SUCCEEDED, so the
-- window is short: a long one lets another healer's heal on the same tank
-- take the credit. A heal that arrives a little BEFORE the success event
-- waits in `pending` for PRE_WINDOW so the order of the two does not matter.
local CREDIT_WINDOW = 0.5
local PRE_WINDOW    = 0.1
local pending = {}          -- heals not (yet) matched: { unit, key, amount, crit, time, overheal }
-- credits[i] = { expires, left, name, target = GUID|nil, used = { [GUID] = true },
--                last = { key, time, amount } }
local credits = {}
local sentTargets = {}      -- castGUID -> target GUID, from UNIT_SPELLCAST_SENT

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

-- A GUID for a unit token, or the token itself if the GUID is unreadable.
local function UnitKey(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and guid and not issecretvalue(guid) then return guid end
    return unit
end

local function Plain(v)
    return v ~= nil and not issecretvalue(v)
end

-- UNIT_SPELLCAST_SENT names the target only by NAME. Find the unit that
-- carries it among the tokens a heal can be aimed at.
local NAME_TOKENS = { "target", "mouseover", "focus", "player", "pet" }
for i = 1, 4 do NAME_TOKENS[#NAME_TOKENS + 1] = "party" .. i end
for i = 1, 4 do NAME_TOKENS[#NAME_TOKENS + 1] = "partypet" .. i end
for i = 1, 40 do NAME_TOKENS[#NAME_TOKENS + 1] = "raid" .. i end

local function GUIDForName(name)
    if not Plain(name) or name == "" then return nil end
    local short = name:match("^([^%-]+)") or name
    for i = 1, #NAME_TOKENS do
        local u = NAME_TOKENS[i]
        if UnitExists(u) then
            local ok, n, realm = pcall(UnitName, u)
            if ok and Plain(n) and (n == name or n == short
                    or (Plain(realm) and realm ~= "" and (n .. "-" .. realm) == name)) then
                local key = UnitKey(u)
                if key ~= u then return key end
            end
        end
    end
    return nil
end

local function OnSpellSent(target, castGUID)
    if not Plain(castGUID) then return end
    local guid
    if Plain(target) and target ~= "" then
        -- A name we cannot place (secret, or not in the group) leaves the
        -- credit unbound rather than tied to the wrong unit.
        guid = GUIDForName(target)
    else
        -- No name: the client picked the target itself -- a friendly
        -- target, else (auto self-cast) the player.
        local ok, friendly = pcall(UnitIsFriend, "player", "target")
        guid = UnitKey((ok and friendly == true) and "target" or "player")
    end
    sentTargets[castGUID] = guid
end

-- The lowest amount the spell's tooltip says it heals ("for 93 to 107"),
-- or nil when the tooltip has no range (Swiftmend) or is not loaded yet.
local function MinHealFor(spellID)
    local desc
    if C_Spell and C_Spell.GetSpellDescription then
        desc = C_Spell.GetSpellDescription(spellID)
    elseif GetSpellDescription then
        desc = GetSpellDescription(spellID)
    end
    if not Plain(desc) then return nil end
    local lo = desc:gsub(",", ""):match("for (%d+) to %d+")
    return lo and tonumber(lo) or nil
end

local function Debug(...)
    if HT.debug then print("|cff11ace9BF heal|r", ...) end
end

local MatchPending   -- defined below TakeCredit

local function OnPlayerCast(castGUID, spellID)
    local target = Plain(castGUID) and sentTargets[castGUID] or nil
    if Plain(castGUID) then sentTargets[castGUID] = nil end
    local name = SpellNameOf(spellID)
    local n = name and DIRECT_HEALS[name]
    if not n then return end
    local now = GetTime()
    local credit = {
        time = now, expires = now + CREDIT_WINDOW, left = n, name = name,
        -- Single-target heals are tied to the unit they were cast on; the
        -- group heals (Chain Heal, Prayer of Healing, Holy Nova) are not.
        target = (n == 1) and target or nil,
        min = MinHealFor(spellID),
        used = {},
    }
    credits[#credits + 1] = credit
    Debug("cast", name, "target", tostring(credit.target), "min", tostring(credit.min))
    MatchPending(credit)
end

-- Can this credit take this heal? The same heal reaches UNIT_COMBAT once
-- per token naming the unit (party1 AND target, say), at one time, with
-- one amount: a repeat of the heal a credit just took passes again without
-- using anything up. Anything else must be on the cast's target, at least
-- the spell's tooltip minimum, and inside the window.
local function TryCredit(c, heal)
    local last = c.last
    if last and last.key == heal.key and last.time == heal.time
            and heal.amount and last.amount == heal.amount then
        return true
    end
    if c.left <= 0 or c.used[heal.key] then return false end
    if c.target ~= nil and c.target ~= heal.key then return false, "other target" end
    if heal.time > c.expires or heal.time < c.time - PRE_WINDOW then return false, "outside window" end
    if c.min and heal.amount and heal.amount < c.min * 0.9 then return false, "below spell min" end
    c.left = c.left - 1
    c.used[heal.key] = true
    c.last = { key = heal.key, time = heal.time, amount = heal.amount }
    return true
end

local function TakeCredit(heal)
    local now = GetTime()
    local i, why = 1, "no cast"
    while i <= #credits do
        local c = credits[i]
        if c.expires < now - PRE_WINDOW then
            table.remove(credits, i)
        else
            local ok, reason = TryCredit(c, heal)
            if ok then return c end
            why = reason or why
            i = i + 1
        end
    end
    return nil, why
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

local function Render(heal, credit)
    local cfg = Cfg()
    local text
    if heal.amount then
        local overheal = heal.overheal or 0
        text = "+" .. FormatAmount(heal.amount - overheal) .. (heal.crit and "!" or "")
        if overheal > 0 then
            text = text .. " |cff999999(" .. FormatAmount(overheal) .. ")|r"
        end
        if cfg.showSpell and credit then text = credit.name .. " " .. text end
    end
    ForEachFrame(heal.unit, function(f) Show(f, text, heal.raw, heal.crit) end)
end

-- A cast just went off: its result may already be waiting.
MatchPending = function(credit)
    local now = GetTime()
    local i = 1
    while i <= #pending do
        local heal = pending[i]
        if heal.time < now - PRE_WINDOW then
            table.remove(pending, i)
        elseif TryCredit(credit, heal) then
            table.remove(pending, i)
            Debug("heal", heal.unit, tostring(heal.amount), "-> " .. credit.name, "(arrived first)")
            Render(heal, credit)
        else
            i = i + 1
        end
    end
end

local function OnUnitCombat(unit, action, descriptor, amount)
    if action ~= "HEAL" or not unit then return end
    local cfg = Cfg()
    local plain = Plain(amount) and type(amount) == "number"
    if plain and amount <= 0 then return end
    local heal = {
        unit = unit, key = UnitKey(unit), time = GetTime(),
        raw = amount, amount = plain and amount or nil,
        crit = (descriptor == "CRITICAL"),
    }
    -- Overheal is read NOW, while the health cache still describes this heal.
    if plain and cfg.showOverheal then heal.overheal = EstimateOverheal(unit, amount) end

    -- No way to tell a HoT tick from a direct heal, or whose heal it was,
    -- except by matching it to one of the player's own direct-heal casts.
    local credit, why = TakeCredit(heal)
    if credit then
        Debug("heal", unit, tostring(heal.amount), "-> " .. credit.name,
              string_format("dt %.2f", heal.time - credit.time))
        Render(heal, credit)
    elseif cfg.showHoTs then
        Render(heal, nil)
    else
        Debug("heal", unit, tostring(heal.amount), "held:", why)
        pending[#pending + 1] = heal
        while #pending > 40 do table.remove(pending, 1) end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "UNIT_HEALTH" then
        OnUnitHealth((...))
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, target, castGUID = ...
        OnSpellSent(target, castGUID)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        OnPlayerCast(castGUID, spellID)
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
        -- Output of the retired C_DamageMeter probe (secret in combat on
        -- Forever, so of no use to heal text).
        self.db.global.meterProbe = nil
    end
    self:Refresh()
end

function HT:Refresh()
    local cfg = Cfg()
    eventFrame:UnregisterEvent("UNIT_COMBAT")
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:UnregisterEvent("UNIT_SPELLCAST_SENT")
    if not (cfg and cfg.enabled) then return end
    eventFrame:RegisterEvent("UNIT_COMBAT")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
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
    elseif msg == "debug" then
        HT.debug = not HT.debug
        print("|cff11ace9Buzzard Frames|r heal text debug " .. (HT.debug and "on" or "off"))
    else
        print("|cff11ace9Buzzard Frames|r heal text: "
            .. ((Cfg() and Cfg().enabled) and "on" or "off")
            .. ".  /bfheal test shows sample numbers, /bfheal debug explains each heal.")
    end
end
