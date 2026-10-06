#include <stdio.h>
#include <stdlib.h>

int main(void) {
    printf("%d\n", abs(-5));
    printf("%ld\n", labs(-123456789L));
    printf("%lld\n", llabs(-9000000000LL));
    int a = 2 + 3 * 4 - 1;
    printf("%d\n", a);
    printf("%d\n", (1 << 10) / 4);
    printf("%d\n", (7 * 8) - (9 / 3) + (10 % 4));
    return 0;
}
