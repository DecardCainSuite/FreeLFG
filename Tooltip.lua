-- Free LFG - the group tooltip (hover a row of the table).
-- Drawn by the addon (not GameTooltip) so it can have columns:
--   activity + level range / group title and comment / summary (label : value) /
--   members by role (role, name, class, level) + open slots / the message "Msg" sends.

local ADDON, ns = ...
local UI = LibStub("LibFreeUI-1.0")
local C = UI.C
local WHITE = "Interface\\Buttons\\WHITE8x8"
local LEADER_ICON = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12:0:0|t"

local PAD, GAP, MINW, MAXW = 12, 8, 260, 440
local TAGW, LVLW, ROWH = 40, 22, 18
local ROLE = {
    TANK    = { label = "Tank", fg = { 0.45, 0.70, 1.00 }, bg = { 0.106, 0.165, 0.239, 1 } },
    HEALER  = { label = "Heal", fg = { 0.40, 0.90, 0.50 }, bg = { 0.106, 0.200, 0.141, 1 } },
    DAMAGER = { label = "DPS",  fg = { 1.00, 0.55, 0.45 }, bg = { 0.239, 0.133, 0.114, 1 } },
}
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local DIM, MUTED = C.dim, C.muted
local YELLOW, COMMENT, GREEN = { 1, 0.82, 0.4 }, { 0.85, 0.85, 0.85 }, { 0.56, 0.86, 0.56 }
local MAX_MEMBERS = 12

local tip
local fsPool, txPool, fsUsed, txUsed = {}, {}, 0, 0

local function Make()
    tip = CreateFrame("Frame", "FreeLFGTooltip", UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:Hide()
    local bg = tip:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(WHITE); bg:SetVertexColor(0.047, 0.051, 0.063, 0.97); bg:SetAllPoints()
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = tip:CreateTexture(nil, "BORDER"); e:SetTexture(WHITE); e:SetVertexColor(0.23, 0.235, 0.267, 1)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
    end
    local top = tip:CreateTexture(nil, "ARTWORK"); top:SetTexture(WHITE); top:SetVertexColor(unpack(C.accent))
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
end

local function FS(size, color, wrap)
    fsUsed = fsUsed + 1
    local fs = fsPool[fsUsed]
    if not fs then fs = tip:CreateFontString(nil, "OVERLAY"); fsPool[fsUsed] = fs end
    UI.SetFont(fs, size)
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(wrap and true or false)
    fs:ClearAllPoints()
    fs:SetWidth(0)
    fs:SetAlpha(1)
    fs:Show()
    return fs
end
local function Tex(color)
    txUsed = txUsed + 1
    local t = txPool[txUsed]
    if not t then t = tip:CreateTexture(nil, "ARTWORK", nil, 1); t:SetTexture(WHITE); txPool[txUsed] = t end
    t:SetVertexColor(unpack(color))
    t:ClearAllPoints()
    t:Show()
    return t
end
local function W(fs) return fs:GetStringWidth() or 0 end
local function H(fs, min) local h = fs:GetStringHeight() or 0; return math.max(h, min or 0) end

local function AgoText(sec)
    if not sec then return "?" end
    if sec < 60 then return "just now" end
    local m = math.floor(sec / 60)
    if m < 60 then return m .. " min ago" end
    return math.floor(m / 60) .. " h " .. string.format("%02d", m % 60) .. " ago"
end

local function LevelRange(row)
    local a = row.act
    if not a then return nil end
    local lo, hi = tonumber(a.minSug) or 0, tonumber(a.maxSug) or 0
    if lo > 0 and hi > 0 then return lo == hi and tostring(lo) or (lo .. "-" .. hi) end
    if lo > 0 then return lo .. "+" end
end

local function Hex(c)
    local function b(v) return math.max(0, math.min(255, math.floor((v or 1) * 255 + 0.5))) end
    return string.format("|cff%02x%02x%02x", b(c[1]), b(c[2]), b(c[3]))
end

local shownOwner
function ns.HideRowTooltip() shownOwner = nil; if tip then tip:Hide() end end

-- the results changed while the tooltip is open (members' details often arrive a moment later): draw it again
function ns.RefreshRowTooltip()
    local o = shownOwner
    if not (o and tip and tip:IsShown() and o.row and o.IsVisible and o:IsVisible()) then return end
    if o.IsMouseOver and not o:IsMouseOver() then return end
    pcall(ns.ShowRowTooltip, o, o.row)
end

function ns.ShowRowTooltip(owner, row)
    if not row then return end
    if not tip then Make() end
    shownOwner = owner
    for i = 1, #fsPool do fsPool[i]:Hide() end
    for i = 1, #txPool do txPool[i]:Hide() end
    fsUsed, txUsed = 0, 0

    local items, need = {}, MINW
    local function add(place, after) items[#items + 1] = { place = place, after = after or 3 } end
    local function want(w) if w > need then need = w end end
    local function sep()
        add(function(y, w) local t = Tex({ 0.165, 0.173, 0.2, 1 }); t:SetHeight(1)
            t:SetPoint("TOPLEFT", PAD, y - 4); t:SetPoint("TOPRIGHT", -PAD, y - 4); return 9 end, 2)
    end
    local function caption(text)
        local fs = FS(11, C.accent); fs:SetText(text)
        add(function(y) fs:SetPoint("TOPLEFT", PAD, y); return 13 end, 2)
    end
    local function wrapped(text, size, color)
        local fs = FS(size, color, true); fs:SetText(text)
        want(math.min(W(fs), MAXW - 2 * PAD) + 2 * PAD)
        add(function(y, w)
            fs:SetWidth(w - 2 * PAD); fs:SetPoint("TOPLEFT", PAD, y)
            return H(fs, size + 2)
        end)
    end

    -- header: activity (full name as the game gives it) + level range on the right
    local title = FS(15, C.text, true); title:SetText(row.dungeon or "?")
    local range = LevelRange(row)
    local rf = range and FS(12, MUTED)
    if rf then rf:SetText(range) end
    local rw = rf and (W(rf) + 16) or 0
    want(W(title) + rw + 2 * PAD)
    add(function(y, w)
        local avail = w - 2 * PAD - rw
        if W(title) > avail then title:SetWidth(avail) end
        title:SetPoint("TOPLEFT", PAD, y)
        if rf then rf:SetPoint("TOPRIGHT", -PAD, y - 3) end
        return H(title, 17)
    end)
    -- the group's own title and comment (written by the leader)
    if row.title and row.title ~= "" then wrapped(row.title, 13, YELLOW) end
    if row.comment and row.comment ~= "" then wrapped(row.comment, 12, COMMENT) end
    sep()

    -- summary: label on the left, value on the right
    local function kv(label, value)
        local l = FS(13, DIM); l:SetText(label)
        local v = FS(13, C.text); v:SetText(value)
        want(2 * PAD + W(l) + 16 + W(v))
        add(function(y) l:SetPoint("TOPLEFT", PAD, y); v:SetPoint("TOPRIGHT", -PAD, y); return 15 end, 2)
    end
    local mut = Hex(MUTED)
    kv("Leader", Hex({ ns.ClassColor(row.class) }) .. (row.leaderFull and ns.Short(row.leaderFull) or row.leader or "?") .. "|r"
        .. (row.level and (mut .. "  ·  " .. row.level .. "|r") or ""))
    if row.solo then
        local roles = {}
        if (row.tank or 0) > 0 then roles[#roles + 1] = "Tank" end
        if (row.heal or 0) > 0 then roles[#roles + 1] = "Heal" end
        if (row.dps or 0) > 0 then roles[#roles + 1] = "DPS" end
        kv("Group", "Solo" .. (#roles > 0 and (mut .. "  ·  " .. table.concat(roles, ", ") .. "|r") or ""))
    else
        kv("Group", (row.members or 1) .. "/" .. (row.maxMembers or 5) .. mut .. "  ·  " .. (row.free or 0) .. " free|r")
    end
    if row.state and row.state ~= "" then kv("Status", row.state) end
    kv("Listed", AgoText(row.ageSec))
    if row.ilvl and row.ilvl > 0 then kv("Item level", row.ilvl .. "+") end
    if row.voice then kv("Voice", row.voice) end
    if row.newPlayer then kv("New players", Hex(GREEN) .. "welcome|r") end

    -- members, by role; then the open slots
    -- The game does not always answer again on hover (seen on 15/11 in Zul'Farrak): use what was read with the
    -- results, and fill the gaps from the role counts ("member" lines) when even that is missing.
    local list, nameless = {}, 0
    local cached = type(row.memberInfo) == "table" and row.memberInfo or {}
    for i = 1, math.min(row.members or 0, 40) do
        local m = ns.MemberInfo and ns.MemberInfo(row.id, i)
        local c = cached[i]
        if c and (not m or (not m.name and not m.class)) then m = c end
        if m and (m.name or m.class) then list[#list + 1] = m else nameless = nameless + 1 end
    end
    if nameless > 0 then
        local known = { TANK = 0, HEALER = 0, DAMAGER = 0 }
        for _, m in ipairs(list) do if known[m.role] then known[m.role] = known[m.role] + 1 end end
        local missing = { TANK = (row.tank or 0) - known.TANK, HEALER = (row.heal or 0) - known.HEALER, DAMAGER = (row.dps or 0) - known.DAMAGER }
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            for _ = 1, math.max(0, missing[role]) do
                if nameless == 0 then break end
                list[#list + 1] = { role = role, unknown = true }; nameless = nameless - 1
            end
        end
        for _ = 1, nameless do list[#list + 1] = { unknown = true } end
    end
    table.sort(list, function(a, b)
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        if (a.unknown or false) ~= (b.unknown or false) then return not a.unknown end
        if a.isLeader ~= b.isLeader then return a.isLeader end
        return (a.name or "") < (b.name or "")
    end)
    local open = {}
    if not row.solo then
        for _ = 1, row.tankfree or 0 do open[#open + 1] = "TANK" end
        for _ = 1, row.healfree or 0 do open[#open + 1] = "HEALER" end
        for _ = 1, row.dpsfree or 0 do open[#open + 1] = "DAMAGER" end
    end
    if #list > 0 or #open > 0 then
        sep()
        caption("MEMBERS")
        local mrows, nameW, classW = {}, 0, 0
        local function tag(role, isOpen)
            local r = ROLE[role]
            local bg = Tex(r and (isOpen and { r.bg[1], r.bg[2], r.bg[3], 0.45 } or r.bg) or { 0.2, 0.2, 0.22, 1 })
            local t = FS(11, r and r.fg or MUTED); t:SetText(r and r.label or "-"); t:SetJustifyH("CENTER")
            if isOpen then t:SetAlpha(0.7) else t:SetAlpha(1) end
            return bg, t
        end
        for k, m in ipairs(list) do
            if k > MAX_MEMBERS then break end
            local bg, t = tag(m.role)
            if m.unknown then
                local nf = FS(13, MUTED); nf:SetText("member")
                nameW = math.max(nameW, W(nf))
                mrows[#mrows + 1] = { bg, t, nf }
            else
                local name = m.name and m.name ~= "" and ns.Short(m.name) or (m.isLeader and row.leader) or nil
                local nf = FS(13, { ns.ClassColor(m.class) })
                nf:SetText((name or m.classLoc or m.class or "?") .. (m.isLeader and (" " .. LEADER_ICON) or ""))
                local cf = FS(12, MUTED); cf:SetText(name and (m.classLoc or m.class or "") or "")
                local lf = FS(12, MUTED); lf:SetText(m.level and tostring(m.level) or ""); lf:SetJustifyH("RIGHT")
                nameW, classW = math.max(nameW, W(nf)), math.max(classW, W(cf))
                mrows[#mrows + 1] = { bg, t, nf, cf, lf }
            end
        end
        for _, role in ipairs(open) do
            local bg, t = tag(role, true)
            local nf = FS(13, MUTED); nf:SetText("open slot")
            nameW = math.max(nameW, W(nf))
            mrows[#mrows + 1] = { bg, t, nf }
        end
        want(2 * PAD + TAGW + GAP + nameW + GAP + classW + GAP + LVLW)
        for _, r in ipairs(mrows) do
            add(function(y, w)
                r[1]:SetSize(TAGW, 14); r[1]:SetPoint("TOPLEFT", PAD, y - 1)
                r[2]:SetWidth(TAGW); r[2]:SetPoint("CENTER", r[1], "CENTER", 0, 0)
                r[3]:SetPoint("TOPLEFT", PAD + TAGW + GAP, y)
                if r[4] then r[4]:SetPoint("TOPRIGHT", -(PAD + LVLW + GAP), y - 1) end
                if r[5] then r[5]:SetWidth(LVLW); r[5]:SetPoint("TOPRIGHT", -PAD, y - 1) end
                return ROWH - 2
            end, 2)
        end
        if #list > MAX_MEMBERS then
            local more = FS(11, MUTED); more:SetText("... and " .. (#list - MAX_MEMBERS) .. " more")
            add(function(y) more:SetPoint("TOPLEFT", PAD + TAGW + GAP, y); return 13 end)
        end
    end

    -- what the "Msg" button sends
    sep()
    caption("YOUR MESSAGE")
    wrapped(ns.ExpandTemplate(ns.P().template, row), 13, GREEN)
    local ago = ns.SentAgo and ns.SentAgo(row.leaderFull)
    if ago then wrapped("Already whispered " .. ns.SentText(ago) .. " ago", 11, C.accent) end
    local hint = FS(11, MUTED); hint:SetText(LEADER_ICON .. " leader  ·  Msg sends it  ·  Custom: type your own")
    want(W(hint) + 2 * PAD)
    add(function(y) hint:SetPoint("TOPLEFT", PAD, y - 2); return 14 end)

    -- layout
    local width = math.floor(math.min(MAXW, math.max(MINW, need)) + 0.5)
    local y = -10
    for _, it in ipairs(items) do
        local h = it.place(y, width) or 0
        y = y - h - it.after
    end
    tip:SetSize(width, math.floor(-y + 7))
    tip:ClearAllPoints()
    local right, screen = owner.GetRight and owner:GetRight(), UIParent.GetRight and UIParent:GetRight()
    local scale = (owner.GetEffectiveScale and owner:GetEffectiveScale() or 1) / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
    if right and screen and right * scale + 6 + width > screen then
        tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -6, 0)          -- no room on the right
    else
        tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    end
    tip:Show()
    return tip
end

-- ------------------------------------------------------------ filter syntax (the "?" next to the filter box), 1.0.21
-- Same frame and look as the group tooltip; fixed width, laid out in sections.
local CODE = { 1, 0.74, 0.48 }          -- what you type
local SYN_W = 500
local CLASS_GRID = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }

function ns.ShowSyntaxTooltip(owner)
    if not tip then Make() end
    shownOwner = nil                    -- not a row: RefreshRowTooltip must leave it alone
    for i = 1, #fsPool do fsPool[i]:Hide() end
    for i = 1, #txPool do txPool[i]:Hide() end
    fsUsed, txUsed = 0, 0
    local W0, L, R = SYN_W, PAD, SYN_W - PAD
    local y = -10

    local function text(t, size, color, x, yy, wrapW)
        local fs = FS(size, color, wrapW and true or false); fs:SetText(t)
        if wrapW then fs:SetWidth(wrapW) end
        fs:SetPoint("TOPLEFT", x, yy)
        return fs
    end
    local function sep()
        local t = Tex({ 0.165, 0.173, 0.2, 1 }); t:SetHeight(1)
        t:SetPoint("TOPLEFT", L, y - 5); t:SetPoint("TOPRIGHT", -PAD, y - 5)
        y = y - 11
    end
    local function caption(t, right)
        text(t, 11, C.accent, L, y)
        if right then local f = FS(10, MUTED); f:SetText(right); f:SetPoint("TOPRIGHT", -PAD, y) end
        y = y - 16
    end
    -- a small box with code in it (operators, keywords); returns its width
    local function chip(t, x, yy)
        local f = FS(12, CODE); f:SetText(t)
        local w = math.max(22, W(f) + 12)
        local bg = Tex(C.control); bg:SetSize(w, 16); bg:SetPoint("TOPLEFT", x, yy + 1)
        f:SetPoint("CENTER", bg, "CENTER", 0, 0)
        return w
    end
    -- rows of "code  description" in n columns
    local function grid(pairs_, cols, codeW)
        local colW = (W0 - 2 * PAD) / cols
        for i, pr in ipairs(pairs_) do
            local c = (i - 1) % cols
            local x = L + c * colW
            text(pr[1], 12, CODE, x, y)
            text(pr[2], 11, DIM, x + codeW, y - 1)
            if c == cols - 1 or i == #pairs_ then y = y - 16 end
        end
    end

    -- header
    text("Filter syntax", 15, C.text, L, y)
    local r = FS(11, MUTED); r:SetText("live  ·  only this table"); r:SetPoint("TOPRIGHT", -PAD, y - 3)
    y = y - 20
    local sub = text("Type a rule: the table keeps the groups where it is true. Case does not matter.", 11, DIM, L, y, W0 - 2 * PAD)
    y = y - H(sub, 13) - 4
    sep()

    -- roles: in the group / open slots
    caption("ROLES", "number of players")
    local X1, X2 = L + TAGW + 18, L + TAGW + 18 + 150
    text("in the group", 10, MUTED, X1, y); text("open slots", 10, MUTED, X2, y)
    y = y - 14
    for _, rr in ipairs({ { "TANK", "tank", "tankfree" }, { "HEALER", "heal", "healfree", "healer" }, { "DAMAGER", "dps", "dpsfree", "damage" } }) do
        local R0 = ROLE[rr[1]]
        local bg = Tex(R0.bg); bg:SetSize(TAGW, 14); bg:SetPoint("TOPLEFT", L, y)
        local tg = FS(10, R0.fg); tg:SetText(R0.label); tg:SetWidth(TAGW); tg:SetJustifyH("CENTER"); tg:SetPoint("CENTER", bg, "CENTER", 0, 0)
        local a = text(rr[2], 12, CODE, X1, y)
        if rr[4] then text("or " .. rr[4], 11, MUTED, X1 + W(a) + 8, y - 1) end
        text(rr[3], 12, CODE, X2, y)
        y = y - 18
    end
    y = y - 2
    sep()

    -- group
    caption("GROUP")
    grid({ { "members", "players in it" }, { "free", "open slots" },
           { "level", "leader's level" }, { "age", "minutes listed" },
           { "solo", "1 = a single player" }, { "delisted", "1 = no longer listed" } }, 2, 68)
    y = y - 2
    sep()

    -- classes, in class colours
    caption("CLASSES", "members of that class, leader included")
    local colW = (W0 - 2 * PAD) / 3
    for i, name in ipairs(CLASS_GRID) do
        local c = (i - 1) % 3
        local cr, cg, cb = ns.ClassColor(name:upper())
        text(name, 12, { cr, cg, cb }, L + c * colW, y)
        if c == 2 then y = y - 16 end
    end
    local hint = text("Plural works (rogues >= 2).  " .. Hex(CODE) .. "unknown|r = members whose class the game did not give.", 11, MUTED, L, y, W0 - 2 * PAD)
    y = y - H(hint, 13) - 2
    sep()

    -- compare
    caption("COMPARE")
    local x = L
    for _, op in ipairs({ ">=", "<=", ">", "<", "=", "!=" }) do x = x + chip(op, x, y) + 6 end
    text("equal: = or ==   ·   not equal: != or <>", 11, MUTED, x + 8, y - 1)
    y = y - 22
    text("Ranges", 11, DIM, L, y - 1)
    x = L + 58
    for i, ex in ipairs({ "dps in 1..2", "1 <= dps <= 2", "dps between 1 and 2" }) do
        local f = text(ex, 12, CODE, x, y)
        x = x + W(f)
        if i < 3 then local d = text("·", 12, MUTED, x + 8, y); x = x + 22 end
    end
    y = y - 18
    sep()

    -- combine
    caption("COMBINE")
    x = L
    for _, kw in ipairs({ "and", "or", "not", "( )" }) do x = x + chip(kw, x, y) + 6 end
    text("also  && |||| !     maths  + - *", 11, MUTED, x + 8, y - 1)
    y = y - 22
    local bare = text("A name alone means at least one:  " .. Hex(CODE) .. "rogue and healfree|r", 11, DIM, L, y - 1, W0 - 2 * PAD)
    y = y - H(bare, 13) - 2
    sep()

    -- text fields
    caption("TEXT", "contains, case ignored")
    grid({ { 'name:"abc"', "leader's name" }, { 'dungeon:"zul"', "activity" },
           { 'comment:"fast"', "title and comment" }, { 'class:"mage"', "leader's class" },
           { 'state:"relaxed"', "state column" } }, 2, 104)
    y = y - 2
    sep()

    -- examples
    caption("EXAMPLES")
    for _, ex in ipairs({
        { "rogue >= 1 and healfree >= 1", "a rogue, room for a healer" },
        { "(heal >= 1 or tank >= 1) and dps <= 2", "a tank or a healer, few DPS" },
        { "tankfree and not delisted", "a tank slot, still listed" },
        { "solo and level >= 40", "single players 40+" },
        { 'dungeon:"zul" and age <= 10', "Zul'Farrak, listed < 10 min" },
    }) do
        text(ex[1], 12, GREEN, L, y)
        local d = FS(11, MUTED); d:SetText(ex[2]); d:SetPoint("TOPRIGHT", -PAD, y - 1)
        y = y - 16
    end
    y = y - 2
    sep()
    local foot = text("Only this table changes, never the game's search. An invalid rule shows all groups.", 11, GREEN, L, y, W0 - 2 * PAD)
    y = y - H(foot, 13)

    tip:SetSize(W0, math.floor(-y + 9))
    tip:ClearAllPoints()
    tip:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    tip:Show()
    return tip
end
