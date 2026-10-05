-- ============================================================
-- BuzzardFramesOptions: Pages_BorderStyle.lua
--
-- One border style control, shared by the six places that draw one.
--
-- THE PROBLEM IT SOLVES. `borderStyle` stores four values across this
-- addon -- blizzard, flat/square, rounded, rounded_thick -- and the last
-- two are not two styles. They are ONE style at two weights: the same
-- rounded frame, the thick one about a pixel heavier. Offering them as
-- peers of Square made the reader choose a shape and a weight in a single
-- list, and put the weight of the rounded border somewhere entirely
-- different from the thickness of the square one.
--
-- So the list drops to shapes, and a second strip appears beside it while
-- a rounded shape is picked:
--
--     Border Style      [ Blizzard-Style | Square | Rounded ]
--     Border Thickness  [ Thin | Thick ]          (rounded only)
--     Border Thickness  [ - 2 + ]                 (square only)
--
-- NOTHING ABOUT STORAGE CHANGES. `borderStyle` still holds rounded or
-- rounded_thick, the runtime still reads exactly what it read before, and
-- no profile needs migrating. The two strips are two VIEWS of that one
-- value: the style strip answers "which shape", the weight strip answers
-- "which of the two rounded spellings", and both write through the page's
-- own setter so whatever that setter does -- seeding highlight widths,
-- coercing an aggro style, refreshing containers -- still happens.
--
-- Each page keeps its own reader and writer, because the five of them
-- store this in five different places: a flat profile key, a per-Layout
-- section key, a container's effective source. Only the SHAPE of the
-- control is shared, which is the part that was duplicated.
-- ============================================================
local ADDON = ...
local BuzzardFramesOptions = _G.BuzzardFramesOptions

-- `hidden`, `disabled` and friends may be a function or a plain value; the
-- library resolves them either way, and so must anything composing them.
local function Call(v, ...)
    if type(v) == "function" then return v(...) end
    return v
end

-- Returns the style strip and the Thin/Thick strip, in that order. Put
-- them next to each other: the second is the second half of the first.
--
--   spec.options    the shapes, WITHOUT the thick variant
--   spec.thin       the stored value for the light rounded frame
--   spec.thick      the stored value for the heavy one
--   spec.get/set    the page's own reader and writer for the style key
--   spec.bind/id/default/hidden/disabled/onChange/refresh
--                   passed through to the style strip unchanged
function BuzzardFramesOptions:BorderStyleFields(spec)
    local thin  = spec.thin  or "rounded"
    local thick = spec.thick or "rounded_thick"

    -- The node the page's reader and writer expect to be handed. The
    -- weight strip has no bind of its own, so it borrows this one -- which
    -- is what makes its write indistinguishable from the style strip's.
    local key = { bind = spec.bind, id = spec.id }

    local function current(ctx) return spec.get(key, ctx) end
    local function isRounded(ctx)
        local v = current(ctx)
        return v == thin or v == thick
    end

    local style = {
        control  = "segmented",
        label    = spec.label or "Border Style",
        desc     = spec.desc,
        options  = spec.options,
        bind     = spec.bind,
        id       = spec.id,
        default  = spec.default,
        hidden   = spec.hidden,
        disabled = spec.disabled or "combat",
        onChange = spec.onChange,
        refresh  = spec.refresh,

        get = function(node, ctx)
            local v = spec.get(node, ctx)
            -- Thick is not a shape. It reads as Rounded here, and the
            -- strip beside this one says which of the two is stored.
            if v == thick then return thin end
            return v
        end,

        set = function(node, ctx, v)
            -- Re-picking Rounded while Thick is stored must NOT quietly
            -- demote it to Thin. This control does not own that half of
            -- the value, and a segmented control writes on every click,
            -- including a click on the segment already lit.
            if v == thin and spec.get(node, ctx) == thick then return end
            spec.set(node, ctx, v)
            -- A shape change adds or removes a whole field -- the weight
            -- strip, the square thickness stepper -- so the card has to be
            -- laid out again rather than repainted.
            if ctx and ctx.app then ctx.app:Invalidate() end
        end,
    }

    local weight = {
        control  = "segmented",
        label    = "Border Thickness",
        desc     = spec.weightDesc
            or "Thick draws the same rounded frame about a pixel heavier.",
        options  = { { value = thin,  text = "Thin"  },
                     { value = thick, text = "Thick" } },
        disabled = spec.disabled or "combat",
        onChange = spec.onChange,
        refresh  = spec.refresh,

        -- No `bind` and no `id`: this is a second view of the style key,
        -- not a setting of its own. Two fields sharing one bind would
        -- collide in the widget index, and the style strip already carries
        -- the right-click Undo and Reset for the value they share.
        hidden = function(node, ctx)
            if Call(spec.hidden, node, ctx) then return true end
            return not isRounded(ctx)
        end,

        get = function(_, ctx)
            return (current(ctx) == thick) and thick or thin
        end,

        set = function(_, ctx, v)
            spec.set(key, ctx, v)
        end,
    }

    return style, weight
end
