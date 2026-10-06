/* 963: CHECK(strcmp(buf, "aabc") == 0);
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
    strcpy(buf, "abcd");
    /* The destination is past the source, so the copy runs backwards and the
     * two characters that would otherwise be overwritten are read first. */
    memmove(buf + 1, buf, 3);
    CHECK(strcmp(buf, "aabc") == 0);
    return 0;
}
