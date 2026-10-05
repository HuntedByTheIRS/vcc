/* 502: CHECK(memcmp(other, binary, sizeof binary) == 0);
 *
 * monolithic.c:11143 (strings)
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
            char bytes[16];
            char overlapping[16] = "0123456789";
            memset(bytes, 0x5A, sizeof bytes);
            CHECK(bytes[0] == 0x5A && bytes[15] == 0x5A);
            memcpy(bytes, "ab\0cd", 5);
            CHECK(bytes[0] == 'a' && bytes[1] == 'b' && bytes[2] == '\0');
            CHECK(bytes[4] == 'd' && bytes[5] == 0x5A);
            CHECK(memchr(bytes, '\0', 5) == &bytes[2]);
            CHECK(memcmp("abc", "abc", 3) == 0);
            CHECK(memcmp("abc", "abd", 3) < 0);
            CHECK(memcmp("abd", "abc", 3) > 0);
            CHECK(memcmp("abc", "abcdef", 3) == 0);
            memmove(overlapping + 2, overlapping, 8);      /* overlapping copy */
            CHECK(memcmp(overlapping, "0101234567", 10) == 0);
            memmove(overlapping, overlapping + 2, 8);
            CHECK(memcmp(overlapping, "01234567", 8) == 0);
        }
    {
    unsigned char binary[8] = {0x00, 0x7F, 0x80, 0xFF, 'A', 0, 'B', 'C'};
    unsigned char other[8];
    memcpy(other, binary, sizeof binary);
    CHECK(memcmp(other, binary, sizeof binary) == 0);
    }
    return 0;
}
