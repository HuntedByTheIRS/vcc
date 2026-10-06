/* 1099: the-complex-analytic-functions-yield-their-double-value
 *
 * ISO/IEC 9899:1999 7.3.6.1: the ccos functions compute the complex cosine
 * of z.
 */

#include <complex.h>
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
    double complex z = 2.0 + 0.5 * I;
    CHECK(fabs(creal(ccos(z)) - cos(2.0) * cosh(0.5)) < 1e-12);
    CHECK(fabs(creal(csin(z)) - sin(2.0) * cosh(0.5)) < 1e-12);
    CHECK(fabs(creal(ccosh(z)) - cosh(2.0) * cos(0.5)) < 1e-12);
    CHECK(fabs(creal(csinh(z)) - sinh(2.0) * cos(0.5)) < 1e-12);
    CHECK(fabs(creal(cacos(cos(2.0) + 0.0 * I)) - 2.0) < 1e-12);
    return 0;
}
