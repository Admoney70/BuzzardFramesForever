-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesAbsorbs.lua
-- The GLOBAL STYLES > Absorbs & Heal Prediction section, in BuzzardPanel.
--
-- The panel equivalent of the `absorbsHealPred` group in BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, the same writes and
-- the same side effects, with the AceConfig `childGroups = "tab"` group
-- replaced by four BuzzardPanel pages -- one per subtab, each a route of
-- its own under `globalStyles/absorbsHealPred`, drawn as a strip by the
-- `tabs` navigator that node declares (the Pages_Icons pattern).
--
-- Storage: NONE of its own. Global Styles is a write-through: every field
-- here fans out through the shared helpers in Pages_GlobalStylesShared.lua
-- (`BuzzardFramesOptions:GS()`) into the `absorbs` section of the
-- Raid/Party profile -- the global section AND every Layout flat -- and
-- into every custom frame group's flat. The unit frames have no absorbs
-- surface at all, which is why ApplyAbsorbs has no UF branch and why the
-- Ace "Apply Changes To" card on this section offered only two switches.
--
-- Reads come back from GS.absorbsSource(): the first surface in scope, the
-- one a change would definitely land on. After any change here the
-- in-scope surfaces agree anyway.
--
-- Every field is therefore get/set rather than bound -- one write fans out
-- to many places, so there is no single table for `bind` to resolve
-- against -- and every field carries its RP storage key as `id` plus the
-- shipped Raid/Party default (via BuzzardFramesOptions:GSDefault) so
-- right-click Undo and Reset still work.
--
-- The Test flags (testAbsorb, testAbsorbSize, testHealAbsorb,
-- testHealPrediction, testReducedMaxHealth) are GLOBAL debug flags on
-- BF.db.global, cleared on every reload -- the fields on these pages that
-- fan out nowhere, exactly as in the Ace section.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- Nothing at file scope reads the addon: every helper below resolves it
-- when the panel calls, which is after BuzzardFrames has loaded.
local function BF() return _G.BuzzardFrames end

-- The fan-out table, resolved lazily on every use for the same reason.
local function GS() return BuzzardFramesOptions:GS() end

-- ── Read side ──────────────────────────────────────────────────
--
-- The absorbs section of whichever surface the page is displaying.
local function Src()
    local gs = GS()
    return gs and gs.absorbsSource()
end

-- The Ace gsAbsorbsOff(): the missing-health master is off only when the
-- stored value is EXPLICITLY false -- an unseeded profile reads as on.
local function AbsorbsOff()
    local gs = GS()
    return gs and gs.gsAbsorbsOff()
end

-- ── Shared option lists ────────────────────────────────────────
--
-- The statusbar textures LibSharedMedia knows, alphabetical -- the same
-- list the Ace LSM30_Statusbar widgets offered, previews and all: each
-- entry carries its `texture`, which the dropdown draws behind the name.
local function StatusbarOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out, names = {}, {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for i = 1, #names do
        out[i] = { value = names[i], text = names[i],
                   texture = LSM:Fetch("statusbar", names[i]) }
    end
    return out
end

-- ── Defaults ───────────────────────────────────────────────────
--
-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source; never a literal restated here.
local function GSD(key)
    return BuzzardFramesOptions:GSDefault("absorbs", key)
end

-- Storage is keyed ({r=,g=,b=,a=}); the panel's color control speaks
-- arrays, so the default is converted into the control's own shape.
local function ColorDefault(key, hasAlpha)
    local c = GSD(key)
    if type(c) ~= "table" then return nil end
    if hasAlpha then return { c.r, c.g, c.b, c.a } end
    return { c.r, c.g, c.b }
end

local function GetColor(key, hasAlpha)
    return function()
        local src = Src()
        local c   = src and src[key]
        if type(c) ~= "table" then return nil end
        if hasAlpha then return { c.r, c.g, c.b, c.a } end
        return { c.r, c.g, c.b }
    end
end

-- ── Refresh chains ─────────────────────────────────────────────
--
-- One function per chain the Ace setters passed to ApplyAbsorbs, in the
-- order they ran it. The debounce BUCKET names are the Ace ones
-- ("absorbs", "healAbsorbs", "healPred", "reducedMax"), so a change made
-- here coalesces with one made on the Raid/Party page instead of running
-- twice while both panels exist.

local function RefreshAbsorbs()
    local bf = BF()
    if bf then bf:RefreshAllAbsorbs() end
end

-- The overshield style and the custom-texture routes re-cut cached
-- textures, so the cache is stale-marked BEFORE the refresh reads through
-- it again -- the same order the Ace setters keep.
local function RefreshAbsorbsTexture()
    local bf = BF()
    if not bf then return end
    if bf.InvalidateAbsorbTextureCaches then bf:InvalidateAbsorbTextureCaches() end
    bf:RefreshAllAbsorbs()
end

local function PreviewAbsorb()
    local bf = BF()
    if bf and bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
end

local function RefreshHealAbsorbs()
    local bf = BF()
    if bf then bf:RefreshAllHealAbsorbs() end
end

local function PreviewHealAbsorb()
    local bf = BF()
    if bf and bf.RefreshPreviewHealAbsorb then bf:RefreshPreviewHealAbsorb() end
end

local function RefreshHealPrediction()
    local bf = BF()
    if bf then bf:RefreshAllHealPrediction() end
end

local function PreviewHealPrediction()
    local bf = BF()
    if bf and bf.RefreshPreviewHealPrediction then bf:RefreshPreviewHealPrediction() end
end

local function RefreshReducedMax()
    local bf = BF()
    if bf then bf:RefreshAllReducedMaxHealth() end
end

local function PreviewReducedMax()
    local bf = BF()
    if bf and bf.RefreshPreviewReducedMaxHealth then bf:RefreshPreviewReducedMaxHealth() end
end

-- Re-layout every active frame, then refresh the options-panel preview --
-- the shared helper the Ace setters called by the same name.
local function LayoutFrames()
    local gs = GS()
    if gs then gs.RefreshRPAbsorbsLayout() end
end

-- The reduced-max % text look: re-layout, then re-run every indicator.
local function ReducedMaxTextLook()
    local bf = BF()
    if not bf then return end
    LayoutFrames()
    for frame in pairs(bf.activeFrames or {}) do
        frame:UpdateIndicators()
    end
end

-- Flipping WHAT the % text is (shown at all, appended, appended where)
-- also re-evaluates the conditional reducedmaxhealth->nameText bind.
local function ReducedMaxTextBind()
    local bf = BF()
    if not bf then return end
    if bf.RebindAbsorbStatuses then bf:RebindAbsorbStatuses() end
    ReducedMaxTextLook()
end

-- ── The write fan-out ──────────────────────────────────────────
--
-- One call per Ace setter shape: ApplyAbsorbs(writeRP, writeCFG, bucket,
-- rpRefreshFn, previewFn), with the same arguments in the same order.
local function Fan(key, val, bucket, rpRefresh, preview)
    local gs = GS()
    if not gs then return end
    gs.ApplyAbsorbs(
        function() gs.WriteRPAbsorbs(key, val) end,
        function() gs.WriteCFGAbsorbs(key, val) end,
        bucket, rpRefresh, preview)
end

local function SetAbsorb(key, val)
    Fan(key, val, "absorbs", RefreshAbsorbs, PreviewAbsorb)
end

local function SetAbsorbTexture(key, val)
    Fan(key, val, "absorbs", RefreshAbsorbsTexture, PreviewAbsorb)
end

local function SetHealAbsorb(key, val)
    Fan(key, val, "healAbsorbs", RefreshHealAbsorbs, PreviewHealAbsorb)
end

local function SetHealPred(key, val)
    Fan(key, val, "healPred", RefreshHealPrediction, PreviewHealPrediction)
end

local function SetReducedMax(key, val)
    Fan(key, val, "reducedMax", RefreshReducedMax, PreviewReducedMax)
end

local function SetReducedMaxBind(key, val)
    Fan(key, val, "reducedMax", ReducedMaxTextBind, PreviewReducedMax)
end

local function SetReducedMaxLook(key, val)
    Fan(key, val, "reducedMax", ReducedMaxTextLook, PreviewReducedMax)
end

local function SetReducedMaxLayout(key, val)
    Fan(key, val, "reducedMax", LayoutFrames, PreviewReducedMax)
end

-- Color setters write a FRESH keyed table, the very shape the Ace setters
-- wrote, through the same fan-out.
local function SetColor(key, hasAlpha, writer)
    return function(_, _, v)
        if InCombatLockdown() then return end
        local col
        if hasAlpha then
            col = { r = v[1], g = v[2], b = v[3], a = v[4] }
        else
            col = { r = v[1], g = v[2], b = v[3] }
        end
        writer(key, col)
    end
end

-- ── Visibility and enabled predicates ──────────────────────────
--
-- Copies of the Ace bodies, one per shape, so a field can name the one it
-- had rather than restating it.

-- The Ace missing-health color/texture GROUP predicate: hidden with no
-- profile at all, hidden when the master is explicitly off, and hidden
-- when a LEFT-anchored active overshield has taken the bar over.
local function MissingOff()
    local bf  = BF()
    local src = Src()
    if not src then return true end
    return src.showAbsorbsMissingHealth == false
        or (src.overshieldAnchor == "LEFT"
            and bf and bf:IsOvershieldActive(src)
            and src.overshieldStyle ~= "Glow")
end

-- The Ace overshield color/texture GROUP predicate.
local function OvershieldOff()
    if AbsorbsOff() then return true end
    local src = Src()
    return src and src.overshieldStyle == "Glow"
end

local function OvershieldDisabled()
    local bf = BF()
    return InCombatLockdown()
        or not (bf and bf:IsOvershieldActive(Src()))
end

-- hidden = "this key is not truthy" -- the commonest Ace shape here.
local function NotShown(key)
    return function()
        local src = Src()
        return not (src and src[key])
    end
end

-- disabled = "in combat, or this key is not truthy".
local function CombatOrNot(key)
    return function()
        local src = Src()
        return InCombatLockdown() or not (src and src[key])
    end
end

-- Only the two "(Blizzard Style)" heal absorb styles draw the plus
-- symbols, so their color pair exists only there.
local function HealAbsorbBlizzStyle()
    local src = Src()
    return src and (src.healAbsorbStyle == "OverlayBlizzard"
        or src.healAbsorbStyle == "BarBlizzard")
end

-- The reduced-max master is off only when EXPLICITLY false.
local function ReducedOff()
    local src = Src()
    return src and src.showReducedMaxHealth == false
end

-- hidden for the % text fields: master off, or the text not shown.
local function ReducedTextOff()
    local src = Src()
    if not src then return true end
    return src.showReducedMaxHealth == false or not src.showReducedMaxHealthText
end

-- ... and additionally when the text is APPENDED to another element
-- rather than placed on its own.
local function ReducedTextPlacementOff()
    local src = Src()
    if not src then return true end
    return src.showReducedMaxHealth == false
        or not src.showReducedMaxHealthText
        or src.appendReducedMaxText
end

-- ── The "Apply Changes To" card ────────────────────────────────
--
-- The shared builder, with the two desc strings the Ace scopeToggle calls
-- on THIS section pass. Two, not three: the Ace applyGroup here offers
-- only Raid/Party and Custom Frame Groups, because the unit frames have no
-- absorbs surface and ApplyAbsorbs has no UF branch -- a surface with no
-- desc gets no switch. The second paragraph is the Ace note's own.
local function ScopeCard()
    return BuzzardFramesOptions:GSScopeCard({
        rp  = "Writes the Absorbs & Heal Prediction section on the base profile and on every Layout.",
        cfg = "Writes every custom frame group, whether or not the group has Absorbs & Heal Prediction overridden.",
    }, "Unit Frames always follow the Raid/Party settings here "
       .. "and don't have separate Absorb settings currently.")
end

-- ── The four pages ─────────────────────────────────────────────
--
-- Published so Panel.lua builds the route children from the same list
-- that builds the pages. Titles are the Ace group names verbatim; the
-- order is the Ace tabs' own (gsAbsorbTab 1, gsHealAbsorbTab 2,
-- gsHealPredictionTab 3, gsReducedMaxHealth 4).
BuzzardFramesOptions.GS_ABSORBS_SUBTABS = {
    { id = "absorbs",        title = "Absorbs" },
    { id = "healAbsorbs",    title = "Heal Absorbs" },
    { id = "healPrediction", title = "Heal Prediction" },
    { id = "reducedMax",     title = "Temp Reduced Max Health" },
}

local PAGES = {}

-- gsAbsorbTab. The bare Ace headers become card titles (absorbMissingHeader,
-- overshieldHeader, testAbsorbHeader); the inline groups become cards under
-- their own names, in the Ace order. absorbColorsHeader and
-- absorbTexturesHeader (both hidden = gsAbsorbsOff in Ace) are folded into
-- the cards beneath them -- a card title and a band saying almost the same
-- words would be two headings for one thing -- exactly as the Raid/Party
-- twin of this tab does.
function PAGES.absorbs()
    return {
        -- absorbMissingHeader.
        { title = "Absorbs (Missing Health)", preset = "form", fields = {
            { control = "switch", label = "Show Absorbs (Missing Health)",
              desc = "Show damage absorb shields in the missing health gap",
              id = "showAbsorbsMissingHealth",
              -- Not in the defaults table -- the shipped state is the nil
              -- that reads as true. The one restated default on this page;
              -- see the notes file.
              default = true,
              disabled = "combat",
              get = function()
                  local src = Src()
                  return src and src.showAbsorbsMissingHealth ~= false
              end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("showAbsorbsMissingHealth", v)
                  ctx.app:RefreshPage()
              end },
        }},
        -- overshieldHeader.
        { title = "Overshield (Absorbs Over Max Health)", preset = "form",
          hidden = AbsorbsOff,
          fields = {
            { control = "switch", label = "Show Overshield",
              desc = "Show absorb shields that exceed max health",
              id = "showOvershield", default = GSD("showOvershield"),
              hidden = AbsorbsOff, disabled = "combat",
              get = function() local src = Src(); return src and src.showOvershield end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("showOvershield", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Overshield Style",
              desc = "How to display absorbs exceeding max health",
              id = "overshieldStyle", default = GSD("overshieldStyle"),
              -- No Ace `sorting`, so the dialog showed the keys
              -- alphabetically.
              options = {
                  { value = "Glow",    text = "Glow"    },
                  { value = "Overlay", text = "Overlay" },
              },
              hidden = AbsorbsOff,
              disabled = OvershieldDisabled,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorbTexture("overshieldStyle", v)
                  ctx.app:RefreshPage()
              end,
              get = function() local src = Src(); return src and src.overshieldStyle end },
            { control = "dropdown", label = "Overshield Anchor",
              desc = "Position where the overshield anchors on the health bar",
              id = "overshieldAnchor", default = GSD("overshieldAnchor"),
              options = {
                  { value = "LEFT",  text = "Left" },
                  { value = "RIGHT", text = "Right (Blizzard Style)" },
              },
              hidden = function()
                  if AbsorbsOff() then return true end
                  local src = Src()
                  return src and src.overshieldStyle == "Glow"
              end,
              disabled = OvershieldDisabled,
              get = function() local src = Src(); return src and src.overshieldAnchor end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("overshieldAnchor", v)
                  ctx.app:RefreshPage()
              end },
        }},
        -- absorbColorsHeader + absorbColorGroup.
        { title = "Missing Health Absorb Colors", preset = "form",
          hidden = MissingOff,
          fields = {
            { control = "switch", label = "Use Custom Absorb Color",
              id = "useCustomAbsorbColor", default = GSD("useCustomAbsorbColor"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomAbsorbColor end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("useCustomAbsorbColor", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Absorb Overlay Color", alpha = true,
              desc = "Color and opacity of the missing health absorb overlay texture",
              id = "absorbOverlayColor",
              default = ColorDefault("absorbOverlayColor", true),
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  return not src.useCustomAbsorbColor or src.useCustomAbsorbBarTexture
              end,
              disabled = "combat",
              get = GetColor("absorbOverlayColor", true),
              set = SetColor("absorbOverlayColor", true, SetAbsorb) },
            -- Absorb seam shadow (the default-UI look). Deliberately NOT
            -- gated on the custom-color pair: the shadow rides any bar
            -- texture.
            { control = "switch", label = "Show Absorb Shadow",
              desc = "Show a shadow where the absorb shield meets the health "
                  .. "bar (Blizzard's default look). Works with custom absorb "
                  .. "textures too.",
              id = "showAbsorbShadow", default = GSD("showAbsorbShadow"),
              hidden = MissingOff, disabled = "combat",
              -- `~= false` like the master: an unseeded value reads ON.
              get = function()
                  local src = Src()
                  return src and src.showAbsorbShadow ~= false
              end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("showAbsorbShadow", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Absorb Shadow Color", alpha = true,
              desc = "Color and opacity of the absorb seam shadow",
              id = "absorbShadowColor",
              default = ColorDefault("absorbShadowColor", true),
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  if src.showAbsorbShadow == false then return true end
                  return MissingOff()
              end,
              disabled = "combat",
              get = GetColor("absorbShadowColor", true),
              set = SetColor("absorbShadowColor", true, SetAbsorb) },
            -- Last in its card in the Ace order too (order 27, after the
            -- shadow pair).
            { control = "color", label = "Absorb Color", alpha = true,
              desc = "Color and opacity of the missing health absorb base texture",
              id = "absorbBaseColor",
              default = ColorDefault("absorbBaseColor", true),
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  if not src.useCustomAbsorbColor then return true end
                  return MissingOff()
              end,
              disabled = "combat",
              get = GetColor("absorbBaseColor", true),
              set = SetColor("absorbBaseColor", true, SetAbsorb) },
        }},
        -- overshieldColorGroup.
        { title = "Overshield Absorb Colors", preset = "form",
          hidden = OvershieldOff,
          fields = {
            { control = "switch", label = "Use Custom Overshield Color",
              id = "useCustomOvershieldColor",
              default = GSD("useCustomOvershieldColor"),
              disabled = OvershieldDisabled,
              get = function() local src = Src(); return src and src.useCustomOvershieldColor end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorb("useCustomOvershieldColor", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Overshield Color", alpha = true,
              desc = "Color and opacity of the overshield absorb base texture",
              id = "overshieldBaseColor",
              default = ColorDefault("overshieldBaseColor", true),
              hidden = function()
                  local src = Src()
                  return not (src and src.useCustomOvershieldColor)
              end,
              disabled = "combat",
              get = GetColor("overshieldBaseColor", true),
              set = SetColor("overshieldBaseColor", true, SetAbsorb) },
            { control = "color", label = "Overshield Overlay Color", alpha = true,
              desc = "Color and opacity of the overshield absorb overlay texture",
              id = "overshieldOverlayColor",
              default = ColorDefault("overshieldOverlayColor", true),
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  return not src.useCustomOvershieldColor
                      or src.useCustomOvershieldBarTexture
              end,
              disabled = "combat",
              get = GetColor("overshieldOverlayColor", true),
              set = SetColor("overshieldOverlayColor", true, SetAbsorb) },
        }},
        -- absorbTexturesHeader + absorbTextureGroup.
        { title = "Missing Health Absorb Textures", preset = "form",
          hidden = MissingOff,
          fields = {
            { control = "switch", label = "Use Custom Absorb Texture",
              id = "useCustomAbsorbBarTexture",
              default = GSD("useCustomAbsorbBarTexture"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomAbsorbBarTexture end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorbTexture("useCustomAbsorbBarTexture", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Absorb Texture",
              desc = "Statusbar fill texture for the missing health absorb bar.",
              id = "absorbBarTexture", default = GSD("absorbBarTexture"),
              options = StatusbarOptions,
              hidden = NotShown("useCustomAbsorbBarTexture"),
              disabled = "combat",
              get = function() local src = Src(); return (src and src.absorbBarTexture) or "Solid" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetAbsorbTexture("absorbBarTexture", v)
              end },
        }},
        -- overshieldTextureGroup.
        { title = "Overshield Textures", preset = "form",
          hidden = OvershieldOff,
          fields = {
            { control = "switch", label = "Use Custom Overshield Texture",
              id = "useCustomOvershieldBarTexture",
              default = GSD("useCustomOvershieldBarTexture"),
              disabled = OvershieldDisabled,
              get = function() local src = Src(); return src and src.useCustomOvershieldBarTexture end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetAbsorbTexture("useCustomOvershieldBarTexture", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Overshield Texture",
              desc = "Statusbar fill texture for the overshield absorb bar.",
              id = "overshieldBarTexture", default = GSD("overshieldBarTexture"),
              options = StatusbarOptions,
              hidden = NotShown("useCustomOvershieldBarTexture"),
              disabled = OvershieldDisabled,
              get = function() local src = Src(); return (src and src.overshieldBarTexture) or "Solid" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetAbsorbTexture("overshieldBarTexture", v)
              end },
        }},
        -- testAbsorbHeader. Global debug flags, cleared on every reload,
        -- hidden while the missing-health master is off -- as in Ace.
        { title = "Test", preset = "form",
          hidden = AbsorbsOff,
          fields = {
            { control = "switch", label = "Test Absorb",
              desc = "Simulate a damage absorb on preview frames for testing. "
                  .. "Disable when done.",
              id = "testAbsorb", default = false,
              hidden = AbsorbsOff, disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testAbsorb
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testAbsorb = v
                  if bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
              end },
            { control = "dropdown", label = "Absorb Size",
              id = "testAbsorbSize", default = "medium",
              options = {
                  { value = "small",   text = "Small Absorb (10%)"    },
                  { value = "medium",  text = "Medium Absorb (40%)"   },
                  { value = "large",   text = "Large Absorb (80%)"    },
                  { value = "massive", text = "Massive Absorb (120%)" },
              },
              hidden = function()
                  local bf = BF()
                  return AbsorbsOff() or not (bf and bf.db.global.testAbsorb)
              end,
              disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and (bf.db.global.testAbsorbSize or "medium")
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testAbsorbSize = v
                  if bf.RefreshPreviewAbsorbOverlay then bf:RefreshPreviewAbsorbOverlay() end
              end },
        }},
    }
end

-- gsHealAbsorbTab. The show toggle DISABLES the style and color rather
-- than hiding them, and the plus-symbol pair hides on STYLE alone (it
-- stays visible with the show toggle off) -- every predicate is the Ace
-- one, on its own field.
function PAGES.healAbsorbs()
    return {
        -- healAbsorbHeader.
        { title = "Heal Absorb", preset = "form", fields = {
            { control = "switch", label = "Show Heal Absorb",
              desc = "Show heal absorption effects on frames",
              id = "showHealAbsorb", default = GSD("showHealAbsorb"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.showHealAbsorb end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("showHealAbsorb", v)
                  -- Turning the effect off turns its test off, so a test
                  -- left on cannot linger invisibly.
                  local bf = BF()
                  if bf and not v and bf.db.global.testHealAbsorb then
                      bf.db.global.testHealAbsorb = false
                  end
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Heal Absorb Style",
              desc = "How to display heal absorb effects.\n\n"
                  .. "|cffffffffOverlay|r: Base fill and right shadow. Use the "
                  .. "Color option to tint the base fill.\n\n"
                  .. "|cffffffffOverlay (Blizzard Style)|r: Base fill, plus "
                  .. "symbols overlay, and right shadow. Use the Color option "
                  .. "to tint the base fill.\n\n"
                  .. "|cffffffffBar|r: A thin bar anchored to the top of the "
                  .. "health bar, fills left-to-right proportional to heal "
                  .. "absorb vs max HP.\n\n"
                  .. "|cffffffffBar (Blizzard Style)|r: Same sizing and position "
                  .. "as Bar, but uses Blizzard's absorb textures with plus "
                  .. "symbols overlay.",
              id = "healAbsorbStyle", default = GSD("healAbsorbStyle"),
              -- No Ace `sorting`, so the dialog showed the keys
              -- alphabetically.
              options = {
                  { value = "Bar",             text = "Bar" },
                  { value = "BarBlizzard",     text = "Bar (Blizzard Style)" },
                  { value = "Overlay",         text = "Overlay" },
                  { value = "OverlayBlizzard", text = "Overlay (Blizzard Style)" },
              },
              disabled = CombatOrNot("showHealAbsorb"),
              get = function() local src = Src(); return src and src.healAbsorbStyle end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("healAbsorbStyle", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Color", alpha = true,
              desc = "Color and opacity of the heal absorb effect.\n\n"
                  .. "|cffffffffOverlay / Overlay (Blizzard Style)|r: Tints the "
                  .. "base fill texture.\n"
                  .. "|cffffffffBar|r: Sets the bar color.",
              id = "healAbsorbColor",
              default = ColorDefault("healAbsorbColor", true),
              disabled = CombatOrNot("showHealAbsorb"),
              get = GetColor("healAbsorbColor", true),
              set = SetColor("healAbsorbColor", true, SetHealAbsorb) },
            -- (The Ace healAbsorbSymbolSpacer -- a full-width empty
            -- description forcing a row break before this toggle -- is
            -- dropped: the flow layout makes it unnecessary.)
            { control = "switch", label = "Use Custom + Symbol Color",
              desc = "Color the plus symbols drawn on the heal absorb texture. "
                  .. "Off uses the default white. Only the two "
                  .. "|cffffffff(Blizzard Style)|r heal absorb styles draw them.",
              id = "useCustomHealAbsorbSymbolColor",
              default = GSD("useCustomHealAbsorbSymbolColor"),
              hidden = function() return not HealAbsorbBlizzStyle() end,
              disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomHealAbsorbSymbolColor end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("useCustomHealAbsorbSymbolColor", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "+ Symbol Color", alpha = true,
              desc = "Color and opacity of the plus symbols on the heal absorb "
                  .. "texture.",
              id = "healAbsorbSymbolColor",
              default = ColorDefault("healAbsorbSymbolColor", true),
              hidden = function()
                  local src = Src()
                  if not HealAbsorbBlizzStyle() then return true end
                  return not src.useCustomHealAbsorbSymbolColor
              end,
              disabled = "combat",
              get = GetColor("healAbsorbSymbolColor", true),
              set = SetColor("healAbsorbSymbolColor", true, SetHealAbsorb) },
            { control = "slider", label = "Bar Height",
              desc = "Height of the heal absorb bar in pixels",
              id = "healAbsorbBarHeight", default = GSD("healAbsorbBarHeight"),
              min = 1, max = 100, step = 1,
              hidden = function()
                  local src = Src()
                  return not (src and (src.healAbsorbStyle == "Bar"
                      or src.healAbsorbStyle == "BarBlizzard"))
              end,
              disabled = CombatOrNot("showHealAbsorb"),
              get = function() local src = Src(); return src and src.healAbsorbBarHeight end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("healAbsorbBarHeight", v)
              end },
        }},
        -- healAbsorbTextureGroup: custom fill texture for the heal absorb
        -- visual. Applies to all four healAbsorbStyle values (the base fill
        -- only -- the Blizzard variants keep their plus-symbol overlay).
        { title = "Heal Absorb Texture", preset = "form",
          hidden = NotShown("showHealAbsorb"),
          fields = {
            { control = "switch", label = "Use Custom Heal Absorb Texture",
              id = "useCustomHealAbsorbTexture",
              default = GSD("useCustomHealAbsorbTexture"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomHealAbsorbTexture end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("useCustomHealAbsorbTexture", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Heal Absorb Texture",
              desc = "Statusbar fill texture for the heal absorb visual.",
              id = "healAbsorbTexture", default = GSD("healAbsorbTexture"),
              options = StatusbarOptions,
              hidden = NotShown("useCustomHealAbsorbTexture"),
              disabled = "combat",
              get = function() local src = Src(); return (src and src.healAbsorbTexture) or "Solid" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetHealAbsorb("healAbsorbTexture", v)
              end },
        }},
        -- testHealAbsorbHeader.
        { title = "Test", preset = "form",
          hidden = NotShown("showHealAbsorb"),
          fields = {
            { control = "switch", label = "Test Heal Absorb (50%)",
              desc = "Simulate a 50% heal absorb on preview frames for testing. "
                  .. "Disable when done.",
              id = "testHealAbsorb", default = false,
              hidden = NotShown("showHealAbsorb"), disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testHealAbsorb
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testHealAbsorb = v
                  if bf.RefreshPreviewHealAbsorb then bf:RefreshPreviewHealAbsorb() end
              end },
        }},
    }
end

-- gsHealPredictionTab. The show toggle DISABLES the anchor (visible,
-- grayed) but HIDES the color, the texture pair and the test -- kept
-- exactly.
function PAGES.healPrediction()
    return {
        -- healPredictionHeader.
        { title = "Heal Prediction", preset = "form", fields = {
            { control = "switch", label = "Show Heal Prediction",
              desc = "Show incoming heal prediction on health bars",
              id = "showHealPrediction", default = GSD("showHealPrediction"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.showHealPrediction end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealPred("showHealPrediction", v)
                  local bf = BF()
                  if bf and not v and bf.db.global.testHealPrediction then
                      bf.db.global.testHealPrediction = false
                  end
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Heal Prediction Anchor",
              desc = "Position where heal prediction bar anchors.\n\n"
                  .. "|cffffffffLeft|r: Overlays the health bar from the left "
                  .. "edge, showing predicted health as a fill. Incoming heals "
                  .. "are clamped to max health.\n\n"
                  .. "|cffffffffRight (Blizzard Style)|r: Extends from the right "
                  .. "edge of the current health fill into the missing health "
                  .. "area.",
              id = "healPredictionAnchor", default = GSD("healPredictionAnchor"),
              options = {
                  { value = "LEFT",  text = "Left" },
                  { value = "RIGHT", text = "Right (Blizzard Style)" },
              },
              disabled = CombatOrNot("showHealPrediction"),
              get = function() local src = Src(); return src and src.healPredictionAnchor end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealPred("healPredictionAnchor", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Heal Prediction Color", alpha = true,
              desc = "Color and opacity of the heal prediction bar",
              id = "healPredictionColor",
              default = ColorDefault("healPredictionColor", true),
              hidden = NotShown("showHealPrediction"),
              disabled = "combat",
              get = GetColor("healPredictionColor", true),
              set = SetColor("healPredictionColor", true, SetHealPred) },
        }},
        -- healPredTextureHeader.
        { title = "Heal Prediction Texture", preset = "form",
          hidden = NotShown("showHealPrediction"),
          fields = {
            { control = "switch", label = "Use Custom Texture",
              id = "useCustomHealPredictionTexture",
              default = GSD("useCustomHealPredictionTexture"),
              hidden = NotShown("showHealPrediction"), disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomHealPredictionTexture end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetHealPred("useCustomHealPredictionTexture", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Heal Prediction Texture",
              desc = "Statusbar fill texture for the heal prediction bar.",
              id = "healPredictionTexture", default = GSD("healPredictionTexture"),
              options = StatusbarOptions,
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  return not src.showHealPrediction
                      or not src.useCustomHealPredictionTexture
              end,
              disabled = "combat",
              get = function() local src = Src(); return (src and src.healPredictionTexture) or "Solid" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetHealPred("healPredictionTexture", v)
              end },
        }},
        -- testHealPredHeader.
        { title = "Test", preset = "form",
          hidden = NotShown("showHealPrediction"),
          fields = {
            { control = "switch", label = "Test Heal Prediction",
              desc = "Simulate a 10% incoming heal on preview frames for "
                  .. "testing. Disable when done.",
              id = "testHealPrediction", default = false,
              hidden = NotShown("showHealPrediction"), disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testHealPrediction
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testHealPrediction = v
                  if bf.RefreshPreviewHealPrediction then bf:RefreshPreviewHealPrediction() end
              end },
        }},
    }
end

-- gsReducedMaxHealth. The master reads `~= false`; everything below it
-- hides when it is explicitly off. The Ace Position inline group plus the
-- two font fields that followed it at tab level with the same visibility
-- share one card here -- same order, same predicates.
function PAGES.reducedMax()
    return {
        -- reducedMaxHeader; reducedMaxDesc is the card's first (full-width)
        -- field, above the master switch -- where the Ace page drew it.
        { title = "Temporary Reduced Max Health", preset = "form", fields = {
            { control = "note", wide = true,
              text = "Some boss abilities temporarily reduce a unit's maximum "
                  .. "health. When active, a gray bar fills from the right side "
                  .. "of the health bar to indicate the unavailable portion. "
                  .. "This mirrors the default Blizzard raid frame behavior." },
            { control = "switch", label = "Show Reduced Max Health Bar",
              desc = "Show a gray overlay on the health bar when a unit's "
                  .. "maximum health is temporarily reduced.",
              id = "showReducedMaxHealth", default = GSD("showReducedMaxHealth"),
              disabled = "combat",
              get = function()
                  local src = Src()
                  return src and src.showReducedMaxHealth ~= false
              end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetReducedMax("showReducedMaxHealth", v)
                  local bf = BF()
                  if bf and not v and bf.db.global.testReducedMaxHealth then
                      bf.db.global.testReducedMaxHealth = false
                  end
                  ctx.app:RefreshPage()
              end },
        }},
        -- reducedMaxBarTextureHeader.
        { title = "Reduced Max Health Bar Texture", preset = "form",
          hidden = ReducedOff,
          fields = {
            { control = "switch", label = "Use Custom Texture",
              id = "useCustomReducedMaxTexture",
              default = GSD("useCustomReducedMaxTexture"),
              hidden = ReducedOff, disabled = "combat",
              get = function() local src = Src(); return src and src.useCustomReducedMaxTexture end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetReducedMax("useCustomReducedMaxTexture", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Bar Texture",
              desc = "Statusbar fill texture for the reduced max health bar.",
              id = "reducedMaxHealthTexture",
              default = GSD("reducedMaxHealthTexture"),
              options = StatusbarOptions,
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  return src.showReducedMaxHealth == false
                      or not src.useCustomReducedMaxTexture
              end,
              disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthTexture) or "Solid" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMax("reducedMaxHealthTexture", v)
              end },
            { control = "color", label = "Bar Color", alpha = true,
              desc = "Color of the reduced max health overlay bar.",
              id = "reducedMaxHealthColor",
              default = ColorDefault("reducedMaxHealthColor", true),
              hidden = function()
                  local src = Src()
                  if not src then return true end
                  return src.showReducedMaxHealth == false
                      or not src.useCustomReducedMaxTexture
              end,
              disabled = "combat",
              -- The Ace get's `c.a or 0.8` kept: a legacy color saved
              -- without alpha shows the shipped 0.8 rather than opaque.
              get = function()
                  local src = Src()
                  local c   = src and src.reducedMaxHealthColor
                  if type(c) ~= "table" then return nil end
                  return { c.r, c.g, c.b, c.a or 0.8 }
              end,
              set = SetColor("reducedMaxHealthColor", true, SetReducedMax) },
        }},
        -- reducedMaxTextHeader.
        { title = "Reduced Max Health % Text", preset = "form",
          hidden = ReducedOff,
          fields = {
            { control = "switch", label = "Show Reduced Max Health % Text",
              desc = "Show a separate text element displaying the remaining max "
                  .. "health percentage when temporarily reduced.",
              id = "showReducedMaxHealthText",
              default = GSD("showReducedMaxHealthText"),
              hidden = ReducedOff, disabled = "combat",
              get = function() local src = Src(); return src and src.showReducedMaxHealthText == true end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxBind("showReducedMaxHealthText", v)
                  ctx.app:RefreshPage()
              end },
            { control = "color", label = "Text Color",
              id = "reducedMaxHealthTextColor",
              default = ColorDefault("reducedMaxHealthTextColor", false),
              hidden = ReducedTextOff, disabled = "combat",
              get = GetColor("reducedMaxHealthTextColor", false),
              set = SetColor("reducedMaxHealthTextColor", false, SetReducedMaxLook) },
        }},
        -- appendReducedMaxGroup.
        { title = "Append", preset = "form",
          hidden = ReducedTextOff,
          fields = {
            { control = "switch", label = "Append Text",
              desc = "Append the reduced max health percentage to an existing "
                  .. "text element instead of showing it separately.",
              id = "appendReducedMaxText", default = GSD("appendReducedMaxText"),
              disabled = "combat",
              get = function() local src = Src(); return src and src.appendReducedMaxText == true end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxBind("appendReducedMaxText", v)
                  ctx.app:RefreshPage()
              end },
            { control = "dropdown", label = "Append To",
              desc = "Choose which text element to append the reduced max health "
                  .. "percentage to.",
              id = "appendReducedMaxTarget",
              default = GSD("appendReducedMaxTarget"),
              options = {
                  { value = "health", text = "Health Text" },
                  { value = "name",   text = "Name" },
              },
              hidden = NotShown("appendReducedMaxText"),
              disabled = "combat",
              get = function() local src = Src(); return (src and src.appendReducedMaxTarget) or "health" end,
              set = function(_, ctx, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxBind("appendReducedMaxTarget", v)
                  ctx.app:RefreshPage()
              end },
        }},
        -- reducedMaxHealthTextPositionGroup -- the Ace Position inline group,
        -- plus the Font Size and Font Border fields that followed it at tab
        -- level with the same visibility -- one card, same order.
        { title = "Position", preset = "form",
          hidden = ReducedTextPlacementOff,
          fields = {
            { control = "dropdown", label = "Anchor",
              id = "reducedMaxHealthTextPosition",
              default = GSD("reducedMaxHealthTextPosition"),
              -- No Ace `sorting`, so the dialog showed the keys
              -- alphabetically.
              options = {
                  { value = "BOTTOM",      text = "Bottom" },
                  { value = "BOTTOMLEFT",  text = "Bottom Left" },
                  { value = "BOTTOMRIGHT", text = "Bottom Right" },
                  { value = "CENTER",      text = "Center" },
                  { value = "LEFT",        text = "Left" },
                  { value = "RIGHT",       text = "Right" },
                  { value = "TOP",         text = "Top" },
                  { value = "TOPLEFT",     text = "Top Left" },
                  { value = "TOPRIGHT",    text = "Top Right" },
              },
              disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthTextPosition) or "BOTTOMRIGHT" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxLayout("reducedMaxHealthTextPosition", v)
              end },
            { control = "slider", label = "X Offset",
              id = "reducedMaxHealthTextX",
              default = GSD("reducedMaxHealthTextX"),
              min = -20, max = 20, step = 1,
              disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthTextX) or -2 end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxLayout("reducedMaxHealthTextX", v)
              end },
            { control = "slider", label = "Y Offset",
              id = "reducedMaxHealthTextY",
              default = GSD("reducedMaxHealthTextY"),
              min = -20, max = 20, step = 1,
              disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthTextY) or 2 end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxLayout("reducedMaxHealthTextY", v)
              end },
            { control = "slider", label = "Font Size",
              id = "reducedMaxHealthFontSize",
              default = GSD("reducedMaxHealthFontSize"),
              min = 6, max = 24, step = 1,
              hidden = ReducedTextPlacementOff, disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthFontSize) or 9 end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxLayout("reducedMaxHealthFontSize", v)
              end },
            { control = "dropdown", label = "Font Border",
              id = "reducedMaxHealthFontBorder",
              default = GSD("reducedMaxHealthFontBorder"),
              options = {
                  { value = "",             text = "None" },
                  { value = "OUTLINE",      text = "Outline" },
                  { value = "THICKOUTLINE", text = "Thick Outline" },
              },
              hidden = ReducedTextPlacementOff, disabled = "combat",
              get = function() local src = Src(); return (src and src.reducedMaxHealthFontBorder) or "" end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  SetReducedMaxLayout("reducedMaxHealthFontBorder", v)
              end },
        }},
        -- testHeader.
        { title = "Test", preset = "form",
          hidden = ReducedOff,
          fields = {
            { control = "switch", label = "Test Reduced Max Health (50%)",
              desc = "Simulate a 50% max health reduction on preview frames for "
                  .. "testing.",
              id = "testReducedMaxHealth", default = false,
              hidden = ReducedOff, disabled = "combat",
              get = function()
                  local bf = BF()
                  return bf and bf.db.global.testReducedMaxHealth == true
              end,
              set = function(_, _, v)
                  if InCombatLockdown() then return end
                  local bf = BF()
                  if not bf then return end
                  bf.db.global.testReducedMaxHealth = v
                  if bf.RefreshPreviewReducedMaxHealth then bf:RefreshPreviewReducedMaxHealth() end
              end },
        }},
    }
end

-- ── The page ───────────────────────────────────────────────────
--
-- The "Apply Changes To" card comes FIRST on every subtab. The Ace dialog
-- drew it once, above the tab strip, because it sat at the section level
-- and the four tabs were its siblings; the panel's tab strip has no room
-- above it for a three-row card, so the same card opens each subtab
-- instead -- same information, same place on screen.
--
-- No `db` and no `defaults`: nothing on these pages is bound. Global
-- Styles owns no storage, so every field is get/set with its own `id` and
-- `default` -- which is what keeps Undo and Reset working.

-- Mark a group as pinned without editing the builder that made it.
local function Pinned(g)
    if type(g) == "table" then g.pinned = true end
    return g
end

-- ── The section as ONE page ────────────────────────────────────
--
-- The scope strip belongs to the SECTION, not to the subtab on screen --
-- which is where the Ace dialog put it: above the tab strip, stated once.
-- As route subtabs each page could only draw it inside itself, so the same
-- strip appeared under the tabs four times over.
--
-- So the section is one page with an IN-PAGE subtab strip: the strip card
-- above it, then a `subtabs` group carrying what each tab draws. The same
-- shape a buff container page uses for Container Settings / Conditions,
-- and the reason the library has `subtabs` at all.
--
-- Each tab's `groups` is a FUNCTION, so a tab is built when it is selected
-- rather than all of them on every render -- and rebuilt when the page is,
-- which is what the per-route pages got for free.
function BuzzardFramesOptions:GlobalStylesAbsorbsPage()
    local tabs = {}
    for _, st in ipairs(BuzzardFramesOptions.GS_ABSORBS_SUBTABS) do
        tabs[#tabs + 1] = {
            id = st.id, title = st.title,
            groups = function()
                local build = PAGES[st.id]
                return build and build() or {}
            end,
        }
    end
    return { groups = {
        -- PINNED: the scope strip and the strip of subtabs stay put while
        -- the tab's own cards scroll under them. They are the terms the page
        -- is edited under -- which surfaces a write lands on, and which tab
        -- is on screen -- and scrolling those away leaves the reader
        -- adjusting settings whose terms are somewhere above.
        Pinned(ScopeCard()),
        { subtabKey = "gsAbsorbs", subtabs = tabs, pinned = true },
    }}
end
