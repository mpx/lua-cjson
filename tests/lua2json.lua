#!/usr/bin/env lua

-- usage: lua2json.lua [lua_file]
--
-- Eg:
-- echo '{ "testing" }' | ./lua2json.lua
-- ./lua2json.lua test.lua

local json = require "cjson"
local misc = require "cjson-misc"

function get_lua_table(s)
    local env = {}
    local func

    env.json = {}
    env.json.null = json.null
    env.null = json.null
    s = "data = " .. s

    -- Use setfenv() if it exists, otherwise assume Lua 5.2 load() exists
    if _G.setfenv then
        func = loadstring(s)
        if func then
            setfenv(func, env)
        end
    else
        func = load(s, nil, nil, env)
    end

	if func == nil then
		error("Invalid syntax. Failed to parse Lua table.")
	end
	func()

    return env.data
end

local t = get_lua_table(misc.file_load(arg[1]))
print(json.encode(t))

-- vi:ai et sw=4 ts=4:
