/* 1095: csqrt-of-a-negative-real-is-imaginary
 *
 * ISO/IEC 9899:1999 7.3.9.4: the csqrt functions compute the complex square
 * root of z on the interval [-inf, +0].
 */

#include <complex.h>

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
    double complex z = csqrt(-4.0 + 0.0 * I);
    float complex zf = csqrtf(-4.0f + 0.0f * I);
    long double complex zl = csqrtl(-4.0L + 0.0L * I);
    CHECK(creal(z) == 0.0 && cimag(z) == 2.0);
    CHECK(crealf(zf) == 0.0f && cimagf(zf) == 2.0f);
    CHECK(creall(zl) == 0.0L && cimagl(zl) == 2.0L);
    return 0;
}
