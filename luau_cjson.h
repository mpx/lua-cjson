#ifndef LUA_CJSON_H
#define LUA_CJSON_H

/* Only use this header when using Luau */
#ifdef  LUAU

#include "lua.h"

LUA_API int luaopen_cjson(lua_State *l);
LUA_API int luaopen_cjson_safe(lua_State *l);

#endif /* LUAU */
#endif /* LUA_CJSON_H */