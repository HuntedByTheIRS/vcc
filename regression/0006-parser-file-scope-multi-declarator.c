/* 0006: every declarator of a file-scope declaration is registered

`static int a = 0, b = 0;` used to register only the first declarator, so
`b = 5` refused and `&b` had no object.  Fixed in 9c6150d ("parser: register
every declarator of a file-scope declaration"). */

#include <stdio.h>

static int a = 0, b = 0;
int main(void)
{
    b = 5;
    if (b != 5) { fprintf(stderr, "the second file-scope declarator has no storage\n"); return 1; }
    if (a != 0) { fprintf(stderr, "the first file-scope declarator lost its value\n"); return 1; }
    return 0;
}
