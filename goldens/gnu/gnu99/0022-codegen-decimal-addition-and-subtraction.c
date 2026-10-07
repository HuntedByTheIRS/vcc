/*
 * Run-time addition, subtraction and negation of the three decimal floating
 * types, at all three widths.
 *
 * A decimal value is an object, not a register, so each of these operations is
 * a call into a routine that reads its operands where they live and writes the
 * result into the object. The bytes below are what gcc 16.2.1 stores at -O0 for
 * the same program, and the point of the case is that this compiler's routine
 * writes the same bytes: the coefficient, the sign, and the exponent the
 * operation's preferred exponent gives the result.
 *
 * The zero a cancellation produces carries the preferred exponent and not a
 * plain one - `1e7df - 1e7df` is a zero at a power of seven - and a sum whose
 * operands are far apart in magnitude is rounded to the format's digit count,
 * which is why the third block of each width is here.
 */
#include <stdio.h>
#include <string.h>

int main(void) {
	unsigned char out[16];
	int i;

	/* _Decimal32 */
	{
		volatile _Decimal32 a = 1.5df;
		volatile _Decimal32 b = 2.25df;
		_Decimal32 sum = a + b;
		_Decimal32 diff = a - b;
		_Decimal32 down = -a;
		memcpy(out, &sum, 4);
		for (i = 0; i < 4; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &diff, 4);
		for (i = 0; i < 4; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &down, 4);
		for (i = 0; i < 4; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal32 p = 1e7df;
		volatile _Decimal32 q = 1e7df;
		_Decimal32 cancelled = p - q;
		memcpy(out, &cancelled, 4);
		for (i = 0; i < 4; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal32 big = 1e30df;
		volatile _Decimal32 small = 1e-30df;
		_Decimal32 rounded = big + small;
		memcpy(out, &rounded, 4);
		for (i = 0; i < 4; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}

	/* _Decimal64 */
	{
		volatile _Decimal64 a = 1.5dd;
		volatile _Decimal64 b = 2.25dd;
		_Decimal64 sum = a + b;
		_Decimal64 diff = a - b;
		_Decimal64 down = -a;
		memcpy(out, &sum, 8);
		for (i = 0; i < 8; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &diff, 8);
		for (i = 0; i < 8; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &down, 8);
		for (i = 0; i < 8; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal64 p = 1e7dd;
		volatile _Decimal64 q = 1e7dd;
		_Decimal64 cancelled = p - q;
		memcpy(out, &cancelled, 8);
		for (i = 0; i < 8; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal64 big = 1e40dd;
		volatile _Decimal64 small = 1e-40dd;
		_Decimal64 rounded = big + small;
		memcpy(out, &rounded, 8);
		for (i = 0; i < 8; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}

	/* _Decimal128 */
	{
		volatile _Decimal128 a = 1.5dl;
		volatile _Decimal128 b = 2.25dl;
		_Decimal128 sum = a + b;
		_Decimal128 diff = a - b;
		_Decimal128 down = -a;
		memcpy(out, &sum, 16);
		for (i = 0; i < 16; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &diff, 16);
		for (i = 0; i < 16; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
		memcpy(out, &down, 16);
		for (i = 0; i < 16; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal128 p = 1e7dl;
		volatile _Decimal128 q = 1e7dl;
		_Decimal128 cancelled = p - q;
		memcpy(out, &cancelled, 16);
		for (i = 0; i < 16; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}
	{
		volatile _Decimal128 big = 1e40dl;
		volatile _Decimal128 small = 1e-40dl;
		_Decimal128 rounded = big + small;
		memcpy(out, &rounded, 16);
		for (i = 0; i < 16; i++) printf("%02x", (unsigned) out[i]);
		printf("\n");
	}

	return 0;
}
