/* 0535: CHECK(c99_nearly(fdim(5.0, 3.0), 2.0) && c99_nearly(fdim(1.0, 3.0), 0.0));
 *
 * monolithic.c:11245 (numerics)
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
    return 0;
}
