/* 0493: CHECK(bytes[0] == 'a' && bytes[1] == 'b' && bytes[2] == '\0');
 *
 * monolithic.c:11125 (strings)
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
    memset(bytes, 0x5A, sizeof bytes);
    CHECK(bytes[0] == 0x5A && bytes[15] == 0x5A);
    memcpy(bytes, "ab\0cd", 5);
    CHECK(bytes[0] == 'a' && bytes[1] == 'b' && bytes[2] == '\0');
    }
    return 0;
}
