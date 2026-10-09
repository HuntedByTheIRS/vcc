// 0057: a tentative definition and the definition after it are one object.
//
// ISO/IEC 9899:1999 6.9.2p2: "If a translation unit contains one or more
// tentative definitions for an identifier, and the translation unit contains no
// external definition for that identifier, then the behavior is exactly as if
// the translation unit contains a file scope declaration of that identifier,
// with the composite type as of the end of the translation unit, with an
// initializer equal to 0." The unit here does contain an external definition,
// `int x = 5; int s[8] = "hi";`, so that is the object: it is the one whose
// storage the image holds, and the initializer it carries is theirs. Before this
// case, the emitter laid out the first declaration it found by name and skipped
// the definition, so reading x gave 0 and reading s gave an empty string.

int x;
int x = 5;

char s[8];
char s[8] = "hi";

int zero;
int seven = 7;

int main(void) {
	if (x != 5) {
		return 1;
	}
	if (s[0] != 'h' || s[1] != 'i' || s[2] != 0) {
		return 2;
	}
	if (zero != 0 || seven != 7) {
		return 3;
	}
	return 0;
}
