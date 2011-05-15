#!/usr/bin/env lua

require "common"
require "cjson"

if not arg[1] then
	print("usage: decode.lua FILE")
	os.exit(-1)
end

print(serialise_value(cjson.decode(file_load(arg[1]))))
