// The exponent a folded decimal constant carries, which is the part of constant
// decimal arithmetic that is easy to get wrong: gcc's front end gives a result
// the exponent its own algorithm prefers, and that is not always the exponent a
// run-time routine would leave.
//
// `1.0df / 2.0df` is the coefficient 5 at a power of minus one, not the
// coefficient 5000000000000000 the scaling of the dividend leaves; `1e10dd /
// 2e0dd` is the coefficient 5 at a power of nine; `1e96df * 1e-7df` keeps the
// padded coefficient 1000000 at a power of 83 because `1e96df` is stored as that
// coefficient; a zero result carries the exponent the operation prefers, so
// `1e7df - 1e7df` is a zero at a power of seven and `0.0dd / 0.0dd` is the NaN
// at all zero bytes but the marker. A fold that computed the right *value* with
// the wrong exponent, or that emitted a call where gcc emits a constant, would
// pass a value test and fail here.
//
// The case is silent on purpose: for a regression case a line of output is the
// regression, so it compares against the bytes gcc 16.2.1 writes and exits
// non-zero rather than printing them.
#include <string.h>

int main(void) {
	// A quotient that is exact is expressed with the exponent the division
	// prefers: 0.5 is the coefficient 5 at minus one, not the wide coefficient
	// the run-time division scales to.
	{
		_Decimal32 v = 1.0df / 2.0df;
		unsigned int bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x32000005u) {
			return 1;
		}
	}
	// A zero result carries the smaller of the two operands' exponents, so a
	// cancellation of two values at a power of seven is a zero at a power of
	// seven and not the plain zero.
	{
		_Decimal32 v = 1e7df - 1e7df;
		unsigned int bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x36000000u) {
			return 2;
		}
	}
	// An operand is the value as it is stored, so 1e96df is the padded
	// coefficient 1000000 at a power of 90 and the product keeps that shape.
	{
		_Decimal32 v = 1e96df * 1e-7df;
		unsigned int bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x5c0f4240u) {
			return 3;
		}
	}
	// The same exact-quotient rule at the wider width, where a run-time
	// division would leave fifteen trailing zeros in the coefficient.
	{
		_Decimal64 v = 1.0dd / 2.0dd;
		unsigned long long bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x31a0000000000005ULL) {
			return 4;
		}
	}
	// The exponent of an exact quotient is the difference of the operands'
	// powers, reduced only as far as the coefficient needs to be an integer.
	{
		_Decimal64 v = 100.0dd / 2.0dd;
		unsigned long long bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x31c0000000000032ULL) {
			return 5;
		}
	}
	{
		_Decimal64 v = 1e10dd / 2e0dd;
		unsigned long long bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x32e0000000000005ULL) {
			return 6;
		}
	}
	// Zero divided by zero is the NaN whose quiet bit is clear, measured on gcc
	// 16.2.1 at all three widths.
	{
		_Decimal64 v = 0.0dd / 0.0dd;
		unsigned long long bits = 0;
		memcpy(&bits, &v, sizeof bits);
		if (bits != 0x7c00000000000000ULL) {
			return 7;
		}
	}
	// The 128-bit width, whose value is two words in memory.
	{
		_Decimal128 v = 1.0dl / 2.0dl;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &v, sizeof low);
		memcpy(&high, (char *) &v + sizeof low, sizeof high);
		if (low != 0x0000000000000005ULL || high != 0x303e000000000000ULL) {
			return 8;
		}
	}
	{
		_Decimal128 v = 1e6144dl * 1e-6176dl;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &v, sizeof low);
		memcpy(&high, (char *) &v + sizeof low, sizeof high);
		if (low != 0x38c15b0a00000000ULL || high != 0x2fbe314dc6448d93ULL) {
			return 9;
		}
	}
	return 0;
}
