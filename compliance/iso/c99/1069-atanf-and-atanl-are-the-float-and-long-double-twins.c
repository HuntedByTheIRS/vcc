/* 1069: atanf-and-atanl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.4.3: the atan functions compute the principal
 * value of the arc tangent.
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
    CHECK(atanf(0.0f) == 0.0f);
    CHECK(atanl(0.0L) == 0.0L);
    CHECK(atan2f(0.0f, 1.0f) == 0.0f);
    CHECK(atan2l(0.0L, 1.0L) == 0.0L);
    return 0;
}
