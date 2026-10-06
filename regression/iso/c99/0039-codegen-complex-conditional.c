/* 0039: a conditional of complex arms takes the complex type

`(1 ? x : y)` for two double _Complex values.  Fixed in 218f2f2 ("codegen:
convert a conditional of complex arms to its complex type"). */

#include <stdio.h>
#include <complex.h>
int main(void)
{
    double _Complex x = 1.0 + 2.0 * I;
    double _Complex y = 3.0 + 4.0 * I;
    double _Complex z = (1 ? x : y);
    if (creal(z) != 1.0 || cimag(z) != 2.0) { fprintf(stderr, "a complex conditional chose the wrong arm\n"); return 1; }
    return 0;
}
