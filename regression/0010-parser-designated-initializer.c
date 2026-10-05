/* 0010: a designated initializer goes into the member it names

`{.b = 5}` and `{[3] = 1}`, with the members not named left zero.  Fixed in
fa829cf ("parser: take a designated aggregate member as the element's
value"). */

#include <stdio.h>

struct S { int a; int b; };
int main(void)
{
    struct S s = {.b = 5};
    int a[5] = {[3] = 1};
    if (s.b != 5 || s.a != 0) { fprintf(stderr, "a designated member initializer is wrong\n"); return 1; }
    if (a[3] != 1 || a[0] != 0) { fprintf(stderr, "a designated array initializer is wrong\n"); return 1; }
    return 0;
}
