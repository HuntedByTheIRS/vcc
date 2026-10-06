/* 464: CHECK(strcmp(copy, "hello") == 0 && copy[5] == '\0');
 *
 * monolithic.c:11047 (strings)
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
    char copy[64];
    strcpy(copy, "hello");
    CHECK(strcmp(copy, "hello") == 0 && copy[5] == '\0');
    return 0;
}
