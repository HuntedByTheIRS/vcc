/* 1067: acosf-and-acosl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.4.1: 7.12.4.1p2 the acos functions compute the
 * principal value of the arc cosine.
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
    CHECK(acosf(1.0f) == 0.0f);
    CHECK(acosl(1.0L) == 0.0L);
    CHECK(acos(1.0) == 0.0);
    return 0;
}
