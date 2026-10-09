/* 0055: an object of no bytes hands over nothing and reads as nothing

A structure with no members has no bytes: the machine has no register for one, no
word of the stack and nothing to load, so an argument of the type spends no
register and the arguments beside it keep the places they had. Reading one is not
a read at all, whether it is reached by dereferencing a pointer to one or as a
member of a larger object that holds one, because there are no bytes for a load
to bring into a register.

An empty structure is what V's own generated C passes at every interface call it
writes: the declaration of the structure an interface holds an object inside is
filled in by a compiler macro, and with no macro defined the structure is empty,
so an interface call passes one of these and reads one.

Measured on gcc 16.2.1, which prints `42 42 42 42` and exits 0; the pre-change
binary refuses the file at its first read of one. */

typedef struct Empty {
	;
} Empty;

typedef struct Holder {
	int head;
	Empty field;
	int tail;
} Holder;

int take(Empty e, int x) {
	(void)e;
	return x;
}

int take_two(Empty a, int x, Empty b, int y) {
	(void)a;
	(void)b;
	return x + y;
}

int main(void) {
	Empty e = {};
	Empty other = {};
	Holder h;
	h.head = 41;
	h.tail = 1;
	return take(e, 42) == 42 && take_two(e, 20, other, 22) == 42 && take(*&e, 42) == 42 && take(h.field, 42) == 42 && h.head + h.tail == 42 && sizeof(Empty) == 0 ? 0 : 1;
}
