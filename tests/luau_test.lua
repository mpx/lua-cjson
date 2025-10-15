-- Various common routines used by the Lua CJSON package
--
-- Mark Pulford <mark@kyne.au>

-- Determine with a Lua table can be treated as an array.
-- Explicitly returns "not an array" for very sparse arrays.
-- Returns:
-- -1   Not an array
-- 0    Empty table
-- >0   Highest index in the array

-- Provide unpack for Lua 5.3+ built without LUA_COMPAT_UNPACK
local unpack = unpack
if table.unpack then unpack = table.unpack end

local function is_array(table)
    local max = 0
    local count = 0
    for k, v in pairs(table) do
        if type(k) == "number" then
            if k > max then max = k end
            count = count + 1
        else
            return -1
        end
    end
    if max > count * 2 then
        return -1
    end

    return max
end

local serialise_value

local function serialise_table(value, indent, depth)
    local spacing, spacing2, indent2
    if indent then
        spacing = "\n" .. indent
        spacing2 = spacing .. "  "
        indent2 = indent .. "  "
    else
        spacing, spacing2, indent2 = " ", " ", false
    end
    depth = depth + 1
    if depth > 50 then
        return "Cannot serialise any further: too many nested tables"
    end

    local max = is_array(value)

    local comma = false
    local fragment = { "{" .. spacing2 }
    if max > 0 then
        -- Serialise array
        for i = 1, max do
            if comma then
                table.insert(fragment, "," .. spacing2)
            end
            table.insert(fragment, serialise_value(value[i], indent2, depth))
            comma = true
        end
    elseif max < 0 then
        -- Serialise table
        for k, v in pairs(value) do
            if comma then
                table.insert(fragment, "," .. spacing2)
            end
            table.insert(fragment,
                ("[%s] = %s"):format(serialise_value(k, indent2, depth),
                                     serialise_value(v, indent2, depth)))
            comma = true
        end
    end
    table.insert(fragment, spacing .. "}")

    return table.concat(fragment)
end

function serialise_value(value, indent, depth)
    if indent == nil then indent = "" end
    if depth == nil then depth = 0 end

    if value == cjson.null then
        return "json.null"
    elseif type(value) == "string" then
        return ("%q"):format(value)
    elseif type(value) == "nil" or type(value) == "number" or
           type(value) == "boolean" then
        return tostring(value)
    elseif type(value) == "table" then
        return serialise_table(value, indent, depth)
    else
        return "\"<" .. type(value) .. ">\""
    end
end

local function compare_values(val1, val2)
    local type1 = type(val1)
    local type2 = type(val2)
    if type1 ~= type2 then
        return false
    end

    -- Check for NaN
    if type1 == "number" and val1 ~= val1 and val2 ~= val2 then
        return true
    end

    if type1 ~= "table" then
        return val1 == val2
    end

    -- check_keys stores all the keys that must be checked in val2
    local check_keys = {}
    for k, _ in pairs(val1) do
        check_keys[k] = true
    end

    for k, v in pairs(val2) do
        if not check_keys[k] then
            return false
        end

        if not compare_values(val1[k], val2[k]) then
            return false
        end

        check_keys[k] = nil
    end
    for k, _ in pairs(check_keys) do
        -- Not the same if any keys from val1 were not found in val2
        return false
    end
    return true
end

local test_count_pass = 0
local test_count_total = 0

local function run_test_summary()
    return test_count_pass, test_count_total
end

local function run_test(testname, func, input, should_work, output)

    local function to_printable_str(str, max_len)
        if #str > max_len then
            return string.sub(str, 1, max_len) .. "... (" .. #str-max_len .. " bytes omitted)"
        else
            return str
        end
    end

    local function status_line(name, status, value, max_len)
        local statusmap = { [true] = ":success", [false] = ":error" }
        if status ~= nil then
            name = name .. statusmap[status]
        end
        print(("[%s] %s"):format(name, to_printable_str(serialise_value(value, false), max_len)))
    end

    local result = { pcall(func, unpack(input)) }
    local success = table.remove(result, 1)

    local correct = false
    if success == should_work and compare_values(result, output) then
        correct = true
        test_count_pass = test_count_pass + 1
    end
    test_count_total = test_count_total + 1

    local teststatus = { [true] = "PASS", [false] = "FAIL" }
    print(("==> Test [%d] %s: %s"):format(test_count_total, testname,
                                          teststatus[correct]))

    local max_len = 120                               

    status_line("Input", nil, input, max_len)
    if not correct then
        status_line("Expected", should_work, output, max_len)
    end
    status_line("Received", success, result, max_len)
    print()

    if not correct then
        error("test failed")
    end

    return correct, result
end

local function run_test_group(tests)
    local function run_helper(name, func, input)
        if type(name) == "string" and #name > 0 then
            print("==> " .. name)
        end
        -- Not a protected call, these functions should never generate errors.
        func(unpack(input or {}))
        print()
    end

    for _, v in ipairs(tests) do
        -- Run the helper if "should_work" is missing
        if v[4] == nil then
            run_helper(unpack(v))
        else
            run_test(unpack(v))
        end
    end
end

-- Run a Lua script in a separate environment
local function run_script(script, env)
    local env = env or {}
    local func

    -- Use setfenv() if it exists, otherwise assume Lua 5.2 load() exists
    if _G.setfenv then
        func = loadstring(script)
        if func then
            setfenv(func, env)
        end
    else
        func = load(script, nil, nil, env)
    end

    if func == nil then
            error("Invalid syntax.")
    end
    func()

    return env
end

-- Export functions
local util = {
    serialise_value = serialise_value,
    file_load = luau_file_load,
    compare_values = compare_values,
    run_test_summary = run_test_summary,
    run_test = run_test,
    run_test_group = run_test_group,
    run_script = run_script
}

-- Luau CJSON tests
--
-- Mark Pulford <mark@kyne.au>
--
-- Note: The output of this script is easier to read with "less -S"

local function json_encode_output_type(value)
    local text = cjson.encode(value)
    if string.match(text, "{.*}") then
        return "object"
    elseif string.match(text, "%[.*%]") then
        return "array"
    else
        return "scalar"
    end
end

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
        local esc = ('\\u%04X'):format(code)
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

local function load_testdata()
    local data = {}

    -- Data for 8bit raw <-> escaped octets tests
    data.octets_raw = gen_raw_octets()
    data.octets_escaped = util.file_load("octets-escaped.dat")

    -- Data for \uXXXX -> UTF-8 test
    data.utf16_escaped = gen_utf16_escaped()

    -- Load matching data for utf16_escaped
    local utf8_loaded
    utf8_loaded, data.utf8_raw = pcall(util.file_load, "utf8.dat")
    if not utf8_loaded then
        data.utf8_raw = "Failed to load utf8.dat - please run genutf8.pl"
    end

    data.table_cycle = {}
    data.table_cycle[1] = data.table_cycle

    local big = {}
    for i = 1, 1100 do
        big = { { 10, false, true, cjson.null }, "string", a = big }
    end
    data.deeply_nested_data = big

    return data
end

local function test_decode_cycle(filename)
    local obj1 = cjson.decode(util.file_load(filename))
    local obj2 = cjson.decode(cjson.encode(obj1))
    return util.compare_values(obj1, obj2)
end

-- Set up data used in tests
local Inf = math.huge;
local NaN = math.huge * 0;

local testdata = load_testdata()

local cjson_tests = {
    -- Test API variables
    { "Check module name, version",
      function () return cjson._NAME, cjson._VERSION end, { },
      true, { "cjson", "2.1devel" } },

    -- Test decoding simple types
    { "Decode string",
      cjson.decode, { '"test string"' }, true, { "test string" } },
    { "Decode numbers",
      cjson.decode, { '[ 0.0, -5e3, -1, 0.3e-3, 1023.2, 0e10 ]' },
      true, { { 0.0, -5000, -1, 0.0003, 1023.2, 0 } } },
    { "Decode null",
      cjson.decode, { 'null' }, true, { cjson.null } },
    { "Decode true",
      cjson.decode, { 'true' }, true, { true } },
    { "Decode false",
      cjson.decode, { 'false' }, true, { false } },
    { "Decode object with numeric keys",
      cjson.decode, { '{ "1": "one", "3": "three" }' },
      true, { { ["1"] = "one", ["3"] = "three" } } },
    { "Decode object with string keys",
      cjson.decode, { '{ "a": "a", "b": "b" }' },
      true, { { a = "a", b = "b" } } },
    { "Decode array",
      cjson.decode, { '[ "one", null, "three" ]' },
      true, { { "one", cjson.null, "three" } } },

    -- Test decoding errors
    { "Decode UTF-16BE [throw error]",
      cjson.decode, { '\0"\0"' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-16LE [throw error]",
      cjson.decode, { '"\0"\0' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-32BE [throw error]",
      cjson.decode, { '\0\0\0"' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode UTF-32LE [throw error]",
      cjson.decode, { '"\0\0\0' },
      false, { "JSON parser does not support UTF-16 or UTF-32" } },
    { "Decode partial JSON [throw error]",
      cjson.decode, { '{ "unexpected eof": ' },
      false, { "Expected value but found T_END at character 21" } },
    { "Decode with extra comma [throw error]",
      cjson.decode, { '{ "extra data": true }, false' },
      false, { "Expected the end but found T_COMMA at character 23" } },
    { "Decode invalid escape code [throw error]",
      cjson.decode, { [[ { "bad escape \q code" } ]] },
      false, { "Expected object key string but found invalid escape code at character 16" } },
    { "Decode invalid unicode escape [throw error]",
      cjson.decode, { [[ { "bad unicode \u0f6 escape" } ]] },
      false, { "Expected object key string but found invalid unicode escape code at character 17" } },
    { "Decode invalid keyword [throw error]",
      cjson.decode, { ' [ "bad barewood", test ] ' },
      false, { "Expected value but found invalid token at character 20" } },
    { "Decode invalid number #1 [throw error]",
      cjson.decode, { '[ -+12 ]' },
      false, { "Expected value but found invalid number at character 3" } },
    { "Decode invalid number #2 [throw error]",
      cjson.decode, { '-v' },
      false, { "Expected value but found invalid number at character 1" } },
    { "Decode invalid number exponent [throw error]",
      cjson.decode, { '[ 0.4eg10 ]' },
      false, { "Expected comma or array end but found invalid token at character 6" } },

    -- Test decoding nested arrays / objects
    { "Set decode_max_depth(5)",
      cjson.decode_max_depth, { 5 }, true, { 5 } },
    { "Decode array at nested limit",
      cjson.decode, { '[[[[[ "nested" ]]]]]' },
      true, { {{{{{ "nested" }}}}} } },
    { "Decode array over nested limit [throw error]",
      cjson.decode, { '[[[[[[ "nested" ]]]]]]' },
      false, { "Found too many nested data structures (6) at character 6" } },
    { "Decode object at nested limit",
      cjson.decode, { '{"a":{"b":{"c":{"d":{"e":"nested"}}}}}' },
      true, { {a={b={c={d={e="nested"}}}}} } },
    { "Decode object over nested limit [throw error]",
      cjson.decode, { '{"a":{"b":{"c":{"d":{"e":{"f":"nested"}}}}}}' },
      false, { "Found too many nested data structures (6) at character 26" } },
    { "Set decode_max_depth(1000)",
      cjson.decode_max_depth, { 1000 }, true, { 1000 } },
    { "Decode deeply nested array [throw error]",
      cjson.decode, { string.rep("[", 1100) .. '1100' .. string.rep("]", 1100)},
      false, { "Found too many nested data structures (1001) at character 1001" } },

    -- Test encoding nested tables
    { "Set encode_max_depth(5)",
      cjson.encode_max_depth, { 5 }, true, { 5 } },
    { "Encode nested table as array at nested limit",
      cjson.encode, { {{{{{"nested"}}}}} }, true, { '[[[[["nested"]]]]]' } },
    { "Encode nested table as array after nested limit [throw error]",
      cjson.encode, { { {{{{{"nested"}}}}} } },
      false, { "Cannot serialise, excessive nesting (6)" } },
    { "Encode nested table as object at nested limit",
      cjson.encode, { {a={b={c={d={e="nested"}}}}} },
      true, { '{"a":{"b":{"c":{"d":{"e":"nested"}}}}}' } },
    { "Encode nested table as object over nested limit [throw error]",
      cjson.encode, { {a={b={c={d={e={f="nested"}}}}}} },
      false, { "Cannot serialise, excessive nesting (6)" } },
    { "Encode table with cycle [throw error]",
      cjson.encode, { testdata.table_cycle },
      false, { "Cannot serialise, excessive nesting (6)" } },
    { "Set encode_max_depth(1000)",
      cjson.encode_max_depth, { 1000 }, true, { 1000 } },
    { "Encode deeply nested data [throw error]",
      cjson.encode, { testdata.deeply_nested_data },
      false, { "Cannot serialise, excessive nesting (1001)" } },

    -- Test encoding simple types
    { "Encode null",
      cjson.encode, { cjson.null }, true, { 'null' } },
    { "Encode true",
      cjson.encode, { true }, true, { 'true' } },
    { "Encode false",
      cjson.encode, { false }, true, { 'false' } },
    { "Encode empty object",
      cjson.encode, { { } }, true, { '{}' } },
    { "Encode integer",
      cjson.encode, { 10 }, true, { '10' } },
    { "Encode string",
      cjson.encode, { "hello" }, true, { '"hello"' } },
    { "Encode Lua function [throw error]",
      cjson.encode, { function () end },
      false, { "Cannot serialise function: type not supported" } },

    -- Test decoding invalid numbers
    { "Set decode_invalid_numbers(true)",
      cjson.decode_invalid_numbers, { true }, true, { true } },
    { "Decode hexadecimal",
      cjson.decode, { '0x6.ffp1' }, true, { 13.9921875 } },
    { "Decode numbers with leading zero",
      cjson.decode, { '[ 0123, 00.33 ]' }, true, { { 123, 0.33 } } },
    { "Decode +-Inf",
      cjson.decode, { '[ +Inf, Inf, -Inf ]' }, true, { { Inf, Inf, -Inf } } },
    { "Decode +-Infinity",
      cjson.decode, { '[ +Infinity, Infinity, -Infinity ]' },
      true, { { Inf, Inf, -Inf } } },
    { "Decode +-NaN",
      cjson.decode, { '[ +NaN, NaN, -NaN ]' }, true, { { NaN, NaN, NaN } } },
    { "Decode Infrared (not infinity) [throw error]",
      cjson.decode, { 'Infrared' },
      false, { "Expected the end but found invalid token at character 4" } },
    { "Decode Noodle (not NaN) [throw error]",
      cjson.decode, { 'Noodle' },
      false, { "Expected value but found invalid token at character 1" } },
    { "Set decode_invalid_numbers(false)",
      cjson.decode_invalid_numbers, { false }, true, { false } },
    { "Decode hexadecimal [throw error]",
      cjson.decode, { '0x6' },
      false, { "Expected value but found invalid number at character 1" } },
    { "Decode numbers with leading zero [throw error]",
      cjson.decode, { '[ 0123, 00.33 ]' },
      false, { "Expected value but found invalid number at character 3" } },
    { "Decode +-Inf [throw error]",
      cjson.decode, { '[ +Inf, Inf, -Inf ]' },
      false, { "Expected value but found invalid token at character 3" } },
    { "Decode +-Infinity [throw error]",
      cjson.decode, { '[ +Infinity, Infinity, -Infinity ]' },
      false, { "Expected value but found invalid token at character 3" } },
    { "Decode +-NaN [throw error]",
      cjson.decode, { '[ +NaN, NaN, -NaN ]' },
      false, { "Expected value but found invalid token at character 3" } },
    { 'Set decode_invalid_numbers("on")',
      cjson.decode_invalid_numbers, { "on" }, true, { true } },

    -- Test encoding invalid numbers
    { "Set encode_invalid_numbers(false)",
      cjson.encode_invalid_numbers, { false }, true, { false } },
    { "Encode NaN [throw error]",
      cjson.encode, { NaN },
      false, { "Cannot serialise number: must not be NaN or Infinity" } },
    { "Encode Infinity [throw error]",
      cjson.encode, { Inf },
      false, { "Cannot serialise number: must not be NaN or Infinity" } },
    { "Set encode_invalid_numbers(\"null\")",
      cjson.encode_invalid_numbers, { "null" }, true, { "null" } },
    { "Encode NaN as null",
      cjson.encode, { NaN }, true, { "null" } },
    { "Encode Infinity as null",
      cjson.encode, { Inf }, true, { "null" } },
    { "Set encode_invalid_numbers(true)",
      cjson.encode_invalid_numbers, { true }, true, { true } },
    { "Encode NaN",
      cjson.encode, { NaN }, true, { "NaN" } },
    { "Encode +Infinity",
      cjson.encode, { Inf }, true, { "Infinity" } },
    { "Encode -Infinity",
      cjson.encode, { -Inf }, true, { "-Infinity" } },
    { 'Set encode_invalid_numbers("off")',
      cjson.encode_invalid_numbers, { "off" }, true, { false } },

    -- Test encoding tables
    { "Set encode_sparse_array(true, 2, 3)",
      cjson.encode_sparse_array, { true, 2, 3 }, true, { true, 2, 3 } },
    { "Encode sparse table as array #1",
      cjson.encode, { { [3] = "sparse test" } },
      true, { '[null,null,"sparse test"]' } },
    { "Encode sparse table as array #2",
      cjson.encode, { { [1] = "one", [4] = "sparse test" } },
      true, { '["one",null,null,"sparse test"]' } },
    { "Encode sparse array as object",
      json_encode_output_type, { { [1] = "one", [5] = "sparse test" } },
      true, { 'object' } },
    { "Encode table with numeric string key as object",
      cjson.encode, { { ["2"] = "numeric string key test" } },
      true, { '{"2":"numeric string key test"}' } },
    { "Set encode_sparse_array(false)",
      cjson.encode_sparse_array, { false }, true, { false, 2, 3 } },
    { "Encode table with incompatible key [throw error]",
      cjson.encode, { { [false] = "wrong" } },
      false, { "Cannot serialise boolean: table key must be a number or string" } },

    -- Test escaping
    { "Encode all octets (8-bit clean)",
      cjson.encode, { testdata.octets_raw }, true, { testdata.octets_escaped } },
    { "Decode all escaped octets",
      cjson.decode, { testdata.octets_escaped }, true, { testdata.octets_raw } },
    { "Decode single UTF-16 escape",
      cjson.decode, { [["\uF800"]] }, true, { "\239\160\128" } },
    { "Decode all UTF-16 escapes (including surrogate combinations)",
      cjson.decode, { testdata.utf16_escaped }, true, { testdata.utf8_raw } },
    { "Decode swapped surrogate pair [throw error]",
      cjson.decode, { [["\uDC00\uD800"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode duplicate high surrogate [throw error]",
      cjson.decode, { [["\uDB00\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode duplicate low surrogate [throw error]",
      cjson.decode, { [["\uDB00\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode missing low surrogate [throw error]",
      cjson.decode, { [["\uDB00"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },
    { "Decode invalid low surrogate [throw error]",
      cjson.decode, { [["\uDB00\uD"]] },
      false, { "Expected value but found invalid unicode escape code at character 2" } },

    -- Test locale support
    --
    -- The standard Lua interpreter is ANSI C online doesn't support locales
    -- by default. Force a known problematic locale to test strtod()/sprintf().
    { "Set locale to en_DK.utf8 (comma separator)", function ()
        luau_setlocale("en_DK.utf8")
        cjson.reset()
    end },
    { "Encode number under comma locale",
      cjson.encode, { 1.5 }, true, { '1.5' } },
    { "Decode number in array under comma locale",
      cjson.decode, { '[ 10, "test" ]' }, true, { { 10, "test" } } },
    { "Revert locale to POSIX", function ()
        luau_setlocale("C")
        cjson.reset()
    end },

    -- Test encode_keep_buffer() and enable_number_precision()
    { "Set encode_keep_buffer(false)",
      cjson.encode_keep_buffer, { false }, true, { false } },
    { "Set encode_number_precision(3)",
      cjson.encode_number_precision, { 3 }, true, { 3 } },
    { "Encode number with precision 3",
      cjson.encode, { 1/3 }, true, { "0.333" } },
    { "Set encode_number_precision(14)",
      cjson.encode_number_precision, { 14 }, true, { 14 } },
    { "Set encode_keep_buffer(true)",
      cjson.encode_keep_buffer, { true }, true, { true } },

    -- Test config API errors
    -- Function is listed as '?' due to pcall
    { "Set encode_number_precision(0) [throw error]",
      cjson.encode_number_precision, { 0 },
      false, { "invalid argument #1 to 'encode_number_precision' (expected integer between 1 and 14)" } },
    { "Set encode_number_precision(\"five\") [throw error]",
      cjson.encode_number_precision, { "five" },
      false, { "invalid argument #1 to 'encode_number_precision' (number expected, got string)" } },
    { "Set encode_keep_buffer(nil, true) [throw error]",
      cjson.encode_keep_buffer, { nil, true },
      false, { "invalid argument #2 to 'encode_keep_buffer' (found too many arguments)" } },
    { "Set encode_max_depth(\"wrong\") [throw error]",
      cjson.encode_max_depth, { "wrong" },
      false, { "invalid argument #1 to 'encode_max_depth' (number expected, got string)" } },
    { "Set decode_max_depth(0) [throw error]",
      cjson.decode_max_depth, { "0" },
      false, { "invalid argument #1 to 'decode_max_depth' (expected integer between 1 and 2147483647)" } },
    { "Set encode_invalid_numbers(-2) [throw error]",
      cjson.encode_invalid_numbers, { -2 },
      false, { "invalid argument #1 to 'encode_invalid_numbers' (invalid option '-2')" } },
    { "Set decode_invalid_numbers(true, false) [throw error]",
      cjson.decode_invalid_numbers, { true, false },
      false, { "invalid argument #2 to 'decode_invalid_numbers' (found too many arguments)" } },
    { "Set encode_sparse_array(\"not quite on\") [throw error]",
      cjson.encode_sparse_array, { "not quite on" },
      false, { "invalid argument #1 to 'encode_sparse_array' (invalid option 'not quite on')" } },

    { "Reset Lua CJSON configuration", function () cjson.reset() end },
    -- Wrap in a function to ensure the table returned by cjson.reset() is used
    { "Check encode_sparse_array()",
      function (...) return cjson.encode_sparse_array(...) end, { },
      true, { false, 2, 10 } },

    { "Encode (safe) simple value",
      cjson_safe.encode, { true },
      true, { "true" } },
    { "Encode (safe) argument validation [throw error]",
      cjson_safe.encode, { "arg1", "arg2" },
      false, { "invalid argument #1 to 'encode' (expected 1 argument)" } },
    { "Decode (safe) error generation",
      cjson_safe.decode, { "Oops" },
      true, { nil, "Expected value but found invalid token at character 1" } },
    { "Decode (safe) error generation after reset()",
      function(...) 
        cjson_safe.reset() 
        return cjson_safe.decode(...) 
      end, { "Oops" },
      true, { nil, "Expected value but found invalid token at character 1" } },
}

print(("==> Testing Lua CJSON version %s\n"):format(cjson._VERSION))

util.run_test_group(cjson_tests)

local decode_cycle_files = {
    "example1.json",
    "example2.json",
    "example3.json",
    "example4.json",
    "example5.json",
    "numbers.json",
    "rfc-example1.json",
    "rfc-example2.json",
    "types.json"
}

for _, filename in ipairs(decode_cycle_files) do
    util.run_test("Decode cycle " .. filename, test_decode_cycle, { filename },
                  true, { true })
end

local pass, total = util.run_test_summary()

if pass == total then
    print("==> Summary: all tests succeeded")
else
    print(("==> Summary: %d/%d tests failed"):format(total - pass, total))
    error("tests failed")
end

-- vi:ai et sw=4 ts=4:
