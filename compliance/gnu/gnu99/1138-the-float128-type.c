/* 1138: the-float128-type
 *
 * GCC 6.1.4 Additional Floating Types: "As an extension, GNU C and GNU C++
 * support additional floating types, which are not supported by all targets.
 * __float128 is available on i386, x86_64, IA-64, LoongArch and hppa HP-UX ...
 * other than HP-UX, __float128 is an alias for _Float128."
 */

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
    _Float128 a = 1.5f128;

    CHECK(sizeof(_Float128) == 16);
    CHECK((double)a == 1.5);
    return 0;
}
