#include <stdio.h>

int main(void) {
    int a = 2, b = 3, c = 4;
    printf("%d\n", a + b * c);
    printf("%d\n", (a + b) * c);
    printf("%d\n", a << b - 1);
    printf("%d\n", 1 + 2 == 3);
    printf("%d\n", (a < b) + (b < c));
    printf("%d\n", (a & 1) | (b & 2));
    printf("%d\n", a ^ b & b - 1);
    printf("%d\n", -a * -b);
    printf("%d\n", a % b + c * b);
    return 0;
}
