/* 1071: acoshf-asinhf-atanhf-are-the-hyperbolic-twins
 *
 * ISO/IEC 9899:1999 7.12.5.1: the acosh functions compute the nonnegative
 * area hyperbolic cosine.
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
    CHECK(acoshf(1.0f) == 0.0f);
    CHECK(acoshl(1.0L) == 0.0L);
    CHECK(asinhf(0.0f) == 0.0f);
    CHECK(asinhl(0.0L) == 0.0L);
    CHECK(atanhf(0.0f) == 0.0f);
    CHECK(atanhl(0.0L) == 0.0L);
    return 0;
}
