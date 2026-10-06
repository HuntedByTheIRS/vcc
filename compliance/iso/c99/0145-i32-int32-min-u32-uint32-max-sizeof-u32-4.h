/* 0145: CHECK(i32 == INT32_MIN && u32 == UINT32_MAX && sizeof(u32) == 4);
 *
 * monolithic.c:9825 (types)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int32_t i32 = INT32_MIN;
    uint32_t u32 = UINT32_MAX;
    CHECK(i32 == INT32_MIN && u32 == UINT32_MAX && sizeof(u32) == 4);
    return 0;
}
