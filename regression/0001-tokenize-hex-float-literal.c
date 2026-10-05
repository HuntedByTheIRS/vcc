/* 0001: a hexadecimal floating constant reads as its value

The pp-number 0x1p3 was refused with `p is not a digit in base 16` and the
value path did not exist.  Fixed in 4ed37ce ("parser: read hexadecimal
floating constants"). */

#include <stdio.h>

int main(void)
{
    double a = 0x1p3;
    double b = 0x1.8p1;
    if (a != 8.0) { fprintf(stderr, "a hexadecimal float literal is wrong\n"); return 1; }
    if (b != 3.0) { fprintf(stderr, "a fractional hexadecimal float literal is wrong\n"); return 1; }
    return 0;
}
