#!/usr/bin/env lua

-- Simple JSON benchmark.
--
-- Your Mileage May Vary.
--
-- Mark Pulford <mark@kyne.com.au>

require "common"
require "socket"
local json = require "cjson"

function benchmark(tests, iter, rep)
    local function bench(func, iter)
        -- collectgarbage("stop")
        collectgarbage("collect")
        local t = socket.gettime()
        for i = 1, iter do
            func(i)
        end
        t = socket.gettime() - t
        -- collectgarbage("restart")
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

function bench_file(filename)
    local data_json = file_load(filename)
    local data_obj = json.decode(data_json)

    local function test_encode ()
        json.encode(data_obj)
    end
    local function test_decode ()
        json.decode(data_json)
    end

    local tests = {
        encode = test_encode,
        decode = test_decode
    }

    return benchmark(tests, 5000, 5)
end

cjson.encode_keep_buffer(true)

for i = 1, #arg do
    local results = bench_file(arg[i])
    for k, v in pairs(results) do
        print(string.format("%s: %s: %d", arg[i], k, v))
    end
end

-- vi:ai et sw=4 ts=4:
