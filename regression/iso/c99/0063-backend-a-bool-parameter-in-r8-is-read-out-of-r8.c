// 0063: a `_Bool` parameter handed over in a register is read out of that register.
//
// The move that widens a one-byte value into a whole register names one register
// in each field of its modrm byte, the byte it reads in the rm field and the whole
// register it writes in the reg field, and both are the same register. A register
// past the eighth needs the prefix bit of each field for that, and the encoder set
// only the destination's, so `movzbl %r8b, %r8d` was written as `movzbl %al, %r8d`
// and the callee read whatever the caller had left in al. A `_Bool` parameter
// arrived as zero where the caller passed a one.
//
// The shape that reaches it is a call whose earlier arguments are structures passed
// by value: those travel in memory, so the general registers stay free for the
// scalars after them, and a `_Bool` in the fifth of those arrives in r8. The
// program passes three structures by value and a one in that parameter, and checks
// the value came through, printing nothing.
//
// Measured on this tree: the program exited 1 before the fix and 0 after it, and
// gcc 16.2.1 answers the same as the fix.

typedef struct {
	long len;
	long data;
	long cap;
} Array;
typedef struct {
	long reg;
	int kind;
	long base;
} Target;
typedef struct {
	long text, rodata, data, rela, symtab, strtab, headers, total;
} Sections;
typedef struct {
	long f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11;
} Program;

static long total(Array* output, Target target, Sections sections, Program program,
	long first, long second, int third, _Bool seen, unsigned long weight) {
	if (sections.text != 7 || program.f0 != 0 || target.reg != 1 || output->len != 5) {
		return -1;
	}
	if (first != 11 || second != 13 || third != 2 || weight != 17) {
		return -1;
	}
	return (seen ? 1000 : 0) + third + (long)weight + first + second + target.reg + output->len;
}

int main(void) {
	Array output = { 5, 0, 0 };
	Target target = { 1, 2, 3 };
	Sections sections = { 7, 0, 0, 0, 0, 0, 0, 0 };
	Program program = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
	return total(&output, target, sections, program, 11, 13, 2, 1, 17) == 1049 ? 0 : 1;
}
