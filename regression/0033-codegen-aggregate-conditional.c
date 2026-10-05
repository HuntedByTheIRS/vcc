/* 0033: a conditional of aggregate arms is materialized as a value

`struct S z = (c ? x : y);` has to copy the chosen struct's bytes.  Fixed in
00ca4d2 ("codegen: materialize an aggregate conditional as a value"). */

#include <stdio.h>

struct S { int a; int b; };
int main(void)
{
    struct S x = {1, 2};
    struct S y = {3, 4};
    struct S z = (1 ? x : y);
    struct S w = (0 ? x : y);
    if (z.a != 1 || z.b != 2) { fprintf(stderr, "an aggregate conditional chose the wrong arm\n"); return 1; }
    if (w.a != 3 || w.b != 4) { fprintf(stderr, "an aggregate conditional lost its value\n"); return 1; }
    return 0;
}
