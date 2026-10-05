/* 964: CHECK(strcmp(buf, "bcde") == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char buf[8];
    strcpy(buf, "abcde");
    /* Five bytes are moved, the terminator included, and the destination is
     * before the source, so the copy runs forwards from the start. */
    memmove(buf, buf + 1, 5);
    CHECK(strcmp(buf, "bcde") == 0);
    return 0;
}
