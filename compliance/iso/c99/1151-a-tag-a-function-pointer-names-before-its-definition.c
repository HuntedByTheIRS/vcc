/* 1151: a-tag-a-function-pointer-names-before-its-definition
 *
 * ISO/IEC 9899:1999 6.7.2.3p4: "All declarations of structure, union, or
 * enumerated types that have the same scope and use the same tag declare the
 * same type."
 *
 * 6.7.2.3p6 searches the declarations in scope for the tag and declares that
 * type, and 6.7.2.3p8 completes it where the list of members is written. So the
 * `struct R` the function type at the top of this file returns and the
 * `struct R` defined below it are one type, and the `struct R` a call through
 * the pointer produces has the size that definition gives it.
 *
 * unimplemented: a structure a function type names before its own definition is
 * not completed, so a call through that pointer has no width for its result.
 */

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
