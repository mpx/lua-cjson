#ifdef ENABLE_DTRACE
#include "cjson_dtrace.h"
#else
#define	LUA_CJSON_START_ENABLED() (0)
#define LUA_CJSON_START()
#define	LUA_CJSON_END_ENABLED() (0)
#define LUA_CJSON_END(arg0, arg1)
#endif
