/* Lua JSON routines
 */

/* Caveats:
 * - Assumes strings are valid UTF-8 and mostly treats them as opaque
 *   binary data. Will not throw an exception on bad data.
 * - Will decode \uXXXX escapes, but leaves high codepoints as UTF-8
 *   when encoding.
 * - JSON "null" values are represented as lightuserdata. Compare with
 *   json.null.
 * - Parsing comments is not supported. According to json.org, this isn't
 *   part of the spec.
 * - Parser accepts number formats beyond the JSON spec.
 *
 * Note: lua_json_decode() probably spends significant time rehashing
 *       tables since it is difficult to know their size ahead of time.
 *       Earlier JSON libaries didn't have this problem but the intermediate
 *       storage (and their implementations) were much slower anyway..
 */

/* FIXME:
 * - Option to encode non-printable characters? Only \" \\ are required
 */

#include <assert.h>
#include <string.h>
#include <math.h>
#include <lua.h>
#include <lauxlib.h>

#include "strbuf.h"


#define CJSON_CONFIG_KEY "cjson_configdata"
#define DEFAULT_SPARSE_RATIO 2
#define DEFAULT_MAX_DEPTH 20

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
    json_token_type_t ch2token[256];
    char ch2escape[256];
    int sparse_ratio;
    int max_depth;
    int current_depth;
} json_config_t;

typedef struct {  
    const char *data;
    int index;
    strbuf_t *tmp;    /* Temporary storage for strings */
    json_config_t *cfg;
} json_parse_t;

typedef struct {
    json_token_type_t type;
    int index;
    union {
        char *string;
        double number;
        int boolean;
    } value;
    int string_len;
} json_token_t;

/* ===== CONFIGURATION ===== */

static json_config_t *json_fetch_config(lua_State *l)
{
    json_config_t *cfg;

    lua_getfield(l, LUA_REGISTRYINDEX, CJSON_CONFIG_KEY);
    cfg = lua_touserdata(l, -1);
    if (!cfg)
        luaL_error(l, "BUG: Unable to fetch cjson configuration");

    lua_pop(l, 1);

    return cfg;
}

static int json_sparse_ratio(lua_State *l)
{
    json_config_t *cfg;
    int sparse_ratio;
    int args;

    args = lua_gettop(l);
    luaL_argcheck(l, args <= 1, 2, "found too many arguments");

    cfg = json_fetch_config(l);

    if (args == 1) {
        sparse_ratio = luaL_checkinteger(l, 1);
        luaL_argcheck(l, sparse_ratio >= 0, 1,
                      "expected zero or positive integer");
        cfg->sparse_ratio = sparse_ratio;
    }

    lua_pushinteger(l, cfg->sparse_ratio);

    return 1;
}

static int json_max_depth(lua_State *l)
{
    json_config_t *cfg;
    int max_depth;
    int args;

    args = lua_gettop(l);
    luaL_argcheck(l, args <= 1, 2, "found too many arguments");

    cfg = json_fetch_config(l);

    if (args == 1) {
        max_depth = luaL_checkinteger(l, 1);
        luaL_argcheck(l, max_depth > 0, 1, "expected positive integer");
        cfg->max_depth = max_depth;
    }

    lua_pushinteger(l, cfg->max_depth);

    return 1;
}

static void json_create_config(lua_State *l)
{
    json_config_t *cfg;
    int i;

    cfg = lua_newuserdata(l, sizeof(*cfg));

    /* Tag all characters as an error */
    for (i = 0; i < 256; i++)
        cfg->ch2token[i] = T_ERROR;

    /* Set tokens that require no further processing */
    cfg->ch2token['{'] = T_OBJ_BEGIN;
    cfg->ch2token['}'] = T_OBJ_END;
    cfg->ch2token['['] = T_ARR_BEGIN;
    cfg->ch2token[']'] = T_ARR_END;
    cfg->ch2token[','] = T_COMMA;
    cfg->ch2token[':'] = T_COLON;
    cfg->ch2token['\0'] = T_END;
    cfg->ch2token[' '] = T_WHITESPACE;
    cfg->ch2token['\t'] = T_WHITESPACE;
    cfg->ch2token['\n'] = T_WHITESPACE;
    cfg->ch2token['\r'] = T_WHITESPACE;

    /* Update characters that require further processing */
    cfg->ch2token['n'] = T_UNKNOWN;
    cfg->ch2token['t'] = T_UNKNOWN;
    cfg->ch2token['f'] = T_UNKNOWN;
    cfg->ch2token['"'] = T_UNKNOWN;
    cfg->ch2token['-'] = T_UNKNOWN;
    for (i = 0; i < 10; i++)
        cfg->ch2token['0' + i] = T_UNKNOWN;

    for (i = 0; i < 256; i++)
        cfg->ch2escape[i] = 0;  /* String error */

    cfg->ch2escape['"'] = '"';
    cfg->ch2escape['\\'] = '\\';
    cfg->ch2escape['/'] = '/';
    cfg->ch2escape['b'] = '\b';
    cfg->ch2escape['t'] = '\t';
    cfg->ch2escape['n'] = '\n';
    cfg->ch2escape['f'] = '\f';
    cfg->ch2escape['r'] = '\r';
    cfg->ch2escape['u'] = 'u';  /* This needs to be parsed as unicode */

    cfg->sparse_ratio = DEFAULT_SPARSE_RATIO;
    cfg->max_depth = DEFAULT_MAX_DEPTH;
}

/* ===== ENCODING ===== */

static void json_encode_exception(lua_State *l, strbuf_t *json, int lindex,
                                  const char *reason)
{
    strbuf_free(json);

    luaL_error(l, "Cannot serialise %s: %s",
                  lua_typename(l, lua_type(l, lindex)), reason);
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

    /* Worst case is len * 6 (all unicode escapes).
     * This buffer is reused constantly for small strings
     * If there are any excess pages, they won't be hit anyway.
     * This gains ~5% speedup. */
    strbuf_ensure_empty_length(json, len * 6);

    strbuf_append_char(json, '\"');
    for (i = 0; i < len; i++) {
        p = json_escape_char(str[i]);
        if (p)
            strbuf_append_string(json, p);
        else
            strbuf_append_char_unsafe(json, str[i]);
    }
    strbuf_append_char(json, '\"');
}

/* Find the size of the array on the top of the Lua stack
 * -1   object (not a pure array)
 * >=0  elements in array
 */
static int lua_array_length(lua_State *l, int sparse_ratio)
{
    double k;
    int max;
    int items;

    max = 0;
    items = 0;

    lua_pushnil(l);
    /* table, startkey */
    while (lua_next(l, -2) != 0) {
        /* table, key, value */
        if (lua_isnumber(l, -2) &&
            (k = lua_tonumber(l, -2))) {
            /* Integer >= 1 ? */
            if (floor(k) == k && k >= 1) {
                if (k > max)
                    max = k;
                items++;
                lua_pop(l, 1);
                continue;
            }
        }

        /* Must not be an array (non integer key) */
        lua_pop(l, 2);
        return -1;
    }

    /* Encode very sparse arrays as objects (if enabled) */
    if (sparse_ratio > 0 && max > items * sparse_ratio)
        return -1;

    return max;
}

static void json_encode_descend(lua_State *l, json_config_t *cfg,
                                strbuf_t *json)
{
    cfg->current_depth++;

    if (cfg->current_depth > cfg->max_depth) {
        strbuf_free(json);
        luaL_error(l, "Cannot serialise, excessive nesting (%d)",
                   cfg->current_depth);
    }
}

static void json_append_data(lua_State *l, json_config_t *cfg, strbuf_t *json);

/* json_append_array args:
 * - lua_State
 * - JSON strbuf
 * - Size of passwd Lua array (top of stack) */
static void json_append_array(lua_State *l, json_config_t *cfg, strbuf_t *json,
                              int array_length)
{
    int comma, i;

    json_encode_descend(l, cfg, json);

    strbuf_append_string(json, "[ ");

    comma = 0;
    for (i = 1; i <= array_length; i++) {
        if (comma)
            strbuf_append_string(json, ", ");
        else
            comma = 1;

        lua_rawgeti(l, -1, i);
        json_append_data(l, cfg, json);
        lua_pop(l, 1);
    }

    strbuf_append_string(json, " ]");

    cfg->current_depth--;
}

static void json_append_object(lua_State *l, json_config_t *cfg,
                               strbuf_t *json)
{
    int comma, keytype;

    json_encode_descend(l, cfg, json);

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
            json_encode_exception(l, json, -2,
                                  "table key must be a number or string");
            /* never returns */
        }

        /* table, key, value */
        json_append_data(l, cfg, json);
        lua_pop(l, 1);
        /* table, key */
    }

    strbuf_append_string(json, " }");

    cfg->current_depth--;
}

/* Serialise Lua data into JSON string. */
static void json_append_data(lua_State *l, json_config_t *cfg, strbuf_t *json)
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
        len = lua_array_length(l, cfg->sparse_ratio);
        if (len > 0)
            json_append_array(l, cfg, json, len);
        else
            json_append_object(l, cfg, json);
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
        json_encode_exception(l, json, -1, "type not supported");
        /* never returns */
    }
}

static int json_encode(lua_State *l)
{
    json_config_t *cfg;
    strbuf_t buf;
    char *json;
    int len;

    luaL_argcheck(l, lua_gettop(l) == 1, 1, "expected 1 argument");

    cfg = json_fetch_config(l);
    cfg->current_depth = 0;

    strbuf_init(&buf, 0);
    json_append_data(l, cfg, &buf);
    json = strbuf_free_to_string(&buf, &len);

    lua_pushlstring(l, json, len);
    free(json);

    return 1;
}

/* ===== DECODING ===== */

static void json_process_value(lua_State *l, json_parse_t *json, json_token_t *token);

static inline int hexdigit2int(char hex)
{
    if ('0' <= hex  && hex <= '9')
        return hex - '0';

    /* Force lowercase */
    hex |= 0x20;
    if ('a' <= hex && hex <= 'f')
        return 10 + hex - 'a';

    return -1;
}

static int decode_hex4(const char *hex)
{
    int digit[4];
    int i;

    /* Convert ASCII hex digit to numeric digit
     * Note: this returns an error for invalid hex digits, including
     *       NULL */
    for (i = 0; i < 4; i++) {
        digit[i] = hexdigit2int(hex[i]);
        if (digit[i] < 0) {
            return -1;
        }
    }

    return (digit[0] << 12) +
           (digit[1] << 8) +
           (digit[2] << 4) +
            digit[3];
}

static int codepoint_to_utf8(char *utf8, int codepoint)
{
    if (codepoint <= 0x7F) {
        utf8[0] = codepoint;
        return 1;
    }
    
    if (codepoint <= 0x7FF) {
        utf8[0] = (codepoint >> 6) | 0xC0;
        utf8[1] = (codepoint & 0x3F) | 0x80;
        return 2;
    }

    if (codepoint <= 0xFFFF) {
        utf8[0] = (codepoint >> 12) | 0xE0;
        utf8[1] = ((codepoint >> 6) & 0x3F) | 0x80;
        utf8[2] = (codepoint & 0x3F) | 0x80;
        return 3;
    }

    return 0;
}


/* Called when index pointing to beginning of UCS-2 hex code: uXXXX
 * Translate to UTF-8 and append to temporary token string.
 * Must advance index to the next character to be processed.
 * Returns: 0   success
 *          -1  error
 */
static int json_append_unicode_escape(json_parse_t *json)
{
    char utf8[4];       /* 3 bytes of UTF-8 can handle UCS-2 */
    int codepoint;
    int len;

    /* Fetch UCS-2 codepoint */
    codepoint = decode_hex4(&json->data[json->index + 1]);
    if (codepoint < 0) {
        return -1;
    }

    /* Convert to UTF-8 */
    len = codepoint_to_utf8(utf8, codepoint);
    if (!len) {
        return -1;
    }

    /* Append bytes and advance counter */
    strbuf_append_mem(json->tmp, utf8, len);
    json->index += 5;

    return 0;
}

static void json_next_string_token(json_parse_t *json, json_token_t *token)
{
    char *ch2escape = json->cfg->ch2escape;
    char ch;

    /* Caller must ensure a string is next */
    assert(json->data[json->index] == '"');

    /* Skip " */
    json->index++;

    /* json->tmp is the temporary strbuf used to accumulate the
     * decoded string value. */
    json->tmp->length = 0;
    while ((ch = json->data[json->index]) != '"') {
        if (!ch) {
            /* Premature end of the string */
            token->type = T_ERROR;
            token->index = json->index;
            token->value.string = "unexpected end of string";
            return;
        }
        
        /* Handle escapes */
        if (ch == '\\') {
            /* Skip \ and fetch escape character */
            json->index++;
            ch = json->data[json->index];

            /* Translate escape code and append to tmp string */
            ch = ch2escape[(unsigned char)ch];
            if (ch == 'u') {
                if (json_append_unicode_escape(json) == 0)
                    continue;

                token->type = T_ERROR;
                token->index = json->index - 1;     /* point at '\' */
                token->value.string = "invalid unicode escape";
                return;
            }
            if (!ch) {
                /* Invalid escape code */
                token->type = T_ERROR;
                token->index = json->index - 1;
                token->value.string = "invalid escape";
                return;
            }
        }
        /* Append normal character or translated single character
         * Unicode escapes are handled above */
        strbuf_append_char(json->tmp, ch);
        json->index++;
    }
    json->index++;  /* Eat final quote (") */

    strbuf_ensure_null(json->tmp);

    token->type = T_STRING;
    token->value.string = strbuf_string(json->tmp, &token->string_len);
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
    if (startptr == endptr) {
        token->type = T_ERROR;
        token->index = json->index;
        token->value.string = "invalid number";
    } else {
        json->index += endptr - startptr;   /* Skip the processed number */
    }

    return;
}

/* Fills in the token struct.
 * T_STRING will return a pointer to the json_parse_t temporary string
 * T_ERROR will leave the json->index pointer at the error.
 */
static void json_next_token(json_parse_t *json, json_token_t *token)
{
    json_token_type_t *ch2token = json->cfg->ch2token;
    int ch;

    /* Eat whitespace. FIXME: UGLY */
    token->type = ch2token[(unsigned char)json->data[json->index]];
    while (token->type == T_WHITESPACE)
        token->type = ch2token[(unsigned char)json->data[++json->index]];

    token->index = json->index;

    /* Don't advance the pointer for an error or the end */
    if (token->type == T_ERROR) {
        token->value.string = "invalid token";
        return;
    }

    if (token->type == T_END)
        return;

    /* Found a known single character token, advance index and return */
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

    /* We can fall through here if a token starts with t/f/n but isn't
     * recognised above */
    token->type = T_ERROR;
    token->value.string = "invalid token";
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
    const char *found;

    strbuf_free(json->tmp);

    if (token->type == T_ERROR)
        found = token->value.string;
    else
        found = json_token_type_name[token->type];

    /* Note: token->index is 0 based, display starting from 1 */
    luaL_error(l, "Expected %s but found %s at character %d",
               exp, found, token->index + 1);
}

static void json_parse_object_context(lua_State *l, json_parse_t *json)
{
    json_token_t token;

    /* 3 slots required:
     * .., table, key, value */
    luaL_checkstack(l, 3, "too many nested data structures");

    lua_newtable(l);

    json_next_token(json, &token);

    /* Handle empty objects */
    if (token.type == T_OBJ_END)
        return;

    while (1) {
        if (token.type != T_STRING)
            json_throw_parse_error(l, json, "object key string", &token);

        /* Push key */
        lua_pushlstring(l, token.value.string, token.string_len);

        json_next_token(json, &token);
        if (token.type != T_COLON)
            json_throw_parse_error(l, json, "colon", &token);

        /* Fetch value */
        json_next_token(json, &token);
        json_process_value(l, json, &token);

        /* Set key = value */
        lua_rawset(l, -3);

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

    /* 2 slots required:
     * .., table, value */
    luaL_checkstack(l, 2, "too many nested data structures");

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
        lua_pushlstring(l, token->value.string, token->string_len);
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
static void lua_json_decode(lua_State *l, const char *json_text)
{
    json_parse_t json;
    json_token_t token;

    json.cfg = json_fetch_config(l);
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

static int json_decode(lua_State *l)
{
    const char *json;

    luaL_argcheck(l, lua_gettop(l) <= 1, 2, "found too many arguments");
    json = luaL_checkstring(l, 1);

    lua_json_decode(l, json);

    return 1;
}

/* ===== INITIALISATION ===== */

int luaopen_cjson(lua_State *l)
{
    luaL_Reg reg[] = {
        { "encode", json_encode },
        { "decode", json_decode },
        { "sparse_ratio", json_sparse_ratio },
        { "max_depth", json_max_depth },
        { NULL, NULL }
    };

    json_create_config(l);
    lua_setfield(l, LUA_REGISTRYINDEX, CJSON_CONFIG_KEY);

    luaL_register(l, "cjson", reg);

    /* Set cjson.null */
    lua_pushlightuserdata(l, NULL);
    lua_setfield(l, -2, "null");

    /* Return cjson table */
    return 1;
}

/* vi:ai et sw=4 ts=4:
 */
