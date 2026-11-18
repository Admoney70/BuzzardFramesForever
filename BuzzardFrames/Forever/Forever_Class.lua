local BF = _G["BuzzardFrames"]
if not BF.isForever then return end
BF.Forever = BF.Forever or {}

-- ============================================================
-- BuzzardFrames: Forever/Forever_Class.lua  (WoW Forever only)
--
-- The CLASS concept that replaces specializations on Forever (plan sections
-- 4, 6 E2/E4, 15.1). Forever has no specializations -- GetSpecialization()
-- reports the whole class -- so every Retail "Spec" surface gets a class twin
-- here, and the Retail spec code is skipped by `-- [FOREVER]` hooks.
--
--   F.playerClass                  the player's class token, cached at load
--   F.CLASSES                      ordered { token, name, color, icon }
--   F.CLASS_SET                    { [token] = true }
--   F.ClassLabel(token)            icon + class-colored name (dropdowns)
--   F.IsClassConditionMet(c)       the Class load condition (runtime gate)
--   F.ClassConditionEmpty(c)       condition on, every class OFF
--   F.GetSingleEnabledClass(c)     the one class ON, or nil
--   F.SingleBuffMatchesClassFilter(c, token)   Buff List "Filter by Class"
--   F.NormalizeClassFilter(v)      filter value -> token, or 0 for "All"
--   F.ResolveBuffsClassPreset(t)   Buffs preset class override (D3)
--
-- Storage convention (same as the Retail Spec condition, do NOT invert):
--   c.loadClass       bool -- the condition is switched on
--   c.loadClassTypes  [TOKEN] = false means OFF; an absent key, or an absent
--                     table, means ON.
--
-- Settings-time only. Every caller resolves these into the same caches the
-- Spec condition feeds (the _fbs tables, container relevance, claim sets);
-- nothing here runs per frame or per UNIT_AURA.
-- ============================================================

local F = BF.Forever

-- Grid2 GridCore pattern: the class is constant for the session.
F.playerClass = select(2, UnitClass("player"))

-- ── Class list ─────────────────────────────────────────────────────────────
-- Built from the global CLASS_SORT_ORDER, which Forever's own UI sets to
-- exactly its 9 classes (Blizzard Camelot\Constants.lua, plan section 11).
-- LOCALIZED_CLASS_NAMES_MALE and CLASS_ICON_TCOORDS list all 13 classes on
-- both games, so neither can be the source of the list.
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function ClassColorHex(token)
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not cc then return "ffffff" end
    if type(cc.colorStr) == "string" and #cc.colorStr == 8 then
        return cc.colorStr:sub(3)
    end
    return ("%02x%02x%02x"):format(
        math.floor((cc.r or 1) * 255 + 0.5),
        math.floor((cc.g or 1) * 255 + 0.5),
        math.floor((cc.b or 1) * 255 + 0.5))
end

local function ClassIconString(token)
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if not tc then return nil end
    -- |T path : h : w : x : y : texW : texH : l : r : t : b |t, in pixels of a
    -- 256x256 atlas.
    return ("|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t"):format(CLASS_ICON_TEXTURE,
        math.floor(tc[1] * 256 + 0.5), math.floor(tc[2] * 256 + 0.5),
        math.floor(tc[3] * 256 + 0.5), math.floor(tc[4] * 256 + 0.5))
end

local CLASSES, CLASS_SET = {}, {}
do
    local order = CLASS_SORT_ORDER or {}
    for i = 1, #order do
        local token = order[i]
        if type(token) == "string" and not CLASS_SET[token] then
            CLASS_SET[token] = true
            CLASSES[#CLASSES + 1] = {
                token = token,
                name  = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token])
                        or token,
                color = ClassColorHex(token),
                icon  = ClassIconString(token),
            }
        end
    end
end
F.CLASSES   = CLASSES
F.CLASS_SET = CLASS_SET

local _classByToken = {}
for i = 1, #CLASSES do _classByToken[CLASSES[i].token] = CLASSES[i] end

-- Icon + class-colored name, the class twin of BF.SpecFilterLabel. Every
-- Forever dropdown builds its rows through this, so they cannot drift.
function F.ClassLabel(token)
    local e = _classByToken[token]
    if not e then return tostring(token or "") end
    local label = "|cff" .. e.color .. e.name .. "|r"
    if e.icon then return e.icon .. " " .. label end
    return label
end

-- ── Class load condition ───────────────────────────────────────────────────
-- Semantics copied from BF:IsSingleBuffSpecMet, fail-open conventions
-- included: condition off -> loads; class unknown -> loads; no table ->
-- loads; otherwise loadClassTypes[class] ~= false.
function F.IsClassConditionMet(c)
    if type(c) ~= "table" or not c.loadClass then return true end
    local cls = F.playerClass
    if cls == nil then return true end
    local t = c.loadClassTypes
    if type(t) ~= "table" then return true end
    return t[cls] ~= false
end

-- TRUE when the condition is on with NOTHING ticked (twin of
-- BF.SingleBuffSpecConditionEmpty): the entry can never load.
function F.ClassConditionEmpty(c)
    if not (type(c) == "table" and c.loadClass) then return false end
    local t = c.loadClassTypes
    if type(t) ~= "table" then return false end
    for i = 1, #CLASSES do
        if t[CLASSES[i].token] ~= false then return false end
    end
    return #CLASSES > 0
end

-- The one class an entry is restricted to (twin of BF.GetSingleEnabledSpec),
-- or nil for none / several / no condition. Bails at the second hit.
function F.GetSingleEnabledClass(c)
    if not (type(c) == "table" and c.loadClass) then return nil end
    local t = c.loadClassTypes
    if type(t) ~= "table" then return nil end
    local found
    for i = 1, #CLASSES do
        local token = CLASSES[i].token
        if t[token] ~= false then
            if found then return nil end
            found = token
        end
    end
    return found
end

-- The Buff List preview / tree filter value: a class token, or 0 for "All".
-- Deliberately NOT tonumber(v) or 0 (plan 15.1) -- that would turn every
-- token into "All".
function F.NormalizeClassFilter(v)
    if type(v) == "string" and v ~= "" and CLASS_SET[v] then return v end
    return 0
end

-- "Filter by Class" (owner rule, plan E4): an entry shows under a class iff
-- it LOADS for that class. No condition => loads everywhere => shown. A
-- condition with nothing ticked is an incomplete config and stays visible
-- under every selection (the Spec filter's rule). Used by the Buff List
-- tree, the container Add Buff dropdown, the Assigned Spells tree and the
-- Buff List preview painter (through the BF:SingleBuffMatchesSpecFilter hook),
-- so the preview always matches the list.
function F.SingleBuffMatchesClassFilter(c, token)
    if type(c) ~= "table" then return false end
    if token == nil or token == "" or token == 0 then return true end
    local sid = BF.GetSingleBuffDisplaySpellID and BF:GetSingleBuffDisplaySpellID(c) or nil
    if not sid then return false end
    if c.loadClass then
        local t = c.loadClassTypes
        if type(t) ~= "table" then return true end
        if F.ClassConditionEmpty(c) then return true end
        return t[token] ~= false
    end
    return true
end

-- ── D3: Buffs preset class override ────────────────────────────────────────
-- t.classOverrides[TOKEN] = { preset = "<key>", _present = true }, parallel to
-- the Retail specOverrides. Returns the preset key, or nil to fall through to
-- the role and global arms of BF:ResolveBuffsPreset (class -> role -> global).
function F.ResolveBuffsClassPreset(t)
    local co = type(t) == "table" and t.classOverrides
    local cls = F.playerClass
    if type(co) ~= "table" or not cls then return nil end
    local e = co[cls]
    if type(e) == "table" and e._present and e.preset
       and BF.BUFFS_PRESETS and BF.BUFFS_PRESETS[e.preset] then
        return e.preset
    end
    return nil
end
