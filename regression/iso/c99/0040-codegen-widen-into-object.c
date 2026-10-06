/* 0040: assigning a value narrower than the object converts it to the object's
type instead of refusing

`long v = i` for an int i stores the int sign-extended into the whole object,
which is the conversion C99 6.5.16.1 defines and the same one `(long)i` makes.
The store paths in codegen/codegen.v (store_value, assign_member, the element
stores and convert_for_global) refused every width mismatch, so an int stored in
a long was rejected as "a value of 4 bytes is stored into a slot of 8" even
though the widening is defined.  Fixed by letting a value narrower than the
object through the width check and widening it with extend_operand_to_word. */

#include <stdio.h>

struct S { long m; };
static long g;

int main(void)
{
    int i = -3;
    long declared = i;
    long assigned;
    unsigned long uns = i;
    struct S s;

    assigned = i;
    g = i;
    s.m = i;

    if (declared != -3) { fprintf(stderr, "a declaration initializer dropped the sign of an int in a long\n"); return 1; }
    if ((declared >> 40) != -1) { fprintf(stderr, "a declaration initializer filled the high bytes with zero\n"); return 1; }
    if (assigned != -3) { fprintf(stderr, "an assignment dropped the sign of an int in a long\n"); return 1; }
    if ((assigned >> 40) != -1) { fprintf(stderr, "an assignment filled the high bytes with zero\n"); return 1; }
    if (g != -3) { fprintf(stderr, "an assignment to a file-scope object dropped the sign\n"); return 1; }
    if ((int)(uns >> 32) != -1) { fprintf(stderr, "an int stored in an unsigned long lost its sign bits\n"); return 1; }
    if (s.m != -3) { fprintf(stderr, "a struct member dropped the sign of an int in a long\n"); return 1; }
    return 0;
}
