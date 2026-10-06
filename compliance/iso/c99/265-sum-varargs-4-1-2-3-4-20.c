/* 265: CHECK(c99_sum_varargs(4, 1, 2, 3, 4) == 20);
 *
 * monolithic.c:10381 (functions)
 */

#include <stdio.h>
#include <stdarg.h>

static int c99_sum_varargs(int count, ...)
{
    va_list ap, snapshot;
    int total = 0;

    va_start(ap, count);
    va_copy(snapshot, ap);
    for (int i = 0; i < count; ++i) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    for (int i = 0; i < count; ++i) {
        total += va_arg(snapshot, int);
    }
    va_end(snapshot);
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
    CHECK(c99_sum_varargs(4, 1, 2, 3, 4) == 20);
    return 0;
}
