/* 0138: CHECK(c99_nearlyl(sqrtl(2.0L) * sqrtl(2.0L), 2.0L));
 *
 * monolithic.c:9817 (types)
 */

#include <stdio.h>
#include <math.h>
#include <tgmath.h>

static long double c99_nearlyl(long double a, long double b);

static long double c99_nearlyl(long double a, long double b)
{
    long double diff = fabsl(a - b);
    long double scale = fabsl(a) > fabsl(b) ? fabsl(a) : fabsl(b);
    return diff <= 1e-18L * (scale > 1.0L ? scale : 1.0L);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_nearlyl(sqrtl(2.0L) * sqrtl(2.0L), 2.0L));
    return 0;
}
