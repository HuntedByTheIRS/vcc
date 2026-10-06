/* 1086: fdimf-fmaxf-fminf-fmaf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.12.1: the fdim functions return the positive
 * difference between x and y.
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
    CHECK(fdimf(3.0f, 1.0f) == 2.0f);
    CHECK(fdiml(3.0L, 1.0L) == 2.0L);
    CHECK(fmaxf(1.0f, 2.0f) == 2.0f);
    CHECK(fmaxl(1.0L, 2.0L) == 2.0L);
    CHECK(fminf(1.0f, 2.0f) == 1.0f);
    CHECK(fminl(1.0L, 2.0L) == 1.0L);
    CHECK(fmaf(2.0f, 3.0f, 1.0f) == 7.0f);
    CHECK(fmal(2.0L, 3.0L, 1.0L) == 7.0L);
    return 0;
}
