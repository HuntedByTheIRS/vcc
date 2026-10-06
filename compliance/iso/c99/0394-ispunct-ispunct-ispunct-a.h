/* 0394: CHECK(ispunct('.') && ispunct(',') && !ispunct('a'));
 *
 * monolithic.c:10864 (characters)
 */

#include <stdio.h>
#include <ctype.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(ispunct('.') && ispunct(',') && !ispunct('a'));
    return 0;
}
