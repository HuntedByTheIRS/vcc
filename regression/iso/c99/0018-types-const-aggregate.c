/* 0018: a const-qualified aggregate reads as its unqualified type

`const struct S s = {3};` then `s.a`.  Fixed in ddc0750 ("types: read a
const-qualified aggregate as its unqualified type"). */

#include <stdio.h>

struct S { int a; };
static const struct S s = {3};
int main(void)
{
    if (s.a != 3) { fprintf(stderr, "a const aggregate lost its initializer\n"); return 1; }
    return 0;
}
