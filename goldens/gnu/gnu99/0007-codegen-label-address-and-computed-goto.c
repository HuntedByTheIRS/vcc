/* the address of a label, &&label, and a computed goto, goto *expr */

#include <stdio.h>

int main(void)
{
    static void *table[3];
    int i, n = 0;

    table[0] = &&zero;
    table[1] = &&one;
    table[2] = &&two;

    for (i = 0; i < 3; i++) {
        goto *table[i];
zero:
        n += 1;
        continue;
one:
        n += 10;
        continue;
two:
        n += 100;
        continue;
    }
    printf("%d\n", n);
    return 0;
}
