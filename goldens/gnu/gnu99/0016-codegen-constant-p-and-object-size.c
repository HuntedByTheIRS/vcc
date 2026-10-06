/* __builtin_constant_p and __builtin_object_size */

#include <stdio.h>

int main(void)
{
    int arr[10];
    int i = 3;

    printf("%d %d\n", __builtin_constant_p(7), __builtin_constant_p(i));
    printf("%zu %zu\n", __builtin_object_size(arr, 0), __builtin_object_size("abcdef", 0));
    return 0;
}
