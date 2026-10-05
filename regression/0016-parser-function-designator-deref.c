/* 0016: the dereference of a function designator is the designator

`(*f)()` is `f()`.  Fixed in 295ce73 ("parser, codegen: the dereference of a
function designator is the designator"). */

#include <stdio.h>

static int f(void) { return 7; }
int main(void)
{
    if ((*f)() != 7) { fprintf(stderr, "a dereferenced function designator is not callable\n"); return 1; }
    return 0;
}
