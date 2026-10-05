/* 0015: a pointer-to-array parameter reads through it

`int (*p)[3]`, with (*p)[1] the element.  Fixed in 1801e71 ("parser: a pointer
to an array an alias names is a parameter this reader knows"). */

#include <stdio.h>

static int second(int (*p)[3])
{
    return (*p)[1];
}
int main(void)
{
    int a[3] = {1, 2, 3};
    if (second(&a) != 2) { fprintf(stderr, "a pointer-to-array parameter is read wrong\n"); return 1; }
    return 0;
}
