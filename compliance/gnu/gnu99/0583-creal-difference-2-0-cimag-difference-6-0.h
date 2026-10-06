/* 0583: CHECK(creal(difference) == 2.0 && cimag(difference) == 6.0);
 *
 * monolithic.c:11310 (numerics)
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
    {
    double complex z = 3.0 + 4.0 * I;
    double complex w = 1.0 - 2.0 * I;
    double _Complex bare = 1.0 + 1.0 * I;
    double complex sum = z + w;
    double complex difference = z - w;
    CHECK(sizeof z == 2 * sizeof(double));
    CHECK(sizeof(bare) == sizeof(double complex));
    CHECK(creal(z) == 3.0 && cimag(z) == 4.0);
    CHECK(creal(sum) == 4.0 && cimag(sum) == 2.0);
    CHECK(creal(difference) == 2.0 && cimag(difference) == 6.0);
    }
    return 0;
}
