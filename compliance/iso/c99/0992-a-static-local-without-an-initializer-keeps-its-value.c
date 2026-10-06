/* 0992: CHECK(twice() == 2);
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

static int counter(void)
{
    static int kept;
    kept = kept + 1;
    return kept;
}

int main(void)
{
    /* An object of static storage duration starts as zero and is one object for
     * the whole run, so the second call sees what the first one left. */
    CHECK(counter() == 1);
    CHECK(counter() == 2);
    CHECK(counter() == 3);
    return 0;
}
