/* 580: CHECK(sizeof(bare) == sizeof(double complex));
 *
 * monolithic.c:11307 (numerics)
 */

#include <stdio.h>
#include <complex.h>
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
    {
    double _Complex bare = 1.0 + 1.0 * I;
    CHECK(sizeof(bare) == sizeof(double complex));
    }
    return 0;
}
