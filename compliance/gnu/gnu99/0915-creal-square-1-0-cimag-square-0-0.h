/* 0915: CHECK(creal(square) == -1.0 && cimag(square) == 0.0);
 *
 * monolithic.c:12155 (imaginary)
 * requires-define: C99_IMAGINARY
 * imaginary types are optional in C99 and neither gcc nor this
 * compiler implements them
 */

#include <stdio.h>
#include <complex.h>
#include <math.h>
#include <tgmath.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    double _Imaginary imaginary_unit = 1.0 * _Imaginary_I;
    double _Complex square = imaginary_unit * imaginary_unit;
    CHECK(creal(square) == -1.0 && cimag(square) == 0.0);
    return 0;
}
