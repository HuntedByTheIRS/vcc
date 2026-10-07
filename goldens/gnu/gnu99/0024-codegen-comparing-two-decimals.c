// C99 6.5.8 and 6.5.9 on the decimal floating types: the six relational and
// equality operators, and the logical not, for each of the three widths. A
// comparison of two of these is not a machine compare at any width - the values
// are BID-encoded objects - so it is a routine, and this is the program whose
// output says the routine orders them the way gcc 16.2.1 does.
//
// The cases are the ones that are not the plain order. Two equal values written
// with different exponents have different bytes and have to compare equal; a zero
// carries an exponent and a sign, so two zeros with different bytes are still
// equal, and a zero is never ordered against another zero. An infinity is greater
// than every finite value and equal to an infinity of its own sign, and a NaN is
// unordered: it is not equal to itself, not equal to anything, and not less or
// greater, but it is not equal, so `!=` is the one operator a NaN answers.
//
// The NaN and the odd zero are written into their objects byte by byte, because a
// decimal value cannot be computed into one yet and the bytes are the operand
// either way: gcc and this compiler are read the same object. The NaN is the quiet
// one, the five bits below the sign all set with the quiet bit above the payload.
#include <stdio.h>
#include <string.h>

int main(void) {
	// Two equal values written with a different exponent and a different number
	// of digits are equal, and neither is less or greater than the other.
	volatile _Decimal32 a32 = 1.5df;
	volatile _Decimal32 b32 = 15e-1df;
	volatile _Decimal32 c32 = 1.50df;
	printf("%d %d %d %d %d %d\n", a32 == b32, a32 != b32, a32 < b32, a32 <= b32, a32 > b32,
		a32 >= b32);
	printf("%d %d\n", a32 == c32, a32 != c32);

	volatile _Decimal64 a64 = 1.5dd;
	volatile _Decimal64 b64 = 15e-1dd;
	volatile _Decimal64 c64 = 1.50dd;
	printf("%d %d %d %d %d %d\n", a64 == b64, a64 != b64, a64 < b64, a64 <= b64, a64 > b64,
		a64 >= b64);
	printf("%d %d\n", a64 == c64, a64 != c64);

	volatile _Decimal128 a128 = 1.5dl;
	volatile _Decimal128 b128 = 15e-1dl;
	volatile _Decimal128 c128 = 1.50dl;
	printf("%d %d %d %d %d %d\n", a128 == b128, a128 != b128, a128 < b128, a128 <= b128,
		a128 > b128, a128 >= b128);
	printf("%d %d\n", a128 == c128, a128 != c128);

	// A zero carries a power of ten, so a zero written with another exponent has
	// other bytes and is still equal to the plain one. The two byte patterns are
	// printed to show they differ.
	volatile _Decimal32 z32 = 0.0df;
	volatile _Decimal32 z32e = 0e30df;
	volatile _Decimal64 z64 = 0.0dd;
	volatile _Decimal64 z64e = 0e300dd;
	volatile _Decimal128 z128 = 0.0dl;
	volatile _Decimal128 z128e = 0e300dl;
	unsigned int z32a = 0;
	unsigned int z32b = 0;
	unsigned long long z64a = 0;
	unsigned long long z64b = 0;
	unsigned long long z128lo = 0;
	unsigned long long z128hi = 0;
	unsigned long long z128lo2 = 0;
	unsigned long long z128hi2 = 0;
	memcpy(&z32a, (const void *) &z32, sizeof z32a);
	memcpy(&z32b, (const void *) &z32e, sizeof z32b);
	memcpy(&z64a, (const void *) &z64, sizeof z64a);
	memcpy(&z64b, (const void *) &z64e, sizeof z64b);
	memcpy(&z128lo, (const void *) &z128, sizeof z128lo);
	memcpy(&z128hi, (const char *) &z128 + sizeof z128lo, sizeof z128hi);
	memcpy(&z128lo2, (const void *) &z128e, sizeof z128lo2);
	memcpy(&z128hi2, (const char *) &z128e + sizeof z128lo2, sizeof z128hi2);
	printf("%08x %08x %016llx %016llx %016llx%016llx %016llx%016llx\n", z32a, z32b, z64a,
		z64b, z128hi, z128lo, z128hi2, z128lo2);
	printf("%d %d %d\n", z32 == z32e, z64 == z64e, z128 == z128e);
	printf("%d %d %d\n", z32 >= z32e, z64 >= z64e, z128 >= z128e);

	// An infinity is past the format's range, so a constant beyond it is stored as
	// one. It is greater than every finite value, less than none, and equal to an
	// infinity of its own sign.
	volatile _Decimal32 inf32 = 1e100df;
	volatile _Decimal64 inf64 = 1e400dd;
	volatile _Decimal128 inf128 = 1e6200dl;
	volatile _Decimal64 neg64 = -1e400dd;
	printf("%d %d %d %d\n", inf32 > a32, inf64 > a64, inf128 > a128, inf64 == inf64);
	printf("%d %d %d %d\n", neg64 < a64, neg64 < inf64, inf64 > neg64, neg64 != inf64);

	// The NaN bytes: the five marker bits below the sign all set, the quiet bit
	// above the payload clear in the payload and set as the quiet marker. The
	// object is a plain one written through its address, so the operand is the
	// same bytes for both compilers.
	volatile _Decimal32 nan32;
	volatile _Decimal64 nan64;
	volatile _Decimal128 nan128;
	unsigned char nan32_bytes[4] = { 0, 0, 0, 0x7c };
	unsigned char nan64_bytes[8] = { 0, 0, 0, 0, 0, 0, 0, 0x7c };
	unsigned char nan128_bytes[16] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x7c };
	memcpy((void *) &nan32, nan32_bytes, sizeof nan32_bytes);
	memcpy((void *) &nan64, nan64_bytes, sizeof nan64_bytes);
	memcpy((void *) &nan128, nan128_bytes, sizeof nan128_bytes);
	printf("%d %d %d %d\n", nan32 == nan32, nan64 == nan64, nan128 == nan128, nan32 != nan32);
	printf("%d %d %d %d\n", nan64 != nan64, nan128 != nan128, nan32 < a32, nan64 < a64);
	printf("%d %d %d %d\n", nan128 < a128, nan32 <= a32, nan64 >= a64, nan128 >= a128);
	printf("%d %d %d %d\n", nan32 == a32, nan64 == a64, nan128 == a128, nan64 == inf64);

	// The logical not asks whether the value is zero, and a NaN is not zero.
	printf("%d %d %d %d %d %d\n", !a64, !z64, !inf64, !nan64, !neg64, !z64e);
	return 0;
}
