/* 0049: a value wider than the object it is stored in is narrowed, not refused

6.3.1.3 makes the conversion from an integer type to a narrower one defined:
the value is shortened to the width of the destination, which for a signed
destination is the low bytes read back with the destination's sign and for an
unsigned one is the value modulo one more than its maximum. 6.5.16.1 then makes
that conversion part of the assignment, so `int pad = width - s.len;` is legal C
and not a mistake the compiler may refuse.

The back end refused it with 'a value of 8 bytes is stored into a slot of 4',
which stopped V's own generated C at the first `int` initialized from a
difference of a long. The store moves the slot's bytes, so the low ones are
already what the conversion leaves; what the check still refuses is an address
in a slot of fewer bytes, which is not a conversion at all.

Measured against gcc 16.2.1 on this machine: every line printed here is the same
under gcc and under vcc. */

#include <stdio.h>

static long difference(void)
{
    return 3 - (long)5;
}

int main(void)
{
    long diff = difference();
    int pad = diff;
    unsigned unsigned_pad = diff;

    if (diff != -2 || pad != -2 || unsigned_pad != 4294967294u) {
        fprintf(stderr, "an eight-byte value narrowed into four is wrong: %ld %d %u\n",
            diff, pad, unsigned_pad);
        return 1;
    }

    /* The width used to read the destination back is the destination's, so a
       negative value stays negative and an unsigned one does not. */
    int from_long = 4294967299L;
    if (from_long != 3) {
        fprintf(stderr, "2^32 + 3 did not narrow to 3: %d\n", from_long);
        return 1;
    }

    unsigned char c = 300;
    char sc = 200;
    short s = 70000;
    unsigned short us = 70000;
    if (c != 44 || sc != -56 || s != 4464 || us != 4464) {
        fprintf(stderr, "narrowing into a byte and a halfword is wrong: %u %d %d %u\n",
            (unsigned)c, (int)sc, (int)s, (unsigned)us);
        return 1;
    }

    long wide = 1234567890123L;
    int cut = wide;
    if (cut != 1912276171) {
        fprintf(stderr, "an eight-byte value cut to four is wrong: %d\n", cut);
        return 1;
    }

    /* The arithmetic happens at the wide type and only the store narrows it. */
    short half = 300 - 100000;
    int whole = 300 - 100000;
    long both = 300 - 100000;
    if (half != 31372 || whole != -99700 || both != -99700) {
        fprintf(stderr, "the arithmetic narrowed before the store: %d %d %ld\n",
            (int)half, whole, both);
        return 1;
    }

    long big = 4294967296L;
    int small = big;
    if (small != 0 || !(small == (int)big)) {
        fprintf(stderr, "the low four bytes of 2^32 are not zero: %d\n", small);
        return 1;
    }
    return 0;
}
