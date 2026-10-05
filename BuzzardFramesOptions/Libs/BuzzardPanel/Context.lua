-- ============================================================
-- BuzzardPanel: Context.lua
-- Right-click menus on fields and group headers.
--
-- The rule this file exists to keep: NOTHING IS RESERVED FOR IT. No glyph
-- beside a label, no hover affordance, no column held open for a button
-- that is usually absent. Reset is a rare action and paying layout for it
-- on every row is the wrong trade -- so it lives entirely in a right-click.
--
-- Two menus, deliberately short:
--
--   on a field         Undo change        (only when there is one)
--                      Reset to default   (only when a default is known)
--
--   on a group header  Reset group to defaults
--                      Copy group to <target>   (only when the page says how)
--
-- An entry that cannot do anything is not shown rather than shown grayed:
-- a two-item menu is read at a glance, and a disabled item in it is just
-- something to wonder about.
-- ============================================================
local ADDON, ns = ...

ns.context = {}

local function Menu(owner, build)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
end

-- Every setting a node touches: one for a plain control, several for a
-- composite. Returned as {bind = path, node = nodeToWriteThrough}.
local function BoundKeys(node)
    local out = {}
    if node.bind then out[#out + 1] = { bind = node.bind, node = node } end
    for _, bound in pairs(node.binds or {}) do
        -- Through the entry's OWN node, so a composite setting with a
        -- custom writer is Undone and Reset the same way it is set. A bare
        -- path still becomes `{ bind = path }`, which is what this was.
        local n = ns.BindNode(bound, {})
        out[#out + 1] = { bind = ns.BindPath(bound) or n.id, node = n }
    end
    -- A field with a get/set pair and no bind has no path to look a default
    -- up by, but it can still declare one outright -- and then Reset works.
    --
    -- An `id` ALONE is enough to be listed here, because ns.SetValue records
    -- undo under `node.bind or node.id`: gating this on a default as well
    -- meant such a field had an undo point recorded that the menu could
    -- never reach. Reset stays gated where it belongs -- on a default
    -- actually existing -- which DefaultFor answers on its own.
    if #out == 0 and node.set and (node.default ~= nil or node.id) then
        out[#out + 1] = { bind = node.id, node = node, direct = true }
    end
    return out
end

-- A composite's own `binds` entries are written through throwaway nodes, so
-- the undo record and the write both address the real setting rather than
-- the composite as a whole.
local function ResetOne(app, ctx, entry)
    -- Spelled out rather than `entry.direct and nil or entry.bind`, which
    -- CANNOT return nil: `true and nil or x` is `nil or x` is `x`. That is
    -- what made Reset silently do nothing for every field that declares a
    -- default without a bind -- the direct case passed the bind path after
    -- all, DefaultFor looked it up in the page's defaults, and found none.
    local bindPath
    if not entry.direct then bindPath = entry.bind end
    local def, known = ns.DefaultFor(entry.node, ctx, bindPath)
    if not known then return false end
    ns.SetValue(entry.node, ctx, def)
    app:RefreshBinding(entry.bind)
    return true
end

local function HasDefault(node, ctx)
    for _, e in ipairs(BoundKeys(node)) do
        -- Same trap as ResetOne above: this must pass nil for a direct
        -- entry, and `and nil or` never does.
        local bindPath
        if not e.direct then bindPath = e.bind end
        local _, known = ns.DefaultFor(e.node, ctx, bindPath)
        if known then return true end
    end
    return false
end

local function HasUndo(app, node)
    for _, e in ipairs(BoundKeys(node)) do
        if app.undo and app.undo[e.bind] ~= nil then return true end
    end
    return false
end

-- ── Field menu ─────────────────────────────────────────────────

function ns.context.FieldMenu(owner, app, node, ctx)
    local undo    = HasUndo(app, node)
    local canReset = HasDefault(node, ctx)
    if not (undo or canReset) then return end

    Menu(owner, function(root)
        if undo then
            root:CreateButton("Undo change", function()
                for _, e in ipairs(BoundKeys(node)) do
                    local rec = app.undo and app.undo[e.bind]
                    if rec ~= nil then
                        -- Written through SetValue so a node with its own
                        -- setter is honored, then the record is CONSUMED:
                        -- undo is one level, and leaving it in place would
                        -- let the entry toggle between two values forever.
                        ns.SetValue(e.node, ctx, rec.value)
                        app.undo[e.bind] = nil
                        app:RefreshBinding(e.bind)
                    end
                end
                -- One effect after the whole restore, and on the node's
                -- own tier: undoing a heavy setting should not be the one
                -- path that runs the heavy pass inline.
                ns.FireEffect(node, ctx)
            end)
        end
        if canReset then
            root:CreateButton("Reset to default", function()
                for _, e in ipairs(BoundKeys(node)) do ResetOne(app, ctx, e) end
                ns.FireEffect(node, ctx)
            end)
        end
    end)
end

-- ── Group menu ─────────────────────────────────────────────────

-- `group.copy` is how a page offers "copy this group somewhere else":
--     copy = {
--         targets = function() return { {value=..., text=...}, ... } end,
--         apply   = function(target, group, ctx) ... end,
--     }
-- Without it the menu is a single entry, which is correct -- a panel with
-- no notion of layouts should not be offered a copy that does nothing.
function ns.context.GroupMenu(owner, app, group, ctx)
    Menu(owner, function(root)
        root:CreateButton("Reset group to defaults", function()
            local touched = false
            -- A gated card's switch lives in its HEADER rather than among
            -- its fields, and is still one of the group's settings -- so it
            -- resets with them. It needs an `id` and a `default` for the
            -- same reason any get/set field does.
            local t = group.toggle
            if t and t.set and (t.default ~= nil or t.id) then
                local node = {
                    id = t.id, default = t.default,
                    get = function(_, c) return t.get and t.get(group, c) end,
                    set = function(_, c, v) t.set(group, c, v) end,
                }
                for _, e in ipairs(BoundKeys(node)) do
                    if ResetOne(app, ctx, e) then touched = true end
                end
            end
            for _, field in ipairs(group.fields or {}) do
                for _, e in ipairs(BoundKeys(field)) do
                    if ResetOne(app, ctx, e) then touched = true end
                end
            end
            -- One page render rather than one per field: a group reset can
            -- change predicates as well as values, and re-rendering once at
            -- the end is both cheaper and more correct than N binding
            -- refreshes that each see a half-reset group.
            if touched then app:RenderPage() end
        end)

        local copy = group.copy
        if copy and copy.apply then
            local targets = copy.targets
            if type(targets) == "function" then targets = targets() end
            if type(targets) == "table" and #targets > 0 then
                -- A real submenu, not an indented list: the targets are a
                -- second choice, and flattening them into the same menu
                -- would break the two-entry rule the moment an addon has
                -- more than a couple of layouts.
                local sub = root:CreateButton(copy.label or "Copy group to")
                for _, t in ipairs(targets) do
                    local value = (type(t) == "table") and t.value or t
                    local text  = (type(t) == "table") and t.text  or tostring(t)
                    sub:CreateButton(text, function()
                        copy.apply(value, group, ctx)
                        app:RenderPage()
                    end)
                end
            end
        end
    end)
end

-- ── Hit areas ──────────────────────────────────────────────────
--
-- A right-click target is an invisible button, sized to whatever it covers
-- and registered for the right button ONLY, so it never eats a left click
-- meant for the control underneath.

function ns.context.Hit(parent, onRightClick)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnClick", onRightClick)
    return b
end

-- ── Right-click on the control itself ──────────────────────────
--
-- An invisible overlay is NOT how this is done. A mouse-enabled frame
-- swallows hit-testing for every button, whatever it is registered for, so
-- a right-click catcher laid over a control would eat the left click meant
-- for the control underneath.
--
-- OnMouseUp is the way in: it fires for any button the frame receives,
-- independently of RegisterForClicks, which governs OnClick only. So the
-- control's own left-click behavior is untouched and we simply listen for
-- the right one.
--
-- Hooked ONCE per frame and dispatched through a field, because a composite's
-- sub-widgets are never released and HookScript accumulates -- hooking every
-- render would stack a new closure each time. The flag is `_bp_` prefixed so
-- the pool's scrub clears it along with the scripts it clears.
-- ONLY frames that already take mouse input.
--
-- Attaching a mouse script to a decorative Frame changes the input topology
-- of the control: the switch's track is a plain Frame sitting exactly over
-- the visible pill, and hooking it made it start intercepting clicks -- so
-- the pill went dead while the empty part of the switch's frame beside it
-- still worked. Nothing here may make a frame clickable that was not
-- clickable before.
local function TakesMouse(frame)
    return frame and frame.IsMouseEnabled and frame:IsMouseEnabled()
end

local function HookRight(frame)
    if not (frame and frame.HookScript and frame.HasScript) then return end
    if not TakesMouse(frame) then return end
    if not frame:HasScript("OnMouseUp") then return end
    if frame._bp_rightHooked then return end
    frame._bp_rightHooked = true
    frame:HookScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.bpRightFn then self.bpRightFn(self) end
    end)
end

local function Attach(frame, fn, depth)
    if not frame then return end
    -- Walk THROUGH a decorative frame to whatever is clickable underneath
    -- it, but never hook the decoration itself.
    if TakesMouse(frame) then
        frame.bpRightFn = fn
        HookRight(frame)
    end
    if depth <= 0 then return end
    -- Children too: a segmented picker is clicked on one of its segments, a
    -- composite on one of its sub-controls, and the reader does not know or
    -- care which frame that is.
    for _, child in ipairs({ frame:GetChildren() }) do
        Attach(child, fn, depth - 1)
    end
end

-- Give a field's whole widget -- and what it is built from -- the same
-- right-click menu its label has.
function ns.context.AttachField(widget, app, node, ctx)
    Attach(widget, function(self)
        ns.context.FieldMenu(self, app, node, ctx)
    end, 2)
end

-- ── Tooltips ───────────────────────────────────────────────────
--
-- `desc` on any field or group is hover help. It may be a string or a
-- function, so text that depends on the current value stays correct
-- without the page rebuilding.
--
-- A tooltip says what the setting is. Nothing else. It does not advertise
-- the right-click menu: a line repeated on every tooltip in the panel stops
-- being information after the first one and is then just noise on all the
-- rest.

local function DescOf(node, ctx)
    local d = node and (node.desc or node.tooltip)
    if type(d) == "function" then d = d(node, ctx) end
    return d
end

-- Our OWN tooltip frame, not GameTooltip.
--
-- This is what other options dialogs do, and the reason is the one that bit
-- here: GameTooltip is shared with the entire UI. Its position, its scale,
-- its mouse state and its script hooks belong to whoever touched it last,
-- and a tooltip that another addon has made mouse-enabled will sit over the
-- panel and swallow clicks. A private frame has none of those questions --
-- it is ours, it is only ever used by this panel, and nothing else can
-- have configured it.
local tip
local function Tip()
    if not tip then
        tip = CreateFrame("GameTooltip", "BuzzardPanelTooltip", UIParent,
                          "GameTooltipTemplate")
    end
    return tip
end

local ShowTip
function ns.context.Show(owner, app, title, desc) return ShowTip(owner, app, title, desc) end
function ns.context.Hide() if tip then tip:Hide() end end

-- WHERE THE TOOLTIP GOES: bottom-left over the control's top-left.
--
-- An anchor NAME cannot say that. ANCHOR_TOPRIGHT -- which is what this
-- used, and what most options dialogs pass -- puts the tooltip's bottom-right
-- at the owner's top-right, so a tooltip several hundred wide runs back
-- across the panel and reads as belonging to whatever it lands over rather
-- than to the control being hovered. They get away with it because their
-- widget frames are the whole option cell; ours are the control.
--
-- So the point is stated outright, the way tab tooltips elsewhere are
-- (ANCHOR_NONE plus a SetPoint). `app.tooltipAnchor` still works: a
-- consumer that names an anchor gets that anchor and none of this.
local TIP_GAP = 4    -- between the control's top and the tooltip's bottom

function ShowTip(owner, app, title, desc)
    if not owner or (not desc and not title) then return end
    local skin = app.skin
    local t = Tip()
    local named = app.tooltipAnchor
    if named then
        t:SetOwner(owner, named)
    else
        t:SetOwner(owner, "ANCHOR_NONE")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, TIP_GAP)
    end
    if title and title ~= "" then
        local h = skin.tooltipTitle or skin.accent or skin.text
        t:SetText(title, h[1], h[2], h[3], 1, true)
    else
        t:ClearLines()
    end
    if desc then
        local c = skin.tooltipText or skin.textNote or skin.textMuted
        t:AddLine(desc, c[1], c[2], c[3], true)   -- true = wrap
    end
    t:Show()

    -- KEPT ON SCREEN, after Show, which is the first moment the tooltip has
    -- a size: its height comes from text that has just been wrapped to a
    -- width the tooltip chose for itself.
    --
    --   too tall for the room above  -> hang it BELOW the control instead
    --   too wide for the room right  -> slide it left until it fits
    --
    -- Both re-state the point rather than nudging the old one, so a second
    -- hover cannot inherit the first one's correction.
    if named then return end
    local screenH = (UIParent:GetHeight() or 0)
    local screenW = (UIParent:GetWidth() or 0)
    local top     = (t:GetTop() or 0)
    local right   = (t:GetRight() or 0)
    local below   = top > screenH
    local overW   = math.max(0, right - screenW)
    if below or overW > 0 then
        t:ClearAllPoints()
        if below then
            t:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -overW, -TIP_GAP)
        else
            t:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -overW, TIP_GAP)
        end
    end
end

-- Same once-only hook as the right-click wiring, and for the same reason.
local function HookHover(frame)
    if not (frame and frame.HookScript and frame.HasScript) then return end
    if not TakesMouse(frame) then return end
    if not frame:HasScript("OnEnter") then return end
    if frame._bp_tipHooked then return end
    frame._bp_tipHooked = true
    frame:HookScript("OnEnter", function(self)
        if self.bpTipFn then self.bpTipFn(self) end
    end)
    frame:HookScript("OnLeave", function(self)
        if self.bpTipFn then ns.context.Hide() end
    end)
end

-- `fn` ignores which frame was entered: every frame in a field shows the
-- SAME tooltip in the SAME place, anchored to the field's own widget.
local function AttachTip(frame, fn, depth)
    if not frame then return end
    -- A frame that has claimed its own tooltip keeps it. The anchor pad's
    -- cells each name their own position, which is more useful than the
    -- field's description repeated nine times.
    if frame.bpTipOwn then return end
    if TakesMouse(frame) then
        frame.bpTipFn = fn
        HookHover(frame)
    end
    if depth <= 0 then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        AttachTip(child, fn, depth - 1)
    end
end

-- `tooltipTitle` overrides the heading the tooltip takes from the field's
-- LABEL. For a control whose label is a picture: a spec toggle labeled
-- with its spec icon put that icon on the title line and the spec's name
-- on the line under it, which reads as a break in the middle of one
-- phrase. Naming the title lets the whole phrase -- icon, name, class --
-- be one line, with no description under it at all.
local function TipTitle(node, ctx)
    local t = node.tooltipTitle
    if t ~= nil then
        if type(t) == "function" then t = t(node, ctx) end
        return (t ~= false) and t or nil
    end
    -- Through FieldLabel, not raw: a function-valued label (a stepper's
    -- "Row/Column Spacing") must be RESOLVED to a string here, or it reaches
    -- SetText as a function and errors. FieldLabel calls it and tostring's it.
    return ns.FieldLabel(node)
end

function ns.context.AttachFieldTooltip(widget, app, node, ctx, label)
    local desc = DescOf(node, ctx)
    -- A title of its own is reason enough to have a tooltip: the field
    -- that names one usually has nothing left to put in a description.
    if not desc and node.tooltipTitle == nil then
        -- Nothing to say: make sure a pooled widget stops saying the last
        -- field's piece. Cleared over the same subtree it is SET over --
        -- a widget whose mouse-taking part is a child holds the tooltip on
        -- that child, so clearing only the top frame leaves the old text
        -- live on everything under it.
        AttachTip(widget, nil, 2)
        if label then AttachTip(label, nil, 0) end
        return
    end
    -- Evaluated on HOVER, not captured here. A `desc` function exists
    -- precisely so the text can depend on the current value; capturing its
    -- result at render time freezes it, and the tooltip then describes the
    -- state the field was in when the page was last built. The title is
    -- read on hover for the same reason.
    local fn = function()
        ShowTip(widget, app, TipTitle(node, ctx), DescOf(node, ctx))
    end
    AttachTip(widget, fn, 2)
    if label then AttachTip(label, fn, 0) end
end

-- A tooltip that belongs to ONE frame, with text of its own rather than the
-- field's. For a part of a control that is its own thing: a gated card's
-- header switch, a row button inside a composite. Pass no title and no desc
-- to clear it.
--
-- The caller is expected to set `frame.bpTipOwn` if the frame sits inside a
-- field's widget tree -- that is what stops AttachFieldTooltip's walk
-- replacing this with the field's description.
function ns.context.AttachOwnTooltip(frame, app, title, desc)
    if not frame then return end
    if not (title or desc) then AttachTip(frame, nil, 0); return end
    AttachTip(frame, function() ShowTip(frame, app, title, desc) end, 0)
end

-- The tooltip for a gated card's header switch. Its own, rather than the
-- group's: the switch is one SETTING and the card is a section, and a
-- reader hovering the switch is asking what the switch does.
function ns.context.AttachToggleTooltip(gate, app, title, desc)
    return ns.context.AttachOwnTooltip(gate, app, title, desc)
end

function ns.context.AttachGroupTooltip(hit, app, group, ctx)
    local desc = DescOf(group, ctx)
    if not desc then hit.bpTipFn = nil; return end
    local title = group.title
    -- Anchored to the TITLE, not to the header: the header is as wide as
    -- the group, and hanging a tooltip off its edge puts it nowhere near
    -- the thing being described.
    local anchor = hit:GetParent() and hit:GetParent():GetParent()
    anchor = (anchor and anchor.title) or hit
    AttachTip(hit, function() ShowTip(anchor, app, title, desc) end, 0)
end
