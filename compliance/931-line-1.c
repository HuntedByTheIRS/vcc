/* 931: CHECK(__LINE__ == 1);
 *
 * monolithic.c:12334 (line)
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
    #line 1 "monolithic.c"
    CHECK(__LINE__ == 1);
    return 0;
}
