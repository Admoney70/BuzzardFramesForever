-- ============================================================
-- BuzzardFrames: Indicators/InterruptAlert.lua
-- "Interrupted!" on a raid/party frame when that group member's own cast
-- or channel is interrupted -- a mob kicking the healer, say -- so the
-- group can see who is locked out.
--
-- Source: UNIT_SPELLCAST_INTERRUPTED and UNIT_SPELLCAST_CHANNEL_STOP for
-- group units. Both carry `interruptedBy` (the interrupter's GUID): set
-- for a real interrupt, nil when the caster moved or cancelled, which is
-- what tells the two apart. It may be a secret value; only nil-tested.
-- The combat log is never touched (protected on Forever).
--
-- The lockout's real length is not reported, so the alert stays up for a
-- set time (Duration), with a countdown swipe; it clears early when the
-- member starts casting again.
--
-- Settings: their own AceDB (BuzzardFramesInterruptDB), one account-wide
-- profile, edited from the options panel's "Interrupt Alerts" page.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local CreateFrame   = CreateFrame
local GetTime       = GetTime
local pcall         = pcall
local issecretvalue = issecretvalue or function() return false end

local IA = {}
BF.InterruptAlert = IA

BF.interruptAlertDefaults = {
    profile = {
        enabled       = true,
        includePlayer = true,   -- your own frame too
        realOnly      = true,   -- skip casts you moved out of or cancelled
        showText      = true,
        duration      = 4,      -- seconds
        iconSize      = 24,
        yOffset       = 0,
        playSound     = false,
    },
}

local FALLBACK_ICON = 132219   -- Ability_Kick
local eventFrame = CreateFrame("Frame")

local function Cfg()
    return IA.db and IA.db.profile
end

local function Debug(...)
    if IA.debug then print("|cff11ace9BF interrupt|r", ...) end
end

-- ── Display ───────────────────────────────────────────────────

local function Build(frame)
    local h = CreateFrame("Frame", nil, frame)
    h:SetFrameLevel(frame:GetFrameLevel() + 40)
    h:Hide()
    local icon = h:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(h)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = h:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", h, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.9, 0.1, 0.1, 1)
    local cd = CreateFrame("Cooldown", nil, h, "CooldownFrameTemplate")
    cd:SetAllPoints(h)
    cd:SetReverse(true)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
    local text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", h, "BOTTOM", 0, -1)
    text:SetTextColor(1, 0.2, 0.2)
    text:SetText("Interrupted")
    h.icon, h.cd, h.text = icon, cd, text
    frame._bfInterruptAlert = h
    return h
end

local function SetIcon(tex, spellID)
    local ok = false
    if spellID ~= nil and C_Spell and C_Spell.GetSpellTexture then
        local got, t = pcall(C_Spell.GetSpellTexture, spellID)
        if got and t ~= nil then ok = pcall(tex.SetTexture, tex, t) end
    end
    if not ok then tex:SetTexture(FALLBACK_ICON) end
end

local function Show(frame, spellID)
    local cfg = Cfg()
    local h = frame._bfInterruptAlert or Build(frame)
    local size = cfg.iconSize or 24
    h:SetSize(size, size)
    h:ClearAllPoints()
    h:SetPoint("CENTER", frame, "CENTER", 0, cfg.yOffset or 0)
    SetIcon(h.icon, spellID)
    h.text:SetShown(cfg.showText ~= false)
    local dur = cfg.duration or 4
    h.cd:SetCooldown(GetTime(), dur)
    h:Show()
    if h._timer then h._timer:Cancel() end
    h._timer = C_Timer.NewTimer(dur, function()
        h._timer = nil
        h:Hide()
    end)
end

local function Clear(frame)
    local h = frame._bfInterruptAlert
    if h and h:IsShown() then
        if h._timer then h._timer:Cancel(); h._timer = nil end
        h:Hide()
    end
end

-- ── Frame lookup ──────────────────────────────────────────────

local function FrameUnit(frame)
    return frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
end

local function VisitFrames(fn)
    if BF.IterateHeaderChildren and BF.groupsUsed then
        BF:IterateHeaderChildren(fn)
    end
    local twins = BF.twinFrames
    if twins then
        for i = 1, #twins do
            if twins[i]._bf_twinActive then fn(twins[i]) end
        end
    end
end

local function ForEachFrame(unit, fn)
    VisitFrames(function(frame)
        if frame and frame:IsVisible() and FrameUnit(frame) == unit then fn(frame) end
    end)
end

-- ── Events ────────────────────────────────────────────────────

local function IsGroupUnit(unit, cfg)
    if unit == "player" then return cfg.includePlayer ~= false end
    return unit:find("^party%d$") or unit:find("^raid%d+$")
end

local function OnInterrupted(unit, spellID, interruptedBy, how)
    local cfg = Cfg()
    if not (cfg and cfg.enabled and unit and IsGroupUnit(unit, cfg)) then return end
    if interruptedBy == nil and cfg.realOnly ~= false then
        Debug(unit, how, "no interrupter (moved / cancelled), skipped")
        return
    end
    Debug(unit, how, "spell", issecretvalue(spellID) and "<secret>" or tostring(spellID),
          "by", interruptedBy == nil and "nil"
              or (issecretvalue(interruptedBy) and "<secret>" or tostring(interruptedBy)))
    ForEachFrame(unit, function(f) Show(f, spellID) end)
    if cfg.playSound and SOUNDKIT then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- (unit, castGUID, spellID, interruptedBy, castID)
        local _, spellID, interruptedBy = ...
        OnInterrupted(unit, spellID, interruptedBy, "cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- (unit, castGUID, spellID, interruptedBy, castID): a channel that
        -- ended on its own has no interrupter.
        local _, spellID, interruptedBy = ...
        if interruptedBy ~= nil then OnInterrupted(unit, spellID, interruptedBy, "channel") end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- Casting again: the lockout is over.
        if unit then ForEachFrame(unit, Clear) end
    elseif event == "PLAYER_LOGIN" then
        IA:Init()
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- ── Lifecycle ─────────────────────────────────────────────────

function IA:Init()
    if not self.db then
        self.db = LibStub("AceDB-3.0"):New("BuzzardFramesInterruptDB", BF.interruptAlertDefaults, true)
        BF.interruptAlertDB = self.db
    end
    self:Refresh()
end

local EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
}

function IA:Refresh()
    local cfg = Cfg()
    for i = 1, #EVENTS do eventFrame:UnregisterEvent(EVENTS[i]) end
    if not (cfg and cfg.enabled) then
        VisitFrames(function(f) if f then Clear(f) end end)
        return
    end
    for i = 1, #EVENTS do eventFrame:RegisterEvent(EVENTS[i]) end
end

-- A sample alert on every shown group frame, for size and position checks.
function IA:Test()
    if not Cfg() then return end
    VisitFrames(function(f)
        local unit = f and FrameUnit(f)
        if f and f:IsVisible() and unit and UnitExists(unit) then Show(f, 2061) end
    end)
end

SLASH_BUZZARDINTERRUPT1 = "/bfkick"
SlashCmdList.BUZZARDINTERRUPT = function(msg)
    msg = (msg or ""):lower()
    if msg == "test" then
        IA:Test()
    elseif msg == "debug" then
        IA.debug = not IA.debug
        print("|cff11ace9Buzzard Frames|r interrupt alert debug " .. (IA.debug and "on" or "off"))
    else
        print("|cff11ace9Buzzard Frames|r interrupt alerts: "
            .. ((Cfg() and Cfg().enabled) and "on" or "off")
            .. ".  /bfkick test shows a sample, /bfkick debug prints each interrupt.")
    end
end
