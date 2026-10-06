/* 0518: CHECK(fpclassify(DBL_MIN / 4.0) == FP_SUBNORMAL || fpclassify(DBL_MIN / 4.0) == FP_ZERO);
 *
 * monolithic.c:11223 (numerics)
 */

#include <stdio.h>
#include <float.h>
#include <math.h>
#include <tgmath.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    volatile double zero = 0.0;
    volatile double one = 1.0;
    volatile double negative = -1.0;
    double inf = one / zero;
    double neg_inf = negative / zero;
    double not_a_number = inf - inf;
    double d = 2.5;
    CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
    CHECK(isinf(inf) != 0 && isinf(neg_inf) != 0 && isinf(d) == 0);
    CHECK(isfinite(d) != 0 && isfinite(inf) == 0 && isfinite(not_a_number) == 0);
    CHECK(fpclassify(1.0) == FP_NORMAL);
    CHECK(fpclassify(0.0) == FP_ZERO);
    CHECK(fpclassify(inf) == FP_INFINITE);
    CHECK(fpclassify(not_a_number) == FP_NAN);
    CHECK(fpclassify(DBL_MIN / 4.0) == FP_SUBNORMAL ||
              fpclassify(DBL_MIN / 4.0) == FP_ZERO);
    return 0;
}
