#include <stdlib.h>
#include <stdarg.h>

typedef struct {
    char *data;
    int size;   /* Bytes allocated */
    int length; /* Current length of string, not including NULL */
    int increment;  /* Allocation Increments */
} strbuf_t;

#ifndef STRBUF_DEFAULT_INCREMENT
#define STRBUF_DEFAULT_INCREMENT 8
#endif

extern void strbuf_init(strbuf_t *s);
extern strbuf_t *strbuf_new();
extern void strbuf_free(strbuf_t *s);
extern char *strbuf_to_char(strbuf_t *s, int *len);

extern void strbuf_set_increment(strbuf_t *s, int increment);
extern void strbuf_resize(strbuf_t *s, int len);
extern void strbuf_append_fmt(strbuf_t *s, const char *format, ...);
extern void strbuf_append_mem(strbuf_t *s, const char *c, int len);
extern void strbuf_ensure_null(strbuf_t *s);

/* Return bytes remaining in the string buffer
 * Ensure there is space for a NULL.
 * Returns -1 if the string has not been allocated yet */
static inline int strbuf_emptylen(strbuf_t *s)
{
    return s->size - s->length - 1;
}

static inline int strbuf_length(strbuf_t *s)
{
    return s->length;
}

static inline void strbuf_append_char(strbuf_t *s, const char c)
{
    if (strbuf_emptylen(s) < 1)
        strbuf_resize(s, s->length + 1);

    s->data[s->length++] = c;
}

/* vi:ai et sw=4 ts=4:
 */
