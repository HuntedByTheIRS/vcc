/* 0480: CHECK(strstr("hello", "xyz") == NULL && strstr("", "") != NULL);
 *
 * monolithic.c:11084 (strings)
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
    CHECK(strstr("hello world", "world") != NULL);
    CHECK(strstr("hello", "xyz") == NULL && strstr("", "") != NULL);
    return 0;
}
