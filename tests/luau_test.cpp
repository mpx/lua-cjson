#include <iostream>
#include <fstream>
#include <sstream>
#include <clocale>

// luau
#include "luacode.h"
#include "lua.h"
#include "lualib.h"

// lua-cjson
#include "luau_cjson.h"

std::string load_file_to_string(std::string& filename)
{
    std::ifstream file(filename);
    if (!file)
    {
        std::cerr << "Failed to open file: " << filename << std::endl;
        return "";
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

int exec_luau_source(lua_State* L, std::string chunkname, std::string& source)
{
    lua_CompileOptions complile_options = {};
    //// debug
    //complile_options.optimizationLevel = 0;
    //complile_options.debugLevel        = 2;
    // default
    complile_options.optimizationLevel = 1;
    complile_options.debugLevel        = 1;
    //// performance
    //complile_options.optimizationLevel = 2;
    //complile_options.debugLevel        = 0;
    
    size_t bytecodeSize = 0;
    char * bytecode     = luau_compile(source.c_str(), source.size(), &complile_options, &bytecodeSize);
    int    load_result  = luau_load(L, chunkname.c_str(), bytecode, bytecodeSize, 0);
    free(bytecode);

    // load bytecode into VM
    if (load_result != 0)
    {
        std::cerr << "Load error: " << lua_tostring(L, -1) << std::endl;
        lua_pop(L, 1); // remove error from stack
        lua_close(L);
        return 1;
    }

    /* Stack: [ ... , chunk ] */

    /* 2) push debug.traceback and remove the debug table (so stack becomes [ ... , chunk, traceback] ) */
    lua_getglobal(L, "debug");            /* pushes debug table */
    lua_getfield(L, -1, "traceback");     /* pushes debug.traceback */
    lua_remove(L, -2);                    /* remove debug table; stack: [ ... , chunk, traceback ] */

    /* 3) move traceback *below* the chunk => stack becomes [ ... , traceback, chunk ] */
    lua_insert(L, -2);

    int errfunc = lua_gettop(L) - 1;

    // execute script
    if (lua_pcall(L, 0, LUA_MULTRET, errfunc) != 0)
    {
        std::cerr << "Runtime error: " << lua_tostring(L, -1) << std::endl;
        lua_pop(L, 1); // remove error from stack
        lua_close(L);
        return 1;
    }

    lua_remove(L, errfunc);

    return 0;
}

// Luau has no file access, we create a custom function here to make the tests work
int luau_file_load(lua_State* L)
{
    int narg = lua_gettop(L);
    if (narg != 1) 
        luaL_error(L, "luau_file_load: expected 1 argument (filename : string), got %d arguments", narg);
    const char *arg1 = lua_tostring(L, 1);
    if (arg1 == NULL) 
        luaL_error(L, "luau_file_load: expected 1 argument (filename : string), argument not a string");
    FILE* f = fopen(arg1, "rb");
    if (f == NULL)
        luaL_error(L, "luau_file_load: can not open file %s", arg1);
    fseek(f, 0, SEEK_END);
    size_t f_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* f_data = (char*)malloc(f_size);
    if (f_data == NULL)
        luaL_error(L, "luau_file_load: can not allocate %llu bytes", (long long unsigned)f_size);
    size_t f_read = fread(f_data, 1, f_size, f);
    if (f_read != f_size)
        luaL_error(L, "luau_file_load: can only read %llu bytes, wanted %llu bytes", (long long unsigned)f_read, (long long unsigned)f_size);
    lua_pushlstring(L, f_data, f_size);
    free(f_data);
    fclose(f);
    return 1;
}

// Luau has no setlocale, we create a custom function here to make the tests work
int luau_setlocale(lua_State* L)
{
    int narg = lua_gettop(L);
    if (narg != 1) 
        luaL_error(L, "luau_setlocale: expected 1 argument (locale : string), got %d arguments", narg);
    const char *arg1 = lua_tostring(L, 1);
    if (arg1 == NULL) 
        luaL_error(L, "luau_setlocale: expected 1 argument (locale : string), argument not a string");
    char* ret = setlocale(LC_ALL, arg1);
	if (ret == NULL)
        luaL_error(L, "luau_setlocale: can not set locale %s", arg1);
    return 0;
}

int main(int argc, char** argv)
{
    if (argc < 2)
    {
        std::cerr << "Usage: " << argv[0] << " script.luau" << std::endl;
        return 1;
    }

    // create a new Luau VM state
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);

    // load lua-cjson library
    lua_pushcfunction(L, luaopen_cjson, "luaopen_cjson");
    lua_call(L, 0, 0);
    lua_pushcfunction(L, luaopen_cjson_safe, "luaopen_cjson_safe");
    lua_call(L, 0, 0);

    // load user defined functions
    lua_pushcfunction(L, luau_file_load, "luau_file_load");
    lua_setglobal(L, "luau_file_load");
    lua_pushcfunction(L, luau_setlocale, "luau_setlocale");
    lua_setglobal(L, "luau_setlocale");

    // lock global state
    luaL_sandbox(L);

    // load user lua code
    {
        std::string user_filename = std::string(argv[1]);
        std::string user_src      = load_file_to_string(user_filename);
        if (exec_luau_source(L, user_filename, user_src)) return 1;
    }

    lua_close(L);
    return 0;
}