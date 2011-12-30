# If Lua is installed in a non-standard location, please set the LUA_DIR
# environment variable to point to prefix for the install. Eg:
#       Unix: export LUA_DIR=/home/user/pkg
#       Windows: set LUA_DIR=c:\lua51

project(lua_cjson C)
cmake_minimum_required(VERSION 2.6)

set(CMAKE_BUILD_TYPE Release)

find_package(Lua51 REQUIRED)
include_directories(${LUA_INCLUDE_DIR})

# Handle platforms missing isinf() macro (Eg, some Solaris systems).
include(CheckSymbolExists)
CHECK_SYMBOL_EXISTS(isinf math.h HAVE_ISINF)
if(NOT HAVE_ISINF)
    add_definitions(-DUSE_INTERNAL_ISINF)
endif()

if(APPLE)
    set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
        "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -undefined dynamic_lookup")
endif()

get_filename_component(_lua_lib_dir ${LUA_LIBRARY} PATH)
if(WIN32)
    set(_lua_module_dir "${_lua_lib_dir}")
else()
    set(_lua_module_dir "${_lua_lib_dir}/lua/5.1")
endif()

add_library(cjson MODULE lua_cjson.c strbuf.c fpconv.c)
set_target_properties(cjson PROPERTIES PREFIX "")
install(TARGETS cjson DESTINATION "${_lua_module_dir}")

# vi:ai et sw=4 ts=4:
