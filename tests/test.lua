#!/usr/bin/env lua

-- Lua CJSON tests
--
-- Mark Pulford <mark@kyne.com.au>
--
-- Note: The output of this script is easier to read with "less -S"

local json = require "cjson"
local util = require "cjson.util"

local function gen_ascii()
    local chars = {}
    for i = 0, 255 do chars[i + 1] = string.char(i) end
    return table.concat(chars)
end

-- Generate every UTF-16 codepoint, including supplementary codes
local function gen_utf16_escaped()
    -- Create raw table escapes
    local utf16_escaped = {}
    local count = 0

    local function append_escape(code)
        local esc = string.format('\\u%04X', code)
        table.insert(utf16_escaped, esc)
    end

    table.insert(utf16_escaped, '"')
    for i = 0, 0xD7FF do
        append_escape(i)
    end
    -- Skip 0xD800 - 0xDFFF since they are used to encode supplementary
    -- codepoints
    for i = 0xE000, 0xFFFF do
        append_escape(i)
    end
    -- Append surrogate pair for each supplementary codepoint
    for high = 0xD800, 0xDBFF do
        for low = 0xDC00, 0xDFFF do
            append_escape(high)
            append_escape(low)
        end
    end
    table.insert(utf16_escaped, '"')

    return table.concat(utf16_escaped)
end

function test_decode_cycle(filename)
    local obj1 = json.decode(util.file_load(filename))
    local obj2 = json.decode(json.encode(obj1))
    return util.compare_values(obj1, obj2)
end

local Inf = math.huge;
local NaN = math.huge * 0;
local octets_raw = gen_ascii()
local octets_escaped = util.file_load("octets-escaped.dat")
local utf8_loaded, utf8_raw = pcall(util.file_load, "utf8.dat")
if not utf8_loaded then
    utf8_raw = "Failed to load utf8.dat"
end
local utf16_escaped = gen_utf16_escaped()
local nested5 = {{{{{ "nested" }}}}}
local table_cycle = {}
local table_cycle2 = { table_cycle }
table_cycle[1] = table_cycle2

local decode_simple_tests = {
    { json.decode, { '"test string"' }, true, { "test string" } },
    { json.decode, { '-5e3' }, true, { -5000 } },
    { json.decode, { 'null' }, true, { json.null } },
    { json.decode, { 'true' }, true, { true } },
    { json.decode, { 'false' }, true, { false } },
    { json.decode, { '{ "1": "one", "3": "three" }' },
      true, { { ["1"] = "one", ["3"] = "three" } } },
    { json.decode, { '[ "one", null, "three" ]' },
      true, { { "one", json.null, "three" } } }
}

local encode_simple_tests = {
    { json.encode, { json.null }, true, { 'null' } },
    { json.encode, { true }, true, { 'true' } },
    { json.encode, { false }, true, { 'false' } },
    { json.encode, { { } }, true, { '{}' } },
    { json.encode, { 10 }, true, { '10' } },
    { json.encode, { NaN },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { json.encode, { Inf },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { json.encode, { "hello" }, true, { '"hello"' } },
}

local decode_numeric_tests = {
    { json.decode, { '[ 0.0, -1, 0.3e-3, 1023.2 ]' },
      true, { { 0.0, -1, 0.0003, 1023.2 } } },
    { json.decode, { '00123' }, true, { 123 } },
    { json.decode, { '05.2' }, true, { 5.2 } },
    { json.decode, { '0e10' }, true, { 0 } },
    { json.decode, { '0x6' }, true, { 6 } },
    { json.decode, { '[ +Inf, Inf, -Inf ]' }, true, { { Inf, Inf, -Inf } } },
    { json.decode, { '[ +Infinity, Infinity, -Infinity ]' },
      true, { { Inf, Inf, -Inf } } },
    { json.decode, { '[ +NaN, NaN, -NaN ]' }, true, { { NaN, NaN, NaN } } },
    { json.decode, { 'Infrared' },
      false, { "Expected the end but found invalid token at character 4" } },
    { json.decode, { 'Noodle' },
      false, { "Expected value but found invalid token at character 1" } },
}

local encode_table_tests = {
    function()
        json.encode_sparse_array(true, 2, 3)
        json.encode_max_depth(5)
        return "Setting sparse array (true, 2, 3) / max depth (5)"
    end,
    { json.encode, { { [3] = "sparse test" } },
      true, { '[null,null,"sparse test"]' } },
    { json.encode, { { [1] = "one", [4] = "sparse test" } },
      true, { '["one",null,null,"sparse test"]' } },
    { json.encode, { { [1] = "one", [5] = "sparse test" } },
      true, { '{"1":"one","5":"sparse test"}' } },

    { json.encode, { { ["2"] = "numeric string key test" } },
      true, { '{"2":"numeric string key test"}' } },

    { json.encode, { nested5 }, true, { '[[[[["nested"]]]]]' } },
    { json.encode, { { nested5 } },
      false, { "Cannot serialise, excessive nesting (6)" } },
    { json.encode, { table_cycle },
      false, { "Cannot serialise, excessive nesting (6)" } }
}

local encode_error_tests = {
    { json.encode, { { [false] = "wrong" } },
      false, { "Cannot serialise boolean: table key must be a number or string" } },
    { json.encode, { function () end },
      false, { "Cannot serialise function: type not supported" } },
    function ()
        json.encode_invalid_numbers(false)
        return 'Setting encode_invalid_numbers(false)'
    end,
    { json.encode, { NaN },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { json.encode, { Inf },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    function ()
        json.encode_invalid_numbers("null")
        return 'Setting encode_invalid_numbers("null").'
    end,
    { json.encode, { NaN }, true, { "null" } },
    { json.encode, { Inf }, true, { "null" } },
    function ()
        json.encode_invalid_numbers(true)
        return 'Setting encode_invalid_numbers(true).'
    end,
    { json.encode, { NaN }, true, { "nan" } },
    { json.encode, { Inf }, true, { "inf" } },
    function ()
        json.encode_invalid_numbers(false)
        return 'Setting encode_invalid_numbers(false)'
    end,
}

local decode_error_tests = {
    { json.decode, { '\0"\0"' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { json.decode, { '"\0"\0' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { json.decode, { '{ "unexpected eof": ' },
      false, { "Expected value but found T_END at character 21" } },
    { json.decode, { '{ "extra data": true }, false' },
      false, { "Expected the end but found T_COMMA at character 23" } },
    { json.decode, { ' { "bad escape \\q code" } ' },
      false, { "Expected object key string but found invalid escape code at character 16" } },
    { json.decode, { ' { "bad unicode \\u0f6 escape" } ' },
      false, { "Expected object key string but found invalid unicode escape code at character 17" } },
    { json.decode, { ' [ "bad barewood", test ] ' },
      false, { "Expected value but found invalid token at character 20" } },
    { json.decode, { '[ -+12 ]' },
      false, { "Expected value but found invalid number at character 3" } },
    { json.decode, { '-v' },
      false, { "Expected value but found invalid number at character 1" } },
    { json.decode, { '[ 0.4eg10 ]' },
      false, { "Expected comma or array end but found invalid token at character 6" } },
    function ()
        json.decode_max_depth(5)
        return "Setting decode_max_depth(5)"
    end,
    { json.decode, { '[[[[[ "nested" ]]]]]' },
      true, { {{{{{ "nested" }}}}} } },
    { json.decode, { '[[[[[[ "nested" ]]]]]]' },
      false, { "Too many nested data structures" } },
    function ()
        json.decode_max_depth(1000)
        return "Setting decode_max_depth(1000)"
    end
}

local escape_tests = {
    -- Test 8bit clean
    { json.encode, { octets_raw }, true, { octets_escaped } },
    { json.decode, { octets_escaped }, true, { octets_raw } },
    -- Ensure high bits are removed from surrogate codes
    { json.decode, { '"\\uF800"' }, true, { "\239\160\128" } },
    -- Test inverted surrogate pairs
    { json.decode, { '"\\uDB00\\uD800"' },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    -- Test 2x high surrogate code units
    { json.decode, { '"\\uDB00\\uDB00"' },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    -- Test invalid 2nd escape
    { json.decode, { '"\\uDB00\\"' },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { json.decode, { '"\\uDB00\\uD"' },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    -- Test decoding of all UTF-16 escapes
    { json.decode, { utf16_escaped }, true, { utf8_raw } }
}

-- The standard Lua interpreter is ANSI C online doesn't support locales
-- by default. Force a known problematic locale to test strtod()/sprintf().
local locale_tests = {
    function ()
        os.setlocale("cs_CZ")
        json.new()
        return "Setting locale to cs_CZ (comma separator)"
    end,
    { json.encode, { 1.5 }, true, { '1.5' } },
    { json.decode, { "[ 10, \"test\" ]" }, true, { { 10, "test" } } },
    function ()
        os.setlocale("C")
        json.new()
        return "Reverting locale to POSIX"
    end
}

print(string.format("Testing Lua CJSON version %s\n", json.version))

util.run_test_group("decode simple value", decode_simple_tests)
util.run_test_group("encode simple value", encode_simple_tests)
util.run_test_group("decode numeric", decode_numeric_tests)
util.run_test_group("encode table", encode_table_tests)
util.run_test_group("decode error", decode_error_tests)
util.run_test_group("encode error", encode_error_tests)
util.run_test_group("escape", escape_tests)
util.run_test_group("locale", locale_tests)

json.encode_invalid_numbers(true)
json.decode_invalid_numbers(true)
json.encode_max_depth(20)
for i = 1, #arg do
    util.run_test("decode cycle " .. arg[i], test_decode_cycle, { arg[i] },
                  true, { true })
end

local pass, total = util.run_test_summary()

if pass == total then
    print("==> Summary: all tests succeeded")
else
    print(string.format("==> Summary: %d/%d tests failed", total - pass, total))
    os.exit(1)
end

-- vi:ai et sw=4 ts=4:
