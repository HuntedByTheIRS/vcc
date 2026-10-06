/* 0027: two long double calls in one argument list keep both values

The inner call's stack release used to take the words the outer call had
already pushed, so the second value came back zero.  Fixed in 59b1243
("codegen: test two long double calls in one argument list"). */

#include <stdio.h>

static long double half(long double v) { return v / 2.0L; }
static long double add(long double a, long double b) { return a + b; }
int main(void)
{
    long double r = add(half(9.0L), half(8.0L));
    long double s = add(add(2.0L, 3.0L), add(4.0L, 5.0L));
    if (r != 8.5L) { fprintf(stderr, "two long double calls in one argument list lost a value\n"); return 1; }
    if (s != 14.0L) { fprintf(stderr, "nested long double calls lost a value\n"); return 1; }
    return 0;
}
