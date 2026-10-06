/* 1079: cbrtf-fabsf-hypotf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.7.1: the cbrt functions compute the real cube root
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
    CHECK(cbrtf(27.0f) == 3.0f);
    CHECK(cbrtl(27.0L) == 3.0L);
    CHECK(fabsf(-2.0f) == 2.0f);
    CHECK(fabsl(-2.0L) == 2.0L);
    CHECK(hypotf(3.0f, 4.0f) == 5.0f);
    CHECK(hypotl(3.0L, 4.0L) == 5.0L);
    return 0;
}
