-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesBorders.lua
-- The Global Styles > Borders page, in BuzzardPanel.
--
-- The panel equivalent of the `borders` child of BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, in the same order,
-- with the same storage routing and the same side effects. Both panels
-- exist while the Ace one is being retired, and an edit in either lands in
-- exactly the same place, so they cannot drift apart in what they STORE.
--
-- Storage: NONE of its own. The frame-border fields are WRITE-THROUGHS
-- into the keys the Raid/Party frames (rpDB.profile.borders plus every
-- layout flat), the custom frame groups (every group's flat.borders) and
-- the unit frames (the three per-bar <bar>Border* keys plus the rounded
-- ring's frameBorderColor / oufBorderMode) already read. The fan-out, the
-- read side and the per-surface refresh chains live in
-- Pages_GlobalStylesShared.lua and are reached through
-- BuzzardFramesOptions:GS(). That shared module is what keeps the two
-- panels in step: neither writes a db table directly.
--
-- The one exception is the Unit Frames card: bar separators are a
-- unit-frame-only feature with no Raid/Party or custom-group analogue, so
-- those two fields write ufDB.profile directly and refresh the unit frames
-- only -- exactly as the Ace widgets did, and outside the Apply Changes To
-- scope for the same reason.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- Nothing at file scope reads the addon; resolved inside the builders and
-- the setters, after the panel is open.
local function BF() return _G.BuzzardFrames end

-- The shipped default for a `borders` section key, in the array shape the
-- color control speaks.
local function BorderColorDefault(key)
    local c = BuzzardFramesOptions:GSDefault("borders", key)
    if type(c) ~= "table" then return nil end
    return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
end

-- The shipped default for a unit-frame profile key. The Raid/Party
-- defaults table has no answer for a UF-only setting, so these two read
-- BuzzardFrames' own unit frame defaults -- the single source, as
-- everywhere else.
local function UFDefault(key)
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    d = d and d.profile
    return d and d[key]
end

-- A color arrives from the control (and from an undo) as an array, and
-- from a Reset as the defaults table's named copy, so both are read.
local function RGBA(v)
    if type(v) ~= "table" then return nil end
    local r = v.r; if r == nil then r = v[1] end
    local g = v.g; if g == nil then g = v[2] end
    local b = v.b; if b == nil then b = v[3] end
    local a = v.a; if a == nil then a = v[4] end
    if a == nil then a = 1 end
    return r, g, b, a
end

local SEPARATOR_STYLE_OPTIONS = {
    { value = "rings", text = "Full Borders (per bar)" },
    { value = "lines", text = "Divider Lines" },
}

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:GlobalStylesBordersPage()
    local GS = self:GS()
    if not GS then return { groups = {} } end

    -- Enable Border off HIDES the dependent settings (owner report:
    -- graying them out reads as a bug).
    local function NoBorder() return not GS.readBorderEnable() end

    -- Shape and weight, over the one `borderStyle` key. This page has no
    -- Blizzard-Style option: the frame border is drawn by this addon
    -- either way, so the only shapes are Square and Rounded, and the Ace
    -- list's third entry (Rounded (Thick)) is the weight strip.
    local borderStyleField, borderWeightField = self:BorderStyleFields({
        id = "borderStyle",
        default = self:GSDefault("borders", "borderStyle"),
        desc = "Square draws a flat colored border at the chosen thickness. "
            .. "Rounded draws a rounded frame ring; Thick is the same ring "
            .. "slightly heavier.",
        options = {
            { value = "square",  text = "Square"  },
            { value = "rounded", text = "Rounded" },
        },
        hidden   = NoBorder,
        disabled = "combat",
        get = function() return GS.readBorderStyle() end,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            GS.ApplyBorders(
                function() GS.WriteRPBorders("borderStyle", val) end,
                function() GS.WriteCFGBorders("borderStyle", val) end,
                function() GS.WriteUFBorderStyle(val) end)
            ctx.app:RefreshPage()
        end,
    })

    return {
        groups = {
            -- order 0.5. The three tooltip strings are the ones this
            -- page's own scopeToggle calls passed.
            self:GSScopeCard({
                rp  = "Writes the frame border on the base profile and on every Layout.",
                cfg = "Writes every custom frame group, whether or not the group has Borders overridden.",
                uf  = "Writes the player, target, focus, pet, target-of-target and boss frame borders.",
            }),

            -- ── healthBarBordersGroup (order 1) ──────────────
            { title = "Health Bar Borders", preset = "form", fields = {
                { control = "switch", label = "Enable Border",
                  id = "enableBorder",
                  default = self:GSDefault("borders", "enableBorder"),
                  disabled = "combat",
                  get = function() return GS.readBorderEnable() end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      GS.ApplyBorders(
                          function() GS.WriteRPBorders("enableBorder", v) end,
                          function() GS.WriteCFGBorders("enableBorder", v) end,
                          function() GS.WriteUFBorderEnable(v) end)
                      ctx.app:RefreshPage()
                  end },

                borderStyleField,
                borderWeightField,

                { control = "color", label = "Border Color", alpha = true,
                  desc = "Color and opacity of the frame border. The alpha "
                      .. "slider is the border's opacity.",
                  id = "borderColor", default = BorderColorDefault("borderColor"),
                  disabled = "combat",
                  hidden = NoBorder,
                  get = function()
                      local c = GS.readBorderColor() or { r = 0, g = 0, b = 0, a = 1 }
                      return { c.r, c.g, c.b, (c.a ~= nil) and c.a or 1 }
                  end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      local r, g, b, a = RGBA(v)
                      if r == nil then return end
                      local col = { r = r, g = g, b = b, a = a }
                      GS.ApplyBorders(
                          function() GS.WriteRPBorders("borderColor", col) end,
                          function() GS.WriteCFGBorders("borderColor", col) end,
                          function() GS.WriteUFBorderColor(col) end)
                  end },

                -- A stepper, not a slider: five whole numbers, and the
                -- reader wants "one more pixel" rather than a position on
                -- a track. Same choice the Raid/Party Borders page made
                -- for this same key.
                { control = "stepper", label = "Border Thickness",
                  desc = "Thickness of the square border. Rounded styles use "
                      .. "fixed art thickness.",
                  min = 1, max = 5, step = 1,
                  id = "borderThickness",
                  default = self:GSDefault("borders", "borderThickness"),
                  disabled = "combat",
                  -- Rounded styles have fixed art thickness; the slider
                  -- only applies to the square border (matches the Borders
                  -- page). Hidden too when Enable Border is off, like
                  -- Style and Color.
                  hidden = function()
                      if NoBorder() then return true end
                      local bf = BF()
                      return bf and bf.IsRoundedBorderStyle(GS.readBorderStyle())
                          and true or false
                  end,
                  get = function() return GS.readBorderThickness() end,
                  set = function(_, _, v)
                      if InCombatLockdown() then return end
                      GS.ApplyBorders(
                          function() GS.WriteRPBorders("borderThickness", v) end,
                          function() GS.WriteCFGBorders("borderThickness", v) end,
                          function() GS.WriteUFBorderThickness(v) end)
                  end },
            }},

            -- ── unitFramesGroup (order 2) ────────────────────
            -- Bar separators: a unit-frame-only feature (rounded border
            -- styles only), writing the same ufDB.profile keys the Unit
            -- Frames > Player/Target page writes and relaying out every
            -- unit frame through the shared RefreshUF.
            { title = "Unit Frames", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "Bar separators apply to the player, target, focus, "
                      .. "pet, target-of-target and boss unit frames, and only "
                      .. "while a rounded border style is active." },

                { control = "switch", label = "Unit Frames Bar Separator",
                  desc = "Give each unit frame bar (name, health, power) its "
                      .. "own full rounded border instead of one border around "
                      .. "the whole frame.",
                  id = "oufRoundedSeparators",
                  default = UFDefault("oufRoundedSeparators"),
                  disabled = "combat",
                  hidden = function()
                      local bf = BF()
                      return not (bf and bf:IsOUFRounded())
                  end,
                  get = function()
                      local pf = GS.ufProfile()
                      return pf and pf.oufRoundedSeparators == true
                  end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      local pf = GS.ufProfile(); if not pf then return end
                      pf.oufRoundedSeparators = v and true or false
                      GS.RefreshUF(true)
                      ctx.app:RefreshPage()
                  end },

                { control = "dropdown", label = "Bar Separator Style",
                  desc = "Full Borders: every bar keeps its own rounded "
                      .. "border, with shared edges overlapped so the border "
                      .. "between bars is never double thickness. Divider "
                      .. "Lines: one rounded border around the whole frame "
                      .. "plus straight single-thickness lines between the bars.",
                  options = SEPARATOR_STYLE_OPTIONS,
                  id = "oufSeparatorStyle",
                  default = UFDefault("oufSeparatorStyle"),
                  disabled = "combat",
                  hidden = function()
                      local bf = BF()
                      local pf = GS.ufProfile()
                      return not (bf and bf:IsOUFRounded())
                          or not (pf and pf.oufRoundedSeparators == true)
                  end,
                  get = function()
                      local pf = GS.ufProfile()
                      return (pf and pf.oufSeparatorStyle) or "rings"
                  end,
                  set = function(_, ctx, v)
                      if InCombatLockdown() then return end
                      local pf = GS.ufProfile(); if not pf then return end
                      pf.oufSeparatorStyle = v
                      GS.RefreshUF(true)
                      ctx.app:RefreshPage()
                  end },
            }},
        },
    }
end
