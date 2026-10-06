/* a designated initializer that names a range, [first ... last] = value */

#include <stdio.h>

int widths[] = { [0 ... 3] = 1, [4 ... 6] = 2, [7] = 3 };

int main(void)
{
    int slot[10] = { [2 ... 5] = 9 };
    int i;

    printf("%zu\n", sizeof(widths) / sizeof(widths[0]));
    for (i = 0; i < 8; i++) printf("%d", widths[i]);
    printf("\n");
    for (i = 0; i < 10; i++) printf("%d", slot[i]);
    printf("\n");
    return 0;
}
