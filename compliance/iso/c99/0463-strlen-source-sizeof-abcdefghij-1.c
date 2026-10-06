/* 0463: CHECK(strlen(source) == sizeof "abcdefghij" - 1);
 *
 * monolithic.c:11044 (strings)
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
    const char *source = "abcdefghij";
    CHECK(strlen("") == 0 && strlen("abc") == 3 && strlen(source) == 10);
    CHECK(strlen(source) == sizeof "abcdefghij" - 1);
    return 0;
}
