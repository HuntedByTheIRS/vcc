/* 0985: CHECK(hits == 3);
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
    int hits = 0;
    int which = 1;
    switch (which) {
    case 1:
        hits++;
    case 2:
        hits++;
    case 3:
        hits++;
        break;
    case 4:
        hits = 100;
        break;
    default:
        hits = 200;
        break;
    }
    /* The case entered runs to the next break, so three labels are reached. */
    CHECK(hits == 3);
    return 0;
}
