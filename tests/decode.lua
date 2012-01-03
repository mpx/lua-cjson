#!/usr/bin/env lua

-- usage: decode.lua [json_file]
--
-- Eg:
-- echo '[ "testing" ]' | ./decode.lua
-- ./decode.lua test.json

local json = require "cjson"
local misc = require "cjson-misc"

local json_text = misc.file_load(arg[1])
local t = json.decode(json_text)
print(misc.serialise_value(t))
