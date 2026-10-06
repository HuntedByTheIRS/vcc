/* 118: CHECK(b_from_ull == 1);
 *
 * monolithic.c:9795 (types)
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    unsigned long long ull_source = 1ULL << 40;
    _Bool b_from_ull = ull_source;
    CHECK(b_from_ull == 1);
    return 0;
}
