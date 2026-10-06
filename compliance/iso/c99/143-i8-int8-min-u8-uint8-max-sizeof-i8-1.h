/* 143: CHECK(i8 == INT8_MIN && u8 == UINT8_MAX && sizeof(i8) == 1);
 *
 * monolithic.c:9823 (types)
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
    int8_t i8 = INT8_MIN;
    uint8_t u8 = UINT8_MAX;
    CHECK(i8 == INT8_MIN && u8 == UINT8_MAX && sizeof(i8) == 1);
    return 0;
}
