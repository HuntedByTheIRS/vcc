/* 0542: CHECK(scalbn(1.0, 10) == 1024.0 && scalbln(1.0, 10L) == 1024.0);
 *
 * monolithic.c:11252 (numerics)
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
    CHECK(scalbn(1.0, 10) == 1024.0 && scalbln(1.0, 10L) == 1024.0);
    return 0;
}
