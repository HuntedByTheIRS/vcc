/* 0283: CHECK(c99_return_from_block(3) == 6 && c99_return_from_block(0) == 0);
 *
 * monolithic.c:10409 (functions)
 */

#include <stdio.h>

static int c99_return_from_block(int n)
{
    if (n > 0) {
        {
            return n * 2;
        }
    }
    return 0;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_return_from_block(3) == 6 && c99_return_from_block(0) == 0);
    return 0;
}
