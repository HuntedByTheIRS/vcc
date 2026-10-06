/* 0961: CHECK(strcmp(buf, "ab") == 0);
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
    strcpy(buf, "a");
    /* One character is appended and then the terminator, so "a" and "b" of
     * "bcd" fit where n says two. */
    strncat(buf, "bcd", 1);
    CHECK(strcmp(buf, "ab") == 0);
    strncat(buf, "cd", 8);
    CHECK(strcmp(buf, "abcd") == 0);
    return 0;
}
