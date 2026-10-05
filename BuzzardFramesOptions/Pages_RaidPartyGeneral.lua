-- ============================================================
-- BuzzardFramesOptions: Pages_RaidPartyGeneral.lua
-- The Raid/Party Frames parent page, in BuzzardPanel.
--
-- The panel equivalent of the raidPartyFrames root args in
-- BuzzardFrames' Options/Options.lua (the enable toggles and the three
-- Hide Blizzard groups): the same settings, the same storage and the
-- same reload popups, with the AceConfig args replaced by a BuzzardPanel
-- page. It replaces the placeholder note on the `raidPartyFrames` route.
--
-- Storage: BF().db.global.* directly -- these five keys are account-wide
-- root-level settings (partyFramesEnabled, raidFramesEnabled,
-- hideBlizzardParty, hideBlizzardRaid, hideBlizzardRaidManager), outside
-- every per-Layout section, and both panels write the same keys, which
-- is what keeps them in step.
--
-- NOT migrated, on purpose: the Ace page's _rootSectionTracker and
-- globalSetupTracker description nodes. Both are AceConfig plumbing --
-- one resets BF._currentSection when the root tab renders, the other
-- pushes the "Active: ... Modifying: ..." readout into the Ace dialog's
-- status text. The panel's status strip (Panel.lua's SetStatusBar spec)
-- is where that readout lives here, and section tracking is a route
-- observer's job in this shell, not a hidden description's.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- What a key resets TO. Buzzard Frames' own defaults table is the single
-- source: a copy here would be a second answer to the same question, and
-- the two would part company the first time a default changed.
local function DefaultG(key)
    local bf = BF()
    local d  = bf and bf.defaults
    d = d and d.global
    return d and d[key]
end

-- ── The raid/party gate ────────────────────────────────────────
--
-- Published, because Panel.lua asks it when it declares the tree: the
-- section drops its sub-tabs while both switches are off.
--
-- `== false` on BOTH keys, which is the Ace raidPartyHidden() to the
-- letter -- an absent key means ON there as it does in the gate's own
-- getter, so only an explicit false on each hides anything.
function BuzzardFramesOptions.RaidPartyOff()
    local bf = BF()
    if not bf then return false end
    local g = bf.db.global
    return g.partyFramesEnabled == false and g.raidFramesEnabled == false
end

-- The two enable toggles. They differ by nothing but their key and their
-- names, so they are built rather than written out twice. The setter is
-- the Ace one to the letter: combat guard, the write, and the reload
-- popup deferred a frame -- the C_Timer.After(0, ...) wrapper is kept
-- verbatim, as the popup must not open inside the widget's own handler.
-- The route rebuild between the write and the popup is the one addition,
-- and it is what the Ace hidden() did by another means (see below).
--
-- These are header GATES, not fields: the setting each card is about
-- lives in the card's own header (`toggle = { get, set }` on the group,
-- as Page.lua reads it), so the card reads "[switch] Enable Party Frames" and
-- collapses to that header when the switch is off. The combat guard is
-- the setter's own, since a gate takes no `disabled` key.
local function EnableGate(key, tooltip, desc)
    return {
        id = key, default = DefaultG(key),
        tooltip = tooltip,
        desc = desc,
        -- `~= false` rather than the raw value: an absent key means ON.
        get = function()
            local bf = BF()
            return bf and bf.db.global[key] ~= false
        end,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            bf.db.global[key] = val
            -- raidPartyHidden's place in the chain, and the same job:
            -- the Ace panel stamped a hidden() onto all fourteen
            -- sub-tabs, so the whole strip vanished while both switches
            -- were off, and the equivalent here is rebuilding the route
            -- tree without those children. RebuildRoutes re-runs
            -- Panel.lua's declaration, which asks RaidPartyOff above;
            -- SetRoutes re-points a route that no longer exists at the
            -- first section, so turning the second switch off from a
            -- page that is about to vanish lands somewhere real rather
            -- than nowhere.
            if ctx and ctx.app then
                BuzzardFramesOptions:RebuildRoutes(ctx.app)
            end
            C_Timer.After(0, function() StaticPopup_Show("BUZZARDFRAMES_RELOAD") end)
        end,
    }
end

-- The three Hide Blizzard toggles, one card each -- the Ace page's three
-- inline groups (hideBlizzardPartyGroup, hideBlizzardRaidGroup,
-- hideBlizzardPanelGroup), titles and all. The setter shows the reload
-- popup in BOTH directions: the hide path installs hooks that cannot be
-- uninstalled, and live-hiding the default frames is fragile across
-- solo<->group transitions, so a reload is the only honest apply.
local function HideField(key, label, desc)
    return {
        control = "switch", label = label,
        id = key, default = DefaultG(key),
        desc = desc,
        disabled = "combat",
        get = function()
            local bf = BF()
            return bf and bf.db.global[key]
        end,
        set = function(_, _, val)
            if InCombatLockdown() then return end
            local bf = BF()
            if not bf then return end
            bf.db.global[key] = val
            StaticPopup_Show("BUZZARDFRAMES_RELOAD")
        end,
    }
end

function BuzzardFramesOptions:RaidPartyGeneralPage()
    return {
        groups = {
            -- The two enable toggles are the headers of the cards they
            -- govern: each card is "[switch] Party Frames" / "[switch]
            -- Raid Frames", with the matching Hide Blizzard switch inside
            -- it. Off, the card collapses to its header, which is what a
            -- gate does everywhere else in this panel.
            { title = "Enable Party Frames", preset = "form",
              toggle = EnableGate("partyFramesEnabled", "Enable Party Frames",
                    "Enable BuzzardFrames for party groups. Requires a UI "
                    .. "reload to take effect."),
              fields = {
                HideField("hideBlizzardParty", "Hide Blizzard Party Frames",
                    "Hide the default Blizzard party frames while "
                    .. "BuzzardFrames is active. Requires a UI reload to "
                    .. "apply."),
            }},

            { title = "Enable Raid Frames", preset = "form",
              toggle = EnableGate("raidFramesEnabled", "Enable Raid Frames",
                    "Enable BuzzardFrames for raid groups. Requires a UI "
                    .. "reload to take effect."),
              fields = {
                HideField("hideBlizzardRaid", "Hide Blizzard Raid Frames",
                    "Hide the default Blizzard raid frames while "
                    .. "BuzzardFrames is active. Requires a UI reload to "
                    .. "apply."),
            }},

            { title = "Blizzard Raid Tools Panel", preset = "form", fields = {
                HideField("hideBlizzardRaidManager",
                    "Hide Blizzard Raid Tools Panel",
                    "Also hide the Blizzard raid tools panel (ready check, "
                    .. "role poll, etc.) shown on the left side of the "
                    .. "screen. Changing this requires a UI reload."),
            }},
        },
    }
end
