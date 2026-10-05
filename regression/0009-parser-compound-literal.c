/* 0009: a compound literal is an object with its values

`(struct S){1, 2}` as an initializer and as a call argument.  Fixed in
3083e2e ("parser: a compound literal initializes an aggregate object and its
elements"). */

#include <stdio.h>

struct S { int a; int b; };
static int sum(struct S s) { return s.a + s.b; }
int main(void)
{
    struct S s = (struct S){1, 2};
    if (s.b != 2) { fprintf(stderr, "a compound literal is wrong\n"); return 1; }
    if (sum((struct S){3, 4}) != 7) { fprintf(stderr, "a compound literal argument is wrong\n"); return 1; }
    return 0;
}
