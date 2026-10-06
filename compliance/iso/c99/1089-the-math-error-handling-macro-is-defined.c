/* 1089: the-math-error-handling-macro-is-defined
 *
 * ISO/IEC 9899:1999 7.12.1p3: math_errhandling is a macro that expands to
 * MATH_ERRNO or MATH_ERREXCEPT or both.
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
    CHECK(math_errhandling == MATH_ERRNO
        || math_errhandling == MATH_ERREXCEPT
        || math_errhandling == (MATH_ERRNO | MATH_ERREXCEPT));
    return 0;
}
