/* 0046: a decimal long double past the extended range

A decimal constant whose value is above LDBL_MAX was refused with "the constant
is outside the range this reader converts". The standard leaves the value
undefined and gcc 16.2.1 reads it as an infinity, which is what glibc's
HUGE_VALL names outside a GNU dialect as `1e10000L`. A constant past the range
is an infinity, one just inside the range stays finite, and the negation of an
overflowing one is an infinity of the other sign. Fixed in 775f0e7 ("parser: a
decimal long double past the extended range is an infinity"). */

#include <float.h>
#include <stdio.h>

int main(void)
{
    long double past = 1e10000L;
    if (!(past > LDBL_MAX)) {
        fprintf(stderr, "a decimal long double above the range did not overflow\n");
        return 1;
    }
    long double edge = 1e4933L;
    if (!(edge > LDBL_MAX)) {
        fprintf(stderr, "a decimal long double just above LDBL_MAX did not overflow\n");
        return 1;
    }
    long double inside = 1e4932L;
    if (!(inside < LDBL_MAX) || inside > LDBL_MAX) {
        fprintf(stderr, "a decimal long double inside the range did not stay finite\n");
        return 1;
    }
    if (!(-past < -LDBL_MAX)) {
        fprintf(stderr, "the negation of an overflowing constant is wrong\n");
        return 1;
    }
    return 0;
}
