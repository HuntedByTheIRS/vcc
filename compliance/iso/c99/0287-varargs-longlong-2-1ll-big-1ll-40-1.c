/* 0287: CHECK(c99_varargs_longlong(2, 1LL, big) == (1LL << 40) + 1);
 *
 * monolithic.c:10423 (functions)
 */

#include <stdio.h>
#include <stdarg.h>

static long long c99_varargs_longlong(int count, ...);

static long long c99_varargs_longlong(int count, ...)
{
    va_list ap;
    long long total = 0;

    va_start(ap, count);
    for (int i = 0; i < count; ++i) {
        total += va_arg(ap, long long);
    }
    va_end(ap);
    return total;
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
    {
    long long big = 1LL << 40;
    CHECK(c99_varargs_longlong(2, 1LL, big) == (1LL << 40) + 1);
    }
    return 0;
}
