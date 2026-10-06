/* 1081: erff-erfcf-lgammf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.8.1: the erf functions compute the error function
 * of x.
 */

#include <math.h>

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(erff(0.0f) == 0.0f);
    CHECK(erfl(0.0L) == 0.0L);
    CHECK(erfcf(0.0f) == 1.0f);
    CHECK(erfcl(0.0L) == 1.0L);
    CHECK(lgammaf(1.0f) == 0.0f);
    CHECK(lgammal(1.0L) == 0.0L);
    CHECK(tgammaf(5.0f) == 24.0f);
    CHECK(tgammal(5.0L) == 24.0L);
    return 0;
}
