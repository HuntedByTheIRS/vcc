/* 0036: a function pointer survives a trip through void *

`void *p = (void *)f; int (*g)(void) = (int (*)(void))p;`.  Fixed in 10ac21b
("codegen: convert between a function pointer and void *"). */

#include <stdio.h>

static int f(void) { return 42; }
int main(void)
{
    void *p = (void *)f;
    int (*g)(void) = (int (*)(void))p;
    if (g() != 42) { fprintf(stderr, "a function pointer through void * does not survive\n"); return 1; }
    return 0;
}
