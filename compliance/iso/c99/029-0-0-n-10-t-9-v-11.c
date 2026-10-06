/* 029: CHECK('\0' == 0 && '\n' == 10 && '\t' == 9 && '\v' == 11);
 *
 * monolithic.c:287 (lexical)
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK('\0' == 0 && '\n' == 10 && '\t' == 9 && '\v' == 11);
    return 0;
}
