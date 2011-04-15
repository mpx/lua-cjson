/*
 * Lua JSON routines
 *
 * CAVEATS:
 * - JSON "null" handling:
 *   - Decoding a "null" in an array will leave a "nil" placeholder in Lua, but will not show up at the end of the array.
 *   - Decoding a "null" in an object will ensure that particular key is deleted in the Lua table.
 */

#include <string.h>
#include <math.h>

#include <lua.h>
#include <lauxlib.h>
#include <json/json.h>

#include "lua_json.h"
#include "utils.h"
#include "str.h"

/* FIXME:
 * - Don't just pushnil on error and return?
 * - Review all strbuf usage for NULL termination
 */

/* JSON escape a character if required, or return NULL */
static inline char *json_escape_char(int c)
{
    switch(c) {
    case 0:
        return "\\u0000";
    case '\\':
        return "\\\\";
    case '"':
        return "\\\"";
    case '\b':
        return "\\b";
    case '\t':
        return "\\t";
    case '\n':
        return "\\n";
    case '\f':
        return "\\f";
    case '\r':
        return "\\r";
    }

    return NULL;
}

/* FIXME:
 * - Use lua_checklstring() instead of lua_tolstring() ?*
 */

/* FIXME:
 * - Option to encode non-printable characters? Only \" \\ are required
 * - Unicode?
 * - Improve performance?
 */
static void json_append_string(lua_State *l, struct str *json, int index)
{
    char *p;
    int i;
    const char *str;
    size_t len;

    str = lua_tolstring(l, index, &len);

    strbuf_append_char(json, '\"');
    for (i = 0; i < len; i++) {
        p = json_escape_char(str[i]);
        if (p)
            strbuf_append_mem(json, p, strlen(p));
        else
            strbuf_append_char(json, str[i]);
    }
    strbuf_append_char(json, '\"');
}

/* Find the size of the array on the top of the Lua stack
 * -1   object
 * >=0  elements in array
 */
static int lua_array_length(lua_State *l)
{
    double k;
    int max;

    max = 0;

    lua_pushnil(l);
    /* table, startkey */
    while (lua_next(l, -2) != 0) {
        /* table, key, value */
        if ((k = lua_tonumber(l, -2))) {
            /* Integer >= 1 ? */
            if (floor(k) == k && k >= 1) {
                if (k > max)
                    max = k;
                lua_pop(l, 1);
                continue;
            }
        }

        /* Must not be an array (non integer key) */
        lua_pop(l, 2);
        return -1;
    }

    return max;
}

static void json_append_data(lua_State *l, struct str *s);

static void json_append_array(lua_State *l, struct str *s, int size)
{
    int comma, i;

    strbuf_append_mem(s, "[ ", 2);

    comma = 0;
    for (i = 1; i <= size; i++) {
        if (comma)
            strbuf_append_mem(s, ", ", 2);
        else
            comma = 1;

        lua_rawgeti(l, -1, i);
        json_append_data(l, s);
        lua_pop(l, 1);
    }

    strbuf_append_mem(s, " ]", 2);
}

static void json_append_object(lua_State *l, struct str *s)
{
    int comma, keytype;

    /* Object */
    strbuf_append_mem(s, "{ ", 2);

    lua_pushnil(l);
    /* table, startkey */
    comma = 0;
    while (lua_next(l, -2) != 0) {
        if (comma)
            strbuf_append_mem(s, ", ", 2);
        else
            comma = 1;

        /* table, key, value */
        keytype = lua_type(l, -2);
        if (keytype == LUA_TNUMBER) {
            strbuf_append(s, "\"" LUA_NUMBER_FMT "\": ", lua_tonumber(l, -2));
        } else if (keytype == LUA_TSTRING) {
            json_append_string(l, s, -2);
            strbuf_append_mem(s, ": ", 2);
        } else {
            die("Cannot serialise table key %s", lua_typename(l, lua_type(l, -2)));
        }

        /* table, key, value */
        json_append_data(l, s);
        lua_pop(l, 1);
        /* table, key */
    }

    strbuf_append_mem(s, " }", 2);
}

/* Serialise Lua data into JSON string.
 *
 * FIXME:
 * - Error handling when cannot serialise key or value (return to script)
 */
static void json_append_data(lua_State *l, struct str *s)
{
    int len;

    switch (lua_type(l, -1)) {
    case LUA_TSTRING:
        json_append_string(l, s, -1);
        break;
    case LUA_TNUMBER:
        strbuf_append(s, "%lf", lua_tonumber(l, -1));
        break;
    case LUA_TBOOLEAN:
        if (lua_toboolean(l, -1))
            strbuf_append_mem(s, "true", 4);
        else
            strbuf_append_mem(s, "false", 5);
        break;
    case LUA_TTABLE:
        len = lua_array_length(l);
        if (len >= 0)
            json_append_array(l, s, len);
        else
            json_append_object(l, s);
        break;
    case LUA_TNIL:
        strbuf_append_mem(s, "null", 4);
        break;
    default:
        /* Remaining types (LUA_TFUNCTION, LUA_TUSERDATA, LUA_TTHREAD, and LUA_TLIGHTUSERDATA)
         * cannot be serialised */
        /* FIXME: return error */
        die("Cannot serialise %s", lua_typename(l, lua_type(l, -1)));
    }
}

char *lua_to_json(lua_State *l, int *len)
{
    struct str *s;
    char *data;

    s = strbuf_new();
    strbuf_set_increment(s, 256);
    json_append_data(l, s);
    data = strbuf_to_char(s, len);

    return data;
}

int lua_json_encode(lua_State *l)
{
    char *json;
    int len;

    json = lua_to_json(l, &len);
    lua_pushlstring(l, json, len);
    free(json);

    return 1;
}

void lua_json_init(lua_State *l)
{
    luaL_Reg reg[] = {
        { "encode", lua_json_encode },
        { "decode", lua_json_decode },
        { NULL, NULL }
    };

    /* Create "db" table.
     * Added functions as table entries
     */

    luaL_register(l, "json", reg);

    /* FIXME: Debugging */
    json_init_lookup_tables();
}

/* vi:ai et sw=4 ts=4:
 */
