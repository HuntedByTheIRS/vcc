/* 1141: arithmetic-with-overflow-checking
 *
 * GCC 7.2.5 Built-in Functions to Perform Arithmetic with Overflow Checking:
 * "These built-in functions ... use the operands to perform simple arithmetic
 * operations together with checking whether the operations overflowed. ...
 * Built-in Function: bool __builtin_add_overflow (type1 a, type2 b, type3 * res)"
 *
 * unimplemented: __builtin_add_overflow and __builtin_mul_overflow.
 */

#include <stdio.h>
#include <limits.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int r = 0;

    CHECK(__builtin_add_overflow(1, 2, &r) == 0);
    CHECK(r == 3);
    CHECK(__builtin_mul_overflow(3, 4, &r) == 0);
    CHECK(r == 12);
    CHECK(__builtin_add_overflow(INT_MAX, 1, &r) != 0);
    return 0;
}
