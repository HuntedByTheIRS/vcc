/* 0005: a block-scope extern declaration has no local storage

`{ extern int obj; got = obj; }` of a file-scope `static int obj = 100;` read
address-shaped garbage, because the extern declaration was given a local.  It
names the object the unit defines now.  Fixed in 88b5610 ("parser: give a
block-scope extern declaration no local storage"). */

#include <stdio.h>

static int obj = 100;
int main(void)
{
    int got = 0;
    { extern int obj; got = obj; }
    if (got != 100) { fprintf(stderr, "block-scope extern read the wrong object\n"); return 1; }
    return 0;
}
