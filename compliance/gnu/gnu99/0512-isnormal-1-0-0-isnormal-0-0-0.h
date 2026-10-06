/* 0512: CHECK(isnormal(1.0) != 0 && isnormal(0.0) == 0);
 *
 * monolithic.c:11217 (numerics)
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
    CHECK(isnormal(1.0) != 0 && isnormal(0.0) == 0);
    return 0;
}
