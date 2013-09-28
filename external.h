#ifdef ENABLE_DTRACE
#include "cjson_dtrace.h"
#else
#define CJSON_ENCODE_START()
#define CJSON_ENCODE_DONE(arg0, arg1)
#endif
