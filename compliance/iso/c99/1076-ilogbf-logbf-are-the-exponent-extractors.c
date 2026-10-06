/* 1076: ilogbf-logbf-are-the-exponent-extractors
 *
 * ISO/IEC 9899:1999 7.12.6.9: the ilogb functions extract the exponent of x
 * as a signed int.
 */

#include <math.h>

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
    CHECK(ilogbf(8.0f) == 3);
    CHECK(ilogbl(8.0L) == 3);
    CHECK(logbf(8.0f) == 3.0f);
    CHECK(logbl(8.0L) == 3.0L);
    return 0;
}
