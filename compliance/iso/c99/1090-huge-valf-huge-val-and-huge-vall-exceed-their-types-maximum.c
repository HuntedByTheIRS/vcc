/* 1090: huge-valf-huge-val-and-huge-vall-exceed-their-types-maximum
 *
 * ISO/IEC 9899:1999 7.12p3: HUGE_VALF, HUGE_VAL and HUGE_VALL expand to
 * positive constant expressions of type float, double and long double.
 *
 * unimplemented: HUGE_VALL, which glibc defines as 1e10000L.
 *
 * gcc 16.2.1 compiles this program, runs it silent and exits 0, so the
 * program conforms to this clause and what is missing is this compiler.
 * What this compiler says instead:
 *
 *     1e10000L: the constant is outside the range this reader converts
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
