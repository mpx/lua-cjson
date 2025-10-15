# If Lua is installed in a non-standard location, please set the LUA_DIR
# environment variable to point to prefix for the install. Eg:
#       Unix: export LUA_DIR=/home/user/pkg
#       Windows: set LUA_DIR=c:\lua51

cmake_minimum_required(VERSION 3.14)
project(lua-cjson C)

option(USE_INTERNAL_FPCONV "Use internal strtod() / g_fmt() code for performance")
option(MULTIPLE_THREADS "Support multi-threaded apps with internal fpconv - recommended" ON)
option(USE_LUAU "Use Luau instead of standard Lua" OFF)
option(COMPILE_LUAU_TEST "Use Luau instead of standard Lua" OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
        FORCE)
endif()

#add_compile_options(-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer)

#add_compile_options(-fsanitize=address)
#add_link_options(-fsanitize=address)

if(USE_LUAU)
    add_library(cjson)
else()
    add_library(cjson MODULE)
endif()

if(USE_LUAU)
    include(FetchContent)
    FetchContent_Declare(
        luau
        GIT_REPOSITORY https://github.com/luau-lang/luau.git
        GIT_TAG        origin/master
        GIT_SHALLOW    TRUE
        GIT_PROGRESS   TRUE
        PATCH_COMMAND  git apply ${CMAKE_CURRENT_SOURCE_DIR}/luau_extern_fix.patch
        UPDATE_DISCONNECTED 1
    )
    set(LUAU_BUILD_CLI   OFF CACHE BOOL "Build CLI"                      FORCE)
    set(LUAU_BUILD_TESTS OFF CACHE BOOL "Build tests"                    FORCE)
    set(LUAU_BUILD_WEB   OFF CACHE BOOL "Build Web module"               FORCE)
    set(LUAU_WERROR      OFF CACHE BOOL "Warnings as errors"             FORCE)
    set(LUAU_STATIC_CRT  OFF CACHE BOOL "Link with the static CRT (/MT)" FORCE)
    set(LUAU_EXTERN_C    ON  CACHE BOOL "Use extern C for all APIs"      FORCE)
    FetchContent_MakeAvailable(luau)
    target_include_directories(cjson PRIVATE ${luau_SOURCE_DIR}/VM/include)
    target_compile_definitions(cjson PUBLIC  LUAU=1)
else ()
    find_package(Lua51 REQUIRED)
    target_include_directories(cjson PRIVATE ${LUA_INCLUDE_DIR})
endif()

if(NOT USE_INTERNAL_FPCONV)
    # Use libc number conversion routines (strtod(), sprintf())
    target_sources(cjson PRIVATE fpconv.c)
else()
    # Use internal number conversion routines
    target_compile_definitions(cjson PRIVATE USE_INTERNAL_FPCONV)
    target_sources(cjson PRIVATE g_fmt.c dtoa.c)

    include(TestBigEndian)
    TEST_BIG_ENDIAN(IEEE_BIG_ENDIAN)
    if(IEEE_BIG_ENDIAN)
        target_compile_definitions(cjson PRIVATE IEEE_BIG_ENDIAN)
    endif()

    if(MULTIPLE_THREADS)
        set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
        find_package(Threads REQUIRED)
        if(NOT CMAKE_USE_PTHREADS_INIT)
            message(FATAL_ERROR
                    "Pthreads not found - required by MULTIPLE_THREADS option")
        endif()
        target_compile_definitions(cjson PRIVATE MULTIPLE_THREADS)
        target_link_libraries(cjson PRIVATE Threads::Threads)
    endif()
endif()

# Handle platforms missing isinf() macro (Eg, some Solaris systems).
include(CheckSymbolExists)
CHECK_SYMBOL_EXISTS(isinf math.h HAVE_ISINF)
if(NOT HAVE_ISINF)
    target_compile_definitions(cjson PRIVATE USE_INTERNAL_ISINF)
endif()

if(USE_LUAU)
    target_link_libraries(cjson PRIVATE Luau.VM)
    target_compile_definitions(cjson PRIVATE ENABLE_CJSON_GLOBAL)
else()
    if(WIN32)
        # Win32 modules need to be linked to the Lua library.
        target_link_libraries(cjson PRIVATE ${LUA_LIBRARIES})
    endif()
endif()

if(APPLE)
    set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
        "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -undefined dynamic_lookup")
endif()

if(WIN32)
    # Windows sprintf()/strtod() handle NaN/inf differently. Not supported.
    target_compile_definitions(cjson PRIVATE DISABLE_INVALID_NUMBERS)
endif()

if(MSVC)
    target_compile_definitions(cjson PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_definitions(cjson PRIVATE inline=__inline)
    target_compile_definitions(cjson PRIVATE snprintf=_snprintf)
    target_compile_definitions(cjson PRIVATE strncasecmp=_strnicmp)
endif()

target_sources(cjson PRIVATE lua_cjson.c strbuf.c)
set_target_properties(cjson PROPERTIES PREFIX "")
if(NOT USE_LUAU)
    get_filename_component(_lua_lib_dir ${LUA_LIBRARY} PATH)
    if(WIN32)
        set(_lua_module_dir "${_lua_lib_dir}")
    else()
        set(_lua_module_dir "${_lua_lib_dir}/lua/5.1")
    endif()
    install(TARGETS cjson DESTINATION "${_lua_module_dir}")
endif()

if(COMPILE_LUAU_TEST)
    if(NOT USE_LUAU)
        message(FATAL_ERROR "Can not compile Luau test if Luau is not used")
    endif()
    enable_language(CXX)
    add_executable(luau_test tests/luau_test.cpp)
    target_link_libraries(luau_test PRIVATE 
        Luau.Compiler
        Luau.VM 
        cjson
    )
    target_include_directories(luau_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${luau_SOURCE_DIR}/VM/include
        ${luau_SOURCE_DIR}/Compiler/include
    )
endif()

# vi:ai et sw=4 ts=4:
