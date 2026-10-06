// Two blocks written one after another each define a nested function of one
// name. Each block is a scope of its own, so the two are two functions and each
// block calls the one it defined; the last call reads an enclosing object, which
// is what the frame the definition is written in carries.
#include <stdio.h>

int main(void) {
	{
		int f(void) { return 1; }
		printf("%d\n", f());
	}
	{
		int f(void) { return 2; }
		printf("%d\n", f());
	}
	int n = 4;
	int outer(void) {
		int g(void) { return n + 1; }
		return g();
	}
	printf("%d\n", outer());
	return 0;
}
