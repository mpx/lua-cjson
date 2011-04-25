/* Lua JSON routines
 */

/* Caveats:
 * - No unicode support
 * - JSON "null" values are represented as lightuserdata. Compare with
 *   json.null.
 * - Parsing comments is not support. According to json.org, this isn't
 *   part of the spec.
 */

/* FIXME:
 * - Ensure JSON data is UTF-8. Fail otherwise.
 *   - Alternatively, dynamically support Unicode in JSON string. Return current locale.
 * - Use lua_checkstack() to ensure there is enough stack space left to
 *   fulfill an operation. What happens if we don't, is that acceptible too?
 *   Does lua_checkstack grow the stack, or merely check if it is possible?
 */

/* FIXME:
 * - Option to encode non-printable characters? Only \" \\ are required
 * - Unicode?
 */

/* FIXME:
 * - Review memory allocation handling and error returns.
 *   Ensure all memory is free. Including after exceptions.
 */

#include <assert.h>
#include <string.h>
#include <math.h>

#include <pthread.h>

#include <lua.h>
#include <lauxlib.h>

#include "lua_json.h"
#include "lua_misc.h"
#include "strbuf.h"

#include "die.h"

/* ===== ENCODING ===== */

static void json_encode_exception(lua_State *l, strbuf_t *json,
                                  char *location, int lindex)
                                  
{
    strbuf_free(json);

    luaL_error(l, "Cannot serialise %s: %s", location,
               lua_typename(l, lua_type(l, lindex)));
}

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

/* json_append_string args:
 * - lua_State
 * - JSON strbuf
 * - String (Lua stack index)
 *
 * Returns nothing. Doesn't remove string from Lua stack */
static void json_append_string(lua_State *l, strbuf_t *json, int lindex)
{
    char *p;
    int i;
    const char *str;
    size_t len;

    str = lua_tolstring(l, lindex, &len);

    strbuf_append_char(json, '\"');
    for (i = 0; i < len; i++) {
        p = json_escape_char(str[i]);
        if (p)
            strbuf_append_string(json, p);
        else
            strbuf_append_char(json, str[i]);
    }
    strbuf_append_char(json, '\"');
}

/* Find the size of the array on the top of the Lua stack
 * -1   object (not a pure array)
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

static void json_append_data(lua_State *l, strbuf_t *json);

/* json_append_array args:
 * - lua_State
 * - JSON strbuf
 * - Size of passwd Lua array (top of stack) */
static void json_append_array(lua_State *l, strbuf_t *json, int array_length)
{
    int comma, i;

    strbuf_append_string(json, "[ ");

    comma = 0;
    for (i = 1; i <= array_length; i++) {
        if (comma)
            strbuf_append_string(json, ", ");
        else
            comma = 1;

        lua_rawgeti(l, -1, i);
        json_append_data(l, json);
        lua_pop(l, 1);
    }

    strbuf_append_string(json, " ]");
}

static void json_append_object(lua_State *l, strbuf_t *json)
{
    int comma, keytype;

    /* Object */
    strbuf_append_string(json, "{ ");

    lua_pushnil(l);
    /* table, startkey */
    comma = 0;
    while (lua_next(l, -2) != 0) {
        if (comma)
            strbuf_append_string(json, ", ");
        else
            comma = 1;

        /* table, key, value */
        keytype = lua_type(l, -2);
        if (keytype == LUA_TNUMBER) {
            strbuf_append_fmt(json, "\"" LUA_NUMBER_FMT "\": ",
                                    lua_tonumber(l, -2));
        } else if (keytype == LUA_TSTRING) {
            json_append_string(l, json, -2);
            strbuf_append_string(json, ": ");
        } else {
            json_encode_exception(l, json, "table key", -2);
            /* never returns */
        }

        /* table, key, value */
        json_append_data(l, json);
        lua_pop(l, 1);
        /* table, key */
    }

    strbuf_append_string(json, " }");
}

/* Serialise Lua data into JSON string. */
static void json_append_data(lua_State *l, strbuf_t *json)
{
    int len;

    switch (lua_type(l, -1)) {
    case LUA_TSTRING:
        json_append_string(l, json, -1);
        break;
    case LUA_TNUMBER:
        strbuf_append_fmt(json, "%lf", lua_tonumber(l, -1));
        break;
    case LUA_TBOOLEAN:
        if (lua_toboolean(l, -1))
            strbuf_append_string(json, "true");
        else
            strbuf_append_string(json, "false");
        break;
    case LUA_TTABLE:
        len = lua_array_length(l);
        if (len >= 0)
            json_append_array(l, json, len);
        else
            json_append_object(l, json);
        break;
    case LUA_TNIL:
        strbuf_append_string(json, "null");
        break;
    case LUA_TLIGHTUSERDATA:
        if (lua_touserdata(l, -1) == NULL) {
            strbuf_append_string(json, "null");
            break;
        }
    default:
        /* Remaining types (LUA_TFUNCTION, LUA_TUSERDATA, LUA_TTHREAD,
         * and LUA_TLIGHTUSERDATA) cannot be serialised */
        json_encode_exception(l, json, "value", -1);
        /* never returns */
    }
}

/* lua_json_encode can throw an exception */
char *lua_json_encode(lua_State *l, int *len)
{
    strbuf_t buf;
    char *json;

    strbuf_init(&buf, 0);
    json_append_data(l, &buf);
    json = strbuf_free_to_string(&buf, len);

    return json;
}

/* lua_c_json_encode(object) must be called via lua_pcall().
 * It can be used to catch any encoder exceptions */
int lua_c_json_encode(lua_State *l)
{
    char *json;
    int len;

    lua_verify_arg_count(l, 1);

    json = lua_json_encode(l, &len);

    lua_pushlightuserdata(l, json);
    lua_pushnumber(l, len);

    return 2;
}

int lua_api_json_encode(lua_State *l)
{
    char *json;
    int len;

    json = lua_json_encode(l, &len);
    lua_pushlstring(l, json, len);
    free(json);

    return 1;
}

/* ===== DECODING ===== */

typedef struct {  
    const char *data;
    int index;
    strbuf_t *tmp;    /* Temporary storage for strings */
} json_parse_t;

typedef enum {
    T_OBJ_BEGIN,
    T_OBJ_END,
    T_ARR_BEGIN,
    T_ARR_END,
    T_STRING,
    T_NUMBER,
    T_BOOLEAN,
    T_NULL,
    T_COLON,
    T_COMMA,
    T_END,
    T_WHITESPACE,
    T_ERROR,
    T_UNKNOWN
} json_token_type_t;

static const char *json_token_type_name[] = {
    "T_OBJ_BEGIN",
    "T_OBJ_END",
    "T_ARR_BEGIN",
    "T_ARR_END",
    "T_STRING",
    "T_NUMBER",
    "T_BOOLEAN",
    "T_NULL",
    "T_COLON",
    "T_COMMA",
    "T_END",
    "T_WHITESPACE",
    "T_ERROR",
    "T_UNKNOWN",
    NULL
};

typedef struct {
    json_token_type_t type;
    int index;
    union {
        char *string;
        double number;
        int boolean;
    } value;
    int length; /* FIXME: Merge into union? Won't save memory, but more logical */
} json_token_t;

static void json_process_value(lua_State *l, json_parse_t *json, json_token_t *token);

static json_token_type_t json_ch2token[256];
static char json_ch2escape[256];

static void json_global_init()
{
    int i;

    /* Tag all characters as an error */
    for (i = 0; i < 256; i++)
        json_ch2token[i] = T_ERROR;

    /* Set tokens that require no further processing */
    json_ch2token['{'] = T_OBJ_BEGIN;
    json_ch2token['}'] = T_OBJ_END;
    json_ch2token['['] = T_ARR_BEGIN;
    json_ch2token[']'] = T_ARR_END;
    json_ch2token[','] = T_COMMA;
    json_ch2token[':'] = T_COLON;
    json_ch2token['\0'] = T_END;
    json_ch2token[' '] = T_WHITESPACE;
    json_ch2token['\t'] = T_WHITESPACE;
    json_ch2token['\n'] = T_WHITESPACE;
    json_ch2token['\r'] = T_WHITESPACE;

    /* Update characters that require further processing */
    json_ch2token['n'] = T_UNKNOWN;
    json_ch2token['t'] = T_UNKNOWN;
    json_ch2token['f'] = T_UNKNOWN;
    json_ch2token['"'] = T_UNKNOWN;
    json_ch2token['-'] = T_UNKNOWN;
    for (i = 0; i < 10; i++)
        json_ch2token['0' + i] = T_UNKNOWN;

    for (i = 0; i < 256; i++)
        json_ch2escape[i] = 0;  /* String error */

    json_ch2escape['"'] = '"';
    json_ch2escape['\\'] = '\\';
    json_ch2escape['/'] = '/';
    json_ch2escape['b'] = '\b';
    json_ch2escape['t'] = '\t';
    json_ch2escape['n'] = '\n';
    json_ch2escape['f'] = '\f';
    json_ch2escape['r'] = '\r';
    json_ch2escape['u'] = 'u';  /* This needs to be parsed as unicode */
}

static void json_next_string_token(json_parse_t *json, json_token_t *token)
{
    char ch;

    /* Caller must ensure a string is next */
    assert(json->data[json->index] == '"');

    /* Gobble string. FIXME, ugly */

    json->tmp->length = 0;
    while ((ch = json->data[++json->index]) != '"') {
        /* Handle escapes */
        if (ch == '\\') {
            /* Translate escape code */
            ch = json_ch2escape[(unsigned char)json->data[++json->index]];
            if (!ch) {
                /* Invalid escape code */
                token->type = T_ERROR;
                return;
            }
            if (ch == 'u') {
                /* Process unicode */
                /* FIXME: cleanup memory handling. Implement iconv(3)
                 * conversion from UCS-2 -> UTF-8
                 */
                if (!memcmp(&json->data[json->index], "u0000", 5)) {
                    /* Handle NULL */
                    ch = 0;
                    json->index += 4;
                } else {
                    /* Remaining codepoints unhandled */
                    token->type = T_ERROR;
                    return;
                }
            }
        }
        strbuf_append_char(json->tmp, ch);
    }
    json->index++;  /* Eat final quote (") */

    strbuf_ensure_null(json->tmp);

    token->type = T_STRING;
    token->value.string = strbuf_string(json->tmp, NULL);
    token->length = json->tmp->length;
}

static void json_next_number_token(json_parse_t *json, json_token_t *token)
{
    const char *startptr;
    char *endptr;

    /* FIXME:
     * Verify that the number takes the following form:
     * -?(0|[1-9]|[1-9][0-9]+)(.[0-9]+)?([eE][-+]?[0-9]+)?
     * strtod() below allows other forms (Hex, infinity, NaN,..) */
    /* i = json->index;
    if (json->data[i] == '-')
        i++;
    j = i;
    while ('0' <= json->data[i] && json->data[i] <= '9')
        i++;
    if (i == j)
        return T_ERROR; */

    token->type = T_NUMBER;
    startptr = &json->data[json->index];
    token->value.number = strtod(&json->data[json->index], &endptr);
    if (startptr == endptr)
        token->type = T_ERROR;
    else
        json->index += endptr - startptr;   /* Skip the processed number */

    return;
}

/* Fills in the token struct.
 * T_STRING will return a pointer to the json_parse_t temporary string
 * T_ERROR will leave the json->index pointer at the error.
 */
static void json_next_token(json_parse_t *json, json_token_t *token)
{
    int ch;

    /* Eat whitespace. FIXME: UGLY */
    token->type = json_ch2token[(unsigned char)json->data[json->index]];
    while (token->type == T_WHITESPACE)
        token->type = json_ch2token[(unsigned char)json->data[++json->index]];

    token->index = json->index;

    /* Don't advance the pointer for an error or the end */
    if (token->type == T_ERROR || token->type == T_END)
        return;

    /* Found a known token, advance index and return */
    if (token->type != T_UNKNOWN) {
        json->index++;
        return;
    }

    /* Process characters which triggered T_UNKNOWN */
    ch = json->data[json->index];

    if (ch == '"') {
        json_next_string_token(json, token);
        return;
    } else if (ch == '-' || ('0' <= ch && ch <= '9')) {
        json_next_number_token(json, token);
        return;
    } else if (!strncmp(&json->data[json->index], "true", 4)) {
        token->type = T_BOOLEAN;
        token->value.boolean = 1;
        json->index += 4;
        return;
    } else if (!strncmp(&json->data[json->index], "false", 5)) {
        token->type = T_BOOLEAN;
        token->value.boolean = 0;
        json->index += 5;
        return;
    } else if (!strncmp(&json->data[json->index], "null", 4)) {
        token->type = T_NULL;
        json->index += 4;
        return;
    }

    token->type = T_ERROR;
}

/* This function does not return.
 * DO NOT CALL WITH DYNAMIC MEMORY ALLOCATED.
 * The only supported exception is the temporary parser string
 * json->tmp struct.
 * json and token should exist on the stack somewhere.
 * luaL_error() will long_jmp and release the stack */
static void json_throw_parse_error(lua_State *l, json_parse_t *json,
                                   const char *exp, json_token_t *token)
{
    strbuf_free(json->tmp);
    luaL_error(l, "Expected %s but found type <%s> at character %d",
               exp, json_token_type_name[token->type], token->index);
}

static void json_parse_object_context(lua_State *l, json_parse_t *json)
{
    json_token_t token;

    lua_newtable(l);

    json_next_token(json, &token);

    /* Handle empty objects */
    if (token.type == T_OBJ_END)
        return;

    while (1) {
        if (token.type != T_STRING)
            json_throw_parse_error(l, json, "object key", &token);

        lua_pushlstring(l, token.value.string, token.length);     /* Push key */

        json_next_token(json, &token);
        if (token.type != T_COLON)
            json_throw_parse_error(l, json, "colon", &token);

        json_next_token(json, &token);
        json_process_value(l, json, &token);
        lua_rawset(l, -3);            /* Set key = value */

        json_next_token(json, &token);

        if (token.type == T_OBJ_END)
            return;

        if (token.type != T_COMMA)
            json_throw_parse_error(l, json, "comma or object end", &token);

        json_next_token(json, &token);
    } 
}

/* Handle the array context */
static void json_parse_array_context(lua_State *l, json_parse_t *json)
{
    json_token_t token;
    int i;

    lua_newtable(l);

    json_next_token(json, &token);

    /* Handle empty arrays */
    if (token.type == T_ARR_END)
        return;

    i = 1;
    while (1) {
        json_process_value(l, json, &token);
        lua_rawseti(l, -2, i);            /* arr[i] = value */

        json_next_token(json, &token);

        if (token.type == T_ARR_END)
            return;

        if (token.type != T_COMMA)
            json_throw_parse_error(l, json, "comma or array end", &token);

        json_next_token(json, &token);
        i++;
    }
}

/* Handle the "value" context */
static void json_process_value(lua_State *l, json_parse_t *json, json_token_t *token) 
{
    switch (token->type) {
    case T_STRING:
        lua_pushlstring(l, token->value.string, token->length);
        break;;
    case T_NUMBER:
        lua_pushnumber(l, token->value.number);
        break;;
    case T_BOOLEAN:
        lua_pushboolean(l, token->value.boolean);
        break;;
    case T_OBJ_BEGIN:
        json_parse_object_context(l, json);
        break;;
    case T_ARR_BEGIN:
        json_parse_array_context(l, json);
        break;;
    case T_NULL:
        /* In Lua, setting "t[k] = nil" will delete k from the table.
         * Hence a NULL pointer lightuserdata object is used instead */
        lua_pushlightuserdata(l, NULL);
        break;;
    default:
        json_throw_parse_error(l, json, "value", token);
    }
}

/* json_text must be null terminated string */
void lua_json_decode(lua_State *l, const char *json_text)
{
    json_parse_t json;
    json_token_t token;

    json.data = json_text;
    json.index = 0;
    json.tmp = strbuf_new(0);

    json_next_token(&json, &token);
    json_process_value(l, &json, &token);

    /* Ensure there is no more input left */
    json_next_token(&json, &token);

    if (token.type != T_END)
        json_throw_parse_error(l, &json, "the end", &token);

    strbuf_free(json.tmp);
}

/* lua_c_json_decode(string) must be called from C with lua_pcall() */
int lua_c_json_decode(lua_State *l)
{
    const char *json;

    lua_verify_arg_count(l, 1);
    luaL_argcheck(l, lua_islightuserdata(l, 1), 1,
                  "missing lightuserdata");

    json = lua_touserdata(l, 1);
    lua_pop(l, 1);

    lua_json_decode(l, json);

    return 1;
}

static int lua_api_json_decode(lua_State *l)
{
    const char *json;

    lua_verify_arg_count(l, 1);
    json = luaL_checkstring(l, 1);

    lua_json_decode(l, json);

    lua_remove(l, 1);
    
    return 1;
}

/* ===== INITIALISATION ===== */

static pthread_once_t json_global_init_once = PTHREAD_ONCE_INIT;

void lua_json_init(lua_State *l)
{
    luaL_Reg reg[] = {
        { "encode", lua_api_json_encode },
        { "decode", lua_api_json_decode },
        { NULL, NULL }
    };

    luaL_register(l, "json", reg);

    /* Set json.null, and pop "json" table from the stack */
    lua_pushlightuserdata(l, NULL);
    lua_setfield(l, -2, "null");
    lua_pop(l, 1);

    SYS_NOFAIL(pthread_once(&json_global_init_once, json_global_init));
}

/* vi:ai et sw=4 ts=4:
 */
