/* 0509: CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
 *
 * monolithic.c:11214 (numerics)
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
    volatile double zero = 0.0;
    volatile double one = 1.0;
    double inf = one / zero;
    double not_a_number = inf - inf;
    double d = 2.5;
    CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
    return 0;
}
