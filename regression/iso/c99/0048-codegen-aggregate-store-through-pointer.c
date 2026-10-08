/* 0048: an aggregate written through a pointer is the object copy

C99 6.5.16.1 lets a structure be assigned to an expression of the same
structure type, and `*p = v` for a `struct S *p` is that assignment through the
address the pointer holds. The back end chose its store from the pointed-at
type's width, and an aggregate has no width a single instruction writes, so the
shape was refused as "*p is assigned through an address of struct S, and this
back end writes ints, chars, doubles and pointers only". The address now takes
the object copy an assignment to an object of the same type already makes, at
the address the pointer holds: assign_deref (codegen/codegen.v). */

#include <stdio.h>

struct S { int a; int b; };
struct B { struct S s; long n; };

static struct S after = { 7, 8 };
static struct B after_big = { { 9, 10 }, 11 };

static void set(struct S *p, int a, int b)
{
    struct S v = { a, b };
    *p = v;
}

static void set_big(struct B *p)
{
    struct B v = { { 1, 2 }, 3 };
    *p = v;
}

static void set_from_call(struct S *p)
{
    *p = (struct S){ 5, 6 };
}

static struct S from_function(void)
{
    struct S v = { 41, 42 };
    return v;
}

static void set_from_return(struct S *p)
{
    *p = from_function();
}

int main(void)
{
    struct S s = { 0, 0 };
    set(&s, 4, 5);
    if (s.a != 4 || s.b != 5) {
        fprintf(stderr, "a struct written through a pointer did not read back\n");
        return 1;
    }
    set_from_call(&s);
    if (s.a != 5 || s.b != 6) {
        fprintf(stderr, "a compound literal written through a pointer is wrong\n");
        return 1;
    }
    set_from_return(&s);
    if (s.a != 41 || s.b != 42) {
        fprintf(stderr, "a call's result written through a pointer is wrong\n");
        return 1;
    }
    if (after.a != 7 || after.b != 8) {
        fprintf(stderr, "the store ran past the object it named\n");
        return 1;
    }

    struct B b = { { 0, 0 }, 0 };
    set_big(&b);
    if (b.s.a != 1 || b.s.b != 2 || b.n != 3) {
        fprintf(stderr, "a larger struct written through a pointer is wrong\n");
        return 1;
    }
    if (after_big.s.a != 9 || after_big.s.b != 10 || after_big.n != 11) {
        fprintf(stderr, "the larger store ran past the object it named\n");
        return 1;
    }

    /* The same shape one and two levels down, which already worked. */
    struct S *p = &s;
    struct S **pp = &p;
    **pp = s;
    if (s.a != 41 || s.b != 42) {
        fprintf(stderr, "a store through a pointer to a pointer is wrong\n");
        return 1;
    }
    if (s.a != p->a || s.b != p->b) {
        fprintf(stderr, "the pointer and the object disagree\n");
        return 1;
    }
    return 0;
}
