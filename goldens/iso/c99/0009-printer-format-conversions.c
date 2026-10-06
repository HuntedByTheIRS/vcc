#include <stdio.h>

int main(void) {
    printf("%d|%5d|%-5d|%05d|%+d\n", 7, 7, 7, 7, 7);
    printf("%x %X %o\n", 255, 255, 8);
    printf("%u\n", 4000000000u);
    printf("%c%c\n", 'o', 'k');
    printf("%s|%10s|%-10s|\n", "abc", "abc", "abc");
    printf("%.2f %.0f %e %g\n", 3.14159, 2.5, 1234.5, 0.0001);
    printf("%%\n");
    return 0;
}
