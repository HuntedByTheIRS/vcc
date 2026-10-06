/* 0527: CHECK(expm1(0.0) == 0.0 && log1p(0.0) == 0.0);
 *
 * monolithic.c:11237 (numerics)
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
    CHECK(expm1(0.0) == 0.0 && log1p(0.0) == 0.0);
    return 0;
}
