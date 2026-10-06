/* 1087: the-classification-macros-take-a-float-and-a-long-double
 *
 * ISO/IEC 9899:1999 7.12.3.1: each of the classification macros classifies
 * its argument without converting it.
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
    float f = 1.0f;
    long double l = 1.0L;
    float zero = 0.0f;
    CHECK(fpclassify(f) == FP_NORMAL && fpclassify(l) == FP_NORMAL);
    CHECK(fpclassify(zero) == FP_ZERO);
    CHECK(isfinite(f) && isfinite(l));
    CHECK(!isinf(f) && !isinf(l));
    CHECK(!isnan(f) && !isnan(l));
    CHECK(isnormal(f) && isnormal(l));
    CHECK(signbit(-f) && signbit(-l) && !signbit(f));
    return 0;
}
