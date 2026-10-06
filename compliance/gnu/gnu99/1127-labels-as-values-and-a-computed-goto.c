/* 1127: labels-as-values-and-a-computed-goto
 *
 * GCC 6.12.3 Labels as Values: "You can get the address of a label defined in
 * the current function (or a containing function) with the unary operator '&&'.
 * The value has type void *. ... To use these values, you need to be able to
 * jump to one. This is done with the computed goto statement, goto *exp;."
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
    void *targets[2];
    int reached = 0;

    targets[0] = &&zero;
    targets[1] = &&one;
    goto *targets[1];
zero:
    reached = 0;
    goto done;
one:
    reached = 1;
done:
    CHECK(reached == 1);
    return 0;
}
