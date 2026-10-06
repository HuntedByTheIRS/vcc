/* 0998: CHECK((long double)(double)third != third);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    long double third = 1.0L / 3.0L;
    /* The extended type has more significand bits than a double, so a value it
     * holds is not always one a double can hold: the round trip through double
     * is a different number. */
    CHECK(third > 0.0L);
    CHECK(third < 1.0L);
    CHECK((long double)(double)third != third);
    CHECK(sizeof(long double) > sizeof(double));
    return 0;
}
