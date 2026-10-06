/* 0547: CHECK(remainder_result == 1.0 && quo == 2);
 *
 * monolithic.c:11257 (numerics)
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
    int quo = 0;
    double remainder_result = remquo(7.0, 3.0, &quo);
    CHECK(remainder_result == 1.0 && quo == 2);
    return 0;
}
