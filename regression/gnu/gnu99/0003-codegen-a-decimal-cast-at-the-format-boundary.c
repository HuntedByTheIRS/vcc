// A decimal cast at the boundary of a format: the exponent a zero keeps when it
// is widened, the coefficient a value at the end of the flat form is stored with,
// and the value past what the destination holds.
//
// Each of these was wrong here before the conversions existed. Widening a zero
// dropped its exponent and wrote a flat zero, so `_Decimal32 0.0df` widened was
// all zeroes rather than a coefficient of zero under the exponent the value was
// written with. Widening a value that fits the flat form wrote the
// large-coefficient form instead, so `_Decimal32 1.5df` widened was not the
// fifteen under a power of minus one. Narrowing a value past what the destination
// holds wrote nothing at all, because a zero was stored where the exponent was
// lost. Negating a `_Decimal128` inverted a byte past the end of the object,
// because the copy had already advanced the pointer, so the sign never flipped
// and eight bytes beyond the object were written.
//
// gcc 16.2.1 stores and converts these as the values below say. The case is
// silent on purpose: for a regression case a line of output is itself the
// regression, so this compares against the bytes gcc wrote and exits non-zero
// rather than printing them.
#include <stdio.h>
#include <string.h>

int main(void) {
	_Decimal32 zero32 = 0.0df;
	_Decimal32 one32 = 1.5df;
	_Decimal32 max32 = 1e96df;
	_Decimal32 tiny32 = 1e-101df;
	_Decimal64 one64 = 1.5dd;
	_Decimal64 tiny64 = 1e-398dd;
	_Decimal128 one128 = 1.5dl;
	_Decimal128 wide128 = 1e-6176dl;

	_Decimal64 w1 = (_Decimal64) zero32;
	_Decimal64 w2 = (_Decimal64) one32;
	_Decimal64 w3 = (_Decimal64) max32;
	_Decimal64 w4 = (_Decimal64) tiny32;
	_Decimal32 n1 = (_Decimal32) one64;
	_Decimal32 n2 = (_Decimal32) tiny64;
	_Decimal64 n3 = (_Decimal64) wide128;
	_Decimal128 w5 = (_Decimal128) zero32;
	_Decimal128 w6 = (_Decimal128) one128;
	_Decimal128 neg = -one128;

	unsigned int one32_bits = 0;
	unsigned int n1_bits = 0;
	unsigned int n2_bits = 0;
	unsigned long long w1_bits = 0;
	unsigned long long w2_bits = 0;
	unsigned long long w3_bits = 0;
	unsigned long long w4_bits = 0;
	unsigned long long n3_bits = 0;
	unsigned long long w5_low = 0;
	unsigned long long w5_high = 0;
	unsigned long long w6_high = 0;
	unsigned long long neg_high = 0;
	unsigned long long neg_low = 0;
	unsigned int zero32_bits = 0;
	memcpy(&zero32_bits, &zero32, sizeof zero32_bits);
	memcpy(&one32_bits, &one32, sizeof one32_bits);
	memcpy(&n1_bits, &n1, sizeof n1_bits);
	memcpy(&n2_bits, &n2, sizeof n2_bits);
	memcpy(&w1_bits, &w1, sizeof w1_bits);
	memcpy(&w2_bits, &w2, sizeof w2_bits);
	memcpy(&w3_bits, &w3, sizeof w3_bits);
	memcpy(&w4_bits, &w4, sizeof w4_bits);
	memcpy(&n3_bits, &n3, sizeof n3_bits);
	memcpy(&w5_low, &w5, sizeof w5_low);
	memcpy(&w5_high, (char *) &w5 + sizeof w5_low, sizeof w5_high);
	memcpy(&w6_high, (char *) &w6 + sizeof w5_low, sizeof w6_high);
	memcpy(&neg_low, &neg, sizeof neg_low);
	memcpy(&neg_high, (char *) &neg + sizeof neg_low, sizeof neg_high);

	// The zero a widened decimal carries is the zero the source was written as:
	// `0.0df` is a coefficient of zero under a power of minus one, and widening
	// keeps that power.
	if (zero32_bits != 0x32000000u || w1_bits != 0x31a0000000000000ULL) {
		fprintf(stderr, "a widened zero lost its exponent\n");
		return 1;
	}
	// A value that fits the flat form uses it: 1.5 is fifteen under a power of
	// minus one, in the flat form and not the large one.
	if (one32_bits != 0x3200000fu) {
		fprintf(stderr, "1.5df is not stored flat\n");
		return 2;
	}
	if (w2_bits != 0x31a000000000000fULL) {
		fprintf(stderr, "a widened 1.5 is not the flat fifteen\n");
		return 3;
	}
	// The same at the end of the flat form: 1e96 has seven digits of coefficient
	// with the last of them padded, and widening keeps the exponent.
	if (w3_bits != 0x3d000000000f4240ULL) {
		fprintf(stderr, "a widened 1e96 is not the padded coefficient\n");
		return 4;
	}
	// A value whose coefficient is one and whose power is the smallest the wider
	// format carries is still widened exactly.
	if (w4_bits != 0x2520000000000001ULL) {
		fprintf(stderr, "a widened 1e-101 is not exact\n");
		return 5;
	}
	// Narrowed, a value whose digits all fit is unchanged.
	if (n1_bits != 0x3200000fu) {
		fprintf(stderr, "a narrowed 1.5 changed\n");
		return 6;
	}
	// And one below what the narrower format holds is a zero there.
	if (n2_bits != 0x00000000u || n3_bits != 0x0000000000000000ULL) {
		fprintf(stderr, "an underflow did not answer zero\n");
		return 7;
	}
	// The wider format's own zero carries the source's exponent, which is a
	// biased 6176 rather than the flat zero.
	if (w5_low != 0 || w5_high != 0x303e000000000000ULL) {
		fprintf(stderr, "a 128-bit widened zero lost its exponent\n");
		return 8;
	}
	// A value that is exactly what the wider format holds is widened unchanged.
	if (w6_high != 0x303e000000000000ULL || neg_high != 0xb03e000000000000ULL ||
	    neg_low != 0x000000000000000fULL) {
		fprintf(stderr, "a 1.5dl widened or negated wrongly\n");
		return 9;
	}
	return 0;
}
