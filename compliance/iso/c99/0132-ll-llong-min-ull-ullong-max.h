/* 0132: CHECK(ll == LLONG_MIN && ull == ULLONG_MAX);
 *
 * monolithic.c:9810 (types)
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
    long long ll = LLONG_MIN;
    unsigned long long ull = ULLONG_MAX;
    CHECK(ll == LLONG_MIN && ull == ULLONG_MAX);
    return 0;
}
