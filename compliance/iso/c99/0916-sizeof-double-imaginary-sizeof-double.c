/* 0916: CHECK(sizeof(double _Imaginary) == sizeof(double));
 *
 * monolithic.c:12156 (imaginary)
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
    CHECK(sizeof(double _Imaginary) == sizeof(double));
    return 0;
}
