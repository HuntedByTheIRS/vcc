/* 0139: CHECK(FLT_RADIX >= 2 && FLT_MANT_DIG > 0 && DBL_MANT_DIG > FLT_MANT_DIG);
 *
 * monolithic.c:9818 (types)
 */

#include <stdio.h>
#include <float.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(FLT_RADIX >= 2 && FLT_MANT_DIG > 0 && DBL_MANT_DIG > FLT_MANT_DIG);
    return 0;
}
