/* 1100: cpow-matches-the-repeated-product
 *
 * ISO/IEC 9899:1999 7.3.9.3: the cpow functions compute the complex power
 * function x raised to the power y.
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
    double complex z = 2.0 + 1.0 * I;
    double complex q = cpow(z, 2.0 + 0.0 * I);
    double complex p = z * z;
    CHECK(fabs(creal(q) - creal(p)) < 1e-12);
    CHECK(fabs(cimag(q) - cimag(p)) < 1e-12);
    return 0;
}
