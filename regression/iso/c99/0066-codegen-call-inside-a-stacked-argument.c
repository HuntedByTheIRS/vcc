/* 0066: a call written inside a stacked argument is entered aligned

A string is three eightbytes, so a call whose argument is one hands over three
words and takes a fourth so the total is even.  The emitter took that word
before it evaluated the argument, and an argument that is itself a call ran
with the word standing: the callee's frame started eight bytes off the
alignment the convention asks for.  Nothing this compiler emits uses an aligned
sixteen-byte move, so the fault waited until a collected program reached
libgcc's unwinder through the collector.  Fixed in 615aed0 ("codegen: a call
inside a stacked argument is entered aligned"). */

#include <stdio.h>

typedef struct {
	unsigned char *str;
	long len;
	long is_lit;
} string;

/* record answers with the alignment of a local of its own frame.  A frame
   entered as the convention asks puts that local at one of two addresses, and
   the same one every time; a frame entered eight bytes off shifts it. */
string record(long n)
{
	unsigned char local[8];
	string s;
	s.str = local;
	s.len = (long)(((unsigned long)local) & 15);
	s.is_lit = n;
	return s;
}

/* carry hands back what the call written in its argument recorded, so the
   number survives the call it was an argument of. */
string carry(string s, int width)
{
	unsigned char local[8];
	string r;
	r.str = local;
	r.len = s.len;
	r.is_lit = (long)width;
	return r;
}

int main(void)
{
	long direct, inside;

	direct = record(1).len; /* called from a statement, nothing on the stack */
	inside = carry(record(2), 3).len; /* called inside a stacked argument */
	if (direct != inside) {
		fprintf(stderr, "a call inside a stacked argument was entered misaligned: %ld against %ld\n",
			direct, inside);
		return 1;
	}
	return 0;
}
