-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesHealth.lua
-- The Global Styles > Health & Power Bars page, in BuzzardPanel.
--
-- The panel equivalent of the `healthBars` child of BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, in the same order,
-- with the same storage routing and the same side effects. Both panels
-- exist while the Ace one is being retired, and an edit in either lands in
-- exactly the same place, so they cannot drift apart in what they STORE.
--
-- Storage: NONE of its own. Every field here is a WRITE-THROUGH into the
-- keys the Raid/Party frames (rpDB.profile.healthPower plus every layout
-- flat), the custom frame groups (every group's flat.healthPower) and the
-- unit frames (ufDB.profile.ouf*/playerFrame*) already read. The fan-out,
-- the read side and the per-surface refresh chains all live in
-- Pages_GlobalStylesShared.lua and are reached through
-- BuzzardFramesOptions:GS() -- one table whose entries are the helpers the
-- Ace widgets called, under the same names. That shared module is what
-- keeps the two panels in step: neither writes a db table directly.
--
-- Which surfaces a change reaches is the "Apply Changes To" card at the
-- top (db.global.globalStyles, a UI preference that survives profile
-- switches). The read side displays the FIRST surface in scope.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- No accessor for BuzzardFrames here: every read and write this page
-- makes goes through the shared fan-out, which resolves the addon itself
-- once the panel is open. Nothing at file scope reads it either way.

-- ── Shared option lists ────────────────────────────────────────

-- The statusbar textures LibSharedMedia knows, alphabetical -- the same
-- list the Ace page's LSM30_Statusbar widget offered, previews and all:
-- each entry carries its `texture`, which the dropdown draws behind the
-- name in the menu and on the control once it is picked.
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

-- The Ace `values` tables, in their own `sorting` order. The fill and the
-- background list the SAME three modes in DIFFERENT orders (the Ace page
-- sorts the fill class-first and the background static-first, each putting
-- its own default at the top) -- kept exactly as found.
local HEALTH_MODE_OPTIONS = {
    { value = "class",    text = "Use Class Colors" },
    { value = "gradient", text = "Use Color Gradient (Health Percent)" },
    { value = "static",   text = "Use Static Color" },
}
local BG_MODE_OPTIONS = {
    { value = "static",   text = "Use Static Color" },
    { value = "gradient", text = "Use Color Gradient (Health Percent)" },
    { value = "class",    text = "Use Class Colors" },
}

-- ── Value-shape adapters ───────────────────────────────────────

-- A fraction stored 0-1, shown 0-100. The Ace page's isPercent sliders
-- keep their storage shape (0.05 steps on a 0-1 value); the panel's slider
-- shows integers in its value box, so the control works in percent units
-- and these convert at the edge. `default` is in the same percent units,
-- which is what keeps undo and reset working without a bind.
local function ToPct(v)
    if type(v) ~= "number" then return nil end
    return math.floor(v * 100 + 0.5)
end

-- The shipped Raid/Party default for a healthPower key, in percent units.
local function PctDefault(key)
    return ToPct(BuzzardFramesOptions:GSDefault("healthPower", key))
end

-- A color arrives from the control (and from an undo) as an array, and
-- from a Reset as the defaults table's named copy, so both are read.
local function RGB(v)
    if type(v) ~= "table" then return nil end
    local r = v.r; if r == nil then r = v[1] end
    local g = v.g; if g == nil then g = v[2] end
    local b = v.b; if b == nil then b = v[3] end
    return r, g, b
end

-- The shipped default for a healthPower color key, in the array shape the
-- color control speaks.
local function ColorDefault(key)
    local c = BuzzardFramesOptions:GSDefault("healthPower", key)
    if type(c) ~= "table" then return nil end
    return { c.r, c.g, c.b }
end

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:GlobalStylesHealthPage()
    -- The fan-out, resolved once per page build (the route rebuilds the
    -- page each time it is shown, so this is never stale). Without the
    -- addon there is nothing to write through to and nothing to read.
    local GS = self:GS()
    if not GS then return { groups = {} } end

    -- The three modes, as the Ace setters spelled them. RP/CFG store the
    -- fill mode as two booleans and the background mode as two others;
    -- the unit frames store a string enum for each. Both halves of each
    -- pair are written together, exactly as the Ace setters did.
    local function SetHealthMode(v)
        if InCombatLockdown() then return end
        local useCustom   = (v ~= "class")
        local useGradient = (v == "gradient")
        GS.Apply(false, false,
            function()
                GS.WriteRP("useCustomHealthColor", useCustom)
                GS.WriteRP("useHealthGradient",    useGradient)
            end,
            function()
                GS.WriteCFG("useCustomHealthColor", useCustom)
                GS.WriteCFG("useHealthGradient",    useGradient)
            end,
            function()
                local pf = GS.ufProfile()
                if not pf then return end
                pf.playerFrameHealthColorMode  = v
                pf.globalPlayerHealthColorMode = v
                pf.globalNpcHealthColorMode    = GS.UF_NPC_MODE[v] or "classification"
                -- The pet frame has no color mode of its own. It is left
                -- alone here on purpose: with "Match Player Color" on (the
                -- default) it already follows the player mode written
                -- above, and forcing that toggle back on would silently
                -- destroy the setting of anyone who deliberately turned it
                -- off. Their pet keeps using the static Health Color,
                -- which this page also writes.
            end)
    end

    -- Static mode hides the pointer at the Colors section: it reads
    -- nothing from there, so the link would send the reader somewhere
    -- that cannot affect what they are looking at.
    local function NotStatic() return GS.readMode() ~= "static" end
    local function IsStatic()  return GS.readMode() == "static" end

    local function NoBgCustom()   return not GS.readBgUseCustom() end
    local function BgNotGradient()
        return NoBgCustom() or GS.readBgMode() ~= "gradient"
    end

    return {
        groups = {
            -- order 0.5. The three tooltip strings are the ones this
            -- page's own scopeToggle calls passed.
            self:GSScopeCard({
                rp  = "Writes the Health & Power Bars section on the base profile and on every Layout.",
                cfg = "Writes every custom frame group, whether or not the group has Health & Power Bars overridden.",
                uf  = "Writes the player, target, focus, pet, target-of-target and boss frames.",
            }),

            -- ── texturesGroup (order 1) ──────────────────────
            { title = "Textures", preset = "form", fields = {
                { control = "switch", label = "Use Custom Health Texture",
                  id = "useCustomHealthBarTexture",
                  default = self:GSDefault("healthPower", "useCustomHealthBarTexture"),
                  disabled = "combat",
                  get = function() return GS.readUseTexture() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      GS.Apply(true, true,
                          function() GS.WriteRP("useCustomHealthBarTexture", v) end,
                          function() GS.WriteCFG("useCustomHealthBarTexture", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufUseCustomHealthBarTexture = v end
                          end)
                      ctx.app:RefreshPage()
                  end },

                { control = "dropdown", label = "Health Bar Texture",
                  desc = "Texture for the health bar fill.",
                  id = "healthBarTexture",
                  default = self:GSDefault("healthPower", "healthBarTexture"),
                  options = StatusbarOptions, disabled = "combat",
                  hidden = function() return not GS.readUseTexture() end,
                  get = function() return GS.readTexture() end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      GS.Apply(true, true,
                          function() GS.WriteRP("healthBarTexture", v) end,
                          function() GS.WriteCFG("healthBarTexture", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufHealthBarTexture = v end
                          end)
                  end },

                -- powerTextureBreak (order 3) was a zero-height full-width
                -- description, there only to force AceGUI's Flow layout
                -- onto a new row. The panel's form preset lays rows out
                -- itself, so the spacer is dropped.

                { control = "switch", label = "Use Custom Power Texture",
                  id = "useCustomPowerBarTexture",
                  default = self:GSDefault("healthPower", "useCustomPowerBarTexture"),
                  disabled = "combat",
                  get = function() return GS.readUsePowerTexture() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      GS.ApplyPower(true, GS.RefreshUFPowerTexture,
                          function() GS.WriteRP("useCustomPowerBarTexture", v) end,
                          function() GS.WriteCFG("useCustomPowerBarTexture", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufUseCustomPowerBarTexture = v end
                          end)
                      ctx.app:RefreshPage()
                  end },

                { control = "dropdown", label = "Power Bar Texture",
                  desc = "Texture for the power bar fill.",
                  id = "powerBarTexture",
                  default = self:GSDefault("healthPower", "powerBarTexture"),
                  options = StatusbarOptions, disabled = "combat",
                  hidden = function() return not GS.readUsePowerTexture() end,
                  get = function() return GS.readPowerTexture() end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      GS.ApplyPower(true, GS.RefreshUFPowerTexture,
                          function() GS.WriteRP("powerBarTexture", v) end,
                          function() GS.WriteCFG("powerBarTexture", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufPowerBarTexture = v end
                          end)
                  end },
            }},

            -- ── healthColorGroup (order 2) ───────────────────
            { title = "Health Bar Color", preset = "form", fields = {
                { control = "dropdown", label = "Color Mode",
                  options = HEALTH_MODE_OPTIONS,
                  -- A derived value: RP/CFG store it as two booleans, so
                  -- the default is the pair of shipped defaults read back
                  -- through the same rule readMode() uses (both false =
                  -- "class").
                  id = "healthColorMode",
                  default = (function()
                      if not self:GSDefault("healthPower", "useCustomHealthColor") then
                          return "class"
                      end
                      if self:GSDefault("healthPower", "useHealthGradient") then
                          return "gradient"
                      end
                      return "static"
                  end)(),
                  disabled = "combat",
                  get = function() return GS.readMode() end,
                  set = function(_, ctx, v)
                      SetHealthMode(v)
                      -- Every other field in this card is gated on the
                      -- mode, so the page is read and laid out again.
                      ctx.app:RefreshPage()
                  end },

                { control = "color", label = "Health Color",
                  id = "healthColor", default = ColorDefault("healthColor"),
                  disabled = "combat",
                  hidden = NotStatic,
                  get = function()
                      local c = GS.readHealthColor() or { r = 0.24, g = 0.78, b = 0.24 }
                      return { c.r, c.g, c.b }
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local r, g, b = RGB(v)
                      if r == nil then return end
                      local col = { r = r, g = g, b = b }
                      GS.Apply(false, false,
                          function() GS.WriteRP("healthColor", col) end,
                          function() GS.WriteCFG("healthColor", col) end,
                          function()
                              local pf = GS.ufProfile()
                              if not pf then return end
                              pf.playerFrameHealthColor = { r = r, g = g, b = b }
                              pf.globalHealthColor      = { r = r, g = g, b = b }
                              pf.globalNpcHealthColor   = { r = r, g = g, b = b }
                              if type(pf.pet) ~= "table" then pf.pet = {} end
                              pf.pet.healthColor = { r = r, g = g, b = b }
                          end)
                  end },

                { control = "slider", label = "Health Bar Opacity",
                  desc = "Opacity of the health bar fill.",
                  min = 0, max = 100, step = 5,
                  id = "healthBarOpacity",
                  -- No entry in the defaults table; the Ace getter's own
                  -- fallback (1.0), in percent units.
                  default = PctDefault("healthBarOpacity") or 100,
                  disabled = "combat",
                  -- In gradient mode the alpha comes from the per-stop
                  -- alpha of the gradient color pickers in the Colors
                  -- section instead.
                  hidden = function() return GS.readMode() == "gradient" end,
                  get = function() return ToPct(GS.readOpacity()) end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      -- Raid/Party treats opacity as a color change
                      -- (hpColors bucket); the unit frames relayout for it.
                      local val = v / 100
                      GS.Apply(false, true,
                          function() GS.WriteRP("healthBarOpacity", val) end,
                          function() GS.WriteCFG("healthBarOpacity", val) end,
                          function()
                              local pf = GS.ufProfile()
                              if not pf then return end
                              pf.oufHealthBarOpacity         = val
                              pf.playerFrameHealthBarOpacity = val
                          end)
                  end },

                -- colorsNote (order 90) + openColorsBtn (order 91). Only
                -- class and gradient mode read anything from the Colors
                -- section.
                { control = "note", wide = true, hidden = IsStatic,
                  text = "Class Colors and Health Gradient Colors can be "
                      .. "customized in the global Colors section:" },
                -- The Ace func deferred through C_Timer.After(0, ...) to
                -- work around an AceConfigDialog reentrancy problem when
                -- an execute handler re-selected a group; a route change
                -- has no such constraint.
                { control = "button", text = "Colors", hidden = IsStatic,
                  onClick = function(_, ctx)
                      ctx.app:Navigate("globalStyles", "colors")
                  end },
            }},

            -- ── backgroundGroup (order 3) ────────────────────
            { title = "Health Bar Background Colors", preset = "form", fields = {
                { control = "switch", label = "Use Custom Background Color",
                  id = "useCustomBackgroundColor",
                  default = self:GSDefault("healthPower", "useCustomBackgroundColor"),
                  disabled = "combat",
                  get = function() return GS.readBgUseCustom() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      -- Every background setting needs a real layout pass
                      -- on both surfaces: the background is a drawn
                      -- region, not a bar color re-evaluation.
                      GS.Apply(true, true,
                          function() GS.WriteRP("useCustomBackgroundColor", v) end,
                          function() GS.WriteCFG("useCustomBackgroundColor", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufUseCustomBackgroundColor = v end
                          end)
                      ctx.app:RefreshPage()
                  end },

                { control = "dropdown", label = "Color Mode",
                  options = BG_MODE_OPTIONS,
                  id = "bgColorMode",
                  -- Derived from the same two shipped booleans readBgMode
                  -- reads (neither set = "static").
                  default = (function()
                      if self:GSDefault("healthPower", "useBgGradient") then return "gradient" end
                      if self:GSDefault("healthPower", "useBgClass")    then return "class"    end
                      return "static"
                  end)(),
                  disabled = "combat",
                  hidden = NoBgCustom,
                  get = function() return GS.readBgMode() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      -- RP/CFG: two booleans, neither set means static.
                      -- UF: string enum.
                      local useGradient = (v == "gradient")
                      local useClass    = (v == "class")
                      GS.Apply(true, true,
                          function()
                              GS.WriteRP("useBgGradient", useGradient)
                              GS.WriteRP("useBgClass",    useClass)
                          end,
                          function()
                              GS.WriteCFG("useBgGradient", useGradient)
                              GS.WriteCFG("useBgClass",    useClass)
                          end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufBackgroundColorMode = v end
                          end)
                      ctx.app:RefreshPage()
                  end },

                { control = "color",
                  -- In class mode this color no longer applies to players
                  -- (they take their class color), only to units that have
                  -- no class. The raid and custom frames are player-only,
                  -- so the control is meaningful in class mode purely as
                  -- the unit frames' NPC background -- and is therefore
                  -- only offered when Unit Frames is actually in scope.
                  label = function()
                      if GS.readBgMode() == "class" then return "NPC Background Color" end
                      return "Background Color"
                  end,
                  desc = function()
                      if GS.readBgMode() == "class" then
                          return "Background color for non-player units, which have no class color."
                      end
                      return "Static background color for health bars."
                  end,
                  id = "backgroundColor", default = ColorDefault("backgroundColor"),
                  disabled = "combat",
                  hidden = function()
                      if not GS.readBgUseCustom() then return true end
                      local mode = GS.readBgMode()
                      if mode == "gradient" then return true end
                      if mode == "class" and not GS.wantUF() then return true end
                      return false
                  end,
                  get = function()
                      local c = GS.readBgColor() or { r = 0, g = 0, b = 0 }
                      return { c.r, c.g, c.b }
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local r, g, b = RGB(v)
                      if r == nil then return end
                      local col = { r = r, g = g, b = b }
                      GS.Apply(true, true,
                          function() GS.WriteRP("backgroundColor", col) end,
                          function() GS.WriteCFG("backgroundColor", col) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufBackgroundColor = { r = r, g = g, b = b } end
                          end)
                  end },

                { control = "slider", label = "Background Opacity",
                  desc = "Opacity of the health bar background.",
                  min = 0, max = 100, step = 5,
                  id = "backgroundAlpha", default = PctDefault("backgroundAlpha"),
                  disabled = "combat",
                  hidden = function()
                      if not GS.readBgUseCustom() then return true end
                      -- In gradient mode the alpha comes from the per-stop
                      -- alpha of the background gradient pickers in the
                      -- Colors section.
                      return GS.readBgMode() == "gradient"
                  end,
                  get = function() return ToPct(GS.readBgAlpha()) end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local val = v / 100
                      GS.Apply(true, true,
                          function() GS.WriteRP("backgroundAlpha", val) end,
                          function() GS.WriteCFG("backgroundAlpha", val) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufBackgroundAlpha = val end
                          end)
                  end },

                { control = "slider", label = "Background Darkening",
                  desc = "Darkens the class-colored background. 0% = full "
                      .. "class color; higher values multiply the color "
                      .. "toward black for a dimmer backdrop behind the fill.",
                  min = 0, max = 80, step = 5,
                  id = "bgClassDarken", default = PctDefault("bgClassDarken"),
                  disabled = "combat",
                  hidden = function()
                      return not GS.readBgUseCustom() or GS.readBgMode() ~= "class"
                  end,
                  get = function() return ToPct(GS.readBgDarken()) end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local val = v / 100
                      GS.Apply(true, true,
                          function() GS.WriteRP("bgClassDarken", val) end,
                          function() GS.WriteCFG("bgClassDarken", val) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufBgClassDarken = val end
                          end)
                  end },

                -- gradientNote (order 8) + openBgColorsBtn (order 9).
                { control = "note", wide = true, hidden = BgNotGradient,
                  text = "Background gradient colors can be customized in "
                      .. "the global Colors section:" },
                { control = "button", text = "Colors", hidden = BgNotGradient,
                  onClick = function(_, ctx)
                      ctx.app:Navigate("globalStyles", "colors")
                  end },
            }},

            -- ── powerBackgroundGroup (order 4) ───────────────
            -- Unlike the health background, the power background has no
            -- class or gradient mode on any surface -- just a static color
            -- and an opacity.
            { title = "Power Bar Background Colors", preset = "form", fields = {
                { control = "switch", label = "Use Custom Background Color",
                  id = "useCustomPowerBarBgColor",
                  default = self:GSDefault("healthPower", "useCustomPowerBarBgColor"),
                  disabled = "combat",
                  get = function() return GS.readUsePowerBg() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      GS.ApplyPower(false, GS.RefreshUFPowerBg,
                          function() GS.WriteRP("useCustomPowerBarBgColor", v) end,
                          function() GS.WriteCFG("useCustomPowerBarBgColor", v) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufUseCustomPowerBarBgColor = v end
                          end)
                      ctx.app:RefreshPage()
                  end },

                { control = "color", label = "Background Color",
                  desc = "Color of the power bar background.",
                  id = "powerBarBgColor", default = ColorDefault("powerBarBgColor"),
                  disabled = "combat",
                  hidden = function() return not GS.readUsePowerBg() end,
                  get = function()
                      local c = GS.readPowerBgColor() or { r = 0.08, g = 0.08, b = 0.08 }
                      return { c.r, c.g, c.b }
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local r, g, b = RGB(v)
                      if r == nil then return end
                      GS.ApplyPower(false, GS.RefreshUFPowerBg,
                          function()
                              -- The raid key carries a vestigial `a` field
                              -- that nothing renders (opacity comes from
                              -- powerBarBgOpacity). Preserved rather than
                              -- dropped, so the shape matches what the
                              -- Health & Power Bars page's setter writes.
                              local gp = GS.rpGlobal()
                              local prev = gp and gp.powerBarBgColor
                              GS.WriteRP("powerBarBgColor",
                                  { r = r, g = g, b = b, a = (prev and prev.a) or 1.0 })
                          end,
                          function()
                              local gp = GS.rpGlobal()
                              local prev = gp and gp.powerBarBgColor
                              GS.WriteCFG("powerBarBgColor",
                                  { r = r, g = g, b = b, a = (prev and prev.a) or 1.0 })
                          end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufPowerBarBgColor = { r = r, g = g, b = b } end
                          end)
                  end },

                { control = "slider", label = "Background Opacity",
                  desc = "Opacity of the power bar background. On the unit "
                      .. "frames this multiplies with the Power Bar Opacity "
                      .. "slider, because their background sits inside the "
                      .. "bar rather than behind it.",
                  min = 0, max = 100, step = 5,
                  id = "powerBarBgOpacity", default = PctDefault("powerBarBgOpacity"),
                  disabled = "combat",
                  hidden = function() return not GS.readUsePowerBg() end,
                  get = function() return ToPct(GS.readPowerBgOpacity()) end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local val = v / 100
                      GS.ApplyPower(false, GS.RefreshUFPowerBg,
                          function() GS.WriteRP("powerBarBgOpacity", val) end,
                          function() GS.WriteCFG("powerBarBgOpacity", val) end,
                          function()
                              local pf = GS.ufProfile()
                              if pf then pf.oufPowerBarBgAlpha = val end
                          end)
                  end },
            }},
        },
    }
end
