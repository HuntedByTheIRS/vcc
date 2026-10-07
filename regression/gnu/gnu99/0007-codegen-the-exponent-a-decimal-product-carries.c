// The exponent a decimal product carries.
//
// A decimal product's exponent is the sum of the operands' exponents, and a
// coefficient the format cannot keep is given way: the product is rounded to the
// format's precision, the digits dropped move the exponent up, and when the
// biased exponent would sit above the field's largest the coefficient is padded
// with zeros instead so the field stays in range. A decimal128 coefficient runs
// to thirty-four digits, twice a decimal64's sixteen, and a value at the top of
// the exponent range is the shape that reaches the boundary: 1e6144dl is stored
// with its coefficient padded to thirty-four digits and an exponent of 6111, and
// its product with 1.0 must come back with that same cohort rather than a
// differently scaled one.
//
// Each product is computed at run time, from operands in volatile objects, so no
// constant folding reaches it and the routine the emitter writes is what runs.
// The case prints nothing on purpose: for a regression case a line of output is
// itself the regression, so the products are compared against the words gcc
// 16.2.1 wrote and a mismatch returns non-zero instead of printing anything.
#include <string.h>

int main(void) {
	{
		volatile _Decimal32 a = 1e96df;
		volatile _Decimal32 b = 1.0df;
		_Decimal32 r = a * b;
		unsigned int bits = 0;
		memcpy(&bits, &r, sizeof bits);
		if (bits != 0x5f8f4240u) {
			return 1;
		}
	}
	{
		volatile _Decimal64 a = 1e384dd;
		volatile _Decimal64 b = 1.0dd;
		_Decimal64 r = a * b;
		unsigned long long bits = 0;
		memcpy(&bits, &r, sizeof bits);
		if (bits != 0x5fe38d7ea4c68000ULL) {
			return 2;
		}
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 1.0dl;
		_Decimal128 r = a * b;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &r, sizeof low);
		memcpy(&high, (char *) &r + sizeof low, sizeof high);
		if (low != 0x38c15b0a00000000ULL) {
			return 3;
		}
		if (high != 0x5ffe314dc6448d93ULL) {
			return 4;
		}
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 1e-6176dl;
		_Decimal128 r = a * b;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &r, sizeof low);
		memcpy(&high, (char *) &r + sizeof low, sizeof high);
		if (low != 0x38c15b0a00000000ULL) {
			return 5;
		}
		if (high != 0x2fbe314dc6448d93ULL) {
			return 6;
		}
	}
	{
		volatile _Decimal128 a = 123456789012345678901234567890.1dl;
		volatile _Decimal128 b = 1.0dl;
		_Decimal128 r = a * b;
		unsigned long long low = 0;
		unsigned long long high = 0;
		memcpy(&low, &r, sizeof low);
		memcpy(&high, (char *) &r + sizeof low, sizeof high);
		if (low != 0x5943dd1690a03a12ULL) {
			return 7;
		}
		if (high != 0x303c009bd30a3c64ULL) {
			return 8;
		}
	}
	return 0;
}
