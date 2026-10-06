/* 0962: CHECK(strcmp(buf, "abcdef") == 0);
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
    char buf[16];
    strcpy(buf, "abc");
    CHECK(strcat(buf, "def") == buf);
    CHECK(strcmp(buf, "abcdef") == 0);
    CHECK(buf[6] == 0);
    strcat(buf, "");
    CHECK(strlen(buf) == 6);
    return 0;
}
