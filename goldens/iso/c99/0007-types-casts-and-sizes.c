#include <stdio.h>
#include <stdint.h>

int main(void) {
    double d = 3.99;
    printf("%d\n", (int)d);
    printf("%d\n", (int)-2.7);
    printf("%.1f\n", (double)7 / 2);
    printf("%d\n", (int)(unsigned char)300);
    printf("%d\n", (int)(unsigned short)70000);
    printf("%u\n", (uint32_t)-1);
    unsigned long long big = 4294967295ULL;
    printf("%llu\n", big + 1);
    printf("%zu\n", sizeof(char));
    printf("%d\n", (int)(int32_t)100000 * 10);
    return 0;
}
