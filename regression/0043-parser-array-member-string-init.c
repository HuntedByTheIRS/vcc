/* 0043: a struct member that is an array of char takes a string literal

C99 6.7.8p14 lets an array of character type be initialized by a string
literal, and a struct member is an object like any other: `struct P { char
s[4]; }; struct P p = { "ab" };` writes 'a', 'b' and two zeros. The walk that
places a struct's brace initializer reached the member's char array one element
at a time, and the literal, which is an address, was refused as "an address
initializes an object of the type char, which is not a pointer". The walk now
recognizes a string literal on an array of character type at the subobject it
initializes and lays its bytes out the way the direct array case already does,
in fill_one and the array arm of fill_brace (parser/declarations.v). A local
initializer of the same shape reached the same refusal one stage later, in
codegen's store, and is fixed by the same walk. */

#include <stdio.h>

struct P { char s[4]; };
struct Q { struct P p; };
struct R { char s[4]; int n; };
struct E { char s[2]; };
struct C { const char s[4]; };

static struct P p1 = { "ab" };
static struct Q q1 = { { "ab" } };
static struct R r1 = { "ab", 7 };
static struct P many[2] = { { "ab" }, { "cd" } };
static struct E exact = { "ab" };
static struct P escape = { "\1" "2" };
static const struct C constant = { "ab" };
static struct P braced = { {"ab"} };

/* Things that already worked and must keep working. */
char direct[4] = "ab";
char *pointer = "ab";
struct M { char *s; };
static struct M member_pointer = { "ab" };
static struct N { int a; char s[4]; } nested_values = { 1, {'x'} };

int main(void)
{
    if (p1.s[0] != 'a' || p1.s[1] != 'b' || p1.s[2] != 0 || p1.s[3] != 0) {
        fprintf(stderr, "a struct member from a string literal is wrong\n");
        return 1;
    }
    if (q1.p.s[0] != 'a' || q1.p.s[1] != 'b' || q1.p.s[2] != 0) {
        fprintf(stderr, "a nested struct member from a string literal is wrong\n");
        return 1;
    }
    if (r1.s[0] != 'a' || r1.s[1] != 'b' || r1.s[2] != 0 || r1.s[3] != 0 || r1.n != 7) {
        fprintf(stderr, "a member before another member took the literal, or the member after it did\n");
        return 1;
    }
    if (many[0].s[0] != 'a' || many[0].s[1] != 'b' || many[1].s[0] != 'c'
        || many[1].s[1] != 'd' || sizeof many != 8) {
        fprintf(stderr, "an array of structs from string literals is wrong\n");
        return 1;
    }
    if (exact.s[0] != 'a' || exact.s[1] != 'b' || sizeof exact.s != 2) {
        fprintf(stderr, "a literal exactly filling the member kept a terminator it had no room for\n");
        return 1;
    }
    if (escape.s[0] != 1 || escape.s[1] != '2' || escape.s[2] != 0) {
        fprintf(stderr, "adjacent literals naming an escape are wrong in the member\n");
        return 1;
    }
    if (constant.s[0] != 'a' || constant.s[1] != 'b' || constant.s[2] != 0) {
        fprintf(stderr, "a const member from a string literal is wrong\n");
        return 1;
    }
    if (braced.s[0] != 'a' || braced.s[1] != 'b' || braced.s[2] != 0) {
        fprintf(stderr, "a braced string literal for the member is wrong\n");
        return 1;
    }

    /* The same shape as a local initializer, which reaches the store path. */
    struct P local = { "ab" };
    if (local.s[0] != 'a' || local.s[1] != 'b' || local.s[2] != 0 || local.s[3] != 0) {
        fprintf(stderr, "a local struct member from a string literal is wrong\n");
        return 1;
    }
    static struct P local_static = { "ab" };
    if (local_static.s[0] != 'a' || local_static.s[1] != 'b' || local_static.s[2] != 0) {
        fprintf(stderr, "a local static member from a string literal is wrong\n");
        return 1;
    }
    struct R local_tail = { "ab", 9 };
    if (local_tail.s[0] != 'a' || local_tail.s[1] != 'b' || local_tail.s[2] != 0
        || local_tail.s[3] != 0 || local_tail.n != 9) {
        fprintf(stderr, "a local member before another member is wrong\n");
        return 1;
    }

    /* Unchanged behaviour. */
    if (direct[0] != 'a' || direct[1] != 'b' || direct[2] != 0 || direct[3] != 0) {
        fprintf(stderr, "a direct char array from a string literal regressed\n");
        return 1;
    }
    if (pointer[0] != 'a' || pointer[1] != 'b' || member_pointer.s[0] != 'a'
        || member_pointer.s[1] != 'b') {
        fprintf(stderr, "a pointer from a string literal regressed\n");
        return 1;
    }
    if (nested_values.a != 1 || nested_values.s[0] != 'x' || nested_values.s[1] != 0) {
        fprintf(stderr, "a nested list for a char array member regressed\n");
        return 1;
    }
    return 0;
}
