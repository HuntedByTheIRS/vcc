/* 1083: nearbyintf-rintf-roundf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.9.3: the nearbyint functions round x to an integer
 * in the current rounding direction.
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
    CHECK(nearbyintf(2.5f) == 2.0f);
    CHECK(nearbyintl(2.5L) == 2.0L);
    CHECK(rintf(2.5f) == 2.0f);
    CHECK(rintl(2.5L) == 2.0L);
    CHECK(roundf(2.5f) == 3.0f);
    CHECK(roundl(2.5L) == 3.0L);
    return 0;
}
