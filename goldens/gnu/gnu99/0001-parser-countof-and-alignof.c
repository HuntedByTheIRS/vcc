/* _Countof counts an array's elements and __alignof__ an alignment */

#include <stdio.h>

int main(void)
{
    int a[7];
    char b[3];
    double d;

    printf("%zu %zu %zu\n", (size_t)_Countof(a), (size_t)_Countof(b), (size_t)_Countof("hello"));
    printf("%zu %zu %zu %zu\n", (size_t)__alignof__(int), (size_t)__alignof__(double),
           (size_t)__alignof__(a), (size_t)__alignof__(d));
    return 0;
}
