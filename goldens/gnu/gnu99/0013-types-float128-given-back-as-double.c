/* the _Float128 type, read and given back as a double */

#include <stdio.h>

int main(void)
{
    _Float128 a = 1.5f128;
    _Float128 b = 2.5f128;
    _Float128 c = a + b;

    printf("%g %g %zu\n", (double)a, (double)c, sizeof(_Float128));
    return 0;
}
