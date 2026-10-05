// The defect: phase 6 joined adjacent string literals by copying their
// spellings, so a literal whose text ended inside an escape let the following
// literal's first characters fall into that escape and change the bytes.
// `"\1" "2"` is the smallest shape: copied as spellings it reads as `\12`, one
// byte of value 10, where reading the two literals apart gives the bytes 1 and
// 50, and the compiler refused the pair rather than answer wrongly. The same
// held for a literal that ends in a hex escape, `"\x41" "b"`, which gcc reads
// as 65 and 98. The join now concatenates the decoded contents, so each literal
// keeps the bytes reading it alone would give and the following literal's first
// character stays its own. gcc is the oracle and reads every literal below the
// same way this program expects.
#include <stdio.h>

int main(void) {
	const char *what = 0;
	int got = 0;
	int want = 0;

	{
		char s[] = "\1" "2";
		if (s[0] != 1) {
			what = "\\1\"2 first byte";
			got = s[0];
			want = 1;
		} else if (s[1] != '2') {
			what = "\\1\"2 second byte";
			got = s[1];
			want = '2';
		}
	}
	if (!what) {
		char s[] = "a" "\1";
		if (s[0] != 'a') {
			what = "\"a\"\"\\1\" first byte";
			got = s[0];
			want = 'a';
		} else if (s[1] != 1) {
			what = "\"a\"\"\\1\" second byte";
			got = s[1];
			want = 1;
		}
	}
	if (!what) {
		char s[] = "x\x41" "y";
		if (s[0] != 'x') {
			what = "\"x\\x41\"\"y\" first byte";
			got = s[0];
			want = 'x';
		} else if (s[1] != 65) {
			what = "\"x\\x41\"\"y\" second byte";
			got = s[1];
			want = 65;
		} else if (s[2] != 'y') {
			what = "\"x\\x41\"\"y\" third byte";
			got = s[2];
			want = 'y';
		}
	}
	if (!what) {
		char s[] = "\x41" "b";
		if (s[0] != 65) {
			what = "\"\\x41\"\"b\" first byte";
			got = s[0];
			want = 65;
		} else if (s[1] != 'b') {
			what = "\"\\x41\"\"b\" second byte";
			got = s[1];
			want = 'b';
		}
	}
	if (!what) {
		char s[] = "ab" "cd";
		if (s[0] != 'a' || s[1] != 'b' || s[2] != 'c' || s[3] != 'd' || s[4] != 0) {
			what = "\"ab\"\"cd\" bytes";
			got = s[0];
			want = 'a';
		}
	}
	if (what) {
		fprintf(stderr, "adjacent string literals: %s read as %d, wanted %d\n", what, got, want);
		return 1;
	}
	return 0;
}
