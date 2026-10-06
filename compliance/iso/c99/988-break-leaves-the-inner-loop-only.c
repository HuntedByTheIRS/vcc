/* 988: CHECK(outer == 4);
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
    int outer = 0;
    int inner = 0;
    for (outer = 1; outer <= 3; outer++) {
        for (inner = 1; inner <= 3; inner++) {
            break;
        }
        /* The inner break leaves the inner loop, so the outer one keeps going
         * and the inner counter is set again by the next outer round. */
        if (inner != 1) {
            return 1;
        }
    }
    CHECK(outer == 4);
    CHECK(inner == 1);
    return 0;
}
