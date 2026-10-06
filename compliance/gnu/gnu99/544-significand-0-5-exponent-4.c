/* 544: CHECK(significand == 0.5 && exponent == 4);
 *
 * monolithic.c:11254 (numerics)
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
    int exponent = 0;
    double significand = frexp(8.0, &exponent);
    CHECK(significand == 0.5 && exponent == 4);
    return 0;
}
