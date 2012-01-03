#!/usr/bin/env lua

-- usage: json2lua.lua [json_file]
--
-- Eg:
-- echo '[ "testing" ]' | ./json2lua.lua
-- ./json2lua.lua test.json

local json = require "cjson"
local misc = require "cjson-misc"

local json_text = misc.file_load(arg[1])
local t = json.decode(json_text)
print(misc.serialise_value(t))
