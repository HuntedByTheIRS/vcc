// Run-time multiplication and division of the decimal floating types.
//
// No register holds a decimal value, so a product or a quotient of two decimal
// objects is a routine the emitter writes: the operands sit in volatile objects
// and the result is written into one. The routine has to make the same bytes gcc
// makes, because gcc reaches libgcc's __bid_ routines for the same operation and
// those bytes are the specification.
//
// Nothing here prints a decimal value directly. printf has no conversion for one,
// so what a program can read is the result's bytes: each line below names the
// operation and prints the bytes of the object the routine wrote.
//
// The cases are the shapes the routine has to get right: ordinary values, a
// coefficient the format cannot keep, a power of ten at the top of the exponent
// field, an overflow to infinity, an underflow to zero, and a decimal128
// coefficient of thirty-four digits, which is longer than any decimal64
// coefficient and is the one a frame's scratch has to hold whole.
#include <stdio.h>
#include <string.h>

static void show32(const char *name, const void *p) {
	unsigned int bits = 0;
	memcpy(&bits, p, sizeof bits);
	printf("%s %08x\n", name, bits);
}

static void show64(const char *name, const void *p) {
	unsigned long long bits = 0;
	memcpy(&bits, p, sizeof bits);
	printf("%s %016llx\n", name, bits);
}

static void show128(const char *name, const void *p) {
	unsigned long long low = 0;
	unsigned long long high = 0;
	memcpy(&low, p, sizeof low);
	memcpy(&high, (const char *) p + sizeof low, sizeof high);
	printf("%s %016llx%016llx\n", name, high, low);
}

int main(void) {
	{
		volatile _Decimal32 a = 1.5df;
		volatile _Decimal32 b = -2.5df;
		_Decimal32 r = a * b;
		show32("d32 1.5 * -2.5", &r);
	}
	{
		volatile _Decimal32 a = 0.1df;
		volatile _Decimal32 b = 0.1df;
		_Decimal32 r = a * b;
		show32("d32 0.1 * 0.1", &r);
	}
	{
		volatile _Decimal32 a = 1e96df;
		volatile _Decimal32 b = 1e96df;
		_Decimal32 r = a * b;
		show32("d32 1e96 * 1e96", &r);
	}
	{
		volatile _Decimal32 a = 1e-101df;
		volatile _Decimal32 b = 1e-7df;
		_Decimal32 r = a * b;
		show32("d32 1e-101 * 1e-7", &r);
	}
	{
		volatile _Decimal32 a = 1234567.8df;
		volatile _Decimal32 b = 1e-7df;
		_Decimal32 r = a / b;
		show32("d32 1234567.8 / 1e-7", &r);
	}
	{
		volatile _Decimal64 a = 123456789012345.6dd;
		volatile _Decimal64 b = -2.5dd;
		_Decimal64 r = a * b;
		show64("d64 123456789012345.6 * -2.5", &r);
	}
	{
		volatile _Decimal64 a = 9999999999999999.0dd;
		volatile _Decimal64 b = 1.0dd;
		_Decimal64 r = a * b;
		show64("d64 9999999999999999.0 * 1.0", &r);
	}
	{
		volatile _Decimal64 a = 1e384dd;
		volatile _Decimal64 b = 1e384dd;
		_Decimal64 r = a * b;
		show64("d64 1e384 * 1e384", &r);
	}
	{
		volatile _Decimal64 a = 1e384dd;
		volatile _Decimal64 b = 1.5dd;
		_Decimal64 r = a / b;
		show64("d64 1e384 / 1.5", &r);
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 1.0dl;
		_Decimal128 r = a * b;
		show128("d128 1e6144 * 1.0", &r);
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 1.0dl;
		_Decimal128 r = a / b;
		show128("d128 1e6144 / 1.0", &r);
	}
	{
		volatile _Decimal128 a = 123456789012345678901234567890.1dl;
		volatile _Decimal128 b = 1.0dl;
		_Decimal128 r = a / b;
		show128("d128 31 digits / 1.0", &r);
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 1e6144dl;
		_Decimal128 r = a / b;
		show128("d128 1e6144 / 1e6144", &r);
	}
	{
		volatile _Decimal128 a = 1e6144dl;
		volatile _Decimal128 b = 0.1dl;
		_Decimal128 r = a / b;
		show128("d128 1e6144 / 0.1", &r);
	}
	return 0;
}
