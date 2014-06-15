local os = require"os"
local lfs = require"lfs"
local m = require"lpeg"
local _ = require"underscore"

local C,Cb,Cf,Cg,Cp,Cs,Ct,Cmt = m.C,m.Cb,m.Cf,m.Cg,m.Cp,m.Cs,m.Ct,m.Cmt
local P,R,S,V = m.P,m.R,m.S,m.V
local I=Cp()

local list = {}

local addrom
do
    local any = P(1)
    local space = S' \t'
    local special = S'([.'
    local ROM, Filename, Name, Region, Languages, Tag, Other, Ext = V"ROM", V"Filename", V"Name", V"Region", V"Languages", V"Tag", V"Other", V"Ext"
    local grammar = { ROM,
        ROM = Ct(Filename);
        Filename = space^0 * Name * space^0 * Region^-1 * space^0 * Languages^-1 * space^0 * Cg(Ct(Tag^0), "tags") * space^0 * Other^0 * S'.' * Ext;
        Name = Cg((1 - P(special))^1, "name");
        Region = S'(' * Cg((any - S')')^1, "region") * S')';
        Languages = S'(' * Cg((any - S')')^1, "languages") * S')';
        Tag = space^0 * S'[' * C((any - S']')^1) * S']' * space^0;
        Other = Cg(any - S'.', "other");
        Ext = Cg(any^1, "ext");
    }
    local trim = function(s)
        return s:match"^%s*(.-)%s*$"
    end
    local printrom = function(e)
        local s = e.name
        if e.ext then s = s .. ' [Ext: ' .. e.ext .. ']' end
        if e.region then s = s .. ' [Region: ' .. e.region .. ']' end
        if e.languages then s = s .. ' [Languages: ' .. e.languages .. ']' end
        if e.tags and #e.tags > 0 then
            s = s .. ' [Tags: '
            for k,v in ipairs(e.tags) do
                s = s .. v .. ','
            end
            s = s:sub(1,-2) .. ']'
        end
        if e.other then s = s .. ' [Other: ' .. e.other .. ']' end
        print(s)
    end
    addrom = function(f, path)
        local e = m.match(grammar, f)
        if not e then e = { name = f } end
        e.name = trim(e.name)
        e.path = path
        local l = list[e.name] or {}
        table.insert(l, e)
        list[e.name] = l
    end
end

local scan
scan = function(dir)
    for f in lfs.dir(dir) do
        if f ~= '.' and f ~= '..' then
            local path = dir .. '/' .. f
            local att = lfs.attributes(path, 'mode')
            if att == 'directory' then scan(path)
            elseif att == 'file' then addrom(f, path) end
        end
    end
end

local remove = function()
    local totalcount = 0
    local deletecount = 0
    local favregion = { 'E', 'U', 'UE', 'W', 'PD', 'J' }
    local hastag = function(e, tag) return _.detect(e.tags, function(x) return x:match(tag) end) end
    for name,et in pairs(list) do
        local fav
        local isExclamation
        local selectregion = function(e)
            local old
            if fav.region then old = _.detect(favregion, function(x) return x == fav.region end) end
            local new = _.detect(favregion, function(x) return x == e.region end)
            if new and not old then fav = e return true
            elseif new and old and new < old then fav = e return true
            end
        end
        local selectworking = function(e)
            if not fav then fav = e return true end
            if hastag(fav, 'b%d+') and not hastag(e, 'b%d+') then fav = e return true end
            if hastag(fav, 'h%d+') and not hastag(e, 'h%d+') then fav = e return true end
            if hastag(fav, 'p%d+') and not hastag(e, 'p%d+') then fav = e return true end
            if hastag(fav, 't%d+') and not hastag(e, 't%d+') then fav = e return true end
            if hastag(fav, 'a%d+') and not hastag(e, 'a%d+') then fav = e return true end
            local trans = hastag(e, 'T%+(.*)')
            if trans then
                trans = string.upper(trans)
                if trans:sub(1,1) == 'F' then fav = e return true end
                if trans:sub(1,1) == 'E' then fav = e return true end
            end
        end
        for i,e in pairs(et) do
            if e.tags and hastag(e, '!') then
                if not fav or not isExclamation then
                    fav = e
                    isExclamation = true
                elseif isExclamation and e.region then
                    selectregion(e)
                end
            elseif not isExclamation then
                if not selectworking(e) then selectregion(e) end
            end
        end
        if not fav then fav = et[1] end
        totalcount = totalcount + #et
        deletecount = deletecount + #et - 1
        list[name] = { fav }
    end
    print('total:', totalcount, 'deleted:', deletecount, 'kept:', totalcount - deletecount)
end

local sort = function(mincount)
    local counts = {}
    local nextletter = function(l)
        if l == '(' then return '0'
        elseif l == '0' then return 'A'
        elseif l >= 'A' and l <= 'Z' then return string.char(string.byte(l) + 1)
        end
    end
    local move = function(first, last)
        local letter = first
        local dir = first
        if last ~= first then
            dir = first .. '-' .. last
        end
        dir = dir
        while letter do
            local files = counts[letter]
            if files then for k,v in ipairs(files) do
                v:gsub('\\', '/')
                if not v:find('/') then v = './' .. v end
                local sdir, file = v:match'(.*/)(.*)'
                sdir = sdir .. dir
                lfs.mkdir(sdir)
                os.rename(v, sdir .. '/' .. file)
                --print(v, '=>', sdir .. '/' .. file)
            end end
            if letter == last then break end
            letter = nextletter(letter)
        end
    end
    for k,v in pairs(list) do
        for kk,e in pairs(v) do
            local i = string.upper(e.name:sub(1,1))
            if i >= '0' and i <= '9' then i = '0'
            elseif i < 'A' or i > 'Z' then i = '('
            end
            if not counts[i] then counts[i] = {} end
            table.insert(counts[i], e.path)
        end
    end
    local count = 0
    local letter = '('
    local last = letter
    while letter do
        if counts[letter] then
            count = count + #counts[letter]
            if count >= mincount then 
                move(last, letter)
                last = letter
                count = 0
            end
        end
        letter = nextletter(letter)
    end
    if count > 0 then move(last, 'Z') end
end

local args = {...}
local dir = '.'
if #args > 0 then dir = args[1] end
scan(dir)
remove()
io.write('proceed? [y,N]: ')
local answer = io.read()
if answer == 'y' or answer == 'Y' then
    sort(100)
end

