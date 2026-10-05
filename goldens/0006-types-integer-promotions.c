#include <stdio.h>
#include <stdint.h>

int main(void) {
    uint8_t a = 200, b = 100;
    printf("%d\n", a + b);
    uint16_t c = 60000, d = 10000;
    printf("%d\n", c + d);
    int8_t e = -100;
    printf("%d\n", e * 3);
    unsigned char f = 0xFF;
    printf("%d %d\n", (int)f, f == 255);
    short g = -1;
    unsigned int h = 1;
    printf("%u\n", h + g);
    printf("%zu %zu %zu\n", sizeof(uint8_t), sizeof(uint16_t), sizeof(uint32_t));
    return 0;
}
