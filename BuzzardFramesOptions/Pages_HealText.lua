-- ============================================================
-- BuzzardFramesOptions: Pages_HealText.lua
-- The Heal Text page: floating heal numbers on raid/party and unit frames.
--
-- Storage: BF().healTextDB.profile (BuzzardFrames/Indicators/HealText.lua),
-- account-wide. Every style setting is read at the moment a number is
-- shown, so only the master switch needs the module told (Refresh, which
-- re-registers its events).
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

local function Cfg()
    local bf = BF()
    local db = bf and bf.healTextDB
    return db and db.profile
end

local function Default(key)
    local bf = BF()
    local d = bf and bf.healTextDefaults
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
            local ht = BF() and BF().HealText
            if ht then ht:Refresh() end
        end
        if ctx and ctx.app then ctx.app:RefreshPage() end
    end
end

local function Off()
    local c = Cfg()
    return not (c and c.enabled)
end

local function Switch(key, label, desc, refresh)
    return { control = "switch", label = label, desc = desc,
             id = key, default = Default(key), hidden = Off,
             get = Get(key), set = Set(key, refresh) }
end

local function Slider(key, label, desc, min, max, step)
    return { control = "slider", label = label, desc = desc,
             id = key, default = Default(key), hidden = Off,
             min = min, max = max, step = step,
             get = Get(key), set = Set(key) }
end

-- The LSM font list, resolved each time the menu opens, each row drawn in
-- its own face (the same picker Pages_AuraText.lua builds).
local function FontOptions()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            out[#out + 1] = { value = name, text = name,
                              font = LSM:Fetch("font", name) }
        end
    end
    return out
end

local OUTLINE_OPTIONS = {
    { value = "",             text = "None" },
    { value = "OUTLINE",      text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick Outline" },
}

local OVERHEAL_FORMATS = {
    { value = "total",     text = "Whole Heal: +103 (93)" },
    { value = "effective", text = "Healing Done: +10 (93)" },
}

local function Dropdown(key, label, options)
    return { control = "dropdown", label = label, options = options,
             id = key, default = Default(key), hidden = Off,
             get = Get(key), set = Set(key) }
end

function BuzzardFramesOptions:HealTextPage()
    return {
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Floating numbers on the frames when a heal lands: "
                      .. "Regrowth's initial hit, Healing Touch, Swiftmend and "
                      .. "so on. |cffffd100/bfheal test|r shows sample numbers." },
            }},
            { title = "Heal Text", preset = "form", fields = {
                { control = "switch", label = "Show Heal Text", wide = true,
                  desc = "Show floating heal numbers on the frames.",
                  id = "enabled", default = Default("enabled"),
                  get = Get("enabled"), set = Set("enabled", true) },
            }},
            { title = "What To Show", preset = "form", fields = {
                Switch("showHoTs", "Show All Heals (HoT Ticks Too)",
                    "Off: only your own direct heals show (Regrowth's first "
                    .. "hit, Healing Touch, Swiftmend...), matched to your "
                    .. "casts.\n\nOn: every heal on the unit shows, from any "
                    .. "healer, HoT ticks included -- the game does not say "
                    .. "whose heal it was or whether it was a tick."),
                Switch("showOverheal", "Show Overhealing",
                    "Show the overhealed part in grey brackets after the "
                    .. "number. Worked out from the unit's health, so it can "
                    .. "be slightly off."),
                Dropdown("overhealFormat", "Overheal Number", OVERHEAL_FORMATS),
                Switch("showSpell", "Show Spell Name",
                    "Put the spell name in front of the number (your own "
                    .. "direct heals only)."),
                Switch("biggerCrits", "Bigger Crits",
                    "Show critical heals in a larger font."),
            }},
            { title = "Where", preset = "form", fields = {
                Switch("raidParty", "Raid/Party Frames",
                    "Show heal text on raid and party frames."),
                Switch("unitFrames", "Unit Frames",
                    "Show heal text on the player, target, focus, pet and "
                    .. "target-of-target frames."),
            }},
            { title = "Style", preset = "form", fields = {
                Dropdown("font", "Font", FontOptions),
                Dropdown("fontOutline", "Font Outline", OUTLINE_OPTIONS),
                Slider("fontSize", "Font Size", nil, 8, 32, 1),
                Slider("yOffset", "Vertical Offset",
                    "Where the number starts, relative to the frame's center.",
                    -40, 40, 1),
                Slider("rise", "Float Distance",
                    "How far the number floats upward.", 0, 60, 1),
                Slider("duration", "Duration",
                    "Seconds each number stays on screen.", 0.5, 4, 0.1),
                { control = "color", label = "Color", alpha = true,
                  id = "color", hidden = Off,
                  get = function()
                      local c = Cfg()
                      c = c and c.color
                      if type(c) ~= "table" then return nil end
                      return { c.r, c.g, c.b, c.a }
                  end,
                  set = function(_, _, v)
                      local c = Cfg()
                      if not c then return end
                      c.color = { r = v[1], g = v[2], b = v[3], a = v[4] or 1 }
                  end },
            }},
        },
    }
end
