// 0061: a structure whose size is not one the machine moves travels in a register.
//
// System V gives an object of an aggregate type one register per eightbyte it fits
// in, so a structure of three bytes travels in one general register as the low three
// bytes of it, and no x86-64 general register has a three-byte move. The emitter read
// the object's bytes with one move at the width the class carries and the machine
// refused it as an internal error, which is the worst shape a refusal has: no
// location, and nothing naming the construct. The same width comes back in the other
// two places an object crosses a register, the callee writing the register into its
// own parameter and a call handing a result structure back.
//
// Every value has to survive both directions, so the program checks the bytes it sent
// and the size of the type, prints nothing and exits zero.

struct T {
	unsigned char a;
	unsigned char b;
	unsigned char c;
};

struct T id(struct T x) {
	return x;
}

int main(void) {
	struct T a;
	a.a = 1;
	a.b = 2;
	a.c = 3;
	struct T b = id(a);
	if (b.a != 1 || b.b != 2 || b.c != 3) {
		return 1;
	}
	if (sizeof(struct T) != 3) {
		return 2;
	}
	return 0;
}
