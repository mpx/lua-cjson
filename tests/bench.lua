#!/usr/bin/env lua

-- Simple JSON benchmark.
--
-- Your Mileage May Vary.

require "common"
local json = require "cjson"
--local json = require "json"
--local json = require "dkjson"

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

i = 1
while arg[i] do
    local results = {}
    results[arg[i]] = bench_file(arg[i])
    dump_value(results)
    i = i + 1
end

-- vi:ai et sw=4 ts=4:
