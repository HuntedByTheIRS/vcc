/* 166: CHECK(INT_LEAST8_MIN < 0 && INT_FAST8_MIN < 0);
 *
 * monolithic.c:9856 (types)
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
    CHECK(INT_LEAST8_MIN < 0 && INT_FAST8_MIN < 0);
    return 0;
}
