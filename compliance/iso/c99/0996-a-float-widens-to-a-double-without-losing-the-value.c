/* 0996: CHECK((double)half == 0.5);
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
    float half = 0.5f;
    float quarter = 0.25f;
    /* Every float is a double, so widening one keeps its value exactly. */
    CHECK((double)half == 0.5);
    CHECK((double)quarter == 0.25);
    CHECK((double)half + (double)quarter == 0.75);
    CHECK(half + quarter == 0.75f);
    return 0;
}
