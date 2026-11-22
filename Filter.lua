-- Free LFG - live filter expressions.
-- A tiny hand-written tokenizer + recursive-descent parser (no loadstring / load, nothing is ever executed
-- from the text). ns.Filter.Compile(text) -> fn(row) -> boolean, or nil, message, position.
--
--   expr    := or
--   or      := and { ("or" | "||") and }
--   and     := not { ("and" | "&&") not }
--   not     := ("not" | "!") not | primary
--   primary := "(" expr ")" | text | comparison
--   text    := field ":" ( "quoted" | word )          field = name, dungeon, comment, class, state
--   compare := sum [ op sum [ op sum ] ]              op = >= <= > < = == != <>   (1 <= dps <= 2 chains)
--            | sum "in" sum ".." sum
--            | sum "between" sum "and" sum
--   sum     := term { ("+" | "-") term }              term := factor { "*" factor }
--   factor  := number | variable | "(" sum ")" | "-" factor

local ADDON, ns = ...
local F = {}
ns.Filter = F

-- name -> function(row) returning a number
local VARS = {
    tank = function(r) return r.tank or 0 end,
    heal = function(r) return r.heal or 0 end,
    healer = function(r) return r.heal or 0 end,
    dps = function(r) return r.dps or 0 end,
    damage = function(r) return r.dps or 0 end,
    members = function(r) return r.members or 0 end,
    size = function(r) return r.members or 0 end,
    free = function(r) return r.free or 0 end,
    tankfree = function(r) return r.tankfree or 0 end,
    healfree = function(r) return r.healfree or 0 end,
    dpsfree = function(r) return r.dpsfree or 0 end,
    solo = function(r) return r.solo and 1 or 0 end,
    level = function(r) return r.level or 0 end,
    age = function(r) return r.ageMin or 0 end,
    delisted = function(r) return r.delisted and 1 or 0 end,
}
-- one counter per class: members of that class in the group, leader included (1.0.21).
-- Counts only the members the game described; the others are in "unknown".
local CLASS_VARS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
    deathknight = "DEATHKNIGHT", dk = "DEATHKNIGHT", monk = "MONK", demonhunter = "DEMONHUNTER", dh = "DEMONHUNTER", evoker = "EVOKER",
}
for name, token in pairs(CLASS_VARS) do
    local get = function(r) return (r.classCount and r.classCount[token]) or 0 end
    VARS[name] = get
    if name:len() > 2 then VARS[name .. "s"] = get end      -- "rogues >= 2" reads naturally too
end
VARS.unknown = function(r) return r.unknownClass or 0 end
F.CLASS_VARS = CLASS_VARS
F.VARS = VARS
-- text fields -> function(row) returning a string
local FIELDS = {
    name = function(r) return r.leader or "" end,
    leader = function(r) return r.leader or "" end,
    dungeon = function(r) return (r.dungeon or "") .. " " .. (r.dungeonShort or "") end,
    activity = function(r) return (r.dungeon or "") .. " " .. (r.dungeonShort or "") end,
    comment = function(r) return (r.title or "") .. " " .. (r.comment or "") end,
    class = function(r) return (r.classLoc or "") .. " " .. (r.class or "") end,
    state = function(r) return r.state or "" end,
}
F.FIELDS = FIELDS

local function Fail(msg, pos) error({ msg = msg, pos = pos }, 0) end

-- ------------------------------------------------------------ tokenizer
-- token = { t = type, v = value, pos = start column }
-- types: num, id, field, str, op (comparison), lp, rp, plus, minus, star, range, and, or, not, in, between, eof
local KEYWORDS = { ["and"] = "and", ["or"] = "or", ["not"] = "not", ["in"] = "in", ["between"] = "between" }

local function Tokenize(s)
    local toks, i, n = {}, 1, #s
    local function add(t, v, pos) toks[#toks + 1] = { t = t, v = v, pos = pos } end
    while i <= n do
        local c = s:sub(i, i)
        local two = s:sub(i, i + 1)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") then
            local j = i
            while s:sub(j, j):match("%d") do j = j + 1 end
            -- a decimal point only when a digit follows ("1..2" is a range, not "1." and ".2")
            if s:sub(j, j) == "." and s:sub(j + 1, j + 1):match("%d") then
                j = j + 1
                while s:sub(j, j):match("%d") do j = j + 1 end
            end
            add("num", tonumber(s:sub(i, j - 1)), i)
            i = j
        elseif c:match("[%a_]") then
            local j = i
            while s:sub(j, j):match("[%w_]") do j = j + 1 end
            local word = s:sub(i, j - 1)
            local low = word:lower()
            if s:sub(j, j) == ":" then
                add("field", low, i); i = j + 1
            elseif KEYWORDS[low] then
                add(KEYWORDS[low], low, i); i = j
            else
                add("id", low, i); i = j
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and s:sub(j, j) ~= c do j = j + 1 end
            if j > n then Fail("Unterminated text (missing " .. c .. ")", i) end
            add("str", s:sub(i + 1, j - 1), i)
            i = j + 1
        elseif two == ">=" or two == "<=" or two == "==" or two == "!=" or two == "<>" then
            add("op", (two == "==") and "=" or (two == "<>" and "!=" or two), i); i = i + 2
        elseif two == "&&" then add("and", "&&", i); i = i + 2
        elseif two == "||" then add("or", "||", i); i = i + 2
        elseif two == ".." then add("range", "..", i); i = i + 2
        elseif c == ">" or c == "<" or c == "=" then add("op", c, i); i = i + 1
        elseif c == "!" then add("not", "!", i); i = i + 1
        elseif c == "(" then add("lp", c, i); i = i + 1
        elseif c == ")" then add("rp", c, i); i = i + 1
        elseif c == "+" then add("plus", c, i); i = i + 1
        elseif c == "-" then add("minus", c, i); i = i + 1
        elseif c == "*" then add("star", c, i); i = i + 1
        else
            Fail("Unexpected character '" .. c .. "'", i)
        end
    end
    add("eof", nil, n + 1)
    return toks
end

local function Describe(tok)
    if tok.t == "eof" then return "end of the expression" end
    if tok.t == "num" then return "number " .. tostring(tok.v) end
    if tok.t == "str" then return "text \"" .. tok.v .. "\"" end
    return "'" .. tostring(tok.v) .. (tok.t == "field" and ":" or "") .. "'"
end

-- ------------------------------------------------------------ parser (builds closures)
local CMP = {
    [">="] = function(a, b) return a >= b end, ["<="] = function(a, b) return a <= b end,
    [">"] = function(a, b) return a > b end, ["<"] = function(a, b) return a < b end,
    ["="] = function(a, b) return a == b end, ["!="] = function(a, b) return a ~= b end,
}
local function truthy(v) return v ~= nil and v ~= false and v ~= 0 end

local function Parse(toks, src)
    local p = 1
    local function peek() return toks[p] end
    local function nextTok() local t = toks[p]; p = p + 1; return t end
    local function expect(t, what)
        local tok = peek()
        if tok.t ~= t then Fail("Expected " .. what .. " but found " .. Describe(tok), tok.pos) end
        return nextTok()
    end

    local expr, sum

    local function factor()
        local tok = nextTok()
        if tok.t == "num" then
            local v = tok.v
            return function() return v end
        elseif tok.t == "id" then
            local get = VARS[tok.v]
            if not get then
                local names = {}
                for k in pairs(VARS) do
                    local base = k:gsub("s$", "")
                    if not CLASS_VARS[k] and not CLASS_VARS[base] then names[#names + 1] = k end   -- classes listed once below
                end
                table.sort(names)
                Fail("Unknown variable '" .. tok.v .. "' (use: " .. table.concat(names, ", ") .. ", or a class: rogue, mage, priest...)", tok.pos)
            end
            return get
        elseif tok.t == "minus" then
            local f = factor()
            return function(r) return -f(r) end
        elseif tok.t == "lp" then
            local e = sum()
            expect("rp", "')'")
            return e
        end
        p = p - 1
        Fail("Expected a number or a variable but found " .. Describe(tok), tok.pos)
    end
    local function term()
        local a = factor()
        while peek().t == "star" do
            nextTok()
            local b, l = factor(), a
            a = function(r) return l(r) * b(r) end
        end
        return a
    end
    function sum()
        local a = term()
        while peek().t == "plus" or peek().t == "minus" do
            local op = nextTok().t
            local b, l = term(), a
            if op == "plus" then a = function(r) return l(r) + b(r) end
            else a = function(r) return l(r) - b(r) end end
        end
        return a
    end

    local function textMatch()
        local f = nextTok()                     -- field
        local get = FIELDS[f.v]
        if not get then
            local names = {}
            for k in pairs(FIELDS) do names[#names + 1] = k end
            table.sort(names)
            Fail("Unknown text field '" .. f.v .. ":' (use: " .. table.concat(names, ", ") .. ")", f.pos)
        end
        local tok = nextTok()
        local needle
        if tok.t == "str" then needle = tok.v
        elseif tok.t == "id" or tok.t == "num" then needle = tostring(tok.v)
        else p = p - 1; Fail("Expected a text after '" .. f.v .. ":' (like " .. f.v .. ":\"abc\")", tok.pos) end
        needle = needle:lower()
        return function(r) return (get(r) or ""):lower():find(needle, 1, true) ~= nil end
    end

    local function comparison()
        local a = sum()
        local tok = peek()
        if tok.t == "in" then
            nextTok()
            local lo = sum()
            expect("range", "'..' (like 1..2)")
            local hi = sum()
            return function(r) local v = a(r); return v >= lo(r) and v <= hi(r) end
        elseif tok.t == "between" then
            nextTok()
            local lo = sum()
            expect("and", "'and' (like between 1 and 2)")
            local hi = sum()
            return function(r) local v = a(r); return v >= lo(r) and v <= hi(r) end
        elseif tok.t == "op" then
            nextTok()
            local b = sum()
            local f1 = CMP[tok.v]
            local first = function(r) return f1(a(r), b(r)) end
            if peek().t == "op" then          -- chain: 1 <= dps <= 2  ==  (1 <= dps) and (dps <= 2)
                local op2 = nextTok()
                local c = sum()
                local f2 = CMP[op2.v]
                return function(r) return first(r) and f2(b(r), c(r)) end
            end
            return first
        end
        -- a bare value means "not zero": "heal" = at least one healer
        return function(r) return a(r) ~= 0 end
    end

    local function primary()
        local tok = peek()
        if tok.t == "lp" then
            -- "(" may open a group of conditions or a parenthesised sum ("(tank+heal) >= 2"):
            -- try the group first, fall back to a comparison if what follows is an operator
            local save = p
            nextTok()
            local ok, e = pcall(expr)
            if ok and peek().t == "rp" then
                nextTok()
                local nt = peek().t
                if nt ~= "op" and nt ~= "in" and nt ~= "between" and nt ~= "plus" and nt ~= "minus" and nt ~= "star" then return e end
            elseif ok and peek().t == "eof" then
                Fail("Missing ')' to close the group", tok.pos)
            elseif not ok then
                -- may be a sum in parentheses: re-parse as comparison; if that fails too, report the group's error
                p = save
                local ok2, e2 = pcall(comparison)
                if ok2 then return e2 end
                error(e, 0)
            end
            p = save
            return comparison()
        elseif tok.t == "field" then
            return textMatch()
        end
        return comparison()
    end

    local function notExpr()
        if peek().t == "not" then
            nextTok()
            local e = notExpr()
            return function(r) return not truthy(e(r)) end
        end
        return primary()
    end
    local function andExpr()
        local a = notExpr()
        while peek().t == "and" do
            nextTok()
            local b, l = notExpr(), a
            a = function(r) return truthy(l(r)) and truthy(b(r)) end
        end
        return a
    end
    function expr()
        local a = andExpr()
        while peek().t == "or" do
            nextTok()
            local b, l = andExpr(), a
            a = function(r) return truthy(l(r)) or truthy(b(r)) end
        end
        return a
    end

    local root = expr()
    local tok = peek()
    if tok.t ~= "eof" then
        if tok.t == "rp" then Fail("Unexpected ')' (no matching '(')", tok.pos) end
        Fail("Unexpected " .. Describe(tok) .. " (missing 'and' / 'or'?)", tok.pos)
    end
    return function(r) return truthy(root(r)) end
end

-- Compile(text): function(row) -> boolean for a valid expression (empty text -> always true),
-- or nil, message, position for an invalid one. Never raises.
function F.Compile(text)
    text = tostring(text or "")
    if text:match("^%s*$") then return function() return true end, nil, nil, true end
    local ok, res = pcall(function() return Parse(Tokenize(text), text) end)
    if ok then return res end
    if type(res) == "table" and res.msg then return nil, res.msg, res.pos end
    return nil, "Cannot read this filter", 1
end

F.help = {
    "Variables: tank heal dps (in the group)  tankfree healfree dpsfree (open slots)  members free level age (min)  solo delisted",
    "Classes: warrior paladin hunter rogue priest shaman mage warlock druid (members of that class)  unknown (class not given)",
    "Compare: >= <= > < = !=      Range: dps in 1..2   1 <= dps <= 2   dps between 1 and 2",
    "Combine: and  or  not  ( )   (also && |||| !)      Maths: tank + heal >= 2",
    "Text: name:\"abc\"  dungeon:\"razor\"  comment:\"fast\"  class:\"mage\"  state:\"relaxed\"",
    "Example: (heal >= 1 or tank >= 1) and dps <= 1      rogue >= 1 and healfree >= 1",
}
