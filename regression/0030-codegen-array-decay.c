/* 0030: an array of aggregates reads as the address of its first element

`struct S t[3]; struct S *e = t;` used to be refused as an aggregate value.
Fixed in 2924959 ("codegen: an array of aggregates reads as the address of
its first element"). */

#include <stdio.h>

struct S { int a; int b; };
static struct S t[3] = {{1, 2}, {3, 4}, {5, 6}};
int main(void)
{
    struct S *e = t;
    if (e[1].a != 3) { fprintf(stderr, "an array of aggregates did not decay\n"); return 1; }
    if (e[2].b != 6) { fprintf(stderr, "a member read through the decayed pointer is wrong\n"); return 1; }
    if (e->a != 1) { fprintf(stderr, "a member read through the pointer is wrong\n"); return 1; }
    return 0;
}
