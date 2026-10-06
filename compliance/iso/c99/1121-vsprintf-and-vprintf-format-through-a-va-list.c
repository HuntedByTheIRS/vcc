/* 1121: vsprintf-and-vprintf-format-through-a-va-list
 *
 * ISO/IEC 9899:1999 7.19.6.12: the vsprintf function is equivalent to
 * sprintf with the variable argument list replaced by arg.
 */

#include <stdarg.h>
#include <stdio.h>

static int into(char *buf, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsprintf(buf, fmt, ap);
    va_end(ap);
    return r;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char buf[16];
    CHECK(into(buf, "%d", 41) == 2);
    CHECK(buf[0] == '4' && buf[1] == '1');
    return 0;
}
