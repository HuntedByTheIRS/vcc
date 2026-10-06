/* 270: CHECK(strcmp(buffer, "tru") == 0);
 *
 * monolithic.c:10386 (functions)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>

static int c99_format_into(char *restrict buf, size_t n,
                           const char *restrict fmt, ...)
{
    va_list ap;
    int written;

    va_start(ap, fmt);
    written = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return written;
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
    char buffer[64];
    CHECK(c99_format_into(buffer, sizeof buffer, "%d-%s-%.2f", 7, "x", 0.5) == 8);
    CHECK(strcmp(buffer, "7-x-0.50") == 0);
    CHECK(c99_format_into(buffer, 4, "%s", "truncated") == 9);
    CHECK(strcmp(buffer, "tru") == 0);
    return 0;
}
