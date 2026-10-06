/* 0284: CHECK(c99_inline_local(1) == 2);
 *
 * monolithic.c:10410 (functions)
 */

#include <stdio.h>

static inline int c99_inline_local(int x)
{
    return x + 1;
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
    CHECK(c99_inline_local(1) == 2);
    return 0;
}
