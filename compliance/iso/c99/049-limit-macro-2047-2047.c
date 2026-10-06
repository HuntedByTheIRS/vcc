/* 049: CHECK(C99_LIMIT_MACRO_2047 == 2047);
 *
 * monolithic.c:9551 (limits)
 */

#include <stdio.h>

#define C99_LIMIT_MACRO_2047 2047

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_LIMIT_MACRO_2047 == 2047);
    return 0;
}
