/* 0022: a conversion to _Bool compares the value with zero

`_Bool b = 2;` is 1 and `_Bool b = 0.0;` is 0.  Fixed in e4113e9 ("codegen: a
conversion to _Bool compares the value with zero"). */

#include <stdio.h>

int main(void)
{
    _Bool a = 2;
    _Bool b = 0.0;
    if (a != 1) { fprintf(stderr, "_Bool from a nonzero int is not 1\n"); return 1; }
    if (b != 0) { fprintf(stderr, "_Bool from zero is not 0\n"); return 1; }
    return 0;
}
