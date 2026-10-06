/* 0044: the quotient of two long double _Complex values

C99 7.3.3p1 gives the multiplicative operators their usual meaning for complex
operands, and the division of a `long double _Complex` was refused by name:
"/ is not an operator this back end computes long double _Complex with". The
quotient is the scaled division of Annex G.5.1, which is the arithmetic
libgcc's __divxc3 carries. A divisor whose component is at the top of the
extended range, and one whose component is small enough to need the scale-up
branch, both have to come out right rather than to overflow or underflow.
Fixed in a936814 ("backend, codegen: the extended complex quotient"). */

#include <complex.h>
#include <stdio.h>

static long double _Complex make(long double re, long double im)
{
    return re + im * I;
}

int main(void)
{
    long double _Complex a = make(3.0L, 4.0L);
    long double _Complex half = a / 2.0L;
    if (creall(half) != 1.5L || cimagl(half) != 2.0L) {
        fprintf(stderr, "a long double _Complex quotient by a real value is wrong\n");
        return 1;
    }
    long double _Complex b = make(1.0L, -2.0L);
    long double _Complex q = a / b;
    if (creall(q) != -1.0L || cimagl(q) != 2.0L) {
        fprintf(stderr, "a long double _Complex quotient is wrong\n");
        return 1;
    }
    /* Every component is exactly representable, so a value divided by itself is
       one and zero, however large the value is and whichever branch the scaling
       takes. */
    long double _Complex huge = make(1e4932L, 1e4932L);
    long double _Complex identity = huge / huge;
    if (creall(identity) != 1.0L || cimagl(identity) != 0.0L) {
        fprintf(stderr, "a quotient of two values at the top of the range is wrong\n");
        return 1;
    }
    long double _Complex tiny = make(1e-2000L, 1e-2000L);
    long double _Complex other = tiny / tiny;
    if (creall(other) != 1.0L || cimagl(other) != 0.0L) {
        fprintf(stderr, "a quotient of two values at the bottom of the range is wrong\n");
        return 1;
    }
    /* The quotient is a value the same width as its operands, so it can be
       stored and read back through a real object of the type. */
    long double _Complex stored = q;
    if (creall(stored) != creall(q) || cimagl(stored) != cimagl(q)) {
        fprintf(stderr, "a stored long double _Complex quotient changed\n");
        return 1;
    }
    return 0;
}
