-- ============================================================
-- BuzzardFramesOptions: Pages_InterruptAlert.lua
-- The Interrupt Alerts page: an alert on a group member's raid/party frame
-- when their own cast is interrupted.
--
-- Storage: BF().interruptAlertDB.profile (BuzzardFrames/Indicators/
-- InterruptAlert.lua), account-wide. Style settings are read each time an
-- alert shows; only the master switch needs the module told (Refresh).
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function Cfg()
    local bf = BF()
    local db = bf and bf.interruptAlertDB
    return db and db.profile
end

local function Default(key)
    local bf = BF()
    local d = bf and bf.interruptAlertDefaults
    return d and d.profile[key]
end

local function Get(key)
    return function()
        local c = Cfg()
        return c and c[key]
    end
end

local function Set(key, refresh)
    return function(_, ctx, v)
        local c = Cfg()
        if not c then return end
        c[key] = v
        if refresh then
            local ia = BF() and BF().InterruptAlert
            if ia then ia:Refresh() end
        end
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end
end

local function Off()
    local c = Cfg()
    return not (c and c.enabled)
end

local function Switch(key, label, desc)
    return { control = "switch", label = label, desc = desc,
             id = key, default = Default(key), hidden = Off,
             get = Get(key), set = Set(key) }
end

local function Slider(key, label, desc, min, max, step)
    return { control = "slider", label = label, desc = desc,
             id = key, default = Default(key), hidden = Off,
             min = min, max = max, step = step,
             get = Get(key), set = Set(key) }
end

function BuzzardFramesOptions:InterruptAlertPage()
    return {
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Shows the interrupted spell, marked Interrupted, on a "
                      .. "group member's raid/party frame when their own cast "
                      .. "is interrupted, e.g. a mob kicking your healer. "
                      .. "|cffffd100/bfkick test|r shows a sample." },
            }},
            { title = "Interrupt Alerts", preset = "form", fields = {
                { control = "switch", label = "Show Interrupt Alerts", wide = true,
                  desc = "Show an alert on a group member's frame when their "
                      .. "cast is interrupted.",
                  id = "enabled", default = Default("enabled"),
                  get = Get("enabled"), set = Set("enabled", true) },
            }},
            { title = "When", preset = "form", fields = {
                Switch("realOnly", "Only Real Interrupts",
                    "On: only casts something interrupted (a kick, a "
                    .. "silence...).\n\nOff: also casts the player moved out "
                    .. "of or cancelled."),
                Switch("includePlayer", "Include Me",
                    "Show the alert on your own frame too."),
                Switch("playSound", "Play a Sound",
                    "Play the raid warning sound with each alert."),
            }},
            { title = "Style", preset = "form", fields = {
                Switch("showText", "Show \"Interrupted\" Text",
                    "Show the word Interrupted under the icon."),
                Slider("duration", "Duration",
                    "Seconds the alert stays up. The game does not report "
                    .. "the lockout's real length; the alert also clears "
                    .. "when the member starts casting again.", 1, 10, 0.5),
                Slider("iconSize", "Icon Size", nil, 12, 48, 1),
                Slider("yOffset", "Vertical Offset",
                    "Where the icon sits, relative to the frame's center.",
                    -40, 40, 1),
            }},
        },
    }
end
