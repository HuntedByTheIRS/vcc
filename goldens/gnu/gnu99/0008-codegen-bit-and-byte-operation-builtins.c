/* the bit-operation and byte-swapping builtins */

#include <stdio.h>

int main(void)
{
    unsigned int v = 0x0000F00Du;

    printf("%d %d %d %d\n", __builtin_popcount(v), __builtin_popcount(0),
           __builtin_popcount(0xFFFFFFFFu), __builtin_parity(v));
    printf("%d %d %d\n", __builtin_clz(1u), __builtin_clz(0x80000000u), __builtin_ctz(8u));
    printf("%d %d %d\n", __builtin_ctz(0x80000000u), __builtin_clz(0xFu),
           __builtin_parity(0xFFFFFFFFu));
    printf("%d %d\n", (int)__builtin_bswap16(0x1234u), (int)__builtin_bswap32(0x12345678u));
    return 0;
}
