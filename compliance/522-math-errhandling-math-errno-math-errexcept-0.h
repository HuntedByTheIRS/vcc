/* 522: CHECK((math_errhandling & (MATH_ERRNO | MATH_ERREXCEPT)) != 0);
 *
 * monolithic.c:11230 (numerics)
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
    CHECK((math_errhandling & (MATH_ERRNO | MATH_ERREXCEPT)) != 0);
    return 0;
}
