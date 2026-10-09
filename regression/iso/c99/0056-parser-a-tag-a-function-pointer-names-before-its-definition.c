// 0056: a tag a function pointer names before its definition, completed by it.
//
// ISO/IEC 9899:1999 6.7.2.3p4: "All declarations of structure, union, or
// enumerated types that have the same scope and use the same tag declare the
// same type." The `struct R` the function type at the top of this file returns
// and the `struct R` defined below it are one type, so the call through the
// pointer produces an object of the size the definition gives it. 6.7.5.3p1
// gives the function type its return type.
//
// V's own generated C writes this shape: a result structure's name in a
// function-pointer typedef, and the structure's body further down the unit.
// Before this case, the call was refused with "struct R is an object whose size
// this back end does not know".

typedef struct R (*fnptr)(int);

struct R {
	int ok;
	int value;
};

static fnptr table;

static struct R make(int value) {
	struct R made;
	made.ok = 1;
	made.value = value;
	return made;
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
	return 0;
}
