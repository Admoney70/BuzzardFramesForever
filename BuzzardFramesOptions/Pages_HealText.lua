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

function BuzzardFramesOptions:HealTextPage()
    return {
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "Floating numbers on the frames when a heal lands: "
                      .. "Regrowth's initial hit, Healing Touch, Swiftmend and "
                      .. "so on. |cffffd100/bfheal test|r shows sample numbers; "
                      .. "|cffffd100/bfheal|r says which data source is in use." },
            }},
            { title = "Heal Text", preset = "form", fields = {
                { control = "switch", label = "Show Heal Text", wide = true,
                  desc = "Show floating heal numbers on the frames.",
                  id = "enabled", default = Default("enabled"),
                  get = Get("enabled"), set = Set("enabled", true) },
            }},
            { title = "What To Show", preset = "form", fields = {
                Switch("onlyMine", "Only My Heals",
                    "Show only heals you cast. Needs the combat log; if the "
                    .. "client does not give addons the combat log, every "
                    .. "heal on the unit shows instead."),
                Switch("showHoTs", "Show HoT Ticks",
                    "Also show each periodic tick (Rejuvenation, Regrowth's "
                    .. "HoT, Renew...). Off shows only direct heals. Needs "
                    .. "the combat log."),
                Switch("showOverheal", "Show Overhealing",
                    "Add the overhealed amount in grey brackets after the "
                    .. "number. Needs the combat log."),
                Switch("showSpell", "Show Spell Name",
                    "Put the spell name in front of the number. Needs the "
                    .. "combat log."),
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
