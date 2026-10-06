/* 0034: a static bitfield initializer writes the member's own bits

`static struct S s = {5, 21};` for two bitfields.  Fixed in 2684e14
("codegen: write a static bitfield initializer's own bits"). */

#include <stdio.h>

struct S { unsigned a : 3; unsigned b : 5; };
static struct S s = {5, 21};
int main(void)
{
    if (s.a != 5) { fprintf(stderr, "a static bitfield initializer is wrong\n"); return 1; }
    if (s.b != 21) { fprintf(stderr, "a static bitfield initializer is wrong\n"); return 1; }
    return 0;
}
