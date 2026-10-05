/* 165: CHECK(INT8_MIN < 0 && INT16_MIN < 0 && INT32_MIN < 0 && INT64_MIN < 0);
 *
 * monolithic.c:9855 (types)
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
    int8_t i8 = INT8_MIN;
    uint8_t u8 = UINT8_MAX;
    int32_t i32 = INT32_MIN;
    uint32_t u32 = UINT32_MAX;
    CHECK(i8 == INT8_MIN && u8 == UINT8_MAX && sizeof(i8) == 1);
    CHECK(i32 == INT32_MIN && u32 == UINT32_MAX && sizeof(u32) == 4);
    CHECK(INT8_MIN < 0 && INT16_MIN < 0 && INT32_MIN < 0 && INT64_MIN < 0);
    return 0;
}
