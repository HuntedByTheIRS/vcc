/* 1070: cosf-and-cosl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.4.5: the cos functions compute the cosine of x.
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
    CHECK(cosf(0.0f) == 1.0f);
    CHECK(cosl(0.0L) == 1.0L);
    CHECK(sinf(0.0f) == 0.0f);
    CHECK(sinl(0.0L) == 0.0L);
    CHECK(tanf(0.0f) == 0.0f);
    CHECK(tanl(0.0L) == 0.0L);
    return 0;
}
