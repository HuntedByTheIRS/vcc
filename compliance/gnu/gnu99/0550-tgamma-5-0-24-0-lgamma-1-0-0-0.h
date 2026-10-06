/* 0550: CHECK(tgamma(5.0) == 24.0 && lgamma(1.0) == 0.0);
 *
 * monolithic.c:11260 (numerics)
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
    CHECK(tgamma(5.0) == 24.0 && lgamma(1.0) == 0.0);
    return 0;
}
