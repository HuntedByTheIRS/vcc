// A NaN compared with a decimal. C99 6.5.8 makes every relational and equality
// operator false when either operand is a NaN, except !=, which is true. The
// comparison is a routine, and this case pins the one operand the routine cannot
// produce from its table: a NaN has no literal spelling here, so its bytes are
// written into the object through the object's address and the same bytes are read
// back by both compilers.
//
// The other half is a zero written with another exponent. `0e30dd` is a zero and
// its bytes are not `0.0dd`'s, and two zeros are equal whatever bytes each keeps,
// so a comparison that reads the bytes instead of the value answers this case
// wrong.
//
// The case is silent on purpose: for a regression case a line of output is itself
// the regression, so this checks the answers and exits non-zero rather than
// printing them.
#include <string.h>

int main(void) {
	_Decimal64 a = 1.5dd;
	_Decimal64 b = 15e-1dd;

	// Two equal values written with a different exponent are equal, and neither is
	// less or greater than the other.
	if (a != b) {
		return 1;
	}
	if (a < b) {
		return 2;
	}
	if (b < a) {
		return 3;
	}

	// A zero carries its own exponent, so `0e30dd` has other bytes than `0.0dd`
	// and the two zeros are still equal.
	_Decimal64 z = 0.0dd;
	_Decimal64 ze = 0e30dd;
	if (z != ze) {
		return 4;
	}
	if (z < ze) {
		return 5;
	}

	// The quiet NaN: the five marker bits below the sign all set, the quiet bit
	// above the payload set.
	_Decimal64 n;
	unsigned char nan[8] = { 0, 0, 0, 0, 0, 0, 0, 0x7c };
	memcpy(&n, nan, sizeof nan);

	if (n == n) {
		return 6;
	}
	if (!(n != n)) {
		return 7;
	}
	if (n == a) {
		return 8;
	}
	if (!(n != a)) {
		return 9;
	}
	if (n < a) {
		return 10;
	}
	if (n > a) {
		return 11;
	}
	if (n <= a) {
		return 12;
	}
	if (n >= a) {
		return 13;
	}

	// A NaN is not zero, so the logical not of one is no; a zero is zero, so the
	// logical not of one is yes.
	if (!n) {
		return 14;
	}
	if (!(!z)) {
		return 15;
	}
	return 0;
}
