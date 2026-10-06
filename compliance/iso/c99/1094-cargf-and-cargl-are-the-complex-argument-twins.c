/* 1094: cargf-and-cargl-are-the-complex-argument-twins
 *
 * ISO/IEC 9899:1999 7.3.7.1: the carg functions compute the argument of z.
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
    float complex zf = 1.0f + 0.0f * I;
    double complex z = 1.0 + 0.0 * I;
    long double complex zl = 1.0L + 0.0L * I;
    CHECK(cargf(zf) == 0.0f);
    CHECK(carg(z) == 0.0);
    CHECK(cargl(zl) == 0.0L);
    return 0;
}
