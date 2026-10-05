/* 0017: an unsuffixed decimal past every signed type is unsigned

18446744073709551615 fits no signed type; the reader refused it.  The widest
type this back end writes holds its low 64 bits.  Fixed in 97c86d5 ("types: a
decimal constant past every signed type is an unsigned 64-bit type"). */

#include <stdio.h>

int main(void)
{
    unsigned long long u = 18446744073709551615;
    if (u != 0xFFFFFFFFFFFFFFFFULL) { fprintf(stderr, "an unsuffixed decimal past signed types is wrong\n"); return 1; }
    return 0;
}
