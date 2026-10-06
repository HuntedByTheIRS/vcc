/* 0017: a decimal long double past the extended range

The extended format reaches about 1.19e4932, and a decimal constant above that
is an overflow the standard leaves undefined. gcc 16.2.1 reads one as an
infinity, which is what glibc's HUGE_VALL names outside a GNU dialect, and the
case records that a constant just past the range is an infinity while one just
inside it stays finite. */

#include <float.h>
#include <stdio.h>

int main(void)
{
    long double past = 1e10000L;
    long double edge = 1e4933L;
    long double inside = 1e4932L;
    printf("%d %d %d\n", past > LDBL_MAX, edge > LDBL_MAX, inside < LDBL_MAX);
    printf("%d %d\n", -past < -LDBL_MAX, -past == -past);
    return 0;
}
