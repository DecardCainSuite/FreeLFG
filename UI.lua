-- Free LFG - window: Browse (search bar, live filter, sortable table), Options, Profiles.
-- One LibFreeUI window: free-standing (/flfg) or embedded in Free Hub.

local ADDON, ns = ...
local UI = LibStub("LibFreeUI-1.0")
local C = UI.C
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local kit = UI:New({ name = "FreeLFGWindow", title = "Free LFG", sub = "Looking for group", addon = ADDON,
                     icon = MEDIA .. "icon", circle = MEDIA .. "circle", shadow = MEDIA .. "shadow", w = 1000, h = 720,
                     subFn = function()
                         return "  ·  " .. #ns.view .. " of " .. #ns.rows .. " groups"
                     end })
ns.kit = kit

local frame
local tfs = {}            -- table texts: { fs, delta } so a font change can be re-applied
local rows, headBtns = {}, {}
local offset = 0
local layoutX = {}        -- [column key] = { x, w }
local statusText, statusBad = nil, false
local footerText

-- ------------------------------------------------------------ fonts
local function LFM() return LibStub and LibStub("LibFreeMedia-1.0", true) end
local function ApplyFont(fs, delta)
    local p = ns.P()
    local size = math.max(8, (p.fontSize or 12) + (delta or 0))
    local lib = LFM()
    if lib then
        lib:SetFont(fs, p.font, size, p.outline)
        lib:ApplyOutline(fs, p.outline)
    else
        UI.SetFont(fs, size)
    end
end
local function TText(parent, delta, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, delta)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(unpack(color or C.text))
    tfs[#tfs + 1] = { fs, delta or 0 }
    return fs
end
local function ReapplyFonts()
    for _, t in ipairs(tfs) do ApplyFont(t[1], t[2]) end
end

local function Status(text, bad) statusText, statusBad = text, bad and true or false; kit:Refresh() end

-- ------------------------------------------------------------ small widgets
local function MiniButton(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 16)
    b.bg = kit:Fill(b, C.control); b.bg:SetAllPoints()
    kit:Border(b, 0.10)
    b.label = kit:Text(b, 11, C.text); b.label:SetPoint("CENTER"); b.label:SetWordWrap(false); b.label:SetText(label)
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then s.bg:SetVertexColor(unpack(C.hover)) end; if s.tip then GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine(s.tip, 1, 1, 1, true); GameTooltip:Show() end end)
    b:SetScript("OnLeave", function(s) s.bg:SetVertexColor(unpack(C.control)); if s.tip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", onClick)
    hooksecurefunc(b, "SetEnabled", function(s, on) s:SetAlpha(on and 1 or 0.35) end)
    return b
end

local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }
local ROLE_COLOR = { TANK = { 0.45, 0.68, 1 }, HEALER = { 0.45, 0.90, 0.50 }, DAMAGER = { 1, 0.50, 0.42 } }
local function RoleIcon(tex, role)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ROLE_ATLAS[role])
    if hasAtlas and tex.SetAtlas then
        tex:SetAtlas(ROLE_ATLAS[role])
    else
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        local c = ROLE_COORDS[role]
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

-- ------------------------------------------------------------ tooltip
-- the classic GameTooltip version, kept as a fallback if the new tooltip (Tooltip.lua) fails
local function RowTooltipClassic(r)
    local row = r.row
    if not row then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    local cr, cg, cb = ns.ClassColor(row.class)
    GameTooltip:AddLine(row.leaderFull or row.leader, cr, cg, cb)
    local a = row.dungeon or "?"
    if row.level then a = a .. "  |cffaaaaaa(leader level " .. row.level .. ")|r" end
    GameTooltip:AddLine(a, 1, 1, 1, true)
    if row.title ~= "" then GameTooltip:AddLine(row.title, 1, 0.82, 0.4, true) end
    if row.comment ~= "" then GameTooltip:AddLine(row.comment, 0.85, 0.85, 0.85, true) end
    GameTooltip:AddLine(string.format("%d/%d members  ·  %d free  ·  %s", row.members, row.maxMembers, row.free, row.state or ""), 0.7, 0.72, 0.78)
    GameTooltip:AddLine(string.format("Tank %d   Healer %d   DPS %d", row.tank, row.heal, row.dps), 0.7, 0.72, 0.78)
    if not row.solo then GameTooltip:AddLine(string.format("Open: tank %d   healer %d   DPS %d", row.tankfree, row.healfree, row.dpsfree), 0.7, 0.72, 0.78) end
    if row.newPlayer then GameTooltip:AddLine("New player friendly", 0.55, 0.85, 0.55) end
    GameTooltip:AddLine("Listed for " .. ns.AgeText(row.ageSec), 0.7, 0.72, 0.78)
    if row.ilvl and row.ilvl > 0 then GameTooltip:AddLine("Item level " .. row.ilvl .. "+", 0.7, 0.72, 0.78) end
    if row.voice then GameTooltip:AddLine("Voice: " .. row.voice, 0.7, 0.72, 0.78, true) end
    local shown = 0
    for i = 1, math.min(row.members, 40) do
        local m = ns.MemberInfo(row.id, i)
        if m and (m.class or m.role) then
            if shown == 0 then GameTooltip:AddLine(" ") end
            shown = shown + 1
            if shown <= 12 then
                local mr, mg, mb = ns.ClassColor(m.class)
                local role = (m.role == "TANK" and "Tank") or (m.role == "HEALER" and "Healer") or (m.role == "DAMAGER" and "DPS") or ""
                GameTooltip:AddLine(string.format("%s%s  %s%s%s", m.classLoc or m.class or "?", (m.spec and m.spec ~= "") and (" (" .. m.spec .. ")") or "",
                    role, m.level and ("  lvl " .. m.level) or "", m.isLeader and "  |cffff8a3dleader|r" or ""), mr, mg, mb)
            end
        end
    end
    if shown > 12 then GameTooltip:AddLine("... and " .. (shown - 12) .. " more", 0.5, 0.5, 0.55) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Msg sends: " .. ns.ExpandTemplate(ns.P().template, row), 0.55, 0.75, 0.55, true)
    GameTooltip:Show()
end

local function RowTooltip(r)
    if not r.row then return end
    local ok, err = pcall(ns.ShowRowTooltip, r, r.row)
    if not ok then
        if ns.HideRowTooltip then ns.HideRowTooltip() end
        if not ns.tooltipErrorShown then ns.tooltipErrorShown = true; print("|cffff8a3dFree LFG|r: tooltip error, using the simple one (" .. tostring(err) .. ")") end
        RowTooltipClassic(r)
    end
end

-- ------------------------------------------------------------ build
local function Build()
    local pages, footer = kit:Build()
    frame = kit.frame
    local PAD = kit.PAD
    local LX, RX, COLW = kit.LX, kit.RX, kit.COLW
    local p = pages.browse

    -- the profile may change under us: filter box and fonts follow
    local relayout            -- forward

    -- ======================================================= search bar
    local function CatItems()
        local out = {}
        for _, c in ipairs(ns.Categories()) do out[#out + 1] = { key = c.id, label = c.name } end
        if #out == 0 then out[1] = { key = 0, label = "No category" } end
        return out
    end
    local catDD = kit:Dropdown(p, nil, PAD, -4, 170, CatItems,
        function() return ns.CurrentCategory() or 0 end,
        function(v)
            if v ~= ns.CurrentCategory() then   -- results of the old category no longer apply: wait for a new search
                for i = #ns.rows, 1, -1 do ns.rows[i] = nil end
                ns.total, ns.lastRead, ns.failed = 0, nil, false
            end
            ns.cat = v; ns.P().activitySel = {}; kit:Refresh()
        end, 0)
    catDD:ClearAllPoints(); catDD:SetPoint("TOPLEFT", PAD, -4); kit.flow[#kit.flow] = nil

    local function ActItems()
        local acc = C.accent
        local pr = ns.P()
        -- first the mode, then the activities of the category that match it (ticking only narrows the table)
        local lvlMode = pr.activityMode ~= "all"
        local out = { { key = "level", label = "Activities at my level", check = lvlMode, keepOpen = true },
                      { key = "all", label = "All activities", check = not lvlMode, keepOpen = true },
                      { sep = true } }
        for _, a in ipairs(ns.Activities(ns.CurrentCategory(), lvlMode)) do
            out[#out + 1] = { key = a.id, label = a.name .. (a.range and ("  |cff808590" .. a.range .. "|r") or ""),
                              check = pr.activitySel[a.id] and true or false, keepOpen = true }
        end
        return out
    end
    local actDD = kit:Dropdown(p, nil, PAD + 180, -4, 250, ActItems,
        function() return ns.ActivitySummary() end,   -- no item has this key: the box shows the text itself
        function(v) ns.ToggleActivity(v); kit:Refresh() end, 0)
    actDD:ClearAllPoints(); actDD:SetPoint("TOPLEFT", PAD + 180, -4); kit.flow[#kit.flow] = nil

    local bRefresh = kit:Button(p, "Refresh", 96, true, function()
        local ok, why = ns.Search()
        if ok then Status("Searching...") else Status(why, true) end
    end)
    bRefresh:SetPoint("TOPLEFT", PAD + 440, -3)
    local count = kit:Text(p, 12, C.dim); count:SetPoint("LEFT", bRefresh, "RIGHT", 12, 0); count:SetWordWrap(false)
    local stamp = kit:Text(p, 11, C.muted); stamp:SetPoint("TOPRIGHT", -PAD, -9); stamp:SetJustifyH("RIGHT")

    -- ======================================================= live filter
    local box = kit:InputBox(p, 300)
    box:SetPoint("TOPLEFT", PAD, -40); box:SetPoint("TOPRIGHT", -PAD - 34, -40)
    ns.filterBox = box
    local ph = kit:Text(box, 12, C.muted); ph:SetPoint("LEFT", 8, 0)
    ph:SetText("Filter the table as you type:  (heal >= 1 or tank >= 1) and dps <= 1")
    box:SetScript("OnTextChanged", function(s, userInput)
        local t = s:GetText() or ""
        ph:SetShown(t == "")
        -- SetText from our code may fire this a frame later: only typing applies the text here
        if s.syncing or userInput == false then return end
        ns.SetFilter(t)
        offset = 0
        kit:Refresh()
    end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    local help = MiniButton(p, "?", 24, function() end)
    help:SetSize(26, 24); help.label:SetText("?")
    help:SetPoint("TOPRIGHT", -PAD, -40)
    help:SetScript("OnEnter", function(s)
        s.bg:SetVertexColor(unpack(C.hover))
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Filter syntax", C.accent[1], C.accent[2], C.accent[3])
        for _, l in ipairs(ns.Filter.help) do GameTooltip:AddLine(l, 0.85, 0.85, 0.9, true) end
        GameTooltip:AddLine("The filter only changes this table, never the game's search.", 0.55, 0.75, 0.55, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function(s) s.bg:SetVertexColor(unpack(C.control)); GameTooltip:Hide() end)
    local err = kit:Text(p, 11, C.muted); err:SetPoint("TOPLEFT", PAD + 2, -68); err:SetPoint("TOPRIGHT", -PAD, -68)
    err:SetWordWrap(false)

    -- saved filters
    local selFilter                     -- index of the picked saved filter
    local function FilterItems()
        local out = {}
        for i, f in ipairs(ns.P().filters) do out[i] = { key = i, label = f.name, color = (i == selFilter) and C.accent or nil } end
        if #out == 0 then out[1] = { key = 0, label = "(none saved)" } end
        return out
    end
    local savedDD = kit:Dropdown(p, nil, PAD, -88, 230, FilterItems,
        function()
            local f = selFilter and ns.P().filters[selFilter]
            return f and selFilter or "Saved filters..."
        end,
        function(i)
            local f = ns.P().filters[i]
            if not f then return end
            selFilter = i
            ns.SetFilter(f.expr)
            box.syncing = true; box:SetText(f.expr); box.syncing = false; box:ClearFocus()
            offset = 0
            kit:Refresh()
        end, 0)
    savedDD:ClearAllPoints(); savedDD:SetPoint("TOPLEFT", PAD, -88); kit.flow[#kit.flow] = nil
    local nameBox = kit:InputBox(p, 170); nameBox:SetPoint("TOPLEFT", PAD + 240, -88); nameBox:SetHeight(26)
    local nph = kit:Text(nameBox, 11, C.muted); nph:SetPoint("LEFT", 8, 0); nph:SetText("name (optional)")
    nameBox:SetScript("OnTextChanged", function(s) nph:SetShown((s:GetText() or "") == "") end)
    local bSave = kit:Button(p, "Save filter", 96, false, function()
        local expr = box:GetText() or ""
        if expr:match("^%s*$") then Status("Type a filter first.", true); return end
        local name = nameBox:GetText() or ""
        if name:match("^%s*$") and selFilter and ns.P().filters[selFilter] then name = ns.P().filters[selFilter].name end
        selFilter = ns.SaveFilter(name, expr)
        nameBox:SetText(""); nameBox:ClearFocus()
        Status("Saved: " .. (selFilter and ns.P().filters[selFilter].name or "?"))
    end)
    bSave:SetPoint("TOPLEFT", PAD + 420, -87)
    local bDel = kit:Button(p, "Delete", 76, false, function()
        if selFilter and ns.DeleteFilter(selFilter) then selFilter = nil; Status("Filter deleted.") end
    end)
    bDel:SetPoint("LEFT", bSave, "RIGHT", 6, 0)
    local bClear = kit:Button(p, "Clear", 64, false, function() ns.SetFilter(""); box.syncing = true; box:SetText(""); box.syncing = false; box:ClearFocus(); selFilter = nil; kit:Refresh() end)
    bClear:SetPoint("LEFT", bDel, "RIGHT", 6, 0)

    -- ======================================================= table
    local COLS = ns.COLUMNS
    local HEAD_H = 24
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", PAD, -124); list:SetPoint("BOTTOMRIGHT", -PAD, 8)
    local lbg = kit:Fill(list, C.panel); lbg:SetAllPoints()
    kit:Border(list, 0.06)
    local head = CreateFrame("Frame", nil, list)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(HEAD_H)
    local hbg = kit:Fill(head, { 1, 1, 1, 0.04 }); hbg:SetAllPoints()
    for _, c in ipairs(COLS) do
        local b = CreateFrame("Button", nil, head)
        b:SetHeight(HEAD_H - 2)
        b.t = kit:Text(b, 12, C.dim); b.t:SetPoint("LEFT"); b.t:SetWordWrap(false)
        b.key = c.key
        if c.key ~= "actions" then
            b:SetScript("OnClick", function() ns.SetSort(c.key); offset = 0; kit:Refresh() end)
            b:SetScript("OnEnter", function(s) if ns.P().sortKey ~= c.key then s.t:SetTextColor(unpack(C.text)) end end)
            b:SetScript("OnLeave", function(s) if ns.P().sortKey ~= c.key then s.t:SetTextColor(unpack(C.dim)) end end)
        end
        headBtns[c.key] = b
    end

    -- slim orange scroll bar
    local track = kit:Fill(list, { 1, 1, 1, 0.06 }, "ARTWORK"); track:SetWidth(4)
    track:SetPoint("TOPRIGHT", -3, -HEAD_H - 2); track:SetPoint("BOTTOMRIGHT", -3, 2)
    local thumb = kit:Fill(list, C.accent, "ARTWORK", 2); thumb:SetWidth(4)

    local function RowHeight() return math.max(14, math.min(40, tonumber(ns.P().rowHeight) or 20)) end

    local function MakeRow()
        local r = CreateFrame("Button", nil, list)
        r.zebra = kit:Fill(r, { 1, 1, 1, 0 }); r.zebra:SetAllPoints()
        r.hl = kit:Fill(r, { 1, 1, 1, 0.06 }, "ARTWORK", 1); r.hl:SetAllPoints(); r.hl:Hide()
        r.c = {}
        for _, col in ipairs(COLS) do
            if col.key ~= "actions" and col.key ~= "roles" then r.c[col.key] = TText(r, 0, C.text) end
        end
        r.c.level:SetJustifyH("CENTER"); r.c.members:SetJustifyH("CENTER")
        -- roles: icon + count for tank / healer / dps, then the free slots
        r.role = {}
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            local ic = r:CreateTexture(nil, "ARTWORK"); ic:SetSize(14, 14)
            RoleIcon(ic, role)
            r.role[role] = { icon = ic, n = TText(r, 0, C.muted) }
        end
        r.free = TText(r, -1, C.muted)
        r.msg = MiniButton(r, "Msg", 44, function(s)
            local ok, res = ns.Whisper(r.row)
            if ok then Status("Whispered " .. r.row.leader .. ": " .. res)
            elseif res ~= "wait" then Status(res, true) end
        end)
        r.msg.tip = "Whisper the leader with your message template (see Options)."
        r.cus = MiniButton(r, "Custom", 56, function()
            local ok, res = ns.CustomWhisper(r.row)
            if ok then Status("Type your message to " .. r.row.leader .. " and press Enter.")
            else Status(res, true) end
        end)
        r.cus.tip = "Open a whisper to the leader starting with your custom start (see Options): type the rest, then Enter."
        r.inv = MiniButton(r, "Invite", 54, function()
            local ok, res = ns.Invite(r.row)
            if ok then Status("Invite sent to " .. r.row.leader)
            elseif res ~= "wait" then Status(res, true) end
        end)
        r.inv.tip = "Invite a solo player."
        -- "sent 3m 07s ago": my last whisper to this leader (Msg, or Custom once sent), 1.0.21
        r.sent = TText(r, -1, C.accent)
        r:SetScript("OnEnter", function(s) s.hl:Show(); RowTooltip(s) end)
        r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide(); if ns.HideRowTooltip then ns.HideRowTooltip() end end)
        return r
    end

    local function Layout()
        local pr = ns.P()
        local W = (list:GetWidth() or 900) - 14
        local fixed, vis = 0, {}
        for _, c in ipairs(COLS) do
            if pr.columns[c.key] then vis[#vis + 1] = c; if c.w > 0 then fixed = fixed + c.w end end
        end
        local flex = (pr.columns.comment and "comment") or (pr.columns.activity and "activity") or nil
        local flexW
        if flex then
            local base = 0
            for _, c in ipairs(vis) do if c.key == flex and c.w > 0 then base = c.w end end
            flexW = math.max(base > 0 and base or 80, W - 8 - (fixed - base))
        end
        local x = 8
        for k in pairs(layoutX) do layoutX[k] = nil end
        for _, c in ipairs(vis) do
            local w = (c.key == flex) and flexW or c.w
            layoutX[c.key] = { x = x, w = w }
            x = x + w
        end
    end
    ns.layoutX = layoutX

    local function PlaceRow(r, i, RH)
        r:SetHeight(RH)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -HEAD_H - (i - 1) * RH); r:SetPoint("TOPRIGHT", -9, -HEAD_H - (i - 1) * RH)
        r.zebra:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
        local pr = ns.P()
        for key, fs in pairs(r.c) do
            local L = layoutX[key]
            fs:ClearAllPoints()
            if L then fs:SetPoint("LEFT", L.x, 0); fs:SetWidth(math.max(8, L.w - 6)); fs:Show() else fs:Hide() end
        end
        local L = layoutX.roles
        local rx = L and L.x or 0
        for n, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            local e = r.role[role]
            e.icon:ClearAllPoints(); e.n:ClearAllPoints()
            e.icon:SetShown(L and true or false); e.n:SetShown(L and true or false)
            if L then
                e.icon:SetPoint("LEFT", rx + (n - 1) * 36, 0)
                e.n:SetPoint("LEFT", rx + (n - 1) * 36 + 16, 0); e.n:SetWidth(18)
            end
        end
        r.free:ClearAllPoints(); r.free:SetShown(L and true or false)
        if L then r.free:SetPoint("LEFT", rx + 108, 0); r.free:SetWidth(math.max(10, L.w - 108)) end
        local A = layoutX.actions
        r.msg:SetHeight(math.max(12, RH - 4)); r.cus:SetHeight(math.max(12, RH - 4)); r.inv:SetHeight(math.max(12, RH - 4))
        r.msg:ClearAllPoints(); r.cus:ClearAllPoints(); r.inv:ClearAllPoints()
        r.msg:SetShown(A and true or false); r.cus:SetShown(A and true or false); r.inv:SetShown(A and true or false)
        if A then r.msg:SetPoint("LEFT", A.x, 0); r.cus:SetPoint("LEFT", A.x + 48, 0); r.inv:SetPoint("LEFT", A.x + 108, 0) end
        r.sent:ClearAllPoints(); r.sent:SetShown(A and true or false)
        if A then r.sent:SetPoint("LEFT", A.x + 168, 0); r.sent:SetWidth(math.max(10, A.w - 172)) end
    end

    local empty = kit:Text(list, 13, C.muted); empty:SetPoint("CENTER", 0, -10)

    local function Render()
        local pr = ns.P()
        local RH = RowHeight()
        Layout()
        local view = ns.BuildView()
        -- header
        for _, c in ipairs(COLS) do
            local b = headBtns[c.key]
            local L = layoutX[c.key]
            b:ClearAllPoints()
            if L then
                b:SetPoint("LEFT", head, "LEFT", L.x, 0); b:SetWidth(math.max(10, L.w - 4)); b:Show()
                local sel = pr.sortKey == c.key
                b.t:SetText(c.label .. (sel and (pr.sortAsc and "  ^" or "  v") or ""))
                b.t:SetTextColor(unpack(sel and C.accent or C.dim))
            else b:Hide() end
        end
        local fit = math.max(3, math.floor(((list:GetHeight() or 400) - HEAD_H - 2) / RH))
        offset = math.max(0, math.min(offset, #view - fit))
        local nShow = math.min(fit, 120)
        while #rows < nShow do rows[#rows + 1] = MakeRow() end
        for i, r in ipairs(rows) do
            local row = (i <= nShow) and view[i + offset] or nil
            r.row = row
            if row then
                PlaceRow(r, i, RH)
                local lr, lg, lb = ns.ClassColor(row.class)
                r.c.leader:SetText(row.leader); r.c.leader:SetTextColor(lr, lg, lb)
                r.c.level:SetText(row.level and tostring(row.level) or "-"); r.c.level:SetTextColor(unpack(C.dim))
                r.c.activity:SetText(row.dungeon or "?"); r.c.activity:SetTextColor(unpack(C.text))
                r.c.members:SetText(row.members .. "/" .. row.maxMembers)
                r.c.members:SetTextColor(unpack(row.free == 0 and C.muted or C.text))
                for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                    local n = (role == "TANK" and row.tank) or (role == "HEALER" and row.heal) or row.dps
                    local e = r.role[role]
                    e.n:SetText(tostring(n))
                    if n > 0 then e.n:SetTextColor(unpack(ROLE_COLOR[role])); e.icon:SetAlpha(1)
                    else e.n:SetTextColor(unpack(C.muted)); e.icon:SetAlpha(0.35) end
                end
                r.free:SetText(row.free > 0 and (row.free .. " free") or "full")
                r.c.state:SetText(row.state or "")
                local sc = (row.delisted and C.bad) or (row.free == 0 and C.muted) or (row.playstyle and C.dim) or C.good
                r.c.state:SetTextColor(unpack(sc))
                r.c.age:SetText(ns.AgeText(row.ageSec)); r.c.age:SetTextColor(unpack(C.dim))
                local cm = (row.title ~= "" and row.title) or row.comment or ""
                r.c.comment:SetText(cm); r.c.comment:SetTextColor(unpack(C.muted))
                r.msg:SetEnabled(row.leaderFull and true or false)
                local can, why = ns.InviteWhy(row)
                r.inv:SetEnabled(can and true or false)
                r.inv.tip = why
                r.inv.__why = why
                local ago = ns.SentAgo(row.leaderFull)
                r.sent:SetText(ago and (ns.SentText(ago) .. " ago") or "")
                r:Show()
            else
                r:Hide()
            end
        end
        -- scroll bar
        local total = #view
        if total > fit then
            local th = math.max(18, (list:GetHeight() - HEAD_H - 4) * fit / total)
            local avail = (list:GetHeight() - HEAD_H - 4) - th
            local frac = offset / math.max(1, total - fit)
            track:Show(); thumb:Show(); thumb:SetHeight(th); thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -3, -HEAD_H - 2 - avail * frac)
        else track:Hide(); thumb:Hide() end
        -- texts around the table
        if ns.searching then empty:SetText("Searching...")
        elseif ns.failed and #ns.rows == 0 then empty:SetText("The search failed. Try Refresh again in a moment.")
        elseif #ns.rows == 0 then empty:SetText("No results yet. Press Refresh to search (or search in the game's own window).")
        elseif #view == 0 then empty:SetText("No group matches the filter or the activity selection.")
        else empty:SetText("") end
        count:SetText(#view .. " of " .. #ns.rows .. " groups" .. (ns.filterErr and "  |cffff6b61(filter invalid: showing all)|r" or ""))
        stamp:SetText(ns.lastRead and ("Updated " .. ns.lastRead .. (ns.total > #ns.rows and ("  ·  game reports " .. ns.total) or "")) or "Not searched yet")
        -- filter message
        if ns.filterErr then
            err:SetText("Filter error at " .. tostring(ns.filterPos or "?") .. ": " .. ns.filterErr .. "  -  showing all groups")
            err:SetTextColor(unpack(C.bad))
        else
            err:SetText(ns.filterEmpty and "No filter. Filter text only hides rows of this table. Hover ? for the syntax." or "Filter active.")
            err:SetTextColor(unpack(C.muted))
        end
        if not box:HasFocus() and (box:GetText() or "") ~= (pr.filter or "") then
            box.syncing = true; box:SetText(pr.filter or ""); box.syncing = false
        end
        ph:SetShown((box:GetText() or "") == "" and (pr.filter or "") == "")
        local prev = "Message: " .. ns.ExpandTemplate(pr.template, ns.SampleRow())
        footerText:SetText(statusText and ((statusBad and "|cffff6b61" or "|cff73d980") .. statusText .. "|r") or prev)
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; kit:Refresh() end)
    list:SetScript("OnSizeChanged", function() kit:Refresh() end)
    -- keep the "sent ... ago" labels ticking without redrawing the whole table
    local sentTick = 0
    list:SetScript("OnUpdate", function(_, el)
        sentTick = sentTick + (el or 0)
        if sentTick < 1 then return end
        sentTick = 0
        for _, r in ipairs(rows) do
            if r.row and r:IsShown() then
                local ago = ns.SentAgo(r.row.leaderFull)
                r.sent:SetText(ago and (ns.SentText(ago) .. " ago") or "")
            end
        end
    end)
    kit:OnRefresh(Render)
    kit.onResize[#kit.onResize + 1] = function() kit:Refresh() end
    ns.RenderTable = Render

    -- footer
    footerText = kit:Text(footer, 12, C.muted); footerText:SetPoint("LEFT", PAD, 0); footerText:SetPoint("RIGHT", -PAD, 0); footerText:SetWordWrap(false)

    -- ======================================================= options
    local o = pages.options
    local P = ns.P
    local function Changed() ReapplyFonts(); kit:Refresh() end
    kit:Caption(o, "Window", LX, 0)
    kit:SliderRow(o, "Scale", LX, kit:Y(1), COLW, function() return P().scale end,
        function(v) P().scale = v; ns.ApplyScale(); kit:Refresh() end, { lo = 0.6, hi = 1.6, step = 0.05, min = 0.4, max = 2 })
    kit:SliderRow(o, "Row height", LX, kit:Y(2), COLW, function() return P().rowHeight end,
        function(v) P().rowHeight = math.floor(v); kit:Refresh() end, { lo = 14, hi = 34, step = 1, min = 12, max = 40 })
    kit:FontDropdown(o, "Font", LX, kit:Y(3), COLW, function() return P().font end, function(v) P().font = v; Changed() end)
    kit:SliderRow(o, "Font size", LX, kit:Y(4), COLW, function() return P().fontSize end,
        function(v) P().fontSize = math.floor(v); Changed() end, { lo = 9, hi = 18, step = 1, min = 8, max = 24 })
    kit:OutlineDropdown(o, "Outline", LX, kit:Y(5), COLW, function() return P().outline end, function(v) P().outline = v; Changed() end)

    kit:Caption(o, "Message to the leader", LX, -214)
    local tbox = kit:InputBox(o, COLW)
    tbox:SetPoint("TOPLEFT", LX, -236); kit:Flow(tbox, "TOPLEFT", LX, -236, COLW)
    tbox:SetMaxLetters(200)
    local prevFS = kit:Hint(o, "", LX, -268, COLW)
    tbox:SetScript("OnTextChanged", function(s, userInput)
        if s.syncing or userInput == false then return end
        P().template = s:GetText() or ""
        kit:Refresh()
    end)
    kit:Hint(o, "Wildcards: {class} {level} {role} {dungeon} {leader} {spec}.  Sent as a whisper to the leader when you click Msg (one per second at most).", LX, -304, COLW)
    kit:SwitchRow(o, "Short dungeon name when the game has one", LX, -346, COLW, function() return P().shortDungeon end, function(v) P().shortDungeon = v end)
    local bTplReset = kit:Button(o, "Default message", 130, false, function() P().template = "{class} {level} LFG {dungeon}"; tbox.syncing = true; tbox:SetText(P().template); tbox.syncing = false; kit:Refresh() end)
    bTplReset:SetPoint("TOPLEFT", LX, -382); kit:Flow(bTplReset, "TOPLEFT", LX, -382)

    kit:Caption(o, "Game window and minimap", LX, -430)
    kit:SwitchRow(o, "Side tab on the game's group finder", LX, -452, COLW, function() return P().hookGame end,
        function(v) P().hookGame = v; ns.UpdateGameButton() end)
    kit:SwitchRow(o, "Minimap button", LX, -488, COLW, function() return ns.IsMinimapShown == nil or ns.IsMinimapShown() end,
        function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end end)
    local function DefCatItems()
        local out = { { key = "AUTO", label = "Dungeons (automatic)" } }
        for _, c in ipairs(ns.Categories()) do out[#out + 1] = { key = c.id, label = c.name } end
        return out
    end
    kit:Dropdown(o, "Default category", LX, -524, COLW, DefCatItems, function() return P().category end,
        function(v) P().category = v; ns.cat = nil; kit:Refresh() end)

    kit:Caption(o, "Columns", RX, 0)
    for i, c in ipairs(COLS) do
        kit:SwitchRow(o, (c.key == "actions") and "Actions (Msg, Custom, Invite)" or ((c.key == "level") and "Leader level" or c.label), RX, kit:Y(i), COLW,
            function() return P().columns[c.key] end,
            function(v) P().columns[c.key] = v; kit:Refresh() end)
    end
    kit:Caption(o, "Saved filters", RX, -358)
    local bRestore = kit:Button(o, "Restore the default filters", 200, false, function() ns.RestoreFilters(); kit:Refresh() end)
    bRestore:SetPoint("TOPLEFT", RX, -380); kit:Flow(bRestore, "TOPLEFT", RX, -380)
    kit:Hint(o, "Filters are saved in your profile. Write them in the Browse tab, then press Save filter.", RX, -416, COLW)

    kit:Caption(o, "Custom message start", RX, -458)
    local cbox = kit:InputBox(o, COLW)
    cbox:SetPoint("TOPLEFT", RX, -480); kit:Flow(cbox, "TOPLEFT", RX, -480, COLW)
    cbox:SetMaxLetters(120)
    cbox:SetScript("OnTextChanged", function(s, userInput)
        if s.syncing or userInput == false then return end
        P().customStart = s:GetText() or ""
        kit:Refresh()
    end)
    local cprev = kit:Hint(o, "", RX, -512, COLW)
    kit:OnRefresh(function()
        if not cbox:HasFocus() and (cbox:GetText() or "") ~= (P().customStart or "") then
            cbox.syncing = true; cbox:SetText(P().customStart or ""); cbox.syncing = false
        end
        cprev:SetText("Custom opens a whisper to the leader: |cffffffff" .. ns.ExpandTemplate(P().customStart or "", ns.SampleRow()) .. "|r...  you type the rest.")
    end)

    kit:OnRefresh(function()
        if not tbox:HasFocus() and (tbox:GetText() or "") ~= (P().template or "") then
            tbox.syncing = true; tbox:SetText(P().template or ""); tbox.syncing = false
        end
        prevFS:SetText("Preview: |cffffffff" .. ns.ExpandTemplate(P().template, ns.SampleRow()) .. "|r")
    end)

    -- ======================================================= profiles
    local pp = pages.profiles
    local PM = function() return ns.profiles end
    local function profileItems(exceptCurrent)
        local out = {}
        local m = PM()
        if not m then return out end
        for _, name in ipairs(m:List()) do
            if not (exceptCurrent and name == m:Current()) then
                local n = m:Users(name)
                out[#out + 1] = { key = name, label = name .. (n > 0 and ("  (" .. n .. " char.)") or "") }
            end
        end
        return out
    end
    local function Switched() offset = 0; ns.cat = nil; ns.SetFilter(P().filter); ReapplyFonts(); ns.ApplyScale(); kit:Refresh() end
    kit:Caption(pp, "Profile", LX, 0)
    kit:Dropdown(pp, "This character", LX, kit:Y(1), COLW, function() return profileItems(false) end,
        function() return PM() and PM():Current() end, function(v) if PM() then PM():Set(v); Switched() end end)
    kit:Label(pp, "New profile", LX, kit:Y(2) - 5)
    local newBox = kit:InputBox(pp, COLW - 120 - 2 * 76)
    newBox:SetPoint("TOPLEFT", LX + 120, kit:Y(2)); kit:Flow(newBox, "TOPLEFT", LX + 120, kit:Y(2), COLW - 120 - 2 * 76)
    local function newName() local t = (newBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""); return t ~= "" and t or nil end
    local bNew = kit:Button(pp, "Empty", 72, false, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n); Switched()
    end)
    bNew:SetPoint("LEFT", newBox, "RIGHT", 4, 0)
    local bDup = kit:Button(pp, "Copy", 72, true, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n, PM():Current()); Switched()
    end)
    bDup:SetPoint("LEFT", bNew, "RIGHT", 4, 0)
    kit:Dropdown(pp, "Copy settings", LX, kit:Y(3), COLW, function() return profileItems(true) end,
        function() return "from another profile..." end, function(v) if PM() then PM():CopyFrom(v); Switched() end end)
    kit:Dropdown(pp, "Delete", LX, kit:Y(4), COLW, function() return profileItems(true) end,
        function() return "choose a profile..." end, function(v) if PM() then PM():Delete(v); kit:Refresh() end end)
    kit:Label(pp, "Current profile", LX, kit:Y(5) - 5)
    local bReset
    bReset = kit:Button(pp, "Reset to defaults", 150, false, function()
        local now = GetTime and GetTime() or 0
        if bReset.armed and now - bReset.armed < 4 then
            bReset.armed = nil; bReset.label:SetText("Reset to defaults")
            if PM() then PM():Reset(); Switched() end
        else
            bReset.armed = now; bReset.label:SetText("Click again")
        end
    end)
    bReset:SetPoint("TOPLEFT", LX + 120, kit:Y(5))
    kit:OnRefresh(function() bReset.armed = nil; bReset.label:SetText("Reset to defaults") end)
    kit:Hint(pp, "Each character has its own profile by default. \"Copy\" starts the new profile from the current one.", LX, kit:Y(6) + 4, COLW)
    local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
    kit:Caption(pp, "Share", RX, 0)
    local bExp = kit:Button(pp, "Export profile", 150, false, function()
        if LFP and PM() then LFP:ShowExport("Export Free LFG profile: " .. PM():Current(), PM():Export()) end
    end)
    bExp:SetPoint("TOPLEFT", RX, kit:Y(1)); kit:Flow(bExp, "TOPLEFT", RX, kit:Y(1))
    local bImp = kit:Button(pp, "Import profile", 150, false, function()
        if LFP and PM() then
            LFP:ShowImport("Import a Free LFG profile", "Imported", function(text, name)
                local ok, res = PM():Import(text, name)
                if ok then Switched() end
                return ok, res
            end)
        end
    end)
    bImp:SetPoint("LEFT", bExp, "RIGHT", 8, 0)
    kit:Hint(pp, "Export gives one line of text to paste on another character or account. Import creates a profile from such a text and selects it.", RX, kit:Y(2), COLW)

    -- resize grip (free-standing window only; inside Free Hub the hub sets the size)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    local gt = kit:Fill(grip, C.dim, "OVERLAY"); gt:SetSize(10, 2); gt:SetPoint("BOTTOMRIGHT", -2, 3); gt:SetRotation(math.rad(45))
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetResizeBounds then frame:SetResizeBounds(kit.W, 520, 1800, 1200) elseif frame.SetMinResize then frame:SetMinResize(kit.W, 520) end
    grip:SetScript("OnMouseDown", function() if not frame.fhEmbedded then frame:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    kit:OnRefresh(function() grip:SetShown(not frame.fhEmbedded) end)

    frame:HookScript("OnShow", function() ns.ApplyScale(); if ns.P() then ns.ReadResults() end end)
end

kit.o.tabs = { { "browse", "Browse" }, { "options", "Options" }, { "profiles", "Profiles" } }

local function DoBuild() if not kit.frame then Build() end end

-- ------------------------------------------------------------ public
function ns.ApplyScale()
    local f = kit.frame
    if not f then return end
    if f.fhEmbedded then f:SetScale(1) else f:SetScale(tonumber(ns.P().scale) or 1) end
end
ns.OnChanged = function()
    -- results arrived (or the search failed): drop the "Searching..." line
    if not ns.searching and statusText == "Searching..." then statusText = nil end
    kit:Refresh()
end
ns.OnData = ns.OnChanged
ns.OnProfileChanged = function() ReapplyFonts(); ns.ApplyScale(); kit:Refresh() end

local inHub = kit:RegisterHub("FreeLFG", DoBuild, function(show) if ns.ApplyMinimapVisibility then ns.ApplyMinimapVisibility(show) end end)

function ns.Toggle()
    if not ns.GetDB() then return end
    kit:Toggle("FreeLFG", DoBuild)
    ns.ApplyScale()
end
function ns.Open()
    DoBuild()
    if not (kit.frame and kit.frame:IsShown()) then ns.Toggle() end
end

-- ------------------------------------------------------------ side tab on the game's finder
-- One more tab under the game's own column of side tabs (right edge of LFGParentFrame), with our icon cut round.
-- No taint: it is our own plain Button parented to the game's frame; on the game's side we only add an OnShow
-- post-hook. The look is copied from the last existing tab (textures, highlight, size, spacing), measured at runtime.
local gameTabs, hooked = {}, false      -- [game frame] = our button
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function G(f, ...) if type(f) ~= "function" then return nil end local ok, a, b, c, d, e, g, h, i = pcall(f, ...); if ok then return a, b, c, d, e, g, h, i end end
local function Obj(o, m, ...) if o and o[m] then return G(o[m], o, ...) end end

-- all values of a method that returns many (GetChildren, GetRegions), as a table
local function Pack(o, m)
    if not (o and o[m]) then return {} end
    local t = { pcall(o[m], o) }
    if table.remove(t, 1) then return t end
    return {}
end

local function IsButton(o)
    local t = Obj(o, "GetObjectType")
    return t == "Button" or t == "CheckButton"
end

-- side tabs of the game's frame, top to bottom. Screen coordinates (left/top x effective scale) so the
-- test holds whatever the UI scale and the scale of the tabs' own parent; nested frames are searched too.
local function ScreenRect(b)
    local es = Obj(b, "GetEffectiveScale") or 1
    local l, bt, w, h = Obj(b, "GetLeft"), Obj(b, "GetBottom"), Obj(b, "GetWidth"), Obj(b, "GetHeight")
    if not (l and bt and w and h) then return nil end
    return l * es, bt * es, w * es, h * es
end
ns.ScreenRect = ScreenRect
local function FindTabs(f, ours)
    local fl, fb, fw, fh = ScreenRect(f)
    if not fl then return {} end
    local fes = Obj(f, "GetEffectiveScale") or 1
    local rightS = fl + fw
    local found, seen = {}, {}
    local function consider(b)
        if not b or seen[b] or b == ours then return end
        seen[b] = true
        -- on this client the side tabs are plain Frames (the eye, the magnifier, the people), not Buttons
        local ty = Obj(b, "GetObjectType")
        if not (ty == "Button" or ty == "CheckButton" or ty == "Frame") or Obj(b, "IsShown") == false then return end
        local l, bt, w, h = ScreenRect(b)
        if not l or w <= 0 or h <= 0 then return end
        local squareish = math.abs(w - h) <= 0.4 * math.max(w, h)
        -- seen in game (/flfg tabs): the tabs are 35x35 starting exactly at the frame's right edge; the scroll bars'
        -- arrows (11x7, a few px inside the edge) must not count, or ours lands at the bottom of the window
        if l >= rightS - 6 * fes and l <= rightS + 60 * fes and squareish and w >= 24 * fes and h >= 24 * fes then found[#found + 1] = b end
    end
    for i = 1, 8 do
        for _, g in ipairs({ _G["LFGParentFrameSideTab" .. i], _G["LFGParentFrameTab" .. i] }) do consider(g) end
    end
    local function walk(p0, depth)
        for _, k in ipairs(Pack(p0, "GetChildren")) do
            consider(k)
            if depth < 3 then walk(k, depth + 1) end
        end
    end
    walk(f, 1)
    -- keep only the real tabs: the biggest squares there (scroll bar arrows also sit on that edge)
    local maxW = 0
    for _, t in ipairs(found) do local _, _, w = ScreenRect(t); if w and w > maxW then maxW = w end end
    local kept = {}
    for _, t in ipairs(found) do local _, _, w = ScreenRect(t); if w and w >= maxW * 0.7 then kept[#kept + 1] = t end end
    found = kept
    table.sort(found, function(a, b)
        local _, ab, _, ah = ScreenRect(a); local _, bb, _, bh = ScreenRect(b)
        return ((ab or 0) + (ah or 0)) > ((bb or 0) + (bh or 0))
    end)
    return found
end

local function FindIcon(btn)
    for _, k in ipairs({ "icon", "Icon", "IconTexture", "iconTexture" }) do
        local t = rawget(btn, k)
        if type(t) == "table" and Obj(t, "GetObjectType") == "Texture" then return t end
    end
    for _, r in ipairs(Pack(btn, "GetRegions")) do
        if Obj(r, "GetObjectType") == "Texture" then
            local nm = Obj(r, "GetName") or ""
            local file = Obj(r, "GetTexture")
            if nm:find("[Ii]con") or (type(file) == "string" and file:lower():find("icons")) then return r end
        end
    end
end

local function CopyTexture(src, dst, ours, theirs)
    local atlas = Obj(src, "GetAtlas")
    if atlas and dst.SetAtlas then
        G(dst.SetAtlas, dst, atlas)
    else
        local file = Obj(src, "GetTexture")
        if file then G(dst.SetTexture, dst, file) end
        local c = { Obj(src, "GetTexCoord") }
        if #c == 8 then G(dst.SetTexCoord, dst, unpack(c, 1, 8))
        elseif #c == 4 then G(dst.SetTexCoord, dst, unpack(c, 1, 4)) end
    end
    local r, g, b, a = Obj(src, "GetVertexColor")
    if r then G(dst.SetVertexColor, dst, r, g, b, a) end
    local bm = Obj(src, "GetBlendMode"); if bm then G(dst.SetBlendMode, dst, bm) end
    local w, h = Obj(src, "GetSize"); if w and h and w > 0 then G(dst.SetSize, dst, w, h) end
    local n = Obj(src, "GetNumPoints") or 0
    if n > 0 then
        dst:ClearAllPoints()
        for i = 1, n do
            local p, rel, rp, x, y = Obj(src, "GetPoint", i)
            if p then dst:SetPoint(p, (rel == theirs or rel == nil) and ours or ours, rp or p, x or 0, y or 0) end
        end
    end
end

local function RoundIcon(ours, size, theirIcon)
    local ic = ours:CreateTexture(nil, "ARTWORK", nil, 1)
    ic:SetTexture(MEDIA .. "icon")
    ic:SetSize(size[1], size[2])
    if theirIcon then
        local n = Obj(theirIcon, "GetNumPoints") or 0
        if n > 0 then
            ic:ClearAllPoints()
            for i = 1, n do
                local p, rel, rp, x, y = Obj(theirIcon, "GetPoint", i)
                if p then ic:SetPoint(p, ours, rp or p, x or 0, y or 0) end
            end
        else ic:SetPoint("CENTER") end
    else ic:SetPoint("CENTER") end
    if ours.CreateMaskTexture and ic.AddMaskTexture then
        local path = MASK
        local m1 = theirIcon and Obj(theirIcon, "GetMaskTexture", 1)
        local mf = m1 and Obj(m1, "GetTexture")
        if type(mf) == "string" and mf ~= "" then path = mf end
        local ok = pcall(function()
            local m = ours:CreateMaskTexture()
            m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(ic)
            ic:AddMaskTexture(m)
        end)
        if not ok then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    else
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    return ic
end

local function Wire(b)
    b:SetScript("OnClick", function() ns.Open() end)
    b:SetScript("OnEnter", function(s)
        if GameTooltip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetText("Free LFG"); GameTooltip:Show() end
        if s.fhHover then s.fhHover() end
    end)
    b:SetScript("OnLeave", function(s) if GameTooltip then GameTooltip:Hide() end; if s.fhLeave then s.fhLeave() end end)
end

function ns.UpdateGameButton()
    local on = ns.GetDB() and ns.P().hookGame and true or false
    for _, b in pairs(gameTabs) do b:SetShown(on) end
end

-- builds the tab; returns true when done. allowFallback: with no game tabs found, make a small square button instead.
function ns.BuildGameTab(allowFallback, frameOverride)
    local f = frameOverride or _G.LFGParentFrame or _G.LFGBrowseFrame
    if not f or not ns.GetDB() then return false end
    if gameTabs[f] then return true end
    local tabs = FindTabs(f, nil)
    -- the lowest of the game's side tabs (smallest bottom), if any
    local low, lowB, lowW
    for _, t in ipairs(tabs) do
        local _, bt, wS = ScreenRect(t)
        if bt and (not lowB or bt < lowB) then low, lowB, lowW = t, bt, wS end
    end
    if not low and not allowFallback then return false end
    local ok = pcall(function()
        -- our own tab, drawn like the game's classic side tabs (spellbook-style bronze frame), never a copy
        -- of theirs (copied regions stayed anchored to their tab and drew over it)
        -- the game's tab width converted to our parent's scale (UI scale, frame scales), a little smaller
        local fes = Obj(f, "GetEffectiveScale") or 1
        -- same size as the game's tabs (screen size -> our parent's units)
        local w = (low and lowW) and (lowW / fes) or 36
        w = math.max(20, math.min(80, w))
        local b = CreateFrame("Button", nil, f)
        b:SetSize(w, w)
        if low then
            -- same gap as between the game's tabs (screen units -> our parent's units)
            local gap = 8
            local prevB
            for _, t in ipairs(tabs) do
                local _, bt, _, hS = ScreenRect(t)
                if t ~= low and bt and (not prevB or bt < prevB) then prevB = bt end
            end
            if prevB then
                local _, lb, _, lh = ScreenRect(low)
                local g = (prevB - (lb + lh)) / fes
                if g >= 0 and g <= 40 then gap = g end
            end
            b:SetPoint("TOPLEFT", low, "BOTTOMLEFT", 0, -gap)
        else
            -- game tabs not found: bottom of the right edge, where nothing of the game's sits
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 2, 70)
        end
        -- above the game's frame and its tabs, so the mouse reaches it
        -- same strata and level as the game's tabs: their left part slips under the window's border
        if low then
            b:SetFrameStrata(Obj(low, "GetFrameStrata") or Obj(f, "GetFrameStrata") or "MEDIUM")
            b:SetFrameLevel(Obj(low, "GetFrameLevel") or Obj(f, "GetFrameLevel") or 1)
        else
            b:SetFrameStrata(Obj(f, "GetFrameStrata") or "MEDIUM")
            b:SetFrameLevel((Obj(f, "GetFrameLevel") or 1) + 2)
        end
        -- the game's own side-tab art (seen with /flfg tabs on Forever): atlas common-sidetab 55x60 for a 55 px
        -- tab, the icon 50x50, common-sidetab-hover on mouse-over; the classic spellbook tab if the atlas is missing
        local frameTex = b:CreateTexture(nil, "BACKGROUND")
        local hasAtlas = frameTex.SetAtlas and pcall(frameTex.SetAtlas, frameTex, "common-sidetab")
            and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo("common-sidetab"))
        if hasAtlas then
            frameTex:SetSize(w, w * 60 / 55); frameTex:SetPoint("CENTER")
            -- our icon fills the frame's opening
            local ic = b:CreateTexture(nil, "ARTWORK")
            -- Media\tab: the icon cut as a bevelled square (same shape as the frame's opening), filling it like the game's 50x50 icons
            ic:SetTexture(MEDIA .. "tab")
            -- measured on the game's frame (screenshot, 2026-11-11): the opening is 60 x 57 px for a 64.6 px tab,
            -- centred 1.5 px right of and 1 px above where the 1.0.13 icon sat; its right corners are cut ~12%
            -- 1.0.16 (measured on the 1.0.15 screenshot, 64.6 px per tab): opening x 7..67, y 9..69 with a 9 px
            -- bevel on the right; icon 55 x 55 px at x 9..63, y 12..66 = a 2-3 px margin inside the border
            ic:SetSize(w * 0.851, w * 0.851)
            ic:SetPoint("CENTER", b, "CENTER", -w * 0.0585, w * 0.023)
            b.fhIcon = ic
        else
            frameTex:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
            frameTex:SetSize(w * 1.6, w * 1.6); frameTex:SetPoint("TOPLEFT", b, "TOPLEFT", -w * 0.075, w * 0.275)
            RoundIcon(b, { w * 0.8, w * 0.8 }, nil)
        end
        b.fhAtlas = hasAtlas
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        if not (b.fhAtlas and pcall(hl.SetAtlas, hl, "common-sidetab-hover")) then
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
            hl:SetAllPoints()
        else
            hl:SetSize(w, w * 60 / 55); hl:SetPoint("CENTER")
        end
        Wire(b)
        gameTabs[f] = b
        ns.sideTabMode = low and "tab" or "fallback"
    end)
    if not ok then gameTabs[f] = nil; return false end
    ns.UpdateGameButton()
    return gameTabs[f] and true or false
end

-- /flfg tabs: what the side-tab detection sees (to place the tab on clients we can't test)
function ns.DebugTabs()
    local f = _G.LFGParentFrame or _G.LFGBrowseFrame
    if not f then ns.Print("no group finder frame"); return end
    local l, bt, w, h = ScreenRect(f)
    ns.Print(string.format("frame %s  left %.0f bottom %.0f w %.0f h %.0f  scale %.2f", tostring(Obj(f, "GetName")), l or -1, bt or -1, w or -1, h or -1, Obj(f, "GetEffectiveScale") or -1))
    local tabs = FindTabs(f, gameTabs[f])
    ns.Print(#tabs .. " side tab(s) found")
    -- the art of the last game tab (to reuse the game's own frame texture)
    local last = tabs[#tabs]
    if last then
        local function dump(obj, label)
            for _, r in ipairs(Pack(obj, "GetRegions")) do
                if Obj(r, "GetObjectType") == "Texture" then
                    local w2, h2 = Obj(r, "GetSize")
                    ns.Print(string.format("  %s texture  atlas=%s  file=%s  %sx%s  layer=%s", label, tostring(Obj(r, "GetAtlas")), tostring(Obj(r, "GetTexture")),
                        tostring(w2 and math.floor(w2 + 0.5)), tostring(h2 and math.floor(h2 + 0.5)), tostring(Obj(r, "GetDrawLayer"))))
                end
            end
        end
        dump(last, "tab")
        for _, k in ipairs(Pack(last, "GetChildren")) do dump(k, "child " .. tostring(Obj(k, "GetObjectType"))) end
    end
    local function walk(p0, depth)
        for _, k in ipairs(Pack(p0, "GetChildren")) do
            local kl, kb, kw, kh = ScreenRect(k)
            if kl and kl >= (l + w) - 80 then
                ns.Print(string.format("%s%s %s  left %.0f bottom %.0f %.0fx%.0f", string.rep("  ", depth), tostring(Obj(k, "GetName")), tostring(Obj(k, "GetObjectType")), kl, kb, kw, kh))
            end
            if depth < 3 then walk(k, depth + 1) end
        end
    end
    walk(f, 1)
end

function ns.HookGameFrame()
    if hooked or not ns.GetDB() then return end
    local f = _G.LFGParentFrame or _G.LFGBrowseFrame
    if not (f and f.HookScript) then return end
    local function Try()
        if gameTabs[f] then ns.UpdateGameButton(); return end
        if ns.BuildGameTab(false) then return end
        -- layout may not be ready on the very first show: look again a moment later, then fall back
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() ns.BuildGameTab(true) end)
        else ns.BuildGameTab(true) end
    end
    if pcall(f.HookScript, f, "OnShow", Try) then
        hooked = true
        if f.IsShown and f:IsShown() then Try() end
    end
end
