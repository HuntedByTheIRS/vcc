/* 1098: complex-addition-subtraction-and-negation-for-every-type
 *
 * ISO/IEC 9899:1999 7.3.2p1: the additive operators have their usual
 * meaning for complex operands.
 *
 * The negation of a `long double _Complex` flips the sign of each component
 * with the same x87 negate the scalar extended type uses, which is the
 * instruction gcc 16.2.1 emits for it at -O0.
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
    float complex af = 1.0f + 2.0f * I;
    float complex bf = 3.0f + 4.0f * I;
    double complex a = 1.0 + 2.0 * I;
    double complex b = 3.0 + 4.0 * I;
    long double complex al = 1.0L + 2.0L * I;
    long double complex bl = 3.0L + 4.0L * I;
    CHECK(crealf(af + bf) == 4.0f && cimagf(af + bf) == 6.0f);
    CHECK(creal(a + b) == 4.0 && cimag(a + b) == 6.0);
    CHECK(creall(al + bl) == 4.0L && cimagl(al + bl) == 6.0L);
    CHECK(crealf(bf - af) == 2.0f && cimagf(bf - af) == 2.0f);
    CHECK(creal(b - a) == 2.0 && cimag(b - a) == 2.0);
    CHECK(creall(bl - al) == 2.0L && cimagl(bl - al) == 2.0L);
    CHECK(crealf(-af) == -1.0f && cimagf(-af) == -2.0f);
    CHECK(creall(-al) == -1.0L && cimagl(-al) == -2.0L);
    return 0;
}
