// 0062: a function returning a pointer to a narrow integer type returns the address.
//
// A spelling carrying a star names a pointer, and the predicate deciding whether a
// return type is narrower than an int read the words and ignored the star: `unsigned
// char *` was read as `unsigned char`, so a function returning one of them had its
// address cut to its low eight bits. An array returned from a function came back as
// `0x30` where gcc answers the array's own address, and a copy routine storing through
// it took the process down. `int *` looked right only because an address in this image
// fits in thirty-two bits, so the defect reached every pointer to a byte-sized type,
// which in V's generated C is every string.
//
// The program checks that the address survives three forms of the round trip, prints
// nothing and exits zero.
//
//	at_pool     returns an array, which decays to the address of its first element
//	offset_by   returns an array plus an offset
//	through_one returns a pointer parameter

typedef unsigned char u8;

static u8 pool[4096];

static u8* at_pool(void) {
	return pool;
}

static u8* offset_by(long n) {
	return pool + n;
}

static u8* through_one(u8* p) {
	return p;
}

int main(void) {
	pool[0] = 7;
	pool[3] = 9;
	pool[5] = 11;
	u8* a = at_pool();
	if (a != pool) {
		return 1;
	}
	u8* b = offset_by(5);
	if (b != pool + 5) {
		return 2;
	}
	u8* c = through_one(pool + 3);
	if (c != pool + 3) {
		return 3;
	}
	/* The address has to be usable and not only comparable. */
	if (*a != 7 || *b != 11 || *c != 9) {
		return 4;
	}
	return 0;
}
