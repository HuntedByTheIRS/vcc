/* 0984: CHECK(n == 3);
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
    int rounds = 0;
    do {
        rounds++;
        if (rounds < 3) {
            continue;
        }
        n++;
    } while (rounds < 3);
    /* The continue goes to the test rather than past it, so the loop ends when
     * the third round finishes and the statement after it runs once. */
    CHECK(rounds == 3);
    CHECK(n == 1);
    return 0;
}
