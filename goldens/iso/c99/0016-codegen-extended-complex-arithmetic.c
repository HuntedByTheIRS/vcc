/* 0016: the arithmetic of the extended complex type

`long double _Complex` is two extended components, thirty-two bytes in all. The
case prints the quotient, the negation, the sum, the difference and the product
of a pair of values, so a change to the x87 arithmetic behind any of them moves
the recorded bytes. It also prints whether a decimal constant past the extended
range reads as an infinity. */

#include <complex.h>
#include <float.h>
#include <stdio.h>

int main(void)
{
    long double _Complex a = 3.0L + 4.0L * I;
    long double _Complex b = 1.0L - 2.0L * I;
    long double _Complex q = a / 2.0L;
    long double _Complex r = a / b;
    long double _Complex n = -a;
    long double _Complex s = a + b;
    long double _Complex d = a - b;
    long double _Complex p = a * b;
    long double big = 1e10000L;
    printf("%d\n", (int)sizeof(long double _Complex));
    printf("%.1Lf %.1Lf\n", creall(q), cimagl(q));
    printf("%.1Lf %.1Lf\n", creall(r), cimagl(r));
    printf("%.1Lf %.1Lf\n", creall(n), cimagl(n));
    printf("%.1Lf %.1Lf\n", creall(s), cimagl(s));
    printf("%.1Lf %.1Lf\n", creall(d), cimagl(d));
    printf("%.1Lf %.1Lf\n", creall(p), cimagl(p));
    printf("%d %d\n", big > LDBL_MAX, big < -LDBL_MAX);
    return 0;
}
