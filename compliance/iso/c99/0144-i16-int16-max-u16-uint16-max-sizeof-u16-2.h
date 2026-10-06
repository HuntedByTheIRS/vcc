/* 0144: CHECK(i16 == INT16_MAX && u16 == UINT16_MAX && sizeof(u16) == 2);
 *
 * monolithic.c:9824 (types)
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
    int16_t i16 = INT16_MAX;
    uint16_t u16 = UINT16_MAX;
    CHECK(i16 == INT16_MAX && u16 == UINT16_MAX && sizeof(u16) == 2);
    return 0;
}
