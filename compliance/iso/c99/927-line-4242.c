/* 927: CHECK(__LINE__ == 4242);
 *
 * monolithic.c:12328 (line)
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
    #line 4242 "c99-line-directive.h"
    CHECK(__LINE__ == 4242);
    return 0;
}
