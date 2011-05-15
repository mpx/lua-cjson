#!/usr/bin/env lua

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

if not arg[1] then
    print("usage: encode.lua FILE")
    os.exit(-1)
end

print(cjson.encode(get_lua_table(arg[1])))

-- vi:ai et sw=4 ts=4:
