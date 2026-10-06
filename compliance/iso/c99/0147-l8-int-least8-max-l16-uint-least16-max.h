/* 0147: CHECK(l8 == INT_LEAST8_MAX && l16 == UINT_LEAST16_MAX);
 *
 * monolithic.c:9827 (types)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int_least8_t l8 = INT_LEAST8_MAX;
    uint_least16_t l16 = UINT_LEAST16_MAX;
    CHECK(l8 == INT_LEAST8_MAX && l16 == UINT_LEAST16_MAX);
    return 0;
}
