/* 0546: CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
 *
 * monolithic.c:11256 (numerics)
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
    CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
    return 0;
}
