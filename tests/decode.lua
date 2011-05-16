#!/usr/bin/env lua

-- usage: decode.lua [json_file]
--
-- Eg:
-- echo '[ "testing" ]' | ./decode.lua
-- ./decode.lua test.json

require "common"
require "cjson"

local json_text = file_load(arg[1])
local t = cjson.decode(json_text)
print(serialise_value(t))
