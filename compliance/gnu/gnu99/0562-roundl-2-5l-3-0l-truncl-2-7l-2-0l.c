/* 0562: CHECK(roundl(2.5L) == 3.0L && truncl(-2.7L) == -2.0L);
 *
 * monolithic.c:11272 (numerics)
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
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
    CHECK(roundl(2.5L) == 3.0L && truncl(-2.7L) == -2.0L);
    return 0;
}
