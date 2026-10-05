/* 0038: complex division uses the scaled formula

The naive `c*c + d*d` overflows on extreme pairs; C99 Annex G.5.1 scales.
Fixed in f8f1c52 ("codegen: emit the complex quotient with the scaled
division"). */

#include <stdio.h>
#include <complex.h>
int main(void)
{
    double _Complex a = 1.0 + 2.0 * I;
    double _Complex b = 3.0 + 4.0 * I;
    double _Complex c = a * b;   /* -5 + 10i */
    double _Complex d = c / b;   /* back to a */
    if (creal(d) != 1.0 || cimag(d) != 2.0) { fprintf(stderr, "complex multiplication or division is wrong\n"); return 1; }
    return 0;
}
