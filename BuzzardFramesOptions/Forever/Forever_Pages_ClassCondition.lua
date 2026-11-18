-- ============================================================
-- BuzzardFramesOptions: Forever/Forever_Pages_ClassCondition.lua
-- WoW Forever only. The Class load condition and Filter by Class (plan
-- E3 / E4, F2 / F3), for Pages_AuraContainers.lua:
--
--   * ClassConditionCards -- the "Class" card, its switch in the card
--     header (with "Select My Class"), that a Buff List entry or a container
--     shows in place of the Spec switch, the Specs card and "Select Current
--     Spec".
--     Storage: c.loadClass (true / nil) and c.loadClassTypes, where
--     `[TOKEN] = false` is OFF and an absent key is ON -- the Spec
--     condition's own convention. Never writes loadSpec / loadSpecTypes.
--   * Filter by Class -- in place of BOTH Filter by Spec dropdowns: the
--     Buff List's (list column) and a buff container's (Assigned Spells,
--     "Select from Buff List"). Values are class TOKENS, never numbers.
--     Rule (owner): an entry shows under a class iff it LOADS for that
--     class -- BF.Forever.SingleBuffMatchesClassFilter, the same test the
--     Buff List preview painter uses, so the preview matches the list.
--   * The Buff List row's "!" incomplete mark and single-class mark.
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
local FUI   = BuzzardFramesOptions.ForeverUI
local RT    = FUI.RT

local ALL = "ALL"

-- ── The runtime's class-condition answers, with the convention as the
-- fallback while a runtime function is missing ──────────────────

local function ConditionEmpty(c)
    local f = RT().ClassConditionEmpty
    if f then return f(c) and true or false end
    if not (type(c) == "table" and c.loadClass) then return false end
    local t = c.loadClassTypes
    if type(t) ~= "table" then return false end
    for _, cl in ipairs(RT().CLASSES or {}) do
        if t[cl.token] ~= false then return false end
    end
    return true
end

local function SingleEnabledClass(c)
    local f = RT().GetSingleEnabledClass
    if f then return f(c) end
    return nil
end

local function MatchesClass(c, token)
    if token == nil or token == "" or token == ALL then return true end
    local f = RT().SingleBuffMatchesClassFilter
    if f then return f(c, token) and true or false end
    if not (type(c) == "table" and c.loadClass) then return true end
    local t = c.loadClassTypes
    return type(t) ~= "table" or t[token] ~= false
end

local function ClassFilterOptions()
    local out = { { value = ALL, text = "All" } }
    for _, cl in ipairs(FUI.SortedClasses()) do
        out[#out + 1] = { value = cl.token, text = FUI.ClassLabel(cl.token) }
    end
    return out
end

-- ══ The Class load condition ══════════════════════════════════

-- Densify on first write, as EnsureSpecTypes does: the first un-tick
-- writes `true` for every other class. A WRITE-path helper.
local function EnsureClassTypes(c)
    local t = c.loadClassTypes
    if type(t) ~= "table" then
        t = {}
        for _, cl in ipairs(RT().CLASSES or {}) do t[cl.token] = true end
        c.loadClassTypes = t
    end
    return t
end

-- The two cards. `appliedBy` and `combatStatus` are the page's own Applied By
-- and Combat Status fields, `conditionsRefresh` the page's ConditionsRefresh,
-- and `onChanged` the caller's targeted refresh -- the same the Retail cards
-- use. The Class condition's switch is the "Class" card's header toggle
-- (owner, 2026-11-15): off, the card collapses to its header.
function FUI.ClassConditionCards(getC, subject, onChanged, appliedBy, conditionsRefresh, combatStatus)
    local function refresh(ctx)
        local bf = BuzzardFramesOptions:BF()
        if bf and bf.RefreshContainersWithRebuildDebounced then
            bf:RefreshContainersWithRebuildDebounced()
        end
        if onChanged then
            -- The caller's targeted refresh names the Retail card id
            -- ("bfSpecs"); the Class card below is "bfClasses", so it is
            -- refreshed here first, as the Retail path does its own card
            -- before the list row. RefreshGroup is a no-op for an id the
            -- page does not show.
            if ctx and ctx.app then ctx.app:RefreshGroup("bfClasses") end
            onChanged(ctx)
        elseif ctx and ctx.app then ctx.app:RefreshPage() end
    end
    local classFields = {
        -- What the switches below add up to, as the Specs card's read-out.
        { control = "note", wide = true,
          desc = function()
              local c = getC()
              local t = c and c.loadClassTypes
              if type(t) ~= "table" then return "Every class." end
              local out, n, total = {}, 0, 0
              for _, cl in ipairs(FUI.SortedClasses()) do
                  total = total + 1
                  if t[cl.token] ~= false then
                      n = n + 1
                      out[#out + 1] = FUI.ClassLabel(cl.token)
                  end
              end
              if n == 0 then
                  return "|cffff4444No classes are selected, so " .. subject
                      .. " will never show.|r"
              end
              if n >= total then return "Every class." end
              return table.concat(out, "\n")
          end,
          text = function()
              local lead = "|cffffd100Enabled for Classes:|r "
              local c = getC()
              local t = c and c.loadClassTypes
              if type(t) ~= "table" then return lead .. "All" end
              local out, n, total = {}, 0, 0
              for _, cl in ipairs(FUI.SortedClasses()) do
                  total = total + 1
                  if t[cl.token] ~= false then
                      n = n + 1
                      out[#out + 1] = FUI.ClassLabel(cl.token)
                  end
              end
              -- None FIRST, so an empty class table can never report "All".
              if n == 0 then
                  return lead .. "|cffff4444None|r |cffaaaaaaNo classes are "
                      .. "selected, so " .. subject .. " will never show. "
                      .. "Check at least one below, or turn the Class "
                      .. "condition off in this card's header.|r"
              end
              if n >= total then return lead .. "All" end
              return lead .. table.concat(out, ", ")
          end },

        { control = "button", disabled = "combat", newRow = true,
          -- The label IS the state: "Select All" while anything is off.
          label = function()
              local c = getC()
              local t = c and c.loadClassTypes
              if type(t) ~= "table" then return "Deselect All" end
              for _, cl in ipairs(RT().CLASSES or {}) do
                  if t[cl.token] == false then return "Select All" end
              end
              return "Deselect All"
          end,
          onClick = function(_, ctx)
              if InCombatLockdown() then return end
              local c = getC()
              if not c then return end
              local t, allChecked = c.loadClassTypes, true
              if type(t) == "table" then
                  for _, cl in ipairs(RT().CLASSES or {}) do
                      if t[cl.token] == false then allChecked = false; break end
                  end
              end
              local target = not allChecked
              t = {}
              for _, cl in ipairs(RT().CLASSES or {}) do t[cl.token] = target end
              c.loadClassTypes = t
              refresh(ctx)
          end },

        { control = "button", label = "Select My Class",
          desc = "Check only your own class, and uncheck every other.",
          disabled = function()
              return InCombatLockdown() or not FUI.IsClass(FUI.PlayerClass())
          end,
          onClick = function(_, ctx)
              if InCombatLockdown() then return end
              local c  = getC()
              local pc = FUI.PlayerClass()
              if not (c and FUI.IsClass(pc)) then return end
              local t = {}
              for _, cl in ipairs(RT().CLASSES or {}) do t[cl.token] = (cl.token == pc) end
              c.loadClassTypes = t
              refresh(ctx)
          end },
    }

    for i, cl in ipairs(FUI.SortedClasses()) do
        local token = cl.token
        classFields[#classFields + 1] = {
            control = "switch", label = FUI.ClassLabel(token),
            labelSide = "after", cellWidth = 130,
            -- Three to a row after the buttons, which take the row above.
            newRow = (i == 1) or nil,
            tooltipTitle = FUI.ClassName(token),
            disabled = "combat",
            get = function()
                local c = getC()
                local t = c and c.loadClassTypes
                return type(t) ~= "table" or t[token] ~= false
            end,
            set = function(_, ctx, val)
                if InCombatLockdown() then return end
                local c = getC()
                if not c then return end
                EnsureClassTypes(c)[token] = val and true or false
                refresh(ctx)
            end,
        }
    end

    return {
        { title = "Conditions", preset = "form", fields = {
            appliedBy,
            -- Same row as Applied By (owner, 2026-11-15).
            combatStatus,
        }},
        { title = "Class", preset = "form", id = "bfClasses",
          toggle = {
              id = "loadClass", default = false, disabled = "combat",
              tooltip = "Class",
              desc = "Only show " .. subject .. " while your class is checked "
                  .. "below. When off, it shows on every class.",
              get = function()
                  local c = getC()
                  return (c and c.loadClass) and true or false
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local c = getC()
                  if not c then return end
                  c.loadClass = val and true or nil
                  -- The FIRST enable pins the condition to the player's own
                  -- class: every OTHER class is written OFF. First time
                  -- only: an existing table is left alone.
                  if val and type(c.loadClassTypes) ~= "table" then
                      local pc, t = FUI.PlayerClass(), {}
                      for _, cl in ipairs(RT().CLASSES or {}) do
                          t[cl.token] = (cl.token == pc)
                      end
                      c.loadClassTypes = t
                  end
                  conditionsRefresh(ctx)
              end },
          fields = classFields },
    }
end

-- ══ Filter by Class: a buff container's Assigned Spells ════════

-- Session-only and shared by every container page, as the Retail
-- containerSpecFilter is. PRESENTATIONAL: it hides cards, writes nothing.
local containerClassFilter = ALL

function FUI.ContainerClassFilterField(hidden)
    return {
        control = "dropdown", label = "Filter by Class",
        hidden = hidden,
        desc = "Show only Buff List entries that load for that class: "
            .. "entries with no Class condition load for every class, and "
            .. "an entry with one loads for the classes it checks.",
        options = ClassFilterOptions,
        get = function() return containerClassFilter end,
        set = function(_, ctx, val)
            containerClassFilter = FUI.IsClass(val) and val or ALL
            ctx.app:RefreshPage()
        end,
    }
end

function FUI.ContainerClassFilterHides(sb)
    if containerClassFilter == ALL then return false end
    return not MatchesClass(sb, containerClassFilter)
end

-- ══ Filter by Class: the Buff List ═════════════════════════════

local buffListClassFilter = ALL
-- While the user has not picked a value this session, the filter FOLLOWS
-- the player's class, as Filter by Spec follows the player's spec.
local buffListClassFilterTouched = false
-- The page's own session-exempt set and route-to-key helper, bound once
-- by a hook in Pages_AuraContainers.lua.
local bound = {}

function FUI.BindBuffList(t)
    bound = t or {}
end

local function SeedClassFilter()
    if buffListClassFilterTouched then return end
    local pc = FUI.PlayerClass()
    if FUI.IsClass(pc) and buffListClassFilter ~= pc then
        buffListClassFilter = pc
    end
end

-- What the Buff List preview is told: a class token, or 0 for All -- the
-- same "0 = All" a Filter by Spec value uses.
local function PreviewFilter()
    SeedClassFilter()
    return (buffListClassFilter == ALL) and 0 or buffListClassFilter
end
FUI.BuffListPreviewFilter = PreviewFilter

function FUI.BuffListClassFilterHides(sid, c, exempt) -- luacheck: ignore sid
    SeedClassFilter()
    local f = buffListClassFilter
    if f == ALL then return false end
    if type(c) == "table" and exempt and exempt[c] then return false end
    return not MatchesClass(c, f)
end

-- A just-added entry the class filter would hide clears the filter, as
-- AddSingleBuff clears Filter by Spec.
function FUI.BuffListClassFilterOnAdd(c)
    if buffListClassFilter == ALL or not c then return end
    if not MatchesClass(c, buffListClassFilter) then
        buffListClassFilter = ALL
        buffListClassFilterTouched = true
    end
end

function FUI.BuffListFilterWhy(searchOn)
    if searchOn and buffListClassFilter ~= ALL then return "Filter by Class and Search" end
    if searchOn then return "Search" end
    return "Filter by Class"
end

-- EnterSingleBuffs' preview stamp, with the class filter. `bf` is the
-- page's BF() (the Custom Frame Groups proxy under a group's scope).
function FUI.EnterBuffListPreview(bf, sel, first)
    local f     = PreviewFilter()
    local was   = bf.IsPreviewingBuffList and bf:IsPreviewingBuffList() or false
    local prevF = bf.GetBuffListPreviewFilter and bf:GetBuffListPreviewFilter() or nil
    local prevK = bf.GetBuffListPreviewKey and bf:GetBuffListPreviewKey() or nil
    local changed = (not was) or prevF ~= f or prevK ~= sel
    if bf.SetBuffListPreview then bf:SetBuffListPreview(f, sel) end
    if (changed or first) and not InCombatLockdown() and bf.RefreshPreviewDummyAuras then
        bf:RefreshPreviewDummyAuras()
    end
end

local function BuffListClassFilterField()
    return {
        control = "dropdown", label = "Filter by Class",
        labelPlacement = "above", width = "full",
        desc = "Show only Buff List entries that load for that class: "
            .. "entries with no Class condition load for every class, and an "
            .. "entry with one loads for the classes it checks.",
        options = ClassFilterOptions,
        get = function()
            SeedClassFilter()
            return buffListClassFilter
        end,
        set = function(_, ctx, val)
            local bf = BuzzardFramesOptions:BF()
            buffListClassFilter = FUI.IsClass(val) and val or ALL
            -- A manual change ends the session exemption for entries added
            -- this session, and ends following the player's class.
            if bound.exempt then wipe(bound.exempt) end
            buffListClassFilterTouched = true
            if bf and bf.SetBuffListPreview then
                local r  = ctx.app.route
                local rk = type(r) == "table" and table.concat(r, "/") or nil
                bf:SetBuffListPreview(PreviewFilter(),
                    bound.selectedKey and bound.selectedKey(rk) or nil)
            end
            if not InCombatLockdown() and bf and bf.RefreshPreviewDummyAuras then
                bf:RefreshPreviewDummyAuras()
            end
            ctx.app:Invalidate("singleBuffs")
            ctx.app:RefreshPage()
        end,
    }
end

FUI.BuffListClassFilterField = BuffListClassFilterField

-- A Buff List row's title on Forever: the single-class mark (an entry
-- whose Class condition checks exactly one class), the spell icon, the
-- label, and the "!" mark for a Class condition with nothing checked.
function FUI.BuffListRowTitle(c, tex, label)
    local warn = ConditionEmpty(c)
        and " |TInterface\\GossipFrame\\AvailableQuestIcon:14:14:0:0|t" or ""
    local pinned = SingleEnabledClass(c)
    local pin = pinned and FUI.ClassIcon(pinned, 14) or ""
    if pin ~= "" then pin = pin .. " " end
    return pin .. (tex and ("|T" .. tex .. ":14:14:0:0|t ") or "") .. label .. warn
end
