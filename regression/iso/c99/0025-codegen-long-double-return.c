/* 0025: a long double returns on the x87 stack

A function whose result is a long double hands the value back.  Fixed in
db6f22e ("codegen: return a long double on the x87 stack"). */

#include <stdio.h>

static long double half(long double v)
{
    return v / 2.0L;
}
int main(void)
{
    if (half(9.0L) != 4.5L) { fprintf(stderr, "a long double return lost its value\n"); return 1; }
    return 0;
}
