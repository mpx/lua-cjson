#!/usr/bin/env lua

-- usage: lua2json.lua [lua_file]
--
-- Eg:
-- echo '{ "testing" }' | ./lua2json.lua
-- ./lua2json.lua test.lua

local json = require "cjson"
local misc = require "cjson-misc"

local env = {
    json = { null = json.null },
    null = json.null
}

local t = misc.run_script("data = " .. misc.file_load(arg[1]), env)
print(json.encode(t.data))

-- vi:ai et sw=4 ts=4:
