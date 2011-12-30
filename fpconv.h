/* Lua CJSON floating point conversion routines */

/* Buffer larger than required to store the largest %.14g number */
# define FPCONV_G_FMT_BUFSIZE   32

extern void fpconv_update_locale();
extern int fpconv_g_fmt(char*, double, int);
extern double fpconv_strtod(const char*, char**);

/* vi:ai et sw=4 ts=4:
 */
