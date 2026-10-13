-- ============================================================
-- BuzzardFrames: Indicators/MeterProbe.lua
-- Temporary diagnostics for the client's built-in damage meter
-- (C_DamageMeter), to find out whether heal text can read the player's
-- OWN healing from it instead of guessing from casts.
--
--   /bfheal meter       inventory: functions, enums, availability, and a
--                       snapshot of the player's healing (amounts shown as
--                       <secret> if the client hides them from addons)
--   /bfheal meterwatch  toggle: log every damage meter event and, on each
--                       one, the player's healing total and per-spell totals
--
-- Everything printed is also kept in BuzzardFramesHealTextDB.global.meterProbe
-- (WTF\Account\<name>\SavedVariables\BuzzardFrames.lua after a /reload).
-- Read-only: calls getters under pcall, never changes meter state.
-- ============================================================
local BF = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local issecretvalue = issecretvalue or function() return false end
local pcall, type, tostring, pairs = pcall, type, tostring, pairs

local MP = {}
BF.MeterProbe = MP

local log, logLines = nil, 0
local MAX_LINES = 120

local function Out(line)
    print("|cff11ace9BF meter|r " .. line)
    if log and logLines < 400 then
        log[#log + 1] = line
        logLines = logLines + 1
    end
end

local function Show(v)
    if issecretvalue(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then return '"' .. v .. '"' end
    if t == "table" then return "{...}" end
    return tostring(v)
end

-- Shallow-ish dump: nested tables to `depth`, arrays capped at 4 entries.
local function Dump(prefix, v, depth, budget)
    budget = budget or { n = 0 }
    if budget.n > MAX_LINES then return end
    if issecretvalue(v) or type(v) ~= "table" then
        budget.n = budget.n + 1
        Out(prefix .. " = " .. Show(v))
        return
    end
    if depth <= 0 then
        budget.n = budget.n + 1
        Out(prefix .. " = {table}")
        return
    end
    local count = 0
    for k, val in pairs(v) do
        count = count + 1
        -- Long arrays: the first 4 entries, and a count below.
        if not (type(k) == "number" and k > 4) then
            Dump(prefix .. "." .. tostring(k), val, depth - 1, budget)
        end
    end
    if #v > 4 then
        budget.n = budget.n + 1
        Out(prefix .. " (#" .. #v .. " entries, first 4 shown)")
    end
    if count == 0 then
        budget.n = budget.n + 1
        Out(prefix .. " = {}")
    end
end

local function NewLog(title)
    local db = BF.healTextDB
    if db then
        db.global.meterProbe = db.global.meterProbe or {}
        log = {}
        db.global.meterProbe[title] = log
    end
    logLines = 0
end

local function EnumKeys(name)
    local e = Enum and Enum[name]
    if type(e) ~= "table" then return nil end
    local parts = {}
    for k, v in pairs(e) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(parts)
    return table.concat(parts, " ")
end

local function HealingType()
    local e = Enum and Enum.DamageMeterType
    if type(e) ~= "table" then return nil end
    return e.HealingDone or e.Healing or e.HealingAndAbsorbs
end

local function SessionTypes()
    local e = Enum and Enum.DamageMeterSessionType
    if type(e) ~= "table" then return {} end
    local out = {}
    for _, key in ipairs({ "Current", "Overall", "Expired" }) do
        if e[key] ~= nil then out[#out + 1] = { key, e[key] } end
    end
    return out
end

local function Try(label, fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then
        Out(label .. " -> error: " .. tostring(res[2]))
        return nil
    end
    return res[2], res[3]
end

-- The player's healing as the meter sees it right now.
local function Snapshot(depth)
    local DM = C_DamageMeter
    local ht = HealingType()
    local guid = UnitGUID("player")
    if ht == nil then
        Out("no healing meter type in Enum.DamageMeterType")
        return
    end
    for _, st in ipairs(SessionTypes()) do
        local name, sv = st[1], st[2]
        local session = Try("GetCombatSessionFromType(" .. name .. ")",
            DM.GetCombatSessionFromType, sv, ht)
        if session then Dump("session[" .. name .. "]", session, depth + 1) end
        local src = Try("GetCombatSessionSourceFromType(" .. name .. ")",
            DM.GetCombatSessionSourceFromType, sv, ht, guid)
        if src then Dump("me[" .. name .. "]", src, depth + 1) end
    end
end

function MP:Inventory()
    NewLog("inventory")
    local DM = C_DamageMeter
    if type(DM) ~= "table" then
        Out("C_DamageMeter missing")
        return
    end
    local fns = {}
    for k, v in pairs(DM) do fns[#fns + 1] = k .. (type(v) == "function" and "()" or "") end
    table.sort(fns)
    Out("functions: " .. table.concat(fns, ", "))
    Out("Enum.DamageMeterType: " .. tostring(EnumKeys("DamageMeterType")))
    Out("Enum.DamageMeterSessionType: " .. tostring(EnumKeys("DamageMeterSessionType")))
    local ok, avail, why = pcall(function()
        if DM.IsDamageMeterAvailable then return DM.IsDamageMeterAvailable() end
        return "n/a"
    end)
    Out("IsDamageMeterAvailable: " .. Show(ok and avail) .. " " .. Show(why))
    Out("in combat: " .. tostring(InCombatLockdown()))
    local sessions = Try("GetAvailableCombatSessions", DM.GetAvailableCombatSessions)
    if sessions then Dump("sessions", sessions, 2) end
    Snapshot(2)
end

-- ── Event watch ───────────────────────────────────────────────

local EVENTS = {
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}
local watcher = CreateFrame("Frame")
local watching = false
local lastPrint = 0

watcher:SetScript("OnEvent", function(_, event, ...)
    local args = {}
    for i = 1, select("#", ...) do args[i] = Show((select(i, ...))) end
    Out(string.format("%.2f %s(%s)", GetTime(), event, table.concat(args, ", ")))
    -- One player snapshot per half second at most, so a fight does not
    -- flood chat.
    local now = GetTime()
    if now - lastPrint >= 0.5 then
        lastPrint = now
        local DM = C_DamageMeter
        local ht = HealingType()
        local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
        if DM and ht and cur ~= nil then
            local src = Try("source", DM.GetCombatSessionSourceFromType, cur, ht, UnitGUID("player"))
            if src then Dump("  me", src, 3, { n = MAX_LINES - 30 }) end
        end
    end
end)

function MP:ToggleWatch()
    watching = not watching
    if watching then
        NewLog("watch")
        for _, e in ipairs(EVENTS) do
            local ok, err = pcall(watcher.RegisterEvent, watcher, e)
            Out(e .. (ok and " registered" or (" not available: " .. tostring(err))))
        end
        Out("watch ON -- heal something, then /bfheal meterwatch again to stop")
    else
        watcher:UnregisterAllEvents()
        Out("watch OFF")
        log = nil
    end
end
