#include <stdlib.h>
#include <stdarg.h>

/* Size: Total bytes allocated to *buf
 * Length: String length, excluding optional NULL terminator.
 * Increment: Allocation increments when resizing the string buffer.
 * Dynamic: True if created via strbuf_new()
 */

typedef struct {
    char *buf;
    int size;
    int length;
    int increment;
    int dynamic;
} strbuf_t;

#ifndef STRBUF_DEFAULT_INCREMENT
#define STRBUF_DEFAULT_INCREMENT 8
#endif

/* Initialise */
extern strbuf_t *strbuf_new();
extern void strbuf_init(strbuf_t *s);
extern void strbuf_set_increment(strbuf_t *s, int increment);

/* Release */
extern void strbuf_free(strbuf_t *s);
extern char *strbuf_free_to_string(strbuf_t *s, int *len);

/* Management */
extern void strbuf_resize(strbuf_t *s, int len);
static int strbuf_empty_length(strbuf_t *s);
static int strbuf_length(strbuf_t *s);
static char *strbuf_string(strbuf_t *s, int *len);

/* Update */
extern void strbuf_append_fmt(strbuf_t *s, const char *format, ...);
extern void strbuf_append_mem(strbuf_t *s, const char *c, int len);
extern void strbuf_append_string(strbuf_t *s, const char *str);
static void strbuf_append_char(strbuf_t *s, const char c);
static void strbuf_ensure_null(strbuf_t *s);

/* Return bytes remaining in the string buffer
 * Ensure there is space for a NULL terminator. */
static inline int strbuf_empty_length(strbuf_t *s)
{
    return s->size - s->length - 1;
}

static inline int strbuf_length(strbuf_t *s)
{
    return s->length;
}

static inline void strbuf_append_char(strbuf_t *s, const char c)
{
    if (strbuf_empty_length(s) < 1)
        strbuf_resize(s, s->length + 1);

    s->buf[s->length++] = c;
}

static inline void strbuf_ensure_null(strbuf_t *s)
{
    s->buf[s->length] = 0;
}

static inline char *strbuf_string(strbuf_t *s, int *len)
{
    if (len)
        *len = s->length;

    return s->buf;
}

/* vi:ai et sw=4 ts=4:
 */
