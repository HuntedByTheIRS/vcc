/* 472: CHECK(strcmp("abc", "abd") < 0 && strcmp("abd", "abc") > 0);
 *
 * monolithic.c:11075 (strings)
 */

#include <stdio.h>
#include <stddef.h>
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
    char buffer[64];
    char copy[64];
    const char *source = "abcdefghij";
    CHECK(strlen("") == 0 && strlen("abc") == 3 && strlen(source) == 10);
    CHECK(strlen(source) == sizeof "abcdefghij" - 1);
    strcpy(copy, "hello");
    CHECK(strcmp(copy, "hello") == 0 && copy[5] == '\0');
    strcat(copy, " world");
    CHECK(strcmp(copy, "hello world") == 0);
    {
            /* strncat appends at most n characters and always terminates.  The
             * count is a volatile load so that -Wstringop-truncation does not fire
             * at -O2 about the deliberate truncation. */
            volatile size_t append_bound = 2;
            CHECK(strncat(copy, "!!!", append_bound) == copy);
            CHECK(strcmp(copy, "hello world!!") == 0);
        }
    {
            volatile size_t bound = 4;
            memset(buffer, '#', sizeof buffer);
            strncpy(buffer, source, bound);
            buffer[bound] = '\0';               /* the caller's job */
            CHECK(strcmp(buffer, "abcd") == 0);
            CHECK(buffer[bound - 1] == 'd' && buffer[bound] == '\0');
            memset(buffer, 0, sizeof buffer);
            strncpy(buffer, "ab", 8);
            CHECK(buffer[0] == 'a' && buffer[1] == 'b' && buffer[2] == '\0');
        }
    CHECK(strcmp("abc", "abc") == 0);
    CHECK(strcmp("abc", "abd") < 0 && strcmp("abd", "abc") > 0);
    return 0;
}
