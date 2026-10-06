/* 1146: builtin-unreachable-and-builtin-trap
 *
 * GCC 7.12 Other Built-in Functions Provided by GCC: "Built-in Function: void
 * __builtin_unreachable (void) If control flow reaches the point of the
 * __builtin_unreachable, the program is undefined. ... Built-in Function: void
 * __builtin_trap (void) This function causes the program to exit abnormally."
 *
 * unimplemented: __builtin_unreachable and __builtin_trap.
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
    int x = 1;

    if (x == 3) {
        __builtin_unreachable();
    }
    if (sizeof(int) == 0) {
        __builtin_trap();
    }
    CHECK(x == 1);
    return 0;
}
