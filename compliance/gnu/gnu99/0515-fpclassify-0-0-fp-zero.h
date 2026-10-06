/* 0515: CHECK(fpclassify(0.0) == FP_ZERO);
 *
 * monolithic.c:11220 (numerics)
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
    CHECK(fpclassify(1.0) == FP_NORMAL);
    CHECK(fpclassify(0.0) == FP_ZERO);
    return 0;
}
