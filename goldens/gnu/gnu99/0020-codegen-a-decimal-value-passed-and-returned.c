// A decimal value travelling the four ways a value travels: read out of an
// object for its value, handed to a function and given back, carried inside a
// struct passed and returned by value, and passed through a variadic call.
//
// The readings are one per shape of object a value can sit in: a variable, an
// element of an array, a member of a struct, and the target of a pointer. The
// calls carry three decimals at once so more than one floating-point argument
// register is exercised, and a _Decimal128 takes two of them.
//
// Measured on gcc 16.2.1: every width is passed and given back in xmm0, a
// _Decimal128 across the xmm0:xmm1 pair, and a variadic call passes the raw
// payload with no promotion, so what a double read out of the variadic argument
// area holds is the value's own bytes.
#include <stdarg.h>
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

// A variadic call passes a decimal with no promotion, so the raw payload is in
// the floating-point argument area and a double read from there is its bytes.
static void payload(int n, ...) {
	va_list ap;
	(void) n;
	va_start(ap, n);
	double raw = va_arg(ap, double);
	unsigned long long bits = 0;
	memcpy(&bits, &raw, sizeof bits);
	printf("%016llx\n", bits);
	va_end(ap);
}

static _Decimal64 three(_Decimal64 a, _Decimal64 b, _Decimal64 c) {
	return c;
}

static _Decimal32 three32(_Decimal32 a, _Decimal32 b, _Decimal32 c) {
	return c;
}

static _Decimal128 three128(_Decimal128 a, _Decimal128 b, _Decimal128 c) {
	return c;
}

struct hold64 {
	_Decimal64 x;
};

static struct hold64 through(struct hold64 s) {
	return s;
}

int main(void) {
	_Decimal64 a = 1.5dd, b = 2.5dd, c = 3.5dd;
	_Decimal64 arr[4];
	struct hold64 s;
	_Decimal64 *p = &c;
	_Decimal64 r;

	// Read from a variable, an array element, a member and an address.
	arr[2] = 4.5dd;
	s.x = 5.5dd;
	r = a;
	hex(&r, 8);
	r = arr[2];
	hex(&r, 8);
	r = s.x;
	hex(&r, 8);
	r = *p;
	hex(&r, 8);

	// Handed over and given back, three at a time.
	r = three(a, b, c);
	hex(&r, 8);
	_Decimal32 r32 = three32(1.5df, 2.5df, 3.5df);
	hex(&r32, 4);
	_Decimal128 r128 = three128(1.5dl, 2.5dl, 3.5dl);
	hex(&r128, 16);

	// A struct carrying a decimal, passed and returned by value.
	struct hold64 t = through(s);
	hex(&t.x, 8);

	// A variadic call: the payload is the value's own bytes.
	payload(1, a);
	payload(1, c);
	return 0;
}
