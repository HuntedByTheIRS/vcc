/* 609: CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
 *
 * monolithic.c:11346 (numerics)
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
    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    }
    return 0;
}
