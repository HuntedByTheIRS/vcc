/* 0536: CHECK(fmax(3.0, 5.0) == 5.0 && fmin(3.0, 5.0) == 3.0);
 *
 * monolithic.c:11246 (numerics)
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
    CHECK(fmax(3.0, 5.0) == 5.0 && fmin(3.0, 5.0) == 3.0);
    return 0;
}
