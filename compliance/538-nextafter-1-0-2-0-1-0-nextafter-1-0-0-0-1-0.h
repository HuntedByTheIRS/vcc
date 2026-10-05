/* 538: CHECK(nextafter(1.0, 2.0) > 1.0 && nextafter(1.0, 0.0) < 1.0);
 *
 * monolithic.c:11248 (numerics)
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
    CHECK(nextafter(1.0, 2.0) > 1.0 && nextafter(1.0, 0.0) < 1.0);
    return 0;
}
