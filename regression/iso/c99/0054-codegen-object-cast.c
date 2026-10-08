/* 0054: a cast whose operand is an object is that object

A cast names a type, and where the operand is already an object of an aggregate
type the cast is not a conversion of it: the types are compatible or the type
checker refused the program, so what travels is the operand's own bytes. V's own
generated C writes one at every array it makes, `Array res = (Array)(...)`, and
one at every panic of a message it builds in place.

What this case reaches is a cast of a call, a cast of a name returned from a
function, a cast of a parameter, a cast of a cast and a cast of a compound
literal, at four, eight and sixteen bytes.

Measured on gcc 16.2.1, which prints the two lines below and exits 0; the
pre-change binary refuses the file at its first cast. */
#include <stdio.h>

typedef struct Pair {
	int a;
	int b;
} Pair;

typedef struct Big {
	long x;
	long y;
	long z;
} Big;

Pair make(int a, int b) {
	Pair p;
	p.a = a;
	p.b = b;
	return p;
}

Big big(long x) {
	Big b;
	b.x = x;
	b.y = x + 1;
	b.z = x + 2;
	return b;
}

Pair passthrough(Pair p) {
	return (Pair)(p);
}

Big big_cast(Big v) {
	return (Big)(v);
}

int main(void) {
	Pair p = (Pair)(make(3, 4));
	Big b = (Big)(big(10));
	Pair q = passthrough((Pair)(p));
	Big c = big_cast((Big)(b));
	Pair r = (Pair)((Pair){7, 8});
	int said = 0;
	printf("%d %d %ld %d %d %d\n", p.a + p.b, q.a * q.b, b.x + b.y + b.z, (int)c.x, (int)c.y, (int)c.z);
	printf("%d\n", (int)r.a + (int)r.b);
	said = p.a + p.b == 7 && q.a * q.b == 12 && b.x + b.y + b.z == 33;
	said = said && (int)c.x == 10 && (int)c.y == 11 && (int)c.z == 12;
	return said && (int)r.a + (int)r.b == 15 ? 0 : 1;
}
