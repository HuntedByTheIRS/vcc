/* 1096: cexp-of-zero-is-one-for-every-complex-type
 *
 * ISO/IEC 9899:1999 7.3.5.1: the cexp functions compute the complex base-e
 * exponential of z.
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
    float complex zf = 0.0f + 0.0f * I;
    double complex z = 0.0 + 0.0 * I;
    long double complex zl = 0.0L + 0.0L * I;
    CHECK(crealf(cexpf(zf)) == 1.0f && cimagf(cexpf(zf)) == 0.0f);
    CHECK(creal(cexp(z)) == 1.0 && cimag(cexp(z)) == 0.0);
    CHECK(creall(cexpl(zl)) == 1.0L && cimagl(cexpl(zl)) == 0.0L);
    CHECK(crealf(clogf(1.0f + 0.0f * I)) == 0.0f);
    CHECK(creal(clog(1.0 + 0.0 * I)) == 0.0);
    CHECK(creall(clogl(1.0L + 0.0L * I)) == 0.0L);
    return 0;
}
