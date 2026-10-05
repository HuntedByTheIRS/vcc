/* 141: CHECK(DECIMAL_DIG >= 9);
 *
 * monolithic.c:9820 (types)
 */

#include <stdio.h>
#include <float.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(DECIMAL_DIG >= 9);
    return 0;
}
