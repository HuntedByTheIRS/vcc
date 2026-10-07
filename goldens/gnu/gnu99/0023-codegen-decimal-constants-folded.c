// Constant decimal arithmetic, folded the way gcc's front end folds it: an
// expression whose operands are decimal constants is evaluated while the program
// is compiled, and the value's bytes are the ones gcc writes into the object.
//
// What this case is for is the exponent a folded result carries, which is not
// always the exponent a run-time routine would produce. `1.0dd / 2.0dd` is the
// coefficient 5 at a power of minus one, not the coefficient 5000000000000000
// that scaling the dividend leaves; `100.0dd / 2.0dd` is the coefficient 50 at a
// power of zero because that is the exponent the division prefers; a zero
// carries the exponent the operation prefers too, so `1e7df - 1e7df` is a zero
// at a power of seven and not the plain zero. An operand is the value as it is
// stored, which is why `1e96df * 1e-7df` keeps the padded coefficient 1000000 at
// a power of 83 rather than the coefficient 1 at a power of 89.
//
// Nothing here prints a decimal value directly, because printf has no conversion
// for one, so each value is printed as its bytes, least significant first, which
// is the order they sit in memory.
#include <stdio.h>
#include <string.h>

static void show(const void *p, unsigned long n) {
	const unsigned char *b = p;
	unsigned long i;
	for (i = 0; i < n; i++) {
		printf("%02x", (unsigned int) b[i]);
	}
	printf("\n");
}

#define ROW(name, width, value)         \
	do {                            \
		width v = (value);      \
		printf("%-12s ", name); \
		show(&v, sizeof v);     \
	} while (0)

int main(void) {
	ROW("df add", _Decimal32, 1.0df + 2.0df);
	ROW("df sub", _Decimal32, 1.0df - 2.0df);
	ROW("df mul", _Decimal32, 1.0df * 2.0df);
	ROW("df div", _Decimal32, 1.0df / 2.0df);
	ROW("df div2", _Decimal32, 100.0df / 2.0df);
	ROW("df padded", _Decimal32, 1e96df * 1e-7df);
	ROW("df zero", _Decimal32, 1e7df - 1e7df);
	ROW("df under", _Decimal32, 1e-101df * 1e-7df);
	ROW("df over", _Decimal32, 1e96df * 1e96df);
	ROW("df nan", _Decimal32, 0.0df / 0.0df);
	ROW("df inf", _Decimal32, 1.0df / 0.0df);

	ROW("dd add", _Decimal64, 1.0dd + 2.0dd);
	ROW("dd div", _Decimal64, 1.0dd / 2.0dd);
	ROW("dd div2", _Decimal64, 100.0dd / 2.0dd);
	ROW("dd div3", _Decimal64, 1e10dd / 2e0dd);
	ROW("dd repeat", _Decimal64, 1.0dd / 3.0dd);
	ROW("dd zero", _Decimal64, 1e-398dd - 1e-398dd);
	ROW("dd under", _Decimal64, 1e-398dd * 1e-398dd);
	ROW("dd over", _Decimal64, 1e384dd * 1e384dd);
	ROW("dd padded", _Decimal64, 1e384dd * 1e-320dd);

	ROW("dl add", _Decimal128, 1.0dl + 2.0dl);
	ROW("dl div", _Decimal128, 1.0dl / 2.0dl);
	ROW("dl mul", _Decimal128, 1e30dl * 1e30dl);
	ROW("dl over", _Decimal128, 1e6144dl * 1e6144dl);
	ROW("dl under", _Decimal128, 1e-6176dl * 1e-6176dl);
	ROW("dl zero", _Decimal128, 1e-6176dl - 1e-6176dl);

	// The six comparisons, which fold to the int C gives them.
	printf("cmp %d %d %d %d %d %d\n", 1.0dd == 1.0dd, 1.0dd != 1.0dd, 1.0dd < 2.0dd,
	       2.0dd <= 2.0dd, 3.0dd > 2.0dd, 2.0dd >= 2.0dd);
	printf("cmp2 %d %d %d %d %d %d\n", 1.0dd == 2.0dd, 1.0dd != 2.0dd, 2.0dd < 1.0dd,
	       1.0dd <= 0.5dd, 1.0dd > 2.0dd, 1.0dd >= 2.0dd);
	return 0;
}
