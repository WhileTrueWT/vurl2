local lp
local lines = {}
local branches = {}
local globals = {}
local mem = globals
local callStack = {}
local functionReturn
local commands

local function parseLine(line)
    line = string.match(line, "^%s*(.*)%s*$")
    local cmd, argstring = string.match(line, "^(%w+)%s*(.*)")
    assert(cmd, "Malformed Command Name\n" .. tostring(line))
    
    local args = {}
    local i = 1
    local curArg = ""
    local isInQuotes = false
    local parensLevel = 0
    
    while i <= #argstring do
        local char = string.sub(argstring, i, i)
        
        if char == "\\" then
            i = i + 1
            curArg = curArg .. string.sub(argstring, i, i)
        elseif char == '"' then
            isInQuotes = not isInQuotes
            curArg = curArg .. char
        elseif char == "(" then
            parensLevel = parensLevel + 1
            curArg = curArg .. char
        elseif char == ")" then
            parensLevel = parensLevel - 1
            curArg = curArg .. char
        elseif (not isInQuotes) and (parensLevel <= 0) and string.match(char, "%s") then
            table.insert(args, curArg)
            curArg = ""
        else
            curArg = curArg .. char
        end
        
        i = i + 1
    end
    
    if #curArg > 0 then
        table.insert(args, curArg)
    end
    
    local parsedArgs = {}
    for i, arg in ipairs(args) do
        if string.match(arg, "^%(.+%)$") then
            parsedArgs[i] = {type="cmd", value=parseLine(string.sub(arg, 2, -2))}
        elseif string.match(arg, "^\"(.*)\"$") then
            parsedArgs[i] = {type="lit", value=string.sub(arg, 2, -2)}
        elseif string.match(arg, "^%d") then
            parsedArgs[i] = {type="lit", value=arg}
        else
            parsedArgs[i] = {type="var", value=arg}
        end
    end
    
    local line = {}
    line.command = cmd
    line.args = parsedArgs
    
    return line
end

local function runLine(line)
    local args = {}
    for i, a in ipairs(line.args) do
        if a.type == "var" then
            if line.command == "set" and i == 1
            or line.command == "local" and i == 1
            or line.command == "define" then
                args[i] = a.value
            else
                args[i] = mem[a.value] or ""
            end
        elseif a.type == "cmd" then
            args[i] = runLine(a.value)
        elseif a.type == "lit" then
            args[i] = a.value
        end
    end
    
    local ret
    if commands[line.command] then
        ret = commands[line.command](args)
    end
    return ret or ""
end

local function runChunk(ln)
    lp = ln
    while lp <= #lines do
        local line = lines[lp]
        
        runLine(line)
        
        if functionReturn then
            local ret = functionReturn
            functionReturn = nil
            return ret
        end
        
        lp = lp + 1
    end
end

local function callFunction(fp, args)
    local locals = {args = args}
    setmetatable(locals, {
        __index = mem,
        __newindex = mem,
    })
    
    table.insert(callStack, {
        lp = lp,
        mem = mem,
        locals = locals
    })
    
    mem = callStack[#callStack].locals
    
    return runChunk(fp, args)
end

commands = {
    set = function(a)
        mem[a[1]] = a[2]
    end,
    ["local"] = function(a)
        rawset(mem, a[1], a[2])
    end,
    list = function(a)
        setmetatable(a, {
            __tostring = function(v)
                return string.format("[%s]", table.concat(v, ", "))
            end
        })
        return a
    end,
    index = function(a)
        if type(a[1]) ~= "table" then return "" end
        return a[1][tonumber(a[2])] or ""
    end,
    push = function(a)
        if type(a[1]) ~= "table" then return end
        table.insert(a[1], a[2])
    end,
    pop = function(a)
        if type(a[1]) ~= "table" then return "" end
        return table.remove(a[1])
    end,
    insert = function(a)
        if type(a[1]) ~= "table" then return end
        table.insert(a[1], a[3], a[2])
    end,
    remove = function(a)
        if type(a[1]) ~= "table" then return "" end
        return table.remove(a[1], a[2])
    end,
    replace = function(a)
        if type(a[1]) ~= "table" then return end
        if not tonumber(a[2]) then return end
        if tonumber(a[2]) > #a[1] then return end
        a[1][a[2]] = a[3]
    end,
    islist = function(a)
        return (type(a[1]) == "table") and "1" or "0"
    end,
    add = function(a)
        local n = 0
        for _, x in ipairs(a) do
            if tonumber(x) then
                n = n + tonumber(x)
            end
        end
        return tostring(n)
    end,
    sub = function(a)
        if (not tonumber(a[1])) or (not tonumber(a[2])) then return end
        return tostring(tonumber(a[1]) - tonumber(a[2]))
    end,
    mul = function(a)
        local n = 1
        for _, x in ipairs(a) do
            if tonumber(x) then
                n = n * tonumber(x)
            end
        end
        return tostring(n)
    end,
    div = function(a)
        if (not tonumber(a[1])) or (not tonumber(a[2])) then return end
        return tostring(tonumber(a[1]) / tonumber(a[2]))
    end,
    mod = function(a)
        if (not tonumber(a[1])) or (not tonumber(a[2])) then return end
        return tostring(tonumber(a[1]) % tonumber(a[2]))
    end,
    pow = function(a)
        if (not tonumber(a[1])) or (not tonumber(a[2])) then return end
        return tostring(tonumber(a[1]) ^ tonumber(a[2]))
    end,
    exp = function(a)
        if not tonumber(a[1]) then return end
        return math.exp(tostring(tonumber(a[1])))
    end,
    floor = function(a)
        if not tonumber(a[1]) then return end
        return math.floor(tostring(tonumber(a[1])))
    end,
    ceil = function(a)
        if not tonumber(a[1]) then return end
        return math.ceil(tostring(tonumber(a[1])))
    end,
    sqrt = function(a)
        if not tonumber(a[1]) then return end
        return math.sqrt(tostring(tonumber(a[1])))
    end,
    log = function(a)
        if not tonumber(a[1]) then return end
        return math.log(tostring(tonumber(a[1])))
    end,
    sin = function(a)
        if not tonumber(a[1]) then return end
        return math.sin(tostring(tonumber(a[1])))
    end,
    cos = function(a)
        if not tonumber(a[1]) then return end
        return math.cos(tostring(tonumber(a[1])))
    end,
    tan = function(a)
        if not tonumber(a[1]) then return end
        return math.tan(tostring(tonumber(a[1])))
    end,
    asin = function(a)
        if not tonumber(a[1]) then return end
        return math.asin(tostring(tonumber(a[1])))
    end,
    acos = function(a)
        if not tonumber(a[1]) then return end
        return math.acos(tostring(tonumber(a[1])))
    end,
    atan = function(a)
        if not tonumber(a[1]) then return end
        return math.atan(tostring(tonumber(a[1])))
    end,
    join = function(a)
        local s = ""
        for _, x in ipairs(a) do
            s = s .. x
        end
        return s
    end,
    len = function(a)
        return #a[1]
    end,
    substr = function(a)
        if type(a[1]) ~= "string" then return end
        if not tonumber(a[2]) then return "" end
        if not tonumber(a[3]) then return "" end
        if not (tonumber(a[2]) >= 1) then return "" end
        if not (tonumber(a[3]) >= 1) then return "" end
        return string.sub(a[1], tonumber(a[2]), tonumber(a[3]))
    end,
    eq = function(a)
        return (a[1] == a[2]) and "1" or "0"
    end,
    gt = function(a)
        return (tonumber(a[1]) > tonumber(a[2])) and "1" or "0"
    end,
    lt = function(a)
        return (tonumber(a[1]) < tonumber(a[2])) and "1" or "0"
    end,
    ["and"] = function(a)
        return (a[1] == "1" and a[2] == "1") and "1" or "0"
    end,
    ["or"] = function(a)
        return (a[1] == "1" or a[2] == "1") and "1" or "0"
    end,
    ["not"] = function(a)
        return (a[1] ~= "1") and "1" or "0"
    end,
    ["if"] = function(a)
        if a[1] ~= "1" then
            lp = branches[lp]
        end
    end,
    ["elseif"] = function(a)
        if a[1] ~= "1" then
            lp = branches[lp]
        end
    end,
    ["else"] = function(a)
    end,
    ["while"] = function(a)
        if a[1] ~= "1" then
            lp = branches[lp]
        end
    end,
    ["define"] = function(a)
        mem[a[1]] = lp
        lp = branches[lp]
    end,
    ["call"] = function(a)
        local args = {}
        for i, arg in ipairs(a) do
            if i > 1 then
                table.insert(args, arg)
            end
        end
        
        return callFunction(a[1]+1, args)
    end,
    ["return"] = function(a)
        if #callStack < 1 then return end
        local state = table.remove(callStack)
        lp = state.lp
        mem = state.mem
        functionReturn = a[1] or ""
    end,
    ["end"] = function(a)
        if branches[lp].type == "while" then
            lp = branches[lp].value - 1
        elseif branches[lp].type == "define" then
            if #callStack < 1 then return end
            local state = table.remove(callStack)
            lp = state.lp
            mem = state.mem
            functionReturn = ""
        end
    end,
    print = function(a)
        print(a[1])
    end,
    input = function(a)
        return io.read()
    end,
}

local function run(code)
    lines = {}
    local branchStack = {}
    branches = {}
    
    local lineNumber = 1
    for line in string.gmatch(code, "([^\n]+)") do
        if (not string.match(line, "^%s*#")) and (not string.match(line, "^%s+$")) then
            local parsedLine = parseLine(line)
            table.insert(lines, parsedLine)
            
            if parsedLine.command == "if"
            or parsedLine.command == "while"
            or parsedLine.command == "define" then
                table.insert(branchStack, {type=parsedLine.command, value=lineNumber})
            elseif parsedLine.command == "end" then
                local b = table.remove(branchStack)
                branches[lineNumber] = b
                branches[b.value] = lineNumber
            elseif parsedLine.command == "elseif" then
                local b = table.remove(branchStack)
                branches[b.value] = lineNumber-1
                table.insert(branchStack, {type=parsedLine.command, value=lineNumber})
            elseif parsedLine.command == "else" then
                local b = table.remove(branchStack)
                branches[b.value] = lineNumber-1
                table.insert(branchStack, {type=parsedLine.command, value=lineNumber})
            end
            
            lineNumber = lineNumber + 1
        end
    end
    
    runChunk(1)
end

local infile = ...
if not infile then
    print("error: no input file")
    os.exit()
end

local f = io.open(infile, "r")
local code = f:read("*a")
f:close()

run(code)
