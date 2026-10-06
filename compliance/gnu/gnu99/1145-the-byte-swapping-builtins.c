/* 1145: the-byte-swapping-builtins
 *
 * GCC 7.2.3 Byte-Swapping Builtins: "Built-in Function: uint16_t
 * __builtin_bswap16 (uint16_t x) ... Built-in Function: uint32_t
 * __builtin_bswap32 (uint32_t x) Similar to __builtin_bswap16, except the
 * argument and return types are 32-bit."
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(__builtin_bswap16(0x0102u) == 0x0201u);
    CHECK(__builtin_bswap32(0x01020304u) == 0x04030201u);
    return 0;
}
