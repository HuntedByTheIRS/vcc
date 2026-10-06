/* __builtin_add_overflow and __builtin_mul_overflow */

#include <stdio.h>

int main(void)
{
    int r = -1, over;

    over = __builtin_add_overflow(1, 2, &r);
    printf("%d %d\n", over, r);
    over = __builtin_add_overflow(2147483647, 1, &r);
    printf("%d %d\n", over, r);
    over = __builtin_mul_overflow(100000, 100000, &r);
    printf("%d %d\n", over, r);
    over = __builtin_mul_overflow(3, 4, &r);
    printf("%d %d\n", over, r);
    return 0;
}
