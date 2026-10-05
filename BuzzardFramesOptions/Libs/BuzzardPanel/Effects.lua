-- ============================================================
-- BuzzardPanel: Effects.lua
-- Refresh tiers: WHEN a setting's side effect runs.
--
-- Three things happen when a reader changes a control, and they do NOT
-- share a schedule:
--
--   1. the profile WRITE                 -- always immediate, in the setter
--   2. the WIDGET's own repaint          -- always immediate, one lookup
--   3. the consuming addon's SIDE EFFECT -- scheduled, and that is this file
--
-- Only (3) is ever expensive. A slider fires its setter on every drag notch;
-- if the addon's "re-lay-out every frame" callback rides along on each one,
-- the drag itself stutters. But (1) and (2) must stay immediate or the
-- control visibly lags the mouse, which is worse.
--
-- -- Why per-frame coalescing is the WRONG default --
--
-- A trailing debounce still fires MID-DRAG: hold the thumb still for the
-- delay and the heavy pass runs while the button is down, which is exactly
-- the hitch it was added to prevent. So there is a third tier that does no
-- work at all while a drag is in progress:
--
--   write     the effect runs inline. What DISCRETE controls get: a switch
--             or a dropdown pick fires once per click, so there is nothing
--             to coalesce and a delay would be pure latency.
--   debounce  keyed trailing edge, default 0.15s. What CONTINUOUS controls
--             get -- sliders and the color wheel -- because those fire a
--             stream of setter calls per gesture.
--   mouseup   zero work while a drag is in progress; runs the moment it
--             ends. For effects heavy enough that even a mid-drag debounce
--             is felt.
--
-- The per-kind default lives on the control definitions as `defaultTier`
-- and is resolved by ns.FireEffect; this file's own fallback stays "write",
-- so a control that declares nothing, or an unrecognized tier, runs inline.
--
-- -- Supersession, not just coalescing --
--
-- Two effects on the same key are not always interchangeable. A broad
-- "rebuild everything" pass makes a narrow "restyle this one thing" pass
-- redundant, and running both is pure waste. So a pending effect carries a
-- RANK, and when the key fires only the highest-ranked entries run; anything
-- below them is dropped as already covered. Ranks are the consuming addon's
-- to choose -- the library only honors the ordering.
--
-- This is why the scheduler stores (key, id, rank) rather than a bare
-- closure. A closure is opaque: two of them cannot be compared, so one can
-- never absorb the other.
--
-- -- Combat --
--
-- Combat is re-checked AT FIRE TIME, never at enqueue time, because a drag
-- can cross into combat mid-gesture. If the effect cannot run then, it stays
-- PENDING and is flushed when combat ends. Dropping it instead -- which is
-- the tempting one-liner -- leaves the panel showing one thing and the
-- profile holding another until the reader happens to touch the control
-- again.
--
-- -- Detecting "a drag is in progress" --
--
-- Two sources, because neither covers everything:
--
--   * app.dragDepth, raised and lowered by the library's OWN controls. It is
--     exact, it ignores mouse buttons held for unrelated reasons, and it
--     gives a real release moment to flush on rather than a timer.
--   * IsMouseButtonDown("LeftButton"), for drags the library does not own.
--     The color picker's wheel is the case that matters: it is a foreign
--     frame, it calls back per wheel tick, and it never tells anyone the
--     gesture ended. Nothing local can see that drag, so the fallback timer
--     re-arms until the button comes up.
--
-- State lives on the APP, not on the library, so two panels open at once
-- cannot flush or supersede each other's work.
-- ============================================================
local ADDON, ns = ...

ns.effects = {}

local DEFAULT_DEBOUNCE = 0.15
local DEFAULT_MOUSEUP  = 0.25

local ArmFallback   -- forward declaration: it re-arms itself

local function State(app)
    local s = app.effectState
    if not s then
        s = { pending = {}, timers = {} }
        app.effectState = s
    end
    return s
end

-- ============================================================
-- Drag state
-- ============================================================

function ns.effects.IsDragging(app)
    if (app.dragDepth or 0) > 0 then
        -- Self-heal. A drag is only open while the button is down, so a
        -- positive depth with the button up means a release was missed --
        -- the mouse came up over another frame, or the widget was released
        -- back to the pool mid-gesture. Left alone that depth is permanent
        -- and every mouseup-tier effect silently stops firing for the rest
        -- of the session, which is far worse than one early flush.
        if IsMouseButtonDown("LeftButton") then return true end
        app.dragDepth = 0
        return false
    end
    return IsMouseButtonDown("LeftButton") and true or false
end

-- ============================================================
-- The pending set
-- ============================================================

local function Cancel(app, key)
    local s = State(app)
    local t = s.timers[key]
    if t then t:Cancel(); s.timers[key] = nil end
end

local function Enqueue(app, key, id, rank, tier, fn)
    local s = State(app)
    local slot = s.pending[key]
    if not slot then
        slot = { entries = {}, top = nil }
        s.pending[key] = slot
    end
    -- Re-scheduling the same id replaces it: the newer closure reads the
    -- newer value, and the older one would only write a stale result.
    slot.entries[id] = { fn = fn, rank = rank }
    if slot.top == nil or rank > slot.top then slot.top = rank end
    -- The key's tier is whatever most recently asked for it. Mixed tiers on
    -- one key are not a configuration the library tries to reconcile -- the
    -- last writer decides when the whole key fires.
    slot.tier = tier
    return slot
end

-- Run one key's pending effects, highest rank only.
--
-- Combat is checked HERE, at fire time. A blocked key keeps its pending set
-- and its top rank, so the flush after combat runs exactly what would have
-- run now.
local function Run(app, key)
    local s = State(app)
    local slot = s.pending[key]
    if not slot then return end
    if InCombatLockdown() then return end

    s.pending[key] = nil
    local top = slot.top
    for _, e in pairs(slot.entries) do
        if e.rank == top then e.fn() end
    end
end

ArmFallback = function(app, key, delay)
    local s = State(app)
    s.timers[key] = C_Timer.NewTimer(delay, function()
        s.timers[key] = nil
        -- Still dragging: re-arm rather than fire. This is what makes the
        -- fallback incapable of running mid-drag -- it can only ever reach
        -- Run() on a tick where the gesture is already over.
        if ns.effects.IsDragging(app) then
            ArmFallback(app, key, delay)
            return
        end
        Run(app, key)
    end)
end

-- ============================================================
-- The entry point
-- ============================================================
--
-- spec = { tier, key, id, rank, delay }
function ns.effects.Schedule(app, spec, fn)
    if not app then fn(); return end

    local tier = spec.tier or "write"
    local key  = spec.key  or "?"
    local id   = spec.id   or "onChange"

    Enqueue(app, key, id, spec.rank or 0, tier, fn)

    if tier == "debounce" then
        Cancel(app, key)
        local s = State(app)
        s.timers[key] = C_Timer.NewTimer(spec.delay or DEFAULT_DEBOUNCE, function()
            s.timers[key] = nil
            Run(app, key)
        end)
        return
    end

    if tier == "mouseup" then
        -- Cancel first: the immediate path below must not be able to run
        -- alongside a fallback timer armed earlier in the same gesture.
        Cancel(app, key)
        if ns.effects.IsDragging(app) then
            ArmFallback(app, key, spec.delay or DEFAULT_MOUSEUP)
            return
        end
        Run(app, key)
        return
    end

    -- "write", and anything unrecognized. An unknown tier running the effect
    -- immediately is the safe failure: the panel is correct and merely less
    -- smooth, rather than silently never refreshing.
    Cancel(app, key)
    Run(app, key)
end

-- ============================================================
-- Flushes
-- ============================================================

local function FlushWhere(app, want)
    local s = app.effectState
    if not s then return end
    local keys = {}
    for key, slot in pairs(s.pending) do
        if want == nil or slot.tier == want then keys[#keys + 1] = key end
    end
    for _, key in ipairs(keys) do
        Cancel(app, key)
        Run(app, key)
    end
end

-- A library-owned drag ended. Only mouseup-tier keys flush: a debounce-tier
-- key asked for a quiet period and has not had one yet, and cutting it short
-- here would quietly turn one tier into the other.
function ns.effects.EndDragFlush(app) FlushWhere(app, "mouseup") end

-- Combat ended. Everything that was blocked at fire time runs now, whatever
-- tier it came from -- these have all already waited out their schedule.
function ns.effects.OnCombatEnd(app) FlushWhere(app, nil) end

function ns.effects.BeginDrag(app)
    if not app then return end
    app.dragDepth = (app.dragDepth or 0) + 1
end

function ns.effects.EndDrag(app)
    if not app then return end
    app.dragDepth = math.max(0, (app.dragDepth or 1) - 1)
    if app.dragDepth == 0 then ns.effects.EndDragFlush(app) end
end

-- Test seam for the demo: how many keys are still waiting.
function ns.effects.GetPending(app)
    local s = app and app.effectState
    if not s then return 0 end
    local n = 0
    for _ in pairs(s.pending) do n = n + 1 end
    return n
end
