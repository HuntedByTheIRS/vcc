/* 0929: CHECK(__LINE__ == 7);
 *
 * monolithic.c:12331 (line)
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
    #line 7
    CHECK(__LINE__ == 7);
    return 0;
}
