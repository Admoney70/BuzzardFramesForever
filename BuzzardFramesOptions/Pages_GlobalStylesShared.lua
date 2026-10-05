-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesShared.lua
-- The Global Styles write fan-out, and the "Apply Changes To" card every
-- Global Styles page opens with. Defines no page of its own.
--
-- Global Styles owns NO storage and adds nothing to any read path: every
-- field on its pages is a WRITE-THROUGH into the keys the Raid/Party
-- frames, the custom frame groups and the unit frames already read. The
-- helpers below are that fan-out -- one write lands on the rpDB global
-- section, on EVERY layout flat, on EVERY custom frame group flat and on
-- the unit frame profile -- plus the read side (the pages display the
-- first surface in scope) and the per-surface refresh chains.
--
-- Built LAZILY, the first time a page asks for it: nothing at file scope
-- reads BuzzardFrames, and the accessor table closes over the addon only
-- once the panel is open. Every entry keeps the name and signature the
-- Ace widgets called, so a page reads like the section it replaces:
--
--     local GS = BuzzardFramesOptions:GS()
--     GS.Apply(false, false, function() GS.WriteRP("healthColor", col) end, ...)
--
-- Storage invariants (both corrupt the profile if broken):
--   * NEVER reassign rpDB.profile.healthPower (or any section table):
--     every flat's section table has __index pointing at that exact table
--     object (WireSectionFallback); replacing it orphans every fallback.
--   * ALWAYS rawget before deciding whether to create flat.<section>.
--     Flats carry a WireFlatDefaults metatable, so a plain read can return
--     an INHERITED table and the create step is skipped -- the write then
--     lands on shared storage. See EnsureHealthPower.
--
-- SCOPE ("Apply Changes To") is a UI preference, so it lives in db.global
-- (survives profile switches), not in any of the three profile DBs.
-- DEPTH: "Global" means global -- a write lands on every layout whether or
-- not the section's per-layout toggle is on, and on every custom frame
-- group whether or not that group overrides the section.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local SECTION = "healthPower"

-- The RP three-way health color mode has no NPC analogue on the unit
-- frames: NPCs have no class. "Use Class Colors" therefore maps to the
-- nearest per-unit-identity coloring UF offers, "Color by Classification".
local UF_NPC_MODE = {
    class    = "classification",
    gradient = "gradient",
    static   = "static",
}

-- ── The fan-out ────────────────────────────────────────────────
--
-- A builder rather than file-scope locals: `BF` is resolved when the
-- panel first asks, not while this file loads.
local function BuildGS()
    local BF = _G.BuzzardFrames
    if not BF then return nil end

    -- ── Scope ("Apply changes to") ──────────────────────
    -- Seeded once, all-on: a section called "Global Styles" that silently
    -- did nothing on first open would be a worse default than one that
    -- does what its name says.
    local scopeFallback = { rp = true, cfg = true, uf = true }
    local function scope()
        local g = BF.db and BF.db.global
        if not g then return scopeFallback end
        if type(g.globalStyles) ~= "table" then
            g.globalStyles = { rp = true, cfg = true, uf = true }
        end
        return g.globalStyles
    end
    local function wantRP()  local s = scope(); return s.rp  ~= false end
    local function wantCFG() local s = scope(); return s.cfg ~= false end
    local function wantUF()  local s = scope(); return s.uf  ~= false end

    -- Which surface the read-side widgets display: the first in scope (a
    -- change would definitely land on it). Defined up here — BEFORE the
    -- borders read helpers (bordersSource) that call it. It previously lived
    -- lower in the file, so bordersSource resolved `readSurface` to a nil
    -- global and threw "attempt to call a nil value" when the Borders health
    -- group was opened.
    local function readSurface()
        if wantRP()  then return "rp"  end
        if wantCFG() then return "cfg" end
        if wantUF()  then return "uf"  end
        return "rp"
    end

    -- ── Storage accessors ───────────────────────────────
    local function rpGlobal()
        local p = BF.rpDB and BF.rpDB.profile
        local t = p and p[SECTION]
        return type(t) == "table" and t or nil
    end

    local function ufProfile()
        local p = BF.ufDB and BF.ufDB.profile
        return type(p) == "table" and p or nil
    end

    -- Get-or-create flat[SECTION], rawget-guarded (see header invariants).
    -- Mirrors the create-before-write that Options_CustomFrameSections.lua
    -- does in the override toggle setter.
    local function EnsureHealthPower(flat)
        if type(flat) ~= "table" then return nil end
        local t = rawget(flat, SECTION)
        if type(t) ~= "table" then
            flat[SECTION] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, SECTION) end
            t = rawget(flat, SECTION)
        end
        return type(t) == "table" and t or nil
    end

    -- Tables must not be shared by reference across destinations, or a
    -- later in-place edit to one layout's color would silently mutate all
    -- of them. Scalars are copied by value already.
    local function put(t, key, val)
        if type(val) == "table" and BF.DeepCopy then
            t[key] = BF:DeepCopy(val)
        else
            t[key] = val
        end
    end

    -- ── Write fan-out: Raid/Party ───────────────────────
    -- Global section first (identity preserved -- keys are assigned into
    -- the existing table, never a fresh one), then every layout flat.
    local function WriteRP(key, val)
        local gp = rpGlobal()
        if not gp then return end
        put(gp, key, val)

        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        -- flatLayouts is a STRING-KEYED map ("flat_party", ...), not an
        -- array: pairs, never ipairs.
        for _, flat in pairs(fl) do
            local t = EnsureHealthPower(flat)
            if t then put(t, key, val) end
        end
    end

    -- ── Write fan-out: Custom Frame Groups ──────────────
    -- customFrameGroups IS an array. The group's overrideHealthPower flag
    -- is deliberately left alone: with the global section written too, the
    -- group resolves to the same value whichever side of the flag it reads.
    local function WriteCFG(key, val)
        -- Bail if the RP global section is missing. WireSectionFallback
        -- early-returns without setting a metatable when the global isn't a
        -- table, so writing here would leave every group holding an UNWIRED
        -- healthPower -- and from then on every key we did not write would
        -- read nil for that group instead of inheriting the global.
        if not rpGlobal() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureHealthPower(grp.flat)
                if t then put(t, key, val) end
            end
        end
    end

    -- ════════════════════════════════════════════════════
    -- BORDERS (frame border) write-through — same fan-out model as the
    -- healthPower helpers above, but into the `borders` section (RP + CFG)
    -- and the ufDB frame-border keys (UF). The frame border is what
    -- Options_Borders.lua's "Border" tab edits; here one change lands on
    -- every Layout, every custom frame group, and every unit frame at once.
    -- ════════════════════════════════════════════════════
    local BORDERS = "borders"

    local function rpBorders()
        local p = BF.rpDB and BF.rpDB.profile
        local t = p and p[BORDERS]
        return type(t) == "table" and t or nil
    end

    -- Get-or-create flat.borders, rawget-guarded exactly like
    -- EnsureHealthPower (flats carry a WireFlatDefaults metatable, so a plain
    -- read can return an INHERITED table and the create step is skipped).
    local function EnsureBorders(flat)
        if type(flat) ~= "table" then return nil end
        local t = rawget(flat, BORDERS)
        if type(t) ~= "table" then
            flat[BORDERS] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, BORDERS) end
            t = rawget(flat, BORDERS)
        end
        return type(t) == "table" and t or nil
    end

    -- RP: global section (identity preserved) + every layout flat.
    local function WriteRPBorders(key, val)
        local gp = rpBorders()
        if not gp then return end
        put(gp, key, val)
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureBorders(flat)
            if t then put(t, key, val) end
        end
    end

    -- CFG: every group's flat.borders. overrideBorders is left alone (same
    -- rationale as overrideHealthPower — with the global section written too,
    -- the group resolves to the same value either side of the flag).
    local function WriteCFGBorders(key, val)
        if not rpBorders() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureBorders(grp.flat)
                if t then put(t, key, val) end
            end
        end
    end

    -- UF frame border. Per owner decision the SAME value applies to every part
    -- of the unit frame border: the three square-mode per-bar boxes (name /
    -- health / power) and the rounded ring. So enable/thickness fan out to the
    -- three <bar>Border* keys and color to the three <bar>BorderColor keys plus
    -- the rounded frameBorderColor; style writes oufBorderMode.
    local UF_BORDER_BARS = { "name", "health", "power" }
    local function WriteUFBorderEnable(v)
        local pf = ufProfile(); if not pf then return end
        for _, bar in ipairs(UF_BORDER_BARS) do
            pf[bar .. "BorderEnabled"] = v and true or false
        end
    end
    local function WriteUFBorderStyle(v)
        local pf = ufProfile(); if not pf then return end
        pf.oufBorderMode = v
    end
    local function WriteUFBorderColor(col)
        local pf = ufProfile(); if not pf then return end
        for _, bar in ipairs(UF_BORDER_BARS) do
            pf[bar .. "BorderColor"] = { r = col.r, g = col.g, b = col.b, a = col.a }
        end
        -- Rounded ring shares one color key.
        pf.frameBorderColor = { r = col.r, g = col.g, b = col.b, a = col.a }
    end
    local function WriteUFBorderThickness(v)
        local pf = ufProfile(); if not pf then return end
        for _, bar in ipairs(UF_BORDER_BARS) do
            pf[bar .. "BorderThickness"] = v
        end
    end

    -- ── Refresh: Raid/Party borders ─────────────────────
    -- The Borders page (Options_Borders.lua) re-lays out every active frame on
    -- the "bordersLayout" debounce bucket; reuse the exact same bucket so a
    -- change here coalesces with one made there.
    local function RefreshRPBorders()
        BF:DebounceOption("bordersLayout", function()
            BF:LayoutAllIndicators()
            -- The border-style highlights (target / aggro border /
            -- dispel border) switch ring<->edges in their Update based
            -- on `enableBorder AND rounded` (isRoundedActive), so
            -- enable/style changes from this page must refresh them
            -- too — same walk the Borders page setters run (owner
            -- report: the target highlight stayed rounded after
            -- disabling a rounded border here).
            for f in pairs(BF.activeFrames or {}) do
                BF:UpdateTarget(f)
                BF:UpdateThreat(f)
                if BF.UpdateDebuffHighlight then BF:UpdateDebuffHighlight(f) end
            end
        end)
        if BF.RefreshPreviewLayout then BF:RefreshPreviewLayout() end
    end

    -- ── Read side: borders ──────────────────────────────
    -- Show the first surface in scope (same rule as the health widgets). RP/CFG
    -- read the `borders` section; UF falls back to its own keys. After any
    -- change here all in-scope surfaces agree anyway.
    local function cfgBordersSource()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[BORDERS]) == "table" then
                    return flat[BORDERS]
                end
            end
        end
        return rpBorders()
    end
    local function bordersSource()
        local s = readSurface()
        if s == "cfg" then return cfgBordersSource() end
        if s == "uf"  then return nil end
        return rpBorders()
    end

    local function readBorderEnable()
        local bp = bordersSource()
        if bp then return bp.enableBorder ~= false end
        local pf = ufProfile()
        return (pf and pf.healthBorderEnabled) and true or false
    end
    local function readBorderStyle()
        local bp = bordersSource()
        if bp then return bp.borderStyle or "square" end
        local pf = ufProfile()
        return (pf and pf.oufBorderMode) or "square"
    end
    local function readBorderColor()
        local bp = bordersSource()
        if bp then return bp.borderColor end
        local pf = ufProfile()
        return pf and (pf.healthBorderColor or pf.frameBorderColor)
    end
    local function readBorderThickness()
        local bp = bordersSource()
        if bp then return bp.borderThickness or 1 end
        local pf = ufProfile()
        return (pf and pf.healthBorderThickness) or 1
    end

    -- ── Refresh: Raid/Party ─────────────────────────────
    -- Same two debounce keys the Health & Power Bars page uses, so a change
    -- made here coalesces with one made there instead of running twice.
    local function RefreshRP(needLayout)
        if BF.InvalidateRaidProfileCache then BF:InvalidateRaidProfileCache() end
        if BF.RebindHealthBarColor then BF:RebindHealthBarColor() end
        if needLayout then
            BF:DebounceOption("hpHealthLayout", function() BF:RefreshHealthBarLayout() end)
        else
            BF:DebounceOption("hpColors", function() BF:RefreshColors() end)
        end
        if BF.RefreshPreviewHealthBar then BF:RefreshPreviewHealthBar() end
    end

    -- ── Refresh: Custom Frame Groups ────────────────────
    -- Replicates RefreshCFGAfterSettingChange (a local closure inside
    -- Options_CustomFrameSections.lua, unreachable from here). The aura
    -- cache wipes look unrelated to health bars but are kept: aura sizing
    -- reads frame geometry that the healthPower section feeds.
    local function RefreshCFG()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" then
                    if flat._sectionCache then
                        for k in pairs(flat._sectionCache) do flat._sectionCache[k] = nil end
                    end
                    if flat._auraCache then
                        for k in pairs(flat._auraCache) do flat._auraCache[k] = nil end
                    end
                    if BF.InvalidateFlatAuraCache then BF:InvalidateFlatAuraCache(flat) end
                end
            end
        end
        if InCombatLockdown() then return end
        if BF.RefreshCustomFrameHeaders then BF:RefreshCustomFrameHeaders() end
        if BF.UpdateCustomFrameTestFrames then BF:UpdateCustomFrameTestFrames() end
        if BF.RefreshCFGAurasOnly then BF:RefreshCFGAurasOnly() end
        if BF.RefreshPreviewFrames then BF:RefreshPreviewFrames() end
    end

    -- ── Refresh: Unit Frames ────────────────────────────
    -- Replicates relayoutAll() + updateAll() from Options_oUF_Other.lua
    -- (also locals). BF:OnUFProfileChanged() is a superset but re-resolves
    -- the active UF layout and can fire the reload-UI popup, which is not
    -- wanted for a plain appearance change.
    local function RefreshUF(needLayout)
        if needLayout then
            BF:DebounceOption("gsUFLayout", function()
                if BF.oufPlayer         and BF.ApplyOUFPlayerLayout         then BF:ApplyOUFPlayerLayout()         end
                if BF.oufTarget         and BF.ApplyOUFTargetLayout         then BF:ApplyOUFTargetLayout()         end
                if BF.oufFocus          and BF.ApplyOUFFocusLayout          then BF:ApplyOUFFocusLayout()          end
                if BF.oufPet            and BF.ApplyOUFPetLayout            then BF:ApplyOUFPetLayout()            end
                if BF.oufTargetOfTarget and BF.ApplyOUFTargetOfTargetLayout then BF:ApplyOUFTargetOfTargetLayout() end
                if BF.oufFocusTarget    and BF.ApplyOUFFocusTargetLayout    then BF:ApplyOUFFocusTargetLayout()    end
                if BF.oufBoss           and BF.ApplyOUFBossFrameLayout      then BF:ApplyOUFBossFrameLayout()      end
                if BF.RefreshOUFFonts then BF:RefreshOUFFonts() end
            end)
        end
        BF:DebounceOption("gsUFUpdate", function()
            local frames = {
                BF.oufPlayer, BF.oufTarget, BF.oufFocus,
                BF.oufPet, BF.oufTargetOfTarget, BF.oufFocusTarget,
            }
            for i = 1, #frames do
                local f = frames[i]
                if f then f:UpdateAllElements("Manual") end
            end
            if BF.oufBoss then
                for i = 1, 5 do
                    local f = BF.oufBoss[i]
                    if f then f:UpdateAllElements("Manual") end
                end
            end
        end)
    end

    -- Borders counterpart of Apply(). Scope-gated like the health Apply, but
    -- the RP refresh is the border relayout and the UF refresh is the full
    -- frame relayout (RefreshUF(true), same seven ApplyOUF*Layout appliers the
    -- health page uses — they run _ApplyOUFFrameBorder). CFG reuses RefreshCFG.
    -- Defined here, AFTER RefreshCFG/RefreshUF — it previously sat above them
    -- and resolved both to nil globals, so only the Raid/Party refresh ran
    -- (RefreshRPBorders is defined earlier) and CFG/UF never updated, with a
    -- "call a nil value" error on the CFG branch.
    -- ══ WHY EVERY Apply* BELOW INVALIDATES ════════════════════════════════
    --
    -- The write fan-outs on this page (WriteRPBorders, WriteRPIcons, WriteRPText,
    -- WriteRPAbsorbs) assign into the EXISTING section tables -- identity is
    -- preserved on purpose, stated in the fan-out header at :125-127 ("keys are
    -- assigned into the existing table, never a fresh one"), which is what keeps
    -- this page and the dedicated section pages in step. A bare re-Layout was
    -- therefore all this ever needed.
    --
    -- That stopped being true when the indicators moved to per-scope resolved
    -- blocks (BuzzardFrames_IndicatorUpdateDB_Plan.md, section 12). A block is
    -- keyed on (section table, BF._sectionCfgGen). Identity deliberately does not
    -- move, so the generation counter is the ONLY thing that can retire a block --
    -- and nothing on this page moved it. Every setter here wrote the profile and
    -- changed nothing on screen until an unrelated zone or roster change bumped
    -- the counter.
    --
    -- WHY HERE AND NOT IN THE REFRESH FUNCTION. Two reasons, and the second is the
    -- one that decides it:
    --
    --   1. Coverage. A setter picks its own rpRefreshFn, so invalidating inside
    --      one refresh covers only the setters that happen to pass that one. That
    --      is how the first attempt missed Role Icon Style (which passes
    --      RefreshRPRoleIcons, not RefreshRPIconsLayout), every Health Text
    --      control on the Text page (which passes HealthUpdate), and the whole
    --      absorbs fan-out. Apply* is the single chokepoint every setter on these
    --      pages goes through, so placing it here cannot be missed by a new one.
    --
    --   2. Ordering. RefreshCFG() (:370) and previewFn run SYNCHRONOUSLY in the
    --      same call, and RefreshCFG reaches RefreshCustomFrameHeaders,
    --      UpdateCustomFrameTestFrames and RefreshPreviewFrames -- all of which
    --      re-Layout. Invalidating inside the debounced RP callback instead would
    --      leave the CFG frames and the options preview repainting from a stale
    --      block on every drag notch, converging only 0.15s after the drag stops.
    --
    -- COST. One generation increment plus one table-slot nil per RP flat and per
    -- CFG flat (Core_ProfileAPI.lua:988-1011) -- the same order of walk the write
    -- immediately above already does, at the same frequency. Nothing is added to
    -- the debounced path: the expensive part, the 40-frame LayoutAllIndicators
    -- walk, stays behind its existing DebounceOption / MouseUpOption gate exactly
    -- as before. This is what BF:WriteSectionKey already does at write time
    -- (Core_ProfileAPI.lua:1029, :1035), which is why the dedicated section pages
    -- never had this bug.
    --
    -- healthPower needs no call of its own: RefreshRP (:354) and RefreshRPPower
    -- (:643) already invalidate, synchronously, at the right point. auras needs
    -- none either -- no converted indicator reads that section.
    -- ══════════════════════════════════════════════════════════════════════

    local function ApplyBorders(writeRP, writeCFG, writeUF)
        -- Reaches Container's content inset plus block.borderN on PowerBar
        -- (Indicators/PowerBar.lua:163), NameText (:348) and CastBar (:350).
        -- Container was deliberately left unconverted (plan section 4.1), so
        -- without this the frame TORE rather than going inert: the inset moved
        -- while the power bar stayed anchored to the old one.
        if BF._InvalidateSectionViews then BF:_InvalidateSectionViews("borders") end
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end
        if wantUF()  and writeUF  then writeUF()  end
        if wantRP()  then RefreshRPBorders() end
        if wantCFG() then RefreshCFG() end
        if wantUF()  then RefreshUF(true) end
    end

    -- Applies whichever surfaces are in scope.
    --
    -- The two layout flags are deliberately SEPARATE, because the same
    -- setting needs different work on the two surfaces. Opacity is the
    -- case in point: the raid frames only re-evaluate color for it
    -- (Options_HealthPower.lua uses the hpColors bucket), while the unit
    -- frames genuinely relayout (Options_oUF_Player_Target.lua calls
    -- relayoutAll). Collapsing these into one flag would either do a
    -- pointless healthBar:Layout sweep on every raid frame or skip a
    -- needed relayout on the unit frames.
    local function Apply(rpNeedLayout, ufNeedLayout, writeRP, writeCFG, writeUF)
        if wantRP() then
            if writeRP then writeRP() end
        end
        if wantCFG() then
            if writeCFG then writeCFG() end
        end
        if wantUF() then
            if writeUF then writeUF() end
        end

        -- ORDER IS LOAD-BEARING: RebuildHealthGradientCurves reads the very
        -- keys written above (hp.useHealthGradient and the UF color modes)
        -- to decide whether to populate the curve. Calling it first would
        -- rebuild against the OLD state, leaving an empty curve that the
        -- frames then sample. Both existing pages write-then-rebuild for
        -- the same reason. It runs regardless of scope because the curve is
        -- process-wide, shared by the raid frames and the unit frames.
        if BF.RebuildHealthGradientCurves then BF:RebuildHealthGradientCurves() end

        if wantRP()  then RefreshRP(rpNeedLayout) end
        if wantCFG() then RefreshCFG() end
        if wantUF()  then RefreshUF(ufNeedLayout) end
    end

    -- ── Read side ───────────────────────────────────────
    -- Global Styles persists nothing of its own, so the widgets have to
    -- display one of the surfaces. They show the first surface that is in
    -- scope -- the one a change would definitely land on. With all three
    -- checked (the default) that is Raid/Party, and after any change here
    -- all three agree anyway. (readSurface is defined earlier, before its
    -- first use in bordersSource.)

    -- Representative CFG source. Read THROUGH the metatable (not rawget)
    -- so an un-customized group correctly reports the inherited global.
    local function cfgSource()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[SECTION]) == "table" then
                    return flat[SECTION]
                end
            end
        end
        return rpGlobal()
    end

    -- Returns the healthPower-shaped table for rp/cfg, or nil for uf.
    local function hpSource()
        local s = readSurface()
        if s == "cfg" then return cfgSource() end
        if s == "uf"  then return nil end
        return rpGlobal()
    end

    local function readMode()
        local hp = hpSource()
        if hp then
            if not hp.useCustomHealthColor then return "class" end
            return hp.useHealthGradient and "gradient" or "static"
        end
        local pf = ufProfile()
        return (pf and pf.globalPlayerHealthColorMode) or "class"
    end

    local function readHealthColor()
        local hp = hpSource()
        if hp then return hp.healthColor end
        local pf = ufProfile()
        return pf and pf.globalHealthColor
    end

    local function readOpacity()
        local hp = hpSource()
        if hp then return hp.healthBarOpacity or 1 end
        local pf = ufProfile()
        return (pf and pf.oufHealthBarOpacity) or 1
    end

    local function readUseTexture()
        local hp = hpSource()
        if hp then return hp.useCustomHealthBarTexture and true or false end
        local pf = ufProfile()
        return (pf and pf.oufUseCustomHealthBarTexture) and true or false
    end

    local function readTexture()
        local hp = hpSource()
        if hp then return hp.healthBarTexture or "Blizzard Raid Bar" end
        local pf = ufProfile()
        return (pf and pf.oufHealthBarTexture) or "Blizzard Raid Bar"
    end

    -- ── Read side: background ───────────────────────────
    -- Same divergence as the fill: RP/CFG store the mode as two booleans
    -- (useBgClass / useBgGradient, neither set = static) while UF stores a
    -- string enum. Note the defaults differ too -- RP declares
    -- backgroundAlpha 1.0, UF falls back to 0.6 -- so each surface is read
    -- with its OWN fallback rather than a single shared one.
    local function readBgUseCustom()
        local hp = hpSource()
        if hp then return hp.useCustomBackgroundColor and true or false end
        local pf = ufProfile()
        return (pf and pf.oufUseCustomBackgroundColor) and true or false
    end

    local function readBgMode()
        local hp = hpSource()
        if hp then
            if hp.useBgGradient then return "gradient" end
            if hp.useBgClass    then return "class" end
            return "static"
        end
        local pf = ufProfile()
        return (pf and pf.oufBackgroundColorMode) or "static"
    end

    local function readBgColor()
        local hp = hpSource()
        if hp then return hp.backgroundColor end
        local pf = ufProfile()
        return pf and pf.oufBackgroundColor
    end

    local function readBgAlpha()
        local hp = hpSource()
        if hp then return hp.backgroundAlpha or 1 end
        local pf = ufProfile()
        return (pf and pf.oufBackgroundAlpha) or 0.6
    end

    local function readBgDarken()
        local hp = hpSource()
        if hp then return hp.bgClassDarken or 0 end
        local pf = ufProfile()
        return (pf and pf.oufBgClassDarken) or 0
    end

    -- ── Read side: power bar ────────────────────────────
    -- The power background alphas do NOT agree across surfaces: raid frames
    -- default powerBarBgOpacity to 1.0, the unit frames default
    -- oufPowerBarBgAlpha to 0.6 (the value their style hardcoded before the
    -- key existed). Each is read with its own fallback so the widget shows
    -- the truth for whichever surface it is displaying; a write then brings
    -- them into agreement.
    local function readUsePowerTexture()
        local hp = hpSource()
        if hp then return hp.useCustomPowerBarTexture and true or false end
        local pf = ufProfile()
        return (pf and pf.oufUseCustomPowerBarTexture) and true or false
    end

    local function readPowerTexture()
        local hp = hpSource()
        if hp then return hp.powerBarTexture or "Blizzard Raid Bar" end
        local pf = ufProfile()
        return (pf and pf.oufPowerBarTexture) or "Blizzard Raid Bar"
    end

    local function readUsePowerBg()
        local hp = hpSource()
        if hp then return hp.useCustomPowerBarBgColor and true or false end
        local pf = ufProfile()
        return (pf and pf.oufUseCustomPowerBarBgColor) and true or false
    end

    local function readPowerBgColor()
        local hp = hpSource()
        if hp then return hp.powerBarBgColor end
        local pf = ufProfile()
        return pf and pf.oufPowerBarBgColor
    end

    local function readPowerBgOpacity()
        local hp = hpSource()
        if hp then return hp.powerBarBgOpacity or 1 end
        local pf = ufProfile()
        return (pf and pf.oufPowerBarBgAlpha) or 0.6
    end

    -- Power settings need the raid frames' power-specific refresh, which is
    -- a different debounce bucket and a different function from the health
    -- bar's. RefreshRP/RefreshUF above only know about health, so power
    -- writes use this instead.
    local function RefreshRPPower(needLayout)
        if BF.InvalidateRaidProfileCache then BF:InvalidateRaidProfileCache() end
        if needLayout then
            BF:DebounceOption("hpPowerLayout", function() BF:RefreshPowerBarLayout() end)
        else
            for frame in pairs(BF.activeFrames or {}) do BF:UpdatePower(frame) end
        end
        if BF.RefreshPreviewPowerBar then BF:RefreshPreviewPowerBar() end
    end

    -- Power bar background is a plain SetColorTexture on regions that already
    -- exist, so it is pushed by walking the frames rather than relayouting --
    -- the unit frame layout chain bails out in combat and does protected
    -- geometry work these settings do not need.
    local function RefreshUFPowerBg()
        local function apply(f)
            if f and BF._ApplyOUFPowerBgColor then BF:_ApplyOUFPowerBgColor(f) end
        end
        apply(BF.oufPlayer)
        apply(BF.oufTarget)
        apply(BF.oufFocus)
        apply(BF.oufPet)
        apply(BF.oufTargetOfTarget)
        apply(BF.oufFocusTarget)
        if BF.oufBoss then
            for i = 1, 5 do apply(BF.oufBoss[i]) end
        end
        local pb = BF.oufDetachedPowerBar
        if pb and pb._bg and BF._GetOUFPowerBgColor then
            pb._bg:SetColorTexture(BF:_GetOUFPowerBgColor())
        end
    end

    -- Power texture DOES need the unit frame relayout, plus one extra reach:
    -- the resource bar pips share oufPowerBarTexture but sit outside the
    -- frame chain, so relayoutAll only finds them via the player frame.
    local function RefreshUFPowerTexture()
        RefreshUF(true)
        BF:DebounceOption("gsUFResourceBar", function()
            if BF.ApplyOUFResourceBarLayout then BF:ApplyOUFResourceBarLayout() end
        end)
    end

    -- Power counterpart of Apply(). Same scope gating, different refreshes.
    local function ApplyPower(rpNeedLayout, ufRefresh, writeRP, writeCFG, writeUF)
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end
        if wantUF()  and writeUF  then writeUF()  end

        if wantRP()  then RefreshRPPower(rpNeedLayout) end
        if wantCFG() then RefreshCFG() end
        if wantUF()  then ufRefresh() end
    end

    -- ════════════════════════════════════════════════════
    -- ABSORBS & HEAL PREDICTION write-through — same fan-out model as the
    -- healthPower and borders helpers above, but into the `absorbs` section
    -- (RP + CFG only — unit frames have no absorbs surface). One change
    -- lands on every Layout and every custom frame group at once.
    -- ════════════════════════════════════════════════════
    local ABSORBS_SECTION = "absorbs"

    local function rpAbsorbs()
        local p = BF.rpDB and BF.rpDB.profile
        local t = p and p[ABSORBS_SECTION]
        return type(t) == "table" and t or nil
    end

    -- Get-or-create flat.absorbs, rawget-guarded (see header invariants).
    local function EnsureAbsorbs(flat)
        if type(flat) ~= "table" then return nil end
        local t = rawget(flat, ABSORBS_SECTION)
        if type(t) ~= "table" then
            flat[ABSORBS_SECTION] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, ABSORBS_SECTION) end
            t = rawget(flat, ABSORBS_SECTION)
        end
        return type(t) == "table" and t or nil
    end

    -- RP: global section (identity preserved) + every layout flat.
    local function WriteRPAbsorbs(key, val)
        local gp = rpAbsorbs()
        if not gp then return end
        put(gp, key, val)
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureAbsorbs(flat)
            if t then put(t, key, val) end
        end
    end

    -- CFG: every group's flat.absorbs. overrideAbsorbs is left alone (same
    -- rationale as the other sections).
    local function WriteCFGAbsorbs(key, val)
        if not rpAbsorbs() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureAbsorbs(grp.flat)
                if t then put(t, key, val) end
            end
        end
    end

    -- ── Read side: absorbs ─────────────────────────────
    local function cfgAbsorbsSource()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[ABSORBS_SECTION]) == "table" then
                    return flat[ABSORBS_SECTION]
                end
            end
        end
        return rpAbsorbs()
    end
    local function absorbsSource()
        local s = readSurface()
        if s == "cfg" then return cfgAbsorbsSource() end
        -- UF has no absorbs section; fall back to RP so the widgets display
        -- something rather than nil when only UF is in scope.
        return rpAbsorbs()
    end

    -- Scope-gated write + refresh for absorbs settings. No UF branch.
    local function ApplyAbsorbs(writeRP, writeCFG, debounceBucket, rpRefreshFn, previewFn)
        -- See the block above ApplyBorders. Reaches ReducedMaxHealthText, whose
        -- block caches every key this page writes -- fontSize, fontFlags, point,
        -- x, y and the color triple (Indicators/ReducedMaxHealthText.lua:169-183).
        if BF._InvalidateSectionViews then BF:_InvalidateSectionViews("absorbs") end
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end

        if wantRP()  then BF:DebounceOption(debounceBucket, rpRefreshFn) end
        if wantCFG() then RefreshCFG() end
        if previewFn then previewFn() end
    end

    -- Layout refresh for absorb position/geometry changes.
    local function RefreshRPAbsorbsLayout()
        BF:LayoutAllIndicators()
        if BF.RefreshPreviewLayout then BF:RefreshPreviewLayout() end
    end

    -- Master-gate predicate for the absorbs subtab (mirrors absorbsOff in
    -- Options_Absorbs.lua but reads from the first in-scope surface).
    local function gsAbsorbsOff()
        local src = absorbsSource()
        return src and src.showAbsorbsMissingHealth == false
    end


    -- ════════════════════════════════════════════════════
    -- ICONS write-through — into the `icons` section (RP + CFG only —
    -- unit frames have no icons surface). One change lands on every
    -- Layout and every custom frame group at once.
    -- ════════════════════════════════════════════════════
    local ICONS_SECTION = "icons"

    local function rpIcons()
        local p = BF.rpDB and BF.rpDB.profile
        local t = p and p[ICONS_SECTION]
        return type(t) == "table" and t or nil
    end

    local function EnsureIcons(flat)
        if type(flat) ~= "table" then return nil end
        local t = rawget(flat, ICONS_SECTION)
        if type(t) ~= "table" then
            flat[ICONS_SECTION] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, ICONS_SECTION) end
            t = rawget(flat, ICONS_SECTION)
        end
        return type(t) == "table" and t or nil
    end

    local function WriteRPIcons(key, val)
        local gp = rpIcons()
        if not gp then return end
        put(gp, key, val)
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureIcons(flat)
            if t then put(t, key, val) end
        end
    end

    local function WriteCFGIcons(key, val)
        if not rpIcons() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureIcons(grp.flat)
                if t then put(t, key, val) end
            end
        end
    end

    local function cfgIconsSource()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[ICONS_SECTION]) == "table" then
                    return flat[ICONS_SECTION]
                end
            end
        end
        return rpIcons()
    end
    local function iconsSource()
        local s = readSurface()
        if s == "cfg" then return cfgIconsSource() end
        return rpIcons()
    end

    local function ApplyIcons(writeRP, writeCFG, debounceBucket, rpRefreshFn, previewFn)
        -- See the block above ApplyBorders. Reaches RoleIcon, RaidTargetIcon,
        -- LeaderIcon, StatusIcons, PingIndicator and NameText's role offset.
        -- Covers BOTH icons setters: Role Icon Style
        -- (Pages_GlobalStylesIcons.lua:163, which passes RefreshRPRoleIcons) and
        -- Role Icon Size (:186, which passes RefreshRPIconsLayout). Style is the
        -- one a refresh-side call missed.
        if BF._InvalidateSectionViews then BF:_InvalidateSectionViews("icons") end
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end
        if wantRP()  then BF:DebounceOption(debounceBucket, rpRefreshFn) end
        if wantCFG() then RefreshCFG() end
        if previewFn then previewFn() end
    end

    local function RefreshRPIconsLayout()
        BF:LayoutAllIndicators()
        if BF.RefreshPreviewLayout then BF:RefreshPreviewLayout() end
    end

    local function RefreshRPRoleIcons()
        for f in pairs(BF.activeFrames or {}) do BF:UpdateRoleIcon(f) end
        if BF.RefreshPreviewRoleIcon then BF:RefreshPreviewRoleIcon() end
    end

    -- ════════════════════════════════════════════════════
    -- TEXT write-through — into the `text` section (RP + CFG only —
    -- unit frames have their own OUF text handling with different keys).
    -- One change lands on every Layout and every custom frame group.
    -- ════════════════════════════════════════════════════
    local TEXT_SECTION = "text"

    local function rpText()
        local p = BF.rpDB and BF.rpDB.profile
        local t = p and p[TEXT_SECTION]
        return type(t) == "table" and t or nil
    end

    local function EnsureText(flat)
        if type(flat) ~= "table" then return nil end
        local t = rawget(flat, TEXT_SECTION)
        if type(t) ~= "table" then
            flat[TEXT_SECTION] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, TEXT_SECTION) end
            t = rawget(flat, TEXT_SECTION)
        end
        return type(t) == "table" and t or nil
    end

    local function WriteRPText(key, val)
        local gp = rpText()
        if not gp then return end
        put(gp, key, val)
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureText(flat)
            if t then put(t, key, val) end
        end
    end

    -- Text has subtable keys (namePosition, vehicleNamePosition, etc.)
    -- that need deep-write support for nested fields.
    local function WriteRPTextNested(section, subkey, val)
        local gp = rpText()
        if not gp then return end
        if type(gp[section]) ~= "table" then gp[section] = {} end
        gp[section][subkey] = val
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureText(flat)
            if t then
                if type(t[section]) ~= "table" then t[section] = {} end
                t[section][subkey] = val
            end
        end
    end

    local function WriteCFGText(key, val)
        if not rpText() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureText(grp.flat)
                if t then put(t, key, val) end
            end
        end
    end

    local function WriteCFGTextNested(section, subkey, val)
        if not rpText() then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureText(grp.flat)
                if t then
                    if type(t[section]) ~= "table" then t[section] = {} end
                    t[section][subkey] = val
                end
            end
        end
    end

    local function cfgTextSource()
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[TEXT_SECTION]) == "table" then
                    return flat[TEXT_SECTION]
                end
            end
        end
        return rpText()
    end
    local function textSource()
        local s = readSurface()
        if s == "cfg" then return cfgTextSource() end
        return rpText()
    end

    local function ApplyText(writeRP, writeCFG, debounceBucket, rpRefreshFn, previewFn)
        -- See the block above ApplyBorders. Reaches NameText, HealthText,
        -- LevelText, VehicleText and StatusText_Overlay. Covers the Health Text
        -- controls too (Pages_GlobalStylesText.lua:452-488), which pass
        -- HealthUpdate rather than a Layout refresh: HealthText:Update re-stamps
        -- _bf_htCfg only when the generation has moved
        -- (Indicators/HealthText.lua:417), and that stamp is a COPY of the section
        -- values (:111-128), so without a bump "Show Health Text" itself froze.
        if BF._InvalidateSectionViews then BF:_InvalidateSectionViews("text") end
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end
        if wantRP()  then BF:DebounceOption(debounceBucket, rpRefreshFn) end
        if wantCFG() then RefreshCFG() end
        if previewFn then previewFn() end
    end

    local function RefreshRPTextLayout()
        BF:LayoutAllIndicators()
        if BF.RefreshPreviewLayout then BF:RefreshPreviewLayout() end
    end

    -- LSM font values: the shared name -> path builder (see
    -- BF:LSMFontValues) so LSM30_Font previews each row in its own font.
    local gsBuildFontVals = function() return BF:LSMFontValues() end
    local GS_FONT_BORDER_VALUES = {
        [""] = "None (Default)", ["OUTLINE"] = "Outline", ["THICKOUTLINE"] = "Thick Outline",
        ["MONOCHROME"] = "Monochrome", ["OUTLINE, MONOCHROME"] = "Outline + Monochrome",
        ["THICKOUTLINE, MONOCHROME"] = "Thick Outline + Monochrome",
    }

    -- Font get helper (handles nil / "DEFAULT" / legacy path values).
    local function gsGetFont(key)
        local tp = textSource()
        return BF:NormalizeFontName(tp and tp[key])
    end

    -- ════════════════════════════════════════════════════
    -- AURAS write-through — into the `auras` section (RP + CFG) and
    -- into the ufDB profile for aura border settings (UF).
    -- Auras has subcategories: "buffs", "debuffs", "dispelIndicator".
    -- Write-through targets the specific subcategory within the auras
    -- section on every Layout and every custom frame group.
    -- UF aura borders use SHARED keys (oufAuraBorderStyle etc.) that
    -- apply to both buffs and debuffs — no separate buff/debuff border
    -- on unit frames.  Both the Buffs Border and Debuffs Border tabs
    -- write to these same UF keys (whichever the user changes last wins).
    -- ════════════════════════════════════════════════════
    local AURAS_SECTION = "auras"

    local function rpAurasSubcat(subcat)
        local p = BF.rpDB and BF.rpDB.profile
        local a = p and p[AURAS_SECTION]
        if type(a) ~= "table" then return nil end
        local t = a[subcat]
        return type(t) == "table" and t or nil
    end

    local function EnsureAurasSubcat(flat, subcat)
        if type(flat) ~= "table" then return nil end
        local a = rawget(flat, AURAS_SECTION)
        if type(a) ~= "table" then
            flat[AURAS_SECTION] = {}
            if BF.WireSectionFallback then BF:WireSectionFallback(flat, AURAS_SECTION) end
            a = rawget(flat, AURAS_SECTION)
        end
        if type(a) ~= "table" then return nil end
        if type(a[subcat]) ~= "table" then a[subcat] = {} end
        return a[subcat]
    end

    local function WriteRPAuras(subcat, key, val)
        local gp = rpAurasSubcat(subcat)
        if not gp then return end
        put(gp, key, val)
        local p  = BF.rpDB.profile
        local fl = p.layouts and p.layouts.flatLayouts
        if type(fl) ~= "table" then return end
        for _, flat in pairs(fl) do
            local t = EnsureAurasSubcat(flat, subcat)
            if t then put(t, key, val) end
        end
    end

    local function WriteCFGAuras(subcat, key, val)
        if not rpAurasSubcat(subcat) then return end
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) ~= "table" then return end
        for i = 1, #groups do
            local grp = groups[i]
            if type(grp) == "table" then
                local t = EnsureAurasSubcat(grp.flat, subcat)
                if t then put(t, key, val) end
            end
        end
    end

    -- UF aura border write-through. UF stores a SINGLE set of border
    -- keys shared by buffs and debuffs, so both the "buffs" and "debuffs"
    -- subcategory border writes translate to the same oufAura* profile keys.
    -- Map from the RP per-subcat keys to the flat UF key names:
    local UF_AURA_BORDER_MAP = {
        -- buffs subcat keys → per-kind UF keys
        buffBorderStyle        = "oufBuffBorderStyle",
        buffBlizzardBorders    = "oufBuffUseBlizzardBorders",
        buffBorderColor        = "oufBuffBorderColor",
        buffBorderThickness    = "oufBuffBorderThickness",
        -- debuffs subcat keys → per-kind UF keys
        debuffBorderStyle      = "oufDebuffBorderStyle",
        debuffBlizzardBorders  = "oufDebuffUseBlizzardBorders",
        debuffBorderColor      = "oufDebuffBorderColor",
        debuffBorderThickness  = "oufDebuffBorderThickness",
    }

    local function WriteUFAuras(key, val)
        local ufKey = UF_AURA_BORDER_MAP[key]
        if not ufKey then return end
        local pf = ufProfile(); if not pf then return end
        put(pf, ufKey, val)
    end

    local function cfgAurasSource(subcat)
        local groups = BF.cfgDB and BF.cfgDB.profile and BF.cfgDB.profile.customFrameGroups
        if type(groups) == "table" then
            for i = 1, #groups do
                local grp  = groups[i]
                local flat = type(grp) == "table" and grp.flat or nil
                if type(flat) == "table" and type(flat[AURAS_SECTION]) == "table"
                   and type(flat[AURAS_SECTION][subcat]) == "table" then
                    return flat[AURAS_SECTION][subcat]
                end
            end
        end
        return rpAurasSubcat(subcat)
    end
    local function aurasGSSource(subcat)
        local s = readSurface()
        if s == "cfg" then return cfgAurasSource(subcat) end
        return rpAurasSubcat(subcat)
    end

    local function ApplyAuras(subcat, writeRP, writeCFG, rpRefreshFn, previewFn, writeUF)
        if wantRP()  and writeRP  then writeRP()  end
        if wantCFG() and writeCFG then writeCFG() end
        if wantUF()  and writeUF  then writeUF()  end
        if wantRP()  and rpRefreshFn then rpRefreshFn() end
        if wantCFG() then RefreshCFG() end
        if wantUF()  then
            if BF.RestyleOUFAuraButtons then BF:RestyleOUFAuraButtons() end
        end
        if previewFn then previewFn() end
    end

    local function RefreshRPAurasLayout()
        BF:DebounceOption("aurasLayout", function()
            BF:LayoutAllIndicators()
        end)
        if BF.RefreshPreviewLayout then BF:RefreshPreviewLayout() end
    end

    -- Border style helpers for aura borders (mirrors Options_Auras.lua).
    local GS_AURA_BORDER_STYLE_VALUES = { blizzard = "Blizzard", flat = "Square", rounded = "Rounded", rounded_thick = "Rounded (Thick)" }
    local GS_AURA_BORDER_STYLE_SORTING = { "blizzard", "flat", "rounded", "rounded_thick" }

    -- ── Publish ────────────────────────────────────────
    return {
        scope = scope,
        wantRP = wantRP,
        wantCFG = wantCFG,
        wantUF = wantUF,
        readSurface = readSurface,
        rpGlobal = rpGlobal,
        ufProfile = ufProfile,
        EnsureHealthPower = EnsureHealthPower,
        put = put,
        WriteRP = WriteRP,
        WriteCFG = WriteCFG,
        rpBorders = rpBorders,
        EnsureBorders = EnsureBorders,
        WriteRPBorders = WriteRPBorders,
        WriteCFGBorders = WriteCFGBorders,
        WriteUFBorderEnable = WriteUFBorderEnable,
        WriteUFBorderStyle = WriteUFBorderStyle,
        WriteUFBorderColor = WriteUFBorderColor,
        WriteUFBorderThickness = WriteUFBorderThickness,
        RefreshRPBorders = RefreshRPBorders,
        cfgBordersSource = cfgBordersSource,
        bordersSource = bordersSource,
        readBorderEnable = readBorderEnable,
        readBorderStyle = readBorderStyle,
        readBorderColor = readBorderColor,
        readBorderThickness = readBorderThickness,
        RefreshRP = RefreshRP,
        RefreshCFG = RefreshCFG,
        RefreshUF = RefreshUF,
        ApplyBorders = ApplyBorders,
        Apply = Apply,
        cfgSource = cfgSource,
        hpSource = hpSource,
        readMode = readMode,
        readHealthColor = readHealthColor,
        readOpacity = readOpacity,
        readUseTexture = readUseTexture,
        readTexture = readTexture,
        readBgUseCustom = readBgUseCustom,
        readBgMode = readBgMode,
        readBgColor = readBgColor,
        readBgAlpha = readBgAlpha,
        readBgDarken = readBgDarken,
        readUsePowerTexture = readUsePowerTexture,
        readPowerTexture = readPowerTexture,
        readUsePowerBg = readUsePowerBg,
        readPowerBgColor = readPowerBgColor,
        readPowerBgOpacity = readPowerBgOpacity,
        RefreshRPPower = RefreshRPPower,
        RefreshUFPowerBg = RefreshUFPowerBg,
        RefreshUFPowerTexture = RefreshUFPowerTexture,
        ApplyPower = ApplyPower,
        rpAbsorbs = rpAbsorbs,
        EnsureAbsorbs = EnsureAbsorbs,
        WriteRPAbsorbs = WriteRPAbsorbs,
        WriteCFGAbsorbs = WriteCFGAbsorbs,
        cfgAbsorbsSource = cfgAbsorbsSource,
        absorbsSource = absorbsSource,
        ApplyAbsorbs = ApplyAbsorbs,
        RefreshRPAbsorbsLayout = RefreshRPAbsorbsLayout,
        gsAbsorbsOff = gsAbsorbsOff,
        rpIcons = rpIcons,
        EnsureIcons = EnsureIcons,
        WriteRPIcons = WriteRPIcons,
        WriteCFGIcons = WriteCFGIcons,
        cfgIconsSource = cfgIconsSource,
        iconsSource = iconsSource,
        ApplyIcons = ApplyIcons,
        RefreshRPIconsLayout = RefreshRPIconsLayout,
        RefreshRPRoleIcons = RefreshRPRoleIcons,
        rpText = rpText,
        EnsureText = EnsureText,
        WriteRPText = WriteRPText,
        WriteRPTextNested = WriteRPTextNested,
        WriteCFGText = WriteCFGText,
        WriteCFGTextNested = WriteCFGTextNested,
        cfgTextSource = cfgTextSource,
        textSource = textSource,
        ApplyText = ApplyText,
        RefreshRPTextLayout = RefreshRPTextLayout,
        gsGetFont = gsGetFont,
        rpAurasSubcat = rpAurasSubcat,
        EnsureAurasSubcat = EnsureAurasSubcat,
        WriteRPAuras = WriteRPAuras,
        WriteCFGAuras = WriteCFGAuras,
        WriteUFAuras = WriteUFAuras,
        cfgAurasSource = cfgAurasSource,
        aurasGSSource = aurasGSSource,
        ApplyAuras = ApplyAuras,
        RefreshRPAurasLayout = RefreshRPAurasLayout,
        scopeFallback = scopeFallback,
        BORDERS = BORDERS,
        UF_BORDER_BARS = UF_BORDER_BARS,
        ABSORBS_SECTION = ABSORBS_SECTION,
        ICONS_SECTION = ICONS_SECTION,
        TEXT_SECTION = TEXT_SECTION,
        gsBuildFontVals = gsBuildFontVals,
        GS_FONT_BORDER_VALUES = GS_FONT_BORDER_VALUES,
        AURAS_SECTION = AURAS_SECTION,
        UF_AURA_BORDER_MAP = UF_AURA_BORDER_MAP,
        GS_AURA_BORDER_STYLE_VALUES = GS_AURA_BORDER_STYLE_VALUES,
        GS_AURA_BORDER_STYLE_SORTING = GS_AURA_BORDER_STYLE_SORTING,
        UF_NPC_MODE = UF_NPC_MODE,
        SECTION = SECTION,
    }
end

local gs
function BuzzardFramesOptions:GS()
    if not gs then gs = BuildGS() end
    return gs
end

-- The shipped default for a Raid/Party section key -- what Reset and undo
-- restore. Global Styles writes the same key to three surfaces, so the
-- Raid/Party default is the one the page reports.
function BuzzardFramesOptions:GSDefault(section, key)
    local bf = _G.BuzzardFrames
    local d = bf and bf.raidPartyFrameDefaults and bf.raidPartyFrameDefaults.profile
    local s = d and d[section]
    if type(s) == "table" then return s[key] end
    return nil
end

-- ── The "Apply Changes To" strip ──────────────────────────────
--
-- The Ace section put this inline group at order 0.5 of every Global
-- Styles page: a note and one switch per surface the page can write,
-- stored in db.global.globalStyles. `descs` carries the per-page tooltip
-- strings (they differ page to page -- the Health & Power Bars page says
-- "Writes the Health & Power Bars section...", Borders says its own), and
-- a surface with NO desc gets NO switch: Icons, Absorbs and Text have no
-- unit-frame fan-out, and the Ace card offered two switches there rather
-- than a third that did nothing. `extraNote` is the second paragraph two
-- of those pages append to the note (Absorbs and Text), verbatim.
-- Returned as ONE group; the page puts it first.
--
-- A STRIP, not a card, and for the reason the Raid/Party per-Layout row is
-- one: this says WHERE the page writes rather than what it writes, so it is
-- chrome about the settings below it and must not read as another card of
-- settings. That costs the standing paragraph -- a band is one row -- so the
-- prose leads each switch's own tooltip instead, where a reader asking "what
-- does ticking this do" already looks. The caption wears the same sky blue
-- the per-Layout switch does: this configures the CONFIGURATION.
function BuzzardFramesOptions:GSScopeCard(descs, extraNote)
    descs = descs or {}
    local shared = "Settings below are written straight into the surfaces you "
        .. "tick here. Every Layout and every custom frame group is updated, "
        .. "not just the one you are currently editing."
    if extraNote and extraNote ~= "" then
        shared = shared .. "\n\n" .. extraNote
    end
    local function scopeSwitch(field, label, desc)
        return {
            control = "switch", label = label, desc = shared .. "\n\n" .. desc,
            -- State first, then what it is the state of -- the strip's own
            -- convention, and what keeps three switches on one row readable.
            labelSide = "after",
            id = "gsScope_" .. field, default = true,
            get = function()
                local GS = BuzzardFramesOptions:GS()
                if not GS then return true end
                local s = GS.scope()
                return s[field] ~= false
            end,
            set = function(_, ctx, v)
                if InCombatLockdown() then return end
                local GS = BuzzardFramesOptions:GS()
                if not GS then return end
                GS.scope()[field] = v and true or false
                -- The read side follows the first surface in scope, so
                -- every value on the page can change with this switch.
                ctx.app:RefreshPage()
            end,
            disabled = "combat",
        }
    end
    -- The caption, as a field rather than the group's title: a strip with a
    -- header is a card with its sides filed off, and the row reads as one
    -- sentence -- "Apply changes to: Raid/Party, Custom Frame Groups" --
    -- when the words sit on the row with the switches they govern.
    local fields = {
        -- A CARD'S HEADING, in a strip that has no header to put one in:
        -- the group heading's own gold and the heading font, read from the
        -- skin rather than copied, so the Group Heading Text swatch moves
        -- this with every other heading in the panel.
        { control = "note", text = "Apply Changes to:", compact = true,
          -- The size a card's title is drawn at (the form preset's
          -- headerSize), not the font object's own -- beside a page of
          -- card headings a smaller one reads as a caption.
          fontSize = 12,
          -- The font a card's own title is drawn in (Page.lua makes g.title
          -- from this one and sizes it to the preset's headerSize, which is
          -- this font's own 12), so the two headings match.
          font = "GameFontNormalSmall",
          color = function(_, ctx)
              local skin = ctx and ctx.app and ctx.app.skin
              return skin and skin.groupHeading
          end },
    }
    if descs.rp  then fields[#fields + 1] = scopeSwitch("rp",  "Raid/Party Frames",   descs.rp)  end
    if descs.cfg then fields[#fields + 1] = scopeSwitch("cfg", "Custom Frame Groups", descs.cfg) end
    if descs.uf  then fields[#fields + 1] = scopeSwitch("uf",  "Unit Frames",         descs.uf)  end
    -- The one thing about this strip a reader cannot work out from the
    -- switches: ticking a surface writes EVERY Layout and group of it, not
    -- the one on screen. `wide`, so it takes a line of its own under the
    -- row rather than flowing as a fourth item beside the switches.
    fields[#fields + 1] = {
        control = "note", wide = true, compact = true,
        text = "Every Layout and Custom Frame Group is updated.",
    }
    return {
        preset = "strip", id = "gsScope",
        -- `justify = "start"`: the strip preset SPREADS by default -- spare
        -- width dealt out between the items -- which is right for the
        -- per-Layout row, where a switch at one end and a dropdown at the
        -- other are two different things with the width between them. These
        -- are one list of surfaces to tick, so they flow from the left and
        -- the spare width stays at the end, instead of two of them being
        -- flung against the right edge.
        justify = "start",
        fields = fields,
    }
end
