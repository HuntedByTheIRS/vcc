/* 0523: CHECK(c99_nearly(cbrt(27.0), 3.0));
 *
 * monolithic.c:11233 (numerics)
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
    return 0;
}
