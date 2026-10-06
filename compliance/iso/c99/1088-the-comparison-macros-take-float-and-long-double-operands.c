/* 1088: the-comparison-macros-take-float-and-long-double-operands
 *
 * ISO/IEC 9899:1999 7.12.14.1: isgreater, isgreaterequal, isless,
 * islessequal, islessgreater and isunordered are macros.
 */

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
    float small = 1.0f;
    float big = 2.0f;
    long double l = 1.0L;
    CHECK(isgreater(big, small) && isgreater(big, l));
    CHECK(isgreater(l, 0.5f) && !isgreater(0.5f, l));
    CHECK(isgreaterequal(big, small) && isgreaterequal(small, small));
    CHECK(isless(small, big) && islessequal(small, big) && islessequal(big, big));
    CHECK(islessgreater(small, big) && !islessgreater(small, small));
    CHECK(!isunordered(small, big));
    CHECK(isunordered(nanf(""), small));
    return 0;
}
