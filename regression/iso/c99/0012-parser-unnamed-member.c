/* 0012: an unnamed struct or union member promotes its members

`struct S { union { int a; int b; }; int c; };` makes a and b members of S.
Fixed in dd2d5d7 ("parser: record an unnamed struct or union member so its
members are promoted"). */

#include <stdio.h>

struct S { union { int a; int b; }; int c; };
int main(void)
{
    struct S s;
    s.a = 5;
    s.c = 6;
    if (s.b != 5) { fprintf(stderr, "an unnamed member's members are not promoted\n"); return 1; }
    if (s.c != 6) { fprintf(stderr, "a named member after an unnamed one is wrong\n"); return 1; }
    return 0;
}
