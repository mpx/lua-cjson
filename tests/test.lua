#!/usr/bin/env lua

-- Lua CJSON tests
--
-- Mark Pulford <mark@kyne.com.au>
--
-- Note: The output of this script is easier to read with "less -S"

local json = require "cjson"
local util = require "cjson.util"

local function gen_raw_octets()
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

-- Set up data used in tests
local Inf = math.huge;
local NaN = math.huge * 0;

local octets_raw = gen_raw_octets()
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

local all_tests = {
    -- Simple decode tests
    { "Decode string",
      json.decode, { '"test string"' }, true, { "test string" } },
    { "Decode number with exponent",
      json.decode, { '-5e3' }, true, { -5000 } },
    { "Decode null",
      json.decode, { 'null' }, true, { json.null } },
    { "Decode true",
      json.decode, { 'true' }, true, { true } },
    { "Decode false",
      json.decode, { 'false' }, true, { false } },
    { "Decode object with numeric keys",
      json.decode, { '{ "1": "one", "3": "three" }' },
      true, { { ["1"] = "one", ["3"] = "three" } } },
    { "Decode array",
      json.decode, { '[ "one", null, "three" ]' },
      true, { { "one", json.null, "three" } } },

    -- Numeric decode tests
    { "Decode various numbers",
      json.decode, { '[ 0.0, -1, 0.3e-3, 1023.2 ]' },
      true, { { 0.0, -1, 0.0003, 1023.2 } } },
    { "Decode integer with leading zeros",
      json.decode, { '00123' }, true, { 123 } },
    { "Decode floating point with leading zero",
      json.decode, { '05.2' }, true, { 5.2 } },
    { "Decode zero with exponent",
      json.decode, { '0e10' }, true, { 0 } },
    { "Decode hexadecimal",
      json.decode, { '0x6' }, true, { 6 } },
    { "Decode +-Inf",
      json.decode, { '[ +Inf, Inf, -Inf ]' }, true, { { Inf, Inf, -Inf } } },
    { "Decode +-Infinity",
      json.decode, { '[ +Infinity, Infinity, -Infinity ]' },
      true, { { Inf, Inf, -Inf } } },
    { "Decode +-NaN",
      json.decode, { '[ +NaN, NaN, -NaN ]' }, true, { { NaN, NaN, NaN } } },
    { "Decode Infrared (not infinity)",
      json.decode, { 'Infrared' },
      false, { "Expected the end but found invalid token at character 4" } },
    { "Decode Noodle (not NaN)",
      json.decode, { 'Noodle' },
      false, { "Expected value but found invalid token at character 1" } },

    -- Decode error tests
    { "Decode UTF-16BE",
      json.decode, { '\0"\0"' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-16LE",
      json.decode, { '"\0"\0' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-32BE",
      json.decode, { '\0\0\0"' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-32LE",
      json.decode, { '"\0\0\0' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode partial JSON",
      json.decode, { '{ "unexpected eof": ' },
      false, { "Expected value but found T_END at character 21" } },
    { "Decode with extra comma",
      json.decode, { '{ "extra data": true }, false' },
      false, { "Expected the end but found T_COMMA at character 23" } },
    { "Decode invalid escape code",
      json.decode, { [[ { "bad escape \q code" } ]] },
      false, { "Expected object key string but found invalid escape code at character 16" } },
    { "Decode invalid unicode escape",
      json.decode, { [[ { "bad unicode \u0f6 escape" } ]] },
      false, { "Expected object key string but found invalid unicode escape code at character 17" } },
    { "Decode invalid keyword",
      json.decode, { ' [ "bad barewood", test ] ' },
      false, { "Expected value but found invalid token at character 20" } },
    { "Decode invalid number #1",
      json.decode, { '[ -+12 ]' },
      false, { "Expected value but found invalid number at character 3" } },
    { "Decode invalid number #2",
      json.decode, { '-v' },
      false, { "Expected value but found invalid number at character 1" } },
    { "Decode invalid number exponent",
      json.decode, { '[ 0.4eg10 ]' },
      false, { "Expected comma or array end but found invalid token at character 6" } },
    { "Setting decode_max_depth(5)", function ()
        json.decode_max_depth(5)
    end },
    { "Decode array at nested limit",
      json.decode, { '[[[[[ "nested" ]]]]]' },
      true, { {{{{{ "nested" }}}}} } },
    { "Decode array over nested limit",
      json.decode, { '[[[[[[ "nested" ]]]]]]' },
      false, { "Too many nested data structures" } },
    { "Setting decode_max_depth(1000)", function ()
        json.decode_max_depth(1000)
    end },

    -- Simple encode tests
    { "Encode null",
      json.encode, { json.null }, true, { 'null' } },
    { "Encode true",
      json.encode, { true }, true, { 'true' } },
    { "Encode false",
      json.encode, { false }, true, { 'false' } },
    { "Encode empty object",
      json.encode, { { } }, true, { '{}' } },
    { "Encode integer",
      json.encode, { 10 }, true, { '10' } },
    { "Encode NaN (invalid numbers disabled)",
      json.encode, { NaN },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { "Encode Infinity (invalid numbers disabled)",
      json.encode, { Inf },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { "Encode string",
      json.encode, { "hello" }, true, { '"hello"' } },

    -- Table encode tests
    { "Setting sparse array (true, 2, 3) / max depth (5)", function()
        json.encode_sparse_array(true, 2, 3)
        json.encode_max_depth(5)
    end },
    { "Encode sparse table as array #1",
      json.encode, { { [3] = "sparse test" } },
      true, { '[null,null,"sparse test"]' } },
    { "Encode sparse table as array #2",
      json.encode, { { [1] = "one", [4] = "sparse test" } },
      true, { '["one",null,null,"sparse test"]' } },
    { "Encode sparse array as object",
      json.encode, { { [1] = "one", [5] = "sparse test" } },
      true, { '{"1":"one","5":"sparse test"}' } },

    { "Encode table with numeric string key as object",
      json.encode, { { ["2"] = "numeric string key test" } },
      true, { '{"2":"numeric string key test"}' } },

    { "Encode nested table",
      json.encode, { nested5 }, true, { '[[[[["nested"]]]]]' } },
    { "Encode nested table (throw error)",
      json.encode, { { nested5 } },
      false, { "Cannot serialise, excessive nesting (6)" } },
    { "Encode table with cycle",
      json.encode, { table_cycle },
      false, { "Cannot serialise, excessive nesting (6)" } },

    -- Encode error tests
    { "Encode table with incompatible key",
      json.encode, { { [false] = "wrong" } },
      false, { "Cannot serialise boolean: table key must be a number or string" } },
    { "Encode Lua function",
      json.encode, { function () end },
      false, { "Cannot serialise function: type not supported" } },
    { "Setting encode_invalid_numbers(false)", function ()
        json.encode_invalid_numbers(false)
    end },
    { "Encode NaN (invalid numbers disabled)",
      json.encode, { NaN },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { "Encode Infinity (invalid numbers disabled)",
      json.encode, { Inf },
      false, { "Cannot serialise number: must not be NaN or Inf" } },
    { 'Setting encode_invalid_numbers("null").', function ()
        json.encode_invalid_numbers("null")
    end },
    { "Encode NaN as null",
      json.encode, { NaN }, true, { "null" } },
    { "Encode Infinity as null",
      json.encode, { Inf }, true, { "null" } },
    { 'Setting encode_invalid_numbers(true).', function ()
        json.encode_invalid_numbers(true)
    end },
    { "Encode NaN",
      json.encode, { NaN }, true, { "nan" } },
    { "Encode Infinity",
      json.encode, { Inf }, true, { "inf" } },
    { 'Setting encode_invalid_numbers(false)', function ()
        json.encode_invalid_numbers(false)
    end },

    -- Escaping tests
    { "Encode all octets (8-bit clean)",
      json.encode, { octets_raw }, true, { octets_escaped } },
    { "Decode all escaped octets",
      json.decode, { octets_escaped }, true, { octets_raw } },
    { "Decode single UTF-16 escape",
      json.decode, { [["\uF800"]] }, true, { "\239\160\128" } },
    { "Decode swapped surrogate pair",
      json.decode, { [["\uDC00\uD800"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode duplicate high surrogate",
      json.decode, { [["\uDB00\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode duplicate low surrogate",
      json.decode, { [["\uDB00\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode missing low surrogate",
      json.decode, { [["\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode invalid low surrogate",
      json.decode, { [["\uDB00\uD"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode all UTF-16 escapes (including surrogate combinations)",
      json.decode, { utf16_escaped }, true, { utf8_raw } },

    -- Locale tests
    --
    -- The standard Lua interpreter is ANSI C online doesn't support locales
    -- by default. Force a known problematic locale to test strtod()/sprintf().
    { "Setting locale to cs_CZ (comma separator)", function ()
        os.setlocale("cs_CZ")
        json.new()
    end },
    { "Encode number under comma locale",
      json.encode, { 1.5 }, true, { '1.5' } },
    { "Decode number in array under comma locale",
      json.decode, { '[ 10, "test" ]' }, true, { { 10, "test" } } },
    { "Reverting locale to POSIX", function ()
        os.setlocale("C")
        json.new()
    end },
}

print(string.format("Testing Lua CJSON version %s\n", json.version))

util.run_test_group(all_tests)

json.encode_invalid_numbers(true)
json.decode_invalid_numbers(true)
json.encode_max_depth(20)
for i = 1, #arg do
    util.run_test("Decode cycle " .. arg[i], test_decode_cycle, { arg[i] },
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
