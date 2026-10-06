/* 0152: CHECK(INT8_C(1) == 1 && UINT8_C(1) == 1u);
 *
 * monolithic.c:9832 (types)
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
    CHECK(INT8_C(1) == 1 && UINT8_C(1) == 1u);
    return 0;
}
