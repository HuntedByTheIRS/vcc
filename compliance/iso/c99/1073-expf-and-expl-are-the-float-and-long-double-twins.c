/* 1073: expf-and-expl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.6.1: the exp functions compute the base-e
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
    CHECK(expf(0.0f) == 1.0f);
    CHECK(expl(0.0L) == 1.0L);
    CHECK(expf(1.0f) == (float)exp(1.0));
    return 0;
}
