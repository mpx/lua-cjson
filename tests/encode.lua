#!/usr/bin/env lua

-- usage: encode.lua [lua_file]
--
-- Eg:
-- echo '{ "testing" }' | ./encode.lua
-- ./encode.lua lua_data.lua

require "common"
require "cjson"

function get_lua_table(file)
	local func = loadstring("data = " .. file_load(file))
	if func == nil then
		error("Invalid syntax? Lua table required.")
	end

	local env = {}
	func = setfenv(func, env)
	func()

	return env.data
end

local t = get_lua_table(arg[1])
print(cjson.encode(t))

-- vi:ai et sw=4 ts=4:
