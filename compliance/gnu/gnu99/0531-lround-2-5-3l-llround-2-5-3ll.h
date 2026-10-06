/* 0531: CHECK(lround(2.5) == 3L && llround(-2.5) == -3LL);
 *
 * monolithic.c:11241 (numerics)
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
    CHECK(lround(2.5) == 3L && llround(-2.5) == -3LL);
    return 0;
}
