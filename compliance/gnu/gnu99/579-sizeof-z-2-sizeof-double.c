/* 579: CHECK(sizeof z == 2 * sizeof(double));
 *
 * monolithic.c:11306 (numerics)
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
    double complex z = 3.0 + 4.0 * I;
    CHECK(sizeof z == 2 * sizeof(double));
    }
    return 0;
}
