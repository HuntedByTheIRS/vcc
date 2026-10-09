// 0056: a tag a function pointer names before its definition, completed by it.
//
// ISO/IEC 9899:1999 6.7.2.3p4: "All declarations of structure, union, or
// enumerated types that have the same scope and use the same tag declare the
// same type." The `struct R` the function type at the top of this file returns
// and the `struct R` defined below it are one type, so a call through the
// pointer produces an object of the size the definition gives it. 6.7.5.3p1
// gives the function type its return type.
//
// V's own generated C writes this shape twice over: a result structure's name in
// an encoder's function-pointer typedef, and that typedef as a field of a
// structure whose body is read before the result structure's. Before this case,
// a call through the pointer was refused with "struct R is an object whose size
// this back end does not know", both where the typedef name was used again after
// the body and where only the field that held the mention was.

typedef struct R (*fnptr)(int);

// A mention written before the body with nothing that names the typedef again
// once the body has been read: the call through the field is the only later use.
struct Encoders {
	fnptr late;
};

struct R {
	int ok;
	int value;
};

static fnptr table;
static struct Encoders encoders;

static struct R make(int value) {
	struct R made;
	made.ok = 1;
	made.value = value;
	return made;
}

static int through_the_field(void) {
	struct R got = encoders.late(11);
	return got.ok == 1 && got.value == 11 ? 0 : 1;
}

int main(void) {
	struct R got;
	if (sizeof(struct R) != 8) {
		return 1;
	}
	table = make;
	got = table(41);
	if (got.ok != 1 || got.value != 41) {
		return 2;
	}
	encoders.late = make;
	if (through_the_field() != 0) {
		return 3;
	}
	return 0;
}
