/* 476: CHECK(strchr("hello", 'l') != NULL && *(strchr("hello", 'l')) == 'l');
 *
 * monolithic.c:11080 (strings)
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
    CHECK(strchr("hello", 'l') != NULL && *(strchr("hello", 'l')) == 'l');
    return 0;
}
