/* 0048: CHECK(C99_LIMIT_MACRO_0000 == 0);
 *
 * monolithic.c:9550 (limits)
 */

#include <stdio.h>

#define C99_LIMIT_MACRO_0000 0

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_LIMIT_MACRO_0000 == 0);
    return 0;
}
