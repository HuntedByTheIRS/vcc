/* 0623: CHECK(feraiseexcept(FE_DIVBYZERO) == 0);
 *
 * monolithic.c:11374 (numerics)
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
    fexcept_t flags;
    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    CHECK(feraiseexcept(FE_INEXACT) == 0);
    CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_INEXACT) != 0);
    CHECK(feclearexcept(FE_INEXACT) == 0);
    CHECK(fetestexcept(FE_INEXACT) == 0);
    CHECK(fegetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(fesetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    CHECK(feraiseexcept(FE_DIVBYZERO) == 0);
    }
    return 0;
}
