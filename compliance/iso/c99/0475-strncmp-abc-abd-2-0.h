/* 0475: CHECK(strncmp("abc", "abd", 2) == 0);
 *
 * monolithic.c:11078 (strings)
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
    CHECK(strncmp("abcde", "abcXX", 3) == 0);
    CHECK(strncmp("abc", "abd", 3) < 0);
    CHECK(strncmp("abc", "abd", 2) == 0);
    return 0;
}
