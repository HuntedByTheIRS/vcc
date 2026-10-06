/* 0966: CHECK(memset(buf, 'a', 3) == buf);
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
    char *back;
    memset(buf, 0, sizeof buf);
    back = memset(buf, 'a', 3);
    CHECK(back == buf);
    CHECK(buf[0] == 'a' && buf[2] == 'a');
    /* The byte after the n written is the one the buffer held before. */
    CHECK(buf[3] == 0);
    return 0;
}
