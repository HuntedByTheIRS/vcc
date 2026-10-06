/* 1133: a-conditional-with-the-middle-operand-omitted
 *
 * GCC 6.12.13 Conditionals with Omitted Operands: "The middle operand in a
 * conditional expression may be omitted. Then if the first operand is nonzero,
 * its value is the value of the conditional expression. Therefore, the
 * expression x ? : y has the value of x if that is nonzero; otherwise, the
 * value of y."
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
    int y = 9;
    int zero = 0;
    const char *name = 0;

    CHECK((x ?: y) == 5);
    CHECK((zero ?: y) == 9);
    CHECK((name ?: "fallback")[0] == 'f');
    return 0;
}
