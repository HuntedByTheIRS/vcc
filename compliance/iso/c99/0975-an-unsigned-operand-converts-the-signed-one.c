/* 0975: CHECK(!(-1 < 1u));
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
    /* The usual arithmetic conversions turn -1 into an unsigned int, which is
     * the largest one, so the comparison is false where an int comparison would
     * be true. */
    CHECK(!(-1 < 1u));
    CHECK(-1 > 1u);
    CHECK((unsigned int)-1 == 4294967295u);
    return 0;
}
