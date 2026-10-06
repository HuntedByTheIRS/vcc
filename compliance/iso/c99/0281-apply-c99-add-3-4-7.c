/* 0281: CHECK(c99_apply(c99_add, 3, 4) == 7);
 *
 * monolithic.c:10407 (functions)
 */

#include <stdio.h>

static int c99_add(int x, int y) { return x + y; }

static int c99_apply(int (*fn)(int, int), int a, int b)
{
    return fn(a, b);
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
    CHECK(c99_apply(c99_add, 3, 4) == 7);
    return 0;
}
