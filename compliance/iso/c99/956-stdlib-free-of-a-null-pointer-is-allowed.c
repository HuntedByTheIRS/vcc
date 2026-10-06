/* 956: CHECK(held == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    void *held = 0;
    free(0);
    free(held);
    /* free takes a null pointer and does nothing with it, so a pointer the
     * program never allocated can be freed through this path. */
    CHECK(held == 0);
    return 0;
}
