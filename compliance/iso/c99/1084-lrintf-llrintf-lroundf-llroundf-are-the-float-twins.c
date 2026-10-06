/* 1084: lrintf-llrintf-lroundf-llroundf-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.9.5: the lrint functions round x to the nearest
 * long.
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
    CHECK(lrintf(2.5f) == 2L);
    CHECK(lrintl(2.5L) == 2L);
    CHECK(llrintf(2.5f) == 2LL);
    CHECK(llrintl(2.5L) == 2LL);
    CHECK(lroundf(2.5f) == 3L);
    CHECK(lroundl(2.5L) == 3L);
    CHECK(llroundf(2.5f) == 3LL);
    CHECK(llroundl(2.5L) == 3LL);
    return 0;
}
