require "cjson"
require "posix"

function dump_value(value, indent)
    if indent == nil then
        indent = ""
    end

    if value == cjson.null then
        value = "<cjson.null>"
    end

    if type(value) == "string" or type(value) == "number" or
       type(value) == "boolean" then
        print(indent .. tostring(value))
    elseif type(value) == "table" then
        local count = 0
        for k, v in pairs(value) do
            dump_value(v, indent .. k .. ":  ")
            count = count + 1
        end
        if count == 0 then
            print(indent .. ": <empty>")
        end
    else
        print(indent .. "<" .. type(value) .. ">")
    end

end

function file_load(filename)
    local file, err = io.open(filename)
    if file == nil then
        error("Unable to read " .. filename)
    end
    local data = file:read("*a")
    file:close()

    return data
end

function gettimeofday()
    local tv_sec, tv_usec = posix.gettimeofday()

    return tv_sec + tv_usec / 1000000
end

function benchmark(tests, iter, rep)
    local function bench(func, iter)
        collectgarbage("collect")
        local t = gettimeofday()
        for i = 1, iter do
            func(i)
        end
        t = gettimeofday() - t
        return (iter / t)
    end

    local test_results = {}
    for name, func in pairs(tests) do
        -- k(number), v(string)
        -- k(string), v(function)
        -- k(number), v(function)
        if type(func) == "string" then
            name = func
            func = _G[name]
        end
        local result = {}
        for i = 1, rep do
            result[i] = bench(func, iter)
        end
        table.sort(result)
        test_results[name] = result[rep]
    end

    return test_results
end

function compare_values(val1, val2)
    local type1 = type(val1)
    local type2 = type(val2)
    if type1 ~= type2 then
        return false
    end
    if type1 ~= "table" then
        return val1 == val2
    end
    local val1_keys = {}
    -- Note all the keys in val1 need to be checked
    for k, _ in pairs(val1) do
        check_keys[k] = true
    end
    for k, v in pairs(val2) do
        if not check_keys[k] then
            -- Key didn't exist in val1
            return false
        end
        if not compare_value(val1[k], val2[k]) then
            return false
        end
        check_keys[k] = nil
    end
    for k, _ in pairs(check_keys) do
        -- Not the same if any keys left to check
        return false
    end
    return true
end

-- vi:ai et sw=4 ts=4:
