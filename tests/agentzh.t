use TestLua;

plan tests => 2 * blocks();

run_tests();

__DATA__

=== TEST 1: empty tables as objects
--- lua
local cjson = require "cjson"
print(cjson.encode({}))
print(cjson.encode({dogs = {}}))
--- out
{}
{"dogs":{}}



=== TEST 2: empty tables as arrays
--- lua
local cjson = require "cjson"
cjson.encode_empty_table_as_object(false)
print(cjson.encode({}))
print(cjson.encode({dogs = {}}))
--- out
[]
{"dogs":[]}



=== TEST 3: empty tables as objects (explicit)
--- lua
local cjson = require "cjson"
cjson.encode_empty_table_as_object(true)
print(cjson.encode({}))
print(cjson.encode({dogs = {}}))
--- out
{}
{"dogs":{}}



=== TEST 4: & in JSON
--- lua
local cjson = require "cjson"
local a="[\"a=1&b=2\"]"
local b=cjson.decode(a)
print(cjson.encode(b))
--- out
["a=1&b=2"]



=== TEST 5: default and max precision
--- lua
local math = require "math"
local cjson = require "cjson"
local double = math.pow(2, 53)
print(cjson.encode(double))
cjson.encode_number_precision(16)
print(cjson.encode(double))
print(string.format("%16.0f", cjson.decode("9007199254740992")))
--- out
9.007199254741e+15
9007199254740992
9007199254740992
