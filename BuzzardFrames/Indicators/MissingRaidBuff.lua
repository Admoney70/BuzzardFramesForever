--[[
BuzzardFrames: Indicators/MissingRaidBuff.lua
Missing raid buff icons -- one icon per missing buff of the player's class
(Fortitude, Mark of the Wild, ...; a Forever Priest has three), out of
combat only.

Reads tracker state from BF._missingRaidBuffTrackers, the ordered list
AuraCustomizations.lua (EnsureMissingRaidBuffTrackers) keeps: one
SingleAuraTracker per buff the player's class can be reminded of, in
BF.MISSING_RAID_BUFFS order. The trackers maintain s.idx[unit] from the
shared HELPFUL scan in Buffs:UNIT_AURA; this indicator fills its icon slots
with the textures of the trackers reporting absent, in list order, packed.

Slot 1 is frame.missingRaidBuffIcon (sized by ApplyAuraGeometry,
AuraConfig.lua, and invalidated by name elsewhere); every slot, slot 1
included, is in frame.missingRaidBuffIcons. Slots past the first are built
on demand, so a class with one buff never carries more than one.

Options preview frames never run :Update (PreviewSystem.lua); the Test
Missing Raid Buff switch paints them through BF:PaintMissingRaidBuffPreview.
]]

local BF  = LibStub("AceAddon-3.0"):GetAddon("BuzzardFrames")

local UnitIsConnected  = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsVisible    = UnitIsVisible
local UnitIsUnit       = UnitIsUnit
local GetSpellTexture  = C_Spell and C_Spell.GetSpellTexture

local SetIconBorderColor = BF.SetIconBorderColor

local MissingRaidBuff = BF.indicatorPrototype:new("missingRaidBuff")

-- Per-indicator Create: build slot 1. No tooltip wiring (missing-raid-buff
-- icons never had tooltips). OVERLAY draw layer and the desaturate that gives
-- the "buff missing" visual cue. Preview frames get it too, for the Test
-- Missing Raid Buff switch.
function MissingRaidBuff:Layout() end

local function BuildSlot(parent)
    local level = parent:GetFrameLevel() + 223
    local icon = BF.BuildAuraIconFrame(parent, level + 1)
    if icon.Icon then
        icon.Icon:SetDrawLayer("OVERLAY", 1)
        icon.Icon:SetDesaturated(true)
    end
    icon:Hide()
    return icon
end

function MissingRaidBuff:Create(parent)
    if parent.missingRaidBuffIcon then return end
    local icon = BuildSlot(parent)
    parent.missingRaidBuffIcon  = icon
    parent.missingRaidBuffIcons = { icon }
end

-- Grow the slot list to n. Cold: runs only when more buffs are missing at
-- once than this frame has ever shown.
local function EnsureSlots(frame, n)
    local slots = frame.missingRaidBuffIcons
    for i = #slots + 1, n do
        slots[i] = BuildSlot(frame)
    end
    return slots
end

-- ============================================================
-- ICON EFFECT (None / Glow / Marching Ants / Flash + Effect Color, and
-- Steady / Pulsing for Glow) -- the Buffs Icon Effect, drawn with the same
-- art and the same declarative machinery as Auras/ContainerFactory.lua
-- (InitAuraButton's glow ring, ants FlipBook and flash pulse; ApplyGlowCore /
-- ApplyIconEffectCore), sized by the same BF.AURA_GLOW_PAD / AURA_ANTS_SCALE.
-- These icons are BF-built frames (BuildAuraIconFrame), not engine-owned aura
-- buttons, so the regions are created lazily on first use and the animation
-- groups merely Play()/Stop() -- and only while an icon is shown, so a hidden
-- or effect-less icon steps no animation at all.
--
-- `fx` is a resolved block { effect, pulse, r, g, b, a } (ResolveFx below).
-- ApplyFx is change-guarded on the block's identity and the icon size, so a
-- redraw with nothing changed costs two compares.
-- ============================================================
local function EnsureFx(icon)
    if icon._mrbGlow then return end
    local glow = BF.Texture(icon, nil, "OVERLAY", nil, 2)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:Hide()
    local gAG = glow:CreateAnimationGroup()
    gAG:SetLooping("REPEAT")
    local gIn = gAG:CreateAnimation("Alpha")
    gIn:SetOrder(1); gIn:SetDuration(0.6)
    local gOut = gAG:CreateAnimation("Alpha")
    gOut:SetOrder(2); gOut:SetDuration(0.6)

    local ants = BF.Texture(icon, nil, "OVERLAY", nil, 3)
    ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
    ants:Hide()
    local aAG = ants:CreateAnimationGroup()
    aAG:SetLooping("REPEAT")
    local fb = aAG:CreateAnimation("FlipBook")
    fb:SetDuration(0.7)
    fb:SetFlipBookRows(5); fb:SetFlipBookColumns(5); fb:SetFlipBookFrames(22)
    -- 48px frames on a 256px sheet: without explicit frame dimensions the
    -- flipbook divides the FULL sheet into 5ths and every frame samples
    -- off-grid (the ants visibly jump).
    if fb.SetFlipBookFrameWidth then
        fb:SetFlipBookFrameWidth(48)
        fb:SetFlipBookFrameHeight(48)
    end

    local flash = BF.Texture(icon, nil, "OVERLAY", nil, 4)
    flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    flash:SetBlendMode("ADD")
    flash:SetAllPoints(icon)
    flash:SetAlpha(0)
    flash:Hide()
    local fAG = flash:CreateAnimationGroup()
    fAG:SetLooping("REPEAT")
    local fIn = fAG:CreateAnimation("Alpha")
    fIn:SetOrder(1); fIn:SetDuration(0.4); fIn:SetFromAlpha(0)
    local fOut = fAG:CreateAnimation("Alpha")
    fOut:SetOrder(2); fOut:SetDuration(0.4); fOut:SetToAlpha(0)

    icon._mrbGlow,  icon._mrbGlowAG,  icon._mrbGlowIn,  icon._mrbGlowOut  = glow,  gAG, gIn, gOut
    icon._mrbAnts,  icon._mrbAntsAG                                       = ants,  aAG
    icon._mrbFlash, icon._mrbFlashAG, icon._mrbFlashIn, icon._mrbFlashOut = flash, fAG, fIn, fOut
end

local function StopAG(ag)
    if ag and ag:IsPlaying() then ag:Stop() end
end

-- Stop and hide every effect region. Cheap no-op on an icon that never had one.
local function ClearFx(icon)
    if not icon._mrbFx then return end
    StopAG(icon._mrbGlowAG);  icon._mrbGlow:Hide()
    StopAG(icon._mrbAntsAG);  icon._mrbAnts:Hide()
    StopAG(icon._mrbFlashAG); icon._mrbFlash:Hide()
    icon._mrbFx, icon._mrbFxSize = nil, nil
end

local function ApplyFx(icon, fx, size)
    if not fx then ClearFx(icon) return end
    if icon._mrbFx == fx and icon._mrbFxSize == size then return end
    EnsureFx(icon)
    local kind, r, g, b, a = fx.effect, fx.r, fx.g, fx.b, fx.a

    -- Glow ring. Tint on the vertex color, STRENGTH on object alpha (the
    -- ContainerFactory rule: vertex-color alpha does not read on these assets).
    local glow = icon._mrbGlow
    if kind == "glow" then
        local pad = size * BF.AURA_GLOW_PAD
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        glow:SetVertexColor(r, g, b)
        glow:SetAlpha(a)
        glow:Show()
        local ag = icon._mrbGlowAG
        if fx.pulse then
            icon._mrbGlowIn:SetFromAlpha(a * 0.35);  icon._mrbGlowIn:SetToAlpha(a)
            icon._mrbGlowOut:SetFromAlpha(a);        icon._mrbGlowOut:SetToAlpha(a * 0.35)
            if not ag:IsPlaying() then ag:Play() end
        elseif ag:IsPlaying() then
            -- Stop() restores the baked alpha; re-stamp the picker's.
            ag:Stop()
            glow:SetAlpha(a)
        end
    else
        StopAG(icon._mrbGlowAG)
        glow:Hide()
    end

    -- Marching ants, centered, icon x AURA_ANTS_SCALE.
    local ants = icon._mrbAnts
    if kind == "ants" then
        local aw = size * BF.AURA_ANTS_SCALE
        ants:ClearAllPoints()
        ants:SetPoint("CENTER", icon, "CENTER", 0, 0)
        ants:SetSize(aw, aw)
        ants:SetVertexColor(r, g, b)
        ants:SetAlpha(a)
        ants:Show()
        local ag = icon._mrbAntsAG
        if not ag:IsPlaying() then ag:Play() end
    else
        StopAG(icon._mrbAntsAG)
        ants:Hide()
    end

    -- Flash: the color's alpha is the pulse peak.
    local flash = icon._mrbFlash
    if kind == "flash" then
        flash:SetVertexColor(r, g, b)
        icon._mrbFlashIn:SetToAlpha(a)
        icon._mrbFlashOut:SetFromAlpha(a)
        flash:Show()
        local ag = icon._mrbFlashAG
        if not ag:IsPlaying() then ag:Play() end
    else
        StopAG(icon._mrbFlashAG)
        flash:Hide()
    end

    icon._mrbFx, icon._mrbFxSize = fx, size
end

-- Effect Color default: red, the color the old Show Glow ants always drew.
local FX_DEFAULT_COLOR = { r = 1, g = 0, b = 0, a = 1 }

-- The icons section's Icon Effect as one block, or nil for None. A fresh
-- table per call: called once per settings resolve (UpdateDB) and once per
-- preview paint, never per aura event.
local function ResolveFx(ip)
    local kind = ip and ip.missingRaidBuffIconEffect
    if kind ~= "glow" and kind ~= "ants" and kind ~= "flash" then return nil end
    local c = ip.missingRaidBuffIconEffectColor or FX_DEFAULT_COLOR
    return {
        effect = kind,
        pulse  = ip.missingRaidBuffIconEffectGlowStyle == "pulse",
        r = c.r or 1, g = c.g or 0, b = c.b or 0, a = c.a or 1,
    }
end

-- Per-scope cache write. Fields live in the `icons` section, not `auras`.
-- show* toggles stay off-cache (read live via GetCachedSection in
-- :Update) — only geometry fields are pre-resolved here.
function MissingRaidBuff:UpdateDB(cache, flat, grp)
    local ipp = BF.ResolveCFGSection(BF, flat, grp, "icons") or {}
    cache.missingRaidBuffSize    = ipp.missingRaidBuffSize    or 12
    cache.missingRaidBuffAnchor  = ipp.missingRaidBuffAnchor  or "CENTER"
    cache.missingRaidBuffOffsetX = ipp.missingRaidBuffOffsetX or 0
    cache.missingRaidBuffOffsetY = ipp.missingRaidBuffOffsetY or 0
    cache.missingRaidBuffSpacing = ipp.missingRaidBuffSpacing or 2
    cache.missingRaidBuffFx      = ResolveFx(ipp)
    cache.missingRaidBuffDesaturate = ipp.missingRaidBuffDesaturate ~= false
    cache._roundedMissingRaidBuffSize = BF:PixelRound(cache.missingRaidBuffSize)
end

-- ============================================================
-- HideAll
-- ============================================================
local function HideSlot(icon)
    if icon:IsShown() then
        ClearFx(icon)
        icon:Hide()
    end
end

function MissingRaidBuff:HideAll(frame)
    local slots = frame.missingRaidBuffIcons
    if not slots then return end
    for i = 1, #slots do HideSlot(slots[i]) end
end

-- ============================================================
-- Render: show slots 1..n with textures[1..n] and hide the rest.
--
-- The row grows away from the anchor's side: rightward from a LEFT anchor,
-- leftward from a RIGHT anchor, centered on any other anchor. Positions are
-- re-applied only when something that decides them changed; slot 1's
-- SF_MissingAnchor / cachedSize being nil (other files clear them by name on
-- a geometry refresh) forces a re-apply of every slot.
-- ============================================================
local function Render(frame, textures, n, size, anchor, offX, offY, spacing, fx, desat)
    local slots = EnsureSlots(frame, n)
    local first = slots[1]
    if first.SF_MissingAnchor == nil or first.cachedSize == nil
       or frame._mrbN ~= n or frame._mrbSize ~= size or frame._mrbAnchor ~= anchor
       or frame._mrbX ~= offX or frame._mrbY ~= offY or frame._mrbSpacing ~= spacing then
        local step = size + spacing
        local startX
        if anchor:find("LEFT") then
            startX = offX
        elseif anchor:find("RIGHT") then
            startX = offX - (n - 1) * step
        else
            startX = offX - (n - 1) * step / 2
        end
        for i = 1, n do
            local icon = slots[i]
            icon:SetSize(size, size)
            icon.cachedSize = size
            icon:ClearAllPoints()
            icon:SetPoint(anchor, frame, anchor, startX + (i - 1) * step, offY)
        end
        first.SF_MissingAnchor = anchor
        frame._mrbN, frame._mrbSize, frame._mrbAnchor = n, size, anchor
        frame._mrbX, frame._mrbY, frame._mrbSpacing   = offX, offY, spacing
    end
    for i = 1, n do
        local icon = slots[i]
        icon.Icon:SetTexture(textures[i])
        -- Desaturate Icons (default on). Change-guarded: a plain property
        -- setter, but no reason to re-stamp it on every redraw.
        if icon._mrbDesat ~= desat then
            icon.Icon:SetDesaturated(desat)
            icon._mrbDesat = desat
        end
        icon.Icon:Show()
        SetIconBorderColor(icon, 0, 0, 0, 0.8)
        icon.count:Hide()
        if icon.cooldown then icon.cooldown:SetCooldown(0, 0); icon.cooldown:Hide() end
        icon:Show()
        ApplyFx(icon, fx, size)
    end
    for i = n + 1, #slots do HideSlot(slots[i]) end
end

-- Scratch list of the textures to show. Filled and consumed inside one
-- Update; never held across calls.
local _textures = {}

-- ============================================================
-- Update
-- ============================================================
function MissingRaidBuff:Update(frame, unit)
    -- Pet frames: pets don't need missing raid buff indicators
    local parentHeader = frame._bf_parentHeader or frame:GetParent()
    if parentHeader and parentHeader.isPetFrame then
        self:HideAll(frame)
        return
    end

    -- FAST-PATH FEATURE GATE: resolve the feature-enabled check BEFORE any
    -- other work. This function fires on every buff UNIT_AURA event (bound
    -- to the buffs status), so if the feature is off, we must return with
    -- essentially zero cost. The guard reads section config via the cached
    -- section profile (Perf 1A), a single table hash lookup.
    local p_mb = BF:GetCachedSection("icons", frame)
    if not p_mb then
        return
    end
    if not p_mb.showMissingRaidBuff then
        -- Feature off. Sweep any lingering icon from a previous enabled
        -- state; HideAll bails per slot on `not IsShown()`, so the steady
        -- state stays at one table index + one IsShown() per slot.
        self:HideAll(frame)
        return
    end

    local list = BF._missingRaidBuffTrackers
    if not list or #list == 0 then
        self:HideAll(frame)
        return
    end

    if not frame.missingRaidBuffIcon then return end

    -- Skip preview/dummy frames — BF:PaintMissingRaidBuffPreview paints them.
    if frame._isPreviewFrame then return end

    -- v93: hostile/charmed suppression (Auras/ContainerFactory.lua). This
    -- indicator reads real aura data through SingleAuraTrackers, which keeps
    -- working on a charmed member -- so without this gate the frame would go
    -- on advertising the raid buffs a hostile unit is "missing", the one
    -- aura visual left on an otherwise blank frame.
    if BF:IsUnitAuraSuppressed(unit) then
        self:HideAll(frame)
        return
    end

    local ac = BF:GetAuraCacheForFrame(frame)

    -- Gate: global showBuffs off suppresses everything including missing buff
    if ac.showBuffs == false then
        self:HideAll(frame)
        return
    end

    -- Gate: unit not visible (phased, cross-shard)
    if not UnitIsVisible(unit) then
        self:HideAll(frame)
        return
    end

    -- OUT OF COMBAT ONLY, unconditionally. 12.1 makes the in-combat case
    -- impossible; the stored showMissingRaidBuffInCombat key survives in old
    -- profiles and is deliberately NOT read here.
    -- This Layout's own Instance Type condition: another Layout may be
    -- keeping the trackers alive where this one's condition is not met.
    if BF._inCombat
       or not BF.MissingRaidBuffInstanceMet(p_mb)
       or not UnitIsConnected(unit)
       or UnitIsDeadOrGhost(unit) then
        self:HideAll(frame)
        return
    end

    -- One texture per tracked buff that is ticked in THIS Layout's Enabled
    -- Buffs and absent on the unit, in list (slot) order. A tracker still
    -- waiting on its texture (SingleAuraTrackers DoRegisterNow) is skipped.
    -- Personal buffs (Symbiotic Relationship) show only on the player's own
    -- frame while grouped, and are read from the literal "player" token: the
    -- framework's player-scoped UNIT_AURA subscription writes s.idx["player"],
    -- not s.idx[frame.unit] (raid7 / party3).
    local n = 0
    local isPlayer
    local enabled = BF.MissingRaidBuffEnabled
    for i = 1, #list do
        local rec = list[i]
        local t, e = rec.tracker, rec.entry
        local tex = t.registered and t.missingTexture
        if tex and enabled(p_mb, e.key) then
            local absent
            if e.personal then
                if isPlayer == nil then isPlayer = UnitIsUnit(unit, "player") and true or false end
                absent = isPlayer
                    and GetNumGroupMembers and GetNumGroupMembers() > 0
                    and t:IsAbsent("player")
            else
                absent = t:IsAbsent(unit)
            end
            if absent then
                n = n + 1
                _textures[n] = tex
            end
        end
    end

    if n == 0 then
        self:HideAll(frame)
        return
    end
    Render(frame, _textures, n,
        ac._roundedMissingRaidBuffSize or 12,
        ac.missingRaidBuffAnchor  or "CENTER",
        ac.missingRaidBuffOffsetX or 0,
        ac.missingRaidBuffOffsetY or 0,
        ac.missingRaidBuffSpacing or 2,
        ac.missingRaidBuffFx,
        ac.missingRaidBuffDesaturate ~= false)
    for i = 1, n do _textures[i] = nil end
end

-- ============================================================
-- Options preview (Test Missing Raid Buff).
--
-- Preview frames never run :Update. With the test switch on (a global debug
-- flag, BF.db.global.testMissingRaidBuff, reset every reload) and the
-- feature on in the frame's Layout, show one icon per buff of the player's
-- class ticked in that Layout's Enabled Buffs -- the full row, so size,
-- spacing, position and icon effect can all be judged. Known-ness and the Instance
-- Type condition are ignored here, as previews ignore Combat Status.
-- Called from Preview/PreviewData.lua ApplyPreviewIconTests with the
-- frame's own icons section.
-- ============================================================
function BF:PaintMissingRaidBuffPreview(frame, ip)
    if not frame.missingRaidBuffIcons then return end
    if not (ip and ip.showMissingRaidBuff and BF.db.global.testMissingRaidBuff) then
        MissingRaidBuff:HideAll(frame)
        return
    end
    local cls = UnitClassBase and UnitClassBase("player")
    local all = BF.MISSING_RAID_BUFFS or {}
    local enabled = BF.MissingRaidBuffEnabled
    local n = 0
    for i = 1, #all do
        local e = all[i]
        if e.class == cls and enabled(ip, e.key) then
            local tex = GetSpellTexture and GetSpellTexture(e.spell)
            if tex then
                n = n + 1
                _textures[n] = tex
            end
        end
    end
    if n == 0 then
        MissingRaidBuff:HideAll(frame)
        return
    end
    Render(frame, _textures, n,
        BF:PixelRound(ip.missingRaidBuffSize or 12),
        ip.missingRaidBuffAnchor  or "CENTER",
        ip.missingRaidBuffOffsetX or 0,
        ip.missingRaidBuffOffsetY or 0,
        ip.missingRaidBuffSpacing or 2,
        ResolveFx(ip),
        ip.missingRaidBuffDesaturate ~= false)
    for i = 1, n do _textures[i] = nil end
end

BF:RegisterIndicator(MissingRaidBuff)
MissingRaidBuff:EnableDeferredUpdates()

-- ============================================================
-- Combat-state hide/re-evaluate (plan §6.1 user decision).
--
-- The indicator is out-of-combat only (12.1), so it must hide
-- immediately on combat enter (not freeze the last-rendered state until
-- the next per-unit UA) and re-evaluate on combat exit. This used to be
-- conditional on the showMissingRaidBuffInCombat opt-in; now it always
-- applies.
--
-- Implementation: subscribe to PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED
-- via a dedicated event frame. On either event, call UpdateAllFrames so
-- every visible frame runs through MissingRaidBuff:_DoUpdate, which already
-- contains the correct in-combat gates (wantMissingCheck at the top of the
-- missing-detection block). On combat enter, every frame's gate will
-- evaluate to "don't check" and HideAll will fire. On combat exit, the
-- gate evaluates to "check" and the icon re-renders based on live tracker
-- state.
--
-- UpdateAllFrames goes through the deferred dispatcher's Update stub
-- (because the prototype's UpdateAllFrames calls self:Update, which was
-- replaced by EnableDeferredUpdates). That just marks every visible frame
-- dirty -- the actual _DoUpdate runs on the next OnUpdate flush. For an
-- immediate effect (HideAll on combat enter feels "instant"), we could
-- call _DoUpdate directly, but the one-frame deferral is imperceptible
-- and uses the existing batching infrastructure.
--
-- Combat-safe: PLAYER_REGEN_DISABLED fires entering combat, but the
-- dispatch path (mark dirty -> next OnUpdate -> _DoUpdate -> HideAll ->
-- mIcon:Hide + ants animation Stop) touches no protected APIs.
do
    -- v86 (event refactor stage 4): was a private CreateFrame. Both events
    -- are unitless, so this is a straight lift onto the shared layer.
    local combatEvents = BF:EventOwner("missingRaidBuffCombat")
    local function OnCombatChanged()
        if MissingRaidBuff.UpdateAllFrames then
            MissingRaidBuff:UpdateAllFrames()
        end
    end
    combatEvents:Sub("PLAYER_REGEN_DISABLED", OnCombatChanged, "unitless")
    combatEvents:Sub("PLAYER_REGEN_ENABLED",  OnCombatChanged, "unitless")
end
