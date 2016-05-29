# If Lua is installed in a non-standard location, please set the LUA_DIR
# environment variable to point to prefix for the install. Eg:
#       Unix: export LUA_DIR=/home/user/pkg
#       Windows: set LUA_DIR=c:\lua51

project(lua-cjson C)
cmake_minimum_required(VERSION 2.6)

option(USE_INTERNAL_FPCONV "Use internal strtod() / g_fmt() code for performance")
option(MULTIPLE_THREADS "Support multi-threaded apps with internal fpconv - recommended" ON)
option(ENABLE_DTRACE "DTrace support" OFF)

if(ENABLE_DTRACE)
    find_program(DTRACE dtrace)
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
        FORCE)
endif()

find_package(Lua51 REQUIRED)
include_directories(${LUA_INCLUDE_DIR})

if(NOT USE_INTERNAL_FPCONV)
    # Use libc number conversion routines (strtod(), sprintf())
    set(FPCONV_SOURCES fpconv.c)
else()
    # Use internal number conversion routines
    add_definitions(-DUSE_INTERNAL_FPCONV)
    set(FPCONV_SOURCES g_fmt.c dtoa.c)

    include(TestBigEndian)
    TEST_BIG_ENDIAN(IEEE_BIG_ENDIAN)
    if(IEEE_BIG_ENDIAN)
        add_definitions(-DIEEE_BIG_ENDIAN)
    endif()

    if(MULTIPLE_THREADS)
        set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
        find_package(Threads REQUIRED)
        if(NOT CMAKE_USE_PTHREADS_INIT)
            message(FATAL_ERROR
                    "Pthreads not found - required by MULTIPLE_THREADS option")
        endif()
        add_definitions(-DMULTIPLE_THREADS)
    endif()
endif()

# Handle platforms missing isinf() macro (Eg, some Solaris systems).
include(CheckSymbolExists)
CHECK_SYMBOL_EXISTS(isinf math.h HAVE_ISINF)
if(NOT HAVE_ISINF)
    add_definitions(-DUSE_INTERNAL_ISINF)
endif()

set(_MODULE_LINK "${CMAKE_THREAD_LIBS_INIT}")
get_filename_component(_lua_lib_dir ${LUA_LIBRARY} PATH)

if(APPLE)
    set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
        "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -undefined dynamic_lookup")
endif()

if(WIN32)
    # Win32 modules need to be linked to the Lua library.
    set(_MODULE_LINK ${LUA_LIBRARY} ${_MODULE_LINK})
    set(_lua_module_dir "${_lua_lib_dir}")
    # Windows sprintf()/strtod() handle NaN/inf differently. Not supported.
    add_definitions(-DDISABLE_INVALID_NUMBERS)
else()
    set(_lua_module_dir "${_lua_lib_dir}/lua/5.1")
endif()

# Init empty cjson_obj for adding dtrace.o after generation one
set(cjson_obj)

add_library(cjson_objs OBJECT lua_cjson.c strbuf.c ${FPCONV_SOURCES})
set_target_properties(cjson_objs PROPERTIES POSITION_INDEPENDENT_CODE ON)
set(cjson_obj ${cjson_obj} $<TARGET_OBJECTS:cjson_objs>)

if(ENABLE_DTRACE AND DTRACE)
    message(STATUS "DTrace found and enabled to build with probes")
    add_definitions(-DENABLE_DTRACE)
    set(D_FILE ${PROJECT_SOURCE_DIR}/cjson_dtrace)
    execute_process(
       COMMAND ${DTRACE} -h -s ${D_FILE}.d -o ${D_FILE}.h
    )
    if(${CMAKE_SYSTEM_NAME} STREQUAL "FreeBSD")
# Dirty hack, because isn't supported see for more details:
# http://public.kitware.com/Bug/view.php?id=14447
        set(cjson_c_o ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/cjson_objs.dir/lua_cjson.c.o)
        set(dtrace_obj ${CMAKE_CURRENT_BINARY_DIR}/dtrace.o)
        add_custom_command(OUTPUT ${dtrace_obj}
            COMMAND ${DTRACE} -G -s ${D_FILE}.d -o ${dtrace_obj} ${cjson_c_o}
            DEPENDS ${cjson_c_o}
        )
        set_source_files_properties(${dtrace_obj}
            PROPERTIES
            EXTERNAL_OBJECT true
            GENERATED true
        )
        set(_MODULE_LINK ${_MODULE_LINK} elf)
        set(cjson_obj ${cjson_obj} ${dtrace_obj})
        unset(cjson_c_o)
        unset(dtrace_obj)
        unset(D_FILE)
    endif()
endif()

add_library(cjson MODULE ${cjson_obj})
set_target_properties(cjson PROPERTIES PREFIX "")
target_link_libraries(cjson ${_MODULE_LINK})

install(TARGETS cjson DESTINATION "${_lua_module_dir}")

# vi:ai et sw=4 ts=4:
