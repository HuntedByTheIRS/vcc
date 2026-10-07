// The decimal floating types: the three widths, what they are sized at, what
// they convert to, and the bytes each value is stored as. Nothing here prints a
// decimal value directly, because printf has no conversion for one — both gcc's
// manual and the measurement for this work say a `%f` with a decimal is a
// warning and the wrong bytes — so what a program can read is the value's bytes
// and its double.
//
// The values are the ones the encoding has to get right: the plain ones, a
// coefficient at the boundary where the format stops keeping it flat
// (8388608.0df is two to the twenty-third), a power of ten past what the
// exponent field can hold, which gcc stores with the coefficient padded with
// zeros, and a thirty-four digit decimal128.
#include <stdio.h>
#include <string.h>

int main(void) {
	_Decimal32 a = 1.5df;
	_Decimal64 b = 2.5dd;
	_Decimal128 c = 3.5dl;

	printf("%zu %zu %zu\n", sizeof(_Decimal32), sizeof(_Decimal64), sizeof(_Decimal128));
	printf("%.17g %.17g %.17g\n", (double) a, (double) b, (double) c);

	_Decimal32 large = 8388608.0df;
	_Decimal64 padded = 1e384dd;
	_Decimal128 wide = 1234567890123456789012345678901234.0dl;

	unsigned int abits = 0;
	unsigned int big = 0;
	unsigned long long bbits = 0;
	unsigned long long padded_bits = 0;
	unsigned long long clow = 0;
	unsigned long long chigh = 0;
	unsigned long long wide_low = 0;
	unsigned long long wide_high = 0;
	memcpy(&abits, &a, sizeof abits);
	memcpy(&big, &large, sizeof big);
	memcpy(&bbits, &b, sizeof bbits);
	memcpy(&padded_bits, &padded, sizeof padded_bits);
	memcpy(&clow, &c, sizeof clow);
	memcpy(&chigh, (char *) &c + sizeof clow, sizeof chigh);
	memcpy(&wide_low, &wide, sizeof wide_low);
	memcpy(&wide_high, (char *) &wide + sizeof wide_low, sizeof wide_high);

	printf("%08x %08x %016llx %016llx %016llx%016llx\n", abits, big, bbits, padded_bits, chigh,
	       clow);
	printf("%016llx%016llx\n", wide_high, wide_low);
	printf("%.17g %.17g %.17g\n", (double) large, (double) padded, (double) wide);

	// The conversion of a value the compiler cannot fold, and one whose double is
	// not the decimal that was written: a tenth has no exact double. This is the
	// path a program takes when it converts a value it computed, and it has to
	// round the same way the folded one does.
	volatile _Decimal64 tenth = 0.1dd;
	volatile _Decimal128 many = 1e-320dl;
	double converted = (double) tenth;
	unsigned long long converted_bits = 0;
	memcpy(&converted_bits, &converted, sizeof converted_bits);
	printf("%.17g %.17g\n", converted, (double) many);
	printf("%016llx\n", converted_bits);
	return 0;
}
