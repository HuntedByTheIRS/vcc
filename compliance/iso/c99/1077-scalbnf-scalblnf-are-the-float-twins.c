/* 1077: scalbnf-scalblnf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.6.13: the scalbn functions compute x times
 * FLT_RADIX to the power n.
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
    CHECK(scalbnf(1.0f, 3) == 8.0f);
    CHECK(scalbnl(1.0L, 3) == 8.0L);
    CHECK(scalblnf(1.0f, 3) == 8.0f);
    CHECK(scalblnl(1.0L, 3) == 8.0L);
    return 0;
}
