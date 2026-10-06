/* 1072: coshf-sinhf-tanhf-are-the-hyperbolic-twins
 *
 * ISO/IEC 9899:1999 7.12.5.4: the cosh functions compute the hyperbolic
 * cosine of x.
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
    CHECK(coshf(0.0f) == 1.0f);
    CHECK(coshl(0.0L) == 1.0L);
    CHECK(sinhf(0.0f) == 0.0f);
    CHECK(sinhl(0.0L) == 0.0L);
    CHECK(tanhf(0.0f) == 0.0f);
    CHECK(tanhl(0.0L) == 0.0L);
    return 0;
}
