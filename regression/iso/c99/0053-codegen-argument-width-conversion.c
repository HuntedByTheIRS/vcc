/* 0053: an argument's width against its parameter's is the conversion the call makes

An argument is converted to the parameter's type as an assignment would convert
it (C99 6.5.2.2), so a value wider than the parameter is handed over as the low
bytes its width leaves and one narrower is widened where it is parked. V's own
generated C passes a four-byte value to a `u8` parameter at every call of its
string routines, so what this case reaches is every pair of the widths the
machine has: four into one, one into four, eight into four, two into eight, one
into eight, and four and one into two parameters of one call.

Every value here is one a program computes rather than a constant, because a
constant is converted where it is folded and never reaches the call.

Measured on gcc 16.2.1, which prints the two lines below and exits 0; the
pre-change binary refuses the file at its first call. */

unsigned char ascii(unsigned char c) {
	return c;
}

unsigned char pair_sum(unsigned char a, unsigned char b) {
	return a + b;
}

int widen(char c) {
	return c;
}

long long widen_short(short s) {
	return s;
}

int narrow(long long v) {
	return v;
}

int main(void) {
	int n = 300;
	char ch = -1;
	long long big = 0x1234567890LL;
	unsigned char u = 200;
	short sh = 40000;
	int wide = 0;
	wide = ascii(n) == 44 && ascii(ch) == 255 && widen(u) == -56;
	wide = wide && narrow(big) == 878082192 && (int)widen_short(sh) == -25536;
	return wide && pair_sum(n, ch) == 43 ? 0 : 1;
}
