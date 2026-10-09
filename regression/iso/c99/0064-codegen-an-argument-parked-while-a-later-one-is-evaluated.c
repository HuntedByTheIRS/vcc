/* An argument evaluated after another one is not allowed to take the slot the
 * earlier argument is parked in.
 *
 * `parser__Parser__fill_member` is called with an object of more than two
 * eightbytes, two arrays by value, and three scalars, one of which is the index
 * `start`. The argument after `start` is `base + (*(i64*)array_get(...))`, so a
 * call is evaluated while `start` is already parked in a frame slot. The slot
 * levels are what tell parked arguments apart, and the nested call used to start
 * at the level of the argument next to it, so it wrote its own copy's address
 * over `start`. The callee then indexed with a stack address instead of 7.
 *
 * Measured on the tree's own C before the fix: the compiler built from it read
 * `start` as 140732011043376 and panicked in array.get with `a.len` of 1. After
 * it, `start` arrives as 7. The same call also passes `base` wrong today, by a
 * separate defect in the same shape that this case does not cover: the callee
 * reads its `base` out of the register the caller put `writes` in. This case
 * asserts only the argument the slot clash reached, so it fails on the emitter
 * that clashed and passes on the one that does not.
 *
 * Exit status is the whole answer: 0 when the first scalar arrived, 1 when it
 * did not, and nothing is printed either way.
 */
typedef long long i64;

typedef struct {
	void* data;
	i64 offset;
	i64 len;
	i64 cap;
	int flags;
	int pad;
	i64 element_size;
} Array;

typedef struct { i64 w[35]; } Member;

typedef struct {
	i64 kind;
	Array members;
	Array bits;
	Array offsets;
} Layout;

static void* array_get(Array a, i64 i) {
	return (void*)((char*)a.data + i * 8);
}

static i64 fill_member(void* p, Member member, i64 bit_offset, Array rest, Array items,
	i64 start, i64 base, Array* writes) {
	(void)p;
	(void)member;
	(void)bit_offset;
	(void)rest;
	(void)items;
	(void)base;
	(void)writes;
	return start;
}

static i64 fill_brace(void* p, Layout typ, Array rest, Array items, i64 start, i64 base,
	Array* writes) {
	i64 member = 0;
	return fill_member(p, (*(Member*)array_get(typ.members, member)),
		(*(i64*)array_get(typ.bits, member)), rest, items, start,
		base + (*(i64*)array_get(typ.offsets, member)), writes);
}

int main(void) {
	static Member pool[1];
	static i64 bits[1];
	static i64 offsets[1];
	Layout typ = { 0 };
	typ.members = (Array){ pool, 0, 1, 1, 0, 0, sizeof(Member) };
	typ.bits = (Array){ bits, 0, 1, 1, 0, 0, 8 };
	typ.offsets = (Array){ offsets, 0, 1, 1, 0, 0, 8 };
	bits[0] = -1;
	Array rest = { 0, 0, 1, 1, 0, 0, 8 };
	Array items = { 0, 0, 1, 1, 0, 0, 8 };
	Array writes = { 0, 0, 0, 0, 0, 0, 0 };
	return fill_brace(0, typ, rest, items, 7, 8, &writes) == 7 ? 0 : 1;
}
