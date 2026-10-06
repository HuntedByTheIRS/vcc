/* 128: CHECK(lo == LONG_MAX && ul == ULONG_MAX);
 *
 * monolithic.c:9806 (types)
 */

#include <stdio.h>
#include <limits.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    long lo = LONG_MAX;
    unsigned long ul = ULONG_MAX;
    CHECK(lo == LONG_MAX && ul == ULONG_MAX);
    return 0;
}
