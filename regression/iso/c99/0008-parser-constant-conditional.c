/* 0008: a constant conditional folds to its taken arm

`1 ? 10 : 20` has to fold to 10.  Fixed in 885dba9 ("parser: fold a constant
condition of a conditional expression"); 26a1060 ("codegen: emit only the
taken arm of a constant conditional") followed. */

#include <stdio.h>

int main(void)
{
    int x = (1 ? 10 : 20);
    int y = (0 ? 30 : 40);
    if (x != 10) { fprintf(stderr, "a constant conditional chose the wrong arm\n"); return 1; }
    if (y != 40) { fprintf(stderr, "a constant conditional chose the wrong arm\n"); return 1; }
    return 0;
}
