/* 0024: a truth test on a long double compares it with zero

A long double used as a condition tests against zero, not its low word.
Fixed in 9375559 ("codegen,backend: a truth test on a long double compares it
with zero"). */

#include <stdio.h>

int main(void)
{
    long double z = 0.0L;
    long double n = -3.0L;
    if (z) { fprintf(stderr, "a zero long double tested true\n"); return 1; }
    if (!n) { fprintf(stderr, "a nonzero long double tested false\n"); return 1; }
    return 0;
}
