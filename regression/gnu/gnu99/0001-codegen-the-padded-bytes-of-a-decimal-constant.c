// A decimal constant whose power of ten is past what the exponent field holds is
// stored with the coefficient padded with zeros: `1e384dd` is a coefficient of
// 1000000000000000 with a power of 369, because `_Decimal64`'s exponent field
// stops at a biased 767 (768 and up are the marker for the large-coefficient
// form) and 384 with a coefficient of one would be a biased 782.
//
// A coefficient at the boundary where the flat form ends is the other half of
// the shape: `8388608.0df` is two to the twenty-third, which is one past what
// `_Decimal32` carries flat, so it is stored in the large form and is not the
// flat coefficient `800000`.
//
// gcc 16.2.1 stores and converts these as the numbers below say, and this
// compiler stored and converted them differently before the padding and the
// boundary were handled. The case is silent on purpose: for a regression case a
// line of output is itself the regression, so this compares against the values
// gcc wrote and exits non-zero rather than printing them.
#include <string.h>

int main(void) {
	_Decimal32 large = 8388608.0df;
	_Decimal64 padded = 1e384dd;
	unsigned int large_bits = 0;
	unsigned long long padded_bits = 0;
	memcpy(&large_bits, &large, sizeof large_bits);
	memcpy(&padded_bits, &padded, sizeof padded_bits);

	if (large_bits != 0x6ca00000u) {
		return 1;
	}
	if (padded_bits != 0x5fe38d7ea4c68000ULL) {
		return 2;
	}
	if ((double) large != 8388608.0) {
		return 3;
	}

	// 1e384 is past what a double holds, so gcc converts it to an infinity. An
	// infinity is not NaN (it equals itself) and subtracting it from itself gives
	// NaN rather than zero, which is what tells it apart from a finite value.
	double converted = (double) padded;
	if (!(converted == converted)) {
		return 4;
	}
	if (converted - converted == 0.0) {
		return 5;
	}
	return 0;
}
