/* 0946: CHECK(read == 2);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdarg.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int scan_from_string(const char *text, const char *fmt, ...)
{
    va_list ap;
    int read;
    va_start(ap, fmt);
    read = vsscanf(text, fmt, ap);
    va_end(ap);
    return read;
}

int main(void)
{
    int a = 0;
    int b = 0;
    int read = scan_from_string("5 6", "%d %d", &a, &b);
    CHECK(read == 2);
    CHECK(a == 5 && b == 6);
    return 0;
}
