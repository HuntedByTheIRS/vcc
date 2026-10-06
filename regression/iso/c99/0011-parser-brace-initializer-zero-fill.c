/* 0011: a brace list zero-fills what it does not write

A shorter brace list leaves the rest of the aggregate zero.  Fixed in 1445f9e
("parser: zero-fill an aggregate subobject a brace list does not write"). */

#include <stdio.h>

struct S { int a; int b; int c; };
int main(void)
{
    struct S s = {1};
    int a[4] = {2, 3};
    if (s.b != 0 || s.c != 0) { fprintf(stderr, "a brace list did not zero-fill the rest\n"); return 1; }
    if (a[2] != 0 || a[3] != 0) { fprintf(stderr, "an array brace list did not zero-fill the rest\n"); return 1; }
    return 0;
}
