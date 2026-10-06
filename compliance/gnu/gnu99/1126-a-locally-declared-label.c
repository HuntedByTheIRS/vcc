/* 1126: a-locally-declared-label
 *
 * GCC 6.12.2 Locally Declared Labels: "GCC allows you to declare local labels
 * in any nested block scope. A local label is just like an ordinary label, but
 * you can only reference it (with a goto statement, or by taking its address)
 * within the block in which it is declared."
 *
 * unimplemented: a local label declared with __label__.
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
    int taken = 0;

    {
        __label__ found;

        if (taken == 0) {
            taken = 1;
            goto found;
        }
        taken = 2;
    found:;
    }
    CHECK(taken == 1);
    return 0;
}
