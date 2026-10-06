/* 1090: huge-valf-huge-val-and-huge-vall-exceed-their-types-maximum
 *
 * ISO/IEC 9899:1999 7.12p3: HUGE_VALF, HUGE_VAL and HUGE_VALL expand to
 * positive constant expressions of type float, double and long double.
 *
 * Outside a GNU dialect glibc defines HUGE_VALL as `1e10000L`, a decimal
 * constant past every value the extended format reaches. The standard leaves
 * its value undefined and gcc 16.2.1 reads it as an infinity, which is what
 * this compiler does too.
 */

#include <float.h>
#include <math.h>

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(HUGE_VALF > FLT_MAX);
    CHECK(HUGE_VAL > DBL_MAX);
    CHECK(HUGE_VALL > LDBL_MAX);
    return 0;
}
