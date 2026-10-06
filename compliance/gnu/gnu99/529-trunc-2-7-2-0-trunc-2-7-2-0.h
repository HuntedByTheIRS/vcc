/* 529: CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
 *
 * monolithic.c:11239 (numerics)
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
    CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
    return 0;
}
