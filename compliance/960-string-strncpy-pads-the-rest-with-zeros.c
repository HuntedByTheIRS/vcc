/* 960: CHECK(buf[2] == 0 && buf[7] == 0);
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
    memset(buf, 'z', sizeof buf);
    strncpy(buf, "ab", sizeof buf);
    CHECK(buf[0] == 'a');
    CHECK(buf[1] == 'b');
    /* n characters are written whatever the source holds, and the ones past the
     * copying are zeros rather than whatever the destination had. */
    CHECK(buf[2] == 0);
    CHECK(buf[7] == 0);
    return 0;
}
