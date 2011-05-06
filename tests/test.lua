#!/usr/bin/env lua

require "common"
local json = require "cjson"

local cjson_test_non_default = true

function run_tests(tests, func)
    for k, v in ipairs(tests) do
        local success, msg = pcall(func, v)
        if not success then
            print("Error: " .. msg)
        end
        print()
    end
end

local simple_value_tests = {
    [[ "test string" ]],
    [[ -5e3 ]],
    [[ null ]],
    [[ true ]],
    [[ false ]],
    [[ { "1": "one", "3": "three" } ]]
}

local numeric_tests = {
    "[ 0.0, -1, 0.3e-3, 1023.2 ]",
    "[ 00123 ]",
    "[ 05.2 ]",
    "[ 0e10 ]",
    "[ 0x6 ]",
    "[ +Inf ]",
    "[ Inf ]",
    "[ -Inf ]",
    "[ +Infinity ]",
    "[ Infinity ]",
    "[ -Infinity ]",
    "[ +NaN ]",
    "[ NaN ]",
    "[ -NaN ]",
    "[ Infrared ]",
    "[ Noodle ]"
}

local object_tests = {
    { [5] = "sparse test" },
    { [6] = "sparse test" },
    {{{{{{{{{{{{{{{{{{{{{ "nested" }}}}}}}}}}}}}}}}}}}}}
}

local decode_error_tests = {
    '{ "unexpected eof": ',
    '{ "extra data": true }, false',
    [[ { "bad escape \q code" } ]],
    [[ { "bad unicode \u0f6 escape" } ]],
    [[ [ "bad barewood", test ] ]],
    "[ -+12 ]",
    "-v",
    "[ 0.4eg10 ]",
}

local simple_encode_tests = {
    json.null, true, false, { }, 10, "hello"
}


local function gen_ascii(max)
    local chars = {}
    for i = 0, max do
        chars[i] = string.char(i)
    end
    return table.concat(chars)
end

local function decode_encode(text)
    print("==JSON=> " .. text)
    local obj_data = json.decode(text)
    dump_value(obj_data)
    local obj_json = json.encode(obj_data)
    print(obj_json)
end
local function encode_decode(obj)
    print("==OBJ==> ")
    dump_value(obj)
    local obj_json = json.encode(obj)
    print(obj_json)
    local obj_data = json.decode(obj_json)
    dump_value(obj_data)
end

run_tests(simple_value_tests, decode_encode)
run_tests(decode_error_tests, decode_encode)

run_tests(numeric_tests, decode_encode)

if cjson_test_non_default then
    print("=== Disabling strict numbers ===")
    json.strict_numbers(false)
    run_tests(numeric_tests, decode_encode)
    json.strict_numbers(true)
end

run_tests(object_tests, encode_decode)
print ("Encode tests..")

run_tests(simple_encode_tests, encode_decode)

if cjson_test_non_default then
    print("=== Setting max_depth to 21, sparse_ratio to 5 ===")
    json.max_depth(21)
    json.sparse_ratio(5)
    run_tests(object_tests, encode_decode)
end

local ascii1 = gen_ascii(255)
print("Unprintable escapes:")
print(json.encode(ascii1))
print("===")
local ascii2 = json.decode(json.encode(ascii))

print("8bit clean encode/decode: " .. tostring(ascii1 ~= ascii2))

for i = 1, #arg do
    local obj1 = json.decode(file_load(arg[i]))
    local obj2 = json.decode(json.encode(obj1))
    if compare_values(obj, obj) then
        print(arg[i] .. ": PASS")
    else
        print(arg[i] .. ": FAIL")
        print("== obj1 ==")
        dump_value(obj1)
        print("== obj2 ==")
        dump_value(obj2)
    end
end

-- vi:ai et sw=4 ts=4:
