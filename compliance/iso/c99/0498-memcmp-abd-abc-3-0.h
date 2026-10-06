/* 0498: CHECK(memcmp("abd", "abc", 3) > 0);
 *
 * monolithic.c:11130 (strings)
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
    {
    CHECK(memcmp("abc", "abc", 3) == 0);
    CHECK(memcmp("abc", "abd", 3) < 0);
    CHECK(memcmp("abd", "abc", 3) > 0);
    }
    return 0;
}
