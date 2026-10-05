-- ============================================================
-- BuzzardFramesOptions: Pages_Frames.lua
-- The Raid/Party Frames > Frame Configuration > Size & Position page,
-- in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Frames.lua
-- (BF:BuildFramesOptions): the same settings, the same storage and the
-- same side effects, with the AceConfig args table replaced by a
-- BuzzardPanel page. Both descriptions exist while both panels do; an
-- edit in either lands in the same place, so they cannot drift apart in
-- what they STORE -- only in what they show.
--
-- Storage: the modifying flat itself -- rpDB.profile.layouts.flatLayouts
-- [BF._modifyingFlat], falling back to flat_party exactly as the Ace
-- page's getFramesProfile does. Frames is ALWAYS per-Layout by design
-- (every flat owns its own position/size/spacing), so there is no
-- per-Layout toggle here: the scope strip carries only the Modifying
-- dropdown and the whole-flat Copy-to. Reads fall through each flat's
-- WireFlatDefaults __index template for anything the user never touched;
-- writes land as raw keys on the flat, which is what AceDB persists.
--
-- THE PAGE'S STRUCTURE DEPENDS ON THE FLAT: a raid flat carries the Show
-- Raid Groups card and a party flat does not (an empty titled card is
-- worse than none). So the page is rebuilt -- ctx.app:Invalidate(), not
-- RefreshPage() -- whenever the Modifying dropdown changes the flat, and
-- a route observer self-heals the one gap that leaves: Modifying changed
-- from ANOTHER page's strip (which only calls RefreshPage) while this
-- page sat memoised with the old flat's shape.
--
-- That gap is no longer load-bearing. The library DOES take a
-- group-level `hidden` now (it did not when this page was written), and
-- the card carries one, so a render that arrives holding the wrong flat
-- draws no card instead of drawing one whose fields read keys a party
-- flat has never had. Rebuilding is still what keeps the page HONEST --
-- the card should not merely be invisible, it should not be there -- but
-- a missed rebuild is now a cosmetic staleness rather than an error.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- The addon, or -- while a Custom Frame Group page is being built,
-- rendered or committed -- a proxy that answers the section and flat
-- questions for the selected group. One line, and every declaration in
-- this file edits that group instead. See Pages_CustomFrameSections.lua.
local function BF() return BuzzardFramesOptions:BF() end

-- ── The flat being modified ────────────────────────────────────

local function FlatLayouts()
    local bf = BF()
    return (bf and bf.rpDB and bf.rpDB.profile.layouts.flatLayouts) or {}
end

-- Party flats first, then raid, each alphabetical by name; the ACTIVE
-- Layout is tinted green, which is how the Ace dropdown has always shown
-- the difference between "active" and "being edited".
local function FlatOptions()
    local bf = BF()
    local fl = FlatLayouts()
    local activeID = bf and bf.ResolveActiveFlat and bf:ResolveActiveFlat(bf:GetActiveSlot())
    local party, raid = {}, {}
    for id, flat in pairs(fl) do
        if type(flat) == "table" then
            local into = (flat.type == "party") and party or raid
            into[#into + 1] = id
        end
    end
    local function byName(a, b)
        return ((fl[a].name or a):lower()) < ((fl[b].name or b):lower())
    end
    table.sort(party, byName)
    table.sort(raid,  byName)

    local out = {}
    local function add(id)
        local name = fl[id].name or id
        out[#out + 1] = {
            value = id,
            text  = (id == activeID) and ("|cff76CC4B" .. name .. "|r") or name,
        }
    end
    for _, id in ipairs(party) do add(id) end
    for _, id in ipairs(raid)  do add(id) end
    return out
end

-- _modifyingFlat can be unset (a fresh session) or name a Layout that has
-- since been deleted, so it falls back the way the Ace page's
-- getFramesProfile does: flat_party first, then whatever exists.
local function CurrentFlat()
    local bf = BF()
    local fl = FlatLayouts()
    local cur = bf and bf._modifyingFlat
    if cur and fl[cur] then return cur end
    if fl.flat_party then return "flat_party" end
    local opts = FlatOptions()
    return opts[1] and opts[1].value
end

-- The data source for every field on this page. The SAME resolution the
-- dropdown shows, so the predicates below cannot disagree with the data --
-- the Ace file records the crash that disagreement caused.
local function GetFlat()
    local bf = BF()
    -- The one question the proxy cannot answer by method: `_modifyingFlat`
    -- is a FIELD whose value is an ID looked up in the Raid/Party
    -- flatLayouts, and a Custom Frame Group's flat is not in there. The two
    -- cards this file exports (Size and Scale) are rendered on the Custom
    -- Frame Groups page against that group's flat, so the scope is asked
    -- outright -- which also keeps IsParty/IsRaid, Defaults and ROOT
    -- agreeing with the data, the disagreement the Ace file records a crash
    -- from.
    if bf and bf.BFOScopeFlat then return bf:BFOScopeFlat() end
    local fl = FlatLayouts()
    return fl[CurrentFlat()]
end

-- isParty/isRaid must derive from the SAME flat GetFlat() returns:
-- with _modifyingFlat unset the data source falls back to flat_party, and
-- a naive lookup answering "neither" would expose the raid group1-8
-- toggles against a party flat that has no showGroup.
local function IsParty()
    local f = GetFlat()
    return (f and f.type == "party") or false
end
local function IsRaid() return not IsParty() end

-- What a key resets TO. The flat's own WireFlatDefaults template
-- (CreateRaidProfile / CreatePartyProfile) is the single source: it is
-- what an untouched key already reads through, so reset and read cannot
-- give two answers. The invariants (name/type/anchorX/anchorY) are
-- deliberately absent from it -- a position has no default.
local function Defaults()
    local f  = GetFlat()
    local mt = f and getmetatable(f)
    return mt and mt.__index
end

-- ── The write-through root ─────────────────────────────────────
--
-- The routed storage wearing the shape of a plain table, so scalar fields
-- can BIND rather than carry get/set pairs -- binding is what makes the
-- right-click Undo and Reset work on them for free. Reads fall through to
-- the flat (and on through its defaults template); writes land on the
-- flat as raw keys and mark the profile cache stale, which is the first
-- two steps of every Ace setter in the source file. The rest of each
-- setter's chain lives in that field's onChange.
--
-- No field on this page binds a table-valued key (showGroup needs
-- copy-on-write and keeps get/set), so __index returns values as they
-- are.
local ROOT = setmetatable({}, {
    __index = function(_, k)
        local f = GetFlat()
        return f and f[k]
    end,
    __newindex = function(_, k, v)
        if InCombatLockdown() then return end
        local bf = BF()
        local f  = GetFlat()
        if not (bf and f) then return end
        f[k] = v
        bf:InvalidateRaidProfileCache()
    end,
})

local function Root() return ROOT end

-- ── Side effects ───────────────────────────────────────────────
--
-- The panel's copies of the Ace setters' refresh chains, minus the write
-- and the cache invalidation that already happened in ROOT. Field
-- `refresh = "write"` keeps each running inline per commit, exactly when
-- the Ace setter ran -- the debouncing below is the SOURCE's own, on the
-- SAME BF timer fields, so an edit in either panel cancels the other's
-- pending heavy pass instead of stacking a second one.

-- framesSetResize's chain: light path inline so the user sees feedback
-- while dragging (cheap -- small frame count), heavy full-resize + aura
-- rebuild debounced 0.3s onto BF._framesResizeTimer.
local function ResizeEffect()
    local bf = BF()
    if not bf then return end
    if bf.ResizeTestFramesInPlace then bf:ResizeTestFramesInPlace() end
    if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
    if bf._framesResizeTimer then bf._framesResizeTimer:Cancel() end
    bf._framesResizeTimer = C_Timer.NewTimer(0.3, function()
        bf._framesResizeTimer = nil
        if InCombatLockdown() then return end
        if not bf:ActiveMatchesModifying() then
            if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
            if bf.RefreshDummyAuras then bf:RefreshDummyAuras() end
        else
            if bf.ResizeAllFrames then bf:ResizeAllFrames() end
            if bf.RefreshPetHeaders then bf:RefreshPetHeaders() end
            if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
            if bf.RefreshDummyAuras then bf:RefreshDummyAuras() end
        end
        if bf.RefreshPreviewLayout then bf:RefreshPreviewLayout() end
    end)
end

-- The raid-style twins' own chain. The write and the cache invalidation
-- already happened in ROOT; the only thing left to tell is the twin
-- layout, which re-reads the flat's frame size and these scales. The
-- raid/party frames themselves do not change, so none of the resize
-- chain above is run.
local function TwinScaleEffect()
    local bf = BF()
    if bf and bf.RefreshTwinLayout then bf:RefreshTwinLayout() end
end

-- framesSetSpacing's chain: nothing inline, the whole layout pass
-- debounced 0.15s onto BF._framesSpacingTimer -- the slider fires on
-- every tick, and the timer batches the heavy work into one call after
-- the user stops dragging.
local function SpacingEffect()
    local bf = BF()
    if not bf then return end
    if bf._framesSpacingTimer then bf._framesSpacingTimer:Cancel() end
    bf._framesSpacingTimer = C_Timer.NewTimer(0.15, function()
        bf._framesSpacingTimer = nil
        if InCombatLockdown() then return end
        bf:InvalidateRaidProfileCache()
        -- SetResolvedProfile atomically updates _resolvedProfile and the
        -- _lastResolvedFlatID cache key -- see Core_ProfileAPI.lua.
        bf:SetResolvedProfile(bf._contextIsRaid)
        bf:PlaceHeaders()
        bf:UpdateHeaders()
        if bf:ActiveMatchesModifying() then
            bf:ResizeAllFrames()
        end
        if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
    end)
end

-- The pet-size chain (Ace petFrameWidth/Height/Spacing and the two count
-- sliders): the full RefreshPetHeaders path rather than a lighter inline
-- one -- it re-sizes the children AND the pet anchor frame AND forces a
-- clean secure re-layout, which the lighter path missed.
local function PetHeadersEffect()
    local bf = BF()
    if not bf then return end
    if bf:ActiveMatchesModifying() then
        bf:RefreshPetHeaders()
    end
    if bf.UpdatePetTestFrames then bf:UpdatePetTestFrames() end
end

-- The Ace page's safeLayout: RefreshAll from a fresh stack, so a secure
-- rebuild is never started from a tainted options-widget path.
local function SafeLayout()
    C_Timer.After(0, function()
        local bf = BF()
        if bf and not InCombatLockdown() then
            bf:RefreshAll()
        end
    end)
end

-- ── The whole-flat copy ────────────────────────────────────────
--
-- Frames copies the ENTIRE flat, not a section table, so targets are
-- restricted to flats of the same type -- party spacing keys mean nothing
-- to a raid flat -- and the identity/position keys are skipped so those
-- do not leak between flats. pairs() over the source flat walks RAW keys
-- only (the sparse user edits), never the defaults template, exactly as
-- the Ace doCopy does.

local function CopyTargets()
    local fl  = FlatLayouts()
    local cur = CurrentFlat()
    local src = fl[cur]
    local t   = {}
    if not src then return t end
    for id, flat in pairs(fl) do
        if id ~= cur and type(flat) == "table" and flat.type == src.type then
            t[#t + 1] = { id = id, name = flat.name or id }
        end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

local function LayoutName(id)
    local fl = FlatLayouts()
    return (fl[id] and fl[id].name) or id or "current Layout"
end

local function CopyTo(targetID)
    if InCombatLockdown() then return end
    local bf = BF()
    local fl = FlatLayouts()
    local src, dst = fl[CurrentFlat()], fl[targetID]
    if not (bf and src and dst) then return end

    -- Position keys are intentionally excluded so positions don't leak
    -- between flats. Identity keys (name, type) are also preserved on the
    -- destination.
    local SKIP_KEYS = {
        name = true, type = true,
        anchorX = true, anchorY = true,
    }
    for k, v in pairs(src) do
        if not SKIP_KEYS[k] then
            dst[k] = (type(v) == "table") and bf:DeepCopy(v) or v
        end
    end
    bf:InvalidateRaidProfileCache()
    bf:RefreshAll()
end

-- ── The scope strip ────────────────────────────────────────────
--
-- No per-Layout toggle: Frames is always per-flat by design, so the strip
-- carries only which Layout is being edited and the copy. The Modifying
-- chain is the same one every section strip runs, but it ends in
-- Invalidate rather than RefreshPage: this page's SHAPE follows the
-- flat's type (see the header comment), so the page must be rebuilt, not
-- just re-read.

local function ScopeStrip()
    return { preset = "strip", fields = {
        -- The Ace page's _perLayoutInfo blurb, in the strip's LEFT slot --
        -- where every other section carries its "Enable per-Layout Config"
        -- switch, in the same sky blue. Frames has no such switch (it is
        -- always per-Layout), so what stands there is the sentence that
        -- says so, and the dropdowns sit at the right edge as they do
        -- everywhere else: `justify = "spread"` holds the first field and
        -- pushes the rest to the far edge.
        --
        -- "fit", because a note otherwise takes the whole row and would
        -- leave the dropdowns alone on a second line -- and the fixed
        -- width this used to carry wrapped the sentence the moment the
        -- face outgrew it. "fit" measures the words in the live face, so
        -- the note stays on one line wherever the row has room for it.
        { control = "note", width = "fit",
          color = { 0.53, 0.81, 0.92, 1.00 },
          text = "Per-Layout configuration is always enabled for "
              .. "this section." },

        -- A way OUT of the strip, next to the dropdown that raises the
        -- question: the Modifying list names Layouts, and the reader who
        -- wants a Layout that is not in it has nowhere to go from here.
        -- Left of the dropdown so it reads as the list's companion rather
        -- than as one more thing being edited.
        { control = "button", text = "Manage Layouts",
          desc = "Open the Layouts section, where Layouts are created, "
              .. "renamed and removed.",
          onClick = function(_, ctx)
              ctx.app:Navigate("raidPartyFrames", "roleSpecLayouts")
          end },

        { control = "dropdown", label = "Modifying",
          -- Labeled above, like any other dropdown, and sized rather
          -- than left to its 200px natural width: a layout name is short.
          labelPlacement = "above",
          desc = "Which Layout the settings on this page are edited "
              .. "for. The currently active Layout is shown in green.",
          disabled = "combat",
          options = FlatOptions,
          get = function() return CurrentFlat() end,
          set = function(_, ctx, v)
              local bf = BF()
              if not bf then return end
              bf._modifyingFlat = v
              bf:InvalidateRaidProfileCache()
              if bf.UpdateAuraSizeCache  then bf:UpdateAuraSizeCache()  end
              -- The same post-change chain the Ace dropdown runs: swap
              -- the setup-mode test header to the new layout, re-position
              -- the test anchor to that layout's own saved anchor, and
              -- refresh the preview.
              if bf.UpdateSetupFrames    then bf:UpdateSetupFrames()    end
              if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
              if bf.RefreshPreviewFrames then bf:RefreshPreviewFrames() end
              -- STRUCTURAL, not value-level: a party flat and a raid flat
              -- do not carry the same cards, so the memoised page is
              -- stale, not merely unread.
              ctx.app:Invalidate()
          end },

        { control = "dropdown", label = "Copy to",
          labelPlacement = "above",
          desc = "Copy the current Frames settings to another Layout "
              .. "of the same type.",
          disabled = "combat",
          -- Nothing to copy TO is the same as nothing to copy: the
          -- control goes rather than offering an empty list.
          hidden = function() return #CopyTargets() == 0 end,
          options = function()
              local out = {}
              local targets = CopyTargets()
              for _, e in ipairs(targets) do
                  out[#out + 1] = { value = e.id, text = e.name }
              end
              if #targets > 1 then
                  out[#out + 1] = { value = "__all", text = "All (same type)" }
              end
              return out
          end,
          -- A copy is an ACTION, not a setting: the dropdown never shows
          -- a current value, it just offers destinations.
          get = function() return nil end,
          set = function(_, ctx, v)
              if InCombatLockdown() then return end
              local from = LayoutName(CurrentFlat())
              local text
              if v == "__all" then
                  text = "Copy all Frames settings from \"" .. from
                      .. "\" to all other Layouts? This will overwrite "
                      .. "every setting in Frames section for all other "
                      .. "Layouts."
              else
                  local toName = LayoutName(v)
                  text = "Copy all Frames settings from \"" .. from
                      .. "\" to \"" .. toName .. "\"? This will overwrite "
                      .. "every setting in Frames section for the \""
                      .. toName .. "\" Layout."
              end
              ctx.app:Confirm(text, function()
                  if v == "__all" then
                      for _, e in ipairs(CopyTargets()) do CopyTo(e.id) end
                  else
                      CopyTo(v)
                  end
              end)
          end },
    }}
end

-- ── Screen-bounded position sliders ────────────────────────────
--
-- The Ace sliders carried softMin/softMax that ClampPositionSlider
-- re-derived from the live screen size on every get (resolutions change
-- mid-session, and login-time values lie). The panel slider has min/max
-- only, so the same bounds land there: seeded from BF:GetPositionHalfW/H
-- when the field is built, re-derived through the same methods on every
-- get. One honest difference: Ace's soft bounds only limited the DRAG
-- and let the text box type past them; the panel clamps the commit too.

-- One axis as a BIND ENTRY: the soft-bounds getter and the setter, with no
-- field of its own. The `pair` composite takes two of these -- the main
-- block's X/Y, and the pet block's.
local function PositionBind(key, axis, fallback, set)
    local bf   = BF()
    local half = 1024
    if bf then
        half = (axis == "x") and bf:GetPositionHalfW() or bf:GetPositionHalfH()
    end
    return {
        id = key, min = -half, max = half, step = 1,
        get = function(node)
            local b = BF()
            if b then
                local h = (axis == "x") and b:GetPositionHalfW() or b:GetPositionHalfH()
                node.min, node.max = -h, h
            end
            local f = GetFlat()
            return (f and f[key]) or fallback
        end,
        set = set }
end

-- The same bind entry with its tooltip attached -- a sub-control inside a
-- composite has no label of its own to carry one, so the desc rides on the
-- bind (see AxisOpt in the library's offsets composite).
local function PetBind(key, axis, fallback, set, desc)
    local b = PositionBind(key, axis, fallback, set)
    b.desc = desc
    return b
end

-- Shared setter for the main anchorX/anchorY sliders (Ace
-- framesSetPosition): write, invalidate, move the anchor.
local function AnchorSet(key)
    return function(_, _, val)
        if InCombatLockdown() then return end
        local bf = BF()
        local f  = GetFlat()
        if not (bf and f) then return end
        f[key] = val
        bf:InvalidateRaidProfileCache()
        if bf.UpdateAnchorPosition then bf:UpdateAnchorPosition() end
    end
end

-- The pet anchor setters move the live pet header immediately: clear the
-- saved detached position, re-point the header at the new coordinates,
-- and save it back. The X setter's extra leading save is the Ace source's
-- own asymmetry, kept as found.
local function PetAnchorSet(key, saveFirst)
    return function(_, _, val)
        if InCombatLockdown() then return end
        local bf = BF()
        local f  = GetFlat()
        if not (bf and f) then return end
        f[key] = val
        bf:InvalidateRaidProfileCache()
        if bf:ActiveMatchesModifying() then
            for _, header in ipairs(bf.groupsUsed or {}) do
                if header.isPetFrame then
                    if saveFirst then bf:SaveDetachedHeaderPosition(header) end
                    -- Write the new position directly into saved
                    -- positions then restore so the header moves
                    -- immediately.
                    local cfgp = bf.cfgDB.profile
                    if cfgp.customFrameGroupPositions then
                        cfgp.customFrameGroupPositions[header.headerPosKey] = nil
                    end
                    local flat = GetFlat()
                    header:ClearAllPoints()
                    header:SetPoint("CENTER", UIParent, "CENTER",
                        flat.petFrameAnchorX or 0,
                        flat.petFrameAnchorY or -300)
                    bf:SaveDetachedHeaderPosition(header)
                end
            end
        end
    end
end

-- Center the frame BLOCK on one axis, and only that axis.
--
-- anchorX/anchorY offset the LAYOUT ANCHOR from the screen center, and that
-- anchor is a corner -- so writing 0 centers the corner and leaves the
-- block hanging off it, which is the trap this exists to avoid. The block's
-- own center is the anchor plus half the grid's extent, signed by which
-- corner the anchor names, so the value that centers it is that half
-- extent negated. An axis the anchor already centers (Grow from Center
-- pins the cross axis by an edge, and a party's CENTER pins both) names
-- neither side, and its answer is plainly 0.
--
-- The extent is the CONFIGURED grid -- the full party row, the full raid
-- grid -- not the frames that happen to be visible: it already follows the
-- grow direction, frame size, spacing, group count and header scale, and
-- it is the box the anchor frame itself is sized to, which is what keeps
-- the block still as people join and leave.
--
-- The anchor is derived from the SAME flat the extent is, for the reason
-- IsParty() is: with _modifyingFlat unset or naming a deleted Layout,
-- GetFlat() falls back to flat_party while BF:GetModifyingLayoutAnchor()
-- falls back to the ACTIVE profile -- so asking the library for the anchor
-- could pair a party extent with a raid flat's corner (or with a
-- Grow-from-Center edge, which party never has) and throw the block a full
-- width off. The branches below are GetModifyingLayoutAnchor's own, over a
-- flat named rather than resolved.
local function LayoutAnchorFor(bf, f)
    local sp = bf:GetSectionProfile("sorting", f)
    if f.type == "party" then
        if sp and sp.growFromCenter then return "CENTER" end
        return f.partyLayoutAnchor or "TOPLEFT"
    end
    if sp and sp.raidGrowFromCenter then
        return bf:GrowFromCenterAnchor((sp and sp.raidGrowDirection) or "DOWN")
    end
    return f.raidLayoutAnchor or "TOPLEFT"
end

-- The pet block's twin of CenterAxis below. Same argument, different block:
-- the pet header is pinned by the corner DeriveGroupAnchor gives its own
-- grow direction (BFLayout, RefreshPetHeaders), and its extent is the pet
-- grid rather than the raid one.
local function PetCenterAxis(axis)
    return function(_, ctx)
        if InCombatLockdown() then return end
        local bf, f = BF(), GetFlat()
        if not (bf and f and bf.GetPetGridExtent) then return end
        local w, h = bf:GetPetGridExtent(f)
        if not w then return end
        local a = bf:DeriveGroupAnchor(f.petGrowDirection or "DOWN",
                                       bf:GetPetSecondaryGrowDirection(f))
                  or "TOPLEFT"

        local key, v = "petFrameAnchorX", 0
        if axis == "x" then
            local half = w / 2
            if     a:find("LEFT")  then v = -half
            elseif a:find("RIGHT") then v =  half end
        else
            key = "petFrameAnchorY"
            local half = h / 2
            if     a:find("TOP")    then v =  half
            elseif a:find("BOTTOM") then v = -half end
        end

        -- Through the pet setters, so the header moves with the number.
        PetAnchorSet(key, axis == "x")(nil, ctx, math.floor(v + 0.5))
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end
end

local function CenterAxis(axis)
    return function(_, ctx)
        if InCombatLockdown() then return end
        local bf, f = BF(), GetFlat()
        if not (bf and f and bf.GetConfiguredGridExtent) then return end
        local w, h = bf:GetConfiguredGridExtent(f, IsParty())
        local a = LayoutAnchorFor(bf, f) or "TOPLEFT"

        local key, v = "anchorX", 0
        if axis == "x" then
            local half = (w or 0) / 2
            if     a:find("LEFT")  then v = -half
            elseif a:find("RIGHT") then v =  half end
        else
            key = "anchorY"
            local half = (h or 0) / 2
            if     a:find("TOP")    then v =  half
            elseif a:find("BOTTOM") then v = -half end
        end

        -- Through the same setter the slider uses: one write, one cache
        -- invalidation, one anchor move. Rounded because the slider's step
        -- is a pixel and a half-pixel anchor is a blurry frame.
        AnchorSet(key)(nil, ctx, math.floor(v + 0.5))
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end
end

-- ── The cards ──────────────────────────────────────────────────

-- Ace: args.positionGroup.
local function PositionCard()
    -- One field, not two sliders: X and Y are one position, and the
    -- `offsets` composite says so -- the anchor pad's right-hand half,
    -- without the pad, because a flat is positioned by coordinates against
    -- a fixed anchor rather than by picking a point.
    local x = PositionBind("anchorX", "x", -200, AnchorSet("anchorX"))
    local y = PositionBind("anchorY", "y",  100, AnchorSet("anchorY"))
    x.desc = "Adjust the horizontal position of the frame anchor."
    y.desc = "Adjust the vertical position of the frame anchor."
    return { title = "Frame Position", preset = "form", fields = {
        { control = "offsets", id = "framePosition", disabled = "combat",
          captions = { x = "X Position", y = "Y Position" },
          -- Icons, not words: a box with a rule through the axis being
          -- centered says it in the width of the value box beside it, and
          -- the words move to the tooltip rather than being lost.
          buttons = {
              x = { icon = "center-h", text = "Center Horizontally",
                    desc = "Center the frames horizontally, keeping their "
                        .. "current vertical position.",
                    onClick = CenterAxis("x") },
              y = { icon = "center-v", text = "Center Vertically",
                    desc = "Center the frames vertically, keeping their "
                        .. "current horizontal position.",
                    onClick = CenterAxis("y") },
          },
          binds = { x = x, y = y } },
    }}
end

-- Ace: args.sizeGroup.
local function SizeCard()
    return { title = "Frame Size", preset = "form", fields = {
        -- Width and height as ONE field, stacked, the way X and Y are on
        -- the Position card: they are two halves of a frame's size and are
        -- always set together. Each keeps its own range.
        { control = "pair", id = "frameSize", disabled = "combat",
          captions = { x = "Frame Width", y = "Frame Height" },
          binds = {
              x = { bind = "frameWidth",  min = 20, max = 300, step = 1 },
              y = { bind = "frameHeight", min = 20, max = 200, step = 1 },
          },
          onChange = ResizeEffect, refresh = "write" },
        -- Spacing lives here rather than in a card of its own: it is a
        -- dimension of the block like the two above it -- how big a frame
        -- is, then how far apart they sit -- and a card holding one or two
        -- steppers was a heading for a setting.
        --
        -- Steppers, not sliders: whole pixels over a short range, where the
        -- reader wants "one more" rather than a position on a track, and
        -- the number is typed directly when they know it. The party/raid
        -- split stays at field level, so the watched predicates re-lay the
        -- card out when the Modifying Layout changes type.
        -- A party is a single row or column, so it has ONE spacing and no
        -- pair to make; a raid grid has two, which stack like the size
        -- above them. The two shapes swap on the same predicates every
        -- other party/raid field on this page uses.
        { control = "stepper", label = "Frame Spacing", bind = "frameSpacing",
          min = 0, max = 20, step = 1, disabled = "combat",
          desc = "Gap in pixels between frames.",
          hidden = function() return IsRaid() end,
          onChange = SpacingEffect, refresh = "write" },
        { control = "pair", id = "frameSpacingGrid", sub = "stepper",
          disabled = "combat",
          captions = { x = "Spacing (Horizontal)", y = "Spacing (Vertical)" },
          hidden = function() return IsParty() end,
          binds = {
              x = { bind = "frameSpacingH", min = 0, max = 20, step = 1,
                    desc = "Gap in pixels between columns of frames." },
              y = { bind = "frameSpacingV", min = 0, max = 20, step = 1,
                    desc = "Gap in pixels between rows of frames." },
          },
          onChange = SpacingEffect, refresh = "write" },
    }}
end

-- Ace: args.scaleGroup. The enableFrameScale toggle GATES the two fields
-- (the Ace page hid them while it was off), so it lives in the card's
-- header and the card collapses -- and its setter reverts the gated
-- settings to defaults on the way off, exactly as the Ace toggle does.
local function ScaleCard()
    local d = Defaults()
    return { title = "Scale Frames", preset = "form",
        toggle = {
            id      = "enableFrameScale",
            default = d and d.enableFrameScale,
            tooltip = "Scale Frames",
            desc    = "Enable custom frame scaling. When unchecked, scale "
                .. "is reset to 1.0 and Apply Scale to Indicators is reset "
                .. "to enabled.",
            get     = function()
                local f = GetFlat()
                return f and f.enableFrameScale
            end,
            set     = function(_, _, val)
                if InCombatLockdown() then return end
                local bf = BF()
                local prof = GetFlat()
                if not (bf and prof) then return end
                prof.enableFrameScale = val
                if not val then
                    -- Revert scale settings to defaults
                    prof.frameScale      = 1.0
                    prof.scaleIndicators = true
                end
                bf:InvalidateRaidProfileCache()
                if bf:ActiveMatchesModifying() then
                    if bf.ResizeAllFrames then bf:ResizeAllFrames() end
                    if bf.RefreshPetHeaders then bf:RefreshPetHeaders() end
                end
                if bf.UpdateSetupFrames then bf:UpdateSetupFrames() end
                if bf.RefreshDummyAuras then bf:RefreshDummyAuras() end
            end,
        },
        fields = {
            { control = "slider", label = "Frame Scale", bind = "frameScale",
              desc = "Scale multiplier for all unit frames (does not "
                  .. "affect frame width/height values)",
              min = 0.5, max = 3.0, step = 0.05, disabled = "combat",
              onChange = ResizeEffect, refresh = "write" },
            { control = "switch", label = "Apply Scale to Indicators",
              bind = "scaleIndicators",
              desc = "When enabled, frame scale also scales auras, icons, "
                  .. "text, and borders. When disabled, only the frame "
                  .. "body is scaled and indicators stay at their "
                  .. "configured sizes.",
              disabled = "combat",
              onChange = ResizeEffect, refresh = "write" },
        },
    }
end

-- Ace: args.raidGroupsGroup (raid flats only -- the CALLER leaves this
-- card out of a party flat's page, which is what the Ace group-level
-- hidden did).
--
-- showGroup is guaranteed present via the flat's __index template; the
-- setter's copy-on-write is what keeps the user's edits on the flat
-- itself (writing through the metatable would mutate the template, which
-- is regenerated on every WireFlatDefaults call and never saved).
-- Auto Hide Groups by Instance Size is read by the eight per-group
-- switches' `hidden` predicates, which the library asks afresh on every
-- render -- so the toggle's own write re-lays the card out and the eight
-- switches appear or vanish on the next frame with no explicit refresh.
local function AutoHideGroupsOn()
    local f = GetFlat()
    return (f and f.autoHideGroupsByInstance) and true or false
end

local function RaidGroupsCard()
    local d = Defaults()
    local dShow = d and d.showGroup
    local fields = {}
    fields[1] = {
        control = "switch", label = "Auto Hide Groups by Instance Size",
        id = "autoHideGroupsByInstance", wide = true,
        default = d and d.autoHideGroupsByInstance,
        desc = "Hides raid groups based on the max players that can fit "
            .. "in the current instance: Hides groups 5-8 in a 20-man "
            .. "raid. All 8 groups are shown in Open world and 40-man "
            .. "raids.",
        disabled = "combat",
        get = function()
            local f = GetFlat()
            return f and f.autoHideGroupsByInstance
        end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local bf = BF()
            local flat = GetFlat()
            if not (bf and flat) then return end
            flat.autoHideGroupsByInstance = val
            bf:InvalidateRaidProfileCache()
            if bf.db.global.setupModeActive and bf.UpdateSetupFrames then
                bf:UpdateSetupFrames()
            end
            SafeLayout()
        end,
    }
    for i = 1, 8 do
        fields[i + 1] = {
            control = "switch", label = "Group " .. i,
            id = "group" .. i,
            default = dShow and dShow[i],
            disabled = "combat",
            -- Group 1 starts a fresh line so the Auto Hide switch above
            -- keeps a row to itself. `wide` cannot do that job on a
            -- switch: the library resolves it to switch.wideWidth (a
            -- CONTROL's width, sized for the label) rather than the row,
            -- because a full row for a 28px toggle is a row of nothing --
            -- so the eight group toggles packed onto the end of its line.
            -- A break says the reason, which is that they are a separate
            -- set of settings.
            newRow = (i == 1) or nil,
            -- Managed by the toggle above: showing both would offer the
            -- reader two controls for one answer, only one of which the
            -- render path is listening to.
            hidden = AutoHideGroupsOn,
            get = function()
                -- showGroup is guaranteed on a RAID flat (the template
                -- supplies it) and absent on a party one. The `f and`
                -- guard alone was not enough: it covers f being nil and
                -- says nothing about f.showGroup, so a render that
                -- reached this card holding a party flat indexed nil and
                -- threw. That is reachable whenever the page's memoised
                -- shape outlives the flat it was built for -- the card's
                -- own `hidden` now closes that door, and this closes it
                -- again from the inside.
                local f  = GetFlat()
                local sg = f and f.showGroup
                return sg and sg[i]
            end,
            set = function(_, _, val)
                if InCombatLockdown() then return end
                local bf = BF()
                local flat = GetFlat()
                if not (bf and flat) then return end
                -- Copy-on-write: flat.showGroup reads fall through the
                -- __index metatable to the per-flat template. Copy the
                -- template's table into a rawkey on the flat so the
                -- user's edits live on the flat itself and AceDB
                -- persists them to SavedVariables.
                if rawget(flat, "showGroup") == nil then
                    local src = flat.showGroup  -- reads through __index
                    local copy = {}
                    if type(src) == "table" then
                        for k, v in pairs(src) do copy[k] = v end
                    end
                    rawset(flat, "showGroup", copy)
                end
                flat.showGroup[i] = val
                bf:InvalidateRaidProfileCache()
                -- When setup mode is active, always refresh the test
                -- frames so the new group visibility flows into the
                -- test-frame reconfigure (which reads showGroup) and the
                -- resize handle is re-anchored after hiding groups
                -- shifts which frame is last-visible.
                if bf.db.global.setupModeActive and bf.UpdateSetupFrames then
                    bf:UpdateSetupFrames()
                end
                -- Live frame rebuild path, from a fresh stack.
                SafeLayout()
            end,
        }
    end
    return {
        title = "Show Raid Groups", preset = "form", fields = fields,
        -- Asked afresh on every render, so the card takes itself out the
        -- moment the modifying flat is a party one -- it no longer
        -- depends on the page having been REBUILT with the right shape.
        -- The IsRaid() guard at the call site stays: this is the render's
        -- answer, that one is the build's, and there is no reason to
        -- construct eight fields that would only be hidden again.
        hidden = function() return not IsRaid() end,
    }
end

-- Ace: args.petsHeader / showPetFrames / petShowSolo / petPositionGroup.
-- One card: the Show Pet Frames toggle gated the solo switch AND the
-- whole position group on the Ace page (all hidden while it was off), so
-- here it is the card's header gate and everything it governed lives
-- under it. The Ace "Pet Frame Position" sub-heading is the one thing
-- this flattens away.
local function PetsCard()
    local d = Defaults()
    local f = GetFlat()
    local dir = (f and f.petGrowDirection) or "DOWN"
    local horizontal = (dir == "RIGHT" or dir == "LEFT")
    return { title = "Show Pet Frames", preset = "form",
        toggle = {
            id      = "showPetFrames",
            default = d and d.showPetFrames,
            tooltip = "Show Pet Frames",
            desc    = "Show a detached frame group for player pets. "
                .. "Unlock frames to drag it into position.",
            get     = function()
                local flat = GetFlat()
                return flat and flat.showPetFrames
            end,
            set     = function(_, _, val)
                if InCombatLockdown() then return end
                local bf = BF()
                local flat = GetFlat()
                if not (bf and flat) then return end
                flat.showPetFrames = val
                -- Seed pet grow direction from the main layout when
                -- first enabled.
                if val and not flat.petGrowDirection then
                    local sp2 = bf:GetSectionProfile("sorting", flat)
                    if flat.type == "party" then
                        local gd = (sp2 and sp2.growDirection) or "RIGHT"
                        if gd == "HORIZONTAL" then gd = "RIGHT" end
                        if gd == "VERTICAL" then gd = "DOWN" end
                        flat.petGrowDirection = gd
                        -- Party has no secondary grow direction UI (it
                        -- uses the canonical default for the axis).
                        -- Clear any stale value that could have leaked
                        -- in so the derived anchor is deterministic for
                        -- the seeded axis.
                        flat.petSecondaryGrowDirection = nil
                    else
                        flat.petGrowDirection =
                            (sp2 and sp2.raidGrowDirection) or "DOWN"
                        flat.petSecondaryGrowDirection =
                            sp2 and sp2.raidSecondaryGrowDirection
                    end
                end
                bf:InvalidateRaidProfileCache()
                if bf:ActiveMatchesModifying() then
                    bf:TogglePetFrames()
                end
                -- Refresh the setup-mode preview regardless of whether
                -- the modifying flat is the active one: the preview
                -- tracks the MODIFYING flat, so this must show/hide it
                -- immediately.
                if bf._IsSetupModeActive and bf._IsSetupModeActive() then
                    if val then
                        if bf.ShowPetTestFrames then bf:ShowPetTestFrames() end
                    else
                        if bf.HidePetTestFrames then bf:HidePetTestFrames() end
                    end
                end
            end,
        },
        fields = {
            { control = "switch", label = "Show when Solo",
              id = "petShowSolo",
              default = d and d.petShowSolo,
              desc = "Spawn the pet frame when you are not in a group. "
                  .. "Requires the layout to be rendering while solo "
                  .. "(e.g. this Party layout selected for the solo slot).",
              -- Raid flats never spawn pet frames while solo; the
              -- showPetFrames half of the Ace predicate is the card's
              -- gate now.
              hidden = function() return not IsParty() end,
              disabled = function()
                  if InCombatLockdown() then return true end
                  local flat = GetFlat()
                  return not (flat and flat.showPetFrames)
              end,
              get = function()
                  local flat = GetFlat()
                  return flat and flat.petShowSolo
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  local flat = GetFlat()
                  if not (bf and flat) then return end
                  flat.petShowSolo = val
                  bf:InvalidateRaidProfileCache()
                  if bf:ActiveMatchesModifying() then
                      bf:RefreshPetHeaders()
                  end
              end },

            -- Position and size as stacked PAIRS, the way the main block's
            -- are: two halves of one setting, set together. The X/Y binds
            -- keep PositionBind's soft bounds and the pet setters' own
            -- side effects (the header moves as the number changes).
            { control = "pair", id = "petFramePosition", disabled = "combat",
              newRow = true,
              captions = { x = "X Position", y = "Y Position" },
              buttons = {
                  x = { icon = "center-h", text = "Center Horizontally",
                        desc = "Center the pet frames horizontally, keeping "
                            .. "their current vertical position.",
                        onClick = PetCenterAxis("x") },
                  y = { icon = "center-v", text = "Center Vertically",
                        desc = "Center the pet frames vertically, keeping "
                            .. "their current horizontal position.",
                        onClick = PetCenterAxis("y") },
              },
              binds = {
                  x = PetBind("petFrameAnchorX", "x", 0,
                          PetAnchorSet("petFrameAnchorX", true),
                          "Horizontal position of the pet frames."),
                  y = PetBind("petFrameAnchorY", "y", -300,
                          PetAnchorSet("petFrameAnchorY", false),
                          "Vertical position of the pet frames."),
              } },

            { control = "pair", id = "petFrameSize", disabled = "combat",
              captions = { x = "Frame Width", y = "Frame Height" },
              binds = {
                  x = { bind = "petFrameWidth",  min = 20, max = 300, step = 1 },
                  y = { bind = "petFrameHeight", min = 10, max = 100, step = 1 },
              },
              onChange = PetHeadersEffect, refresh = "write" },

            -- Starts a line, so the two pairs above have one to themselves.
            { control = "stepper", label = "Frame Spacing",
              bind = "petFrameSpacing", newRow = true,
              desc = "Gap in pixels between pet frames.",
              min = 0, max = 20, step = 1, disabled = "combat",
              onChange = PetHeadersEffect, refresh = "write" },

            { control = "dropdown", label = "Grow Direction",
              id = "petGrowDirection",
              default = d and d.petGrowDirection,
              desc = "Direction pet frames grow from the anchor.",
              disabled = "combat",
              options = {
                  { value = "DOWN",  text = "Down"  },
                  { value = "UP",    text = "Up"    },
                  { value = "RIGHT", text = "Right" },
                  { value = "LEFT",  text = "Left"  },
              },
              get = function()
                  local flat = GetFlat()
                  local gd = flat and flat.petGrowDirection
                  if gd == "RIGHT" or gd == "UP" or gd == "LEFT" then return gd end
                  return "DOWN"
              end,
              set = function(_, ctx, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  local flat = GetFlat()
                  if not (bf and flat) then return end
                  -- Recompute the stored position from the CURRENT (old)
                  -- anchor frame BEFORE storing the new direction.
                  local newSecForAnchor = nil
                  local newLA = bf:DeriveGroupAnchor(val, newSecForAnchor)
                  if bf:ActiveMatchesModifying() and bf.RecomputePetHeaderAnchor then
                      bf:RecomputePetHeaderAnchor(
                          bf._modifyingFlat or "flat_party", newLA)
                  end
                  flat.petGrowDirection = val
                  flat.petSecondaryGrowDirection = nil
                  bf:InvalidateRaidProfileCache()
                  if bf:ActiveMatchesModifying() then
                      bf:RefreshPetHeaders()
                  end
                  if bf.UpdatePetTestFrames then bf:UpdatePetTestFrames() end
                  -- The two count sliders take their LABELS from this
                  -- value ("Max Rows" against "Max Columns"), and a label
                  -- is baked when the page is built -- so the page is
                  -- rebuilt, exactly as the Modifying dropdown does.
                  ctx.app:Invalidate()
              end },

            { control = "dropdown", label = "Secondary Grow Direction",
              id = "petSecondaryGrowDirection",
              desc = "Direction groups/columns extend perpendicular to "
                  .. "the primary grow direction.",
              hidden = function() return IsParty() end,
              disabled = "combat",
              options = function()
                  local flat = GetFlat()
                  local gd = (flat and flat.petGrowDirection) or "DOWN"
                  if gd == "RIGHT" or gd == "LEFT" then
                      return { { value = "DOWN",  text = "Down" },
                               { value = "UP",    text = "Up"   } }
                  else
                      return { { value = "RIGHT", text = "Right" },
                               { value = "LEFT",  text = "Left"  } }
                  end
              end,
              get = function()
                  local flat = GetFlat()
                  if not flat then return nil end
                  local gd = flat.petGrowDirection or "DOWN"
                  local horiz = (gd == "RIGHT" or gd == "LEFT")
                  local sec = flat.petSecondaryGrowDirection
                  -- Only return the stored value if valid for the
                  -- current primary axis; a stale cross-axis value would
                  -- blank the dropdown.
                  if sec then
                      if horiz then
                          if sec == "DOWN" or sec == "UP" then return sec end
                      else
                          if sec == "RIGHT" or sec == "LEFT" then return sec end
                      end
                  end
                  return horiz and "DOWN" or "RIGHT"
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  local flat = GetFlat()
                  if not (bf and flat) then return end
                  local gd = flat.petGrowDirection or "DOWN"
                  local isDefault =
                      (gd == "RIGHT" or gd == "LEFT") and val == "DOWN"
                      or (gd == "DOWN" or gd == "UP") and val == "RIGHT"
                  flat.petSecondaryGrowDirection = (not isDefault) and val or nil
                  bf:InvalidateRaidProfileCache()
                  -- Re-derive the anchor corner and recompute the stored
                  -- position so the block stays put when the secondary
                  -- grow direction flips.
                  if bf:ActiveMatchesModifying() and bf.RecomputePetHeaderAnchor then
                      local newLA = bf:DeriveGroupAnchor(
                          gd, flat.petSecondaryGrowDirection)
                      bf:RecomputePetHeaderAnchor(
                          bf._modifyingFlat or "flat_party", newLA)
                  end
                  if bf:ActiveMatchesModifying() then
                      bf:RefreshPetHeaders()
                  end
                  if bf.UpdatePetTestFrames then bf:UpdatePetTestFrames() end
              end },

            -- Party is capped to a single column of 5 pets, so the two
            -- count steppers only apply to raid layouts. Their labels are
            -- baked per build; the petGrowDirection setter rebuilds the
            -- page when they would change.
            -- Units per Column first: the Max below is derived from it
            -- (see BF:GetGridMaxColumns), so the reader sets the row
            -- width and then how many rows of it to show. Matches the
            -- custom frame group pair.
            { control = "stepper",
              label = horizontal and "Units per Row" or "Units per Column",
              id = "petUnitsPerColumn",
              default = d and d.petUnitsPerColumn,
              desc = "Number of pet frames per column (vertical grow) or "
                  .. "per row (horizontal grow).",
              min = 1, max = 10, step = 1,
              hidden = function() return IsParty() end,
              disabled = "combat",
              get = function()
                  local bf, flat = BF(), GetFlat()
                  if not (bf and flat) then return end
                  local _, upc = bf:GetPetGridDims(flat)
                  return upc
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  local flat = GetFlat()
                  if not (bf and flat) then return end
                  flat.petUnitsPerColumn = val
                  -- A wider column means fewer of them fit under the unit
                  -- ceiling; bring a now-too-large stored value down with it.
                  local cap = bf:GetGridMaxColumns(val)
                  if (flat.petMaxColumns or 0) > cap then
                      flat.petMaxColumns = cap
                  end
                  bf:InvalidateRaidProfileCache()
                  if bf:ActiveMatchesModifying() then
                      bf:RefreshPetHeaders()
                  end
                  if bf.UpdatePetTestFrames then bf:UpdatePetTestFrames() end
              end },
            { control = "stepper",
              label = horizontal and "Max Rows to Show" or "Max Columns to Show",
              id = "petMaxColumns",
              default = d and d.petMaxColumns,
              desc = "Maximum number of columns (vertical grow) or rows "
                  .. "(horizontal grow) of pet frames. Held to whatever it "
                  .. "takes to show 40 pets at the current Units per Column -- "
                  .. "every slot in the grid is a frame that gets built, and a "
                  .. "raid cannot field more than 40.",
              min = 1, max = 8, step = 1,
              hidden = function() return IsParty() end,
              disabled = "combat",
              get = function()
                  local bf, flat = BF(), GetFlat()
                  if not (bf and flat) then return end
                  local maxCols = bf:GetPetGridDims(flat)
                  return maxCols
              end,
              set = function(_, _, val)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  local flat = GetFlat()
                  if not (bf and flat) then return end
                  -- The stepper still travels its whole range; the VALUE is
                  -- what is held to the unit ceiling.
                  local _, upc = bf:GetPetGridDims(flat)
                  flat.petMaxColumns = math.min(val, bf:GetGridMaxColumns(upc))
                  bf:InvalidateRaidProfileCache()
                  if bf:ActiveMatchesModifying() then
                      bf:RefreshPetHeaders()
                  end
                  if bf.UpdatePetTestFrames then bf:UpdatePetTestFrames() end
              end },
        },
    }
end

-- ── The two cards the Custom Frame Groups page reuses ──────────
--
-- A custom frame group stores frameWidth / frameHeight / frameSpacingH /
-- frameSpacingV and enableFrameScale / frameScale / scaleIndicators on its
-- own flat, under exactly the names these two cards bind -- so the Custom
-- Frame Groups "Frames - Size & Position" page renders THESE rather than a
-- second copy of them. GetFlat above is what makes them land on the right
-- flat; nothing in either card had to change.
--
-- Published rather than exported wholesale: the Position, Raid Groups and
-- Pets cards are Raid/Party-only and have no counterpart there.
function BuzzardFramesOptions:FramesSizeCard()  return SizeCard()  end
function BuzzardFramesOptions:FramesScaleCard() return ScaleCard() end

-- Ace: args.twinScaleGroup. Per-flat, per-twin: how big the Player,
-- Target, Focus and Boss frames are drawn while they are showing as
-- Raid/Party frames (Unit Frames > <frame> > Size & Position > "Show as
-- Raid/Party frame"). 1 is pixel-identical to a raid frame of this flat.
--
-- Bound, not get/set: they are plain flat scalars like frameWidth, so the
-- write-through root carries them and right-click Undo and Reset come
-- free. Left on the slider's own debounce rather than the neighbors'
-- `refresh = "write"`: the resize and spacing effects debounce their heavy
-- pass internally and the twin relayout does not.
local function TwinScaleCard()
    local function Sl(key, label, unitName)
        return { control = "slider", label = label, bind = key,
                 min = 0.5, max = 2.0, step = 0.05, disabled = "combat",
                 desc = "Scale of the " .. unitName .. " while shown as a "
                     .. "Raid/Party frame.",
                 onChange = TwinScaleEffect }
    end
    -- Experimental: raid-style twins are gated behind Preview & Special
    -- Options > Experimental Options > Enable Experimental Options, along
    -- with the four "Show as Raid/Party frame" switches on the unit frame
    -- pages that these sliders size. Hidden at the CARD, so the title goes
    -- with the sliders instead of leaving an empty form behind.
    return { title = "Raid-style Frame Scale", preset = "form",
             hidden = BuzzardFramesOptions.ExperimentalOff, fields = {
        Sl("twinScalePlayer", "Raid-style Player scale", "Player frame"),
        Sl("twinScaleTarget", "Raid-style Target scale", "Target frame"),
        Sl("twinScaleFocus",  "Raid-style Focus scale",  "Focus frame"),
        Sl("twinScaleBoss",   "Raid-style Boss scale",   "Boss frames"),
    }}
end

-- ── The page ───────────────────────────────────────────────────

-- What the current structure was built against, for the observer below:
-- a party page and a raid page do not carry the same cards.
local builtForType = nil

function BuzzardFramesOptions:FramesPage(app)
    -- Self-heal for the one staleness the strip cannot see: the Modifying
    -- flat changed from ANOTHER page's strip (those call RefreshPage, and
    -- rightly -- their structure does not depend on the flat), and this
    -- page sat memoised with the old flat's shape. Checked on every entry
    -- to the route; a mismatch rebuilds before anything is drawn.
    if app and not self._bfFramesObserver then
        self._bfFramesObserver = true
        -- WithScope(nil, ...): observers fire from the navigation, BEFORE
        -- the render that would rebind the scope. GetFlat() answers
        -- bf:BFOScopeFlat() while a Custom Frame Groups scope is bound, and
        -- a custom frame group's flat is always type "raid" -- so arriving
        -- at Raid/Party > Size & Position from a Custom Frame Groups page
        -- would compare the wrong flat's type and rebuild (or fail to
        -- rebuild) the page on that answer.
        app:RegisterRouteObserver("raidPartyFrames/frames/sizePos", function(isActive)
            if not isActive or builtForType == nil then return end
            BuzzardFramesOptions:WithScope(nil, function()
                local f = GetFlat()
                local t = (f and f.type) or "party"
                if t ~= builtForType then app:Invalidate() end
            end)
        end)
    end

    builtForType = IsParty() and "party" or "raid"

    local groups = {
        ScopeStrip(),
        PositionCard(),
        SizeCard(),
        TwinScaleCard(),
        ScaleCard(),
    }
    -- Raid flats only: the Ace raidGroupsGroup hid itself for party
    -- flats, so the card is simply not built. The Modifying dropdown and
    -- the route observer both rebuild the page when the flat's type
    -- changes; the card's own `hidden` covers the render that slips
    -- between a flat change and its rebuild.
    if IsRaid() then
        groups[#groups + 1] = RaidGroupsCard()
    end
    groups[#groups + 1] = PetsCard()

    return {
        -- The flat, wearing the shape the library binds into. Scalar
        -- binds only; everything with copy-on-write or cross-key writes
        -- keeps get/set.
        db       = Root,
        -- The flat's own defaults template, in the same shape -- what
        -- makes right-click "Reset to default" work on the bound fields
        -- without each declaring one.
        defaults = Defaults,
        groups   = groups,
    }
end
