/* 0974: CHECK(-7 % 2 == -1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    CHECK(7 % 2 == 1);
    CHECK(-7 % 2 == -1);
    CHECK(7 % -2 == 1);
    CHECK(-7 % -2 == -1);
    /* a == (a / b) * b + a % b, which is the identity the two operators share
     * whatever signs the operands have. */
    CHECK(-7 == (-7 / 2) * 2 + (-7 % 2));
    return 0;
}
