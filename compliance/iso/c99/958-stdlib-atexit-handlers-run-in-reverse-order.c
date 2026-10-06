/* 958: CHECK(ran == 1);
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

static int ran;

static void registered_second(void)
{
    ran = 1;
}

static void registered_first(void)
{
    /* This one runs last, so the other has already set ran. If the handlers ran
     * in the order they were registered this sees zero, and _Exit leaves a
     * status the runner reads as a failure. */
    if (!ran) {
        _Exit(3);
    }
}

int main(void)
{
    atexit(registered_first);
    atexit(registered_second);
    CHECK(ran == 0);
    return 0;
}
