/* 1097: complex-multiplication-and-division-for-every-type
 *
 * ISO/IEC 9899:1999 7.3.3p1: the multiplicative operators have their usual
 * meaning for complex operands.
 *
 * The quotient of a `long double _Complex` is the scaled division C99's Annex
 * G.5.1 describes, which is the arithmetic libgcc's __divxc3 carries. It is
 * emitted here rather than called, because no symbol an image this compiler
 * builds can name holds the helper.
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
    float complex af = 3.0f + 4.0f * I;
    float complex gf = af / 2.0f;
    double complex a = 3.0 + 4.0 * I;
    double complex g = a / 2.0;
    long double complex al = 3.0L + 4.0L * I;
    long double complex gl = al / 2.0L;
    CHECK(crealf(af * af) == -7.0f && cimagf(af * af) == 24.0f);
    CHECK(creal(a * a) == -7.0 && cimag(a * a) == 24.0);
    CHECK(creall(al * al) == -7.0L && cimagl(al * al) == 24.0L);
    CHECK(crealf(gf) == 1.5f && cimagf(gf) == 2.0f);
    CHECK(creal(g) == 1.5 && cimag(g) == 2.0);
    CHECK(creall(gl) == 1.5L && cimagl(gl) == 2.0L);
    return 0;
}
