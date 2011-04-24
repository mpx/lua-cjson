#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "strbuf.h"

static void die(const char *format, ...)
{
    va_list arg;

    va_start(arg, format);
    vfprintf(stderr, format, arg);
    va_end(arg);

    exit(-1);
}

void strbuf_init(strbuf_t *s, int len)
{
    int size;

    if (len <= 0)
        size = STRBUF_DEFAULT_SIZE;
    else
        size = len + 1;         /* \0 terminator */

    s->buf = NULL;
    s->size = size;
    s->length = 0;
    s->increment = STRBUF_DEFAULT_INCREMENT;
    s->dynamic = 0;
    s->reallocs = 0;
    s->debug = 0;

    s->buf = malloc(size);
    if (!s->buf)
        die("Out of memory");

    strbuf_ensure_null(s);
}

strbuf_t *strbuf_new(int len)
{
    strbuf_t *s;

    s = malloc(sizeof(strbuf_t));
    if (!s)
        die("Out of memory");

    strbuf_init(s, len);

    /* Dynamic strbuf allocation / deallocation */
    s->dynamic = 1;

    return s;
}

void strbuf_set_increment(strbuf_t *s, int increment)
{
    /* Increment > 0:  Linear buffer growth rate
     * Increment < -1: Exponential buffer growth rate */
    if (increment == 0 || increment == -1)
        die("BUG: Invalid string increment");

    s->increment = increment;
}

static inline void debug_stats(strbuf_t *s)
{
    if (s->debug) {
        fprintf(stderr, "strbuf(%lx) reallocs: %d, length: %d, size: %d\n",
                (long)s, s->reallocs, s->length, s->size);
    }
}

void strbuf_free(strbuf_t *s)
{
    debug_stats(s);

    if (s->buf)
        free(s->buf);
    if (s->dynamic)
        free(s);
}

char *strbuf_free_to_string(strbuf_t *s, int *len)
{
    char *buf;

    debug_stats(s);

    strbuf_ensure_null(s);

    buf = s->buf;
    if (len)
        *len = s->length;

    if (s->dynamic)
        free(s);

    return buf;
}

static int calculate_new_size(strbuf_t *s, int len)
{
    int reqsize, newsize;

    if (len <= 0)
        die("BUG: Invalid strbuf length requested");

    /* Ensure there is room for optional NULL termination */
    reqsize = len + 1;

    /* If the user has requested to shrink the buffer, do it exactly */
    if (s->size > reqsize)
        return reqsize;

    newsize = s->size;
    if (s->increment < 0) {
        /* Exponential sizing */
        while (newsize < reqsize)
            newsize *= -s->increment;
    } else {
        /* Linear sizing */
        newsize = ((newsize + s->increment - 1) / s->increment) * s->increment;
    }

    return newsize;
}


/* Ensure strbuf can handle a string length bytes long (ignoring NULL
 * optional termination). */
void strbuf_resize(strbuf_t *s, int len)
{
    int newsize;

    newsize = calculate_new_size(s, len);

    if (s->debug > 1) {
        fprintf(stderr, "strbuf(%lx) resize: %d => %d\n",
                (long)s, s->size, newsize);
    }

    s->size = newsize;
    s->buf = realloc(s->buf, s->size);
    if (!s->buf)
        die("Out of memory");
    s->reallocs++;
}

void strbuf_append_mem(strbuf_t *s, const char *c, int len)
{
    if (len > strbuf_empty_length(s))
        strbuf_resize(s, s->length + len);

    memcpy(s->buf + s->length, c, len);
    s->length += len;
}

void strbuf_append_string(strbuf_t *s, const char *str)
{
    int space, i;

    space = strbuf_empty_length(s);

    for (i = 0; str[i]; i++) {
        if (space < 1) {
            strbuf_resize(s, s->length + 1);
            space = strbuf_empty_length(s);
        }

        s->buf[s->length] = str[i];
        s->length++;
        space--;
    }
}

void strbuf_append_fmt(strbuf_t *s, const char *fmt, ...)
{
    va_list arg;
    int fmt_len, try;
    int empty_len;

    /* If the first attempt to append fails, resize the buffer appropriately
     * and try again */
    for (try = 0; ; try++) {
        va_start(arg, fmt);
        /* Append the new formatted string */
        /* fmt_len is the length of the string required, excluding the
         * trailing NULL */
        empty_len = strbuf_empty_length(s);
        /* Add 1 since there is also space to store the terminating NULL. */
        fmt_len = vsnprintf(s->buf + s->length, empty_len + 1, fmt, arg);
        va_end(arg);

        if (fmt_len <= empty_len)
            break;  /* SUCCESS */
        if (try > 0)
            die("BUG: length of formatted string changed");

        strbuf_resize(s, s->length + fmt_len);
    }

    s->length += fmt_len;
}

/* vi:ai et sw=4 ts=4:
 */
