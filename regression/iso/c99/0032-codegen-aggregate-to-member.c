/* 0032: an aggregate value copies into a struct member

`o.in = i;` for a struct member of struct type.  Fixed in e5dbde5 ("codegen:
copy an aggregate value into a struct member"). */

#include <stdio.h>

struct Inner { int a; int b; };
struct Outer { struct Inner in; int c; };
int main(void)
{
    struct Inner i = {1, 2};
    struct Outer o;
    o.in = i;
    o.c = 3;
    if (o.in.b != 2) { fprintf(stderr, "an aggregate assignment into a member is wrong\n"); return 1; }
    if (o.c != 3) { fprintf(stderr, "a member after an aggregate member is wrong\n"); return 1; }
    return 0;
}
