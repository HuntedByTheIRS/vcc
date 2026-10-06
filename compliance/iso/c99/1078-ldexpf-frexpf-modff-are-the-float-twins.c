/* 1078: ldexpf-frexpf-modff-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.6.3: the ldexp functions compute x times two to
 * the power exp.
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
    int e = 0;
    float fr = frexpf(8.0f, &e);
    float ip = 0.0f;
    modff(2.5f, &ip);
    CHECK(ldexpf(1.0f, 3) == 8.0f);
    CHECK(ldexpl(1.0L, 3) == 8.0L);
    CHECK(fr == 0.5f && e == 4);
    CHECK(ip == 2.0f);
    return 0;
}
