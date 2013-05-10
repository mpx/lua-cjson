# Copyright (C) 2007-2011 LuaDist.
# Created by Peter Kapec
# Redistribution and use of this file is allowed according to the terms of the MIT license.
# For details see the COPYRIGHT file distributed with LuaDist.
# Please note that the package source code is licensed under its own license.

project ( lua-cjson C )
cmake_minimum_required ( VERSION 2.6 )
include ( dist.cmake )

option(USE_LUA "Use Lua (also called 'C' Lua) version 5.1 includes (default)" ON)
option(USE_LUAJIT "Use LuaJIT includes instead of 'C' Lua ones (recommended, if you're using LuaJIT, but disabled by default)")

if(USE_LUAJIT)
# Find luajit
        find_package(LuaJIT REQUIRED)
        set(USE_LUA OFF)
# / Find lua
endif()

if(USE_LUA)
# Find lua
        find_package(Lua51 REQUIRED)
# / Find lua
endif()

# lua-cjson modules
add_definitions ( -DVERSION="1.0.3" )
install_lua_module( cjson lua_cjson.c strbuf.c )


# Install Lua-CJSON Documentation
install_data( README NEWS performance.txt rfc4627.txt )

# Install Tests
install_test( tests/ )