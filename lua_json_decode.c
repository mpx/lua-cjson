#include <assert.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include "strbuf.h"

/* Caveats:
 * - NULL values do not work in objects (unssuported by Lua tables).
 *   - Could use a secial "null" table object, that is unique
 * - NULL values work in arrays (probably not at the end)
 */

/* FIXME:
 * - Ensure JSON data is UTF-8. Fail otherwise.
 *   - Alternatively, dynamically support Unicode in JSON string. Return current locale.
 * - Use lua_checkstack() to ensure there is enough stack space left to
 *   fulfill an operation. What happens if we don't, is that acceptible too?
 *   Does lua_checkstack grow the stack, or merely check if it is possible?
 * - Merge encode/decode files
 */

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

void json_init_lookup_tables()
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
    token->value.string = json->tmp->data;
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

    ch = json->data[json->index];

    /* Process characters which triggered T_UNKNOWN */
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
 * The only allowed exception is the temporary parser string
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
    } while (1);

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
        lua_pushnil(l);
        break;;
    default:
        json_throw_parse_error(l, json, "value", token);
    }
}

/* json_text must be null terminated string */
void json_parse(lua_State *l, const char *json_text)
{
    json_parse_t json;
    json_token_t token;

    json.data = json_text;
    json.index = 0;
    json.tmp = strbuf_new();
    json.tmp->scale = 256;

    json_next_token(&json, &token);
    json_process_value(l, &json, &token);

    /* Ensure there is no more input left */
    json_next_token(&json, &token);

    if (token.type != T_END)
        json_throw_parse_error(l, &json, "the end", &token);

    strbuf_free(json.tmp);
}

int lua_json_decode(lua_State *l)
{
    int i, n;

    n = lua_gettop(l);

    for (i = 1; i <= n; i++) {
        if (lua_isstring(l, i)) {
            json_parse(l, lua_tostring(l, i));
        } else {
            lua_pushnil(l);
        }
    }

    return n;   /* Number of results */
}

/* vi:ai et sw=4 ts=4:
 */
