/* 0041: e[i].m = v stores through a pointer subscript, not refused

Assigning to a member of a subscripted pointer, `e[1].a = 5` for `struct S *e`,
was refused as "e is read as an array, and its declaration is not one" while
the same subscript on a read was accepted. The assignment target now resolves
the pointer subscript the way the read does, in parse_member_path
(parser/parser.v), which holds the element in the Field's base and looks the
member up in what the pointer points at. */

#include <stdio.h>

struct S { int a; int b; };
static struct S t[3];

int main(void)
{
    struct S *e = t;
    e[1].a = 5;
    if (e[1].a != 5) { fprintf(stderr, "a store through a pointer subscript did not read back\n"); return 1; }
    if (e[0].a != 0) { fprintf(stderr, "the store wrote the element before the one it named\n"); return 1; }
    if (e[2].a != 0) { fprintf(stderr, "the store wrote the element after the one it named\n"); return 1; }
    e[2].b = 4;
    if (e[2].b != 4 || e[2].a != 0) { fprintf(stderr, "a second member through a pointer subscript is wrong\n"); return 1; }
    int i = 1;
    e[i].a = 7;
    if (e[1].a != 7) { fprintf(stderr, "a variable index through a pointer subscript is wrong\n"); return 1; }
    struct S *p = &t[1];
    p[0].b = 9;
    if (t[1].b != 9) { fprintf(stderr, "a pointer into the middle of the array did not store where it points\n"); return 1; }
    return 0;
}
