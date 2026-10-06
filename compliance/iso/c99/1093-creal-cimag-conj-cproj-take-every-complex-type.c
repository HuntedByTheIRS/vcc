/* 1093: creal-cimag-conj-cproj-take-every-complex-type
 *
 * ISO/IEC 9899:1999 7.3.9.1: the creal functions compute the real part of
 * z.
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
    float complex zf = 1.0f + 2.0f * I;
    double complex z = 1.0 + 2.0 * I;
    long double complex zl = 1.0L + 2.0L * I;
    CHECK(crealf(zf) == 1.0f && cimagf(zf) == 2.0f);
    CHECK(creal(z) == 1.0 && cimag(z) == 2.0);
    CHECK(creall(zl) == 1.0L && cimagl(zl) == 2.0L);
    CHECK(conjf(zf) == 1.0f - 2.0f * I);
    CHECK(conj(z) == 1.0 - 2.0 * I);
    CHECK(conjl(zl) == 1.0L - 2.0L * I);
    CHECK(crealf(cprojf(zf)) == 1.0f);
    CHECK(creal(cproj(z)) == 1.0);
    CHECK(creall(cprojl(zl)) == 1.0L);
    return 0;
}
