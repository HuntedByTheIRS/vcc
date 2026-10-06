/* 1082: ceilf-floorf-truncf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.9.1: the ceil functions compute the smallest
 * integer not less than x.
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
    CHECK(ceilf(1.2f) == 2.0f);
    CHECK(ceill(1.2L) == 2.0L);
    CHECK(floorf(1.8f) == 1.0f);
    CHECK(floorl(1.8L) == 1.0L);
    CHECK(truncf(2.7f) == 2.0f);
    CHECK(truncl(2.7L) == 2.0L);
    return 0;
}
