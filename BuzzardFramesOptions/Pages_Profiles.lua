-- ============================================================
-- BuzzardFramesOptions: Pages_Profiles.lua
-- The Profiles section, in BuzzardPanel.
--
-- The panel equivalent of BuzzardFrames' Options/Options_Profiles.lua
-- (BF:BuildProfilesOptions) and Options/Options_Themes.lua
-- (BF:BuildThemesOptions): the same settings, the same storage and the
-- same side effects, with the AceConfig childGroups="tab" section
-- replaced by five BuzzardPanel pages -- one per subtab, each a route of
-- its own under `profiles`, drawn as a strip by the `tabs` navigator that
-- node declares. The Ace tabs map one to one, in the Ace `order` the
-- strip read them in: tabGeneral (1) -> general, tabManage (1.5) ->
-- manage, tabThemes (1.7) -> themes, tabExport (2) -> export, tabImport
-- (3) -> import.
--
-- Profiles takes NO per-Layout scope row: a profile is not a Layout.
--
-- Storage. Nothing on these pages is an ordinary setting in one table,
-- so there is no page `db` and no `bind` anywhere:
--   * General switches a module's AceDB profile through that DB's own
--     :SetProfile, which is what fires the module's OnProfileChanged;
--   * Profile Management renames and clones by reaching into the module's
--     SavedVariables table (AceDB has no rename API) and deletes through
--     db:DeleteProfile -- the Ace page's own handlers, ported whole;
--   * Export stores its name and its include set in
--     BuzzardFrames.db.global (exportProfileName / exportIncludeModules),
--     resolved through ProfilesUI.ResolveExportInclude so the two panels
--     can never disagree about what "included" means;
--   * Import writes nothing until the Import button: the pasted string
--     and the decoded intermediate are session state in
--     ProfilesUI.importState, exactly as they were file-locals of the Ace
--     builder;
--   * Themes calls the engine published on BuzzardFrames
--     (BF.THEMES, BF:ApplyThemeAsNewProfiles / ApplyThemeToCurrentProfiles
--     through the BUZZARDFRAMES_APPLY_THEME popup, BF:BuildThemeSnapshot).
-- Both panels go through those same doors, which is what keeps them in
-- step while both exist.
--
-- The pipeline the tabs drive -- the legacy decoders, the import state,
-- the decode report, the import committer, the copy window, the theme
-- snapshot serializer -- is Pages_ProfilesShared.lua, published as
-- BuzzardFramesOptions.ProfilesUI.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- The ported pipeline. Read through a function rather than captured at
-- file scope: the two files load in .toc order and this one must not
-- depend on which way round that is.
local function UI() return BuzzardFramesOptions.ProfilesUI end

-- ── The tab strip ──────────────────────────────────────────────
--
-- Ace order: General 1, Profile Management 1.5, Themes 1.7, Export 2,
-- Import 3.
--
-- Themes carries the Ace group's own `hidden` as a `when` predicate, so
-- the ROUTE is not minted at all while Enable Experimental Options is
-- off -- a hidden tab in the Ace strip and an absent route are the same
-- thing on screen. SubtabRoutes (Panel.lua) honors it, and the
-- experimental switch's setter in Pages_Preview.lua calls RebuildRoutes
-- so the tab appears and disappears with the flag.
BuzzardFramesOptions.PROFILES_SUBTABS = {
    { id = "general", title = "General" },
    { id = "manage",  title = "Profile Management" },
    { id = "themes",  title = "Themes",
      when = function()
          local bf = BF()
          return (bf and bf.db and bf.db.global
              and bf.db.global.enableExperimentalOptions) and true or false
      end },
    { id = "export",  title = "Export" },
    { id = "import",  title = "Import" },
}

-- ── Shared bits ────────────────────────────────────────────────

-- A module's AceDB, or nil.
local function ModuleDB(key)
    local bf = BF()
    local ui = UI()
    return bf and ui and bf[ui.MODULE_DB_FIELD[key]]
end

-- A module's profile list as dropdown options, the ACTIVE one tinted
-- green -- how the Ace dropdown has always shown "this is the one in
-- use". The one color escape this page keeps, per the migration guide.
local function ProfileOptions(key)
    local db = ModuleDB(key)
    if not db then return {} end
    local current = db:GetCurrentProfile()
    local out = {}
    for _, name in ipairs(db:GetProfiles()) do
        out[#out + 1] = {
            value = name,
            text  = (name == current) and ("|cff76CC4B" .. name .. "|r") or name,
        }
    end
    return out
end

-- One of the five General dropdowns -- the Ace module_RaidPartyFrames,
-- module_AuraCustomizations, module_CustomFrameGroups, module_UnitFrames
-- and module_IncomingCasts selects, in that order (Ace order 11-15). The
-- module DB's own OnProfileChanged callback, registered in Core_DB, fires
-- the shared BF:OnProfileChanged refresh pipeline, so the setter only has
-- to call SetProfile and let the page re-read.
--
-- The Ace widget also carried `validate` returning "Profile cannot be
-- changed in combat"; the panel has no validate, and the same rule is
-- already stated twice over by `disabled = "combat"` and the setter's own
-- guard, which is what actually enforces it.
local function ModuleProfileField(key, label, desc)
    return {
        control = "dropdown", label = label, desc = desc,
        -- The Ace widget was width = "double". A profile name is longer
        -- than a layout name and shorter than a sentence.
        width = 260,
        id = "module_" .. key,
        disabled = "combat",
        options = function() return ProfileOptions(key) end,
        get = function()
            local db = ModuleDB(key)
            return db and db:GetCurrentProfile() or "Default"
        end,
        set = function(_, ctx, val)
            if InCombatLockdown() then return end
            local db = ModuleDB(key)
            if not db then return end
            db:SetProfile(val)
            ctx.app:RefreshPage()
        end,
    }
end

-- ── Tab: General ───────────────────────────────────────────────

local function GeneralPage()
    return {
        groups = {
            { preset = "bare", fields = {
                { control = "note", wide = true,
                  text = "BuzzardFrames Profiles are global, not "
                      .. "character-specific. Profiles are now modular, "
                      .. "changing the profile for one module does not "
                      .. "affect the other modules.\nUse the Profile "
                      .. "Management tab to rename, clone, or delete "
                      .. "profiles." },
            }},

            -- The Ace moduleHeader, as the card it always was.
            { title = "Module Profiles", preset = "form", fields = {
                ModuleProfileField("RaidPartyFrames", "Raid/Party Frames",
                    "The profile that Raid/Party Frames uses. Switching takes effect immediately."),
                ModuleProfileField("AuraCustomizations", "Aura Customizations",
                    "The profile that Aura Customizations uses. Switching takes effect immediately."),
                ModuleProfileField("CustomFrameGroups", "Custom Frame Groups",
                    "The profile that Custom Frame Groups uses. Switching takes effect immediately."),
                ModuleProfileField("UnitFrames", "Unit Frames",
                    "The profile that Unit Frames uses. Switching takes effect immediately."),
                ModuleProfileField("IncomingCasts", "Incoming Casts",
                    "The profile that Incoming Casts uses. Switching takes effect immediately."),
            }},
        },
    }
end

-- ── Tab: Profile Management ────────────────────────────────────
--
-- Session-only state, file-local exactly as it was in the Ace builder's
-- closure: which module's profiles are being managed, which profile, and
-- what the Rename box currently holds.
local mgmtModule  = nil   -- selected MODULE_KEYS entry
local mgmtProfile = nil   -- selected profile name
local mgmtRename  = ""    -- rename input value

local function MgmtDB()
    if not mgmtModule then return nil end
    return ModuleDB(mgmtModule)
end

local function MgmtIsActive()
    local db = MgmtDB()
    return db and mgmtProfile == db:GetCurrentProfile()
end

-- The module's SavedVariables table, for the two handlers that have to
-- reach past AceDB (Rename and Clone).
local function MgmtSV()
    local ui = UI()
    local name = ui and ui.SV_NAMES[mgmtModule]
    return name and _G[name]
end

-- The Ace page rebuilt its whole args table on every NotifyChangeSafe,
-- which is what let its actionsHeader be a FUNCTION of the selection.
-- A card's title cannot be a function, so the card is built from the
-- session state and the four handlers that move that state ask for the
-- page to be BUILT again rather than merely re-read.
--
-- Invalidate is the rung that does that: RefreshPage and RenderPage both
-- draw from app.pageCache, which only ns.page.ClearPageCache empties --
-- and the reindex Invalidate performs is what calls it. See the same
-- idiom in Pages_AuraText.lua.
local function RebuildMgmt(ctx)
    if ctx and ctx.app then ctx.app:Invalidate("bfProfileMgmt") end
end

-- Rename: AceDB has no rename API, so a rename is copy the data to the
-- new name, re-point every profileKeys entry that named the old one,
-- switch if it was active, drop the old.
local function MgmtRenameTo(val, ctx)
    if not val or val:match("^%s*$") then return end
    local bf = BF()
    local ui = UI()
    local db = MgmtDB()
    if not (bf and ui and db and mgmtProfile) then return end
    -- Check for name collision
    for _, existing in ipairs(db:GetProfiles()) do
        if existing == val then
            print("|cffff4444BuzzardFrames:|r A profile named \"" .. val
                .. "\" already exists in " .. ui.MODULE_LABELS[mgmtModule] .. ".")
            return
        end
    end
    local sv = MgmtSV()
    if not sv or not sv.profiles or not sv.profiles[mgmtProfile] then return end
    local wasActive = MgmtIsActive()
    sv.profiles[val] = sv.profiles[mgmtProfile]
    sv.profiles[mgmtProfile] = nil
    -- Update profileKeys entries that pointed to the old name
    if sv.profileKeys then
        for charKey, profName in pairs(sv.profileKeys) do
            if profName == mgmtProfile then
                sv.profileKeys[charKey] = val
            end
        end
    end
    if wasActive then
        db:SetProfile(val)
    end
    print("|cffd3ff7dBuzzardFrames:|r Renamed " .. ui.MODULE_LABELS[mgmtModule]
        .. " profile \"" .. mgmtProfile .. "\" to \"" .. val .. "\".")
    mgmtProfile = val
    mgmtRename  = val
    RebuildMgmt(ctx)
end

local function MgmtClone(ctx)
    local bf = BF()
    local ui = UI()
    local db = MgmtDB()
    if not (bf and ui and db and mgmtProfile) then return end
    local sv = MgmtSV()
    if not sv or not sv.profiles or not sv.profiles[mgmtProfile] then return end
    -- Find a unique name
    local base = mgmtProfile .. " Copy"
    local candidate = base
    local i = 1
    local taken = {}
    for _, name in ipairs(db:GetProfiles()) do taken[name] = true end
    while taken[candidate] do
        i = i + 1
        candidate = base .. " " .. i
    end
    -- Deep copy the profile data
    sv.profiles[candidate] = bf:DeepCopy(sv.profiles[mgmtProfile])
    print("|cffd3ff7dBuzzardFrames:|r Cloned " .. ui.MODULE_LABELS[mgmtModule]
        .. " profile \"" .. mgmtProfile .. "\" as \"" .. candidate .. "\".")
    mgmtProfile = candidate
    mgmtRename  = candidate
    RebuildMgmt(ctx)
end

local function MgmtDelete(ctx)
    local ui = UI()
    local db = MgmtDB()
    if not (ui and db and mgmtProfile) then return end
    db:DeleteProfile(mgmtProfile, true)
    print("|cffd3ff7dBuzzardFrames:|r Deleted " .. ui.MODULE_LABELS[mgmtModule]
        .. " profile \"" .. mgmtProfile .. "\".")
    mgmtProfile = nil
    mgmtRename  = ""
    RebuildMgmt(ctx)
end

local function ManagePage()
    local ui = UI()
    if not ui then return { groups = {} } end

    -- The Ace moduleSelect and profileSelect, in one card: nothing stood
    -- above them there either.
    local groups = {
        { preset = "form", fields = {
            { control = "dropdown", label = "Module",
              desc = "Select which module's profiles to manage.",
              width = 260,
              -- The Ace select's `sorting` was MODULE_KEYS, which is the
              -- order this list is written in.
              options = function()
                  local out = {}
                  for _, key in ipairs(ui.MODULE_KEYS) do
                      out[#out + 1] = { value = key, text = ui.MODULE_LABELS[key] }
                  end
                  return out
              end,
              get = function() return mgmtModule end,
              set = function(_, ctx, val)
                  mgmtModule  = val
                  mgmtProfile = nil
                  mgmtRename  = ""
                  RebuildMgmt(ctx)
              end },

            { control = "dropdown", label = "Profile",
              desc = "Select a profile to manage.",
              width = 260,
              hidden = function() return not mgmtModule end,
              options = function()
                  return mgmtModule and ProfileOptions(mgmtModule) or {}
              end,
              get = function() return mgmtProfile end,
              set = function(_, ctx, val)
                  mgmtProfile = val
                  mgmtRename  = val or ""
                  RebuildMgmt(ctx)
              end },
        }},
    }

    -- The Ace actionsHeader and the three actions under it -- renameInput,
    -- cloneButton, deleteButton and the deleteNote beneath them. Everything
    -- here carried `hidden = not mgmtProfile`, so with nothing selected
    -- the card simply is not built.
    if mgmtProfile then
        groups[#groups + 1] = {
            title  = ui.MODULE_LABELS[mgmtModule] .. " — " .. mgmtProfile,
            preset = "form",
            fields = {
                { control = "text", label = "Rename",
                  desc = "Type a new name and press Enter -- or the button in "
                      .. "the box -- to rename this profile.",
                  -- `submit`: the Accept button the text control draws in
                  -- the box once what is typed differs from what is stored.
                  -- Enter alone was the only way to commit, which is a
                  -- keystroke the reader has to know about -- and the one
                  -- box on the page whose neighbors are both buttons.
                  submit = "Rename",
                  width = 260,
                  get = function() return mgmtRename end,
                  set = function(_, ctx, val) MgmtRenameTo(val, ctx) end },

                { control = "button", label = "Clone",
                  desc = "Create a copy of this profile with a new name.",
                  onClick = function(_, ctx) MgmtClone(ctx) end },

                { control = "button", label = "Delete", danger = true,
                  desc = "Permanently delete this profile.",
                  -- Can't delete the currently active profile or Default.
                  disabled = function()
                      return MgmtIsActive() or mgmtProfile == "Default"
                  end,
                  onClick = function(_, ctx)
                      ctx.app:Confirm("Permanently delete "
                          .. ui.MODULE_LABELS[mgmtModule] .. " profile \""
                          .. mgmtProfile .. "\"? This cannot be undone.",
                          function() MgmtDelete(ctx) end)
                  end },

                -- The Ace deleteNote: why the button is grayed, shown
                -- only when it IS grayed.
                { control = "note", wide = true,
                  hidden = function()
                      return not MgmtIsActive() and mgmtProfile ~= "Default"
                  end,
                  text = function()
                      if mgmtProfile == "Default" then
                          return "The Default profile cannot be deleted."
                      end
                      return "The currently active profile cannot be deleted. "
                          .. "Switch to a different profile first."
                  end },
            },
        }
    end

    return { groups = groups }
end

-- ── Tab: Themes ────────────────────────────────────────────────

local function ThemesPage()
    local bf = BF()
    local ui = UI()
    local themes = bf and bf.THEMES
    if not (ui and type(themes) == "table") then return { groups = {} } end

    local groups = {
        -- The Ace themesHeader + themesDesc.
        { title = "Themes", preset = "bare", fields = {
            { control = "note", wide = true,
              text = "Themes apply a curated look to Raid/Party Frames, "
                  .. "Custom Frame Groups and Unit Frames. Sizes, positions, "
                  .. "sorting, tooltips, layouts, Aura Customizations and "
                  .. "Incoming Casts are never modified." },
        }},
    }

    for _, key in ipairs(ui.THEME_ORDER) do
        local theme = themes[key]
        if type(theme) == "table" then
            local fields = {
                -- The Ace shot_<key> description: an empty name carrying
                -- the screenshot at the size the Ace dialog drew it.
                { control = "note", wide = true, text = "",
                  image = theme.screenshot, imageWidth = 448, imageHeight = 224 },

                { control = "button", label = "Apply Theme",
                  desc = "Apply the " .. theme.name .. " to Raid/Party Frames, "
                      .. "Custom Frame Groups and Unit Frames.",
                  disabled = function()
                      return InCombatLockdown() or not theme.data
                  end,
                  -- BUZZARDFRAMES_APPLY_THEME lives in Options_Themes.lua
                  -- beside the two apply flows its buttons call, so it is
                  -- shown verbatim rather than re-declared here.
                  onClick = function()
                      StaticPopup_Show("BUZZARDFRAMES_APPLY_THEME", theme.name, nil, key)
                  end },
            }
            -- rawget: `data = nil` is the shipped state and means
            -- "awaiting values", which is exactly what this note says.
            if not rawget(theme, "data") then
                fields[#fields + 1] = { control = "note", wide = true,
                    text = "(Theme data not captured yet — use the snapshot tool below.)" }
            end
            groups[#groups + 1] = { title = theme.name, preset = "form", fields = fields }
        end
    end

    -- The Ace devHeader / devDesc / devSnapshot: the authoring tool that
    -- captures the current settings as a paste-ready `data` table.
    groups[#groups + 1] = { title = "Theme Authoring", preset = "form", fields = {
        { control = "note", wide = true,
          text = "Set up the addon to look exactly how the theme should, then "
              .. "capture the themed settings (global Raid/Party sections + "
              .. "Unit Frames, minus sizes/positions) as a paste-ready data "
              .. "table.\n\n|cffaaaaaaFrom Buffs, a theme takes Buff Settings "
              .. "and Big Defensive. From Debuffs it takes Debuffs, "
              .. "Dispellable Debuffs and Crowd Control. The Global Options "
              .. "groups, the Debuffs Sorting & Filtering block, the Show "
              .. "Buffs / Show Debuffs toggles, Private Auras, and everything "
              .. "stored in Aura Customizations (presets, whitelist/blacklist, "
              .. "containers) are left alone.|r" },
        { control = "button", label = "Copy Current Settings as Theme Data",
          onClick = function() UI().ShowThemeSnapshot() end },
    }}

    return { groups = groups }
end

-- ── Tab: Export ────────────────────────────────────────────────
--
-- Exports the currently-active namespace profiles of the user-selected
-- modules through BF:ExportProfileString (ProfileExport.lua).

-- One of the five include switches -- the Ace includeRaidPartyFrames,
-- includeAuraCustomizations, includeCustomFrameGroups, includeUnitFrames
-- and includeIncomingCasts toggles (Ace order 20-24). v93:
-- the setter materialises EVERY key, not just this one, so the stored
-- table is never half-populated for a direct reader.
local function ExportIncludeField(key, label, desc)
    return {
        control = "switch", label = label, desc = desc, wide = true,
        id = "exportInclude_" .. key,
        get = function() return UI().ResolveExportInclude()[key] end,
        set = function(_, _, val)
            local bf = BF()
            if not bf then return end
            local inc = UI().ResolveExportInclude()
            inc[key] = val
            bf.db.global.exportIncludeModules = inc
        end,
    }
end

local function ExportPage()
    return {
        groups = {
            -- The Ace exportDesc, exportName and exportButton.
            { preset = "form", fields = {
                { control = "note", wide = true,
                  text = "Export the currently-active profiles of one or more "
                      .. "modules as a text string you can share with others. "
                      .. "Recipients paste it into the Import tab on their "
                      .. "end.\n\nEach module toggle below controls whether "
                      .. "that module's active profile is included in the "
                      .. "exported string." },

                { control = "text", label = "Export Name",
                  desc = "This name is embedded in the export string and "
                      .. "pre-fills the recipient's Import tab. Leave blank to "
                      .. "use the default.",
                  width = 260,
                  id = "exportProfileName",
                  -- Committed when the focus leaves the box, not only on
                  -- Enter: the Export button reads the STORED value, and a
                  -- name typed and then clicked past was otherwise never
                  -- stored -- the string went out under the current profile
                  -- name (or the last name that had been committed). Same
                  -- fix as the Import tab's Profile Name field.
                  commitOnBlur = true,
                  get = function()
                      local bf = BF()
                      return bf and bf.db.global.exportProfileName or ""
                  end,
                  -- The Ace widget's `validate` refused '[' and ']'. The
                  -- panel has no validate, so the refusal happens here, in
                  -- the one place that can still decline to write: the
                  -- header format is "[=== <n> profile ===]" and the
                  -- recipient extracts the name with a %[(.-)%] pattern, so
                  -- a user-supplied bracket would truncate that capture.
                  -- The message is the Ace one, said the way this addon
                  -- says everything else that went wrong.
                  set = function(_, _, val)
                      local bf = BF()
                      if not bf then return end
                      if type(val) == "string"
                         and (val:find("[", 1, true) or val:find("]", 1, true)) then
                          print("|cffff4444BuzzardFrames:|r Export name cannot "
                              .. "contain '[' or ']' characters.")
                          return
                      end
                      bf.db.global.exportProfileName = val or ""
                  end },

                { control = "button", label = "Export",
                  desc = "Export the checked modules' active profiles to a "
                      .. "text string you can copy.",
                  -- Disabled ONLY when zero modules are checked. Resolved
                  -- through ResolveExportInclude so this can never
                  -- disagree with the checkboxes (v93).
                  disabled = function()
                      local inc = UI().ResolveExportInclude()
                      for _, key in ipairs(UI().MODULE_KEYS) do
                          if inc[key] then return false end
                      end
                      return true
                  end,
                  onClick = function()
                      local bf = BF()
                      local ui = UI()
                      if not (bf and ui) then return end
                      -- The registry-driven exporter (sparse portable
                      -- build + "!4!" envelope, ProfileExport.lua).
                      local data = bf:ExportProfileString(ui.ResolveExportInclude(),
                          bf.db.global.exportProfileName)
                      -- v93: length in the status bar. Export strings are
                      -- pasted into places with hard length caps, and
                      -- "did that change actually make it shorter" should
                      -- be a number rather than an impression.
                      local n = #data
                      local pretty = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                      ui.ShowSerializeFrame(
                          "Modular profile export (paste into another character's Import tab)",
                          pretty .. " characters  --  press CTRL-C to copy the text to your clipboard",
                          data
                      )
                  end },
            }},

            -- The Ace includeHeader / includeDesc and the five toggles.
            { title = "Include Modules", preset = "form", fields = {
                { control = "note", wide = true,
                  text = "Choose which modules' active profiles to include in "
                      .. "the exported string." },
                ExportIncludeField("RaidPartyFrames", "Raid/Party Frames",
                    "Include the currently-active Raid/Party Frames profile in the export."),
                ExportIncludeField("AuraCustomizations", "Aura Customizations",
                    "Include the currently-active Aura Customizations profile in the export. Includes Buff & Debuff Containers and Buff List Customizations."),
                ExportIncludeField("CustomFrameGroups", "Custom Frame Groups",
                    "Include the currently-active Custom Frame Groups profile in the export."),
                ExportIncludeField("UnitFrames", "Unit Frames",
                    "Include the currently-active Unit Frames profile in the export."),
                ExportIncludeField("IncomingCasts", "Incoming Casts",
                    "Include the currently-active Incoming Casts profile in the export."),
            }},
        },
    }
end

-- ── Tab: Import ────────────────────────────────────────────────
--
-- Accepts a pasted export string, lets the user pick which modules to
-- import and a profile name, then writes a new namespace profile entry
-- per selected module. Non-destructive: existing profiles are untouched.
--
-- Flow:
--   1. Paste the string into the box.
--   2. Committing it decodes it. On failure, an error appears.
--   3. On success, per-module switches + name input + Import button
--      appear (all present modules checked by default, name pre-filled
--      from the string's header).
--   4. Import. Each selected module gets a new namespace profile entry
--      under a disambiguated name.
--
-- Everything below the box reads ProfilesUI.importState rather than
-- SavedVariables, because the pasted string and decoded intermediate are
-- session-transient.

local function NoDecode()
    return not UI().importState.decoded
end

-- One of the five import switches (the Ace include<Key> toggles). Each is
-- shown only if the decoded string actually carries that module.
local function ImportIncludeField(key, label)
    return {
        control = "switch", label = label, wide = true,
        id = "importInclude_" .. key,
        hidden = function()
            local st = UI().importState
            return not st.decoded or type(st.decoded[key]) ~= "table"
        end,
        get = function() return UI().importState.include[key] == true end,
        set = function(_, _, val) UI().importState.include[key] = val end,
    }
end

local function ImportPage()
    local ui = UI()
    if not ui then return { groups = {} } end
    local st = ui.importState

    return {
        groups = {
            -- The Ace importDesc and pasteBox; the Ace resetButton is the
            -- box's own clear X.
            { preset = "form", fields = {
                { control = "note", wide = true,
                  text = "Paste an exported profile string below and click "
                      .. "Accept. The profile information will be decoded. You "
                      .. "can then select which modules to import and rename "
                      .. "the profile, then click Import.\n\nImporting creates "
                      .. "new profiles for the selected modules. Your current "
                      .. "profile settings will not be overwritten." },

                -- The Ace pasteBox: input, width "full", multiline = 10.
                -- `submit = "Accept"` is the AceGUI multi-line box's own
                -- Accept button, drawn once the box differs from what is
                -- stored; Enter accepts too.
                { control = "text", label = "Paste Export String",
                  desc = "Paste the full exported string here and click Accept. "
                      .. "The string will be decoded automatically.",
                  wide = true, multiline = 10, submit = "Accept", clear = true,
                  id = "importPaste",
                  get = function() return st.pasted end,
                  -- The box's clear X is the Ace Reset button: emptying
                  -- the box commits "", and an empty commit clears the
                  -- pasted string, the decoded contents and the name input
                  -- -- exactly what Reset did -- rather than decoding
                  -- nothing and reporting an error for it.
                  set = function(_, ctx, val)
                      val = val or ""
                      if val:match("^%s*$") then
                          ui.ResetImportState()
                      else
                          st.pasted = val
                          -- Auto-decode on commit so the user doesn't need
                          -- to click a separate Decode button.
                          ui.DecodeImportString(st.pasted)
                      end
                      -- Everything below is gated on the decode's result,
                      -- so the page is re-read whole.
                      ctx.app:RefreshPage()
                  end },
            }},

            -- The Ace errorHeader / errorText. The red stays: it is the
            -- decode's own message, quoted inside a note body.
            { title = "Error", preset = "bare",
              hidden = function() return not st.error end,
              fields = {
                { control = "note", wide = true,
                  text = function() return "|cffff4444" .. (st.error or "") .. "|r" end },
            }},

            -- The Ace containsHeader / containsDesc / decodeReport and
            -- the five module switches. §E.5: what the string carries,
            -- shown BEFORE anything is written.
            { title = "This string contains", preset = "form",
              hidden = NoDecode,
              fields = {
                { control = "note", wide = true,
                  text = "Uncheck any modules you don't want to import." },
                { control = "note", wide = true,
                  hidden = function() return not (st.decoded and st.report) end,
                  text = function()
                      local r = st.report
                      if not r or r == "" then return "" end
                      return "|cffd3ff7d" .. r .. "|r"
                  end },
                ImportIncludeField("RaidPartyFrames", "Raid/Party Frames"),
                ImportIncludeField("AuraCustomizations", "Aura Customizations"),
                ImportIncludeField("CustomFrameGroups", "Custom Frame Groups"),
                ImportIncludeField("UnitFrames", "Unit Frames"),
                ImportIncludeField("IncomingCasts", "Incoming Casts"),
            }},

            -- The Ace nameHeader / nameInput / importButton.
            { title = "Import as profile name", preset = "form",
              hidden = NoDecode,
              fields = {
                { control = "text", label = "Profile Name",
                  desc = "The name that each selected module's imported data "
                      .. "will be saved as. If this name already exists in any "
                      .. "selected module, a numeric suffix will be appended "
                      .. "automatically.",
                  width = 260,
                  id = "importName",
                  -- Committed when the focus leaves the box, not only on
                  -- Enter: the Import button beside it reads this value,
                  -- and a name typed and then clicked past was otherwise
                  -- never stored -- the import went out under the name
                  -- the string arrived with, disambiguated to "Default 2".
                  commitOnBlur = true,
                  get = function() return st.name end,
                  set = function(_, _, val) st.name = val or "" end },

                { control = "button", label = "Import",
                  desc = "Create a new profile in each selected module with "
                      .. "the imported data.",
                  disabled = function()
                      if not st.decoded then return true end
                      if st.name:match("^%s*$") then return true end
                      for _, key in ipairs(ui.MODULE_KEYS) do
                          if st.include[key] then return false end
                      end
                      return true
                  end,
                  onClick = function(_, ctx)
                      ui.ImportDecodedProfile()
                      ctx.app:RefreshPage()
                  end },
            }},
        },
    }
end

-- ── The page entry point ───────────────────────────────────────
--
-- One function per the route wiring in Panel.lua (ProfilesRoutes ->
-- SubtabRoutes), which calls it with the subtab id and its title.
local PAGES = {
    general = GeneralPage,
    manage  = ManagePage,
    themes  = ThemesPage,
    export  = ExportPage,
    import  = ImportPage,
}

function BuzzardFramesOptions:ProfilesPage(id, title)   -- luacheck: ignore title
    local build = PAGES[id]
    if not build then return { groups = {} } end
    return build()
end
