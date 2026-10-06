/* 0035: a bitfield store writes only its own bits, and a read masks them

An unsigned, a signed and a following bitfield in one struct.  Fixed in
de2db9d ("codegen: read a bitfield member from its own bits") and 6d042db
("codegen: write only a bitfield member's own bits"). */

#include <stdio.h>

struct S { unsigned a : 3; int b : 5; unsigned c : 7; };
int main(void)
{
    struct S s;
    s.a = 6;
    s.b = -7;
    s.c = 100;
    if (s.a != 6) { fprintf(stderr, "a runtime bitfield store lost bits\n"); return 1; }
    if (s.b != -7) { fprintf(stderr, "a signed runtime bitfield store lost bits\n"); return 1; }
    if (s.c != 100) { fprintf(stderr, "a bitfield after a signed one is wrong\n"); return 1; }
    return 0;
}
