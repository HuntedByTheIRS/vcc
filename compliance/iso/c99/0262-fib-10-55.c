/* 0262: CHECK(c99_fib(10) == 55);
 *
 * monolithic.c:10378 (functions)
 */

#include <stdio.h>

static int c99_fib(int n)                        /* two recursive calls */
{
    return n < 2 ? n : c99_fib(n - 1) + c99_fib(n - 2);
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
    CHECK(c99_fib(10) == 55);
    return 0;
}
