/* 263: CHECK(c99_is_even(10) == 1 && c99_is_odd(10) == 0);
 *
 * monolithic.c:10379 (functions)
 */

#include <stdio.h>

static int c99_is_even(unsigned n);

static int c99_is_odd(unsigned n)
{
    return n == 0 ? 0 : c99_is_even(n - 1);
}

static int c99_is_even(unsigned n)
{
    return n == 0 ? 1 : c99_is_odd(n - 1);
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
    CHECK(c99_is_even(10) == 1 && c99_is_odd(10) == 0);
    return 0;
}
