/* 0632: CHECK(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2);
 *
 * monolithic.c:11437 (stdio)
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
    CHECK(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2);
    return 0;
}
