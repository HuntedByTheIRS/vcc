/* a conditional with the middle operand left out, `a ?: b` */

#include <stdio.h>

static int calls;

static int bump(void) { calls++; return 0; }

int main(void)
{
    int x = 5, y = 7;
    int old = x++;
    int v;

    printf("%d %d\n", old, x ?: y);
    calls = 0;
    v = bump() ?: 42;
    printf("%d %d\n", v, calls);
    return 0;
}
