/* 1068: asinf-and-asinl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.4.2: the asin functions compute the principal
 * value of the arc sine.
 */

#include <math.h>

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
    CHECK(asinf(0.0f) == 0.0f);
    CHECK(asinl(0.0L) == 0.0L);
    return 0;
}
