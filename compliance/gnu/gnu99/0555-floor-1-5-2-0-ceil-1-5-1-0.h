/* 0555: CHECK(floor(-1.5) == -2.0 && ceil(-1.5) == -1.0);
 *
 * monolithic.c:11265 (numerics)
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
    return 0;
}
