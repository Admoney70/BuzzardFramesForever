-- TEMPORARY DIAGNOSTIC (2026-10-14): /bfpanediag
--
-- Prints the state of the Buff List entry pane's fixed header (the name,
-- Enabled switch and per-Layout strip above the subtab strip) so a blank
-- header can be measured in game rather than guessed at. Read-only: it
-- changes nothing. Remove (move to _to_delete/) once the blank-header bug
-- is fixed.

-- Output is collected and shown in BF's copyable text window (CLAUDE.md
-- rule: debug output goes in a copy-pasteable popup, never in chat).
local out = {}
local function emit(line) out[#out + 1] = line end

local function lvl(f) return f and f.GetFrameLevel and f:GetFrameLevel() or -1 end
local function vis(f) return f and f.IsVisible and (f:IsVisible() and "V" or "v") or "?" end
local function shw(f) return f and f.IsShown and (f:IsShown() and "S" or "s") or "?" end
local function alp(f)
    if not (f and f.GetAlpha) then return "?" end
    local e = f.GetEffectiveAlpha and f:GetEffectiveAlpha() or -1
    return string.format("%.2f/%.2f", f:GetAlpha(), e)
end
local function y(f)
    if not (f and f.GetTop) then return "?" end
    local t, b = f:GetTop(), f:GetBottom()
    return string.format("%s..%s", t and string.format("%.0f", t) or "nil",
                         b and string.format("%.0f", b) or "nil")
end
local function desc(f)
    return string.format("%s%s a=%s L=%d y=%s", shw(f), vis(f), alp(f), lvl(f), y(f))
end
local function n(v) return v and string.format("%.1f", v) or "nil" end
local function nm(f)
    if not f then return "nil" end
    if f == UIParent then return "UIParent" end
    return (f.GetName and f:GetName()) or tostring(f):gsub("table: ", "")
end
-- Geometry: left/right/width/height, scale, rect validity, and every anchor.
local function geo(tag, f)
    if not (f and f.GetLeft) then emit("      " .. tag .. " ?") return end
    local rv = f.IsRectValid and tostring(f:IsRectValid()) or "?"
    emit(("      %s %s L=%s R=%s T=%s B=%s w=%s h=%s sc=%s esc=%s rv=%s pts=%d"):format(
        tag, nm(f), n(f:GetLeft()), n(f:GetRight()), n(f:GetTop()), n(f:GetBottom()),
        n(f:GetWidth()), n(f:GetHeight()), n(f.GetScale and f:GetScale()),
        n(f.GetEffectiveScale and f:GetEffectiveScale()), rv, f:GetNumPoints()))
    for i = 1, f:GetNumPoints() do
        local p, rel, rp, x, yy = f:GetPoint(i)
        emit(("        pt%d %s -> %s %s %s,%s"):format(i, tostring(p), nm(rel), tostring(rp), n(x), n(yy)))
    end
end
local function within(f, root)
    local p, n = f, 0
    while p and n < 15 do
        if p == root then return true end
        p = p.GetParent and p:GetParent() or nil
        n = n + 1
    end
    return false
end

SLASH_BFPANEDIAG1 = "/bfpanediag"
SlashCmdList.BFPANEDIAG = function()
    local P = LibStub and LibStub("BuzzardPanel-1.0", true)
    local app = P and P:GetApp("BuzzardFrames")
    out = {}
    if not app then print("bfpanediag: options panel not open") return end
    emit("bfpanediag route=" .. table.concat(app.route or {}, "/"))
    for scope, g in pairs(app.paneScopes or {}) do
        if g and g.IsShown and g:IsShown() then
            emit(("card %s %s"):format(scope, desc(g)))
            emit("  body " .. desc(g.body) .. "  band L=" .. lvl(g.treePaneBand))
            emit("  pane " .. desc(g.treePane))
            emit("  head " .. desc(g.treeHead))
            emit("  scroll " .. desc(g.treeScroll) .. "  content " .. desc(g.treeContent))
            geo("head", g.treeHead)
            -- The first card in the scrolling part, which draws: the same
            -- numbers for a card that works, on the same screen.
            for _, lg in ipairs(app.liveGroups or {}) do
                if lg.GetParent and lg:GetParent() == g.treeContent then
                    emit("  contentcard " .. desc(lg))
                    geo("card", lg); geo("surf", lg.surface); geo("body", lg.body)
                    break
                end
            end
            local head = g.treeHead
            if head then
                local i = 0
                for _, lg in ipairs(app.liveGroups or {}) do
                    if lg.GetParent and lg:GetParent() == head then
                        i = i + 1
                        emit(("  headcard%d %s surf=%s bodyc=%s"):format(i, desc(lg),
                            desc(lg.surface), desc(lg.body)))
                        geo("card", lg); geo("surf", lg.surface); geo("body", lg.body)
                    end
                end
                for _, e in ipairs(app.liveFields or {}) do
                    local w = e.widget
                    if w and within(w, head) then
                        local n = e.node or {}
                        emit(("    field %s '%s' %s parent=%s"):format(
                            tostring(n.control), tostring(n.label or n.id or ""),
                            desc(w), tostring(w:GetParent() and w:GetParent():GetFrameLevel())))
                    end
                end
            end
        end
    end
    local text = table.concat(out, "\n")
    local bf = BuzzardFramesOptions and BuzzardFramesOptions.BF and BuzzardFramesOptions:BF()
    if not (bf and bf.ShowTextWindow and bf:ShowTextWindow("bfpanediag", text,
            { status = "Ctrl+C to copy", label = "", layout = "Fill",
              width = 760, height = 560 })) then
        print(text)
    end
end
