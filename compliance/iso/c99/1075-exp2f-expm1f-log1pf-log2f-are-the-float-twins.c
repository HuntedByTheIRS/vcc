/* 1075: exp2f-expm1f-log1pf-log2f-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.6.7: the exp2 functions compute the base-2
 * exponential of x.
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
    CHECK(exp2f(3.0f) == 8.0f);
    CHECK(exp2l(3.0L) == 8.0L);
    CHECK(expm1f(0.0f) == 0.0f);
    CHECK(expm1l(0.0L) == 0.0L);
    CHECK(log1pf(0.0f) == 0.0f);
    CHECK(log1pl(0.0L) == 0.0L);
    CHECK(log2f(8.0f) == 3.0f);
    CHECK(log2l(8.0L) == 3.0L);
    return 0;
}
