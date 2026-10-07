/*
 * The exponent a decimal sum carries is part of the observable result.
 *
 * Three-operand decimal addition and subtraction carry the operation's
 * preferred exponent, which is the smaller of the two operands' exponents, and
 * gcc 16.2.1's run-time routines preserve it. A cancellation is where the rule
 * shows most plainly: `1e7df - 1e7df` is not a plain zero but a zero at a power
 * of seven, and `0.0dd - 0.0dd` is a zero at a power of minus one. A nonzero
 * sum carries it too - `1.5dd + 2.25dd` is 3.75, a coefficient of 375 at minus
 * two - and a sum whose operands are far apart in magnitude carries it through
 * the rounding.
 *
 * A regression case is silent on purpose: a line of output is itself the
 * regression, so this compares against the bytes gcc wrote and exits non-zero
 * rather than printing them.
 */
#include <string.h>

int main(void) {
	/* A cancellation zero carries the preferred exponent. */
	{
		volatile _Decimal32 p = 1e7df;
		volatile _Decimal32 q = 1e7df;
		_Decimal32 z = p - q;
		unsigned int bits = 0;
		memcpy(&bits, &z, sizeof bits);
		if (bits != 0x36000000u) {
			return 1;
		}
	}
	{
		volatile _Decimal32 p = 0.0df;
		volatile _Decimal32 q = 0.0df;
		_Decimal32 z = p - q;
		unsigned int bits = 0;
		memcpy(&bits, &z, sizeof bits);
		if (bits != 0x32000000u) {
			return 2;
		}
	}
	{
		volatile _Decimal64 p = 1e7dd;
		volatile _Decimal64 q = 1e7dd;
		_Decimal64 z = p - q;
		unsigned long long bits = 0;
		memcpy(&bits, &z, sizeof bits);
		if (bits != 0x32a0000000000000ULL) {
			return 3;
		}
	}
	{
		volatile _Decimal128 p = 1e7dl;
		volatile _Decimal128 q = 1e7dl;
		_Decimal128 z = p - q;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &z, sizeof low);
		memcpy(&high, ((unsigned char *) &z) + 8, sizeof high);
		if (low != 0ULL || high != 0x304e000000000000ULL) {
			return 4;
		}
	}

	/* A nonzero sum carries the preferred exponent too. */
	{
		volatile _Decimal32 a = 1.5df;
		volatile _Decimal32 b = 2.25df;
		_Decimal32 s = a + b;
		unsigned int bits = 0;
		memcpy(&bits, &s, sizeof bits);
		if (bits != 0x31800177u) {
			return 5;
		}
	}
	{
		volatile _Decimal64 a = 1.5dd;
		volatile _Decimal64 b = 2.25dd;
		_Decimal64 s = a + b;
		unsigned long long bits = 0;
		memcpy(&bits, &s, sizeof bits);
		if (bits != 0x3180000000000177ULL) {
			return 6;
		}
	}
	{
		volatile _Decimal128 a = 1.5dl;
		volatile _Decimal128 b = 2.25dl;
		_Decimal128 s = a + b;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &s, sizeof low);
		memcpy(&high, ((unsigned char *) &s) + 8, sizeof high);
		if (low != 0x177ULL || high != 0x303c000000000000ULL) {
			return 7;
		}
	}

	return 0;
}
