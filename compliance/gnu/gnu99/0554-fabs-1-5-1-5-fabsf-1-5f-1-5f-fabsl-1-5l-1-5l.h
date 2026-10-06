/* 0554: CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
 *
 * monolithic.c:11264 (numerics)
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
    CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
    return 0;
}
