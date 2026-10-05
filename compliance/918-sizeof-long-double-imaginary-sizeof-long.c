/* 918: CHECK(sizeof(long double _Imaginary) == sizeof(long double));
 *
 * monolithic.c:12158 (imaginary)
 * requires-define: C99_IMAGINARY
 * imaginary types are optional in C99 and neither gcc nor this
 * compiler implements them
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
    CHECK(sizeof(long double _Imaginary) == sizeof(long double));
    return 0;
}
