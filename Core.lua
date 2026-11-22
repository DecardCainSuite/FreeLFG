-- Free LFG - a sortable, filterable table for the game's group finder (Classic-style "LFGBrowse").
--
-- What we rely on (all guarded: a missing or changed call never raises):
--   C_LFGList.GetAvailableCategories / GetCategoryInfo / GetAvailableActivities / GetActivityInfoTable (or GetActivityInfo)
--   C_LFGList.Search(...)                      only from a direct click on our Refresh button (hardware event)
--   C_LFGList.GetFilteredSearchResults (or GetSearchResults) / GetSearchResultInfo / GetSearchResultMemberCounts / GetSearchResultPlayerInfo
--   events LFG_LIST_SEARCH_RESULTS_RECEIVED, _RESULT_UPDATED, _AVAILABILITY_UPDATE, _FAILED, GROUP_ROSTER_UPDATE
--   SendChatMessage(msg, "WHISPER", nil, leader)  /  C_PartyInfo.InviteUnit(leader)   both only from a click
-- We never touch the game's frames (only an optional extra button parented to them, see UI.lua).

local ADDON, ns = ...
local PREFIX = "|cffff8a3dFree LFG|r: "
function ns.Print(msg) print(PREFIX .. msg) end

local db                       -- saved variables root
ns.rows = {}                   -- all results as read from the game (see ReadResults)
ns.view = {}                   -- rows after filter + activity selection + sort
ns.total = 0                   -- results the game reported
ns.lastRead = nil              -- time of the last read (date string)
ns.searching = false

-- ------------------------------------------------------------ defaults / profile
local PRESET_FILTERS = {
    { name = "Need a healer", expr = "heal < 1 and free >= 1" },
    { name = "Need a tank", expr = "tank < 1 and free >= 1" },
    { name = "Room for a DPS", expr = "dps < 3 and free >= 1" },
    { name = "Tank/healer, max 1 DPS", expr = "(heal >= 1 or tank >= 1) and dps <= 1" },
    { name = "Almost full", expr = "free = 1" },
    { name = "Fresh groups (10 min)", expr = "age <= 10 and not delisted" },
}
ns.PRESET_FILTERS = PRESET_FILTERS

ns.COLUMNS = {   -- key, label, default width (0 = takes the room left), default shown
    { key = "leader", label = "Leader", w = 140 },
    { key = "level", label = "Lvl", w = 36 },
    { key = "activity", label = "Activity", w = 176 },
    { key = "members", label = "Size", w = 46 },
    { key = "roles", label = "Roles", w = 156 },
    { key = "state", label = "State", w = 84 },
    { key = "age", label = "Listed", w = 58 },
    { key = "comment", label = "Comment", w = 0 },
    { key = "actions", label = "", w = 236 },   -- Msg / Custom / Invite + "sent ... ago" (1.0.21; was 166)
}

local DEFAULTS = {
    scale = 1,
    font = "ARIALN", fontSize = 12, outline = "NONE",
    rowHeight = 20,
    columns = { leader = true, level = true, activity = true, members = true, roles = true, state = true, age = true, comment = true, actions = true },
    template = "{class} {level} LFG {dungeon}",
    customStart = "{class} {level} ",  -- "Custom": opens a whisper to the leader with this text, you type the rest
    shortDungeon = true,
    category = "AUTO",
    activityMode = "level",            -- "level" (activities for my level) | "all" | "custom" (activitySel)
    activitySel = {},
    filter = "",
    filters = false,                   -- list of { name, expr }; filled with the presets the first time
    sortKey = "default", sortAsc = true,           -- "default" = the game's order
    hookGame = true,
}

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Prepare(p)
    for k, v in pairs(DEFAULTS) do
        if p[k] == nil then p[k] = Copy(v) end
    end
    for _, c in ipairs(ns.COLUMNS) do
        if p.columns[c.key] == nil then p.columns[c.key] = true end
    end
    if p.activityMode ~= "all" then p.activityMode = "level" end      -- older versions had a "custom" mode
    if type(p.activitySel) ~= "table" then p.activitySel = {} end
    if p.filters == false then p.filters = Copy(PRESET_FILTERS) end
    return p
end

function ns.GetDB() return db end
-- settings of the current profile (never nil once the addon is loaded)
function ns.P()
    if ns.profiles then return ns.profiles:Data() end
    return ns.fallback or Prepare({})
end

local function SafeNumber(v, d) v = tonumber(v); return v or d end

-- ------------------------------------------------------------ small helpers
local function S(v)   -- a "secret" value (restricted by the game) is treated as unknown
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Short(name) return name and (name:match("^([^%-]+)") or name) or "?" end
ns.Short = Short
local function Pc(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d, e, g = pcall(f, ...)
    if ok then return a, b, c, d, e, g end
end
ns.Pc = Pc

function ns.ClassColor(token)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

function ns.AgeText(sec)
    if not sec then return "?" end
    if sec < 60 then return math.floor(sec) .. "s" end
    local m = math.floor(sec / 60)
    if m < 60 then return m .. "m" end
    return math.floor(m / 60) .. "h" .. string.format("%02d", m % 60)
end

-- ------------------------------------------------------------ categories & activities
local actCache = {}
-- returns { id, name, short, minSug, maxSug (suggested levels), maxPlayers } (fields may be nil when the game gives nothing)
function ns.ActivityInfo(id)
    if not id then return nil end
    if actCache[id] ~= nil then return actCache[id] or nil end
    local out
    local t = C_LFGList and Pc(C_LFGList.GetActivityInfoTable, id)
    if type(t) == "table" then
        out = { id = id, name = S(t.fullName), short = S(t.shortName), minLevel = S(t.minLevel), maxLevel = S(t.maxLevel),
                minSug = tonumber(S(t.minLevelSuggestion)), maxSug = tonumber(S(t.maxLevelSuggestion)),
                maxPlayers = S(t.maxNumPlayers), cat = S(t.categoryID) }
    elseif C_LFGList and C_LFGList.GetActivityInfo then
        -- older shape: fullName, shortName, categoryID, groupID, itemLevel, filters, minLevel, maxPlayers
        local ok, full, short, cat, _, _, _, minL, maxP = pcall(C_LFGList.GetActivityInfo, id)
        if ok and full then out = { id = id, name = S(full), short = S(short), cat = S(cat), minLevel = S(minL), maxPlayers = S(maxP) } end
    end
    actCache[id] = out or false
    return out
end

function ns.Categories()
    local out = {}
    if not (C_LFGList and C_LFGList.GetAvailableCategories) then return out end
    local ids = Pc(C_LFGList.GetAvailableCategories)
    if type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local name
        -- this client: C_LFGList.GetLfgCategoryInfo(id) -> { name = ... }; older ones: GetCategoryInfo
        local info = C_LFGList.GetLfgCategoryInfo and Pc(C_LFGList.GetLfgCategoryInfo, id)
        if info == nil and C_LFGList.GetCategoryInfo then info = Pc(C_LFGList.GetCategoryInfo, id) end
        if type(info) == "table" then name = S(info.name) elseif type(info) == "string" then name = S(info) end
        if type(name) ~= "string" or name == "" then name = nil end
        -- only categories that have activities for this character (like the game's menu)
        local acts = C_LFGList.GetAvailableActivities and Pc(C_LFGList.GetAvailableActivities, id)
        if type(acts) ~= "table" or #acts > 0 then
            out[#out + 1] = { id = id, name = name or ("Category " .. tostring(id)) }
        end
    end
    return out
end

-- default category: the one the player chose, else "Dungeons" (by id 2 or by name), else the first one
function ns.DefaultCategory()
    local list = ns.Categories()
    local want = ns.P().category
    if want and want ~= "AUTO" then
        for _, c in ipairs(list) do if c.id == want then return c.id end end
    end
    for _, c in ipairs(list) do if c.id == 2 then return c.id end end
    for _, c in ipairs(list) do if c.name:lower():find("dungeon") or c.name:lower():find("donjon") then return c.id end end
    return list[1] and list[1].id
end
function ns.CurrentCategory()
    if not ns.cat then ns.cat = ns.DefaultCategory() end
    return ns.cat
end

-- the level rule of the game's finder: an activity is kept unless its suggested minimum is above my level
-- or its suggested maximum is below it (no suggestion = always kept)
function ns.ActivityAtLevel(a, lvl)
    if not a then return true end
    if a.minSug and a.minSug > 0 and a.minSug > lvl then return false end
    if a.maxSug and a.maxSug > 0 and a.maxSug < lvl then return false end
    return true
end
local function MyLevel() return (UnitLevel and tonumber(UnitLevel("player"))) or 1 end

local function RangeText(a)
    if not a then return nil end
    local lo, hi = a.minSug or 0, a.maxSug or 0
    if lo > 0 and hi > 0 then return (lo == hi) and tostring(lo) or (lo .. "-" .. hi) end
    if lo > 0 then return lo .. "+" end
    if hi > 0 then return "up to " .. hi end
    return nil
end

-- activities of a category, in the game's order: suggested level (lowest first, none last), then name.
-- filtered: only those usable at my level.
function ns.Activities(cat, filtered)
    local out = {}
    if not (cat and C_LFGList and C_LFGList.GetAvailableActivities) then return out end
    local ids = Pc(C_LFGList.GetAvailableActivities, cat)
    if type(ids) ~= "table" then return out end
    local lvl = MyLevel()
    for _, id in ipairs(ids) do
        local a = ns.ActivityInfo(id)
        if not filtered or ns.ActivityAtLevel(a, lvl) then
            local lo = (a and a.minSug and a.minSug > 0) and a.minSug or 1e9
            out[#out + 1] = { id = id, name = (a and a.name) or ("Activity " .. id), sortLevel = lo, range = RangeText(a), a = a }
        end
    end
    table.sort(out, function(x, y)
        if x.sortLevel ~= y.sortLevel then return x.sortLevel < y.sortLevel end
        if x.name ~= y.name then return x.name < y.name end
        return x.id < y.id
    end)
    return out
end

local function ActivityPasses(a, myLevel)
    local p = ns.P()
    if p.activityMode ~= "all" and not ns.ActivityAtLevel(a, myLevel) then return false end
    if next(p.activitySel) then return a ~= nil and p.activitySel[a.id] and true or false end   -- ticked = narrowing
    return true
end

function ns.ActivitySummary()
    local p = ns.P()
    local base = (p.activityMode == "all") and "All activities" or "Activities at my level"
    local n, one = 0, nil
    for id, v in pairs(p.activitySel) do if v then n = n + 1; one = id end end
    if n == 0 then return base end
    if n == 1 then local a = ns.ActivityInfo(one); return (a and a.name) or ("Activity " .. one) end
    return n .. " activities"
end

-- "level" / "all" choose the mode (and forget ticked activities); an activity id ticks / unticks it (narrows the table only)
function ns.ToggleActivity(id)
    local p = ns.P()
    if id == "level" or id == "all" then p.activityMode = id; p.activitySel = {}; return end
    p.activitySel[id] = (not p.activitySel[id]) or nil
end

-- ------------------------------------------------------------ reading results
local PLAYSTYLE_FALLBACK = { "Learning", "Relaxed", "Competitive", "Carry offered" }
local OLD_PLAYSTYLE = { "Standard", "Casual", "Hardcore" }
local function PlaystyleText(info)
    local g = S(info.generalPlaystyle)
    if type(g) == "number" and g > 0 then
        return _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. g] or PLAYSTYLE_FALLBACK[g]
    end
    local o = S(info.playstyle)
    if type(o) == "number" and o > 0 then return _G["GROUP_FINDER_PLAYSTYLE" .. o] or OLD_PLAYSTYLE[o] end
    return nil
end

-- one member: { name, class (token), classLoc, level, role (assigned), isLeader, lfgRoles = {tank,healer,dps}, area }
-- The game does not always give everything (some fields can be missing or restricted): we keep what we get,
-- and remember a few incomplete answers (FreeLFGDB.memberGaps) to see what the client really sends.
local function First(t, ...)
    for k = 1, select("#", ...) do
        local v = S(t[select(k, ...)])
        if v ~= nil and v ~= "" then return v end
    end
end
local function RecordGap(id, i, t)
    if not db then return end
    local gaps = db.memberGaps
    if type(gaps) ~= "table" then gaps = {}; db.memberGaps = gaps end
    local keys = {}
    for k, v in pairs(t) do
        local secret = issecretvalue and issecretvalue(v)
        keys[#keys + 1] = tostring(k) .. "=" .. (secret and "secret" or type(v) == "table" and "table" or tostring(v))
    end
    table.sort(keys)
    table.insert(gaps, 1, { at = time and time() or 0, id = id, i = i, fields = table.concat(keys, ", ") })
    for n = #gaps, 9, -1 do gaps[n] = nil end
end
local function MemberInfo(id, i)
    if not C_LFGList then return nil end
    local m
    if C_LFGList.GetSearchResultPlayerInfo then
        local ok, t = pcall(C_LFGList.GetSearchResultPlayerInfo, id, i)
        if ok and type(t) == "table" then
            local class = First(t, "classFilename", "classFile", "class")
            local roles = S(t.lfgRoles)
            m = { name = First(t, "name", "fullName"), class = class, classLoc = First(t, "className", "classLocalized"),
                  level = tonumber(S(t.level)), role = First(t, "assignedRole", "role"), isLeader = S(t.isLeader) and true or false,
                  lfgRoles = type(roles) == "table" and { tank = S(roles.tank) and true or false, healer = S(roles.healer) and true or false, dps = S(roles.dps) and true or false } or nil,
                  area = S(t.areaName) }
            if not m.name and not m.class then RecordGap(id, i, t) end
        end
    end
    if C_LFGList.GetSearchResultMemberInfo and (not m or not m.class or not m.role) then   -- older shape, also used to complete
        local ok, role, class, classLoc, spec, isLeader, _, level = pcall(C_LFGList.GetSearchResultMemberInfo, id, i)
        if ok and (S(role) or S(class)) then
            m = m or { isLeader = S(isLeader) and true or false }
            m.role = m.role or S(role); m.class = m.class or S(class); m.classLoc = m.classLoc or S(classLoc)
            m.spec = m.spec or S(spec); m.level = m.level or tonumber(S(level))
        end
    end
    if m and m.class and not m.classLoc then
        m.classLoc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class
    end
    return m
end
ns.MemberInfo = MemberInfo

local function InGroup() return IsInGroup and IsInGroup() end
local function MyName() return UnitName and UnitName("player") end

-- Default order (used when no column is picked, and as the secondary order of every sort):
-- my own listing, then solo listings if I am in a group (groups otherwise), groups with a slot for my role,
-- bigger groups, newer listings, result id.
local function MyRoleKey()
    local ok, _, tank, healer, dps = pcall(function() return GetLFGRoles() end)
    if ok then
        if tank then return "tankfree" elseif healer then return "healfree" elseif dps then return "dpsfree" end
    end
    return nil
end
function ns.DefaultLess(a, b)
    if a.mine ~= b.mine then return a.mine end
    local wantSolo = InGroup() and true or false
    local am, bm = (a.solo == wantSolo), (b.solo == wantSolo)
    if am ~= bm then return am end
    local rk = ns.myRoleKey
    if rk and not a.solo and not b.solo then
        local as, bs = (a[rk] or 0) > 0, (b[rk] or 0) > 0
        if as ~= bs then return as end
    end
    if a.members ~= b.members then return a.members > b.members end
    local aa, ba = a.ageSec or 0, b.ageSec or 0
    if aa ~= ba then return aa > ba end   -- the game: listed longer first
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end

local function GeneralPlaystyle(info, id)
    local g = S(info.generalPlaystyle)
    if type(g) ~= "number" or g <= 0 then return nil end
    local txt
    if GetGeneralPlaystyleString then
        local ok, t = pcall(GetGeneralPlaystyleString, g)
        if ok and type(t) == "string" and t ~= "" then txt = t end
    end
    return txt or _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. g] or PLAYSTYLE_FALLBACK[g]
end

local function BuildRow(id, idx)
    local info = C_LFGList.GetSearchResultInfo and Pc(C_LFGList.GetSearchResultInfo, id)
    if type(info) ~= "table" then return nil end
    local r = { id = id, idx = idx }
    -- activities: the biggest group size of all of them, the first one names the row
    local actIDs = S(info.activityIDs)
    if type(actIDs) ~= "table" then actIDs = { S(info.activityID) } end
    local a, maxP
    for _, aid in ipairs(actIDs) do
        local ai = ns.ActivityInfo(aid)
        if ai then
            a = a or ai
            if ai.maxPlayers and (not maxP or ai.maxPlayers > maxP) then maxP = ai.maxPlayers end
        end
    end
    r.activityID = actIDs[1]
    r.dungeon = (a and (a.name or a.short)) or "?"
    r.dungeonShort = (a and (a.short and a.short ~= "" and a.short)) or nil
    r.act = a
    r.leaderFull = S(info.leaderName)
    if type(r.leaderFull) ~= "string" or r.leaderFull == "" then r.leaderFull = nil end
    r.leader = r.leaderFull and Short(r.leaderFull) or "?"
    r.title = S(info.name); if type(r.title) ~= "string" then r.title = "" end
    r.comment = S(info.comment); if type(r.comment) ~= "string" then r.comment = "" end
    r.members = SafeNumber(S(info.numMembers), 1)
    r.solo = r.members <= 1
    r.maxMembers = (maxP and maxP > 0 and maxP) or 5
    if r.members > r.maxMembers then r.maxMembers = r.members end
    r.free = math.max(0, r.maxMembers - r.members)
    r.ageSec = SafeNumber(S(info.age), nil)
    r.ageMin = r.ageSec and math.floor(r.ageSec / 60) or 0
    r.delisted = S(info.isDelisted) and true or false
    r.newPlayer = S(info.newPlayerFriendly) and true or false
    r.playstyle = GeneralPlaystyle(info, id)
    r.voice = S(info.voiceChat); if type(r.voice) ~= "string" or r.voice == "" then r.voice = nil end
    r.ilvl = SafeNumber(S(info.requiredItemLevel), 0)
    r.autoAccept = S(info.autoAccept) and true or false
    r.mine = S(info.hasSelf) and true or false
    -- members: member 1 is the leader (class, level); a solo listing says which roles the player takes
    local m1
    r.memberInfo = {}      -- kept for the tooltip: the game does not always answer again on hover
    for i = 1, math.min(r.members, 40) do
        local m = MemberInfo(id, i)
        r.memberInfo[i] = m or false
        if m then
            if i == 1 or m.isLeader then
                if not m1 or m.isLeader then m1 = m end
            end
        end
    end
    if m1 then
        r.class, r.classLoc, r.level = m1.class, m1.classLoc, m1.level
        if r.leader == "?" and m1.name and m1.name ~= "" then r.leaderFull = m1.name; r.leader = Short(m1.name) end
    end
    if r.leaderFull and not r.mine then
        local me = MyName()
        if me and Short(r.leaderFull) == me then r.mine = true end
    end
    -- roles: counts and open slots per role
    local tank, heal, dps, tf, hf, df = 0, 0, 0, 0, 0, 0
    local counts = C_LFGList.GetSearchResultMemberCounts and Pc(C_LFGList.GetSearchResultMemberCounts, id)
    if type(counts) == "table" then
        tank, heal, dps = SafeNumber(S(counts.TANK), 0), SafeNumber(S(counts.HEALER), 0), SafeNumber(S(counts.DAMAGER), 0)
        tf, hf, df = SafeNumber(S(counts.TANK_REMAINING), 0), SafeNumber(S(counts.HEALER_REMAINING), 0), SafeNumber(S(counts.DAMAGER_REMAINING), 0)
    end
    if r.solo and m1 and m1.lfgRoles and (tank + heal + dps) == 0 then
        if m1.lfgRoles.tank then tank = 1 end
        if m1.lfgRoles.healer then heal = 1 end
        if m1.lfgRoles.dps then dps = 1 end
    end
    r.tank, r.heal, r.dps = tank, heal, dps
    r.tankfree, r.healfree, r.dpsfree = tf, hf, df
    -- state
    if r.delisted then r.state = "Delisted"
    elseif r.mine then r.state = "Yours"
    elseif r.solo then r.state = r.playstyle or "Solo"
    elseif r.free == 0 then r.state = "Full"
    else r.state = r.playstyle or "Open" end
    return r
end

function ns.ReadResults()
    local list = ns.rows
    for i = #list, 1, -1 do list[i] = nil end
    local total, ids = 0, nil
    local getter = C_LFGList and (C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults)
    if getter then
        local ok, a, b = pcall(getter)
        if ok then
            if type(b) == "table" then ids, total = b, tonumber(a) or #b
            elseif type(a) == "table" then ids, total = a, #a end
        end
    end
    ns.myRoleKey = MyRoleKey()
    if ids then
        for i, id in ipairs(ids) do
            local ok, r = pcall(BuildRow, id, i)
            if ok and r then list[#list + 1] = r end
        end
    end
    -- game's default order = our default order
    table.sort(list, ns.DefaultLess)
    for i, r in ipairs(list) do r.idx = i end
    ns.total = total or #list
    ns.failed = false
    ns.lastRead = date and date("%H:%M:%S") or ""
    ns.searching = false
    ns.dirty = false
    if ns.OnData then ns.OnData() end
    if ns.RefreshRowTooltip then ns.RefreshRowTooltip() end
end

-- ------------------------------------------------------------ search (only from a click)
-- Returns true, or false + reason. Must be called straight from a click handler (the game requires a hardware event):
-- never from a menu pick or a timer. The search covers the category's activities usable at my level (all of them in "All activities" mode); picking activities in
-- our dropdown only narrows the table afterwards.
function ns.Search()
    if not (C_LFGList and C_LFGList.Search) then return false, "The group finder is not available on this client." end
    local cat = ns.CurrentCategory()
    if not cat then return false, "No category to search." end
    local acts = {}
    for _, a in ipairs(ns.Activities(cat, ns.P().activityMode ~= "all")) do acts[#acts + 1] = a.id end
    local lang = C_LFGList.GetLanguageSearchFilter and Pc(C_LFGList.GetLanguageSearchFilter)
    local attempts = {
        function() return pcall(C_LFGList.Search, cat, 0, 0, nil, false, nil, acts) end,
        function() return pcall(C_LFGList.Search, cat, 0, 0, lang) end,
        function() return pcall(C_LFGList.Search, cat, 0) end,
        function() return pcall(C_LFGList.Search, cat) end,
    }
    ns.tryRefused = false
    ns.trying = true
    local ok
    for _, try in ipairs(attempts) do
        ok = try()
        if ok or ns.tryRefused then break end
    end
    ns.trying = false
    if ns.tryRefused then return false, "The game refused the search from here. Press the game's own Refresh button once." end
    if not ok then return false, "The search call failed." end
    ns.searching = true
    ns.failed = false
    ns.searchStarted = GetTime and GetTime() or 0
    return true
end

-- ------------------------------------------------------------ filter + sort
local SORTERS = {
    leader = function(r) return r.leader:lower() end,
    level = function(r) return r.level or 0 end,
    activity = function(r) return (r.dungeon or ""):lower() end,
    members = function(r) return r.members end,
    roles = function(r) return r.tank * 10000 + r.heal * 100 + r.dps end,
    state = function(r) return (r.state or ""):lower() end,
    age = function(r) return r.ageSec or 0 end,
    default = function(r) return r.idx end,
    comment = function(r) return ((r.title ~= "" and r.title) or r.comment or ""):lower() end,
}
ns.SORTERS = SORTERS

function ns.SetFilter(text)
    text = text or ""
    ns.P().filter = text
    local fn, msg, pos, empty = ns.Filter.Compile(text)
    ns.filterFn, ns.filterErr, ns.filterPos, ns.filterEmpty = fn, msg, pos, empty
end

function ns.SortRows(list, key, asc)
    local get = SORTERS[key] or SORTERS.default
    table.sort(list, function(a, b)
        local ka, kb = get(a), get(b)
        if ka == kb then return a.idx < b.idx end    -- secondary order = game order, whatever the direction
        if asc then return ka < kb else return ka > kb end
    end)
end

function ns.BuildView()
    local p = ns.P()
    local view = ns.view
    for i = #view, 1, -1 do view[i] = nil end
    local fn = ns.filterFn
    if ns.filterFn == nil and ns.filterErr == nil then ns.SetFilter(p.filter); fn = ns.filterFn end
    local myLevel = MyLevel()
    for _, r in ipairs(ns.rows) do
        if ActivityPasses(r.act, myLevel) then
            local ok = true
            if fn then
                local good, res = pcall(fn, r)
                ok = (not good) or res   -- a failing row stays visible
            end
            if ok then view[#view + 1] = r end
        end
    end
    ns.SortRows(view, p.sortKey, p.sortAsc)
    return view
end

function ns.SetSort(key)
    local p = ns.P()
    if p.sortKey == key then p.sortAsc = not p.sortAsc else p.sortKey, p.sortAsc = key, true end
end

-- ------------------------------------------------------------ saved filters
function ns.SaveFilter(name, expr)
    local p = ns.P()
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = (expr or ""):sub(1, 28) end
    if name == "" then return nil end
    for i, f in ipairs(p.filters) do
        if f.name == name then f.expr = expr; return i end
    end
    p.filters[#p.filters + 1] = { name = name, expr = expr }
    return #p.filters
end
function ns.DeleteFilter(i)
    local p = ns.P()
    if p.filters[i] then table.remove(p.filters, i); return true end
end
function ns.RestoreFilters()
    local p = ns.P()
    for _, pf in ipairs(PRESET_FILTERS) do
        local found
        for _, f in ipairs(p.filters) do if f.name == pf.name then f.expr = pf.expr; found = true end end
        if not found then p.filters[#p.filters + 1] = { name = pf.name, expr = pf.expr } end
    end
end

-- ------------------------------------------------------------ message template
local function MyRoles()
    local out = {}
    local ok, leader, tank, healer, dps = pcall(function() if GetLFGRoles then return GetLFGRoles() end end)
    if ok and (tank or healer or dps) then
        if tank then out[#out + 1] = "tank" end
        if healer then out[#out + 1] = "healer" end
        if dps then out[#out + 1] = "dps" end
    end
    return table.concat(out, "/")
end
local function MySpec()
    local ok, name = pcall(function()
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
            local idx = C_SpecializationInfo.GetSpecialization()
            if idx and C_SpecializationInfo.GetSpecializationInfo then return select(2, C_SpecializationInfo.GetSpecializationInfo(idx)) end
        elseif GetSpecialization and GetSpecializationInfo then
            local idx = GetSpecialization()
            if idx then return select(2, GetSpecializationInfo(idx)) end
        end
    end)
    return (ok and type(name) == "string") and name or ""
end

local ALIASES = { currentclass = "class", currentlvl = "level", currentlevel = "level", targeteddungeon = "dungeon", targetdungeon = "dungeon", lfg = nil }

-- Fills the wildcards of `tpl` for `row` (nil row: sample values). Unknown {words} are left as typed.
function ns.ExpandTemplate(tpl, row)
    local className = (UnitClass and (UnitClass("player"))) or "Class"
    local level = (UnitLevel and tonumber(UnitLevel("player"))) or 1
    local p = ns.P()
    local dungeon = "Dungeon"
    if row then
        dungeon = (p.shortDungeon and row.dungeonShort) or row.dungeon or "?"
    end
    local vals = { class = className, level = tostring(level), role = MyRoles(), dungeon = dungeon,
                   leader = row and row.leader or "Leader", spec = MySpec() }
    local msg = tostring(tpl or ""):gsub("{(%w+)}", function(w)
        local k = w:lower()
        k = ALIASES[k] or k
        local v = vals[k]
        if v == nil then return nil end   -- keep unknown wildcards
        return v
    end)
    msg = msg:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #msg > 255 then msg = msg:sub(1, 255) end
    return msg
end

function ns.SampleRow()
    return ns.view[1] or ns.rows[1] or { dungeon = "Ragefire Chasm", dungeonShort = "RFC", leader = "Thrall" }
end

-- ------------------------------------------------------------ whispers already sent
-- FreeLFGDB.sent[name] = time() of my last whisper to that player (account-wide, kept SENT_KEEP).
-- Filled by Msg, and by CHAT_MSG_WHISPER_INFORM (the game confirms a whisper I sent: covers Custom).
local SENT_KEEP = 3 * 3600
local function Now() return (time and time()) or (os and os.time and os.time()) or 0 end
local function NameKey(n)
    if type(n) ~= "string" then return nil end
    if issecretvalue and issecretvalue(n) then return nil end
    local ok, k = pcall(function() return (n:gsub("%-.*$", "")):lower() end)   -- drop "-Realm"
    if not ok or not k or k == "" then return nil end
    return k
end
function ns.MarkSent(name)
    local k = NameKey(name)
    if not (k and db) then return end
    if type(db.sent) ~= "table" then db.sent = {} end
    db.sent[k] = Now()
end
-- seconds since my last whisper to `name`, or nil
function ns.SentAgo(name)
    local k = NameKey(name)
    local t = k and db and type(db.sent) == "table" and db.sent[k]
    if type(t) ~= "number" then return nil end
    local d = Now() - t
    if d < 0 or d > SENT_KEEP then return nil end
    return d
end
-- 42s · 3m 07s (under 10 min) · 14m · 1h05
function ns.SentText(sec)
    if not sec then return "" end
    sec = math.floor(sec)
    if sec < 60 then return sec .. "s" end
    local m = math.floor(sec / 60)
    if m < 10 then return m .. "m " .. string.format("%02d", sec % 60) .. "s" end
    if m < 60 then return m .. "m" end
    return math.floor(m / 60) .. "h" .. string.format("%02d", m % 60)
end
local function PurgeSent()
    if type(db.sent) ~= "table" then return end
    local now = Now()
    for k, t in pairs(db.sent) do
        if type(t) ~= "number" or now - t > SENT_KEEP or now - t < 0 then db.sent[k] = nil end
    end
end

-- ------------------------------------------------------------ actions (direct clicks)
local lastMsg = 0
function ns.Whisper(row)
    if not (row and row.leaderFull) then return false, "No leader name." end
    local now = GetTime and GetTime() or 0
    if now - lastMsg < 1 then return false, "wait" end        -- 1 s anti double click
    lastMsg = now
    local msg = ns.ExpandTemplate(ns.P().template, row)
    if msg == "" then return false, "The message template is empty." end
    local send = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)
    if not send then return false, "Cannot send messages here." end
    local ok = pcall(send, msg, "WHISPER", nil, row.leaderFull)
    if not ok then return false, "The game refused the whisper." end
    ns.lastSent = { to = row.leaderFull, msg = msg }
    ns.MarkSent(row.leaderFull)
    return true, msg
end

-- "Custom": open the chat box as a whisper to the leader, already holding the start of the message,
-- so the player types the rest and presses Enter himself. Names may contain spaces on this server,
-- so the whisper target is set directly (not through "/w Name text").
function ns.CustomWhisper(row)
    if not (row and row.leaderFull) then return false, "No leader name." end
    local start = ns.ExpandTemplate(ns.P().customStart or "", row)
    if start ~= "" and not start:find(" $") then start = start .. " " end
    local name = row.leaderFull
    local function active()
        return (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
            or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
    end
    -- 1. the game's own "whisper this player" (handles names with spaces)
    local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if sendTell and pcall(sendTell, name) then
        local eb = active()
        if eb then
            if start ~= "" and eb.Insert then eb:Insert(start) end
            if not ns.informOK then ns.MarkSent(name) end   -- no confirmation event: count the click
            return true, start
        end
    end
    -- 2. open the chat box and set the whisper target by hand
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    if open and pcall(open, "") then
        local eb = active()
        if eb and eb.SetAttribute then
            eb:SetAttribute("chatType", "WHISPER")
            eb:SetAttribute("tellTarget", name)
            local upd = ChatEdit_UpdateHeader or (ChatFrameUtil and ChatFrameUtil.UpdateHeader)
            if upd then pcall(upd, eb) end
            if start ~= "" and eb.Insert then eb:Insert(start) end
            if not ns.informOK then ns.MarkSent(name) end   -- no confirmation event: count the click
            return true, start
        end
    end
    return false, "Could not open the chat box."
end

-- Invite only exists for solo listings that are not mine, when I am alone or leader/assistant of my group.
-- Returns true, or false + the reason (shown in the tooltip). Groups are contacted with the whisper instead.
function ns.InviteWhy(row)
    if not row then return false, "" end
    if row.mine then return false, "This is your own listing." end
    if not row.solo then return false, "This is a group: use Msg to ask for a spot." end
    if not row.leaderFull then return false, "No player name." end
    if InGroup() then
        local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
        local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
        if not (lead or assist) then return false, "Only the leader or an assistant of your group can invite." end
    end
    return true, "Invite this player to your group."
end
function ns.CanInvite(row) return (ns.InviteWhy(row)) end
local lastInv = 0
function ns.Invite(row)
    local ok0, why = ns.InviteWhy(row)
    if not ok0 then return false, why end
    local now = GetTime and GetTime() or 0
    if now - lastInv < 1 then return false, "wait" end
    lastInv = now
    local inv = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not inv then return false, "Cannot invite from here." end
    local ok = pcall(inv, row.leaderFull)
    if not ok then return false, "The game refused the invite." end
    return true
end

-- ------------------------------------------------------------ profiles
local function OnProfileSwitch(d)
    ns.cat = nil
    ns.SetFilter(d.filter)
    if ns.OnProfileChanged then ns.OnProfileChanged() end
end

-- ------------------------------------------------------------ events
local ev = CreateFrame("Frame")
ns.eventFrame = ev
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_AVAILABILITY_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)   -- a name unknown to this client must not break us
end
ns.informOK = pcall(ev.RegisterEvent, ev, "CHAT_MSG_WHISPER_INFORM")   -- "To X: ..." = a whisper I sent
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "CHAT_MSG_WHISPER_INFORM" then
        if db then pcall(ns.MarkSent, arg2) end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            if arg1 and arg1:find("^Blizzard_GroupFinder") or arg1 == "Blizzard_LookingForGroupUI" then
                if ns.HookGameFrame then ns.HookGameFrame() end
            end
            return
        end
        FreeLFGDB = type(FreeLFGDB) == "table" and FreeLFGDB or {}
        db = FreeLFGDB
        db.minimap = db.minimap or { hide = false }
        PurgeSent()
        local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
        if LFP then
            ns.profiles = LFP:New("FreeLFG", db, OnProfileSwitch, Prepare, nil, { perCharacter = true })
        else
            db.profiles = db.profiles or {}
            db.profiles.Default = Prepare(db.profiles.Default or {})
            ns.fallback = db.profiles.Default
        end
        ns.SetFilter(ns.P().filter)
        return
    end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        if arg1 == ADDON then
            if ns.trying then ns.tryRefused = true
            else ns.Print("the game refused an action. Use the buttons of the table directly.") end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        if ns.profiles then ns.profiles:EnsureCharacter(); ns.profiles:Activate() end
        if ns.HookGameFrame then ns.HookGameFrame() end
        if ns.OnLogin then ns.OnLogin() end
        return
    end
    if event == "LFG_LIST_SEARCH_FAILED" then
        ns.searching = false
        ns.failed = true
        if ns.OnData then ns.OnData() end
        return
    end
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        if ns.P() then ns.ReadResults() end
        return
    end
    if event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_AVAILABILITY_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        ns.dirty = true      -- coalesced: read on the next frame
        return
    end
end)
ev:SetScript("OnUpdate", function()
    if ns.dirty and db then ns.ReadResults() end
end)

-- ------------------------------------------------------------ slash
SLASH_FREELFG1 = "/flfg"
SLASH_FREELFG2 = "/freelfg"
SlashCmdList.FREELFG = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "help" or msg == "?" then
        ns.Print("/flfg = open the table. Use its Refresh button to search (the game only allows a search from a click).")
        ns.Print("Filter examples: (heal >= 1 or tank >= 1) and dps <= 1   |   dps in 1..2   |   dungeon:\"razor\"")
    elseif msg == "tabs" then
        if ns.DebugTabs then ns.DebugTabs() end
    elseif msg == "members" then
        local gaps = db and db.memberGaps
        if type(gaps) ~= "table" or #gaps == 0 then ns.Print("no incomplete member info recorded.") return end
        ns.Print(#gaps .. " incomplete member answer(s), newest first:")
        for _, g in ipairs(gaps) do ns.Print(string.format("result %s, member %s: %s", tostring(g.id), tostring(g.i), g.fields or "?")) end
    elseif ns.Toggle then ns.Toggle() end
end
function FreeLFG_Toggle() if ns.Toggle then ns.Toggle() end end
