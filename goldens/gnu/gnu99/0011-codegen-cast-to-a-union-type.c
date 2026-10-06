/* a cast to a union type initializes the member the operand's type matches */

#include <stdio.h>

union value { int i; float f; };

int main(void)
{
    union value a = (union value)42;
    union value b = (union value)1.5f;

    printf("%d %g\n", a.i, (double)b.f);
    return 0;
}
