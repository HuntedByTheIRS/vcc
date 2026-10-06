/* 1092: cabsf-and-cabsl-are-the-complex-magnitude-twins
 *
 * ISO/IEC 9899:1999 7.3.8.1: the cabs functions compute the complex
 * absolute value of z.
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
    float complex zf = 3.0f + 4.0f * I;
    double complex z = 3.0 + 4.0 * I;
    long double complex zl = 3.0L + 4.0L * I;
    CHECK(cabsf(zf) == 5.0f);
    CHECK(cabs(z) == 5.0);
    CHECK(cabsl(zl) == 5.0L);
    return 0;
}
