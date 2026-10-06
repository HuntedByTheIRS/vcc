/* 1143: builtin-constant-p
 *
 * GCC 7.12 Other Built-in Functions Provided by GCC: "You can use the built-in
 * function __builtin_constant_p to determine if the expression exp is known to
 * be constant at compile time ... The function returns the integer 1 if the
 * argument is known to be a compile-time constant and 0 if it is not."
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
    int x = 5;

    CHECK(__builtin_constant_p(3) == 1);
    CHECK(__builtin_constant_p(2 + 3) == 1);
    CHECK(__builtin_constant_p(x) == 0);
    return 0;
}
