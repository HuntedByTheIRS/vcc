/* 0047: an element of the aggregate's own type initializes the subobject whole

C99 6.7.8p13 makes a structure's initializer a brace-enclosed list, and one
element of that list is the value of the member it names by position. The walk
that placed a struct's brace list read every element that was not itself a
brace list as the first of the initializers the elision rule of 6.7.8p20
spreads over the member's own members, so `struct M m = {a, b, 9}` with `a` and
`b` of the member's type wrote `a`'s members into the first member's members
and pushed everything after them down one member. With a scalar member at that
position the misreading is silent; with a member that is itself an aggregate it
surfaces as a member lookup against the wrong type, which is how V's generated
C reached it: `struct array has no member named sign`. fill_one now asks
whether the element is an expression of the aggregate's own type and writes it
whole when it is, and the elements after it go to the next member
(parser/declarations.v). */

#include <stdio.h>

typedef struct P { int x; int y; } P;
typedef struct M { P a; P b; int c; } M;

static P first = { 11, 12 };
static P second = { 21, 22 };
static M from_names = { { 31, 32 }, { 33, 34 }, 35 };

/* Every element an object of the member's own type. */
static M variables(void)
{
    P a = { 1, 2 };
    P b = { 3, 4 };
    M m = { a, b, 9 };
    return m;
}

/* The same through a compound literal, and through a return. */
static M literal(void)
{
    P a = { 1, 2 };
    P b = { 3, 4 };
    return (M){ a, b, 9 };
}

/* The members named by .name, which the walk already took one level down. */
static M named(void)
{
    return (M){ .a = first, .b = second, .c = 6 };
}

/* An array of the struct type, one element per value. */
static P element(int i)
{
    P a = { 5, 6 };
    P b = { 7, 8 };
    P v[2] = { a, b };
    return v[i];
}

/* Brace elision proper: no element is of the aggregate's own type. */
static M elided(void)
{
    M m = { 1, 2, 3, 4, 5 };
    return m;
}

int main(void)
{
    M m = variables();
    if (m.a.x != 1 || m.a.y != 2 || m.b.x != 3 || m.b.y != 4 || m.c != 9) {
        fprintf(stderr, "a member from a value of its own type is wrong\n");
        return 1;
    }
    M l = literal();
    if (l.a.x != 1 || l.a.y != 2 || l.b.x != 3 || l.b.y != 4 || l.c != 9) {
        fprintf(stderr, "the same through a compound literal is wrong\n");
        return 1;
    }
    M n = named();
    if (n.a.x != 11 || n.a.y != 12 || n.b.x != 21 || n.b.y != 22 || n.c != 6) {
        fprintf(stderr, "a designated element of the member's type is wrong\n");
        return 1;
    }
    P p0 = element(0);
    P p1 = element(1);
    if (p0.x != 5 || p0.y != 6 || p1.x != 7 || p1.y != 8) {
        fprintf(stderr, "an element of a struct array from a struct value is wrong\n");
        return 1;
    }
    if (from_names.a.y != 32 || from_names.b.x != 33 || from_names.c != 35) {
        fprintf(stderr, "a braced member of the member's own type regressed\n");
        return 1;
    }
    M e = elided();
    if (e.a.x != 1 || e.a.y != 2 || e.b.x != 3 || e.b.y != 4 || e.c != 5) {
        fprintf(stderr, "brace elision for elements none of which is a value is wrong\n");
        return 1;
    }
    if (sizeof(M) != 20 || sizeof(P) != 8) {
        fprintf(stderr, "the members do not sit where they did\n");
        return 1;
    }
    return 0;
}
