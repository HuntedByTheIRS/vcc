/* 540: CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
 *
 * monolithic.c:11250 (numerics)
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
    CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
    return 0;
}
