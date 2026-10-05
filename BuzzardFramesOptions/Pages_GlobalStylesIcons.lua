-- ============================================================
-- BuzzardFramesOptions: Pages_GlobalStylesIcons.lua
-- The Global Styles > Icons page, in BuzzardPanel.
--
-- The panel equivalent of the `gsIcons` child of BuzzardFrames'
-- Options/Options_GlobalStyles.lua: the same settings, in the same order,
-- with the same storage routing and the same side effects. Both panels
-- exist while the Ace one is being retired, and an edit in either lands in
-- exactly the same place, so they cannot drift apart in what they STORE.
--
-- Storage: NONE of its own, and TWO different destinations.
--   * The two role icon fields are WRITE-THROUGHS into the `icons`
--     section -- rpDB.profile.icons plus every layout flat, and every
--     custom frame group's flat.icons -- through the shared fan-out in
--     Pages_GlobalStylesShared.lua (BuzzardFramesOptions:GS()). The unit
--     frames have no role icon, so that fan-out has no UF branch.
--   * Everything from "Unit Frames: Class Icon" down writes ufDB.profile
--     directly and relays out the unit frames, exactly as the Ace widgets
--     did -- the same keys the Unit Frames > Global > Class Icon page
--     writes, so the two pages edit one setting between them.
--
-- Neither path writes a db table this file owns, which is what keeps the
-- two panels in step.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- Nothing at file scope reads the addon; resolved inside the builders and
-- the setters, after the panel is open.
local function BF() return _G.BuzzardFrames end

-- The shipped default for a unit-frame profile key -- BuzzardFrames' own
-- defaults table, the single source for what a key resets TO. The
-- Raid/Party defaults table has no answer for a UF-only setting.
local function UFDefault(key)
    local bf = BF()
    local d  = bf and bf.unitFrameDefaults
    d = d and d.profile
    return d and d[key]
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

local function UFColorDefault(key)
    local c = UFDefault(key)
    if type(c) ~= "table" then return nil end
    return { c.r, c.g, c.b }
end

-- ── Shared option lists, in the Ace `values` order ─────────────
--
-- None of these Ace selects declared a `sorting`, so the dialog showed
-- them alphabetically by label. The panel draws them in declaration
-- order, and that is the order used here.
local ROLE_ICON_STYLE_OPTIONS = {
    { value = "BLIZZARD", text = "Blizzard Circular (Classic)" },
    { value = "GLASS",    text = "Glass" },
    { value = "MODERN",   text = "Modern (10.1.5+)" },
    { value = "TINY",     text = "Tiny Atlas Icons" },
}
local ICON_STYLE_OPTIONS = {
    { value = "classicon", text = "Class Icon" },
    { value = "model",     text = "Model" },
    { value = "portrait",  text = "Portrait" },
}
local ICON_SHAPE_OPTIONS = {
    { value = "circular", text = "Circular" },
    { value = "square",   text = "Square" },
}
local ICON_LOCATION_OPTIONS = {
    { value = "center", text = "Center" },
    { value = "inner",  text = "Inner" },
    { value = "outer",  text = "Outer" },
}

-- ── The page ───────────────────────────────────────────────────

function BuzzardFramesOptions:GlobalStylesIconsPage()
    local GS = self:GS()
    if not GS then return { groups = {} } end

    local function Prof() return GS.ufProfile() end

    -- The Ace `hidden` predicate every unit frame field below carried.
    local function NoClassIcon()
        local pf = Prof()
        return not pf or not pf.playerShowClassIcon
    end
    local function NoIconBorder()
        local pf = Prof()
        return NoClassIcon() or not pf.classIconBorderEnabled
    end

    -- One writer for the whole unit-frame half of this page: set the key,
    -- relayout and update every unit frame. `RefreshUF(true)` is the same
    -- call each Ace setter made.
    local function SetUF(key, val)
        local pf = Prof(); if not pf then return end
        pf[key] = val
        GS.RefreshUF(true)
    end

    -- A plain unit-frame field: everything but the control kind and the
    -- value adapters is identical across the eleven of them.
    local function UF(field)
        local key = field.key
        field.key = nil
        field.id = key
        if field.default == nil then field.default = UFDefault(key) end
        field.disabled = "combat"
        if field.get == nil then
            field.get = function() local pf = Prof(); return pf and pf[key] end
        end
        if field.set == nil then
            field.set = function(_, _, val)
                if InCombatLockdown() then return end
                SetUF(key, val)
            end
        end
        return field
    end

    return {
        groups = {
            -- order 0.5. This page's own scopeToggle calls passed only the
            -- Raid/Party and Custom Frame Groups tooltips: the unit frame
            -- settings below are NOT scope-gated (they write ufDB
            -- unconditionally, as they did in the Ace page), so the Ace
            -- card carried two switches rather than three -- and so does
            -- this one: a surface with no desc gets no switch.
            self:GSScopeCard({
                rp  = "Writes the Icons section on the base profile and on every Layout.",
                cfg = "Writes every custom frame group, whether or not the group has Icons overridden.",
            }),

            -- The two role icon fields sat at the top of the Ace page with
            -- no header above them (orders 1 and 2). A card needs a title;
            -- this one names what its two fields are about, which is the
            -- one presentational change the migration allows.
            { title = "Role Icons", preset = "form", fields = {
                { control = "dropdown", label = "Role Icon Style",
                  desc = "Choose between modern 10.1.5 icons, classic "
                      .. "circular icons, small atlas icons, or translucent "
                      .. "glass icons",
                  options = ROLE_ICON_STYLE_OPTIONS,
                  id = "roleIconStyle",
                  default = self:GSDefault("icons", "roleIconStyle"),
                  disabled = "combat",
                  get = function()
                      local src = GS.iconsSource()
                      return src and src.roleIconStyle
                  end,
                  set = function(_, _, val)
                      if InCombatLockdown() then return end
                      GS.ApplyIcons(
                          function() GS.WriteRPIcons("roleIconStyle", val) end,
                          function() GS.WriteCFGIcons("roleIconStyle", val) end,
                          "iconsLayout", GS.RefreshRPRoleIcons,
                          function()
                              local bf = BF()
                              if bf and bf.RefreshPreviewRoleIcon then
                                  bf:RefreshPreviewRoleIcon()
                              end
                          end)
                  end },

                { control = "slider", label = "Role Icon Size",
                  min = 6, max = 24, step = 1,
                  id = "roleIconSize",
                  default = self:GSDefault("icons", "roleIconSize"),
                  disabled = "combat",
                  get = function()
                      local src = GS.iconsSource()
                      return src and src.roleIconSize
                  end,
                  set = function(_, _, val)
                      if InCombatLockdown() then return end
                      GS.ApplyIcons(
                          function() GS.WriteRPIcons("roleIconSize", val) end,
                          function() GS.WriteCFGIcons("roleIconSize", val) end,
                          "iconsLayout", GS.RefreshRPIconsLayout, nil)
                  end },
            }},

            -- ── ufClassIconHeader (order 10) ─────────────────
            { title = "Unit Frames: Class Icon", preset = "form", fields = {
                UF({ control = "switch", key = "playerShowClassIcon",
                     label = "Show Class Icon",
                     desc = "Show the class icon slot on all unit frames." }),

                UF({ control = "dropdown", key = "iconStyle", label = "Icon Style",
                     desc = "Class Icon: shows the class icon for players, "
                         .. "portrait for NPCs.\nPortrait: always shows the "
                         .. "unit portrait.",
                     options = ICON_STYLE_OPTIONS,
                     hidden = NoClassIcon }),

                UF({ control = "dropdown", key = "iconShape", label = "Icon Shape",
                     options = ICON_SHAPE_OPTIONS,
                     hidden = function()
                         local pf = Prof()
                         return NoClassIcon() or pf.iconStyle == "model"
                     end }),

                UF({ control = "slider", key = "iconSize", label = "Icon Size",
                     min = 20, max = 80, step = 1,
                     hidden = NoClassIcon,
                     get = function()
                         local pf = Prof()
                         return pf and (pf.iconSize or 51)
                     end }),

                -- isPercent on a 0-1 value: stored as a fraction, shown in
                -- percent units, converted at the edge (the same adapter
                -- the Unit Frames Class Icon page uses for this key).
                UF({ control = "slider", key = "iconOpacity", label = "Icon Opacity",
                     min = 0, max = 100, step = 1,
                     default = (function()
                         local d = UFDefault("iconOpacity")
                         if type(d) ~= "number" then return 100 end
                         return math.floor(d * 100 + 0.5)
                     end)(),
                     hidden = NoClassIcon,
                     get = function()
                         local pf = Prof()
                         if not pf then return 100 end
                         local v = pf.iconOpacity
                         if v == nil then return 100 end
                         return math.floor(v * 100 + 0.5)
                     end,
                     set = function(_, _, val)
                         if InCombatLockdown() then return end
                         SetUF("iconOpacity", math.floor(val + 0.5) / 100)
                     end }),
            }},

            -- ── ufHdrIconPos (order 20) ──────────────────────
            -- The Ace header carried the same hidden predicate its fields
            -- did; on a card that is the card's own.
            { title = "Icon Position", preset = "form", hidden = NoClassIcon,
              fields = {
                -- The Ace sliders were -100..100 with soft bounds at
                -- -30..30. The library has no soft bound, so the SHOWN
                -- range is what the field carries -- the same call the
                -- unit frame pages made for their offset sliders.
                UF({ control = "slider", key = "iconOffsetX", label = "X Offset",
                     desc = "Moves all icons horizontally.",
                     min = -30, max = 30, step = 1,
                     hidden = NoClassIcon,
                     get = function()
                         local pf = Prof()
                         return pf and (pf.iconOffsetX or 0)
                     end }),

                UF({ control = "slider", key = "iconOffsetY", label = "Y Offset",
                     desc = "Moves all icons vertically by the same amount.",
                     min = -30, max = 30, step = 1,
                     hidden = NoClassIcon,
                     get = function()
                         local pf = Prof()
                         return pf and (pf.iconOffsetY or 0)
                     end }),

                UF({ control = "dropdown", key = "iconLocation", label = "Location",
                     desc = "Where the icon sits relative to the bar frame "
                         .. "edge.\nOuter: fully outside the bars (default)."
                         .. "\nCenter: icon center sits on the edge.\nInner: "
                         .. "fully inside the bars.",
                     options = ICON_LOCATION_OPTIONS,
                     hidden = NoClassIcon }),
            }},

            -- ── ufHdrIconBorder (order 30) ───────────────────
            { title = "Icon Border", preset = "form", hidden = NoClassIcon,
              fields = {
                UF({ control = "switch", key = "classIconBorderEnabled",
                     label = "Enable Icon Border",
                     hidden = NoClassIcon,
                     get = function()
                         local pf = Prof()
                         return pf and pf.classIconBorderEnabled ~= false
                     end }),

                -- A stepper, not a slider: ten whole numbers, and the
                -- reader wants "one more pixel". Same choice the Unit
                -- Frames Class Icon page made for this key.
                UF({ control = "stepper", key = "classIconBorderThickness",
                     label = "Border Thickness",
                     min = 1, max = 10, step = 1,
                     hidden = NoIconBorder,
                     get = function()
                         local pf = Prof()
                         return pf and (pf.classIconBorderThickness or 2)
                     end }),

                UF({ control = "switch", key = "classIconBorderUseHealthColor",
                     label = "Use Health Bar Colors",
                     desc = "Match the icon border color to the unit's health "
                         .. "bar color. Updates automatically when the target "
                         .. "changes.",
                     hidden = NoIconBorder }),

                -- The Ace setter MUTATED the stored table in place rather
                -- than replacing it; kept, so anything holding a reference
                -- to that table sees the change.
                UF({ control = "color", key = "classIconBorderColor",
                     label = "Border Color",
                     default = UFColorDefault("classIconBorderColor"),
                     hidden = function()
                         local pf = Prof()
                         return NoIconBorder()
                             or (pf.classIconBorderUseHealthColor and true or false)
                     end,
                     get = function()
                         local pf = Prof()
                         local c = pf and pf.classIconBorderColor or { r = 0, g = 0, b = 0 }
                         return { c.r, c.g, c.b }
                     end,
                     set = function(_, _, v)
                         if InCombatLockdown() then return end
                         local pf = Prof(); if not pf then return end
                         local r, g, b = RGB(v)
                         if r == nil then return end
                         local c = pf.classIconBorderColor or {}
                         c.r, c.g, c.b = r, g, b
                         pf.classIconBorderColor = c
                         GS.RefreshUF(true)
                     end }),
            }},
        },
    }
end
