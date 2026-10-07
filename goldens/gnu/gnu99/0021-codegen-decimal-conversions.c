// Every decimal conversion this compiler makes, and the bytes each result is
// stored as. A cast is an expression here: the operand is an object, the result
// is written into an object, and a value the compiler folds and one it cannot are
// both read where they lie, so the two spellings of the same conversion have to
// answer the same bytes.
//
// The values are the ones a conversion has to get right. A decimal to an integer
// discards the fraction and rounds toward zero. An integer to a decimal keeps
// every digit it has that fits and rounds the rest to even. A width conversion
// rounds to the destination's precision and, past what the destination holds,
// answers zero or an infinity. A decimal narrowed to a float rounds into the
// binary format, which is the same rounding and not the same number of digits.
#include <stdio.h>
#include <string.h>

static void hex(const void *p, int n) {
	int i;
	const unsigned char *b = (const unsigned char *) p;
	for (i = 0; i < n; i++) {
		printf("%02x", (unsigned) b[i]);
	}
	printf("\n");
}

int main(void) {
	// A decimal to an integer: the fraction is discarded, toward zero.
	_Decimal32 s32 = 1234567.8df;
	_Decimal64 s64 = 123456789012345.6dd;
	_Decimal128 s128 = 123456789012345678901234567890.1dl;
	_Decimal32 n32 = -2.5df;
	_Decimal64 n64 = -2.5dd;
	_Decimal128 n128 = 2.5dl;
	printf("%d %ld %lu\n", (int) s32, (long) s64, (unsigned long) s128);
	printf("%d %ld %lu\n", (int) n32, (long) n64, (unsigned long) n128);

	// The same conversions of objects the compiler cannot fold, which is the path
	// a program takes for a value it computed.
	volatile _Decimal32 v32 = 1234567.8df;
	volatile _Decimal64 v64 = 123456789012345.6dd;
	volatile _Decimal128 v128 = 123456789012345678901234567890.1dl;
	printf("%d %ld %lu\n", (int) v32, (long) v64, (unsigned long) v128);

	// A decimal to a double or a float rounds into the binary format.
	double d64 = (double) s64;
	float f32 = (float) s32;
	unsigned char out[16];
	memcpy(out, &d64, 8);
	hex(out, 8);
	memcpy(out, &f32, 4);
	hex(out, 4);
	printf("%.17g %.9g\n", (double) v64, (double) v128);

	// An integer to a decimal: exact when the destination holds every digit.
	int small = -1234567;
	long lmid = 123456789012345L;
	unsigned long huge = 18446744073709551615UL;
	_Decimal32 di = (_Decimal32) small;
	_Decimal64 dlon = (_Decimal64) lmid;
	_Decimal128 du = (_Decimal128) huge;
	hex(&di, 4);
	hex(&dlon, 8);
	hex(&du, 16);
	printf("%d %ld\n", (int) di, (long) dlon);

	// And rounded to even when it does not: 2147483647 is ten digits and a
	// _Decimal32 holds seven, so the last three are dropped and the seventh
	// rounds up; 2 to the sixty-third minus one is nineteen digits and a
	// _Decimal64 holds sixteen.
	int ten = 2147483647;
	long nineteen = 9223372036854775807L;
	_Decimal32 rounded = (_Decimal32) ten;
	_Decimal64 rounded64 = (_Decimal64) nineteen;
	hex(&rounded, 4);
	hex(&rounded64, 8);

	// The same conversions of objects the compiler cannot fold.
	volatile int vsmall = -1234567;
	volatile unsigned long vhuge = 18446744073709551615UL;
	_Decimal64 fromsmall = (_Decimal64) vsmall;
	_Decimal128 fromhuge = (_Decimal128) vhuge;
	hex(&fromsmall, 8);
	hex(&fromhuge, 16);

	// A double or a float to a decimal. A binary value is a significand times a
	// power of two and a decimal one is a coefficient times a power of ten, so the
	// two meet at ten: the coefficient is the significand times a power of five.
	// The destination holds its own count of digits, so a long coefficient is
	// rounded to even there while a short one stands as it is.
	double bhalf = 1.5;
	double btenth = 0.1;
	double bbig = 1e30;
	double bsmall64 = 1e-320;
	float fhalf = 1.5f;
	float ftenth = 0.1f;
	float fmax = 3.4028235e38f;
	float ftiny = 1e-45f;
	_Decimal32 bh32 = (_Decimal32) bhalf;
	_Decimal64 bh64 = (_Decimal64) bhalf;
	_Decimal128 bh128 = (_Decimal128) bhalf;
	_Decimal32 bt32 = (_Decimal32) btenth;
	_Decimal64 bt64 = (_Decimal64) btenth;
	_Decimal128 bt128 = (_Decimal128) btenth;
	_Decimal64 bs64 = (_Decimal64) bbig;
	_Decimal128 bs128 = (_Decimal128) bbig;
	_Decimal64 bu64 = (_Decimal64) bsmall64;
	_Decimal32 fh32 = (_Decimal32) fhalf;
	_Decimal64 fh64 = (_Decimal64) fhalf;
	_Decimal128 fh128 = (_Decimal128) fhalf;
	_Decimal32 ft32 = (_Decimal32) ftenth;
	_Decimal64 ft64 = (_Decimal64) ftenth;
	_Decimal128 ft128 = (_Decimal128) ftenth;
	_Decimal64 fm64 = (_Decimal64) fmax;
	_Decimal128 fm128 = (_Decimal128) fmax;
	_Decimal64 fu64 = (_Decimal64) ftiny;
	hex(&bh32, 4);
	hex(&bh64, 8);
	hex(&bh128, 16);
	hex(&bt32, 4);
	hex(&bt64, 8);
	hex(&bt128, 16);
	hex(&bs64, 8);
	hex(&bs128, 16);
	hex(&bu64, 8);
	hex(&fh32, 4);
	hex(&fh64, 8);
	hex(&fh128, 16);
	hex(&ft32, 4);
	hex(&ft64, 8);
	hex(&ft128, 16);
	hex(&fm64, 8);
	hex(&fm128, 16);
	hex(&fu64, 8);

	// And the same conversions of objects the compiler cannot fold.
	volatile double vbhalf = 1.5;
	volatile float vftenth = 0.1f;
	_Decimal32 vh32 = (_Decimal32) vbhalf;
	_Decimal128 vh128 = (_Decimal128) vbhalf;
	_Decimal64 vf64 = (_Decimal64) vftenth;
	_Decimal128 vf128 = (_Decimal128) vftenth;
	hex(&vh32, 4);
	hex(&vh128, 16);
	hex(&vf64, 8);
	hex(&vf128, 16);

	// A decimal of one width converted to another: every pair, both ways.
	_Decimal64 a32 = (_Decimal64) s32;
	_Decimal128 b32 = (_Decimal128) s32;
	_Decimal32 a64 = (_Decimal32) s64;
	_Decimal128 b64 = (_Decimal128) s64;
	_Decimal32 a128 = (_Decimal32) s128;
	_Decimal64 b128 = (_Decimal64) s128;
	hex(&a32, 8);
	hex(&b32, 16);
	hex(&a64, 4);
	hex(&b64, 16);
	hex(&a128, 4);
	hex(&b128, 8);

	// One value whose digits do not all fit the destination, so it rounds.
	_Decimal64 eight = 1234567.8dd;
	_Decimal128 thirty = 1234567.8dl;
	_Decimal32 north = (_Decimal32) eight;
	_Decimal64 up = (_Decimal64) thirty;
	hex(&north, 4);
	hex(&up, 8);

	// One below what the destination holds is a zero there.
	_Decimal64 tiny = 1e-398dd;
	_Decimal128 tinier = 1e-6176dl;
	_Decimal32 under = (_Decimal32) tiny;
	_Decimal64 under64 = (_Decimal64) tinier;
	hex(&under, 4);
	hex(&under64, 8);

	// Negating a decimal is a flip of the sign bit.
	_Decimal32 negated32 = -s32;
	_Decimal128 negated128 = -s128;
	_Decimal64 negated64 = -tiny;
	hex(&negated32, 4);
	hex(&negated128, 16);
	hex(&negated64, 8);

	// And a decimal is not zero unless its coefficient is, whatever its sign and
	// whatever its exponent.
	_Decimal64 zero = 0.0dd;
	_Decimal64 negzero = -zero;
	printf("%d %d %d %d\n", !s32, !zero, !negzero, !s128);
	return 0;
}
