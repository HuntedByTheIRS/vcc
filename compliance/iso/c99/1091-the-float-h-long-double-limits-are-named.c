/* 1091: the-float-h-long-double-limits-are-named
 *
 * ISO/IEC 9899:1999 5.2.4.2.2p11: LDBL_MANT_DIG, LDBL_DIG, LDBL_MIN_EXP,
 * LDBL_MAX_EXP, LDBL_MIN, LDBL_MAX and LDBL_EPSILON are the long double
 * limits.
 */

#include <float.h>

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
    CHECK(LDBL_MANT_DIG >= 64);
    CHECK(LDBL_DIG >= 18);
    CHECK(LDBL_MIN_EXP <= -16381);
    CHECK(LDBL_MAX_EXP >= 16384);
    CHECK(LDBL_MIN < 1e-4900L);
    CHECK(LDBL_MAX > 1e4900L);
    CHECK(LDBL_EPSILON < 1e-18L);
    CHECK(DECIMAL_DIG >= LDBL_DIG);
    return 0;
}
