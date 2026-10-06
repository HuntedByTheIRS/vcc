/* __auto_type takes its type from the initializer */

#include <stdio.h>

int main(void)
{
    __auto_type n = 42;
    __auto_type d = 1.5;
    int arr[3];
    __auto_type p = arr;

    p[0] = 7;
    printf("%d %g\n", n, d);
    printf("%zu %zu %zu %d\n", sizeof(n), sizeof(d), sizeof(*p), p[0]);
    return 0;
}
