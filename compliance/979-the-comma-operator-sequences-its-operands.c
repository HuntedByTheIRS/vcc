/* 979: CHECK(m == 2 && n == 1);
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
    int n = 0;
    int m = (n++, n + 1);
    /* The left operand is evaluated and its value discarded, and the right one
     * is the value of the whole expression. */
    CHECK(n == 1);
    CHECK(m == 2);
    CHECK((n = 5, n * 2) == 10);
    return 0;
}
