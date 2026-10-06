/* 282: CHECK(c99_apply(c99_mul, 3, 4) == 12);
 *
 * monolithic.c:10408 (functions)
 */

#include <stdio.h>

static int c99_add(int x, int y) { return x + y; }

static int c99_mul(int x, int y) { return x * y; }

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
    CHECK(c99_apply(c99_mul, 3, 4) == 12);
    return 0;
}
