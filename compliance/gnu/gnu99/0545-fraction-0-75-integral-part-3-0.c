/* 0545: CHECK(fraction == 0.75 && integral_part == 3.0);
 *
 * monolithic.c:11255 (numerics)
 */

#include <stdio.h>
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
    double integral_part = 0.0;
    double fraction = modf(3.75, &integral_part);
    CHECK(fraction == 0.75 && integral_part == 3.0);
    return 0;
}
