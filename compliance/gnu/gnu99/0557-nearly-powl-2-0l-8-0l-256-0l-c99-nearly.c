/* 0557: CHECK(c99_nearly(powl(2.0L, 8.0L), 256.0L) && c99_nearly(fmodl(7.0L, 3.0L), 1.0L));
 *
 * monolithic.c:11267 (numerics)
 */

#include <stdio.h>
#include <complex.h>
#include <math.h>
#include <tgmath.h>

static double c99_nearly(double a, double b);

static double c99_nearly(double a, double b)
{
    double diff = fabs(a - b);
    double scale = fabs(a) > fabs(b) ? fabs(a) : fabs(b);
    return diff <= 1e-12 * (scale > 1.0 ? scale : 1.0);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_nearly(cbrt(27.0), 3.0));
    CHECK(c99_nearly(hypot(3.0, 4.0), 5.0));
    CHECK(c99_nearly(exp2(3.0), 8.0));
    CHECK(c99_nearly(log2(8.0), 3.0));
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(c99_nearly(roundf(1.5f), 2.0f));
    CHECK(c99_nearly(rint(2.4), 2.0) && c99_nearly(nearbyint(2.4), 2.0));
    CHECK(c99_nearly(fdim(5.0, 3.0), 2.0) && c99_nearly(fdim(1.0, 3.0), 0.0));
    CHECK(c99_nearly(fma(2.0, 3.0, 4.0), 10.0));
    CHECK(c99_nearly(logb(8.0), 3.0) && ilogb(8.0) == 3);
    CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
    CHECK(c99_nearly(erf(0.0), 0.0) && c99_nearly(erfc(0.0), 1.0));
    CHECK(c99_nearly(tanh(0.0), 0.0) && c99_nearly(asinh(0.0), 0.0));
    CHECK(c99_nearly(atan2(1.0, 1.0), 0.7853981633974483));
    CHECK(c99_nearly(pow(2.0, 10.0), 1024.0) && c99_nearly(sqrt(2.0) * sqrt(2.0), 2.0));
    CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
    CHECK(c99_nearly(powl(2.0L, 8.0L), 256.0L) && c99_nearly(fmodl(7.0L, 3.0L), 1.0L));
    return 0;
}
