/* 0045: the negation of a long double _Complex

C99 7.3.2p1 gives the additive operators their usual meaning for complex
operands, and the negation of a `long double _Complex` was refused by name on
the grounds that the x87 stack has no negate for the extended format. It has
one, `fchs`, and the negation flips the sign bit of each component and changes
nothing else: a component that is zero keeps its sign, a value already negative
becomes positive, and an infinity keeps being an infinity with the other sign.
Fixed in fff5276 ("codegen: negate a long double _Complex component by
component"). */

#include <complex.h>
#include <float.h>
#include <stdio.h>
#include <string.h>

static int sign_bit(long double v)
{
    unsigned char bytes[16];
    memcpy(bytes, &v, 16);
    return (bytes[9] >> 7) & 1;
}

int main(void)
{
    long double _Complex a = 1.0L + 2.0L * I;
    long double _Complex n = -a;
    if (creall(n) != -1.0L || cimagl(n) != -2.0L) {
        fprintf(stderr, "the negation of a long double _Complex is wrong\n");
        return 1;
    }
    if (creall(-n) != creall(a) || cimagl(-n) != cimagl(a)) {
        fprintf(stderr, "a double negation is not the value it started from\n");
        return 1;
    }
    /* The sign bit flips on each component and nothing else rounds, so a zero
       component is still a zero afterwards and its sign is the other one. */
    long double _Complex z = -0.0L + 0.0L * I;
    long double _Complex nz = -z;
    if (sign_bit(creall(nz)) == sign_bit(creall(z))) {
        fprintf(stderr, "the real component of a negated zero kept its sign\n");
        return 1;
    }
    if (sign_bit(cimagl(nz)) == sign_bit(cimagl(z))) {
        fprintf(stderr, "the imaginary component of a negated zero kept its sign\n");
        return 1;
    }
    /* An infinity takes the other sign and stays an infinity. */
    long double _Complex inf = 1e10000L + 0.0L * I;
    long double _Complex ninf = -inf;
    if (!(creall(ninf) < -LDBL_MAX) || !(cimagl(ninf) == 0.0L)) {
        fprintf(stderr, "the negation of an infinite long double _Complex is wrong\n");
        return 1;
    }
    return 0;
}
