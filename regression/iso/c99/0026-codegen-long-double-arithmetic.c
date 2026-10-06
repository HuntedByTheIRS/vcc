/* 0026: long double arithmetic and comparison run on the x87 stack

The four operations and the six comparisons of two long doubles.  Fixed in
b03dbc1 ("codegen: compute and compare long doubles on the x87 stack"). */

#include <stdio.h>

int main(void)
{
    long double a = 6.0L, b = 4.0L;
    if (a + b != 10.0L) { fprintf(stderr, "long double addition is wrong\n"); return 1; }
    if (a - b != 2.0L) { fprintf(stderr, "long double subtraction is wrong\n"); return 1; }
    if (a * b != 24.0L) { fprintf(stderr, "long double multiplication is wrong\n"); return 1; }
    if (a / b != 1.5L) { fprintf(stderr, "long double division is wrong\n"); return 1; }
    if (!(a > b) || !(b < a) || !(a != b)) { fprintf(stderr, "long double comparison is wrong\n"); return 1; }
    return 0;
}
