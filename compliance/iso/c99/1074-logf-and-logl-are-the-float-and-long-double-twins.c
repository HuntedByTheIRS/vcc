/* 1074: logf-and-logl-are-the-float-and-long-double-twins
 *
 * ISO/IEC 9899:1999 7.12.6.4: the log functions compute the natural
 * logarithm of x.
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
    CHECK(logf(1.0f) == 0.0f);
    CHECK(logl(1.0L) == 0.0L);
    CHECK(log10f(1.0f) == 0.0f);
    CHECK(log10l(1.0L) == 0.0L);
    return 0;
}
