-- ============================================================
-- BuzzardFramesOptions: Pages_ProfilesShared.lua
-- The Profiles section's PIPELINE, ported out of BuzzardFrames'
-- Options/Options_Profiles.lua (lines 20-1103) and the small authoring
-- helpers of Options_Themes.lua.
--
-- Pages_Profiles.lua is the five tabs; everything they DO lives here:
-- the legacy import decoders, the transient import state, the decode
-- report, the import committer, the export copy window, and the theme
-- snapshot serializer. It is a port rather than a call because these are
-- file-locals of an AceConfig builder -- nothing published them, so the
-- panel could not reach them -- and because the Ace file is deleted once
-- this section is migrated. Everything that IS published on
-- BuzzardFrames is called instead of copied: BF:ExportProfileString /
-- BF:DecodeProfileString (ProfileExport.lua), BF:DeepMergeProfile,
-- BF:RehydrateFlats, the five OnXProfileChanged handlers, and the theme
-- engine (BF.THEMES, BF:BuildThemeSnapshot,
-- BF:ApplyThemeToCurrentProfiles, BF:ApplyThemeAsNewProfiles).
--
-- Storage: none of its own. The import writes through each module's own
-- AceDB (db:SetProfile + BF:DeepMergeProfile), the export include set
-- lives in BuzzardFrames.db.global.exportIncludeModules, and the pasted
-- string / decoded intermediate are session-transient file state, not
-- config -- exactly as in the Ace file. Both panels resolve the include
-- set through ResolveExportInclude and write the same db.global key,
-- which is what keeps the two in step while both exist.
--
-- NOTHING AT FILE SCOPE READS BuzzardFrames. `BF()` is called inside the
-- functions, after the panel is open -- see the note at the top of
-- Panel.lua for why that is not belt-and-braces. The pure helpers
-- (the decoders, the scrubber, the Lua serializer) are functions of
-- their arguments and name the addon nowhere at all.
-- ============================================================
local BuzzardFramesOptions = _G.BuzzardFramesOptions

local function BF() return _G.BuzzardFrames end

-- ── The post-import reload prompt ──────────────────────────────
--
-- v94's BUZZARDFRAMES_RELOAD_IMPORT, same name and same wording. The
-- post-merge resync (ImportDecodedProfile) re-runs each module's
-- profile-changed handler, which is the same path a normal profile switch
-- takes and applies the great majority of an imported profile live -- but
-- "the majority" is not "all": anything stamped onto a frame at creation,
-- or read once at load, only follows a reload. Owner call: always offer
-- it, rather than trying to detect which imported keys need it.
--
-- DEFINED LAZILY, AND ONLY IF ABSENT. The Ace file still loads while both
-- panels exist and defines this dialog itself, so re-declaring it at file
-- scope would be two answers to one question -- and the later of the two
-- would win by load order, which is not a thing to decide a popup's text
-- by. Lazy also means this file touches no global table while loading, so
-- it loads under a harness that has no StaticPopupDialogs at all.
local function EnsureReloadPopup()
    local dialogs = _G.StaticPopupDialogs
    if type(dialogs) ~= "table" then return end
    if dialogs["BUZZARDFRAMES_RELOAD_IMPORT"] then return end
    dialogs["BUZZARDFRAMES_RELOAD_IMPORT"] = {
        text         = "BuzzardFrames: Profile imported.\n\nReload the UI to make sure every imported setting is applied?",
        button1      = "Reload Now",
        button2      = "Later",
        OnAccept     = function() ReloadUI() end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- ============================================================
-- LEGACY IMPORT DECODERS (decode-only)
-- ============================================================
-- Everything down to ExtractProfileName exists to IMPORT flat-era
-- strings: hex body (pre-v93) and "!2!" Base64 body (v93, _format 2/3
-- incl. the flat delta). The matching ENCODERS are gone -- the Export
-- button runs BF:ExportProfileString ("!4!"), and its decoder lives
-- there too. Nothing here writes a string any more.

-- ── v93 body encoding (format "!2!"), DECODE side only ──────────────────
-- v93 exports wrapped an AceSerializer -> LibCompress:Compress payload in
-- Base64 (standard alphabet, = padding) between the legacy
-- "[=== <name> profile ===]" header lines, with the "!2!" marker leading
-- the body. UnserializeProfile branches on that marker; hex bodies take
-- the pre-v93 path.
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP  -- built lazily: char byte -> 6-bit value

-- Returns (decodedString) or (false, errorMessage). Mirrors HexDecode's shape.
local function Base64Decode(s)
    if not B64_LOOKUP then
        B64_LOOKUP = {}
        for k = 1, 64 do
            B64_LOOKUP[string.byte(B64_CHARS, k)] = k - 1
        end
    end
    s = s:gsub("%[.-%]", ""):gsub("^%s*!2!", ""):gsub("%s+", "")
    s = s:gsub("!2!", "")
    s = s:gsub("=+$", "")
    if #s == 0 then return false, "Empty export body" end
    local byte, char, concat = string.byte, string.char, table.concat
    local t = {}
    local acc, bits = 0, 0
    for i = 1, #s do
        local v = B64_LOOKUP[byte(s, i)]
        if not v then
            return false, "Invalid character in export string"
        end
        acc = acc * 64 + v
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local div = 2 ^ bits
            local b = math.floor(acc / div)
            acc = acc - b * div
            t[#t + 1] = char(b)
        end
    end
    return concat(t)
end

-- Plain hexadecimal decoding.
local function HexDecode(s)
    s = s:gsub("%[.-%]", ""):gsub("[^0123456789ABCDEF]", "")
    if #s == 0 or #s % 2 ~= 0 then return false, "Invalid hex string" end
    local b_lshift = bit.lshift
    local byte     = string.byte
    local char     = string.char
    local t = {}
    local i = 1
    repeat
        local bl = byte(s, i)
        bl = bl >= 65 and bl - 55 or bl - 48
        i = i + 1
        local bh = byte(s, i)
        bh = bh >= 65 and bh - 55 or bh - 48
        i = i + 1
        t[#t + 1] = char(b_lshift(bh, 4) + bl)
    until i >= #s
    return table.concat(t)
end

-- ============================================================
-- PROFILE SCRUB (import side)
-- ============================================================
-- AceDB profile tables carry DERIVED RUNTIME STATE alongside real settings,
-- and some of that state is not serializable at all:
--
--   flat._auraCache      Auras/AuraConfig.lua RebuildAuraCacheScope. Holds
--                        cache.expiringCurveBuff / Debuff / BigDef, which are
--                        C_CurveUtil.CreateColorCurve() objects -- USERDATA.
--                        AceSerializer throws "Cannot serialize a value of
--                        type 'userdata'" the moment it walks into one.
--   flat._sectionCache   Core_ProfileAPI.lua GetCachedSection. Holds
--                        CROSS-DB references (a cfgDB flat's entry can point
--                        at an rpDB section), which deserialize on the far
--                        side as detached duplicates.
--   flat._stash          Core_Migrations.lua scratch.
--
-- Every one of these is rebuilt on demand (UpdateAuraSizeCache /
-- InvalidateRaidProfileCache), so dropping them loses nothing.
--
-- ScrubProfile deep-copies a profile table, skipping those keys and skipping
-- any value AceSerializer cannot represent (userdata, functions, threads) --
-- so a future runtime stamp we have not thought of degrades into a missing
-- key instead of a hard error. Cycles are cut.
--
-- pairs() sees only raw keys, exactly like the serializer did, so a sparse
-- flat still resolves through its defaults metatable on the receiving end
-- (see RehydrateFlats, Core_FlatDefaults.lua).
local RUNTIME_PROFILE_KEYS = {
    _auraCache    = true,
    _sectionCache = true,
    _stash        = true,
    -- Retired runtime flag (2026-08-24, see ProfileExport.lua
    -- RUNTIME_KEYS -- keep the two lists in sync): swept from saved data
    -- by migration 76, but a legacy string exported before the sweep
    -- can still carry it.
    _bf_hasSotFSpell = true,
}

local function ScrubValue(value, seen, stats)
    local vt = type(value)
    if vt == "string" or vt == "number" or vt == "boolean" then
        return value
    end
    if vt ~= "table" then
        -- userdata / function / thread: unserializable, drop it.
        stats.values = stats.values + 1
        return nil
    end
    if seen[value] then
        stats.cycles = stats.cycles + 1
        return nil
    end
    seen[value] = true
    local copy = {}
    for k, v in pairs(value) do
        local kt = type(k)
        if RUNTIME_PROFILE_KEYS[k] then
            stats.caches = stats.caches + 1
        elseif kt == "string" or kt == "number" then
            local scrubbed = ScrubValue(v, seen, stats)
            if scrubbed ~= nil then copy[k] = scrubbed end
        else
            -- boolean/table/userdata keys cannot round-trip; drop the pair.
            stats.values = stats.values + 1
        end
    end
    seen[value] = nil
    return copy
end

-- Public entry point. Returns a scrubbed deep copy plus a stats table
-- { caches, values, cycles }. Never returns the original table.
local function ScrubProfile(tbl)
    local stats = { caches = 0, values = 0, cycles = 0 }
    if type(tbl) ~= "table" then return nil, stats end
    return ScrubValue(tbl, {}, stats), stats
end

-- Accumulate scrub stats across the modules of one import and report
-- anything unexpected. Dropped runtime caches are normal and stay silent;
-- a dropped VALUE or a cycle means something stamped state onto a profile
-- that has no business being there, so surface it under the debug gate.
local function ReportScrub(stats, what)
    local bf = BF()
    if (stats.values > 0 or stats.cycles > 0) and bf
       and bf.IsDebugOutputEnabled and bf:IsDebugOutputEnabled() then
        print(string.format(
            "|cffd3ff7dBuzzardFrames:|r %s dropped %d unserializable value(s) and %d cyclic reference(s).",
            what, stats.values, stats.cycles))
    end
end

-- Full decode pipeline for the frozen flat-era formats.
-- Returns (true, decoded_table) on success, (false, error_message) on failure.
local function UnserializeProfile(data)
    local Compressor = LibStub("LibCompress")
    local decoded, decompressed, err, decErr
    -- v93: two body formats. "!2!" = Base64 + LibCompress:Compress (method
    -- auto-detected by Decompress from its leading method byte). Anything else
    -- is a pre-v93 string: hex + CompressHuffman. Kept indefinitely -- export
    -- strings live in forum posts and pastebins, and breaking old ones to save
    -- twenty lines here would be a poor trade.
    if data:find("!2!", 1, true) then
        decoded, err = Base64Decode(data)
        if not decoded then
            return false, err or "Base64 decode failed"
        end
        decompressed, decErr = Compressor:Decompress(decoded)
    else
        decoded, err = HexDecode(data)
        if not decoded then
            return false, err or "Hex decode failed"
        end
        decompressed, decErr = Compressor:DecompressHuffman(decoded)
    end
    if not decompressed then
        return false, "Decompression failed: " .. tostring(decErr or "unknown error")
    end
    local Serializer = LibStub("AceSerializer-3.0")
    local ok, result = Serializer:Deserialize(decompressed)
    if not ok then
        return false, "Deserialization failed: " .. tostring(result or "unknown error")
    end
    return true, result
end

-- Extract the profile name from the `[=== <n> profile ===]` header that
-- the encoder writes. Returns the trimmed name, or nil if the string is
-- missing / malformed.
local function ExtractProfileName(data)
    local header = string.sub(data, 1, 64)
    local name = (header:match("%[(.-)%]") or header):gsub("=", ""):gsub("profile", ""):trim()
    if name ~= "" then
        return name
    end
end

-- ============================================================
-- v93: FLAT-LAYOUT DELTA (_format 3) -- DECODE side only
-- ============================================================
-- The ENCODE half is gone -- format 4 ships sparse FULL flats. What
-- remains rebuilds layouts.flatLayouts from a v93 string's delta shape:
--     _flatBase   = <the chosen base flat, in full>
--     _flatBaseID = <its flatID, so it can be rebuilt in place>
--     _flatDiffs  = { [flatID] = { set = {..}, del = { "key", ... } } }
--
-- WHY THE BASE TRAVELS IN THE STRING: it would be smaller to diff against
-- the addon's DEFAULTS, and that was rejected deliberately (owner ruling).
-- A default that changes in a later version would silently reconstruct an
-- old export into a DIFFERENT profile, with nothing to tell the user. The
-- base being carried inline makes reconstruction depend only on the string.
--
-- DELETIONS ARE A LIST, NOT A SENTINEL. A key present in the base but
-- absent from a flat is named in `del`. An in-band "this key is deleted"
-- token would have to be a value, and any value can in principle collide
-- with a real stored value; a separate list cannot.
--
-- ALIASING: reconstruction deep-copies the base per flat, so flats never
-- share sub-tables.
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, val in pairs(v) do o[k] = DeepCopy(val) end
    return o
end

-- Rebuild a flat: deep copy of the base, then apply del then set. A `set`
-- value marked _sub recurses (the encoder marked string-keyed sub-table
-- diffs that way); everything else lands wholesale as a deep copy.
local function ApplyDiff(base, d)
    local out = DeepCopy(base)
    if d then
        if d.del then
            for i = 1, #d.del do out[d.del[i]] = nil end
        end
        if d.set then
            for k, v in pairs(d.set) do
                if type(v) == "table" and v._sub then
                    out[k] = ApplyDiff(type(out[k]) == "table" and out[k] or {}, v)
                else
                    out[k] = DeepCopy(v)
                end
            end
        end
    end
    return out
end

-- Import side. Restores layouts.flatLayouts from the delta shape. Safe to
-- call on a _format 2 table: without _flatBase it does nothing.
local function DeltaDecodeFlats(rp)
    local layouts = rp and rp.layouts
    if type(layouts) ~= "table" or type(layouts._flatBase) ~= "table" then return end
    local base   = layouts._flatBase
    local baseID = layouts._flatBaseID
    local diffs  = layouts._flatDiffs or {}
    local flats  = {}
    if baseID then flats[baseID] = DeepCopy(base) end
    for id, d in pairs(diffs) do
        flats[id] = ApplyDiff(base, d)
    end
    layouts.flatLayouts = flats
    layouts._flatBase, layouts._flatBaseID, layouts._flatDiffs = nil, nil, nil
end

-- ============================================================
-- THE FIVE MODULES (dbVersion 18)
-- ============================================================
-- Each of the five modules has its own independent top-level AceDB. Each
-- module's profile selection is stored in that DB's own
-- profileKeys[charKey] and switched via the standard AceDB :SetProfile
-- API. The parent DB (BuzzardFramesDB) still exists but only holds
-- cross-cutting db.global state; its profile is not switched from this UI.
local MODULE_KEYS = { "RaidPartyFrames", "AuraCustomizations", "CustomFrameGroups", "UnitFrames", "IncomingCasts" }

-- v93 BUGFIX: ONE definition of "is this module included in the export".
--
-- db.global.exportIncludeModules started life nil (= everything on) and was
-- only ever written with the key the user just clicked, so after unticking a
-- single module the table held exactly one `false` and nothing else. The
-- widgets read that as "absent means ON" (inc.X ~= false) while the Export
-- button's disabled= and the old exporter read it as "absent means OFF"
-- (if inc.X then). Two consequences, both owner-reported or latent:
--   * Untick any one module -> no key is truthy -> the Export button grayed
--     out while four modules still showed ticked.
--   * Worse, and silent: an export taken in that state contained ONLY the
--     modules explicitly set true, so modules the UI showed as ticked were
--     dropped from the string with no indication.
-- Everything resolves through here, on the "absent means ON" rule the
-- checkboxes have always presented.
local function ResolveExportInclude()
    local bf = BF()
    local stored = bf and bf.db and bf.db.global and bf.db.global.exportIncludeModules
    local out = {}
    for _, key in ipairs(MODULE_KEYS) do
        out[key] = not (stored and stored[key] == false)
    end
    return out
end

local MODULE_LABELS = {
    RaidPartyFrames    = "Raid/Party Frames",
    AuraCustomizations = "Aura Customizations",
    CustomFrameGroups  = "Custom Frame Groups",
    UnitFrames         = "Unit Frames",
    IncomingCasts      = "Incoming Casts",
}
local MODULE_DB_FIELD = {
    RaidPartyFrames    = "rpDB",
    AuraCustomizations = "acDB",
    CustomFrameGroups  = "cfgDB",
    UnitFrames         = "ufDB",
    IncomingCasts      = "icDB",
}

-- The SavedVariables table name per module. AceDB has no rename API, so
-- Profile Management's Rename and Clone reach past it into the saved
-- variable itself (copy the profile under the new name, re-point
-- profileKeys, drop the old). The Ace page built this table inline twice,
-- once in each of those two handlers; named once here so the two cannot
-- disagree about a variable name.
local SV_NAMES = {
    RaidPartyFrames    = "BuzzardFramesRaidPartyFramesDB",
    AuraCustomizations = "BuzzardFramesAuraCustomizationsDB",
    CustomFrameGroups  = "BuzzardFramesCustomFrameGroupsDB",
    UnitFrames         = "BuzzardFramesUnitFramesDB",
    IncomingCasts      = "BuzzardFramesIncomingCastsDB",
}

-- ============================================================
-- MODULAR IMPORT STATE
-- ============================================================
-- File-local state for the Import tab. Populated when the paste box
-- commits, consumed by the Import button, and cleared when the Import
-- finishes or the user clicks Reset. Not persisted -- the pasted string
-- and decoded intermediate are transient session state, not config.
local importState = {
    pasted  = "",    -- paste box contents
    decoded = nil,   -- successful deserialize result (the config table)
    error   = nil,   -- human-readable message on decode failure
    name    = "",    -- user's input for the final profile name
    include = {},    -- MODULE_KEYS subset that will actually import
}

local function ResetImportState()
    importState.pasted      = ""
    importState.decoded     = nil
    importState.error       = nil
    importState.name        = ""
    importState.include     = {}
    importState.report      = nil
    importState.isNewFormat = nil
    -- v94: belt-and-braces. The flag is cleared at the end of the resync, but
    -- an unhandled error anywhere between SetProfile and there would otherwise
    -- leave it set for the rest of the session, silently suppressing the UF
    -- reload prompt on every later profile switch. Every import exit path --
    -- success, cancel, clear -- lands here.
    local bf = BF()
    if bf then bf._importPendingMerge = nil end
end

-- ── Phase L: legacy-key hygiene for import strings ─────────────────────────
-- Strips the pre-flat named-layout keys (BF.LEGACY_LAYOUT_KEYS, defined in
-- Core_Migrations.lua) PLUS the two migration sentinels from a
-- RaidPartyFrames table, and the dead raid40/30/20 buckets from a
-- UnitFrames table. Strings exported BEFORE Phase L still carry the keys,
-- and the import merge would faithfully write them into a cleaned profile.
-- Operates on scrubbed/decoded copies only -- never on a live profile
-- (live SavedVariables are cleaned once by the dbVersion-73 migration).
local function StripLegacyExportKeys(rpTable, ufTable)
    if type(rpTable) == "table" and type(rpTable.layouts) == "table" then
        local rpl = rpTable.layouts
        local keys = BF() and BF().LEGACY_LAYOUT_KEYS
        if keys then
            for _, key in ipairs(keys) do rpl[key] = nil end
        end
        -- The sentinels belong to the sending install and must not travel.
        -- Nilling them is INERT as of the v93 hotfix: StripLegacyLayoutData
        -- now mines only when layouts.layouts is actually present, and the
        -- loop above has already stripped that key from this copy -- so a
        -- sentinel-less imported profile can no longer arm the flat-wipe
        -- path. Do not restore the old sentinel-absence guard there.
        rpl._flatLayoutsMigrated       = nil
        rpl._roleSpecOverridesMigrated = nil
    end
    if type(ufTable) == "table" and type(ufTable.ufLayouts) == "table" then
        for _, layout in pairs(ufTable.ufLayouts) do
            if type(layout) == "table" then
                layout.raid40 = nil
                layout.raid30 = nil
                layout.raid20 = nil
            end
        end
    end
end

-- §E.5: the pre-import report. Built once per successful decode and shown
-- under the module checkboxes, so the user sees what a pasted string
-- actually contains BEFORE anything is written. Counting only -- never
-- mutates `decoded`. Format is owner-specified (2026-08-24): five plain
-- lines, no caveat text.
--   "Buff Containers"     = multi-icon custom buff containers
--   "Buff Customizations" = Single Buff entries carrying user changes:
--                           whole-travelling single buffs plus curated
--                           diffs (empty presence markers are pristine
--                           and deliberately NOT counted)
--   "Debuff Containers"   = customDebuffContainers entries (these DO
--                           travel with the Aura Customizations module)
local function BuildDecodeReport(decoded)
    local lines = {}

    local rp = decoded.RaidPartyFrames
    if type(rp) == "table" then
        local flats = type(rp.layouts) == "table" and rp.layouts.flatLayouts
        local n = 0
        if type(flats) == "table" then
            for _ in pairs(flats) do n = n + 1 end
        end
        lines[#lines + 1] = ("Raid/Party Frames: %d Layouts"):format(n)
    end

    local ac = decoded.AuraCustomizations
    if type(ac) == "table" then
        local nContainers, nCustomized = 0, 0
        if type(ac.sbPortable) == "table" then
            for _, w in ipairs(ac.sbPortable.whole or {}) do
                if type(w.entry) == "table" then
                    if w.entry.singleBuff then
                        nCustomized = nCustomized + 1
                    else
                        nContainers = nContainers + 1
                    end
                end
            end
            for _, r in ipairs(ac.sbPortable.diffs or {}) do
                -- an empty diff is a presence marker for a pristine
                -- entry, not a customization
                if type(r.d) == "table" and next(r.d) ~= nil then
                    nCustomized = nCustomized + 1
                end
            end
        elseif type(ac.customBuffContainers) == "table" then
            for _, c in pairs(ac.customBuffContainers) do
                if type(c) == "table" then
                    if c.singleBuff then
                        nCustomized = nCustomized + 1
                    else
                        nContainers = nContainers + 1
                    end
                end
            end
        end
        local nDebuff = 0
        if type(ac.customDebuffContainers) == "table" then
            for _, c in pairs(ac.customDebuffContainers) do
                if type(c) == "table" then nDebuff = nDebuff + 1 end
            end
        end
        lines[#lines + 1] = ("Aura Customizations: %d Buff Containers, %d Buff Customizations, %d Debuff Containers")
            :format(nContainers, nCustomized, nDebuff)
    end

    local cfg = decoded.CustomFrameGroups
    if type(cfg) == "table" then
        local n = type(cfg.customFrameGroups) == "table" and #cfg.customFrameGroups or 0
        lines[#lines + 1] = ("Custom Frame Groups: %d"):format(n)
    end

    if type(decoded.UnitFrames) == "table" then
        lines[#lines + 1] = "Unit Frames Settings"
    end
    if type(decoded.IncomingCasts) == "table" then
        lines[#lines + 1] = "Incoming Casts Settings"
    end

    return table.concat(lines, "\n")
end

-- Attempt to decode a pasted modular export string. On success, populates
-- importState.decoded, importState.include (all present modules checked),
-- importState.report (§E.5 content summary shown in the UI), and
-- importState.name (from the header via ExtractProfileName). On
-- failure, populates importState.error and clears the rest.
--
-- TWO PIPELINES, ONE STATE:
--   * "!4!" in the body -> BF:DecodeProfileString (ProfileExport.lua): the
--     new envelope (EncodeForPrint + LibDeflate + AceSerializer, per-module
--     schema numbers). It returns the modules already flattened to the
--     decoded[moduleKey] shape everything below expects.
--   * anything else -> the FROZEN flat-era path unchanged: hex or "!2!"
--     body, LibCompress, _format 2/3, DeltaDecodeFlats, the §L.7 pre-flat
--     rejection and the §L.7 legacy-key strip. None of those apply to a
--     new-format string -- it cannot carry a delta or a legacy key -- so
--     they stay inside the legacy branch rather than running on both.
-- Either way, importState is populated identically and the Import flow is
-- untouched.
local function DecodeImportString(data)
    importState.decoded     = nil
    importState.error       = nil
    importState.name        = ""
    importState.include     = {}
    importState.report      = nil
    importState.isNewFormat = nil

    if type(data) ~= "string" or data:match("^%s*$") then
        importState.error = "Paste an exported profile string above, then click Decode."
        return
    end

    local bf = BF()
    if not bf then return end

    -- Look for the marker in the BODY only. The bracketed header carries a
    -- user-chosen profile name, and a name containing "!4!" would otherwise
    -- route a legacy string into the new decoder. No encoder's alphabet
    -- (hex, Base64, EncodeForPrint) contains "[", "]" or "!", so removing
    -- the headers first cannot hide a real marker.
    local isNewFormat = (bf.EXPORT_FORMAT_MARKER
        and data:gsub("%[.-%]", ""):find(bf.EXPORT_FORMAT_MARKER, 1, true)) and true or false

    local ok, result
    if isNewFormat then
        ok, result = bf:DecodeProfileString(data)
    else
        ok, result = UnserializeProfile(data)
    end
    if not ok then
        -- DecodeProfileString already returns a finished user-facing
        -- message; UnserializeProfile returns a bare reason.
        importState.error = isNewFormat and tostring(result)
            or ("Decode failed: " .. tostring(result))
        return
    end
    if type(result) ~= "table" then
        importState.error = "Decode failed: expected a table, got " .. type(result) .. "."
        return
    end

    if not isNewFormat then
        if result._format ~= 2 and result._format ~= 3 then
            importState.error = "This export string is from an older BuzzardFrames version and is no longer supported. Please re-export from the new version."
            return
        end
        -- v93: expand the flat-layout delta before anything downstream looks at
        -- layouts.flatLayouts. No-ops on a _format 2 string.
        if result._format == 3 then
            DeltaDecodeFlats(result.RaidPartyFrames)
        end

        -- Phase L (§L.7, owner decision 2026-08-23): REJECT pre-flat strings.
        -- A RaidPartyFrames module whose layouts table has no flatLayouts is a
        -- v17-v18 export -- its layout data lives in the retired
        -- layouts.layouts tier tables, imports never run migrations, and the
        -- owner ruled against a mine-on-import path. Abort the WHOLE import
        -- before anything is written: the user still has the string and no
        -- profile has been touched.
        local rpModule = result.RaidPartyFrames
        if type(rpModule) == "table" then
            local rpl = rpModule.layouts
            if type(rpl) ~= "table" or type(rpl.flatLayouts) ~= "table" then
                importState.error = "This export string is from an older BuzzardFrames version (before the flat layout system) and is no longer supported. Please re-export from the new version."
                return
            end
        end

        -- Phase L (§L.7): strip the pre-flat legacy keys and migration
        -- sentinels that flat-era strings exported before Phase L still carry,
        -- so importing an old string cannot reintroduce legacy data. The
        -- receiving profile keeps its OWN sentinels.
        StripLegacyExportKeys(result.RaidPartyFrames, result.UnitFrames)
    end

    -- Pre-check: at least one known module must be present.
    local any = false
    for _, key in ipairs(MODULE_KEYS) do
        if type(result[key]) == "table" then
            any = true
            importState.include[key] = true  -- all present modules checked by default
        end
    end
    if not any then
        importState.error = "Decoded string contains no recognized modules."
        return
    end

    importState.decoded     = result
    importState.name        = ExtractProfileName(data) or ""
    importState.isNewFormat = isNewFormat
    importState.report      = BuildDecodeReport(result)
end

-- Find a name that doesn't collide with any existing profile in any of the
-- selected namespaces: the first-available name wins, appending " 2",
-- " 3", etc. until unique across ALL selected namespaces simultaneously.
local function DisambiguateProfileName(baseName, include)
    baseName = (baseName ~= "" and baseName) or (UnitName("player") .. " - " .. GetRealmName())

    local function nameTaken(name)
        local bf = BF()
        for _, key in ipairs(MODULE_KEYS) do
            if include[key] then
                local db = bf and bf[MODULE_DB_FIELD[key]]
                if db then
                    for _, existing in ipairs(db:GetProfiles()) do
                        if existing == name then return true end
                    end
                end
            end
        end
        return false
    end

    local candidate = baseName
    local i = 1
    while nameTaken(candidate) do
        i = i + 1
        candidate = baseName .. " " .. i
    end
    return candidate
end

-- ── v94: import-time scope repair for container per-Layout overrides ──
--
-- A container's per-Layout settings live in c.groupSettings[<flatID>], and flat
-- IDs come from two disjoint namespaces that are only meaningful INSIDE ONE
-- PROFILE: rpDB's "flat_<n>" (user layouts) and cfgDB's "cfg_flat_<n>" (Custom
-- Frame Groups). Both are minted first-unused-slot, so the exporter's flat_3
-- and the receiver's flat_3 are different layouts wearing the same ID. The
-- import path copies groupSettings verbatim -- the whole-array replace for
-- customDebuffContainers, the sbPortable whole-entry append for buff
-- containers (ProfileExport.lua) -- and nothing remaps them. Silently, the
-- exporter's per-Layout overrides land on an unrelated layout of the
-- receiver's, or on a layout that does not exist here at all.
--
-- The repair is deliberately conservative: DROP the override, never guess a
-- mapping. A dropped sub-table collapses that container to its shared
-- top-level settings, which is both what the runtime already does with an
-- unresolvable key (ResolveGroupSource falls through) and the owner's
-- "per-Layout starts DISABLED for every imported container" ruling.
--
-- Kept:
--   * flat_party / flat_raid40 -- seeded by RehydrateFlats on every profile of
--     every install, so these two always denote the same layout;
--   * "flat_<n>" when RaidPartyFrames came in THIS import (the exporter's
--     flatLayouts arrived with it, so the ID still means what it meant there)
--     AND the flat is actually present after the merge;
--   * "cfg_flat_<n>" under the same rule against CustomFrameGroups.
-- Everything else goes, including IDs from a namespace this version does not
-- recognize -- a key nothing can resolve has no business outliving the import.
local BUILTIN_FLAT_IDS = { flat_party = true, flat_raid40 = true }

local function ScrubImportedContainerScopes()
    local bf  = BF()
    local acp = bf and bf.acDB and bf.acDB.profile
    if type(acp) ~= "table" then return end
    local inc = importState.include or {}
    local rpImported  = (inc.RaidPartyFrames == true)
    local cfgImported = (inc.CustomFrameGroups == true)
    local rpP   = bf.rpDB and bf.rpDB.profile
    local flats = rpP and rpP.layouts and rpP.layouts.flatLayouts

    local function KeepScope(id)
        if type(id) ~= "string" then return false end
        if BUILTIN_FLAT_IDS[id] then return true end
        if id:match("^cfg_flat_%d+$") then
            if not cfgImported then return false end
            if not bf.ResolveCFGGroupByFlatID then return false end
            return bf:ResolveCFGGroupByFlatID(id) ~= nil
        end
        if id:match("^flat_%d+$") then
            if not rpImported then return false end
            return type(flats) == "table" and flats[id] ~= nil
        end
        return false
    end

    local dropped = 0
    local arrays = { "customBuffContainers", "customDebuffContainers" }
    for ai = 1, #arrays do
        local containers = acp[arrays[ai]]
        if type(containers) == "table" then
            for i = 1, #containers do
                local c = containers[i]
                if type(c) == "table" and type(c.groupSettings) == "table" then
                    -- Assigning nil to an EXISTING field mid-pairs is the one
                    -- mutation the Lua manual permits during traversal.
                    for id in pairs(c.groupSettings) do
                        if not KeepScope(id) then
                            c.groupSettings[id] = nil
                            dropped = dropped + 1
                        end
                    end
                    if next(c.groupSettings) == nil then c.groupSettings = nil end
                end
            end
        end
    end
    if dropped > 0 then
        print(string.format(
            "|cffd3ff7dBuzzardFrames:|r Import: dropped %d per-Layout container "
            .. "override%s pointing at layouts this profile does not own.",
            dropped, dropped == 1 and "" or "s"))
    end
end

-- Commit the decoded import into new sub-profile entries in each selected
-- namespace: per module, SetProfile creates/switches to the destination
-- profile and the decoded data is then merged onto it. Runs on the module
-- namespaces directly rather than via a parent-profile cascade.
--
-- Namespace SetProfile does NOT cascade up to the parent. Under v18
-- each module DB fires its own OnProfileChanged; callbacks are routed
-- to BF:OnProfileChanged (see Core_DB.lua registration block). We do
-- NOT detach callbacks here because SetProfile(finalName) is followed
-- immediately by the merge before any user interaction, so a transient
-- RefreshAll between those two calls is harmless.
--
-- Each module's SetProfile+merge pair is wrapped in pcall so that
-- a failure on one module doesn't block the others. Failures are collected
-- and reported alongside the successes at the end of the loop.
--
-- The writer is BF:DeepMergeProfile, not a shallow key move. SetProfile
-- hands back a profile with the CURRENT defaults materialised; the merge
-- recurses string-keyed maps and only assigns leaves, so a sparse imported
-- sub-table no longer wipes its defaulted siblings. This applies to legacy
-- strings too -- one writer, one set of rules, for every format.
local function ImportDecodedProfile()
    if not importState.decoded then return end
    local bf = BF()
    if not bf then return end
    EnsureReloadPopup()

    local baseName = importState.name
    if baseName:match("^%s*$") then
        baseName = ""  -- DisambiguateProfileName will substitute a default
    end
    local finalName = DisambiguateProfileName(baseName, importState.include)

    local importedLabels = {}
    local failedLabels   = {}
    local scrubStats = { caches = 0, values = 0, cycles = 0 }
    -- v94: set for the whole SetProfile+merge window. Each db:SetProfile below
    -- fires that module's OnXProfileChanged against a profile the imported data
    -- has not reached yet; the flag tells the one handler that takes an
    -- IRREVERSIBLE action off the back of that (OnUFProfileChanged consuming
    -- _ufReloadSnapshot) to hold off. Cleared at the end of the resync below.
    bf._importPendingMerge = true
    for _, key in ipairs(MODULE_KEYS) do
        if importState.include[key] and type(importState.decoded[key]) == "table" then
            local db = bf[MODULE_DB_FIELD[key]]
            if db then
                -- Scrub on the way IN as well as on the way out -- LEGACY
                -- strings only (§E.7 step 5). An older export can still
                -- carry _auraCache / _sectionCache / _stash, and pouring a
                -- stale, foreign _auraCache onto a fresh profile would hand
                -- every flat a frozen copy of the exporter's derived state.
                -- A "!4!" string CANNOT: its builders are whitelist-driven
                -- and exclude runtime keys by construction, so scrubbing it
                -- again would only burn a deep copy (DeepMergeProfile
                -- already copies everything it assigns).
                local clean
                if importState.isNewFormat then
                    clean = importState.decoded[key]
                else
                    local s
                    clean, s = ScrubProfile(importState.decoded[key])
                    scrubStats.caches = scrubStats.caches + s.caches
                    scrubStats.values = scrubStats.values + s.values
                    scrubStats.cycles = scrubStats.cycles + s.cycles
                end
                -- §3.9.1: assert reconstruction ran BEFORE anything is
                -- written. Delta expansion happens at decode time for every
                -- module in the string, regardless of what the user ticked;
                -- a surviving _flatBase / _flatBaseID / _flatDiffs means it
                -- did not run for this module, and writing half-expanded
                -- data would produce a profile missing most of its settings
                -- with no error anywhere. Abort this module instead: the
                -- user still has the string and no profile is touched.
                local marker = bf.FindReconstructionMarker
                    and bf:FindReconstructionMarker(clean)
                if marker then
                    failedLabels[#failedLabels + 1] = MODULE_LABELS[key]
                        .. " (unexpanded \"" .. tostring(marker)
                        .. "\" data — nothing was written for this module; please re-export the string)"
                elseif key == "AuraCustomizations" and type(clean.sbPortable) == "table"
                       and not (bf._CuratedSBHelpers and bf.ApplySingleBuffPortable) then
                    -- §E.7c pre-flight: a schema-2 string needs the shared
                    -- curated helpers to reconstruct the Single Buffs. Bail
                    -- BEFORE SetProfile -- erroring after it would leave a
                    -- half-imported ACTIVE profile while reporting that
                    -- nothing was written (same doctrine as the marker
                    -- guard above). Should be unreachable in a normal
                    -- install; a load failure in Core_Migrations.lua is
                    -- what would get here.
                    failedLabels[#failedLabels + 1] = MODULE_LABELS[key]
                        .. " (curated Single Buff support unavailable — nothing was written for this module)"
                else
                    local ok, err = pcall(function()
                        db:SetProfile(finalName)
                        -- §E.7c (AC schema 2): the Single Buffs / container
                        -- array travels as sbPortable -- curated-entry diffs
                        -- plus whole non-curated entries -- NOT as profile
                        -- data. Pull it out before the merge, apply it
                        -- AFTER: its diffs land on the entries the fresh
                        -- profile's own curated mint created, and its c:N
                        -- remap and candidacy sweep need the merged
                        -- spellAssign in place. Schema-1 strings have no
                        -- sbPortable and take the plain merge unchanged.
                        local sbPortable, mergeSrc = nil, clean
                        if key == "AuraCustomizations" and type(clean.sbPortable) == "table" then
                            sbPortable = clean.sbPortable
                            -- Filtered VIEW, not a mutation. (`clean` is the
                            -- ScrubProfile copy, not importState.decoded
                            -- itself -- but keeping the source read-only here
                            -- costs one shallow table and removes any
                            -- dependence on that implementation detail.)
                            mergeSrc = {}
                            for k2, v2 in pairs(clean) do
                                if k2 ~= "sbPortable" then mergeSrc[k2] = v2 end
                            end
                        end
                        bf:DeepMergeProfile(mergeSrc, db.profile)
                        if sbPortable then
                            bf:ApplySingleBuffPortable(db.profile, sbPortable, finalName)
                        end
                    end)
                    if ok then
                        importedLabels[#importedLabels + 1] = MODULE_LABELS[key]
                    else
                        failedLabels[#failedLabels + 1] = MODULE_LABELS[key] .. " (" .. tostring(err) .. ")"
                    end
                end
            end
        end
    end

    -- Merge global colors from the export into rpDB.profile.colors.
    -- When an RP profile is imported, the module merge above has already
    -- written its .colors section. This handles the case where
    -- only non-RP modules were selected (e.g. UF-only import) -- the
    -- _globalColors sidecar still carries the exporter's gradient /
    -- class / power colors so they arrive on the recipient's machine.
    -- ScrubProfile doubles as the DEEP COPY here (the loop below must not
    -- alias importState.decoded's tables into the live profile), so it
    -- stays for both formats even though a "!4!" sidecar has nothing to
    -- scrub.
    local importedColors = ScrubProfile(importState.decoded._globalColors)
    if type(importedColors) == "table" then
        local rpP = bf.rpDB and bf.rpDB.profile
        if rpP then
            if not rpP.colors then rpP.colors = {} end
            for k, v in pairs(importedColors) do
                rpP.colors[k] = v
            end
        end
    end
    ReportScrub(scrubStats, "Import")

    -- Legacy backward compat: old exports (pre-independent-flat) bundled
    -- _baseLayouts containing the RP flat each CFG inherited from. Current
    -- exports no longer produce this (each CFG has its own deep-copied flat),
    -- but we still handle it for old export strings.
    local cfgP = bf.cfgDB and bf.cfgDB.profile
    if cfgP and cfgP._baseLayouts then
        local rpLayouts = bf.rpDB and bf.rpDB.profile and bf.rpDB.profile.layouts
        if rpLayouts then
            if not rpLayouts.flatLayouts then rpLayouts.flatLayouts = {} end
            local fl = rpLayouts.flatLayouts
            for flatID, flatData in pairs(cfgP._baseLayouts) do
                if not fl[flatID] then
                    fl[flatID] = flatData
                    local flatName = flatData.name or flatID
                    print("|cffd3ff7dBuzzardFrames:|r Imported base layout \"" .. flatName .. "\" (required by Custom Frame Group)")
                end
            end
        end
        cfgP._baseLayouts = nil  -- clean up; not a real profile key
    end

    -- Wire metatable __index templates on imported flats so un-customized
    -- keys fall through to defaults. Imported profiles land fully-
    -- materialized from the exporter; this makes them sparse-compatible
    -- on next logout, and ensures reads of un-customized keys resolve
    -- correctly if the exporter stripped anything default-equal.
    -- See Core_FlatDefaults.lua.
    if bf.RehydrateFlats then bf:RehydrateFlats() end
    if bf.RehydrateCFGFlats then bf:RehydrateCFGFlats() end

    -- No container per-Layout seed here. dbVersion 65 briefly seeded
    -- c.perLayoutConfig from the old section toggles at this point (the import
    -- path is the one entry the AceDB callbacks cannot cover), but the owner
    -- ruled 2026-08-15 that per-Layout starts DISABLED for every container and
    -- Single Buff -- imported ones included. See the
    -- _AuraMig_SeedContainerPerLayout tombstone in Core_Migrations.lua.

    -- ── v94: post-merge import resync ────────────────────────────────────
    -- Everything in this block runs AFTER BF:DeepMergeProfile, and that
    -- ordering is the entire point of it.
    --
    -- db:SetProfile(finalName) up in the module loop fires AceDB's
    -- OnProfileChanged, so every module's OnXProfileChanged handler
    -- (Core_ProfileLifecycle.lua) already ran -- against the FRESH, still-empty
    -- profile, before the imported data existed. Nothing re-ran them
    -- afterwards: refreshing the options panel re-READS values but neither
    -- regenerates the page nor touches the frames.
    --
    -- Two owner-reported symptoms, one cause:
    --   * an imported custom DEBUFF container had no subtab under Debuffs until
    --     a second container was added by hand (the create path calls
    --     BF:RebuildDebuffsContainerSubtabs, which re-enumerates the whole
    --     array, so the imported one finally showed up as "Custom 1" beside the
    --     new "Custom 2") -- OnACProfileChanged rebuilds those subtabs, and it
    --     had run too early;
    --   * imported Raid/Party settings such as frame orientation did not apply
    --     until a reload -- OnRPProfileChanged's RehydrateFlats ->
    --     ScrubInvalidSlotAssignments -> InvalidateRaidProfileCache ->
    --     RefreshAll chain, the very chain that makes a normal profile switch
    --     apply live, had likewise run too early.
    --
    -- So the resync is not a hand-picked list of refreshes: it re-fires each
    -- included module's profile-changed handler, i.e. it puts the import back
    -- on the same path a profile switch takes. The pre-merge pass is left in
    -- place rather than suppressed -- OnACProfileChanged's
    -- EnsureAurasMigratedForProfile has to mint the fresh profile's curated
    -- Single Buff rows BEFORE the merge or the schema-2 sbPortable diffs have
    -- nothing to land on (see ApplySingleBuffPortable) -- so every handler must
    -- stay safe to run twice. They are: the migrations are sentinel-guarded and
    -- the rest are refreshes.
    --
    -- Failures are REPORTED, not swallowed. A silent pcall here reads exactly
    -- like the fix having done nothing.
    local function ResyncStep(label, fn, ...)
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            print(string.format(
                "|cffff4444BuzzardFrames:|r Import resync step '%s' failed: %s",
                label, tostring(err)))
        end
    end

    -- Data repair first, so every rebuild below emits the repaired state.
    ResyncStep("container scopes", ScrubImportedContainerScopes)

    local RESYNC_HANDLERS = {
        RaidPartyFrames    = "OnRPProfileChanged",
        AuraCustomizations = "OnACProfileChanged",
        CustomFrameGroups  = "OnCFGProfileChanged",
        UnitFrames         = "OnUFProfileChanged",
        IncomingCasts      = "OnICProfileChanged",
    }
    for _, key in ipairs(MODULE_KEYS) do
        if importState.include[key] == true and bf[MODULE_DB_FIELD[key]] then
            local name = RESYNC_HANDLERS[key]
            ResyncStep(name, bf[name], bf)
        end
    end

    -- The import window is over. The snapshot is dropped unconsumed: the popup
    -- below is unconditional, so the UF reload-key comparison has nothing left
    -- to decide, and leaving a stale snapshot behind would make the NEXT real
    -- profile switch compare against a profile two switches old.
    bf._ufReloadSnapshot   = nil
    bf._importPendingMerge = nil

    if #importedLabels > 0 then
        print(string.format(
            "|cffd3ff7dBuzzardFrames:|r Imported as '%s': %s",
            finalName,
            table.concat(importedLabels, ", ")
        ))
    end
    if #failedLabels > 0 then
        print(string.format(
            "|cffff4444BuzzardFrames:|r Import failed for: %s",
            table.concat(failedLabels, ", ")
        ))
    end

    -- Owner call (2026-08-25): prompt after EVERY successful import, resync or
    -- no resync. Deferred a frame for the same reason OnUFProfileChanged defers
    -- its own: this runs inside a control's commit handler, and the panel's
    -- own post-write render is still mid-flight.
    if #importedLabels > 0 then
        C_Timer.After(0, function()
            StaticPopup_Show("BUZZARDFRAMES_RELOAD_IMPORT")
        end)
    end

    ResetImportState()
end

-- ── The copy window ────────────────────────────────────────────
--
-- The Ace file built its own AceGUI frame here (ShowSerializeFrame) with
-- two modes: show text for copying, or accept pasted text. Only the FIRST
-- mode is reachable from the panel -- pasting is an in-panel multiline
-- text field now, not a second window -- and BuzzardFrames already
-- publishes exactly that window as BF:ShowTextWindow (Core_OptionsBridge.
-- lua), which is where the eventual AceGUI removal is a one-file change.
-- So this is a call, not a second copy: same frame title, same status
-- line, same editbox label, same 525x375.
local function ShowSerializeFrame(title, subtitle, data)
    local bf = BF()
    if not (bf and bf.ShowTextWindow) then return end
    bf:ShowTextWindow("BuzzardFrames: Profile Import/Export", data, {
        status = subtitle,
        label  = title,
        width  = 525,
        height = 375,
    })
end

-- ============================================================
-- THEMES: the authoring helpers
-- ============================================================
-- The theme ENGINE stays in BuzzardFrames (BF.THEMES,
-- BF:BuildThemeSnapshot, BF:ApplyThemeToCurrentProfiles,
-- BF:ApplyThemeAsNewProfiles, and the BUZZARDFRAMES_APPLY_THEME popup).
-- What was file-local to the Ace builder, and so had to come across, is
-- the strip order and the "capture current settings" serializer.

-- The order the two themes are offered in, exactly as the Ace tab read
-- it: an array of THEMES keys, not the hash's own iteration order.
local THEME_ORDER = { "square", "glass" }

-- Serialize a snapshot as readable Lua source (sorted keys, stable
-- output) for pasting into a THEMES entry's `data` field.
local function LuaKey(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k .. " = " end
    if type(k) == "number" then return "[" .. tostring(k) .. "] = " end
    return "[" .. string.format("%q", tostring(k)) .. "] = "
end

local function LuaValue(v, indent, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{\n"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = indent .. "    " .. LuaKey(k)
            LuaValue(v[k], indent .. "    ", out)
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "number" then
        out[#out + 1] = string.format("%.14g", v)
    else
        out[#out + 1] = tostring(v)
    end
end

local function SerializeSnapshot(snap)
    local out = { "data = " }
    LuaValue(snap, "", out)
    out[#out + 1] = ",\n"
    return table.concat(out)
end

-- The Themes tab's "Copy Current Settings as Theme Data" button. The Ace
-- ShowSnapshotFrame was a second hand-built AceGUI window; like
-- ShowSerializeFrame above it goes through BF:ShowTextWindow, keeping the
-- title, the status line, the editbox label and the 560x420 size.
local function ShowThemeSnapshot()
    local bf = BF()
    if not (bf and bf.BuildThemeSnapshot and bf.ShowTextWindow) then return end
    bf:ShowTextWindow("BuzzardFrames: Theme Snapshot",
        SerializeSnapshot(bf:BuildThemeSnapshot()), {
            status = "Buffs/Debuffs are captured per raid (flat_raid40) and party (flat_party); other sections capture the globals only. Global Options, Sorting & Filtering, Show Buffs/Show Debuffs and everything in Aura Customizations are excluded.",
            label  = "Press CTRL-C to copy, then paste into the theme's `data` field in Options_Themes.lua",
            width  = 560,
            height = 420,
        })
end

-- ============================================================
-- What Pages_Profiles.lua uses
-- ============================================================
-- One table rather than a global per helper: the page file is the only
-- consumer, and a single published name is one thing to find when the Ace
-- file goes.
BuzzardFramesOptions.ProfilesUI = {
    MODULE_KEYS          = MODULE_KEYS,
    MODULE_LABELS        = MODULE_LABELS,
    MODULE_DB_FIELD      = MODULE_DB_FIELD,
    SV_NAMES             = SV_NAMES,
    ResolveExportInclude = ResolveExportInclude,
    importState          = importState,
    ResetImportState     = ResetImportState,
    DecodeImportString   = DecodeImportString,
    ImportDecodedProfile = ImportDecodedProfile,
    ShowSerializeFrame   = ShowSerializeFrame,
    THEME_ORDER          = THEME_ORDER,
    ShowThemeSnapshot    = function() ShowThemeSnapshot() end,
}
