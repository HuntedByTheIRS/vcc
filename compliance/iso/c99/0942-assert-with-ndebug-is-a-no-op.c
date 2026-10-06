/* 0942: CHECK(1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>

#define NDEBUG 1
#include <assert.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    /* NDEBUG is defined before <assert.h>, so assert expands to a statement
     * with no effect and this program runs to the end. */
    assert(0);
    assert(1 == 2);
    CHECK(1);
    return 0;
}
