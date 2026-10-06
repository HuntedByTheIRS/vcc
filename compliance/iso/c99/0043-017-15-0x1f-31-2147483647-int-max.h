/* 0043: CHECK(017 == 15 && 0x1F == 31 && 2147483647 == INT_MAX);
 *
 * monolithic.c:302 (lexical)
 */

#include <stdio.h>
#include <limits.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(017 == 15 && 0x1F == 31 && 2147483647 == INT_MAX);
    return 0;
}
