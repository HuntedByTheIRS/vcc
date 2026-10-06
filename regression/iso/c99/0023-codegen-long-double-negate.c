/* 0023: unary minus on a long double negates it

The x87 negate the extended format needs.  Fixed in 1b1b472 ("codegen:
compute unary minus on a long double with the x87 negate"). */

#include <stdio.h>

int main(void)
{
    long double x = 5.0L;
    long double y = -x;
    if (y != -5.0L) { fprintf(stderr, "unary minus on a long double is wrong\n"); return 1; }
    if (x != 5.0L) { fprintf(stderr, "unary minus changed its operand\n"); return 1; }
    return 0;
}
