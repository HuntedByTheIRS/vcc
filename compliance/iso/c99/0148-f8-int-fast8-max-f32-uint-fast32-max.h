/* 0148: CHECK(f8 == INT_FAST8_MAX && f32 == UINT_FAST32_MAX);
 *
 * monolithic.c:9828 (types)
 */

#include <stdio.h>
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
    int_fast8_t f8 = INT_FAST8_MAX;
    uint_fast32_t f32 = UINT_FAST32_MAX;
    CHECK(f8 == INT_FAST8_MAX && f32 == UINT_FAST32_MAX);
    return 0;
}
