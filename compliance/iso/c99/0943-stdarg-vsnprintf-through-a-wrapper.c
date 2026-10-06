/* 0943: CHECK(n == 5);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int format_into(char *dst, size_t n, const char *fmt, ...)
{
    va_list ap;
    int written;
    va_start(ap, fmt);
    written = vsnprintf(dst, n, fmt, ap);
    va_end(ap);
    return written;
}

int main(void)
{
    char buf[32];
    int n = format_into(buf, sizeof buf, "%d-%s", 42, "ok");
    CHECK(n == 5);
    CHECK(strcmp(buf, "42-ok") == 0);
    return 0;
}
