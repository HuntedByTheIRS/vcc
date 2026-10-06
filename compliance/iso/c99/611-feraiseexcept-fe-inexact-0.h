/* 611: CHECK(feraiseexcept(FE_INEXACT) == 0);
 *
 * monolithic.c:11348 (numerics)
 */

#include <stdio.h>
#include <fenv.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    CHECK(feraiseexcept(FE_INEXACT) == 0);
    }
    return 0;
}
