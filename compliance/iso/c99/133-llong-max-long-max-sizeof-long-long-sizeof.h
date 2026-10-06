/* 133: CHECK(LLONG_MAX > LONG_MAX || sizeof(long long) == sizeof(long));
 *
 * monolithic.c:9811 (types)
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
    CHECK(LLONG_MAX > LONG_MAX || sizeof(long long) == sizeof(long));
    return 0;
}
