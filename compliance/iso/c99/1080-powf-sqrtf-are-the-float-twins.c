/* 1080: powf-sqrtf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.7.4: the pow functions compute x raised to the
 * power y.
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
    CHECK(powf(2.0f, 3.0f) == 8.0f);
    CHECK(powl(2.0L, 3.0L) == 8.0L);
    CHECK(sqrtf(4.0f) == 2.0f);
    CHECK(sqrtl(4.0L) == 2.0L);
    return 0;
}
