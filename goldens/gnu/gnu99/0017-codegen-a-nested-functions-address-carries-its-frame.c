// The address of a nested function is a trampoline: the stub carries the frame
// the address was taken in, so a call through the pointer reads the enclosing
// objects the nested body uses. The calls are made directly, through the
// pointer, through a dereference, through a second pointer that was copied, and
// through another function that was handed the pointer.
#include <stdio.h>

int main(void) {
	int n = 5;
	int add(int v) { return v + n; }
	int twice(int (*f)(int), int v) { return f(v) * 2; }
	int (*fp)(int) = add;
	int (*same)(int) = fp;
	printf("%d\n", fp(3));
	n = 20;
	printf("%d\n", (*fp)(1));
	printf("%d\n", twice(add, 2));
	printf("%d\n", same(0));
	return 0;
}
