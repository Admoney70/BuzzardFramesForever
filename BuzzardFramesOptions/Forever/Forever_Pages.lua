-- ============================================================
-- BuzzardFramesOptions: Forever/Forever_Pages.lua
-- WoW Forever only. The options panel's shared Forever machinery.
--
-- On Retail this file exits on its first line and defines nothing, so
-- BuzzardFramesOptions.ForeverUI stays nil and every `-- [FOREVER]` hook
-- in the page files falls through to the Retail code, unchanged.
--
-- What lives here: the ForeverUI table every Forever options file hangs
-- its functions off, the class helpers they share, and the small Forever
-- builders the page files call from their own `-- [FOREVER]` hooks (the
-- preview class list, the non-combat debuff menu).
--
-- Every hidden or replaced option is hooked AT ITS OWN DEFINITION in its
-- page file (owner ruling 2026-11-06) -- `grep "\[FOREVER\]"` lists them.
-- Nothing here edits a page after it is built.
--
-- Loads after Panel.lua (it registers on the table Panel.lua publishes)
-- and before the page files.
-- ============================================================
-- Gate on the client build, NOT on the BuzzardFrames object: this load-on-
-- demand addon must never look the main addon up in its main chunk (see the
-- Panel.lua header -- two earlier versions failed exactly that way). Same
-- test as BF.isForever in BuzzardFrames/Defaults.lua; the runtime's
-- BF.Forever table is created by the runtime files, never here.
local _cli = select(4, GetBuildInfo())
if not (_cli >= 16000 and _cli < 20000) then return end -- not WoW Forever
local function BF() return _G.BuzzardFrames end

local BuzzardFramesOptions = _G.BuzzardFramesOptions
local FUI = BuzzardFramesOptions.ForeverUI or {}
BuzzardFramesOptions.ForeverUI = FUI

-- The runtime's Forever table, read at call time: the runtime files
-- populate it at their own load, and a page is built long after.
local function RT() local bf = BF(); return (bf and bf.Forever) or {} end
FUI.RT = RT

-- ── Classes ────────────────────────────────────────────────────

-- Forever's classes, sorted by display name. The same order every Forever
-- picker uses, the way the Retail spec pickers sort by spec name.
function FUI.SortedClasses()
    local src = RT().CLASSES or {}
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    table.sort(out, function(a, b)
        return (a.name or a.token) < (b.name or b.token)
    end)
    return out
end

function FUI.IsClass(token)
    local set = RT().CLASS_SET
    return type(token) == "string" and set ~= nil and set[token] == true
end

function FUI.ClassName(token)
    local list = RT().CLASSES or {}
    for i = 1, #list do
        if list[i].token == token then return list[i].name or token end
    end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
end

-- The class-colored label every Forever dropdown and list row shows.
function FUI.ClassLabel(token)
    local f = RT().ClassLabel
    if f then return f(token) end
    local list = RT().CLASSES or {}
    for i = 1, #list do
        local c = list[i]
        if c.token == token and c.color then
            return "|cff" .. c.color .. (c.name or token) .. "|r"
        end
    end
    return FUI.ClassName(token)
end

-- A class icon as a texture escape, or "" where the client has no
-- coordinates for it. Used where a row wants the class as a MARK beside
-- its own icon, not as a name.
function FUI.ClassIcon(token, size)
    size = size or 14
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if not tc then return "" end
    return ("|TInterface\\WorldStateFrame\\Icons-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t")
        :format(size, size, tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256)
end

function FUI.PlayerClass()
    local pc = RT().playerClass
    if pc then return pc end
    return UnitClass and select(2, UnitClass("player")) or nil
end

-- The Custom Frame Groups class filter's list: the runtime's own when it
-- publishes one, otherwise Forever's classes sorted by token.
function FUI.ClassSortOrderAlpha()
    local list = RT().CLASS_SORT_ORDER_ALPHA
    if type(list) == "table" and #list > 0 then return list end
    local out = {}
    local src = RT().CLASSES or {}
    for i = 1, #src do out[i] = src[i].token end
    table.sort(out)
    return out
end

-- The option table for a field Forever hides outright (e.g. F5's Blood DK
-- power bars: no Death Knights). Fresh per call -- the panel may annotate it.
-- Show Last Name (Text -> Names and Global Styles -> Names, Modify Names
-- card). The runtime half is BuzzardFrames/Forever/Forever_Names.lua.
FUI.SHOW_LAST_NAME_DESC = "Show each player's surname after their name."

function FUI.AlwaysHiddenOpts()
    return { hidden = true }
end

-- Custom Frame Groups' Class Filter: a class switch's `hidden` on Forever.
-- The Retail rule narrows the list by spec role (ROLE_CLASSES); Forever has
-- no specs and any class can take any role, so every class stays listed.
function FUI.CustomFrameClassHidden(g, token) -- luacheck: ignore g token
    return false
end

-- F13: the preview class dropdowns list only Forever's classes.
function FUI.PreviewClassOptions(src)
    local out = {}
    for i = 1, #(src or {}) do
        local o = src[i]
        if FUI.IsClass(o.value) then out[#out + 1] = o end
    end
    return out
end

-- F15 + F17: of the out-of-combat debuff filters only Deserter exists on
-- Forever, and only its Battleground form (26013).
local LONG_TERM_KEEP = { showDeserterDebuffs = true }
local LONG_TERM_DESC = {
    showDeserterDebuffs = "Show the Battleground Deserter debuff on "
        .. "raid/party frames when out of combat.",
}

-- The Non-Combat Debuffs menu's items, Forever's subset. `list` and
-- `item` are the page's own table and row builder, so a row reads and
-- writes exactly where the Retail row does.
function FUI.LongTermDebuffItems(list, item)
    local out = {}
    for i = 1, #(list or {}) do
        local e = list[i]
        if LONG_TERM_KEEP[e.key] then
            local row = { key = e.key, label = e.label,
                          desc = LONG_TERM_DESC[e.key] or e.desc }
            out[#out + 1] = item(row)
        end
    end
    return out
end
