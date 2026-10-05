/* 0031: an array-typed member reads as its address where it decays

An array member is not a value, so `s.a[i]` is a subscript through the
member's address.  Fixed in 93ef8f2 ("codegen: read an array-typed member as
its address where it decays"). */

#include <stdio.h>

struct S { int a[3]; };
int main(void)
{
    struct S s;
    s.a[1] = 9;
    if (s.a[1] != 9) { fprintf(stderr, "an array-typed member did not decay\n"); return 1; }
    return 0;
}
