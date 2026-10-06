/* 1144: the-bit-operation-builtins
 *
 * GCC 7.2.2 Bit Operation Builtins: "Built-in Function: int __builtin_popcount
 * (unsigned int x) Returns the number of 1-bits in x. ... int __builtin_parity
 * (unsigned int x) Returns the parity of x, i.e. the number of 1-bits in x
 * modulo 2."
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
    CHECK(__builtin_popcount(0xF0u) == 4);
    CHECK(__builtin_clz(1u) == 31);
    CHECK(__builtin_ctz(8u) == 3);
    CHECK(__builtin_parity(7u) == 1);
    return 0;
}
