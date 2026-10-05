/* 501: CHECK(memcmp(overlapping, "01234567", 8) == 0);
 *
 * monolithic.c:11135 (strings)
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
    char overlapping[16] = "0123456789";
    CHECK(memcmp("abc", "abc", 3) == 0);
    CHECK(memcmp("abc", "abd", 3) < 0);
    CHECK(memcmp("abd", "abc", 3) > 0);
    CHECK(memcmp("abc", "abcdef", 3) == 0);
    memmove(overlapping + 2, overlapping, 8);
    CHECK(memcmp(overlapping, "0101234567", 10) == 0);
    memmove(overlapping, overlapping + 2, 8);
    CHECK(memcmp(overlapping, "01234567", 8) == 0);
    }
    return 0;
}
