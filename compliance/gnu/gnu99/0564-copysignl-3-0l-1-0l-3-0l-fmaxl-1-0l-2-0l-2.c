/* 0564: CHECK(copysignl(3.0L, -1.0L) == -3.0L && fmaxl(1.0L, 2.0L) == 2.0L);
 *
 * monolithic.c:11274 (numerics)
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
    CHECK(fmax(3.0, 5.0) == 5.0 && fmin(3.0, 5.0) == 3.0);
    CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
    CHECK(copysignl(3.0L, -1.0L) == -3.0L && fmaxl(1.0L, 2.0L) == 2.0L);
    return 0;
}
