// The decimal calling convention: a value read out of an object for its own
// value, handed to a function and given back, carried inside a struct passed and
// returned by value, and passed through a variadic call, at all three widths.
//
// Measured on gcc 16.2.1: every width is passed and given back in xmm0, a
// _Decimal128 across the xmm0:xmm1 pair, and a variadic call passes the raw
// payload with no promotion. The bytes below are the ones gcc 16.2.1 wrote for
// these values, so a program that reads them back differently has changed what
// travels, which is the regression this case holds.
//
// The case is silent on purpose: for a regression a line of output is itself the
// regression, so it compares against the bytes gcc wrote and exits non-zero at
// the point of the first mismatch rather than printing them.
#include <stdarg.h>
#include <string.h>

static _Decimal64 three(_Decimal64 a, _Decimal64 b, _Decimal64 c) {
	return c;
}

static _Decimal32 three32(_Decimal32 a, _Decimal32 b, _Decimal32 c) {
	return c;
}

static _Decimal128 three128(_Decimal128 a, _Decimal128 b, _Decimal128 c) {
	return c;
}

struct hold {
	_Decimal64 x;
};

static struct hold through(struct hold s) {
	return s;
}

// A variadic call passes a decimal with no promotion, so what a double read out
// of the variadic argument area holds is the value's own bytes.
static unsigned long long payload(int n, ...) {
	va_list ap;
	unsigned long long bits = 0;
	double raw;
	(void) n;
	va_start(ap, n);
	raw = va_arg(ap, double);
	memcpy(&bits, &raw, sizeof bits);
	va_end(ap);
	return bits;
}

int main(void) {
	_Decimal64 a = 1.5dd, b = 2.5dd, c = 3.5dd;
	_Decimal64 arr[4];
	struct hold s;
	_Decimal64 *p = &c;
	_Decimal64 r;
	unsigned long long w = 0;
	unsigned long long low = 0;
	unsigned long long high = 0;
	unsigned int w32 = 0;
	_Decimal128 r128;

	arr[2] = 4.5dd;
	s.x = 5.5dd;

	// Read from a variable, an array element, a member and an address.
	r = a;
	memcpy(&w, &r, sizeof w);
	if (w != 0x31a000000000000fULL) {
		return 1;
	}
	r = arr[2];
	memcpy(&w, &r, sizeof w);
	if (w != 0x31a000000000002dULL) {
		return 2;
	}
	r = s.x;
	memcpy(&w, &r, sizeof w);
	if (w != 0x31a0000000000037ULL) {
		return 3;
	}
	r = *p;
	memcpy(&w, &r, sizeof w);
	if (w != 0x31a0000000000023ULL) {
		return 4;
	}

	// Handed over and given back, three at a time.
	r = three(a, b, c);
	memcpy(&w, &r, sizeof w);
	if (w != 0x31a0000000000023ULL) {
		return 5;
	}
	_Decimal32 r32 = three32(1.5df, 2.5df, 3.5df);
	memcpy(&w32, &r32, sizeof w32);
	if (w32 != 0x32000023u) {
		return 6;
	}
	r128 = three128(1.5dl, 2.5dl, 3.5dl);
	memcpy(&low, &r128, sizeof low);
	memcpy(&high, (char *) &r128 + sizeof low, sizeof high);
	if (low != 0x0000000000000023ULL) {
		return 7;
	}
	if (high != 0x303e000000000000ULL) {
		return 8;
	}

	// A struct carrying a decimal, passed and returned by value.
	struct hold t = through(s);
	memcpy(&w, &t.x, sizeof w);
	if (w != 0x31a0000000000037ULL) {
		return 9;
	}

	// A variadic call: the payload is the value's own bytes.
	if (payload(1, a) != 0x31a000000000000fULL) {
		return 10;
	}
	if (payload(1, c) != 0x31a0000000000023ULL) {
		return 11;
	}
	return 0;
}
