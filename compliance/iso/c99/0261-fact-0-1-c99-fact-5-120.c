/* 0261: CHECK(c99_fact(0) == 1 && c99_fact(5) == 120);
 *
 * monolithic.c:10377 (functions)
 */

#include <stdio.h>

static int c99_fact(int n)                       /* recursion */
{
    return n <= 1 ? 1 : n * c99_fact(n - 1);
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
    CHECK(c99_fact(0) == 1 && c99_fact(5) == 120);
    return 0;
}
