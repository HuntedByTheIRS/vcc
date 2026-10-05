/* 556: CHECK(floorf(-1.5f) == -2.0f && floorl(-1.5L) == -2.0L);
 *
 * monolithic.c:11266 (numerics)
 */

#include <stdio.h>
#include <complex.h>
#include <math.h>
#include <tgmath.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(floor(-1.5) == -2.0 && ceil(-1.5) == -1.0);
    CHECK(floorf(-1.5f) == -2.0f && floorl(-1.5L) == -2.0L);
    return 0;
}
