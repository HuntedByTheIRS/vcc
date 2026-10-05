/* 528: CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
 *
 * monolithic.c:11238 (numerics)
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
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    return 0;
}
